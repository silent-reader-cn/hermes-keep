import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import '../utils/uuid.dart';
import 'chat_message.dart';
import 'json_value.dart';
import 'tool_call.dart';

/// 会话列表响应信封（Swift: SessionsResponse）。
class SessionsResponse {
  const SessionsResponse({
    this.sessions,
    this.cliCount,
    this.archivedCount,
    this.serverTime,
    this.serverTz,
  });

  factory SessionsResponse.fromJson(Map<String, Object?> json) {
    return SessionsResponse(
      sessions: optModelList(json, 'sessions', SessionSummary.fromJson),
      cliCount: lossyInt(json, 'cli_count'),
      archivedCount: lossyInt(json, 'archived_count'),
      serverTime: lossyDouble(json, 'server_time'),
      serverTz: lossyString(json, 'server_tz'),
    );
  }

  final List<SessionSummary>? sessions;
  final int? cliCount;
  final int? archivedCount;
  final double? serverTime;
  final String? serverTz;

  @override
  bool operator ==(Object other) {
    return other is SessionsResponse &&
        deepEquals(other.sessions, sessions) &&
        other.cliCount == cliCount &&
        other.archivedCount == archivedCount &&
        other.serverTime == serverTime &&
        other.serverTz == serverTz;
  }

  @override
  int get hashCode => Object.hash(
    deepHash(sessions),
    cliCount,
    archivedCount,
    serverTime,
    serverTz,
  );

  @override
  String toString() => 'SessionsResponse(sessions: ${sessions?.length})';
}

/// 会话搜索响应信封（Swift: SessionSearchResponse）。
class SessionSearchResponse {
  const SessionSearchResponse({this.sessions, this.query, this.count});

  factory SessionSearchResponse.fromJson(Map<String, Object?> json) {
    return SessionSearchResponse(
      sessions: optModelList(json, 'sessions', SessionSummary.fromJson),
      query: lossyString(json, 'query'),
      count: lossyInt(json, 'count'),
    );
  }

  final List<SessionSummary>? sessions;
  final String? query;
  final int? count;

  @override
  bool operator ==(Object other) {
    return other is SessionSearchResponse &&
        deepEquals(other.sessions, sessions) &&
        other.query == query &&
        other.count == count;
  }

  @override
  int get hashCode => Object.hash(deepHash(sessions), query, count);

  @override
  String toString() => 'SessionSearchResponse(sessions: ${sessions?.length})';
}

/// 单个会话响应信封（Swift: SessionResponse）。
///
/// 兼容后端多种返回形态（实机验证：服务端可能返回平坦 `session_id` / `data` 包裹）：
/// 1) `{session: {...}}` 标准嵌套；2) 平坦 `{session_id/id, title, ...}`；
/// 3) `{data: {session: {...}}}` 或 `{data: {session_id, ...}}` 包裹。
class SessionResponse {
  const SessionResponse({this.session});

  factory SessionResponse.fromJson(Map<String, Object?> json) {
    final nested = optModel(json, 'session', SessionDetail.fromJson);
    if (nested != null) return SessionResponse(session: nested);
    final flatId =
        lossyString(json, 'session_id') ??
        lossyString(json, 'id') ??
        lossyString(json, 'sessionId');
    if (flatId != null && flatId.trim().isNotEmpty) {
      try {
        return SessionResponse(session: SessionDetail.fromJson(json));
      } catch (_) {
        return SessionResponse(
          session: SessionDetail(
            sessionId: flatId,
            title: lossyString(json, 'title'),
          ),
        );
      }
    }
    final data = json['data'];
    if (data is Map) {
      final Map<String, Object?> m;
      try {
        m = Map<String, Object?>.from(data);
      } catch (_) {
        // 非 String 键的 Map（手工构造 / 异构 payload）：与 SessionBranchResponse 的
        // 同名解析保持一致，退化为 data 不可用，绝不向上抛 TypeError。
        return const SessionResponse(session: null);
      }
      final dNested = optModel(m, 'session', SessionDetail.fromJson);
      if (dNested != null) return SessionResponse(session: dNested);
      final dFlat =
          lossyString(m, 'session_id') ??
          lossyString(m, 'id') ??
          lossyString(m, 'sessionId');
      if (dFlat != null && dFlat.trim().isNotEmpty) {
        try {
          return SessionResponse(session: SessionDetail.fromJson(m));
        } catch (_) {
          return SessionResponse(
            session: SessionDetail(
              sessionId: dFlat,
              title: lossyString(m, 'title'),
            ),
          );
        }
      }
    }
    return const SessionResponse(session: null);
  }

  final SessionDetail? session;

  @override
  bool operator ==(Object other) =>
      other is SessionResponse && other.session == session;

  @override
  int get hashCode => Object.hashAll([session]);

  @override
  String toString() => 'SessionResponse(session: $session)';
}

/// 会话变更响应信封（Swift: SessionMutationResponse）。
class SessionMutationResponse {
  const SessionMutationResponse({this.ok, this.session, this.error});

  factory SessionMutationResponse.fromJson(Map<String, Object?> json) {
    return SessionMutationResponse(
      ok: lossyBool(json, 'ok'),
      session: optModel(json, 'session', SessionSummary.fromJson),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final SessionSummary? session;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is SessionMutationResponse &&
        other.ok == ok &&
        other.session == session &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, session, error);

  @override
  String toString() => 'SessionMutationResponse(ok: $ok)';
}

/// 项目列表响应信封（Swift: ProjectsResponse）。
class ProjectsResponse {
  const ProjectsResponse({this.projects});

  factory ProjectsResponse.fromJson(Map<String, Object?> json) {
    return ProjectsResponse(
      projects: optModelList(json, 'projects', ProjectSummary.fromJson),
    );
  }

  final List<ProjectSummary>? projects;

