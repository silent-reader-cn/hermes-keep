import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('#41 聊天底部跟随手势状态机测试', () {
    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    ChatMessageListState stateOf(WidgetTester tester) {
      return tester.state<ChatMessageListState>(
        find.byType(ChatMessageList).first,
      );
    }

    List<Map<String, dynamic>> generateMessages(int count) {
      return List.generate(
        count,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '测试消息第 $i 轮：用于撑起滚动视图高度的长文本。' * 6,
          'message_id': 'm-$i',
        },
      );
    }

    testWidgets('1. 跟随中：向下拖动（=内容向下=朝顶部）取消跟随；向上拖动保持跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-gesture-1',
          'messages': generateMessages(30),
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-gesture-1')),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final state = stateOf(tester);

      // 初始收敛后处于跟随态
      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);

      // 向下拖动（手指从上往下滑 Offset(0, 200)，内容向下，朝历史方向）
      await tester.drag(scrollable, const Offset(0, 200));
      await tester.pumpAndSettle();

      // 验证取消跟随
      expect(state.userHasScrolled, isTrue, reason: '向下滑动离底后应取消跟随');
      expect(state.nearBottom, isFalse);

      // 重新跳回到底部恢复跟随以测试向上拖动
      await tester.tap(find.text('回到底部'));
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);

      // 跟随中向上拖动（手指从下往上滑 Offset(0, -50)，内容向上，朝底部方向）
      await tester.drag(scrollable, const Offset(0, -50));
      await tester.pumpAndSettle();

      // 验证仍然保持跟随
      expect(state.userHasScrolled, isFalse, reason: '跟随中向上拖动松手仍近底应保持跟随');
      expect(state.nearBottom, isTrue);
    });

    testWidgets('2. 不跟随中：向上拖动接近底部（<80px）恢复跟随；未接近则保持不跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-gesture-2',
          'messages': generateMessages(30),
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-gesture-2')),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final state = stateOf(tester);
      final pos = positionOf(tester);

      // 先向下滑动离开底部 400px 进入不跟随态
      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isTrue);
      expect(pos.pixels, greaterThan(150.0));

      // 不跟随中向上滑动一段距离（手指从下往上滑 Offset(0, -50)），但仍离底 > 100px
      await tester.drag(scrollable, const Offset(0, -50));
      await tester.pumpAndSettle();
      expect(
        pos.pixels,
        greaterThan(80.0),
        reason: '仍未达到贴底阈值',
      );
      expect(
        state.userHasScrolled,
        isTrue,
        reason: '未接近底部时向上滑动应保持不跟随',
      );

      // 向上滑动足够距离接近底部（< 80px）
      await tester.drag(scrollable, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(pos.pixels, lessThan(80.0));
      expect(
        state.userHasScrolled,
        isFalse,
        reason: '向上滑动进入 < 80px 范围后应恢复跟随',
      );
      expect(state.nearBottom, isTrue);
    });

    testWidgets('3. 轻点与微小位移（< 8px）：状态回到按压前，不改变跟随状态', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-gesture-3',
          'messages': generateMessages(30),
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-gesture-3')),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final state = stateOf(tester);

      // 1) 跟随态下轻点（tap）
      expect(state.userHasScrolled, isFalse);
      await tester.tap(scrollable);
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isFalse, reason: '跟随态轻点后应保持跟随');

      // 2) 跟随态下产生 < 8px 的微小拖动
      await tester.drag(scrollable, const Offset(0, 4));
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isFalse, reason: '微小位移（<8px）不触发离底取消');

      // 3) 离底不跟随状态下的轻点与微小位移
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isTrue);

      await tester.tap(scrollable);
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isTrue, reason: '离底不跟随态轻点后保持不跟随');

      await tester.drag(scrollable, const Offset(0, -4));
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isTrue, reason: '离底不跟随态微小位移保持不跟随');
    });

    testWidgets('4. 布局挤压/窗口 resize/新消息到达：绝不误取消跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      api.sessionResult = {
        'session': {
          'session_id': 's-gesture-4',
          'active_stream_id': 'stream-g4',
          'messages': generateMessages(20),
          'message_count': 20,
        },
      };

      var containerHeight = 600.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: SizedBox(
                    height: containerHeight,
                    child: const ChatMessageList(sessionId: 's-gesture-4'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final state = stateOf(tester);
      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);

      // 改变容器高度（模拟窗口 resize / 布局挤压）
      containerHeight = 400.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: SizedBox(
                    height: containerHeight,
                    child: const ChatMessageList(sessionId: 's-gesture-4'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.userHasScrolled, isFalse, reason: '容器高度变化不得误判为用户离底');

      // 注入新 token
      api.emit(TokenSseEvent('新消息流式内容 chunk ' * 10));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump();

      expect(state.userHasScrolled, isFalse, reason: '新消息到达自动跟随不取消');
    });

    testWidgets('5. 普通发送新消息进跟随；Steer 发送不进跟随且先前跟随则保持', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      api.sessionResult = {
        'session': {
          'session_id': 's-gesture-5',
          'active_stream_id': 'stream-g5',
          'messages': generateMessages(25),
          'message_count': 25,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-gesture-5')),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final state = stateOf(tester);
      final pos = positionOf(tester);

      // 1) 先离底 300px 进入阅读态（不跟随）
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isTrue);
      final readingPos = pos.pixels;

      // 在离底不跟随态下发出 steer 请求
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatMessageList)),
      );
      final controller = container.read(
        chatControllerProvider('s-gesture-5').notifier,
      );
      final steerSuccess = await controller.send(
        'Steer 调整指令',
        behavior: StreamingSendBehavior.steer,
      );
      expect(steerSuccess, isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 验证 steer 请求发出后不打开自动跟随，依然保持在离底阅读位
      expect(state.userHasScrolled, isTrue, reason: '离底时发送 steer 不得强制进跟随');
      expect((pos.pixels - readingPos).abs(), lessThan(5.0));

      // 2) 恢复跟随态后发出 steer 请求
      await tester.tap(find.text('回到底部'));
      await tester.pumpAndSettle();
      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);

      final steerSuccess2 = await controller.send(
        '第二条 Steer 调整指令',
        behavior: StreamingSendBehavior.steer,
      );
      expect(steerSuccess2, isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 验证先前跟随则继续保持跟随
      expect(state.userHasScrolled, isFalse, reason: '跟随中发送 steer 保持跟随');
    });

    testWidgets('6. 大纲跳转与高亮搜索定位为主动导航例外：离底即不跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-gesture-6',
          'messages': generateMessages(30),
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-gesture-6')),
        ),
      );

      await tester.pumpAndSettle();

      final state = stateOf(tester);
      expect(state.userHasScrolled, isFalse);

      // 大纲跳转到历史第 2 轮
      state.outlineJumpTo('m-2', 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 200));

      // 验证大纲跳转主动取消跟随
      expect(state.userHasScrolled, isTrue, reason: '大纲跳转为主动导航，必须取消跟随');
      expect(state.nearBottom, isFalse);
    });
  });
}
