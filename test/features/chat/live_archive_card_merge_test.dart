import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

Map<String, Object?> _toolCall(String id, String name) => {
  'id': id,
  'type': 'function',
  'function': {'name': name, 'arguments': '{"command":"ls"}'},
};

/// live 期间最后一张归档卡与 live 时间线首卡之间没有正文分隔（流式临时
/// 消息被服务端权威行吸收重锚，该权威行自身不进 transcript）→ 必须呈现为
/// 一张卡。旧实现两卡分属两个渲染源、各自成卡，视觉上就是主人所报的
/// 「相邻两张 tools 不合并，有时变成多张 tools」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live：末张归档卡与 live 首卡合并为一张', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      kToolGroupCoalesceKey: false,
      kTurnCollapseKey: false,
    });

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    api.sessionResult = {
      'session': {
        'session_id': 's-live-merge',
        'title': 'live-merge',
        'active_stream_id': 'stream-1',
        'messages': [
          {'role': 'user', 'content': '开始', 'message_id': 'u1'},
          {
            'role': 'assistant',
            'content': '第一段正文。',
            'message_id': 'a1',
            'tool_calls': [_toolCall('c1', 'terminal')],
          },
          {
            'role': 'tool',
            'content': 'ok1',
            'tool_call_id': 'c1',
            'message_id': 'm-t1',
          },
          {
            'role': 'assistant',
            'content': '',
            'message_id': 'a2',
            'tool_calls': [_toolCall('c2', 'terminal')],
          },
          {
            'role': 'tool',
            'content': 'ok2',
            'tool_call_id': 'c2',
            'message_id': 'm-t2',
          },
        ],
        'message_count': 5,
      },
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-live-merge')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    List<ToolCallGroupCard> cards() => tester
        .widgetList<ToolCallGroupCard>(find.byType(ToolCallGroupCard))
        .toList();

    // 无正文分隔的相邻归档块已合成一张（a1 的 c1 + a2 的 c2）。
    expect(cards().length, 1, reason: '相邻无正文的归档块应合成一张卡');
    expect(
      cards().single.group.toolCalls.map((c) => c.id).toList(),
      ['c1', 'c2'],
    );

    // live 工具到达：streaming 消息重锚到最后一条 assistant（a2），其行不进
    // transcript → live 卡与上方归档卡之间没有正文，应并入同一张卡。
    api.emit(
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 'L1', name: 'terminal'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));

    expect(
      find.byType(ToolCallGroupCard),
      findsOneWidget,
      reason: 'live 首卡与末张归档卡之间无正文时不得变成第二张 tools 卡',
    );
    expect(
      cards().single.group.toolCalls.map((c) => c.id).toList(),
      ['c1', 'c2', 'L1'],
      reason: 'live 工具行按事件时间线追加在归档行之后',
    );
  });

  testWidgets('live：同一工具 id 同时出现在归档卡与 live 时只留一行', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      kToolGroupCoalesceKey: false,
      kTurnCollapseKey: false,
    });

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    api.sessionResult = {
      'session': {
        'session_id': 's-live-dedupe',
        'title': 'live-dedupe',
        'active_stream_id': 'stream-1',
        'messages': [
          {'role': 'user', 'content': '开始', 'message_id': 'u1'},
          {
            'role': 'assistant',
            'content': '第一段正文。',
            'message_id': 'a1',
            'tool_calls': [_toolCall('c1', 'terminal')],
          },
          {
            'role': 'tool',
            'content': 'ok1',
            'tool_call_id': 'c1',
            'message_id': 'm-t1',
          },
        ],
        'message_count': 3,
      },
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-live-dedupe')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    // 服务端 transcript 已归档 c1，live 侧又收到同一 stable id（归档副本仍在
    // liveToolCalls 里继续切片展示）→ 合并时必须按 stable id 去重，不得双显。
    api.emit(
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 'c1', name: 'terminal'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));

    final cards = tester
        .widgetList<ToolCallGroupCard>(find.byType(ToolCallGroupCard))
        .toList();
    expect(cards.length, 1, reason: '合并后只有一张卡');
    expect(
      cards.single.group.toolCalls.map((c) => c.id).toList(),
      ['c1'],
      reason: '同一 stable id 的归档行与 live 行不得重复',
    );
  });
}