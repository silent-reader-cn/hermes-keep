import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/locale/locale_resolver.dart';
import '../../app/router.dart';
import '../../l10n/app_localizations.dart';
import '../chat/chat_providers.dart';
import '../desktop/window_title_service.dart';
import 'background_keepalive_service.dart';
import 'live_update_service.dart';
import 'turn_notification_service.dart';

/// App 生命周期状态（生产由 [NotificationLifecycleObserver] 驱动；测试可
/// 直接调用 notifier.setState 或 override 注入）。
final appLifecycleStateProvider =
    NotifierProvider<AppLifecycleNotifier, AppLifecycleState>(
      AppLifecycleNotifier.new,
    );

/// 生命周期跟踪：默认前台（resumed）——观察器未挂载时 hook 保守不发通知。
class AppLifecycleNotifier extends Notifier<AppLifecycleState> {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  /// 更新生命周期状态（相同值不重复通知）。
  void setState(AppLifecycleState state) {
    if (state == this.state) return;
    this.state = state;
  }
}

/// 通知设置状态。
class NotificationSettings {
  const NotificationSettings({
    this.notifyTurnsEnabled = true,
    this.notifyClarifyEnabled = true,
    this.notifyErrorsEnabled = true,
    this.bgForegroundServiceEnabled = false,
    this.bgLiveUpdateEnabled = true,
    this.error,
  });

  final bool notifyTurnsEnabled;
  final bool notifyClarifyEnabled;
  final bool notifyErrorsEnabled;
  final bool bgForegroundServiceEnabled;

  /// 安卓 16 实况通知（灵动岛/状态栏 chip）开关，默认开（渐进增强，
  /// 低版本自动无感；关=回退到仅保活常驻通知的现状）。
  final bool bgLiveUpdateEnabled;
  final String? error;

  String? get keepaliveError => error;

  static const Object _sentinel = Object();

  NotificationSettings copyWith({
    bool? notifyTurnsEnabled,
    bool? notifyClarifyEnabled,
    bool? notifyErrorsEnabled,
    bool? bgForegroundServiceEnabled,
    bool? bgLiveUpdateEnabled,
    Object? error = _sentinel,
  }) {
    return NotificationSettings(
      notifyTurnsEnabled: notifyTurnsEnabled ?? this.notifyTurnsEnabled,
      notifyClarifyEnabled: notifyClarifyEnabled ?? this.notifyClarifyEnabled,
      notifyErrorsEnabled: notifyErrorsEnabled ?? this.notifyErrorsEnabled,
      bgForegroundServiceEnabled:
          bgForegroundServiceEnabled ?? this.bgForegroundServiceEnabled,
      bgLiveUpdateEnabled: bgLiveUpdateEnabled ?? this.bgLiveUpdateEnabled,
      error: error == _sentinel ? this.error : (error as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationSettings &&
          runtimeType == other.runtimeType &&
          notifyTurnsEnabled == other.notifyTurnsEnabled &&
          notifyClarifyEnabled == other.notifyClarifyEnabled &&
          notifyErrorsEnabled == other.notifyErrorsEnabled &&
          bgForegroundServiceEnabled == other.bgForegroundServiceEnabled &&
          bgLiveUpdateEnabled == other.bgLiveUpdateEnabled &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
    notifyTurnsEnabled,
    notifyClarifyEnabled,
    notifyErrorsEnabled,
    bgForegroundServiceEnabled,
    bgLiveUpdateEnabled,
    error,
  );
}

class NotificationSettingsNotifier extends Notifier<NotificationSettings> {
  static const keyTurns = 'notify_turns_enabled';
  static const keyClarify = 'notify_clarify_enabled';
  static const keyErrors = 'notify_errors_enabled';
  static const keyBgForegroundService = 'bg_foreground_service_enabled';
  static const keyBgLiveUpdate = LiveUpdateService.prefsKeyLiveUpdateEnabled;

  bool _loaded = false;

  @override
  NotificationSettings build() {
    _loaded = false;
    unawaited(_loadFromPrefs());
    return const NotificationSettings();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_loaded) return;
      _loaded = true;
      state = NotificationSettings(
        notifyTurnsEnabled: prefs.getBool(keyTurns) ?? state.notifyTurnsEnabled,
        notifyClarifyEnabled:
            prefs.getBool(keyClarify) ?? state.notifyClarifyEnabled,
        notifyErrorsEnabled:
            prefs.getBool(keyErrors) ?? state.notifyErrorsEnabled,
        bgForegroundServiceEnabled:
            prefs.getBool(keyBgForegroundService) ??
            state.bgForegroundServiceEnabled,
        bgLiveUpdateEnabled:
            prefs.getBool(keyBgLiveUpdate) ?? state.bgLiveUpdateEnabled,
      );
    } catch (e) {
      developer.log('Failed to load notification settings from prefs: $e');
    }
  }

