import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/session_list/session_entry_visibility.dart';
import '../../features/session_list/session_list_providers.dart';
import '../../features/settings/settings_providers.dart';
import '../../l10n/app_localizations.dart';
import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';
import 'sidebar_nav_order.dart';
import 'sidebar_utility_item.dart';

/// 宽屏侧栏顶部「常用功能」纵向列表（#147 案 A，参考 Codex 的顶部功能区）。
///
/// 结构与 Codex 一致：品牌行 + 4 个纵向功能项（[新对话] 为动作，其余为路由跳转），
/// 下方以发丝线与会话列表分隔。
///
/// 为什么是纵向列表而非图标网格：与会话行同构（都是「细图标 + 文字 + 可点行」），
/// 视觉语言统一、可读性最好；图标网格在 340px 侧栏里显得更重（案 B 已否决）。
///
/// 行为约定：
/// - [新对话] 走 `createSession` + 跳转（宽屏 `go` / 窄屏 `push`），与列表头部的
///   新建按钮同语义（复用同一套 provider，不另造会话创建逻辑）；
/// - 其余项一律 `context.push`，落到宽屏右侧面板栈（#77 既有设计）；
/// - 受 [sessionEntryVisibilityProvider] 控制显隐，与旧工具条口径一致。
class SidebarToolsList extends ConsumerWidget {
  const SidebarToolsList({super.key, required this.currentLocation});

  /// 当前激活的路由路径（用于选中高亮）。
  final String currentLocation;

  // #154：「顶部常用项」不再硬编码 —— 改由 sidebarNavOrderProvider 提供
  // （设置页「侧栏导航入口」可调位置与顺序）。默认值与旧常量一致。

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
    final divider = LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: CupertinoColors.separator,
    );

    final navOrder = ref.watch(sidebarNavOrderProvider);
    final rows = <Widget>[];
    for (final id in navOrder.top) {
      if (id == 'new_session') {
        rows.add(
          _ToolRow(
            itemId: 'new_session',
            icon: CupertinoIcons.add,
            label: l10n.newSession,
            selected: false,
            activeFg: activeFg,
            inactiveFg: inactiveFg,
            activeBg: activeBg,
            onTap: () => unawaited(_onNewSession(context, ref)),
          ),
        );
        continue;
      }
      if (id != 'settings' && !visibility.isVisible(id)) continue;
      final item = sidebarUtilityItems.firstWhere(
        (it) => it.id == id,
        orElse: () => sidebarUtilityItems.first,
      );
      final selected =
          currentLocation == item.path ||
          currentLocation.startsWith('${item.path}/');
      rows.add(
        _ToolRow(
          itemId: item.id,
          icon: item.icon,
          label: item.getTitle(l10n),
          selected: selected,
          activeFg: activeFg,
          inactiveFg: inactiveFg,
          activeBg: activeBg,
          onTap: () => unawaited(context.push(item.path)),
        ),
      );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
        Container(height: 0.5, color: divider),
      ],
    );

    return isLight
        ? ColoredBox(color: LightSurfaces.page, child: content)
        : content;
  }

  /// 新建会话并跳转 —— 与 `SessionListPage._onNewSession` 同语义：
  /// 先落 `createSession`，标记 `recentlyCreatedSessionIdProvider`（列表置顶/高亮用），
  /// 再按宽窄屏分别 `go` / `push`。刻意不依赖页面私有方法，避免跨层耦合。
  Future<void> _onNewSession(BuildContext context, WidgetRef ref) async {
    final targetWorkspace = ref.read(selectedWorkspaceFilterProvider);
    final controller = ref.read(sessionListControllerProvider.notifier);
    final id = await controller.createSession(workspace: targetWorkspace);
    if (!context.mounted || id == null) return;
    ref.read(recentlyCreatedSessionIdProvider.notifier).markCreated(id);
    // 本组件只出现在宽屏侧栏（SessionSidebar 仅宽屏渲染），故一律 go ——
    // 与 SessionListPage._openChatRoute 的宽屏分支同语义；同时避免为此
    // 引用 adaptive_shell.dart 里的 kAdaptiveBreakpoint 造成循环依赖。
    context.go('/chat/$id');
  }
}

/// 单个工具行：细图标 + 文字，行高 28，圆角 7（与设计稿一致）。
class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.itemId,
    required this.icon,
    required this.label,
    required this.selected,
    required this.activeFg,
    required this.inactiveFg,
    required this.activeBg,
    required this.onTap,
  });

  final String itemId;
  final IconData icon;
  final String label;
  final bool selected;
  final Color activeFg;
  final Color inactiveFg;
  final Color activeBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? activeFg : inactiveFg;
    return Semantics(
      key: ValueKey('sidebar-tool-semantics-$itemId'),
      label: label,
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1.0),
        child: CupertinoButton(
          key: ValueKey('sidebar-tool-$itemId'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(double.infinity, 28.0),
          borderRadius: BorderRadius.circular(7.0),
          color: selected ? activeBg : CupertinoColors.transparent,
          onPressed: onTap,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Icon(icon, size: 14.0, color: fg),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        // #153：对齐 markdown 正文基准（15），原 12.5 偏小。
                        fontSize: 15.0,
                        color: selected
                            ? activeFg
                            : LightSurfaces.resolve(
                                context,
                                const Color(0xFF1C1C1E),
                                dark: CupertinoColors.label,
                              ),
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
}