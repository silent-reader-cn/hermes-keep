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

  /// Native switch interaction with visible light tracks, also when disabled.
  static CupertinoSwitch toggle(
    BuildContext context,
    CupertinoSwitch original,
  ) {
    if (!isLight(context)) return original;
    // CupertinoSwitch composites disabled controls at 50% opacity. Black
    // becomes #808080 on white (3.95:1), keeping the track distinguishable.
    final disabled = original.onChanged == null;
    return CupertinoSwitch(
      key: original.key,
      value: original.value,
      onChanged: original.onChanged,
      activeTrackColor: disabled
          ? CupertinoColors.black
          : statusGreenText.resolveFrom(context),
      inactiveTrackColor: disabled
          ? CupertinoColors.black
          : LightSurfaces.textSecondary,
      thumbColor: LightSurfaces.card,
      inactiveThumbColor: LightSurfaces.card,
      focusNode: original.focusNode,
      autofocus: original.autofocus,
      onFocusChange: original.onFocusChange,
    );
  }

  /// Uses selection blue on light segmented controls only.
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
      backgroundColor: LightSurfaces.page,
      thumbColor: LightSurfaces.selection,
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
