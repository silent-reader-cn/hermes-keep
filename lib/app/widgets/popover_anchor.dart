import 'package:flutter/cupertino.dart';

/// 弹层锚点：按 [key] 在 [context] 子树里定位元素，返回其 **overlay 坐标系**矩形。
///
/// ## 为什么锚点不能用 `GlobalKey`
/// Cupertino 的导航栏在路由转场时走 **Hero 飞行**：`_NavigationBarComponentsTransition`
/// 会直接重建用户传进 `leading` / `middle` / `trailing` 的 widget（它取的是
/// `trailingKey.currentWidget.child`，框架注释明写「…still present in the widget tree
/// during the hero transitions, it would cause global key duplications」）。于是放在
/// 这些槽位里的 **任何 `GlobalKey`** 都会在同一帧被「静态顶栏 + 飞行穿梭层」两处 build：
///
/// - debug：撞 `BuildOwner._debugVerifyGlobalKeyReservation` →
///   「Multiple widgets used the same GlobalKey」；
/// - release：`Element._retakeInactiveElement` 会把元素从原处
///   `forgetChild` + `deactivateChild` **抽走**交给穿梭层，飞行结束穿梭层销毁 ⇒
///   挂在 GlobalKey 下的按钮**连元素一起消失**，而同一行里没挂 GlobalKey 的兄弟按钮
///   还留在原处（用户看到的就是「某个图标有时不见了、旁边的还在」）。
///
/// `ValueKey` 不参与 GlobalKey 的登记与抢占，天然免疫这一类问题；弹层定位改为
/// **按 key 现算矩形**（本函数）即可，行为与 `GlobalKey.currentContext` 完全等价 ——
/// 唯一的差别是「key 必须唯一」，重复 key 会让锚点绑到第一个匹配项，因此调用方应保证
/// 锚点 key 在子树内唯一（本仓锚点一律用 `ValueKey('xxx')` 常量）。
///
/// 返回 `null` 表示未找到元素或元素已卸载 —— 调用方应放弃展示弹层（而不是退回屏幕原点，
/// 那会让弹层诡异地飘到左上角）。
Rect? resolvePopoverAnchorRect(
  BuildContext context,
  OverlayState overlay,
  Key key,
) {
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  if (overlayBox == null) return null;
  if (context is! Element) return null;

  Element? target;
  void visit(Element element) {
    if (target != null) return;
    if (element.widget.key == key) {
      target = element;
      return;
    }
    element.visitChildren(visit);
  }

  visit(context);
  final box = target?.renderObject as RenderBox?;
  if (box == null || !box.attached) return null;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  return Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height);
}
