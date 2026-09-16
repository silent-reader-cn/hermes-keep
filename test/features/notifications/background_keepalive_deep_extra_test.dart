// PL1 批次：`background_keepalive_service.dart` /
// `workmanager_registration_probe.dart` 平台接缝补测（深度补强）。
//
// 纪律（与既有测试一致）：
//  * `debugDefaultTargetPlatformOverride` 用完必须还原成 `null`（tearDown 兜底），
//    否则污染同文件后续用例；
//  * 定时器/异步一律 await 或 pumpEventQueue，禁 `await Future.delayed` 真等；
//  * 所有断言预期值均从实现里读出来，禁空断言。
//
// 本文件第 1 部分：纯逻辑 + 服务状态机分支（用 Fake wrapper / Mock Workmanager
// 注入，不走平台通道）。
// 第 2 部分：真实平台接缝（MethodChannel mock、真实 ForegroundTaskWrapper、
// handleTask 走本机 loopback HttpServer）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_service.dart';
import 'package:hermes_ui/features/notifications/live_update_service.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:hermes_ui/features/notifications/workmanager_registration_probe.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

// ---------------------------------------------------------------------------
// 测试替身
// ---------------------------------------------------------------------------

class _MockWorkmanager extends Mock implements Workmanager {}

class _MockLiveUpdateService extends Mock implements LiveUpdateService {}

/// 注解级 Fake：可控 init / isRunning / start / update / stop 的每一个分支。
class _FakeForegroundTaskWrapper implements ForegroundTaskWrapper {
  int initCallCount = 0;
  AndroidNotificationOptions? capturedAndroidNotificationOptions;
  IOSNotificationOptions? capturedIosNotificationOptions;
  ForegroundTaskOptions? capturedForegroundTaskOptions;

  /// 非 null 时 [init] 抛出该对象。
  Object? initError;

  bool isRunning = false;

  /// 非 null 时 [isRunningService] 抛出该对象。
  Object? isRunningError;

  int startServiceCallCount = 0;
  String? lastNotificationTitle;
  String? lastNotificationText;
  Function? lastCallback;
  ServiceRequestResult startServiceResult = const ServiceRequestSuccess();
  Object? startServiceError;

  int updateServiceCallCount = 0;
  ServiceRequestResult updateServiceResult = const ServiceRequestSuccess();
  Object? updateServiceError;

  int stopServiceCallCount = 0;
  ServiceRequestResult stopServiceResult = const ServiceRequestSuccess();
  Object? stopServiceError;

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {
    final error = initError;
    if (error != null) {
      throw error;
    }
    initCallCount++;
    capturedAndroidNotificationOptions = androidNotificationOptions;
    capturedIosNotificationOptions = iosNotificationOptions;
    capturedForegroundTaskOptions = foregroundTaskOptions;
  }

  @override
  Future<bool> get isRunningService async {
    final error = isRunningError;
    if (error != null) {
      throw error;
    }
    return isRunning;
  }

  @override
  Future<ServiceRequestResult> startService({
    required String notificationTitle,
    required String notificationText,
    Function? callback,
  }) async {
    startServiceCallCount++;
    lastNotificationTitle = notificationTitle;
    lastNotificationText = notificationText;
    lastCallback = callback;
    final error = startServiceError;
    if (error != null) {
      throw error;
    }
    if (startServiceResult is ServiceRequestSuccess) {
      isRunning = true;
    }
    return startServiceResult;
  }

  @override
  Future<ServiceRequestResult> updateService({
    required String notificationTitle,
    required String notificationText,
  }) async {
    updateServiceCallCount++;
    lastNotificationTitle = notificationTitle;
    lastNotificationText = notificationText;
    final error = updateServiceError;
    if (error != null) {
      throw error;
    }
    return updateServiceResult;
  }

  @override
  Future<ServiceRequestResult> stopService() async {
    stopServiceCallCount++;
    final error = stopServiceError;
    if (error != null) {
      throw error;
    }
    if (stopServiceResult is ServiceRequestSuccess) {
      isRunning = false;
    }
    return stopServiceResult;
  }
}

class _RecordingRegistrationProbe implements WorkManagerRegistrationProbe {
  _RecordingRegistrationProbe(this.snapshot);

  final WorkManagerRegistrationSnapshot snapshot;
  int calls = 0;

  @override
  Future<WorkManagerRegistrationSnapshot> probe() async {
    calls++;
    return snapshot;
  }
}

/// 让 `SharedPreferences.getInstance()` 直接抛错的存储实现：
/// 用于覆盖各方法「读配置失败」的 catch 降级分支。
class _ThrowingPrefsStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() async => throw StateError('prefs clear unavailable');

  @override
  Future<Map<String, Object>> getAll() async =>
      throw StateError('prefs getAll unavailable');

  @override
  Future<bool> remove(String key) async =>
      throw StateError('prefs remove unavailable');

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      throw StateError('prefs setValue unavailable');
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

