import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/widgets/app_scrollbar.dart';
import 'package:hermes_ui/app/widgets/reading_width_box.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 批次 1（G1–G4 横切件）「真渲染目检图」工装（**非金照基线，不参与 CI 比对**）
//
// 用法：BATCH1_SHOTS=1 C:/tmp/f.bat test
//         test/screenshots/batch1_shots_test.dart --update-goldens
// 产物：.shots/*.png（本地工件目录，已被 .gitignore 排除）
//
// 目的：文本断言抓不到视觉问题 —— 28 圆底位置对不对、会不会压到文字、滚动条
// 看不看得见又不脏、暗色发不发黑，都必须出真图人工逐张核对。
// ---------------------------------------------------------------------------

final bool _capture = Platform.environment['BATCH1_SHOTS'] == '1';
const String _skipReason = '设置 BATCH1_SHOTS=1 才生成批次 1 目检图';

class _FixedTasksController extends TasksController {
  @override
  Future<TasksState> build() async {
    ref.watch(tasksApiFactoryProvider);
    return const TasksState(
      jobs: <CronJob>[CronJob(jobId: 'a', name: '每日备份')],
    );
  }
}

class _EmptyProjectsController extends ProjectsController {
  @override
  Future<List<ProjectSummary>> build() async => const [];
}

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

