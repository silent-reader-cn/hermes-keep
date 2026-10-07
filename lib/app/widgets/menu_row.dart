import 'package:flutter/cupertino.dart';

import '../theme/light_surfaces.dart';

/// 暗色「选中 / 悬停 / 按下」三档面色。
///
/// 浅色沿用既有的 [LightSurfaces.selectedSurface] / `hoverSurface` / `pressed`
/// 三个令牌；暗色此前由 `CupertinoButton` 的按压变暗兜底，没有对应面色，
/// 故在此补齐（值取 iOS 暗色填充族的等效量），保证两态**各有面色、同一套语义**。
const Color _kDarkSelectedSurface = Color.fromRGBO(120, 120, 128, 0.24);
const Color _kDarkHoverSurface = Color.fromRGBO(120, 120, 128, 0.14);
const Color _kDarkPressedSurface = Color.fromRGBO(120, 120, 128, 0.32);

/// 弹层菜单行的**唯一实现**：一套布局，两态只差配色。
///
/// ## 为什么必须唯一（本组件存在的理由）
///
/// 此前菜单行按主题分成两支：浅色走 `CupertinoListTile`、暗色走
/// `CupertinoButton`。这两个控件**内部布局并不相同** —— `CupertinoListTile`
/// 把 title 装在 `Column(mainAxisAlignment: spaceBetween, mainAxisSize: max)`
/// 里，当外层 `SizedBox` 把行高压到鼠标档（30 / 36 / 46）时，`spaceBetween`
/// 会把内容**顶到上沿**；`CupertinoButton` 则是居中的。于是同一个菜单项在
/// 明暗两态下**布局不同**（实测浅色比行中心高 8pt，暗色 0pt）—— 这不是配色
/// 差异，是封装漏了：**行的布局不该由主题分支决定**。
///
/// 本组件把规则收拢成一条：
/// - **布局恒定**：定高 + `Row(crossAxisAlignment: center)`，任何主题都垂直居中；
/// - **配色分态**：面色 / 图标色一律 [LightSurfaces.resolve] 两态各自定色；
/// - **按下自带面色**：用 `ColoredBox` 画面色（浅色按下 = [LightSurfaces.pressed]，
///   既有视觉契约），不再借用 `CupertinoListTile.backgroundColorActivated`。
///
/// 行内容由 [child] 决定（单行文字 / 「名称 + 路径」双行），图标列与右侧
/// 附属物由 [icon] / [trailing] 决定 —— 三个弹窗族（操作菜单、选择器、
/// 上下文弹层下拉）因此共用同一条行骨架。
class MenuRow extends StatefulWidget {
  /// 构造一行菜单项。
  const MenuRow({
    super.key,
    required this.height,
    required this.child,
    this.onTap,
    this.icon,
    this.iconSize = 14,
    this.iconBoxWidth = 16,
    this.iconGap = 10,
    this.iconColor,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });

  /// 行高（定高；鼠标档 30 / 选择器 36 / 双行工作区 46 / 窄屏触屏档 44）。
  final double height;

  /// 行内容（已由调用方定好字号与颜色）。
  final Widget child;

  /// 点击回调；[enabled] 为 false 时不下发。
  final VoidCallback? onTap;

  /// 可选前置图标（画在 [iconBoxWidth] 宽的盒子里，保证各行的文字左缘对齐）。
  final IconData? icon;

  /// 图标字号。
  final double iconSize;

  /// 图标盒宽度（决定文字左缘：盒宽 + [iconGap]）。
  final double iconBoxWidth;

  /// 图标与内容之间的间距。
  final double iconGap;

  /// 图标颜色；为 null 时取次级文字色。动作菜单的图标与标签同色，故由调用方传入。
  final Color? iconColor;

  /// 右侧附属物（勾选 / 快捷键列）；间距由调用方自带。
  final Widget? trailing;

  /// 选中态：填 [LightSurfaces.selectedSurface] 面色。
  ///
  /// 选中语言 = **中性灰底 + 蓝字 + 右勾**（三样，由调用方给文字/勾的颜色）。
  /// 曾经还有一条左侧 2px 蓝竖条（设计稿 `.prow.sel::before`），已按主人
  /// 2026-10-07 的裁定**移除**（原话「不要左侧的那个蓝色高亮条 很丑」）——
  /// 故本组件不再提供该能力，避免它被顺手用回来。
  final bool selected;

  /// 是否可点（false 时不响应、不显按下态、语义置灰）。
  final bool enabled;

  /// 内容左右内边距。
  final EdgeInsetsGeometry padding;

  @override
  State<MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<MenuRow> {
  bool _pressed = false;
  bool _hovered = false;

  /// 面色优先级：按下 > 选中 > 悬停 > 常态。
  ///
  /// 按下必须压过选中：否则「点当前项」在视觉上没有任何反馈。
  Color _background(BuildContext context) {
    if (_pressed && widget.enabled) {
      return LightSurfaces.resolve(
        context,
        LightSurfaces.pressed,
        dark: _kDarkPressedSurface,
      );
    }
    if (widget.selected) {
      return LightSurfaces.resolve(
        context,
        LightSurfaces.selectedSurface,
        dark: _kDarkSelectedSurface,
      );
    }
    if (_hovered && widget.enabled) {
      return LightSurfaces.resolve(
        context,
        LightSurfaces.hoverSurface,
        dark: _kDarkHoverSurface,
      );
    }
    return LightSurfaces.resolve(
      context,
      LightSurfaces.card,
      dark: CupertinoColors.systemBackground,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        widget.iconColor ??
        LightSurfaces.resolve(
          context,
          LightSurfaces.textSecondary,
          dark: CupertinoColors.secondaryLabel,
        );

    final content = ColoredBox(
      color: _background(context),
      child: Padding(
        padding: widget.padding,
        child: Row(
          // 显式居中：这是本组件存在的意义 —— 绝不再靠控件自身的默认对齐。
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              SizedBox(
                width: widget.iconBoxWidth,
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: effectiveIconColor,
                ),
              ),
              SizedBox(width: widget.iconGap),
            ],
            Expanded(child: widget.child),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) {
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered || _pressed) {
            setState(() {
              _hovered = false;
              _pressed = false;
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapUp: widget.enabled
              ? (_) => setState(() => _pressed = false)
              : null,
          onTapCancel: widget.enabled
              ? () => setState(() => _pressed = false)
              : null,
          onTap: widget.enabled ? widget.onTap : null,
          child: SizedBox(height: widget.height, child: content),
        ),
      ),
    );
  }
}
