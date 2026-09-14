import 'dart:async';
import 'dart:developer' as developer;

import 'package:android_intent_plus/android_intent.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../diagnostics/diagnostics_models.dart';
import '../diagnostics/diagnostics_service.dart';
import 'live_update_service.dart';
import 'turn_notification_service.dart';
import 'workmanager_registration_probe.dart';

/// HyperOS / Android 系统保活与权限跳转类型。
enum HyperOsSettingType {
  /// 自启动管理（小米安全中心 / 标准应用详情）
  autoStart,

  /// 省电策略（无限制 / 电池优化）
  batteryOptimization,

  /// 联网控制（WLAN / 移动数据）
  networkControl,

  /// 系统通知设置
  notificationSettings,
}

/// 后台保活服务接口（抽象接口，便于单元测试与平台解耦）。
abstract interface class BackgroundKeepaliveService {
  /// 单例实例访问（默认指向生产单例或测试注入实例）。
  static BackgroundKeepaliveService instance =
      ProductionBackgroundKeepaliveService();

  /// 冷启动初始化（注册 WorkManager 与 ForegroundTask 配置）。
  Future<void> initialize();

  /// App 生命周期变更联动（仅上报流状态用于文本更新与 WorkManager 加急任务调度，不停止常驻前台服务）。
  Future<void> onAppLifecycleChanged({
    required AppLifecycleState state,
    required String? activeSessionId,
    required String? activeStreamId,
    required bool isStreaming,
    required bool foregroundServiceEnabled,
  });

  /// 启动前台服务（持 WakeLock 保活网络，常驻通知显示进行中会话数）。
  Future<void> startForegroundService({
    String sessionId = '',
    String? streamId,
    int? activeCount,
    Function? callback,
  });

  /// 停止前台服务（force 为 true 时无条件停止；force 为 false 且开关开启时仅刷新通知文本为 0）。
  Future<void> stopForegroundService({bool force = false});

  /// 更新常驻通知文本（会话数动态文本）。
  Future<void> updateNotification({int activeCount = 0});

  /// 幂等同步常驻保活通知（若文案无变化则不触发底层服务更新，避免 Android notify 抖动）。
  Future<void> syncOngoingNotification(
    int activeCount, [
    List<String>? titles,
  ]);

  /// 调度 WorkManager 加急/退避单次轮询任务。
  Future<void> scheduleExpeditedOneOffPoll({
    required String sessionId,
    required String? streamId,
  });

  /// 取消指定会话的单次轮询任务。
  Future<void> cancelOneOffPoll(String sessionId);

  /// 标记某回合已由前台或后台发送过通知（去重）。
  Future<void> recordTurnNotified({
    required String sessionId,
    required String? streamId,
  });

  /// 检查某回合是否已发送过通知。
  Future<bool> isTurnAlreadyNotified({
    required String sessionId,
    required String? streamId,
  });

  /// 打开系统/HyperOS 引导设置页。
  Future<void> openHyperOsSetting(HyperOsSettingType type);

  /// WorkManager 任务处理静态入口。
  static Future<bool> handleWorkManagerTask(
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    return await ProductionBackgroundKeepaliveService.handleTask(
      taskName,
      inputData,
    );
  }
}

/// WorkManager 顶层回调分发器（必须为 top-level 或 static 函数并标 @pragma('vm:entry-point')）。
@pragma('vm:entry-point')
void workmanagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    return await BackgroundKeepaliveService.handleWorkManagerTask(
      taskName,
      inputData,
    );
  });
}

/// 前台任务顶层回调入口（由 flutter_foreground_task 在前台任务 Isolate 执行）。
@pragma('vm:entry-point')
void foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(HermesKeepaliveTaskHandler());
}

/// Hermes 前台保活服务任务处理器（实现 TaskHandler 契约）。
class HermesKeepaliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    developer.log(
      'HermesKeepaliveTaskHandler onStart: $timestamp, starter: $starter',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    developer.log('HermesKeepaliveTaskHandler onRepeatEvent: $timestamp');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    developer.log('HermesKeepaliveTaskHandler onDestroy: $timestamp');
  }

  /// 别名/诊断回调（对齐规格说明）。
  void onStop() {
    developer.log('HermesKeepaliveTaskHandler onStop');
  }
}

/// [FlutterForegroundTask] 静态 API 的包装抽象，便于测试注入与 Mock。
class ForegroundTaskWrapper {
  const ForegroundTaskWrapper();

  /// 初始化前台任务配置。
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {
    FlutterForegroundTask.init(
      androidNotificationOptions: androidNotificationOptions,
      iosNotificationOptions: iosNotificationOptions,
      foregroundTaskOptions: foregroundTaskOptions,
    );
  }

  /// 检查前台服务是否正在运行。
  Future<bool> get isRunningService => FlutterForegroundTask.isRunningService;

  /// 启动前台服务。
  Future<ServiceRequestResult> startService({
    required String notificationTitle,
    required String notificationText,
    Function? callback,
  }) {
    return FlutterForegroundTask.startService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      callback: callback,
    );
  }

  /// 更新前台服务通知。
  Future<ServiceRequestResult> updateService({
    required String notificationTitle,
    required String notificationText,
  }) {
    return FlutterForegroundTask.updateService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
  }

  /// 停止前台服务。
  Future<ServiceRequestResult> stopService() {
    return FlutterForegroundTask.stopService();
  }
}

