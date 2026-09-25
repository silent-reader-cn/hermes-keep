import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 回归：空 content 的 assistant 消息（agy 纯工具回合）不得渲染成空气泡。
///
/// 背景（2026-09-03 会话 466b3311f728 实证）：agy 子代理每调一个工具就产一条
/// content='' + tool_calls + reasoning 的 assistant 消息。这类消息在
/// transcriptMessagesProvider 过滤中曾因 hasReasoningGroups 被保留，但
/// _AssistantContent 不渲染 reasoningGroups（思考已由 withThinkingRows 融进
/// 工具组 think 子卡行）→ 渲染成 0 高度气泡 + padding 占位 = 折叠卡下方空白，
/// 且 tool 越多空白越高。
///
/// 修复：空内容消息仅当挂载工具组/附件时保留（纯思考消息会被
/// withThinkingRows 补 persisted-think- 工具组，仍走 hasToolGroups 保留）。
void main() {
  Future<FakeChatApi> pumpHistory({
    required WidgetTester tester,
    required int emptyToolMessages,
  }) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      kToolGroupCoalesceKey: true,
      kThinkGroupCoalesceKey: true,
      kHideReasoningKey: false,
    });
    final api = FakeChatApi();
    final msgs = <Map<String, Object?>>[
      {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
      for (var i = 0; i < emptyToolMessages; i++)
        {
          'role': 'assistant',
          'content': '',
          'message_id': 'a-empty-$i',
          'reasoning': '思考段 $i：我需要检查实现…',
          'tool_calls': [
            {
              'id': 'call-empty-$i',
              'call_id': 'call-empty-$i',
              'type': 'function',
              'function': {
                'name': 'execute_code',
                'arguments': '{"code": "print(1)"}',
              },
            },
          ],
        },
      for (var i = 0; i < emptyToolMessages; i++)
        {
          'role': 'tool',
          'tool_call_id': 'call-empty-$i',
          'content': '{"ok":1}',
        },
      {
        'role': 'assistant',
        'content': '两条新菜单项点击后路由没动。交给 agy 带着诊断线索返修：',
        'message_id': 'a-text',
        'tool_calls': [
          {
            'id': 'call-x',
            'call_id': 'call-x',
            'type': 'function',
            'function': {
              'name': 'terminal',
              'arguments': '{"command": "echo x"}',
            },
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 'call-x', 'content': '{"ok":1}'},
    ];
    api.sessionResult = {
      'session': {
        'session_id': 's-h',
        'title': 'history',
        'active_stream_id': null,
        'messages': msgs,
        'message_count': msgs.length,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-h')),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('空消息 0 条基线：文本气泡位置', (tester) async {
    await pumpHistory(tester: tester, emptyToolMessages: 0);
    final textFinder = find.textContaining('两条新菜单项');
    expect(textFinder, findsOneWidget);
    // A 重构（reverse）：内容不足一屏时**贴底**排列（正向为贴顶），
    // 故绝对 y 不再是「视口顶部附近」——改判「在视口内」。
    final y0 = tester.getTopLeft(textFinder).dy;
    expect(y0, greaterThan(0), reason: '文本气泡应在视口内');
    expect(y0, lessThan(3000.0), reason: '文本气泡应在视口内（reverse 贴底）');
  });

  testWidgets('3 条空消息不得产生空气泡把文本顶低', (tester) async {
    // A 重构（reverse）：内容不足一屏时贴底排列，绝对 y 不可跨用例比较；
    // 本用例真实意图是「空气泡不产生额外高度」——改为与 0 条基线直接比较。
    await pumpHistory(tester: tester, emptyToolMessages: 0);
    final y0 = tester.getTopLeft(find.textContaining('两条新菜单项')).dy;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await pumpHistory(tester: tester, emptyToolMessages: 3);
    final y3 = tester.getTopLeft(find.textContaining('两条新菜单项')).dy;
    // 修复前：3 条空消息每条空气泡 ≈22px → 文本被顶低 ~66px（位移明显）；
    // 修复后：空消息被过滤，文本位置与 0 条基线一致（差值应在容差内）。
    expect(
      (y3 - y0).abs(),
      lessThan(30),
      reason: '空内容消息不应保留为空气泡占位（0 条 y=$y0 vs 3 条 y=$y3）',
    );
    // 工具聚合卡仍应存在（挂在最早工具消息上）
    expect(find.textContaining('执行代码 ×3'), findsOneWidget);
  });
}