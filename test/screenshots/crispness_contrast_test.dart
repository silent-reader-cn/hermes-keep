import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';

import '../helpers/contrast_utils.dart';

// ---------------------------------------------------------------------------
// 次级文字色的 WCAG AA 钉桩（清晰度批次）
//
// 背景：主人在 125% 系统缩放（DPR 1.25）下反馈「小字发虚」。分数 DPR 的抗锯齿
// 让 12–13pt 小字更软，此时**对比度余量**就是可读性的最后一道防线。
// 审计发现浅色 `secondaryText` 原为 `0x99`（α=60%）的**半透明**色，旧注释按
// 不透明色估的「白底 ~4.5:1」是错的：合成后对白卡只有 3.439:1、对页底 3.283:1，
// **低于 AA 正文 4.5:1**。本文件把修正后的实测值钉住。
//
// 判级口径：WCAG 2.1 §1.4.3 —— 正文（<18pt 常规 / <14pt 粗体）≥ 4.5:1；
// 大字号 ≥ 3:1；非文字图形对象（图标/状态点）§1.4.11 ≥ 3:1。
// 半透明前景一律先合成到背景再算（[contrastRatio] 内部已合成）。
// ---------------------------------------------------------------------------

/// 浅色页底（用户可调档的默认值）。
const Color _lightPage = LightSurfaces.kDefaultPage;

/// 浅色白卡。
const Color _lightCard = LightSurfaces.card;

void main() {
  group('次级文字色 AA（半透明先合成再算）', () {
    test('浅色 secondaryText：对白卡与页底都 ≥ 4.5:1', () {
      final vsCard = contrastRatio(secondaryText.color, _lightCard);
      final vsPage = contrastRatio(secondaryText.color, _lightPage);
      expect(
        vsCard,
        greaterThanOrEqualTo(4.5),
        reason: 'secondaryText(light) 对白卡实测 ${vsCard.toStringAsFixed(3)}:1',
      );
      expect(
        vsPage,
        greaterThanOrEqualTo(4.5),
        reason: 'secondaryText(light) 对页底实测 ${vsPage.toStringAsFixed(3)}:1',
      );
    });

    test('浅色 secondaryText 高对比档：强于普通档且仍 ≥ 4.5:1', () {
      final base = contrastRatio(secondaryText.color, _lightCard);
      final hc = contrastRatio(secondaryText.highContrastColor, _lightCard);
      final hcPage = contrastRatio(secondaryText.highContrastColor, _lightPage);
      expect(hc, greaterThan(base));
      expect(hcPage, greaterThanOrEqualTo(4.5));
    });

    test('深色 secondaryText：对黑与暗卡都 ≥ 4.5:1', () {
      const darkPage = Color(0xFF000000);
      const darkCard = Color(0xFF1C1C1E);
      expect(
        contrastRatio(secondaryText.darkColor, darkPage),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(secondaryText.darkColor, darkCard),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('LightSurfaces.textSecondary：对白卡与页底都 ≥ 4.5:1', () {
      expect(
        contrastRatio(LightSurfaces.textSecondary, _lightCard),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(LightSurfaces.textSecondary, _lightPage),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('状态文字色 AA（列出实测值，防回退）', () {
    const lightCases = <String, CupertinoDynamicColor>{
      'statusGreenText': statusGreenText,
      'statusOrangeText': statusOrangeText,
      'statusBlueText': statusBlueText,
      'statusGreyText': statusGreyText,
      'statusYellowText': statusYellowText,
      'statusRedText': statusRedText,
    };

    lightCases.forEach((name, color) {
      test('$name 浅色档对白卡 ≥ 4.5:1', () {
        final ratio = contrastRatio(color.color, _lightCard);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name 实测 ${ratio.toStringAsFixed(3)}:1',
        );
      });
      test('$name 深色档对纯黑 ≥ 4.5:1', () {
        final ratio = contrastRatio(color.darkColor, const Color(0xFF000000));
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name 深色实测 ${ratio.toStringAsFixed(3)}:1',
        );
      });
    });

    test('statusTealText：作为文字用（白卡）≥ 4.5:1；作图标（页底）≥ 3:1', () {
      final vsCard = contrastRatio(statusTealText.color, _lightCard);
      final vsPage = contrastRatio(statusTealText.color, _lightPage);
      expect(vsCard, greaterThanOrEqualTo(4.5));
      // 页底上它只出现在「工作区目录图标」（非文字对象，§1.4.11 ≥ 3:1）。
      expect(vsPage, greaterThanOrEqualTo(3.0));
    });
  });
}
