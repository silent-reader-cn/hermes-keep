import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import 'menu_metrics.dart';

/// 弹层菜单的**统一定位壳**（锚点上方优先，边界内收敛，按可用高度交付内容）。
///
/// 收拢了此前分散在两处的两份 `_FloatingMenu`（选择器 / 上下文弹层下拉）：
/// 二者定位逻辑几乎逐行相同，只有宽度默认值、下方偏移与左右对齐三处差异 ——
/// 那三处都做成了参数。
///
/// 与旧实现的关键差别在**高度**：
/// - 旧实现只把「估算高度」用于方向决策，卡片高度由内容自己撑（各处再各自硬编码
///   一个上限，选择器与上下文弹层都是 200）→ 内容一超就在行中间切断；
/// - 本壳把「该侧真实可用高度」（已按安全边距与 [maxHeight] 收紧）**交给内容**，
///   由内容用 `fitMenuHeight` 按行边界取整。方向决策仍沿用「放得下优先」的老口径。
class PopoverMenuShell extends StatelessWidget {
  /// 构造定位壳。
  const PopoverMenuShell({
    super.key,
    required this.anchorRect,
    required this.estimatedHeight,
    required this.oneRowHeight,
    required this.width,
    required this.onDismiss,
    required this.builder,
    this.alignToAnchorRight = false,
    this.gapAbove = 8,
    this.gapBelow = 4,
    this.maxHeight = kPopoverMenuMaxHeight,
  });

  /// 触发器在 overlay 坐标系中的全局矩形。
  final Rect anchorRect;

  /// 内容估算高度（= 全部行高 + 卡片开销），**仅用于展开方向决策**。
  final double estimatedHeight;

  /// 单行高度（可用高度的保底：再挤也不低于一行）。
  final double oneRowHeight;

  /// 菜单宽度。
  final double width;

  /// 是否与触发器**右缘**对齐（紧靠弹层右侧的快捷入口用）。
  final bool alignToAnchorRight;

  /// 向上展开时，菜单底边与触发器顶部的间隔。
  final double gapAbove;

  /// 向下展开时，菜单顶边与触发器底部的间隔。
  final double gapBelow;

  /// 高度上限（默认 [kPopoverMenuMaxHeight]）。
  final double maxHeight;

  /// 点空白处收起。
  final VoidCallback onDismiss;

  /// 内容构建：[available] 为该侧真实可用高度（调用方据此按行边界裁剪）。
  final Widget Function(BuildContext context, double available) builder;

  /// 屏幕安全边距（水平 clamp 与纵向底线）。
  static const double _safeMargin = 8.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final safeTop = media.padding.top + _safeMargin;
    final safeBottom = media.padding.bottom + _safeMargin;

    final maxLeft = math.max(_safeMargin, screenWidth - _safeMargin - width);
    final targetLeft = alignToAnchorRight
        ? anchorRect.right - width
        : anchorRect.left;
    final left = targetLeft.clamp(_safeMargin, maxLeft).toDouble();

    final spaceAbove = anchorRect.top - safeTop - gapAbove;
    final spaceBelow =
        screenHeight - anchorRect.bottom - safeBottom - gapBelow;

    // 方向决策沿用旧口径「放得下优先」；两侧都放不下时才比大小。
    final bool fitsAbove = spaceAbove >= estimatedHeight;
    final bool fitsBelow = spaceBelow >= estimatedHeight;
    final bool placeAbove;
    if (fitsAbove) {
      placeAbove = true;
    } else if (fitsBelow) {
      placeAbove = false;
    } else {
      placeAbove = spaceAbove >= spaceBelow;
    }

    final sideSpace = placeAbove ? spaceAbove : spaceBelow;
    final available = math.min(
      maxHeight,
      math.max(oneRowHeight, sideSpace),
    );

    final positioned = Positioned(
      left: left,
      width: width,
      top: placeAbove ? null : anchorRect.bottom + gapBelow,
      bottom: placeAbove ? screenHeight - anchorRect.top + gapAbove : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: available),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: Builder(
            builder: (innerContext) => builder(innerContext, available),
          ),
        ),
      ),
    );

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
            ),
          ),
          positioned,
        ],
      ),
    );
  }
}
