import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';

import '../../golden/golden_helpers.dart';
import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 批次 5B · §D3（宽屏右键菜单密排）+ §D4（菜单触发三入口统一）验收护栏。
///
/// 契约（数值即规格，改坏必红）：
/// - **§D3 密排**：宽屏菜单行高 **30**（触屏档 44 是手指档位，鼠标端不要）、
///   面板宽 **260**（≤260）、按语义分组的分组线（复制 / 跳转 / 破坏性）、
///   右侧快捷键列（复制文本 / 复制 Markdown / 复制选中文本 / 编辑并重新发送）；
/// - **§D3 快捷键必须真的能触发**：右侧列画出的组合与点击走**同一个回调**
///   ⇒ 本文件用真实按键（Ctrl+C / Ctrl+Shift+C / Ctrl+Alt+C / Enter）验证
///   剪贴板与编辑回填，杜绝「只显示不触发」的伪造功能；
/// - **§D4 三入口一致**：右键 / 悬停「⋯」/ 键盘（Shift+F10 或 Menu 键）打开的
///   是**同一个菜单**（按键集合逐个相同），键盘入口的焦点行带 2px 蓝焦点环；
/// - **窄屏不变**：仍走长按 → `CupertinoActionSheet`（44 行），无密排行、无分组线、
///   无快捷键列、无悬停「⋯」、无焦点环。
///
/// 报错口径：断言文案里写「实测 vs 期望」，RED 时能一眼看出坏在哪条规格。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 目检图要能读中文：与金照/其它工装同一套字体装载（不影响文本断言）。
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  tearDown(() {
    AdaptivePopover.debugReset();
  });

  Widget buildTestApp({required FakeChatApi api, required Size size}) {
    final router = GoRouter(
      initialLocation: '/chat/s1',
      routes: [
        GoRoute(
          path: '/chat/:id',
          builder: (context, state) =>
              ChatPage(sessionId: state.pathParameters['id'] ?? 's1'),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(api),
        // 连接库走 flutter_secure_storage（测试环境没有该插件）⇒ 注入内存实现，
        // 否则侧栏/输入栏的异步读取会抛 MissingPluginException 污染用例。
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: InMemorySecureStorage()),
        ),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: CupertinoApp.router(
          routerConfig: router,
          // 目检工装出图：关掉 debug banner（主仓其它出图工装同样设置）。
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        ),
      ),
    );
  }

  /// 起一个会话页；[size] 决定宽窄（宽屏 1200，窄屏 600）。
  Future<FakeChatApi> boot(
    WidgetTester tester, {
    required List<Map<String, String?>> messages,
    Size size = const Size(1200, 800),
  }) async {
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': messages},
    };
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildTestApp(api: api, size: size));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return api;
  }

  /// 慢速右键（按住 300ms 再松手）—— #134 实测：正文的选字手势会抢赢快速右键。
  Future<void> rightClickRow(WidgetTester tester, String text) async {
    final rect = tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(ChatMessageBubble),
          )
          .first,
    );
    final gesture = await tester.startGesture(
      rect.topLeft + const Offset(8, 8),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 窄屏长按气泡留白。
  Future<void> longPressRow(WidgetTester tester, String text) async {
    final rect = tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(ChatMessageBubble),
          )
          .first,
    );
    await tester.longPressAt(rect.topLeft + const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 鼠标悬停整行（保持指针在行上，返回手势以便测试内继续移动）。
  Future<TestGesture> hoverRow(WidgetTester tester, String text) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    final rect = tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(ChatMessageBubble),
          )
          .first,
    );
    await gesture.moveTo(rect.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return gesture;
  }

  /// 发一个带修饰键的按键（Ctrl / ⌘ / Shift / Alt 由调用方置位）。
  Future<void> pressKey(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool meta = false,
    bool shift = false,
    bool alt = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(key);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 分组线（`ActionMenuDivider`）实例数 —— 不 import 新符号，按运行时类型名找。
  int dividerCount() => find
      .byWidgetPredicate((w) => w.runtimeType.toString() == 'ActionMenuDivider')
      .evaluate()
      .length;

  /// 当前宽屏菜单里可见行的 key 集合（判「三入口同一个菜单」用）。
  Set<String> visibleMenuKeys() {
    const keys = [
      'msg-action-copy',
      'msg-action-copy-md',
      'msg-action-copy-selection',
      'msg-action-edit',
      'msg-action-branch',
      'msg-action-truncate',
    ];
    return {
      for (final k in keys)
        if (find.byKey(ValueKey(k)).evaluate().isNotEmpty) k,
    };
  }

  /// 消息行（user 角色）的 2px 焦点环 —— §D4/G3：仅键盘导航时出现。
  final Finder focusRing = find.byWidgetPredicate((w) {
    if (w is! DecoratedBox) return false;
    final decoration = w.decoration;
    if (decoration is! BoxDecoration) return false;
    final border = decoration.border;
    return border is Border && border.top.width == 2;
  });

  /// 把键盘焦点交给消息行 —— 与其他行内元素无关地拿到该行的 `FocusNode`。
  ///
  /// 取 `chat-message-bubble` 元素：它的最近 `Focus` 祖先正是行级
  /// `FocusableActionDetector` 的节点（行内不再嵌别的 Focus 组件）。
  FocusNode messageRowFocusNode(WidgetTester tester) {
    final node = Focus.maybeOf(
      tester.element(find.byKey(const ValueKey('chat-message-bubble')).first),
    );
    expect(node, isNotNull, reason: '§D4 消息行必须是可聚焦的（键盘入口的前置）');
    return node!;
  }

  const userText = '帮我写一段 Python 数据清洗脚本';
  const assistantText = '好的，这是清洗脚本的骨架。';

  /// §D4「三入口打开同一个菜单」的期望内容：右键 / 悬停「⋯」/ 键盘三处逐个对齐它。
  const expectedWideMenuKeys = {
    'msg-action-copy',
    'msg-action-copy-md',
    'msg-action-edit',
    'msg-action-branch',
    'msg-action-truncate',
  };

  group('§D3 宽屏右键菜单密排', () {
    testWidgets('行高 30 · 面板宽 260 · 两组分组线 · 快捷键列文案可见', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
          {'role': 'assistant', 'content': assistantText, 'message_id': 'm2'},
        ],
      );
      await rightClickRow(tester, userText);

      for (final k in const [
        'msg-action-copy',
        'msg-action-copy-md',
        'msg-action-edit',
        'msg-action-branch',
        'msg-action-truncate',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(k)));
        expect(size.height, 30.0, reason: '§D3 宽屏行高必须是 30（触屏档 44 不得带进鼠标场景）');
        expect(
          size.width,
          lessThanOrEqualTo(260.0),
          reason: '§D3 宽屏菜单宽必须 ≤260',
        );
      }
      // 面板宽（含 1px 边框 ×2）：行内容 258 + 边框 2 = 260 ⇒ 恰好吃满规格上限。
      final rowWidth = tester
          .getSize(find.byKey(const ValueKey('msg-action-copy')))
          .width;
      expect(
        rowWidth,
        greaterThanOrEqualTo(256.0),
        reason: '§D3 密排菜单必须吃满规格宽度（行内容 258 = 面板 260 − 边框 2）',
      );

      // 分组线：复制族 / 跳转族 / 破坏性族 ⇒ 两组线。
      expect(dividerCount(), 2, reason: '§D3 三族之间必须有 2 条分组线（复制 / 跳转 / 破坏性）');

      // 快捷键列：Windows/Linux 口径（本用例平台 windows）显示 Ctrl 系。
      expect(find.text('Ctrl+C'), findsOneWidget);
      expect(find.text('Ctrl+Shift+C'), findsOneWidget);
      expect(find.text('Enter'), findsOneWidget);
      // 窄屏档 ActionSheet 不得同现。
      expect(find.byType(CupertinoActionSheet), findsNothing);
      // 右键入口的菜单内容（三入口都对齐这一份期望集合）。
      expect(
        visibleMenuKeys(),
        expectedWideMenuKeys,
        reason: '§D4 右键打开的消息菜单内容',
      );
    });

    testWidgets('macOS 口径：右侧列画 ⌘/⇧/⌥，且注册的就是 meta 组合', (tester) async {
      // 目标平台必须在**测试体内**复位（foundation 不变量检查在收尾会查它）。
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await boot(
          tester,
          messages: [
            {'role': 'user', 'content': userText, 'message_id': 'm1'},
          ],
        );
        await rightClickRow(tester, userText);

        expect(find.text('⌘C'), findsOneWidget);
        expect(find.text('⇧⌘C'), findsOneWidget);
        expect(find.text('↵'), findsOneWidget);

        // 真按键：⌘C ⇒ 复制文本（写入剪贴板 + 菜单关闭）。
        String? clipboardText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardText =
                  (call.arguments as Map<dynamic, dynamic>?)?['text']
                      as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await pressKey(tester, LogicalKeyboardKey.keyC, meta: true);

        expect(
          clipboardText,
          userText,
          reason: 'macOS 口径的 ⌘C 必须真的触发「复制文本」，不能只画标签',
        );
        expect(
          find.byType(CupertinoActionSheet),
          findsNothing,
          reason: '菜单在快捷键命中后应当关闭',
        );
        expect(
          find.byKey(const ValueKey('msg-action-copy')),
          findsNothing,
          reason: '菜单在快捷键命中后应当关闭（面板消失）',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('§D3 快捷键真的能触发动作', () {
    testWidgets('Ctrl+C → 复制文本（剪贴板写入整条消息，菜单关闭）', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
        ],
      );
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<dynamic, dynamic>?)?['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await rightClickRow(tester, userText);
      expect(find.byKey(const ValueKey('msg-action-copy')), findsOneWidget);

      await pressKey(tester, LogicalKeyboardKey.keyC, control: true);

      expect(
        clipboardText,
        userText,
        reason: 'Ctrl+C 与点击「复制文本」必须走同一个回调（真触发，不是装饰）',
      );
      expect(
        find.byKey(const ValueKey('msg-action-copy')),
        findsNothing,
        reason: '命中快捷键后菜单应当关闭',
      );
    });

    testWidgets('Ctrl+Shift+C → 复制 Markdown；菜单关闭', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'assistant', 'content': assistantText, 'message_id': 'm1'},
        ],
      );
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<dynamic, dynamic>?)?['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await rightClickRow(tester, assistantText);
      expect(find.text('Ctrl+Shift+C'), findsOneWidget);

      await pressKey(
        tester,
        LogicalKeyboardKey.keyC,
        control: true,
        shift: true,
      );

      expect(
        clipboardText,
        assistantText,
        reason: 'Ctrl+Shift+C 必须真的复制 Markdown',
      );
      expect(find.byKey(const ValueKey('msg-action-copy')), findsNothing);
    });

    testWidgets('Enter → 编辑并重新发送（截断 + 输入框回填）', (tester) async {
      final api = await boot(
        tester,
        messages: [
          {'role': 'user', 'content': '保留的第0条', 'message_id': 'm0'},
          {'role': 'assistant', 'content': '保留的助手回复', 'message_id': 'm1'},
          {'role': 'user', 'content': userText, 'message_id': 'm2'},
        ],
      );

      await rightClickRow(tester, userText);
      expect(find.text('Enter'), findsOneWidget);

      await pressKey(tester, LogicalKeyboardKey.enter);

      expect(api.truncateCalls, 1, reason: 'Enter 必须真的触发「编辑并重新发送」的截断语义');
      expect(api.truncateKeepCounts, [2]);
      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-input-field')),
      );
      expect(field.controller!.text, userText, reason: '输入框必须被回填');
    });

    testWidgets('有选区时 ⌥⌘C/Ctrl+Alt+C → 复制选中文本（不是整条）', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'assistant', 'content': assistantText, 'message_id': 'm1'},
        ],
      );
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<dynamic, dynamic>?)?['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      // 双击选词建立选区（与 #134 同一套触发方式）。
      final textFinder = find.text(assistantText);
      await tester.tap(textFinder);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(textFinder);
      await tester.pump(const Duration(milliseconds: 200));
      await rightClickRow(tester, assistantText);

      expect(
        find.byKey(const ValueKey('msg-action-copy-selection')),
        findsOneWidget,
      );
      expect(find.text('Ctrl+Alt+C'), findsOneWidget);

      await pressKey(tester, LogicalKeyboardKey.keyC, control: true, alt: true);

      expect(clipboardText, isNotNull, reason: 'Ctrl+Alt+C 必须真的复制选中片段');
      expect(
        clipboardText,
        isNot(equals(assistantText)),
        reason: '复制选中文本写的是片段，不是整条消息',
      );
    });
  });

  group('§D4 三入口统一（右键 / 悬停 ⋯ / 键盘）', () {
    testWidgets('入口①右键 → 菜单内容 = 期望集合（见 D3 用例）', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
        ],
      );
      await rightClickRow(tester, userText);
      expect(
        visibleMenuKeys(),
        expectedWideMenuKeys,
        reason: '§D4 入口①（右键）打开的消息菜单',
      );
    });

    testWidgets('入口②悬停整行 → 行尾浮出「⋯」，点它打开同一套菜单', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
        ],
      );

      const buttonKey = ValueKey('msg-row-hover-actions');
      expect(
        find.byKey(buttonKey),
        findsNothing,
        reason: '未悬停时不得常驻「⋯」（只有鼠标压上来才出现）',
      );

      final gesture = await hoverRow(tester, userText);
      expect(
        find.byKey(buttonKey),
        findsOneWidget,
        reason: '§D4 悬停整行必须浮出「⋯」入口',
      );

      await tester.tap(find.byKey(buttonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        visibleMenuKeys(),
        expectedWideMenuKeys,
        reason: '§D4 入口②（悬停「⋯」）打开的必须与右键同一个菜单',
      );
      await gesture.removePointer();
    });

    testWidgets('入口③键盘 Shift+F10 → 焦点行打开同一套菜单 + 2px 蓝焦点环', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
        ],
      );

      // 先发一次按键把 highlightMode 打到 traditional（G3：鼠标点击不出环）。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      messageRowFocusNode(tester).requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(focusRing, findsOneWidget, reason: '§D4 键盘导航时焦点行必须显示 2px 焦点环');

      await pressKey(tester, LogicalKeyboardKey.f10, shift: true);
      expect(
        visibleMenuKeys(),
        expectedWideMenuKeys,
        reason: '§D4 入口③（Shift+F10）打开的必须与右键同一个菜单',
      );

      // 关掉再验 Menu 键（Applications 键）走同一条链路。
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('msg-action-copy')), findsNothing);

      messageRowFocusNode(tester).requestFocus();
      await tester.pump();
      await pressKey(tester, LogicalKeyboardKey.contextMenu);
      expect(
        visibleMenuKeys(),
        expectedWideMenuKeys,
        reason: '§D4 Menu 键必须对焦点行打开同一菜单',
      );
    });

    testWidgets('快捷键与焦点解耦：输入框拿着焦点时 Ctrl+C 照样触发菜单动作', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
        ],
      );

      // 用户正在输入（焦点在输入框）——这是「快捷键靠抢焦点实现」会翻车的场景。
      final field = find.byKey(const ValueKey('chat-input-field'));
      await tester.showKeyboard(field);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        isNotNull,
        reason: '前置：输入框拿到焦点',
      );

      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<dynamic, dynamic>?)?['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await rightClickRow(tester, userText);
      expect(find.byKey(const ValueKey('msg-action-copy')), findsOneWidget);

      await pressKey(tester, LogicalKeyboardKey.keyC, control: true);

      expect(
        clipboardText,
        userText,
        reason:
            '菜单快捷键走 HardwareKeyboard handler（与焦点解耦）：'
            '焦点在输入框上时也必须触发，不得被输入框的复制吃掉',
      );
      expect(
        find.byKey(const ValueKey('msg-action-copy')),
        findsNothing,
        reason: '命中快捷键后菜单应当关闭',
      );
      // 焦点归属说明：菜单打开会让输入框失焦（**上游既有行为**，基线同样如此，
      // 与本批无关），故本批不承诺焦点还原，只承诺「快捷键不依赖焦点」。
    });

    testWidgets('Tab 遍历可达消息行（纯键盘可达，不靠鼠标）', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
        ],
      );

      var reached = false;
      for (var i = 0; i < 60 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        reached = focusRing.evaluate().isNotEmpty;
      }
      expect(reached, isTrue, reason: '§D4 消息行必须能被 Tab 遍历到（否则「键盘入口」只是理论可达）');
    });

    testWidgets('鼠标点击不出焦点环（G3：环只认键盘导航）', (tester) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
        ],
      );
      // 真实鼠标点击（触摸指针会把 highlightMode 打到 touch，鼠标更贴场景）。
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      final center = tester.getCenter(find.text(userText));
      await gesture.moveTo(center);
      await tester.pump();
      await gesture.down(center);
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(focusRing, findsNothing, reason: '§G3 焦点环仅键盘导航触发；鼠标点击不得出环');
    });
  });

  group('窄屏逐像素不变（长按 + ActionSheet 44 档）', () {
    testWidgets('长按 → CupertinoActionSheet；无密排行 / 无分组线 / 无快捷键列 / 无悬停 ⋯', (
      tester,
    ) async {
      await boot(
        tester,
        messages: [
          {'role': 'user', 'content': userText, 'message_id': 'm1'},
        ],
        size: const Size(600, 800),
      );

      await longPressRow(tester, userText);

      expect(
        find.byType(CupertinoActionSheet),
        findsOneWidget,
        reason: '窄屏必须仍是长按 → CupertinoActionSheet（触屏档）',
      );
      expect(dividerCount(), 0, reason: '窄屏不得出现宽屏分组线');
      for (final label in const [
        'Ctrl+C',
        'Ctrl+Shift+C',
        'Ctrl+Alt+C',
        'Enter',
        '⌘C',
      ]) {
        expect(find.text(label), findsNothing, reason: '窄屏不得出现快捷键列');
      }
      // 窄屏不给悬停/键盘入口（MouseRegion/Focus 都不挂）。
      expect(
        find.byKey(const ValueKey('msg-row-hover-actions')),
        findsNothing,
        reason: '窄屏不得常驻「⋯」入口',
      );

      // 触屏档行高：ActionSheet 的动作行高于密排档 30。
      final actionSize = tester.getSize(
        find.byKey(const ValueKey('msg-action-copy')),
      );
      expect(
        actionSize.height,
        greaterThan(30.0),
        reason: '窄屏动作行必须是触屏档（>30），不得被密排压扁',
      );
      expect(
        actionSize.height,
        greaterThanOrEqualTo(44.0),
        reason: '窄屏动作行高 ≥44（手指档位）',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 真渲染目检工装（**非金照基线、不参与 CI 比对**）
  //
  // 用法：MENU_SHOTS=1 C:/tmp/f.bat test test/features/chat/message_menu_entry_test.dart
  //       --update-goldens     → 产物 .shots/*.png（.gitignore 已排除）
  // 目的：文本断言抓不到视觉问题（分组线是否可见、快捷键列是否与标签打架、
  // 窄屏 ActionSheet 是否被改动），必须出真图人工核对。
  // ---------------------------------------------------------------------------
  final bool capture = Platform.environment['MENU_SHOTS'] == '1';
  const String skipReason = '设置 MENU_SHOTS=1 才生成菜单真渲染目检图';

  test('工装环境自检', () {
    expect(capture, isTrue, reason: skipReason);
  }, skip: !capture);

  testWidgets('目检图 · 宽屏右键菜单（浅色）', (tester) async {
    Directory('.shots').createSync(recursive: true);
    await boot(
      tester,
      messages: [
        {'role': 'user', 'content': userText, 'message_id': 'm1'},
        {'role': 'assistant', 'content': assistantText, 'message_id': 'm2'},
      ],
    );
    await rightClickRow(tester, userText);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('../../../.shots/wide_message_menu_light.png'),
    );
  }, skip: !capture);

  testWidgets('目检图 · 窄屏长按操作表（浅色）', (tester) async {
    Directory('.shots').createSync(recursive: true);
    await boot(
      tester,
      messages: [
        {'role': 'user', 'content': userText, 'message_id': 'm1'},
      ],
      size: const Size(600, 800),
    );
    await longPressRow(tester, userText);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('../../../.shots/narrow_message_sheet_light.png'),
    );
  }, skip: !capture);
}
