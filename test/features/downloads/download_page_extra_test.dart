import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/features/downloads/download_controller.dart';
import 'package:hermes_ui/features/downloads/download_models.dart';
import 'package:hermes_ui/features/downloads/download_page.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/features/downloads/download_repository.dart';
import 'package:hermes_ui/features/downloads/download_save_service.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 与 `lib/features/downloads/download_page.dart` 内 `_fileShareChannel` 同名，
/// 同一 channel 名下注册的 mock handler 会被库内实例命中。
const MethodChannel _fileShareChannel = MethodChannel(
  'com.silentreader.hermes_ui/file_share',
);

/// `enqueue` 调用参数快照（断言按钮把任务元数据原样透传）。
typedef _EnqueueArgs = ({
  String? sourceUrl,
  String fileName,
  String? mimeType,
  int? expectedBytes,
  String? sessionId,
});

/// 记录型下载控制器：只记录动作调用，不跑真实队列/网络/落盘。
///
/// `build` 一并覆写为空态，避免真控制器启动 `_ensureInitialized` 微任务在
/// FakeAsync 下悬空。
class _RecordingDownloadController extends DownloadController {
  _RecordingDownloadController(this.calls, this.enqueues);

  final List<String> calls;
  final List<_EnqueueArgs> enqueues;

  @override
  DownloadState build() => const DownloadState();

  @override
  Future<void> cancel(String id) async {
    calls.add('cancel:$id');
  }

  @override
  Future<void> retry(String id) async {
    calls.add('retry:$id');
  }

  @override
  Future<void> remove(String id) async {
    calls.add('remove:$id');
  }

  @override
  Future<void> clearTerminalRecords() async {
    calls.add('clearTerminalRecords');
  }

  @override
  Future<String> enqueue({
    String? sourceUrl,
    Uint8List? bytes,
    required String fileName,
    String? mimeType,
    int? expectedBytes,
    String? sessionId,
  }) async {
    calls.add('enqueue:$fileName');
    enqueues.add((
      sourceUrl: sourceUrl,
      fileName: fileName,
      mimeType: mimeType,
      expectedBytes: expectedBytes,
      sessionId: sessionId,
    ));
    return 'enqueued-$fileName';
  }
}

