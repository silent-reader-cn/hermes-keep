import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/clarification.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('#124 澄清选择弹窗与等待态生命周期（A+B+C+D+E）', () {
    late FakeChatApi api;
    late List<(String, String)> clarifyNotified;
    late List<(String, String, ChatLiveActivity, String)> liveActivityEvents;

    setUp(() {
      api = FakeChatApi();
      clarifyNotified = [];
      liveActivityEvents = [];
    });

    ProviderContainer buildContainer() {
      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          chatClarificationNeededCallbackProvider.overrideWithValue((
            sessionId,
            question,
          ) {
            clarifyNotified.add((sessionId, question));
          }),
          chatLiveActivityCallbackProvider.overrideWithValue((
            sessionId,
            title,
            activity,
            detail,
          ) {
            liveActivityEvents.add((sessionId, title, activity, detail));
          }),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // -------------------------------------------------------------------------
    // 1. 重连保卡：有澄清卡片时触发流收尾路径 → clarificationPrompt 保持保留
    // -------------------------------------------------------------------------
    test('1. 重连保卡：流收尾路径（_handleTransportError 无活跃流与 finalize 失败）保留澄清卡片', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        // 建立初始流式
        unawaited(controller.send('测试保卡'));
        async.flushMicrotasks();

        // 收到澄清卡片
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {
              'clarify_id': 'c-keep-1',
              'question': '请选择操作',
              'choices_offered': ['A', 'B'],
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();

        expect(
          container
              .read(chatControllerProvider('sess-1'))
              .pendingAction
              .clarificationPrompt,
          isNotNull,
        );

        // 触发 StreamEndSseEvent 流收尾
        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        // 断言流结束但澄清卡片仍保留（A 项核心）
        var state = container.read(chatControllerProvider('sess-1'));
        expect(state.phase, ChatPhase.idle);
        expect(state.pendingAction.clarificationPrompt, isNotNull);
        expect(
          state.pendingAction.clarificationPrompt!['clarify_id'],
          'c-keep-1',
        );

        // 再次测试 _handleTransportError 无活跃流分支
        api.emit(const TransportErrorSseEvent('连接丢失'));
        async.flushMicrotasks();

        state = container.read(chatControllerProvider('sess-1'));
        expect(state.pendingAction.clarificationPrompt, isNotNull);
        expect(state.sendErrorMessage, '连接丢失');
      });
    });

    // -------------------------------------------------------------------------
    // 2. 收尾仍清审批：有审批卡片时流收尾 → approvalPrompt == null
    // -------------------------------------------------------------------------
    test('2. 收尾仍清审批：流收尾清除 approval 卡片，行为与原逻辑一致', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('执行危险命令'));
        async.flushMicrotasks();

        // 收到审批事件
        api.emit(
          const ApprovalPendingSseEvent({
            'pending': {
              'approval_id': 'appr-1',
              'tool_call': {'name': 'bash', 'args': 'rm -rf /'},
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider('sess-1'));
        expect(state.pendingAction.approvalPrompt, isNotNull);

        // 触发流收尾
        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        state = container.read(chatControllerProvider('sess-1'));
        expect(state.pendingAction.approvalPrompt, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // 3. 通知幂等：同一 clarify_id 连续多次上报（含卡片被清后重建）通知只触发 1 次
    // -------------------------------------------------------------------------
    test('3. 通知幂等：同一 clarify_id 连续多次上报或重建卡片，通知回调恒为 1 次', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        // 首次收到 clarify_id = 'c-idempotent-1'
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {
              'clarify_id': 'c-idempotent-1',
              'question': '这是需要澄清的问题',
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();

        expect(clarifyNotified.length, 1);
        expect(clarifyNotified.first.$2, '这是需要澄清的问题');

        // 第二次收到相同的 clarify_id（如 SSE 重复或者轮询拿到相同 id）
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {
              'clarify_id': 'c-idempotent-1',
              'question': '这是需要澄清的问题（重复）',
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();

        // 依然只通知了一次
        expect(clarifyNotified.length, 1);

        // 即使 handleClarificationTimeout 清理卡片
        controller.handleClarificationTimeout();
        async.flushMicrotasks();
        expect(
          container
              .read(chatControllerProvider('sess-1'))
              .pendingAction
              .clarificationPrompt,
          isNull,
        );

        // 之后服务端又推了相同的 clarify_id，由于 _notifiedClarifyId 未变，不重复弹通知
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {
              'clarify_id': 'c-idempotent-1',
              'question': '这是需要澄清的问题',
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();

        expect(clarifyNotified.length, 1);
      });
    });

    // -------------------------------------------------------------------------
    // 4. id 变化可再通知：clarify_id 换成新值 → 通知计数 +1
    // -------------------------------------------------------------------------
    test('4. id 变化可再通知：换成新的 clarify_id 会再次触发通知', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {'clarify_id': 'c-seq-1', 'question': '第一个问题'},
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();
        expect(clarifyNotified.length, 1);

        // 换成新的 id
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {'clarify_id': 'c-seq-2', 'question': '第二个问题'},
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();
        expect(clarifyNotified.length, 2);
        expect(clarifyNotified.last.$2, '第二个问题');
      });
    });

    // -------------------------------------------------------------------------
    // 5. 无 id 回退：payload 不带 clarify_id 时行为与修复前一致（不崩且兼容原判定）
    // -------------------------------------------------------------------------
    test('5. 无 id 回退：缺失 clarify_id 时安全回退到相态判据', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        // 首次收到无 id 的 pending
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {'question': '无 id 问题'},
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();
        expect(clarifyNotified.length, 1);

        // 卡片已存在且处于 clarifyPending 状态，再次推无 id 的相同 pending 不重复通知
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {'question': '无 id 问题刷新'},
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();
        expect(clarifyNotified.length, 1);
      });
    });

    // -------------------------------------------------------------------------
    // 6. 轮询抗抖：模拟轮询连续返回空 —— 第 1 次空不清卡、第 2 次空才清卡
    // -------------------------------------------------------------------------
    test('6. 轮询抗抖：轮询第 1 次返回空不清卡，第 2 次空才清卡；非空中途归零', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        // 初始设置澄清卡片
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {'clarify_id': 'c-jitter-1', 'question': '抗抖测试问题'},
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();
        expect(
          container
              .read(chatControllerProvider('sess-1'))
              .pendingAction
              .clarificationPrompt,
          isNotNull,
        );

        // 启动轮询通道，配置 fake API 返回空结果
        api.clarifyPendingResponse = const ClarificationPendingResponse(
          pending: null,
          pendingCount: 0,
        );

        // 第 1 次轮询周期触发（20s）
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        // 第 1 次空：抗抖生效，卡片依然保留！
        expect(
          container
              .read(chatControllerProvider('sess-1'))
              .pendingAction
              .clarificationPrompt,
          isNotNull,
        );

        // 中途服务端恢复非空 pending
        api.clarifyPendingResponse = const ClarificationPendingResponse(
          pending: PendingClarification(
            clarifyId: 'c-jitter-1',
            question: '抗抖测试问题恢复',
          ),
          pendingCount: 1,
        );
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(
          container
              .read(chatControllerProvider('sess-1'))
              .pendingAction
              .clarificationPrompt,
          isNotNull,
        );

        // 再次变为连续返回空：第 1 次空
        api.clarifyPendingResponse = const ClarificationPendingResponse(
          pending: null,
          pendingCount: 0,
        );
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(
          container
              .read(chatControllerProvider('sess-1'))
              .pendingAction
              .clarificationPrompt,
          isNotNull,
        );

        // 第 2 次空：确认清卡
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(
          container
              .read(chatControllerProvider('sess-1'))
              .pendingAction
              .clarificationPrompt,
          isNull,
        );
      });
    });

    // -------------------------------------------------------------------------
    // 7. 作答后清卡：respondToClarification 成功后卡片清空
    // -------------------------------------------------------------------------
    test('7. 作答后清卡：respondToClarification 成功后立即清除澄清卡片', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {'clarify_id': 'c-ans-1', 'question': '请作答'},
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();
        expect(
          container
              .read(chatControllerProvider('sess-1'))
              .pendingAction
              .clarificationPrompt,
          isNotNull,
        );

        unawaited(controller.respondToClarification('我的答案'));
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-1'));
        expect(state.pendingAction.clarificationPrompt, isNull);
        expect(api.respondClarificationCalls, 1);
        expect(api.lastClarificationResponse, '我的答案');
      });
    });

    // -------------------------------------------------------------------------
    // 8. D 项判重算法纯函数单元测试
    // -------------------------------------------------------------------------
    test('8. D 项判重算法 shouldReinitClarifyCountdown 判重正确', () {
      // 1) 倒计时未激活 (hasActiveTimer == false) 时必须启动
      expect(
        shouldReinitClarifyCountdown(
          hasActiveTimer: false,
          lastId: 'c-1',
          currentId: 'c-1',
          lastPrompt: {'question': 'q1'},
          currentPrompt: {'question': 'q1'},
        ),
        isTrue,
      );

      // 2) 倒计时已激活且 clarify_id 相同 → 不重新初始化（防止 Timer 重建）
      expect(
        shouldReinitClarifyCountdown(
          hasActiveTimer: true,
          lastId: 'c-1',
          currentId: 'c-1',
          lastPrompt: {'question': 'q1'},
          currentPrompt: {'question': 'q1', 'another_field': 123},
        ),
        isFalse,
      );

      // 3) 倒计时已激活且 clarify_id 改变 → 重新初始化
      expect(
        shouldReinitClarifyCountdown(
          hasActiveTimer: true,
          lastId: 'c-1',
          currentId: 'c-2',
          lastPrompt: {'question': 'q1'},
          currentPrompt: {'question': 'q2'},
        ),
        isTrue,
      );

      // 4) 无 id 情况下通过 mapEquals 深比较：Map 内容一致 → 不重新初始化
      expect(
        shouldReinitClarifyCountdown(
          hasActiveTimer: true,
          lastId: null,
          currentId: null,
          lastPrompt: {'question': 'same', 'timeout': 10},
          currentPrompt: {'question': 'same', 'timeout': 10},
        ),
        isFalse,
      );

      // 5) 无 id 情况下通过 mapEquals 深比较：Map 内容不一致 → 重新初始化
      expect(
        shouldReinitClarifyCountdown(
          hasActiveTimer: true,
          lastId: null,
          currentId: null,
          lastPrompt: {'question': 'old'},
          currentPrompt: {'question': 'new'},
        ),
        isTrue,
      );
    });

    // -------------------------------------------------------------------------
    // 9. E-收尾不顶岛：澄清卡片存在时收尾事件保持 waitingReply 不被 finished 顶掉
    // -------------------------------------------------------------------------
    test(
      '9. E-收尾不顶岛：澄清卡片存在时收尾事件（StreamEndSseEvent）保持 waitingReply 不被 finished 顶掉',
      () {
        fakeAsync((async) {
          final container = buildContainer();
          final controller = container.read(
            chatControllerProvider('sess-1').notifier,
          );
          async.flushMicrotasks();

          unawaited(controller.send('开始'));
          async.flushMicrotasks();

          api.emit(
            const ClarificationPendingSseEvent({
              'pending': {'clarify_id': 'c-island-1', 'question': '岛上等待回复'},
              'pending_count': 1,
            }),
          );
          async.flushMicrotasks();

          // 触发 StreamEndSseEvent 收尾
          api.emit(const StreamEndSseEvent());
          async.flushMicrotasks();

          // 断言未上报 finished（不顶掉岛），且最终稳定停在 waitingReply
          expect(
            liveActivityEvents.any((e) => e.$3 == ChatLiveActivity.finished),
            isFalse,
          );
          expect(liveActivityEvents.last.$3, ChatLiveActivity.waitingReply);
        });
      },
    );

    // -------------------------------------------------------------------------
    // 10. E-无等待态仍报 finished：既无澄清也无审批时收尾上报 finished
    // -------------------------------------------------------------------------
    test('10. E-无等待态仍报 finished：普通回合收尾上报 finished（不回归）', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('普通请求'));
        async.flushMicrotasks();

        liveActivityEvents.clear();

        // 正常 done + stream_end
        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 'sess-1',
                'messages': [
                  {'role': 'assistant', 'content': '完成回答'},
                ],
              },
            ),
          ),
        );
        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        expect(
          liveActivityEvents.any((e) => e.$3 == ChatLiveActivity.finished),
          isTrue,
        );
      });
    });

    // -------------------------------------------------------------------------
    // 11. E-重建即上岛：纯轮询拉取 pending 重建卡片时即刻上报 waitingReply
    // -------------------------------------------------------------------------
    test('11. E-重建即上岛：不经过 SSE，轮询拉到 pending 自动上报 waitingReply', () {
      fakeAsync((async) {
        final container = buildContainer();
        // 激活 controller
        container.read(chatControllerProvider('sess-1'));
        async.flushMicrotasks();

        liveActivityEvents.clear();

        // 启动轮询并返回 pending
        api.clarifyPendingResponse = const ClarificationPendingResponse(
          pending: PendingClarification(
            clarifyId: 'c-poll-island',
            question: '轮询拉到的问题',
          ),
          pendingCount: 1,
        );

        // 启动通道并触发轮询
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        expect(
          liveActivityEvents.any((e) => e.$3 == ChatLiveActivity.waitingReply),
          isTrue,
        );
      });
    });

    // -------------------------------------------------------------------------
    // 12. E-清卡回落：作答成功后卡片清空 → 上报 finished 回落态
    // -------------------------------------------------------------------------
    test('12. E-清卡回落：作答成功卡片清空后，上报 finished 回落态', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        // 先推入澄清态
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {'clarify_id': 'c-fallback-1', 'question': '回落测试'},
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();

        // 流已结束（此时处于 idle + 澄清卡片保留）
        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        liveActivityEvents.clear();

        // 用户作答成功，清空卡片
        unawaited(controller.respondToClarification('作答确认'));
        async.flushMicrotasks();

        // 断言已上报 finished 回落态，不在 waitingReply 驻留
        expect(liveActivityEvents.last.$3, ChatLiveActivity.finished);
      });
    });
  });
}
