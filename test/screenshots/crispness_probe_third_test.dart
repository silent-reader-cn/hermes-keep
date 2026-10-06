import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/widgets/hermes_dialog.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/chat/widgets/perf_monitor_panel.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:hermes_ui/features/settings/perf_monitor_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_system_health.dart';

// ---------------------------------------------------------------------------
// 清晰度探针 · 第三批（Hermes 弹窗动作按钮 / 性能监控弹层）
//
// 用法：CRISPNESS_PROBE3=1 C:/tmp/f.bat test test/screenshots/crispness_probe_third_test.dart
// 结果写到 `.shots/crispness/probe3.txt`。
// ---------------------------------------------------------------------------

final bool _probe = Platform.environment['CRISPNESS_PROBE3'] == '1';
const String _skipReason = '设置 CRISPNESS_PROBE3=1 才跑第三批清晰度探针';
const String _outPath = '.shots/crispness/probe3.txt';

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

class _TwoPane extends ComposerTwoPaneController {
  @override
  bool build() => true;
}

class _PerfOn extends PerfMonitorController {
  @override
  bool build() => true;
}

void main() {
  setUpAll(loadHermesGoldenFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Hermes 弹窗动作文案缩放探针', (tester) async {
    if (!_probe) {
      markTestSkipped(_skipReason);
      return;
    }
    // 真实调用点里最长的动作文案 + 一个压力用超长文案。
    const labels = <String>[
      '取消',
      '删除工作区',
      '清理并重建索引',
      '删除该工作区并同时清理其临时文件与缓存索引（压力样本）',
    ];
    for (final label in labels) {
      for (final width in <double>[1280, 900]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          CupertinoApp(
            theme: buildCupertinoTheme(Brightness.light),
            home: Builder(
              builder: (context) => CupertinoPageScaffold(
                child: Center(
                  child: CupertinoButton(
                    onPressed: () => showHermesDialog<void>(
                      context,
                      kind: HermesDialogKind.confirm,
                      title: (_) => const Text('确认'),
                      content: (_) => const Text('内容'),
                      actions: <HermesDialogAction>[
                        HermesDialogAction(
                          key: const ValueKey('probe-cancel'),
                          builder: (_) => const Text('取消'),
                        ),
                        HermesDialogAction(
                          key: const ValueKey('probe-main'),
                          isDefaultAction: true,
                          builder: (_) => Text(label),
                        ),
                      ],
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final lines = fittedLines(tester, 'dialog("$label")', width);
        final vis = <String>[];
        for (final el in tester.allElements) {
          final r = el.renderObject;
          if (r is RenderParagraph) {
            final t = r.text.toPlainText().trim();
            if (t.isNotEmpty) vis.add(t);
          }
        }
        _emit('dialogVisibleTexts=${vis.toSet().join('|')}');
        _emit(
          '--- dialog label="$label" w=$width '
          'fittedBoxes=${lines.length} ---',
        );
        for (final l in lines) {
          _emit(l);
        }
      }
    }
    _flush();
  });

  testWidgets('性能监控弹层磁盘行缩放探针', (tester) async {
    if (!_probe) {
      markTestSkipped(_skipReason);
      return;
    }
    for (final width in <double>[1280, 390]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(buildSystemHealthApiClient()),
            composerTwoPaneProvider.overrideWith(_TwoPane.new),
            perfMonitorProvider.overrideWith(_PerfOn.new),
          ],
          child: CupertinoApp(
            theme: buildCupertinoTheme(Brightness.light),
            home: const CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.topRight,
                child: PerfMonitorPanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('perf-monitor-panel'));
      if (panel.evaluate().isEmpty) {
        _emit('--- perf w=$width：面板未渲染（无数据） ---');
        continue;
      }
      await tester.tap(panel);
      await tester.pumpAndSettle();
      final lines = fittedLines(tester, 'perfPopover', width);
      _emit('--- perf w=$width fittedBoxes=${lines.length} ---');
      for (final l in lines) {
        _emit(l);
      }
    }
    _flush();
  });
}
