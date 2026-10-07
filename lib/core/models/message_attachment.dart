import '../utils/lossy_json.dart';
import 'json_value.dart';

/// 消息附件（Swift: MessageAttachment.swift）。
///
/// 支持**裸字符串解码**：旧服务器把附件存成裸文件名时，整个元素是字符串，
/// 则 `name = 该字符串`，其余字段 null。
class MessageAttachment {
  const MessageAttachment({
    this.name,
    this.path,
    this.mime,
    this.size,
    this.isImage,
  });

  /// 从 JSON 解码。`json` 可以是对象（正常形态）或裸字符串（旧数据形态）。
  factory MessageAttachment.fromJson(Object? json) {
    if (json is String) {
      return MessageAttachment(name: json);
    }
    if (json is! Map) {
      return const MessageAttachment();
    }
    Map<String, Object?> map;
    try {
      map = Map<String, Object?>.from(json);
    } catch (_) {
      return const MessageAttachment();
    }
    return MessageAttachment(
      name: firstKey(map, ['name', 'filename'], lossyString),
      path: lossyString(map, 'path'),
      mime: lossyString(map, 'mime'),
      size: lossyInt(map, 'size'),
      isImage: lossyBool(map, 'is_image'),
    );
  }

  final String? name;
  final String? path;
  final String? mime;
  final int? size;
  final bool? isImage;

  /// 序列化（聊天发送用，对应 `toJSONValue`）：`{name, path, mime, size, is_image}`。
  JsonValue toJsonValue() {
    final object = <String, JsonValue>{
      if (name != null) 'name': JsonString(name!),
      if (path != null) 'path': JsonString(path!),
      if (mime != null) 'mime': JsonString(mime!),
      if (size != null) 'size': JsonNumber(size!.toDouble()),
      'is_image': JsonBool(isImage ?? false),
    };
    return JsonObject(object);
  }

  Map<String, Object?> toJson() {
    return {
      if (name != null) 'name': name,
      if (path != null) 'path': path,
      if (mime != null) 'mime': mime,
      if (size != null) 'size': size,
      if (isImage != null) 'is_image': isImage,
    };
  }

  /// 稳定身份键：name/path 中第一个非空值的 basename（最后一个 `/` 后一段）小写；
  /// 都空 → null。用于同一附件两种表示之间的匹配。
  String? get identityKey {
    final raw = [name, path]
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .firstOrNull;
    if (raw == null) return null;
    final lastComponent = _lastPathComponent(raw);
    final value = (lastComponent.isEmpty ? raw : lastComponent).toLowerCase();
    return value.isEmpty ? null : value;
  }

  /// 从消息文本尾部的 `[Attached files: ref1, ref2]` 标记推断附件列表；无标记 → null。
  static List<MessageAttachment>? inferredFromAttachedFilesMarker(
    String? content,
  ) {
    final marker = _attachedFilesMarker(content);
    if (marker == null) return null;

    String? inferredDirectory;
    for (final reference in marker.references) {
      if (_hasDirectorySeparator(reference)) {
        inferredDirectory = _parentDirectory(reference);
        break;
      }
    }

    final attachments = marker.references.map((reference) {
      return MessageAttachment(
        name: _displayName(reference),
        path: _inferredPath(reference, inferredDirectory),
        mime: null,
        size: null,
        isImage: isImageReference(reference),
      );
    }).toList();

    return attachments.isEmpty ? null : attachments;
  }

  /// 移除消息文本尾部的 `[Attached files: …]` 标记（连同其前的分隔空白），
  /// 供显示层使用。无标记 → 原样返回。
  static String contentWithoutAttachedFilesMarker(String content) {
    final marker = _attachedFilesMarker(content);
    if (marker == null) return content;

    var prefix = content.substring(0, marker.rangeStart);
    while (prefix.isNotEmpty &&
        _isWhitespace(prefix.codeUnitAt(prefix.length - 1))) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return prefix;
  }

