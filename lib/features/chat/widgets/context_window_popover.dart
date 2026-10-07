import 'dart:async';

import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/layout_tokens.dart';
import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/menu_metrics.dart';
import '../../../app/widgets/adaptive_action_menu.dart'
    show ActionMenuDivider, kActionMenuDividerHeight;
import '../../../app/widgets/picker_menu_content.dart';
import '../../../app/widgets/popover_dropdown.dart';
import '../../../app/widgets/popover_menu_shell.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_client_server_panels.dart';
import '../../../core/api/api_client_workspace.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/models/context_window_snapshot.dart';
import '../../../core/models/workspace.dart';
import '../../../core/utils/context_window_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/settings_providers.dart';
import '../chat_providers.dart';

/// 窄屏弹层宽度（现状值，逐像素不变）。
const double _kPopoverNarrowWidth = 260;

/// 宽屏弹层宽度（设计稿 `dialog-family-proposal.html` §3 推荐①：260 → 300）。
const double _kPopoverWideWidth = 300;

/// 窄屏内容左右内边距（现状值）。
const double _kPopoverNarrowHPad = 16;

/// 宽屏内容左右内边距（设计稿 §3：14）。
const double _kPopoverWideHPad = 14;

/// 推理强度下拉宽度（现状值，紧靠弹层右侧的窄入口）。
const double _kReasoningDropdownWidth = 140;

/// 菜单与触发器之间的间隔：向上贴触发器顶部 +8、向下贴触发器底部 +8。
///
/// 旧副本（本文件自带的 `_FloatingMenu`）向下展开用的是「触发器**顶部** + 38」的老
/// 偏移；本文件改用共享定位壳后统一成「触发器**底边** + 8」。触发器实测高 44，
/// 故向下展开时菜单顶边比旧实现低 14pt（旧实现 `bottom − 6` 会盖住触发器 6pt）。
const double _kDropdownGap = 8;

/// 工作区为空时「暂无工作区」提示块高度（`Padding(all: 4)` + `kFontMicro` 行）。
/// 该块不是菜单行，故单列一个高度喂给 `fitMenuHeight`（按行边界裁剪不切到它）。
const double _kEmptyWorkspaceHintHeight = 22;

/// 加载态卡片（下拉候选仍在拉取时的转圈），三档下拉共用。
const Widget _loadingCard = PopoverDropdownCard(
  child: Center(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: CupertinoActivityIndicator(radius: 8),
    ),
  ),
);

/// 窄屏行文案：名称与路径拼成单行（与输入栏选择器同口径）。
String _menuWorkspaceLabel(WorkspaceRoot w) =>
    (w.name != null && w.name!.trim().isNotEmpty)
    ? '${w.name} (${w.path})'
    : (w.path ?? '');

/// 宽屏双行首行文案：只取名称（无名回落为路径）。
String _menuWorkspaceName(WorkspaceRoot w) =>
    (w.name != null && w.name!.trim().isNotEmpty) ? w.name! : (w.path ?? '');

/// 工作区是否命中查询（名称**或**路径，与选择器同口径）。
bool _menuWorkspaceMatches(WorkspaceRoot w, String q) =>
    _menuWorkspaceName(w).toLowerCase().contains(q) ||
    (w.path ?? '').toLowerCase().contains(q);

/// 上下文详情弹层（Swift: ContextWindowPopover，对齐 WebUI _syncCtxIndicator 阈值提示）。
///
/// 圆角 18、背景 secondarySystemBackground + separator 边框。内容：头部（窄屏
/// `tokensLabel` + 压缩 icon／宽屏大数字 + 「已用 · 上限」副行 + 进度条） /
/// InfoRows / 模型切换 / 工作区切换 / 关闭（仅窄屏）。
///
/// 宽窄分流（阈值见 `layout_tokens.isWideLayout`，= 900）：
/// - **窄屏（<900）逐像素维持原排版**：宽 260、头部 tokensLabel 行、四项数值 12pt、
///   底部「关闭」行。唯一变化是无数据文案走 l10n（缺陷修复，两态共用）。
/// - **宽屏（>=900）按设计稿 §3 重排**：宽 300、大数字（窗口上限 21pt）+ 副行
///   「已用 X · 上限 Y」、占用进度条、「输入/输出/阈值/费用」数值 13pt 右对齐
///   （等宽数字、无数据退为次级色），去掉底部「关闭」行（点外部即关）。
class ContextWindowPopover extends ConsumerStatefulWidget {
  const ContextWindowPopover({
    super.key,
    required this.sessionId,
    required this.snapshot,
    required this.currentModel,
    required this.onClose,
  });

  final String sessionId;
  final ContextWindowSnapshot snapshot;
  final String? currentModel;
  final VoidCallback onClose;

  @override
  ConsumerState<ContextWindowPopover> createState() =>
      _ContextWindowPopoverState();
}

class _ContextWindowPopoverState extends ConsumerState<ContextWindowPopover> {
  bool _compressing = false;
  bool _savingWorkspace = false;
  bool _loadingModels = false;
  bool _manualInputExpanded = false;
  bool _loadingWorkspaces = false;
  bool _workspacesFetched = false;

