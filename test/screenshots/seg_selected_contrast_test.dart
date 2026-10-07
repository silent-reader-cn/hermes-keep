import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';

import '../helpers/contrast_utils.dart';

// ---------------------------------------------------------------------------
// 分段控件「选中态」对比度探针（数值取证，非金照）
//
// 用法：SEG_PROBE=1 C:/tmp/f.bat test test/screenshots/seg_selected_contrast_test.dart
// 不带 SEG_PROBE=1 时 skip，`flutter test` 全量零影响。
//
// 背景：主人 2026-10-07 报「设置页分段控件选中项（跟随系统）文字和底色都太浅」。
// 本探针把「渲染时的真实颜色」算出来（半透明前景先合成到背景），并与真机截图的
// 像素读数交叉核对，用于给设计稿提供客观判据。
// ---------------------------------------------------------------------------

final bool _probe = Platform.environment['SEG_PROBE'] == '1';
const String _skipReason = '设置 SEG_PROBE=1 才运行分段控件对比度探针';

/// SDK `CupertinoSlidingSegmentedControl` 暗色拇指默认值
/// （`sliding_segmented_control.dart` 的 `_kThumbColor.darkColor`）。
const Color _kSdkThumbDark = Color(0xFF636366);

/// 档 C 候选：提亮后的暗色胶囊（白字仍 ≥ 4.5:1 的上限灰度）。
const Color _kThumbDarkLifted = Color(0xFF757577);

String _hex(Color c) {
  final v = c.toARGB32();
  return '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

void _row(String label, Color fg, Color bg) {
  final composed = compositeOver(fg, bg);
  final ratio = contrastRatio(fg, bg);
  final verdict = ratio >= 4.5 ? 'AA  ' : (ratio >= 3.0 ? 'AA-大' : '不足 ');
  // ignore: avoid_print
  print(
    '${label.padRight(34)} 前景 ${_hex(fg)} @ alpha '
    '${fg.a.toStringAsFixed(2)} 底色 ${_hex(bg)} → 渲染 '
    '${_hex(composed)}  ${ratio.toStringAsFixed(2)}:1  $verdict',
  );
}

void main() {
  test('分段控件选中态对比度矩阵', () {
    // ── 语义色原始定义 ─────────────────────────────────────────────────
    const secondaryLabel = CupertinoColors.secondaryLabel;
    final slLight = secondaryLabel.color; // #3C3C43 @ 60%
    final slDark = secondaryLabel.darkColor; // #EBEBF5 @ 60%
    const fill = CupertinoColors.tertiarySystemFill;
    final fillLight = fill.color; // #767680 @ 8%
    final fillDark = fill.darkColor; // #767680 @ 24%

    // ── 底色 ───────────────────────────────────────────────────────────
    const cardDark = Color(0xFF1C1C1E);
    const cardLight = Color(0xFFFFFFFF);
    final trackDark = compositeOver(fillDark, cardDark);
    final trackLight = compositeOver(fillLight, cardLight);

    // ignore: avoid_print
    print('── 底色（合成后） ─────────────────────────────────────────');
    // ignore: avoid_print
    print(
      '  暗色 卡片 ${_hex(cardDark)}  轨道 ${_hex(trackDark)}  '
      '胶囊(SDK) ${_hex(_kSdkThumbDark)}',
    );
    // ignore: avoid_print
    print(
      '  浅色 卡片 ${_hex(cardLight)}  轨道 ${_hex(trackLight)}  '
      '胶囊(SDK) #FFFFFF',
    );
    // ignore: avoid_print
    print(
      '  暗色 胶囊/卡片 ${contrastRatio(_kSdkThumbDark, cardDark).toStringAsFixed(2)}:1  '
      '胶囊/轨道 ${contrastRatio(_kSdkThumbDark, trackDark).toStringAsFixed(2)}:1',
    );
    // ignore: avoid_print
    print(
      '  浅色 胶囊/卡片 ${contrastRatio(cardLight, cardLight).toStringAsFixed(2)}:1  '
      '胶囊/轨道 ${contrastRatio(cardLight, trackLight).toStringAsFixed(2)}:1',
    );

    // ignore: avoid_print
    print('\n── 现状（标签继承 _secondary 的次级色） ───────────────────');
    _row('暗 选中「跟随系统」', slDark, _kSdkThumbDark);
    _row('暗 未选中「浅色」', slDark, trackDark);
    _row('浅 选中「跟随系统」', LightSurfaces.textSecondary, cardLight);
    _row('浅 未选中「浅色」', LightSurfaces.textSecondary, trackLight);
    // 反例：浅色若改用 SDK 的 secondaryLabel 会掉到 3.4:1 —— 故未选中色
    // 必须继续读 `_SectionPalette.secondaryText`（浅色 = LightSurfaces.textSecondary）。
    _row('浅 若用 secondaryLabel（反例）', slLight, cardLight);

    // ignore: avoid_print
    print('\n── 候选档 1：选中标签改主标签色 label ─────────────────────');
    _row('暗 选中「跟随系统」', CupertinoColors.label.darkColor, _kSdkThumbDark);
    _row('浅 选中「跟随系统」', CupertinoColors.label.color, cardLight);

    // ignore: avoid_print
    print('\n── 候选档 2：胶囊改主题强调色 + 白字 ─────────────────────');
    _row(
      '暗 选中「跟随系统」',
      CupertinoColors.white,
      CupertinoColors.systemBlue.darkColor,
    );
    _row('浅 选中「跟随系统」', CupertinoColors.white, CupertinoColors.systemBlue.color);

    // ignore: avoid_print
    print('\n── 候选档 3：胶囊提亮 #757577 + 主标签色 ─────────────────');
    _row('暗 选中「跟随系统」', CupertinoColors.label.darkColor, _kThumbDarkLifted);
    // ignore: avoid_print
    print(
      '  暗色 提亮后 胶囊/卡片 '
      '${contrastRatio(_kThumbDarkLifted, cardDark).toStringAsFixed(2)}:1  '
      '胶囊/轨道 ${contrastRatio(_kThumbDarkLifted, trackDark).toStringAsFixed(2)}:1',
    );

    // ignore: avoid_print
    print('\n── 真机截图实测（主人 2026-10-07 安卓机，暗色） ───────────');
    const measuredThumb = Color(0xFF636365);
    const measuredTrack = Color(0xFF323136);
    const measuredSelectedText = Color(0xFFB5B6BB);
    const measuredUnselectedText = Color(0xFFA1A1A9);
    _row('实测 选中字 / 胶囊', measuredSelectedText, measuredThumb);
    _row('实测 未选中字 / 轨道', measuredUnselectedText, measuredTrack);
    // ignore: avoid_print
    print(
      '  实测 胶囊/卡片 '
      '${contrastRatio(measuredThumb, cardDark).toStringAsFixed(2)}:1',
    );
  }, skip: !_probe);

  test('工装门控', () {
    expect(_probe, isTrue, reason: _skipReason);
  }, skip: !_probe);
}
