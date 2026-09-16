import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';
import 'package:hermes_ui/features/workspace_manager/file_preview_body.dart';

import '../../helpers/fake_workspace_api.dart';

/// 补齐 [FilePreviewBody] 的覆盖率：类型判定边界、三个纯数据 source 类、
/// `_load()` 各分类分支、Office 四种正文体、错误/兜底视图、PDF 临时文件生命周期。
///
/// 与 `file_preview_page_test.dart` 共用同一套 `FakeWorkspaceApi` +
/// `ProviderScope` override 手法；本文件直接 pump `FilePreviewBody`，
/// 以避开页面外壳（导航条/下载弹窗）的干扰。
const String kBaseUrl = 'http://test.local:30002';

/// 1x1 透明 PNG（widget 测试用可解码位图）。
final Uint8List kPngBytes = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

WorkspaceEntry wsEntry(String name, {String? path, int? size}) =>
    WorkspaceEntry(name: name, path: path ?? name, size: size);

/// 入参不是 String / WorkspaceEntry 时走 `toString()` 判定。
class _Stringish {
  const _Stringish(this.value);

  final String value;

  @override
  String toString() => value;
}

/// 可注入的 [ApiClient]：可改 `baseUrl`（含空串 / 抛错两种异常配置），
/// 并拦截 `urlBytes` 记录请求 URL（避免测试触发真实网络）。
class _StubApiClient extends ApiClient {
  _StubApiClient({
    this.baseUrlOverride,
    this.throwOnBaseUrl = false,
    this.bytes = const [7, 7, 7],
  }) : super(baseUrl: kBaseUrl);

  final String? baseUrlOverride;
  final bool throwOnBaseUrl;
  final List<int> bytes;

  final List<String> requestedUrls = [];

  @override
  String get baseUrl {
    if (throwOnBaseUrl) {
      throw StateError('baseUrl unavailable');
    }
    return baseUrlOverride ?? super.baseUrl;
  }

  @override
  Future<Uint8List> urlBytes(
    String url, {
    bool mapsUnauthorized = false,
    bool allowAutoReauth = true,
    void Function(int receivedBytes, int totalBytes)? onReceiveProgress,
  }) async {
    requestedUrls.add(url);
    return Uint8List.fromList(bytes);
  }
}

