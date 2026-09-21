import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/media_cache_service.dart';

/// [MediaCacheService.refresh]（图片预览「刷新」的底座）的守卫集。
///
/// 这里钉住两条**容易在后续重构里被「优化掉」**的硬约束：
/// 1. 刷新必须**换文件名**——`Image.file` 的 provider key 是
///    `FileImage(path, scale)`，不含 mtime/size；同名写回时 `Image` 不会重新
///    解码，用户点刷新会「毫无反应」。
/// 2. `_get` 命中必须**按索引 filePath** 取文件——若退回按固定名回算，刷新后
///    每次访问都会判「未命中」而重下，缓存形同失效。
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
  required Future<Uint8List> Function(Uri) downloader,
  int maxBytes = kDefaultMaxMediaCacheBytes,
}) {
  final db = AppDatabase.memory();
  final root = Directory.systemTemp.createTempSync('hermes_media_refresh_');
  final service = MediaCacheService.withDownloader(
    database: db,
    downloader: downloader,
    rootDir: root,
    maxBytes: maxBytes,
  );
  return _Rig(db, root, service);
}

List<File> _filesIn(Directory dir) =>
    dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

Future<CachedMediaData?> _row(_Rig rig, String url) => (rig.db.select(
  rig.db.cachedMedia,
)..where((t) => t.url.equals(url))).getSingleOrNull();

void main() {
  group('MediaCacheService.refresh 强制刷新媒体缓存', () {
    test('换名落盘：返回新内容、旧文件即刻删除、索引改指新名', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          return Uint8List.fromList([downloads]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/pic.png';

      final first = await rig.service.get(url);
      expect(await first.readAsBytes(), [1]);

      final refreshed = await rig.service.refresh(url);
      expect(downloads, 2);
      expect(await refreshed.readAsBytes(), [2]);
      // 关键 1：路径必须变（⇒ FileImage key 变 ⇒ Image 重新解码）。
      expect(refreshed.path, isNot(first.path));
      expect(refreshed.uri.pathSegments.last, contains('-'));
      expect(refreshed.uri.pathSegments.last, endsWith('.png'));
      // 旧文件已删，磁盘只留一份（不堆积版本文件）。
      expect(await first.exists(), isFalse);
      expect(_filesIn(rig.root), hasLength(1));
      // 索引跟着换名。
      final row = await _row(rig, url);
      expect(row!.filePath, refreshed.uri.pathSegments.last);
      expect(row.byteSize, 1);
    });

    test('刷新后 get 命中新条目：不再重复下载（索引 filePath 是唯一真相）', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          return Uint8List.fromList([downloads]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/again.png';

      await rig.service.get(url);
      final refreshed = await rig.service.refresh(url);
      expect(downloads, 2);

      final after = await rig.service.get(url);
      // RED 红线：若 _get 退回「按 sha256 固定名回算」，旧名文件已被删 ⇒ 判未命中
      // ⇒ downloads 变 3、且返回的 File 指向不存在的旧路径。
      expect(downloads, 2, reason: '刷新后必须命中新路径缓存，不能再下一遍');
      expect(after.path, refreshed.path);
      expect(await after.readAsBytes(), [2]);
    });

    test('下载失败：旧缓存（文件 + 索引）原封不动，get 仍返回旧内容', () async {
      var downloads = 0;
      var fail = false;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          if (fail) throw StateError('500 for test');
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/keep.png';

      final first = await rig.service.get(url);
      fail = true;

      await expectLater(rig.service.refresh(url), throwsA(isA<StateError>()));

      // 先下载后落盘 ⇒ 旧图还在，别让「点一下刷新」把唯一可看的图弄没。
      expect(await first.exists(), isTrue);
      expect(await first.readAsBytes(), [1, 2, 3]);
      expect((await _row(rig, url))!.filePath, first.uri.pathSegments.last);

      fail = false;
      final after = await rig.service.get(url);
      expect(downloads, 2, reason: '刷新失败不应破坏缓存命中');
      expect(after.path, first.path);
    });

    test('连续两次刷新得到不同路径（同一 URL 的相邻刷新不会撞名）', () async {
      final rig = _build(downloader: (_) async => Uint8List.fromList([7]));
      addTearDown(rig.dispose);
      const url = 'https://example.com/twice.png';

      final a = await rig.service.refresh(url);
      final b = await rig.service.refresh(url);

      expect(b.path, isNot(a.path));
      expect(await a.exists(), isFalse);
      expect(await b.exists(), isTrue);
    });

    test('刷新期间并发 get 只下载一次（共享 in-flight）', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Uint8List.fromList([4, 4]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/inflight.png';

      final results = await Future.wait([
        rig.service.get(url),
        rig.service.refresh(url),
      ]);

      expect(downloads, 1);
      expect(results[0].path, results[1].path);
    });

    test('版本后缀文件被容量淘汰时索引一并清掉（_keyFromFileName 兼容换名）', () async {
      // 1024 B/文件、上限 1500 B ⇒ 写完第二个文件必触发一次淘汰。
      final rig = _build(
        downloader: (_) async => Uint8List(1024),
        maxBytes: 1500,
      );
      addTearDown(rig.dispose);
      const a = 'https://example.com/lru_a.png';
      const b = 'https://example.com/lru_b.png';

      await rig.service.get(a);
      final refreshedA = await rig.service.refresh(a);
      expect(refreshedA.uri.pathSegments.last, contains('-'));
      // 拉开 lastAccessedAt，避免同毫秒导致淘汰顺序不确定。
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await rig.service.get(b);

      // 版本名（`<sha256>-<ver>.png`）也能被反推回 cacheKey，否则索引会留下
      // 永不回收的孤儿行（文件已删、行还在）。
      expect(await refreshedA.exists(), isFalse);
      expect(await _row(rig, a), isNull);
    });

    test('刷新后仍守 TTL：过期条目不因为「刷过一次」而豁免', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          return Uint8List.fromList([9]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/ttl_after_refresh.png';

      await rig.service.get(url);
      await rig.service.refresh(url);
      expect(downloads, 2);

      // lastAccessedAt 被刷新写成了「现在」⇒ 未过期 ⇒ 命中。
      await rig.service.get(url);
      expect(downloads, 2);
    });
  });
}
