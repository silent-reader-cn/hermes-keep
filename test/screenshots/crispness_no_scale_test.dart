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
// 设置页分段控件「不缩放」守卫
//
// 背景：这些行过去写作
//   `trailing: ConstrainedBox(maxWidth: 220) > FittedBox(scaleDown) > 分段控件`
// `FittedBox` 会把塞不下的整块控件等比缩小 ⇒ **文字与图标一起被重采样**。
// 实测（MiSans，`test/screenshots/crispness_probe_test.dart`）：
//   · 中文「会话分组方式」行：scale 0.9129，13pt 标签实际画成 11.87pt；
//   · 英文「推送测试类型」行：scale 0.6339，13pt 实际画成 8.24pt。
//
// 本测试钉住三条：
//   ① 设置页里**不再有** `FittedBox`（没有任何等比重采样路径）；
//   ② 每个分段控件的每个标签都按**自身 intrinsic 宽**渲染且单行（既没被压扁、
//      也没折行）—— 这才是「清晰」的可测判据，而不是「看起来还行」；
//   ③ 控件宽度不超过行内可用宽（没有溢出）。
//
// 覆盖宽度取「产品真实可用宽度」：中文界面 ≥ 360（手机与桌面全覆盖）；
// 英文界面标签更长，本仓既有基线在 ≥ 480 才全部单行，故英文只钉 ≥ 480。
// ---------------------------------------------------------------------------

/// 一台探针：遍历渲染树里的全部 [RenderFittedBox]。
List<RenderFittedBox> _fittedBoxes(WidgetTester tester) {
  final out = <RenderFittedBox>[];
  for (final el in tester.allElements) {
    final ro = el.renderObject;
    if (ro is RenderFittedBox && ro.hasSize) out.add(ro);
  }
  return out;
}

/// 对一个分段控件断言每个标签都单行且未被压缩。
void _expectLabelsIntact(
  WidgetTester tester,
  Element controlElement,
  String where,
) {
  final paragraphs = <RenderParagraph>[];
  void scan(Element e) {
    final r = e.renderObject;
    if (r is RenderParagraph) paragraphs.add(r);
    e.visitChildren(scan);
  }

  scan(controlElement);
  expect(paragraphs, isNotEmpty, reason: '$where：分段控件里应有标签');
  for (final p in paragraphs) {
    final text = p.text.toPlainText().trim();
    final intrinsic = p.getMaxIntrinsicWidth(double.infinity);
    final oneLineHeight = p.getMaxIntrinsicHeight(double.infinity);
    expect(
      p.size.height,
      lessThanOrEqualTo(oneLineHeight + 0.5),
      reason: '$where：「$text」被折行（高度 ${p.size.height} > 单行 $oneLineHeight）',
    );
    expect(
      p.size.width,
      greaterThanOrEqualTo(intrinsic - 0.5),
      reason: '$where：「$text」被压缩（实宽 ${p.size.width} < intrinsic $intrinsic）',
    );
  }
}

void main() {
  setUpAll(loadHermesGoldenFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    required double width,
    required bool english,
  }) async {
    LocaleResolver.reset(mode: english ? AppLocaleMode.en : AppLocaleMode.zh);
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: InMemorySecureStorage()),
        ),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        settingsApiFactoryProvider.overrideWithValue((_) => FakeSettingsApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
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

    // 设置页是懒加载 sliver：滚到底把所有分组 build 出来。
    for (var i = 0; i < 60; i++) {
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -700),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  int segmentedCount(WidgetTester tester) {
    var n = 0;
    for (final el in tester.allElements) {
      if (el.widget is CupertinoSlidingSegmentedControl) n++;
    }
    return n;
  }

  void checkAllControls(WidgetTester tester, String where) {
    final controls = tester.allElements
        .where((el) => el.widget is CupertinoSlidingSegmentedControl)
        .toList();
    expect(controls, isNotEmpty, reason: '$where：应至少有一个分段控件');
    for (final el in controls) {
      _expectLabelsIntact(tester, el, where);
    }
  }

  group('设置页分段控件不缩放（清晰度守卫）', () {
    for (final width in <double>[360, 390, 480, 800, 1024, 1280, 1600]) {
      testWidgets('中文 w=$width：无 FittedBox + 标签单行未压缩', (tester) async {
        await pumpSettings(tester, width: width, english: false);
        expect(
          _fittedBoxes(tester),
          isEmpty,
          reason: '设置页不应再有 FittedBox（等比缩放会把文字/图标一起重采样）',
        );
        // 窄屏单栏渲染全部分组（6 个行）；宽屏走分类导航，只渲染当前分类。
        expect(
          segmentedCount(tester),
          width < 900 ? 6 : greaterThanOrEqualTo(4),
          reason: '分组行都应挂出分段控件',
        );
        checkAllControls(tester, 'zh w=$width');
      });
    }

    for (final width in <double>[480, 800, 1280, 1600]) {
      testWidgets('英文 w=$width：无 FittedBox + 标签单行未压缩', (tester) async {
        await pumpSettings(tester, width: width, english: true);
        expect(_fittedBoxes(tester), isEmpty);
        checkAllControls(tester, 'en w=$width');
      });
    }

    testWidgets('极窄 320 中文：仍然零 FittedBox（宁可段窄也不重采样字形）', (tester) async {
      await pumpSettings(tester, width: 320, english: false);
      expect(_fittedBoxes(tester), isEmpty);
      expect(segmentedCount(tester), 6);
    });
  });
}
