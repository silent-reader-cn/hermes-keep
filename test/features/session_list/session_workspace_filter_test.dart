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
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_session_list_api.dart';

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(
  String id,
  String title, {
  String? workspace,
  String? projectId,
  bool pinned = false,
  DateTime? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    workspace: workspace,
    projectId: projectId,
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
    final s1 = _session(
      's1',
      'Session 1',
      workspace: '/ws/alpha',
      projectId: 'p1',
      at: now,
    );
    final s2 = _session(
      's2',
      'Session 2',
      workspace: '/ws/beta',
      projectId: 'p2',
      at: now,
    );
    final s3 = _session(
      's3',
      'Session 3',
      workspace: '/ws/alpha',
      projectId: 'p2',
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

      await container.read(sessionListControllerProvider.future);

      final filter = container.read(selectedWorkspaceFilterProvider);
      expect(filter, isNull);

      final state = container.read(sessionListControllerProvider).valueOrNull!;
      final filtered = container.read(filteredDisplaySessionsProvider);
      final visible = container.read(sessionListVisibleSessionsProvider);

      expect(filtered.length, equals(state.displaySessions.length));
      expect(
        filtered.map((s) => s.sessionId),
        equals(state.displaySessions.map((s) => s.sessionId)),
      );
      expect(visible.length, equals(4));
    });

    test('② 选中工作区后只剩该工作区会话，且区分于 projectId 维度', () async {
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

      // 选中 /ws/alpha（s1 和 s3 属于该工作区，但 s1 属于 p1，s3 属于 p2）
      container
          .read(selectedWorkspaceFilterProvider.notifier)
          .selectWorkspace('/ws/alpha');
      expect(
        container.read(selectedWorkspaceFilterProvider),
        equals('/ws/alpha'),
      );

      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.filterMode, equals(SessionListFilterMode.workspace));
      expect(state.filterValue, equals('/ws/alpha'));

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
        container.read(sessionListControllerProvider).valueOrNull!.filterMode,
        equals(SessionListFilterMode.all),
      );
      expect(
        container.read(filteredDisplaySessionsProvider).length,
        equals(4),
      );
    });

    test('工作区筛选下的分页 loadMore 行为', () async {
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
      bool throwWorkspaceError = false,
      SessionListFilterMode initialMode = SessionListFilterMode.all,
      String? initialFilterValue,
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
              if (throwWorkspaceError) {
                return Future<List<WorkspaceRoot>>.error(
                  Exception('Failed to load workspaces'),
                );
              }
              return Future.value(workspaces);
            }),
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
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      if (initialMode != SessionListFilterMode.all ||
          initialFilterValue != null) {
        final element = tester.element(find.byType(SessionListPage));
        final container = ProviderScope.containerOf(element);
        await container.read(sessionListControllerProvider.notifier).setFilter(
          initialMode,
          value: initialFilterValue,
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('④ 默认态列表与改造前逐像素一致（关键回归守卫）：移除侧栏卡片后无多余顶部卡片', (tester) async {
      final s1 = _session('s1', '会话一', workspace: '/projects/alpha');
      final s2 = _session('s2', '会话二', workspace: '/projects/beta');

      await pumpSessionList(
        tester,
        sessions: [s1, s2],
        workspaces: [
          const WorkspaceRoot(path: '/projects/alpha', name: 'Alpha'),
          const WorkspaceRoot(path: '/projects/beta', name: 'Beta'),
        ],
      );

      // 侧栏工作区选择器卡片已被彻底移除，不再渲染
      expect(
        find.byKey(const ValueKey('sidebar-workspace-selector')),
        findsNothing,
      );

      // 会话行正常展示
      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsOneWidget);

      // 筛选按钮存在
      expect(
        find.byKey(const ValueKey('session-list-filter-trigger')),
        findsOneWidget,
      );
    });

    testWidgets('① 筛选菜单出现工作区维度：展示全部工作区与各项（name 优先、path 兜底），默认态全部勾选', (tester) async {
      final s1 = _session('s1', 'Alpha 会话', workspace: '/projects/alpha');
      final s2 = _session('s2', 'Beta 会话', workspace: '/projects/beta');

      await pumpSessionList(
        tester,
        sessions: [s1, s2],
        workspaces: [
          const WorkspaceRoot(path: '/projects/alpha', name: 'Alpha 项目'),
          const WorkspaceRoot(path: '/projects/beta'), // 无 name，path 兜底
        ],
      );

      // 打开筛选菜单
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 出现工作区分组
      expect(
        find.byKey(const ValueKey('filter-section-workspaces')),
        findsOneWidget,
      );
      expect(find.text('工作区'), findsOneWidget);

      // 全部工作区存在
      expect(find.byKey(const ValueKey('workspace-chip-all')), findsOneWidget);
      expect(find.text('全部工作区'), findsOneWidget);

      // name 优先（显示 Alpha 项目）
      expect(
        find.byKey(const ValueKey('workspace-chip-/projects/alpha')),
        findsOneWidget,
      );
      expect(find.text('Alpha 项目'), findsOneWidget);

      // path 兜底（显示 /projects/beta）
      expect(
        find.byKey(const ValueKey('workspace-chip-/projects/beta')),
        findsOneWidget,
      );
      expect(find.text('/projects/beta'), findsOneWidget);

      // 默认态下「全部工作区」行显示 checkmark 选中
      final allRowFinder = find.descendant(
        of: find.byKey(const ValueKey('workspace-chip-all')),
        matching: find.byIcon(CupertinoIcons.check_mark),
      );
      expect(allRowFinder, findsOneWidget);
    });

    testWidgets('② 选中工作区后只留该工作区会话', (tester) async {
      final sAlpha = _session('s_alpha', 'Alpha 会话', workspace: '/projects/alpha');
      final sBeta = _session('s_beta', 'Beta 会话', workspace: '/projects/beta');

      await pumpSessionList(
        tester,
        sessions: [sAlpha, sBeta],
        workspaces: [
          const WorkspaceRoot(path: '/projects/alpha', name: 'Alpha 项目'),
          const WorkspaceRoot(path: '/projects/beta', name: 'Beta 项目'),
        ],
      );

      // 打开筛选菜单
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 点击 Alpha 项目
      await tester.tap(
        find.byKey(const ValueKey('workspace-chip-/projects/alpha')),
      );
      await tester.pumpAndSettle();

      // 弹层关闭，只留该工作区会话
      expect(find.byKey(const ValueKey('session-filter-sheet')), findsNothing);
      expect(find.text('Alpha 会话'), findsOneWidget);
      expect(find.text('Beta 会话'), findsNothing);

      // 再次打开筛选菜单，确认 Alpha 项目项被勾选，「全部工作区」未勾选
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final alphaCheckmark = find.descendant(
        of: find.byKey(const ValueKey('workspace-chip-/projects/alpha')),
        matching: find.byIcon(CupertinoIcons.check_mark),
      );
      expect(alphaCheckmark, findsOneWidget);

      final allCheckmark = find.descendant(
        of: find.byKey(const ValueKey('workspace-chip-all')),
        matching: find.byIcon(CupertinoIcons.check_mark),
      );
      expect(allCheckmark, findsNothing);

      // 同时「会话」分组出现「清除筛选」
      expect(find.byKey(const ValueKey('sheet-filter-clear')), findsOneWidget);
    });

    testWidgets('③-a 工作区列表为空时不显示该分组', (tester) async {
      final sAlpha = _session('s_alpha', 'Alpha 会话', workspace: '/projects/alpha');

      await pumpSessionList(
        tester,
        sessions: [sAlpha],
        workspaces: const [],
      );

      // 打开筛选菜单
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 不显示工作区分组
      expect(
        find.byKey(const ValueKey('filter-section-workspaces')),
        findsNothing,
      );
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('③-b 工作区列表加载失败时不显示该分组（不显示错误态）', (tester) async {
      final sAlpha = _session('s_alpha', 'Alpha 会话', workspace: '/projects/alpha');

      await pumpSessionList(
        tester,
        sessions: [sAlpha],
        throwWorkspaceError: true,
      );

      // 打开筛选菜单
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 不显示工作区分组，且不显示错误态
      expect(
        find.byKey(const ValueKey('filter-section-workspaces')),
        findsNothing,
      );
      expect(find.text('Failed to load workspaces'), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('在筛选菜单中选中「全部工作区」恢复显示全部会话', (tester) async {
      final sAlpha = _session('s_alpha', 'Alpha 会话', workspace: '/projects/alpha');
      final sBeta = _session('s_beta', 'Beta 会话', workspace: '/projects/beta');

      await pumpSessionList(
        tester,
        sessions: [sAlpha, sBeta],
        workspaces: [
          const WorkspaceRoot(path: '/projects/alpha', name: 'Alpha'),
          const WorkspaceRoot(path: '/projects/beta', name: 'Beta'),
        ],
        initialMode: SessionListFilterMode.workspace,
        initialFilterValue: '/projects/alpha',
      );

      expect(find.text('Alpha 会话'), findsOneWidget);
      expect(find.text('Beta 会话'), findsNothing);

      // 打开筛选菜单
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 点击「全部工作区」
      await tester.tap(find.byKey(const ValueKey('workspace-chip-all')));
      await tester.pumpAndSettle();

      // 弹层关闭，恢复显示全部会话
      expect(find.byKey(const ValueKey('session-filter-sheet')), findsNothing);
      expect(find.text('Alpha 会话'), findsOneWidget);
      expect(find.text('Beta 会话'), findsOneWidget);
    });

    testWidgets('空结果空态 + 「清除筛选」动作恢复会话', (tester) async {
      final sAlpha = _session('s_alpha', 'Alpha 会话', workspace: '/projects/alpha');

      await pumpSessionList(
        tester,
        sessions: [sAlpha],
        workspaces: [
          const WorkspaceRoot(path: '/projects/alpha', name: 'Alpha'),
          const WorkspaceRoot(path: '/projects/empty', name: 'EmptyWS'),
        ],
        initialMode: SessionListFilterMode.workspace,
        initialFilterValue: '/projects/empty',
      );

      // 筛选后无会话，显示工作区专属空态
      expect(find.text('该工作区下暂无会话'), findsOneWidget);
      expect(find.text('清除筛选以查看全部会话'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.folder_badge_minus), findsOneWidget);

      final clearBtn = find.byKey(const ValueKey('session-list-clear-filter'));
      expect(clearBtn, findsOneWidget);

      // 点击清除筛选
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // 会话重新出现
      expect(find.text('Alpha 会话'), findsOneWidget);
      expect(find.text('该工作区下暂无会话'), findsNothing);
    });
  });
}
