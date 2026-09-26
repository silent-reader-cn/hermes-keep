import '../../core/api/api_client.dart';
import '../../core/api/api_client_chat.dart';
import '../../core/api/api_client_sessions.dart';
import '../../core/api/sse_client.dart';
import '../../core/models/approval.dart';
import '../../core/models/clarification.dart';
import '../../core/models/server_catalog.dart';
import '../../core/models/session.dart';

/// 聊天模块所需的最小服务器 API 面。
///
/// 生产实现 [ChatApiClient] 包 [ApiClient] + [SseClient]；测试可注入纯 Dart
/// fake，彻底绕开网络/事件循环（对齐 onboarding 的 `OnboardingServerApi` 模式）。
abstract interface class ChatServerApi {
  /// POST /api/chat/start → ChatStartResponse。
  Future<ChatStartResponse> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  });

  /// POST /api/chat/steer {session_id, text} → ChatSteerResponse。
  Future<ChatSteerResponse> steerChat({required String sessionId, required String text});

  /// GET /api/chat/cancel?stream_id= → ChatCancelResponse。
  Future<ChatCancelResponse> cancelChat(String streamId);

  /// GET /api/chat/stream/status?stream_id= → ChatStreamStatusResponse。
  Future<ChatStreamStatusResponse> chatStreamStatus(String streamId);

  /// POST /api/approval/respond {session_id, choice, approval_id?} → ApprovalRespondResponse。
  Future<ApprovalRespondResponse> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  });

  /// POST /api/clarify/respond {session_id, response, clarify_id?} → ClarificationRespondResponse。
  Future<ClarificationRespondResponse> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  });

  /// GET /api/session（messages=1 时带 transcript；无消息 = 补拉标题）→ SessionResponse。
  Future<SessionResponse> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  });

  /// POST /api/session/rename {session_id, title} → SessionMutationResponse。
  Future<SessionMutationResponse> renameSession({required String sessionId, required String title});

  /// POST /api/session/pin {session_id, pinned} → SessionMutationResponse。
  Future<SessionMutationResponse> pinSession({required String sessionId, required bool pinned});

  /// POST /api/session/archive {session_id, archived} → SessionMutationResponse。
  Future<SessionMutationResponse> archiveSession({required String sessionId, required bool archived});

  /// POST /api/session/delete {session_id} → SessionMutationResponse。
  Future<SessionMutationResponse> deleteSession(String sessionId);

  /// POST /api/session/branch {session_id, keep_count?} → SessionBranchResponse。
  ///
  /// [keepCount] 为复制前 N 条消息（0 = 空分支；缺省 = 全量历史）。
  Future<SessionBranchResponse> branchSession(String sessionId, {int? keepCount});

  /// POST /api/session/truncate {session_id, keep_count} → SessionResponse。
  ///
  /// [keepCount] 为从开头保留的消息条数（0 = 清空）。
  Future<SessionResponse> truncateSession({
    required String sessionId,
    required int keepCount,
  });

  /// POST /api/session/compress {session_id, focus_topic?} → SessionCompressResponse。
  Future<SessionCompressResponse> compressSession({
    required String sessionId,
    String? focusTopic,
  });

  /// POST /api/session/compress/start {session_id, focus_topic?} →
  /// SessionCompressStatusResponse（#156 异步压缩：立刻返回，后台线程执行；
  /// 已有 running job 时幂等复用）。
  Future<SessionCompressStatusResponse> startSessionCompression({
    required String sessionId,
    String? focusTopic,
  });

  /// GET /api/session/compress/status?session_id= →
  /// SessionCompressStatusResponse（#156 轮询进度；无 job 时为 idle）。
  Future<SessionCompressStatusResponse> compressionStatus(String sessionId);

  /// POST /api/session/undo {session_id} → SessionUndoResponse（删最后一轮）。
  Future<SessionUndoResponse> undoSession(String sessionId);

  /// POST /api/session/retry {session_id} → SessionRetryResponse（text=最后一轮用户消息原文）。
  Future<SessionRetryResponse> retrySession(String sessionId);

  /// POST /api/session/update {session_id, workspace?, model?, model_provider?}
  /// → SessionResponse。
  Future<SessionResponse> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  });

  /// GET /api/session/yolo?session_id= → SessionYoloResponse。
  Future<SessionYoloResponse> getYolo(String sessionId);

  /// POST /api/session/yolo {session_id, enabled} → SessionYoloResponse。
  Future<SessionYoloResponse> setYolo({
    required String sessionId,
    required bool enabled,
  });

  /// 建立 SSE 连接并持续派发解码后的事件；流自然结束/出错后返回。
  ///
  /// [onEventId] 在收到事件 `id:` 字段时回调（lastEventID 跟踪用）。
  /// [onTransportError] / [onClosed] 分别对应传输错误与连接关闭。
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  });

  /// 主动断开**指定 stream** 的 SSE 连接（静默，不触发 onTransportError）。
  ///
  /// 必须按 streamId 精确断开：多会话并行时每个会话各持一条独立连接，
  /// 无差别断开会误杀其它会话的流 → 对方静默无传输活动 → 看门狗判
  /// transport silence → 强制重连风暴（见 [ChatApiClient] 的 per-stream 池）。
  void stopStream(String streamId);

  /// 建立 Clarify SSE 独立流连接（`/api/clarify/stream?session_id=`）。
  Future<void> startClarifyStream(
    String sessionId, {
    required void Function(SseEvent event) onEvent,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  });

  /// 主动断开 Clarify SSE 连接。
  void stopClarifyStream();

  /// GET /api/clarify/pending?session_id= → ClarificationPendingResponse。
  Future<ClarificationPendingResponse> clarifyPending(String sessionId);

  /// 建立 Approval SSE 独立流连接（`/api/approval/stream?session_id=`）。
  Future<void> startApprovalStream(
    String sessionId, {
    required void Function(SseEvent event) onEvent,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  });

  /// 主动断开 Approval SSE 连接。
  void stopApprovalStream();

  /// GET /api/approval/pending?session_id= → ApprovalPendingResponse。
  Future<ApprovalPendingResponse> approvalPending(String sessionId);
}

