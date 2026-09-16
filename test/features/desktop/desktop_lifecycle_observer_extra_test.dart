// DesktopLifecycleObserver 补充覆盖测试（TASK-B3）
//
// 覆盖目标（lcov 行号口径；基线 f035bf1 = 124/192 covered）：
//   66-69    didChangeLocales 桌面分支 → 托盘菜单节流刷新
//   110-111  _initDesktopServices「enabled 且状态未就绪 → 主动 start」
//   119      _initDesktopServices 异常吞没（catch 分支）
//   138-148  _onRouteChanged 路由段解析与 activeSessionId 写入
//   152-182  _syncSessionTitle 三条取标题路径
//   200-213  设置变更监听（快捷键注册/注销、关闭拦截）
//   224-238  activeSessionId 空/非空 + 活跃会话标题变更监听
//   248-251  会话列表变化 → 托盘上下文菜单
//   267-268  sidecar host/port 变更 → 托盘菜单节流刷新
//   320-340  ColdStartGraceState.copyWith / operator== / hashCode
//   454-455  _pollHealth 入口守卫（状态已非 active 时自行停表）
//   469      健康探测就绪 → _resolveGrace（联动会话列表刷新）
//
// 语义提醒：本仓做过「失焦(AppLifecycleState.inactive) vs 隐藏(hidden)」语义修复，
// 本文件所有期望值均照 desktop_lifecycle_observer.dart 的真实实现书写，
// 不引用任何未经验证的印象。
//
// 已知无法覆盖：第 213 行（见 TASK_REPORT.md「实现观察」——`unawaited` 包裹的
// 异步调用无法被同步 try/catch 命中）。

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/core/install/webui_bootstrap.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/desktop/desktop_lifecycle_observer.dart';
import 'package:hermes_ui/features/desktop/desktop_settings.dart';
import 'package:hermes_ui/features/desktop/desktop_shortcuts.dart';
import 'package:hermes_ui/features/desktop/tray_manager_service.dart';
import 'package:hermes_ui/features/desktop/window_memory.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Sidecar mock 基建（与 desktop_lifecycle_observer_test.dart 同一套手法）
// ---------------------------------------------------------------------------

class _FakeSidecarConfigStorage extends Fake
    implements WebuiSidecarConfigStorage {
  _FakeSidecarConfigStorage({
    SidecarConfig initialConfig = const SidecarConfig(),
  }) : config = initialConfig;

  SidecarConfig config;

  @override
  Future<SidecarConfig> load() async => config;

  @override
  Future<void> save(SidecarConfig newConfig) async {
    config = newConfig;
  }

  @override
  Future<void> setEnabled(bool value) async {
    config = config.copyWith(enabled: value);
  }

  @override
  Future<void> setHost(String value) async {
    config = config.copyWith(host: value);
  }

  @override
  Future<void> setPort(int value) async {
    config = config.copyWith(port: value);
  }

  @override
  Future<void> setPassword(String value) async {
    config = config.copyWith(password: value);
  }
}

class _FakeSidecarFileSystem extends Fake implements SidecarFileSystem {
  @override
  bool get isWindows => true;

  @override
  bool isBundleAvailable() => true;
}

class _FakeSidecarService implements WebuiSidecarService {
  _FakeSidecarService({
    SidecarState initialState = SidecarState.initial,
    this.emitRunningOnStart = true,
  }) : _state = initialState;

  /// start() 是否立即把状态推进到 running（默认 true，对齐既有 mock）。
  ///
  /// 置 false 可造出「已 enabled 但状态仍未就绪」的场景，用于覆盖
  /// _initDesktopServices 里「enabled && status 非 running/starting → 主动 start」
  /// 的分支（既有 mock 因 start() 立即 running 而永远短路）。
  final bool emitRunningOnStart;

  SidecarState _state;
  final StreamController<SidecarState> _controller =
      StreamController<SidecarState>.broadcast();

  int startCallCount = 0;
  int stopCallCount = 0;

  @override
  SidecarState get currentState => _state;

  @override
  Stream<SidecarState> get states => _controller.stream;

