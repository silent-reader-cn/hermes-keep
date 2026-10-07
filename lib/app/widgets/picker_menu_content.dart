import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';
import '../theme/typography_tokens.dart';
import 'menu_metrics.dart';
import 'menu_row.dart';
import 'popover_dropdown.dart';

/// 搜索框整块高度（`margin 6` + 控件自然高 27 + `margin 6`）。
///
/// 单独成常量：它参与「列表可用高 = 该侧可用高 − 搜索框块 − 卡片边框」的算术，
/// 写死在 widget 里就没人能引用了。
const double kPickerSearchBarBlockHeight = 39.0;

/// 搜索框**显示门槛**：候选数 ≥ 本值才出搜索框（候选太少时搜索是噪声）。
///
/// 设计稿 `dialog-family-proposal.html` §2 的口径是「工作区 ≥6 个时出搜索」，
/// 本值按主人 2026-10-07 的要求放宽到 2 ——「两个选择器都要有搜索框」。
const double kPickerSearchMinCandidates = 2;

/// 菜单一行的描述子：**真实渲染高度** + 它的 widget。
///
/// 高度必须是真值：它同时喂给 [fitMenuListHeight] 做整行裁剪，一旦与实际渲染
/// 高度不符，切口就会落在行中间（半行）。
class PickerMenuRow {
  /// 构造一行。
  const PickerMenuRow(this.height, this.widget);

  /// 行高（真值）。
  final double height;

  /// 行 widget。
  final Widget widget;
}

/// 鼠标档单行行高（模型项 / 元操作 / 短枚举行）。
const double kMenuRowHeightMouse = 36.0;

/// 鼠标档双行行高（「名称 + 路径」的工作区项，设计稿「变体 A」）。
const double kMenuRowHeightMouseTwoLine = 46.0;

/// 触屏档行高（窄屏 44：`CupertinoListTile` / `CupertinoButton` 的最小交互尺寸）。
const double kMenuRowHeightTouch = 44.0;

/// 搜索无匹配提示行高（定高，供 `fitMenuListHeight` 精确裁剪）。
const double kPickerNoResultsRowHeight = 44.0;

/// 搜索无匹配时的提示行：次级色 + [kFontCaption]（注解档），定高定裁。
class MenuNoResultsRow extends StatelessWidget {
  /// 构造提示行。
  const MenuNoResultsRow({super.key, required this.label});

  /// 提示文案（调用方给 l10n，保持本组件不依赖本地化层）。
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kPickerNoResultsRowHeight,
    child: Center(
      child: Text(
        label,
        style: TextStyle(
          fontSize: kFontCaption,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: CupertinoColors.secondaryLabel,
          ),
        ),
      ),
    ),
  );
}

/// 单行菜单行：图标（可选）+ 文案 + 选中勾。
///
/// 选择器（输入栏 chip）与上下文弹层内的下拉**共用这一个** —— 行高、内边距、
/// 图标列宽度、选中态（中性底 + 蓝字 w600 + 右勾，无左竖条）都在这里定死，
/// 两处不再各写一份，也就不会再出现「一边 44 一边 36」「一边有图标一边没有」。
class MenuRowSingle extends StatelessWidget {
  /// 构造一行单行菜单项。
  const MenuRowSingle({
    super.key,
    required this.height,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.fontSize = kFontNavItem,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.iconBoxWidth = 16,
    this.iconGap = 10,
  });

  /// 行高（鼠标档 36 / 触屏档 44 / 双行档 46）。
  final double height;

  /// 行文案。
  final String label;

  /// 是否当前选中项。
  final bool selected;

  /// 点选落地。
  final VoidCallback onTap;

  /// 可选前置图标（不传则无图标列，文字左缘即 [padding] 起点）。
  final IconData? icon;

  /// 文案字号（默认 [kFontNavItem]）。
  final double fontSize;

  /// 左右内边距（鼠标档 12 / 触屏档 8）。
  final EdgeInsetsGeometry padding;

  /// 图标盒宽（决定文字左缘：盒宽 + [iconGap]）。
  final double iconBoxWidth;

  /// 图标与文案的间距。
  final double iconGap;

