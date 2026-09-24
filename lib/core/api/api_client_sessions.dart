import 'api_client.dart';
import 'endpoints.dart';
import '../models/approval.dart';
import '../models/session.dart';

/// sessions 域方法（18 个端点）+ projects 域（4 个端点）。
extension ApiClientSessions on ApiClient {
  /// 会话列表全量返回超时：120s（#111；其余端点保持默认 60s）。
  ///
  /// 服务端会话库全量重建（缓存失效时同步进行，数百个 JSON、本机实测解析
  /// 9.3s 起步，叠加 reconcile / CLI 合并 / 序列化 + frp 出口）在弱网下会
  /// 顶穿默认 60s，把冷启动首屏变成 receiveTimeout 红屏。列表是只读全量
  /// 接口，放宽超时不影响写操作的失败可见性。
  static const sessionsListTimeout = Duration(seconds: 120);

  /// GET /api/sessions（`include_archived` 为 opt-in，`archived_limit` 仅随其发送）。
  ///
  /// 并发去重：同参数的并发请求共享一次网络往返（冷启动会话列表 + 托盘菜单
  /// 会同时触发，见 [ApiClient.coalesceRequest]）。
  Future<SessionsResponse> sessions({
    bool includeArchived = false,
    int? archivedLimit,
  }) {
    return coalesceRequest(
      'sessions-list:${includeArchived ? 1 : 0}:${archivedLimit ?? '-'}',
      () async {
        final json = await sendJson(
          Endpoint.sessions(
            includeArchived: includeArchived,
            archivedLimit: archivedLimit,
          ),
          timeout: sessionsListTimeout,
        );
        return SessionsResponse.fromJson(_asMap(json));
      },
    );
  }

  /// GET /api/sessions/search?q=&content=&depth= → SessionSearchResponse。
  Future<SessionSearchResponse> searchSessions({
    required String query,
    bool content = true,
    int depth = 5,
  }) async {
    final json = await sendJson(
      Endpoint.sessionsSearch(query: query, content: content, depth: depth),
    );
    return SessionSearchResponse.fromJson(_asMap(json));
  }

