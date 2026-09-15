import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// #120 回合实时活动 → 实况通知（灵动岛）上报链路的 controller 侧契约。
///
/// 断言口径（why）：
/// - 上岛不再依赖会话列表刷新，故每一处活动变化都必须**立刻**经
///   [chatLiveActivityCallbackProvider] 上报——这条回调是 LIVE 的唯一事实源；
/// - 退到后台（paused）时列表轮询与 SSE 已停，必须**强制**补报一次，
///   否则岛在后台不会出现（主人 2026-09-15 报的「等一会才显示」）；
/// - 高频 token 事件不得穿透（同活动连续到达只报一次），避免平台通道抖动。
void main() {
  group('#120 回合实时活动上报', () {
    test('token → output 上报（带会话 id）；同活动去重；退后台强制重报', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final reports = <(String, ChatLiveActivity, String)>[];
        final container = _buildContainer(api, reports);
        final controller = container.read(
          chatControllerProvider('').notifier,
        );

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 新会话首条消息：sessionId 未定（startChat 尚未回填），跳过上报
        // ——通知点击需要可跳转的会话。
        expect(reports, isEmpty);

        // 首段正文 token → 「输出中」。
        api.emit(const TokenSseEvent('文本 '));
        async.flushMicrotasks();
        expect(reports, hasLength(1));
        expect(reports.last.$1, 'sess-new');
        expect(reports.last.$2, ChatLiveActivity.output);

        // 去重：同活动连续 token 不再上报。
        final before = reports.length;
        api.emit(const TokenSseEvent('继续 '));
        async.flushMicrotasks();
        expect(reports, hasLength(before));

        // 退后台：强制补报一次（活动未变也要报）。
        _setLifecycle(container, AppLifecycleState.paused);
        async.flushMicrotasks();
        expect(reports, hasLength(before + 1));
        expect(reports.last.$2, ChatLiveActivity.output);
      });
    });

    test('reasoning → thinking；tool_started → tool 且带工具名', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final reports = <(String, ChatLiveActivity, String)>[];
        final container = _buildContainer(api, reports);
        final controller = container.read(
          chatControllerProvider('').notifier,
        );
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const ReasoningSseEvent('先看下目录'));
        async.flushMicrotasks();
        expect(reports.last.$2, ChatLiveActivity.thinking);
        expect(reports.last.$3, '');

        api.emit(
          const ToolStartedSseEvent(ToolStreamEvent(name: 'terminal')),
        );
        async.flushMicrotasks();
        expect(reports.last.$2, ChatLiveActivity.tool);
        expect(reports.last.$3, 'terminal');

        // 工具完成 → 回到推理。
        api.emit(
          const ToolCompletedSseEvent(ToolStreamEvent(name: 'terminal')),
        );
        async.flushMicrotasks();
        expect(reports.last.$2, ChatLiveActivity.thinking);
      });
    });

    test('clarify → waitingReply；approval → waitingApproval', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final reports = <(String, ChatLiveActivity, String)>[];
        final container = _buildContainer(api, reports);
        final controller = container.read(
          chatControllerProvider('').notifier,
        );
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ClarificationPendingSseEvent(<String, Object?>{}),
        );
        async.flushMicrotasks();
        expect(reports.last.$2, ChatLiveActivity.waitingReply);

        api.emit(const ApprovalPendingSseEvent(<String, Object?>{}));
        async.flushMicrotasks();
        expect(reports.last.$2, ChatLiveActivity.waitingApproval);
      });
    });

    test('回合收尾（stream_end）→ finished（撤销岛）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final reports = <(String, ChatLiveActivity, String)>[];
        final container = _buildContainer(api, reports);
        final controller = container.read(
          chatControllerProvider('').notifier,
        );
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('文本 '));
        async.flushMicrotasks();
        expect(reports.last.$2, ChatLiveActivity.output);

        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();
        expect(reports.last.$2, ChatLiveActivity.finished);
      });
    });

    test('回合未进行时退后台 → 不上报（不无中生有地点亮岛）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final reports = <(String, ChatLiveActivity, String)>[];
        final container = _buildContainer(api, reports);
        // 不发送任何消息：controller 处于 idle。
        container.read(chatControllerProvider(''));

        _setLifecycle(container, AppLifecycleState.paused);
        async.flushMicrotasks();

        expect(reports, isEmpty);
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 测试基础设施（对齐 test/features/chat/chat_lockscreen_reveal_test.dart）
// ---------------------------------------------------------------------------

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
  List<(String, ChatLiveActivity, String)> reports,
) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.memory();
  final cache = _NoopCacheService(db);
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      appDatabaseProvider.overrideWithValue(db),
      cacheServiceProvider.overrideWithValue(cache),
      // 捕获上报（生产由 main.dart 注入 chatLiveActivityHookProvider）。
      chatLiveActivityCallbackProvider.overrideWith(
        (ref) => (sessionId, title, activity, detail) {
          reports.add((sessionId, activity, detail));
        },
      ),
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

/// 驱动 App 生命周期（等价 handleAppLifecycleStateChanged 的生产链路）。
void _setLifecycle(ProviderContainer container, AppLifecycleState state) {
  container.read(appLifecycleStateProvider.notifier).setState(state);
}