  @override
  Widget build(BuildContext context) {
    final accent = LightSurfaces.resolve(
      context,
      statusBlueText.resolveFrom(context),
      dark: CupertinoColors.activeBlue,
    );
    return MenuRow(
      height: height,
      icon: icon,
      iconBoxWidth: iconBoxWidth,
      iconGap: iconGap,
      padding: padding,
      selected: selected,
      onTap: onTap,
      trailing: selected
          ? Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.check_mark, size: 16, color: accent),
            )
          : null,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected
              ? LightSurfaces.resolve(
                  context,
                  LightSurfaces.selectionForeground,
                  dark: CupertinoColors.activeBlue,
                )
              : CupertinoColors.label.resolveFrom(context),
        ),
      ),
    );
  }
}

/// 双行菜单行：图标 + 名称（主行）+ 路径（副行，灰色）+ 选中勾。
///
/// 名称与路径是**两个独立文本节点**（不是 `名称 (路径)` 拼接串），路径因此不会
/// 被省略号连坐吃掉；两行左对齐、各自超长省略。副行字号比主行小一档，是为了
/// 让「主行是名字、副行是注解」的层级立住（实测见 HERMES.md 2026-10-07 记录）。
class MenuRowTwoLine extends StatelessWidget {
  /// 构造一行双行菜单项。
  const MenuRowTwoLine({
    super.key,
    required this.height,
    required this.icon,
    required this.name,
    required this.path,
    required this.selected,
    required this.onTap,
    this.nameFontSize = kFontLabel,
    this.pathFontSize = kFontMicro,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.iconBoxWidth = 16,
    this.iconGap = 10,
  });

  /// 行高（双行档 46）。
  final double height;

  /// 前置图标。
  final IconData icon;

  /// 主行：名称（无名时调用方回落为路径）。
  final String name;

  /// 副行：路径。
  final String path;

  /// 是否当前选中项。
  final bool selected;

  /// 点选落地。
  final VoidCallback onTap;

  /// 主行字号。
  final double nameFontSize;

  /// 副行字号（设计稿那行是 11.5px 等宽 Menlo；实现无等宽字族，MiSans 同 px
  /// 字面更大，故取 11 让**渲染后的墨高**与设计稿对齐）。
  final double pathFontSize;

  /// 左右内边距。
  final EdgeInsetsGeometry padding;

  /// 图标盒宽。
  final double iconBoxWidth;

  /// 图标与内容的间距。
  final double iconGap;

  @override
  Widget build(BuildContext context) {
    final accent = LightSurfaces.resolve(
      context,
      LightSurfaces.selectionForeground,
      dark: CupertinoColors.activeBlue,
    );
    final nameColor = selected
        ? accent
        : CupertinoColors.label.resolveFrom(context);
    final pathColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    return MenuRow(
      height: height,
      icon: icon,
      iconBoxWidth: iconBoxWidth,
      iconGap: iconGap,
      padding: padding,
      selected: selected,
      onTap: onTap,
      trailing: selected
          ? Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.check_mark, size: 16, color: accent),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: nameFontSize,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: nameColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: pathFontSize, color: pathColor),
          ),
        ],
      ),
    );
  }
}

/// 下拉/选择器菜单**内容**：卡片内的搜索框（可选）+ 按行边界裁剪的可滚动列表。
///
/// 两处共用同一份（输入栏 chip 选择器 + 上下文弹层内的三个下拉），差异只有三处
/// 参数：搜索框占位文案（null = 不出搜索框）、候选清单（喂 [buildRows]）、以及
/// 由调用方决定的各档行高。
///
/// **搜索态是本控件自己的局部状态**：弹层挂在 `OverlayEntry` 上，外层 State 的
/// `setState` 并不会重建已插入的 entry，输入过滤必须由弹层内容自己持有（否则
/// 打字时列表纹丝不动）。
///
/// 高度：可用高来自 `PopoverMenuShell`（该侧真实可用），按行边界裁剪 ——
/// 内容放得下就全放，放不下才滚动，且切口永远落在两行之间。
class PickerMenuContent extends StatefulWidget {
  /// 构造菜单内容。
  const PickerMenuContent({
    super.key,
    required this.available,
    required this.searchPlaceholder,
    required this.searchFieldKey,
    required this.buildRows,
    this.width,
  });

  /// 该侧真实可用高度（来自 `PopoverMenuShell`）。
  final double available;

  /// 搜索框占位文案；为 null 表示不显示搜索框（窄屏 / 候选不足 / 短枚举菜单）。
  final String? searchPlaceholder;

  /// 搜索框的测试锚点（守卫与探针按 key 定位）；不显示搜索框时可为 null。
  final Key? searchFieldKey;

