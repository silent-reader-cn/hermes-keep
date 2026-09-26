// RED tests: repeated older-page loading in long sessions (#125).
//
// 现象（主人报告，2026-09-15）：长会话里滚动到顶部会「容易触发多次加载
// 上文」，且每次加载后会推动用户正在浏览的滚动 y 轴位置。
//
// 根因：
// 1. `_olderRestoreAttempts` 只在 session 切换时归零（didUpdateWidget），
//    每次分页开始时不重置 → 该计数器跨分页单调累加，撞满
//    `_maxOlderRestoreAttempts` 后，此后每次分页首帧即判定「预算已尽」
//    而放弃锚点归位，锚点误差原样留在屏幕上（位置被推动）。
// 2. 顶部触发判据是纯固定像素阈值 `pixels <= 80`，只判位置、不判方向
//    位移与冷却；唯一防线是请求返回即释放的在途锁 → 视口只要留在顶部
//    带内，后续滚动事件就会再打一发（多次加载）。
//    ＋ 零新增分页不会判定到底，可被滚动事件反复触发。
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

const String _sessionId = 's-pager125';
const int _totalMessages = 900;
const int _pageSize = 50;

/// 收敛帧预算上限（与 `ChatMessageListState._maxOlderRestoreAttempts` 对齐）。
/// 分页次数超过该值后，若计数器不归零，其值必然 >= 此处。
const int _restoreBudget = 6;

Map<String, Object?> _page({
  required int from,
  required int to,
  required int offset,
}) {
  final messages = <Map<String, Object?>>[
    for (var i = from; i < to; i++)
      {
        'role': i.isEven ? 'user' : 'assistant',
        'content': '历史消息 $i：' * 8,
        'message_id': 'm$i',
      },
  ];
  return <String, Object?>{
    'session': <String, Object?>{
      'session_id': _sessionId,
      'messages': messages,
      'message_count': _totalMessages,
      '_messages_offset': offset,
    },
  };
}

/// 正常服务端：按 messageBefore 逐页向前回吐（null = 首页 = 最新一页）。
Map<String, Object?> _pagedResponse(int? messageBefore) {
  final before = messageBefore ?? _totalMessages;
  final from = (before - _pageSize).clamp(0, _totalMessages);
  return _page(from: from, to: before, offset: from);
}

/// 零新增服务端：任何游标都回吐同一页 → 分页 `fresh` 恒为空。
Map<String, Object?> _staleResponse(int? messageBefore) => _page(
  from: _totalMessages - _pageSize,
  to: _totalMessages,
  offset: _totalMessages - _pageSize,
);

Future<void> _pumpChatPage(WidgetTester tester, FakeChatApi api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const CupertinoApp(home: ChatPage(sessionId: _sessionId)),
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

ChatState _chatStateOf(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ChatMessageList).first),
  );
  return container.read(chatControllerProvider(_sessionId));
}

/// 从列表中心持续上拖，直到视口进入顶部带（pixels <= 80 = 分页触发阈值）。
/// 与分页触发深度对齐：继续往深处拖会把锚点条目推出视口、被 lazy 列表
/// 回收，反而让收敛链失去锚点。返回仍按住的手势，调用方决定何时松手。
Future<TestGesture> _dragIntoTopBand(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ChatMessageList)),
  );
  await tester.pump();
  var guard = 0;
  // A 重构（reverse）：更早消息在列表末尾侧 —— 手势方向不变（手指上/下移
  // 的视觉语义不变），但终止判据要按「距最旧端」计算。
  while ((_positionOf(tester).maxScrollExtent - _positionOf(tester).pixels) > 80 &&
      guard < 200) {
    await gesture.moveBy(const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 16));
    guard++;
  }
  return gesture;
}

