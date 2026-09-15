import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

import 'custom_header.dart';
import 'sse_client.dart';

/// SSE 长连接通道公共抽象基类。
///
/// 封装通用的连接生命周期管理（start/stop/dispose）、指数退避重连、认证头与 Cookie 注入、
/// 流读取及 CancelToken 生命周期管理（防止连接泄漏，对齐 #73 规范）。
abstract class SseChannelBase {
  SseChannelBase({
    required this.dio,
    required this.baseUrl,
    this.customHeaderProvider,
    this.cookieProvider,
    this.isEnabled,
    this.backoffStrategy,
  });

  /// 传输用 dio；传入 [ApiClient.dio] 时自动继承其自定义头/cookie 拦截器。
  final Dio dio;

  /// 服务器 base URL。
  final String baseUrl;

  /// 自定义请求头提供者。
  final List<CustomHeader> Function()? customHeaderProvider;

  /// Cookie 提供者。
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

  /// 通道是否处于运行状态。
  bool get isRunning => _running;

  /// 当前重连尝试次数。
  int get reconnectAttempts => _reconnectAttempts;

  /// 测试专用的当前 CancelToken 句柄。
  @visibleForTesting
  CancelToken? get cancelTokenForTesting => _cancelToken;

  /// 本次连接的目标 URL（子类必实现）。
  @protected
  Uri buildUrl();

  /// 帧路由处理（子类必实现）。
  @protected
  void processWire(SseWireEvent wire);

  /// start() 的额外前置守卫（可选覆写，返回 false 则不建连）。
  @protected
  bool canStart() => true;

  /// 连接成功建立后的回调（可选覆写）。
  /// [wasReconnecting] 表示是否由断线重连触发。
  @protected
  void onConnected({required bool wasReconnecting}) {}

  /// 启动通道订阅（幂等）。已启动、已 dispose、未通过 [canStart] 或未启用时为 no-op。
  void start() {
    if (_disposed || _running) return;
    if (!canStart()) return;
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

  /// 计算指定重试次数的退避延迟。
  Duration getBackoffDelay(int attempt) {
    if (backoffStrategy != null) return backoffStrategy!(attempt);
    // 指数退避 1s * 2^n 封顶 30s
    final shift = attempt > 30 ? 30 : attempt;
    final seconds = (1 << shift).clamp(1, 30);
    return Duration(seconds: seconds);
  }

  void _scheduleReconnect() {
    if (!_running || _disposed) return;
    _reconnectTimer?.cancel();
    final delay = getBackoffDelay(_reconnectAttempts);
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

    final url = buildUrl();

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
      onConnected(wasReconnecting: wasReconnecting);

      final parser = SseWireParser();
      await for (final chunk in body.stream) {
        if (!_running || _disposed || cancelToken.isCancelled) break;
        final text = utf8.decode(chunk, allowMalformed: true);
        for (final wire in parser.feed(text)) {
          processWire(wire);
        }
      }
      for (final wire in parser.finish()) {
        processWire(wire);
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
}
