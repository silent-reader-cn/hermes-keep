import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 忠实事件时间线：撤销完成态卡位固定干预（推翻 b0db568「卡恒在正文下方」与 ecf850e「卡恒在上方」）。
///
/// 真实事件序：think(m1) → text(m1) → tools(m1) → think(m2) → text(m2) → tools(m2)
/// - 聚合关（coalesce=false）：
///   1. 首段 text 之前的 think(m1) → 独立思考卡，在第一条正文「上方」；
///   2. tools(m1)+think(m2)（夹在 text(m1) 与 text(m2) 之间）→ 合并一张卡，在两段正文「之间」；
///   3. 末段 text 之后的 tools(m2) → 工具卡，在最后一条正文「下方」。
/// - 聚合开（coalesce=true）：
///   整回合并为一张大卡，大卡位置 = 回合第一个事件（思考，回合开头）→ 钉在首条正文「上方」。
void main() {
  Future<FakeChatApi> pumpHistorySession(
    WidgetTester tester, {
    required bool coalesceTools,
  }) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      kTurnCollapseKey: false,
      kToolGroupCoalesceKey: coalesceTools,
      kThinkGroupCoalesceKey: true,
      kHideReasoningKey: false,
    });
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's-timeline',
        'title': 'timeline',
        'active_stream_id': null,
        'messages': [
          {'role': 'user', 'content': '请帮我实现这个功能', 'message_id': 'u1'},
          {
            'role': 'assistant',
            'message_id': 'a1',
            'reasoning': '第一步先理清需求和架构。',
            'content': '收到，我先进行第一步分析。',
            'tool_calls': [
              {
                'id': 'call_1',
                'call_id': 'call_1',
                'type': 'function',
                'function': {
                  'name': 'read_file',
                  'arguments': '{"path": "lib/a.dart"}',
                },
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_1', 'content': '{"ok":1}'},
          {
            'role': 'assistant',
            'message_id': 'a2',
            'reasoning': '第二步检查具体实现逻辑并进行修改。',
            'content': '接下来进行修改和验证。',
            'tool_calls': [
              {
                'id': 'call_2',
                'call_id': 'call_2',
                'type': 'function',
                'function': {
                  'name': 'write_file',
                  'arguments': '{"path": "lib/b.dart"}',
                },
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_2', 'content': '{"ok":1}'},
        ],
        'message_count': 5,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-timeline')),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('完成态（聚合关）：忠实事件时间线——思考卡在首正文上方、中间卡在两正文之间、工具卡在末正文下方', (
    tester,
  ) async {
    await pumpHistorySession(tester, coalesceTools: false);

    // 两个 assistant 消息正文均已渲染
    final text1Finder = find.textContaining('收到，我先进行第一步分析');
    final text2Finder = find.textContaining('接下来进行修改和验证');
    expect(text1Finder, findsOneWidget);
    expect(text2Finder, findsOneWidget);

    final toolCards = find.byType(ToolCallGroupCard);
    expect(toolCards, findsNWidgets(3));

    // A 重构（reverse）：`find.byType` 遍历顺序 = 物理 index 顺序，reverse 下
    // 物理 0 在底部 ⇒ 树序为「从下到上」，`.at(i)` 视觉语义反转。改为按屏幕
    // dy 排序（从上到下）取用，与树序解耦。
    final cardTops = <double>[
      for (var i = 0; i < toolCards.evaluate().length; i++)
        tester.getTopLeft(toolCards.at(i)).dy,
    ]..sort();
    final card0Top = cardTops[0];
    final text1Top = tester.getTopLeft(text1Finder).dy;
    final card1Top = cardTops[1];
    final text2Top = tester.getTopLeft(text2Finder).dy;
    final card2Top = cardTops[2];

    // 1. 首组思考卡在第一条正文上方
    expect(
      card0Top,
      lessThan(text1Top),
      reason: '首组思考卡应在首条正文上方，实际 card0Top=$card0Top text1Top=$text1Top',
    );

    // 2. 中间卡在第一条正文下方、第二条正文上方（两正文之间）
    expect(
      card1Top,
      greaterThan(text1Top),
      reason: '中间卡应在第一条正文下方，实际 text1Top=$text1Top card1Top=$card1Top',
    );
    expect(
      card1Top,
      lessThan(text2Top),
      reason: '中间卡应在第二条正文上方，实际 card1Top=$card1Top text2Top=$text2Top',
    );

    // 3. 末组工具卡在第二条正文下方
    expect(
      card2Top,
      greaterThan(text2Top),
      reason: '末组工具卡应在最后正文下方，实际 text2Top=$text2Top card2Top=$card2Top',
    );
  });

  testWidgets('完成态（聚合开）：大卡钉在首条正文上方', (tester) async {
    await pumpHistorySession(tester, coalesceTools: true);

    final text1Finder = find.textContaining('收到，我先进行第一步分析');
    final text2Finder = find.textContaining('接下来进行修改和验证');
    expect(text1Finder, findsOneWidget);
    expect(text2Finder, findsOneWidget);

    // 聚合为一张大卡
    final toolCards = find.byType(ToolCallGroupCard);
    expect(toolCards, findsOneWidget);

    final cardTop = tester.getTopLeft(toolCards.first).dy;
    final text1Top = tester.getTopLeft(text1Finder).dy;

    // 大卡钉在首条正文上方（因为回合首事件为思考）
    expect(
      cardTop,
      lessThan(text1Top),
      reason: '聚合开时大卡应排在首条正文上方，实际 cardTop=$cardTop text1Top=$text1Top',
    );
  });
}
