import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hermes_ui/core/api/api_client.dart';

/// 演示 / 测试用：返回固定系统指标（CPU / 内存 / 磁盘）的 [ApiClient]。
///
/// 用途：让「性能监控面板」在**截图工装**里拿到数据 —— 面板在没有数据时整体
/// 不占位（`SizedBox.shrink`），演示图里就完全看不到它，也就看不出宽屏下
/// 「左三 + 仪表盘 + chip」那一排的真实观感。
///
/// 实现口径：`ApiClient.systemHealth()` 是 extension，靠子类覆写行不通 ⇒
/// 用 Dio 的 `HttpClientAdapter` 注入固定响应体（与本仓既有测试同法）。
ApiClient buildSystemHealthApiClient({
  String baseUrl = 'http://demo.local:30002',
  double cpu = 42,
  double mem = 58,
  double disk = 71,
  int usedBytes = 148000000000,
  int totalBytes = 256000000000,
}) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = _SystemHealthAdapter(
    cpu: cpu,
    mem: mem,
    disk: disk,
    usedBytes: usedBytes,
    totalBytes: totalBytes,
  );
  return ApiClient(baseUrl: baseUrl, dio: dio);
}

class _SystemHealthAdapter implements HttpClientAdapter {
  _SystemHealthAdapter({
    required this.cpu,
    required this.mem,
    required this.disk,
    required this.usedBytes,
    required this.totalBytes,
  });

  final double cpu;
  final double mem;
  final double disk;
  final int usedBytes;
  final int totalBytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/api/system/health') {
      return ResponseBody.fromString(
        jsonEncode({
          'status': 'ok',
          'available': true,
          'checked_at': '2026-09-27T00:00:00Z',
          'cpu': {'percent': cpu},
          'memory': {
            'percent': mem,
            'used_bytes': usedBytes,
            'total_bytes': totalBytes,
          },
          'disk': {
            'percent': disk,
            'used_bytes': usedBytes,
            'total_bytes': totalBytes,
          },
          'errors': <String>[],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}
