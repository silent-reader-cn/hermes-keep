import 'package:flutter/cupertino.dart';

import '../shell/adaptive_shell.dart';
import 'large_title_sliver_header.dart';
import 'narrow_navigation_dropdown.dart';

/// 宽屏自动收敛的 Cupertino 导航栏（Sliver 版）。
///
/// - 窄屏（width < 900，手机）：自绘大标题头部（[LargeTitleSliverHeaderDelegate]，
///   几何对齐会话列表页 `SessionListHeaderDelegate` 基准），快捷导航下拉按钮
///   （[NarrowNavigationDropdownButton]）紧贴大标题右侧并随展开/收起平滑移动
///   （TASK sep03：不再挤在右上角 trailing 区）；#128 起大标题本身亦可点击，
///   与点击 ▾ 打开同一个下拉菜单；
/// - 宽屏（width >= 900，桌面双栏）：收敛为 44pt 紧凑导航条
///   （`CupertinoNavigationBar`，不可随滚动收起），与左侧侧栏顶部的
///   [SidebarUtilityToolbar]（44px）高度对齐，消除双栏下内容区 Header
///   与侧栏工具条的高度参差。
///
/// 注意：`CupertinoSliverNavigationBar` 断言 largeTitle 不可为 null
/// （无大标题内容即崩溃），且其 largeTitle 行无法在标题旁插入子组件，
/// 因此窄屏改走自绘 delegate；宽屏固定条亦不能与其共用。
class AdaptiveSliverNavigationBar extends StatefulWidget {
  const AdaptiveSliverNavigationBar({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.padding,
    this.bottom,
    this.showMiddleOnNarrow = false,
    this.showNarrowNavigationDropdown = true,
    this.onTitleDoubleTap,
    this.alwaysCollapsed = false,
  });

  /// 大标题 / 收起态中标题的共用文案。
  final String title;

  /// 导航栏左侧按钮（返回等）。
  final Widget? leading;

  /// 导航栏右侧按钮列表。
  final Widget? trailing;

  /// 内容横向内边距（仅窄屏大标题模式生效，宽屏固定条无此参数）。
  final EdgeInsetsDirectional? padding;

  /// 固定在导航栏底部的小部件（操作横幅等），收起/展开态均可见。
  final PreferredSizeWidget? bottom;

  /// 窄屏下是否同时在 44pt 条显示中标题。
  ///
  /// 少数页面原本即「大标题 + 收起态 middle」双模式（workspace 系），
  /// 传 `true` 保持窄屏行为不变。
  final bool showMiddleOnNarrow;

  /// 窄屏下是否在大标题右侧追加快捷导航下拉按钮（TASK W3-2）。
  ///
  /// 默认为 `true`；可显式传 `false` 关闭。关闭时大标题点击亦不打开下拉
  /// （无 ▾ 可对应，见 #128）。
  final bool showNarrowNavigationDropdown;

  /// 双击标题回调（例如回顶：scrollController.animateTo(0, ...)）。
  final VoidCallback? onTitleDoubleTap;

  /// 强制使用折叠态紧凑导航条（44pt，不随滚动展开大标题）。
  ///
  /// 文档预览等「标题即文件名、可能超长」的页面用：长文本由
  /// [CupertinoNavigationBar] 的 middle 在 leading/trailing 之间截断，
  /// 不会像大标题模式那样无界绘制压住两侧按钮。
  final bool alwaysCollapsed;

  @override
  State<AdaptiveSliverNavigationBar> createState() =>
      _AdaptiveSliverNavigationBarState();
}

