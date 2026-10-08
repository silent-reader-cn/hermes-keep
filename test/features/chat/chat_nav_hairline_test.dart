import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/divider_tokens.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 主人 2026-10-08 报告的现象：**有聊天内容的会话与刚新建的会话，title header
/// 下沿的分割线深浅不一样 —— 向下一滚动就加深**。
///
/// 根因（SDK 源码 + 实测）：`CupertinoNavigationBar` 默认
/// `border: _kDefaultNavBarBorder`（`#4D000000`，`width: 0.0 // 0.0 means one
/// physical pixel`），且在 `CupertinoPageScaffold` 内会随内容滚动把这条黑 30% 线
/// 从透明淡入（`_scrollAnimationValue`，depth==0 的滚动通知驱动，阈值 10 逻辑
/// 像素）；新会话无可滚动内容 ⇒ 只剩自绘的 0.5px 发丝线 ⇒ 两条形态深浅不同。
///
/// 本测试钉住修复：导航栏显式 `border: null`，发丝线常驻且颜色取线族令牌，
/// **滚动前后必须同色**。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  List<Map<String, Object?>> messages(int count) => [
    for (var i = 0; i < count; i++)
      {
        'role': i.isEven ? 'user' : 'assistant',
        'content': '细分隔线回归 message $i ' * 4,
        'message_id': 'm$i',
        '_ts': i.toDouble(),
      },
  ];

  for (final brightness in Brightness.values) {
    testWidgets('聊天顶栏发丝线 $brightness：关掉 SDK 边框，滚动前后同色', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': 's-hairline',
            'messages': messages(30),
            'message_count': 30,
          },
        };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            theme: buildCupertinoTheme(brightness),
            home: const ChatPage(sessionId: 's-hairline'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<CupertinoNavigationBar>(
        find.byType(CupertinoNavigationBar),
      );
      expect(
        navBar.border,
        isNull,
        reason: 'SDK 默认边框（1 物理像素黑 30%）会随滚动淡入并与发丝线叠加'
            ' ⇒ 必须显式传 border: null',
      );

      // 取「高 0.5 逻辑像素」的那条线（避免与导航栏内部其它 ColoredBox 混淆）。
      Color hairlineColor() {
        final boxes = find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: find.byType(ColoredBox),
        );
        for (final element in boxes.evaluate()) {
          final size = (element.renderObject! as RenderBox).size;
          if (size.height == Dividers.hairlineWidth) {
            return (element.widget as ColoredBox).color;
          }
        }
        fail('未找到顶栏发丝线（高 ${Dividers.hairlineWidth} 的 ColoredBox）');
      }

      final context = tester.element(find.byType(ChatPage));
      final atTop = hairlineColor().toARGB32();
      expect(
        atTop,
        Dividers.structural(context).toARGB32(),
        reason: '发丝线颜色 = 线族结构线令牌（与侧栏低栏同色）',
      );

      final scrollable = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(
        position.maxScrollExtent,
        greaterThan(100),
        reason: '内容须真的可滚动，否则测不到 SDK 的滚动淡入',
      );

      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(10));
      expect(
        hairlineColor().toARGB32(),
        atTop,
        reason: '滚动后分割线不得变深（主人报告的现象）',
      );

      // 滚回底部同样不得变深。
      await tester.drag(scrollable, const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(hairlineColor().toARGB32(), atTop);
    });
  }
}
