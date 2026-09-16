import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/workspace.dart';
import '../../l10n/app_localizations.dart';
import '../chat/widgets/chat_media_parser.dart';
import '../chat/widgets/markdown_styles.dart';
import '../workspace/workspace_providers.dart';
import 'office_document.dart';

/// 文件预览类型（镜像 WebUI `workspace.js:811-820` 的扩展名白名单思路）。
enum WorkspaceFileKind {
  /// 文本（代码/标记/纯文本），走 /api/file 文本预览。
  text,

  /// 图片，走 /api/file/raw 原始字节。
  image,

  /// 视频，media_kit 内存字节播放（mp4/mov/webm/mkv/avi/m4v）。
  video,

  /// 音频，media_kit 内存字节播放（mp3/wav/m4a/aac/ogg/flac/opus）。
  audio,

  /// PDF（pdfrx 内嵌渲染）。
  pdf,

  /// Office 文档（docx/xlsx/pptx/doc/xls/ppt）。
  office,

  /// 归档/二进制黑名单（zip 等，点击直接下载）。
  archive,

  /// 其他未知类型（不猜测，走下载兜底）。
  other,
}

const Set<String> _textExts = {
  '.md',
  '.markdown',
  '.txt',
  '.text',
  '.log',
  '.dart',
  '.py',
  '.js',
  '.jsx',
  '.ts',
  '.tsx',
  '.json',
  '.yaml',
  '.yml',
  '.toml',
  '.ini',
  '.cfg',
  '.conf',
  '.sh',
  '.bash',
  '.bat',
  '.cmd',
  '.ps1',
  '.xml',
  '.html',
  '.htm',
  '.css',
  '.scss',
  '.sql',
  '.java',
  '.go',
  '.rs',
  '.c',
  '.cpp',
  '.h',
  '.rb',
  '.php',
  '.kt',
  '.swift',
  '.gradle',
  '.lock',
  '.env',
  '.gitignore',
  '.gitattributes',
  '.editorconfig',
  '.svg',
  '.csv',
  '.tsv',
  '.rtf',
};

const Set<String> _imageExts = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.ico',
};

const Set<String> _videoExts = {
  '.mp4',
  '.mov',
  '.webm',
  '.mkv',
  '.avi',
  '.m4v',
};

const Set<String> _audioExts = {
  '.mp3',
  '.wav',
  '.m4a',
  '.aac',
  '.ogg',
  '.flac',
  '.opus',
};

const Set<String> _pdfExts = {'.pdf'};

const Set<String> _officeExts = {
  '.docx',
  '.xlsx',
  '.pptx',
  '.doc',
  '.xls',
  '.ppt',
};

/// 归档/二进制「下载优先」扩展名。
const Set<String> _archiveExts = {
  '.zip',
  '.tar',
  '.gz',
  '.tgz',
  '.bz2',
  '.tbz2',
  '.xz',
  '.txz',
  '.7z',
  '.rar',
  '.iso',
  '.exe',
  '.msi',
  '.dmg',
  '.pkg',
  '.apk',
  '.aab',
  '.ipa',
  '.dll',
  '.so',
  '.dylib',
  '.bin',
  '.dat',
  '.db',
  '.sqlite',
  '.sqlite3',
  '.woff',
  '.woff2',
  '.ttf',
  '.otf',
};

/// 按扩展名或 WorkspaceEntry 判定文件预览类型。
WorkspaceFileKind workspaceFileKindOf(Object entryOrName) {
  final String name;
  if (entryOrName is WorkspaceEntry) {
    name = (entryOrName.name ?? entryOrName.path ?? '').toLowerCase();
  } else if (entryOrName is String) {
    name = entryOrName.toLowerCase();
  } else {
    name = entryOrName.toString().toLowerCase();
  }
  if (_imageExts.any(name.endsWith)) return WorkspaceFileKind.image;
  if (_videoExts.any(name.endsWith)) return WorkspaceFileKind.video;
  if (_audioExts.any(name.endsWith)) return WorkspaceFileKind.audio;
  if (_pdfExts.any(name.endsWith)) return WorkspaceFileKind.pdf;
  if (_officeExts.any(name.endsWith)) return WorkspaceFileKind.office;
  if (_archiveExts.any(name.endsWith)) return WorkspaceFileKind.archive;
  if (_textExts.any(name.endsWith)) return WorkspaceFileKind.text;
  return WorkspaceFileKind.other;
}

