import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/session_list/session_entry_visibility.dart';
import '../../l10n/app_localizations.dart';
import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';
import 'sidebar_utility_item.dart';

/// 侧栏常驻工具入口行（TASK W2/W3 / 蓝本 SessionListComponents.swift §SessionSidebarUtilityRows）。
///
/// 宽屏下展示在会话列表顶部，提供任务、看板、工作区、技能、统计、记忆、设置的快捷跳转与激活高亮。
/// 受 [sessionEntryVisibilityProvider] 控制功能入口显隐；所有功能入口全关时整条工具条仅保留设置图标。
class SidebarUtilityToolbar extends ConsumerWidget {
  const SidebarUtilityToolbar({super.key, required this.currentLocation});

  /// 当前激活的路由路径。
  final String currentLocation;

  static const List<SidebarUtilityItem> _items = sidebarUtilityItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(sessionEntryVisibilityProvider);

    final l10n = AppLocalizations.of(context);
    final theme = CupertinoTheme.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final primaryColor = isLight
        ? statusBlueText.resolveFrom(context)
        : theme.primaryColor;
    final inactiveColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    final visibleItems = _items
        .where((item) {
          if (item.id == 'settings') return true;
          return visibility.isVisible(item.id);
        })
        .toList(growable: false);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: visibleItems
                .map((item) {
                  final isSelected =
                      currentLocation == item.path ||
                      currentLocation.startsWith('${item.path}/');
                  final title = item.getTitle(l10n);

                  return Expanded(
                    child: Semantics(
                      label: title,
                      selected: isSelected,
                      button: true,
                      child: CupertinoButton(
                        key: ValueKey('sidebar-utility-${item.id}'),
                        // 视觉压到 32pt（icon 20 + 上下 6pt），点击区保持
                        // 44pt HIG 下限；配合外层 6pt×2 边距总高 44px，
                        // 与内容区标准导航栏 / 紧凑导航条顶端对齐。
                        minimumSize: const Size(40, 32),
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        borderRadius: BorderRadius.circular(8.0),
                        color: isSelected
                            ? (isLight
                                  ? LightSurfaces.selection
                                  : primaryColor.withValues(alpha: 0.12))
                            : CupertinoColors.transparent,
                        onPressed: () {
                          unawaited(context.push(item.path));
                        },
                        child: Icon(
                          item.icon,
                          size: 20.0,
                          color: isSelected ? primaryColor : inactiveColor,
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
        Container(
          height: 0.5,
          // Decorative structural line; the icons carry the navigation semantics.
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
        ),
      ],
    );
    return isLight
        ? ColoredBox(color: LightSurfaces.page, child: content)
        : content;
  }
}
