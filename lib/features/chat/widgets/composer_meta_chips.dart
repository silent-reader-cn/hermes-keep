import 'dart:async';
import 'dart:math' as math;
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/adaptive_shell.dart' show kAdaptiveBreakpoint;
import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/adaptive_action_menu.dart' show ActionMenuDivider;
import '../../../app/widgets/menu_metrics.dart';
import '../../../app/widgets/menu_row.dart';
import '../../../app/widgets/popover_dropdown.dart';
import '../../../app/widgets/popover_menu_shell.dart';
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
      builder: (entryContext) => PopoverMenuShell(
        anchorRect: anchor,
        estimatedHeight: _estimatedMenuHeight(
          rowHeights: _workspaceRowHeights(
            isWide: isWide,
            candidateCount: roots.length,
          ),
          searchBlock: _pickerSearchBarBlock(isWide, roots.length),
        ),
        oneRowHeight: isWide ? _wideWorkspaceRowHeight : _narrowRowHeight,
        width: popoverDropdownWidthFor(entryContext),
        onDismiss: () {
          _removeMenu();
          if (mounted) setState(() {});
        },
        builder: (context, available) =>
            _buildWorkspaceMenu(context, available),
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
      builder: (entryContext) => PopoverMenuShell(
        anchorRect: anchor,
        estimatedHeight: _estimatedMenuHeight(
          rowHeights: _modelRowHeights(
            isWide: isWide,
            candidateCount: models.length,
          ),
          searchBlock: _pickerSearchBarBlock(isWide, models.length),
        ),
        oneRowHeight: isWide ? _wideSingleRowHeight : _narrowRowHeight,
        width: popoverDropdownWidthFor(entryContext),
        onDismiss: () {
          _removeMenu();
          if (mounted) setState(() {});
        },
        builder: (context, available) => _buildModelMenu(context, available),
      ),
    );
    _activeMenuEntry = entry;
    _activeMenuType = _ActiveMenuType.model;
    overlay.insert(entry);
    setState(() {});
  }

  /// 估算高度：全部行高 + 卡片边框 +（可选的）搜索框块。
  ///
  /// 只喂给 [PopoverMenuShell.estimatedHeight] 做**展开方向决策** —— 真正的高度
  /// 交给 `fitMenuHeight` 按行边界算（见 [_PickerMenuContent]）。
  static double _estimatedMenuHeight({
    required List<double> rowHeights,
    required double searchBlock,
  }) =>
      rowHeights.fold<double>(0, (sum, h) => sum + h) +
      kPopoverMenuCardChrome +
      searchBlock;

  /// 搜索框块高：不显示搜索框时为 0。
  static double _pickerSearchBarBlock(bool isWide, int candidateCount) =>
      _pickerSearchVisible(isWide, candidateCount)
      ? _kPickerSearchBarBlockHeight
      : 0.0;

  /// 是否显示搜索框：**仅宽屏**，且候选 ≥ [_kPickerSearchMinCandidates]。
  ///
  /// 窄屏（< [kAdaptiveBreakpoint]）保持原样：228 宽的弹层再塞一个搜索框就只剩
  /// 一条缝了。候选数的口径是**实体项**（工作区 / 模型），不含元操作行。
  static bool _pickerSearchVisible(bool isWide, int candidateCount) =>
      isWide && candidateCount >= _kPickerSearchMinCandidates;

  /// 工作区选择器的行高清单（过滤前口径）：宽屏 = 候选（双行 46）+ 分组线 +
  /// 元操作（36）；无候选时 = 元操作 + 「无工作区」提示行。窄屏每行 44。
  static List<double> _workspaceRowHeights({
    required bool isWide,
    required int candidateCount,
  }) {
    if (!isWide) {
      return [
        for (var i = 0; i <= candidateCount; i++) _narrowRowHeight,
      ];
    }
    return [
      for (var i = 0; i < candidateCount; i++) _wideWorkspaceRowHeight,
      // 元操作（跟随默认）与实体工作区分群，各自独立成群。
      if (candidateCount > 0) _wideDividerHeight,
      _wideSingleRowHeight,
      if (candidateCount == 0) _kNoWorkspaceHintRowHeight,
    ];
  }

  /// 模型选择器的行高清单（过滤前口径）：宽屏 = 候选（36）+ 分组线 + 元操作（36）；
  /// 窄屏每行 44。
  static List<double> _modelRowHeights({
    required bool isWide,
    required int candidateCount,
  }) {
    if (!isWide) {
      return [
        for (var i = 0; i <= candidateCount; i++) _narrowRowHeight,
      ];
    }
    return [
      for (var i = 0; i < candidateCount; i++) _wideSingleRowHeight,
      if (candidateCount > 0) _wideDividerHeight,
      _wideSingleRowHeight,
    ];
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

  Widget _buildWorkspaceMenu(BuildContext menuContext, double available) {
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

    if (isLoading) {
      return const PopoverDropdownCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: CupertinoActivityIndicator(radius: 8),
          ),
        ),
      );
    }

    final secondary = LightSurfaces.resolve(
      menuContext,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    // 「跟随会话默认工作区」是否处于当前态（与窄屏判据一字不差）。
    final followDefaultSelected =
        currentWorkspace == null || currentWorkspace.trim().isEmpty;

    // 过滤判据：大小写不敏感子串，**名称或路径**命中皆算 —— 宽屏项的主信息
    // 就是「名称 + 路径」，只匹配名称会让「按路径找」落空。
    bool matches(WorkspaceRoot w, String query) {
      final q = query.toLowerCase();
      return _workspaceName(w).toLowerCase().contains(q) ||
          (w.path ?? '').toLowerCase().contains(q);
    }

    List<_PickerRow> rowsFor(BuildContext context, String query) {
      final searching = query.isNotEmpty;
      final matched = searching
          ? [for (final w in roots) if (matches(w, query)) w]
          : roots;
      return [
        for (final w in matched)
          if (isWide)
            _PickerRow(
              _wideWorkspaceRowHeight,
              _WorkspaceRowWide(
                key: ValueKey('composer-workspace-item-${w.path}'),
                name: _workspaceName(w),
                path: w.path ?? '',
                selected: currentWorkspace == w.path,
                onTap: () => _selectWorkspace(w.path),
              ),
            )
          else
            _PickerRow(
              _narrowRowHeight,
              _NarrowRow(
                key: ValueKey('composer-workspace-item-${w.path}'),
                label: _workspaceLabel(w),
                selected: currentWorkspace == w.path,
                onTap: () => _selectWorkspace(w.path),
              ),
            ),
        // 元操作（跟随默认）与实体工作区分群，各自独立成群。搜索态下整组不出现
        // ——否则「只剩匹配行」这句读法就不成立；清空搜索框即恢复。
        if (!searching) ...[
          if (isWide && roots.isNotEmpty)
            const _PickerRow(_wideDividerHeight, ActionMenuDivider()),
          _PickerRow(
            isWide ? _wideSingleRowHeight : _narrowRowHeight,
            isWide
                ? _MenuRowWide(
                    key: const ValueKey('composer-workspace-item-default'),
                    icon: CupertinoIcons.arrow_uturn_left,
                    label: l10n.followSessionDefaultWorkspace,
                    // 主行文字统一 13（kFontLabel）：设计稿 13.5、令牌阶梯上 14 之下
                    // 最近的档是 13 —— 主人 2026-10-07 裁定「主行文字改小点」。
                    // （语义档上更贴的是 kFontBody(14)「一句话」，此处按视觉裁定落档。）
                    fontSize: kFontLabel,
                    selected: followDefaultSelected,
                    onTap: () => _selectWorkspace(null),
                  )
                : _NarrowRow(
                    key: const ValueKey('composer-workspace-item-default'),
                    label: l10n.followSessionDefaultWorkspace,
                    selected: followDefaultSelected,
                    onTap: () => _selectWorkspace(null),
                  ),
          ),
        ],
        if (searching && matched.isEmpty)
          _PickerRow(
            _kNoResultsRowHeight,
            _noResultsRow(l10n, secondary),
          ),
        if (!searching && roots.isEmpty)
          _PickerRow(
            _kNoWorkspaceHintRowHeight,
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                l10n.noWorkspacesAvailableHint,
                style: TextStyle(fontSize: kFontMicro, color: secondary),
              ),
            ),
          ),
      ];
    }

    return _PickerMenuContent(
      available: available,
      searchPlaceholder: _pickerSearchVisible(isWide, roots.length)
          ? l10n.pickerSearchWorkspaces
          : null,
      searchFieldKey: const ValueKey('composer-picker-search-workspaces'),
      buildRows: rowsFor,
    );
  }

  /// 搜索无匹配时的提示行：次级色 + [kFontCaption]（注解档），定高
  /// [_kNoResultsRowHeight] 以便 [fitMenuHeight] 精确按行裁剪。
  Widget _noResultsRow(AppLocalizations l10n, Color color) => SizedBox(
    height: _kNoResultsRowHeight,
    child: Center(
      child: Text(
        l10n.pickerSearchNoResults,
        style: TextStyle(fontSize: kFontCaption, color: color),
      ),
    ),
  );

  Widget _buildModelMenu(BuildContext menuContext, double available) {
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

    if (isLoading) {
      return const PopoverDropdownCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: CupertinoActivityIndicator(radius: 8),
          ),
        ),
      );
    }

    final secondary = LightSurfaces.resolve(
      menuContext,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    List<_PickerRow> rowsFor(BuildContext context, String query) {
      final searching = query.isNotEmpty;
      final matched = searching
          ? [
              for (final m in models)
                if (m.toLowerCase().contains(query.toLowerCase())) m,
            ]
          : models;
      return [
        for (final m in matched)
          if (isWide)
            _PickerRow(
              _wideSingleRowHeight,
              _MenuRowWide(
                key: ValueKey('composer-model-item-$m'),
                icon: CupertinoIcons.sparkles,
                label: m,
                // 模型名与工作区名同为「选择器主行」，统一 13（kFontLabel）——
                // 此前用 kFontItemTitle(15) 是选择器里最大的一行，主人裁定改小。
                fontSize: kFontLabel,
                selected: m == currentModel,
                onTap: () => _selectModel(m),
              ),
            )
          else
            _PickerRow(
              _narrowRowHeight,
              _NarrowRow(
                key: ValueKey('composer-model-item-$m'),
                label: m,
                selected: m == currentModel,
                onTap: () => _selectModel(m),
              ),
            ),
        if (!searching) ...[
          if (isWide && models.isNotEmpty)
            const _PickerRow(_wideDividerHeight, ActionMenuDivider()),
          _PickerRow(
            isWide ? _wideSingleRowHeight : _narrowRowHeight,
            isWide
                ? _MenuRowWide(
                    key: const ValueKey('composer-model-item-default'),
                    icon: CupertinoIcons.arrow_uturn_left,
                    label: l10n.contextWindowFollowServerDefault,
                    fontSize: kFontLabel,
                    selected: followServerSelected,
                    onTap: () => _selectModel(null),
                  )
                : _NarrowRow(
                    key: const ValueKey('composer-model-item-default'),
                    label: l10n.contextWindowFollowServerDefault,
                    selected: followServerSelected,
                    onTap: () => _selectModel(null),
                  ),
          ),
        ],
        if (searching && matched.isEmpty)
          _PickerRow(_kNoResultsRowHeight, _noResultsRow(l10n, secondary)),
      ];
    }

    return _PickerMenuContent(
      available: available,
      searchPlaceholder: _pickerSearchVisible(isWide, models.length)
          ? l10n.pickerSearchModels
          : null,
      searchFieldKey: const ValueKey('composer-picker-search-models'),
      buildRows: rowsFor,
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

/// 窄屏（< [kAdaptiveBreakpoint]）单行菜单项（工作区 / 模型 / 元操作共用）。
///
/// 「单行拼接串 + 选中勾」是窄屏的既有形态：工作区是 `名称 (路径)` 拼成一行、
/// 模型就是模型名。几何必须与替换前**逐像素一致** —— 旧实现浅色走
/// `CupertinoListTile`、暗色走 `CupertinoButton`，两者的最小交互高度都是 44
/// （实测两态文字都落在行中心，delta 0.00），故这里是定高 [_narrowRowHeight]
/// 的居中行。行骨架交给 [MenuRow]：浅 / 深两态只差配色，不再各写一套布局。
class _NarrowRow extends StatelessWidget {
  const _NarrowRow({
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
    final accent = LightSurfaces.resolve(
      context,
      statusBlueText.resolveFrom(context),
      dark: CupertinoColors.activeBlue,
    );
    return MenuRow(
      height: _narrowRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: kFontNavItem,
                color: selected
                    ? accent
                    : CupertinoColors.label.resolveFrom(context),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selected)
            Icon(CupertinoIcons.check_mark, size: 16, color: accent),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 选择器弹层的行规格 / 搜索框规格
//
// 出处：设计稿 `sketches/dialog-family-proposal.html` §2「★ 选择器专项」，
// 主人拍板【变体 A：双行 + 4px 间距】。工作区项双行（行高 46），模型项与
// 元操作单行（行高 36），二者同宽同圆角、仍是一家人。
// 窄屏不使用这些行（窄屏走 `_NarrowRow`，44 触屏档，逐像素不变）。
//
// 行高在这里是**真值**而不是估值：它们同时喂给 `fitMenuHeight` 做整行裁剪，
// 一旦与实际渲染高度不符，切口就会落在行中间（见 `menu_metrics.dart`）。
// ─────────────────────────────────────────────────────────────────────────

/// 宽屏双行工作区行高（设计稿「变体 A」）。
const double _wideWorkspaceRowHeight = 46.0;

/// 宽屏单行行高（模型项 / 元操作行）。
const double _wideSingleRowHeight = 36.0;

/// 窄屏单行行高（触屏档 44）—— [`CupertinoListTile`] 与 [`CupertinoButton`]
/// 的最小交互尺寸都是 44，替换前实测两态行高都是 44、文字居中。
const double _narrowRowHeight = 44.0;

/// 菜单分组线高度（= [ActionMenuDivider] 的 0.5）。
const double _wideDividerHeight = 0.5;

/// 「无工作区」提示行高（Padding 8×2 + [kFontMicro] 11 的一行 ≈ 29）。
const double _kNoWorkspaceHintRowHeight = 29.0;

/// 搜索无匹配提示行高（定高，供 [fitMenuHeight] 精确裁剪）。
const double _kNoResultsRowHeight = 44.0;

/// 选择器搜索框的**显示门槛**：宽屏候选数 ≥ 本值才出搜索框。
///
/// 设计稿的口径是「工作区 ≥6 个时出搜索」；本处按主人「两个选择器都要有搜索框」
/// 放宽到 2 —— 两个候选起搜索就有意义，1 个候选时它纯属占地方。
const int _kPickerSearchMinCandidates = 2;

/// 搜索框整块高度：设计稿 `.searchbar` 的 `margin:6px 10px` + 控件自然高。
///
/// 这个值是**参与高度算术的**（`fitMenuHeight` 的可用高要减掉它），所以测试里
/// 有一条守卫钉住「实测块高 == 本常量」——控件内边距一改，守卫会先红。
const double _kPickerSearchBarBlockHeight = 39.0;

/// 窄屏行文案：名称与路径拼成单行（保持既有形态逐像素不变）。
String _workspaceLabel(WorkspaceRoot w) =>
    (w.name != null && w.name!.trim().isNotEmpty)
    ? '${w.name} (${w.path})'
    : (w.path ?? '');

/// 宽屏双行首行文案：只取名称（无名回落为路径）。
String _workspaceName(WorkspaceRoot w) =>
    (w.name != null && w.name!.trim().isNotEmpty) ? w.name! : (w.path ?? '');

/// 宽屏工作区项（双行）：图标 + 名称（[kFontLabel]）+ 路径副行（[kFontMicro]，间距 4px）。
///
/// 名称与路径是**两个独立文本节点**（不再是 `名称 (路径)` 拼接串），路径因此
/// 不会被省略号连坐吃掉；两行左对齐、各自超长省略。
///
/// 行骨架走共享 [MenuRow]（定高 + `Row(crossAxisAlignment: center)`），所以
/// 两态都垂直居中 —— 旧实现浅色分支借 `CupertinoListTile`、暗色分支借
/// `CupertinoButton`，前者的 title 装在 `Column(mainAxisAlignment: spaceBetween)`
/// 里、被定高压到上沿（实测浅色名称比行中心高 16pt、暗色 8pt），这正是本控件
/// 存在的理由：**行的布局不该由主题分支决定**。
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
    final accent = LightSurfaces.resolve(
      context,
      LightSurfaces.selectionForeground,
      dark: CupertinoColors.activeBlue,
    );
    final nameColor = selected
        ? accent
        : CupertinoColors.label.resolveFrom(context);
    final pathColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    return MenuRow(
      height: _wideWorkspaceRowHeight,
      // 16 宽图标盒 + 10 间距（设计稿 `.prow .ic{width:16px}` / `gap:10px`）。
      icon: CupertinoIcons.folder,
      iconBoxWidth: 16,
      iconGap: 10,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      selected: selected,
      onTap: onTap,
      trailing: selected
          ? Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.check_mark, size: 16, color: accent),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: kFontLabel,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: nameColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // 路径字号取 [kFontMicro]（11）而不是 [kFontCaption]（12）：
            // 设计稿这行是 11.5px **等宽 Menlo**（`.prow .pt{font-family:ui-monospace,
            // Menlo,monospace}`），字符窄、字面小；实现只有 MiSans（比例字体，
            // 同 px 下字面更大、笔画更满）。实测同一串路径 `D:\projects\
            // greenscreen-studio` 归一化到同卡片宽后：设计稿墨高 13、12px 实现墨高 16
            // ——「路径行看着比设计稿大」的主因是字形而非字号。取 11 后渲染墨高与
            // 设计稿对齐（≈14 vs 13~14.5），且仍落在令牌阶梯内（不改字族、不引新字体资源）。
            style: TextStyle(fontSize: kFontMicro, color: pathColor),
          ),
        ],
      ),
    );
  }
}

