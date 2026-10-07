import 'dart:async';

import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/layout_tokens.dart';
import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/menu_metrics.dart';
import '../../../app/widgets/menu_row.dart';
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
const double kContextPopoverNarrowWidth = 260;

/// 宽屏弹层宽度（紧凑档：300 → 248）。
///
/// 现状 300 出自设计稿 `dialog-family-proposal.html` §3（为「大数字 + 右对齐数值」
/// 预留的宽度）；主人 2026-10-07 反馈「宽屏下这个弹窗显得太大 —— 大字体宽间距大圆角，
/// 和整个界面不太兼容」后收一档，见 `sketches/context-popover-compact.html`。
const double kContextPopoverWideWidth = 248;

/// 窄屏内容左右内边距（现状值）。
const double _kPopoverNarrowHPad = 16;

/// 宽屏内容左右内边距（紧凑档：14 → 12）。
const double _kPopoverWideHPad = 12;

/// 宽屏头部大数字字号（紧凑档：`kFontMetric` 21 → `kFontPageTitle` 17）。
///
/// 21pt 原本借的是「洞察页指标大数据字」档位，比页面标题（17）还大一档；弹层里它只是
/// 一个读数头部，收进梯子后不再抢戏（这是主人说的「大字体」的主因）。
const double _kPopoverWideMetricFontSize = kFontPageTitle;

/// 宽屏卡圆角（紧凑档：浮层族 14 → 独立卡令牌 `kRadiusCard` 12）。
///
/// 浮层族令牌 `kPopoverDropdownRadius` 是 14（菜单 / 弹层共用）；这里按「独立卡片」档
/// 收到 12，只作用于本弹层（经 `showCupertinoPopover(radius:)` 传入，不动全族）。
const double kContextPopoverWideRadius = kRadiusCard;

/// 宽屏触发器（模型 / 工作区 / 手动输入）内边距与圆角（紧凑档：v8/h10 + 8 → v5/h8 + 7）。
const EdgeInsets _kWideFieldPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 5,
);
const double _kWideFieldRadius = kRadiusInline;

/// 宽屏压缩钮直径（紧凑档：32 → 26）与图标（18 → 15）。
const double _kWideCompressSize = 26;
const double _kWideCompressIconSize = 15;

/// 三个下拉的行高：实测浅/深两态都是 44（统一由 [MenuRow] 定高，不再靠
/// `CupertinoListTile` / `CupertinoButton` 各自的默认最小高兜底）。
const double _kDropdownRowHeight = 44;

