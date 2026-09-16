import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/desktop/tray_manager_service.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../helpers/fake_session_list_api.dart';

// ---------------------------------------------------------------------------
// 平台通道 mock 基建
//
// 沿用 tray_manager_service_test.dart 的同一套手法：只 mock `tray_manager` /
// `window_manager` 两个 MethodChannel（这两个包都直接 `invokeMethod`）。
// 本文件额外补两件既有测试没做的事：
//   1) 可注入的「指定方法抛错」开关 —— 覆盖各 catch 分支；
//   2) 反向派发原生事件（handlePlatformMessage）—— 覆盖 buildMenuItems 回调闭包。
// ---------------------------------------------------------------------------

const String _trayChannelName = 'tray_manager';
const String _windowChannelName = 'window_manager';

class _ChannelMock {
  _ChannelMock(this.name);

  final String name;
  final List<MethodCall> calls = <MethodCall>[];
  final Set<String> throwingMethods = <String>{};
  Map<String, dynamic>? lastContextMenuPayload;

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(MethodChannel(name), _handle);
  }

  void uninstall() {
    _messenger.setMockMethodCallHandler(MethodChannel(name), null);
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    if (throwingMethods.contains(call.method)) {
      throw PlatformException(
        code: 'mock-failure',
        message: 'mock failure for ${call.method}',
      );
    }
    if (call.method == 'setContextMenu') {
      final args = call.arguments;
      if (args is Map && args['menu'] is Map) {
        lastContextMenuPayload = Map<String, dynamic>.from(args['menu'] as Map);
      }
    }
    // windowManager.show() 内部先问 isMinimized，必须回 bool。
    if (call.method == 'isMinimized') return false;
    return null;
  }

  int countOf(String method) => calls.where((c) => c.method == method).length;

  bool called(String method) => calls.any((c) => c.method == method);

  MethodCall? lastOf(String method) {
    for (final call in calls.reversed) {
      if (call.method == method) return call;
    }
    return null;
  }
}

late _ChannelMock _trayChannel;
late _ChannelMock _windowChannel;

/// 从托盘菜单序列化载荷里按 key 取菜单项 id。
int? _menuItemIdByKey(Map<String, dynamic>? menu, String key) {
  final items = menu?['items'];
  if (items is! List) return null;
  for (final entry in items) {
    if (entry is Map && entry['key'] == key) return entry['id'] as int?;
  }
  return null;
}

