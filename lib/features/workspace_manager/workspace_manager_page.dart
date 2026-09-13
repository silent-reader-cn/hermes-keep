import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_action_menu.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/workspace.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import 'add_workspace_sheet.dart';
import 'workspace_manager_providers.dart';

/// 工作区管理页（路由 `/workspaces`，对齐 Hermes WebUI 工作区注册表面板）。
///
/// 列表展示全部已注册工作区（友好名 + 完整路径副行 + 「当前」徽标）；点击行
/// 进入该工作区的文件浏览（借用一个 `workspace == path` 的会话）；长按弹出
/// CupertinoContextMenu（重命名/移除），行尾按钮弹出同款操作菜单；`+` 新建
/// 弹全高表单（路径补全 + 可选名称 + 自动创建开关）；footer 强调「移除只注销
/// 路径不删文件」。
class WorkspaceManagerPage extends ConsumerStatefulWidget {
  const WorkspaceManagerPage({super.key});

  @override
  ConsumerState<WorkspaceManagerPage> createState() =>
      _WorkspaceManagerPageState();
}

class _WorkspaceManagerPageState extends ConsumerState<WorkspaceManagerPage> {
  /// 待重命名的工作区（非空 = 重命名弹窗打开中）。
  WorkspaceRoot? _renameTarget;

  /// 重命名弹窗输入。
  final TextEditingController _renameController = TextEditingController();

  /// 待移除确认的工作区（非空 = 移除确认弹窗打开中）。
  WorkspaceRoot? _pendingRemove;

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(workspaceManagerControllerProvider);
    final state = async.valueOrNull;

    ref.listen(workspaceManagerControllerProvider, (previous, next) {
      final error = next.valueOrNull?.actionError;
      if (error != null && error != previous?.valueOrNull?.actionError) {
        unawaited(_showInfoDialog(l10n.actionFailed, error));
        unawaited(
          ref
              .read(workspaceManagerControllerProvider.notifier)
              .clearActionError(),
        );
      }
      final notice = next.valueOrNull?.notice;
      if (notice != null && notice != previous?.valueOrNull?.notice) {
        unawaited(_showInfoDialog(l10n.notice, notice));
        unawaited(
          ref.read(workspaceManagerControllerProvider.notifier).clearNotice(),
        );
      }
    });

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('workspaces-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.workspacesTitle,
            showMiddleOnNarrow: true,
            // 返回回会话列表 '/' 兜底。
            // 窄屏从会话列表 push 进入时栈为 [/, /workspaces]，canPop true 时
            // 由 AppBackButton.canPop/pop 返回 /；仅当直进深链或刷新后栈仅
            // [/workspaces]、canPop false 时 go(fallback) 才生效，此时
            // fallback 必须为 '/' 才能回到会话列表，写死 '/settings' 导致
            // 窄屏返回误跳设置页（本文件分区 bug 根因）。
            leading: const AppBackButton(fallback: '/'),
            trailing: CupertinoButton(
              key: const ValueKey('workspaces-add'),
              padding: EdgeInsets.zero,
              onPressed: state?.isMutating == true
                  ? null
                  : () => _showAddSheet(),
              child: const Icon(CupertinoIcons.add),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(workspaceManagerControllerProvider.notifier).refresh(),
          ),
          ..._buildContentSlivers(async, state),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<WorkspaceManagerState> async,
    WorkspaceManagerState? state,
  ) {
    final l10n = AppLocalizations.of(context);
    if (state == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(async.error)];
    }

    if (state.workspaces.isEmpty && !state.isRefreshing) {
      return [_buildEmptySliver()];
    }