  /// GET /api/session?session_id=&messages=… → SessionResponse {session}。
  Future<SessionResponse> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) async {
    final json = await sendJson(
      Endpoint.session(
        sessionId: sessionId,
        includeMessages: includeMessages,
        messageLimit: messageLimit,
        messageBefore: messageBefore,
        expandRenderable: expandRenderable,
      ),
    );
    return SessionResponse.fromJson(_asMap(json));
  }

  /// GET /api/session/status?session_id= → SessionStatusResponse。
  Future<SessionStatusResponse> sessionStatus(String sessionId) async {
    final json = await sendJson(Endpoint.sessionStatus(sessionId));
    return SessionStatusResponse.fromJson(_asMap(json));
  }

  /// POST /api/session/new {workspace?, model?, model_provider?, profile?}。
  Future<SessionResponse> createSession({
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
  }) async {
    final json = await sendJson(
      Endpoint.newSession,
      method: 'POST',
      body: {
        'workspace': ?workspace,
        'model': ?model,
        'model_provider': ?modelProvider,
        'profile': ?profile,
      },
    );
    return SessionResponse.fromJson(_asMap(json));
  }

  Future<SessionMutationResponse> renameSession({
    required String sessionId,
    required String title,
  }) async {
    final json = await sendJson(
      Endpoint.renameSession,
      method: 'POST',
      body: {'session_id': sessionId, 'title': title},
    );
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  Future<SessionMutationResponse> deleteSession(String sessionId) async {
    final json = await sendJson(
      Endpoint.deleteSession,
      method: 'POST',
      body: {'session_id': sessionId},
    );
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    final json = await sendJson(
      Endpoint.pinSession,
      method: 'POST',
      body: {'session_id': sessionId, 'pinned': pinned},
    );
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    final json = await sendJson(
      Endpoint.archiveSession,
      method: 'POST',
      body: {'session_id': sessionId, 'archived': archived},
    );
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  Future<SessionBranchResponse> branchSession({
    required String sessionId,
    int? keepCount,
    String? title,
  }) async {
    final json = await sendJson(
      Endpoint.branchSession,
      method: 'POST',
      body: {
        'session_id': sessionId,
        'keep_count': ?keepCount,
        'title': ?title,
      },
    );
    return SessionBranchResponse.fromJson(_asMap(json));
  }

  Future<SessionCompressResponse> compressSession({
    required String sessionId,
    String? focusTopic,
  }) async {
    final json = await sendJson(
      Endpoint.compressSession,
      method: 'POST',
      body: {'session_id': sessionId, 'focus_topic': ?focusTopic},
    );
    return SessionCompressResponse.fromJson(_asMap(json));
  }

  /// POST /api/session/compress/start {session_id, focus_topic?}（#156 异步压缩）。
  ///
  /// 立刻返回（后台线程执行）；若该会话已有 running job 则**幂等复用**并原样
  /// 返回其状态。可能被拒：会话仍在流式（409）、agent runtime 过期（409，
  /// 响应带 `type: agent_runtime_stale` 且 `retryable: true`）。
  Future<SessionCompressStatusResponse> startSessionCompression({
    required String sessionId,
    String? focusTopic,
  }) async {
    final json = await sendJson(
      Endpoint.startSessionCompression,
      method: 'POST',
      body: {'session_id': sessionId, 'focus_topic': ?focusTopic},
    );
    return SessionCompressStatusResponse.fromJson(_asMap(json));
  }

  /// GET /api/session/compress/status?session_id= → SessionCompressStatusResponse。
  ///
  /// 无 job 时服务端返回 `{ok: true, status: "idle"}`（**不是 404**）。
  Future<SessionCompressStatusResponse> compressionStatus(
    String sessionId,
  ) async {
    final json = await sendJson(Endpoint.sessionCompressionStatus(sessionId));
    return SessionCompressStatusResponse.fromJson(_asMap(json));
  }

  Future<SessionUndoResponse> undoSession(String sessionId) async {
    final json = await sendJson(
      Endpoint.undoSession,
      method: 'POST',
      body: {'session_id': sessionId},
    );
    return SessionUndoResponse.fromJson(_asMap(json));
  }

  Future<SessionRetryResponse> retrySession(String sessionId) async {
    final json = await sendJson(
      Endpoint.retrySession,
      method: 'POST',
      body: {'session_id': sessionId},
    );
    return SessionRetryResponse.fromJson(_asMap(json));
  }

  Future<SessionResponse> truncateSession({
    required String sessionId,
    required int keepCount,
  }) async {
    final json = await sendJson(
      Endpoint.truncateSession,
      method: 'POST',
      body: {'session_id': sessionId, 'keep_count': keepCount},
    );
    return SessionResponse.fromJson(_asMap(json));
  }

  Future<SessionResponse> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) async {
    final json = await sendJson(
      Endpoint.updateSession,
      method: 'POST',
      body: {
        'session_id': sessionId,
        'workspace': ?workspace,
        'model': ?model,
        'model_provider': ?modelProvider,
      },
    );
    return SessionResponse.fromJson(_asMap(json));
  }

  Future<SessionMutationResponse> moveSession({
    required String sessionId,
    String? projectId,
  }) async {
    final json = await sendJson(
      Endpoint.moveSession,
      method: 'POST',
      body: {'session_id': sessionId, 'project_id': ?projectId},
    );
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  /// GET /api/session/yolo（查状态，session_id 可选）。
  Future<SessionYoloResponse> sessionYolo([String? sessionId]) async {
    final json = await sendJson(Endpoint.sessionYolo(sessionId));
    return SessionYoloResponse.fromJson(_asMap(json));
  }

  /// POST /api/session/yolo {session_id, enabled}（设状态，无 query）。
  Future<SessionYoloResponse> setSessionYolo({
    required String sessionId,
    required bool enabled,
  }) async {
    final json = await sendJson(
      Endpoint.sessionYolo(),
      method: 'POST',
      body: {'session_id': sessionId, 'enabled': enabled},
    );
    return SessionYoloResponse.fromJson(_asMap(json));
  }

  /// GET /api/session/export?session_id=&format=html|json — 文件下载（非 JSON），
  /// Accept=`*/*`；文件名由调用方用 [SessionExportFilename] 从响应头解析。
  Future<ApiByteResponse> exportSession({
    required String sessionId,
    required String format,
    Duration? timeout,
  }) => sendDataReturningResponse(
    Endpoint.exportSession(sessionId: sessionId, format: format),
    method: 'GET',
    accept: '*/*',
    timeout: timeout,
  );

  // -------------------------------------------------------------------------
  // projects（1.3）— 4 个
  // -------------------------------------------------------------------------

  Future<ProjectsResponse> projects() async {
    final json = await sendJson(Endpoint.projects);
    return ProjectsResponse.fromJson(_asMap(json));
  }

  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async {
    final json = await sendJson(
      Endpoint.createProject,
      method: 'POST',
      body: {'name': name, 'color': ?color},
    );
    return ProjectMutationResponse.fromJson(_asMap(json));
  }

  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async {
    final json = await sendJson(
      Endpoint.renameProject,
      method: 'POST',
      body: {'project_id': projectId, 'name': name, 'color': ?color},
    );
    return ProjectMutationResponse.fromJson(_asMap(json));
  }

  Future<ProjectMutationResponse> deleteProject(String projectId) async {
    final json = await sendJson(
      Endpoint.deleteProject,
      method: 'POST',
      body: {'project_id': projectId},
    );
    return ProjectMutationResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});


/// 从 `Content-Disposition` 解析导出文件名（对齐 SessionExportFile.filename）。
///
/// 优先级：`filename="…"`（或裸 token）→ 会话标题（净化）+ 扩展名 →
/// `hermes-<session-id>.<ext>`。
class SessionExportFilename {
  const SessionExportFilename._();

  static String resolve({
    required String? contentDisposition,
    required String? fallbackTitle,
    required String sessionId,
    required String format,
  }) {
    final fromHeader = _filenameParameter(contentDisposition);
    final sanitized = fromHeader == null ? null : _sanitizeFilename(fromHeader);
    if (sanitized != null) return sanitized;

    final titleStem = fallbackTitle == null
        ? null
        : _sanitizeFilenameStem(fallbackTitle);
    if (titleStem != null) return '$titleStem.$format';

    final idStem = _sanitizeFilenameStem(sessionId) ?? 'session';
    return 'hermes-$idStem.$format';
  }

  static String? _filenameParameter(String? contentDisposition) {
    if (contentDisposition == null) return null;
    for (final rawParameter in contentDisposition.split(';').skip(1)) {
      final parameter = rawParameter.trim();
      final eq = parameter.indexOf('=');
      if (eq <= 0) continue;
      final key = parameter.substring(0, eq).trim().toLowerCase();
      if (key != 'filename') continue;
      var value = parameter.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _sanitizeFilename(String raw) {
    final normalized = raw.replaceAll('\\', '/');
    final lastComponent = normalized.split('/').last;
    final cleaned = _replaceUnsafeCharacters(lastComponent);
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return null;
    return cleaned;
  }

  static String? _sanitizeFilenameStem(String raw) {
    final cleaned = _replaceUnsafeCharacters(raw);
    if (cleaned.isEmpty) return null;
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80);
  }

  static String _replaceUnsafeCharacters(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final isUnsafe =
          ch == '/' || ch == '\\' || ch == ':' || ch == '\n' || ch == '\r';
      buffer.write(isUnsafe ? ' ' : ch);
    }
    return buffer
        .toString()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }
}
