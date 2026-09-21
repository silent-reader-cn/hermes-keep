import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/utils/clipboard_paste.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_clipboard/super_clipboard.dart';

class MockVirtualFileReceiver extends Mock implements VirtualFileReceiver {}

class FakeReadProgress implements ReadProgress {
  @override
  ValueListenable<bool> get cancellable => ValueNotifier(false);

  @override
  ValueListenable<double?> get fraction => ValueNotifier(1.0);

  @override
  void cancel() {}
}

class FakeClipboardDataReader extends ClipboardDataReader {
  FakeClipboardDataReader({
    this.values = const {},
    this.virtualFormats = const {},
    this.suggestedName,
    this.virtualFileReceiver,
    this.throwsError = false,
  });

  final Map<DataFormat, Object?> values;
  final Set<DataFormat> virtualFormats;
  final String? suggestedName;
  final VirtualFileReceiver? virtualFileReceiver;
  final bool throwsError;

  @override
  bool hasValue(DataFormat format) {
    if (throwsError) throw Exception('Simulated clipboard error');
    return values.containsKey(format) || virtualFormats.contains(format);
  }

  @override
  Future<T?> readValue<T extends Object>(DataFormat<T> format) async {
    if (throwsError) throw Exception('Simulated read error');
    return values[format] as T?;
  }

  @override
  bool isVirtual(DataFormat<Object> format) {
    return virtualFormats.contains(format);
  }

  @override
  Future<String?> getSuggestedName() async {
    return suggestedName;
  }

  @override
  Future<VirtualFileReceiver?> getVirtualFileReceiver({
    VirtualFileFormat? format,
  }) async {
    return virtualFileReceiver;
  }

  @override
  List<DataFormat> getFormats(List<DataFormat> allFormats) {
    return allFormats.where(hasValue).toList();
  }

  @override
  ReadProgress? getValue<T extends Object>(
    DataFormat<T> format,
    ValueChanged<DataReaderValue<T>> onValue,
  ) {
    onValue(DataReaderValue(value: values[format] as T?));
    return null;
  }

  @override
  bool isSynthetized(DataFormat<Object> format) => false;
}

