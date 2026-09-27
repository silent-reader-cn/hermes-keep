import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// L2 选中态「真渲染目检图」工装（**非金照基线，不参与 CI 比对**）
//
// 用法：SELECTION_SHOTS=1 C:/tmp/f.bat test
//         test/screenshots/selection_l2_shots_test.dart --update-goldens
// 产物：.shots/*.png（本地工件目录，已被 .gitignore 排除）
//
// 目的：文本断言抓不到视觉问题（灰底在白卡/侧栏底上立不立得住、内描边是否
// 可见而不突兀、选中与 hover 是否一眼可分），故必须出真图人工核对。
// 三态同框：alpha = 当前会话（内描边 + 2px 蓝条）、beta = 选中（蓝字）、
// gamma = 鼠标悬停（淡灰底、前景不变）；侧栏工具行（定时任务）同时是选中态。
// ---------------------------------------------------------------------------

final bool _capture = Platform.environment['SELECTION_SHOTS'] == '1';
const String _skipReason = '设置 SELECTION_SHOTS=1 才生成 L2 选中态目检图';

class _EmptyProjectsController extends ProjectsController {
  @override
  Future<List<ProjectSummary>> build() async => const [];
}

const String _tAlpha = '产品发布计划：多平台统一路线图';
const String _tBeta = '帮我写一段 Python 数据清洗脚本';
const String _tGamma = '重构引导页的分段控件';

ProviderContainer _container() {
  final api = FakeSessionListApi(
    sessions: const [
      SessionSummary(
        sessionId: 'alpha',
        title: _tAlpha,
        workspace: '/demo/hermes',
        messageCount: 12,
      ),
      SessionSummary(
        sessionId: 'beta',
        title: _tBeta,
        workspace: '/demo/hermes',
        messageCount: 7,
      ),
      SessionSummary(
        sessionId: 'gamma',
        title: _tGamma,
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
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump();
  return gesture;
}

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Directory('.shots').createSync(recursive: true);
  });

  /// 宽屏侧栏（320pt @2x）：三态同框 + 工具行选中态（currentLocation=/tasks）。
  Future<void> captureSidebar(
    WidgetTester tester, {
    required Brightness brightness,
    required String name,
  }) async {
    // 逻辑 1280×900（≥900 才进宽屏紧凑行）@2x。
    tester.view.physicalSize = const Size(2560.0, 1800.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final container = _container();
    container.read(activeChatSessionIdProvider.notifier).state = 'alpha';
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          theme: buildCupertinoTheme(brightness),
          home: CupertinoPageScaffold(
            child: Row(
              children: [
                const SizedBox(
                  width: 320.0,
                  child: SessionSidebar(currentLocation: '/tasks'),
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

    // 选中（beta）：控制器进入多选模式 ⇒ 侧栏紧凑行同享高亮。
    container.read(sessionListControllerProvider.notifier).toggleSelection('beta');
    await tester.pump();
    // 悬停（gamma）：鼠标停在第三行上。
    await _hover(tester, find.byKey(const ValueKey('session-row-gamma')));

    await expectLater(
      find.byType(SessionSidebar),
      matchesGoldenFile('../../.shots/$name.png'),
    );

    await unmountHermesPage(tester);
  }

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);

  testWidgets('宽屏浅色 · 三态同框 + 工具行选中', (tester) async {
    await captureSidebar(
      tester,
      brightness: Brightness.light,
      name: 'wide_light_sidebar',
    );
  }, skip: !_capture);

  testWidgets('宽屏暗色 · 对照（应仍为 primary 12% + 蓝字，无内描边）', (tester) async {
    await captureSidebar(
      tester,
      brightness: Brightness.dark,
      name: 'wide_dark_sidebar',
    );
  }, skip: !_capture);

  /// 窄屏单栈（780×1688 @2x，同 README 截图档）：证明窄屏不受影响。
  Future<void> captureNarrow(
    WidgetTester tester, {
    required Brightness brightness,
    required String name,
  }) async {
    tester.view.physicalSize = goldenSurfaceSize;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final container = _container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          theme: buildCupertinoTheme(brightness),
          home: const SessionListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 窄屏长按 = 多选（既有语义），故「选中行」在窄屏是旧浅蓝底。
    await tester.longPress(find.text(_tAlpha));
    await tester.pump();

    await expectLater(
      find.byType(SessionListPage),
      matchesGoldenFile('../../.shots/$name.png'),
    );

    await unmountHermesPage(tester);
  }

  testWidgets('窄屏浅色 · 选中仍是旧浅蓝（逐像素不变）', (tester) async {
    await captureNarrow(
      tester,
      brightness: Brightness.light,
      name: 'narrow_light_selected',
    );
  }, skip: !_capture);

  testWidgets('窄屏暗色 · 对照', (tester) async {
    await captureNarrow(
      tester,
      brightness: Brightness.dark,
      name: 'narrow_dark_selected',
    );
  }, skip: !_capture);
}
