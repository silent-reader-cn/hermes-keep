import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell/left_pane_module.dart';

/// 页面左上角统一返回按钮（跨 feature 复用）。
///
/// App 顶层页面统一用 `context.go` 跳转（go_router 无页面堆栈），而 Windows
/// 等桌面端没有系统返回手势/导航键，会话列表之外的所有页面必须显式提供
/// 返回入口，否则无法回到上级页面。
///
/// 行为：当前路由可 pop（存在上级页面，如 `push` 进入的详情页）→ `pop`
/// 返回；否则按 [fallback] 兜底跳转（默认 `/` 会话列表主页，即页面是从
/// `go` 直进、没有返回堆栈的场景）。
/// 在左栏模块视图（[LeftPaneScope]）中不展示返回按钮。
///
/// 图标：纤细 `CupertinoIcons.chevron_left`（20pt），细度对齐窄屏大标题
/// 右侧 `NarrowNavigationDropdownButton` 的 `chevron_down`（参照 `_BackChevron`
/// 的粗 chevron 已弃用）。
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.fallback = '/'});

  /// 无可 pop 堆栈时兜底跳转的路径（默认主页 `/`）。
  final String fallback;

  @override
  Widget build(BuildContext context) {
    if (LeftPaneScope.of(context)) {
      return const SizedBox.shrink();
    }
    // 语义标签沿用 SDK 返回按钮的本地化文案（en: Back / zh: 返回）。
    final backLabel = CupertinoLocalizations.of(context).backButtonLabel;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: backLabel,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        // 点击热区 ≥ 44×44（Cupertino 最小交互尺寸），不随图标缩小。
        minimumSize: const Size(44, 44),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(fallback);
          }
        },
        child: const Icon(CupertinoIcons.chevron_left, size: 20.0),
      ),
    );
  }
}
