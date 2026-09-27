import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/mcp.dart';
import 'package:hermes_ui/core/update/github_release.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/settings/settings_subpages.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 批 5 · C1「settings 系弹窗迁移（D1 四档宽）」真渲染目检工装
// （**非金照基线，不参与 CI**）
//
// 用法（改动前后各跑一次，同一份工装 → 图可直接对照）：
//   DIALOG_SHOTS=1 DIALOG_SHOTS_TAG=before C:/tmp/f.bat test \
//       test/screenshots/c1_settings_dialogs_shots_test.dart --update-goldens
//   …落码后把 TAG 换成 after 再跑一次。
//   不带 DIALOG_SHOTS=1 时全部 skip，`flutter test` 全量零影响。
//
// 产物：`.shots/dialogs/<tag>/<name>-<light|dark>.png`
//   - 宽屏 1280×800 逻辑 @2x（≥900 → 卡片形态）
//   - 窄屏 800×600 逻辑 @2x（<900 → 系统 CupertinoAlertDialog）
//
// 覆盖四条**真实调用点**路径（每条宽窄各一组、各浅暗两图）：
//   1. `c1-settings-server-delete`  —— SettingsPage 服务器行删除确认（confirm 380）
//   2. `c1-settings-repo-fallback`  —— 关于页外链失败兜底（confirm 380，两动作）
//   3. `c1-settings-update-available` —— 关于页「发现有新版本」（wideForm 760，长说明）
//   4. `c1-mcp-delete-confirm`      —— MCP 服务器删除确认（confirm 380，破坏性）
//
// 窄屏那几组的用途很具体：before/after 两张 `*-narrow.png` **必须逐字节相同**
// —— 这是「窄屏逐像素不变」的可视证据（工装不注入任何测试专用 UI，宿主是
// 真实页面、字体是真字体、主题是真主题）。
//
// 与产品代码的关系：不修改任何 `lib/` 代码，只注入 fake API + 演示数据。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip。
final bool _capture = Platform.environment['DIALOG_SHOTS'] == '1';

/// 产物子目录标签（before / after），默认 after。
final String _tag = Platform.environment['DIALOG_SHOTS_TAG'] ?? 'after';

/// 产物根目录（相对本文件：test/screenshots/ → 仓库根 .shots；与批 5A 同根）。
const String _shotRoot = '../../.shots/dialogs';

/// 宽屏逻辑尺寸（≥ kAdaptiveBreakpoint=900）。
const double _wideLogicalWidth = 1280;
const double _wideLogicalHeight = 800;

/// 窄屏逻辑尺寸（< 900 → 单列 + 系统弹窗）。
const double _narrowLogicalWidth = 800;
const double _narrowLogicalHeight = 600;

/// 截图倍率（物理 = 逻辑 × 2）。
const double _dpr = 2.0;

/// 演示服务器连接（两条，删除第二条才有「删掉一个还剩一个」的真实语义）。
ServerConnection _conn(String id, String name, String url) => ServerConnection(
  id: id,
  name: name,
  baseUrl: url,
  createdAt: DateTime.utc(2026, 1, 1),
);

/// 「发现有新版本」演示 Release：多行说明 = wideForm 760 的存在理由。
const GithubRelease _demoRelease = GithubRelease(
  tagName: 'v0.1.99',
  htmlUrl:
      'https://github.com/silent-reader-cn/hermes-keep/releases/tag/v0.1.99',
  name: 'v0.1.99',
  body:
      '新增\n'
      '· 弹窗四档宽（确认 380 / 单选 460 / 表单 560 / 宽表单 760）\n'
      '· 表单行宽屏「左 label / 右控件」横排\n'
      '\n'
      '修复\n'
      '· 宽屏下确认框仍是 270 窄条的问题\n'
      '· 长 Release 说明在弹窗里看不全的问题\n'
      '\n'
      '其它\n'
      '· 窄屏形态（系统弹窗）逐像素不变，仅宽屏换卡片\n',
);

/// 假外链平台：返回 false（模拟「无浏览器 / 被策略拦截」）→ 走兜底弹窗。
class _FailingUrlLauncher extends UrlLauncherPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => false;
}

/// 演示更新检测服务：自动检查关（避免挂载即弹窗），手动检查返回「有新版」。
class _DemoUpdateChecker extends UpdateCheckerService {
  _DemoUpdateChecker()
    : super(
        currentVersion: '0.1.51+57',
        currentVersionResolver: () async => '0.1.51+57',
      );

  @override
  Future<bool> isAutoCheckEnabled() async => false;

  @override
  Future<UpdateCheckResult> checkForUpdates({
    bool isManual = false,
    DateTime? now,
  }) async => isManual
      ? UpdateCheckResult.updateAvailable(
          currentVersion: '0.1.51+57',
          release: _demoRelease,
        )
      : UpdateCheckResult.skippedDisabled(currentVersion: '0.1.51+57');
}

/// 自动检查开关控制器（快照里开关呈「开」，与真机默认一致）。
class _AutoCheckOn extends AutoCheckUpdateController {
  @override
  bool build() => true;
}

