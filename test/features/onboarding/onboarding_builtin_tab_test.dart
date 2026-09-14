import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/models/server_info.dart';
import 'package:hermes_ui/features/desktop/desktop_settings.dart';
import 'package:hermes_ui/features/onboarding/onboarding_page.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_secure_storage.dart';

class _FakeInstallDetector implements InstallDetector {
  bool hasAgent = true;
  bool isBundled = true;

  @override
  bool isWindows = true;

  @override
  String get hermesAgentPath => r'C:\Users\User\AppData\Local\hermes\hermes-agent';

  @override
  String get hermesHomePath => r'C:\Users\User\AppData\Local\hermes';

  @override
  String get localAppDataPath => r'C:\Users\User\AppData\Local';

  @override
  String get webuiPath => r'C:\Users\User\AppData\Local\hermes\webui';

  @override
  Future<bool> agentInstalled() async => hasAgent;

  @override
  bool bundledWebuiAvailable() => isBundled;

  @override
  Future<bool> isInstalled() async => hasAgent;
}

class _FakeSidecarFileSystem implements SidecarFileSystem {
  @override
  bool isWindows = true;
  bool bundleAvailable = true;

  @override
  bool isBundleAvailable() => isWindows && bundleAvailable;

  @override
  String get defaultSidecarDir => r'C:\app\webui';

  @override
  bool directoryExists(String path) => true;

  @override
  String? get envSidecarRoot => null;

  bool Function(String path)? fileExistsOverride;
  String customAgentDir = r'C:\Users\Admin\AppData\Local\hermes\hermes-agent';

  String get hermesAgentDir => customAgentDir;

  @override
  bool fileExists(String path) {
    if (fileExistsOverride != null) {
      return fileExistsOverride!(path);
    }
    return true;
  }

  @override
  String get logDirectoryPath => r'C:\logs';

  @override
  String get logFilePath => r'C:\logs\webui.log';

  @override
  Future<void> appendLogLine(String path, String line) async {}

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  String resolveBundleDir() => r'C:\app\webui';

  @override
  Future<void> rotateLogIfNeeded(
    String path, {
    int maxSizeBytes = 5 * 1024 * 1024,
  }) async {}
}

class _SpyConnectionStore extends ConnectionStore {
  _SpyConnectionStore({required super.storage, required this.callOrder});

  final List<String> callOrder;
  ServerConnection? lastSaved;

  @override
  Future<void> save(ServerConnection connection) async {
    callOrder.add('upsert');
    lastSaved = connection;
    await super.save(connection);
  }

  @override
  Future<void> setActive(String id) async {
    callOrder.add('setActive');
    await super.setActive(id);
  }
}

class _MockWebuiSidecarService implements WebuiSidecarService {
  _MockWebuiSidecarService({SidecarState? initialState, this.onStart})
      : _state = initialState ?? SidecarState.initial;

  SidecarState _state;
  final StreamController<SidecarState> _controller =
      StreamController<SidecarState>.broadcast();

  final Future<void> Function()? onStart;
  int startCalls = 0;
  int stopCalls = 0;

  void emitState(SidecarState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  SidecarState get currentState => _state;

  @override
  Stream<SidecarState> get states => _controller.stream;

  @override
  Future<void> start() async {
    startCalls++;
    if (onStart != null) {
      await onStart!();
    } else {
      emitState(const SidecarState(status: SidecarStatus.running, pid: 8888));
    }
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    emitState(const SidecarState(status: SidecarStatus.stopped));
  }

  @override
  Future<void> restart() async {
    emitState(const SidecarState(status: SidecarStatus.running, pid: 8889));
  }
}

class _FakeOnboardingApi implements OnboardingServerApi {
  _FakeOnboardingApi({this.onLogin});

  final void Function(String password)? onLogin;
  int loginCalls = 0;
  String? lastPassword;

  @override
  Future<HealthResponse> health() async => const HealthResponse(status: 'ok');