  @override
  bool operator ==(Object other) =>
      other is ProjectsResponse && deepEquals(other.projects, projects);

  @override
  int get hashCode => Object.hashAll([deepHash(projects)]);

  @override
  String toString() => 'ProjectsResponse(projects: ${projects?.length})';
}

/// 项目变更响应信封（Swift: ProjectMutationResponse）。
class ProjectMutationResponse {
  const ProjectMutationResponse({this.ok, this.project, this.error});

  factory ProjectMutationResponse.fromJson(Map<String, Object?> json) {
    return ProjectMutationResponse(
      ok: lossyBool(json, 'ok'),
      project: optModel(json, 'project', ProjectSummary.fromJson),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final ProjectSummary? project;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is ProjectMutationResponse &&
        other.ok == ok &&
        other.project == project &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, project, error);

  @override
  String toString() => 'ProjectMutationResponse(ok: $ok)';
}

/// 项目摘要（Swift: ProjectSummary）。`id` = projectId ?? name ?? uuid。
class ProjectSummary {
  const ProjectSummary({this.projectId, this.name, this.color, this.createdAt});

  factory ProjectSummary.fromJson(Map<String, Object?> json) {
    return ProjectSummary(
      projectId: lossyString(json, 'project_id'),
      name: lossyString(json, 'name'),
      color: lossyString(json, 'color'),
      createdAt: lossyDouble(json, 'created_at'),
    );
  }

  final String? projectId;
  final String? name;
  final String? color;
  final double? createdAt;

  String get id => projectId ?? name ?? uuidV4();

  @override
  bool operator ==(Object other) {
    return other is ProjectSummary &&
        other.projectId == projectId &&
        other.name == name &&
        other.color == color &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(projectId, name, color, createdAt);

  @override
  String toString() => 'ProjectSummary(projectId: $projectId, name: $name)';
}

/// 会话分支响应（Swift: SessionBranchResponse）。
class SessionBranchResponse {
  const SessionBranchResponse({
    this.sessionId,
    this.title,
    this.parentSessionId,
    this.error,
  });

  factory SessionBranchResponse.fromJson(Map<String, Object?> json) {
    final raw = json['data'];
    Map<String, Object?>? dataMap;
    if (raw is Map) {
      try {
        dataMap = Map<String, Object?>.from(raw);
      } catch (_) {
        dataMap = null;
      }
    }
    // 兼容平坦 / data 包裹 / 顶层 fallback
    final sid =
        lossyString(json, 'session_id') ??
        (dataMap != null ? lossyString(dataMap, 'session_id') : null) ??
        lossyString(json, 'id') ??
        (dataMap != null ? lossyString(dataMap, 'id') : null);
    final title =
        lossyString(json, 'title') ??
        (dataMap != null ? lossyString(dataMap, 'title') : null);
    final parentId =
        lossyString(json, 'parent_session_id') ??
        (dataMap != null ? lossyString(dataMap, 'parent_session_id') : null);
    // session 嵌套形态（部分后端返回 {session:{session_id}}）
    String? nestedSid;
    String? nestedTitle;
    String? nestedParent;
    final sess = json['session'];
    if (sess is Map) {
      try {
        final m = Map<String, Object?>.from(sess);
        nestedSid = lossyString(m, 'session_id') ?? lossyString(m, 'id');
        nestedTitle = lossyString(m, 'title');
        nestedParent = lossyString(m, 'parent_session_id');
      } catch (_) {}
    }
    if (dataMap != null) {
      final ds = dataMap['session'];
      if (ds is Map) {
        try {
          final m = Map<String, Object?>.from(ds);
          nestedSid ??= lossyString(m, 'session_id') ?? lossyString(m, 'id');
          nestedTitle ??= lossyString(m, 'title');
          nestedParent ??= lossyString(m, 'parent_session_id');
        } catch (_) {}
      }
    }
    return SessionBranchResponse(
      sessionId: sid ?? nestedSid,
      title: title ?? nestedTitle,
      parentSessionId: parentId ?? nestedParent,
      error:
          lossyString(json, 'error') ??
          (dataMap != null ? lossyString(dataMap, 'error') : null),
    );
  }

  final String? sessionId;
  final String? title;
  final String? parentSessionId;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is SessionBranchResponse &&
        other.sessionId == sessionId &&
        other.title == title &&
        other.parentSessionId == parentSessionId &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(sessionId, title, parentSessionId, error);

  @override
  String toString() => 'SessionBranchResponse(sessionId: $sessionId)';
}

/// 会话压缩响应（Swift: SessionCompressResponse）。
class SessionCompressResponse {
  const SessionCompressResponse({
    this.ok,
    this.session,
    this.summary,
    this.focusTopic,
    this.error,
  });

