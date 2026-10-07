import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/message_attachment.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';
import 'package:hermes_ui/features/chat/widgets/selected_context_card.dart';

/// 电脑端双栏气泡溢出回归：气泡 maxWidth 必须基于「实际槽位宽度」而非
/// 全窗口 MediaQuery 宽（双栏下 chat 区 = 窗口宽 − 320 侧栏），
/// 否则 0.78 比例会顶出屏幕右侧（RenderFlex overflow）。
///
/// 复现条件（与生产同构）：窗口 1280 宽，Row = 320 侧栏 + Expanded chat 区
/// （960）。旧实现 bubble max = 0.78×1280 = 998 > 960 → overflow；修复后
/// LayoutBuilder 取 Expanded 实际宽 960 → 0.78×960 = 749 → 正常。
void main() {
  Future<void> pumpInSlot(
    WidgetTester tester, {
    required ChatMessage message,
    double windowWidth = 1280,
    bool withSidebar = true,
  }) async {
    // 真实视口与 MediaQuery 一致，且高度给足（长文只测横向约束）。
    tester.view.physicalSize = Size(windowWidth, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final Widget chatArea = ChatMessageBubble(message: message);
    await tester.pumpWidget(
      // 用户气泡附件区含 Consumer（图片瓦片走 mediaFileProvider），
      // 生产环境始终有 ProviderScope —— 测试工装补齐同一前提。
      ProviderScope(
        child: MediaQuery(
        data: MediaQueryData(size: Size(windowWidth, 800)),
        child: CupertinoTheme(
          data: const CupertinoThemeData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: withSidebar
                  ? [
                      const SizedBox(width: 320),
                      const ColoredBox(color: CupertinoColors.white),
                      Expanded(child: chatArea),
                    ]
                  : [Expanded(child: chatArea)],
            ),
          ),
        ),
      ),
      ),
    );
  }

  double bubbleWidth(WidgetTester tester) => tester
      .renderObject<RenderBox>(
        find.byKey(const ValueKey('chat-message-bubble')),
      )
      .size
      .width;

  testWidgets('双栏窄槽位：用户长消息气泡不超出可用宽度（无 overflow）', (tester) async {
    final longText = List.filled(60, '这是一段很长的用户输入内容，用于模拟真实超长消息。').join();
    await pumpInSlot(
      tester,
      message: ChatMessage(role: 'user', content: longText),
    );

    // 修复前：bubble maxWidth = 0.78×1280 = 998 > 960 → RenderFlex overflow
    expect(tester.takeException(), isNull);
    // 修复后 ≈ 0.78×960 = 748.8
    expect(bubbleWidth(tester), lessThanOrEqualTo(960));
  });

  testWidgets('双栏窄槽位：助手长 Markdown（含超长 URL 与代码块）不溢出', (tester) async {
    final longUrl = 'https://example.com/${'x' * 120}';
    final content =
        '这是一段助手回复。\n\n这是一个很长的链接：$longUrl\n\n'
        '```\n${'y' * 200}\n```\n\n- 列表项';
    await pumpInSlot(
      tester,
      message: ChatMessage(role: 'assistant', content: content),
    );

    expect(tester.takeException(), isNull);
    // 修复后 ≈ 0.78×960 = 748.8
    expect(bubbleWidth(tester), lessThanOrEqualTo(960));
  });

  testWidgets('单栈全宽（手机/窗口无侧栏）行为不变：气泡仍受 78% 上限约束', (tester) async {
    await pumpInSlot(
      tester,
      message: const ChatMessage(role: 'user', content: '手机端单栈消息'),
      windowWidth: 390,
      withSidebar: false,
    );
    expect(tester.takeException(), isNull);
    // 390 × 0.78 = 304.2，气泡宽 ≤ 305
    expect(bubbleWidth(tester), lessThanOrEqualTo(390 * 0.78 + 1));
  });

  group('#34 用户气泡宽度自适应 min(内容宽, 0.78 封顶)', () {
    // 槽位 960（1280 窗口 − 320 侧栏），0.78 封顶 = 748.8
    const slot = 960.0;
    const maxBubble = slot * 0.78;

    testWidgets('单字符短消息「好」：气泡收窄贴近字宽 + padding，且贴右缘', (tester) async {
      await pumpInSlot(
        tester,
        message: const ChatMessage(role: 'user', content: '好'),
      );
      expect(tester.takeException(), isNull);
      // 修复前 stretch 把 Text 撑满 ≈ 748.8；修复后「好」15pt 字宽 ≈ 15px
      // + 水平 padding 24 ≈ 40px，明显小于 0.78 槽宽
      final w = bubbleWidth(tester);
      expect(w, lessThan(maxBubble / 2));
      expect(w, greaterThan(20));
      // 右对齐语义保持：气泡右缘 = 槽位右缘 − 12 外 padding（窗口 1280）
      final right = tester
          .getTopRight(find.byKey(const ValueKey('chat-message-bubble')))
          .dx;
      expect(right, closeTo(1280 - 12, 0.5));
    });

    testWidgets('长文本仍封顶 ≈ 0.78 槽宽（不溢出、不破版）', (tester) async {
      final longText = List.filled(60, '这是一段很长的用户输入内容，用于模拟真实超长消息。').join();
      await pumpInSlot(
        tester,
        message: ChatMessage(role: 'user', content: longText),
      );
      expect(tester.takeException(), isNull);
      expect(bubbleWidth(tester), closeTo(maxBubble, 1));
    });

    testWidgets('含选中上下文卡片：块级内容态保持 stretch，气泡仍撑满 0.78', (tester) async {
      const raw =
          '好\n\n'
          '**Context 1:**\n'
          '<!-- hermes-selected-context -->\n'
          '> hello';
      await pumpInSlot(
        tester,
        message: const ChatMessage(role: 'user', content: raw),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SelectedContextCardGroup), findsOneWidget);
      expect(bubbleWidth(tester), closeTo(maxBubble, 1));
    });

    testWidgets('含附件芯片：块级内容态保持 stretch，气泡仍撑满 0.78', (tester) async {
      const msg = ChatMessage(
        role: 'user',
        content: '看这张图',
        attachments: [MessageAttachment(name: 'photo.png', path: 'photo.png')],
      );
      await pumpInSlot(tester, message: msg);
      expect(tester.takeException(), isNull);
      expect(bubbleWidth(tester), closeTo(maxBubble, 1));
    });
  });
}
