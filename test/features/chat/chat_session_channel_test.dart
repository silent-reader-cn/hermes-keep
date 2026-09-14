import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/endpoints.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_session_channel.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

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

class _StubActiveConnection extends ActiveConnectionController {
  @override
  ServerConnection? build() => ServerConnection(
        id: 'conn-test',
        name: 'Test',
        baseUrl: 'http://hermes.local:30002',
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

ProviderContainer _createChatContainer({
  required FakeChatApi fakeApi,
  ApiClient? apiClient,
}) {
  return ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(fakeApi),
      apiClientProvider.overrideWithValue(
        apiClient ?? ApiClient(baseUrl: 'http://hermes.local:30002'),
      ),
      activeConnectionProvider.overrideWith(() => _StubActiveConnection()),
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Endpoint.sessionStream (#108)', () {
    test('无 knownCount 时生成不带 known_count query 的 URL', () {
      final ep = Endpoint.sessionStream('s-101');
      final uri = ep.url('http://hermes.local:30002');
      expect(uri.path, '/api/session/stream');
      expect(uri.queryParameters['session_id'], 's-101');
      expect(uri.queryParameters.containsKey('known_count'), isFalse);
    });

    test('带 knownCount 时生成包含 known_count query 的 URL', () {
      final ep = Endpoint.sessionStream('s-101', 42);
      final uri = ep.url('http://hermes.local:30002');
      expect(uri.path, '/api/session/stream');
      expect(uri.queryParameters['session_id'], 's-101');
      expect(uri.queryParameters['known_count'], '42');
    });
  });

  group('ChatSessionChannel 协议解析与事件路由', () {
    test('① session-updated 帧 → 回调带 count', () async {
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

      final updatedCounts = <int>[];
      final channel = ChatSessionChannel(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        sessionId: 's-101',
        onSessionUpdated: (count) => updatedCounts.add(count),
        onServerTurnStarted: (_, {recovered = false, pendingStartedAt}) {},
        onBgTaskComplete: (_) {},
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.first.path,
        'http://hermes.local:30002/api/session/stream?session_id=s-101',
      );

      // 推送有效 session-updated 帧
      streamController.add(
        utf8.encode(
          'event: session-updated\n'
          'data: {"session_id":"s-101","message_count":12,"known_count":10,"source":"subscribe_recovery"}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(updatedCounts, [12]);

      channel.stop();
      await streamController.close();
    });

    test('③ server_turn_started fresh/recovered → 回调参数正确 + 同 streamId 二次帧幂等', () async {
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

      final turns = <Map<String, dynamic>>[];
      final channel = ChatSessionChannel(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        sessionId: 's-101',
        onSessionUpdated: (_) {},
        onServerTurnStarted: (streamId, {recovered = false, pendingStartedAt}) {
          turns.add({
            'streamId': streamId,
            'recovered': recovered,
            'pendingStartedAt': pendingStartedAt,
          });
        },
        onBgTaskComplete: (_) {},
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 1. Fresh server turn
      streamController.add(
        utf8.encode(
          'event: server_turn_started\n'
          'data: {"session_id":"s-101","stream_id":"stream-1","pending_started_at":1726281000.0}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(turns, hasLength(1));
      expect(turns.first['streamId'], 'stream-1');
      expect(turns.first['recovered'], isFalse);
      expect(turns.first['pendingStartedAt'], 1726281000.0);

      // 2. 同 streamId 二次帧幂等（忽略）
      streamController.add(
        utf8.encode(
          'event: server_turn_started\n'
          'data: {"session_id":"s-101","stream_id":"stream-1","recovered":false}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(turns, hasLength(1)); // 没有增加

      // 3. Recovered server turn (新 streamId)
      streamController.add(
        utf8.encode(
          'event: server_turn_started\n'
          'data: {"session_id":"s-101","stream_id":"stream-2","recovered":true,"pending_started_at":1726282000.5}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(turns, hasLength(2));
      expect(turns.last['streamId'], 'stream-2');
      expect(turns.last['recovered'], isTrue);
      expect(turns.last['pendingStartedAt'], 1726282000.5);

      // 4. 重复 stream-2 帧再次被幂等过滤
      streamController.add(
        utf8.encode(
          'event: server_turn_started\n'
          'data: {"session_id":"s-101","stream_id":"stream-2","recovered":true}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(turns, hasLength(2));

      channel.stop();
      await streamController.close();
    });

    test('bg_task_complete 帧触发回调且忽略 process_complete 旧别名', () async {
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

      final payloads = <Map<String, Object?>>[];
      final channel = ChatSessionChannel(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        sessionId: 's-101',
        onSessionUpdated: (_) {},
        onServerTurnStarted: (_, {recovered = false, pendingStartedAt}) {},
        onBgTaskComplete: (payload) => payloads.add(payload),
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 忽略 process_complete 旧别名
      streamController.add(
        utf8.encode(
          'event: process_complete\n'
          'data: {"task_id":"t-old","status":"done"}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(payloads, isEmpty);

      // 接收 canonical bg_task_complete
      streamController.add(
        utf8.encode(
          'event: bg_task_complete\n'
          'data: {"task_id":"t-new","status":"completed","exit_code":0}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(payloads, hasLength(1));
      expect(payloads.first['task_id'], 't-new');
      expect(payloads.first['exit_code'], 0);

      channel.stop();
      await streamController.close();
    });

    test('④ keepalive/未知帧不炸', () async {
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

      var updatedCount = 0;
      var turnCount = 0;
      var bgTaskCount = 0;

      final channel = ChatSessionChannel(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        sessionId: 's-101',
        onSessionUpdated: (_) => updatedCount++,
        onServerTurnStarted: (_, {recovered = false, pendingStartedAt}) =>
            turnCount++,
        onBgTaskComplete: (_) => bgTaskCount++,
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 注入各种杂项帧：注释、心跳、initial、未知事件、畸形 JSON
      final rawFrames = [
        ': keepalive\n\n',
        ': 30s heartbeat comment\n\n',
        'event: initial\ndata: {"session_id":"s-101"}\n\n',
        'event: unknown_event\ndata: {"some":"data"}\n\n',
        'event: session-updated\ndata: {broken json\n\n',
        'event: server_turn_started\ndata: not-json\n\n',
        'event: bg_task_complete\ndata: [1, 2, 3]\n\n',
        'event: bg_task_complete\ndata:   \n\n',
      ];

      for (final frame in rawFrames) {
        streamController.add(utf8.encode(frame));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 验证没有异常崩坏且不合法的帧未触发业务逻辑
      expect(updatedCount, 0);
      expect(turnCount, 0);
      expect(bgTaskCount, 0);

      channel.stop();
      await streamController.close();
    });

    test('⑤ 断线重连 known_count 取最新注入值', () async {
      final controllers = <StreamController<Uint8List>>[];

      final adapter = _RecordingAdapter(
        responder: (options) {
          final sc = StreamController<Uint8List>();
          controllers.add(sc);
          return ResponseBody(
            sc.stream,
            200,
            headers: {
              'content-type': ['text/event-stream'],
            },
          );
        },
      );
      final dio = Dio()..httpClientAdapter = adapter;

      int currentKnownCount = 5;
      final channel = ChatSessionChannel(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        sessionId: 's-101',
        knownCountProvider: () => currentKnownCount,
        backoffStrategy: (_) => const Duration(milliseconds: 10),
        onSessionUpdated: (_) {},
        onServerTurnStarted: (_, {recovered = false, pendingStartedAt}) {},
        onBgTaskComplete: (_) {},
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.first.path,
        'http://hermes.local:30002/api/session/stream?session_id=s-101&known_count=5',
      );

      // 本地状态更新，随后流中断
      currentKnownCount = 18;
      await controllers.first.close(); // 模拟连接断开

      // 等待重连
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests[1].path,
        'http://hermes.local:30002/api/session/stream?session_id=s-101&known_count=18',
      );

      channel.stop();
      for (final c in controllers) {
        if (!c.isClosed) await c.close();
      }
    });

    test('⑥ 开关关 → 不建连', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody(
          const Stream.empty(),
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      final channel = ChatSessionChannel(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        sessionId: 's-101',
        isEnabled: () => false, // 禁用
        onSessionUpdated: (_) {},
        onServerTurnStarted: (_, {recovered = false, pendingStartedAt}) {},
        onBgTaskComplete: (_) {},
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(adapter.requests, isEmpty);
      expect(channel.isRunning, isFalse);

      channel.stop();
    });

    test('start/stop/dispose 幂等性', () {
      final dio = Dio();
      final channel = ChatSessionChannel(
        dio: dio,
        baseUrl: 'http://hermes.local:30002',
        sessionId: 's-101',
        onSessionUpdated: (_) {},
        onServerTurnStarted: (_, {recovered = false, pendingStartedAt}) {},
        onBgTaskComplete: (_) {},
      );

      channel.stop(); // 未 start 时 stop 安全
      expect(channel.isRunning, isFalse);

      channel.dispose(); // 重复 dispose 安全
      channel.dispose();
      channel.stop();
    });
  });

  group('ChatController 会话内容同步门控与处理 (#108)', () {
    test('② 已知 count 追平后 syncMissingMessages 不再触发（门控）', () {
      fakeAsync((async) {
        final fakeApi = FakeChatApi();
        fakeApi.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 's-101',
            messageCount: 15,
            messages: [],
          ),
        );

        final container = _createChatContainer(fakeApi: fakeApi);
        addTearDown(container.dispose);

        final controller =
            container.read(chatControllerProvider('s-101').notifier);
        controller.setPersistedMessageCountForTesting(10);

        fakeApi.sessionResult = {
          'session': {
            'session_id': 's-101',
            'message_count': 15,
            'messages': <Map<String, Object?>>[],
          },
        };

        // 消费初始加载的 microtask
        async.elapse(const Duration(milliseconds: 50));
        final initialCalls = fakeApi.sessionCalls;

        // 1. 服务端 count <= 本地持久 count (8 <= 10) → 不触发
        controller.onSessionContentUpdatedForTesting(8);
        async.elapse(const Duration(seconds: 2));
        expect(fakeApi.sessionCalls, initialCalls);

        // 2. 服务端 count == 本地持久 count (10 == 10) → 不触发
        controller.onSessionContentUpdatedForTesting(10);
        async.elapse(const Duration(seconds: 2));
        expect(fakeApi.sessionCalls, initialCalls);

        // 3. 服务端 count > 本地持久 count (15 > 10) → 经 1s 去抖触发 syncMissingMessages
        controller.onSessionContentUpdatedForTesting(15);
        // 500ms 内尚未达到 1s 防抖
        async.elapse(const Duration(milliseconds: 500));
        expect(fakeApi.sessionCalls, initialCalls);

        // 再来一次 16 > 10，重置 1s 计时器
        controller.onSessionContentUpdatedForTesting(16);
        async.elapse(const Duration(milliseconds: 500));
        expect(fakeApi.sessionCalls, initialCalls);

        // 再走 600ms 达到 1s 防抖完成
        async.elapse(const Duration(milliseconds: 600));

        // 检查调用了一次 syncMissingMessages，且 _persistedMessageCount 追平
        expect(fakeApi.sessionCalls, initialCalls + 1);
        expect(controller.persistedMessageCountForTesting, 15);
      });
    });

    test('当前处于 streaming 或 sending 态时忽略 session-updated', () {
      fakeAsync((async) {
        final fakeApi = FakeChatApi();
        final container = _createChatContainer(fakeApi: fakeApi);
        addTearDown(container.dispose);

        final controller =
            container.read(chatControllerProvider('s-101').notifier);
        controller.setPersistedMessageCountForTesting(5);

        // 模拟当前正在 streaming
        controller.onServerTurnStartedForTesting('active-stream-1');
        expect(
          container.read(chatControllerProvider('s-101')).phase,
          ChatPhase.streaming,
        );

        // 收到更新应当被跳过
        controller.onSessionContentUpdatedForTesting(20);
        async.elapse(const Duration(seconds: 2));

        // 确认没有覆盖或重置流状态
        expect(
          container.read(chatControllerProvider('s-101')).phase,
          ChatPhase.streaming,
        );
        expect(
          container.read(chatControllerProvider('s-101')).stream.activeStreamId,
          'active-stream-1',
        );
      });
    });

    test('server_turn_started fresh 启动流式回合，同 streamId 幂等', () {
      fakeAsync((async) {
        final fakeApi = FakeChatApi();
        final container = _createChatContainer(fakeApi: fakeApi);
        addTearDown(container.dispose);

        final controller =
            container.read(chatControllerProvider('s-101').notifier);
        expect(
          container.read(chatControllerProvider('s-101')).phase,
          ChatPhase.idle,
        );

        // Fresh frame
        controller.onServerTurnStartedForTesting(
          'stream-turn-1',
          pendingStartedAt: 1726280000.0,
        );

        final state = container.read(chatControllerProvider('s-101'));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.activeStreamId, 'stream-turn-1');
        expect(state.turnStartedMillis, 1726280000000);

        // 再次收到同 streamId 帧 → 幂等 bail
        controller.onServerTurnStartedForTesting('stream-turn-1');
        expect(
          container.read(chatControllerProvider('s-101')).stream.activeStreamId,
          'stream-turn-1',
        );
      });
    });

    test('server_turn_started recovered 带 replay 参数恢复附加', () {
      fakeAsync((async) {
        final fakeApi = FakeChatApi();
        fakeApi.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 's-101',
            messageCount: 3,
            messages: [],
          ),
        );

        final container = _createChatContainer(fakeApi: fakeApi);
        addTearDown(container.dispose);

        final controller =
            container.read(chatControllerProvider('s-101').notifier);

        controller.onServerTurnStartedForTesting(
          'stream-recovered-1',
          recovered: true,
          pendingStartedAt: 1726280500.0,
        );
        async.elapse(const Duration(milliseconds: 100));

        final state = container.read(chatControllerProvider('s-101'));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.activeStreamId, 'stream-recovered-1');
        expect(state.stream.isReplayConnection, isTrue);
      });
    });

    test('bg_task_complete 触发增量消息拉取去抖', () {
      fakeAsync((async) {
        final fakeApi = FakeChatApi();
        fakeApi.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 's-101',
            messageCount: 7,
            messages: [],
          ),
        );

        final container = _createChatContainer(fakeApi: fakeApi);
        addTearDown(container.dispose);

        final controller =
            container.read(chatControllerProvider('s-101').notifier);
        controller.setPersistedMessageCountForTesting(5);

        controller.onSessionBgTaskCompleteForTesting({
          'task_id': 'proc-1',
          'status': 'completed',
        });

        // 1s 防抖后执行 syncMissingMessages
        async.elapse(const Duration(seconds: 1));
        expect(controller.persistedMessageCountForTesting, 7);
      });
    });
  });

  group('sessionContentStreamEnabledProvider 设置开关与持久化', () {
    test('默认开启 true，修改后写 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(sessionContentStreamEnabledProvider), isTrue);

      await container
          .read(sessionContentStreamEnabledProvider.notifier)
          .setEnabled(false);
      expect(container.read(sessionContentStreamEnabledProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSessionContentStreamEnabledKey), isFalse);

      final loaded = await SessionContentStreamEnabledController.loadPref();
      expect(loaded, isFalse);
    });
  });
}
