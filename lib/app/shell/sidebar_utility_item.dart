import 'package:flutter/cupertino.dart';

import '../../l10n/app_localizations.dart';

/// 侧栏工具项配置（导航轨与工具条共享数据结构）。
class SidebarUtilityItem {
  const SidebarUtilityItem({
    required this.id,
    required this.path,
    required this.icon,
    required this.getTitle,
  });

  /// 唯一标识（用于显隐控制与 Semantics / ValueKey）。
  final String id;

  /// 目标路由路径。
  final String path;

  /// 图标数据。
  final IconData icon;

  /// 本地化标题获取函数。
  final String Function(AppLocalizations l10n) getTitle;
}

/// 侧栏工具条 / 导航轨共享项清单（8 个功能入口）。
const List<SidebarUtilityItem> sidebarUtilityItems = [
  SidebarUtilityItem(
    id: 'tasks',
    path: '/tasks',
    icon: CupertinoIcons.clock,
    getTitle: _getTasksTitle,
  ),
  SidebarUtilityItem(
    id: 'kanban',
    path: '/kanban',
    icon: CupertinoIcons.square_split_2x2,
    getTitle: _getKanbanTitle,
  ),
  SidebarUtilityItem(
    id: 'workspaces',
    path: '/workspaces',
    icon: CupertinoIcons.folder,
    getTitle: _getWorkspacesTitle,
  ),
  SidebarUtilityItem(
    id: 'skills',
    path: '/skills',
    icon: CupertinoIcons.hammer,
    getTitle: _getSkillsTitle,
  ),
  SidebarUtilityItem(
    id: 'insights',
    path: '/insights',
    icon: CupertinoIcons.chart_bar,
    getTitle: _getInsightsTitle,
  ),
  SidebarUtilityItem(
    id: 'memory',
    path: '/memory',
    // #75：bookmark 与收藏提示词按钮撞脸，记忆入口改用 book（记忆库语义）。
    icon: CupertinoIcons.book,
    getTitle: _getMemoryTitle,
  ),
  SidebarUtilityItem(
    id: 'downloads',
    path: '/downloads',
    icon: CupertinoIcons.arrow_down_circle,
    getTitle: _getDownloadsTitle,
  ),
  SidebarUtilityItem(
    id: 'settings',
    path: '/settings',
    icon: CupertinoIcons.gear_alt,
    getTitle: _getSettingsTitle,
  ),
];

String _getTasksTitle(AppLocalizations l10n) => l10n.tasksTitle;
String _getKanbanTitle(AppLocalizations l10n) => l10n.kanbanTitle;
String _getWorkspacesTitle(AppLocalizations l10n) => l10n.workspacesTitle;
String _getSkillsTitle(AppLocalizations l10n) => l10n.skillsTitle;
String _getInsightsTitle(AppLocalizations l10n) => l10n.insightsTitle;
String _getMemoryTitle(AppLocalizations l10n) => l10n.memoryTitle;
String _getDownloadsTitle(AppLocalizations l10n) => l10n.downloadsTitle;
String _getSettingsTitle(AppLocalizations l10n) => l10n.settingsTitle;
