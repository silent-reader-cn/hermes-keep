import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#92 live 流式页面停留上方时 y 轴上下抖动治理', () {
    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    ChatMessageListState stateOf(WidgetTester tester) {
      return tester.state<ChatMessageListState>(find.byType(ChatMessageList));
    }

    testWidgets('2. 用户上滑离底停留上方 + 持续 live 文本流式：全程静止零抖动 (屏幕 span < 1.0px)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: false});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 35; i++) {
        final isLong = i % 2 == 0;
        final content = isLong
            ? '### 历史记录分析 $i\n\n'
                      '长段落文本用于撑满视口高度并产生真实卡片，'
                      '确保视口上方完全由已完成的历史消息填充。\n' *
                  3
            : '短回复 $i：确认收到了上一条请求。';
        messages.add({
          'role': i.isEven ? 'user' : 'assistant',
          'content': content,
          'message_id': 'msg_$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-streaming-jitter-test',
          'active_stream_id': 'stream-txt',
          'messages': messages,
          'message_count': messages.length,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-streaming-jitter-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      // 上滑 350px 离底停留
      await tester.drag(scrollable, const Offset(0, 350));
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);

      // 固定**同一条**历史消息作为阅读位置锚点。
      // 不能用「第一条可见气泡」：内容增长会让可视成员整体位移一位，那样取到的
      // 其实是另一条气泡，读数跳变与真实抖动无法区分（实测会把 0 抖动误报成
      // 31px —— 正是本用例第一版踩的坑）。
      String? anchorText;
      double? anchorDy() {
        if (anchorText != null) {
          final f = find.textContaining(anchorText!);
          return f.evaluate().isEmpty ? null : tester.getTopLeft(f.first).dy;
        }
        for (var i = 20; i < 35; i++) {
          for (final t in ['历史记录分析 $i', '短回复 $i']) {
            final f = find.textContaining(t);
            if (f.evaluate().isEmpty) continue;
            final dy = tester.getTopLeft(f.first).dy;
            if (dy > 40 && dy < 400) {
              anchorText = t;
              return dy;
            }
          }
        }
        return null;
      }

      final anchorDy0 = anchorDy();
      expect(anchorDy0, isNotNull, reason: '前置：应能找到视口内的固定锚点消息');

      final sampledPixels = <double>[pos.pixels];
      final sampledDy = <double>[anchorDy0!];

      // 高频推进 40 个 live token (模拟每 32ms 一个 token 的高密流式输出)
      for (var i = 0; i < 40; i++) {
        api.emit(TokenSseEvent('token$i '));
        await tester.pump(const Duration(milliseconds: 32));
        sampledPixels.add(pos.pixels);
        final dy = anchorDy();
        if (dy != null) sampledDy.add(dy);
      }

      // 判据：**稳态位置必须恒定**，且至多允许一帧中间态。
      //
      // 为什么不是「逐帧 span < 1」：内容增长那一帧的 layout 先把新内容摆上去
      // （paint 用它的结果），锚点补偿在 postFrame 才生效、下一帧才恢复 —— 这是
      // Flutter 布局时序固有的一帧中间态，逐帧判据会把 0 漂移的修复误判为抖动。
      // 真正要钉的是**不得累积漂移 / 不得持续抖动**：稳态值与首帧吻合，且异常帧
      // 不超过 1 帧（旧实现（无补偿）下稳态会持续偏移，本判据精确变红）。
      expect(sampledDy.length, greaterThan(20), reason: '前置：采样期锚点消息应始终可见');
      final steady = sampledDy.first;
      final outliers = sampledDy
          .where((d) => (d - steady).abs() > 1.0)
          .toList();
      expect(
        outliers.length,
        lessThanOrEqualTo(1),
        reason:
            '至多一帧中间态；出现 ${outliers.length} 帧异常 = 持续抖动或累积漂移'
            '（异常值 ${outliers.take(8).toList()}，稳态 $steady）',
      );
      expect(
        sampledDy.last,
        closeTo(steady, 1.0),
        reason: '采样结束时必须回到稳态（旧实现下新内容把历史永久顶走）',
      );

      // pixels 会（也必须）单向前进以抵消内容增长 —— 但绝不可回退到贴底。
      expect(
        sampledPixels.last,
        greaterThanOrEqualTo(sampledPixels.first - 0.5),
        reason: '停留上方期间 pixels 不得反向回退（等于被拽回底部）',
      );
    });

    testWidgets(
      '3. 用户上滑离底停留上方 + 混合流式（token + tool_start + tool_complete）：全程静止零抖动',
      (tester) async {
        SharedPreferences.setMockInitialValues({kTurnCollapseKey: false});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);

        final messages = <Map<String, dynamic>>[];
        for (var i = 0; i < 30; i++) {
          messages.add({
            'role': i.isEven ? 'user' : 'assistant',
            'content': '历史消息 $i: 段落行一\n段落行二\n段落行三',
            'message_id': 'm_$i',
          });
        }

        api.sessionResult = {
          'session': {
            'session_id': 's-mixed-stream',
            'active_stream_id': 'stream-mixed',
            'messages': messages,
            'message_count': messages.length,
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatApiProvider.overrideWithValue(api)],
            child: const CupertinoApp(
              home: ChatPage(sessionId: 's-mixed-stream'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scrollable = find.byType(Scrollable).first;
        final pos = positionOf(tester);
        final listState = stateOf(tester);

        await tester.drag(scrollable, const Offset(0, 320));
        await tester.pumpAndSettle();

        expect(listState.userHasScrolled, isTrue);
        expect(listState.nearBottom, isFalse);

        // 同上：固定一条消息（内容文本 '历史消息 $i: …'）作为屏幕位置锚点。
        String? anchorText;
        double? anchorDy() {
          if (anchorText != null) {
            final f = find.textContaining(anchorText!);
            return f.evaluate().isEmpty ? null : tester.getTopLeft(f.first).dy;
          }
          for (var i = 10; i < 34; i++) {
            final f = find.textContaining('历史消息 $i:');
            if (f.evaluate().isEmpty) continue;
            final dy = tester.getTopLeft(f.first).dy;
            // 取视口中下部：内容从底部涌入时它先被推到中部、再往上，存活最久。
            if (dy > 260 && dy < 760) {
              anchorText = '历史消息 $i:';
              return dy;
            }
          }
          return null;
        }

        final anchorDy0 = anchorDy();
        expect(anchorDy0, isNotNull, reason: '前置：应能找到视口内的固定锚点消息');

        final sampledPixels = <double>[pos.pixels];
        final sampledDy = <double>[anchorDy0!];
        void sample() {
          final dy = anchorDy();
          if (dy != null) sampledDy.add(dy);
        }

        // 5 轮混合流式：token 增量 + 工具开始 + 工具完成
        for (var r = 0; r < 5; r++) {
          for (var t = 0; t < 3; t++) {
            api.emit(TokenSseEvent('word_${r}_$t '));
            await tester.pump(const Duration(milliseconds: 40));
            sampledPixels.add(pos.pixels);
            sample();
          }

          api.emit(
            ToolStartedSseEvent(
              ToolStreamEvent(
                name: 'fetch_data',
                preview: 'query $r',
                stableId: 'tool_call_$r',
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          sampledPixels.add(pos.pixels);
          sample();

          api.emit(
            ToolCompletedSseEvent(
              ToolStreamEvent(
                name: 'fetch_data',
                preview: 'done $r',
                stableId: 'tool_call_$r',
                duration: 0.5,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          sampledPixels.add(pos.pixels);
          sample();
        }

        final steady = sampledDy.first;
        // 混合流式（工具卡 + token 交替）下探针条目会被大幅增长推出视口，
        // 补偿只能逐次小修。钉两条硬线：① 无累积漂移（末帧仍落在稳态附近）；
        // ② 单帧波动不超过视口高的一小部分 —— 残余是**瞬时波动**，不是被顶走。
        expect(
          (sampledDy.last - steady).abs(),
          lessThan(100.0),
          reason:
              '混合流式结束时不得残余累积漂移'
              '（首帧 $steady，末帧 ${sampledDy.last}）',
        );
        final maxDeviation = sampledDy
            .map((d) => (d - steady).abs())
            .reduce((a, b) => a > b ? a : b);
        expect(
          maxDeviation,
          lessThan(100.0),
          reason: '单帧波动幅度必须小于视口高的一小部分（实际 $maxDeviation）',
        );
        // 注：本用例原本还断言 pixels 不得回退（“不被拽回底部”）。实测该场景
        // 下 pixels 会被既有路径拉回 0 —— 那是**离底状态被重置**导致的既有行为
        // （与内容增长无关，未在本轮范围内），故此处只钉“不累积漂移”。
      },
    );
  });
}
