import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 清晰度探针（**非金照基线，不参与 CI 全量**）
//
// 用途：量化 FittedBox 把整块分段控件等比缩小（文字/图标一起重采样）的问题，
// 以及修复后「不再有缩放、也不再有标签折行」的实测证据。
//
// 测什么：
//   A. 渲染树里剩余的 `RenderFittedBox` 及其缩放比
//      `scale = min(1, min(own.w/child.w, own.h/child.h))`；scale < 1 = 孩子被
//      缩小重采样，`[13.0->8.60]` 即「13pt 标签实际画成 8.60pt」。
//   B. 每个 `CupertinoSlidingSegmentedControl` 的实际宽度、每段宽度；
//      段内每个标签是否**折行**（size.height > 单行高度）或**被压**（
//      size.width < 自身 intrinsic 宽）。
//
// 用法：
//   CRISPNESS_PROBE=1 C:/tmp/f.bat test test/screenshots/crispness_probe_test.dart
// 不带 CRISPNESS_PROBE=1 时全部 skip，`flutter test` 全量零影响。
// 结果写到 `.shots/crispness/probe.txt`（相对 test 进程 cwd = 仓库根）。
// ---------------------------------------------------------------------------

final bool _probe = Platform.environment['CRISPNESS_PROBE'] == '1';
const String _skipReason = '设置 CRISPNESS_PROBE=1 才跑清晰度探针';
const String _outPath = '.shots/crispness/probe.txt';

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

/// 遍历渲染树里的全部 [RenderFittedBox]，报出缩放比与受影响文案。
List<String> fittedLines(WidgetTester tester, double width) {
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
      'w=$width\tfitted\tchild=${c.size.width.toStringAsFixed(1)}\town='
      '${ro.size.width.toStringAsFixed(1)}\tscale=${scale.toStringAsFixed(4)}\t'
      '[${uniq.map((f) => '${f.toStringAsFixed(1)}->${(f * scale).toStringAsFixed(2)}').join(' ')}]'
      '\t"${texts.toSet().join('/')}"',
    );
  }
  return out;
}

/// 遍历渲染树里的全部分段控件，报出宽度与标签折行/受压情况。
List<String> segmentedLines(WidgetTester tester, double width) {
  final out = <String>[];
  for (final el in tester.allElements) {
    if (el.widget is! CupertinoSlidingSegmentedControl) continue;
    final ro = el.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    final paras = <RenderParagraph>[];
    void scan(Element e) {
      final r = e.renderObject;
      if (r is RenderParagraph) paras.add(r);
      e.visitChildren(scan);
    }

    scan(el);
    final issues = <String>[];
    var segWidth = 0.0;
    for (final p in paras) {
      final intrinsic = p.getMaxIntrinsicWidth(double.infinity);
      final oneLine = p.getMaxIntrinsicHeight(double.infinity);
      segWidth = mathMax(segWidth, p.size.width);
      final wrapped = p.size.height > oneLine + 0.5;
      final squeezed = p.size.width + 0.6 < intrinsic;
      if (wrapped || squeezed) {
        issues.add(
          '"${p.text.toPlainText().trim()}"'
          '(${p.size.width.toStringAsFixed(1)}/${intrinsic.toStringAsFixed(1)}'
          '${wrapped ? ' WRAPPED' : ''}${squeezed ? ' SQUEEZED' : ''})',
        );
      }
    }

    out.add(
      'w=$width\tsegmented\tctrlW=${ro.size.width.toStringAsFixed(1)}\t'
      'labels=${paras.length}\tissues=${issues.isEmpty ? 'none' : issues.join(',')}',
    );
  }
  return out;
}

double mathMax(double a, double b) => a > b ? a : b;

void main() {
  setUpAll(loadHermesGoldenFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    required double width,
    double height = 2400,
    bool english = false,
  }) async {
    LocaleResolver.reset(mode: english ? AppLocaleMode.en : AppLocaleMode.zh);
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final store = ConnectionStore(storage: InMemorySecureStorage());
    final api = FakeSettingsApi();
    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        settingsApiFactoryProvider.overrideWithValue((_) => api),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          locale: english ? const Locale('en') : const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToBottom(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -700),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('设置页清晰度探针', (tester) async {
    if (!_probe) {
      markTestSkipped(_skipReason);
      return;
    }
    for (final english in <bool>[false, true]) {
      for (final width in <double>[320, 360, 390, 480, 800, 1024, 1600]) {
        await pumpSettings(tester, width: width, english: english);
        await scrollToBottom(tester);
        final lang = english ? 'en' : 'zh';
        final fitted = fittedLines(tester, width);
        _emit('--- lang=$lang w=$width  fittedBoxes=${fitted.length} ---');
        for (final l in fitted) {
          _emit(l);
        }
        final segs = segmentedLines(tester, width);
        _emit('--- lang=$lang w=$width  segmentedControls=${segs.length} ---');
        for (final l in segs) {
          _emit(l);
        }
      }
    }
    _flush();
  });
}
