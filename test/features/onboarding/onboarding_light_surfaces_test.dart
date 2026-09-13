import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_info.dart';
import 'package:hermes_ui/features/onboarding/onboarding_page.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/onboarding/widgets/builtin_tab.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

class _MissingAgent extends AgentEnvPresentNotifier {
  @override
  FutureOr<bool> build() => false;
}

class _PendingHealthApi extends FakeOnboardingLoginApi {
  final response = Completer<HealthResponse>();

  @override
  Future<HealthResponse> health() => response.future;
}

class _StoppedSidecar extends WebuiSidecarController {
  @override
  SidecarState build() => SidecarState.initial;
}

class _DemoConfig extends WebuiSidecarConfigController {
  @override
  SidecarConfig build() => const SidecarConfig(password: 'demo-password');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      testWidgets(
        'connection form remains readable with $brightness, high contrast $highContrast',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(
                disableAnimations: true,
                highContrast: highContrast,
              );
          addTearDown(tester.view.reset);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          final api = _PendingHealthApi();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                bundledWebuiAvailableProvider.overrideWithValue(false),
                onboardingApiFactoryProvider.overrideWithValue((_, _) => api),
              ],
              child: CupertinoApp(
                theme: buildCupertinoTheme(brightness),
                home: const OnboardingPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(OnboardingPage));
          final l10n = AppLocalizations.of(context);
          final description = tester.widget<Text>(
            find.text(l10n.inputServerAddressHint),
          );
          final url = tester.widget<CupertinoTextField>(
            find.byKey(const ValueKey('onboarding-url')),
          );
          final button = tester.widget<CupertinoButton>(
            find.byKey(const ValueKey('onboarding-connect')),
          );

          if (brightness == Brightness.light) {
            expect(description.style!.color, LightSurfaces.textSecondary);
            expect(
              _contrast(description.style!.color!, LightSurfaces.page),
              greaterThanOrEqualTo(4.5),
            );
            expect(url.decoration!.color, LightSurfaces.card);
            expect(url.decoration!.border!.top.color, LightSurfaces.cardBorder);
            expect(
              _contrast(url.placeholderStyle!.color!, url.decoration!.color!),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              _contrast(CupertinoColors.white, button.color!),
              greaterThanOrEqualTo(4.5),
            );
          } else {
            expect(
              description.style!.color,
              secondaryText.resolveFrom(context),
            );
            expect(url.decoration, const CupertinoTextField().decoration);
            expect(
              url.placeholderStyle,
              const CupertinoTextField().placeholderStyle,
            );
            expect(button.color, isNull);
          }

          // The password field appears only after the existing health/auth flow.
          await tester.enterText(
            find.byKey(const ValueKey('onboarding-url')),
            'https://hermes.example.com',
          );
          await tester.tap(find.byKey(const ValueKey('onboarding-connect')));
          await tester.pump();
          final busyButton = tester.widget<CupertinoButton>(
            find.byKey(const ValueKey('onboarding-connect')),
          );
          final spinner = busyButton.child as CupertinoActivityIndicator;
          expect(busyButton.onPressed, isNull);
          if (brightness == Brightness.light) {
            // A busy filled button uses the SDK disabled fill, not its blue color.
            for (final surface in [LightSurfaces.card, LightSurfaces.page]) {
              final disabledFill = Color.alphaBlend(
                CupertinoDynamicColor.resolve(
                  busyButton.disabledColor,
                  context,
                ),
                surface,
              );
              expect(
                _contrast(spinner.color!, disabledFill),
                greaterThanOrEqualTo(3),
              );
            }
          } else {
            expect(spinner.color, isNull);
          }
          api.response.complete(const HealthResponse(status: 'ok'));
          await tester.pumpAndSettle();
          final password = tester.widget<CupertinoTextField>(
            find.byKey(const ValueKey('onboarding-password')),
          );
          expect(password.decoration, url.decoration);
          expect(password.placeholderStyle, url.placeholderStyle);
          expect(password.obscureText, isTrue);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }

    testWidgets('missing agent actions and warning surface $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bundledWebuiAvailableProvider.overrideWithValue(true),
            connectionStoreProvider.overrideWithValue(
              ConnectionStore(storage: InMemorySecureStorage()),
            ),
            agentEnvPresentProvider.overrideWith(_MissingAgent.new),
            webuiSidecarControllerProvider.overrideWith(_StoppedSidecar.new),
            webuiSidecarConfigProvider.overrideWith(_DemoConfig.new),
          ],
          child: CupertinoApp(
            theme: buildCupertinoTheme(brightness),
            home: const CupertinoPageScaffold(child: BuiltinTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = tester.widget<Container>(
        find.byKey(const ValueKey('onboarding-missing-agent-card')),
      );
      final decoration = card.decoration! as BoxDecoration;
      final context = tester.element(find.byType(BuiltinTab));
      final install = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('onboarding-install-agent-btn')),
      );
      if (brightness == Brightness.light) {
        expect(decoration.color, LightSurfaces.tintWarning);
        expect(decoration.border!.top.color, LightSurfaces.cardBorder);
        expect(
          _contrast(statusOrangeText.resolveFrom(context), decoration.color!),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(LightSurfaces.textSecondary, decoration.color!),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(CupertinoColors.white, install.color!),
          greaterThanOrEqualTo(4.5),
        );
      } else {
        expect(
          decoration.color,
          CupertinoColors.systemOrange
              .resolveFrom(context)
              .withValues(alpha: 0.12),
        );
        expect(
          decoration.border!.top.color,
          CupertinoColors.systemOrange
              .resolveFrom(context)
              .withValues(alpha: 0.35),
        );
        expect(
          install.color,
          CupertinoColors.activeOrange.resolveFrom(context),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
