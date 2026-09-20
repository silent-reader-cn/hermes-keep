import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell/adaptive_shell.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/widgets/adaptive_popover.dart';
import '../../core/models/workspace.dart';
import '../../core/providers/catalog_providers.dart';
import '../../l10n/app_localizations.dart';
import 'session_list_providers.dart';

/// 桌面端侧栏顶部「工作区选择器」组件（#145，设计案 C）。
///
/// 视觉与交互规范：
/// - 白底卡片行：左 20×20 圆角 6 图标容器 + 中间两行（主行工作区名 12.5px/600，
///   副行路径 10.5px 等宽体 + 会话计数）+ 右 12px chevron。
/// - 外边距 `0 12px 6px`，内边距 `8/10`，圆角 10，描边 0.5px。
/// - 浅色：面 [LightSurfaces.card]、描边 [LightSurfaces.cardBorder]、主行 `#1C1C1E`、
///   副行 [LightSurfaces.textSecondary]；
///   深色：面 `#1C1C1E`、描边 `#3A3A3C`、主行 `#EBEBF0`、副行 `#9A9AA0`。
/// - 点击向下展开 popover 菜单（空间不足自动向上翻转）：
///   「全部工作区」+ 各工作区根（name 优先、path 兜底）+ 当前项勾选。
/// - 窄屏（< 900）或工作区空列表/加载失败：安全折叠为 [SizedBox.shrink]，不显示错误态。
class SidebarWorkspaceSelector extends ConsumerStatefulWidget {
  const SidebarWorkspaceSelector({super.key});

  @override
  ConsumerState<SidebarWorkspaceSelector> createState() =>
      _SidebarWorkspaceSelectorState();
}

