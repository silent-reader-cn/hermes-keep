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
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/contrast_utils.dart';
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
    fakeKeepaliveService = FakeBackgroundKeepaliveService();
  });

  Widget buildNotificationHost({
    required Brightness brightness,
    required Widget child,
    InAppNotificationItem? bannerItem,
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
        inAppNotificationProvider.overrideWith((ref) => bannerItem),
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
    testWidgets('In-app 悬浮横幅在双主题下的边框、阴影与关闭图标契约', (tester) async {
      const bannerItem = InAppNotificationItem(
        id: 'banner-test-1',
        sessionId: 'session-1',
        title: 'Task Finished',
        message: 'Your background job completed.',
        type: InAppNotificationType.turnCompleted,
      );

      // --- 1. 浅色模式测试 ---
      await tester.pumpWidget(
        buildNotificationHost(
          brightness: Brightness.light,
          bannerItem: bannerItem,
          child: const CupertinoPageScaffold(
            child: Center(child: Text('Content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bannerFinder = find.byKey(
        const ValueKey('in-app-notification-banner-test-1'),
      );
      expect(bannerFinder, findsOneWidget);

      final cardContainer = tester.widget<Container>(
        find
            .descendant(of: bannerFinder, matching: find.byType(Container))
            .first,
      );
      final cardDeco = cardContainer.decoration! as BoxDecoration;
      expect(cardDeco.color, LightSurfaces.card);
      expect(
        cardDeco.border,
        Border.all(color: LightSurfaces.cardBorder, width: 0.5),
      );

      // 装饰性阴影保留
      expect(cardDeco.boxShadow, isNotNull);
      expect(cardDeco.boxShadow!.length, 1);
      expect(cardDeco.boxShadow!.first.offset, const Offset(0, 3));
      expect(cardDeco.boxShadow!.first.blurRadius, 10);

      // 实际消息文字使用 textSecondary，且对卡片背景对比度达标
      final msgText = tester.widget<Text>(
        find.descendant(
          of: bannerFinder,
          matching: find.text('Your background job completed.'),
        ),
      );
      expect(msgText.style?.color, LightSurfaces.textSecondary);
      expect(
        contrastRatio(msgText.style!.color!, cardDeco.color!),
        greaterThanOrEqualTo(4.5),
      );

      // 关闭图标使用 textSecondary，且对比度达标
      final dismissIcon = tester.widget<Icon>(
        find.descendant(
          of: bannerFinder,
          matching: find.byIcon(CupertinoIcons.xmark_circle_fill),
        ),
      );
      expect(dismissIcon.color, LightSurfaces.textSecondary);
      expect(
        contrastRatio(dismissIcon.color!, cardDeco.color!),
        greaterThanOrEqualTo(4.5),
      );

      // --- 2. 深色模式测试 ---
      await tester.pumpWidget(
        buildNotificationHost(
          brightness: Brightness.dark,
          bannerItem: bannerItem,
          child: const CupertinoPageScaffold(
            child: Center(child: Text('Content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkCardContainer = tester.widget<Container>(
        find
            .descendant(of: bannerFinder, matching: find.byType(Container))
            .first,
      );
      final darkCardDeco = darkCardContainer.decoration! as BoxDecoration;
      // 深色下边框严格为 null
      expect(darkCardDeco.border, isNull);

      // 关闭图标在深色下保持原 raw systemGrey 字节 (0xFF8E8E93)
      final darkDismissIcon = tester.widget<Icon>(
        find.descendant(
          of: bannerFinder,
          matching: find.byIcon(CupertinoIcons.xmark_circle_fill),
        ),
      );
      expect(darkDismissIcon.color, const Color(0xFF8E8E93));

      // 销毁组件树以清理挂载的定时器
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
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
