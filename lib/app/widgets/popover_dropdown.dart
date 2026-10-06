import 'package:flutter/cupertino.dart';

import '../shell/adaptive_shell.dart' show kAdaptiveBreakpoint;
import '../theme/light_surfaces.dart';

/// 窄屏（`width < kAdaptiveBreakpoint`）浮层宽度。
const double kPopoverDropdownWidthNarrow = 228.0;

/// 宽屏（`width >= kAdaptiveBreakpoint`）浮层宽度。
///
/// 弹层家族重排（设计稿 `sketches/dialog-family-proposal.html` §2「推荐：宽 300」）：
/// 228 → 300，好让工作区项的「名称 + 路径」双行排得下。窄屏刻意维持 228 ——
/// 手机端逐像素不变。
const double kPopoverDropdownWidthWide = 300.0;

/// 浮层圆角（8 → 14）：与全仓弹层家族统一（设计稿 `.dlg{border-radius:14px}`）。
const double kPopoverDropdownRadius = 14.0;

/// 当前视口下的浮层宽度：宽屏 [kPopoverDropdownWidthWide] / 窄屏 [kPopoverDropdownWidthNarrow]。
///
/// 定位壳（`composer_meta_chips.dart` 的 `_FloatingMenu`）与卡片自身都走本函数，
/// 保证「定位用的宽度」与「卡片实际宽度」永远同源，不会一边 300 一边 228。
double popoverDropdownWidthFor(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint
    ? kPopoverDropdownWidthWide
    : kPopoverDropdownWidthNarrow;

/// 弹窗内部悬浮下拉卡片容器（用于模型选择、工作区选择等嵌入式下拉浮层）。
///
/// 宽度默认按视口分流（见 [popoverDropdownWidthFor]），圆角 [kPopoverDropdownRadius]，
/// 背景 [CupertinoColors.systemBackground]，边框 [CupertinoColors.separator]，
/// 投影 blurRadius 16 offset (0, 8)，并裁剪溢出内容。
class PopoverDropdownCard extends StatelessWidget {
  const PopoverDropdownCard({super.key, required this.child, this.width});

  final Widget child;

  /// 显式宽度；为 null（默认）时按视口取 [popoverDropdownWidthFor]。
  final double? width;

  @override
  Widget build(BuildContext context) {
    final bg = LightSurfaces.resolve(
      context,
      LightSurfaces.card,
      dark: CupertinoColors.systemBackground,
    );
    final separator = LightSurfaces.resolve(
      context,
      LightSurfaces.cardBorder,
      dark: CupertinoColors.separator,
    );
    return Container(
      width: width ?? popoverDropdownWidthFor(context),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kPopoverDropdownRadius),
        border: Border.all(color: separator),
        // Decorative shadow; not used for readable text or control boundaries.
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.systemGrey3
                .resolveFrom(context)
                .withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
