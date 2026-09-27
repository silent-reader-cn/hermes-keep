import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart' show kAdaptiveBreakpoint;
import 'package:hermes_ui/app/theme/layout_tokens.dart';

/// G1–G4 宽屏横切件令牌守卫（批 1）。
///
/// 契约出处：`sketches/wide-global-rules-decision.html` §G1/§G2/§G3/§G4。
/// 数值即契约：本文件把每个值钉死，防止后续哪一页「顺手调一眼」把全局节奏改掉。
void main() {
  group('常量值固定（数值即契约，防止被随手改）', () {
    test('G1 三类容器宽度 + 阈值', () {
      expect(kWideBreakpoint, 900.0);
      expect(kReadingMaxWidth, 760.0);
      expect(kFormMaxWidth, 560.0);
    });

    test('G2 内边距两档与圆角三档', () {
      expect(kPanelPaddingWide, 24.0);
      expect(kPanelPaddingNarrow, 16.0);
      expect(kRadiusGroup, 10.0);
      expect(kRadiusCard, 12.0);
      expect(kRadiusInline, 7.0);
    });

    test('G3 焦点环与图标钮尺寸', () {
      expect(kFocusRingWidth, 2.0);
      expect(kFocusRingOffset, 2.0);
      expect(kIconButtonHoverSize, 28.0);
    });

    test('G4 常显滚动条厚度与圆头半径（半径 = 厚度一半才叫圆头）', () {
      expect(kScrollbarThickness, 6.0);
      expect(kScrollbarRadius, 3.0);
      expect(kScrollbarRadius, kScrollbarThickness / 2);
    });

    test('阈值与 kAdaptiveBreakpoint 恒等 —— 两处不许漂', () {
      // 本文件刻意不 import adaptive_shell（避免 theme ← shell 循环依赖），
      // 单一事实来源由这条恒等守卫保证。
      expect(kWideBreakpoint, kAdaptiveBreakpoint);
    });
  });

  group('isWideLayout 边界', () {
    Future<bool> probe(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 600.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late bool result;
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) {
              result = isWideLayout(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('899 → 窄屏（false）', (tester) async {
      expect(await probe(tester, 899.0), isFalse);
    });

    testWidgets('900 → 宽屏（true，含等号）', (tester) async {
      expect(await probe(tester, 900.0), isTrue);
    });

    testWidgets('899.9 → 窄屏 / 900.1 → 宽屏（无小数缝）', (tester) async {
      expect(await probe(tester, 899.9), isFalse);
      expect(await probe(tester, 900.1), isTrue);
    });
  });

  group('G3 光标语义 kPointerCursor', () {
    test('可点 → click；禁用 → forbidden', () {
      expect(kPointerCursor.resolve(<WidgetState>{}), SystemMouseCursors.click);
      expect(
        kPointerCursor.resolve(<WidgetState>{WidgetState.disabled}),
        SystemMouseCursors.forbidden,
      );
      expect(
        kPointerCursor.resolve(<WidgetState>{
          WidgetState.disabled,
          WidgetState.hovered,
        }),
        SystemMouseCursors.forbidden,
      );
    });

    testWidgets('挂到 CupertinoButton：启用 click / 禁用 forbidden（覆盖整颗按钮）', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: Column(
            children: [
              CupertinoButton(
                key: const ValueKey('cursor-on'),
                mouseCursor: kPointerCursor,
                onPressed: () {},
                child: const Text('on'),
              ),
              const CupertinoButton(
                key: ValueKey('cursor-off'),
                mouseCursor: kPointerCursor,
                onPressed: null,
                child: Text('off'),
              ),
            ],
          ),
        ),
      );

      MouseCursor? cursorOf(String key) {
        // CupertinoButton 内部不止一个 MouseRegion（外层带 effectiveMouseCursor，
        // 内层来自 FocusableActionDetector）⇒ 取最外层那个。
        final regions = tester.widgetList<MouseRegion>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(MouseRegion),
          ),
        );
        expect(regions, isNotEmpty);
        return regions.first.cursor;
      }

      expect(cursorOf('cursor-on'), SystemMouseCursors.click);
      expect(cursorOf('cursor-off'), SystemMouseCursors.forbidden);

      // 不传 mouseCursor 时是框架默认（非 Web 平台 defer）——说明这确实是本令牌
      // 带来的差异，而不是框架本来就给的手型。
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoButton(
            key: const ValueKey('cursor-default'),
            onPressed: () {},
            child: const Text('default'),
          ),
        ),
      );
      expect(cursorOf('cursor-default'), MouseCursor.defer);
    });
  });
}
