import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// #155 收尾帧（done）畸形 / 截断。
///
/// 现场：真实 done 帧内含全量 session（实测单帧 ~9.7 MB），手机经 frp 慢链路 +
/// 服务端 20s SSE 写超时 → 帧被截断。旧实现把它判成 transportError → 落进
/// 「重连 + journal 回放」链，而回放会把同一张巨帧原样重发（回合结束后
/// `replay_available` 仍为真）→ 既不收敛也不报错，界面永远停在「生成中」。
///
/// 新语义：**done 是终结帧，载荷没吃全 ≠ 回合没结束** → 一律按「收尾」处理：
/// 探活一次，服务端已结束就用 REST transcript 收尾，**绝不回放**。
void main() {
  group('收尾帧畸形 → 按回合收尾（#155）', () {
    test('服务端已结束 → REST transcript 收尾；不回放、不重连、不打扰主人', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        // 回放可用也**不许**走：回放会把 9.7 MB 巨帧原样重发。
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();
        api.sessionCalls = 0;
        api.statusCalls = 0;

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 服务端此刻已落库最终回复（模拟真实：done 帧坏了但回合已完成）
        api.sessionResponse = _session(
          messages: [_user('hi'), _assistant('最终回复', 'm-final')],
        );

        api.emit(const MalformedDoneSseEvent('收尾帧格式异常（done 载荷未吃全）'));
        async.flushMicrotasks();

        expect(api.statusCalls, 1, reason: '只探活一次');
        expect(api.sessionCalls, greaterThanOrEqualTo(1), reason: '走 REST 收尾');
        expect(controller.state.stream.hasCompletedResponse, isTrue);
        expect(controller.state.stream.activeStreamId, isNull);
        expect(controller.state.phase, ChatPhase.idle);
        expect(
          controller.state.sendErrorMessage,
          isNull,
          reason: 'transcript 已前进 = 正常收尾，不该报错',
        );
        expect(api.startStreamCalls, 1, reason: '绝不回放（无第二次流连接）');

        // 旧实现会在此反复重吃巨帧；新实现此后必须完全静止。
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);
        expect(api.statusCalls, 1);
        expect(controller.state.phase, ChatPhase.idle);
      });
    });

    test('transcript 未前进 → 仍收尾但显式告知（绝不静默丢尾）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: false);
        // 会话里已有一条旧回复，且不会再更新 → 判据「transcript 是否前进」为假
        api.sessionResponse = _session(
          messages: [_user('hi'), _assistant('旧回复', 'm-old')],
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const MalformedDoneSseEvent('收尾帧格式异常（done 载荷未吃全）'));
        async.flushMicrotasks();

        expect(controller.state.stream.hasCompletedResponse, isTrue);
        expect(controller.state.phase, ChatPhase.idle);
        expect(
          controller.state.sendErrorMessage,
          '收尾数据不完整，已按当前记录收尾。',
          reason: '有丢尾风险必须显式告知，而不是静默收尾',
        );
      });
    });

    test('服务端仍在写 → 正常 resume（不误收尾、不误判完成）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 断点已知（id 形如 <streamId>:<seq>）才允许 resume
        api.emitId('stream-1:50');
        api.emit(const MalformedDoneSseEvent('收尾帧格式异常（done 载荷未吃全）'));
        async.flushMicrotasks();

        expect(api.statusCalls, 1);
        expect(controller.state.stream.hasCompletedResponse, isFalse);
        expect(controller.state.phase, ChatPhase.streaming);
        expect(api.startStreamCalls, 2, reason: '续传（带断点）');
      });
    });

    test('探活本身失败（真·网络故障）→ 落回既有传输恢复链', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusError = NetworkException(NetworkExceptionKind.cannotConnect);
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const MalformedDoneSseEvent('收尾帧格式异常（done 载荷未吃全）'));
        async.flushMicrotasks();

        expect(api.statusCalls, 1);
        expect(controller.state.phase, ChatPhase.recovering);
        expect(controller.state.stream.hasCompletedResponse, isFalse);

        // 1s 退避后进入重连链（预算内的既有行为）
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, greaterThanOrEqualTo(2));
        expect(api.startStreamCalls, greaterThanOrEqualTo(2));
      });
    });

    test('连续畸形超阈值 → 熔断：收尾 + 显式报错 + 停止一切重试', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        api.sessionResponse = _session(
          messages: [_user('hi'), _assistant('最终回复', 'm-final')],
        );
        final clock = _FakeClock();
        final container = _buildContainer(
          api,
          clock,
          watchdogConfig: const ChatWatchdogConfig(
            fullReconnectCooldown: Duration.zero,
            reconnectJitterMax: Duration.zero,
            maxMalformedDoneSettleAttempts: 1,
          ),
        );
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emitId('stream-1:50');
        api.emit(const MalformedDoneSseEvent('第 1 次'));
        async.flushMicrotasks();
        expect(controller.state.stream.hasCompletedResponse, isFalse);

        api.emitId('stream-1:50');
        api.emit(const MalformedDoneSseEvent('第 2 次'));
        async.flushMicrotasks();

        expect(controller.state.stream.hasCompletedResponse, isTrue);
        expect(controller.state.phase, ChatPhase.idle);
        expect(
          controller.state.sendErrorMessage,
          '收尾数据不完整（已重试多次），已按服务器记录收尾。',
        );

        final streamsAtBreaker = api.startStreamCalls;
        final statusAtBreaker = api.statusCalls;
        async.elapse(const Duration(seconds: 120));
        async.flushMicrotasks();
        expect(api.startStreamCalls, streamsAtBreaker, reason: '熔断后不再重连');
        expect(api.statusCalls, statusAtBreaker, reason: '熔断后不再探活');
      });
    });

    test('回合收尾后计数归零：新回合第 1 次畸形不误触熔断', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: false);
        api.sessionResponse = _session(
          messages: [_user('hi'), _assistant('回复一', 'm-1')],
        );
        final clock = _FakeClock();
        final container = _buildContainer(
          api,
          clock,
          watchdogConfig: const ChatWatchdogConfig(
            fullReconnectCooldown: Duration.zero,
            reconnectJitterMax: Duration.zero,
            maxMalformedDoneSettleAttempts: 1,
          ),
        );
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        // 回合 1：1 次畸形 → 阈值 1，不触发熔断（熔断是「超过」），收尾并归零
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emit(const MalformedDoneSseEvent('第 1 次'));
        async.flushMicrotasks();
        expect(controller.state.stream.hasCompletedResponse, isTrue);
        expect(
          controller.state.sendErrorMessage,
          '收尾数据不完整，已按当前记录收尾。',
        );

        // 回合 2：再来 1 次畸形。若计数未归零 → 累计 2 > 1 → 会喷熔断文案
        unawaited(controller.send('再来'));
        async.flushMicrotasks();
        api.emit(const MalformedDoneSseEvent('回合 2 第 1 次'));
        async.flushMicrotasks();
        expect(controller.state.stream.hasCompletedResponse, isTrue);
        expect(
          controller.state.sendErrorMessage,
          isNot('收尾数据不完整（已重试多次），已按服务器记录收尾。'),
          reason: '计数必须随回合收尾归零，否则新回合会被误熔断',
        );
      });
    });

    test('已成功收尾（done 已到）后再收到畸形 done → 幂等清理，不误伤', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const DoneSseEvent(DoneStreamEvent(usage: {'input_tokens': 1})),
        );
        async.flushMicrotasks();
        expect(controller.state.stream.hasCompletedResponse, isTrue);
        final statusAfterDone = api.statusCalls;
        final streamsAfterDone = api.startStreamCalls;

        api.emit(const MalformedDoneSseEvent('收尾帧格式异常（done 载荷未吃全）'));
        async.flushMicrotasks();

        // 分派层的 _resetReconnectBackoff 可能已记一次事件，但不得因此进恢复链
        expect(api.startStreamCalls, streamsAfterDone);
        expect(api.statusCalls, statusAfterDone, reason: '已收尾 → 无需再探活');
        expect(controller.state.phase, ChatPhase.idle);
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 测试基建（与 chat_reconnect_backoff_test.dart 同款）
// ---------------------------------------------------------------------------

ChatMessage _user(String content) =>
    ChatMessage(role: 'user', content: content, timestamp: 1);

ChatMessage _assistant(String content, String id) => ChatMessage(
  role: 'assistant',
  content: content,
  timestamp: 2,
  messageId: id,
);

SessionResponse _session({required List<ChatMessage> messages}) =>
    SessionResponse(
      session: SessionDetail(sessionId: 'sess-1', messages: messages),
    );

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
  ChatWatchdogConfig watchdogConfig = const ChatWatchdogConfig(
    fullReconnectCooldown: Duration.zero,
    reconnectJitterMax: Duration.zero,
  ),
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