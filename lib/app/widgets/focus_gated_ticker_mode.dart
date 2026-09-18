import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/session_list/session_auto_refresh.dart';

/// 窗口失焦（含被遮挡 / 锁屏）时静音子树内全部动画 ticker（#141 方案 A）。
///
/// **为什么需要它**：Flutter 的帧调度只看「有没有帧请求」—— 只要有一个无限
/// 循环动画在树上（例如会话行「活动中」的转圈），引擎就会按显示器刷新率持续
/// 出帧。而 Windows 端在「失焦但可见 / 被遮挡 / 锁屏」这些情形下并不像最小化
/// 那样进 `hidden`，于是窗口明明没人看得见，进程仍实测空转约 1 个 CPU 核与
/// ~73% GPU 3D 引擎（锁屏状态下连续采样 38 分钟，恒定不降）。
///
/// **为什么用 [TickerMode] 而不是逐处替换动画**：本仓有 30+ 处
/// `CupertinoActivityIndicator`（会话行、聊天状态行、工具卡、各页 loading），
/// 逐处降级既治标又分散，且新加一处就要记得处理一次。[TickerMode] 一处覆盖
/// 整棵子树，并且是官方为此场景提供的机制 —— `CupertinoActivityIndicator`
/// 内部即 `SingleTickerProviderStateMixin` + `_controller.repeat()`，受其管控。
///
/// **它不做什么**：只静音「重复动画产生的帧」。动画不倒退、不丢时间，重新聚焦
/// 后从当前时刻无缝继续；`Timer` / `setState` 驱动的真实内容更新（流式正文、
/// 新到达的消息）不受影响，照常渲染。
class FocusGatedTickerMode extends ConsumerWidget {
  const FocusGatedTickerMode({super.key, required this.child});

  /// 被管控的子树（全局挂在 `CupertinoApp.router` 的 builder 里）。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TickerMode(enabled: ref.watch(windowFocusedProvider), child: child);
  }
}