ProviderContainer _container() {
  final api = FakeSessionListApi(
    sessions: const [
      SessionSummary(
        sessionId: 'alpha',
        title: '产品发布计划：多平台统一路线图',
        workspace: '/demo/hermes',
        messageCount: 12,
      ),
      SessionSummary(
        sessionId: 'beta',
        title: '帮我写一段 Python 数据清洗脚本',
        workspace: '/demo/hermes',
        messageCount: 7,
      ),
      SessionSummary(
        sessionId: 'gamma',
        title: '重构引导页的分段控件',
        workspace: '/demo/hermes',
        messageCount: 3,
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectsProvider.overrideWith(_EmptyProjectsController.new),
      tasksControllerProvider.overrideWith(_FixedTasksController.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<TestGesture> _hover(WidgetTester tester, Offset target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(target);
  await tester.pump();
  return gesture;
}

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Directory('.shots').createSync(recursive: true);
  });

  /// 宽屏侧栏（320pt @2x）：hover 前 / hover 后各一张。
  Future<void> captureSidebar(
    WidgetTester tester, {
    required Brightness brightness,
    required String name,
    required bool hover,
  }) async {
    // 逻辑 1280×900（≥900 才走宽屏分支）@2x。
    tester.view.physicalSize = const Size(2560.0, 1800.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(),
        child: CupertinoApp(
          locale: const Locale('zh'),
          localizationsDelegates: _delegates,
          supportedLocales: const [Locale('zh'), Locale('en')],
          theme: buildCupertinoTheme(brightness),
          home: CupertinoPageScaffold(
            child: Row(
              children: [
                const SizedBox(
                  width: 320.0,
                  child: SessionSidebar(currentLocation: '/'),
                ),
                Expanded(
                  child: ColoredBox(
                    color: brightness == Brightness.light
                        ? LightSurfaces.page
                        : CupertinoColors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (hover) {
      // 顶部工具行「定时任务」（未选中）：整行悬停 → 图标后 28 圆底。
      await _hover(
        tester,
        tester.getCenter(find.byKey(const ValueKey('sidebar-tool-tasks'))),
      );
    }

    await expectLater(
      find.byType(SessionSidebar),
      matchesGoldenFile('../../.shots/$name.png'),
    );

    await unmountHermesPage(tester);
  }

  /// 宽屏滚动条（常显 6px 圆头 @2x）：常态 / 滑块悬停 / 暗色对照。
  Future<void> captureScrollbar(
    WidgetTester tester, {
    required Brightness brightness,
    required String name,
    bool hoverThumb = false,
  }) async {
    // 注意 dpr=2 ⇒ 物理尺寸必须是逻辑的两倍，否则逻辑宽会掉到 900 以下走窄屏
    // 分支（本组件在窄屏是透传，出的图就完全看不到滚动条了）。
    tester.view.physicalSize = const Size(2560.0, 1680.0); // 逻辑 1280×840
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final controller = ScrollController();
    addTearDown(controller.dispose);

    // 工装明暗各自的正文色/行底色（`inherit: false` 的样式不带颜色会落成白字，
    // 白底上直接看不见 —— 实测踩过）。
    final labelColor = brightness == Brightness.light
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);
    final rowColor = brightness == Brightness.light
        ? LightSurfaces.card
        : const Color(0xFF1C1C1E);

    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: CupertinoPageScaffold(
          child: Center(
            child: SizedBox(
              width: 560.0,
              height: 380.0,
              child: AppScrollbar(
                controller: controller,
                child: ListView.builder(
                  controller: controller,
                  itemCount: 20,
                  itemBuilder: (context, index) => Container(
                    height: 44.0,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14.0),
                    decoration: BoxDecoration(
                      color: rowColor,
                      border: Border(
                        bottom: BorderSide(
                          color: brightness == Brightness.light
                              ? LightSurfaces.divider
                              : CupertinoColors.separator,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Text(
                      '第 ${index + 1} 行内容 · 常显细滚动条目检',
                      key: ValueKey('sb-row-$index'),
                      style: TextStyle(
                        fontSize: 13.0,
                        inherit: false,
                        fontFamily: kAppFontFamily,
                        color: labelColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (hoverThumb) {
      final rect = tester.getRect(find.byType(AppScrollbar));
      await _hover(tester, Offset(rect.right - 3.0, rect.top + 30.0));
    }

    await expectLater(
      find.byType(AppScrollbar),
      matchesGoldenFile('../../.shots/$name.png'),
    );

    await unmountHermesPage(tester);
  }

  /// G1 限宽：宽屏居中（左）+ 窄屏逐像素不变（右）对照。
  Future<void> captureReadingBox(
    WidgetTester tester, {
    required double width,
    required String name,
  }) async {
    tester.view.physicalSize = Size(width * 2, 700.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        home: CupertinoPageScaffold(
          child: ReadingWidthBox(
            key: const ValueKey('rwb'),
            child: ListView(
              children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    key: ValueKey('rwb-row-$i'),
                    height: 56.0,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    decoration: BoxDecoration(
                      color: LightSurfaces.card,
                      border: Border(
                        bottom: BorderSide(
                          color: LightSurfaces.divider,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Text(
                      '阅读型内容第 ${i + 1} 行（限宽 760 居中）',
                      style: const TextStyle(
                        fontSize: 14.0,
                        inherit: false,
                        fontFamily: kAppFontFamily,
                        // 同上：不带 color 会落成白字，白卡上完全看不见。
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('rwb')),
      matchesGoldenFile('../../.shots/$name.png'),
    );

    await unmountHermesPage(tester);
  }

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);

  testWidgets('宽屏浅色 · 侧栏悬停前', (tester) async {
    await captureSidebar(
      tester,
      brightness: Brightness.light,
      name: 'batch1_sidebar_light_idle',
      hover: false,
    );
  }, skip: !_capture);

  testWidgets('宽屏浅色 · 侧栏悬停后（28 圆底）', (tester) async {
    await captureSidebar(
      tester,
      brightness: Brightness.light,
      name: 'batch1_sidebar_light_hover',
      hover: true,
    );
  }, skip: !_capture);

  testWidgets('宽屏暗色 · 侧栏悬停前', (tester) async {
    await captureSidebar(
      tester,
      brightness: Brightness.dark,
      name: 'batch1_sidebar_dark_idle',
      hover: false,
    );
  }, skip: !_capture);

  testWidgets('宽屏暗色 · 侧栏悬停后（28 圆底）', (tester) async {
    await captureSidebar(
      tester,
      brightness: Brightness.dark,
      name: 'batch1_sidebar_dark_hover',
      hover: true,
    );
  }, skip: !_capture);

  testWidgets('宽屏浅色 · 滚动条常显', (tester) async {
    await captureScrollbar(
      tester,
      brightness: Brightness.light,
      name: 'batch1_scrollbar_light_idle',
    );
  }, skip: !_capture);

  testWidgets('宽屏浅色 · 滚动条滑块悬停加深', (tester) async {
    await captureScrollbar(
      tester,
      brightness: Brightness.light,
      name: 'batch1_scrollbar_light_hover',
      hoverThumb: true,
    );
  }, skip: !_capture);

  testWidgets('宽屏暗色 · 滚动条常显', (tester) async {
    await captureScrollbar(
      tester,
      brightness: Brightness.dark,
      name: 'batch1_scrollbar_dark_idle',
    );
  }, skip: !_capture);

  testWidgets('宽屏暗色 · 滚动条滑块悬停加深', (tester) async {
    await captureScrollbar(
      tester,
      brightness: Brightness.dark,
      name: 'batch1_scrollbar_dark_hover',
      hoverThumb: true,
    );
  }, skip: !_capture);

  testWidgets('宽屏浅色 · 阅读型限宽居中', (tester) async {
    await captureReadingBox(tester, width: 1280.0, name: 'batch1_reading_wide');
  }, skip: !_capture);

  testWidgets('窄屏浅色 · 阅读型容器透传（应与普通单列一致）', (tester) async {
    await captureReadingBox(tester, width: 390.0, name: 'batch1_reading_narrow');
  }, skip: !_capture);
}
