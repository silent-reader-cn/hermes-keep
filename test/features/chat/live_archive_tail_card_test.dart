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
import 'package:hermes_ui/features/settings/tool_group_settings.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 后台久挂 → 回前台补拉 transcript 后，归档工具卡**不得**：
/// 1. 残留客户端 `stream-` 幽灵行（整轮正文重复一份，且把工具锚点拖进临时锚空间）；
/// 2. 把整轮工具堆成一个 `live-tools-*` 组挂在临时锚 / 末条 assistant 上
///    （主人报的「回合末尾攒一张 tools 超多、位置错误的聚合卡」）；
/// 3. 跨卡重复搬运同一工具；
/// 4. 卡位从「回合首条正文之上」被降级到正文之下。
///
/// 场景形状取自真机会话（`webui_30002/sessions/*.json`）：一个回合内**分轮**产出
/// 「短说明 + 工具」，最后一条才是长报告；每轮正文与工具各自挂在自己的 assistant 行。
/// 工具聚合开关**两种模式都测**（真机默认 false，主人截图那张 17 行大卡在关闭态
/// 更不可能属于任何「服务端分段」—— 它就是 live 堆）。
void main() {
  for (final coalesceTools in [false, true]) {
    final mode = coalesceTools ? '聚合开启' : '聚合关闭';
    group('后台恢复补拉（$mode）：归档工具卡的锚点、位置与去重', () {
      test('服务端已完结 → 恢复补拉：无幽灵行、锚为权威行、不跨卡重复、工具不跨段搬运', () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          unawaited(
            container
                .read(toolGroupCoalesceProvider.notifier)
                .setCoalesce(coalesceTools),
          );
          final controller = container.read(
            chatControllerProvider('').notifier,
          );
          unawaited(controller.send('hi'));
          async.flushMicrotasks();

          // 切后台：SSE 照到，但正文消费被 _appPaused 冻结（工具写入无门控）。
          _setLifecycle(container, AppLifecycleState.paused);
          api
            ..emit(const TokenSseEvent('轮一 '))
            ..emit(_tool('t1', 'terminal'))
            ..emit(const TokenSseEvent('轮二 '))
            ..emit(_tool('t2', 'read_file'))
            ..emit(const TokenSseEvent('轮三 '))
            ..emit(_tool('t3', 'terminal'));
          clock.advance(const Duration(seconds: 2));
          async.elapse(const Duration(seconds: 2));

          // 服务端真身（后台期间该回合已跑完并落库）。
          api.sessionResult = _serverSession();
          // 回前台：状态探测 → 服务端已完结（active=false / 无 replay）→ 补拉。
          _setLifecycle(container, AppLifecycleState.resumed);
          clock.advance(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          clock.advance(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();

          final state = container.read(chatControllerProvider(''));
          final authoritative = <String>{
            for (final m in state.messages)
              if (m.messageId != null && m.messageId!.isNotEmpty) m.messageId!,
          };

          // 1) 幽灵行退役 + 正文不丢
          final ghosts = [
            for (final m in state.messages)
              if ((m.messageId ?? '').startsWith('stream-')) m.messageId,
          ];
          expect(ghosts, isEmpty, reason: '补拉后不得残留客户端 stream- 幽灵行：$ghosts');
          final allText = state.messages
              .where((m) => m.role == 'assistant')
              .map((m) => m.content ?? '')
              .join('|');
          for (final segment in ['轮一', '轮二', '轮三']) {
            expect(
              allText.contains(segment),
              isTrue,
              reason: '正文 $segment 不得丢失',
            );
          }

          final toolGroups = container
              .read(toolGroupsProvider(''))
              .where((g) => g.toolCalls.any((c) => !c.isThinking))
              .toList();

          // 2) 锚点必须是服务端权威行（不得是 raw:/stream-/local- 或悬空）
          for (final g in toolGroups) {
            expect(
              authoritative.contains(g.anchorMessageID),
              isTrue,
              reason:
                  '工具卡锚点 ${g.anchorMessageID} 必须是服务端权威行'
                  '（漂到临时锚/末条锚 = 主人看到的位置错误）',
            );
          }

          // 3) 同一工具（stable id）只能出现在一张卡里，且三条各一次
          final seen = <String, String>{};
          for (final g in toolGroups) {
            for (final call in g.toolCalls) {
              if (call.isThinking) continue;
              final previous = seen[call.id];
              expect(
                previous == null || previous == g.id,
                isTrue,
                reason: '工具 ${call.id} 被跨卡重复搬运（$previous + ${g.id}）',
              );
              seen[call.id] = g.id;
            }
          }
          expect(seen.keys.toSet(), {
            't1',
            't2',
            't3',
          }, reason: '三条工具应各出现一次（实得：${seen.keys.toList()}）');

          // 4) 卡位与卡内成分
          if (coalesceTools) {
            // 聚合开启 = 整回合一张卡，钉在回合**首条正文之上**。
            expect(toolGroups.length, 1, reason: '聚合开启 = 整回合一张卡');
            expect(
              toolGroups.first.anchorMessageID,
              'a1',
              reason: '整回合大卡应钉在「组内首个事件所在行」= a1（而非末条行 a3）',
            );
            expect(
              [
                for (final c in toolGroups.first.toolCalls)
                  if (!c.isThinking) c.id,
              ],
              ['t1', 't2', 't3'],
              reason: '卡内工具必须保持事件顺序：整堆搬运会把别段工具挤进来/换位',
            );
          } else {
            // 聚合关闭 = 按段分卡：每张卡只含它那一段的工具，不得出现 17 行巨卡。
            expect(toolGroups.length, 3, reason: '三段正文 = 三张卡（相邻无正文才合并）');
            for (final g in toolGroups) {
              expect(
                g.toolCalls.where((c) => !c.isThinking).length,
                1,
                reason: '「$mode」下每卡只应含本段那一个工具行（整堆搬运即 tools 超多）',
              );
            }
          }
        });
      });
    });
  }
}

/// 服务端 transcript：一个用户回合，三轮「短说明 + 工具」，工具归各自那一行。
Map<String, Object?> _serverSession() => {
  'session': {
    'session_id': '',
    'messages': [
      {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
      {'role': 'assistant', 'content': '轮一 ', 'message_id': 'a1'},
      {'role': 'assistant', 'content': '轮二 ', 'message_id': 'a2'},
      {'role': 'assistant', 'content': '轮三 ', 'message_id': 'a3'},
    ],
    'tool_calls': [
      {
        'name': 'terminal',
        'snippet': 'out-1',
        'tid': 't1',
        'assistant_msg_idx': 1,
      },
      {
        'name': 'read_file',
        'snippet': 'out-2',
        'tid': 't2',
        'assistant_msg_idx': 2,
      },
      {
        'name': 'terminal',
        'snippet': 'out-3',
        'tid': 't3',
        'assistant_msg_idx': 3,
      },
    ],
  },
};

ToolStartedSseEvent _tool(String id, String name) =>
    ToolStartedSseEvent(ToolStreamEvent(stableId: id, name: name));

class _FakeClock {
  DateTime now = DateTime(2026, 1, 1);
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

void _setLifecycle(ProviderContainer container, AppLifecycleState state) {
  container.read(appLifecycleStateProvider.notifier).setState(state);
}
