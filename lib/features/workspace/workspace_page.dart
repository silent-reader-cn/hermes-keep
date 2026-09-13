import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/workspace.dart';
import '../../core/utils/accessibility.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/shell/android_back_interceptor.dart';
import '../../app/widgets/adaptive_action_menu.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import '../workspace_manager/file_preview_page.dart';
import 'workspace_providers.dart';
import '../../app/widgets/hermes_page_route.dart';

/// 文件选择结果（平台通道后置：生产环境暂未接入 file picker，测试可注入）。
class WorkspacePickedFile {
  const WorkspacePickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 文件选择回调；返回 null 表示用户取消。
typedef WorkspaceFilePicker = Future<WorkspacePickedFile?> Function();

/// 格式化文件大小（`123 B` / `1.5 KB` / `2.3 MB` / `1.2 GB`）。
String formatWorkspaceFileSize(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

/// 格式化修改时间（Unix 秒 → 本地 `yyyy-MM-dd HH:mm`）。
String formatWorkspaceModifiedTime(double? epochSeconds) {
  if (epochSeconds == null || epochSeconds <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch((epochSeconds * 1000).round());
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

/// 条目副标题：目录 → 路径（与名称相同则省略）；文件 → 「大小 · 修改时间」
/// （缺失项跳过；均缺失时回退路径，与名称相同则省略）。
String workspaceEntryDetail(WorkspaceEntry entry) {
  final fallback =
      (entry.path != null && entry.path!.isNotEmpty && entry.path != entry.name)
      ? entry.path!
      : '';
  if (entry.isBrowsableDirectory) {
    return fallback;
  }
  final parts = <String>[
    if (entry.size != null) formatWorkspaceFileSize(entry.size),
    if (entry.modified != null) formatWorkspaceModifiedTime(entry.modified),
  ];
  if (parts.isNotEmpty) return parts.join(' · ');
  return fallback;
}

/// 文件浏览页（对齐 Hermex FileBrowserView）。
///
/// Cupertino 风格：路径头（面包屑 + 根目录/上一级）+ 下拉刷新 + 文件列表
/// （目录行点击进入、文件行点击弹出操作菜单：下载/重命名/删除）+ 上传入口
/// （[filePicker] 未注入时提示平台通道后置）+ 加载/错误/空态。
class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key, required this.sessionId, this.filePicker});

  /// 会话 ID（`/api/list` 以它定位工作区）。
  final String sessionId;

  /// 文件选择回调；生产暂为 null（平台通道后置），测试注入 fake picker。
  final WorkspaceFilePicker? filePicker;

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends ConsumerState<WorkspacePage> {
  /// 待重命名的条目（非空 = 重命名弹窗打开中）。
  WorkspaceEntry? _renameEntry;

  /// 重命名弹窗输入。
  final TextEditingController _renameController = TextEditingController();

  /// 待删除确认的条目（非空 = 删除确认弹窗打开中）。
  WorkspaceEntry? _pendingDelete;

  /// Android 系统返回拦截：非根目录时消费返回 = 上一级目录；根目录放行
  /// （交还 shell 走 pop 退出页面）。仅当本页为当前顶层路由（文件预览页 /
  /// 弹窗未覆盖）且列表状态就绪时才消费。
  bool _handleAndroidBack() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    final value = ref
        .read(workspaceControllerProvider(widget.sessionId))
        .valueOrNull;
    if (value == null || value.isAtRoot) return false;
    unawaited(
      ref
          .read(workspaceControllerProvider(widget.sessionId).notifier)
          .navigateUp(),
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    AndroidBackInterceptorRegistry.register(_handleAndroidBack);
  }

  @override
  void dispose() {
    // Dart 方法 tear-off 同实例恒等（== 为 true），可直接注销 initState
    // 注册的同一引用。
    AndroidBackInterceptorRegistry.unregister(_handleAndroidBack);
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = workspaceControllerProvider(widget.sessionId);
    final async = ref.watch(provider);
    final state = async.valueOrNull;
    final crumbs = ref.watch(workspaceBreadcrumbsProvider(widget.sessionId));

    ref.listen<AsyncValue<WorkspaceState>>(provider, (previous, next) {
      final error = next.valueOrNull?.actionError;
      if (error != null && error != previous?.valueOrNull?.actionError) {
        unawaited(_showActionError(context, error));
      }
      final notice = next.valueOrNull?.notice;
      if (notice != null && notice != previous?.valueOrNull?.notice) {
        unawaited(_showNotice(context, notice));
      }
    });

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('workspace-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.files,
            showMiddleOnNarrow: true,
            // 返回回会话列表 '/' 兜底。
            // 窄屏从会话列表 push 进入时栈为 [/, /workspace/:sid]，canPop 为
            // true 由 canPop/pop 返回 / 无需 fallback；仅当直进深链或桌面刷新
            // 后栈仅 [/workspace/:sid]，canPop false 时 fallback 应回 '/' 而
            // 非 '/chat/:sid'（后者在从 /workspaces 管理页 push 进来等场景与
            // “返回会话列表”预期偏离）。
            leading: const AppBackButton(fallback: '/'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AccessibleButton(
                  key: const ValueKey('workspace-refresh'),
                  label: l10n.refreshFileList,
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      unawaited(ref.read(provider.notifier).refresh()),
                  child: const Icon(CupertinoIcons.arrow_clockwise),
                ),
                const SizedBox(width: 14),
                _UploadButton(
                  uploading: state?.isUploading == true,
                  onPressed: () => unawaited(_onUploadPressed()),
                ),
              ],
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () => ref.read(provider.notifier).refresh(),
          ),
          _PathHeader(
            crumbs: crumbs,
            displayPath: state?.displayPath ?? l10n.rootDir,
            isRefreshing: state?.isRefreshing == true,
            isFolderDownloading: state?.isFolderDownloading == true,
            errorMessage:
                state != null &&
                    state.actionError != null &&
                    state.entries.isNotEmpty
                ? state.actionError
                : null,
            onRoot: () =>
                unawaited(ref.read(provider.notifier).navigateToRoot()),
            onUp: () => unawaited(ref.read(provider.notifier).navigateUp()),
            onDownloadFolder: () => unawaited(
              ref.read(provider.notifier).downloadFolder(context: context),
            ),
            onRetry: () =>
                unawaited(ref.read(provider.notifier).retryLastLoad()),
            onCrumbTap: (crumb) =>
                unawaited(ref.read(provider.notifier).navigateTo(crumb.path)),
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
    AsyncValue<WorkspaceState> async,
    WorkspaceState? state,
  ) {
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

    if (state.entries.isEmpty && !state.isRefreshing) {
      return [_buildEmptySliver(state)];
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
          children: [
            for (final entry in state.entries)
              _WorkspaceEntryRow(
                key: ValueKey('workspace-row-${entry.name ?? entry.path}'),
                entry: entry,
                busy: state.isBusy(entry.path ?? ''),
                onTap: () => _onEntryTap(entry),
                onActions: (anchorKey) =>
                    unawaited(_showRowActions(entry, anchorKey)),
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
              key: const ValueKey('workspace-retry'),
              color: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? LightSurfaces.userDetail
                  : null,
              onPressed: () => unawaited(
                ref
                    .read(
                      workspaceControllerProvider(widget.sessionId).notifier,
                    )
                    .refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver(WorkspaceState state) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.folder_open,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.noFiles, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              state.displayPath,
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
  // 交互：目录进入 / 行操作菜单 / 上传 / 重命名 / 删除
  // -------------------------------------------------------------------------

  void _onEntryTap(WorkspaceEntry entry) {
    final controller = ref.read(
      workspaceControllerProvider(widget.sessionId).notifier,
    );
    if (entry.isBrowsableDirectory) {
      unawaited(controller.navigateTo(entry.path ?? entry.name ?? '.'));
    }
  }

  Future<void> _showRowActions(
    WorkspaceEntry entry,
    GlobalKey anchorKey,
  ) async {
    final l10n = AppLocalizations.of(context);
    await AdaptiveActionMenu.show(
      context,
      anchorKey: anchorKey,
      title: entry.name ?? entry.path ?? '',
      cancelLabel: l10n.cancel,
      cancelKey: const ValueKey('workspace-action-cancel'),
      items: [
        if (workspaceFileIsPreviewable(entry) && !entry.isReadOnlyEscape)
          AdaptiveMenuItem(
            key: const ValueKey('workspace-action-preview'),
            label: l10n.preview,
            onPressed: () => _openPreview(entry),
          ),
        AdaptiveMenuItem(
          key: const ValueKey('workspace-action-download'),
          label: l10n.download,
          onPressed: () => unawaited(_onDownload(entry)),
        ),
        AdaptiveMenuItem(
          key: const ValueKey('workspace-action-rename'),
          label: l10n.rename,
          onPressed: () => _showRenameDialog(entry),
        ),
        AdaptiveMenuItem(
          key: const ValueKey('workspace-action-delete'),
          isDestructive: true,
          label: l10n.delete,
          onPressed: () => _showDeleteDialog(entry),
        ),
      ],
    );
  }

  Future<void> _onDownload(WorkspaceEntry entry) async {
    await ref
        .read(workspaceControllerProvider(widget.sessionId).notifier)
        .download(entry, context: context);
  }

  /// 打开文件预览页（文本/图片走 /api/file、/api/file/raw）。
  void _openPreview(WorkspaceEntry entry) {
    Navigator.of(context).push(
      HermesPageRoute<void>(
        builder: (context) =>
            FilePreviewPage(sessionId: widget.sessionId, entry: entry),
      ),
    );
  }

  void _showDeleteDialog(WorkspaceEntry entry) {
    final l10n = AppLocalizations.of(context);
    setState(() => _pendingDelete = entry);
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(l10n.deleteFile),
          content: Text(l10n.confirmDeleteFile(entry.name ?? entry.path ?? '')),
          actions: [
            CupertinoDialogAction(
              key: const ValueKey('workspace-delete-cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => _pendingDelete = null);
              },
              child: Text(l10n.cancel),
            ),
            CupertinoDialogAction(
              key: const ValueKey('workspace-delete-confirm'),
              isDestructiveAction: true,
              onPressed: () {
                final target = _pendingDelete;
                Navigator.of(context).pop();
                setState(() => _pendingDelete = null);
                if (target != null) {
                  unawaited(
                    ref
                        .read(
                          workspaceControllerProvider(widget.sessionId)
                              .notifier,
                        )
                        .delete(target),
                  );
                }
              },
              child: Text(l10n.delete),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(WorkspaceEntry entry) {
    final l10n = AppLocalizations.of(context);
    _renameController.text = entry.name ?? entry.path ?? '';
    setState(() => _renameEntry = entry);
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(l10n.rename),
          content: CupertinoTextField(
            key: const ValueKey('workspace-rename-field'),
            controller: _renameController,
            autofocus: true,
          ),
          actions: [
            CupertinoDialogAction(
              key: const ValueKey('workspace-rename-cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => _renameEntry = null);
              },
              child: Text(l10n.cancel),
            ),
            CupertinoDialogAction(
              key: const ValueKey('workspace-rename-save'),
              onPressed: () {
                final target = _renameEntry;
                final newName = _renameController.text;
                Navigator.of(context).pop();
                setState(() => _renameEntry = null);
                if (target != null && newName.trim().isNotEmpty) {
                  unawaited(
                    ref
                        .read(
                          workspaceControllerProvider(widget.sessionId)
                              .notifier,
                        )
                        .rename(target, newName),
                  );
                }
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onUploadPressed() async {
    final l10n = AppLocalizations.of(context);
    final picker = widget.filePicker;
    if (picker == null) {
      await _showInfoDialog(
        l10n.filePickerNotAvailable,
        l10n.filePickerPendingPlatformSupport,
      );
      return;
    }
    final picked = await picker();
    if (picked == null) return; // 用户取消
    await ref
        .read(workspaceControllerProvider(widget.sessionId).notifier)
        .uploadFile(filename: picked.name, data: picked.bytes);
  }

  // -------------------------------------------------------------------------
  // 弹窗
  // -------------------------------------------------------------------------

  Future<void> _showActionError(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    await _showInfoDialog(l10n.actionFailed, message);
    await ref
        .read(workspaceControllerProvider(widget.sessionId).notifier)
        .clearActionError();
  }

  Future<void> _showNotice(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    await _showInfoDialog(l10n.notice, message);
    await ref
        .read(workspaceControllerProvider(widget.sessionId).notifier)
        .clearNotice();
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
            key: const ValueKey('workspace-dialog-ok'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

/// 导航栏上传按钮（上传中显示 ActivityIndicator）。
class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.uploading, required this.onPressed});

  final bool uploading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (uploading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: CupertinoActivityIndicator(radius: 10),
      );
    }
    return AccessibleButton(
      key: const ValueKey('workspace-upload'),
      label: AppLocalizations.of(context).uploadFile,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: const Icon(CupertinoIcons.arrow_up_doc),
    );
  }
}

/// 路径头：展示路径 + 根目录/上一级按钮 + 面包屑 + 加载/错误横幅。
class _PathHeader extends StatelessWidget {
  const _PathHeader({
    required this.crumbs,
    required this.displayPath,
    required this.isRefreshing,
    required this.isFolderDownloading,
    required this.errorMessage,
    required this.onRoot,
    required this.onUp,
    required this.onDownloadFolder,
    required this.onRetry,
    required this.onCrumbTap,
  });

  final List<WorkspaceBreadcrumb> crumbs;
  final String displayPath;
  final bool isRefreshing;
  final bool isFolderDownloading;
  final String? errorMessage;
  final VoidCallback onRoot;
  final VoidCallback onUp;
  final VoidCallback onDownloadFolder;
  final VoidCallback onRetry;

  /// 点击面包屑 → 跳转到该路径。
  final ValueChanged<WorkspaceBreadcrumb> onCrumbTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final isAtRoot = crumbs.length == 1;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  l10n.locationLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: secondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CupertinoButton(
                  key: const ValueKey('workspace-root'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  disabledColor: CupertinoColors.quaternaryLabel.resolveFrom(
                    context,
                  ),
                  onPressed: isAtRoot ? null : onRoot,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.house,
                        size: 14,
                        color: isDark
                            ? null
                            : (isAtRoot
                                  ? LightSurfaces.textSecondary
                                  : LightSurfaces.userDetail),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.rootDir,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? null
                              : (isAtRoot
                                    ? LightSurfaces.textSecondary
                                    : LightSurfaces.userDetail),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                CupertinoButton(
                  key: const ValueKey('workspace-up'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  disabledColor: CupertinoColors.quaternaryLabel.resolveFrom(
                    context,
                  ),
                  onPressed: isAtRoot ? null : onUp,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.arrow_up,
                        size: 14,
                        color: isDark
                            ? null
                            : (isAtRoot
                                  ? LightSurfaces.textSecondary
                                  : LightSurfaces.userDetail),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.parentDir,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? null
                              : (isAtRoot
                                    ? LightSurfaces.textSecondary
                                    : LightSurfaces.userDetail),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (isFolderDownloading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: CupertinoActivityIndicator(radius: 9),
                  )
                else
                  AccessibleButton(
                    key: const ValueKey('workspace-download-folder'),
                    label: l10n.downloadFolderZip,
                    padding: EdgeInsets.zero,
                    onPressed: onDownloadFolder,
                    child: const Icon(CupertinoIcons.arrow_down_doc, size: 16),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < crumbs.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Icon(
                                CupertinoIcons.chevron_right,
                                size: 10,
                                color: LightSurfaces.resolve(
                                  context,
                                  LightSurfaces.textSecondary,
                                  dark: CupertinoColors.tertiaryLabel,
                                ),
                              ),
                            ),
                          CupertinoButton(
                            key: ValueKey('workspace-crumb-${crumbs[i].path}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            disabledColor: CupertinoColors.quaternaryLabel
                                .resolveFrom(context),
                            onPressed: crumbs[i].path == crumbs.last.path
                                ? null
                                : () => onCrumbTap(crumbs[i]),
                            child: Text(
                              crumbs[i].title,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? null
                                    : (crumbs[i].path == crumbs.last.path
                                          ? LightSurfaces.textSecondary
                                          : LightSurfaces.userDetail),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isRefreshing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CupertinoActivityIndicator(radius: 9),
                  const SizedBox(width: 8),
                  Text(
                    l10n.loadingIndicator,
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
            )
          else if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 14,
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      errorMessage!,
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
                  ),
                  CupertinoButton(
                    key: const ValueKey('workspace-banner-retry'),
                    padding: EdgeInsets.zero,
                    onPressed: onRetry,
                    child: Text(
                      l10n.retry,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? null : LightSurfaces.userDetail,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// 单行文件/目录（自绘行，对齐 Hermex FileBrowserRow：图标 + 名称 + 副标题）。
class _WorkspaceEntryRow extends StatefulWidget {
  const _WorkspaceEntryRow({
    super.key,
    required this.entry,
    required this.busy,
    required this.onTap,
    required this.onActions,
  });

  final WorkspaceEntry entry;
  final bool busy;
  final VoidCallback onTap;
  final void Function(GlobalKey anchorKey) onActions;

  @override
  State<_WorkspaceEntryRow> createState() => _WorkspaceEntryRowState();
}

class _WorkspaceEntryRowState extends State<_WorkspaceEntryRow> {
  final GlobalKey _actionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDirectory = widget.entry.isBrowsableDirectory;
    final detail = workspaceEntryDetail(widget.entry);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isDirectory) {
          widget.onTap();
        } else {
          widget.onActions(_actionKey);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _EntryIcon(entry: widget.entry),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.entry.name ?? l10n.unnamedFile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
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
            if (widget.busy)
              const CupertinoActivityIndicator(radius: 10)
            else if (isDirectory)
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.tertiaryLabel,
                ),
              )
            else
              KeyedSubtree(
                key: _actionKey,
                child: AccessibleButton(
                  key: ValueKey(
                    'workspace-actions-${widget.entry.name ?? widget.entry.path}',
                  ),
                  label: l10n.fileActions,
                  padding: EdgeInsets.zero,
                  onPressed: () => widget.onActions(_actionKey),
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
    );
  }
}

/// 条目类型图标（目录 / 按 type 与扩展名区分的文件图标）。
class _EntryIcon extends StatelessWidget {
  const _EntryIcon({required this.entry});

  final WorkspaceEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconFor(entry);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final resolvedIconColor = isDark
        ? color.resolveFrom(context)
        : _resolveLightIconColor(context, color);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        // 图标灰底属于配套装饰，保留系统 fill 并逐字节保留暗色解析
        color:
            (entry.isBrowsableDirectory
                    ? CupertinoColors.tertiarySystemFill
                    : CupertinoColors.secondarySystemFill)
                .resolveFrom(context),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 16, color: resolvedIconColor),
    );
  }

  static Color _resolveLightIconColor(
    BuildContext context,
    CupertinoDynamicColor color,
  ) {
    if (color == CupertinoColors.secondaryLabel) {
      return LightSurfaces.textSecondary;
    }
    if (color == CupertinoColors.systemGreen) {
      return statusGreenText.resolveFrom(context);
    }
    if (color == CupertinoColors.systemTeal) {
      return statusTealText.resolveFrom(context);
    }
    return color.resolveFrom(context);
  }

  static (IconData, CupertinoDynamicColor) _iconFor(WorkspaceEntry entry) {
    if (entry.isBrowsableDirectory) {
      return (CupertinoIcons.folder, CupertinoColors.label);
    }
    final type = (entry.type ?? '').toLowerCase();
    final name = (entry.name ?? '').toLowerCase();
    switch (type) {
      case 'image':
        return (CupertinoIcons.photo, CupertinoColors.systemBlue);
      case 'video':
        return (CupertinoIcons.film, CupertinoColors.systemPurple);
      case 'audio':
        return (CupertinoIcons.music_note, CupertinoColors.systemPink);
      case 'code':
        return (
          CupertinoIcons.chevron_left_slash_chevron_right,
          CupertinoColors.systemGreen,
        );
      case 'markdown':
      case 'text':
        return (CupertinoIcons.doc_text, CupertinoColors.systemTeal);
      default:
        break;
    }
    if (name.endsWith('.md') || name.endsWith('.txt')) {
      return (CupertinoIcons.doc_text, CupertinoColors.systemTeal);
    }
    if (name.endsWith('.dart') ||
        name.endsWith('.py') ||
        name.endsWith('.js') ||
        name.endsWith('.ts') ||
        name.endsWith('.json') ||
        name.endsWith('.yaml')) {
      return (
        CupertinoIcons.chevron_left_slash_chevron_right,
        CupertinoColors.systemGreen,
      );
    }
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp')) {
      return (CupertinoIcons.photo, CupertinoColors.systemBlue);
    }
    if (name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm')) {
      return (CupertinoIcons.film, CupertinoColors.systemPurple);
    }
    if (name.endsWith('.mp3') || name.endsWith('.wav')) {
      return (CupertinoIcons.music_note, CupertinoColors.systemPink);
    }
    return (CupertinoIcons.doc, CupertinoColors.secondaryLabel);
  }
}
