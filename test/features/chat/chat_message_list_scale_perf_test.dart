import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';

import '../../helpers/fake_chat_api.dart';

/// 大消息量性能基线与守卫。
///
/// 背景：主人反馈「消息超过 1000 条后上下滑动卡顿」。本组测试量化两件事：
/// ① 虚拟化是否真的生效（首帧只构建可见条目，而非全量）；
/// ② 每帧 rebuild 的规模是否与消息总量挂钩（挂钩 = 存在 O(n) 全量重算热点）。
///
/// ⚠️ 场景口径（重要，勿误读）：生产**首屏只加载约 50 条** ——
/// `ChatController.loadMessages` 固定请求 `messageLimit: 50`，服务端
/// `_message_window_for_display`（hermes-webui `api/routes.py`）按「可见行尾窗」
/// 语义返回最后 N 条可见行。
/// 因此本文件「一次给 1000 条」的构造**不是冷启动场景**，而是
/// 「用户向上翻历史、分页累积到 1000+ 条之后」的状态。
/// 该状态成立时，任何需要到达**远处偏移**的操作（初始定位 / 回到底部 /
/// 大纲跳转 / 分页后的位置恢复）都会让 SliverList 从 index 0 顺序创建子项 ——
/// 实测 1000 条时 itemBuilder 被调用 1258 次而最终只存活 62 个。
///
/// 计时仅作趋势参考（测试环境 JIT 抖动大，不做硬阈值断言）；
/// 硬断言只用在「构建条目数」这类稳定指标上。

class _NoopCacheService extends CacheService {
  _NoopCacheService(super.db);

