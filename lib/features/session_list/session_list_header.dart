import 'package:flutter/cupertino.dart';

/// 会话列表页头部（替换 `CupertinoSliverNavigationBar` 的大标题模式）。
///
/// Flutter 的 `CupertinoSliverNavigationBar` 在展开大标题时，`trailing`
/// 按钮固定在顶部 persistent 栏（44pt），大标题在其下方独立展开——视觉上
/// 会话列表顶部导航栏 Delegate（TASK W3-2 窄屏大标题 + 导航下拉 + 桌面紧凑单行）。
///
/// 支持两种显示模式：
/// - **移动端大标题模式（默认）**：展开时呈现 34pt 大标题，紧贴标题右侧支持渲染
///   [titleTrailing]（如窄屏快捷导航下拉按钮 ▾，间距 4pt），右侧为操作按钮 [actions]；
///   滚动时大标题平滑淡出过渡为 17pt 居左收起态中标题，[titleTrailing] 与 [actions]
///   沿垂直中线（[buttonCenterY]）同轴平滑上升至持久导航栏。
/// - **桌面紧凑单行模式（`compactHeader == true`）**：彻底移除「会话」大标题，将
///   搜索框（[searchField]）与操作按钮（[actions]）并入同一行 pinned 头部，节省垂直空间。
class SessionListHeaderDelegate extends SliverPersistentHeaderDelegate {
  const SessionListHeaderDelegate({
    required this.title,
    this.titleTrailing,
    this.actions = const [],
    this.topPadding = 0,
    this.brightness = Brightness.light,
    this.compactHeader = false,
    this.searchField,
    this.onTitleTap,
  });

  /// 顶部安全区高度（状态栏），由页面在 build 时以
  /// `MediaQuery.paddingOf(context).top` 传入。
  final double topPadding;

  /// 大标题 / 收起态中标题共用文案（移动端模式使用）。
  final String title;

  /// 紧贴标题右侧的尾随组件（如窄屏快捷导航下拉按钮 ▾）。
  ///
  /// 仅在非紧凑模式（大标题模式）下渲染，紧随标题右侧（间距 4pt），
  /// 随滚动参与 [buttonCenterY] 与文本宽度的展开/收起过渡动画。
  final Widget? titleTrailing;

  /// 右侧操作按钮列表（设置 / 筛选 / 新建会话等）。
  final List<Widget> actions;

  /// 当前主题亮度（浅/深）。参与 [shouldRebuild] 比较：主题切换时
  /// SliverPersistentHeader 不会因 InheritedWidget 变化自动重建，不参与
  /// 比较会导致标题颜色冻结在旧主题（桌面端浅深切换不跟色 bug）。
  final Brightness brightness;

  /// 紧凑头部模式：桌面双栏侧栏复用时传 `true`。
  ///
  /// 彻底移除「会话」大标题，将搜索框与操作按钮（筛选/加号）整合到单行 pinned 头部；
  /// 手机端单栈保持默认 `false`（大标题模式）。
  final bool compactHeader;

  /// 紧凑模式下的搜索框组件（桌面端并入单行头部）。
  final Widget? searchField;

  /// 单击标题回调（#128 窄屏「点击大标题 = 点击右侧 ▾」）。
  ///
  /// 仅在非紧凑模式且确有 [titleTrailing]（▾）时由页面接线；为 `null` 时
  /// 标题不可点（行为与改动前一致）。
  final VoidCallback? onTitleTap;

  /// 收起态导航栏高度（对齐 iOS `_kNavBarPersistentHeight`）。
  static const double barHeight = 44.0;

  /// 展开态大标题区高度（对齐系统 `_kNavBarLargeTitleHeightExtension`）。
  static const double largeTitleHeight = 52.0;

  /// 紧凑单行头部高度（对齐桌面侧栏搜索行高度）。
  static const double compactBarHeight = 50.0;

  /// 展开态大标题文字顶部距状态栏的间距（宽敞模式）。
  ///
  /// 对齐系统 `CupertinoSliverNavigationBar` 展开态大标题的视觉位置：
  /// - 2026-08-26 窄屏探针（Ahem 默认字体）实测系统 34pt 大标题顶距 = 54px，
  ///   本组件 49px → 修正为 54（49→54）。
  /// - 2026-08-29 真 MiSans + 应用主题探针（真机同度量，见
  ///   `test/features/session_list/session_vs_tasks_title_gap_probe_test.dart`）
  ///   实测：MiSans 34pt 行高 = 45px → 系统组件大标题顶 = 88 - 45 = 43px，
  ///   会话页 54px 高出 11px（主人实机观测「会话页空白更高」方向吻合）
  ///   → 反向修正 54→43（todo #24，主人确认后落地）。
  /// 仅手机端单栈使用；紧凑模式不受影响。
  static const double _spaciousLargeTitleTopGap = 43.0;

  /// 大标题文字行盒高度（MiSans 34pt 实测渲染高度，探针数据）。
  ///
  /// 收起态中标题（17pt）与展开态大标题的文字布局都以此类字体度量
  /// 为基准计算按钮中心，保证按钮与文字垂直居中而非依赖估算偏移。
  static const double _largeTitleLineHeight = 39.0;

  /// 按钮视觉半高（按钮 44×44 点击区，中心定位）。
  static const double _buttonHalfSize = 22.0;

  @override
  double get minExtent =>
      topPadding + (compactHeader ? compactBarHeight : barHeight);

