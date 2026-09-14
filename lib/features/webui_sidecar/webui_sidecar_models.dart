import 'dart:math';

/// WebUI Sidecar 运行状态。
enum SidecarStatus {
  /// 服务已停止。
  stopped,

  /// 服务正在启动中。
  starting,

  /// 服务运行中（正常托管或接管模式）。
  running,

  /// 服务启动或运行失败。
  failed,
}

/// WebUI Sidecar 失败原因枚举。
enum SidecarFailureReason {
  /// 无失败。
  none,

  /// 端口已被外部进程占用且 /health 探测失败。
  portOccupied,

  /// 内置 WebUI 依赖包缺失（#76 二期：server.py 未找到）。
  missingBundle,

  /// 启动子进程后轮询 /health 接口 30s 超时。
  healthTimeout,

  /// 进程启动失败、平台不支持或自愈连续重试超限。
  startFailed,
}

/// WebUI Sidecar 状态快照。
class SidecarState {
  /// 构造 WebUI Sidecar 状态快照。
  const SidecarState({
    this.status = SidecarStatus.stopped,
    this.reason = SidecarFailureReason.none,
    this.pid,
    this.detail,
  });

  /// 初始状态（已停止）。
  static const SidecarState initial = SidecarState();

  /// 当前状态。
  final SidecarStatus status;

  /// 失败原因（仅在 [status] 为 [SidecarStatus.failed] 时具有实际意义）。
  final SidecarFailureReason reason;

  /// 托管子进程的系统 PID（接管模式或未运行为 null）。
  final int? pid;

  /// 状态描述细节（如自愈注记、接管提示、错误异常信息等）。
  final String? detail;

  /// 复制并更新部分字段。
  SidecarState copyWith({
    SidecarStatus? status,
    SidecarFailureReason? reason,
    int? pid,
    String? detail,
    bool clearPid = false,
    bool clearDetail = false,
  }) {
    return SidecarState(
      status: status ?? this.status,
      reason: reason ?? this.reason,
      pid: clearPid ? null : (pid ?? this.pid),
      detail: clearDetail ? null : (detail ?? this.detail),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SidecarState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          reason == other.reason &&
          pid == other.pid &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(status, reason, pid, detail);

  @override
  String toString() =>
      'SidecarState(status: $status, reason: $reason, pid: $pid, detail: $detail)';
}

/// WebUI Sidecar 配置模型。
class SidecarConfig {
  /// 构造 Sidecar 配置。
  const SidecarConfig({
    this.enabled = false,
    this.host = defaultHost,
    this.port = defaultPort,
    this.password = '',
  });

  /// 默认监听主机。
  static const String defaultHost = '127.0.0.1';

  /// 默认监听端口。
  static const int defaultPort = 8787;

  /// 默认密码长度。
  static const int defaultPasswordLength = 24;

  /// 是否启用内置 WebUI 服务。
  final bool enabled;

  /// WebUI 监听 IP（如 127.0.0.1 或 0.0.0.0）。
  final String host;

  /// WebUI 监听端口（默认 8787）。
  final int port;

  /// WebUI 访问密码（安全约定：属于秘密，禁止打印明文日志，禁止导出到 toJson）。
  final String password;

  /// 生成指定长度的高强度随机密码（大小写字母与数字组合）。
  static String generateRandomPassword([int length = defaultPasswordLength]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// 复制并更新部分字段。
  SidecarConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? password,
  }) {
    return SidecarConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
    );
  }

  /// 持久化字典（严格遵循安全约定：**不包含密码**）。
  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'host': host,
      'port': port,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SidecarConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          host == other.host &&
          port == other.port &&
          password == other.password;

  @override
  int get hashCode => Object.hash(enabled, host, port, password);

  @override
  String toString() =>
      'SidecarConfig(enabled: $enabled, host: $host, port: $port, password: ***)';
}
