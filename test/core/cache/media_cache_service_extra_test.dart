import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/media_cache_service.dart';
// 测试需要替换 path_provider 的平台实现（透传依赖，非直接依赖）。
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 补测：默认构造（走 ApiClient.downloadData）、未注入 rootDir 时的
/// path_provider 落点、以及三处「删除失败吞掉 FileSystemException」分支。
class _Rig {
  _Rig(this.db, this.root, this.service);

  final AppDatabase db;
  final Directory root;
  final MediaCacheService service;

  Future<void> dispose() async {
    await db.close();
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // ignore
    }
  }
}

_Rig _build({
  Future<Uint8List> Function(Uri)? downloader,
  int maxBytes = kDefaultMaxMediaCacheBytes,
  Duration ttl = kDefaultMediaTtl,
}) {
  final db = AppDatabase.memory();
  final root = Directory.systemTemp.createTempSync('hermes_media_extra_');
  final service = MediaCacheService.withDownloader(
    database: db,
    downloader: downloader ?? (_) async => Uint8List.fromList(<int>[1, 2, 3]),
    rootDir: root,
    maxBytes: maxBytes,
    ttl: ttl,
  );
  return _Rig(db, root, service);
}

/// 固定的假 dio 适配器：不发真实网络请求，直接回固定字节。
class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes, {this.statusCode = 200});

  final List<int> bytes;
  final int statusCode;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

/// 把文件设为只读（Windows）——之后 `File.delete()` 会抛
/// `PathAccessException`（`FileSystemException` 子类），
/// 用于打通「删除失败被吞掉」的容错分支。
Future<bool> _makeReadOnly(File file) async {
  if (!Platform.isWindows) return false;
  if (!await file.exists()) {
    // attrib 对不存在的路径也可能返回 0，这里显式守卫，避免「假只读」。
    throw StateError('_makeReadOnly: 文件不存在，无法加只读：${file.path}');
  }
  final result = await Process.run('attrib', <String>['+r', file.path]);
  if (result.exitCode != 0) {
    throw StateError('attrib +r 失败：${result.stderr}');
  }
  return true;
}

String _keyOf(File file) => file.uri.pathSegments.last.split('.').first;

