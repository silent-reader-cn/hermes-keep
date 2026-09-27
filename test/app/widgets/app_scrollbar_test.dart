import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/layout_tokens.dart';
import 'package:hermes_ui/app/widgets/app_scrollbar.dart';

/// G4 常显细滚动条守卫：宽屏常显 6px 圆头、悬停加深；窄屏不改行为。
const Key _listKey = ValueKey('sb-list');

/// 只有本组件会往 `foregroundPainter` 里塞 `ScrollbarPainter`。
Finder _painterFinder() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter,
);

ScrollbarPainter? _painter(WidgetTester tester) {
  final found = _painterFinder().evaluate();
  if (found.isEmpty) {
    return null;
  }
  return (found.first.widget as CustomPaint).foregroundPainter as ScrollbarPainter;
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  bool wrap = true,
}) async {
  tester.view.physicalSize = Size(width, 400.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = ScrollController();
  addTearDown(controller.dispose);
  final list = ListView.builder(
    key: _listKey,
    controller: controller,
    itemCount: 40,
    itemBuilder: (context, index) =>
        SizedBox(height: 40.0, child: Text('row $index')),
  );
  await tester.pumpWidget(
    CupertinoApp(
      theme: buildCupertinoTheme(brightness),
      home: CupertinoPageScaffold(
        child: wrap ? AppScrollbar(controller: controller, child: list) : list,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 建一条鼠标指针。
///
/// **一个测试只建一条**：`PointerAddedEvent` 必须与 `PointerRemovedEvent` 配对
/// （`MouseTracker._shouldMarkStateDirty` 的硬断言），同一测试里反复
/// `createGesture(...).addPointer()` 会直接踩断言 —— 挪动鼠标改用同一条 gesture。
Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  return gesture;
}

/// 把鼠标移到 [target] 并推进一帧（悬停生效）。
Future<void> _hover(WidgetTester tester, TestGesture mouse, Offset target) async {
  await mouse.moveTo(target);
  await tester.pump();
}

/// 滑块热区：贴右边缘（crossAxisMargin 0）、从滚动区顶部起（mainAxisMargin 0），
/// 内容 1600 / 视口 400 ⇒ 滑块长 ≈ 100，取 top+20 稳稳落在滑块内。
Offset _thumbPoint(WidgetTester tester) {
  final rect = tester.getRect(find.byType(AppScrollbar));
  return Offset(rect.right - 3.0, rect.top + 20.0);
}

void main() {
  group('宽屏（≥900）· 常显细滚动条', () {
    testWidgets('浅色：常显（不淡出）+ 6px 圆头 + 常态色 .32', (tester) async {
      await _pump(tester, brightness: Brightness.light, width: 1200.0);

      final widget = tester.widget<AppScrollbar>(find.byType(AppScrollbar));
      expect(widget.thumbVisibility, isTrue, reason: '宽屏常显');
      expect(widget.thickness, kScrollbarThickness);
      expect(widget.radius, const Radius.circular(kScrollbarRadius));

      final painter = _painter(tester);
      expect(painter, isNotNull);
      expect(painter!.color, AppScrollbar.lightThumb);
      expect(painter.thickness, kScrollbarThickness);
      expect(painter.radius, const Radius.circular(kScrollbarRadius));
      expect(
        painter.fadeoutOpacityAnimation.value,
        1.0,
        reason: '常显 = 不淡出（Mac 隐身那条要消失）',
      );
    });

    testWidgets('浅色：悬停滑块加深到 .55 → 移开回到 .32（同一 painter 颜色变化）', (tester) async {
      await _pump(tester, brightness: Brightness.light, width: 1200.0);
      expect(_painter(tester)!.color, AppScrollbar.lightThumb);

      final mouse = await _mouse(tester);
      await _hover(tester, mouse, _thumbPoint(tester));
      expect(_painter(tester)!.color, AppScrollbar.lightThumbHover);

      await _hover(tester, mouse, const Offset(4.0, 4.0));
      expect(_painter(tester)!.color, AppScrollbar.lightThumb);
    });

    testWidgets('浅色：鼠标只在内容区（不在滑块上）不加深 —— hover 判定认滑块不认区域', (tester) async {
      await _pump(tester, brightness: Brightness.light, width: 1200.0);
      final rect = tester.getRect(find.byType(AppScrollbar));
      final mouse = await _mouse(tester);

      // 贴着右边缘但落在滑块下方的空白轨区（滑块只占顶部 ~100pt）。
      await _hover(tester, mouse, Offset(rect.right - 3.0, rect.top + 300.0));
      expect(_painter(tester)!.color, AppScrollbar.lightThumb);

      // 内容区正中（离滑块很远）同样不加深。
      await _hover(tester, mouse, rect.center);
      expect(_painter(tester)!.color, AppScrollbar.lightThumb);
    });

    testWidgets('暗色：常态 .30 / 悬停 .42（明暗分别设计）', (tester) async {
      await _pump(tester, brightness: Brightness.dark, width: 1200.0);
      expect(_painter(tester)!.color, AppScrollbar.darkThumb);

      final mouse = await _mouse(tester);
      await _hover(tester, mouse, _thumbPoint(tester));
      expect(_painter(tester)!.color, AppScrollbar.darkThumbHover);
    });
  });

  group('窄屏（<900）不改行为', () {
    testWidgets('不包滚条：树里没有 ScrollbarPainter，内容矩形与不包时逐字段相等', (tester) async {
      await _pump(
        tester,
        brightness: Brightness.light,
        width: 800.0,
        wrap: false,
      );
      final bareRect = tester.getRect(find.byKey(_listKey));

      await _pump(tester, brightness: Brightness.light, width: 800.0);
      expect(
        _painterFinder(),
        findsNothing,
        reason: '窄屏交回系统默认，本组件不许自己画滚条',
      );
      expect(tester.getRect(find.byKey(_listKey)), bareRect);

      // 窄屏悬停滑块位置也不该有任何加深（根本没有我们的滑块）。
      final mouse = await _mouse(tester);
      await _hover(
        tester,
        mouse,
        Offset(bareRect.right - 3.0, bareRect.top + 20.0),
      );
      expect(_painterFinder(), findsNothing);
    });

    testWidgets('恰好 899 仍是窄屏（阈值含等号在 900 一侧）', (tester) async {
      await _pump(tester, brightness: Brightness.light, width: 899.0);
      expect(_painterFinder(), findsNothing);
    });
  });
}
