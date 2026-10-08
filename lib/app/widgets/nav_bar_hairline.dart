import 'package:flutter/cupertino.dart';

import '../theme/divider_tokens.dart';

/// 导航栏底部**常驻**发丝结构线（结构线 L1，0.5 逻辑像素）。
///
/// 主人 2026-10-08 拍板：「常驻发丝线；本来叠在上面的线去掉 —— 用这条常驻的
/// 发丝线，而不是后加的分隔线」。即：**全应用导航栏一律走本件**，并且必须同时
/// 给 `CupertinoNavigationBar` 传 `border: null`。
///
/// 为什么必须 `border: null`：SDK 的 `CupertinoNavigationBar` 默认
/// `border = _kDefaultNavBarBorder`（`#4D000000` 黑 30%，`width: 0.0` = 一个物理
/// 像素），它在 `CupertinoPageScaffold` 内由滚动通知驱动、10 逻辑像素内从透明
/// 淡入（`_scrollAnimationValue`；reverse 列表取 `extentAfter` ⇒ 内容能滚就常亮）
/// ⇒ 与常驻发丝线叠加，就成了「新会话浅、有内容的会话一滚动就变深」。
///
/// 用法（宽屏固定条 / 独立页导航栏）：
/// ```dart
/// CupertinoNavigationBar(
///   border: null,
///   bottom: const NavBarHairline(),
///   middle: ...,
/// )
/// ```
/// 页面自带 `bottom`（操作横幅等）时改用 [NavBarBottom] 叠起来。
class NavBarHairline extends StatelessWidget implements PreferredSizeWidget {
  const NavBarHairline({super.key});

  /// 线高（逻辑像素），与 [Dividers.hairlineWidth] 同源。
  static const double hairlineHeight = Dividers.hairlineWidth;

  @override
  Size get preferredSize => const Size.fromHeight(hairlineHeight);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: hairlineHeight,
    width: double.infinity,
    child: ColoredBox(color: Dividers.structural(context)),
  );
}

/// 把页面既有的 `bottom` 部件（操作横幅、分段控件等）与 [NavBarHairline]
/// 叠成一列，**发丝线永远贴在最下沿**。
///
/// 高度 = `bottom` 高度 + 0.5；`CupertinoNavigationBar` 会把 `bottom` 的
/// `preferredSize` 计入自身总高（44 + bottom + 顶部安全区），因此宽屏下导航栏
/// 总高 = 44.5，与侧栏品牌栏（44 + 0.5）严格同轴。
class NavBarBottom extends StatelessWidget implements PreferredSizeWidget {
  const NavBarBottom({super.key, this.bottom});

  /// 页面自定义的底部部件（可为空，此时只剩发丝线）。
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
    (bottom?.preferredSize.height ?? 0.0) + NavBarHairline.hairlineHeight,
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // ⚠️ 必须按 `preferredSize` 钉高：`PreferredSizeWidget` 只声明高度、
      // 不约束自身渲染（`PreferredSize` 是直通壳），而 Column 给非 flex 子件
      // 的约束是**无限高** ⇒ 一个「自然高 > 声明高」的横幅（如 git 操作横幅
      // 声明 52 / 自然 79）会撑破本列。窄屏 delegate 与 SDK 都是按声明高
      // 定死布局的，这里保持一致（像素行为不变）。
      if (bottom != null)
        SizedBox(
          height: bottom!.preferredSize.height,
          child: bottom,
        ),
      const NavBarHairline(),
    ],
  );
}
