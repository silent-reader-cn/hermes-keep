import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/custom_header.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/sse_client.dart';

/// 会话内容更新推送回调签名。
typedef SessionUpdatedCallback = void Function(int serverCount);

/// 服务端自唤醒回合启动回调签名。
typedef ServerTurnStartedCallback = void Function(
  String streamId, {
  bool recovered,
  double? pendingStartedAt,
});

/// 后台任务完成推送回调签名。
typedef BgTaskCompleteCallback = void Function(Map<String, Object?> payload);

/// 持久化 key：会话内容实时同步。
const String kSessionContentStreamEnabledKey = 'session_content_stream_enabled';

/// 会话内容实时同步（SSE）开关 Provider（持久化到 shared_preferences，默认开启 true）。
final sessionContentStreamEnabledProvider =
    NotifierProvider<SessionContentStreamEnabledController, bool>(
      SessionContentStreamEnabledController.new,
    );

/// 控制会话内容实时同步开关及本地持久化的 Notifier。
class SessionContentStreamEnabledController extends Notifier<bool> {
  static const String key = kSessionContentStreamEnabledKey;

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

/// 会话内容实时同步通道（SSE 订阅 GET /api/session/stream?session_id=&known_count=）。
///
/// 特性：
/// - 帧路由：
///   - `session-updated` → [onSessionUpdated]（带 serverCount）
///   - `server_turn_started` → [onServerTurnStarted]（带 streamId, recovered, pendingStartedAt，同 streamId 幂等去重）
///   - `bg_task_complete` → [onBgTaskComplete]（带 payload；忽略 process_complete 旧别名）
///   - `initial`、keepalive 注释帧与未知事件静默忽略，不崩崩溃；
/// - 重连机制：断线指数退避 1s*2^n 封顶 30s；
///   重连时通过 [knownCountProvider] 拉取最新本地持久 message_count 作为 query 参数；
/// - start/stop/dispose 幂等。
class ChatSessionChannel {
  ChatSessionChannel({
    required this.dio,
    required this.baseUrl,
    required this.sessionId,
    required this.onSessionUpdated,
    required this.onServerTurnStarted,
    required this.onBgTaskComplete,
    this.knownCountProvider,
    this.customHeaderProvider,
    this.cookieProvider,
    this.isEnabled,
    this.backoffStrategy,
  });

  /// 传输用 dio；传入 [ApiClient.dio] 时自动继承其自定义头/cookie 拦截器。
  final Dio dio;

  /// 服务器 base URL。
  final String baseUrl;

  /// 当前订阅会话 ID。
  final String sessionId;

  /// 会话增量计数更新回调。
  final SessionUpdatedCallback onSessionUpdated;

  /// 服务端自唤醒回合开始回调。
  final ServerTurnStartedCallback onServerTurnStarted;

  /// 后台任务完成事件回调。
  final BgTaskCompleteCallback onBgTaskComplete;

  /// 提供当前本地最新持久 message_count 的回调（用于 (重)连 query）。
  final int? Function()? knownCountProvider;

  final List<CustomHeader> Function()? customHeaderProvider;
  final String? Function(Uri uri)? cookieProvider;

  /// 可选的启用门控（返回 false 则 start 不建连）。
  final bool Function()? isEnabled;

  /// 可选的退避计算策略（测试注入用）。
  final Duration Function(int attempt)? backoffStrategy;

  bool _running = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _connectTimer;
  CancelToken? _cancelToken;
  String? _lastServerTurnStreamId;

  bool get isRunning => _running;
  int get reconnectAttempts => _reconnectAttempts;
  String? get lastServerTurnStreamId => _lastServerTurnStreamId;

  @visibleForTesting
  CancelToken? get cancelTokenForTesting => _cancelToken;

  @visibleForTesting
  void resetLastServerTurnStreamId() => _lastServerTurnStreamId = null;

  /// 启动通道订阅（幂等）。已启动、已 dispose 或未启用时为 no-op。
  void start() {
    if (_disposed || _running) return;
    if (sessionId.isEmpty) return;
    if (isEnabled != null && !isEnabled!()) return;
    _running = true;
    _reconnectAttempts = 0;
    _connectTimer?.cancel();
    _connectTimer = Timer(Duration.zero, () {
      if (!_running || _disposed) return;
      unawaited(_connect());
    });
  }

  /// 停止通道订阅（幂等）。
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

  /// 释放通道资源。
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

    final knownCount = knownCountProvider?.call();
    final url = Endpoint.sessionStream(sessionId, knownCount).url(baseUrl);

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

      _reconnectAttempts = 0;

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
    final eventType = wire.eventType;

    // 忽略 initial 连接确认与旧别名 process_complete
    if (eventType == 'initial' || eventType == 'process_complete') {
      return;
    }

    final data = wire.data.trim();
    if (data.isEmpty) return;

    Map<String, Object?>? jsonMap;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, Object?>) {
        jsonMap = decoded;
      } else if (decoded is Map) {
        jsonMap = Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // 畸形 JSON 忽略，保证稳健
      return;
    }

    if (jsonMap == null) return;

    switch (eventType) {
      case 'session-updated':
        final rawCount = jsonMap['message_count'];
        int? count;
        if (rawCount is int) {
          count = rawCount;
        } else if (rawCount is num) {
          count = rawCount.toInt();
        } else if (rawCount is String) {
          count = int.tryParse(rawCount);
        }
        if (count != null) {
          try {
            onSessionUpdated(count);
          } catch (_) {}
        }
        break;

      case 'server_turn_started':
        final streamId = jsonMap['stream_id']?.toString().trim();
        if (streamId == null || streamId.isEmpty) return;

        // 同 streamId 幂等去重
        if (streamId == _lastServerTurnStreamId) {
          return;
        }
        _lastServerTurnStreamId = streamId;

        final recovered = jsonMap['recovered'] == true;
        final rawPendingStartedAt = jsonMap['pending_started_at'];
        double? pendingStartedAt;
        if (rawPendingStartedAt is num) {
          pendingStartedAt = rawPendingStartedAt.toDouble();
        } else if (rawPendingStartedAt is String) {
          pendingStartedAt = double.tryParse(rawPendingStartedAt);
        }

        try {
          onServerTurnStarted(
            streamId,
            recovered: recovered,
            pendingStartedAt: pendingStartedAt,
          );
        } catch (_) {}
        break;

      case 'bg_task_complete':
        try {
          onBgTaskComplete(jsonMap);
        } catch (_) {}
        break;

      default:
        // 未知帧静默忽略
        break;
    }
  }

  @visibleForTesting
  void processWireForTesting(SseWireEvent wire) => _processWire(wire);
}
