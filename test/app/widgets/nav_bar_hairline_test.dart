import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/divider_tokens.dart';
import 'package:hermes_ui/app/widgets/adaptive_sliver_navigation_bar.dart';
import 'package:hermes_ui/app/widgets/nav_bar_hairline.dart';

/// 常驻发丝线部件（[NavBarHairline] / [NavBarBottom]）的几何与配色守卫。
///
/// 主人 2026-10-08 拍板：「常驻发丝线；本来叠在上面的线去掉」。全应用导航栏
/// 底边一律由本件提供，且必须 `border: null`（那条 SDK 黑 30% 会随滚动淡入、
/// 与常驻线叠加后「一滚动就变深」）。
void main() {
  Future<void> withContext(
    WidgetTester tester,
    Brightness brightness,
    void Function(BuildContext context) callback,
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
    callback(captured);
  }

  Future<void> pump(WidgetTester tester, Brightness brightness, Widget child) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: CupertinoPageScaffold(child: child),
      ),
    );
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    testWidgets('发丝线 $brightness：高 0.5、宽撑满、颜色取结构线令牌', (
      tester,
    ) async {
      await pump(tester, brightness, const NavBarHairline());
      final box = tester.renderObject<RenderBox>(find.byType(NavBarHairline));
      expect(box.size.height, Dividers.hairlineWidth);
      expect(
        box.size.width,
        tester.getSize(find.byType(CupertinoPageScaffold)).width,
        reason: '发丝线须撑满导航栏宽度',
      );
      final colored = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(NavBarHairline),
          matching: find.byType(ColoredBox),
        ),
      );
      final context = tester.element(find.byType(NavBarHairline));
      expect(
        colored.color.toARGB32(),
        Dividers.structural(context).toARGB32(),
        reason: '发丝线颜色必须与线族结构线同色（侧栏各栏同款）',
      );
    });
  }

  testWidgets('NavBarBottom：把既有 bottom 与发丝线叠起来，线贴最下沿', (tester) async {
    const bannerHeight = 6.0;
    const banner = PreferredSize(
      preferredSize: Size.fromHeight(bannerHeight),
      child: SizedBox(height: bannerHeight, child: Text('banner')),
    );
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            NavBarBottom(bottom: banner),
          ]),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<NavBarBottom>(find.byType(NavBarBottom)).preferredSize.height,
      bannerHeight + Dividers.hairlineWidth,
    );
    final bannerY = tester.getRect(find.text('banner')).bottom;
    final hairlineY = tester.getRect(find.byType(NavBarHairline)).top;
    expect(hairlineY, greaterThanOrEqualTo(bannerY));
  });

  testWidgets('NavBarBottom 无自定义 bottom 时只剩发丝线', (tester) async {
    await withContext(tester, Brightness.light, (context) {
      expect(
        const NavBarBottom().preferredSize.height,
        Dividers.hairlineWidth,
      );
    });
  });

  testWidgets('宽屏包装件：导航栏总高 44.5（44 + 发丝线），滚动前后线都在', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        home: const CupertinoPageScaffold(
          child: CustomScrollView(
            slivers: [
              AdaptiveSliverNavigationBar(title: '探针页面'),
              SliverToBoxAdapter(child: SizedBox(height: 3000)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navFinder = find.byType(CupertinoNavigationBar);
    expect(navFinder, findsOneWidget);
    // 44 + 0.5 = 与侧栏品牌栏（44 + 0.5）严格同轴（#163 口径）。
    expect(
      tester.getSize(navFinder).height,
      44.0 + Dividers.hairlineWidth,
    );
    final nav = tester.widget<CupertinoNavigationBar>(navFinder);
    expect(nav.border, isNull);
    expect(nav.bottom, isA<NavBarBottom>());
    expect(find.byType(NavBarHairline), findsOneWidget);

    // 滚动（原本 SDK 边框才会淡入）后依然是同一条常驻线。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byType(NavBarHairline), findsOneWidget);
    expect(
      tester.widget<CupertinoNavigationBar>(navFinder).border,
      isNull,
    );
  });
}
