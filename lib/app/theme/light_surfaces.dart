// 浅色面令牌：固定不透明 sRGB；仅由选择接入的页面消费，不改全局主题。
// Python WCAG 2.x 实算（tools/light_theme_contrast.py --tokens）：
// token         RGB       对 page   对 card   对 textSecondary
// page          #F2F2F7   1.000000  1.115871  4.820554
// card          #FFFFFF   1.115871  1.000000  5.379116
// cardBorder    #CCD0DA   1.383553  1.543866  3.484185
// divider       #C6C6C8   1.528439  1.705540  3.153907
// textSecondary #6A6A6F   4.820554  5.379116  1.000000
// selection     #E0ECFF   1.068576  1.192393  4.511193
// pressed = page；placeholder = textSecondary，三向数值同对应令牌。
// 面/分隔线为装饰层级，不以正文 AA 判级；选中态另有勾选图标标识。
// v2（2026-09-13 主人实机反馈「灰底太深」回调）：page 从 #EBEBF0 退回
// iOS 标准 #F2F2F7，分层主力移交加深一档的 cardBorder（#DDE0E8→#CCD0DA，
// 对白卡 1.543866:1，接近 GitHub Primer #d0d7de 的可见 hairline 档位）。
// page 变浅后 textSecondary 对 page 余量增大（4.527→4.821），维持不变。
// tertiaryLabel/placeholderText 合成到 page/card 后仅 1.683235/1.725396，
// 可读占位文案使用 placeholder，不通过降低透明度制造文字层级。

import 'package:flutter/cupertino.dart';

/// 浅色面与文字令牌；深色由调用方传入原有颜色，逐字节保留。
abstract final class LightSurfaces {
  /// 页面与会话侧边栏列表区的分组背景。
  static const Color page = Color(0xFFF2F2F7);

  /// 分组卡片、输入框及普通浮层的白色面。
  static const Color card = Color(0xFFFFFFFF);

  /// 分组卡片轮廓（0.5–1 逻辑像素 hairline）。
  static const Color cardBorder = Color(0xFFCCD0DA);

  /// iOS 浅色 opaqueSeparator，避免透明分隔线随承载面漂移。
  static const Color divider = Color(0xFFC6C6C8);

  /// 次级文字和需要辨认的图标；页面、白卡、选中面均满足正文 AA。
  static const Color textSecondary = Color(0xFF6A6A6F);

  /// 可读占位文案，与次级文字共用对比度下限。
  static const Color placeholder = textSecondary;

  /// 会话行选中面；蓝色色相配合勾选图标表达选择状态。
  static const Color selection = Color(0xFFE0ECFF);

  /// 会话行按下面，与白色静止行形成可见差异。
  static const Color pressed = page;

  /// Success notices and clarification answers; secondary text 5.036250:1.
  static const Color tintGreen = Color(0xFFF0FAF2);

  /// Approval/warning surface; statusOrangeText 4.790918:1.
  static const Color tintWarning = Color(0xFFFFF4E8);

  /// Error surface; keeps the status label independent of the page beneath.
  static const Color tintError = Color(0xFFFFF4F3);

  /// Clarification surface; secondary text 4.855495:1.
  static const Color tintClarification = Color(0xFFF3F2FF);

  /// Local code/link/attachment surface inside the unchanged brand-blue bubble.
  /// White content reaches 6.308159:1; the main bubble stays #007AFF.
  static const Color userDetail = Color(0xFF005FB8);

  /// Action-sheet blue from the existing high-contrast status palette.
  /// Keeps native translucent pressed rows readable without changing their skin.
  static const Color menuAction = Color(0xFF004A94);

  /// 浅色使用固定 [light]，深色显式解析调用点原有的 [dark] 语义色。
  ///
  /// 保留深色高对比度及 elevated 分支；原来直接绘制的未解析颜色应传
  /// 原绘制值（普通 [Color]），防止此次浅色接入顺带改变深色像素。
  static Color resolve(
    BuildContext context,
    Color light, {
    required Color dark,
  }) {
    return CupertinoTheme.brightnessOf(context) == Brightness.light
        ? light
        : CupertinoDynamicColor.resolve(dark, context);
  }
}
