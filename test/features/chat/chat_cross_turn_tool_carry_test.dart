import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 回合 1 的工具数。
const int kTurn1Tools = 24;

/// 回合 1 窗口的偏移（模拟真实服务端分页窗口：offset > 0 且随转录增长而滑动）。
const int kTurn1Offset = 100;

/// 回合 2 收尾快照的窗口偏移（窗口已滑过回合 1 的行 ⇒ 回合 1 成员的 `raw:` 锚全部失效）。
const int kTurn2Offset = 130;

final RegExp _turn1ToolId = RegExp(r'^t\d+$');

/// 回合 1 窗口：`[user, (assistant(tool), tool) × N]`，**行不带 message_id**
/// （对齐真实 hermes-webui 窗口：`message_id` 为 null ⇒ anchor 一律是 `raw:<offset+i>`）。
Map<String, Object?> buildTurn1Window() {
  final messages = <Map<String, Object?>>[
    {'role': 'user', 'content': '第一回合：长任务'},
  ];
  final toolCalls = <Map<String, Object?>>[];
  for (var i = 0; i < kTurn1Tools; i++) {
    messages.add({
      'role': 'assistant',
      'content': '',
      'reasoning': '思考$i。',
      'tool_calls': [
        {
          'id': 't$i',
          'call_id': 't$i',
          'type': 'function',
          'function': {'name': 'terminal', 'arguments': '{"command":"echo $i"}'},
        },
      ],
    });
    messages.add({'role': 'tool', 'tool_call_id': 't$i', 'content': 'ok'});
    toolCalls.add({
      'name': 'terminal',
      'snippet': 'out',
      'tid': 't$i',
      'assistant_msg_idx': messages.length - 2,
    });
  }
  return {
    'session_id': 's-carry',
    'messages': messages,
    'tool_calls': toolCalls,
    'message_count': kTurn1Offset + messages.length,
    '_messages_offset': kTurn1Offset,
    '_messages_truncated': true,
  };
}

/// 回合 2 的收尾窗口：已滑过回合 1 大部 + 回合 2（1 个工具，可选收尾正文）。
Map<String, Object?> buildTurn2Window({required bool withClosingText}) {
  final messages = <Map<String, Object?>>[
    {
      'role': 'assistant',
      'content': '',
      'reasoning': '思考$kTurn1Tools。',
      'tool_calls': [
        {
          'id': 't23',
          'call_id': 't23',
          'type': 'function',
          'function': {'name': 'terminal', 'arguments': '{"command":"echo 23"}'},
        },
      ],
    },
    {'role': 'tool', 'tool_call_id': 't23', 'content': 'ok'},
    {'role': 'user', 'content': '第二回合：小任务'},
    {
      'role': 'assistant',
      'content': '',
      'reasoning': '思考。',
      'tool_calls': [
        {
          'id': 'r1',
          'call_id': 'r1',
          'type': 'function',
          'function': {'name': 'read_file', 'arguments': '{"path":"a"}'},
        },
      ],
    },
    {'role': 'tool', 'tool_call_id': 'r1', 'content': 'ok'},
    if (withClosingText)
      {'role': 'assistant', 'content': '第二回合完成。'},
  ];
  return {
    'session_id': 's-carry',
    'messages': messages,
    'tool_calls': const <Object?>[],
    'message_count': kTurn1Offset + 1 + kTurn1Tools * 2 + messages.length,
    '_messages_offset': kTurn2Offset,
    '_messages_truncated': true,
  };
}

Future<({FakeChatApi api, ChatController controller, ProviderContainer c})>
_pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    kTurnCollapseKey: false,
    kToolGroupCoalesceKey: false,
    kThinkGroupCoalesceKey: true,
    kHideReasoningKey: true,
  });

  final api = FakeChatApi()
    ..statusResponse = const ChatStreamStatusResponse(active: false);
  api.sessionResult = {
    'session': {
      'session_id': 's-carry',
      'messages': const <Object?>[],
      'message_count': 0,
    },
  };
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const CupertinoApp(home: ChatPage(sessionId: 's-carry')),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ChatPage)),
  );
  final controller = container.read(chatControllerProvider('s-carry').notifier);
  return (api: api, controller: controller, c: container);
}

