import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/locale/locale_resolver.dart';
import '../../app/router.dart';
import '../../l10n/app_localizations.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/session.dart';
import '../session_list/session_list_providers.dart';
import '../webui_sidecar/webui_sidecar_providers.dart';
import 'desktop_settings.dart';

/// 从 asset 加载托盘图标并写入临时文件，返回临时文件的绝对路径。
///
/// 避免 Windows 下直接引用相对路径导致图标无法加载的问题。
/// Windows 下 [tray_manager] 的原生侧通过 `LoadImage(IMAGE_ICON, LR_LOADFROMFILE)`
/// 仅可靠加载 `.ico`，传入 `.png` 会静默失败导致托盘空白；因此 Windows 分支
/// 应传入 `assets/branding/tray_icon.ico` 并以 `.ico` 后缀落盘。
/// 当 [fileName] 以 `.ico` 结尾时直接写入资产字节即可（资产本身即为合法 ICO）。
Future<String> prepareTrayIconFile({
  AssetBundle? assetBundle,
  Directory? tempDir,
  String assetPath = 'assets/branding/tray_icon_32.png',
  String fileName = 'hermes_tray_icon_32.png',
}) async {
  final bundle = assetBundle ?? rootBundle;
  final dir = tempDir ?? Directory.systemTemp;
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');

  final byteData = await bundle.load(assetPath);
  final bytes = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );

  await file.writeAsBytes(bytes, flush: true);
  return file.absolute.path;
}

/// 会话状态映射为托盘显示文案（运行中 / 排队中 / 已归档 / 只读 / null）。
String? formatSessionStatus(SessionSummary session) {
  final l10n = AppLocalizations(LocaleResolver.resolve());
  if (session.isStreaming == true ||
      (session.activeStreamId != null && session.activeStreamId!.isNotEmpty)) {
    return l10n.trayStatusRunning;
  }
  if (session.hasPendingUserMessage == true) {
    return l10n.trayStatusQueued;
  }
  if (session.archived == true) {
    return l10n.trayStatusArchived;
  }
  if (session.isSessionReadOnly) {
    return l10n.trayStatusReadOnly;
  }
  return null;
}

/// 格式化托盘最近会话菜单项文案（含标题截断与状态标签）。
String formatRecentSessionLabel(
  SessionSummary session, {
  int maxTitleLength = 24,
}) {
  final rawTitle = session.title?.trim();
  String title = (rawTitle != null && rawTitle.isNotEmpty)
      ? rawTitle
      : 'Untitled';

  if (title.characters.length > maxTitleLength) {
    title = '${title.characters.take(maxTitleLength).toString()}...';
  }

  final status = formatSessionStatus(session);
  if (status != null && status.isNotEmpty) {
    return '$title ($status)';
  }
  return title;
}

/// 格式化 WebUI Sidecar 服务状态在托盘菜单中的展示文案。
String formatWebuiStatusLabel(SidecarStatus status) {
  final l10n = AppLocalizations(LocaleResolver.resolve());
  switch (status) {
    case SidecarStatus.running:
      return l10n.trayWebuiRunning;
    case SidecarStatus.starting:
      return l10n.trayWebuiStarting;
    case SidecarStatus.failed:
      return l10n.trayWebuiFailed;
    case SidecarStatus.stopped:
      return l10n.trayWebuiStopped;
  }
}

/// 系统托盘服务。
///
/// 职责：
/// 1. 创建并维护系统托盘图标（Windows 下写出真实临时文件）；
/// 2. 设置右键上下文菜单（显示主窗口 / 新建会话 / 打开 WebUI / WebUI 状态 / 最近会话列表 / 退出应用）；
/// 3. 处理托盘点击恢复窗口与最近会话跳转；
/// 4. 非桌面平台安全降级 no-op。
class TrayManagerService with TrayListener {
  /// 菜单项 Key 常量
  static const String menuItemShowWindow = 'show_window';
  static const String menuItemNewSession = 'new_session';
  static const String menuItemOpenWebui = 'open_webui';
  static const String menuItemWebuiStatus = 'webui_status';
  static const String menuItemNoRecentSessions = 'no_recent_sessions';
  static const String menuItemQuitApp = 'quit_app';
  static const String recentSessionPrefix = 'recent_';

