import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/features/downloads/download_models.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/features/downloads/download_save_service.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotificationService implements TurnNotificationService {
  final List<(String id, String fileName, int size)> downloadCompletedCalls =
      [];
  final List<(String, String, String)> notifyCalls = [];
  final List<(String, String)> clarifyCalls = [];
  final List<(String, String, String)> errorCalls = [];
  int clearAllCalls = 0;
  final List<({String fileName, int receivedBytes, int expectedBytes})>
      progressCalls = [];
  int clearProgressCalls = 0;

  @override
  Future<void> notifyDownloadCompleted(
    String downloadId,
    String fileName,
    int byteSize,
  ) async {
    downloadCompletedCalls.add((downloadId, fileName, byteSize));
  }
  @override
  Future<void> updateDownloadProgress({
    required String fileName,
    required int receivedBytes,
    required int expectedBytes,
    int queuedCount = 0,
  }) async {
    progressCalls.add(
      (fileName: fileName, receivedBytes: receivedBytes, expectedBytes: expectedBytes),
    );
  }

  @override
  Future<void> clearDownloadProgress() async {
    clearProgressCalls++;
  }


  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {
    notifyCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {
    clarifyCalls.add((sessionId, question));
  }

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {
    errorCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<String?> getLaunchSessionId() async => null;
}

class _FailingSaveService extends DownloadSaveService {
  _FailingSaveService({required this.error});
  final Object error;

  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    throw error;
  }

  @override
  Future<String> saveFromFile({
    required String fileName,
    required File sourceFile,
    String? mimeType,
  }) async {
    throw error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tempSaveDir;
  late DownloadSaveService saveService;
  late _FakeNotificationService notificationService;
  late Map<String, Uint8List Function()> mockDownloadResponses;

  setUp(() async {
    SharedPreferences.setMockInitialValues({kDiagnosticsEnabledKey: true});
    await DiagnosticsService.instance.init();
    await DiagnosticsService.instance.clear();

    db = AppDatabase.memory();
    tempSaveDir = Directory.systemTemp.createTempSync(
      'hermes_controller_test_',
    );
    saveService = DownloadSaveService(destinationDirOverride: tempSaveDir);
    notificationService = _FakeNotificationService();
    mockDownloadResponses = {};
  });

  tearDown(() async {
    await db.close();
    try {
      await tempSaveDir.delete(recursive: true);
    } catch (_) {}
  });

  /// 轮询等待 [predicate] 成立（有界超时）。替代固定延迟：CI runner 负载下
  /// 固定毫秒数常常不够，会在终态/副作用落地前断言。
  Future<void> waitUntil(
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 15),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('waitUntil 超时（${reason ?? '条件未成立'}）');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// 等待下载队列静默（无 queued/downloading 任务），替代固定延迟。
  ///
  /// 固定延迟在 CI runner 负载下常常不够：会在任务到终态前断言，断言失败后
  /// tearDown 关闭 drift 连接，而仍在跑的队列链继续落库 → 
  /// "Can't re-open a database after closing it"（同一测试二次报错）。
  Future<void> settleDownloads(
    ProviderContainer container, {
    Duration timeout = const Duration(seconds: 15),
    String? reason,
  }) {
    return waitUntil(
      () => container
          .read(downloadControllerProvider)
          .tasks
          .every(
            (t) =>
                t.status != DownloadStatus.queued &&
                t.status != DownloadStatus.downloading,
          ),
      timeout: timeout,
      reason: reason ?? '队列未静默',
    );
  }

  ProviderContainer createContainer({
    DownloadBytesDownloader? customDownloader,
    DownloadResumableDownloader? customResumableDownloader,
    DownloadSaveService? customSaveService,
    DownloadBackoffCalculator? customBackoff,
    DownloadTempDirectoryResolver? customTempDirectoryResolver,
  }) {
    final effectiveDownloader = customDownloader ??
        (url, {onProgress}) async {
          final key = url.toString();
          if (mockDownloadResponses.containsKey(key)) {
            return mockDownloadResponses[key]!();
          }
          return Uint8List.fromList([1, 2, 3, 4]);
        };

    final effectiveResumable = customResumableDownloader ??
        ((url, {rangeHeader}) async {
          final streamController = StreamController<Uint8List>();
          final initialHeadersCompleter = Completer<Map<String, List<String>>>();

          void completeHeaders([int? total]) {
            if (!initialHeadersCompleter.isCompleted) {
              final h = <String, List<String>>{
                'accept-ranges': ['bytes'],
              };
              if (total != null && total > 0) {
                h['content-length'] = ['$total'];
              }
              initialHeadersCompleter.complete(h);
            }
          }

          unawaited(
            () async {
              try {
                var lastEmitted = 0;
                final bytes = await effectiveDownloader(
                  url,
                  onProgress: (received, total) {
                    completeHeaders(total);
                    if (received > lastEmitted) {
                      final chunk = Uint8List.fromList(List.filled(received - lastEmitted, 7));
                      streamController.add(chunk);
                      lastEmitted = received;
                    }
                  },
                );
                completeHeaders(bytes.length);
                if (bytes.length > lastEmitted) {
                  streamController.add(Uint8List.fromList(bytes.sublist(lastEmitted)));
                }
                unawaited(streamController.close());
              } catch (e, st) {
                if (!initialHeadersCompleter.isCompleted) {
                  initialHeadersCompleter.completeError(e, st);
                } else {
                  streamController.addError(e, st);
                  unawaited(streamController.close());
                }
              }
            }(),
          );

          final headersMap = await initialHeadersCompleter.future;

          return ResumableDownloadResponse(
            statusCode: 200,
            headers: Headers.fromMap(headersMap),
            stream: streamController.stream,
          );
        });

    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        downloadSaveServiceProvider.overrideWithValue(
          customSaveService ?? saveService,
        ),
        turnNotificationServiceProvider.overrideWithValue(notificationService),
        downloadDownloaderProvider.overrideWithValue(effectiveDownloader),
        downloadBackoffProvider.overrideWithValue(
          customBackoff ?? ((_) => Duration.zero),
        ),
        downloadTempDirectoryProvider.overrideWithValue(
          customTempDirectoryResolver ?? (() async => tempSaveDir),
        ),
        downloadResumableDownloaderProvider.overrideWithValue(
          effectiveResumable,
        ),
      ],
    );
  }

  group('#93 下载进度常驻通知同步', () {
    test('下载中调用 updateDownloadProgress（开始 + onProgress 回调），完成后 clear', () async {
      mockDownloadResponses['https://example.com/progress.zip'] = () =>
          Uint8List.fromList(List.filled(64, 7));

      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          // 模拟 dio 分片回调（总量 64）
          onProgress?.call(16, 64);
          onProgress?.call(48, 64);
          return Uint8List.fromList(List.filled(64, 7));
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/progress.zip',
        fileName: 'progress.zip',
        expectedBytes: 64,
      );
      await settleDownloads(container);

      final state = container.read(downloadControllerProvider);
      expect(state.taskById(id)!.status, DownloadStatus.completed);

      // 开始下载（received=0）+ 两次分片 = 至少 2 次进度调用
      expect(notificationService.progressCalls, isNotEmpty);
      expect(
        notificationService.progressCalls.every((c) => c.fileName == 'progress.zip'),
        isTrue,
      );
      // 完成后进度通知被清除（clear 调用 ≥1；开始+分片+完成兜底都会触发）
      expect(notificationService.clearProgressCalls, greaterThanOrEqualTo(1));
    });

    test('下载失败后清进度通知', () async {
      final container = createContainer(
        customDownloader: (url, {onProgress}) async =>
            throw Exception('boom'),
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      await controller.enqueue(
        sourceUrl: 'https://example.com/boom.zip',
        fileName: 'boom.zip',
      );
      await settleDownloads(container);

      final state = container.read(downloadControllerProvider);
      expect(
        state.tasks.every((t) => t.status != DownloadStatus.downloading),
        isTrue,
      );
      expect(notificationService.clearProgressCalls, greaterThanOrEqualTo(1));
    });

    test('取消下载后清进度通知', () async {
      // 慢速下载器：给 cancel 留出时间窗
      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return Uint8List.fromList([1]);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/slow.zip',
        fileName: 'slow.zip',
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await controller.cancel(id);
      await settleDownloads(container, reason: '取消后队列应静默');
      // 清进度通知是取消的异步副作用（状态变更后才落地）：等条件而非固定延迟。
      await waitUntil(
        () => notificationService.clearProgressCalls >= 1,
        reason: '取消后应清进度通知',
      );

      final state = container.read(downloadControllerProvider);
      expect(state.taskById(id)!.status, DownloadStatus.cancelled);
      expect(notificationService.clearProgressCalls, greaterThanOrEqualTo(1));
    });
  });

  group('DownloadController 核心队列与状态机', () {
    test('单任务下载成功：更新 completed、保存文件、触发通知、记录诊断日志', () async {
      mockDownloadResponses['https://example.com/sample.pdf'] = () =>
          Uint8List.fromList([10, 20, 30]);

      final container = createContainer();
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/sample.pdf',
        fileName: 'sample.pdf',
        mimeType: 'application/pdf',
        expectedBytes: 3,
      );

      // 等待 FIFO worker 处理完成
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.completed);
      expect(task.receivedBytes, 3);
      expect(task.savedPath, isNotNull);
      expect(File(task.savedPath!).existsSync(), isTrue);

      // 验证通知触发
      expect(notificationService.downloadCompletedCalls, hasLength(1));
      expect(notificationService.downloadCompletedCalls.single, (
        id,
        'sample.pdf',
        3,
      ));

      // 验证数据库持久化
      final repo = container.read(downloadRepositoryProvider);
      final persisted = await repo.getRecordById(id);
      expect(persisted?.status, DownloadStatus.completed);
      expect(persisted?.savedPath, task.savedPath);

      // 验证诊断日志
      final logs = DiagnosticsService.instance.logs
          .where((l) => l.tag == 'downloads')
          .toList();
      expect(logs.any((l) => l.message.contains('下载完成')), isTrue);
    });

    test('任务下载失败：更新 failed、填充 failureMessage、记录 error 日志', () async {
      final container = createContainer(
        customDownloader: (url, {onProgress}) async =>
            throw Exception('网络连接超时 504'),
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/fail.zip',
        fileName: 'fail.zip',
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.failed);
      expect(task.failureMessage, contains('网络连接超时 504'));
      expect(task.completedAt, isNotNull);

      // 验证数据库
      final repo = container.read(downloadRepositoryProvider);
      final persisted = await repo.getRecordById(id);
      expect(persisted?.status, DownloadStatus.failed);
      expect(persisted?.failureMessage, contains('网络连接超时 504'));
    });

    test('#69 下载过程进度回传：onProgress 中途刷新 receivedBytes/expectedBytes', () async {
      final progressEmitted = Completer<void>();
      final releaseDownload = Completer<void>();

      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          // 模拟 dio 分块回调：先报一半（total 已知），等测试读取中间态后放行。
          onProgress?.call(500, 1000);
          progressEmitted.complete();
          await releaseDownload.future;
          return Uint8List(1000);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/progress.bin',
        fileName: 'progress.bin',
      );

      await progressEmitted.future;
      // 回调里 DateTime.now() 距 epoch 恒 >100ms → 首帧必刷。等一帧 state 更新。
      await Future<void>.delayed(const Duration(milliseconds: 20));

      var task = container.read(downloadControllerProvider).taskById(id);
      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.downloading);
      expect(task.receivedBytes, 500);
      expect(task.expectedBytes, 1000);
      expect(task.progress, closeTo(0.5, 0.01));

      releaseDownload.complete();
      await settleDownloads(container);
      task = container.read(downloadControllerProvider).taskById(id);
      expect(task!.status, DownloadStatus.completed);
    });

    test('#69 total 未知(-1)时进度仍回传 receivedBytes', () async {
      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          onProgress?.call(700, -1);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Uint8List(700);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/unknown_total.bin',
        fileName: 'unknown_total.bin',
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final task = container.read(downloadControllerProvider).taskById(id);
      // 首帧回调即刷 receivedBytes（timeHit）；完成后为 completed+700。
      expect(task!.receivedBytes, 700);
    });

    test('取消排队中任务：状态转为 cancelled 并跳过下载', () async {
      final downloadStarted = Completer<void>();
      final blockFirstDownload = Completer<void>();

      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          if (url.toString().contains('first')) {
            downloadStarted.complete();
            await blockFirstDownload.future;
            return Uint8List(10);
          }
          return Uint8List(20);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);

      // 1. 加入第一个任务（阻塞在下载中）
      final id1 = await controller.enqueue(
        sourceUrl: 'https://example.com/first.bin',
        fileName: 'first.bin',
      );

      await downloadStarted.future;

      // 2. 加入第二个任务（排队中）
      final id2 = await controller.enqueue(
        sourceUrl: 'https://example.com/second.bin',
        fileName: 'second.bin',
      );

      // 取消第二个任务
      await controller.cancel(id2);

      expect(
        container.read(downloadControllerProvider).taskById(id2)?.status,
        DownloadStatus.cancelled,
      );

      // 释放第一个任务
      blockFirstDownload.complete();
      await settleDownloads(container);

      final state = container.read(downloadControllerProvider);
      expect(state.taskById(id1)?.status, DownloadStatus.completed);
      expect(state.taskById(id2)?.status, DownloadStatus.cancelled);
    });

    test('取消正在下载的任务：下载返回后丢弃结果，不保存文件且不发通知', () async {
      final downloadStarted = Completer<void>();
      final finishDownload = Completer<void>();

      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          downloadStarted.complete();
          await finishDownload.future;
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/canceling.bin',
        fileName: 'canceling.bin',
      );

      await downloadStarted.future;
      expect(
        container.read(downloadControllerProvider).taskById(id)?.status,
        DownloadStatus.downloading,
      );

      // 标记取消
      await controller.cancel(id);
      expect(
        container.read(downloadControllerProvider).taskById(id)?.status,
        DownloadStatus.cancelled,
      );

      // 下载返回
      finishDownload.complete();
      await settleDownloads(container);

      final state = container.read(downloadControllerProvider);
      expect(state.taskById(id)?.status, DownloadStatus.cancelled);
      expect(state.taskById(id)?.savedPath, isNull);
      expect(notificationService.downloadCompletedCalls, isEmpty);
    });

    test('重试失败/已取消任务：重新加入队列并成功完成', () async {
      var failOnce = true;
      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          if (failOnce) {
            failOnce = false;
            throw Exception('第一次失败');
          }
          return Uint8List.fromList([42]);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/retry.bin',
        fileName: 'retry.bin',
      );

      await settleDownloads(container);
      expect(
        container.read(downloadControllerProvider).taskById(id)?.status,
        DownloadStatus.failed,
      );

      // 重试
      await controller.retry(id);
      await settleDownloads(container);

      final state = container.read(downloadControllerProvider);
      expect(state.taskById(id)?.status, DownloadStatus.completed);
      expect(state.taskById(id)?.failureMessage, isNull);
      expect(state.taskById(id)?.receivedBytes, 1);
    });

    test('允许重复下载：同 URL 已完成且本地文件存在，再次 enqueue 返回新任务 ID 并重新入队下载', () async {
      var downloadCalls = 0;
      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          downloadCalls++;
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);

      // 第一次下载
      final id1 = await controller.enqueue(
        sourceUrl: 'https://example.com/dedup.png',
        fileName: 'dedup.png',
      );
      await settleDownloads(container);
      expect(downloadCalls, 1);
      final task1 = container.read(downloadControllerProvider).taskById(id1)!;
      expect(task1.status, DownloadStatus.completed);
      expect(File(task1.savedPath!).existsSync(), isTrue);

      // 第二次相同 sourceUrl：本地文件存在，依然生成新任务 ID 并重新下载
      final id2 = await controller.enqueue(
        sourceUrl: 'https://example.com/dedup.png',
        fileName: 'dedup.png',
      );
      expect(id2, isNot(equals(id1)));
      await settleDownloads(container);
      expect(downloadCalls, 2);

      final task2 = container.read(downloadControllerProvider).taskById(id2)!;
      expect(task2.status, DownloadStatus.completed);
      expect(File(task2.savedPath!).existsSync(), isTrue);
      // 落盘层自动添加冲突后缀如 dedup (1).png
      expect(task2.savedPath, isNot(equals(task1.savedPath)));
      expect(task2.savedPath, contains('(1)'));
    });

    test('队列中活跃同 URL 合并：不重复入队', () async {
      final blockDownload = Completer<void>();
      final downloadStarted = Completer<void>();
      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          downloadStarted.complete();
          await blockDownload.future;
          return Uint8List(10);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);

      final id1 = await controller.enqueue(
        sourceUrl: 'https://example.com/merge.bin',
        fileName: 'merge.bin',
      );
      await downloadStarted.future;

      final id2 = await controller.enqueue(
        sourceUrl: 'https://example.com/merge.bin',
        fileName: 'merge.bin',
      );

      expect(id2, equals(id1));
      expect(container.read(downloadControllerProvider).tasks, hasLength(1));

      blockDownload.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    test('remove 与 clearTerminalRecords', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);

      final id1 = await controller.enqueue(
        sourceUrl: 'https://example.com/file1',
        fileName: 'file1',
      );
      final id2 = await controller.enqueue(
        sourceUrl: 'https://example.com/file2',
        fileName: 'file2',
      );
      expect(id2, isNotEmpty);

      await settleDownloads(container);
      expect(container.read(downloadControllerProvider).tasks, hasLength(2));

      await controller.remove(id1);
      expect(container.read(downloadControllerProvider).tasks, hasLength(1));
      expect(container.read(downloadControllerProvider).taskById(id1), isNull);

      await controller.clearTerminalRecords();
      expect(container.read(downloadControllerProvider).tasks, isEmpty);
    });

    test('内存字节模式：直接保存文件，不经过网络下载器，sourceType 为 bytes', () async {
      var networkCalled = false;
      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          networkCalled = true;
          return Uint8List(0);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final rawBytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      final id = await controller.enqueue(
        bytes: rawBytes,
        fileName: 'memory_image.png',
        mimeType: 'image/png',
        expectedBytes: 5,
      );

      await settleDownloads(container);

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.sourceType, DownloadSourceType.bytes);
      expect(task.status, DownloadStatus.completed);
      expect(task.receivedBytes, 5);
      expect(task.savedPath, isNotNull);
      expect(File(task.savedPath!).existsSync(), isTrue);
      expect(File(task.savedPath!).readAsBytesSync(), rawBytes);
      expect(networkCalled, isFalse);

      expect(notificationService.downloadCompletedCalls, hasLength(1));
      expect(notificationService.downloadCompletedCalls.single, (
        id,
        'memory_image.png',
        5,
      ));
    });

    test('Data URI 模式：解码 base64 直接落盘，sourceType 为 bytes 且不调下载器', () async {
      var networkCalled = false;
      final container = createContainer(
        customDownloader: (url, {onProgress}) async {
          networkCalled = true;
          return Uint8List(0);
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      // "hello" in base64: aGVsbG8=
      final id = await controller.enqueue(
        sourceUrl: 'data:text/plain;base64,aGVsbG8=',
        fileName: 'hello.txt',
        mimeType: 'text/plain',
      );

      await settleDownloads(container);

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.sourceType, DownloadSourceType.bytes);
      expect(task.status, DownloadStatus.completed);
      expect(task.savedPath, isNotNull);
      expect(File(task.savedPath!).existsSync(), isTrue);
      expect(File(task.savedPath!).readAsStringSync(), 'hello');
      expect(networkCalled, isFalse);
    });

    test('允许重复下载（内存字节）：本地文件存在时再次 enqueue 返回新任务 ID 并重新落盘', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final rawBytes = Uint8List.fromList([1, 2, 3]);

      final id1 = await controller.enqueue(
        bytes: rawBytes,
        fileName: 'dup_test.bin',
      );
      await settleDownloads(container);

      final task1 = container.read(downloadControllerProvider).taskById(id1)!;
      expect(task1.status, DownloadStatus.completed);
      expect(File(task1.savedPath!).existsSync(), isTrue);

      // 再次 enqueue 相同 fileName 与 bytes：文件存在仍返回新任务 ID 并重新落盘
      final id2 = await controller.enqueue(
        bytes: rawBytes,
        fileName: 'dup_test.bin',
      );
      expect(id2, isNot(equals(id1)));
      await settleDownloads(container);

      final task2 = container.read(downloadControllerProvider).taskById(id2)!;
      expect(task2.status, DownloadStatus.completed);
      expect(File(task2.savedPath!).existsSync(), isTrue);
      expect(task2.savedPath, isNot(equals(task1.savedPath)));
      expect(task2.savedPath, contains('(1)'));
    });

    test('平台保存异常透传（Area D）：DownloadSaveService 抛错捕获置 failed 并记录诊断日志', () async {
      final container = createContainer(
        customSaveService: _FailingSaveService(
          error: const FileSystemException(
            'Permission denied (Scoped Storage)',
          ),
        ),
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/scoped_storage_test.apk',
        fileName: 'scoped_storage_test.apk',
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.failed);
      expect(task.failureMessage, contains('Permission denied'));

      // 验证诊断日志包含错误
      final logs = DiagnosticsService.instance.logs
          .where((l) => l.tag == 'downloads')
          .toList();
      expect(
        logs.any(
          (l) => l.message.contains('保存失败') || l.message.contains('下载失败'),
        ),
        isTrue,
      );
    });
  });

  group('#98 下载自动重试与断点续传', () {
    test('网络短暂故障自动重试：前 2 次失败，第 3 次成功 → completed 且 attemptCount == 2', () async {
      var calls = 0;
      final container = createContainer(
        customResumableDownloader: (url, {rangeHeader}) async {
          calls++;
          if (calls <= 2) {
            throw const SocketException('Connection reset');
          }
          return ResumableDownloadResponse(
            statusCode: 200,
            headers: Headers.fromMap({
              'accept-ranges': ['bytes'],
              'content-length': ['4'],
            }),
            stream: Stream.value(Uint8List.fromList([1, 2, 3, 4])),
          );
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/retry_success.bin',
        fileName: 'retry_success.bin',
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.completed);
      expect(task.attemptCount, 2);
      expect(calls, 3);
      expect(task.savedPath, isNotNull);
      expect(File(task.savedPath!).readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('重试 3 次仍失败：连续 4 次短暂故障 → 标记 failed 且 attemptCount == 3，包含重试文案', () async {
      var calls = 0;
      final container = createContainer(
        customResumableDownloader: (url, {rangeHeader}) async {
          calls++;
          throw const SocketException('Connection refused');
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/retry_exhaust.bin',
        fileName: 'retry_exhaust.bin',
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.failed);
      expect(task.attemptCount, 3);
      expect(calls, 4); // 初始 1 次 + 重试 3 次 = 4 次
      expect(task.failureMessage, contains('已重试 3 次'));
    });

    test('不可重试错误立即失败：404 错误不进行退避重试，直接标记 failed 且 attemptCount == 0', () async {
      var calls = 0;
      final container = createContainer(
        customResumableDownloader: (url, {rangeHeader}) async {
          calls++;
          return ResumableDownloadResponse(
            statusCode: 404,
            headers: Headers(),
            stream: const Stream.empty(),
          );
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/not_found.bin',
        fileName: 'not_found.bin',
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.failed);
      expect(task.attemptCount, 0);
      expect(calls, 1);
      expect(task.failureMessage, contains('404'));
    });

    test('断点续传：第 1 次中途断开，第 2 次 Range 续传成功 (206) 且最终文件完整，.part 被清理', () async {
      var calls = 0;
      String? receivedRangeHeader;

      final container = createContainer(
        customResumableDownloader: (url, {rangeHeader}) async {
          calls++;
          receivedRangeHeader = rangeHeader;

          if (calls == 1) {
            // 第一次：返回 200，只给前 5 字节，然后流异常中断
            final controller = StreamController<Uint8List>();
            controller.add(Uint8List.fromList([1, 2, 3, 4, 5]));
            controller.addError(const SocketException('Connection interrupted'));
            unawaited(controller.close());

            return ResumableDownloadResponse(
              statusCode: 200,
              headers: Headers.fromMap({
                'accept-ranges': ['bytes'],
                'content-length': ['10'],
              }),
              stream: controller.stream,
            );
          } else {
            // 第二次：重试请求，期望带上 bytes=5-
            expect(rangeHeader, 'bytes=5-');
            return ResumableDownloadResponse(
              statusCode: 206,
              headers: Headers.fromMap({
                'accept-ranges': ['bytes'],
                'content-range': ['bytes 5-9/10'],
                'content-length': ['5'],
              }),
              stream: Stream.value(Uint8List.fromList([6, 7, 8, 9, 10])),
            );
          }
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/resume_test.bin',
        fileName: 'resume_test.bin',
        expectedBytes: 10,
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.completed);
      expect(task.attemptCount, 1);
      expect(task.receivedBytes, 10);
      expect(calls, 2);
      expect(receivedRangeHeader, 'bytes=5-');

      // 验证保存的文件完整性（1..10 共 10 个字节）
      final savedFile = File(task.savedPath!);
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.readAsBytesSync(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      // 验证临时 .part 文件已被删除
      if (task.tempPath != null) {
        expect(File(task.tempPath!).existsSync(), isFalse);
      }
    });

    test('服务端忽略 Range 降级：第 2 次返回 200 OK，清空 .part 从头重新下载', () async {
      var calls = 0;

      final container = createContainer(
        customResumableDownloader: (url, {rangeHeader}) async {
          calls++;
          if (calls == 1) {
            // 第一次：下 4 字节断开
            final controller = StreamController<Uint8List>();
            controller.add(Uint8List.fromList([1, 2, 3, 4]));
            controller.addError(const SocketException('interrupted'));
            unawaited(controller.close());

            return ResumableDownloadResponse(
              statusCode: 200,
              headers: Headers.fromMap({
                'content-length': ['8'],
              }),
              stream: controller.stream,
            );
          } else {
            // 第二次：虽然有 Range，但服务端忽略并返回 200，全量重新给
            return ResumableDownloadResponse(
              statusCode: 200,
              headers: Headers.fromMap({
                'content-length': ['8'],
              }),
              stream: Stream.value(Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80])),
            );
          }
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/downgrade_200.bin',
        fileName: 'downgrade_200.bin',
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.completed);
      expect(task.receivedBytes, 8);
      // 验证最终保存的文件是服务端 200 返回的全量内容，旧 .part 没有被重复追加
      final savedBytes = File(task.savedPath!).readAsBytesSync();
      expect(savedBytes, [10, 20, 30, 40, 50, 60, 70, 80]);
    });

    test('416 Range Not Satisfiable 重新全量下载：清空 .part 后发起无 Range 请求', () async {
      var calls = 0;
      final rangeHeaders = <String?>[];

      final container = createContainer(
        customResumableDownloader: (url, {rangeHeader}) async {
          calls++;
          rangeHeaders.add(rangeHeader);

          if (calls == 1) {
            // 第一次：下 6 字节断开
            final controller = StreamController<Uint8List>();
            controller.add(Uint8List.fromList([1, 2, 3, 4, 5, 6]));
            controller.addError(const SocketException('interrupted'));
            unawaited(controller.close());

            return ResumableDownloadResponse(
              statusCode: 200,
              headers: Headers.fromMap({'content-length': ['6']}),
              stream: controller.stream,
            );
          } else if (calls == 2) {
            // 第二次：客户端带 bytes=6-，服务端返回 416
            return ResumableDownloadResponse(
              statusCode: 416,
              headers: Headers(),
              stream: const Stream.empty(),
            );
          } else {
            // 第三次：收到 416 后控制器内部重新发起 rangeHeader: null
            return ResumableDownloadResponse(
              statusCode: 200,
              headers: Headers.fromMap({'content-length': ['3']}),
              stream: Stream.value(Uint8List.fromList([7, 8, 9])),
            );
          }
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/status_416.bin',
        fileName: 'status_416.bin',
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.completed);
      expect(calls, 3);
      expect(rangeHeaders[0], isNull);
      expect(rangeHeaders[1], 'bytes=6-');
      expect(rangeHeaders[2], isNull); // 416 之后必须为 null
      expect(File(task.savedPath!).readAsBytesSync(), [7, 8, 9]);
    });

    test('Content-Range 总长度不匹配重新全量下载：清空 .part 重新下载', () async {
      var calls = 0;
      final rangeHeaders = <String?>[];

      final container = createContainer(
        customResumableDownloader: (url, {rangeHeader}) async {
          calls++;
          rangeHeaders.add(rangeHeader);

          if (calls == 1) {
            final controller = StreamController<Uint8List>();
            controller.add(Uint8List.fromList([1, 2, 3]));
            controller.addError(const SocketException('interrupted'));
            unawaited(controller.close());

            return ResumableDownloadResponse(
              statusCode: 200,
              headers: Headers.fromMap({'content-length': ['10']}),
              stream: controller.stream,
            );
          } else if (calls == 2) {
            // 第二次：返回 206，但 content-range 表明 total 是 20，与原 10 不符
            return ResumableDownloadResponse(
              statusCode: 206,
              headers: Headers.fromMap({
                'content-range': ['bytes 3-19/20'],
                'content-length': ['17'],
              }),
              stream: const Stream.empty(),
            );
          } else {
            // 第三次：从 0 开始全量
            return ResumableDownloadResponse(
              statusCode: 200,
              headers: Headers.fromMap({'content-length': ['5']}),
              stream: Stream.value(Uint8List.fromList([100, 101, 102, 103, 104])),
            );
          }
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/range_mismatch.bin',
        fileName: 'range_mismatch.bin',
        expectedBytes: 10,
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = container.read(downloadControllerProvider);
      final task = state.taskById(id);

      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.completed);
      expect(calls, 3);
      expect(rangeHeaders[2], isNull);
      expect(File(task.savedPath!).readAsBytesSync(), [100, 101, 102, 103, 104]);
    });

    test('退避等待中取消：打断退避并标记 cancelled，停止继续重试', () async {
      var calls = 0;

      final container = createContainer(
        customBackoff: (_) => const Duration(seconds: 10), // 长退避
        customResumableDownloader: (url, {rangeHeader}) async {
          calls++;
          throw const SocketException('Connection lost');
        },
      );
      addTearDown(container.dispose);

      final controller = container.read(downloadControllerProvider.notifier);
      final id = await controller.enqueue(
        sourceUrl: 'https://example.com/backoff_cancel.bin',
        fileName: 'backoff_cancel.bin',
      );

      // 等待第 1 次失败并进入退避
      await Future<void>.delayed(const Duration(milliseconds: 60));

      var state = container.read(downloadControllerProvider);
      var task = state.taskById(id);
      expect(task, isNotNull);
      expect(task!.isBackingOff, isTrue);
      expect(task.attemptCount, 1);

      // 取消任务
      await controller.cancel(id);

      state = container.read(downloadControllerProvider);
      task = state.taskById(id);
      expect(task!.status, DownloadStatus.cancelled);
      expect(task.isBackingOff, isFalse);

      // 等待确认没有再发起新的调用
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 1);
    });
  });
}