  @override
  Future<AuthStatusResponse> authStatus() async =>
      const AuthStatusResponse(authEnabled: true);

  @override
  Future<LoginResponse> login(String password) async {
    loginCalls++;
    lastPassword = password;
    onLogin?.call(password);
    return const LoginResponse(ok: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySecureStorage storage;
  late _FakeInstallDetector detector;
  late _FakeSidecarFileSystem fakeFs;
  late _MockWebuiSidecarService mockService;
  late _FakeOnboardingApi fakeApi;
  late List<String> callOrder;
  late _SpyConnectionStore spyStore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = InMemorySecureStorage();
    detector = _FakeInstallDetector();
    fakeFs = _FakeSidecarFileSystem();
    mockService = _MockWebuiSidecarService();
    fakeApi = _FakeOnboardingApi();
    callOrder = <String>[];
    spyStore = _SpyConnectionStore(storage: storage, callOrder: callOrder);
  });

  Widget buildTestApp({
    bool bundledAvailable = true,
    bool isWindows = true,
    GoRouter? router,
  }) {
    // 平台语义走注入：默认 Windows（本文件断言的是 Windows 桌面形态），
    // 传 false 可构造「非 Windows 宿主 → 形态 B」的判别用例。
    fakeFs.isWindows = isWindows;
    final effectiveRouter = router ??
        GoRouter(
          initialLocation: '/onboarding',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Text('HOME_PAGE'),
            ),
            GoRoute(
              path: '/onboarding',
              builder: (context, state) => const OnboardingPage(),
            ),
            GoRoute(
              path: '/install-guide',
              builder: (context, state) => const Text('INSTALL_GUIDE_PAGE'),
            ),
          ],
        );

