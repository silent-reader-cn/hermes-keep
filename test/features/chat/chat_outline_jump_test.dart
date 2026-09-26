import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/chat/widgets/chat_outline_sheet.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('ChatOutlineSheet 弹层与间距测试', () {
    testWidgets('大纲悬浮面板向下展开位置为 anchorRect.bottom + 12（避免贴/盖导航栏）', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          chatOutlineEntriesProvider('s1').overrideWithValue([
            const OutlineEntry(
              index: 1,
              renderId: 'r1',
              messageId: 'm1',
              preview: '第 1 轮提问',
              loadedIndex: 0,
            ),
            const OutlineEntry(
              index: 2,
              renderId: 'r2',
              messageId: 'm2',
              preview: '第 2 轮提问',
              loadedIndex: 2,
            ),
          ]),
        ],
      );
      addTearDown(container.dispose);

      String? jumpedRenderId;
      int? jumpedLoadedIndex;
      bool dismissed = false;
      OverlayEntry? entry;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp(
            home: Consumer(
              builder: (context, ref, _) {
                return CupertinoPageScaffold(
                  navigationBar: const CupertinoNavigationBar(
                    middle: Text('会话标题'),
                  ),
                  child: Center(
                    child: CupertinoButton(
                      child: const Text('打开大纲'),
                      onPressed: () {
                        final overlay = Overlay.of(context);
                        const anchor = Rect.fromLTWH(100, 44, 200, 44);
                        entry = ChatOutlineSheet.insert(
                          overlay: overlay,
                          ref: ref,
                          anchorRect: anchor,
                          sessionId: 's1',
                          selectedRenderId: 'r1',
                          onJump: (rId, lIdx) {
                            jumpedRenderId = rId;
                            jumpedLoadedIndex = lIdx;
                          },
                          onDismiss: () {
                            dismissed = true;
                            entry?.remove();
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开大纲'));
      await tester.pump();

      // 验证大纲卡片 top 为 anchor.bottom(88) + 12 = 100
      final cardFinder = find.byType(SingleChildScrollView);
      expect(cardFinder, findsOneWidget);
      final cardTopLeft = tester.getTopLeft(cardFinder);
      expect(cardTopLeft.dy, closeTo(100.0, 1.0));

      // 点击第 2 行
      expect(find.text('第 2 轮提问'), findsOneWidget);
      await tester.tap(find.text('第 2 轮提问'));
      await tester.pump();

      expect(jumpedRenderId, 'r2');
      expect(jumpedLoadedIndex, 2);
      expect(dismissed, isTrue);
    });
  });

  group('ChatMessageList 大纲点击跳转跑飞与跟随防护回归测试', () {
    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    testWidgets('长会话视口外目标点击：准确定位目标气泡、停在阅读态不误入跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: false);

      // 构造 30 轮多消息长会话（共 60 条）
      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 30; i++) {
        messages.add({
          'role': 'user',
          'content': '用户第 $i 轮提问：测试大纲跳转定位准确性。这是一段用于撑起列表高度的测试文本。',
          'message_id': 'u-$i',
        });
        messages.add({
          'role': 'assistant',
          'content': '助手第 $i 轮回答：这里是较长的回复内容，用来拉大列表总滚动高度。' * 4,
          'message_id': 'a-$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-outline-jump',
          'title': '大纲跳转长会话',
          'messages': messages,
          'message_count': 60,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-outline-jump'),
          ),
        ),
      );

      // 等待初始定位收敛至底部
      await tester.pumpAndSettle();

      final listState = tester.state<ChatMessageListState>(
        find.byType(ChatMessageList),
      );
      final pos = positionOf(tester);

      // 确认初始处于底部附近（A 重构 reverse：贴底 ⇔ pixels ≈ 0；
      // 原正向为 pixels ≈ maxScrollExtent，两条断言其一被批量替换误改，此处归一）。
      expect(pos.pixels, lessThan(80));

      // 模拟点击标题栏展开大纲，并跳转到视口外较靠前的第 2 轮用户气泡（u-2，loadedIndex=4）
      final outlineTargetKey = 'u-2';
      listState.outlineJumpTo(outlineTargetKey, 4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 200));

      // 验证目标用户气泡进入视口
      expect(
        find.textContaining('用户第 2 轮提问'),
        findsOneWidget,
        reason: '视口外目标经粗跳+精定后已成功进入视口',
      );

      // 验证没有跳到底部且未进入跟随态
      final distFromBottom = pos.pixels;
      expect(
        distFromBottom,
        greaterThan(100.0),
        reason: '跳位后应停在阅读位，绝不落底',
      );

      // 验证回到底部按钮已展示
      expect(
        find.text('回到底部'),
        findsOneWidget,
        reason: '离底主动阅读态下右下角展示回底按钮',
      );
    });

    testWidgets('流式中点大纲跳转：停在阅读位，新 token 到达不拽回，点回底按钮才恢复跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 20; i++) {
        messages.add({
          'role': 'user',
          'content': '历史提问 $i：测试流式中大纲跳转。',
          'message_id': 'u-$i',
        });
        messages.add({
          'role': 'assistant',
          'content': '历史回复 $i：用于撑起滚动条。' * 3,
          'message_id': 'a-$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-outline-stream',
          'title': '流式大纲跳转',
          'active_stream_id': 'stream-outline',
          'messages': messages,
          'message_count': 40,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-outline-stream'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final listState = tester.state<ChatMessageListState>(
        find.byType(ChatMessageList),
      );
      final pos = positionOf(tester);

      // 流式进行中点大纲跳转到早期第 1 轮（u-1，loadedIndex=2）
      listState.outlineJumpTo('u-1', 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('历史提问 1'), findsOneWidget);
      final readingPos = pos.pixels;

      // 持续注入新的流式 token
      for (var i = 0; i < 5; i++) {
        api.emit(TokenSseEvent('新流式内容 chunk $i '));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump();
      }

      // 新 token 到达时 pixels 会（也必须）同量前进以抵消内容推移；关键是
      // **不得被拽回底部**（屏幕坐标的强守卫见 chat_read_anchor_follow_test）。
      expect(
        pos.pixels,
        greaterThanOrEqualTo(readingPos - 0.5),
        reason: '流式中点击大纲进入阅读态，新 token 不得将视口拽回底部',
      );

      // 点击右下角回到底部按钮
      expect(find.text('回到底部'), findsOneWidget);
      await tester.tap(find.text('回到底部'));
      await tester.pumpAndSettle();

      // 验证恢复贴底
      expect(
        pos.pixels,
        lessThan(5.0),
        reason: '点击回底按钮后恢复平滑滚底跟随',
      );
    });
  });
}
