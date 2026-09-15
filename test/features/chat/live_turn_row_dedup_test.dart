import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// #121 回归：live 回合中途恢复/重载后，同一段正文不得在
/// 「live 层（时间线切片或 legacy 单气泡）」与「transcript 层（本回合服务端行）」
/// 各渲染一次 —— 真机表现为首行吞掉全回合正文、后续行又重复一遍。
///
/// 真机取证（session 20a4a6c7a7f5）：
/// 180659 = s1 + [skill_view, terminal]；180664 = s2 + [read_file, terminal]；
/// 180667 = s3 + [terminal, execute_code]；三段正文各自独立落库，服务端无重复。
void main() {
  const s1 = '主人これは—先确认现场：本喵先看 wisart 的用法和现有图标产线，再开工生成。';
  const s2 = '先看现有产线和素材，确认「反色剪影」现在长什么样，再定变体方向。';
  const s3 = '本喵先看一眼现状（源图 + 当前反色剪影 + 大图标），再决定变体方向。';

  group('#121 live 回合中途恢复不得重复正文本', () {
    test('中段重载并入本回合服务端行后，每段正文在可见层只出现一次', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // live 事件序（与真机一致）：思考 → 正文 s1 → 工具 → 正文 s2 → 工具 → 正文 s3
        api.emit(const ReasoningSseEvent('先确认现场。'));
        api.emit(const InterimAssistantSseEvent(text: s1, alreadyStreamed: false));
        async.elapse(const Duration(milliseconds: 64));
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'skill_view'),
          ),
        );
        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'skill_view'),
          ),
        );
        async.flushMicrotasks();

        api.emit(const InterimAssistantSseEvent(text: s2, alreadyStreamed: false));
        async.elapse(const Duration(milliseconds: 64));
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-2', name: 'read_file'),
          ),
        );
        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(stableId: 't-2', name: 'read_file'),
          ),
        );
        async.flushMicrotasks();

        api.emit(const InterimAssistantSseEvent(text: s3, alreadyStreamed: false));
        async.elapse(const Duration(milliseconds: 64));

        final state = container.read(chatControllerProvider(''));
        expect(state.stream.activeStreamId, isNotNull, reason: '流应仍在进行中');
        final liveContent = _streamingContent(container);
        expect(
          liveContent,
          contains(s3),
          reason: '前置条件：live 层缓冲已累积三段正文',
        );

        // 回合中途恢复/重载：服务端 transcript 已含本回合三行（各带正文 + 工具）
        api.sessionResult = {
          'session': {
            'session_id': state.sessionId.isEmpty ? 'sess-1' : state.sessionId,
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
              {'role': 'assistant', 'content': s1, 'message_id': 'a1'},
              {'role': 'assistant', 'content': s2, 'message_id': 'a2'},
              {'role': 'assistant', 'content': s3, 'message_id': 'a3'},
            ],
            'message_count': 4,
            'tool_calls': [
              {'name': 'skill_view', 'tid': 't-1'},
              {'name': 'read_file', 'tid': 't-2'},
            ],
          },
        };
        unawaited(controller.loadMessages());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));

        final blocks = _visibleTextBlocks(container);
        for (final paragraph in <String>[s1, s2, s3]) {
          final hits = blocks.where((b) => b.contains(paragraph)).length;
          expect(
            hits,
            1,
            reason: '「$paragraph」在可见正文块里出现了 $hits 次（应为 1 次）\n'
                '可见块明细：${blocks.map((b) => b.length > 24 ? '${b.substring(0, 24)}…' : b).toList()}',
          );
        }
        // 不得出现「一段吞掉多段」的整段块（真机首行形态）。
        for (final block in blocks) {
          final paragraphs = <String>[
            s1,
            s2,
            s3,
          ].where((p) => block.contains(p)).length;
          expect(
            paragraphs,
            lessThanOrEqualTo(1),
            reason: '单个正文块吞掉了 $paragraphs 个段落：${block.substring(0, block.length.clamp(0, 40))}',
          );
        }
        // 修复①：live 行身份必须保住 → live 层仍在（否则整轮内容退回 transcript 单层渲染）。
        expect(
          container.read(streamingMessageProvider('')),
          isNotNull,
          reason: '中段重载后流式消息身份不得丢失（live 层不能消失）',
        );
        final timeline = container.read(liveTimelineProvider(''));
        expect(timeline, isNotNull, reason: 'live 时间线不得回退 legacy');
        // 修复②：本回合工具卡不得丢（由 live 层承载）。
        final liveTools = <String>[
          for (final entry in timeline!)
            if (entry.toolGroup != null)
              for (final call in entry.toolGroup!.toolCalls)
                if ((call.name ?? '').isNotEmpty) call.name!,
        ];
        expect(
          liveTools,
          containsAll(<String>['skill_view', 'read_file']),
          reason: 'live 层应仍渲染本回合两张工具卡，实际：$liveTools',
        );
      });
    });

    test('服务端行含 live 层未渲染的正文时不得被跳过（不丢内容）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // live 只收到 s1（缓冲落后于服务端 checkpoint 的形态）
        api.emit(const InterimAssistantSseEvent(text: s1, alreadyStreamed: false));
        async.elapse(const Duration(milliseconds: 64));

        final state = container.read(chatControllerProvider(''));
        api.sessionResult = {
          'session': {
            'session_id': state.sessionId.isEmpty ? 'sess-1' : state.sessionId,
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
              {'role': 'assistant', 'content': s1, 'message_id': 'a1'},
              {'role': 'assistant', 'content': s2, 'message_id': 'a2'},
            ],
            'message_count': 3,
            'tool_calls': const [],
          },
        };
        unawaited(controller.loadMessages());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));

        final blocks = _visibleTextBlocks(container);
        expect(
          blocks.where((b) => b.contains(s2)).length,
          1,
          reason: 'live 层未渲染的 s2 必须由 transcript 渲染（不得被跳过）\n'
              '可见块：${blocks.map((b) => b.length > 20 ? '${b.substring(0, 20)}…' : b).toList()}',
        );
        expect(
          blocks.where((b) => b.contains(s1)).length,
          1,
          reason: 's1 已被 live 覆盖，只应渲染一次',
        );
      });
    });
  });
}

/// live 层正文缓冲（流式消息的 content）。
String _streamingContent(ProviderContainer container) {
  final streaming = container.read(streamingMessageProvider(''));
  return (streaming?.content ?? '').trim();
}

/// 复刻渲染层的可见正文块集合：
/// - transcript 行（跳过流式消息自身）→ 每行一个正文块；
/// - live 层：时间线模式取 text 段切片；legacy 兜底取整条流式气泡正文。
List<String> _visibleTextBlocks(ProviderContainer container) {
  final blocks = <String>[];
  for (final entry in container.read(transcriptMessagesProvider(''))) {
    final content = (entry.message.content ?? '').trim();
    if (content.isNotEmpty) blocks.add(content);
  }
  final streaming = container.read(streamingMessageProvider(''));
  if (streaming != null) {
    final timeline = container.read(liveTimelineProvider(''));
    if (timeline == null) {
      final content = (streaming.content ?? '').trim();
      if (content.isNotEmpty) blocks.add(content);
    } else {
      for (final entry in timeline) {
        if (entry.kind != LiveSegmentKind.text) continue;
        final slice = entry.textSlice.trim();
        if (slice.isNotEmpty) blocks.add(slice);
      }
    }
  }
  return blocks;
}

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

ProviderContainer _buildContainer(FakeChatApi api, _FakeClock clock) {
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
