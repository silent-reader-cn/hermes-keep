import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/update/github_release.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_session_channel.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/session_list/session_events_client.dart';
import 'package:hermes_ui/features/settings/chat_send_shortcut_settings.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:hermes_ui/features/settings/injected_notice_settings.dart';
import 'package:hermes_ui/features/settings/perf_monitor_settings.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/settings/settings_subpages.dart';
import 'package:hermes_ui/features/settings/smooth_streaming_settings.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// [settings_page.dart] 覆盖补强（E3）：只补既有 [settings_page_test.dart]
/// 未触达的交互回调分支（开关 onChanged / 弹层取消 / 二级页跳转 /
/// 服务器编辑表单分支 / 模型选择页刷新与错误态 / 关于「检查更新」三分支）。

/// 构造服务器连接（测试用）。
ServerConnection buildConn(
  String id,
  String name,
  String url, {
  Map<String, String> customHeaders = const {},
}) {
  return ServerConnection(
    id: id,
    name: name,
    baseUrl: url,
    customHeaders: customHeaders,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// 模型目录 + 推理能力样例（与既有 settings_page_test 同形状）。
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

ResponseBody jsonBody(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

/// 更新检测服务 mock（「关于」分组三分支用）。
class MockUpdateCheckerService extends Mock implements UpdateCheckerService {}

/// 推送服务 mock：可让某个推送通道抛错，覆盖失败兜底分支。
class MockTurnNotificationService extends Mock
    implements TurnNotificationService {}

/// 登录 fake：抛非 [ApiException] 的异常（网络层中断，非鉴权失败）。
class _ThrowingLoginApi extends Mock implements OnboardingServerApi {}

/// 记录外链调用的假实现。
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];
  final List<LaunchOptions> launchedOptions = <LaunchOptions>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    launchedOptions.add(options);
    return true;
  }
}

