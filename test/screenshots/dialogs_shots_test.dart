import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/selection_provider.dart';
import 'package:hermes_ui/features/chat/widgets/selection_chips.dart';
import 'package:hermes_ui/features/downloads/download_confirm_dialog.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_session_list_api.dart';
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
//   3. 批 5 · C2 三处 session / chat 系迁移（380 批量归档 / 760 导出长文预览 /
//      560 选区重命名）—— 只走真实页面与真实面板入口；宽窄两档都出图，
//      窄屏图是「逐像素不变」的迁移前后对照。
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

// ---------------------------------------------------------------------------
// 批 5 · C2（session / chat 系弹窗迁移到四档宽）的真实调用点宿主
// ---------------------------------------------------------------------------

/// 导出链路走 `apiClientProvider`（不是 fake session api）：dio mock 给长正文，
/// 让「导出成功 = 长文本预览 = 760 宽表单档」这一档有真内容可看。
class _ExportMockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '# Hermes 会话导出\n'
    '\n'
    '- 第一条消息：批 5 · C2 弹窗调用点迁移\n'
    '- 第二条消息：宽屏 760 长文预览应完整可见\n'
    '- 第三条消息：窄屏仍走系统弹窗，逐像素不变\n'
    '\n'
    '## 说明\n'
    '导出正文是长文本，宽屏档位取 wideForm（760）；窄屏仍由系统弹窗承载。\n',
    200,
  );

  @override
  void close({bool force = false}) {}
}

ApiClient _exportClient() {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  )..httpClientAdapter = _ExportMockAdapter();
  final publicDio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  )..httpClientAdapter = _ExportMockAdapter();
  return ApiClient(
    baseUrl: 'https://hermes.example.com:8787',
    dio: dio,
    publicMediaDio: publicDio,
  );
}

class _ShotsProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

/// 会话列表页宿主所需的注入（真页面 + 演示会话）。
List<Override> _sessionListShotsOverrides() => <Override>[
  sessionListApiFactoryProvider.overrideWithValue(
    (_) => FakeSessionListApi(
      sessions: <SessionSummary>[
        SessionSummary(
          sessionId: 's1',
          title: '批 5 · C2 弹窗迁移',
          messageCount: 12,
          lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
        ),
      ],
    ),
  ),
  projectApiFactoryProvider.overrideWithValue((_) => _ShotsProjectApi()),
];

/// 选区条宿主：真实 `SelectionChipPanel` + 一条真实待发选区（工装数据）。
class _SelectionRenameShotsHost extends StatelessWidget {
  const _SelectionRenameShotsHost();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: CupertinoColors.systemGroupedBackground,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: SelectionChipPanel(sessionId: 's1'),
    ),
  );
}

/// 选区条演示数据的注入：`pendingSelectionsProvider` 是 family，覆写时要现造再喂。
Override _selectionShotsOverride() => pendingSelectionsProvider.overrideWith(
  (ref, sessionId) => SelectionNotifier()..add('被选中的正文片段（用于重命名目检）'),
);

/// 结算固定帧数（**不用 `pumpAndSettle`**：宽屏行操作菜单/SSE 心跳有常驻定时器，
/// `pumpAndSettle` 会挂到超时）。
Future<void> _settleFrames(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

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
    ApiClient? apiClient,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            apiClient ?? ApiClient(baseUrl: 'https://hermes.example.com:8787'),
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

  // -------------------------------------------------------------------------
  // 4. 批 5 · C2 —— session / chat 系弹窗迁移到四档宽（真实调用点）
  //
  //    三处，覆盖本批用到的三档：380（确认）/ 560（表单）/ 760（宽表单）。
  //    宽屏与窄屏都出图：宽屏看「档位形态」，窄屏是「逐像素不变」的对照图
  //    （同一份工装在迁移前后各跑一次，窄屏图应逐字节相同）。
  // -------------------------------------------------------------------------

  /// 会话列表 · 批量归档确认框（380 确认档）。
  Future<void> batchArchiveShot(
    WidgetTester tester,
    Brightness brightness, {
    required bool narrow,
  }) => capture(
    tester,
    name: narrow
        ? 'dialog-session-batch-archive-narrow'
        : 'dialog-session-batch-archive',
    home: const SessionListPage(),
    brightness: brightness,
    size: narrow ? _narrowSize : _wideSize,
    overrides: _sessionListShotsOverrides(),
    interact: (tester) async {
      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await _settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey('batch-archive')));
      await _settleFrames(tester);
    },
  );

  /// 会话列表 · 导出成功（760 宽表单档 · 长文本预览）。
  Future<void> exportWideFormShot(
    WidgetTester tester,
    Brightness brightness, {
    required bool narrow,
  }) => capture(
    tester,
    name: narrow
        ? 'dialog-session-export-wide-form-narrow'
        : 'dialog-session-export-wide-form',
    home: const SessionListPage(),
    brightness: brightness,
    size: narrow ? _narrowSize : _wideSize,
    apiClient: _exportClient(),
    overrides: _sessionListShotsOverrides(),
    interact: (tester) async {
      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await _settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await _settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey('session-export-markdown')));
      await _settleFrames(tester, 10);
    },
  );

  /// 选区条 · 重命名（560 表单档 · 含输入框）。
  Future<void> selectionRenameShot(
    WidgetTester tester,
    Brightness brightness, {
    required bool narrow,
  }) => capture(
    tester,
    name: narrow ? 'dialog-selection-rename-narrow' : 'dialog-selection-rename',
    home: const _SelectionRenameShotsHost(),
    brightness: brightness,
    size: narrow ? _narrowSize : _wideSize,
    overrides: [_selectionShotsOverride()],
    interact: (tester) async {
      await tester.tap(find.byKey(const ValueKey('selection-rename-ctx-1')));
      await _settleFrames(tester);
    },
  );

  shotPair('弹窗 · 会话批量归档确认框（380）', (tester, brightness) async {
    await batchArchiveShot(tester, brightness, narrow: false);
  });

  shotPair('弹窗 · 导出成功长文预览（760 宽表单档）', (tester, brightness) async {
    await exportWideFormShot(tester, brightness, narrow: false);
  });

  shotPair('弹窗 · 选区重命名（560 表单档）', (tester, brightness) async {
    await selectionRenameShot(tester, brightness, narrow: false);
  });

  narrowShotPair('弹窗 · 会话批量归档确认框（窄屏）', (tester, brightness) async {
    await batchArchiveShot(tester, brightness, narrow: true);
  });

  narrowShotPair('弹窗 · 导出成功长文预览（窄屏）', (tester, brightness) async {
    await exportWideFormShot(tester, brightness, narrow: true);
  });

  narrowShotPair('弹窗 · 选区重命名（窄屏）', (tester, brightness) async {
    await selectionRenameShot(tester, brightness, narrow: true);
  });
}
