import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/custom_header.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/sse_client.dart';

/// 会话变更推送事件回调签名。
typedef SessionsChangedCallback = void Function({
  int? version,
  String? reason,
  String? profile,
  String? sessionId,
});

/// 持久化 key：会话列表实时推送。
const String kSessionEventsStreamEnabledKey = 'session_events_stream_enabled';

/// 会话列表实时推送（SSE）开关 Provider（持久化到 shared_preferences，默认开启 true）。
final sessionEventsStreamEnabledProvider =
    NotifierProvider<SessionEventsStreamEnabledController, bool>(
      SessionEventsStreamEnabledController.new,
    );

/// 控制会话列表实时推送开关及本地持久化的 Notifier。
class SessionEventsStreamEnabledController extends Notifier<bool> {
  static const String key = kSessionEventsStreamEnabledKey;

  /// 读取开关偏好的静态辅助方法。
  static Future<bool> loadPref({SharedPreferences? customPrefs}) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? true;
    } catch (_) {
      return true;
    }
  }

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return true; // 默认 true
  }

  Future<void> _load() async {
    try {
      final value = await loadPref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // 单元测试无 SharedPreferences 时静默忽略
    }
  }

  Future<void> load() => _load();

  Future<void> setEnabled(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // 单元测试环境忽略
    }
  }
}

/// 会话列表变更推送客户端（SSE 订阅 GET /api/sessions/events）。
///
/// 特性：
/// - 仅认 `event: sessions_changed`，忽略 keepalive 注释帧与其他事件名；
/// - version 单调去重：`payload.version <= lastVersion` → skip（初值 -1）；
///   payload 非法/无 version → 视为有效（宁多刷不漏刷）；
/// - 断线重连：指数退避 1s*2^n 封顶 30s；每次成功重连后立即触发一次回调（补空洞）；
/// - 提供 start() / stop() / dispose()，stop 幂等。
class SessionEventsSseClient {
  SessionEventsSseClient({
    required this.dio,
    required this.baseUrl,
    required this.onSessionsChanged,
    this.customHeaderProvider,
    this.cookieProvider,
    this.isEnabled,
    this.backoffStrategy,
  });

  /// 传输用 dio；传入 [ApiClient.dio] 时自动继承其自定义头/cookie 拦截器。
  final Dio dio;

  /// 服务器 base URL。
  final String baseUrl;

  /// 收到有效变更事件或成功重连后的回调。
  final SessionsChangedCallback onSessionsChanged;

  final List<CustomHeader> Function()? customHeaderProvider;
  final String? Function(Uri uri)? cookieProvider;

  /// 可选的启用门控（返回 false 则 start 不建连）。
  final bool Function()? isEnabled;

  /// 可选的退避计算策略（测试注入用）。
  final Duration Function(int attempt)? backoffStrategy;

  int _lastVersion = -1;
  bool _running = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _connectTimer;
  CancelToken? _cancelToken;

  int get lastVersion => _lastVersion;
  bool get isRunning => _running;
  int get reconnectAttempts => _reconnectAttempts;

  @visibleForTesting
  CancelToken? get cancelTokenForTesting => _cancelToken;

  /// 启动订阅。已启动或已 dispose 则为 no-op。
  void start() {
    if (_disposed || _running) return;
    if (isEnabled != null && !isEnabled!()) return;
    _running = true;
    _reconnectAttempts = 0;
    _connectTimer?.cancel();
    _connectTimer = Timer(Duration.zero, () {
      if (!_running || _disposed) return;
      unawaited(_connect());
    });
  }

  /// 停止订阅（幂等）。
  void stop() {
    _running = false;
    _connectTimer?.cancel();
    _connectTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    _reconnectAttempts = 0;
  }

  /// 释放资源。
  void dispose() {
    _disposed = true;
    _connectTimer?.cancel();
    _connectTimer = null;
    stop();
  }

  Duration _getBackoffDelay(int attempt) {
    if (backoffStrategy != null) return backoffStrategy!(attempt);
    // 指数退避 1s * 2^n 封顶 30s
    final shift = attempt > 30 ? 30 : attempt;
    final seconds = (1 << shift).clamp(1, 30);
    return Duration(seconds: seconds);
  }

