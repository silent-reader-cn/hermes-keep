import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_service.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_settings_page.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/workmanager_registration_probe.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_download_service.dart';

class _FakeProbe implements WorkManagerRegistrationProbe {
  _FakeProbe(this.snapshot);
  final WorkManagerRegistrationSnapshot snapshot;

  @override
  Future<WorkManagerRegistrationSnapshot> probe() async => snapshot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  late FakeTurnNotificationService fakeTurnService;
  late FakeBackgroundKeepaliveService fakeKeepaliveService;
  late WorkManagerRegistrationProbe originalProbe;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeTurnService = FakeTurnNotificationService();
    fakeKeepaliveService = FakeBackgroundKeepaliveService();
    originalProbe = WorkManagerRegistrationProbe.instance;
    debugDefaultTargetPlatformOverride = null;
  });

  tearDown(() {
    WorkManagerRegistrationProbe.instance = originalProbe;
    debugDefaultTargetPlatformOverride = null;
  });

  Widget buildHost({
    required Widget child,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh'),
    List<Override> extraOverrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        turnNotificationServiceProvider.overrideWithValue(fakeTurnService),
        backgroundKeepaliveServiceProvider.overrideWithValue(
          fakeKeepaliveService,
        ),
        notificationPermissionProvider.overrideWith((ref) => true),
        ...extraOverrides,
      ],
      child: CupertinoApp(
        locale: locale,
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: testDelegates,
        theme: buildCupertinoTheme(brightness),
        home: child,
      ),
    );
  }

  group('TASK #113 保活设置页「WorkManager 状态」三态契约测试', () {
    testWidgets('1. 就绪态（Android 且 wmReady == true）→ 绿勾 + 现有文案', (tester) async {
      fakeKeepaliveService.wmReady = true;

      await tester.pumpWidget(
        buildHost(
          child: const BackgroundKeepalivePage(),
        ),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(
        const ValueKey('settings-bg-workmanager-status'),
      );
      expect(tileFinder, findsOneWidget);

      // 绿勾图标
      final greenCheck = find.descendant(
        of: tileFinder,
        matching: find.byIcon(CupertinoIcons.checkmark_seal_fill),
      );
      expect(greenCheck, findsOneWidget);

      final iconWidget = tester.widget<Icon>(greenCheck);
      final element = tester.element(tileFinder);
      expect(iconWidget.color, statusGreenText.resolveFrom(element));

      // 现有文案（zh: 已就绪）
      expect(
        find.descendant(
          of: tileFinder,
          matching: find.text('已就绪（15 分钟周期 + 切后台即时探活兜底）'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('2. 未就绪态（Android 且 wmReady == false）→ 失败标识 + subtitle 含 probe 归因', (tester) async {
      fakeKeepaliveService.wmReady = false;

      const snapshot = WorkManagerRegistrationSnapshot(
        initialized: false,
        creation: 'manual-initialize-failed',
        error: 'IllegalStateException: WorkManager is not initialized properly',
        chain: 'rustLib=loaded urlLauncher=true wakelock=true workmanager=false',
      );
      WorkManagerRegistrationProbe.instance = _FakeProbe(snapshot);

      await tester.pumpWidget(
        buildHost(
          child: const BackgroundKeepalivePage(),
        ),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(
        const ValueKey('settings-bg-workmanager-status'),
      );
      expect(tileFinder, findsOneWidget);

      // 严禁是绿勾
      final greenCheck = find.descendant(
        of: tileFinder,
        matching: find.byIcon(CupertinoIcons.checkmark_seal_fill),
      );
      expect(greenCheck, findsNothing);

      // 必须是红/橙失败标识（CupertinoIcons.exclamationmark_circle_fill）
      final failureIcon = find.descendant(
        of: tileFinder,
        matching: find.byIcon(CupertinoIcons.exclamationmark_circle_fill),
      );
      expect(failureIcon, findsOneWidget);

      final iconWidget = tester.widget<Icon>(failureIcon);
      final element = tester.element(tileFinder);
      expect(iconWidget.color, statusRedText.resolveFrom(element));

      // subtitle 包含 probe describe 归因信息
      expect(
        find.descendant(
          of: tileFinder,
          matching: find.textContaining(snapshot.describe()),
        ),
        findsOneWidget,
      );
      // subtitle 包含「未就绪」
      expect(
        find.descendant(
          of: tileFinder,
          matching: find.textContaining('未就绪'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('3. 不适用态（非 Android，如 Windows）→ 「不适用」文案 + 中性图标，不误报未就绪', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        fakeKeepaliveService.wmReady = false;

        await tester.pumpWidget(
          buildHost(
            child: const BackgroundKeepalivePage(),
          ),
        );
        await tester.pumpAndSettle();

        final tileFinder = find.byKey(
          const ValueKey('settings-bg-workmanager-status'),
        );
        expect(tileFinder, findsOneWidget);

        // 严禁是绿勾
        final greenCheck = find.descendant(
          of: tileFinder,
          matching: find.byIcon(CupertinoIcons.checkmark_seal_fill),
        );
        expect(greenCheck, findsNothing);

        // 中性灰图标（CupertinoIcons.minus_circle）
        final neutralIcon = find.descendant(
          of: tileFinder,
          matching: find.byIcon(CupertinoIcons.minus_circle),
        );
        expect(neutralIcon, findsOneWidget);

        final iconWidget = tester.widget<Icon>(neutralIcon);
        final element = tester.element(tileFinder);
        expect(iconWidget.color, statusGreyText.resolveFrom(element));

        // 呈现「不适用」文案
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.textContaining('不适用'),
          ),
          findsOneWidget,
        );

        // 严禁误报「未就绪」或失败归因
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.textContaining('未就绪'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.textContaining('initialized='),
          ),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