  @override
  double get maxExtent =>
      topPadding +
      (compactHeader ? compactBarHeight : barHeight + largeTitleHeight);

  @override
  bool shouldRebuild(SessionListHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.titleTrailing != titleTrailing ||
      oldDelegate.actions != actions ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.brightness != brightness ||
      oldDelegate.compactHeader != compactHeader ||
      oldDelegate.searchField != searchField ||
      oldDelegate.onTitleTap != onTitleTap;

  /// 收起态中标题（17pt 居左，随展开进度淡出）。
  Widget _collapsedTitleLabel(double collapsed, Color labelColor) {
    return Opacity(
      opacity: collapsed,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: labelColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 展开态大标题（34pt 居左，随展开进度淡入）。
  Widget _largeTitleLabel(double progress, Color labelColor) {
    return Opacity(
      opacity: progress,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: labelColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 展开进度：1 = 完全展开（大标题可见），0 = 完全收起。
  double _expandProgress(double shrinkOffset) {
    final range = maxExtent - minExtent;
    if (range <= 0) return 0.0;
    return ((maxExtent - shrinkOffset) - minExtent) / range;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = CupertinoTheme.of(context);
    final barColor = CupertinoDynamicColor.resolve(
      theme.barBackgroundColor,
      context,
    );

    // 桌面端紧凑单行模式：搜索框与操作按钮（筛选/加号）同一行，不渲染大标题。
    if (compactHeader) {
      return Stack(
        key: const ValueKey('session-list-header'),
        fit: StackFit.expand,
        children: [
          ColoredBox(color: barColor),
          Padding(
            padding: EdgeInsets.only(top: topPadding, left: 12, right: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (searchField != null)
                  Expanded(child: searchField!)
                else
                  const Spacer(),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  ...actions,
                ],
              ],
            ),
          ),
        ],
      );
    }

    final progress = _expandProgress(shrinkOffset).clamp(0.0, 1.0);
    final collapsed = 1.0 - progress;

    final labelColor = CupertinoDynamicColor.resolve(
      theme.textTheme.textStyle.color ?? CupertinoColors.label,
      context,
    );

    // 标题几何：展开态大标题从状态栏下方 49pt 处开始（与系统导航栏大标题
    // 位置一致），收起态中标题位于导航栏中线。两者起点同为 left 20，
    // 滚动时同轴缩放不跳位。
    // 大标题文字行盒中心（展开态，按钮对齐基准）。
    final largeTitleCenterY =
        topPadding + _spaciousLargeTitleTopGap + _largeTitleLineHeight / 2;
    // 中标题文字中心（收起态）。
    final collapsedTitleCenterY = topPadding + barHeight / 2;
    // 按钮中心：展开态与大标题文字行盒中心对齐（垂直居中），收起态对齐
    // 导航栏中线。
    final expandedButtonCenterY = largeTitleCenterY;
    final collapsedButtonCenterY = collapsedTitleCenterY;
    final buttonCenterY =
        collapsedButtonCenterY +
        (expandedButtonCenterY - collapsedButtonCenterY) * progress;
    // 大标题垂直位置：展开到底部附近（top 定位，随滚动上移淡出）。
    final largeTitleTop =
        topPadding +
        _spaciousLargeTitleTopGap -
        4 * collapsed -
        4 * (1 - progress);

    double largeTitleWidth = 0.0;
    double collapsedTitleWidth = 0.0;
    if (titleTrailing != null) {
      final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
      final textScaler =
          MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;

      final largePainter = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      largeTitleWidth = largePainter.width;

      final collapsedPainter = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      collapsedTitleWidth = collapsedPainter.width;
    }

    final trailingLeft =
        20.0 +
        (collapsedTitleWidth +
            (largeTitleWidth - collapsedTitleWidth) * progress) +
        4.0;
    final trailingTop = buttonCenterY - _buttonHalfSize;

    return Stack(
      key: const ValueKey('session-list-header'),
      fit: StackFit.expand,
      children: [
        // 背景：固定不透明主题 bar 底色（不随滚动变灰/透明）。
        ColoredBox(color: barColor),
        // 收起态中标题（左对齐）。
        // #128：点击标题 = 点击右侧 ▾（打开快捷导航下拉）；未接线时保持原样
        // （不加 GestureDetector，命中行为零变化）。
        Positioned(
          left: 20,
          top: collapsedTitleCenterY - 12,
          child: onTitleTap == null
              ? _collapsedTitleLabel(collapsed, labelColor)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTitleTap,
                  child: _collapsedTitleLabel(collapsed, labelColor),
                ),
        ),
        // 大标题（左对齐，紧贴状态栏，随滚动上移淡出）。
        Positioned(
          left: 20,
          top: largeTitleTop,
          child: onTitleTap == null
              ? _largeTitleLabel(progress, labelColor)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTitleTap,
                  child: _largeTitleLabel(progress, labelColor),
                ),
        ),
        // 紧贴标题右侧的尾随组件（如窄屏快捷导航下拉按钮 ▾），随展开/收起平滑过渡。
        if (titleTrailing != null)
          Positioned(
            left: trailingLeft,
            top: trailingTop,
            child: titleTrailing!,
          ),
        // 右上角操作按钮：展开时与大标题同行，收起时平滑升至导航栏。
        if (actions.isNotEmpty)
          Positioned(
            right: 4,
            top: buttonCenterY - _buttonHalfSize,
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
      ],
    );
  }
}
