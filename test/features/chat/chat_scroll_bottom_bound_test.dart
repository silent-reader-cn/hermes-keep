import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// #23 发送消息后滚动区「下拉拉超又弹回」回弹守卫（像素轨迹探针）。
///
/// A 重构后列表为 **reverse**（`offset 0 = 底部 = 最新消息`），坐标基准随之改变：
/// 「回弹」的像素级实证特征变为 `pixels` 先**负向拉超**（< 0，越出列表起点），
/// 再被 ClampingScrollPhysics 拉回（弹回）——即轨迹「下探 + 回弹」。
/// 探针断言（reverse 口径）：
/// 1. 任何样本 `-1.0 <= pixels <= maxScrollExtent + 1.0`（双向不越界，容差 ±1px）；
/// 2. 轨迹不出现显著回升（`pixels` 不得远离 0 后再回来，即无弹簧回弹）；
/// 3. 最终 `pixels ≈ 0`（容差 1px，停在真实底部）。
void main() {
  group('#23 发送消息后滚底不越界/不回弹', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DiagnosticsService.instance.clear();
      await DiagnosticsService.instance.setEnabled(false);
    });

    tearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await DiagnosticsService.instance.clear();
      await DiagnosticsService.instance.setEnabled(false);
    });

    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    /// 捕获像素轨迹：listener 记录每一次 pixels 变化（含 jumpTo 落点/
    /// clamp 修正瞬态），pump 后再补一帧采样。
    ({List<double> pixels, List<double> maxes}) capture(ScrollPosition pos) {
      final pixels = <double>[];
      final maxes = <double>[];
      // A 重构（reverse）：列表初始即在底部，贴底/跟底可能**全程零跳转**
      // （零 pixels 变化正是目标状态）。先记录一次当前快照，使轨迹恒有样本，
      // 既避免空列表取值异常，又保留「无跳转」的可观测性。
      pixels.add(pos.pixels);
      maxes.add(pos.maxScrollExtent);
      pos.addListener(() {
        pixels.add(pos.pixels);
        maxes.add(pos.maxScrollExtent);
      });
      return (pixels: pixels, maxes: maxes);
    }

    void assertNoBounce(
      List<double> pixels,
      List<double> maxes, {
      required String label,
    }) {
      expect(pixels.length, maxes.length);
      // A 重构（reverse）：列表初始即在底部（offset 0），贴底/跟底都无需跳转，
      // 因此「轨迹为空」是**目标状态**而非失败——它正说明 O(n) 跳转已被消除。
      for (var i = 0; i < pixels.length; i++) {
        expect(
          pixels[i] >= -1.0 && pixels[i] <= maxes[i] + 1.0,
          isTrue,
          reason:
              '$label：样本[$i] 越界（拉超凸起）pixels=${pixels[i]} '
              'max=${maxes[i]}（reverse：起点外为负）',
        );
      }
      // A 重构（reverse）：跳底目标恒为 offset 0，正常轨迹是「向 0 收敛或恒为 0」。
      // 回弹的特征是 pixels 先负向拉超、再回升到 0——即出现显著「回升」。
      for (var i = 1; i < pixels.length; i++) {
        final pixelDelta = pixels[i] - pixels[i - 1];
        expect(
          pixelDelta <= 1.0,
          isTrue,
          reason:
              '$label：样本[$i] 像素出现回升（被弹簧拉回·弹回特征）'
              '[${pixels[i - 1]} -> ${pixels[i]}]'
              '\n完整轨迹 pixels=$pixels\nmaxes=$maxes',
        );
      }
    }

    testWidgets('600 条长会话长短混合静态构建滚底收敛：停在真实底部，全程不越界', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        600,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': i % 11 == 0
              ? '消息 $i：${'这是一段非常长的消息内容用于撑高气泡高度制造估算偏差。' * 24}'
              : '消息 $i：短',
          'message_id': 'm$i',
        },
      );
      api.sessionResult = {
        'session': {
          'session_id': 's-bounce-static-600',
          'messages': messages,
          'message_count': 600,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-bounce-static-600'),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final pos = positionOf(tester);
      expect(
        pos.pixels >= -1.0 && pos.pixels <= pos.maxScrollExtent + 1.0,
        isTrue,
        reason: '初始定位不得越界（reverse：起点外为负）',
      );
      expect(
        pos.pixels,
        closeTo(0.0, 1.0),
        reason: '600 条懒加载长会话应收敛到真实底部',
      );
    });

    testWidgets('发送消息 + 流式增长全程不越界、轨迹单调、最终贴底（长会话长短混合）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      // 长短混合长会话（200 条）：lazy ListView 的估算 maxScrollExtent 与真实 extent
      // 偏差大（约 20 屏高），发送后跳底验证不越界、不回弹。
      final messages = List.generate(
        200,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': i % 11 == 0
              ? '消息 $i：${'这是一段非常长的消息内容用于撑高气泡高度制造估算偏差。' * 24}'
              : '消息 $i：短',
          'message_id': 'm$i',
        },
      );
      api.sessionResult = {
        'session': {
          'session_id': 's-bounce-long',
          'active_stream_id': 'stream-bounce',
          'messages': messages,
          'message_count': 200,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-bounce-long')),
        ),
      );
      // 初始定位收敛：确定性 pump 序列消除活跃流定时器与 pumpAndSettle 竞态。
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final pos = positionOf(tester);
      final traj = capture(pos);

      // 发送消息（active stream → 流式内提交路径）。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatMessageList)),
      );
      unawaited(
        container
            .read(chatControllerProvider('s-bounce-long').notifier)
            .send('hello #23'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 流式 token 增长：16ms 合并 + 48ms reveal（与既有粘底测试同节奏）。
      for (var i = 0; i < 24; i++) {
        api.emit(TokenSseEvent('新增流式文本块 $i ：${'内容' * (i % 13 + 1)} '));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      assertNoBounce(traj.pixels, traj.maxes, label: '发送+流式');
      expect(
        traj.pixels.isEmpty ? pos.pixels : traj.pixels.last,
        closeTo(0.0, 1.0),
        reason:
            '最终应收敛到真实底部（max=${traj.maxes.last}, '
            'pixels=${traj.pixels.last}）',
      );
    });

    testWidgets('发送后「extent 增长 → 复核再跳」两步内停在真实底部', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        20,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：' * 10,
          'message_id': 'm$i',
        },
      );
      api.sessionResult = {
        'session': {
          'session_id': 's-settle-first',
          'messages': messages,
          'message_count': 20,
        },
      };
      api.startChatResult = {'ok': true, 'stream_id': 'stream-new'};

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-settle-first'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pos = positionOf(tester);
      final traj = capture(pos);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatMessageList)),
      );
      unawaited(
        container
            .read(chatControllerProvider('s-settle-first').notifier)
            .send('second message'),
      );

      // 发送 → sending 相位 200ms 平滑动画收敛。
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        traj.pixels.isEmpty ? pos.pixels : traj.pixels.last,
        closeTo(0.0, 1.0),
        reason:
            '发送后第一步应收敛到当前底部'
            '（max=${traj.maxes.last}, pixels=${traj.pixels.last}）',
      );

      // 流式开始：sending 指示器被流式气泡替换（extent 变化窗口）。
      // 模拟任务书时序「首次 jumpTo 后 extent 变化 → 复核跳」：
      // 两次 pump 让新气泡入场并触发复核，最终停在真实底部。
      api.emit(const TokenSseEvent('回复内容开始 '));
      await tester.pump(); // 16ms 合并帧：新气泡入场，extent 增长
      await tester.pump(const Duration(milliseconds: 48)); // reveal 帧：复核跳
      await tester.pump(const Duration(milliseconds: 16)); // 再一帧稳定

      expect(
        traj.pixels.isEmpty ? pos.pixels : traj.pixels.last,
        closeTo(0.0, 1.0),
        reason:
            'extent 增长后复核应停在真实底部'
            '（max=${traj.maxes.last}, pixels=${traj.pixels.last}）',
      );

      // 继续流式多批，始终贴底。
      for (var i = 0; i < 6; i++) {
        api.emit(TokenSseEvent('更多回复文本 $i ' * 8));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
      }

      assertNoBounce(traj.pixels, traj.maxes, label: '发送+extent增长复核');
      expect(
        traj.pixels.isEmpty ? pos.pixels : traj.pixels.last,
        closeTo(0.0, 1.0),
        reason: '流式持续增长期间应始终贴底',
      );
    });

    testWidgets('流式增量跟随节奏零回归：无动画活动、贴底（#13 回归）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      final messages = List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：' * 10,
          'message_id': 'm$i',
        },
      );
      api.sessionResult = {
        'session': {
          'session_id': 's-rhythm',
          'active_stream_id': 'stream-rhythm',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-rhythm')),
        ),
      );
      await tester.pumpAndSettle();

      var drivenCount = 0;
      final pos = positionOf(tester);
      void onPosChanged() {
        if (pos.activity is DrivenScrollActivity) drivenCount++;
      }

      pos.addListener(onPosChanged);
      final traj = capture(pos);

      for (var i = 0; i < 5; i++) {
        api.emit(TokenSseEvent('new text chunk $i ' * 10));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump();
      }

      pos.removeListener(onPosChanged);

      expect(
        drivenCount,
        0,
        reason: '流式增量 token 不应产生 animateTo 动画活动（#13 节奏零回归）',
      );
      assertNoBounce(traj.pixels, traj.maxes, label: '流式跟随');
      expect(
        traj.pixels.isEmpty ? pos.pixels : traj.pixels.last,
        closeTo(0.0, 1.0),
        reason: '流式增量更新应始终保持粘底',
      );
    });
  });
}
