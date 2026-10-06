import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';
import 'package:hermes_ui/app/widgets/adaptive_sliver_navigation_bar.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 清晰度取证工装（**非金照基线，不参与 CI 全量**）
//
// 主人在 125% 系统缩放下反馈「界面中的各个文字和图标有点发虚」。本工装把
// 三处代表性场景在 **DPR = 1.25**（= Windows 125% 缩放的分数像素比）下渲染成
// PNG，并落一份 `rects.json`（每个目标的物理像素矩形），供
// `tools/crispness_metrics.py` 做两组量化对照：
//   ① 文字笔画边缘过渡宽度（抗锯齿中间灰像素的占比 / 连续游程）
//   ② 前景（墨）/背景实测对比度（WCAG 公式）
//
// 用法：
//   CRISPNESS_SHOTS=1 CRISPNESS_SHOTS_TAG=after \
//       C:/tmp/f.bat test test/screenshots/crispness_shots_test.dart --update-goldens
// 产物：`.shots/crispness/<tag>/*.png` + `rects.json`（相对路径按 test 进程 cwd）。
//
// 目标：
//   1. `settings-theme-row`    设置页「主题」行（分段控件；旧 cap 220 = 实需，故本就未缩放）
//   1b.`settings-grouping-row` 设置页「会话分组方式」行（**旧 cap 200 < 实需 219.1 ⇒ 0.9129**）
//   2. `settings-contrast-row` 设置页「高对比度模式」行（小字注解 + 开关）
//   3. `chat-top-bar`          聊天顶栏（真实 `AdaptiveSliverNavigationBar`）
//   4. `secondary-text-sample` `secondaryText` 令牌 + [kFontCaption](12pt) 样本
//      —— **令牌样本**（不是整页）：浅色下该令牌正是对比度修复项，单独出图才能
//      把「α 0x99 → 0xBD」的前后差从像素上量出来。
// ---------------------------------------------------------------------------

final bool _capture = Platform.environment['CRISPNESS_SHOTS'] == '1';
const String _skipReason = '设置 CRISPNESS_SHOTS=1 才生成清晰度取证图';
final String _tag = Platform.environment['CRISPNESS_SHOTS_TAG'] ?? 'after';
const String _root = '../../.shots/crispness';

/// 主人机器：Windows 系统缩放 125% ⇒ 视口 DPR = 1.25（**分数像素比**，
/// 「发虚」的物理前提；100%/200% 才是整数 DPR）。
const double _dpr = 1.25;

/// 宽屏逻辑视口（≥ kAdaptiveBreakpoint=900，走设置页宽屏分类导航）。
const double _logicalW = 1280;
const double _logicalH = 900;

final Map<String, List<double>> _rects = <String, List<double>>{};

void main() {
  setUpAll(loadHermesGoldenFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> setView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(_logicalW * _dpr, _logicalH * _dpr);
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
  }

  /// 记录目标矩形（逻辑 → 物理像素），并截图整屏。
  Future<void> record(
    WidgetTester tester,
    String name,
    Finder finder, {
    Rect? explicitRect,
  }) async {
    final rect = explicitRect ?? tester.getRect(finder);
    _rects[name] = <double>[
      rect.left * _dpr,
      rect.top * _dpr,
      rect.width * _dpr,
      rect.height * _dpr,
    ];
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('$_root/$_tag/$name.full.png'),
    );
  }

  testWidgets('设置页两行 @DPR1.25', (tester) async {
    if (!_capture) {
      markTestSkipped(_skipReason);
      return;
    }
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    await setView(tester);
    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: InMemorySecureStorage()),
        ),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        settingsApiFactoryProvider.overrideWithValue((_) => FakeSettingsApi()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          theme: buildCupertinoTheme(Brightness.light),
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 主题行（含分段控件）
    await record(
      tester,
      'settings-theme-row',
      find.ancestor(
        of: find.text('主题'),
        matching: find.byType(CupertinoListTile),
      ),
    );
    // 高对比度模式行（小字注解 + 开关）
    await record(
      tester,
      'settings-contrast-row',
      find.byKey(const ValueKey('settings-force-high-contrast')),
    );
    // 会话分组方式行 —— **中文界面下唯一真正被缩放的设置行**
    // （探针实测：控件实需 219.1，旧 cap 200 ⇒ scale 0.9129，13pt 画成 11.87pt）
    await record(
      tester,
      'settings-grouping-row',
      find.byKey(const ValueKey('settings-session-grouping')),
    );
    // 单标签级裁剪：裁剪区里只有这一个标签 + 纯色底 ⇒ 颜色/边缘指标可精确归因
    // （整行裁剪切含多种文字色，墨色会被纯黑标题/Toggle 带偏）。
    await record(tester, 'seg-label-theme', find.text('跟随系统'));
    await record(tester, 'seg-label-uiscale', find.text('100%'));
    await record(tester, 'seg-label-grouping', find.text('跟随屏幕'));
  });

  testWidgets('聊天顶栏 @DPR1.25', (tester) async {
    if (!_capture) {
      markTestSkipped(_skipReason);
      return;
    }
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    await setView(tester);
    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: CustomScrollView(
          slivers: <Widget>[
            AdaptiveSliverNavigationBar(
              title: '设计稿对齐与真机取证',
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {},
                child: const Icon(CupertinoIcons.back, size: 22),
              ),
              trailing: const Text(
                'gpt-4o',
                style: TextStyle(
                  fontSize: kFontCaption,
                  color: LightSurfaces.textSecondary,
                ),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: ColoredBox(color: LightSurfaces.page),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 导航栏本体是 sliver（`_RenderSliverPinnedPersistentHeaderForWidgets`），
    // 不是 RenderBox ⇒ `getRect` 会抛断言；改取滚动视图顶部 150 逻辑像素作为
    // 「顶栏区域」，这正是用户在聊天页看到的那一条。
    final view = tester.getRect(find.byType(CustomScrollView));
    await record(
      tester,
      'chat-top-bar',
      find.byType(CustomScrollView),
      explicitRect: Rect.fromLTWH(view.left, view.top, view.width, 150),
    );
  });

  testWidgets('secondaryText 令牌样本 @DPR1.25', (tester) async {
    if (!_capture) {
      markTestSkipped(_skipReason);
      return;
    }
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    await setView(tester);
    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        locale: const Locale('zh'),
        home: ColoredBox(
          color: LightSurfaces.card,
          child: Center(
            child: Builder(
              builder: (context) => Text(
                '更新于 2026-10-06 · 125% 缩放',
                key: const ValueKey('secondary-text-sample'),
                style: TextStyle(
                  fontSize: kFontCaption,
                  color: secondaryText.resolveFrom(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await record(
      tester,
      'secondary-text-sample',
      find.byKey(const ValueKey('secondary-text-sample')),
    );
  });

  tearDownAll(() {
    if (!_capture) return;
    // golden 落点是「相对测试文件」解析的（= 仓库根/.shots），而 File 写入是
    // 「相对 test 进程 cwd」解析的（= 仓库根）⇒ 两边都落在 .shots/crispness。
    final dir = Directory('.shots/crispness/$_tag');
    dir.createSync(recursive: true);
    File('.shots/crispness/$_tag/rects.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_rects));
    // ignore: avoid_print
    print('crispness shots → $_root/$_tag  (${_rects.keys.join(', ')})');
  });
}
