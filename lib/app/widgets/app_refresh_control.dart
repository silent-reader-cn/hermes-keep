import 'package:flutter/cupertino.dart';

import '../shell/adaptive_shell.dart' show kAdaptiveBreakpoint;

/// 全 App 统一尺寸的下拉刷新控件（宽屏侧栏 + 各功能页共用）。
///
/// 为什么需要它：Flutter 的 [CupertinoSliverRefreshControl] 默认指示器是
/// **库内写死**的 radius 14（`_kActivityIndicatorRadius`），直径约 28dp，
/// 指示器区固定 60dp。本项目正文基准 15pt、宽屏侧栏行文字仅 12.5pt，
/// 默认尺寸在侧栏里明显偏大（主人实机反馈「Loading 图标太大」）。
///
/// 这里把「指示器大小 / 指示器区高度」收敛到与全 App 文字层级协调的一档，
/// 并把构建逻辑集中一处，避免 10 个页面各自用默认值各显其大。
///
/// 手感取舍：**只动观感，不动拉动距离** —— [triggerPullDistance] 保持 SDK 的
/// 100（改它等于改「要拉多深才触发」，与尺寸反馈无关）。
class AppRefreshControl extends StatelessWidget {
  const AppRefreshControl({super.key, required this.onRefresh});

  /// 宽屏指示器半径：8 → 直径约 16dp（SDK 默认 14 → 约 28dp）。
  ///
  /// 参照系：侧栏行内「进行中」小圆点 radius 6、品牌行刷新按钮 radius 10。
  static const double wideIndicatorRadius = 8.0;

  /// 宽屏指示器区高度：48（SDK 默认 60）。
  static const double wideIndicatorExtent = 48.0;

  /// 窄屏沿用 SDK 默认（radius 14）—— 本轮尺寸收敛**只针对宽屏**，
  /// 手机端下拉刷新保持原口径逐像素不变。
  static const double narrowIndicatorRadius = 14.0;

  /// 窄屏指示器区高度（SDK 默认 60）。
  static const double narrowIndicatorExtent = 60.0;

  /// 触发刷新的拉动距离（SDK 默认 100，宽窄一致）。断言要求 ≥ 指示器区高。
  static const double triggerPullDistance = 100.0;

  /// 与 `CupertinoSliverRefreshControl.onRefresh` 同义。
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    final radius = isWide ? wideIndicatorRadius : narrowIndicatorRadius;
    final extent = isWide ? wideIndicatorExtent : narrowIndicatorExtent;
    return CupertinoSliverRefreshControl(
      refreshIndicatorExtent: extent,
      refreshTriggerPullDistance: triggerPullDistance,
      builder:
          (
            context,
            refreshState,
            pulledExtent,
            refreshTriggerPullDistance,
            refreshIndicatorExtent,
          ) => _buildIndicator(
            refreshState,
            pulledExtent,
            refreshTriggerPullDistance,
            refreshIndicatorExtent,
            radius,
          ),
      onRefresh: onRefresh,
    );
  }

  /// 与 SDK 默认 builder 同构，仅替换半径与垂直落点（按新区高居中）。
  static Widget _buildIndicator(
    RefreshIndicatorMode refreshState,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
    double radius,
  ) {
    final double percentageComplete =
        (pulledExtent / refreshTriggerPullDistance).clamp(0.0, 1.0);
    // 用 Stack/Positioned 显式落点：指示器自身会随尺寸做内部位移，
    // 靠 Padding 推不可控（与 SDK 内的注释同因）。
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            top: (refreshIndicatorExtent - radius * 2) / 2,
            left: 0.0,
            right: 0.0,
            child: _indicatorFor(refreshState, percentageComplete, radius),
          ),
        ],
      ),
    );
  }

  static Widget _indicatorFor(
    RefreshIndicatorMode refreshState,
    double percentageComplete,
    double radius,
  ) {
    switch (refreshState) {
      case RefreshIndicatorMode.drag:
        // 拖动中逐个刻度浮出；透明度曲线沿用 SDK 取值（对齐 iOS 13.5）。
        const Curve opacityCurve = Interval(0.0, 0.35, curve: Curves.easeInOut);
        return Opacity(
          opacity: opacityCurve.transform(percentageComplete),
          child: CupertinoActivityIndicator.partiallyRevealed(
            radius: radius,
            progress: percentageComplete,
          ),
        );
      case RefreshIndicatorMode.armed:
      case RefreshIndicatorMode.refresh:
        return CupertinoActivityIndicator(radius: radius);
      case RefreshIndicatorMode.done:
        // 松手后随进度收缩（与 SDK 默认一致）。
        return CupertinoActivityIndicator(radius: radius * percentageComplete);
      case RefreshIndicatorMode.inactive:
        return const SizedBox.shrink();
    }
  }
}