/// 宽屏单行菜单项（模型项 / 元操作）：图标 + 名称，行高 [_wideSingleRowHeight]。
///
/// 模型名本身就是全部信息，硬拆两行会「上重下空」，故模型项保持单行。
/// 选中态是「底色 + 蓝字 + 右侧勾」，**不画左竖条**：竖条是工作区项的锚点
/// （设计稿里只出现在双行项上）。
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
    final accent = LightSurfaces.resolve(
      context,
      LightSurfaces.selectionForeground,
      dark: CupertinoColors.activeBlue,
    );
    final color = selected
        ? accent
        : CupertinoColors.label.resolveFrom(context);
    return MenuRow(
      height: _wideSingleRowHeight,
      icon: icon,
      iconBoxWidth: 16,
      iconGap: 10,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      selected: selected,
      onTap: onTap,
      trailing: selected
          ? Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.check_mark, size: 16, color: accent),
            )
          : null,
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

/// 选择器弹层里的一行：[height] 喂给 `fitMenuHeight` 做**整行裁剪**，[widget] 用于渲染。
///
/// 分组线也占一行（0.5），这样「候选 + 分组线 + 元操作」的混合列表同样只会
/// 裁在整行边界上。
class _PickerRow {
  const _PickerRow(this.height, this.widget);

