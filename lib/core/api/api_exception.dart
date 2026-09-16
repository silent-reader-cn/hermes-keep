import 'dart:convert';

/// API 错误归一化后的统一异常体系（镜像 `.reference/hermex-src/Networking/APIError.swift`）。
///
/// 所有 API 层错误都继承 [ApiException]，业务层按需 catch 展示。
sealed class ApiException implements Exception {
  const ApiException(this.message);

  /// 面向用户的错误描述（中文）。
  final String message;

  @override
  String toString() => '$runtimeType: $message';

  /// 缓存兜底判定（对齐 CacheFallbackPolicy.swift）：网络类错误（DNS/连不上/离线/
  /// 超时）或 HTTP 408/502/503/504 时允许上层走离线缓存。
  static bool shouldUseCache(ApiException error) {
    if (error is NetworkException) {
      switch (error.kind) {
        case NetworkExceptionKind.cannotFindHost:
        case NetworkExceptionKind.cannotConnect:
        case NetworkExceptionKind.offline:
        case NetworkExceptionKind.timedOut:
          return true;
        case NetworkExceptionKind.tls:
        case NetworkExceptionKind.cancelled:
        case NetworkExceptionKind.other:
          return false;
      }
    }
    if (error is HttpException) {
      return const {408, 502, 503, 504}.contains(error.statusCode);
    }
    return false;
  }
}

/// 服务器地址无效（APIError.invalidServerURL 等价物）。
class InvalidServerUrlException extends ApiException {
  const InvalidServerUrlException([
    super.message =
        '请输入有效的服务器地址，例如 https://hermes.example.com 或 http://<服务器IP>:8787。',
  ]);
}

/// 网络错误分类（按底层错误细分，对齐 APIError.network 的中文提示）。
enum NetworkExceptionKind {
  /// 连接/发送/接收超时。
  timedOut('服务器响应超时。请确认服务器在线、隧道连通后重试。'),

  /// DNS 解析失败 / 找不到主机。
  cannotFindHost('无法解析服务器地址。请检查 URL 与 DNS 配置。'),

  /// 连不上主机 / 连接丢失。
  cannotConnect('无法连接到服务器。请确认 hermes-webui 正在运行、隧道已连通。'),

  /// 设备离线 / 数据网络被禁止。
  offline('设备当前处于离线状态。请连接网络后重试。'),

  /// TLS / 证书问题。
  tls('HTTPS 连接失败。请检查服务器 URL 与证书配置。'),

  /// 请求被取消。
  cancelled('请求已取消。'),

  /// 其他未分类网络错误。
  other('无法连接到服务器。请检查 URL、网络连接与隧道状态。');

  const NetworkExceptionKind(this.message);

  final String message;
}

/// 网络层异常（APIError.network 等价物）。
class NetworkException extends ApiException {
  NetworkException(this.kind, [String? message])
    : super(message ?? kind.message);

  final NetworkExceptionKind kind;
}

/// HTTP 非 2xx 异常（APIError.http 等价物）。
///
/// [body] 为原始响应体文本；[serverCode] / [serverMessage] / [stale] /
/// [activeStreamId] 从 body JSON 解析（解析失败置 null/false）。
class HttpException extends ApiException {
  HttpException(
    this.statusCode,
    this.body, {
    this.serverCode,
    this.serverMessage,
    this.activeStreamId,
    this.stale = false,
    String? message,
  }) : super(message ?? '服务器返回 HTTP $statusCode。');

  final int statusCode;

  /// 原始响应体文本（可能为 null）。
  final String? body;

  /// body JSON 的 `{code}` 字段。
  final String? serverCode;

  /// body JSON 的 `error` → `message` → `detail` 首个非空值。
  final String? serverMessage;

  /// 仅 409：body `{active_stream_id}`（trim 后非空才有值）。
  final String? activeStreamId;

  /// 仅 409：body `{stale: true}`。
  final bool stale;

  /// 审批/澄清「提示已过期」友好态：409 且 body `{stale: true}`。
  bool get indicatesExpiredPendingPrompt => statusCode == 409 && stale;

