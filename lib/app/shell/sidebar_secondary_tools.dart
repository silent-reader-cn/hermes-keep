import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/session_list/session_entry_visibility.dart';
import '../../l10n/app_localizations.dart';
import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';
import '../../features/session_list/session_list_providers.dart';
import '../../features/settings/settings_providers.dart';
import 'sidebar_nav_order.dart';
import 'sidebar_utility_item.dart';

/// 宽屏侧栏底部「次级功能」图标组（#149 案 A）。
///
/// 顶部 [SidebarToolsList] 只放 4 个高频入口（新建会话/定时任务/看板/技能），
/// 其余功能下沉到此处：工作区 / 统计 / 记忆 / 下载 / 设置。
///
/// 组件本身**只返回一行图标**（紧凑形态）：由 [SidebarStatusBar] 的 `trailing`
/// 槽嵌入底部行最右侧，与「已连接 / 端口 / 服务类型」同一行，
/// **不再单独占一行高度**（对齐设计稿：`● 已连接 ……… ▤ ◔ ☰ ↓ ⚙`）。
///
/// 行为：全部走 `context.push`（宽屏右侧面板栈，#77 既有设计）；
/// 显隐沿用 [sessionEntryVisibilityProvider]（设置项恒显示，与旧工具条口径一致）。
class SidebarSecondaryTools extends ConsumerWidget {
  const SidebarSecondaryTools({super.key, required this.currentLocation});

  /// 当前激活的路由路径（选中高亮）。
  final String currentLocation;

  // #154：底部次级项不再硬编码 —— 改由 sidebarNavOrderProvider 提供
  // （设置页「侧栏导航入口」可调位置与顺序）。默认值与旧常量一致。

  /// `new_session` 是**动作项**（无路由），若用户把它排到右下角，用这个合成条目
  /// 承载其图标与标题；点击走新建会话而不是 `context.push`。
  static final SidebarUtilityItem _newSessionItem = SidebarUtilityItem(
    id: SidebarNavOrder.newSessionId,
    path: '',
    icon: CupertinoIcons.add,
    getTitle: (l10n) => l10n.newSession,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final visibility = ref.watch(sessionEntryVisibilityProvider);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;

    final activeFg = isLight
        ? statusBlueText.resolveFrom(context)
        : CupertinoTheme.of(context).primaryColor;
    final inactiveFg = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final activeBg = isLight
        ? LightSurfaces.selection
        : activeFg.withValues(alpha: 0.12);

    // #154：顺序与成员来自配置；`new_session`（动作项）也被允许放在右下角。
    final navOrder = ref.watch(sidebarNavOrderProvider);
    final visible = <SidebarUtilityItem>[];
    for (final id in navOrder.bottom) {
      if (id == SidebarNavOrder.newSessionId) {
        visible.add(_newSessionItem);
        continue;
      }
      if (id == 'settings' || visibility.isVisible(id)) {
        final item = sidebarUtilityItems.firstWhere(
          (it) => it.id == id,
          orElse: () => sidebarUtilityItems.first,
        );
        visible.add(item);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: visible
          .map(
            (item) => _SecondaryIcon(
              item: item,
              label: item.getTitle(l10n),
              // 动作项（new_session）不参与路由高亮。
              selected: item.path.isNotEmpty &&
                  (currentLocation == item.path ||
                      currentLocation.startsWith('${item.path}/')),
              onPressed: item.path.isEmpty
                  ? () => unawaited(_onNewSession(context, ref))
                  : null,
              activeFg: activeFg,
              inactiveFg: inactiveFg,
              activeBg: activeBg,
            ),
          )
          .toList(growable: false),
    );
  }

  /// 新建会话并跳转（#154）。
  ///
  /// 与 `SidebarToolsList._onNewSession` 及 `SessionListPage._onNewSession`
  /// 同语义：先落 `createSession`，标记 `recentlyCreatedSessionIdProvider`
  /// （列表置顶/高亮用），再跳 `/chat/:id`。刻意不依赖页面私有方法。
  /// 只有当用户把动作项 `new_session` 排到右下角时才会被调用。
  Future<void> _onNewSession(BuildContext context, WidgetRef ref) async {
    final targetWorkspace = ref.read(selectedWorkspaceFilterProvider);
    final controller = ref.read(sessionListControllerProvider.notifier);
    final id = await controller.createSession(workspace: targetWorkspace);
    if (!context.mounted || id == null) return;
    ref.read(recentlyCreatedSessionIdProvider.notifier).markCreated(id);
    // 本组件只出现在宽屏侧栏（SessionSidebar 仅宽屏渲染），故一律 go。
    context.go('/chat/$id');
  }
}

/// 单个次级图标：命中区 30×26，图标 16，圆角 6（紧凑，与底部行高度匹配）。
class _SecondaryIcon extends StatelessWidget {
  const _SecondaryIcon({
    required this.item,
    required this.label,
    required this.selected,
    this.onPressed,
    required this.activeFg,
    required this.inactiveFg,
    required this.activeBg,
  });

  final SidebarUtilityItem item;
  final String label;
  final bool selected;

  /// 覆盖默认行为（动作项用）；null 时走 `context.push(item.path)`。
  final VoidCallback? onPressed;
  final Color activeFg;
  final Color inactiveFg;
  final Color activeBg;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('sidebar-secondary-semantics-${item.id}'),
      label: label,
      tooltip: label,
      selected: selected,
      button: true,
      child: CupertinoButton(
        key: ValueKey('sidebar-secondary-${item.id}'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(30.0, 26.0),
        borderRadius: BorderRadius.circular(6.0),
        color: selected ? activeBg : CupertinoColors.transparent,
        onPressed: onPressed ?? () => unawaited(context.push(item.path)),
        child: Icon(
          item.icon,
          size: 16.0,
          color: selected ? activeFg : inactiveFg,
        ),
      ),
    );
  }
}