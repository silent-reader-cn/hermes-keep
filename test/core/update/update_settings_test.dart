import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/update/github_release.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/downloads/download_controller.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockUpdateCheckerService extends Mock implements UpdateCheckerService {}

class FakeDownloadController extends DownloadController {
  String? lastEnqueuedUrl;
  String? lastEnqueuedName;

  @override
  DownloadState build() => const DownloadState();

  @override
  Future<String> enqueue({
    String? sourceUrl,
    Uint8List? bytes,
    required String fileName,
    String? mimeType,
    int? expectedBytes,
    String? sessionId,
  }) async {
    lastEnqueuedUrl = sourceUrl;
    lastEnqueuedName = fileName;
    return 'fake-task-id';
  }
}

class _TestTriggerWidget extends ConsumerWidget {
  const _TestTriggerWidget({required this.onTap});

  final void Function(BuildContext context, WidgetRef ref) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoButton(
      key: const ValueKey('test-trigger-button'),
      onPressed: () => onTap(context, ref),
      child: const Text('Trigger'),
    );
  }
}

Widget buildTestableWidget({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: CupertinoApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        DefaultCupertinoLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: const Locale('zh'),
      home: child,
    ),
  );
}

void main() {
  late MockUpdateCheckerService mockChecker;

  setUp(() {
    mockChecker = MockUpdateCheckerService();
    when(() => mockChecker.currentVersion).thenReturn('0.1.30');
    when(() => mockChecker.isAutoCheckEnabled()).thenAnswer((_) async => true);
    when(() => mockChecker.setAutoCheckEnabled(any())).thenAnswer((_) async {});
    when(() => mockChecker.checkForUpdates(
      isManual: any(named: 'isManual'),
      now: any(named: 'now'),
    )).thenAnswer(
      (_) async => UpdateCheckResult.upToDate(currentVersion: '0.1.30'),
    );
  });

  group('设置页更新检测与自动更新开关', () {
    testWidgets('1. 设置页渲染「自动检查更新」开关、「检查更新」按钮与版本号', (tester) async {
      SharedPreferences.setMockInitialValues({
        kAutoCheckUpdateEnabledKey: true,
      });

      await tester.pumpWidget(
        buildTestableWidget(
          overrides: [
            updateCheckerServiceProvider.overrideWithValue(mockChecker),
          ],
          child: const SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-auto-check-update-switch')),
        100,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings-version-tile')), findsOneWidget);

      final switchFinder = find.byKey(const ValueKey('settings-auto-check-update-switch'));
      expect(switchFinder, findsOneWidget);
      final cupertinoSwitch = tester.widget<CupertinoSwitch>(switchFinder);
      expect(cupertinoSwitch.value, isTrue);

      expect(find.byKey(const ValueKey('settings-check-update-tile')), findsOneWidget);
    });

    testWidgets('2. 点击「自动检查更新」开关切换状态并持久化', (tester) async {
      SharedPreferences.setMockInitialValues({
        kAutoCheckUpdateEnabledKey: true,
      });

      await tester.pumpWidget(
        buildTestableWidget(
          overrides: [
            updateCheckerServiceProvider.overrideWithValue(mockChecker),
          ],
          child: const SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-auto-check-update-switch')),
        100,
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const ValueKey('settings-auto-check-update-switch'));
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      verify(() => mockChecker.setAutoCheckEnabled(false)).called(1);
    });

    testWidgets('3. 手动点击「检查更新」发现新版本弹窗展示并可点击「前往下载」', (tester) async {
      SharedPreferences.setMockInitialValues({});
      const fakeRelease = GithubRelease(
        tagName: 'v0.1.31',
        htmlUrl: 'https://github.com/silent-reader-cn/hermes-keep/releases/tag/v0.1.31',
        name: 'v0.1.31 更新日志',
        body: '1. 修复已知问题\n2. 优化性能',
      );

      when(() => mockChecker.checkForUpdates(isManual: true)).thenAnswer(
        (_) async => UpdateCheckResult.updateAvailable(
          currentVersion: '0.1.30',
          release: fakeRelease,
        ),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          overrides: [
            updateCheckerServiceProvider.overrideWithValue(mockChecker),
          ],
          child: const SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-check-update-tile')),
        100,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings-check-update-tile')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('发现新版本 v0.1.31'), findsOneWidget);
      expect(find.text('1. 修复已知问题\n2. 优化性能'), findsOneWidget);
      expect(find.text('前往下载'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('4. 手动点击「检查更新」无更新时弹窗提示「已是最新版本」', (tester) async {
      SharedPreferences.setMockInitialValues({});
      when(() => mockChecker.checkForUpdates(isManual: true)).thenAnswer(
        (_) async => UpdateCheckResult.upToDate(
          currentVersion: '0.1.30',
        ),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          overrides: [
            updateCheckerServiceProvider.overrideWithValue(mockChecker),
          ],
          child: const SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-check-update-tile')),
        100,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings-check-update-tile')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('已是最新版本'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });
  });

  group('handleDownloadOrOpenRelease 双端行为测试', () {
    testWidgets('Android 命中 .apk 资产时入队下载器', (tester) async {
      const releaseWithApk = GithubRelease(
        tagName: 'v0.1.31',
        htmlUrl: 'https://github.com/releases/v0.1.31',
        name: 'v0.1.31',
        assets: [
          ReleaseAsset(
            name: 'app-release.apk',
            browserDownloadUrl: 'https://example.com/app-release.apk',
            size: 1024,
          ),
        ],
      );

      final fakeController = FakeDownloadController();

      await tester.pumpWidget(
        buildTestableWidget(
          overrides: [
            downloadControllerProvider.overrideWith(() => fakeController),
          ],
          child: _TestTriggerWidget(
            onTap: (context, ref) async {
              await handleDownloadOrOpenRelease(
                context,
                ref,
                releaseWithApk,
                platform: TargetPlatform.android,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('test-trigger-button')));
      await tester.pumpAndSettle();

      expect(fakeController.lastEnqueuedUrl, 'https://example.com/app-release.apk');
      expect(fakeController.lastEnqueuedName, 'app-release.apk');
      expect(find.text('已加入下载队列，可在下载管理中查看进度'), findsOneWidget);
    });

    testWidgets('Windows 平台使用 urlLauncher 打开资产链接', (tester) async {
      const releaseWithExe = GithubRelease(
        tagName: 'v0.1.31',
        htmlUrl: 'https://github.com/releases/v0.1.31',
        name: 'v0.1.31',
        assets: [
          ReleaseAsset(
            name: 'hermes-ui-setup.exe',
            browserDownloadUrl: 'https://example.com/hermes-ui-setup.exe',
            size: 2048,
          ),
        ],
      );

      Uri? launchedUri;

      await tester.pumpWidget(
        buildTestableWidget(
          child: _TestTriggerWidget(
            onTap: (context, ref) async {
              await handleDownloadOrOpenRelease(
                context,
                ref,
                releaseWithExe,
                platform: TargetPlatform.windows,
                urlLauncher: (uri) async {
                  launchedUri = uri;
                  return true;
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('test-trigger-button')));
      await tester.pumpAndSettle();

      expect(launchedUri?.toString(), 'https://example.com/hermes-ui-setup.exe');
    });

    testWidgets('未找到匹配资产时退化为打开 html_url', (tester) async {
      const releaseNoAsset = GithubRelease(
        tagName: 'v0.1.31',
        htmlUrl: 'https://github.com/releases/v0.1.31',
        name: 'v0.1.31',
      );

      Uri? launchedUri;

      await tester.pumpWidget(
        buildTestableWidget(
          child: _TestTriggerWidget(
            onTap: (context, ref) async {
              await handleDownloadOrOpenRelease(
                context,
                ref,
                releaseNoAsset,
                platform: TargetPlatform.windows,
                urlLauncher: (uri) async {
                  launchedUri = uri;
                  return true;
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('test-trigger-button')));
      await tester.pumpAndSettle();

      expect(launchedUri?.toString(), 'https://github.com/releases/v0.1.31');
    });
  });
}
