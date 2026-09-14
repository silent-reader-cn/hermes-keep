import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';
import 'package:hermes_ui/features/session_list/session_events_client.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_session_list_api.dart';

/// 记录请求的假 HttpClientAdapter。
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.responder});

  final ResponseBody Function(RequestOptions options) responder;
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

class _StubActiveConnection extends ActiveConnectionController {
  _StubActiveConnection();
  @override
  ServerConnection? build() => ServerConnection(
        id: 'conn-test',
        name: 'Test',
        baseUrl: 'http://hermes.local:30002',
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

ProviderContainer _createContainer({
  required FakeSessionListApi sessionApi,
  Dio? dio,
}) {
  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(
          baseUrl: 'http://hermes.local:30002',
          dio: dio,
        ),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      activeConnectionProvider.overrideWith(() => _StubActiveConnection()),
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => FakeOnboardingLoginApi(),
      ),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    enableSessionAutoRefresh = true;
  });

  tearDown(() {
    enableSessionAutoRefresh = true;
  });

  group('SessionEventsSseClient 协议与事件解析', () {
    test('推 sessions_changed 帧 → 触发 onSessionsChanged 回调', () async {
      final streamController = StreamController<Uint8List>();
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody(
          streamController.stream,
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      final events = <Map<String, dynamic>>[];
      final client = SessionEventsSseClient(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        onSessionsChanged: ({version, reason, profile, sessionId}) {
          events.add({
            'version': version,
            'reason': reason,
            'profile': profile,
            'sessionId': sessionId,
          });
        },
      );

      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.first.path,
        'http://hermes.local:30002/api/sessions/events',
      );

      // 推送有效帧
      streamController.add(
        utf8.encode(
          'event: sessions_changed\n'
          'data: {"type":"session_new","version":1,"reason":"new","profile":"p1","session_id":"s-101"}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events, hasLength(1));
      expect(events.first['version'], 1);
      expect(events.first['reason'], 'new');
      expect(events.first['profile'], 'p1');
      expect(events.first['sessionId'], 's-101');

      client.stop();
      await streamController.close();
    });

    test('version 单调去重：version <= lastVersion 忽略，> lastVersion 派发', () async {
      final streamController = StreamController<Uint8List>();
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody(
          streamController.stream,
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      final versions = <int?>[];
      final client = SessionEventsSseClient(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        onSessionsChanged: ({version, reason, profile, sessionId}) {
          versions.add(version);
        },
      );

      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 初始 version: 5
      streamController.add(
        utf8.encode('event: sessions_changed\ndata: {"version":5}\n\n'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(versions, [5]);
      expect(client.lastVersion, 5);

      // 回退 version: 3 (<= 5) → 忽略
      streamController.add(
        utf8.encode('event: sessions_changed\ndata: {"version":3}\n\n'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(versions, [5]);

      // 重复 version: 5 (<= 5) → 忽略
      streamController.add(
        utf8.encode('event: sessions_changed\ndata: {"version":5}\n\n'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(versions, [5]);

      // 递增 version: 8 (> 5) → 派发
      streamController.add(
        utf8.encode('event: sessions_changed\ndata: {"version":8}\n\n'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(versions, [5, 8]);
      expect(client.lastVersion, 8);

      // 无 version → 视为有效（宁多刷不漏刷），不改变 lastVersion
      streamController.add(
        utf8.encode('event: sessions_changed\ndata: {"reason":"flush"}\n\n'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(versions, [5, 8, null]);
      expect(client.lastVersion, 8);

      client.stop();
      await streamController.close();
    });

    test('keepalive 与其他事件不触发回调，畸形帧不崩溃且视为有效刷新', () async {
      final streamController = StreamController<Uint8List>();
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody(
          streamController.stream,
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      var callbackCount = 0;
      final client = SessionEventsSseClient(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        onSessionsChanged: ({version, reason, profile, sessionId}) {
          callbackCount++;
        },
      );

      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 1. keepalive 注释帧 (: keepalive)
      streamController.add(utf8.encode(': keepalive\n\n'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callbackCount, 0);

      // 2. 其他事件名 (ping)
      streamController.add(utf8.encode('event: ping\ndata: pong\n\n'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callbackCount, 0);

      // 3. 畸形 JSON 帧 → 不崩溃，视为有效（宁多刷不漏刷）
      streamController.add(
        utf8.encode('event: sessions_changed\ndata: not-json-at-all\n\n'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callbackCount, 1);

      // 4. 空 payload 帧 → 视为有效
      streamController.add(utf8.encode('event: sessions_changed\ndata: \n\n'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callbackCount, 2);

      client.stop();
      await streamController.close();
    });

    test('开关关闭 → 不建连', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('', 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      final client = SessionEventsSseClient(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        isEnabled: () => false,
        onSessionsChanged: ({version, reason, profile, sessionId}) {},
      );

      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(adapter.requests, isEmpty);
      expect(client.isRunning, isFalse);
    });

    test('断线重连：指数退避并于重连成功后立即触发回调（补空洞）', () {
      fakeAsync((async) {
        var connectAttempts = 0;
        final streams = <StreamController<Uint8List>>[];

        final adapter = _RecordingAdapter(
          responder: (_) {
            connectAttempts++;
            if (connectAttempts == 1) {
              // 第一次：连接成功后立即断开
              final sc = StreamController<Uint8List>();
              streams.add(sc);
              unawaited(sc.close());
              return ResponseBody(sc.stream, 200);
            } else if (connectAttempts == 2) {
              // 第二次：HTTP 500 失败
              return ResponseBody.fromString('error', 500);
            } else {
              // 第三次：重连成功
              final sc = StreamController<Uint8List>();
              streams.add(sc);
              return ResponseBody(sc.stream, 200);
            }
          },
        );
        final dio = Dio()..httpClientAdapter = adapter;

        final reasons = <String?>[];
        final client = SessionEventsSseClient(
          dio: dio,
          baseUrl: 'http://hermes.local:30002',
          onSessionsChanged: ({version, reason, profile, sessionId}) {
            reasons.add(reason);
          },
        );

        client.start();
        async.elapse(Duration.zero);
        expect(connectAttempts, 1);

        // 第一次流关闭后调度重连，退避 1s * 2^0 = 1s
        async.elapse(const Duration(seconds: 1));
        expect(connectAttempts, 2);

        // 第二次 500 失败后调度下一次重连，退避 1s * 2^1 = 2s
        async.elapse(const Duration(seconds: 2));
        expect(connectAttempts, 3);

        // 成功重连后立即触发一次 'reconnect' 补空洞
        expect(reasons, contains('reconnect'));

        client.stop();
        client.dispose();
      });
    });
  });

  group('SessionListController 补拉兜底与联动', () {
    test('推 sessions_changed 帧 → 800ms debounce 后恰 1 次 refreshIfStale(force)', () {
      fakeAsync((async) {
        final sessionApi = FakeSessionListApi(sessions: const []);
        final container = _createContainer(sessionApi: sessionApi);
        addTearDown(container.dispose);

        // 初始化
        container.read(sessionListControllerProvider);
        async.elapse(Duration.zero);
        expect(sessionApi.fetchCount, 1);

        final controller = container.read(sessionListControllerProvider.notifier);

        // 连续推两帧
        controller.onSessionsChangedEvent(version: 1, reason: 'new');
        async.elapse(const Duration(milliseconds: 400));
        // 400ms 未达 800ms，不应刷新
        expect(sessionApi.fetchCount, 1);

        controller.onSessionsChangedEvent(version: 2, reason: 'update');
        // 重置 debounce：再过 500ms（距第 2 帧仅 500ms）仍未触发
        async.elapse(const Duration(milliseconds: 500));
        expect(sessionApi.fetchCount, 1);

        // 满足 800ms debounce → 恰好触发 1 次刷新
        async.elapse(const Duration(milliseconds: 350));
        expect(sessionApi.fetchCount, 2);
      });
    });

    test('force 撞 _refreshInFlight → 当前轮 finally 自动补拉 1 次（fetch +2 而非 +1）', () async {
      Completer<SessionsResponse>? inFlightCompleter;
      var fetchCount = 0;

      final sessionApi = _CustomAsyncSessionListApi(
        onFetch: () {
          fetchCount++;
          if (inFlightCompleter != null && !inFlightCompleter.isCompleted) {
            return inFlightCompleter.future;
          }
          return Future.value(const SessionsResponse(sessions: []));
        },
      );

      final container = _createContainer(sessionApi: sessionApi);
      addTearDown(container.dispose);

      // 先等待首屏初始化加载完成
      await container.read(sessionListControllerProvider.future);
      expect(fetchCount, 1);

      final controller = container.read(sessionListControllerProvider.notifier);
      inFlightCompleter = Completer<SessionsResponse>();

      // 第一轮 refresh 启动并在途（挂在 inFlightCompleter）
      final firstRefresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(fetchCount, 2);
      expect(controller.isRefreshInFlightForTesting, isTrue);

      // 在途期间调用 force refresh → 触发 dirty 标记
      await controller.refreshIfStale(force: true);
      expect(controller.isRefreshDirtyForTesting, isTrue);

      // 完成第一轮
      inFlightCompleter.complete(const SessionsResponse(sessions: []));
      await firstRefresh;

      // 等待 finally 补拉执行
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fetchCount, 3); // 首屏 1 + refresh 1 + 补拉 1 = 3（相对 refresh 启动前 +2）
      expect(controller.isRefreshDirtyForTesting, isFalse);
    });

    test('handleNewChatSession 阶梯：前 2 次不含新 sid、第 3 次含 → 恰 3 次请求后停止', () {
      fakeAsync((async) {
        var fetchCalls = 0;
        final targetId = 'sess-ladder-target';

        final sessionApi = _CustomAsyncSessionListApi(
          onFetch: () async {
            fetchCalls++;
            if (fetchCalls <= 3) {
              return const SessionsResponse(
                sessions: [
                  SessionSummary(sessionId: 'other', title: '其他会话'),
                ],
              );
            }
            return SessionsResponse(
              sessions: [
                const SessionSummary(sessionId: 'other', title: '其他会话'),
                SessionSummary(sessionId: targetId, title: '目标新会话'),
              ],
            );
          },
        );

        final container = _createContainer(sessionApi: sessionApi);
        addTearDown(container.dispose);

        // 初始化第 1 次 fetch (与 handleNewChatSession 无关)
        container.read(sessionListControllerProvider);
        async.elapse(Duration.zero);
        expect(fetchCalls, 1);

        final controller = container.read(sessionListControllerProvider.notifier);

        // 启动阶梯补拉
        unawaited(controller.handleNewChatSession(targetId));

        // 第 1 枪 (0ms): fetchCalls 变为 2 (handleNewChatSession 的第 1 次)，未包含目标
        async.elapse(Duration.zero);
        expect(fetchCalls, 2);

        // 第 2 枪 (+600ms): fetchCalls 变为 3 (handleNewChatSession 的第 2 次)，未包含目标
        async.elapse(const Duration(milliseconds: 600));
        expect(fetchCalls, 3);

        // 第 3 枪 (+2.5s 从头，即再 +1900ms): fetchCalls 变为 4 (handleNewChatSession 的第 3 次)，包含目标！
        async.elapse(const Duration(milliseconds: 1900));
        expect(fetchCalls, 4);

        // 再过 10 秒（远超过 +5.5s 的第 4 枪门槛），阶梯已终止，不再有新的 fetch
        async.elapse(const Duration(seconds: 10));
        expect(fetchCalls, 4);
      });
    });

    test('推送事件提前终止阶梯：等待期间列表已含该 sid 则终止后续枪', () {
      fakeAsync((async) {
        var fetchCalls = 0;
        final targetId = 'sess-stream-stop';
        var hasTarget = false;

        final sessionApi = _CustomAsyncSessionListApi(
          onFetch: () async {
            fetchCalls++;
            return SessionsResponse(
              sessions: [
                if (hasTarget)
                  SessionSummary(sessionId: targetId, title: '新会话'),
              ],
            );
          },
        );

        final container = _createContainer(sessionApi: sessionApi);
        addTearDown(container.dispose);

        container.read(sessionListControllerProvider);
        async.elapse(Duration.zero);
        expect(fetchCalls, 1);

        final controller = container.read(sessionListControllerProvider.notifier);

        // 启动阶梯
        unawaited(controller.handleNewChatSession(targetId));
        async.elapse(Duration.zero);
        expect(fetchCalls, 2); // 阶梯第 1 枪 (0ms)

        // 推进到 600ms：第 2 枪触发
        async.elapse(const Duration(milliseconds: 600));
        expect(fetchCalls, 3); // 阶梯第 2 枪 (600ms)

        // 在 700ms 收到推送事件，使后端返回包含新 session
        async.elapse(const Duration(milliseconds: 100));
        hasTarget = true;
        controller.onSessionsChangedEvent(reason: 'new', sessionId: targetId);

        // 经过 800ms debounce (当前时间 1500ms)
        async.elapse(const Duration(milliseconds: 800));
        expect(fetchCalls, 4); // 由 SSE 推送防抖触发的刷新，已命中新 session

        // 推进时间至 2500ms（原第 3 枪时刻）及更远（5500ms 原第 4 枪时刻）
        // 阶梯检查到新 session 已在列表中，提前终止
        async.elapse(const Duration(seconds: 10));
        expect(fetchCalls, 4); // 第 3 枪与第 4 枪未被触发
      });
    });
  });
}

class _CustomAsyncSessionListApi extends FakeSessionListApi {
  _CustomAsyncSessionListApi({required this.onFetch});

  final Future<SessionsResponse> Function() onFetch;

  @override
  Future<SessionsResponse> fetchSessions({
    bool includeArchived = false,
    int? archivedLimit,
  }) =>
      onFetch();
}
