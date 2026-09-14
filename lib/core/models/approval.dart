import '../utils/lossy_json.dart';

/// 审批选择（Swift: ApprovalChoice）。未知字符串 → null。
enum ApprovalChoice { once, session, always, deny }

/// 解析审批选择：字符串匹配 4 个 rawValue，未知 → null。
ApprovalChoice? approvalChoiceFromJson(Object? value) {
  if (value is! String) return null;
  switch (value) {
    case 'once':
      return ApprovalChoice.once;
    case 'session':
      return ApprovalChoice.session;
    case 'always':
      return ApprovalChoice.always;
    case 'deny':
      return ApprovalChoice.deny;
    default:
      return null;
  }
}

/// 待审批请求/响应类型别名（兼容 TASK W3 强类型命名）。
typedef ApprovalRequest = ApprovalPendingResponse;

/// 待审批响应信封（Swift: ApprovalPendingResponse）。
class ApprovalPendingResponse {
  const ApprovalPendingResponse({this.pending, this.pendingCount});

  factory ApprovalPendingResponse.fromJson(Map<String, Object?> json) {
    return ApprovalPendingResponse(
      pending: optModel(json, 'pending', PendingApproval.fromJson),
      pendingCount: firstKey(json, ['pending_count', 'pendingCount'], lossyInt),
    );
  }

  /// SSE 流载荷解析（对齐 Swift `streamPayload`）：先解自身（pending 或
  /// pendingCount 非 null 即用）；否则直接解 PendingApproval，非空则包装
  /// `(pending, 1)`；否则 `(null, null)`。
  static ApprovalPendingResponse streamPayload(Map<String, Object?> json) {
    final wrapped = ApprovalPendingResponse.fromJson(json);
    if (wrapped.pending != null || wrapped.pendingCount != null) {
      return wrapped;
    }
    final direct = PendingApproval.fromJson(json);
    if (!direct.isEmpty) {
      return ApprovalPendingResponse(pending: direct, pendingCount: 1);
    }
    return const ApprovalPendingResponse();
  }

  final PendingApproval? pending;
  final int? pendingCount;

  @override
  bool operator ==(Object other) {
    return other is ApprovalPendingResponse &&
        other.pending == pending &&
        other.pendingCount == pendingCount;
  }

  @override
  int get hashCode => Object.hash(pending, pendingCount);

  @override
  String toString() => 'ApprovalPendingResponse(pendingCount: $pendingCount)';
}

/// 待审批（Swift: PendingApproval）。`id` = approvalId 非空 ? approvalId :
/// `$command-$description-${displayPatternKeys.join(',')}`。
class PendingApproval {
  PendingApproval({
    String? approvalId,
    this.command,
    this.description,
    this.patternKey,
    this.patternKeys,
    this.raw,
  }) : approvalId = _normalizedApprovalId(approvalId);

  factory PendingApproval.fromJson(Map<String, Object?> json) {
    return PendingApproval(
      approvalId: _decodeApprovalId(json),
      command: lossyString(json, 'command'),
      description: lossyString(json, 'description'),
      patternKey: firstKey(json, ['pattern_key', 'patternKey'], lossyString),
      patternKeys: lossyStringArray(json, ['pattern_keys', 'patternKeys']),
      raw: json,
    );
  }

  final String? approvalId;
  final String? command;
  final String? description;
  final String? patternKey;
  final List<String>? patternKeys;
  final Map<String, Object?>? raw;

  /// 序列化为 Map，优先复用原始入参保证字段无损。
  Map<String, Object?> toJson() {
    if (raw != null) return Map<String, Object?>.from(raw!);
    return {
      if (approvalId != null) 'approval_id': approvalId,
      if (command != null) 'command': command,
      if (description != null) 'description': description,
      if (patternKey != null) 'pattern_key': patternKey,
      if (patternKeys != null) 'pattern_keys': patternKeys,
    };
  }

  String get id {
    final aid = approvalId;
    if (aid != null && aid.isNotEmpty) return aid;
    return '${command ?? ''}-${description ?? ''}-${displayPatternKeys.join(',')}';
  }

  /// patternKeys 过滤空 trim 后非空用，否则 patternKey 单元素。
  List<String> get displayPatternKeys {
    final keys =
        patternKeys?.where((e) => e.trim().isNotEmpty).toList() ?? const [];
    if (keys.isNotEmpty) return keys;
    final key = patternKey?.trim();
    if (key == null || key.isEmpty) return const [];
    return [key];
  }

  /// 5 字段全空。
  bool get isEmpty {
    return approvalId == null &&
        command == null &&
        description == null &&
        patternKey == null &&
        (patternKeys?.isEmpty ?? true);
  }

  static String? _decodeApprovalId(Map<String, Object?> json) {
    for (final key in const ['approval_id', 'approvalId', 'id']) {
      final value = _normalizedApprovalId(lossyString(json, key));
      if (value != null) return value;
    }
    return null;
  }

  static String? _normalizedApprovalId(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  bool operator ==(Object other) {
    return other is PendingApproval &&
        other.approvalId == approvalId &&
        other.command == command &&
        other.description == description &&
        other.patternKey == patternKey &&
        _listEquals(other.patternKeys, patternKeys);
  }

  @override
  int get hashCode =>
      Object.hash(approvalId, command, description, patternKey, _hashList(patternKeys));

  @override
  String toString() => 'PendingApproval(approvalId: $approvalId, command: $command)';
}

/// 审批响应（Swift: ApprovalRespondResponse）。
class ApprovalRespondResponse {
  const ApprovalRespondResponse({
    this.ok,
    this.choice,
    this.staleCleared,
    this.relayed,
    this.stale,
  });

  factory ApprovalRespondResponse.fromJson(Map<String, Object?> json) {
    return ApprovalRespondResponse(
      ok: lossyBool(json, 'ok'),
      choice: approvalChoiceFromJson(json['choice']),
      staleCleared: firstKey(json, ['stale_cleared', 'staleCleared'], lossyBool),
      relayed: lossyBool(json, 'relayed'),
      stale: lossyBool(json, 'stale'),
    );
  }

  final bool? ok;
  final ApprovalChoice? choice;
  final bool? staleCleared;
  final bool? relayed;
  final bool? stale;

  @override
  bool operator ==(Object other) {
    return other is ApprovalRespondResponse &&
        other.ok == ok &&
        other.choice == choice &&
        other.staleCleared == staleCleared &&
        other.relayed == relayed &&
        other.stale == stale;
  }

  @override
  int get hashCode => Object.hash(ok, choice, staleCleared, relayed, stale);

  @override
  String toString() => 'ApprovalRespondResponse(ok: $ok, choice: $choice)';
}

/// 会话 YOLO 模式响应（Swift: SessionYoloResponse）。
class SessionYoloResponse {
  const SessionYoloResponse({this.ok, this.yoloEnabled});

  factory SessionYoloResponse.fromJson(Map<String, Object?> json) {
    return SessionYoloResponse(
      ok: lossyBool(json, 'ok'),
      yoloEnabled: firstKey(json, ['yolo_enabled', 'yoloEnabled'], lossyBool),
    );
  }

  final bool? ok;
  final bool? yoloEnabled;

  @override
  bool operator ==(Object other) {
    return other is SessionYoloResponse &&
        other.ok == ok &&
        other.yoloEnabled == yoloEnabled;
  }

  @override
  int get hashCode => Object.hash(ok, yoloEnabled);

  @override
  String toString() => 'SessionYoloResponse(ok: $ok, yoloEnabled: $yoloEnabled)';
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

int _hashList(List<String>? list) => Object.hashAll(list ?? const []);
