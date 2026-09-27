import 'dart:async';

import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

/// 可配置的 [SessionListApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空会话；测试可按需配置 [sessions] / [searchResults] / 各方法抛错，
/// 并通过计数器断言调用次数与参数。
class FakeSessionListApi implements SessionListApi {
  FakeSessionListApi({List<SessionSummary>? sessions})
    : sessions = sessions ?? [];

  /// `fetchSessions` 返回的会话（普通模式列表）。
  List<SessionSummary> sessions;

  /// `fetchSessions` 抛出的异常（非 null 时优先于 [sessions]）。
  Object? fetchError;

  /// 控制 [fetchError] 抛出的次数上限（-1 = 无限，默认保持经典行为）。
  ///
  /// 用于自动重登用例：先抛 1 次 401 触发重登，重登后恢复正常——
  /// 例如 `fetchErrorCap = 1` 时首次 fetch 抛错、第二次起成功。
  int fetchErrorCap = -1;

  int _fetchErrorsThrown = 0;

  /// 非 null 时 `fetchSessions` 挂起等待该 gate（测试加载态用）。
  Completer<void>? fetchGate;

  /// 远程搜索命中表（query → 结果）。
  final Map<String, List<SessionSummary>> searchResults = {};

  /// `searchSessions` 抛出的异常。
  Object? searchError;

  /// `createSession` 返回的新会话（sessionId 为空 → 模拟服务器未返回 ID）。
  SessionSummary createdSession = const SessionSummary(
    sessionId: 'new-1',
    title: '新会话',
  );

  /// 最近一次 `createSession` 调用的 workspace 参数。
  String? lastCreatedWorkspace;

  /// `fetchWorkspaces` 返回的工作区列表。
  List<WorkspaceRoot> workspaces = const [];

  /// `fetchWorkspaces` 抛出的异常。
  Object? workspacesError;

  int fetchWorkspacesCount = 0;

  /// `branchSession` 返回的结果（sessionId 为空 → 模拟失败）。
  SessionBranchResponse branchResponse = const SessionBranchResponse(
    sessionId: 'branch-1',
    title: '分支副本',
  );

  /// 各变更方法抛出的异常（非 null 时模拟失败）。
  Object? pinError;
  Object? archiveError;
  Object? deleteError;
  Object? branchError;
  Object? createError;

  int fetchCount = 0;
  int searchCount = 0;
  int createCount = 0;

  /// 已调用的变更操作记录（含参数，如 `pin s1:true`）。
  final List<String> pinCalls = [];
  final List<String> archiveCalls = [];
  final List<String> deleteCalls = [];
  final List<String> branchCalls = [];
  final List<String> searchQueries = [];
  final List<String> moveCalls = [];

  /// `fetchSessions` 是否最近一次以 includeArchived=true 调用。
  bool lastFetchedArchived = false;

  /// `moveSession` 抛出的异常。
  Object? moveError;

  /// 变更调用闸门（#174）：**先**在测试里 `gate(id)` 预注册，再启动操作，
  /// 调用一到该条即挂起 —— 于是「已发出 / 未发出」的边界完全确定，
  /// 不依赖微任务时序。留空时完全不挂起（对既有用例零影响）。
  final Map<String, Completer<void>> gates = {};

  /// 这些会话 id 的变更在闸门放行后抛 `ApiException`（模拟部分失败）。
  final Set<String> failingIds = {};

  /// 预注册 / 取用某个 id 的闸门（同一 id 始终同一实例）。
  Completer<void> gate(String id) => gates.putIfAbsent(id, Completer<void>.new);

  /// 清空全部闸门（同一 id 需要做第二轮操作时调用）。
  void resetGates() => gates.clear();

  /// 记录后、判错前：等闸门 → 按 [failingIds] 抛错。
  Future<void> _waitGateAndMaybeFail(String sessionId) async {
    final g = gates[sessionId];
    if (g != null) await g.future;
    if (failingIds.contains(sessionId)) {
      throw HttpException(500, 'fake failure');
    }
  }