/// 生产级后台保活实现（基于 WorkManager + flutter_foreground_task + android_intent_plus）。
class ProductionBackgroundKeepaliveService
    implements BackgroundKeepaliveService {
  ProductionBackgroundKeepaliveService({
    Workmanager? workmanager,
    ForegroundTaskWrapper? foregroundTaskWrapper,
    WorkManagerRegistrationProbe? registrationProbe,
  })  : _workmanager = workmanager ?? Workmanager(),
        _foregroundTaskWrapper =
            foregroundTaskWrapper ?? const ForegroundTaskWrapper(),
        _registrationProbe =
            registrationProbe ?? WorkManagerRegistrationProbe.instance;

  final Workmanager _workmanager;
  final ForegroundTaskWrapper _foregroundTaskWrapper;

  /// 原生注册探针（#110；仅 WorkManager 初始化失败归因时使用）。
  final WorkManagerRegistrationProbe _registrationProbe;

  static const String periodicTaskTag = 'hermes-bg-poll';
  static const String periodicTaskUniqueName = 'hermes-bg-poll-periodic';
  static const String periodicTaskName = 'hermes.bg.poll.periodic';

  static const String oneOffTaskTag = 'hermes-bg-oneoff';
  static const String oneOffTaskName = 'hermes.bg.poll.oneoff';

  static const String keyActiveBaseUrl = 'bg_active_base_url';
  static const String keyActiveSessionId = 'bg_active_session_id';
  static const String keyActiveStreamId = 'bg_active_stream_id';
  static const String keyIsStreaming = 'bg_is_streaming';
  static const String keyLastNotifiedStreamPrefix = 'bg_last_notified_stream_';
  static const String keyLastNotifiedSessionPrefix = 'bg_last_notified_session_';

  Object? _localeListenerToken;

  bool _fgTaskReady = false;
  bool _workmanagerReady = false;
  String? _lastOngoingText;

  /// 语言切换时刷新常驻通知（读流状态重算 activeCount，非运行时静默跳过）。
  Future<void> _refreshNotificationForLocale() async {
    if (!_isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('bg_foreground_service_enabled') ?? false;
      if (!enabled) return;
      final isStreaming = prefs.getBool(keyIsStreaming) ?? false;
      final activeStreamId = prefs.getString(keyActiveStreamId);
      final activeCount =
          (isStreaming || (activeStreamId != null && activeStreamId.isNotEmpty))
              ? 1
              : 0;
      _lastOngoingText = null;
      await updateNotification(activeCount: activeCount);
    } catch (e, st) {
      developer.log(
        '_refreshNotificationForLocale error: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// ForegroundTask 是否已初始化就绪。
  bool get fgTaskReady => _fgTaskReady;

  /// WorkManager 是否已初始化并注册周期任务。
  bool get wmReady => _workmanagerReady;

  /// 全部关键步骤是否就绪。
  bool get isInitialized => _fgTaskReady && _workmanagerReady;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 格式化常驻通知文本（「N 个会话正在生成」/「暂无进行中会话」）。
  static String formatNotificationText(int count, {bool isEnglish = false}) {
    if (count > 0) {
      return isEnglish
          ? '$count session${count == 1 ? '' : 's'} generating'
          : '$count 个会话正在生成';
    }
    return isEnglish ? 'No active sessions' : '暂无进行中会话';
  }

  @override
  Future<void> initialize() async {
    if (!_isAndroid) return;
    if (_fgTaskReady && _workmanagerReady) return;

    // 1. 首先初始化 Foreground Task（纯内存静态配置，无外部依赖，防 WorkManager 阻断）
    if (!_fgTaskReady) {
      try {
        _foregroundTaskWrapper.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'hermes_foreground_service',
            channelName: '后台生成保活',
            channelDescription: '后台流式生成进行中常驻通知',
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW,
            enableVibration: false,
            playSound: false,
            showWhen: false,
            visibility: NotificationVisibility.VISIBILITY_PUBLIC,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: false,
            playSound: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            autoRunOnBoot: false,
            autoRunOnMyPackageReplaced: false,
            allowWakeLock: true,
            allowWifiLock: true,
          ),
        );
        _fgTaskReady = true;
        // L2：语言模式变化 -> 按当前流状态重算并刷新常驻通知文案。
        _localeListenerToken ??= LocaleResolver.addListener(() {
          unawaited(_refreshNotificationForLocale());
        });
      } catch (e, st) {
        developer.log(
          'FlutterForegroundTask.init 失败: $e',
          error: e,
          stackTrace: st,
        );
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.error,
          tag: 'keepalive',
          message: 'ForegroundTask 初始化失败',
          errorKind: e.toString(),
        );
      }
    }

    // 2. 初始化 WorkManager 与周期性轮询（15min 系统最小周期，约束：联网）
    if (!_workmanagerReady) {
      try {
        await _workmanager.initialize(
          workmanagerCallbackDispatcher,
        );

        await _workmanager.registerPeriodicTask(
          periodicTaskUniqueName,
          periodicTaskName,
          tag: periodicTaskTag,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(
            networkType: NetworkType.connected,
          ),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: const Duration(seconds: 30),
        );
        _workmanagerReady = true;
      } catch (e, st) {
        developer.log(
          'WorkManager 初始化失败: $e',
          error: e,
          stackTrace: st,
        );
        // #110：channel-error 说明原生插件注册期就抛了异常，补一次原生探针
        // 取证，把「为什么通道没绑定」直接落进诊断日志（无需 adb 即可判定
        // 是 WorkManager 自身初始化失败，还是插件从未附着）。
        final attribution = await describeWorkManagerInitFailure(e);
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.error,
          tag: 'keepalive',
          message: 'WorkManager 初始化失败$attribution',
          errorKind: e.toString(),
        );
      }
    }

    // 3. 记录诊断状态
    if (_fgTaskReady && _workmanagerReady) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'keepalive',
        message: '后台保活服务初始化成功（WorkManager + ForegroundTask）',
      );
    } else if (_fgTaskReady) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.warn,
        tag: 'keepalive',
        message: '后台保活服务部分就绪（ForegroundTask 就绪，WorkManager 失败）',
      );
    }

    // 4. 若保活开关已开启且 ForegroundTask 已就绪，冷启动直启常驻服务
    if (_fgTaskReady) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final enabled = prefs.getBool('bg_foreground_service_enabled') ?? false;
        if (enabled) {
          final isStreaming = prefs.getBool(keyIsStreaming) ?? false;
          final activeStreamId = prefs.getString(keyActiveStreamId);
          final hasActive =
              isStreaming ||
              (activeStreamId != null && activeStreamId.isNotEmpty);
          await startForegroundService(
            activeCount: hasActive ? 1 : 0,
            callback: foregroundTaskCallback,
          );
        }
      } catch (e, st) {
        developer.log(
          '冷启动拉起前台服务失败: $e',
          error: e,
          stackTrace: st,
        );
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.error,
          tag: 'keepalive',
          message: '冷启动拉起前台服务失败',
          errorKind: e.toString(),
        );
      }
    }
  }

  /// channel-error 归因增强（#110）：返回可直接拼进诊断日志的补充说明。
  ///
  /// 仅当失败是 pigeon `channel-error`（通道未绑定 = 原生插件注册期已抛异常）
  /// 时才调用原生探针；其余失败（约束非法、配额等）返回空串。
  ///
  /// 注意：通道在引擎 attach 时绑定，失败后同进程内**不会**恢复——Dart 侧重试
  /// `initialize()` 无法自愈，这里只做归因，不做假修复。
  @visibleForTesting
  Future<String> describeWorkManagerInitFailure(Object error) async {
    final isChannelError =
        error is PlatformException && error.code == 'channel-error';
    if (!isChannelError) return '';
    try {
      final snapshot = await _registrationProbe.probe();
      return '（channel-error：原生插件注册未绑定，探针 ${snapshot.describe()}）';
    } on Object {
      return '（channel-error：原生插件注册未绑定，探针不可用）';
    }
  }

  @override
  Future<void> onAppLifecycleChanged({
    required AppLifecycleState state,
    required String? activeSessionId,
    required String? activeStreamId,
    required bool isStreaming,
    required bool foregroundServiceEnabled,
  }) async {
    if (!_isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyActiveSessionId, activeSessionId ?? '');
      await prefs.setString(keyActiveStreamId, activeStreamId ?? '');
      await prefs.setBool(keyIsStreaming, isStreaming);

      // 流状态即时更新通知文本（0 ↔ 1）
      final activeCount =
          (isStreaming ||
                  (activeStreamId != null && activeStreamId.isNotEmpty))
              ? 1
              : 0;
      if (foregroundServiceEnabled) {
        final isRunning = await _foregroundTaskWrapper.isRunningService;
        if (isRunning) {
          await updateNotification(activeCount: activeCount);
        } else {
          await startForegroundService(
            sessionId: activeSessionId ?? '',
            streamId: activeStreamId,
            activeCount: activeCount,
            callback: foregroundTaskCallback,
          );
        }
      }

      if (state == AppLifecycleState.resumed) {
        // 回到前台：取消加急轮询（常驻服务不停止）
        if (activeSessionId != null && activeSessionId.isNotEmpty) {
          await cancelOneOffPoll(activeSessionId);
        }
      } else {
        // 切后台：若正在生成，调度加急轮询兜底
        if (isStreaming ||
            (activeStreamId != null && activeStreamId.isNotEmpty)) {
          if (activeSessionId != null && activeSessionId.isNotEmpty) {
            await scheduleExpeditedOneOffPoll(
              sessionId: activeSessionId,
              streamId: activeStreamId,
            );
          }
        }
      }
    } catch (e, st) {
      developer.log('onAppLifecycleChanged error: $e', error: e, stackTrace: st);
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'keepalive',
        message: '生命周期保活联动失败',
        errorKind: e.toString(),
      );
    }
  }

  @override
  Future<void> startForegroundService({
    String sessionId = '',
    String? streamId,
    int? activeCount,
    Function? callback,
  }) async {
    if (!_isAndroid) return;

    try {
      if (!_fgTaskReady) {
        await initialize();
      }
      if (!_fgTaskReady) {
        throw StateError('ForegroundTask not initialized');
      }
      final count = activeCount ??
          ((streamId != null && streamId.isNotEmpty) ? 1 : 0);
      final text = formatNotificationText(count, isEnglish: LocaleResolver.isEnglish);

      final isRunning = await _foregroundTaskWrapper.isRunningService;
      if (isRunning) {
        final updateResult = await _foregroundTaskWrapper.updateService(
          notificationTitle: 'Hermes',
          notificationText: text,
        );
        if (updateResult is ServiceRequestFailure) {
          throw updateResult.error;
        }
        _lastOngoingText = text;
        return;
      }

      final result = await _foregroundTaskWrapper.startService(
        notificationTitle: 'Hermes',
        notificationText: text,
        callback: callback ?? foregroundTaskCallback,
      );
      if (result is ServiceRequestFailure) {
        throw result.error;
      }
      _lastOngoingText = text;

      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'keepalive',
        message: '启动前台保活服务成功',
        details: {
          'sessionId': sessionId,
          'streamId': streamId,
          'activeCount': count,
        },
      );
    } catch (e, st) {
      developer.log('startForegroundService error: $e', error: e, stackTrace: st);
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'keepalive',
        message: '启动前台保活服务失败',
        errorKind: e.toString(),
      );
      rethrow;
    }
  }

  @override
  Future<void> updateNotification({int activeCount = 0}) async {
    if (!_isAndroid) return;
    try {
      final isRunning = await _foregroundTaskWrapper.isRunningService;
      if (!isRunning) return;
      final text = formatNotificationText(activeCount, isEnglish: LocaleResolver.isEnglish);
      final result = await _foregroundTaskWrapper.updateService(
        notificationTitle: 'Hermes',
        notificationText: text,
      );
      if (result is ServiceRequestFailure) {
        throw result.error;
      }
      _lastOngoingText = text;
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.debug,
        tag: 'keepalive',
        message: '更新前台服务常驻通知文本',
        details: {'activeCount': activeCount, 'text': text},
      );
    } catch (e, st) {
      developer.log('updateNotification error: $e', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> syncOngoingNotification(
    int activeCount, [
    List<String>? titles,
  ]) async {
    if (!_isAndroid) return;
    // #105 安卓 16 实况通知（灵动岛/状态栏 chip）：与常驻保活通知并列的增强
    // 链路。放在「服务未 running 早退」之前——LIVE 通知不依赖保活服务运行；
    // 开关读取、幂等缓存、平台/版本判定与吞错均在 LiveUpdateService 内部。
    unawaited(
      LiveUpdateService.instance
          .sync(activeCount: activeCount, titles: titles ?? const [])
          .catchError((Object _) {}),
    );
    try {
      final isRunning = await _foregroundTaskWrapper.isRunningService;
      if (!isRunning) return;
      final text = formatNotificationText(
        activeCount,
        isEnglish: LocaleResolver.isEnglish,
      );
      if (text == _lastOngoingText) {
        return;
      }
      final result = await _foregroundTaskWrapper.updateService(
        notificationTitle: 'Hermes',
        notificationText: text,
      );
      if (result is ServiceRequestFailure) {
        throw result.error;
      }
      _lastOngoingText = text;
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.debug,
        tag: 'keepalive',
        message: '幂等同步前台服务常驻通知文本',
        details: {
          'activeCount': activeCount,
          'text': text,
          'titles': ?titles,
        },
      );
    } catch (e, st) {
      developer.log('syncOngoingNotification error: $e', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> stopForegroundService({bool force = false}) async {
    if (!_isAndroid) return;
    try {
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final enabled =
            prefs.getBool('bg_foreground_service_enabled') ?? false;
        if (enabled) {
          // 开关仍开启时，通知常驻不消失，仅将文本更新为「暂无进行中会话」
          await updateNotification(activeCount: 0);
          return;
        }
      }

      final isRunning = await _foregroundTaskWrapper.isRunningService;
      if (isRunning) {
        final result = await _foregroundTaskWrapper.stopService();
        if (result is ServiceRequestFailure) {
          throw result.error;
        }
        _lastOngoingText = null;
      }
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'keepalive',
        message: '停止前台保活服务',
      );
    } catch (e, st) {
      developer.log('stopForegroundService error: $e', error: e, stackTrace: st);
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'keepalive',
        message: '停止前台保活服务失败',
        errorKind: e.toString(),
      );
      // 修复规格①「stopForegroundService 同检返回值」：失败向上冒泡，
      // 供 setBgForegroundServiceEnabled 回滚开关；fire-and-forget 调用方
      // （unawaited）自吞不影响主流程。
      rethrow;
    }
  }

  @override
  Future<void> scheduleExpeditedOneOffPoll({
    required String sessionId,
    required String? streamId,
  }) async {
    if (!_isAndroid || sessionId.isEmpty) return;
    try {
      final uniqueName = 'hermes-bg-oneoff-$sessionId';
      await _workmanager.registerOneOffTask(
        uniqueName,
        oneOffTaskName,
        tag: oneOffTaskTag,
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
        outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
        inputData: {
          'sessionId': sessionId,
          'streamId': streamId ?? '',
        },
      );
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'keepalive',
        message: '调度 WorkManager 加急探活任务',
        details: {'sessionId': sessionId, 'streamId': streamId},
      );
    } catch (e) {
      developer.log('scheduleExpeditedOneOffPoll error: $e');
    }
  }

  @override
  Future<void> cancelOneOffPoll(String sessionId) async {
    if (!_isAndroid || sessionId.isEmpty) return;
    try {
      final uniqueName = 'hermes-bg-oneoff-$sessionId';
      await _workmanager.cancelByUniqueName(uniqueName);
    } catch (e) {
      developer.log('cancelOneOffPoll error: $e');
    }
  }

  @override
  Future<void> recordTurnNotified({
    required String sessionId,
    required String? streamId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nowStr = DateTime.now().toIso8601String();
      if (streamId != null && streamId.isNotEmpty) {
        await prefs.setString('$keyLastNotifiedStreamPrefix$streamId', nowStr);
      }
      if (sessionId.isNotEmpty) {
        await prefs.setString(
            '$keyLastNotifiedSessionPrefix$sessionId', nowStr);
      }
    } catch (e) {
      developer.log('recordTurnNotified error: $e');
    }
  }

  @override
  Future<bool> isTurnAlreadyNotified({
    required String sessionId,
    required String? streamId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (streamId != null && streamId.isNotEmpty) {
        final val = prefs.getString('$keyLastNotifiedStreamPrefix$streamId');
        if (val != null && val.isNotEmpty) return true;
      }
      if (sessionId.isNotEmpty) {
        final val = prefs.getString('$keyLastNotifiedSessionPrefix$sessionId');
        if (val != null && val.isNotEmpty) {
          // 30秒内同一会话判定为已通知
          final dt = DateTime.tryParse(val);
          if (dt != null &&
              DateTime.now().difference(dt).inSeconds < 30) {
            return true;
          }
        }
      }
    } catch (e) {
      developer.log('isTurnAlreadyNotified error: $e');
    }
    return false;
  }

  @override
  Future<void> openHyperOsSetting(HyperOsSettingType type) async {
    if (!_isAndroid) return;
    try {
      String? packageName;
      try {
        final pkgInfo = await PackageInfo.fromPlatform();
        packageName = pkgInfo.packageName;
      } catch (e) {
        developer.log('PackageInfo.fromPlatform fallback error: $e');
        packageName = 'com.silentreader.hermes_ui';
      }

      switch (type) {
        case HyperOsSettingType.autoStart:
          await _tryLaunchIntents([
            // 1. 小米安全中心自启动管理
            const AndroidIntent(
              action: 'miui.intent.action.OP_AUTO_START',
              componentName:
                  'com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity',
            ),
            // 2. 小米应用权限管理
            AndroidIntent(
              action: 'miui.intent.action.APP_PERM_EDITOR',
              componentName:
                  'com.miui.securitycenter/com.miui.permcenter.permissions.PermissionsEditorActivity',
              arguments: {'extra_pkgname': packageName},
            ),
            // 3. 通用应用详情
            AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$packageName',
            ),
          ]);
          break;

        case HyperOsSettingType.batteryOptimization:
          await _tryLaunchIntents([
            // 1. 小米省电策略详情
            AndroidIntent(
              componentName:
                  'com.miui.powerkeeper/com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
              arguments: {
                'package_name': packageName,
                'package_label': 'Hermes',
              },
            ),
            // 2. 原生忽略电池优化设置
            const AndroidIntent(
              action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
            ),
            // 3. 通用应用详情
            AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$packageName',
            ),
          ]);
          break;

        case HyperOsSettingType.networkControl:
          await _tryLaunchIntents([
            // 1. 小米网络助手 / 联网控制
            const AndroidIntent(
              componentName:
                  'com.miui.networkassistant/com.miui.networkassistant.ui.NetworkAssistantActivity',
            ),
            // 2. 原生网络设置
            const AndroidIntent(
              action: 'android.settings.WIRELESS_SETTINGS',
            ),
            // 3. 通用应用详情
            AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$packageName',
            ),
          ]);
          break;

        case HyperOsSettingType.notificationSettings:
          await _tryLaunchIntents([
            // 1. 原生应用通知设置 (API 26+)
            AndroidIntent(
              action: 'android.settings.APP_NOTIFICATION_SETTINGS',
              arguments: {
                'android.provider.extra.APP_PACKAGE': packageName,
              },
            ),
            // 2. 通用应用详情
            AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$packageName',
            ),
          ]);
          break;
      }
    } catch (e) {
      developer.log('openHyperOsSetting error: $e');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'keepalive',
        message: '跳转系统设置页异常',
        errorKind: e.toString(),
      );
    }
  }

  Future<void> _tryLaunchIntents(List<AndroidIntent> intents) async {
    for (final intent in intents) {
      try {
        await intent.launch();
        return;
      } catch (e) {
        developer.log('Candidate intent launch failed, trying next: $e');
        // 尝试下一个候选 intent
      }
    }
  }

  /// 静态后台任务执行体（由 WorkManager 在后台 Isolate 调用）。
  static Future<bool> handleTask(
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // L2/L3：后台 Isolate 无法继承主 Isolate 的 LocaleResolver 状态，
      // 从持久化配置恢复语言模式，通知标题/正文按语言本地化。
      final localeRaw = prefs.getString('app_locale_mode');
      for (final m in AppLocaleMode.values) {
        if (m.name == localeRaw) {
          LocaleResolver.updateMode(m);
          break;
        }
      }
      final bgL10n = AppLocalizations(LocaleResolver.resolve());
      final notifyTurns = prefs.getBool('notify_turns_enabled') ?? true;
      final notifyClarify = prefs.getBool('notify_clarify_enabled') ?? true;
      final notifyErrors = prefs.getBool('notify_errors_enabled') ?? true;
      final bgFgsEnabled =
          prefs.getBool('bg_foreground_service_enabled') ?? false;

      final baseUrl = prefs.getString(keyActiveBaseUrl);
      if (baseUrl == null || baseUrl.isEmpty) {
        return true;
      }

      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl.endsWith('/')
              ? baseUrl.substring(0, baseUrl.length - 1)
              : baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/json'},
        ),
      );

      // 0. 后台保活：拉取 /health?deep=1 刷新常驻通知文本
      if (bgFgsEnabled) {
        try {
          final healthRes = await dio.get<Map<String, dynamic>>(
            '/health',
            queryParameters: {'deep': 1},
          );
          final healthData = healthRes.data;
          if (healthData != null && healthData.containsKey('active_streams')) {
            final activeStreams =
                (healthData['active_streams'] as num?)?.toInt() ?? 0;
            final isRunning = await FlutterForegroundTask.isRunningService;
            if (isRunning) {
              final text = formatNotificationText(activeStreams, isEnglish: LocaleResolver.isEnglish);
              await FlutterForegroundTask.updateService(
                notificationTitle: 'Hermes',
                notificationText: text,
              );
            }
          }
        } catch (e) {
          developer.log('WorkManager /health?deep=1 error: $e');
        }
      }

      if (!notifyTurns && !notifyClarify && !notifyErrors) {
        return true;
      }

      final sessionId = (inputData?['sessionId'] as String?) ??
          prefs.getString(keyActiveSessionId) ??
          '';
      final streamId = (inputData?['streamId'] as String?) ??
          prefs.getString(keyActiveStreamId) ??
          '';

      if (sessionId.isEmpty && streamId.isEmpty) {
        return true;
      }

      // 1. 若有 activeStreamId，查 /api/chat/stream/status
      if (streamId.isNotEmpty) {
        try {
          final res = await dio.get<Map<String, dynamic>>(
            '/api/chat/stream/status',
            queryParameters: {'stream_id': streamId},
          );
          final data = res.data;
          if (data != null) {
            final active = data['active'] == true;
            final journal = data['journal'] as Map<String, dynamic>?;
            final terminal = journal?['terminal'] == true;
            final terminalState = journal?['terminal_state']?.toString();

            if (!active || terminal) {
              // 流已在服务端收尾，检查是否已通知
              final alreadyNotified =
                  prefs.getString('$keyLastNotifiedStreamPrefix$streamId') != null;
              if (!alreadyNotified) {
                // 判断完成/澄清/错误类型
                final isError = terminalState == 'error' ||
                    terminalState == 'cancelled' ||
                    terminalState == 'interrupted';
                final isClarify = terminalState == 'clarify' ||
                    terminalState == 'clarification_needed';

                if (isClarify && notifyClarify) {
                  await _showBackgroundNotification(
                    id: LocalNotificationsTurnNotificationService
                        .notificationClarifyId,
                    channelId: LocalNotificationsTurnNotificationService
                        .channelClarifyId,
                    channelName: LocalNotificationsTurnNotificationService
                        .channelClarifyName,
                    channelDesc: LocalNotificationsTurnNotificationService
                        .channelClarifyDescription,
                    title: bgL10n.clarificationNeeded,
                    body: bgL10n.notifClarifyBody,
                    payload: sessionId,
                  );
                } else if (isError && notifyErrors) {
                  await _showBackgroundNotification(
                    id: LocalNotificationsTurnNotificationService
                        .notificationErrorsId,
                    channelId: LocalNotificationsTurnNotificationService
                        .channelErrorsId,
                    channelName: LocalNotificationsTurnNotificationService
                        .channelErrorsName,
                    channelDesc: LocalNotificationsTurnNotificationService
                        .channelErrorsDescription,
                    title: bgL10n.sessionErrorTitle,
                    body: bgL10n.notifErrorBody,
                    payload: sessionId,
                  );
                } else if (notifyTurns) {
                  // 补拉会话最新内容作为预览
                  String preview = bgL10n.notifTurnFallbackBody;
                  try {
                    final sessionRes = await dio.get<Map<String, dynamic>>(
                      '/api/session',
                      queryParameters: {
                        'session_id': sessionId,
                        'messages': 1,
                        'include_messages': true,
                      },
                    );
                    final sessData = sessionRes.data;
                    final sDetail = sessData?['session'] as Map<String, dynamic>? ??
                        sessData;
                    final msgs = sDetail?['messages'] as List?;
                    if (msgs != null && msgs.isNotEmpty) {
                      for (final m in msgs.reversed) {
                        if (m is Map &&
                            m['role'] == 'assistant' &&
                            m['content'] is String &&
                            (m['content'] as String).trim().isNotEmpty) {
                          preview = LocalNotificationsTurnNotificationService
                              .formatPreview(m['content'] as String);
                          break;
                        }
                      }
                    }
                  } catch (e) {
                    developer.log('WorkManager fetch session preview error: $e');
                  }

                  await _showBackgroundNotification(
                    id: LocalNotificationsTurnNotificationService
                        .notificationTurnsId,
                    channelId: LocalNotificationsTurnNotificationService
                        .channelTurnsId,
                    channelName: LocalNotificationsTurnNotificationService
                        .channelTurnsName,
                    channelDesc: LocalNotificationsTurnNotificationService
                        .channelTurnsDescription,
                    title: bgL10n.notifTurnCompleted,
                    body: preview,
                    payload: sessionId,
                  );
                }

                // 标记已通知
                final nowStr = DateTime.now().toIso8601String();
                await prefs.setString(
                    '$keyLastNotifiedStreamPrefix$streamId', nowStr);
                if (sessionId.isNotEmpty) {
                  await prefs.setString(
                      '$keyLastNotifiedSessionPrefix$sessionId', nowStr);
                }
              }

              // 清理 activeStream 状态并取消 OneOff
              await prefs.setString(keyActiveStreamId, '');
              await prefs.setBool(keyIsStreaming, false);
              if (bgFgsEnabled) {
                try {
                  final isRunning =
                      await FlutterForegroundTask.isRunningService;
                  if (isRunning) {
                    await FlutterForegroundTask.updateService(
                      notificationTitle: 'Hermes',
                      notificationText: formatNotificationText(0, isEnglish: LocaleResolver.isEnglish),
                    );
                  }
                } catch (e) {
                  developer.log('WorkManager updateService error: $e');
                }
              }
              try {
                await Workmanager().cancelByUniqueName('hermes-bg-oneoff-$sessionId');
              } catch (e) {
                developer.log('WorkManager cancelByUniqueName error: $e');
              }
              return true;
            }
          }
        } catch (e) {
          developer.log('WorkManager /api/chat/stream/status error: $e');
          // 网络抖动，返回 false 触发指数退避
          return false;
        }
      }

      // 2. 查 /api/session
      if (sessionId.isNotEmpty) {
        try {
          final res = await dio.get<Map<String, dynamic>>(
            '/api/session',
            queryParameters: {
              'session_id': sessionId,
              'messages': 1,
              'include_messages': true,
            },
          );
          final sessData = res.data;
          final sDetail =
              sessData?['session'] as Map<String, dynamic>? ?? sessData;
          final isStreaming = sDetail?['is_streaming'] == true;
          final activeStream = sDetail?['active_stream_id'] as String?;

          if (!isStreaming && (activeStream == null || activeStream.isEmpty)) {
            // 已不在生成状态，检查去重
            final lastNotified =
                prefs.getString('$keyLastNotifiedSessionPrefix$sessionId');
            final wasStreaming = prefs.getBool(keyIsStreaming) ?? false;

            if (wasStreaming && lastNotified == null && notifyTurns) {
              String preview = bgL10n.notifTurnFallbackBody;
              final msgs = sDetail?['messages'] as List?;
              if (msgs != null && msgs.isNotEmpty) {
                for (final m in msgs.reversed) {
                  if (m is Map &&
                      m['role'] == 'assistant' &&
                      m['content'] is String &&
                      (m['content'] as String).trim().isNotEmpty) {
                    preview = LocalNotificationsTurnNotificationService
                        .formatPreview(m['content'] as String);
                    break;
                  }
                }
              }

              await _showBackgroundNotification(
                id: LocalNotificationsTurnNotificationService
                    .notificationTurnsId,
                channelId: LocalNotificationsTurnNotificationService
                    .channelTurnsId,
                channelName: LocalNotificationsTurnNotificationService
                    .channelTurnsName,
                channelDesc: LocalNotificationsTurnNotificationService
                    .channelTurnsDescription,
                title: bgL10n.notifTurnCompleted,
                body: preview,
                payload: sessionId,
              );

              final nowStr = DateTime.now().toIso8601String();
              await prefs.setString(
                  '$keyLastNotifiedSessionPrefix$sessionId', nowStr);
              await prefs.setBool(keyIsStreaming, false);
              if (bgFgsEnabled) {
                try {
                  final isRunning =
                      await FlutterForegroundTask.isRunningService;
                  if (isRunning) {
                    await FlutterForegroundTask.updateService(
                      notificationTitle: 'Hermes',
                      notificationText: formatNotificationText(0, isEnglish: LocaleResolver.isEnglish),
                    );
                  }
                } catch (e) {
                  developer.log('WorkManager updateService error: $e');
                }
              }
            }
          }
        } catch (e) {
          developer.log('WorkManager /api/session error: $e');
          return false;
        }
      }

      return true;
    } catch (e) {
      developer.log('handleTask unexpected error: $e');
      return false;
    }
  }

  static Future<void> _showBackgroundNotification({
    required int id,
    required String channelId,
    required String channelName,
    required String channelDesc,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      developer.log('showBackgroundNotification error: $e');
    }
  }
}

