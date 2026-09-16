import '../utils/equality.dart';
import '../utils/lossy_json.dart';

// ============================================================================
// 14.1 配置 / 看板列表
// ============================================================================

/// Kanban 桥配置（Swift: KanbanConfiguration）。
/// 每个字段保持可选：服务器加字段/改名绝不导致整体解码失败。
class KanbanConfiguration {
  const KanbanConfiguration({
    this.columns,
    this.assignees,
    this.defaultTenant,
    this.laneByProfile,
    this.includeArchivedByDefault,
    this.renderMarkdown,
    this.readOnly,
  });

  factory KanbanConfiguration.fromJson(Map<String, Object?> json) {
    return KanbanConfiguration(
      columns: optStringList(json, 'columns'),
      assignees: _decodeAssignees(json['assignees']),
      defaultTenant: lossyString(json, 'default_tenant'),
      laneByProfile: lossyBool(json, 'lane_by_profile'),
      includeArchivedByDefault: lossyBool(json, 'include_archived_by_default'),
      renderMarkdown: lossyBool(json, 'render_markdown'),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final List<String>? columns;
  final List<String>? assignees;
  final String? defaultTenant;
  final bool? laneByProfile;
  final bool? includeArchivedByDefault;
  final bool? renderMarkdown;
  final bool? readOnly;

  /// assignees 特殊：先试 `List<KanbanAssigneeValue>`（元素可为字符串或
  /// {name} 对象）取 name 列表；任一元素两者都不是 → 整数组 null
  /// （对齐 Swift 数组解码失败语义）。
  static List<String>? _decodeAssignees(Object? raw) {
    if (raw is! List) return null;
    final result = <String>[];
    for (final element in raw) {
      final name = kanbanAssigneeName(element);
      if (name == null) return null;
      result.add(name);
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanConfiguration &&
        _listEquals(other.columns, columns) &&
        _listEquals(other.assignees, assignees) &&
        other.defaultTenant == defaultTenant &&
        other.laneByProfile == laneByProfile &&
        other.includeArchivedByDefault == includeArchivedByDefault &&
        other.renderMarkdown == renderMarkdown &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(columns ?? const []),
    Object.hashAll(assignees ?? const []),
    defaultTenant,
    laneByProfile,
    includeArchivedByDefault,
    renderMarkdown,
    readOnly,
  );

  @override
  String toString() => 'KanbanConfiguration(columns: $columns)';
}

/// 解析 Kanban 成员名（对应 Swift `KanbanAssigneeValue`）：元素是字符串 → 自身；
/// 是对象 → `name`（lossyString）。
String? kanbanAssigneeName(Object? value) {
  if (value is String) return value;
  if (value is Map) {
    // 非 String 键会让 Map.from 抛 TypeError；本函数是容错解析入口，降级返回 null
    //（对齐 lossy_json.dart「绝不 throw」口径）。
    try {
      return lossyString(Map<String, Object?>.from(value), 'name');
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// 看板列表响应信封（Swift: KanbanBoardsResponse）。
class KanbanBoardsResponse {
  const KanbanBoardsResponse({this.boards, this.current, this.readOnly});

  factory KanbanBoardsResponse.fromJson(Map<String, Object?> json) {
    return KanbanBoardsResponse(
      boards: optModelList(json, 'boards', KanbanBoard.fromJson),
      current: lossyString(json, 'current'),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final List<KanbanBoard>? boards;
  final String? current;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanBoardsResponse &&
        deepEquals(other.boards, boards) &&
        other.current == current &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(deepHash(boards), current, readOnly);

  @override
  String toString() => 'KanbanBoardsResponse(current: $current)';
}

/// 看板（Swift: KanbanBoard）。
class KanbanBoard {
  const KanbanBoard({
    this.slug,
    this.name,
    this.description,
    this.icon,
    this.color,
    this.isCurrent,
    this.total,
    this.counts,
    this.readOnly,
  });

  factory KanbanBoard.fromJson(Map<String, Object?> json) {
    return KanbanBoard(
      slug: lossyString(json, 'slug'),
      name: lossyString(json, 'name'),
      description: lossyString(json, 'description'),
      icon: lossyString(json, 'icon'),
      color: lossyString(json, 'color'),
      isCurrent: lossyBool(json, 'is_current'),
      total: lossyInt(json, 'total'),
      counts: _decodeIntMap(json['counts']),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final String? slug;
  final String? name;
  final String? description;
  final String? icon;
  final String? color;
  final bool? isCurrent;
  final int? total;
  final Map<String, int>? counts;
  final bool? readOnly;

  static Map<String, int>? _decodeIntMap(Object? raw) {
    if (raw is! Map) return null;
    try {
      final result = <String, int>{};
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is int) {
          result[entry.key.toString()] = value;
        } else if (value is double &&
            value.isFinite &&
            value >= -9223372036854775808.0 &&
            value < 9223372036854775808.0) {
          result[entry.key.toString()] = value.truncate().toInt();
        } else {
          return null;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanBoard &&
        other.slug == slug &&
        other.name == name &&
        other.description == description &&
        other.icon == icon &&
        other.color == color &&
        other.isCurrent == isCurrent &&
        other.total == total &&
        deepEquals(other.counts, counts) &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(
    slug,
    name,
    description,
    icon,
    color,
    isCurrent,
    total,
    deepHash(counts),
    readOnly,
  );

  @override
  String toString() => 'KanbanBoard(slug: $slug, name: $name)';
}

/// 看板变更信封（Swift: KanbanBoardMutationEnvelope）。
class KanbanBoardMutationEnvelope {
  const KanbanBoardMutationEnvelope({this.board, this.current, this.readOnly});

  factory KanbanBoardMutationEnvelope.fromJson(Map<String, Object?> json) {
    return KanbanBoardMutationEnvelope(
      board: optModel(json, 'board', KanbanBoard.fromJson),
      current: lossyString(json, 'current'),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final KanbanBoard? board;
  final String? current;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanBoardMutationEnvelope &&
        other.board == board &&
        other.current == current &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(board, current, readOnly);

  @override
  String toString() => 'KanbanBoardMutationEnvelope(board: $board)';
}

// ============================================================================
// 14.2 看板快照 / 列 / 卡
// ============================================================================

/// 看板快照（Swift: KanbanBoardSnapshot）。`latestEventID` 显式 camel 键。
class KanbanBoardSnapshot {
  const KanbanBoardSnapshot({
    this.columns,
    this.tenants,
    this.assignees,
    this.filters,
    this.changed,
    this.latestEventID,
    this.readOnly,
  });

  factory KanbanBoardSnapshot.fromJson(Map<String, Object?> json) {
    return KanbanBoardSnapshot(
      columns: optModelList(json, 'columns', KanbanColumn.fromJson),
      tenants: optStringList(json, 'tenants'),
      assignees: optStringList(json, 'assignees'),
      filters: optModel(json, 'filters', KanbanAppliedFilters.fromJson),
      changed: lossyBool(json, 'changed'),
      latestEventID: lossyInt(json, 'latestEventId'),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final List<KanbanColumn>? columns;
  final List<String>? tenants;
  final List<String>? assignees;
  final KanbanAppliedFilters? filters;
  final bool? changed;
  final int? latestEventID;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanBoardSnapshot &&
        deepEquals(other.columns, columns) &&
        _listEquals(other.tenants, tenants) &&
        _listEquals(other.assignees, assignees) &&
        other.filters == filters &&
        other.changed == changed &&
        other.latestEventID == latestEventID &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(
    deepHash(columns),
    Object.hashAll(tenants ?? const []),
    Object.hashAll(assignees ?? const []),
    filters,
    changed,
    latestEventID,
    readOnly,
  );

  @override
  String toString() => 'KanbanBoardSnapshot(changed: $changed)';
}

/// 看板列（Swift: KanbanColumn）。cards 的键是 `tasks`。
class KanbanColumn {
  const KanbanColumn({this.name, this.cards});

  factory KanbanColumn.fromJson(Map<String, Object?> json) {
    return KanbanColumn(
      name: lossyString(json, 'name'),
      cards: optModelList(json, 'tasks', KanbanCard.fromJson),
    );
  }

  final String? name;
  final List<KanbanCard>? cards;

  @override
  bool operator ==(Object other) =>
      other is KanbanColumn &&
      other.name == name &&
      deepEquals(other.cards, cards);

  @override
  int get hashCode => Object.hash(name, deepHash(cards));

  @override
  String toString() => 'KanbanColumn(name: $name, cards: ${cards?.length})';
}

/// 已应用的过滤条件（Swift: KanbanAppliedFilters）。
class KanbanAppliedFilters {
  const KanbanAppliedFilters({
    this.tenant,
    this.assignee,
    this.includeArchived,
    this.onlyMine,
    this.profile,
  });

  factory KanbanAppliedFilters.fromJson(Map<String, Object?> json) {
    return KanbanAppliedFilters(
      tenant: lossyString(json, 'tenant'),
      assignee: lossyString(json, 'assignee'),
      includeArchived: lossyBool(json, 'include_archived'),
      onlyMine: lossyBool(json, 'only_mine'),
      profile: lossyString(json, 'profile'),
    );
  }

  final String? tenant;
  final String? assignee;
  final bool? includeArchived;
  final bool? onlyMine;
  final String? profile;

  @override
  bool operator ==(Object other) {
    return other is KanbanAppliedFilters &&
        other.tenant == tenant &&
        other.assignee == assignee &&
        other.includeArchived == includeArchived &&
        other.onlyMine == onlyMine &&
        other.profile == profile;
  }

  @override
  int get hashCode =>
      Object.hash(tenant, assignee, includeArchived, onlyMine, profile);

  @override
  String toString() => 'KanbanAppliedFilters(assignee: $assignee)';
}

// ============================================================================
// 14.3 KanbanCard
// ============================================================================

/// 看板卡状态（Swift `KanbanStatus`）。**类而非枚举**，需保留未知值。
class KanbanStatus {
  const KanbanStatus(this.rawValue);

  final String rawValue;

  bool get isSupported => const {
    'triage',
    'todo',
    'blocked',
    'ready',
    'running',
    'done',
    'archived',
  }.contains(rawValue.toLowerCase());

  @override
  bool operator ==(Object other) =>
      other is KanbanStatus && other.rawValue == rawValue;

  @override
  int get hashCode => Object.hashAll([rawValue]);

  @override
  String toString() => 'KanbanStatus($rawValue)';
}

/// 看板卡陈旧度（Swift `KanbanStaleness`）。
enum KanbanStaleness { none, warning, critical }

/// 看板卡（Swift: KanbanCard）。
class KanbanCard {
  const KanbanCard({
    this.cardID,
    this.title,
    this.status,
    this.assignee,
    this.body,
    this.tenant,
    this.priority,
    this.commentCount,
    this.linkCounts,
    this.ageSeconds,
    this.createdAt,
    this.updatedAt,
    this.workspaceKind,
    this.workspacePath,
    this.skills,
    this.maxRuntimeSeconds,
    this.currentRunID,
    this.claimLock,
    this.claimExpires,
    this.workerID,
  });

  factory KanbanCard.fromJson(Map<String, Object?> json) {
    final statusRaw = lossyString(json, 'status');
    return KanbanCard(
      cardID: lossyString(json, 'id'),
      title: lossyString(json, 'title'),
      status: statusRaw == null ? null : KanbanStatus(statusRaw),
      assignee: lossyString(json, 'assignee'),
      body: lossyString(json, 'body'),
      tenant: lossyString(json, 'tenant'),
      priority: lossyInt(json, 'priority'),
      commentCount: lossyInt(json, 'comment_count'),
      linkCounts: optModel(json, 'link_counts', KanbanLinkCounts.fromJson),
      ageSeconds: lossyDouble(json, 'age_seconds'),
      createdAt: lossyString(json, 'created_at'),
      updatedAt: lossyString(json, 'updated_at'),
      workspaceKind: lossyString(json, 'workspace_kind'),
      workspacePath: lossyString(json, 'workspace_path'),
      skills: optStringList(json, 'skills'),
      maxRuntimeSeconds: lossyInt(json, 'max_runtime_seconds'),
      currentRunID: lossyString(json, 'currentRunId'),
      claimLock: lossyString(json, 'claim_lock'),
      claimExpires: lossyString(json, 'claim_expires'),
      workerID: lossyString(json, 'workerPid'),
    );
  }

  final String? cardID;
  final String? title;
  final KanbanStatus? status;
  final String? assignee;
  final String? body;
  final String? tenant;
  final int? priority;
  final int? commentCount;
  final KanbanLinkCounts? linkCounts;
  final double? ageSeconds;
  final String? createdAt;
  final String? updatedAt;
  final String? workspaceKind;
  final String? workspacePath;
  final List<String>? skills;
  final int? maxRuntimeSeconds;
  final String? currentRunID;
  final String? claimLock;
  final String? claimExpires;
  final String? workerID;

  /// 陈旧度（running ≥3600s critical / ≥600s warning；ready ≥3600s warning；
  /// blocked ≥86400s critical / ≥3600s warning；无 status/age → none）。
  KanbanStaleness get staleness {
    final age = ageSeconds;
    final rawStatus = status?.rawValue;
    if (age == null || rawStatus == null) return KanbanStaleness.none;
    switch (rawStatus) {
      case 'running':
        return age >= 3600
            ? KanbanStaleness.critical
            : age >= 600
            ? KanbanStaleness.warning
            : KanbanStaleness.none;
      case 'ready':
        return age >= 3600 ? KanbanStaleness.warning : KanbanStaleness.none;
      case 'blocked':
        return age >= 86400
            ? KanbanStaleness.critical
            : age >= 3600
            ? KanbanStaleness.warning
            : KanbanStaleness.none;
      default:
        return KanbanStaleness.none;
    }
  }

  /// copyWith 换状态；非 running 时清空 currentRunID/claimLock/claimExpires/workerID。
  KanbanCard replacingStatus(String newStatus) {
    return KanbanCard(
      cardID: cardID,
      title: title,
      status: KanbanStatus(newStatus),
      assignee: assignee,
      body: body,
      tenant: tenant,
      priority: priority,
      commentCount: commentCount,
      linkCounts: linkCounts,
      ageSeconds: ageSeconds,
      createdAt: createdAt,
      updatedAt: updatedAt,
      workspaceKind: workspaceKind,
      workspacePath: workspacePath,
      skills: skills,
      maxRuntimeSeconds: maxRuntimeSeconds,
      currentRunID: newStatus == 'running' ? currentRunID : null,
      claimLock: newStatus == 'running' ? claimLock : null,
      claimExpires: newStatus == 'running' ? claimExpires : null,
      workerID: newStatus == 'running' ? workerID : null,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanCard &&
        other.cardID == cardID &&
        other.title == title &&
        other.status == status &&
        other.assignee == assignee &&
        other.body == body &&
        other.tenant == tenant &&
        other.priority == priority &&
        other.commentCount == commentCount &&
        other.linkCounts == linkCounts &&
        other.ageSeconds == ageSeconds &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.workspaceKind == workspaceKind &&
        other.workspacePath == workspacePath &&
        _listEquals(other.skills, skills) &&
        other.maxRuntimeSeconds == maxRuntimeSeconds &&
        other.currentRunID == currentRunID &&
        other.claimLock == claimLock &&
        other.claimExpires == claimExpires &&
        other.workerID == workerID;
  }

  @override
  int get hashCode => Object.hash(
    cardID,
    title,
    status,
    assignee,
    body,
    tenant,
    priority,
    commentCount,
    linkCounts,
    ageSeconds,
    createdAt,
    updatedAt,
    workspaceKind,
    workspacePath,
    Object.hashAll(skills ?? const []),
    maxRuntimeSeconds,
    currentRunID,
    claimLock,
    claimExpires,
    workerID,
  );

  @override
  String toString() => 'KanbanCard(cardID: $cardID, title: $title)';
}

// ============================================================================
// 14.4 卡片详情 / 评论 / 事件 / 运行 / 日志
// ============================================================================

/// 卡片详情信封（Swift: KanbanCardDetailEnvelope）。card 的键是 `task`。
class KanbanCardDetailEnvelope {
  const KanbanCardDetailEnvelope({
    this.card,
    this.comments,
    this.events,
    this.links,
    this.runs,
    this.readOnly,
  });

  factory KanbanCardDetailEnvelope.fromJson(Map<String, Object?> json) {
    return KanbanCardDetailEnvelope(
      card: optModel(json, 'task', KanbanCard.fromJson),
      comments: optModelList(json, 'comments', KanbanComment.fromJson),
      events: optModelList(json, 'events', KanbanDetailEvent.fromJson),
      links: optModel(json, 'links', KanbanDependencyLinks.fromJson),
      runs: optModelList(json, 'runs', KanbanDispatchRun.fromJson),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final KanbanCard? card;
  final List<KanbanComment>? comments;
  final List<KanbanDetailEvent>? events;
  final KanbanDependencyLinks? links;
  final List<KanbanDispatchRun>? runs;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanCardDetailEnvelope &&
        other.card == card &&
        deepEquals(other.comments, comments) &&
        deepEquals(other.events, events) &&
        other.links == links &&
        deepEquals(other.runs, runs) &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(
    card,
    deepHash(comments),
    deepHash(events),
    links,
    deepHash(runs),
    readOnly,
  );

  @override
  String toString() => 'KanbanCardDetailEnvelope(card: $card)';
}

/// 卡片变更信封（Swift: KanbanCardMutationEnvelope）。card 的键是 `task`。
class KanbanCardMutationEnvelope {
  const KanbanCardMutationEnvelope({this.card, this.readOnly});

  factory KanbanCardMutationEnvelope.fromJson(Map<String, Object?> json) {
    return KanbanCardMutationEnvelope(
      card: optModel(json, 'task', KanbanCard.fromJson),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final KanbanCard? card;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanCardMutationEnvelope &&
        other.card == card &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(card, readOnly);

  @override
  String toString() => 'KanbanCardMutationEnvelope(card: $card)';
}

/// 看板评论（Swift: KanbanComment）。
class KanbanComment {
  const KanbanComment({
    this.commentID,
    this.cardID,
    this.author,
    this.body,
    this.createdAt,
  });

  factory KanbanComment.fromJson(Map<String, Object?> json) {
    return KanbanComment(
      commentID: lossyString(json, 'id'),
      cardID: lossyString(json, 'taskId'),
      author: lossyString(json, 'author'),
      body: lossyString(json, 'body'),
      createdAt: lossyString(json, 'created_at'),
    );
  }

  final String? commentID;
  final String? cardID;
  final String? author;
  final String? body;
  final String? createdAt;

  /// commentID ?? [cardID, author, createdAt, body].join('|')。
  String get presentationID {
    final id = commentID;
    if (id != null) return id;
    return [cardID, author, createdAt, body].whereType<String>().join('|');
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanComment &&
        other.commentID == commentID &&
        other.cardID == cardID &&
        other.author == author &&
        other.body == body &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(commentID, cardID, author, body, createdAt);

  @override
  String toString() => 'KanbanComment(commentID: $commentID)';
}

/// 卡片详情事件（Swift: KanbanDetailEvent）。payload 只保留展示所需字段。
class KanbanDetailEvent {
  const KanbanDetailEvent({
    this.eventID,
    this.cardID,
    this.runID,
    this.kind,
    this.createdAt,
    this.payload,
  });

  factory KanbanDetailEvent.fromJson(Map<String, Object?> json) {
    return KanbanDetailEvent(
      eventID: lossyString(json, 'id'),
      cardID: lossyString(json, 'taskId'),
      runID: lossyString(json, 'run_id'),
      kind: lossyString(json, 'kind'),
      createdAt: lossyString(json, 'created_at'),
      payload: optModel(json, 'payload', KanbanDetailEventPayload.fromJson),
    );
  }

  final String? eventID;
  final String? cardID;
  final String? runID;
  final String? kind;
  final String? createdAt;
  final KanbanDetailEventPayload? payload;

  /// eventID ?? [cardID, runID, kind, createdAt].join('|')。
  String get presentationID {
    final id = eventID;
    if (id != null) return id;
    return [cardID, runID, kind, createdAt].whereType<String>().join('|');
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanDetailEvent &&
        other.eventID == eventID &&
        other.cardID == cardID &&
        other.runID == runID &&
        other.kind == kind &&
        other.createdAt == createdAt &&
        other.payload == payload;
  }

  @override
  int get hashCode =>
      Object.hash(eventID, cardID, runID, kind, createdAt, payload);

  @override
  String toString() => 'KanbanDetailEvent(eventID: $eventID, kind: $kind)';
}

/// 详情事件载荷（Swift: KanbanDetailEventPayload）。
class KanbanDetailEventPayload {
  const KanbanDetailEventPayload({
    this.status,
    this.reason,
    this.summary,
    this.fields,
  });

  factory KanbanDetailEventPayload.fromJson(Map<String, Object?> json) {
    return KanbanDetailEventPayload(
      status: lossyString(json, 'status'),
      reason: lossyString(json, 'reason'),
      summary: lossyString(json, 'summary'),
      fields: optStringList(json, 'fields'),
    );
  }

  final String? status;
  final String? reason;
  final String? summary;
  final List<String>? fields;

  @override
  bool operator ==(Object other) {
    return other is KanbanDetailEventPayload &&
        other.status == status &&
        other.reason == reason &&
        other.summary == summary &&
        _listEquals(other.fields, fields);
  }

  @override
  int get hashCode =>
      Object.hash(status, reason, summary, Object.hashAll(fields ?? const []));

  @override
  String toString() => 'KanbanDetailEventPayload(status: $status)';
}

/// 依赖链接（Swift: KanbanDependencyLinks）。parents / children 显式键。
class KanbanDependencyLinks {
  const KanbanDependencyLinks({this.prerequisites, this.dependents});

  factory KanbanDependencyLinks.fromJson(Map<String, Object?> json) {
    return KanbanDependencyLinks(
      prerequisites: optStringList(json, 'parents'),
      dependents: optStringList(json, 'children'),
    );
  }

  final List<String>? prerequisites;
  final List<String>? dependents;

  @override
  bool operator ==(Object other) {
    return other is KanbanDependencyLinks &&
        _listEquals(other.prerequisites, prerequisites) &&
        _listEquals(other.dependents, dependents);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(prerequisites ?? const []),
    Object.hashAll(dependents ?? const []),
  );

  @override
  String toString() => 'KanbanDependencyLinks(prerequisites: $prerequisites)';
}

/// 派发运行（Swift: KanbanDispatchRun）。runID / finishedAt / workerID 双键。
class KanbanDispatchRun {
  const KanbanDispatchRun({
    this.runID,
    this.status,
    this.outcome,
    this.summary,
    this.error,
    this.startedAt,
    this.finishedAt,
    this.workerID,
    this.logTail,
  });

  factory KanbanDispatchRun.fromJson(Map<String, Object?> json) {
    return KanbanDispatchRun(
      runID: firstKey(json, ['id', 'runId'], lossyString),
      status: lossyString(json, 'status'),
      outcome: lossyString(json, 'outcome'),
      summary: lossyString(json, 'summary'),
      error: lossyString(json, 'error'),
      startedAt: lossyString(json, 'started_at'),
      finishedAt: firstKey(json, ['endedAt', 'finished_at'], lossyString),
      workerID: firstKey(json, ['workerPid', 'worker'], lossyString),
      logTail: lossyString(json, 'log_tail'),
    );
  }

  final String? runID;
  final String? status;
  final String? outcome;
  final String? summary;
  final String? error;
  final String? startedAt;
  final String? finishedAt;
  final String? workerID;
  final String? logTail;

  /// runID ?? [status, outcome, startedAt, finishedAt].join('|')。
  String get presentationID {
    final id = runID;
    if (id != null) return id;
    return [
      status,
      outcome,
      startedAt,
      finishedAt,
    ].whereType<String>().join('|');
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanDispatchRun &&
        other.runID == runID &&
        other.status == status &&
        other.outcome == outcome &&
        other.summary == summary &&
        other.error == error &&
        other.startedAt == startedAt &&
        other.finishedAt == finishedAt &&
        other.workerID == workerID &&
        other.logTail == logTail;
  }

  @override
  int get hashCode => Object.hash(
    runID,
    status,
    outcome,
    summary,
    error,
    startedAt,
    finishedAt,
    workerID,
    logTail,
  );

  @override
  String toString() => 'KanbanDispatchRun(runID: $runID, status: $status)';
}

/// 工作线程日志（Swift: KanbanWorkerLog）。`path` 字段刻意不保留。
class KanbanWorkerLog {
  const KanbanWorkerLog({
    this.cardID,
    this.exists,
    this.sizeBytes,
    this.content,
    this.truncated,
  });

  factory KanbanWorkerLog.fromJson(Map<String, Object?> json) {
    return KanbanWorkerLog(
      cardID: lossyString(json, 'taskId'),
      exists: lossyBool(json, 'exists'),
      sizeBytes: lossyInt(json, 'size_bytes'),
      content: lossyString(json, 'content'),
      truncated: lossyBool(json, 'truncated'),
    );
  }

  final String? cardID;
  final bool? exists;
  final int? sizeBytes;
  final String? content;
  final bool? truncated;

  @override
  bool operator ==(Object other) {
    return other is KanbanWorkerLog &&
        other.cardID == cardID &&
        other.exists == exists &&
        other.sizeBytes == sizeBytes &&
        other.content == content &&
        other.truncated == truncated;
  }

  @override
  int get hashCode =>
      Object.hash(cardID, exists, sizeBytes, content, truncated);

  @override
  String toString() => 'KanbanWorkerLog(cardID: $cardID)';
}

/// 添加评论响应（Swift: KanbanAddCommentResponse）。commentId 显式键。
class KanbanAddCommentResponse {
  const KanbanAddCommentResponse({this.ok, this.commentID, this.readOnly});

  factory KanbanAddCommentResponse.fromJson(Map<String, Object?> json) {
    return KanbanAddCommentResponse(
      ok: lossyBool(json, 'ok'),
      commentID: lossyString(json, 'commentId'),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final bool? ok;
  final String? commentID;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanAddCommentResponse &&
        other.ok == ok &&
        other.commentID == commentID &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(ok, commentID, readOnly);

  @override
  String toString() => 'KanbanAddCommentResponse(ok: $ok)';
}

/// 链接计数（Swift: KanbanLinkCounts）。
class KanbanLinkCounts {
  const KanbanLinkCounts({this.parents, this.children});

  factory KanbanLinkCounts.fromJson(Map<String, Object?> json) {
    return KanbanLinkCounts(
      parents: lossyInt(json, 'parents'),
      children: lossyInt(json, 'children'),
    );
  }

  final int? parents;
  final int? children;

  @override
  bool operator ==(Object other) =>
      other is KanbanLinkCounts &&
      other.parents == parents &&
      other.children == children;

  @override
  int get hashCode => Object.hash(parents, children);

  @override
  String toString() =>
      'KanbanLinkCounts(parents: $parents, children: $children)';
}

/// 看板统计（Swift: KanbanStats）。
class KanbanStats {
  const KanbanStats({this.total, this.byStatus, this.byAssignee});

  factory KanbanStats.fromJson(Map<String, Object?> json) {
    return KanbanStats(
      total: lossyInt(json, 'total'),
      byStatus: KanbanBoard._decodeIntMap(json['by_status']),
      byAssignee: KanbanBoard._decodeIntMap(json['by_assignee']),
    );
  }

  final int? total;
  final Map<String, int>? byStatus;
  final Map<String, int>? byAssignee;

  @override
  bool operator ==(Object other) {
    return other is KanbanStats &&
        other.total == total &&
        deepEquals(other.byStatus, byStatus) &&
        deepEquals(other.byAssignee, byAssignee);
  }

  @override
  int get hashCode =>
      Object.hash(total, deepHash(byStatus), deepHash(byAssignee));

  @override
  String toString() => 'KanbanStats(total: $total)';
}

/// 成员历史（Swift: KanbanAssigneeHistory）。assignees 用 KanbanAssigneeValue 解析。
class KanbanAssigneeHistory {
  const KanbanAssigneeHistory({this.assignees});

  factory KanbanAssigneeHistory.fromJson(Map<String, Object?> json) {
    return KanbanAssigneeHistory(
      assignees: KanbanConfiguration._decodeAssignees(json['assignees']),
    );
  }

  final List<String>? assignees;

  @override
  bool operator ==(Object other) =>
      other is KanbanAssigneeHistory && _listEquals(other.assignees, assignees);

  @override
  int get hashCode => Object.hashAll([Object.hashAll(assignees ?? const [])]);

  @override
  String toString() => 'KanbanAssigneeHistory(assignees: $assignees)';
}

// ============================================================================
// 14.5 事件流 / 批量操作 / dispatch
// ============================================================================

/// 事件流信封（Swift: KanbanEventsEnvelope）。latestEventId 显式键。
class KanbanEventsEnvelope {
  const KanbanEventsEnvelope({
    this.events,
    this.cursor,
    this.latestEventID,
    this.readOnly,
  });

  factory KanbanEventsEnvelope.fromJson(Map<String, Object?> json) {
    return KanbanEventsEnvelope(
      events: optModelList(json, 'events', KanbanEvent.fromJson),
      cursor: lossyInt(json, 'cursor'),
      latestEventID: lossyInt(json, 'latestEventId'),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final List<KanbanEvent>? events;
  final int? cursor;
  final int? latestEventID;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanEventsEnvelope &&
        deepEquals(other.events, events) &&
        other.cursor == cursor &&
        other.latestEventID == latestEventID &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode =>
      Object.hash(deepHash(events), cursor, latestEventID, readOnly);

  @override
  String toString() => 'KanbanEventsEnvelope(cursor: $cursor)';
}

/// 流事件（Swift: KanbanEvent）。payload 刻意不保留。
class KanbanEvent {
  const KanbanEvent({
    this.eventID,
    this.cardID,
    this.runID,
    this.kind,
    this.createdAt,
  });

  factory KanbanEvent.fromJson(Map<String, Object?> json) {
    return KanbanEvent(
      eventID: firstKey(json, ['id', 'eventId', 'event_id'], lossyInt),
      cardID: firstKey(json, [
        'taskId',
        'task_id',
        'cardId',
        'card_id',
      ], lossyString),
      runID: firstKey(json, ['runId', 'run_id'], lossyString),
      kind: lossyString(json, 'kind'),
      createdAt: firstKey(json, [
        'created_at',
        'createdAt',
        'timestamp',
      ], lossyInt),
    );
  }

  final int? eventID;
  final String? cardID;
  final String? runID;
  final String? kind;
  final int? createdAt;

  Map<String, Object?> toJson() {
    return {
      if (eventID != null) 'id': eventID,
      if (cardID != null) 'taskId': cardID,
      if (runID != null) 'runId': runID,
      if (kind != null) 'kind': kind,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanEvent &&
        other.eventID == eventID &&
        other.cardID == cardID &&
        other.runID == runID &&
        other.kind == kind &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(eventID, cardID, runID, kind, createdAt);

  @override
  String toString() => 'KanbanEvent(eventID: $eventID, kind: $kind)';
}

/// 批量操作信封（Swift: KanbanBulkActionEnvelope）。
class KanbanBulkActionEnvelope {
  const KanbanBulkActionEnvelope({this.results, this.readOnly});

  factory KanbanBulkActionEnvelope.fromJson(Map<String, Object?> json) {
    return KanbanBulkActionEnvelope(
      results: optModelList(json, 'results', KanbanBulkActionResult.fromJson),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final List<KanbanBulkActionResult>? results;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanBulkActionEnvelope &&
        deepEquals(other.results, results) &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode => Object.hash(deepHash(results), readOnly);

  @override
  String toString() => 'KanbanBulkActionEnvelope(results: ${results?.length})';
}

/// 批量操作结果（Swift: KanbanBulkActionResult）。
/// **整元素非对象时三字段全 null**（Swift 用 try? 容器）。
class KanbanBulkActionResult {
  const KanbanBulkActionResult({this.cardID, this.ok, this.error});

  factory KanbanBulkActionResult.fromJson(Object? json) {
    if (json is! Map) return const KanbanBulkActionResult();
    final map = Map<String, Object?>.from(json);
    return KanbanBulkActionResult(
      cardID: lossyString(map, 'id'),
      ok: lossyBool(map, 'ok'),
      error: lossyString(map, 'error'),
    );
  }

  final String? cardID;
  final bool? ok;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is KanbanBulkActionResult &&
        other.cardID == cardID &&
        other.ok == ok &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(cardID, ok, error);

  @override
  String toString() => 'KanbanBulkActionResult(cardID: $cardID, ok: $ok)';
}

/// 依赖变更信封（Swift: KanbanDependencyMutationEnvelope）。
/// parentId / childId 显式键。
class KanbanDependencyMutationEnvelope {
  const KanbanDependencyMutationEnvelope({
    this.ok,
    this.changed,
    this.prerequisiteID,
    this.dependentID,
    this.readOnly,
  });

  factory KanbanDependencyMutationEnvelope.fromJson(Map<String, Object?> json) {
    return KanbanDependencyMutationEnvelope(
      ok: lossyBool(json, 'ok'),
      changed: lossyBool(json, 'changed'),
      prerequisiteID: lossyString(json, 'parentId'),
      dependentID: lossyString(json, 'childId'),
      readOnly: lossyBool(json, 'read_only'),
    );
  }

  final bool? ok;
  final bool? changed;
  final String? prerequisiteID;
  final String? dependentID;
  final bool? readOnly;

  @override
  bool operator ==(Object other) {
    return other is KanbanDependencyMutationEnvelope &&
        other.ok == ok &&
        other.changed == changed &&
        other.prerequisiteID == prerequisiteID &&
        other.dependentID == dependentID &&
        other.readOnly == readOnly;
  }

  @override
  int get hashCode =>
      Object.hash(ok, changed, prerequisiteID, dependentID, readOnly);

  @override
  String toString() => 'KanbanDependencyMutationEnvelope(ok: $ok)';
}

/// 派发结果（Swift: KanbanDispatchResult）。8 个计数，键值特殊：
/// 数组 → 长度；数字 → 截断转 int（有限检查）；字符串 → int.parse(trim)；
/// bool/object/null → null。
class KanbanDispatchResult {
  const KanbanDispatchResult({
    this.spawned,
    this.promoted,
    this.reclaimed,
    this.skippedUnassigned,
    this.skippedNonspawnable,
    this.autoBlocked,
    this.timedOut,
    this.crashed,
  });

  factory KanbanDispatchResult.fromJson(Map<String, Object?> json) {
    return KanbanDispatchResult(
      spawned: _count(json['spawned']),
      promoted: _count(json['promoted']),
      reclaimed: _count(json['reclaimed']),
      skippedUnassigned: _count(json['skipped_unassigned']),
      skippedNonspawnable: _count(json['skipped_nonspawnable']),
      autoBlocked: _count(json['auto_blocked']),
      timedOut: _count(json['timed_out']),
      crashed: _count(json['crashed']),
    );
  }

  final int? spawned;
  final int? promoted;
  final int? reclaimed;
  final int? skippedUnassigned;
  final int? skippedNonspawnable;
  final int? autoBlocked;
  final int? timedOut;
  final int? crashed;

  bool get hasKnownCategory {
    return [
      spawned,
      promoted,
      reclaimed,
      skippedUnassigned,
      skippedNonspawnable,
      autoBlocked,
      timedOut,
      crashed,
    ].any((value) => value != null);
  }

  static int? _count(Object? value) {
    if (value is List) return value.length;
    if (value is int) return value;
    if (value is double) {
      if (!value.isFinite ||
          value < -9223372036854775808.0 ||
          value >= 9223372036854775808.0) {
        return null;
      }
      return value.truncate().toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanDispatchResult &&
        other.spawned == spawned &&
        other.promoted == promoted &&
        other.reclaimed == reclaimed &&
        other.skippedUnassigned == skippedUnassigned &&
        other.skippedNonspawnable == skippedNonspawnable &&
        other.autoBlocked == autoBlocked &&
        other.timedOut == timedOut &&
        other.crashed == crashed;
  }

  @override
  int get hashCode => Object.hash(
    spawned,
    promoted,
    reclaimed,
    skippedUnassigned,
    skippedNonspawnable,
    autoBlocked,
    timedOut,
    crashed,
  );

  @override
  String toString() {
    return 'KanbanDispatchResult(spawned: $spawned, promoted: $promoted, '
        'reclaimed: $reclaimed)';
  }
}

// ============================================================================
// 请求 DTO（query 参数 + 少量 body，编码一律 snake_case）
// ============================================================================

/// 看板请求（Swift: KanbanBoardRequest）。
class KanbanBoardRequest {
  const KanbanBoardRequest({
    required this.board,
    this.tenant,
    this.assignee,
    this.includeArchived = false,
    this.onlyMine = false,
    this.since,
  });

  final String board;
  final String? tenant;
  final String? assignee;
  final bool includeArchived;
  final bool onlyMine;
  final int? since;

  Map<String, String> get queryParameters {
    final result = <String, String>{'board': board};
    if (tenant != null && tenant!.isNotEmpty) result['tenant'] = tenant!;
    if (assignee != null && assignee!.isNotEmpty) {
      result['assignee'] = assignee!;
    }
    if (includeArchived) result['include_archived'] = 'true';
    if (onlyMine) result['only_mine'] = 'true';
    if (since != null) result['since'] = '$since';
    return result;
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanBoardRequest &&
        other.board == board &&
        other.tenant == tenant &&
        other.assignee == assignee &&
        other.includeArchived == includeArchived &&
        other.onlyMine == onlyMine &&
        other.since == since;
  }

  @override
  int get hashCode =>
      Object.hash(board, tenant, assignee, includeArchived, onlyMine, since);

  @override
  String toString() => 'KanbanBoardRequest(board: $board)';
}

/// 事件请求（Swift: KanbanEventsRequest）。limit clamp 1..200。
class KanbanEventsRequest {
  const KanbanEventsRequest({
    required this.board,
    required this.since,
    this.limit = 200,
  });

  final String board;
  final int since;
  final int limit;

  Map<String, String> get queryParameters {
    return {
      'board': board,
      'since': '${since < 0 ? 0 : since}',
      'limit': '${limit.clamp(1, 200)}',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is KanbanEventsRequest &&
      other.board == board &&
      other.since == since &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(board, since, limit);

  @override
  String toString() => 'KanbanEventsRequest(board: $board, since: $since)';
}

/// 事件流请求（Swift: KanbanEventsStreamRequest）。
class KanbanEventsStreamRequest {
  const KanbanEventsStreamRequest({required this.board, required this.since});

  final String board;
  final int since;

  Map<String, String> get queryParameters {
    return {'board': board, 'since': '${since < 0 ? 0 : since}'};
  }

  @override
  bool operator ==(Object other) =>
      other is KanbanEventsStreamRequest &&
      other.board == board &&
      other.since == since;

  @override
  int get hashCode => Object.hash(board, since);

  @override
  String toString() => 'KanbanEventsStreamRequest(board: $board)';
}

/// 工作线程日志请求（Swift: KanbanWorkerLogRequest）。tailBytes clamp 1..2_000_000。
class KanbanWorkerLogRequest {
  const KanbanWorkerLogRequest({
    required this.cardID,
    required this.board,
    this.tailBytes = 65536,
  });

  final String cardID;
  final String board;
  final int tailBytes;

  Map<String, String> get queryParameters {
    return {'board': board, 'tail': '${tailBytes.clamp(1, 2000000)}'};
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanWorkerLogRequest &&
        other.cardID == cardID &&
        other.board == board &&
        other.tailBytes == tailBytes;
  }

  @override
  int get hashCode => Object.hash(cardID, board, tailBytes);

  @override
  String toString() => 'KanbanWorkerLogRequest(cardID: $cardID)';
}

/// 派发请求（Swift: KanbanDispatchRequest）。max=8。
class KanbanDispatchRequest {
  const KanbanDispatchRequest({required this.board, required this.dryRun});

  static const int maximum = 8;

  final String board;
  final bool dryRun;

  Map<String, String> get queryParameters {
    return {
      'board': board,
      'dry_run': dryRun ? 'true' : 'false',
      'max': '$maximum',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is KanbanDispatchRequest &&
      other.board == board &&
      other.dryRun == dryRun;

  @override
  int get hashCode => Object.hash(board, dryRun);

  @override
  String toString() => 'KanbanDispatchRequest(board: $board, dryRun: $dryRun)';
}

/// 创建卡片请求（Swift: KanbanCreateCardRequest）。board 走 query。
class KanbanCreateCardRequest {
  const KanbanCreateCardRequest({
    required this.board,
    required this.title,
    this.body,
    required this.status,
    this.priority,
    this.assignee,
    this.tenant,
    required this.workspaceKind,
    this.workspacePath,
    this.skills,
    this.maxRuntimeSeconds,
    this.prerequisiteID,
    required this.idempotencyKey,
  });

  final String board;
  final String title;
  final String? body;
  final String status;
  final int? priority;
  final String? assignee;
  final String? tenant;
  final String workspaceKind;
  final String? workspacePath;
  final List<String>? skills;
  final int? maxRuntimeSeconds;
  final String? prerequisiteID;
  final String idempotencyKey;

  Map<String, String> get queryParameters => {'board': board};

  Map<String, Object?> toJson() {
    return {
      'title': title,
      if (body != null) 'body': body,
      'status': status,
      if (priority != null) 'priority': priority,
      if (assignee != null) 'assignee': assignee,
      if (tenant != null) 'tenant': tenant,
      'workspace_kind': workspaceKind,
      if (workspacePath != null) 'workspace_path': workspacePath,
      if (skills != null) 'skills': skills,
      if (maxRuntimeSeconds != null) 'max_runtime_seconds': maxRuntimeSeconds,
      if (prerequisiteID != null) 'prerequisite_id': prerequisiteID,
      'idempotency_key': idempotencyKey,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanCreateCardRequest &&
        other.board == board &&
        other.title == title &&
        other.body == body &&
        other.status == status &&
        other.priority == priority &&
        other.assignee == assignee &&
        other.tenant == tenant &&
        other.workspaceKind == workspaceKind &&
        other.workspacePath == workspacePath &&
        _listEquals(other.skills, skills) &&
        other.maxRuntimeSeconds == maxRuntimeSeconds &&
        other.prerequisiteID == prerequisiteID &&
        other.idempotencyKey == idempotencyKey;
  }

  @override
  int get hashCode => Object.hash(
    board,
    title,
    body,
    status,
    priority,
    assignee,
    tenant,
    workspaceKind,
    workspacePath,
    Object.hashAll(skills ?? const []),
    maxRuntimeSeconds,
    prerequisiteID,
    idempotencyKey,
  );

  @override
  String toString() => 'KanbanCreateCardRequest(title: $title)';
}

/// 编辑卡片请求（Swift: KanbanEditCardRequest）。
class KanbanEditCardRequest {
  const KanbanEditCardRequest({
    required this.cardID,
    required this.board,
    required this.title,
    required this.body,
    this.tenant,
    required this.priority,
    this.assignee,
    this.status,
  });

  final String cardID;
  final String board;
  final String title;
  final String body;
  final String? tenant;
  final int priority;
  final String? assignee;
  final String? status;

  Map<String, String> get queryParameters => {'board': board};

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'body': body,
      if (tenant != null) 'tenant': tenant,
      'priority': priority,
      if (assignee != null) 'assignee': assignee,
      if (status != null) 'status': status,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanEditCardRequest &&
        other.cardID == cardID &&
        other.board == board &&
        other.title == title &&
        other.body == body &&
        other.tenant == tenant &&
        other.priority == priority &&
        other.assignee == assignee &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(
    cardID,
    board,
    title,
    body,
    tenant,
    priority,
    assignee,
    status,
  );

  @override
  String toString() => 'KanbanEditCardRequest(cardID: $cardID)';
}

/// 卡片状态请求（Swift: KanbanCardStatusRequest）。
class KanbanCardStatusRequest {
  const KanbanCardStatusRequest({
    required this.cardID,
    required this.board,
    required this.status,
  });

  final String cardID;
  final String board;
  final String status;

  Map<String, String> get queryParameters => {'board': board};

  Map<String, Object?> toJson() => {'status': status};

  @override
  bool operator ==(Object other) {
    return other is KanbanCardStatusRequest &&
        other.cardID == cardID &&
        other.board == board &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(cardID, board, status);

  @override
  String toString() => 'KanbanCardStatusRequest(cardID: $cardID)';
}

/// 卡片动作请求（Swift: KanbanCardActionRequest）。
class KanbanCardActionRequest {
  const KanbanCardActionRequest({
    required this.cardID,
    required this.board,
    this.reason,
  });

  final String cardID;
  final String board;
  final String? reason;

  Map<String, String> get queryParameters => {'board': board};

  Map<String, Object?> toJson() {
    return {if (reason != null) 'reason': reason};
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanCardActionRequest &&
        other.cardID == cardID &&
        other.board == board &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(cardID, board, reason);

  @override
  String toString() => 'KanbanCardActionRequest(cardID: $cardID)';
}

/// 依赖变更请求（Swift: KanbanDependencyMutationRequest）。
class KanbanDependencyMutationRequest {
  const KanbanDependencyMutationRequest({
    required this.board,
    required this.prerequisiteID,
    required this.dependentID,
  });

  final String board;
  final String prerequisiteID;
  final String dependentID;

  Map<String, String> get queryParameters => {'board': board};

  Map<String, Object?> toJson() {
    return {'prerequisite_id': prerequisiteID, 'dependent_id': dependentID};
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanDependencyMutationRequest &&
        other.board == board &&
        other.prerequisiteID == prerequisiteID &&
        other.dependentID == dependentID;
  }

  @override
  int get hashCode => Object.hash(board, prerequisiteID, dependentID);

  @override
  String toString() => 'KanbanDependencyMutationRequest(board: $board)';
}

/// 添加评论请求（Swift: KanbanAddCommentRequest）。
class KanbanAddCommentRequest {
  const KanbanAddCommentRequest({
    required this.cardID,
    required this.board,
    required this.body,
  });

  final String cardID;
  final String board;
  final String body;

  Map<String, String> get queryParameters => {'board': board};

  Map<String, Object?> toJson() => {'body': body};

  @override
  bool operator ==(Object other) {
    return other is KanbanAddCommentRequest &&
        other.cardID == cardID &&
        other.board == board &&
        other.body == body;
  }

  @override
  int get hashCode => Object.hash(cardID, board, body);

  @override
  String toString() => 'KanbanAddCommentRequest(cardID: $cardID)';
}

/// 创建看板请求（Swift: KanbanCreateBoardRequest）。
class KanbanCreateBoardRequest {
  const KanbanCreateBoardRequest({
    required this.slug,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String slug;
  final String name;
  final String description;
  final String icon;
  final String color;

  Map<String, Object?> toJson() {
    return {
      'slug': slug,
      'name': name,
      'description': description,
      'icon': icon,
      'color': color,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanCreateBoardRequest &&
        other.slug == slug &&
        other.name == name &&
        other.description == description &&
        other.icon == icon &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(slug, name, description, icon, color);

  @override
  String toString() => 'KanbanCreateBoardRequest(slug: $slug)';
}

/// 编辑看板请求（Swift: KanbanEditBoardRequest）。
class KanbanEditBoardRequest {
  const KanbanEditBoardRequest({
    required this.slug,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String slug;
  final String name;
  final String description;
  final String icon;
  final String color;

  Map<String, Object?> toJson() {
    return {
      'slug': slug,
      'name': name,
      'description': description,
      'icon': icon,
      'color': color,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is KanbanEditBoardRequest &&
        other.slug == slug &&
        other.name == name &&
        other.description == description &&
        other.icon == icon &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(slug, name, description, icon, color);

  @override
  String toString() => 'KanbanEditBoardRequest(slug: $slug)';
}

/// 看板变更请求（Swift: KanbanBoardMutationRequest）。
class KanbanBoardMutationRequest {
  const KanbanBoardMutationRequest({required this.slug});

  final String slug;

  Map<String, Object?> toJson() => {'slug': slug};

  @override
  bool operator ==(Object other) =>
      other is KanbanBoardMutationRequest && other.slug == slug;

  @override
  int get hashCode => Object.hashAll([slug]);

  @override
  String toString() => 'KanbanBoardMutationRequest(slug: $slug)';
}

/// 批量操作（Swift `KanbanBulkAction`）。sealed 类。
sealed class KanbanBulkAction {
  const KanbanBulkAction();
}

/// 改状态。
final class KanbanBulkActionChangeStatus extends KanbanBulkAction {
  const KanbanBulkActionChangeStatus(this.status);

  final String status;

  @override
  bool operator ==(Object other) =>
      other is KanbanBulkActionChangeStatus && other.status == status;

  @override
  int get hashCode => Object.hashAll([status]);
}

/// 指派 profile。
final class KanbanBulkActionAssignProfile extends KanbanBulkAction {
  const KanbanBulkActionAssignProfile(this.profile);

  final String? profile;

  @override
  bool operator ==(Object other) =>
      other is KanbanBulkActionAssignProfile && other.profile == profile;

  @override
  int get hashCode => Object.hashAll([profile]);
}

/// 设优先级。
final class KanbanBulkActionSetPriority extends KanbanBulkAction {
  const KanbanBulkActionSetPriority(this.priority);

  final int priority;

  @override
  bool operator ==(Object other) =>
      other is KanbanBulkActionSetPriority && other.priority == priority;

  @override
  int get hashCode => Object.hashAll([priority]);
}

/// 归档卡片。
final class KanbanBulkActionArchiveCards extends KanbanBulkAction {
  const KanbanBulkActionArchiveCards();

  @override
  bool operator ==(Object other) => other is KanbanBulkActionArchiveCards;

  @override
  int get hashCode => Object.hashAll([KanbanBulkActionArchiveCards]);
}

/// 批量操作请求（Swift: KanbanBulkActionRequest）。
class KanbanBulkActionRequest {
  const KanbanBulkActionRequest({
    required this.board,
    required this.cardIDs,
    required this.action,
  });

  final String board;
  final List<String> cardIDs;
  final KanbanBulkAction action;

  Map<String, String> get queryParameters => {'board': board};

  @override
  bool operator ==(Object other) {
    return other is KanbanBulkActionRequest &&
        other.board == board &&
        _listEquals(other.cardIDs, cardIDs) &&
        other.action == action;
  }

  @override
  int get hashCode => Object.hash(board, Object.hashAll(cardIDs), action);

  @override
  String toString() => 'KanbanBulkActionRequest(board: $board)';
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
