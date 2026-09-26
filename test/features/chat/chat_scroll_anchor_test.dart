import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

/// 进入长会话时初始滚动位置必须收敛到底部（最新消息）。
///
/// 回归守卫：lazy ListView 首帧 maxScrollExtent 为估算值，单次 jumpTo
/// 会停在随机中间位置；现改为逐帧复核收敛到真实底部。
void main() {
  Future<void> pumpLongChat(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeChatApi();
    final messages = List.generate(
      60,
      (i) => {
        'role': i.isEven ? 'user' : 'assistant',
        'content': '第 $i 条消息：${'这是一段较长的消息内容用于撑高消息气泡。' * 3}',
        'message_id': 'm$i',
      },
    );
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'title': '长会话',
        'messages': messages,
        'message_count': 60,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  ScrollPosition positionOf(WidgetTester tester) {
    final scrollableFinder = find
        .descendant(
          of: find.byType(ChatMessageList),
          matching: find.byType(Scrollable),
        )
        .first;
    return tester.state<ScrollableState>(scrollableFinder).position;
  }

  testWidgets('窄屏：进入 60 条长会话后停在底部', (tester) async {
    await pumpLongChat(tester, size: const Size(390, 844));
    // 收敛循环逐帧复核，settle 到稳定。
    await tester.pumpAndSettle();

    final position = positionOf(tester);
    expect(
      position.pixels,
      closeTo(0.0, 1.0),
      reason: '初始定位应收敛到真实底部（max=${position.maxScrollExtent}',
    );
  });

  testWidgets('宽屏：进入 60 条长会话后停在底部', (tester) async {
    await pumpLongChat(tester, size: const Size(1280, 800));
    await tester.pumpAndSettle();

    final position = positionOf(tester);
    expect(
      position.pixels,
      closeTo(0.0, 1.0),
      reason: '初始定位应收敛到真实底部（max=${position.maxScrollExtent}',
    );
  });

  testWidgets('初始定位期间流式 token 不触发 animateTo（R2 竞态回归）', (tester) async {
    // 进入一个「已在流式」的超长会话，初始定位收敛大量帧；期间持续注入
    // token（trigger++/phase 事件路径）。修复前 _scrollToBottom 会在定位
    // 期间启动 200ms animateTo，与 jumpTo 收敛循环竞争并在估算 extent 上
    // 越界 → 「撞击反弹」；修复后定位期间禁用动画，由收敛循环独占。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    // 高低混合消息：估算 extent 与真实 extent 偏差大 → 收敛循环多帧在途，
    // 确保 token reveal 落在初始定位窗口内（竞态可观测）。
    final messages = List.generate(
      800,
      (i) => {
        'role': i.isEven ? 'user' : 'assistant',
        'content': i % 11 == 0 ? '消息 $i：${'超长文本用于制造高度偏差。' * 24}' : '消息 $i：短',
        'message_id': 'm$i',
      },
    );
    api.sessionResult = {
      'session': {
        'session_id': 's-live',
        'title': '长会话',
        'active_stream_id': 'stream-live',
        'messages': messages,
        'message_count': 800,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-live')),
      ),
    );

    // 从列表挂载起监听滚动活动：任何 DrivenScrollActivity（animateTo）出现
    // 即记数。修复前恢复连接（phase→streaming）与首个 token reveal
    // （trigger++）都会在初始定位期间启动 200ms animateTo；
    // 修复后定位在途期间完全禁用动画，由 jumpTo 收敛循环独占。
    var drivenStarts = 0;
    final watched = positionOf(tester);
    void onPositionChanged() {
      if (watched.activity is DrivenScrollActivity) drivenStarts++;
    }

    watched.addListener(onPositionChanged);

    await tester.pump(); // transcript 加载 + 相位变化（恢复期）
    await tester.pump(const Duration(milliseconds: 30)); // 状态检查 + 恢复连接
    expect(api.startStreamCalls, 1);
    expect(
      drivenStarts,
      0,
      reason: '恢复连接进入 streaming 时不得触发 animateTo（R2 相位路径）',
    );

    // token 注入：16ms 合并 + 48ms reveal → trigger++ → _scrollTriggerSub。
    api.emit(const TokenSseEvent('x '));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 48));
    await tester.pump(); // 供动画首 tick 落地（若 gate 失效，此帧必被记数）
    expect(
      drivenStarts,
      0,
      reason: '初始定位期间 trigger++ 不得触发 animateTo（R2 滚动触发路径）',
    );
    watched.removeListener(onPositionChanged);

    // 继续注入 token：任何帧都不得越界（overshoot 被 clamp 拉回 = 反弹观感）。
    for (var i = 0; i < 4; i++) {
      api.emit(TokenSseEvent('y$i '));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      final p = positionOf(tester);
      expect(
        p.pixels >= -0.5 && p.pixels <= p.maxScrollExtent + 0.5,
        isTrue,
        reason: '初始定位期间不得越界/反弹',
      );
    }

    // 收敛检查：活跃看门狗 + 活动流下避免 pumpAndSettle，手动推进若干帧。
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final settled = positionOf(tester);
    expect(
      settled.pixels,
      closeTo(0.0, 1.0),
      reason: '定位与流式跟随最终应收敛到底部',
    );
  });
}