void main() {
  late UrlLauncherPlatform originalLauncher;

  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalLauncher = UrlLauncherPlatform.instance;
    // 默认：外链失败兜底（关于页「Hermes UI」行会弹地址框）。
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

  /// 挂宿主 → 可选 [navigate]（宽屏先点左栏分类）→ 可选 [interact]（触发弹窗）→ 截图。
  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
    required bool wide,
    required Widget home,
    List<Override> overrides = const [],
    Future<void> Function(WidgetTester tester)? navigate,
    Future<void> Function(WidgetTester tester)? interact,
    FakeSettingsApi? settingsApi,
  }) async {
    final physicalWidth =
        (wide ? _wideLogicalWidth : _narrowLogicalWidth) * _dpr;
    final physicalHeight =
        (wide ? _wideLogicalHeight : _narrowLogicalHeight) * _dpr;
    tester.view.physicalSize = Size(physicalWidth, physicalHeight);
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://hermes.local:30002'),
          ),
          connectionStoreProvider.overrideWithValue(await buildStore()),
          settingsApiFactoryProvider.overrideWithValue(
            (_) => settingsApi ?? FakeSettingsApi(),
          ),
          autoCheckUpdateEnabledProvider.overrideWith(_AutoCheckOn.new),
          updateCheckerServiceProvider.overrideWithValue(_DemoUpdateChecker()),
          ...overrides,
        ],
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(brightness),
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
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
    await tester.pump(const Duration(milliseconds: 400));

    if (navigate != null) {
      await navigate(tester);
      await tester.pumpAndSettle();
    }

    if (interact != null) {
      await interact(tester);
      // 弹窗入场（Cupertino 弹簧 ≈250ms）结算后再截。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Directory('$_shotRoot/$_tag').createSync(recursive: true);
    // 窄屏加 `-narrow` 后缀：**不要**让它与宽屏图同名（同名会互相覆盖，
    // 批 5A 工装即用这个约定，前后对照时按后缀成对取用）。
    final fileName = wide ? name : '$name-narrow';
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile(
        '$_shotRoot/$_tag/$fileName-${brightness == Brightness.dark ? 'dark' : 'light'}.png',
      ),
    );

    await unmountHermesPage(tester);
  }

  /// 宽屏先点左栏分类（<900 是长卷，不需要）。
  Future<void> selectCategory(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) return;
    await tester.tap(finder);
  }

  /// 宽屏（≥900）只渲染当前分类 → 服务器分类要先点左栏。
  Future<void> revealAndTap(WidgetTester tester, Finder finder) async {
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
  }

  /// 同一路径出宽/窄两组、各浅暗两图。
  void shots(
    String title,
    Future<void> Function(WidgetTester tester, Brightness brightness, bool wide)
    body,
  ) {
    for (final wide in [true, false]) {
      final scope = wide ? '宽屏' : '窄屏';
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
        testWidgets('$scope$suffix · $title', (tester) async {
          await body(tester, brightness, wide);
        }, skip: !_capture);
      }
    }
  }

  // -------------------------------------------------------------------------
  // 1. 设置 · 删除服务器确认（settings_page.dart · confirm 380）
  // -------------------------------------------------------------------------
  shots('设置 · 删除服务器确认（confirm 380）', (tester, brightness, wide) async {
    await capture(
      tester,
      name: 'c1-settings-server-delete',
      brightness: brightness,
      wide: wide,
      home: const SettingsPage(),
      navigate: (tester) => selectCategory(tester, 'settings-nav-server'),
      interact: (tester) =>
          revealAndTap(tester, find.byKey(const ValueKey('server-delete-c2'))),
    );
  });

  // -------------------------------------------------------------------------
  // 2. 设置 · 关于页外链失败兜底（settings_page.dart · confirm 380，两动作）
  // -------------------------------------------------------------------------
  shots('设置 · 外链失败兜底（confirm 380）', (tester, brightness, wide) async {
    await capture(
      tester,
      name: 'c1-settings-repo-fallback',
      brightness: brightness,
      wide: wide,
      home: const SettingsPage(),
      navigate: (tester) => selectCategory(tester, 'settings-nav-about'),
      interact: (tester) => revealAndTap(
        tester,
        find.byKey(const ValueKey('settings-repo-tile')),
      ),
    );
  });

  // -------------------------------------------------------------------------
  // 3. 设置 · 发现有新版本（settings_page.dart · wideForm 760，长 Release 说明）
  // -------------------------------------------------------------------------
  shots('设置 · 新版本提示（wideForm 760）', (tester, brightness, wide) async {
    await capture(
      tester,
      name: 'c1-settings-update-available',
      brightness: brightness,
      wide: wide,
      home: const SettingsPage(),
      navigate: (tester) => selectCategory(tester, 'settings-nav-about'),
      interact: (tester) async {
        await revealAndTap(
          tester,
          find.byKey(const ValueKey('settings-check-update-tile')),
        );
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. MCP · 删除服务器确认（mcp_section.dart · confirm 380，破坏性动作）
  // -------------------------------------------------------------------------
  shots('MCP · 删除服务器确认（confirm 380）', (tester, brightness, wide) async {
    final api = FakeSettingsApi()
      ..mcpServersResponse = const McpServersResponse(
        servers: [McpServer(name: 'demo', command: 'npx')],
      );
    await capture(
      tester,
      name: 'c1-mcp-delete-confirm',
      brightness: brightness,
      wide: wide,
      home: const McpPage(),
      settingsApi: api,
      interact: (tester) async {
        await tester.tap(find.byKey(const ValueKey('mcp-server-row-demo')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mcp-delete-demo')));
        await tester.pumpAndSettle();
      },
    );
  });
}
