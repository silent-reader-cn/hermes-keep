import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/chat/widgets/chat_text_selection.dart';

import '../../helpers/fake_chat_api.dart';

/// #81 → #134 桌面右键聊天正文：Flutter 原生选择工具条不得叠在自定义消息菜单之上。
///
/// #81（2026-09-13）只压了「无选区」那一半，有选区时仍放行原生工具条；
/// #134（2026-09-15 主人拍板）改为：**桌面端**任何选区状态下都抑制原生工具条，
/// 一次右键恒定只出一层自定义消息菜单，选区复制由菜单项「复制选中文本」承载；
/// **移动端**保留原生工具条（实测长按选字时自定义菜单不会同现，工具条是移动端
/// 选中即复制的唯一入口）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AdaptivePopover.debugReset();
  });

  Widget buildTestApp({required FakeChatApi api}) {
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
        data: const MediaQueryData(size: Size(1200, 800)),
        child: CupertinoApp.router(
          routerConfig: router,
          localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        ),
      ),
    );
  }

  Future<void> boot(
    WidgetTester tester,
    List<Map<String, String?>> messages,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': messages},
    };
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildTestApp(api: api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('#81/#134 右键正文不叠原生选择工具条', () {
    testWidgets('右键 assistant markdown 正文 → 原生「全选」工具条不弹出', (tester) async {
      await boot(tester, [
        {
          'role': 'assistant',
          'content': '右键测试正文段落，这里不该叠出全选条。',
          'message_id': 'm1',
        },
      ]);

      final rect = tester.getRect(find.text('右键测试正文段落，这里不该叠出全选条。'));
      await tester.tapAt(rect.center, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 修复前该工装路径必现原生工具条（无修复基线实测 selall=1 / toolbar 节点=4）。
      expect(find.text('Select all'), findsNothing);
      expect(find.text('全选'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().contains('TextSelectionToolbar'),
        ),
        findsNothing,
        reason: '聊天正文右键不得出现任何原生文本选择工具条',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('右键 user MEDIA markdown 气泡正文 → 同样不弹出', (tester) async {
      await boot(tester, [
        {
          'role': 'user',
          'content': 'MEDIA: https://example.invalid/a.png\n这段文字在媒体气泡里',
          'message_id': 'm2',
        },
      ]);

      final textFinder = find.textContaining('这段文字在媒体气泡里');
      expect(textFinder, findsWidgets);
      final rect = tester.getRect(textFinder.first);
      await tester.tapAt(rect.center, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Select all'), findsNothing);
      expect(find.text('全选'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('正文仍为可选中 SelectableText（拖选/双击选字能力未收回）', (tester) async {
      await boot(tester, [
        {
          'role': 'assistant',
          'content': '可选中正文能力回归检查。',
          'message_id': 'm3',
        },
      ]);

      final selectable = find.descendant(
        of: find.byType(ChatMessageList),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'SelectableText',
        ),
      );
      expect(selectable, findsWidgets, reason: '正文仍为可选中 SelectableText');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('#134 chatMessageTextContextMenu 行为（桌面抑制 / 移动保留）', () {
    testWidgets('桌面（Windows）：空选区与有选区均返回零尺寸抑制占位', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final controller = TextEditingController(text: '一二三四五六七八');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(CupertinoApp(
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        home: Center(
          child: SizedBox(
            width: 200,
            child: EditableText(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(),
              cursorColor: CupertinoColors.label,
              backgroundCursorColor: CupertinoColors.systemGrey,
              readOnly: true,
              contextMenuBuilder: chatMessageTextContextMenu,
            ),
          ),
        ),
      ));
      await tester.pump();

      final editableFinder = find.byType(EditableText);
      final state = tester.state<EditableTextState>(editableFinder);
      final ctx = tester.element(editableFinder);

      // 无选区：抑制为零尺寸占位。
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(
        chatMessageTextContextMenu(ctx, state),
        isA<SizedBox>(),
        reason: 'collapsed 选区右键应抑制原生工具条',
      );

      // 有选区：新契约（主人 2026-09-15 拍板：一次右键只出一层自定义菜单，
      // 选区复制改由自定义菜单项「复制选中文本」承载）——桌面端无条件返回 SizedBox。
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();
      final out = chatMessageTextContextMenu(ctx, state);
      expect(
        out,
        isA<SizedBox>(),
        reason: '桌面端有选区时也必须返回空 SizedBox 抑制原生工具条',
      );
      expect(
        out.runtimeType.toString().contains('Toolbar'),
        isFalse,
        reason: '桌面端不允许出现任何原生文本选择工具条',
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('移动端（Android）：空选区抑制，有选区保留原生工具条', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final controller = TextEditingController(text: '一二三四五六七八');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(CupertinoApp(
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        home: Center(
          child: SizedBox(
            width: 200,
            child: EditableText(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(),
              cursorColor: CupertinoColors.label,
              backgroundCursorColor: CupertinoColors.systemGrey,
              readOnly: true,
              contextMenuBuilder: chatMessageTextContextMenu,
            ),
          ),
        ),
      ));
      await tester.pump();

      final editableFinder = find.byType(EditableText);
      final state = tester.state<EditableTextState>(editableFinder);
      final ctx = tester.element(editableFinder);

      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(chatMessageTextContextMenu(ctx, state), isA<SizedBox>());

      // 移动端长按选字时自定义菜单不会同现（实测：气泡外层长按手势被选字手势抢先，
      // 只有留白区长按才走自定义菜单），原生工具条是移动端「选中即复制」的唯一入口
      // → 必须保留，否则移动端失去复制能力。
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();
      final out = chatMessageTextContextMenu(ctx, state);
      expect(
        out.runtimeType.toString(),
        contains('Toolbar'),
        reason: '移动端有选区时必须保留原生工具条（选中即复制唯一入口）',
      );
      expect(out, isNot(isA<SizedBox>()));
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
