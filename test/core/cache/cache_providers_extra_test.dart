import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/cache/media_cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
// 测试需要替换 path_provider 的平台实现（透传依赖，非直接依赖）。
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 不联网的 ApiClient 替身：`downloadData` 直接回固定字节。
class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'http://stub.local:30002');

  final List<Uri> downloaded = <Uri>[];

  @override
  Future<Uint8List> downloadData(
    Uri url, {
    bool mapsUnauthorized = false,
    bool allowAutoReauth = true,
    void Function(int receivedBytes, int totalBytes)? onReceiveProgress,
  }) async {
    downloaded.add(url);
    return Uint8List.fromList(<int>[4, 5, 6, 7]);
  }
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

/// 补测：`offlineCacheEnabledProvider`、`mediaCacheServiceProvider` 的装配
/// 返回值、以及 `CachedSessionData` 构造。
void main() {
  group('offlineCacheEnabledProvider', () {
    test('默认 true（离线缓存默认开启）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(offlineCacheEnabledProvider), isTrue);
    });

    test('可被 override 关闭', () {
      final container = ProviderContainer(
        overrides: <Override>[
          offlineCacheEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(offlineCacheEnabledProvider), isFalse);
    });
  });

  group('cacheServiceProvider', () {
    test('用 appDatabaseProvider 装配 CacheService，且与媒体缓存同库', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(cacheServiceProvider);

      expect(service, isA<CacheService>());
      expect(
        identical(service, container.read(cacheServiceProvider)),
        isTrue,
        reason: 'Provider 单例缓存',
      );
      // 同一个 AppDatabase 实例（避免同库二次打开）。
      final AppDatabase db = container.read(appDatabaseProvider);
      expect(identical(db, container.read(appDatabaseProvider)), isTrue);
      expect(identical(db, container.read(persistentAppDatabaseProvider)), isTrue);
    });
  });

  group('mediaCacheServiceProvider', () {
    test('用 appDatabaseProvider + apiClientProvider 装配出可用的 MediaCacheService', () async {
      final supportDir = Directory.systemTemp.createTempSync(
        'hermes_provider_support_',
      );
      final previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(supportDir.path);

      final client = _StubApiClient();
      final container = ProviderContainer(
        overrides: <Override>[apiClientProvider.overrideWithValue(client)],
      );

      addTearDown(container.dispose);
      addTearDown(() {
        PathProviderPlatform.instance = previousPathProvider;
      });
      addTearDown(() async {
        try {
          await supportDir.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      final service = container.read(mediaCacheServiceProvider);

      expect(service, isA<MediaCacheService>());
      expect(service.maxBytes, kDefaultMaxMediaCacheBytes);
      expect(service.ttl, kDefaultMediaTtl);
      expect(
        identical(service, container.read(mediaCacheServiceProvider)),
        isTrue,
        reason: 'Provider 单例缓存，不重复构造',
      );

      // 下载器确实接的是注入的 ApiClient（stub 返回字节，不触网）。
      final file = await service.get('http://stub.local:30002/media/pic.png');

      expect(await file.readAsBytes(), <int>[4, 5, 6, 7]);
      expect(client.downloaded, hasLength(1));
      expect(client.downloaded.single.toString(), 'http://stub.local:30002/media/pic.png');
      expect(file.path, contains(kMediaCacheDirName));
    });

    test('与 appDatabaseProvider 同库（索引写进同一 AppDatabase）', () async {
      final client = _StubApiClient();
      final container = ProviderContainer(
        overrides: <Override>[apiClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      // 直接读 db 不触发 path_provider（mediaCacheServiceProvider 也未解析根目录）。
      final db = container.read(appDatabaseProvider);
      expect(
        identical(db, container.read(persistentAppDatabaseProvider)),
        isTrue,
      );
      expect(container.read(mediaCacheServiceProvider), isA<MediaCacheService>());
    });

    test('不同 container → 各自独立实例（不泄漏单例）', () {
      final containerA = ProviderContainer(
        overrides: <Override>[
          apiClientProvider.overrideWithValue(_StubApiClient()),
        ],
      );
      final containerB = ProviderContainer(
        overrides: <Override>[
          apiClientProvider.overrideWithValue(_StubApiClient()),
        ],
      );
      addTearDown(containerA.dispose);
      addTearDown(containerB.dispose);

      expect(
        identical(
          containerA.read(mediaCacheServiceProvider),
          containerB.read(mediaCacheServiceProvider),
        ),
        isFalse,
      );
    });
  });

  group('CachedSessionData', () {
    test('空列表：sessions 为空而非 null', () {
      const data = CachedSessionData(<SessionSummary>[]);

      expect(data.sessions, isEmpty);
      expect(data.sessions, isA<List<SessionSummary>>());
    });

    test('包裹会话列表：内容原样透出（不复制、不重排）', () {
      const list = <SessionSummary>[
        SessionSummary(sessionId: 's1', title: '第一个会话'),
        SessionSummary(sessionId: 's2', title: '第二个会话'),
      ];
      const data = CachedSessionData(list);

      expect(data.sessions, hasLength(2));
      expect(
        identical(data.sessions, list),
        isTrue,
        reason: '只做包裹，不做拷贝',
      );
      expect(data.sessions.first.sessionId, 's1');
      expect(data.sessions.first.title, '第一个会话');
      expect(data.sessions.last.sessionId, 's2');
      expect(data.sessions.last.title, '第二个会话');
    });
  });
}