/// 是否可在应用内预览（文本/图片/音视频/PDF/Office）；其余类型走下载兜底。
bool workspaceFileIsPreviewable(Object entryOrName) {
  final kind = workspaceFileKindOf(entryOrName);
  return kind == WorkspaceFileKind.text ||
      kind == WorkspaceFileKind.image ||
      kind == WorkspaceFileKind.video ||
      kind == WorkspaceFileKind.audio ||
      kind == WorkspaceFileKind.pdf ||
      kind == WorkspaceFileKind.office;
}

/// 文件预览数据源抽象。
abstract class FilePreviewSource {
  const FilePreviewSource();

  /// 工作区文件来源（通过 WorkspaceApi 拉取）。
  factory FilePreviewSource.workspaceFile(String sessionId, String path) =
      _WorkspaceFilePreviewSource;

  /// 已解析的 URL 或内存字节来源（聊天附件用）。
  factory FilePreviewSource.resolved(
    String? url, {
    Uint8List? bytes,
    String? sessionId,
  }) = _ResolvedFilePreviewSource;

  /// 直接内存字节来源。
  factory FilePreviewSource.bytes(Uint8List bytes) = _BytesFilePreviewSource;

  /// 拉取文本内容。
  Future<FileResponse> loadText(WidgetRef ref, {required String fileName});

  /// 拉取二进制原始字节。
  Future<Uint8List> loadBytes(WidgetRef ref);
}

class _WorkspaceFilePreviewSource extends FilePreviewSource {
  const _WorkspaceFilePreviewSource(this.sessionId, this.path);

  final String sessionId;
  final String path;

  @override
  Future<FileResponse> loadText(WidgetRef ref, {required String fileName}) {
    final api = ref.read(workspaceApiFactoryProvider)(
      ref.read(apiClientProvider),
    );
    return api.fetchFileContent(sessionId: sessionId, path: path);
  }

  @override
  Future<Uint8List> loadBytes(WidgetRef ref) {
    final api = ref.read(workspaceApiFactoryProvider)(
      ref.read(apiClientProvider),
    );
    return api.downloadFile(sessionId: sessionId, path: path);
  }
}

class _ResolvedFilePreviewSource extends FilePreviewSource {
  const _ResolvedFilePreviewSource(this.url, {this.bytes, this.sessionId});

  final String? url;
  final Uint8List? bytes;
  final String? sessionId;

  @override
  Future<Uint8List> loadBytes(WidgetRef ref) async {
    if (bytes != null && bytes!.isNotEmpty) {
      return bytes!;
    }
    final rawUrl = url;
    if (rawUrl == null || rawUrl.isEmpty) {
      return Uint8List(0);
    }

    // 1. data: URI 解码
    if (rawUrl.startsWith('data:')) {
      final commaIdx = rawUrl.indexOf(',');
      final payload = commaIdx != -1 ? rawUrl.substring(commaIdx + 1) : rawUrl;
      return base64Decode(payload);
    }

    // 2. 本地文件直读
    if (!kIsWeb) {
      var localPath = rawUrl;
      if (localPath.startsWith('file://')) {
        try {
          localPath = Uri.parse(localPath).toFilePath();
        } catch (_) {
          localPath = localPath.substring(7);
        }
      }
      final localFile = File(localPath);
      if (await localFile.exists()) {
        return localFile.readAsBytes();
      }
    }

    // 3. 相对 api 路径解析为有效 URL
    var effectiveUrl = rawUrl;
    if (!effectiveUrl.startsWith('http://') &&
        !effectiveUrl.startsWith('https://')) {
      String baseUrl = '';
      try {
        baseUrl = ref.read(apiClientProvider).baseUrl;
      } catch (_) {
        baseUrl = '';
      }
      if (baseUrl.isNotEmpty) {
        effectiveUrl = ChatMediaResolver.resolveMediaUrl(
          effectiveUrl,
          baseUrl: baseUrl,
          sessionId: sessionId,
        );
      }
    }

    // 4. http(s) 走 ApiClient 通用拉字节
    if (effectiveUrl.startsWith('http://') ||
        effectiveUrl.startsWith('https://')) {
      final client = ref.read(apiClientProvider);
      return client.urlBytes(effectiveUrl);
    }

    return Uint8List(0);
  }

