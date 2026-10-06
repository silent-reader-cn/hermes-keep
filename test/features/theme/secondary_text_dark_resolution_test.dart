import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';

void main() {
  group('secondaryText 暗黑与浅色模式解析回归测试', () {
    testWidgets('dark: Text widget secondaryText resolveFrom painted color == 0x99EBEBF5', (
      tester,
    ) async {
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) => Center(
              child: Text(
                'x',
                style: TextStyle(color: secondaryText.resolveFrom(context)),
              ),
            ),
          ),
        ),
      );
      final renderParagraph = tester.renderObject<RenderParagraph>(
        find.text('x'),
      );
      expect(renderParagraph.text.style!.color!.toARGB32(), 0x99EBEBF5);
    });

    testWidgets('light: Text widget secondaryText resolveFrom painted color == 0xBD3C3C43', (
      tester,
    ) async {
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (context) => Center(
              child: Text(
                'x',
                style: TextStyle(color: secondaryText.resolveFrom(context)),
              ),
            ),
          ),
        ),
      );
      final renderParagraph = tester.renderObject<RenderParagraph>(
        find.text('x'),
      );
      // 清晰度批次（2026-10-06）：浅色档由 0x99（α=60%）提到 0xBD（α=74.1%）。
      // 原因：半透明色必须先合成再算对比度，0x99 合成到白卡只有 3.439:1、
      // 到页底 3.283:1，**低于 WCAG AA 正文 4.5:1**；0xBD 为 4.998 / 4.734。
      // 详见 `test/screenshots/crispness_contrast_test.dart` 与
      // `.shots/crispness/before-after.md` §3。
      expect(renderParagraph.text.style!.color!.toARGB32(), 0xBD3C3C43);
    });

    test('secondaryText darkColor and darkHighContrastColor 对齐 secondaryLabel', () {
      expect(
        secondaryText.darkColor.toARGB32(),
        CupertinoColors.secondaryLabel.darkColor.toARGB32(),
      );
      expect(
        secondaryText.darkHighContrastColor.toARGB32(),
        CupertinoColors.secondaryLabel.darkHighContrastColor.toARGB32(),
      );
      expect(secondaryText.darkColor.toARGB32(), 0x99EBEBF5);
      expect(secondaryText.darkHighContrastColor.toARGB32(), 0xADEBEBF5);
    });
  });
}
