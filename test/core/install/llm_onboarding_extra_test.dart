import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/llm_onboarding.dart';

/// 目标缺口（lcov 实测，基线 8/23）：120-151 —— `DefaultLlmOnboardingApi.saveConfig`
/// 全量 + `llmOnboardingApiProvider`。
///
/// `saveConfig` 内部直接 new HttpClient（无可注入接缝），因此用**本地回环 HTTP 服务器**
/// 打通真实链路：只绑定 127.0.0.1 临时端口，不访问外网、不依赖外部服务。

/// 回环测试服务器：记录请求，按 responder 回包。
class _LoopbackServer {
  _LoopbackServer._(this._server, this._responder);

  static Future<_LoopbackServer> start(
    Future<void> Function(HttpRequest request) responder,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _LoopbackServer._(server, responder);
    unawaited(instance._serve());
    return instance;
  }

  final HttpServer _server;
  final Future<void> Function(HttpRequest request) _responder;

  final List<String> methods = <String>[];
  final List<String> paths = <String>[];
  final List<String> bodies = <String>[];
  final List<String?> contentTypes = <String?>[];

  int get port => _server.port;

  String get baseUrl => 'http://127.0.0.1:$port';

  int get requestCount => paths.length;

  Future<void> _serve() async {
    try {
      await for (final request in _server) {
        methods.add(request.method);
        paths.add(request.uri.path);
        contentTypes.add(request.headers.contentType?.mimeType);
        bodies.add(await utf8.decoder.bind(request).join());
        try {
          await _responder(request);
        } catch (_) {
          // 客户端提前断开等边缘情况：忽略，不影响被测逻辑。
        }
      }
    } catch (_) {
      // close(force: true) 会中断 await for：静默收尾。
    }
  }

  Future<void> close() => _server.close(force: true);
}

Future<void> _respond(HttpRequest request, int status, String body) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(body);
  await request.response.close();
}

/// 占一个临时端口后立刻释放 —— 用于构造「连接被拒绝」的确定性场景。
Future<int> _reserveClosedPort() async {
  final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close(force: true);
  return port;
}

const LlmOnboardingConfig _config = LlmOnboardingConfig(
  provider: 'openrouter',
  apiKey: 'sk-or-v1-cov',
  baseUrl: 'https://openrouter.ai/api/v1',
  model: 'anthropic/claude-3.5-sonnet',
);

