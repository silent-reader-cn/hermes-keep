import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/session_list/session_list_page.dart';
import 'sidebar_brand_bar.dart';
import 'sidebar_secondary_tools.dart';
import 'sidebar_status_bar.dart';
import 'sidebar_tools_list.dart';

/// 宽屏自适应外壳的左侧常驻侧栏。
///
/// 结构自上而下（#149 案 A，对齐设计稿）：
/// 1. [SidebarBrandBar] —— 品牌行：`[logo] Hermes ……… [搜索][刷新][筛选]`
///    （搜索图标可展开一行搜索框）；
/// 2. [SidebarToolsList] —— 顶部常用功能纵向列表（新建会话 / 定时任务 / 看板 / 技能）；
/// 3. [SessionListPage] —— 会话列表（按工作区分组，见 #146）；
/// 4. [SidebarStatusBar] —— 连接状态条，**次级功能图标并入住同一行最右侧**
///    （`trailing` 槽），不再单独占一行高度。
///
/// 演进说明：本组件曾包含 50px 竖排导航轨（SidebarNavRail）与「点击导航轨把模块
/// 显示到左栏」的 leftPaneModuleProvider 机制（#145）。2026-09 主人实机判定竖轨
/// 设计不佳，改回单列侧栏 + 品牌行/顶部功能区（#149）；功能入口一律走宽屏右侧
/// 面板栈（`context.push`，#77 既有设计），左栏始终只承载会话列表。
class SessionSidebar extends ConsumerWidget {
  const SessionSidebar({super.key, required this.currentLocation});

  /// 当前激活的路由路径（工具列表选中高亮用）。
  final String currentLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Android 15+ 强制 edge-to-edge（targetSdk >= 35）：宽屏侧栏是全项目唯一
    // 未处理状态栏 inset 的顶层区域（todo #16 方案 A）。外层 SafeArea 一次吸收
    // 顶部 inset —— 品牌行整体下移、不再被系统状态栏盖住（现象①）；其
    // MediaQuery.removePadding(top) 同时使子树 SessionListPage header 读到的
    // MediaQuery.paddingOf(context).top 归零，消除品牌行/列表之间的状态栏
    // 高度空白带（现象②），一处改动两现象同消。bottom: false 按方案 A 不吸收
    // 底部 inset；默认视口（padding == 0）下 SafeArea 空转，窄屏不渲染本组件，
    // 均零回归。禁止手动给品牌行加 paddingTop（会双倍间距）。
    return SafeArea(
      key: const ValueKey('adaptive-session-sidebar'),
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SidebarBrandBar(),
          SidebarToolsList(currentLocation: currentLocation),
          // 品牌行已承担搜索/刷新/筛选、工具列表承担新建会话与常用模块，
          // 内部会话列表不再重复渲染这些入口（showUtilityRows/showSettingsTrailing
          // 传 false，showFab 亦关闭）——避免宽屏多层双入口。
          const Expanded(
            child: SessionListPage(
              showUtilityRows: false,
              showSettingsTrailing: false,
              showFab: false,
            ),
          ),
          SidebarStatusBar(
            trailing: SidebarSecondaryTools(currentLocation: currentLocation),
          ),
        ],
      ),
    );
  }
}