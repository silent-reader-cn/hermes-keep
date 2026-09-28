import 'dart:async';
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/adaptive_popover.dart';
import 'android_back_interceptor.dart';
import 'empty_detail_pane.dart';
import 'session_sidebar.dart';
import 'sidebar_resize_handle.dart';

export 'sidebar_resize_handle.dart';

/// 宽屏双栏断点阈值（像素）。
///
/// 避开 Flutter 测试默认视口（800×600），确保现有单测与页面 widget 测试保持窄屏单栈分支。
const double kAdaptiveBreakpoint = 900.0;

/// 宽屏左侧栏默认宽度（像素）。
const double kAdaptiveSidebarDefaultWidth = 320.0;

/// 宽屏左侧栏最小宽度（像素）。
const double kAdaptiveSidebarMinWidth = 280.0;

/// 宽屏左侧栏最大宽度（像素）。
const double kAdaptiveSidebarMaxWidth = 420.0;

/// 兼容旧常量：宽屏左侧栏默认宽度（像素）。
///
/// 对齐 iOS 原生 NavigationSplitView 理想宽度（ideal: 340 / min: 280 / max: 420）。
const double kAdaptiveSidebarWidth = kAdaptiveSidebarDefaultWidth;

/// 侧栏宽度在 [SharedPreferences] 中的持久化键名。
const String kAdaptiveSidebarWidthStorageKey = 'adaptive_sidebar_width';