/// 当前诊断缓冲里的 (level, message) 列表。
List<(DiagnosticsLogLevel, String)> _diagEntries({String tag = 'keepalive'}) {
  return DiagnosticsService.instance.logs
      .where((e) => e.tag == tag)
      .map((e) => (e.level, e.message))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(workmanagerCallbackDispatcher);
    registerFallbackValue(const Duration(minutes: 15));
    registerFallbackValue(ExistingPeriodicWorkPolicy.keep);
    registerFallbackValue(ExistingWorkPolicy.replace);
    registerFallbackValue(BackoffPolicy.exponential);
    registerFallbackValue(Constraints(networkType: NetworkType.connected));
    registerFallbackValue(OutOfQuotaPolicy.runAsNonExpeditedWorkRequest);
  });

  late ProductionBackgroundKeepaliveService service;
  late _FakeForegroundTaskWrapper fg;
  late _MockWorkmanager wm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    DiagnosticsService.instance.clearMemoryOnly();
    await DiagnosticsService.instance.setEnabled(true);
    fg = _FakeForegroundTaskWrapper();
    wm = _MockWorkmanager();
    service = ProductionBackgroundKeepaliveService(
      workmanager: wm,
      foregroundTaskWrapper: fg,
    );
    _stubWorkmanager(wm);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    LocaleResolver.reset();
    DiagnosticsService.instance.clearMemoryOnly();
  });

  // =========================================================================
  // A. 平台判据：非 Android 一律早退（不得触碰任何平台通道 / 不得改持久化）
  // =========================================================================

  group('A. 非 Android 平台早退判据（debugDefaultTargetPlatformOverride）', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.windows,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      test('$platform：八个平台方法全部静默早退，且不写任何持久化键', () async {
        debugDefaultTargetPlatformOverride = platform;

        await service.initialize();
        expect(fg.initCallCount, 0, reason: '非 Android 不应初始化 ForegroundTask');
        expect(service.fgTaskReady, isFalse);
        expect(service.wmReady, isFalse);
        expect(service.isInitialized, isFalse);

        await service.onAppLifecycleChanged(
          state: AppLifecycleState.paused,
          activeSessionId: 's1',
          activeStreamId: 'st1',
          isStreaming: true,
          foregroundServiceEnabled: true,
        );
        await service.startForegroundService(activeCount: 1);
        await service.updateNotification(activeCount: 2);
        await service.syncOngoingNotification(3, const ['t']);
        await service.stopForegroundService(force: true);
        await service.scheduleExpeditedOneOffPoll(
          sessionId: 's1',
          streamId: 'st1',
        );
        await service.cancelOneOffPoll('s1');
        await service.openHyperOsSetting(HyperOsSettingType.autoStart);

        expect(fg.startServiceCallCount, 0);
        expect(fg.updateServiceCallCount, 0);
        expect(fg.stopServiceCallCount, 0);
        verifyNever(
          () => wm.registerPeriodicTask(
            any(),
            any(),
            frequency: any(named: 'frequency'),
            flexInterval: any(named: 'flexInterval'),
            inputData: any(named: 'inputData'),
            initialDelay: any(named: 'initialDelay'),
            constraints: any(named: 'constraints'),
            existingWorkPolicy: any(named: 'existingWorkPolicy'),
            backoffPolicy: any(named: 'backoffPolicy'),
            backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
            tag: any(named: 'tag'),
            foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
          ),
        );
        verifyNever(
          () => wm.registerOneOffTask(
            any(),
            any(),
            inputData: any(named: 'inputData'),
            initialDelay: any(named: 'initialDelay'),
            constraints: any(named: 'constraints'),
            existingWorkPolicy: any(named: 'existingWorkPolicy'),
            backoffPolicy: any(named: 'backoffPolicy'),
            backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
            tag: any(named: 'tag'),
            outOfQuotaPolicy: any(named: 'outOfQuotaPolicy'),
            foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
            expedited: any(named: 'expedited'),
          ),
        );
        verifyNever(() => wm.cancelByUniqueName(any()));

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(ProductionBackgroundKeepaliveService.keyIsStreaming),
          isNull,
          reason: '非 Android 不应写入流状态键',
        );
        expect(
          prefs.getKeys().where((k) => k.contains('bg_')),
          isEmpty,
          reason: '非 Android 不应留下任何保活相关持久化痕迹',
        );
      });
    }
  });

  // =========================================================================
  // B. initialize() 分支
  // =========================================================================

  group('B. initialize() 分支', () {
    test('B1 ForegroundTask.init 抛异常 → fgTaskReady 保持 false、写 error 诊断，'
        '但 WorkManager 仍继续初始化成功（分步隔离）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.initError = PlatformException(
        code: 'init-boom',
        message: 'foreground task init failed',
      );

      expect(service.isInitialized, isFalse);
      await service.initialize();

      expect(service.fgTaskReady, isFalse, reason: 'init 失败不得置就绪');
      expect(service.wmReady, isTrue, reason: 'WorkManager 步骤必须独立于 fg 步骤');
      expect(service.isInitialized, isFalse);

      final logged = _diagEntries();
      expect(
        logged,
        contains((
          DiagnosticsLogLevel.error,
          'ForegroundTask 初始化失败',
        )),
      );
      // 只走到「部分就绪」分支：wmReady=true 但 fgTaskReady=false → 两条日志都不该出现
      expect(
        logged.map((e) => e.$2),
        isNot(contains('后台保活服务初始化成功（WorkManager + ForegroundTask）')),
      );
      expect(
        logged.map((e) => e.$2),
        isNot(contains('后台保活服务部分就绪（ForegroundTask 就绪，WorkManager 失败）')),
      );

      // 重试：fg 恢复后补齐
      fg.initError = null;
      await service.initialize();
      expect(fg.initCallCount, 1);
      expect(service.fgTaskReady, isTrue);
      expect(service.isInitialized, isTrue);
      expect(
        _diagEntries().map((e) => e.$2),
        contains('后台保活服务初始化成功（WorkManager + ForegroundTask）'),
      );
    });

    test('B2 WorkManager 初始化抛非 channel-error → 不调探针，仍写 error 诊断且无归因后缀',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final probe = _RecordingRegistrationProbe(
        const WorkManagerRegistrationSnapshot(initialized: true),
      );
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: fg,
        registrationProbe: probe,
      );
      when(() => wm.initialize(any())).thenThrow(
        PlatformException(code: 'constraint-error', message: 'bad constraints'),
      );

      await local.initialize();

      expect(local.fgTaskReady, isTrue);
      expect(local.wmReady, isFalse);
      expect(probe.calls, 0, reason: '非 channel-error 不触发原生探针');
      expect(
        _diagEntries(),
        contains((
          DiagnosticsLogLevel.error,
          'WorkManager 初始化失败',
        )),
      );
      expect(
        _diagEntries().map((e) => e.$2),
        contains('后台保活服务部分就绪（ForegroundTask 就绪，WorkManager 失败）'),
      );
    });

    test('B3 WorkManager 报 channel-error → 调原生探针，归因串拼进诊断 message（#110）',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final probe = _RecordingRegistrationProbe(
        const WorkManagerRegistrationSnapshot(
          initialized: false,
          creation: 'manual-initialize-failed',
          error: 'IllegalStateException: WorkManager is not initialized',
          chain: 'rustLib=loaded workmanager=false',
        ),
      );
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: fg,
        registrationProbe: probe,
      );
      when(() => wm.initialize(any())).thenThrow(
        PlatformException(code: 'channel-error', message: 'unbound'),
      );

      await local.initialize();

      expect(probe.calls, 1);
      final messages = _diagEntries().map((e) => e.$2).toList();
      final attributed = messages.firstWhere(
        (m) => m.startsWith('WorkManager 初始化失败（channel-error'),
      );
      expect(attributed, contains('探针 initialized=false'));
      expect(attributed, contains('creation=manual-initialize-failed'));
      expect(attributed, contains('WorkManager is not initialized'));
      expect(attributed, contains('chain=rustLib=loaded workmanager=false'));
      // 探针失败时降级文案
      final degraded = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: fg,
        registrationProbe: _ThrowingRegistrationProbe(),
      );
      await degraded.describeWorkManagerInitFailure(
        PlatformException(code: 'channel-error', message: 'unbound'),
      ).then((text) {
        expect(text, '（channel-error：原生插件注册未绑定，探针不可用）');
      });
    });

    test('B4 WM 首次失败后重试成功 → wmReady 置位；周期任务参数（15 分钟/联网/keep/指数退避 30s）精确断言',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      when(() => wm.initialize(any())).thenThrow(StateError('boom'));

      await service.initialize();
      expect(service.wmReady, isFalse);

      _stubWorkmanager(wm);
      await service.initialize();
      expect(service.wmReady, isTrue);
      expect(fg.initCallCount, 1, reason: 'fgTask 已就绪不应重复 init');

      final captured = verify(
        () => wm.registerPeriodicTask(
          captureAny(),
          captureAny(),
          frequency: captureAny(named: 'frequency'),
          flexInterval: any(named: 'flexInterval'),
          inputData: any(named: 'inputData'),
          initialDelay: any(named: 'initialDelay'),
          constraints: captureAny(named: 'constraints'),
          existingWorkPolicy: captureAny(named: 'existingWorkPolicy'),
          backoffPolicy: captureAny(named: 'backoffPolicy'),
          backoffPolicyDelay: captureAny(named: 'backoffPolicyDelay'),
          tag: captureAny(named: 'tag'),
          foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
        ),
      ).captured;

      expect(captured[0], 'hermes-bg-poll-periodic');
      expect(captured[1], 'hermes.bg.poll.periodic');
      expect(captured[2], const Duration(minutes: 15));
      expect(captured[3], isA<Constraints>());
      expect(
        (captured[3] as Constraints).networkType,
        NetworkType.connected,
      );
      expect(captured[4], ExistingPeriodicWorkPolicy.keep);
      expect(captured[5], BackoffPolicy.exponential);
      expect(captured[6], const Duration(seconds: 30));
      expect(captured[7], 'hermes-bg-poll');
    });

    test('B5 init 已全部就绪时重复调用 → 立即早退（不重复 initialize / 不重复注册）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await service.initialize();
      expect(service.isInitialized, isTrue);

      await service.initialize();
      await service.initialize();

      verify(() => wm.initialize(any())).called(1);
      expect(fg.initCallCount, 1);
    });

    test('B6 冷启动条件拉起：开关关 → 不拉起；开关开 + 无活跃流 → 「暂无进行中会话」',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': false,
      });
      await service.initialize();
      expect(fg.startServiceCallCount, 0);

      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
      });
      final second = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: fg,
      );
      await second.initialize();
      expect(fg.startServiceCallCount, 1);
      expect(fg.lastNotificationTitle, 'Hermes');
      expect(fg.lastNotificationText, '暂无进行中会话');
      expect(fg.lastCallback, equals(foregroundTaskCallback));
    });

    test('B7 冷启动条件拉起：开关开 + activeStreamId 非空（isStreaming=false）也判为活跃',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
        ProductionBackgroundKeepaliveService.keyActiveStreamId: 'stream-9',
      });

      await service.initialize();

      expect(fg.startServiceCallCount, 1);
      expect(fg.lastNotificationText, '1 个会话正在生成');
    });

    test('B8 冷启动拉起失败（ServiceRequestFailure）→ 冒泡被 catch，写 error 诊断且不抛出',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
        'bg_is_streaming': true,
      });
      fg.startServiceResult = ServiceRequestFailure(
        error: Exception('ServiceTimeoutException'),
      );

      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(
        _diagEntries(),
        contains((
          DiagnosticsLogLevel.error,
          '冷启动拉起前台服务失败',
        )),
      );
      final failed = _diagEntries().firstWhere(
        (e) => e.$2 == '冷启动拉起前台服务失败',
      );
      expect(failed.$1, DiagnosticsLogLevel.error);
    });

    test('B9 冷启动读配置抛错（SharedPreferences 不可用）→ 走 catch，不抛出', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();

      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(
        _diagEntries().map((e) => e.$2),
        contains('冷启动拉起前台服务失败'),
      );
      expect(fg.startServiceCallCount, 0, reason: '拿不到开关就不得拉起');
    });
  });

  // =========================================================================
  // C. 语言监听刷新（_refreshNotificationForLocale，L2 接线）
  // =========================================================================

  group('C. 语言切换刷新常驻通知（LocaleResolver 监听接线）', () {
    test('C1 init 成功即注册语言监听；切到 en 且开关开 + 正在流式 → 通知重算为英文 1 会话',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
        ProductionBackgroundKeepaliveService.keyIsStreaming: true,
      });
      final wrapper = _FakeForegroundTaskWrapper()..isRunning = true;
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: wrapper,
      );

      expect(LocaleResolver.listenerCount, 0);
      await local.initialize();
      expect(LocaleResolver.listenerCount, 1, reason: '语言监听必须注册一次');

      wrapper.updateServiceCallCount = 0;
      LocaleResolver.updateMode(AppLocaleMode.en);
      await pumpEventQueue();

      expect(wrapper.updateServiceCallCount, 1);
      expect(wrapper.lastNotificationText, '1 session generating');
      expect(wrapper.lastNotificationTitle, 'Hermes');
    });

    test('C2 开关关闭 → 监听回调早退，不刷新通知', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': false,
      });
      final wrapper = _FakeForegroundTaskWrapper()..isRunning = true;
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: wrapper,
      );
      await local.initialize();

      wrapper.updateServiceCallCount = 0;
      LocaleResolver.updateMode(AppLocaleMode.en);
      await pumpEventQueue();

      expect(wrapper.updateServiceCallCount, 0);
    });

    test('C3 开关开但流已结束（isStreaming=false 且无 activeStreamId）→ 重算为 0 文案',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
        ProductionBackgroundKeepaliveService.keyIsStreaming: false,
      });
      final wrapper = _FakeForegroundTaskWrapper()..isRunning = true;
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: wrapper,
      );
      await local.initialize();

      wrapper.updateServiceCallCount = 0;
      LocaleResolver.updateMode(AppLocaleMode.en);
      await pumpEventQueue();

      expect(wrapper.lastNotificationText, 'No active sessions');
    });

    test('C4 非 Android → 监听回调早退（不读配置、不刷新）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      LocaleResolver.updateMode(AppLocaleMode.en);
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: fg,
      );
      await local.initialize();
      expect(LocaleResolver.listenerCount, 0, reason: '非 Android 不注册监听');

      LocaleResolver.updateMode(AppLocaleMode.zh);
      await pumpEventQueue();
      expect(fg.updateServiceCallCount, 0);
    });

    test('C6 开关开 + isStreaming=false 但 activeStreamId 非空 → 仍判为活跃（|| 右操作数分支）',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
        'bg_is_streaming': false,
        ProductionBackgroundKeepaliveService.keyActiveStreamId: 'stream-live',
      });
      final wrapper = _FakeForegroundTaskWrapper()..isRunning = true;
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: wrapper,
      );
      await local.initialize();

      wrapper.updateServiceCallCount = 0;
      LocaleResolver.updateMode(AppLocaleMode.en);
      await pumpEventQueue();

      expect(wrapper.updateServiceCallCount, 1);
      expect(wrapper.lastNotificationText, '1 session generating');
    });

    test('C5 读配置抛错 → catch 吞掉（切语言不得打断主流程）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();

      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: fg,
      );
      await local.initialize();
      expect(LocaleResolver.listenerCount, 1);

      // 触发监听回调：内部 SharedPreferences 抛错，由 catch 吸收，不冒泡。
      LocaleResolver.updateMode(AppLocaleMode.en);
      await pumpEventQueue();
      expect(fg.updateServiceCallCount, 0);
    });
  });

  // =========================================================================
  // D. onAppLifecycleChanged 分支
  // =========================================================================

  group('D. onAppLifecycleChanged 分支', () {
    test('D1 流状态持久化：三个键分别写成（null → 空串）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final prefs = await SharedPreferences.getInstance();

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.resumed,
        activeSessionId: 'sess-a',
        activeStreamId: 'stream-a',
        isStreaming: true,
        foregroundServiceEnabled: false,
      );

      expect(
        prefs.getString(ProductionBackgroundKeepaliveService.keyActiveSessionId),
        'sess-a',
      );
      expect(
        prefs.getString(ProductionBackgroundKeepaliveService.keyActiveStreamId),
        'stream-a',
      );
      expect(
        prefs.getBool(ProductionBackgroundKeepaliveService.keyIsStreaming),
        isTrue,
      );

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.resumed,
        activeSessionId: null,
        activeStreamId: null,
        isStreaming: false,
        foregroundServiceEnabled: false,
      );
      expect(
        prefs.getString(ProductionBackgroundKeepaliveService.keyActiveSessionId),
        '',
      );
      expect(
        prefs.getString(ProductionBackgroundKeepaliveService.keyActiveStreamId),
        '',
      );
      expect(
        prefs.getBool(ProductionBackgroundKeepaliveService.keyIsStreaming),
        isFalse,
      );
      expect(fg.startServiceCallCount, 0, reason: '开关关闭不得启服务');
      expect(fg.updateServiceCallCount, 0);
    });

    test('D2 开关开 + 服务未运行 → 启动前台服务（count 由流状态决定）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = false;

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-a',
        activeStreamId: 'stream-a',
        isStreaming: false,
        foregroundServiceEnabled: true,
      );

      expect(fg.startServiceCallCount, 1);
      expect(fg.lastNotificationText, '1 个会话正在生成');
      expect(fg.lastCallback, equals(foregroundTaskCallback));
      expect(fg.updateServiceCallCount, 0);
    });

    test('D3 开关开 + 服务已运行 → 只刷通知文本，不重启服务', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.inactive,
        activeSessionId: 'sess-a',
        activeStreamId: null,
        isStreaming: false,
        foregroundServiceEnabled: true,
      );

      expect(fg.startServiceCallCount, 0);
      expect(fg.updateServiceCallCount, 1);
      expect(fg.lastNotificationText, '暂无进行中会话');
    });

    test('D4 resumed + sessionId 非空 → 取消 OneOff；resumed + 空 sessionId → 不取消',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.resumed,
        activeSessionId: 'sess-a',
        activeStreamId: 'stream-a',
        isStreaming: true,
        foregroundServiceEnabled: false,
      );
      verify(() => wm.cancelByUniqueName('hermes-bg-oneoff-sess-a')).called(1);
      verifyNever(
        () => wm.registerOneOffTask(
          any(),
          any(),
          inputData: any(named: 'inputData'),
          initialDelay: any(named: 'initialDelay'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
          tag: any(named: 'tag'),
          outOfQuotaPolicy: any(named: 'outOfQuotaPolicy'),
          foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
          expedited: any(named: 'expedited'),
        ),
      );

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.resumed,
        activeSessionId: null,
        activeStreamId: null,
        isStreaming: false,
        foregroundServiceEnabled: false,
      );
      verifyNever(() => wm.cancelByUniqueName(any()));
    });

    test('D5 切后台 + 正在流式 → 调度 OneOff，参数（延迟 1min/联网/runAsNonExpedited/inputData）精确断言',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-a',
        activeStreamId: 'stream-a',
        isStreaming: true,
        foregroundServiceEnabled: false,
      );

      final captured = verify(
        () => wm.registerOneOffTask(
          captureAny(),
          captureAny(),
          inputData: captureAny(named: 'inputData'),
          initialDelay: captureAny(named: 'initialDelay'),
          constraints: captureAny(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: captureAny(named: 'backoffPolicy'),
          backoffPolicyDelay: captureAny(named: 'backoffPolicyDelay'),
          tag: captureAny(named: 'tag'),
          outOfQuotaPolicy: captureAny(named: 'outOfQuotaPolicy'),
          foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
          expedited: any(named: 'expedited'),
        ),
      ).captured;

      expect(captured[0], 'hermes-bg-oneoff-sess-a');
      expect(captured[1], 'hermes.bg.poll.oneoff');
      expect(captured[2], {'sessionId': 'sess-a', 'streamId': 'stream-a'});
      expect(captured[3], const Duration(minutes: 1));
      expect((captured[4] as Constraints).networkType, NetworkType.connected);
      expect(captured[5], BackoffPolicy.exponential);
      expect(captured[6], const Duration(seconds: 30));
      expect(captured[7], 'hermes-bg-oneoff');
      expect(captured[8], OutOfQuotaPolicy.runAsNonExpeditedWorkRequest);
      expect(
        _diagEntries().map((e) => e.$2),
        contains('调度 WorkManager 加急探活任务'),
      );
    });

    test('D6 切后台但 isStreaming=false 且 activeStreamId 空 → 不调度 OneOff', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-a',
        activeStreamId: '',
        isStreaming: false,
        foregroundServiceEnabled: false,
      );

      verifyNever(
        () => wm.registerOneOffTask(
          any(),
          any(),
          inputData: any(named: 'inputData'),
          initialDelay: any(named: 'initialDelay'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
          tag: any(named: 'tag'),
          outOfQuotaPolicy: any(named: 'outOfQuotaPolicy'),
          foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
          expedited: any(named: 'expedited'),
        ),
      );
    });

    test('D7 切后台 + 流式但 sessionId 为空 → 有流也不调度（sessionId 为前置条件）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: '',
        activeStreamId: 'stream-a',
        isStreaming: true,
        foregroundServiceEnabled: false,
      );

      verifyNever(
        () => wm.registerOneOffTask(
          any(),
          any(),
          inputData: any(named: 'inputData'),
          initialDelay: any(named: 'initialDelay'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
          tag: any(named: 'tag'),
          outOfQuotaPolicy: any(named: 'outOfQuotaPolicy'),
          foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
          expedited: any(named: 'expedited'),
        ),
      );
    });

    test('D8 启服务失败向上冒泡 → 被本方法 catch，写 error 诊断且不抛出', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = false;
      fg.startServiceResult = ServiceRequestFailure(error: Exception('start-kaboom'));

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-a',
        activeStreamId: 'stream-a',
        isStreaming: true,
        foregroundServiceEnabled: true,
      );

      expect(
        _diagEntries(),
        contains((
          DiagnosticsLogLevel.error,
          '生命周期保活联动失败',
        )),
      );
    });

    test('D9 读配置抛错 → catch 吞掉，不抛出', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();

      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-a',
        activeStreamId: 'stream-a',
        isStreaming: true,
        foregroundServiceEnabled: false,
      );

      expect(
        _diagEntries().map((e) => e.$2),
        contains('生命周期保活联动失败'),
      );
    });
  });

  // =========================================================================
  // E. startForegroundService 分支
  // =========================================================================

  group('E. startForegroundService 分支', () {
    test('E1 fgTask 未就绪 → 先 initialize；仍不就绪 → 抛 StateError 并 rethrow（失败可见化）',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.initError = StateError('fg init down');

      await expectLater(
        service.startForegroundService(activeCount: 1),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ForegroundTask not initialized',
          ),
        ),
      );

      expect(
        _diagEntries(),
        contains((
          DiagnosticsLogLevel.error,
          '启动前台保活服务失败',
        )),
      );
      expect(fg.startServiceCallCount, 0);
    });

    test('E2 未就绪 → initialize 成功后就绪并继续启动服务', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await service.startForegroundService(activeCount: 2);

      expect(fg.initCallCount, 1);
      expect(service.isInitialized, isTrue);
      expect(fg.startServiceCallCount, 1);
      expect(fg.lastNotificationText, '2 个会话正在生成');
    });

    test('E3 count 推导：显式 activeCount 优先 > streamId 非空记 1 > 两者皆无记 0', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await service.initialize();

      await service.startForegroundService(activeCount: 5, streamId: 'st');
      expect(fg.lastNotificationText, '5 个会话正在生成');

      fg.isRunning = true;
      await service.startForegroundService(streamId: 'st');
      expect(fg.lastNotificationText, '1 个会话正在生成');
      expect(fg.updateServiceCallCount, 1, reason: '运行中走 updateService');

      await service.startForegroundService(streamId: '');
      expect(fg.lastNotificationText, '暂无进行中会话');
      await service.startForegroundService();
      expect(fg.lastNotificationText, '暂无进行中会话');
    });

    test('E4 服务已运行 → 走 updateService 分支（不 startService），text 落库为上次文案',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await service.initialize();
      fg.isRunning = true;

      await service.startForegroundService(activeCount: 1);

      expect(fg.startServiceCallCount, 0);
      expect(fg.updateServiceCallCount, 1);
      expect(fg.lastNotificationTitle, 'Hermes');
      expect(fg.lastNotificationText, '1 个会话正在生成');
    });

    test('E5 updateService 返回 ServiceRequestFailure → 抛出并 rethrow（同检返回值）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await service.initialize();
      fg.isRunning = true;
      fg.updateServiceResult = ServiceRequestFailure(
        error: Exception('update-service-failed'),
      );

      await expectLater(
        service.startForegroundService(activeCount: 1),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString',
            contains('update-service-failed'),
          ),
        ),
      );
      expect(
        _diagEntries(),
        contains((
          DiagnosticsLogLevel.error,
          '启动前台保活服务失败',
        )),
      );
    });

    test('E6 startService 返回 ServiceRequestFailure → 抛出并 rethrow', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await service.initialize();
      fg.isRunning = false;
      fg.startServiceResult = ServiceRequestFailure(
        error: Exception('start-service-failed'),
      );

      await expectLater(
        service.startForegroundService(activeCount: 1),
        throwsA(isA<Exception>()),
      );
      expect(fg.isRunning, isFalse, reason: '失败不得置运行态');
    });

    test('E7 成功路径：自定义 callback 透传 + 写 info 诊断（含 details）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await service.initialize();
      void customCallback() {}

      await service.startForegroundService(
        sessionId: 'sess-x',
        streamId: 'stream-x',
        activeCount: 1,
        callback: customCallback,
      );

      expect(fg.lastCallback, equals(customCallback));
      final log = _diagEntries().firstWhere(
        (e) => e.$2 == '启动前台保活服务成功',
      );
      expect(log.$1, DiagnosticsLogLevel.info);
      final entry = DiagnosticsService.instance.logs.firstWhere(
        (e) => e.message == '启动前台保活服务成功',
      );
      expect(entry.details, containsPair('sessionId', 'sess-x'));
      expect(entry.details, containsPair('streamId', 'stream-x'));
      expect(entry.details, containsPair('activeCount', 1));
    });

    test('E8 英文语言：文案切换为单复数敏感英文', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      LocaleResolver.reset(mode: AppLocaleMode.en);
      await service.initialize();

      await service.startForegroundService(activeCount: 1);
      expect(fg.lastNotificationText, '1 session generating');

      fg.isRunning = true;
      await service.startForegroundService(activeCount: 3);
      expect(fg.lastNotificationText, '3 sessions generating');
    });
  });

  // =========================================================================
  // F. updateNotification 分支
  // =========================================================================

  group('F. updateNotification 分支', () {
    test('F1 服务未运行 → 早退，不调 updateService', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = false;

      await service.updateNotification(activeCount: 3);

      expect(fg.updateServiceCallCount, 0);
    });

    test('F2 服务运行 → 更新文本并写 debug 诊断', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;

      await service.updateNotification(activeCount: 4);

      expect(fg.updateServiceCallCount, 1);
      expect(fg.lastNotificationTitle, 'Hermes');
      expect(fg.lastNotificationText, '4 个会话正在生成');
      final log = _diagEntries().firstWhere(
        (e) => e.$2 == '更新前台服务常驻通知文本',
      );
      expect(log.$1, DiagnosticsLogLevel.debug);
    });

    test('F3 返回 ServiceRequestFailure → 抛出但被本方法 catch（不冒泡）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;
      fg.updateServiceResult = ServiceRequestFailure(error: Exception('nope'));

      await service.updateNotification(activeCount: 1);

      expect(fg.updateServiceCallCount, 1, reason: '已发出调用，失败不外抛');
      expect(
        _diagEntries().map((e) => e.$2),
        isNot(contains('更新前台服务常驻通知文本')),
      );
    });

    test('F4 updateService 直接抛异常 → 同样被吞', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;
      fg.updateServiceError = PlatformException(code: 'boom');

      await service.updateNotification(activeCount: 1);

      expect(fg.updateServiceCallCount, 1);
    });
  });

  // =========================================================================
  // G. syncOngoingNotification 分支
  // =========================================================================

  group('G. syncOngoingNotification 分支（#89 幂等 + LIVE 委托）', () {
    late _MockLiveUpdateService live;

    setUp(() {
      live = _MockLiveUpdateService();
      LiveUpdateService.instance = live;
      when(
        () => live.sync(
          activeCount: any(named: 'activeCount'),
          titles: any(named: 'titles'),
        ),
      ).thenAnswer((_) async {});
    });

    tearDown(() {
      LiveUpdateService.instance = LiveUpdateService();
    });

    test('G1 LIVE 同步先于「服务未运行早退」：即使保活服务没跑也必须上报（不依赖保活运行）',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = false;

      await service.syncOngoingNotification(2, const ['会话 A']);

      verify(
        () => live.sync(activeCount: 2, titles: const ['会话 A']),
      ).called(1);
      expect(fg.updateServiceCallCount, 0, reason: '服务未运行仍不刷常驻通知');
    });

    test('G2 titles 缺省 → 传给 LIVE 的是空列表（非 null）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = false;

      await service.syncOngoingNotification(1);

      verify(() => live.sync(activeCount: 1, titles: const [])).called(1);
    });

    test('G3 服务运行：首次刷新一次；文案不变时幂等拦截', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;

      await service.syncOngoingNotification(1, const ['A']);
      expect(fg.updateServiceCallCount, 1);
      expect(fg.lastNotificationText, '1 个会话正在生成');

      await service.syncOngoingNotification(1, const ['A', 'B']);
      expect(fg.updateServiceCallCount, 1, reason: 'activeCount 相同 → 文案相同 → 幂等');

      await service.syncOngoingNotification(2, const ['A', 'B']);
      expect(fg.updateServiceCallCount, 2);
      expect(fg.lastNotificationText, '2 个会话正在生成');

      await service.syncOngoingNotification(0);
      expect(fg.updateServiceCallCount, 3);
      expect(fg.lastNotificationText, '暂无进行中会话');
    });

    test('G4 返回 ServiceRequestFailure → 抛出但被吞（幂等缓存不推进）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;
      fg.updateServiceResult = ServiceRequestFailure(error: Exception('x'));

      await service.syncOngoingNotification(1);

      expect(fg.updateServiceCallCount, 1);
      expect(
        _diagEntries().map((e) => e.$2),
        isNot(contains('幂等同步前台服务常驻通知文本')),
      );
    });

    test('G5 本方法自身抛错（isRunningService 抛）→ 吞掉，且 LIVE 已上报', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunningError = PlatformException(code: 'is-running-boom');

      await service.syncOngoingNotification(1);

      verify(() => live.sync(activeCount: 1, titles: const [])).called(1);
      expect(fg.updateServiceCallCount, 0);
    });

    test('G6 LIVE 同步失败不阻断常驻通知链路（catchError 吞）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      when(
        () => live.sync(
          activeCount: any(named: 'activeCount'),
          titles: any(named: 'titles'),
        ),
      ).thenAnswer((_) async => throw StateError('live down'));
      fg.isRunning = true;

      await service.syncOngoingNotification(1);
      await pumpEventQueue();

      expect(fg.updateServiceCallCount, 1, reason: 'LIVE 失败不得影响常驻通知');
    });

    test('G7 幂等缓存键是「文案」而非「计数」：force 停止清缓存后同计数仍需刷新', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;

      await service.syncOngoingNotification(1);
      expect(fg.updateServiceCallCount, 1);

      // force=true 且服务在跑 → stopService 并把 _lastOngoingText 清空
      await service.stopForegroundService(force: true);
      expect(fg.stopServiceCallCount, 1);
      expect(fg.isRunning, isFalse);

      fg.isRunning = true;
      await service.syncOngoingNotification(1);
      expect(fg.updateServiceCallCount, 2, reason: '缓存已清，同计数应重刷');
    });
  });

  // =========================================================================
  // H. stopForegroundService 分支
  // =========================================================================

  group('H. stopForegroundService 分支', () {
    test('H1 force=false + 开关开 → 只把文本刷成 0，不停服务', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
      });
      fg.isRunning = true;
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: fg,
      );

      await local.stopForegroundService();

      expect(fg.stopServiceCallCount, 0);
      expect(fg.updateServiceCallCount, 1);
      expect(fg.lastNotificationText, '暂无进行中会话');
      expect(fg.isRunning, isTrue, reason: '开关开着时服务必须常驻');
      expect(
        _diagEntries().map((e) => e.$2),
        isNot(contains('停止前台保活服务')),
      );
    });

    test('H2 force=false + 开关关 + 服务在跑 → 真停 + 写 info 诊断', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;

      await service.stopForegroundService();

      expect(fg.stopServiceCallCount, 1);
      expect(fg.isRunning, isFalse);
      expect(
        _diagEntries(),
        contains((
          DiagnosticsLogLevel.info,
          '停止前台保活服务',
        )),
      );
    });

    test('H3 force=false + 开关关 + 服务没跑 → 不调 stopService，但仍记 info 日志', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = false;

      await service.stopForegroundService();

      expect(fg.stopServiceCallCount, 0);
      expect(
        _diagEntries().map((e) => e.$2),
        contains('停止前台保活服务'),
      );
    });

    test('H4 force=true 跳过开关检查：即使开关开着也真停', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
      });
      fg.isRunning = true;
      final local = ProductionBackgroundKeepaliveService(
        workmanager: wm,
        foregroundTaskWrapper: fg,
      );

      await local.stopForegroundService(force: true);

      expect(fg.stopServiceCallCount, 1);
      expect(fg.isRunning, isFalse);
      expect(fg.updateServiceCallCount, 0);
    });

    test('H5 返回 ServiceRequestFailure → rethrow + 写 error 诊断（供开关回滚）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;
      fg.stopServiceResult = ServiceRequestFailure(
        error: Exception('stop-failed'),
      );

      await expectLater(
        service.stopForegroundService(),
        throwsA(isA<Exception>()),
      );
      expect(
        _diagEntries(),
        contains((
          DiagnosticsLogLevel.error,
          '停止前台保活服务失败',
        )),
      );
    });

    test('H6 stopService 直接抛异常 → 同样 rethrow', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fg.isRunning = true;
      fg.stopServiceError = PlatformException(code: 'stop-boom');

      await expectLater(
        service.stopForegroundService(force: true),
        throwsA(isA<PlatformException>()),
      );
    });

    test('H7 读配置抛错 → catch 吞掉并 rethrow 语义分离：读失败也 rethrow（在 try 内）',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();

      await expectLater(
        service.stopForegroundService(),
        throwsA(isA<StateError>()),
      );
      expect(
        _diagEntries().map((e) => e.$2),
        contains('停止前台保活服务失败'),
      );
    });
  });

  // =========================================================================
  // I. scheduleExpeditedOneOffPoll / cancelOneOffPoll 边界
  // =========================================================================

  group('I. OneOff 轮询调度与取消边界', () {
    test('I1 sessionId 为空 → 调度与取消都直接早退，不触碰 WorkManager', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await service.scheduleExpeditedOneOffPoll(
        sessionId: '',
        streamId: 'stream-a',
      );
      await service.cancelOneOffPoll('');

      verifyNever(
        () => wm.registerOneOffTask(
          any(),
          any(),
          inputData: any(named: 'inputData'),
          initialDelay: any(named: 'initialDelay'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
          tag: any(named: 'tag'),
          outOfQuotaPolicy: any(named: 'outOfQuotaPolicy'),
          foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
          expedited: any(named: 'expedited'),
        ),
      );
      verifyNever(() => wm.cancelByUniqueName(any()));
    });

    test('I2 streamId null → inputData 里补空串（后端约定非 null）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await service.scheduleExpeditedOneOffPoll(
        sessionId: 'sess-z',
        streamId: null,
      );

      final captured = verify(
        () => wm.registerOneOffTask(
          captureAny(),
          captureAny(),
          inputData: captureAny(named: 'inputData'),
          initialDelay: any(named: 'initialDelay'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
          tag: any(named: 'tag'),
          outOfQuotaPolicy: any(named: 'outOfQuotaPolicy'),
          foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
          expedited: any(named: 'expedited'),
        ),
      ).captured;

      expect(captured[2], {'sessionId': 'sess-z', 'streamId': ''});
    });

    test('I3 registerOneOffTask 抛异常 → 吞掉不外抛（网络/配额失败不打断）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      when(
        () => wm.registerOneOffTask(
          any(),
          any(),
          inputData: any(named: 'inputData'),
          initialDelay: any(named: 'initialDelay'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
          tag: any(named: 'tag'),
          outOfQuotaPolicy: any(named: 'outOfQuotaPolicy'),
          foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
          expedited: any(named: 'expedited'),
        ),
      ).thenThrow(PlatformException(code: 'channel-error'));

      await service.scheduleExpeditedOneOffPoll(
        sessionId: 'sess-z',
        streamId: 'st',
      );

      expect(
        _diagEntries().map((e) => e.$2),
        isNot(contains('调度 WorkManager 加急探活任务')),
      );
    });

    test('I4 cancelOneOffPoll 抛异常 → 吞掉不外抛', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      when(() => wm.cancelByUniqueName(any())).thenThrow(
        PlatformException(code: 'channel-error'),
      );

      await service.cancelOneOffPoll('sess-z');

      verify(() => wm.cancelByUniqueName('hermes-bg-oneoff-sess-z')).called(1);
    });
  });

  // =========================================================================
  // J. recordTurnNotified / isTurnAlreadyNotified 精确语义
  // =========================================================================

  group('J. 回合通知去重记录语义', () {
    test('J1 recordTurnNotified：streamId 与 sessionId 均写 ISO8601 时间戳', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final before = DateTime.now();

      await service.recordTurnNotified(
        sessionId: 's-1',
        streamId: 'st-1',
      );

      final streamVal = prefs.getString('bg_last_notified_stream_st-1');
      final sessionVal = prefs.getString('bg_last_notified_session_s-1');
      expect(streamVal, isNotNull);
      expect(sessionVal, isNotNull);
      expect(streamVal, sessionVal, reason: '同一次记录共用同一时间戳');
      final parsed = DateTime.parse(streamVal!);
      expect(
        parsed.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('J2 recordTurnNotified：streamId 为空/null 只写 session 键；sessionId 为空只写 stream 键',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await service.recordTurnNotified(sessionId: 's-2', streamId: null);
      expect(prefs.getString('bg_last_notified_session_s-2'), isNotNull);
      expect(prefs.getKeys().where((k) => k.contains('stream_')), isEmpty);

      SharedPreferences.setMockInitialValues({});
      final prefs2 = await SharedPreferences.getInstance();
      await service.recordTurnNotified(sessionId: '', streamId: 'st-2');
      expect(prefs2.getString('bg_last_notified_stream_st-2'), isNotNull);
      expect(prefs2.getKeys().where((k) => k.contains('session_')), isEmpty);
    });

    test('J3 recordTurnNotified：两个都空 → 一个键都不写', () async {
      SharedPreferences.setMockInitialValues({});

      await service.recordTurnNotified(sessionId: '', streamId: '');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('J4 isTurnAlreadyNotified：stream 键命中即 true（无 30 秒窗口）', () async {
      final old = DateTime.now().subtract(const Duration(hours: 5));
      SharedPreferences.setMockInitialValues({
        'bg_last_notified_stream_st-old': old.toIso8601String(),
      });

      final notified = await service.isTurnAlreadyNotified(
        sessionId: 's-x',
        streamId: 'st-old',
      );

      expect(notified, isTrue, reason: 'stream 维度只看存在性，不受 30 秒限制');
    });

    test('J5 isTurnAlreadyNotified：session 键 30 秒窗口边界（29s 命中 / 31s 过期）',
        () async {
      final fresh = DateTime.now().subtract(const Duration(seconds: 29));
      SharedPreferences.setMockInitialValues({
        'bg_last_notified_session_s-fresh': fresh.toIso8601String(),
      });
      expect(
        await service.isTurnAlreadyNotified(
          sessionId: 's-fresh',
          streamId: null,
        ),
        isTrue,
      );

      final stale = DateTime.now().subtract(const Duration(seconds: 31));
      SharedPreferences.setMockInitialValues({
        'bg_last_notified_session_s-stale': stale.toIso8601String(),
      });
      expect(
        await service.isTurnAlreadyNotified(
          sessionId: 's-stale',
          streamId: null,
        ),
        isFalse,
      );
    });

    test('J6 isTurnAlreadyNotified：session 键为空串 / 非法时间戳 → 均判 false', () async {
      SharedPreferences.setMockInitialValues({
        'bg_last_notified_session_s-empty': '',
      });
      expect(
        await service.isTurnAlreadyNotified(sessionId: 's-empty', streamId: null),
        isFalse,
        reason: '空串视为未记录',
      );

      SharedPreferences.setMockInitialValues({
        'bg_last_notified_session_s-bad': 'not-a-date',
      });
      expect(
        await service.isTurnAlreadyNotified(sessionId: 's-bad', streamId: null),
        isFalse,
        reason: '解析失败不得误判为已通知',
      );
    });

    test('J7 isTurnAlreadyNotified：sessionId 与 streamId 皆空 → false', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await service.isTurnAlreadyNotified(sessionId: '', streamId: ''),
        isFalse,
      );
    });

    test('J8 isTurnAlreadyNotified 的 stream 键为空串时该维度不命中，回落 session 维度',
        () async {
      SharedPreferences.setMockInitialValues({
        'bg_last_notified_stream_st-blank': '',
        'bg_last_notified_session_s-mix':
            DateTime.now().toIso8601String(),
      });

      expect(
        await service.isTurnAlreadyNotified(
          sessionId: 's-mix',
          streamId: 'st-blank',
        ),
        isTrue,
      );
    });

    test('J9 读配置抛错 → isTurnAlreadyNotified 返回 false（保守：宁可重复通知）',
        () async {
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();

      expect(
        await service.isTurnAlreadyNotified(sessionId: 's', streamId: 'st'),
        isFalse,
      );
    });

    test('J10 写配置抛错 → recordTurnNotified 吞掉不外抛', () async {
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _ThrowingPrefsStore();

      await service.recordTurnNotified(sessionId: 's', streamId: 'st');
    });

    test('J11 桌面平台（非 Android）不做平台早退：去重读写照常工作', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final prefs = await SharedPreferences.getInstance();

      await service.recordTurnNotified(sessionId: 's-d', streamId: 'st-d');
      expect(
        prefs.getString('bg_last_notified_session_s-d'),
        isNotNull,
        reason: '实现观察：去重方法无 _isAndroid 早退，桌面端也落盘',
      );

      expect(
        await service.isTurnAlreadyNotified(
          sessionId: 's-d',
          streamId: 'st-d',
        ),
        isTrue,
      );
    });
  });

  // =========================================================================
  // K. openHyperOsSetting 分支
  // =========================================================================

  group('K. openHyperOsSetting 分支', () {
    test('K1 PackageInfo 通道未绑定 → 走 fallback 包名分支，四个设置项都不抛出', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      // 前提判据：测试环境没注册 package_info 通道 → fromPlatform 必须抛。
      await expectLater(
        PackageInfo.fromPlatform(),
        throwsA(anything),
      );

      for (final type in HyperOsSettingType.values) {
        await service.openHyperOsSetting(type);
      }

      expect(
        _diagEntries().map((e) => e.$2),
        isNot(contains('跳转系统设置页异常')),
      );
    });

    // ⚠️ 顺序敏感：`PackageInfo.setMockInitialValues` 会永久写满
    // `PackageInfo._fromPlatform`（package_info_plus 无 reset API），
    // 因此「成功分支」必须放在「fallback 分支」之后、且本文件内不可再有
    // 依赖 `fromPlatform()` 抛错的前置判据。
    test('K2 PackageInfo 可用 → 走成功分支（不写 fallback 日志），四个设置项都不抛出',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PackageInfo.setMockInitialValues(
        appName: 'Hermes UI',
        packageName: 'com.silentreader.hermes_ui',
        version: '0.0.1',
        buildNumber: '1',
        buildSignature: 'sig',
      );
      expect(
        (await PackageInfo.fromPlatform()).packageName,
        'com.silentreader.hermes_ui',
      );

      for (final type in HyperOsSettingType.values) {
        await service.openHyperOsSetting(type);
      }

      expect(
        _diagEntries().map((e) => e.$2),
        isNot(contains('跳转系统设置页异常')),
      );
    });
  });

  // =========================================================================
  // M. ForegroundTaskWrapper 真实包装（走 flutter_foreground_task 方法通道）
  // =========================================================================

  group('M. ForegroundTaskWrapper 真实包装（flutter_foreground_task/methods）', () {
    final calls = <MethodCall>[];
    var serviceRunning = false;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterForegroundTask.resetStatic();
      // 官方 @visibleForTesting 开关：跳过 5 秒「服务是否真的起来」轮询，
      // 避免测试真等 5s（禁 await Future.delayed 真等）。
      FlutterForegroundTask.skipServiceResponseCheck = true;
      calls.clear();
      serviceRunning = false;
      _mockMethodChannel(_fftMethodsChannel, (call) async {
        calls.add(call);
        if (call.method == 'isRunningService') {
          return serviceRunning;
        }
        return null;
      });
      _initForegroundTask();
    });

    tearDown(() {
      _mockMethodChannel(_fftMethodsChannel, null);
      FlutterForegroundTask.resetStatic();
      debugDefaultTargetPlatformOverride = null;
    });

    test('M1 init 把三组配置原样写进 FlutterForegroundTask 静态态', () {
      expect(FlutterForegroundTask.isInitialized, isTrue);
      final android = FlutterForegroundTask.androidNotificationOptions!;
      expect(android.channelId, 'hermes_foreground_service');
      expect(android.channelName, '后台生成保活');
      expect(
        android.channelImportance,
        NotificationChannelImportance.LOW,
      );
      expect(android.enableVibration, isFalse);
      expect(android.playSound, isFalse);
      expect(android.showWhen, isFalse);
      expect(
        FlutterForegroundTask.iosNotificationOptions!.showNotification,
        isFalse,
      );
      expect(
        FlutterForegroundTask.foregroundTaskOptions!.allowWakeLock,
        isTrue,
      );
      expect(
        FlutterForegroundTask.foregroundTaskOptions!.allowWifiLock,
        isTrue,
      );
      expect(
        FlutterForegroundTask.foregroundTaskOptions!.autoRunOnBoot,
        isFalse,
      );
    });

    test('M2 isRunningService 透传原生返回值（真/假两分支）', () async {
      const wrapper = ForegroundTaskWrapper();

      serviceRunning = false;
      expect(await wrapper.isRunningService, isFalse);

      serviceRunning = true;
      expect(await wrapper.isRunningService, isTrue);

      expect(
        calls.where((c) => c.method == 'isRunningService'),
        hasLength(2),
      );
    });

    test('M3 startService 成功 → 返回 ServiceRequestSuccess，通道收到标题/正文', () async {
      const wrapper = ForegroundTaskWrapper();
      serviceRunning = false;

      final result = await wrapper.startService(
        notificationTitle: 'Hermes',
        notificationText: '1 个会话正在生成',
        callback: foregroundTaskCallback,
      );

      expect(result, isA<ServiceRequestSuccess>());
      final call = calls.firstWhere((c) => c.method == 'startService');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['notificationContentTitle'], 'Hermes');
      expect(args['notificationContentText'], '1 个会话正在生成');
    });

    test('M4 startService 失败 → ServiceRequestFailure 且 error 保留原始异常', () async {
      const wrapper = ForegroundTaskWrapper();
      serviceRunning = false;
      _mockMethodChannel(_fftMethodsChannel, (call) async {
        calls.add(call);
        if (call.method == 'isRunningService') {
          return false;
        }
        throw PlatformException(code: 'start-error', message: 'service denied');
      });

      final result = await wrapper.startService(
        notificationTitle: 'Hermes',
        notificationText: 'x',
      );

      expect(result, isA<ServiceRequestFailure>());
      final error = (result as ServiceRequestFailure).error;
      expect(error, isA<PlatformException>());
      expect((error as PlatformException).code, 'start-error');
    });

    test('M5 startService 在未 init 时 → 失败但由插件内部转成 ServiceRequestFailure', () async {
      FlutterForegroundTask.resetStatic();
      const wrapper = ForegroundTaskWrapper();
      serviceRunning = false;

      final result = await wrapper.startService(
        notificationTitle: 'Hermes',
        notificationText: 'x',
      );

      expect(result, isA<ServiceRequestFailure>());
      expect(
        calls.where((c) => c.method == 'startService'),
        isEmpty,
        reason: '未 init 时不得触达原生通道',
      );
    });

    test('M6 updateService 成功/失败双分支', () async {
      const wrapper = ForegroundTaskWrapper();
      serviceRunning = true;

      final ok = await wrapper.updateService(
        notificationTitle: 'Hermes',
        notificationText: '2 个会话正在生成',
      );
      expect(ok, isA<ServiceRequestSuccess>());
      final call = calls.firstWhere((c) => c.method == 'updateService');
      expect(
        (call.arguments as Map<Object?, Object?>)['notificationContentText'],
        '2 个会话正在生成',
      );

      _mockMethodChannel(_fftMethodsChannel, (call) async {
        calls.add(call);
        if (call.method == 'isRunningService') {
          return true;
        }
        throw PlatformException(code: 'update-error');
      });
      final failed = await wrapper.updateService(
        notificationTitle: 'Hermes',
        notificationText: 'x',
      );
      expect(failed, isA<ServiceRequestFailure>());
      expect(
        (failed as ServiceRequestFailure).error,
        isA<PlatformException>(),
      );
    });

    test('M7 updateService 在服务未运行时 → 失败且不触达通道（插件前置校验）', () async {
      const wrapper = ForegroundTaskWrapper();
      serviceRunning = false;

      final result = await wrapper.updateService(
        notificationTitle: 'Hermes',
        notificationText: 'x',
      );

      expect(result, isA<ServiceRequestFailure>());
      expect(calls.where((c) => c.method == 'updateService'), isEmpty);
    });

    test('M8 stopService 成功/失败双分支', () async {
      const wrapper = ForegroundTaskWrapper();
      serviceRunning = true;

      final ok = await wrapper.stopService();
      expect(ok, isA<ServiceRequestSuccess>());
      expect(calls.any((c) => c.method == 'stopService'), isTrue);

      _mockMethodChannel(_fftMethodsChannel, (call) async {
        calls.add(call);
        if (call.method == 'isRunningService') {
          return true;
        }
        throw PlatformException(code: 'stop-error');
      });
      final failed = await wrapper.stopService();
      expect(failed, isA<ServiceRequestFailure>());
    });

    test('M9 stopService 在服务未运行时 → 失败且不触达通道', () async {
      const wrapper = ForegroundTaskWrapper();
      serviceRunning = false;

      final result = await wrapper.stopService();

      expect(result, isA<ServiceRequestFailure>());
      expect(calls.any((c) => c.method == 'stopService'), isFalse);
    });
  });

  // =========================================================================
  // O. 顶层回调入口（WorkManager / 前台任务）
  // =========================================================================

  group('O. 顶层回调入口', () {
    setUp(() {
      // 前台任务入口会向 background 通道发 'start'，mock 掉避免未处理异常。
      _mockMethodChannel(_fftBackgroundChannel, (call) async => null);
    });

    tearDown(() {
      _mockMethodChannel(_fftBackgroundChannel, null);
    });

    test('O1 foregroundTaskCallback 挂上 TaskHandler 并向后台上通道发 start', () async {
      final started = <MethodCall>[];
      _mockMethodChannel(_fftBackgroundChannel, (call) async {
        started.add(call);
        return null;
      });

      foregroundTaskCallback();
      await pumpEventQueue();

      expect(
        started.map((c) => c.method),
        contains('start'),
        reason: 'setTaskHandler 必须真的把后台通道拉起来（否则前台任务收不到回调）',
      );
    });

    // 说明：`workmanagerCallbackDispatcher` 不做独立用例 —— `Workmanager._flutterApi`
    // 是 `late final`，本 isolate 只能成功调用一次顶层分发器；其握手信号与
    // `executeTask → handleTask` 穿透两条行为断言全部合并在 N35 的同一次调用里
    // （避免留下"存在性即通过"的空用例）。
  });

  // =========================================================================
  // P. MethodChannelWorkManagerRegistrationProbe 通道分支
  // =========================================================================

  group('P. MethodChannelWorkManagerRegistrationProbe 通道分支', () {
    const probe = MethodChannelWorkManagerRegistrationProbe();
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
    });

    tearDown(() {
      _mockMethodChannel(_probeChannel, null);
    });

    test('P1 原生返回完整快照 → 字段逐一映射（含插件链压行）', () async {
      _mockMethodChannel(_probeChannel, (call) async {
        calls.add(call);
        if (call.method == 'probeWorkManager') {
          return <String, Object?>{
            'initialized': true,
            'creation': 'already-initialized',
            'error': null,
          };
        }
        if (call.method == 'probePluginChain') {
          return <String, Object?>{
            'rustLib': 'loaded',
            'urlLauncher': 'true',
            'wakelock': 'true',
            'workmanager': 'true',
          };
        }
        return null;
      });

      final snapshot = await probe.probe();

      expect(
        snapshot.describe(),
        'initialized=true creation=already-initialized '
        'chain=rustLib=loaded urlLauncher=true wakelock=true workmanager=true',
      );
      expect(snapshot.chain, isNotNull);
      expect(calls.map((c) => c.method), [
        'probeWorkManager',
        'probePluginChain',
      ]);
    });

    test('P2 原生返回 initialized=false + error → 与 #110 归因判据一致', () async {
      _mockMethodChannel(_probeChannel, (call) async {
        if (call.method == 'probeWorkManager') {
          return <String, Object?>{
            'initialized': false,
            'creation': 'manual-initialize-failed',
            'error': 'java.lang.IllegalStateException: not initialized',
          };
        }
        return null;
      });

      final snapshot = await probe.probe();

      expect(snapshot.initialized, isFalse);
      expect(snapshot.creation, 'manual-initialize-failed');
      expect(snapshot.error, 'java.lang.IllegalStateException: not initialized');
      expect(snapshot.chain, isNull, reason: '插件链分支缺失时静默降级为 null');
    });

    test('P3 原生返回 null → 降级为 unavailable 且不再调插件链子探针', () async {
      _mockMethodChannel(_probeChannel, (call) async {
        calls.add(call);
        return null;
      });

      final snapshot = await probe.probe();

      expect(snapshot.initialized, isFalse);
      expect(snapshot.creation, 'unavailable');
      expect(snapshot.error, isNull);
      expect(snapshot.chain, isNull);
      expect(
        calls.map((c) => c.method),
        ['probeWorkManager'],
        reason: 'probeWorkManager 为 null 时直接早退，不调 probePluginChain',
      );
    });

    test('P4 通道未注册（抛异常）→ 静默降级 unavailable，不抛出', () async {
      // 不注册任何 handler：MethodChannel 未绑定 → MissingPluginException。
      final snapshot = await probe.probe();

      expect(snapshot.describe(), 'initialized=false creation=unavailable');
    });

    test('P5 插件链探针返回空 Map → chain 为 null（老包不认分支）', () async {
      _mockMethodChannel(_probeChannel, (call) async {
        if (call.method == 'probeWorkManager') {
          return <String, Object?>{'initialized': true};
        }
        return <String, Object?>{};
      });

      final snapshot = await probe.probe();

      expect(snapshot.initialized, isTrue);
      expect(snapshot.chain, isNull);
      expect(snapshot.describe(), 'initialized=true');
    });

    test('P6 插件链探针抛异常 → chain 为 null 但主快照仍在', () async {
      _mockMethodChannel(_probeChannel, (call) async {
        if (call.method == 'probeWorkManager') {
          return <String, Object?>{
            'initialized': false,
            'creation': 'unavailable',
          };
        }
        throw PlatformException(code: 'no-such-method');
      });

      final snapshot = await probe.probe();

      expect(snapshot.initialized, isFalse);
      expect(snapshot.creation, 'unavailable');
      expect(snapshot.chain, isNull);
      expect(snapshot.describe(), 'initialized=false creation=unavailable');
    });

    test('P7 单例默认实现即通道实现（生产接线判据）', () {
      expect(
        WorkManagerRegistrationProbe.instance,
        isA<MethodChannelWorkManagerRegistrationProbe>(),
      );
    });
  });

  // =========================================================================
  // N. handleTask 后台任务执行体（本机 loopback HttpServer，无外网依赖）
  // =========================================================================

  group('N. handleTask 后台任务执行体全分支（loopback HttpServer）', () {
    late _LoopbackServer server;
    late List<MethodCall> notifCalls;
    late List<MethodCall> fftCalls;
    var serviceRunning = false;
    var fftUpdateThrows = false;
    var fftIsRunningThrows = false;
    var notifShowThrows = false;
    var notifCancelThrows = false;
    HttpOverrides? savedHttpOverrides;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      LocaleResolver.reset(mode: AppLocaleMode.zh);
      // ⚠️ flutter_test 的 binding 会装上 `_MockHttpOverrides`：所有 HttpClient
      // 请求固定返回 400 且不发真实网络请求。本组要让 `handleTask` 里的 Dio 走
      // 真实 HTTP 栈打本机 loopback，故临时摘掉它（tearDown 原样还原）。
      savedHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      server = _LoopbackServer();
      await server.start();
      notifCalls = [];
      fftCalls = [];
      serviceRunning = false;
      fftUpdateThrows = false;
      fftIsRunningThrows = false;
      notifShowThrows = false;
      notifCancelThrows = false;

      // flutter_local_notifications 的平台实现是 `static late` 无默认值：
      // 测试环境必须自行装填，否则 resolvePlatformSpecificImplementation 抛
      // LateInitializationError（那只能覆盖 catch 分支，覆盖不到通道分支）。
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();

      _mockMethodChannel(_notificationsChannel, (call) async {
        notifCalls.add(call);
        if (call.method == 'initialize') return true;
        if (call.method == 'show' && notifShowThrows) {
          throw PlatformException(code: 'notif-show-boom');
        }
        if (call.method == 'cancel' && notifCancelThrows) {
          throw PlatformException(code: 'notif-cancel-boom');
        }
        return null;
      });
      _mockMethodChannel(_fftMethodsChannel, (call) async {
        fftCalls.add(call);
        if (call.method == 'isRunningService') {
          if (fftIsRunningThrows) {
            throw PlatformException(code: 'fft-isrunning-boom');
          }
          return serviceRunning;
        }
        if (call.method == 'updateService' && fftUpdateThrows) {
          throw PlatformException(code: 'fft-update-boom');
        }
        return null;
      });
    });

    tearDown(() async {
      _mockMethodChannel(_notificationsChannel, null);
      _mockMethodChannel(_fftMethodsChannel, null);
      await server.stop();
      HttpOverrides.global = savedHttpOverrides;
      debugDefaultTargetPlatformOverride = null;
    });

    Future<Map<String, Object>> prefsWithBaseUrl(
      String? baseUrl, {
      Map<String, Object> extra = const {},
    }) async {
      final values = <String, Object>{...extra};
      if (baseUrl != null) {
        values['bg_active_base_url'] = baseUrl;
      }
      SharedPreferences.setMockInitialValues(values);
      return values;
    }

    test('N1 baseUrl 缺失 → 直接返回 true，一个请求都不发', () async {
      await prefsWithBaseUrl(null);

      expect(await ProductionBackgroundKeepaliveService.handleTask('t', null), isTrue);
      expect(server.paths, isEmpty);
    });

    test('N2 baseUrl 为空串 → 同样早退（不清洗出更空的 base）', () async {
      await prefsWithBaseUrl('');

      expect(await ProductionBackgroundKeepaliveService.handleTask('t', null), isTrue);
      expect(server.paths, isEmpty);
    });

    test('N3 baseUrl 带尾斜杠 → 归一化后请求路径仍为 /health（不出现 //health）', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}/', extra: {
        'bg_foreground_service_enabled': true,
      });
      server.on('/health', (req) => _replyJson(req, {'active_streams': 0}));

      expect(await ProductionBackgroundKeepaliveService.handleTask('t', null), isTrue);
      expect(server.paths, contains('/health'));
    });

    test('N4 保活开 + health 返回 active_streams=2 + 服务在跑 → 常驻通知刷成 2 会话',
        () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_foreground_service_enabled': true,
      });
      serviceRunning = true;
      server.on('/health', (req) => _replyJson(req, {'active_streams': 2}));

      expect(await ProductionBackgroundKeepaliveService.handleTask('t', null), isTrue);

      final update = fftCalls.firstWhere((c) => c.method == 'updateService');
      expect(
        (update.arguments as Map<Object?, Object?>)['notificationContentText'],
        '2 个会话正在生成',
      );
    });

    test('N5 health 返回不含 active_streams → 不刷新常驻通知', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_foreground_service_enabled': true,
      });
      serviceRunning = true;
      server.on('/health', (req) => _replyJson(req, {'ok': true}));

      await ProductionBackgroundKeepaliveService.handleTask('t', null);

      expect(fftCalls.any((c) => c.method == 'updateService'), isFalse);
    });

    test('N6 health 请求失败（404）→ 吞掉异常，主流程继续（开关全关时仍返回 true）',
        () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_foreground_service_enabled': true,
        'notify_turns_enabled': false,
        'notify_clarify_enabled': false,
        'notify_errors_enabled': false,
      });

      expect(await ProductionBackgroundKeepaliveService.handleTask('t', null), isTrue);
      expect(server.paths, contains('/health'));
    });

    test('N7 三类通知开关全关 → 早退为 true，不再打流状态接口', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'notify_turns_enabled': false,
        'notify_clarify_enabled': false,
        'notify_errors_enabled': false,
      });

      expect(await ProductionBackgroundKeepaliveService.handleTask('t', null), isTrue);
      expect(server.paths, isEmpty);
    });

    test('N8 sessionId 与 streamId 都取不到 → 早退为 true', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');

      expect(await ProductionBackgroundKeepaliveService.handleTask('t', null), isTrue);
      expect(server.paths, isEmpty);
    });

    test('N9 terminal_state=clarify → 澄清通知（id/通道/标题/正文/payload 全参数断言）'
        ' + 撤销实况通知 1501 + 清流状态', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));
      final prefs = await SharedPreferences.getInstance();
      const l10n = AppLocalizations(Locale('zh'));

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        ProductionBackgroundKeepaliveService.oneOffTaskName,
        {'sessionId': 'sess-clarify', 'streamId': 'stream-clarify'},
      );

      expect(result, isTrue);
      expect(server.queriesFor('/api/chat/stream/status').first['stream_id'],
          'stream-clarify');

      final show = notifCalls.firstWhere((c) => c.method == 'show');
      final args = show.arguments as Map<Object?, Object?>;
      expect(
        args['id'],
        LocalNotificationsTurnNotificationService.notificationClarifyId,
      );
      expect(args['title'], l10n.clarificationNeeded);
      expect(args['body'], l10n.notifClarifyBody);
      expect(args['payload'], 'sess-clarify');
      final specifics = args['platformSpecifics'] as Map<Object?, Object?>;
      expect(
        specifics['channelId'],
        LocalNotificationsTurnNotificationService.channelClarifyId,
      );
      expect(
        specifics['channelName'],
        LocalNotificationsTurnNotificationService.channelClarifyName,
      );

      // LIVE 兜底撤岛：按固定 ID 直接 cancel（后台 isolate 无自定义通道）
      final cancel = notifCalls.firstWhere((c) => c.method == 'cancel');
      expect(
        (cancel.arguments as Map<Object?, Object?>)['id'],
        LiveUpdateService.kLiveUpdateNotificationId,
      );

      // 去重标记 + 流状态清理
      expect(
        prefs.getString('bg_last_notified_stream_stream-clarify'),
        isNotNull,
      );
      expect(
        prefs.getString('bg_last_notified_session_sess-clarify'),
        isNotNull,
      );
      expect(
        prefs.getString(ProductionBackgroundKeepaliveService.keyActiveStreamId),
        '',
      );
      expect(
        prefs.getBool(ProductionBackgroundKeepaliveService.keyIsStreaming),
        isFalse,
      );
    });

    test('N10 terminal_state=error → 走错误通知分支（errors 通道）', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'error'},
          }));
      const l10n = AppLocalizations(Locale('zh'));

      await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-err', 'streamId': 'st-err'},
      );

      final show = notifCalls.firstWhere((c) => c.method == 'show');
      final args = show.arguments as Map<Object?, Object?>;
      expect(
        args['id'],
        LocalNotificationsTurnNotificationService.notificationErrorsId,
      );
      expect(args['title'], l10n.sessionErrorTitle);
      expect(args['body'], l10n.notifErrorBody);
      expect(
        (args['platformSpecifics'] as Map<Object?, Object?>)['channelId'],
        LocalNotificationsTurnNotificationService.channelErrorsId,
      );
    });

    for (final state in <String>['cancelled', 'interrupted']) {
      test('N11 terminal_state=$state → 归入错误类通知', () async {
        await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
        server.on('/api/chat/stream/status', (req) => _replyJson(req, {
              'active': false,
              'journal': {'terminal': true, 'terminal_state': state},
            }));

        await ProductionBackgroundKeepaliveService.handleTask(
          't',
          {'sessionId': 's-$state', 'streamId': 'st-$state'},
        );

        final show = notifCalls.firstWhere((c) => c.method == 'show');
        expect(
          (show.arguments as Map<Object?, Object?>)['id'],
          LocalNotificationsTurnNotificationService.notificationErrorsId,
        );
      });
    }

    test('N12 terminal_state=clarification_needed → 同样归入澄清类', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {
              'terminal': true,
              'terminal_state': 'clarification_needed',
            },
          }));

      await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-cn', 'streamId': 'st-cn'},
      );

      expect(
        (notifCalls.firstWhere((c) => c.method == 'show').arguments
            as Map<Object?, Object?>)['id'],
        LocalNotificationsTurnNotificationService.notificationClarifyId,
      );
    });

    test('N13 澄清态但 notifyClarify 关 → 落到回合完成通知（不静默丢失）', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'notify_clarify_enabled': false,
      });
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {
              'messages': [
                {'role': 'assistant', 'content': '请选择 A 还是 B'},
              ],
            },
          }));

      await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-nc', 'streamId': 'st-nc'},
      );

      final args = notifCalls.firstWhere((c) => c.method == 'show').arguments
          as Map<Object?, Object?>;
      expect(
        args['id'],
        LocalNotificationsTurnNotificationService.notificationTurnsId,
      );
      expect(
        args['body'],
        LocalNotificationsTurnNotificationService.formatPreview('请选择 A 还是 B'),
      );
    });

    test('N14 错误态但 notifyErrors 关 → 同样落到回合完成通知', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'notify_errors_enabled': false,
      });
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'error'},
          }));
      server.on('/api/session', (req) => _replyJson(req, {
            'messages': [
              {'role': 'assistant', 'content': '已完成'},
            ],
          }));

      await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-ne', 'streamId': 'st-ne'},
      );

      expect(
        (notifCalls.firstWhere((c) => c.method == 'show').arguments
            as Map<Object?, Object?>)['id'],
        LocalNotificationsTurnNotificationService.notificationTurnsId,
      );
    });

    test('N15 默认终态（无 terminal_state）→ 回合完成通知，预览取最后一条非空 assistant 正文',
        () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true},
          }));
      // 逆序扫描：最后一条 assistant + content 非空 生效（tool 结果 / 空正文被跳过）
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {
              'messages': [
                {'role': 'assistant', 'content': '   '},
                {'role': 'user', 'content': '用户提问'},
                {'role': 'assistant', 'content': '最终答案\n换行内容'},
              ],
            },
          }));
      const l10n = AppLocalizations(Locale('zh'));

      await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-turn', 'streamId': 'st-turn'},
      );

      final args = notifCalls.firstWhere((c) => c.method == 'show').arguments
          as Map<Object?, Object?>;
      expect(
        args['id'],
        LocalNotificationsTurnNotificationService.notificationTurnsId,
      );
      expect(args['title'], l10n.notifTurnCompleted);
      expect(
        args['body'],
        LocalNotificationsTurnNotificationService.formatPreview('最终答案\n换行内容'),
        reason: '预览必须单行化（formatPreview）',
      );
      expect(args['body'], '最终答案 换行内容');
      // /api/session 预览查询参数契约
      final q = server.queriesFor('/api/session').first;
      expect(q['session_id'], 's-turn');
      expect(q['messages'], '1');
      expect(q['include_messages'], 'true');
    });

    test('N16 预览拉取失败（/api/session 404）→ 回落 fallback 文案，仍发通知并 return true',
        () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true},
          }));
      const l10n = AppLocalizations(Locale('zh'));

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-fb', 'streamId': 'st-fb'},
      );

      expect(result, isTrue);
      expect(
        (notifCalls.firstWhere((c) => c.method == 'show').arguments
            as Map<Object?, Object?>)['body'],
        l10n.notifTurnFallbackBody,
      );
    });

    test('N17 已通知过去重命中 → 不发任何通知，但仍撤岛 + 清状态 + return true', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_last_notified_stream_st-dup': DateTime.now().toIso8601String(),
      });
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));
      final prefs = await SharedPreferences.getInstance();

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-dup', 'streamId': 'st-dup'},
      );

      expect(result, isTrue);
      expect(notifCalls.any((c) => c.method == 'show'), isFalse);
      expect(
        notifCalls.any(
          (c) =>
              c.method == 'cancel' &&
              (c.arguments as Map<Object?, Object?>)['id'] ==
                  LiveUpdateService.kLiveUpdateNotificationId,
        ),
        isTrue,
        reason: '撤岛在去重判断之外（幂等：对不存在的通知是 no-op）',
      );
      expect(
        prefs.getString(ProductionBackgroundKeepaliveService.keyActiveStreamId),
        '',
      );
    });

    test('N18 流仍 active 且非终态 → 不收尾；随后 /api/session 判定为已结束且曾 streaming → 发回合通知',
        () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_is_streaming': true,
      });
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': true,
            'journal': {'terminal': false},
          }));
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {
              'is_streaming': false,
              'active_stream_id': null,
              'messages': [
                {'role': 'assistant', 'content': '后台完成的回答'},
              ],
            },
          }));
      final prefs = await SharedPreferences.getInstance();

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-live', 'streamId': 'st-live'},
      );

      expect(result, isTrue);
      expect(server.paths, contains('/api/chat/stream/status'));
      expect(server.paths, contains('/api/session'));
      final args = notifCalls.firstWhere((c) => c.method == 'show').arguments
          as Map<Object?, Object?>;
      expect(
        args['id'],
        LocalNotificationsTurnNotificationService.notificationTurnsId,
      );
      expect(args['body'], '后台完成的回答');
      expect(
        prefs.getString('bg_last_notified_session_s-live'),
        isNotNull,
      );
      expect(
        prefs.getBool(ProductionBackgroundKeepaliveService.keyIsStreaming),
        isFalse,
      );
    });

    test('N19 /api/chat/stream/status 请求失败 → return false（触发指数退避）', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's', 'streamId': 'st'},
      );

      expect(result, isFalse);
      expect(notifCalls.any((c) => c.method == 'show'), isFalse);
    });

    test('N20 无 streamId：/api/session 已结束 + 曾 streaming + 未通知 → 发回合通知并清 isStreaming',
        () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_is_streaming': true,
      });
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {
              'is_streaming': false,
              'active_stream_id': '',
              'messages': [
                {'role': 'assistant', 'content': '仅会话维度的完成通知'},
              ],
            },
          }));
      final prefs = await SharedPreferences.getInstance();

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-only'},
      );

      expect(result, isTrue);
      expect(notifCalls.any((c) => c.method == 'show'), isTrue);
      expect(
        prefs.getString('bg_last_notified_session_s-only'),
        isNotNull,
      );
      expect(
        prefs.getBool(ProductionBackgroundKeepaliveService.keyIsStreaming),
        isFalse,
      );
      // 会话维度不应误写 stream 标记
      expect(prefs.getKeys().where((k) => k.contains('stream_')), isEmpty);
    });

    test('N21 无 streamId 但曾未 streaming → 不发通知（避免冷启动误报）', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_is_streaming': false,
      });
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {'is_streaming': false, 'active_stream_id': null},
          }));

      expect(
        await ProductionBackgroundKeepaliveService.handleTask('t', {'sessionId': 's-x'}),
        isTrue,
      );
      expect(notifCalls.any((c) => c.method == 'show'), isFalse);
    });

    test('N22 无 streamId 但会话维度已通知过 → 不发通知', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_is_streaming': true,
        'bg_last_notified_session_s-notified':
            DateTime.now().toIso8601String(),
      });
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {'is_streaming': false, 'active_stream_id': null},
          }));

      expect(
        await ProductionBackgroundKeepaliveService.handleTask(
          't',
          {'sessionId': 's-notified'},
        ),
        isTrue,
      );
      expect(notifCalls.any((c) => c.method == 'show'), isFalse);
    });

    test('N23 无 streamId 但 notifyTurns 关 → 不发通知', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_is_streaming': true,
        'notify_turns_enabled': false,
      });
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {'is_streaming': false, 'active_stream_id': null},
          }));

      expect(
        await ProductionBackgroundKeepaliveService.handleTask('t', {'sessionId': 's-nt'}),
        isTrue,
      );
      expect(notifCalls.any((c) => c.method == 'show'), isFalse);
    });

    test('N24 无 streamId 但会话仍在生成（is_streaming=true）→ 不发通知', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_is_streaming': true,
      });
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {'is_streaming': true, 'active_stream_id': 'st-any'},
          }));

      expect(
        await ProductionBackgroundKeepaliveService.handleTask('t', {'sessionId': 's-st'}),
        isTrue,
      );
      expect(notifCalls.any((c) => c.method == 'show'), isFalse);
    });

    test('N25 /api/session 请求失败 → return false（触发指数退避）', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_is_streaming': true,
      });

      expect(
        await ProductionBackgroundKeepaliveService.handleTask('t', {'sessionId': 's'}),
        isFalse,
      );
    });

    test('N26 inputData 优先于持久化的 sessionId/streamId', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        ProductionBackgroundKeepaliveService.keyActiveSessionId: 'pref-sess',
        ProductionBackgroundKeepaliveService.keyActiveStreamId: 'pref-stream',
      });
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true},
          }));
      server.on('/api/session', (req) => _replyJson(req, {
            'messages': [
              {'role': 'assistant', 'content': 'ok'},
            ],
          }));

      await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 'input-sess', 'streamId': 'input-stream'},
      );

      expect(
        server.queriesFor('/api/chat/stream/status').first['stream_id'],
        'input-stream',
      );
      expect(
        server.queriesFor('/api/session').first['session_id'],
        'input-sess',
      );
    });

    test('N27 顶层兜底 catch：inputData 类型不符 → return false（不抛出）', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      server.on('/health', (req) => _replyJson(req, {'ok': true}));

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        <String, dynamic>{'sessionId': 12345},
      );

      expect(result, isFalse);
    });

    test('N28 app_locale_mode=en → 后台通知标题/正文按英文落盘', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'app_locale_mode': 'en',
      });
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));
      const english = AppLocalizations(Locale('en'));

      await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-en', 'streamId': 'st-en'},
      );

      final args = notifCalls.firstWhere((c) => c.method == 'show').arguments
          as Map<Object?, Object?>;
      expect(args['title'], english.clarificationNeeded);
      expect(args['body'], english.notifClarifyBody);
      expect(LocaleResolver.currentMode, AppLocaleMode.en);

      // 清回默认，避免污染同文件后续用例
      LocaleResolver.reset(mode: AppLocaleMode.zh);
    });

    test('N29 静态入口 BackgroundKeepaliveService.handleWorkManagerTask 委托到 handleTask',
        () async {
      await prefsWithBaseUrl(null);

      expect(
        await BackgroundKeepaliveService.handleWorkManagerTask('t', null),
        isTrue,
      );
      expect(server.paths, isEmpty);
    });

    test('N30 保活开 + 收尾后常驻通知回落为 0 文案（bgFgsEnabled 内层再读一次）',
        () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_foreground_service_enabled': true,
      });
      serviceRunning = true;
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));
      server.on('/health', (req) => _replyJson(req, {'active_streams': 1}));

      await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-bg', 'streamId': 'st-bg'},
      );

      final updates = fftCalls
          .where((c) => c.method == 'updateService')
          .map(
            (c) => (c.arguments as Map<Object?, Object?>)[
                'notificationContentText'],
          )
          .toList();
      expect(updates, ['1 个会话正在生成', '暂无进行中会话']);
    });

    test('N31 收尾时常驻通知链路异常 → 内层 catch 吞掉，主流程仍 return true', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_foreground_service_enabled': true,
      });
      serviceRunning = true;
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));

      // 场景 1：updateService 自身失败 —— 插件内部转成 ServiceRequestFailure 并不抛，
      // 所以这一支不会进本模块的 catch，仅固化「失败不改判任务成败」。
      fftUpdateThrows = true;
      expect(
        await ProductionBackgroundKeepaliveService.handleTask(
          't',
          {'sessionId': 's-fft1', 'streamId': 'st-fft1'},
        ),
        isTrue,
        reason: '常驻通知刷新失败只是增强功能，不得改判任务成败',
      );
      expect(fftCalls.any((c) => c.method == 'updateService'), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('bg_last_notified_stream_st-fft1'),
        isNotNull,
      );

      // 场景 2：isRunningService 抛（该调用在插件里没有 try/catch）→ 才真正进
      // 「WorkManager updateService error」内层 catch。
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_foreground_service_enabled': true,
      });
      fftUpdateThrows = false;
      fftIsRunningThrows = true;
      expect(
        await ProductionBackgroundKeepaliveService.handleTask(
          't',
          {'sessionId': 's-fft1b', 'streamId': 'st-fft1b'},
        ),
        isTrue,
      );

      final prefs2 = await SharedPreferences.getInstance();
      expect(
        prefs2.getString('bg_last_notified_stream_st-fft1b'),
        isNotNull,
      );
    });

    test('N32 会话维度收尾 + 保活开 → 读运行态刷 0 文案；异常走内层 catch', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_foreground_service_enabled': true,
        'bg_is_streaming': true,
      });
      serviceRunning = true;
      server.on('/api/session', (req) => _replyJson(req, {
            'session': {'is_streaming': false, 'active_stream_id': null},
          }));

      final ok = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-fft2'},
      );

      expect(ok, isTrue);
      final update = fftCalls.firstWhere((c) => c.method == 'updateService');
      expect(
        (update.arguments as Map<Object?, Object?>)['notificationContentText'],
        '暂无进行中会话',
      );

      // 再来一次：这次 isRunningService 抛 → 覆盖该分支的内层 catch
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}', extra: {
        'bg_foreground_service_enabled': true,
        'bg_is_streaming': true,
      });
      fftIsRunningThrows = true;
      final second = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-fft3'},
      );
      expect(second, isTrue);
    });

    test('N33 通知插件 show 抛异常 → _showBackgroundNotification 吞掉，任务仍 return true',
        () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      notifShowThrows = true;
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-th', 'streamId': 'st-th'},
      );

      expect(result, isTrue);
      expect(notifCalls.any((c) => c.method == 'show'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('bg_last_notified_stream_st-th'),
        isNotNull,
        reason: '通知失败也照常落去重标记，避免无限重试刷屏',
      );
    });

    test('N34 撤岛 cancel 抛异常 → 吞掉（增强功能不阻断回合通知链路）', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      notifCancelThrows = true;
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));

      final result = await ProductionBackgroundKeepaliveService.handleTask(
        't',
        {'sessionId': 's-th2', 'streamId': 'st-th2'},
      );

      expect(result, isTrue);
      expect(notifCalls.any((c) => c.method == 'cancel'), isTrue);
    });

    test('N35 顶层分发器 → handleTask 端到端：注册期握手 + native executeTask 穿透', () async {
      await prefsWithBaseUrl('http://127.0.0.1:${server.port}');
      server.on('/api/chat/stream/status', (req) => _replyJson(req, {
            'active': false,
            'journal': {'terminal': true, 'terminal_state': 'clarify'},
          }));

      // native 侧等的那次握手信号（pigeon HostApi，Dart→native）
      final handshake = <Object?>[];
      const handshakeChannel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.workmanager_platform_interface.'
        'WorkmanagerHostApi.notifyBackgroundChannelInitialized',
        StandardMessageCodec(),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler<Object?>(
        handshakeChannel,
        (message) async {
          handshake.add(message);
          return <Object?>[null];
        },
      );
      addTearDown(() {
        messenger.setMockDecodedMessageHandler<Object?>(handshakeChannel, null);
      });

      // 1. 走后台 isolate 的启动路径：注册分发器（本 isolate 只允许调用一次）
      workmanagerCallbackDispatcher();
      await pumpEventQueue();

      expect(
        handshake,
        hasLength(1),
        reason: 'executeTask 注册完毕后必须回一次握手，native 才放行 executeTask 回调；'
            '缺这行就意味着后台任务永远收不到任务',
      );

      // 2. 模拟 native 侧调用 pigeon FlutterApi 的 executeTask（native→Dart 方向）
      const codec = StandardMessageCodec();
      final reply = await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'dev.flutter.pigeon.workmanager_platform_interface.'
        'WorkmanagerFlutterApi.executeTask',
        codec.encodeMessage(<Object?>[
          ProductionBackgroundKeepaliveService.oneOffTaskName,
          <String, Object?>{'sessionId': 's-e2e', 'streamId': 'st-e2e'},
        ]),
        null,
      );

      final decoded = codec.decodeMessage(reply) as List<Object?>;
      expect(
        decoded.first,
        isTrue,
        reason: '分发器把 taskName/inputData 原样转给 handleTask，成败必须回传 native',
      );
      expect(server.paths, contains('/api/chat/stream/status'));
      expect(
        (notifCalls.firstWhere((c) => c.method == 'show').arguments
            as Map<Object?, Object?>)['payload'],
        's-e2e',
      );
    });
  });

  // =========================================================================
  // Q. FakeBackgroundKeepaliveService 剩余分支（测试替身自身契约）
  // =========================================================================

  group('Q. FakeBackgroundKeepaliveService 剩余分支', () {
    late FakeBackgroundKeepaliveService fake;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LocaleResolver.reset(mode: AppLocaleMode.zh);
      fake = FakeBackgroundKeepaliveService();
    });

    test('Q1 切后台且 isStreaming=false 但 activeStreamId 非空 → 判为活跃并调度 OneOff',
        () async {
      await fake.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-q',
        activeStreamId: 'stream-q',
        isStreaming: false,
        foregroundServiceEnabled: true,
      );

      expect(fake.currentActiveCount, 1);
      expect(fake.startedForegroundServices, ['sess-q']);
      expect(fake.scheduledOneOffPolls, [('sess-q', 'stream-q')]);
    });

    test('Q2 Fake.startForegroundService 缺省 activeCount 时按 streamId 推导（非空 1 / 空 0）',
        () async {
      await fake.startForegroundService(streamId: 'stream-q');
      expect(fake.currentActiveCount, 1);
      expect(fake.lastOngoingText, '1 个会话正在生成');

      fake.isForegroundServiceRunning = false;
      await fake.startForegroundService();
      expect(fake.currentActiveCount, 0);
      expect(fake.lastOngoingText, '暂无进行中会话');
    });

    test('Q3 Fake.isTurnAlreadyNotified：stream 维与 session 维各自独立命中', () async {
      expect(
        await fake.isTurnAlreadyNotified(sessionId: 's', streamId: 'st'),
        isFalse,
      );

      await fake.recordTurnNotified(sessionId: 'sess-q', streamId: 'stream-q');

      expect(
        await fake.isTurnAlreadyNotified(
          sessionId: 'other',
          streamId: 'stream-q',
        ),
        isTrue,
        reason: 'stream 维度命中即可',
      );
      expect(
        await fake.isTurnAlreadyNotified(sessionId: 'sess-q', streamId: null),
        isTrue,
        reason: 'streamId 为 null 时回落到 session 维度',
      );
      expect(
        await fake.isTurnAlreadyNotified(sessionId: 'nope', streamId: ''),
        isFalse,
      );
    });

    test('Q4 Fake.force 停止清运行态；非 force 只把计数归零', () async {
      await fake.startForegroundService(activeCount: 2);
      expect(fake.isForegroundServiceRunning, isTrue);

      await fake.stopForegroundService(force: false);
      expect(fake.isForegroundServiceRunning, isTrue);
      expect(fake.currentActiveCount, 0);
      expect(fake.lastOngoingText, '暂无进行中会话');

      await fake.stopForegroundService(force: true);
      expect(fake.isForegroundServiceRunning, isFalse);
      expect(fake.lastOngoingText, isNull);
    });
  });

  // =========================================================================
  // L. TaskHandler 契约（#110 家族：前台任务回调必须活着）
  // =========================================================================

  group('L. HermesKeepaliveTaskHandler 契约', () {
    test('L1 四个回调均可调用且幂等（onStart/onRepeatEvent/onDestroy/onStop）', () async {
      final handler = HermesKeepaliveTaskHandler();
      final now = DateTime(2026, 9, 16, 12);

      await handler.onStart(now, TaskStarter.developer);
      handler.onRepeatEvent(now);
      await handler.onDestroy(now);
      handler.onStop();
      // 二次调用（诊断重入）不应抛
      await handler.onStart(now, TaskStarter.developer);
    });
  });
}

