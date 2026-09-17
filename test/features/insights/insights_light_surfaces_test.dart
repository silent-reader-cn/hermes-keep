import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/insights/insights_api.dart';
import 'package:hermes_ui/features/insights/insights_page.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/contrast_utils.dart';
import '../../helpers/fake_insights_api.dart';
import 'insights_test.dart' show sampleResponse;

const _l10n = AppLocalizations(Locale('zh'));

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required FakeInsightsApi api,
  bool highContrast = false,
  CupertinoUserInterfaceLevelData level = CupertinoUserInterfaceLevelData.base,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local'),
        ),
        insightsApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: highContrast),
          child: CupertinoUserInterfaceLevel(data: level, child: child!),
        ),
        home: const InsightsPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Color _textColor(WidgetTester tester, String text) {
  final richText = tester.widget<RichText>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  return Color(richText.text.style!.color!.toARGB32());
}

BarTouchResponse _touchResponse(BarChart chart) => BarTouchResponse(
  touchLocation: Offset.zero,
  touchChartCoordinate: Offset.zero,
  spot: BarTouchedSpot(
    chart.data.barGroups[1],
    1,
    chart.data.barGroups[1].barRods[0],
    0,
    null,
    -1,
    const FlSpot(1, 150),
    Offset.zero,
  ),
);

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    final isLight = brightness == Brightness.light;
    for (final highContrast in [false, true]) {
      for (final level in CupertinoUserInterfaceLevelData.values) {
        testWidgets('Insights surfaces and chart contrast $brightness '
            'highContrast=$highContrast level=$level', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            highContrast: highContrast,
            level: level,
            api: FakeInsightsApi(response: sampleResponse()),
          );
          final context = tester.element(find.byType(CupertinoPageScaffold));
          final theme = CupertinoTheme.of(context);
          expect(
            theme.scaffoldBackgroundColor,
            isLight ? LightSurfaces.page : const Color(0xFF000000),
          );
          expect(
            theme.barBackgroundColor,
            isLight ? LightSurfaces.page : const Color(0xFF000000),
          );
          final sections = tester.widgetList<CupertinoListSection>(
            find.byType(CupertinoListSection),
          );
          expect(sections, hasLength(4));
          for (final section in sections) {
            expect(
              section.backgroundColor,
              isLight
                  ? LightSurfaces.page
                  : CupertinoColors.systemGroupedBackground.resolveFrom(
                      context,
                    ),
            );
            expect(
              section.separatorColor,
              isLight
                  ? LightSurfaces.divider
                  : CupertinoColors.separator.resolveFrom(context),
            );
            if (isLight) {
              expect(section.decoration!.color, LightSurfaces.card);
              expect(
                section.decoration!.border,
                Border.all(color: LightSurfaces.cardBorder, width: 0.5),
              );
            } else {
              // Null retains the SDK's original superellipse and clipping.
              expect(section.decoration, isNull);
            }
          }

          final secondaryLabels = [
            '08-15',
            '08-16',
            _l10n.peakDaySessions('2026-08-16', 5),
            _l10n.peakHourSessions('14:00', 3),
            _l10n.insightsSourceFooter(30),
          ];
          for (final label in secondaryLabels) {
            final foreground = _textColor(tester, label);
            expect(
              foreground,
              isLight
                  ? LightSurfaces.textSecondary
                  : Color(secondaryText.resolveFrom(context).toARGB32()),
            );
            if (isLight) {
              final surface = label == _l10n.insightsSourceFooter(30)
                  ? LightSurfaces.page
                  : LightSurfaces.card;
              expect(
                contrastRatio(foreground, surface),
                greaterThanOrEqualTo(4.5),
                reason: label,
              );
            }
          }
          final subtitle = _l10n.modelTokensSubtitle('1,000');
          expect(
            _textColor(tester, subtitle),
            isLight
                ? LightSurfaces.textSecondary
                : Color(
                    CupertinoColors.secondaryLabel
                        .resolveFrom(context)
                        .toARGB32(),
                  ),
          );
          expect(
            _textColor(tester, '60%'),
            isLight
                ? Color(statusBlueText.resolveFrom(context).toARGB32())
                : const Color(0xFF007AFF),
          );
          if (isLight) {
            for (final label in [subtitle, '60%', r'$1.2345', '87.5%']) {
              expect(
                contrastRatio(_textColor(tester, label), LightSurfaces.card),
                greaterThanOrEqualTo(4.5),
                reason: label,
              );
            }
          } else {
            expect(tester.widget<Text>(find.text(subtitle)).style, isNull);
          }

          final chart = tester.widget<BarChart>(find.byType(BarChart));
          expect(chart.data.gridData.show, isFalse);
          expect(chart.data.barTouchData.handleBuiltInTouches, isFalse);
          for (final group in chart.data.barGroups) {
            final color = group.barRods.single.color!;
            expect(color, CupertinoColors.systemBlue);
            if (isLight) {
              expect(
                contrastRatio(color, LightSurfaces.card),
                greaterThanOrEqualTo(3),
              );
            }
          }
          chart.data.barTouchData.touchCallback!(
            const FlPointerHoverEvent(PointerHoverEvent()),
            _touchResponse(chart),
          );
          await tester.pump();
          final hovered = tester.widget<BarChart>(find.byType(BarChart));
          final highlight = hovered.data.barGroups[1].barRods.single.color!;
          expect(highlight, const Color(0xFF004999));
          if (isLight) {
            expect(
              contrastRatio(highlight, LightSurfaces.card),
              greaterThanOrEqualTo(3),
            );
          }
          hovered.data.barTouchData.touchCallback!(
            const FlPointerExitEvent(PointerExitEvent()),
            null,
          );
          await tester.pump();
          expect(
            tester
                .widget<BarChart>(find.byType(BarChart))
                .data
                .barGroups[1]
                .barRods
                .single
                .color,
            CupertinoColors.systemBlue,
          );
          expect(tester.takeException(), isNull);
          await _unmount(tester);
        });
      }

      for (final isError in [false, true]) {
        testWidgets('Insights empty/error contrast $brightness '
            'highContrast=$highContrast error=$isError', (tester) async {
          final api = FakeInsightsApi();
          if (isError) {
            api.fetchError = NetworkException(
              NetworkExceptionKind.cannotConnect,
            );
          }
          await _pump(
            tester,
            brightness: brightness,
            highContrast: highContrast,
            api: api,
          );
          final icon = tester.widget<Icon>(
            find.byIcon(
              isError
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.chart_bar,
            ),
          );
          // #140 P2-b：深色档改由 CupertinoColors.systemGrey 解析而来 —— 普通档
          // #8E8E93（与原先逐字节一致），高对比档跟随其 #AEAEB2 变体（本轮新增
          // 的「高对比度模式」开关所开启的行为）。
          final expectedDark = highContrast
              ? CupertinoColors.systemGrey.darkHighContrastColor
              : const Color(0xFF8E8E93);
          expect(
            icon.color!.toARGB32(),
            (isLight ? LightSurfaces.textSecondary : expectedDark).toARGB32(),
          );
          if (isLight) {
            expect(
              contrastRatio(icon.color!, LightSurfaces.page),
              greaterThanOrEqualTo(3),
            );
            if (!isError) {
              expect(
                contrastRatio(
                  _textColor(tester, _l10n.insightsWillShowHere),
                  LightSurfaces.page,
                ),
                greaterThanOrEqualTo(4.5),
              );
            }
          }
          if (isError) {
            final button = tester.widget<CupertinoButton>(
              find.byKey(const ValueKey('insights-retry')),
            );
            if (isLight) {
              expect(
                contrastRatio(_textColor(tester, _l10n.retry), button.color!),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                contrastRatio(
                  _textColor(tester, (api.fetchError! as ApiException).message),
                  LightSurfaces.page,
                ),
                greaterThanOrEqualTo(4.5),
              );
            } else {
              expect(button.color, isNull);
            }
          }
          expect(tester.takeException(), isNull);
          await _unmount(tester);
        });
      }

      testWidgets(
        'Insights day dialog action $brightness highContrast=$highContrast',
        (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            highContrast: highContrast,
            api: FakeInsightsApi(response: sampleResponse()),
          );
          final chart = tester.widget<BarChart>(find.byType(BarChart));
          chart.data.barTouchData.touchCallback!(
            FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.touch)),
            _touchResponse(chart),
          );
          await tester.pumpAndSettle();
          expect(find.text('2026-08-16'), findsOneWidget);
          expect(find.text(r'$0.01'), findsOneWidget);
          final action = tester.widget<CupertinoDialogAction>(
            find.byType(CupertinoDialogAction),
          );
          if (isLight) {
            final foreground = _textColor(tester, _l10n.ok);
            expect(foreground, LightSurfaces.menuAction);
            // Native dialog: white/page backdrops and the opaque pressed row.
            for (final background in [
              LightSurfaces.card,
              LightSurfaces.page,
              const Color(0xFFE1E1E1),
            ]) {
              expect(
                contrastRatio(foreground, background),
                greaterThanOrEqualTo(4.5),
              );
            }
          } else {
            expect(action.textStyle, isNull);
          }
          await tester.tap(find.text(_l10n.ok));
          await tester.pumpAndSettle();
          expect(find.byType(CupertinoAlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
          await _unmount(tester);
        },
      );
    }
  }
}
