import '../utils/uuid.dart';

enum ConnectionKind {
  builtin,
  remote,
}

/// 服务器连接（app_shell_spec.md §5.1）。
///
/// 对应 Hermex 的 ServerAccount + 认证信息：一条记录描述一个可连接的
/// hermes-webui 服务器（多服务器支持，可切换 active）。
///
/// 安全约定：`password` 与 `customHeaders` 的值属于秘密，**只允许**存在于
/// 内存与 flutter_secure_storage（密码单独 key 加密存储，见
/// [ConnectionStore]）；`toJson()` **不导出密码**，禁止进日志/状态快照。
class ServerConnection {
  const ServerConnection({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.username,
    this.password,
    this.customHeaders = const {},
    required this.createdAt,
    this.kind = ConnectionKind.remote,
    bool enabled = true,
  }) : enabled = (kind == ConnectionKind.builtin) ? enabled : true;

  /// 内置连接的固定 ID（U2 将按此 ID upsert）。
  static const String builtinId = 'builtin-sidecar';

  /// 本地生成 uuid（[uuidV4]）。
  final String id;

  /// 用户命名，如 'Home'（缺省用主机名）。
  final String name;

  /// 服务器地址，如 `https://hermes.example.com:8787`（不含尾斜杠）。
  final String baseUrl;

  /// dashboard 登录用户名（可空；登录请求实际只发密码，见 api_spec §1.1）。
  final String? username;

  /// 密码：仅内存 + secure storage 单独 key，**不进入 toJson**。
  final String? password;

  /// 反向代理自定义头（如 `Authorization: Bearer xxx`）。
  final Map<String, String> customHeaders;

  /// 创建时间（本地持久化用 ISO8601）。
  final DateTime createdAt;

  /// 连接类别：builtin（内置 sidecar）或 remote（远程服务器），默认 remote。
  final ConnectionKind kind;

  /// 是否启用：builtin 专用语义；remote 恒为 true。
  final bool enabled;

  /// 容错解码：字段缺失/类型不符给安全默认值，绝不 crash（AGENTS.md §6）。
  ///
  /// 密码不在此 JSON 中（由 [ConnectionStore] 从单独 key 读出后注入）。
  /// 存量 JSON 缺失 kind 字段时默认兼容为 [ConnectionKind.remote]。
  factory ServerConnection.fromJson(
    Map<String, Object?> json, {
    String? password,
  }) {
    final id = json['id'] is String ? json['id'] as String : '';
    final name = json['name'] is String ? json['name'] as String : '';
    final baseUrl = json['base_url'] is String ? json['base_url'] as String : '';
    final username = json['username'] is String ? json['username'] as String : null;
    final headers = _decodeHeaders(json['custom_headers']);
    final kindRaw = json['kind'];
    final kind = (kindRaw is String && kindRaw == ConnectionKind.builtin.name)
        ? ConnectionKind.builtin
        : ConnectionKind.remote;
    final enabledRaw = json['enabled'];
    final enabled = enabledRaw is bool ? enabledRaw : true;

    return ServerConnection(
      id: id.isEmpty ? uuidV4() : id,
      name: name,
      baseUrl: baseUrl,
      username: username,
      password: password,
      customHeaders: headers,
      createdAt: _parseDate(json['created_at']),
      kind: kind,
      enabled: enabled,
    );
  }

  /// 持久化 JSON（**不含密码**；custom_headers 整体进 secure storage 加密区）。
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      if (username != null) 'username': username,
      'custom_headers': customHeaders,
      'created_at': createdAt.toUtc().toIso8601String(),
      'kind': kind.name,
      'enabled': enabled,
    };
  }

  ServerConnection copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? username,
    String? password,
    Map<String, String>? customHeaders,
    DateTime? createdAt,
    ConnectionKind? kind,
    bool? enabled,
  }) {
    final resolvedKind = kind ?? this.kind;
    return ServerConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      customHeaders: customHeaders ?? this.customHeaders,
      createdAt: createdAt ?? this.createdAt,
      kind: resolvedKind,
      enabled: enabled ?? this.enabled,
    );
  }

  /// 容错解析自定义头：期望 `Map<String, String>`，类型不符/元素非字符串时跳过。
  static Map<String, String> _decodeHeaders(Object? value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is String && entry.value is String) {
        result[entry.key as String] = entry.value as String;
      }
    }
    return result;
  }

  static DateTime _parseDate(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  @override
  bool operator ==(Object other) {
    return other is ServerConnection &&
        other.id == id &&
        other.name == name &&
        other.baseUrl == baseUrl &&
        other.username == username &&
        other.password == password &&
        _mapEquals(other.customHeaders, customHeaders) &&
        other.createdAt == createdAt &&
        other.kind == kind &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        baseUrl,
        username,
        password,
        createdAt,
        kind,
        enabled,
      );

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
