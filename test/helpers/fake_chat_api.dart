import 'dart:async';

import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/approval.dart';
import 'package:hermes_ui/core/models/clarification.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_server_api.dart';

/// 可配置的 [ChatServerApi] fake（测试注入，彻底绕开网络/事件循环）。
class FakeChatApi implements ChatServerApi {
  FakeChatApi({
    this.steerAccepted = true,
    this.cancelOk = true,
    this.mutationOk = true,
  });

  bool steerAccepted;
  bool cancelOk;
  bool mutationOk;
  String? mutationError;
  Object? mutationThrows;

  Object? startChatError;
  ChatStartResponse? startChatResponse;
  Map<String, Object?>? startChatResult;

  Object? statusError;
  ChatStreamStatusResponse? statusResponse;
  Map<String, Object?>? statusResult;
  Future<ChatStreamStatusResponse> Function(String)? onChatStreamStatus;

  SessionResponse? sessionResponse;
  Map<String, Object?>? sessionResult;
  /// 动态响应构造器（#125）：按 messageBefore 逐页生成响应，优先于
  /// [sessionResult]。用于「连续多次分页」场景。
  Map<String, Object?> Function(int? messageBefore)? sessionResultBuilder;
  Object? sessionError;

  SessionMutationResponse? renameResponse;
  Map<String, Object?>? renameResult;

  SessionMutationResponse? pinResponse;
  SessionMutationResponse? archiveResponse;
  SessionMutationResponse? deleteResponse;

  SessionBranchResponse? branchResponse;

  SessionResponse? truncateResponse;
  SessionCompressResponse? compressResponse;
  SessionUndoResponse? undoResponse;

  // #156 异步压缩（start + status 轮询）
  int compressStartCalls = 0;
  int compressStatusCalls = 0;
  String? lastCompressFocusTopic;
  SessionCompressStatusResponse? compressStartResponse;
  SessionCompressStatusResponse? compressStatusResponse;
  /// 动态状态序列（#156）：按第 N 次 status 调用（1 起）返回不同状态，
  /// 优先于 [compressStatusResponse]，用于「running → running → done」场景。
  SessionCompressStatusResponse Function(int call)? compressStatusBuilder;
  Object? compressStartError;
  Object? compressStatusError;

  SessionRetryResponse? retryResponse;
  Map<String, Object?>? retryResult;

  SessionResponse? updateSessionResponse;
  Map<String, Object?>? updateSessionResult;

  SessionYoloResponse? yoloResponse;
  Map<String, Object?>? yoloResult;
  SessionYoloResponse? setYoloResponse;
  Map<String, Object?>? setYoloResult;

  ApprovalRespondResponse? respondApprovalResponse;
  ClarificationRespondResponse? respondClarificationResponse;

  // 调用计数与记录
  int startChatCalls = 0;
  int steerCalls = 0;
  int cancelCalls = 0;
  int statusCalls = 0;
  int sessionCalls = 0;
  /// 每次 session() 收到的 messageBefore（null = 首页加载），供分页断言。
  final List<int?> sessionMessageBefore = [];
  int renameCalls = 0;
  int pinCalls = 0;
  int archiveCalls = 0;
  int deleteCalls = 0;
  int branchCalls = 0;
  int truncateCalls = 0;
  final List<int> truncateKeepCounts = [];
  int compressCalls = 0;
  int undoCalls = 0;
  int retryCalls = 0;
  int updateSessionCalls = 0;
  int getYoloCalls = 0;
  int setYoloCalls = 0;
  int startStreamCalls = 0;
  int stopStreamCalls = 0;

  /// 被精确停止的 streamId 序列（多会话隔离断言用）。
  final List<String> stopStreamIds = <String>[];

  String? lastSentText;
  String? lastModel;
  String? lastModelProvider;

