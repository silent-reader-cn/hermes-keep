import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

/// 长会话构造：每轮 `user` + [工具结果 × toolsPerTurn] + `assistant`。
///
/// `toolsPerTurn > 0` 时，`state.messages` 的下标与 `transcriptMessagesProvider`
/// 产出的列表下标会**错开**（transcript 跳过 `role == 'tool'` 的消息）——
/// 这正是「长内容中点击大纲条目无效」的现场：大纲把 messages 下标当
/// transcript 下标用于粗跳插值，内容越长错得越多。
List<Map<String, dynamic>> buildLongSession({
  int turns = 30,
  int toolsPerTurn = 0,
  int assistantRepeat = 6,
  int userRepeat = 1,
}) {
  final messages = <Map<String, dynamic>>[];
  for (var i = 0; i < turns; i++) {
    messages.add({
      'role': 'user',
      'content': 'U-turn-$i 提问正文，用来把列表总高度拉到真机量级。' * userRepeat,
      'message_id': 'u-$i',
    });
    for (var t = 0; t < toolsPerTurn; t++) {
      messages.add({
        'role': 'tool',
        'content': '{"result": "tool output $i-$t"}',
        'message_id': 't-$i-$t',
      });
    }
    messages.add({
      'role': 'assistant',
      'content': 'A-turn-$i 回答正文，用来撑高列表。' * assistantRepeat,
      'message_id': 'a-$i',
    });
  }
  return messages;
}

Future<ProviderContainer> pumpChatSession(
  WidgetTester tester,
  String sessionId,
  List<Map<String, dynamic>> messages,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = FakeChatApi()
    ..statusResponse = const ChatStreamStatusResponse(active: false)
    ..sessionResult = {
      'session': {
        'session_id': sessionId,
        'title': '大纲测试会话',
        'messages': messages,
        'message_count': messages.length,
      },
    };

  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: CupertinoApp(home: ChatPage(sessionId: sessionId)),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(ChatPage)));
}