  /// 扩展名 ∈ {jpg,jpeg,png,gif,webp,heic,heif,bmp,tiff,tif,svg,ico,avif} 或 data:image/。
  static bool isImageReference(String reference) {
    if (reference.trim().toLowerCase().startsWith('data:image/')) return true;
    final ext = _extensionOf(reference);
    return const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'bmp',
      'tiff',
      'tif',
      'svg',
      'ico',
      'avif',
    }.contains(ext);
  }

  /// 扩展名 ∈ {mp3,ogg,wav,m4a,aac,flac,wma,opus,oga,webm}。
  static bool isAudioReference(String reference) {
    final ext = _extensionOf(reference);
    return const {
      'mp3',
      'ogg',
      'wav',
      'm4a',
      'aac',
      'flac',
      'wma',
      'opus',
      'oga',
    }.contains(ext);
  }

  /// 扩展名 ∈ {mp4,webm,mkv,mov,avi,ogv,m4v}。
  static bool isVideoReference(String reference) {
    final ext = _extensionOf(reference);
    return const {
      'mp4',
      'webm',
      'mkv',
      'mov',
      'avi',
      'ogv',
      'm4v',
    }.contains(ext);
  }

  /// 文档类扩展名（pdf, txt, md, json, csv, etc.）。
  static bool isDocumentReference(String reference) {
    final ext = _extensionOf(reference);
    return const {
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'md',
      'csv',
      'json',
      'yaml',
      'yml',
      'html',
      'htm',
      'diff',
      'patch',
      'excalidraw',
    }.contains(ext);
  }

  /// 获取媒体类别。
  static MessageMediaKind mediaKindForName(String reference) {
    if (isImageReference(reference)) return MessageMediaKind.image;
    if (isAudioReference(reference)) return MessageMediaKind.audio;
    if (isVideoReference(reference)) return MessageMediaKind.video;
    if (isDocumentReference(reference)) return MessageMediaKind.document;
    return MessageMediaKind.file;
  }

  /// 拼接 `[Attached files: …]` 后缀（聊天发送用，对应 Swift `chatMessageText`）。
  static String chatMessageText(
    String draft,
    List<MessageAttachment> attachments,
  ) {
    final references = attachments
        .map((a) => (a.path == null || a.path!.isEmpty) ? a.name : a.path)
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (references.isEmpty) return draft;
    return '$draft\n\n[Attached files: ${references.join(', ')}]';
  }

  static bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D;
  }

  static String _lastPathComponent(String raw) {
    var s = raw.split('?').first.split('#').first;
    while (s.endsWith('/') || s.endsWith(r'\')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return raw;
    final forwardSlash = s.lastIndexOf('/');
    final backSlash = s.lastIndexOf(r'\');
    final idx = forwardSlash > backSlash ? forwardSlash : backSlash;
    return idx == -1 ? s : s.substring(idx + 1);
  }

  static String _extensionOf(String reference) {
    var clean = reference.split('?').first.split('#').first;
    clean = clean.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    final last = _lastPathComponent(clean);
    final dot = last.lastIndexOf('.');
    if (dot == -1 || dot == last.length - 1) return '';
    return last.substring(dot + 1).toLowerCase();
  }

  static String _displayName(String reference) {
    if (reference.trim().toLowerCase().startsWith('data:image/')) return 'image';
    final last = _lastPathComponent(reference);
    return last.isEmpty ? reference : last;
  }

  /// 是否为「带目录的引用」——`/` 与 Windows 的 `\` 都算目录分隔符。
  ///
  /// 历史实现只认 `/`，于是 `[Attached files: C:\Users\…\a.png]` 被当成
  /// 裸文件名：`path` 解析为 null ⇒ 用户气泡里的图片只剩文件名条、
  /// 内联缩略图永不出现（Windows 专属观感缺陷）。
  static bool _hasDirectorySeparator(String reference) =>
      _lastSeparatorIndex(reference) != -1;

  /// 最后一个目录分隔符下标（`/` 与 `\` 取更靠后者）；无则 -1。
  static int _lastSeparatorIndex(String value) {
    final forwardSlash = value.lastIndexOf('/');
    final backSlash = value.lastIndexOf(r'\');
    return forwardSlash > backSlash ? forwardSlash : backSlash;
  }

  static String? _parentDirectory(String reference) {
    var s = reference;
    while (s.endsWith('/') || s.endsWith(r'\')) {
      s = s.substring(0, s.length - 1);
    }
    final idx = _lastSeparatorIndex(s);
    if (idx == -1) return null;
    return s.substring(0, idx);
  }

  /// 用与 [directory] 相同的分隔符风格拼接（Windows 目录下不要掺 `/`）。
  static String _joinPath(String directory, String name) {
    if (directory.endsWith('/') || directory.endsWith(r'\')) {
      return '$directory$name';
    }
    final separator = directory.contains(r'\') && !directory.contains('/')
        ? r'\'
        : '/';
    return '$directory$separator$name';
  }

  static String? _inferredPath(String reference, String? fallbackDirectory) {
    if (_hasDirectorySeparator(reference)) return reference;
    if (isImageReference(reference) &&
        fallbackDirectory != null &&
        fallbackDirectory.isNotEmpty) {
      return _joinPath(fallbackDirectory, reference);
    }
    return null;
  }

  static ({int rangeStart, List<String> references})? _attachedFilesMarker(
    String? content,
  ) {
    if (content == null) return null;
    final markerStart = content.lastIndexOf('[Attached files:');
    if (markerStart == -1) return null;

    final afterMarker = content.substring(markerStart + '[Attached files:'.length);
    final closeBracket = afterMarker.indexOf(']');
    if (closeBracket == -1) return null;

    final afterBracket = afterMarker.substring(closeBracket + 1);
    if (afterBracket.trim().isNotEmpty) return null;

    final references = afterMarker
        .substring(0, closeBracket)
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return (
      rangeStart: markerStart,
      references: references,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MessageAttachment &&
        other.name == name &&
        other.path == path &&
        other.mime == mime &&
        other.size == size &&
        other.isImage == isImage;
  }

  @override
  int get hashCode => Object.hash(name, path, mime, size, isImage);

  @override
  String toString() {
    return 'MessageAttachment(name: $name, path: $path, mime: $mime, '
        'size: $size, isImage: $isImage)';
  }
}

/// 媒体类型分类。
enum MessageMediaKind {
  image,
  audio,
  video,
  document,
  file,
}

