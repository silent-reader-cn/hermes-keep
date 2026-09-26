import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_service.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_settings_page.dart';
import 'package:hermes_ui/features/notifications/notification_lifecycle_observer.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  late FakeTurnNotificationService fakeNotificationService;
  late FakeBackgroundKeepaliveService fakeKeepaliveService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeNotificationService = FakeTurnNotificationService();
    fakeKeepaliveService = FakeBackgroundKeepaliveService()..wmReady = true;
  });

  Widget buildNotificationHost({
    required Brightness brightness,
    required Widget child,
    bool permissionEnabled = false,
  }) {
    return ProviderScope(
      overrides: [
        turnNotificationServiceProvider.overrideWithValue(
          fakeNotificationService,
        ),
        backgroundKeepaliveServiceProvider.overrideWithValue(
          fakeKeepaliveService,
        ),
        notificationPermissionProvider.overrideWith((ref) => permissionEnabled),
      ],
      child: CupertinoApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: testDelegates,
        theme: buildCupertinoTheme(brightness),
        home: NotificationLifecycleObserver(child: child),
      ),
    );
  }

  group('Notification Light Surfaces & Dual-Theme Tests', () {
    // 应用内悬浮横幅已移除（前台统一走系统通知），横幅双主题契约用例随之删除。

    testWidgets('NotificationLifecycleObserver 前台恢复时清除全部系统通知', (tester) async {
      final service = _ClearTrackingTurnService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            turnNotificationServiceProvider.overrideWithValue(service),
            backgroundKeepaliveServiceProvider.overrideWithValue(
              fakeKeepaliveService,
            ),
          ],
          child: CupertinoApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            theme: buildCupertinoTheme(Brightness.light),
            home: const NotificationLifecycleObserver(
              child: CupertinoPageScaffold(
                child: Center(child: Text('Content')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final callsBefore = service.clearAllCalls;
      // 先切后台（不触发清理），再回前台（触发一次 clearAll）。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(service.clearAllCalls, callsBefore);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // 观察器契约：每次 resumed 事件都触发一次 clearAll
      expect(service.clearAllCalls, callsBefore + 1);
    });

    testWidgets('BackgroundKeepalivePage 在双主题下的列表标题与状态图标契约', (tester) async {
      // --- 1. 浅色模式测试 ---
      await tester.pumpWidget(
        buildNotificationHost(
          brightness: Brightness.light,
          permissionEnabled: false,
          child: const BackgroundKeepalivePage(),
        ),
      );
      await tester.pumpAndSettle();

      // 浅色下 section header 显式指定 textSecondary
      final lightHeader = tester.widget<Text>(
        find.descendant(
          of: find.byType(CupertinoListSection).first,
          matching: find.text('后台保活'),
        ),
      );
      expect(lightHeader.style?.color, LightSurfaces.textSecondary);

      // 浅色下 WorkManager 状态图标使用 statusGreenText
      final lightCheckmark = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-bg-workmanager-status')),
          matching: find.byIcon(CupertinoIcons.checkmark_seal_fill),
        ),
      );
      final context = tester.element(
        find.byKey(const ValueKey('settings-bg-workmanager-status')),
      );
      expect(lightCheckmark.color, statusGreenText.resolveFrom(context));

      // --- 2. 深色模式测试 ---
      await tester.pumpWidget(
        buildNotificationHost(
          brightness: Brightness.dark,
          permissionEnabled: false,
          child: const BackgroundKeepalivePage(),
        ),
      );
      await tester.pumpAndSettle();

      // 深色下 section header style 必须为 null，继承 SDK 默认 _kHeaderFooterColor
      final darkHeader = tester.widget<Text>(
        find.descendant(
          of: find.byType(CupertinoListSection).first,
          matching: find.text('后台保活'),
        ),
      );
      expect(darkHeader.style, isNull);

      // 深色下 WorkManager 状态图标严格保留原常量 0xFF34C759
      final darkCheckmark = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-bg-workmanager-status')),
          matching: find.byIcon(CupertinoIcons.checkmark_seal_fill),
        ),
      );
      expect(darkCheckmark.color, const Color(0xFF34C759));

      // 销毁组件树以清理定时器
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

/// 统计 clearAll 调用次数的最小 fake（观察器回前台清通知契约专用）。
class _ClearTrackingTurnService implements TurnNotificationService {
  int clearAllCalls = 0;

  @override
  Future<void> clearAll() async => clearAllCalls++;

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
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<String?> getLaunchSessionId() async => null;
}
