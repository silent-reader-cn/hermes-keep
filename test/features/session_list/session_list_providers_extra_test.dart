import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/custom_header.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_session_list_api.dart';

/// 秒级时间戳辅助。
double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(
  String? id,
  String title, {
  bool pinned = false,
  bool archived = false,
  String? sourceLabel,
  String? projectId,
  double? at,
  int? messageCount,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    archived: archived,
    sourceLabel: sourceLabel,
    projectId: projectId,
    messageCount: messageCount,
    lastMessageAt: at ?? _sec(DateTime.now()),
  );
}

/// 固定返回注入连接的 active 控制器 stub（跳过异步加载，测试可控）。
class _StubActiveConnection extends ActiveConnectionController {
  _StubActiveConnection(this._connection);

  final ServerConnection? _connection;

  @override
  ServerConnection? build() => _connection;
}

/// 空项目 API stub：避免真实 [ApiClient] 发出 dio 请求残留超时 Timer。
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

/// 可编排的缓存 fake：默认成功，可切换为读取抛异常。
class _FakeCache extends Fake implements CacheService {
  _FakeCache({this.readResult = const [], this.throwOnRead = false});

  List<SessionSummary> readResult;
  bool throwOnRead;
  int readCount = 0;

  @override
  Future<List<SessionSummary>> readSessions() async {
    readCount++;
    if (throwOnRead) {
      throw NetworkException(NetworkExceptionKind.offline);
    }
    return readResult;
  }

  @override
  Future<void> writeSessions(List<SessionSummary> sessions) async {}
}

