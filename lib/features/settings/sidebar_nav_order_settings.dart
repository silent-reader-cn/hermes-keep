import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell/sidebar_nav_order.dart';
import '../../app/shell/sidebar_utility_item.dart';
import '../../l10n/app_localizations.dart';
import 'settings_surfaces.dart';

/// 设置页「侧栏导航入口」分组（#154）。
///
/// 让主人自行安排宽屏侧栏两处承载区：
/// - **侧栏最上方**（纵向文字列表，默认 新建会话 / 定时任务 / 看板 / 技能）；
/// - **侧栏右下角**（一排小图标，默认 工作区 / 统计 / 记忆 / 下载 / 设置）。
///
/// 交互取舍：用**上移/下移 + 移到另一区**而不是拖拽 ——
/// `ReorderableListView` 需要固定高度，嵌进 `CupertinoListSection` 的滚动页里
/// 很容易出现高度/手势冲突；按钮式排序在同一列表里稳定、可点、无障碍标签清晰。
///
/// 显隐仍由「会话列表入口」组的开关负责，本组只管**位置与顺序**，两者正交。
class SidebarNavOrderSection extends ConsumerWidget {
  const SidebarNavOrderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final order = ref.watch(sidebarNavOrderProvider);
    final controller = ref.read(sidebarNavOrderProvider.notifier);

    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,
        header: Text(l10n.sidebarNavOrderSection),
        footer: Text(l10n.sidebarNavOrderSectionFooter),
        children: [
          _ZoneLabel(label: l10n.sidebarNavOrderTopLabel),
          for (var i = 0; i < order.top.length; i++)
            _NavOrderTile(
              id: order.top[i],
              inTop: true,
              index: i,
              total: order.top.length,
              onMoveUp: i == 0
                  ? null
                  : () => unawaited(controller.reorderTop(i, i - 1)),
              onMoveDown: i == order.top.length - 1
                  ? null
                  : () => unawaited(controller.reorderTop(i, i + 2)),
              onToggleZone: () =>
                  unawaited(controller.moveToBottom(order.top[i])),
            ),
          _ZoneLabel(label: l10n.sidebarNavOrderBottomLabel),
          if (order.bottom.isEmpty)
            CupertinoListTile(title: Text(l10n.sidebarNavOrderEmptyHint)),
          for (var i = 0; i < order.bottom.length; i++)
            _NavOrderTile(
              id: order.bottom[i],
              inTop: false,
              index: i,
              total: order.bottom.length,
              onMoveUp: i == 0
                  ? null
                  : () => unawaited(controller.reorderBottom(i, i - 1)),
              onMoveDown: i == order.bottom.length - 1
                  ? null
                  : () => unawaited(controller.reorderBottom(i, i + 2)),
              onToggleZone: () =>
                  unawaited(controller.moveToTop(order.bottom[i])),
            ),
          CupertinoListTile(
            key: const ValueKey('settings-nav-order-reset'),
            title: Text(l10n.sidebarNavOrderReset),
            onTap: () => unawaited(controller.reset()),
            trailing: const Icon(
              CupertinoIcons.arrow_counterclockwise,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区小标题（「侧栏最上方」/「侧栏右下角」）。
class _ZoneLabel extends StatelessWidget {
  const _ZoneLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 4.0),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isLight
              ? CupertinoColors.secondaryLabel.resolveFrom(context)
              : CupertinoColors.secondaryLabel,
        ),
      ),
    );
  }
}

/// 单个入口行：图标 + 名称 + 上移/下移/移到另一区。
class _NavOrderTile extends StatelessWidget {
  const _NavOrderTile({
    required this.id,
    required this.inTop,
    required this.index,
    required this.total,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleZone,
  });

  final String id;
  final bool inTop;
  final int index;
  final int total;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onToggleZone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isNewSession = id == SidebarNavOrder.newSessionId;
    final item = isNewSession
        ? null
        : sidebarUtilityItems.where((it) => it.id == id).firstOrNull;
    final label = isNewSession
        ? l10n.newSession
        : (item?.getTitle(l10n) ?? id);
    final icon = isNewSession
        ? CupertinoIcons.add
        : (item?.icon ?? CupertinoIcons.square);

    return CupertinoListTile(
      key: ValueKey('settings-nav-order-$id'),
      leading: Icon(icon, size: 20),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniAction(
            buttonKey: 'settings-nav-order-$id-up',
            icon: CupertinoIcons.chevron_up,
            label: l10n.sidebarNavOrderMoveUp,
            onPressed: onMoveUp,
          ),
          _MiniAction(
            buttonKey: 'settings-nav-order-$id-down',
            icon: CupertinoIcons.chevron_down,
            label: l10n.sidebarNavOrderMoveDown,
            onPressed: onMoveDown,
          ),
          _MiniAction(
            buttonKey: 'settings-nav-order-$id-zone',
            icon: inTop
                ? CupertinoIcons.arrow_down_to_line
                : CupertinoIcons.arrow_up_to_line,
            label: inTop
                ? l10n.sidebarNavOrderMoveToBottom
                : l10n.sidebarNavOrderMoveToTop,
            onPressed: onToggleZone,
          ),
        ],
      ),
    );
  }
}

/// 行内小按钮（上移/下移/换区）。
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final color = enabled
        ? (isLight
              ? CupertinoColors.activeBlue.resolveFrom(context)
              : CupertinoColors.activeBlue)
        : CupertinoColors.tertiaryLabel.resolveFrom(context);

    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: CupertinoButton(
        key: ValueKey(buttonKey),
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        minimumSize: const Size(28.0, 28.0),
        onPressed: onPressed,
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}