import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/popover_dropdown.dart';
import '../../../core/models/workspace.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../chat_providers.dart';

/// 聊天输入区「工作区 / 模型」元信息 chip 组（#145）。
///
/// 紧邻发送按钮左侧常驻显示当前会话绑定的工作区与模型，点击向上弹出选择器浮层。
/// 支持四态：
/// 1. 正常：会话已设值，显示「[图标] 键名 值 [chevron]」；
/// 2. 无值：会话未设值，虚线描边 + l10n「选择工作区」/「跟随默认模型」；
/// 3. 工作区失效：红字「工作区已失效」，描边偏红；判定条件为 roots 列表非空且找不到该 path；
/// 4. 悬停：描边加深一档，无阴影不变形。
class ComposerMetaChips extends ConsumerStatefulWidget {
  const ComposerMetaChips({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  ConsumerState<ComposerMetaChips> createState() => _ComposerMetaChipsState();
}

enum _ActiveMenuType {
  none,
  workspace,
  model,
}

class _ComposerMetaChipsState extends ConsumerState<ComposerMetaChips> {
  OverlayEntry? _activeMenuEntry;
  _ActiveMenuType _activeMenuType = _ActiveMenuType.none;

  final GlobalKey _workspaceKey = GlobalKey();
  final GlobalKey _modelKey = GlobalKey();

  bool _workspaceHovered = false;
  bool _modelHovered = false;

  @override
  void didUpdateWidget(covariant ComposerMetaChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _removeMenu();
    }
  }

  @override
  void dispose() {
    _removeMenu();
    super.dispose();
  }

  void _removeMenu() {
    _activeMenuEntry?.remove();
    _activeMenuEntry = null;
    _activeMenuType = _ActiveMenuType.none;
  }

  Rect? _resolveAnchorRect(GlobalKey key, OverlayState overlay) {
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      box.size.width,
      box.size.height,
    );
  }

  void _toggleWorkspaceMenu() {
    if (_activeMenuType == _ActiveMenuType.workspace) {
      _removeMenu();
      setState(() {});
      return;
    }
    _removeMenu();
    final overlay = Overlay.of(context);
    final anchor = _resolveAnchorRect(_workspaceKey, overlay);
    if (anchor == null) return;

    final rootsAsync = ref.read(workspaceRootsProvider);
    final roots = rootsAsync.valueOrNull ?? const <WorkspaceRoot>[];
    final rowCount = roots.length + (roots.isEmpty ? 2 : 1);

    final entry = OverlayEntry(
      builder: (entryContext) => _FloatingMenu(
        anchorRect: anchor,
        estimatedHeight: _estimateMenuHeight(rowCount),
        onDismiss: () {
          _removeMenu();
          if (mounted) setState(() {});
        },
        child: _buildWorkspaceMenu(entryContext),
      ),
    );
    _activeMenuEntry = entry;
    _activeMenuType = _ActiveMenuType.workspace;
    overlay.insert(entry);
    setState(() {});
  }

  void _toggleModelMenu() {
    if (_activeMenuType == _ActiveMenuType.model) {
      _removeMenu();
      setState(() {});
      return;
    }
    _removeMenu();
    final overlay = Overlay.of(context);
    final anchor = _resolveAnchorRect(_modelKey, overlay);
    if (anchor == null) return;

    final modelsAsync = ref.read(availableModelIdsProvider);
    final models = modelsAsync.valueOrNull ?? const <String>[];
    final entry = OverlayEntry(
      builder: (entryContext) => _FloatingMenu(
        anchorRect: anchor,
        estimatedHeight: _estimateMenuHeight(models.length + 1),
        onDismiss: () {
          _removeMenu();
          if (mounted) setState(() {});
        },
        child: _buildModelMenu(entryContext),
      ),
    );
    _activeMenuEntry = entry;
    _activeMenuType = _ActiveMenuType.model;
    overlay.insert(entry);
    setState(() {});
  }

  static double _estimateMenuHeight(int rowCount) {
    const rowHeight = 44.0;
    const cardBorder = 2.0;
    const maxMenuHeight = 200.0;
    return math.min<double>(maxMenuHeight, rowCount * rowHeight + cardBorder);
  }

