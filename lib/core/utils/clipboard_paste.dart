import 'dart:async';
import 'dart:io';
// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// 粘贴附件数据（二进制内容 + 文件名）。
typedef PastedAttachment = ({Uint8List bytes, String filename});

/// 剪贴板附件读取服务抽象接口。
///
/// 生产实现 [PlatformClipboardPasteService] 读取系统剪贴板；
/// 测试注入 [FakeClipboardPasteService] 或自定义 fake，避免碰平台通道。
abstract interface class ClipboardPasteService {
  /// 从剪贴板读取待粘贴的附件（图片或文件）。
  /// 若剪贴板中无可粘贴附件（例如仅含纯文本或为空），返回 null。
  Future<PastedAttachment?> readPastedAttachment();
}

/// 生产实现：基于剪贴板读取系统剪贴板。
///
/// - Windows：使用 [Pasteboard]（纯 Win32 C++，无 Rust FFI）绕过
///   `super_clipboard`/`irondash 0.1.1` 在 Dart 3.13 上的
///   `Dart_UpdateFinalizableExternalSize not found` abort。
/// - 桌面（macOS / Linux）：使用 `super_clipboard` 的 [ClipboardReader]。
/// - 移动端（Android / iOS / fuchsia）：**不探测附件**（恒返回 null）。
///   同一条 FFI 路径在移动端是进程级 abort 风险（懒初始化 + `panic = "abort"`），
///   这正是「输入框长按 → 粘贴 → 闪退」的根因，见 [nativeFfiPasteProbeEnabled]。
class PlatformClipboardPasteService implements ClipboardPasteService {
  const PlatformClipboardPasteService({this.customReader});

  /// 自定义 reader（可选，用于测试注入）。
  final ClipboardDataReader? customReader;

  @override
  Future<PastedAttachment?> readPastedAttachment() {
    return readPastedAttachmentFromClipboard(customReader: customReader);
  }
}

/// 测试用 Fake：固定返回一个附件（或抛错/返回 null 模拟无附件/取消）。
class FakeClipboardPasteService implements ClipboardPasteService {
  FakeClipboardPasteService({this.result, this.error});

  /// 要返回的结果；null 表示无附件（放行文本）。
  final PastedAttachment? result;

  /// 若设置，readPastedAttachment 直接抛此异常。
  final Object? error;

  @override
  Future<PastedAttachment?> readPastedAttachment() async {
    if (error != null) throw error!;
    return result;
  }
}

/// 支持的图片格式列表（按优先级尝试，仅非 Windows 路径）。
const _imageFormats = <SimpleDataFormat<Uint8List>>[
  Formats.png,
  Formats.jpeg,
  Formats.gif,
  Formats.webp,
  Formats.tiff,
];

/// 附件探测超时：非 Windows 上 FFI 可能卡死/抛异常，超时即视为无附件放行文本。
const _attachmentProbeTimeout = Duration(milliseconds: 1500);

/// 从剪贴板尝试读取附件（图片或文件），无附件时返回 null。
///
/// - Windows：使用 [Pasteboard.image] / [Pasteboard.files]（Win32 无 FFI）。
/// - 桌面非 Windows（macOS / Linux）：优先级策略：
///   1. 优先图片：检测 png/jpeg/gif/webp/tiff，读取二进制，支持 virtual file 兜底；
///   2. 其次文件：检测 fileUri，解析为本地文件并读取 bytes；支持 virtual file 兜底；
///   3. 皆无则返回 null，放行系统默认纯文本粘贴。
/// - 移动端（Android / iOS）：**不探测，恒返回 null**（放行纯文本粘贴）——
///   见 [nativeFfiPasteProbeEnabled] 的契约与代价。
///
/// 所有 FFI 路径均有 try/catch + 超时兜底，任何异常都返回 null 不抛。
Future<PastedAttachment?> readPastedAttachment({
  ClipboardDataReader? customReader,
}) => readPastedAttachmentFromClipboard(customReader: customReader);