class _AdaptiveSliverNavigationBarState
    extends State<AdaptiveSliverNavigationBar> {
  /// 窄屏「点击大标题 = 点击 ▾」的请求通道（#128）。
  ///
  /// 标题由 header delegate 自绘，触达不到 [NarrowNavigationDropdownButton]
  /// 的内部状态，故由本 State 持有通道：标题 onTap → 通道被通知 → ▾ 打开同一个
  /// 下拉菜单（锚点仍是 ▾ 自身，弹层位置与直接点击一致）。
  final ValueNotifier<int> _narrowNavOpenSignal = ValueNotifier<int>(0);

  @override
  void dispose() {
    _narrowNavOpenSignal.dispose();
    super.dispose();
  }

  /// 标题点击 → 请求打开下拉。
  ///
  /// 以实例方法 tear-off 传给 delegate：同一 State 的 tear-off 相等，
  /// 不会让 [SliverPersistentHeaderDelegate.shouldRebuild] 因闭包身份
  /// 每帧判真而反复重建头部。
  void _requestNarrowNavMenu() {
    _narrowNavOpenSignal.value = _narrowNavOpenSignal.value + 1;
  }

  @override
  Widget build(BuildContext context) {
    Widget buildTitle(String text) {
      final textWidget = Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      if (widget.onTitleDoubleTap != null) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onTitleDoubleTap,
          child: textWidget,
        );
      }
      return textWidget;
    }

    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    final effectiveLeading = widget.leading;

    if (isWide || widget.alwaysCollapsed) {
      // 桌面宽屏：44pt 固定紧凑导航条（SliverNavigationBar 不允许
      // largeTitle 为 null，改用 CupertinoNavigationBar）。
      // pinned：与窄屏大标题头部同理，滚动后标题与返回/操作按钮钉在顶部，
      // 内容从其下方滑过（此前 SliverToBoxAdapter 会随滚动流走）。
      return SliverPersistentHeader(
        pinned: true,
        delegate: _FixedNavBarSliverDelegate(
          navBar: CupertinoNavigationBar(
            leading: effectiveLeading,
            trailing: widget.trailing,
            middle: buildTitle(widget.title),
            bottom: widget.bottom,
          ),
          topPadding: MediaQuery.paddingOf(context).top,
        ),
      );
    }

    // 窄屏：自绘大标题头部，▾ 紧贴大标题右侧（与会话列表页基准一致）。
    final showDropdown = widget.showNarrowNavigationDropdown;
    return SliverPersistentHeader(
      pinned: true,
      delegate: LargeTitleSliverHeaderDelegate(
        title: widget.title,
        leading: effectiveLeading,
        trailing: widget.trailing,
        titleTrailing: showDropdown
            ? NarrowNavigationDropdownButton(
                openSignal: _narrowNavOpenSignal,
              )
            : null,
        // #128：窄屏点击大标题 / 收起态中标题 = 点击 ▾（仅在确有 ▾ 时接线；
        // 与 onTitleDoubleTap 共存时单击等双击判定窗口，全页面行为一致）。
        onTitleTap: showDropdown ? _requestNarrowNavMenu : null,
        showCollapsedTitle: widget.showMiddleOnNarrow,
        topPadding: MediaQuery.paddingOf(context).top,
        brightness: CupertinoTheme.of(context).brightness ?? Brightness.light,
        padding: widget.padding,
        bottom: widget.bottom,
        onTitleDoubleTap: widget.onTitleDoubleTap,
        portrait: MediaQuery.orientationOf(context) == Orientation.portrait,
      ),
    );
  }
}

/// 宽屏紧凑导航条的 pinned delegate：把 [CupertinoNavigationBar] 的总高
/// （44pt + bottom 高 + 顶部安全区）如实报告给 sliver，保证不溢出且常驻顶部。
class _FixedNavBarSliverDelegate extends SliverPersistentHeaderDelegate {
  const _FixedNavBarSliverDelegate({required this.navBar, this.topPadding = 0});

  final CupertinoNavigationBar navBar;
  final double topPadding;

  static const double _kNavBarPersistentHeight = 44.0;

  double get _bottomHeight => navBar.bottom?.preferredSize.height ?? 0.0;

  double get _extent => _kNavBarPersistentHeight + _bottomHeight + topPadding;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  bool shouldRebuild(covariant _FixedNavBarSliverDelegate oldDelegate) =>
      oldDelegate.navBar != navBar || oldDelegate.topPadding != topPadding;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => navBar;
}
