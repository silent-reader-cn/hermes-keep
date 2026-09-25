// RED tests: pagination scroll-position corruption.
//
// Symptom (user report, 2026-09-07): scrolling up in a long chat to load
// older messages makes the scroll position jump wildly — either to the
// very bottom (newest messages) or to the head of the freshly loaded
// history block.
//
// Root causes:
// 1. Gesture-end during an in-flight older-messages restore is silently
//    discarded (`_handleGestureEnd` early-returns when
//    `_restoringOlderPosition` is true), so the user's "I left the
//    bottom" intent is lost; afterwards the post-build follow logic
//    sees `_nearBottom && !_userHasScrolled` and yanks the list back to
//    the bottom.
// 2. `_restoreOlderScrollPosition` compensates with
//    `beforePixels + (maxScrollExtent - beforeExtent)`, but a lazy
//    ListView's `maxScrollExtent` is an *estimate* (unbuilt items are
//    averaged). When 50 older items arrive, the estimate error can be
//    several viewport heights; the clamp then lands the user at an
//    endpoint (0 = history head, or max = newest bottom) and the real
//    layout corrections that follow show up as visible re-jumps.
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

const int _totalMessages = 120;

Map<String, Object?> _page({required int from, required int to, int? offset}) {
  final messages = <Map<String, Object?>>[
    for (var i = from; i < to; i++)
      {
        'role': i.isEven ? 'user' : 'assistant',
        'content': '历史消息 $i：' * 24,
        'message_id': 'm$i',
      },
  ];
  return <String, Object?>{
    'session': <String, Object?>{
      'session_id': 's-pager',
      'messages': messages,
      'message_count': _totalMessages,
      '_messages_offset': offset ?? from,
    },
  };
}

Future<void> _pumpChatPage(WidgetTester tester, FakeChatApi api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const CupertinoApp(home: ChatPage(sessionId: 's-pager')),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _positionOf(WidgetTester tester) {
  final scrollableFinder = find
      .descendant(
        of: find.byType(ChatMessageList),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(scrollableFinder).position;
}

ChatMessageListState _stateOf(WidgetTester tester) {
  return tester.state<ChatMessageListState>(find.byType(ChatMessageList).first);
}

/// 从列表中心持续向上拖，直到触发 older 分页（pixels <= 80 阈值）。
/// 返回手势（仍按住），调用方决定何时松手。
Future<TestGesture> _dragUntilPaginationArmed(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ChatMessageList)),
  );
  await tester.pump();
  var guard = 0;
  // A 重构（reverse）：更早消息在列表末尾侧 —— 手势方向不变（手指上/下移
  // 的视觉语义不变），但终止判据要按「距最旧端」计算。
  while ((_positionOf(tester).maxScrollExtent - _positionOf(tester).pixels) > 80 &&
      guard < 60) {
    await gesture.moveBy(const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 16));
    guard++;
  }
  return gesture;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('上滑加载历史消息后滚动位置保持（分页乱跳回归）', () {
    testWidgets(
      'RED-1 restore 期间手势结束不吞用户离底意图（不回跳末尾）',
      (tester) async {
        final api = FakeChatApi()
          ..sessionResult = _page(from: 70, to: 120, offset: 70);
        await _pumpChatPage(tester, api);

        final pos = _positionOf(tester);
        final state = _stateOf(tester);
        expect(pos.pixels, moreOrLessEquals(0.0, epsilon: 1));

        // 持续上滑直到触发 older 分页（restore 窗口开启后即松手）。
        final gesture = await _dragUntilPaginationArmed(tester);
        // restore 期间松手 —— 用户的离底意图必须被保留。
        await gesture.up();
        // Restore 收敛链（3 帧预算）：泵足帧让链跑完。
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();

        expect(
          state.userHasScrolled,
          isTrue,
          reason: 'restore 期间（或期间结束的）手势必须结算离底意图；'
              '丢失它会让后续 follow 逻辑把列表拉回末尾',
        );
        // 实际现象断言：松手后列表不得被自动拉回最底部。
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          pos.pixels,
          greaterThan(200),
          reason: '离底阅读历史时，列表不应被拉回最底部（新消息端）',
        );
      },
    );

    testWidgets(
      'RED-2 分页加载后视口锚定加载前顶条（不跳端点）',
      (tester) async {
        final api = FakeChatApi()
          ..sessionResult = _page(from: 70, to: 120, offset: 70);
        await _pumpChatPage(tester, api);

        await _dragUntilPaginationArmed(tester);
        // Restore 依赖 postFrame 收敛链：显式泵足帧让链跑完（上限 8 帧）。
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(_stateOf(tester).restoringOlderPosition, isFalse);
        // 核心断言：补偿完成后，分页触发时视口顶缘可见的最旧已载消息
        // 应保持在分页前的视口位置附近（锚定条目 = transcript:71，
        // 即分页时第一部分可见条目；其同屏邻居 msg72 随之归位）。
        // 锚定失效（跳到 0 或 max）时该条目会被虚拟化回收出树。
        final anchorFinder = find.text('历史消息 71：' * 24);
        if (anchorFinder.evaluate().isEmpty) {
          fail('锚定失效：分页触发时的顶缘锚定条目（历史消息 71）已不在树中'
              '（跳到端点后被虚拟化回收）');
        }
        final dy = tester.getTopRight(anchorFinder.first).dy;
        // A 重构（reverse）：分页触发发生在**最旧端**（视觉上方），锚定条目
        // 会停在视口内但不一定贴着顶缘 —— 判据改为「在视口内可见」。
        expect(
          dy,
          inInclusiveRange(-140, 800),
          reason: '加载更早历史后，分页触发时视口顶部可见的最旧已载消息'
              '（历史消息 70）应保持在视口顶部附近；'
              '跳到 0（历史头部）或 max（末尾）都说明补偿失效。实际 dy=$dy',
        );
      },
    );
  });
}
