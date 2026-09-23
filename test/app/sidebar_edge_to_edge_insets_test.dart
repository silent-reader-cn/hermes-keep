import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/shell/sidebar_tools_list.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session_list_api.dart';
import 'package:hermes_ui/app/shell/sidebar_brand_bar.dart';

/// todo #16：Android 15+ 强制 edge-to-edge 下，宽屏侧栏顶部 inset 处理。
///
/// 方案 A：`SessionSidebar` 外层包 `SafeArea(bottom: false)` —— 顶部 inset
/// 一次吸收（现象①工具条不再被状态栏盖住）；SafeArea 的
/// `MediaQuery.removePadding(top)` 使子树 header 读到的 `paddingOf(context).top`
/// 归零（现象②工具条/搜索栏之间不再有状态栏高度空白带）。
/// 通过 `tester.view.padding` 注入真实设备语义的顶部 inset，走完整
/// AdaptiveShell + GoRouter 生产路径断言几何。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    enableSessionAutoRefresh = false;
  });
  tearDown(() {
    enableSessionAutoRefresh = true;
  });

  const List<LocalizationsDelegate<dynamic>> testDelegates = [
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  Widget buildShellTestApp({
    required String initialLocation,
    required Size size,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const SessionListPage(),
            ),
            GoRoute(
              path: '/tasks',
              builder: (context, state) =>
                  const Text('Tasks Content', key: ValueKey('tasks-child')),
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => FakeSessionListApi(),
        ),
      ],
      child: MediaQuery(
        // 注：本 Flutter 版本 WidgetsApp 内层 MediaQuery 与外层 data 合并、
        // 外层为权威（实测 view.padding 会被外层 data 的默认 0 覆盖），
        // 因此在此处直接注入 MediaQuery.padding(top: X) 模拟设备状态栏 inset。
        data: MediaQueryData(size: size, padding: padding),
        child: CupertinoApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: testDelegates,
        ),
      ),
    );
  }

  group('SessionSidebar edge-to-edge inset（todo #16 方案 A）', () {
    testWidgets('宽屏注入 MediaQuery.padding(top: 48)：侧栏外层 SafeArea 吸收顶部 inset，header 不再叠加 topPadding', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/',
          size: const Size(1280, 800),
          padding: const EdgeInsets.only(top: 48),
        ),
      );
      await tester.pumpAndSettle();

      // 现象①：侧栏外层 SafeArea 存在且不吸收底部（方案 A 规格）。
      final safeArea = tester.widget<SafeArea>(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
      );
      expect(safeArea.bottom, isFalse);

      // 现象①：侧栏最顶的品牌行整体下移一个状态栏高（顶部恰在状态栏下沿），不再被盖。
      final brandTop = tester
          .getTopLeft(find.byType(SidebarBrandBar))
          .dy;
      expect(brandTop, moreOrLessEquals(48.0, epsilon: 0.001));

      // #150：侧栏场景（宽屏 + showUtilityRows=false）下，列表头部已被移除 ——
      // 它的四个 action 渲染条件（筛选/设置/新建/刷新）在侧栏全不成立，只剩
      // 一个 50px 的空架子（表现为「工具列表下方一大块空白」），故整块不渲染。
      // ⇒ 此处断言「不存在」；topPadding 归零的验证由窄屏用例承担（那里 header 仍在）。
      expect(find.byType(SliverPersistentHeader), findsNothing);
      expect(
        find.byKey(const ValueKey('session-list-header')),
        findsNothing,
      );

      // 顶部对齐：侧栏自上而下 = 品牌行 → 常用功能列表 → 会话列表，
      // 且品牌行整体吸收了 SafeArea 的顶部 inset（48）。断言相对关系，不写死绝对值。
      final absorbedBrandTop = tester
          .getTopLeft(find.byType(SidebarBrandBar))
          .dy;
      final absorbedToolsTop = tester
          .getTopLeft(find.byType(SidebarToolsList))
          .dy;
      final absorbedToolsBottom = tester
          .getBottomLeft(find.byType(SidebarToolsList))
          .dy;
      expect(absorbedBrandTop, moreOrLessEquals(48, epsilon: 0.5));
      expect(
        absorbedToolsTop,
        moreOrLessEquals(absorbedBrandTop + 40.5, epsilon: 0.5),
      );
      expect(absorbedToolsBottom, greaterThan(absorbedToolsTop));
    });

    testWidgets('宽屏 padding == 0（默认视口语义）：SafeArea 空转，工具条顶零，零回归', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildShellTestApp(initialLocation: '/', size: const Size(1280, 800)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
        findsOneWidget,
      );
      final brandTop = tester
          .getTopLeft(find.byType(SidebarBrandBar))
          .dy;
      expect(brandTop, moreOrLessEquals(0.0, epsilon: 0.001));
    });

    testWidgets('窄屏（800 < 900）注入 padding(top: 48)：不渲染侧栏，child 直接展示，布局零变化', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/tasks',
          size: const Size(800, 600),
          padding: const EdgeInsets.only(top: 48),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tasks-child')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
        findsNothing,
      );
      expect(find.byType(SidebarBrandBar), findsNothing);
    });
  });
}