  Future<void> _selectWorkspace(String? path) async {
    _removeMenu();
    if (mounted) setState(() {});
    final ok = await ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .updateSessionSettings(workspace: path);
    if (!ok && mounted) {
      final l10n = AppLocalizations.of(context);
      ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .setNotice(l10n.actionFailed);
    }
  }

  void _selectModel(String? model) {
    _removeMenu();
    if (mounted) setState(() {});
    ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .selectModel(model);
  }

  Widget _buildWorkspaceMenu(BuildContext menuContext) {
    final l10n = AppLocalizations.of(menuContext);
    final currentWorkspace = ref
        .watch(chatControllerProvider(widget.sessionId))
        .workspace;
    final rootsAsync = ref.watch(workspaceRootsProvider);
    final roots = rootsAsync.valueOrNull ?? const <WorkspaceRoot>[];
    final isLoading = rootsAsync.isLoading;

    final secondary = LightSurfaces.resolve(
      menuContext,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    return PopoverDropdownCard(
      child: isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CupertinoActivityIndicator(radius: 8),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (roots.isNotEmpty) ...[
                      for (final w in roots)
                        _WorkspaceRow(
                          key: ValueKey('composer-workspace-item-${w.path}'),
                          label: (w.name != null && w.name!.trim().isNotEmpty)
                              ? '${w.name} (${w.path})'
                              : (w.path ?? ''),
                          selected: currentWorkspace == w.path,
                          onTap: () => _selectWorkspace(w.path),
                        ),
                      _WorkspaceRow(
                        key: const ValueKey('composer-workspace-item-default'),
                        label: l10n.followSessionDefaultWorkspace,
                        selected:
                            currentWorkspace == null ||
                            currentWorkspace.trim().isEmpty,
                        onTap: () => _selectWorkspace(null),
                      ),
                    ] else ...[
                      _WorkspaceRow(
                        key: const ValueKey('composer-workspace-item-default'),
                        label: l10n.followSessionDefaultWorkspace,
                        selected:
                            currentWorkspace == null ||
                            currentWorkspace.trim().isEmpty,
                        onTap: () => _selectWorkspace(null),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          l10n.noWorkspacesAvailableHint,
                          style: TextStyle(fontSize: 11, color: secondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildModelMenu(BuildContext menuContext) {
    final l10n = AppLocalizations.of(menuContext);
    final currentModel = ref
        .watch(chatControllerProvider(widget.sessionId))
        .model;
    final modelsAsync = ref.watch(availableModelIdsProvider);
    final models = modelsAsync.valueOrNull ?? const <String>[];
    final isLoading = modelsAsync.isLoading;

    return PopoverDropdownCard(
      child: isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CupertinoActivityIndicator(radius: 8),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in models)
                      _ModelRow(
                        key: ValueKey('composer-model-item-$m'),
                        label: m,
                        selected: m == currentModel,
                        onTap: () => _selectModel(m),
                      ),
                    _ModelRow(
                      key: const ValueKey('composer-model-item-default'),
                      label: l10n.contextWindowFollowServerDefault,
                      selected: currentModel == null || currentModel.isEmpty,
                      onTap: () => _selectModel(null),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessionId.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final sessionState = ref.watch(chatControllerProvider(widget.sessionId));
    final currentWorkspace = sessionState.workspace;
    final currentModel = sessionState.model;

    final rootsAsync = ref.watch(workspaceRootsProvider);
    final roots = rootsAsync.valueOrNull;

    // 工作区失效判定：roots 列表非空且其中找不到该 path
    final hasWorkspace =
        currentWorkspace != null && currentWorkspace.trim().isNotEmpty;
    final isWorkspaceUnavailable = hasWorkspace &&
        roots != null &&
        roots.isNotEmpty &&
        !roots.any((r) => r.path == currentWorkspace);

    final matchRoot = hasWorkspace
        ? roots?.where((r) => r.path == currentWorkspace).firstOrNull
        : null;
    final workspaceDisplayValue = isWorkspaceUnavailable
        ? l10n.composerWorkspaceUnavailable
        : hasWorkspace
            ? ((matchRoot?.name != null && matchRoot!.name!.trim().isNotEmpty)
                ? matchRoot.name!
                : currentWorkspace)
            : l10n.composerNoWorkspace;

    final hasModel = currentModel != null && currentModel.trim().isNotEmpty;
    final modelDisplayValue =
        hasModel ? currentModel : l10n.composerDefaultModel;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄宽时 chip 优先自我收缩：丢掉键名、只留「图标 + 值」
        final screenWidth = MediaQuery.sizeOf(context).width;
        final bool showKeyName = constraints.hasBoundedWidth
            ? constraints.maxWidth >= 260
            : screenWidth >= 600;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: _MetaChip(
                key: const ValueKey('composer-workspace-chip'),
                triggerKey: _workspaceKey,
                icon: CupertinoIcons.folder,
                keyName: showKeyName && hasWorkspace && !isWorkspaceUnavailable
                    ? l10n.composerWorkspaceLabel
                    : null,
                value: workspaceDisplayValue,
                isDashed: !hasWorkspace,
                isError: isWorkspaceUnavailable,
                isHovered: _workspaceHovered,
                onHoverChanged: (h) => setState(() => _workspaceHovered = h),
                onTap: _toggleWorkspaceMenu,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              fit: FlexFit.loose,
              child: _MetaChip(
                key: const ValueKey('composer-model-chip'),
                triggerKey: _modelKey,
                icon: CupertinoIcons.sparkles,
                keyName: showKeyName && hasModel ? l10n.composerModelLabel : null,
                value: modelDisplayValue,
                isDashed: !hasModel,
                isError: false,
                isHovered: _modelHovered,
                onHoverChanged: (h) => setState(() => _modelHovered = h),
                onTap: _toggleModelMenu,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 单枚元信息 chip 渲染控件。
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    super.key,
    required this.triggerKey,
    required this.icon,
    required this.keyName,
    required this.value,
    required this.isDashed,
    required this.isError,
    required this.isHovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final GlobalKey triggerKey;
  final IconData icon;
  final String? keyName;
  final String value;
  final bool isDashed;
  final bool isError;
  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  static const double _height = 22.0;
  static const double _radius = 11.0;
  static const double _maxWidth = 190.0;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;

    // 面色
    final surfaceColor = LightSurfaces.resolve(
      context,
      LightSurfaces.card, // #FFFFFF
      dark: const Color(0xFF2C2C2E),
    );

    // 描边色
    final Color borderColor;
    if (isError) {
      borderColor = LightSurfaces.resolve(
        context,
        const Color(0xFFE8B9B5),
        dark: const Color(0xFF5A2A2A),
      );
    } else if (isHovered) {
      borderColor = LightSurfaces.resolve(
        context,
        const Color(0xFFB4B9C4),
        dark: const Color(0xFF5A5A5E),
      );
    } else {
      borderColor = LightSurfaces.resolve(
        context,
        LightSurfaces.cardBorder, // #CCD0DA (0.5px)
        dark: const Color(0xFF3A3A3C),
      );
    }

    // 键名与辅助色（#8A8A8F）
    const keyColor = Color(0xFF8A8A8F);

    // 值文字色
    final Color valueColor;
    final FontWeight valueWeight;
    if (isError) {
      valueColor = LightSurfaces.resolve(
        context,
        const Color(0xFFB3261E),
        dark: statusRedText.resolveFrom(context),
      );
      valueWeight = FontWeight.w600;
    } else if (isDashed) {
      valueColor = keyColor;
      valueWeight = FontWeight.w400;
    } else {
      valueColor = isLight ? const Color(0xFF1C1C1E) : const Color(0xFFEBEBF0);
      valueWeight = FontWeight.w600;
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 11,
          color: isError ? valueColor : keyColor,
        ),
        if (keyName != null) ...[
          const SizedBox(width: 5),
          Text(
            keyName!,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w400,
              color: keyColor,
            ),
          ),
        ],
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: valueWeight,
              color: valueColor,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 5),
        Icon(
          CupertinoIcons.chevron_down,
          size: 9,
          color: isError ? valueColor : keyColor,
        ),
      ],
    );

    Widget chipBox;
    if (isDashed) {
      chipBox = CustomPaint(
        painter: DashedRRectPainter(
          color: borderColor,
          radius: _radius,
          strokeWidth: 0.5,
        ),
        child: Container(
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: content,
        ),
      );
    } else {
      chipBox = Container(
        height: _height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(
            color: borderColor,
            width: 0.5,
          ),
        ),
        child: content,
      );
    }

    return Semantics(
      button: true,
      label: keyName != null ? '$keyName $value' : value,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHoverChanged(true),
        onExit: (_) => onHoverChanged(false),
        child: GestureDetector(
          key: triggerKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: chipBox,
        ),
      ),
    );
  }
}

/// 虚线胶囊描边绘制器（用于无值态 chip）。
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 0.5,
    this.dashLength = 3.0,
    this.dashSpace = 2.5,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double dashSpace;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    final dashedPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = math.min(dashLength, metric.length - distance);
        dashedPath.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
        distance += dashLength + dashSpace;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant DashedRRectPainter oldDelegate) =>
      color != oldDelegate.color ||
      radius != oldDelegate.radius ||
      strokeWidth != oldDelegate.strokeWidth ||
      dashLength != oldDelegate.dashLength ||
      dashSpace != oldDelegate.dashSpace;
}

/// 向上优先的悬浮菜单 overlay 壳。
class _FloatingMenu extends StatelessWidget {
  const _FloatingMenu({
    required this.anchorRect,
    required this.estimatedHeight,
    required this.onDismiss,
    required this.child,
  });

