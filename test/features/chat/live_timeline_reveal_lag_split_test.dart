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
import 'package:hermes_ui/features/chat/chat_models.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// #147：live 工具的切卡判据必须与 reveal（打字机）进度**解耦**。
///
/// 铁律：**「正文是唯一分隔符」按「事件到达真相」判定，不按「已 reveal 的可见正文」**。
/// 断点游标记在「已到达」空间（`_currentStreamingContent()` = content + 待合并 + 待揭示），
/// 而旧渲染链把 flush 与「已 reveal 切片非空」绑在一起 —— 只要 reveal 落后于事件到达
/// （后台冻结 / 回前台重放补课 / 打字机滞后），内容性正文就被 clamp 成空段，渲染端据此
/// 拒绝切卡 ⇒ 本该分开的工具全并进一张卡（主人现象：切回前台攒出「工具特别多」的大卡，
/// 把工具分开的正文随后才一段段吐出来）。
///
/// 修复落点（两层）：
/// 1. `chat_controller.dart` `_appendAssistantToken` / 重放补点：**纯空白 token 不建 text 断点**
///    ⇒ 保住 #62 语义（空白不是分隔符）且让「存在 text 断点 ⇔ 到达过内容性正文」成为不变量；
/// 2. `chat_models.dart` `buildLiveTimelineEntries`：text 断点**无条件 flush**
///    （仅「是否渲染该 text 条目」仍看已 reveal 文本，文字随后填进槽位）。
///
/// #162 补充（时机层，不推翻上面两条）：「无条件 flush」保住了**边界真相**，但卡会
/// 抢跑占位 —— 正文还在打字时后续工具卡已就位，未揭示的正文随后补进卡与卡之间的
/// 缝隙（凭空插入 + 向下推挤，主人现象）。故新增**正文前沿闸门**：某段正文未吐完
/// 时，其后的工具/思考条目只挂起**展示**，卡片数量与分组一律不变。
/// 于是本文件的期望分两层：
///   · 打字机未追上（冻结中 / 刚到达）→ 未揭示正文之后的卡**尚未**上屏；
///   · 打字机追上后 → 边界与 #147 完全一致（仍是各自成卡，绝不并成一张大卡）。
///
/// 上面第 3 条防回归用例（纯空白 token 不切卡）不受闸门影响：它已先 elapse 到追平。
void main() {
  group('#147 live 切卡判据与 reveal 解耦', () {
    test('后台冻结：正文/工具交替到达 → 冻结中全挂起，回前台铺全文后三张卡齐现且边界不变', () {
      fakeAsync((async) {
        final session = _LiveSession.start(async);

        // 切后台：SSE 仍到达，但正文消费（merge/reveal）被冻结。
        _setLifecycle(session.container, AppLifecycleState.paused);
        _emitAlternatingTextTool(session.api);
        async.elapse(const Duration(seconds: 2));

        final state = session.state;
        expect(
          state.pendingAssistantTokenChunks.length,
          3,
          reason: '冻结期正文应只入 pending（未 reveal）',
        );
        expect(state.liveToolCalls.length, 3);
        // 冻结中屏幕不可见；闸门挂起正文之后的卡，但边界真相（三张、不并卡）
        // 会在回前台铺全文后兑现 —— 见下面两步断言。
        expect(
          _shape(session.entries),
          '',
          reason: '冻结中正文一个字都没吐 ⇒ 前沿闸门挂起其后所有工具卡',
        );

        // 回前台：积压一次性铺全文 → 三个正文段填进各自的槽位，卡片边界不变。
        _setLifecycle(session.container, AppLifecycleState.resumed);
        expect(
          _shape(session.entries),
          'X4 | T1@2 | X4 | T1@4 | X4 | T1@6',
          reason: '恢复瞬间正文补齐，卡片边界与冻结期一致',
        );

        async.elapse(const Duration(seconds: 5));
        expect(
          _shape(session.entries),
          'X4 | T1@2 | X4 | T1@4 | X4 | T1@6',
          reason: '打字机追平后边界仍不变（不出现「先并后拆」的抖动）',
        );
      });
    });

    test('前台 reveal 滞后：token 已全到但打字机未吐 → 全书挂起，追平后逐段放行', () {
      fakeAsync((async) {
        final session = _LiveSession.start(async);

        // 前台：与冻结期同一条事件序列，只是不暂停 —— 差别仅在于 reveal 追得上与否。
        _emitAlternatingTextTool(session.api);

        expect(
          _shape(session.entries),
          '',
          reason: 'token 已全到但打字机未吐 ⇒ 闸门挂起，不再抢跑占位',
        );

        // 16ms 合并窗关闭后：正文进了 reveal 队列但一个字都没落地，仍应挂起。
        async.elapse(const Duration(milliseconds: 20));
        expect(
          _shape(session.entries),
          '',
          reason: '已入队但未揭示 ⇒ 仍挂起（前沿未推进）',
        );

        async.elapse(const Duration(seconds: 5));
        expect(
          _shape(session.entries),
          'X4 | T1@2 | X4 | T1@4 | X4 | T1@6',
          reason: '打字机追平后补齐正文，边界不变',
        );
      });
    });

    test('防回归 #62：工具之间的纯空白 token 仍不切卡，且不建 text 断点', () {
      fakeAsync((async) {
        final session = _LiveSession.start(async);

        session.api
          ..emit(const TokenSseEvent('A'))
          ..emit(_tool('t1', 'cd'))
          ..emit(const TokenSseEvent('\n\n'))
          ..emit(_tool('t2', 'ls'))
          ..emit(const TokenSseEvent(' '))
          ..emit(_tool('t3', 'pwd'));
        async.elapse(const Duration(seconds: 2));

        expect(session.state.liveTimelinePoints.map((p) => p.kind).toList(), [
          LiveSegmentKind.text,
          LiveSegmentKind.tools,
        ], reason: '空白 token 不得留下隐形 text 断点（#62：空白不是分隔符）');
        expect(
          _shape(session.entries),
          'X4 | T3@2',
          reason: '三个工具仍并成一张卡；可见正文 A 独立成段（段内含到达的空白字符，不可见）',
        );
      });
    });

    test('防回归：可见正文仍照常切卡（穿插语义不误伤）', () {
      fakeAsync((async) {
        final session = _LiveSession.start(async);

        session.api
          ..emit(_tool('t1', 'cd'))
          ..emit(const TokenSseEvent('中间有正文'))
          ..emit(_tool('t2', 'ls'));

        expect(
          _shape(session.entries),
          'T1@1',
          reason: '第一张卡在未揭示正文之前 ⇒ 立即放行；第二张在正文之后 ⇒ 挂起待吐完',
        );

        async.elapse(const Duration(seconds: 5));
        expect(
          _shape(session.entries),
          'T1@1 | X5 | T1@3',
          reason: '正文填入后应夹在两张卡之间',
        );
      });
    });
  });
}