void main() {
  late UrlLauncherPlatform originalLauncher;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalLauncher = UrlLauncherPlatform.instance;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
  });

  /// 组装容器：注入内存存储 + fake 设置 API + 占位 ApiClient（按需覆盖
  /// 通知服务 / 更新检测服务 / 登录 fake）。
  Future<ProviderContainer> makeContainer({
    required FakeSettingsApi api,
    List<ServerConnection> connections = const [],
    String? activeId,
    OnboardingServerApi? loginApi,
    ApiClient? mockApiClient,
    TurnNotificationService? notificationService,
    UpdateCheckerService? updateChecker,
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
        if (updateChecker != null)
          updateCheckerServiceProvider.overrideWithValue(updateChecker),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 挂载设置页并等异步加载完成（沿用既有 settings_page_test 口径）。
  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container, {
    Size size = const Size(800, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.noScaling),
          child: const CupertinoApp(home: SettingsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 滚动目标进视口（惰性 sliver 未 build 时先 scrollUntilVisible）。
  Future<Finder> scrollTo(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 120);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    return finder;
  }

  /// 滚动到目标后点击。
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = await scrollTo(tester, key);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 读取某个 [CupertinoSwitch] 的当前值。
  bool switchValue(WidgetTester tester, String key) =>
      tester.widget<CupertinoSwitch>(find.byKey(ValueKey(key))).value;

  /// 点击开关并返回翻转后的值。
  Future<bool> toggleSwitch(WidgetTester tester, String key) async {
    await tapKey(tester, key);
    return switchValue(tester, key);
  }

  group('外观 / 对话分组开关回调', () {
    testWidgets('注入通知折叠开关：点击后状态翻转', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      final tile = find.byKey(
        const ValueKey('settings-collapse-injected-notices'),
      );
      await scrollTo(tester, 'settings-collapse-injected-notices');
      final switchFinder = find.descendant(
        of: tile,
        matching: find.byType(CupertinoSwitch),
      );
      expect(switchFinder, findsOneWidget);

      final before = container
          .read(injectedNoticeSettingsProvider)
          .collapseInjectedNotices;
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        container.read(injectedNoticeSettingsProvider).collapseInjectedNotices,
        isNot(before),
      );
    });

    testWidgets('发送快捷键分段控件：切换为 Ctrl+Enter 并写回 provider', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await scrollTo(tester, 'settings-send-message-shortcut');
      final segmented = tester
          .widget<CupertinoSlidingSegmentedControl<ChatSendShortcutMode>>(
            find.descendant(
              of: find.byKey(const ValueKey('settings-send-message-shortcut')),
              matching: find.byType(
                CupertinoSlidingSegmentedControl<ChatSendShortcutMode>,
              ),
            ),
          );
      expect(segmented.groupValue, ChatSendShortcutMode.enter);

      segmented.onValueChanged(ChatSendShortcutMode.ctrlEnter);
      await tester.pumpAndSettle();

      expect(
        container.read(chatSendShortcutSettingsProvider).mode,
        ChatSendShortcutMode.ctrlEnter,
      );
      expect(
        tester
            .widget<CupertinoSlidingSegmentedControl<ChatSendShortcutMode>>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('settings-send-message-shortcut'),
                ),
                matching: find.byType(
                  CupertinoSlidingSegmentedControl<ChatSendShortcutMode>,
                ),
              ),
            )
            .groupValue,
        ChatSendShortcutMode.ctrlEnter,
      );
    });

    testWidgets('对话分组各开关：逐个点击后 provider 状态翻转', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      final hideBefore = container.read(hideReasoningProvider);
      expect(
        await toggleSwitch(tester, 'settings-switch-hide-thinking'),
        isNot(hideBefore),
      );
      expect(container.read(hideReasoningProvider), isNot(hideBefore));

      final statusBefore = container.read(chatStatusLineProvider);
      expect(
        await toggleSwitch(tester, 'settings-switch-chat-status-line'),
        isNot(statusBefore),
      );
      expect(container.read(chatStatusLineProvider), isNot(statusBefore));

      final coalesceBefore = container.read(toolGroupCoalesceProvider);
      expect(
        await toggleSwitch(tester, 'settings-switch-group-tools-by-turn'),
        isNot(coalesceBefore),
      );
      expect(
        container.read(toolGroupCoalesceProvider),
        isNot(coalesceBefore),
      );

      final collapseBefore = container.read(turnCollapseProvider);
      expect(
        await toggleSwitch(tester, 'settings-switch-turn-collapse'),
        isNot(collapseBefore),
      );
      expect(container.read(turnCollapseProvider), isNot(collapseBefore));
    });

    testWidgets('两段式输入栏开关：关闭时联动关掉性能监控，再开回来', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 默认两段式开启 → 性能监控行可见
      expect(container.read(composerTwoPaneProvider), isTrue);
      expect(
        await scrollTo(tester, 'settings-perf-monitor'),
        findsOneWidget,
      );

      // 关掉性能监控开关（onChanged 分支）
      expect(
        await toggleSwitch(tester, 'settings-switch-perf-monitor'),
        isFalse,
      );
      expect(container.read(perfMonitorProvider), isFalse);

      // 关掉两段式 → 联动把性能监控也置 false
      expect(
        await toggleSwitch(tester, 'settings-switch-composer-two-pane'),
        isFalse,
      );
      expect(container.read(composerTwoPaneProvider), isFalse);
      expect(container.read(perfMonitorProvider), isFalse);
      // 两段式关闭后性能监控行不渲染
      expect(
        find.byKey(const ValueKey('settings-perf-monitor')),
        findsNothing,
      );

      // 再开回来 → 行恢复渲染
      expect(
        await toggleSwitch(tester, 'settings-switch-composer-two-pane'),
        isTrue,
      );
      expect(
        await scrollTo(tester, 'settings-perf-monitor'),
        findsOneWidget,
      );
    });

    testWidgets('Mermaid 行：开关切换 + 整行点击各翻转一次', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      final before = container.read(chatRenderMermaidProvider);
      expect(
        await toggleSwitch(tester, 'settings-mermaid-toggle'),
        isNot(before),
      );
      expect(container.read(chatRenderMermaidProvider), isNot(before));

      // 整行 onTap：避开右侧开关，点行左段
      final tileFinder = await scrollTo(tester, 'settings-mermaid-tile');
      final rect = tester.getRect(tileFinder);
      await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
      await tester.pumpAndSettle();

      expect(container.read(chatRenderMermaidProvider), before);
      expect(switchValue(tester, 'settings-mermaid-toggle'), before);
    });

    testWidgets('平滑流速度行：打开选择弹层后点「取消」不改变档位', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 速度行仅在平滑流开启时渲染（先滚到该行触发惰性 build）
      await scrollTo(tester, 'settings-switch-smooth-streaming');
      if (!switchValue(tester, 'settings-switch-smooth-streaming')) {
        await tapKey(tester, 'settings-switch-smooth-streaming');
      }
      expect(container.read(smoothStreamingProvider), isTrue);

      final before = container.read(smoothStreamingSpeedProvider);
      await tapKey(tester, 'settings-smooth-streaming-speed');
      expect(find.text('打字机速度'), findsWidgets);

      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      expect(container.read(smoothStreamingSpeedProvider), before);
      expect(find.byKey(const ValueKey('settings-smooth-streaming-speed')),
          findsOneWidget);
    });

    testWidgets('定时会话分组：事件流 / 审批流 / 内容流开关点击翻转', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      final eventsBefore = container.read(sessionEventsStreamEnabledProvider);
      expect(
        await toggleSwitch(tester, 'settings-switch-session-events-stream'),
        isNot(eventsBefore),
      );
      expect(
        container.read(sessionEventsStreamEnabledProvider),
        isNot(eventsBefore),
      );

      final approvalBefore = container.read(approvalStreamEnabledProvider);
      expect(
        await toggleSwitch(tester, 'settings-switch-approval-stream'),
        isNot(approvalBefore),
      );
      expect(
        container.read(approvalStreamEnabledProvider),
        isNot(approvalBefore),
      );

      final contentBefore = container.read(sessionContentStreamEnabledProvider);
      expect(
        await toggleSwitch(tester, 'settings-switch-session-content-stream'),
        isNot(contentBefore),
      );
      expect(
        container.read(sessionContentStreamEnabledProvider),
        isNot(contentBefore),
      );
    });

    testWidgets('通知分组：需要澄清 / 异常中断两个开关点击翻转并持久化', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      final clarifyBefore = container
          .read(notificationSettingsProvider)
          .notifyClarifyEnabled;
      expect(
        await toggleSwitch(tester, 'settings-switch-notify-clarify'),
        isNot(clarifyBefore),
      );
      expect(
        container.read(notificationSettingsProvider).notifyClarifyEnabled,
        isNot(clarifyBefore),
      );

      final errorsBefore = container
          .read(notificationSettingsProvider)
          .notifyErrorsEnabled;
      expect(
        await toggleSwitch(tester, 'settings-switch-notify-errors'),
        isNot(errorsBefore),
      );
      expect(
        container.read(notificationSettingsProvider).notifyErrorsEnabled,
        isNot(errorsBefore),
      );
    });

    testWidgets('推送测试失败：捕获异常并弹出错误提示，不静默吞错', (tester) async {
      final service = MockTurnNotificationService();
      when(() => service.requestPermission()).thenAnswer((_) async => true);
      when(
        () => service.notifyTurnCompleted(any(), any(), any()),
      ).thenThrow(Exception('push failed'));

      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        notificationService: service,
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-notify-push-test-button');
      await tester.pump(const Duration(milliseconds: 300));

      verify(
        () => service.notifyTurnCompleted(any(), any(), any()),
      ).called(1);
      expect(find.text('推送测试'), findsOneWidget);
      // 复验修正：推送失败改走同文件 _describeError 统一口径 —— ApiException
      // 取其 message，其余回落本地化兜底文案；不再把 error.toString() 原样
      // 暴露给用户。用例核心意图（不静默吞错、有可见反馈）不变，故用
      // 语言无关正则容纳中英两种兜底文案，并反向钉住原始异常串不再外泄。
      expect(find.textContaining('push failed'), findsNothing);
      expect(
        find.textContaining(RegExp('加载失败|Loading failed')),
        findsOneWidget,
      );

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });
  });

  group('二级页面跳转与弹层取消', () {
    testWidgets('会话行信息入口：点击进入二级页', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-entry-session-row-subtitle');

      expect(find.byType(SessionRowSubtitlePage), findsOneWidget);
    });

    testWidgets('桌面入口：点击进入二级页', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-entry-desktop');

      expect(find.byType(DesktopSettingsPage), findsOneWidget);
    });

    testWidgets('删除服务器弹窗点「取消」：连接保留', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn('c1', 'Home', 'http://hermes.local:30002'),
          buildConn('c2', 'Office', 'http://office.example.com:30002'),
        ],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'server-delete-c2');
      expect(find.text('删除服务器'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('删除服务器'), findsNothing);
      expect(
        container.read(connectionsProvider).map((c) => c.id).toList(),
        ['c1', 'c2'],
      );
    });

    testWidgets('推理强度 action sheet 点「取消」：不触发保存', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-reasoning');
      expect(find.text('推理强度'), findsWidgets);

      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      expect(api.reasoningEffortCalls, isEmpty);
      expect(find.text('取消'), findsNothing);
    });
  });

  group('服务器编辑表单分支', () {
    testWidgets('非激活连接：走独立 client 加载 Profile，弹层取消不切换', (tester) async {
      final mockClient = buildMockApiClient(
        handler: (options) {
          if (options.path.endsWith('/api/profiles')) {
            return jsonBody(
              '{"profiles":[{"name":"Default"},{"name":"Work"}],'
              '"active":"Default"}',
            );
          }
          return jsonBody('{}');
        },
      );

      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn('c1', 'Home', 'http://hermes.local:30002'),
          buildConn(
            'c2',
            'Office',
            'http://office.example.com:30002',
            customHeaders: const {'X-Test': '1'},
          ),
        ],
        activeId: 'c1',
        mockApiClient: mockClient,
      );
      await pumpPage(tester, container);

      // c2 非激活 → _getClient 走 factory 分支（含自定义头）
      await tapKey(tester, 'server-edit-c2');
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);

      // 打开 Profile 选择弹层 → 点取消
      await tapKey(tester, 'server-editor-profile-tile');
      expect(find.text('选择 Profile'), findsOneWidget);

      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      expect(find.text('选择 Profile'), findsNothing);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('新增：地址缺协议 → 校验失败并停留表单', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'server-add');
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-url')),
        'hermes.local:30002',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      expect(
        find.text('请输入有效的服务器地址，例如 https://hermes.example.com:8787'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-editor-url')),
        findsOneWidget,
      );
      expect(container.read(connectionsProvider), hasLength(1));
    });

    testWidgets('新增：名称为空 → 用地址主机名回填', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'server-add');
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-url')),
        'http://lab.example.com:30002',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      final connections = container.read(connectionsProvider);
      expect(connections, hasLength(2));
      expect(connections.last.name, 'lab.example.com');
      expect(connections.last.baseUrl, 'http://lab.example.com:30002');
      expect(find.text('lab.example.com'), findsWidgets);
    });

    testWidgets('编辑带自定义头 + 填密码：登录抛非鉴权异常 → 提示无法连接且不落库', (
      tester,
    ) async {
      final throwingApi = _ThrowingLoginApi();
      when(() => throwingApi.login(any())).thenThrow(Exception('socket closed'));

      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn(
            'c2',
            'Office',
            'http://office.example.com:30002',
            customHeaders: const {'X-Test': '1'},
          ),
        ],
        activeId: 'c2',
        loginApi: throwingApi,
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'server-edit-c2');
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-password')),
        'secret',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      verify(() => throwingApi.login('secret')).called(1);
      expect(find.text('无法连接到服务器'), findsOneWidget);
      // 表单停留 + 未改名落库
      expect(find.byKey(const ValueKey('server-editor-url')), findsOneWidget);
      expect(container.read(connectionsProvider).single.name, 'Office');
    });
  });

  group('模型选择页刷新与错误态', () {
    testWidgets('刷新按钮 + 下拉刷新均触发 refreshModels', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-default-model');
      expect(find.byKey(const ValueKey('model-option-o3')), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('model-picker-refresh-button')),
      );
      await tester.pumpAndSettle();
      expect(api.refreshModelsCount, 1);

      // 未下拉时刷新条被视口判为 offstage，需 skipOffstage: false 才能取到。
      final refreshControl = tester.widget<CupertinoSliverRefreshControl>(
        find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
      );
      await refreshControl.onRefresh!();
      await tester.pumpAndSettle();
      expect(api.refreshModelsCount, 2);
    });

    testWidgets('刷新失败：显示错误条，点清除后消失', (tester) async {
      final api = buildApi()..refreshModelsError = const UnauthorizedException();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-default-model');
      expect(
        find.byKey(const ValueKey('model-picker-refresh-error')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('model-picker-refresh-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('model-picker-refresh-error')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('model-picker-clear-refresh-error')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('model-picker-refresh-error')),
        findsNothing,
      );
    });

    testWidgets('目录为空：显示暂无可用模型占位', (tester) async {
      final api = FakeSettingsApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-default-model');

      expect(find.text('暂无可用模型'), findsOneWidget);
    });
  });

  group('关于分组：检查更新与自动检查开关', () {
    MockUpdateCheckerService buildChecker(UpdateCheckResult result) {
      final checker = MockUpdateCheckerService();
      when(() => checker.isAutoCheckEnabled()).thenAnswer((_) async => true);
      when(() => checker.setAutoCheckEnabled(any())).thenAnswer((_) async {});
      when(
        () => checker.checkForUpdates(
          isManual: any(named: 'isManual'),
          now: any(named: 'now'),
        ),
      ).thenAnswer((_) async => result);
      return checker;
    }

    testWidgets('有新版本：弹窗展示版本与说明，点「前往下载」打开外链', (tester) async {
      final launcher = _FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;

      const release = GithubRelease(
        tagName: 'v0.1.99',
        htmlUrl: 'https://example.com/release/v0.1.99',
        name: 'v0.1.99',
        body: '修复若干问题',
      );
      final checker = buildChecker(
        UpdateCheckResult.updateAvailable(
          currentVersion: '0.1.46',
          release: release,
        ),
      );
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        updateChecker: checker,
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-check-update-tile');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('发现新版本 v0.1.99'), findsOneWidget);
      expect(find.text('修复若干问题'), findsOneWidget);

      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();

      expect(launcher.launchedUrls, ['https://example.com/release/v0.1.99']);
      verify(
        () => checker.checkForUpdates(
          isManual: true,
          now: any(named: 'now'),
        ),
      ).called(1);
    });

    testWidgets('已是最新：弹窗提示 + 点「好」关闭', (tester) async {
      final checker = buildChecker(
        UpdateCheckResult.upToDate(currentVersion: '0.1.46'),
      );
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        updateChecker: checker,
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-check-update-tile');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('已是最新版本'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('检查失败：弹窗提示稍后重试，点「好」关闭', (tester) async {
      final checker = buildChecker(
        UpdateCheckResult.failed(
          currentVersion: '0.1.46',
          error: Exception('network down'),
          isSilent: false,
        ),
      );
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        updateChecker: checker,
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-check-update-tile');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('检查更新失败，请稍后重试'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('有新版本但说明为空：回落 Release 名，点「取消」不打开外链', (tester) async {
      final launcher = _FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;

      const release = GithubRelease(
        tagName: 'v0.2.0',
        htmlUrl: 'https://example.com/release/v0.2.0',
        name: 'Hotfix Release',
      );
      final checker = buildChecker(
        UpdateCheckResult.updateAvailable(
          currentVersion: '0.1.46',
          release: release,
        ),
      );
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        updateChecker: checker,
      );
      await pumpPage(tester, container);

      await tapKey(tester, 'settings-check-update-tile');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('发现新版本 v0.2.0'), findsOneWidget);
      expect(find.text('Hotfix Release'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(launcher.launchedUrls, isEmpty);
    });

    testWidgets('自动检查更新开关：点击后调用服务持久化', (tester) async {
      final checker = buildChecker(
        UpdateCheckResult.upToDate(currentVersion: '0.1.46'),
      );
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        updateChecker: checker,
      );
      await pumpPage(tester, container);

      await scrollTo(tester, 'settings-auto-check-update-switch');
      expect(switchValue(tester, 'settings-auto-check-update-switch'), isTrue);
      expect(
        await toggleSwitch(tester, 'settings-auto-check-update-switch'),
        isFalse,
      );

      verify(() => checker.setAutoCheckEnabled(false)).called(1);
    });
  });
}
