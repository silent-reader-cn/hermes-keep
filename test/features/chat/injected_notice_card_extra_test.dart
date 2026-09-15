import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/utils/injected_message.dart';
import 'package:hermes_ui/features/chat/widgets/injected_notice_card.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

/// 覆盖率补强：`InjectedNoticeCard`（此前 0%）。
///
/// 断言全部绑定实现里的真实行为：摘要文本（`InjectedMessage.extractSummary`）、
/// 折叠/展开按钮文案（`l10n.injectedNoticeShowOutput/HideOutput`）、
/// 正文可见性与 `maxHeight: 400` 约束、按 kind 分派的图标。
ChatMessage _msg(String? content, {String role = 'user'}) =>
    ChatMessage(role: role, content: content);

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

Future<void> _pumpCard(
  WidgetTester tester, {
  required ChatMessage message,
  required bool expanded,
  VoidCallback? onToggle,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: _delegates,
      home: CupertinoPageScaffold(
        child: InjectedNoticeCard(
          message: message,
          expanded: expanded,
          onToggle: onToggle ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 实现里 _backgroundSummary 的输出：'后台进程 proc_abc · 已完成'
  const backgroundContent =
      '[IMPORTANT: Background process proc_abc completed normally';
  const backgroundSummaryUpper = '后台进程 PROC_ABC · 已完成';

  group('InjectedNoticeCard 折叠/展开', () {
    testWidgets('折叠态：渲染大写摘要 + 「展开」按钮，正文不落地', (tester) async {
      await _pumpCard(
        tester,
        message: _msg(backgroundContent),
        expanded: false,
      );

      expect(find.text(backgroundSummaryUpper), findsOneWidget);
      expect(find.text('展开'), findsOneWidget);
      expect(find.text('收起'), findsNothing);
      // 折叠时正文（SelectableText）根本不构建
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text(backgroundContent), findsNothing);
    });

    testWidgets('展开态：正文进 SelectableText（挂 #81 右键菜单抑制器）+ 400 上限 + 「收起」', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        message: _msg(backgroundContent),
        expanded: true,
      );

      expect(find.text(backgroundSummaryUpper), findsOneWidget);
      expect(find.text('收起'), findsOneWidget);
      expect(find.text('展开'), findsNothing);

      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.data, backgroundContent);
      // #81：右键不叠原生「全选」工具条 → 必须接线 chatMessageTextContextMenu
      expect(selectable.contextMenuBuilder, isNotNull);
      final style = selectable.style!;
      expect(style.fontFamily, 'monospace');
      expect(style.fontSize, 12);
      expect(style.height, 1.5);

      final box = tester.widget<ConstrainedBox>(
        find.ancestor(
          of: find.byType(SelectableText),
          matching: find.byType(ConstrainedBox),
        ),
      );
      expect(box.constraints.maxHeight, 400);
    });

    testWidgets('content 为 null 时正文渲染空串（?? 兜底）', (tester) async {
      await _pumpCard(
        tester,
        message: _msg(null),
        expanded: true,
      );

      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        '',
      );
      // 非注入消息 → extractSummary 返回空串，标题行随之渲染为空
      final headerTexts = tester.widgetList<Text>(
        find.descendant(of: find.byType(Row), matching: find.byType(Text)),
      );
      expect(headerTexts.first.data, '');
      expect(find.text('收起'), findsOneWidget);
    });

    testWidgets('点击切换按钮把回调透传到 onToggle（折叠态与展开态各一次）', (tester) async {
      var toggles = 0;
      await _pumpCard(
        tester,
        message: _msg(backgroundContent),
        expanded: false,
        onToggle: () => toggles++,
      );

      await tester.tap(find.text('展开'));
      await tester.pump();
      expect(toggles, 1);

      await _pumpCard(
        tester,
        message: _msg(backgroundContent),
        expanded: true,
        onToggle: () => toggles++,
      );
      await tester.tap(find.text('收起'));
      await tester.pump();
      expect(toggles, 2);
    });

    testWidgets('摘要同时挂到外层 Semantics.label（无障碍读屏用原文非大写）', (tester) async {
      await _pumpCard(
        tester,
        message: _msg(backgroundContent),
        expanded: false,
      );

      expect(find.bySemanticsLabel('后台进程 proc_abc · 已完成'), findsWidgets);
    });
  });

  group('InjectedNoticeCard 图标按 kind 分派', () {
    // (用例名, 注入原文, 期望图标)
    final cases = <(String, String, IconData)>[
      (
        'backgroundProcess → command',
        '[IMPORTANT: Background process proc_abc completed normally',
        CupertinoIcons.command,
      ),
      (
        'backgroundProcessWatch → command',
        '[IMPORTANT: Background process watchdog matched watch pattern for proc_a',
        CupertinoIcons.command,
      ),
      (
        'backgroundProcessAggregated → command',
        '[IMPORTANT: Background processes completed: 2',
        CupertinoIcons.command,
      ),
      (
        'subagentAggregated → command',
        '[IMPORTANT: Background subagent delegations completed: 3',
        CupertinoIcons.command,
      ),
      (
        'overflow → command',
        '[IMPORTANT: Background process proc_x overflow watch_disabled',
        CupertinoIcons.command,
      ),
      (
        'skill → hammer',
        '[IMPORTANT: The user has invoked the "foo" skill',
        CupertinoIcons.hammer,
      ),
      (
        'skillBundle → hammer',
        '[IMPORTANT: The user has invoked the "foo" skill bundle',
        CupertinoIcons.hammer,
      ),
      (
        'skillAutoLoaded → hammer',
        '[IMPORTANT: The "foo" skill is auto-loaded',
        CupertinoIcons.hammer,
      ),
      (
        'cron → clock',
        '[IMPORTANT: You are running as a scheduled cron job.',
        CupertinoIcons.clock,
      ),
      (
        'mcp → cube_box',
        '[IMPORTANT: MCP servers have been reloaded',
        CupertinoIcons.cube_box,
      ),
      (
        'continuationNetworkCut → arrow_2_circlepath',
        '[System: The previous response was cut off by a network error mid-stream.]',
        CupertinoIcons.arrow_2_circlepath,
      ),
      (
        'continuationOutputLimit → arrow_2_circlepath',
        '[System: Your previous response was truncated by the output limit.]',
        CupertinoIcons.arrow_2_circlepath,
      ),
      (
        'continuationToolTooLarge → arrow_2_circlepath',
        '[System: Your previous tool call was too large to be processed.]',
        CupertinoIcons.arrow_2_circlepath,
      ),
      (
        'codexNudge(reasoning) → lightbulb',
        '[System: Your previous response contained only internal reasoning and no answer.]',
        CupertinoIcons.lightbulb,
      ),
      (
        'codexNudge(裸 nudge) → lightbulb',
        'Your previous turn indicated a tool call but none was included',
        CupertinoIcons.lightbulb,
      ),
      (
        'gatewayRecovery → info_circle',
        '[System note: The previous turn was interrupted by a shutdown; the gateway is now back online.]',
        CupertinoIcons.info_circle,
      ),
      (
        'sessionReset → info_circle',
        "[System note: The user's previous session was stopped and suspended.]",
        CupertinoIcons.info_circle,
      ),
      (
        'memoryRecall → info_circle',
        '[System note: The following is recalled memory context, NOT new user input.]',
        CupertinoIcons.info_circle,
      ),
      (
        'none（普通正文）→ command',
        'hello world',
        CupertinoIcons.command,
      ),
    ];

    for (final (name, content, icon) in cases) {
      testWidgets(name, (tester) async {
        final message = _msg(content);
        // 先钉住分类结果，图标断言才有意义（否则 kind 漂移会静默换图标）
        expect(
          InjectedMessage.classify(message),
          _expectedKindFor(content),
          reason: '分类漂移会改变图标语义，需同步更新本用例',
        );
        await _pumpCard(tester, message: message, expanded: false);
        expect(find.byIcon(icon), findsOneWidget);
      });
    }
  });
}