  /// 唤起主窗口回调（可自定义用于测试）。
  final FutureOr<void> Function()? onShowWindow;

  /// 新建会话回调（可自定义用于测试）。
  final FutureOr<void> Function()? onNewSession;

  /// 打开指定会话回调（可自定义用于测试）。
  final FutureOr<void> Function(String sessionId)? onOpenSession;

  /// 打开 WebUI 回调（可自定义用于测试）。
  final FutureOr<void> Function()? onOpenWebui;

  /// 退出应用回调（可自定义用于测试）。
  final FutureOr<void> Function()? onQuit;

  /// 停止 Sidecar 回调（可自定义用于测试）。
  final Future<void> Function()? onStopSidecar;

  /// WebUI Sidecar 服务（测试可注入 fake sidecar）。
  final WebuiSidecarService? sidecarService;

  /// 获取 WebUI Sidecar 即时状态函数。
  final SidecarState Function()? getSidecarState;

  /// 获取 WebUI Sidecar 即时配置函数。
  final SidecarConfig Function()? getSidecarConfig;

  /// 获取最近会话列表函数（同步读取，用于刷新菜单）。
  final List<SessionSummary>? Function()? getRecentSessions;

  /// 异步拉取最近会话列表函数。
  final Future<List<SessionSummary>?> Function()? fetchRecentSessions;

  /// 托盘菜单刷新节流时长（默认 500ms，防 Windows 托盘狂刷抖动）。
  final Duration throttleDuration;

  /// 是否为桌面平台。
  final bool isDesktop;

  bool _initialized = false;

  /// 语言变化监听 token（initialize 注册、disposeLocaleListener 注销）。
  Object? _localeListenerToken;
  List<SessionSummary> _cachedSessions = const [];
  SidecarState _cachedSidecarState = SidecarState.initial;
  SidecarConfig _cachedSidecarConfig = const SidecarConfig();
  Timer? _menuUpdateThrottleTimer;
  bool _pendingMenuUpdate = false;
  StreamSubscription<SidecarState>? _sidecarSubscription;

  /// 构造系统托盘服务。
  TrayManagerService({
    this.onShowWindow,
    this.onNewSession,
    this.onOpenSession,
    this.onOpenWebui,
    this.onQuit,
    this.onStopSidecar,
    this.sidecarService,
    this.getSidecarState,
    this.getSidecarConfig,
    this.getRecentSessions,
    this.fetchRecentSessions,
    this.throttleDuration = const Duration(milliseconds: 500),
    bool? isDesktop,
  }) : isDesktop = isDesktop ?? isDesktopPlatform();

  /// 服务是否已初始化。
  bool get isInitialized => _initialized;

