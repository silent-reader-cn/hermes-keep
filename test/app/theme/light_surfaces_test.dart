import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';

import '../../helpers/contrast_utils.dart';

void main() {
  test('次级文字及占位符在页面、卡片、选中、按下面均满足正文 AA', () {
    for (final surface in [
      LightSurfaces.page,
      LightSurfaces.card,
      LightSurfaces.selection,
      LightSurfaces.pressed,
      LightSurfaces.tintGreen,
      LightSurfaces.tintWarning,
      LightSurfaces.tintError,
      LightSurfaces.tintClarification,
    ]) {
      expect(
        contrastRatio(LightSurfaces.textSecondary, surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(LightSurfaces.placeholder, surface),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrastRatio(CupertinoColors.white, LightSurfaces.userDetail),
      greaterThanOrEqualTo(4.5),
    );
    for (final token in [
      LightSurfaces.userDetail,
      LightSurfaces.page,
      LightSurfaces.card,
      LightSurfaces.cardBorder,
      LightSurfaces.divider,
      LightSurfaces.textSecondary,
      LightSurfaces.placeholder,
      LightSurfaces.selection,
      LightSurfaces.pressed,
      LightSurfaces.tintGreen,
      LightSurfaces.tintWarning,
      LightSurfaces.tintError,
      LightSurfaces.tintClarification,
    ]) {
      expect(token.a, 1);
      expect(token, isNot(isA<CupertinoDynamicColor>()));
    }
  });

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      for (final level in CupertinoUserInterfaceLevelData.values) {
        testWidgets('$brightness / highContrast=$highContrast / $level', (
          tester,
        ) async {
          await tester.pumpWidget(
            CupertinoApp(
              theme: buildCupertinoTheme(brightness),
              home: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
                child: CupertinoUserInterfaceLevel(
                  data: level,
                  child: Builder(
                    builder: (context) {
                      for (final legacy in <Color>[
                        CupertinoColors.systemBackground,
                        CupertinoColors.systemGroupedBackground,
                        CupertinoColors.secondarySystemGroupedBackground,
                        CupertinoColors.systemGrey5,
                        CupertinoColors.secondaryLabel,
                        CupertinoColors.separator,
                        secondaryText,
                        const Color(0xFF8E8E93),
                        const Color(0xFF007AFF),
                        const Color(0xCC2C2C2E),
                      ]) {
                        final actual = LightSurfaces.resolve(
                          context,
                          LightSurfaces.card,
                          dark: legacy,
                        );
                        final expected = brightness == Brightness.light
                            ? LightSurfaces.card
                            : CupertinoDynamicColor.resolve(legacy, context);
                        expect(actual.toARGB32(), expected.toARGB32());
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          );
        });
      }
    }
  }
}
