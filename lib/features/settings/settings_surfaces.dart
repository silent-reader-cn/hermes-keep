import 'dart:async';
import 'dart:math' as math;

import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../core/utils/accessibility.dart';

/// 设置页族的呈现接缝：结构（分区卡片 / 排版令牌）两主题统一，控件皮肤按
/// 主题取舍 —— 浅色走冻结的浅色令牌，深色沿用 SDK 原生。
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

  /// 分区卡片：**两个主题共用同一套 inset 结构** —— 相同的水平内缩
  /// (`16/8/16/8`)、圆角 14、0.5pt 前景描边、0.5pt 全宽分割线，以及同一套排版
  /// 令牌；只有**取色**按主题解析（浅色读 [LightSurfaces] 固定令牌；深色读
  /// Cupertino 动态语义色并 `resolveFrom` 保留高对比度 / elevated 变体）。
  ///
  /// 统一的是**结构**：深色下 base 构造的默认 `margin` 是
  /// `EdgeInsets.only(bottom: 8)`（零水平边距、零圆角、无前景描边），那正是
  /// 「深色通栏方角、浅色内缩卡片」这一控件级不一致的根因。
  ///
  /// 控件皮肤（toggle / segmented / dialog / sheet / fieldDecoration /
  /// actionColor / selection / serverAction）仍各自 `isLight` 门控，深色继续
  /// 走 SDK 原生，本轮**不**统一它们。
  static CupertinoListSection section(
    BuildContext context,
    CupertinoListSection original,
  ) {
    const radius = BorderRadius.all(Radius.circular(14));
    final palette = _SectionPalette.of(context);
    final rows = original.children ?? const <Widget>[];
    return CupertinoListSection.insetGrouped(
      key: original.key,
      backgroundColor: palette.page,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      dividerMargin: 0,
      additionalDividerMargin: 0,
      separatorColor: palette.divider,
      clipBehavior: Clip.none,
      header: original.header == null
          ? null
          : DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: kFontSectionTitle,
                fontWeight: FontWeight.w500,
                color: palette.secondaryText,
              ),
              child: original.header!,
            ),
      footer: _secondary(original.footer, palette),
      decoration: BoxDecoration(color: palette.card, borderRadius: radius),
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
                    border: Border.all(color: palette.border, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          SizedBox(
                            height: 0.5,
                            width: double.infinity,
                            child: ColoredBox(color: palette.divider),
                          ),
                        rows[i] is CupertinoListTile
                            ? _tile(rows[i] as CupertinoListTile, palette)
                            : rows[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
    );
  }

  /// 设置项名：统一到项名档 [kFontItemTitle]（不继承主题 17pt）。
  static Widget _primary(Widget child) => DefaultTextStyle.merge(
    style: const TextStyle(fontSize: kFontItemTitle),
    child: child,
  );

  /// 说明 / 附加信息：统一到注解档（原先继承主题 17pt，在宽屏右侧显得过大）。
  ///
  /// 字号令牌在**两个主题**都生效（字号统一是本轮目的之一）；颜色按主题解析
  /// —— 浅色读 [LightSurfaces.textSecondary]，深色读 `secondaryLabel`
  /// 的动态变体，避免把「只在白卡上成立的深灰」硬搬到深色卡片上。
  ///
  /// [palette] 由调用方解析一次后透传，避免每行重复解一遍动态色。
  static Widget? _secondary(Widget? child, _SectionPalette palette) =>
      child == null
      ? null
      : DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: kFontCaption,
            color: palette.secondaryText,
          ),
          child: child,
        );

  static CupertinoListTile _tile(
    CupertinoListTile original,
    _SectionPalette palette,
  ) => CupertinoListTile(
    key: original.key,
    // 设置项名统一到项名档（原先继承主题 17pt —— 主人反馈宽屏右侧「太大」）。
    title: _primary(original.title),
    subtitle: _secondary(original.subtitle, palette),
    additionalInfo: _secondary(original.additionalInfo, palette),
    leading: original.leading,
    trailing: _trailing(original.trailing, palette),
    onTap: original.onTap,
    padding: original.padding,
    leadingSize: original.leadingSize,
    leadingToTitle: original.leadingToTitle,
    backgroundColor: original.backgroundColor,
    backgroundColorActivated: palette.pressed,
  );

  static Widget? _trailing(Widget? original, _SectionPalette palette) {
    if (original is CupertinoListTileChevron) {
      return Icon(
        CupertinoIcons.right_chevron,
        size: kFontItemTitle,
        color: palette.secondaryText,
      );
    }
    if (original is Icon && original.icon == CupertinoIcons.chevron_right) {
      return Icon(
        original.icon,
        key: original.key,
        size: original.size,
        semanticLabel: original.semanticLabel,
        textDirection: original.textDirection,
        color: palette.secondaryText,
      );
    }
    return _secondary(original, palette);
  }

  /// Selection adds a surface only in light mode; checkmarks remain intact.
  ///
  /// L2：浅色选中底改中性灰 .16（暗色返回 null，取值未变）。
  static Color? selection(BuildContext context, bool selected) =>
      isLight(context) && selected ? LightSurfaces.selectedSurface : null;

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
    final base = isLight(context) ? _pinnedLightSegmented(original) : original;
    return _withSegmentLabelColors(context, base);
  }

  /// 浅色档：把 SDK 的拇指/轨道钉回 iOS 原生取值（白拇指 + `tertiarySystemFill`）。
  static CupertinoSlidingSegmentedControl<T>
  _pinnedLightSegmented<T extends Object>(
    CupertinoSlidingSegmentedControl<T> original,
  ) => CupertinoSlidingSegmentedControl<T>(
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

  /// 分段标签「选中 / 未选中」分档上色（#180，2026-10-07 主人拍板档 1）。
  ///
  /// ── 修的是什么 ──────────────────────────────────────────────────────────
  /// [segmentedRow] 走的是 [`_trailing`]，而 `_trailing` 会把「非 chevron 的
  /// trailing」交给 [`_secondary`] —— 后者给整块控件 merge 一个
  /// `color: palette.secondaryText` 的 `DefaultTextStyle`
  /// （深色 = `CupertinoColors.secondaryLabel`，即 `#EBEBF5` @60%）。
  /// 而 SDK 对**启用**的段写死 `color: null`（`sliding_segmented_control.dart:212`）
  /// ⇒ **选中段与未选中段被迫共用同一个「次级色」**。同一个色，合成到更亮的
  /// 胶囊 `#636366` 上只剩 **2.92:1**（真机像素实测 `#B5B6BB`/`#636365`，
  /// 低于 AA 正文 4.5:1，连 3:1 都不到），而合成到暗轨道 `#323235` 上是
  /// 5.00:1 —— 于是**选中项成了整行对比度最弱的元素**（同行行标题是 15.7:1）。
  ///
  /// ── 怎么修 ──────────────────────────────────────────────────────────────
  /// 只把**选中段**的标签色换成主标签色 [CupertinoColors.label]
  /// （深色 `#FFFFFF` / 浅色 `#000000`），与同行行标题同一层级：
  /// 深色 **2.92 → 5.99:1**、浅色 5.38 → **21.0:1**。
  /// 未选中段继续读 `_SectionPalette.secondaryText`，保持"次级"的层级不抢眼
  /// （暗轨道上 5.00:1、浅色 4.68:1，均达标）。
  /// **胶囊本身不动**（深色仍是 SDK 原生的 `#636366`）—— 改动只落在"字色"这一处。
  ///
  /// 早前那条把浅色拇指改蓝的尝试（`#E0ECFF`）已被证伪并回滚，本次不再碰拇指。
  static CupertinoSlidingSegmentedControl<T> _withSegmentLabelColors<
    T extends Object
  >(BuildContext context, CupertinoSlidingSegmentedControl<T> base) {
    final selectedLabel = CupertinoColors.label.resolveFrom(context);
    final unselectedLabel = _SectionPalette.of(context).secondaryText;
    return CupertinoSlidingSegmentedControl<T>(
      key: base.key,
      children: {
        for (final entry in base.children.entries)
          entry.key: DefaultTextStyle.merge(
            style: TextStyle(
              color: entry.key == base.groupValue
                  ? selectedLabel
                  : unselectedLabel,
            ),
            child: entry.value,
          ),
      },
      onValueChanged: base.onValueChanged,
      disabledChildren: base.disabledChildren,
      groupValue: base.groupValue,
      padding: base.padding,
      proportionalWidth: base.proportionalWidth,
      isMomentary: base.isMomentary,
      backgroundColor: base.backgroundColor,
      thumbColor: base.thumbColor,
    );
  }

  /// 行标题预留宽度下限（逻辑像素）：控件再宽也至少给标题留这么宽的横排空间。
  static const double kMinTitleReserve = 44.0;

  /// `CupertinoListTile` 默认左右内边距之和（框架 `_kPadding` /
  /// `_kPaddingWithSubtitle` 均为 `start: 20, end: 14`，合计 34）。
  ///
  /// 行内真实可用宽 = 行外量到的 tile 宽 − 本值。之所以要自己减：**
  /// `CupertinoListTile` 用 `LayoutBuilder` 量不到行内宽** —— 框架把 trailing
  /// 摆在 `Row` 的**非弹性**槽位，而非弹性子项在横向 `Row` 里拿到的是
  /// `BoxConstraints(maxHeight: …)`（**没有 maxWidth**，即无限宽）。实测
  /// `trailing` 里的 `LayoutBuilder` 永远读到 `Infinity`（探针
  /// `test/screenshots/crispness_probe_test.dart` 的 SEGTRAIL 输出）。
  static const double kTileRowInset = 34.0;

  /// 一行「名字（+ 副标题） + 分段控件」的 `CupertinoListTile`，控件**不缩放**。
  ///
  /// ── 它替掉了什么 ────────────────────────────────────────────────────────
  /// 过去这些行写作
  /// `trailing: ConstrainedBox(maxWidth: 220) > FittedBox(scaleDown)`。
  /// `FittedBox` 会把「塞不下的整块控件」等比缩小 ⇒ **文字与图标一起被重采样**。
  /// 探针实测（MiSans、`CRISPNESS_PROBE=1`）：
  ///   ·「会话分组方式」行（cap 200，控件实需 219.1）⇒ scale 0.9129，
  ///     13pt 标签被画成 11.87pt；
  ///   · 英文界面「推送测试类型」行（cap 240，实需 378.6）⇒ scale 0.6339，
  ///     13pt 被画成 8.24pt（比 `kFontMicro` 的 11 还小）。
  ///
  /// ── 怎么做到不缩放 ──────────────────────────────────────────────────────
  /// **只限宽、不缩放**：控件交给 `BoxConstraints(maxWidth: cap)` 即可。
  /// `CupertinoSlidingSegmentedControl` 自己会把每段宽度收敛到
  /// `(maxWidth − 分隔线) / 段数`，而每段里还留着 2×10 逻辑像素的固定最小内边距
  /// 可被收缩吸收 —— 因此**字形从不被重采样**，最坏也只是段变窄、文字换行。
  ///
  /// 宽度上限 `cap = 行内可用宽 − [reserveForTitle]`：给标题留出横排空间，避免
  /// 控件变宽把标题挤折行。只要 `cap` 不小于控件实需宽度，控件就按原尺寸渲染，
  /// `scale ≡ 1.0`（探针实测：中文界面 320–1600 宽全部 `issues=none`）。
  ///
  /// 之所以在 **tile 外**包 `LayoutBuilder`（而不是在 trailing 里）：见
  /// [kTileRowInset] 的说明 —— trailing 槽位拿到的是无限宽约束，在那里量不到行宽。
  static Widget segmentedRow(
    BuildContext context, {
    required Widget title,
    required Widget control,
    required double reserveForTitle,
    Widget? subtitle,
    Key? key,
    VoidCallback? onTap,
    Widget? leading,
  }) {
    return LayoutBuilder(
      builder: (layoutContext, constraints) {
        final tileWidth = constraints.maxWidth;
        final rowWidth = tileWidth.isFinite
            ? tileWidth - kTileRowInset
            : double.infinity;
        // ⚠️ 这里必须**逐项复刻** `_tile()` 的装配（`_primary` / `_secondary` /
        // `_trailing`）：`section()` 只对「本身是 `CupertinoListTile` 的行」调用
        // `_tile()`，而本部件在 tile 外包了 `LayoutBuilder`，`_tile()` 因此不会
        // 再被套用。漏掉任何一项都会静默改掉字号/颜色/描边（实测踩过：漏了
        // `_trailing` ⇒ 分段标签从 `textSecondary` 变回 `label`；漏了 `_primary`
        // ⇒ 项名从 15pt 掉回主题 17pt）。
        final palette = _SectionPalette.of(context);
        return CupertinoListTile(
          key: key,
          leading: leading,
          title: _primary(title),
          subtitle: _secondary(subtitle, palette),
          onTap: onTap,
          backgroundColorActivated: palette.pressed,
          trailing: _trailing(
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(
                  rowWidth,
                  math.max(rowWidth - reserveForTitle, kMinTitleReserve),
                ),
              ),
              child: control,
            ),
            palette,
          ),
        );
      },
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
      title: _secondary(original.title, _SectionPalette.of(context)),
      message: _secondary(original.message, _SectionPalette.of(context)),
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

/// 分区卡片的结构取色族：**浅色逐令牌固定，深色逐语义动态**。
///
/// 之所以单列一族：本轮把「深色 / 浅色两套分区结构」收敛成一套，取色是**唯一**
/// 允许分叉的维度。深色一律走 [CupertinoColors] 的动态语义色并 `resolveFrom`，
/// 因此高对比度与 elevated（`CupertinoUserInterfaceLevel`）变体都被保留；浅色
/// 读 [LightSurfaces] 的固定令牌（含用户可调的页底色 getter），逐像素不变。
///
/// **不得**把深浅两边的取值写成同一条 ARGB 字面量 —— 那会在高对比度模式下丢掉
/// 系统专属变体，等于把动态色语义抹掉。
class _SectionPalette {
  const _SectionPalette({
    required this.page,
    required this.card,
    required this.border,
    required this.divider,
    required this.secondaryText,
    required this.pressed,
  });

  /// 分区背后整页底色。
  final Color page;

  /// 卡片底。
  final Color card;

  /// 卡片轮廓 + 结构线（同值同族，浅色口径一致）。
  final Color border;
  final Color divider;

  /// 分组标题 / 说明 / 副标题 / chevron 的颜色。
  final Color secondaryText;

  /// 行按下底。
  final Color pressed;

  static _SectionPalette of(BuildContext context) {
    if (SettingsSurfaces.isLight(context)) {
      return _SectionPalette(
        page: LightSurfaces.page,
        card: LightSurfaces.card,
        border: LightSurfaces.cardBorder,
        divider: LightSurfaces.divider,
        secondaryText: LightSurfaces.textSecondary,
        pressed: LightSurfaces.pressed,
      );
    }
    // 深色：与 SDK 原生的分组语义对齐 —— 页 `systemGroupedBackground`、
    // 卡片 `secondarySystemGroupedBackground`、线族 `separator`、次级文字
    // `secondaryLabel`、行按下底 `systemGrey4`（即 CupertinoListTile 的默认值）。
    return _SectionPalette(
      page: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      card: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      border: CupertinoColors.separator.resolveFrom(context),
      divider: CupertinoColors.separator.resolveFrom(context),
      secondaryText: CupertinoColors.secondaryLabel.resolveFrom(context),
      pressed: CupertinoColors.systemGrey4.resolveFrom(context),
    );
  }
}
