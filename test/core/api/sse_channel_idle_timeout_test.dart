import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/api/sse_channel_base.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ResponseBody _createSseResponse(
  RequestOptions options,
  StreamController<Uint8List> controller,
) {
  final whenCancel = options.cancelToken?.whenCancel;
  if (whenCancel != null) {
    unawaited(
      whenCancel.then((_) {
        if (!controller.isClosed) {
          controller.addError(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
        }
      }),
    );
  }
  return ResponseBody(
    controller.stream,
    200,
    headers: {
      'content-type': ['text/event-stream'],
    },
  );
}

class _FakeIdleChannel extends SseChannelBase {
  _FakeIdleChannel({
    required super.dio,
    required super.baseUrl,
    super.idleTimeout,
    super.backoffStrategy,
  });

  final List<SseWireEvent> receivedEvents = [];

  @override
  Uri buildUrl() => Uri.parse('$baseUrl/api/fake/stream');

  @override
  void processWire(SseWireEvent wire) {
    receivedEvents.add(wire);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SseChannelBase 空闲超时看门狗', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DiagnosticsService.instance.init();
      await DiagnosticsService.instance.clear();
      await DiagnosticsService.instance.setEnabled(true);
    });

    tearDown(() async {
      await DiagnosticsService.instance.clear();
      await DiagnosticsService.instance.setEnabled(false);
    });

    test('RED-1: 持续无数据 ⇒ 超过 idleTimeout 后当前连接被主动取消', () async {
      final streamController = StreamController<Uint8List>();
      final adapter = _RecordingAdapter(
        responder: (options) => _createSseResponse(options, streamController),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final channel = _FakeIdleChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        idleTimeout: const Duration(milliseconds: 100),
        backoffStrategy: (_) => const Duration(seconds: 10),
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(adapter.requests, hasLength(1));
      final firstToken = adapter.requests.first.cancelToken;
      expect(firstToken, isNotNull);
      expect(firstToken!.isCancelled, isFalse);

      // 持续无数据：等待超过 idleTimeout (100ms)
      await Future<void>.delayed(const Duration(milliseconds: 130));

      // 校验：当前连接已被主动取消
      expect(firstToken.isCancelled, isTrue);

      // 校验：诊断日志记录包含 tag: sse_idle、URL 与毫秒数
      final idleLogs = DiagnosticsService.instance.logs
          .where((l) => l.tag == 'sse_idle')
          .toList();
      expect(idleLogs, isNotEmpty);
      expect(idleLogs.first.level, DiagnosticsLogLevel.warn);
      expect(
        idleLogs.first.message,
        contains('http://test.local/api/fake/stream'),
      );
      expect(idleLogs.first.message, contains('100ms'));

      channel.stop();
      if (!streamController.isClosed) await streamController.close();
    });

    test('RED-2: idle 判死后必须触发重连（再次发起请求并成功建连）', () async {
      final controllers = <StreamController<Uint8List>>[];
      final adapter = _RecordingAdapter(
        responder: (options) {
          final sc = StreamController<Uint8List>();
          controllers.add(sc);
          return _createSseResponse(options, sc);
        },
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final channel = _FakeIdleChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        idleTimeout: const Duration(milliseconds: 80),
        backoffStrategy: (_) => const Duration(milliseconds: 10),
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(adapter.requests, hasLength(1));
      final firstToken = adapter.requests.first.cancelToken;
      expect(firstToken, isNotNull);
      expect(firstToken!.isCancelled, isFalse);

      // 等待 idleTimeout (80ms) 触发取消 + 退避重连 (10ms + 调度缓冲)
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // 关键断言：必须触发重连，发起第 2 次请求
      expect(adapter.requests.length, greaterThanOrEqualTo(2));
      final secondToken = adapter.requests[1].cancelToken;
      expect(firstToken.isCancelled, isTrue);
      expect(secondToken, isNotNull);
      expect(secondToken!.isCancelled, isFalse);

      channel.stop();
      for (final c in controllers) {
        if (!c.isClosed) await c.close();
      }
    });

    test('RED-3: 有数据流动时 idle timer 被重置（含仅收到 keepalive 注释帧分支）', () async {
      final controller = StreamController<Uint8List>();
      final adapter = _RecordingAdapter(
        responder: (options) => _createSseResponse(options, controller),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final channel = _FakeIdleChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        idleTimeout: const Duration(milliseconds: 100),
        backoffStrategy: (_) => const Duration(seconds: 10),
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.requests, hasLength(1));
      final token = adapter.requests.first.cancelToken;
      expect(token!.isCancelled, isFalse);

      // 仅收到 keepalive 注释帧分支：每 40ms 发送一次 keepalive 注释帧，累计约 150ms (> 100ms)
      await Future<void>.delayed(const Duration(milliseconds: 40));
      controller.add(utf8.encode(': keepalive\n\n'));

      await Future<void>.delayed(const Duration(milliseconds: 40));
      controller.add(utf8.encode(': keepalive\n\n'));

      await Future<void>.delayed(const Duration(milliseconds: 40));
      controller.add(utf8.encode(': keepalive\n\n'));

      await Future<void>.delayed(const Duration(milliseconds: 30));
      // 累计耗时已超 100ms idleTimeout；因 keepalive 续命，连接未被断开
      expect(token.isCancelled, isFalse);
      expect(adapter.requests, hasLength(1));

      // 停止发送数据，等待超过 idleTimeout (100ms)
      await Future<void>.delayed(const Duration(milliseconds: 130));

      // 空闲超时生效，连接被主动取消
      expect(token.isCancelled, isTrue);

      channel.stop();
      if (!controller.isClosed) await controller.close();
    });

    test('RED-4: stop() 之后推进时间，idle timer 不再触发任何动作', () async {
      final controller = StreamController<Uint8List>();
      final adapter = _RecordingAdapter(
        responder: (options) => _createSseResponse(options, controller),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final channel = _FakeIdleChannel(
        dio: dio,
        baseUrl: 'http://test.local',
        idleTimeout: const Duration(milliseconds: 80),
        backoffStrategy: (_) => const Duration(milliseconds: 10),
      );

      channel.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.requests, hasLength(1));

      // 在 idleTimeout 到期前显式 stop()
      channel.stop();
      expect(channel.isRunning, isFalse);
      expect(channel.idleTimerForTesting?.isActive ?? false, isFalse);
      await DiagnosticsService.instance.clear();

      // 推进时间超过 idleTimeout
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // 校验：stop() 后 idle timer 已被取消，无新请求、无重连、无诊断日志
      expect(adapter.requests, hasLength(1));
      expect(channel.isRunning, isFalse);
      expect(channel.reconnectAttempts, 0);
      final idleLogs = DiagnosticsService.instance.logs
          .where((l) => l.tag == 'sse_idle')
          .toList();
      expect(idleLogs, isEmpty);

      if (!controller.isClosed) await controller.close();
    });
  });
}
