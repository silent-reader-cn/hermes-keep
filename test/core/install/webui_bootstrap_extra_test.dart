import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/webui_bootstrap.dart';

/// 目标缺口（lcov 实测，基线 16/33）：
///   14-15   ─ WebuiBootstrapException.toString
///   27-45   ─ SystemHealthChecker.checkHealth 全量
///   87-93   ─ resolvePythonPath 的 alt venv / PATH 降级分支
///   117-118 ─ webuiBootstrapProvider

/// 回环测试服务器：只绑定 127.0.0.1 临时端口，不访问外网。
class _LoopbackServer {
  _LoopbackServer._(this._server);

  static Future<_LoopbackServer> start({int status = 200, String body = '{}'}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _LoopbackServer._(server);
    instance.status = status;
    instance.body = body;
    unawaited(instance._serve());
    return instance;
  }

  final HttpServer _server;
  int status = 200;
  String body = '{}';

  final List<String> paths = <String>[];

  int get port => _server.port;

  String get baseUrl => 'http://127.0.0.1:$port';

  Future<void> _serve() async {
    try {
      await for (final request in _server) {
        paths.add(request.uri.path);
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(body);
        await request.response.close();
      }
    } catch (_) {
      // close(force: true) 会中断 await for：静默收尾。
    }
  }

  Future<void> close() => _server.close(force: true);
}

Future<int> _reserveClosedPort() async {
  final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close(force: true);
  return port;
}

class _FakeFileSystemAdapter implements FileSystemAdapter {
  _FakeFileSystemAdapter({
    this.existingFiles = const <String>{},
    this.localAppData = r'C:\Users\Admin\AppData\Local',
    this.isWindows = true,
  });

  final Set<String> existingFiles;

  @override
  String localAppData;

  @override
  bool isWindows;

  @override
  String executablePath = r'C:\Program Files\Hermes\hermes.exe';

  @override
  bool directoryExists(String path) => false;

  @override
  bool fileExists(String path) => existingFiles.contains(path);

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  Future<String> readString(String path) async => '';

  @override
  Future<void> writeString(String path, String content) async {}
}

class _RecordingHealthChecker implements HealthChecker {
  _RecordingHealthChecker(this.result);

  final bool result;
  final List<String> urls = <String>[];

  @override
  Future<bool> checkHealth(String url) async {
    urls.add(url);
    return result;
  }
}

