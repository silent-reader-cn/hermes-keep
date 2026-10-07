import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/features/settings/settings_surfaces.dart';

import '../../helpers/contrast_utils.dart';

// ---------------------------------------------------------------------------
// #180 守卫：设置页分段控件「选中段标签」必须与胶囊 ≥ 4.5:1（WCAG AA 正文）
//
// 缺陷回顾：`segmentedRow` 的 `_trailing()` 把整块控件交给 `_secondary()`，
// 后者 merge 一个 `color: secondaryText` 的 DefaultTextStyle；而 SDK 的分段控件对
// **启用**段写死 `color: null`（继承）⇒ 选中段与未选中段共用「次级色」。
// 深色 `secondaryLabel`(#EBEBF5@60%) 合成到胶囊 `#636366` 上只剩 **2.92:1**
// （真机像素实测 #B5B6BB/#636365），连 3:1 都不到 —— 选中项成了整行最弱的元素。
//
// 本守卫**读渲染态**（RenderParagraph 的生效字色）而不是读源码常量，
// 因此它同时钉住「值」与「接线」：把 `_withSegmentLabelColors` 摘掉即红。
// ---------------------------------------------------------------------------

Future<void> _pumpRow(WidgetTester tester, Brightness brightness) async {
  await tester.pumpWidget(
    CupertinoApp(
      theme: buildCupertinoTheme(brightness),
      home: CupertinoPageScaffold(
        child: Builder(
          builder: (context) => SettingsSurfaces.segmentedRow(
            context,
            title: const Text('主题'),
            reserveForTitle: 56,
            control: SettingsSurfaces.segmented(
              context,
              CupertinoSlidingSegmentedControl<int>(
                groupValue: 0,
                onValueChanged: (_) {},
                children: const <int, Widget>{
                  0: Text('跟随系统'),
                  1: Text('浅色'),
                  2: Text('深色'),
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 取某段标签的**渲染态**字色（已按当前明暗解析）。
Color _labelColor(WidgetTester tester, String label) {
  final finder = find.text(label);
  final raw = tester.renderObject<RenderParagraph>(finder).text.style!.color!;
  final context = tester.element(finder);
  final resolved = CupertinoDynamicColor.maybeResolve(raw, context) ?? raw;
  return Color(resolved.toARGB32());
}

/// 取该控件实际的胶囊色（已按当前明暗解析）。
Color _thumbColor(WidgetTester tester) {
  final finder = find.byType(CupertinoSlidingSegmentedControl<int>);
  final control = tester.widget<CupertinoSlidingSegmentedControl<int>>(finder);
  return Color(
    CupertinoDynamicColor.resolve(
      control.thumbColor,
      tester.element(finder),
    ).toARGB32(),
  );
}

void main() {
  group('#180 分段控件选中标签对比度', () {
    for (final brightness in Brightness.values) {
      final name = brightness == Brightness.dark ? '深色' : '浅色';
      testWidgets('$name：选中段标签对胶囊 ≥ 4.5:1', (tester) async {
        await _pumpRow(tester, brightness);
        final selected = _labelColor(tester, '跟随系统');
        final thumb = _thumbColor(tester);
        final ratio = contrastRatio(selected, thumb);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '$name 选中标签 ${selected.toARGB32().toRadixString(16)} 对胶囊 '
              '${thumb.toARGB32().toRadixString(16)} 实测 '
              '${ratio.toStringAsFixed(2)}:1',
        );
      });
    }

    testWidgets('选中/未选中标签必须分档（不得整块同色）', (tester) async {
      for (final brightness in Brightness.values) {
        await _pumpRow(tester, brightness);
        expect(
          _labelColor(tester, '跟随系统'),
          isNot(_labelColor(tester, '浅色')),
          reason: '${brightness.name}：选中段与未选中段又共用了同一个颜色',
        );
      }
    });

    testWidgets('选中段用主标签色（深 #FFFFFF / 浅 #000000）', (tester) async {
      await _pumpRow(tester, Brightness.dark);
      expect(_labelColor(tester, '跟随系统').toARGB32(), 0xFFFFFFFF);
      await _pumpRow(tester, Brightness.light);
      expect(_labelColor(tester, '跟随系统').toARGB32(), 0xFF000000);
    });

    testWidgets('未选中段仍是次级色，不与选中段抢层级', (tester) async {
      await _pumpRow(tester, Brightness.dark);
      final unselected = _labelColor(tester, '浅色');
      expect(
        unselected.toARGB32(),
        isNot(0xFFFFFFFF),
        reason: '未选中段不该被一起提亮到主标签色',
      );
      await _pumpRow(tester, Brightness.light);
      expect(_labelColor(tester, '浅色').toARGB32(), isNot(0xFF000000));
    });

    testWidgets('胶囊本体未被改动（深色仍是 SDK 原生灰）', (tester) async {
      await _pumpRow(tester, Brightness.dark);
      expect(
        _thumbColor(tester).toARGB32(),
        0xFF636366,
        reason: '本批只改「字色」，胶囊必须保持 iOS 原生值',
      );
      await _pumpRow(tester, Brightness.light);
      expect(_thumbColor(tester).toARGB32(), 0xFFFFFFFF);
    });
  });
}
