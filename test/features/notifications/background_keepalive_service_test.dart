import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_service.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_settings_page.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:hermes_ui/features/notifications/workmanager_registration_probe.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(workmanagerCallbackDispatcher);
    registerFallbackValue(const Duration(minutes: 15));
    registerFallbackValue(ExistingPeriodicWorkPolicy.keep);
    registerFallbackValue(BackoffPolicy.exponential);
    registerFallbackValue(Constraints(networkType: NetworkType.connected));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 通知文本随 LocaleResolver 取语言（L2）；钉死中文。
    LocaleResolver.reset(mode: AppLocaleMode.zh);
  });

  group('FakeBackgroundKeepaliveService 生命周期与保活逻辑', () {
    late FakeBackgroundKeepaliveService service;

    setUp(() {
      service = FakeBackgroundKeepaliveService();
    });

    test('初始化后 isInitialized 为 true', () async {
      expect(service.isInitialized, isFalse);
      await service.initialize();
      expect(service.isInitialized, isTrue);
    });

    test('切后台 + 正在流式生成 + 前台服务已开启 → 启动前台服务并调度 OneOff', () async {
      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-123',
        activeStreamId: 'stream-abc',
        isStreaming: true,
        foregroundServiceEnabled: true,
      );

      expect(service.startedForegroundServices, ['sess-123']);
      expect(service.scheduledOneOffPolls, [('sess-123', 'stream-abc')]);
      expect(service.stoppedForegroundServices, isEmpty);
      expect(service.currentActiveCount, 1);
      expect(service.isForegroundServiceRunning, isTrue);
    });

    test('切后台 + 正在流式生成 + 前台服务关闭（默认） → 仅调度 OneOff 探活，不启前台服务', () async {
      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-123',
        activeStreamId: 'stream-abc',
        isStreaming: true,
        foregroundServiceEnabled: false,
      );

      expect(service.startedForegroundServices, isEmpty);
      expect(service.scheduledOneOffPolls, [('sess-123', 'stream-abc')]);
      expect(service.isForegroundServiceRunning, isFalse);
    });

    test('回到前台（resumed） → 取消 OneOff 任务且不停止常驻前台服务', () async {
      service.isForegroundServiceRunning = true;
      await service.onAppLifecycleChanged(
        state: AppLifecycleState.resumed,
        activeSessionId: 'sess-123',
        activeStreamId: null,
        isStreaming: false,
        foregroundServiceEnabled: true,
      );

      // 回到前台不再调用 stopForegroundService，服务保持常驻
      expect(service.isForegroundServiceRunning, isTrue);
      expect(service.cancelledOneOffPolls, ['sess-123']);
      expect(service.currentActiveCount, 0);
    });
  });

  group('开关直启与常驻保活联动（Switch Direct Start/Stop & Persistent）', () {
    test('开关打开 → 立即 startForegroundService（前后台都启），关闭 → 立即 stopForegroundService(force: true)', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final container = ProviderContainer(
        overrides: [
          backgroundKeepaliveServiceProvider.overrideWithValue(fakeKeepalive),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(notificationSettingsProvider.notifier);
      expect(fakeKeepalive.isForegroundServiceRunning, isFalse);

      // 1. 开关打开 → 立即启动前台服务常驻
      await notifier.setBgForegroundServiceEnabled(true);
      expect(fakeKeepalive.startedForegroundServices, hasLength(1));
      expect(fakeKeepalive.isForegroundServiceRunning, isTrue);

      // 2. 开关关闭 → 立即停止前台服务
      await notifier.setBgForegroundServiceEnabled(false);
      expect(fakeKeepalive.stoppedForegroundServices, contains('stopped'));
      expect(fakeKeepalive.isForegroundServiceRunning, isFalse);
    });

    test('流开始/结束 → 文本 0 ↔ N 动态更新，无会话时显示「暂无」且不 stop', () async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();

      // 启动常驻服务（初始无活跃会话，count = 0）
      await fakeKeepalive.startForegroundService(activeCount: 0);
      expect(fakeKeepalive.isForegroundServiceRunning, isTrue);
      expect(fakeKeepalive.currentActiveCount, 0);

      // 流开始：更新为 1 个会话生成中
      await fakeKeepalive.updateNotification(activeCount: 1);
      expect(fakeKeepalive.currentActiveCount, 1);
      expect(fakeKeepalive.isForegroundServiceRunning, isTrue);

      // 多流并发：更新为 2 个会话生成中
      await fakeKeepalive.updateNotification(activeCount: 2);
      expect(fakeKeepalive.currentActiveCount, 2);

      // 流结束：调用非强制 stopForegroundService → 计数归 0，常驻服务不消失
      await fakeKeepalive.stopForegroundService(force: false);
      expect(fakeKeepalive.currentActiveCount, 0);
      expect(fakeKeepalive.isForegroundServiceRunning, isTrue);
    });
  });

  group('常驻通知文本格式化 formatNotificationText', () {
    test('中文格式：0 -> 暂无进行中会话，N -> N 个会话正在生成', () {
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(0),
        '暂无进行中会话',
      );
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(1),
        '1 个会话正在生成',
      );
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(3),
        '3 个会话正在生成',
      );
    });

    test('英文格式：0 -> No active sessions，1 -> 1 session generating，N -> N sessions generating', () {
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(0, isEnglish: true),
        'No active sessions',
      );
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(1, isEnglish: true),
        '1 session generating',
      );
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(2, isEnglish: true),
        '2 sessions generating',
      );
    });
  });

  group('#89 保活常驻通知幂等同步（syncOngoingNotification）', () {
    test('活跃流集合从 0 变 1 → 文案更新为「1 个会话正在生成」；再次传入相同 activeCount (1) → 幂等不重复更新', () async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      await fakeKeepalive.startForegroundService(activeCount: 0);
      fakeKeepalive.updatedNotificationCounts.clear();

      // 活跃流变化：0 -> 1，文案更新一次
      await fakeKeepalive.syncOngoingNotification(1, ['会话 A']);
      expect(fakeKeepalive.currentActiveCount, 1);
      expect(fakeKeepalive.lastOngoingText, '1 个会话正在生成');
      expect(fakeKeepalive.updatedNotificationCounts, [1]);
      expect(fakeKeepalive.syncedOngoingNotifications, hasLength(1));
      expect(fakeKeepalive.syncedOngoingNotifications.first.$1, 1);
      expect(fakeKeepalive.syncedOngoingNotifications.first.$2, ['会话 A']);

      // 活跃流集合无变化（相同 activeCount 与文案）→ 幂等不重复更新 notify
      await fakeKeepalive.syncOngoingNotification(1, ['会话 A']);
      expect(fakeKeepalive.updatedNotificationCounts, [1]);
      expect(fakeKeepalive.syncedOngoingNotifications, hasLength(1));
    });

    test('活跃流集合变化 1 -> 2 -> 0，文案变化各更新一次；不变时幂等不 notify', () async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      await fakeKeepalive.startForegroundService(activeCount: 1);
      fakeKeepalive.updatedNotificationCounts.clear();

      // 1 -> 2: 文案更新
      await fakeKeepalive.syncOngoingNotification(2, ['会话 A', '会话 B']);
      expect(fakeKeepalive.currentActiveCount, 2);
      expect(fakeKeepalive.lastOngoingText, '2 个会话正在生成');
      expect(fakeKeepalive.updatedNotificationCounts, [2]);

      // 2 -> 2: 文案无变化，不重复 notify
      await fakeKeepalive.syncOngoingNotification(2, ['会话 A', '会话 B']);
      expect(fakeKeepalive.updatedNotificationCounts, [2]);

      // 2 -> 0: 文案变为「暂无进行中会话」，更新一次
      await fakeKeepalive.syncOngoingNotification(0, []);
      expect(fakeKeepalive.currentActiveCount, 0);
      expect(fakeKeepalive.lastOngoingText, '暂无进行中会话');
      expect(fakeKeepalive.updatedNotificationCounts, [2, 0]);

      // 0 -> 0: 再次同步 0，幂等不重复 notify
      await fakeKeepalive.syncOngoingNotification(0, []);
      expect(fakeKeepalive.updatedNotificationCounts, [2, 0]);
    });

    test('ProductionBackgroundKeepaliveService 真实幂等逻辑单测（服务未运行不更新，文案相同不重复 updateService）', () async {
      final fakeFg = FakeForegroundTaskWrapper();
      fakeFg.isRunning = true;
      final service = ProductionBackgroundKeepaliveService(
        foregroundTaskWrapper: fakeFg,
      );

      // 1. 首次同步 1 个活跃会话 -> updateService 调用一次
      await service.syncOngoingNotification(1, ['Session 1']);
      expect(fakeFg.updateServiceCallCount, 1);
      expect(fakeFg.lastNotificationText, '1 个会话正在生成');

      // 2. 再次同步相同活跃会话（文案相同） -> 幂等拦截，不调用 updateService
      await service.syncOngoingNotification(1, ['Session 1']);
      expect(fakeFg.updateServiceCallCount, 1);

      // 3. 活跃数变更为 2 -> 文案变化，调用 updateService
      await service.syncOngoingNotification(2, ['Session 1', 'Session 2']);
      expect(fakeFg.updateServiceCallCount, 2);
      expect(fakeFg.lastNotificationText, '2 个会话正在生成');

      // 4. 服务未运行时 -> 不调用 updateService
      fakeFg.isRunning = false;
      await service.syncOngoingNotification(3, ['Session 1', 'Session 2', 'Session 3']);
      expect(fakeFg.updateServiceCallCount, 2);
    });
  });

  group('回合通知去重逻辑（Deduplication）', () {
    late ProductionBackgroundKeepaliveService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = ProductionBackgroundKeepaliveService();
    });

    test('未记录的回合返回 isTurnAlreadyNotified == false', () async {
      final notified = await service.isTurnAlreadyNotified(
        sessionId: 'sess-test',
        streamId: 'stream-test',
      );
      expect(notified, isFalse);
    });

    test('调用 recordTurnNotified 后，同一 streamId 判定为已通知', () async {
      await service.recordTurnNotified(
        sessionId: 'sess-test',
        streamId: 'stream-test',
      );

      final notified = await service.isTurnAlreadyNotified(
        sessionId: 'sess-test',
        streamId: 'stream-test',
      );
      expect(notified, isTrue);

      final otherStreamNotified = await service.isTurnAlreadyNotified(
        sessionId: 'other-sess',
        streamId: 'other-stream',
      );
      expect(otherStreamNotified, isFalse);
    });
  });

  group('NotificationSettings 与持久化', () {
    test('默认 bgForegroundServiceEnabled 为 false', () {
      const settings = NotificationSettings();
      expect(settings.bgForegroundServiceEnabled, isFalse);
      expect(settings.notifyTurnsEnabled, isTrue);
    });

    test('setBgForegroundServiceEnabled 切换并保存至 SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final container = ProviderContainer(
        overrides: [
          backgroundKeepaliveServiceProvider.overrideWithValue(fakeKeepalive),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(notificationSettingsProvider.notifier);
      expect(
        container.read(notificationSettingsProvider).bgForegroundServiceEnabled,
        isFalse,
      );

      await notifier.setBgForegroundServiceEnabled(true);
      expect(
        container.read(notificationSettingsProvider).bgForegroundServiceEnabled,
        isTrue,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('bg_foreground_service_enabled'), isTrue);

      await notifier.setBgForegroundServiceEnabled(false);
      expect(
        container.read(notificationSettingsProvider).bgForegroundServiceEnabled,
        isFalse,
      );
      expect(prefs.getBool('bg_foreground_service_enabled'), isFalse);
    });
  });

  group('HyperOS 设置跳转', () {
    late FakeBackgroundKeepaliveService service;

    setUp(() {
      service = FakeBackgroundKeepaliveService();
    });

    test('打开各个 HyperOS 设置项记录到 openedSettings', () async {
      await service.openHyperOsSetting(HyperOsSettingType.autoStart);
      await service.openHyperOsSetting(HyperOsSettingType.batteryOptimization);
      await service.openHyperOsSetting(HyperOsSettingType.networkControl);
      await service.openHyperOsSetting(HyperOsSettingType.notificationSettings);

      expect(service.openedSettings, [
        HyperOsSettingType.autoStart,
        HyperOsSettingType.batteryOptimization,
        HyperOsSettingType.networkControl,
        HyperOsSettingType.notificationSettings,
      ]);
    });
  });

  group('通知 Hook 与 Keepalive 联动', () {
    test(
      '回合完成 hook 触发时调用 keepalive.recordTurnNotified & stopForegroundService',
      () {
        final fakeKeepalive = FakeBackgroundKeepaliveService();
        final fakeTurnService = _FakeTurnNotificationService();
        final container = ProviderContainer(
          overrides: [
            backgroundKeepaliveServiceProvider.overrideWithValue(fakeKeepalive),
            turnNotificationServiceProvider.overrideWithValue(fakeTurnService),
          ],
        );
        addTearDown(container.dispose);

        container
            .read(appLifecycleStateProvider.notifier)
            .setState(AppLifecycleState.paused);
        final hook = container.read(turnNotificationHookProvider);

        hook('sess-100', 'Title', 'Preview content');

        expect(fakeTurnService.notifyCalls, hasLength(1));
        expect(fakeKeepalive.stoppedForegroundServices, ['stopped']);
        expect(fakeKeepalive.cancelledOneOffPolls, ['sess-100']);
        expect(fakeKeepalive.notifiedRecords, [('sess-100', null)]);
      },
    );
  });

  group('TASK K: 安卓前台服务保活修复（init 顺序/标志位 + callback + 失败可见化）', () {
    late MockWorkmanager mockWm;
    late FakeForegroundTaskWrapper fakeFg;
    late ProductionBackgroundKeepaliveService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockWm = MockWorkmanager();
      fakeFg = FakeForegroundTaskWrapper();
      service = ProductionBackgroundKeepaliveService(
        workmanager: mockWm,
        foregroundTaskWrapper: fakeFg,
      );

      when(() => mockWm.initialize(any())).thenAnswer((_) async {});
      when(
        () => mockWm.registerPeriodicTask(
          any(),
          any(),
          tag: any(named: 'tag'),
          frequency: any(named: 'frequency'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
        ),
      ).thenAnswer((_) async {});
    });

    test('1. init 顺序与分步标志：WorkManager 失败时 fgTask.init 仍完成且 fgTaskReady=true, wmReady=false', () async {
      when(() => mockWm.initialize(any())).thenThrow(
        Exception('WorkManager initialize failed on device'),
      );

      expect(service.fgTaskReady, isFalse);
      expect(service.wmReady, isFalse);
      expect(service.isInitialized, isFalse);

      await service.initialize();

      // FlutterForegroundTask.init 作为第一步已完成
      expect(fakeFg.initCallCount, 1);
      expect(
        fakeFg.capturedAndroidNotificationOptions?.channelId,
        'hermes_foreground_service',
      );
      expect(
        fakeFg.capturedAndroidNotificationOptions?.channelName,
        '后台生成保活',
      );
      expect(service.fgTaskReady, isTrue);
      expect(service.wmReady, isFalse);
      expect(service.isInitialized, isFalse);

      // 再次调用 initialize：WorkManager 恢复后完成重试，且 fgTask 不重复 init
      when(() => mockWm.initialize(any())).thenAnswer((_) async {});
      await service.initialize();

      expect(fakeFg.initCallCount, 1);
      expect(service.fgTaskReady, isTrue);
      expect(service.wmReady, isTrue);
      expect(service.isInitialized, isTrue);
    });

    test('2. startForegroundService 收到非空 callback 参数（foregroundTaskCallback）', () async {
      await service.initialize();
      await service.startForegroundService(activeCount: 1);

      expect(fakeFg.startServiceCallCount, 1);
      expect(fakeFg.lastCallback, isNotNull);
      expect(fakeFg.lastCallback, equals(foregroundTaskCallback));
      expect(fakeFg.lastNotificationTitle, 'Hermes');
      expect(fakeFg.lastNotificationText, contains('1 个会话正在生成'));
    });

    test('3. startForegroundService 失败异常向上冒泡（ServiceRequestFailure 时 throw）', () async {
      await service.initialize();
      fakeFg.startServiceResult = ServiceRequestFailure(
        error: Exception('ServiceTimeoutException: service failed to start within 5s'),
      );

      expect(
        () => service.startForegroundService(activeCount: 1),
        throwsA(isA<Exception>()),
      );
    });

    test('4. 开关失败 → provider 状态回滚 false + error 字段可读', () async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      fakeKeepalive.shouldFailStartForegroundServiceWith = Exception(
        'ServiceNotInitializedException: ForegroundTask not ready',
      );

      final container = ProviderContainer(
        overrides: [
          backgroundKeepaliveServiceProvider.overrideWithValue(fakeKeepalive),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(notificationSettingsProvider.notifier);
      expect(
        container.read(notificationSettingsProvider).bgForegroundServiceEnabled,
        isFalse,
      );
      expect(
        container.read(notificationSettingsProvider).error,
        isNull,
      );

      // 打开开关触发异常
      await notifier.setBgForegroundServiceEnabled(true);

      final settings = container.read(notificationSettingsProvider);
      // 状态回滚为 false
      expect(settings.bgForegroundServiceEnabled, isFalse);
      // error 字段可读
      expect(settings.error, isNotNull);
      expect(
        settings.error,
        contains('ServiceNotInitializedException'),
      );
      expect(settings.keepaliveError, equals(settings.error));

      // 持久化保存也回滚为 false
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('bg_foreground_service_enabled'), isFalse);
    });

    test('5. 冷启动条件拉起路径回归（开关为 true 时拉起，文本根据流状态动态计算）', () async {
      // 开启开关 + 正在流式生成
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
        ProductionBackgroundKeepaliveService.keyIsStreaming: true,
      });

      await service.initialize();

      expect(fakeFg.startServiceCallCount, 1);
      expect(fakeFg.lastCallback, equals(foregroundTaskCallback));
      expect(fakeFg.lastNotificationText, '1 个会话正在生成');
    });

    test('6. 冷启动条件拉起路径回归（开关为 false 时不拉起）', () async {
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': false,
        ProductionBackgroundKeepaliveService.keyIsStreaming: true,
      });

      await service.initialize();

      expect(fakeFg.startServiceCallCount, 0);
    });

    test('7. HermesKeepaliveTaskHandler 契约各方法健全性验证', () async {
      final handler = HermesKeepaliveTaskHandler();
      await handler.onStart(DateTime.now(), TaskStarter.developer);
      handler.onRepeatEvent(DateTime.now());
      await handler.onDestroy(DateTime.now());
      handler.onStop();
    });

    testWidgets('8. UI 就地错误提示展示（开关失败后显示红色错误 Tile）', (tester) async {
      final container = ProviderContainer(
        overrides: [
          notificationSettingsProvider.overrideWith(
            () => _ErrorMockNotificationSettingsNotifier(
              'ServiceNotInitializedException: ForegroundTask not ready',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: BackgroundKeepAliveSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final errorTile = find.byKey(
        const ValueKey('settings-bg-foreground-service-error'),
      );
      expect(errorTile, findsOneWidget);
      expect(find.text('前台保活服务启动失败'), findsOneWidget);
      expect(
        find.text('ServiceNotInitializedException: ForegroundTask not ready'),
        findsOneWidget,
      );
    });
  });

  group('WorkManager 初始化失败归因探针 (#110)', () {
    test('channel-error → 调原生探针并把成因写进诊断说明', () async {
      final probe = _RecordingRegistrationProbe(
        const WorkManagerRegistrationSnapshot(
          initialized: false,
          creation: 'manual-initialize-failed',
          error: 'java.lang.IllegalStateException: WorkManager is not initialized',
        ),
      );
      final service = ProductionBackgroundKeepaliveService(
        registrationProbe: probe,
      );

      final text = await service.describeWorkManagerInitFailure(
        PlatformException(
          code: 'channel-error',
          message:
              'Unable to establish connection on channel: '
              '"dev.flutter.pigeon.workmanager_platform_interface.'
              'WorkmanagerHostApi.initialize"',
        ),
      );

      expect(probe.calls, 1);
      expect(text, contains('channel-error'));
      expect(text, contains('initialized=false'));
      expect(text, contains('creation=manual-initialize-failed'));
      expect(text, contains('WorkManager is not initialized'));
    });

    test('channel-error 但 WorkManager 本身正常 → 说明指向插件注册（陈旧构建/注册期竞态）', () async {
      final probe = _RecordingRegistrationProbe(
        const WorkManagerRegistrationSnapshot(
          initialized: true,
          creation: 'already-initialized',
        ),
      );
      final service = ProductionBackgroundKeepaliveService(
        registrationProbe: probe,
      );

      final text = await service.describeWorkManagerInitFailure(
        PlatformException(code: 'channel-error', message: 'unbound'),
      );

      expect(probe.calls, 1);
      expect(text, contains('initialized=true'));
      expect(text, contains('creation=already-initialized'));
    });

    test('插件链快照（#119）→ 连坐判据一并写进诊断说明', () async {
      // 场景：WorkManager 自身正常，但上游 Rust 插件缺 .so 抛 Error，把
      // GeneratedPluginRegistrant 从中间截断，其后插件全部静默失联。
      // 探针这两项（库能否加载 + 尾部插件在不在）就是判据本身。
      final probe = _RecordingRegistrationProbe(
        const WorkManagerRegistrationSnapshot(
          initialized: true,
          creation: 'already-initialized',
          chain:
              'rustLib=java.lang.UnsatisfiedLinkError: dlopen failed: library '
              '"libsuper_native_extensions.so" not found '
              'urlLauncher=false wakelock=false workmanager=false',
        ),
      );
      final service = ProductionBackgroundKeepaliveService(
        registrationProbe: probe,
      );

      final text = await service.describeWorkManagerInitFailure(
        PlatformException(code: 'channel-error', message: 'unbound'),
      );

      expect(probe.calls, 1);
      expect(text, contains('chain='));
      expect(text, contains('rustLib=java.lang.UnsatisfiedLinkError'));
      expect(text, contains('workmanager=false'));
    });

    test('非 channel-error 失败 → 不调探针、不加说明', () async {
      final probe = _RecordingRegistrationProbe(
        const WorkManagerRegistrationSnapshot(initialized: true),
      );
      final service = ProductionBackgroundKeepaliveService(
        registrationProbe: probe,
      );

      final text = await service.describeWorkManagerInitFailure(
        PlatformException(code: 'constraint-error', message: 'bad constraints'),
      );

      expect(text, isEmpty);
      expect(probe.calls, 0);
    });

    test('探针不可用（通道缺失/原生异常）→ 降级为「探针不可用」且不抛出', () async {
      final service = ProductionBackgroundKeepaliveService(
        registrationProbe: _ThrowingRegistrationProbe(),
      );

      final text = await service.describeWorkManagerInitFailure(
        PlatformException(code: 'channel-error', message: 'unbound'),
      );

      expect(text, contains('channel-error'));
      expect(text, contains('探针不可用'));
    });

    test('快照 describe 拼装（null 字段不出现）', () {
      const snapshot = WorkManagerRegistrationSnapshot(
        initialized: true,
        creation: 'already-initialized',
      );
      expect(
        snapshot.describe(),
        'initialized=true creation=already-initialized',
      );
      expect(
        const WorkManagerRegistrationSnapshot(initialized: false).describe(),
        'initialized=false',
      );
    });
  });
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

class _ThrowingRegistrationProbe implements WorkManagerRegistrationProbe {
  @override
  Future<WorkManagerRegistrationSnapshot> probe() async {
    throw MissingPluginException('no implementation found for probeWorkManager');
  }
}

class MockWorkmanager extends Mock implements Workmanager {}

class FakeForegroundTaskWrapper implements ForegroundTaskWrapper {
  int initCallCount = 0;
  AndroidNotificationOptions? capturedAndroidNotificationOptions;
  IOSNotificationOptions? capturedIosNotificationOptions;
  ForegroundTaskOptions? capturedForegroundTaskOptions;

  bool isRunning = false;
  int startServiceCallCount = 0;
  String? lastNotificationTitle;
  String? lastNotificationText;
  Function? lastCallback;
  ServiceRequestResult startServiceResult = const ServiceRequestSuccess();

  int updateServiceCallCount = 0;
  ServiceRequestResult updateServiceResult = const ServiceRequestSuccess();

  int stopServiceCallCount = 0;
  ServiceRequestResult stopServiceResult = const ServiceRequestSuccess();

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {
    initCallCount++;
    capturedAndroidNotificationOptions = androidNotificationOptions;
    capturedIosNotificationOptions = iosNotificationOptions;
    capturedForegroundTaskOptions = foregroundTaskOptions;
  }

  @override
  Future<bool> get isRunningService async => isRunning;

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
    return updateServiceResult;
  }

  @override
  Future<ServiceRequestResult> stopService() async {
    stopServiceCallCount++;
    if (stopServiceResult is ServiceRequestSuccess) {
      isRunning = false;
    }
    return stopServiceResult;
  }
}

class _ErrorMockNotificationSettingsNotifier
    extends NotificationSettingsNotifier {
  _ErrorMockNotificationSettingsNotifier(this.initialError);
  final String initialError;

  @override
  NotificationSettings build() {
    return NotificationSettings(
      bgForegroundServiceEnabled: false,
      error: initialError,
    );
  }
}

class _FakeTurnNotificationService implements TurnNotificationService {
  final List<(String, String, String)> notifyCalls = [];
  final List<(String, String)> clarifyCalls = [];
  final List<(String, String, String)> errorCalls = [];
  int clearAllCalls = 0;

  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {
    notifyCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {
    clarifyCalls.add((sessionId, question));
  }

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {
    errorCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyDownloadCompleted(
    String downloadId,
    String fileName,
    int byteSize,
  ) async {}
  @override
  Future<void> updateDownloadProgress({
    required String fileName,
    required int receivedBytes,
    required int expectedBytes,
    int queuedCount = 0,
  }) async {}

  @override
  Future<void> clearDownloadProgress() async {}


  @override
  Future<void> clearAll() async {
    clearAllCalls++;
  }

  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<String?> getLaunchSessionId() async => null;

  @override
  Future<bool> requestPermission() async => true;
}