/// 形状描述：`T<n>@<断点序号>` = 工具卡（含 n 个工具调用）；`X<len>` = 正文段。
String _shape(List<LiveTimelineEntry>? entries) {
  if (entries == null) return 'null';
  return entries
      .map(
        (e) => e.kind == LiveSegmentKind.tools
            ? 'T${e.toolGroup?.toolCalls.length ?? 0}'
                  '@${e.renderKey.split(':').last}'
            : 'X${e.textSlice.length}',
      )
      .join(' | ');
}

/// 正文A → 工具1 → 正文B → 工具2 → 正文C → 工具3（三条工具分属不同正文区段）。
void _emitAlternatingTextTool(FakeChatApi api) {
  api
    ..emit(const TokenSseEvent('正文A '))
    ..emit(_tool('t1', 'cd'))
    ..emit(const TokenSseEvent('正文B '))
    ..emit(_tool('t2', 'ls'))
    ..emit(const TokenSseEvent('正文C '))
    ..emit(_tool('t3', 'pwd'));
}

ToolStartedSseEvent _tool(String id, String name) =>
    ToolStartedSseEvent(ToolStreamEvent(stableId: id, name: name));

/// live 会话台架：真 controller + FakeChatApi + 可控时钟。
class _LiveSession {
  _LiveSession(this.api, this.clock, this.container);

  final FakeChatApi api;
  final _FakeClock clock;
  final ProviderContainer container;

  static _LiveSession start(FakeAsync async) {
    final api = FakeChatApi();
    final clock = _FakeClock();
    final container = _buildContainer(api, clock);
    final controller = container.read(chatControllerProvider('').notifier);
    unawaited(controller.send('hi'));
    async.flushMicrotasks();
    return _LiveSession(api, clock, container);
  }

  ChatState get state => container.read(chatControllerProvider(''));

  List<LiveTimelineEntry>? get entries =>
      container.read(liveTimelineProvider(''));
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
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatClockProvider.overrideWithValue(clock.call),
      chatWatchdogConfigProvider.overrideWithValue(
        const ChatWatchdogConfig(
          reconnectJitterMax: Duration.zero,
          fullReconnectCooldown: Duration.zero,
        ),
      ),
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      appDatabaseProvider.overrideWithValue(db),
      cacheServiceProvider.overrideWithValue(_NoopCacheService(db)),
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

/// 驱动 App 生命周期（等价 `NotificationLifecycleObserver` 转发生产链路）。
void _setLifecycle(ProviderContainer container, AppLifecycleState state) {
  container.read(appLifecycleStateProvider.notifier).setState(state);
}
