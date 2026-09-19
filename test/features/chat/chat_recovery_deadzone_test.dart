import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _FakeClock {
  DateTime now = DateTime(2026, 9, 19, 12, 0, 0);

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
    watchdogInterval: Duration(seconds: 1),
    deadZoneStallThreshold: Duration(seconds: 15),
    deadZoneCooldown: Duration(seconds: 30),
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

void _setLifecycle(ProviderContainer container, AppLifecycleState next) {
  container.read(appLifecycleStateProvider.notifier).setState(next);
}

void main() {
  group('TASK #142: 消灭「streaming 但 activeStreamId == null」恢复死区', () {
    test(
      'RED-1（死区触发）：phase == streaming + activeStreamId == null + _lastProgress 超阈值 + 非 pendingPrompt ⇒ watchdog 一跳后必须发生一次 syncMissingMessages',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller =
              container.read(chatControllerProvider('sess-1').notifier);
          async.flushMicrotasks();

          // 构造死区特征：
          // 1. phase == streaming
          // 2. activeStreamId == null
          // 3. _lastProgress 为 20s 前（已超 15s 阈值）
          // 4. hasPendingPrompt == false
          controller.setStateForTesting(
            controller.state.copyWith(
              phase: ChatPhase.streaming,
              stream: controller.state.stream.copyWith(clearActiveStreamId: true),
              pendingAction: const ChatPendingActionState(),
            ),
          );
          controller.setLastProgressForTesting(
            clock.now.subtract(const Duration(seconds: 20)),
          );

          final initialCalls = api.sessionCalls;

          // watchdog 走 1 跳（1s）
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();

          expect(
            api.sessionCalls,
            equals(initialCalls + 1),
            reason: '死区状态下 watchdog 走 1 跳必须触发 syncMissingMessages',
          );
        });
      },
    );

    test('RED-2（有流不抢）：activeStreamId != null 时不触发（交给 transport 链）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();

        controller.setStateForTesting(
          controller.state.copyWith(
            phase: ChatPhase.streaming,
            stream: controller.state.stream.copyWith(
              activeStreamId: 'stream-123',
            ),
            pendingAction: const ChatPendingActionState(),
          ),
        );
        controller.setLastProgressForTesting(
          clock.now.subtract(const Duration(seconds: 20)),
        );
        // 上下文窗口轮询基准设为当前时刻，防 context poll 抢跑
        controller.setLastContextPollTimeForTesting(clock.now);

        final initialCalls = api.sessionCalls;

        // watchdog 走 1 跳
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(
          controller.deadZoneCooldownUntilForTesting,
          isNull,
          reason: '有活跃流时不应激活死区冷却与死区恢复链',
        );
        expect(
          api.sessionCalls,
          equals(initialCalls),
          reason: '有活跃流时不应抢跑触发死区求证，应交给 transport 链处理',
        );
      });
    });

    test('RED-3（等作答不催）：hasPendingPrompt == true 时不触发', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();

        controller.setStateForTesting(
          controller.state.copyWith(
            phase: ChatPhase.streaming,
            stream: controller.state.stream.copyWith(clearActiveStreamId: true),
            pendingAction: const ChatPendingActionState(
              clarificationPrompt: {
                'clarify_id': 'c1',
                'question': 'question',
              },
            ),
          ),
        );
        controller.setLastProgressForTesting(
          clock.now.subtract(const Duration(seconds: 20)),
        );

        final initialCalls = api.sessionCalls;

        // watchdog 走 1 跳
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(
          api.sessionCalls,
          equals(initialCalls),
          reason: '等待主人作答时不应催促向服务端拉取',
        );
      });
    });

    test('RED-4（冷却生效）：连续多跳只触发一次', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();

        controller.setStateForTesting(
          controller.state.copyWith(
            phase: ChatPhase.streaming,
            stream: controller.state.stream.copyWith(clearActiveStreamId: true),
            pendingAction: const ChatPendingActionState(),
          ),
        );
        controller.setLastProgressForTesting(
          clock.now.subtract(const Duration(seconds: 20)),
        );

        final initialCalls = api.sessionCalls;

        // 连续推进 10 秒（10 跳，仍在 30s 冷却内）
        for (var i = 0; i < 10; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
        }

        expect(
          api.sessionCalls,
          equals(initialCalls + 1),
          reason: '30s 冷却期内连续多跳只触发一次求证',
        );
      });
    });

    test(
      'RED-5（resumed 立即对账）：activeStreamId == null + phase == streaming 时，lifecycle → resumed 应立即触发一次（不等阈值）',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller =
              container.read(chatControllerProvider('sess-1').notifier);
          async.flushMicrotasks();

          _setLifecycle(container, AppLifecycleState.paused);
          async.flushMicrotasks();

          controller.setStateForTesting(
            controller.state.copyWith(
              phase: ChatPhase.streaming,
              stream: controller.state.stream.copyWith(clearActiveStreamId: true),
              pendingAction: const ChatPendingActionState(),
            ),
          );
          // lastProgress 为刚刚，未达到 15s 阈值
          controller.setLastProgressForTesting(clock.now);

          final initialCalls = api.sessionCalls;

          // 回到前台 resumed，不等 15s 阈值立即触发一次
          _setLifecycle(container, AppLifecycleState.resumed);
          async.flushMicrotasks();

          expect(
            api.sessionCalls,
            equals(initialCalls + 1),
            reason: 'resumed 到达时若存在死区特征应立即触发一次求证，不等 watchdog 15s 阈值',
          );
        });
      },
    );

    test(
      'RED-6（预算无条件复位）：activeStreamId == null 且 _reconnectAttempts 已达上限时，lifecycle → resumed 后预算必须归零',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller =
              container.read(chatControllerProvider('sess-1').notifier);
          async.flushMicrotasks();

          _setLifecycle(container, AppLifecycleState.paused);
          async.flushMicrotasks();

          // activeStreamId == null，且重连预算已耗尽（6 次）
          controller.setStateForTesting(
            controller.state.copyWith(
              stream: controller.state.stream.copyWith(clearActiveStreamId: true),
            ),
          );
          controller.reconnectAttemptsForTesting = 6;
          expect(controller.reconnectAttemptsForTesting, 6);

          // 回到前台 resumed
          _setLifecycle(container, AppLifecycleState.resumed);
          async.flushMicrotasks();

          expect(
            controller.reconnectAttemptsForTesting,
            0,
            reason: '无论 activeStreamId 是否为空，resumed 到达时恢复预算必须无条件清零',
          );
        });
      },
    );

    test(
      'RED-7（早退不再吞掉恢复）：_appPaused 与传入状态相同的 resumed 事件到达时，仍执行轻量对账',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller =
              container.read(chatControllerProvider('sess-1').notifier);
          async.flushMicrotasks();

          // 先进入 paused 状态
          _setLifecycle(container, AppLifecycleState.paused);
          async.flushMicrotasks();

          // 模拟 out-of-sync：_appPaused 与传入的 resumed 状态一致（即 _appPaused == false），
          // 但真实重连预算已被耗尽至 6
          controller.setAppPausedForTesting(false);
          controller.reconnectAttemptsForTesting = 6;
          expect(controller.reconnectAttemptsForTesting, 6);

          // 传入 resumed 事件（此时 nowPaused == _appPaused == false，走早退分支）
          _setLifecycle(container, AppLifecycleState.resumed);
          async.flushMicrotasks();

          expect(
            controller.reconnectAttemptsForTesting,
            0,
            reason: 'believed 状态未变但收到 resumed 时仍应执行轻量对账复位资源',
          );
        });
      },
    );
  });
}
