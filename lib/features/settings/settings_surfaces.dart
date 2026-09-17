import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../core/utils/accessibility.dart';

/// Opt-in settings presentation. Dark mode returns the original widgets.
abstract final class SettingsSurfaces {
  /// Whether this settings view uses the frozen light palette.
  static bool isLight(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.light;

  /// Gives each settings route its own opaque page and navigation surfaces.
  static Widget page(BuildContext context, Widget child) {
    if (!isLight(context)) return child;
    final theme = CupertinoTheme.of(context);
    return CupertinoTheme(
      data: theme.copyWith(
        scaffoldBackgroundColor: LightSurfaces.page,
        barBackgroundColor: LightSurfaces.page,
      ),
      child: DefaultSelectionStyle(
        selectionColor: LightSurfaces.selection,
        cursorColor: DefaultSelectionStyle.of(context).cursorColor,
        child: child,
      ),
    );
  }

  /// Inset white cards with full-width 0.5-point separators in light mode.
  ///
  /// Keeping the original section in dark mode also preserves native margins,
  /// header typography and separator resolution.
  static CupertinoListSection section(
    BuildContext context,
    CupertinoListSection original,
  ) {
    if (!isLight(context)) return original;
    const radius = BorderRadius.all(Radius.circular(14));
    final rows = original.children ?? const <Widget>[];
    return CupertinoListSection.insetGrouped(
      key: original.key,
      backgroundColor: LightSurfaces.page,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      dividerMargin: 0,
      additionalDividerMargin: 0,
      separatorColor: LightSurfaces.divider,
      clipBehavior: Clip.none,
      header: original.header == null
          ? null
          : DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: LightSurfaces.textSecondary,
              ),
              child: original.header!,
            ),
      footer: _secondary(original.footer),
      decoration: const BoxDecoration(
        color: LightSurfaces.card,
        borderRadius: radius,
      ),
      // A single native child lets separators stay at 0.5 logical pixels at
      // every device pixel ratio. The foreground border survives pressed rows.
      children: rows.isEmpty
          ? null
          : [
              ClipRRect(
                borderRadius: radius,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: LightSurfaces.cardBorder,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          const SizedBox(
                            height: 0.5,
                            width: double.infinity,
                            child: ColoredBox(color: LightSurfaces.divider),
                          ),
                        rows[i] is CupertinoListTile
                            ? _tile(context, rows[i] as CupertinoListTile)
                            : rows[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
    );
  }

  static Widget? _secondary(Widget? child) => child == null
      ? null
      : DefaultTextStyle.merge(
          style: const TextStyle(color: LightSurfaces.textSecondary),
          child: child,
        );

  static CupertinoListTile _tile(
    BuildContext context,
    CupertinoListTile original,
  ) => CupertinoListTile(
    key: original.key,
    title: original.title,
    subtitle: _secondary(original.subtitle),
    additionalInfo: _secondary(original.additionalInfo),
    leading: original.leading,
    trailing: _trailing(context, original.trailing),
    onTap: original.onTap,
    padding: original.padding,
    leadingSize: original.leadingSize,
    leadingToTitle: original.leadingToTitle,
    backgroundColor: original.backgroundColor,
    backgroundColorActivated: LightSurfaces.pressed,
  );

  static Widget? _trailing(BuildContext context, Widget? original) {
    if (original is CupertinoListTileChevron) {
      return Icon(
        CupertinoIcons.right_chevron,
        size: CupertinoTheme.of(context).textTheme.textStyle.fontSize,
        color: LightSurfaces.textSecondary,
      );
    }
    if (original is Icon && original.icon == CupertinoIcons.chevron_right) {
      return Icon(
        original.icon,
        key: original.key,
        size: original.size,
        semanticLabel: original.semanticLabel,
        textDirection: original.textDirection,
        color: LightSurfaces.textSecondary,
      );
    }
    return _secondary(original);
  }

  /// Selection adds a surface only in light mode; checkmarks remain intact.
  static Color? selection(BuildContext context, bool selected) =>
      isLight(context) && selected ? LightSurfaces.selection : null;

  /// Preserves the SDK's original dark text-field decoration verbatim.
  static BoxDecoration fieldDecoration(BuildContext context) => isLight(context)
      ? BoxDecoration(
          color: LightSurfaces.card,
          border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
          borderRadius: const BorderRadius.all(Radius.circular(5)),
        )
      : const BoxDecoration(
          color: CupertinoDynamicColor.withBrightness(
            color: CupertinoColors.white,
            darkColor: CupertinoColors.black,
          ),
          border: Border.fromBorderSide(
            BorderSide(
              color: CupertinoDynamicColor.withBrightness(
                color: Color(0x33000000),
                darkColor: Color(0x33FFFFFF),
              ),
              width: 0,
            ),
          ),
          borderRadius: BorderRadius.all(Radius.circular(5)),
        );

  /// Readable placeholders without changing the SDK's dark weight or color.
  static TextStyle placeholderStyle(BuildContext context) => TextStyle(
    fontWeight: FontWeight.w400,
    color: LightSurfaces.resolve(
      context,
      LightSurfaces.placeholder,
      dark: CupertinoColors.placeholderText,
    ),
  );

  /// Text-button foreground, including disabled form submission buttons.
  static Color? actionColor(BuildContext context, {bool disabled = false}) =>
      isLight(context)
      ? (disabled ? LightSurfaces.textSecondary : LightSurfaces.menuAction)
      : null;

  /// Keeps button labels readable throughout the light pressed animation.
  static double pressedOpacity(BuildContext context) =>
      isLight(context) ? 0.9 : 0.4;

  /// Plain server actions retain accessibility and haptics while held down.
  ///
  /// AccessibleButton has no pressed-opacity option. Keep its original dark
  /// widget and adapt only these two light server actions within this feature.
  static Widget serverAction(BuildContext context, AccessibleButton original) {
    if (!isLight(context)) return original;
    return Semantics(
      key: original.key,
      button: true,
      enabled: original.onPressed != null,
      label: original.label,
      hint: original.hint,
      child: CupertinoButton(
        padding: original.padding,
        minimumSize: original.minimumSize,
        color: original.color,
        disabledColor: original.disabledColor,
        borderRadius: original.borderRadius,
        alignment: original.alignment,
        foregroundColor: actionColor(
          context,
          disabled: original.onPressed == null,
        ),
        pressedOpacity: pressedOpacity(context),
        onPressed: original.onPressed == null
            ? null
            : () {
                unawaited(selectionHaptic());
                original.onPressed!();
              },
        child: original.child,
      ),
    );
  }

  /// Native navigation hairline, using the unified structure token in light.
  static Border navigationBorder(BuildContext context) => Border(
    bottom: BorderSide(
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.divider,
        dark: const Color(0x4D000000),
      ),
      width: 0,
    ),
  );

  /// Native switch interaction with iOS system colours in light mode.
  ///
  /// Enabled tracks keep the SDK palette verbatim: [CupertinoColors.systemGreen]
  /// on (#34C759) and the near-invisible [CupertinoColors.secondarySystemFill]
  /// off (composites to #EAEAEB on a white card, 1.20:1).
  ///
  /// A previous revision fed the *text* status green (`statusGreenText`,
  /// #1E7A34 -- darkened to reach 4.5:1 for label text) into the track fill,
  /// which turned the switch into a solid dark block. WCAG text contrast does
  /// not govern a large control fill, so that mapping was a category error.
  ///
  /// Disabled controls are composited by the SDK at 50% opacity, where both
  /// tracks would collapse to an unreadable wash; black keeps a visible track
  /// at 3.95:1 on white (#808080). That is the one deliberate light-mode
  /// departure, and it is pinned by [settings_light_surfaces_test].
  static CupertinoSwitch toggle(
    BuildContext context,
    CupertinoSwitch original,
  ) {
    if (!isLight(context)) return original;
    final disabled = original.onChanged == null;
    return CupertinoSwitch(
      key: original.key,
      value: original.value,
      onChanged: original.onChanged,
      activeTrackColor: disabled
          ? CupertinoColors.black
          : CupertinoColors.systemGreen,
      inactiveTrackColor: disabled
          ? CupertinoColors.black
          : CupertinoColors.secondarySystemFill,
      thumbColor: CupertinoColors.white,
      inactiveThumbColor: CupertinoColors.white,
      focusNode: original.focusNode,
      autofocus: original.autofocus,
      onFocusChange: original.onFocusChange,
    );
  }

  /// Pins light-mode segmented controls to the SDK's native iOS palette.
  ///
  /// This seam previously re-skinned the thumb with [LightSurfaces.selection]
  /// (#E0ECFF) on a [LightSurfaces.page] track. Measured against iOS that read
  /// as a recessed blue block, and it separated *worse* than the native white
  /// thumb (1.069:1 vs 1.149:1 thumb-to-track) -- a pure regression with no
  /// accessibility payoff, since the SDK default already passes.
  ///
  /// The two colours below are byte-identical to the SDK defaults
  /// (`_kThumbColor` / `tertiarySystemFill`). They stay pinned explicitly so
  /// the settings family cannot silently drift away from the platform control
  /// again -- that drift is exactly what this file had to undo.
  static CupertinoSlidingSegmentedControl<T> segmented<T extends Object>(
    BuildContext context,
    CupertinoSlidingSegmentedControl<T> original,
  ) {
    if (!isLight(context)) return original;
    return CupertinoSlidingSegmentedControl<T>(
      key: original.key,
      children: original.children,
      onValueChanged: original.onValueChanged,
      disabledChildren: original.disabledChildren,
      groupValue: original.groupValue,
      padding: original.padding,
      proportionalWidth: original.proportionalWidth,
      isMomentary: original.isMomentary,
      backgroundColor: CupertinoColors.tertiarySystemFill,
      thumbColor: CupertinoColors.white,
    );
  }

  /// Native action-sheet surfaces with readable labels and destructive text.
  static CupertinoActionSheet sheet(
    BuildContext context,
    CupertinoActionSheet original,
  ) {
    if (!isLight(context)) return original;
    Widget action(Widget child) {
      if (child is! CupertinoActionSheetAction) return child;
      return CupertinoActionSheetAction(
        key: child.key,
        onPressed: child.onPressed,
        isDefaultAction: child.isDefaultAction,
        isDestructiveAction: child.isDestructiveAction,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: child.isDestructiveAction
                ? statusRedText.resolveFrom(context)
                : LightSurfaces.menuAction,
          ),
          child: child.child,
        ),
      );
    }

