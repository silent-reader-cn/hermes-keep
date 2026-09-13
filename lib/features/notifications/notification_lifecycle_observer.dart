import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import 'notification_providers.dart';

/// 生命周期观察器（挂载在 App 壳根部）。
///
/// 职责：
/// 1. 驱动 [appLifecycleStateProvider]（前后台判断依据，hook 据此决定发不发）；
/// 2. 回到前台自动清除通知（回到 app 通知即消失）；
/// 3. 冷启动恢复：由通知点击拉起 app 时跳到对应会话；
/// 4. 启动时请求通知权限（Android 13+ 系统弹窗，一次性）；
/// 5. In-app 通知悬浮横幅：前台跨会话触发时提示，2.8s 自动消失，可点击跳转对应会话。
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
  Timer? _inAppDismissTimer;

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
    _inAppDismissTimer?.cancel();
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
  Widget build(BuildContext context) {
    ref.listen<InAppNotificationItem?>(inAppNotificationProvider, (prev, next) {
      _inAppDismissTimer?.cancel();
      if (next != null) {
        _inAppDismissTimer = Timer(const Duration(milliseconds: 2800), () {
          if (mounted) {
            ref.read(inAppNotificationProvider.notifier).state = null;
          }
        });
      }
    });

    final inApp = ref.watch(inAppNotificationProvider);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (inApp != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _InAppNotificationBanner(
                  key: ValueKey('in-app-notification-${inApp.id}'),
                  item: inApp,
                  onTap: () {
                    _inAppDismissTimer?.cancel();
                    openSessionFromNotification(ref, inApp.sessionId);
                    ref.read(inAppNotificationProvider.notifier).state = null;
                  },
                  onDismiss: () {
                    _inAppDismissTimer?.cancel();
                    ref.read(inAppNotificationProvider.notifier).state = null;
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InAppNotificationBanner extends StatelessWidget {
  const _InAppNotificationBanner({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDismiss,
  });

  final InAppNotificationItem item;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final IconData icon;
    final Color iconColor;
    switch (item.type) {
      case InAppNotificationType.turnCompleted:
        icon = CupertinoIcons.checkmark_circle_fill;
        iconColor = statusGreenText.resolveFrom(context);
      case InAppNotificationType.clarificationNeeded:
        icon = CupertinoIcons.question_circle_fill;
        iconColor = CupertinoColors.systemIndigo;
      case InAppNotificationType.sessionError:
        icon = CupertinoIcons.exclamationmark_circle_fill;
        iconColor = statusRedText.resolveFrom(context);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemGroupedBackground,
        ),
        borderRadius: BorderRadius.circular(10),
        border: isLight
            ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
            : null,
        // 装饰性阴影保留原样，无需为浅色添加额外阴影
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.systemGrey.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  if (item.message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          dark: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              // ignore: deprecated_member_use
              minSize: 28,
              onPressed: onDismiss,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 18,
                color: isLight
                    ? LightSurfaces.textSecondary
                    : const Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