void main() {
  group('WebuiBootstrapException', () {
    test('toString 带可读前缀与原始消息', () {
      const error = WebuiBootstrapException('WebUI 服务未就绪');

      expect(error.message, 'WebUI 服务未就绪');
      expect(error.toString(), 'WebuiBootstrapException: WebUI 服务未就绪');
      expect(error, isA<Exception>());
    });

    test('空消息也保持前缀结构', () {
      expect(
        const WebuiBootstrapException('').toString(),
        'WebuiBootstrapException: ',
      );
    });
  });

  group('SystemHealthChecker.checkHealth（生产默认健康检查器）', () {
    test('200 且 {"status":"ok"} → true，请求路径为 /health', () async {
      final server = await _LoopbackServer.start(
        status: 200,
        body: '{"status": "ok"}',
      );
      addTearDown(server.close);
      const checker = SystemHealthChecker();

      final ok = await checker.checkHealth('${server.baseUrl}/health');

      expect(ok, isTrue);
      expect(server.paths.single, '/health');
    });

    test('200 且附带额外字段 → 仍判健康', () async {
      final server = await _LoopbackServer.start(
        status: 200,
        body: '{"status": "ok", "build": "0.1.50", "agents": 2}',
      );
      addTearDown(server.close);
      const checker = SystemHealthChecker();

      expect(await checker.checkHealth('${server.baseUrl}/health'), isTrue);
    });

    test('200 但 status != "ok" → false', () async {
      final server = await _LoopbackServer.start(
        status: 200,
        body: '{"status": "degraded"}',
      );
      addTearDown(server.close);
      const checker = SystemHealthChecker();

      expect(await checker.checkHealth('${server.baseUrl}/health'), isFalse);
    });

    test('200 但 status 大小写不符 "OK" → false（区分大小写）', () async {
      final server = await _LoopbackServer.start(
        status: 200,
        body: '{"status": "OK"}',
      );
      addTearDown(server.close);
      const checker = SystemHealthChecker();

      expect(await checker.checkHealth('${server.baseUrl}/health'), isFalse);
    });

    test('200 但响应体是 JSON 数组（非 Map）→ false', () async {
      final server = await _LoopbackServer.start(status: 200, body: '[1, 2, 3]');
      addTearDown(server.close);
      const checker = SystemHealthChecker();

      expect(await checker.checkHealth('${server.baseUrl}/health'), isFalse);
    });

    test('200 但响应体非 JSON → 解析异常被吞，返回 false', () async {
      final server = await _LoopbackServer.start(
        status: 200,
        body: 'not-json-at-all',
      );
      addTearDown(server.close);
      const checker = SystemHealthChecker();

      expect(await checker.checkHealth('${server.baseUrl}/health'), isFalse);
    });

    test('非 200（404 / 500）→ false，且不读取响应体', () async {
      final server = await _LoopbackServer.start(
        status: 404,
        body: '{"status": "ok"}',
      );
      addTearDown(server.close);
      const checker = SystemHealthChecker();

      expect(await checker.checkHealth('${server.baseUrl}/health'), isFalse);

      server.status = 500;
      expect(await checker.checkHealth('${server.baseUrl}/health'), isFalse);
      expect(server.paths, hasLength(2));
    });

    test('端口无人监听 → 连接异常被吞，返回 false', () async {
      final deadPort = await _reserveClosedPort();
      const checker = SystemHealthChecker();

      expect(
        await checker.checkHealth('http://127.0.0.1:$deadPort/health'),
        isFalse,
      );
    });

    test('URL 语法非法 → 构造请求抛错被吞，返回 false', () async {
      const checker = SystemHealthChecker();

      expect(await checker.checkHealth('http://['), isFalse);
    });
  });

  group('DefaultWebuiBootstrap.resolvePythonPath 回退链', () {
    test('两级 venv 同时存在 → agent venv 优先', () {
      final fs = _FakeFileSystemAdapter(
        existingFiles: <String>{
          r'C:\Users\Admin\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe',
          r'C:\Users\Admin\AppData\Local\hermes\venv\Scripts\python.exe',
        },
      );

      expect(
        DefaultWebuiBootstrap(fileSystem: fs).resolvePythonPath(),
        r'C:\Users\Admin\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe',
      );
    });

    test('agent venv 缺失、统一 venv 存在 → 返回统一 venv python', () {
      final fs = _FakeFileSystemAdapter(
        existingFiles: <String>{
          r'C:\Users\Admin\AppData\Local\hermes\venv\Scripts\python.exe',
        },
      );

      expect(
        DefaultWebuiBootstrap(fileSystem: fs).resolvePythonPath(),
        r'C:\Users\Admin\AppData\Local\hermes\venv\Scripts\python.exe',
      );
    });

    test('两级 venv 都不存在 → 降级 PATH：Windows 用 python.exe', () {
      final fs = _FakeFileSystemAdapter(isWindows: true);

      expect(DefaultWebuiBootstrap(fileSystem: fs).resolvePythonPath(), 'python.exe');
    });

    test('两级 venv 都不存在 → 降级 PATH：非 Windows 用 python', () {
      final fs = _FakeFileSystemAdapter(isWindows: false);

      expect(DefaultWebuiBootstrap(fileSystem: fs).resolvePythonPath(), 'python');
    });

    test('localAppData 为空 → 跳过 venv 探测，直接降级 PATH', () {
      final fs = _FakeFileSystemAdapter(localAppData: '', isWindows: true);

      expect(DefaultWebuiBootstrap(fileSystem: fs).resolvePythonPath(), 'python.exe');
    });

    test('近似路径反例：venv 目录下 python（无 .exe）不被识别', () {
      final fs = _FakeFileSystemAdapter(
        existingFiles: <String>{
          r'C:\Users\Admin\AppData\Local\hermes\hermes-agent\venv\Scripts\python',
        },
      );

      expect(DefaultWebuiBootstrap(fileSystem: fs).resolvePythonPath(), 'python.exe');
    });
  });

  group('DefaultWebuiBootstrap.waitForHealth URL 拼装', () {
    test('baseUrl 无尾斜杠 → 补 /health', () async {
      final checker = _RecordingHealthChecker(true);
      final bootstrap = DefaultWebuiBootstrap(healthChecker: checker);

      await bootstrap.waitForHealth(
        baseUrl: 'http://127.0.0.1:8787',
        timeout: const Duration(seconds: 1),
        interval: const Duration(milliseconds: 5),
      );

      expect(checker.urls.single, 'http://127.0.0.1:8787/health');
    });

    test('baseUrl 已带尾斜杠 → 不重复加斜杠', () async {
      final checker = _RecordingHealthChecker(true);
      final bootstrap = DefaultWebuiBootstrap(healthChecker: checker);

      await bootstrap.waitForHealth(
        baseUrl: 'http://127.0.0.1:8787/',
        timeout: const Duration(seconds: 1),
        interval: const Duration(milliseconds: 5),
      );

      expect(checker.urls.single, 'http://127.0.0.1:8787/health');
    });

    test('超时异常携带超时秒数', () async {
      final checker = _RecordingHealthChecker(false);
      final bootstrap = DefaultWebuiBootstrap(healthChecker: checker);

      await expectLater(
        bootstrap.waitForHealth(
          baseUrl: 'http://127.0.0.1:8787',
          timeout: const Duration(milliseconds: 60),
          interval: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<WebuiBootstrapException>()
              .having((e) => e.message, 'message', contains('秒内就绪')),
        ),
      );
      expect(checker.urls, isNotEmpty);
    });

    test('接口默认端口常量保持 8787', () {
      expect(WebuiBootstrap.defaultPort, 8787);
    });
  });

  group('webuiBootstrapProvider', () {
    test('默认 build → DefaultWebuiBootstrap', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(webuiBootstrapProvider),
        isA<DefaultWebuiBootstrap>(),
      );
    });

    test('override 注入 fake 后 read 返回注入实例', () {
      final fake = _StubWebuiBootstrap();
      final container = ProviderContainer(
        overrides: [webuiBootstrapProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(webuiBootstrapProvider), same(fake));
    });
  });
}

class _StubWebuiBootstrap implements WebuiBootstrap {
  @override
  String resolvePythonPath() => 'stub-python';

  @override
  Future<bool> waitForHealth({
    String baseUrl = 'http://127.0.0.1:8787',
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 500),
  }) async =>
      false;
}
