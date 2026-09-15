import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
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
import 'workmanager_registration_probe.dart';

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

/// 读取底层保活服务的 wmReady 状态（非侵入式判定）。
///
/// 仅有的两个实现（生产 / Fake）都暴露 `wmReady`，用 `is` 判定即可；
/// 未知实现按「未就绪」处理——Android 上宁可如实报未就绪，也不谎报就绪
/// （这正是 #113 要修的病根：静态绿勾）。故不做动态读取兜底。
bool _resolveWmReady(BackgroundKeepaliveService service) {
  if (service is ProductionBackgroundKeepaliveService) {
    return service.wmReady;
  }
  if (service is FakeBackgroundKeepaliveService) {
    return service.wmReady;
  }
  return false;
}

/// 测试注入用的目标平台覆盖 Provider（null 表示使用系统真实 defaultTargetPlatform）。
final workManagerTargetPlatformProvider =
    Provider<TargetPlatform?>((ref) => null);

/// 判定当前是否为 Android 平台（优先读取 [workManagerTargetPlatformProvider] 覆盖）。
bool isWorkManagerAndroidPlatform(Ref ref) {
  final override = ref.watch(workManagerTargetPlatformProvider);
  if (override != null) {
    return override == TargetPlatform.android;
  }
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

/// WorkManager 原生注册探针 Provider（#110/#113 测试可注入或直接替换单例）。
final workManagerRegistrationProbeProvider =
    Provider<WorkManagerRegistrationProbe>((ref) {
  return WorkManagerRegistrationProbe.instance;
});

/// WorkManager 状态三态枚举（#113）。
enum WorkManagerStatusKind {
  /// 就绪（Android 且 wmReady == true）
  ready,

  /// 未就绪（Android 且 wmReady == false）
  notReady,

  /// 不适用（非 Android 平台）
  notApplicable,
}

/// WorkManager 状态只读模型（#113）。
class WorkManagerStatus {
  const WorkManagerStatus({
    required this.kind,
    this.failureReason,
  });

  /// 状态三态类型。
  final WorkManagerStatusKind kind;

  /// 失败归因文本（仅 notReady 态且探针返回后有值）。
  final String? failureReason;

  /// 是否就绪。
  bool get isReady => kind == WorkManagerStatusKind.ready;

  /// 是否未就绪。
  bool get isNotReady => kind == WorkManagerStatusKind.notReady;

  /// 是否不适用。
  bool get isNotApplicable => kind == WorkManagerStatusKind.notApplicable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkManagerStatus &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          failureReason == other.failureReason;

  @override
  int get hashCode => Object.hash(kind, failureReason);

  @override
  String toString() =>
      'WorkManagerStatus(kind: $kind, failureReason: $failureReason)';
}

/// WorkManager 状态控制器（#113 只读派生状态）。
class WorkManagerStatusController extends Notifier<WorkManagerStatus> {
  @override
  WorkManagerStatus build() {
    final service = ref.watch(backgroundKeepaliveServiceProvider);
    final isAndroid = isWorkManagerAndroidPlatform(ref);
    if (!isAndroid) {
      return const WorkManagerStatus(
        kind: WorkManagerStatusKind.notApplicable,
      );
    }

    final isReady = _resolveWmReady(service);
    if (isReady) {
      return const WorkManagerStatus(
        kind: WorkManagerStatusKind.ready,
      );
    }

    // Android 且 wmReady == false：初始状态即为 notReady，异步拉取 probe 归因
    unawaited(_loadAttribution());
    return const WorkManagerStatus(
      kind: WorkManagerStatusKind.notReady,
    );
  }

  Future<void> _loadAttribution() async {
    final probe = ref.read(workManagerRegistrationProbeProvider);
    try {
      final snapshot = await probe.probe();
      state = WorkManagerStatus(
        kind: WorkManagerStatusKind.notReady,
        failureReason: snapshot.describe(),
      );
    } catch (e) {
      state = WorkManagerStatus(
        kind: WorkManagerStatusKind.notReady,
        failureReason: e.toString(),
      );
    }
  }
}

/// WorkManager 只读状态 Provider（#113）。
final workManagerStatusProvider =
    NotifierProvider<WorkManagerStatusController, WorkManagerStatus>(
      WorkManagerStatusController.new,
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
    // #129 撤除 #105 遗留的实况通知兜底 cancel：该调用在开关判定之前无条件撤岛，
    // 而 #120 之后岛改由**回合实时事件驱动**——chat 侧 `_reportTurnSettled` 已在
    // 同一收尾点上报「已完成 / 已中断」（停留 15s 后自行撤岛），此处再撤一次
    // 属于对打死。收尾撤岛的唯一责任方是 chat 事件驱动（另见后台兜底
    // `_cancelLiveUpdateNotification` 与列表归零 `sync(activeCount: 0)`）。

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
        // #129 撤除 #105 遗留的无条件 cancel：澄清是「等主人行动」的报警态，
        // chat 侧 `_applyClarificationUpdate` 刚上报 waitingReply（让其抢占上岛），
        // 本 hook 随即撤岛会把等待态抹掉（且 `cancelAll` 只清服务侧 `_activity`，
        // chat 侧去重表无人重置 → 后续轮询重建卡片也被去重跳过，岛再也回不来）。
        // 撤岛责任归 chat 事件驱动，见 turnNotificationHookProvider 同段落注释。

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

/// 回合实时活动 → 实况通知（灵动岛）hook（#120）。
///
/// chat_controller 在 SSE 事件分派点（推理/工具/输出/等待态）与生命周期变化点
/// 调用；活动变化即刻刷新通知正文与状态栏 chip，退后台时**强制**再上报一次，
/// 使岛在后台立刻出现（修复「退后台延迟上岛」）。收到
/// [ChatLiveActivity.finished] 时撤销。
///
/// LIVE 是增强功能：异常在 service 内部已静默吞掉，这里再兜一层，绝不影响
/// 回合主流程。
final chatLiveActivityHookProvider =
    Provider<ChatLiveActivityCallback>((ref) {
      return (sessionId, title, activity, detail) {
        final mapped = switch (activity) {
          ChatLiveActivity.thinking => LiveUpdateActivity.thinking,
          ChatLiveActivity.tool => LiveUpdateActivity.tool,
          ChatLiveActivity.output => LiveUpdateActivity.output,
          ChatLiveActivity.waitingReply => LiveUpdateActivity.waitingReply,
          ChatLiveActivity.waitingApproval => LiveUpdateActivity.waitingApproval,
          // #129 完成 / 中断态：上岛停留（chat 侧 15s）后再由 finished 撤销。
          ChatLiveActivity.completed => LiveUpdateActivity.completed,
          ChatLiveActivity.interrupted => LiveUpdateActivity.interrupted,
          // finished → null：收尾撤销。
          ChatLiveActivity.finished => null,
        };
        unawaited(
          LiveUpdateService.instance
              .notifyActivity(
                sessionId: sessionId,
                title: title,
                activity: mapped,
                detail: detail,
              )
              .catchError((Object _) {}),
        );
      };
    });
