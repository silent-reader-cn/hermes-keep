import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_session_list_api.dart';

import 'package:hermes_ui/app/shell/session_sidebar.dart';

/// #161：侧栏「定时任务」行带待办计数徽标 ⇒ `SidebarToolsList` 会 watch
/// `tasksJobCountProvider`（build 会真发 `fetchJobs`）。这些用例不关心任务数据，
/// 注入空任务避免真实请求留下 Dio 超时 timer（表现为 `!timersPending`）。
class _EmptyTasksController extends TasksController {
  @override
  Future<TasksState> build() async {
    ref.watch(tasksApiFactoryProvider);
    return const TasksState(jobs: <CronJob>[]);
  }
}

double sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary buildSession(
  String id,
  String title, {
  bool pinned = false,
  DateTime? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    lastMessageAt: sec(at ?? DateTime.now()),
  );
}

ProviderContainer makeContainer(
  FakeSessionListApi api, {
  AppLifecycleState lifecycle = AppLifecycleState.resumed,
  bool windowFocused = true,
}) {
  final container = ProviderContainer(
    overrides: [
      tasksControllerProvider.overrideWith(_EmptyTasksController.new),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => FakeOnboardingLoginApi(),
      ),
    ],
  );
  container.read(appLifecycleStateProvider.notifier).setState(lifecycle);
  container.read(windowFocusedProvider.notifier).state = windowFocused;
  addTearDown(container.dispose);
  return container;
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