// ---------------------------------------------------------------------------
// 共享桩
// ---------------------------------------------------------------------------

/// 平台通道名（与各插件源码里的字面量一一对应）。
const MethodChannel _fftMethodsChannel = MethodChannel(
  'flutter_foreground_task/methods',
);
const MethodChannel _fftBackgroundChannel = MethodChannel(
  'flutter_foreground_task/background',
);
const MethodChannel _notificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const MethodChannel _probeChannel = MethodChannel(
  'com.silentreader.hermes_ui/keepalive_probe',
);

void _mockMethodChannel(
  MethodChannel channel,
  Future<Object?> Function(MethodCall call)? handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}

/// 与 `ProductionBackgroundKeepaliveService.initialize()` 第一步同构的配置。
///
/// 用途：`FlutterForegroundTask.startService/updateService` 有 `isInitialized`
/// 与 `androidNotificationOptions != null` 前置条件，走通道分支前必须先满足。
void _initForegroundTask() {
  const ForegroundTaskWrapper().init(
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
}

/// 本机 loopback HTTP 服务：让 `handleTask` 里的 `Dio` 走真实 HTTP 栈，
/// 但**完全不依赖外网**（绑定 127.0.0.1:0 由内核分配端口）。
class _LoopbackServer {
  late final HttpServer _server;
  final List<String> paths = [];
  final List<Map<String, String>> queries = [];

  final Map<String, Future<void> Function(HttpRequest)> _routes = {};

  int get port => _server.port;

  void on(String path, Future<void> Function(HttpRequest request) responder) {
    _routes[path] = responder;
  }

  List<Map<String, String>> queriesFor(String path) {
    final result = <Map<String, String>>[];
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] == path) {
        result.add(queries[i]);
      }
    }
    return result;
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  Future<void> _serve() async {
    try {
      await for (final request in _server) {
        paths.add(request.uri.path);
        queries.add(request.uri.queryParameters);
        final responder = _routes[request.uri.path];
        if (responder == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }
        try {
          await responder(request);
        } catch (_) {
          // 客户端提前断开等边缘情况：忽略，不影响被测逻辑。
        }
      }
    } catch (_) {
      // close(force: true) 会中断 await for：静默收尾。
    }
  }

  Future<void> stop() => _server.close(force: true);
}

