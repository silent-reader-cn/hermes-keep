import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/insights/insights_api.dart';
import 'package:hermes_ui/features/insights/insights_page.dart';
import 'package:hermes_ui/features/onboarding/widgets/builtin_tab.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../features/insights/insights_test.dart' show sampleResponse;
import '../helpers/fake_insights_api.dart';

// ---------------------------------------------------------------------------
// 清晰度探针 · 第二批（洞察页 / 引导页内置服务卡）
//
// 目的同 `crispness_probe_test.dart`：量出 FittedBox 是否在**运行期真的**把
// 文字做了等比缩小（scale < 1 = 字形被重采样）。
//
// 用法：CRISPNESS_PROBE2=1 C:/tmp/f.bat test test/screenshots/crispness_probe_extra_test.dart
// 结果写到 `.shots/crispness/probe2.txt`。
// ---------------------------------------------------------------------------

final bool _probe = Platform.environment['CRISPNESS_PROBE2'] == '1';
const String _skipReason = '设置 CRISPNESS_PROBE2=1 才跑第二批清晰度探针';
const String _outPath = '.shots/crispness/probe2.txt';

final List<String> _log = <String>[];
void _emit(String s) {
  _log.add(s);
  // ignore: avoid_print
  print(s);
}

void _flush() {
  final f = File(_outPath);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(_log.join('\n'));
}

List<String> fittedLines(WidgetTester tester, String tag, double width) {
  final out = <String>[];
  for (final el in tester.allElements) {
    final ro = el.renderObject;
    if (ro is! RenderFittedBox || !ro.hasSize || ro.child == null) continue;
    final c = ro.child!;
    if (!c.hasSize || c.size.width <= 0 || c.size.height <= 0) continue;
    var scale = ro.size.width / c.size.width;
    final fy = ro.size.height / c.size.height;
    if (fy < scale) scale = fy;
    if (scale > 1.0) scale = 1.0;
    final fonts = <double>[];
    final texts = <String>[];
    void scan(Element e) {
      final r = e.renderObject;
      if (r is RenderParagraph) {
        final fs = r.text.style?.fontSize;
        if (fs != null) fonts.add(fs);
        final t = r.text.toPlainText().trim();
        if (t.isNotEmpty) texts.add(t);
      }
      e.visitChildren(scan);
    }

    scan(el);
    final uniq = fonts.toSet().toList()..sort();
    out.add(
      '$tag\tw=$width\tchild=${c.size.width.toStringAsFixed(1)}\town='
      '${ro.size.width.toStringAsFixed(1)}\tscale=${scale.toStringAsFixed(4)}\t'
      '[${uniq.map((f) => '${f.toStringAsFixed(1)}->${(f * scale).toStringAsFixed(2)}').join(' ')}]'
      '\t"${texts.toSet().join('/')}"',
    );
  }
  return out;
}

List<LocalizationsDelegate<Object>> _delegates() =>
    const <LocalizationsDelegate<Object>>[
      AppLocalizationsDelegate(),
      DefaultCupertinoLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ];

List<String> labelLines(
  WidgetTester tester,
  String tag,
  double width,
  List<String> labels,
) {
  final out = <String>[];
  for (final el in tester.allElements) {
    final r = el.renderObject;
    if (r is! RenderParagraph) continue;
    final t = r.text.toPlainText().trim();
    if (!labels.contains(t)) continue;
    final intrinsic = r.getMaxIntrinsicWidth(double.infinity);
    final oneLine = r.getMaxIntrinsicHeight(double.infinity);
    out.add(
      '$tag\tw=$width\t"$t"\twidth=${r.size.width.toStringAsFixed(1)}\t'
      'intrinsic=${intrinsic.toStringAsFixed(1)}\theight='
      '${r.size.height.toStringAsFixed(1)}\toneLine='
      '${oneLine.toStringAsFixed(1)}\t'
      '${r.size.height > oneLine + 0.5 ? 'WRAPPED' : 'single-line'}',
    );
  }
  return out;
}

void main() {
  setUpAll(loadHermesGoldenFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('洞察页时间范围分段控件缩放探针', (tester) async {
    if (!_probe) {
      markTestSkipped(_skipReason);
      return;
    }
    for (final english in <bool>[false, true]) {
      for (final width in <double>[360, 390, 430, 480, 800, 1280]) {
        LocaleResolver.reset(
          mode: english ? AppLocaleMode.en : AppLocaleMode.zh,
        );
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final api = FakeInsightsApi(response: sampleResponse());
        final router = GoRouter(
          initialLocation: '/',
          routes: [GoRoute(path: '/', builder: (_, _) => const InsightsPage())],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(
                ApiClient(baseUrl: 'http://test.local:30002'),
              ),
              insightsApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: CupertinoApp.router(
              routerConfig: router,
              locale: english ? const Locale('en') : const Locale('zh'),
              supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
              localizationsDelegates: _delegates(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final lines = [
          ...fittedLines(tester, 'insights(${english ? 'en' : 'zh'})', width),
          ...labelLines(
            tester,
            'insights(${english ? 'en' : 'zh'})',
            width,
            <String>[
              '今天',
              '近 7 天',
              '近 30 天',
              '全部',
              'Today',
              'Last 7 Days',
              'Last 30 Days',
              'All Time',
            ],
          ),
        ];
        _emit(
          '--- insights lang=${english ? 'en' : 'zh'} w=$width '
          'fittedBoxes=${lines.length} ---',
        );
        for (final l in lines) {
          _emit(l);
        }
        final visible = <String>[];
        for (final el in tester.allElements) {
          final r = el.renderObject;
          if (r is RenderParagraph) {
            final t = r.text.toPlainText().trim();
            if (t.isNotEmpty) visible.add(t);
          }
        }
        _emit('visibleTexts=${visible.toSet().join('|')}');
      }
    }
    _flush();
  });

  testWidgets('引导页·内置服务 agent 缺失卡按钮缩放探针', (tester) async {
    if (!_probe) {
      markTestSkipped(_skipReason);
      return;
    }
    for (final english in <bool>[false, true]) {
      for (final width in <double>[360, 390, 480, 800, 1280]) {
        LocaleResolver.reset(
          mode: english ? AppLocaleMode.en : AppLocaleMode.zh,
        );
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              agentEnvPresentProvider.overrideWith(_MissingAgent.new),
            ],
            child: CupertinoApp(
              locale: english ? const Locale('en') : const Locale('zh'),
              supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
              localizationsDelegates: _delegates(),
              home: const Scaffold2(child: BuiltinTab()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final lines = [
          ...fittedLines(tester, 'builtinTab(${english ? 'en' : 'zh'})', width),
          ...labelLines(tester, 'builtinTab(${english ? 'en' : 'zh'})', width, [
            '查看安装指南',
            '我装好了，重新检测',
            'View Install Guide',
            'I have installed it, recheck',
          ]),
        ];
        _emit(
          '--- builtinTab lang=${english ? 'en' : 'zh'} w=$width '
          'fittedBoxes=${lines.length} ---',
        );
        for (final l in lines) {
          _emit(l);
        }
      }
    }
    _flush();
  });
}

class _MissingAgent extends AgentEnvPresentNotifier {
  @override
  Future<bool> build() async => false;
}

/// 给 [BuiltinTab] 一个可滚动的宿主（它自身是 Column 型内容）。
class Scaffold2 extends StatelessWidget {
  const Scaffold2({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}
