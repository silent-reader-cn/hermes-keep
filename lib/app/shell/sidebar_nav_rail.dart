import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/session_list/session_entry_visibility.dart';
import '../../l10n/app_localizations.dart';
import '../theme/light_surfaces.dart';
import 'sidebar_utility_item.dart';

/// 桌面端侧栏 50px 宽竖排导航轨（#145 规格 B 案）。
///
/// 承载 tasks / kanban / workspaces / skills / insights / memory / downloads 7 个
/// 功能入口（顶部）与 settings 设置入口（钉底），中间以 20×0.5px 分隔线与 Spacer 分隔。
/// 图标 19px、命中区 34×34、圆角 9；显隐受 [sessionEntryVisibilityProvider] 控制。
class SidebarNavRail extends ConsumerWidget {
  const SidebarNavRail({super.key, required this.currentLocation});

  /// 导航轨固定宽度（50px）。
  static const double railWidth = 50.0;

  /// 当前激活的路由路径。
  final String currentLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(sessionEntryVisibilityProvider);
    final l10n = AppLocalizations.of(context);

    final bgColor = LightSurfaces.resolve(
      context,
      const Color(0xFFEAEAF0),
      dark: const Color(0xFF242426),
    );
    final borderColor = LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: const Color(0xFF3A3A3C),
    );
    final activeBg = LightSurfaces.resolve(
      context,
      LightSurfaces.selection,
      dark: const Color(0xFF0A3A66),
    );
    final activeFg = LightSurfaces.resolve(
      context,
      const Color(0xFF007AFF),
      dark: const Color(0xFF4DA3FF),
    );
    final inactiveFg = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: const Color(0xFF9A9AA0),
    );

    final topItems = sidebarUtilityItems
        .where((item) => item.id != 'settings')
        .toList(growable: false);
    final settingsItem = sidebarUtilityItems.firstWhere(
      (item) => item.id == 'settings',
    );

    final visibleTopItems = topItems
        .where((item) => visibility.isVisible(item.id))
        .toList(growable: false);

    return Container(
      width: railWidth,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: BorderSide(
            width: 0.5,
            color: borderColor,
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < visibleTopItems.length; i++) ...[
            if (i > 0) const SizedBox(height: 2.0),
            _buildItem(
              context,
              visibleTopItems[i],
              l10n,
              activeBg: activeBg,
              activeFg: activeFg,
              inactiveFg: inactiveFg,
            ),
          ],
          if (visibleTopItems.isNotEmpty) ...[
            const SizedBox(height: 6.0),
            Container(
              width: 20.0,
              height: 0.5,
              color: borderColor,
            ),
            const SizedBox(height: 6.0),
          ],
          const Spacer(),
          _buildItem(
            context,
            settingsItem,
            l10n,
            activeBg: activeBg,
            activeFg: activeFg,
            inactiveFg: inactiveFg,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    SidebarUtilityItem item,
    AppLocalizations l10n, {
    required Color activeBg,
    required Color activeFg,
    required Color inactiveFg,
  }) {
    final isSelected =
        currentLocation == item.path ||
        currentLocation.startsWith('${item.path}/');
    final title = item.getTitle(l10n);

    return Semantics(
      key: ValueKey('sidebar-utility-${item.id}'),
      label: title,
      tooltip: title,
      selected: isSelected,
      button: true,
      child: SizedBox(
        width: 34.0,
        height: 34.0,
        child: CupertinoButton(
          key: ValueKey('sidebar-nav-${item.id}'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(34.0, 34.0),
          borderRadius: BorderRadius.circular(9.0),
          color: isSelected ? activeBg : CupertinoColors.transparent,
          onPressed: () {
            // #77 宽屏右侧面板导航栈：侧栏入口必须 push 入栈（而非 go 替换），
            // 否则模块页不积累导航栈、返回无法逐级回退 —— 与旧
            // SidebarUtilityToolbar 的跳转语义逐字一致（既有
            // wide_panel_nav_stack_test 即钉此行为）。
            unawaited(context.push(item.path));
          },
          child: Icon(
            item.icon,
            size: 19.0,
            color: isSelected ? activeFg : inactiveFg,
          ),
        ),
      ),
    );
  }
}