  factory SessionCompressResponse.fromJson(Map<String, Object?> json) {
    return SessionCompressResponse(
      ok: lossyBool(json, 'ok'),
      session: optModel(json, 'session', SessionDetail.fromJson),
      summary: optModel(json, 'summary', SessionCompressionSummary.fromJson),
      focusTopic: lossyString(json, 'focus_topic'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final SessionDetail? session;
  final SessionCompressionSummary? summary;
  final String? focusTopic;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is SessionCompressResponse &&
        other.ok == ok &&
        other.session == session &&
        other.summary == summary &&
        other.focusTopic == focusTopic &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, session, summary, focusTopic, error);

  @override
  String toString() => 'SessionCompressResponse(ok: $ok)';
}

/// 会话压缩摘要（Swift: SessionCompressionSummary）。
class SessionCompressionSummary {
  const SessionCompressionSummary({
    this.headline,
    this.tokenLine,
    this.note,
    this.referenceMessage,
  });

  factory SessionCompressionSummary.fromJson(Map<String, Object?> json) {
    return SessionCompressionSummary(
      headline: lossyString(json, 'headline'),
      tokenLine: lossyString(json, 'token_line'),
      note: lossyString(json, 'note'),
      referenceMessage: lossyString(json, 'reference_message'),
    );
  }

  final String? headline;
  final String? tokenLine;
  final String? note;
  final String? referenceMessage;

  /// tokenLine 按 `→` / `->` 取末段数字（如 `128k -> 42k` → 42）。
  int? get compressedTokenEstimate {
    final line = tokenLine;
    if (line == null || line.isEmpty) return null;
    final byArrow = line.split('\u{2192}').last;
    final trailing = byArrow.split('->').last;
    final digits = trailing.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  @override
  bool operator ==(Object other) {
    return other is SessionCompressionSummary &&
        other.headline == headline &&
        other.tokenLine == tokenLine &&
        other.note == note &&
        other.referenceMessage == referenceMessage;
  }

  @override
  int get hashCode => Object.hash(headline, tokenLine, note, referenceMessage);

  @override
  String toString() => 'SessionCompressionSummary(headline: $headline)';
}

/// 会话撤销响应（Swift: SessionUndoResponse）。
class SessionUndoResponse {
  const SessionUndoResponse({
    this.ok,
    this.removedCount,
    this.removedPreview,
    this.error,
  });

  factory SessionUndoResponse.fromJson(Map<String, Object?> json) {
    return SessionUndoResponse(
      ok: lossyBool(json, 'ok'),
      removedCount: lossyInt(json, 'removed_count'),
      removedPreview: lossyString(json, 'removed_preview'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final int? removedCount;
  final String? removedPreview;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is SessionUndoResponse &&
        other.ok == ok &&
        other.removedCount == removedCount &&
        other.removedPreview == removedPreview &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, removedCount, removedPreview, error);

  @override
  String toString() => 'SessionUndoResponse(ok: $ok)';
}

/// 会话重试响应（Swift: SessionRetryResponse）。
class SessionRetryResponse {
  const SessionRetryResponse({
    this.ok,
    this.lastUserText,
    this.removedCount,
    this.error,
  });

  factory SessionRetryResponse.fromJson(Map<String, Object?> json) {
    return SessionRetryResponse(
      ok: lossyBool(json, 'ok'),
      lastUserText: lossyString(json, 'last_user_text'),
      removedCount: lossyInt(json, 'removed_count'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final String? lastUserText;
  final int? removedCount;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is SessionRetryResponse &&
        other.ok == ok &&
        other.lastUserText == lastUserText &&
        other.removedCount == removedCount &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, lastUserText, removedCount, error);

  @override
  String toString() => 'SessionRetryResponse(ok: $ok)';
}

/// 会话状态响应（Swift: SessionStatusResponse）。
class SessionStatusResponse {
  const SessionStatusResponse({
    this.sessionId,
    this.activeStreamId,
    this.isStreaming,
    this.pendingUserMessage,
    this.error,
  });

  factory SessionStatusResponse.fromJson(Map<String, Object?> json) {
    return SessionStatusResponse(
      sessionId: lossyString(json, 'session_id'),
      activeStreamId: lossyString(json, 'active_stream_id'),
      isStreaming: lossyBool(json, 'is_streaming'),
      pendingUserMessage: lossyString(json, 'pending_user_message'),
      error: lossyString(json, 'error'),
    );
  }

  final String? sessionId;
  final String? activeStreamId;
  final bool? isStreaming;
  final String? pendingUserMessage;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is SessionStatusResponse &&
        other.sessionId == sessionId &&
        other.activeStreamId == activeStreamId &&
        other.isStreaming == isStreaming &&
        other.pendingUserMessage == pendingUserMessage &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    activeStreamId,
    isStreaming,
    pendingUserMessage,
    error,
  );

  @override
  String toString() => 'SessionStatusResponse(sessionId: $sessionId)';
}

/// 会话摘要（Swift: SessionSummary）。`id` = sessionId 非空直接用，
/// 否则 `session-<title或untitled>-<createdAt??updatedAt??lastMessageAt??0>`。
class SessionSummary {
  const SessionSummary({
    this.sessionId,
    this.title,
    this.workspace,
    this.model,
    this.modelProvider,
    this.messageCount,
    this.createdAt,
    this.updatedAt,
    this.lastMessageAt,
    this.pinned,
    this.archived,
    this.projectId,
    this.profile,
    this.inputTokens,
    this.outputTokens,
    this.estimatedCost,
    this.activeStreamId,
    this.isStreaming,
    this.isCliSession,
    this.userMessageCount,
    this.hasPendingUserMessage,
    this.pendingStartedAt,
    this.worktreePath,
    this.sourceTag,
    this.rawSource,
    this.sessionSource,
    this.sourceLabel,
    this.parentSessionId,
    this.relationshipType,
    this.readOnly,
    this.isReadOnly,
    this.matchType,
    this.matchPreview,
  });

  factory SessionSummary.fromJson(Map<String, Object?> json) {
    return SessionSummary(
      sessionId: lossyString(json, 'session_id'),
      title: lossyString(json, 'title'),
      workspace: lossyString(json, 'workspace'),
      model: lossyString(json, 'model'),
      modelProvider: lossyString(json, 'model_provider'),
      messageCount: lossyInt(json, 'message_count'),
      createdAt: lossyDouble(json, 'created_at'),
      updatedAt: lossyDouble(json, 'updated_at'),
      lastMessageAt: lossyDouble(json, 'last_message_at'),
      pinned: lossyBool(json, 'pinned'),
      archived: lossyBool(json, 'archived'),
      projectId: lossyString(json, 'project_id'),
      profile: lossyString(json, 'profile'),
      inputTokens: lossyInt(json, 'input_tokens'),
      outputTokens: lossyInt(json, 'output_tokens'),
      estimatedCost: lossyDouble(json, 'estimated_cost'),
      activeStreamId: lossyString(json, 'active_stream_id'),
      isStreaming: lossyBool(json, 'is_streaming'),
      isCliSession: lossyBool(json, 'is_cli_session'),
      userMessageCount: lossyInt(json, 'user_message_count'),
      hasPendingUserMessage: lossyBool(json, 'has_pending_user_message'),
      pendingStartedAt: lossyDouble(json, 'pending_started_at'),
      worktreePath: lossyString(json, 'worktree_path'),
      sourceTag: lossyString(json, 'source_tag'),
      rawSource: lossyString(json, 'raw_source'),
      sessionSource: lossyString(json, 'session_source'),
      sourceLabel: lossyString(json, 'source_label'),
      parentSessionId: lossyString(json, 'parent_session_id'),
      relationshipType: lossyString(json, 'relationship_type'),
      readOnly: lossyBool(json, 'read_only'),
      isReadOnly: lossyBool(json, 'is_read_only'),
      matchType: lossyString(json, 'match_type'),
      matchPreview: lossyString(json, 'match_preview'),
    );
  }

  /// 从 SessionDetail 构造摘要（对应 Swift `init(from detail:)`）。
  SessionSummary.fromDetail(SessionDetail detail)
    : sessionId = detail.sessionId,
      title = detail.title,
      workspace = detail.workspace,
      model = detail.model,
      modelProvider = detail.modelProvider,
      messageCount = detail.messageCount ?? detail.messages?.length,
      createdAt = detail.createdAt,
      updatedAt = detail.updatedAt,
      lastMessageAt = detail.lastMessageAt,
      pinned = detail.pinned,
      archived = detail.archived,
      projectId = detail.projectId,
      profile = detail.profile,
      inputTokens = detail.inputTokens,
      outputTokens = detail.outputTokens,
      estimatedCost = detail.estimatedCost,
      activeStreamId = detail.activeStreamId,
      isStreaming = null,
      isCliSession = detail.isCliSession,
      userMessageCount = null,
      hasPendingUserMessage =
          _nonEmpty(detail.pendingUserMessage) != null ||
          detail.pendingAttachments?.isNotEmpty == true,
      pendingStartedAt = detail.pendingStartedAt,
      worktreePath = detail.worktreePath,
      sourceTag = detail.sourceTag,
      rawSource = detail.rawSource,
      sessionSource = detail.sessionSource,
      sourceLabel = detail.sourceLabel,
      parentSessionId = detail.parentSessionId,
      relationshipType = detail.relationshipType,
      readOnly = detail.readOnly,
      isReadOnly = detail.isReadOnly,
      matchType = null,
      matchPreview = null;

  final String? sessionId;
  final String? title;
  final String? workspace;
  final String? model;
  final String? modelProvider;
  final int? messageCount;
  final double? createdAt;
  final double? updatedAt;
  final double? lastMessageAt;
  final bool? pinned;
  final bool? archived;
  final String? projectId;
  final String? profile;
  final int? inputTokens;
  final int? outputTokens;
  final double? estimatedCost;
  final String? activeStreamId;
  final bool? isStreaming;
  final bool? isCliSession;
  final int? userMessageCount;
  final bool? hasPendingUserMessage;
  final double? pendingStartedAt;
  final String? worktreePath;
  final String? sourceTag;
  final String? rawSource;
  final String? sessionSource;
  final String? sourceLabel;
  final String? parentSessionId;
  final String? relationshipType;
  final bool? readOnly;
  final bool? isReadOnly;
  final String? matchType;

  /// 搜索命中摘录（`match_preview`，content 命中时由服务端生成）。
  final String? matchPreview;

  String get id {
    final sid = sessionId;
    if (sid != null && sid.isNotEmpty) return sid;
    final titlePart = title?.trim() ?? 'untitled';
    final timestamp = createdAt ?? updatedAt ?? lastMessageAt ?? 0;
    return 'session-$titlePart-$timestamp';
  }

  /// 局部改标题（保留会话列表元数据，对应 Swift `replacingTitle`）。
  SessionSummary replacingTitle(String newTitle) {
    return SessionSummary(
      sessionId: sessionId,
      title: newTitle,
      workspace: workspace,
      model: model,
      modelProvider: modelProvider,
      messageCount: messageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastMessageAt: lastMessageAt,
      pinned: pinned,
      archived: archived,
      projectId: projectId,
      profile: profile,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      estimatedCost: estimatedCost,
      activeStreamId: activeStreamId,
      isStreaming: isStreaming,
      isCliSession: isCliSession,
      userMessageCount: userMessageCount,
      hasPendingUserMessage: hasPendingUserMessage,
      pendingStartedAt: pendingStartedAt,
      worktreePath: worktreePath,
      sourceTag: sourceTag,
      rawSource: rawSource,
      sessionSource: sessionSource,
      sourceLabel: sourceLabel,
      parentSessionId: parentSessionId,
      relationshipType: relationshipType,
      readOnly: readOnly,
      isReadOnly: isReadOnly,
      matchType: matchType,
      matchPreview: matchPreview,
    );
  }

  /// 局部更新流式状态（[isStreaming] 与 [activeStreamId]）。
  SessionSummary withStreaming({
    required bool isStreaming,
    String? activeStreamId,
  }) {
    return SessionSummary(
      sessionId: sessionId,
      title: title,
      workspace: workspace,
      model: model,
      modelProvider: modelProvider,
      messageCount: messageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastMessageAt: lastMessageAt,
      pinned: pinned,
      archived: archived,
      projectId: projectId,
      profile: profile,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      estimatedCost: estimatedCost,
      activeStreamId: isStreaming
          ? (activeStreamId ?? this.activeStreamId ?? 'active')
          : null,
      isStreaming: isStreaming,
      isCliSession: isCliSession,
      userMessageCount: userMessageCount,
      hasPendingUserMessage: hasPendingUserMessage,
      pendingStartedAt: pendingStartedAt,
      worktreePath: worktreePath,
      sourceTag: sourceTag,
      rawSource: rawSource,
      sessionSource: sessionSource,
      sourceLabel: sourceLabel,
      parentSessionId: parentSessionId,
      relationshipType: relationshipType,
      readOnly: readOnly,
      isReadOnly: isReadOnly,
      matchType: matchType,
      matchPreview: matchPreview,
    );
  }

  /// sourceTag/rawSource/sessionSource/sourceLabel/title 任一 normalize 后
  /// 含 `subagent` 字样。
  ///
  /// 实证（2026-08-29，D:/hermes-webui 服务端源码 + 服务端测试 fixture）：
  /// 委派 subagent 子会话在 state.db 中 `source='subagent'`，但服务端
  /// `normalize_agent_session_source` 把 `raw='subagent'` 归一到
  /// `session_source='other'`（agent_sessions.py:74-115，subagent 不在
  /// 归一分支）；`_apply_sidebar_state_db_override_metadata`（models.py:
  /// 5606-5614）只对 `state_db_source=='webui'` 覆盖四 source 字段，subagent
  /// 子会话保留 stale sidecar 旧值（注释明言 sidebar row 由 stale sidecar
  /// 构建）→ 客户端收到的 source 四字段不保证含 'subagent'。而通用标题
  /// 恒为 `Subagent Session`（服务端 fixture test_5306 证实），故把 title
  /// 并入判定（OR），保证「关闭 subagent 开关后按标题可辨识的会话必隐藏」。
  bool get isDelegatedSubagentSession {
    final markers = [
      sourceTag,
      rawSource,
      sessionSource,
      sourceLabel,
      title,
    ].map(_normalizedSourceMarker).whereType<String>();
    return markers.any((marker) => marker.contains('subagent'));
  }

  /// sourceTag/rawSource 含 `claude_code`。
  bool get isClaudeCodeSession {
    return [
      sourceTag,
      rawSource,
    ].map(_normalizedSourceMarker).whereType<String>().contains('claude_code');
  }

  /// 委派子代理会话或 readOnly==true 或 isReadOnly==true。
  bool get isSessionReadOnly {
    return isDelegatedSubagentSession || readOnly == true || isReadOnly == true;
  }

  bool get shouldAppearInSessionList => !isEmptySidebarPlaceholder;

  /// 占位标题且无 sidebar 状态且无消息数。
  bool get isEmptySidebarPlaceholder {
    if (!hasPlaceholderTitle) return false;
    if (hasSidebarState) return false;
    if (hasMessageActivity) return false;
    return (messageCount ?? 0) == 0 && (userMessageCount ?? 0) == 0;
  }

  /// 源自定时 cron 任务（sessionId 小写以 `cron_` 开头，或四个 source 标记含 `cron`）。
  bool get isCronSession {
    final sid = sessionId?.trim().toLowerCase();
    if (sid != null && sid.startsWith('cron_')) return true;
    return [
      sessionSource,
      sourceTag,
      rawSource,
      sourceLabel,
    ].map(_normalizedSourceMarker).whereType<String>().contains('cron');
  }

  bool get hasPlaceholderTitle {
    final normalizedTitle = _nonEmpty(title)?.toLowerCase();
    if (normalizedTitle == null) return true;
    return normalizedTitle == 'untitled' ||
        normalizedTitle == 'untitled session';
  }

  bool get hasSidebarState {
    return pinned == true ||
        isStreaming == true ||
        _nonEmpty(activeStreamId) != null ||
        hasPendingUserMessage == true ||
        pendingStartedAt != null ||
        _nonEmpty(worktreePath) != null;
  }

  bool get hasMessageActivity {
    if (messageCount != null && messageCount! > 0) return true;
    if (userMessageCount != null && userMessageCount! > 0) return true;
    return false;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? _normalizedSourceMarker(String? value) {
    return _nonEmpty(value)?.toLowerCase();
  }

  @override
  bool operator ==(Object other) {
    return other is SessionSummary &&
        other.sessionId == sessionId &&
        other.title == title &&
        other.workspace == workspace &&
        other.model == model &&
        other.modelProvider == modelProvider &&
        other.messageCount == messageCount &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.lastMessageAt == lastMessageAt &&
        other.pinned == pinned &&
        other.archived == archived &&
        other.projectId == projectId &&
        other.profile == profile &&
        other.inputTokens == inputTokens &&
        other.outputTokens == outputTokens &&
        other.estimatedCost == estimatedCost &&
        other.activeStreamId == activeStreamId &&
        other.isStreaming == isStreaming &&
        other.isCliSession == isCliSession &&
        other.userMessageCount == userMessageCount &&
        other.hasPendingUserMessage == hasPendingUserMessage &&
        other.pendingStartedAt == pendingStartedAt &&
        other.worktreePath == worktreePath &&
        other.sourceTag == sourceTag &&
        other.rawSource == rawSource &&
        other.sessionSource == sessionSource &&
        other.sourceLabel == sourceLabel &&
        other.parentSessionId == parentSessionId &&
        other.relationshipType == relationshipType &&
        other.readOnly == readOnly &&
        other.isReadOnly == isReadOnly &&
        other.matchType == matchType;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      sessionId,
      title,
      workspace,
      model,
      modelProvider,
      messageCount,
      createdAt,
      updatedAt,
      lastMessageAt,
      pinned,
      archived,
      projectId,
      profile,
      inputTokens,
      outputTokens,
      estimatedCost,
      activeStreamId,
      isStreaming,
      isCliSession,
      userMessageCount,
      hasPendingUserMessage,
      pendingStartedAt,
      worktreePath,
      sourceTag,
      rawSource,
      sessionSource,
      sourceLabel,
      parentSessionId,
      relationshipType,
      readOnly,
      isReadOnly,
      matchType,
    ]);
  }

  @override
  String toString() => 'SessionSummary(sessionId: $sessionId, title: $title)';

  /// 复制并替换部分字段（手写容错，对齐项目其他模型的 copyWith 惯例）。
  SessionSummary copyWith({
    String? sessionId,
    String? title,
    String? workspace,
    String? model,
    String? modelProvider,
    int? messageCount,
    double? createdAt,
    double? updatedAt,
    double? lastMessageAt,
    bool? pinned,
    bool? archived,
    String? projectId,
    String? profile,
    int? inputTokens,
    int? outputTokens,
    double? estimatedCost,
    String? activeStreamId,
    bool? isStreaming,
    bool? isCliSession,
    int? userMessageCount,
    bool? hasPendingUserMessage,
    double? pendingStartedAt,
    String? worktreePath,
    String? sourceTag,
    String? rawSource,
    String? sessionSource,
    String? sourceLabel,
    String? parentSessionId,
    String? relationshipType,
    bool? readOnly,
    bool? isReadOnly,
    String? matchType,
    String? matchPreview,
  }) {
    return SessionSummary(
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      workspace: workspace ?? this.workspace,
      model: model ?? this.model,
      modelProvider: modelProvider ?? this.modelProvider,
      messageCount: messageCount ?? this.messageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      projectId: projectId ?? this.projectId,
      profile: profile ?? this.profile,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      activeStreamId: activeStreamId ?? this.activeStreamId,
      isStreaming: isStreaming ?? this.isStreaming,
      isCliSession: isCliSession ?? this.isCliSession,
      userMessageCount: userMessageCount ?? this.userMessageCount,
      hasPendingUserMessage:
          hasPendingUserMessage ?? this.hasPendingUserMessage,
      pendingStartedAt: pendingStartedAt ?? this.pendingStartedAt,
      worktreePath: worktreePath ?? this.worktreePath,
      sourceTag: sourceTag ?? this.sourceTag,
      rawSource: rawSource ?? this.rawSource,
      sessionSource: sessionSource ?? this.sessionSource,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      parentSessionId: parentSessionId ?? this.parentSessionId,
      relationshipType: relationshipType ?? this.relationshipType,
      readOnly: readOnly ?? this.readOnly,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      matchType: matchType ?? this.matchType,
      matchPreview: matchPreview ?? this.matchPreview,
    );
  }
}

/// 自动化会话可见性配置（Swift `AutomatedSessionVisibility`）。纯 UI 配置类。
class AutomatedSessionVisibility {
  const AutomatedSessionVisibility({
    required this.showsCron,
    required this.showsCli,
    this.showsClaudeCode = true,
    this.showsSubagents = false,
  });

  /// 显示全部种类（显式 opt-in 与测试用）。
  static const AutomatedSessionVisibility showAll = AutomatedSessionVisibility(
    showsCron: true,
    showsCli: true,
    showsClaudeCode: true,
    showsSubagents: true,
  );

  final bool showsCron;
  final bool showsCli;
  final bool showsClaudeCode;
  final bool showsSubagents;

  /// 该会话在此开关组合下是否应保持可见。
  bool shows(SessionSummary session) {
    if (session.isDelegatedSubagentSession && !showsSubagents) return false;
    if (session.isCronSession && !showsCron) return false;
    if (session.isCliSession == true && !showsCli) return false;
    if (session.isClaudeCodeSession && !showsClaudeCode) return false;
    return true;
  }

  @override
  bool operator ==(Object other) {
    return other is AutomatedSessionVisibility &&
        other.showsCron == showsCron &&
        other.showsCli == showsCli &&
        other.showsClaudeCode == showsClaudeCode &&
        other.showsSubagents == showsSubagents;
  }

  @override
  int get hashCode =>
      Object.hash(showsCron, showsCli, showsClaudeCode, showsSubagents);

  @override
  String toString() {
    return 'AutomatedSessionVisibility(showsCron: $showsCron, showsCli: $showsCli, '
        'showsClaudeCode: $showsClaudeCode, showsSubagents: $showsSubagents)';
  }
}

/// 会话详情（Swift: SessionDetail）。
///
/// 字段 = SessionSummary 全部字段（除 matchType、hasPendingUserMessage 外）
/// + 下列专属字段（严格按 models_spec.md §4.4）。
class SessionDetail {
  const SessionDetail({
    this.sessionId,
    this.title,
    this.workspace,
    this.model,
    this.modelProvider,
    this.messageCount,
    this.createdAt,
    this.updatedAt,
    this.lastMessageAt,
    this.pinned,
    this.archived,
    this.projectId,
    this.profile,
    this.inputTokens,
    this.outputTokens,
    this.estimatedCost,
    this.activeStreamId,
    this.isStreaming,
    this.isCliSession,
    this.userMessageCount,
    this.pendingStartedAt,
    this.worktreePath,
    this.sourceTag,
    this.rawSource,
    this.sessionSource,
    this.sourceLabel,
    this.parentSessionId,
    this.relationshipType,
    this.readOnly,
    this.isReadOnly,
    this.pendingUserMessage,
    this.pendingAttachments,
    this.contextLength,
    this.thresholdTokens,
    this.lastPromptTokens,
    this.messages,
    this.toolCalls,
    this.messagesTruncated,
    this.messagesOffset,
    this.compressionAnchorVisibleIdx,
    this.compressionAnchorMessageKey,
    this.compressionAnchorSummary,
  });

  factory SessionDetail.fromJson(Map<String, Object?> json) {
    return SessionDetail(
      sessionId: lossyString(json, 'session_id'),
      title: lossyString(json, 'title'),
      workspace: lossyString(json, 'workspace'),
      model: lossyString(json, 'model'),
      modelProvider: lossyString(json, 'model_provider'),
      messageCount: lossyInt(json, 'message_count'),
      createdAt: lossyDouble(json, 'created_at'),
      updatedAt: lossyDouble(json, 'updated_at'),
      lastMessageAt: lossyDouble(json, 'last_message_at'),
      pinned: lossyBool(json, 'pinned'),
      archived: lossyBool(json, 'archived'),
      projectId: lossyString(json, 'project_id'),
      profile: lossyString(json, 'profile'),
      inputTokens: lossyInt(json, 'input_tokens'),
      outputTokens: lossyInt(json, 'output_tokens'),
      estimatedCost: lossyDouble(json, 'estimated_cost'),
      activeStreamId: lossyString(json, 'active_stream_id'),
      isStreaming: lossyBool(json, 'is_streaming'),
      isCliSession: lossyBool(json, 'is_cli_session'),
      userMessageCount: lossyInt(json, 'user_message_count'),
      pendingStartedAt: lossyDouble(json, 'pending_started_at'),
      worktreePath: lossyString(json, 'worktree_path'),
      sourceTag: lossyString(json, 'source_tag'),
      rawSource: lossyString(json, 'raw_source'),
      sessionSource: lossyString(json, 'session_source'),
      sourceLabel: lossyString(json, 'source_label'),
      parentSessionId: lossyString(json, 'parent_session_id'),
      relationshipType: lossyString(json, 'relationship_type'),
      readOnly: lossyBool(json, 'read_only'),
      isReadOnly: lossyBool(json, 'is_read_only'),
      pendingUserMessage: lossyString(json, 'pending_user_message'),
      pendingAttachments: optJsonValueList(json, 'pending_attachments'),
      contextLength:
          firstKey(json, ['context_length', 'contextLength'], lossyInt) ??
          lossyInt(json, 'context_length'),
      thresholdTokens:
          firstKey(json, ['threshold_tokens', 'thresholdTokens'], lossyInt) ??
          lossyInt(json, 'threshold_tokens'),
      lastPromptTokens:
          firstKey(json, [
            'last_prompt_tokens',
            'lastPromptTokens',
          ], lossyInt) ??
          lossyInt(json, 'last_prompt_tokens'),
      messages: _decodeMessagesTolerantly(json),
      toolCalls: _decodeToolCallsTolerantly(json),
      messagesTruncated: firstKey(json, [
        '_messages_truncated',
        '_messagesTruncated',
        'messages_truncated',
      ], lossyBool),
      messagesOffset: firstKey(json, [
        '_messages_offset',
        '_messagesOffset',
        'messages_offset',
      ], lossyInt),
      compressionAnchorVisibleIdx: firstKey(json, [
        'compression_anchor_visible_idx',
        'compressionAnchorVisibleIdx',
      ], lossyInt),
      compressionAnchorMessageKey: firstKeyModel(json, [
        'compression_anchor_message_key',
        'compressionAnchorMessageKey',
      ], CompressionAnchorMessageKey.fromJson),
      compressionAnchorSummary: firstKey(json, [
        'compression_anchor_summary',
        'compressionAnchorSummary',
      ], lossyString),
    );
  }

  final String? sessionId;
  final String? title;
  final String? workspace;
  final String? model;
  final String? modelProvider;
  final int? messageCount;
  final double? createdAt;
  final double? updatedAt;
  final double? lastMessageAt;
  final bool? pinned;
  final bool? archived;
  final String? projectId;
  final String? profile;
  final int? inputTokens;
  final int? outputTokens;
  final double? estimatedCost;
  final String? activeStreamId;
  final bool? isStreaming;
  final bool? isCliSession;
  final int? userMessageCount;
  final double? pendingStartedAt;
  final String? worktreePath;
  final String? sourceTag;
  final String? rawSource;
  final String? sessionSource;
  final String? sourceLabel;
  final String? parentSessionId;
  final String? relationshipType;
  final bool? readOnly;
  final bool? isReadOnly;
  final String? pendingUserMessage;
  final List<JsonValue>? pendingAttachments;
  final int? contextLength;
  final int? thresholdTokens;
  final int? lastPromptTokens;
  final List<ChatMessage>? messages;
  final List<PersistedToolCall>? toolCalls;
  final bool? messagesTruncated;
  final int? messagesOffset;
  final int? compressionAnchorVisibleIdx;
  final CompressionAnchorMessageKey? compressionAnchorMessageKey;
  final String? compressionAnchorSummary;

  String get id {
    final sid = sessionId;
    if (sid != null && sid.isNotEmpty) return sid;
    final titlePart = title?.trim() ?? 'untitled';
    final timestamp = createdAt ?? updatedAt ?? lastMessageAt ?? 0;
    return 'session-$titlePart-$timestamp';
  }

  /// 安全地把任意 Map 转成 `Map<String, Object?>`。
  ///
  /// 键含非 String 时返回 null 而**不是抛 TypeError** —— 对齐 `lossy_json.dart`
  /// 「绝不 throw」的容错口径，由调用方降级到慢路径处理。
  /// （裸 `Map<String, Object?>.from(raw)` 对非 String 键会直接抛 TypeError，
  /// 直穿 fromJson 让整个响应解析失败。）
  static Map<String, Object?>? _toStringKeyedMap(Map<Object?, Object?> raw) {
    try {
      return Map<String, Object?>.from(raw);
    } catch (_) {
      return null;
    }
  }

  /// messages 容错解码（同 ChatMessage.attachments 的两级兜底模式）。
  static List<ChatMessage>? _decodeMessagesTolerantly(
    Map<String, Object?> json,
  ) {
    final raw = json['messages'];
    if (raw is! List) return null;

    var fastOk = true;
    final fast = <ChatMessage>[];
    for (final element in raw) {
      final asMap = element is Map
          ? _toStringKeyedMap(element as Map<Object?, Object?>)
          : null;
      if (asMap == null) {
        // 不是 Map，或键非 String（后者交由慢路径按 JsonValue 重新解码）
        fastOk = false;
        break;
      }
      fast.add(ChatMessage.fromJson(asMap));
    }
    if (fastOk) return fast;

    final slow = <ChatMessage>[];
    for (final element in raw) {
      final value = JsonValue.fromJson(element);
      if (value is JsonObject) {
        slow.add(
          ChatMessage.fromJson(
            Map<String, Object?>.from(value.toJson() as Map),
          ),
        );
      }
    }
    return slow.isEmpty ? null : slow;
  }

  /// toolCalls 容错解码（同 messages 的两级兜底模式）。
  static List<PersistedToolCall>? _decodeToolCallsTolerantly(
    Map<String, Object?> json,
  ) {
    final raw = json['tool_calls'];
    if (raw is! List) return null;

    var fastOk = true;
    final fast = <PersistedToolCall>[];
    for (final element in raw) {
      final asMap = element is Map
          ? _toStringKeyedMap(element as Map<Object?, Object?>)
          : null;
      if (asMap == null) {
        fastOk = false;
        break;
      }
      fast.add(PersistedToolCall.fromJson(asMap));
    }
    if (fastOk) return fast;

    final slow = <PersistedToolCall>[];
    for (final element in raw) {
      final value = JsonValue.fromJson(element);
      if (value is JsonObject) {
        slow.add(
          PersistedToolCall.fromJson(
            Map<String, Object?>.from(value.toJson() as Map),
          ),
        );
      }
    }
    return slow.isEmpty ? null : slow;
  }

  /// 多键嵌套模型尝试（对应 Swift `A ?? B` 的 optModel 版本）。
  static T? firstKeyModel<T>(
    Map<String, Object?> json,
    List<String> keys,
    T Function(Map<String, Object?>) fromJson,
  ) {
    for (final key in keys) {
      final value = optModel(json, key, fromJson);
      if (value != null) return value;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is SessionDetail &&
        other.sessionId == sessionId &&
        other.title == title &&
        other.workspace == workspace &&
        other.model == model &&
        other.modelProvider == modelProvider &&
        other.messageCount == messageCount &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.lastMessageAt == lastMessageAt &&
        other.pinned == pinned &&
        other.archived == archived &&
        other.projectId == projectId &&
        other.profile == profile &&
        other.inputTokens == inputTokens &&
        other.outputTokens == outputTokens &&
        other.estimatedCost == estimatedCost &&
        other.activeStreamId == activeStreamId &&
        other.isStreaming == isStreaming &&
        other.isCliSession == isCliSession &&
        other.userMessageCount == userMessageCount &&
        other.pendingStartedAt == pendingStartedAt &&
        other.worktreePath == worktreePath &&
        other.sourceTag == sourceTag &&
        other.rawSource == rawSource &&
        other.sessionSource == sessionSource &&
        other.sourceLabel == sourceLabel &&
        other.parentSessionId == parentSessionId &&
        other.relationshipType == relationshipType &&
        other.readOnly == readOnly &&
        other.isReadOnly == isReadOnly &&
        other.pendingUserMessage == pendingUserMessage &&
        deepEquals(other.pendingAttachments, pendingAttachments) &&
        other.contextLength == contextLength &&
        other.thresholdTokens == thresholdTokens &&
        other.lastPromptTokens == lastPromptTokens &&
        deepEquals(other.messages, messages) &&
        deepEquals(other.toolCalls, toolCalls) &&
        other.messagesTruncated == messagesTruncated &&
        other.messagesOffset == messagesOffset &&
        other.compressionAnchorVisibleIdx == compressionAnchorVisibleIdx &&
        other.compressionAnchorMessageKey == compressionAnchorMessageKey &&
        other.compressionAnchorSummary == compressionAnchorSummary;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      sessionId,
      title,
      workspace,
      model,
      modelProvider,
      messageCount,
      createdAt,
      updatedAt,
      lastMessageAt,
      pinned,
      archived,
      projectId,
      profile,
      inputTokens,
      outputTokens,
      estimatedCost,
      activeStreamId,
      isStreaming,
      isCliSession,
      userMessageCount,
      pendingStartedAt,
      worktreePath,
      sourceTag,
      rawSource,
      sessionSource,
      sourceLabel,
      parentSessionId,
      relationshipType,
      readOnly,
      isReadOnly,
      pendingUserMessage,
      deepHash(pendingAttachments),
      contextLength,
      thresholdTokens,
      lastPromptTokens,
      deepHash(messages),
      deepHash(toolCalls),
      messagesTruncated,
      messagesOffset,
      compressionAnchorVisibleIdx,
      compressionAnchorMessageKey,
      compressionAnchorSummary,
    ]);
  }

  @override
  String toString() => 'SessionDetail(sessionId: $sessionId, title: $title)';
}

/// 压缩锚点消息键（Swift `CompressionAnchorMessageKey`）。
class CompressionAnchorMessageKey {
  const CompressionAnchorMessageKey({
    this.role,
    this.ts,
    this.text,
    this.attachments,
  });

  factory CompressionAnchorMessageKey.fromJson(Map<String, Object?> json) {
    return CompressionAnchorMessageKey(
      role: lossyString(json, 'role'),
      ts: lossyDouble(json, 'ts'),
      text: lossyString(json, 'text'),
      attachments: lossyInt(json, 'attachments'),
    );
  }

  final String? role;
  final double? ts;
  final String? text;
  final int? attachments;

  @override
  bool operator ==(Object other) {
    return other is CompressionAnchorMessageKey &&
        other.role == role &&
        other.ts == ts &&
        other.text == text &&
        other.attachments == attachments;
  }

  @override
  int get hashCode => Object.hash(role, ts, text, attachments);

  @override
  String toString() => 'CompressionAnchorMessageKey(role: $role, ts: $ts)';
}
