import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';

/// 目标缺口（lcov 实测，基线 31/53）：
///   32/40 ─ SystemProcessExecutor.run
///   48/57 ─ SystemProcessExecutor.start
///   83-112 ─ SystemFileSystemAdapter 全量成员
///   209/210 ─ installDetectorProvider
///
/// 说明：`SystemProcessExecutor` / `SystemFileSystemAdapter` 是生产默认实现，
/// 源码里没有可注入接缝（内部直接调 dart:io 静态 API），因此只能真实调用；
/// 进程调用一律使用「不存在的可执行文件」触发 ProcessException，
/// 成功路径只用宿主自带的 shell 执行无害 echo，不产生文件/注册表副作用。

/// 一定不存在的可执行文件名（用于打通 dart:io 的错误路径）。
const String _missingExecutable = 'hermes-cov-nonexistent-binary-9f3a1c';

/// 宿主自带 shell 的无害 echo 命令（Windows: cmd /c echo，POSIX: sh -c echo）。
List<String> _echoCommand(String marker) => Platform.isWindows
    ? <String>['cmd', '/c', 'echo', marker]
    : <String>['sh', '-c', 'echo $marker'];

String _join(Object? first, String child) =>
    '$first${Platform.pathSeparator}$child';

void main() {
  group('SystemProcessExecutor（生产默认进程执行器）', () {
    test('run：成功路径 —— 执行真实 shell echo 并回传 exitCode/stdout', () async {
      const executor = SystemProcessExecutor();
      final cmd = _echoCommand('hermes-cov-probe');

      final result = await executor.run(
        cmd.first,
        cmd.sublist(1),
        workingDirectory: Directory.current.path,
        environment: Map<String, String>.from(Platform.environment),
        runInShell: false,
      );

      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('hermes-cov-probe'));
      expect(result.stderr.toString(), isEmpty);
    });

    test('run：不存在的可执行文件 → ProcessException（错误原样抛出，不被吞掉）', () async {
      const executor = SystemProcessExecutor();

      await expectLater(
        executor.run(_missingExecutable, const <String>['--version']),
        throwsA(isA<ProcessException>()),
      );
    });

    test('start：成功路径 —— 启动真实 shell 并回传 exitCode', () async {
      const executor = SystemProcessExecutor();
      final cmd = _echoCommand('hermes-cov-start-probe');

      final process = await executor.start(
        cmd.first,
        cmd.sublist(1),
        workingDirectory: Directory.current.path,
        environment: Map<String, String>.from(Platform.environment),
        runInShell: false,
        mode: ProcessStartMode.normal,
      );

      expect(await process.exitCode, 0);
    });

    test('start：不存在的可执行文件 → ProcessException', () async {
      const executor = SystemProcessExecutor();

      await expectLater(
        executor.start(_missingExecutable, const <String>[]),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('SystemFileSystemAdapter（生产默认文件系统适配器）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hermes_cov_fs_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('directoryExists：不存在的多级路径 → false', () {
      const fs = SystemFileSystemAdapter();
      final missing = _join(_join(tempDir.path, 'nope'), 'deeper');

      expect(fs.directoryExists(missing), isFalse);
    });

    test('createDirectory：recursive 默认递归建整条链，directoryExists 随后为 true', () async {
      const fs = SystemFileSystemAdapter();
      final nested = _join(_join(_join(tempDir.path, 'a'), 'b'), 'c');

      await fs.createDirectory(nested);

      expect(fs.directoryExists(nested), isTrue);
      expect(fs.directoryExists(_join(tempDir.path, 'a')), isTrue);
    });

    test('createDirectory(recursive: false)：父目录已存在时创建子目录', () async {
      const fs = SystemFileSystemAdapter();
      final child = _join(tempDir.path, 'child');

      await fs.createDirectory(child, recursive: false);

      expect(fs.directoryExists(child), isTrue);
    });

    test('createDirectory 幂等：重复创建同一目录不抛异常', () async {
      const fs = SystemFileSystemAdapter();

      await fs.createDirectory(tempDir.path);
      await fs.createDirectory(tempDir.path);
      await fs.createDirectory(tempDir.path, recursive: false);

      expect(fs.directoryExists(tempDir.path), isTrue);
    });

    test('fileExists/writeString/readString：往返内容（含中文与换行）', () async {
      const fs = SystemFileSystemAdapter();
      final path = _join(tempDir.path, 'install.ps1');
      const content = '# 安装脚本\r\nWrite-Host "你好"\n\$env:HERMES=1\n';

      expect(fs.fileExists(path), isFalse);

      await fs.writeString(path, content);

      expect(fs.fileExists(path), isTrue);
      expect(await fs.readString(path), content);
    });

    test('writeString：覆盖写入 —— 后写内容完全替换先写内容', () async {
      const fs = SystemFileSystemAdapter();
      final path = _join(tempDir.path, 'overwrite.txt');

      await fs.writeString(path, 'first');
      await fs.writeString(path, 'second');

      expect(await fs.readString(path), 'second');
    });

    test('readString：文件不存在 → 抛出 FileSystemException', () async {
      const fs = SystemFileSystemAdapter();
      final path = _join(tempDir.path, 'missing.txt');

      await expectLater(
        fs.readString(path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('fileExists：目录路径 → false（只有普通文件才算存在）', () async {
      const fs = SystemFileSystemAdapter();

      expect(fs.fileExists(tempDir.path), isFalse);
      expect(fs.directoryExists(tempDir.path), isTrue);
    });

    test('localAppData：优先取 LOCALAPPDATA 环境变量，缺失时回落用户目录兜底', () {
      const fs = SystemFileSystemAdapter();
      final envValue = Platform.environment['LOCALAPPDATA'];

      if (envValue == null) {
        // 走 `?? (Platform.isWindows ? 'C:\\Users\\<USERNAME>\\AppData\\Local' : '')`
        if (Platform.isWindows) {
          expect(fs.localAppData, startsWith('C:\\Users\\'));
          expect(fs.localAppData, endsWith(r'\AppData\Local'));
        } else {
          expect(fs.localAppData, isEmpty);
        }
      } else {
        expect(fs.localAppData, envValue);
      }
    });

    test('isWindows / executablePath：对齐运行时平台事实', () {
      const fs = SystemFileSystemAdapter();

      expect(fs.isWindows, Platform.isWindows);
      expect(fs.executablePath, Platform.resolvedExecutable);
      expect(fs.executablePath, isNotEmpty);
    });
  });

  group('installDetectorProvider', () {
    test('默认 build → DefaultInstallDetector（生产装配未被替换）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final detector = container.read(installDetectorProvider);

      expect(detector, isA<DefaultInstallDetector>());
      expect(detector.isWindows, Platform.isWindows);
      // localAppDataPath 透传自 %LOCALAPPDATA%：Windows 上必有值，
      // 其余平台可能为空（CI 的 ubuntu runner 实测为空）—— 两端语义都钉住，
      // 不假设它一定非空。
      if (Platform.isWindows) {
        expect(detector.localAppDataPath, isNotEmpty);
      } else {
        expect(detector.localAppDataPath, isEmpty);
      }
    });

    test('override 注入 fake 后 read 返回注入实例（测试接缝有效）', () {
      final fake = _StubInstallDetector();
      final container = ProviderContainer(
        overrides: [installDetectorProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(installDetectorProvider), same(fake));
      expect(container.read(installDetectorProvider).isWindows, isTrue);
    });
  });
}

class _StubInstallDetector implements InstallDetector {
  @override
  String get localAppDataPath => r'C:\Users\Stub\AppData\Local';

  @override
  String get hermesHomePath => r'C:\Users\Stub\AppData\Local\hermes';

  @override
  String get hermesAgentPath => r'C:\Users\Stub\AppData\Local\hermes\hermes-agent';

  @override
  String get webuiPath => r'C:\Users\Stub\AppData\Local\hermes\webui';

  @override
  bool get isWindows => true;

  @override
  Future<bool> agentInstalled() async => true;

  @override
  bool bundledWebuiAvailable() => false;

  @override
  Future<bool> isInstalled() => agentInstalled();
}