/// 与上面用例表一一对应的 kind 期望值（显式列全，避免测试自我循环）。
InjectedNoticeKind _expectedKindFor(String content) {
  switch (content) {
    case '[IMPORTANT: Background process proc_abc completed normally':
      return InjectedNoticeKind.backgroundProcess;
    case '[IMPORTANT: Background process watchdog matched watch pattern for proc_a':
      return InjectedNoticeKind.backgroundProcessWatch;
    case '[IMPORTANT: Background processes completed: 2':
      return InjectedNoticeKind.backgroundProcessAggregated;
    case '[IMPORTANT: Background subagent delegations completed: 3':
      return InjectedNoticeKind.subagentAggregated;
    case '[IMPORTANT: Background process proc_x overflow watch_disabled':
      return InjectedNoticeKind.overflow;
    case '[IMPORTANT: The user has invoked the "foo" skill':
      return InjectedNoticeKind.skill;
    case '[IMPORTANT: The user has invoked the "foo" skill bundle':
      return InjectedNoticeKind.skillBundle;
    case '[IMPORTANT: The "foo" skill is auto-loaded':
      return InjectedNoticeKind.skillAutoLoaded;
    case '[IMPORTANT: You are running as a scheduled cron job.':
      return InjectedNoticeKind.cron;
    case '[IMPORTANT: MCP servers have been reloaded':
      return InjectedNoticeKind.mcp;
    case '[System: The previous response was cut off by a network error mid-stream.]':
      return InjectedNoticeKind.continuationNetworkCut;
    case '[System: Your previous response was truncated by the output limit.]':
      return InjectedNoticeKind.continuationOutputLimit;
    case '[System: Your previous tool call was too large to be processed.]':
      return InjectedNoticeKind.continuationToolTooLarge;
    case '[System: Your previous response contained only internal reasoning and no answer.]':
      return InjectedNoticeKind.codexNudge;
    case 'Your previous turn indicated a tool call but none was included':
      return InjectedNoticeKind.codexNudge;
    case '[System note: The previous turn was interrupted by a shutdown; the gateway is now back online.]':
      return InjectedNoticeKind.gatewayRecovery;
    case "[System note: The user's previous session was stopped and suspended.]":
      return InjectedNoticeKind.sessionReset;
    case '[System note: The following is recalled memory context, NOT new user input.]':
      return InjectedNoticeKind.memoryRecall;
    case 'hello world':
      return InjectedNoticeKind.none;
    default:
      fail('未登记分类期望的用例内容：$content');
  }
}