/// 是否允许走 `super_clipboard` 的原生 FFI 附件探测。
///
/// 契约（2026-09-21，主人拍板 A 案）：**移动端一律不走，只有桌面走**。
///
/// 背景（本判据存在的理由，勿删）：`super_clipboard` 的 Dart 侧是**懒初始化**
/// ——`ClipboardReader.instance`（`static final`）→ `superNativeExtensionsContext`
/// （顶层 `final`）→ `DynamicLibrary.open("libsuper_native_extensions.so")` +
/// `super_native_extensions_init_message_channel_context`，即**首次真正用到
/// `ClipboardReader` 时才进 Rust**。而该 Rust 库 profile 为 `panic = "abort"`
/// （包内 `rust/Cargo.toml`），源码里还有 `CONTEXT.get().unwrap()` /
/// `CLIP_DATA_HELPER.get().unwrap()` 一类断点（`rust/src/android/reader.rs`），
/// 且 Java 侧 `SuperNativeExtensionsPlugin.onAttachedToEngine` 用
/// `catch (Throwable)` 把 native init 失败**静默吞成一行 log** ⇒
/// 任何失败都是**进程级 abort**，Dart 的 `try/catch` 完全兜不住，
/// 表现为「聊天输入框长按 → 粘贴 → 闪退」。
///
/// Windows 早在同类 abort 上实测复现过（改走 `pasteboard` 绕过，见
/// `tools/patch_windows_irondash.py` 与 `windows/CMakeLists.txt`），
/// **Android 从未被处置**：输入框菜单把「粘贴」劫持进 `_handlePaste()`，
/// 而它无条件先探附件 ⇒ 一定进 FFI 路径。
///
/// 代价（已知并接受）：移动端不再支持「粘贴图片/文件为附件」，
/// 剪贴板为纯文本时照常粘贴（引擎 `Clipboard.getData` 通道，安全）。
/// 彻底解法是升级 `super_clipboard` 到 0.9+（脱离 irondash 0.1.x），
/// 届时本判据连同两个 pub cache / Windows 补丁脚本一并删除。
///
/// 抽成独立判据以便测试用 `debugDefaultTargetPlatformOverride` 覆盖。
@visibleForTesting
bool nativeFfiPasteProbeEnabled(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return true;
  }
}

/// 核心读取实现。
Future<PastedAttachment?> readPastedAttachmentFromClipboard({
  ClipboardDataReader? customReader,
}) async {
  // 有注入 reader（测试）时直接走短路径，不加超时
  if (customReader != null) {
    try {
      final direct = await _readFromDataReader(customReader);
      if (direct != null) return direct;
      // fileUri / virtual 路径也在最外层兜底里，但这里再补一次
      return await _readVirtualFallback(customReader);
    } catch (_) {
      return null;
    }
  }

  // 移动端：整条 FFI 探测路径摘除（「输入框长按 → 粘贴 → 闪退」的止血，
  // 契约与代价见 nativeFfiPasteProbeEnabled 的文档）。这里直接报告「无附件」，
  // 由调用方回落纯文本粘贴（引擎 Clipboard.getData 通道，安全）。
  //
  // 判据必须排在最前：`defaultTargetPlatform` 可被测试 override，而 `Platform`
  // 是 dart:io 的真实平台——顺序颠倒会让「在 Windows 主机上跑 Android 分支」
  // 的测试误进 pasteboard 分支摸真实剪贴板。
  if (!nativeFfiPasteProbeEnabled(defaultTargetPlatform)) {
    return null;
  }

  // Windows：使用 pasteboard（纯 Win32 C++），完全绕过 super_clipboard 的 Rust FFI。
  if (!kIsWeb && Platform.isWindows) {
    return await _readFromPasteboardWindows();
  }

  // 桌面（macOS / Linux）生产路径：FFI 带超时，超时/异常一律视为无附件
  try {
    final result = await _probeAttachmentWithTimeout();
    return result;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}

/// Windows 专用：使用 pasteboard 读取剪贴板图片/文件（Win32 CF_DIB/CF_HDROP，无 Rust FFI）。
Future<PastedAttachment?> _readFromPasteboardWindows() async {
  // 1. 优先图片：Pasteboard.image 在 Windows 返回临时文件路径上的 bytes（Dart 层已读删）
  try {
    final imageBytes = await Pasteboard.image;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      // pasteboard 的 Windows 实现通过 GDI+ 将 CF_DIB 转 PNG bytes
      return (bytes: imageBytes, filename: 'pasted_image.png');
    }
  } catch (_) {}

  // 2. 其次文件：Pasteboard.files() 返回剪贴板中的文件路径列表
  try {
    final files = await Pasteboard.files();
    if (files.isNotEmpty) {
      final firstPath = files.first;
      if (firstPath.isNotEmpty) {
        final file = File(firstPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            final filename = file.uri.pathSegments.isNotEmpty
                ? file.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'attachment')
                : 'attachment';
            return (bytes: bytes, filename: filename);
          }
        }
      }
    }
  } catch (_) {}

  return null;
}

