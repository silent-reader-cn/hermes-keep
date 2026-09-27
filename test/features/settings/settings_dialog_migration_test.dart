import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/app/widgets/hermes_dialog.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/extensions.dart';
import 'package:hermes_ui/core/models/mcp.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/update/github_release.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/settings/settings_subpages.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 批 5 · C1「settings 系弹窗迁移（D1 四档宽）」守卫
//
// 钉死的是**结构性契约**，不是「看起来差不多」：
//
// 1. **宽屏（≥900）走卡片**：每个迁移过的弹窗都渲染 `HermesDialogCard`，
//    且卡片**实测宽度**等于该处声明的档位（380 / 760，写死绝对值 —— 拿
//    `kind.width` 比 `kind.width` 是自证，档位写错也照样绿）；
// 2. **窄屏（<900）仍是系统弹窗**：`CupertinoAlertDialog` 在位、卡片为 0、
//    路由是 `CupertinoDialogRoute` 而**不是** `HermesDialogRoute`、宽度仍是
//    Cupertino 自己的 270 定宽（「窄屏逐像素不变」的结构性判据）；
// 3. **窄屏浅色动作文字口径不变**：动作文字仍是 `LightSurfaces.menuAction` /
//    `statusRedText`（迁移前由 `SettingsSurfaces.dialog` 施加），**不得**回落
//    Cupertino 默认 `activeBlue` —— 这条是像素级不变量在断言层的替身，
//    少了它「窄屏逐像素不变」就只剩一句口号。
//
// 覆盖面：settings 系四处文件里**全部 11 个** `CupertinoAlertDialog` 调用点
// （settings_page 8 + mcp_section 1 + extensions_section 1 +
// auxiliary_models_section 1）。action sheet（`CupertinoActionSheet`）按任务的
// 迁移规则**不迁移**（不是 `CupertinoAlertDialog`），故不在守卫范围。
// ---------------------------------------------------------------------------

/// 宽屏视口（≥ kAdaptiveBreakpoint=900）。
const Size _kWide = Size(1280, 800);

/// 窄屏视口（宽度 < 900 即单列 + 系统弹窗；高度给足以减少滚动摩擦）。
const Size _kNarrow = Size(800, 1200);

/// Cupertino 弹窗默认动作色（主题 primaryColor）——迁移后**不应**出现在
/// 浅色弹窗动作上（浅色口径由调用点显式传入 `LightSurfaces.menuAction`）。
const Color _kCupertinoDefaultActionBlue = Color(0xFF007AFF);

/// 两个 provider 分组 + 一个 extra model 的样例目录。
const List<Map<String, Object?>> _sampleGroups = <Map<String, Object?>>[
  {
    'provider_id': 'openai',
    'name': 'OpenAI',
    'models': [
      {'id': 'gpt-4o', 'name': 'GPT-4o'},
    ],
  },
];

/// 带模型目录 + 推理能力 + 扩展 + MCP 的默认 fake（各用例按需覆盖）。
FakeSettingsApi buildApi() {
  final api = FakeSettingsApi();
  api.modelsResponse = ModelsResponse.fromJson({
    'default_model': 'gpt-4o',
    'active_provider': 'openai',
    'groups': _sampleGroups,
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
    servers: [McpServer(name: 'demo', command: 'npx')],
  );
  return api;
}

ServerConnection _conn(String id, String name, String url) => ServerConnection(
  id: id,
  name: name,
  baseUrl: url,
  createdAt: DateTime.utc(2026, 1, 1),
);

/// 外链平台返回 false（模拟无浏览器）→ 关于页走兜底弹窗。
class _FailingUrlLauncher extends UrlLauncherPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => false;
}

/// 通知服务最小实现（推送测试成功 → `_showNotice` 单动作提示弹窗）。
class _FakeNotifier implements TurnNotificationService {
  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {}

  @override
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {}

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {}

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
  Future<void> clearAll() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<String?> getLaunchSessionId() async => null;
}

/// 手动检查返回固定结果（或直接抛错）的更新检测服务。
class _StubUpdateChecker extends UpdateCheckerService {
  _StubUpdateChecker(this.onManual)
    : super(
        currentVersion: '0.1.51+57',
        currentVersionResolver: () async => '0.1.51+57',
      );

  final Future<UpdateCheckResult> Function() onManual;

  @override
  Future<bool> isAutoCheckEnabled() async => false;

  @override
  Future<UpdateCheckResult> checkForUpdates({
    bool isManual = false,
    DateTime? now,
  }) async => isManual
      ? onManual()
      : UpdateCheckResult.skippedDisabled(currentVersion: '0.1.51+57');
}

