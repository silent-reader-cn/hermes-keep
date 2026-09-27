import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/features/workspace/workspace_page.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_download_service.dart';
import '../helpers/fake_tasks_api.dart';
import '../helpers/fake_workspace_api.dart';

// ---------------------------------------------------------------------------
// 批 5 · C3「其余 feature 弹窗调用点迁移」真渲染目检工装
// （**非金照基线，不参与 CI**：不带环境变量时全部 skip）
//
// 用法（同一份工装，落码前/后各跑一次 → 图可直接对照）：
//   C3_SHOTS=1 C3_SHOTS_TAG=before C:/tmp/f.bat test \
//       test/screenshots/c3_dialogs_shots_test.dart --update-goldens
//   C3_SHOTS=1 C3_SHOTS_TAG=after  C:/tmp/f.bat test \
//       test/screenshots/c3_dialogs_shots_test.dart --update-goldens
//
// 产物：`.shots/c3/<tag>/<name>-<light|dark>.png`
//   - `*-wide.png`   逻辑 1280×800 @2x（≥900 → 宽屏卡片形态）
//   - `*-narrow.png` 逻辑 800×600 @2x（<900 → 系统 alert 形态）
//
// 覆盖三个**真实调用点**（全部经页面 UI 触发，不构造测试专用弹窗）：
//   1. `tasks-page-delete-confirm`  —— 定时任务页 → 行菜单 → 删除（D1 `confirm` 380）
//   2. `tasks-action-error`         —— 定时任务页 → 行菜单 → 运行（失败告警 380）
//   3. `workspace-rename`           —— 工作区页 → 行菜单 → 重命名（D1 `form` 560，含输入框）
//   4. `workspace-delete`           —— 工作区页 → 行菜单 → 删除（380）
//
// 「窄屏逐像素不变」的证据链：before/after 两轮的 `*-narrow.png` 逐字节比对
// 必须为 0 差异（见交付报告）。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip（全量 `flutter test` 零影响）。
final bool _capture = Platform.environment['C3_SHOTS'] == '1';

/// 产物子目录标签（before / after）。
final String _tag = Platform.environment['C3_SHOTS_TAG'] ?? 'after';

const String _shotRoot = '../../.shots/c3';

/// 宽屏截图物理像素（逻辑 1280×800 @2x；≥ kAdaptiveBreakpoint=900）。
const Size _wideSize = Size(2560, 1600);

/// 窄屏截图物理像素（逻辑 800×600 @2x；< 900 → 单列）。
const Size _narrowSize = Size(1600, 1200);

List<CronJob> _demoJobs() => const <CronJob>[
  CronJob(
    jobId: 'j1',
    name: 'Hermes 仓 CI 巡检',
    prompt: '巡检 analyze + 全量测试，失败则汇总失败用例到会话',
    schedule: CronSchedule(expression: '0 9 * * *'),
    enabled: true,
    state: 'completed',
  ),
  CronJob(
    jobId: 'j2',
    name: '用量周报（近 7 天 token / 成本）',
    prompt: '汇总近 7 天 token 与成本，超过 \$20 阈值时标注',
    schedule: CronSchedule(expression: '0 9 * * 1'),
    enabled: true,
    state: 'completed',
  ),
];

