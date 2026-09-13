import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/kanban.dart';
import '../../core/utils/accessibility.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import 'kanban_providers.dart';
import '../../app/widgets/hermes_page_route.dart';

/// Kanban 状态展示标题（对齐 Hermex KanbanStatusPresentation.title）。
String kanbanStatusTitle(String? rawValue, [BuildContext? context]) {
  if (context != null) {
    final l10n = AppLocalizations.of(context);
    switch (rawValue) {
      case 'triage':
        return l10n.kanbanStatusTriage;
      case 'todo':
        return l10n.kanbanStatusTodo;
      case 'ready':
        return l10n.kanbanStatusReady;
      case 'running':
        return l10n.kanbanStatusRunning;
      case 'blocked':
        return l10n.kanbanStatusBlocked;
      case 'done':
        return l10n.kanbanStatusDone;
      case 'archived':
        return l10n.kanbanStatusArchived;
      case null:
      case '':
        return l10n.kanbanStatusUnknown;
      default:
        return l10n.kanbanStatusUnsupported(rawValue);
    }
  }
  switch (rawValue) {
    case 'triage':
      return '待分类';
    case 'todo':
      return '待办';
    case 'ready':
      return '就绪';
    case 'running':
      return '运行中';
    case 'blocked':
      return '受阻';
    case 'done':
      return '完成';
    case 'archived':
      return '已归档';
    case null:
    case '':
      return '未知状态';
    default:
      return '不支持: $rawValue';
  }
}

/// Kanban 状态标识颜色（对齐 Hermex KanbanStatusPresentation.color）。
///
/// 返回 [CupertinoDynamicColor]：圆点与文字共用，浅色/深色均满足 WCAG AA。
CupertinoDynamicColor kanbanStatusColor(String? rawValue) {
  switch (rawValue) {
    case 'triage':
      return statusGreyText;
    case 'todo':
      return statusBlueText;
    case 'ready':
      return _kanbanReadyColor;
    case 'running':
      return statusOrangeText;
    case 'blocked':
      return _kanbanBlockedColor;
    case 'done':
      return statusGreenText;
    case 'archived':
      return _kanbanArchivedColor;
    default:
      return _kanbanUnknownColor;
  }
}

// Reuse existing stronger light palette entries on page/card/pressed surfaces.
// Keep all four dark variants from the original status color unchanged.
final _kanbanReadyColor = _withLightStatusColor(
  statusTealText,
  statusTealText.highContrastColor,
);
final _kanbanBlockedColor = _withLightStatusColor(
  CupertinoColors.systemRed,
  statusRedText.color,
  highContrast: statusRedText.highContrastColor,
);
final _kanbanArchivedColor = _withLightStatusColor(
  secondaryText,
  LightSurfaces.textSecondary,
);
final _kanbanUnknownColor = _withLightStatusColor(
  CupertinoColors.systemPurple,
  CupertinoColors.systemPurple.highContrastColor,
);

CupertinoDynamicColor _withLightStatusColor(
  CupertinoDynamicColor original,
  Color light, {
  Color? highContrast,
}) {
  return CupertinoDynamicColor(
    color: light,
    darkColor: original.darkColor,
    highContrastColor: highContrast ?? light,
    darkHighContrastColor: original.darkHighContrastColor,
    elevatedColor: light,
    darkElevatedColor: original.darkElevatedColor,
    highContrastElevatedColor: highContrast ?? light,
    darkHighContrastElevatedColor: original.darkHighContrastElevatedColor,
  );
}

/// 看板页（`/kanban`）。
///
/// Cupertino 风格：大标题 + 新建卡片 + 看板切换条（横向 chips）+ 按状态分列
/// 的看板视图（每列：状态名 + 计数 + 卡片列表）+ 下拉刷新 + 加载 / 错误 /
/// 空态。卡片点击进入 [KanbanCardDetailPage]。
class KanbanPage extends ConsumerStatefulWidget {
  const KanbanPage({super.key});