/// [ChatServerApi] 的生产实现（包 [ApiClient]，SSE 复用其 dio 继承 header/cookie）。
class ChatApiClient implements ChatServerApi {
  ChatApiClient(this._client);

  final ApiClient _client;

  /// per-stream SSE 连接池（key = streamId；池空 = 当前无活跃会话流）。
  ///
  /// 每个 streamId 各持**独立** [SseClient]（独立 CancelToken）：会话 B 开流
  /// 不会取消会话 A 的流，[stopStream] 也只断指定流。流自然结束 / 出错后由
  /// [startStream] 的 finally 回收，避免池泄漏。
  ///
  /// 反面教材：曾共用同一个 [SseClient] 实例，而它的 `start()` 会先 cancel
  /// 旧 token —— 多会话并行时互相踩断连接，制造 transport silence 重连风暴。
  final Map<String, SseClient> _streamClients = <String, SseClient>{};

  /// 底层 [ApiClient] 实例（供伴随通道复用其 dio 与 baseUrl）。
  ApiClient get client => _client;

  @override
  Future<ChatStartResponse> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) {
    return _client.startChat(
      sessionId: sessionId,
      message: message,
      workspace: workspace,
      model: model,
      modelProvider: modelProvider,
      profile: profile,
      explicitModelPick: explicitModelPick,
      attachments: attachments,
    );
  }

  @override
  Future<ChatSteerResponse> steerChat({
    required String sessionId,
    required String text,
  }) {
    return _client.steerChat(sessionId: sessionId, text: text);
  }

  @override
  Future<ChatCancelResponse> cancelChat(String streamId) =>
      _client.cancelChat(streamId);

  @override
  Future<ChatStreamStatusResponse> chatStreamStatus(String streamId) =>
      _client.chatStreamStatus(streamId);

  @override
  Future<ApprovalRespondResponse> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) {
    return _client.respondApproval(
      sessionId: sessionId,
      choice: choice,
      approvalId: approvalId,
    );
  }

  @override
  Future<ClarificationRespondResponse> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) {
    return _client.respondClarification(
      sessionId: sessionId,
      response: response,
      clarifyId: clarifyId,
    );
  }

  @override
  Future<SessionResponse> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) {
    return _client.session(
      sessionId: sessionId,
      includeMessages: includeMessages,
      messageLimit: messageLimit,
      messageBefore: messageBefore,
      expandRenderable: expandRenderable,
    );
  }

  @override
  Future<SessionMutationResponse> renameSession({
    required String sessionId,
    required String title,
  }) {
    return _client.renameSession(sessionId: sessionId, title: title);
  }

  @override
  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  }) {
    return _client.pinSession(sessionId: sessionId, pinned: pinned);
  }

  @override
  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  }) {
    return _client.archiveSession(sessionId: sessionId, archived: archived);
  }

  @override
  Future<SessionMutationResponse> deleteSession(String sessionId) =>
      _client.deleteSession(sessionId);

  @override
  Future<SessionBranchResponse> branchSession(String sessionId, {int? keepCount}) =>
      _client.branchSession(sessionId: sessionId, keepCount: keepCount);

  @override
  Future<SessionResponse> truncateSession({
    required String sessionId,
    required int keepCount,
  }) {
    return _client.truncateSession(sessionId: sessionId, keepCount: keepCount);
  }

  @override
  Future<SessionCompressResponse> compressSession({
    required String sessionId,
    String? focusTopic,
  }) {
    return _client.compressSession(
      sessionId: sessionId,
      focusTopic: focusTopic,
    );
  }

  @override
  Future<SessionCompressStatusResponse> startSessionCompression({
    required String sessionId,
    String? focusTopic,
  }) {
    return _client.startSessionCompression(
      sessionId: sessionId,
      focusTopic: focusTopic,
    );
  }

  @override
  Future<SessionCompressStatusResponse> compressionStatus(String sessionId) =>
      _client.compressionStatus(sessionId);

  @override
  Future<SessionUndoResponse> undoSession(String sessionId) =>
      _client.undoSession(sessionId);

  @override
  Future<SessionRetryResponse> retrySession(String sessionId) =>
      _client.retrySession(sessionId);

  @override
  Future<SessionResponse> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) {
    return _client.updateSession(
      sessionId: sessionId,
      workspace: workspace,
      model: model,
      modelProvider: modelProvider,
    );
  }

  @override
  Future<SessionYoloResponse> getYolo(String sessionId) => _client.sessionYolo(sessionId);

  @override
  Future<SessionYoloResponse> setYolo({
    required String sessionId,
    required bool enabled,
  }) {
    return _client.setSessionYolo(sessionId: sessionId, enabled: enabled);
  }

  @override
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    final url = _client.chatStreamUrl(
      streamId,
      replayAfterSeq: replayAfterSeq,
    );
    // 同一 streamId 的重连：替换并取消**自己的**旧连接；其它 streamId 不受影响。
    _streamClients.remove(streamId)?.stop();
    final sse = SseClient(dio: _client.dio, baseUrl: _client.baseUrl);
    _streamClients[streamId] = sse;
    try {
      await sse.start(
        url,
        onEvent: onEvent,
        onEventId: onEventId,
        onTransportError: onTransportError,
        onClosed: onClosed,
      );
    } finally {
      if (identical(_streamClients[streamId], sse)) {
        _streamClients.remove(streamId);
      }
    }
  }

  @override
  void stopStream(String streamId) => _streamClients.remove(streamId)?.stop();

  SseClient? _clarifySseClient;

  @override
  Future<ClarificationPendingResponse> clarifyPending(String sessionId) =>
      _client.clarifyPending(sessionId);

  @override
  Future<void> startClarifyStream(
    String sessionId, {
    required void Function(SseEvent event) onEvent,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    _clarifySseClient?.stop();
    final sse = SseClient(dio: _client.dio, baseUrl: _client.baseUrl);
    _clarifySseClient = sse;
    final url = _client.clarifyStreamUrl(sessionId);
    await sse.start(
      url,
      onEvent: onEvent,
      onTransportError: onTransportError,
      onClosed: onClosed,
    );
  }

  @override
  void stopClarifyStream() {
    _clarifySseClient?.stop();
    _clarifySseClient = null;
  }

  SseClient? _approvalSseClient;

  @override
  Future<ApprovalPendingResponse> approvalPending(String sessionId) =>
      _client.approvalPending(sessionId);

  @override
  Future<void> startApprovalStream(
    String sessionId, {
    required void Function(SseEvent event) onEvent,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    _approvalSseClient?.stop();
    final sse = SseClient(dio: _client.dio, baseUrl: _client.baseUrl);
    _approvalSseClient = sse;
    final url = _client.approvalStreamUrl(sessionId);
    await sse.start(
      url,
      onEvent: onEvent,
      onTransportError: onTransportError,
      onClosed: onClosed,
    );
  }

  @override
  void stopApprovalStream() {
    _approvalSseClient?.stop();
    _approvalSseClient = null;
  }
}