/// 模型 / 工作区下拉宽度（现状值：定位壳与卡片同宽）。
const double _kDropdownWidth = 228;

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
    final rowHeights = _modelMenuRowHeights();
    final entry = OverlayEntry(
      builder: (entryContext) => PopoverMenuShell(
        anchorRect: anchor,
        estimatedHeight: _estimatedMenuHeight(rowHeights),
        oneRowHeight: _kDropdownRowHeight,
        width: _kDropdownWidth,
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
    final rowHeights = _workspaceMenuRowHeights();
    final entry = OverlayEntry(
      builder: (entryContext) => PopoverMenuShell(
        anchorRect: anchor,
        estimatedHeight: _estimatedMenuHeight(rowHeights),
        oneRowHeight: _kDropdownRowHeight,
        width: _kDropdownWidth,
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
    final rowHeights = List<double>.filled(efforts.length, _kDropdownRowHeight);
    final entry = OverlayEntry(
      builder: (entryContext) => PopoverMenuShell(
        anchorRect: anchor,
        estimatedHeight: _estimatedMenuHeight(rowHeights),
        oneRowHeight: _kDropdownRowHeight,
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

  /// 模型下拉的行高清单：候选模型 + 「跟随服务器默认」。
  List<double> _modelMenuRowHeights() {
    final providerModels = ref.read(chatAvailableModelsProvider);
    final resolved = providerModels.isNotEmpty
        ? providerModels
        : _fetchedModels;
    return List<double>.filled(resolved.length + 1, _kDropdownRowHeight);
  }

  /// 工作区下拉的行高清单：候选工作区 + 「跟随会话默认」；列表为空时再加
  /// 「暂无工作区」提示块（不是菜单行，单列高度见 [_kEmptyWorkspaceHintHeight]）。
  List<double> _workspaceMenuRowHeights() => _workspaces.isNotEmpty
      ? List<double>.filled(_workspaces.length + 1, _kDropdownRowHeight)
      : const [_kDropdownRowHeight, _kEmptyWorkspaceHintHeight];

  /// 模型下拉菜单内容（悬浮卡片，展开时构建）。
  ///
  /// [available] 为该侧真实可用高度（定位壳交付），列表可见高度取
  /// `fitMenuHeight` —— **内容放得下就全放**，放不下才滚动且裁在行边界上。
  Widget _buildModelMenu(BuildContext menuContext, double available) {
    final l10n = AppLocalizations.of(menuContext);
    final providerModels = ref.read(chatAvailableModelsProvider);
    final resolved = providerModels.isNotEmpty
        ? providerModels
        : _fetchedModels;
    final currentModel = ref
        .read(chatControllerProvider(widget.sessionId))
        .model;
    final rowHeights = _modelMenuRowHeights();
    return PopoverDropdownCard(
      child: _loadingModels
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CupertinoActivityIndicator(radius: 8),
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: fitMenuListHeight(
                  rowHeights: rowHeights,
                  available: available,
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in resolved)
                      _DropdownRow(
                        key: ValueKey('context-popover-model-$m'),
                        label: m,
                        selected: m == currentModel,
                        onTap: () {
                          _removeEntry(_modelMenuEntry);
                          _modelMenuEntry = null;
                          ref
                              .read(
                                chatControllerProvider(widget.sessionId)
                                    .notifier,
                              )
                              .selectModel(m);
                          widget.onClose();
                        },
                      ),
                    _DropdownRow(
                      key: const ValueKey('context-popover-model-default'),
                      label: l10n.contextWindowFollowServerDefault,
                      selected: currentModel == null || currentModel.isEmpty,
                      onTap: () {
                        _removeEntry(_modelMenuEntry);
                        _modelMenuEntry = null;
                        ref
                            .read(
                              chatControllerProvider(widget.sessionId).notifier,
                            )
                            .selectModel(null);
                        widget.onClose();
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// 工作区下拉菜单内容（悬浮卡片，展开时构建）。
  ///
  /// [available] 见 [_buildModelMenu]。
  Widget _buildWorkspaceMenu(BuildContext menuContext, double available) {
    final l10n = AppLocalizations.of(menuContext);
    final currentWorkspace = ref
        .read(chatControllerProvider(widget.sessionId))
        .workspace;
    final secondary = LightSurfaces.resolve(
      menuContext,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final rowHeights = _workspaceMenuRowHeights();
    return PopoverDropdownCard(
      child: _loadingWorkspaces
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CupertinoActivityIndicator(radius: 8),
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: fitMenuListHeight(
                  rowHeights: rowHeights,
                  available: available,
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_workspaces.isNotEmpty) ...[
                      for (final w in _workspaces)
                        _DropdownRow(
                          key: ValueKey('workspace-item-${w.path}'),
                          label: (w.name != null && w.name!.trim().isNotEmpty)
                              ? '${w.name} (${w.path})'
                              : (w.path ?? ''),
                          selected: currentWorkspace == w.path,
                          onTap: () => _selectWorkspace(w.path),
                        ),
                      _DropdownRow(
                        key: const ValueKey('workspace-item-default'),
                        label: l10n.followSessionDefaultWorkspace,
                        selected:
                            currentWorkspace == null ||
                            currentWorkspace.trim().isEmpty,
                        onTap: () => _selectWorkspace(null),
                      ),
                    ] else ...[
                      _DropdownRow(
                        key: const ValueKey('workspace-item-default'),
                        label: l10n.followSessionDefaultWorkspace,
                        selected:
                            currentWorkspace == null ||
                            currentWorkspace.trim().isEmpty,
                        onTap: () => _selectWorkspace(null),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          l10n.noWorkspacesAvailableHint,
                          style: TextStyle(
                            fontSize: kFontMicro,
                            color: secondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  /// 推理强度下拉菜单内容（悬浮卡片，展开时构建）。
  ///
  /// [available] 见 [_buildModelMenu]。
  Widget _buildReasoningMenu(BuildContext menuContext, double available) {
    final settingsState = ref.watch(settingsControllerProvider).valueOrNull;
    final efforts = settingsState?.supportedEfforts ?? const <String>[];
    final currentEffort = settingsState?.reasoningEffort;
    return PopoverDropdownCard(
      width: _kReasoningDropdownWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: fitMenuListHeight(
            rowHeights: List<double>.filled(
              efforts.length,
              _kDropdownRowHeight,
            ),
            available: available,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final effort in efforts)
                _DropdownRow(
                  key: ValueKey('context-popover-reasoning-$effort'),
                  label: effort,
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
            ],
          ),
        ),
      ),
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

    // ── 紧凑档分流 ─────────────────────────────────────────────────────────
    // 模型 / 工作区两个分区在宽窄两态**共用同一段代码**，所以紧凑值必须在这里
    // 按 [isWide] 分流 —— 直接把共用处改成紧凑值会连窄屏一起改掉（硬约束：
    // 窄屏逐像素不变）。下面这组局部变量就是「窄屏取改造前的值」的唯一出口。
    final fieldPadding = isWide
        ? _kWideFieldPadding
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final fieldRadius = isWide ? _kWideFieldRadius : 8.0;
    final fieldChevronSize = isWide ? 12.0 : 14.0;
    final modelSectionPadding = EdgeInsets.fromLTRB(
      hPad,
      isWide ? 8 : 10,
      hPad,
      isWide ? 6 : 8,
    );
    final workspaceSectionPadding = EdgeInsets.fromLTRB(
      hPad,
      isWide ? 8 : 10,
      hPad,
      isWide ? 10 : 12,
    );
    final sectionLabelGap = isWide ? 4.0 : 6.0;

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
      // 紧凑档只作用于宽屏（26 / 15 / 7）；窄屏维持 32 / 18 / 8 逐像素不变。
      size: isWide ? _kWideCompressSize : 32,
      iconSize: isWide ? _kWideCompressIconSize : 18,
      radius: isWide ? _kWideFieldRadius : 8,
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
      width: isWide ? kContextPopoverWideWidth : kContextPopoverNarrowWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header：窄屏 tokensLabel 行／宽屏大数字 + 「已用 · 上限」副行
          if (isWide)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 9, hPad, 8),
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
                            fontSize: _kPopoverWideMetricFontSize,
                            fontWeight: FontWeight.w500,
                            height: 1.1,
                          ),
                        ),
                        if (usageSubLabel != null) ...[
                          const SizedBox(height: 2),
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
            padding: modelSectionPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.contextWindowCurrentModel,
                  style: TextStyle(fontSize: kFontCaption, color: secondary),
                ),
                SizedBox(height: sectionLabelGap),
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
                                borderRadius: BorderRadius.circular(
                                  fieldRadius,
                                ),
                                border: Border.all(color: separator),
                              ),
                              padding: fieldPadding,
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
                                      size: fieldChevronSize,
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
                                borderRadius: BorderRadius.circular(
                                  fieldRadius,
                                ),
                                border: Border.all(color: separator),
                              ),
                              padding: fieldPadding,
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
                                      size: fieldChevronSize,
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
            padding: workspaceSectionPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 标签可收缩（英文 `Workspace` + `Manual input` 在 248 宽下
                    // 按自然宽度排会溢出）；空间够时与「自然宽度 + Spacer」
                    // 逐像素一致，不够时退化为省略号。
                    Expanded(
                      child: Text(
                        l10n.workspace,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: kFontCaption,
                          color: secondary,
                        ),
                      ),
                    ),
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
                SizedBox(height: sectionLabelGap),
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
                          borderRadius: BorderRadius.circular(fieldRadius),
                          border: Border.all(color: separator),
                        ),
                        padding: fieldPadding,
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
                                size: fieldChevronSize,
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
                          padding: fieldPadding,
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
                            borderRadius: BorderRadius.circular(
                              fieldRadius,
                            ),
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
///
/// 紧凑档：上下内距 4 → 2.5（行距 24.5 → 21.5）。
///
/// **左右内距由父层给**（`Padding(symmetric(horizontal: hPad))`）：本行原先自带
/// `horizontal: _kPopoverWideHPad`，与父层叠加成 28，导致四项读数比「当前模型 /
/// 工作区」这类区块标题多缩进 14 —— 同屏两套左缘。紧凑档一并收掉（两层变一层）。
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
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: kFontCaption, color: labelColor),
          ),
          const SizedBox(width: 8),
          // 数值侧必须**可收缩**：左端标签 + 右端数值若都按自然宽度排，长文案
          // （英文 `Threshold` + `Unavailable`、极长费用值）会直接溢出 Row。
          // 用 `Expanded` + 右对齐 + 省略号 —— 空间够时与「Spacer + 自然宽度」
          // 逐像素一致（数值右缘仍然贴齐），不够时退化为省略号而不是黄黑警戒条。
          Expanded(
            child: Text(
              value ?? unavailableLabel,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: kFontLabel,
                fontWeight: isMuted ? FontWeight.w400 : FontWeight.w500,
                color: valueColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
/// 紧凑档：高 4 → 3、圆角 2 → 1.5、下方留白 12 → 8。
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
        8,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1.5),
        child: SizedBox(
          height: 3,
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
    this.size = 32,
    this.iconSize = 18,
    this.radius = 8,
  });

  final bool isHigh;
  final bool isMid;
  final bool compressing;
  final bool enabled;
  final VoidCallback? onPressed;

  /// 按钮直径（现状 32；宽屏紧凑档 26）。
  final double size;

  /// 图标字号（现状 18；宽屏紧凑档 15）。
  final double iconSize;

  /// 圆角（现状 8；宽屏紧凑档 7 = `kRadiusInline`）。
  final double radius;

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
        ? CupertinoActivityIndicator(radius: size >= 32 ? 10 : 8)
        : Icon(CupertinoIcons.archivebox, size: iconSize, color: iconColor);

    return Semantics(
      button: true,
      enabled: enabled && !compressing,
      label: 'Compress',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size(size, size),
        onPressed: enabled && !compressing ? onPressed : null,
        child: Container(
          width: size,
          height: size,
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
            borderRadius: BorderRadius.circular(radius),
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

/// 三个下拉共用的行：定高 44 + [MenuRow]（全仓菜单行的唯一实现）。
///
/// 旧实现按主题分叉（浅色 `CupertinoListTile` / 暗色 `CupertinoButton`），而**行高与
/// 内容对齐本该由菜单行自己定**——两个控件的内部布局并不相同，于是同一个菜单项在
/// 两态下并不逐像素一致（见 [MenuRow] 文档）。统一到 [MenuRow] 后两态只差配色。
///
/// 选中态只用「文字色 + 字重 + 右侧勾」表达；面色 / 悬停 / 按下态交给 [MenuRow]。
class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// 行文案（模型名 / 工作区「名称 (路径)」/ 推理强度）。
  final String label;

  /// 是否当前选中项。
  final bool selected;

  /// 点选落地。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = LightSurfaces.resolve(
      context,
      statusBlueText.resolveFrom(context),
      dark: CupertinoColors.activeBlue,
    );
    return MenuRow(
      height: _kDropdownRowHeight,
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
