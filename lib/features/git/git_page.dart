import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/git_workspace.dart';
import '../../core/utils/accessibility.dart';
import '../../app/theme/layout_tokens.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/theme/typography_tokens.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../app/widgets/app_scrollbar.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import 'git_branch_tree.dart';
import 'git_providers.dart';
import '../../app/widgets/app_refresh_control.dart';

/// 宽屏左栏（变更列表）固定宽 380（批 4 设计稿 §P9「左 380 变更列表 + 右 diff」）。
///
/// 比工作区左栏（340）宽一档：这里每行要放下「文件路径 + 变更类型/增删行数 +
/// 暂存/丢弃两个操作」，380 是清单里最紧一档刚好不折行的宽度。右栏 diff 是
/// **工具型**内容（长行、缩进），故铺满、不设上限并可横向滚。
const double kWideGitChangesWidth = 380.0;

/// 会话工作区 Git 面板（对齐 Hermex GitWorkspaceView 的展示形态）。
///
/// 以 [sessionId] 定位会话工作区：分支选择（ActionSheet 切换本地分支）、
/// 状态列表（已暂存 / 未暂存分区）、文件 diff 展开查看、提交表单、
/// fetch / pull / push 按钮；含加载 / 错误 / 空态（非仓库 / 工作区干净）。
class GitPage extends ConsumerStatefulWidget {
  const GitPage({super.key, required this.sessionId});

  /// 会话 ID（服务器据此解析工作区路径）。
  final String sessionId;

  @override
  ConsumerState<GitPage> createState() => _GitPageState();
}

class _GitPageState extends ConsumerState<GitPage> {
  final TextEditingController _messageController = TextEditingController();

