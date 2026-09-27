import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/features/downloads/download_confirm_dialog.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_tasks_api.dart';

// ---------------------------------------------------------------------------
// 批 5A「弹窗基础设施（D1 四档宽 + D2 表单横排）」真渲染目检工装
// （**非金照基线，不参与 CI**）
//
// 用法（改动前后各跑一次，同一份工装 → 图可直接对照）：
//   DIALOG_SHOTS=1 DIALOG_SHOTS_TAG=before C:/tmp/f.bat test \
//       test/screenshots/dialogs_shots_test.dart --update-goldens
//   …落码后把 TAG 换成 after 再跑一次。
//   不带 DIALOG_SHOTS=1 时全部 skip，`flutter test` 全量零影响。
//
// 产物：`.shots/dialogs/<tag>/<name>-<light|dark>.png`（1280×800 逻辑 @2x）
//
// 覆盖两组（各浅/暗）：
//   1. `dialog-download-confirm` —— 走**真实调用点** `showDownloadConfirmationDialog`
//      （D1 的 380 确认框样板）。
//   2. `dialog-tasks-form` —— 走**真实调用点** `TasksPage` 工具条「+」按钮
//      （D2 的 560 表单 + 左 label 88 横排样板）。
//
// 工装刻意只渲染「真实组件」：真人真字体（[loadHermesGoldenFonts]）、真主题
// （[buildCupertinoTheme]）、真中文本地化；**不注入任何测试专用 UI**。
// 背景宿主只用真实产品页（`TasksPage`）或最小启动页 —— 弹窗才是被检对象。
//
// 与产品代码的关系：不修改任何 `lib/` 代码，只注入 fake API + 演示数据。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip。
final bool _capture = Platform.environment['DIALOG_SHOTS'] == '1';

/// 产物子目录标签（before / after），默认 after。
final String _tag = Platform.environment['DIALOG_SHOTS_TAG'] ?? 'after';

const String _shotRoot = '../../.shots/dialogs';

/// 宽屏截图物理像素（逻辑 1280×800 @2x；≥ kAdaptiveBreakpoint=900）。
const Size _wideSize = Size(2560, 1600);

/// 窄屏截图物理像素（逻辑 800×600 @2x；< 900 → 单列）。
///
/// 存在的唯一理由：把「窄屏逐像素不变」做成**可视证据** —— 同一份工装在落码前
/// （`DIALOG_SHOTS_TAG=before`）与落码后（`after`）各跑一次，两张
/// `*-narrow.png` 逐像素比对应为 0 差异。
const Size _narrowSize = Size(1600, 1200);

/// 演示定时任务（具体内容，无 Item 1 / TODO 这类占位）。
List<CronJob> _demoJobs() => const [
  CronJob(
    jobId: 'job-1',
    name: 'Hermes 仓 CI 巡检',
    prompt: '巡检 analyze + 全量测试，失败则汇总失败用例到会话',
    schedule: CronSchedule(expression: '0 9 * * *'),
    enabled: true,
    state: 'completed',
  ),
  CronJob(
    jobId: 'job-2',
    name: '用量周报（近 7 天 token / 成本）',
    prompt: '汇总近 7 天 token 与成本，超过 \$20 阈值时标注',
    schedule: CronSchedule(expression: '0 9 * * 1'),
    enabled: true,
    state: 'completed',
  ),
  CronJob(
    jobId: 'job-3',
    name: 'worktree 与分支清理',
    prompt: '清理超过 3 天未动的 worktree 与已合并分支',
    schedule: CronSchedule(expression: '0 3 * * *'),
    enabled: false,
    state: 'paused',
  ),
];

/// 下载确认框的启动宿主：真实主题 + 真实背景页，只有一个「触发」按钮
/// （产品里该弹窗由聊天媒体气泡 / 文件预览页触发；此处只取最小触发面，
/// 不复制那两个页面的依赖）。标题与说明如实写明是工装宿主。
class _ConfirmLauncherPage extends StatelessWidget {
  const _ConfirmLauncherPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      backgroundColor: LightSurfaces.resolve(
        context,
        LightSurfaces.page,
        dark: CupertinoColors.systemGroupedBackground,
      ),
      navigationBar: const CupertinoNavigationBar(
        middle: Text('下载确认框 · 宽屏目检宿主'),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '产品里该弹窗由聊天媒体气泡 / 文件预览页触发',
              style: TextStyle(
                fontSize: 13,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              key: const ValueKey('shots-open-confirm'),
              onPressed: () => showDownloadConfirmationDialog(
                context,
                fileName: 'wide-dialogs-menus-decision.html',
                mimeType: 'text/html',
                expectedBytes: 184320,
                sessionId: 's-demo-1',
                modifiedAtSeconds: 1789000000.0,
              ),
              child: Text(l10n.downloadConfirmTitle),
            ),
          ],
        ),
      ),
    );
  }
}

