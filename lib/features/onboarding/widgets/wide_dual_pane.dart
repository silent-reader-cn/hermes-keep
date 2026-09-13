import 'package:flutter/cupertino.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/shell/adaptive_shell.dart';
import 'onboarding_hero_motion.dart';

/// 引导与安装体系的通用宽屏双栏骨架 Widget。
///
/// 遵循宽屏双栏铁律：
/// - 窗口宽 >= [kAdaptiveBreakpoint]（900）时：左 45% 品牌氛围区 + 右单列功能区（maxWidth 460，水平垂直居中）；
/// - 窗口宽 < 900（Android / 窄窗）时：完全渲染 [child]，现状单列形态零变化。
class WideDualPane extends StatelessWidget {
  const WideDualPane({
    super.key,
    required this.child,
    this.wideChild,
    this.brandPane,
    this.maxWidth = 460.0,
  });

  /// 窄屏回退 Widget（<900 宽时直接返回渲染）。
  final Widget child;

  /// 宽屏右侧栏功能区 Widget（若为空则回退到 [child]）。
  final Widget? wideChild;

  /// 可选自定义左侧品牌区 Widget。
  final Widget? brandPane;

  /// 右侧单列功能区的最大宽度（铁律规格 420~480，默认 460）。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (!isWide) {
      return child;
    }

    final effectiveRightChild = wideChild ?? child;
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // 左品牌氛围区（占 40-50%，此处采用 flex 45:55，即约 45%）
        Expanded(
          flex: 45,
          child: brandPane ?? OnboardingBrandPane(isDark: isDark),
        ),
        // 极简灰白分割线
        Container(
          width: 0.5,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
        ),
        // 右单列功能区（maxWidth 420~480 列内水平垂直居中，可滚动）
        Expanded(
          flex: 55,
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey('wide-dual-pane-form-container'),
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: effectiveRightChild,
            ),
          ),
        ),
      ],
    );
  }
}

/// 默认左侧品牌氛围区 Widget。
class OnboardingBrandPane extends StatelessWidget {
  /// Creates the default brand pane for the wide onboarding layout.
  const OnboardingBrandPane({super.key, required this.isDark});

  /// Whether the surrounding onboarding page uses the dark palette.
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('onboarding-brand-pane'),
      color: isDark
          ? const Color(0xFF0A0A0C)
          : CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: OnboardingHeroMotion(isDark: isDark),
    );
  }
}
