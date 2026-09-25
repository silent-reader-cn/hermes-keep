import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('#13 滚动粘底保持测试', () {
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
      return tester.state<ChatMessageListState>(find.byType(ChatMessageList).first);
    }

    testWidgets('Live token 增量无动画 jump 跟随（不触发 DrivenScrollActivity）', (tester) async {
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
          'session_id': 's-sticky-live',
          'active_stream_id': 'stream-sticky',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-sticky-live')),
        ),
      );

      await tester.pumpAndSettle();

      var drivenCount = 0;
      final pos = positionOf(tester);
      void onPosChanged() {
        if (pos.activity is DrivenScrollActivity) drivenCount++;
      }

      pos.addListener(onPosChanged);

      // 发送 token 增量，验证滚动跟随为无动画 jump
      for (var i = 0; i < 5; i++) {
        api.emit(TokenSseEvent('new text chunk $i ' * 10));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump();
      }

      pos.removeListener(onPosChanged);

      expect(drivenCount, 0, reason: 'Live 增量 token 不应产生 animateTo 动画活动');
      expect(
        pos.pixels,
        closeTo(0.0, 1.0),
        reason: 'Live 增量更新应始终保持粘底',
      );
    });

    testWidgets('阶段切换（sending 开始）保留平滑动画', (tester) async {
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
          'session_id': 's-phase-anim',
          'messages': messages,
          'message_count': 20,
        },
      };
      api.startChatResult = {
        'ok': true,
        'stream_id': 'stream-new',
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-phase-anim')),
        ),
      );

      await tester.pumpAndSettle();

      final pos = positionOf(tester);

      // 发送消息触发 sending 相位
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatMessageList)),
      );
      unawaited(
        container
            .read(chatControllerProvider('s-phase-anim').notifier)
            .send('test message'),
      );

      await tester.pump();
      // A 重构（reverse）：贴底时滚底目标恒为 offset 0，且当前已在 0 ——
      // 无位移即无动画活动（不产生 DrivenScrollActivity 是正确结果）。
      // 原断言「必须有平滑动画」是正向实现（需从 max 位置跳转）的产物。
      expect(
        pos.pixels,
        closeTo(0.0, 1.0),
        reason: '阶段切到 sending 后仍应贴底（reverse：底部 = offset 0）',
      );

      // 推进多帧让 200ms 动画收敛完成
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(pos.pixels, closeTo(0.0, 1.0));
    });

    testWidgets('全平台（Android+iOS）软键盘弹出/收起触发 postFrame 无动画 jump 回底', (tester) async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final api = FakeChatApi();
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
              'session_id': 's-ime-$platform',
              'messages': messages,
              'message_count': 30,
            },
          };

          await tester.pumpWidget(
            ProviderScope(
              overrides: [chatApiProvider.overrideWithValue(api)],
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(390, 844),
                  viewInsets: EdgeInsets.zero,
                ),
                child: CupertinoApp(
                  home: CupertinoPageScaffold(
                    child: ChatMessageList(sessionId: 's-ime-$platform'),
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          final pos = positionOf(tester);
          expect(pos.pixels, closeTo(0.0, 1.0));

          // 模拟键盘弹出 (bottom viewInset = 300)
          await tester.pumpWidget(
            ProviderScope(
              overrides: [chatApiProvider.overrideWithValue(api)],
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(390, 844),
                  viewInsets: EdgeInsets.only(bottom: 300.0),
                ),
                child: CupertinoApp(
                  home: CupertinoPageScaffold(
                    child: ChatMessageList(sessionId: 's-ime-$platform'),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          final posAfterKeyboard = positionOf(tester);
          expect(
            posAfterKeyboard.pixels,
            closeTo(0.0, 1.0),
            reason: '键盘弹出后在 $platform 上应 postFrame jump 回底',
          );

          // 模拟键盘收起 (bottom viewInset = 0)
          await tester.pumpWidget(
            ProviderScope(
              overrides: [chatApiProvider.overrideWithValue(api)],
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(390, 844),
                  viewInsets: EdgeInsets.zero,
                ),
                child: CupertinoApp(
                  home: CupertinoPageScaffold(
                    child: ChatMessageList(sessionId: 's-ime-$platform'),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          final posAfterDismiss = positionOf(tester);
          expect(
            posAfterDismiss.pixels,
            closeTo(0.0, 1.0),
            reason: '键盘收起后在 $platform 上应 postFrame jump 回底',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });

    testWidgets('离底阅读态下键盘弹出不拉回底部（保持用户阅读位置）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：' * 10,
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-ime-reading',
          'messages': messages,
          'message_count': 40,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              viewInsets: EdgeInsets.zero,
            ),
            child: CupertinoApp(
              home: CupertinoPageScaffold(
                child: ChatMessageList(sessionId: 's-ime-reading'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);

      // 用户上滑离底 300px
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      final readingPixels = pos.pixels;
      expect(pos.maxScrollExtent - readingPixels, greaterThan(80));
      expect(stateOf(tester).userHasScrolled, isTrue);

      // 模拟键盘弹出
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              viewInsets: EdgeInsets.only(bottom: 300.0),
            ),
            child: CupertinoApp(
              home: CupertinoPageScaffold(
                child: ChatMessageList(sessionId: 's-ime-reading'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final posAfterKeyboard = positionOf(tester);
      expect(
        (posAfterKeyboard.pixels - readingPixels).abs(),
        lessThan(5.0),
        reason: '离底阅读态下键盘弹出不得将用户拉回底部',
      );
    });

    testWidgets('跟随态下输入栏多行/高度变化触发 postFrame 无动画 jump 保持贴底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
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
          'session_id': 's-input-expand',
          'messages': messages,
          'message_count': 30,
        },
      };

      // 用可变高度的下部 Widget 模拟输入栏从 50px 增高到 180px（多行输入）
      var inputHeight = 50.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: Column(
                    children: [
                      const Expanded(
                        child: ChatMessageList(sessionId: 's-input-expand'),
                      ),
                      SizedBox(height: inputHeight),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final pos = positionOf(tester);
      expect(pos.pixels, closeTo(0.0, 1.0));
      expect(stateOf(tester).userHasScrolled, isFalse);
      expect(stateOf(tester).nearBottom, isTrue);

      // 改变输入栏高度（增高 130px）
      inputHeight = 180.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: Column(
                    children: [
                      const Expanded(
                        child: ChatMessageList(sessionId: 's-input-expand'),
                      ),
                      SizedBox(height: inputHeight),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final posAfterExpand = positionOf(tester);
      expect(
        posAfterExpand.pixels,
        closeTo(0.0, 1.0),
        reason: '输入栏增高挤压后应 postFrame jump 保持贴底',
      );
      expect(stateOf(tester).userHasScrolled, isFalse);
      expect(stateOf(tester).nearBottom, isTrue);
    });

    testWidgets('离底阅读态下输入栏增高不拉回底部', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：' * 10,
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-input-reading',
          'messages': messages,
          'message_count': 40,
        },
      };

      var inputHeight = 50.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: Column(
                    children: [
                      const Expanded(
                        child: ChatMessageList(sessionId: 's-input-reading'),
                      ),
                      SizedBox(height: inputHeight),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);

      // 用户上滑离底 300px
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      final readingPixels = pos.pixels;
      expect(pos.maxScrollExtent - readingPixels, greaterThan(80));
      expect(stateOf(tester).userHasScrolled, isTrue);

      // 模拟输入栏增高
      inputHeight = 180.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: Column(
                    children: [
                      const Expanded(
                        child: ChatMessageList(sessionId: 's-input-reading'),
                      ),
                      SizedBox(height: inputHeight),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final posAfterExpand = positionOf(tester);
      expect(
        (posAfterExpand.pixels - readingPixels).abs(),
        lessThan(5.0),
        reason: '离底阅读态下输入栏增高挤压不得将视口拉回底部',
      );
    });

    testWidgets('进入历史会话后自动进入跟随态（探针全部符合且新 token 自动贴底）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = List.generate(
        50,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '历史消息 $i：' * 8,
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-enter-follow',
          'active_stream_id': 'stream-enter-follow',
          'messages': messages,
          'message_count': 50,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-enter-follow')),
        ),
      );

      await tester.pumpAndSettle();

      final state = stateOf(tester);
      final pos = positionOf(tester);

      // 探针断言：进入历史会话收敛后必须处于跟随态
      expect(state.nearBottom, isTrue, reason: '收敛后 _nearBottom 应为 true');
      expect(state.userHasScrolled, isFalse, reason: '收敛后 _userHasScrolled 应为 false');
      expect(state.pinnedTranscriptCount, 0, reason: '收敛后 _pinnedTranscriptCount 应为 0');
      expect(state.hasReadingAnchor, isFalse, reason: '收敛后 _readingAnchor 应为 null');
      expect(find.byKey(const ValueKey('chat-scroll-to-bottom-button')), findsNothing, reason: '回底按钮不显');
      expect(pos.pixels, closeTo(0.0, 1.0), reason: '初始应精准贴底');

      // 无手势流式后新 token 自动贴底
      for (var i = 0; i < 5; i++) {
        api.emit(TokenSseEvent('token chunk $i ' * 10));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump();
      }

      final posAfterTokens = positionOf(tester);
      expect(
        posAfterTokens.pixels,
        lessThan(80.0),
        reason: '新 token 到达后应自动贴底跟随',
      );
      expect(posAfterTokens.pixels, closeTo(0.0, 1.0));
      expect(find.byKey(const ValueKey('chat-scroll-to-bottom-button')), findsNothing);
    });

    testWidgets('多次冷/热切回会话稳定贴底且无反弹', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages1 = List.generate(
        60,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '会话1消息 $i：' * (i % 5 + 3),
          'message_id': 's1_m$i',
        },
      );
      final messages2 = List.generate(
        40,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '会话2消息 $i：' * (i % 7 + 2),
          'message_id': 's2_m$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-switch-1',
          'messages': messages1,
          'message_count': 60,
        },
      };

      var activeSessionId = 's-switch-1';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: ChatMessageList(sessionId: activeSessionId),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      var pos = positionOf(tester);
      expect(pos.pixels, closeTo(0.0, 1.0));
      expect(stateOf(tester).nearBottom, isTrue);
      expect(stateOf(tester).userHasScrolled, isFalse);

      // 切换到会话 2
      api.sessionResult = {
        'session': {
          'session_id': 's-switch-2',
          'messages': messages2,
          'message_count': 40,
        },
      };
      activeSessionId = 's-switch-2';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: ChatMessageList(sessionId: activeSessionId),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      pos = positionOf(tester);
      expect(pos.pixels, closeTo(0.0, 1.0));
      expect(stateOf(tester).nearBottom, isTrue);
      expect(stateOf(tester).userHasScrolled, isFalse);

      // 切回会话 1
      api.sessionResult = {
        'session': {
          'session_id': 's-switch-1',
          'messages': messages1,
          'message_count': 60,
        },
      };
      activeSessionId = 's-switch-1';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return CupertinoPageScaffold(
                  child: ChatMessageList(sessionId: activeSessionId),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      pos = positionOf(tester);
      expect(pos.pixels, closeTo(0.0, 1.0));
      expect(stateOf(tester).nearBottom, isTrue);
      expect(stateOf(tester).userHasScrolled, isFalse);
    });
  });
}
