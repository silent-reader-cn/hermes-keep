import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_detail_sheet.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_page.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_providers.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/contrast_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticsService service;
  late Directory tempDir;

  const testDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('diag_light_test_');
    SafeClipboard.destinationDirOverride = tempDir;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = DiagnosticsService(customPrefs: prefs);
    await service.init(prefs: prefs);
  });

  tearDown(() {
    SafeClipboard.resetOverridesForTesting();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    service.clearMemoryOnly();
  });

  Widget buildDiagnosticsApp({
    required Brightness brightness,
    Widget child = const DiagnosticsPage(),
  }) {
    return ProviderScope(
      overrides: [diagnosticsServiceProvider.overrideWithValue(service)],
      child: CupertinoApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: buildCupertinoTheme(brightness),
        localizationsDelegates: testDelegates,
        home: child,
      ),
    );
  }

  group('Diagnostics Light Surfaces & Contrast Tests', () {
    testWidgets('DiagnosticsPage 真实 WARN 级别色块（宽屏左栏 / 窄屏 chips）与行展开箭头在双主题下的契约', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.warn,
        tag: 'network',
        message: 'High latency detected',
      );

      // 1. 浅色主题测试
      await tester.pumpWidget(
        buildDiagnosticsApp(brightness: Brightness.light),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // 宽屏（≥900）：WARN 筛选入口 = 左 220 导航的级别行；契约点从「顶部 chip 的
      // AnimatedContainer + 字母 Text」平移到「左栏行的级别字母色块 + 字母 Text」，
      // **色值口径不变**（选中态一律用级别 tint 与级别 textColor）。
      final warnChipFinder = find.byKey(
        const ValueKey('diagnostics-nav-level-W'),
      );
      expect(warnChipFinder, findsOneWidget);
      expect(
        find.byKey(const ValueKey('diagnostics-filter-level-W')),
        findsNothing,
        reason: '宽屏 chips 行已搬进左栏，顶部不再有级别 chip',
      );

      final warnLetter = find.descendant(
        of: warnChipFinder,
        matching: find.text('W'),
      );
      final animatedContainer = tester.widget<Container>(
        find.ancestor(of: warnLetter, matching: find.byType(Container)).first,
      );
      final chipDeco = animatedContainer.decoration! as BoxDecoration;
      expect(chipDeco.color, LightSurfaces.tintWarning);

      final chipText = tester.widget<Text>(warnLetter);
      final chipFg = chipText.style!.color!;
      expect(contrastRatio(chipFg, chipDeco.color!), greaterThanOrEqualTo(4.5));

      // 验证导航栏边框浅色使用 divider
      final navBar = tester.widget<CupertinoNavigationBar>(
        find.byType(CupertinoNavigationBar),
      );
      final navBorder = navBar.border!;
      expect(navBorder.bottom.color, LightSurfaces.divider);
      expect(navBorder.bottom.width, 0.5);

      // 2. 深色主题测试
      await tester.pumpWidget(buildDiagnosticsApp(brightness: Brightness.dark));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // 深色下选中的级别色块底色保留 0.2 alpha
      final darkWarnChip = tester.widget<Container>(
        find
            .ancestor(
              of: find.descendant(
                of: find.byKey(const ValueKey('diagnostics-nav-level-W')),
                matching: find.text('W'),
              ),
              matching: find.byType(Container),
            )
            .first,
      );
      final darkChipDeco = darkWarnChip.decoration! as BoxDecoration;
      final warnTextDark = DiagnosticsLogLevel.warn.textColor.resolveFrom(
        tester.element(warnChipFinder),
      );
      expect(darkChipDeco.color, warnTextDark.withValues(alpha: 0.2));

      // 深色下展开箭头严格保留 raw 0xFFC7C7CC
      final chevron = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.chevron_right),
      );
      expect(chevron.color, const Color(0xFFC7C7CC));

      // 导航栏边框深色保留 SDK 默认
      final darkNavBar = tester.widget<CupertinoNavigationBar>(
        find.byType(CupertinoNavigationBar),
      );
      final darkNavBorder = darkNavBar.border!;
      expect(darkNavBorder.bottom.color, const Color(0x4D000000));
      expect(darkNavBorder.bottom.width, 0.0);

      // 3. 窄屏（<900）：顶部 chips 行的同一契约原样保留
      // （批 4C 只改宽屏；这条口径就是改动前的原断言）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.physicalSize = const Size(800, 1500);
      await tester.pumpWidget(
        buildDiagnosticsApp(brightness: Brightness.light),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final narrowChip = find.byKey(
        const ValueKey('diagnostics-filter-level-W'),
      );
      expect(narrowChip, findsOneWidget, reason: '窄屏筛选入口仍是顶部 chips 行');
      final narrowDeco =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: narrowChip,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(narrowDeco.color, LightSurfaces.tintWarning);
      final narrowFg = tester
          .widget<Text>(
            find.descendant(of: narrowChip, matching: find.byType(Text)),
          )
          .style!
          .color!;
      expect(
        contrastRatio(narrowFg, narrowDeco.color!),
        greaterThanOrEqualTo(4.5),
      );

      // 卸载组件树
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('DiagnosticsDetailSheet 详情卡片在双主题下的边框契约', (tester) async {
      final entry = DiagnosticsLogEntry(
        id: 'diag-entry-1',
        timestamp: DateTime(2026, 3, 12, 14, 30),
        level: DiagnosticsLogLevel.warn,
        tag: 'storage',
        message: 'Disk threshold warning',
      );

      // 浅色模式：主消息卡片有 cardBorder 0.5 发丝边框
      await tester.pumpWidget(
        buildDiagnosticsApp(
          brightness: Brightness.light,
          child: DiagnosticsDetailSheet(entry: entry),
        ),
      );
      await tester.pumpAndSettle();

      final msgTextFinder = find.text('Disk threshold warning');
      expect(msgTextFinder, findsOneWidget);

      final lightCard = tester.widget<Container>(
        find
            .ancestor(of: msgTextFinder, matching: find.byType(Container))
            .first,
      );
      final lightCardDeco = lightCard.decoration! as BoxDecoration;
      expect(lightCardDeco.color, LightSurfaces.card);
      expect(
        lightCardDeco.border,
        Border.all(color: LightSurfaces.cardBorder, width: 0.5),
      );

      // 深色模式：主消息卡片边框为 null
      await tester.pumpWidget(
        buildDiagnosticsApp(
          brightness: Brightness.dark,
          child: DiagnosticsDetailSheet(entry: entry),
        ),
      );
      await tester.pumpAndSettle();

      final darkCard = tester.widget<Container>(
        find
            .ancestor(of: msgTextFinder, matching: find.byType(Container))
            .first,
      );
      final darkCardDeco = darkCard.decoration! as BoxDecoration;
      expect(darkCardDeco.border, isNull);

      // 卸载组件树
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
