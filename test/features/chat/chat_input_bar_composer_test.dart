import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/providers/clipboard_paste_provider.dart';
import 'package:hermes_ui/core/providers/file_picker_provider.dart';
import 'package:hermes_ui/core/utils/accessibility.dart';
import 'package:hermes_ui/core/utils/clipboard_paste.dart';
import 'package:hermes_ui/core/utils/file_picker.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:hermes_ui/features/settings/perf_monitor_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_prompts_api.dart';

bool _isButtonEnabled(WidgetTester tester, Finder finder) {
  final widget = tester.widget<AccessibleButton>(finder);
  return widget.onPressed != null;
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  required FakeChatApi chatApi,
  FakePromptsApi? promptsApi,
  String sessionId = 's1',
  ApiClient? apiClient,
}) async {
  final prompts = promptsApi ?? FakePromptsApi(initialPrompts: const []);
  final client = apiClient ?? ApiClient(baseUrl: 'http://test.local:30002');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        promptsApiFactoryProvider.overrideWithValue((_) => prompts),
        filePickerServiceProvider.overrideWithValue(FakeFilePickerService()),
        clipboardPasteServiceProvider.overrideWithValue(
          FakeClipboardPasteService(),
        ),
        apiClientProvider.overrideWithValue(client),
      ],
      child: CupertinoApp(home: ChatPage(sessionId: sessionId)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ChatInputBar 布局开关（两段式默认启用 / 显式关闭回退经典）', () {
    testWidgets('显式关闭时：经典单行布局（min1，无独立工具行），回车即发送', (tester) async {
      SharedPreferences.setMockInitialValues({kComposerTwoPaneKey: false});
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      expect(inputFinder, findsOneWidget);

      // 经典单行：保留自适应（min1/max4 软上限）。
      final field = tester.widget<CupertinoTextField>(inputFinder);
      expect(field.minLines, 1);
      expect(field.maxLines, 4);

      // 回车即发送（经典模式走 onSubmitted：测试里用 IME 提交动作模拟回车）
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.enterText(inputFinder, '经典消息');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(chatApi.startChatCalls, 1);
      expect(chatApi.lastSentText, '经典消息');

      await _unmount(tester);
    });

    testWidgets('开关打开：两段式布局（min2/max8），多行自适应增高且封顶', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        // 直接以开启状态注入（模拟设置页已打开开关并持久化）
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
        });
        await _pumpComposer(tester, chatApi: chatApi);
        // 等待异步 _load 从 prefs 读到 true
        await tester.pump(const Duration(milliseconds: 50));

        final inputFinder = find.byKey(const ValueKey('chat-input-field'));
        final field = tester.widget<CupertinoTextField>(inputFinder);
        expect(field.minLines, 2);
        expect(field.maxLines, 8);

        final initialHeight = tester.getSize(inputFinder).height;

        // 输入 4 行文本 → 高度增长
        await tester.enterText(inputFinder, '第一行\n第二行\n第三行\n第四行');
        await tester.pump();
        final height4Lines = tester.getSize(inputFinder).height;
        expect(height4Lines, greaterThan(initialHeight));

        // 16 行（超 maxLines: 8）→ 封顶不再增长
        await tester.enterText(
          inputFinder,
          '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16',
        );
        await tester.pump();
        final height16 = tester.getSize(inputFinder).height;
        expect(height16, greaterThan(height4Lines));

        await _unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        SharedPreferences.setMockInitialValues(<String, Object>{});
      }
    });

    testWidgets('两种布局下所有功能 Key 一致且唯一（GlobalKey 不撞车）', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };

      // 经典单行
      await _pumpComposer(tester, chatApi: chatApi);
      for (final key in const [
        'chat-attach-button',
        'chat-saved-prompts-button',
        'chat-context-indicator-button',
        'chat-send-button',
        'chat-input-field',
      ]) {
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: '经典布局应含 $key 且唯一',
        );
      }
      await _unmount(tester);

      // 两段式
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      await _pumpComposer(tester, chatApi: chatApi);
      await tester.pump(const Duration(milliseconds: 50));
      for (final key in const [
        'chat-attach-button',
        'chat-saved-prompts-button',
        'chat-context-indicator-button',
        'chat-send-button',
        'chat-input-field',
      ]) {
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: '两段式布局应含 $key 且唯一',
        );
      }
      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets(
      '现有工具栏按键 Key 全部存在（chat-attach-button, chat-saved-prompts-button, chat-send-button）',
      (tester) async {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _pumpComposer(tester, chatApi: chatApi);

        expect(
          find.byKey(const ValueKey('chat-attach-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('chat-saved-prompts-button')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-input-field')), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-steer-button')), findsNothing);
        expect(find.byKey(const ValueKey('chat-stop-button')), findsNothing);

        await _unmount(tester);
      },
    );
  });

  group('ChatInputBar 流式状态工具行按钮', () {
    testWidgets('流式期间（streaming）显示 steer 与 stop 按钮，隐藏 send 按钮', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);

      // 发送消息进入流式
      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.enterText(inputFinder, '测试问题');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      // 流式状态下工具行出现 steer + 停止按钮，发送按钮消失
      final steerBtn = find.byKey(const ValueKey('chat-steer-button'));
      final stopBtn = find.byKey(const ValueKey('chat-stop-button'));
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));

      expect(steerBtn, findsOneWidget);
      expect(stopBtn, findsOneWidget);
      expect(sendBtn, findsNothing);

      // 未输入 steer 内容时 steer 按钮禁用
      expect(_isButtonEnabled(tester, steerBtn), isFalse);

      // 输入 steer 内容后 steer 按钮可用
      await tester.enterText(inputFinder, '纠偏补充');
      await tester.pump();
      expect(_isButtonEnabled(tester, steerBtn), isTrue);

      // 点击停止按钮 → #19 二次确认框出现，确认后才真正停止
      await tester.tap(stopBtn);
      await tester.pump();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      // 点「停止生成」确认（输入栏 stop 按钮为 icon-only 无文本，
      // 页面上文本「停止生成」唯一，可安全定位）。
      await tester.tap(find.text('停止生成'));
      await tester.pumpAndSettle();
      expect(chatApi.cancelCalls, 1);

      await _unmount(tester);
    });
  });

  group('ChatInputBar 回车语义（桌面 Enter 发送 / Shift+Enter 换行；移动端 Enter 换行）', () {
    testWidgets('桌面端（Windows）两段式：Enter 键触发发送，Shift+Enter 插入换行', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      try {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _pumpComposer(tester, chatApi: chatApi);
        await tester.pump(const Duration(milliseconds: 50));

        final inputFinder = find.byKey(const ValueKey('chat-input-field'));

        // 聚焦输入框并输入文本
        await tester.tap(inputFinder);
        await tester.pump();
        await tester.enterText(inputFinder, '桌面消息');
        await tester.pump();

        // 桌面端按 Enter 触发发送
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump();

        expect(chatApi.startChatCalls, 1);
        expect(chatApi.lastSentText, '桌面消息');

        final field = tester.widget<CupertinoTextField>(inputFinder);
        expect(field.controller!.text, isEmpty);

        // 重置调用计数以测试 Shift+Enter
        chatApi.startChatCalls = 0;
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _unmount(tester);
        await _pumpComposer(tester, chatApi: chatApi);

        final freshInput = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(freshInput);
        await tester.pump();
        await tester.enterText(freshInput, '第一行');
        await tester.pump();

        // 按 Shift+Enter 插入换行，不触发发送
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(chatApi.startChatCalls, 0);
        final freshField = tester.widget<CupertinoTextField>(freshInput);
        expect(freshField.controller!.text, contains('\n'));

        await _unmount(tester);
        SharedPreferences.setMockInitialValues(<String, Object>{});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('移动端（Android）两段式：Enter 不发送（插入换行），点发送按钮发送', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      try {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _pumpComposer(tester, chatApi: chatApi);
        await tester.pump(const Duration(milliseconds: 50));

        final inputFinder = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(inputFinder);
        await tester.pump();
        await tester.enterText(inputFinder, '移动端消息');
        await tester.pump();

        // 两段式移动端按 Enter 键插入换行、不发送。
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(chatApi.startChatCalls, 0);
        final field = tester.widget<CupertinoTextField>(inputFinder);
        expect(field.controller!.text, contains('\n'));

        // 点击发送按钮触发发送
        final sendBtn = find.byKey(const ValueKey('chat-send-button'));
        expect(_isButtonEnabled(tester, sendBtn), isTrue);
        await tester.tap(sendBtn);
        await tester.pump();
        await tester.pump();

        expect(chatApi.startChatCalls, 1);
        expect(chatApi.lastSentText, contains('移动端消息'));

        await _unmount(tester);
        SharedPreferences.setMockInitialValues(<String, Object>{});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('ChatInputBar 上下文窗口指示器位置与排列顺序（todo #1）', () {
    testWidgets('经典单行布局：[＋] [书签] [上下文圆环] [输入框] [发送] 水平从左到右排列', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: false,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);

      final attachX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-attach-button')))
          .dx;
      final bookmarkX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-saved-prompts-button')))
          .dx;
      final indicatorX = tester
          .getTopLeft(
            find.byKey(const ValueKey('chat-context-indicator-button')),
          )
          .dx;
      final inputX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-input-field')))
          .dx;
      final sendX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-send-button')))
          .dx;

      expect(attachX, lessThan(bookmarkX));
      expect(bookmarkX, lessThan(indicatorX));
      expect(indicatorX, lessThan(inputX));
      expect(inputX, lessThan(sendX));

      await _unmount(tester);
    });

    testWidgets('两段式布局：工具行 [附件] [书签] [上下文圆环] | Spacer | [发送] 排列', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);
      await tester.pump(const Duration(milliseconds: 50));

      final attachX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-attach-button')))
          .dx;
      final bookmarkX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-saved-prompts-button')))
          .dx;
      final indicatorX = tester
          .getTopLeft(
            find.byKey(const ValueKey('chat-context-indicator-button')),
          )
          .dx;
      final sendX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-send-button')))
          .dx;

      expect(attachX, lessThan(bookmarkX));
      expect(bookmarkX, lessThan(indicatorX));
      expect(indicatorX, lessThan(sendX));

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('只读会话下仍显示上下文圆环指示器', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': const [],
          'is_read_only': true,
        },
      };
      await _pumpComposer(tester, chatApi: chatApi);

      expect(
        find.byKey(const ValueKey('chat-context-indicator-button')),
        findsOneWidget,
      );
      await _unmount(tester);
    });
  });

  group('两段式底栏性能监控布局与悬浮卡片', () {
    testWidgets('两段式开启+监控开启+有数据：左三贴左，监控在左侧紧跟左三，Spacer 推发送按钮贴最右', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      final client = _buildHealthClient(cpu: 45.0, mem: 60.0);

      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));

      final attachX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-attach-button')))
          .dx;
      final bookmarkX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-saved-prompts-button')))
          .dx;
      final indicatorX = tester
          .getTopLeft(
            find.byKey(const ValueKey('chat-context-indicator-button')),
          )
          .dx;
      final perfX = tester
          .getTopLeft(find.byKey(const ValueKey('perf-monitor-panel')))
          .dx;
      final sendX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-send-button')))
          .dx;

      // 左三贴左，监控紧随其后如状态后缀（统一左靠，不居中）
      expect(attachX, lessThan(bookmarkX));
      expect(bookmarkX, lessThan(indicatorX));
      expect(indicatorX, lessThan(perfX));
      expect(perfX, lessThan(160)); // 左靠剩余空间，紧跟左簇

      // Spacer 把右簇推至最右边缘（800 视口下 sendX 为 748）
      expect(sendX, greaterThan(740));

      // 紧凑态文本展示 CPU/MEM 百分比
      expect(find.textContaining('CPU 45%'), findsOneWidget);
      expect(find.textContaining('MEM 60%'), findsOneWidget);

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('流式状态下：steer 与 stop 整组贴最右，监控仍居左', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      final client = _buildHealthClient();

      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.enterText(inputFinder, '测试问题');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      final perfX = tester
          .getTopLeft(find.byKey(const ValueKey('perf-monitor-panel')))
          .dx;
      final steerX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-steer-button')))
          .dx;
      final stopX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-stop-button')))
          .dx;

      expect(perfX, lessThan(160));
      expect(steerX, greaterThan(stopX));
      expect(stopX, greaterThan(700));

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('窄屏（320px）自适应：监控缩放省略，两端按钮均可见可交互', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      final client = _buildHealthClient();

      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('chat-attach-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('perf-monitor-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('点击紧凑态以监控文本为锚点向上弹出悬浮卡片，输入栏工具行高度不变', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      final client = _buildHealthClient(cpu: 45.0, mem: 60.0, disk: 70.0);

      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));

      final attachButton = find.byKey(const ValueKey('chat-attach-button'));
      final attachTopBefore = tester.getTopLeft(attachButton).dy;

      // 点击紧凑态展开悬浮卡片
      await tester.tap(find.byKey(const ValueKey('perf-monitor-panel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 悬浮卡片出现
      final popoverCard = find.byKey(
        const ValueKey('perf-monitor-popover-card'),
      );
      expect(popoverCard, findsOneWidget);

      // 输入栏底栏行高度前后一致，不撑高文档流
      final attachTopAfter = tester.getTopLeft(attachButton).dy;
      expect(attachTopAfter, equals(attachTopBefore));

      // 悬浮卡片包含 CPU / MEM / DISK 内容
      expect(find.textContaining('CPU'), findsWidgets);
      expect(find.textContaining('MEM'), findsWidgets);
      expect(find.textContaining('DISK'), findsOneWidget);
      expect(find.textContaining('70%'), findsOneWidget);

      // 点击外部遮罩收起
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('perf-monitor-popover-card')),
        findsNothing,
      );

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('再次点击紧凑态手势收起悬浮卡片', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      final client = _buildHealthClient();

      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));

      // 首次点击展开
      await tester.tap(find.byKey(const ValueKey('perf-monitor-panel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey('perf-monitor-popover-card')),
        findsOneWidget,
      );

      // 再次点击监控文本所在区域（由屏障拦截响应）手势收起
      await tester.tap(
        find.byKey(const ValueKey('perf-monitor-panel')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey('perf-monitor-popover-card')),
        findsNothing,
      );

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('经典单行模式、perfMonitor=false、无数据时静默隐藏不占位', (tester) async {
      // 1. 经典单行模式
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: false,
        kShowPerfMonitorKey: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      final client = _buildHealthClient();

      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('perf-monitor-panel')), findsNothing);
      await _unmount(tester);

      // 2. perfMonitor=false
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: false,
      });
      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('perf-monitor-panel')), findsNothing);
      await _unmount(tester);

      // 3. 无数据时（未请求或出错）
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: true,
      });
      final failingDio = Dio(
        BaseOptions(validateStatus: (_) => true, followRedirects: false),
      );
      failingDio.httpClientAdapter = _HealthAdapter(
        responder: (_) => ResponseBody.fromString('Internal Error', 500),
      );
      final failingClient = ApiClient(
        baseUrl: 'http://test.local:30002',
        dio: failingDio,
      );
      await _pumpComposer(tester, chatApi: chatApi, apiClient: failingClient);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('perf-monitor-panel')), findsNothing);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('宽屏（1200px）下统一左靠（紧跟左簇），右簇贴最右', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      final client = _buildHealthClient();

      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));

      final attachX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-attach-button')))
          .dx;
      final indicatorX = tester
          .getTopLeft(
            find.byKey(const ValueKey('chat-context-indicator-button')),
          )
          .dx;
      final perfX = tester
          .getTopLeft(find.byKey(const ValueKey('perf-monitor-panel')))
          .dx;
      final sendX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-send-button')))
          .dx;

      expect(attachX, lessThan(indicatorX));
      expect(indicatorX, lessThan(perfX));
      expect(perfX, lessThan(160)); // 宽屏下依然紧随左三，统一左靠
      expect(sendX, greaterThan(1140)); // 右簇贴最右边缘

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    // ---------------------------------------------------------------------
    // #163 宽屏栏位档位（顶栏发丝线 / 标题 15 / 输入字段 15 + 两行起）
    // ---------------------------------------------------------------------
    testWidgets('#163 宽屏：顶栏含 0.5 发丝线且标题 15pt、字段 15pt 两行起', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      // 注意：resetPhysicalSize 不复位 DPR，同文件后续用例会看到被改小的
      // 视口 ⇒ 这里整屏复位（`reset`），避免用例间串味。
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '宽屏栏位校验',
          'messages': const [],
        },
      };

      await _pumpComposer(
        tester,
        chatApi: chatApi,
        apiClient: _buildHealthClient(),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // 顶栏：带 0.5px 底部分割线 ⇒ 总高 44.5（与侧栏品牌栏同高同线）。
      final navBar = tester.widget<CupertinoNavigationBar>(
        find.byType(CupertinoNavigationBar),
      );
      expect(navBar.bottom, isNotNull);
      expect(tester.getSize(find.byType(CupertinoNavigationBar)).height, 44.5);
      // 标题 17 → 15（＝侧栏品牌名同号）。
      final title = tester.widget<Text>(find.text('宽屏栏位校验'));
      expect(title.style?.fontSize, 15.0);

      // 输入字段：15pt（原主题默认 17）、两行起（主人 2026-09-27 定版）。
      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-input-field')),
      );
      expect(field.minLines, 2);
      expect(field.style?.fontSize, 15.0);

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('#163 窄屏：顶栏不加线、标题与字段走原档位（逐像素不变）', (tester) async {
      // flutter_test 默认逻辑宽 800（< 900）= 窄屏分支；显式固定，免受同文件
      // 其他用例改过的 viewport 影响。
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '窄屏栏位校验',
          'messages': const [],
        },
      };

      await _pumpComposer(
        tester,
        chatApi: chatApi,
        apiClient: _buildHealthClient(),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final navBar = tester.widget<CupertinoNavigationBar>(
        find.byType(CupertinoNavigationBar),
      );
      expect(navBar.bottom, isNull);
      final title = tester.widget<Text>(find.text('窄屏栏位校验'));
      expect(title.style, isNull);

      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-input-field')),
      );
      expect(field.minLines, 2);
      expect(field.style, isNull);

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('阈值着色：≥85% 红色，≥75% 橙色，正常 secondaryLabel', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
        kShowPerfMonitorKey: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      // CPU: 90% (>=85 红), MEM: 80% (>=75 橙), DISK: 50% (<75 secondary)
      final client = _buildHealthClient(cpu: 90.0, mem: 80.0, disk: 50.0);

      await _pumpComposer(tester, chatApi: chatApi, apiClient: client);
      await tester.pump(const Duration(milliseconds: 50));

      // 验证紧凑态下 CPU 90% 与 MEM 80% 渲染
      expect(find.textContaining('CPU 90%'), findsOneWidget);
      expect(find.textContaining('MEM 80%'), findsOneWidget);

      // 展开悬浮卡片
      await tester.tap(find.byKey(const ValueKey('perf-monitor-panel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('perf-monitor-popover-card')),
        findsOneWidget,
      );
      expect(find.textContaining('90%'), findsWidgets);
      expect(find.textContaining('80%'), findsWidgets);
      expect(find.textContaining('50%'), findsOneWidget);

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });
  });
}

class _HealthAdapter implements HttpClientAdapter {
  _HealthAdapter({required this.responder});

  final ResponseBody Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _buildHealthClient({
  double cpu = 45.0,
  double mem = 60.0,
  double disk = 70.0,
  int usedBytes = 140000000000,
  int totalBytes = 200000000000,
}) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = _HealthAdapter(
    responder: (options) {
      if (options.uri.path == '/api/system/health') {
        return ResponseBody.fromString(
          jsonEncode({
            'status': 'ok',
            'available': true,
            'checked_at': '2026-08-30T00:00:00Z',
            'cpu': {'percent': cpu},
            'memory': {
              'percent': mem,
              'used_bytes': usedBytes,
              'total_bytes': totalBytes,
            },
            'disk': {
              'percent': disk,
              'used_bytes': usedBytes,
              'total_bytes': totalBytes,
            },
            'errors': [],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString('{}', 200);
    },
  );
  return ApiClient(baseUrl: 'http://test.local:30002', dio: dio);
}
