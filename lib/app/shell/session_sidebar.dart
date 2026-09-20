import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/downloads/download_page.dart';
import '../../features/memory/memory_page.dart';
import '../../features/session_list/session_list_page.dart';
import '../../features/skills/skills_page.dart';
import '../../features/workspace_manager/workspace_manager_page.dart';
import 'left_pane_module.dart';
import 'sidebar_nav_rail.dart';
import 'sidebar_status_bar.dart';

/// 宽屏自适应外壳的左侧常驻侧栏（TASK W1 / #145 重设计 + #145 第二轮 T2 左栏模块切换）。
///
/// 结构自左向右：50px 导航轨（[SidebarNavRail]）+ 列表列/模块展示区。
/// - [leftPaneModuleProvider] 为 null 时：展示会话列表与底部状态条（[SidebarStatusBar]）；
/// - [leftPaneModuleProvider] 非空时：展示对应模块页（工作区管理 / 记忆 / 下载 / 技能）。
class SessionSidebar extends ConsumerWidget {
  const SessionSidebar({super.key, required this.currentLocation});

  /// 当前激活的路由路径。
  final String currentLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leftPaneModule = ref.watch(leftPaneModuleProvider);

    // Android 15+ 强制 edge-to-edge（targetSdk >= 35）：宽屏侧栏是全项目唯一
    // 未处理状态栏 inset 的顶层区域（todo #16 方案 A）。外层 SafeArea 一次吸收
    // 顶部 inset —— 工具条整体下移、不再被系统状态栏盖住（现象①）；其
    // MediaQuery.removePadding(top) 同时使子树 SessionListPage header 读到的
    // MediaQuery.paddingOf(context).top 归零，消除工具条/搜索栏之间的状态栏
    // 高度空白带（现象②），一处改动两现象同消。bottom: false 按方案 A 不吸收
    // 底部 inset；默认视口（padding == 0）下 SafeArea 空转，窄屏不渲染本组件，
    // 均零回归。禁止手动给 SidebarUtilityToolbar 加 paddingTop（会双倍间距）。
    return SafeArea(
      key: const ValueKey('adaptive-session-sidebar'),
      bottom: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SidebarNavRail(currentLocation: currentLocation),
          Expanded(
            child: leftPaneModule == null
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 侧栏左侧已有 SidebarNavRail 提供工具入口，内部会话
                      // 列表不再重复渲染工具行，避免宽屏双层入口重叠；设置图标同样由
                      // 导航轨承担，隐藏列表头部右侧齿轮避免双设置入口。
                      Expanded(
                        child: SessionListPage(
                          showUtilityRows: false,
                          showSettingsTrailing: false,
                          showFab: false,
                        ),
                      ),
                      SidebarStatusBar(),
                    ],
                  )
                : _buildModulePane(context, leftPaneModule),
          ),
        ],
      ),
    );
  }

  Widget _buildModulePane(BuildContext context, String modulePath) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            size: Size(constraints.maxWidth, mediaQuery.size.height),
          ),
          child: LeftPaneScope(
            child: _buildModuleWidget(modulePath),
          ),
        );
      },
    );
  }

  Widget _buildModuleWidget(String modulePath) {
    final normalized = modulePath.startsWith('/') ? modulePath : '/$modulePath';
    switch (normalized) {
      case '/workspaces':
        return const WorkspaceManagerPage(
          key: ValueKey('left-pane-workspaces'),
        );
      case '/memory':
        return const MemoryPage(
          key: ValueKey('left-pane-memory'),
        );
      case '/downloads':
        return const DownloadPage(
          key: ValueKey('left-pane-downloads'),
        );
      case '/skills':
        return const SkillsPage(
          key: ValueKey('left-pane-skills'),
        );
      default:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SessionListPage(
                showUtilityRows: false,
                showSettingsTrailing: false,
                showFab: false,
              ),
            ),
            SidebarStatusBar(),
          ],
        );
    }
  }
}