  @override
  Future<void> writeMessages({
    required String sessionId,
    required List<Map<String, Object?>> messages,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> readMessages(String sessionId) async =>
      const [];
}

/// 构造 [count] 条「用户/助手交替」的消息，贴近真实会话长度形态。
List<Map<String, Object?>> _buildMessages(int count) => [
  for (var i = 0; i < count; i++)
    <String, Object?>{
      'role': i.isEven ? 'user' : 'assistant',
      'content': '第 $i 条消息正文，长度接近真实气泡内容以取得可信的布局高度。',
      'message_id': 'm$i',
    },
];

class _ScaleMetrics {
  _ScaleMetrics({
    required this.count,
    required this.firstFrameMs,
    required this.scrollFrameMs,
    required this.rebuildMs,
    required this.bubblesBuilt,
    required this.bubblesAfterScroll,
    required this.settleFrames,
    required this.pumpWidgetMs,
    required this.pump1Ms,
    required this.pump2Ms,
  });

  final int count;
  final double firstFrameMs;

  /// 滚动一屏那一帧的耗时（含 _onScroll 副作用），抖动较大，仅作参考。
  final double scrollFrameMs;

  /// **整表 rebuild 成本**：transcript/toolGroups 引用均不变，只强制重建 widget。
  /// 这一帧的成本 = build 内数据层派生重算（O(n) 起），是「每帧重算」的直接度量，
  /// 也是本次优化的靶子指标。
  final double rebuildMs;
  final int bubblesBuilt;
  final int bubblesAfterScroll;

  /// 初始 settle 用掉的帧数：若随 N 增长，说明「初始定位收敛」是按消息量
  /// 逐帧迭代的（首帧耗时的真实放大源）。
  final int settleFrames;

  /// 分阶段耗时：定位首帧耗时的真正归属。
  final double pumpWidgetMs;
  final double pump1Ms;
  final double pump2Ms;

  @override
  String toString() =>
      'N=$count  首帧=${firstFrameMs.toStringAsFixed(1)}ms  '
      '[pumpWidget=${pumpWidgetMs.toStringAsFixed(1)}ms '
      'pump1=${pump1Ms.toStringAsFixed(1)}ms '
      'pump2=${pump2Ms.toStringAsFixed(1)}ms '
      'settle帧=$settleFrames]  '
      '整表rebuild=${rebuildMs.toStringAsFixed(1)}ms  '
      '滚动帧=${scrollFrameMs.toStringAsFixed(1)}ms  '
      '构建气泡=$bubblesBuilt  滚动后气泡=$bubblesAfterScroll';
}

Future<_ScaleMetrics> _measureScale(
  WidgetTester tester,
  int count, {
  bool scroll = false,
}) async {
  final api = FakeChatApi();
  api.sessionResult = {
    'session': {
      'session_id': 's-scale',
      'title': '规模压测',
      'messages': _buildMessages(count),
      'message_count': count,
    },
  };
  final db = AppDatabase.memory();
  addTearDown(() => db.close());

  final sw = Stopwatch()..start();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(api),
        appDatabaseProvider.overrideWithValue(db),
        cacheServiceProvider.overrideWithValue(_NoopCacheService(db)),
      ],
      child: const CupertinoApp(home: ChatPage(sessionId: 's-scale')),
    ),
  );
  final pumpWidgetMs = sw.elapsedMicroseconds / 1000.0;
  await tester.pump();
  final pump1Ms = sw.elapsedMicroseconds / 1000.0;
  await tester.pump(const Duration(milliseconds: 50));
  final pump2Ms = sw.elapsedMicroseconds / 1000.0;
  // 用带计数的 settle 循环替代 pumpAndSettle：既完成收敛，又能测出帧数。
  var settleFrames = 0;
  while (tester.binding.hasScheduledFrame && settleFrames < 20000) {
    await tester.pump(const Duration(milliseconds: 16));
    settleFrames++;
  }
  final firstFrameMs = sw.elapsedMicroseconds / 1000.0;

  final bubblesBuilt = tester.allWidgets.whereType<ChatMessageBubble>().length;

  // 整表 rebuild 成本：微调 devicePixelRatio 触发重建（transcript / toolGroups
  // 引用均不变 → 优化的缓存应当命中；未优化时 build 内会重算全量派生）。
  sw.reset();
  sw.start();
  tester.view.devicePixelRatio = 1.0001;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  sw.stop();
  final rebuildMs = sw.elapsedMicroseconds / 1000.0;
  tester.view.devicePixelRatio = 1.0;
  await tester.pump();

  var bubblesAfterScroll = bubblesBuilt;
  var scrollFrameMs = 0.0;
  if (scroll) {
    // 滚动一屏：_onScroll 里的状态跃迁会 setState → 整表 rebuild。
    // 计时覆盖 drag 事件处理 + 随后两帧（含 rebuild 与新条目构建）。
    sw.reset();
    sw.start();
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, 400),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    sw.stop();
    scrollFrameMs = sw.elapsedMicroseconds / 1000.0;
    bubblesAfterScroll = tester
        .allWidgets
        .whereType<ChatMessageBubble>()
        .length;
  }

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  return _ScaleMetrics(
    count: count,
    firstFrameMs: firstFrameMs,
    scrollFrameMs: scrollFrameMs,
    rebuildMs: rebuildMs,
    bubblesBuilt: bubblesBuilt,
    bubblesAfterScroll: bubblesAfterScroll,
    settleFrames: settleFrames,
    pumpWidgetMs: pumpWidgetMs,
    pump1Ms: pump1Ms,
    pump2Ms: pump2Ms,
  );
}

