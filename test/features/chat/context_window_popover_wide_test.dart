import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';
import 'package:hermes_ui/core/models/context_window_snapshot.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/context_window_popover.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_chat_api.dart';

/// 上下文弹层宽窄分流验收（设计稿 `dialog-family-proposal.html` §3 推荐①）：
///
/// - 宽屏（>=900，`isWideLayout`）：宽 300、大数字（窗口上限）+「已用 X · 上限 Y」
///   副行、占用进度条、四项数值 13pt 右对齐、**去掉**底部「关闭」行；
/// - 窄屏（<900）：宽 260、`tokensLabel` 行、四项数值 12pt、保留「关闭」行
///   —— 逐像素维持改造前排版（本组用例把两条分流的关键差异钉死）；
/// - 无数据文案两态共用 l10n（`l10n.unavailable`），不再出现 formatter 里
///   硬编码的英文 'Unavailable'（缺陷修复）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fullSnapshot = ContextWindowSnapshot.fromJson({
    'context_length': 128000,
    'last_prompt_tokens': 1200,
    'input_tokens': 800,
    'output_tokens': 400,
    'threshold_tokens': 96000,
    'estimated_cost': 0.0123,
  });
  final emptySnapshot = ContextWindowSnapshot.fromJson(const {});

  Widget host({required Widget child, Locale locale = const Locale('zh')}) {
    final fakeChat = FakeChatApi();
    fakeChat.sessionResult = {
      'session': {'session_id': 's1', 'workspace': null},
    };
    return ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(fakeChat),
        chatAvailableModelsProvider.overrideWithValue(const ['gpt-4o']),
      ],
      child: CupertinoApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: CupertinoPageScaffold(child: Center(child: child)),
      ),
    );
  }

  Widget popover(ContextWindowSnapshot snapshot) => ContextWindowPopover(
    sessionId: 's1',
    snapshot: snapshot,
    currentModel: 'gpt-4o',
    onClose: () {},
  );

  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('宽屏（>=900）重排', () {
    testWidgets('宽 300：大数字 + 已用/上限副行 + 进度条 + 数值 13pt + 去「关闭」行', (
      tester,
    ) async {
      useViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(host(child: popover(fullSnapshot)));
      await settle(tester);

      expect(tester.getSize(find.byType(ContextWindowPopover)).width, 300);
      // 大数字 = 窗口上限；副行 = 已用 · 上限
      expect(
        find.byKey(const ValueKey('context-popover-window-label')),
        findsOneWidget,
      );
      expect(find.text('128.0K'), findsOneWidget);
      expect(find.text('已用 1.2K · 上限 128.0K'), findsOneWidget);
      // 进度条
      expect(
        find.byKey(const ValueKey('context-popover-usage-bar')),
        findsOneWidget,
      );
      // 去「关闭」行（点外部即关）
      expect(find.byKey(const ValueKey('context-popover-close')), findsNothing);
      // 四项数值：13pt（kFontLabel）右对齐
      final thresholdValue = tester.widget<Text>(find.text('96.0K (75%)'));
      expect(thresholdValue.style?.fontSize, kFontLabel);
      expect(thresholdValue.style?.fontWeight, FontWeight.w500);
      expect(thresholdValue.textAlign, TextAlign.right);
      expect(tester.widget<Text>(find.text('800')).style?.fontSize, kFontLabel);
      // 窄屏头部样式不出现
      expect(find.text('1.2K / 128.0K'), findsNothing);
    });

    testWidgets('无数据（宽屏）：数值退次级色 + 文案走 l10n 中文', (tester) async {
      useViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(host(child: popover(emptySnapshot)));
      await settle(tester);

      expect(find.text('Unavailable'), findsNothing);
      // 大数字 + 四项数值 + 副行（无数据时副行不渲染，只剩大数字）
      expect(find.text('暂无数据'), findsNWidgets(5));
      // 大数字保持强调字重；四项数值退为不加粗（设计稿 .kv .v.muted）
      final windowText = tester.widget<Text>(
        find.byKey(const ValueKey('context-popover-window-label')),
      );
      expect(windowText.style?.fontWeight, FontWeight.w500);
      final mutedValues = tester
          .widgetList<Text>(find.text('暂无数据'))
          .where((t) => t.style?.fontWeight == FontWeight.w400)
          .toList();
      expect(mutedValues.length, 4);
      expect(mutedValues.first.style?.fontSize, kFontLabel);
    });

    testWidgets('英文语言下无数据文案为 Unavailable（本地化而非硬编码）', (tester) async {
      useViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(
        host(child: popover(emptySnapshot), locale: const Locale('en')),
      );
      await settle(tester);

      expect(find.text('暂无数据'), findsNothing);
      expect(find.text('Unavailable'), findsNWidgets(5));
    });
  });

  group('窄屏（<900）逐像素维持原排版', () {
    testWidgets('宽 260：tokensLabel 行 + 数值 12pt + 保留「关闭」行 + 无进度条', (
      tester,
    ) async {
      useViewport(tester, const Size(800, 600));
      await tester.pumpWidget(host(child: popover(fullSnapshot)));
      await settle(tester);

      expect(tester.getSize(find.byType(ContextWindowPopover)).width, 260);
      expect(find.text('1.2K / 128.0K'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('context-popover-window-label')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('context-popover-usage-bar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('context-popover-close')),
        findsOneWidget,
      );
      final thresholdValue = tester.widget<Text>(find.text('96.0K (75%)'));
      expect(thresholdValue.style?.fontSize, kFontCaption);
      expect(thresholdValue.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('400 手机视口同样走窄屏排版（无宽屏分支渗漏）', (tester) async {
      useViewport(tester, const Size(400, 700));
      await tester.pumpWidget(host(child: popover(fullSnapshot)));
      await settle(tester);

      expect(tester.getSize(find.byType(ContextWindowPopover)).width, 260);
      expect(find.text('1.2K / 128.0K'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('context-popover-usage-bar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('context-popover-close')),
        findsOneWidget,
      );
    });

    testWidgets('无数据（窄屏）：中文「暂无数据」而非英文 Unavailable', (tester) async {
      useViewport(tester, const Size(800, 600));
      await tester.pumpWidget(host(child: popover(emptySnapshot)));
      await settle(tester);

      expect(find.text('Unavailable'), findsNothing);
      // tokensLabel 行 + 四项数值
      expect(find.text('暂无数据'), findsNWidgets(5));
    });
  });
}
