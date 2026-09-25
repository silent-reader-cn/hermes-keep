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

  group('#56 阅读锚点抖动修复与机制单测', () {
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

    testWidgets('真实形状下离底阅读（回合折叠关）：统计像素抖动反转次数与锚点切换', (tester) async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: false});

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      // 构造长短悬殊的历史消息（短消息与长 markdown 交替产生显著高度方差）
      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 40; i++) {
        final isLong = i % 3 == 0;
        final content = isLong
            ? '### 长章节分析报告 $i\n\n'
                      '这是用于模拟长 markdown 渲染的段落内容，包含代码段与列表：\n'
                      '```dart\n'
                      'void processBatch$i() {\n'
                      '  for (var k = 0; k < 15; k++) {\n'
                      '    print("Batch item \$k for report $i");\n'
                      '  }\n'
                      '}\n'
                      '```\n\n'
                      '- 重点指标 A: 正常\n'
                      '- 重点指标 B: 警告需要关注\n'
                      '- 重点指标 C: 延迟 120ms\n\n'
                      '补充说明文字段落以撑起条目高度，使其在视口进出 cacheExtent 边界时产生明显的估算高度差异。' *
                  2
            : '短回复 $i：这是一条简短的确认文本。';
        messages.add({
          'role': i.isEven ? 'user' : 'assistant',
          'content': content,
          'message_id': 'm$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-jitter-test',
          'active_stream_id': 'stream-jitter',
          'messages': messages,
          'message_count': messages.length,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-jitter-test')),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      // 拖拽离底：多档测试使视口顶部条目贴边
      await tester.drag(scrollable, const Offset(0, 312));
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);

      final sampledPixels = <double>[];
      final anchorKeys = <String?>[];

      // 6 轮真实节奏 live 事件：token + tool_start + tool_complete
      for (var round = 0; round < 6; round++) {
        for (var t = 0; t < 4; t++) {
          api.emit(TokenSseEvent('token $round-$t '));
          await tester.pump(const Duration(milliseconds: 50));
          sampledPixels.add(pos.pixels);
          anchorKeys.add(listState.readingAnchorCandidateKey);
        }

        api.emit(
          ToolStartedSseEvent(
            ToolStreamEvent(
              name: 'execute_command',
              preview: 'run round $round',
              stableId: 'tool_$round',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        sampledPixels.add(pos.pixels);
        anchorKeys.add(listState.readingAnchorCandidateKey);

        api.emit(
          ToolCompletedSseEvent(
            ToolStreamEvent(
              name: 'execute_command',
              preview: 'completed $round',
              stableId: 'tool_$round',
              duration: 0.8,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        sampledPixels.add(pos.pixels);
        anchorKeys.add(listState.readingAnchorCandidateKey);
      }

      // 计算方向反转次数（幅度 >= 1.0px）
      var reversals = 0;
      double? lastDirection;
      for (var i = 1; i < sampledPixels.length; i++) {
        final delta = sampledPixels[i] - sampledPixels[i - 1];
        if (delta.abs() >= 1.0) {
          final dir = delta > 0 ? 1.0 : -1.0;
          if (lastDirection != null && dir != lastDirection) {
            reversals++;
          }
          lastDirection = dir;
        }
      }

      // 统计锚点键交替切换次数
      var anchorSwitches = 0;
      for (var i = 1; i < anchorKeys.length; i++) {
        if (anchorKeys[i] != null &&
            anchorKeys[i - 1] != null &&
            anchorKeys[i] != anchorKeys[i - 1]) {
          anchorSwitches++;
        }
      }

      expect(
        reversals,
        equals(0),
        reason: '离底阅读时不应发生像素方向反转抖动 (reversals=$reversals)',
      );
      expect(
        anchorSwitches,
        equals(0),
        reason: '流式期间阅读锚点不应在不同条目间来回横跳 (switches=$anchorSwitches)',
      );
    });

    testWidgets('真实形状下离底阅读（#55 回合折叠开）：统计像素抖动与锚点稳定性', (tester) async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: true});

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 40; i++) {
        final isLong = i % 3 == 0;
        final content = isLong
            ? '### 长章节分析报告 $i\n\n'
                      '包含代码段与长文本：\n'
                      '```dart\n'
                      'void processBatch$i() {}\n'
                      '```\n\n'
                      '补充说明文字段落以撑起条目高度。' *
                  3
            : '短回复 $i：这是一条简短的确认文本。';
        messages.add({
          'role': i.isEven ? 'user' : 'assistant',
          'content': content,
          'message_id': 'm$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-jitter-collapse',
          'active_stream_id': 'stream-jitter-col',
          'messages': messages,
          'message_count': messages.length,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-jitter-collapse'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      // 上滑离底
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);

      final sampledPixels = <double>[];
      final anchorKeys = <String?>[];

      for (var round = 0; round < 4; round++) {
        for (var t = 0; t < 3; t++) {
          api.emit(TokenSseEvent('token col $round-$t '));
          await tester.pump(const Duration(milliseconds: 50));
          sampledPixels.add(pos.pixels);
          anchorKeys.add(listState.readingAnchorCandidateKey);
        }
      }

      var reversals = 0;
      double? lastDirection;
      for (var i = 1; i < sampledPixels.length; i++) {
        final delta = sampledPixels[i] - sampledPixels[i - 1];
        if (delta.abs() >= 1.0) {
          final dir = delta > 0 ? 1.0 : -1.0;
          if (lastDirection != null && dir != lastDirection) {
            reversals++;
          }
          lastDirection = dir;
        }
      }

      var anchorSwitches = 0;
      for (var i = 1; i < anchorKeys.length; i++) {
        if (anchorKeys[i] != null &&
            anchorKeys[i - 1] != null &&
            anchorKeys[i] != anchorKeys[i - 1]) {
          anchorSwitches++;
        }
      }

      expect(reversals, equals(0));
      expect(anchorSwitches, equals(0));
    });

  });
}