void main() {
  group('MediaCacheService 默认构造（ApiClient 链路）', () {
    test('默认构造：maxBytes/ttl 取常量，下载走 ApiClient.downloadData 真实取回字节', () async {
      final db = AppDatabase.memory();
      final root = Directory.systemTemp.createTempSync('hermes_media_default_');
      addTearDown(() async {
        await db.close();
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      final adapter = _BytesAdapter(<int>[10, 20, 30, 40]);
      final dio = Dio()..httpClientAdapter = adapter;
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:30002',
        dio: dio,
        publicMediaDio: dio,
      );

      final service = MediaCacheService(
        database: db,
        client: client,
        rootDir: root,
      );

      expect(service.maxBytes, kDefaultMaxMediaCacheBytes);
      expect(service.ttl, kDefaultMediaTtl);

      const url = 'http://127.0.0.1:30002/media/photo.png';
      final file = await service.get(url);

      expect(await file.readAsBytes(), <int>[10, 20, 30, 40]);
      expect(file.uri.pathSegments.last, endsWith('.png'));
      expect(adapter.requests, hasLength(1), reason: '只发一次请求');
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, url);

      final row = await (db.select(
        db.cachedMedia,
      )..where((t) => t.url.equals(url))).getSingle();
      expect(row.byteSize, 4);
      expect(row.filePath, file.uri.pathSegments.last);
    });

    test('默认构造支持自定义 maxBytes/ttl（覆盖常量）', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:30002');

      final service = MediaCacheService(
        database: db,
        client: client,
        maxBytes: 123,
        ttl: const Duration(minutes: 5),
      );

      expect(service.maxBytes, 123);
      expect(service.ttl, const Duration(minutes: 5));
    });

    test('非 2xx（404）：抛 HttpException，不落盘也不写索引', () async {
      final db = AppDatabase.memory();
      final root = Directory.systemTemp.createTempSync('hermes_media_404_');
      addTearDown(() async {
        await db.close();
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      final adapter = _BytesAdapter(<int>[1, 2], statusCode: 404);
      final dio = Dio()..httpClientAdapter = adapter;
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:30002',
        dio: dio,
        publicMediaDio: dio,
      );
      final service = MediaCacheService(
        database: db,
        client: client,
        rootDir: root,
      );

      await expectLater(
        service.get('http://127.0.0.1:30002/media/missing.png'),
        throwsA(
          isA<HttpException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );

      expect(adapter.requests, hasLength(1));
      expect(root.listSync().whereType<File>(), isEmpty);
      expect(await db.select(db.cachedMedia).get(), isEmpty);
    });
  });

  group('未注入 rootDir：落点由 path_provider 决定', () {
    test('默认落点 = <应用支持目录>/hermes_media 且被自动创建', () async {
      final supportDir = Directory.systemTemp.createTempSync(
        'hermes_support_',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(supportDir.path);
      addTearDown(() {
        PathProviderPlatform.instance = previous;
      });

      final db = AppDatabase.memory();
      addTearDown(() async {
        await db.close();
        try {
          await supportDir.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      final service = MediaCacheService(
        database: db,
        client: ApiClient(baseUrl: 'http://127.0.0.1:30002'),
      );

      await service.initialize();

      final expected = Directory(
        '${supportDir.path}${Platform.pathSeparator}$kMediaCacheDirName',
      );
      expect(expected.existsSync(), isTrue);
      expect(supportDir.listSync().whereType<Directory>(), hasLength(1));

      // 重复 initialize 幂等（不重复建目录/不重复清理）。
      await service.initialize();
      expect(expected.existsSync(), isTrue);
    });
  });

  group('索引与文件不一致的恢复', () {
    test('索引在而文件丢失 → 删索引重下（不返回不存在的路径）', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          return Uint8List.fromList(<int>[1, 1, 1]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/lost-file.png';

      final first = await rig.service.get(url);
      expect(downloads, 1);
      final key = _keyOf(first);

      // 模拟外部清理：文件没了，索引还在。
      await first.delete();
      expect(await first.exists(), isFalse);
      expect(
        await (rig.db.select(
          rig.db.cachedMedia,
        )..where((t) => t.cacheKey.equals(key))).get(),
        hasLength(1),
        reason: '索引仍在（孤儿索引）',
      );

      final second = await rig.service.get(url);

      expect(downloads, 2, reason: '文件丢失应重下，而不是直接返回坏路径');
      expect(await second.exists(), isTrue);
      expect(second.path, first.path);
      // 索引被重建为一条，而不是残留两条。
      final rows = await rig.db.select(rig.db.cachedMedia).get();
      expect(rows, hasLength(1));
      expect(rows.single.filePath, second.uri.pathSegments.last);
    });
  });

  group('删除失败（FileSystemException）一律吞掉不中断主流程', () {
    test('孤儿清理：文件删不掉时不抛出，其余孤儿照删', () async {
      final rig = _build();
      addTearDown(rig.dispose);

      final lockedOrphan = File(
        '${rig.root.path}${Platform.pathSeparator}locked_orphan.png',
      );
      await lockedOrphan.writeAsBytes(<int>[1, 2, 3]);
      final otherOrphan = File(
        '${rig.root.path}${Platform.pathSeparator}other_orphan.png',
      );
      await otherOrphan.writeAsBytes(<int>[4, 5, 6]);
      final windowsLocked = await _makeReadOnly(lockedOrphan);

      await rig.service.cleanupOrphans();

      expect(await otherOrphan.exists(), isFalse, reason: '其余孤儿照常删除');
      if (windowsLocked) {
        expect(
          await lockedOrphan.exists(),
          isTrue,
          reason: '只读文件删除失败被吞掉（cleanupOrphans 的 FileSystemException 分支）',
        );
      } else {
        expect(await lockedOrphan.exists(), isFalse);
      }
    });

    test('TTL 过期：旧文件删不掉时索引照清，不会永远命中过期项', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          return Uint8List.fromList(<int>[7, 7]);
        },
        ttl: const Duration(milliseconds: 30),
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/ttl-locked.png';

      final first = await rig.service.get(url);
      expect(downloads, 1);
      final key = _keyOf(first);
      final windowsLocked = await _makeReadOnly(first);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      if (windowsLocked) {
        // 只读文件既删不掉也写不进 → 删除失败被吞后继续重下，最终写盘再抛。
        await expectLater(
          rig.service.get(url),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          await first.exists(),
          isTrue,
          reason: '只读文件删除失败被吞（_removeEntry 的 FileSystemException 分支）',
        );
        expect(
          await (rig.db.select(
            rig.db.cachedMedia,
          )..where((t) => t.cacheKey.equals(key))).get(),
          isEmpty,
          reason: '删不掉文件也必须清索引，否则永远命中过期项',
        );
      } else {
        final second = await rig.service.get(url);
        expect(downloads, 2);
        expect(await second.exists(), isTrue);
      }
    });

    test('LRU 淘汰：最旧文件删不掉时不中断淘汰循环，其余照淘汰', () async {
      // 体积刻意不等：A(500) + B(1000) = 1500B ≤ 上限 2000B → 前两次写入不淘汰；
      // 写入 C(1500B) 后共 3000B → 需淘汰 A、B **两个**（A 删不掉也不能中断循环）。
      const urlA = 'https://example.com/lru_a.png';
      const urlB = 'https://example.com/lru_b.png';
      const urlC = 'https://example.com/lru_c.png';
      const sizes = <String, int>{urlA: 500, urlB: 1000, urlC: 1500};

      final rig = _build(
        downloader: (uri) async => Uint8List(sizes[uri.toString()]!),
        maxBytes: 2000,
      );
      addTearDown(rig.dispose);

      final oldest = await rig.service.get(urlA);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final middle = await rig.service.get(urlB);
      expect(await oldest.exists(), isTrue, reason: '前两次写入未触发淘汰');
      expect(await middle.exists(), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      final windowsLocked = await _makeReadOnly(oldest);
      final newest = await rig.service.get(urlC);

      // 最新的必然保留。
      expect(await newest.exists(), isTrue);

      if (windowsLocked) {
        expect(
          await oldest.exists(),
          isTrue,
          reason: '只读文件淘汰删除失败被吞（_evictIfNeeded 的 FileSystemException 分支）',
        );
        expect(
          await middle.exists(),
          isFalse,
          reason: '删除失败不得中断淘汰循环 → 次旧的仍被淘汰',
        );
      } else {
        expect(await oldest.exists(), isFalse);
        expect(await middle.exists(), isFalse);
      }

      // 无论文件删没删成，索引都必须与淘汰决策同步。
      final remainingKeys = (await rig.db.select(rig.db.cachedMedia).get())
          .map((r) => r.cacheKey)
          .toSet();
      expect(remainingKeys, isNot(contains(_keyOf(oldest))));
      expect(remainingKeys, isNot(contains(_keyOf(middle))));
      expect(remainingKeys, contains(_keyOf(newest)));
    });
  });
}