ScrollPosition scrollPositionOf(WidgetTester tester) {
  final finder = find
      .descendant(
        of: find.byType(ChatMessageList),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(finder).position;
}

/// 点标题栏展开大纲 → 点第 [entryIndex] 个条目 → 等跳转收敛。
Future<void> tapOutlineEntry(
  WidgetTester tester,
  ProviderContainer container,
  String sessionId,
  int entryIndex,
) async {
  final entries = container.read(chatOutlineEntriesProvider(sessionId));
  await tester.tap(find.byKey(const ValueKey('chat-title-outline-trigger')));
  await tester.pump();

  final rowFinder = find.byKey(
    ValueKey('outline-row-${entries[entryIndex].renderId}'),
  );
  expect(rowFinder, findsOneWidget, reason: '大纲面板应列出第 ${entryIndex + 1} 个条目');

  await tester.tap(rowFinder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('大纲点击跳转：真实 UI 路径（长内容 + 工具消息错位）', () {
    testWidgets('点标题展开大纲后点条目，目标轮次进入视口且不落底', (tester) async {
      // 内容形态与真机一致：每轮夹 5 条工具结果 ⇒ messages 下标 ≠ transcript 下标
      final container = await pumpChatSession(
        tester,
        's-outline-real',
        buildLongSession(
          turns: 30,
          toolsPerTurn: 5,
          userRepeat: 3,
          assistantRepeat: 8,
        ),
      );
      final pos = scrollPositionOf(tester);

      final entries = container.read(
        chatOutlineEntriesProvider('s-outline-real'),
      );
      expect(entries, hasLength(30));

      await tapOutlineEntry(tester, container, 's-outline-real', 1);

      expect(
        find.textContaining('U-turn-1 提问正文'),
        findsOneWidget,
        reason: '点击大纲条目后目标轮次必须进入视口（错位下标会让它永远看不到）',
      );
      expect(
        pos.pixels,
        greaterThan(100.0),
        reason: '跳位后停在阅读位，不落回底部',
      );
    });

    testWidgets('即便调用方传入错误的 messages 下标，renderId 仍是权威定位依据', (
      tester,
    ) async {
      final container = await pumpChatSession(
        tester,
        's-outline-authority',
        buildLongSession(
          turns: 30,
          toolsPerTurn: 5,
          userRepeat: 3,
          assistantRepeat: 8,
        ),
      );
      final listState = tester.state<ChatMessageListState>(
        find.byType(ChatMessageList),
      );
      final pos = scrollPositionOf(tester);

      final entries = container.read(
        chatOutlineEntriesProvider('s-outline-authority'),
      );
      final target = entries[1];
      expect(target.renderId, 'transcript:7'); // 对应 messages 下标 7

      // 故意传 0（错误的 messages 下标）：旧实现据此算出偏移 0 ⇒ 原地不动
      listState.outlineJumpTo(target.renderId, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.textContaining('U-turn-1 提问正文'),
        findsOneWidget,
        reason: 'renderId 反查到的 transcript 下标才是粗跳依据，入参错误不应影响定位',
      );
      expect(pos.pixels, greaterThan(100.0), reason: '不得停在底部');
    });
  });

  group('大纲条目只列主人的提问', () {
    testWidgets('后台任务完成等系统合成消息不进大纲，也不占轮次编号', (tester) async {
      final container = await pumpChatSession(tester, 's-outline-filter', [
        {
          'role': 'user',
          'content': '[Workspace::v1: D:\\projects\\hermes-ui]\n真正的第一轮提问',
          'message_id': 'u-0',
        },
        {'role': 'assistant', 'content': '回答 0', 'message_id': 'a-0'},
        // 后台任务完成：服务端合成的 role=user 消息
        {
          'role': 'user',
          'content':
              '[IMPORTANT: Background process proc_abc completed '
                  '(exit_code=0).\nCommand: sleep 30\nOutput:\n done]',
          'message_id': 'bg-1',
        },
        {'role': 'assistant', 'content': '收到', 'message_id': 'a-1'},
        // 定时任务回执（不带方括号）
        {
          'role': 'user',
          'content': 'Cronjob Response: 每日扫描\n任务已完成。',
          'message_id': 'cron-1',
        },
        {'role': 'assistant', 'content': '收到', 'message_id': 'a-2'},
        {
          'role': 'user',
          'content': '[Workspace::v1: D:\\projects\\hermes-ui]\n真正的第二轮提问',
          'message_id': 'u-1',
        },
        {'role': 'assistant', 'content': '回答 1', 'message_id': 'a-3'},
      ]);

      final entries = container.read(
        chatOutlineEntriesProvider('s-outline-filter'),
      );

      expect(
        entries,
        hasLength(2),
        reason: '后台任务完成 / 定时回执不是主人的提问，不占大纲行',
      );
      expect(entries[0].index, 1);
      expect(entries[1].index, 2, reason: '轮次编号连续，不被系统消息撑出空号');
      expect(entries[0].preview, '真正的第一轮提问');
      expect(entries[1].preview, '真正的第二轮提问');
    });

    testWidgets('主人手打的 [IMPORTANT: …] 不被误伤', (tester) async {
      final container = await pumpChatSession(tester, 's-outline-mine', [
        {
          'role': 'user',
          'content': '[IMPORTANT: hello world] 这是我手打的',
          'message_id': 'u-0',
        },
        {'role': 'assistant', 'content': '回答', 'message_id': 'a-0'},
      ]);

      final entries = container.read(
        chatOutlineEntriesProvider('s-outline-mine'),
      );
      expect(entries, hasLength(1));
      expect(entries[0].preview, '[IMPORTANT: hello world] 这是我手打的');
    });

    testWidgets('预览不暴露服务端注入标记（上游剥离行为守卫）', (tester) async {
      // 实测：`[Workspace::v1: …]` / `[Attached files: …]` 在 ChatController
      // 加载归一化阶段就已被剥离，大纲 provider 拿到的 content 本就干净 ——
      // 故本用例无法通过回退大纲改动转红，它守的是「上游剥离行为不退化、
      // 大纲预览不会突然冒出工作区路径」这道体验底线。
      final container = await pumpChatSession(tester, 's-outline-preview', [
        {
          'role': 'user',
          'content':
              '[Workspace::v1: D:\\projects\\hermes-ui]\n'
                  '修复一下在长内容中点击标题后的大纲弹窗中点击弹窗无效的 bug 吧\n\n'
                  '[Attached files: ref-a, ref-b]',
          'message_id': 'u-0',
        },
        {'role': 'assistant', 'content': '回答', 'message_id': 'a-0'},
      ]);

      final entries = container.read(
        chatOutlineEntriesProvider('s-outline-preview'),
      );
      expect(entries, hasLength(1));
      expect(
        entries[0].preview,
        startsWith('修复一下在长内容中'),
        reason: '工作区路径不该占满预览首 40 字',
      );
      expect(entries[0].preview, isNot(contains('Workspace::v1')));
      expect(entries[0].preview, isNot(contains('Attached files')));
    });
  });
}