ServerConnection _builtinConnection({
  String baseUrl = 'http://test.local:30002',
  String? password,
  Map<String, String> customHeaders = const {},
}) {
  return ServerConnection(
    id: ServerConnection.builtinId,
    name: 'Builtin',
    baseUrl: baseUrl,
    password: password,
    customHeaders: customHeaders,
    kind: ConnectionKind.builtin,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// dio mock adapter：按路径返回预设响应，记录全部请求。
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({required this.responder});

  ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _buildAdapterClient(_MockAdapter adapter) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = adapter;
  final publicDio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  publicDio.httpClientAdapter = adapter;
  return ApiClient(baseUrl: 'http://hermes.local:8787', dio: dio, publicMediaDio: publicDio);
}

ProviderContainer _container(
  FakeSessionListApi api, {
  ServerConnection? active,
  FakeOnboardingLoginApi? loginApi,
  CacheService? cache,
  void Function(List<CustomHeader> headers)? onHeaders,
}) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      if (cache != null) cacheServiceProvider.overrideWithValue(cache),
      if (active != null)
        activeConnectionProvider.overrideWith(
          () => _StubActiveConnection(active),
        ),
      onboardingApiFactoryProvider.overrideWithValue((baseUrl, headers) {
        onHeaders?.call(headers);
        return loginApi ?? FakeOnboardingLoginApi();
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SessionListApiClient 生产实现（ApiClient 包装，l.72-149）', () {
    test('sessionListApiFactoryProvider 默认产出 SessionListApiClient', () {
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final factory = container.read(sessionListApiFactoryProvider);
      final api = factory(container.read(apiClientProvider));
      expect(api, isA<SessionListApiClient>());
    });

    test('fetchSessions / searchSessions / fetchWorkspaces 透传解码', () async {
      final adapter = _MockAdapter(
        responder: (options) {
          final path = options.path;
          if (path.contains('/api/sessions/search')) {
            return ResponseBody.fromString(
              '{"sessions":[{"session_id":"hit-1","title":"命中"}],"query":"q","count":1}',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (path.contains('/api/sessions')) {
            return ResponseBody.fromString(
              '{"sessions":[{"session_id":"s1","title":"A"}],"archived_count":2}',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (path.contains('/api/workspaces')) {
            return ResponseBody.fromString(
              '{"workspaces":[{"path":"/w/one","name":"one"}]}',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('{}', 200);
        },
      );
      final client = SessionListApiClient(_buildAdapterClient(adapter));

      final sessions = await client.fetchSessions(
        includeArchived: true,
        archivedLimit: 5,
      );
      expect(sessions.sessions?.single.sessionId, 's1');
      expect(sessions.archivedCount, 2);
      expect(
        adapter.requests.first.uri.queryParameters['include_archived'],
        '1',
      );

      final hits = await client.searchSessions(query: 'q');
      expect(hits.sessions?.single.sessionId, 'hit-1');
      expect(hits.count, 1);

      final workspaces = await client.fetchWorkspaces();
      expect(workspaces.single.path, '/w/one');
      expect(workspaces.single.name, 'one');
    });

    test('fetchWorkspaces：响应缺 workspaces 键 → 空列表兜底', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString(
          '{}',
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        ),
      );
      final client = SessionListApiClient(_buildAdapterClient(adapter));
      expect(await client.fetchWorkspaces(), isEmpty);
    });

    test('createSession：带 session detail → SessionSummary.fromDetail', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString(
          '{"session":{"session_id":"srv-9","title":"服务器新会话","workspace":"/w"}}',
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        ),
      );
      final client = SessionListApiClient(_buildAdapterClient(adapter));
      final created = await client.createSession(workspace: '/w');
      expect(created.sessionId, 'srv-9');
      expect(created.title, '服务器新会话');
      expect(created.workspace, '/w');
    });

    test('createSession：响应无 session detail → 空 SessionSummary 兜底', () async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString(
          '{}',
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        ),
      );
      final client = SessionListApiClient(_buildAdapterClient(adapter));
      final created = await client.createSession();
      expect(created.sessionId, isNull);
      expect(created.title, isNull);
    });

    test('变更类端点（pin/archive/delete/branch/move/status）逐一透传', () async {
      final adapter = _MockAdapter(
        responder: (options) {
          final path = options.path;
          if (path.contains('/api/session/status')) {
            return ResponseBody.fromString(
              '{"session_id":"s1","is_streaming":true,"active_stream_id":"st-7"}',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (path.contains('/api/session/branch')) {
            return ResponseBody.fromString(
              '{"session_id":"b-1","title":"分支"}',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString(
            '{"ok":true}',
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        },
      );
      final client = SessionListApiClient(_buildAdapterClient(adapter));

      expect((await client.pinSession(sessionId: 's1', pinned: true)).ok, isTrue);
      expect(
        (await client.archiveSession(sessionId: 's1', archived: true)).ok,
        isTrue,
      );
      expect((await client.deleteSession('s1')).ok, isTrue);
      final branch = await client.branchSession('s1');
      expect(branch.sessionId, 'b-1');
      expect(branch.title, '分支');
      expect(
        (await client.moveSession(sessionId: 's1', projectId: 'p-1')).ok,
        isTrue,
      );
      final status = await client.fetchSessionStatus('s1');
      expect(status.isStreaming, isTrue);
      expect(status.activeStreamId, 'st-7');

      final paths = adapter.requests.map((r) => r.path).toList();
      expect(paths.any((p) => p.contains('/api/session/pin')), isTrue);
      expect(paths.any((p) => p.contains('/api/session/archive')), isTrue);
      expect(paths.any((p) => p.contains('/api/session/delete')), isTrue);
      expect(paths.any((p) => p.contains('/api/session/branch')), isTrue);
      expect(paths.any((p) => p.contains('/api/session/move')), isTrue);
      expect(paths.any((p) => p.contains('/api/session/status')), isTrue);
    });
  });

  group('SessionListState / BatchMutationResult 纯逻辑', () {
    test('source 筛选：filterValue 为空 → 回落到全部会话', () {
      final state = SessionListState(
        sessions: [_session('s1', 'A'), _session('s2', 'B')],
        filterMode: SessionListFilterMode.source,
        filterValue: null,
        visibleCount: 50,
      );
      expect(state.displaySessions.length, 2);

      // 空串回落全部；纯空白不回落（filterValue 未 trim）→ 匹配不到任何来源
      expect(state.copyWith(filterValue: () => '').displaySessions.length, 2);
      expect(state.copyWith(filterValue: () => '   ').displaySessions, isEmpty);
    });

    test('project 筛选：filterValue 为空 → 回落到全部会话', () {
      final state = SessionListState(
        sessions: [_session('s1', 'A', projectId: 'p1')],
        filterMode: SessionListFilterMode.project,
        visibleCount: 50,
      );
      expect(state.displaySessions.length, 1);
      expect(state.copyWith(filterValue: () => '').displaySessions.length, 1);
      expect(
        state.copyWith(filterValue: () => 'p-other').displaySessions,
        isEmpty,
      );
    });

    test('toString 输出会话数 / 窗口 / 查询 / 命中数', () {
      final state = SessionListState(
        sessions: [_session('s1', 'A')],
        visibleCount: 50,
        searchQuery: 'q',
        searchResults: [_session('s2', 'B')],
      );
      final text = state.toString();
      expect(text, contains('sessions: 1'));
      expect(text, contains('visibleCount: 50'));
      expect(text, contains('searchQuery: q'));
      expect(text, contains('searchResults: 1'));

      expect(
        const BatchMutationResult(succeeded: 2, failed: 1).toString(),
        'BatchMutationResult(succeeded: 2, failed: 1)',
      );
    });

    test('hasMore / sessionListVisibleSessionsProvider 分块窗口', () async {
      final container = ProviderContainer(
        overrides: [
          sessionListControllerProvider.overrideWith(() => _SeedController()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionListControllerProvider.future);
      expect(container.read(sessionListVisibleSessionsProvider).length, 2);
      expect(container.read(sessionListRefreshingProvider), isFalse);
    });
  });

  group('SessionListController 调度 / 退避 / 去重', () {
    test('eventsDebounceTimerForTesting：事件到达后置位，800ms 后复位', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      expect(controller.eventsDebounceTimerForTesting, isNull);
      controller.onSessionsChangedEvent(reason: 'update', sessionId: 's1');
      expect(controller.eventsDebounceTimerForTesting, isNotNull);
      // 二次事件重置计时器（合并语义）。
      controller.onSessionsChangedEvent(reason: 'update2');
      expect(controller.eventsDebounceTimerForTesting, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(controller.eventsDebounceTimerForTesting, isNull);
      await pumpEventQueue();
    });

    test('scheduleAutoRefresh / cancelAutoRefresh / currentBackoffDelay', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      expect(controller.currentBackoffDelay, const Duration(seconds: 30));
      controller.scheduleAutoRefresh(period: const Duration(hours: 1));
      controller.scheduleAutoRefresh();
      controller.cancelAutoRefresh();
      controller.cancelFocusDebounce();

      api.fetchError = HttpException(500, 'boom');
      await controller.refresh();
      expect(api.fetchCount, 2);
      expect(controller.currentBackoffDelay, const Duration(seconds: 60));
      controller.cancelAutoRefresh();
    });

    test('scheduleAutoRefresh：到期后自动触发一次条件刷新', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);
      expect(api.fetchCount, 1);

      controller.scheduleAutoRefresh(period: const Duration(milliseconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await pumpEventQueue();

      expect(api.fetchCount, greaterThanOrEqualTo(2));
      expect(controller.isRefreshInFlightForTesting, isFalse);
      controller.cancelAutoRefresh();
      controller.cancelFocusDebounce();
    });

    test('scheduleFocusRefresh：1s 后触发一次条件刷新', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);
      expect(api.fetchCount, 1);

      controller.scheduleFocusRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.cancelFocusDebounce();
      // 取消后不再触发刷新。
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(api.fetchCount, 1);

      controller.scheduleFocusRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(api.fetchCount, 2);
      await pumpEventQueue();
    });

    test('refreshIfStale：错误态（无数据）强制刷新', () async {
      final api = FakeSessionListApi()..fetchError = HttpException(500, 'x');
      final container = _container(api);
      await expectLater(
        container.read(sessionListControllerProvider.future),
        throwsA(isA<HttpException>()),
      );
      final controller = container.read(sessionListControllerProvider.notifier);

      api.fetchError = null;
      api.sessions = [_session('s1', 'A')];
      await controller.refreshIfStale();
      expect(api.fetchCount, 2);
      expect(
        container.read(sessionListControllerProvider).valueOrNull?.sessions.length,
        1,
      );
    });

    test('refresh 在途时再次 refresh → 置脏标记，收尾自动补拉一次', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final gate = Completer<void>();
      api.fetchGate = gate;
      final first = controller.refresh();
      await pumpEventQueue();
      expect(controller.isRefreshInFlightForTesting, isTrue);

      await controller.refresh();
      expect(controller.isRefreshDirtyForTesting, isTrue);

      api.fetchGate = null;
      gate.complete();
      await first;
      await pumpEventQueue();
      expect(controller.isRefreshInFlightForTesting, isFalse);
      // 初始 build 1 次 + 首轮 + 补拉 1 次
      expect(api.fetchCount, greaterThanOrEqualTo(3));
    });

    test('refresh 失败：已有数据 → 保留数据并累加失败次数（不转错误态）', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      api.fetchError = HttpException(500, 'boom');
      await controller.refresh();

      final async = container.read(sessionListControllerProvider);
      expect(async.hasError, isFalse);
      final state = async.valueOrNull!;
      expect(state.sessions.length, 1);
      expect(state.refreshing, isFalse);
      expect(state.consecutiveFailures, 1);
      expect(state.actionError, isNull);
    });

    test('refresh 失败：无数据 → 转 AsyncError', () async {
      final api = FakeSessionListApi()..fetchError = HttpException(500, 'boom');
      final container = _container(api);
      await expectLater(
        container.read(sessionListControllerProvider.future),
        throwsA(isA<HttpException>()),
      );
      final controller = container.read(sessionListControllerProvider.notifier);

      await controller.refresh();
      final async = container.read(sessionListControllerProvider);
      expect(async.hasError, isTrue);
      expect(async.error, isA<HttpException>());
    });

    test('容器销毁时取消阶梯补拉计时器', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        ],
      );
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);
      // 目标会话不在列表 → 阶梯补拉会挂三个计时器。
      await controller.handleNewChatSession('missing-session');
      container.dispose();
      await pumpEventQueue();
    });

    test('_overlayStreaming：无 id 会话保持原样，有 id 会话叠加流式', () async {
      final api = FakeSessionListApi(
        sessions: [
          _session(null, '无 id 占位'),
          _session('s1', 'A'),
        ],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);
      controller.markStreaming('s1', true, activeStreamId: 'st-1');

      await controller.refresh();
      final sessions =
          container.read(sessionListControllerProvider).valueOrNull!.sessions;
      final byId = {for (final s in sessions) s.sessionId: s};
      expect(byId['s1']!.isStreaming, isTrue);
      expect(byId['s1']!.activeStreamId, 'st-1');
      expect(byId[null]!.title, '无 id 占位');
    });
  });

  group('缓存回退与自动重登', () {
    test('可缓存网络错误 + 缓存读取抛异常 → 向上抛原错误', () async {
      final api = FakeSessionListApi()
        ..fetchError = NetworkException(NetworkExceptionKind.offline);
      final cache = _FakeCache(throwOnRead: true);
      final container = _container(
        api,
        cache: cache,
        active: _builtinConnection(),
      );
      await expectLater(
        container.read(sessionListControllerProvider.future),
        throwsA(isA<NetworkException>()),
      );
      expect(cache.readCount, 1);
    });

    test('可缓存网络错误 + 缓存命中（远程连接）→ actionError 提示离线缓存', () async {
      final api = FakeSessionListApi()
        ..fetchError = NetworkException(NetworkExceptionKind.timedOut);
      final cache = _FakeCache(readResult: [_session('c1', '缓存会话')]);
      final container = _container(
        api,
        cache: cache,
        active: ServerConnection(
          id: 'conn-remote',
          name: 'Remote',
          baseUrl: 'http://test.local:30002',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final state = await container.read(sessionListControllerProvider.future);
      expect(state.sessions.single.sessionId, 'c1');
      expect(state.actionError, '离线缓存：当前显示最近缓存的会话');
      expect(state.visibleCount, 1);
    });

    test('401 → 自动重登一次并把自定义头透传给登录工厂', () async {
      final api = FakeSessionListApi()
        ..fetchError = const UnauthorizedException()
        ..fetchErrorCap = 1
        ..sessions = [_session('s1', 'A')];
      final loginApi = FakeOnboardingLoginApi();
      List<CustomHeader>? captured;
      final container = _container(
        api,
        loginApi: loginApi,
        active: _builtinConnection(
          password: 'secret',
          customHeaders: const {'X-Api-Key': 'tok'},
        ),
        onHeaders: (headers) => captured = headers,
      );
      final state = await container.read(sessionListControllerProvider.future);
      expect(state.sessions.single.sessionId, 's1');
      expect(loginApi.loginCalls, 1);
      expect(loginApi.lastPassword, 'secret');
      expect(captured, isNotNull);
      expect(captured!.single.name, 'X-Api-Key');
      expect(captured!.single.value, 'tok');
    });
  });

  group('筛选 / 归档 / 搜索失败分支', () {
    test('fetchArchived 抛 ApiException → 保留旧数据只写 actionError', () async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', 'A', archived: true)],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      api.fetchError = HttpException(500, 'archive boom');
      await controller.setFilter(SessionListFilterMode.archived);

      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.filterMode, SessionListFilterMode.archived);
      expect(state.archivedSessions, isEmpty);
      expect(state.actionError, '服务器返回 HTTP 500。');
    });

    test('fetchArchived 成功 → 写入归档列表与计数、重置窗口', () async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', 'A', archived: true)],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      await controller.fetchArchived();
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.archivedSessions.single.sessionId, 's1');
      expect(state.archivedCount, 1);
      expect(state.visibleCount, 1);
    });

    test('search 抛 ApiException → 清空命中并写 actionError', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')])
        ..searchError = HttpException(503, 'search boom');
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      await controller.search('keyword');
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.searchQuery, 'keyword');
      expect(state.searchResults, isEmpty);
      expect(state.isSearching, isFalse);
      expect(state.actionError, '服务器返回 HTTP 503。');
    });
  });

  group('多选与批量操作', () {
    test('selectAllInSection 收集当前视图全部 id 并进入多选', () async {
      final api = FakeSessionListApi(
        sessions: [
          _session('s1', 'A'),
          _session('s2', 'B'),
          _session(null, '无 id 行', messageCount: 3),
        ],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.selectAllInSection();
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.selectedSessionIds, {'s1', 's2'});
      expect(state.isSelectionMode, isTrue);

      controller.clearSelection();
      final cleared =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(cleared.selectedSessionIds, isEmpty);
      expect(cleared.isSelectionMode, isFalse);
    });

    test('batchArchive 部分失败 → 成功项移出列表并写 actionError', () async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', 'A'), _session('s2', 'B')],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.toggleSelection('s1');
      controller.toggleSelection('s2');
      api.archiveError = HttpException(500, 'boom');
      final result = await controller.batchArchive();
      expect(result.succeeded, 0);
      expect(result.failed, 2);
      expect(api.archiveCalls, ['s1:true', 's2:true']);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '批量归档：2 个会话操作失败',
      );
    });

    test('batchArchive 恢复语义（archived: false）+ 全成功清空勾选', () async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', 'A', archived: true)],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.toggleSelection('s1');
      final result = await controller.batchArchive(archived: false);
      expect(result.succeeded, 1);
      expect(result.failed, 0);
      expect(api.archiveCalls, ['s1:false']);
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.selectedSessionIds, isEmpty);
      expect(state.isSelectionMode, isFalse);
    });

    test('batchDelete 失败 → actionError 文案', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')])
        ..deleteError = HttpException(500, 'boom');
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.toggleSelection('s1');
      final result = await controller.batchDelete();
      expect(result.failed, 1);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '批量删除：1 个会话失败',
      );
    });

    test('batchMove 失败 → actionError 文案；空勾选 → 空结果', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')])
        ..moveError = HttpException(500, 'boom');
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      expect((await controller.batchMove('p1')).succeeded, 0);
      controller.toggleSelection('s1');
      final result = await controller.batchMove('p1');
      expect(result.failed, 1);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '批量移动：1 个会话失败',
      );
    });

    test('batchMove 成功 → 本地刷新 projectId 且搜索命中同步', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      api.searchResults['k'] = [_session('s1', 'A')];
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      await controller.search('k');
      controller.toggleSelection('s1');
      final result = await controller.batchMove('p-9');
      expect(result.succeeded, 1);
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.single.projectId, 'p-9');
      expect(state.searchResults!.single.projectId, 'p-9');
    });
  });

  group('行操作：缺 ID 与失败分支', () {
    late FakeSessionListApi api;
    late ProviderContainer container;
    late SessionListController controller;

    setUp(() async {
      api = FakeSessionListApi(
        sessions: [
          _session(null, '无 id 行', messageCount: 4),
          _session('s1', 'A'),
        ],
      );
      container = _container(api);
      await container.read(sessionListControllerProvider.future);
      controller = container.read(sessionListControllerProvider.notifier);
    });

    test('会话无 sessionId → 五个行操作均回报「服务器未提供会话 ID」', () async {
      final noId = const SessionSummary(title: '无 id 行');
      expect(await controller.moveToProject(noId, 'p1'), isFalse);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器未提供会话 ID',
      );
      await controller.clearActionError();

      expect(await controller.setPinned(noId, true), isFalse);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器未提供会话 ID',
      );
      await controller.clearActionError();

      expect(await controller.setArchived(noId, true), isFalse);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器未提供会话 ID',
      );
      await controller.clearActionError();

      expect(await controller.delete(noId), isFalse);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器未提供会话 ID',
      );
      await controller.clearActionError();

      expect(await controller.branch(noId), isNull);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器未提供会话 ID',
      );
    });

    test('moveToProject / setArchived / delete / branch 失败 → actionError', () async {
      final target = const SessionSummary(sessionId: 's1', title: 'A');

      api.moveError = HttpException(500, 'move boom');
      expect(await controller.moveToProject(target, 'p1'), isFalse);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器返回 HTTP 500。',
      );
      await controller.clearActionError();

      api.archiveError = HttpException(500, 'archive boom');
      expect(await controller.setArchived(target, true), isFalse);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器返回 HTTP 500。',
      );
      await controller.clearActionError();

      api.deleteError = HttpException(500, 'delete boom');
      expect(await controller.delete(target), isFalse);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器返回 HTTP 500。',
      );
      await controller.clearActionError();

      api.branchError = HttpException(500, 'branch boom');
      expect(await controller.branch(target), isNull);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器返回 HTTP 500。',
      );
    });

    test('setArchived(false)：本地反归档 + 归档视图移除 + 计数递减', () async {
      final archived = _session('s1', 'A', archived: true);
      // 归档视图拉到该行；普通列表也含同一 id（模拟服务端两侧一致）。
      api.sessions = [archived];
      await controller.fetchArchived();
      api.sessions = [_session('s1', 'A')];
      await controller.refresh();

      expect(await controller.setArchived(archived, false), isTrue);
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.single.archived, isFalse);
      expect(state.archivedSessions, isEmpty);
      expect(state.archivedCount, 0);
    });

    test('setArchived(true)：从普通列表移除并递增计数', () async {
      final target = const SessionSummary(sessionId: 's1', title: 'A');
      expect(await controller.setArchived(target, true), isTrue);
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.any((s) => s.sessionId == 's1'), isFalse);
      expect(state.archivedCount, 1);
    });

    test('delete → 普通 / 搜索命中 / 归档三视图同时移除', () async {
      final target = const SessionSummary(sessionId: 's1', title: 'A');
      api.searchResults['k'] = [target];
      await controller.search('k');
      await controller.fetchArchived();

      expect(await controller.delete(target), isTrue);
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.any((s) => s.sessionId == 's1'), isFalse);
      expect(state.searchResults, isEmpty);
      expect(state.archivedSessions, isEmpty);
    });

    test('createSession 无 id → actionError；有 id 时插入顶部并覆盖流式', () async {
      api.createdSession = const SessionSummary(title: '无 id');
      expect(await controller.createSession(), isNull);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '服务器未返回会话 ID',
      );
      await controller.clearActionError();

      controller.markStreaming('new-1', true, activeStreamId: 'st-new');
      api.createdSession = const SessionSummary(sessionId: 'new-1', title: '新会话');
      expect(await controller.createSession(), 'new-1');
      final inserted =
          container.read(sessionListControllerProvider).valueOrNull!.sessions.first;
      expect(inserted.sessionId, 'new-1');
      expect(inserted.isStreaming, isTrue);
      expect(inserted.activeStreamId, 'st-new');
    });

    test('branch：服务器未返回 id → actionError；缺标题时补 (fork) 后缀', () async {
      api.branchResponse = const SessionBranchResponse(error: '分支失败');
      expect(
        await controller.branch(const SessionSummary(sessionId: 's1')),
        isNull,
      );
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        '分支失败',
      );
      await controller.clearActionError();

      controller.markStreaming('branch-1', true, activeStreamId: 'st-b');
      api.branchResponse = const SessionBranchResponse(sessionId: 'branch-1');
      expect(
        await controller.branch(const SessionSummary(sessionId: 's1', title: '源会话')),
        'branch-1',
      );
      final head =
          container.read(sessionListControllerProvider).valueOrNull!.sessions.first;
      expect(head.title, '源会话 (fork)');
      expect(head.isStreaming, isTrue);
    });

    test('setPinned 成功 → 行内 pinned 翻转（三视图同步）', () async {
      final target = const SessionSummary(sessionId: 's1', title: 'A');
      api.searchResults['k'] = [target];
      await controller.search('k');
      await controller.fetchArchived();

      expect(await controller.setPinned(target, true), isTrue);
      final state =
          container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.firstWhere((s) => s.sessionId == 's1').pinned, isTrue);
      expect(state.searchResults!.single.pinned, isTrue);
      expect(api.pinCalls, ['s1:true']);
    });
  });

  group('markStreaming 与后台纠偏', () {
    test('markStreaming 同时刷新普通列表与搜索命中', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      api.searchResults['k'] = [_session('s1', 'A')];
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);
      await controller.search('k');

      controller.markStreaming('s1', true, activeStreamId: 'st-1');
      var state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.single.isStreaming, isTrue);
      expect(state.searchResults!.single.isStreaming, isTrue);

      controller.markStreaming('', true);
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.single.isStreaming, isTrue);

      controller.markStreaming('s1', false);
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.single.isStreaming, isFalse);
      expect(state.searchResults!.single.isStreaming, isFalse);
    });

    test('后台校验：服务端 activeStreamId 不同 → 覆盖本地乐观值', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      api.statusResponses['s1'] = const SessionStatusResponse(
        sessionId: 's1',
        isStreaming: true,
        activeStreamId: 'server-9',
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.markStreaming(
        's1',
        true,
        activeStreamId: 'local-1',
        verifyInBackground: true,
      );
      await pumpEventQueue();
      expect(api.statusCalls, ['s1']);
      final session =
          container.read(sessionListControllerProvider).valueOrNull!.sessions.single;
      expect(session.activeStreamId, 'server-9');
    });

    test('后台校验：服务端确认为非流式 → 纠偏清空', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      api.statusResponses['s1'] = const SessionStatusResponse(sessionId: 's1');
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.markStreaming(
        's1',
        true,
        activeStreamId: 'local-1',
        verifyInBackground: true,
      );
      await pumpEventQueue();
      final session =
          container.read(sessionListControllerProvider).valueOrNull!.sessions.single;
      expect(session.isStreaming, isFalse);
    });
  });

  group('聊天页外部同步（applyExternal*）', () {
    late FakeSessionListApi api;
    late ProviderContainer container;
    late SessionListController controller;

    setUp(() async {
      api = FakeSessionListApi(
        sessions: [
          _session('s1', '旧标题'),
          _session('s2', 'B'),
          _session('s3', '已归档行', archived: true),
        ],
      );
      api.searchResults['k'] = [_session('s1', '旧标题')];
      container = _container(api);
      await container.read(sessionListControllerProvider.future);
      controller = container.read(sessionListControllerProvider.notifier);
      // 顺序：先取归档视图（archivedSessions 非空），再进搜索模式
      // （searchResults 非空；refresh 会把搜索态清空，故不放在最后）。
      await controller.fetchArchived();
      await controller.search('k');
    });

    SessionListState currentState() =>
        container.read(sessionListControllerProvider).valueOrNull!;

    test('applyExternalRename：空 id / 空标题 no-op，正常则三视图改标题', () {
      final before = currentState().sessions.length;
      controller.applyExternalRename('', 'X');
      controller.applyExternalRename('s1', '   ');
      expect(currentState().sessions.length, before);
      expect(currentState().sessions.first.title, '旧标题');

      controller.applyExternalRename('s1', ' 新标题 ');
      expect(currentState().sessions.firstWhere((s) => s.sessionId == 's1').title, '新标题');
      expect(currentState().searchResults!.single.title, '新标题');
    });

    test('applyExternalPinned：置顶同步并清零流式标记', () {
      controller.applyExternalPinned('s1', true);
      expect(currentState().sessions.firstWhere((s) => s.sessionId == 's1').pinned, isTrue);
      controller.applyExternalPinned('', true);
      controller.applyExternalPinned('absent', true);
      expect(currentState().sessions.length, 2);
    });

    test('applyExternalArchived(true)：三视图移除 + 计数 +1', () async {
      final before = currentState().archivedCount!;
      controller.applyExternalArchived('s1', true);
      expect(currentState().sessions.any((s) => s.sessionId == 's1'), isFalse);
      expect(currentState().searchResults, isEmpty);
      await pumpEventQueue();
      expect(currentState().archivedCount, before + 1);

      controller.applyExternalArchived('', true);
      expect(currentState().sessions.length, 1);
    });

    test('applyExternalArchived(false)：反归档并递减计数', () async {
      expect(currentState().archivedCount, 1);
      controller.applyExternalArchived('s1', false);
      expect(
        currentState().sessions.firstWhere((s) => s.sessionId == 's1').archived,
        isFalse,
      );
      await pumpEventQueue();
      expect(currentState().archivedCount, 0);
    });

    test('applyExternalDeleted：三视图移除 + 取消勾选', () {
      controller.toggleSelection('s1');
      controller.applyExternalDeleted('s1');
      expect(currentState().sessions.any((s) => s.sessionId == 's1'), isFalse);
      expect(currentState().searchResults, isEmpty);
      expect(currentState().selectedSessionIds, isEmpty);

      controller.applyExternalDeleted('');
      expect(currentState().sessions.length, 1);
    });

    test('applyExternalBranched：缺时间戳补现在并置顶；重复 id no-op', () {
      controller.applyExternalBranched(
        const SessionSummary(sessionId: 'b-1', title: '分支'),
      );
      expect(currentState().sessions.first.sessionId, 'b-1');
      expect(currentState().sessions.first.createdAt, isNotNull);

      controller.applyExternalBranched(
        const SessionSummary(sessionId: 'b-1', title: '分支'),
      );
      expect(currentState().sessions.where((s) => s.sessionId == 'b-1').length, 1);

      controller.applyExternalBranched(const SessionSummary(title: '无 id'));
      controller.applyExternalBranched(
        const SessionSummary(sessionId: 'b-2', title: '带时间'),
      );
      expect(currentState().sessions.first.sessionId, 'b-2');
    });

    test('applyExternalBranched：命中本地流式表 → 新行带流式态', () {
      controller.markStreaming('b-3', true, activeStreamId: 'st-3');
      controller.applyExternalBranched(
        const SessionSummary(sessionId: 'b-3', title: '流式分支'),
      );
      final head = currentState().sessions.first;
      expect(head.sessionId, 'b-3');
      expect(head.isStreaming, isTrue);
      expect(head.activeStreamId, 'st-3');
    });

    test('applyExternal*：状态未就绪（仍在加载）时全部静默 no-op', () async {
      final loading = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final gate = Completer<void>();
      loading.fetchGate = gate;
      final other = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => loading),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        ],
      );
      addTearDown(other.dispose);
      // 不 await：状态保持 AsyncLoading（valueOrNull == null）。
      unawaited(other.read(sessionListControllerProvider.future));
      final c = other.read(sessionListControllerProvider.notifier);
      expect(other.read(sessionListControllerProvider).valueOrNull, isNull);

      c.applyExternalRename('s1', 'X');
      c.applyExternalPinned('s1', true);
      c.applyExternalArchived('s1', true);
      c.applyExternalDeleted('s1');
      c.applyExternalBranched(const SessionSummary(sessionId: 'x'));
      expect(other.read(sessionListControllerProvider).valueOrNull, isNull);

      gate.complete();
      await pumpEventQueue();
      // 加载完成后仅第 1 条仍在列表（上面的 no-op 没有写入任何行）。
      expect(
        other.read(sessionListControllerProvider).valueOrNull!.sessions.length,
        1,
      );
    });
  });

  group('分区与工作区排序补充分支', () {
    test('buildSessionSections：无工作区的会话落入「其他」', () {
      final sections = buildSessionSections([
        const SessionSummary(sessionId: 't1', title: '无工作区'),
      ]);
      expect(sections.single.title, '其他');
      expect(sections.single.sessions.single.sessionId, 't1');
    });

    test('rankWorkspaces：剔除空 path；次数优先、其次最近', () {
      final ranked = rankWorkspaces(
        registered: const [
          WorkspaceRoot(path: '', name: '空'),
          WorkspaceRoot(path: '/w/a', name: 'A'),
          WorkspaceRoot(path: '/w/b', name: 'B'),
        ],
        sessions: [
          _session('s1', 'x', at: 100),
          _session('s2', 'y', at: 200),
          _session('s3', 'z', at: 300),
        ].map((s) => s.copyWith(workspace: s.sessionId == 's3' ? '/w/b' : '/w/a')).toList(),
      );
      expect(ranked.map((w) => w.path).toList(), ['/w/a', '/w/b']);
      expect(
        rankWorkspaces(registered: const [], sessions: const []),
        isEmpty,
      );
    });
  });
}

/// 直接产出带数据的 AsyncData 的 seed 控制器（分块窗口断言用）。
class _SeedController extends SessionListController {
  @override
  Future<SessionListState> build() async {
    return SessionListState(
      sessions: [_session('s1', 'A'), _session('s2', 'B')],
      visibleCount: 2,
    );
  }
}