  @override
  Future<void> start() async {
    startCallCount++;
    if (emitRunningOnStart) {
      emitState(_state.copyWith(status: SidecarStatus.running));
    }
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> restart() async {
    await stop();
    await start();
  }

  void emitState(SidecarState newState) {
    _state = newState;
    _controller.add(newState);
  }

  void dispose() {
    unawaited(_controller.close());
  }
}

class _FakeHealthChecker implements HealthChecker {
  _FakeHealthChecker({this.isHealthy = false});

  bool isHealthy;
  int callCount = 0;

  @override
  Future<bool> checkHealth(String url) async {
    callCount++;
    return isHealthy;
  }
}

// ---------------------------------------------------------------------------
// 桌面服务记录型替身（替换真实平台调用，只记调用不碰 windowManager）
// ---------------------------------------------------------------------------

class _RecordingTitleService extends WindowTitleService {
  _RecordingTitleService() : super(isDesktop: false);

  /// updateSessionTitle 收到的原始（未格式化）标题，按调用顺序记录。
  final List<String?> sessionTitles = <String?>[];
  int resetCount = 0;

  @override
  Future<void> resetTitle() async {
    resetCount++;
  }

  @override
  Future<void> updateSessionTitle(String? sessionTitle) async {
    sessionTitles.add(sessionTitle);
  }
}

class _ThrowingTitleService extends WindowTitleService {
  _ThrowingTitleService() : super(isDesktop: false);

  int resetCount = 0;

  @override
  Future<void> resetTitle() async {
    resetCount++;
    throw StateError('resetTitle 注入失败');
  }
}

class _RecordingTrayService extends TrayManagerService {
  _RecordingTrayService() : super(isDesktop: false);

  int initializeCount = 0;
  int scheduleCount = 0;
  int updateContextMenuCount = 0;
  List<SessionSummary>? lastMenuSessions;

  @override
  Future<void> initialize() async {
    initializeCount++;
  }

  @override
  void scheduleThrottledUpdateContextMenu() {
    scheduleCount++;
  }

  @override
  Future<void> updateContextMenu({
    List<SessionSummary>? sessions,
    SidecarStatus? sidecarStatus,
    bool? sidecarEnabled,
  }) async {
    updateContextMenuCount++;
    lastMenuSessions = sessions;
  }
}

class _RecordingMemoryService extends WindowMemoryService {
  _RecordingMemoryService() : super(isDesktop: false);

  int initializeCount = 0;
  int restoreCount = 0;

  @override
  Future<void> initialize() async {
    initializeCount++;
  }

  @override
  Future<bool> restoreWindowBounds({
    SharedPreferences? customPrefs,
    List<Rect>? customDisplayBounds,
  }) async {
    restoreCount++;
    return true;
  }
}

class _RecordingShortcutsService extends DesktopShortcutsService {
  _RecordingShortcutsService() : super(isDesktop: false);

  int registerCount = 0;
  int unregisterCount = 0;

  @override
  Future<void> registerShortcuts() async {
    registerCount++;
  }

  @override
  Future<void> unregisterShortcuts() async {
    unregisterCount++;
  }
}

// ---------------------------------------------------------------------------
// 会话列表 / 聊天控制器替身
// ---------------------------------------------------------------------------

class _FakeSessionListController extends SessionListController {
  _FakeSessionListController({
    this.initialSessions = const <SessionSummary>[],
  });

  final List<SessionSummary> initialSessions;

  int refreshCallCount = 0;
  String? appliedTimeoutError;

  @override
  Future<SessionListState> build() async =>
      SessionListState(sessions: initialSessions);

  /// 运行期推送一份新的会话列表（驱动 observer 的托盘菜单监听）。
  void emitSessions(List<SessionSummary> sessions) {
    state = AsyncData<SessionListState>(SessionListState(sessions: sessions));
  }

  @override
  Future<void> refresh() async {
    refreshCallCount++;
  }

  @override
  void applyGraceTimeout(String message) {
    appliedTimeoutError = message;
  }
}

/// 聊天控制器工厂。
///
/// `chatControllerProvider` 是 family：每个 sessionId 都会新建一个 notifier 实例
/// （NotifierBase 的 `_element` 是 late final，同一实例不能挂到两个元素上），
/// 因此这里按需建实例并登记，测试侧改标题时统一驱动。
class _FakeChatControllerFactory {
  _FakeChatControllerFactory(this._displayTitle);

