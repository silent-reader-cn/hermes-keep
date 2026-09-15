import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/accessibility.dart';
import '../../features/session_list/session_entry_visibility.dart';
import '../../l10n/app_localizations.dart';
import 'adaptive_action_menu.dart';

/// 窄屏大标题右侧的快捷导航下拉按钮（TASK W3-2 / W3）。
///
/// 仅在窄屏（width < 900）大标题右侧展示，点击后通过 [AdaptiveActionMenu.show] 展开
/// 下拉菜单，提供任务、看板、工作区、技能、统计、记忆 6 个功能模块的快捷跳转（受
/// [SessionEntryVisibility] 控制显隐）。
///
/// 当所有入口均处于隐藏状态（`showsAny == false`）时渲染为 [SizedBox.shrink]。
class NarrowNavigationDropdownButton extends ConsumerStatefulWidget {
  const NarrowNavigationDropdownButton({
    super.key,
    this.buttonKey = const ValueKey('narrow-nav-dropdown'),
    this.icon = CupertinoIcons.chevron_down,
    this.iconSize = 20.0,
    this.openSignal,
  });

  /// 按钮组件的 Key（用于测试定位）。
  final Key? buttonKey;

  /// 下拉图标（默认 `CupertinoIcons.chevron_down`）。
  final IconData icon;

  /// 图标大小。
  final double iconSize;

  /// 外部「打开请求」通道（`Listenable` 语义：被通知即等同点击本按钮）。
  ///
  /// 供窄屏大标题点击使用（#128：点击标题 = 点击 ▾）：标题所在的 header
  /// delegate 触达不到本组件内部状态，改由持有方（导航栏 / 会话列表页）创建
  /// `ValueNotifier`，标题被点击即通知本组件打开同一个下拉菜单；弹层锚点仍是
  /// 本按钮的 [_anchorKey]，位置与直接点击 ▾ 完全一致。
  final Listenable? openSignal;

  @override
  ConsumerState<NarrowNavigationDropdownButton> createState() =>
      _NarrowNavigationDropdownButtonState();
}

class _NarrowNavigationDropdownButtonState
    extends ConsumerState<NarrowNavigationDropdownButton> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.openSignal?.addListener(_handleOpenSignal);
  }

  @override
  void didUpdateWidget(covariant NarrowNavigationDropdownButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openSignal != widget.openSignal) {
      oldWidget.openSignal?.removeListener(_handleOpenSignal);
      widget.openSignal?.addListener(_handleOpenSignal);
    }
  }

  @override
  void dispose() {
    widget.openSignal?.removeListener(_handleOpenSignal);
    super.dispose();
  }

  /// 外部（大标题 / 中标题点击）请求打开下拉：与点击 ▾ 同一入口、同一锚点。
  void _handleOpenSignal() {
    if (!mounted) return;
    final visibility = ref.read(sessionEntryVisibilityProvider);
    if (!visibility.showsAny) return;
    unawaited(_openMenu(context, AppLocalizations.of(context), visibility));
  }

  Future<void> _openMenu(
    BuildContext context,
    AppLocalizations l10n,
    SessionEntryVisibility visibility,
  ) async {
    final items = <AdaptiveMenuItem>[
      if (visibility.tasks)
        AdaptiveMenuItem(
          key: const ValueKey('narrow-nav-tasks'),
          label: l10n.tasks,
          onPressed: () => unawaited(context.push('/tasks')),
        ),
      if (visibility.kanban)
        AdaptiveMenuItem(
          key: const ValueKey('narrow-nav-kanban'),
          label: l10n.kanban,
          onPressed: () => unawaited(context.push('/kanban')),
        ),
      if (visibility.workspaces)
        AdaptiveMenuItem(
          key: const ValueKey('narrow-nav-workspaces'),
          label: l10n.workspacesTitle,
          onPressed: () => unawaited(context.push('/workspaces')),
        ),
      if (visibility.skills)
        AdaptiveMenuItem(
          key: const ValueKey('narrow-nav-skills'),
          label: l10n.skills,
          onPressed: () => unawaited(context.push('/skills')),
        ),
      if (visibility.insights)
        AdaptiveMenuItem(
          key: const ValueKey('narrow-nav-insights'),
          label: l10n.insights,
          onPressed: () => unawaited(context.push('/insights')),
        ),
      if (visibility.memory)
        AdaptiveMenuItem(
          key: const ValueKey('narrow-nav-memory'),
          label: l10n.memoryTitle,
          onPressed: () => unawaited(context.push('/memory')),
        ),
      if (visibility.downloads)
        AdaptiveMenuItem(
          key: const ValueKey('narrow-nav-downloads'),
          label: l10n.downloadsTitle,
          onPressed: () => unawaited(context.push('/downloads')),
        ),
    ];

    if (items.isEmpty) return;

    await AdaptiveActionMenu.show(
      context,
      anchorKey: _anchorKey,
      items: items,
      cancelLabel: l10n.cancel,
      cancelKey: const ValueKey('narrow-nav-cancel'),
      preferredWidth: 200,
      minWidth: 160,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibility = ref.watch(sessionEntryVisibilityProvider);
    if (!visibility.showsAny) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    return KeyedSubtree(
      key: _anchorKey,
      child: AccessibleButton(
        key: widget.buttonKey,
        label: l10n.utilityNavigation,
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () => unawaited(_openMenu(context, l10n, visibility)),
        child: Icon(widget.icon, size: widget.iconSize),
      ),
    );
  }
}