  void _scheduleReconnect() {
    if (!_running || _disposed) return;
    _reconnectTimer?.cancel();
    final delay = _getBackoffDelay(_reconnectAttempts);
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () {
      if (!_running || _disposed) return;
      unawaited(_connect());
    });
  }

  Future<void> _connect() async {
    if (!_running || _disposed) return;
    _cancelToken?.cancel();
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    final url = Endpoint.sessionEvents.url(baseUrl);
    final headers = <String, dynamic>{
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      'Accept-Encoding': 'identity',
    };
    if (customHeaderProvider != null) {
      for (final header in customHeaderProvider!()) {
        if (!header.isApplicable) continue;
        final name = header.sanitizedName;
        final lower = name.toLowerCase();
        if (!headers.keys.any((k) => k.toLowerCase() == lower)) {
          headers[name] = header.sanitizedValue;
        }
      }
    }
    final cookie = cookieProvider?.call(url);
    if (cookie != null &&
        cookie.isNotEmpty &&
        !headers.keys.any((k) => k.toLowerCase() == 'cookie')) {
      headers['Cookie'] = cookie;
    }

    final options = RequestOptions(
      method: 'GET',
      path: url.toString(),
      headers: headers,
      responseType: ResponseType.stream,
      validateStatus: (_) => true,
      followRedirects: true,
      receiveTimeout: const Duration(days: 1),
      sendTimeout: const Duration(seconds: 15),
      connectTimeout: const Duration(seconds: 15),
      cancelToken: cancelToken,
    );

    try {
      final response = await dio.fetch<ResponseBody>(options);
      if (response.statusCode != 200) {
        _scheduleReconnect();
        return;
      }
      final body = response.data;
      if (body == null) {
        _scheduleReconnect();
        return;
      }

      final wasReconnecting = _reconnectAttempts > 0;
      _reconnectAttempts = 0;

      // 每次成功重连后立即触发一次回调（补空洞）
      if (wasReconnecting) {
        onSessionsChanged(reason: 'reconnect');
      }

      final parser = SseWireParser();
      await for (final chunk in body.stream) {
        if (!_running || _disposed || cancelToken.isCancelled) break;
        final text = utf8.decode(chunk, allowMalformed: true);
        for (final wire in parser.feed(text)) {
          _processWire(wire);
        }
      }
      for (final wire in parser.finish()) {
        _processWire(wire);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || cancelToken.isCancelled) {
        return;
      }
      _scheduleReconnect();
      return;
    } catch (_) {
      if (!_running || _disposed || cancelToken.isCancelled) return;
      _scheduleReconnect();
      return;
    }

    if (_running && !_disposed && !cancelToken.isCancelled) {
      _scheduleReconnect();
    }
  }

  void _processWire(SseWireEvent wire) {
    if (wire.heartbeat) return;
    if (wire.eventType != 'sessions_changed') return;

    final data = wire.data.trim();
    if (data.isEmpty) {
      // 畸形/空 payload 视为有效（宁多刷不漏刷）
      onSessionsChanged();
      return;
    }

    Map<String, Object?>? jsonMap;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, Object?>) {
        jsonMap = decoded;
      } else if (decoded is Map) {
        jsonMap = Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // 畸形帧不炸，视为有效（宁多刷不漏刷）
    }

    if (jsonMap == null) {
      onSessionsChanged();
      return;
    }

    final rawVersion = jsonMap['version'];
    int? version;
    if (rawVersion is int) {
      version = rawVersion;
    } else if (rawVersion is num) {
      version = rawVersion.toInt();
    }

    final reason = jsonMap['reason'] is String
        ? jsonMap['reason'] as String
        : (jsonMap['type'] is String ? jsonMap['type'] as String : null);
    final profile =
        jsonMap['profile'] is String ? jsonMap['profile'] as String : null;
    final sessionId = jsonMap['session_id'] is String
        ? jsonMap['session_id'] as String
        : (jsonMap['sessionId'] is String
            ? jsonMap['sessionId'] as String
            : null);

    // version 单调去重：payload.version <= lastVersion → skip（初值 -1）；
    // payload 非法/无 version → 视为有效（宁多刷不漏刷）。
    if (version == null) {
      onSessionsChanged(
        version: null,
        reason: reason,
        profile: profile,
        sessionId: sessionId,
      );
      return;
    }

    if (version <= _lastVersion) {
      return;
    }

    _lastVersion = version;
    onSessionsChanged(
      version: version,
      reason: reason,
      profile: profile,
      sessionId: sessionId,
    );
  }
}
