import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import '../theme/layout_tokens.dart';

/// G4：宽屏**常显**的细滚动条（6px 圆头、悬停加深）；窄屏原样透传。
///
/// 背景（设计稿 §G4）：Mac 默认滚动条隐身、Windows 会忽然冒出一条粗的 ——
/// 宽屏下滚动位置是导航信息（「这屏还有多长」「我在哪」），隐身等于把这条信息
/// 丢掉。统一成常显细条。
///
/// 取值（设计稿原值，明暗两套）：
/// - 浅色：常态 `rgba(60,60,67,.32)` → 悬停 `rgba(60,60,67,.55)`
/// - 暗色：常态 `rgba(235,235,245,.30)` → 悬停 `rgba(235,235,245,.42)`
/// - 厚度 6（[kScrollbarThickness]）、圆头半径 3（[kScrollbarRadius]）
///
/// 实现要点：
/// - 直接继承 [RawScrollbar]，而不是 `CupertinoScrollbar`：后者的公开构造器
///   **不接受** thumb 颜色（颜色写死在 `_CupertinoScrollbarState` 的
///   `_kScrollbarColor`），且默认 `thumbVisibility: false`、厚度 3 —— 与 G4 的
///   「常显 6px」正相反。本类复用的 `updateScrollbarPainter` / `handleHover`
///   两个钩子，正是 `CupertinoScrollbar` 自己也用的扩展点。
/// - 「悬停加深」用 `RawScrollbarState` 暴露的钩子：`handleHover` +
///   `isPointerOverThumb`（指针**压在滑块上**才算悬停 —— 不是「指针在内容区里」
///   就算，否则常态与悬停两档根本分不出来），颜色直接改在 `scrollbarPainter`
///   上（`ScrollbarPainter` 是 ChangeNotifier，改色即重绘）。
/// - 窄屏（`width < kWideBreakpoint`）：**不包滚条、不改任何行为**，直接返回
///   `child`，滚动条仍由平台自己的 `ScrollBehavior` 决定（手机端逐像素不变）。
///
/// 消费前提：[thumbVisibility] 常显需要一个 [ScrollController]（或挂在
/// `PrimaryScrollController` 上），与 `CupertinoScrollbar` 的官方要求一致 ——
/// 拿不到 controller 时不会崩，只是不画滑块。
class AppScrollbar extends RawScrollbar {
  /// 创建一个宽屏常显滚动条（默认：常显 6px 圆头）。
  ///
  /// [thumbColor] / [hoverThumbColor] 留作覆写口；不传则按当前明暗取 G4 规格值。
  const AppScrollbar({
    super.key,
    required super.child,
    super.controller,
    super.thumbVisibility = true,
    super.thickness = kScrollbarThickness,
    super.radius = const Radius.circular(kScrollbarRadius),
    super.thumbColor,
    this.hoverThumbColor,
    super.interactive,
    super.mainAxisMargin,
  });

  /// 悬停（鼠标压在滑块上）时的滑块色；null = 按明暗取规格值。
  final Color? hoverThumbColor;

  /// G4 浅色档 · 常态滑块 `rgba(60,60,67,.32)`。
  static const Color lightThumb = Color.fromRGBO(60, 60, 67, 0.32);

  /// G4 浅色档 · 悬停滑块 `rgba(60,60,67,.55)`。
  static const Color lightThumbHover = Color.fromRGBO(60, 60, 67, 0.55);

  /// G4 暗色档 · 常态滑块 `rgba(235,235,245,.30)`。
  static const Color darkThumb = Color.fromRGBO(235, 235, 245, 0.30);

  /// G4 暗色档 · 悬停滑块 `rgba(235,235,245,.42)`。
  static const Color darkThumbHover = Color.fromRGBO(235, 235, 245, 0.42);

  @override
  RawScrollbarState<AppScrollbar> createState() => _AppScrollbarState();
}

class _AppScrollbarState extends RawScrollbarState<AppScrollbar> {
  /// 鼠标是否**压在滑块上**（只在宽屏会置位）。
  bool _thumbHovered = false;

  @override
  Widget build(BuildContext context) {
    // 窄屏不改行为：连滚条都不包，交回系统默认。
    if (!isWideLayout(context)) {
      return widget.child;
    }
    return super.build(context);
  }

  /// 常态/悬停两档按明暗取规格值（`thumbColor` 覆写优先于规格常态色）。
  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    final isLight =
        (CupertinoTheme.maybeBrightnessOf(context) ??
            MediaQuery.platformBrightnessOf(context)) ==
        Brightness.light;
    final normal =
        widget.thumbColor ??
        (isLight ? AppScrollbar.lightThumb : AppScrollbar.darkThumb);
    final hover =
        widget.hoverThumbColor ??
        (isLight ? AppScrollbar.lightThumbHover : AppScrollbar.darkThumbHover);
    scrollbarPainter.color = _thumbHovered ? hover : normal;
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    // 只认「压在滑块上」：`isPointerOverThumb` 是精确命中（不是放宽的热区）。
    _setThumbHovered(isPointerOverThumb(event.position, event.kind));
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    _setThumbHovered(false);
  }

  void _setThumbHovered(bool value) {
    if (_thumbHovered == value) {
      return;
    }
    setState(() => _thumbHovered = value);
  }
}
