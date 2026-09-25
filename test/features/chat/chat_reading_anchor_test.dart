import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('#14 阅读锚定测试', () {
    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    testWidgets('离底阅读时，流式 token 与 phase 变化绝不拉回底部（误拉底收敛）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = List.generate(
        50,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '历史消息 $i：这是一段测试段落内容用于撑起列表高度。这是一段测试段落内容用于撑起列表高度。',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-reading-anchor',
          'active_stream_id': 'stream-anchor',
          'messages': messages,
          'message_count': 50,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-reading-anchor'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);

      // 用户主动向上滚动到中间位置 (离底 > 120px)
      await tester.drag(scrollable, const Offset(0, 500));
      await tester.pumpAndSettle();

      final readingPixels = pos.pixels;
      expect(
        pos.maxScrollExtent - readingPixels,
        greaterThan(120),
        reason: '用户已上滑离底阅读',
      );

      // 1. 流式注入 token 增量
      for (var i = 0; i < 5; i++) {
        api.emit(TokenSseEvent('token $i token $i token $i '));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump();
      }

      // 验证离底阅读时，像素位置未被拉到最新底部
      expect(
        (pos.pixels - readingPixels).abs(),
        lessThan(10.0),
        reason: '流式 token 注入时不应将离底阅读的用户拉回底部',
      );
    });

    testWidgets('用户刚发送新消息（phase sending）后首帧保留滚底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：这是一段测试消息内容。这是一段测试消息内容。',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-user-send',
          'messages': messages,
          'message_count': 40,
        },
      };
      api.startChatResult = {
        'ok': true,
        'stream_id': 'stream-send',
      };
      api.statusResponse = const ChatStreamStatusResponse(active: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-user-send'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);

      // 用户上滑离底
      await tester.drag(scrollable, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(pos.pixels, greaterThan(120));

      api.statusResponse = const ChatStreamStatusResponse(active: true);

      // 用户发送新消息触发 phase -> sending
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatMessageList)),
      );
      unawaited(
        container
            .read(chatControllerProvider('s-user-send').notifier)
            .send('new message from user'),
      );

      await tester.pump();

      // 推进多帧让 200ms 滚底动画执行完成
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump();

      final endPos = positionOf(tester);
      expect(
        endPos.pixels <= 2.0,
        isTrue,
        reason: '用户发送新消息后应平滑滚动到底部展示新内容',
      );
    });

    testWidgets('流式中用户上滑暂停跟随，出现回底按钮，点击按钮恢复粘底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：这是一段测试消息内容。这是一段测试消息内容。',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-unpin',
          'active_stream_id': 'stream-unpin',
          'messages': messages,
          'message_count': 40,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-unpin'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);

      // 上滑 80px
      await tester.drag(scrollable, const Offset(0, 80));
      await tester.pumpAndSettle();

      final readingPixels = pos.pixels;
      expect(pos.maxScrollExtent - readingPixels, greaterThan(50));

      // 注入 token，因粘滞离底状态，不应被拽回底部
      api.emit(const TokenSseEvent('token append token append token append'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump();

      expect(
        (pos.pixels - readingPixels).abs(),
        lessThan(5.0),
        reason: '流式中上滑后新 token 不得将视口拽回底部',
      );

      // 悬浮回底按钮应出现
      final scrollToBottomFinder = find.byKey(
        const ValueKey('chat-scroll-to-bottom-button'),
      );
      expect(scrollToBottomFinder, findsOneWidget);

      // 点击悬浮按钮，应平滑回到底部并恢复跟随
      await tester.tap(scrollToBottomFinder);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump();

      expect(
        pos.pixels,
        closeTo(0.0, 1.0),
        reason: '点击回底按钮后应恢复贴底',
      );

      // 再次注入 token，恢复自动跟随
      api.emit(const TokenSseEvent('more tokens'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump();

      expect(
        pos.pixels,
        closeTo(0.0, 1.0),
        reason: '恢复跟随状态后新 token 应继续粘底',
      );
    });
  });
}
