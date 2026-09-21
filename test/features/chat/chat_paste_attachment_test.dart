import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/providers/clipboard_paste_provider.dart';
import 'package:hermes_ui/core/providers/file_picker_provider.dart';
import 'package:hermes_ui/core/utils/accessibility.dart';
import 'package:hermes_ui/core/utils/clipboard_paste.dart';
import 'package:hermes_ui/core/utils/file_picker.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/settings/perf_monitor_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_ui/features/chat/widgets/chat_input_bar.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';

import '../../helpers/fake_chat_api.dart';

final Uint8List kTransparentPngBytes = Uint8List.fromList([
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
  0x0A,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chat 输入框粘贴附件链路 Widget 测试', () {
    testWidgets('Ctrl+V 粘贴图片：uploadFile 进入待发附件条，不直接发送；点发送随消息提交', (
      tester,
    ) async {
      final chatApi = FakeChatApi();
      final pasteService = FakeClipboardPasteService(
        result: (bytes: kTransparentPngBytes, filename: 'screenshot.png'),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString(
          '{"ok":true,"filename":"screenshot.png","path":"/files/screenshot.png","is_image":true}',
          200,
        ),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      expect(inputFinder, findsOneWidget);

      // 聚焦输入框并触发粘贴意图
      await tester.tap(inputFinder);
      await tester.pump();

      Actions.invoke(
        tester.element(inputFinder),
        const PasteAttachmentIntent(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言 uploadFile 请求发出且参数正确
      final uploadReqs = adapter.requests.where((r) => r.uri.path == '/api/upload').toList();
      expect(uploadReqs.length, 1);
      final req = uploadReqs.first;
      expect(req.uri.path, '/api/upload');
      final bodyStr = utf8.decode(req.data as Uint8List, allowMalformed: true);
      expect(bodyStr, contains('name="session_id"\r\n\r\ns1'));
      expect(bodyStr, contains('filename="screenshot.png"'));

      // 不直接发送：无 startChat、无本地消息、无成功弹窗
      expect(chatApi.startChatCalls, 0);
      expect(find.text('📎 screenshot.png'), findsNothing);
      expect(find.text('上传成功'), findsNothing);

      // 待发附件条出现（缩略图 + 文件名）
      expect(
        find.byKey(const ValueKey('attachment-pending-list')),
        findsOneWidget,
      );
      expect(find.text('screenshot.png'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('attachment-clear-all')),
        findsNothing, // 单附件不显示清空按钮
      );

      // 发送按钮因附件可用
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));
      final sendWidget = tester.widget<AccessibleButton>(sendBtn);
      expect(sendWidget.onPressed, isNotNull);

      // 点发送 → startChat 一次：文本带附件引用，attachments 参数完整
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(chatApi.startChatCalls, 1);
      expect(chatApi.lastSentText, '[Attached files: /files/screenshot.png]');
      expect(chatApi.lastSentAttachments, isNotNull);
      expect(chatApi.lastSentAttachments!.length, 1);
      expect(chatApi.lastSentAttachments!.first['name'], 'screenshot.png');
      expect(
        chatApi.lastSentAttachments!.first['path'],
        '/files/screenshot.png',
      );
      expect(chatApi.lastSentAttachments!.first['is_image'], true);

      // 发送成功后附件条清空，附件转为消息气泡内卡片（对齐 WebUI 回显）
      await tester.pump();
      expect(
        find.byKey(const ValueKey('attachment-pending-list')),
        findsNothing,
      );
      expect(find.byType(ChatAttachmentChipView), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('PasteTextIntent 粘贴文件：入待发附件条，点发送一并提交（非图片走文档图标）', (
      tester,
    ) async {
      final chatApi = FakeChatApi();
      final pasteService = FakeClipboardPasteService(
        result: (
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          filename: 'document.pdf',
        ),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString(
          '{"ok":true,"filename":"document.pdf","path":"/files/document.pdf","is_image":false}',
          200,
        ),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.tap(inputFinder);
      await tester.pump();

      // 触发 PasteTextIntent（系统粘贴 / 右键菜单默认意图）
      Actions.invoke(
        tester.element(inputFinder),
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList().length, 1);
      expect(chatApi.startChatCalls, 0);
      expect(find.text('上传成功'), findsNothing);

      // 待发附件条中的文档项
      expect(
        find.byKey(const ValueKey('attachment-pending-list')),
        findsOneWidget,
      );
      expect(find.text('document.pdf'), findsOneWidget);

      // 点发送 → 带附件提交
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(chatApi.startChatCalls, 1);
      expect(chatApi.lastSentText, '[Attached files: /files/document.pdf]');
      expect(chatApi.lastSentAttachments!.length, 1);
      expect(chatApi.lastSentAttachments!.first['is_image'], false);

      await tester.pump();
      expect(
        find.byKey(const ValueKey('attachment-pending-list')),
        findsNothing,
      );
      expect(find.byType(ChatAttachmentChipView), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('纯文本粘贴放行：pasteService 返回 null 时插入文本到输入框，不发起上传', (tester) async {
      final chatApi = FakeChatApi();
      final pasteService = FakeClipboardPasteService(result: null);
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      // 预置系统剪贴板文本
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': 'Hello from clipboard!'};
          }
          return null;
        },
      );

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.tap(inputFinder);
      await tester.pump();

      // 触发 PasteAttachmentIntent
      Actions.invoke(
        tester.element(inputFinder),
        const PasteAttachmentIntent(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言没有调用 uploadFile
      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList(), isEmpty);
      expect(chatApi.startChatCalls, 0);

      // 断言输入框内文本为剪贴板文本
      final textField = tester.widget<CupertinoTextField>(inputFinder);
      expect(textField.controller?.text, 'Hello from clipboard!');

      // 断言发送按钮变为可用
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));
      final sendWidget = tester.widget<AccessibleButton>(sendBtn);
      expect(sendWidget.onPressed, isNotNull);

      await _unmount(tester);
    });

    testWidgets('粘贴上传失败路径：uploadFile 抛错 → 弹出失败提示对话框且包含 statusRedText 错误信息', (
      tester,
    ) async {
      final chatApi = FakeChatApi();
      final pasteService = FakeClipboardPasteService(
        result: (bytes: Uint8List.fromList([1, 2, 3]), filename: 'corrupt.png'),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"error":"上传超时"}', 500),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.tap(inputFinder);
      await tester.pump();

      Actions.invoke(
        tester.element(inputFinder),
        const PasteAttachmentIntent(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList().length, 1);
      expect(chatApi.startChatCalls, 0);

      // 断言失败弹窗
      expect(find.text('上传失败'), findsOneWidget);
      final errorFinder = find.text('服务器返回 HTTP 500。');
      expect(errorFinder, findsOneWidget);
      final errorWidget = tester.widget<Text>(errorFinder);
      expect(
        errorWidget.style?.color,
        statusRedText.resolveFrom(tester.element(find.byType(CupertinoApp))),
      );

      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _unmount(tester);
    });

    testWidgets('只读/禁用会话中忽略粘贴', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': const [],
          'is_read_only': true,
        },
      };
      final pasteService = FakeClipboardPasteService(
        result: (bytes: Uint8List.fromList([1, 2, 3]), filename: 'photo.png'),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      Actions.invoke(
        tester.element(inputFinder),
        const PasteAttachmentIntent(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList(), isEmpty);
      expect(chatApi.startChatCalls, 0);

      await _unmount(tester);
    });

    testWidgets('pasteService 抛出异常时容错放行：静默捕获异常并插入系统纯文本，不弹错误弹窗', (tester) async {
      final chatApi = FakeChatApi();
      // 模拟 super_clipboard 读取异常（例如 Windows 平台通道报错）
      final pasteService = FakeClipboardPasteService(
        error: PlatformException(
          code: 'UNAVAILABLE',
          message: 'Clipboard unavailable',
        ),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      // 预置系统剪贴板文本
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': 'Fallback plain text'};
          }
          return null;
        },
      );

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.tap(inputFinder);
      await tester.pump();

      Actions.invoke(
        tester.element(inputFinder),
        const PasteAttachmentIntent(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言没有发起上传，不弹错误弹窗
      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList(), isEmpty);
      expect(find.text('上传失败'), findsNothing);
      expect(find.text('选择文件失败'), findsNothing);

      // 断言纯文本成功插入
      final textField = tester.widget<CupertinoTextField>(inputFinder);
      expect(textField.controller?.text, 'Fallback plain text');

      await _unmount(tester);
    });

    testWidgets('pasteService 返回空 bytes 时放行纯文本：不发起上传，插入系统纯文本，不弹错误弹窗', (
      tester,
    ) async {
      final chatApi = FakeChatApi();
      // 模拟异常返回空 bytes 附件
      final pasteService = FakeClipboardPasteService(
        result: (bytes: Uint8List(0), filename: 'empty.png'),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': 'Plain text when attachment empty'};
          }
          return null;
        },
      );

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.tap(inputFinder);
      await tester.pump();

      Actions.invoke(
        tester.element(inputFinder),
        const PasteAttachmentIntent(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList(), isEmpty);
      expect(find.text('上传失败'), findsNothing);

      final textField = tester.widget<CupertinoTextField>(inputFinder);
      expect(textField.controller?.text, 'Plain text when attachment empty');

      await _unmount(tester);
    });

    testWidgets('纯文本粘贴选区替换与光标位置保持：替换选中部分并移动光标至末尾，更新 hasText', (tester) async {
      final chatApi = FakeChatApi();
      final pasteService = FakeClipboardPasteService(result: null);
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': 'Hermex'};
          }
          return null;
        },
      );

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.tap(inputFinder);
      await tester.pump();

      // 预先输入文本并选中部分
      final textField = tester.widget<CupertinoTextField>(inputFinder);
      textField.controller!.value = const TextEditingValue(
        text: 'Hello World',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();

      Actions.invoke(
        tester.element(inputFinder),
        const PasteAttachmentIntent(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(textField.controller?.text, 'Hello Hermex');
      expect(
        textField.controller?.selection,
        const TextSelection.collapsed(offset: 12),
      );

      // 发送按钮可用
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));
      final sendWidget = tester.widget<AccessibleButton>(sendBtn);
      expect(sendWidget.onPressed, isNotNull);

      await _unmount(tester);
    });

    testWidgets('剪贴板为空或异常时静默放行：不弹错、不 crash', (tester) async {
      final chatApi = FakeChatApi();
      final pasteService = FakeClipboardPasteService(result: null);
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      // 剪贴板为空
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return null;
          }
          return null;
        },
      );

      await _pumpPage(
        tester,
        chatApi: chatApi,
        pasteService: pasteService,
        apiClient: client,
      );

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.tap(inputFinder);
      await tester.pump();

      Actions.invoke(
        tester.element(inputFinder),
        const PasteAttachmentIntent(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList(), isEmpty);
      expect(find.text('上传失败'), findsNothing);
      expect(find.text('选择文件失败'), findsNothing);

      final textField = tester.widget<CupertinoTextField>(inputFinder);
      expect(textField.controller?.text, '');

      await _unmount(tester);
    });

    testWidgets(
      'Android：粘贴不再进入 super_clipboard FFI（不触碰 pasteboard 通道），纯文本照常插入',
      (tester) async {
        // 注意：widget 测试的 `_verifyInvariants` 在**测试体结束前**就校验
        // foundation debug 变量是否复位（addTearDown 太晚，实测报
        // "The value of a foundation debug variable was changed by the test"），
        // 故必须 try/finally 就地复位。
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final chatApi = FakeChatApi();
          final adapter = _RecordingAdapter(
            responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
          );
          final client = _buildClient(adapter);

          // 用**真实生产服务**（不注入 fake）：这条要验的正是修复后的真实路径。
          var pasteboardCalls = 0;
          const pasteboardChannel = MethodChannel('pasteboard');
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(pasteboardChannel, (call) async {
            pasteboardCalls++;
            return null;
          });
          addTearDown(
            () => messenger.setMockMethodCallHandler(pasteboardChannel, null),
          );

          // 预置系统剪贴板纯文本
          messenger.setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall methodCall,
          ) async {
            if (methodCall.method == 'Clipboard.getData') {
              return {'text': 'Android plain text'};
            }
            return null;
          });

          await _pumpPage(
            tester,
            chatApi: chatApi,
            pasteService: const PlatformClipboardPasteService(),
            apiClient: client,
          );

          final inputFinder = find.byKey(const ValueKey('chat-input-field'));
          await tester.tap(inputFinder);
          await tester.pump();

          Actions.invoke(
            tester.element(inputFinder),
            const PasteAttachmentIntent(),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          // 宿主平台是 Windows：若移动端短路失效，这里必然命中 pasteboard 通道
          // （`Pasteboard.image` + `Pasteboard.files`）。真机上同一条路就是闪退。
          expect(pasteboardCalls, 0, reason: '移动端必须完全不进入 pasteboard 分支');
          expect(
            adapter.requests.where((r) => r.uri.path == '/api/upload').toList(),
            isEmpty,
          );
          final textField = tester.widget<CupertinoTextField>(inputFinder);
          expect(textField.controller?.text, 'Android plain text');

          await _unmount(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required FakeChatApi chatApi,
  required ClipboardPasteService pasteService,
  required ApiClient apiClient,
}) async {
  SharedPreferences.setMockInitialValues({kShowPerfMonitorKey: false});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        filePickerServiceProvider.overrideWithValue(FakeFilePickerService()),
        clipboardPasteServiceProvider.overrideWithValue(pasteService),
        apiClientProvider.overrideWithValue(apiClient),
      ],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

ApiClient _buildClient(_RecordingAdapter adapter) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = adapter;
  final publicDio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  publicDio.httpClientAdapter = adapter;
  return ApiClient(
    baseUrl: 'http://test.local:30002',
    dio: dio,
    publicMediaDio: publicDio,
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.responder});

  final ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}