Future<void> _replyJson(HttpRequest request, Map<String, Object?> body) async {
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

void _stubWorkmanager(_MockWorkmanager wm) {
  when(() => wm.initialize(any())).thenAnswer((_) async {});
  when(
    () => wm.registerPeriodicTask(
      any(),
      any(),
      frequency: any(named: 'frequency'),
      flexInterval: any(named: 'flexInterval'),
      inputData: any(named: 'inputData'),
      initialDelay: any(named: 'initialDelay'),
      constraints: any(named: 'constraints'),
      existingWorkPolicy: any(named: 'existingWorkPolicy'),
      backoffPolicy: any(named: 'backoffPolicy'),
      backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
      tag: any(named: 'tag'),
      foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
    ),
  ).thenAnswer((_) async {});
  when(
    () => wm.registerOneOffTask(
      any(),
      any(),
      inputData: any(named: 'inputData'),
      initialDelay: any(named: 'initialDelay'),
      constraints: any(named: 'constraints'),
      existingWorkPolicy: any(named: 'existingWorkPolicy'),
      backoffPolicy: any(named: 'backoffPolicy'),
      backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
      tag: any(named: 'tag'),
      outOfQuotaPolicy: any(named: 'outOfQuotaPolicy'),
      foregroundServiceConfig: any(named: 'foregroundServiceConfig'),
      expedited: any(named: 'expedited'),
    ),
  ).thenAnswer((_) async {});
  when(() => wm.cancelByUniqueName(any())).thenAnswer((_) async {});
}

class _ThrowingRegistrationProbe implements WorkManagerRegistrationProbe {
  @override
  Future<WorkManagerRegistrationSnapshot> probe() async {
    throw MissingPluginException('no implementation found for probeWorkManager');
  }
}