/// 定时任务页的 fake API 注入（宽/窄两组用例共用同一份演示数据）。
Override tasksApiFactoryOverride() => tasksApiFactoryProvider.overrideWithValue(
  (_) => FakeTasksApi(jobs: _demoJobs()),
);

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 挂载 [home]（可注入 overrides）→ 可选 [interact] 触发弹窗 → 截图。
  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Widget home,
    required Brightness brightness,
    List<Override> overrides = const [],
    Future<void> Function(WidgetTester tester)? interact,
    Size size = _wideSize,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'https://hermes.example.com:8787'),
          ),
          ...overrides,
        ],
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(brightness),
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
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

    if (interact != null) {
      await interact(tester);
      // 弹窗入场（Cupertino 弹簧 ≈250ms）结算后再截。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Directory('$_shotRoot/$_tag').createSync(recursive: true);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile(
        '$_shotRoot/$_tag/$name-${brightness == Brightness.dark ? 'dark' : 'light'}.png',
      ),
    );

    await unmountHermesPage(tester);
  }

  /// 窄屏同款两图（`<900` 单列形态）—— 「窄屏逐像素不变」的目检证据。
  void narrowShotPair(
    String title,
    Future<void> Function(WidgetTester tester, Brightness brightness) body,
  ) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
      testWidgets('窄屏$suffix · $title', (tester) async {
        await body(tester, brightness);
      }, skip: !_capture);
    }
  }

  /// 宽屏同款两图（一条用例出两套，避免跑两遍命令）。
  void shotPair(
    String title,
    Future<void> Function(WidgetTester tester, Brightness brightness) body,
  ) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
      testWidgets('宽屏$suffix · $title', (tester) async {
        await body(tester, brightness);
      }, skip: !_capture);
    }
  }

  // -------------------------------------------------------------------------
  // 1. D1 · 下载确认框（380 登录卡）
  // -------------------------------------------------------------------------
  shotPair('弹窗 · 下载确认框（380）', (tester, brightness) async {
    await capture(
      tester,
      name: 'dialog-download-confirm',
      home: const _ConfirmLauncherPage(),
      brightness: brightness,
      interact: (tester) async {
        await tester.tap(find.byKey(const ValueKey('shots-open-confirm')));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 2. D2 · 新建定时任务表单（560 + 左 label 88 横排）
  // -------------------------------------------------------------------------
  shotPair('弹窗 · 新建定时任务表单（560）', (tester, brightness) async {
    await capture(
      tester,
      name: 'dialog-tasks-form',
      home: const TasksPage(),
      brightness: brightness,
      overrides: [
        tasksApiFactoryOverride(),
      ],
      interact: (tester) async {
        await tester.tap(find.byKey(const ValueKey('tasks-create')));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 3. 窄屏对照组（同一份工装、同一份触发路径）—— 逐像素比对的基线/复验图。
  // -------------------------------------------------------------------------
  narrowShotPair('弹窗 · 下载确认框（窄屏）', (tester, brightness) async {
    await capture(
      tester,
      name: 'dialog-download-confirm-narrow',
      home: const _ConfirmLauncherPage(),
      brightness: brightness,
      size: _narrowSize,
      interact: (tester) async {
        await tester.tap(find.byKey(const ValueKey('shots-open-confirm')));
      },
    );
  });

  narrowShotPair('弹窗 · 新建定时任务表单（窄屏）', (tester, brightness) async {
    await capture(
      tester,
      name: 'dialog-tasks-form-narrow',
      home: const TasksPage(),
      brightness: brightness,
      size: _narrowSize,
      overrides: [tasksApiFactoryOverride()],
      interact: (tester) async {
        await tester.tap(find.byKey(const ValueKey('tasks-create')));
      },
    );
  });
}
