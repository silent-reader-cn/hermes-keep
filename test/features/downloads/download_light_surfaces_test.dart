import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/features/downloads/download_confirm_dialog.dart';
import 'package:hermes_ui/features/downloads/download_models.dart';
import 'package:hermes_ui/features/downloads/download_page.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/contrast_utils.dart';
import '../../helpers/fake_download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const List<LocalizationsDelegate<dynamic>> testDelegates = [
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase.memory();
    tempDir = Directory.systemTemp.createTempSync('dl_light_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    await db.close();
  });

  Widget buildDownloadApp({
    required Brightness brightness,
    List<DownloadTask>? tasks,
    Widget? home,
  }) {
    return ProviderScope(
      overrides: [
        ...createDownloadTestOverrides(db: db, tempDir: tempDir),
        if (tasks != null) downloadTasksProvider.overrideWithValue(tasks),
      ],
      child: CupertinoApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: testDelegates,
        theme: buildCupertinoTheme(brightness),
        home: home ?? const DownloadPage(),
      ),
    );
  }

  group('Download Light Surfaces & Dual-Theme Tests', () {
    testWidgets('DownloadPage 空态与重试卡片在双主题下的对比度与深色不变性', (tester) async {
      const fixedTime = 1773278400000;
      const failedTask = DownloadTask(
        id: 'task-failed-1',
        sourceUrl: 'https://example.com/build.tar.gz',
        fileName: 'build.tar.gz',
        mimeType: 'application/gzip',
        status: DownloadStatus.failed,
        failureMessage: 'Network timeout',
        createdAt: fixedTime,
      );

      // --- 1. 浅色主题校验 ---
      await tester.pumpWidget(
        buildDownloadApp(
          brightness: Brightness.light,
          tasks: const [failedTask],
        ),
      );
      await tester.pumpAndSettle();

      // 脚手架背景
      final scaffold = tester.widget<CupertinoPageScaffold>(
        find.byType(CupertinoPageScaffold),
      );
      expect(scaffold.backgroundColor, LightSurfaces.page);

      // 任务卡片容器与发丝线边框
      final taskFinder = find.byKey(
        const ValueKey('download-task-task-failed-1'),
      );
      expect(taskFinder, findsOneWidget);
      final cardContainer = tester.widget<Container>(
        find.descendant(of: taskFinder, matching: find.byType(Container)).first,
      );
      final cardDeco = cardContainer.decoration! as BoxDecoration;
      expect(cardDeco.color, LightSurfaces.card);
      expect(
        cardDeco.border,
        Border.all(color: LightSurfaces.cardBorder, width: 0.5),
      );

      // 重试按钮：浅色使用 userDetail，白字对比度 >= 4.5
      final retryBtnFinder = find.byKey(
        const ValueKey('download-retry-task-failed-1'),
      );
      expect(retryBtnFinder, findsOneWidget);
      final retryBtn = tester.widget<CupertinoButton>(retryBtnFinder);
      expect(retryBtn.color, LightSurfaces.userDetail);
      expect(
        contrastRatio(const Color(0xFFFFFFFF), retryBtn.color!),
        greaterThanOrEqualTo(4.5),
      );

      // --- 2. 深色主题校验 ---
      await tester.pumpWidget(
        buildDownloadApp(
          brightness: Brightness.dark,
          tasks: const [failedTask],
        ),
      );
      await tester.pumpAndSettle();

      // 深色卡片边框必须为 null
      final darkTaskFinder = find.byKey(
        const ValueKey('download-task-task-failed-1'),
      );
      final darkCardContainer = tester.widget<Container>(
        find
            .descendant(of: darkTaskFinder, matching: find.byType(Container))
            .first,
      );
      final darkCardDeco = darkCardContainer.decoration! as BoxDecoration;
      expect(darkCardDeco.border, isNull);

      // 深色重试按钮保留原 primaryColor
      final darkRetryBtn = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('download-retry-task-failed-1')),
      );
      final darkContext = tester.element(
        find.byKey(const ValueKey('download-retry-task-failed-1')),
      );
      expect(darkRetryBtn.color, CupertinoTheme.of(darkContext).primaryColor);

      // --- 3. 空状态文本与图标对比度 ---
      await tester.pumpWidget(
        buildDownloadApp(brightness: Brightness.light, tasks: const []),
      );
      await tester.pumpAndSettle();

      final emptyText = tester.widget<Text>(find.text('暂无下载记录'));
      expect(emptyText.style?.color, LightSurfaces.textSecondary);
      expect(
        contrastRatio(emptyText.style!.color!, LightSurfaces.page),
        greaterThanOrEqualTo(4.5),
      );

      final emptyIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.arrow_down_circle),
      );
      expect(emptyIcon.color, LightSurfaces.textSecondary);

      // 卸载组件树
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('showDownloadConfirmationDialog 按钮在双主题下的契约', (tester) async {
      Widget buildDialogOpener(Brightness brightness) {
        return CupertinoApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          theme: buildCupertinoTheme(brightness),
          localizationsDelegates: testDelegates,
          home: CupertinoPageScaffold(
            child: Builder(
              builder: (ctx) => CupertinoButton(
                key: const ValueKey('open-dialog-btn'),
                onPressed: () async {
                  await showDownloadConfirmationDialog(
                    ctx,
                    fileName: 'release.zip',
                    mimeType: 'application/zip',
                    expectedBytes: 2048,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
      }

      // 浅色模式测试
      await tester.pumpWidget(buildDialogOpener(Brightness.light));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-dialog-btn')));
      await tester.pumpAndSettle();

      final lightCancelText = tester.widget<Text>(
        find.descendant(
          of: find.byType(CupertinoDialogAction),
          matching: find.text('取消'),
        ),
      );
      expect(lightCancelText.style?.color, LightSurfaces.menuAction);
      expect(
        contrastRatio(LightSurfaces.menuAction, LightSurfaces.card),
        greaterThanOrEqualTo(4.5),
      );

      // 关闭弹窗
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 深色模式测试
      await tester.pumpWidget(buildDialogOpener(Brightness.dark));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-dialog-btn')));
      await tester.pumpAndSettle();

      final darkCancelText = tester.widget<Text>(
        find.descendant(
          of: find.byType(CupertinoDialogAction),
          matching: find.text('取消'),
        ),
      );
      // 深色下继承默认，style 为 null
      expect(darkCancelText.style, isNull);

      // 关闭弹窗清理组件树
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 卸载组件树
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
