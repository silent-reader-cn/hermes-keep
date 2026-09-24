import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// #156 压缩上下文：异步 start + status 轮询。
///
/// 主人诉求：① 关掉弹窗后仍能看到「是否还在压缩」→ 压缩状态必须挂在会话状态
/// （ChatState）而非弹窗局部；② 压缩期间不允许发消息 → send 守卫。
///
/// 本文件覆盖状态机与守卫；UI 侧（指示器 loading / 发送按钮禁用）见
/// `context_window_indicator_compress_test.dart` 与 `chat_input_bar_compress_test.dart`。
void main() {
  group('#156 压缩上下文（异步 start + status 轮询）', () {
    test('RED-156-1 启动走异步接口且立刻返回：进入压缩态，轮询按官方退避取状态', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        // 服务端持续 running（否则第一拍轮询即收敛，测不到退避节奏）。
        api.compressStatusResponse = const SessionCompressStatusResponse(
          ok: true,
          status: 'running',
          sessionId: 'sess-1',
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        bool? started;
        unawaited(
          controller.startCompression().then((value) => started = value),
        );
        async.flushMicrotasks();

        // 关键：必须走 /compress/start，绝不再用会超时的同步 /compress。
        expect(api.compressStartCalls, 1);
        expect(api.compressCalls, 0);
        expect(started, isTrue);
        expect(controller.state.isCompressingContext, isTrue);

        // 官方退避首拍 700ms：600ms 时尚未轮询。
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();
        expect(api.compressStatusCalls, 0);

        // 越过 700ms → 第 1 次轮询。
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(api.compressStatusCalls, 1);

        // 第 2 拍 = 700 + 300 = 1000ms。
        async.elapse(const Duration(milliseconds: 1000));
        async.flushMicrotasks();
        expect(api.compressStatusCalls, 2);

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-2 轮询到 done：复位压缩态 + 刷新 transcript + 轻提示', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.compressStatusBuilder = (call) {
          if (call < 3) {
            return const SessionCompressStatusResponse(
              ok: true,
              status: 'running',
              sessionId: 'sess-1',
            );
          }
          return const SessionCompressStatusResponse(
            ok: true,
            status: 'done',
            sessionId: 'sess-1',
            result: SessionCompressResponse(ok: true),
          );
        };
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();
        api.sessionCalls = 0;

        unawaited(controller.startCompression());
        async.flushMicrotasks();
        expect(controller.state.isCompressingContext, isTrue);

        // 跑到 done（第 3 次轮询）。
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        expect(
          controller.state.isCompressingContext,
          isFalse,
          reason: '完成后必须复位',
        );
        expect(controller.state.noticeMessage, '会话已压缩');
        expect(api.sessionCalls, greaterThan(0), reason: '完成后应刷新 transcript');

        // 收尾后不再继续轮询（避免空转请求）。
        final callsAfterDone = api.compressStatusCalls;
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(api.compressStatusCalls, callsAfterDone);

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-3 status=idle（job 过期/服务重启）→ 本地收敛，不永久转圈', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.compressStatusResponse = const SessionCompressStatusResponse(
          ok: true,
          status: 'idle',
          sessionId: 'sess-1',
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.startCompression());
        async.flushMicrotasks();
        expect(controller.state.isCompressingContext, isTrue);

        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(controller.state.isCompressingContext, isFalse);
        // 收敛后停止轮询。
        final calls = api.compressStatusCalls;
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(api.compressStatusCalls, calls);

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-4 status=error → 复位并显式报错', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.compressStatusResponse = const SessionCompressStatusResponse(
          ok: false,
          status: 'error',
          sessionId: 'sess-1',
          error: '压缩失败：上下文过大',
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.startCompression());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(controller.state.isCompressingContext, isFalse);
        expect(controller.state.sendErrorMessage, '压缩失败：上下文过大');

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-5 压缩期间 send 被拒（不发新回合）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.startCompression());
        async.flushMicrotasks();
        expect(controller.state.isCompressingContext, isTrue);
        api.startChatCalls = 0;

        bool? sent;
        unawaited(controller.send('接下来做什么？').then((v) => sent = v));
        async.flushMicrotasks();

        expect(sent, isFalse, reason: '压缩期间发送必须被拒');
        expect(api.startChatCalls, 0, reason: '不得真的发出新回合');
        expect(controller.state.sendErrorMessage, isNotNull);

        // 对照：压缩结束后可以正常发送。
        api.compressStatusResponse = const SessionCompressStatusResponse(
          ok: true,
          status: 'idle',
          sessionId: 'sess-1',
        );
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(controller.state.isCompressingContext, isFalse);

        unawaited(controller.send('现在可以发了'));
        async.flushMicrotasks();
        expect(api.startChatCalls, 1);

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-6 恢复探测：服务端仍在压缩 → 接管并点亮状态（App 重启场景）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.compressStatusResponse = const SessionCompressStatusResponse(
          ok: true,
          status: 'running',
          sessionId: 'sess-1',
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();
        api.compressStatusCalls = 0;

        unawaited(controller.resumeCompressionIfRunning());
        async.flushMicrotasks();

        expect(api.compressStatusCalls, 1);
        expect(controller.state.isCompressingContext, isTrue);

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-7 恢复探测有节流：本地已在跟踪时不重复探测', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.startCompression());
        async.flushMicrotasks();
        api.compressStatusCalls = 0;

        unawaited(controller.resumeCompressionIfRunning());
        async.flushMicrotasks();
        expect(api.compressStatusCalls, 0, reason: '已在压缩中不应重复探测');

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-8 start 被拒（如 agent runtime 过期）→ 不进压缩态且报错', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.compressStartResponse = const SessionCompressStatusResponse(
          ok: false,
          status: 'error',
          sessionId: 'sess-1',
          error: 'Agent runtime 已过期，请重试',
          errorStatus: 409,
          retryable: true,
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        bool? started;
        unawaited(
          controller.startCompression().then((value) => started = value),
        );
        async.flushMicrotasks();

        expect(started, isFalse);
        expect(controller.state.isCompressingContext, isFalse);
        expect(controller.state.sendErrorMessage, 'Agent runtime 已过期，请重试');

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-9 轮询连续失败达上限 → 收敛并报错（绝不静默挂死）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.compressStatusError = HttpException(500, null, message: '网络不可达');
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.startCompression());
        async.flushMicrotasks();
        expect(controller.state.isCompressingContext, isTrue);

        async.elapse(const Duration(minutes: 3));
        async.flushMicrotasks();

        expect(controller.state.isCompressingContext, isFalse);
        expect(controller.state.sendErrorMessage, isNotNull);

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('RED-156-10 回合进行中不允许压缩（服务端同样 409）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hello'));
        async.flushMicrotasks();
        expect(controller.state.phase, ChatPhase.streaming);
        api.compressStartCalls = 0;

        bool? started;
        unawaited(
          controller.startCompression().then((value) => started = value),
        );
        async.flushMicrotasks();

        expect(started, isFalse);
        expect(api.compressStartCalls, 0, reason: '流式中不应发起压缩请求');

        container.dispose();
        async.flushMicrotasks();
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 测试辅助（照 test/features/chat/chat_context_window_poll_test.dart 范式）
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
