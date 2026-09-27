import 'package:flutter/cupertino.dart';

import '../theme/layout_tokens.dart';
import '../theme/light_surfaces.dart';

/// G3 图标钮悬停圆底（直径 [kIconButtonHoverSize] = 28 的圆）：鼠标压上去时
/// 在图标/按钮**底下**垫一枚浅灰圆底。
///
/// 为什么是圆不是方：与 iOS 工具条语言一致（设计稿 §G3 明确「图标钮 hover 给
/// 圆底（不是方形）」）。
///
/// 为什么用 [CustomPaint] 的 painter、而不是 `Stack` + `Positioned`：
/// `Stack` 默认 `StackFit.loose`，会把父级给的**紧约束放开** —— 被它包住的
/// `CupertinoButton` 会从「铺满 `Expanded` 槽位」缩回自身最小宽 40，那等于顺手
/// 改了布局（命中区也一起缩）。[CustomPaint] 是 proxy box：约束原样透传、自身
/// 尺寸 = child 尺寸，painter 只在 child **底下**画一层，布局零影响。
///
/// 两种用法（同一个组件）：
/// 1. **自接管**（默认，[hovered] 留 null）：包住整颗图标钮 —— 悬停命中区 =
///    整颗按钮，圆底居中（图标在按钮里居中，所以圆心正落在图标上）。
/// 2. **外部接管**（[hovered] 非 null）：包住图标本身，悬停由外层（行级
///    `MouseRegion`）给 —— 圆底精确垫在图标后面：28 > 图标盒，四周对称溢出，
///    行高 28 时上下正好齐平（`_ToolRow` 走这条）。
///    此模式不挂 `MouseRegion`、不设光标，光标语义归外层。
///
/// 选中态优先（[selected]）：选中时**不画圆底** —— 否则 16% 的圆底会叠在选中底
/// 上，读起来像「更深的选中」，与 L2「中性灰底 + 蓝前景」的语义打架。
///
/// 颜色：`LightSurfaces.selectedSurface`（`rgba(120,120,128,.16)`）。设计稿里
/// L2 选中底与 G3 图标钮 hover 圆底给的是**同一个值**，故直接复用该令牌而不另立
/// 一个同值色（两处一旦漂移就是两种灰）。暗色同值叠在暗底上（设计稿口径：
/// 「同级取值，明暗分别设计」在此项上正好同值）。
///
/// 窄屏（`width < kWideBreakpoint`）：**原样透传** `child` —— 不挂 `MouseRegion`、
/// 不挂 painter，手机端逐像素不变（G3 只在桌面成立）。
class IconHoverDisk extends StatefulWidget {
  /// 创建一个悬停圆底。
  ///
  /// [hovered] 传 null（默认）= 自己接管悬停；传非 null = 悬停由外部接管。
  const IconHoverDisk({
    super.key,
    required this.child,
    this.size = kIconButtonHoverSize,
    this.selected = false,
    this.hovered,
  });

  /// 圆底要垫在其下的内容（图标钮，或单独一枚图标）。
  final Widget child;

  /// 圆底直径，默认 [kIconButtonHoverSize]（28）。
  final double size;

  /// 是否处于选中态；选中优先 —— 不叠圆底。
  final bool selected;

  /// 外部接管的悬停态；null = 由本组件自己包 `MouseRegion` 判定。
  final bool? hovered;

  @override
  State<IconHoverDisk> createState() => _IconHoverDiskState();
}

class _IconHoverDiskState extends State<IconHoverDisk> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) {
      return widget.child;
    }

    final external = widget.hovered;
    if (external != null) {
      return _withDisk(external);
    }
    return MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: _withDisk(_hovering),
    );
  }

  /// 按「悬停 + 非选中」决定是否垫圆底；不显示时连 painter 都不挂。
  Widget _withDisk(bool hovering) {
    final visible = hovering && !widget.selected;
    return CustomPaint(
      // 固定 key：测试/工装按它定位「圆底是否在」并读 painter（见
      // `kIconHoverDiskPaintKey` 的说明）。
      key: kIconHoverDiskPaintKey,
      painter: visible ? _IconHoverDiskPainter(diameter: widget.size) : null,
      child: widget.child,
    );
  }

  void _setHovering(bool value) {
    if (_hovering == value) {
      return;
    }
    setState(() => _hovering = value);
  }
}

/// 圆底画布（[CustomPaint]）的 key。
///
/// 圆底「在不在」全靠这个 [CustomPaint] 的 `painter` 是否为 null —— 测试与截图
/// 工装按它定位（`find.descendant(of: row, matching: find.byKey(kIconHoverDiskPaintKey))`），
/// 免得靠 `find.byType(CustomPaint)` 撞上页面里别的 CustomPaint。
const Key kIconHoverDiskPaintKey = ValueKey('icon-hover-disk-paint');

/// 圆底 painter：在画布正中画一枚直径 [diameter] 的实心圆（色同 L2 选中底）。
class _IconHoverDiskPainter extends CustomPainter {
  const _IconHoverDiskPainter({required this.diameter});

  final double diameter;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      diameter / 2,
      Paint()..color = LightSurfaces.selectedSurface,
    );
  }

  @override
  bool shouldRepaint(_IconHoverDiskPainter oldDelegate) =>
      oldDelegate.diameter != diameter;
}