void main() {
  // 本文件有一条测试要 mock MethodChannel（断言 pasteboard 通道零调用），
  // 该能力依赖已初始化的测试 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardPaste 工具与服务单测', () {
    test('图片优先：包含 PNG 图片时读取 bytes 并生成正确文件名', () async {
      final pngBytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      final reader = FakeClipboardDataReader(
        values: {
          Formats.png: pngBytes,
          Formats.plainText: 'Ignored text description',
        },
        suggestedName: 'screenshot',
      );

      final result = await readPastedAttachment(customReader: reader);

      expect(result, isNotNull);
      expect(result!.bytes, pngBytes);
      expect(result.filename, 'screenshot.png');
    });

    test('图片优先：无 suggestedName 时回退为 pasted_image.png', () async {
      final pngBytes = Uint8List.fromList([137, 80, 78, 71]);
      final reader = FakeClipboardDataReader(
        values: {Formats.png: pngBytes},
      );

      final result = await readPastedAttachment(customReader: reader);

      expect(result, isNotNull);
      expect(result!.bytes, pngBytes);
      expect(result.filename, 'pasted_image.png');
    });

    test('图片格式适配：JPEG / GIF / WEBP / TIFF', () async {
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
      final jpegReader = FakeClipboardDataReader(
        values: {Formats.jpeg: jpegBytes},
        suggestedName: 'photo.jpg',
      );
      final jpegRes = await readPastedAttachment(customReader: jpegReader);
      expect(jpegRes?.filename, 'photo.jpg');
      expect(jpegRes?.bytes, jpegBytes);

      final gifBytes = Uint8List.fromList([0x47, 0x49, 0x46]);
      final gifReader = FakeClipboardDataReader(
        values: {Formats.gif: gifBytes},
      );
      final gifRes = await readPastedAttachment(customReader: gifReader);
      expect(gifRes?.filename, 'pasted_image.gif');

      final webpBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);
      final webpReader = FakeClipboardDataReader(
        values: {Formats.webp: webpBytes},
      );
      final webpRes = await readPastedAttachment(customReader: webpReader);
      expect(webpRes?.filename, 'pasted_image.webp');
    });

    test('文件 URI 解析：解析 file:// 本地文件并读取 bytes + 文件名', () async {
      final tempDir = await Directory.systemTemp.createTemp('hermex_test_paste_');
      final tempFile = File('${tempDir.path}/test_document.pdf');
      await tempFile.writeAsBytes([1, 2, 3, 4, 5]);

      try {
        final reader = FakeClipboardDataReader(
          values: {
            Formats.fileUri: tempFile.uri,
          },
        );

        final result = await readPastedAttachment(customReader: reader);

        expect(result, isNotNull);
        expect(result!.bytes, Uint8List.fromList([1, 2, 3, 4, 5]));
        expect(result.filename, 'test_document.pdf');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Virtual file 兜底：直接 readValue 为空时通过 VirtualFileReceiver 读取', () async {
      final tempDir = await Directory.systemTemp.createTemp('hermex_test_virt_');
      final virtFile = File('${tempDir.path}/virtual_photo.png');
      final expectedBytes = Uint8List.fromList([9, 8, 7, 6]);
      await virtFile.writeAsBytes(expectedBytes);

      try {
        final mockReceiver = MockVirtualFileReceiver();
        when(() => mockReceiver.receiveVirtualFile(targetFolder: any(named: 'targetFolder'))).thenAnswer(
          (invocation) => Pair(Future.value(virtFile.path), FakeReadProgress()),
        );

        final reader = FakeClipboardDataReader(
          values: {Formats.png: null},
          virtualFormats: {Formats.png},
          suggestedName: 'virtual_photo.png',
          virtualFileReceiver: mockReceiver,
        );

        final result = await readPastedAttachment(customReader: reader);

        expect(result, isNotNull);
        expect(result!.bytes, expectedBytes);
        expect(result.filename, 'virtual_photo.png');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('仅文本时返回 null（放行系统文本粘贴）', () async {
      final reader = FakeClipboardDataReader(
        values: {
          Formats.plainText: 'Hello world',
          Formats.htmlText: '<p>Hello world</p>',
        },
      );

      final result = await readPastedAttachment(customReader: reader);
      expect(result, isNull);
    });

    test('剪贴板为空时返回 null', () async {
      final reader = FakeClipboardDataReader(values: {});
      final result = await readPastedAttachment(customReader: reader);
      expect(result, isNull);
    });

    test('异常发生时容错返回 null，不抛出 crash', () async {
      final reader = FakeClipboardDataReader(throwsError: true);
      final result = await readPastedAttachment(customReader: reader);
      expect(result, isNull);
    });

    test('图片或文件读取为空 bytes 时返回 null', () async {
      final reader = FakeClipboardDataReader(
        values: {
          Formats.png: Uint8List(0),
        },
      );
      final result = await readPastedAttachment(customReader: reader);
      expect(result, isNull);
    });

    test('FakeClipboardPasteService / PlatformClipboardPasteService 行为', () async {
      final fake = FakeClipboardPasteService(
        result: (bytes: Uint8List.fromList([1, 2]), filename: 'fake.png'),
      );
      final fakeRes = await fake.readPastedAttachment();
      expect(fakeRes?.filename, 'fake.png');

      final fakeError = FakeClipboardPasteService(error: Exception('Failed'));
      expect(() => fakeError.readPastedAttachment(), throwsException);

      final platform = PlatformClipboardPasteService(
        customReader: FakeClipboardDataReader(
          values: {Formats.png: Uint8List.fromList([42])},
        ),
      );
      final platformRes = await platform.readPastedAttachment();
      expect(platformRes?.bytes, Uint8List.fromList([42]));
    });

    group('移动端 FFI 探测摘除（点粘贴闪退止血 · A 案）', () {
      tearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });

      test('判据：移动端一律不走 super_clipboard FFI', () {
        expect(nativeFfiPasteProbeEnabled(TargetPlatform.android), isFalse);
        expect(nativeFfiPasteProbeEnabled(TargetPlatform.iOS), isFalse);
        expect(nativeFfiPasteProbeEnabled(TargetPlatform.fuchsia), isFalse);
      });

      test('判据：桌面端保留 FFI 探测（Windows 另有 pasteboard 分支先接管）', () {
        expect(nativeFfiPasteProbeEnabled(TargetPlatform.windows), isTrue);
        expect(nativeFfiPasteProbeEnabled(TargetPlatform.linux), isTrue);
        expect(nativeFfiPasteProbeEnabled(TargetPlatform.macOS), isTrue);
      });

      test('Android：短路优先于 Windows 分支（不触碰 pasteboard 通道）', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        var pasteboardCalls = 0;
        const channel = MethodChannel('pasteboard');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          pasteboardCalls++;
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        // 测试宿主是 Windows，故 dart:io 的 `Platform.isWindows` 恒为 true：
        // 若移动端短路没排在 pasteboard 分支之前，这里至少命中 `image` / `files`
        // 的通道调用。断言调用数为 0 **与宿主剪贴板内容无关**，是可确定判红的
        // 守卫（只断言返回 null 会在宿主剪贴板为空时假绿 —— 实测已踩过）。
        final result = await readPastedAttachment();

        expect(pasteboardCalls, 0, reason: '移动端必须完全不进入 pasteboard 分支');
        expect(result, isNull);
      });

      test('Android：注入 reader 的测试短路径不受影响（附件仍可解析）', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final bytes = Uint8List.fromList([1, 2, 3]);
        final reader = FakeClipboardDataReader(values: {Formats.png: bytes});
        final result = await readPastedAttachment(customReader: reader);
        expect(result?.bytes, bytes);
      });

      test('Android：生产服务对象同样恒 null（PlatformClipboardPasteService）', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        const service = PlatformClipboardPasteService();
        expect(await service.readPastedAttachment(), isNull);
      });
    });
  });
}
