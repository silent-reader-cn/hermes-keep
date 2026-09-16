import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import 'app_database.dart';

/// 媒体缓存目录相对文件名（相对平台私有应用数据目录）。
const String kMediaCacheDirName = 'hermes_media';

/// 默认媒体缓存容量上限（200MB，超限按 LRU 淘汰）。
const int kDefaultMaxMediaCacheBytes = 200 * 1024 * 1024;

/// 默认媒体缓存 TTL（30 天，读命中时超期视为失效删除重下）。
const Duration kDefaultMediaTtl = Duration(days: 30);

/// 媒体本地缓存服务。
///
/// 二进制内容落文件系统（`getApplicationSupportDirectory()/hermes_media/`），
/// drift `cached_media` 表只存索引元数据（沿用现有 `CachedMessages`
/// 「纯文本 payload、富媒体不进库」的既定方向，见 docs/cache_audit_report.md
/// §3.2/§3.4）。
///
/// 下载统一走 [ApiClient.downloadData] —— 即 dio 链路：同域自动携带会话 cookie
/// + 用户自定义头 + 401 自动重登；跨域走裸客户端（防自定义头泄密）。因此
/// `Image.network` 手工拼头的方案（`ChatMediaHeaders`）不再需要，详见 §3.6。
///
/// 缓存 key = `sha256(完整 URL)`（URL 已含 `path` + `session_id`，天然区分
/// 「同一文件、不同会话授权」的取回）。失效策略：200MB LRU + 30 天 TTL +
/// 启动孤儿清理（§3.3/§3.5）。
class MediaCacheService {
  MediaCacheService({
    required AppDatabase database,
    required ApiClient client,
    Directory? rootDir,
    this.maxBytes = kDefaultMaxMediaCacheBytes,
    this.ttl = kDefaultMediaTtl,
  }) : _database = database, // ignore: prefer_initializing_formals
       _rootDirOverride = rootDir {
    _download = (url) => client.downloadData(url);
  }

  /// 测试构造：注入任意下载函数（返回 bytes 或抛错），避免真实网络与
  /// ApiClient/连接初始化；生产路径一律用默认构造（ApiClient.downloadData）。
  @visibleForTesting
  MediaCacheService.withDownloader({
    required AppDatabase database,
    required Future<Uint8List> Function(Uri) downloader,
    Directory? rootDir,
    this.maxBytes = kDefaultMaxMediaCacheBytes,
    this.ttl = kDefaultMediaTtl,
  }) : _database = database, // ignore: prefer_initializing_formals
       _rootDirOverride = rootDir {
    _download = downloader;
  }

  final AppDatabase _database;
  final Directory? _rootDirOverride;
  late final Future<Uint8List> Function(Uri) _download;

  /// 容量上限（字节）。
  final int maxBytes;

  /// 时间 TTL。
  final Duration ttl;

  Directory? _root;
  bool _initialized = false;

  /// 进行中的 per-URL 下载 Future，合并列表滚动时同一 URL 的并发重复请求。
  final Map<String, Future<File>> _inflight = <String, Future<File>>{};

  /// 取回（必要时下载）媒体文件。
  ///
  /// 命中缓存则更新 `lastAccessedAt` 并返回 [File]；未命中则经
  /// [ApiClient.downloadData] 下载落盘（2xx 才写缓存）后返回 [File]；
  /// 非 2xx（401/404 等）不缓存、抛异常（由调用方渲染占位符）。
  /// [sessionId] 仅作为业务维度写入索引（会话联动清理备用），不影响 key。
  Future<File> get(String fullUrl, {String? sessionId}) {
    final existing = _inflight[fullUrl];
    if (existing != null) return existing;
    final completer = Completer<File>();
    _inflight[fullUrl] = completer.future;
    // 异步执行实际取回；成功/失败都经 completer 派发，并清掉 in-flight 合并项。
    // 刻意不用 `.whenComplete` 链（避免在部分 runner 上结果未被转发）。
    unawaited(_runGet(fullUrl, sessionId, completer));
    return completer.future;
  }

  Future<void> _runGet(
    String fullUrl,
    String? sessionId,
    Completer<File> completer,
  ) async {
    try {
      final file = await _get(fullUrl, sessionId);
      completer.complete(file);
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      unawaited(_inflight.remove(fullUrl)!);
    }
  }

