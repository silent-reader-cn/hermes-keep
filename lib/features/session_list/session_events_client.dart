import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/sse_channel_base.dart';
import '../../core/api/sse_client.dart';
import '../../core/api/stream_toggle_controller.dart';

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
class SessionEventsStreamEnabledController extends StreamToggleController {
  static const String key = kSessionEventsStreamEnabledKey;

  @override
  String get storageKey => key;

  /// 读取开关偏好的静态辅助方法。
  static Future<bool> loadPref({SharedPreferences? customPrefs}) =>
      StreamToggleController.loadPrefFor(key, customPrefs: customPrefs);
}

/// 会话列表变更推送客户端（SSE 订阅 GET /api/sessions/events）。
///
/// 特性：
/// - 仅认 `event: sessions_changed`，忽略 keepalive 注释帧与其他事件名；
/// - version 单调去重：`payload.version <= lastVersion` → skip（初值 -1）；
///   payload 非法/无 version → 视为有效（宁多刷不漏刷）；
/// - 断线重连：指数退避 1s*2^n 封顶 30s；每次成功重连后立即触发一次回调（补空洞）；
/// - 提供 start() / stop() / dispose()，stop 幂等。
class SessionEventsSseClient extends SseChannelBase {
  SessionEventsSseClient({
    required super.dio,
    required super.baseUrl,
    required this.onSessionsChanged,
    super.customHeaderProvider,
    super.cookieProvider,
    super.isEnabled,
    super.backoffStrategy,
  });

  /// 收到有效变更事件或成功重连后的回调。
  final SessionsChangedCallback onSessionsChanged;

  int _lastVersion = -1;

  int get lastVersion => _lastVersion;

  @override
  Uri buildUrl() => Endpoint.sessionEvents.url(baseUrl);

  @override
  void onConnected({required bool wasReconnecting}) {
    if (wasReconnecting) {
      onSessionsChanged(reason: 'reconnect');
    }
  }

  @override
  void processWire(SseWireEvent wire) {
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
    final profile = jsonMap['profile'] is String
        ? jsonMap['profile'] as String
        : null;
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
