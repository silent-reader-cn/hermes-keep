import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/shell/empty_detail_pane.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';
import 'package:hermes_ui/app/shell/sidebar_nav_rail.dart';
import 'package:hermes_ui/app/widgets/hermes_page_route.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/downloads/download_page.dart';
import 'package:hermes_ui/features/memory/memory_api.dart';
import 'package:hermes_ui/features/memory/memory_page.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/shared/app_back_button.dart';
import 'package:hermes_ui/features/skills/skills_api.dart';
import 'package:hermes_ui/features/skills/skills_page.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_page.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_memory_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/fake_skills_api.dart';
import '../helpers/fake_workspace_manager_api.dart';

class _StubProjectApi implements ProjectApi {
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

class _TasksStub extends StatelessWidget {
  const _TasksStub();

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: AppBackButton(),
        middle: Text('Tasks Page'),
      ),
      child: Center(
        child: Text('Tasks Detail Content', key: ValueKey('tasks-content')),
      ),
    );
  }
}

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const AppBackButton(),
        middle: Text('Chat $sessionId'),
      ),
      child: Center(
        child: Text('Chat Content $sessionId', key: ValueKey('chat-$sessionId-content')),
      ),
    );
  }
}

GoRouter _buildTestRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AdaptiveShell(state: state, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('home'),
              builder: (_) => const SessionListPage(),
            ),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            pageBuilder: (context, state) => HermesPage<void>(
              key: ValueKey('chat-${state.pathParameters['sessionId']}'),
              builder: (_) =>
                  _ChatStub(sessionId: state.pathParameters['sessionId'] ?? ''),
            ),
          ),
          GoRoute(
            path: '/tasks',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('tasks'),
              builder: (_) => const _TasksStub(),
            ),
          ),
          GoRoute(
            path: '/workspaces',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('workspaces'),
              builder: (_) => const WorkspaceManagerPage(),
            ),
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required GoRouter router,
  required Size viewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final sessionApi = FakeSessionListApi(
    sessions: [
      SessionSummary(
        sessionId: 's1',
        title: '测试会话1',
        lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
      ),
    ],
  );
  final workspaceApi = FakeWorkspaceManagerApi();
  final memoryApi = FakeMemoryApi();
  final skillsApi = FakeSkillsApi();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
        projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        workspaceManagerApiFactoryProvider.overrideWithValue((_) => workspaceApi),
        memoryApiFactoryProvider.overrideWithValue((_) => memoryApi),
        skillsApiFactoryProvider.overrideWithValue((_) => skillsApi),
      ],
      child: CupertinoApp.router(
        routerConfig: router,
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TASK T2 / #145 第二轮 左栏模块切换（B 案）测试', () {
    testWidgets('① 点表内模块 → 左栏内容切换且路由不变（核心守卫：不动路由，右侧会话不被打断）', (tester) async {
      final router = _buildTestRouter(initialLocation: '/chat/s1');
      await _pumpApp(tester, router: router, viewport: const Size(1280, 800));

      // 验证初始状态：右侧主区为会话 s1 内容，左栏为会话列表
      expect(find.text('Chat Content s1'), findsOneWidget);
      expect(find.byType(SessionListPage), findsOneWidget);
      expect(find.byType(WorkspaceManagerPage), findsNothing);
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/chat/s1');

      // 点击导航轨中的表内模块「工作区」
      await tester.tap(find.byKey(const ValueKey('sidebar-nav-workspaces')));
      await tester.pumpAndSettle();

      // 断言左栏切换至工作区管理页
      expect(find.byKey(const ValueKey('left-pane-workspaces')), findsOneWidget);
      expect(find.byType(WorkspaceManagerPage), findsOneWidget);
      expect(find.byType(SessionListPage), findsNothing);

      // 核心断言：路由完全未变，仍处于 /chat/s1；右侧聊天内容丝毫不被打断
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/chat/s1');
      expect(find.text('Chat Content s1'), findsOneWidget);
    });

    testWidgets('② 点「会话」→ 回会话列表且路由不变', (tester) async {
      final router = _buildTestRouter(initialLocation: '/chat/s1');
      await _pumpApp(tester, router: router, viewport: const Size(1280, 800));

      // 1. 切入表内模块「记忆」
      await tester.tap(find.byKey(const ValueKey('sidebar-nav-memory')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('left-pane-memory')), findsOneWidget);
      expect(find.byType(MemoryPage), findsOneWidget);
      expect(find.byType(SessionListPage), findsNothing);
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/chat/s1');

      // 2. 点击「会话」入口
      await tester.tap(find.byKey(const ValueKey('sidebar-nav-sessions')));
      await tester.pumpAndSettle();

      // 断言左栏回到会话列表，记忆页销毁
      expect(find.byType(SessionListPage), findsOneWidget);
      expect(find.byType(MemoryPage), findsNothing);

      // 核心断言：路由仍为 /chat/s1，右侧主区未被打断
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/chat/s1');
      expect(find.text('Chat Content s1'), findsOneWidget);
    });

    testWidgets('③ 点表外模块 → 仍 push 走右侧面板栈（保留 #77 行为）', (tester) async {
      final router = _buildTestRouter(initialLocation: '/');
      await _pumpApp(tester, router: router, viewport: const Size(1280, 800));

      // 初始为根路径，右侧为空态占位
      expect(find.byType(EmptyDetailPane), findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-content')), findsNothing);

      // 点击表外模块「任务」
      await tester.tap(find.byKey(const ValueKey('sidebar-nav-tasks')));
      await tester.pumpAndSettle();

      // 断言任务页以 push 方式打开在右侧主区，路由变更为 /tasks
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/tasks');
      expect(find.byKey(const ValueKey('tasks-content')), findsOneWidget);
      expect(find.byType(EmptyDetailPane), findsNothing);

      // 左栏仍保留会话列表
      expect(find.byType(SessionListPage), findsOneWidget);
    });

    testWidgets('④ 窄屏（<900）下导航轨与侧栏不渲染，逐像素不变', (tester) async {
      final router = _buildTestRouter(initialLocation: '/');
      await _pumpApp(tester, router: router, viewport: const Size(800, 600));

      // 窄屏下导航轨与常驻侧栏均不应渲染
      expect(find.byType(SidebarNavRail), findsNothing);
      expect(find.byType(SessionSidebar), findsNothing);

      // 根页面直接呈现 SessionListPage 单栈
      expect(find.byType(SessionListPage), findsOneWidget);
    });

    testWidgets('⑤ 模块页在左栏适配：不展示返回按钮，宽度自适应', (tester) async {
      final router = _buildTestRouter(initialLocation: '/');
      await _pumpApp(tester, router: router, viewport: const Size(1280, 800));

      // 切换至左栏工作区管理页
      await tester.tap(find.byKey(const ValueKey('sidebar-nav-workspaces')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('left-pane-workspaces')), findsOneWidget);

      // 断言左栏内部的 AppBackButton 返回按钮不渲染（因处于 LeftPaneScope）
      final backButtons = find.descendant(
        of: find.byKey(const ValueKey('left-pane-workspaces')),
        matching: find.byType(AppBackButton),
      );
      expect(backButtons, findsNothing);

      // 大标题正常展示（文案取自 l10n.workspacesTitle = 「工作区」）。
      // 用 descendant 限定在左栏子树内，避免与导航轨同文案的 tooltip 撞车；
      // 断言「至少一个」而非恰好一个——AdaptiveSliverNavigationBar 是
      //「展开态大标题 + 收起态中标题」双标题结构，同文案会出现两处。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('left-pane-workspaces')),
          matching: find.text('工作区'),
        ),
        findsWidgets,
        reason: '左栏模块页应展示标题',
      );
    });

    testWidgets('各表内模块依次切换正常展示', (tester) async {
      final router = _buildTestRouter(initialLocation: '/');
      await _pumpApp(tester, router: router, viewport: const Size(1280, 800));

      // 依次点击技能、下载、记忆、工作区
      await tester.tap(find.byKey(const ValueKey('sidebar-nav-skills')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('left-pane-skills')), findsOneWidget);
      expect(find.byType(SkillsPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sidebar-nav-downloads')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('left-pane-downloads')), findsOneWidget);
      expect(find.byType(DownloadPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sidebar-nav-memory')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('left-pane-memory')), findsOneWidget);
      expect(find.byType(MemoryPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sidebar-nav-workspaces')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('left-pane-workspaces')), findsOneWidget);
      expect(find.byType(WorkspaceManagerPage), findsOneWidget);

      // 路由始终未变
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/');
    });
  });
}