void main() {
  setUp(() {
    enableSessionAutoRefresh = true;
  });
  tearDown(() {
    enableSessionAutoRefresh = true;
  });
  group('SessionListState 刷新字段', () {
    test('copyWith 保留/更新 lastRefreshAt/refreshing/consecutiveFailures', () {
      final now = DateTime.utc(2026, 8, 22, 12);
      const s = SessionListState();
      expect(s.refreshing, isFalse);
      expect(s.consecutiveFailures, 0);
      expect(s.lastRefreshAt, isNull);
      final s2 = s.copyWith(
        lastRefreshAt: () => now,
        refreshing: true,
        consecutiveFailures: 2,
      );
      expect(s2.lastRefreshAt, now);
      expect(s2.refreshing, isTrue);
      expect(s2.consecutiveFailures, 2);
      final s3 = s2.copyWith(refreshing: false);
      expect(s3.refreshing, isFalse);
      expect(s3.lastRefreshAt, now);
    });
  });

  group('SessionListController.nextAutoRefreshDelay 指数退避', () {
    test('0→30s,1→60s,2→120s,3→capped120s', () {
      expect(
        SessionListController.nextAutoRefreshDelay(0),
        const Duration(seconds: 30),
      );
      expect(
        SessionListController.nextAutoRefreshDelay(1),
        const Duration(seconds: 60),
      );
      expect(
        SessionListController.nextAutoRefreshDelay(2),
        const Duration(seconds: 120),
      );
      expect(
        SessionListController.nextAutoRefreshDelay(3),
        const Duration(seconds: 120),
      );
      expect(
        SessionListController.nextAutoRefreshDelay(10),
        const Duration(seconds: 120),
      );
    });
  });

  group('refresh 成功/失败语义', () {
    test('refresh 成功写 lastRefreshAt/clear failures', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      final c = makeContainer(api);
      await c.read(sessionListControllerProvider.future);
      await c.read(sessionListControllerProvider.notifier).refresh();
      final st = c.read(sessionListControllerProvider).valueOrNull!;
      expect(st.sessions, hasLength(1));
      expect(st.lastRefreshAt, isNotNull);
      expect(st.lastAttemptAt, isNotNull);
      expect(st.refreshing, isFalse);
      expect(st.consecutiveFailures, 0);
    });

    test('有数据时 refresh 失败→保留数据+failures+1不进AsyncError', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      final c = makeContainer(api);
      await c.read(sessionListControllerProvider.future);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await c.read(sessionListControllerProvider.notifier).refresh();
      final st = c.read(sessionListControllerProvider).valueOrNull!;
      expect(st.sessions, hasLength(1));
      expect(st.consecutiveFailures, 1);
      expect(st.refreshing, isFalse);
      expect(st.lastAttemptAt, isNotNull);
      expect(c.read(sessionListControllerProvider).hasError, isFalse);
    });

    test('连续失败退避计数递增，成功清零', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      final c = makeContainer(api);
      await c.read(sessionListControllerProvider.future);
      final notifier = c.read(sessionListControllerProvider.notifier);
      api.fetchError = NetworkException(NetworkExceptionKind.timedOut);
      await notifier.refresh();
      expect(
        c.read(sessionListControllerProvider).valueOrNull!.consecutiveFailures,
        1,
      );
      await notifier.refresh();
      expect(
        c.read(sessionListControllerProvider).valueOrNull!.consecutiveFailures,
        2,
      );
      api.fetchError = null;
      await notifier.refresh();
      expect(
        c.read(sessionListControllerProvider).valueOrNull!.consecutiveFailures,
        0,
      );
    });
  });

  group('refreshIfStale 门槛', () {
    test('10s 去重窗口内 no-op', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      final c = makeContainer(api);
      await c.read(sessionListControllerProvider.future);
      final n = c.read(sessionListControllerProvider.notifier);
      await n.refresh();
      expect(
        c.read(sessionListControllerProvider).valueOrNull!.lastRefreshAt,
        isNotNull,
      );
      final before = api.fetchCount;
      await n.refreshIfStale();
      expect(api.fetchCount, before);
    });

    test('force:true 跳过去重窗口', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      final c = makeContainer(api);
      await c.read(sessionListControllerProvider.future);
      final n = c.read(sessionListControllerProvider.notifier);
      await n.refresh();
      final before = api.fetchCount;
      await n.refreshIfStale(force: true);
      expect(api.fetchCount, before + 1);
    });

    test('搜索模式 no-op', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.searchResults['hi'] = [buildSession('r1', '命中')];
      final c = makeContainer(api);
      await c.read(sessionListControllerProvider.future);
      final n = c.read(sessionListControllerProvider.notifier);
      await n.search('hi');
      final before = api.fetchCount;
      await n.refreshIfStale(force: true);
      expect(api.fetchCount, before);
    });

    test('归档模式 no-op', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      final c = makeContainer(api);
      await c.read(sessionListControllerProvider.future);
      final n = c.read(sessionListControllerProvider.notifier);
      await n.setFilter(SessionListFilterMode.archived);
      final before = api.fetchCount;
      await n.refreshIfStale(force: true);
      expect(api.fetchCount, before);
    });

    test('并发互斥：刷新在途时 no-op', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.fetchGate = Completer<void>();
      final c = makeContainer(api);
      // build 会被 gate 卡住，改用不等待的刷新路径验证互斥：先让初始加载完成
      api.fetchGate!.complete();
      await c.read(sessionListControllerProvider.future);
      // 第二轮卡住
      api.fetchGate = Completer<void>();
      final n = c.read(sessionListControllerProvider.notifier);
      final fut = n.refresh();
      // 在途时再调 no-op
      await n.refreshIfStale(force: true);
      // 只应多一次（首个 refresh），期间的 stale 不应额外计数
      expect(api.fetchCount, 2);
      api.fetchGate!.complete();
      await fut;
      // 完成
    });
  });

  group('SessionAutoRefreshObserver / 桌面按钮可见性', () {
    Future<void> pump(
      WidgetTester tester,
      FakeSessionListApi api,
      Size size,
      TargetPlatform platform,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
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
            tasksControllerProvider.overrideWith(_EmptyTasksController.new),
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            onboardingApiFactoryProvider.overrideWithValue(
              (_, second) => FakeOnboardingLoginApi(),
            ),
            // 关键：测试的 appLifecycle/windowFocused 需覆盖 observer 的读取
          ],
          child: MediaQuery(
            data: MediaQueryData(size: size),
            child: CupertinoApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('桌面平台显示刷新按钮，移动平台不显示', (tester) async {
      // #149：刷新按钮已从列表头部移入侧栏品牌行。品牌行是宽屏侧栏的一部分，
      // 其可见性判据 = 平台（桌面专属，沿用原 showDesktopRefresh 语义）。
      // 注意「窄屏不显示」不再在此断言：SessionSidebar 是宽屏专用组件、自身
      // 不判宽窄（判宽窄的是 AdaptiveShell），窄屏下整条侧栏不渲染，
      // 该行为由 app 级外壳测试覆盖。
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      await pump(tester, api, const Size(1200, 800), TargetPlatform.windows);
      expect(
        find.byKey(const ValueKey('sidebar-brand-refresh')),
        findsOneWidget,
      );
      debugDefaultTargetPlatformOverride = null;

      final api3 = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      await pump(tester, api3, const Size(1200, 800), TargetPlatform.android);
      expect(find.byKey(const ValueKey('sidebar-brand-refresh')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('桌面刷新按钮 force 刷新', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      await pump(tester, api, const Size(1200, 800), TargetPlatform.windows);
      final before = api.fetchCount;
      await tester.tap(find.byKey(const ValueKey('sidebar-brand-refresh')));
      await tester.pumpAndSettle();
      expect(api.fetchCount, before + 1);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('#89 会话列表活跃流变化与常驻保活同步联动', () {
    testWidgets('列表出现正在生成的流式会话 → 触发 sessionStreamingSyncCallbackProvider', (
      tester,
    ) async {
      final syncCalls = <(int, List<String>)>[];
      const streamingSession = SessionSummary(
        sessionId: 's-stream-1',
        title: '流式生成会话',
        isStreaming: true,
      );
      final api = FakeSessionListApi(sessions: [streamingSession]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksControllerProvider.overrideWith(_EmptyTasksController.new),
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            onboardingApiFactoryProvider.overrideWithValue(
              (_, _) => FakeOnboardingLoginApi(),
            ),
            sessionStreamingSyncCallbackProvider.overrideWithValue((
              count,
              titles,
            ) {
              syncCalls.add((count, titles));
            }),
          ],
          child: const CupertinoApp(
            home: SessionAutoRefreshObserver(child: SizedBox()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(syncCalls, hasLength(1));
      expect(syncCalls.single.$1, 1);
      expect(syncCalls.single.$2, ['流式生成会话']);
    });

    testWidgets('刷新后活跃流集合无变化 → 幂等不重复触发回调；集合变化时触发', (tester) async {
      final syncCalls = <(int, List<String>)>[];
      const s1 = SessionSummary(
        sessionId: 's1',
        title: '会话 1',
        isStreaming: true,
      );
      final api = FakeSessionListApi(sessions: [s1]);

      late WidgetRef refHolder;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksControllerProvider.overrideWith(_EmptyTasksController.new),
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            onboardingApiFactoryProvider.overrideWithValue(
              (_, _) => FakeOnboardingLoginApi(),
            ),
            sessionStreamingSyncCallbackProvider.overrideWithValue((
              count,
              titles,
            ) {
              syncCalls.add((count, titles));
            }),
          ],
          child: CupertinoApp(
            home: SessionAutoRefreshObserver(
              child: Consumer(
                builder: (context, ref, _) {
                  refHolder = ref;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(syncCalls, hasLength(1));
      expect(syncCalls.first.$1, 1);

      // 刷新列表，但 s1 仍在生成中（集合相同：{'s1'}）
      await refHolder
          .read(sessionListControllerProvider.notifier)
          .refreshIfStale(force: true);
      await tester.pump();
      await tester.pump();

      // 集合不变 -> 不重复触发回调
      expect(syncCalls, hasLength(1));

      // 新增一个流式会话 s2，刷新后集合变为 {'s1', 's2'}
      const s2 = SessionSummary(
        sessionId: 's2',
        title: '会话 2',
        isStreaming: true,
      );
      api.sessions = [s1, s2];
      await refHolder
          .read(sessionListControllerProvider.notifier)
          .refreshIfStale(force: true);
      await tester.pump();
      await tester.pump();

      // 集合变化 -> 触发回调更新
      expect(syncCalls, hasLength(2));
      expect(syncCalls.last.$1, 2);
      expect(syncCalls.last.$2, ['会话 1', '会话 2']);
    });
  });
}