  /// 已有活跃流：409 且 `active_stream_id` 非空。
  bool get indicatesActiveStream => statusCode == 409 && activeStreamId != null;

  /// 流已不存在：404 且 serverMessage 含 "stream not found"（大小写不敏感）。
  bool get indicatesMissingStream =>
      statusCode == 404 &&
      _containsIgnoreCase(serverMessage, 'stream not found');

  /// 会话已消失：404 且 serverMessage 含 "Session not found"（大小写不敏感）。
  bool get isVanishedSession =>
      statusCode == 404 &&
      _containsIgnoreCase(serverMessage, 'Session not found');

  /// 从状态码 + body 文本构建，并解析 body JSON 中的语义字段。
  factory HttpException.fromBody(int statusCode, String? body) {
    String? code;
    String? serverMessage;
    var stale = false;
    String? activeStreamId;
    if (body != null && body.isNotEmpty) {
      try {
        final json = jsonDecode(body);
        if (json is Map<String, dynamic>) {
          code = _stringField(json['code']);
          serverMessage = _firstNonEmpty([
            json['error'],
            json['message'],
            json['detail'],
          ]);
          stale = json['stale'] == true;
          final rawStreamId = json['active_stream_id'];
          if (rawStreamId is String) {
            final trimmed = rawStreamId.trim();
            activeStreamId = trimmed.isEmpty ? null : trimmed;
          }
        }
      } catch (_) {
        // body 不是合法 JSON：语义字段全部保持 null/false。
      }
    }
    return HttpException(
      statusCode,
      body,
      serverCode: code,
      serverMessage: serverMessage,
      stale: stale,
      activeStreamId: activeStreamId,
    );
  }
}

/// JSON 解码失败（APIError.decoding 等价物）。
class DecodingException extends ApiException {
  const DecodingException([super.message = '服务器响应无法解析。']);
}

/// 401 未授权（APIError.unauthorized 等价物）。
class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = '密码被拒绝。请检查服务器密码后重试。']);
}

/// kanban 响应 Content-Type 不是 `application/json`（§2.5 kanbanJSON 守卫）。
class KanbanNonJsonContentTypeException extends ApiException {
  const KanbanNonJsonContentTypeException([
    super.message = 'kanban 响应 Content-Type 不是 application/json。',
  ]);
}

/// kanban dispatch 结果 8 个计数全空（hasKnownCategory == false，§2.5 守卫）。
class KanbanDispatchMissingResultException extends ApiException {
  const KanbanDispatchMissingResultException([
    super.message = 'kanban dispatch 结果缺少已知分类计数。',
  ]);
}

/// kanban card status 不得设为 running（running 只能由 dispatcher 设置，§2.5 守卫）。
class KanbanRunningStatusRequiresDispatcherException extends ApiException {
  const KanbanRunningStatusRequiresDispatcherException([
    super.message = 'card 状态 running 只能由 dispatcher 设置。',
  ]);
}

/// 附件超过 20MB 本地预检上限（Models/UploadResponse.swift maximumUploadBytes）。
class UploadFileTooLargeException extends ApiException {
  const UploadFileTooLargeException([super.message = '附件超过 20MB 上限，无法上传。']);
}

/// 服务端明确拒绝写入：HTTP 200，但 body `ok: false` 且带 `error` 原因。
///
/// 用于「收藏提示词」这类**业务层拒绝**——HTTP 层是成功的、无需重试，
/// 但服务端给的原因（如「已达上限 (max 200)」）必须透出到 UI：
/// 否则用户只看到通用「收藏失败」，永远不知道该删掉几条。
class RequestRejectedException extends ApiException {
  const RequestRejectedException([super.message = '服务器拒绝了该操作。']);
}

String? _stringField(Object? value) => value is String ? value : null;

String? _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
  }
  return null;
}

bool _containsIgnoreCase(String? haystack, String needle) {
  if (haystack == null) return false;
  return haystack.toLowerCase().contains(needle.toLowerCase());
}