    return CupertinoActionSheet(
      key: original.key,
      title: _secondary(original.title),
      message: _secondary(original.message),
      messageScrollController: original.messageScrollController,
      actionScrollController: original.actionScrollController,
      actions: original.actions?.map(action).toList(),
      cancelButton: original.cancelButton == null
          ? null
          : action(original.cancelButton!),
    );
  }

  /// Alert actions keep native behavior and dark pixels, including deletion.
  static CupertinoAlertDialog dialog(
    BuildContext context,
    CupertinoAlertDialog original,
  ) {
    if (!isLight(context)) return original;
    return CupertinoAlertDialog(
      key: original.key,
      title: original.title,
      content: original.content,
      scrollController: original.scrollController,
      actionScrollController: original.actionScrollController,
      insetAnimationDuration: original.insetAnimationDuration,
      insetAnimationCurve: original.insetAnimationCurve,
      actions: [
        for (final action in original.actions)
          if (action is CupertinoDialogAction)
            CupertinoDialogAction(
              key: action.key,
              onPressed: action.onPressed,
              isDefaultAction: action.isDefaultAction,
              isDestructiveAction: action.isDestructiveAction,
              textStyle: (action.textStyle ?? const TextStyle()).copyWith(
                color: action.onPressed == null
                    ? LightSurfaces.textSecondary
                    : action.isDestructiveAction
                    ? statusRedText.resolveFrom(context)
                    : LightSurfaces.menuAction,
              ),
              child: action.onPressed == null
                  ? DefaultTextStyle.merge(
                      // CupertinoDialogAction halves its own disabled text
                      // alpha; an inner style keeps the label readable.
                      style: const TextStyle(
                        color: LightSurfaces.textSecondary,
                      ),
                      child: action.child,
                    )
                  : action.child,
            )
          else
            action,
      ],
    );
  }
}