  /// 最近一次 startChat 提交的附件（待发附件链路断言用）。
  List<Map<String, Object?>>? lastSentAttachments;
  String? lastProfile;
  bool? lastExplicitModelPick;
  String? lastRenameTitle;
  bool? lastPinned;
  bool? lastArchived;
  int? lastBranchKeepCount;
  String? lastFocusTopic;
  String? lastUpdatedWorkspace;
  String? lastUpdatedModel;
  bool? lastYoloEnabled;
  int respondClarificationCalls = 0;
  String? lastClarificationSessionId;
  String? lastClarificationResponse;

  final List<String> streamIds = [];
  final List<int?> replaySeqs = [];

  void Function(SseEvent event)? _onEvent;
  void Function(String eventId)? _onEventId;
  void Function(String message)? _onTransportError;
  void Function()? _onClosed;

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
  }) async {
    startChatCalls++;
    lastSentText = message;
    lastSentAttachments = attachments;
    lastModel = model;
    lastModelProvider = modelProvider;
    lastProfile = profile;
    lastExplicitModelPick = explicitModelPick;
    if (startChatError != null) throw startChatError!;
    if (startChatResponse != null) return startChatResponse!;
    if (startChatResult != null) {
      return ChatStartResponse.fromJson(startChatResult!);
    }
    return ChatStartResponse(
      streamId: 'stream-$startChatCalls',
      sessionId: sessionId.isEmpty ? 'sess-new' : sessionId,
    );
  }

  @override
  Future<ChatSteerResponse> steerChat({
    required String sessionId,
    required String text,
  }) async {
    steerCalls++;
    return ChatSteerResponse(accepted: steerAccepted);
  }

  @override
  Future<ChatCancelResponse> cancelChat(String streamId) async {
    cancelCalls++;
    return ChatCancelResponse(ok: cancelOk, cancelled: cancelOk);
  }

  @override
  Future<ChatStreamStatusResponse> chatStreamStatus(String streamId) async {
    statusCalls++;
    if (statusError != null) throw statusError!;
    if (onChatStreamStatus != null) return onChatStreamStatus!(streamId);
    if (statusResponse != null) return statusResponse!;
    if (statusResult != null) {
      return ChatStreamStatusResponse.fromJson(statusResult!);
    }
    return const ChatStreamStatusResponse(
      active: false,
      replayAvailable: false,
    );
  }

  @override
  Future<SessionResponse> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) async {
    sessionCalls++;
    sessionMessageBefore.add(messageBefore);
    if (sessionError != null) throw sessionError!;
    if (sessionResponse != null) return sessionResponse!;
    if (sessionResultBuilder != null) {
      return SessionResponse.fromJson(sessionResultBuilder!(messageBefore));
    }
    if (sessionResult != null) {
      return SessionResponse.fromJson(sessionResult!);
    }
    return SessionResponse(
      session: SessionDetail(sessionId: sessionId, messages: const []),
    );
  }

  @override
  Future<ApprovalRespondResponse> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) async {
    return respondApprovalResponse ?? const ApprovalRespondResponse(ok: true);
  }

  @override
  Future<ClarificationRespondResponse> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) async {
    respondClarificationCalls++;
    lastClarificationSessionId = sessionId;
    lastClarificationResponse = response;
    return respondClarificationResponse ??
        const ClarificationRespondResponse(ok: true);
  }

  @override
  Future<SessionMutationResponse> renameSession({
    required String sessionId,
    required String title,
  }) async {
    renameCalls++;
    lastRenameTitle = title;
    if (mutationThrows != null) throw mutationThrows!;
    if (renameResponse != null) return renameResponse!;
    if (renameResult != null) {
      return SessionMutationResponse.fromJson(renameResult!);
    }
    return SessionMutationResponse(
      ok: mutationOk,
      error: mutationError,
      session: SessionSummary(sessionId: sessionId, title: title),
    );
  }

  @override
  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    pinCalls++;
    lastPinned = pinned;
    if (mutationThrows != null) throw mutationThrows!;
    if (pinResponse != null) return pinResponse!;
    return SessionMutationResponse(
      ok: mutationOk,
      error: mutationError,
      session: SessionSummary(sessionId: sessionId, pinned: pinned),
    );
  }

  @override
  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    archiveCalls++;
    lastArchived = archived;
    if (mutationThrows != null) throw mutationThrows!;
    if (archiveResponse != null) return archiveResponse!;
    return SessionMutationResponse(
      ok: mutationOk,
      error: mutationError,
      session: SessionSummary(sessionId: sessionId, archived: archived),
    );
  }

  @override
  Future<SessionMutationResponse> deleteSession(String sessionId) async {
    deleteCalls++;
    if (mutationThrows != null) throw mutationThrows!;
    if (deleteResponse != null) return deleteResponse!;
    return SessionMutationResponse(ok: mutationOk, error: mutationError);
  }

  @override
  Future<SessionBranchResponse> branchSession(
    String sessionId, {
    int? keepCount,
  }) async {
    branchCalls++;
    lastBranchKeepCount = keepCount;
    if (mutationThrows != null) throw mutationThrows!;
    if (branchResponse != null) return branchResponse!;
    return SessionBranchResponse(
      sessionId: mutationOk ? 'branch-$sessionId' : null,
      parentSessionId: sessionId,
      error: mutationOk ? null : mutationError,
    );
  }

  @override
  Future<SessionResponse> truncateSession({
    required String sessionId,
    required int keepCount,
  }) async {
    truncateCalls++;
    truncateKeepCounts.add(keepCount);
    if (mutationThrows != null) throw mutationThrows!;
    if (truncateResponse != null) return truncateResponse!;
    if (!mutationOk) {
      throw HttpException(400, null, message: mutationError ?? '截断会话失败。');
    }
    return SessionResponse(session: SessionDetail(sessionId: sessionId));
  }

  @override
  Future<SessionCompressResponse> compressSession({
    required String sessionId,
    String? focusTopic,
  }) async {
    compressCalls++;
    lastFocusTopic = focusTopic;
    if (mutationThrows != null) throw mutationThrows!;
    if (compressResponse != null) return compressResponse!;
    return SessionCompressResponse(ok: mutationOk, error: mutationError);
  }

  @override
  Future<SessionCompressStatusResponse> startSessionCompression({
    required String sessionId,
    String? focusTopic,
  }) async {
    compressStartCalls++;
    lastCompressFocusTopic = focusTopic;
    if (compressStartError != null) throw compressStartError!;
    if (compressStartResponse != null) return compressStartResponse!;
    return SessionCompressStatusResponse(
      ok: true,
      status: 'running',
      sessionId: sessionId,
    );
  }

  @override
  Future<SessionCompressStatusResponse> compressionStatus(
    String sessionId,
  ) async {
    compressStatusCalls++;
    if (compressStatusError != null) throw compressStatusError!;
    final builder = compressStatusBuilder;
    if (builder != null) return builder(compressStatusCalls);
    if (compressStatusResponse != null) return compressStatusResponse!;
    return SessionCompressStatusResponse(
      ok: true,
      status: 'idle',
      sessionId: sessionId,
    );
  }

  @override
  Future<SessionUndoResponse> undoSession(String sessionId) async {
    undoCalls++;
    if (mutationThrows != null) throw mutationThrows!;
    if (undoResponse != null) return undoResponse!;
    return SessionUndoResponse(ok: mutationOk, error: mutationError);
  }

  @override
  Future<SessionRetryResponse> retrySession(String sessionId) async {
    retryCalls++;
    if (mutationThrows != null) throw mutationThrows!;
    if (retryResponse != null) return retryResponse!;
    if (retryResult != null) {
      return SessionRetryResponse.fromJson(retryResult!);
    }
    return SessionRetryResponse(
      ok: mutationOk,
      error: mutationError,
      lastUserText: '你好',
    );
  }

  @override
  Future<SessionResponse> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) async {
    updateSessionCalls++;
    lastUpdatedWorkspace = workspace;
    lastUpdatedModel = model;
    if (mutationThrows != null) throw mutationThrows!;
    if (updateSessionResponse != null) return updateSessionResponse!;
    if (updateSessionResult != null) {
      return SessionResponse.fromJson(updateSessionResult!);
    }
    return SessionResponse(
      session: SessionDetail(
        sessionId: sessionId,
        workspace: workspace,
        model: model,
        modelProvider: modelProvider,
      ),
    );
  }

  @override
  Future<SessionYoloResponse> getYolo(String sessionId) async {
    getYoloCalls++;
    if (yoloResponse != null) return yoloResponse!;
    if (yoloResult != null) {
      return SessionYoloResponse.fromJson(yoloResult!);
    }
    return const SessionYoloResponse(ok: true, yoloEnabled: false);
  }

  @override
  Future<SessionYoloResponse> setYolo({
    required String sessionId,
    required bool enabled,
  }) async {
    setYoloCalls++;
    lastYoloEnabled = enabled;
    if (setYoloResponse != null) return setYoloResponse!;
    if (setYoloResult != null) {
      return SessionYoloResponse.fromJson(setYoloResult!);
    }
    return SessionYoloResponse(ok: mutationOk, yoloEnabled: enabled);
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
    startStreamCalls++;
    streamIds.add(streamId);
    replaySeqs.add(replayAfterSeq);
    _onEvent = onEvent;
    _onEventId = onEventId;
    _onTransportError = onTransportError;
    _onClosed = onClosed;
  }

  @override
  void stopStream(String streamId) {
    stopStreamCalls++;
    stopStreamIds.add(streamId);
  }

  void Function(SseEvent event)? _onClarifyEvent;
  void Function(String message)? _onClarifyTransportError;
  void Function()? _onClarifyClosed;
  ClarificationPendingResponse? clarifyPendingResponse;
  int startClarifyStreamCalls = 0;
  int stopClarifyStreamCalls = 0;
  int clarifyPendingCalls = 0;

  @override
  Future<ClarificationPendingResponse> clarifyPending(String sessionId) async {
    clarifyPendingCalls++;
    return clarifyPendingResponse ?? const ClarificationPendingResponse();
  }

  @override
  Future<void> startClarifyStream(
    String sessionId, {
    required void Function(SseEvent event) onEvent,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    startClarifyStreamCalls++;
    _onClarifyEvent = onEvent;
    _onClarifyTransportError = onTransportError;
    _onClarifyClosed = onClosed;
  }

  @override
  void stopClarifyStream() {
    stopClarifyStreamCalls++;
    _onClarifyEvent = null;
    _onClarifyTransportError = null;
    _onClarifyClosed = null;
  }

  void emitClarify(SseEvent event) => _onClarifyEvent?.call(event);

  void failClarify(String message) => _onClarifyTransportError?.call(message);

  void closeClarifyStream() => _onClarifyClosed?.call();

  void Function(SseEvent event)? _onApprovalEvent;
  void Function(String message)? _onApprovalTransportError;
  void Function()? _onApprovalClosed;
  ApprovalPendingResponse? approvalPendingResponse;
  int startApprovalStreamCalls = 0;
  int stopApprovalStreamCalls = 0;
  int approvalPendingCalls = 0;

  @override
  Future<ApprovalPendingResponse> approvalPending(String sessionId) async {
    approvalPendingCalls++;
    return approvalPendingResponse ?? const ApprovalPendingResponse();
  }

  @override
  Future<void> startApprovalStream(
    String sessionId, {
    required void Function(SseEvent event) onEvent,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    startApprovalStreamCalls++;
    _onApprovalEvent = onEvent;
    _onApprovalTransportError = onTransportError;
    _onApprovalClosed = onClosed;
  }

  @override
  void stopApprovalStream() {
    stopApprovalStreamCalls++;
    _onApprovalEvent = null;
    _onApprovalTransportError = null;
    _onApprovalClosed = null;
  }

  void emitApproval(SseEvent event) => _onApprovalEvent?.call(event);

  void failApproval(String message) => _onApprovalTransportError?.call(message);

  void closeApprovalStream() => _onApprovalClosed?.call();

  void emit(SseEvent event) => _onEvent?.call(event);

  void emitId(String id) => _onEventId?.call(id);

  void fail(String message) => _onTransportError?.call(message);

  void closeStream() => _onClosed?.call();
}