/// 自适应宽屏双栏外壳（TASK W2 / TASK-SIDEBAR-RESIZE / Android 系统返回三级分流）。
///
/// - 窄屏（width < 900）：直接展示当前页面 [child]，保持单栈 Cupertino 体验。
/// - 宽屏（width >= 900）：左侧展示常驻 [SessionSidebar]（宽度可拖拽调整并在 [280, 420] 之间 clamp，且持久化到本地存储），
///   中间展示拖拽手柄 [SidebarResizeHandle]，右侧展示详情内容 [child]（若路由为 `/` 则展示 [EmptyDetailPane]）。
/// - 系统返回（Android）：四级分流接管（① 弹层/覆盖层关闭；② 页面级拦截器
///   （如工作区非根目录 → 上一级目录，[AndroidBackInterceptorRegistry]）；
///   ③ 二级页回退到主页 `/`；④ 主页 2 秒内双击退出应用），其他平台行为空转。
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key, required this.state, required this.child});

  /// 当前路由状态。
  final GoRouterState state;

  /// 当前路由对应的主页面组件。
  final Widget child;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  double _sidebarWidth = kAdaptiveSidebarDefaultWidth;
  DateTime? _lastBackPressTime;
  bool _showExitToast = false;
  Timer? _exitToastTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPersistedWidth());
  }

  @override
  void didUpdateWidget(covariant AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.matchedLocation != widget.state.matchedLocation) {
      _lastBackPressTime = null;
      _dismissExitToast();
    }
  }

  @override
  void dispose() {
    _exitToastTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPersistedWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final rawWidth = prefs.get(kAdaptiveSidebarWidthStorageKey);
    if (rawWidth is num && mounted) {
      final resolved = rawWidth.toDouble().clamp(
        kAdaptiveSidebarMinWidth,
        kAdaptiveSidebarMaxWidth,
      );
      if (resolved == _sidebarWidth) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final again = resolved.clamp(
          kAdaptiveSidebarMinWidth,
          kAdaptiveSidebarMaxWidth,
        );
        if (again == _sidebarWidth) return;
        setState(() {
          _sidebarWidth = again;
        });
      });
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    // 高频拖拽：只做布局更新，不做磁盘 I/O，避免每帧 SharedPreferences
    // 写入阻塞 UI 线程并放大窗口重绘压力（Windows EGL Context Lost）。
    final nextWidth = (_sidebarWidth + details.delta.dx).clamp(
      kAdaptiveSidebarMinWidth,
      kAdaptiveSidebarMaxWidth,
    );
    if ((nextWidth - _sidebarWidth).abs() < 0.5) return;
    if (nextWidth != _sidebarWidth) {
      setState(() {
        _sidebarWidth = nextWidth;
      });
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    unawaited(_persistWidth(_sidebarWidth));
  }

  Future<void> _persistWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kAdaptiveSidebarWidthStorageKey, width);
  }

  void _dismissExitToast() {
    _exitToastTimer?.cancel();
    if (_showExitToast && mounted) {
      setState(() {
        _showExitToast = false;
      });
    }
  }

  void _showExitToastMessage() {
    _exitToastTimer?.cancel();
    if (mounted) {
      setState(() {
        _showExitToast = true;
      });
    }
    _exitToastTimer = Timer(const Duration(seconds: 2), () {
      _lastBackPressTime = null;
      if (mounted) {
        setState(() {
          _showExitToast = false;
        });
      }
    });
  }

  void _handlePopInvoked(bool didPop, dynamic result) {
    if (didPop) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    _handleAndroidBack();
  }

  void _handleAndroidBack() {
    // 1. 先关 overlay 弹层（AdaptiveActionMenu / ContextWindowPopover 等）
    if (AdaptivePopover.closeTopOverlay()) {
      _lastBackPressTime = null;
      _dismissExitToast();
      return;
    }

    // 1.5 页面级拦截器（LIFO）：如工作区文件浏览非根目录时返回 = 上一级
    // 目录而非退出页面；处理器自证当前顶层（isCurrent）才消费。
    if (AndroidBackInterceptorRegistry.handle()) {
      _lastBackPressTime = null;
      _dismissExitToast();
      return;
    }

    // 2. 再关 Navigator route 覆盖层（bottom sheet / modal popup）
    if (Navigator.of(context).canPop()) {
      _lastBackPressTime = null;
      _dismissExitToast();
      Navigator.of(context).pop();
      return;
    }

    final location = widget.state.matchedLocation;
    // 3. 无覆盖层且非首页（/onboarding 除外）→ canPop ? pop : go('/')
    if (location != '/' && location != '/onboarding') {
      _lastBackPressTime = null;
      _dismissExitToast();
      context.go('/');
      return;
    }

    // 4. 首页 / → 首次按返回提示，2s 内再按退出应用
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      _showExitToastMessage();
    } else {
      _dismissExitToast();
      _lastBackPressTime = null;
      unawaited(SystemNavigator.pop());
    }
  }

  Widget _buildExitToast(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: IgnorePointer(
            child: Container(
              key: const ValueKey('android-back-exit-toast'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: CupertinoColors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                '再按一次退出应用',
                style: TextStyle(
                  color: CupertinoColors.white,
                  fontSize: kFontSidebarTitle,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    final router = GoRouter.maybeOf(context);
    final effectiveLocation =
        router?.routerDelegate.currentConfiguration.last.matchedLocation ??
        widget.state.matchedLocation;
    final isRootSessionList = effectiveLocation == '/';
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    final Widget content = isWide
        ? ColoredBox(
            color: CupertinoTheme.of(context).scaffoldBackgroundColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  key: const ValueKey('adaptive-shell-wide-layout'),
                  children: [
                    SizedBox(
                      key: const ValueKey('adaptive-shell-sidebar-container'),
                      width: _sidebarWidth,
                      child: SessionSidebar(currentLocation: effectiveLocation),
                    ),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (isRootSessionList)
                            const EmptyDetailPane()
                          else
                            widget.child,
                          if (isRootSessionList)
                            Offstage(offstage: true, child: widget.child),
                        ],
                      ),
                    ),
                  ],
                ),
                // #168 拖拽把手改「覆盖层」：不再占布局宽度 —— 原先它横在两栏之间
                // 吃掉 9px，两栏的水平发丝线因此在分界处各断一截（左右各少 ~4.5px，
                // 肉眼即「接缝」）。改为以分界线为中心叠加后，两栏横线严丝合缝，
                // 只有那条 1px 竖线穿过它们。
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: _sidebarWidth - SidebarResizeHandle.defaultWidth / 2,
                  width: SidebarResizeHandle.defaultWidth,
                  child: SidebarResizeHandle(
                    onDragUpdate: _handleDragUpdate,
                    onDragEnd: _handleDragEnd,
                  ),
                ),
              ],
            ),
          )
        : widget.child;

    return PopScope(
      key: const ValueKey('adaptive-shell-pop-scope'),
      canPop: !isAndroid,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Stack(
        children: [content, if (_showExitToast) _buildExitToast(context)],
      ),
    );
  }
}