/// 测试用 FakeBackgroundKeepaliveService 实现。
class FakeBackgroundKeepaliveService implements BackgroundKeepaliveService {
  final List<String> startedForegroundServices = [];
  final List<String> stoppedForegroundServices = [];
  final List<int> updatedNotificationCounts = [];
  final List<(String sessionId, String? streamId)> scheduledOneOffPolls = [];
  final List<String> cancelledOneOffPolls = [];
  final List<(String sessionId, String? streamId)> notifiedRecords = [];
  final List<HyperOsSettingType> openedSettings = [];
  final List<Function?> receivedCallbacks = [];
  final List<(int count, List<String>? titles)> syncedOngoingNotifications = [];
  String? lastOngoingText;

  bool isInitialized = false;
  bool fgTaskReady = false;
  bool wmReady = false;
  bool isForegroundServiceRunning = false;
  int currentActiveCount = 0;
  Object? shouldFailStartForegroundServiceWith;

  @override
  Future<void> initialize() async {
    isInitialized = true;
    fgTaskReady = true;
    wmReady = true;
  }

  @override
  Future<void> onAppLifecycleChanged({
    required AppLifecycleState state,
    required String? activeSessionId,
    required String? activeStreamId,
    required bool isStreaming,
    required bool foregroundServiceEnabled,
  }) async {
    final activeCount =
        (isStreaming || (activeStreamId != null && activeStreamId.isNotEmpty))
            ? 1
            : 0;
    if (foregroundServiceEnabled) {
      if (isForegroundServiceRunning) {
        await updateNotification(activeCount: activeCount);
      } else {
        await startForegroundService(
          sessionId: activeSessionId ?? '',
          streamId: activeStreamId,
          activeCount: activeCount,
          callback: foregroundTaskCallback,
        );
      }
    }

    if (state == AppLifecycleState.resumed) {
      if (activeSessionId != null && activeSessionId.isNotEmpty) {
        await cancelOneOffPoll(activeSessionId);
      }
    } else {
      if (isStreaming ||
          (activeStreamId != null && activeStreamId.isNotEmpty)) {
        if (activeSessionId != null && activeSessionId.isNotEmpty) {
          await scheduleExpeditedOneOffPoll(
            sessionId: activeSessionId,
            streamId: activeStreamId,
          );
        }
      }
    }
  }