List<WorkspaceEntry> _demoEntries() => const <WorkspaceEntry>[
  WorkspaceEntry(name: 'DESIGN.md', path: 'DESIGN.md', size: 18432),
  WorkspaceEntry(name: 'AGENTS.md', path: 'AGENTS.md', size: 9021),
  WorkspaceEntry(name: 'lib', path: 'lib', isDirectory: true),
];

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 挂载页面 → [interact] 触发弹窗 → 结算入场动画 → 截图。
  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Widget home,
    required Brightness brightness,
    required List<Override> overrides,
    required Future<void> Function(WidgetTester tester) interact,
    Size size = _wideSize,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'https://hermes.example.com:8787'),
          ),
          ...overrides,
        ],
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(brightness),
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await interact(tester);
    // 行菜单 / 弹窗入场（Cupertino 弹簧 ≈250ms）结算后再截。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    Directory('$_shotRoot/$_tag').createSync(recursive: true);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile(
        '$_shotRoot/$_tag/$name-${brightness == Brightness.dark ? 'dark' : 'light'}.png',
      ),
    );

    await unmountHermesPage(tester);
  }

  /// 行菜单 → 目标动作。
  Future<void> rowAction(
    WidgetTester tester, {
    required Key rowActions,
    required Key action,
  }) async {
    await tester.tap(find.byKey(rowActions));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(action));
    await tester.pumpAndSettle();
  }

  List<Override> tasksOverrides() => <Override>[
    tasksApiFactoryProvider.overrideWithValue(
      (_) => FakeTasksApi(jobs: _demoJobs()),
    ),
  ];

  /// 运行失败 → 告警弹窗：用 `runError` 让行菜单的「运行」落到错误分支。
  List<Override> tasksErrorOverrides() => <Override>[
    tasksApiFactoryProvider.overrideWithValue(
      (_) => FakeTasksApi(jobs: _demoJobs())
        ..runError = HttpException(500, null, message: '触发服务不可用（工装注入）'),
    ),
  ];

  List<Override> workspaceOverrides() => <Override>[
    workspaceApiFactoryProvider.overrideWithValue(
      (_) => FakeWorkspaceApi(
        directories: <String, List<WorkspaceEntry>>{'.': _demoEntries()},
      ),
    ),
    ...createDownloadTestOverrides(),
  ];

  /// 一档视口出浅/暗两张。
  void shotPair(
    String title,
    Size size,
    Future<void> Function(WidgetTester tester, Brightness brightness) body,
  ) {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
      final viewport = size == _wideSize ? '宽屏' : '窄屏';
      testWidgets('$viewport$suffix · $title', (tester) async {
        await body(tester, brightness);
      }, skip: !_capture);
    }
  }

  // 1. 定时任务页 · 删除确认（confirm 380）
  for (final size in <Size>[_wideSize, _narrowSize]) {
    final viewport = size == _wideSize ? 'wide' : 'narrow';
    shotPair('定时任务 · 删除确认（380）', size, (tester, brightness) async {
      await capture(
        tester,
        name: 'tasks-page-delete-confirm-$viewport',
        home: const TasksPage(),
        brightness: brightness,
        overrides: tasksOverrides(),
        size: size,
        interact: (tester) => rowAction(
          tester,
          rowActions: const ValueKey('tasks-actions-j1'),
          action: const ValueKey('tasks-action-delete'),
        ),
      );
    });
  }

  // 2. 定时任务页 · 操作失败告警（380）
  for (final size in <Size>[_wideSize, _narrowSize]) {
    final viewport = size == _wideSize ? 'wide' : 'narrow';
    shotPair('定时任务 · 操作失败告警（380）', size, (tester, brightness) async {
      await capture(
        tester,
        name: 'tasks-action-error-$viewport',
        home: const TasksPage(),
        brightness: brightness,
        overrides: tasksErrorOverrides(),
        size: size,
        interact: (tester) => rowAction(
          tester,
          rowActions: const ValueKey('tasks-actions-j1'),
          action: const ValueKey('tasks-action-run'),
        ),
      );
    });
  }

  // 3. 工作区页 · 重命名（form 560，含输入框）
  for (final size in <Size>[_wideSize, _narrowSize]) {
    final viewport = size == _wideSize ? 'wide' : 'narrow';
    shotPair('工作区 · 重命名（560）', size, (tester, brightness) async {
      await capture(
        tester,
        name: 'workspace-rename-$viewport',
        home: const WorkspacePage(sessionId: 's-demo'),
        brightness: brightness,
        overrides: workspaceOverrides(),
        size: size,
        interact: (tester) => rowAction(
          tester,
          rowActions: const ValueKey('workspace-actions-DESIGN.md'),
          action: const ValueKey('workspace-action-rename'),
        ),
      );
    });
  }

  // 4. 工作区页 · 删除文件（380）
  for (final size in <Size>[_wideSize, _narrowSize]) {
    final viewport = size == _wideSize ? 'wide' : 'narrow';
    shotPair('工作区 · 删除文件（380）', size, (tester, brightness) async {
      await capture(
        tester,
        name: 'workspace-delete-$viewport',
        home: const WorkspacePage(sessionId: 's-demo'),
        brightness: brightness,
        overrides: workspaceOverrides(),
        size: size,
        interact: (tester) => rowAction(
          tester,
          rowActions: const ValueKey('workspace-actions-DESIGN.md'),
          action: const ValueKey('workspace-action-delete'),
        ),
      );
    });
  }
}
