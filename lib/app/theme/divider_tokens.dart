// 分割线语义分级（**唯一出口**）。
//
// 主人 2026-10-08 拍板：「全应用的分割线统一做下语义颜色、分下级、统一下」。
//
// ── 起案根因（实测）──────────────────────────────────────────────────────
// 「标题栏下沿那条线」在两种会话状态下深浅不同：新会话只见本仓自绘的 0.5px
// 发丝线；**有内容的会话一滚动就加深**。根因 = Flutter SDK 的
// `CupertinoNavigationBar` 默认 `border: _kDefaultNavBarBorder`
// （`#4D000000` 即黑 30%，`width: 0.0 // 0.0 means one physical pixel`），且在
// `CupertinoPageScaffold` 内会随内容滚动把这条黑线从透明淡入
// （`_scrollAnimationValue`，由 depth==0 的滚动通知驱动，阈值 10 逻辑像素）
// ⇒ 与自绘发丝线叠加。全仓另有 20 余处导航栏沿用该 SDK 默认值、或把它硬编码成
// `Color(0x4D000000)`，于是线族里并存「黑 30%」与「令牌灰」两套色。
//
// ── 分级口径 ─────────────────────────────────────────────────────────────
// | 级 | 语义 | 浅色 | 深色 | 线宽 |
// | L1 结构线 | 栏底（导航栏 / 侧栏各栏）、分栏竖线、区域分隔 | `LightSurfaces.divider` | `CupertinoColors.separator` | 0.5 |
// | L2 容器描边 | 卡片 / 输入框 / 弹层轮廓 | `LightSurfaces.cardBorder` | `CupertinoColors.separator` | 0.5 |
// | L3 行间线 | 分组内列表项之间（含 `CupertinoListSection.separatorColor`） | `LightSurfaces.divider` | `CupertinoColors.separator` | 内置 |
//
// L1/L2/L3 目前**同值同族**（v3 2026-09-13 主人拍板「分栏线/区域线提到同档拉平」，
// 见 `light_surfaces.dart` 顶部注）。分级的意义是**把语义显名**：以后要把层次
// 拉开（例如「外框比内线重一档」），只改本文件，不必再全仓找线。
//
// ── 线宽口径 ─────────────────────────────────────────────────────────────
// 统一取 [hairlineWidth] = 0.5 逻辑像素（与侧栏各栏、聊天顶栏同口径）。SDK 默认的
// `width: 0.0`（= 1 物理像素）在 1x 屏上是整像素实线，比线族其它线重一倍
// （主人 1x 屏实测：两条叠一起就是「一滚动就加深」的那个深色行），故不采用。

import 'package:flutter/cupertino.dart';

import 'light_surfaces.dart';

/// 分割线语义分级（唯一出口）。详见文件头注释的分级表。
abstract final class Dividers {
  /// 发丝线线宽（逻辑像素）。全应用结构线/容器描边统一取此值。
  static const double hairlineWidth = 0.5;

  /// L1 **结构线**：栏底（导航栏、侧栏各栏）、分栏竖线、区域分隔。
  ///
  /// 浅色 = [LightSurfaces.divider]（随用户所选页底色派生），
  /// 深色 = 系统 `separator`（保留动态色语义，逐像素沿用改造前）。
  static Color structural(BuildContext context) => LightSurfaces.resolve(
    context,
    LightSurfaces.divider,
    dark: CupertinoColors.separator,
  );

  /// L2 **容器描边**：卡片、输入框、弹层轮廓。
  ///
  /// 与 [structural] 同值同族（v3 拍板），此别名用于表达语义。
  static Color containerOutline(BuildContext context) => LightSurfaces.resolve(
    context,
    LightSurfaces.cardBorder,
    dark: CupertinoColors.separator,
  );

  /// L3 **行间线**：分组内列表项之间（`CupertinoListSection.separatorColor`
  /// 一类 SDK 分隔线插槽）。
  static Color rowSeparator(BuildContext context) => structural(context);

  // ⚠️ **导航栏底线不在此类**：一律用常驻发丝线部件
  // （`app/widgets/nav_bar_hairline.dart` 的 `NavBarHairline` / `NavBarBottom`），
  // 并给导航栏显式 `border: null` 关掉 SDK 那条随滚动淡入的黑 30%。
  // 主人 2026-10-08 拍板：「常驻发丝线；本来叠在上面的线去掉 —— 用这条常驻的
  // 发丝线，而不是后加的分隔线。」走 border 形态必然回到「滚动才淡入、两条
  // 叠一起」的老问题，故此处刻意不提供 border 令牌。
}
