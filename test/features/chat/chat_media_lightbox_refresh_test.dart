import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/media_cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';

import '../../helpers/fake_download_service.dart';
import '../../helpers/fake_media_cache.dart';

/// 图片灯箱「刷新」按钮的**编排**守卫（#148）。
///
/// 关注三件事：**只对远端图出现**、**点一下真的绕过缓存重取并换掉消费端看的
/// 文件**（内联缩略图与灯箱共用 `mediaFileProvider`）、**失败不破坏旧图**。
///
/// 缓存**行为**（换名落盘 / 失败保留旧条目 / 容量淘汰兼容…）由
/// `test/core/cache/media_cache_refresh_test.dart` 用真实 service 覆盖；这里
/// 注入一个**同步落盘**的替身，因为 widget 测试跑在 FakeAsync 下，真实文件 IO
/// 与 drift 查询不会自己推进（只能靠 `runAsync` 反复放行，时序脆、还会挂）。
const String kBaseUrl = 'http://test.local:30002';
const String kMediaUrl = '$kBaseUrl/api/media?path=pic.png&session_id=s1';
const String kPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
final Uint8List kPngBytes = base64Decode(kPngBase64);
final String kPngDataUri = 'data:image/png;base64,$kPngBase64';

const ValueKey<String> kRefreshKey = ValueKey<String>('media-refresh-button');

/// 同步落盘的假媒体缓存：不碰 drift、不做异步文件 IO，只保留 service 的
/// **接口语义**（`get` 命中、`refresh` 换新路径 + 删旧文件 + 失败不破坏）。
///
/// 「换名」是刻意复刻的：`Image.file` 的 provider key 是 `FileImage(path, scale)`，
/// 路径不变时 widget 不会重新解码新字节 —— 见 `MediaCacheService.refresh` 注释。
class _SyncMediaCache extends MediaCacheService {
  _SyncMediaCache(this.root)
    : super.withDownloader(
        database: AppDatabase.memory(),
        downloader: (_) async => Uint8List(0),
        rootDir: root,
      );

  final Directory root;

  /// `get` / `refresh` 各自的调用次数（分开计：刷新后 provider 会再 `get` 一次）。
  int getCalls = 0;
  int refreshCalls = 0;

  /// 当前对外有效的缓存文件。
  File? current;

  /// 非 null 时 `refresh` 挂起等待（模拟慢网络，用于稳定观察「刷新中」态）。
  Completer<void>? refreshGate;

  /// 非 null 时 `refresh` 抛错（模拟服务端 5xx）。
  Object? refreshError;

  int _version = 0;

  @override
  Future<File> get(String fullUrl, {String? sessionId}) async {
    getCalls++;
    return current ??= _writeVersioned();
  }

  @override
  Future<File> refresh(String fullUrl, {String? sessionId}) {
    refreshCalls++;
    return _refresh();
  }

  Future<File> _refresh() async {
    final gate = refreshGate;
    if (gate != null) await gate.future;
    final error = refreshError;
    if (error != null) throw error;
    final previous = current;
    final next = _writeVersioned();
    current = next;
    if (previous != null && previous.path != next.path) {
      try {
        previous.deleteSync();
      } on FileSystemException {
        // 忽略：与真实 service 同样允许删不掉（留给孤儿清理）。
      }
    }
    return next;
  }

  File _writeVersioned() {
    final name = '${'a' * 64}-${_version++}.png';
    return File('${root.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(kPngBytes);
  }
}

Future<void> _pumpLightbox(
  WidgetTester tester, {
  required MediaCacheService service,
  Uint8List? bytes,
  String? resolvedUrl,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: kBaseUrl)),
        mediaCacheOverride(service),
        ...createDownloadTestOverrides(),
      ],
      child: CupertinoApp(
        home: AttachmentLightbox(
          bytes: bytes,
          resolvedUrl: resolvedUrl,
          name: 'pic.png',
          isImage: true,
        ),
      ),
    ),
  );
  await tester.pump();
}

(_SyncMediaCache, Future<void> Function()) _buildCache() {
  final root = Directory.systemTemp.createTempSync('hermes_refresh_widget_');
  final cache = _SyncMediaCache(root);
  return (
    cache,
    () async {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // ignore
      }
    },
  );
}

