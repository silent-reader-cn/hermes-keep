import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_page.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildSettingsApp() {
  return ProviderScope(
    child: CupertinoApp(
      theme: buildCupertinoTheme(Brightness.light),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: const SettingsPage(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsPage Diagnostics Entry', () {
    testWidgets('diagnostics entry tile exists and navigates to DiagnosticsPage', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildSettingsApp());
      await tester.pumpAndSettle();

      final diagnosticsTile = find.byKey(
        const ValueKey('settings-entry-diagnostics'),
      );
      expect(diagnosticsTile, findsOneWidget);

      // 开关行会随版本追加，tile 可能滑出 2000px 视口（#107/#108 并集实测
      // y=2018）——先滚进视口再点，别依赖页长魔数。
      await tester.dragUntilVisible(
        diagnosticsTile,
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      await tester.tap(diagnosticsTile);
      await tester.pumpAndSettle();

      expect(find.byType(DiagnosticsPage), findsOneWidget);
    });
  });
}
