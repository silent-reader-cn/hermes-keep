import 'package:flutter/cupertino.dart';

import '../theme/light_surfaces.dart';

/// 弹窗内部悬浮下拉卡片容器（用于模型选择、工作区选择等嵌入式下拉浮层）。
///
/// 宽度固定 228，圆角 8，背景 [CupertinoColors.systemBackground]，边框 [CupertinoColors.separator]，
/// 投影 blurRadius 16 offset (0, 8)，并裁剪溢出内容。
class PopoverDropdownCard extends StatelessWidget {
  const PopoverDropdownCard({super.key, required this.child, this.width = 228});

  final Widget child;
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
      width: width,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
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