void main() {
  group('AttachmentLightbox 图片刷新按钮', () {
    testWidgets('远端图片：出现刷新按钮，且与下载按钮并排共存', (tester) async {
      final (cache, dispose) = _buildCache();
      addTearDown(dispose);

      await _pumpLightbox(tester, service: cache, resolvedUrl: kMediaUrl);

      expect(find.byKey(kRefreshKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('attachment-download-button')),
        findsOneWidget,
      );
    });

    testWidgets('内存字节（Image.memory）：没有远端副本，不显示刷新按钮', (tester) async {
      final (cache, dispose) = _buildCache();
      addTearDown(dispose);

      await _pumpLightbox(tester, service: cache, bytes: kPngBytes);

      expect(find.byKey(kRefreshKey), findsNothing);
    });

    testWidgets('data: URI：不显示刷新按钮', (tester) async {
      final (cache, dispose) = _buildCache();
      addTearDown(dispose);

      await _pumpLightbox(tester, service: cache, resolvedUrl: kPngDataUri);

      expect(find.byKey(kRefreshKey), findsNothing);
    });

    testWidgets('本地文件路径：不显示刷新按钮', (tester) async {
      final (cache, dispose) = _buildCache();
      addTearDown(dispose);

      await _pumpLightbox(
        tester,
        service: cache,
        resolvedUrl: '/tmp/not-a-remote/pic.png',
      );

      expect(find.byKey(kRefreshKey), findsNothing);
    });

    testWidgets('点刷新：绕过缓存重下 → 换成新路径文件、旧文件删除，且刷新中不可连点', (tester) async {
      final (cache, dispose) = _buildCache();
      addTearDown(dispose);

      await _pumpLightbox(tester, service: cache, resolvedUrl: kMediaUrl);
      final first = cache.current;
      expect(first, isNotNull, reason: '首次渲染应已走一次缓存取回');
      expect(cache.getCalls, 1);

      final gate = Completer<void>();
      cache.refreshGate = gate;
      // 兜底放行：用例若在放行前失败，挂起的 refresh 会把测试 isolate 一直吊住
      // （实测残留 flutter_tester 进程并锁住 build 产物）。
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await tester.tap(find.byKey(kRefreshKey));
      await tester.pump();

      // 刷新中：按钮位换成活动指示器 —— 该处不再可点（防连点的可见证据；
      // 组件里另有一层 `if (_refreshing) return` 兜底，此处不做「点不存在的
      // 按钮」这种假动作）。
      expect(cache.refreshCalls, 1);
      expect(find.byKey(kRefreshKey), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(cache.refreshCalls, 1, reason: '刷新未完成期间不得再发第二次请求');

      gate.complete();
      await tester.pump();
      await tester.pump();

      // 关键：消费端拿到的文件路径变了 —— 内联缩略图与灯箱共用同一个
      // `mediaFileProvider`，路径变 ⇒ FileImage 的 key 必变 ⇒ 两边一起重解码。
      expect(cache.refreshCalls, 1);
      expect(cache.current!.path, isNot(first!.path));
      expect(cache.current!.existsSync(), isTrue);
      expect(first.existsSync(), isFalse, reason: '旧版本文件应被删掉，不堆积');
      expect(find.byKey(kRefreshKey), findsOneWidget);
    });

    testWidgets('刷新失败：提示「刷新失败」，旧图与缓存条目原样保留', (tester) async {
      final (cache, dispose) = _buildCache();
      addTearDown(dispose);

      await _pumpLightbox(tester, service: cache, resolvedUrl: kMediaUrl);
      final first = cache.current!;

      cache.refreshError = StateError('500 from test');
      await tester.tap(find.byKey(kRefreshKey));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.refreshCalls, 1);
      expect(find.text('刷新失败'), findsOneWidget);

      // 旧图没被弄丢：文件还在、消费端仍指向它。
      expect(first.existsSync(), isTrue);
      expect(cache.current!.path, first.path);

      // 关掉提示后按钮回到可用态。
      await tester.tap(find.byKey(const ValueKey('media-refresh-error-ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(kRefreshKey), findsOneWidget);
    });
  });
}
