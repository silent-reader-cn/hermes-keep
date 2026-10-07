import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/providers/file_picker_provider.dart';
import 'package:hermes_ui/core/utils/accessibility.dart';
import 'package:hermes_ui/core/utils/file_picker.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/settings/perf_monitor_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('Chat 附件上传链路 Widget 测试', () {
    testWidgets('成功路径：选择文件 → uploadFile → 入待发附件条（不直接发送）；点发送随消息提交', (
      tester,
    ) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(
        result: FilePickerResult(
          name: 'report.pdf',
          bytes: Uint8List.fromList([10, 20, 30]),
        ),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString(
          '{"ok":true,"filename":"report.pdf","path":"/files/report.pdf","is_image":false}',
          200,
        ),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      expect(find.byKey(const ValueKey('chat-attach-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言 uploadFile 真实请求被发出且参数正确（过滤掉性能监控的 systemHealth 轮询）
      final uploadReqs = adapter.requests.where((r) => r.uri.path == '/api/upload').toList();
      expect(uploadReqs.length, 1);
      final req = uploadReqs.first;
      expect(req.uri.path, '/api/upload');
      final bodyStr = utf8.decode(req.data as Uint8List, allowMalformed: true);
      expect(bodyStr, contains('name="session_id"\r\n\r\ns1'));
      expect(bodyStr, contains('filename="report.pdf"'));

      // 不直接发送：无 startChat、无本地消息、无成功弹窗
      expect(chatApi.startChatCalls, 0);
      expect(find.text('📎 report.pdf'), findsNothing);
      expect(find.text('上传成功'), findsNothing);

      // 待发附件条出现（文档项）
      expect(
        find.byKey(const ValueKey('attachment-pending-list')),
        findsOneWidget,
      );
      expect(find.text('report.pdf'), findsOneWidget);

      // 发送按钮因附件可用
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));
      final sendWidget = tester.widget<AccessibleButton>(sendBtn);
      expect(sendWidget.onPressed, isNotNull);

      // 点发送 → 带附件提交，之后附件条清空
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(chatApi.startChatCalls, 1);
      expect(chatApi.lastSentText, '[Attached files: /files/report.pdf]');
      expect(chatApi.lastSentAttachments, isNotNull);
      expect(chatApi.lastSentAttachments!.length, 1);
      expect(chatApi.lastSentAttachments!.first['name'], 'report.pdf');
      expect(chatApi.lastSentAttachments!.first['path'], '/files/report.pdf');

      await tester.pump();
      expect(
        find.byKey(const ValueKey('attachment-pending-list')),
        findsNothing,
      );
      // 用户气泡附件区改为「宫格 + 文件行条」，用稳定 key 断言。
      expect(
        find.byKey(const ValueKey('user-attachment-file-report.pdf')),
        findsOneWidget,
      );

      await _unmount(tester);
    });

    testWidgets('取消路径：picker 返回 null → 无上传调用、无对话框', (tester) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(result: null);
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言未调用 uploadFile，也未发送聊天消息（过滤 systemHealth）
      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList(), isEmpty);
      expect(chatApi.startChatCalls, 0);

      // 断言无任何弹窗出现
      expect(find.byType(CupertinoAlertDialog), findsNothing);

      await _unmount(tester);
    });

    testWidgets('上传失败路径：uploadFile 抛错 → 失败对话框出现且包含错误信息与 statusRedText 样式', (
      tester,
    ) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(
        result: FilePickerResult(
          name: 'large_image.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"error":"服务器内部错误"}', 500),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言请求发出但 chat 未发送本地消息
      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').length, 1);
      expect(chatApi.startChatCalls, 0);

      // 断言失败对话框展示，且内容文字为 statusRedText 的解析色（已 resolve，深浅色均达标）
      expect(find.text('上传失败'), findsOneWidget);
      final errorFinder = find.text('服务器返回 HTTP 500。');
      expect(errorFinder, findsOneWidget);
      final errorWidget = tester.widget<Text>(errorFinder);
      expect(
        errorWidget.style?.color,
        statusRedText.resolveFrom(tester.element(find.byType(CupertinoApp))),
      );

      // 关闭弹窗
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('上传失败'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('选择失败路径：picker 抛异常 → 选择失败对话框出现且内容为 statusRedText', (
      tester,
    ) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(error: Exception('访问相册权限被拒绝'));
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言未调用 uploadFile，也未发送消息（过滤 systemHealth）
      expect(adapter.requests.where((r) => r.uri.path == '/api/upload').toList(), isEmpty);
      expect(chatApi.startChatCalls, 0);

      // 断言选择失败对话框展示（解析色已 resolve）
      expect(find.text('选择文件失败'), findsOneWidget);
      final errorFinder = find.textContaining('访问相册权限被拒绝');
      expect(errorFinder, findsOneWidget);
      final errorWidget = tester.widget<Text>(errorFinder);
      expect(
        errorWidget.style?.color,
        statusRedText.resolveFrom(tester.element(find.byType(CupertinoApp))),
      );

      // 关闭弹窗
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('选择文件失败'), findsNothing);

      await _unmount(tester);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeChatApi chatApi,
  required FilePickerService filePicker,
  required ApiClient apiClient,
}) async {
  SharedPreferences.setMockInitialValues({kShowPerfMonitorKey: false});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        filePickerServiceProvider.overrideWithValue(filePicker),
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

typedef _FakeChatApi = FakeChatApi;