  /// 模型/工作区/推理强度下拉悬浮菜单：手动 `OverlayEntry`，位置在打开瞬间按触发器
  /// RenderBox 全局坐标换算（不用 CompositedTransformFollower 固定 offset——
  /// 要做「优先向上 + 顶部越界回落」的动态方向决策，需要触发器的真实几何）。
  /// 不参与 Column 高度流，展开时覆盖在弹层内容之上，
  /// 弹层高度恒定不挤占。不用 OverlayPortal（其 DeferredLayout 在嵌套
  /// OverlayEntry（popover 内）场景下 hit test 不经过覆盖层子项）。
  OverlayEntry? _modelMenuEntry;
  OverlayEntry? _workspaceMenuEntry;
  OverlayEntry? _reasoningMenuEntry;
  final LayerLink _modelMenuLink = LayerLink();
  final LayerLink _workspaceMenuLink = LayerLink();
  final LayerLink _reasoningMenuLink = LayerLink();

  /// 触发器锚点 GlobalKey：打开下拉时取 RenderBox 全局矩形（换算方式见
  /// [_resolveAnchorRect]），计算向上/向下展开方向与边界 clamp。
  final GlobalKey _modelTriggerKey = GlobalKey();
  final GlobalKey _workspaceTriggerKey = GlobalKey();
  final GlobalKey _reasoningTriggerKey = GlobalKey();

  List<WorkspaceRoot> _workspaces = const [];
  late final TextEditingController _workspaceController;
  List<String> _fetchedModels = const [];

