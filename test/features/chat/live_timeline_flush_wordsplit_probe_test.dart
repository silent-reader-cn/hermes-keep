import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 回归：文本 token 全部到达 + reveal 未完成时工具事件到达 → 不劈同一句。
///
/// 数据真相（2026-09-03 会话 7ea92838441b 消息 #160298 实证）：
/// Hermes 后端 SSE 顺序 = 完整文本 token → 工具事件（工具执行时才触发
/// tool_start_callback，见 hermes-agent conversation_loop.py:7445-7475）。
/// 但客户端 reveal 逐词消费：工具事件到达时 content 只 flush 到句子中间，
/// 若 flush 路径按「已 flush 长度」建兜底 text 断点，会把完整一句话在
/// 工具断点之后劈开（「一致性问题」的「一」「致」之间插工具卡）。
///
/// 修复（chat_controller.dart `_appendToStreamingMessage`）：flush/reveal
/// 路径不再建 text 断点（text 段在 token 事件到达时已定义）；仅
/// interim_assistant 新段落路径（establishPoint: true）建点。
void main() {
  Future<FakeChatApi> pumpStreamingSession(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      kToolGroupCoalesceKey: true,
      kThinkGroupCoalesceKey: true,
      kHideReasoningKey: false,
    });
    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    api.sessionResult = {
      'session': {
        'session_id': 's-live',
        'title': 'live',
        'active_stream_id': 'stream-live',
        'messages': [
          {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
        ],
        'message_count': 1,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-live')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(api.startStreamCalls, 1);
    return api;
  }

  testWidgets('文本全到达但未 reveal 完时工具事件到达 → 整句完整、工具卡在后', (tester) async {
    final api = await pumpStreamingSession(tester);

    // 1) 文本 token 全部到达（模拟 SSE 文本流完整先到）
    api.emit(const TokenSseEvent('好喵，这是个新的方向/一致性问题。柚子先明确：先摸清侧栏工具栏和窄屏导航的实现。'));
    await tester.pump();

    // 2) reveal 进行中（消费部分文本，让 content 只 flush 到中间——模拟慢速档真实时序）
    await tester.pump(const Duration(milliseconds: 16)); // merge
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 48));
    }

    // 3) 工具事件在文本 reveal 中途到达（后端顺序：文本完整先到，工具执行时才发事件）
    api.emit(
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'read_file', args: {'path': 'x'}),
      ),
    );
    await tester.pump();
    api.emit(
      const ToolCompletedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'read_file'),
      ),
    );
    await tester.pump();

    // 4) reveal 完全落地
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 48));
    }
    await tester.pumpAndSettle();

    // 断言 A：只有 1 个 text 时间线条目（完整一段，未被劈成两段）。
    //
    // 计数口径（2026-10-07 随「列表项锚点去 GlobalKey」一并收紧）：原写法是
    // `w.key.toString().contains('live:text')` —— 它只在外层条目包装层的 key 是
    // **匿名 GlobalKey**（toString 不含 renderKey）时才恰好等于段数。改为按
    // `ValueKey<String>` 的**取值**精确匹配 `live:text:*`，即只数
    // `_LiveTimelineItem` 自持的那把段级 key，不再被包装层/框架 `KeyedSubtree.wrap`
    // 的键串污染（判据仍是「段数 = 1」）。
    final textKeys = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('live:text'),
        )
        .evaluate()
        .length;
    expect(textKeys, 1, reason: '文本应是一整段，不能被工具断点劈开');

    // 断言 B：整句开头与「致」（句子中段）都在同一段内渲染
    expect(find.textContaining('好喵，这是个新的方向'), findsOneWidget);
    expect(find.textContaining('致性问题'), findsOneWidget);
    // 断言 C：工具卡存在（合并卡），排在文本之后
    expect(find.byKey(const ValueKey('live:tools:merged')), findsOneWidget);
  });

  testWidgets('文本全到达且 reveal 完成后工具事件到达 → 完整句 + 工具卡（基线不回归）', (tester) async {
    final api = await pumpStreamingSession(tester);

    api.emit(const TokenSseEvent('好喵，这是个新的方向/一致性问题。柚子先明确：先摸清侧栏工具栏和窄屏导航的实现。'));
    await tester.pump();
    // 文本完全落地后再来工具事件
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 48));
    }
    api.emit(
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'read_file', args: {'path': 'x'}),
      ),
    );
    await tester.pump();
    api.emit(
      const ToolCompletedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'read_file'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final textKeys = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('live:text'),
        )
        .evaluate()
        .length;
    expect(textKeys, 1);
    expect(find.textContaining('好喵，这是个新的方向'), findsOneWidget);
    expect(find.textContaining('致性问题'), findsOneWidget);
    expect(find.byKey(const ValueKey('live:tools:merged')), findsOneWidget);
  });
}