    return ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(spyStore),
        installDetectorProvider.overrideWithValue(detector),
        sidecarFileSystemProvider.overrideWithValue(fakeFs),
        bundledWebuiAvailableProvider.overrideWithValue(bundledAvailable),
        webuiSidecarServiceProvider.overrideWithValue(mockService),
        onboardingApiFactoryProvider.overrideWithValue((_, _) => fakeApi),
      ],
      child: CupertinoApp.router(
        locale: const Locale('zh'),
        theme: buildCupertinoTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        routerConfig: effectiveRouter,
      ),
    );
  }

  group('TASK U2 — 形态 A/B 判定', () {
    testWidgets('bundledWebuiAvailable=false → 形态 B（分段控件不渲染，渲染远程表单）',
        (tester) async {
      await tester.pumpWidget(buildTestApp(bundledAvailable: false));
      await tester.pumpAndSettle();

      // 分段控件不存在
      expect(
        find.byKey(const ValueKey('onboarding-segmented-control')),
        findsNothing,
      );
      // 远程 URL 输入框与提交按钮存在
      expect(find.byKey(const ValueKey('onboarding-url')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-connect')), findsOneWidget);
      // 内置 Tab 的按钮不存在
      expect(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
        findsNothing,
      );
    });

    testWidgets(
        'bundledWebuiAvailable=true 且 isWindows=false → 形态 B'
        '（形态判定跟随注入的平台语义，不读宿主 Platform.isWindows）',
        (tester) async {
      // 判别用例：宿主是 Windows 时，旧实现（Platform.isWindows）会判成形态 A
      // → 本条即失败。CI(Linux) 上旧的实现同样判不出形态 A，故两头皆可比。
      await tester.pumpWidget(
        buildTestApp(bundledAvailable: true, isWindows: false),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('onboarding-segmented-control')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('onboarding-url')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-connect')), findsOneWidget);
    });

    testWidgets('bundledWebuiAvailable=true → 形态 A（分段控件渲染，默认内置服务 Tab）',
        (tester) async {
      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      // 分段控件存在
      expect(
        find.byKey(const ValueKey('onboarding-segmented-control')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('onboarding-segmented-control')),
          matching: find.text('内置服务'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('onboarding-segmented-control')),
          matching: find.text('连接服务器'),
        ),
        findsOneWidget,
      );

      // 默认选中内置 Tab
      expect(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
        findsOneWidget,
      );
      expect(find.text('启动并连接'), findsOneWidget);
    });
  });

  group('TASK U2 — 默认 Tab 记忆 (onboarding_last_tab)', () {
    testWidgets('无持久化记录时默认选中内置服务 Tab', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
        findsOneWidget,
      );
    });

    testWidgets('持久化记录为 remote 时，首屏默认选中连接服务器 Tab', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_last_tab': 'remote'});

      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      // 远程表单可见
      expect(find.byKey(const ValueKey('onboarding-url')), findsOneWidget);
    });

    testWidgets('切换分段控件将新 Tab 写入 SharedPreferences', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      // 点击切换到远程
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('onboarding-segmented-control')),
          matching: find.text('连接服务器'),
        ),
      );
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('onboarding_last_tab'), 'remote');

      // 再切回内置
      await tester.tap(find.text('内置服务'));
      await tester.pumpAndSettle();

      expect(prefs.getString('onboarding_last_tab'), 'builtin');
    });
  });

  group('TASK U2 — 启动并连接全链 (start -> login -> upsert -> setActive 顺序断言)', () {
    testWidgets('点击「启动并连接」依次执行 start -> login -> upsert -> setActive 并跳转 /',
        (tester) async {
      mockService = _MockWebuiSidecarService(
        onStart: () async {
          callOrder.add('start');
          mockService.emitState(
            const SidecarState(status: SidecarStatus.running, pid: 7777),
          );
        },
      );
      fakeApi = _FakeOnboardingApi(
        onLogin: (_) {
          callOrder.add('login');
        },
      );

      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      // 点击「启动并连接」
      await tester.tap(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // 断言四步执行顺序严格对齐
      expect(callOrder, ['start', 'login', 'upsert', 'setActive']);

      // 断言保存的连接属性
      expect(spyStore.lastSaved, isNotNull);
      expect(spyStore.lastSaved!.id, ServerConnection.builtinId);
      expect(spyStore.lastSaved!.kind, ConnectionKind.builtin);
      expect(spyStore.lastSaved!.enabled, isTrue);

      // 断言路由跳转至首页
      expect(find.text('HOME_PAGE'), findsOneWidget);
    });
  });

  group('TASK U2 — 30s 超时失败', () {
    testWidgets('启动等待 30s 超时转为失败态，就地展示红字与重试按钮', (tester) async {
      final hangingCompleter = Completer<void>();
      addTearDown(() {
        if (!hangingCompleter.isCompleted) hangingCompleter.complete();
      });

      mockService = _MockWebuiSidecarService(
        onStart: () async {
          mockService.emitState(
            const SidecarState(status: SidecarStatus.starting),
          );
          await hangingCompleter.future;
        },
      );

      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      // 点击启动
      await tester.tap(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
      );
      await tester.pump();

      // 推进 30 秒超时
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();

      // 验证就地红字显示「健康超时」
      expect(
        find.byKey(const ValueKey('onboarding-builtin-error-text')),
        findsOneWidget,
      );
      expect(find.textContaining('健康超时'), findsOneWidget);

      // 验证重试按钮存在
      expect(
        find.byKey(const ValueKey('onboarding-builtin-retry-btn')),
        findsOneWidget,
      );

      hangingCompleter.complete();
      await tester.pump();
    });
  });

  group('TASK #76 — 引导页内置 Tab 门禁与 agent 缺失卡', () {
    testWidgets('agentEnvPresent=false 时渲染缺失卡、文案明确、按钮置灰，重检触发 refresh',
        (tester) async {
      var installed = false;
      final expectedVenv = '${fakeFs.customAgentDir}\\venv\\Scripts\\python.exe';
      fakeFs.fileExistsOverride = (path) => installed && path == expectedVenv;

      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      // 验证卡片与文案存在
      expect(
        find.byKey(const ValueKey('onboarding-missing-agent-card')),
        findsOneWidget,
      );
      expect(find.text('未检测到 Hermes Agent'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-install-agent-btn')),
        findsOneWidget,
      );
      expect(find.text('查看安装指南'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-recheck-agent-btn')),
        findsOneWidget,
      );
      expect(find.text('我装好了，重新检测'), findsOneWidget);

      // 验证「启动并连接」按钮置灰（onPressed is null）
      final actionBtn = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
      );
      expect(actionBtn.onPressed, isNull);

      // 模拟用户安装就绪后点击「我装好了，重新检测」
      installed = true;
      await tester.tap(
        find.byKey(const ValueKey('onboarding-recheck-agent-btn')),
      );
      await tester.pumpAndSettle();

      // 缺失卡收起，启动按钮解禁
      expect(
        find.byKey(const ValueKey('onboarding-missing-agent-card')),
        findsNothing,
      );
      final enabledActionBtn = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
      );
      expect(enabledActionBtn.onPressed, isNotNull);
    });

    testWidgets('agentEnvPresent=true 时不显示缺失卡片，启动按钮可用', (tester) async {
      fakeFs.fileExistsOverride = (path) => true;

      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('onboarding-missing-agent-card')),
        findsNothing,
      );
      final actionBtn = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
      );
      expect(actionBtn.onPressed, isNotNull);
    });
  });

  group('TASK U2 — 高级折叠改动 -> config 写回', () {
    testWidgets('展开高级折叠并修改端口、主机、密码、开机自启，均即时写回 Provider', (tester) async {
      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(spyStore),
          installDetectorProvider.overrideWithValue(detector),
          sidecarFileSystemProvider.overrideWithValue(fakeFs),
          bundledWebuiAvailableProvider.overrideWithValue(true),
          webuiSidecarServiceProvider.overrideWithValue(mockService),
          onboardingApiFactoryProvider.overrideWithValue((_, _) => fakeApi),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp(
            locale: const Locale('zh'),
            theme: buildCupertinoTheme(Brightness.light),
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('zh'), Locale('en')],
            home: const OnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始默认展开（#84：host/port/密码首见即见）
      expect(
        find.byKey(const ValueKey('onboarding-sidecar-port-input')),
        findsOneWidget,
      );

      // 修改端口
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-sidecar-port-input')),
        '9090',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(container.read(webuiSidecarConfigProvider).port, 9090);

      // 修改监听 IP
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-sidecar-host-input')),
        '0.0.0.0',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(container.read(webuiSidecarConfigProvider).host, '0.0.0.0');

      // 密码行：默认明文内联框，眼睛切显隐，改字回车即写回
      final passwordInputFinder = find.byKey(
        const ValueKey('onboarding-sidecar-password-input'),
      );
      expect(passwordInputFinder, findsOneWidget);
      expect(
        tester.widget<CupertinoTextField>(passwordInputFinder).obscureText,
        isFalse,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('onboarding-sidecar-password-visibility-btn'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(passwordInputFinder).obscureText,
        isTrue,
      );
      await tester.tap(
        find.byKey(
          const ValueKey('onboarding-sidecar-password-visibility-btn'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(passwordInputFinder, 'my-new-secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        container.read(webuiSidecarConfigProvider).password,
        'my-new-secret',
      );

      // 空密码不写回并红字提示
      await tester.enterText(passwordInputFinder, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('密码不能为空'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).password,
        'my-new-secret',
      );

      // 切换开机自启开关
      expect(container.read(desktopSettingsProvider).startOnLogin, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('onboarding-sidecar-start-on-login-switch')),
      );
      await tester.pumpAndSettle();
      expect(container.read(desktopSettingsProvider).startOnLogin, isTrue);
    });
  });

  group('TASK U2 — 宽屏右列 <= 480', () {
    testWidgets('在 1280x900 宽屏视口下渲染双栏且右列容器最大宽度 <= 480', (tester) async {
      // Settle the layout without waiting on the intentional brand loop.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildTestApp(bundledAvailable: true));
      await tester.pumpAndSettle();

      // 验证左品牌氛围区存在
      expect(
        find.byKey(const ValueKey('onboarding-brand-pane')),
        findsOneWidget,
      );

      // 验证右列容器存在且宽度 <= 480
      final containerFinder =
          find.byKey(const ValueKey('wide-dual-pane-form-container'));
      expect(containerFinder, findsOneWidget);

      final size = tester.getSize(containerFinder);
      expect(size.width, lessThanOrEqualTo(480.0));

      // 分段控件在右列中渲染
      expect(
        find.byKey(const ValueKey('onboarding-segmented-control')),
        findsOneWidget,
      );
    });
  });

  group('TASK U2 — 已 active 且 running / 停用回退', () {
    testWidgets('已 active 且 running 时按钮变为「进入会话列表」并可直达 /', (tester) async {
      mockService = _MockWebuiSidecarService(
        initialState: const SidecarState(status: SidecarStatus.running, pid: 1111),
      );

      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(spyStore),
          installDetectorProvider.overrideWithValue(detector),
          sidecarFileSystemProvider.overrideWithValue(fakeFs),
          bundledWebuiAvailableProvider.overrideWithValue(true),
          webuiSidecarServiceProvider.overrideWithValue(mockService),
          onboardingApiFactoryProvider.overrideWithValue((_, _) => fakeApi),
        ],
      );
      addTearDown(container.dispose);

      // 先存入 builtin 连接并设为 active
      final builtinConn = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Hermes',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.now().toUtc(),
        kind: ConnectionKind.builtin,
        enabled: true,
      );
      await container
          .read(connectionsProvider.notifier)
          .upsertBuiltinAndActivate(builtinConn);

      final router = GoRouter(
        initialLocation: '/onboarding',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('HOME_PAGE')),
          GoRoute(
            path: '/onboarding',
            builder: (_, _) => const OnboardingPage(),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp.router(
            locale: const Locale('zh'),
            theme: buildCupertinoTheme(Brightness.light),
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('zh'), Locale('en')],
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 按钮文案变更为「进入会话列表」
      expect(find.text('进入会话列表'), findsOneWidget);

      // 点击直接进入首页
      await tester.tap(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOME_PAGE'), findsOneWidget);
    });

    testWidgets('停用回退：active 从 builtin 被清时，停留内置 Tab 且状态胶囊显示未启动',
        (tester) async {
      mockService = _MockWebuiSidecarService(
        initialState: const SidecarState(status: SidecarStatus.stopped),
      );

      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(spyStore),
          installDetectorProvider.overrideWithValue(detector),
          sidecarFileSystemProvider.overrideWithValue(fakeFs),
          bundledWebuiAvailableProvider.overrideWithValue(true),
          webuiSidecarServiceProvider.overrideWithValue(mockService),
          onboardingApiFactoryProvider.overrideWithValue((_, _) => fakeApi),
        ],
      );
      addTearDown(container.dispose);

      // 预置已激活的 builtin 连接
      final builtinConn = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Hermes',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.now().toUtc(),
        kind: ConnectionKind.builtin,
        enabled: true,
      );
      await container
          .read(connectionsProvider.notifier)
          .upsertBuiltinAndActivate(builtinConn);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp(
            locale: const Locale('zh'),
            theme: buildCupertinoTheme(Brightness.light),
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('zh'), Locale('en')],
            home: const OnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 模拟清除 active 连接（停用回退）
      await container.read(activeConnectionProvider.notifier).clear();
      await tester.pumpAndSettle();

      // 仍然停留在内置 Tab，状态胶囊反映未启动
      expect(
        find.byKey(const ValueKey('onboarding-builtin-action-btn')),
        findsOneWidget,
      );
      expect(find.textContaining('未启动'), findsOneWidget);
    });
  });
}
