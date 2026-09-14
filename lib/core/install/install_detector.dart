import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform_paths.dart';

/// 进程执行器抽象（用于单测 mock Process.run / Process.start，禁止在测试中拉起真实系统进程）。
abstract interface class ProcessExecutor {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  });

  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  });
}

/// 生产环境默认进程执行器（封装 dart:io Process）。
class SystemProcessExecutor implements ProcessExecutor {
  const SystemProcessExecutor();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) =>
      Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: runInShell,
      );

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) =>
      Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: runInShell,
        mode: mode,
      );
}

/// 文件系统与环境检测抽象（支持单测 mock 路径与文件检查）。
abstract interface class FileSystemAdapter {
  bool directoryExists(String path);
  bool fileExists(String path);
  Future<void> createDirectory(String path, {bool recursive = true});
  Future<void> writeString(String path, String content);
  Future<String> readString(String path);
  String get localAppData;
  bool get isWindows;
  String get executablePath;
}

/// 生产环境默认文件系统适配器。
class SystemFileSystemAdapter implements FileSystemAdapter {
  const SystemFileSystemAdapter();

  @override
  bool directoryExists(String path) => Directory(path).existsSync();

  @override
  bool fileExists(String path) => File(path).existsSync();

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) =>
      Directory(path).create(recursive: recursive);

  @override
  Future<void> writeString(String path, String content) =>
      File(path).writeAsString(content);

  @override
  Future<String> readString(String path) =>
      File(path).readAsString();

  @override
  String get localAppData =>
      Platform.environment['LOCALAPPDATA'] ??
      (Platform.isWindows
          ? 'C:\\Users\\${Platform.environment['USERNAME'] ?? 'User'}\\AppData\\Local'
          : '');

  @override
  bool get isWindows => Platform.isWindows;

  @override
  String get executablePath => Platform.resolvedExecutable;
}

/// 本机已安装检测接口。
abstract interface class InstallDetector {
  /// 是否已安装 Hermes Agent（满足 hermes 命令在 PATH 中或 %LOCALAPPDATA%\hermes\hermes-agent 存在）。
  Future<bool> agentInstalled();

  /// 探测内置 WebUI 是否可用（`<exe目录>\webui\server\server.py` 存在）。
  bool bundledWebuiAvailable();

  /// 兼容旧方法：等同于 [agentInstalled]。
  Future<bool> isInstalled();

  /// %LOCALAPPDATA% 基础路径。
  String get localAppDataPath;

  /// %LOCALAPPDATA%\hermes 目录。
  String get hermesHomePath;

  /// %LOCALAPPDATA%\hermes\hermes-agent 目录。
  String get hermesAgentPath;

  /// %LOCALAPPDATA%\hermes\webui 目录。
  String get webuiPath;

  /// 当前是否为 Windows 平台。
  bool get isWindows;
}

/// [InstallDetector] 默认实现。
class DefaultInstallDetector implements InstallDetector {
  const DefaultInstallDetector({
    this.processExecutor = const SystemProcessExecutor(),
    this.fileSystem = const SystemFileSystemAdapter(),
  });

  final ProcessExecutor processExecutor;
  final FileSystemAdapter fileSystem;

  @override
  bool get isWindows => fileSystem.isWindows;

  @override
  String get localAppDataPath => fileSystem.localAppData;

  @override
  String get hermesHomePath {
    final base = localAppDataPath;
    if (base.isEmpty) return 'hermes';
    return '$base\\hermes';
  }

  @override
  String get hermesAgentPath => '$hermesHomePath\\hermes-agent';

  @override
  String get webuiPath => '$hermesHomePath\\webui';

  @override
  bool bundledWebuiAvailable() {
    if (!isWindows) return false;
    final exe = fileSystem.executablePath;
    if (exe.isEmpty) return false;
    // 用平台无关的父目录解析：File(exe).parent 走**宿主**路径规则，
    // Linux 上对 `C:\...\hermes.exe` 会得到 `.`，令本判定恒假。
    final exeDir = platformParentDir(exe);
    final serverPy = '$exeDir\\webui\\server\\server.py';
    return fileSystem.fileExists(serverPy);
  }

  @override
  Future<bool> agentInstalled() async {
    // 1. 优先检查 %LOCALAPPDATA%\hermes\hermes-agent 目录是否存在
    if (fileSystem.directoryExists(hermesAgentPath)) {
      return true;
    }

    // 2. 检查 hermes 命令是否在 PATH 中 (Windows: where.exe / Unix: which)
    try {
      final cmd = isWindows ? 'where.exe' : 'which';
      final res = await processExecutor.run(cmd, ['hermes']);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        return true;
      }
    } catch (_) {
      // 忽略检查异常
    }

    return false;
  }

  @override
  Future<bool> isInstalled() => agentInstalled();
}

/// [InstallDetector] 全局 Provider（测试中可通过 override 注入 fake）。
final installDetectorProvider = Provider<InstallDetector>(
  (ref) => const DefaultInstallDetector(),
);