/// 自动检查开关（关）：避免挂载即触发静默检查干扰断言。
class _AutoCheckOff extends AutoCheckUpdateController {
  @override
  bool build() => false;
}

/// 演示 Release（多行说明 = wideForm 760 的存在理由）。
const GithubRelease _demoRelease = GithubRelease(
  tagName: 'v0.1.99',
  htmlUrl: 'https://example.com/release/v0.1.99',
  name: 'v0.1.99',
  body: '新增\n· 弹窗四档宽\n\n修复\n· 宽屏确认框仍是 270 窄条\n',
);

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

/// 构造桩 ApiClient（Profile 切换 403 用）。
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

/// 取 [finder] 命中件里每个 `Text` 的**已解析**文字色。
List<Color> _textColors(WidgetTester tester, Finder finder) {
  final colors = <Color>[];
  for (final element in finder.evaluate()) {
    final render = element.renderObject;
    if (render is RenderParagraph) {
      colors.add(render.text.style?.color ?? const Color(0x00000000));
    }
  }
  return colors;
}

/// 一处迁移调用点的用例描述。
///
/// [menuInk] / [dangerInk] = 该弹窗在**窄屏浅色**下应命中的动作文字色件数
/// （`LightSurfaces.menuAction` / `statusRedText`）。逐件计数而不是「至少一个」：
/// 少传一处 `textStyle` 就会精确变红（RED 实测见交付报告）。
typedef _Case = ({
  String name,
  double width,
  int menuInk,
  int dangerInk,
  Future<void> Function(WidgetTester tester, bool wide) open,
});