  final double height;
  final Widget widget;
}

/// 选择器弹层内容（宽屏带搜索框）：**搜索态是本控件自己的局部状态**。
///
/// 为什么不能放在外层 `_ComposerMetaChipsState`：弹层挂在 `OverlayEntry` 上，
/// 外层 State 的 `setState` 并不会重建已插入的 entry，输入过滤必须由弹层内容
/// 自己持有（否则打字时列表纹丝不动）。
///
/// 高度：可用高来自 [PopoverMenuShell]（该侧真实可用），按行边界裁剪 ——
/// 内容放得下就全放，放不下才滚动，且切口永远落在两行之间。
class _PickerMenuContent extends StatefulWidget {
  const _PickerMenuContent({
    required this.available,
    required this.searchPlaceholder,
    required this.searchFieldKey,
    required this.buildRows,
  });

  /// 该侧真实可用高度（来自 [PopoverMenuShell]）。
  final double available;

  /// 搜索框占位文案；为 null 表示不显示搜索框（窄屏 / 候选不足）。
  final String? searchPlaceholder;

  /// 搜索框的测试锚点（既有守卫与探针按 key 定位）。
  final Key searchFieldKey;

  /// 按当前查询串构建行（含「无匹配」提示行；查询串已 trim）。
  final List<_PickerRow> Function(BuildContext context, String query) buildRows;

