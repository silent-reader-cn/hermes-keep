// 浅色面令牌：固定不透明 sRGB；仅由选择接入的页面消费，不改全局主题。
// Python WCAG 2.x 实算（tools/light_theme_contrast.py --tokens）：
// token         RGB       对 page   对 card   对 textSecondary
// page          #F2F2F7   1.000000  1.115871  4.820554
// card          #FFFFFF   1.115871  1.000000  5.379116
// cardBorder    #CCD0DA   1.383553  1.543866  3.484185
// divider       #CCD0DA   1.383553  1.543866  3.484185
// textSecondary #6A6A6F   4.820554  5.379116  1.000000
// selection     #E0ECFF   1.068576  1.192393  4.511193
// pressed = page；placeholder = textSecondary，三向数值同对应令牌。
// 面/分隔线为装饰层级，不以正文 AA 判级；选中态另有勾选图标标识。
// v3（2026-09-13 主人拍板「分栏线/区域线提到同档拉平」）：divider 由
// #C6C6C8 改为 cardBorder 别名（#CCD0DA）——原 divider 比描边更深且为
// 中性灰，与冷灰紫描边色相分家，产生「结构线比卡片边界散」的观感；
// 统一后全页线族/描边同一族同一档。v2（2026-09-13 主人实机反馈
// 「灰底太深」回调）：page 从 #EBEBF0 退回
// iOS 标准 #F2F2F7，分层主力移交加深一档的 cardBorder（#DDE0E8→#CCD0DA，
// 对白卡 1.543866:1，接近 GitHub Primer #d0d7de 的可见 hairline 档位）。
// page 变浅后 textSecondary 对 page 余量增大（4.527→4.821），维持不变。
// tertiaryLabel/placeholderText 合成到 page/card 后仅 1.683235/1.725396，
// 可读占位文案使用 placeholder，不通过降低透明度制造文字层级。
// v4（2026-09-27 主人拍板 L2 选中态）：新增 selectedSurface / hoverSurface /
// currentStroke / selectionForeground —— 前三者是**半透明叠加层**，不参与上面的
// 不透明对比度表（合成值见各令牌 doc）。出处均为设计稿
// `sketches/selection-light-mode-proposal.html` §3/§4（L2 规格表）。

import 'package:flutter/cupertino.dart';

/// 浅色面与文字令牌；深色由调用方传入原有颜色，逐字节保留。
abstract final class LightSurfaces {
  /// 页面与会话侧边栏列表区的分组背景。
  static const Color page = Color(0xFFF2F2F7);

  /// 分组卡片、输入框及普通浮层的白色面。
  static const Color card = Color(0xFFFFFFFF);

  /// 分组卡片轮廓（0.5–1 逻辑像素 hairline）。
  static const Color cardBorder = Color(0xFFCCD0DA);

  /// iOS 浅色 opaqueSeparator；v3（主人拍板拉平）与 cardBorder 同值同族，
  /// 结构线与卡片描边共用一档冷灰紫，消除色相分家与层级倒挂观感。
  static const Color divider = cardBorder;

  /// 次级文字和需要辨认的图标；页面、白卡、选中面均满足正文 AA。
  static const Color textSecondary = Color(0xFF6A6A6F);

  /// 可读占位文案，与次级文字共用对比度下限。
  static const Color placeholder = textSecondary;

  /// 旧浅蓝选中面（#E0ECFF，≈ primary 12% 叠白）。
  ///
  /// L2 起**不再用于「选中行」**（改由 [selectedSurface] 承担）：主人判定该色
  /// 「在白纸上贴了张便利贴」。剩余用途是文本选区底（`DefaultSelectionStyle`
  /// 的 selectionColor）与诊断级别色相，本令牌值保持不变以维持那些场景原样。
  static const Color selection = Color(0xFFE0ECFF);

  /// 选中态底（L2 浅色规格）。半透明中性灰、零色相，叠加在白卡与 [page] 上
  /// 都立得住（合成后：白卡 ≈ #E9E9EB、[page] ≈ #DEDEE4）。
  /// 出处：`sketches/selection-light-mode-proposal.html` §4「选中 · 底 rgba(120,120,128,.16)」。
  static const Color selectedSurface = Color.fromRGBO(120, 120, 128, 0.16);

  /// 悬停态底（L2 浅色规格）：比 [selectedSurface] 淡一档、同样不带色相，
  /// 扫列表时不会「闪蓝」。与选中的差别 = 有蓝字 vs 无蓝字。
  /// 出处：同设计稿 §3「hover · 底 rgba(120,120,128,.10)」。
  static const Color hoverSurface = Color.fromRGBO(120, 120, 128, 0.10);

  /// 「当前」持久态内描边（1px，圆角内），叠在 [selectedSurface] 之上，
  /// 用于侧栏「当前会话」与文件树「当前文件」，比选中「更停得住」。
  /// 出处：同设计稿 §4「当前 · 内描边 rgba(0,95,184,.28)」。
  static const Color currentStroke = Color.fromRGBO(0, 95, 184, 0.28);

  /// 选中态前景（文字**和**图标）。
  ///
  /// 与 [userDetail] **同值同源**（#005FB8，浅色正文 AA），此处按语义另设
  /// 别名，避免选中态语义挂在「用户气泡详情」令牌上。
  static const Color selectionForeground = userDetail;

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
