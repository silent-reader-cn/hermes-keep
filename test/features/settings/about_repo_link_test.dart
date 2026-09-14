import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// 设置 →「关于」→「Hermes UI」行跳转 GitHub 仓库（点击行为回归）。
///
/// 锁死三件事：
/// 1. 该行可点击（chevron 提示）→ 走 url_launcher 外部浏览器打开公开仓库；
/// 2. 平台返回 false（无浏览器/被策略拦截）→ 弹窗给出完整地址，不静默失败；
/// 3. 平台直接抛错 → 同样弹窗兜底，地址可一键复制。

class MockUpdateCheckerService extends Mock implements UpdateCheckerService {}

/// 记录外链调用的假实现；[result]=false 模拟打开失败。
class _FakeUrlLauncher extends UrlLauncherPlatform {
  _FakeUrlLauncher({this.result = true});

  final bool result;
  final List<String> launchedUrls = <String>[];
  final List<LaunchOptions> launchedOptions = <LaunchOptions>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    launchedOptions.add(options);
    return result;
  }
}

/// 平台层直接抛错（如桌面端无可用浏览器）。
class _ThrowingUrlLauncher extends UrlLauncherPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    throw _PlatformFailure();
  }
}

class _PlatformFailure implements Exception {
  @override
  String toString() => '_PlatformFailure';
}

late MockUpdateCheckerService _checker;

Widget _buildPage() {
  return ProviderScope(
    overrides: [updateCheckerServiceProvider.overrideWithValue(_checker)],
    child: const CupertinoApp(
      localizationsDelegates: [
        AppLocalizationsDelegate(),
        DefaultCupertinoLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: [Locale('zh'), Locale('en')],
      locale: Locale('zh'),
      home: SettingsPage(),
    ),
  );
}

void main() {
  late UrlLauncherPlatform originalLauncher;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _checker = MockUpdateCheckerService();
    when(() => _checker.currentVersion).thenReturn('0.1.46');
    when(() => _checker.isAutoCheckEnabled()).thenAnswer((_) async => true);
    when(() => _checker.setAutoCheckEnabled(any())).thenAnswer((_) async {});
    // 页面初始化会自动检查更新：给通用桩，避免裸 Mock 抛类型错。
    when(
      () => _checker.checkForUpdates(
        isManual: any(named: 'isManual'),
        now: any(named: 'now'),
      ),
    ).thenAnswer(
      (_) async => UpdateCheckResult.upToDate(currentVersion: '0.1.46'),
    );
    originalLauncher = UrlLauncherPlatform.instance;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
  });

  /// 「关于」分组置底：先滚到目标行再交互。
  Future<void> pumpAboutSection(WidgetTester tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-repo-tile')),
      100,
    );
    await tester.pumpAndSettle();
  }

  /// 捕获剪贴板写入调用（`Clipboard.setData`）。
  List<MethodCall> captureClipboard(WidgetTester tester) {
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    return calls;
  }

  group('设置「关于」→ Hermes UI 行跳转 GitHub 仓库', () {
    testWidgets('该行可点击（带 chevron），点击后外部浏览器打开仓库地址', (tester) async {
      final fake = _FakeUrlLauncher();
      UrlLauncherPlatform.instance = fake;

      await pumpAboutSection(tester);

      final tileFinder = find.byKey(const ValueKey('settings-repo-tile'));
      expect(tileFinder, findsOneWidget);

      // 可点击行：onTap 已接线 + 行尾 chevron 提示。
      // 注：浅色模式下 SettingsSurfaces 会把 CupertinoListTileChevron
      // 统一替换成同形状 Icon，故按「渲染出的 chevron 图标」断言。
      expect(tester.widget<CupertinoListTile>(tileFinder).onTap, isNotNull);
      expect(
        find.descendant(
          of: tileFinder,
          matching: find.byIcon(CupertinoIcons.right_chevron),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tileFinder, matching: find.text('Hermes UI')),
        findsOneWidget,
      );

      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      expect(fake.launchedUrls, [kHermesUiRepoUrl]);
      expect(
        fake.launchedOptions.single.mode,
        PreferredLaunchMode.externalApplication,
      );
      // 成功打开不弹任何提示框。
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('打开失败（返回 false）→ 弹窗给出地址，可一键复制', (tester) async {
      UrlLauncherPlatform.instance = _FakeUrlLauncher(result: false);
      final clipboardCalls = captureClipboard(tester);

      await pumpAboutSection(tester);
      await tester.tap(find.byKey(const ValueKey('settings-repo-tile')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('操作失败'), findsOneWidget);
      expect(find.text(kHermesUiRepoUrl), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);

      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      final setDataCalls = clipboardCalls
          .where((call) => call.method == 'Clipboard.setData')
          .toList();
      expect(setDataCalls, hasLength(1));
      expect(
        (setDataCalls.single.arguments as Map<Object?, Object?>)['text'],
        kHermesUiRepoUrl,
      );
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('平台抛错（无可用浏览器）→ 同样弹窗兜底，不静默失败', (tester) async {
      UrlLauncherPlatform.instance = _ThrowingUrlLauncher();

      await pumpAboutSection(tester);
      await tester.tap(find.byKey(const ValueKey('settings-repo-tile')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text(kHermesUiRepoUrl), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });
  });
}