  final Rect anchorRect;
  final double estimatedHeight;
  final VoidCallback onDismiss;
  final Widget child;

  static const double _menuWidth = 228.0;
  static const double _gapAbove = 8.0;
  static const double _gapBelow = 4.0;
  static const double _safeMargin = 8.0;
  static const double _minMenuHeight = 46.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final safeTop = media.padding.top + _safeMargin;

    final maxLeft = math.max(
      _safeMargin,
      screenWidth - _safeMargin - _menuWidth,
    );
    final left = anchorRect.left.clamp(_safeMargin, maxLeft).toDouble();

    // 优先向上展开
    final upTop = anchorRect.top - estimatedHeight - _gapAbove;
    final fitsAbove = upTop >= safeTop;

    Widget positioned;
    if (fitsAbove) {
      final maxHeight = math.max(
        _minMenuHeight,
        anchorRect.top - safeTop - _gapAbove,
      );
      positioned = Positioned(
        left: left,
        bottom: screenHeight - anchorRect.top + _gapAbove,
        width: _menuWidth,
        child: _menuShell(maxHeight: maxHeight),
      );
    } else {
      final downTop = anchorRect.bottom + _gapBelow;
      final downAvail = math.max(0.0, screenHeight - downTop - _safeMargin);
      final menuHeight = math.max(
        math.min(estimatedHeight, downAvail),
        _minMenuHeight,
      );
      positioned = Positioned(
        left: left,
        top: downTop,
        width: _menuWidth,
        child: _menuShell(maxHeight: menuHeight),
      );
    }

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

