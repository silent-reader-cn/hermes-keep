/// 宽屏左栏分类导航骨架（批 3 · 设置页 P1 / 记忆页 P6 共用）。
///
/// 尺寸与分界取自批 3 设计稿（两页同一套）：栏宽 220（含 10 内边距）、
/// 右侧 0.5px 分栏线、行高 32、圆角 7、12.5pt 文案、16pt 图标；
/// 选中态走 L2 —— 浅色「中性灰底 + 蓝字/蓝图标」（底 [LightSurfaces.selectedSurface]，
/// 前景 [LightSurfaces.selectionForeground]），暗色沿用既有口径
/// （primary 12% 底 + primary 前景），不改动暗色实参。
///
/// 只负责「长什么样 + 点哪到哪」，不含任何分区语义：分类项与内容由调用页决定。
library;

import 'package:flutter/cupertino.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/layout_tokens.dart';
// 左栏宽度来自 `app/theme/layout_tokens.dart`（G1-G4 令牌，单一事实来源）；
// 这里 export 一下，使既有「只 import 本文件」的调用点继续拿得到同名符号。
export '../../app/theme/layout_tokens.dart' show kWideNavRailWidth;

/// 左导航行文案（浅色设计稿 `#3A3A3C`，对 page 10.17:1）；深色回退 label 语义色。
const Color _kNavRowLabel = Color(0xFF3A3A3C);

/// 左导航行图标与分组标题（浅色设计稿 `#8A8A90`，对 page 3.08:1）；
/// 深色回退 secondaryLabel。
const Color _kNavRowIcon = Color(0xFF8A8A90);

/// 分栏线/组间线：浅色与卡片描边同族（[LightSurfaces.divider]），暗色沿用 separator。
Color _railSeparator(BuildContext context) => LightSurfaces.resolve(
  context,
  LightSurfaces.divider,
  dark: CupertinoColors.separator,
);

/// 左侧分类导航栏骨架：固定宽 [kWideNavRailWidth]、右侧 0.5px 分栏线、纵向排列。
class WideNavRail extends StatelessWidget {
  const WideNavRail({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kWideNavRailWidth,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: _railSeparator(context), width: 0.5),
        ),
      ),
      child: Column(
        // 必须 max：分栏线是 Container 的右边框，min 会让它只到内容底部（实测现象）。
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// 分组标题（10pt w600 次级灰）。
class WideNavRailGroupLabel extends StatelessWidget {
  const WideNavRailGroupLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
      child: Text(
        label,
        style: TextStyle(
          fontSize: kFontSectionTitle,
          fontWeight: FontWeight.w600,
          color: LightSurfaces.resolve(
            context,
            _kNavRowIcon,
            dark: CupertinoColors.secondaryLabel,
          ),
        ),
      ),
    );
  }
}

/// 组间分隔线（0.5px，左右 6 内缩）。
class WideNavRailSeparator extends StatelessWidget {
  const WideNavRailSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Container(height: 0.5, color: _railSeparator(context)),
    );
  }
}

/// 单个导航行：16pt 图标 + 12.5pt 文案，行高 32、圆角 7，选中态走 L2。
class WideNavRailRow extends StatelessWidget {
  const WideNavRailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    // L2 选中态：浅色中性灰 .16 + #005FB8 前景；暗色沿用 primary 12%（取值不变）。
    final activeFg = isLight
        ? LightSurfaces.selectionForeground
        : CupertinoTheme.of(context).primaryColor;
    final activeBg = isLight
        ? LightSurfaces.selectedSurface
        : activeFg.withValues(alpha: 0.12);
    final labelFg = selected
        ? activeFg
        : LightSurfaces.resolve(
            context,
            _kNavRowLabel,
            dark: CupertinoColors.label,
          );
    final iconFg = selected
        ? activeFg
        : LightSurfaces.resolve(
            context,
            _kNavRowIcon,
            dark: CupertinoColors.secondaryLabel,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(double.infinity, 32),
          borderRadius: BorderRadius.circular(7),
          color: selected ? activeBg : CupertinoColors.transparent,
          onPressed: onTap,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: iconFg),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: kFontNavItem, color: labelFg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