  @override
  void initState() {
    super.initState();
    final initialWorkspace =
        ref.read(chatControllerProvider(widget.sessionId)).workspace ?? '';
    _workspaceController = TextEditingController(text: initialWorkspace);
    // 若 provider 模型列表为空，异步拉取真实模型以保证可切换；异步拉取工作区列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeFetchModels());
      unawaited(_fetchWorkspaces());
    });
  }

  @override
  void didUpdateWidget(covariant ContextWindowPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _workspaceController.text =
          ref.read(chatControllerProvider(widget.sessionId)).workspace ?? '';
      _workspacesFetched = false;
      _manualInputExpanded = false;
      _removeAllMenus();
      unawaited(_fetchWorkspaces());
    }
  }

  @override
  void dispose() {
    _modelMenuEntry?.remove();
    _workspaceMenuEntry?.remove();
    _reasoningMenuEntry?.remove();
    _workspaceController.dispose();
    super.dispose();
  }

  void _removeEntry(OverlayEntry? entry) {
    if (entry != null && entry.mounted) entry.remove();
  }

  void _removeAllMenus() {
    _removeEntry(_modelMenuEntry);
    _removeEntry(_workspaceMenuEntry);
    _removeEntry(_reasoningMenuEntry);
    _modelMenuEntry = null;
    _workspaceMenuEntry = null;
    _reasoningMenuEntry = null;
  }

  /// 展开/收起模型下拉（互斥：展开本菜单时收起工作区菜单与手动输入）。
  void _toggleModelMenu() {
    if (_modelMenuEntry != null) {
      _removeEntry(_modelMenuEntry);
      _modelMenuEntry = null;
      setState(() {});
      return;
    }
    _removeAllMenus();
    setState(() => _manualInputExpanded = false);
    final overlay = Overlay.of(context);
    final anchor = _resolveAnchorRect(_modelTriggerKey, overlay);
    if (anchor == null) return;
    final rowHeights = _modelMenuRowHeights(isWideLayout(context));
    final entry = OverlayEntry(
      builder: (entryContext) => PopoverMenuShell(
        anchorRect: anchor,
        estimatedHeight: _estimatedMenuHeight(rowHeights),
        oneRowHeight: isWideLayout(entryContext)
            ? kMenuRowHeightMouse
            : kMenuRowHeightTouch,
        // 宽度与输入栏选择器**同源**（宽屏 300 / 窄屏 228）：内层下拉与外侧
        // 选择器是同一套排版语言，宽度不该是两套数。
        width: popoverDropdownWidthFor(entryContext),
        gapAbove: _kDropdownGap,
        gapBelow: _kDropdownGap,
        maxHeight: kPopoverMenuMaxHeight,
        onDismiss: () {
          _removeEntry(_modelMenuEntry);
          _modelMenuEntry = null;
          if (mounted) setState(() {});
        },
        builder: (menuContext, available) =>
            _buildModelMenu(menuContext, available),
      ),
    );
    _modelMenuEntry = entry;
    overlay.insert(entry);
  }

  /// 展开/收起工作区下拉（互斥：展开本菜单时收起模型菜单与手动输入）。
  void _toggleWorkspaceMenu() {
    if (_workspaceMenuEntry != null) {
      _removeEntry(_workspaceMenuEntry);
      _workspaceMenuEntry = null;
      setState(() {});
      return;
    }
    _removeAllMenus();
    setState(() => _manualInputExpanded = false);
    final overlay = Overlay.of(context);
    final anchor = _resolveAnchorRect(_workspaceTriggerKey, overlay);
    if (anchor == null) return;
    final rowHeights = _workspaceMenuRowHeights(isWideLayout(context));
    final entry = OverlayEntry(
      builder: (entryContext) => PopoverMenuShell(
        anchorRect: anchor,
        estimatedHeight: _estimatedMenuHeight(rowHeights),
        oneRowHeight: isWideLayout(entryContext)
            ? kMenuRowHeightMouseTwoLine
            : kMenuRowHeightTouch,
        width: popoverDropdownWidthFor(entryContext),
        gapAbove: _kDropdownGap,
        gapBelow: _kDropdownGap,
        maxHeight: kPopoverMenuMaxHeight,
        onDismiss: () {
          _removeEntry(_workspaceMenuEntry);
          _workspaceMenuEntry = null;
          if (mounted) setState(() {});
        },
        builder: (menuContext, available) =>
            _buildWorkspaceMenu(menuContext, available),
      ),
    );
    _workspaceMenuEntry = entry;
    overlay.insert(entry);
  }

  /// 展开/收起推理强度下拉（互斥：展开本菜单时收起模型菜单、工作区菜单与手动输入）。
  void _toggleReasoningMenu() {
    if (_reasoningMenuEntry != null) {
      _removeEntry(_reasoningMenuEntry);
      _reasoningMenuEntry = null;
      setState(() {});
      return;
    }
    _removeAllMenus();
    setState(() => _manualInputExpanded = false);
    final overlay = Overlay.of(context);
    final anchor = _resolveAnchorRect(_reasoningTriggerKey, overlay);
    if (anchor == null) return;
    final settingsState = ref.read(settingsControllerProvider).valueOrNull;
    final efforts = settingsState?.supportedEfforts ?? const <String>[];
    final isWideReasoning = isWideLayout(context);
    final rowHeights = List<double>.filled(
      efforts.length,
      isWideReasoning ? kMenuRowHeightMouse : kMenuRowHeightTouch,
    );
    final entry = OverlayEntry(
      builder: (entryContext) => PopoverMenuShell(
        anchorRect: anchor,
        estimatedHeight: _estimatedMenuHeight(rowHeights),
        oneRowHeight: isWideLayout(entryContext)
            ? kMenuRowHeightMouse
            : kMenuRowHeightTouch,
        width: _kReasoningDropdownWidth,
        alignToAnchorRight: true,
        gapAbove: _kDropdownGap,
        gapBelow: _kDropdownGap,
        maxHeight: kPopoverMenuMaxHeight,
        onDismiss: () {
          _removeEntry(_reasoningMenuEntry);
          _reasoningMenuEntry = null;
          if (mounted) setState(() {});
        },
        builder: (menuContext, available) =>
            _buildReasoningMenu(menuContext, available),
      ),
    );
    _reasoningMenuEntry = entry;
    overlay.insert(entry);
  }

  /// 计算触发器在 overlay 坐标系中的全局矩形（对齐自适应 popover 的锚点
  /// 换算方式：`localToGlobal(ancestor: overlayBox)`）。取不到 RenderBox
  /// 时返回 null，调用方直接放弃展开（触发器未布局时属防御性保护）。
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

  /// 菜单估算高度（= 全部行高 + 卡片边框 [kPopoverMenuCardChrome]）。
  ///
  /// 只喂给 [PopoverMenuShell.estimatedHeight] 做**展开方向决策** —— 不再像旧实现
  /// 那样封顶 200（封顶会让「上方其实放不下」被判成放得下）；真实可见高度由内容用
  /// `fitMenuHeight` 按行边界算（见 `_buildModelMenu` 等）。
  static double _estimatedMenuHeight(List<double> rowHeights) =>
      rowHeights.fold<double>(0, (sum, h) => sum + h) + kPopoverMenuCardChrome;

  /// 模型下拉的行高清单：候选模型 + 「跟随服务器默认」（宽屏另夹一条分组线）
  /// + （宽屏且候选够多时的）搜索框块。
  List<double> _modelMenuRowHeights(bool isWide) {
    final providerModels = ref.read(chatAvailableModelsProvider);
    final resolved = providerModels.isNotEmpty
        ? providerModels
        : _fetchedModels;
    final row = isWide ? kMenuRowHeightMouse : kMenuRowHeightTouch;
    return <double>[
      if (isWide && resolved.length >= kPickerSearchMinCandidates)
        kPickerSearchBarBlockHeight,
      ...List<double>.filled(resolved.length, row),
      if (isWide && resolved.isNotEmpty) kActionMenuDividerHeight,
      row,
    ];
  }

  /// 工作区下拉的行高清单：候选工作区 + 「跟随会话默认」；列表为空时再加
  /// 「暂无工作区」提示块（不是菜单行，单列高度见 [_kEmptyWorkspaceHintHeight]）。
  List<double> _workspaceMenuRowHeights(bool isWide) {
    final row = isWide ? kMenuRowHeightMouseTwoLine : kMenuRowHeightTouch;
    if (_workspaces.isEmpty) {
      return <double>[
        if (isWide) kPickerSearchBarBlockHeight,
        row,
        _kEmptyWorkspaceHintHeight,
      ];
    }
    return <double>[
      if (isWide && _workspaces.length >= kPickerSearchMinCandidates)
        kPickerSearchBarBlockHeight,
      ...List<double>.filled(_workspaces.length, row),
      if (isWide) kActionMenuDividerHeight,
      isWide ? kMenuRowHeightMouse : kMenuRowHeightTouch,
    ];
  }

  /// 模型下拉菜单内容（悬浮卡片，展开时构建）。
  ///
  /// 与输入栏「模型」选择器**同一套排版语言**：内容走共享 [PickerMenuContent]
  /// （宽屏带搜索框 + 按行边界裁剪的列表），行走共享 [MenuRowSingle]
  /// （宽屏鼠标档 36 / 窄屏 44、图标列 + 选中底色 + 蓝字 + 右勾、无左竖条）。
  ///
  /// [available] 为该侧真实可用高度（定位壳交付），列表可见高度取
  /// `fitMenuListHeight` —— **内容放得下就全放**，放不下才滚动且裁在行边界上。
  Widget _buildModelMenu(BuildContext menuContext, double available) {
    final l10n = AppLocalizations.of(menuContext);
    final isWide = isWideLayout(menuContext);
    final providerModels = ref.read(chatAvailableModelsProvider);
    final resolved = providerModels.isNotEmpty
        ? providerModels
        : _fetchedModels;
    final currentModel = ref
        .read(chatControllerProvider(widget.sessionId))
        .model;
    final rowHeight = isWide ? kMenuRowHeightMouse : kMenuRowHeightTouch;
    final padding = EdgeInsets.symmetric(horizontal: isWide ? 12 : 8);

    void select(String? model) {
      _removeEntry(_modelMenuEntry);
      _modelMenuEntry = null;
      ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .selectModel(model);
      widget.onClose();
    }

    List<PickerMenuRow> rowsFor(BuildContext context, String query) {
      final q = query.toLowerCase();
      final matched = q.isEmpty
          ? resolved
          : <String>[
              for (final m in resolved)
                if (m.toLowerCase().contains(q)) m,
            ];
      return <PickerMenuRow>[
        for (final m in matched)
          PickerMenuRow(
            rowHeight,
            MenuRowSingle(
              key: ValueKey('context-popover-model-$m'),
              height: rowHeight,
              padding: padding,
              icon: CupertinoIcons.sparkles,
              label: m,
              fontSize: kFontLabel,
              selected: m == currentModel,
              onTap: () => select(m),
            ),
          ),
        // 元操作独立成群（搜索时整组隐去，与选择器同口径）。
        if (q.isEmpty) ...[
          if (isWide && matched.isNotEmpty)
            const PickerMenuRow(kActionMenuDividerHeight, ActionMenuDivider()),
          PickerMenuRow(
            rowHeight,
            MenuRowSingle(
              key: const ValueKey('context-popover-model-default'),
              height: rowHeight,
              padding: padding,
              icon: CupertinoIcons.arrow_uturn_left,
              label: l10n.contextWindowFollowServerDefault,
              fontSize: kFontLabel,
              selected: currentModel == null || currentModel.isEmpty,
              onTap: () => select(null),
            ),
          ),
        ],
        if (q.isNotEmpty && matched.isEmpty)
          PickerMenuRow(
            kPickerNoResultsRowHeight,
            MenuNoResultsRow(label: l10n.pickerSearchNoResults),
          ),
      ];
    }

    if (_loadingModels) return _loadingCard;
    return PickerMenuContent(
      available: available,
      searchPlaceholder: isWide && resolved.length >= kPickerSearchMinCandidates
          ? l10n.pickerSearchModels
          : null,
      searchFieldKey: const ValueKey('context-popover-model-search'),
      buildRows: rowsFor,
    );
  }

  /// 工作区下拉菜单内容（悬浮卡片，展开时构建）。
  ///
  /// 与输入栏「工作区」选择器**同一套排版语言**：宽屏双行（名称 + 路径，行高 46）
  /// + 图标列 + 元操作独立成群；窄屏维持单行拼接串（44 触屏档）与 228 宽。
  ///
  /// [available] 见 [_buildModelMenu]。
  Widget _buildWorkspaceMenu(BuildContext menuContext, double available) {
    final l10n = AppLocalizations.of(menuContext);
    final isWide = isWideLayout(menuContext);
    final currentWorkspace = ref
        .read(chatControllerProvider(widget.sessionId))
        .workspace;
    final followSelected =
        currentWorkspace == null || currentWorkspace.trim().isEmpty;
    final padding = EdgeInsets.symmetric(horizontal: isWide ? 12 : 8);
    final secondary = LightSurfaces.resolve(
      menuContext,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    Widget workspaceRow(WorkspaceRoot w) => isWide
        ? MenuRowTwoLine(
            key: ValueKey('workspace-item-${w.path}'),
            height: kMenuRowHeightMouseTwoLine,
            icon: CupertinoIcons.folder,
            name: _menuWorkspaceName(w),
            path: w.path ?? '',
            selected: currentWorkspace == w.path,
            onTap: () => _selectWorkspace(w.path),
          )
        : MenuRowSingle(
            key: ValueKey('workspace-item-${w.path}'),
            height: kMenuRowHeightTouch,
            padding: padding,
            label: _menuWorkspaceLabel(w),
            selected: currentWorkspace == w.path,
            onTap: () => _selectWorkspace(w.path),
          );

    PickerMenuRow followRow() => PickerMenuRow(
      isWide ? kMenuRowHeightMouse : kMenuRowHeightTouch,
      MenuRowSingle(
        key: const ValueKey('workspace-item-default'),
        height: isWide ? kMenuRowHeightMouse : kMenuRowHeightTouch,
        padding: padding,
        icon: CupertinoIcons.arrow_uturn_left,
        label: l10n.followSessionDefaultWorkspace,
        fontSize: isWide ? kFontLabel : kFontNavItem,
        selected: followSelected,
        onTap: () => _selectWorkspace(null),
      ),
    );

    List<PickerMenuRow> rowsFor(BuildContext context, String query) {
      final q = query.toLowerCase();
      if (_workspaces.isEmpty) {
        return <PickerMenuRow>[
          followRow(),
          PickerMenuRow(
            _kEmptyWorkspaceHintHeight,
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                l10n.noWorkspacesAvailableHint,
                style: TextStyle(fontSize: kFontMicro, color: secondary),
              ),
            ),
          ),
        ];
      }
      final matched = q.isEmpty
          ? _workspaces
          : <WorkspaceRoot>[
              for (final w in _workspaces)
                if (_menuWorkspaceMatches(w, q)) w,
            ];
      return <PickerMenuRow>[
        for (final w in matched)
          PickerMenuRow(
            isWide ? kMenuRowHeightMouseTwoLine : kMenuRowHeightTouch,
            workspaceRow(w),
          ),
        if (q.isEmpty) ...[
          if (isWide && matched.isNotEmpty)
            const PickerMenuRow(kActionMenuDividerHeight, ActionMenuDivider()),
          followRow(),
        ],
        if (q.isNotEmpty && matched.isEmpty)
          PickerMenuRow(
            kPickerNoResultsRowHeight,
            MenuNoResultsRow(label: l10n.pickerSearchNoResults),
          ),
      ];
    }

    if (_loadingWorkspaces) return _loadingCard;
    return PickerMenuContent(
      available: available,
      searchPlaceholder:
          isWide && _workspaces.length >= kPickerSearchMinCandidates
          ? l10n.pickerSearchWorkspaces
          : null,
      searchFieldKey: const ValueKey('context-popover-workspace-search'),
      buildRows: rowsFor,
    );
  }

  /// 推理强度下拉菜单内容（悬浮卡片，展开时构建）。
  ///
  /// [available] 见 [_buildModelMenu]。这档刻意**不出搜索框**：几档强度是短枚举
  /// （一眼看得完），在 140 宽的窄菜单里塞搜索框纯属噪声。行仍走共享
  /// [MenuRowSingle]，与另外两档同一套行语言。
  Widget _buildReasoningMenu(BuildContext menuContext, double available) {
    final isWide = isWideLayout(menuContext);
    final settingsState = ref.watch(settingsControllerProvider).valueOrNull;
    final efforts = settingsState?.supportedEfforts ?? const <String>[];
    final currentEffort = settingsState?.reasoningEffort;
    final rowHeight = isWide ? kMenuRowHeightMouse : kMenuRowHeightTouch;
    final padding = EdgeInsets.symmetric(horizontal: isWide ? 12 : 8);

    List<PickerMenuRow> rowsFor(BuildContext context, String query) =>
        <PickerMenuRow>[
          for (final effort in efforts)
            PickerMenuRow(
              rowHeight,
              MenuRowSingle(
                key: ValueKey('context-popover-reasoning-$effort'),
                height: rowHeight,
                padding: padding,
                label: effort,
                fontSize: isWide ? kFontLabel : kFontNavItem,
                selected: effort == currentEffort,
                onTap: () {
                  _removeEntry(_reasoningMenuEntry);
                  _reasoningMenuEntry = null;
                  unawaited(
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setReasoningEffort(effort),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ),
        ];

    return PickerMenuContent(
      available: available,
      searchPlaceholder: null,
      searchFieldKey: null,
      width: _kReasoningDropdownWidth,
      buildRows: rowsFor,
    );
  }

  Future<void> _maybeFetchModels() async {
    final existing = ref.read(chatAvailableModelsProvider);
    if (existing.isNotEmpty) return;
    if (_loadingModels) return;

    final ApiClient client;
    try {
      client = ref.read(apiClientProvider);
    } catch (_) {
      // 处于测试环境或无激活连接时静默处理
      return;
    }

    setState(() => _loadingModels = true);
    try {
      final response = await client.modelsLive();
      final liveOptions = response.liveOptions;
      if (!mounted) return;
      final modelIds = <String>[];
      final seen = <String>{};
      for (final opt in liveOptions) {
        final id = opt.id.trim();
        if (id.isEmpty) continue;
        final normKey = id
            .toLowerCase()
            .replaceAll(' ', '-')
            .replaceAll('_', '-');
        if (seen.add(normKey)) {
          modelIds.add(id);
        }
      }
      setState(() {
        _fetchedModels = modelIds;
      });
    } catch (_) {
      // 网络请求失败静默保留空列表（仅显示跟随服务器默认）
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _fetchWorkspaces() async {
    if (_loadingWorkspaces || _workspacesFetched) return;
    setState(() => _loadingWorkspaces = true);
    try {
      final client = ref.read(apiClientProvider);
      final response = await client.workspaces();
      if (!mounted) return;
      setState(() {
        _workspaces = response.workspaces ?? const [];
        _workspacesFetched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _workspaces = const [];
        _workspacesFetched = true;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingWorkspaces = false);
      }
    }
  }

  Future<void> _selectWorkspace(String? path) async {
    final text = path?.trim() ?? '';
    _workspaceController.text = text;
    _removeEntry(_workspaceMenuEntry);
    _workspaceMenuEntry = null;
    setState(() {
      _savingWorkspace = true;
    });
    try {
      await ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .updateSessionSettings(workspace: text);
    } finally {
      if (mounted) {
        setState(() => _savingWorkspace = false);
      }
    }
  }

  Future<void> _saveManualWorkspace() async {
    final text = _workspaceController.text.trim();
    setState(() => _savingWorkspace = true);
    try {
      await ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .updateSessionSettings(workspace: text);
      if (!mounted) return;
      setState(() => _manualInputExpanded = false);
    } finally {
      if (mounted) {
        setState(() => _savingWorkspace = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshot = widget.snapshot;
    // 宽窄分流（阈值 900，唯一判据走 layout_tokens）：宽屏按设计稿 §3 重排，
    // 窄屏维持原排版逐像素不变。
    final isWide = isWideLayout(context);
    final hPad = isWide ? _kPopoverWideHPad : _kPopoverNarrowHPad;
    final unavailable = l10n.unavailable;
    final pct = snapshot.percentage;
    final pctInt = pct == null ? null : (pct * 100).round().clamp(0, 100);
    final tokensLabel =
        ContextWindowFormatter.tokensLabel(snapshot) ?? unavailable;
    // 四项数值：formatter 无数据返回 null（不再硬编码 'Unavailable'），
    // 文案在 UI 层兜底 l10n.unavailable —— 中文界面不再出现英文残留。
    final inputValue = ContextWindowFormatter.inputTokensLabel(snapshot);
    final outputValue = ContextWindowFormatter.outputTokensLabel(snapshot);
    final thresholdValue = ContextWindowFormatter.thresholdLabel(snapshot);
    final costValue = ContextWindowFormatter.costLabel(snapshot);
    // 宽屏头部：大数字（窗口上限）+ 副行「已用 X · 上限 Y」（设计稿 §3）。
    final windowLabel =
        ContextWindowFormatter.windowLabel(snapshot) ?? unavailable;
    final usedTokens = snapshot.tokensUsed;
    final totalTokens = snapshot.contextLength;
    final usageSubLabel = (usedTokens != null && totalTokens != null)
        ? l10n.contextWindowUsageSummary(
            ContextWindowFormatter.formatTokens(usedTokens),
            ContextWindowFormatter.formatTokens(totalTokens),
          )
        : null;

    final isHigh = pctInt != null && pctInt >= 75;
    final isMid = pctInt != null && pctInt >= 50 && pctInt < 75;

    final separator = LightSurfaces.resolve(
      context,
      LightSurfaces.cardBorder,
      dark: CupertinoColors.separator,
    );
    final secondary = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    final currentModel = widget.currentModel;
    final workspace = ref.watch(
      chatControllerProvider(widget.sessionId).select((s) => s.workspace),
    );
    // #156：压缩状态取自 controller（会话级真相）而非弹窗局部 —— 弹窗关掉、
    // 重开、甚至切走再回来，这里读到的都是同一个真实进度。
    final isCompressing = ref.watch(
      chatControllerProvider(widget.sessionId)
          .select((s) => s.isCompressingContext),
    );
    final settingsState = ref.watch(settingsControllerProvider).valueOrNull;
    final supportsReasoning =
        (settingsState?.supportsReasoningEffort ?? false) &&
        (settingsState?.supportedEfforts.isNotEmpty ?? false);
    final reasoningEffort = settingsState?.reasoningEffort;
    // 保持输入框与外部 workspace 同步（用户未编辑时）
    if (!_savingWorkspace &&
        _workspaceController.text != (workspace ?? '') &&
        !_workspaceController.selection.isValid) {
      // 避免在 build 中直接改 controller 导致光标丢失，仅当未聚焦时同步
      // 用 postFrame 避免 build 期间 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_workspaceController.text != (workspace ?? '')) {
          _workspaceController.text = workspace ?? '';
        }
      });
    }

    final currentWorkspace = workspace;
    String currentWorkspaceLabel = l10n.followSessionDefaultWorkspace;
    if (currentWorkspace != null && currentWorkspace.trim().isNotEmpty) {
      final match = _workspaces
          .where((w) => w.path == currentWorkspace)
          .firstOrNull;
      if (match != null &&
          match.name != null &&
          match.name!.trim().isNotEmpty) {
        currentWorkspaceLabel = '${match.name} (${match.path})';
      } else {
        currentWorkspaceLabel = currentWorkspace;
      }
    }

    // 压缩入口：宽窄两个头部各挂一次，构建一次复用。
    final compressButton = _CompressIconButton(
      key: const ValueKey('context-popover-compress'),
      isHigh: isHigh,
      isMid: isMid,
      compressing: _compressing || isCompressing,
      enabled: pctInt != null && pctInt > 0,
      onPressed: (_compressing || isCompressing)
          ? null
          : () async {
              setState(() => _compressing = true);
              try {
                // #156：异步启动（立刻返回），随后由 controller 轮询，
                // 进度落到会话状态里 —— 所以可以放心关掉弹窗。
                final started = await ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .startCompression();
                if (!mounted) return;
                if (started) widget.onClose();
              } finally {
                if (mounted) {
                  setState(() => _compressing = false);
                }
              }
            },
    );

    return SizedBox(
      width: isWide ? _kPopoverWideWidth : _kPopoverNarrowWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header：窄屏 tokensLabel 行／宽屏大数字 + 「已用 · 上限」副行
          if (isWide)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 13, hPad, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          windowLabel,
                          key: const ValueKey('context-popover-window-label'),
                          style: const TextStyle(
                            fontSize: kFontMetric,
                            fontWeight: FontWeight.w500,
                            height: 1.1,
                          ),
                        ),
                        if (usageSubLabel != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            usageSubLabel,
                            key: const ValueKey(
                              'context-popover-usage-summary',
                            ),
                            style: TextStyle(
                              fontSize: kFontCaption,
                              color: secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  compressButton,
                ],
              ),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 14, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      tokensLabel,
                      style: const TextStyle(
                        fontSize: kFontBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  compressButton,
                ],
              ),
            ),
          // 宽屏：占用进度条（替代窄屏头部下的分隔线）
          if (isWide)
            _ContextUsageBar(
              key: const ValueKey('context-popover-usage-bar'),
              percentage: pct,
            )
          else
            Container(height: 0.5, color: separator),
          // 四项读数：窄屏 12pt 现值行／宽屏 13pt 右对齐 + 无数据退次级色
          if (isWide)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _KeyValueRow(
                    label: l10n.contextWindowInput,
                    value: inputValue,
                    unavailableLabel: unavailable,
                  ),
                  _KeyValueRow(
                    label: l10n.contextWindowOutput,
                    value: outputValue,
                    unavailableLabel: unavailable,
                  ),
                  _KeyValueRow(
                    label: l10n.contextWindowThreshold,
                    value: thresholdValue,
                    unavailableLabel: unavailable,
                  ),
                  _KeyValueRow(
                    label: l10n.contextWindowCost,
                    value: costValue,
                    unavailableLabel: unavailable,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: l10n.contextWindowInput,
                    value: inputValue ?? unavailable,
                  ),
                  const SizedBox(height: 6),
                  _InfoRow(
                    label: l10n.contextWindowOutput,
                    value: outputValue ?? unavailable,
                  ),
                  const SizedBox(height: 6),
                  _InfoRow(
                    label: l10n.contextWindowThreshold,
                    value: thresholdValue ?? unavailable,
                  ),
                  const SizedBox(height: 6),
                  _InfoRow(
                    label: l10n.contextWindowCost,
                    value: costValue ?? unavailable,
                  ),
                ],
              ),
            ),
          Container(height: 0.5, color: separator),
          // 模型切换区
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.contextWindowCurrentModel,
                  style: TextStyle(fontSize: kFontCaption, color: secondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: l10n.selectModel,
                        child: CompositedTransformTarget(
                          key: _modelTriggerKey,
                          link: _modelMenuLink,
                          child: CupertinoButton(
                            key: const ValueKey(
                              'context-popover-model-trigger',
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: _toggleModelMenu,
                            child: Container(
                              decoration: BoxDecoration(
                                color: LightSurfaces.resolve(
                                  context,
                                  LightSurfaces.card,
                                  dark: CupertinoColors.systemBackground,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: separator),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (currentModel == null ||
                                              currentModel.isEmpty)
                                          ? l10n.contextWindowFollowServerDefault
                                          : currentModel,
                                      style: TextStyle(
                                        fontSize: kFontLabel,
                                        fontWeight: FontWeight.w500,
                                        color: CupertinoColors.label
                                            .resolveFrom(context),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedRotation(
                                    turns: _modelMenuEntry != null ? 0.5 : 0.0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      CupertinoIcons.chevron_down,
                                      size: 14,
                                      color: secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (supportsReasoning) ...[
                      const SizedBox(width: 8),
                      Semantics(
                        button: true,
                        label: l10n.reasoningEffort,
                        child: CompositedTransformTarget(
                          key: _reasoningTriggerKey,
                          link: _reasoningMenuLink,
                          child: CupertinoButton(
                            key: const ValueKey(
                              'context-popover-reasoning-trigger',
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: _toggleReasoningMenu,
                            child: Container(
                              decoration: BoxDecoration(
                                color: LightSurfaces.resolve(
                                  context,
                                  LightSurfaces.card,
                                  dark: CupertinoColors.systemBackground,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: separator),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 60,
                                    ),
                                    child: Text(
                                      (reasoningEffort == null ||
                                              reasoningEffort.isEmpty)
                                          ? l10n.notSet
                                          : reasoningEffort,
                                      style: TextStyle(
                                        fontSize: kFontLabel,
                                        fontWeight: FontWeight.w500,
                                        color: CupertinoColors.label
                                            .resolveFrom(context),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  AnimatedRotation(
                                    turns: _reasoningMenuEntry != null
                                        ? 0.5
                                        : 0.0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      CupertinoIcons.chevron_down,
                                      size: 14,
                                      color: secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: separator),
          // 工作区切换区
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.workspace,
                      style: TextStyle(
                        fontSize: kFontCaption,
                        color: secondary,
                      ),
                    ),
                    const Spacer(),
                    if (_savingWorkspace)
                      const CupertinoActivityIndicator(radius: 8)
                    else
                      CupertinoButton(
                        key: const ValueKey(
                          'context-popover-workspace-manual-toggle',
                        ),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 24),
                        onPressed: () {
                          _removeAllMenus();
                          setState(() {
                            _manualInputExpanded = !_manualInputExpanded;
                          });
                        },
                        child: Text(
                          _manualInputExpanded
                              ? l10n.cancel
                              : l10n.manualInputWorkspace,
                          style: const TextStyle(fontSize: kFontButton),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Semantics(
                  button: true,
                  label: l10n.selectWorkspace,
                  child: CompositedTransformTarget(
                    key: _workspaceTriggerKey,
                    link: _workspaceMenuLink,
                    child: CupertinoButton(
                      key: const ValueKey('context-popover-workspace-trigger'),
                      padding: EdgeInsets.zero,
                      onPressed: _toggleWorkspaceMenu,
                      child: Container(
                        decoration: BoxDecoration(
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.card,
                            dark: CupertinoColors.systemBackground,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: separator),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                currentWorkspaceLabel,
                                style: TextStyle(
                                  fontSize: kFontLabel,
                                  fontWeight: FontWeight.w500,
                                  color: CupertinoColors.label.resolveFrom(
                                    context,
                                  ),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                              turns: _workspaceMenuEntry != null ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                CupertinoIcons.chevron_down,
                                size: 14,
                                color: secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_manualInputExpanded) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          key: const ValueKey(
                            'context-popover-workspace-field',
                          ),
                          controller: _workspaceController,
                          placeholder: l10n.workspaceOptionalPlaceholder,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          style: const TextStyle(fontSize: kFontLabel),
                          placeholderStyle: TextStyle(
                            fontSize: kFontLabel,
                            color: secondary,
                          ),
                          decoration: BoxDecoration(
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.card,
                              dark: CupertinoColors.systemBackground,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: separator),
                          ),
                          onSubmitted: (_) => _saveManualWorkspace(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        key: const ValueKey('context-popover-workspace-save'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(44, 28),
                        onPressed: _savingWorkspace
                            ? null
                            : _saveManualWorkspace,
                        child: Text(
                          l10n.save,
                          style: const TextStyle(fontSize: kFontButton),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // 窄屏保留底部「关闭」行（逐像素不变）；宽屏去掉（点外部即关，
          // 设计稿 §3 待裁决项 D）。
          if (!isWide) ...[
            Container(height: 0.5, color: separator),
            CupertinoButton(
              key: const ValueKey('context-popover-close'),
              padding: const EdgeInsets.symmetric(vertical: 10),
              onPressed: widget.onClose,
              child: Text(l10n.contextWindowClose),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: kFontCaption,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: CupertinoColors.secondaryLabel,
            ),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: kFontCaption,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 宽屏键值行（设计稿 §3 `.kv`）：标签在左（12pt 次级色），数值在右
/// （13pt、w500、等宽数字、基线对齐）；[value] 为 null（无数据）时数值退为
/// 次级色且不加粗，文案取 [unavailableLabel]（= `l10n.unavailable`，中文界面
/// 不再出现英文 'Unavailable'）。
class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    required this.unavailableLabel,
  });

  final String label;
  final String? value;
  final String unavailableLabel;

  @override
  Widget build(BuildContext context) {
    final isMuted = value == null;
    // 降级色取次级文字：设计稿 --l-key #8A8A8F 无对应令牌，而
    // CupertinoColors.tertiaryLabel 合成后对比度仅 ~1.7:1（不可用于可读文字）。
    final labelColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final valueColor = isMuted
        ? labelColor
        : CupertinoColors.label.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _kPopoverWideHPad,
        vertical: 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: kFontCaption, color: labelColor),
          ),
          const Spacer(),
          Text(
            value ?? unavailableLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: kFontLabel,
              fontWeight: isMuted ? FontWeight.w400 : FontWeight.w500,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 宽屏头部下方的上下文占用进度条（设计稿 §3 `.bar`）：高 4、圆角 2、轨道灰、
/// 填充品牌蓝；[percentage] 为 null 时只留空轨道。
///
/// 只做可视化，不承载文字 —— 百分比读数由 `ContextWindowIndicator` 与头部副行
/// 承担（不伪造百分比文案）。
class _ContextUsageBar extends StatelessWidget {
  const _ContextUsageBar({super.key, required this.percentage});

  final double? percentage;

  @override
  Widget build(BuildContext context) {
    final fraction = (percentage ?? 0).clamp(0.0, 1.0);
    // 轨道：浅色 systemGrey5 #E5E5EA / 深色 systemGrey4 #3A3A3C（设计稿
    // --l-track / --d-track）；填充：品牌蓝 #007AFF / #0A84FF（--l-blue / --d-blue）。
    final track = LightSurfaces.resolve(
      context,
      CupertinoColors.systemGrey5,
      dark: CupertinoColors.systemGrey4,
    );
    final fill = LightSurfaces.resolve(
      context,
      CupertinoColors.activeBlue,
      dark: CupertinoColors.activeBlue,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kPopoverWideHPad,
        0,
        _kPopoverWideHPad,
        12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 4,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: track)),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  heightFactor: 1,
                  child: ColoredBox(color: fill),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompressIconButton extends StatelessWidget {
  const _CompressIconButton({
    super.key,
    required this.isHigh,
    required this.isMid,
    required this.compressing,
    required this.enabled,
    required this.onPressed,
  });

  final bool isHigh;
  final bool isMid;
  final bool compressing;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    Color? iconColor;
    if (!enabled) {
      iconColor = LightSurfaces.resolve(
        context,
        LightSurfaces.textSecondary,
        dark: CupertinoColors.secondaryLabel,
      );
    } else if (isHigh) {
      iconColor = LightSurfaces.resolve(
        context,
        statusRedText.resolveFrom(context),
        dark: CupertinoColors.systemRed,
      );
    } else if (isMid) {
      iconColor = LightSurfaces.resolve(
        context,
        statusOrangeText.resolveFrom(context),
        dark: CupertinoColors.systemOrange,
      );
    } else {
      iconColor = LightSurfaces.resolve(
        context,
        LightSurfaces.textSecondary,
        dark: CupertinoColors.secondaryLabel,
      );
    }

    final child = compressing
        ? const CupertinoActivityIndicator(radius: 10)
        : Icon(CupertinoIcons.archivebox, size: 18, color: iconColor);

    return Semantics(
      button: true,
      enabled: enabled && !compressing,
      label: 'Compress',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        onPressed: enabled && !compressing ? onPressed : null,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled
                ? (isHigh
                      ? LightSurfaces.resolve(
                          context,
                          LightSurfaces.tintError,
                          dark: CupertinoColors.systemRed
                              .resolveFrom(context)
                              .withValues(alpha: 0.12),
                        )
                      : isMid
                      ? LightSurfaces.resolve(
                          context,
                          LightSurfaces.tintWarning,
                          dark: CupertinoColors.systemOrange
                              .resolveFrom(context)
                              .withValues(alpha: 0.12),
                        )
                      : LightSurfaces.resolve(
                          context,
                          LightSurfaces.page,
                          dark: CupertinoColors.systemGrey5,
                        ))
                : LightSurfaces.resolve(
                    context,
                    LightSurfaces.page,
                    dark: CupertinoColors.systemGrey5,
                  ).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? (isHigh
                        ? LightSurfaces.resolve(
                            context,
                            statusRedText.resolveFrom(context),
                            dark: CupertinoColors.systemRed,
                          )
                        : isMid
                        ? LightSurfaces.resolve(
                            context,
                            statusOrangeText.resolveFrom(context),
                            dark: CupertinoColors.systemOrange,
                          )
                        : LightSurfaces.resolve(
                            context,
                            LightSurfaces.cardBorder,
                            dark: CupertinoColors.separator,
                          ))
                  : LightSurfaces.resolve(
                      context,
                      LightSurfaces.cardBorder,
                      dark: CupertinoColors.separator,
                    ),
              width: 0.5,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