/// 现场拼一个最小 xlsx（每张表可指定是否有数据行），
/// 用于覆盖「单工作表 / 空工作表」两个分支，避免新增 fixture 文件。
Uint8List buildXlsxBytes(List<({String name, bool withRow})> sheets) {
  final archive = Archive();
  void addText(String path, String xml) =>
      archive.addFile(ArchiveFile.bytes(path, utf8.encode(xml)));

  final workbook = StringBuffer(
    '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets>',
  );
  final rels = StringBuffer(
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
  );
  for (var i = 0; i < sheets.length; i++) {
    final id = 'rId${i + 1}';
    workbook.write('<sheet name="${sheets[i].name}" r:id="$id"/>');
    rels.write(
      '<Relationship Id="$id" Target="worksheets/sheet${i + 1}.xml"/>',
    );
    final body = sheets[i].withRow
        ? '<row r="1"><c r="A1" t="inlineStr"><is><t>only</t></is></c></row>'
        : '';
    addText(
      'xl/worksheets/sheet${i + 1}.xml',
      '<worksheet><sheetData>$body</sheetData></worksheet>',
    );
  }
  workbook.write('</sheets></workbook>');
  rels.write('</Relationships>');
  addText('xl/workbook.xml', workbook.toString());
  addText('xl/_rels/workbook.xml.rels', rels.toString());

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// 本用例注入的预览临时目录里的 `hermes_preview_*` 文件集合（PDF/音视频落盘用）。
///
/// 走 `FilePreviewBody.previewTempDir`（setUp 指向本用例专属子目录），而**不是**全局
/// %TEMP%：`flutter test` 是多测试文件并发跑的，共享目录会被同目录其它用例落下的
/// 文件混入，让「本次新增了几个」的 difference 断言假失败（实测单跑恒绿、三目录一起跑必红）。
Set<String> previewTempPaths() {
  final dir = FilePreviewBody.previewTempDir;
  if (!dir.existsSync()) return <String>{};
  return dir
      .listSync()
      .whereType<File>()
      .map((e) => e.path)
      .where(
        (p) =>
            p.split(Platform.pathSeparator).last.startsWith('hermes_preview_'),
      )
      .toSet();
}

/// pump 一个 `FilePreviewBody`，provider 全部注入。
Future<void> pumpBody(
  WidgetTester tester, {
  required Widget body,
  FakeWorkspaceApi? api,
  ApiClient? client,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          client ?? ApiClient(baseUrl: kBaseUrl),
        ),
        workspaceApiFactoryProvider.overrideWithValue(
          (_) => api ?? FakeWorkspaceApi(),
        ),
      ],
      child: CupertinoApp(home: body),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// 取一个真实 [WidgetRef]（供直接调用 source 的 loadText/loadBytes）。
Future<WidgetRef> captureRef(
  WidgetTester tester, {
  ApiClient? client,
  FakeWorkspaceApi? api,
}) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          client ?? ApiClient(baseUrl: kBaseUrl),
        ),
        workspaceApiFactoryProvider.overrideWithValue(
          (_) => api ?? FakeWorkspaceApi(),
        ),
      ],
      child: CupertinoApp(
        home: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

/// 让真实文件 IO（临时文件写入/删除）在 widget 测试里推进完成。
Future<void> settleRealIo(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// `_ResolvedFilePreviewSource.loadBytes` 会碰真实文件系统（`File.exists()`），
/// 而 flutter_test 默认的假异步区不会推进 dart:io 的 Future——必须走 runAsync。
Future<Uint8List> loadResolvedBytes(
  WidgetTester tester,
  WidgetRef ref,
  FilePreviewSource source,
) async {
  final bytes = await tester.runAsync(() => source.loadBytes(ref));
  return bytes ?? Uint8List(0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDirs = <Directory>[];

  setUp(() {
    // pdfrx 会经 path_provider 取临时目录；flutter_test 不加载平台插件，
    // 必须打桩，否则 MissingPluginException 直接判测试失败。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
    // 预览临时目录改用**本用例专用子目录**：flutter test 并发跑多文件，共享 %TEMP%
    // 会让「本次落了几个文件」的断言被同目录其它用例落下的文件污染。
    // 注：此处不用 newTempDir()——Dart 局部函数不支持在声明前引用。
    final previewDir = Directory.systemTemp.createTempSync('hermes_fpb_preview_');
    tempDirs.add(previewDir);
    FilePreviewBody.previewTempDir = previewDir;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    // 还原注入，避免污染其它测试文件。
    FilePreviewBody.previewTempDir = Directory.systemTemp;
    for (final dir in tempDirs) {
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    tempDirs.clear();
  });

  Directory newTempDir() {
    final dir = Directory.systemTemp.createTempSync('hermes_fpb_extra_');
    tempDirs.add(dir);
    return dir;
  }

  // ---------------------------------------------------------------------------
  // 1. 类型判定（枚举闭集 + 未知回退）
  // ---------------------------------------------------------------------------
  group('workspaceFileKindOf 边界与枚举闭集', () {
    test('非 String / WorkspaceEntry 的入参回退到 toString 判定', () {
      expect(workspaceFileKindOf(42), WorkspaceFileKind.other);
      expect(workspaceFileKindOf(Object()), WorkspaceFileKind.other);
      expect(
        workspaceFileKindOf(const _Stringish('archive.tar.gz')),
        WorkspaceFileKind.archive,
      );
      expect(
        workspaceFileKindOf(const _Stringish('PHOTO.JPEG')),
        WorkspaceFileKind.image,
      );
      expect(
        workspaceFileKindOf(const _Stringish('notes.markdown')),
        WorkspaceFileKind.text,
      );
    });

    test('WorkspaceEntry 的 name 缺失才回退 path，空 name 不回退', () {
      expect(
        workspaceFileKindOf(const WorkspaceEntry(path: 'dir/a.md')),
        WorkspaceFileKind.text,
      );
      expect(workspaceFileKindOf(const WorkspaceEntry()), WorkspaceFileKind.other);
      expect(
        workspaceFileKindOf(const WorkspaceEntry(name: '', path: 'x.mp3')),
        WorkspaceFileKind.other,
        reason: 'name 非 null 时不做 path 回退',
      );
    });

    test('扩展名白名单全量命中（图片/视频/音频/PDF/Office/归档）', () {
      for (final ext in ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico']) {
        expect(workspaceFileKindOf('f$ext'), WorkspaceFileKind.image, reason: ext);
      }
      for (final ext in ['.mp4', '.mov', '.webm', '.mkv', '.avi', '.m4v']) {
        expect(workspaceFileKindOf('f$ext'), WorkspaceFileKind.video, reason: ext);
      }
      for (final ext in ['.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac', '.opus']) {
        expect(workspaceFileKindOf('f$ext'), WorkspaceFileKind.audio, reason: ext);
      }
      for (final ext in ['.docx', '.xlsx', '.pptx', '.doc', '.xls', '.ppt']) {
        expect(workspaceFileKindOf('f$ext'), WorkspaceFileKind.office, reason: ext);
      }
      for (final ext in [
        '.zip',
        '.tar',
        '.gz',
        '.iso',
        '.exe',
        '.msi',
        '.apk',
        '.aab',
        '.ipa',
        '.sqlite3',
        '.woff2',
        '.otf',
      ]) {
        expect(workspaceFileKindOf('f$ext'), WorkspaceFileKind.archive, reason: ext);
      }
      expect(workspaceFileKindOf('f.pdf'), WorkspaceFileKind.pdf);
      expect(workspaceFileKindOf('f.PDF'), WorkspaceFileKind.pdf);
    });

    test('预取扩展名优先于文本白名单（.svg/.csv 归 text，.doc 归 office）', () {
      expect(workspaceFileKindOf('icon.svg'), WorkspaceFileKind.text);
      expect(workspaceFileKindOf('rows.csv'), WorkspaceFileKind.text);
      expect(workspaceFileKindOf('legacy.doc'), WorkspaceFileKind.office);
      expect(workspaceFileKindOf('legacy.xls'), WorkspaceFileKind.office);
      expect(workspaceFileKindOf('legacy.ppt'), WorkspaceFileKind.office);
    });

    test('WorkspaceFileKind 全取值与名称稳定（未知值只能落在 other）', () {
      expect(
        WorkspaceFileKind.values.map((k) => k.name).toList(),
        <String>[
          'text',
          'image',
          'video',
          'audio',
          'pdf',
          'office',
          'archive',
          'other',
        ],
      );
    });

    test('workspaceFileIsPreviewable：六类可预览，归档/未知/空串不可预览', () {
      for (final name in ['a.md', 'a.png', 'a.mp4', 'a.mp3', 'a.pdf', 'a.docx']) {
        expect(workspaceFileIsPreviewable(name), isTrue, reason: name);
      }
      for (final name in ['a.zip', 'a.exe', 'noext', '', 'bin.dat']) {
        expect(workspaceFileIsPreviewable(name), isFalse, reason: name);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 2. 三个 source 数据类
  // ---------------------------------------------------------------------------
  group('FilePreviewSource.bytes（内存字节源）', () {
    testWidgets('loadText 派生 content / path / size / lines', (tester) async {
      final ref = await captureRef(tester);
      final source = FilePreviewSource.bytes(
        Uint8List.fromList(utf8.encode('a\nb\nc')),
      );

      final text = await source.loadText(ref, fileName: 'note.txt');
      expect(text.content, 'a\nb\nc');
      expect(text.path, 'note.txt');
      expect(text.size, 5);
      expect(text.lines, 3);

      expect(await source.loadBytes(ref), hasLength(5));
    });

    testWidgets('loadText：空字节 → lines 0 且 content 为空', (tester) async {
      final ref = await captureRef(tester);
      final source = FilePreviewSource.bytes(Uint8List(0));

      final text = await source.loadText(ref, fileName: 'empty.txt');
      expect(text.content, '');
      expect(text.size, 0);
      expect(text.lines, 0);
      expect(await source.loadBytes(ref), isEmpty);
    });

    testWidgets('loadText：单行无换行 → lines 1', (tester) async {
      final ref = await captureRef(tester);
      final source = FilePreviewSource.bytes(Uint8List.fromList([0x68, 0x69]));
      final text = await source.loadText(ref, fileName: 'one.txt');
      expect(text.content, 'hi');
      expect(text.lines, 1);
    });
  });

  group('FilePreviewSource.workspaceFile（工作区拉取源）', () {
    testWidgets('loadText 经 workspaceApiFactory 拉文本', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['d/a.txt'] = const FileResponse(
        content: 'hello',
        size: 5,
        lines: 1,
      );
      final ref = await captureRef(tester, api: api);
      final source = FilePreviewSource.workspaceFile('s9', 'd/a.txt');

      final text = await source.loadText(ref, fileName: 'd/a.txt');
      expect(text.content, 'hello');
      expect(api.fetchFileCalls, ['s9|d/a.txt']);
    });

    testWidgets('loadBytes 经 workspaceApiFactory 下载原始字节', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;
      final ref = await captureRef(tester, api: api);
      final source = FilePreviewSource.workspaceFile('s9', 'd/p.png');

      expect(await loadResolvedBytes(tester, ref, source), same(kPngBytes));
      expect(api.downloadCalls, ['s9|d/p.png']);
    });
  });

  group('FilePreviewSource.resolved（URL / 内存字节解析）', () {
    testWidgets('bytes 非空时优先返回，未发生任何 URL 解析', (tester) async {
      final client = _StubApiClient();
      final ref = await captureRef(tester, client: client);
      final source = FilePreviewSource.resolved(
        'http://example.com/x.png',
        bytes: kPngBytes,
      );

      expect(await source.loadBytes(ref), same(kPngBytes));
      expect(client.requestedUrls, isEmpty);
    });

    testWidgets('url 为 null → 返回空字节', (tester) async {
      final ref = await captureRef(tester);
      expect(
        await loadResolvedBytes(tester, ref, FilePreviewSource.resolved(null)),
        isEmpty,
      );
    });

    testWidgets('url 为空串 → 返回空字节', (tester) async {
      final ref = await captureRef(tester);
      expect(
        await loadResolvedBytes(tester, ref, FilePreviewSource.resolved('')),
        isEmpty,
      );
    });

    testWidgets('data: URI → base64 解码为字节', (tester) async {
      final ref = await captureRef(tester);
      final source = FilePreviewSource.resolved(
        'data:image/png;base64,${base64Encode(utf8.encode('hi'))}',
      );
      expect(utf8.decode(await loadResolvedBytes(tester, ref, source)), 'hi');
    });

    testWidgets('data: URI 缺逗号 → 解码失败抛出（不静默吞）', (tester) async {
      final ref = await captureRef(tester);
      final source = FilePreviewSource.resolved('data:image/png');
      await expectLater(source.loadBytes(ref), throwsA(isA<FormatException>()));
    });

    testWidgets('本地绝对路径直读真实文件', (tester) async {
      final dir = newTempDir();
      final file = File('${dir.path}/local.txt')
        ..writeAsBytesSync(utf8.encode('local-bytes'));
      final ref = await captureRef(tester);
      final source = FilePreviewSource.resolved(file.path);

      expect(
        utf8.decode(await loadResolvedBytes(tester, ref, source)),
        'local-bytes',
      );
    });

    testWidgets('file:// URI 解包后直读真实文件', (tester) async {
      final dir = newTempDir();
      final file = File('${dir.path}/uri.txt')
        ..writeAsBytesSync(utf8.encode('uri-bytes'));
      final ref = await captureRef(tester);
      final source = FilePreviewSource.resolved(Uri.file(file.path).toString());

      expect(
        utf8.decode(await loadResolvedBytes(tester, ref, source)),
        'uri-bytes',
      );
    });

    testWidgets('file:// 非法 URI → 回退 substring 后按相对路径继续', (tester) async {
      final client = _StubApiClient(bytes: [1, 2]);
      final ref = await captureRef(tester, client: client);
      final source = FilePreviewSource.resolved('file://%C3%28/x');

      expect(await loadResolvedBytes(tester, ref, source), hasLength(2));
      expect(client.requestedUrls, hasLength(1));
    });

    testWidgets('相对 api 路径 → 拼接 baseUrl 后走 urlBytes', (tester) async {
      final client = _StubApiClient(bytes: [9, 9]);
      final ref = await captureRef(tester, client: client);
      final source = FilePreviewSource.resolved(
        'images/a.png',
        sessionId: 's7',
      );

      expect(await loadResolvedBytes(tester, ref, source), hasLength(2));
      expect(client.requestedUrls, hasLength(1));
      expect(client.requestedUrls.single, startsWith('$kBaseUrl/api/media?path='));
      expect(client.requestedUrls.single, contains('session_id=s7'));
      expect(client.requestedUrls.single, contains(Uri.encodeComponent('images/a.png')));
    });

    testWidgets('相对路径 + baseUrl 为空 → 无法拼 URL，返回空字节', (tester) async {
      final client = _StubApiClient(baseUrlOverride: '');
      final ref = await captureRef(tester, client: client);
      final source = FilePreviewSource.resolved('images/a.png');

      expect(await loadResolvedBytes(tester, ref, source), isEmpty);
      expect(client.requestedUrls, isEmpty);
    });

    testWidgets('读取 baseUrl 抛错 → 吞掉异常后退化为空字节', (tester) async {
      final client = _StubApiClient(throwOnBaseUrl: true);
      final ref = await captureRef(tester, client: client);
      final source = FilePreviewSource.resolved('images/a.png');

      expect(await loadResolvedBytes(tester, ref, source), isEmpty);
      expect(client.requestedUrls, isEmpty);
    });

    testWidgets('loadText 由字节派生（UTF-8 容错解码 + 行数）', (tester) async {
      final ref = await captureRef(tester);
      final source = FilePreviewSource.resolved(
        'data:application/octet-stream;base64,${base64Encode([0x61, 0x0A, 0xFF])}',
      );

      final text = await source.loadText(ref, fileName: 'weird.bin');
      expect(text.path, 'weird.bin');
      expect(text.size, 3);
      expect(text.lines, 2, reason: '0xFF 走 allowMalformed 替换字符，不抛异常');
    });
  });

  // ---------------------------------------------------------------------------
  // 3. 文本 / 错误 / 兜底视图
  // ---------------------------------------------------------------------------
  group('FilePreviewBody · 文本与错误分支', () {
    testWidgets('文本：内容 + 大小/行数/截断元信息', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['a.log'] = const FileResponse(
        content: 'x\ny',
        size: 36,
        lines: 2,
        truncated: true,
      );
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'a.log',
          source: FilePreviewSource.workspaceFile('s1', 'a.log'),
        ),
      );

      expect(find.byKey(const ValueKey('preview-text')), findsOneWidget);
      expect(find.textContaining('x\ny'), findsOneWidget);
      expect(find.textContaining('36 B'), findsOneWidget);
      expect(find.textContaining('2 行'), findsOneWidget);
      expect(find.textContaining('已截断'), findsOneWidget);
    });

    testWidgets('文本：.markdown 也走 MarkdownBody 富渲染', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['doc.markdown'] = const FileResponse(
        content: '# H',
        size: 3,
        lines: 1,
      );
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'doc.markdown',
          source: FilePreviewSource.workspaceFile('s1', 'doc.markdown'),
        ),
      );

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-text')), findsNothing);
    });

    testWidgets('文本：空内容 → 空文件占位', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['blank.txt'] = const FileResponse(content: '');
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'blank.txt',
          source: FilePreviewSource.workspaceFile('s1', 'blank.txt'),
        ),
      );

      expect(find.text('（空文件）'), findsOneWidget);
    });

    testWidgets('文本：服务端 error 字段 → 失败兜底 + 自定义下载按钮', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['bad.txt'] = const FileResponse(
        content: 'ignored',
        error: 'server refused',
      );
      var taps = 0;
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'bad.txt',
          source: FilePreviewSource.workspaceFile('s1', 'bad.txt'),
          downloadButton: CupertinoButton(
            onPressed: () => taps++,
            child: const Text('自定义下载'),
          ),
        ),
      );

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('server refused'), findsOneWidget);
      expect(find.text('自定义下载'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('preview-download-fallback')),
        findsNothing,
        reason: '自定义按钮优先于默认下载按钮',
      );
      await tester.tap(find.text('自定义下载'));
      await tester.pump();
      expect(taps, 1);

      // 重试闭包（服务端 error 兜底那条路径）也要真跑一次。
      await tester.tap(find.byKey(const ValueKey('preview-retry')));
      await tester.pump();
      await tester.pump();
      expect(api.fetchFileCalls, ['s1|bad.txt', 's1|bad.txt']);
    });

    testWidgets('文本：ApiException → 直接展示 error.message', (tester) async {
      final api = FakeWorkspaceApi()
        ..fetchFileError = HttpException(
          500,
          null,
          message: '接口炸了',
        );
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'a.txt',
          source: FilePreviewSource.workspaceFile('s1', 'a.txt'),
        ),
      );

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('接口炸了'), findsOneWidget);
    });

    testWidgets('文本：非 ApiException → 退回 error.toString()', (tester) async {
      final api = FakeWorkspaceApi()
        ..fetchFileError = Exception('raw failure');
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'a.txt',
          source: FilePreviewSource.workspaceFile('s1', 'a.txt'),
        ),
      );

      expect(find.textContaining('raw failure'), findsOneWidget);
    });

    testWidgets('文本：重试按钮重新加载并恢复内容', (tester) async {
      final api = FakeWorkspaceApi()
        ..fetchFileError = HttpException(404, null, message: 'gone');
      final body = FilePreviewBody(
        fileName: 'retry.txt',
        source: FilePreviewSource.workspaceFile('s1', 'retry.txt'),
      );
      await pumpBody(tester, api: api, body: body);
      expect(find.text('gone'), findsOneWidget);

      api.fetchFileError = null;
      api.fileContents['retry.txt'] = const FileResponse(
        content: 'recovered',
        size: 9,
        lines: 1,
      );
      await tester.tap(find.byKey(const ValueKey('preview-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('recovered'), findsOneWidget);
      expect(find.text('gone'), findsNothing);
      expect(api.fetchFileCalls, ['s1|retry.txt', 's1|retry.txt']);
    });

    testWidgets('未知类型：无法预览 + 自定义下载按钮（默认按钮不渲染）', (tester) async {
      await pumpBody(
        tester,
        body: FilePreviewBody(
          fileName: 'noext',
          source: FilePreviewSource.resolved(
            'data:application/octet-stream;base64,AAAA',
          ),
          downloadButton: CupertinoButton(
            onPressed: () {},
            child: const Text('自定义下载'),
          ),
        ),
      );

      expect(find.text('无法预览该文件'), findsOneWidget);
      expect(find.text('暂不支持预览该文件类型，请改用下载。'), findsOneWidget);
      expect(find.text('自定义下载'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('preview-download-fallback')),
        findsNothing,
      );
    });

    testWidgets('未知类型：无自定义按钮时回落到默认下载按钮并可点击', (tester) async {
      var taps = 0;
      await pumpBody(
        tester,
        body: FilePreviewBody(
          fileName: 'bundle.tar',
          source: FilePreviewSource.resolved(null),
          onDownload: () => taps++,
        ),
      );

      final button = find.byKey(const ValueKey('preview-download-fallback'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(taps, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. 图片 / 音视频
  // ---------------------------------------------------------------------------
  group('FilePreviewBody · 图片与音视频分支', () {
    testWidgets('图片：字节非空渲染 Image.memory', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'pic.png',
          source: FilePreviewSource.workspaceFile('s1', 'pic.png'),
        ),
      );

      final image = tester.widget<Image>(
        find.byKey(const ValueKey('preview-image'), skipOffstage: false),
      );
      expect((image.image as MemoryImage).bytes, same(kPngBytes));
      expect(api.downloadCalls, ['s1|pic.png']);
    });

    testWidgets('图片：字节为空 → 退回无法预览', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = Uint8List(0);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'empty.png',
          source: FilePreviewSource.workspaceFile('s1', 'empty.png'),
        ),
      );

      expect(find.text('无法预览该文件'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-image')), findsNothing);
    });

    testWidgets('视频：字节为空 → 不建播放器，退回无法预览', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = Uint8List(0);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'empty.mp4',
          source: FilePreviewSource.workspaceFile('s1', 'empty.mp4'),
        ),
      );

      expect(find.text('无法预览该文件'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('preview-video-controls')),
        findsNothing,
      );
    });

    testWidgets('音频：字节为空 → 不建播放器，退回无法预览', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = Uint8List(0);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'empty.mp3',
          source: FilePreviewSource.workspaceFile('s1', 'empty.mp3'),
        ),
      );

      expect(find.text('无法预览该文件'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-audio-controls')), findsNothing);
    });

    testWidgets('视频：字节非空 → 要么进播放器，要么 media_kit 缺席时走失败兜底', (
      tester,
    ) async {
      // media_kit 需要 libmpv 动态库 + `MediaKit.ensureInitialized()`；
      // flutter_test 环境两者都没有（见 TASK_REPORT「不可达分支」），
      // 因此这里只锁定「不退化到 unsupported」这一契约。
      final before = previewTempPaths();
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'movie.mp4',
          sizeBytes: 2048,
          source: FilePreviewSource.workspaceFile('s1', 'movie.mp4'),
        ),
      );
      // 落盘临时文件是真实 IO，需要 runAsync 才能推进。
      // 轮次给足：全量并发跑时 CPU 争抢会让默认 4 轮（80ms）不够，_load() 未收尾
      // 会让下面「有控件 or 有兜底」双断言假失败（单跑恒绿）。
      await settleRealIo(tester, rounds: 12);

      expect(find.text('无法预览该文件'), findsNothing);
      final hasControls = find
          .byKey(const ValueKey('preview-video-controls'))
          .evaluate()
          .isNotEmpty;
      final hasFallback = find.text('加载失败').evaluate().isNotEmpty;
      expect(hasControls || hasFallback, isTrue);

      // 收尾：清理本用例产生的临时文件（Player() 构造失败时源文件不会自清理，
      // 见 TASK_REPORT「实现观察」#1）。
      for (final path in previewTempPaths().difference(before)) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 5. PDF
  // ---------------------------------------------------------------------------
  group('FilePreviewBody · PDF 分支', () {
    testWidgets('PDF：字节非空 → 落盘临时文件并渲染 preview-pdf，销毁时清理', (
      tester,
    ) async {
      final before = previewTempPaths();
      final api = FakeWorkspaceApi()
        ..downloadBytes = Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'doc.pdf',
          source: FilePreviewSource.workspaceFile('s1', 'doc.pdf'),
        ),
      );
      await settleRealIo(tester);

      expect(find.byKey(const ValueKey('preview-pdf')), findsOneWidget);
      expect(api.downloadCalls, ['s1|doc.pdf']);
      final created = previewTempPaths().difference(before);
      expect(created, hasLength(1), reason: 'PDF 字节必须先落盘再交给 pdfrx');
      expect(created.single, endsWith('.pdf'));

      // 组件销毁 → dispose 内异步删除临时文件。
      await tester.pumpWidget(const SizedBox.shrink());
      await settleRealIo(tester, rounds: 3);
      expect(previewTempPaths().difference(before), isEmpty);
    });

    testWidgets('PDF：字节为空 → 失败兜底（Empty PDF file）', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = Uint8List(0);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'empty.pdf',
          source: FilePreviewSource.workspaceFile('s1', 'empty.pdf'),
        ),
      );

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('Empty PDF file'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-pdf')), findsNothing);
      expect(find.byKey(const ValueKey('preview-retry')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Office 四种正文体
  // ---------------------------------------------------------------------------
  group('FilePreviewBody · Office 正文体', () {
    testWidgets('docx：标题/段落/表格全部渲染', (tester) async {
      final api = FakeWorkspaceApi()
        ..downloadBytes = File('test/fixtures/office/sample.docx')
            .readAsBytesSync();
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'sample.docx',
          sizeBytes: 3 * 1024 * 1024,
          source: FilePreviewSource.workspaceFile('s1', 'sample.docx'),
        ),
      );

      expect(find.byKey(const ValueKey('preview-office-docx')), findsOneWidget);
      expect(find.textContaining('项目周报 Report 周三'), findsOneWidget);
      expect(find.text('工作项'), findsOneWidget);
      expect(find.text('柚子'), findsOneWidget);
      expect(find.text('3.0 MB'), findsOneWidget);
      expect(find.text('无法预览该文件'), findsNothing);
    });

    testWidgets('xlsx：多工作表分段控件 + 切换工作表重绘', (tester) async {
      final api = FakeWorkspaceApi()
        ..downloadBytes = File('test/fixtures/office/sample.xlsx')
            .readAsBytesSync();
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'sample.xlsx',
          sizeBytes: 2048,
          source: FilePreviewSource.workspaceFile('s1', 'sample.xlsx'),
        ),
      );

      expect(find.byKey(const ValueKey('preview-office-xlsx')), findsOneWidget);
      expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('产品'), findsWidgets);
      expect(find.text('销量'), findsWidgets);

      await tester.tap(find.text('备注'));
      await tester.pumpAndSettle();

      expect(find.text('备注页内容'), findsOneWidget);
      expect(find.text('产品'), findsNothing);
    });

    testWidgets('xlsx：单工作表 → 不渲染分段控件，直接出表格', (tester) async {
      final api = FakeWorkspaceApi()
        ..downloadBytes = buildXlsxBytes([(name: 'only', withRow: true)]);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'single.xlsx',
          source: FilePreviewSource.workspaceFile('s1', 'single.xlsx'),
        ),
      );

      expect(find.byKey(const ValueKey('preview-office-xlsx')), findsOneWidget);
      expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsNothing);
      expect(find.text('only'), findsOneWidget);
    });

    testWidgets('xlsx：切到空工作表 → 表格消失（rows.isEmpty 分支）', (tester) async {
      final api = FakeWorkspaceApi()
        ..downloadBytes = buildXlsxBytes([
          (name: '有数据', withRow: true),
          (name: '空表', withRow: false),
        ]);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'two.xlsx',
          source: FilePreviewSource.workspaceFile('s1', 'two.xlsx'),
        ),
      );

      expect(find.byType(Table), findsOneWidget);
      await tester.tap(find.text('空表'));
      await tester.pumpAndSettle();

      expect(find.byType(Table), findsNothing);
      expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    });

    testWidgets('Office：字节损坏 → OfficeParseException 无法解析分支', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = Uint8List.fromList([1, 2, 3]);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'broken.xlsx',
          source: FilePreviewSource.workspaceFile('s1', 'broken.xlsx'),
        ),
      );

      expect(find.text('无法解析该办公文档'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-office-xlsx')), findsNothing);
    });

    testWidgets('pptx：多页渲染 + 分页分隔 + 页码标签', (tester) async {
      final api = FakeWorkspaceApi()
        ..downloadBytes = File('test/fixtures/office/sample.pptx')
            .readAsBytesSync();
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'sample.pptx',
          sizeBytes: 5 * 1024 * 1024,
          source: FilePreviewSource.workspaceFile('s1', 'sample.pptx'),
        ),
      );

      expect(find.byKey(const ValueKey('preview-office-pptx')), findsOneWidget);
      expect(find.text('第 1 页'), findsOneWidget);
      expect(find.text('第 2 页'), findsOneWidget);
      expect(find.text('产品介绍'), findsOneWidget);
      expect(find.text('第一页 要点一'), findsOneWidget);
      expect(find.text('第二页标题'), findsOneWidget);
      expect(find.text('5.0 MB'), findsOneWidget);
    });

    testWidgets('pptx：暗色主题下卡片走 dark 配色分支', (tester) async {
      final api = FakeWorkspaceApi()
        ..downloadBytes = File('test/fixtures/office/sample.pptx')
            .readAsBytesSync();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient(baseUrl: kBaseUrl)),
            workspaceApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp(
            theme: const CupertinoThemeData(brightness: Brightness.dark),
            home: FilePreviewBody(
              fileName: 'sample.pptx',
              source: FilePreviewSource.workspaceFile('s1', 'sample.pptx'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('preview-office-pptx')), findsOneWidget);
      expect(find.text('第 2 页'), findsOneWidget);
      expect(find.text('第二页标题'), findsOneWidget);
    });

    testWidgets('legacy .doc：文本提取预览 + 旧格式提示', (tester) async {
      final api = FakeWorkspaceApi()
        ..downloadBytes = Uint8List.fromList(
          utf8.encode('Microsoft Word 97-2003 Document Header goes here'),
        );
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'old.doc',
          sizeBytes: 999,
          source: FilePreviewSource.workspaceFile('s1', 'old.doc'),
        ),
      );

      expect(find.byKey(const ValueKey('preview-office-legacy')), findsOneWidget);
      expect(find.text('旧版 Office 格式仅提取文本预览'), findsOneWidget);
      expect(
        find.textContaining('Microsoft Word 97-2003 Document Header'),
        findsOneWidget,
      );
      expect(find.text('999 B'), findsOneWidget);
    });

    testWidgets('Office：字节为空 → OfficeParseException 不支持分支', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = Uint8List(0);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'empty.docx',
          source: FilePreviewSource.workspaceFile('s1', 'empty.docx'),
        ),
      );

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('无法解析该办公文档'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-office-docx')), findsNothing);
    });

    testWidgets('Office：超过 50MB 上限 → 「文件过大」分支', (tester) async {
      final api = FakeWorkspaceApi()
        ..downloadBytes = Uint8List(50 * 1024 * 1024 + 1);
      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(
          fileName: 'huge.docx',
          source: FilePreviewSource.workspaceFile('s1', 'huge.docx'),
        ),
      );

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('文件过大，无法预览，请改用下载'), findsOneWidget);
    });

    testWidgets('sizeBytes 各档位格式化（B/KB/MB/GB）与缺省不渲染', (tester) async {
      final bytes = File('test/fixtures/office/sample.docx').readAsBytesSync();
      final api = FakeWorkspaceApi()..downloadBytes = bytes;
      Widget build(int? size) => FilePreviewBody(
        fileName: 'sample.docx',
        sizeBytes: size,
        source: FilePreviewSource.workspaceFile('s1', 'sample.docx'),
      );

      await pumpBody(tester, api: api, body: build(1024));
      expect(find.text('1024 B'), findsNothing, reason: '_buildMediaMetaLine 只做分档');
      expect(find.text('1.0 KB'), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient(baseUrl: kBaseUrl)),
            workspaceApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp(home: build(2 * 1024 * 1024 * 1024)),
        ),
      );
      await tester.pump();
      expect(find.text('2.0 GB'), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient(baseUrl: kBaseUrl)),
            workspaceApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp(home: build(null)),
        ),
      );
      await tester.pump();
      expect(
        find.textContaining(RegExp(r'^\d+(\.\d+)? (B|KB|MB|GB)$')),
        findsNothing,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 7. 生命周期
  // ---------------------------------------------------------------------------
  group('FilePreviewBody · 生命周期', () {
    testWidgets('fileName 变化触发重新加载并切换类型判定', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['one.txt'] = const FileResponse(
        content: 'one',
        size: 3,
        lines: 1,
      );
      api.fileContents['two.md'] = const FileResponse(
        content: '# two',
        size: 5,
        lines: 1,
      );
      final source = FilePreviewSource.workspaceFile('s1', 'shared');

      await pumpBody(
        tester,
        api: api,
        body: FilePreviewBody(fileName: 'one.txt', source: source),
      );
      expect(find.byKey(const ValueKey('preview-text')), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient(baseUrl: kBaseUrl)),
            workspaceApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp(
            home: FilePreviewBody(fileName: 'two.md', source: source),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('preview-markdown')), findsOneWidget);
      expect(api.fetchFileCalls, ['s1|shared', 's1|shared']);
    });
  });
}
