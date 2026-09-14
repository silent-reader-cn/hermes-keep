import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'webui_sidecar_service.dart';

export 'webui_sidecar_service.dart';

/// 文件系统与环境适配器 Provider（测试可覆盖注入）。
final sidecarFileSystemProvider = Provider<SidecarFileSystem>(
  (ref) => const DefaultSidecarFileSystem(),
);

/// Sidecar 配置存储器 Provider（测试可注入 fake storage）。
final webuiSidecarConfigStorageProvider = Provider<WebuiSidecarConfigStorage>(
  (ref) => WebuiSidecarConfigStorage(),
);

/// 内置 WebUI 包可用性探测 Provider（仅 Windows 且包内含 server/server.py 时为 true；
/// #76 二期起不再要求 embedded python）。
final bundledWebuiAvailableProvider = Provider<bool>((ref) {
  final fs = ref.watch(sidecarFileSystemProvider);
  return fs.isBundleAvailable();
});

/// Agent 环境存在性探测 Notifier。
class AgentEnvPresentNotifier extends AsyncNotifier<bool> {
  @override
  FutureOr<bool> build() {
    final fs = ref.watch(sidecarFileSystemProvider);
    return isAgentEnvPresent(fs);
  }

  /// 重新探测环境。
  Future<bool> refresh() async {
    state = const AsyncValue.loading();
    final fs = ref.read(sidecarFileSystemProvider);
    final present = isAgentEnvPresent(fs);
    state = AsyncValue.data(present);
    return present;
  }
}

/// Agent 环境（venv 解释器）是否存在探测 Provider。
final agentEnvPresentProvider =
    AsyncNotifierProvider<AgentEnvPresentNotifier, bool>(
  AgentEnvPresentNotifier.new,
);

/// WebUI Sidecar 核心服务 Provider。
final webuiSidecarServiceProvider = Provider<WebuiSidecarService>((ref) {
  final service = DefaultWebuiSidecarService(
    getConfig: () => ref.read(webuiSidecarConfigProvider),
    fileSystem: ref.watch(sidecarFileSystemProvider),
  );
  ref.onDispose(() {
    unawaited(service.stop());
  });
  return service;
});

/// WebUI Sidecar 配置 Provider。
final webuiSidecarConfigProvider =
    NotifierProvider<WebuiSidecarConfigController, SidecarConfig>(
  WebuiSidecarConfigController.new,
);

/// WebUI Sidecar 配置 Notifier Controller。
class WebuiSidecarConfigController extends Notifier<SidecarConfig> {
  late WebuiSidecarConfigStorage _storage;

  @override
  SidecarConfig build() {
    _storage = ref.watch(webuiSidecarConfigStorageProvider);
    unawaited(load());
    return const SidecarConfig();
  }

  /// 从持久化存储中读取配置。
  Future<void> load() async {
    final loaded = await _storage.load();
    state = loaded;
  }

  /// 保存完整配置。
  Future<void> updateConfig(SidecarConfig newConfig) async {
    state = newConfig;
    await _storage.save(newConfig);
  }

  /// 更新启用状态开关。
  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    await _storage.setEnabled(value);
  }

  /// 更新监听主机。
  Future<void> setHost(String value) async {
    state = state.copyWith(host: value);
    await _storage.setHost(value);
  }

  /// 更新监听端口。
  Future<void> setPort(int value) async {
    state = state.copyWith(port: value);
    await _storage.setPort(value);
  }

  /// 更新访问密码（写入加密安全存储）。
  Future<void> setPassword(String value) async {
    state = state.copyWith(password: value);
    await _storage.setPassword(value);
  }
}

/// WebUI Sidecar 状态控制器 Provider。
final webuiSidecarControllerProvider =
    NotifierProvider<WebuiSidecarController, SidecarState>(
  WebuiSidecarController.new,
);

/// WebUI Sidecar 控制器（包装 service 的 states 流，管理生命周期与配置变更联动）。
class WebuiSidecarController extends Notifier<SidecarState> {
  /// 默认日志子目录相对路径（`%LOCALAPPDATA%\hermes\webui-bundled\logs`）。
  static const String defaultLogSubdirectory = r'hermes\webui-bundled\logs';

  StreamSubscription<SidecarState>? _subscription;

  @override
  SidecarState build() {
    final service = ref.watch(webuiSidecarServiceProvider);

    final oldSub = _subscription;
    if (oldSub != null) {
      unawaited(oldSub.cancel());
    }
    _subscription = service.states.listen((newState) {
      state = newState;
    });

    ref.onDispose(() {
      final s = _subscription;
      if (s != null) {
        unawaited(s.cancel());
      }
    });

    // 运行中改 port/host/password → 自动重启服务；stopped 状态下配置变化不触发重启动作。
    ref.listen<SidecarConfig>(webuiSidecarConfigProvider, (previous, current) {
      if (previous == null) return;
      if (state.status != SidecarStatus.running) return;

      final configChanged = previous.host != current.host ||
          previous.port != current.port ||
          previous.password != current.password;

      if (configChanged) {
        unawaited(service.restart());
      }
    });

    return service.currentState;
  }

  /// 启动内置 WebUI 服务。
  ///
  /// 仅 Windows 平台拉起进程；非 Windows 平台置 failed(startFailed) 并附 detail 说明。
  Future<void> start() async {
    final fs = ref.read(sidecarFileSystemProvider);
    if (!fs.isWindows) {
      state = const SidecarState(
        status: SidecarStatus.failed,
        reason: SidecarFailureReason.startFailed,
        detail: 'Built-in WebUI sidecar is only supported on Windows',
      );
      return;
    }

    final service = ref.read(webuiSidecarServiceProvider);
    await service.start();
  }

  /// 停止内置 WebUI 服务。
  Future<void> stop() async {
    final service = ref.read(webuiSidecarServiceProvider);
    await service.stop();
  }

  /// 重启内置 WebUI 服务。
  Future<void> restart() async {
    final fs = ref.read(sidecarFileSystemProvider);
    if (!fs.isWindows) {
      state = const SidecarState(
        status: SidecarStatus.failed,
        reason: SidecarFailureReason.startFailed,
        detail: 'Built-in WebUI sidecar is only supported on Windows',
      );
      return;
    }

    final service = ref.read(webuiSidecarServiceProvider);
    await service.restart();
  }
}
