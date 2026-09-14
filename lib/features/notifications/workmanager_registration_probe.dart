import 'package:flutter/services.dart';

/// WorkManager 原生注册探针（#110）。
///
/// 背景：`workmanager_android` 的插件注册顺序是**先构造再绑通道**——
/// `WorkmanagerPlugin.onAttachedToEngine()` 里
/// `WorkManagerWrapper(binding.applicationContext)`（内部
/// `WorkManager.getInstance(context)`）先执行，随后才
/// `WorkmanagerHostApi.setUp(binding.binaryMessenger, this)`。前者一旦抛异常，
/// 整个插件注册被 GeneratedPluginRegistrant 的 try/catch 吞掉（只打 logcat），
/// pigeon 通道永不绑定，Dart 侧只能看到
/// `PlatformException(channel-error, Unable to establish connection on channel: ...)`。
///
/// 由于通道在引擎 attach 时绑定、失败后**不会**在同进程内恢复（Dart 侧重试无意义），
/// 必须把成因区分清楚才能对症：
/// - 探针 `initialized=false` + `error` 有值 → WorkManager 自身初始化失败
///   （数据库迁移异常 / 未初始化），修复方向是数据清理或强制初始化；
/// - 探针 `initialized=true` → WorkManager 正常，失败点在插件注册（陈旧构建
///   产物 / 注册期竞态），修复方向是 clean 重打包。
///
/// 探针本身失败（非 Android 平台、通道未注册）一律静默降级，绝不阻断保活初始化。
abstract interface class WorkManagerRegistrationProbe {
  /// 单例访问（测试可替换）。
  static WorkManagerRegistrationProbe instance =
      const MethodChannelWorkManagerRegistrationProbe();

  /// 读取一次原生侧 WorkManager 初始化快照。
  Future<WorkManagerRegistrationSnapshot> probe();
}

/// 探针返回的原生侧快照。
class WorkManagerRegistrationSnapshot {
  const WorkManagerRegistrationSnapshot({
    required this.initialized,
    this.creation,
    this.error,
  });

  /// 探针调用当下 `WorkManager.getInstance()` 是否成功。
  final bool initialized;

  /// 冷启动兜底动作：`already-initialized` / `manual-initialize` /
  /// `manual-initialize-failed` / `unavailable`（探针不可用）。
  final String? creation;

  /// 初始化异常描述（`异常类名: message`），无异常时为 null。
  final String? error;

  /// 单行描述，直接拼进诊断日志。
  String describe() {
    return [
      'initialized=$initialized',
      if (creation != null) 'creation=$creation',
      if (error != null) 'error=$error',
    ].join(' ');
  }
}

/// 生产实现：走 MainActivity 的 keepalive_probe 通道。
class MethodChannelWorkManagerRegistrationProbe
    implements WorkManagerRegistrationProbe {
  const MethodChannelWorkManagerRegistrationProbe();

  /// 原生通道（MainActivity 注册）。
  static const MethodChannel channel = MethodChannel(
    'com.silentreader.hermes_ui/keepalive_probe',
  );

  @override
  Future<WorkManagerRegistrationSnapshot> probe() async {
    try {
      final raw = await channel.invokeMapMethod<String, Object?>(
        'probeWorkManager',
      );
      if (raw == null) {
        return const WorkManagerRegistrationSnapshot(
          initialized: false,
          creation: 'unavailable',
        );
      }
      return WorkManagerRegistrationSnapshot(
        initialized: raw['initialized'] == true,
        creation: raw['creation'] as String?,
        error: raw['error'] as String?,
      );
    } on Object {
      // 探针不可用（非 Android / 通道未注册 / 原生异常）：静默降级。
      return const WorkManagerRegistrationSnapshot(
        initialized: false,
        creation: 'unavailable',
      );
    }
  }
}