  /// 宽屏三处常显滚动条（G4）控制器：左栏列表 / diff 纵向 / diff 横向。
  final ScrollController _changesScrollController = ScrollController();
  final ScrollController _diffVerticalController = ScrollController();
  final ScrollController _diffHorizontalController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _changesScrollController.dispose();
    _diffVerticalController.dispose();
    _diffHorizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(gitControllerProvider(widget.sessionId));
    final state = async.valueOrNull;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('git-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.gitPanelTitle,
            leading: AppBackButton(fallback: '/chat/${widget.sessionId}'),
            trailing: AccessibleButton(
              key: const ValueKey('git-refresh'),
              label: l10n.refreshGitStatus,
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(
                ref
                    .read(gitControllerProvider(widget.sessionId).notifier)
                    .refresh(),
              ),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
            // 操作结果横幅：固定在导航栏底部，任何滚动位置都可见。
            bottom: _buildActionBanner(state),
          ),
          AppRefreshControl(
            onRefresh: () => ref
                .read(gitControllerProvider(widget.sessionId).notifier)
                .refresh(),
          ),
          ..._buildContentSlivers(ref, async, state),
        ],
      ),
    );
  }

  /// 操作结果横幅（错误红 / 成功绿），固定在导航栏底部，任何滚动位置可见。
  PreferredSizeWidget? _buildActionBanner(GitState? state) {
    final error = state?.actionError;
    final message = state?.actionMessage;
    if (error == null && message == null) return null;
    final isError = error != null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(52),
      child: _ActionBanner(
        key: ValueKey(isError ? 'git-action-error' : 'git-action-message'),
        text: isError ? error : message!,
        color: isError
            ? CupertinoColors.systemRed
            : CupertinoColors.systemGreen,
        isError: isError,
        onDismiss: () {
          final controller = ref.read(
            gitControllerProvider(widget.sessionId).notifier,
          );
          unawaited(
            isError
                ? controller.clearActionError()
                : controller.clearActionMessage(),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 面板正文
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    WidgetRef ref,
    AsyncValue<GitState> async,
    GitState? state,
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
      return [_buildErrorSliver(ref, async.error)];
    }

    if (state.isNonRepository) {
      return [_buildEmptySliver(l10n.notAGitRepo, l10n.notAGitRepoDetail)];
    }

    if (!state.isGitRepository) {
      // status 已加载但 is_git 缺失：按非仓库处理（容错）。
      return [_buildEmptySliver(l10n.notAGitRepo, l10n.notAGitRepoDetail)];
    }

    return [
      // 宽屏（≥900）：左 380 变更列表（四段保留）+ 右 diff 铺满。
      // 窄屏（<900）：竖排堆叠原样（diff 就地展开）。
      if (isWideLayout(context))
        _buildWideHostSliver(_buildWideBody(ref, state))
      else ...[
        _buildSummarySliver(ref, state),
        _buildBranchTreeSliver(ref, state),
        if (!state.hasCommittableChanges)
          SliverToBoxAdapter(child: _CleanWorkspacePlaceholder())
        else ...[
          if (state.stagedFiles.isNotEmpty)
            _buildFileSectionSliver(
              ref,
              state,
              l10n.stagedSection,
              state.stagedFiles,
            ),
          if (state.unstagedFiles.isNotEmpty)
            _buildFileSectionSliver(
              ref,
              state,
              l10n.unstagedSection,
              state.unstagedFiles,
            ),
        ],
        if (state.status?.truncated == true)
          SliverToBoxAdapter(child: _buildTruncatedWarning(l10n)),
        _buildCommitSliver(ref, state),
        _buildRemoteSliver(ref, state),
      ],
    ];
  }

  // -------------------------------------------------------------------------
  // 宽屏双栏（≥900）：左 380 变更列表 + 右 diff 铺满
  // -------------------------------------------------------------------------

  /// 双栏宿主：把「剩余视口高度」算准后交给两栏（两栏各自内部滚动）。
  ///
  /// 刻意**不用** `SliverFillRemaining`：`hasScrollBody: false` 会向子级要
  /// intrinsic 高度 —— 子级里含 viewport（左栏的 [CustomScrollView]）时直接抛
  /// `RenderViewport does not support returning intrinsic dimensions`；
  /// `hasScrollBody: true` 又把该 sliver 的 scrollExtent 记成「整幅视口高」，
  /// 外层会白白多出一段可滚动距离。显式按 `remainingPaintExtent` 定高，
  /// 既拿到确定的剩余高度，又让外层 maxScrollExtent 恰好为 0（下拉刷新靠
  /// overscroll 仍然可用）。
  Widget _buildWideHostSliver(Widget child) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        return SliverToBoxAdapter(
          child: SizedBox(
            height: constraints.remainingPaintExtent,
            child: child,
          ),
        );
      },
    );
  }

  /// 宽屏主体：左栏复用与窄屏**同一批 sliver**（摘要 / 分支树 / 已暂存 /
  /// 未暂存 / 提交 / 远程操作 —— 四段结构原样保留，唯一差别是 diff 不再内联），
  /// 固定 [kWideGitChangesWidth]；右栏 diff **铺满**（`Expanded`，不限宽 + 可横滚）。
  Widget _buildWideBody(WidgetRef ref, GitState state) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('git-wide-changes'),
          width: kWideGitChangesWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.divider,
                    dark: CupertinoColors.separator,
                  ),
                  width: 0.5,
                ),
              ),
            ),
            child: AppScrollbar(
              key: const ValueKey('git-wide-changes-scroll'),
              controller: _changesScrollController,
              child: CustomScrollView(
                controller: _changesScrollController,
                slivers: [
                  _buildSummarySliver(ref, state),
                  _buildBranchTreeSliver(ref, state),
                  if (!state.hasCommittableChanges)
                    SliverToBoxAdapter(child: _CleanWorkspacePlaceholder())
                  else ...[
                    if (state.stagedFiles.isNotEmpty)
                      _buildFileSectionSliver(
                        ref,
                        state,
                        l10n.stagedSection,
                        state.stagedFiles,
                        selectedHighlight: true,
                        inlineDiff: false,
                      ),
                    if (state.unstagedFiles.isNotEmpty)
                      _buildFileSectionSliver(
                        ref,
                        state,
                        l10n.unstagedSection,
                        state.unstagedFiles,
                        selectedHighlight: true,
                        inlineDiff: false,
                      ),
                  ],
                  if (state.status?.truncated == true)
                    SliverToBoxAdapter(child: _buildTruncatedWarning(l10n)),
                  _buildCommitSliver(ref, state),
                  _buildRemoteSliver(ref, state),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          key: const ValueKey('git-wide-diff-pane'),
          child: _buildWideDiffPane(state),
        ),
      ],
    );
  }

  /// 右侧 diff 栏：标题行（文件路径 + 加载中）＋ 正文（铺满 + 双向常显滚动条）。
  Widget _buildWideDiffPane(GitState state) {
    final l10n = AppLocalizations.of(context);
    final file = state.selectedFile;
    if (file == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.doc_text,
              size: 44,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.preview,
              key: const ValueKey('git-wide-diff-empty'),
              style: TextStyle(
                // TODO(type): 错用 (a)——15 写「说明文字」（应 kFontCaption/Body），值不动。
                fontSize: kFontItemTitle,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.divider,
                  dark: CupertinoColors.separator,
                ),
                width: 0.5,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    file.displayPath,
                    key: const ValueKey('git-wide-diff-path'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      // TODO(type): 12.5 未进梯子（diff 栏路径 → kFontCode 12）。
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (state.isDiffLoading)
                  const CupertinoActivityIndicator(radius: 8),
              ],
            ),
          ),
        ),
        Expanded(child: _buildWideDiffBody(state, l10n)),
      ],
    );
  }

  /// 宽屏 diff 正文：**铺满**（不限宽）＋ 横向滚动（长行不换行、可横滚）。
  Widget _buildWideDiffBody(GitState state, AppLocalizations l10n) {
    return Container(
      key: const ValueKey('git-diff'),
      color: gitDiffSurface(context),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: AppScrollbar(
        key: const ValueKey('git-wide-diff-scroll'),
        controller: _diffVerticalController,
        child: SingleChildScrollView(
          controller: _diffVerticalController,
          child: AppScrollbar(
            key: const ValueKey('git-wide-diff-hscroll'),
            controller: _diffHorizontalController,
            child: SingleChildScrollView(
              controller: _diffHorizontalController,
              scrollDirection: Axis.horizontal,
              child: Text(
                gitDiffText(state, l10n),
                key: const ValueKey('git-wide-diff-text'),
                softWrap: false,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  // TODO(type): 等宽 diff 应 kFontCode(12)；值 11 属既有口径，保持不动。
                  fontSize: kFontCode,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 文件数超限提示（窄屏 sliver 与宽屏左栏共用）。
  Widget _buildTruncatedWarning(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        l10n.tooManyChangedFilesWarning,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: kFontCaption,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: secondaryText,
          ),
        ),
      ),
    );
  }

  Widget _buildSummarySliver(WidgetRef ref, GitState state) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final branches = state.branches;
    final current = branches?.current ?? state.status?.branch;
    final ahead = state.status?.ahead ?? 0;
    final behind = state.status?.behind ?? 0;
    final additions = state.status?.totalAdditions ?? 0;
    final deletions = state.status?.totalDeletions ?? 0;
    final changed = state.status?.changedCount ?? 0;

    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        dividerMargin: 0,
        additionalDividerMargin: 0,
        decoration: isDark
            ? null
            : BoxDecoration(
                color: LightSurfaces.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
              ),
        separatorColor: isDark ? null : LightSurfaces.divider,
        children: [
          CupertinoListTile(
            leading: Icon(
              CupertinoIcons.arrow_branch,
              color: isDark
                  ? CupertinoColors.systemBlue
                  : statusBlueText.resolveFrom(context),
            ),
            title: Text(
              current?.isNotEmpty == true ? current! : l10n.unknownBranch,
            ),
            subtitle: Text(
              ahead > 0 || behind > 0
                  ? l10n.aheadBehind(ahead, behind)
                  : l10n.syncedWithRemote,
              style: isDark
                  ? null
                  : const TextStyle(color: LightSurfaces.textSecondary),
            ),
            trailing: CupertinoButton(
              key: const ValueKey('git-branch-picker'),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: branches == null || state.isActionRunning
                  ? null
                  : () => unawaited(_showBranchPicker(ref, state)),
              child: Text(
                l10n.switchBranch,
                style: TextStyle(
                  color: isDark
                      ? null
                      : (branches == null || state.isActionRunning
                            ? LightSurfaces.textSecondary
                            : LightSurfaces.userDetail),
                ),
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.changesLabel),
            subtitle: Text(
              l10n.changesSummary(additions, deletions, changed),
              style: isDark
                  ? null
                  : const TextStyle(color: LightSurfaces.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchTreeSliver(WidgetRef ref, GitState state) {
    final controller = ref.read(
      gitControllerProvider(widget.sessionId).notifier,
    );
    return SliverToBoxAdapter(
      child: GitBranchTree(
        branches: state.branches,
        currentBranch: state.branches?.current ?? state.status?.branch,
        isActionRunning: state.isActionRunning,
        isLoading: state.isBranchesLoading,
        errorMessage: state.branchesError,
        onCheckout: (refName) => unawaited(controller.checkout(refName)),
        onReload: () => unawaited(controller.reloadBranches()),
      ),
    );
  }

  Widget _buildFileSectionSliver(
    WidgetRef ref,
    GitState state,
    String header,
    List<GitFile> files, {
    bool selectedHighlight = false,
    bool inlineDiff = true,
  }) {
    final controller = ref.read(
      gitControllerProvider(widget.sessionId).notifier,
    );
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        dividerMargin: 0,
        additionalDividerMargin: 0,
        decoration: isDark
            ? null
            : BoxDecoration(
                color: LightSurfaces.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
              ),
        separatorColor: isDark ? null : LightSurfaces.divider,
        header: Text(header),
        children: [
          for (final file in files) ...[
            _FileTile(
              file: file,
              expanded: state.selectedFile?.id == file.id,
              // 选中态底高亮只在宽屏左栏开（窄屏竖排保持原样、逐像素不变）。
              selected: selectedHighlight && state.selectedFile?.id == file.id,
              isActionRunning: state.isActionRunning,
              onTap: () => unawaited(controller.selectFile(file)),
              onStage: file.staged == true
                  ? () => unawaited(controller.unstage([_filePath(file)]))
                  : () => unawaited(controller.stage([_filePath(file)])),
              onDiscard: () => unawaited(controller.discard([_filePath(file)])),
            ),
            // 宽屏 diff 搬到右栏（inlineDiff=false）→ 左栏不再内联展开。
            if (inlineDiff && state.selectedFile?.id == file.id)
              _DiffExpansion(state: state),
          ],
        ],
      ),
    );
  }

  Widget _buildCommitSliver(WidgetRef ref, GitState state) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(
      gitControllerProvider(widget.sessionId).notifier,
    );
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        dividerMargin: 0,
        additionalDividerMargin: 0,
        decoration: isDark
            ? null
            : BoxDecoration(
                color: LightSurfaces.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
              ),
        separatorColor: isDark ? null : LightSurfaces.divider,
        header: Text(l10n.commitSection),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: CupertinoTextField(
                    key: const ValueKey('git-commit-message'),
                    controller: _messageController,
                    placeholder: l10n.commitMessagePlaceholder,
                    placeholderStyle: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.placeholder,
                        dark: CupertinoColors.placeholderText,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 3,
                    enabled: !state.isActionRunning,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton.filled(
                  key: const ValueKey('git-commit-button'),
                  color: isDark ? null : LightSurfaces.userDetail,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onPressed: state.isActionRunning
                      ? null
                      : () {
                          final message = _messageController.text.trim();
                          if (message.isEmpty) return;
                          unawaited(
                            controller.commit(message).then((ok) {
                              if (ok && mounted) {
                                _messageController.clear();
                              }
                            }),
                          );
                        },
                  child: Text(l10n.commitButton),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteSliver(WidgetRef ref, GitState state) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(
      gitControllerProvider(widget.sessionId).notifier,
    );
    final running = state.isActionRunning;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        dividerMargin: 0,
        additionalDividerMargin: 0,
        decoration: isDark
            ? null
            : BoxDecoration(
                color: LightSurfaces.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
              ),
        separatorColor: isDark ? null : LightSurfaces.divider,

        header: Text(l10n.remoteOperations),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoButton.filled(
                    key: const ValueKey('git-fetch'),
                    color: isDark ? null : LightSurfaces.userDetail,
                    onPressed: running
                        ? null
                        : () => unawaited(controller.fetchRemote()),
                    child: const Text('fetch'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoButton.filled(
                    key: const ValueKey('git-pull'),
                    color: isDark ? null : LightSurfaces.userDetail,
                    onPressed: running
                        ? null
                        : () => unawaited(controller.pullRemote()),
                    child: const Text('pull'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoButton.filled(
                    key: const ValueKey('git-push'),
                    color: isDark ? null : LightSurfaces.userDetail,
                    onPressed: running
                        ? null
                        : () => unawaited(controller.pushRemote()),
                    child: const Text('push'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSliver(WidgetRef ref, Object? error) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
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
              color: isDark
                  ? CupertinoColors.systemGrey
                  : LightSurfaces.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              // TODO(type): 空态/错误标题语义应 kFontItemTitle(15)；值 17 不动。
              style: const TextStyle(
                fontSize: kFontItemTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kFontLabel,
                color: statusRedText.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('git-retry'),
              color: isDark ? null : LightSurfaces.userDetail,
              onPressed: () => unawaited(
                ref
                    .read(gitControllerProvider(widget.sessionId).notifier)
                    .refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver(String title, String detail) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
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
              color: isDark
                  ? CupertinoColors.systemGrey
                  : LightSurfaces.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              // TODO(type): 空态标题语义应 kFontItemTitle(15)；值 17 不动。
              style: const TextStyle(
                fontSize: kFontPageTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kFontLabel,
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

  Future<void> _showBranchPicker(WidgetRef ref, GitState state) async {
    final l10n = AppLocalizations.of(context);
    final local = (state.branches?.local ?? const <GitBranchRef>[])
        .where((b) => b.name != null && b.name!.trim().isNotEmpty)
        .toList(growable: false);
    if (local.isEmpty) {
      await ref
          .read(gitControllerProvider(widget.sessionId).notifier)
          .reloadBranches();
      return;
    }
    final current = state.branches?.current;
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (modalContext) {
        final isDark =
            CupertinoTheme.brightnessOf(modalContext) == Brightness.dark;
        return CupertinoActionSheet(
          title: Text(
            l10n.switchBranch,
            style: isDark
                ? null
                : const TextStyle(color: LightSurfaces.textSecondary),
          ),
          actions: [
            for (final branch in local)
              CupertinoActionSheetAction(
                key: ValueKey('git-branch-${branch.name}'),
                isDefaultAction: branch.name == current,
                onPressed: () => Navigator.pop(modalContext, branch.name),
                child: Text(
                  branch.name!,
                  style: isDark
                      ? null
                      : const TextStyle(color: LightSurfaces.menuAction),
                ),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(modalContext),
            child: Text(
              l10n.cancel,
              style: isDark
                  ? null
                  : const TextStyle(color: LightSurfaces.menuAction),
            ),
          ),
        );
      },
    );
    if (selected != null && selected != current && mounted) {
      unawaited(
        ref
            .read(gitControllerProvider(widget.sessionId).notifier)
            .checkout(selected),
      );
    }
  }

  static String _filePath(GitFile file) {
    final path = file.displayPath;
    return path.isEmpty ? file.oldPath ?? '' : path;
  }

  String _errorMessage(Object? error) {
    if (error is Exception) return gitFriendlyError(error);
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

// ---------------------------------------------------------------------------
// 文件行
// ---------------------------------------------------------------------------

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.expanded,
    required this.isActionRunning,
    required this.onTap,
    required this.onStage,
    required this.onDiscard,
    this.selected = false,
  });

  final GitFile file;
  final bool expanded;
  final bool isActionRunning;
  final VoidCallback onTap;
  final VoidCallback onStage;
  final VoidCallback onDiscard;

  /// 宽屏左栏选中态（L2）；窄屏恒 false（行底逐像素不变）。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final kind = file.changeKind;
    return CupertinoListTile(
      key: ValueKey('git-file-${file.id}'),
      // L2 选中底：浅色中性灰 .16、暗色 primary 12%（与左导航行同口径）。
      backgroundColor: selected
          ? (isDark
                ? CupertinoTheme.of(context).primaryColor
                      .withValues(alpha: 0.12)
                : LightSurfaces.selectedSurface)
          : null,
      leading: Icon(_kindIcon(kind), color: _kindColor(context, kind)),
      title: Text(
        file.displayPath,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_kindLabel(context, kind)}'
        '${(file.additions ?? 0) > 0 ? ' +${file.additions}' : ''}'
        '${(file.deletions ?? 0) > 0 ? ' −${file.deletions}' : ''}',
        style: isDark
            ? null
            : const TextStyle(color: LightSurfaces.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton(
            key: ValueKey(
              file.staged == true
                  ? 'git-unstage-${file.id}'
                  : 'git-stage-${file.id}',
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: isActionRunning ? null : onStage,
            child: Text(
              file.staged == true ? l10n.unstageAction : l10n.stageAction,
              style: TextStyle(
                fontSize: kFontButton,
                color: isDark
                    ? null
                    : (isActionRunning
                          ? LightSurfaces.textSecondary
                          : LightSurfaces.userDetail),
              ),
            ),
          ),
          AccessibleButton(
            key: ValueKey('git-discard-${file.id}'),
            label: l10n.discardChanges,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onPressed: isActionRunning ? null : onDiscard,
            child: Icon(
              CupertinoIcons.trash,
              size: 16,
              color: isDark
                  ? CupertinoColors.systemRed
                  : statusRedText.resolveFrom(context),
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  static IconData _kindIcon(GitFileChangeKind kind) {
    switch (kind) {
      case GitFileChangeKind.added:
        return CupertinoIcons.plus_circle;
      case GitFileChangeKind.deleted:
        return CupertinoIcons.minus_circle;
      case GitFileChangeKind.renamed:
        return CupertinoIcons.arrow_swap;
      case GitFileChangeKind.conflict:
        return CupertinoIcons.exclamationmark_triangle;
      case GitFileChangeKind.untracked:
        return CupertinoIcons.question_circle;
      case GitFileChangeKind.ignored:
        return CupertinoIcons.eye_slash;
      case GitFileChangeKind.modified:
      case GitFileChangeKind.unknown:
        return CupertinoIcons.pencil_circle;
    }
  }

  static Color _kindColor(BuildContext context, GitFileChangeKind kind) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    if (isDark) {
      switch (kind) {
        case GitFileChangeKind.added:
        case GitFileChangeKind.renamed:
          return CupertinoColors.systemGreen;
        case GitFileChangeKind.deleted:
          return CupertinoColors.systemRed;
        case GitFileChangeKind.conflict:
          return CupertinoColors.systemOrange;
        case GitFileChangeKind.untracked:
          return CupertinoColors.systemGrey;
        case GitFileChangeKind.ignored:
          return CupertinoColors.systemGrey2;
        case GitFileChangeKind.modified:
        case GitFileChangeKind.unknown:
          return CupertinoColors.systemBlue;
      }
    }
    switch (kind) {
      case GitFileChangeKind.added:
      case GitFileChangeKind.renamed:
        return statusGreenText.resolveFrom(context);
      case GitFileChangeKind.deleted:
        return statusRedText.resolveFrom(context);
      case GitFileChangeKind.conflict:
        return statusOrangeText.resolveFrom(context);
      case GitFileChangeKind.untracked:
        return LightSurfaces.textSecondary;
      case GitFileChangeKind.ignored:
        return LightSurfaces.placeholder;
      case GitFileChangeKind.modified:
      case GitFileChangeKind.unknown:
        return statusBlueText.resolveFrom(context);
    }
  }

  static String _kindLabel(BuildContext context, GitFileChangeKind kind) {
    final l10n = AppLocalizations.of(context);
    switch (kind) {
      case GitFileChangeKind.added:
        return l10n.gitChangeAdded;
      case GitFileChangeKind.deleted:
        return l10n.gitChangeDeleted;
      case GitFileChangeKind.renamed:
        return l10n.gitChangeRenamed;
      case GitFileChangeKind.conflict:
        return l10n.gitChangeConflict;
      case GitFileChangeKind.untracked:
        return l10n.gitChangeUntracked;
      case GitFileChangeKind.ignored:
        return l10n.gitChangeIgnored;
      case GitFileChangeKind.modified:
      case GitFileChangeKind.unknown:
        return l10n.gitChangeModified;
    }
  }
}

// ---------------------------------------------------------------------------
// diff 展开区
// ---------------------------------------------------------------------------

/// diff 块底色：浅色 [LightSurfaces.page]，暗色沿用 `secondarySystemBackground`。
///
/// 修复（真渲染目检发现，原注释自认「旧暗问题待裁」）：
/// `CupertinoColors.secondarySystemBackground` 是 dynamic color，直接交给
/// `Container.color` **不会**按亮度解析 —— 暗色下落到浅色 raw 值 (#F2F2F7)，
/// 而正文文字继承主题为浅色 ⇒ 白字叠浅底、几乎不可读。
/// 改走 [LightSurfaces.resolve]：暗色分支内部会 `CupertinoDynamicColor.resolve`
/// ⇒ 解析为暗色 #1C1C1E；浅色仍是 page。
///
/// **宽窄两处共用同一份实现** —— 抽出成函数就是为了让「原地展开（窄屏）」与
/// 「右栏铺满（宽屏）」不可能各自漂移回未解析的 dynamic color。
Color gitDiffSurface(BuildContext context) => LightSurfaces.resolve(
  context,
  LightSurfaces.page,
  dark: CupertinoColors.secondarySystemBackground,
);

/// diff 正文文案（含不可用 / 二进制 / 过大 / 空态兜底）；宽窄两处共用。
String gitDiffText(GitState state, AppLocalizations l10n) {
  final diff = state.diff;
  if (diff == null) return l10n.cannotLoadDiff;
  if (diff.binary == true) return l10n.binaryFileCannotShowDiff;
  final text = diff.diff ?? '';
  if (text.isEmpty) return l10n.noDiffContent;
  if (diff.tooLarge == true) return l10n.fileTooLargePartialContent(text);
  return text;
}

class _DiffExpansion extends StatelessWidget {
  const _DiffExpansion({required this.state});

  final GitState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.isDiffLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CupertinoActivityIndicator(radius: 10)),
      );
    }
    return Container(
      key: const ValueKey('git-diff'),
      width: double.infinity,
      color: gitDiffSurface(context),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Text(
        gitDiffText(state, l10n),
        style: const TextStyle(
          fontFamily: 'monospace',
          // TODO(type): 等宽 diff 应 kFontCode(12)；值 11 属既有口径，保持不动。
          fontSize: kFontCode,
          height: 1.4,
        ),
      ),
    );
  }
}

class _CleanWorkspacePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.checkmark_circle,
            size: 44,
            color: isDark
                ? CupertinoColors.systemGreen
                : statusGreenText.resolveFrom(context),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.workspaceClean,
            // TODO(type): 16 未进梯子（空态标题应与同文件 17 档统一，语义 → kFontItemTitle 15）。
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.noPendingChanges,
            style: TextStyle(
              fontSize: kFontLabel,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 操作结果横幅
// ---------------------------------------------------------------------------

class _ActionBanner extends StatelessWidget {
  const _ActionBanner({
    super.key,
    required this.text,
    required this.color,
    required this.onDismiss,
    this.isError = false,
  });

  final String text;
  final Color color;
  final VoidCallback onDismiss;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    // 暗色逐字节保留原 raw 绘制值（未 resolve 的 systemRed/systemGreen 及其 alpha 0.12 底色）
    final Color bgColor;
    final Color textColor;
    final Border? border;

    if (isDark) {
      bgColor = color.withValues(alpha: 0.12);
      textColor = color;
      border = null;
    } else {
      bgColor = isError ? LightSurfaces.tintError : LightSurfaces.tintGreen;
      textColor = isError
          ? statusRedText.resolveFrom(context)
          : statusGreenText.resolveFrom(context);
      border = Border.all(color: LightSurfaces.cardBorder, width: 0.5);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: border,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: kFontLabel, color: textColor),
              ),
            ),
            AccessibleButton(
              key: const ValueKey('git-banner-dismiss'),
              label: l10n.closeNotice,
              onPressed: onDismiss,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 16,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
