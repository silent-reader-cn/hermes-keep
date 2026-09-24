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
/// 多会话同时聊天 = 多条 SSE 长连接并存，这正是本组测试要复现的场景。
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
}