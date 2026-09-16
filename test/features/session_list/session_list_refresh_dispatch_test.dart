// #20 回归守卫（页面层）：下拉刷新必须按当前视图态分派。
//
// 控制器层（session_list_refresh_viewstate_test.dart）钉住「刷新后视图态保留」；
// 本文件钉住页面层的分派语义 —— `_onRefresh` 不能无脑调 refresh()：
// - 搜索态 → 重跑当前搜索（refresh() 拉的是普通列表，语义不符）；
// - 归档态 → 重拉归档列表（同上）。
//
// 验证方式：直接取 CupertinoSliverRefreshControl 的 onRefresh 回调调用，
// 避免依赖下拉手势的物理参数；并以 api 侧调用计数为硬证据。

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_session_list_api.dart';

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(String id, String title, {bool archived = false}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    archived: archived,
    lastMessageAt: _sec(DateTime.now()),
  );
}

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(middle: Text('chat-$sessionId')),
    child: const SizedBox(),
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
  Future<void> pumpList(WidgetTester tester, FakeSessionListApi api) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
        GoRoute(
          path: '/chat/:sessionId',
          builder: (_, state) =>
              _ChatStub(sessionId: state.pathParameters['sessionId'] ?? ''),
        ),
        GoRoute(path: '/chat', builder: (_, _) => const _ChatStub(sessionId: '')),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
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

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SessionListPage)));

  /// 触发下拉刷新的 onRefresh 回调（不依赖手势物理参数）。
  Future<void> triggerRefresh(WidgetTester tester) async {
    // 未激活的 sliver 会被视口判为 offstage，必须 skipOffstage: false 才找得到
    //（E3 补测报告记录的同款坑）。
    final control = tester.widget<CupertinoSliverRefreshControl>(
      find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
    );
    expect(control.onRefresh, isNotNull, reason: '应挂载下拉刷新回调');
    await control.onRefresh!();
  }

  SessionListState stateOf(ProviderContainer c) {
    final s = c.read(sessionListControllerProvider).valueOrNull;
    expect(s, isNotNull);
    return s!;
  }

  group('#20 下拉刷新按视图态分派（页面层守卫）', () {
    testWidgets('搜索态：下拉刷新重跑搜索，不退出搜索模式', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      api.searchResults['alpha'] = [_session('s9', '命中')];
      await pumpList(tester, api);
      final container = containerOf(tester);
      final c = container.read(sessionListControllerProvider.notifier);

      await c.search('alpha');
      await tester.pumpAndSettle();
      expect(api.searchCount, 1, reason: '进入搜索态应查一次');

      await triggerRefresh(tester);
      await tester.pumpAndSettle();

      final st = stateOf(container);
      expect(st.searchQuery, 'alpha', reason: '搜索态下拉刷新不该退出搜索');
      expect(api.searchCount, 2, reason: '应重跑当前搜索而非拉普通列表');
    });

    testWidgets('归档态：下拉刷新走归档重拉，不退回「全部」', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      await pumpList(tester, api);
      final container = containerOf(tester);
      final c = container.read(sessionListControllerProvider.notifier);

      await c.setFilter(SessionListFilterMode.archived);
      await tester.pumpAndSettle();
      expect(api.lastFetchedArchived, isTrue, reason: '切归档应拉过归档');

      // 置回 false，以便证明「下拉确实又拉了一次归档」
      api.lastFetchedArchived = false;
      final fetchBefore = api.fetchCount;

      await triggerRefresh(tester);
      await tester.pumpAndSettle();

      final st = stateOf(container);
      expect(
        st.filterMode,
        SessionListFilterMode.archived,
        reason: '归档态下拉刷新不该退回「全部」',
      );
      expect(api.lastFetchedArchived, isTrue, reason: '应重拉归档列表');
      expect(api.fetchCount, greaterThan(fetchBefore));
    });
  });
}