  @override
  Future<FileResponse> loadText(
    WidgetRef ref, {
    required String fileName,
  }) async {
    final b = await loadBytes(ref);
    final text = utf8.decode(b, allowMalformed: true);
    final lineCount = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    return FileResponse(
      content: text,
      path: fileName,
      size: b.length,
      lines: lineCount,
    );
  }
}

class _BytesFilePreviewSource extends FilePreviewSource {
  const _BytesFilePreviewSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<FileResponse> loadText(
    WidgetRef ref, {
    required String fileName,
  }) async {
    final text = utf8.decode(bytes, allowMalformed: true);
    final lineCount = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    return FileResponse(
      content: text,
      path: fileName,
      size: bytes.length,
      lines: lineCount,
    );
  }

  @override
  Future<Uint8List> loadBytes(WidgetRef ref) async => bytes;
}

/// 共享文件预览正文组件（支持 text/image/video/audio/pdf/office/兜底下载）。
class FilePreviewBody extends ConsumerStatefulWidget {
  /// 预览临时文件目录。
  ///
  /// 默认 [Directory.systemTemp]；测试可覆盖为**独立子目录**——`flutter test`
  /// 是多测试文件并发跑的，共享同一目录会让「本次落了几个文件」这类断言被
  /// 同目录其它用例落下的文件污染（实测可致假失败）。
  @visibleForTesting
  static Directory previewTempDir = Directory.systemTemp;

  const FilePreviewBody({
    super.key,
    required this.fileName,
    required this.source,
    this.onDownload,
    this.downloadButton,
    this.sizeBytes,
  });

  /// 文件名或路径（用于类型判定及元信息展示）。
  final String fileName;

  /// 数据来源。
  final FilePreviewSource source;

  /// 兜底下载回调。
  final VoidCallback? onDownload;

  /// 自定义下载按钮小部件（优先渲染于兜底视图）。
  final Widget? downloadButton;

  /// 预估文件大小（字节数）。
  final int? sizeBytes;

  @override
  ConsumerState<FilePreviewBody> createState() => _FilePreviewBodyState();
}

class _FilePreviewBodyState extends ConsumerState<FilePreviewBody> {
  late WorkspaceFileKind _kind = workspaceFileKindOf(widget.fileName);

  bool _loading = true;
  Object? _loadError;

  FileResponse? _file;
  Uint8List? _imageBytes;
  String? _mediaTempPath;
  String? _pdfTempPath;
  OfficeDocument? _officeDocument;
  int _selectedSheetIndex = 0;

  /// 加载代次：并发 [_load]（rebuild 风暴）时后发者取代先发者。
  ///
  /// 落盘型分支凭它判断「自己是否已被取代」——被取代则立刻删掉刚写下的临时文件，
  /// 否则同一批并发加载会各留一个孤儿（实测单次 pump 可残留 4 个 `.pdf`）。
  int _loadGeneration = 0;

  Player? _player;
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(FilePreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileName != widget.fileName ||
        oldWidget.source != widget.source) {
      _kind = workspaceFileKindOf(widget.fileName);
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    unawaited(_disposeMedia());
    super.dispose();
  }

