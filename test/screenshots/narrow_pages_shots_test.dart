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
import 'package:hermes_ui/core/models/memory.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/memory/memory_api.dart';
import 'package:hermes_ui/features/memory/memory_page.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_memory_api.dart';
import '../helpers/fake_onboarding_login_api.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 窄屏（<900）「改动前 / 改动后」真渲染像素对照工装（批 3 设置 / 记忆）
//
// 用法：
//   NARROW_SHOTS=1 C:/tmp/f.bat test test/screenshots/narrow_pages_shots_test.dart \
//       --update-goldens            # 先出「改动前」基线（另存 .shots/narrow-before/）
//   NARROW_SHOTS=1 C:/tmp/f.bat test test/screenshots/narrow_pages_shots_test.dart
//                                   # 改动后**不加** --update-goldens → 逐像素比对
//
// 每条用例为「页面 × 视口宽 × 浅/暗」各出一张 PNG（dpr 1.0，逻辑尺寸=物理尺寸），
// 直接与 `.shots/narrow/<name>.png` 逐像素比对：窄屏改动后仍全绿 ⇒ 逐像素不变。
// 不设 `NARROW_SHOTS=1` 时全部 skip，不参与 `flutter test` 全量结果。
//
// 与 pages_shots_test 的区别：那份工装固定 1280 宽（宽屏）；本份专钉窄屏
// （400 = 手机、880 = 最宽窄屏，紧贴 900 断点内侧），补上「宽屏工装看不到」
// 的那半张契约。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip。
final bool _capture = Platform.environment['NARROW_SHOTS'] == '1';
const String _skipReason = '设置 NARROW_SHOTS=1 才生成窄屏像素对照图';

/// 第二道门：宽屏「上限生效」目检图（1600 宽 ⇒ 右栏 1060 > 744，限宽真正咬合，
/// 用于目检左右留白相等）。与窄屏像素对照互不干扰。
final bool _captureWideLimit = Platform.environment['WIDE_LIMIT_SHOTS'] == '1';
const String _wideLimitSkipReason = '设置 WIDE_LIMIT_SHOTS=1 才生成宽屏限宽目检图';

/// 产物根目录（相对本文件：test/screenshots/ → 仓库根 .shots）。
const String _shotRoot = '../../.shots';

/// 窄屏视口（物理像素；dpr 1.0 ⇒ 逻辑尺寸同值，均 < kAdaptiveBreakpoint=900）。
const List<double> _narrowWidths = [400.0, 880.0];

const String _demoBaseUrl = 'https://hermes.example.com:8787';

/// 固定 mtime（远早于「今天」）⇒ 相对时间文案稳定为「更新于 …」，跨次运行可比。
final double _fixedMtime =
    DateTime(2026, 9, 20, 12).millisecondsSinceEpoch / 1000;

/// 记忆演示数据：四个分区都有内容；项目上下文含标题/正文/列表/代码块
/// （代码块用于目检「随正文收一档」的字号）。
MemoryResponse _demoMemory() => MemoryResponse(
  memory: '# 我的笔记\n\n- 主人拍方向、柚子拆任务、子代理并行执行\n- 每轮收口必须留「判据」：命令 + 阈值 + 实测输出',
  user: '## 用户画像\n\n资深 Flutter 开发者，Windows + Android 双平台。',
  soul: '## 智能体灵魂\n\n- 结论先行，不写废话\n- 中文排版优先',
  memoryPath: r'C:\Users\Admin\AppData\Local\hermes\memories\memory.md',
  userPath: r'C:\Users\Admin\AppData\Local\hermes\memories\user.md',
  soulPath: r'C:\Users\Admin\AppData\Local\hermes\memories\soul.md',
  memoryMtime: _fixedMtime - 5400,
  userMtime: _fixedMtime - 86400,
  soulMtime: _fixedMtime - 172800,
  projectContext:
      '## 项目上下文 · hermes-ui\n\n'
      '**技术栈**：Flutter + Cupertino（禁 Material 混入）· Riverpod · go_router · drift。\n\n'
      '### 约定\n\n'
      '- 所有改动只在宽屏分支生效，窄屏逐像素不变\n'
      '- 设计稿必须放进真实界面渲染，禁止抽象色块\n\n'
      '### 常用命令\n\n'
      '```\nC:/tmp/f.bat analyze\nC:/tmp/f.bat test\n```\n\n'
      '正文字号：窄屏 15、宽屏 13.5（同一套档位函数）。',
  projectContextName: 'hermes-ui',
  projectContextPath: r'D:\projects\hermes-ui\.hermes\context.md',
  projectContextWorkspace: r'D:\projects\hermes-ui',
  projectContextMtime: _fixedMtime,
  projectContextShadowed: false,
  externalNotesEnabled: true,
);

/// 更新检查 no-op（不出网；与 pages_shots 同款）。
class _NoopUpdateChecker extends UpdateCheckerService {
  @override
  Future<bool> isAutoCheckEnabled() async => true;

