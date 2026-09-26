import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';

import '../../helpers/fake_chat_api.dart';

/// 离底阅读时「下方新内容把历史顶上去」的回归守卫。
///
/// reverse 列表把新内容插在**物理 index 0**（`pixels ≈ 0` 那一端 = 视觉
/// 底部）：已有条目的 sliver 偏移整体被推大，而 `pixels` 一动不动。于是旧
/// 判据「pixels 稳定即视觉稳定」放过了真正的位移 —— 用户正在看的历史消息在
/// 屏幕上整体上移，即主人报告的「生成中的新内容把历史顶上去」。
///
/// 这组用例因此**断言屏幕坐标（条目 dy）而不是 pixels**：只钉 pixels 的旧
/// 用例在缺陷存在时照绿（见 chat_streaming_scroll_test 用例 2）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ScrollPosition positionOf(WidgetTester tester) {
    final finder = find
        .descendant(
          of: find.byType(ChatMessageList),
          matching: find.byType(Scrollable),
        )
        .first;
    return tester.state<ScrollableState>(finder).position;
  }

  /// 条目在视口内的顶边 dy；不在树中返回 null。
  double? dyOf(WidgetTester tester, String text) {
    final finder = find.textContaining(text);
    if (finder.evaluate().isEmpty) return null;
    return tester.getTopLeft(finder.first).dy;
  }

  Future<FakeChatApi> pumpStreamingChat(
    WidgetTester tester,
    String sessionId, {
    int messageCount = 40,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    final messages = List.generate(
      messageCount,
      (i) => {
        'role': i.isEven ? 'user' : 'assistant',
        'content': '历史消息 $i：这是一段测试长消息内容，用于占满视口产生足够滚动高度。',
        'message_id': 'm$i',
      },
    );
    api.sessionResult = {
      'session': {
        'session_id': sessionId,
        'active_stream_id': 'stream-$sessionId',
        'messages': messages,
        'message_count': messageCount,
      },
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: CupertinoApp(home: ChatPage(sessionId: sessionId)),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  /// 离底 300px（reverse：手指下拖 = pixels 增大 = 看历史）。
  Future<void> scrollAwayFromBottom(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await tester.pumpAndSettle();
  }

  Future<void> emitTokens(
    WidgetTester tester,
    FakeChatApi api,
    int count, {
    String prefix = '流式生成 token 行内容',
  }) async {
    for (var i = 0; i < count; i++) {
      api.emit(TokenSseEvent('$prefix $i\n'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('1. 离底阅读时流式新内容不再把历史顶上去（屏幕坐标不变）', (tester) async {
    final api = await pumpStreamingChat(tester, 's-anchor-drift-1');
    await scrollAwayFromBottom(tester);

    final before = positionOf(tester);
    expect(before.pixels, greaterThan(80), reason: '前置：应已离底');
    // ScrollPosition 是活对象：必须取标量快照，否则断言时读到的是"之后"的值。
    final beforePixels = before.pixels;

    final anchorDy = dyOf(tester, '历史消息 30：');
    expect(anchorDy, isNotNull, reason: '前置：锚点条目应在视口内');

    await emitTokens(tester, api, 10);

    final after = positionOf(tester);
    expect(
      dyOf(tester, '历史消息 30：'),
      closeTo(anchorDy!, 1.0),
      reason: '下方新内容不得把视口里的历史消息顶上去',
    );
    // 位置是靠增大 pixels 换来的（补偿方向：内容下端插入 ⇒ pixels 必须变大）
    expect(
      after.pixels,
      greaterThan(beforePixels + 1.0),
      reason: '补偿应体现为 pixels 增大，而非原地不动',
    );
    expect(
      after.pixels,
      lessThanOrEqualTo(after.maxScrollExtent + 0.5),
      reason: '补偿不得越界',
    );
    // 离底状态保持：仍在阅读态，回底入口在
    expect(
      find.byKey(const ValueKey('chat-scroll-to-bottom-button')),
      findsOneWidget,
    );
  });

  testWidgets('2. 长文本持续追加（大位移）时屏幕坐标仍稳定', (tester) async {
    final api = await pumpStreamingChat(tester, 's-anchor-drift-2');
    await scrollAwayFromBottom(tester);

    final anchorDy = dyOf(tester, '历史消息 30：');
    expect(anchorDy, isNotNull);

    // 每行更长、条数更多 ⇒ 内容增长远超早期版本
    await emitTokens(tester, api, 25, prefix: '这是一段明显更长的新增正文内容，用于制造较大的内容增长位移');

    expect(
      dyOf(tester, '历史消息 30：'),
      closeTo(anchorDy!, 1.0),
      reason: '大位移场景同样不得顶走历史',
    );
    expect(
      find.byKey(const ValueKey('chat-scroll-to-bottom-button')),
      findsOneWidget,
    );
  });

  testWidgets('3. 读历史期间视口内容连续（补偿不过冲、不留空白）', (tester) async {
    final api = await pumpStreamingChat(tester, 's-anchor-drift-3');
    await scrollAwayFromBottom(tester);

    final anchorDy = dyOf(tester, '历史消息 28：');
    expect(anchorDy, isNotNull);

    await emitTokens(tester, api, 12);

    // 过冲/欠冲都会让相邻条目间距失真：逐条核对相邻 dy 差与补偿前一致
    final dy27 = dyOf(tester, '历史消息 27：');
    final dy28 = dyOf(tester, '历史消息 28：');
    final dy29 = dyOf(tester, '历史消息 29：');
    expect(dy27, isNotNull);
    expect(dy28, isNotNull);
    expect(dy29, isNotNull);
    final double d27 = dy27!;
    final double d28 = dy28!;
    final double d29 = dy29!;
    expect(d29 - d28, closeTo(61.0, 1.0), reason: '相邻条目间距应保持 ~61px（无过冲压缩）');
    expect(d28 - d27, closeTo(61.0, 1.0), reason: '相邻条目间距应保持一致');
  });

  testWidgets('4. 补偿不吞掉流式正文：滚回底部能看到新生成内容', (tester) async {
    final api = await pumpStreamingChat(tester, 's-anchor-drift-4');
    await scrollAwayFromBottom(tester);

    await emitTokens(tester, api, 8);

    await tester.tap(
      find.byKey(const ValueKey('chat-scroll-to-bottom-button')),
    );
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    final settled = positionOf(tester);
    expect(settled.pixels, lessThan(2.0), reason: '回底按钮应把视口带回贴底');
    expect(
      find.byKey(const ValueKey('chat-scroll-to-bottom-button')),
      findsNothing,
    );
    expect(
      find.textContaining('流式生成 token 行内容'),
      findsWidgets,
      reason: '回底后应能看到新生成的正文（补偿不得吞内容）',
    );
  });

  testWidgets('5. 贴底跟随不回归：贴底时新内容照常被跟住', (tester) async {
    final api = await pumpStreamingChat(tester, 's-anchor-drift-5');

    final before = positionOf(tester);
    expect(before.pixels, lessThan(5.0), reason: '前置：初始应贴底');

    await emitTokens(tester, api, 10);

    final after = positionOf(tester);
    expect(after.pixels, lessThan(5.0), reason: '贴底时必须继续跟随最新内容');
    expect(
      find.byKey(const ValueKey('chat-scroll-to-bottom-button')),
      findsNothing,
    );
    expect(find.textContaining('流式生成 token 行内容'), findsWidgets);
  });

  testWidgets('6. 离底补偿后重新上滑仍自由（补偿不夺走手势控制权）', (tester) async {
    final api = await pumpStreamingChat(tester, 's-anchor-drift-6');
    await scrollAwayFromBottom(tester);

    await emitTokens(tester, api, 6);
    final afterCompensation = positionOf(tester).pixels;

    // 用户继续上滑看更早的历史
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pumpAndSettle();

    final afterDrag = positionOf(tester).pixels;
    expect(
      afterDrag,
      greaterThan(afterCompensation + 100),
      reason: '手势应完全生效（补偿不得把用户拽回）',
    );
  });

  testWidgets('7. 工具卡事件同样不顶走历史（含 6px 级微漂移）+ 补偿链不自激', (tester) async {
    final api = await pumpStreamingChat(tester, 's-anchor-drift-7');
    await scrollAwayFromBottom(tester);

    final anchorDy = dyOf(tester, '历史消息 30：');
    expect(anchorDy, isNotNull, reason: '前置：锚点条目应在视口内');

    // 6 次同工具 tool_start：经工具聚合合成一张组卡，插在最底端（物理 index 0）。
    for (var i = 0; i < 6; i++) {
      api.emit(
        ToolStartedSseEvent(
          ToolStreamEvent(
            eventType: 'tool_start',
            name: 'grep_code',
            stableId: 'call-$i',
            args: {'pattern': 'foo$i'},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump();
    }

    // running 态工具卡自带 CupertinoActivityIndicator（无限动画）⇒ pumpAndSettle
    // 永不收敛（首版探针即卡死在这里）。改用定量帧泵，并顺带把「补偿链自激」钉住：
    // 若 jumpTo → metrics → postFrame → jumpTo 形成自激，静默帧里 pixels 会持续变动。
    final quiet = <double>[];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 32));
      quiet.add(positionOf(tester).pixels);
    }
    expect(
      quiet.every((p) => (p - quiet.first).abs() < 0.5),
      isTrue,
      reason: '静默帧内视口不得持续位移（补偿链不得自激）',
    );

    expect(
      dyOf(tester, '历史消息 30：'),
      closeTo(anchorDy!, 1.0),
      reason: '新工具卡不得顶走正在阅读的历史',
    );

    // 前提校验（关键）：running 工具卡落在最底端，离底阅读时在 cacheExtent 之外，
    // 视口内查不到属正常 —— 若据此就下结论，会在「事件根本没落地」的空场景里假绿。
    // 故回底清点一次，确认工具卡确实建出来了。
    positionOf(tester).jumpTo(0);
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      find.byType(ToolCallGroupCard).evaluate().isNotEmpty ||
          find.byType(ToolCallCard).evaluate().isNotEmpty,
      isTrue,
      reason: '前提：工具卡应已渲染（否则本用例测的是空场景）',
    );
    expect(
      find.byType(CupertinoActivityIndicator),
      findsWidgets,
      reason: '前提：运行中指示器应在',
    );
    expect(
      find.textContaining('代码搜索'),
      findsWidgets,
      reason: '前提：工具名应经 localizeToolName 转译后出现在卡上',
    );
  });
}
