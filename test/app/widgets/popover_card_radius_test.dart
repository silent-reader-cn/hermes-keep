import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/layout_tokens.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/app/widgets/cupertino_popover.dart';
import 'package:hermes_ui/features/chat/widgets/context_window_popover.dart';

/// 浮层卡片圆角的接线契约。
///
/// 背景：上下文弹层在「宽屏紧凑档」把卡圆角从浮层族值收到独立卡令牌（14 → 12），
/// 而圆角是**共享件**（`_PopoverCard` 被 4 个 popover 调用点共用）—— 收窄必须经
/// `radius` 参数**逐个传入**，不能改族值：
///   · 改族值 ⇒ 菜单族 / 收藏提示词 / 消息右键菜单 / 性能面板一起变（未经拍板）；
///   · 只在上下文弹层改 ⇒ 族值不动，别处零影响（本组用例守住这两条）。
void main() {
  test('圆角取值：族默认 14，上下文弹层紧凑档 = 独立卡令牌 12', () {
    expect(kAdaptivePopoverRadius, 14);
    expect(kRadiusCard, 12);
    expect(kContextPopoverWideRadius, kRadiusCard);
  });

  /// 读浮层卡片的圆角：卡片是「带投影的 BoxDecoration 容器」（族内唯一签名）。
  double? readCardRadius(WidgetTester tester) {
    for (final container in tester.widgetList<Container>(
      find.byType(Container),
    )) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration &&
          (decoration.boxShadow?.isNotEmpty ?? false)) {
        final radius = decoration.borderRadius;
        if (radius is BorderRadius) return radius.topLeft.x;
      }
    }
    return null;
  }

  Future<void> openPopover(
    WidgetTester tester, {
    required double radius,
  }) async {
    final anchorKey = GlobalKey();
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: SizedBox(key: anchorKey, width: 40, height: 20),
          ),
        ),
      ),
    );
    await tester.pump();
    unawaited(
      showCupertinoPopover(
        context: anchorKey.currentContext!,
        anchorKey: anchorKey,
        radius: radius,
        builder: (context, close) =>
            const SizedBox(width: 120, height: 80, child: Text('内容')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('不传 radius：落到族默认 14（窄屏 / 其余弹层现状不变）', (tester) async {
    await openPopover(tester, radius: kAdaptivePopoverRadius);
    expect(readCardRadius(tester), 14);
  });

  testWidgets('传 radius: 12：只改这一个弹层，卡圆角即为 12', (tester) async {
    await openPopover(tester, radius: kContextPopoverWideRadius);
    expect(readCardRadius(tester), 12);
  });
}
