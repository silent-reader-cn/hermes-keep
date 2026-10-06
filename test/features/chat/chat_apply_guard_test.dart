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
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 应用层活性守卫族（tag: chat_apply）行为测试。
///
/// 覆盖线上「SSE 一直在收帧、相位仍是 streaming，但正文/思考/工具卡永不更新」
/// 的静默冻结：既有自愈链（transport-stale / 死区兜底 / resume 探活）全部看不见
/// 这类卡死，只有「视图是否前进」这一判据能看见。
void main() {
  setUpAll(() async {
    // chat_apply 的 WARN / DEBUG 观测性断言依赖 DiagnosticsService 的内存缓冲。
    SharedPreferences.setMockInitialValues({kDiagnosticsEnabledKey: true});
    await DiagnosticsService.instance.init();
    await DiagnosticsService.instance.clear();
  });

  setUp(() {
    unawaited(DiagnosticsService.instance.clear());
  });

  group('G1 序号游标健全性（陈旧游标 → 全量重放）', () {
    test('afterSeq 超过本 run 已见最大 seq → 归 0，随后内容仍能落账', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 本 run 已到 seq=2，正文 A 已展示。
        api.emitId('s1:2');
        api.emit(const TokenSseEvent('A'));
        async.elapse(const Duration(milliseconds: 100));

        var state = container.read(chatControllerProvider(''));
        final streamingId = state.stream.streamingAssistantMessageId;
        expect(_messageContent(state, streamingId), 'A');
        expect(controller.maxSeenSeqForTesting, 2);

        // 陈旧游标：本地断点被写成远超本 run 已见最大 seq 的值
        // （上一回合残留 / 断点被覆写 —— 线上故障的成因）。
        controller.setStateForTesting(
          state.copyWith(stream: state.stream.copyWith(lastEventId: 's1:99')),
        );

        api.fail('net cut');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 2);

        state = container.read(chatControllerProvider(''));
        // 补丁前：afterSeq=99 → _connectStream(replayAfterSeq: 99)：闸门把
        // seq ≤ 99 的内容帧全部丢弃（连本该补回来的新内容一起丢）→ 永久冻结。
        expect(state.stream.replayAfterSeq, 0, reason: 'G1：陈旧游标必须归 0（全量重放）');
        expect(
          api.replaySeqs.last,
          isNull,
          reason: 'fullReconnect 不带 after_seq',
        );

        // 服务端从 0 重放：已展示内容被内容级去重吃掉，新帧必须落账。
        api.emitId('s1:1');
        api.emit(const TokenSseEvent('A'));
        async.elapse(const Duration(milliseconds: 100));
        api.emitId('s1:3');
        api.emit(const TokenSseEvent('B'));
        async.elapse(const Duration(milliseconds: 300));

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), 'AB');
        expect(_applyWarns('G1'), isNotEmpty);
      });
    });
  });

  group('G2 序号闸门自愈（连续丢弃且视图未前进 → 打开闸门）', () {
    test('连续丢弃 200 帧后闸门打开，后续内容落账（含节流 DEBUG 观测）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 先让本 run 见到 seq=300，再断线重连 → replayAfterSeq=300。
        api.emitId('s1:300');
        api.fail('net cut');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider(''));
        expect(state.stream.isReplayConnection, isTrue);
        expect(state.stream.replayAfterSeq, 300);
        final streamingId = state.stream.streamingAssistantMessageId;

        // 服务端从 seq 1 开始重放 200 帧：seq ≤ 300 → 闸门全部丢弃，本连接视图
        // 从未前进（=「收到帧但永不落账」）。
        for (var i = 1; i <= 200; i++) {
          api.emitId('s1:$i');
          api.emit(TokenSseEvent('帧$i'));
        }

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), '', reason: '闸门期间不得落账');
        expect(
          state.stream.isReplayConnection,
          isFalse,
          reason: 'G2：连续丢弃 200 帧且视图未前进 → 打开闸门',
        );
        expect(state.stream.replayAfterSeq, 0);

        // 闸门打开后，后续内容必须落账。
        // 补丁前：seq=201 ≤ 300 仍被丢弃 → 界面永久冻结（RED）。
        api.emitId('s1:201');
        api.emit(const TokenSseEvent('新正文'));
        async.elapse(const Duration(milliseconds: 300));

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), contains('新正文'));

        // 观测性：节流 DEBUG（第 1 次 + 每 200 次）+ G2 WARN。
        final debugs = _applyLogs(DiagnosticsLogLevel.debug, '重放序号闸门丢弃内容帧');
        expect(debugs, hasLength(2), reason: '第 1 次与第 200 次各一条');
        expect(debugs.first.message, contains('seq=1'));
        expect(debugs.first.message, contains('replayAfterSeq=300'));
        expect(_applyWarns('G2'), isNotEmpty);
      });
    });
  });

  group('G3 去重游标自愈 + 去重不变量收窄', () {
    test('游标已越过首字时，与首字同字的新 token 不得被吞（不变量收窄）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 已展示正文「图上」。
        api.emit(const TokenSseEvent('图上'));
        async.elapse(const Duration(milliseconds: 100));

        // 无 seq 断线重连 → 全量重放（replayAfterSeq=0，内容级去重生效）。
        api.fail('cut');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 2);

        // 重放帧「图」：游标 0 → 1（合法重复，被吞）。
        api.emit(const TokenSseEvent('图'));
        async.elapse(const Duration(milliseconds: 50));

        // 新到达的 token「图」：游标已越过首字，它不在「游标之后的已展示内容」
        // （只有「上」）里 → 不得吞。补丁前旧分支用整段 existingContent 的
        // startsWith(token) 命中 → 静默吞掉且游标不前进（RED：正文停在「图上」）。
        api.emit(const TokenSseEvent('图'));
        async.elapse(const Duration(milliseconds: 300));

        final state = container.read(chatControllerProvider(''));
        final streamingId = state.stream.streamingAssistantMessageId;
        expect(_messageContent(state, streamingId), '图上图');
      });
    });

    test('连续吞掉 ≥64 个 text 帧且游标零前进 → G3 归零游标 + WARN，随后内容仍落账', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('XY'));
        async.elapse(const Duration(milliseconds: 100));

        api.fail('cut');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        // 同构帧「Y」：与已展示内容尾部同字，游标 0 → 0（零前进），全被吞掉。
        for (var i = 0; i < 70; i++) {
          api.emit(const TokenSseEvent('Y'));
        }
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider(''));
        final streamingId = state.stream.streamingAssistantMessageId;
        expect(_messageContent(state, streamingId), 'XY', reason: '这些帧确实全被吞');
        expect(_applyWarns('G3'), isNotEmpty, reason: '连续吞帧 + 零前进 → 必须自愈');
        expect(
          controller.dedupSwallowStreakForTesting,
          6,
          reason: '第 64 帧触发自愈后计数归零，余 6 帧',
        );

        // 自愈后内容仍能正常落账。
        api.emit(const TokenSseEvent('Z'));
        async.elapse(const Duration(milliseconds: 300));
        expect(
          _messageContent(
            container.read(chatControllerProvider('')),
            streamingId,
          ),
          'XYZ',
        );
      });
    });
  });

  group('G4 管线再武装（定时器停摆后的积压）', () {
    test('缓冲有积压但 merge/reveal 定时器均为 null → 看门狗再武装后内容落账', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 后台期间只有「进缓冲」没有「落账」：_scheduleMerge 被 _appPaused 挡下，
        // 两个定时器都不存在。
        controller.setAppPausedForTesting(true);
        api.emit(const TokenSseEvent('积压正文'));
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider(''));
        final streamingId = state.stream.streamingAssistantMessageId;
        expect(state.pendingAssistantTokenChunks, isNotEmpty);
        expect(_messageContent(state, streamingId), '');
        expect(state.isRevealQueueEmpty, isTrue);

        // 回前台但**不走** resumed 铺全文路径（真实故障里定时器已死、无人调度）。
        controller.setAppPausedForTesting(false);
        expect(
          _messageContent(
            container.read(chatControllerProvider('')),
            streamingId,
          ),
          '',
          reason: '补丁前：没有任何人再调度 merge → 积压永久停在缓冲里',
        );

        async.elapse(const Duration(seconds: 1));
        async.elapse(const Duration(milliseconds: 300));

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), contains('积压正文'));
        expect(_applyWarns('G4'), isNotEmpty);
      });
    });
  });

  group('G5 视图活性看门狗', () {
    test('持续收帧但视图 25s 不前进 → WARN；再 10s 仍不前进 → 全量重连重建', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('XY'));
        async.elapse(const Duration(milliseconds: 100));

        api.fail('cut');
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 2);

        // 之后每 4s 来一帧与已展示内容尾部同字的「Y」：帧一直在到（传输活动
        // 永远新鲜）但全部被去重吞掉 → 视图签名一动不动 = 线上故障指纹。
        for (var i = 0; i < 12; i++) {
          api.emit(const TokenSseEvent('Y'));
          clock.advance(const Duration(seconds: 4));
          async.elapse(const Duration(seconds: 4));
        }

        final warnings = _applyWarns('G5');
        expect(warnings, hasLength(2), reason: '一次活性告警 + 一次升级告警（10s 观察期后仍不动）');
        expect(warnings.first.message, contains('视图活性看门狗'));
        expect(warnings.last.message, contains('全量重连'));
        expect(
          api.startStreamCalls,
          3,
          reason: 'G5 升级：fullReconnect 重放重建（补丁前恒为 2）',
        );
        expect(_applyWarns('G1'), isEmpty);
      });
    });

    test('长工具调用期间只有心跳、没有内容帧 → 不得误伤（不触发不重连）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'terminal'),
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        // 工具跑 60s：期间只有心跳（传输活动一直新鲜，但没有内容帧）。
        for (var i = 0; i < 15; i++) {
          api.emit(const HeartbeatSseEvent());
          clock.advance(const Duration(seconds: 4));
          async.elapse(const Duration(seconds: 4));
        }

        expect(_applyWarns('G5'), isEmpty, reason: '没有内容帧 → 守卫天然不适用');
        expect(_applyWarns('G4'), isEmpty);
        expect(api.startStreamCalls, 1, reason: '不得触发任何重连');
        expect(controller.viewSignatureForTesting, isNotEmpty);
      });
    });
  });

  group('反向用例：合法的 after_seq=0 全量重放不得被守卫误伤', () {
    test('大量重复帧（80）全被吞掉：不触发 G2/G3、不产生重复内容', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('AB'));
        async.elapse(const Duration(milliseconds: 100));

        // 无 seq 断线重连 → after_seq=0 的合法全量重放。
        api.fail('cut');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider(''));
        expect(state.stream.isReplayConnection, isTrue);
        expect(state.stream.replayAfterSeq, 0);
        final streamingId = state.stream.streamingAssistantMessageId;

        // 服务端把整段历史重放 40 遍（80 个重复帧）：全部应被去重吃掉。
        for (var i = 0; i < 40; i++) {
          api.emit(const TokenSseEvent('A'));
          api.emit(const TokenSseEvent('B'));
        }
        async.elapse(const Duration(milliseconds: 100));

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), 'AB', reason: '不得产生重复内容');
        expect(_applyWarns('G2'), isEmpty, reason: 'after_seq=0 全量重放：闸门根本不生效');
        expect(_applyWarns('G3'), isEmpty, reason: '帧按序匹配、游标一路前进 → 不构成「游标卡住」');

        // 重放结束后新内容正常接续（且只出现一次）。
        api.emit(const TokenSseEvent('C'));
        async.elapse(const Duration(milliseconds: 300));

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), 'ABC');
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 断言辅助
// ---------------------------------------------------------------------------

List<DiagnosticsLogEntry> _applyLogs(
  DiagnosticsLogLevel level,
  String needle,
) => DiagnosticsService.instance.logs
    .where(
      (e) =>
          e.tag == 'chat_apply' &&
          e.level == level &&
          e.message.contains(needle),
    )
    .toList();

List<DiagnosticsLogEntry> _applyWarns(String needle) =>
    _applyLogs(DiagnosticsLogLevel.warn, needle);

String _messageContent(ChatState state, String? messageId) {
  if (messageId == null) return '';
  for (final m in state.messages) {
    if (m.messageId == messageId) {
      return m.content ?? '';
    }
  }
  return '';
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

ProviderContainer _buildContainer(
  FakeChatApi api,
  _FakeClock clock, {
  ChatWatchdogConfig watchdogConfig = const ChatWatchdogConfig(),
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.memory();
  final cache = _NoopCacheService(db);
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatClockProvider.overrideWithValue(clock.call),
      chatWatchdogConfigProvider.overrideWithValue(watchdogConfig),
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
