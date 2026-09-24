import 'package:flutter/cupertino.dart';

import '../theme/light_surfaces.dart';

/// 轻量 hover 提示（#153）。
///
/// 为什么不用 Material 的 `Tooltip`：本项目约定「业务 UI 不混入 Material」，
/// 而 `Tooltip` 属于 material 库；`Semantics(tooltip:)` 又只有无障碍语义、
/// **桌面悬停时不显示视觉提示**（主人要的是真 hover tip）。
/// 故用 `OverlayPortal` 自绘一个 Cupertino 风格的浮层 —— 不参与父布局、
/// 不会被侧栏的 Column/裁剪影响，也不会改变行高。
class SidebarHoverTip extends StatefulWidget {
  const SidebarHoverTip({
    super.key,
    required this.message,
    required this.child,
    this.tipKey,
    this.alignment = const Alignment(0.0, -1.0),
  });

  /// 提示文案；为空则不显示浮层。
  final String message;

  /// 触发区内容。
  final Widget child;

  /// 浮层 key（测试定位用）。
  final Key? tipKey;

  /// 浮层相对触发区的位置（默认贴触发区上方）。
  final Alignment alignment;

  @override
  State<SidebarHoverTip> createState() => _SidebarHoverTipState();
}

class _SidebarHoverTipState extends State<SidebarHoverTip> {
  final OverlayPortalController _controller = OverlayPortalController();
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) return widget.child;

    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return OverlayPortal(
      controller: _controller,
      // 浮层：深色圆角胶囊 + 白字（Cupertino 反色提示面），不参与布局。
      overlayChildBuilder: (context) {
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomSingleChildLayout(
              delegate: _TipLayoutDelegate(anchor: context.findRenderObject()),
              child: Container(
                key: widget.tipKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                decoration: BoxDecoration(
                  color: isLight
                      ? const Color(0xE61C1C1E)
                      : LightSurfaces.resolve(
                          context,
                          const Color(0xFFE5E5EA),
                          dark: const Color(0xFF48484A),
                        ),
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: Text(
                  widget.message,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isLight
                        ? CupertinoColors.white
                        : CupertinoColors.label,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) {
          _hovering = true;
          _controller.show();
        },
        onExit: (_) {
          _hovering = false;
          _controller.hide();
        },
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    if (_hovering) _controller.hide();
    super.dispose();
  }
}

/// 把浮层定位到锚点上方居中。
class _TipLayoutDelegate extends SingleChildLayoutDelegate {
  const _TipLayoutDelegate({required this.anchor});

  final RenderObject? anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final box = anchor;
    if (box is! RenderBox || !box.hasSize) return Offset.zero;
    final topLeft = box.localToGlobal(Offset.zero);
    final dx = topLeft.dx + (box.size.width - childSize.width) / 2;
    final dy = topLeft.dy - childSize.height - 4.0;
    // 越界保护：贴左/贴顶时回收到可视区内。
    return Offset(
      dx.clamp(0.0, (size.width - childSize.width).clamp(0.0, size.width)),
      dy < 0 ? topLeft.dy + box.size.height + 4.0 : dy,
    );
  }

  @override
  bool shouldRelayout(_TipLayoutDelegate oldDelegate) => false;
}
