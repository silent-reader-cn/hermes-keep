import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';

import '../../helpers/contrast_utils.dart';

/// L2 选中态规格守卫（浅色档）—— 只钉**令牌取值**与合成口径。
///
/// 规格即契约：`sketches/selection-light-mode-proposal.html` §3/§4
/// （主人 2026-09-27 拍板 L2：中性灰底 + 蓝前景）。
/// 组件级渲染守卫（三态底色 / 前景 / 内描边、暗色与窄屏逐字节不变）见
/// `test/app/shell/selection_l2_guard_test.dart`。
void main() {
  group('L2 浅色三态取值（设计稿 §3/§4）', () {
    test('hover 底 = rgba(120,120,128,.10)', () {
      expect(LightSurfaces.hoverSurface.toARGB32(), 0x1A787880);
      expect(
        LightSurfaces.hoverSurface,
        const Color.fromRGBO(120, 120, 128, 0.10),
      );
    });

    test('选中底 = rgba(120,120,128,.16)', () {
      expect(LightSurfaces.selectedSurface.toARGB32(), 0x29787880);
      expect(
        LightSurfaces.selectedSurface,
        const Color.fromRGBO(120, 120, 128, 0.16),
      );
    });

    test('当前态内描边 = rgba(0,95,184,.28)（1px，圆角内）', () {
      expect(LightSurfaces.currentStroke.toARGB32(), 0x47005FB8);
      expect(
        LightSurfaces.currentStroke,
        const Color.fromRGBO(0, 95, 184, 0.28),
      );
    });

    test('选中前景 = #005FB8，与 userDetail 同值同源', () {
      expect(LightSurfaces.selectionForeground.toARGB32(), 0xFF005FB8);
      expect(LightSurfaces.selectionForeground, LightSurfaces.userDetail);
      expect(LightSurfaces.selectionForeground.a, 1.0);
    });

    test('旧浅蓝 selection(#E0ECFF) 保持原值（文本选区/级别色相仍依赖它）', () {
      expect(LightSurfaces.selection.toARGB32(), 0xFFE0ECFF);
      expect(LightSurfaces.selection, const Color(0xFFE0ECFF));
    });
  });

  group('L2 三态合成口径（真实底色：白卡 + #F2F2F7 侧栏底）', () {
    test('hover 比选中淡一档（两个实际底都成立），且合成面零色相', () {
      for (final base in [LightSurfaces.card, LightSurfaces.page]) {
        final hover = compositeOver(LightSurfaces.hoverSurface, base);
        final selected = compositeOver(LightSurfaces.selectedSurface, base);
        expect(
          relativeLuminance(hover),
          greaterThan(relativeLuminance(selected)),
          reason: '悬停底应比选中底更接近背景（更淡）',
        );
        // 中性灰叠加层：三通道极差只来自 rgba 里 120/128 的 8 阶 B 差，
        // 合成后不得超过 6/255（否则「灰底带色相」，正是被否掉的问题）。
        expect(_channelSpread(selected), lessThanOrEqualTo(6));
        expect(_channelSpread(hover), lessThanOrEqualTo(6));
      }
    });

    test('选中前景在两种实际底的合成面上均达正文 AA(≥4.5)', () {
      for (final base in [LightSurfaces.card, LightSurfaces.page]) {
        final surface = compositeOver(LightSurfaces.selectedSurface, base);
        expect(
          contrastRatio(LightSurfaces.selectionForeground, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('合成值符合文档口径（白卡 ≈ #E9E9EB / 页面 ≈ #DEDEE4，容差 1/255）', () {
      _expectRgbClose(
        compositeOver(LightSurfaces.selectedSurface, LightSurfaces.card),
        0xE9E9EB,
      );
      _expectRgbClose(
        compositeOver(LightSurfaces.selectedSurface, LightSurfaces.page),
        0xDEDEE4,
      );
      _expectRgbClose(
        compositeOver(LightSurfaces.hoverSurface, LightSurfaces.card),
        0xF1F1F2,
      );
    });

    test('内描边在选中底上可见但不突兀（对比度 1.05–2.0 区间）', () {
      final surface = compositeOver(
        LightSurfaces.selectedSurface,
        LightSurfaces.card,
      );
      final stroke = compositeOver(LightSurfaces.currentStroke, surface);
      final ratio = contrastRatio(stroke, surface);
      expect(ratio, greaterThan(1.05));
      expect(ratio, lessThan(2.0));
    });
  });
}

/// 三通道极差（`0` = 完全中性灰）。
int _channelSpread(Color color) {
  final channels = <int>[
    (color.r * 255).round(),
    (color.g * 255).round(),
    (color.b * 255).round(),
  ];
  channels.sort();
  return channels.last - channels.first;
}

/// 逐通道容差 1/255 比对（合成走浮点，各平台 rounding 可能差 1 阶）。
void _expectRgbClose(Color actual, int expectedRgb) {
  final argb = actual.toARGB32();
  for (final shift in [16, 8, 0]) {
    final got = (argb >> shift) & 0xFF;
    final want = (expectedRgb >> shift) & 0xFF;
    expect((got - want).abs(), lessThanOrEqualTo(1));
  }
}