  Widget _menuShell({required double maxHeight}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: child,
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _selectionMenuButton(
      context,
      selected: selected,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      onPressed: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected
                    ? LightSurfaces.resolve(
                        context,
                        statusBlueText.resolveFrom(context),
                        dark: CupertinoColors.activeBlue,
                      )
                    : CupertinoColors.label.resolveFrom(context),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selected)
            Icon(
              CupertinoIcons.check_mark,
              size: 16,
              color: LightSurfaces.resolve(
                context,
                statusBlueText.resolveFrom(context),
                dark: CupertinoColors.activeBlue,
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: _selectionMenuButton(
        context,
        selected: selected,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        onPressed: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? LightSurfaces.resolve(
                          context,
                          statusBlueText.resolveFrom(context),
                          dark: CupertinoColors.activeBlue,
                        )
                      : CupertinoColors.label.resolveFrom(context),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected)
              Icon(
                CupertinoIcons.check_mark,
                size: 16,
                color: LightSurfaces.resolve(
                  context,
                  statusBlueText.resolveFrom(context),
                  dark: CupertinoColors.activeBlue,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _selectionMenuButton(
  BuildContext context, {
  required bool selected,
  required EdgeInsetsGeometry padding,
  required VoidCallback onPressed,
  required Widget child,
}) {
  if (CupertinoTheme.brightnessOf(context) == Brightness.light) {
    return CupertinoListTile(
      padding: padding,
      backgroundColor: selected ? LightSurfaces.selection : LightSurfaces.card,
      backgroundColorActivated: LightSurfaces.pressed,
      onTap: onPressed,
      title: child,
    );
  }
  return CupertinoButton(
    padding: padding,
    alignment: Alignment.centerLeft,
    onPressed: onPressed,
    child: child,
  );
}
