import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/api/custom_header.dart';
import 'package:hermes_ui/core/api/sse_channel_base.dart';
import 'package:hermes_ui/core/api/sse_client.dart';

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

class _FakeChannel extends SseChannelBase {
  _FakeChannel({
    required super.dio,
    required super.baseUrl,
    super.customHeaderProvider,
    super.cookieProvider,
    super.isEnabled,
    super.backoffStrategy,
    this.canStartOverride = true,
  });

  bool canStartOverride;
  final List<SseWireEvent> receivedEvents = [];
  final List<bool> connectedStates = [];

  @override
  Uri buildUrl() => Uri.parse('$baseUrl/api/fake/stream');

  @override
  void processWire(SseWireEvent wire) {
    receivedEvents.add(wire);
  }

  @override
  bool canStart() => canStartOverride;

  @override
  void onConnected({required bool wasReconnecting}) {
    connectedStates.add(wasReconnecting);
  }
}

void main() {
  group('SseChannelBase 核心行为契约', () {
    test('1. 退避序列：attempt 0..5 指数退避且封顶 30s，attempt > 30 不越界', () {
      final dio = Dio();
      final channel = _FakeChannel(dio: dio, baseUrl: 'http://test.local');

      expect(channel.getBackoffDelay(0), const Duration(seconds: 1));
      expect(channel.getBackoffDelay(1), const Duration(seconds: 2));
      expect(channel.getBackoffDelay(2), const Duration(seconds: 4));
      expect(channel.getBackoffDelay(3), const Duration(seconds: 8));
      expect(channel.getBackoffDelay(4), const Duration(seconds: 16));
      expect(channel.getBackoffDelay(5), const Duration(seconds: 30));
      expect(channel.getBackoffDelay(6), const Duration(seconds: 30));
      expect(channel.getBackoffDelay(30), const Duration(seconds: 30));
      expect(channel.getBackoffDelay(35), const Duration(seconds: 30));
      expect(channel.getBackoffDelay(100), const Duration(seconds: 30));
    });

    test('2. backoffStrategy 注入时优先使用', () {
      final dio = Dio();
      final channel = _FakeChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        backoffStrategy: (attempt) => Duration(milliseconds: attempt * 50),
      );

      expect(channel.getBackoffDelay(0), Duration.zero);
      expect(channel.getBackoffDelay(3), const Duration(milliseconds: 150));
    });

    test('3. start() 幂等：连续调用多次仅建立一次连接', () async {
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
      final channel = _FakeChannel(dio: dio, baseUrl: 'http://test.local');

      channel.start();
      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(channel.isRunning, isTrue);
      expect(adapter.requests, hasLength(1));

      channel.stop();
      await streamController.close();
    });

    test('4. canStart() 返回 false 时不建连', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody(const Stream.empty(), 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final channel = _FakeChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        canStartOverride: false,
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(channel.isRunning, isFalse);
      expect(adapter.requests, isEmpty);

      channel.stop();
    });

    test('4b. isEnabled 门控返回 false 时不建连', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody(const Stream.empty(), 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final channel = _FakeChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        isEnabled: () => false,
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(channel.isRunning, isFalse);
      expect(adapter.requests, isEmpty);

      channel.stop();
    });

    test('5. stop() / dispose() 幂等；dispose 后 start 不建连', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody(const Stream.empty(), 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final channel = _FakeChannel(dio: dio, baseUrl: 'http://test.local');

      channel.stop();
      expect(channel.isRunning, isFalse);

      channel.dispose();
      channel.dispose();
      channel.stop();

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(channel.isRunning, isFalse);
      expect(adapter.requests, isEmpty);
    });

    test('6. 非 200 响应触发重连；200 正常流读取', () async {
      final controllers = <StreamController<Uint8List>>[];
      var attemptCount = 0;

      final adapter = _RecordingAdapter(
        responder: (_) {
          attemptCount++;
          if (attemptCount == 1) {
            return ResponseBody(const Stream.empty(), 500);
          }
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
      final channel = _FakeChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        backoffStrategy: (_) => const Duration(milliseconds: 10),
      );

      channel.start();
      // 等待第 1 次连接 (500) 和第 2 次重连 (200)
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(adapter.requests, hasLength(2));
      expect(channel.isRunning, isTrue);

      // 推送一个 SSE 事件
      controllers.first.add(utf8.encode('event: test_msg\ndata: hello\n\n'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(channel.receivedEvents, hasLength(1));
      expect(channel.receivedEvents.first.eventType, 'test_msg');
      expect(channel.receivedEvents.first.data, 'hello');

      channel.stop();
      for (final c in controllers) {
        if (!c.isClosed) await c.close();
      }
    });

    test(
      '7. cancelTokenForTesting 在每次连接后是新对象（#73 防线：证明 cancelToken 真的接上了）',
      () async {
        final controllers = <StreamController<Uint8List>>[];

        final adapter = _RecordingAdapter(
          responder: (_) {
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
        final channel = _FakeChannel(
          dio: dio,
          baseUrl: 'http://test.local',
          backoffStrategy: (_) => const Duration(milliseconds: 10),
        );

        channel.start();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(adapter.requests, hasLength(1));
        final firstToken = adapter.requests.first.cancelToken;
        expect(firstToken, isNotNull);
        expect(firstToken!.isCancelled, isFalse);
        expect(channel.cancelTokenForTesting, same(firstToken));

        // 中断第 1 次流，触发重连
        await controllers.first.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(adapter.requests, hasLength(2));
        final secondToken = adapter.requests[1].cancelToken;
        expect(secondToken, isNotNull);
        expect(secondToken!.isCancelled, isFalse);
        expect(channel.cancelTokenForTesting, same(secondToken));

        // 关键断言：旧 token 已被取消，新 token 是独立实例
        expect(firstToken.isCancelled, isTrue);
        expect(secondToken, isNot(same(firstToken)));

        channel.stop();
        expect(secondToken.isCancelled, isTrue);
        for (final c in controllers) {
          if (!c.isClosed) await c.close();
        }
      },
    );

    test('8. onConnected(wasReconnecting) 首连为 false、重连为 true', () async {
      final controllers = <StreamController<Uint8List>>[];

      final adapter = _RecordingAdapter(
        responder: (_) {
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
      final channel = _FakeChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        backoffStrategy: (_) => const Duration(milliseconds: 10),
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(channel.connectedStates, [false]); // 首次连接 wasReconnecting: false

      // 中断流，触发重连
      await controllers.first.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(channel.connectedStates, [
        false,
        true,
      ]); // 重连成功 wasReconnecting: true

      channel.stop();
      for (final c in controllers) {
        if (!c.isClosed) await c.close();
      }
    });

    test('9. headers 与 cookie 注入及大小写不敏感去重', () async {
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
      final channel = _FakeChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        customHeaderProvider: () => const [
          CustomHeader(name: 'X-Custom-Auth', value: 'secret-token'),
          CustomHeader(name: 'accept', value: 'application/json'), // 大小写重叠，应被去重
        ],
        cookieProvider: (uri) => 'session_cookie=abc',
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(adapter.requests, hasLength(1));
      final headers = adapter.requests.first.headers;
      expect(headers['Accept'], 'text/event-stream');
      expect(headers['X-Custom-Auth'], 'secret-token');
      expect(headers['Cookie'], 'session_cookie=abc');

      channel.stop();
      await streamController.close();
    });
  });
}
