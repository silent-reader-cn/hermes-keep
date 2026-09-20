import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/session_list/sidebar_workspace_selector.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_session_list_api.dart';

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(
  String id,
  String title, {
  String? workspace,
  bool pinned = false,
  DateTime? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    workspace: workspace,
    pinned: pinned,
    lastMessageAt: _sec(at ?? DateTime.now()),
  );
}

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async =>
      const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async =>
      const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

void main() {
  group('matchesWorkspace 路径比对工具函数', () {
    test('相同路径匹配', () {
      expect(matchesWorkspace('/path/to/project', '/path/to/project'), isTrue);
    });

    test('容错斜杠与反斜杠差异', () {
      expect(
        matchesWorkspace('C:\\projects\\hermes', 'C:/projects/hermes'),
        isTrue,
      );
    });

    test('忽略首尾空格', () {
      expect(matchesWorkspace('  /a/b  ', '/a/b'), isTrue);
    });

    test('不同路径不匹配', () {
      expect(matchesWorkspace('/path/a', '/path/b'), isFalse);
    });

    test('null 或空字符串不匹配', () {
      expect(matchesWorkspace(null, '/path/a'), isFalse);
      expect(matchesWorkspace('/path/a', null), isFalse);
      expect(matchesWorkspace('', '/path/a'), isFalse);
      expect(matchesWorkspace('/path/a', ''), isFalse);
    });
  });

  group('工作区筛选 Provider 逻辑单测', () {
    final now = DateTime.now();
    final s1 = _session('s1', 'Session 1', workspace: '/ws/alpha', at: now);
    final s2 = _session('s2', 'Session 2', workspace: '/ws/beta', at: now);
    final s3 = _session(
      's3',
      'Session 3',
      workspace: '/ws/alpha',
      pinned: true,
      at: now,
    );
    final s4 = _session('s4', 'Session 4', workspace: null, at: now);

    test('① 默认态不改变列表（关键回归守卫）：filter 为 null 时与原始全量完全一致', () async {
      final api = FakeSessionListApi(sessions: [s1, s2, s3, s4]);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
        ],
      );
      addTearDown(container.dispose);

      // 触发首屏加载
      await container.read(sessionListControllerProvider.future);

      final filter = container.read(selectedWorkspaceFilterProvider);
      expect(filter, isNull);

      final state = container.read(sessionListControllerProvider).valueOrNull!;
      final filtered = container.read(filteredDisplaySessionsProvider);
      final visible = container.read(sessionListVisibleSessionsProvider);

      expect(filtered.length, equals(state.displaySessions.length));
      expect(filtered.map((s) => s.sessionId), equals(state.displaySessions.map((s) => s.sessionId)));
      expect(visible.length, equals(4));
    });

    test('② 选中工作区后只剩该工作区会话', () async {
      final api = FakeSessionListApi(sessions: [s1, s2, s3, s4]);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);

      // 选中 /ws/alpha
      container
          .read(selectedWorkspaceFilterProvider.notifier)
          .selectWorkspace('/ws/alpha');
      expect(
        container.read(selectedWorkspaceFilterProvider),
        equals('/ws/alpha'),
      );

      final filtered = container.read(filteredDisplaySessionsProvider);
      expect(filtered.length, equals(2));
      expect(filtered.map((s) => s.sessionId), containsAll(['s1', 's3']));
      expect(filtered.map((s) => s.sessionId), isNot(contains('s2')));
      expect(filtered.map((s) => s.sessionId), isNot(contains('s4')));

      // 分区包含置顶 s3 与今天 s1
      final sections = container.read(sessionListSectionsProvider);
      expect(sections.any((sec) => sec.title == '置顶'), isTrue);
      final pinnedSec = sections.firstWhere((sec) => sec.title == '置顶');
      expect(pinnedSec.sessions.map((s) => s.sessionId), equals(['s3']));

      // 切换为 /ws/beta
      container
          .read(selectedWorkspaceFilterProvider.notifier)
          .selectWorkspace('/ws/beta');
      final filteredBeta = container.read(filteredDisplaySessionsProvider);
      expect(filteredBeta.length, equals(1));
      expect(filteredBeta.first.sessionId, equals('s2'));

      // 清除筛选
      container.read(selectedWorkspaceFilterProvider.notifier).clearFilter();
      expect(container.read(selectedWorkspaceFilterProvider), isNull);
      expect(
        container.read(filteredDisplaySessionsProvider).length,
        equals(4),
      );
    });

    test('工作区筛选下的分页 loadMore 行为', () async {
      // 创建 60 个 /ws/gamma 会话与 10 个 /ws/other 会话
      final gammaSessions = List.generate(
        60,
        (i) => _session('g_$i', 'Gamma $i', workspace: '/ws/gamma'),
      );
      final otherSessions = List.generate(
        10,
        (i) => _session('o_$i', 'Other $i', workspace: '/ws/other'),
      );

      final api = FakeSessionListApi(
        sessions: [...gammaSessions, ...otherSessions],
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);

      container
          .read(selectedWorkspaceFilterProvider.notifier)
          .selectWorkspace('/ws/gamma');

      expect(container.read(filteredDisplaySessionsProvider).length, equals(60));
      expect(container.read(sessionListVisibleSessionsProvider).length, equals(50));
      expect(container.read(sessionListHasMoreProvider), isTrue);

      // 加载下一页
      await container.read(sessionListControllerProvider.notifier).loadMore();
      expect(container.read(sessionListVisibleSessionsProvider).length, equals(60));
      expect(container.read(sessionListHasMoreProvider), isFalse);

      // 切换工作区重置 visibleCount 为 pageSize
      container
          .read(selectedWorkspaceFilterProvider.notifier)
          .selectWorkspace('/ws/other');
      expect(container.read(sessionListVisibleSessionsProvider).length, equals(10));
      expect(container.read(sessionListHasMoreProvider), isFalse);
    });
  });

  group('SessionListPage 界面筛选与空态交互测试', () {
    Future<void> pumpSessionList(
      WidgetTester tester, {
      required List<SessionSummary> sessions,
      List<WorkspaceRoot> workspaces = const [],
      String? initialWorkspaceFilter,
      bool showWorkspaceSelector = true,
      Size viewportSize = const Size(1200, 800),
    }) async {
      tester.view.physicalSize = viewportSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeSessionListApi(sessions: sessions);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            workspaceRootsProvider.overrideWith(
              (ref) => Future.value(workspaces),
            ),
            if (initialWorkspaceFilter != null)
              selectedWorkspaceFilterProvider.overrideWith(
                () => _InitialWorkspaceController(initialWorkspaceFilter),
              ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: SessionListPage(
                showUtilityRows: false,
                showSettingsTrailing: false,
                showFab: false,
                showWorkspaceSelector: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('② 选中工作区后只剩该工作区会话', (tester) async {
      final sAlpha = _session('s_alpha', 'Alpha 会话', workspace: '/projects/alpha');
      final sBeta = _session('s_beta', 'Beta 会话', workspace: '/projects/beta');

      await pumpSessionList(
        tester,
        sessions: [sAlpha, sBeta],
        workspaces: [
          const WorkspaceRoot(path: '/projects/alpha', name: 'Alpha'),
          const WorkspaceRoot(path: '/projects/beta', name: 'Beta'),
        ],
        initialWorkspaceFilter: '/projects/alpha',
      );

      expect(find.text('Alpha 会话'), findsOneWidget);
      expect(find.text('Beta 会话'), findsNothing);
    });

    testWidgets('③ 空结果空态 + 「清除筛选」动作恢复会话', (tester) async {
      final sAlpha = _session('s_alpha', 'Alpha 会话', workspace: '/projects/alpha');

      await pumpSessionList(
        tester,
        sessions: [sAlpha],
        workspaces: [
          const WorkspaceRoot(path: '/projects/alpha', name: 'Alpha'),
          const WorkspaceRoot(path: '/projects/empty', name: 'EmptyWS'),
        ],
        initialWorkspaceFilter: '/projects/empty',
      );

      // 筛选后无会话，显示工作区专属空态
      expect(find.text('该工作区下暂无会话'), findsOneWidget);
      expect(find.text('清除筛选以查看全部会话'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.folder_badge_minus), findsOneWidget);

      final clearBtn = find.byKey(const ValueKey('session-list-clear-filter'));
      expect(clearBtn, findsOneWidget);

      // 点击清除筛选
      await tester.tap(clearBtn);
      await tester.pump();
      await tester.pump();

      // 会话重新出现
      expect(find.text('Alpha 会话'), findsOneWidget);
      expect(find.text('该工作区下暂无会话'), findsNothing);
    });
  });

  group('SidebarWorkspaceSelector 独立组件测试', () {
    Future<void> pumpSelector(
      WidgetTester tester, {
      required List<WorkspaceRoot> roots,
      List<SessionSummary> sessions = const [],
      String? initialSelectedPath,
      bool throwError = false,
      Size viewportSize = const Size(1200, 800),
    }) async {
      tester.view.physicalSize = viewportSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeSessionListApi(sessions: sessions);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            workspaceRootsProvider.overrideWith((ref) {
              if (throwError) {
                return Future<List<WorkspaceRoot>>.error(
                  Exception('Network error'),
                );
              }
              return Future<List<WorkspaceRoot>>.value(roots);
            }),
            if (initialSelectedPath != null)
              selectedWorkspaceFilterProvider.overrideWith(
                () => _InitialWorkspaceController(initialSelectedPath),
              ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Center(
                child: SizedBox(
                  width: 290,
                  child: SidebarWorkspaceSelector(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('④-a 空列表不渲染选择器 (SizedBox.shrink)', (tester) async {
      await pumpSelector(tester, roots: []);

      expect(
        find.byKey(const ValueKey('sidebar-workspace-selector')),
        findsNothing,
      );
    });

    testWidgets('④-b 加载失败不渲染选择器，不显示错误态', (tester) async {
      await pumpSelector(tester, roots: [], throwError: true);

      expect(
        find.byKey(const ValueKey('sidebar-workspace-selector')),
        findsNothing,
      );
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('④-c 窄屏 (< 900) 不渲染本选择器', (tester) async {
      await pumpSelector(
        tester,
        roots: [const WorkspaceRoot(path: '/ws/1', name: 'WS1')],
        viewportSize: const Size(800, 600), // < 900
      );

      expect(
        find.byKey(const ValueKey('sidebar-workspace-selector')),
        findsNothing,
      );
    });

    testWidgets('正常宽屏下渲染白底卡片 + 会话计数 + 点击展开菜单并切换', (tester) async {
      final s1 = _session('s1', 'S1', workspace: '/ws/alpha');
      final s2 = _session('s2', 'S2', workspace: '/ws/alpha');
      final s3 = _session('s3', 'S3', workspace: '/ws/beta');

      await pumpSelector(
        tester,
        roots: [
          const WorkspaceRoot(path: '/ws/alpha', name: 'Alpha Project'),
          const WorkspaceRoot(path: '/ws/beta', name: 'Beta Project'),
        ],
        sessions: [s1, s2, s3],
      );

      // 默认态：显示「全部工作区」+ 3 个会话
      expect(
        find.byKey(const ValueKey('sidebar-workspace-selector')),
        findsOneWidget,
      );
      expect(find.text('全部工作区'), findsOneWidget);
      expect(find.text('3 个会话'), findsOneWidget);

      // 点击打开菜单
      await tester.tap(find.byKey(const ValueKey('sidebar-workspace-selector')));
      await tester.pump();
      await tester.pump();

      // 菜单项可见
      expect(find.byKey(const ValueKey('workspace-option-all')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-option-/ws/alpha')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-option-/ws/beta')),
        findsOneWidget,
      );
      expect(find.text('Alpha Project'), findsOneWidget);
      expect(find.text('/ws/alpha'), findsOneWidget);

      // 点击选中 Alpha Project
      await tester.tap(find.byKey(const ValueKey('workspace-option-/ws/alpha')));
      await tester.pump();
      await tester.pump();

      // 标题翻新为 Alpha Project，计数为 2 个会话
      expect(find.text('Alpha Project'), findsOneWidget);
      expect(find.text('/ws/alpha · 2 个会话'), findsOneWidget);
    });
  });
}

class _InitialWorkspaceController extends SelectedWorkspaceFilterController {
  _InitialWorkspaceController(this._initial);
  final String _initial;
  @override
  String? build() => _initial;
}