  Future<void> setNotifyTurnsEnabled(bool value) async {
    _loaded = true;
    state = state.copyWith(notifyTurnsEnabled: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyTurns, value);
    } catch (e) {
      developer.log('Failed to save notify turns to prefs: $e');
    }
  }

  Future<void> setNotifyClarifyEnabled(bool value) async {
    _loaded = true;
    state = state.copyWith(notifyClarifyEnabled: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyClarify, value);
    } catch (e) {
      developer.log('Failed to save notify clarify to prefs: $e');
    }
  }

  Future<void> setNotifyErrorsEnabled(bool value) async {
    _loaded = true;
    state = state.copyWith(notifyErrorsEnabled: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyErrors, value);
    } catch (e) {
      developer.log('Failed to save notify errors to prefs: $e');
    }
  }

  Future<void> setBgForegroundServiceEnabled(bool value) async {
    _loaded = true;
    state = state.copyWith(
      bgForegroundServiceEnabled: value,
      error: null,
    );

    try {
      final keepalive = ref.read(backgroundKeepaliveServiceProvider);
      if (value) {
        await keepalive.startForegroundService(
          callback: foregroundTaskCallback,
        );
      } else {
        await keepalive.stopForegroundService(force: true);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyBgForegroundService, value);
    } catch (e, st) {
      developer.log(
        'setBgForegroundServiceEnabled error: $e',
        error: e,
        stackTrace: st,
      );
      // 回滚到操作前态：开失败→false；关失败（stop rethrow）→true，
      // 绝不假成功也不假失败。
      final rollback = !value;
      state = state.copyWith(
        bgForegroundServiceEnabled: rollback,
        error: e.toString(),
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(keyBgForegroundService, rollback);
      } catch (prefsErr) {
        developer.log('Failed to persist rollback state: $prefsErr');
      }
    }
  }

  /// 切换安卓 16 实况通知开关（#105）。
  ///
  /// 纯本地增强开关，无跨进程副作用，写入即生效（LiveUpdateService.sync 每次
  /// 读 prefs 为唯一真相）；关闭时额外撤销当前已展示的实况通知，避免残留。
  Future<void> setBgLiveUpdateEnabled(bool value) async {
    _loaded = true;
    state = state.copyWith(bgLiveUpdateEnabled: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyBgLiveUpdate, value);
    } catch (e) {
      developer.log('Failed to save live update switch to prefs: $e');
    }
    if (!value) {
      unawaited(
        LiveUpdateService.instance.cancelAll().catchError((Object _) {}),
      );
    }
  }
}

/// 通知设置 Provider。
final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      NotificationSettingsNotifier.new,
    );

/// 通知权限是否已授予（Android 13+ 需 POST_NOTIFICATIONS；
/// 升级安装场景系统保留旧状态且不再弹窗，用于设置页状态提示引导）。
final notificationPermissionProvider = FutureProvider<bool>((ref) {
  return ref.watch(turnNotificationServiceProvider).areNotificationsEnabled();
});

