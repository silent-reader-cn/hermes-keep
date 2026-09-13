import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import 'notification_providers.dart';

/// 生命周期观察器（挂载在 App 壳根部）。
///
/// 职责：
/// 1. 驱动 [appLifecycleStateProvider]（供保活等逻辑消费；通知分流已不再
///    依赖前后台状态——应用内横幅移除后，前后台统一走系统通知）；
/// 2. 回到前台自动清除通知（回到 app 通知即消失）；
/// 3. 冷启动恢复：由通知点击拉起 app 时跳到对应会话；
/// 4. 启动时请求通知权限（Android 13+ 系统弹窗，一次性）。
class NotificationLifecycleObserver extends ConsumerStatefulWidget {
  const NotificationLifecycleObserver({super.key, required this.child});

  /// 被包裹的 App 根 Widget。
  final Widget child;

  @override
  ConsumerState<NotificationLifecycleObserver> createState() =>
      _NotificationLifecycleObserverState();
}

class _NotificationLifecycleObserverState
    extends ConsumerState<NotificationLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // 仅 Android：冷启动恢复 + 通知权限（桌面端无 POST_NOTIFICATIONS）+ 后台保活初始化。
        unawaited(_handleLaunchDetails());
        unawaited(
          ref.read(turnNotificationServiceProvider).requestPermission(),
        );
        unawaited(ref.read(backgroundKeepaliveServiceProvider).initialize());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    ref.read(appLifecycleStateProvider.notifier).setState(state);
    if (state == AppLifecycleState.resumed) {
      // 回到 app：通知使命完成，自动清除。
      unawaited(ref.read(turnNotificationServiceProvider).clearAll());
    }
    // 后台保活联动（前台服务/WorkManager 调度）专由 ChatController 以真值
    // （activeStreamId / isStreaming / foregroundServiceEnabled）驱动，
    // 见 chat_controller.dart _handleAppLifecycleChange——此处不做二次调用，
    // 避免与真值调用竞态覆盖 prefs（keyIsStreaming / keyActiveStreamId）。
  }

  /// 冷启动由通知拉起 → 跳转对应会话或下载页并清除通知。
  Future<void> _handleLaunchDetails() async {
    final payload = await ref
        .read(turnNotificationServiceProvider)
        .getLaunchSessionId();
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith('download:')) {
      ref.read(routerProvider).go('/downloads');
    } else {
      ref.read(routerProvider).go('/chat/$payload');
    }
    unawaited(ref.read(turnNotificationServiceProvider).clearAll());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
