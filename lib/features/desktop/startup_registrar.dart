import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/test_environment.dart';

/// Windows 开机启动注册表路径（HKCU，无需管理员权限）。
const String startupRunKeyPath =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

/// 开机启动注册表值名称。
const String startupValueName = 'Hermes';

/// 静默启动命令行参数。
const String silentStartArg = '--silent';

/// 构建开机启动写入注册表的命令行值。
///
/// [executablePath] 为当前可执行文件路径（`Platform.resolvedExecutable`），
/// 一律以双引号包裹（路径可能含空格）；[silent] 为真时追加 `--silent` 参数。
String buildStartupCommand({
  required String executablePath,
  required bool silent,
}) {
  return '"$executablePath"${silent ? ' $silentStartArg' : ''}';
}

/// 判断本次启动是否带 `--silent` 静默参数。
///
/// Windows 桌面下 Flutter 引擎会把命令行参数透传给 Dart `main(List<String>)`，
/// 同时 `Platform.executableArguments` 也提供同一份 argv；两个来源都检查，
/// 任一包含 `--silent` 即视为静默启动（覆盖引擎/平台差异，实测为准）。
bool isSilentStart({List<String>? args, List<String>? executableArguments}) {
  if (args != null && args.contains(silentStartArg)) return true;
  if (executableArguments != null &&
      executableArguments.contains(silentStartArg)) {
    return true;
  }
  return false;
}

/// 开机启动注册接口（可注入，测试用 fake 替身）。
///
/// 职责：查询 / 写入 / 删除
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 下本应用的注册值。
/// 注册表读写一律经本接口，业务层不直接触碰系统状态。
abstract interface class StartupRegistrar {
  /// 当前是否已注册开机启动。
  ///
  /// 存在性以 `reg query` 的退出码判定（中文系统输出本地化，不解析文本）。
  Future<bool> isRegistered();

  /// 设置开机启动状态。
  ///
  /// [registered] 为真时写入 [command]（含引号转义的可执行路径，必要时带
  /// `--silent`）；为假时删除注册值。[command] 仅在 [registered] 为真时提供。
  Future<void> setRegistered(bool registered, {String? command});
}

/// Windows 注册表实现（调用 `reg.exe`）。
class WindowsStartupRegistrar implements StartupRegistrar {
  /// 构造 Windows 注册表实现。
  ///
  /// [runProcess] 与 [isWindowsPlatform] 可注入，便于测试用桩替换
  /// （测试绝不真跑 `reg add` / `reg delete`）。
  WindowsStartupRegistrar({
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runProcess,
    bool Function()? isWindowsPlatform,
  }) : _runProcess = runProcess ?? _defaultRunProcess,
       _isWindowsPlatform = isWindowsPlatform ?? defaultIsWindowsPlatform;

  /// 进程调用器（默认 `Process.run`）。
  final Future<ProcessResult> Function(String executable, List<String> args)
  _runProcess;

  /// 平台判定（默认 `Platform.isWindows`）。
  final bool Function() _isWindowsPlatform;

  /// 默认进程调用器。
  ///
  /// ⚠️ 测试环境硬闸门：`reg` 会**读写系统开机启动注册表**（持久副作用，比弹窗口
  /// 严重一个量级），单测若漏注入 `runProcess` 进来，这里直接抛错而不是真跑——
  /// 本接口返回 `ProcessResult`，静默拦截只能伪造结果，会更隐蔽地骗过测试。
  static Future<ProcessResult> _defaultRunProcess(
    String executable,
    List<String> arguments,
  ) {
    if (isRunningUnderTest) {
      throw StateError(
        '测试环境禁止真跑 `$executable`（会改动系统开机启动注册表）。'
        '请注入 runProcess 替身（见 startup_registrar_test.dart）。',
      );
    }
    return Process.run(executable, arguments);
  }

  /// 默认平台判定。
  static bool defaultIsWindowsPlatform() => Platform.isWindows;

  @override
  Future<bool> isRegistered() async {
    if (!_isWindowsPlatform()) return false;
    final result = await _runProcess('reg', [
      'query',
      startupRunKeyPath,
      '/v',
      startupValueName,
    ]);
    // reg query 退出码：0 存在，1 不存在（存在性判定不依赖本地化输出）。
    return result.exitCode == 0;
  }

  @override
  Future<void> setRegistered(bool registered, {String? command}) async {
    if (!_isWindowsPlatform()) return;
    if (registered) {
      await _runProcess('reg', [
        'add',
        startupRunKeyPath,
        '/v',
        startupValueName,
        '/t',
        'REG_SZ',
        '/d',
        command ?? '',
        '/f',
      ]);
    } else {
      // 值不存在时 reg delete 返回非零；删除语义幂等，忽略退出码。
      await _runProcess('reg', [
        'delete',
        startupRunKeyPath,
        '/v',
        startupValueName,
        '/f',
      ]);
    }
  }
}

/// 开机启动注册服务 Provider（默认 Windows 注册表实现，测试可 override 为 fake）。
final startupRegistrarProvider = Provider<StartupRegistrar>(
  (ref) => WindowsStartupRegistrar(),
);
