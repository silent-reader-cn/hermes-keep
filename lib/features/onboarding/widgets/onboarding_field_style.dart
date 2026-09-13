import 'package:flutter/cupertino.dart';

import '../../../app/theme/light_surfaces.dart';

/// Shared field styling for the connection and local installation forms.
abstract final class OnboardingFieldStyle {
  /// Keeps the SDK field geometry and dark decoration intact.
  static BoxDecoration? decoration(BuildContext context) {
    final original = const CupertinoTextField().decoration;
    return CupertinoTheme.brightnessOf(context) == Brightness.light
        ? original?.copyWith(
            color: LightSurfaces.card,
            border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
          )
        : original;
  }

  /// Makes placeholders readable on the light field surface.
  static TextStyle? placeholder(BuildContext context) {
    final original = const CupertinoTextField().placeholderStyle;
    return CupertinoTheme.brightnessOf(context) == Brightness.light
        ? original?.copyWith(color: LightSurfaces.placeholder)
        : original;
  }
}
