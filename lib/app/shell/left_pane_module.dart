import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 进左栏的模块（窄栏友好型：列表/表单为主）。
/// 其余模块（看板横排多列 / 统计图表 / 任务表单 / 设置宽屏双栏）
/// 仍走右侧 #77 面板栈。
const kLeftPaneModuleIds = <String>{
  'workspaces',
  'memory',
  'downloads',
  'skills',
};

/// 检查指定模块标识是否属于左栏模块。
bool isLeftPaneModule(String id) => kLeftPaneModuleIds.contains(id);

/// 桌面端宽屏左栏展示内容状态 Provider。
///
/// - `null`: 显示会话列表 [SessionListPage]（默认）；
/// - 非空: 显示对应 path 的模块页（例如 `'/workspaces'`, `'/memory'`, `'/downloads'`, `'/skills'`）；
/// - 不落盘（重开应用回退为默认态）。
final leftPaneModuleProvider =
    NotifierProvider<LeftPaneModuleController, String?>(
  LeftPaneModuleController.new,
);

/// 控制桌面端宽屏左栏展示内容的控制器。
class LeftPaneModuleController extends Notifier<String?> {
  @override
  String? build() => null;

  /// 切换左栏展示指定模块（不触发路由变化）。
  void showModule(String path) {
    state = path;
  }

  /// 切换左栏回会话列表。
  void showSessions() {
    state = null;
  }

  /// 设置左栏模块路径（null 为会话列表）。
  void setModule(String? path) {
    state = path;
  }
}

/// 标识当前组件树处于桌面端左栏（侧栏模块视图）语境。
///
/// 在左栏语境下：
/// - 模块页自带的 [AdaptiveSliverNavigationBar] / [AppBackButton] 不显示返回按钮；
/// - 宽度自适应左栏宽度（约 340px），走窄栏单列布局分支。
class LeftPaneScope extends InheritedWidget {
  const LeftPaneScope({
    super.key,
    required super.child,
  });

  /// 检查当前上下文是否处于左栏模块语境。
  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LeftPaneScope>() != null;
  }

  @override
  bool updateShouldNotify(LeftPaneScope oldWidget) => false;
}