class _SidebarWorkspaceSelectorState
    extends ConsumerState<SidebarWorkspaceSelector> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (!isWide) {
      return const SizedBox.shrink();
    }

    final rootsAsync = ref.watch(workspaceRootsProvider);
    final roots = rootsAsync.valueOrNull;
    if (roots == null || roots.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedPath = ref.watch(selectedWorkspaceFilterProvider);
    final sessions =
        ref.watch(sessionListControllerProvider).valueOrNull?.sessions ??
        const [];
    final showSubagent =
        ref.watch(sessionListControllerProvider).valueOrNull?.showSubagent ??
        false;

    final l10n = AppLocalizations.of(context);

    // 匹配当前选中的工作区根
    WorkspaceRoot? currentRoot;
    if (selectedPath != null && selectedPath.isNotEmpty) {
      for (final root in roots) {
        if (matchesWorkspace(root.path, selectedPath)) {
          currentRoot = root;
          break;
        }
      }
    }

    // 统计当前工作区（或全部）下的有效会话数
    final int count;
    if (selectedPath == null || selectedPath.isEmpty) {
      count = sessions
          .where((s) => s.shouldAppearInSessionList)
          .where((s) => showSubagent || !s.isDelegatedSubagentSession)
          .length;
    } else {
      count = sessions
          .where((s) => matchesWorkspace(s.workspace, selectedPath))
          .where((s) => s.shouldAppearInSessionList)
          .where((s) => showSubagent || !s.isDelegatedSubagentSession)
          .length;
    }

    final String title;
    final String subText;
    if (currentRoot != null) {
      final name = currentRoot.name?.trim();
      final path = currentRoot.path?.trim() ?? selectedPath ?? '';
      title = (name != null && name.isNotEmpty) ? name : path;
      subText = '$path · ${l10n.workspaceSessionCount(count)}';
    } else if (selectedPath != null && selectedPath.isNotEmpty) {
      title = selectedPath;
      subText = '$selectedPath · ${l10n.workspaceSessionCount(count)}';
    } else {
      title = l10n.allWorkspaces;
      subText = l10n.workspaceSessionCount(count);
    }

    final cardBg = LightSurfaces.resolve(
      context,
      LightSurfaces.card,
      dark: const Color(0xFF1C1C1E),
    );
    final cardBorder = LightSurfaces.resolve(
      context,
      LightSurfaces.cardBorder,
      dark: const Color(0xFF3A3A3C),
    );
    final titleColor = LightSurfaces.resolve(
      context,
      const Color(0xFF1C1C1E),
      dark: const Color(0xFFEBEBF0),
    );
    final subColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: const Color(0xFF9A9AA0),
    );
    final iconContainerBg = LightSurfaces.resolve(
      context,
      const Color(0xFFE4E4EA),
      dark: const Color(0xFF2C2C2E),
    );
    final iconColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: const Color(0xFF9A9AA0),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: _anchorKey,
          behavior: HitTestBehavior.opaque,
          onTap: () => _openMenu(context, roots, selectedPath),
          child: Container(
            key: const ValueKey('sidebar-workspace-selector'),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cardBorder, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: iconContainerBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    CupertinoIcons.folder,
                    size: 12,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        key: const ValueKey('sidebar-workspace-selector-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subText,
                        key: const ValueKey('sidebar-workspace-selector-subtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  CupertinoIcons.chevron_down,
                  size: 12,
                  color: Color(0xFF9A9AA0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    List<WorkspaceRoot> roots,
    String? selectedPath,
  ) async {
    final renderBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final anchorWidth =
        renderBox?.hasSize == true ? renderBox!.size.width : 290.0;

    await showAdaptivePopover(
      context: context,
      anchorKey: _anchorKey,
      preferredWidth: anchorWidth,
      minWidth: 200,
      maxWidth: 340,
      placement: PopoverPlacement.bottom,
      align: PopoverAlign.start,
      flipOnOverflow: true,
      gap: 4,
      builder: (popoverContext, close) {
        return _WorkspaceSelectorMenu(
          roots: roots,
          selectedPath: selectedPath,
          onSelect: (path) {
            close();
            ref
                .read(selectedWorkspaceFilterProvider.notifier)
                .selectWorkspace(path);
          },
        );
      },
    );
  }
}

class _WorkspaceSelectorMenu extends StatelessWidget {
  const _WorkspaceSelectorMenu({
    required this.roots,
    required this.selectedPath,
    required this.onSelect,
  });

  final List<WorkspaceRoot> roots;
  final String? selectedPath;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAllSelected = selectedPath == null || selectedPath!.isEmpty;

    return Container(
      key: const ValueKey('sidebar-workspace-selector-popover'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkspaceMenuItem(
            key: const ValueKey('workspace-option-all'),
            title: l10n.allWorkspaces,
            isSelected: isAllSelected,
            onTap: () => onSelect(null),
          ),
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.divider,
              dark: CupertinoColors.separator,
            ),
          ),
          for (final root in roots) ...[
            _WorkspaceMenuItem(
              key: ValueKey('workspace-option-${root.path}'),
              title: (root.name != null && root.name!.trim().isNotEmpty)
                  ? root.name!.trim()
                  : (root.path ?? ''),
              subtitle: (root.name != null &&
                      root.name!.trim().isNotEmpty &&
                      root.path != null &&
                      root.path!.trim().isNotEmpty &&
                      root.path != root.name)
                  ? root.path!.trim()
                  : null,
              isSelected: selectedPath != null &&
                  matchesWorkspace(root.path, selectedPath),
              onTap: () => onSelect(root.path),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceMenuItem extends StatefulWidget {
  const _WorkspaceMenuItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_WorkspaceMenuItem> createState() => _WorkspaceMenuItemState();
}

class _WorkspaceMenuItemState extends State<_WorkspaceMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final hoverColor = isLight ? LightSurfaces.page : const Color(0xFF2C2C2E);

    final titleColor = LightSurfaces.resolve(
      context,
      const Color(0xFF1C1C1E),
      dark: const Color(0xFFEBEBF0),
    );
    final subColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: const Color(0xFF9A9AA0),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _isHovered ? hoverColor : const Color(0x00000000),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: widget.isSelected
                    ? const Icon(
                        CupertinoIcons.checkmark,
                        size: 15,
                        color: Color(0xFF007AFF),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: titleColor,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: subColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
