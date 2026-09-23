import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/session_list/session_entry_visibility.dart';
import '../../l10n/app_localizations.dart';
import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';
import 'sidebar_utility_item.dart';

/// 宽屏侧栏底部「次级功能」横排图标条（#147 案 A）。
///
/// 顶部 [SidebarToolsList] 只放 4 个高频入口（新对话/定时任务/看板/技能），
/// 其余功能下沉到此处：工作区 / 统计 / 记忆 / 下载 / 设置。
/// 放底部而非顶部，是因为这些入口使用频率明显低于顶部四项，且底部横排
/// 只占一行高度（约 34px），比继续往顶部纵向堆更省空间。
///
/// 行为：全部走 `context.push`（宽屏右侧面板栈，#77 既有设计）；
/// 显隐沿用 [sessionEntryVisibilityProvider]（设置项恒显示，与旧工具条口径一致）。
class SidebarSecondaryTools extends ConsumerWidget {
  const SidebarSecondaryTools({super.key, required this.currentLocation});

  /// 当前激活的路由路径（选中高亮）。
  final String currentLocation;

  /// 底部次级项（顺序即展示顺序）。
  static const List<String> _ids = <String>[
    'workspaces',
    'insights',
    'memory',
    'downloads',
    'settings',
  ];

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

    final visible = <SidebarUtilityItem>[];
    for (final id in _ids) {
      if (id == 'settings' || visibility.isVisible(id)) {
        final item = sidebarUtilityItems.firstWhere(
          (it) => it.id == id,
          orElse: () => sidebarUtilityItems.first,
        );
        visible.add(item);
      }
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 0.5, color: divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 5.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: visible
                .map(
                  (item) => _SecondaryIcon(
                    item: item,
                    label: item.getTitle(l10n),
                    selected:
                        currentLocation == item.path ||
                        currentLocation.startsWith('${item.path}/'),
                    activeFg: activeFg,
                    inactiveFg: inactiveFg,
                    activeBg: activeBg,
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );

    return isLight
        ? ColoredBox(color: LightSurfaces.page, child: content)
        : content;
  }
}

/// 单个次级图标：命中区 34×28，图标 17，圆角 7。
class _SecondaryIcon extends StatelessWidget {
  const _SecondaryIcon({
    required this.item,
    required this.label,
    required this.selected,
    required this.activeFg,
    required this.inactiveFg,
    required this.activeBg,
  });

  final SidebarUtilityItem item;
  final String label;
  final bool selected;
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
        minimumSize: const Size(34.0, 28.0),
        borderRadius: BorderRadius.circular(7.0),
        color: selected ? activeBg : CupertinoColors.transparent,
        onPressed: () => unawaited(context.push(item.path)),
        child: Icon(
          item.icon,
          size: 17.0,
          color: selected ? activeFg : inactiveFg,
        ),
      ),
    );
  }
}