import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/approval.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_server_api.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

class _MockApprovalStreamEnabledController
    extends ApprovalStreamEnabledController {
  _MockApprovalStreamEnabledController(this._initial);
  final bool _initial;
  @override
  bool build() => _initial;
}

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

ResponseBody _sseResponse(String text) {
  return ResponseBody(
    Stream.value(Uint8List.fromList(utf8.encode(text))),
    200,
    headers: {
      'content-type': ['text/event-stream; charset=utf-8'],
    },
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Approval 独立通道状态机联动测试', () {
    late FakeChatApi api;

    setUp(() {
      api = FakeChatApi();
    });

    ProviderContainer buildContainer({bool? approvalStreamEnabled}) {
      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          if (approvalStreamEnabled != null)
            approvalStreamEnabledProvider.overrideWith(
              () => _MockApprovalStreamEnabledController(approvalStreamEnabled),
            ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('① initial 有 pending → 卡片 phase=approvalPending', () {
      fakeAsync((async) {
        final container = buildContainer();
        container.read(chatControllerProvider('sess-1').notifier);

        async.flushMicrotasks();
        expect(api.startApprovalStreamCalls, 1);
        expect(
          container.read(chatControllerProvider('sess-1')).phase,
          ChatPhase.idle,
        );

        // 服务端连接建立立即推送 initial 帧
        api.emitApproval(
          const ApprovalPendingSseEvent({
            'pending': {
              'approval_id': 'app-init-1',
              'command': 'bash build.sh',
              'description': '执行构建脚本',
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-1'));
        expect(state.phase, ChatPhase.approvalPending);
        expect(state.pendingAction.approvalPrompt, isNotNull);
        expect(
          state.pendingAction.approvalPrompt!['approval_id'],
          'app-init-1',
        );
        expect(
          state.pendingAction.approvalPrompt!['command'],
          'bash build.sh',
        );
        expect(
          state.pendingAction.approvalPrompt!['description'],
          '执行构建脚本',
        );
      });
    });

    test('② approval pending=null → 卡片清', () {
      fakeAsync((async) {
        final container = buildContainer();
        container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();

        // 先推有 pending
        api.emitApproval(
          const ApprovalPendingSseEvent({
            'pending': {
              'approval_id': 'app-2',
              'command': 'rm -rf /tmp/test',
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('sess-1')).phase,
          ChatPhase.approvalPending,
        );

        // 服务端队列清空，推送 pending: null
        api.emitApproval(
          const ApprovalPendingSseEvent({
            'pending': null,
            'pending_count': 0,
          }),
        );
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-1'));
        expect(state.phase, ChatPhase.idle);
        expect(state.pendingAction.approvalPrompt, isNull);
      });
    });

    test('③ approval 帧重复同 id → 幂等不重复弹卡/状态稳定', () {
      fakeAsync((async) {
        final container = buildContainer();
        container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();

        const payload = {
          'pending': {
            'approval_id': 'app-dup-1',
            'command': 'echo hello',
          },
          'pending_count': 1,
        };

        api.emitApproval(const ApprovalPendingSseEvent(payload));
        async.flushMicrotasks();

        final state1 = container.read(chatControllerProvider('sess-1'));
        expect(state1.phase, ChatPhase.approvalPending);
        expect(state1.pendingAction.approvalPrompt!['approval_id'], 'app-dup-1');

        // 重复推送相同 approval_id 帧
        api.emitApproval(const ApprovalPendingSseEvent(payload));
        async.flushMicrotasks();

        final state2 = container.read(chatControllerProvider('sess-1'));
        expect(state2.phase, ChatPhase.approvalPending);
        expect(state2.pendingAction.approvalPrompt!['approval_id'], 'app-dup-1');
        // Map 相等且对象等价
        expect(state1.pendingAction, equals(state2.pendingAction));
      });
    });

    test('④ 开关关 → 不建连不轮询', () {
      fakeAsync((async) {
        final container = buildContainer(approvalStreamEnabled: false);
        container.read(chatControllerProvider('sess-disabled').notifier);

        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 45));
        async.flushMicrotasks();

        expect(api.startApprovalStreamCalls, 0);
        expect(api.approvalPendingCalls, 0);
      });
    });

    test('⑤ 断流 onTransportError → 轮询兜底路径拉到 pending', () {
      fakeAsync((async) {
        final container = buildContainer();
        container.read(chatControllerProvider('sess-fallback').notifier);

        async.flushMicrotasks();
        expect(api.startApprovalStreamCalls, 1);

        // 模拟断流
        api.failApproval('Connection lost');
        async.flushMicrotasks();

        // 准备轮询返回的 pending
        api.approvalPendingResponse = ApprovalPendingResponse(
          pending: PendingApproval(
            approvalId: 'poll-app-99',
            command: 'git push origin feat',
            description: '推送分支',
          ),
          pendingCount: 1,
        );

        // 前进 20 秒触发静默轮询
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        expect(api.approvalPendingCalls, greaterThanOrEqualTo(1));
        final state = container.read(chatControllerProvider('sess-fallback'));
        expect(state.phase, ChatPhase.approvalPending);
        expect(state.pendingAction.approvalPrompt, isNotNull);
        expect(
          state.pendingAction.approvalPrompt!['approval_id'],
          'poll-app-99',
        );
        expect(
          state.pendingAction.approvalPrompt!['command'],
          'git push origin feat',
        );
      });
    });

    test('轮询兜底返回 pending 为 null 时清卡', () {
      fakeAsync((async) {
        final container = buildContainer();
        container.read(chatControllerProvider('sess-clear').notifier);
        async.flushMicrotasks();

        // 初始通过 SSE 弹卡
        api.emitApproval(
          const ApprovalPendingSseEvent({
            'pending': {
              'approval_id': 'app-to-clear',
              'command': 'make test',
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('sess-clear')).phase,
          ChatPhase.approvalPending,
        );

        // 轮询返回 pending 为 null
        api.approvalPendingResponse = const ApprovalPendingResponse(
          pending: null,
          pendingCount: 0,
        );
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-clear'));
        expect(state.phase, ChatPhase.idle);
        expect(state.pendingAction.approvalPrompt, isNull);
      });
    });

    test('运行时切换开关 → 关则停流，开则建流', () {
      fakeAsync((async) {
        final container = buildContainer();
        container.read(chatControllerProvider('sess-switch').notifier);
        async.flushMicrotasks();
        expect(api.startApprovalStreamCalls, 1);
        final initialStops = api.stopApprovalStreamCalls;

        // 关开关
        unawaited(
          container
              .read(approvalStreamEnabledProvider.notifier)
              .setEnabled(false),
        );
        async.flushMicrotasks();
        expect(api.stopApprovalStreamCalls, greaterThan(initialStops));

        // 开开关
        unawaited(
          container
              .read(approvalStreamEnabledProvider.notifier)
              .setEnabled(true),
        );
        async.flushMicrotasks();
        expect(api.startApprovalStreamCalls, 2);
      });
    });

    test('dispose 路径停流与清理', () {
      fakeAsync((async) {
        final container = buildContainer();
        container.read(chatControllerProvider('sess-dispose').notifier);
        async.flushMicrotasks();

        expect(api.startApprovalStreamCalls, 1);
        final initialStops = api.stopApprovalStreamCalls;
        container.dispose();

        expect(api.stopApprovalStreamCalls, greaterThan(initialStops));
      });
    });
  });

  group('Wire-level SSE 协议与 ChatApiClient 解析测试', () {
    test('startApprovalStream 成功解析 initial 与 approval 帧', () async {
      final ssePayload = [
        ': keepalive',
        '',
        'event: initial',
        'data: {"pending":{"approval_id":"app-wire-1","command":"systemctl restart app"},"pending_count":1}',
        '',
        ': keepalive',
        '',
        'event: approval',
        'data: {"pending":null,"pending_count":0}',
        '',
        '',
      ].join('\n');

      final adapter = _RecordingAdapter(
        responder: (options) => _sseResponse(ssePayload),
      );

      final dio = Dio()..httpClientAdapter = adapter;
      final apiClient = ApiClient(
        baseUrl: 'http://test.local:30002',
        dio: dio,
      );
      final chatClient = ChatApiClient(apiClient);

      final receivedEvents = <SseEvent>[];
      final completer = Completer<void>();

      await chatClient.startApprovalStream(
        'sess-wire-1',
        onEvent: (event) {
          if (event is ApprovalPendingSseEvent) {
            receivedEvents.add(event);
            if (receivedEvents.length == 2) {
              completer.complete();
            }
          }
        },
        onTransportError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        onClosed: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future.timeout(const Duration(seconds: 3));

      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.first.uri.path,
        '/api/approval/stream',
      );
      expect(
        adapter.requests.first.uri.queryParameters['session_id'],
        'sess-wire-1',
      );

      expect(receivedEvents, hasLength(2));

      // 第 1 帧为 initial
      expect(receivedEvents[0], isA<ApprovalPendingSseEvent>());
      final event1 = receivedEvents[0] as ApprovalPendingSseEvent;
      final p1 = event1.payload['pending'] as Map<String, Object?>;
      expect(p1['approval_id'], 'app-wire-1');
      expect(p1['command'], 'systemctl restart app');

      // 第 2 帧为 approval（清空）
      expect(receivedEvents[1], isA<ApprovalPendingSseEvent>());
      final event2 = receivedEvents[1] as ApprovalPendingSseEvent;
      expect(event2.payload['pending'], isNull);
      expect(event2.payload['pending_count'], 0);

      chatClient.stopApprovalStream();
    });

    test('approvalPending HTTP 请求路径与参数正确', () async {
      final adapter = _RecordingAdapter(
        responder: (options) => ResponseBody.fromString(
          '{"pending":{"approval_id":"p1","command":"pwd"},"pending_count":1}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );

      final dio = Dio()..httpClientAdapter = adapter;
      final apiClient = ApiClient(
        baseUrl: 'http://test.local:30002',
        dio: dio,
      );
      final chatClient = ChatApiClient(apiClient);

      final resp = await chatClient.approvalPending('sess-http-1');
      expect(resp.pending?.approvalId, 'p1');
      expect(resp.pending?.command, 'pwd');
      expect(resp.pendingCount, 1);

      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.first.uri.path,
        '/api/approval/pending',
      );
      expect(
        adapter.requests.first.uri.queryParameters['session_id'],
        'sess-http-1',
      );
    });
  });

  group('ApprovalStreamEnabledController 偏好测试', () {
    test('默认开启，支持持久化设置', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initial = container.read(approvalStreamEnabledProvider);
      expect(initial, isTrue);

      await container
          .read(approvalStreamEnabledProvider.notifier)
          .setEnabled(false);
      expect(container.read(approvalStreamEnabledProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kApprovalStreamEnabledKey), isFalse);

      final loaded = await ApprovalStreamEnabledController.loadPref();
      expect(loaded, isFalse);
    });
  });
}
