import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/sse_channel_base.dart';
import '../../core/api/sse_client.dart';
import '../../core/api/stream_toggle_controller.dart';

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
class SessionContentStreamEnabledController extends StreamToggleController {
  static const String key = kSessionContentStreamEnabledKey;

  @override
  String get storageKey => key;

  /// 读取开关偏好的静态辅助方法。
  static Future<bool> loadPref({SharedPreferences? customPrefs}) =>
      StreamToggleController.loadPrefFor(key, customPrefs: customPrefs);
}

/// 会话内容实时同步通道（SSE 订阅 GET /api/session/stream?session_id=&known_count=）。
///
/// 特性：
/// - 帧路由：
///   - `session-updated` → [onSessionUpdated]（带 serverCount）
///   - `server_turn_started` → [onServerTurnStarted]（带 streamId, recovered, pendingStartedAt，同 streamId 幂等去重）
///   - `bg_task_complete` → [onBgTaskComplete]（带 payload；忽略 process_complete 旧别名）
///   - `initial`、keepalive 注释帧与未知事件静默忽略，不崩溃；
/// - 重连机制：断线指数退避 1s*2^n 封顶 30s；
///   重连时通过 [knownCountProvider] 拉取最新本地持久 message_count 作为 query 参数；
/// - start/stop/dispose 幂等。
class ChatSessionChannel extends SseChannelBase {
  ChatSessionChannel({
    required super.dio,
    required super.baseUrl,
    required this.sessionId,
    required this.onSessionUpdated,
    required this.onServerTurnStarted,
    required this.onBgTaskComplete,
    this.knownCountProvider,
    super.customHeaderProvider,
    super.cookieProvider,
    super.isEnabled,
    super.backoffStrategy,
  });

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

  String? _lastServerTurnStreamId;

  String? get lastServerTurnStreamId => _lastServerTurnStreamId;

  @visibleForTesting
  void resetLastServerTurnStreamId() => _lastServerTurnStreamId = null;

  @override
  bool canStart() => sessionId.isNotEmpty;

  @override
  Uri buildUrl() => Endpoint.sessionStream(
    sessionId,
    knownCountProvider?.call(),
  ).url(baseUrl);

  @override
  void processWire(SseWireEvent wire) {
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
  void processWireForTesting(SseWireEvent wire) => processWire(wire);
}