  @override
  Future<UpdateCheckResult> checkForUpdates({
    bool isManual = false,
    DateTime? now,
  }) async => UpdateCheckResult.skippedThrottled(currentVersion: '0.1.51+57');
}

Future<ConnectionStore> _demoStore() async {
  final store = ConnectionStore(storage: InMemorySecureStorage());
  await store.save(
    ServerConnection(
      id: 'c1',
      name: 'Home 服务器',
      baseUrl: _demoBaseUrl,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');
  return store;
}

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 页面滚动容器 key（设置页长卷 / 记忆页卡片区）。
  const scrollKeys = {
    'settings': ValueKey('settings-scroll'),
    'memory': ValueKey('memory-scroll'),
  };

  /// 一张图 = 一个「页面 × 视口 × 滚位 × 明暗」切片。
  ///
  /// 长卷页滚多屏（`slices` 屏，每屏 800 逻辑像素），保证「整页逐像素不变」
  /// 而不是只比首屏 —— 首屏之外的改动（例如把左导航误渲到窄屏的深处）同样会被
  /// 像素比对抓住。
  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Widget page,
    required List<Override> overrides,
    required double width,
    required Brightness brightness,
    String dir = 'narrow',
    int slices = 4,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
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
          home: page,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    Directory('$_shotRoot/$dir').createSync(recursive: true);
    final scrollKey = scrollKeys[name];
    for (var slice = 0; slice < slices; slice++) {
      if (slice > 0 && scrollKey != null) {
        await tester.drag(find.byKey(scrollKey), const Offset(0, -800));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile(
          '$_shotRoot/$dir/$name-${width.toInt()}-s$slice-'
          '${brightness == Brightness.dark ? 'dark' : 'light'}.png',
        ),
      );
    }

    await unmountHermesPage(tester);
  }

  void shotPair(
    String title,
    Future<void> Function(WidgetTester tester, double width, Brightness b) body,
  ) {
    for (final width in _narrowWidths) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
        testWidgets('窄屏 ${width.toInt()} $suffix · $title', (tester) async {
          await body(tester, width, brightness);
        }, skip: !_capture);
      }
    }
  }

  shotPair('设置', (tester, width, brightness) async {
    await capture(
      tester,
      name: 'settings',
      page: const SettingsPage(),
      width: width,
      brightness: brightness,
      overrides: await _settingsOverrides(),
    );
  });

  shotPair('记忆', (tester, width, brightness) async {
    await capture(
      tester,
      name: 'memory',
      page: const MemoryPage(),
      width: width,
      brightness: brightness,
      overrides: _memoryOverrides(),
    );
  });

  // 宽屏限宽目检（1600 宽：右栏 1060，744 上限真正咬合 ⇒ 左右留白应各 158）。
  for (final width in [1600.0]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
      testWidgets('宽屏限宽 ${width.toInt()} $suffix · 设置', (tester) async {
        await capture(
          tester,
          name: 'settings',
          page: const SettingsPage(),
          width: width,
          brightness: brightness,
          dir: 'wide-limit',
          overrides: await _settingsOverrides(),
        );
      }, skip: !_captureWideLimit);
      testWidgets('宽屏限宽 ${width.toInt()} $suffix · 记忆', (tester) async {
        await capture(
          tester,
          name: 'memory',
          page: const MemoryPage(),
          width: width,
          brightness: brightness,
          dir: 'wide-limit',
          overrides: _memoryOverrides(),
        );
      }, skip: !_captureWideLimit);
    }
  }

  test('宽屏限宽工装环境自检', () {
    expect(_captureWideLimit, isTrue, reason: _wideLimitSkipReason);
  }, skip: !_captureWideLimit);

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);
}

/// 设置页演示 overrides（同一份数据供窄屏与宽屏限宽工装复用）。
Future<List<Override>> _settingsOverrides() async {
  final store = await _demoStore();
  return _settingsOverrideList(store);
}

List<Override> _settingsOverrideList(ConnectionStore store) {
  return [
    connectionStoreProvider.overrideWithValue(store),
    apiClientProvider.overrideWithValue(ApiClient(baseUrl: _demoBaseUrl)),
    settingsApiFactoryProvider.overrideWithValue((_) => FakeSettingsApi()),
    onboardingApiFactoryProvider.overrideWithValue(
      (baseUrl, headers) => FakeOnboardingLoginApi(),
    ),
    serverEditorApiClientFactoryProvider.overrideWithValue(
      (baseUrl, headers) => ApiClient(baseUrl: _demoBaseUrl),
    ),
    appVersionProvider.overrideWith((ref) async => '0.1.51+57'),
    updateCheckerServiceProvider.overrideWithValue(_NoopUpdateChecker()),
  ];
}

/// 记忆页演示 overrides。
List<Override> _memoryOverrides() => [
  apiClientProvider.overrideWithValue(ApiClient(baseUrl: _demoBaseUrl)),
  memoryApiFactoryProvider.overrideWithValue(
    (_) => FakeMemoryApi(response: _demoMemory()),
  ),
];