  @override
  Future<void> startForegroundService({
    String sessionId = '',
    String? streamId,
    int? activeCount,
    Function? callback,
  }) async {
    if (shouldFailStartForegroundServiceWith != null) {
      throw shouldFailStartForegroundServiceWith!;
    }
    startedForegroundServices.add(sessionId);
    receivedCallbacks.add(callback ?? foregroundTaskCallback);
    isForegroundServiceRunning = true;
    currentActiveCount = activeCount ??
        ((streamId != null && streamId.isNotEmpty) ? 1 : 0);
    lastOngoingText = ProductionBackgroundKeepaliveService.formatNotificationText(
      currentActiveCount,
      isEnglish: LocaleResolver.isEnglish,
    );
    updatedNotificationCounts.add(currentActiveCount);
  }

  @override
  Future<void> stopForegroundService({bool force = false}) async {
    stoppedForegroundServices.add('stopped');
    if (force) {
      isForegroundServiceRunning = false;
      lastOngoingText = null;
    } else {
      currentActiveCount = 0;
      lastOngoingText = ProductionBackgroundKeepaliveService.formatNotificationText(
        0,
        isEnglish: LocaleResolver.isEnglish,
      );
      updatedNotificationCounts.add(0);
    }
  }

  @override
  Future<void> updateNotification({int activeCount = 0}) async {
    currentActiveCount = activeCount;
    lastOngoingText = ProductionBackgroundKeepaliveService.formatNotificationText(
      activeCount,
      isEnglish: LocaleResolver.isEnglish,
    );
    updatedNotificationCounts.add(activeCount);
  }

