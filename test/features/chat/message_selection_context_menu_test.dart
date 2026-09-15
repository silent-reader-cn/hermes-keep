import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';

import '../../helpers/fake_chat_api.dart';

/// #134 选中正文后右键弹出两层菜单（原生文本工具条 + 自定义消息菜单）。
///
/// 守门契约：
/// - 桌面：一次右键**恒定只出一层**自定义消息菜单；原生工具条在任何选区状态下
///   都不得出现；有选区时菜单顶部含「复制选中文本」，复制内容 = 选中片段。
/// - 移动：两层菜单不得同现（长按选字与自定义菜单不会同时出现）。
///
/// 触发要点（实测得出，勿随意改动）：
/// 双击/拖选建立选区后，正文里的 SelectableText 会在手势竞技场中抢赢外层旧实现
/// `GestureDetector.onSecondaryTapDown` —— **快速右键（tapAt）外层收不到回调**
/// （自定义菜单 0 个）、慢速右键才收得到；两条链路各弹一层正是双层菜单的成因。
/// 故外层已改为 `Listener.onPointerDown`（不参与竞技场），本文件的 tapAt 断言
/// 同时充当「触发确定性」护栏。
///
/// 修复前基线（同一工装实测）：拖选后右键选区 / 双击后右键该词 → 原生工具条
/// 节点 = 4；安卓长按正文松手 → 节点 = 8（时序不稳定，见 RED-D 注释）。
///
/// 注意：`debugDefaultTargetPlatformOverride` 必须在**测试体内**复位，
/// 否则 Flutter 的 foundation 不变量检查会在收尾报
/// "The value of a foundation debug variable was changed by the test"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AdaptivePopover.debugReset();
  });

  Widget buildTestApp({
    required FakeChatApi api,
    Size size = const Size(1200, 800),
  }) {
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
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: CupertinoApp.router(
          routerConfig: router,
          localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        ),
      ),
    );
  }

  Future<void> boot(
    WidgetTester tester,
    String content, {
    TargetPlatform platform = TargetPlatform.windows,
    Size size = const Size(1200, 800),
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'messages': [
          {'role': 'assistant', 'content': content, 'message_id': 'm1'},
        ],
      },
    };
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildTestApp(api: api, size: size));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  int toolbarCount() => find
      .byWidgetPredicate(
        (w) => w.runtimeType.toString().contains('TextSelectionToolbar'),
      )
      .evaluate()
      .length;

  int menuCount() =>
      find.byKey(const ValueKey('msg-action-copy')).evaluate().length +
      find.byType(CupertinoActionSheet).evaluate().length;

  Future<void> doubleTapWord(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 慢速右键（按住 300ms 再松手）——最贴近真实鼠标右键。
  Future<void> rightClick(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('#134 选区感知的右键菜单', () {
    testWidgets('RED-A 双击选词后右键 → 原生工具条 0 个（基线 4）+ 自定义菜单恰 1 层 + 含「复制选中文本」', (tester) async {
      const fullText = 'alpha beta gamma delta epsilon';
      await boot(tester, fullText);

      final textFinder = find.text(fullText);
      expect(textFinder, findsOneWidget);
      await doubleTapWord(tester, textFinder);
      await rightClick(tester, tester.getRect(textFinder).center);

      expect(
        toolbarCount(),
        0,
        reason: '桌面右键不得出现任何原生文本选择工具条（修复前基线为 4）',
      );
      expect(find.text('全选'), findsNothing);
      expect(find.text('Select all'), findsNothing);
      expect(
        find.byKey(const ValueKey('msg-action-copy')),
        findsOneWidget,
        reason: '自定义消息菜单必须恰好出现一层',
      );
      expect(
        find.byKey(const ValueKey('msg-action-copy-selection')),
        findsOneWidget,
        reason: '有选区时菜单顶部必须出现「复制选中文本」',
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('RED-A2 拖选后右键选区 → 原生工具条 0 个（基线 4）+ 菜单 1 层 + 含选区项', (tester) async {
      const fullText = 'drag select this sentence for menu';
      await boot(tester, fullText);

      final textFinder = find.text(fullText);
      final rect = tester.getRect(textFinder);
      await tester.dragFrom(
        rect.centerLeft + const Offset(2, 0),
        Offset(rect.width * 0.7, 0),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await rightClick(tester, rect.center);

      expect(toolbarCount(), 0, reason: '拖选路径同样不得残留原生工具条');
      expect(find.byKey(const ValueKey('msg-action-copy')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('msg-action-copy-selection')),
        findsOneWidget,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('RED-B 无选区快速右键 → 自定义菜单稳定弹出 1 层，且不含「复制选中文本」', (tester) async {
      const fullText = 'no selection quick right click';
      await boot(tester, fullText);

      final textFinder = find.text(fullText);
      // 快速右键（down/up 同一帧）：旧实现下被 SelectableText 抢赢竞技场 → 菜单 0 个。
      await tester.tapAt(
        tester.getRect(textFinder).center,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('msg-action-copy')),
        findsOneWidget,
        reason: '右键必须稳定弹出自定义菜单（Listener 触发不参与手势竞技场）',
      );
      expect(
        find.byKey(const ValueKey('msg-action-copy-selection')),
        findsNothing,
        reason: '无选区时不得出现「复制选中文本」',
      );
      expect(toolbarCount(), 0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('RED-C 点「复制选中文本」→ 剪贴板写入选中片段而非整条消息', (tester) async {
      const fullText = 'apple banana cherry durian';
      await boot(tester, fullText);

      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final args = methodCall.arguments as Map<dynamic, dynamic>?;
            clipboardText = args?['text'] as String?;
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

      final textFinder = find.text(fullText);
      await doubleTapWord(tester, textFinder);
      await rightClick(tester, tester.getRect(textFinder).center);

      final itemFinder = find.byKey(const ValueKey('msg-action-copy-selection'));
      expect(itemFinder, findsOneWidget);
      await tester.tap(itemFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(clipboardText, isNotNull, reason: '点击后必须写入剪贴板');
      expect(clipboardText, isNotEmpty);
      expect(
        clipboardText,
        isNot(equals(fullText)),
        reason: '复制的应是选中片段，而不是整条消息',
      );
      expect(
        fullText.split(' '),
        contains(clipboardText),
        reason: '复制内容应为被双击选中的那个词',
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('RED-D 移动端不变量：长按正文时原生工具条与自定义菜单不得同现', (tester) async {
      // 说明：工装里「安卓长按选字后工具条是否渲染」本身时序不稳定（实测同一手势
      // 下 builder 可能拿到 collapsed 选区 → 不渲染），故此处不做「工具条必须出现」
      // 的脆弱断言；移动端「保留工具条」的策略由 message_context_menu_native_toolbar_test
      // 的 builder 单元级用例（android + 非折叠选区 → 返回 Toolbar）确定性守住。
      // 本用例守住的是本 bug 的本质不变量：**两层菜单永不同现**。
      await boot(
        tester,
        'android long press no double menu',
        platform: TargetPlatform.android,
        size: const Size(400, 700),
      );

      final textFinder = find.text('android long press no double menu');
      final gesture = await tester.startGesture(tester.getRect(textFinder).center);
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final toolbars = toolbarCount();
      final menus = menuCount();
      expect(
        toolbars == 0 || menus == 0,
        isTrue,
        reason: '原生工具条($toolbars)与自定义菜单($menus)不得同时出现',
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('RED-E 移动端：窄屏长按气泡留白 → 自定义 ActionSheet 1 层', (tester) async {
      await boot(
        tester,
        'android long press bubble padding',
        platform: TargetPlatform.android,
        size: const Size(400, 700),
      );

      final textFinder = find.text('android long press bubble padding');
      final bubble = find
          .ancestor(of: textFinder, matching: find.byType(ChatMessageBubble))
          .first;
      await tester.longPressAt(
        tester.getRect(bubble).topLeft + const Offset(6, 6),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-copy')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