  /// 启动诊断/清理：删除「有文件无索引」「有索引无文件」的孤儿，并触发一次
  /// 容量达标。首次 [get] 前自动执行一次，也可由宿主显式调用。
  @visibleForTesting
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final root = await _ensureRoot();
    await cleanupOrphans();
    await _evictIfNeeded(root);
  }

  /// 孤儿清理：磁盘有文件但索引无记录 → 删文件；索引有记录但文件丢失 → 删索引。
  Future<void> cleanupOrphans() async {
    final root = await _ensureRoot();
    if (!await root.exists()) return;
    final rows = await _allRows();
    final indexPath = <String>{for (final r in rows) r.filePath};

    await for (final entity in root.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        if (!indexPath.contains(name)) {
          try {
            await entity.delete();
          } on FileSystemException {
            // 忽略并发/权限导致的删除失败（低频清理，不阻塞主流程）。
          }
        }
      }
    }

    for (final row in rows) {
      final abs = await _absoluteFile(row.filePath);
      if (!await abs.exists()) {
        await _deleteIndexRow(row.cacheKey);
      }
    }
  }

  Future<File> _get(String fullUrl, String? sessionId) async {
    await initialize();
    final uri = Uri.parse(fullUrl);
    final key = _sha256(fullUrl);
    final root = await _ensureRoot();
    final fileName = '$key.${_extForUrl(fullUrl)}';
    final file = await _absoluteFile(fileName);

    // 1) 索引命中：文件仍存在 → 校验/更新访问时间后直接返回。
    final row = await _fetchRow(key);
    if (row != null) {
      if (await file.exists()) {
        final now = _now();
        if (now - row.lastAccessedAt > ttl.inMilliseconds) {
          // 超 TTL → 过期删除重下。
          await _removeEntry(key, file);
        } else {
          await _touch(key, now);
          return file;
        }
      } else {
        // 索引在但文件丢失 → 删索引（孤儿），走重下。
        await _deleteIndexRow(key);
      }
    } else if (await file.exists()) {
      // 文件在但索引缺失（例如索引被外部清理）：补索引即可，避免无谓重下。
      await _insertRow(key, fullUrl, file, sessionId);
      return file;
    }

    // 2) 未命中 → 下载（非 2xx 抛错，调用方走占位符；不写缓存）。
    final bytes = await _download(uri);
    await file.writeAsBytes(bytes, flush: true);
    await _insertRow(key, fullUrl, file, sessionId);

    // 3) 写入后做一次容量达标（低频）。
    await _evictIfNeeded(root);
    return file;
  }

  Future<Directory> _ensureRoot() async {
    final dir = _root ?? _rootDirOverride ?? await _defaultRoot();
    await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}$kMediaCacheDirName',
    );
  }

  Future<File> _absoluteFile(String filePath) async {
    final root = await _ensureRoot();
    return File('${root.path}${Platform.pathSeparator}$filePath');
  }

  Future<void> _insertRow(
    String key,
    String url,
    File file,
    String? sessionId, {
    String? mimeType,
  }) async {
    final now = _now();
    final stat = await file.stat();
    await _database
        .into(_database.cachedMedia)
        .insertOnConflictUpdate(
          CachedMediaCompanion.insert(
            cacheKey: key,
            url: url,
            mimeType: Value(mimeType),
            filePath: file.uri.pathSegments.last,
            byteSize: stat.size,
            cachedAt: now,
            lastAccessedAt: now,
            sessionId: Value(sessionId),
          ),
        );
  }

  Future<void> _touch(String key, int now) async {
    await (_database.update(_database.cachedMedia)
          ..where((t) => t.cacheKey.equals(key)))
        .write(CachedMediaCompanion(lastAccessedAt: Value(now)));
  }

  Future<CachedMediaData?> _fetchRow(String key) {
    return (_database.select(
      _database.cachedMedia,
    )..where((t) => t.cacheKey.equals(key))).getSingleOrNull();
  }

  Future<List<CachedMediaData>> _allRows() =>
      _database.select(_database.cachedMedia).get();

  Future<void> _deleteIndexRow(String key) async {
    await (_database.delete(
      _database.cachedMedia,
    )..where((t) => t.cacheKey.equals(key))).go();
  }

  /// 删除缓存文件并清索引。
  ///
  /// ⚠️ 删除失败时【保留索引】：否则会留下「文件还在盘上但索引没了」的孤儿，
  /// 而 [_get] 的「文件在但索引缺失 → 补索引」分支会把它重新登记为有效条目，
  /// 导致过期缓存永远不会被淘汰。保留索引后，下次访问仍走 TTL 检查并重试删除。
  Future<void> _removeEntry(String key, File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 删除失败（文件被占用等）：索引保持不动，交由下次 TTL 检查重试。
      return;
    }
    await _deleteIndexRow(key);
  }

  /// 统计目录总字节，超 [maxBytes] 时按 `lastAccessedAt` 升序删文件+删索引，
  /// 直至达标（缺失索引的文件视为最旧，优先淘汰）。
  Future<void> _evictIfNeeded(Directory root) async {
    if (!await root.exists()) return;
    var total = 0;
    final files = <File>[];
    await for (final entity in root.list()) {
      if (entity is File) {
        total += await entity.length();
        files.add(entity);
      }
    }
    if (total <= maxBytes) return;

    final lastAccess = <String, int>{
      for (final r in await _allRows()) r.filePath: r.lastAccessedAt,
    };
    files.sort((a, b) {
      final an = lastAccess[a.uri.pathSegments.last] ?? -1;
      final bn = lastAccess[b.uri.pathSegments.last] ?? -1;
      return an.compareTo(bn);
    });

    for (final file in files) {
      if (total <= maxBytes) break;
      final name = file.uri.pathSegments.last;
      final size = await file.length();
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // ⚠️ 删除失败时既不扣减 total、也不删索引：
        //  - 扣减会让循环误判“已腾出空间”而提前 break（实际没释放）；
        //  - 删索引会留下「文件在盘但索引没了」的孤儿，被 _get 的补索引分支
        //    重新登记为有效，导致该文件永远不被淘汰。
        continue;
      }
      total -= size;
      await _deleteIndexRow(_keyFromFileName(name));
    }
  }

  /// 由文件内名反推 cacheKey（文件名 = `<sha256hex>.<ext>`，key 为点前段）。
  static String _keyFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot == -1 ? fileName : fileName.substring(0, dot);
  }

  /// 由 URL path 尾部推断扩展名（无则 `.bin`）。dio `downloadData` 只返回
  /// bytes，不暴露 Content-Type，按 design §3.6 从 path 后缀推断已够用。
  static String _extForUrl(String url) {
    final pathOnly = url.split('?').first.split('#').first;
    final dot = pathOnly.lastIndexOf('.');
    if (dot != -1) {
      final ext = pathOnly.substring(dot + 1);
      if (ext.isNotEmpty &&
          ext.length <= 8 &&
          RegExp(r'^[A-Za-z0-9]+$').hasMatch(ext)) {
        return ext.toLowerCase();
      }
    }
    return 'bin';
  }

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
