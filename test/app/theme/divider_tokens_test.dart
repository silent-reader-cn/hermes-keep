import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/divider_tokens.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';

/// 分割线语义分级（L1 结构线 / L2 容器描边 / L3 行间线）的唯一出口守卫。
///
/// 起案（主人 2026-10-08）：标题栏下沿那条线在「有内容的会话一滚动」时变深 ——
/// 根因是 Flutter SDK 的 `CupertinoNavigationBar` 默认边框（`#4D000000`，1 物理
/// 像素）随滚动淡入并与自绘发丝线叠加。本测试钉住三件事：
/// 1. 三级的取值：浅色 = 浅色面令牌，深色 = 系统 `separator`（不再有黑 30%）；
/// 2. 线宽统一 0.5 逻辑像素（SDK 默认的 `width: 0.0` = 1 物理像素，1x 屏上是
///    整像素实线，比线族其它线重一倍，故不采用）；
/// 3. 令牌是**唯一出口**：用户改页底色后结构线随之派生。
void main() {
  Future<void> withContext(
    WidgetTester tester,
    Brightness brightness,
    void Function(BuildContext context) body,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    body(captured);
  }

  tearDown(LightSurfaces.resetUserSurface);

  for (final brightness in Brightness.values) {
    testWidgets('三级线在 $brightness 下取线族令牌，线宽 0.5', (tester) async {
      await withContext(tester, brightness, (context) {
        final expectedL1 = brightness == Brightness.light
            ? LightSurfaces.divider
            : CupertinoColors.separator.resolveFrom(context);
        final expectedL2 = brightness == Brightness.light
            ? LightSurfaces.cardBorder
            : CupertinoColors.separator.resolveFrom(context);

        expect(Dividers.structural(context).toARGB32(), expectedL1.toARGB32());
        expect(
          Dividers.rowSeparator(context).toARGB32(),
          expectedL1.toARGB32(),
          reason: 'L3 行间线与 L1 同值同族（v3 拍板）',
        );
        expect(
          Dividers.containerOutline(context).toARGB32(),
          expectedL2.toARGB32(),
        );

        final border = Dividers.navBarBorder(context);
        expect(border.bottom.width, Dividers.hairlineWidth);
        expect(border.bottom.color.toARGB32(), expectedL1.toARGB32());
        // 起案根因：SDK 默认边框那条 1px 黑 30% 必须彻底退出线族。
        expect(border.bottom.color.toARGB32(), isNot(0x4D000000));
        expect(border.bottom.width, isNot(0.0));
      });
    });
  }

  testWidgets('用户改页底色后结构线随之派生（令牌是唯一出口）', (tester) async {
    const custom = Color(0xFFEDEDED);
    LightSurfaces.applyUserSurface(light: custom, dark: null);

    await withContext(tester, Brightness.light, (context) {
      expect(LightSurfaces.page.toARGB32(), custom.toARGB32());
      expect(
        Dividers.structural(context).toARGB32(),
        LightSurfaces.divider.toARGB32(),
        reason: '结构线必须跟随页底色派生，不得写死旧值',
      );
      expect(
        Dividers.navBarBorder(context).bottom.color.toARGB32(),
        LightSurfaces.divider.toARGB32(),
      );
    });
  });
}
