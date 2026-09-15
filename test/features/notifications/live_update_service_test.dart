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

  group('LiveUpdateService.notifyActivity（#120 回合实时活动）', () {
    test('thinking/output → 正文为动作文案，chip 仍为「生成中」', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: '我的会话',
        activity: LiveUpdateActivity.thinking,
      );
      var args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Hermes · 回合进行中');
      expect(args['text'], '正在思考…');
      expect(args['shortCriticalText'], '生成中');
      expect(args['indeterminate'], isTrue);

      await service.notifyActivity(
        sessionId: 's1',
        title: '我的会话',
        activity: LiveUpdateActivity.output,
      );
      args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '正在输出…');
      expect(args['shortCriticalText'], '生成中');
    });

    test('tool 带工具名 → 「正在调用 终端…」（#123 岛上工具名转译）；空名退化为通用文案', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.tool,
        detail: 'terminal',
      );
      var args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '正在调用 终端…');

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.tool,
        detail: '   ',
      );
      args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '正在调用工具…');
    });

    test('等待态 → #48 定稿 chip「请回复」/「请批准」', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.waitingReply,
      );
      var args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '等待你的回复');
      expect(args['shortCriticalText'], '请回复');

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.waitingApproval,
      );
      args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '等待你的批准');
      expect(args['shortCriticalText'], '请批准');
    });

    test('英文模式 → 等待态 chip「Reply」/「Allow」（≤6 字符硬约束）', () async {
      installMock();
      LocaleResolver.updateMode(AppLocaleMode.en);
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.waitingReply,
      );
      var args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['shortCriticalText'], 'Reply');
      expect(
        (args['shortCriticalText']! as String).length,
        lessThanOrEqualTo(6),
      );

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.waitingApproval,
      );
      args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['shortCriticalText'], 'Allow');
      expect(
        (args['shortCriticalText']! as String).length,
        lessThanOrEqualTo(6),
      );
    });

    test('活动优先于列表总览：正文用动作、标题保留多会话计数', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 3, titles: ['会话 A', '会话 B']);
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话 A',
        activity: LiveUpdateActivity.output,
      );

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Hermes · 回合进行中 · 3 个会话');
      expect(args['text'], '正在输出…');
    });

    test('幂等：同活动连续上报 → 只 show 一次', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.thinking,
      );
      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.thinking,
      );

      expect(calls.where((c) => c.method == 'show'), hasLength(1));
    });

    test('activity=null（收尾）→ cancel 且清活动态（列表链路回退总览文案）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.output,
      );
      await service.notifyActivity(sessionId: 's1', title: 't', activity: null);
      expect(calls.where((c) => c.method == 'cancel'), hasLength(1));

      // 活动态已清：多会话场景下由列表链路重新点亮时正文回退为会话标题。
      await service.sync(activeCount: 1, titles: ['会话 A']);
      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '会话 A');
    });

    test('活动态存在时列表报 0 不误撤（列表滞后场景）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);
      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.thinking,
      );
      await service.sync(activeCount: 0);

      expect(calls.where((c) => c.method == 'cancel'), isEmpty);
      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '正在思考…');
    });

    test('开关关闭 → 活动上报零通道调用', () async {
      SharedPreferences.setMockInitialValues({
        LiveUpdateService.prefsKeyLiveUpdateEnabled: false,
      });
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.waitingReply,
      );

      expect(calls, isEmpty);
    });

    test('低版本设备（isSupported=false）→ 活动上报不发通知', () async {
      installMock(supported: false);
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.thinking,
      );

      expect(calls.map((c) => c.method), ['isSupported']);
    });

    test('非 Android 平台 → 活动上报静默零调用', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.thinking,
      );
      await service.notifyActivity(sessionId: 's1', title: 't', activity: null);

      expect(calls, isEmpty);
    });
  });

  group('LiveUpdateService ProgressStyle 增强（#114-P1）', () {
    test(
      'tool 活动连续上报 3 次 → 第 3 次 progressPoints=3，且每次都触发 show（点数驱动幂等刷新）',
      () async {
        installMock();
        final service = LiveUpdateService();

        await service.notifyActivity(
          sessionId: 's1',
          title: '我的会话',
          activity: LiveUpdateActivity.tool,
          detail: 'read_file',
        );
        await service.notifyActivity(
          sessionId: 's1',
          title: '我的会话',
          activity: LiveUpdateActivity.tool,
          detail: 'read_file',
        );
        await service.notifyActivity(
          sessionId: 's1',
          title: '我的会话',
          activity: LiveUpdateActivity.tool,
          detail: 'read_file',
        );

        final showCalls = calls.where((c) => c.method == 'show').toList();
        expect(showCalls, hasLength(3));

        final args1 = showCalls[0].arguments as Map<Object?, Object?>;
        expect(args1['trackerIcon'], 'tool');
        expect(args1['progressPoints'], 1);

        final args2 = showCalls[1].arguments as Map<Object?, Object?>;
        expect(args2['trackerIcon'], 'tool');
        expect(args2['progressPoints'], 2);

        final args3 = showCalls[2].arguments as Map<Object?, Object?>;
        expect(args3['trackerIcon'], 'tool');
        expect(args3['progressPoints'], 3);
      },
    );

    test('不同活动类型 → trackerIcon 键逐态正确（thinking/tool/output/waiting_reply/waiting_approval）', () async {
      installMock();
      final service = LiveUpdateService();

      final states = <LiveUpdateActivity, String>{
        LiveUpdateActivity.thinking: 'thinking',
        LiveUpdateActivity.tool: 'tool',
        LiveUpdateActivity.output: 'output',
        LiveUpdateActivity.waitingReply: 'waiting_reply',
        LiveUpdateActivity.waitingApproval: 'waiting_approval',
      };

      for (final entry in states.entries) {
        await service.notifyActivity(
          sessionId: 's1',
          title: '会话',
          activity: entry.key,
          detail: 'sub',
        );
        final args =
            calls.where((c) => c.method == 'show').last.arguments
                as Map<Object?, Object?>;
        expect(
          args['trackerIcon'],
          entry.value,
          reason: 'Activity ${entry.key} should map to ${entry.value}',
        );
      }
    });

    test(
      '收尾（activity=null）→ 调 cancel，且点数归零；新回合首个 tool 上报时 progressPoints=1',
      () async {
        installMock();
        final service = LiveUpdateService();

        await service.notifyActivity(
          sessionId: 's1',
          title: '回合 1',
          activity: LiveUpdateActivity.tool,
          detail: 'search',
        );
        await service.notifyActivity(
          sessionId: 's1',
          title: '回合 1',
          activity: LiveUpdateActivity.tool,
          detail: 'grep',
        );
        var lastArgs =
            calls.where((c) => c.method == 'show').last.arguments
                as Map<Object?, Object?>;
        expect(lastArgs['progressPoints'], 2);

        // 回合收尾
        await service.notifyActivity(
          sessionId: 's1',
          title: '回合 1',
          activity: null,
        );
        expect(calls.where((c) => c.method == 'cancel'), hasLength(1));

        // 新回合开始，首次 tool 调用
        await service.notifyActivity(
          sessionId: 's2',
          title: '回合 2',
          activity: LiveUpdateActivity.tool,
          detail: 'read',
        );
        lastArgs =
            calls.where((c) => c.method == 'show').last.arguments
                as Map<Object?, Object?>;
        expect(lastArgs['progressPoints'], 1);
      },
    );

    test('点数超过 kMaxProgressPoints → clamp 到上限（不会无限增长）', () async {
      installMock();
      final service = LiveUpdateService();

      for (var i = 0; i < LiveUpdateService.kMaxProgressPoints + 5; i++) {
        await service.notifyActivity(
          sessionId: 's1',
          title: '会话',
          activity: LiveUpdateActivity.tool,
          detail: 'step_$i',
        );
      }

      final lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['progressPoints'], LiveUpdateService.kMaxProgressPoints);
    });

    test('cancelAll 显式调用 → 重置点数与 trackerIconKey', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: '会话',
        activity: LiveUpdateActivity.tool,
      );
      await service.cancelAll();

      await service.sync(activeCount: 1, titles: ['新会话']);
      final lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['progressPoints'], 0);
      expect(lastArgs['trackerIcon'], 'thinking');
    });
  });

  group('LiveUpdateService #123 下载进度上岛与工具名转译', () {
    test('1. 下载上岛参数：notifyDownloadProgress(fileName: a.apk, 42/100) → show 含 indeterminate=false, progressPercent=42, trackerIcon=download, progressPoints=0', () async {
      installMock();
      final service = LiveUpdateService();

      final ok = await service.notifyDownloadProgress(
        fileName: 'a.apk',
        receivedBytes: 42,
        expectedBytes: 100,
      );

      expect(ok, isTrue);
      expect(calls.where((c) => c.method == 'show'), hasLength(1));
      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['indeterminate'], isFalse);
      expect(args['progressPercent'], 42);
      expect(args['trackerIcon'], 'download');
      expect(args['progressPoints'], 0);
      expect(args['shortCriticalText'], '下载中');
      expect(args['text'], '正在下载 a.apk · 42%');
    });

    test('2. 幂等：同 percent 连续两次上报 → 第二次不产生新的 show（7 字段幂等）', () async {
      installMock();
      var now = DateTime(2026, 9, 15, 12, 0, 0);
      final service = LiveUpdateService(now: () => now);

      await service.notifyDownloadProgress(
        fileName: 'a.apk',
        receivedBytes: 42,
        expectedBytes: 100,
      );
      expect(calls.where((c) => c.method == 'show'), hasLength(1));

      // 时间跨越 600ms（避开节流门控），但参数相同
      now = now.add(const Duration(milliseconds: 600));
      await service.notifyDownloadProgress(
        fileName: 'a.apk',
        receivedBytes: 42,
        expectedBytes: 100,
      );

      // 7 字段完全相同，幂等门控生效，不产生第 2 次 show
      expect(calls.where((c) => c.method == 'show'), hasLength(1));
    });

    test(
      '3. 节流：间隔 <500ms 且百分比变化 <1% → 不新增 show；间隔 ≥500ms 或百分比变化 ≥1% → 新增 show',
      () async {
        installMock();
        var now = DateTime(2026, 9, 15, 12, 0, 0);
        final service = LiveUpdateService(now: () => now);

        // 首次调用不受限 → show #1 (10%)
        await service.notifyDownloadProgress(
          fileName: 'app.apk',
          receivedBytes: 10,
          expectedBytes: 100,
        );
        expect(calls.where((c) => c.method == 'show'), hasLength(1));

        // 200ms < 500ms 且百分比未变 (10%) → 节流生效，无新 show
        now = now.add(const Duration(milliseconds: 200));
        await service.notifyDownloadProgress(
          fileName: 'app.apk',
          receivedBytes: 10,
          expectedBytes: 100,
        );
        expect(calls.where((c) => c.method == 'show'), hasLength(1));

        // 100ms（距上次实际推送 300ms < 500ms），但百分比变化 1% (10% → 11%) → 突破节流，show #2
        now = now.add(const Duration(milliseconds: 100));
        await service.notifyDownloadProgress(
          fileName: 'app.apk',
          receivedBytes: 11,
          expectedBytes: 100,
        );
        expect(calls.where((c) => c.method == 'show'), hasLength(2));

        // 600ms ≥ 500ms，百分比变化 1% (11% → 12%) → show #3
        now = now.add(const Duration(milliseconds: 600));
        await service.notifyDownloadProgress(
          fileName: 'app.apk',
          receivedBytes: 12,
          expectedBytes: 100,
        );
        expect(calls.where((c) => c.method == 'show'), hasLength(3));

        // 100ms < 500ms 且百分比未变 (12%) → 节流生效，无新 show
        now = now.add(const Duration(milliseconds: 100));
        await service.notifyDownloadProgress(
          fileName: 'app.apk',
          receivedBytes: 12,
          expectedBytes: 100,
        );
        expect(calls.where((c) => c.method == 'show'), hasLength(3));
      },
    );

    test('4. 优先级-等待态抢占与自然回落：tool → download → waitingApproval 抢占 → 撤销后自然回落 download', () async {
      installMock();
      final service = LiveUpdateService();

      // 先上报 tool 活动
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话',
        activity: LiveUpdateActivity.tool,
        detail: 'read_file',
      );
      var lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['text'], contains('读取文件'));

      // 再上报下载进度 → 下载压过普通回合活动
      await service.notifyDownloadProgress(
        fileName: 'tool_output.bin',
        receivedBytes: 30,
        expectedBytes: 100,
      );
      lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['text'], '正在下载 tool_output.bin · 30%');
      expect(lastArgs['shortCriticalText'], '下载中');

      // 再上报 waitingApproval → 最高优先级抢占一切
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话',
        activity: LiveUpdateActivity.waitingApproval,
      );
      lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['text'], '等待你的批准');
      expect(lastArgs['shortCriticalText'], '请批准');

      // 等待态撤销（activity = null）→ 下载字段保留，自然回落下载态
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话',
        activity: null,
      );
      lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['text'], '正在下载 tool_output.bin · 30%');
      expect(lastArgs['shortCriticalText'], '下载中');
      expect(lastArgs['indeterminate'], isFalse);
      expect(lastArgs['progressPercent'], 30);
    });

    test(
      '5. 优先级-下载压过回合：thinking 活动存在时 notifyDownloadProgress → 岛显示下载文案',
      () async {
        installMock();
        final service = LiveUpdateService();

        await service.notifyActivity(
          sessionId: 's1',
          title: '会话',
          activity: LiveUpdateActivity.thinking,
        );
        var lastArgs =
            calls.where((c) => c.method == 'show').last.arguments
                as Map<Object?, Object?>;
        expect(lastArgs['text'], '正在思考…');

        await service.notifyDownloadProgress(
          fileName: 'model.onnx',
          receivedBytes: 50,
          expectedBytes: 100,
        );
        lastArgs =
            calls.where((c) => c.method == 'show').last.arguments
                as Map<Object?, Object?>;
        expect(lastArgs['text'], '正在下载 model.onnx · 50%');
        expect(lastArgs['shortCriticalText'], '下载中');
      },
    );

    test(
      '6. 总大小未知：expectedBytes: -1 → indeterminate == true、文案为 UnknownSize 版本',
      () async {
        installMock();
        final service = LiveUpdateService();

        await service.notifyDownloadProgress(
          fileName: 'stream.dat',
          receivedBytes: 2048,
          expectedBytes: -1,
        );

        final lastArgs =
            calls.where((c) => c.method == 'show').last.arguments
                as Map<Object?, Object?>;
        expect(lastArgs['indeterminate'], isTrue);
        expect(lastArgs['progressPercent'], 0);
        expect(lastArgs['text'], '正在下载 stream.dat');
        expect(lastArgs['shortCriticalText'], '下载中');
        expect(lastArgs['trackerIcon'], 'download');
      },
    );

    test(
      '7. 终态清理：clearDownloadProgress() → 有回合活动时回落回合文案；无任何活动时 cancel 被调用',
      () async {
        installMock();
        final serviceWithActivity = LiveUpdateService();

        // Case A: 有回合活动
        await serviceWithActivity.notifyActivity(
          sessionId: 's1',
          title: '会话',
          activity: LiveUpdateActivity.thinking,
        );
        await serviceWithActivity.notifyDownloadProgress(
          fileName: 'temp.zip',
          receivedBytes: 10,
          expectedBytes: 100,
        );
        expect(calls.last.arguments['text'], '正在下载 temp.zip · 10%');

        // 清除下载进度 → 自然回落到 thinking
        await serviceWithActivity.clearDownloadProgress();
        expect(calls.last.arguments['text'], '正在思考…');

        // Case B: 无任何活动
        final emptyService = LiveUpdateService();
        await emptyService.notifyDownloadProgress(
          fileName: 'standalone.apk',
          receivedBytes: 80,
          expectedBytes: 100,
        );
        expect(calls.where((c) => c.method == 'show'), isNotEmpty);
        final cancelCountBefore = calls
            .where((c) => c.method == 'cancel')
            .length;

        // 清除下载进度且无其他活动 → 调 cancel
        await emptyService.clearDownloadProgress();
        expect(
          calls.where((c) => c.method == 'cancel').length,
          cancelCountBefore + 1,
        );
      },
    );

    test('8. 工具名转译：detail = read_file → 「读取文件」；mcp__foo__bar → 「外部工具」；detail = 空 → 「正在调用工具…」', () async {
      installMock();
      final service = LiveUpdateService();

      // read_file → 读取文件
      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.tool,
        detail: 'read_file',
      );
      var lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['text'], contains('读取文件'));

      // mcp__ 前缀 → 外部工具
      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.tool,
        detail: 'mcp__foo__bar',
      );
      lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['text'], contains('外部工具'));

      // 空串 → 正在调用工具…
      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.tool,
        detail: '   ',
      );
      lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['text'], '正在调用工具…');
    });

    test('9. 7 字段透传断言：show 调用同时携带 title/text/chip/trackerIcon/progressPoints/indeterminate/progressPercent', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyDownloadProgress(
        fileName: 'verify.tar.gz',
        receivedBytes: 75,
        expectedBytes: 100,
        queuedCount: 2,
      );

      final lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['id'], LiveUpdateService.kLiveUpdateNotificationId);
      expect(lastArgs['channelId'], LiveUpdateService.kLiveUpdateChannelId);
      expect(lastArgs['title'], isA<String>());
      expect(lastArgs['text'], '正在下载 verify.tar.gz · 75% · 还有 2 个');
      expect(lastArgs['shortCriticalText'], '下载中');
      expect(lastArgs['trackerIcon'], 'download');
      expect(lastArgs['progressPoints'], 0);
      expect(lastArgs['indeterminate'], false);
      expect(lastArgs['progressPercent'], 75);
    });

    test('10. 非 Android 或 isSupported=false 时：notifyDownloadProgress 返回 false 且不产生平台 show', () async {
      installMock(supported: false);
      final service = LiveUpdateService();

      final supported = await service.notifyDownloadProgress(
        fileName: 'test.apk',
        receivedBytes: 50,
        expectedBytes: 100,
      );
      expect(supported, isFalse);
      expect(calls.where((c) => c.method == 'show'), isEmpty);

      final nonAndroidService = LiveUpdateService(
        androidPlatformOverride: false,
      );
      final nonAndroidOk = await nonAndroidService.notifyDownloadProgress(
        fileName: 'test.apk',
        receivedBytes: 50,
        expectedBytes: 100,
      );
      expect(nonAndroidOk, isFalse);
    });

    test('11. 英文模式下的下载文案与 Chip 验证（Save ≤ 6 字符）', () async {
      installMock();
      LocaleResolver.updateMode(AppLocaleMode.en);
      final service = LiveUpdateService();

      await service.notifyDownloadProgress(
        fileName: 'english.pdf',
        receivedBytes: 25,
        expectedBytes: 100,
        queuedCount: 1,
      );

      final lastArgs =
          calls.where((c) => c.method == 'show').last.arguments
              as Map<Object?, Object?>;
      expect(lastArgs['title'], 'Hermes · Working');
      expect(lastArgs['text'], 'Downloading english.pdf · 25% · +1 queued');
      expect(lastArgs['shortCriticalText'], 'Save');
    });
  });
}