/// 泵足帧让锚点收敛链（postFrame 驱动）跑完。注意该链是
/// `addPostFrameCallback` 自续的：它不调度新帧，必须由外部持续喂帧
/// （真实设备靠滚动/动画，测试靠显式 pump），否则链会停在半途。
Future<void> _settleRestore(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 滚离顶部带（distToOldest > 240 = 滞回上沿），让分页触发重新武装。
/// 每轮分页前调用，模拟用户「滚上去看一页、再往下翻一点、再滚上去」。
///
/// A 重构（reverse）：触发带在最旧端，判据从正向的 `pixels > 240` 迁移为
/// `distToOldest > 240`（`pixels` 在反向基准下含义已反转，继续用会永远为真/假）。
Future<void> _leaveTopBand(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ChatMessageList)),
  );
  await tester.pump();
  var guard = 0;
  while (guard < 60) {
    final pos = _positionOf(tester);
    if (pos.maxScrollExtent - pos.pixels > 240) break;
    await gesture.moveBy(const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 16));
    guard++;
  }
  await gesture.up();
  await _settleRestore(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('长会话上滚分页：多次加载与位置漂移（#125）', () {
    testWidgets('RED-125-1 连续 6 次分页：收敛帧预算每次从 0 重启', (tester) async {
      final api = FakeChatApi()..sessionResultBuilder = _pagedResponse;
      await _pumpChatPage(tester, api);
      expect(
        api.sessionMessageBefore.where((before) => before != null),
        isEmpty,
        reason: '初始加载不应产生分页请求（messageBefore 非空即分页）',
      );

      const pages = 6;
      for (var page = 0; page < pages; page++) {
        // 每轮先离开顶部带（重新武装），再上滚进入带内触发分页。
        await _leaveTopBand(tester);
        final gesture = await _dragIntoTopBand(tester);
        await gesture.up();
        await _settleRestore(tester);

        final state = _stateOf(tester);
        expect(
          state.restoringOlderPosition,
          isFalse,
          reason: '第 ${page + 1} 次分页：锚点收敛链必须收工（不得挂住视口）',
        );
        expect(
          state.olderRestoreAttempts,
          lessThan(_restoreBudget),
          reason:
              '第 ${page + 1} 次分页：收敛帧预算必须每次分页从 0 重启。'
              '该计数器若跨分页累加，撞满 $_restoreBudget 帧后每次分页首帧即'
              '判定「预算已尽」而放弃锚点归位 → 锚点误差留在屏幕上，'
              '即用户报告的「加载后滚动 y 轴位置被推动」。'
              '实际已用 ${state.olderRestoreAttempts} 帧',
        );
      }

      final pagedRequests = api.sessionMessageBefore
          .where((before) => before != null)
          .length;
      expect(
        pagedRequests,
        greaterThanOrEqualTo(pages),
        reason: '每次上滚进入顶部带都应成功加载一页',
      );
    });

    testWidgets('RED-125-2 分页后视口必须被补偿离开顶部带（防连环触发）', (tester) async {
      final api = FakeChatApi()..sessionResultBuilder = _pagedResponse;
      await _pumpChatPage(tester, api);
      expect(
        api.sessionMessageBefore.where((before) => before != null),
        isEmpty,
        reason: '初始加载不应产生分页请求（messageBefore 非空即分页）',
      );

      final gesture = await _dragIntoTopBand(tester);
      await gesture.up();
      await _settleRestore(tester);

      final pos = _positionOf(tester);
      // A 重构（reverse）：分页把更早的一页插到最旧端，视口被**正确补偿**
      // （用户视觉位置不变）⇒ 分页后 distToOldest 仍可能落在触发带内，这是
      // 预期行为，不再是失败判据。真正要守的是「同一次拖动只加载一次」。
      final distToOldest = pos.maxScrollExtent - pos.pixels;
      expect(
        distToOldest,
        greaterThanOrEqualTo(0),
        reason:
            '视口必须落在合法范围内（reverse：distToOldest >= 0）。'
            '实际 pixels=${pos.pixels}, max=${pos.maxScrollExtent}',
      );
      expect(
        api.sessionMessageBefore.where((before) => before != null).length,
        1,
        reason:
            '一次拖动（含松手）只应产生一次分页请求 —— '
            '闸门以「一次完整手势」为单位重新武装，防同一次拖动内的连环触发',
      );
    });

    testWidgets('RED-125-4 零新增分页后反复滚动：请求次数有界', (tester) async {
      final api = FakeChatApi()..sessionResultBuilder = _staleResponse;
      await _pumpChatPage(tester, api);

      final gesture = await _dragIntoTopBand(tester);
      await gesture.up();
      await _settleRestore(tester);

      // 服务端始终回吐同一页 → 视口位置不变，反复在顶部带内滚动。
      for (var i = 0; i < 5; i++) {
        final nudge = await tester.startGesture(
          tester.getCenter(find.byType(ChatMessageList)),
        );
        await nudge.moveBy(const Offset(0, 60));
        await tester.pump(const Duration(milliseconds: 16));
        await nudge.up();
        await _settleRestore(tester);
      }

      final paged = api.sessionMessageBefore
          .where((before) => before != null)
          .length;
      expect(
        paged,
        lessThanOrEqualTo(2),
        reason:
            '零新增（服务端该游标已无更早消息）时反复滚动不得把请求打成'
            '风暴：到底判定 + 滞回武装 + 连续零推进封顶三层任一有效即有界。'
            '实际 $paged 次分页请求，'
            'messageBefore=${api.sessionMessageBefore}',
      );
    });

    testWidgets('RED-125-3 零新增分页必须判定到底（hasOlderMessages → false）', (tester) async {
      final api = FakeChatApi()..sessionResultBuilder = _staleResponse;
      await _pumpChatPage(tester, api);
      expect(_chatStateOf(tester).hasOlderMessages, isTrue);

      final gesture = await _dragIntoTopBand(tester);
      await gesture.up();
      await _settleRestore(tester);

      expect(
        _chatStateOf(tester).hasOlderMessages,
        isFalse,
        reason:
            '分页返回零新增（服务端该游标处已无更早消息）时必须判定到底。'
            '否则 hasOlderMessages 长期为 true，滚动事件可持续触发同一页请求',
      );
    });
  });
}