  @override
  State<_PickerMenuContent> createState() => _PickerMenuContentState();
}

class _PickerMenuContentState extends State<_PickerMenuContent> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    if (value == _query) return;
    setState(() => _query = value);
  }

  @override
  Widget build(BuildContext context) {
    final searchBlock = widget.searchPlaceholder == null
        ? 0.0
        : _kPickerSearchBarBlockHeight;
    final rows = widget.buildRows(context, _query.trim());
    // 列表的高度预算 = 该侧可用高 - 搜索框块 - 卡片边框（1px ×2）。
    //
    // 为什么还要减 chrome：`fitMenuHeight` 的返回值**已含**卡片边框（它的口径是
    // 「卡片高」），而卡片自身在内容之外又实打实地叠了两样东西（搜索框块 + 1px
    // 边框 ×2）。不减就会在最紧的那一档超出 2px，被外层 `ConstrainedBox` 裁出
    // 一个溢出条。
    final listBudget = math.max(
      0.0,
      widget.available - searchBlock - kPopoverMenuCardChrome,
    );
    // 列表内容上限一律取 `fitMenuListHeight`（= fitMenuHeight − 卡片边框）：
    // 这里要的是「列表可见高」而不是「卡片高」。不减边框的话切口会停在边界外
    // 2px 处，露出下一行 2px 的边（实测 1280×300 下第 5 个工作区就露出 2px 一条）
    // —— 判据是「绝不出现半行」。
    final listMax = fitMenuListHeight(
      rowHeights: [for (final row in rows) row.height],
      available: listBudget,
    );

    return PopoverDropdownCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.searchPlaceholder != null) _searchBlock(context),
          Flexible(
            // FlexFit.loose + 有界上限：列表按内容撑（内容驱动、不留白），
            // 上限之外滚动。外层若比预算更紧，也只是滚得更早，不会溢出。
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: listMax),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final row in rows) row.widget],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索框块（设计稿 `.searchbar`：`margin:6px 10px` / `padding:6px 9px` /
  /// 圆角 8 / 浅色底 `#F2F2F2` = [LightSurfaces.page]、暗色 `#2C2C2E`，
  /// 0.5 描边浅 [LightSurfaces.cardBorder] / 暗 [CupertinoColors.separator]）。
  ///
  /// 字号取 [kFontCaption]：搜索框里的字是**一段提示语 / 一个查询词**，不是表单
  /// 字段名，且设计稿的 12.5 离本档（12）最近；[kFontLabel]（13）是字段名的档，
  /// 用在这里会整体大一档、压过占位的从属地位。
  ///
  /// 清空按钮用控件自带（[CupertinoSearchTextField] 的 xmark 后缀）。
  Widget _searchBlock(BuildContext context) {
    final fill = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: const Color(0xFF2C2C2E),
    );
    final stroke = LightSurfaces.resolve(
      context,
      LightSurfaces.cardBorder,
      dark: CupertinoColors.separator,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: CupertinoSearchTextField(
        key: widget.searchFieldKey,
        controller: _queryController,
        placeholder: widget.searchPlaceholder,
        itemSize: 14,
        // 设计稿的 `padding:6px 9px`：文字与前后图标各留 6 的纵向、9 的横向
        // （前缀外缩 6 + 文字内缩 6 ≈ 9 的观感，与 `session_list_page` 同法）。
        padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 6),
        prefixInsets: const EdgeInsetsDirectional.fromSTEB(6, 6, 0, 6),
        suffixInsets: const EdgeInsetsDirectional.fromSTEB(0, 6, 6, 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: stroke, width: 0.5),
        ),
        style: TextStyle(
          fontSize: kFontCaption,
          color: CupertinoColors.label.resolveFrom(context),
        ),
        placeholderStyle: TextStyle(
          fontSize: kFontCaption,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.placeholder,
            dark: CupertinoColors.placeholderText,
          ),
        ),
        itemColor: LightSurfaces.resolve(
          context,
          LightSurfaces.textSecondary,
          dark: CupertinoColors.secondaryLabel,
        ),
        onChanged: _onQueryChanged,
      ),
    );
  }
}
