import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

/// 大纲点击跳转端到端回归：**从标题栏点开面板 → 点条目 → 列表真的到位**。
///
/// 关键背景：会话里只要存在被 transcript 跳过的消息（`role == 'tool'`、
/// tool-result-only、流式占位…），「`state.messages` 下标」与「transcript 列表
/// 下标」就会错开；粗跳估算若拿前者当后者插值，落点会偏到半程，目标永不入
/// 视口 —— 用户看到的就是「点了大纲条目没反应」。
///
/// 本文件覆盖两条真实可复现路径：
/// 1. 目标**已在视口内**（精跳 `ensureVisible`）；
/// 2. 目标**在视口外**（粗跳 + 重试收敛），含 tool 密集长会话里的
///    「最早一轮 / 中间轮次 / 靠近底部轮次」三档。
void main() {
  const turns = 30;
  const toolsPerTurn = 4; // 每轮 4 条 tool 消息（transcript 会全部过滤掉）

  /// 每轮 messages 布局：user 在下标 `turn*6`，renderId = `transcript:${turn*6}`。
  const perTurn = 1 + toolsPerTurn + 1;

  String renderIdOf(int turn) => 'transcript:${turn * perTurn}';

  Future<void> pumpLongSession(WidgetTester tester, String sid) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: false);

    final messages = <Map<String, dynamic>>[];
    for (var i = 0; i < turns; i++) {
      messages.add({
        'role': 'user',
        'content': 'U-turn-$i 提问正文',
        'message_id': 'u-$i',
      });
      for (var t = 0; t < toolsPerTurn; t++) {
        messages.add({
          'role': 'tool',
          'content': '{"result": "tool output $i-$t"}',
          'tool_call_id': 'tc-$i-$t',
          'tool_name': 'read_file',
        });
      }
      messages.add({
        'role': 'assistant',
        'content': 'A-turn-$i 回答正文，用来撑高列表。' * 6,
        'message_id': 'a-$i',
      });
    }

    api.sessionResult = {
      'session': {
        'session_id': sid,
        'title': '大纲跳转长会话',
        'messages': messages,
        'message_count': messages.length,
      },
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: CupertinoApp(home: ChatPage(sessionId: sid)),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition posOf(WidgetTester tester) {
    final f = find
        .descendant(
          of: find.byType(ChatMessageList),
          matching: find.byType(Scrollable),
        )
        .first;
    return tester.state<ScrollableState>(f).position;
  }

  /// 点标题栏开面板 → 点指定条目 → 断言面板关闭 + 目标进入视口。
  Future<void> tapOutlineEntry(
    WidgetTester tester, {
    required String renderId,
    required String targetText,
  }) async {
    await tester.tap(find.byKey(const ValueKey('chat-title-outline-trigger')));
    await tester.pumpAndSettle();

    final row = find.byKey(ValueKey('outline-row-$renderId'));
    expect(row, findsOneWidget, reason: '大纲面板应含条目 $renderId');
    // 长会话下面板自身可滚动：真实交互里用户会先把目标行滚进面板可视区。
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('outline-row-$renderId')),
      findsNothing,
      reason: '点击条目后面板应立即收起',
    );
    expect(
      find.textContaining(targetText),
      findsOneWidget,
      reason: '点击大纲条目后目标轮次应进入视口',
    );
  }

  testWidgets('视口外目标（最早一轮）：点击后目标进入视口', (tester) async {
    await pumpLongSession(tester, 's-e2e-first');
    final pos = posOf(tester);
    expect(pos.pixels, lessThan(80), reason: '初始应贴底');

    await tapOutlineEntry(
      tester,
      renderId: renderIdOf(0),
      targetText: 'U-turn-0 提问正文',
    );
    expect(
      posOf(tester).pixels,
      greaterThan(pos.maxScrollExtent * 0.8),
      reason: '最早一轮在视觉最上方，跳转后应接近滚动上限',
    );
  });

  testWidgets('视口外目标（中间轮次）：点击后目标进入视口', (tester) async {
    await pumpLongSession(tester, 's-e2e-middle');

    await tapOutlineEntry(
      tester,
      renderId: renderIdOf(15),
      targetText: 'U-turn-15 提问正文',
    );
    expect(
      posOf(tester).pixels,
      greaterThan(80),
      reason: '中间轮次跳转后应离开贴底位（离底阅读态）',
    );
  });

  testWidgets('视口外目标（tool 密集会话里的第 3 轮）：点击后目标进入视口', (
    tester,
  ) async {
    await pumpLongSession(tester, 's-e2e-early');

    await tapOutlineEntry(
      tester,
      renderId: renderIdOf(2),
      targetText: 'U-turn-2 提问正文',
    );
  });

  testWidgets('视口内目标（最后几轮）：点击后目标进入视口', (tester) async {
    await pumpLongSession(tester, 's-e2e-last');

    await tapOutlineEntry(
      tester,
      renderId: renderIdOf(29),
      targetText: 'U-turn-29 提问正文',
    );
  });

  testWidgets('短会话（几乎没有滚动高度）点最早一轮：不崩且照常收起面板', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: false)
      ..sessionResult = {
        'session': {
          'session_id': 's-e2e-short',
          'title': '短会话',
          'messages': [
            {'role': 'user', 'content': 'U-turn-0 提问正文', 'message_id': 'u-0'},
            {'role': 'assistant', 'content': '短回答', 'message_id': 'a-0'},
            {'role': 'user', 'content': 'U-turn-1 提问正文', 'message_id': 'u-1'},
            {'role': 'assistant', 'content': '短回答', 'message_id': 'a-1'},
          ],
          'message_count': 4,
        },
      };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-e2e-short')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-title-outline-trigger')));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('outline-row-transcript:0'));
    expect(row, findsOneWidget, reason: '短会话同样可开大纲（≥2 轮）');
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('outline-row-transcript:0')),
      findsNothing,
      reason: '面板照常收起，不得因滚动上限为 0 抛错',
    );
    expect(find.textContaining('U-turn-0 提问正文'), findsOneWidget);
  });
}
