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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('流式聊天向上回看与滚底控制测试（todo.md 规格）', () {
    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    testWidgets('1. 贴底时流式 token 自动跟随滚底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '历史消息 $i：这是一段测试长消息内容，用于占满视口产生足够滚动高度。这是一段测试长消息内容。',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-streaming-follow',
          'active_stream_id': 'stream-follow',
          'messages': messages,
          'message_count': 40,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-streaming-follow'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final pos = positionOf(tester);
      final initialPixels = pos.pixels;

      // 模拟流式推送 5 个 token
      for (var i = 0; i < 5; i++) {
        api.emit(TokenSseEvent('新增 token 行内容 $i\n'));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump();
      }

      await tester.pumpAndSettle();
      final afterPos = positionOf(tester);

      // A 重构（reverse）：新内容插在 index 0 侧（底部），贴底时 pixels 天然
      // 保持 0 —— 不再需要「随内容生长自动向下滚动」的像素位移。
      // （原 greaterThan(initialPixels) 断言属于正向实现的口径。）
      expect(initialPixels, lessThan(5.0));
      expect(afterPos.pixels, lessThan(5.0));
      // 贴底时不显示悬浮回底按钮
      expect(find.byKey(const ValueKey('chat-scroll-to-bottom-button')), findsNothing);
    });

    testWidgets('2. 用户上滑后暂停跟随，显示悬浮回底按钮，新 token 不拉回底部', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '历史消息 $i：这是一段测试长消息内容，用于占满视口产生足够滚动高度。这是一段测试长消息内容。',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-unpin-test',
          'active_stream_id': 'stream-unpin',
          'messages': messages,
          'message_count': 40,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-unpin-test'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;

      // 用户主动上滑 300px
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      final pos = positionOf(tester);
      final readingPixels = pos.pixels;
      expect(pos.pixels, greaterThan(80));

      // 应出现悬浮回底按钮
      final buttonFinder = find.byKey(const ValueKey('chat-scroll-to-bottom-button'));
      expect(buttonFinder, findsOneWidget);
      expect(find.text('回到底部'), findsOneWidget);

      // 流式推送 token
      for (var i = 0; i < 8; i++) {
        api.emit(TokenSseEvent('流式生成 token $i\n'));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump();
      }

      await tester.pumpAndSettle();
      final posAfterTokens = positionOf(tester);

      // 视口绝不得被拽回底部
      expect(
        (posAfterTokens.pixels - readingPixels).abs(),
        lessThan(5.0),
        reason: '用户上滑离底后，流式 token 不得拉扯视口',
      );
      expect(buttonFinder, findsOneWidget);
    });

    testWidgets('3. 离底期间支持点击悬浮按钮平滑回底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：这是一段测试长消息内容，用于占满视口产生足够滚动高度。这是一段测试长消息内容。',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-click-bottom',
          'messages': messages,
          'message_count': 40,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-click-bottom'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;

      // 用户上滑
      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const ValueKey('chat-scroll-to-bottom-button'));
      expect(buttonFinder, findsOneWidget);
      expect(find.text('回到底部'), findsOneWidget);

      // 点击回底按钮
      await tester.tap(buttonFinder);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      final endPos = positionOf(tester);
      expect(endPos.pixels, lessThan(2.0));
      expect(find.byKey(const ValueKey('chat-scroll-to-bottom-button')), findsNothing);
    });

    testWidgets('4. 用户手动下滑至距离底部 < 80px 时自动恢复粘底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '历史消息 $i：这是一段测试长消息内容，用于占满视口产生足够滚动高度。这是一段测试长消息内容。',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-scroll-back',
          'messages': messages,
          'message_count': 40,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-scroll-back'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;

      // 向上滑动 300px
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-scroll-to-bottom-button')), findsOneWidget);

      // 向下滑回到底部附近（-300px）
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();

      // 按钮消失，恢复粘底状态
      expect(find.byKey(const ValueKey('chat-scroll-to-bottom-button')), findsNothing);
    });

    testWidgets('5. 用户发送新消息后立即打破离底状态并平滑滚底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：这是一段测试长消息内容，用于占满视口产生足够滚动高度。这是一段测试长消息内容。',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-send-unpin',
          'messages': messages,
          'message_count': 40,
        },
      };
      api.startChatResult = {
        'ok': true,
        'stream_id': 'stream-send-unpin',
      };
      api.statusResponse = const ChatStreamStatusResponse(active: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-send-unpin'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;

      // 用户上滑离底 600px
      await tester.drag(scrollable, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-scroll-to-bottom-button')), findsOneWidget);

      api.statusResponse = const ChatStreamStatusResponse(active: true);

      // 发送新消息
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatMessageList)),
      );
      unawaited(
        container
            .read(chatControllerProvider('s-send-unpin').notifier)
            .send('用户新发送的内容'),
      );

      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump();

      final endPos = positionOf(tester);
      expect(
        endPos.pixels <= 2.0,
        isTrue,
        reason: '用户发送新消息后应立即平滑滚底并展示新消息',
      );
      expect(find.byKey(const ValueKey('chat-scroll-to-bottom-button')), findsNothing);
    });
  });
}