void main() {
  testWidgets(
    '1000 条消息：虚拟化生效（只构建可见条目，不构建全量）',
    timeout: const Timeout(Duration(minutes: 3)),
    (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final m = await _measureScale(tester, 1000, scroll: true);
    // ignore: avoid_print
    print('[scale-perf] $m');

    expect(
      m.bubblesBuilt,
      lessThan(200),
      reason: '1000 条消息的首帧构建气泡数应远小于 1000（虚拟化生效）；'
          '若接近 1000 说明退化成非懒加载',
    );
    expect(
      m.bubblesAfterScroll,
      lessThan(200),
      reason: '滚动一屏后同时驻留的气泡数同样应有上界',
    );
  });

  testWidgets(
    '规模缩放对照：100 / 500 / 1000 条的构建与 rebuild 指标',
    timeout: const Timeout(Duration(minutes: 3)),
    (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final metrics = <_ScaleMetrics>[];
    for (final n in [100, 500, 1000]) {
      metrics.add(await _measureScale(tester, n, scroll: true));
    }

    // ignore: avoid_print
    print('[scale-perf] ===== 规模对照 =====');
    for (final m in metrics) {
      // ignore: avoid_print
      print('[scale-perf] $m');
    }

    // 虚拟化守卫：任何规模下构建气泡数量都不随总量线性增长。
    for (final m in metrics) {
      expect(
        m.bubblesBuilt,
        lessThan(200),
        reason: 'N=${m.count} 时构建气泡 ${m.bubblesBuilt} 个，超出可见范围上界',
      );
    }
  });

  group('数据层分离测量（不渲染 UI，定位首帧耗时的构成）', () {
    test('loadMessages 与 transcript 派生耗时 + provider 重算次数', () async {
      for (final n in [100, 500, 1000]) {
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {
            'session_id': 's-data',
            'title': '数据层压测',
            'messages': _buildMessages(n),
            'message_count': n,
          },
        };
        final db = AppDatabase.memory();
        final container = ProviderContainer(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            appDatabaseProvider.overrideWithValue(db),
            cacheServiceProvider.overrideWithValue(_NoopCacheService(db)),
          ],
        );

        // 统计 transcript 派生的重算次数：若加载期间远超 1 次，
        // 说明存在「每次 state 变化就全量重算」的放大（O(k·n)）。
        var recomputes = 0;
        container.listen(
          transcriptMessagesProvider('s-data'),
          (_, _) => recomputes++,
        );

        final sw = Stopwatch()..start();
        await container
            .read(chatControllerProvider('s-data').notifier)
            .loadMessages();
        final loadMs = sw.elapsedMicroseconds / 1000.0;

        sw.reset();
        sw.start();
        final transcript = container.read(transcriptMessagesProvider('s-data'));
        final deriveMs = sw.elapsedMicroseconds / 1000.0;

        sw.reset();
        sw.start();
        final messages = container
            .read(chatControllerProvider('s-data'))
            .messages;
        final stateMs = sw.elapsedMicroseconds / 1000.0;

        // ignore: avoid_print
        print(
          '[data-layer] N=$n  load=${loadMs.toStringAsFixed(1)}ms  '
          'transcript派生=${deriveMs.toStringAsFixed(1)}ms  '
          'state读取=${stateMs.toStringAsFixed(1)}ms  '
          'transcript=${transcript.length}条  messages=${messages.length}条  '
          '派生重算=$recomputes次',
        );

        container.dispose();
        await db.close();
      }
    });
  });

  testWidgets(
    '分页累积路径：每次向上加载更早消息后的帧耗时（滑动卡顿的直接度量）',
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const total = 1000;
      const pageSize = 50;
      final all = _buildMessages(total);

      final api = FakeChatApi();
      // 按 messageBefore 逐页返回（与生产 msg_before/msg_limit 分页语义一致）。
      api.sessionResultBuilder = (messageBefore) {
        final end = messageBefore ?? total;
        final start = (end - pageSize).clamp(0, total);
        return {
          'session': {
            'session_id': 's-page',
            'title': '分页累积压测',
            'messages': all.sublist(start, end),
            'message_count': total,
            'messages_offset': start,
            'messages_truncated': start > 0,
          },
        };
      };

      final db = AppDatabase.memory();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            appDatabaseProvider.overrideWithValue(db),
            cacheServiceProvider.overrideWithValue(_NoopCacheService(db)),
          ],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-page')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatPage)),
      );

      final sw = Stopwatch();
      // ignore: avoid_print
      print('[paging] ===== 分页累积（每次上滑触发加载更早 50 条）=====');
      for (var round = 1; round <= 60; round++) {
        sw.reset();
        sw.start();
        await tester.drag(
          find.byType(ListView).first,
          const Offset(0, 3000),
          warnIfMissed: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        sw.stop();
        final loaded = container
            .read(chatControllerProvider('s-page'))
            .messages
            .length;
        final bubbles = tester.allWidgets.whereType<ChatMessageBubble>().length;
        // ignore: avoid_print
        print(
          '[paging] 第$round次上滑 已加载=$loaded条 存活气泡=$bubbles '
          '帧耗时=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