/// 后台保活服务 Provider（生产 [BackgroundKeepaliveService.instance]；测试可 override）。
final backgroundKeepaliveServiceProvider = Provider<BackgroundKeepaliveService>(
  (ref) {
    return BackgroundKeepaliveService.instance;
  },
);

/// 全局路由 Provider 别名（对齐 goRouterProvider 契约命名）。
final goRouterProvider = routerProvider;

/// 当前激活会话 ID（从 activeSessionIdProvider 读）。
String? getActiveSessionId(dynamic ref) {
  try {
    return ref.read(activeSessionIdProvider);
  } catch (e) {
    developer.log('getActiveSessionId error: $e');
    return null;
  }
}

/// 当前路由是否为指定会话的聊天页（`/chat/:sessionId`）。
bool isCurrentChatRoute(dynamic ref, String sessionId) {
  if (sessionId.isEmpty) return false;
  try {
    final router = ref.read(routerProvider);
    final config = router.routerDelegate.currentConfiguration;
    final Uri uri;
    if (config.isEmpty) {
      uri = router.routeInformationProvider.value.uri;
    } else {
      uri = config.uri;
    }
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'chat') {
      return segments[1] == sessionId;
    }
    final matches = config.matches;
    if (matches.isNotEmpty) {
      final matchedLocation = config.last.matchedLocation;
      if (matchedLocation == '/chat/$sessionId' ||
          matchedLocation.startsWith('/chat/$sessionId?')) {
        return true;
      }
    }
    return false;
  } catch (e) {
    developer.log('isCurrentChatRoute error: $e');
    return false;
  }
}

/// 判断是否应静默本条通知（#94 免打扰双条件判定，原为应用内横幅设计，
/// 现同等适用于系统通知）。
///
/// 双条件约束：
/// 1. 当前激活会话匹配目标会话（[getActiveSessionId] == [sessionId]）；
/// 2. 当前路由即该会话聊天页（[isCurrentChatRoute] 为 true）。
/// 两者同时满足时静默——主人正在看这个会话本体，答案/澄清弹窗就在眼前，
/// 通知纯属噪音且会遮挡顶层交互。
bool shouldSilenceNotification(dynamic ref, String sessionId) {
  if (sessionId.isEmpty) return false;
  final active = getActiveSessionId(ref);
  if (active != sessionId) {
    return false;
  }
  return isCurrentChatRoute(ref, sessionId);
}

/// 回合/澄清/错误/下载通知服务（生产 [LocalNotificationsTurnNotificationService]；
/// 测试可 override 注入 fake）。
final turnNotificationServiceProvider = Provider<TurnNotificationService>((
  ref,
) {
  return LocalNotificationsTurnNotificationService(
    onTap: (payload) => handleNotificationTap(ref, payload),
  );
});

/// 处理通知点击（根据 payload 前缀分发路由：`download:<id>` 或 sessionId）。
void handleNotificationTap(dynamic ref, String payload) {
  if (payload.isEmpty) return;
  if (payload.startsWith('download:')) {
    ref.read(routerProvider).go('/downloads');
    return;
  }
  openSessionFromNotification(ref, payload);
}

/// 通知点击 → 跳转对应会话（go_router；无激活连接时守卫自动重定向）。
void openSessionFromNotification(dynamic ref, String sessionId) {
  if (sessionId.isEmpty) return;
  ref.read(routerProvider).go('/chat/$sessionId');
}