void main() {
  late UrlLauncherPlatform originalLauncher;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalLauncher = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = _FailingUrlLauncher();
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
  });

  Future<ConnectionStore> buildStore() async {
    final store = ConnectionStore(storage: InMemorySecureStorage());
    await store.save(_conn('c1', 'Home', 'http://hermes.local:30002'));
    await store.save(_conn('c2', 'Office', 'http://office.example.com:30002'));
    await store.setActive('c1');
    return store;
  }

  /// 挂宿主（真主题 + 真中文本地化）。
  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required Widget home,
    required List<Override> overrides,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: CupertinoApp(
          theme: buildCupertinoTheme(Brightness.light),
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 通用 overrides。
  Future<List<Override>> overrides({
    required FakeSettingsApi api,
    ApiClient? client,
    UpdateCheckerService? checker,
    TurnNotificationService? notifier,
  }) async {
    final resolved = client ?? ApiClient(baseUrl: 'http://test.local:30002');
    return <Override>[
      connectionStoreProvider.overrideWithValue(await buildStore()),
      apiClientProvider.overrideWithValue(resolved),
      settingsApiFactoryProvider.overrideWithValue((_) => api),
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => FakeOnboardingLoginApi(),
      ),
      serverEditorApiClientFactoryProvider.overrideWithValue(
        (baseUrl, headers) => resolved,
      ),
      autoCheckUpdateEnabledProvider.overrideWith(_AutoCheckOff.new),
      if (checker != null)
        updateCheckerServiceProvider.overrideWithValue(checker),
      if (notifier != null)
        turnNotificationServiceProvider.overrideWithValue(notifier),
    ];
  }

  /// 宽屏（≥900）SettingsPage 只渲染当前分类 → 先点左栏。
  Future<void> tapNav(WidgetTester tester, bool wide, String item) async {
    if (!wide) return;
    await tester.tap(find.byKey(ValueKey('settings-nav-$item')));
    await tester.pumpAndSettle();
  }

  /// 滚到目标（惰性区外先 scrollUntilVisible）→ ensureVisible → 点击。
  ///
  /// [settle] 默认 true；「检查更新抛异常兜底」那一处**必须**传 false ——
  /// 该分支的弹窗是在 `try` 里 await 的，`finally` 要等弹窗关闭才把
  /// `_isChecking` 置回 false，于是背后的 `CupertinoActivityIndicator`
  /// 一直转，`pumpAndSettle` 必然超时（不是产品缺陷，是工装踩到的坑）。
  Future<void> revealAndTap(
    WidgetTester tester,
    Finder finder, {
    bool settle = true,
  }) async {
    for (var i = 0; i < 20 && finder.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(
        find.byKey(const ValueKey('settings-scroll')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// 宽屏断言：卡片在位 + 宽度 == 档位绝对值 + 系统 alert 为 0 + 路由类型。
  void expectWideCard(WidgetTester tester, double expectedWidth) {
    expect(
      find.byType(HermesDialogCard),
      findsOneWidget,
      reason: '宽屏（≥900）必须走 D1 卡片形态',
    );
    expect(
      find.byType(CupertinoAlertDialog),
      findsNothing,
      reason: '宽屏不得再落回 270 定宽的系统 alert',
    );
    final card = find.byKey(kHermesDialogCardKey);
    expect(card, findsOneWidget);
    expect(
      tester.getSize(card).width,
      expectedWidth,
      reason: '卡片宽度必须等于该处声明的档位（380 / 760…）',
    );
    expect(
      tester.getCenter(card).dx,
      closeTo(_kWide.width / 2, 1.0),
      reason: '宽屏卡片水平居中',
    );
    expect(ModalRoute.of(tester.element(card)), isA<HermesDialogRoute<void>>());
  }

  /// 窄屏断言：系统 alert 在位 + 无卡片 + 270 定宽 + 路由类型 + 浅色动作口径。
  ///
  /// 「浅色动作口径」按**件数**钉：`LightSurfaces.menuAction` 恰好 [menuInk] 件、
  /// `statusRedText`（浅色解析值）恰好 [dangerInk] 件，且**一件都不是** Cupertino
  /// 默认 `primaryColor`。迁移前这套色由 `SettingsSurfaces.dialog` 施加，迁移后
  /// 由调用点显式传 `HermesDialogAction.textStyle` —— 计数就是「一处没漏」的判据。
  void expectNarrowSystemDialog(
    WidgetTester tester, {
    required int menuInk,
    required int dangerInk,
  }) {
    expect(find.byType(HermesDialogCard), findsNothing);
    expect(find.byKey(kHermesDialogCardKey), findsNothing);
    expect(
      find.byType(CupertinoAlertDialog),
      findsOneWidget,
      reason: '窄屏（<900）必须仍是系统 CupertinoAlertDialog',
    );
    expect(
      tester.getSize(find.byType(CupertinoPopupSurface)).width,
      270.0,
      reason: '窄屏宽度仍由 Cupertino 自己定（270），D1 档位不得影响窄屏',
    );
    final route = ModalRoute.of(
      tester.element(find.byType(CupertinoAlertDialog)),
    );
    expect(route, isA<CupertinoDialogRoute<void>>());
    expect(route, isNot(isA<HermesDialogRoute<void>>()));

    final alertContext = tester.element(find.byType(CupertinoAlertDialog));
    final colors = _textColors(
      tester,
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.byType(Text),
      ),
    );
    expect(
      colors,
      isNot(contains(_kCupertinoDefaultActionBlue)),
      reason: '浅色动作文字不得回落 Cupertino 默认 primaryColor（窄屏像素不变量）',
    );
    expect(
      colors.where((color) => color == LightSurfaces.menuAction).length,
      menuInk,
      reason:
          '浅色普通动作文字须逐件取 LightSurfaces.menuAction（与 '
          'SettingsSurfaces.dialog 同值）',
    );
    expect(
      colors
          .where((color) => color == statusRedText.resolveFrom(alertContext))
          .length,
      dangerInk,
      reason:
          '浅色破坏性动作文字须逐件取 statusRedText（与 '
          'SettingsSurfaces.dialog 同值）',
    );
  }

  final List<_Case> cases = <_Case>[
    // 1 ── 设置 · 删除服务器确认（settings_page · confirm 380）
    (
      name: '设置 · 删除服务器确认',
      menuInk: 1,
      dangerInk: 1,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const SettingsPage(),
          overrides: await overrides(api: api),
        );
        await tapNav(tester, wide, 'server');
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('server-delete-c2')),
        );
      },
    ),

    // 2 ── 设置 · 关于页外链失败兜底（settings_page · confirm 380）
    (
      name: '设置 · 外链失败兜底',
      menuInk: 2,
      dangerInk: 0,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const SettingsPage(),
          overrides: await overrides(api: api),
        );
        await tapNav(tester, wide, 'about');
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('settings-repo-tile')),
        );
      },
    ),

    // 3 ── 设置 · 发现有新版本（settings_page · wideForm 760，长 Release 说明）
    (
      name: '设置 · 新版本提示（长说明）',
      menuInk: 2,
      dangerInk: 0,
      width: 760,
      open: (tester, wide) async {
        final api = buildApi();
        final checker = _StubUpdateChecker(
          () async => UpdateCheckResult.updateAvailable(
            currentVersion: '0.1.51+57',
            release: _demoRelease,
          ),
        );
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const SettingsPage(),
          overrides: await overrides(api: api, checker: checker),
        );
        await tapNav(tester, wide, 'about');
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('settings-check-update-tile')),
        );
        await tester.pump(const Duration(milliseconds: 300));
      },
    ),

    // 4 ── 设置 · 已是最新（settings_page · confirm 380）
    (
      name: '设置 · 已是最新',
      menuInk: 1,
      dangerInk: 0,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        final checker = _StubUpdateChecker(
          () async => UpdateCheckResult.upToDate(currentVersion: '0.1.51+57'),
        );
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const SettingsPage(),
          overrides: await overrides(api: api, checker: checker),
        );
        await tapNav(tester, wide, 'about');
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('settings-check-update-tile')),
        );
        await tester.pump(const Duration(milliseconds: 300));
      },
    ),

    // 5 ── 设置 · 检查更新失败（settings_page · confirm 380）
    (
      name: '设置 · 检查更新失败',
      menuInk: 1,
      dangerInk: 0,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        final checker = _StubUpdateChecker(
          () async => UpdateCheckResult.failed(
            currentVersion: '0.1.51+57',
            error: Exception('network down'),
            isSilent: false,
          ),
        );
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const SettingsPage(),
          overrides: await overrides(api: api, checker: checker),
        );
        await tapNav(tester, wide, 'about');
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('settings-check-update-tile')),
        );
        await tester.pump(const Duration(milliseconds: 300));
      },
    ),

    // 6 ── 设置 · 检查更新抛异常兜底（settings_page · confirm 380）
    (
      name: '设置 · 检查更新抛异常兜底',
      menuInk: 1,
      dangerInk: 0,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        final checker = _StubUpdateChecker(
          () async => throw StateError('checker exploded'),
        );
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const SettingsPage(),
          overrides: await overrides(api: api, checker: checker),
        );
        await tapNav(tester, wide, 'about');
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('settings-check-update-tile')),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 300));
      },
    ),

    // 7 ── 设置 · 推送测试提示（settings_page · confirm 380，单动作）
    (
      name: '设置 · 推送测试提示',
      menuInk: 1,
      dangerInk: 0,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const SettingsPage(),
          overrides: await overrides(api: api, notifier: _FakeNotifier()),
        );
        await tapNav(tester, wide, 'notification');
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('settings-notify-push-test-button')),
        );
      },
    ),

    // 8 ── 设置 · Profile 切换失败（settings_page · confirm 380）
    (
      name: '设置 · Profile 切换失败',
      // 正文（错误详情）本身也是 `statusRedText` 一件（动作非破坏性 → 0）。
      menuInk: 1,
      dangerInk: 1,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        final client = buildMockApiClient(
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
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const SettingsPage(),
          overrides: await overrides(api: api, client: client),
        );
        await tapNav(tester, wide, 'server');
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('server-edit-c1')),
        );
        await tester.tap(
          find.byKey(const ValueKey('server-editor-profile-tile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dev'));
        await tester.pumpAndSettle();
      },
    ),

    // 9 ── MCP · 删除服务器确认（mcp_section · confirm 380，破坏性动作）
    (
      name: 'MCP · 删除服务器确认',
      menuInk: 1,
      dangerInk: 1,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const McpPage(),
          overrides: await overrides(api: api),
        );
        await tester.tap(find.byKey(const ValueKey('mcp-server-row-demo')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mcp-delete-demo')));
        await tester.pumpAndSettle();
      },
    ),

    // 10 ── 扩展 · 卸载确认（extensions_section · confirm 380，破坏性动作）
    (
      name: '扩展 · 卸载确认',
      menuInk: 1,
      dangerInk: 1,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const ExtensionsPage(),
          overrides: await overrides(api: api),
        );
        await tester.tap(
          find.byKey(const ValueKey('extension-row-ext-web-search')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('extension-uninstall-ext-web-search')),
        );
        await tester.pumpAndSettle();
      },
    ),

    // 11 ── 辅助模型 · 全部重置确认（auxiliary_models_section · confirm 380）
    (
      name: '辅助模型 · 全部重置确认',
      menuInk: 1,
      dangerInk: 1,
      width: 380,
      open: (tester, wide) async {
        final api = buildApi();
        await pump(
          tester,
          size: wide ? _kWide : _kNarrow,
          home: const AuxiliaryModelsPage(),
          overrides: await overrides(api: api),
        );
        await tester.tap(find.byKey(const ValueKey('settings-aux-reset')));
        await tester.pumpAndSettle();
      },
    ),
  ];

  group('C1 · settings 系弹窗迁移（11 处）', () {
    for (final testCase in cases) {
      testWidgets('宽屏 1280 · ${testCase.name} → ${testCase.width.toInt()} 卡片', (
        tester,
      ) async {
        await testCase.open(tester, true);
        expectWideCard(tester, testCase.width);
      });

      testWidgets('窄屏 800 · ${testCase.name} → 仍是系统弹窗（270 定宽）', (tester) async {
        await testCase.open(tester, false);
        expectNarrowSystemDialog(
          tester,
          menuInk: testCase.menuInk,
          dangerInk: testCase.dangerInk,
        );
      });
    }
  });
}