  @override
  Future<SessionsResponse> fetchSessions({
    bool includeArchived = false,
    int? archivedLimit,
  }) async {
    fetchCount++;
    lastFetchedArchived = includeArchived;
    final error = fetchError;
    if (error != null &&
        (fetchErrorCap < 0 || _fetchErrorsThrown < fetchErrorCap)) {
      _fetchErrorsThrown++;
      throw error;
    }
    final gate = fetchGate;
    if (gate != null) await gate.future;
    final list = includeArchived
        ? sessions.where((s) => s.archived == true).toList()
        : sessions.where((s) => s.archived != true).toList();
    return SessionsResponse(
      sessions: list,
      archivedCount: sessions.where((s) => s.archived == true).length,
    );
  }

  @override
  Future<SessionSearchResponse> searchSessions({required String query}) async {
    searchCount++;
    searchQueries.add(query);
    final error = searchError;
    if (error != null) throw error;
    return SessionSearchResponse(
      sessions: searchResults[query] ?? const [],
      query: query,
      count: (searchResults[query] ?? const []).length,
    );
  }

  @override
  Future<SessionSummary> createSession({String? workspace}) async {
    createCount++;
    lastCreatedWorkspace = workspace;
    final error = createError;
    if (error != null) throw error;
    if (workspace != null) {
      return SessionSummary(
        sessionId: createdSession.sessionId,
        title: createdSession.title,
        workspace: workspace,
        pinned: createdSession.pinned,
        lastMessageAt: createdSession.lastMessageAt,
      );
    }
    return createdSession;
  }

  @override
  Future<List<WorkspaceRoot>> fetchWorkspaces() async {
    fetchWorkspacesCount++;
    final error = workspacesError;
    if (error != null) throw error;
    return workspaces;
  }

  @override
  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    pinCalls.add('$sessionId:$pinned');
    final error = pinError;
    if (error != null) throw error;
    return const SessionMutationResponse(ok: true);
  }

  @override
  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    archiveCalls.add('$sessionId:$archived');
    await _waitGateAndMaybeFail(sessionId);
    final error = archiveError;
    if (error != null) throw error;
    return const SessionMutationResponse(ok: true);
  }

  @override
  Future<SessionMutationResponse> deleteSession(String sessionId) async {
    deleteCalls.add(sessionId);
    await _waitGateAndMaybeFail(sessionId);
    final error = deleteError;
    if (error != null) throw error;
    return const SessionMutationResponse(ok: true);
  }

  @override
  Future<SessionMutationResponse> moveSession({
    required String sessionId,
    String? projectId,
  }) async {
    moveCalls.add('$sessionId:${projectId ?? 'null'}');
    await _waitGateAndMaybeFail(sessionId);
    final error = moveError;
    if (error != null) throw error;
    return const SessionMutationResponse(ok: true);
  }

  @override
  Future<SessionBranchResponse> branchSession(String sessionId) async {
    branchCalls.add(sessionId);
    final error = branchError;
    if (error != null) throw error;
    return branchResponse;
  }

  /// 单会话状态预设返回（sessionId -> response）。
  final Map<String, SessionStatusResponse> statusResponses = {};
  Object? statusError;
  final List<String> statusCalls = [];

  @override
  Future<SessionStatusResponse> fetchSessionStatus(String sessionId) async {
    statusCalls.add(sessionId);
    final error = statusError;
    if (error != null) throw error;
    final found = sessions.cast<SessionSummary?>().firstWhere(
      (s) => s?.sessionId == sessionId,
      orElse: () => null,
    );
    return statusResponses[sessionId] ??
        SessionStatusResponse(
          sessionId: sessionId,
          isStreaming: found?.isStreaming,
          activeStreamId: found?.activeStreamId,
        );
  }
}