    return [
      SliverToBoxAdapter(
        child: CupertinoListSection.insetGrouped(
          dividerMargin: 0,
          additionalDividerMargin: 0,
          decoration: CupertinoTheme.brightnessOf(context) == Brightness.dark
              ? null
              : BoxDecoration(
                  color: LightSurfaces.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: LightSurfaces.cardBorder,
                    width: 0.5,
                  ),
                ),
          separatorColor:
              CupertinoTheme.brightnessOf(context) == Brightness.dark
              ? null
              : LightSurfaces.divider,
          footer: Text(
            l10n.removeWorkspaceFooter,
            style: TextStyle(
              fontSize: 12,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
          children: [
            for (final workspace in state.workspaces)
              _WorkspaceRow(
                key: ValueKey('workspace-manager-row-${workspace.path}'),
                workspace: workspace,
                isCurrent: state.isCurrent(workspace),
                isMutating: state.isMutating,
                onTap: () => unawaited(_onRowTap(workspace)),
                onActions: (anchorKey) =>
                    unawaited(_showRowActions(workspace, anchorKey)),
                onRename: () => _showRenameDialog(workspace),
                onRemove: () => _showRemoveDialog(workspace),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _buildErrorSliver(Object? error) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('workspaces-retry'),
              color: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? LightSurfaces.userDetail
                  : null,
              onPressed: () => unawaited(
                ref.read(workspaceManagerControllerProvider.notifier).refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver() {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.folder_badge_plus,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noWorkspacesYet,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.addWorkspaceHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 交互：进入文件浏览 / 行操作菜单 / 新建 / 重命名 / 移除
  // -------------------------------------------------------------------------

  Future<void> _onRowTap(WorkspaceRoot workspace) async {
    final l10n = AppLocalizations.of(context);
    final path = workspace.path;
    if (path == null || path.isEmpty) return;
    try {
      final sessionId = await ref
          .read(workspaceManagerControllerProvider.notifier)
          .findSessionIdForWorkspace(path);
      if (!mounted) return;
      if (sessionId == null || sessionId.isEmpty) {
        await _showInfoDialog(
          l10n.noSessionForWorkspaceTitle,
          l10n.noSessionForWorkspaceBody(path),
        );
        return;
      }
      unawaited(context.push('/workspace/$sessionId'));
    } on Exception catch (error) {
      if (!mounted) return;
      await _showInfoDialog(
        l10n.actionFailed,
        error is ApiException ? error.message : error.toString(),
      );
    }
  }

  Future<void> _showRowActions(
    WorkspaceRoot workspace,
    GlobalKey anchorKey,
  ) async {
    final l10n = AppLocalizations.of(context);
    await AdaptiveActionMenu.show(
      context,
      anchorKey: anchorKey,
      title: _displayName(workspace),
      cancelLabel: l10n.cancel,
      cancelKey: const ValueKey('workspace-manager-action-cancel'),
      items: [
        AdaptiveMenuItem(
          key: ValueKey('workspace-manager-action-browse-${workspace.path}'),
          label: l10n.browseWorkspaceFiles,
          onPressed: () => unawaited(_onRowTap(workspace)),
        ),
        AdaptiveMenuItem(
          key: ValueKey('workspace-manager-action-rename-${workspace.path}'),
          label: l10n.rename,
          onPressed: () => _showRenameDialog(workspace),
        ),
        AdaptiveMenuItem(
          key: ValueKey('workspace-manager-action-remove-${workspace.path}'),
          isDestructive: true,
          label: l10n.removeWorkspaceTitle,
          onPressed: () => _showRemoveDialog(workspace),
        ),
      ],
    );
  }

  void _showAddSheet() {
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        // 60% 黑遮罩（iOS form sheet 惯例，默认 40% 太浅，列表文字会透上来干扰表单）。
        barrierColor: const Color(0x99000000),
        builder: (context) => const AddWorkspaceSheet(),
      ),
    );
  }

  void _showRenameDialog(WorkspaceRoot workspace) {
    final l10n = AppLocalizations.of(context);
    _renameController.text = workspace.name ?? _basename(workspace.path);
    setState(() => _renameTarget = workspace);
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(l10n.renameWorkspaceTitle),
          content: CupertinoTextField(
            key: const ValueKey('workspace-manager-rename-field'),
            controller: _renameController,
            autofocus: true,
          ),
          actions: [
            CupertinoDialogAction(
              key: const ValueKey('workspace-manager-rename-cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => _renameTarget = null);
              },
              child: Text(
                l10n.cancel,
                style: CupertinoTheme.brightnessOf(context) == Brightness.light
                    ? const TextStyle(color: LightSurfaces.menuAction)
                    : null,
              ),
            ),
            CupertinoDialogAction(
              key: const ValueKey('workspace-manager-rename-save'),
              onPressed: () {
                final target = _renameTarget;
                final newName = _renameController.text.trim();
                Navigator.of(context).pop();
                setState(() => _renameTarget = null);
                if (target != null && newName.isNotEmpty) {
                  unawaited(
                    ref
                        .read(workspaceManagerControllerProvider.notifier)
                        .renameWorkspace(
                          path: target.path ?? '',
                          name: newName,
                        ),
                  );
                }
              },
              child: Text(
                l10n.save,
                style: CupertinoTheme.brightnessOf(context) == Brightness.light
                    ? const TextStyle(color: LightSurfaces.menuAction)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveDialog(WorkspaceRoot workspace) {
    final l10n = AppLocalizations.of(context);
    setState(() => _pendingRemove = workspace);
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(l10n.removeWorkspaceTitle),
          content: Text(l10n.confirmRemoveWorkspace(_displayName(workspace))),
          actions: [
            CupertinoDialogAction(
              key: const ValueKey('workspace-manager-remove-cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => _pendingRemove = null);
              },
              child: Text(
                l10n.cancel,
                style: CupertinoTheme.brightnessOf(context) == Brightness.light
                    ? const TextStyle(color: LightSurfaces.menuAction)
                    : null,
              ),
            ),
            CupertinoDialogAction(
              key: const ValueKey('workspace-manager-remove-confirm'),
              isDestructiveAction: true,
              onPressed: () {
                final target = _pendingRemove;
                Navigator.of(context).pop();
                setState(() => _pendingRemove = null);
                if (target != null && target.path != null) {
                  unawaited(
                    ref
                        .read(workspaceManagerControllerProvider.notifier)
                        .removeWorkspace(target.path!),
                  );
                }
              },
              child: Text(
                l10n.removeWorkspaceTitle,
                style: TextStyle(color: statusRedText.resolveFrom(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInfoDialog(String title, String message) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('workspace-manager-dialog-ok'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.ok,
              style: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? const TextStyle(color: LightSurfaces.menuAction)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }

  static String _displayName(WorkspaceRoot workspace) =>
      workspace.name ?? _basename(workspace.path);

  static String _basename(String? path) {
    if (path == null || path.isEmpty) return '';
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final idx = trimmed.lastIndexOf('/');
    if (idx < 0 || idx == trimmed.length - 1) return trimmed;
    return trimmed.substring(idx + 1);
  }
}

/// 单行工作区（自绘行，对齐 WebUI 列表：友好名 + 路径副行 + 当前徽标）。
class _WorkspaceRow extends StatefulWidget {
  const _WorkspaceRow({
    super.key,
    required this.workspace,
    required this.isCurrent,
    required this.isMutating,
    required this.onTap,
    required this.onActions,
    required this.onRename,
    required this.onRemove,
  });

  final WorkspaceRoot workspace;
  final bool isCurrent;
  final bool isMutating;
  final VoidCallback onTap;
  final void Function(GlobalKey anchorKey) onActions;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
  final GlobalKey _actionKey = GlobalKey();

  String get _displayName =>
      widget.workspace.name ??
      _WorkspaceManagerPageState._basename(widget.workspace.path);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final path = widget.workspace.path ?? '';
    return CupertinoContextMenu(
      key: ValueKey('workspace-manager-ctx-${widget.workspace.path}'),
      actions: [
        CupertinoContextMenuAction(
          key: ValueKey(
            'workspace-manager-ctx-browse-${widget.workspace.path}',
          ),
          onPressed: () {
            Navigator.of(context).pop();
            widget.onTap();
          },
          child: Text(l10n.browseWorkspaceFiles),
        ),
        CupertinoContextMenuAction(
          key: ValueKey(
            'workspace-manager-ctx-rename-${widget.workspace.path}',
          ),
          onPressed: () {
            Navigator.of(context).pop();
            widget.onRename();
          },
          child: Text(l10n.rename),
        ),
        CupertinoContextMenuAction(
          key: ValueKey(
            'workspace-manager-ctx-remove-${widget.workspace.path}',
          ),
          isDestructiveAction: true,
          onPressed: () {
            Navigator.of(context).pop();
            widget.onRemove();
          },
          child: Text(
            l10n.removeWorkspaceTitle,
            style: TextStyle(color: statusRedText.resolveFrom(context)),
          ),
        ),
      ],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _FolderBadge(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName.isEmpty ? l10n.unnamed : _displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (path.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isCurrent) const _CurrentBadge(),
              const SizedBox(width: 4),
              KeyedSubtree(
                key: _actionKey,
                child: CupertinoButton(
                  key: ValueKey(
                    'workspace-manager-actions-${widget.workspace.path}',
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: widget.isMutating
                      ? null
                      : () => widget.onActions(_actionKey),
                  child: Icon(
                    CupertinoIcons.ellipsis,
                    size: 20,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 工作区文件夹图标。
class _FolderBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 文件夹灰底与图标颜色保持系统语义色解析（暗色测试精确断言 0x3D767680 与 0xFFFFFFFF）
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(
        CupertinoIcons.folder,
        size: 16,
        color: CupertinoColors.label.resolveFrom(context),
      ),
    );
  }
}

/// 「当前」激活工作区徽标（`last` 匹配）。
class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge();

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.systemBlue
                  .resolveFrom(context)
                  .withValues(alpha: 0.15)
            : LightSurfaces.selection,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        AppLocalizations.of(context).currentWorkspaceBadge,
        style: TextStyle(
          fontSize: 11,
          color: statusBlueText.resolveFrom(context),
        ),
      ),
    );
  }
}