  @override
  ConsumerState<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends ConsumerState<KanbanPage> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kanbanControllerProvider);
    final state = async.valueOrNull;

    ref.listen<AsyncValue<KanbanState>>(kanbanControllerProvider, (
      previous,
      next,
    ) {
      final error = next.valueOrNull?.actionError;
      if (error != null && error != previous?.valueOrNull?.actionError) {
        unawaited(_showActionError(context, error));
      }
    });

    final l10n = AppLocalizations.of(context);
    final page = CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('kanban-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.kanbanTitle,
            leading: const AppBackButton(),
            trailing: AccessibleButton(
              key: const ValueKey('kanban-create'),
              label: l10n.newCard,
              padding: EdgeInsets.zero,
              onPressed: state == null || state.readOnly
                  ? null
                  : () => _openCreate(context),
              child: const Icon(CupertinoIcons.add),
            ),
          ),
          // 刷新指示器必须排在所有 SliverToBoxAdapter 之前（对齐会话列表页）。
          CupertinoSliverRefreshControl(onRefresh: _onRefresh),
          ..._buildContentSlivers(async, state),
        ],
      ),
    );
    return _withKanbanLightTheme(context, page);
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 看板视图
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<KanbanState> async,
    KanbanState? state,
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

    if (state.boards.isEmpty) {
      return [_buildEmptySliver()];
    }

    // 看板切换条 + 看板视图（快照加载中显示指示器）。
    return [
      SliverToBoxAdapter(child: _buildBoardSwitcher(state)),
      if (state.snapshot == null)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CupertinoActivityIndicator(radius: 14)),
        )
      else
        SliverToBoxAdapter(child: _buildBoardView(state)),
    ];
  }

  Widget _buildBoardSwitcher(KanbanState state) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: state.boards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final board = state.boards[index];
          final slug = board.slug ?? '';
          final selected = slug == state.currentBoardSlug;
          final isLight = _usesLightSurfaces(context);
          return _KanbanPressFeedback(
            enabled: !selected,
            builder: (pressed) {
              final button = CupertinoButton(
                key: ValueKey('kanban-board-$slug'),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                borderRadius: BorderRadius.circular(14),
                pressedOpacity: isLight ? 1 : 0.4,
                // Native buttons reapply the original color alpha after
                // resolution, so dark must retain the unresolved dynamic value.
                color: isLight
                    ? (selected
                          ? LightSurfaces.selection
                          : (pressed
                                ? LightSurfaces.pressed
                                : LightSurfaces.card))
                    : (selected
                          ? CupertinoColors.activeBlue
                          : CupertinoColors.secondarySystemFill),
                disabledColor: isLight
                    ? LightSurfaces.selection
                    : CupertinoColors.quaternarySystemFill,
                onPressed: selected
                    ? null
                    : () => unawaited(_selectBoard(slug)),
                child: Text(
                  board.name ?? board.slug ?? l10n.unnamedBoard,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: isLight
                        ? (selected
                              ? statusBlueText.resolveFrom(context)
                              : CupertinoColors.label.resolveFrom(context))
                        : (selected
                              ? CupertinoColors.white
                              : CupertinoColors.label),
                  ),
                ),
              );
              if (!isLight) return button;
              return Semantics(
                selected: selected,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    // Decorative chip boundary; selection also has weight/semantics.
                    border: Border.all(
                      color: LightSurfaces.cardBorder,
                      width: 0.5,
                    ),
                  ),
                  child: button,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBoardView(KanbanState state) {
    final columns = state.columns;
    if (columns.isEmpty) {
      return _buildEmptyBoard();
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height - 200,
      child: ListView.separated(
        key: const ValueKey('kanban-columns'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: columns.length,
        separatorBuilder: (context, _) => _usesLightSurfaces(context)
            ? const SizedBox(
                width: 12,
                child: Center(
                  child: SizedBox(
                    width: 0.5,
                    height: double.infinity,
                    // Decorative column separator, not a status indicator.
                    child: ColoredBox(color: LightSurfaces.divider),
                  ),
                ),
              )
            : const SizedBox(width: 12),
        itemBuilder: (context, index) => _KanbanColumnView(
          column: columns[index],
          onCardDropped: (card) =>
              _moveCardLocally(state, card, columns[index].name ?? ''),
        ),
      ),
    );
  }

  void _moveCardLocally(
    KanbanState state,
    KanbanCard card,
    String targetStatus,
  ) {
    if (card.status?.rawValue == targetStatus || targetStatus.isEmpty) return;
    // 服务端当前只有 status PATCH；跨列拖拽对应状态变更，复用既有守卫与错误处理。
    unawaited(
      ref
          .read(kanbanControllerProvider.notifier)
          .setStatus(cardId: card.cardID ?? '', status: targetStatus),
    );
  }

  Widget _buildEmptyBoard() {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.rectangle_stack,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.kanbanEmptyContent, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              l10n.clickPlusToCreateFirstCard,
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
              CupertinoIcons.square_stack_3d_up,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.noKanbanBoards, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              l10n.createBoardOnServerPrompt,
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
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
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
              key: const ValueKey('kanban-retry'),
              onPressed: () => unawaited(_onRefresh()),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 交互：刷新 / 切换看板 / 新建卡片 / 错误弹窗
  // -------------------------------------------------------------------------

  Future<void> _onRefresh() =>
      ref.read(kanbanControllerProvider.notifier).refresh();

  Future<void> _selectBoard(String slug) async {
    await ref.read(kanbanControllerProvider.notifier).selectBoard(slug);
  }

  void _openCreate(BuildContext context) {
    Navigator.of(
      context,
    ).push(HermesPageRoute<void>(builder: (_) => const KanbanCreateCardPage()));
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.actionFailed),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            textStyle: _usesLightSurfaces(dialogContext)
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    await ref.read(kanbanControllerProvider.notifier).clearActionError();
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

/// 看板列：状态名 + 计数 + 卡片列表。
class _KanbanColumnView extends StatelessWidget {
  const _KanbanColumnView({required this.column, required this.onCardDropped});

  final KanbanColumn column;
  final ValueChanged<KanbanCard> onCardDropped;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = column.cards ?? const <KanbanCard>[];
    final name = column.name ?? '';
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: kanbanStatusColor(name).resolveFrom(context),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    kanbanStatusTitle(name, context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${cards.length}',
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
          Expanded(
            child: DragTarget<KanbanCard>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) => onCardDropped(details.data),
              builder: (context, candidate, _) => cards.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noCards,
                        style: TextStyle(
                          fontSize: 13,
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: secondaryText,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: ValueKey(
                        'kanban-column-${name.isEmpty ? '?' : name}',
                      ),
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: cards.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          LongPressDraggable<KanbanCard>(
                            data: cards[index],
                            // Drag copies are decorative motion/position cues;
                            // the readable card remains the interaction source.
                            feedback: Opacity(
                              opacity: 0.8,
                              child: SizedBox(
                                width: 260,
                                child: _KanbanCardTile(card: cards[index]),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.35,
                              child: _KanbanCardTile(card: cards[index]),
                            ),
                            child: _KanbanCardTile(card: cards[index]),
                          ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片块：标题 + 负责人 + 依赖标记。
class _KanbanCardTile extends StatelessWidget {
  const _KanbanCardTile({required this.card});

  final KanbanCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = card.cardID ?? '';
    final dependencyBadge = _dependencyBadge(context, card.linkCounts);
    return _KanbanPressFeedback(
      builder: (pressed) => CupertinoButton(
        key: ValueKey('kanban-card-$id'),
        pressedOpacity: _usesLightSurfaces(context) ? 1 : 0.4,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(10),
        onPressed: () => _openDetail(context, id),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // 动态色需显式 resolve：暗黑模式下不 resolve 会画成浅色卡。
            color: LightSurfaces.resolve(
              context,
              pressed ? LightSurfaces.pressed : LightSurfaces.card,
              dark: CupertinoColors.secondarySystemBackground,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              // Decorative hairline, shared with the column/divider line family.
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.cardBorder,
                dark: CupertinoColors.systemGrey.withValues(alpha: 0.25),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.title ?? l10n.unnamedCard,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _usesLightSurfaces(context)
                      ? CupertinoColors.label.resolveFrom(context)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.person,
                    size: 13,
                    // const 动态色不会自动 resolve：深色主题下冻结为黑色隐身，
                    // 必须显式 resolveFrom(context)。
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      card.assignee ?? l10n.unassigned,
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
                  ),
                  if (dependencyBadge != null) ...[
                    const SizedBox(width: 8),
                    dependencyBadge,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _dependencyBadge(BuildContext context, KanbanLinkCounts? linkCounts) {
    if (linkCounts == null) return null;
    final l10n = AppLocalizations.of(context);
    final parents = linkCounts.parents ?? 0;
    final children = linkCounts.children ?? 0;
    if (parents <= 0 && children <= 0) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintWarning,
          dark: CupertinoColors.systemYellow.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.link,
            size: 11,
            color: LightSurfaces.resolve(
              context,
              statusOrangeText.resolveFrom(context),
              dark: Color(CupertinoColors.systemOrange.toARGB32()),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            parents > 0
                ? l10n.parentsDependency(parents)
                : l10n.childrenDependency(children),
            style: TextStyle(
              fontSize: 11,
              // 徽章文字用全强度 label：statusOrangeText 在 20% 黄底上
              // dark 只有 ~1.45:1（背景追踪暴露的真问题），label 深浅色都达标。
              // （注意：必须 resolve，const 动态色冻结浅色变体会在深色下隐身。）
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, String cardId) {
    if (cardId.isEmpty) return;
    Navigator.of(context).push(
      HermesPageRoute<void>(
        builder: (_) => KanbanCardDetailPage(cardId: cardId),
      ),
    );
  }
}

/// 卡片详情页（描述 / 元信息 / 状态变更按钮 / 评论列表 / 添加评论）。
class KanbanCardDetailPage extends ConsumerStatefulWidget {
  const KanbanCardDetailPage({super.key, required this.cardId});

  final String cardId;

  @override
  ConsumerState<KanbanCardDetailPage> createState() =>
      _KanbanCardDetailPageState();
}

class _KanbanCardDetailPageState extends ConsumerState<KanbanCardDetailPage> {
  final TextEditingController _commentController = TextEditingController();
  String? _busyStatus;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kanbanDetailControllerProvider(widget.cardId));
    final state = async.valueOrNull;
    final boardAsync = ref.watch(kanbanControllerProvider);
    final readOnly = boardAsync.valueOrNull?.readOnly ?? false;

    ref.listen<AsyncValue<KanbanDetailState>>(
      kanbanDetailControllerProvider(widget.cardId),
      (previous, next) {
        final error = next.valueOrNull?.actionError;
        if (error != null && error != previous?.valueOrNull?.actionError) {
          unawaited(_showActionError(context, error));
        }
      },
    );

    final l10n = AppLocalizations.of(context);
    final page = CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: _kanbanNavigationBorder(context),
        middle: Text(
          state?.card?.title ?? l10n.cardDetail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      child: _buildContent(async, state, readOnly),
    );
    return _withKanbanLightTheme(context, page);
  }

  Widget _buildContent(
    AsyncValue<KanbanDetailState> async,
    KanbanDetailState? state,
    bool readOnly,
  ) {
    final l10n = AppLocalizations.of(context);
    if (state == null) {
      if (async.isLoading) {
        return const Center(child: CupertinoActivityIndicator(radius: 14));
      }
      return _buildError(async.error);
    }
    final envelope = state.envelope;
    final card = envelope?.card;
    if (envelope == null || card == null) {
      return Center(child: Text(l10n.cardDoesNotExist));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDescription(card),
        const SizedBox(height: 16),
        _buildMetadata(card),
        if (!readOnly && (card.status?.rawValue ?? '') != 'archived') ...[
          const SizedBox(height: 16),
          _buildStatusActions(card),
        ],
        const SizedBox(height: 16),
        _buildCommentsSection(state),
      ],
    );
  }

  Widget _buildDescription(KanbanCard card) {
    final l10n = AppLocalizations.of(context);
    return CupertinoListSection.insetGrouped(
      backgroundColor: LightSurfaces.resolve(
        context,
        LightSurfaces.page,
        dark: CupertinoColors.systemGroupedBackground,
      ),
      decoration: _kanbanSectionDecoration(context),
      separatorColor: _usesLightSurfaces(context)
          ? LightSurfaces.divider
          : null,
      dividerMargin: 0,
      additionalDividerMargin: 0,

      header: Text(l10n.description),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            (card.body ?? '').trim().isEmpty ? l10n.noDescription : card.body!,
            style: TextStyle(
              fontSize: 15,
              color: (card.body ?? '').trim().isEmpty
                  ? LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: secondaryText,
                    )
                  : CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadata(KanbanCard card) {
    final l10n = AppLocalizations.of(context);
    final rows = <Widget>[
      _metadataRow(
        l10n.statusLabel,
        Text(kanbanStatusTitle(card.status?.rawValue, context)),
      ),
      _metadataRow(l10n.assigneeLabel, Text(card.assignee ?? l10n.unassigned)),
      if (card.priority != null)
        _metadataRow(l10n.priorityLabel, Text('P${card.priority}')),
      if (card.createdAt != null && card.createdAt!.isNotEmpty)
        _metadataRow(l10n.createdAtLabel, Text(card.createdAt!)),
      if (card.updatedAt != null && card.updatedAt!.isNotEmpty)
        _metadataRow(l10n.updatedAtLabel, Text(card.updatedAt!)),
    ];
    return CupertinoListSection.insetGrouped(
      backgroundColor: LightSurfaces.resolve(
        context,
        LightSurfaces.page,
        dark: CupertinoColors.systemGroupedBackground,
      ),
      decoration: _kanbanSectionDecoration(context),
      separatorColor: _usesLightSurfaces(context)
          ? LightSurfaces.divider
          : null,
      dividerMargin: 0,
      additionalDividerMargin: 0,

      hasLeading: false,
      header: Text(l10n.info),
      children: rows,
    );
  }

  Widget _metadataRow(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  /// 状态变更按钮：workflow 状态（triage/todo/ready/done/blocked）去掉当前
  /// 状态（running 只能由 dispatcher 设置，不提供按钮）。
  Widget _buildStatusActions(KanbanCard card) {
    final l10n = AppLocalizations.of(context);
    const destinations = ['triage', 'todo', 'ready', 'done', 'blocked'];
    final current = card.status?.rawValue ?? '';
    final buttons = <Widget>[
      for (final status in destinations)
        if (status != current)
          _KanbanPressFeedback(
            enabled: _busyStatus == null,
            builder: (pressed) => CupertinoButton(
              key: ValueKey('kanban-status-$status'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              borderRadius: BorderRadius.circular(10),
              pressedOpacity: _usesLightSurfaces(context) ? 1 : 0.4,
              foregroundColor: _usesLightSurfaces(context)
                  ? statusBlueText.resolveFrom(context)
                  : null,
              color: _usesLightSurfaces(context)
                  ? (pressed ? LightSurfaces.pressed : LightSurfaces.selection)
                  : CupertinoColors.secondarySystemFill,
              onPressed: _busyStatus != null
                  ? null
                  : () => unawaited(_changeStatus(card, status)),
              child: _busyStatus == status
                  ? const CupertinoActivityIndicator(radius: 8)
                  : Text(
                      kanbanStatusTitle(status, context),
                      style: const TextStyle(fontSize: 13),
                    ),
            ),
          ),
    ];
    return CupertinoListSection.insetGrouped(
      backgroundColor: LightSurfaces.resolve(
        context,
        LightSurfaces.page,
        dark: CupertinoColors.systemGroupedBackground,
      ),
      decoration: _kanbanSectionDecoration(context),
      separatorColor: _usesLightSurfaces(context)
          ? LightSurfaces.divider
          : null,
      dividerMargin: 0,
      additionalDividerMargin: 0,

      header: Text(l10n.changeStatus),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ),
      ],
    );
  }

  Widget _buildCommentsSection(KanbanDetailState state) {
    final l10n = AppLocalizations.of(context);
    final comments = state.comments;
    return CupertinoListSection.insetGrouped(
      backgroundColor: LightSurfaces.resolve(
        context,
        LightSurfaces.page,
        dark: CupertinoColors.systemGroupedBackground,
      ),
      decoration: _kanbanSectionDecoration(context),
      separatorColor: _usesLightSurfaces(context)
          ? LightSurfaces.divider
          : null,
      dividerMargin: 0,
      additionalDividerMargin: 0,

      hasLeading: false,
      header: Text(l10n.commentsHeader(comments.length)),
      children: [
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              l10n.noComments,
              style: TextStyle(
                fontSize: 14,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          )
        else
          for (final comment in comments)
            Padding(
              key: ValueKey('kanban-comment-${comment.presentationID}'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.body ?? '',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _commentMeta(comment),
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
              ),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  key: const ValueKey('kanban-comment-input'),
                  controller: _commentController,
                  placeholder: l10n.addCommentPlaceholder,
                  decoration: _kanbanFieldDecoration(context),
                  placeholderStyle: _kanbanPlaceholderStyle(context),
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              AccessibleButton(
                key: const ValueKey('kanban-comment-send'),
                label: l10n.sendComment,
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed:
                    state.isSubmittingComment ||
                        _commentController.text.trim().isEmpty
                    ? null
                    : () => unawaited(_submitComment()),
                child: state.isSubmittingComment
                    ? const CupertinoActivityIndicator(radius: 9)
                    : const Icon(CupertinoIcons.arrow_up_circle_fill, size: 28),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _commentMeta(KanbanComment comment) {
    final parts = <String>[
      if (comment.author != null && comment.author!.isNotEmpty) comment.author!,
      if (comment.createdAt != null && comment.createdAt!.isNotEmpty)
        comment.createdAt!,
    ];
    return parts.join(' · ');
  }

  // -------------------------------------------------------------------------
  // 交互：状态变更 / 提交评论 / 错误弹窗
  // -------------------------------------------------------------------------

  Future<void> _changeStatus(KanbanCard card, String status) async {
    setState(() => _busyStatus = status);
    try {
      final error = await ref
          .read(kanbanControllerProvider.notifier)
          .setStatus(cardId: card.cardID ?? '', status: status);
      if (!mounted) return;
      if (error != null) {
        await _showActionError(context, error);
      } else {
        await ref
            .read(kanbanDetailControllerProvider(widget.cardId).notifier)
            .refresh();
      }
    } finally {
      if (mounted) setState(() => _busyStatus = null);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text;
    final ok = await ref
        .read(kanbanDetailControllerProvider(widget.cardId).notifier)
        .submitComment(text);
    if (!mounted) return;
    if (ok) _commentController.clear();
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.actionFailed),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            textStyle: _usesLightSurfaces(dialogContext)
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await ref
        .read(kanbanDetailControllerProvider(widget.cardId).notifier)
        .clearActionError();
  }

  Widget _buildError(Object? error) {
    final l10n = AppLocalizations.of(context);
    return Center(
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
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              error is ApiException
                  ? error.message
                  : (error?.toString() ?? l10n.unknownError),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('kanban-detail-retry'),
              onPressed: () => unawaited(
                ref
                    .read(
                      kanbanDetailControllerProvider(widget.cardId).notifier,
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
}

/// 创建卡片表单页（标题 / 描述 / 负责人 / 状态）。
///
/// 标题为空时创建按钮禁用（对齐 Hermex 编辑草稿校验）。状态可选
/// triage/todo/ready（对齐 Hermex createStatuses）。
class KanbanCreateCardPage extends ConsumerStatefulWidget {
  const KanbanCreateCardPage({super.key});

  @override
  ConsumerState<KanbanCreateCardPage> createState() =>
      _KanbanCreateCardPageState();
}

class _KanbanCreateCardPageState extends ConsumerState<KanbanCreateCardPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _assigneeController = TextEditingController();
  String _status = 'triage';
  bool _saving = false;

  bool get _canSave => !_saving && _titleController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _assigneeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final boardAsync = ref.watch(kanbanControllerProvider);
    final currentBoard = boardAsync.valueOrNull?.currentBoard;

    final page = CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: _kanbanNavigationBorder(context),
        middle: Text(l10n.newCard),
        trailing: CupertinoButton(
          key: const ValueKey('kanban-form-save'),
          padding: EdgeInsets.zero,
          onPressed: _canSave ? () => unawaited(_save(context)) : null,
          child: Text(l10n.create),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (currentBoard != null) ...[
            Text(
              l10n.boardPrefix(currentBoard.name ?? currentBoard.slug ?? ''),
              style: TextStyle(
                fontSize: 13,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildField(
            label: l10n.titleLabel,
            fieldKey: const ValueKey('kanban-form-title'),
            controller: _titleController,
            placeholder: l10n.cardTitlePlaceholder,
          ),
          const SizedBox(height: 16),
          _buildField(
            label: l10n.description,
            fieldKey: const ValueKey('kanban-form-body'),
            controller: _bodyController,
            placeholder: l10n.cardDescriptionPlaceholder,
            maxLines: 5,
          ),
          const SizedBox(height: 16),
          _buildField(
            label: l10n.assigneeLabel,
            fieldKey: const ValueKey('kanban-form-assignee'),
            controller: _assigneeController,
            placeholder: l10n.assignProfilePlaceholder,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.initialStatus,
            style: TextStyle(
              fontSize: 13,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildInitialStatusControl(),
        ],
      ),
    );
    return _withKanbanLightTheme(context, page);
  }

  Widget _buildInitialStatusControl() {
    final control = CupertinoSlidingSegmentedControl<String>(
      groupValue: _status,
      onValueChanged: (value) => setState(() => _status = value ?? 'triage'),
      children: {
        for (final status in KanbanController.createStatuses)
          status: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(kanbanStatusTitle(status, context)),
          ),
      },
    );
    if (!_usesLightSurfaces(context)) return control;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        // Decorative field outline; the native thumb identifies selection.
        border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
      ),
      child: CupertinoSlidingSegmentedControl<String>(
        groupValue: control.groupValue,
        onValueChanged: control.onValueChanged,
        children: control.children,
        backgroundColor: LightSurfaces.card,
        thumbColor: LightSurfaces.selection,
      ),
    );
  }

  Widget _buildField({
    required String label,
    required Key fieldKey,
    required TextEditingController controller,
    required String placeholder,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          key: fieldKey,
          controller: controller,
          placeholder: placeholder,
          decoration: _kanbanFieldDecoration(context),
          placeholderStyle: _kanbanPlaceholderStyle(context),
          maxLines: maxLines,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    setState(() => _saving = true);
    final controller = ref.read(kanbanControllerProvider.notifier);
    final ok = await controller.createCard(
      title: _titleController.text,
      body: _bodyController.text.trim().isEmpty ? null : _bodyController.text,
      status: _status,
      assignee: _assigneeController.text.trim().isEmpty
          ? null
          : _assigneeController.text,
    );
    if (!context.mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.maybePop(context);
    }
  }
}

bool _usesLightSurfaces(BuildContext context) =>
    CupertinoTheme.brightnessOf(context) == Brightness.light;

Widget _withKanbanLightTheme(BuildContext context, Widget child) {
  if (!_usesLightSurfaces(context)) return child;
  return CupertinoTheme(
    data: CupertinoTheme.of(context).copyWith(
      scaffoldBackgroundColor: LightSurfaces.page,
      barBackgroundColor: LightSurfaces.page,
      primaryColor: statusBlueText.resolveFrom(context),
    ),
    child: DefaultSelectionStyle(
      selectionColor: LightSurfaces.selection,
      cursorColor: statusBlueText.resolveFrom(context),
      child: child,
    ),
  );
}

Border? _kanbanNavigationBorder(BuildContext context) =>
    _usesLightSurfaces(context)
    ? const Border(bottom: BorderSide(color: LightSurfaces.divider, width: 0))
    : const CupertinoNavigationBar().border;

BoxDecoration? _kanbanSectionDecoration(BuildContext context) =>
    _usesLightSurfaces(context)
    ? const BoxDecoration(
        color: LightSurfaces.card,
        borderRadius: BorderRadius.all(Radius.circular(10)),
        // Decorative outline, consistent with the session list cards.
        border: Border.fromBorderSide(
          BorderSide(color: LightSurfaces.cardBorder, width: 0.5),
        ),
      )
    : null;

BoxDecoration? _kanbanFieldDecoration(BuildContext context) =>
    _usesLightSurfaces(context)
    ? BoxDecoration(
        color: LightSurfaces.card,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
      )
    : const CupertinoTextField().decoration;

TextStyle? _kanbanPlaceholderStyle(BuildContext context) =>
    _usesLightSurfaces(context)
    ? const TextStyle(
        fontWeight: FontWeight.w400,
        color: LightSurfaces.placeholder,
      )
    : const CupertinoTextField().placeholderStyle;

/// Surface feedback wraps native buttons only in light mode.
/// The original Cupertino fade, gesture handling and layout remain in dark mode.
class _KanbanPressFeedback extends StatefulWidget {
  const _KanbanPressFeedback({required this.builder, this.enabled = true});

  final Widget Function(bool pressed) builder;
  final bool enabled;

  @override
  State<_KanbanPressFeedback> createState() => _KanbanPressFeedbackState();
}

class _KanbanPressFeedbackState extends State<_KanbanPressFeedback> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesLightSurfaces(context)) return widget.builder(false);
    return Listener(
      onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: widget.builder(widget.enabled && _pressed),
    );
  }
}
