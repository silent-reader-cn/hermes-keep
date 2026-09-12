import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../chat_providers.dart';

/// 聊天大纲悬浮面板（active.md §7：标题栏点击展开用户轮次列表）。
///
/// 复用 context_window_popover 的悬浮菜单框架：
/// - `OverlayEntry` 悬浮，不占主 Widget 树高度。
/// - 向下展开，紧贴导航栏底部，越界时收紧高度由滚动兜底。
/// - 水平以锚点居中 clamp 屏幕边距。
/// - 全屏透明 barrier 点外部收起。
class ChatOutlineSheet {
  const ChatOutlineSheet._();

  /// 面板卡片宽度。
  static const double _menuWidth = 290;

  /// 向下展开时顶部与锚点底部的间距（留出小间距，避免贴/盖导航栏）。
  static const double _gapBelow = 12;

  /// 面板最大高度。
  static const double _maxHeight = 340;

  /// 安全边距（水平 clamp）。
  static const double _safeMargin = 8;

  /// 行高（CupertinoButton minimumSize 基准）。
  static const double _rowHeight = 48.0;

  /// 估算面板高度（行数 × 行高，上限 [_maxHeight]）。
  static double estimateHeight(int rowCount) {
    const border = 2.0;
    return math.min(_maxHeight, rowCount * _rowHeight + border);
  }

  /// 插入大纲面板 OverlayEntry 并返回（供持有者 remove/dispose）。
  ///
  /// [anchorRect]：锚点（标题栏 middle widget）在 overlay 坐标系的全局矩形，
  ///   通过 `RenderBox.localToGlobal(ancestor: overlayRenderBox)` 换算。
  /// [selectedRenderId]：当前视口首可见用户轮次 renderId，用于高亮行。
  /// [onJump]：用户点击某轮次回调，参数为 (renderId, loadedIndex)。
  /// [onDismiss]：面板关闭回调（点外部或点某行后由内部调用再传出）。
  static OverlayEntry insert({
    required OverlayState overlay,
    required WidgetRef ref,
    required Rect anchorRect,
    required String sessionId,
    required String? selectedRenderId,
    required void Function(String renderId, int loadedIndex) onJump,
    required VoidCallback onDismiss,
  }) {
    final entries = ref.read(chatOutlineEntriesProvider(sessionId));
    final estimatedH = estimateHeight(entries.length);

    final overlayEntry = OverlayEntry(
      builder: (ctx) => _ChatOutlineOverlay(
        anchorRect: anchorRect,
        sessionId: sessionId,
        estimatedHeight: estimatedH,
        selectedRenderId: selectedRenderId,
        onJump: onJump,
        onDismiss: onDismiss,
      ),
    );
    overlay.insert(overlayEntry);
    return overlayEntry;
  }
}

/// 大纲面板 overlay 完整视图（barrier + 定位卡片）。
class _ChatOutlineOverlay extends ConsumerWidget {
  const _ChatOutlineOverlay({
    required this.anchorRect,
    required this.sessionId,
    required this.estimatedHeight,
    required this.selectedRenderId,
    required this.onJump,
    required this.onDismiss,
  });

  final Rect anchorRect;
  final String sessionId;
  final double estimatedHeight;
  final String? selectedRenderId;
  final void Function(String renderId, int loadedIndex) onJump;
  final VoidCallback onDismiss;

  static const double _menuWidth = ChatOutlineSheet._menuWidth;
  static const double _safeMargin = ChatOutlineSheet._safeMargin;
  static const double _gapBelow = ChatOutlineSheet._gapBelow;
  static const double _maxHeight = ChatOutlineSheet._maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final safeBottom = media.padding.bottom + _safeMargin;

    // 水平：以锚点为中心，clamp 到屏幕内。
    final anchorCenterX = anchorRect.left + anchorRect.width / 2;
    final idealLeft = anchorCenterX - _menuWidth / 2;
    final left = idealLeft.clamp(
      _safeMargin,
      (screenWidth - _menuWidth - _safeMargin).clamp(_safeMargin, screenWidth),
    );

    // 垂直：向下，从锚点底部 + gapBelow 处开始。
    final downTop = anchorRect.bottom + _gapBelow;
    final downAvail = math.max(0.0, screenHeight - downTop - safeBottom);
    final menuHeight = math
        .max(
          math.min(estimatedHeight, downAvail),
          46.0, // 保底：至少一行高
        )
        .clamp(0.0, _maxHeight);

    return SizedBox.expand(
      child: Stack(
        children: [
          // 透明 barrier：点外部收起
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
            ),
          ),
          // 大纲卡片
          Positioned(
            left: left,
            top: downTop,
            width: _menuWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // 阻止点击穿透到 barrier
              child: _OutlineCard(
                sessionId: sessionId,
                selectedRenderId: selectedRenderId,
                maxHeight: menuHeight,
                onRowTap: (renderId, loadedIndex) {
                  onJump(renderId, loadedIndex);
                  onDismiss();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 大纲卡片：圆角容器 + 内容列表。
class _OutlineCard extends ConsumerWidget {
  const _OutlineCard({
    required this.sessionId,
    required this.selectedRenderId,
    required this.maxHeight,
    required this.onRowTap,
  });

  final String sessionId;
  final String? selectedRenderId;
  final double maxHeight;
  final void Function(String renderId, int loadedIndex) onRowTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(chatOutlineEntriesProvider(sessionId));

    return Container(
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemBackground,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 0.5,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.divider,
                      dark: CupertinoColors.separator,
                    ),
                    margin: const EdgeInsets.only(left: 46),
                  ),
                _OutlineRow(
                  key: ValueKey('outline-row-${entries[i].renderId}'),
                  entry: entries[i],
                  selected: entries[i].renderId == selectedRenderId,
                  onTap: () =>
                      onRowTap(entries[i].renderId, entries[i].loadedIndex),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 大纲单行：序号徽章 + 预览文本 + 选中态。
class _OutlineRow extends StatelessWidget {
  const _OutlineRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final OutlineEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeBlue = LightSurfaces.resolve(
      context,
      statusBlueText.resolveFrom(context),
      dark: CupertinoColors.activeBlue,
    );
    final labelColor = selected
        ? activeBlue
        : CupertinoColors.label.resolveFrom(context);

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      alignment: Alignment.centerLeft,
      onPressed: onTap,
      child: Row(
        children: [
          // 序号徽章
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: selected
                  ? activeBlue.withValues(alpha: 0.15)
                  : LightSurfaces.resolve(
                      context,
                      LightSurfaces.page,
                      dark: CupertinoColors.systemGrey5,
                    ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${entry.index}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? activeBlue
                      : LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          dark: CupertinoColors.secondaryLabel,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 预览文本
          Expanded(
            child: Text(
              entry.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: labelColor,
              ),
            ),
          ),
          // 当前轮次指示点
          if (selected) ...[
            const SizedBox(width: 6),
            Icon(CupertinoIcons.circle_fill, size: 7, color: activeBlue),
          ],
        ],
      ),
    );
  }
}