  /// 初始化托盘图标与上下文菜单。
  Future<void> initialize() async {
    if (!isDesktop || _initialized) return;

    try {
      trayManager.addListener(this);
      final sidecar = sidecarService;
      if (sidecar != null) {
        _sidecarSubscription = sidecar.states.listen((_) {
          scheduleThrottledUpdateContextMenu();
        });
      }
      // L2：语言模式变化 -> 节流重建托盘菜单（菜单 label 经 LocaleResolver 取语言）。
      _localeListenerToken ??= LocaleResolver.addListener(
        scheduleThrottledUpdateContextMenu,
      );
      await _setupTrayIcon();
      await updateContextMenu();
      _initialized = true;
    } catch (e, st) {
      developer.log(
        'Failed to initialize TrayManagerService',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 设置托盘图标与悬浮提示。
  Future<void> _setupTrayIcon() async {
    try {
      String iconPath;
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        iconPath =
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png';
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        iconPath = await prepareTrayIconFile(
          assetPath: 'assets/branding/tray_icon.ico',
          fileName: 'hermes_tray_icon.ico',
        );
      } else {
        iconPath = await prepareTrayIconFile();
      }
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Hermes');
    } catch (e, st) {
      developer.log(
        'Failed to set tray icon / tooltip',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 构建托盘菜单项纯函数。
  static List<MenuItem> buildMenuItems({
    List<SessionSummary> sessions = const [],
    int maxRecentSessions = 6,
    void Function(String sessionId)? onOpenSession,
    void Function()? onShowWindow,
    void Function()? onNewSession,
    void Function()? onOpenWebui,
    void Function()? onQuit,
    SidecarStatus? sidecarStatus,
    bool? sidecarEnabled,
    SidecarState? sidecarState,
    SidecarConfig? sidecarConfig,
  }) {
    final effectiveStatus =
        sidecarState?.status ?? sidecarStatus ?? SidecarStatus.stopped;

    final effectiveEnabled =
        sidecarConfig?.enabled ??
        sidecarEnabled ??
        (sidecarStatus == SidecarStatus.running);

    final isWebuiEnabled =
        effectiveEnabled && effectiveStatus == SidecarStatus.running;

    final l10n = AppLocalizations(LocaleResolver.resolve());

    final items = <MenuItem>[
      MenuItem(
        key: menuItemShowWindow,
        label: l10n.trayShowWindow,
        onClick: onShowWindow != null ? (_) => onShowWindow() : null,
      ),
      MenuItem(
        key: menuItemNewSession,
        label: l10n.trayNewSession,
        onClick: onNewSession != null ? (_) => onNewSession() : null,
      ),
      MenuItem.separator(),
      MenuItem(
        key: menuItemOpenWebui,
        label: l10n.trayOpenWebui,
        disabled: !isWebuiEnabled,
        onClick: onOpenWebui != null ? (_) => onOpenWebui() : null,
      ),
      MenuItem(
        key: menuItemWebuiStatus,
        label: formatWebuiStatusLabel(effectiveStatus),
        disabled: true,
      ),
      MenuItem.separator(),
    ];

    final visibleSessions = sessions
        .where(
          (s) =>
              s.sessionId != null &&
              s.sessionId!.isNotEmpty &&
              s.shouldAppearInSessionList,
        )
        .take(maxRecentSessions)
        .toList();

    if (visibleSessions.isEmpty) {
      items.add(
        MenuItem(
          key: menuItemNoRecentSessions,
          label: l10n.trayNoRecentSessions,
          disabled: true,
        ),
      );
    } else {
      for (final session in visibleSessions) {
        final sid = session.sessionId!;
        items.add(
          MenuItem(
            key: '$recentSessionPrefix$sid',
            label: formatRecentSessionLabel(session),
            onClick: onOpenSession != null ? (_) => onOpenSession(sid) : null,
          ),
        );
      }
    }

    items.add(MenuItem.separator());
    items.add(
      MenuItem(
        key: menuItemQuitApp,
        label: l10n.trayQuitApp,
        onClick: onQuit != null ? (_) => onQuit() : null,
      ),
    );

    return items;
  }

  /// 节流刷新托盘上下文菜单（500ms 窗口防抖/节流，避免 Windows 托盘闪烁）。
  void scheduleThrottledUpdateContextMenu() {
    if (!isDesktop) return;

    if (_menuUpdateThrottleTimer?.isActive ?? false) {
      _pendingMenuUpdate = true;
      return;
    }
    _pendingMenuUpdate = false;
    unawaited(updateContextMenu());
    _menuUpdateThrottleTimer = Timer(throttleDuration, () {
      if (_pendingMenuUpdate) {
        _pendingMenuUpdate = false;
        unawaited(updateContextMenu());
      }
    });
  }

  /// 刷新托盘菜单接口（测试或外部触发用）。
  Future<void> refreshMenu({bool throttled = true}) async {
    if (throttled) {
      scheduleThrottledUpdateContextMenu();
    } else {
      await updateContextMenu();
    }
  }

  /// 构建并设置托盘上下文菜单。
  Future<void> updateContextMenu({
    List<SessionSummary>? sessions,
    SidecarStatus? sidecarStatus,
    bool? sidecarEnabled,
  }) async {
    if (!isDesktop) return;

    try {
      List<SessionSummary> sessionList = sessions ?? _cachedSessions;
      if (sessions == null && getRecentSessions != null) {
        sessionList = getRecentSessions!() ?? sessionList;
      } else if (sessions == null && fetchRecentSessions != null) {
        try {
          final fetched = await fetchRecentSessions!();
          if (fetched != null) {
            sessionList = fetched;
          }
        } catch (e) {
          developer.log(
            'Failed to fetch recent sessions for tray menu',
            name: 'TrayManagerService',
            error: e,
          );
        }
      }
      _cachedSessions = sessionList;

      final currentSidecarState = sidecarStatus != null
          ? SidecarState(status: sidecarStatus)
          : (getSidecarState?.call() ??
                sidecarService?.currentState ??
                _cachedSidecarState);
      _cachedSidecarState = currentSidecarState;

      final currentSidecarConfig = sidecarEnabled != null
          ? _cachedSidecarConfig.copyWith(enabled: sidecarEnabled)
          : (getSidecarConfig?.call() ?? _cachedSidecarConfig);
      _cachedSidecarConfig = currentSidecarConfig;

      final items = buildMenuItems(
        sessions: sessionList,
        sidecarStatus: currentSidecarState.status,
        sidecarEnabled: currentSidecarConfig.enabled,
        // 刻意【不挂】菜单项 onClick：tray_manager 0.5.3 的原生分发先调
        // menuItem.onClick，再【无条件】调 listener.onTrayMenuItemClick
        // （tray_manager.dart:61-64）。两处都接线会让每次点击触发两次业务回调
        // （典型：handleQuit 重复 stop sidecar，第二次等满 5s 超时，退出肉眼可见变慢）。
        // 统一由 onTrayMenuItemClick 按 key 分发（它是插件保证会调的入口）。
      );

      final menu = Menu(items: items);
      await trayManager.setContextMenu(menu);
    } catch (e, st) {
      developer.log(
        'Failed to set tray context menu',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「显示主窗口」操作。
  Future<void> handleShowWindow() async {
    if (onShowWindow != null) {
      await onShowWindow!();
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      developer.log(
        'Failed to show window',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「新建会话」操作。
  Future<void> handleNewSession() async {
    if (onNewSession != null) {
      await onNewSession!();
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      developer.log(
        'Failed to handle new session',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「打开指定会话」操作。
  Future<void> handleOpenSession(String sessionId) async {
    if (onOpenSession != null) {
      await onOpenSession!(sessionId);
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      developer.log(
        'Failed to open session: $sessionId',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「打开 WebUI」操作。
  Future<void> handleOpenWebui() async {
    final state =
        getSidecarState?.call() ??
        sidecarService?.currentState ??
        _cachedSidecarState;
    final config = getSidecarConfig?.call() ?? _cachedSidecarConfig;

    // Windows 托盘已知坑：disabled 菜单项在 Windows 原生侧仍可能触发点击事件，
    // 此处必须二次判断 enabled 与 running 状态。
    final isRunning = config.enabled && state.status == SidecarStatus.running;
    if (!isRunning) {
      developer.log(
        'WebUI is not running or disabled, ignoring open_webui click',
        name: 'TrayManagerService',
      );
      return;
    }

    if (onOpenWebui != null) {
      await onOpenWebui!();
      return;
    }

    final host = config.host == '0.0.0.0' ? '127.0.0.1' : config.host;
    final port = config.port;
    final url = 'http://$host:$port';

    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      developer.log(
        'Failed to launch WebUI url: $url',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「退出应用」操作。
  Future<void> handleQuit() async {
    // 退出前先停止内置 WebUI Sidecar（5s 超时兜底防挂死）
    try {
      final stopFuture = onStopSidecar != null
          ? onStopSidecar!()
          : sidecarService?.stop();
      if (stopFuture != null) {
        await stopFuture.timeout(const Duration(seconds: 5));
      }
    } catch (e, st) {
      developer.log(
        'Failed or timed out stopping sidecar on quit (fallback to proceed with quit)',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }

    if (onQuit != null) {
      await onQuit!();
      return;
    }
    try {
      await windowManager.destroy();
    } catch (e, st) {
      developer.log(
        'Failed to destroy window on quit',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(handleShowWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    // catchError 必须挂在返回的 Future 上：popUpContextMenu 是 async，
    // 异常经 Future 投递，try/catch 包同步调用永远捕不到（catch 块会成死代码）。
    unawaited(
      trayManager.popUpContextMenu().catchError((Object e, StackTrace st) {
        developer.log(
          'Failed to pop up tray context menu',
          name: 'TrayManagerService',
          error: e,
          stackTrace: st,
        );
      }),
    );
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == null) return;
    if (key == menuItemShowWindow) {
      unawaited(handleShowWindow());
    } else if (key == menuItemNewSession) {
      unawaited(handleNewSession());
    } else if (key == menuItemOpenWebui) {
      unawaited(handleOpenWebui());
    } else if (key == menuItemQuitApp) {
      unawaited(handleQuit());
    } else if (key.startsWith(recentSessionPrefix)) {
      final sessionId = key.substring(recentSessionPrefix.length);
      unawaited(handleOpenSession(sessionId));
    }
  }

  /// 销毁托盘服务。
  /// 注销语言变化监听（dispose 调用，防静态多播表泄漏）。
  void disposeLocaleListener() {
    final token = _localeListenerToken;
    if (token != null) {
      LocaleResolver.removeListener(token);
      _localeListenerToken = null;
    }
  }

  Future<void> dispose() async {
    _menuUpdateThrottleTimer?.cancel();
    _menuUpdateThrottleTimer = null;
    await _sidecarSubscription?.cancel();
    _sidecarSubscription = null;
    disposeLocaleListener();

    if (!isDesktop) return;

    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (e, st) {
      developer.log(
        'Failed to dispose tray manager',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
    _initialized = false;
  }
}

/// 系统托盘服务 Provider。
final trayManagerServiceProvider = Provider<TrayManagerService>((ref) {
  final service = TrayManagerService(
    onShowWindow: () async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        developer.log(
          'Failed to show window',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    onNewSession: () async {
      try {
        await windowManager.show();
        await windowManager.focus();
        ref.read(routerProvider).go('/chat');
      } catch (e) {
        developer.log(
          'Failed to show window and navigate to /chat',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    onOpenSession: (sessionId) async {
      try {
        await windowManager.show();
        await windowManager.focus();
        ref.read(routerProvider).go('/chat/$sessionId');
      } catch (e) {
        developer.log(
          'Failed to show window and navigate to /chat/$sessionId',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    getRecentSessions: () =>
        ref.read(sessionListControllerProvider).valueOrNull?.sessions,
    fetchRecentSessions: () async {
      try {
        final api = ref.read(sessionListApiFactoryProvider)(
          ref.read(apiClientProvider),
        );
        final response = await api.fetchSessions();
        return response.sessions;
      } catch (e) {
        developer.log(
          'Failed to fetch sessions for tray menu',
          name: 'TrayManagerService',
          error: e,
        );
        return null;
      }
    },
    onQuit: () async {
      try {
        await windowManager.destroy();
      } catch (e) {
        developer.log(
          'Failed to destroy window',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    onStopSidecar: () async {
      try {
        await ref.read(webuiSidecarControllerProvider.notifier).stop();
      } catch (e, st) {
        developer.log(
          'Failed to stop sidecar from tray service',
          name: 'TrayManagerService',
          error: e,
          stackTrace: st,
        );
      }
    },
    sidecarService: ref.read(webuiSidecarServiceProvider),
    getSidecarState: () => ref.read(webuiSidecarControllerProvider),
    getSidecarConfig: () => ref.read(webuiSidecarConfigProvider),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
