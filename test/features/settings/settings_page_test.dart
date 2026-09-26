import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/theme_provider.dart';
import 'package:hermes_ui/app/widgets/adaptive_sliver_navigation_bar.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/auxiliary_model.dart';
import 'package:hermes_ui/core/models/extensions.dart';
import 'package:hermes_ui/core/models/mcp.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_service.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/golden_helpers.dart';
import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 构造服务器连接（测试用）。
ServerConnection buildConn(String id, String name, String url) {
  return ServerConnection(
    id: id,
    name: name,
    baseUrl: url,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// 两个 provider 分组 + 一个 extra model 的样例目录（与 controller 测试共用形状）。
const sampleGroups = <Map<String, Object?>>[
  {
    'provider_id': 'openai',
    'name': 'OpenAI',
    'models': [
      {'id': 'gpt-4o', 'name': 'GPT-4o'},
      {'id': 'gpt-4o-mini', 'name': 'GPT-4o mini'},
    ],
    'extra_models': [
      {'id': 'o3', 'name': 'o3'},
    ],
  },
  {
    'provider_id': 'anthropic',
    'name': 'Anthropic',
    'models': [
      {'id': 'claude-sonnet-4', 'name': 'Claude Sonnet 4'},
    ],
  },
];

/// 带模型目录 + 推理能力的默认 fake 配置。
FakeSettingsApi buildApi() {
  final api = FakeSettingsApi();
  api.modelsResponse = ModelsResponse.fromJson({
    'default_model': 'gpt-4o',
    'active_provider': 'openai',
    'groups': sampleGroups,
  });
  api.reasoningResponse = const ReasoningStatusResponse(
    ok: true,
    reasoningEffort: 'medium',
    supportedEfforts: ['low', 'medium', 'high'],
    supportsReasoningEffort: true,
  );
  api.extensionsStatusResponse = const ExtensionsStatusResponse(
    enabled: true,
    extensions: [
      ExtensionInfo(
        id: 'ext-web-search',
        name: 'Web Search',
        enabled: true,
        sidecarActive: true,
        sidecarProxyConsent: true,
      ),
    ],
  );
  api.extensionsRegistryResponse = const ExtensionsRegistryResponse(
    registry: [
      ExtensionRegistryItem(
        id: 'ext-calculator',
        name: 'Calculator',
        version: '1.0.0',
        downloadUrl: 'https://example.com/calc.zip',
        sha256: 'hash_calc',
      ),
    ],
  );
  api.mcpServersResponse = const McpServersResponse(
    servers: [
      McpServer(
        name: 'fetch-server',
        command: 'uvx',
        args: ['mcp-fetch'],
        enabled: true,
        status: 'connected',
      ),
    ],
  );
  api.mcpToolsResponse = const McpToolsResponse(
    tools: [
      McpTool(
        name: 'fetch_url',
        server: 'fetch-server',
        description: 'Fetch webpage',
      ),
    ],
  );
  api.auxiliaryModelsResponse = const AuxiliaryModelsResponse(
    tasks: [
      AuxiliaryTaskRow(
        task: 'vision',
        provider: 'openai',
        model: 'gpt-4o',
        apiKeySet: true,
        label: 'Vision Understanding',
      ),
      AuxiliaryTaskRow(
        task: 'compression',
        provider: 'auto',
        model: '',
        apiKeySet: false,
        label: 'Context Compression',
      ),
    ],
    main: AuxMainModel(provider: 'openai', model: 'gpt-4o'),
  );
  return api;
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ApiClient buildMockApiClient({
  required ResponseBody Function(RequestOptions options) handler,
  String baseUrl = 'http://test.local:30002',
}) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = _MockHttpClientAdapter(handler);
  return ApiClient(baseUrl: baseUrl, dio: dio);
}

class _FakeTurnNotificationService implements TurnNotificationService {
  final List<(String, String, String)> notifyCalls = [];
  final List<(String, String)> clarifyCalls = [];
  final List<(String, String, String)> errorCalls = [];
  int clearAllCalls = 0;
  int permissionRequests = 0;
  bool permissionResult = true;
  bool notificationsEnabled = true;
  String? launchSessionId;

  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {
    notifyCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {
    clarifyCalls.add((sessionId, question));
  }

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {
    errorCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyDownloadCompleted(
    String downloadId,
    String fileName,
    int byteSize,
  ) async {}

  @override
  Future<void> notifyDownloadFailed(
    String downloadId,
    String fileName, {
    required bool cancelled,
  }) async {}

  @override
  Future<void> updateDownloadProgress({
    required String fileName,
    required int receivedBytes,
    required int expectedBytes,
    int queuedCount = 0,
  }) async {}

  @override
  Future<void> clearDownloadProgress() async {}


  @override
  Future<void> clearAll() async {
    clearAllCalls++;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionResult;
  }

  @override
  Future<bool> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<String?> getLaunchSessionId() async => launchSessionId;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 组装容器：注入内存存储（预置连接）+ fake 设置 API + 占位 ApiClient + 可选通知服务。
  Future<ProviderContainer> makeContainer({
    required FakeSettingsApi api,
    List<ServerConnection> connections = const [],
    String? activeId,
    FakeOnboardingLoginApi? loginApi,
    ApiClient? mockApiClient,
    TurnNotificationService? notificationService,
    BackgroundKeepaliveService? keepaliveService,
  }) async {
    final storage = InMemorySecureStorage();
    final store = ConnectionStore(storage: storage);
    for (final connection in connections) {
      await store.save(connection);
    }
    if (activeId != null) {
      await store.setActive(activeId);
    }
    final client =
        mockApiClient ?? ApiClient(baseUrl: 'http://test.local:30002');
    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(client),
        settingsApiFactoryProvider.overrideWithValue((_) => api),
        onboardingApiFactoryProvider.overrideWithValue(
          (baseUrl, headers) => loginApi ?? FakeOnboardingLoginApi(),
        ),
        serverEditorApiClientFactoryProvider.overrideWithValue(
          (baseUrl, headers) => client,
        ),
        if (notificationService != null)
          turnNotificationServiceProvider.overrideWithValue(
            notificationService,
          ),
        if (keepaliveService != null)
          backgroundKeepaliveServiceProvider.overrideWithValue(
            keepaliveService,
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 挂载设置页（CupertinoApp 提供 Directionality / 主题）并等异步加载完成。
  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container, {
    Size size = const Size(800, 2000),
    TextScaler textScaler = TextScaler.noScaling,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: textScaler,
            platformBrightness: brightness,
          ),
          child: CupertinoApp(
            theme: CupertinoThemeData(brightness: brightness),
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 滚动设置主页使目标可见（兼容两种状态）：
  /// - 目标已 build 但视口外 → `ensureVisible` 直接对齐
  /// - 目标未 build（CustomScrollView 惰性区外）→ 先 `scrollUntilVisible` 触发 build
  Future<void> scrollEntryIntoView(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 100);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  group('分组渲染', () {
    testWidgets('分组标题 + 当前服务器 + 默认模型 + 推理强度 + 版本号', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 分组标题
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('服务器'), findsOneWidget);
      expect(find.text('模型'), findsOneWidget);
      expect(find.text('高级设置'), findsOneWidget);

      // 列表行渲染 name + url（激活标识在行内勾选图标）
      final rowC1 = find.byKey(const ValueKey('server-row-c1'));
      expect(
        find.descendant(of: rowC1, matching: find.text('Home')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowC1,
          matching: find.text('http://hermes.local:30002'),
        ),
        findsOneWidget,
      );

      // 模型：默认模型显示名 + 推理强度
      expect(find.text('默认模型'), findsOneWidget);
      expect(find.text('GPT-4o'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-reasoning')),
      );
      expect(find.text('推理强度'), findsOneWidget);
      expect(find.text('medium'), findsOneWidget);

      // 二级入口行
      expect(
        find.byKey(const ValueKey('settings-entry-auxiliary')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settings-entry-mcp')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-entry-extensions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-entry-session-list-entries')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-entry-session-row-subtitle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-entry-desktop')),
        findsOneWidget,
      );

      // 关于：版本号
      await tester.scrollUntilVisible(find.text('版本'), 50);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('版本'), findsOneWidget);
      expect(find.text('1.0.0+1'), findsOneWidget);
    });

    testWidgets('分组顺序：关于分组置底（定时会话板块在模型之后）', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      final customScrollView = tester.widget<CustomScrollView>(
        find.byKey(const ValueKey('settings-scroll')),
      );
      final slivers = customScrollView.slivers;
      expect(slivers.first, isA<AdaptiveSliverNavigationBar>());
      final boxAdapters = slivers.whereType<SliverToBoxAdapter>().toList();
      final typeNames = boxAdapters
          .map((w) => w.child.runtimeType.toString())
          .toList();
      expect(typeNames, [
        '_AppearanceSection',
        '_ChatSection',
        '_ServerSection',
        '_ModelSection',
        '_CronSection',
        '_NotificationSection',
        '_AdvancedSettingsSection',
        '_AboutSection',
      ]);
    });

    testWidgets('无激活连接 → 显示未连接', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
      );
      await pumpPage(tester, container);

      // header 提示未连接；列表行无勾选图标
      expect(find.text('服务器（未连接）'), findsOneWidget);
      final activeIcon = find.descendant(
        of: find.byKey(const ValueKey('server-row-c1')),
        matching: find.byIcon(CupertinoIcons.checkmark_circle_fill),
      );
      expect(activeIcon, findsNothing);
    });

    testWidgets('模型加载失败 → 错误态 + 重试成功', (tester) async {
      final api = buildApi();
      api.modelsError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      expect(find.text('模型加载失败'), findsOneWidget);

      api.modelsError = null;
      await tester.tap(find.byKey(const ValueKey('settings-models-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('模型加载失败'), findsNothing);
      expect(find.text('默认模型'), findsOneWidget);
      expect(find.text('GPT-4o'), findsOneWidget);
    });

    testWidgets('服务器不支持推理强度 → 不显示推理行', (tester) async {
      final api = buildApi();
      api.reasoningResponse = const ReasoningStatusResponse(
        ok: true,
        supportsReasoningEffort: false,
      );
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      expect(find.text('默认模型'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-reasoning')), findsNothing);
    });
  });

  group('主题切换', () {
    testWidgets('三态分段控件：点深色 / 浅色 更新 themeModeProvider', (tester) async {
      final container = await makeContainer(api: buildApi());
      await pumpPage(tester, container);

      expect(container.read(themeModeProvider), AppThemeMode.system);

      await tester.tap(find.text('深色'));
      await tester.pump();
      expect(container.read(themeModeProvider), AppThemeMode.dark);

      await tester.tap(find.text('浅色'));
      await tester.pump();
      expect(container.read(themeModeProvider), AppThemeMode.light);

      await tester.tap(find.text('跟随系统'));
      await tester.pump();
      expect(container.read(themeModeProvider), AppThemeMode.system);
    });
  });

  group('服务器操作', () {
    testWidgets('列表渲染：激活行有勾选，非激活行可点切换', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn('c1', 'Home', 'http://hermes.local:30002'),
          buildConn('c2', 'Office', 'http://office.example.com:30002'),
        ],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      expect(find.text('Office'), findsOneWidget);
      // c1 激活：仅列表行显示 c1（无独立 active 行），行内勾选图标
      expect(find.text('Home'), findsOneWidget);
      final activeIcon = find.descendant(
        of: find.byKey(const ValueKey('server-row-c1')),
        matching: find.byIcon(CupertinoIcons.checkmark_circle_fill),
      );
      expect(activeIcon, findsOneWidget);
      final inactiveIcon = find.descendant(
        of: find.byKey(const ValueKey('server-row-c2')),
        matching: find.byIcon(CupertinoIcons.checkmark_circle_fill),
      );
      expect(inactiveIcon, findsNothing);

      // 切换激活
      await tester.tap(find.byKey(const ValueKey('server-row-c2')));
      await tester.pump();
      await tester.pump();
      expect(container.read(activeConnectionProvider)?.id, 'c2');
      expect(container.read(activeConnectionProvider)?.name, 'Office');
    });

    testWidgets('添加服务器：空 URL 校验失败 → 填写保存入列表', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-add')));
      await tester.pumpAndSettle();

      // 验证新增表单标签文字与说明
      expect(find.text('基本信息'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('地址'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('例如 https://hermes.example.com:8787'), findsOneWidget);

      // 空 URL 直接保存 → 校验错误
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pump();
      expect(find.text('请输入服务器地址'), findsOneWidget);

      // 填名称 + URL → 保存成功并返回
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-name')),
        'Lab',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-url')),
        'http://lab.example.com:30002',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('server-editor-url')), findsNothing);
      final connections = container.read(connectionsProvider);
      expect(connections, hasLength(2));
      expect(connections.last.name, 'Lab');
      expect(connections.last.baseUrl, 'http://lab.example.com:30002');
      // 列表中出现新行
      expect(find.text('Lab'), findsOneWidget);
    });

    testWidgets('编辑服务器：表单预填 + 改名保存', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn('c2', 'Office', 'http://office.example.com:30002'),
        ],
        activeId: 'c2',
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-edit-c2')));
      await tester.pumpAndSettle();

      // 预填原值
      final urlField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('server-editor-url')),
      );
      expect(urlField.controller!.text, 'http://office.example.com:30002');

      // 改名保存
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-name')),
        'Main Office',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      final connections = container.read(connectionsProvider);
      expect(connections, hasLength(1));
      expect(connections.single.id, 'c2'); // id 不变（编辑）
      expect(connections.single.name, 'Main Office');
      expect(connections.single.baseUrl, 'http://office.example.com:30002');
      // 列表行显示新名称（active 信息行也可能显示同名，用行内查询）
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-row-c2')),
          matching: find.text('Main Office'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('添加服务器带密码：先登录成功再保存入列表', (tester) async {
      final loginApi = FakeOnboardingLoginApi();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        loginApi: loginApi,
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('server-editor-name')),
        'Main',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-url')),
        'http://main.example.com:30002',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-password')),
        'secret',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      // 保存前先登录（种 cookie），成功后才落库
      expect(loginApi.loginCalls, 1);
      expect(loginApi.lastPassword, 'secret');
      final connections = container.read(connectionsProvider);
      expect(connections, hasLength(2));
      expect(connections.last.password, 'secret');
      expect(find.byKey(const ValueKey('server-editor-url')), findsNothing);
    });

    testWidgets('密码错误：登录失败 → 报错且不保存', (tester) async {
      final loginApi = FakeOnboardingLoginApi()
        ..loginError = const UnauthorizedException();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        loginApi: loginApi,
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('server-editor-url')),
        'http://main.example.com:30002',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-password')),
        'wrong',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      // 错误提示 + 表单停留 + 未落库
      expect(find.text('登录失败：密码被拒绝。请检查服务器密码后重试。'), findsOneWidget);
      expect(find.byKey(const ValueKey('server-editor-url')), findsOneWidget);
      expect(container.read(connectionsProvider), hasLength(1));
    });

    testWidgets('删除服务器：确认弹窗 → 移除且激活不受影响', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn('c1', 'Home', 'http://hermes.local:30002'),
          buildConn('c2', 'Office', 'http://office.example.com:30002'),
        ],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-delete-c2')));
      await tester.pumpAndSettle();
      expect(find.text('删除服务器'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('server-delete-confirm')));
      await tester.pumpAndSettle();

      final connections = container.read(connectionsProvider);
      expect(connections.map((c) => c.id).toList(), ['c1']);
      expect(container.read(activeConnectionProvider)?.id, 'c1');
      expect(find.text('Office'), findsNothing);
    });

    testWidgets('builtin 行渲染「停用/启用」按钮，无删除与编辑按钮；remote 行维持编辑与删除', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn('c1', 'Remote Server', 'http://remote.example.com:30002'),
          ServerConnection(
            id: ServerConnection.builtinId,
            name: '', // 缺省空名称 → 展示「内置 WebUI」
            baseUrl: 'http://127.0.0.1:8787',
            kind: ConnectionKind.builtin,
            enabled: true,
            createdAt: DateTime.utc(2026, 9, 4),
          ),
        ],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 1. builtin 行断言
      final builtinRow = find.byKey(
        const ValueKey('server-row-builtin-sidecar'),
      );
      expect(builtinRow, findsOneWidget);

      // name 缺省显示「内置 WebUI」
      expect(
        find.descendant(of: builtinRow, matching: find.text('内置 WebUI')),
        findsOneWidget,
      );
      // subtitle 展示 baseUrl
      expect(
        find.descendant(
          of: builtinRow,
          matching: find.text('http://127.0.0.1:8787'),
        ),
        findsOneWidget,
      );

      // builtin 行有停用按钮（key: server-toggle-builtin）
      final toggleBtn = find.descendant(
        of: builtinRow,
        matching: find.byKey(const ValueKey('server-toggle-builtin')),
      );
      expect(toggleBtn, findsOneWidget);
      expect(
        find.descendant(of: toggleBtn, matching: find.text('停用')),
        findsOneWidget,
      );

      // builtin 行完全不出现编辑和删除按钮
      expect(
        find.descendant(
          of: builtinRow,
          matching: find.byKey(const ValueKey('server-edit-builtin-sidecar')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: builtinRow,
          matching: find.byKey(const ValueKey('server-delete-builtin-sidecar')),
        ),
        findsNothing,
      );

      // 2. remote 行照常有编辑和删除按钮，无停用按钮
      final remoteRow = find.byKey(const ValueKey('server-row-c1'));
      expect(remoteRow, findsOneWidget);
      expect(
        find.descendant(
          of: remoteRow,
          matching: find.byKey(const ValueKey('server-edit-c1')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: remoteRow,
          matching: find.byKey(const ValueKey('server-delete-c1')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: remoteRow,
          matching: find.byKey(const ValueKey('server-toggle-builtin')),
        ),
        findsNothing,
      );

      // 3. 点击「停用」→ 切换为已停用（enabled=false），按钮文案变为「启用」
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      final updatedBuiltin = container
          .read(connectionsProvider)
          .firstWhere((c) => c.id == ServerConnection.builtinId);
      expect(updatedBuiltin.enabled, isFalse);
      expect(
        find.descendant(of: toggleBtn, matching: find.text('启用')),
        findsOneWidget,
      );

      // 4. 点击「启用」→ 恢复 enabled=true，按钮文案变回「停用」
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      final reenabledBuiltin = container
          .read(connectionsProvider)
          .firstWhere((c) => c.id == ServerConnection.builtinId);
      expect(reenabledBuiltin.enabled, isTrue);
      expect(
        find.descendant(of: toggleBtn, matching: find.text('停用')),
        findsOneWidget,
      );
    });

    testWidgets('停用正在激活的 builtin 连接：clearActive 回未连接态', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [
          ServerConnection(
            id: ServerConnection.builtinId,
            name: 'Sidecar',
            baseUrl: 'http://127.0.0.1:8787',
            kind: ConnectionKind.builtin,
            enabled: true,
            createdAt: DateTime.utc(2026, 9, 4),
          ),
        ],
        activeId: ServerConnection.builtinId,
      );
      await pumpPage(tester, container);

      // 当前处于激活状态
      expect(
        container.read(activeConnectionProvider)?.id,
        ServerConnection.builtinId,
      );
      expect(find.text('服务器'), findsOneWidget);

      // 点击停用
      await tester.tap(find.byKey(const ValueKey('server-toggle-builtin')));
      await tester.pumpAndSettle();

      // 激活连接被清除
      expect(container.read(activeConnectionProvider), isNull);
      expect(find.text('服务器（未连接）'), findsOneWidget);
    });
  });

  group('服务器编辑页 Profile 集成', () {
    testWidgets('编辑服务器时加载并显示 Profile，点击弹窗切换 Profile 并刷新', (tester) async {
      String currentProfile = 'Default';
      final mockClient = buildMockApiClient(
        handler: (options) {
          if (options.path.endsWith('/api/profiles')) {
            return ResponseBody.fromString(
              '{"profiles":[{"name":"Default"},{"name":"Work"}],"active":"$currentProfile"}',
              200,
              headers: {
                'content-type': ['application/json'],
              },
            );
          }
          if (options.path.endsWith('/api/profile/switch')) {
            currentProfile = 'Work';
            return ResponseBody.fromString(
              '{"profiles":[{"name":"Default"},{"name":"Work"}],"active":"Work"}',
              200,
              headers: {
                'content-type': ['application/json'],
              },
            );
          }
          return ResponseBody.fromString('{}', 200);
        },
      );

      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        mockApiClient: mockClient,
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-edit-c1')));
      await tester.pumpAndSettle();

      // Profile 区块存在且已加载 active profile
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);

      // 点击打开选择弹窗
      await tester.tap(
        find.byKey(const ValueKey('server-editor-profile-tile')),
      );
      await tester.pumpAndSettle();

      expect(find.text('选择 Profile'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);

      // 选择 Work
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      // 切换成功，行显示变为 Work
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('Profile 加载失败显示重试行，点击重试', (tester) async {
      var shouldFail = true;
      final mockClient = buildMockApiClient(
        handler: (options) {
          if (options.path.endsWith('/api/profiles')) {
            if (shouldFail) {
              return ResponseBody.fromString(
                '{"error":"Network error"}',
                500,
                headers: {
                  'content-type': ['application/json'],
                },
              );
            }
            return ResponseBody.fromString(
              '{"profiles":[{"name":"Production"}],"active":"Production"}',
              200,
              headers: {
                'content-type': ['application/json'],
              },
            );
          }
          return ResponseBody.fromString('{}', 200);
        },
      );

      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        mockApiClient: mockClient,
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-edit-c1')));
      await tester.pumpAndSettle();

      // 初始加载失败
      expect(find.text('读取失败'), findsOneWidget);
      expect(find.text('点击重试'), findsOneWidget);

      // 恢复后重试
      shouldFail = false;
      await tester.tap(
        find.byKey(const ValueKey('server-editor-profile-retry')),
      );
      await tester.pumpAndSettle();

      expect(find.text('读取失败'), findsNothing);
      expect(find.text('Production'), findsOneWidget);
    });

    testWidgets('Profile 切换失败显示错误弹窗', (tester) async {
      final mockClient = buildMockApiClient(
        handler: (options) {
          if (options.path.endsWith('/api/profiles')) {
            return ResponseBody.fromString(
              '{"profiles":[{"name":"Default"},{"name":"Dev"}],"active":"Default"}',
              200,
              headers: {
                'content-type': ['application/json'],
              },
            );
          }
          if (options.path.endsWith('/api/profile/switch')) {
            return ResponseBody.fromString(
              '{"error":"Switch forbidden"}',
              403,
              headers: {
                'content-type': ['application/json'],
              },
            );
          }
          return ResponseBody.fromString('{}', 200);
        },
      );

      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        mockApiClient: mockClient,
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-edit-c1')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('server-editor-profile-tile')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dev'));
      await tester.pumpAndSettle();

      // 弹窗提示失败
      expect(find.text('Profile 切换失败'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('Profile 切换失败'), findsNothing);
    });
  });

  group('模型操作', () {
    testWidgets('默认模型选择器：进入选择页 → 选 o3 → 调 API 并更新显示', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-default-model')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-default-model')));
      await tester.pumpAndSettle();

      // 选择页：分组 + 选项渲染
      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.text('Anthropic'), findsOneWidget);
      expect(find.byKey(const ValueKey('model-option-o3')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('model-option-o3')));
      await tester.pumpAndSettle();

      expect(api.defaultModelCalls, ['o3']);
      // 返回设置页后默认模型显示更新
      expect(find.byKey(const ValueKey('model-option-o3')), findsNothing);
      expect(find.text('o3'), findsOneWidget);
    });

    testWidgets('推理强度：action sheet 选择 high → 调 API', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-reasoning')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-reasoning')));
      await tester.pumpAndSettle();

      expect(find.text('推理强度'), findsWidgets); // 标题行 + action sheet 标题
      await tester.tap(find.byKey(const ValueKey('reasoning-high')));
      await tester.pumpAndSettle();

      expect(api.reasoningEffortCalls, ['high']);
    });
  });

  group('Extensions 操作', () {
    testWidgets('渲染已安装扩展 + 启停切换', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-entry-extensions')),
      );
      await tester.pumpAndSettle();

      // 进入扩展二级页
      await tester.tap(find.byKey(const ValueKey('settings-entry-extensions')));
      await tester.pumpAndSettle();

      final toggle = find.byKey(
        const ValueKey('extension-toggle-ext-web-search'),
      );
      expect(find.text('Web Search'), findsOneWidget);
      expect(find.textContaining('ext-web-search'), findsOneWidget);
      expect(toggle, findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(api.toggleExtensionCalls, [('ext-web-search', false)]);
    });

    testWidgets('扩展详情 sheet：sidecar 授权 + 卸载确认', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-entry-extensions')),
      );
      await tester.pumpAndSettle();

      // 进入扩展二级页
      await tester.tap(find.byKey(const ValueKey('settings-entry-extensions')));
      await tester.pumpAndSettle();

      final rowFinder = find.byKey(
        const ValueKey('extension-row-ext-web-search'),
      );
      await tester.tap(rowFinder);
      await tester.pumpAndSettle();

      // Sidecar consent
      expect(
        find.byKey(const ValueKey('extension-sidecar-ext-web-search')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('extension-sidecar-ext-web-search')),
      );
      await tester.pumpAndSettle();
      expect(api.setSidecarConsentCalls, [('ext-web-search', false)]);

      // Uninstall
      await tester.tap(rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('extension-uninstall-ext-web-search')),
      );
      await tester.pumpAndSettle();

      expect(find.text('卸载扩展'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('extension-uninstall-confirm')),
      );
      await tester.pumpAndSettle();

      expect(api.uninstallExtensionCalls, ['ext-web-search']);
    });

    testWidgets('安装扩展：从注册表预填并提交', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-entry-extensions')),
      );
      await tester.pumpAndSettle();

      // 进入扩展二级页
      await tester.tap(find.byKey(const ValueKey('settings-entry-extensions')));
      await tester.pumpAndSettle();

      final installTile = find.byKey(
        const ValueKey('settings-extension-install'),
      );
      await tester.tap(installTile);
      await tester.pumpAndSettle();

      // 点击注册表项预填
      expect(
        find.byKey(const ValueKey('registry-item-ext-calculator')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('registry-item-ext-calculator')),
      );
      await tester.pump();

      final idField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('extension-install-id')),
      );
      expect(idField.controller!.text, 'ext-calculator');

      // 提交安装
      await tester.tap(find.byKey(const ValueKey('extension-install-submit')));
      await tester.pumpAndSettle();

      expect(api.installExtensionCalls, [
        (
          id: 'ext-calculator',
          downloadUrl: 'https://example.com/calc.zip',
          sha256: 'hash_calc',
        ),
      ]);
    });
  });

  group('MCP 服务器操作', () {
    testWidgets('渲染 MCP 服务器 + 启停切换', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 进入 MCP 二级页
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-entry-mcp')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-entry-mcp')));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('mcp-toggle-fetch-server'));
      expect(find.text('fetch-server'), findsOneWidget);
      expect(toggle, findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(api.toggleMcpServerCalls, [('fetch-server', false)]);
    });

    testWidgets('MCP 菜单：查看工具 + 删除服务器确认', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 进入 MCP 二级页
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-entry-mcp')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-entry-mcp')));
      await tester.pumpAndSettle();

      final rowFinder = find.byKey(
        const ValueKey('mcp-server-row-fetch-server'),
      );
      await tester.tap(rowFinder);
      await tester.pumpAndSettle();

      // 查看工具
      expect(
        find.byKey(const ValueKey('mcp-tools-fetch-server')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('mcp-tools-fetch-server')));
      await tester.pumpAndSettle();

      expect(find.text('fetch_url'), findsOneWidget);
      expect(find.text('Fetch webpage'), findsOneWidget);

      // 返回
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();

      // 删除确认
      await tester.tap(rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mcp-delete-fetch-server')));
      await tester.pumpAndSettle();

      expect(find.text('删除 MCP 服务器'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mcp-delete-confirm')));
      await tester.pumpAndSettle();

      expect(api.deleteMcpServerCalls, ['fetch-server']);
    });

    testWidgets('添加 MCP 服务器：填写并保存', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 进入 MCP 二级页
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-entry-mcp')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-entry-mcp')));
      await tester.pumpAndSettle();

      final addFinder = find.byKey(const ValueKey('settings-mcp-add'));
      await tester.tap(addFinder);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('mcp-editor-name')),
        'new-mcp',
      );
      await tester.enterText(
        find.byKey(const ValueKey('mcp-editor-command')),
        'node',
      );
      await tester.enterText(
        find.byKey(const ValueKey('mcp-editor-args')),
        'server.js\n--port\n3000',
      );
      await tester.tap(find.byKey(const ValueKey('mcp-editor-save')));
      await tester.pumpAndSettle();

      expect(api.saveMcpServerCalls, hasLength(1));
      final call = api.saveMcpServerCalls.single;
      expect(call.name, 'new-mcp');
      expect(call.command, 'node');
      expect(call.args, ['server.js', '--port', '3000']);
      expect(call.env, isNull);
      expect(call.enabled, isTrue);
    });
  });

  group('辅助模型操作', () {
    testWidgets('渲染任务行 + 钥匙标记 + 选择模型', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 进入辅助模型二级页
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-entry-auxiliary')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-entry-auxiliary')));
      await tester.pumpAndSettle();

      final taskRowFinder = find.byKey(const ValueKey('aux-task-vision'));

      expect(find.text('Vision Understanding'), findsOneWidget);
      expect(find.text('🔑'), findsOneWidget);
      expect(
        find.descendant(
          of: taskRowFinder,
          matching: find.text('openai / gpt-4o'),
        ),
        findsOneWidget,
      );

      await tester.tap(taskRowFinder);
      await tester.pumpAndSettle();

      // 选择模型页
      expect(
        find.byKey(const ValueKey('aux-model-option-auto')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('aux-model-option-claude-sonnet-4')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('aux-model-option-claude-sonnet-4')),
      );
      await tester.pumpAndSettle();

      expect(api.setAuxiliaryModelCalls, [
        (
          task: 'vision',
          provider: 'anthropic',
          model: 'claude-sonnet-4',
          advanced: null,
        ),
      ]);
    });

    testWidgets('全部重置为自动确认', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 进入辅助模型二级页
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-entry-auxiliary')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-entry-auxiliary')));
      await tester.pumpAndSettle();

      final resetFinder = find.byKey(const ValueKey('settings-aux-reset'));
      await tester.tap(resetFinder);
      await tester.pumpAndSettle();

      expect(find.text('全部重置为自动'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('settings-aux-reset-confirm')),
      );
      await tester.pumpAndSettle();

      expect(api.setAuxiliaryModelCalls, [
        (task: '__reset__', provider: 'auto', model: '', advanced: null),
      ]);
    });
  });

  group('保存按钮几何回归测试', () {
    testWidgets(
      '深色模式 + 真实主题 + 金照字体：保存文本完全落在 CupertinoNavigationBar 内 (scale 1.0 & 1.3)',
      (tester) async {
        await loadHermesGoldenFonts();
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        for (final textScale in [1.0, 1.3]) {
          final container = await makeContainer(
            api: buildApi(),
            connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
            activeId: 'c1',
          );

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: CupertinoApp(
                theme: buildCupertinoTheme(Brightness.dark),
                home: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: const SettingsPage(),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // 打开服务器编辑页
          await tester.tap(find.byKey(const ValueKey('server-edit-c1')));
          await tester.pumpAndSettle();

          final navBarFinder = find.byType(CupertinoNavigationBar);
          expect(navBarFinder, findsOneWidget);
          final navBarRect = tester.getRect(navBarFinder);

          final saveBtnFinder = find.byKey(
            const ValueKey('server-editor-save'),
          );
          expect(saveBtnFinder, findsOneWidget);
          final saveBtnRect = tester.getRect(saveBtnFinder);

          final textFinder = find.descendant(
            of: saveBtnFinder,
            matching: find.text('保存'),
          );
          expect(textFinder, findsOneWidget);
          final textRect = tester.getRect(textFinder);

          // 断言保存按钮及文本在垂直方向完全处于 44pt 导航栏之内
          expect(saveBtnRect.top, greaterThanOrEqualTo(navBarRect.top));
          expect(saveBtnRect.bottom, lessThanOrEqualTo(navBarRect.bottom));
          expect(textRect.top, greaterThanOrEqualTo(navBarRect.top));
          expect(textRect.bottom, lessThanOrEqualTo(navBarRect.bottom));

          // 返回设置页
          await tester.tap(find.byType(CupertinoNavigationBarBackButton));
          await tester.pumpAndSettle();
        }
      },
    );
  });

  group('设置页滚动与双击回顶', () {
    testWidgets('CustomScrollView 绑定滚动控制器，向下滚动后双击 title 回到顶部', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container, size: const Size(400, 600));

      final scrollFinder = find.byKey(const ValueKey('settings-scroll'));
      expect(scrollFinder, findsOneWidget);

      final customScrollView = tester.widget<CustomScrollView>(scrollFinder);
      final controller = customScrollView.controller;
      expect(controller, isNotNull);
      expect(controller!.offset, 0.0);

      // 向下滚动 300px
      await tester.drag(scrollFinder, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(100));

      // 仅双击 title 回顶 — 直接触发 GestureDetector 的 onDoubleTap
      // 窄屏下 largeTitle 与 middle 共存，用 GestureDetector 定位更可靠
      final titleDetectorFinder = find.descendant(
        of: find.byType(AdaptiveSliverNavigationBar),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.onDoubleTap != null,
        ),
      );
      expect(titleDetectorFinder, findsWidgets);

      final detector = tester.widget<GestureDetector>(
        titleDetectorFinder.first,
      );
      detector.onDoubleTap!.call();
      await tester.pumpAndSettle();

      expect(controller.offset, 0.0);
    });

    testWidgets('点击/双击其他区域不触发回顶', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container, size: const Size(400, 600));

      final scrollFinder = find.byKey(const ValueKey('settings-scroll'));
      final customScrollView = tester.widget<CustomScrollView>(scrollFinder);
      final controller = customScrollView.controller!;

      // 向下滚动 300px
      await tester.drag(scrollFinder, const Offset(0, -300));
      await tester.pumpAndSettle();
      final offsetBefore = controller.offset;
      expect(offsetBefore, greaterThan(100));

      // 双击非 title 区域（如外观标题）
      final appearanceFinder = find.text('外观');
      if (appearanceFinder.evaluate().isNotEmpty) {
        await tester.tap(appearanceFinder.first);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(appearanceFinder.first);
        await tester.pumpAndSettle();

        expect(controller.offset, offsetBefore);
      }
    });
  });

  group('通知设置分组', () {
    testWidgets('展示 3 个通知开关并支持切换持久化', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      expect(
        find.byKey(const ValueKey('settings-switch-notify-turns')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-switch-notify-clarify')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-switch-notify-errors')),
        findsOneWidget,
      );

      final turnsSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-switch-notify-turns')),
      );
      expect(turnsSwitch.value, isTrue);

      // 切换 turns 开关
      await scrollEntryIntoView(
        tester,
        find.byKey(const ValueKey('settings-switch-notify-turns')),
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-switch-notify-turns')),
      );
      await tester.pumpAndSettle();

      final updatedSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-switch-notify-turns')),
      );
      expect(updatedSwitch.value, isFalse);
    });

    testWidgets('渲染推送测试行：左侧三选一默认回合完成，右侧按钮可点', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakeService = _FakeTurnNotificationService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        notificationService: fakeService,
      );
      await pumpPage(tester, container);

      // 推送测试行与组件
      expect(
        find.byKey(const ValueKey('settings-notify-push-test')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-notify-push-test-type')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-notify-push-test-button')),
        findsOneWidget,
      );

      // 默认选择为回合完成
      final segmented = tester
          .widget<CupertinoSlidingSegmentedControl<PushTestType>>(
            find.byKey(const ValueKey('settings-notify-push-test-type')),
          );
      expect(segmented.groupValue, PushTestType.turns);

      // 选项文本与按钮文本
      expect(find.text('回合完成'), findsWidgets);
      expect(find.text('需要澄清'), findsWidgets);
      expect(find.text('异常中断'), findsWidgets);
      expect(find.text('推送'), findsOneWidget);
    });

    testWidgets('默认选“回合完成”，点击推送 → 请求权限 + 触发 notifyTurnCompleted + 弹已推送轻提示', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final fakeService = _FakeTurnNotificationService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        notificationService: fakeService,
      );
      await pumpPage(tester, container);

      // 点击推送按钮
      await tester.tap(
        find.byKey(const ValueKey('settings-notify-push-test-button')),
      );
      await tester.pumpAndSettle();

      expect(fakeService.permissionRequests, 1);
      expect(fakeService.notifyCalls, hasLength(1));
      final (sessionId, title, preview) = fakeService.notifyCalls.single;
      expect(sessionId, startsWith('test-push-turns-'));
      expect(title, '测试：回合完成');
      expect(preview, contains('点击可回到测试会话'));

      // 验证轻提示弹窗
      expect(find.text('已推送：回合完成'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('已推送：回合完成'), findsNothing);
    });

    testWidgets('切换为“需要澄清”，点击推送 → 触发 clarify 通道 mock + 弹已推送轻提示', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final fakeService = _FakeTurnNotificationService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        notificationService: fakeService,
      );
      await pumpPage(tester, container);

      // 切换选择器到“需要澄清”
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('settings-notify-push-test-type')),
          matching: find.text('需要澄清'),
        ),
      );
      await tester.pumpAndSettle();

      // 点击推送
      await tester.tap(
        find.byKey(const ValueKey('settings-notify-push-test-button')),
      );
      await tester.pumpAndSettle();

      expect(fakeService.permissionRequests, 1);
      expect(fakeService.clarifyCalls, hasLength(1));
      final (sessionId, question) = fakeService.clarifyCalls.single;
      expect(sessionId, startsWith('test-push-clarify-'));
      expect(question, contains('测试：需要澄清'));
      expect(question, contains('点击可回到测试会话'));

      // 验证轻提示
      expect(find.text('已推送：需要澄清'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
    });

    testWidgets('切换为“异常中断”，点击推送 → 触发 errors 通道 mock + 弹已推送轻提示', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakeService = _FakeTurnNotificationService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        notificationService: fakeService,
      );
      await pumpPage(tester, container);

      // 切换选择器到“异常中断”
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('settings-notify-push-test-type')),
          matching: find.text('异常中断'),
        ),
      );
      await tester.pumpAndSettle();

      // 点击推送
      await tester.tap(
        find.byKey(const ValueKey('settings-notify-push-test-button')),
      );
      await tester.pumpAndSettle();

      expect(fakeService.permissionRequests, 1);
      expect(fakeService.errorCalls, hasLength(1));
      final (sessionId, title, preview) = fakeService.errorCalls.single;
      expect(sessionId, startsWith('test-push-errors-'));
      expect(title, '测试：异常中断');
      expect(preview, contains('点击可回到测试会话'));

      // 验证轻提示
      expect(find.text('已推送：异常中断'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
    });

    testWidgets('对应类型通知开关关闭时，仍允许推送测试但提示开关已关闭', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakeService = _FakeTurnNotificationService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        notificationService: fakeService,
      );
      await pumpPage(tester, container);

      // 关闭 turns 开关
      await tester.tap(
        find.byKey(const ValueKey('settings-switch-notify-turns')),
      );
      await tester.pumpAndSettle();

      // 点击推送测试
      await tester.tap(
        find.byKey(const ValueKey('settings-notify-push-test-button')),
      );
      await tester.pumpAndSettle();

      expect(fakeService.notifyCalls, hasLength(1));
      expect(find.text('该类型通知已关闭，仍已推送测试通知（系统通道独立）'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
    });

    testWidgets('权限被拒绝时，记录诊断日志并轻提示权限被拒绝', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakeService = _FakeTurnNotificationService()
        ..permissionResult = false;
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        notificationService: fakeService,
      );
      await pumpPage(tester, container);

      // 启用诊断收集
      await DiagnosticsService.instance.setEnabled(true);

      // 点击推送测试
      await tester.tap(
        find.byKey(const ValueKey('settings-notify-push-test-button')),
      );
      await tester.pumpAndSettle();

      expect(fakeService.permissionRequests, 1);
      expect(fakeService.notifyCalls, isEmpty);
      expect(find.text('通知权限已被拒绝'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();

      // 验证诊断日志
      final logs = DiagnosticsService.instance.logs;
      expect(
        logs.any(
          (e) =>
              e.tag == 'notifications' && e.level == DiagnosticsLogLevel.warn,
        ),
        isTrue,
      );
    });

    testWidgets('深色/浅色、文本缩放 1.5x、窄屏 320px 不溢出', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(
        tester,
        container,
        size: const Size(320, 800),
        textScaler: const TextScaler.linear(1.5),
        brightness: Brightness.dark,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-notify-push-test')),
        50,
      );

      expect(
        find.byKey(const ValueKey('settings-notify-push-test')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('后台保活设置分组（高级设置二级页）', () {
    testWidgets('展示前台服务开关（默认关闭）并支持切换持久化', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        keepaliveService: fakeKeepalive,
      );
      await pumpPage(tester, container, size: const Size(800, 1400));

      // 主页不再内联后台保活分组：从「高级设置」入口进入二级页
      expect(
        find.byKey(const ValueKey('settings-bg-foreground-service')),
        findsNothing,
      );
      final entry = find.byKey(const ValueKey('settings-entry-bg-keepalive'));
      await scrollEntryIntoView(tester, entry);
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      final fgSwitchRow = find.byKey(
        const ValueKey('settings-bg-foreground-service'),
      );
      await scrollEntryIntoView(tester, fgSwitchRow);
      expect(fgSwitchRow, findsOneWidget);

      final switchWidget = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-switch-bg-foreground-service')),
      );
      expect(switchWidget.value, isFalse);

      // 切换开关
      await tester.tap(
        find.byKey(const ValueKey('settings-switch-bg-foreground-service')),
      );
      await tester.pumpAndSettle();

      final updatedSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-switch-bg-foreground-service')),
      );
      expect(updatedSwitch.value, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('bg_foreground_service_enabled'), isTrue);
    });

    testWidgets('渲染 WorkManager 状态行与 4 个 HyperOS 引导项（独立行）', (tester) async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        keepaliveService: fakeKeepalive,
      );
      await pumpPage(tester, container, size: const Size(800, 1400));

      final entry = find.byKey(const ValueKey('settings-entry-bg-keepalive'));
      await scrollEntryIntoView(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      final wmStatusRow = find.byKey(
        const ValueKey('settings-bg-workmanager-status'),
      );
      await scrollEntryIntoView(tester, wmStatusRow);
      expect(wmStatusRow, findsOneWidget);

      // 引导项各自为独立 list tile（不再塞在单个 subtitle Wrap 内）
      expect(
        find.byKey(const ValueKey('settings-bg-guide-autostart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-bg-guide-battery')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-bg-guide-network')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-bg-guide-notifications')),
        findsOneWidget,
      );
      // 旧的「单个引导 tile」容器不再存在
      expect(
        find.byKey(const ValueKey('settings-bg-hyperos-guide')),
        findsNothing,
      );
    });

    testWidgets('点击 4 个 HyperOS 引导项触发 keepalive.openHyperOsSetting', (
      tester,
    ) async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        keepaliveService: fakeKeepalive,
      );
      await pumpPage(tester, container, size: const Size(800, 1400));

      final entry = find.byKey(const ValueKey('settings-entry-bg-keepalive'));
      await scrollEntryIntoView(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      final autostartBtn = find.byKey(
        const ValueKey('settings-bg-guide-autostart'),
      );
      await scrollEntryIntoView(tester, autostartBtn);

      await tester.tap(autostartBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-bg-guide-battery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-bg-guide-network')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-bg-guide-notifications')),
      );
      await tester.pumpAndSettle();

      expect(fakeKeepalive.openedSettings, [
        HyperOsSettingType.autoStart,
        HyperOsSettingType.batteryOptimization,
        HyperOsSettingType.networkControl,
        HyperOsSettingType.notificationSettings,
      ]);
    });

    testWidgets('通知权限未开启时显示警示行并可跳转通知设置', (tester) async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final fakeNotif = _FakeTurnNotificationService()
        ..notificationsEnabled = false;
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        keepaliveService: fakeKeepalive,
        notificationService: fakeNotif,
      );
      await pumpPage(tester, container, size: const Size(800, 1400));

      final entry = find.byKey(const ValueKey('settings-entry-bg-keepalive'));
      await scrollEntryIntoView(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      final warningRow = find.byKey(
        const ValueKey('settings-bg-guide-permission-warning'),
      );
      await scrollEntryIntoView(tester, warningRow);
      expect(warningRow, findsOneWidget);

      await tester.tap(warningRow);
      await tester.pumpAndSettle();
      expect(fakeKeepalive.openedSettings, [
        HyperOsSettingType.notificationSettings,
      ]);
    });

    testWidgets('通知权限已开启时不显示警示行', (tester) async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final fakeNotif = _FakeTurnNotificationService();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        keepaliveService: fakeKeepalive,
        notificationService: fakeNotif,
      );
      await pumpPage(tester, container, size: const Size(800, 1400));

      final entry = find.byKey(const ValueKey('settings-entry-bg-keepalive'));
      await scrollEntryIntoView(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-bg-guide-permission-warning')),
        findsNothing,
      );
    });

    testWidgets('深色/浅色、文本缩放 1.5x、窄屏 320px 不溢出', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        // 注入 fake 通知服务：真实服务 areNotificationsEnabled 会触发
        // DiagnosticsService 500ms 防抖保存 timer，动画时长变化后
        // pumpAndSettle 不再天然排空 → Timer still pending（2026-09-02）。
        notificationService: _FakeTurnNotificationService(),
      );
      await pumpPage(
        tester,
        container,
        size: const Size(320, 800),
        textScaler: const TextScaler.linear(1.5),
        brightness: Brightness.dark,
      );

      final entry = find.byKey(const ValueKey('settings-entry-bg-keepalive'));
      await scrollEntryIntoView(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      // 窄屏 + 1.5x 下 4 个引导项各自独立成行、不溢出
      expect(
        find.byKey(const ValueKey('settings-bg-guide-autostart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-bg-guide-notifications')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('外观组语言切换', () {
    testWidgets(
        '三态 segmented 渲染（key settings-locale-mode）、点 English → provider 变 + 页面文案切英',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );

      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              final mode = ref.watch(localeModeProvider);
              final locale = switch (mode) {
                AppLocaleMode.system => const Locale('zh'), // 初始中文
                AppLocaleMode.zh => const Locale('zh'),
                AppLocaleMode.en => const Locale('en'),
              };
              return CupertinoApp(
                theme: const CupertinoThemeData(brightness: Brightness.light),
                locale: locale,
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  DefaultCupertinoLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                supportedLocales: const [Locale('zh'), Locale('en')],
                home: const SettingsPage(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final segmentedFinder =
          find.byKey(const ValueKey('settings-locale-mode'));
      expect(segmentedFinder, findsOneWidget);

      // 验证初始文案为中文
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('自动'), findsOneWidget);
      expect(find.text('中文'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      // 点击 English 分段
      await tester.tap(find.descendant(
        of: segmentedFinder,
        matching: find.text('English'),
      ));
      await tester.pumpAndSettle();

      // provider 变
      expect(container.read(localeModeProvider), AppLocaleMode.en);

      // 页面文案切英
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('外观'), findsNothing);
    });
  });
}
