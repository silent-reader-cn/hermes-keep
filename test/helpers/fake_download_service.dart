import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/features/downloads/download_repository.dart';
import 'package:hermes_ui/features/downloads/download_save_service.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';

class FakeTurnNotificationService implements TurnNotificationService {
  final List<(String id, String fileName, int size)> downloadCompletedCalls =
      [];
  final List<(String id, String fileName, bool cancelled)> downloadFailedCalls =
      [];

  @override
  Future<void> notifyDownloadCompleted(
    String downloadId,
    String fileName,
    int byteSize,
  ) async {
    downloadCompletedCalls.add((downloadId, fileName, byteSize));
  }

  @override
  Future<void> notifyDownloadFailed(
    String downloadId,
    String fileName, {
    required bool cancelled,
  }) async {
    downloadFailedCalls.add((downloadId, fileName, cancelled));
  }
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
  Future<void> clearAll() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<String?> getLaunchSessionId() async => null;
}

List<Override> createDownloadTestOverrides({
  AppDatabase? db,
  Directory? tempDir,
  DownloadBytesDownloader? downloader,
  DownloadResumableDownloader? resumableDownloader,
  DownloadBackoffCalculator? backoff,
  DownloadTempDirectoryResolver? tempDirectoryResolver,
  TurnNotificationService? notificationService,
}) {
  final database = db ?? AppDatabase.memory();
  final targetDir =
      tempDir ?? Directory.systemTemp.createTempSync('hermes_dl_test_');
  final partsDir = Directory('${targetDir.path}/parts')..createSync(recursive: true);

  final effectiveDownloader =
      downloader ?? ((uri, {onProgress}) async => Uint8List.fromList([1, 2, 3, 4]));

  final effectiveResumable =
      resumableDownloader ??
      ((uri, {rangeHeader}) async {
        final bytes = await effectiveDownloader(uri);
        return ResumableDownloadResponse(
          statusCode: 200,
          headers: Headers.fromMap({
            'accept-ranges': ['bytes'],
            'content-length': ['${bytes.length}'],
          }),
          stream: Stream.value(bytes),
        );
      });

  return [
    appDatabaseProvider.overrideWithValue(database),
    downloadRepositoryProvider.overrideWithValue(
      DownloadRepository(database, tempDirectoryProvider: () => partsDir),
    ),
    downloadSaveServiceProvider.overrideWithValue(
      DownloadSaveService(destinationDirOverride: targetDir),
    ),
    turnNotificationServiceProvider.overrideWithValue(
      notificationService ?? FakeTurnNotificationService(),
    ),
    downloadDownloaderProvider.overrideWithValue(effectiveDownloader),
    downloadResumableDownloaderProvider.overrideWithValue(effectiveResumable),
    downloadBackoffProvider.overrideWithValue(
      backoff ?? ((_) => Duration.zero),
    ),
    downloadTempDirectoryProvider.overrideWithValue(
      tempDirectoryResolver ?? (() async => partsDir),
    ),
  ];
}
