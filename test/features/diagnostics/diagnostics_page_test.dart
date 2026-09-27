import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_detail_sheet.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_page.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_providers.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildTestApp({
  required DiagnosticsService service,
  Widget child = const DiagnosticsPage(),
  Locale locale = const Locale('zh'),
}) {
  return ProviderScope(
    overrides: [diagnosticsServiceProvider.overrideWithValue(service)],
    child: CupertinoApp(
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      theme: buildCupertinoTheme(Brightness.light),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        DefaultCupertinoLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticsService service;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('diag_page_test_');
    SafeClipboard.destinationDirOverride = tempDir;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = DiagnosticsService(customPrefs: prefs);
    await service.init(prefs: prefs);
  });

  tearDown(() {
    SafeClipboard.resetOverridesForTesting();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
    service.clearMemoryOnly();
  });

  group('DiagnosticsPage Widget Tests', () {
    testWidgets('shows empty placeholder when disabled', (tester) async {
      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pumpAndSettle();

      expect(find.text('调试/诊断'), findsOneWidget);
      expect(find.text('调试模式'), findsOneWidget);
      expect(find.text('打开调试模式后开始记录'), findsOneWidget);
    });

    testWidgets('switch toggles debug mode and persists', (tester) async {
      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('diagnostics-switch-enable'),
      );
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<CupertinoSwitch>(switchFinder);
      expect(switchWidget.value, false);

      await tester.tap(switchFinder);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(service.enabled, true);
    });

    testWidgets('displays log entries and level badges', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'dio',
        message: 'GET /api/status -> 200',
        durationMs: 45,
      );
      service.log(
        level: DiagnosticsLogLevel.error,
        tag: 'sse',
        message: 'SSE connection failed',
        errorKind: 'Timeout',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('GET /api/status -> 200'), findsOneWidget);
      expect(find.text('SSE connection failed'), findsOneWidget);
      expect(find.text('45ms'), findsOneWidget);
      expect(find.text('Timeout'), findsOneWidget);
    });

    testWidgets(
      'filtering by level chips updates displayed list（宽屏左栏 / 窄屏顶部）',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await service.setEnabled(true);
        service.log(
          level: DiagnosticsLogLevel.info,
          tag: 'dio',
          message: 'INFO message',
        );
        service.log(
          level: DiagnosticsLogLevel.error,
          tag: 'dio',
          message: 'ERROR message',
        );

        await tester.pumpWidget(_buildTestApp(service: service));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        expect(find.text('INFO message'), findsOneWidget);
        expect(find.text('ERROR message'), findsOneWidget);

        // 宽屏（≥900）筛选入口 = 左 220 导航的级别行（批 4C：顶部 chips 行搬进左栏）。
        // 位置变了，**筛选行为本身不变**：取消「信息」→ INFO 行消失、ERROR 行保留。
        final infoChip = find.byKey(const ValueKey('diagnostics-nav-level-I'));
        await tester.tap(infoChip);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        expect(find.text('INFO message'), findsNothing);
        expect(find.text('ERROR message'), findsOneWidget);

        // 窄屏（<900）：筛选入口仍是顶部 chips 行，同一行为必须同样成立
        // （批 4C 只改宽屏，窄屏这条契约原样保留）。
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.physicalSize = const Size(800, 1500);
        await tester.pumpWidget(_buildTestApp(service: service));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('diagnostics-nav-rail')),
          findsNothing,
        );
        expect(find.text('INFO message'), findsOneWidget);
        expect(find.text('ERROR message'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('diagnostics-filter-level-I')),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        expect(find.text('INFO message'), findsNothing);
        expect(find.text('ERROR message'), findsOneWidget);
      },
    );

    testWidgets('search filters entries with debounce', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat',
        message: 'Sending user message alpha',
      );
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat',
        message: 'Receiving reply beta',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Sending user message alpha'), findsOneWidget);
      expect(find.text('Receiving reply beta'), findsOneWidget);

      final searchField = find.byKey(
        const ValueKey('diagnostics-search-field'),
      );
      await tester.enterText(searchField, 'alpha');
      // Advance debounce timer (200ms)
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Sending user message alpha'), findsOneWidget);
      expect(find.text('Receiving reply beta'), findsNothing);
    });

    testWidgets('clear logs shows confirmation dialog and clears buffer', (
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
        level: DiagnosticsLogLevel.info,
        tag: 'dio',
        message: 'Log to be cleared',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Log to be cleared'), findsOneWidget);

      final clearBtn = find.byKey(const ValueKey('diagnostics-clear-btn'));
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(find.text('确定要清空所有诊断日志吗？'), findsOneWidget);

      final confirmBtn = find.byKey(
        const ValueKey('diagnostics-clear-confirm'),
      );
      await tester.tap(confirmBtn);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(service.logs, isEmpty);
      expect(find.text('暂无日志记录'), findsOneWidget);
    });

    testWidgets('tap log row opens detail（宽屏右栏内联 / 窄屏整页 sheet）', (
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
        level: DiagnosticsLogLevel.info,
        tag: 'dio',
        message: 'Detailed log message',
        details: {'info': 'value123'},
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // 宽屏（≥900）：详情在右栏内展开，**不再 push 整页**（批 4C 新契约）；
      // 展示的信息与窄屏 sheet 同源（标题 / 消息 / 详情 JSON 都在）。
      await tester.tap(find.text('Detailed log message'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('diagnostics-wide-detail')),
        findsOneWidget,
      );
      expect(find.byType(DiagnosticsDetailSheet), findsNothing);
      expect(find.text('日志详情'), findsOneWidget);
      expect(find.textContaining('value123'), findsOneWidget);

      // 窄屏（<900）：仍是整页 sheet —— 既有契约原样保留。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.physicalSize = const Size(800, 1500);
      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Detailed log message'));
      await tester.pumpAndSettle();

      expect(find.byType(DiagnosticsDetailSheet), findsOneWidget);
      expect(
        find.byKey(const ValueKey('diagnostics-wide-detail')),
        findsNothing,
      );
      expect(find.text('日志详情'), findsOneWidget);
      expect(find.textContaining('value123'), findsOneWidget);
    });

    testWidgets('multi-select mode allows selection and exiting', (
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
        level: DiagnosticsLogLevel.info,
        tag: 'tag1',
        message: 'Entry 1',
      );
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'tag2',
        message: 'Entry 2',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Enter selection mode
      final enterBtn = find.byKey(
        const ValueKey('diagnostics-enter-selection-btn'),
      );
      await tester.tap(enterBtn);
      await tester.pumpAndSettle();

      expect(find.text('已选择 0 条'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);

      // Tap select all
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();

      expect(find.text('已选择 2 条'), findsOneWidget);

      // Exit selection mode
      final exitBtn = find.byKey(
        const ValueKey('diagnostics-exit-selection-btn'),
      );
      await tester.tap(exitBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('diagnostics-enter-selection-btn')),
        findsOneWidget,
      );
    });

    testWidgets('export logs small text copies to clipboard', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'export_test',
        message: 'Small log to export',
      );

      String? copiedContent;
      SafeClipboard.clipboardSetterOverride = (text) async {
        copiedContent = text;
      };

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final exportBtn = find.byKey(const ValueKey('diagnostics-export-btn'));
      await tester.tap(exportBtn);
      await tester.pumpAndSettle();

      expect(find.text('导出'), findsWidgets);
      expect(find.text('诊断日志已导出并复制到剪贴板'), findsOneWidget);
      expect(copiedContent, isNotNull);
      expect(copiedContent, contains('Small log to export'));
    });

    testWidgets('export logs large text saves to file', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'export_large',
        message: 'Large log content that will exceed threshold',
      );

      SafeClipboard.maxBytesOverride = 20;
      SafeClipboard.clockOverride = () => DateTime(2026, 9, 3, 19, 0, 0);

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final exportBtn = find.byKey(const ValueKey('diagnostics-export-btn'));
      await tester.tap(exportBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('导出'), findsWidgets);
      expect(find.textContaining('内容过大已保存到文件：'), findsOneWidget);
      expect(
        find.textContaining('hermes_logs_export_20260903_190000.txt'),
        findsOneWidget,
      );

      final separator = tempDir.path.contains('\\') ? '\\' : '/';
      final exportedFile = File(
        '${tempDir.path}${separator}hermes_logs_export_20260903_190000.txt',
      );
      expect(exportedFile.existsSync(), isTrue);
      expect(exportedFile.readAsStringSync(), contains('Large log content'));
    });

    testWidgets('copy selected logs small text copies to clipboard', (
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
        level: DiagnosticsLogLevel.info,
        tag: 'tag1',
        message: 'Selectable entry 1',
      );

      String? copiedContent;
      SafeClipboard.clipboardSetterOverride = (text) async {
        copiedContent = text;
      };

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // 进入多选模式
      final enterBtn = find.byKey(
        const ValueKey('diagnostics-enter-selection-btn'),
      );
      await tester.tap(enterBtn);
      await tester.pumpAndSettle();

      // 全选
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();

      // 复制选中
      final copyBtn = find.byKey(
        const ValueKey('diagnostics-copy-selected-btn'),
      );
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(find.text('复制'), findsWidgets);
      expect(find.text('已复制到剪贴板'), findsOneWidget);
      expect(copiedContent, isNotNull);
      expect(copiedContent, contains('Selectable entry 1'));
    });

    testWidgets('copy selected logs large text saves to file', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'tag1',
        message: 'Selectable large entry that will exceed threshold',
      );

      SafeClipboard.maxBytesOverride = 20;
      SafeClipboard.clockOverride = () => DateTime(2026, 9, 3, 19, 10, 0);

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // 进入多选模式
      final enterBtn = find.byKey(
        const ValueKey('diagnostics-enter-selection-btn'),
      );
      await tester.tap(enterBtn);
      await tester.pumpAndSettle();

      // 全选
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();

      // 复制选中
      final copyBtn = find.byKey(
        const ValueKey('diagnostics-copy-selected-btn'),
      );
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(find.text('复制'), findsWidgets);
      expect(find.textContaining('内容过大已保存到文件：'), findsOneWidget);
      expect(
        find.textContaining('hermes_logs_export_20260903_191000.txt'),
        findsOneWidget,
      );

      final separator = tempDir.path.contains('\\') ? '\\' : '/';
      final exportedFile = File(
        '${tempDir.path}${separator}hermes_logs_export_20260903_191000.txt',
      );
      expect(exportedFile.existsSync(), isTrue);
      expect(
        exportedFile.readAsStringSync(),
        contains('Selectable large entry'),
      );
    });
  });
}
