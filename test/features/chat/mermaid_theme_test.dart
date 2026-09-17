// Mermaid 明暗主题链路守卫。
//
// 三处都必须跟随**应用**亮度（而非系统亮度）：
//   1. 聊天气泡内的图表（resolveMermaidTheme 按 CupertinoTheme.brightness 分流）；
//   2. 全屏查看页的页面壳与导航栏；
//   3. 全屏查看页包内 pan/zoom 控件（vendor patch：mermaid_flutter 原本硬编码浅色）。
//
// 断言方式是「实测取色 + WCAG 对比度下限」，而不是只比对常量——这样包升级
// 或后续改动一旦把某处拉回硬编码，这里会立刻变红。
// ignore_for_file: depend_on_referenced_packages

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons, Material;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';
import 'package:hermes_ui/features/chat/widgets/mermaid_block.dart';
import 'package:hermes_ui/features/chat/widgets/mermaid_fullscreen_page.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全屏页深色页底（iOS systemGray6 dark）——patch 前的原值，逐字节保留。
const Color _kDarkPageBackground = Color(0xFF1C1C1E);

const String _kDiagram = '```mermaid\ngraph TD\n  A-->B\n```';

Widget _app({
  required Brightness brightness,
  required Widget child,
  bool scaffold = true,
}) => CupertinoApp(
  theme: buildCupertinoTheme(brightness),
  locale: const Locale('zh'),
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh'), Locale('en')],
  home: scaffold ? CupertinoPageScaffold(child: child) : child,
);

/// WCAG 2.x 相对亮度 / 对比度（越界防护：纯函数，无副作用）。
double _channel(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color color) =>
    0.2126 * _channel(color.r) +
    0.7152 * _channel(color.g) +
    0.0722 * _channel(color.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 取某个 Text 实际绘制用的颜色（动态色按当前 context 解析）。
Color _resolvedTextColor(WidgetTester tester, String text) {
  final finder = find.text(text);
  final style = tester.renderObject<RenderParagraph>(finder).text.style;
  final color = style?.color;
  expect(color, isNotNull, reason: '「$text」应有显式文字颜色');
  return CupertinoDynamicColor.resolve(color!, tester.element(finder));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('聊天气泡内图表跟随应用明暗', () {
    testWidgets('亮→暗→亮 三态下 MermaidDiagram.theme 逐态切换且可逆', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      Widget build(Brightness brightness) => _app(
        brightness: brightness,
        child: ProviderScope(
          child: Builder(
            builder: (context) => MarkdownBody(
              data: _kDiagram,
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            ),
          ),
        ),
      );

      core.MermaidTheme currentTheme() => tester
          .widget<MermaidDiagram>(find.byKey(const ValueKey('mermaid-diagram')))
          .theme;

      await tester.pumpWidget(build(Brightness.light));
      await tester.pumpAndSettle();
      expect(currentTheme(), core.MermaidTheme.defaultTheme);

      await tester.pumpWidget(build(Brightness.dark));
      await tester.pumpAndSettle();
      expect(currentTheme(), kMermaidDarkTheme);

      await tester.pumpWidget(build(Brightness.light));
      await tester.pumpAndSettle();
      expect(currentTheme(), core.MermaidTheme.defaultTheme);
    });

    testWidgets('点全屏后，全屏页收到的图表主题与气泡一致', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      for (final entry in {
        Brightness.light: core.MermaidTheme.defaultTheme,
        Brightness.dark: kMermaidDarkTheme,
      }.entries) {
        await tester.pumpWidget(
          _app(
            brightness: entry.key,
            child: ProviderScope(
              child: Builder(
                builder: (context) => MarkdownBody(
                  data: _kDiagram,
                  styleSheet: buildAssistantMarkdownStyleSheet(context),
                  builders: createAssistantMarkdownBuilders(context),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('mermaid-fullscreen-button')),
        );
        await tester.pumpAndSettle();

        final view = tester.widget<MermaidView>(
          find.byKey(const ValueKey('mermaid-fullscreen-view')),
        );
        expect(view.theme, entry.value, reason: '${entry.key} 下图表主题应跟随');

        await tester.tap(find.byIcon(CupertinoIcons.xmark));
        await tester.pumpAndSettle();
      }
    });
  });

  group('全屏查看页跟随应用明暗', () {
    Future<void> pumpFullscreen(
      WidgetTester tester,
      Brightness brightness,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          scaffold: false,
          child: MermaidFullscreenPage(
            source: 'graph TD\n  A-->B',
            theme: brightness == Brightness.dark
                ? kMermaidDarkTheme
                : core.MermaidTheme.defaultTheme,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('亮色：页底走浅色面令牌，标题对页底满足正文 AA', (tester) async {
      await pumpFullscreen(tester, Brightness.light);

      final scaffold = tester.widget<CupertinoPageScaffold>(
        find.byType(CupertinoPageScaffold),
      );
      expect(scaffold.backgroundColor, LightSurfaces.page);

      final titleColor = _resolvedTextColor(tester, 'Mermaid 图表');
      expect(
        _contrast(titleColor, LightSurfaces.page),
        greaterThanOrEqualTo(4.5),
        reason: '浅色页底上标题必须可读',
      );
    });

    testWidgets('暗色：页底保持原 iOS 系统灰，标题对页底满足正文 AA', (tester) async {
      await pumpFullscreen(tester, Brightness.dark);

      final scaffold = tester.widget<CupertinoPageScaffold>(
        find.byType(CupertinoPageScaffold),
      );
      expect(scaffold.backgroundColor, _kDarkPageBackground);

      final titleColor = _resolvedTextColor(tester, 'Mermaid 图表');
      expect(
        _contrast(titleColor, _kDarkPageBackground),
        greaterThanOrEqualTo(4.5),
        reason: '深色页底上标题必须可读',
      );
    });

    testWidgets('包内 pan/zoom 控件：亮/暗两套色板且图标对按钮底满足图形 AA', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pumpFullscreen(tester, brightness);

        final zoomIn = find.byIcon(Icons.add);
        expect(zoomIn, findsOneWidget, reason: '全屏页应显示包内缩放控件');

        final icon = tester.widget<Icon>(zoomIn);
        final button = tester.widget<Material>(
          find.ancestor(of: zoomIn, matching: find.byType(Material)).first,
        );
        final expectedIcon = brightness == Brightness.dark
            ? const Color(0xFFF2F2F7)
            : const Color(0xFF4A4458);
        expect(icon.color, expectedIcon, reason: '$brightness 下控件图标色应跟随');

        expect(
          _contrast(icon.color!, button.color!),
          greaterThanOrEqualTo(3.0),
          reason: '$brightness 下控件图标对按钮底必须可辨',
        );
      }
    });
  });
}