  String _displayTitle;
  final List<_FakeChatController> _instances = <_FakeChatController>[];

  String get displayTitle => _displayTitle;

  _FakeChatController create() {
    final controller = _FakeChatController(this);
    _instances.add(controller);
    return controller;
  }

  /// 运行期改标题（驱动 observer 的 displayTitle 监听）。
  ///
  /// family 为非 autoDispose，元素在容器存活期内不会被销毁，可安全全部驱动。
  void setDisplayTitle(String title) {
    _displayTitle = title;
    for (final controller in _instances) {
      controller.applyTitle(title);
    }
  }
}

class _FakeChatController extends ChatController {
  _FakeChatController(this._factory);

  final _FakeChatControllerFactory _factory;

  @override
  ChatState build(String sessionId) =>
      ChatState(sessionId: sessionId, displayTitle: _factory.displayTitle);

  void applyTitle(String title) {
    state = state.copyWith(displayTitle: title);
  }
}

/// 白盒探针：绕过公开 API 直接把宽限状态拨离 active（定时器保持存活）。
///
/// 仅用于验证 `_pollHealth` 的入口守卫在「状态已非 active 而周期拍尚存」时
/// 会自行停表 —— 该组合在公开 API 下不可达（见 TASK_REPORT.md）。
class _ProbeGraceController extends ColdStartGraceController {
  void forceIdleForTest() {
    state = const ColdStartGraceState();
  }
}

// ---------------------------------------------------------------------------
// 测试替身装配
// ---------------------------------------------------------------------------

class _ObserverHarness {
  _ObserverHarness({
    String initialLocation = '/',
    SidecarConfig sidecarConfig = const SidecarConfig(),
    bool sidecarEmitsRunningOnStart = true,
    List<SessionSummary> sessions = const <SessionSummary>[],
    WindowTitleService? titleServiceOverride,
    String chatDisplayTitle = 'Untitled Session',
  }) : title = _RecordingTitleService(),
       titleServiceOverride = titleServiceOverride,
       tray = _RecordingTrayService(),
       memory = _RecordingMemoryService(),
       shortcuts = _RecordingShortcutsService(),
       storage = _FakeSidecarConfigStorage(initialConfig: sidecarConfig),
       sidecarService = _FakeSidecarService(
         emitRunningOnStart: sidecarEmitsRunningOnStart,
       ),
       sessionList = _FakeSessionListController(initialSessions: sessions),
       chatControllers = _FakeChatControllerFactory(chatDisplayTitle) {
    router = GoRouter(
      initialLocation: initialLocation,
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (context, state) => const SizedBox()),
        GoRoute(path: '/chat', builder: (context, state) => const SizedBox()),
        GoRoute(
          path: '/chat/:sessionId',
          builder: (context, state) => const SizedBox(),
        ),
        GoRoute(
          path: '/workspace/:sessionId',
          builder: (context, state) => const SizedBox(),
        ),
        GoRoute(
          path: '/git/:sessionId',
          builder: (context, state) => const SizedBox(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SizedBox(),
        ),
      ],
    );
    container = ProviderContainer(
      overrides: <Override>[
        routerProvider.overrideWithValue(router),
        windowTitleServiceProvider.overrideWithValue(
          titleServiceOverride ?? title,
        ),
        trayManagerServiceProvider.overrideWithValue(tray),
        windowMemoryServiceProvider.overrideWithValue(memory),
        desktopShortcutsServiceProvider.overrideWithValue(shortcuts),
        webuiSidecarConfigStorageProvider.overrideWithValue(storage),
        webuiSidecarServiceProvider.overrideWithValue(sidecarService),
        sidecarFileSystemProvider.overrideWithValue(_FakeSidecarFileSystem()),
        sessionListControllerProvider.overrideWith(() => sessionList),
        chatControllerProvider.overrideWith(chatControllers.create),
      ],
    );
    addTearDown(() {
      container.dispose();
      router.dispose();
    });
  }