Future<void> _driveTurn1(
  WidgetTester tester,
  FakeChatApi api,
  ChatController controller,
) async {
  api.sessionResult = {'session': buildTurn1Window()};
  await controller.send('第一回合：长任务');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  for (var i = 0; i < kTurn1Tools; i++) {
    api.emit(
      ToolStartedSseEvent(
        ToolStreamEvent(
          stableId: 't$i',
          name: 'terminal',
          args: {'command': 'echo $i'},
        ),
      ),
    );
    api.emit(
      ToolCompletedSseEvent(
        ToolStreamEvent(stableId: 't$i', name: 'terminal', duration: 0.1),
      ),
    );
  }
  api.emit(DoneSseEvent(DoneStreamEvent(session: buildTurn1Window())));
  api.emit(const StreamEndSseEvent());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _driveTurn2(
  WidgetTester tester,
  FakeChatApi api,
  ChatController controller,
) async {
  api.sessionResult = {'session': buildTurn2Window(withClosingText: true)};
  await controller.send('第二回合：小任务');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  api.emit(
    const ToolStartedSseEvent(
      ToolStreamEvent(stableId: 'r1', name: 'read_file', args: {'path': 'a'}),
    ),
  );
  api.emit(
    const ToolCompletedSseEvent(
      ToolStreamEvent(stableId: 'r1', name: 'read_file', duration: 0.2),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  api.emit(const TokenSseEvent('第二回合完成。'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
  api.emit(
    DoneSseEvent(
      DoneStreamEvent(session: buildTurn2Window(withClosingText: true)),
    ),
  );
  api.emit(const StreamEndSseEvent());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 收集「渲染位置在回合 2 提问气泡之下」的过程卡（= 回合 2 的过程区）。
List<({ToolCallGroupCard card, String label})> _cardsInTurn2Area(
  WidgetTester tester, {
  required double turn2UserTop,
}) {
  final result = <({ToolCallGroupCard card, String label})>[];
  for (final card in tester.widgetList<ToolCallGroupCard>(
    find.byType(ToolCallGroupCard),
  )) {
    final top = tester.getTopLeft(find.byWidget(card)).dy;
    if (top <= turn2UserTop) continue;
    final ids = card.group.toolCalls
        .map((t) => t.isThinking ? 'think' : t.id)
        .join(',');
    result.add((
      card: card,
      label: 'card[${card.group.id}] anchor=${card.group.anchorMessageID} '
          'ids=[$ids]',
    ));
  }
  return result;
}

void main() {
  testWidgets('回合 2 的过程卡不得混入回合 1 的工具（跨回合携带）', (tester) async {
    final env = await _pump(tester);
    await _driveTurn1(tester, env.api, env.controller);
    await _driveTurn2(tester, env.api, env.controller);

    final turn2UserTop = tester.getTopLeft(find.text('第二回合：小任务')).dy;
    final turn2Cards = _cardsInTurn2Area(tester, turn2UserTop: turn2UserTop);
    for (final e in turn2Cards) {
      debugPrint('  回合2 区卡片: ${e.label}');
    }

    final offenders = <String>[
      for (final e in turn2Cards)
        if (e.card.group.toolCalls.any((t) => _turn1ToolId.hasMatch(t.id)))
          e.label,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          '回合 2 提问气泡之下的过程卡里出现了回合 1 的工具 —— 上一回合的工具记录被'
          '渲染进了下一回合的过程卡（跨回合携带）',
    );
  });

  testWidgets('收尾刷新后：工具卡回到本回合且不落到正文下方', (tester) async {
    final env = await _pump(tester);
    await _driveTurn1(tester, env.api, env.controller);
    await _driveTurn2(tester, env.api, env.controller);

    // 收尾刷新（done 后拉 transcript）：服务端窗口已覆盖回合 1 的工具真身。
    env.api.sessionResult = {
      'session': {
        'session_id': 's-carry',
        'messages': [
          ...(buildTurn1Window()['messages'] as List),
          {'role': 'user', 'content': '第二回合：小任务'},
          {
            'role': 'assistant',
            'content': '',
            'reasoning': '思考。',
            'tool_calls': [
              {
                'id': 'r1',
                'call_id': 'r1',
                'type': 'function',
                'function': {'name': 'read_file', 'arguments': '{"path":"a"}'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'r1', 'content': 'ok'},
          {'role': 'assistant', 'content': '第二回合完成。'},
        ],
        'message_count': kTurn1Offset + 1 + kTurn1Tools * 2 + 5,
        '_messages_offset': kTurn1Offset,
        '_messages_truncated': true,
      },
    };
    await env.controller.loadMessages();
    await tester.pumpAndSettle();

    final turn2UserTop = tester.getTopLeft(find.text('第二回合：小任务')).dy;
    final turn2Cards = _cardsInTurn2Area(tester, turn2UserTop: turn2UserTop);
    for (final e in turn2Cards) {
      debugPrint('  刷新后回合2 区卡片: ${e.label}');
    }

    // ① 回合 2 的过程区不得出现回合 1 的工具。
    expect(
      turn2Cards.where(
        (e) => e.card.group.toolCalls.any((t) => _turn1ToolId.hasMatch(t.id)),
      ),
      isEmpty,
      reason: '收尾刷新后回合 2 过程卡仍混入回合 1 的工具',
    );
    // ② 含本回合工具的那张卡必须在正文上方（本回合先调工具后出正文）。
    final turn2FinalTop = tester.getTopLeft(find.text('第二回合完成。')).dy;
    final own = turn2Cards
        .where((e) => e.card.group.toolCalls.any((t) => t.id == 'r1'))
        .toList();
    expect(own, isNotEmpty, reason: '收尾刷新后回合 2 自己的工具卡应当可见');
    for (final e in own) {
      expect(
        tester.getTopLeft(find.byWidget(e.card)).dy,
        lessThan(turn2FinalTop),
        reason: '回合 2 的工具卡落到了正文下方（本回合工具先于正文，应在上方）',
      );
    }
  });
}
