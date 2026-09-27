import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/layout_tokens.dart';
import 'package:hermes_ui/app/widgets/reading_width_box.dart';

/// G1 限宽容器守卫：宽屏限宽居中、窄屏逐像素原样透传。
const Key _fillKey = ValueKey('rwb-fill');
const Key _shortKey = ValueKey('rwb-short');

/// 想铺满的 child（ListView / 表单这类内容的等价物）：给它多大就用多大。
Widget _fill() => const SizedBox.expand(
  key: _fillKey,
  child: ColoredBox(color: Color(0xFF1C1C1E)),
);

/// 矮 child（高度 60）：用来证明宽屏**只做水平居中**、不做垂直居中。
Widget _short() => const SizedBox(
  key: _shortKey,
  width: double.infinity,
  height: 60.0,
  child: ColoredBox(color: Color(0xFF2C2C2E)),
);

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required Widget child,
  Widget Function(Widget child)? wrap,
}) async {
  tester.view.physicalSize = Size(width, 800.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CupertinoApp(
      home: CupertinoPageScaffold(child: wrap == null ? child : wrap(child)),
    ),
  );
}

void main() {
  group('宽屏（≥900）限宽 + 水平居中', () {
    testWidgets('阅读型档位：铺满的 child 被限到 760，两侧留白相等', (tester) async {
      await _pump(
        tester,
        width: 1280.0,
        child: _fill(),
        wrap: (child) => ReadingWidthBox(child: child),
      );

      final rect = tester.getRect(find.byKey(_fillKey));
      expect(rect.width, kReadingMaxWidth);
      // 水平居中：左右留白相等，且 = (1280 - 760) / 2。
      expect(rect.left, (1280.0 - kReadingMaxWidth) / 2);
      expect(rect.right, 1280.0 - (1280.0 - kReadingMaxWidth) / 2);
      // 垂直方向不动：铺满的 child 仍然铺满。
      expect(rect.top, 0.0);
      expect(rect.height, 800.0);
    });

    testWidgets('表单型档位：560，且两档确实是两个数', (tester) async {
      await _pump(
        tester,
        width: 1280.0,
        child: _fill(),
        wrap: (child) => ReadingWidthBox.form(child: child),
      );
      expect(tester.getRect(find.byKey(_fillKey)).width, kFormMaxWidth);
      expect(
        tester.getRect(find.byKey(_fillKey)).left,
        (1280.0 - kFormMaxWidth) / 2,
      );
      expect(kFormMaxWidth, isNot(kReadingMaxWidth));
    });

    testWidgets('矮 child 不被垂直居中（只限宽，不改 child 自身布局）', (tester) async {
      await _pump(
        tester,
        width: 1280.0,
        child: _short(),
        wrap: (child) => ReadingWidthBox(child: child),
      );
      final rect = tester.getRect(find.byKey(_shortKey));
      expect(rect.top, 0.0, reason: '限宽只针对水平方向，不能顺手把内容推到屏幕中间');
      expect(rect.height, 60.0);
      expect(rect.width, kReadingMaxWidth);
    });

    testWidgets('恰好 900 就走宽屏分支（含等号）', (tester) async {
      await _pump(
        tester,
        width: 900.0,
        child: _fill(),
        wrap: (child) => ReadingWidthBox(child: child),
      );
      expect(tester.getRect(find.byKey(_fillKey)).width, kReadingMaxWidth);
    });
  });

  group('窄屏（<900）逐像素不变', () {
    /// 同一 child 分别在「包本组件」与「不包本组件」下的矩形，必须逐字段相等。
    Future<void> expectIdentical(
      WidgetTester tester, {
      required double width,
      required Key key,
      required Widget child,
    }) async {
      await _pump(tester, width: width, child: child);
      final bare = tester.getRect(find.byKey(key));

      await _pump(
        tester,
        width: width,
        child: child,
        wrap: (inner) => ReadingWidthBox(child: inner),
      );
      final wrapped = tester.getRect(find.byKey(key));

      expect(wrapped, bare, reason: '窄屏必须原样透传：尺寸与位置一个像素都不许动');
    }

    testWidgets('铺满 child：899 下与不包本组件完全同矩形', (tester) async {
      await expectIdentical(
        tester,
        width: 899.0,
        key: _fillKey,
        child: _fill(),
      );
    });

    testWidgets('矮 child：899 下与不包本组件完全同矩形', (tester) async {
      await expectIdentical(
        tester,
        width: 899.0,
        key: _shortKey,
        child: _short(),
      );
    });

    testWidgets('表单型档位在窄屏同样透传（两档都不许在窄屏生效）', (tester) async {
      await _pump(tester, width: 899.0, child: _fill());
      final bare = tester.getRect(find.byKey(_fillKey));

      await _pump(
        tester,
        width: 899.0,
        child: _fill(),
        wrap: (inner) => ReadingWidthBox.form(child: inner),
      );
      expect(tester.getRect(find.byKey(_fillKey)), bare);
    });

    testWidgets('手机竖屏（390）透传：子树里不存在本组件插入的 Center/Align 约束', (tester) async {
      await _pump(
        tester,
        width: 390.0,
        child: _fill(),
        wrap: (child) => ReadingWidthBox(child: child),
      );
      final rect = tester.getRect(find.byKey(_fillKey));
      expect(rect.width, 390.0);
      expect(rect.left, 0.0);
      // 透传 = 直接返回 child：本组件自身不产生任何 RenderObject 层。
      expect(find.byType(ReadingWidthBox), findsOneWidget);
    });
  });
}