/// chat 收尾 hook：chat_controller 在 done / stream_end 成功收尾处调用。
///
/// 触发时机（应用内横幅已移除，全平台统一走系统通知）：
/// - 开关关闭：不发通知
/// - 免打扰双条件命中（前台 + 正停留在该会话聊天页）：不发，并清残留
/// - 其余场景（前台跨会话 / 后台）：发系统通知
final turnNotificationHookProvider = Provider<ChatTurnCompletedCallback>((ref) {
  final service = ref.watch(turnNotificationServiceProvider);
  final keepalive = ref.watch(backgroundKeepaliveServiceProvider);
  return (sessionId, title, preview) {
    unawaited(
      keepalive.recordTurnNotified(sessionId: sessionId, streamId: null),
    );
    unawaited(keepalive
          .stopForegroundService()
          // 停止失败仅诊断日志（K 修复规格：仅开关路径需回滚，见
          // setBgForegroundServiceEnabled）；fire-and-forget 调用自吞。
          .catchError((Object _) {}));
    unawaited(keepalive.cancelOneOffPoll(sessionId));
    // #105 实况通知兜底 cancel：窄屏聊天页期间会话列表未挂载，sync(0) 回调
    // 要等返回列表才触发——完成态即撤 LIVE，与 stopForegroundService 同步收口。
    unawaited(
      LiveUpdateService.instance.cancelAll().catchError((Object _) {}),
    );

    final settings = ref.read(notificationSettingsProvider);
    if (!settings.notifyTurnsEnabled) return;
    // 免打扰双条件命中（正在看这个会话本体）：不发通知并清残留。
    if (shouldSilenceNotification(ref, sessionId)) {
      unawaited(service.clearAll());
      return;
    }
    unawaited(
      service.notifyTurnCompleted(
        sessionId,
        title.isNotEmpty
            ? title
            : AppLocalizations(LocaleResolver.resolve()).notifTurnCompleted,
        preview,
      ),
    );
  };
});

/// chat 澄清请求 hook：chat_controller 在收到 clarify 事件时调用。
final clarificationNotificationHookProvider =
    Provider<ChatClarificationNeededCallback>((ref) {
      final service = ref.watch(turnNotificationServiceProvider);
      final keepalive = ref.watch(backgroundKeepaliveServiceProvider);
      return (sessionId, question) {
        unawaited(
          keepalive.recordTurnNotified(sessionId: sessionId, streamId: null),
        );
        unawaited(keepalive
          .stopForegroundService()
          // 停止失败仅诊断日志（K 修复规格：仅开关路径需回滚，见
          // setBgForegroundServiceEnabled）；fire-and-forget 调用自吞。
          .catchError((Object _) {}));
        unawaited(keepalive.cancelOneOffPoll(sessionId));
        // #105 实况通知兜底 cancel（同回合完成 hook，窄屏 sync(0) 滞后）。
        unawaited(
          LiveUpdateService.instance.cancelAll().catchError((Object _) {}),
        );

        final settings = ref.read(notificationSettingsProvider);
        if (!settings.notifyClarifyEnabled) return;
        // 免打扰双条件命中（正在看这个会话本体，澄清弹窗就在眼前）：不发。
        if (shouldSilenceNotification(ref, sessionId)) {
          unawaited(service.clearAll());
          return;
        }
        unawaited(service.notifyClarificationNeeded(sessionId, question));
      };
    });

/// chat 会话异常 hook：chat_controller 在 cancel / error / 重连失败时调用。
final sessionErrorNotificationHookProvider = Provider<ChatSessionErrorCallback>(
  (ref) {
    final service = ref.watch(turnNotificationServiceProvider);
    final keepalive = ref.watch(backgroundKeepaliveServiceProvider);
    return (sessionId, title, preview) {
      unawaited(
        keepalive.recordTurnNotified(sessionId: sessionId, streamId: null),
      );
      unawaited(keepalive
          .stopForegroundService()
          // 停止失败仅诊断日志（K 修复规格：仅开关路径需回滚，见
          // setBgForegroundServiceEnabled）；fire-and-forget 调用自吞。
          .catchError((Object _) {}));
      unawaited(keepalive.cancelOneOffPoll(sessionId));

      final settings = ref.read(notificationSettingsProvider);
      if (!settings.notifyErrorsEnabled) return;
      // 免打扰双条件命中（正在看这个会话本体）：不发。
      if (shouldSilenceNotification(ref, sessionId)) {
        unawaited(service.clearAll());
        return;
      }
      unawaited(service.notifySessionError(sessionId, title, preview));
    };
  },
);