Future<PastedAttachment?> _probeAttachmentWithTimeout() async {
  return await Future<PastedAttachment?>(() async {
    final reader = await ClipboardReader.readClipboard();
    // 使用 dynamic 访问 items，避免静态类型收窄告警；运行时行为保持不变
    final dynamic dynReader = reader;
    List<dynamic> items = const [];
    try {
      final dynItems = dynReader.items;
      if (dynItems is List && dynItems.isNotEmpty) items = dynItems;
    } catch (_) {}
    if (items.isNotEmpty) {
      for (final item in items) {
        final result = await _readFromDataReader(item as ClipboardDataReader);
        if (result != null) return result;
      }
      final fallback = await _readVirtualFallback(items.first as ClipboardDataReader);
      if (fallback != null) return fallback;
      return null;
    }
    final direct = await _readFromDataReader(reader);
    if (direct != null) return direct;
    return await _readVirtualFallback(reader);
  }).timeout(_attachmentProbeTimeout);
}

Future<PastedAttachment?> _readFromDataReader(ClipboardDataReader reader) async {
  // 1. 优先图片检测
  for (final format in _imageFormats) {
    if (reader.hasValue(format)) {
      Uint8List? bytes;
      try {
        bytes = await reader.readValue(format);
      } catch (_) {
        bytes = null;
      }

      if ((bytes == null || bytes.isEmpty) && reader.isVirtual(format)) {
        bytes = await _readVirtualData(reader, format: format);
      }

      if (bytes != null && bytes.isNotEmpty) {
        String? suggestedName;
        try {
          suggestedName = await reader.getSuggestedName();
        } catch (_) {
          suggestedName = null;
        }
        final filename = _resolveImageFilename(suggestedName, format);
        return (bytes: bytes, filename: filename);
      }
    }
  }

  // 2. 其次文件 URI 检测
  if (reader.hasValue(Formats.fileUri)) {
    Uri? uri;
    try {
      uri = await reader.readValue(Formats.fileUri);
    } catch (_) {
      uri = null;
    }

    if (uri != null && uri.isScheme('file')) {
      try {
        final filePath = uri.toFilePath();
        final file = File(filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            String? suggestedName;
            try {
              suggestedName = await reader.getSuggestedName();
            } catch (_) {
              suggestedName = null;
            }
            final filename = (suggestedName != null && suggestedName.trim().isNotEmpty)
                ? suggestedName.trim()
                : (file.uri.pathSegments.isNotEmpty
                    ? file.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'attachment')
                    : 'attachment');
            return (bytes: bytes, filename: filename);
          }
        }
      } catch (_) {
        // 文件路径读取异常，走 virtual file 兜底
      }
    }
  }

  return null;
}

Future<PastedAttachment?> _readVirtualFallback(ClipboardDataReader reader) async {
  // 3. Virtual file 兜底（macOS/Windows 虚拟文件）
  try {
    final receiver = await reader.getVirtualFileReceiver();
    if (receiver != null) {
      final tempDir = await Directory.systemTemp.createTemp('hermes_paste_');
      try {
        final pair = receiver.receiveVirtualFile(targetFolder: tempDir.path);
        final filePath = await pair.first;
        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty) {
              String? suggestedName;
              try {
                suggestedName = await reader.getSuggestedName();
              } catch (_) {
                suggestedName = null;
              }
              final filename = (suggestedName != null && suggestedName.trim().isNotEmpty)
                  ? suggestedName.trim()
                  : (file.uri.pathSegments.isNotEmpty
                      ? file.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'attachment')
                      : 'attachment');
              return (bytes: bytes, filename: filename);
            }
          }
        }
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  } catch (_) {
    // 忽略 virtual receiver 错误
  }

  return null;
}

Future<Uint8List?> _readVirtualData(
  ClipboardDataReader reader, {
  VirtualFileFormat? format,
}) async {
  try {
    final receiver = await reader.getVirtualFileReceiver(format: format);
    if (receiver == null) return null;
    final tempDir = await Directory.systemTemp.createTemp('hermes_paste_');
    try {
      final pair = receiver.receiveVirtualFile(targetFolder: tempDir.path);
      final filePath = await pair.first;
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      }
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  } catch (_) {
    return null;
  }
  return null;
}

String _resolveImageFilename(
  String? suggestedName,
  SimpleDataFormat<Uint8List> format,
) {
  final ext = switch (format) {
    Formats.png => '.png',
    Formats.jpeg => '.jpg',
    Formats.gif => '.gif',
    Formats.webp => '.webp',
    Formats.tiff => '.tiff',
    _ => '.png',
  };

  if (suggestedName != null && suggestedName.trim().isNotEmpty) {
    final trimmed = suggestedName.trim();
    if (trimmed.contains('.')) {
      return trimmed;
    }
    return '$trimmed$ext';
  }
  return 'pasted_image$ext';
}