  final _RecordingTitleService title;
  final WindowTitleService? titleServiceOverride;
  final _RecordingTrayService tray;
  final _RecordingMemoryService memory;
  final _RecordingShortcutsService shortcuts;
  final _FakeSidecarConfigStorage storage;
  final _FakeSidecarService sidecarService;
  final _FakeSessionListController sessionList;
  final _FakeChatControllerFactory chatControllers;

  late final GoRouter router;
  late final ProviderContainer container;

  /// 运行期改活跃会话标题（驱动 displayTitle 监听）。
  void setChatDisplayTitle(String title) => chatControllers.setDisplayTitle(title);

  Future<void> pump(WidgetTester tester, {bool isDesktop = true}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: DesktopLifecycleObserver(
          isDesktop: isDesktop,
          child: CupertinoApp.router(routerConfig: router),
        ),
      ),
    );
    // 第一帧结束 → postFrameCallback → _initDesktopServices 的异步链。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const SessionSummary _listSession = SessionSummary(
  sessionId: 'sess-from-list',
  title: '列表标题',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // -------------------------------------------------------------------------
  group('DesktopLifecycleObserver 平台开关与窗口事件', () {
    testWidgets('didChangeLocales：桌面端刷新托盘菜单，非桌面端安全 no-op', (
      tester,
    ) async {
      final desktop = _ObserverHarness();
      await desktop.pump(tester);
      expect(desktop.tray.scheduleCount, 0);

      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('zh'),
      ];
      await tester.pump();
      expect(desktop.tray.scheduleCount, 1);

      // 再变更一次系统语言：仍然只有节流刷新一条路径。
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('en'),
      ];
      await tester.pump();
      expect(desktop.tray.scheduleCount, 2);
      tester.binding.platformDispatcher.clearLocalesTestValue();
    });

    testWidgets('非桌面平台：语言变更与启动初始化都不触碰桌面服务', (tester) async {
      final harness = _ObserverHarness(
        sidecarConfig: const SidecarConfig(enabled: true),
      );
      await harness.pump(tester, isDesktop: false);

      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('zh'),
      ];
      await tester.pump();

      expect(harness.tray.scheduleCount, 0);
      expect(harness.tray.initializeCount, 0);
      expect(harness.title.resetCount, 0);
      expect(harness.memory.initializeCount, 0);
      expect(harness.shortcuts.registerCount, 0);
      expect(harness.sidecarService.startCallCount, 0);
      tester.binding.platformDispatcher.clearLocalesTestValue();
    });
  });

  // -------------------------------------------------------------------------
  group('DesktopLifecycleObserver 启动服务初始化', () {
    testWidgets('桌面端启动：标题重置 → 托盘 → 窗口记忆 → 快捷键全部初始化', (
      tester,
    ) async {
      final harness = _ObserverHarness();
      await harness.pump(tester);

      expect(harness.title.resetCount, 1);
      expect(harness.tray.initializeCount, 1);
      expect(harness.memory.initializeCount, 1);
      expect(harness.memory.restoreCount, 1);
      expect(harness.shortcuts.registerCount, 1);
      expect(harness.sidecarService.startCallCount, 0);
    });

    testWidgets('enabled=true 且 sidecar 状态未就绪：初始化链主动拉起服务', (
      tester,
    ) async {
      final harness = _ObserverHarness(
        sidecarConfig: const SidecarConfig(enabled: true),
        // start() 不自行推进到 running，制造「配置已启用但状态仍未就绪」。
        sidecarEmitsRunningOnStart: false,
      );
      await harness.pump(tester);

      expect(harness.storage.config.enabled, isTrue);
      expect(harness.sidecarService.startCallCount, 2); // 配置监听 + 初始化链
      expect(
        harness.container.read(webuiSidecarControllerProvider).status,
        SidecarStatus.stopped,
      );
    });

    testWidgets('初始化链异常：吞没错误并中断后续服务初始化', (tester) async {
      final throwing = _ThrowingTitleService();
      final harness = _ObserverHarness(titleServiceOverride: throwing);
      await harness.pump(tester);

      expect(throwing.resetCount, 1);
      // 首个 await 抛错后被 catch 吞没：托盘/记忆/快捷键链未继续。
      expect(harness.tray.initializeCount, 0);
      expect(harness.memory.initializeCount, 0);
      expect(harness.shortcuts.registerCount, 0);
      expect(find.byType(DesktopLifecycleObserver), findsOneWidget);
      tester.takeException(); // 断言未抛出给测试框架（catch 已吞没）
    });
  });

  // -------------------------------------------------------------------------
  group('DesktopLifecycleObserver 路由与窗口标题联动', () {
    testWidgets('chat 路由 → activeSessionId 写入 + 聊天标题上窗', (tester) async {
      final harness = _ObserverHarness(
        initialLocation: '/chat/sess-title',
        chatDisplayTitle: '真实标题',
      );
      await harness.pump(tester);

      expect(harness.container.read(activeSessionIdProvider), 'sess-title');
      expect(harness.title.sessionTitles, contains('真实标题'));
    });

    testWidgets('chat 子路由导航 → activeSessionId 跟随路由变化', (tester) async {
      final harness = _ObserverHarness(
        initialLocation: '/settings',
        chatDisplayTitle: '真实标题',
      );
      await harness.pump(tester);
      expect(harness.container.read(activeSessionIdProvider), isNull);

      harness.router.go('/chat/sess-b');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(harness.container.read(activeSessionIdProvider), 'sess-b');
      expect(harness.title.sessionTitles, contains('真实标题'));
    });

    testWidgets('workspace / git 详情路由同样识别为活跃会话', (tester) async {
      final harness = _ObserverHarness(chatDisplayTitle: '真实标题');
      await harness.pump(tester);
      expect(harness.container.read(activeSessionIdProvider), isNull);

      harness.router.go('/workspace/ws-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(harness.container.read(activeSessionIdProvider), 'ws-1');

      harness.router.go('/git/repo-9');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(harness.container.read(activeSessionIdProvider), 'repo-9');

      // 非 chat/workspace/git 前缀 → 不认作活跃会话。
      harness.router.go('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(harness.container.read(activeSessionIdProvider), isNull);
    });

    testWidgets('非 chat 路由 → activeSessionId 清空并重置窗口标题', (tester) async {
      final harness = _ObserverHarness(
        initialLocation: '/chat/sess-c',
        chatDisplayTitle: '真实标题',
      );
      await harness.pump(tester);
      final resetsBefore = harness.title.resetCount;

      harness.router.go('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(harness.container.read(activeSessionIdProvider), isNull);
      expect(harness.title.resetCount, resetsBefore + 1);
    });

    testWidgets('聊天标题为空/占位时回退会话列表标题', (tester) async {
      final harness = _ObserverHarness(
        initialLocation: '/chat/sess-from-list',
        chatDisplayTitle: 'Untitled Session',
        sessions: const <SessionSummary>[_listSession],
      );
      await harness.pump(tester);

      expect(harness.title.sessionTitles, contains('列表标题'));
    });

    testWidgets('聊天标题与会话列表都取不到时回退原始标题', (tester) async {
      final harness = _ObserverHarness(
        initialLocation: '/chat/sess-unknown',
        // 小写 untitled 命中占位名判定，同时非空 → 走到兜底分支。
        chatDisplayTitle: 'untitled',
        sessions: const <SessionSummary>[_listSession],
      );
      await harness.pump(tester);

      expect(harness.title.sessionTitles, isNotEmpty);
      expect(harness.title.sessionTitles.last, 'untitled');
      expect(harness.title.sessionTitles, isNot(contains('列表标题')));
    });

    testWidgets('活跃会话标题运行期变更 → 同步窗口标题', (tester) async {
      final harness = _ObserverHarness(
        initialLocation: '/chat/sess-live',
        chatDisplayTitle: 'Untitled Session',
        sessions: const <SessionSummary>[_listSession],
      );
      await harness.pump(tester);
      final before = harness.title.sessionTitles.length;

      harness.setChatDisplayTitle('改后的标题');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(harness.title.sessionTitles.length, before + 1);
      expect(harness.title.sessionTitles.last, '改后的标题');
    });
  });

  // -------------------------------------------------------------------------
  group('DesktopLifecycleObserver 设置变更监听', () {
    testWidgets('全局快捷键开关翻转 → 注册/注销对应服务', (tester) async {
      final harness = _ObserverHarness();
      await harness.pump(tester);
      final registers = harness.shortcuts.registerCount;

      await harness.container
          .read(desktopSettingsProvider.notifier)
          .setGlobalShortcutsEnabled(false);
      await tester.pump();
      expect(harness.shortcuts.unregisterCount, 1);
      expect(harness.shortcuts.registerCount, registers);

      await harness.container
          .read(desktopSettingsProvider.notifier)
          .setGlobalShortcutsEnabled(true);
      await tester.pump();
      expect(harness.shortcuts.registerCount, registers + 1);
    });

    testWidgets('最小化到托盘开关翻转 → 同步 windowManager.setPreventClose', (
      tester,
    ) async {
      final preventCloseCalls = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (call.method == 'setPreventClose') {
            final args = call.arguments as Map<Object?, Object?>;
            preventCloseCalls.add(args['isPreventClose'] as bool);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        ),
      );

      final harness = _ObserverHarness();
      await harness.pump(tester);
      expect(preventCloseCalls, isEmpty);

      await harness.container
          .read(desktopSettingsProvider.notifier)
          .setMinimizeToTray(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(preventCloseCalls, <bool>[false]);
    });
  });

  // -------------------------------------------------------------------------
  group('DesktopLifecycleObserver 托盘菜单联动', () {
    testWidgets('会话列表变化 → 用新列表刷新托盘上下文菜单', (tester) async {
      final harness = _ObserverHarness();
      await harness.pump(tester);
      final before = harness.tray.updateContextMenuCount;

      harness.sessionList.emitSessions(const <SessionSummary>[_listSession]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(harness.tray.updateContextMenuCount, before + 1);
      expect(
        harness.tray.lastMenuSessions?.map((s) => s.sessionId),
        <String>['sess-from-list'],
      );
    });

    testWidgets('sidecar host/port 变更 → 触发托盘菜单节流刷新', (tester) async {
      final harness = _ObserverHarness();
      await harness.pump(tester);
      final before = harness.tray.scheduleCount;

      await harness.container
          .read(webuiSidecarConfigProvider.notifier)
          .setHost('0.0.0.0');
      await tester.pump();
      expect(harness.tray.scheduleCount, before + 1);

      await harness.container
          .read(webuiSidecarConfigProvider.notifier)
          .setPort(9911);
      await tester.pump();
      expect(harness.tray.scheduleCount, before + 2);
      expect(
        harness.container.read(webuiSidecarConfigProvider).host,
        '0.0.0.0',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('ColdStartGraceState 值语义', () {
    test('copyWith：无参保持等值，指定字段可覆盖/清除', () {
      const base = ColdStartGraceState(
        phase: ColdStartGracePhase.active,
        pendingActionError: '离线缓存：当前显示最近缓存的会话',
      );

      final copied = base.copyWith();
      expect(identical(copied, base), isFalse);
      expect(copied, equals(base));
      expect(copied.hashCode, base.hashCode);
      expect(copied.isActive, isTrue);

      final resolved = base.copyWith(phase: ColdStartGracePhase.resolved);
      expect(resolved.phase, ColdStartGracePhase.resolved);
      expect(resolved.pendingActionError, base.pendingActionError);
      expect(resolved.isActive, isFalse);

      final replaced = base.copyWith(pendingActionError: () => '新错误');
      expect(replaced.pendingActionError, '新错误');
      expect(replaced.phase, ColdStartGracePhase.active);

      final cleared = base.copyWith(pendingActionError: () => null);
      expect(cleared.pendingActionError, isNull);
      expect(cleared.phase, ColdStartGracePhase.active);
    });

    test('operator== / hashCode 遵循值语义', () {
      const a = ColdStartGraceState(
        phase: ColdStartGracePhase.expired,
        pendingActionError: 'x',
      );
      const b = ColdStartGraceState(
        phase: ColdStartGracePhase.expired,
        pendingActionError: 'x',
      );
      const noError = ColdStartGraceState(phase: ColdStartGracePhase.expired);

      // 注意：两个内容相同的 const 实例会被 Dart 规范化成同一对象，
      // 因此这里用运行期构造的副本验证「非同一实例但相等」。
      final runtimeCopy = ColdStartGraceState(
        phase: a.phase,
        pendingActionError: a.pendingActionError,
      );
      expect(identical(a, runtimeCopy), isFalse);
      expect(identical(a, b), isTrue);
      expect(a, equals(b));
      expect(a, equals(runtimeCopy));
      expect(a.hashCode, b.hashCode);
      expect(a.hashCode, runtimeCopy.hashCode);
      expect(a == noError, isFalse);
      expect(
        a ==
            const ColdStartGraceState(
              phase: ColdStartGracePhase.idle,
              pendingActionError: 'x',
            ),
        isFalse,
      );
      expect(a == Object(), isFalse);
      expect(const ColdStartGraceState().phase, ColdStartGracePhase.idle);
      expect(const ColdStartGraceState().isActive, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('ColdStartGraceController 轮询与守卫', () {
    test('健康探测就绪 → resolved 并触发会话列表刷新', () {
      fakeAsync((async) {
        final checker = _FakeHealthChecker(isHealthy: true);
        final sessionList = _FakeSessionListController();
        final container = ProviderContainer(
          overrides: <Override>[
            sessionListControllerProvider.overrideWith(() => sessionList),
            sidecarHealthCheckerProvider.overrideWithValue(checker),
            coldStartGraceTimeoutProvider.overrideWithValue(
              const Duration(seconds: 5),
            ),
            coldStartGraceIntervalProvider.overrideWithValue(
              const Duration(seconds: 1),
            ),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          coldStartGraceControllerProvider.notifier,
        );
        controller.startGrace(pendingActionError: '离线缓存：当前显示最近缓存的会话');
        async.flushMicrotasks();

        // startGrace 末尾的首次探测即命中健康 → 就绪恢复。
        expect(checker.callCount, 1);
        expect(
          container.read(coldStartGraceControllerProvider).phase,
          ColdStartGracePhase.resolved,
        );
        expect(sessionList.refreshCallCount, 1);

        // 定时器已取消：继续推进不再探测、不再补发错误。
        async.elapse(const Duration(seconds: 5));
        expect(checker.callCount, 1);
        expect(sessionList.appliedTimeoutError, isNull);
      });
    });

    test('轮询定时器残活而状态已非 active → 入口守卫自行停表', () {
      fakeAsync((async) {
        final checker = _FakeHealthChecker(isHealthy: false);
        final sessionList = _FakeSessionListController();
        final container = ProviderContainer(
          overrides: <Override>[
            sessionListControllerProvider.overrideWith(() => sessionList),
            sidecarHealthCheckerProvider.overrideWithValue(checker),
            coldStartGraceTimeoutProvider.overrideWithValue(
              const Duration(seconds: 30),
            ),
            coldStartGraceIntervalProvider.overrideWithValue(
              const Duration(seconds: 1),
            ),
            coldStartGraceControllerProvider.overrideWith(
              _ProbeGraceController.new,
            ),
          ],
        );
        addTearDown(container.dispose);

        final controller =
            container.read(coldStartGraceControllerProvider.notifier)
                as _ProbeGraceController;
        controller.startGrace(pendingActionError: '离线缓存：当前显示最近缓存的会话');
        async.flushMicrotasks();
        expect(checker.callCount, 1); // startGrace 末尾首次探测

        async.elapse(const Duration(seconds: 1));
        expect(checker.callCount, 2); // 周期首拍

        // 白盒：直接把状态拨离 active，定时器保持存活（公开 API 下不可达）。
        controller.forceIdleForTest();
        expect(
          container.read(coldStartGraceControllerProvider).phase,
          ColdStartGracePhase.idle,
        );

        async.elapse(const Duration(seconds: 1));
        expect(checker.callCount, 2); // 守卫命中：本轮不再探测
        async.elapse(const Duration(seconds: 10));
        expect(checker.callCount, 2); // 且已自行停表，再无探测
      });
    });
  });
}