/// 在指定平台语义下执行（覆盖 [_setupTrayIcon] 的平台三态分支）。
Future<T> _withPlatform<T>(
  TargetPlatform platform,
  Future<T> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    return await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

// ---------------------------------------------------------------------------
// fake 依赖
// ---------------------------------------------------------------------------

class _FakeSidecarService implements WebuiSidecarService {
  _FakeSidecarService({
    this.onStop,
    this.throwOnStates = false,
    SidecarState initialState = SidecarState.initial,
  }) : _state = initialState;

  final Future<void> Function()? onStop;
  final bool throwOnStates;
  SidecarState _state;
  final StreamController<SidecarState> _controller =
      StreamController<SidecarState>.broadcast();

  int stopCallCount = 0;

  @override
  SidecarState get currentState => _state;

  @override
  Stream<SidecarState> get states {
    if (throwOnStates) {
      throw StateError('sidecar states unavailable');
    }
    return _controller.stream;
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    stopCallCount++;
    final hook = onStop;
    if (hook != null) await hook();
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

class _RecordingUrlLauncher extends UrlLauncherPlatform {
  String? launchedUrl;
  LaunchOptions? lastOptions;
  bool throwOnLaunch = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (throwOnLaunch) {
      throw PlatformException(code: 'launch-failed');
    }
    launchedUrl = url;
    lastOptions = options;
    return true;
  }
}

class _FixedActiveConnectionController extends ActiveConnectionController {
  @override
  ServerConnection? build() => ServerConnection(
    id: 'conn-tray-test',
    name: 'Tray Test',
    baseUrl: 'http://127.0.0.1:9',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

class _FixedSidecarConfigController extends WebuiSidecarConfigController {
  @override
  SidecarConfig build() =>
      const SidecarConfig(enabled: true, host: '127.0.0.1', port: 8787);
}

class _FixedSidecarStateController extends WebuiSidecarController {
  @override
  SidecarState build() => const SidecarState(status: SidecarStatus.running);
}

/// 组装一个可读 trayManagerServiceProvider 的容器（全部外部依赖注入 fake）。
ProviderContainer _makeContainer({
  FakeSessionListApi? listApi,
  _FakeSidecarService? sidecar,
}) {
  final api = listApi ?? FakeSessionListApi();
  final sidecarService = sidecar ?? _FakeSidecarService();
  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://127.0.0.1:9'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      activeConnectionProvider.overrideWith(
        _FixedActiveConnectionController.new,
      ),
      webuiSidecarServiceProvider.overrideWithValue(sidecarService),
      webuiSidecarConfigProvider.overrideWith(
        _FixedSidecarConfigController.new,
      ),
      webuiSidecarControllerProvider.overrideWith(
        _FixedSidecarStateController.new,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 托盘菜单 label 经 LocaleResolver 取语言；钉死中文保住既有断言语义。
  setUp(() {
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    _trayChannel = _ChannelMock(_trayChannelName)..install();
    _windowChannel = _ChannelMock(_windowChannelName)..install();
  });

  tearDown(() {
    _trayChannel.uninstall();
    _windowChannel.uninstall();
    debugDefaultTargetPlatformOverride = null;
    LocaleResolver.reset();
  });

  // _setupTrayIcon 会把图标落盘到系统临时目录（固定文件名），收尾清干净。
  tearDownAll(() {
    for (final name in const [
      'hermes_tray_icon.ico',
      'hermes_tray_icon_32.png',
    ]) {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$name',
      );
      if (file.existsSync()) file.deleteSync();
    }
  });

  group('prepareTrayIconFile 默认参数（assetBundle / tempDir 缺省）', () {
    test('不传 assetBundle/tempDir 时走 rootBundle 与系统临时目录', () async {
      final iconPath = await prepareTrayIconFile();
      addTearDown(() {
        final file = File(iconPath);
        if (file.existsSync()) file.deleteSync();
      });

      final file = File(iconPath);
      expect(file.existsSync(), isTrue);
      expect(file.isAbsolute, isTrue);
      expect(iconPath, endsWith('hermes_tray_icon_32.png'));

      // 落盘内容来自真实资产（而非空写）：与磁盘上的源资产逐字节等长。
      final sourceBytes = File('assets/branding/tray_icon_32.png').lengthSync();
      expect(sourceBytes, greaterThan(0));
      expect(file.lengthSync(), sourceBytes);

      // 写入位置 = Directory.systemTemp（默认 tempDir 分支）。
      final tempEntries = Directory.systemTemp.listSync();
      expect(
        tempEntries
            .map((e) => e.path.replaceAll(r'\', '/'))
            .where((p) => p.endsWith('/hermes_tray_icon_32.png')),
        isNotEmpty,
      );
    });
  });

  group('initialize 桌面平台接线', () {
    test('桌面平台注册托盘监听/语言监听并设置图标与菜单，重复调用幂等', () async {
      final sidecar = _FakeSidecarService(
        initialState: const SidecarState(status: SidecarStatus.running),
      );
      addTearDown(sidecar.dispose);
      final service = TrayManagerService(
        isDesktop: true,
        sidecarService: sidecar,
      );

      await _withPlatform(TargetPlatform.windows, () => service.initialize());

      expect(service.isInitialized, isTrue);
      expect(_trayChannel.called('setIcon'), isTrue);
      expect(_trayChannel.called('setToolTip'), isTrue);
      expect(_trayChannel.called('setContextMenu'), isTrue);
      // 语言变化监听已注册（L2 接线）。
      expect(LocaleResolver.listenerCount, 1);

      final toolTipArgs = _trayChannel.lastOf('setToolTip')?.arguments as Map?;
      expect(toolTipArgs?['toolTip'], 'Hermes');

      final menuCallsAfterFirst = _trayChannel.countOf('setContextMenu');
      await service.initialize();
      expect(service.isInitialized, isTrue);
      // 幂等：第二次 initialize 提前返回，不再重复设置菜单。
      expect(_trayChannel.countOf('setContextMenu'), menuCallsAfterFirst);
    });

    test('sidecar 状态流推送触发节流刷新（订阅回调接线）', () async {
      final sidecar = _FakeSidecarService(
        initialState: const SidecarState(status: SidecarStatus.stopped),
      );
      addTearDown(sidecar.dispose);
      final service = TrayManagerService(
        isDesktop: true,
        sidecarService: sidecar,
        throttleDuration: const Duration(milliseconds: 10),
      );

      await _withPlatform(TargetPlatform.windows, () => service.initialize());
      final beforeEmit = _trayChannel.countOf('setContextMenu');

      sidecar.emitState(const SidecarState(status: SidecarStatus.running));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await pumpEventQueue();

      expect(_trayChannel.countOf('setContextMenu'), greaterThan(beforeEmit));
      final statusItemLabel = _lastWebuiStatusLabel();
      expect(statusItemLabel, 'WebUI 服务：运行中');

      await service.dispose();
      sidecar.dispose();
    });

    test('sidecar states 抛错时 initialize 吞没异常且保持未初始化', () async {
      final sidecar = _FakeSidecarService(throwOnStates: true);
      addTearDown(sidecar.dispose);
      final service = TrayManagerService(
        isDesktop: true,
        sidecarService: sidecar,
      );

      await _withPlatform(TargetPlatform.windows, () => service.initialize());

      expect(service.isInitialized, isFalse);
      expect(_trayChannel.called('setIcon'), isFalse);
      expect(_trayChannel.called('setContextMenu'), isFalse);
    });

    test('disposeLocaleListener 未注册时安全 no-op，注册后注销使监听数归零', () async {
      final service = TrayManagerService(isDesktop: true);

      // 未 initialize：token 为 null，调用应安全 no-op。
      service.disposeLocaleListener();
      expect(LocaleResolver.listenerCount, 0);

      await _withPlatform(TargetPlatform.windows, () => service.initialize());
      expect(LocaleResolver.listenerCount, 1);

      service.disposeLocaleListener();
      expect(LocaleResolver.listenerCount, 0);

      await service.dispose();
    });
  });

  group('_setupTrayIcon 平台三态分支', () {
    test('macOS 分支使用 AppIcon 相对路径；图标加载失败被吞没但菜单仍建立', () async {
      final service = TrayManagerService(isDesktop: true);

      await _withPlatform(TargetPlatform.macOS, () => service.initialize());

      // macOS 资产不在测试资产包里：setIcon 抛错被 _setupTrayIcon 吞没，
      // initialize 继续走到 updateContextMenu 并置 _initialized = true。
      expect(service.isInitialized, isTrue);
      expect(_trayChannel.called('setIcon'), isFalse);
      expect(_trayChannel.called('setToolTip'), isFalse);
      expect(_trayChannel.called('setContextMenu'), isTrue);

      await service.dispose();
    });

    test('Windows 分支落盘 .ico 并 setIcon/setToolTip 传参正确', () async {
      addTearDown(() {
        final ico = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}hermes_tray_icon.ico',
        );
        if (ico.existsSync()) ico.deleteSync();
      });
      final service = TrayManagerService(isDesktop: true);

      await _withPlatform(TargetPlatform.windows, () => service.initialize());

      expect(service.isInitialized, isTrue);
      final iconArgs = _trayChannel.lastOf('setIcon')?.arguments as Map?;
      expect(iconArgs?['iconPath'], contains('hermes_tray_icon.ico'));
      expect(_trayChannel.called('setToolTip'), isTrue);

      await service.dispose();
    });

    test('非 macOS/Windows 分支走默认 PNG 资产', () async {
      addTearDown(() {
        final png = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}hermes_tray_icon_32.png',
        );
        if (png.existsSync()) png.deleteSync();
      });
      final service = TrayManagerService(isDesktop: true);

      await _withPlatform(TargetPlatform.linux, () => service.initialize());

      expect(service.isInitialized, isTrue);
      final iconArgs = _trayChannel.lastOf('setIcon')?.arguments as Map?;
      expect(iconArgs?['iconPath'], contains('hermes_tray_icon_32.png'));

      await service.dispose();
    });
  });

  group('buildMenuItems 分支与回调接线', () {
    test('sidecarState/sidecarConfig 优先于 sidecarStatus/sidecarEnabled', () {
      final items = TrayManagerService.buildMenuItems(
        sessions: const [
          SessionSummary(sessionId: 's1', title: '甲', messageCount: 3),
        ],
        // status/enabled 说「停止/未启用」，state/config 说「运行/启用」→ 后者胜出。
        sidecarStatus: SidecarStatus.stopped,
        sidecarEnabled: false,
        sidecarState: const SidecarState(status: SidecarStatus.running),
        sidecarConfig: const SidecarConfig(
          enabled: true,
          host: '127.0.0.1',
          port: 8787,
        ),
      );

      final openItem = _itemByKey(items, TrayManagerService.menuItemOpenWebui);
      final statusItem = _itemByKey(
        items,
        TrayManagerService.menuItemWebuiStatus,
      );
      expect(openItem.disabled, isFalse);
      expect(statusItem.label, 'WebUI 服务：运行中');
      final recentItem = _itemByKey(items, 'recent_s1');
      expect(recentItem.label, '甲');
    });

    test('五个菜单项 onClick 接线后逐一点击命中对应回调', () {
      final calls = <String>[];
      final items = TrayManagerService.buildMenuItems(
        sessions: const [
          SessionSummary(sessionId: 's7', title: '七号', messageCount: 2),
        ],
        sidecarState: const SidecarState(status: SidecarStatus.running),
        sidecarConfig: const SidecarConfig(enabled: true),
        onShowWindow: () => calls.add('show'),
        onNewSession: () => calls.add('new'),
        onOpenWebui: () => calls.add('webui'),
        onQuit: () => calls.add('quit'),
        onOpenSession: (sid) => calls.add('open:$sid'),
      );

      for (final key in const [
        TrayManagerService.menuItemShowWindow,
        TrayManagerService.menuItemNewSession,
        TrayManagerService.menuItemOpenWebui,
        TrayManagerService.menuItemQuitApp,
        'recent_s7',
      ]) {
        final item = _itemByKey(items, key);
        expect(item.onClick, isNotNull, reason: '$key 应接线 onClick');
        item.onClick!(item);
      }

      expect(calls, ['show', 'new', 'webui', 'quit', 'open:s7']);
    });

    test('无回调时 onClick 为 null 且「暂无最近会话」项禁用', () {
      final items = TrayManagerService.buildMenuItems(
        sidecarState: const SidecarState(status: SidecarStatus.stopped),
        sidecarConfig: const SidecarConfig(enabled: false),
      );

      expect(
        _itemByKey(items, TrayManagerService.menuItemShowWindow).onClick,
        isNull,
      );
      expect(
        _itemByKey(items, TrayManagerService.menuItemNewSession).onClick,
        isNull,
      );
      expect(
        _itemByKey(items, TrayManagerService.menuItemOpenWebui).onClick,
        isNull,
      );
      expect(
        _itemByKey(items, TrayManagerService.menuItemQuitApp).onClick,
        isNull,
      );
      final empty = _itemByKey(
        items,
        TrayManagerService.menuItemNoRecentSessions,
      );
      expect(empty.disabled, isTrue);
      expect(empty.label, '暂无最近会话');
    });
  });

  group('节流刷新与 refreshMenu', () {
    test('scheduleThrottledUpdateContextMenu 窗口内多次调用合并为一次补刷', () async {
      final service = TrayManagerService(
        isDesktop: true,
        throttleDuration: const Duration(milliseconds: 30),
      );

      service.scheduleThrottledUpdateContextMenu();
      await pumpEventQueue();
      expect(_trayChannel.countOf('setContextMenu'), 1);

      // 节流窗口内再次调用：只置 pending，不再立即刷新。
      service.scheduleThrottledUpdateContextMenu();
      await pumpEventQueue();
      expect(_trayChannel.countOf('setContextMenu'), 1);

      // 窗口到期 → 补刷一次。
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await pumpEventQueue();
      expect(_trayChannel.countOf('setContextMenu'), 2);

      await service.dispose();
    });

    test('refreshMenu throttled=false 立即刷新，throttled=true 走节流', () async {
      final service = TrayManagerService(
        isDesktop: true,
        throttleDuration: const Duration(milliseconds: 30),
      );

      await service.refreshMenu(throttled: false);
      await pumpEventQueue();
      expect(_trayChannel.countOf('setContextMenu'), 1);

      await service.refreshMenu();
      await pumpEventQueue();
      expect(_trayChannel.countOf('setContextMenu'), 2);

      await service.dispose();
    });

    test('非桌面平台节流刷新直接返回，不产生任何通道调用', () {
      final service = TrayManagerService(isDesktop: false);
      service.scheduleThrottledUpdateContextMenu();
      expect(_trayChannel.calls, isEmpty);
    });
  });

  group('updateContextMenu 会话来源与 sidecar 回退链', () {
    test('显式 sessions 入参 + sidecarStatus/sidecarEnabled 短路分支', () async {
      final service = TrayManagerService(isDesktop: true);
      await service.updateContextMenu(
        sessions: const [
          SessionSummary(sessionId: 'a1', title: '甲', messageCount: 1),
        ],
        sidecarStatus: SidecarStatus.running,
        sidecarEnabled: true,
      );

      final menu = _trayChannel.lastContextMenuPayload;
      expect(_menuItemIdByKey(menu, 'recent_a1'), isNotNull);
      expect(_menuItemByKeyFromPayload(menu, 'webui_status'), 'WebUI 服务：运行中');
      expect(
        _menuItemDisabledByKey(menu, TrayManagerService.menuItemOpenWebui),
        isFalse,
      );

      await service.dispose();
    });

    test(
      '传入 sessions=null 时 getRecentSessions 优先于 fetchRecentSessions',
      () async {
        var fetchCalled = false;
        final service = TrayManagerService(
          isDesktop: true,
          getRecentSessions: () => const [
            SessionSummary(sessionId: 'cached0', title: '缓存', messageCount: 1),
          ],
          fetchRecentSessions: () async {
            fetchCalled = true;
            return const [
              SessionSummary(sessionId: 'remote', title: '远程', messageCount: 1),
            ];
          },
        );

        await service.updateContextMenu();

        expect(fetchCalled, isFalse);
        expect(
          _menuItemIdByKey(
            _trayChannel.lastContextMenuPayload,
            'recent_cached0',
          ),
          isNotNull,
        );

        await service.dispose();
      },
    );

    test('getRecentSessions 返回 null 时保留既有缓存', () async {
      final service = TrayManagerService(
        isDesktop: true,
        getRecentSessions: () => null,
      );

      await service.updateContextMenu(
        sessions: const [
          SessionSummary(sessionId: 'seed', title: '种子', messageCount: 1),
        ],
      );
      await service.updateContextMenu();
      await service.updateContextMenu();

      final menu = _trayChannel.lastContextMenuPayload;
      expect(_menuItemIdByKey(menu, 'recent_seed'), isNotNull);
      expect(_menuItemIdByKey(menu, 'no_recent_sessions'), isNull);

      await service.dispose();
    });

    test('无 getRecentSessions 时回退 fetchRecentSessions 成功路', () async {
      final service = TrayManagerService(
        isDesktop: true,
        fetchRecentSessions: () async => const [
          SessionSummary(sessionId: 'r1', title: '远端一', messageCount: 2),
        ],
      );

      await service.updateContextMenu();

      expect(
        _menuItemIdByKey(_trayChannel.lastContextMenuPayload, 'recent_r1'),
        isNotNull,
      );

      await service.dispose();
    });

    test('fetchRecentSessions 抛错被吞没且菜单仍建立', () async {
      var attempt = 0;
      final service = TrayManagerService(
        isDesktop: true,
        fetchRecentSessions: () async {
          attempt++;
          throw StateError('fetch failed');
        },
      );

      await service.updateContextMenu();

      expect(attempt, 1);
      final menu = _trayChannel.lastContextMenuPayload;
      expect(
        _menuItemIdByKey(menu, TrayManagerService.menuItemNoRecentSessions),
        isNotNull,
      );

      await service.dispose();
    });

    test('fetchRecentSessions 返回 null 时保留缓存', () async {
      final service = TrayManagerService(
        isDesktop: true,
        fetchRecentSessions: () async => null,
      );

      await service.updateContextMenu(
        sessions: const [
          SessionSummary(sessionId: 'keep', title: '保留', messageCount: 1),
        ],
      );
      await service.updateContextMenu();

      expect(
        _menuItemIdByKey(_trayChannel.lastContextMenuPayload, 'recent_keep'),
        isNotNull,
      );

      await service.dispose();
    });

    test('无 getSidecarState/getSidecarConfig 时回退 sidecarService 与缓存', () async {
      final sidecar = _FakeSidecarService(
        initialState: const SidecarState(status: SidecarStatus.failed),
      );
      addTearDown(sidecar.dispose);
      final service = TrayManagerService(
        isDesktop: true,
        sidecarService: sidecar,
      );

      await service.updateContextMenu();

      expect(
        _menuItemByKeyFromPayload(
          _trayChannel.lastContextMenuPayload,
          TrayManagerService.menuItemWebuiStatus,
        ),
        'WebUI 服务：失败',
      );

      await service.dispose();
    });

    test('getSidecarState 返回值优先于 sidecarService', () async {
      final sidecar = _FakeSidecarService(
        initialState: const SidecarState(status: SidecarStatus.failed),
      );
      addTearDown(sidecar.dispose);
      final service = TrayManagerService(
        isDesktop: true,
        sidecarService: sidecar,
        getSidecarState: () =>
            const SidecarState(status: SidecarStatus.starting),
      );

      await service.updateContextMenu();

      expect(
        _menuItemByKeyFromPayload(
          _trayChannel.lastContextMenuPayload,
          TrayManagerService.menuItemWebuiStatus,
        ),
        'WebUI 服务：启动中',
      );

      await service.dispose();
    });

    test('setContextMenu 抛错被吞没（不向调用方冒泡）', () async {
      _trayChannel.throwingMethods.add('setContextMenu');
      final service = TrayManagerService(
        isDesktop: true,
        getRecentSessions: () => const [
          SessionSummary(sessionId: 'x', title: 'X', messageCount: 1),
        ],
      );

      await service.updateContextMenu();

      expect(_trayChannel.called('setContextMenu'), isTrue);
      // 菜单构建已发生（抛错点在通道层），缓存仍被写入。
      await service.updateContextMenu();
      expect(_trayChannel.countOf('setContextMenu'), 2);

      await service.dispose();
    });

    test('菜单项一律不挂 onClick（去双回调）+ onTrayMenuItemClick 按 key 各分发一次', () async {
      final hits = <String>[];
      final service = TrayManagerService(
        isDesktop: true,
        onShowWindow: () => hits.add('show'),
        onNewSession: () => hits.add('new'),
        onOpenWebui: () => hits.add('webui'),
        onQuit: () => hits.add('quit'),
        onOpenSession: (sid) => hits.add('open:$sid'),
        getRecentSessions: () => const [
          SessionSummary(sessionId: 's3', title: '三号', messageCount: 2),
        ],
        getSidecarState: () =>
            const SidecarState(status: SidecarStatus.running),
        getSidecarConfig: () => const SidecarConfig(enabled: true),
      );

      await service.updateContextMenu();
      final menu = _trayChannel.lastContextMenuPayload;
      expect(menu, isNotNull);

      // ① #12 修复守卫：菜单项一律【不挂】onClick。
      //    tray_manager 0.5.3 的原生分发会先调 menuItem.onClick，再【无条件】调
      //    listener.onTrayMenuItemClick（tray_manager.dart:61-64）；两处都接线会让
      //    每次点击触发两次业务回调（handleQuit 重复 stop sidecar，第二次等满 5s
      //    超时，退出肉眼可见变慢）。
      final items = (menu!['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(
          item['onClick'],
          isNull,
          reason: '菜单项不应挂 onClick：${item['key']}',
        );
      }

      // ② 服务侧 key 分发是【唯一】入口：每个菜单项恰好一次。
      for (final key in const [
        TrayManagerService.menuItemShowWindow,
        TrayManagerService.menuItemNewSession,
        TrayManagerService.menuItemOpenWebui,
        'recent_s3',
        TrayManagerService.menuItemQuitApp,
      ]) {
        final id = _menuItemIdByKey(menu, key);
        expect(id, isNotNull, reason: '$key 应出现在菜单载荷里');
        service.onTrayMenuItemClick(MenuItem(key: key, label: ''));
        await pumpEventQueue();
      }

      expect(hits, ['show', 'new', 'webui', 'open:s3', 'quit']);

      await service.dispose();
    });
  });

  group('handleXxx 无自定义回调时的 windowManager 兜底', () {
    test('handleShowWindow 走 windowManager.show/focus', () async {
      final service = TrayManagerService(isDesktop: false);
      await service.handleShowWindow();
      expect(_windowChannel.called('show'), isTrue);
      expect(_windowChannel.called('focus'), isTrue);
    });

    test('handleShowWindow 兜底抛错被吞没', () async {
      _windowChannel.throwingMethods.add('show');
      final service = TrayManagerService(isDesktop: false);

      await service.handleShowWindow();

      expect(_windowChannel.called('show'), isTrue);
      expect(_windowChannel.called('focus'), isFalse);
    });

    test('handleNewSession 走 windowManager 且兜底抛错被吞没', () async {
      final service = TrayManagerService(isDesktop: false);
      await service.handleNewSession();
      expect(_windowChannel.called('show'), isTrue);
      expect(_windowChannel.called('focus'), isTrue);

      _windowChannel.throwingMethods.add('show');
      final beforeFocus = _windowChannel.countOf('focus');
      final failing = TrayManagerService(isDesktop: false);
      await failing.handleNewSession();
      expect(_windowChannel.countOf('focus'), beforeFocus);
    });

    test('handleOpenSession 走 windowManager 且兜底抛错被吞没', () async {
      final service = TrayManagerService(isDesktop: false);
      await service.handleOpenSession('sess-abc');
      expect(_windowChannel.called('show'), isTrue);
      expect(_windowChannel.called('focus'), isTrue);

      _windowChannel.throwingMethods.add('show');
      final beforeFocus = _windowChannel.countOf('focus');
      final failing = TrayManagerService(isDesktop: false);
      await failing.handleOpenSession('sess-def');
      expect(_windowChannel.countOf('focus'), beforeFocus);
    });
  });

  group('handleOpenWebui 回退链与失败吞没', () {
    test(
      '无 getSidecarState/getSidecarConfig 时从 sidecarService 取即时状态',
      () async {
        final sidecar = _FakeSidecarService(
          initialState: const SidecarState(status: SidecarStatus.running),
        );
        addTearDown(sidecar.dispose);
        final launcher = _RecordingUrlLauncher();
        final oldLauncher = UrlLauncherPlatform.instance;
        UrlLauncherPlatform.instance = launcher;
        addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);

        final service = TrayManagerService(
          isDesktop: false,
          sidecarService: sidecar,
          getSidecarConfig: () =>
              const SidecarConfig(enabled: true, host: '127.0.0.1', port: 8787),
        );

        await service.handleOpenWebui();

        expect(launcher.launchedUrl, 'http://127.0.0.1:8787');
      },
    );

    test('onOpenWebui 自定义回调短路（不调 url_launcher）', () async {
      final launcher = _RecordingUrlLauncher();
      final oldLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);

      var opened = 0;
      final service = TrayManagerService(
        isDesktop: false,
        onOpenWebui: () => opened++,
        getSidecarState: () =>
            const SidecarState(status: SidecarStatus.running),
        getSidecarConfig: () =>
            const SidecarConfig(enabled: true, host: '127.0.0.1', port: 8787),
      );

      await service.handleOpenWebui();

      expect(opened, 1);
      expect(launcher.launchedUrl, isNull);
    });

    test(
      '无 getSidecarState 且无 sidecarService 时回退 updateContextMenu 写入的缓存',
      () async {
        final launcher = _RecordingUrlLauncher();
        final oldLauncher = UrlLauncherPlatform.instance;
        UrlLauncherPlatform.instance = launcher;
        addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);

        // 全新实例：缓存是 initial(stopped)，无任何即时状态源 → 不应打开。
        final cacheCold = TrayManagerService(isDesktop: true);
        await cacheCold.handleOpenWebui();
        expect(launcher.launchedUrl, isNull);

        // 先用 updateContextMenu 把 running / enabled=true 写进缓存。
        final service = TrayManagerService(isDesktop: true);
        await service.updateContextMenu(
          sidecarStatus: SidecarStatus.running,
          sidecarEnabled: true,
        );

        await service.handleOpenWebui();

        expect(launcher.launchedUrl, 'http://127.0.0.1:8787');
        expect(
          launcher.lastOptions?.mode,
          PreferredLaunchMode.externalApplication,
        );

        await service.dispose();
      },
    );

    test('launchUrl 抛错被吞没', () async {
      final launcher = _RecordingUrlLauncher()..throwOnLaunch = true;
      final oldLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);

      final service = TrayManagerService(
        isDesktop: false,
        getSidecarState: () =>
            const SidecarState(status: SidecarStatus.running),
        getSidecarConfig: () =>
            const SidecarConfig(enabled: true, host: '0.0.0.0', port: 6553),
      );

      // 不应抛出：异常在 handleOpenWebui 内部被吞没。
      await service.handleOpenWebui();

      expect(launcher.launchedUrl, isNull);
    });
  });

  group('handleQuit 停止 sidecar 与窗口销毁', () {
    test('onStopSidecar 自定义回调优先于 sidecarService.stop', () async {
      var stopHookCalls = 0;
      final sidecar = _FakeSidecarService();
      addTearDown(sidecar.dispose);
      final service = TrayManagerService(
        isDesktop: false,
        sidecarService: sidecar,
        onStopSidecar: () async {
          stopHookCalls++;
        },
        onQuit: () {},
      );

      await service.handleQuit();

      expect(stopHookCalls, 1);
      expect(sidecar.stopCallCount, 0);
    });

    test('无 onQuit 时销毁窗口；销毁抛错被吞没', () async {
      final service = TrayManagerService(isDesktop: false);
      await service.handleQuit();
      expect(_windowChannel.countOf('destroy'), 1);

      _windowChannel.throwingMethods.add('destroy');
      final failing = TrayManagerService(isDesktop: false);
      await failing.handleQuit();
      expect(_windowChannel.countOf('destroy'), 2);
    });
  });

  group('托盘事件入口与 dispose', () {
    test('onTrayIconRightMouseDown 弹出上下文菜单', () async {
      final service = TrayManagerService(isDesktop: true);

      service.onTrayIconRightMouseDown();
      await pumpEventQueue();

      expect(_trayChannel.called('popUpContextMenu'), isTrue);

      await service.dispose();
    });

    test('dispose 桌面平台移除监听/销毁托盘/复位初始化标记', () async {
      final service = TrayManagerService(isDesktop: true, onQuit: () {});
      await _withPlatform(TargetPlatform.windows, () => service.initialize());
      expect(service.isInitialized, isTrue);

      await service.dispose();

      expect(service.isInitialized, isFalse);
      expect(_trayChannel.called('destroy'), isTrue);
    });

    test('dispose 时托盘销毁抛错被吞没且仍复位初始化标记', () async {
      final service = TrayManagerService(isDesktop: true);
      await _withPlatform(TargetPlatform.windows, () => service.initialize());
      expect(service.isInitialized, isTrue);

      _trayChannel.throwingMethods.add('destroy');
      await service.dispose();

      expect(service.isInitialized, isFalse);
      expect(_trayChannel.called('destroy'), isTrue);
    });

    test('dispose 非桌面平台不触碰托盘通道', () async {
      final service = TrayManagerService(isDesktop: false);
      await service.dispose();
      expect(_trayChannel.called('destroy'), isFalse);
    });
  });

  group('trayManagerServiceProvider 接线', () {
    test('Provider 回调：唤起窗口 / 新建会话 / 打开会话走 windowManager 与路由', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final service = container.read(trayManagerServiceProvider);
      final router = container.read(routerProvider);

      await service.handleShowWindow();
      expect(_windowChannel.called('show'), isTrue);
      expect(_windowChannel.called('focus'), isTrue);

      await service.handleNewSession();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/chat',
        reason: 'onNewSession 应导航到 /chat',
      );

      await service.handleOpenSession('sess-42');
      expect(
        router.routeInformationProvider.value.uri.path,
        '/chat/sess-42',
        reason: 'onOpenSession 应导航到 /chat/<id>',
      );
    });

    test('Provider 回调：windowManager 抛错时逐路吞没', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final service = container.read(trayManagerServiceProvider);

      _windowChannel.throwingMethods.add('show');
      await service.handleShowWindow();
      await service.handleNewSession();
      await service.handleOpenSession('sess-boom');

      expect(_windowChannel.called('show'), isTrue);
      expect(_windowChannel.called('focus'), isFalse);
    });

    test(
      'Provider 回调：getRecentSessions / fetchRecentSessions 读同一份列表源',
      () async {
        final listApi = FakeSessionListApi(
          sessions: const [
            SessionSummary(sessionId: 'p1', title: '来自列表', messageCount: 1),
          ],
        );
        final container = _makeContainer(listApi: listApi);
        addTearDown(container.dispose);
        final service = container.read(trayManagerServiceProvider);

        // 首帧：会话列表 controller 的异步 build 尚未完成 → valueOrNull 为 null。
        expect(service.getRecentSessions!(), isNull);

        await container.read(sessionListControllerProvider.future);
        final fromController = service.getRecentSessions!();
        expect(fromController, isNotNull);
        expect(fromController!.single.sessionId, 'p1');

        final fetched = await service.fetchRecentSessions!();
        expect(fetched, isNotNull);
        expect(fetched!.single.sessionId, 'p1');
        expect(listApi.fetchCount, greaterThan(0));
      },
    );

    test('Provider 回调：fetchRecentSessions 失败返回 null', () async {
      final listApi = FakeSessionListApi()..fetchError = StateError('boom');
      final container = _makeContainer(listApi: listApi);
      addTearDown(container.dispose);
      final service = container.read(trayManagerServiceProvider);

      expect(await service.fetchRecentSessions!(), isNull);
    });

    test('Provider 回调：onQuit 销毁窗口且抛错吞没', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final service = container.read(trayManagerServiceProvider);

      await service.handleQuit();
      expect(_windowChannel.countOf('destroy'), 1);

      _windowChannel.throwingMethods.add('destroy');
      await service.handleQuit();
      expect(_windowChannel.countOf('destroy'), 2);
    });

    test('Provider 回调：onStopSidecar 停 sidecar 且抛错吞没', () async {
      final sidecar = _FakeSidecarService();
      addTearDown(sidecar.dispose);
      final container = _makeContainer(sidecar: sidecar);
      addTearDown(container.dispose);
      final service = container.read(trayManagerServiceProvider);

      await service.onStopSidecar!();
      expect(sidecar.stopCallCount, 1);

      final failingSidecar = _FakeSidecarService(
        onStop: () async => throw StateError('stop failed'),
      );
      addTearDown(failingSidecar.dispose);
      final failingContainer = _makeContainer(sidecar: failingSidecar);
      addTearDown(failingContainer.dispose);
      final failingService = failingContainer.read(trayManagerServiceProvider);

      await failingService.onStopSidecar!();
      expect(failingSidecar.stopCallCount, 1);
    });

    test('Provider 回调：getSidecarState / getSidecarConfig 读即时快照', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final service = container.read(trayManagerServiceProvider);

      expect(service.getSidecarState!().status, SidecarStatus.running);
      expect(service.getSidecarConfig!().enabled, isTrue);
      expect(service.getSidecarConfig!().port, 8787);
    });
  });
}

MenuItem _itemByKey(List<MenuItem> items, String key) =>
    items.firstWhere((item) => item.key == key);

String? _menuItemByKeyFromPayload(Map<String, dynamic>? menu, String key) {
  final items = menu?['items'];
  if (items is! List) return null;
  for (final entry in items) {
    if (entry is Map && entry['key'] == key) return entry['label'] as String?;
  }
  return null;
}

bool? _menuItemDisabledByKey(Map<String, dynamic>? menu, String key) {
  final items = menu?['items'];
  if (items is! List) return null;
  for (final entry in items) {
    if (entry is Map && entry['key'] == key) return entry['disabled'] as bool?;
  }
  return null;
}

String? _lastWebuiStatusLabel() => _menuItemByKeyFromPayload(
  _trayChannel.lastContextMenuPayload,
  TrayManagerService.menuItemWebuiStatus,
);
