import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/popover_dropdown.dart';
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

/// 上下文详情弹层（Swift: ContextWindowPopover，对齐 WebUI _syncCtxIndicator 阈值提示）。
///
/// 宽 260、圆角 18、背景 secondarySystemBackground + separator 边框。
/// 内容：标题行（tokensLabel + 压缩 icon） / InfoRows / 模型切换 / 工作区切换 / 关闭。
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
    final providerModels = ref.read(chatAvailableModelsProvider);
    final resolved = providerModels.isNotEmpty
        ? providerModels
        : _fetchedModels;
    final entry = OverlayEntry(
      builder: (entryContext) => _FloatingMenu(
        anchorRect: anchor,
        estimatedHeight: _estimateMenuHeight(resolved.length + 1),
        onDismiss: () {
          _removeEntry(_modelMenuEntry);
          _modelMenuEntry = null;
          if (mounted) setState(() {});
        },
        child: _buildModelMenu(entryContext),
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
    // 空列表时额外估算一行高度，容纳「暂无工作区」提示块
    final rowCount = _workspaces.length + (_workspaces.isEmpty ? 2 : 1);
    final entry = OverlayEntry(
      builder: (entryContext) => _FloatingMenu(
        anchorRect: anchor,
        estimatedHeight: _estimateMenuHeight(rowCount),
        onDismiss: () {
          _removeEntry(_workspaceMenuEntry);
          _workspaceMenuEntry = null;
          if (mounted) setState(() {});
        },
        child: _buildWorkspaceMenu(entryContext),
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
    final entry = OverlayEntry(
      builder: (entryContext) => _FloatingMenu(
        anchorRect: anchor,
        estimatedHeight: _estimateMenuHeight(efforts.length),
        menuWidth: 140,
        alignRight: true,
        onDismiss: () {
          _removeEntry(_reasoningMenuEntry);
          _reasoningMenuEntry = null;
          if (mounted) setState(() {});
        },
        child: _buildReasoningMenu(entryContext),
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

  /// 按内容行数估算下拉卡片高度：行高 44（CupertinoButton 默认 minimumSize，
  /// 实测逐行间距 44，非 padding+字号 34）、卡片上下边框约 2。上限 200 与
  /// 内容 `ConstrainedBox(maxHeight: 200)` 一致，超出由滚动兜底。
  static double _estimateMenuHeight(int rowCount) {
    const rowHeight = 44.0;
    const cardBorder = 2.0;
    const maxMenuHeight = 200.0;
    return math.min<double>(maxMenuHeight, rowCount * rowHeight + cardBorder);
  }

  /// 模型下拉菜单内容（悬浮卡片，展开时构建）。
  Widget _buildModelMenu(BuildContext menuContext) {
    final l10n = AppLocalizations.of(menuContext);
    final providerModels = ref.read(chatAvailableModelsProvider);
    final resolved = providerModels.isNotEmpty
        ? providerModels
        : _fetchedModels;
    final currentModel = ref
        .read(chatControllerProvider(widget.sessionId))
        .model;
    return PopoverDropdownCard(
      child: _loadingModels
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in resolved)
                      _ModelRow(
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
                    _ModelRow(
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
  Widget _buildWorkspaceMenu(BuildContext menuContext) {
    final l10n = AppLocalizations.of(menuContext);
    final currentWorkspace = ref
        .read(chatControllerProvider(widget.sessionId))
        .workspace;
    final secondary = LightSurfaces.resolve(
      menuContext,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    return PopoverDropdownCard(
      child: _loadingWorkspaces
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
                    if (_workspaces.isNotEmpty) ...[
                      for (final w in _workspaces)
                        _WorkspaceRow(
                          key: ValueKey('workspace-item-${w.path}'),
                          label: (w.name != null && w.name!.trim().isNotEmpty)
                              ? '${w.name} (${w.path})'
                              : (w.path ?? ''),
                          selected: currentWorkspace == w.path,
                          onTap: () => _selectWorkspace(w.path),
                        ),
                      _WorkspaceRow(
                        key: const ValueKey('workspace-item-default'),
                        label: l10n.followSessionDefaultWorkspace,
                        selected:
                            currentWorkspace == null ||
                            currentWorkspace.trim().isEmpty,
                        onTap: () => _selectWorkspace(null),
                      ),
                    ] else ...[
                      _WorkspaceRow(
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

  /// 推理强度下拉菜单内容（悬浮卡片，展开时构建）。
  Widget _buildReasoningMenu(BuildContext menuContext) {
    final settingsState = ref.watch(settingsControllerProvider).valueOrNull;
    final efforts = settingsState?.supportedEfforts ?? const <String>[];
    final currentEffort = settingsState?.reasoningEffort;
    return PopoverDropdownCard(
      width: 140,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final effort in efforts)
                _ReasoningRow(
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
    final pct = snapshot.percentage;
    final pctInt = pct == null ? null : (pct * 100).round().clamp(0, 100);
    final tokensLabel = ContextWindowFormatter.tokensLabel(snapshot);
    final inputLabel = ContextWindowFormatter.inputTokensLabel(snapshot);
    final outputLabel = ContextWindowFormatter.outputTokensLabel(snapshot);
    final thresholdLabel = ContextWindowFormatter.thresholdLabel(snapshot);
    final costLabel = ContextWindowFormatter.costLabel(snapshot);

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
      chatControllerProvider(
        widget.sessionId,
      ).select((s) => s.isCompressingContext),
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

    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header：tokensLabel + 压缩 IconButton
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    tokensLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _CompressIconButton(
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
                                .read(
                                  chatControllerProvider(widget.sessionId)
                                      .notifier,
                                )
                                .startCompression();
                            if (!mounted) return;
                            if (started) widget.onClose();
                          } finally {
                            if (mounted) {
                              setState(() => _compressing = false);
                            }
                          }
                        },
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: separator),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: l10n.contextWindowInput, value: inputLabel),
                const SizedBox(height: 6),
                _InfoRow(label: l10n.contextWindowOutput, value: outputLabel),
                const SizedBox(height: 6),
                _InfoRow(
                  label: l10n.contextWindowThreshold,
                  value: thresholdLabel,
                ),
                const SizedBox(height: 6),
                _InfoRow(label: l10n.contextWindowCost, value: costLabel),
              ],
            ),
          ),
          Container(height: 0.5, color: separator),
          // 模型切换区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.contextWindowCurrentModel,
                  style: TextStyle(fontSize: 12, color: secondary),
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
                                        fontSize: 13,
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
                                        fontSize: 13,
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.workspace,
                      style: TextStyle(fontSize: 12, color: secondary),
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
                          style: const TextStyle(fontSize: 12),
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
                                  fontSize: 13,
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
                          style: const TextStyle(fontSize: 13),
                          placeholderStyle: TextStyle(
                            fontSize: 13,
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
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(height: 0.5, color: separator),
          CupertinoButton(
            key: const ValueKey('context-popover-close'),
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed: widget.onClose,
            child: Text(l10n.contextWindowClose),
          ),
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
            fontSize: 12,
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
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

/// 模型/工作区悬浮下拉菜单的 overlay 壳：全屏透明 barrier（点菜单外先收
/// 起本菜单，悬浮层盖住下层内容时也能点外部收起）+ 按触发器全局坐标定位的卡片。
///
/// 展开策略（需求：优先向上展开 + 顶部越界保护）：
/// 1. 优先向上：菜单底边紧贴触发器顶部、间隔 8px；空间不足时内部滚动兜底
///    （内容自带 `ConstrainedBox(maxHeight: 200)` + `SingleChildScrollView`）。
/// 2. 顶部越界保护：当「触发器顶部 y − 菜单估算高 − 8 < 安全区顶部
///    （MediaQuery 顶部 padding + 8）」时，回落为向下展开（老 offset(0,38) 行为）。
/// 3. 向下空间也不足时收紧菜单高度 = 底部可用空间 − 8（保底 ≥ 一行最小高度），
///    由滚动兜底。
/// 4. 水平：菜单左缘对齐触发器左缘，右缘越界时 clamp 到屏幕右缘 − 菜单宽。
class _FloatingMenu extends StatelessWidget {
  const _FloatingMenu({
    required this.anchorRect,
    required this.estimatedHeight,
    required this.onDismiss,
    required this.child,
    this.menuWidth = _menuWidth,
    this.alignRight = false,
  });

  /// 触发器在 overlay 坐标系中的全局矩形（详见 [_ContextWindowPopoverState
  /// ._resolveAnchorRect]）。
  final Rect anchorRect;

  /// 菜单内容估算高度（行数 × 44 + 边框 2，上限 200，见
  /// [_ContextWindowPopoverState._estimateMenuHeight]），用于展开方向决策。
  final double estimatedHeight;

  final VoidCallback onDismiss;
  final Widget child;

  /// 菜单宽度（默认对齐 `PopoverDropdownCard(width: 228)`）。
  final double menuWidth;

  /// 是否向右对齐触发器右缘（用于紧靠弹层右侧的快捷入口）。
  final bool alignRight;

  /// 默认菜单宽度（对齐 `PopoverDropdownCard(width: 228)`）。
  static const double _menuWidth = 228;

  /// 向上展开时菜单底边距触发器顶部间隔。
  static const double _gapAbove = 8;

  /// 向下展开时的纵向 offset（保持老 offset(0,38) 行为）。
  static const double _gapBelow = 38;

  /// 屏幕安全边距（水平 clamp 与顶部底线）。
  static const double _safeMargin = 8;

  /// 菜单高度保底（一行 44 + 边框 2），空间不足时也不低于它（滚动兜底）。
  static const double _minMenuHeight = 46;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final safeTop = media.padding.top + _safeMargin;

    final maxLeft = math.max(
      _safeMargin,
      screenWidth - _safeMargin - menuWidth,
    );
    final targetLeft = alignRight
        ? anchorRect.right - menuWidth
        : anchorRect.left;
    final left = targetLeft.clamp(_safeMargin, maxLeft).toDouble();

    // 优先向上：菜单底边 = 触发器顶部 − 8。顶部越界则回落向下。
    final upTop = anchorRect.top - estimatedHeight - _gapAbove;
    final fitsAbove = upTop >= safeTop;

    Widget positioned;
    if (fitsAbove) {
      // 向上展开：用 bottom 锚定保证底边恒定贴在触发器上方 8px，
      // 同时限制高度避免突破安全区顶部。
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
      // 回落向下：保持 offset(0,38) 老行为；底部空间不足时收紧高度（保底一行）。
      final downTop = anchorRect.top + _gapBelow;
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

  /// 菜单卡片外壳：菜单本体 + 点卡片本身也收起（行按钮的点击优先命中）。
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

class _ReasoningRow extends StatelessWidget {
  const _ReasoningRow({
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
