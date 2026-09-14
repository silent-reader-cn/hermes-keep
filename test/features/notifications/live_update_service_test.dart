import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/features/notifications/live_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #105 安卓 16 实况通知服务单测：MockMethodChannel 驱动，零真实平台通道。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testChannel = MethodChannel('com.silentreader.hermes_ui/live_update');

  late List<MethodCall> calls;

  /// 安装 mock 处理器；[supported] 控制 isSupported 返回值，[showResult]
  /// 控制 show 返回值（null=抛 MissingPluginException 模拟原生缺失），
  /// [cancelThrows] 使 cancel 抛异常模拟原生失败。
  void installMock({
    bool supported = true,
    bool? showResult = true,
    bool cancelThrows = false,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isSupported':
          return supported;
        case 'show':
          if (showResult == null) {
            throw MissingPluginException('no native handler');
          }
          return showResult;
        case 'cancel':
          if (cancelThrows) {
            throw MissingPluginException('no native handler');
          }
          return true;
      }
      return null;
    });
  }

  void clearMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, null);
  }

  setUp(() {
    calls = <MethodCall>[];
    SharedPreferences.setMockInitialValues({});
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    // flutter_test 默认 android；显式钉死防漂移。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    clearMock();
    debugDefaultTargetPlatformOverride = null;
    LocaleResolver.reset();
  });

  group('LiveUpdateService.sync（安卓 16 实况通知）', () {
    test('activeCount=1 且设备支持 → show 一次，文案含「回合进行中」与 chip「生成中」', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);

      expect(calls.map((c) => c.method), ['isSupported', 'show']);
      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['id'], LiveUpdateService.kLiveUpdateNotificationId);
      expect(args['channelId'], LiveUpdateService.kLiveUpdateChannelId);
      expect(args['title'], 'Hermes · 回合进行中');
      expect(args['text'], '会话 A');
      expect(args['shortCriticalText'], '生成中');
      expect(args['indeterminate'], isTrue);
    });

    test('多会话聚合 → 标题带 N 个会话；无有效标题时正文用兜底文案', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 3, titles: ['  ', '会话 B']);
      var args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Hermes · 回合进行中 · 3 个会话');
      expect(args['text'], '会话 B');

      await service.sync(activeCount: 2, titles: const []);
      args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '正在生成回复…');
    });

    test('英文模式 → 标题/正文/chip 全英文（Live ≤6 字符）', () async {
      installMock();
      LocaleResolver.updateMode(AppLocaleMode.en);
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: const []);

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Hermes · Working');
      expect(args['text'], 'Generating reply…');
      expect(args['shortCriticalText'], 'Live');
    });

    test('幂等：同 (title,text) 连续 sync → 第二次不再 notify（无 show 风暴）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);
      await service.sync(activeCount: 1, titles: ['会话 A']);

      expect(calls.where((c) => c.method == 'show'), hasLength(1));
      expect(calls.where((c) => c.method == 'isSupported'), hasLength(1));
    });

    test('文案变化（1→2 个会话）→ 重新 show 一条', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);
      await service.sync(activeCount: 2, titles: ['会话 A', '会话 B']);

      expect(calls.where((c) => c.method == 'show'), hasLength(2));
    });

    test('activeCount=0 → cancel 并清幂等缓存；再次同文案 sync(1) 重新 show', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);
      await service.sync(activeCount: 0);

      expect(calls.map((c) => c.method), ['isSupported', 'show', 'cancel']);

      // cancel 后缓存清空：同文案再同步可重新展示。
      await service.sync(activeCount: 1, titles: ['会话 A']);
      expect(calls.where((c) => c.method == 'show'), hasLength(2));
    });

    test('低版本设备（isSupported=false）→ 不发实况通知（降级无感）', () async {
      installMock(supported: false);
      final service = LiveUpdateService();

      await service.sync(activeCount: 2, titles: ['会话 A', '会话 B']);

      expect(calls.map((c) => c.method), ['isSupported']);
    });

    test('开关关闭（bg_live_update_enabled=false）→ 零通道调用', () async {
      SharedPreferences.setMockInitialValues({
        LiveUpdateService.prefsKeyLiveUpdateEnabled: false,
      });
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);
      await service.sync(activeCount: 0);

      expect(calls, isEmpty);
    });

    test('非 Android 平台 → 静默零调用', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);
      await service.cancelAll();

      expect(calls, isEmpty);
    });

    test('原生通道缺失（MissingPluginException）→ 吞错不抛、缓存不落', () async {
      installMock(showResult: null);
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);
      // show 失败后幂等缓存不应被写入：下一次同步仍会重试 show。
      await service.sync(activeCount: 1, titles: ['会话 A']);

      expect(calls.where((c) => c.method == 'show'), hasLength(2));
    });

    test('cancelAll 幂等且吞错（原生 cancel 失败仅日志，不抛出）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.cancelAll();
      expect(calls.where((c) => c.method == 'cancel'), hasLength(1));

      // 原生 cancel 抛错（模拟通道缺失/原生异常）：吞错且仍可重复调用。
      installMock(cancelThrows: true);
      await service.cancelAll();
      expect(calls.where((c) => c.method == 'cancel'), hasLength(2));
    });
  });
}