DownloadTask _task({
  required String id,
  required String fileName,
  DownloadStatus status = DownloadStatus.queued,
  String? sourceUrl,
  String? mimeType,
  int? expectedBytes,
  int receivedBytes = 0,
  String? savedPath,
  String? failureMessage,
  int? resumedFromBytes,
  String? sessionId,
  int ageMs = 0,
}) {
  return DownloadTask(
    id: id,
    sourceUrl: sourceUrl ?? 'https://example.com/$fileName',
    fileName: fileName,
    mimeType: mimeType,
    status: status,
    expectedBytes: expectedBytes,
    receivedBytes: receivedBytes,
    savedPath: savedPath,
    failureMessage: failureMessage,
    resumedFromBytes: resumedFromBytes,
    sessionId: sessionId,
    createdAt: DateTime.now().millisecondsSinceEpoch - ageMs,
  );
}

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
  late DownloadRepository repo;
  late Directory tempDir;
  late List<String> calls;
  late List<_EnqueueArgs> enqueues;

  setUp(() async {
    SharedPreferences.setMockInitialValues({kDiagnosticsEnabledKey: true});
    await DiagnosticsService.instance.init();
    await DiagnosticsService.instance.clear();
    db = AppDatabase.memory();
    repo = DownloadRepository(db);
    tempDir = await Directory.systemTemp.createTemp('download_page_extra_');
    calls = <String>[];
    enqueues = <_EnqueueArgs>[];
  });

  tearDown(() async {
    // 日志写入带 500ms debounce Timer，测试结束前必须取消，否则
    // flutter_test 报 “A Timer is still pending”。
    await DiagnosticsService.instance.clear();
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildPage({
    List<DownloadTask> tasks = const <DownloadTask>[],
    Future<void> Function(String path)? onOpenFile,
    Brightness brightness = Brightness.light,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        downloadRepositoryProvider.overrideWithValue(repo),
        downloadSaveServiceProvider.overrideWithValue(
          DownloadSaveService(destinationDirOverride: tempDir),
        ),
        downloadDownloaderProvider.overrideWithValue(
          (uri, {onProgress}) async => Uint8List.fromList([]),
        ),
        downloadControllerProvider.overrideWith(
          () => _RecordingDownloadController(calls, enqueues),
        ),
        downloadTasksProvider.overrideWithValue(tasks),
      ],
      child: CupertinoApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: testDelegates,
        theme: CupertinoThemeData(brightness: brightness),
        home: DownloadPage(onOpenFile: onOpenFile),
      ),
    );
  }

  /// 承载真实 [BuildContext] 的最小宿主（用于直接调顶层 IO 辅助函数）。
  Widget buildContextHost(void Function(BuildContext context) onBuild) {
    return CupertinoApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: testDelegates,
      home: Builder(
        builder: (context) {
          onBuild(context);
          return const SizedBox.shrink();
        },
      ),
    );
  }

  group('下载页顶层纯函数', () {
    test('getDownloadFileTypeIcon：7 种分类各自独立图标', () {
      expect(
        getDownloadFileTypeIcon(DownloadFileType.image),
        CupertinoIcons.photo,
      );
      expect(
        getDownloadFileTypeIcon(DownloadFileType.audio),
        CupertinoIcons.music_note,
      );
      expect(getDownloadFileTypeIcon(DownloadFileType.video), CupertinoIcons.film);
      expect(
        getDownloadFileTypeIcon(DownloadFileType.document),
        CupertinoIcons.doc_text,
      );
      expect(
        getDownloadFileTypeIcon(DownloadFileType.archive),
        CupertinoIcons.archivebox,
      );
      expect(
        getDownloadFileTypeIcon(DownloadFileType.code),
        CupertinoIcons.chevron_left_slash_chevron_right,
      );
      expect(getDownloadFileTypeIcon(DownloadFileType.other), CupertinoIcons.doc);

      // 枚举全覆盖且互不重复（避免新增分类后静默落到默认图标）。
      final icons = DownloadFileType.values.map(getDownloadFileTypeIcon).toList();
      expect(icons.length, DownloadFileType.values.length);
      expect(icons.toSet().length, DownloadFileType.values.length);
    });

    test('localizeDownloadFileType：中文/英文 7 种分类全量映射', () async {
      const zh = AppLocalizations(Locale('zh'));
      const en = AppLocalizations(Locale('en'));

      expect(localizeDownloadFileType(DownloadFileType.image, zh), '图片');
      expect(localizeDownloadFileType(DownloadFileType.audio, zh), '音频');
      expect(localizeDownloadFileType(DownloadFileType.video, zh), '视频');
      expect(localizeDownloadFileType(DownloadFileType.document, zh), '文档');
      expect(localizeDownloadFileType(DownloadFileType.archive, zh), '压缩包');
      expect(localizeDownloadFileType(DownloadFileType.code, zh), '代码');
      expect(localizeDownloadFileType(DownloadFileType.other, zh), '文件');

      expect(localizeDownloadFileType(DownloadFileType.image, en), 'Image');
      expect(localizeDownloadFileType(DownloadFileType.audio, en), 'Audio');
      expect(localizeDownloadFileType(DownloadFileType.video, en), 'Video');
      expect(localizeDownloadFileType(DownloadFileType.document, en), 'Document');
      expect(localizeDownloadFileType(DownloadFileType.archive, en), 'Archive');
      expect(localizeDownloadFileType(DownloadFileType.code, en), 'Code');
      expect(localizeDownloadFileType(DownloadFileType.other, en), 'File');
    });

    test('shareDownloadedFile：成功透传 path/mimeType，异常走诊断兜底且不抛', () async {
      final methodCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_fileShareChannel, (call) async {
            methodCalls.add(call);
            return null;
          });

      await shareDownloadedFile(
        'C:/downloads/app-release.apk',
        mimeType: 'application/vnd.android.package-archive',
      );

      expect(methodCalls, hasLength(1));
      expect(methodCalls.single.method, 'shareFile');
      expect(methodCalls.single.arguments, {
        'path': 'C:/downloads/app-release.apk',
        'mimeType': 'application/vnd.android.package-archive',
      });

      // 原生通道异常：不得向上抛，落诊断日志（error 级 + downloads tag）。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_fileShareChannel, (call) async {
            throw PlatformException(code: 'share_failed', message: 'boom');
          });
      await shareDownloadedFile('C:/downloads/broken.bin');

      final failureLogs = DiagnosticsService.instance.logs
          .where((e) => e.tag == 'downloads' && e.message.contains('分享文件失败'))
          .toList();
      expect(failureLogs, hasLength(1));
      expect(failureLogs.single.level.name, 'error');
      expect(failureLogs.single.errorKind, contains('share_failed'));
    });
  });

  group('CupertinoProgressBar 进度几何', () {
    testWidgets('0/中间值/1.0/越界/null 各档宽度与配色', (tester) async {
      const progressColor = Color(0xFF123456);
      const trackColor = Color(0xFF654321);

      Future<void> pumpBar(double? value, {double height = 4.0}) {
        return tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              child: Center(
                child: SizedBox(
                  width: 200,
                  child: CupertinoProgressBar(
                    value: value,
                    height: height,
                    trackColor: trackColor,
                    progressColor: progressColor,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      Finder boxes() => find.descendant(
        of: find.byType(CupertinoProgressBar),
        matching: find.byType(Container),
      );

      final cases = <({double? value, double expectedWidth})>[
        (value: 0.0, expectedWidth: 0),
        (value: 0.25, expectedWidth: 50),
        (value: 0.5, expectedWidth: 100),
        (value: 1.0, expectedWidth: 200),
        (value: -0.5, expectedWidth: 0),
        (value: 1.5, expectedWidth: 200),
        (value: null, expectedWidth: 0),
      ];

      for (final item in cases) {
        await pumpBar(item.value);
        expect(boxes(), findsNWidgets(2), reason: 'value=${item.value}');

        final track = tester.widget<Container>(boxes().first);
        expect(
          (track.decoration! as BoxDecoration).color,
          trackColor,
          reason: 'value=${item.value}',
        );
        expect(
          (track.decoration! as BoxDecoration).borderRadius,
          BorderRadius.circular(2),
        );
        expect(tester.getSize(boxes().first).height, 4.0);

        final fill = tester.widget<Container>(boxes().last);
        expect((fill.decoration! as BoxDecoration).color, progressColor);
        expect(
          tester.getSize(boxes().last).width,
          closeTo(item.expectedWidth, 0.001),
          reason: 'value=${item.value} 宽度应按 clamp(0,1) 比例铺开',
        );
      }

      // 自定义高度同时作用于轨道与进度块（圆角半径跟随 height/2）。
      await pumpBar(0.5, height: 8);
      expect(tester.getSize(boxes().first).height, 8.0);
      expect(tester.getSize(boxes().last).height, 8.0);
      expect(tester.getSize(boxes().last).width, closeTo(100, 0.001));
      expect(
        (tester.widget<Container>(boxes().first).decoration! as BoxDecoration)
            .borderRadius,
        BorderRadius.circular(4),
      );

      // 未传色值：轨道回落 systemGrey5，进度回落主题 primaryColor。
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: SizedBox(
                width: 100,
                child: CupertinoProgressBar(value: 1.0),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(CupertinoProgressBar));
      final defaultBoxes = find.descendant(
        of: find.byType(CupertinoProgressBar),
        matching: find.byType(Container),
      );
      expect(
        (tester.widget<Container>(defaultBoxes.first).decoration!
                as BoxDecoration)
            .color,
        CupertinoColors.systemGrey5.resolveFrom(context),
      );
      expect(
        (tester.widget<Container>(defaultBoxes.last).decoration! as BoxDecoration)
            .color,
        CupertinoTheme.of(context).primaryColor,
      );
      expect(tester.getSize(defaultBoxes.last).width, closeTo(100, 0.001));
    });
  });

  group('openDownloadedFile 顶层行为', () {
    testWidgets('文件不存在：落诊断日志并弹出提示弹窗（可关闭）', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(buildContextHost((context) => pageContext = context));
      // CupertinoApp 的本地化委托异步解析：首帧后需 settle，Builder 才会真正
      // 构建并交出已挂载 context。
      await tester.pumpAndSettle();

      final missingPath = '${tempDir.path}/definitely_missing.bin';
      unawaited(openDownloadedFile(pageContext, missingPath));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('提示'), findsOneWidget);
      expect(find.text('文件已被移动或删除'), findsOneWidget);
      expect(
        DiagnosticsService.instance.logs.any(
          (e) => e.tag == 'downloads' && e.message.contains('文件不存在'),
        ),
        isTrue,
      );

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(File(missingPath).existsSync(), isFalse);

      // 消化诊断写入的 500ms debounce Timer。
      await tester.pump(const Duration(milliseconds: 600));
    });

    // ⚠️ 该用例会真实调用 Windows 资源管理器（explorer /select, <path>），
    // 可能在桌面上弹出一个定位窗口——这是被覆盖分支本身的副作用，
    // 非测试污染；若不希望有此副作用，删除本用例即可。
    testWidgets('文件存在 + Windows 平台：走资源管理器定位分支且不弹错误框', (tester) async {
      final path = (await tester.runAsync(() async {
        final file = File('${tempDir.path}/locate_me.txt');
        await file.writeAsString('payload');
        return file.path;
      }))!;

      late BuildContext pageContext;
      await tester.pumpWidget(buildContextHost((context) => pageContext = context));
      // CupertinoApp 的本地化委托异步解析：首帧后需 settle，Builder 才会真正
      // 构建并交出已挂载 context。
      await tester.pumpAndSettle();

      await tester.runAsync(() => openDownloadedFile(pageContext, path));
      await tester.pump();

      expect(File(path).existsSync(), isTrue);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(
        DiagnosticsService.instance.logs
            .where((e) => e.message.contains('打开文件异常')),
        isEmpty,
      );
    });

    testWidgets('customOpener 注入时短路平台分支，不再校验文件存在性', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(buildContextHost((context) => pageContext = context));
      // CupertinoApp 的本地化委托异步解析：首帧后需 settle，Builder 才会真正
      // 构建并交出已挂载 context。
      await tester.pumpAndSettle();

      final opened = <String>[];
      await tester.runAsync(
        () => openDownloadedFile(
          pageContext,
          '${tempDir.path}/never_written.bin',
          customOpener: (path) async => opened.add(path),
        ),
      );

      expect(opened, ['${tempDir.path}/never_written.bin']);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });
  });

  group('DownloadPage 任务状态卡片补充', () {
    testWidgets('下载中未预期总大小：展示已接收大小，含断点续传后缀', (tester) async {
      final tasks = [
        _task(
          id: 'unknown-size',
          fileName: 'stream.bin',
          status: DownloadStatus.downloading,
          receivedBytes: 1536,
          resumedFromBytes: 512,
        ),
        _task(
          id: 'unknown-size-fresh',
          fileName: 'fresh.bin',
          status: DownloadStatus.downloading,
          receivedBytes: 0,
          ageMs: 10,
        ),
      ];

      await tester.pumpWidget(buildPage(tasks: tasks));
      await tester.pumpAndSettle();

      expect(find.text('下载中… (1.5 KB) · 已续传 512 B'), findsOneWidget);
      expect(find.text('下载中… (0 B)'), findsOneWidget);
      expect(find.byType(CupertinoProgressBar), findsNWidgets(2));

      // 未传自定义打开回调时，下载中卡片只有取消按钮。
      expect(find.byKey(const ValueKey('download-cancel-unknown-size')), findsOneWidget);
      expect(find.byKey(const ValueKey('download-open-unknown-size')), findsNothing);
      expect(find.byKey(const ValueKey('download-retry-unknown-size')), findsNothing);
      expect(find.byKey(const ValueKey('download-delete-unknown-size')), findsNothing);
    });

    testWidgets('排队中/下载中：「取消」按钮分别调用 controller.cancel', (tester) async {
      final tasks = [
        _task(id: 'q1', fileName: 'queued.zip'),
        _task(
          id: 'd1',
          fileName: 'running.mp4',
          status: DownloadStatus.downloading,
          expectedBytes: 2048,
          receivedBytes: 1024,
          ageMs: 10,
        ),
      ];

      await tester.pumpWidget(buildPage(tasks: tasks));
      await tester.pumpAndSettle();

      expect(find.text('等待中'), findsOneWidget);
      expect(find.text('50% (1.0 KB / 2.0 KB)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('download-cancel-q1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('download-cancel-d1')));
      await tester.pump();

      expect(calls, ['cancel:q1', 'cancel:d1']);
    });

    testWidgets('失败/已取消：「重试」调 retry、「删除」调 remove', (tester) async {
      final tasks = [
        _task(
          id: 'f1',
          fileName: 'broken.zip',
          status: DownloadStatus.failed,
          failureMessage: 'HTTP 500',
        ),
        _task(
          id: 'c1',
          fileName: 'stopped.zip',
          status: DownloadStatus.cancelled,
          ageMs: 10,
        ),
      ];

      await tester.pumpWidget(buildPage(tasks: tasks));
      await tester.pumpAndSettle();

      expect(find.text('失败：HTTP 500'), findsOneWidget);
      expect(find.text('已取消'), findsOneWidget);
      expect(find.byKey(const ValueKey('download-open-f1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('download-retry-f1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('download-delete-f1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('download-retry-c1')));
      await tester.pump();

      expect(calls, ['retry:f1', 'remove:f1', 'retry:c1']);
    });

    testWidgets('完成态（文件存在）：「打开」与「分享」都把路径透传给 onOpenFile', (tester) async {
      final path = (await tester.runAsync(() async {
        final file = File('${tempDir.path}/report.pdf');
        await file.writeAsString('pdf content');
        return file.path;
      }))!;
      final opened = <String>[];
      final tasks = [
        _task(
          id: 'done1',
          fileName: 'report.pdf',
          mimeType: 'application/pdf',
          status: DownloadStatus.completed,
          expectedBytes: 2048,
          receivedBytes: 2048,
          savedPath: path,
        ),
      ];

      await tester.pumpWidget(
        buildPage(tasks: tasks, onOpenFile: (p) async => opened.add(p)),
      );
      await tester.pumpAndSettle();

      expect(find.text('已完成 · 2.0 KB'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.doc_text), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('download-open-done1')));
      await tester.pumpAndSettle();
      expect(opened, [path]);

      // 非 Android 平台分享走「打开」兜底（桌面转发路径）。
      await tester.tap(find.byKey(const ValueKey('download-share-done1')));
      await tester.pumpAndSettle();
      expect(opened, [path, path]);
      expect(find.byIcon(CupertinoIcons.share), findsOneWidget);
    });

    testWidgets('APK 完成态：非 Android 宿主点「打开」走通用打开路径（不进安装闸门）', (tester) async {
      final path = (await tester.runAsync(() async {
        final file = File('${tempDir.path}/app-release.apk');
        await file.writeAsBytes(List.filled(1024, 0));
        return file.path;
      }))!;
      final opened = <String>[];
      final tasks = [
        _task(
          id: 'apk1',
          fileName: 'app-release.apk',
          mimeType: 'application/vnd.android.package-archive',
          status: DownloadStatus.completed,
          receivedBytes: 1024,
          expectedBytes: 1024,
          savedPath: path,
        ),
      ];

      await tester.pumpWidget(
        buildPage(tasks: tasks, onOpenFile: (p) async => opened.add(p)),
      );
      await tester.pumpAndSettle();

      expect(find.text('打开'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('download-open-apk1')));
      await tester.pumpAndSettle();

      expect(opened, [path]);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('完成态但文件缺失：「重新下载」先 remove 再 enqueue 同源任务', (tester) async {
      final missingPath = '${tempDir.path}/gone.zip';
      final tasks = [
        _task(
          id: 'miss1',
          fileName: 'gone.zip',
          mimeType: 'application/zip',
          status: DownloadStatus.completed,
          expectedBytes: 1048576,
          receivedBytes: 1024,
          savedPath: missingPath,
          sessionId: 'session-1',
        ),
      ];

      await tester.pumpWidget(buildPage(tasks: tasks));
      await tester.pumpAndSettle();

      expect(find.text('文件已被移动或删除'), findsOneWidget);
      expect(find.text('重新下载'), findsOneWidget);
      expect(find.byKey(const ValueKey('download-open-miss1')), findsNothing);
      expect(find.byKey(const ValueKey('download-share-miss1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('download-retry-miss1')));
      await tester.pump();

      expect(calls, ['remove:miss1', 'enqueue:gone.zip']);
      expect(enqueues, hasLength(1));
      expect(enqueues.single.sourceUrl, 'https://example.com/gone.zip');
      expect(enqueues.single.fileName, 'gone.zip');
      expect(enqueues.single.mimeType, 'application/zip');
      expect(enqueues.single.expectedBytes, 1048576);
      expect(enqueues.single.sessionId, 'session-1');

      await tester.tap(find.byKey(const ValueKey('download-delete-miss1')));
      await tester.pump();
      expect(calls.last, 'remove:miss1');
    });

    testWidgets('顶部「清除已完成」调用 controller.clearTerminalRecords', (tester) async {
      final tasks = [
        _task(
          id: 't1',
          fileName: 'old.zip',
          status: DownloadStatus.failed,
        ),
      ];

      await tester.pumpWidget(buildPage(tasks: tasks));
      await tester.pumpAndSettle();

      final clearButton = find.byKey(
        const ValueKey('downloads-clear-terminal-button'),
      );
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pump();

      expect(calls, ['clearTerminalRecords']);
    });

    testWidgets('深色主题：完成态「打开」「重新下载」按钮改走主题 primaryColor', (tester) async {
      final existingPath = (await tester.runAsync(() async {
        final file = File('${tempDir.path}/dark.pdf');
        await file.writeAsString('pdf content');
        return file.path;
      }))!;
      final tasks = [
        _task(
          id: 'dark-open',
          fileName: 'dark.pdf',
          mimeType: 'application/pdf',
          status: DownloadStatus.completed,
          receivedBytes: 10,
          expectedBytes: 10,
          savedPath: existingPath,
        ),
        _task(
          id: 'dark-redownload',
          fileName: 'dark-gone.pdf',
          mimeType: 'application/pdf',
          status: DownloadStatus.completed,
          savedPath: '${tempDir.path}/dark_gone.pdf',
          ageMs: 10,
        ),
      ];

      await tester.pumpWidget(
        buildPage(
          tasks: tasks,
          brightness: Brightness.dark,
          onOpenFile: (path) async {},
        ),
      );
      await tester.pumpAndSettle();

      final openFinder = find.byKey(const ValueKey('download-open-dark-open'));
      final redownloadFinder = find.byKey(
        const ValueKey('download-retry-dark-redownload'),
      );
      final darkPrimary = CupertinoTheme.of(tester.element(openFinder)).primaryColor;

      expect(
        tester.widget<CupertinoButton>(openFinder).color,
        darkPrimary,
      );
      expect(tester.widget<CupertinoButton>(openFinder).color, isNot(LightSurfaces.userDetail));
      expect(
        tester.widget<CupertinoButton>(redownloadFinder).color,
        darkPrimary,
      );
      expect(
        tester.widget<CupertinoButton>(redownloadFinder).color,
        isNot(LightSurfaces.userDetail),
      );

      // 浅色对照组：同任务改走 LightSurfaces.userDetail，证明分支真的按主题切换。
      await tester.pumpWidget(
        buildPage(tasks: tasks, onOpenFile: (path) async {}),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<CupertinoButton>(openFinder).color,
        LightSurfaces.userDetail,
      );
      expect(
        tester.widget<CupertinoButton>(redownloadFinder).color,
        LightSurfaces.userDetail,
      );
    });
  });
}
