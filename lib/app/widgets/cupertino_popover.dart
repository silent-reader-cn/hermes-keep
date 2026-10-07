import 'package:flutter/cupertino.dart';

import 'adaptive_popover.dart';

/// Cupertino 风格锚点弹层（popover）薄封装。

///
/// 保留旧 API 兼容，所有新调用方推荐直接使用 [showAdaptivePopover]。
/// 本文件仅做转发，避免既有调用方大改。
Future<void> showCupertinoPopover({
  required BuildContext context,
  GlobalKey? anchorKey,
  Offset? position,
  Rect? anchorRect,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double preferredWidth = 360,
  double? minWidth,
  double? maxWidth,
  double preferredHeight = 420,
  PopoverPlacement placement = PopoverPlacement.auto,
  PopoverAlign align = PopoverAlign.end,
  Offset offset = Offset.zero,
  bool flipOnOverflow = true,
  bool barrierDismissible = true,
  double maxHeight = 420,
  double gap = 8,
  VoidCallback? onClosed,

  /// 卡片圆角（默认浮层族 [kAdaptivePopoverRadius] = 14；单个弹层可收一档）。
  double radius = kAdaptivePopoverRadius,
}) {
  return showAdaptivePopover(
    context: context,
    anchorKey: anchorKey,
    position: position,
    anchorRect: anchorRect,
    builder: builder,
    preferredWidth: preferredWidth,
    minWidth: minWidth,
    maxWidth: maxWidth,
    preferredHeight: preferredHeight,
    placement: placement,
    align: align,
    offset: offset,
    flipOnOverflow: flipOnOverflow,
    barrierDismissible: barrierDismissible,
    maxHeight: maxHeight,
    gap: gap,
    onClosed: onClosed,
    radius: radius,
  );
}
