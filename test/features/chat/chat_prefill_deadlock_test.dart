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
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _FakeClock {
  DateTime now = DateTime(2026, 9, 14, 12, 0, 0);

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
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

void main() {
  group('TASK #109: prefillStatus 迟到帧死锁守卫与自愈测试', () {
    test(
      '1. idle 控制器（无 activeStreamId）喂 context_status: loading 帧 → prefillStatus 不被置位（A 守卫）',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller = container.read(
            chatControllerProvider('s1').notifier,
          );
          async.flushMicrotasks();

          final state = container.read(chatControllerProvider('s1'));
          expect(state.stream.activeStreamId, isNull);
          expect(state.prefillStatus, isNull);

          // 在 idle 态下喂入 context_status: loading
          controller.handleSseEventForTesting(
            const ContextStatusSseEvent(
              status: ContextPrefillStatus.loading,
              label: '正在准备上下文',
            ),
          );

          final afterEvent = container.read(chatControllerProvider('s1'));
          expect(afterEvent.prefillStatus, isNull);
          expect(afterEvent.prefillLabel, isNull);
        });
      },
    );

    test('2. 流式活动中喂同一帧 → 正常置位（回归保护，防 A 过度拦截）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );

        unawaited(controller.send('hello'));
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('s1'));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.activeStreamId, isNotNull);
        expect(state.stream.hasCompletedResponse, isFalse);

        // 活动回合内喂入 context_status: loading 帧
        api.emit(
          const ContextStatusSseEvent(
            status: ContextPrefillStatus.loading,
            label: '模型思考准备中',
          ),
        );

        final updated = container.read(chatControllerProvider('s1'));
        expect(updated.prefillStatus, ContextPrefillStatus.loading);
        expect(updated.prefillLabel, '模型思考准备中');
        expect(controller.prefillSinceForTesting, clock.now);
      });
    });

    test(
      '3. onClosed 在非完成态触发 → 假 api 的 chatStreamStatus 被调用；返回 {active:false, replay_available:false} 且 transcript 有 assistant → 落定为 idle、prefillStatus 为空（B）',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller = container.read(
            chatControllerProvider('s1').notifier,
          );

          unawaited(controller.send('hello'));
          async.flushMicrotasks();

          expect(
            container.read(chatControllerProvider('s1')).stream.activeStreamId,
            isNotNull,
          );

          // 置位 prefillStatus
          api.emit(
            const ContextStatusSseEvent(
              status: ContextPrefillStatus.loading,
              label: 'waiting',
            ),
          );
          expect(
            container.read(chatControllerProvider('s1')).prefillStatus,
            ContextPrefillStatus.loading,
          );

          // 配置探活返回：非活动且不可重放
          api.statusResponse = const ChatStreamStatusResponse(
            active: false,
            replayAvailable: false,
          );
          // transcript 有 assistant
          api.sessionResponse = const SessionResponse(
            session: SessionDetail(
              sessionId: 's1',
              messages: [
                ChatMessage(role: 'user', content: 'hello'),
                ChatMessage(role: 'assistant', content: 'answer from server'),
              ],
            ),
          );

          // onClosed 在非完成态触发
          api.closeStream();
          async.flushMicrotasks();

          // 假 api 的 chatStreamStatus 被调用
          expect(api.statusCalls, 1);

          // 落定为 idle、prefillStatus 为空
          final finalState = container.read(chatControllerProvider('s1'));
          expect(finalState.phase, ChatPhase.idle);
          expect(finalState.stream.activeStreamId, isNull);
          expect(finalState.prefillStatus, isNull);
          expect(finalState.prefillLabel, isNull);
        });
      },
    );

    test(
      '4. prefill loading 挂起超过阈值且无进展 → 自愈清除 prefillStatus（C；阈值用可测注入或测试内拨基线）',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller = container.read(
            chatControllerProvider('s1').notifier,
          );

          unawaited(controller.send('hello'));
          async.flushMicrotasks();

          api.emit(
            const ContextStatusSseEvent(
              status: ContextPrefillStatus.loading,
              label: 'waiting model',
            ),
          );
          expect(
            container.read(chatControllerProvider('s1')).prefillStatus,
            ContextPrefillStatus.loading,
          );
          expect(controller.prefillSinceForTesting, isNotNull);

          api.statusResponse = const ChatStreamStatusResponse(active: true);

          // 拨基线：将 _prefillSince 往前拨 90s（符合规格第 3.C 条），看门狗 1s 周期内精准触发自愈
          controller.prefillSinceForTesting = clock.now.subtract(
            const Duration(seconds: 90),
          );
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));

          // 验证：清除 prefillStatus 并顺带触发 _checkStatusAndReconnect
          final state = container.read(chatControllerProvider('s1'));
          expect(state.prefillStatus, isNull);
          expect(state.prefillLabel, isNull);
          expect(api.statusCalls, 1);
        });
      },
    );

    test('4b. 进展事件（Token）到达时刷新清除 _prefillSince', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );

        unawaited(controller.send('hello'));
        async.flushMicrotasks();

        api.emit(
          const ContextStatusSseEvent(
            status: ContextPrefillStatus.loading,
            label: 'waiting',
          ),
        );
        expect(controller.prefillSinceForTesting, isNotNull);

        // Token 进展到达
        api.emit(const TokenSseEvent('A'));
        expect(controller.prefillSinceForTesting, isNull);
      });
    });

    test('5. _recoverExistingStream 接管后 turnStartedMillis 非空（D）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );

        api.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 's1',
            messages: [
              ChatMessage(role: 'user', content: 'historical message'),
            ],
          ),
        );

        expect(
          container.read(chatControllerProvider('s1')).turnStartedMillis,
          isNull,
        );

        unawaited(controller.recoverExistingStreamForTesting('existing-stream-99'));
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('s1'));
        expect(state.stream.activeStreamId, 'existing-stream-99');
        expect(state.turnStartedMillis, isNotNull);
        expect(state.turnStartedMillis, clock.now.millisecondsSinceEpoch);
      });
    });

    test('5b. _applySessionDetail 活动流接管后 turnStartedMillis 非空（D）', () {
      fakeAsync((async) {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        api.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 's1',
            activeStreamId: 'stream-detail-123',
            messages: [
              ChatMessage(role: 'user', content: 'remote turn'),
            ],
          ),
        );
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );

        unawaited(controller.loadMessages());
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('s1'));
        expect(state.stream.activeStreamId, 'stream-detail-123');
        expect(state.turnStartedMillis, isNotNull);
        expect(state.turnStartedMillis, clock.now.millisecondsSinceEpoch);
      });
    });
  });
}