  @override
  Future<void> syncOngoingNotification(
    int activeCount, [
    List<String>? titles,
  ]) async {
    final text = ProductionBackgroundKeepaliveService.formatNotificationText(
      activeCount,
      isEnglish: LocaleResolver.isEnglish,
    );
    if (text == lastOngoingText) {
      return;
    }
    lastOngoingText = text;
    currentActiveCount = activeCount;
    updatedNotificationCounts.add(activeCount);
    syncedOngoingNotifications.add((activeCount, titles));
  }

  @override
  Future<void> scheduleExpeditedOneOffPoll({
    required String sessionId,
    required String? streamId,
  }) async {
    scheduledOneOffPolls.add((sessionId, streamId));
  }

  @override
  Future<void> cancelOneOffPoll(String sessionId) async {
    cancelledOneOffPolls.add(sessionId);
  }

  @override
  Future<void> recordTurnNotified({
    required String sessionId,
    required String? streamId,
  }) async {
    notifiedRecords.add((sessionId, streamId));
  }

  @override
  Future<bool> isTurnAlreadyNotified({
    required String sessionId,
    required String? streamId,
  }) async {
    return notifiedRecords.any(
      (r) =>
          (streamId != null && streamId.isNotEmpty && r.$2 == streamId) ||
          (sessionId.isNotEmpty && r.$1 == sessionId),
    );
  }

  @override
  Future<void> openHyperOsSetting(HyperOsSettingType type) async {
    openedSettings.add(type);
  }
}