void main() {
  group('DefaultLlmOnboardingApi.saveConfig', () {
    test('200 → true，且以 POST + application/json 打 /api/onboarding', () async {
      final server = await _LoopbackServer.start(
        (request) => _respond(request, 200, '{"ok":true}'),
      );
      addTearDown(server.close);

      final ok = await const DefaultLlmOnboardingApi()
          .saveConfig(serverBaseUrl: server.baseUrl, config: _config);

      expect(ok, isTrue);
      expect(server.requestCount, 1);
      expect(server.methods.single, 'POST');
      expect(server.paths.single, '/api/onboarding');
      expect(server.contentTypes.single, 'application/json');
      expect(jsonDecode(server.bodies.single), <String, dynamic>{
        'provider': 'openrouter',
        'api_key': 'sk-or-v1-cov',
        'base_url': 'https://openrouter.ai/api/v1',
        'model': 'anthropic/claude-3.5-sonnet',
      });
    });

    test('仅 provider 的最小配置：空 apiKey/baseUrl/model 不进入请求体', () async {
      final server = await _LoopbackServer.start(
        (request) => _respond(request, 200, '{"ok":true}'),
      );
      addTearDown(server.close);

      final ok = await const DefaultLlmOnboardingApi().saveConfig(
        serverBaseUrl: server.baseUrl,
        config: const LlmOnboardingConfig(
          provider: 'ollama',
          apiKey: '',
          baseUrl: '',
          model: '',
        ),
      );

      expect(ok, isTrue);
      expect(jsonDecode(server.bodies.single), <String, dynamic>{
        'provider': 'ollama',
      });
    });

    test('baseUrl 首尾空白 + 多个尾斜杠被规整，路径仍为 /api/onboarding', () async {
      final server = await _LoopbackServer.start(
        (request) => _respond(request, 200, '{}'),
      );
      addTearDown(server.close);

      final ok = await const DefaultLlmOnboardingApi().saveConfig(
        serverBaseUrl: '  ${server.baseUrl}///  ',
        config: _config,
      );

      expect(ok, isTrue);
      expect(server.paths.single, '/api/onboarding');
    });

    test('状态码边界：299 → true；300 → false；500 → false', () async {
      var status = 299;
      final server = await _LoopbackServer.start(
        (request) => _respond(request, status, '{}'),
      );
      addTearDown(server.close);
      const api = DefaultLlmOnboardingApi();

      expect(
        await api.saveConfig(serverBaseUrl: server.baseUrl, config: _config),
        isTrue,
      );

      status = 300;
      expect(
        await api.saveConfig(serverBaseUrl: server.baseUrl, config: _config),
        isFalse,
      );

      status = 500;
      expect(
        await api.saveConfig(serverBaseUrl: server.baseUrl, config: _config),
        isFalse,
      );

      expect(server.requestCount, 3);
    });

    test('非绝对 URL → 请求构造抛错被吞，优雅返回 false', () async {
      final ok = await const DefaultLlmOnboardingApi().saveConfig(
        serverBaseUrl: 'not-a-url',
        config: _config,
      );

      expect(ok, isFalse);
    });

    test('端口无人监听（连接被拒）→ 优雅返回 false', () async {
      final deadPort = await _reserveClosedPort();

      final ok = await const DefaultLlmOnboardingApi().saveConfig(
        serverBaseUrl: 'http://127.0.0.1:$deadPort',
        config: _config,
      );

      expect(ok, isFalse);
    });

    test('服务端接受连接后立刻断开 → 不抛出，返回 false', () async {
      // 裸 ServerSocket：accept 后立即 destroy，不给任何 HTTP 响应。
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => raw.close());
      raw.listen((socket) => socket.destroy());

      final ok = await const DefaultLlmOnboardingApi().saveConfig(
        serverBaseUrl: 'http://127.0.0.1:${raw.port}',
        config: _config,
      );

      expect(ok, isFalse);
    });
  });

  group('LlmOnboardingConfig.toJson（逐键位）', () {
    test('四键齐全 → 全部保留', () {
      expect(_config.toJson(), <String, dynamic>{
        'provider': 'openrouter',
        'api_key': 'sk-or-v1-cov',
        'base_url': 'https://openrouter.ai/api/v1',
        'model': 'anthropic/claude-3.5-sonnet',
      });
    });

    test('null 与空串一视同仁 —— 对应键整体省略', () {
      const allNull = LlmOnboardingConfig(provider: 'custom');
      const allEmpty = LlmOnboardingConfig(
        provider: 'custom',
        apiKey: '',
        baseUrl: '',
        model: '',
      );

      expect(allNull.toJson(), <String, dynamic>{'provider': 'custom'});
      expect(allEmpty.toJson(), <String, dynamic>{'provider': 'custom'});
    });

    test('逐键单独存在时只补该键', () {
      expect(
        const LlmOnboardingConfig(provider: 'p', apiKey: 'k').toJson(),
        <String, dynamic>{'provider': 'p', 'api_key': 'k'},
      );
      expect(
        const LlmOnboardingConfig(provider: 'p', baseUrl: 'u').toJson(),
        <String, dynamic>{'provider': 'p', 'base_url': 'u'},
      );
      expect(
        const LlmOnboardingConfig(provider: 'p', model: 'm').toJson(),
        <String, dynamic>{'provider': 'p', 'model': 'm'},
      );
    });

    test('provider 为空串也保留（必填键不做省略判断）', () {
      expect(
        const LlmOnboardingConfig(provider: '').toJson(),
        <String, dynamic>{'provider': ''},
      );
    });

    test('近似键名反例：apiKey / baseUrl / model 只落 snake_case 键', () {
      final json = _config.toJson();

      expect(json.containsKey('apiKey'), isFalse);
      expect(json.containsKey('baseUrl'), isFalse);
      expect(json['api_key'], isNotNull);
      expect(json['base_url'], isNotNull);
      expect(json.keys.toSet(), <String>{
        'provider',
        'api_key',
        'base_url',
        'model',
      });
    });
  });

  group('LlmProviderOption.builtinProviders', () {
    test('6 家内置 provider：id 唯一、必填字段非空', () {
      final providers = LlmProviderOption.builtinProviders;

      expect(providers, hasLength(6));
      expect(
        providers.map((p) => p.id).toSet(),
        <String>{'openrouter', 'anthropic', 'openai', 'google', 'ollama', 'custom'},
      );
      for (final p in providers) {
        expect(p.id, isNotEmpty);
        expect(p.name, isNotEmpty);
        expect(p.description, isNotEmpty);
        expect(p.keyPlaceholder, isNotEmpty);
      }
    });

    test('默认值：只有 ollama 不需要 API Key，且带本地 baseUrl', () {
      final providers = LlmProviderOption.builtinProviders;

      final noKeyNeeded =
          providers.where((p) => !p.requiresApiKey).map((p) => p.id).toList();
      expect(noKeyNeeded, <String>['ollama']);
      expect(
        providers.firstWhere((p) => p.id == 'ollama').defaultBaseUrl,
        'http://127.0.0.1:11434',
      );
    });

    test('默认值：custom 的 baseUrl/model 为空串（由用户填写）', () {
      final custom =
          LlmProviderOption.builtinProviders.firstWhere((p) => p.id == 'custom');

      expect(custom.defaultBaseUrl, isEmpty);
      expect(custom.defaultModel, isEmpty);
      expect(custom.requiresApiKey, isTrue);
      expect(custom.keyPlaceholder, 'API Key');
    });

    test('构造函数默认值：defaultBaseUrl/defaultModel 为空、requiresApiKey 为 true', () {
      const option = LlmProviderOption(
        id: 'x',
        name: 'X',
        description: 'd',
      );

      expect(option.defaultBaseUrl, isEmpty);
      expect(option.defaultModel, isEmpty);
      expect(option.requiresApiKey, isTrue);
      expect(option.keyPlaceholder, '请输入 API Key');
    });
  });

  group('llmOnboardingApiProvider', () {
    test('默认 build → DefaultLlmOnboardingApi', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(llmOnboardingApiProvider),
        isA<DefaultLlmOnboardingApi>(),
      );
    });

    test('override 注入 fake 后 read 返回注入实例', () {
      final fake = _StubLlmOnboardingApi();
      final container = ProviderContainer(
        overrides: [llmOnboardingApiProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(llmOnboardingApiProvider), same(fake));
    });
  });
}

class _StubLlmOnboardingApi implements LlmOnboardingApi {
  @override
  Future<bool> saveConfig({
    required String serverBaseUrl,
    required LlmOnboardingConfig config,
  }) async =>
      true;
}
