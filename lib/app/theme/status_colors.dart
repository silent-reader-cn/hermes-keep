// 状态文字颜色（WCAG AA 达标版）。
//
// 系统状态色（systemGreen/systemOrange/systemBlue/systemGrey/systemYellow）在浅色
// 背景下对比度不足（绿 #34C759 ~2.0:1、橙 #FF9500 ~2.0:1、黄 #FFCC00 ~1.4:1），
// 不适合直接用作文字色，**也不适合直接用作状态指示点/转圈** —— 后者是传达状态的
// 图形对象，按 WCAG 1.4.11 需 >= 3:1（原生黄实测仅 1.355:1）。本组动态色：
// - 浅色模式用深色变体（白底对比 >= 4.5:1）
// - 深色模式用亮色变体（黑底对比 >= 4.5:1）
// - highContrast* 为系统增强对比度模式下的更强变体。
//
// 用法：Text('运行中', style: TextStyle(color: statusGreenText.resolveFrom(context)))
// 必须经 resolveFrom(context) 解析为当前主题色，禁止直接作为 const TextStyle 的 color
//（动态色不解析在暗黑下会退化为浅色变体，对比度不足且与装饰圆点不一致）。
import 'package:flutter/cupertino.dart';

/// 状态「运行中/成功」文字色：浅 #1E7A34（白底 ~5.9:1）/ 深 #34C759（黑底 ~6.3:1）。
const CupertinoDynamicColor statusGreenText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF1E7A34),
  darkColor: Color(0xFF34C759),
  highContrastColor: Color(0xFF0E6B2C),
  darkHighContrastColor: Color(0xFF40DD74),
);

/// 状态「暂停/警告」文字色：浅 #B25000（白底 ~5.2:1）/ 深 #FF9500（黑底 ~9.6:1）。
const CupertinoDynamicColor statusOrangeText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFFB25000),
  darkColor: Color(0xFFFF9500),
  highContrastColor: Color(0xFF9A3F00),
  darkHighContrastColor: Color(0xFFFFB340),
);

/// 状态「进行中/主色」文字色：浅 #005FB8（白底 ~4.7:1）/ 深 #0A84FF（黑底 ~7.5:1）。
const CupertinoDynamicColor statusBlueText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF005FB8),
  darkColor: Color(0xFF0A84FF),
  highContrastColor: Color(0xFF004A94),
  darkHighContrastColor: Color(0xFF45A3FF),
);

/// 状态「关闭/离线」文字色：浅 #595959（白底 ~5.9:1）/ 深 #8E8E93（黑底 ~4.8:1）。
const CupertinoDynamicColor statusGreyText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF595959),
  darkColor: Color(0xFF8E8E93),
  highContrastColor: Color(0xFF3E3E44),
  darkHighContrastColor: Color(0xFFAEAEB6),
);

/// 状态「就绪/teal」文字色：浅 #0E7C86（白底 ~4.9:1）/ 深 #30B0C7（黑底 ~8.2:1）。
const CupertinoDynamicColor statusTealText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF0E7C86),
  darkColor: Color(0xFF30B0C7),
  highContrastColor: Color(0xFF0A6169),
  darkHighContrastColor: Color(0xFF40C4D6),
);

/// 状态「等待/挂起」文字色：浅 #8A6100（对页底 4.965:1、对白卡 5.540:1）/
/// 深 #FFD60A（对黑底 14.875:1、对暗卡 12.052:1）。
///
/// 原生 systemYellow 浅色档 #FFCC00 对页底仅 1.355:1，在浅色面上几乎不可见，
/// 故与绿/橙/红同族补一档压深变体。
const CupertinoDynamicColor statusYellowText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF8A6100),
  darkColor: Color(0xFFFFD60A),
  highContrastColor: Color(0xFF6E4E00),
  darkHighContrastColor: Color(0xFFFFE04F),
);

/// 错误/失败详情文字色：浅 #B3001B（白底 ~7.0:1）/ 深 #FF453A（黑底 ~6.3:1）。
///
/// 系统 systemRed（浅 #FF3B30 白底 ~3.4:1 / 深 #FF453A 黑底 ~6.3:1）在浅色
/// 模式对比度不足，不能直接用作文字色；错误详情、失败提示等一律用本色。
const CupertinoDynamicColor statusRedText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFFB3001B),
  darkColor: Color(0xFFFF453A),
  highContrastColor: Color(0xFF8F0018),
  darkHighContrastColor: Color(0xFFFF6961),
);

/// 辅助/次要信息文字色（对齐 iOS 次级层级，深色模式对齐 CupertinoColors.secondaryLabel 的 60% 白 0x99EBEBF5，即设置页服务器地址显示色）。
///
/// 用于会话列表副标、列表项次要描述、空态提示、详情元数据等用户需读取的辅助文字。
/// - 浅色模式：Color.fromARGB(0x99, 0x3C, 0x3C, 0x43)（白底 ~4.5:1，浅灰底 ~5.0:1）
/// - 深色模式：Color.fromARGB(0x99, 0xEB, 0xEB, 0xF5)（黑底 ~6.7:1，对齐 secondaryLabel 设置页服务器地址色）
const CupertinoDynamicColor secondaryText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color.fromARGB(0x99, 0x3C, 0x3C, 0x43),
  darkColor: Color.fromARGB(0x99, 0xEB, 0xEB, 0xF5),
  highContrastColor: Color.fromARGB(0xAA, 0x3C, 0x3C, 0x43),
  darkHighContrastColor: Color.fromARGB(0xAD, 0xEB, 0xEB, 0xF5),
);
