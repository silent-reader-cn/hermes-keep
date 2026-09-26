import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_server_api.dart';

/// 假 adapter：为每个请求返回一条**永不结束**的 SSE 流，让并发流保持打开。
///
/// 多会话同时聊天 = 多条 SSE 长连接并存，这正是本组测试要复现/压测的场景。
class _OpenStreamAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<StreamController<Uint8List>> controllers = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final controller = StreamController<Uint8List>();
    controllers.add(controller);
    return ResponseBody(
      controller.stream,
      200,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  Future<void> closeAll() async {
    for (final c in controllers) {
      if (!c.isClosed) await c.close();
    }
  }
}

void main() {
  group('多会话并行流隔离（复现 chat_watchdog transport silence 风暴）', () {
    late _OpenStreamAdapter adapter;
    late ChatApiClient api;

    setUp(() {
      adapter = _OpenStreamAdapter();
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = adapter;
      api = ChatApiClient(
        ApiClient(baseUrl: 'http://hermes.local:8787', dio: dio),
      );
    });

    test('会话 B 开流不得取消会话 A 的流（当前 BUG：共享单例 SseClient 互踩）', () async {
      // 会话 A 发起流式
      final aStart = api.startStream(
        'stream-A',
        onEvent: (_) {},
        onTransportError: (_) {},
        onClosed: () {},
      );
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1), reason: '会话 A 应已建立一条 SSE 连接');

      // 会话 B 同时发起流式
      final bStart = api.startStream(
        'stream-B',
        onEvent: (_) {},
        onTransportError: (_) {},
        onClosed: () {},
      );
      await pumpEventQueue();
      expect(adapter.requests, hasLength(2), reason: '会话 B 应已建立自己的 SSE 连接');

      final tokenA = adapter.requests[0].cancelToken;
      expect(tokenA, isNotNull);
      expect(
        tokenA!.isCancelled,
        isFalse,
        reason:
            '会话 A 的 SSE 连接被会话 B 的 startStream 取消了 → A 静默无传输活动 '
            '→ 18s（有工具时 25s）后看门狗判 transport silence → 强制重连；'
            '而重连又调 stopStream() 取消别人的连接 → 多会话互踩雪崩。',
      );

      await adapter.closeAll();
      await aStart;
      await bStart;
    });

    test('chatApiProvider 是全局单例：所有会话共用同一个 ChatServerApi 实例', () {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = _OpenStreamAdapter();
      final shared = ApiClient(baseUrl: 'http://hermes.local:8787', dio: dio);
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(shared)],
      );
      addTearDown(container.dispose);

      final a = container.read(chatApiProvider);
      final b = container.read(chatApiProvider);
      expect(
        identical(a, b),
        isTrue,
        reason: '同一实例意味着同一条 _sseClient / 同一个 cancelToken 被所有会话共享',
      );
    });
  });

  group('多会话并发压力（连接池隔离与回收）', () {
    late _OpenStreamAdapter adapter;
    late ChatApiClient api;

    setUp(() {
      adapter = _OpenStreamAdapter();
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = adapter;
      api = ChatApiClient(
        ApiClient(baseUrl: 'http://hermes.local:8787', dio: dio),
      );
    });

    test('5 个会话同时开流：5 条连接两两独立，无一条被互踩取消', () async {
      final futures = <Future<void>>[];
      for (var i = 0; i < 5; i++) {
        futures.add(
          api.startStream(
            'stream-$i',
            onEvent: (_) {},
            onTransportError: (_) {},
            onClosed: () {},
          ),
        );
      }
      await pumpEventQueue();

      expect(adapter.requests, hasLength(5), reason: '5 个会话应各有一条独立 SSE 连接');
      for (var i = 0; i < 5; i++) {
        final token = adapter.requests[i].cancelToken;
        expect(token, isNotNull);
        expect(
          token!.isCancelled,
          isFalse,
          reason: '并发 5 会话时第 $i 条连接被误取消——连接池隔离失效',
        );
      }

      await adapter.closeAll();
      for (final f in futures) {
        await f;
      }
    });

    test('stopStream 精确断开：只断点名的那条，其它会话不受影响', () async {
      final futures = <Future<void>>[];
      for (var i = 0; i < 5; i++) {
        futures.add(
          api.startStream(
            'stream-$i',
            onEvent: (_) {},
            onTransportError: (_) {},
            onClosed: () {},
          ),
        );
      }
      await pumpEventQueue();

      api.stopStream('stream-2');
      await pumpEventQueue();

      expect(
        adapter.requests[2].cancelToken!.isCancelled,
        isTrue,
        reason: '被点名的 stream-2 应被断开',
      );
      for (final i in [0, 1, 3, 4]) {
        expect(
          adapter.requests[i].cancelToken!.isCancelled,
          isFalse,
          reason: '停 stream-2 不应影响 stream-$i（这正是 transport silence 风暴的另一半）',
        );
      }

      await adapter.closeAll();
      for (final f in futures) {
        await f;
      }
    });

    test('同 streamId 重连：只取消自己的旧连接，不影响其它会话', () async {
      final futures = <Future<void>>[];
      for (var i = 0; i < 3; i++) {
        futures.add(
          api.startStream(
            'stream-$i',
            onEvent: (_) {},
            onTransportError: (_) {},
            onClosed: () {},
          ),
        );
      }
      await pumpEventQueue();
      expect(adapter.requests, hasLength(3));

      // stream-0 重连（同 id）
      futures.add(
        api.startStream(
          'stream-0',
          onEvent: (_) {},
          onTransportError: (_) {},
          onClosed: () {},
        ),
      );
      await pumpEventQueue();

      expect(adapter.requests, hasLength(4), reason: '重连应建立新连接');
      expect(
        adapter.requests[0].cancelToken!.isCancelled,
        isTrue,
        reason: '同 id 重连必须取消自己的旧连接（防连接泄漏）',
      );
      expect(adapter.requests[3].cancelToken!.isCancelled, isFalse);
      expect(
        adapter.requests[1].cancelToken!.isCancelled,
        isFalse,
        reason: 'stream-0 重连不应误伤 stream-1',
      );
      expect(
        adapter.requests[2].cancelToken!.isCancelled,
        isFalse,
        reason: 'stream-0 重连不应误伤 stream-2',
      );

      await adapter.closeAll();
      for (final f in futures) {
        await f;
      }
    });

    test('流自然结束后池已回收：重复 stopStream 安全（无异常、无泄漏）', () async {
      final future = api.startStream(
        'stream-x',
        onEvent: (_) {},
        onTransportError: (_) {},
        onClosed: () {},
      );
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));

      // 流自然结束 → startStream 的 finally 应把该 id 从池里回收
      await adapter.closeAll();
      await future;

      // 此后再停同一 id：池里已无该项，应为安全 no-op（不抛异常）
      expect(() => api.stopStream('stream-x'), returnsNormally);
      expect(() => api.stopStream('不存在的流'), returnsNormally);
    });
  });
}