  /// 删除上一次留下的临时预览文件。
  ///
  /// ⚠️ [_mediaTempPath] / [_pdfTempPath] 都是**单字段**：重新加载时直接覆盖会丢掉
  /// 旧路径，而 dispose 只能删当前这一个 → 每次 rebuild 都在 %TEMP% 漏一个
  /// `hermes_preview_*`（实测单次测试即可累积 4 个）。故落盘成功后先把上一个删掉。
  Future<void> _dropPreviousTempFile(String? path, {String? exceptPath}) async {
    if (path == null || path == exceptPath) return;
    try {
      final previous = File(path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      // 清理失败不影响主流程（下次加载还会再试）。
    }
  }

  Future<void> _disposeMedia() async {
    final player = _player;
    _videoController = null;
    _player = null;
    try {
      await player?.dispose();
    } catch (_) {}
    final tempPath = _mediaTempPath;
    _mediaTempPath = null;
    if (tempPath != null) {
      try {
        final file = File(tempPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    final pdfTempPath = _pdfTempPath;
    _pdfTempPath = null;
    if (pdfTempPath != null) {
      try {
        final file = File(pdfTempPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    await _disposeMedia();
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _file = null;
      _imageBytes = null;
      _mediaTempPath = null;
      _pdfTempPath = null;
      _officeDocument = null;
      _selectedSheetIndex = 0;
    });

    try {
      if (_kind == WorkspaceFileKind.text) {
        final response = await widget.source.loadText(
          ref,
          fileName: widget.fileName,
        );
        if (!mounted) return;
        setState(() {
          _file = response;
          _loading = false;
        });
      } else if (_kind == WorkspaceFileKind.image) {
        final bytes = await widget.source.loadBytes(ref);
        if (!mounted) return;
        setState(() {
          _imageBytes = bytes;
          _loading = false;
        });
      } else if (_kind == WorkspaceFileKind.video ||
          _kind == WorkspaceFileKind.audio) {
        final bytes = await widget.source.loadBytes(ref);
        if (!mounted) return;
        if (bytes.isEmpty) {
          setState(() => _loading = false);
          return;
        }
        final ext = _extOf(widget.fileName);
        final tempDir = FilePreviewBody.previewTempDir;
        final tempFile = File(
          '${tempDir.path}/hermes_preview_${DateTime.now().millisecondsSinceEpoch}$ext',
        );
        await tempFile.writeAsBytes(bytes, flush: true);
        if (generation != _loadGeneration) {
          // 本次加载已被更新的调用取代 → 立刻删掉自己刚写的，避免并发孤儿。
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
          return;
        }
        // 先清掉上一次的临时文件（单字段覆盖会丢旧路径 → 泄漏）。
        await _dropPreviousTempFile(_mediaTempPath, exceptPath: tempFile.path);
        // ⚠️ 写盘后立刻登记路径：下面的 Player() / open() 都可能抛错，
        // 若等 setState 才赋值 _mediaTempPath，异常路径下 dispose 不知道要删哪个文件
        // → %TEMP% 会持续累积 hermes_preview_* 残留。
        _mediaTempPath = tempFile.path;
        final player = Player();
        final controller = _kind == WorkspaceFileKind.video
            ? VideoController(player)
            : null;
        setState(() {
          _player = player;
          _videoController = controller;
        });
        await player.open(Media(tempFile.path));
        if (!mounted) return;
        setState(() => _loading = false);
      } else if (_kind == WorkspaceFileKind.pdf) {
        final bytes = await widget.source.loadBytes(ref);
        if (!mounted) return;
        if (bytes.isEmpty) {
          setState(() {
            _loading = false;
            _loadError = const FormatException('Empty PDF file');
          });
          return;
        }
        final tempDir = FilePreviewBody.previewTempDir;
        final tempFile = File(
          '${tempDir.path}/hermes_preview_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
        await tempFile.writeAsBytes(bytes, flush: true);
        if (generation != _loadGeneration) {
          // 本次加载已被更新的调用取代 → 立刻删掉自己刚写的，避免并发孤儿。
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
          return;
        }
        // 先清掉上一次的临时文件（单字段覆盖会丢旧路径 → 泄漏）。
        await _dropPreviousTempFile(_pdfTempPath, exceptPath: tempFile.path);
        if (!mounted) {
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
          return;
        }
        setState(() {
          _pdfTempPath = tempFile.path;
          _loading = false;
        });
      } else if (_kind == WorkspaceFileKind.office) {
        final bytes = await widget.source.loadBytes(ref);
        if (!mounted) return;
        if (bytes.isEmpty) {
          throw const OfficeParseException('Empty office file');
        }
        final ext = _extOf(widget.fileName);
        final doc = OfficeDocumentParser.parse(bytes, ext);
        if (!mounted) return;
        setState(() {
          _officeDocument = doc;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  static String _extOf(String name) {
    final idx = name.lastIndexOf('.');
    if (idx < 0) return '';
    return name.substring(idx).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CupertinoActivityIndicator(radius: 14),
        ),
      );
    }
    final error = _loadError;
    if (error != null) {
      final String message;
      if (error is OfficeParseException) {
        message = error.isTooLarge
            ? l10n.previewOfficeTooLarge
            : l10n.previewOfficeUnsupported;
      } else if (error is ApiException) {
        message = error.message;
      } else {
        message = error.toString();
      }
      return _buildFallback(
        message: message,
        onRetry: () => unawaited(_load()),
      );
    }

    switch (_kind) {
      case WorkspaceFileKind.text:
        return _buildTextBody();
      case WorkspaceFileKind.image:
        final bytes = _imageBytes;
        if (bytes == null || bytes.isEmpty) {
          return _buildUnsupportedBody(l10n);
        }
        return SizedBox.expand(
          child: InteractiveViewer(
            key: const ValueKey('preview-image-viewer'),
            minScale: 0.5,
            maxScale: 4,
            child: Image.memory(
              bytes,
              key: const ValueKey('preview-image'),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _buildUnsupportedBody(l10n),
            ),
          ),
        );
      case WorkspaceFileKind.video:
        return _buildVideoBody();
      case WorkspaceFileKind.audio:
        return _buildAudioBody();
      case WorkspaceFileKind.pdf:
        return _buildPdfBody();
      case WorkspaceFileKind.office:
        return _buildOfficeBody();
      case WorkspaceFileKind.archive:
      case WorkspaceFileKind.other:
        return _buildUnsupportedBody(l10n);
    }
  }

  Widget _buildVideoBody() {
    final l10n = AppLocalizations.of(context);
    final controller = _videoController;
    final player = _player;
    if (controller == null || player == null) {
      return _buildUnsupportedBody(l10n);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMediaMetaLine(l10n),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(
              key: const ValueKey('preview-video'),
              controller: controller,
            ),
          ),
          const SizedBox(height: 12),
          _MediaControls(
            key: const ValueKey('preview-video-controls'),
            player: player,
          ),
        ],
      ),
    );
  }

  Widget _buildAudioBody() {
    final l10n = AppLocalizations.of(context);
    final player = _player;
    if (player == null) {
      return _buildUnsupportedBody(l10n);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.music_note_2,
            size: 64,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: CupertinoColors.systemGrey,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.fileName.isNotEmpty ? widget.fileName : l10n.unnamedFile,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _buildMediaMetaLine(l10n),
          const SizedBox(height: 20),
          _MediaControls(
            key: const ValueKey('preview-audio-controls'),
            player: player,
          ),
        ],
      ),
    );
  }

  Widget _buildPdfBody() {
    final l10n = AppLocalizations.of(context);
    final tempPath = _pdfTempPath;
    if (tempPath == null) {
      return _buildFallback(
        message: l10n.previewPdfFailed,
        onRetry: () => unawaited(_load()),
      );
    }
    return SizedBox.expand(
      child: Container(
        key: const ValueKey('preview-pdf'),
        child: PdfViewer.file(
          tempPath,
          params: PdfViewerParams(
            backgroundColor: CupertinoColors.systemBackground.resolveFrom(
              context,
            ),
            errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                _buildFallback(
                  message: l10n.previewPdfFailed,
                  onRetry: () => unawaited(_load()),
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildOfficeBody() {
    final l10n = AppLocalizations.of(context);
    final doc = _officeDocument;
    if (doc == null) {
      return _buildUnsupportedBody(l10n);
    }
    switch (doc.kind) {
      case OfficeDocumentKind.docx:
        return _buildDocxBody(doc);
      case OfficeDocumentKind.xlsx:
        return _buildXlsxBody(doc);
      case OfficeDocumentKind.pptx:
        return _buildPptxBody(doc);
      case OfficeDocumentKind.legacy:
        return _buildLegacyOfficeBody(doc);
    }
  }

  Widget _buildDocxBody(OfficeDocument doc) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        key: const ValueKey('preview-office-docx'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMediaMetaLine(l10n),
            const SizedBox(height: 12),
            for (final block in doc.blocks) ...[
              if (block.isTable && block.table != null) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildOfficeTable(block.table!),
                ),
                const SizedBox(height: 12),
              ] else if (block.isParagraph && block.text != null) ...[
                if (block.heading != null) ...[
                  SelectableText(
                    block.text!,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  SelectableText(
                    block.text!,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildXlsxBody(OfficeDocument doc) {
    final l10n = AppLocalizations.of(context);
    final sheets = doc.sheets;
    final currentIdx = (_selectedSheetIndex < sheets.length)
        ? _selectedSheetIndex
        : 0;
    final currentSheet = sheets.isNotEmpty ? sheets[currentIdx] : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        key: const ValueKey('preview-office-xlsx'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMediaMetaLine(l10n),
            const SizedBox(height: 12),
            if (sheets.length > 1) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: currentIdx,
                  children: {
                    for (int i = 0; i < sheets.length; i++)
                      i: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(sheets[i].name),
                      ),
                  },
                  onValueChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedSheetIndex = val);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (currentSheet != null && currentSheet.rows.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildOfficeTable(currentSheet.rows),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPptxBody(OfficeDocument doc) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        key: const ValueKey('preview-office-pptx'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMediaMetaLine(l10n),
            const SizedBox(height: 12),
            for (int i = 0; i < doc.slides.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(height: 12),
                Container(
                  height: 0.5,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.divider,
                    dark: CupertinoColors.separator,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? CupertinoColors.secondarySystemBackground.resolveFrom(
                          context,
                        )
                      : LightSurfaces.card,
                  borderRadius: BorderRadius.circular(8),
                  border: isDark
                      ? null
                      : Border.all(color: LightSurfaces.cardBorder, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemFill.resolveFrom(
                          context,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.previewOfficeSlide(doc.slides[i].index),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: secondaryText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final line in doc.slides[i].lines) ...[
                      SelectableText(
                        line,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegacyOfficeBody(OfficeDocument doc) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        key: const ValueKey('preview-office-legacy'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMediaMetaLine(l10n),
            const SizedBox(height: 8),
            Text(
              l10n.previewOfficeLegacyHint,
              style: TextStyle(
                fontSize: 12,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              doc.legacyText,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfficeTable(List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.divider,
          dark: CupertinoColors.separator,
        ),
        width: 0.5,
      ),
      children: [
        for (int i = 0; i < rows.length; i++)
          TableRow(
            children: [
              for (final cell in rows[i])
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    cell,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == 0 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildMediaMetaLine(AppLocalizations l10n) {
    final size = widget.sizeBytes;
    if (size == null) return const SizedBox.shrink();
    return Text(
      _formatFileSize(size),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.textSecondary,
          dark: secondaryText,
        ),
      ),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  Widget _buildTextBody() {
    final l10n = AppLocalizations.of(context);
    final file = _file;
    final serverError = file?.error;
    if (serverError != null && serverError.isNotEmpty) {
      return _buildFallback(
        message: serverError,
        onRetry: () => unawaited(_load()),
      );
    }
    final name = widget.fileName.toLowerCase();
    final content = file?.content ?? '';
    final isMarkdown = name.endsWith('.md') || name.endsWith('.markdown');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetaLine(l10n, file),
          const SizedBox(height: 8),
          if (isMarkdown)
            MarkdownBody(
              key: const ValueKey('preview-markdown'),
              data: content,
              selectable: true,
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            )
          else
            Text(
              content.isEmpty ? l10n.emptyFile : content,
              key: const ValueKey('preview-text'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetaLine(AppLocalizations l10n, FileResponse? file) {
    final size = file?.size ?? widget.sizeBytes;
    final parts = <String>[
      if (size != null) '$size B',
      if (file?.lines != null) '${file!.lines} ${l10n.linesShort}',
      if (file?.truncated == true) l10n.previewTruncated,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: TextStyle(
        fontSize: 12,
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.textSecondary,
          dark: secondaryText,
        ),
      ),
    );
  }

  Widget _buildUnsupportedBody(AppLocalizations l10n) {
    final customBtn = widget.downloadButton;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.doc_plaintext,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.previewUnavailable,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.previewUnavailableHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
            if (customBtn != null) ...[
              const SizedBox(height: 20),
              customBtn,
            ] else if (widget.onDownload != null) ...[
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('preview-download-fallback'),
                color: CupertinoTheme.brightnessOf(context) == Brightness.light
                    ? LightSurfaces.userDetail
                    : null,
                onPressed: widget.onDownload,
                child: Text(l10n.download),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFallback({
    required String message,
    required VoidCallback onRetry,
  }) {
    final l10n = AppLocalizations.of(context);
    final customBtn = widget.downloadButton;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CupertinoButton.filled(
                  key: const ValueKey('preview-retry'),
                  color:
                      CupertinoTheme.brightnessOf(context) == Brightness.light
                      ? LightSurfaces.userDetail
                      : null,
                  onPressed: onRetry,
                  child: Text(l10n.retry),
                ),
                if (customBtn != null) ...[
                  const SizedBox(width: 12),
                  customBtn,
                ] else if (widget.onDownload != null) ...[
                  const SizedBox(width: 12),
                  CupertinoButton(
                    key: const ValueKey('preview-download-fallback'),
                    onPressed: widget.onDownload,
                    child: Text(l10n.download),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cupertino 风格的音视频播放控件（播放/暂停、进度条、时长）。
class _MediaControls extends StatefulWidget {
  const _MediaControls({super.key, required this.player});

  final Player player;

  @override
  State<_MediaControls> createState() => _MediaControlsState();
}

class _MediaControlsState extends State<_MediaControls> {
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _playing = widget.player.state.playing;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _playingSub = widget.player.stream.playing.listen((value) {
      if (mounted) setState(() => _playing = value);
    });
    _positionSub = widget.player.stream.position.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSub = widget.player.stream.duration.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
  }

  @override
  void dispose() {
    unawaited(_playingSub.cancel());
    unawaited(_positionSub.cancel());
    unawaited(_durationSub.cancel());
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds.toDouble();
    final posMs = _position.inMilliseconds.toDouble().clamp(
      0,
      maxMs > 0 ? maxMs : 0,
    );
    final hasDuration = maxMs > 0;
    return Column(
      children: [
        Row(
          children: [
            CupertinoButton(
              key: const ValueKey('preview-media-play-pause'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () {
                if (_playing) {
                  unawaited(widget.player.pause());
                } else {
                  unawaited(widget.player.play());
                }
              },
              child: Icon(
                _playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                size: 28,
                color: CupertinoColors.activeBlue.resolveFrom(context),
              ),
            ),
            Expanded(
              child: CupertinoSlider(
                key: const ValueKey('preview-media-slider'),
                value: hasDuration ? posMs.toDouble() : 0,
                min: 0,
                max: hasDuration ? maxMs : 1,
                onChanged: hasDuration
                    ? (value) {
                        unawaited(
                          widget.player.seek(
                            Duration(milliseconds: value.round()),
                          ),
                        );
                      }
                    : null,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(
                  fontSize: 12,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: secondaryText,
                  ),
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(
                  fontSize: 12,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
