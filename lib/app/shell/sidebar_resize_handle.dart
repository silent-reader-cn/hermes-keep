import 'package:flutter/cupertino.dart';

import '../theme/light_surfaces.dart';

/// 宽屏双栏外壳中侧栏与内容区之间的可拖拽调整宽度手柄。
///
/// 视觉上呈现 1px 宽的分隔细线，外部扩展命中热区（默认 9px），
/// 鼠标悬停时展示左右调整光标 [SystemMouseCursors.resizeLeftRight]，
/// 支持水平拖拽调整左侧栏宽度。
class SidebarResizeHandle extends StatelessWidget {
  const SidebarResizeHandle({
    super.key,
    required this.onDragUpdate,
    this.onDragEnd,
    this.width = 9.0,
    this.lineWidth = 1.0,
  });

  /// 拖拽手柄热区总宽度（像素），默认 9.0。
  final double width;

  /// 视觉分隔线宽度（像素），默认 1.0。
  final double lineWidth;

  /// 水平拖拽更新回调。
  final GestureDragUpdateCallback onDragUpdate;

  /// 水平拖拽结束回调。
  final GestureDragEndCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: const ValueKey('adaptive-shell-resize-handle'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: onDragEnd,
        child: SizedBox(
          width: width,
          child: Center(
            child: Container(
              width: lineWidth,
              // Structural divider; the unchanged hit area and resize cursor
              // identify the drag control independently of this decorative line.
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.divider,
                dark: CupertinoColors.separator,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
