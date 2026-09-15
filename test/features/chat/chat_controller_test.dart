import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/settings/smooth_streaming_settings.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';

void main() {
  group('ChatPhase 九态（chat_spec.md §2.1）', () {
    test('恰好 9 个状态', () {
      expect(ChatPhase.values, hasLength(9));
      expect(ChatPhase.values.toSet(), {
        ChatPhase.idle,
        ChatPhase.sending,
        ChatPhase.streaming,
        ChatPhase.steered,
        ChatPhase.approvalPending,
        ChatPhase.clarifyPending,
        ChatPhase.recovering,
        ChatPhase.cancelled,
        ChatPhase.error,
      });
    });
  });

  group('send → sending → streaming（§4.1）', () {
    test('乐观消息追加 + startChat 成功进入 streaming', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.sending,
        );
        // 乐观 user 消息已追加
        expect(
          container.read(chatControllerProvider('')).messages,
          hasLength(1),
        );
        expect(
          container.read(chatControllerProvider('')).messages.first.content,
          '你好',
        );
        expect(
          container.read(chatControllerProvider('')).messages.first.role,
          'user',
        );

        async.flushMicrotasks();
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.activeStreamId, 'stream-1');
        expect(api.startChatCalls, 1);
        expect(api.lastSentText, '你好');
        expect(api.streamIds, ['stream-1']);
        // 新会话：服务端返回的 session_id 接管
        expect(state.sessionId, 'sess-new');
      });
    });

    test('startChat 失败 → 回滚乐观消息 + sendErrorMessage + idle', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.startChatError = NetworkException(
          NetworkExceptionKind.cannotConnect,
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.messages, isEmpty);
        expect(state.sendErrorMessage, isNotNull);
        expect(api.startStreamCalls, 0);
      });
    });

    test('409 已有活动流 → 回滚 + loadMessages + 接管已有流', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.startChatError = HttpException.fromBody(
          409,
          '{"error":"active","active_stream_id":"st-exist"}',
        );
        api.sessionResult = {
          'session': {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': 'old', 'message_id': 'u0'},
              {
                'role': 'assistant',
                'content': 'old answer',
                'message_id': 'a0',
              },
            ],
          },
        };
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        final state = container.read(chatControllerProvider('s1'));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.activeStreamId, 'st-exist');
        // 乐观消息已回滚
        expect(state.messages.where((m) => m.content == 'hi'), isEmpty);
        expect(api.streamIds, ['st-exist']);
      });
    });
  });

  group('平滑打字机与积压自适应（smoothStreaming）', () {
    test('adaptiveWordUnitsPerTick 自适应速率算法：五档语义断言', () {
      // 1. 逐字档（固定 1 词/字）
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          0,
          SmoothStreamingSpeedPreset.charByChar,
        ),
        0,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          1,
          SmoothStreamingSpeedPreset.charByChar,
        ),
        1,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          5,
          SmoothStreamingSpeedPreset.charByChar,
        ),
        1,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          500,
          SmoothStreamingSpeedPreset.charByChar,
        ),
        1,
      );

      // 2. 慢档（固定 1 单元）
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          0,
          SmoothStreamingSpeedPreset.slow,
        ),
        0,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          1,
          SmoothStreamingSpeedPreset.slow,
        ),
        1,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          5,
          SmoothStreamingSpeedPreset.slow,
        ),
        1,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          500,
          SmoothStreamingSpeedPreset.slow,
        ),
        1,
      );

      // 3. 标准档（默认，固定 2 单元）
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          0,
          SmoothStreamingSpeedPreset.standard,
        ),
        0,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          1,
          SmoothStreamingSpeedPreset.standard,
        ),
        1,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          2,
          SmoothStreamingSpeedPreset.standard,
        ),
        2,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          5,
          SmoothStreamingSpeedPreset.standard,
        ),
        2,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          500,
          SmoothStreamingSpeedPreset.standard,
        ),
        2,
      );

      // 4. 快档（base=3，自适应加速，上限 32）
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          0,
          SmoothStreamingSpeedPreset.fast,
        ),
        0,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          1,
          SmoothStreamingSpeedPreset.fast,
        ),
        1,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          2,
          SmoothStreamingSpeedPreset.fast,
        ),
        2,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          3,
          SmoothStreamingSpeedPreset.fast,
        ),
        3,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          8,
          SmoothStreamingSpeedPreset.fast,
        ),
        3,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          20,
          SmoothStreamingSpeedPreset.fast,
        ),
        4,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          500,
          SmoothStreamingSpeedPreset.fast,
        ),
        32,
      );

      // 5. 极快档（base=5，自适应加速，上限 32）
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          0,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        0,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          2,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        2,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          4,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        4,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          5,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        5,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          6,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        5,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          8,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        5,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          20,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        6,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          44,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        8,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          68,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        10,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          128,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        15,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          200,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        21,
      );
      expect(
        ChatController.adaptiveWordUnitsPerTick(
          500,
          SmoothStreamingSpeedPreset.veryFast,
        ),
        32,
      );
    });

    test('标准档（默认）：16ms merge + 64ms 固定 2 词 reveal', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 注入 50 个词单元（每词一个 'word '）
        final text = 'word ' * 50;
        api.emit(TokenSseEvent(text));

        // 16ms 合并后进入 reveal 队列
        async.elapse(const Duration(milliseconds: 16));
        var state = container.read(chatControllerProvider(''));
        expect(state.isRevealQueueEmpty, isFalse);

        final streamId = state.stream.streamingAssistantMessageId;

        // 64ms tick 1: 标准档固定吐 2 词单元
        async.elapse(const Duration(milliseconds: 64));
        state = container.read(chatControllerProvider(''));
        final contentAfterTick1 =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(contentAfterTick1, 'word ' * 2);
        expect(state.isRevealQueueEmpty, isFalse);

        // 64ms tick 2: 再次吐 2 词单元（累计 4 词）
        async.elapse(const Duration(milliseconds: 64));
        state = container.read(chatControllerProvider(''));
        final contentAfterTick2 =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(contentAfterTick2, 'word ' * 4);
        expect(state.isRevealQueueEmpty, isFalse);

        // 推进直至队列排空
        async.elapse(const Duration(seconds: 4));
        state = container.read(chatControllerProvider(''));
        final finalContent =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(finalContent, text);
        expect(state.isRevealQueueEmpty, isTrue);
      });
    });

    test('极快档：48ms tick + 自适应加速', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        unawaited(
          container
              .read(smoothStreamingSpeedProvider.notifier)
              .setSpeed(SmoothStreamingSpeedPreset.veryFast),
        );
        async.flushMicrotasks();

        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        final text = 'word ' * 50;
        api.emit(TokenSseEvent(text));

        async.elapse(const Duration(milliseconds: 16));
        var state = container.read(chatControllerProvider(''));
        expect(state.isRevealQueueEmpty, isFalse);

        final streamId = state.stream.streamingAssistantMessageId;

        // 48ms tick 1: backlog = 50 -> count = 5 + (50-8)~/12 = 8 词单元
        async.elapse(const Duration(milliseconds: 48));
        state = container.read(chatControllerProvider(''));
        final contentAfterTick1 =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(contentAfterTick1, 'word ' * 8);

        // 48ms tick 2: backlog = 42 -> count = 5 + (42-8)~/12 = 7 词单元（累计 15 词）
        async.elapse(const Duration(milliseconds: 48));
        state = container.read(chatControllerProvider(''));
        final contentAfterTick2 =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(contentAfterTick2, 'word ' * 15);

        async.elapse(const Duration(milliseconds: 500));
        state = container.read(chatControllerProvider(''));
        final finalContent =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(finalContent, text);
        expect(state.isRevealQueueEmpty, isTrue);
      });
    });

    test('流式中切换档位：立即重启 reveal timer 并在下一 tick 生效新速度', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        final text = 'word ' * 20;
        api.emit(TokenSseEvent(text));
        async.elapse(const Duration(milliseconds: 16));

        final streamId = container
            .read(chatControllerProvider(''))
            .stream
            .streamingAssistantMessageId;

        // 初始为标准档（64ms, 2 词）
        async.elapse(const Duration(milliseconds: 64));
        var state = container.read(chatControllerProvider(''));
        expect(
          state.messages.firstWhere((m) => m.messageId == streamId).content,
          'word ' * 2,
        );

        // 流式途中切换为极快档（48ms, 自适应）
        unawaited(
          container
              .read(smoothStreamingSpeedProvider.notifier)
              .setSpeed(SmoothStreamingSpeedPreset.veryFast),
        );
        async.flushMicrotasks();

        // 48ms 后以极快档 tick 消费（backlog=18 -> count = 5 + (18-8)~/12 = 5 词）
        async.elapse(const Duration(milliseconds: 48));
        state = container.read(chatControllerProvider(''));
        expect(
          state.messages.firstWhere((m) => m.messageId == streamId).content,
          'word ' * 7,
        );
      });
    });

    test('慢档 maxRevealLag 放宽：2s 积压不排空，达到档位上限（8s）才整段排空', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        unawaited(
          container
              .read(smoothStreamingSpeedProvider.notifier)
              .setSpeed(SmoothStreamingSpeedPreset.charByChar),
        );
        async.flushMicrotasks();

        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 逐字档：100ms 吐 1 词，maxRevealLag 为 8s
        final text = 'word ' * 30;
        api.emit(TokenSseEvent(text));
        async.elapse(const Duration(milliseconds: 16));

        final streamId = container
            .read(chatControllerProvider(''))
            .stream
            .streamingAssistantMessageId;

        // 运行 2s（远超原 1s maxRevealLag）
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));

        var state = container.read(chatControllerProvider(''));
        // 2000ms / 100ms = 20 ticks -> 吐出 20 词，未被 1s 误排空
        final contentAt2s =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(contentAt2s, 'word ' * 20);
        expect(state.isRevealQueueEmpty, isFalse);

        // 再过 6s（累计 8s >= charByChar.maxRevealLag 8s）触发排空
        clock.advance(const Duration(seconds: 6));
        async.elapse(const Duration(seconds: 6));

        state = container.read(chatControllerProvider(''));
        final finalContent =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(finalContent, text);
        expect(state.isRevealQueueEmpty, isTrue);
      });
    });

    test('smoothStreaming 关闭时：16ms merge 直接落全文，不经过 reveal 延迟', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        // 关闭平滑输出
        unawaited(
          container
              .read(smoothStreamingProvider.notifier)
              .setSmoothStreaming(false),
        );
        async.flushMicrotasks();

        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('Hello World from fast stream! '));
        var state = container.read(chatControllerProvider(''));
        expect(state.pendingAssistantTokenChunks, [
          'Hello World from fast stream! ',
        ]);

        // 16ms 合并后直接落地全文，无 reveal 队列延迟
        async.elapse(const Duration(milliseconds: 16));
        state = container.read(chatControllerProvider(''));
        final streamId = state.stream.streamingAssistantMessageId;
        final content =
            state.messages.firstWhere((m) => m.messageId == streamId).content ??
            '';
        expect(content, 'Hello World from fast stream! ');
        expect(state.isRevealQueueEmpty, isTrue);
      });
    });
  });
  group('token 三段式缓冲（§3.1）', () {
    test('16ms 合并 + reveal 词级 reveal，收尾全量 flush', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // token 只入缓冲，不改 messages
        api.emit(const TokenSseEvent('Hello '));
        api.emit(const TokenSseEvent('world'));
        var state = container.read(chatControllerProvider(''));
        expect(state.pendingAssistantTokenChunks, ['Hello ', 'world']);
        // 流开始即锚定空流式气泡（思考中指示器）；内容在 flush 前为空
        expect(state.stream.streamingAssistantMessageId, isNotNull);
        final emptyStreaming = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(emptyStreaming!.content, '');

        // 16ms 合并 → reveal 队列（仍不改 messages）
        async.elapse(const Duration(milliseconds: 16));
        state = container.read(chatControllerProvider(''));
        expect(state.pendingAssistantTokenChunks, isEmpty);
        final stillEmpty = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(stillEmpty!.content, '');

        // reveal tick（标准档 64ms）→ 内容落地
        async.elapse(ChatController.revealInterval);
        state = container.read(chatControllerProvider(''));
        final streaming = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(streaming, isNotNull);
        expect(streaming!.content, 'Hello world');

        // 完成路径全量 flush（stop → cancel ok → finishStream 先 flush）
        api.emit(const TokenSseEvent('!'));
        unawaited(controller.stop());
        async.flushMicrotasks();
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.stream.streamingAssistantMessageId, isNull);
        // 文本保留在最后一条 assistant 消息
        final last = state.messages.last;
        expect(last.role, 'assistant');
        expect(last.content, 'Hello world!');
      });
    });

    test('reasoning 整块 flush（不走词级 pacing）', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const ReasoningSseEvent('think step 1'));
        var state = container.read(chatControllerProvider(''));
        expect(state.pendingReasoningChunks, ['think step 1']);
        expect(state.liveReasoningText, isEmpty);

        async.elapse(const Duration(milliseconds: 16));
        state = container.read(chatControllerProvider(''));
        expect(state.pendingReasoningChunks, isEmpty);
        expect(state.liveReasoningText, 'think step 1');
      });
    });
  });

  group('interim_assistant（§3.3）', () {
    test('already_streamed=true 或空文本 → 忽略', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const InterimAssistantSseEvent(text: 'dup', alreadyStreamed: true),
        );
        api.emit(
          const InterimAssistantSseEvent(text: '   ', alreadyStreamed: false),
        );
        expect(
          container.read(chatControllerProvider('')).messages,
          hasLength(2),
        );
      });
    });

    test('先 flush 积压 token 再追加，非 replay 用 \\n\\n 分隔', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('partial '));
        api.emit(
          const InterimAssistantSseEvent(
            text: 'full paragraph',
            alreadyStreamed: false,
          ),
        );
        final state = container.read(chatControllerProvider(''));
        final streaming = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(streaming!.content, 'partial \n\nfull paragraph');
      });
    });
  });

  group('工具调用（§3.5）', () {
    test('tool 追加未完成 → tool_complete 按 stableID 补全', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't1', name: 'bash', args: {'cmd': 'ls'}),
          ),
        );
        var state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(1));
        expect(state.liveToolCalls.first.isCompleted, isFalse);
        expect(state.liveToolCalls.first.name, 'bash');
        expect(state.stream.toolCallAnchorMessageId, isNotNull);

        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(
              stableId: 't1',
              name: 'bash',
              duration: 1.5,
              isError: false,
            ),
          ),
        );
        state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls.first.isCompleted, isTrue);
        expect(state.liveToolCalls.first.duration, 1.5);
      });
    });

    test('tool_complete 匹配不到 → 兜底 append 已完成项', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(name: 'shell', preview: 'done', isError: false),
          ),
        );
        final state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(1));
        expect(state.liveToolCalls.first.isCompleted, isTrue);
        expect(state.liveToolCalls.first.displayName, 'shell');
      });
    });

    test('done 携带 session.toolCalls → 重建 completedToolCallGroups 并清 live', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't1', name: 'bash'),
          ),
        );
        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's1',
                'messages': [
                  {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
                  {
                    'role': 'assistant',
                    'content': 'answer',
                    'message_id': 'a1',
                  },
                ],
                'tool_calls': [
                  {
                    'name': 'bash',
                    'snippet': 'out',
                    'tid': 't1',
                    'assistant_msg_idx': 1,
                  },
                ],
              },
            ),
          ),
        );
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.liveToolCalls, isEmpty);
        expect(state.completedToolCallGroups, isNotEmpty);
        expect(state.completedToolCallGroups.first.toolCalls, hasLength(1));
        expect(
          state.completedToolCallGroups.first.toolCalls.first.isCompleted,
          isTrue,
        );
      });
    });
  });

  group('同回合连续工具调用合并-Hermes 真实形状（role=tool 结果+空文本 assistant 交替）', () {
    test('Hermes 会话：带文本助理+工具结果+空文本助理+工具结果 → 合并为一组 ×2', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('跑测试'));
        async.flushMicrotasks();

        // 形状对齐 state.db e4954fe3579e 真实记录：
        // user → assistant(文本+tool_calls) → tool(结果) → assistant(空+tool_calls) → tool(结果)
        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's1',
                'messages': [
                  {
                    'role': 'user',
                    'content': 'analyze 零告警 + 57 全绿。最后全量验证后提交：',
                    'message_id': 'u1',
                  },
                  {
                    'role': 'assistant',
                    'content': 'analyze 零告警 + 57 全绿。最后全量验证后提交：',
                    'message_id': 'a1',
                    'tool_calls': [
                      {
                        'id': 'call_5c10811e',
                        'call_id': 'call_5c10811e',
                        'response_item_id': 'fc_5c10811e',
                        'type': 'function',
                        'function': {
                          'name': 'terminal',
                          'arguments': '{"command":"flutter test"}',
                        },
                      },
                    ],
                  },
                  {
                    'role': 'tool',
                    'tool_call_id': 'call_5c10811e',
                    'content': '{"output": "01:04 +1669 ..."}',
                  },
                  {
                    'role': 'assistant',
                    'content': '',
                    'message_id': 'a2',
                    'tool_calls': [
                      {
                        'id': 'call_14dce38b',
                        'call_id': 'call_14dce38b',
                        'response_item_id': 'fc_14dce38b',
                        'type': 'function',
                        'function': {
                          'name': 'terminal',
                          'arguments': '{"command":"git commit ..."}',
                        },
                      },
                    ],
                  },
                  {
                    'role': 'tool',
                    'tool_call_id': 'call_14dce38b',
                    'content': '{"output": "warning: ..."}',
                  },
                ],
                'tool_calls': [
                  {
                    'name': 'terminal',
                    'snippet': 'out1',
                    'tid': 'call_5c10811e',
                    'assistant_msg_idx': 1,
                  },
                  {
                    'name': 'terminal',
                    'snippet': 'out2',
                    'tid': 'call_14dce38b',
                    'assistant_msg_idx': 3,
                  },
                ],
              },
            ),
          ),
        );
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        // Hermes 真实形状：同回合连续两个终端（含空文本 assistant 间隔）应合并
        expect(state.completedToolCallGroups, hasLength(1));
        expect(state.completedToolCallGroups.first.toolCalls, hasLength(2));
        expect(
          state.completedToolCallGroups.first.toolCalls.map(
            (t) => t.displayName,
          ),
          everyElement('terminal'),
        );
      });
    });
  });

  group('同回合连续工具调用合并（§工具聚合）', () {
    test('done 会话跨两条 assistant 消息的连续工具调用 → 合并为一组（终端 ×2）', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('跑测试'));
        async.flushMicrotasks();

        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's1',
                'messages': [
                  {'role': 'user', 'content': '跑测试', 'message_id': 'u1'},
                  {
                    'role': 'assistant',
                    'content': '先跑全量测试',
                    'message_id': 'a1',
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': 'terminal',
                          'arguments': '{"command":"flutter test"}',
                        },
                      },
                    ],
                  },
                  {
                    'role': 'user',
                    'content': '{"exit_code":0}',
                    'email': null,
                    'name': null,
                    'tool_call_id': 'call_1',
                  },
                  {
                    'role': 'assistant',
                    'content': '',
                    'message_id': 'a2',
                    'tool_calls': [
                      {
                        'id': 'call_2',
                        'type': 'function',
                        'function': {
                          'name': 'terminal',
                          'arguments': '{"command":"flutter analyze"}',
                        },
                      },
                    ],
                  },
                  {
                    'role': 'user',
                    'content': '{"exit_code":0}',
                    'tool_call_id': 'call_2',
                  },
                ],
                'tool_calls': [
                  {
                    'name': 'terminal',
                    'snippet': 'out',
                    'tid': 'call_1',
                    'assistant_msg_idx': 1,
                  },
                  {
                    'name': 'terminal',
                    'snippet': 'out',
                    'tid': 'call_2',
                    'assistant_msg_idx': 3,
                  },
                ],
              },
            ),
          ),
        );
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        // 同回合两次连续终端调用应合并为一组、两张调用记录
        expect(state.completedToolCallGroups, hasLength(1));
        expect(state.completedToolCallGroups.first.toolCalls, hasLength(2));
        expect(
          state.completedToolCallGroups.first.toolCalls.map(
            (t) => t.displayName,
          ),
          everyElement('terminal'),
        );
      });
    });

    test('coalesce=false 时无打断的相邻工具仍合并为一组（相邻聚合语义）', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        // 开关关闭：设置为 false 触发监听重建
        unawaited(
          container.read(toolGroupCoalesceProvider.notifier).setCoalesce(false),
        );
        async.flushMicrotasks();
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('跑测试'));
        async.flushMicrotasks();

        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's1',
                'messages': [
                  {'role': 'user', 'content': '跑测试', 'message_id': 'u1'},
                  {
                    'role': 'assistant',
                    'content': '先跑全量测试',
                    'message_id': 'a1',
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': 'terminal',
                          'arguments': '{"command":"flutter test"}',
                        },
                      },
                    ],
                  },
                  {
                    'role': 'user',
                    'content': '{"exit_code":0}',
                    'tool_call_id': 'call_1',
                  },
                  {
                    'role': 'assistant',
                    'content': '',
                    'message_id': 'a2',
                    'tool_calls': [
                      {
                        'id': 'call_2',
                        'type': 'function',
                        'function': {
                          'name': 'terminal',
                          'arguments': '{"command":"flutter analyze"}',
                        },
                      },
                    ],
                  },
                  {
                    'role': 'user',
                    'content': '{"exit_code":0}',
                    'tool_call_id': 'call_2',
                  },
                ],
                'tool_calls': [
                  {
                    'name': 'terminal',
                    'snippet': 'out',
                    'tid': 'call_1',
                    'assistant_msg_idx': 1,
                  },
                  {
                    'name': 'terminal',
                    'snippet': 'out',
                    'tid': 'call_2',
                    'assistant_msg_idx': 3,
                  },
                ],
              },
            ),
          ),
        );
        final state = container.read(chatControllerProvider(''));
        // a1(有文本)+tool → result → a2(空)+tool：间隔内无 text/think → 相邻合并 1 组
        expect(state.completedToolCallGroups, hasLength(1));
        expect(state.completedToolCallGroups.first.toolCalls, hasLength(2));
      });
    });

    test('coalesce=false 时被文本打断则拆分（Hermes 形状含中间文本消息）', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        // 开关关闭
        unawaited(
          container.read(toolGroupCoalesceProvider.notifier).setCoalesce(false),
        );
        async.flushMicrotasks();
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('跑测试'));
        async.flushMicrotasks();

        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's1',
                'messages': [
                  {'role': 'user', 'content': '跑测试', 'message_id': 'u1'},
                  {
                    'role': 'assistant',
                    'content': '先跑全量测试',
                    'message_id': 'a1',
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': 'terminal',
                          'arguments': '{"command":"flutter test"}',
                        },
                      },
                    ],
                  },
                  {
                    'role': 'assistant',
                    'content': '测试通过，继续验证分析',
                    'message_id': 'a_break',
                  },
                  {
                    'role': 'assistant',
                    'content': '',
                    'message_id': 'a2',
                    'tool_calls': [
                      {
                        'id': 'call_2',
                        'type': 'function',
                        'function': {
                          'name': 'terminal',
                          'arguments': '{"command":"flutter analyze"}',
                        },
                      },
                    ],
                  },
                ],
                'tool_calls': [
                  {
                    'name': 'terminal',
                    'snippet': 'out1',
                    'tid': 'call_1',
                    'assistant_msg_idx': 1,
                  },
                  {
                    'name': 'terminal',
                    'snippet': 'out2',
                    'tid': 'call_2',
                    'assistant_msg_idx': 3,
                  },
                ],
              },
            ),
          ),
        );
        final state = container.read(chatControllerProvider(''));
        // 中间 assistant 有可见文本 → 打断相邻聚合 → 2 组
        expect(state.completedToolCallGroups, hasLength(2));
      });
    });
  });

  group('done 收尾（§3.7，易错点 #3）', () {
    test('done 带 transcript → 服务端替换 + 清流状态；stream_end 不重复收尾', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('local '));
        async.elapse(const Duration(milliseconds: 64));

        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's1',
                'messages': [
                  {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
                  {
                    'role': 'assistant',
                    'content': 'server answer',
                    'message_id': 'a1',
                  },
                ],
              },
              usage: {'input_tokens': 10, 'output_tokens': 20, 'tps': 8.5},
            ),
          ),
        );
        var state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.stream.activeStreamId, isNull);
        expect(state.stream.hasCompletedResponse, isTrue);
        expect(state.messages, hasLength(2));
        expect(state.messages.last.content, 'server answer');
        expect(state.contextWindowSnapshot, isNotNull);
        expect(state.messages.last.turnTps, 8.5);

        // stream_end 因 hasCompletedResponse 不重复收尾，但 finishStream 清理
        api.emit(const StreamEndSseEvent());
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.messages, hasLength(2));
      });
    });

    test('done 无 transcript → needsTranscriptRefresh → status 轮询兜底', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        var state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.responseCompletionNeedsTranscriptRefresh, isTrue);

        final sessionCallsBefore = api.sessionCalls;
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();
        expect(api.statusCalls, greaterThan(0));
        expect(api.sessionCalls, greaterThan(sessionCallsBefore));
        state = container.read(chatControllerProvider(''));
        expect(state.responseCompletionNeedsTranscriptRefresh, isFalse);
      });
    });

    test('TASK #112: 模拟 done → refresh 序列，completedToolCallGroups 无死锚残留', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('跑一下测试'));
        async.flushMicrotasks();

        // 流式期间收到工具调用
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(
              stableId: 'call_1',
              name: 'terminal',
              args: {'cmd': 'flutter test'},
            ),
          ),
        );
        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(
              stableId: 'call_1',
              name: 'terminal',
              duration: 120,
            ),
          ),
        );
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(1));

        // done 到达（无 transcript，触发 needsTranscriptRefresh）
        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.responseCompletionNeedsTranscriptRefresh, isTrue);

        // 服务端 state.db 读取路径：消息不携带 message_id（ChatMessage.messageId = null）
        api.sessionResult = {
          'session': {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': '跑一下测试'},
              {'role': 'assistant', 'content': '测试已完成'},
            ],
            'tool_calls': [
              {
                'name': 'terminal',
                'args': {'cmd': 'flutter test'},
                'assistant_msg_idx': 1,
                'tid': 'call_1',
              },
            ],
          },
        };

        // 推进 600ms 触发 refreshTranscriptIfCompleted 轮询
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        state = container.read(chatControllerProvider(''));
        expect(state.responseCompletionNeedsTranscriptRefresh, isFalse);

        // 收集当前 messages 的所有合法 anchorID（含 assistant anchorID）
        final currentAnchors = <String>{
          for (var i = 0; i < state.messages.length; i++) ...[
            TranscriptTurnClassifier.anchorID(
              state.messages[i],
              at: i,
              messageOffset: state.messagesOffset,
            ),
            if (state.messages[i].messageId != null)
              state.messages[i].messageId!,
          ],
        };

        // 断言：completedToolCallGroups 必须非空且全部命中当前 anchor 集合，无死锚残留（如 stream- 临时 id）
        expect(state.completedToolCallGroups, isNotEmpty);
        for (final group in state.completedToolCallGroups) {
          expect(group.anchorMessageID, isNotNull);
          expect(
            currentAnchors.contains(group.anchorMessageID),
            isTrue,
            reason:
                'Group ${group.id} 锚点 ${group.anchorMessageID} 是不在当前 anchor 集合内的死锚',
          );
          expect(
            group.anchorMessageID!.startsWith('stream-'),
            isFalse,
            reason: 'Group ${group.id} 仍残留流式临时 id: ${group.anchorMessageID}',
          );
        }
        // 且经去重合并后仅有 1 张卡
        expect(state.completedToolCallGroups, hasLength(1));
      });
    });

    test('error 事件 → sendErrorMessage + 回 idle；done 之后到达不显示', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const ErrorSseEvent('模型出错了'));
        var state = container.read(chatControllerProvider(''));
        expect(state.sendErrorMessage, '模型出错了');
        expect(state.phase, ChatPhase.idle);

        // 第二轮：done 收尾后 error 不显示
        unawaited(controller.send('again'));
        async.flushMicrotasks();
        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        api.emit(const ErrorSseEvent('晚了'));
        state = container.read(chatControllerProvider(''));
        expect(state.sendErrorMessage, isNot('晚了'));
        expect(state.phase, ChatPhase.idle);
      });
    });
  });

  group('stop / steer / queue（§4.2/§4.3）', () {
    test('stop → GET cancel → finishStream（cancelled 瞬时回 idle，文本保留）', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('keep me '));
        async.elapse(const Duration(milliseconds: 64));

        unawaited(controller.stop());
        async.flushMicrotasks();
        expect(api.cancelCalls, 1);
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.stream.isCancelling, isFalse);
        expect(state.messages.last.content, 'keep me ');
      });
    });

    test('stop 失败（ok=false）→ 流继续 + sendErrorMessage', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.cancelOk = false;
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        unawaited(controller.stop());
        async.flushMicrotasks();
        final state = container.read(chatControllerProvider(''));
        expect(state.stream.activeStreamId, isNotNull);
        expect(state.sendErrorMessage, isNotNull);
        expect(state.stream.isCancelling, isFalse);
      });
    });

    test('流式期间 send → steer accepted → steered；收到 token 回 streaming', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        unawaited(controller.send('更详细一点'));
        async.flushMicrotasks();
        expect(api.steerCalls, 1);
        var state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.steered);
        expect(state.steerHints, ['更详细一点']);
        expect(state.lastSteerHint, '更详细一点');
        // steer 不追加 user 气泡（仅乐观 user + 空流式气泡）
        expect(state.messages, hasLength(2));

        api.emit(const TokenSseEvent('ok '));
        async.elapse(const Duration(milliseconds: 64));
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
      });
    });

    test('连续 steer 多次 → steerHints 列表追加堆叠，支持单条与全量关闭，流结束全清', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 连续 steer 3 次
        unawaited(controller.send('提示一'));
        async.flushMicrotasks();
        unawaited(controller.send('提示二'));
        async.flushMicrotasks();
        unawaited(controller.send('提示三'));
        async.flushMicrotasks();

        expect(api.steerCalls, 3);
        var state = container.read(chatControllerProvider(''));
        expect(state.steerHints, ['提示一', '提示二', '提示三']);
        expect(state.lastSteerHint, '提示三');

        // 单条移除 index 1（提示二）
        controller.clearSteerHint(index: 1);
        state = container.read(chatControllerProvider(''));
        expect(state.steerHints, ['提示一', '提示三']);

        // 越界 index 不崩溃不影响
        controller.clearSteerHint(index: 99);
        state = container.read(chatControllerProvider(''));
        expect(state.steerHints, ['提示一', '提示三']);

        // 全清
        controller.clearSteerHint();
        state = container.read(chatControllerProvider(''));
        expect(state.steerHints, isEmpty);
        expect(state.lastSteerHint, isNull);

        // 再次 steer 并通过 done 结束流 → steerHints 自动清空
        unawaited(controller.send('新提示'));
        async.flushMicrotasks();
        expect(container.read(chatControllerProvider('')).steerHints, ['新提示']);

        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': ''})),
        );
        async.flushMicrotasks();
        expect(container.read(chatControllerProvider('')).steerHints, isEmpty);
      });
    });

    test('steer 被拒 → 入队 + notice + cancelActiveStream → 队列顺次发送', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.steerAccepted = false;
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        unawaited(controller.send('被拒的消息'));
        async.flushMicrotasks();
        expect(api.cancelCalls, 1);
        final state = container.read(chatControllerProvider(''));
        // cancel ok → finishStream → pinned notice flush 进 transcript
        expect(
          state.messages.where((m) => m.role == 'local_notice'),
          isNotEmpty,
        );
        expect(api.startChatCalls, 2);
        expect(api.lastSentText, '被拒的消息');
        expect(state.queuedSlashMessages, isEmpty);
        expect(state.phase, ChatPhase.streaming);
      });
    });

    test('queue 行为 → 仅入队；done+stream_end 后自动发送', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        unawaited(
          controller.send('排队消息', behavior: StreamingSendBehavior.queue),
        );
        async.flushMicrotasks();
        var state = container.read(chatControllerProvider(''));
        expect(state.queuedSlashMessages, ['排队消息']);
        expect(state.pinnedLocalNotices, isNotEmpty);
        expect(api.startChatCalls, 1);

        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();
        expect(api.startChatCalls, 2);
        expect(api.lastSentText, '排队消息');
        state = container.read(chatControllerProvider(''));
        expect(state.queuedSlashMessages, isEmpty);
      });
    });

    test('pending_steer_leftover → 入队 + notice', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const PendingSteerLeftoverSseEvent('剩余提示'));
        final state = container.read(chatControllerProvider(''));
        expect(state.queuedSlashMessages, ['剩余提示']);
        expect(state.pinnedLocalNotices, hasLength(1));
      });
    });
  });

  group('transportError 断线恢复（§5.3）', () {
    test('active==true → loadMessages 重载 → 全量重连', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': true, 'replay_available': false};
        api.sessionResult = {
          'session': {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
              {
                'role': 'assistant',
                'content': 'partial answer',
                'message_id': 'a1',
              },
            ],
          },
        };
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TransportErrorSseEvent('连接断开'));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, greaterThan(0));
        expect(api.streamIds, hasLength(2));
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.isSuspended, isFalse);
        expect(state.stream.activeStreamId, 'stream-1');
        expect(state.messages, isNotEmpty);
      });
    });

    test('replayAvailable==true → replay=1&after_seq=N 重连', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': false, 'replay_available': true};
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 记录 SSE 事件 id（lastEventID 语义：事件 id: 字段）
        api.emitId('evt:42');
        api.emit(const TransportErrorSseEvent('断开'));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.streamIds, hasLength(2));
        expect(api.replaySeqs.last, 42);
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.recovery, ActiveStreamRecoveryState.idle);
      });
    });

    test('非 active 且无 replay → loadMessages 按 transcript finalize', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': false, 'replay_available': false};
        api.sessionResult = {
          'session': {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
              {
                'role': 'assistant',
                'content': 'final answer',
                'message_id': 'a1',
              },
            ],
          },
        };
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TransportErrorSseEvent('断开'));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.stream.activeStreamId, isNull);
        expect(state.messages, hasLength(2));
      });
    });

    test('流已结束后的迟到 transportError → 无连接可恢复 → 错误收尾', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 流已结束（done + stream_end 后 activeStreamId 已清空）
        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        api.emit(const StreamEndSseEvent());
        // 迟到的 transportError → 无连接可恢复 → 错误收尾
        api.fail('迟到的断开');
        final state = container.read(chatControllerProvider(''));
        expect(state.sendErrorMessage, '迟到的断开');
        expect(state.phase, ChatPhase.idle);
      });
    });

    test('看门狗：5s 无进度 + 12s 无传输 → status 检查', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': true, 'replay_available': false};
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        clock.advance(const Duration(seconds: 13));
        async.elapse(const Duration(seconds: 13));
        async.flushMicrotasks();
        expect(api.statusCalls, greaterThan(0));
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
      });
    });
  });

  group('title / metering（§3.6）', () {
    test('session_id 不匹配 → 忽略；匹配才生效', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TitleSseEvent(sessionId: 'other', title: '错标题'));
        expect(
          container.read(chatControllerProvider('s1')).displayTitle,
          'Untitled Session',
        );
        api.emit(const TitleSseEvent(sessionId: 's1', title: '  真标题  '));
        expect(
          container.read(chatControllerProvider('s1')).displayTitle,
          '真标题',
        );

        api.emit(
          const MeteringSseEvent(
            tps: 12.5,
            tpsAvailable: true,
            estimated: false,
            sessionId: 's1',
          ),
        );
        expect(
          container
              .read(chatControllerProvider('s1'))
              .stream
              .liveTokensPerSecond,
          12.5,
        );
        // tps<=0 不更新
        api.emit(
          const MeteringSseEvent(
            tps: -1,
            tpsAvailable: true,
            estimated: false,
            sessionId: 's1',
          ),
        );
        expect(
          container
              .read(chatControllerProvider('s1'))
              .stream
              .liveTokensPerSecond,
          12.5,
        );
      });
    });
  });

  group('approval / clarify（§2.3）', () {
    test('approval 事件 → approvalPending；作答后回 streaming', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ApprovalPendingSseEvent({
            'pending': {
              'question': '允许执行?',
              'choices': ['允许', '拒绝'],
            },
          }),
        );
        var state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.approvalPending);
        expect(state.pendingAction.hasPendingPrompt, isTrue);

        unawaited(controller.respondToApproval('允许'));
        async.flushMicrotasks();
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
        expect(state.pendingAction.approvalPrompt, isNull);
      });
    });

    test('clarify 事件 → clarifyPending', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {
              'question': '哪个方案?',
              'choices_offered': ['A', 'B'],
            },
          }),
        );
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.clarifyPending);
        expect(state.pendingAction.clarificationPrompt, isNotNull);
      });
    });
  });

  group('replay 去重算法（§5.6，逐分支）', () {
    ({String remainder, int newCursor, bool stillReplay}) dedup(
      String token,
      String existing, {
      int cursor = 0,
    }) {
      return ChatController.deduplicatedReplayToken(
        token: token,
        existingContent: existing,
        matchedPrefixLength: cursor,
      );
    }

    test('existingContent 为空 → 原样返回 + 关闭 replay', () {
      final result = dedup('abc', '');
      expect(result.remainder, 'abc');
      expect(result.stillReplay, isFalse);
    });

    test('expectedRemainder.hasPrefix(token) → 纯重复，游标前进', () {
      final result = dedup('world', 'Hello world', cursor: 6);
      expect(result.remainder, '');
      // 游标 ≥ existingContent 长度后自动复位（§5.6 规则 3）
      expect(result.newCursor, 0);
      expect(result.stillReplay, isTrue);
    });

    test('token.hasPrefix(expectedRemainder) → 残余拼接', () {
      final result = dedup('world!', 'Hello world', cursor: 6);
      expect(result.remainder, '!');
      expect(result.newCursor, 0);
      expect(result.stillReplay, isTrue);
    });

    test('existingContent.hasPrefix(token) → 完全重复', () {
      final result = dedup('Hello', 'Hello world');
      expect(result.remainder, '');
      expect(result.stillReplay, isTrue);
    });

    test('existingContent.hasSuffix(token) → 完全重复', () {
      final result = dedup('world', 'Hello world');
      expect(result.remainder, '');
      expect(result.stillReplay, isTrue);
    });

    test('token.hasPrefix(existingContent) → 返回多出的部分', () {
      final result = dedup('Hello world!', 'Hello world');
      expect(result.remainder, '!');
      expect(result.stillReplay, isTrue);
    });

    test('最大重叠扫描（后缀 ∩ 前缀）', () {
      final result = dedup('world peace', 'Hello world');
      // existing 'Hello world' 后缀 'world' ∩ token 前缀 'world' → 重叠 5
      expect(result.remainder, ' peace');
      expect(result.stillReplay, isTrue);
    });

    test('皆不匹配 → 原样返回 + 关闭 replay', () {
      final result = dedup('xyz', 'Hello world');
      expect(result.remainder, 'xyz');
      expect(result.stillReplay, isFalse);
      expect(result.newCursor, 0);
    });

    test('游标 ≥ existingContent 长度后自动复位', () {
      final result = dedup('!', 'Hello', cursor: 5);
      expect(result.newCursor, 0);
    });
  });

  group('replay 连接内 token 去重集成（§6.4）', () {
    test('重连后重复 token 被吃掉，只追加新增部分', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': false, 'replay_available': true};
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('Hello world'));
        async.elapse(const Duration(milliseconds: 100));

        // 断开重连（replay）
        api.emitId('evt:5');
        api.emit(const TransportErrorSseEvent('断开'));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.streamIds, hasLength(2));
        expect(
          container.read(chatControllerProvider('')).stream.isReplayConnection,
          isTrue,
        );

        // 重放：先 Hello（已有，吃掉）再 world（已有，吃掉）再 !（新增）
        api.emit(const TokenSseEvent('Hello'));
        async.elapse(const Duration(milliseconds: 100));
        api.emit(const TokenSseEvent(' world'));
        async.elapse(const Duration(milliseconds: 100));
        api.emit(const TokenSseEvent('!'));
        async.elapse(const Duration(milliseconds: 100));

        final state = container.read(chatControllerProvider(''));
        final streaming = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(streaming!.content, 'Hello world!');
      });
    });
  });

  group('词单元切分', () {
    test('英文按空白切分且拼接无损', () {
      expect(ChatController.splitIntoWordUnits('Hello world!'), [
        'Hello ',
        'world!',
      ]);
      expect(
        ChatController.splitIntoWordUnits('Hello world!').join(),
        'Hello world!',
      );
    });

    test('无空白 CJK 长串按 cjkChunkSize 粒度切分', () {
      const text = '你好世界你好世界你好';
      // 默认 8 字符切一刀
      final unitsDefault = ChatController.splitIntoWordUnits(text);
      expect(unitsDefault, ['你好世界你好世界', '你好']);
      expect(unitsDefault.join(), text);

      // 1 字符切一刀（逐字）
      final units1 = ChatController.splitIntoWordUnits(text, cjkChunkSize: 1);
      expect(units1, ['你', '好', '世', '界', '你', '好', '世', '界', '你', '好']);
      expect(units1.join(), text);

      // 2 字符切一刀（慢/标准）
      final units2 = ChatController.splitIntoWordUnits(text, cjkChunkSize: 2);
      expect(units2, ['你好', '世界', '你好', '世界', '你好']);
      expect(units2.join(), text);

      // 4 字符切一刀（快）
      final units4 = ChatController.splitIntoWordUnits(text, cjkChunkSize: 4);
      expect(units4, ['你好世界', '你好世界', '你好']);
      expect(units4.join(), text);

      // 8 字符切一刀（极快）
      final units8 = ChatController.splitIntoWordUnits(text, cjkChunkSize: 8);
      expect(units8, ['你好世界你好世界', '你好']);
      expect(units8.join(), text);
    });
  });

  group('会话操作（第一阶段：聊天页会话菜单）', () {
    test('重命名成功 → 更新 displayTitle', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final ok = await controller.renameSession('新标题');
      expect(ok, isTrue);
      expect(container.read(chatControllerProvider('s1')).displayTitle, '新标题');
      expect(api.renameCalls, 1);
      expect(api.lastRenameTitle, '新标题');
    });

    test('重命名空白标题 → 拒绝且不发请求', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final ok = await controller.renameSession('   ');
      expect(ok, isFalse);
      expect(api.renameCalls, 0);
    });

    test('重命名服务端失败 → 返回 false 且设置错误', () async {
      final api = _FakeChatApi();
      api.mutationOk = false;
      api.mutationError = '标题已存在';
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final ok = await controller.renameSession('新标题');
      expect(ok, isFalse);
      expect(
        container.read(chatControllerProvider('s1')).sendErrorMessage,
        '标题已存在',
      );
    });

    test('重命名网络异常 → 返回 false 且设置错误', () async {
      final api = _FakeChatApi();
      api.mutationThrows = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final ok = await controller.renameSession('新标题');
      expect(ok, isFalse);
      expect(
        container.read(chatControllerProvider('s1')).sendErrorMessage,
        startsWith('无法连接'),
      );
    });

    test('置顶/归档成功 → 返回 true', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.setPinned(true), isTrue);
      expect(api.pinCalls, 1);
      expect(api.lastPinned, isTrue);
      expect(await controller.setArchived(true), isTrue);
      expect(api.archiveCalls, 1);
      expect(api.lastArchived, isTrue);
    });

    test('置顶保持状态 → 返回 true', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.setPinned(false), isTrue);
      expect(api.lastPinned, isFalse);
      expect(await controller.setArchived(false), isTrue);
      expect(api.lastArchived, isFalse);
    });

    test('删除成功 → 返回 true', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.deleteSession(), isTrue);
      expect(api.deleteCalls, 1);
    });

    test('分支成功 → 返回新会话 ID', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final newId = await controller.branchSession();
      expect(newId, 'branch-s1');
      expect(api.branchCalls, 1);
    });

    test('消息级 branchAt：keep_count=index+1，越界拒绝', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'm0', 'message_id': 'u0'},
            {'role': 'assistant', 'content': 'm1', 'message_id': 'a0'},
            {'role': 'user', 'content': 'm2', 'message_id': 'u1'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      // 先加载 3 条消息
      await controller.loadMessages();
      expect(container.read(chatControllerProvider('s1')).messages.length, 3);

      // 从第 2 条（index=1）分支 → keep_count=2
      final newId = await controller.branchAt(1);
      expect(newId, 'branch-s1');
      expect(api.branchCalls, 1);
      expect(api.lastBranchKeepCount, 2);

      // 越界 → 拒绝
      expect(await controller.branchAt(3), isNull);
      expect(api.branchCalls, 1);
    });

    test('新会话（空 sessionId）操作全部拒绝', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('').notifier);

      expect(await controller.renameSession('标题'), isFalse);
      expect(await controller.setPinned(true), isFalse);
      expect(await controller.setArchived(true), isFalse);
      expect(await controller.deleteSession(), isFalse);
      expect(await controller.branchSession(), isNull);
      expect(api.renameCalls, 0);
      expect(api.pinCalls, 0);
      expect(api.archiveCalls, 0);
      expect(api.deleteCalls, 0);
      expect(api.branchCalls, 0);
    });

    test('从此处截断成功 → keepCount = index+1 并刷新', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
            {'role': 'assistant', 'content': 'b', 'message_id': 'm2'},
            {'role': 'user', 'content': 'c', 'message_id': 'm3'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      final ok = await controller.truncateAt(1);
      expect(ok, isTrue);
      expect(api.truncateCalls, 1);
      expect(api.truncateKeepCounts, [2]);
    });

    test('从此处截断：includeTarget=false → keepCount=index（不含自己）', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
            {'role': 'assistant', 'content': 'b', 'message_id': 'm2'},
            {'role': 'user', 'content': 'c', 'message_id': 'm3'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      final ok = await controller.truncateAt(1, includeTarget: false);
      expect(ok, isTrue);
      expect(api.truncateCalls, 1);
      expect(api.truncateKeepCounts, [1]);
    });

    test('从此处截断：服务端失败 → false + 错误', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
            {'role': 'assistant', 'content': 'b', 'message_id': 'm2'},
          ],
        },
      };
      api.mutationOk = false;
      api.mutationError = '截断被拒绝';
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      final ok = await controller.truncateAt(0);
      expect(ok, isFalse);
      expect(
        container.read(chatControllerProvider('s1')).sendErrorMessage,
        '截断被拒绝',
      );
      expect(api.truncateKeepCounts, [1]);
    });

    test('从此处截断：越界 → false 且不发请求', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      expect(await controller.truncateAt(5), isFalse);
      expect(await controller.truncateAt(-1), isFalse);
      expect(api.truncateCalls, 0);
    });

    test('prefillComposer → 设置 composerPrefill', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      controller.prefillComposer('回填内容');
      expect(
        container.read(chatControllerProvider('s1')).composerPrefill,
        '回填内容',
      );
    });

    test('只读会话：truncate/prefill 拒绝', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'read_only': true,
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      expect(await controller.truncateAt(0), isFalse);
      expect(api.truncateCalls, 0);
      controller.prefillComposer('x');
      expect(
        container.read(chatControllerProvider('s1')).composerPrefill,
        isNull,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 测试基础设施
// ---------------------------------------------------------------------------

class _FakeClock {
  DateTime now = DateTime(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

class _NoopCacheService extends CacheService {
  _NoopCacheService(super.db);
  @override
  Future<void> writeMessages({
    required String sessionId,
    required List<Map<String, Object?>> messages,
  }) async {}
  @override
  Future<List<Map<String, Object?>>> readMessages(String sessionId) async =>
      const [];
  @override
  Future<void> writeSessions(List<SessionSummary> sessions) async {}
  @override
  Future<List<SessionSummary>> readSessions() async => const [];
}

typedef _FakeChatApi = FakeChatApi;

ProviderContainer _buildContainer(_FakeChatApi api, _FakeClock clock) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.memory();
  final cache = _NoopCacheService(db);
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatClockProvider.overrideWithValue(clock.call),
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      appDatabaseProvider.overrideWithValue(db),
      cacheServiceProvider.overrideWithValue(cache),
    ],
  );
  addTearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    container.dispose();
  });
  return container;
}
