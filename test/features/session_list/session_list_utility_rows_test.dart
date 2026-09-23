import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_entry_visibility.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_utility_rows.dart';

import '../../helpers/fake_session_list_api.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';

class _FilteredVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: false,
      kanban: true,
      skills: true,
      insights: false,
      workspaces: true,
      memory: false,
    );
  }
}

class _AllVisibleVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: true,
      kanban: true,
      skills: true,
      insights: true,
      workspaces: true,
      memory: true,
    );
  }
}

class _AllHiddenVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: false,
      kanban: false,
      skills: false,
      insights: false,
      workspaces: false,
      memory: false,
      downloads: false,
    );
  }
}

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

class _DestinationStub extends StatelessWidget {
  const _DestinationStub({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('nav-$title')),
      child: Center(child: Text('body-$title')),
    );
  }
}

void main() {
  group('SessionListUtilityRows 独立组件测试', () {
    testWidgets('默认渲染 5 个入口（看板默认隐藏，记忆默认显示）', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      // 默认 5 个入口文本（看板默认关闭，记忆默认开启）
      expect(find.text('任务'), findsOneWidget);
      expect(find.text('看板'), findsNothing);
      expect(find.text('工作区'), findsOneWidget);
      expect(find.text('技能'), findsOneWidget);
      expect(find.text('记忆'), findsOneWidget);
      expect(find.text('统计'), findsOneWidget);

      // 入口 Key
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-workspaces')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsOneWidget,
      );
    });

    testWidgets('显式全开时渲染 6 个入口（含看板与记忆）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllVisibleVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      expect(find.text('看板'), findsOneWidget);
      expect(find.text('记忆'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsOneWidget,
      );
    });

    testWidgets('自定义回调可正常触发', (tester) async {
      var tasksCalled = false;
      var kanbanCalled = false;
      var workspacesCalled = false;
      var skillsCalled = false;
      var insightsCalled = false;
      var memoryCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllVisibleVisibilityNotifier.new,
            ),
          ],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: SessionListUtilityRows(
                onTapTasks: () => tasksCalled = true,
                onTapKanban: () => kanbanCalled = true,
                onTapWorkspaces: () => workspacesCalled = true,
                onTapSkills: () => skillsCalled = true,
                onTapInsights: () => insightsCalled = true,
                onTapMemory: () => memoryCalled = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-tasks')),
      );
      await tester.pump();
      expect(tasksCalled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-kanban')),
      );
      await tester.pump();
      expect(kanbanCalled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-workspaces')),
      );
      await tester.pump();
      expect(workspacesCalled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-skills')),
      );
      await tester.pump();
      expect(skillsCalled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-insights')),
      );
      await tester.pump();
      expect(insightsCalled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-memory')),
      );
      await tester.pump();
      expect(memoryCalled, isTrue);
    });

    testWidgets('可访问性语义：每个按钮具备 Semantics 标签', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllVisibleVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '任务',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '看板',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '技能',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '统计',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '记忆',
        ),
        findsOneWidget,
      );
    });

    testWidgets('按显隐配置过滤入口：关闭任务/统计/记忆，仅渲染其余 3 个', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _FilteredVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-workspaces')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsNothing,
      );
    });

    testWidgets('功能入口全关时组件返回 SizedBox.shrink()（不渲染容器）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllHiddenVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsNothing,
      );
    });
  });

  group('SessionListPage 窄屏快捷导航集成测试与路由跳转（<900）', () {
    Future<GoRouter> pumpSessionListPage(
      WidgetTester tester, {
      FakeSessionListApi? api,
      Override? visibilityOverride,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi =
          api ??
          FakeSessionListApi(
            sessions: [
              SessionSummary(
                sessionId: 's-test-1',
                title: '测试会话 1',
                lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
              ),
            ],
          );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
          GoRoute(
            path: '/tasks',
            builder: (_, _) =>
                const _DestinationStub(title: 'TasksDestination'),
          ),
          GoRoute(
            path: '/kanban',
            builder: (_, _) =>
                const _DestinationStub(title: 'KanbanDestination'),
          ),
          GoRoute(
            path: '/workspaces',
            builder: (_, _) =>
                const _DestinationStub(title: 'WorkspacesDestination'),
          ),
          GoRoute(
            path: '/skills',
            builder: (_, _) =>
                const _DestinationStub(title: 'SkillsDestination'),
          ),
          GoRoute(
            path: '/memory',
            builder: (_, _) =>
                const _DestinationStub(title: 'MemoryDestination'),
          ),
          GoRoute(
            path: '/insights',
            builder: (_, _) =>
                const _DestinationStub(title: 'InsightsDestination'),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) =>
                const _DestinationStub(title: 'SettingsDestination'),
          ),
          GoRoute(
            path: '/chat',
            builder: (_, _) => const _DestinationStub(title: 'ChatNew'),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, state) => const _DestinationStub(title: 'Chat_'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => fakeApi),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            ?visibilityOverride,
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );

      // 加载完成
      await tester.pump();
      await tester.pump();
      return router;
    }

    testWidgets('窄屏下独立工具行不渲染，大标题右侧展示快捷导航下拉按钮', (tester) async {
      await pumpSessionListPage(tester);

      // 窄屏收敛：不渲染横排 SessionListUtilityRows
      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsNothing,
      );
      // 大标题右侧渲染窄屏下拉按钮
      expect(
        find.byKey(const ValueKey('session-list-narrow-nav')),
        findsOneWidget,
      );
    });

    testWidgets('点击窄屏下拉按钮展开菜单并跳转 /tasks', (tester) async {
      await pumpSessionListPage(tester);

      await tester.tap(
        find.byKey(const ValueKey('session-list-narrow-nav')),
      );
      await tester.pumpAndSettle();

      // 默认开启的入口项（任务/工作区/技能/统计/记忆，看板默认关闭）
      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-workspaces')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-skills')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-insights')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-memory')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-kanban')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('narrow-nav-tasks')));
      await tester.pumpAndSettle();

      expect(find.text('body-TasksDestination'), findsOneWidget);
    });

    testWidgets('全开配置下点击窄屏下拉菜单项 → 跳转 /kanban 与 /workspaces', (tester) async {
      await pumpSessionListPage(
        tester,
        visibilityOverride: sessionEntryVisibilityProvider.overrideWith(
          _AllVisibleVisibilityNotifier.new,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('session-list-narrow-nav')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-kanban')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-memory')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('narrow-nav-kanban')));
      await tester.pumpAndSettle();

      expect(find.text('body-KanbanDestination'), findsOneWidget);
    });

    testWidgets('点击技能与统计菜单项 → 跳转 /skills 与 /insights', (tester) async {
      await pumpSessionListPage(tester);

      await tester.tap(
        find.byKey(const ValueKey('session-list-narrow-nav')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('narrow-nav-skills')));
      await tester.pumpAndSettle();

      expect(find.text('body-SkillsDestination'), findsOneWidget);
    });

    testWidgets('搜索模式下窄屏下拉按钮隐藏，清空搜索后重新显示', (tester) async {
      await pumpSessionListPage(tester);

      expect(
        find.byKey(const ValueKey('session-list-narrow-nav')),
        findsOneWidget,
      );

      // 输入搜索内容进入搜索模式
      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        '测试',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // 搜索模式下下拉按钮隐藏
      expect(
        find.byKey(const ValueKey('session-list-narrow-nav')),
        findsNothing,
      );

      // 清空搜索内容退出搜索模式
      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        '',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // 下拉按钮恢复显示
      expect(
        find.byKey(const ValueKey('session-list-narrow-nav')),
        findsOneWidget,
      );
    });

    testWidgets('全关功能入口时窄屏下拉按钮不渲染', (tester) async {
      await pumpSessionListPage(
        tester,
        visibilityOverride: sessionEntryVisibilityProvider.overrideWith(
          _AllHiddenVisibilityNotifier.new,
        ),
      );

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-narrow-nav')),
        findsNothing,
      );
    });
  });

  group('SessionListPage 宽屏工具行集成测试（>=900）', () {
    Future<GoRouter> pumpWideSessionListPage(
      WidgetTester tester, {
      FakeSessionListApi? api,
      Override? visibilityOverride,
    }) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi =
          api ??
          FakeSessionListApi(
            sessions: [
              SessionSummary(
                sessionId: 's-test-1',
                title: '测试会话 1',
                lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
              ),
            ],
          );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
          GoRoute(
            path: '/tasks',
            builder: (_, _) =>
                const _DestinationStub(title: 'TasksDestination'),
          ),
          GoRoute(
            path: '/kanban',
            builder: (_, _) =>
                const _DestinationStub(title: 'KanbanDestination'),
          ),
          GoRoute(
            path: '/workspaces',
            builder: (_, _) =>
                const _DestinationStub(title: 'WorkspacesDestination'),
          ),
          GoRoute(
            path: '/skills',
            builder: (_, _) =>
                const _DestinationStub(title: 'SkillsDestination'),
          ),
          GoRoute(
            path: '/memory',
            builder: (_, _) =>
                const _DestinationStub(title: 'MemoryDestination'),
          ),
          GoRoute(
            path: '/insights',
            builder: (_, _) =>
                const _DestinationStub(title: 'InsightsDestination'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => fakeApi),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            ?visibilityOverride,
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );

      await tester.pump();
      await tester.pump();
      return router;
    }

    testWidgets('宽屏下渲染独立工具行，不渲染大标题右侧下拉按钮', (tester) async {
      await pumpWideSessionListPage(tester);

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-narrow-nav')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsOneWidget,
      );
    });

    testWidgets('宽屏下点击工具行任务入口 → 跳转 /tasks', (tester) async {
      await pumpWideSessionListPage(tester);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-tasks')),
      );
      await tester.pumpAndSettle();

      expect(find.text('body-TasksDestination'), findsOneWidget);
    });

    testWidgets('showUtilityRows=false 桌面模式：工具行不渲染，头部无大标题且为单行搜索框', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SessionSidebar(currentLocation: '/'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue(
              (_) => FakeSessionListApi(),
            ),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsNothing,
      );
      expect(find.text('会话'), findsNothing);
      // #149：侧栏顶部品牌行承担搜索入口（列表内不再有搜索框，
      // 搜索框由品牌行的搜索图标展开）。
      expect(
        find.byKey(const ValueKey('sidebar-brand-search')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-search')),
        findsNothing,
      );
    });
  });
}
