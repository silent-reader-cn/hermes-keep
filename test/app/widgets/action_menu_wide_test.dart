import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/widgets/adaptive_action_menu.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';

/// 批次 5B · §D3 共享宽屏菜单（`AdaptiveActionMenu`）密排护栏。
///
/// 契约（数值即规格）：
/// - 宽屏（≥900）行高 **30**、面板宽 **≤260**（调用方传更大的 preferredWidth 也要被压回）；
/// - `startsGroup` 按语义分组 ⇒ 插 0.5px 分组线（首项即使标了也不插）；
/// - 右侧快捷键列：显示 `ActionMenuShortcut.label`，且该组合**真正注册**（同一点击回调）；
/// - Apple 平台口径 `⌘/⇧/⌥`，其余平台 `Ctrl/Shift/Alt`（显示与注册同源）；
/// - 窄屏（<900）**完全不变**：仍是 `CupertinoActionSheet`（44 档），无密排行、无分组线、
///   无快捷键列。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AdaptivePopover.debugReset();
  });

  /// 起一个只有锚点按钮的最小页面；点按钮弹出被测菜单。
  Future<void> pumpMenu(
    WidgetTester tester, {
    required Size size,
    required List<AdaptiveMenuItem> items,
    String? title,
    double preferredWidth = 220,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                key: anchor,
                onPressed: () => unawaited(
                  AdaptiveActionMenu.show(
                    tester.element(find.byKey(anchor)),
                    anchorKey: anchor,
                    title: title,
                    preferredWidth: preferredWidth,
                    items: items,
                  ),
                ),
                child: const Text('打开菜单'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(anchor));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 发一个带修饰键的按键。
  Future<void> pressKey(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool meta = false,
    bool shift = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  const copyKey = ValueKey('t-copy');
  const copyMdKey = ValueKey('t-copy-md');
  const branchKey = ValueKey('t-branch');

  List<AdaptiveMenuItem> buildItems({required VoidCallback onCopy}) => [
    AdaptiveMenuItem(
      key: copyKey,
      label: '复制文本',
      icon: CupertinoIcons.doc_text,
      shortcut: ActionMenuShortcut.primary(LogicalKeyboardKey.keyC),
      onPressed: onCopy,
    ),
    AdaptiveMenuItem(
      key: copyMdKey,
      label: '复制 Markdown',
      icon: CupertinoIcons.doc_richtext,
      shortcut: ActionMenuShortcut.primary(
        LogicalKeyboardKey.keyC,
        shift: true,
      ),
      onPressed: () {},
    ),
    AdaptiveMenuItem(
      key: branchKey,
      label: '从此处创建分支',
      startsGroup: true,
      icon: CupertinoIcons.square_stack,
      onPressed: () {},
    ),
  ];

  group('§D3 宽屏密排', () {
    testWidgets('行高 30 · 宽 ≤260（调用方传 300 也被压回）· 分组线 · 快捷键列', (tester) async {
      var copies = 0;
      await pumpMenu(
        tester,
        size: const Size(1280, 900),
        title: '消息操作',
        preferredWidth: 300,
        items: buildItems(onCopy: () => copies++),
      );

      for (final key in const [copyKey, copyMdKey, branchKey]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, 30.0, reason: '§D3 宽屏行高必须 30');
        expect(
          size.width,
          lessThanOrEqualTo(260.0),
          reason: '§D3 宽屏菜单宽必须 ≤260',
        );
      }

      // 分组线：分支项标了 startsGroup ⇒ 恰 1 条（标题下那条另算）。
      expect(
        find.byType(ActionMenuDivider),
        findsNWidgets(2),
        reason: '§D3 标题下 1 条 + startsGroup 1 条 = 2 条分组线',
      );
      // 快捷键列：非 Apple 平台（flutter test 默认目标平台）显示 Ctrl 系。
      expect(find.text('Ctrl+C'), findsOneWidget);
      expect(find.text('Ctrl+Shift+C'), findsOneWidget);
      expect(copies, 0);
    });

    testWidgets('快捷键真的触发动作并关闭菜单（Ctrl+C）', (tester) async {
      var copies = 0;
      await pumpMenu(
        tester,
        size: const Size(1280, 900),
        items: buildItems(onCopy: () => copies++),
      );
      expect(find.byType(ActionMenuRow), findsNWidgets(3));

      await pressKey(tester, LogicalKeyboardKey.keyC, control: true);

      expect(copies, 1, reason: '§D3 右侧列画出的组合必须真的能触发（与点击同一个回调）');
      expect(find.byType(ActionMenuRow), findsNothing, reason: '快捷键命中后菜单应当关闭');
    });

    testWidgets('macOS 口径：画 ⌘ 且注册的就是 meta 组合', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        var copies = 0;
        await pumpMenu(
          tester,
          size: const Size(1280, 900),
          items: buildItems(onCopy: () => copies++),
        );
        expect(find.text('⌘C'), findsOneWidget);
        expect(find.text('⇧⌘C'), findsOneWidget);

        await pressKey(tester, LogicalKeyboardKey.keyC, meta: true);
        expect(copies, 1, reason: 'macOS 口径的 ⌘C 必须真的触发（显示与注册同源）');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('窄屏逐像素不变', () {
    testWidgets('仍走 CupertinoActionSheet（44 档）：无密排行 / 无分组线 / 无快捷键列', (
      tester,
    ) async {
      var copies = 0;
      await pumpMenu(
        tester,
        size: const Size(600, 800),
        items: buildItems(onCopy: () => copies++),
      );

      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byType(ActionMenuRow), findsNothing, reason: '窄屏不得出现密排行');
      expect(find.byType(ActionMenuDivider), findsNothing, reason: '窄屏不得出现分组线');
      for (final label in const ['Ctrl+C', 'Ctrl+Shift+C', '⌘C']) {
        expect(find.text(label), findsNothing, reason: '窄屏不得出现快捷键列');
      }

      final actionSize = tester.getSize(find.byKey(copyKey));
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

      // 窄屏点击仍然工作（同一份 items 语义不变）——`Copies` 计数不因密排而受影响。
      // 实际点击放到宽屏用例已覆盖，这里只确认取消按钮存在。
      expect(find.text('取消'), findsOneWidget);
    });
  });
}