  /// 卡片宽度；null 时按视口取 `popoverDropdownWidthFor`（宽屏 300 / 窄屏 228）。
  final double? width;

  /// 按当前查询串构建行（含「无匹配」提示行；查询串已 trim）。
  final List<PickerMenuRow> Function(BuildContext context, String query)
  buildRows;

  @override
  State<PickerMenuContent> createState() => _PickerMenuContentState();
}

class _PickerMenuContentState extends State<PickerMenuContent> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    if (value == _query) return;
    setState(() => _query = value);
  }

  @override
  Widget build(BuildContext context) {
    final searchBlock = widget.searchPlaceholder == null
        ? 0.0
        : kPickerSearchBarBlockHeight;
    final rows = widget.buildRows(context, _query.trim());
    // 列表的高度预算 = 该侧可用高 − 搜索框块 − 卡片边框（1px ×2）。
    //
    // 为什么还要减 chrome：`fitMenuHeight` 的返回值**已含**卡片边框（它的口径是
    // 「卡片高」），而卡片自身在内容之外又实打实地叠了两样东西（搜索框块 + 1px
    // 边框 ×2）。不减就会在最紧的那一档超出 2px，被外层 `ConstrainedBox` 裁出
    // 一个溢出条。
    final listBudget = math.max(
      0.0,
      widget.available - searchBlock - kPopoverMenuCardChrome,
    );
    // 列表内容上限一律取 `fitMenuListHeight`（= fitMenuHeight − 卡片边框）：
    // 这里要的是「列表可见高」而不是「卡片高」。不减边框的话切口会停在边界外
    // 2px 处，露出下一行 2px 的边（实测 1280×300 下第 5 个工作区就露出 2px 一条）
    // —— 判据是「绝不出现半行」。
    final listMax = fitMenuListHeight(
      rowHeights: [for (final row in rows) row.height],
      available: listBudget,
    );

    return PopoverDropdownCard(
      width: widget.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.searchPlaceholder != null) _searchBlock(context),
          Flexible(
            // FlexFit.loose + 有界上限：列表按内容撑（内容驱动、不留白），
            // 上限之外滚动。外层若比预算更紧，也只是滚得更早，不会溢出。
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: listMax),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final row in rows) row.widget],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索框块（设计稿 `.searchbar`：`margin:6px 10px` / `padding:6px 9px` /
  /// 圆角 8 / 浅色底 `#F2F2F2` = [LightSurfaces.page]、暗色 `#2C2C2E`，
  /// 0.5 描边浅 [LightSurfaces.cardBorder] / 暗 [CupertinoColors.separator]）。
  ///
  /// 字号取 [kFontCaption]：搜索框里的字是**一段提示语 / 一个查询词**，不是表单
  /// 字段名，且设计稿的 12.5 离本档（12）最近；[kFontLabel]（13）是字段名的档，
  /// 用在这里会整体大一档、压过占位的从属地位。
  ///
  /// 清空按钮用控件自带（[CupertinoSearchTextField] 的 xmark 后缀）。
  Widget _searchBlock(BuildContext context) {
    final fill = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: const Color(0xFF2C2C2E),
    );
    final stroke = LightSurfaces.resolve(
      context,
      LightSurfaces.cardBorder,
      dark: CupertinoColors.separator,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: CupertinoSearchTextField(
        key: widget.searchFieldKey,
        controller: _queryController,
        placeholder: widget.searchPlaceholder,
        itemSize: 14,
        // 设计稿的 `padding:6px 9px`：文字与前后图标各留 6 的纵向、9 的横向
        // （前缀外缩 6 + 文字内缩 6 ≈ 9 的观感，与 `session_list_page` 同法）。
        padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 6),
        prefixInsets: const EdgeInsetsDirectional.fromSTEB(6, 6, 0, 6),
        suffixInsets: const EdgeInsetsDirectional.fromSTEB(0, 6, 6, 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: stroke, width: 0.5),
        ),
        style: TextStyle(
          fontSize: kFontCaption,
          color: CupertinoColors.label.resolveFrom(context),
        ),
        placeholderStyle: TextStyle(
          fontSize: kFontCaption,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.placeholder,
            dark: CupertinoColors.placeholderText,
          ),
        ),
        itemColor: LightSurfaces.resolve(
          context,
          LightSurfaces.textSecondary,
          dark: CupertinoColors.secondaryLabel,
        ),
        onChanged: _onQueryChanged,
      ),
    );
  }
}
