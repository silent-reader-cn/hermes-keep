import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client_sessions.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/session.dart';
import '../../core/models/workspace.dart';
import '../../core/utils/accessibility.dart';
import '../../core/utils/safe_clipboard.dart';
import '../../app/shell/adaptive_shell.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_action_menu.dart';
import '../../app/widgets/narrow_navigation_dropdown.dart';
import '../../l10n/app_localizations.dart';
import '../desktop/desktop_settings.dart';
import '../projects/project_picker_sheet.dart';
import '../projects/project_providers.dart';
import '../settings/settings_providers.dart';
import '../settings/settings_surfaces.dart';
import '../shared/app_navigation.dart';
import 'session_auto_refresh.dart';
import 'session_list_header.dart';
import 'session_list_providers.dart';
import 'session_list_utility_rows.dart';
import 'session_row_subtitle_settings.dart';

/// 会话列表页（app_shell_spec.md §3：`/` 为主列表）。
///
/// Cupertino 风格：大标题 + 搜索框（防抖远程搜索）+ 下拉刷新 + 无限滚动分页 +
/// 会话分区（置顶/今天/昨天/更早）+ 行快捷操作（pin/archive/branch/delete 弹
/// 菜单）+ 悬浮新建会话按钮。会话点击 → `/chat/:sessionId`。
class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({
    super.key,
    this.showUtilityRows = true,
    this.showSettingsTrailing = true,
    this.showFab = true,
  });

  /// 是否渲染顶部工具行入口（任务/看板/技能/记忆/统计）。
  ///
  /// 宽屏双栏外壳的侧栏顶部已有 [SidebarUtilityToolbar] 承担工具入口
  /// （含设置与激活高亮），故侧栏内复用的会话列表传 `false` 避免双层
  /// 入口重叠；手机单栈（窄屏）保持默认 `true`。
  final bool showUtilityRows;

  /// 是否渲染头部右侧的设置入口（齿轮）。
  ///
  /// 宽屏侧栏顶部 [SidebarUtilityToolbar] 已有设置图标，为避免桌面端双
  /// 入口，侧栏内复用的会话列表传 `false`；手机单栈保持默认 `true`。
  final bool showSettingsTrailing;

  /// 是否渲染悬浮新建会话按钮（FAB）。
  ///
  /// 手机单栈（窄屏）保持默认 `true`；桌面侧栏场景隐藏 FAB，新建入口由
  /// 头部右上角按钮承担（见 [SessionListHeaderDelegate.actions]）。
  final bool showFab;

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  /// 窄屏「点击大标题 = 点击 ▾」的请求通道（#128）。
  ///
  /// 「会话」大标题由 [SessionListHeaderDelegate] 自绘，触达不了
  /// [NarrowNavigationDropdownButton] 内部状态，故由页面持有通道：
  /// 标题 onTap → 自增 → ▾ 打开同一个快捷导航下拉（锚点仍是 ▾）。
  final ValueNotifier<int> _narrowNavOpenSignal = ValueNotifier<int>(0);

  // FAB 悬浮加号长按工作区滑选状态与弹层
  OverlayEntry? _fabWorkspaceOverlayEntry;
  Timer? _fabLongPressTimer;
  int? _hoveredWorkspaceIndex;
  List<WorkspaceRoot> _fabRankedWorkspaces = const [];
  bool _fabMenuOpen = false;
  bool _suppressNextTap = false;
  final GlobalKey _fabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _fabLongPressTimer?.cancel();
    _hideFabWorkspaceOverlay();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _narrowNavOpenSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sessionListControllerProvider);
    final state = async.valueOrNull;
    final sections = ref.watch(sessionListSectionsProvider);
    final isSearchMode = state?.searchQuery?.trim().isNotEmpty == true;
    // 会话行副标题显示开关（设置页配置）+ projectId→名称映射（同屏一次解析）。
    final subtitleSettings = ref.watch(sessionRowSubtitleSettingsProvider);
    final projectNames = _projectNameMap(ref);

    ref.listen<AsyncValue<SessionListState>>(sessionListControllerProvider, (
      previous,
      next,
    ) {
      final error = next.valueOrNull?.actionError;
      if (error != null && error != previous?.valueOrNull?.actionError) {
        unawaited(_showActionError(context, error));
      }
    });

    // 首帧后自动补充分页窗口，直到填满视口或耗尽（内容不足一屏时也能翻页）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());

    final l10n = AppLocalizations.of(context);
    final isDesktop = isDesktopPlatform();
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final showDesktopRefresh = isDesktop && isWide;
    final refreshing = ref.watch(sessionListRefreshingProvider);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final content = SessionAutoRefreshObserver(
      child: CupertinoPageScaffold(
        backgroundColor: isLight ? LightSurfaces.page : null,
        child: Stack(
          children: [
            CustomScrollView(
              key: const ValueKey('session-list-scroll'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: SessionListHeaderDelegate(
                    title: l10n.sessions,
                    topPadding: MediaQuery.paddingOf(context).top,
                    brightness:
                        CupertinoTheme.of(context).brightness ??
                        Brightness.light,
                    // 侧栏复用（showUtilityRows=false）→ 紧凑头部：不渲染「会话」
                    // 大标题，搜索框与操作按钮（筛选/加号）整合为单行 pinned 头部；
                    // 手机端单栈 → 宽敞大标题头部（49pt）。
                    compactHeader: !widget.showUtilityRows,
                    searchField: !widget.showUtilityRows
                        ? _buildSearchField()
                        : null,
                    titleTrailing: !isWide && !isSearchMode
                        ? _buildNarrowNavigationAction()
                        : null,
                    // #128：窄屏点击「会话」大标题（及收起态中标题）= 点击 ▾；
                    // 条件与 titleTrailing 完全一致（无 ▾ 则不接线、点击无效）。
                    onTitleTap: !isWide && !isSearchMode
                        ? _requestNarrowNavMenu
                        : null,
                    actions: [
                      if (!isSearchMode) _buildFilterAction(state),
                      if (widget.showSettingsTrailing)
                        _buildSettingsOrDoneAction(state),
                      if (!widget.showUtilityRows) _buildNewSessionAction(),
                      if (showDesktopRefresh)
                        _buildDesktopRefreshAction(refreshing),
                    ],
                  ),
                ),
                // 注意：刷新指示器必须排在所有 SliverToBoxAdapter 之前
                // （视口会把 overscroll 逐级分给前面的 box sliver，导致
                // 指示器拿不到负 overlap 而无法触发）。
                CupertinoSliverRefreshControl(onRefresh: _onRefresh),
                if (widget.showUtilityRows)
                  SliverToBoxAdapter(child: _buildSearchBar()),
                if (widget.showUtilityRows && !isSearchMode && isWide)
                  const SliverToBoxAdapter(child: SessionListUtilityRows()),
                ..._buildContentSlivers(
                  async,
                  state,
                  sections,
                  isSearchMode,
                  subtitleSettings,
                  projectNames,
                ),
              ],
            ),
            if (state?.isSelectionMode == true)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBatchBar(state!),
              ),
            // 桌面侧栏场景隐藏 FAB（新建入口在头部右上角，见
            // [SessionListHeaderDelegate.actions]）。
            if (widget.showFab)
              Positioned(
                right: 20,
                bottom: state?.isSelectionMode == true ? 76 : 24,
                child: Listener(
                  onPointerDown: (event) => _onFabPointerDown(event, state),
                  onPointerMove: _onFabPointerMove,
                  onPointerUp: _onFabPointerUp,
                  onPointerCancel: _onFabPointerCancel,
                  child: AccessibleButton.filled(
                    key: const ValueKey('session-list-new'),
                    label: l10n.newSession,
                    onPressed: () {
                      if (_suppressNextTap) {
                        _suppressNextTap = false;
                        return;
                      }
                      unawaited(_onNewSession(context));
                    },
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(56, 56),
                    borderRadius: BorderRadius.circular(28),
                    child: SizedBox(
                      key: _fabKey,
                      width: 56,
                      height: 56,
                      child: const Center(
                        child: Icon(CupertinoIcons.add, size: 26),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    // Scope the new bar/page surfaces to this page and its sidebar reuse.
    return isLight
        ? CupertinoTheme(
            data: CupertinoTheme.of(context).copyWith(
              scaffoldBackgroundColor: LightSurfaces.page,
              barBackgroundColor: LightSurfaces.page,
            ),
            child: content,
          )
        : content;
  }

  // -------------------------------------------------------------------------
  // 顶部 chrome
  // -------------------------------------------------------------------------

  Widget _buildDesktopRefreshAction(bool refreshing) {
    final l10n = AppLocalizations.of(context);
    return AccessibleButton(
      key: const ValueKey('session-list-desktop-refresh'),
      // 避免新增 l10n 键，复用刷新相关语义
      label: l10n.refreshInsights,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: refreshing
          ? null
          : () => unawaited(
              ref
                  .read(sessionListControllerProvider.notifier)
                  .refreshIfStale(force: true),
            ),
      child: refreshing
          ? const CupertinoActivityIndicator(radius: 10)
          : const Icon(CupertinoIcons.refresh, size: 22),
    );
  }

  Widget _buildSearchField() {
    final l10n = AppLocalizations.of(context);
    return CupertinoSearchTextField(
      key: const ValueKey('session-list-search'),
      controller: _searchController,
      placeholder: l10n.searchSessions,
      decoration: CupertinoTheme.brightnessOf(context) == Brightness.light
          ? BoxDecoration(
              color: LightSurfaces.card,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
            )
          : null,
      placeholderStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
          ? const TextStyle(color: LightSurfaces.placeholder)
          : null,
      itemColor: LightSurfaces.resolve(
        context,
        LightSurfaces.textSecondary,
        dark: CupertinoColors.secondaryLabel,
      ),
      onChanged: _onSearchChanged,
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: _buildSearchField(),
    );
  }

  /// 头部窄屏快捷导航下拉按钮（大标题右侧向下箭头，点击展开 5 个功能入口）。
  ///
  /// #128：透传打开通道 —— 点击「会话」大标题即视同点击本按钮。
  Widget _buildNarrowNavigationAction() {
    return NarrowNavigationDropdownButton(
      buttonKey: const ValueKey('session-list-narrow-nav'),
      openSignal: _narrowNavOpenSignal,
    );
  }

  /// 大标题（含收起态中标题）点击 → 请求打开窄屏快捷导航下拉（#128）。
  ///
  /// 以实例方法 tear-off 传给 [SessionListHeaderDelegate]：引用稳定，
  /// 不会让 `shouldRebuild` 因闭包身份每次 build 都判真而重建头部。
  void _requestNarrowNavMenu() {
    _narrowNavOpenSignal.value = _narrowNavOpenSignal.value + 1;
  }

  /// 头部筛选入口按钮（「会话」右侧向下箭头，点击展开筛选弹层）。
  Widget _buildFilterAction(SessionListState? state) {
    final l10n = AppLocalizations.of(context);
    return AccessibleButton(
      key: const ValueKey('session-list-filter-trigger'),
      label: l10n.filterSessions,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () {
        if (state != null) _showFilterSheet(state);
      },
      child: const Icon(CupertinoIcons.line_horizontal_3_decrease, size: 22),
    );
  }

  /// 头部设置 / 完成选择按钮（手机单栈右侧齿轮；选择模式下切换为完成）。
  Widget _buildSettingsOrDoneAction(SessionListState? state) {
    final l10n = AppLocalizations.of(context);
    return AccessibleButton(
      key: state?.isSelectionMode == true
          ? const ValueKey('session-list-selection-done')
          : const ValueKey('session-list-settings'),
      label: state?.isSelectionMode == true
          ? l10n.doneSelecting
          : l10n.settings,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () {
        final controller = ref.read(sessionListControllerProvider.notifier);
        if (state?.isSelectionMode == true) {
          controller.clearSelection();
        } else {
          openAdaptiveRoute(context, '/settings');
        }
      },
      child: Icon(
        state?.isSelectionMode == true
            ? CupertinoIcons.xmark
            : CupertinoIcons.gear_alt,
        size: 22,
      ),
    );
  }

  /// 头部新建会话按钮（桌面侧栏场景替代 FAB）。
  Widget _buildNewSessionAction() {
    final l10n = AppLocalizations.of(context);
    return AccessibleButton(
      key: const ValueKey('session-list-header-new'),
      label: l10n.newSession,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () => unawaited(_onNewSession(context)),
      child: const Icon(CupertinoIcons.add, size: 22),
    );
  }

  /// 打开筛选底部弹层（全部/已归档 + 渠道 + 项目）。
  void _showFilterSheet(SessionListState state) {
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => _SessionFilterSheet(
          state: state,
          onSelect: (mode, value) {
            // 先关弹层，再触发过滤（过滤失败也不卡住弹层）。
            Navigator.pop(sheetContext);
            unawaited(
              ref
                  .read(sessionListControllerProvider.notifier)
                  .setFilter(mode, value: value),
            );
          },
        ),
      ),
    );
  }

  /// 底部批量操作栏（多选模式）：选中计数 + 全选 / 归档 / 删除 / 移动项目。
  Widget _buildBatchBar(SessionListState state) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(sessionListControllerProvider.notifier);
    final count = state.selectedSessionIds.length;
    return Container(
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.systemBackground,
        ),
        border: Border(
          top: BorderSide(
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.divider,
              dark: CupertinoColors.separator,
            ),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.selectedCount(count),
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CupertinoButton(
                key: const ValueKey('batch-select-all'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: controller.selectAllInSection,
                child: Text(
                  l10n.selectAll,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              CupertinoButton(
                key: const ValueKey('batch-archive'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: count == 0
                    ? null
                    : () => unawaited(_confirmBatchArchive(context)),
                child: Text(l10n.archive, style: const TextStyle(fontSize: 14)),
              ),
              CupertinoButton(
                key: const ValueKey('batch-delete'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: count == 0
                    ? null
                    : () => unawaited(_confirmBatchDelete(context)),
                child: Text(
                  l10n.delete,
                  style: TextStyle(
                    fontSize: 14,
                    color: LightSurfaces.resolve(
                      context,
                      statusRedText.resolveFrom(context),
                      dark: CupertinoColors.systemRed,
                    ),
                  ),
                ),
              ),
              CupertinoButton(
                key: const ValueKey('batch-move'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: count == 0
                    ? null
                    : () => unawaited(_batchMoveToProject(context)),
                child: Text(
                  l10n.batchMoveProject,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 分区列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<SessionListState> async,
    SessionListState? state,
    List<SessionListSection> sections,
    bool isSearchMode,
    SessionRowSubtitleSettings subtitleSettings,
    Map<String, String> projectNames,
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

    final hasVisible = sections.any((section) => section.sessions.isNotEmpty);
    if (!hasVisible) {
      return [_buildEmptySliver(isSearchMode: isSearchMode)];
    }

    final l10n = AppLocalizations.of(context);
    return [
      for (final section in sections)
        if (section.sessions.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  20.0,
                  16.0,
                  20.0,
                  6.0,
                ),
                child: DefaultTextStyle(
                  style: CupertinoTheme.of(context).textTheme.textStyle.merge(
                    const TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: Text(_sectionTitle(context, section.title)),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              20.0,
              0.0,
              20.0,
              10.0,
            ),
            sliver: DecoratedSliver(
              decoration: ShapeDecoration(
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.card,
                  dark: CupertinoColors.secondarySystemGroupedBackground,
                ),
                shape: RoundedSuperellipseBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(10.0)),
                  side: CupertinoTheme.brightnessOf(context) == Brightness.light
                      ? const BorderSide(
                          color: LightSurfaces.cardBorder,
                          width: 0.5,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        )
                      : BorderSide.none,
                ),
              ),
              sliver: SliverList.separated(
                itemCount: section.sessions.length,
                findItemIndexCallback: (Key key) {
                  if (key is ValueKey<String>) {
                    final value = key.value;
                    if (value.startsWith('session-row-')) {
                      final id = value.substring('session-row-'.length);
                      final index = section.sessions.indexWhere(
                        (s) => (s.sessionId ?? s.id) == id,
                      );
                      return index >= 0 ? index : null;
                    }
                  }
                  return null;
                },
                itemBuilder: (context, index) {
                  final session = section.sessions[index];
                  return _SessionRow(
                    key: ValueKey(
                      'session-row-${session.sessionId ?? session.id}',
                    ),
                    session: session,
                    subtitleSettings: subtitleSettings,
                    projectNames: projectNames,
                    highlightQuery: isSearchMode
                        ? state.searchQuery?.trim()
                        : null,
                    selectionMode: state.isSelectionMode,
                    selected: state.selectedSessionIds.contains(
                      session.sessionId ?? session.id,
                    ),
                    onTap: () => state.isSelectionMode
                        ? ref
                              .read(sessionListControllerProvider.notifier)
                              .toggleSelection(session.sessionId ?? session.id)
                        : _openSession(context, session),
                    onLongPress: () => ref
                        .read(sessionListControllerProvider.notifier)
                        .toggleSelection(session.sessionId ?? session.id),
                    onActions: state.isSelectionMode
                        ? null
                        : (anchorKey) =>
                              _showRowActions(context, session, anchorKey),
                  );
                },
                // #28 分割线全宽：dividerMargin 0，全长贯穿
                separatorBuilder: (context, index) => Container(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.divider,
                    dark: CupertinoColors.separator,
                  ),
                  height: 1.0 / MediaQuery.devicePixelRatioOf(context),
                ),
              ),
            ),
          ),
        ],
      if (state.hasMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CupertinoActivityIndicator(radius: 12)),
          ),
        ),
      if (!state.hasMore &&
          state.displaySessions.length > SessionListState.pageSize)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                l10n.noMore,
                style: TextStyle(
                  fontSize: 13,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: secondaryText,
                  ),
                ),
              ),
            ),
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
                // Preserve the previously unresolved dark icon paint value,
                // including in high contrast mode.
                dark: const Color(0xFF8E8E93),
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
              key: const ValueKey('session-list-retry'),
              onPressed: () => unawaited(
                ref.read(sessionListControllerProvider.notifier).refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver({required bool isSearchMode}) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearchMode
                  ? CupertinoIcons.search
                  : CupertinoIcons.chat_bubble_2,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                // Preserve the previously unresolved dark icon paint value,
                // including in high contrast mode.
                dark: const Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isSearchMode ? l10n.noMatchingSessionsFound : l10n.noSessions,
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              isSearchMode
                  ? l10n.tryAnotherKeyword
                  : l10n.tapButtonToStartNewChat,
              style: TextStyle(
                fontSize: 13,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
            if (!isSearchMode) ...[
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('session-list-empty-new'),
                onPressed: () => unawaited(_onNewSession(context)),
                child: Text(l10n.newSession),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 交互：刷新 / 分页 / 搜索 / 新建 / 打开 / 行操作
  // -------------------------------------------------------------------------

  /// 下拉刷新：按当前视图态分派，避免把搜索/归档视图静默重置为「全部」。
  ///
  /// [refresh] 拉的是普通列表，直接调会在搜索态/归档态下把视图态冲掉
  /// （`refreshIfStale` 有同样的两道守卫，此前只有这条下拉路径漏了）：
  /// - 搜索态 → 重跑当前搜索；
  /// - 归档态 → 重拉归档列表；
  /// - 其余 → 常规刷新（`refresh` 内部已回填视图态）。
  Future<void> _onRefresh() async {
    final controller = ref.read(sessionListControllerProvider.notifier);
    final state = ref.read(sessionListControllerProvider).valueOrNull;
    final query = state?.searchQuery?.trim();
    if (query != null && query.isNotEmpty) {
      await controller.search(query);
      return;
    }
    if (state?.filterMode == SessionListFilterMode.archived) {
      await controller.fetchArchived();
      return;
    }
    await controller.refresh();
  }

  void _onScroll() {
    _maybeLoadMore();
  }

  void _maybeLoadMore() {
    final controller = ref.read(sessionListControllerProvider.notifier);
    final state = ref.read(sessionListControllerProvider).valueOrNull;
    if (state == null || !state.hasMore) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.extentAfter < 200 || position.maxScrollExtent == 0) {
      unawaited(controller.loadMore());
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(ref.read(sessionListControllerProvider.notifier).search(value));
    });
  }

  Future<void> _onNewSession(BuildContext context, {String? workspace}) async {
    final controller = ref.read(sessionListControllerProvider.notifier);
    final id = await controller.createSession(workspace: workspace);
    if (!context.mounted) return;
    if (id != null) {
      ref.read(recentlyCreatedSessionIdProvider.notifier).markCreated(id);
      _openChatRoute(context, id);
    }
  }

  Offset? _getFabCenter() {
    final renderBox = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final pos = renderBox.localToGlobal(Offset.zero);
    return pos + Offset(renderBox.size.width / 2, renderBox.size.height / 2);
  }

  Future<void> _openFabWorkspaceMenu() async {
    if (!mounted) return;
    final state = ref.read(sessionListControllerProvider).valueOrNull;
    if (state?.isSelectionMode == true) return;

    List<WorkspaceRoot> available = const [];
    try {
      final api = ref.read(sessionListApiFactoryProvider)(
        ref.read(apiClientProvider),
      );
      available = await api.fetchWorkspaces();
    } catch (_) {
      available = const [];
    }

    if (!mounted) return;
    final sessions = state?.sessions ?? const [];
    // 取消数量限制：全部工作区参与排序，扇出时逐层向外堆叠。
    final ranked = rankWorkspaces(registered: available, sessions: sessions);

    // 空态：GET /api/workspaces 空/失败 → 不弹菜单，松开直接走原 createSession()
    if (ranked.isEmpty) {
      _fabRankedWorkspaces = const [];
      _fabMenuOpen = false;
      return;
    }

    _fabRankedWorkspaces = ranked;
    _fabMenuOpen = true;
    _hoveredWorkspaceIndex = null;

    unawaited(HapticFeedback.mediumImpact());
    _showFabWorkspaceOverlay();
  }

  void _showFabWorkspaceOverlay() {
    _hideFabWorkspaceOverlay();
    final overlayState = Overlay.of(context, rootOverlay: true);
    _fabWorkspaceOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final fabCenter = _getFabCenter() ?? Offset.zero;
        final brightness =
            CupertinoTheme.of(context).brightness ?? Brightness.light;
        return Positioned.fill(
          child: IgnorePointer(
            child: _FabWorkspaceArcMenu(
              key: const ValueKey('fab-workspace-menu'),
              workspaces: _fabRankedWorkspaces,
              hoveredIndex: _hoveredWorkspaceIndex,
              fabCenter: fabCenter,
              brightness: brightness,
              screenSize: MediaQuery.sizeOf(context),
            ),
          ),
        );
      },
    );
    overlayState.insert(_fabWorkspaceOverlayEntry!);
  }

  void _hideFabWorkspaceOverlay() {
    _fabWorkspaceOverlayEntry?.remove();
    _fabWorkspaceOverlayEntry = null;
  }

  void _onFabPointerDown(PointerDownEvent event, SessionListState? state) {
    if (state?.isSelectionMode == true) return;
    _hoveredWorkspaceIndex = null;
    _fabMenuOpen = false;
    _suppressNextTap = false;
    _fabLongPressTimer?.cancel();
    _fabLongPressTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_openFabWorkspaceMenu());
    });
  }

  void _onFabPointerMove(PointerMoveEvent event) {
    if (!_fabMenuOpen || _fabWorkspaceOverlayEntry == null) return;
    final fabCenter = _getFabCenter();
    if (fabCenter == null) return;

    final newHovered = _hitTestWorkspace(
      pointerPos: event.position,
      fabCenter: fabCenter,
      workspaces: _fabRankedWorkspaces,
      screenSize: MediaQuery.sizeOf(context),
    );

    if (newHovered != _hoveredWorkspaceIndex) {
      _hoveredWorkspaceIndex = newHovered;
      if (newHovered != null) {
        unawaited(HapticFeedback.selectionClick());
      }
      _fabWorkspaceOverlayEntry?.markNeedsBuild();
    }
  }

  void _onFabPointerUp(PointerUpEvent event) {
    _fabLongPressTimer?.cancel();
    _fabLongPressTimer = null;

    if (_fabMenuOpen) {
      _suppressNextTap = true;
      final selected = _hoveredWorkspaceIndex;
      final workspaces = _fabRankedWorkspaces;
      _hideFabWorkspaceOverlay();
      _fabMenuOpen = false;

      if (selected != null && selected >= 0 && selected < workspaces.length) {
        final target = workspaces[selected];
        unawaited(HapticFeedback.lightImpact());
        unawaited(_onNewSession(context, workspace: target.path));
      } else {
        unawaited(HapticFeedback.heavyImpact());
      }
    }
  }

  void _onFabPointerCancel(PointerCancelEvent event) {
    _fabLongPressTimer?.cancel();
    _fabLongPressTimer = null;
    if (_fabMenuOpen) {
      _hideFabWorkspaceOverlay();
      _fabMenuOpen = false;
    }
  }

  int? _hitTestWorkspace({
    required Offset pointerPos,
    required Offset fabCenter,
    required List<WorkspaceRoot> workspaces,
    Size? screenSize,
  }) {
    final n = workspaces.length;
    if (n == 0) return null;

    final d = (pointerPos - fabCenter).distance;
    if (d < 36.0) return null;

    // 多层同心弧布局：命中判定直接取离触点最近的一项，
    // 不再受旧版 36~195px 单环带限制（外圈项同样可命中）。
    final geoms = computeFabWorkspaceLayout(
      total: n,
      fabCenter: fabCenter,
      screenSize: screenSize,
    );

    int? bestIndex;
    double minDistance = double.infinity;

    for (var i = 0; i < n; i++) {
      final dist = (pointerPos - geoms[i].center).distance;
      if (dist < minDistance) {
        minDistance = dist;
        bestIndex = i;
      }
    }

    if (minDistance <= 48.0) {
      return bestIndex;
    }
    return null;
  }

  void _openSession(BuildContext context, SessionSummary session) {
    _openChatRoute(context, session.sessionId ?? session.id);
  }

  /// 进入聊天路由（todo：#43 返回动画修正——窄屏 push / 宽屏 go）。
  ///
  /// - 窄屏（< kAdaptiveBreakpoint）：`context.push` 真入栈，返回时
  ///   `AppBackButton` 走 `pop()` 反向（聊天页向右滑出、会话列表不动）。
  /// - 宽屏（>= kAdaptiveBreakpoint）：双栏外壳 `go` 替换不破坏侧栏选中态。
  void _openChatRoute(BuildContext context, String sessionId) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (isWide) {
      context.go('/chat/$sessionId');
    } else {
      unawaited(context.push('/chat/$sessionId'));
    }
  }

  void _showRowActions(
    BuildContext context,
    SessionSummary session,
    GlobalKey anchorKey,
  ) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(sessionListControllerProvider.notifier);
    final items = [
      AdaptiveMenuItem(
        key: const ValueKey('session-action-pin'),
        label: session.pinned == true ? l10n.unpin : l10n.pin,
        onPressed: () => unawaited(
          controller.setPinned(session, !(session.pinned ?? false)),
        ),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-archive'),
        label: l10n.archive,
        onPressed: () => unawaited(controller.setArchived(session, true)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-branch'),
        label: l10n.branch,
        onPressed: () => unawaited(_onBranch(context, controller, session)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-export'),
        label: l10n.export,
        onPressed: () => unawaited(_showExportFormat(context, session)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-move-project'),
        label: l10n.moveToProject,
        onPressed: () => unawaited(_moveToProject(context, session)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-workspace'),
        label: l10n.workspace,
        onPressed: () {
          if (context.mounted) {
            // 蓝本对应 SF Symbol: folder (CupertinoIcons.folder)
            // push 保留 Navigator 栈，返回时保留滚动/搜索状态
            unawaited(context.push('/workspace/${session.id}'));
          }
        },
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-git'),
        label: l10n.git,
        onPressed: () {
          if (context.mounted) {
            // 蓝本对应 SF Symbol: arrow.triangle.branch (CupertinoIcons.arrow_branch)
            // push 保留 Navigator 栈，返回时保留滚动/搜索状态
            unawaited(context.push('/git/${session.id}'));
          }
        },
      ),
      if (session.archived == true)
        AdaptiveMenuItem(
          key: const ValueKey('session-action-unarchive'),
          label: l10n.unarchive,
          onPressed: () => unawaited(controller.setArchived(session, false)),
        ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-delete'),
        isDestructive: true,
        label: l10n.delete,
        onPressed: () => unawaited(_confirmDelete(context, session)),
      ),
    ];

    unawaited(
      AdaptiveActionMenu.show(
        context,
        anchorKey: anchorKey,
        items: items,
        title: null,
        cancelLabel: l10n.cancel,
        cancelKey: const ValueKey('session-action-cancel'),
        preferredWidth: 220,
        minWidth: 180,
      ),
    );
  }

  Future<void> _showExportFormat(
    BuildContext context,
    SessionSummary session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final format = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l10n.exportSession),
        actions: [
          CupertinoActionSheetAction(
            key: const ValueKey('session-export-markdown'),
            onPressed: () => Navigator.pop(sheetContext, 'markdown'),
            child: Text(l10n.markdownFormat),
          ),
          CupertinoActionSheetAction(
            key: const ValueKey('session-export-json'),
            onPressed: () => Navigator.pop(sheetContext, 'json'),
            child: Text(l10n.jsonFormat),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(l10n.cancel),
        ),
      ),
    );
    if (format == null || !context.mounted) return;

    final sessionId = session.sessionId ?? session.id;
    try {
      final response = await ref
          .read(apiClientProvider)
          .exportSession(
            sessionId: sessionId,
            format: format == 'markdown' ? 'md' : 'json',
          );
      if (!context.mounted) return;
      final content = utf8.decode(response.data, allowMalformed: true);
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(l10n.exportSuccess(format)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Text(content.isEmpty ? l10n.exportContentEmpty : content),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                // 同源修复：导出内容无界，超限/剪贴板异常走 SafeClipboard
                // 落盘文件；提示弹窗沿用 diagnosticsExportTooLargeSaved。
                final result = await SafeClipboard.copyOrSave(
                  content,
                  fileNamePrefix: 'hermes_session_export',
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (result.isFileSaved && context.mounted) {
                  await showCupertinoDialog<void>(
                    context: context,
                    builder: (alertContext) => CupertinoAlertDialog(
                      title: Text(l10n.exportSuccessDialogTitle),
                      content: Text(
                        l10n.diagnosticsExportTooLargeSaved(result.filePath!),
                      ),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(alertContext),
                          child: Text(l10n.ok),
                        ),
                      ],
                    ),
                  );
                }
              },
              child: Text(l10n.copyContent),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(l10n.exportFailed),
          content: Text(
            error is ApiException ? error.message : '$error',
            style: TextStyle(color: statusRedText.resolveFrom(context)),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _onBranch(
    BuildContext context,
    SessionListController controller,
    SessionSummary session,
  ) async {
    final newId = await controller.branch(session);
    if (newId != null && context.mounted) {
      _openChatRoute(context, newId);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SessionSummary session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.deleteSession),
        content: Text(
          l10n.confirmDeleteSession(_displayTitle(context, session)),
        ),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('session-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('session-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(sessionListControllerProvider.notifier).delete(session);
    }
  }

  Future<void> _confirmBatchArchive(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        key: const ValueKey('batch-archive-dialog'),
        title: Text(l10n.batchArchiveTitle),
        content: Text(l10n.confirmBatchArchivePrompt),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('batch-archive-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('batch-archive-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.archive),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(sessionListControllerProvider.notifier)
          .batchArchive(archived: true);
    }
  }

  Future<void> _confirmBatchDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final count =
        ref
            .read(sessionListControllerProvider)
            .valueOrNull
            ?.selectedSessionIds
            .length ??
        0;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        key: const ValueKey('batch-delete-dialog'),
        title: Text(l10n.batchDeleteTitle),
        content: Text(l10n.confirmBatchDeletePrompt(count)),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('batch-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('batch-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(sessionListControllerProvider.notifier).batchDelete();
    }
  }

  Future<void> _batchMoveToProject(BuildContext context) async {
    final projectId = await showProjectPicker(context);
    if (projectId == null || !context.mounted) return;
    await ref
        .read(sessionListControllerProvider.notifier)
        .batchMove(projectId.isEmpty ? null : projectId);
  }

  Future<void> _moveToProject(
    BuildContext context,
    SessionSummary session,
  ) async {
    final projectId = await showProjectPicker(context);
    if (projectId == null || !context.mounted) return;
    await ref
        .read(sessionListControllerProvider.notifier)
        .moveToProject(session, projectId.isEmpty ? null : projectId);
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.actionFailed),
        content: Text(
          message,
          style: TextStyle(color: statusRedText.resolveFrom(context)),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    await ref.read(sessionListControllerProvider.notifier).clearActionError();
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

String _sectionTitle(BuildContext context, String rawTitle) {
  final l10n = AppLocalizations.of(context);
  switch (rawTitle) {
    // 注：不存在 '定时' 分区 —— 分区构造只产出 置顶/今天/昨天/更早
    //（见 session_list_providers.dart 的 sections 构造），原先的 '定时' case
    // 永不命中，已移除；l10n.scheduledSection 保留备用。
    case '置顶':
      return l10n.pinnedSection;
    case '今天':
      return l10n.todaySection;
    case '昨天':
      return l10n.yesterdaySection;
    case '更早':
      return l10n.earlierSection;
    case '搜索结果':
      return l10n.searchResultsSection;
    default:
      return rawTitle;
  }
}

/// 单行会话（自绘行而非 CupertinoListTile，便于独立 ellipsis 按钮命中测试）。
class _SessionRow extends StatefulWidget {
  const _SessionRow({
    super.key,
    required this.session,
    required this.onTap,
    required this.subtitleSettings,
    required this.projectNames,
    this.onLongPress,
    this.onActions,
    this.selectionMode = false,
    this.selected = false,
    this.highlightQuery,
  });

  final SessionSummary session;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 副标题显示项开关（设置页配置）。
  final SessionRowSubtitleSettings subtitleSettings;

  /// projectId → 项目名称 映射（副标题「项目名」显示项）。
  final Map<String, String> projectNames;

  /// 行尾操作按钮回调；null = 隐藏（多选模式下）。
  final void Function(GlobalKey anchorKey)? onActions;

  /// 多选模式：显示勾选圈，点击切换勾选。
  final bool selectionMode;
  final bool selected;

  /// 搜索关键词：非空时标题与摘录中的命中片段高亮。
  final String? highlightQuery;

  @override
  State<_SessionRow> createState() => _SessionRowState();

  /// 按副标题显示开关组装元数据行（消息数 / 项目名 / 工作区 / 渠道 /
  /// 预估价钱 + 搜索命中预览），渠道与预估价钱默认关闭。
  static String? _metadataLabel(
    BuildContext context,
    SessionSummary session, {
    required SessionRowSubtitleSettings settings,
    required Map<String, String> projectNames,
  }) {
    final l10n = AppLocalizations.of(context);
    final projectName = session.projectId == null
        ? null
        : _nonEmpty(projectNames[session.projectId]);
    final parts = <String>[
      if (settings.messageCount &&
          session.messageCount != null &&
          session.messageCount! >= 0)
        l10n.messageCountLabel(session.messageCount!),
      if (settings.projectName && projectName != null) projectName,
      if (settings.workspace && _nonEmpty(session.workspace) != null)
        _lastPathComponent(_nonEmpty(session.workspace)!),
      if (settings.channel && _nonEmpty(session.sourceLabel) != null)
        '· ${_nonEmpty(session.sourceLabel)}',
      if (settings.estimatedCost && session.estimatedCost != null)
        '· \$${session.estimatedCost!.toStringAsFixed(2)}',
      if (_nonEmpty(session.matchPreview) != null)
        _nonEmpty(session.matchPreview)!,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  static bool _isStreaming(SessionSummary session) =>
      session.isStreaming == true || _nonEmpty(session.activeStreamId) != null;

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String _lastPathComponent(String workspace) {
    final parts = workspace.replaceAll(r'\', '/').split('/');
    return parts.lastWhere((p) => p.isNotEmpty, orElse: () => workspace);
  }
}

class _SessionRowState extends State<_SessionRow> {
  final GlobalKey _actionKey = GlobalKey();
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final metadata = _SessionRow._metadataLabel(
      context,
      widget.session,
      settings: widget.subtitleSettings,
      projectNames: widget.projectNames,
    );
    final isStreaming = _SessionRow._isStreaming(widget.session);
    final secondaryColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );
    final pinned = widget.session.pinned == true;
    final isBranched = widget.session.parentSessionId != null;
    final readOnly =
        widget.session.readOnly == true || widget.session.isReadOnly == true;
    final iconWidgets = <Widget>[
      if (pinned)
        Icon(CupertinoIcons.pin_fill, size: 10, color: secondaryColor),
      if (isBranched)
        Icon(
          CupertinoIcons.arrow_2_squarepath,
          size: 12,
          color: secondaryColor,
        ),
      if (readOnly)
        Icon(CupertinoIcons.lock_fill, size: 10, color: secondaryColor),
    ];
    final hasIcons = iconWidgets.isNotEmpty;

    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (widget.selectionMode) ...[
            Icon(
              widget.selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 22,
              color: widget.selected
                  ? LightSurfaces.resolve(
                      context,
                      CupertinoColors.activeBlue.resolveFrom(context),
                      // Legacy Icon painted the unresolved blue in dark mode.
                      dark: const Color(0xFF007AFF),
                    )
                  : LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: CupertinoColors.secondaryLabel,
                    ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: _highlightedSpan(
                        context,
                        _displayTitle(context, widget.session),
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                  ],
                ),
                if (metadata != null || hasIcons) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (metadata != null)
                        Flexible(
                          child: _highlightedSpan(
                            context,
                            metadata,
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryColor,
                            ),
                          ),
                        ),
                      if (hasIcons) ...[
                        if (metadata != null) const SizedBox(width: 6),
                        for (var i = 0; i < iconWidgets.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          iconWidgets[i],
                        ],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (widget.onActions != null)
            KeyedSubtree(
              key: _actionKey,
              child: AccessibleButton(
                key: ValueKey(
                  'session-actions-${widget.session.sessionId ?? widget.session.id}',
                ),
                label: isStreaming
                    ? '${l10n.sessionActions} — Active'
                    : l10n.sessionActions,
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed: () => widget.onActions!(_actionKey),
                child: isStreaming
                    ? Semantics(
                        label: 'Active',
                        excludeSemantics: true,
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CupertinoActivityIndicator(
                            radius: 9,
                            color: CupertinoColors.activeBlue.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                      )
                    : Icon(
                        CupertinoIcons.ellipsis,
                        size: 20,
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          // Preserve the previously unresolved dark icon paint value,
                          // including in high contrast mode.
                          dark: const Color(0xFF8E8E93),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: isLight ? (_) => _setPressed(true) : null,
      onTapUp: isLight ? (_) => _setPressed(false) : null,
      onTapCancel: isLight ? () => _setPressed(false) : null,
      child: isLight
          ? DecoratedBox(
              decoration: ShapeDecoration(
                color: widget.selected
                    ? LightSurfaces.selection
                    : (_pressed ? LightSurfaces.pressed : null),
                shape: const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              child: rowContent,
            )
          : rowContent,
    );
  }

  /// 构造标题/摘要文本：搜索模式下把 [query] 命中片段染成高亮。
  Widget _highlightedSpan(
    BuildContext context,
    String text, {
    TextStyle? style,
  }) {
    final query = widget.highlightQuery;
    if (query == null ||
        query.isEmpty ||
        !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    var index = 0;
    while (true) {
      final hit = lower.indexOf(q, index);
      if (hit < 0) {
        spans.add(TextSpan(text: text.substring(index)));
        break;
      }
      if (hit > index) {
        spans.add(TextSpan(text: text.substring(index, hit)));
      }
      spans.add(
        TextSpan(
          text: text.substring(hit, hit + query.length),
          style: TextStyle(
            color: LightSurfaces.resolve(
              context,
              statusBlueText.resolveFrom(context),
              dark: CupertinoColors.activeBlue,
            ),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      index = hit + query.length;
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String _displayTitle(BuildContext context, SessionSummary session) {
  final title = session.title?.trim();
  if (title == null || title.isEmpty) {
    return AppLocalizations.of(context).untitledSession;
  }
  return title;
}

/// 由 [projectsProvider] 构建 projectId → 名称 映射（会话行副标题「项目名」
/// 项使用；一次构建供整屏复用以避免逐行 map）。
Map<String, String> _projectNameMap(WidgetRef ref) {
  final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
  return {
    for (final project in projects)
      if (project.projectId != null) project.projectId!: project.name ?? '',
  };
}

/// 筛选底部弹层：显示设置 / 会话 / 渠道 / 项目 四段等宽 insetGrouped 列表。
///
/// 视觉对齐标准 iOS 底部弹层（#27 症状 B）：遮罩/动画走
/// [showCupertinoModalPopup] 默认（`_showFilterSheet` 打开），顶部圆角 16
/// 对齐系统 sheet；四段 uniform [CupertinoListSection.insetGrouped]、
/// 卡片圆角 14pt 配 1px 分割线边框（对齐 adaptive_popover:383）；
/// 分割线全宽（#28，divider 起点置 0）；
/// 「全部/已归档」采用左侧 checkbox 单选（[_SheetCheckboxRow]），渠道与项目采用右侧 checkmark 单选。
class _SessionFilterSheet extends ConsumerWidget {
  const _SessionFilterSheet({required this.state, required this.onSelect});

  final SessionListState state;

  /// 选择回调（调用方负责 setFilter 并关闭弹层）。
  final void Function(SessionListFilterMode mode, String? value) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 弹层打开期间开关/筛选即时生效：实时取控制器状态（而非开局快照），
    // 「显示 subagent 会话」开关与渠道列表随切换联动。
    final current =
        ref.watch(sessionListControllerProvider).valueOrNull ?? state;
    final mode = current.filterMode;
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
    final sheetBg = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: CupertinoColors.systemGroupedBackground,
    );
    final screenHeight = MediaQuery.sizeOf(context).height;
    // 顶部圆角对齐系统 sheet（16pt），内容随圆角裁切干净；
    // 宽屏居中盒与窄屏全宽两条路径均在 ConstrainedBox 内部裁切，确保不掉角。
    const sheetRadius = BorderRadius.vertical(top: Radius.circular(16));
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.textSecondary,
        dark: secondaryText,
      ),
      letterSpacing: 0.3,
    );
    // 卡片装饰：14pt 圆角对齐 adaptive_popover:383，补 1px separator 边框清晰区分层次。
    final cardDecoration = BoxDecoration(
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.card,
        dark: CupertinoColors.secondarySystemGroupedBackground,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.cardBorder,
          dark: CupertinoColors.separator,
        ),
        width: 1.0,
      ),
    );

    return SafeArea(
      top: false,
      // 宽屏（桌面双栏）下收窄为居中的 iOS 风格底部弹层，保持纵向可读。
      // Align 负责居中但不扩容背景盒：DecoratedBox 尺寸跟随内容（min）。
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            // 内容超高时滚动而非撑破全屏（约 15% 顶部留白，对齐 iOS 底部弹层）。
            maxHeight: screenHeight * 0.85,
          ),
          child: ClipRRect(
            borderRadius: sheetRadius,
            child: DecoratedBox(
              key: const ValueKey('session-filter-sheet'),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: sheetRadius,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.filterSessions,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AccessibleButton(
                          key: const ValueKey('session-filter-sheet-close'),
                          label: l10n.close,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(36, 36),
                          onPressed: () => Navigator.pop(context),
                          child: Icon(
                            CupertinoIcons.xmark_circle_fill,
                            size: 22,
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.textSecondary,
                              dark: CupertinoColors.secondaryLabel,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CupertinoListSection.insetGrouped(
                            key: const ValueKey('filter-section-display'),
                            hasLeading: false,
                            header: Text(
                              l10n.displaySectionHeader,
                              style: headerStyle,
                            ),
                            backgroundColor: CupertinoColors.transparent,
                            separatorColor: LightSurfaces.resolve(
                              context,
                              LightSurfaces.divider,
                              dark: CupertinoColors.separator,
                            ),
                            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            // #28 分割线全宽：divider 起点 = dividerMargin +
                            // additionalDividerMargin，置 0 使分割线从容器左缘起笔。
                            dividerMargin: 0,
                            additionalDividerMargin: 0,
                            decoration: cardDecoration,
                            children: [
                              CupertinoListTile(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                title: Text(
                                  l10n.showSubagentSessions,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15),
                                ),
                                trailing: SettingsSurfaces.toggle(
                                  context,
                                  CupertinoSwitch(
                                    key: const ValueKey(
                                      'session-filter-subagent-switch',
                                    ),
                                    value: current.showSubagent,
                                    onChanged: (value) => unawaited(
                                      ref
                                          .read(
                                            sessionListControllerProvider
                                                .notifier,
                                          )
                                          .setShowSubagent(value),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          CupertinoListSection.insetGrouped(
                            key: const ValueKey('filter-section-sessions'),
                            hasLeading: true,
                            header: Text(l10n.sessions, style: headerStyle),
                            backgroundColor: CupertinoColors.transparent,
                            separatorColor: LightSurfaces.resolve(
                              context,
                              LightSurfaces.divider,
                              dark: CupertinoColors.separator,
                            ),
                            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            // #28 分割线全宽
                            dividerMargin: 0,
                            additionalDividerMargin: 0,
                            decoration: cardDecoration,
                            children: [
                              _SheetCheckboxRow(
                                key: const ValueKey('sheet-filter-all'),
                                label: l10n.all,
                                selected: mode == SessionListFilterMode.all,
                                onTap: () =>
                                    onSelect(SessionListFilterMode.all, null),
                              ),
                              _SheetCheckboxRow(
                                key: const ValueKey('sheet-filter-archived'),
                                label:
                                    '${l10n.archived}${_archivedCountLabelFor(current)}',
                                selected:
                                    mode == SessionListFilterMode.archived,
                                onTap: () => onSelect(
                                  SessionListFilterMode.archived,
                                  null,
                                ),
                              ),
                              if (mode != SessionListFilterMode.all &&
                                  mode != SessionListFilterMode.archived)
                                _SheetOptionRow(
                                  key: const ValueKey('sheet-filter-clear'),
                                  label: l10n.clearFilter,
                                  selected: false,
                                  onTap: () =>
                                      onSelect(SessionListFilterMode.all, null),
                                ),
                            ],
                          ),
                          if (current.sourceLabels.isNotEmpty)
                            CupertinoListSection.insetGrouped(
                              key: const ValueKey('filter-section-channels'),
                              hasLeading: false,
                              header: Text(l10n.channels, style: headerStyle),
                              backgroundColor: CupertinoColors.transparent,
                              separatorColor: LightSurfaces.resolve(
                                context,
                                LightSurfaces.divider,
                                dark: CupertinoColors.separator,
                              ),
                              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              // #28 分割线全宽
                              dividerMargin: 0,
                              additionalDividerMargin: 0,
                              decoration: cardDecoration,
                              children: [
                                for (final label in current.sourceLabels)
                                  _SheetOptionRow(
                                    key: ValueKey('filter-chip-$label'),
                                    label: label,
                                    selected:
                                        mode == SessionListFilterMode.source &&
                                        current.filterValue == label,
                                    onTap: () => onSelect(
                                      SessionListFilterMode.source,
                                      label,
                                    ),
                                  ),
                              ],
                            ),
                          if (projects.isNotEmpty)
                            CupertinoListSection.insetGrouped(
                              key: const ValueKey('filter-section-projects'),
                              hasLeading: false,
                              header: Text(l10n.projects, style: headerStyle),
                              backgroundColor: CupertinoColors.transparent,
                              separatorColor: LightSurfaces.resolve(
                                context,
                                LightSurfaces.divider,
                                dark: CupertinoColors.separator,
                              ),
                              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              // #28 分割线全宽
                              dividerMargin: 0,
                              additionalDividerMargin: 0,
                              decoration: cardDecoration,
                              children: [
                                for (final project in projects)
                                  _SheetOptionRow(
                                    key: ValueKey('project-chip-${project.id}'),
                                    label: project.name ?? l10n.untitledProject,
                                    selected:
                                        mode == SessionListFilterMode.project &&
                                        current.filterValue == project.id,
                                    onTap: () => onSelect(
                                      SessionListFilterMode.project,
                                      project.id,
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _archivedCountLabelFor(SessionListState state) {
    final count = state.archivedCount ?? state.archivedSessions.length;
    return count > 0 ? ' ($count)' : '';
  }
}

/// 筛选弹层中的单选行（渠道 / 项目 及清除动作共用）。
///
/// 选中态：右侧系统 checkmark（`CupertinoIcons.check_mark`，对齐
/// CupertinoActionSheet/系统列表视觉），行背景与文字样式不变；去自绘
/// activeBlue 浅底 pill 与加粗。未选中：常规 label 文字。
class _SheetOptionRow extends StatelessWidget {
  const _SheetOptionRow({
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
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      backgroundColor: LightSurfaces.resolve(
        context,
        selected ? LightSurfaces.selection : LightSurfaces.card,
        dark: CupertinoColors.secondarySystemGroupedBackground,
      ),
      backgroundColorActivated:
          CupertinoTheme.brightnessOf(context) == Brightness.light
          ? LightSurfaces.pressed
          : null,
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
      trailing: selected
          ? Icon(
              CupertinoIcons.check_mark,
              size: 18,
              color: CupertinoColors.activeBlue.resolveFrom(context),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// 筛选弹层中的 checkbox 样式单选行（「全部」「已归档」专用）。
///
/// 视觉：左侧方框图标（选中为 `CupertinoIcons.checkmark_square_fill` + activeBlue，
/// 未选中为 `CupertinoIcons.checkmark_square` + secondaryLabel），右侧无 checkmark。
/// 语义：单选互斥（filterMode 单值）。
class _SheetCheckboxRow extends StatelessWidget {
  const _SheetCheckboxRow({
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
    final activeColor = CupertinoColors.activeBlue.resolveFrom(context);
    final inactiveColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      backgroundColor: LightSurfaces.resolve(
        context,
        selected ? LightSurfaces.selection : LightSurfaces.card,
        dark: CupertinoColors.secondarySystemGroupedBackground,
      ),
      backgroundColorActivated:
          CupertinoTheme.brightnessOf(context) == Brightness.light
          ? LightSurfaces.pressed
          : null,
      leading: Icon(
        selected
            ? CupertinoIcons.checkmark_square_fill
            : CupertinoIcons.checkmark_square,
        size: 20,
        color: selected ? activeColor : inactiveColor,
      ),
      leadingSize: 20,
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// FAB 悬浮加号长按工作区项几何位置。
@visibleForTesting
class FabWorkspaceItemGeometry {
  const FabWorkspaceItemGeometry({
    required this.center,
    required this.angleDeg,
    required this.radius,
    this.ringIndex = 0,
  });

  final Offset center;
  final double angleDeg;
  final double radius;

  /// 所在同心弧环编号（0 = 最内圈），用于交替标签方向、防跨层遮挡。
  final int ringIndex;
}

/// 工作区多层同心弧扇出布局常量。
///
/// - 图标气泡半径 22px；同圈相邻项中心距（弦距）≥ [kFabWorkspaceMinGap]，
///   该值同时保证 70px 宽的微胶囊标签在同圈互不触碰；
/// - 圈间距 [kFabWorkspaceRingGap]（78px）> 标签最大外延（41px）+ 图标半径，
///   跨圈项与其标签天然不重叠；
/// - 最外圈半径受屏幕左上可用空间（边距 [kFabWorkspaceEdgeMargin]）与
///   全局上限 [kFabWorkspaceMaxRadius] 约束，实现「一层一层向外堆叠到满屏」。
@visibleForTesting
const double kFabWorkspaceIconRadius = 22.0;
@visibleForTesting
const double kFabWorkspaceMinGap = 76.0;
@visibleForTesting
const double kFabWorkspaceRingGap = 78.0;
@visibleForTesting
const double kFabWorkspaceFirstRadius = 132.0;
@visibleForTesting
const double kFabWorkspaceEdgeMargin = 40.0;
@visibleForTesting
const double kFabWorkspaceMaxRadius = 560.0;
@visibleForTesting
const double kFabWorkspaceArcStart = -178.0;
@visibleForTesting
const double kFabWorkspaceArcEnd = -92.0;

/// 计算指定工作区项在 FAB 多层扇出中的中心坐标与几何属性。
@visibleForTesting
FabWorkspaceItemGeometry getFabWorkspaceItemGeometry(
  int index,
  int total,
  Offset fabCenter,
) {
  return computeFabWorkspaceLayout(total: total, fabCenter: fabCenter)[index];
}

/// 计算全部工作区项在多层同心弧扇出中的排布（数量不设上限）。
///
/// 排布规则：
/// 1. 以 FAB 为圆心，从内向外生成同心弧环 R_k = 132 + k*78，
///    直到无可用角度或超出屏幕左上可行区；
/// 2. 每圈的可用角度窗口受屏幕左边缘/上边缘（图标安全边距
///    [kFabWorkspaceEdgeMargin]）约束：越往外的圈在 45° 斜向仍有空间，
///    窗口只收缩被边缘吃掉的端点，实现「一层一层向外堆叠到满屏」；
/// 3. 每圈容量由「相邻弦距 ≥ 76px（含微胶囊标签不触碰）」反推最小角步进
///    得出，项先填满内圈、再逐层向外堆叠；
/// 4. 圈内项在可用弧段上均匀分布（单项时取弧中点）；
/// 5. 极端超量（超过整屏总容量）时，多出的项从最外圈起轮流均摊压缩，
///    仍保持全部项落在屏幕内。
///
/// [screenSize] 为空时退化为旧版各向同性约束（最外圈 ≤ min(fabX, fabY) -
/// 40 与 [kFabWorkspaceMaxRadius] 的较小者），保证无屏幕信息时也不出屏。
@visibleForTesting
List<FabWorkspaceItemGeometry> computeFabWorkspaceLayout({
  required int total,
  required Offset fabCenter,
  Size? screenSize,
}) {
  if (total <= 0) return const [];

  final margin = kFabWorkspaceEdgeMargin;
  final maxRadius = screenSize == null
      ? max(
          min(min(fabCenter.dx, fabCenter.dy) - margin, kFabWorkspaceMaxRadius),
          kFabWorkspaceFirstRadius,
        )
      : // 理论最远：左上角对角线（可行窗口随半径自然收敛，无需显式上限）。
        sqrt(
          screenSize.width * screenSize.width +
              screenSize.height * screenSize.height,
        );

  final radii = <double>[];
  final windows = <List<double>>[]; // 每圈可行角度窗口 [start, end]
  for (
    var r = kFabWorkspaceFirstRadius;
    r <= maxRadius;
    r += kFabWorkspaceRingGap
  ) {
    final window = _feasibleAngleWindow(
      fabCenter,
      r,
      margin,
      topBounded: screenSize != null,
    );
    if (window == null) break; // 窗口随半径单调收窄，空即终止
    radii.add(r);
    windows.add(window);
  }
  if (radii.isEmpty) {
    radii.add(kFabWorkspaceFirstRadius);
    windows.add(const [kFabWorkspaceArcStart, kFabWorkspaceArcEnd]);
  }

  // 各圈容量：最小弦距反推角步进。
  final capacities = <int>[];
  for (var k = 0; k < radii.length; k++) {
    final r = radii[k];
    final minStepRad =
        2 * asin((kFabWorkspaceMinGap / (2 * r)).clamp(0.0, 1.0).toDouble());
    final minStepDeg = minStepRad * 180.0 / pi;
    final sweep = windows[k][1] - windows[k][0];
    capacities.add(max(1, (sweep / minStepDeg).floor() + 1));
  }

  // 逐项分配：先按容量顺序填满内圈→外圈，超量从最外圈起轮流均摊。
  final counts = List<int>.filled(radii.length, 0);
  var remaining = total;
  for (var i = 0; i < radii.length && remaining > 0; i++) {
    final take = min(capacities[i], remaining);
    counts[i] = take;
    remaining -= take;
  }
  var ring = radii.length - 1;
  while (remaining > 0) {
    counts[ring] += 1;
    remaining -= 1;
    ring = ring == 0 ? radii.length - 1 : ring - 1;
  }

  // 逐圈均匀布点。
  final items = <FabWorkspaceItemGeometry>[];
  for (var k = 0; k < radii.length; k++) {
    final r = radii[k];
    final n = counts[k];
    if (n == 0) continue;
    final a0 = windows[k][0];
    final a1 = windows[k][1];
    final sweep = a1 - a0;
    for (var j = 0; j < n; j++) {
      final angleDeg = n == 1 ? a0 + sweep / 2 : a0 + sweep * j / (n - 1);
      final rad = angleDeg * pi / 180.0;
      items.add(
        FabWorkspaceItemGeometry(
          center: fabCenter + Offset(r * cos(rad), r * sin(rad)),
          angleDeg: angleDeg,
          radius: r,
          ringIndex: k,
        ),
      );
    }
  }
  return items;
}

/// 圈层 [radius] 在弧段 [kFabWorkspaceArcStart, kFabWorkspaceArcEnd] 内、
/// 且不越过屏幕左边缘安全区（[margin]）的可行角度窗口；无解返回 null。
///
/// 角度 a ∈ [-180°, -90°] 时：cos 单调递增（x 从 fx-r 增至 fx），
/// sin 单调递减（y 从 fy 减至 fy-r），故两组不等式的解均为连续区间，
/// 反解临界角即可：
/// - 左边界 x ≥ margin ⇔ cos(a) ≥ (margin-fx)/r ⇔ a ≥ -deg(acos(c))；
///   （acos 主值 ∈ [90°,180°]，取负号即落入 [-180°,-90°]）
/// - 上边界 y ≥ margin ⇔ sin(a) ≥ (margin-fy)/r ⇔ a ≤ -180° - deg(asin(s))。
/// [topBounded] 为 false 时由调用方通过 maxRadius 保证上边界，这里只收左界。
List<double>? _feasibleAngleWindow(
  Offset fabCenter,
  double radius,
  double margin, {
  required bool topBounded,
}) {
  var start = kFabWorkspaceArcStart;
  var end = kFabWorkspaceArcEnd;
  final toDeg = 180.0 / pi;

  // 左边界
  final cosMin = (margin - fabCenter.dx) / radius;
  if (cosMin > 1) return null;
  if (cosMin > -1) {
    start = max(start, -acos(cosMin) * toDeg);
  }

  // 上边界
  if (topBounded) {
    final sinMin = (margin - fabCenter.dy) / radius;
    if (sinMin > 0) return null;
    if (sinMin > -1) {
      end = min(end, -180.0 - asin(sinMin) * toDeg);
    }
  }

  if (start >= end) return null;
  return [start, end];
}

/// FAB 悬浮加号长按滑选工作区多层同心弧菜单。
///
/// 视觉与交互：
/// - 向左上扇形区多层同心弧堆叠（R=132 起每层 +78px，随屏幕左上可用空间
///   自动扩圈，数量不设上限，逐层向外布满整屏扇区）；
/// - 毛玻璃/半透明圆底气泡 + 细边框与投影；
/// - 选中项放大高亮（Hermex 蓝底 + 浮动名称 badge）；未选中项显示圆底图标 + 独立微胶囊副标。
class _FabWorkspaceArcMenu extends StatelessWidget {
  const _FabWorkspaceArcMenu({
    super.key,
    required this.workspaces,
    required this.hoveredIndex,
    required this.fabCenter,
    required this.brightness,
    this.screenSize,
  });

  final List<WorkspaceRoot> workspaces;
  final int? hoveredIndex;
  final Offset fabCenter;
  final Brightness brightness;

  /// 屏幕尺寸（提供时外圈沿 45° 斜向扩到角部；null 退化为保守圆约束）。
  final Size? screenSize;

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final n = workspaces.length;
    // 一次算好整张布局，逐项复用（多项时避免 n 次全量重算）。
    final layout = computeFabWorkspaceLayout(
      total: n,
      fabCenter: fabCenter,
      screenSize: screenSize,
    );

    // 悬停项最后入 Stack：浮动 badge 不被外圈气泡遮挡（z 轴置顶）。
    final order = [
      for (var i = 0; i < n; i++)
        if (i != hoveredIndex) i,
      if (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < n)
        hoveredIndex!,
    ];

    return Stack(
      children: [for (final i in order) ..._buildItem(i, layout[i], isDark)],
    );
  }

  List<Widget> _buildItem(
    int index,
    FabWorkspaceItemGeometry geom,
    bool isDark,
  ) {
    final workspace = workspaces[index];
    final isHovered = hoveredIndex == index;
    final displayName = _workspaceDisplayName(workspace);

    final cx = geom.center.dx;
    final cy = geom.center.dy;

    return [
      // 气泡按钮（直径 44px）
      Positioned(
        left: cx - 22,
        top: cy - 22,
        width: 44,
        height: 44,
        child: AnimatedScale(
          scale: isHovered ? 1.18 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Container(
            key: ValueKey('fab-workspace-item-${workspace.path}'),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHovered
                  ? const Color(0xFF007AFF)
                  : (isDark ? const Color(0xCC2C2C2E) : LightSurfaces.card),
              border: Border.all(
                color: isHovered
                    ? CupertinoColors.white.withValues(alpha: 0.85)
                    : (isDark
                          ? const Color(0x33FFFFFF)
                          : LightSurfaces.cardBorder),
                width: isHovered ? 1.5 : 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: isHovered
                      ? const Color(0x55007AFF)
                      : const Color(0x1F000000),
                  blurRadius: isHovered ? 12 : 6,
                  spreadRadius: isHovered ? 1 : 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                isHovered ? CupertinoIcons.folder_fill : CupertinoIcons.folder,
                size: 21,
                color: isHovered
                    ? CupertinoColors.white
                    : (isDark ? CupertinoColors.white : CupertinoColors.black),
              ),
            ),
          ),
        ),
      ),
      // 选中时浮动完整标题 badge，未选中时展示小微胶囊副标
      if (isHovered)
        Positioned(
          left: cx - 55,
          top: cy - 46,
          width: 110,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                // Inverse tooltip surface, not a light card: white text stays
                // legible over both page and card (see the contrast audit).
                color: isDark
                    ? const Color(0xEE1C1C1E)
                    : const Color(0xF0000000),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x33FFFFFF), width: 0.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ),
        )
      else
        Positioned(
          left: cx - 35,
          top: cy + 24,
          width: 70,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x99000000) : LightSurfaces.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark
                      ? const Color(0x26FFFFFF)
                      : LightSurfaces.cardBorder,
                  width: 0.5,
                ),
              ),
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  static String _workspaceDisplayName(WorkspaceRoot workspace) {
    if (workspace.name != null && workspace.name!.trim().isNotEmpty) {
      return workspace.name!.trim();
    }
    final path = workspace.path;
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
