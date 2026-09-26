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
    test('B 案身份优先：列表会话标题上位 title，正文退为通用状态文案', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);

      expect(calls.map((c) => c.method), ['isSupported', 'show']);
      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['id'], LiveUpdateService.kLiveUpdateNotificationId);
      expect(args['channelId'], LiveUpdateService.kLiveUpdateChannelId);
      expect(args['title'], '会话 A');
      expect(args['text'], '正在生成回复…');
      expect(args['shortCriticalText'], '生成中');
      expect(args['indeterminate'], isTrue);
      expect(args['subText'], isNull);
    });

    test('多会话且无标题明细 → title 回退通用文案；有标题时标题上位', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 3, titles: ['  ', '会话 B']);
      var args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], '会话 B');
      expect(args['text'], '正在生成回复…');
      // 明细里除「会话 B」外只剩空白项 → 与身份不同的非空标题数为 0。
      expect(args['subText'], isNull);

      await service.sync(activeCount: 2, titles: const []);
      args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Hermes · 回合进行中 · 2 个会话');
      expect(args['text'], '正在生成回复…');
      expect(args['subText'], isNull);
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
      expect(args['title'], '我的会话');
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

    test('活动优先于列表总览：身份用活动会话标题，其余会话数落 subText', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 3, titles: ['会话 A', '会话 B']);
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话 A',
        activity: LiveUpdateActivity.output,
      );

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], '会话 A');
      expect(args['text'], '正在输出…');
      expect(args['subText'], '另有 1 个会话');
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

      // 活动态已清：列表链路重新点亮时，会话标题落在 title（B 案身份优先）。
      await service.sync(activeCount: 1, titles: ['会话 A']);
      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], '会话 A');
      expect(args['text'], '正在生成回复…');
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
      'B 案停用工具落点：同工具连续上报 3 次 → 不透传 progressPoints，字段全同故幂等只 show 一次',
      () async {
        installMock();
        final service = LiveUpdateService();

        for (var i = 0; i < 3; i++) {
          await service.notifyActivity(
            sessionId: 's1',
            title: '我的会话',
            activity: LiveUpdateActivity.tool,
            detail: 'read_file',
          );
        }

        // #114 的「点数驱动刷新」随落点一起停用：幂等键回到纯文案比对，
        // tool 重复上报（同工具名）不再制造平台通道调用。
        final showCalls = calls.where((c) => c.method == 'show').toList();
        expect(showCalls, hasLength(1));

        final args = showCalls.single.arguments as Map<Object?, Object?>;
        expect(args['trackerIcon'], 'tool');
        expect(args['title'], '我的会话');
        expect(args.containsKey('progressPoints'), isFalse);
      },
    );

    test('不同活动类型 → trackerIcon 键逐态正确（含 #129 已完成/已中断）', () async {
      installMock();
      final service = LiveUpdateService();

      final states = <LiveUpdateActivity, String>{
        LiveUpdateActivity.thinking: 'thinking',
        LiveUpdateActivity.tool: 'tool',
        LiveUpdateActivity.output: 'output',
        LiveUpdateActivity.waitingReply: 'waiting_reply',
        LiveUpdateActivity.waitingApproval: 'waiting_approval',
        LiveUpdateActivity.completed: 'completed',
        LiveUpdateActivity.interrupted: 'interrupted',
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

    test('#129 完成态 → #48 定稿 chip「已完成」+ 确定进度条 100%（满载=完成）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.completed,
      );

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '回合已完成');
      expect(args['shortCriticalText'], '已完成');
      expect(args['trackerIcon'], 'completed');
      // 完成态不再是 indeterminate 转圈，而是确定进度条满载：语义即「已完成」。
      expect(args['indeterminate'], isFalse);
      expect(args['progressPercent'], 100);
    });

    test('#129 中断态 → #48 定稿 chip「已中断」+ 保持 indeterminate（不伪造进度）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.interrupted,
      );

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], '回合已中断');
      expect(args['shortCriticalText'], '已中断');
      expect(args['trackerIcon'], 'interrupted');
      expect(args['indeterminate'], isTrue);
    });

    test('#129 英文模式 → 完成/中断 chip「Done」/「Stop」（≤6 字符硬约束）', () async {
      installMock();
      LocaleResolver.updateMode(AppLocaleMode.en);
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.completed,
      );
      var args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], 'Turn completed');
      expect(args['shortCriticalText'], 'Done');
      expect(
        (args['shortCriticalText']! as String).length,
        lessThanOrEqualTo(6),
      );

      await service.notifyActivity(
        sessionId: 's1',
        title: 't',
        activity: LiveUpdateActivity.interrupted,
      );
      args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['text'], 'Turn interrupted');
      expect(args['shortCriticalText'], 'Stop');
      expect(
        (args['shortCriticalText']! as String).length,
        lessThanOrEqualTo(6),
      );
    });

    test(
      'B 案收尾（activity=null）→ 调 cancel 并清空活动身份，新回合身份切新',
      () async {
        installMock();
        final service = LiveUpdateService();

        await service.notifyActivity(
          sessionId: 's1',
          title: '回合 1',
          activity: LiveUpdateActivity.tool,
          detail: 'search',
        );
        var lastArgs =
            calls.where((c) => c.method == 'show').last.arguments
                as Map<Object?, Object?>;
        expect(lastArgs['title'], '回合 1');

        // 回合收尾
        await service.notifyActivity(
          sessionId: 's1',
          title: '回合 1',
          activity: null,
        );
        expect(calls.where((c) => c.method == 'cancel'), hasLength(1));

        // 新回合开始：身份切到新会话，不与上一回合串味。
        await service.notifyActivity(
          sessionId: 's2',
          title: '回合 2',
          activity: LiveUpdateActivity.tool,
          detail: 'read',
        );
        lastArgs =
            calls.where((c) => c.method == 'show').last.arguments
                as Map<Object?, Object?>;
        expect(lastArgs['title'], '回合 2');
      },
    );

    test('B 案落点整套停用：连续多轮工具调用后 show 参数里始终没有 progressPoints 键', () async {
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

      final showCalls = calls.where((c) => c.method == 'show').toList();
      expect(showCalls, isNotEmpty);
      for (final call in showCalls) {
        final args = call.arguments as Map<Object?, Object?>;
        expect(args.containsKey('progressPoints'), isFalse);
      }
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
      // B 案：cancelAll 清空活动身份，下一次列表链路上报由列表标题接手 title。
      expect(lastArgs['title'], '新会话');
      expect(lastArgs['trackerIcon'], 'thinking');
      expect(lastArgs.containsKey('progressPoints'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // B 案「身份优先 + 状态着色」（2026-09-19，主人拍板；真机取证驱动）
  //
  // 病灶：展开态最大字号位长期被恒定文案「Hermes · 回合进行中」占死，而 chat 侧
  // 一路传上来的会话标题在服务层被丢弃 —— 用户看不出是哪个会话在跑；同时真机
  // 显示小米超级岛会自行在头部显示 App 名与计时器，任何再放 App 名的做法只会
  // 让一屏出现两遍「Hermes」。
  // -------------------------------------------------------------------------
  group('B 案身份优先与 subText（2026-09-19）', () {
    test('活动会话标题上位 title（此前该参数被丢弃）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyActivity(
        sessionId: 's1',
        title: '重构 SSE 重连逻辑',
        activity: LiveUpdateActivity.thinking,
      );

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], '重构 SSE 重连逻辑');
      expect(args['text'], '正在思考…');
      // 单会话：不占 subText 槽。
      expect(args['subText'], isNull);
    });

    test('无实时活动 → 列表链路首个标题上位 title，正文退为通用状态文案', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 1, titles: ['会话 A']);

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], '会话 A');
      expect(args['text'], '正在生成回复…');
      expect(args['subText'], isNull);
    });

    test('身份与标题明细都缺失 → 回退通用文案，且 subText 不重复计数', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 3);

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Hermes · 回合进行中 · 3 个会话');
      expect(args['text'], '正在生成回复…');
      // title 已含计数 —— 再报一次「另有」等于同一句话占两处。
      expect(args['subText'], isNull);
    });

    test('多会话：身份留 title、其余会话数落 subText，且不含 App 名', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 3, titles: ['会话 A', '会话 B', '会话 C']);
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话 A',
        activity: LiveUpdateActivity.output,
      );

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], '会话 A');
      expect(args['subText'], '另有 2 个会话');
      // App 名由系统头部显示，subText 再放会让一屏出现两遍「Hermes」。
      expect(args['subText'], isNot(contains('Hermes')));
    });

    test('当前身份不在列表明细内 → 不把自己算成「另有」', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 2, titles: ['会话 B', '会话 C']);
      await service.notifyActivity(
        sessionId: 's9',
        title: '会话 A',
        activity: LiveUpdateActivity.thinking,
      );

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], '会话 A');
      expect(args['subText'], '另有 2 个会话');
    });

    test('英文模式 subText 按单复数分流', () async {
      installMock();
      LocaleResolver.updateMode(AppLocaleMode.en);
      final service = LiveUpdateService();

      await service.sync(activeCount: 2, titles: ['A', 'B']);
      await service.notifyActivity(
        sessionId: 's1',
        title: 'A',
        activity: LiveUpdateActivity.thinking,
      );
      var args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['subText'], '1 more session');

      await service.sync(activeCount: 4, titles: ['A', 'B', 'C', 'D']);
      await service.notifyActivity(
        sessionId: 's1',
        title: 'A',
        activity: LiveUpdateActivity.output,
      );
      args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['subText'], '3 more sessions');
    });

    test('等待态同样带身份与 subText（报警态不丢上下文）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 2, titles: ['会话 A', '会话 B']);
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话 A',
        activity: LiveUpdateActivity.waitingApproval,
      );

      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['title'], '会话 A');
      expect(args['subText'], '另有 1 个会话');
      expect(args['shortCriticalText'], '请批准');
    });

    test('subText 变化单独触发刷新（幂等键已含该字段）', () async {
      installMock();
      final service = LiveUpdateService();

      await service.sync(activeCount: 2, titles: ['会话 A', '会话 B']);
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话 A',
        activity: LiveUpdateActivity.thinking,
      );
      // 列表链路 1 次（正文为通用状态）+ 活动上报 1 次（正文为动作）。
      expect(calls.where((c) => c.method == 'show'), hasLength(2));

      // 第三条会话进入 → 仅 subText 变化即须重发（幂等键已含该字段）。
      await service.sync(activeCount: 3, titles: ['会话 A', '会话 B', '会话 C']);
      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['subText'], '另有 2 个会话');
      expect(calls.where((c) => c.method == 'show'), hasLength(3));
    });
  });

  group('LiveUpdateService #123 下载进度上岛与工具名转译', () {
    test('1. 下载上岛参数：notifyDownloadProgress(fileName: a.apk, 42/100) → show 含 indeterminate=false, progressPercent=42, trackerIcon=download', () async {
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
      expect(args.containsKey('progressPoints'), isFalse);
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

    test('9. 字段透传断言：show 调用同时携带 title/text/chip/trackerIcon/subText/indeterminate/progressPercent', () async {
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
      // 无多会话信息时不占 subText 槽（键存在但为空）。
      expect(lastArgs['subText'], isNull);
      expect(lastArgs.containsKey('progressPoints'), isFalse);
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

  group('LiveUpdateService #158 下载完成态上岛', () {
    /// 轮询等待（窗口到期由 Timer 回调异步刷新，避免用例对固定 sleep 敏感）。
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 60; i++) {
        if (condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    Map<Object?, Object?> lastShowArgs() =>
        calls.where((c) => c.method == 'show').last.arguments
            as Map<Object?, Object?>;

    int showCount() => calls.where((c) => c.method == 'show').length;

    int cancelCount() => calls.where((c) => c.method == 'cancel').length;

    test(
      '1. 完成上岛参数：notifyDownloadCompleted → 「{文件名} 下载完成」+ chip 已完成 + 确定进度条 100%',
      () async {
        installMock();
        final service = LiveUpdateService();

        await service.notifyDownloadCompleted(fileName: 'hermes-0.1.57.apk');

        final args = lastShowArgs();
        expect(args['text'], 'hermes-0.1.57.apk 下载完成');
        expect(args['shortCriticalText'], '已完成');
        expect(args['trackerIcon'], 'completed');
        expect(args['indeterminate'], isFalse);
        expect(args['progressPercent'], 100);
        await service.cancelAll();
      },
    );

    test('2. 英文模式：text「{fileName} downloaded」+ chip Done（≤6 字符）', () async {
      installMock();
      LocaleResolver.updateMode(AppLocaleMode.en);
      final service = LiveUpdateService();

      await service.notifyDownloadCompleted(fileName: 'english.pdf');

      final args = lastShowArgs();
      expect(args['text'], 'english.pdf downloaded');
      expect(args['shortCriticalText'], 'Done');
      expect(
        args['shortCriticalText'].toString().length,
        lessThanOrEqualTo(6),
        reason: '状态栏 chip 硬限 6 字符（#48 定稿）',
      );
      await service.cancelAll();
    });

    test(
      '3. 完成态压过进行中进度，且下载链路既有的 clearDownloadProgress 不抹掉完成提示',
      () async {
        installMock();
        final service = LiveUpdateService();

        await service.notifyDownloadProgress(
          fileName: 'big.apk',
          receivedBytes: 50,
          expectedBytes: 100,
        );
        expect(lastShowArgs()['text'], '正在下载 big.apk · 50%');

        await service.notifyDownloadCompleted(fileName: 'big.apk');
        expect(lastShowArgs()['text'], 'big.apk 下载完成');

        // 下载链路（download_controller 两条完成路径）既有调用序：
        // notifyDownloadCompleted 紧跟 clearDownloadProgress —— 后者只清「进行中」，
        // 完成提示必须活着（这正是此前「下载完成没有岛提示」的根因）。
        await service.clearDownloadProgress();
        expect(lastShowArgs()['text'], 'big.apk 下载完成');
        expect(cancelCount(), 0);
        await service.cancelAll();
      },
    );

    test('4. 停留窗口到期：无其他活动 → 原生 cancel 撤岛', () async {
      installMock();
      final service = LiveUpdateService(
        downloadCompletedDwell: const Duration(milliseconds: 30),
      );

      await service.notifyDownloadCompleted(fileName: 'done.apk');
      expect(showCount(), 1);
      expect(cancelCount(), 0);

      await waitFor(() => cancelCount() == 1);
      expect(cancelCount(), 1, reason: '窗口到期须撤岛，不能永久停在「已完成」');
      await service.cancelAll();
    });

    test('5. 停留窗口到期：有回合活动在跑 → 自然回落回合文案而非撤岛', () async {
      installMock();
      final service = LiveUpdateService(
        downloadCompletedDwell: const Duration(milliseconds: 30),
      );

      await service.notifyActivity(
        sessionId: 's1',
        title: '会话',
        activity: LiveUpdateActivity.tool,
        detail: 'read_file',
      );
      await service.notifyDownloadCompleted(fileName: 'done.apk');
      expect(lastShowArgs()['text'], 'done.apk 下载完成');

      await waitFor(() => lastShowArgs()['text'] != 'done.apk 下载完成');
      expect(lastShowArgs()['text'], contains('读取文件'));
      expect(cancelCount(), 0, reason: '仍有回合活动时不应撤岛');
      await service.cancelAll();
    });

    test('6. 等待态抢占：完成提示停留期间 waitingApproval 上位', () async {
      installMock();
      final service = LiveUpdateService();

      await service.notifyDownloadCompleted(fileName: 'a.apk');
      await service.notifyActivity(
        sessionId: 's1',
        title: '会话',
        activity: LiveUpdateActivity.waitingApproval,
      );

      final args = lastShowArgs();
      expect(args['text'], '等待你的批准');
      expect(args['shortCriticalText'], '请批准');
      await service.cancelAll();
    });

    test('7. cancelAll 一并清完成态与到期定时器（撤岛后不会被窗口重新拉起）', () async {
      installMock();
      final service = LiveUpdateService(
        downloadCompletedDwell: const Duration(milliseconds: 30),
      );

      await service.notifyDownloadCompleted(fileName: 'a.apk');
      await service.cancelAll();
      final cancelsAfterCancel = cancelCount();
      final showsAfterCancel = showCount();

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(showCount(), showsAfterCancel, reason: '撤岛后窗口不得再拉起岛');
      expect(cancelCount(), cancelsAfterCancel);
    });

    test('8. 非 Android 平台：完成态不上岛、零平台通道调用', () async {
      installMock();
      final service = LiveUpdateService(androidPlatformOverride: false);

      await service.notifyDownloadCompleted(fileName: 'a.apk');

      expect(calls, isEmpty);
    });
  });
}
