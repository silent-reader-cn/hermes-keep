import 'dart:math' as math;

/// 弹层菜单的高度上限（420，与 `showAdaptivePopover` 的默认 `maxHeight` 一致）。
///
/// 再高就会遮住大半屏；超出部分一律交给滚动兜底。
const double kPopoverMenuMaxHeight = 420.0;

/// 菜单卡片的固定开销（`PopoverDropdownCard` / `_PopoverCard` 的 1px 边框 ×2）。
const double kPopoverMenuCardChrome = 2.0;

/// 菜单可见高度：**内容放得下就全放（不裁），放不下才滚动，且裁在行边界上**。
///
/// [rowHeights] 为当前（可能已被搜索过滤后的）各行的真实高度，[chrome] 为卡片
/// 边框等固定开销，[available] 为该侧真实可用高度。
///
/// 为什么必须按行边界裁：弹层是 `SingleChildScrollView`，直接给一个拍脑袋的
/// 上限（历史实现是硬编码 200）会在**行中间**切断 —— 用户看到半行文字，读起来
/// 像渲染坏了，也不像「还有更多」。按整行取最大前缀后，切口永远落在两行之间。
///
/// 连一行都放不下时返回 [available]（由外层有界约束兜底），不返回零 —— 否则
/// 菜单会塌成一条缝。
double fitMenuHeight({
  required List<double> rowHeights,
  required double available,
  double chrome = kPopoverMenuCardChrome,
}) {
  if (rowHeights.isEmpty) return math.min(chrome, available);
  final total = chrome + rowHeights.fold<double>(0, (sum, h) => sum + h);
  if (total <= available) return total;
  var height = chrome;
  for (final row in rowHeights) {
    if (height + row > available) break;
    height += row;
  }
  if (height == chrome) return math.min(available, chrome + rowHeights.first);
  return height;
}

/// 卡片内**滚动列表**的可见高度：等于 [fitMenuHeight] 减去卡片自身边框开销。
///
/// 之所以单列一个入口、而不是让调用方各写 `fitMenuHeight(...) - 2`：
/// [fitMenuHeight] 的口径是**卡片高**（含边框），把它直接当作列表上限会让
/// 卡片比可用高度高出 2pt，被外层夹回后**下一行露出 2pt**（实测两处各踩一次）。
/// 凡「卡片（有边框）+ 可滚动列表」的结构，列表上限一律取本函数。
double fitMenuListHeight({
  required List<double> rowHeights,
  required double available,
}) => math.max(
  0,
  fitMenuHeight(rowHeights: rowHeights, available: available) -
      kPopoverMenuCardChrome,
);
