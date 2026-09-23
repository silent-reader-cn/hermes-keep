import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/app.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/shell/empty_detail_pane.dart';
import 'package:hermes_ui/app/shell/sidebar_utility_toolbar.dart';
import 'package:hermes_ui/app/shell/sidebar_tools_list.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/onboarding/onboarding_page.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session_list_api.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';
import '../helpers/fake_tasks_api.dart';
import '../helpers/in_memory_secure_storage.dart';

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

  ServerConnection buildConn(String id) {
    return ServerConnection(
      id: id,
      name: 'Home',
      baseUrl: 'http://hermes.local:30002',
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  Widget buildShellTestApp({
    required String initialLocation,
    required Size size,
    FakeSessionListApi? sessionApi,
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
        if (sessionApi != null)
          sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: CupertinoApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: testDelegates,
        ),
      ),
    );
  }

  group('AdaptiveShell Widget 单元与视口测试', () {
    testWidgets('窄视口（390×844）：直接渲染 child，不渲染双栏和侧栏', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/tasks',
          size: const Size(390, 844),
          sessionApi: FakeSessionListApi(),
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
      expect(find.byType(EmptyDetailPane), findsNothing);
    });

    testWidgets('宽视口（1280×800）处于根路径 `/`：渲染双栏，左侧常驻侧栏，右侧 EmptyDetailPane', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/',
          size: const Size(1280, 800),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
        findsOneWidget,
      );
      expect(find.byType(SidebarToolsList), findsOneWidget);
      expect(find.byType(EmptyDetailPane), findsOneWidget);
      expect(find.byType(SessionListPage), findsOneWidget);
    });

    testWidgets('宽视口（1280×800）处于二级子路径 `/tasks`：左侧侧栏可见，右侧展示 child', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/tasks',
          size: const Size(1280, 800),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tasks-child')), findsOneWidget);
      expect(find.byType(EmptyDetailPane), findsNothing);
    });

    testWidgets('断点边界值验证：899 窄屏 vs 900 宽屏', (tester) async {
      tester.view.physicalSize = const Size(899, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 899.0 宽 → 窄屏
      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/tasks',
          size: const Size(899, 600),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsNothing,
      );

      // 900.0 宽 → 宽屏
      tester.view.physicalSize = const Size(900, 600);
      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/tasks',
          size: const Size(900, 600),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsOneWidget,
      );
    });
  });

  group('AdaptiveShell 侧栏拖拽调整宽度与持久化测试', () {
    testWidgets('默认无存储记录时侧栏宽度为 320，渲染拖拽手柄与调整光标', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/',
          size: const Size(1280, 800),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();

      final handleFinder = find.byType(SidebarResizeHandle);
      expect(handleFinder, findsOneWidget);

      final mouseRegion = tester.widget<MouseRegion>(
        find.descendant(of: handleFinder, matching: find.byType(MouseRegion)),
      );
      expect(mouseRegion.cursor, SystemMouseCursors.resizeLeftRight);

      final sidebarBox = tester.widget<SizedBox>(
        find.byKey(const ValueKey('adaptive-shell-sidebar-container')),
      );
      expect(sidebarBox.width, kAdaptiveSidebarDefaultWidth);
    });

    testWidgets('拖拽手柄 +40：侧栏宽度变为 360 且持久化到 SharedPreferences', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/',
          size: const Size(1280, 800),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();

      final handleFinder = find.byKey(
        const ValueKey('adaptive-shell-resize-handle'),
      );
      expect(handleFinder, findsOneWidget);

      // 水平向右拖动 +40 像素
      await tester.drag(handleFinder, const Offset(40, 0));
      await tester.pumpAndSettle();

      final sidebarBox = tester.widget<SizedBox>(
        find.byKey(const ValueKey('adaptive-shell-sidebar-container')),
      );
      expect(sidebarBox.width, 360.0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kAdaptiveSidebarWidthStorageKey), 360.0);
    });

    testWidgets('拖拽边界 clamp 验证：拖动 +500 限制在 420，拖动 -500 限制在 280', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/',
          size: const Size(1280, 800),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();

      final handleFinder = find.byKey(
        const ValueKey('adaptive-shell-resize-handle'),
      );

      // 超出上限拖拽 +500
      await tester.drag(handleFinder, const Offset(500, 0));
      await tester.pumpAndSettle();

      var sidebarBox = tester.widget<SizedBox>(
        find.byKey(const ValueKey('adaptive-shell-sidebar-container')),
      );
      expect(sidebarBox.width, kAdaptiveSidebarMaxWidth);
      var prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble(kAdaptiveSidebarWidthStorageKey),
        kAdaptiveSidebarMaxWidth,
      );

      // 超出下限拖拽 -500
      await tester.drag(handleFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      sidebarBox = tester.widget<SizedBox>(
        find.byKey(const ValueKey('adaptive-shell-sidebar-container')),
      );
      expect(sidebarBox.width, kAdaptiveSidebarMinWidth);
      prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble(kAdaptiveSidebarWidthStorageKey),
        kAdaptiveSidebarMinWidth,
      );
    });

    testWidgets('冷启恢复：SharedPreferences 预置 360 时 pump 后侧栏恢复 360 宽度', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        kAdaptiveSidebarWidthStorageKey: 360.0,
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/',
          size: const Size(1280, 800),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();

      final sidebarBox = tester.widget<SizedBox>(
        find.byKey(const ValueKey('adaptive-shell-sidebar-container')),
      );
      expect(sidebarBox.width, 360.0);
    });

    testWidgets('冷启容错恢复：SharedPreferences 预置异常值时安全 clamp 到有效范围', (
      tester,
    ) async {
      // 预置超大异常值 999
      SharedPreferences.setMockInitialValues({
        kAdaptiveSidebarWidthStorageKey: 999.0,
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/',
          size: const Size(1280, 800),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();

      var sidebarBox = tester.widget<SizedBox>(
        find.byKey(const ValueKey('adaptive-shell-sidebar-container')),
      );
      expect(sidebarBox.width, kAdaptiveSidebarMaxWidth);

      // 预置过小异常值 50
      SharedPreferences.setMockInitialValues({
        kAdaptiveSidebarWidthStorageKey: 50.0,
      });

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/',
          size: const Size(1280, 800),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();

      sidebarBox = tester.widget<SizedBox>(
        find.byKey(const ValueKey('adaptive-shell-sidebar-container')),
      );
      expect(sidebarBox.width, kAdaptiveSidebarMinWidth);
    });

    testWidgets('窄屏视口下不渲染拖拽手柄，保持单栈体验', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildShellTestApp(
          initialLocation: '/tasks',
          size: const Size(390, 844),
          sessionApi: FakeSessionListApi(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SidebarResizeHandle), findsNothing);
      expect(
        find.byKey(const ValueKey('adaptive-shell-resize-handle')),
        findsNothing,
      );
    });
  });

  group('SidebarUtilityToolbar 与 EmptyDetailPane 交互测试', () {
    testWidgets('侧栏工具条包含全部 5 个工具入口且对应 Key 准确', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MediaQuery(
            data: MediaQueryData(size: Size(1280, 800)),
            child: CupertinoApp(
              locale: Locale('zh'),
              supportedLocales: [Locale('zh'), Locale('en')],
              localizationsDelegates: testDelegates,
              home: CupertinoPageScaffold(
                child: SizedBox(
                  width: 320,
                  child: SidebarUtilityToolbar(currentLocation: '/tasks'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sidebar-utility-tasks')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sidebar-utility-kanban')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sidebar-utility-skills')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sidebar-utility-memory')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sidebar-utility-insights')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sidebar-utility-settings')),
        findsOneWidget,
      );
    });

    testWidgets('EmptyDetailPane 展示图标、说明与新建按钮', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionListApiFactoryProvider.overrideWithValue(
              (_) => FakeSessionListApi(),
            ),
          ],
          child: const MediaQuery(
            data: MediaQueryData(size: Size(1280, 800)),
            child: CupertinoApp(
              locale: Locale('zh'),
              supportedLocales: [Locale('zh'), Locale('en')],
              localizationsDelegates: testDelegates,
              home: EmptyDetailPane(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('选择会话'), findsOneWidget);
      expect(find.text('从左侧选择会话或新建聊天'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('empty-detail-new-chat-button')),
        findsOneWidget,
      );
    });
  });

  group('HermesApp 全局路由与外壳集成测试', () {
    testWidgets('未连接服务器时进入 /onboarding：无论是宽屏还是窄屏均无侧栏外壳', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = InMemorySecureStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionStoreProvider.overrideWithValue(
              ConnectionStore(storage: storage),
            ),
          ],
          child: const HermesApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
        findsNothing,
      );
    });

    testWidgets('已激活连接在窄屏（390×844）：展示单栈 SessionListPage，无侧栏', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      final conn = buildConn('c1');
      await store.save(conn);
      await store.setActive(conn.id);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionStoreProvider.overrideWithValue(store),
            sessionListApiFactoryProvider.overrideWithValue(
              (_) => FakeSessionListApi(),
            ),
          ],
          child: const HermesApp(),
        ),
      );

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.byType(SessionListPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
        findsNothing,
      );
    });

    testWidgets('已激活连接在宽屏（1280×800）：展示双栏外壳（左侧侧栏 + 右侧 EmptyDetailPane）', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      final conn = buildConn('c1');
      await store.save(conn);
      await store.setActive(conn.id);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionStoreProvider.overrideWithValue(store),
            sessionListApiFactoryProvider.overrideWithValue(
              (_) => FakeSessionListApi(),
            ),
            tasksApiFactoryProvider.overrideWithValue((_) => FakeTasksApi()),
          ],
          child: const HermesApp(),
        ),
      );

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
        findsOneWidget,
      );
      expect(find.byType(EmptyDetailPane), findsOneWidget);
      expect(find.byType(SessionListPage), findsOneWidget);

      // 点击侧栏任务工具按钮 → 切换到 /tasks 页面
      final tasksButton = find.byKey(const ValueKey('sidebar-tool-tasks'));
      expect(tasksButton, findsOneWidget);
      await tester.tap(tasksButton);

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(TasksPage), findsOneWidget);
      expect(find.byType(EmptyDetailPane), findsNothing);
      expect(
        find.byKey(const ValueKey('adaptive-session-sidebar')),
        findsOneWidget,
      );
    });
  });
}
