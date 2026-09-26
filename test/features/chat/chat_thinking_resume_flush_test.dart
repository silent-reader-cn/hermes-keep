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
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 后台切回前台：思考子卡的 flush 对称性守卫。
///
/// 缺陷现象（主人真机报告）：正在生成的会话切后台、再切回，**后台期间新增的
/// tools 折叠卡内的思考子卡整段消失**，在界面上待一会儿才统一出现。
///
/// 根因（三层，本文件钉住第三层的修复）：
/// ① 后台冻结只冻结消费不冻结记账 —— `_scheduleMerge` 被 `_appPaused` 挡下，
///    reasoning 只进 `pendingReasoningChunks`，`liveReasoningText` 原地停滞；
///    而时间线断点游标 `_currentReasoningContent()` 取「已 flush + 待 flush」
///    全量，断点因此跑到数据前面；
/// ② 切片器只读 `liveReasoningText`（不含 pending），越界段被 clamp 成空串，
///    「空思考段…渲染端不产生子行」→ 静默丢行、不报错；
/// ③ resumed 路径原先只补正文（`_flushPendingRevealToFullText`），
///    `pendingReasoningChunks` 没有对应补 flush → 切回前台**不自愈**，
///    要等下一个 SSE 事件触发 merge tick 才一次性补回（「待一会儿又统一出现」）。
///
/// RED 校验：注释掉 `_handleAppLifecycleChange` resumed 分支里的
/// `_flushReasoningChunks();` → 用例 1 / 3 精确变红，用例 2 仍绿（无幽灵行
/// 与本次修复无关，属回归保护）。
class _FakeClock {
  DateTime now = DateTime(2026, 9, 1, 12, 0, 0);

  DateTime call() => now;
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

void _setLifecycle(ProviderContainer container, AppLifecycleState next) {
  container.read(appLifecycleStateProvider.notifier).setState(next);
}

/// live 时间线里所有思考子卡的文本（顺序 = 卡内行序）。
List<String> _thinkingTexts(ProviderContainer container, String sid) {
  final entries =
      container.read(liveTimelineProvider(sid)) ?? const <LiveTimelineEntry>[];
  final out = <String>[];
  for (final entry in entries) {
    final group = entry.toolGroup;
    if (group == null) continue;
    for (final call in group.toolCalls) {
      if (call.name == 'thinking') out.add(call.thinking ?? '<null>');
    }
  }
  return out;
}

String _streamingContent(ProviderContainer container, String sid) {
  final st = container.read(chatControllerProvider(sid));
  final id = st.stream.streamingAssistantMessageId;
  for (final m in st.messages) {
    if (m.messageId == id) return m.content ?? '';
  }
  return '';
}

const _sid = '';

/// 起流 + 发事件 + 时钟推进的薄封装。
class _Harness {
  _Harness(this.container, this.api);

  final ProviderContainer container;
  final FakeChatApi api;

  void start(FakeAsync async) {
    final controller = container.read(chatControllerProvider(_sid).notifier);
    unawaited(controller.send('hi'));
    async.flushMicrotasks();
  }

  void reasoning(FakeAsync async, String text) {
    api.emit(ReasoningSseEvent(text));
    async.flushMicrotasks();
  }

  void token(FakeAsync async, String text) {
    api.emit(TokenSseEvent(text));
    async.flushMicrotasks();
  }

  void tool(FakeAsync async, String name, String stableId) {
    api.emit(
      ToolStartedSseEvent(
        ToolStreamEvent(
          eventType: 'tool_start',
          name: name,
          stableId: stableId,
        ),
      ),
    );
    async.flushMicrotasks();
  }

  void background(FakeAsync async) {
    _setLifecycle(container, AppLifecycleState.hidden);
    async.flushMicrotasks();
  }

  void foreground(FakeAsync async) {
    _setLifecycle(container, AppLifecycleState.resumed);
    async.flushMicrotasks();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('后台切回前台：思考子卡 flush 对称性守卫', () {
    test('用例 1：resumed 当帧即补齐后台累积的思考子卡（不再等下一个 SSE 事件）', () {
      fakeAsync((async) {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final container = _buildContainer(api, _FakeClock());
        final h = _Harness(container, api);

        h.start(async);
        // 前台：思考 → 工具
        h.reasoning(async, '前台思考');
        async.elapse(const Duration(milliseconds: 40));
        h.tool(async, 'grep', 't1');
        async.elapse(const Duration(milliseconds: 40));
        expect(_thinkingTexts(container, _sid), ['前台思考']);

        // 切后台，后台期间：思考 → 工具 → 思考（全程无正文）
        h.background(async);
        h.reasoning(async, '后台思考甲');
        h.tool(async, 'read', 't2');
        h.reasoning(async, '后台思考乙');
        async.elapse(const Duration(milliseconds: 300));

        // 缺陷态：断点已推进，但 liveReasoningText 停滞 → 后台两条被静默丢弃
        expect(
          _thinkingTexts(container, _sid),
          ['前台思考'],
          reason: '后台期间 liveReasoningText 停摆，越界段 clamp 成空串（现象固化）',
        );

        // 切回前台：不推进时钟，只走 resumed 路径（模拟「切回瞬间」）
        h.foreground(async);

        expect(
          _thinkingTexts(container, _sid),
          ['前台思考', '后台思考甲', '后台思考乙'],
          reason: 'resumed 应像铺正文那样把 reasoning 一并落账，思考子卡立即完整',
        );
      });
    });

    test('用例 2：后台无新思考时，resumed 不产生幽灵思考行', () {
      fakeAsync((async) {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final container = _buildContainer(api, _FakeClock());
        final h = _Harness(container, api);

        h.start(async);
        h.reasoning(async, '前台思考');
        async.elapse(const Duration(milliseconds: 40));
        h.tool(async, 'grep', 't1');
        async.elapse(const Duration(milliseconds: 40));

        h.background(async);
        // 后台期间只有工具，没有任何 reasoning
        h.tool(async, 'read', 't2');
        async.elapse(const Duration(milliseconds: 300));

        h.foreground(async);
        async.elapse(const Duration(milliseconds: 40));

        expect(
          _thinkingTexts(container, _sid),
          ['前台思考'],
          reason: 'pending 为空时 flush 是 no-op，不应凭空多出思考行',
        );
      });
    });

    test('用例 3：正文与思考两侧对称 —— 后台正文已铺的同时，思考也已补齐', () {
      fakeAsync((async) {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final container = _buildContainer(api, _FakeClock());
        final h = _Harness(container, api);

        h.start(async);
        h.reasoning(async, '前台思考');
        async.elapse(const Duration(milliseconds: 40));
        h.tool(async, 'grep', 't1');
        async.elapse(const Duration(milliseconds: 40));

        h.background(async);
        h.reasoning(async, '后台思考甲');
        h.token(async, '后台正文');
        h.reasoning(async, '后台思考乙');
        h.tool(async, 'read', 't2');
        async.elapse(const Duration(milliseconds: 300));

        h.foreground(async);

        expect(
          _streamingContent(container, _sid),
          contains('后台正文'),
          reason: '正文两侧对称：resumed 铺全文（原有行为，回归保护）',
        );
        expect(
          _thinkingTexts(container, _sid),
          ['前台思考', '后台思考甲', '后台思考乙'],
          reason: '思考与正文同口径落账，不应一边补上一边缺席',
        );
      });
    });
  });
}
