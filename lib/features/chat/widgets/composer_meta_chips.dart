import 'dart:async';
import 'dart:math' as math;
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/adaptive_shell.dart' show kAdaptiveBreakpoint;
import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/adaptive_action_menu.dart' show ActionMenuDivider;
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
  const ComposerMetaChips({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ComposerMetaChips> createState() => _ComposerMetaChipsState();
}

enum _ActiveMenuType { none, workspace, model }

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
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;

    final entry = OverlayEntry(
      builder: (entryContext) => _FloatingMenu(
        anchorRect: anchor,
        estimatedHeight: isWide
            ? _estimateMenuHeightWide(
                twoLineRows: roots.length,
                singleLineRows: 1,
                hasDivider: roots.isNotEmpty,
              )
            : _estimateMenuHeightNarrow(
                roots.length + (roots.isEmpty ? 2 : 1),
              ),
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
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    final entry = OverlayEntry(
      builder: (entryContext) => _FloatingMenu(
        anchorRect: anchor,
        estimatedHeight: isWide
            ? _estimateMenuHeightWide(
                twoLineRows: 0,
                singleLineRows: models.length + 1,
                hasDivider: models.isNotEmpty,
              )
            : _estimateMenuHeightNarrow(models.length + 1),
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

  /// 窄屏（< [kAdaptiveBreakpoint]）行数估算：单行拼接串，行高按
  /// `CupertinoListTile` 保底 44 计（与重排前逐像素一致）。
  static double _estimateMenuHeightNarrow(int rowCount) {
    const rowHeight = 44.0;
    const cardBorder = 2.0;
    const maxMenuHeight = 200.0;
    return math.min<double>(maxMenuHeight, rowCount * rowHeight + cardBorder);
  }

  /// 宽屏（>= [kAdaptiveBreakpoint]）行数估算：双行工作区行 [_wideWorkspaceRowHeight]、
  /// 单行行 [_wideSingleRowHeight]，中间可能夹一条 [ActionMenuDivider]。
  ///
  /// 之所以不能像窄屏那样「行数 × 一个常数」：宽屏两种行高不同，按 44 固定算会低估
  /// 双行行、高估单行行，向上展开的定位就会错位。
  static double _estimateMenuHeightWide({
    required int twoLineRows,
    required int singleLineRows,
    required bool hasDivider,
  }) {
    const cardBorder = 2.0;
    const maxMenuHeight = 200.0;
    final content =
        twoLineRows * _wideWorkspaceRowHeight +
        singleLineRows * _wideSingleRowHeight +
        (hasDivider ? _wideDividerHeight : 0.0) +
        cardBorder;
    return math.min<double>(maxMenuHeight, content);
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
    // 宽屏专属形态（>= kAdaptiveBreakpoint）：双行工作区项 + 元操作独立成群；
    // 窄屏走原单行拼接串，逐像素不变。
    final isWide =
        MediaQuery.sizeOf(menuContext).width >= kAdaptiveBreakpoint;

    final secondary = LightSurfaces.resolve(
      menuContext,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    // 「跟随会话默认工作区」是否处于当前态（与窄屏判据一字不差）。
    final followDefaultSelected =
        currentWorkspace == null || currentWorkspace.trim().isEmpty;

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
                        if (isWide)
                          _WorkspaceRowWide(
                            key: ValueKey('composer-workspace-item-${w.path}'),
                            name: _workspaceName(w),
                            path: w.path ?? '',
                            selected: currentWorkspace == w.path,
                            onTap: () => _selectWorkspace(w.path),
                          )
                        else
                          _WorkspaceRow(
                            key: ValueKey('composer-workspace-item-${w.path}'),
                            label: _workspaceLabel(w),
                            selected: currentWorkspace == w.path,
                            onTap: () => _selectWorkspace(w.path),
                          ),
                      // 元操作（跟随默认）与实体工作区分群，各自独立成群。
                      if (isWide) const ActionMenuDivider(),
                      if (isWide)
                        _MenuRowWide(
                          key: const ValueKey('composer-workspace-item-default'),
                          icon: CupertinoIcons.arrow_uturn_left,
                          label: l10n.followSessionDefaultWorkspace,
                          // 元操作是一句话，不是「一个东西的名字」，故走正文档。
                          fontSize: kFontBody,
                          selected: followDefaultSelected,
                          onTap: () => _selectWorkspace(null),
                        )
                      else
                        _WorkspaceRow(
                          key: const ValueKey('composer-workspace-item-default'),
                          label: l10n.followSessionDefaultWorkspace,
                          selected: followDefaultSelected,
                          onTap: () => _selectWorkspace(null),
                        ),
                    ] else ...[
                      if (isWide)
                        _MenuRowWide(
                          key: const ValueKey('composer-workspace-item-default'),
                          icon: CupertinoIcons.arrow_uturn_left,
                          label: l10n.followSessionDefaultWorkspace,
                          fontSize: kFontBody,
                          selected: followDefaultSelected,
                          onTap: () => _selectWorkspace(null),
                        )
                      else
                        _WorkspaceRow(
                          key: const ValueKey('composer-workspace-item-default'),
                          label: l10n.followSessionDefaultWorkspace,
                          selected: followDefaultSelected,
                          onTap: () => _selectWorkspace(null),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          l10n.noWorkspacesAvailableHint,
                          style: TextStyle(fontSize: kFontMicro, color: secondary),
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
    // 宽屏（>= kAdaptiveBreakpoint）：模型项仍单行（模型名本身就是全部信息，
    // 硬拆两行会「上重下空」），只加图标与 36 行高；窄屏逐像素不变。
    final isWide =
        MediaQuery.sizeOf(menuContext).width >= kAdaptiveBreakpoint;
    final followServerSelected = currentModel == null || currentModel.isEmpty;

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
                      if (isWide)
                        _MenuRowWide(
                          key: ValueKey('composer-model-item-$m'),
                          icon: CupertinoIcons.sparkles,
                          label: m,
                          // 模型名是「一个东西的名字」⇒ 列表项名档。
                          fontSize: kFontItemTitle,
                          selected: m == currentModel,
                          onTap: () => _selectModel(m),
                        )
                      else
                        _ModelRow(
                          key: ValueKey('composer-model-item-$m'),
                          label: m,
                          selected: m == currentModel,
                          onTap: () => _selectModel(m),
                        ),
                    if (isWide && models.isNotEmpty) const ActionMenuDivider(),
                    if (isWide)
                      _MenuRowWide(
                        key: const ValueKey('composer-model-item-default'),
                        icon: CupertinoIcons.arrow_uturn_left,
                        label: l10n.contextWindowFollowServerDefault,
                        fontSize: kFontBody,
                        selected: followServerSelected,
                        onTap: () => _selectModel(null),
                      )
                    else
                      _ModelRow(
                        key: const ValueKey('composer-model-item-default'),
                        label: l10n.contextWindowFollowServerDefault,
                        selected: followServerSelected,
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

    // #145 窄屏守卫（刻意放在读取任何 provider 之前）：手机视口下输入栏放不下
    // 两枚 chip（实测 390px + 1.3x 文本缩放时经典 Row 溢出 72px），故整组不渲染。
    // 提前 return 还顺带省掉工作区 / 模型目录的两次无谓请求——窄屏既然不显示
    // chip，就没有理由为它拉目录。功能入口不丢失：上下文弹层（ContextWindowPopover）
    // 一直能改模型与工作区。
    if (MediaQuery.sizeOf(context).width < 600) {
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
    final isWorkspaceUnavailable =
        hasWorkspace &&
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
    final modelDisplayValue = hasModel
        ? currentModel
        : l10n.composerDefaultModel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;

        // 窄宽时 chip 优先自我收缩：丢掉键名、只留「图标 + 值」。
        final bool showKeyName = constraints.hasBoundedWidth
            ? constraints.maxWidth >= 260
            : screenWidth >= 760;

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
                keyName: showKeyName && hasModel
                    ? l10n.composerModelLabel
                    : null,
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
    // #163：宽屏 chip 收一档（11.5 → 10.5、图标 11 → 10），与输入栏收紧同批；
    // 窄屏保持原尺寸逐像素不变。
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    // TODO(type): chipFontSize 是绕开令牌的宽窄分流魔数（10.5/11.5 在梯子里
    // 只有侧栏专档）；令牌文件建议改成 kFontXxxFor(context)，值待主人裁。
    final chipFontSize = isWide ? 10.5 : 11.5;
    final chipIconSize = isWide ? 10.0 : 11.0;

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
        Icon(icon, size: chipIconSize, color: isError ? valueColor : keyColor),
        if (keyName != null) ...[
          const SizedBox(width: 5),
          Text(
            keyName!,
            style: TextStyle(
              fontSize: chipFontSize,
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
              fontSize: chipFontSize,
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
          border: Border.all(color: borderColor, width: 0.5),
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
    // 与卡片同源取宽（宽屏 300 / 窄屏 228）——定位宽度与卡片宽度必须一致。
    final menuWidth = popoverDropdownWidthFor(context);

    final maxLeft = math.max(
      _safeMargin,
      screenWidth - _safeMargin - menuWidth,
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
        width: menuWidth,
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
        width: menuWidth,
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
                fontSize: kFontNavItem,
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
                  fontSize: kFontNavItem,
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

// ─────────────────────────────────────────────────────────────────────────
// 宽屏（>= kAdaptiveBreakpoint）专属行规格
//
// 出处：设计稿 `sketches/dialog-family-proposal.html` §2「★ 选择器专项」，
// 主人拍板【变体 A：双行 + 4px 间距】。工作区项双行（行高 46），模型项与
// 元操作单行（行高 36），二者同宽同圆角、仍是一家人。
// 窄屏不使用这些行（窄屏走 `_WorkspaceRow` / `_ModelRow`，逐像素不变）。
// ─────────────────────────────────────────────────────────────────────────

/// 宽屏双行工作区行高（设计稿「变体 A」）。
const double _wideWorkspaceRowHeight = 46.0;

/// 宽屏单行行高（模型项 / 元操作行）。
const double _wideSingleRowHeight = 36.0;

/// 菜单分组线高度（= [ActionMenuDivider] 的 0.5）。
const double _wideDividerHeight = 0.5;

/// 选中竖条上下内缩（设计稿 `.prow.sel::before` 的 `top/bottom:7px`）。
const double _selectedBarInset = 7.0;

/// 窄屏行文案：名称与路径拼成单行（保持既有形态逐像素不变）。
String _workspaceLabel(WorkspaceRoot w) =>
    (w.name != null && w.name!.trim().isNotEmpty)
    ? '${w.name} (${w.path})'
    : (w.path ?? '');

/// 宽屏双行首行文案：只取名称（无名回落为路径）。
String _workspaceName(WorkspaceRoot w) =>
    (w.name != null && w.name!.trim().isNotEmpty) ? w.name! : (w.path ?? '');

/// 宽屏菜单行共用外壳：定高 + 前置图标 + 内容 + 选中态竖条。
///
/// 「三重锥定」中的左侧竖条画在这里（设计稿 `.prow.sel::before`：左 4 /
/// 上下各内缩 [_selectedBarInset] / 宽 2 / 圆角 2），颜色与名称蓝字、右侧
/// checkmark 同源：浅色 [LightSurfaces.selectionForeground]、暗色
/// [CupertinoColors.activeBlue]（spec：左侧竖条 selectionForeground / 暗 activeBlue）。
/// 刻意**不加**选中底色——设计稿的宽屏选中态只有「竖条 + 蓝字 + 勾」三样。
Widget _wideMenuRow(
  BuildContext context, {
  required double height,
  required IconData icon,
  required bool selected,
  required VoidCallback onTap,
  required Widget child,
}) {
  final iconColor = LightSurfaces.resolve(
    context,
    LightSurfaces.textSecondary,
    dark: CupertinoColors.secondaryLabel,
  );
  final accent = LightSurfaces.resolve(
    context,
    LightSurfaces.selectionForeground,
    dark: CupertinoColors.activeBlue,
  );
  final content = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        // 16 宽图标盒 + 10 间距（设计稿 `.prow .ic{width:16px}` / `gap:10px`）。
        SizedBox(width: 16, child: Icon(icon, size: 14, color: iconColor)),
        const SizedBox(width: 10),
        Expanded(child: child),
        if (selected) ...[
          const SizedBox(width: 10),
          Icon(CupertinoIcons.check_mark, size: 16, color: accent),
        ],
      ],
    ),
  );
  final tappable = CupertinoTheme.brightnessOf(context) == Brightness.light
      ? CupertinoListTile(
          padding: EdgeInsets.zero,
          // L2 选中态规格（全仓一致）：选中行底 selectedSurface。本行另有
          // 左竖条 + 蓝字 + 右勾，四重锚定，与侧栏 / 列表的选中态同一套语言。
          backgroundColor: selected
              ? LightSurfaces.selectedSurface
              : LightSurfaces.card,
          backgroundColorActivated: LightSurfaces.pressed,
          onTap: onTap,
          title: content,
        )
      : CupertinoButton(
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          onPressed: onTap,
          child: content,
        );
  return Semantics(
    button: true,
    selected: selected,
    child: SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(child: tappable),
          if (selected)
            Positioned(
              left: 4,
              top: _selectedBarInset,
              bottom: _selectedBarInset,
              child: Container(
                key: const ValueKey('composer-menu-selected-bar'),
                width: 2,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 宽屏工作区项（双行）：图标 + 名称（[kFontBody]）+ 路径副行（[kFontCaption]，间距 4px）。
///
/// 名称与路径是**两个独立文本节点**（不再是 `名称 (路径)` 拼接串），路径因此
/// 不会被省略号连坐吃掉；两行左对齐、各自超长省略。
class _WorkspaceRowWide extends StatelessWidget {
  const _WorkspaceRowWide({
    super.key,
    required this.name,
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String path;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nameColor = selected
        ? LightSurfaces.resolve(
            context,
            LightSurfaces.selectionForeground,
            dark: CupertinoColors.activeBlue,
          )
        : CupertinoColors.label.resolveFrom(context);
    final pathColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    return _wideMenuRow(
      context,
      height: _wideWorkspaceRowHeight,
      icon: CupertinoIcons.folder,
      selected: selected,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: kFontBody,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: nameColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: kFontCaption, color: pathColor),
          ),
        ],
      ),
    );
  }
}

/// 宽屏单行菜单项（模型项 / 元操作）：图标 + 名称，行高 [_wideSingleRowHeight]。
///
/// 模型名本身就是全部信息，硬拆两行会「上重下空」，故模型项保持单行。
class _MenuRowWide extends StatelessWidget {
  const _MenuRowWide({
    super.key,
    required this.icon,
    required this.label,
    required this.fontSize,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double fontSize;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? LightSurfaces.resolve(
            context,
            LightSurfaces.selectionForeground,
            dark: CupertinoColors.activeBlue,
          )
        : CupertinoColors.label.resolveFrom(context);
    return _wideMenuRow(
      context,
      height: _wideSingleRowHeight,
      icon: icon,
      selected: selected,
      onTap: onTap,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: color,
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
      // L2：选中项底改中性灰 .16；前景文字/勾选图标已是 #005FB8。
      backgroundColor: selected
          ? LightSurfaces.selectedSurface
          : LightSurfaces.card,
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
