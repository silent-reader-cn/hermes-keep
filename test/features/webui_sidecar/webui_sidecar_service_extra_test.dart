// WebUI Sidecar 补测二批：缺口区间专项（不真起子进程、不真联网）。
//
// 覆盖目标（行号以 lib/features/webui_sidecar/webui_sidecar_service.dart 为准）：
//   30-39   SystemPortProber（本机回环真实探测，仅 127.0.0.1，不出网）
//   124-131 DefaultSidecarFileSystem 注入接缝下的 envSidecarRoot / defaultSidecarDir
//   150-218 日志路径 + 真实文件操作 + resolveBundleDir / isBundleAvailable
//   228     扩展快路径（DefaultSidecarFileSystem）
//   237-249 扩展动态回退链
//   362-363 extractMissingDependency 关键字回退链
//   432-434 默认指数退避计算
//   461     并发 start 去重
//   545     自愈重启遇端口被占
//   611-620 子进程启动异常（含自愈分支）
//   714-738 接管巡检 watchdog（含重叠巡检在非 running 态撤除的守卫分支）
//   793-794 stop 早退守卫
//   803-804 restart 链路
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/webui_bootstrap.dart';
import 'package:hermes_ui/core/platform_paths.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_service.dart';

/// 轮询等待条件成立（失败即抛错，避免假绿）。
Future<void> _waitFor(
  bool Function() condition, {
  Duration limit = const Duration(seconds: 3),
  String label = 'condition',
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > limit) {
      throw StateError('waitFor 超时：$label');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// 可注入的假子进程（exitCode 由测试手动完成）。
class _FakeProcess implements Process {
  _FakeProcess({required this.pid});

  @override
  final int pid;

  final Completer<int> _exitCompleter = Completer<int>();
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>.broadcast();

  bool killed = false;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  void emitStdout(String text) => _stdoutController.add(utf8.encode(text));

  void emitStderr(String text) => _stderrController.add(utf8.encode(text));

  void completeExit(int code) {
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(code);
    }
  }
}

/// 可注入的假进程执行器（支持「start 抛异常」开关）。
class _FakeProcessExecutor implements ProcessExecutor {
  _FakeProcessExecutor(this.processFactory);

  _FakeProcess Function() processFactory;

  FutureOr<ProcessResult> Function(String executable, List<String> arguments)?
      runHandler;

  /// 非空时 [start] 直接抛出该异常（走 spawn 异常分支）。
  Object? startError;

  final List<Map<String, dynamic>> startCalls = <Map<String, dynamic>>[];
  final List<List<String>> runCalls = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    runCalls.add(<String>[executable, ...arguments]);
    final handler = runHandler;
    if (handler != null) {
      return await handler(executable, arguments);
    }
    return ProcessResult(1001, 0, '', '');
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    startCalls.add(<String, dynamic>{
      'executable': executable,
      'arguments': arguments,
      'workingDirectory': workingDirectory,
      'environment': environment,
    });
    final error = startError;
    if (error != null) {
      throw error;
    }
    return processFactory();
  }
}

/// 可注入的假端口探测器。
class _FakePortProber implements PortProber {
  bool isOpen = false;
  final List<Map<String, dynamic>> probeCalls = <Map<String, dynamic>>[];

  @override
  Future<bool> isPortOpen(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    probeCalls.add(<String, dynamic>{'host': host, 'port': port});
    return isOpen;
  }
}

/// 可编排的假健康检查器。
///
/// 用「本次调用之前是否发生过一次端口探测」+「服务是否 running」把调用者分开：
/// - 巡检（`_startWatchdog` 的 takeover 定时器）只在 running 态、且不带端口探测；
/// - `_performStart` 的健康检查总跟在端口探测之后，或发生在非 running 态。
/// 因此可以分别编排「巡检响应」与「启动链响应」，让重叠巡检等时序分支可确定复现。
class _ScriptedHealthChecker implements HealthChecker {
  _ScriptedHealthChecker(this.prober);

  final _FakePortProber prober;

  /// 启动链（`_performStart`）里的 /health 响应。
  bool chainResponse = true;

  /// 巡检（takeover watchdog）里的 /health 响应（[tickHold] 为 false 时生效）。
  bool tickResponse = true;

  /// 为 true 时巡检调用挂起不返回 → 同一计时器的多次巡检重叠在飞行中。
  bool tickHold = false;

  final List<Completer<bool>> tickPending = <Completer<bool>>[];

  int tickCalls = 0;
  int chainCalls = 0;
  int _probeAtLastCall = 0;

  /// 由测试在服务构造后接线，用于判定当前状态。
  SidecarStatus Function()? statusGetter;

  @override
  Future<bool> checkHealth(String url) async {
    final probes = prober.probeCalls.length;
    final looksLikeChainCall = probes > _probeAtLastCall;
    _probeAtLastCall = probes;
    final status = statusGetter?.call() ?? SidecarStatus.stopped;
    final isChainCall = looksLikeChainCall || status != SidecarStatus.running;

    if (isChainCall) {
      chainCalls++;
      return chainResponse;
    }

    tickCalls++;
    if (!tickHold) {
      return tickResponse;
    }
    final completer = Completer<bool>();
    tickPending.add(completer);
    return completer.future;
  }
}

/// 可注入的假 Sidecar 文件系统。
class _FakeSidecarFileSystem implements SidecarFileSystem {
  @override
  bool isWindows = true;

  bool bundleAvailable = true;
  String root = r'C:\app\webui';
  String agentDir = r'C:\Users\Admin\AppData\Local\hermes\hermes-agent';

  final List<String> logLines = <String>[];
  int rotateCalls = 0;

  @override
  String? get envSidecarRoot => null;

  @override
  String get defaultSidecarDir => root;

  String get hermesAgentDir => agentDir;

  @override
  String get logDirectoryPath =>
      r'C:\Users\Admin\AppData\Local\hermes\webui-bundled\logs';

  @override
  String get logFilePath =>
      r'C:\Users\Admin\AppData\Local\hermes\webui-bundled\logs\webui.log';

  @override
  bool directoryExists(String path) => true;

  @override
  bool fileExists(String path) => true;

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  Future<void> appendLogLine(String path, String line) async {
    logLines.add(line);
  }

  @override
  Future<void> rotateLogIfNeeded(
    String path, {
    int maxSizeBytes = 5 * 1024 * 1024,
  }) async {
    rotateCalls++;
  }

  @override
  String resolveBundleDir() => root;

  @override
  bool isBundleAvailable() => isWindows && bundleAvailable;
}

/// 最小实现（**刻意不声明** `hermesAgentDir`），用于打通扩展的动态回退链。
class _BareSidecarFileSystem implements SidecarFileSystem {
  _BareSidecarFileSystem({required this.logDirectoryPath});

  @override
  bool get isWindows => true;

  @override
  final String logDirectoryPath;

  @override
  String get logFilePath => '$logDirectoryPath\\webui.log';

  @override
  String get defaultSidecarDir => r'C:\app\webui';

  @override
  String? get envSidecarRoot => null;

  @override
  String resolveBundleDir() => defaultSidecarDir;

  @override
  bool isBundleAvailable() => false;

  @override
  bool fileExists(String path) => false;

  @override
  bool directoryExists(String path) => false;

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  Future<void> appendLogLine(String path, String line) async {}

  @override
  Future<void> rotateLogIfNeeded(
    String path, {
    int maxSizeBytes = 5 * 1024 * 1024,
  }) async {}
}

/// 动态属性取到**空串** → 扩展回退链必须继续往下走。
class _EmptyAgentDirFileSystem extends _BareSidecarFileSystem {
  _EmptyAgentDirFileSystem({required super.logDirectoryPath});

  String get hermesAgentDir => '';
}

/// 动态属性**类型不符** → 扩展回退链必须继续往下走。
class _NonStringAgentDirFileSystem extends _BareSidecarFileSystem {
  _NonStringAgentDirFileSystem({required super.logDirectoryPath});

  Object get hermesAgentDir => 42;
}

void main() {
  group('SystemPortProber：本机回环真实探测（不起子进程、不出网）', () {
    test('回环端口有监听 → true（走真实 connect 成功分支）', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sub = server.listen((socket) => socket.destroy());
      addTearDown(() async {
        await sub.cancel();
        await server.close();
      });

      const prober = SystemPortProber();
      expect(
        await prober.isPortOpen(
          '127.0.0.1',
          server.port,
          timeout: const Duration(seconds: 2),
        ),
        isTrue,
      );
    });

    test('回环端口已释放 → false（走异常捕获分支）', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      const prober = SystemPortProber();
      expect(
        await prober.isPortOpen(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 500),
        ),
        isFalse,
      );
    });

    test('host 为 0.0.0.0 时连接目标改写为 127.0.0.1', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sub = server.listen((socket) => socket.destroy());
      addTearDown(() async {
        await sub.cancel();
        await server.close();
      });

      const prober = SystemPortProber();
      expect(
        await prober.isPortOpen(
          '0.0.0.0',
          server.port,
          timeout: const Duration(seconds: 2),
        ),
        isTrue,
      );
    });
  });

  group('DefaultSidecarFileSystem：注入接缝下的路径与环境分支', () {
    test('envSidecarRoot 走注入值；defaultSidecarDir 按 exe 父目录拼 webui', () {
      const fs = DefaultSidecarFileSystem(
        customIsWindows: true,
        customEnvRoot: r'D:\bundle',
        customExePath: r'E:\apps\hermes.exe',
      );

      expect(fs.envSidecarRoot, r'D:\bundle');
      expect(fs.defaultSidecarDir, r'E:\apps\webui');
    });

    test('envSidecarRoot 未注入 → 读宿主环境变量；exe 未注入 → 用当前可执行文件', () {
      const fs = DefaultSidecarFileSystem(customIsWindows: true);

      expect(fs.envSidecarRoot, Platform.environment['HERMES_UI_SIDECAR_ROOT']);
      expect(
        fs.defaultSidecarDir,
        '${platformParentDir(Platform.resolvedExecutable)}\\webui',
      );
    });

    test('日志路径与 Agent 目录按注入 LOCALAPPDATA 拼装', () {
      const fs = DefaultSidecarFileSystem(
        customIsWindows: true,
        customLocalAppData: r'D:\AppData',
      );

      expect(fs.logDirectoryPath, r'D:\AppData\hermes\webui-bundled\logs');
      expect(
        fs.logFilePath,
        r'D:\AppData\hermes\webui-bundled\logs\webui.log',
      );
      expect(fs.hermesAgentDir, r'D:\AppData\hermes\hermes-agent');
    });

    test('未注入 LOCALAPPDATA → 回落宿主 LOCALAPPDATA（缺失分支不可注入，见报告）', () {
      const fs = DefaultSidecarFileSystem(customIsWindows: true);
      final base = Platform.environment['LOCALAPPDATA'];

      if (base != null) {
        expect(fs.logDirectoryPath, '$base\\hermes\\webui-bundled\\logs');
      }
      expect(fs.logFilePath.endsWith(r'\webui.log'), isTrue);
      expect(fs.hermesAgentDir.endsWith(r'\hermes\hermes-agent'), isTrue);
    });
  });

  group('DefaultSidecarFileSystem：真实临时目录下的文件操作与包探测', () {
    late Directory tempRoot;
    final bool hostIsWindows = Platform.isWindows;
    final String sep = platformPathSeparator(Platform.isWindows);

    DefaultSidecarFileSystem hostFs({String? envRoot}) =>
        DefaultSidecarFileSystem(
          customIsWindows: hostIsWindows,
          customEnvRoot: envRoot,
        );

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('hermes_sidecar_extra_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('fileExists / directoryExists / createDirectory 命中真实文件系统', () async {
      final fs = hostFs();
      final dir = '${tempRoot.path}/nested/deep';

      expect(fs.directoryExists(dir), isFalse);
      await fs.createDirectory(dir);
      expect(fs.directoryExists(dir), isTrue);

      final file = '$dir/probe.txt';
      expect(fs.fileExists(file), isFalse);
      File(file).writeAsStringSync('x');
      expect(fs.fileExists(file), isTrue);
    });

    test('appendLogLine 自动建目录并按行追加', () async {
      final fs = hostFs();
      final path = '${tempRoot.path}/logs/webui.log';

      await fs.appendLogLine(path, 'first');
      await fs.appendLogLine(path, 'second');

      expect(File(path).readAsStringSync(), 'first\nsecond\n');
    });

    test('rotateLogIfNeeded 达阈值轮转为 .1（旧 .1 先删）', () async {
      final fs = hostFs();
      final path = '${tempRoot.path}/logs/webui.log';
      File(path).createSync(recursive: true);
      File(path).writeAsStringSync('x' * 64);
      File('$path.1').createSync(recursive: true);
      File('$path.1').writeAsStringSync('stale');

      await fs.rotateLogIfNeeded(path, maxSizeBytes: 16);

      expect(File(path).existsSync(), isFalse);
      expect(File('$path.1').readAsStringSync(), 'x' * 64);
    });

    test('rotateLogIfNeeded 未达阈值不轮转；文件不存在时静默', () async {
      final fs = hostFs();
      final path = '${tempRoot.path}/logs/webui.log';
      File(path).createSync(recursive: true);
      File(path).writeAsStringSync('small');

      await fs.rotateLogIfNeeded(path, maxSizeBytes: 1024);
      expect(File(path).readAsStringSync(), 'small');
      expect(File('$path.1').existsSync(), isFalse);

      final missing = '${tempRoot.path}/missing/none.log';
      await fs.rotateLogIfNeeded(missing);
      expect(File(missing).existsSync(), isFalse);
    });

    test('resolveBundleDir：env 直挂 server.py → env 本身且包可用', () {
      final env = '${tempRoot.path}/direct';
      File('$env/server/server.py').createSync(recursive: true);
      final fs = hostFs(envRoot: env);

      expect(fs.resolveBundleDir(), env);
      expect(fs.isBundleAvailable(), hostIsWindows);
    });

    test('resolveBundleDir：env 下嵌套 webui/server.py → <env>${sep}webui', () {
      final env = '${tempRoot.path}/nested';
      File('$env/webui/server/server.py').createSync(recursive: true);
      final fs = hostFs(envRoot: env);

      expect(fs.resolveBundleDir(), '$env${sep}webui');
      expect(fs.isBundleAvailable(), hostIsWindows);
    });

    test('resolveBundleDir：两者皆无 → 回落 env 本身且包不可用', () {
      final env = '${tempRoot.path}/empty';
      Directory(env).createSync(recursive: true);
      final fs = hostFs(envRoot: env);

      expect(fs.resolveBundleDir(), env);
      expect(fs.isBundleAvailable(), isFalse);
    });

    test('resolveBundleDir：env 未注入（空串）→ 回落 defaultSidecarDir；非 Windows 恒不可用', () {
      final fsNoEnv = hostFs(envRoot: '');
      expect(fsNoEnv.resolveBundleDir(), fsNoEnv.defaultSidecarDir);

      const fsNoEnvWin = DefaultSidecarFileSystem(
        customIsWindows: true,
        customEnvRoot: '',
        customExePath: r'E:\apps\hermes.exe',
      );
      expect(fsNoEnvWin.resolveBundleDir(), r'E:\apps\webui');
      expect(fsNoEnvWin.isBundleAvailable(), isFalse);

      const fsPosix = DefaultSidecarFileSystem(
        customIsWindows: false,
        customEnvRoot: '',
      );
      expect(fsPosix.isBundleAvailable(), isFalse);
    });
  });

  group('SidecarFileSystem.hermesAgentDir 扩展：多形态回退链', () {
    test('DefaultSidecarFileSystem 走快路径（含注入 Agent 目录）', () {
      const SidecarFileSystem custom = DefaultSidecarFileSystem(
        customIsWindows: true,
        customAgentDir: r'Z:\Agent',
      );
      expect(custom.hermesAgentDir, r'Z:\Agent');

      const SidecarFileSystem derived = DefaultSidecarFileSystem(
        customIsWindows: true,
        customLocalAppData: r'D:\AppData',
      );
      expect(derived.hermesAgentDir, r'D:\AppData\hermes\hermes-agent');
    });

    test('实现类无该属性 → 按 logDirectoryPath 中的 hermes 段推导', () {
      final SidecarFileSystem fs = _BareSidecarFileSystem(
        logDirectoryPath: r'C:\Users\u\AppData\Local\hermes\webui-bundled\logs',
      );

      expect(fs.hermesAgentDir, r'C:\Users\u\AppData\Local\hermes\hermes-agent');
    });

    test('动态属性为空串 → 回退链继续', () {
      final SidecarFileSystem fs = _EmptyAgentDirFileSystem(
        logDirectoryPath: r'C:\AppData\hermes\logs',
      );

      expect(fs.hermesAgentDir, r'C:\AppData\hermes\hermes-agent');
    });

    test('动态属性类型不符 → 回退链继续', () {
      final SidecarFileSystem fs = _NonStringAgentDirFileSystem(
        logDirectoryPath: r'C:\AppData\hermes\logs',
      );

      expect(fs.hermesAgentDir, r'C:\AppData\hermes\hermes-agent');
    });

    test('logDirectoryPath 不含 hermes 段 → 回落宿主 LOCALAPPDATA', () {
      final SidecarFileSystem fs = _BareSidecarFileSystem(
        logDirectoryPath: r'C:\logs',
      );
      final base = Platform.environment['LOCALAPPDATA'];

      if (base != null) {
        expect(fs.hermesAgentDir, '$base\\hermes\\hermes-agent');
      } else {
        expect(fs.hermesAgentDir, endsWith(r'\hermes\hermes-agent'));
      }
    });
  });

  group('extractMissingDependency：正则优先 + 关键字回退链', () {
    test('正则命中非空模块名 → 原样返回', () {
      expect(
        DefaultWebuiSidecarService.extractMissingDependency(
          "ModuleNotFoundError: No module named 'numpy'",
        ),
        'numpy',
      );
    });

    test('正则命中但模块名为空 → 落关键字回退链尾部', () {
      expect(
        DefaultWebuiSidecarService.extractMissingDependency(
          "ModuleNotFoundError: No module named ''",
        ),
        'yaml, cryptography',
      );
    });

    test('正则未命中但含 yaml 关键字 → yaml', () {
      expect(
        DefaultWebuiSidecarService.extractMissingDependency(
          'ImportError: cannot import name yaml',
        ),
        'yaml',
      );
    });

    test('两个关键字并存 → yaml 优先（回退链顺序）', () {
      expect(
        DefaultWebuiSidecarService.extractMissingDependency(
          'both yaml and cryptography failed',
        ),
        'yaml',
      );
    });

    test('正则未命中且只有 cryptography → cryptography', () {
      expect(
        DefaultWebuiSidecarService.extractMissingDependency(
          'ImportError: cryptography backend unavailable',
        ),
        'cryptography',
      );
    });

    test('无任何线索 → 双模块兜底', () {
      expect(
        DefaultWebuiSidecarService.extractMissingDependency('unknown failure'),
        'yaml, cryptography',
      );
    });
  });

  group('DefaultWebuiSidecarService 生命周期控制流', () {
    late _FakePortProber prober;
    late _ScriptedHealthChecker health;
    late _FakeProcessExecutor executor;
    late _FakeSidecarFileSystem fs;
    late List<_FakeProcess> spawned;
    late SidecarConfig config;

    setUp(() {
      prober = _FakePortProber();
      health = _ScriptedHealthChecker(prober);
      spawned = <_FakeProcess>[];
      executor = _FakeProcessExecutor(() {
        final process = _FakeProcess(pid: 4321 + spawned.length);
        spawned.add(process);
        return process;
      });
      fs = _FakeSidecarFileSystem();
      config = const SidecarConfig(
        enabled: true,
        host: '127.0.0.1',
        port: 8787,
        password: 'tok',
      );
    });

    DefaultWebuiSidecarService buildService({
      Duration healthTimeout = const Duration(seconds: 30),
      Duration healthInterval = const Duration(milliseconds: 5),
      Duration takeoverInterval = const Duration(milliseconds: 10),
      Duration stopGracePeriod = const Duration(milliseconds: 20),
      bool defaultBackoff = false,
    }) {
      final service = defaultBackoff
          ? DefaultWebuiSidecarService(
              getConfig: () => config,
              processExecutor: executor,
              fileSystem: fs,
              healthChecker: health,
              portProber: prober,
              healthTimeout: healthTimeout,
              healthInterval: healthInterval,
              takeoverInterval: takeoverInterval,
              stopGracePeriod: stopGracePeriod,
            )
          : DefaultWebuiSidecarService(
              getConfig: () => config,
              processExecutor: executor,
              fileSystem: fs,
              healthChecker: health,
              portProber: prober,
              healthTimeout: healthTimeout,
              healthInterval: healthInterval,
              takeoverInterval: takeoverInterval,
              stopGracePeriod: stopGracePeriod,
              backoffCalculator: (_) => Duration.zero,
            );
      health.statusGetter = () => service.currentState.status;
      return service;
    }

    test('并发 start：第二次调用命中进行中短路，只拉起一次子进程', () async {
      final service = buildService(
        healthTimeout: const Duration(milliseconds: 200),
      );

      final first = service.start();
      final second = service.start();

      expect(identical(first, second), isFalse);
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(executor.startCalls.length, 1);
      expect(prober.probeCalls.length, 1);
      expect(service.currentState.status, SidecarStatus.running);
      expect(service.currentState.pid, 4321);

      await service.stop();
    });

    test('stop 早退：未启动状态下不广播状态、不动进程', () async {
      final service = buildService();
      final emitted = <SidecarState>[];
      final sub = service.states.listen(emitted.add);

      await service.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emitted, isEmpty);
      expect(executor.runCalls, isEmpty);
      expect(service.currentState, SidecarState.initial);

      await sub.cancel();
    });

    test('stop 重复调用：已 stopped 且无进程时早退，不重复广播', () async {
      final service = buildService();
      await service.start();

      final emitted = <SidecarState>[];
      final sub = service.states.listen(emitted.add);

      await service.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final afterFirst = emitted.length;
      expect(afterFirst, greaterThan(0));
      expect(emitted.last.status, SidecarStatus.stopped);

      await service.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emitted.length, afterFirst);

      await sub.cancel();
    });

    test('restart：先停旧进程（taskkill 兜底）再拉起新进程', () async {
      final service = buildService();
      final seen = <SidecarStatus>[];
      final sub = service.states.listen((state) => seen.add(state.status));

      await service.start();
      expect(executor.startCalls.length, 1);
      final firstProcess = spawned.first;

      await service.restart();

      expect(firstProcess.killed, isTrue);
      expect(
        executor.runCalls.any(
          (call) =>
              call[0] == 'taskkill' &&
              call.contains('/PID') &&
              call.contains('4321'),
        ),
        isTrue,
      );
      expect(executor.startCalls.length, 2);
      expect(service.currentState.status, SidecarStatus.running);
      expect(service.currentState.pid, 4322);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        seen,
        containsAllInOrder(<SidecarStatus>[
          SidecarStatus.running,
          SidecarStatus.stopped,
          SidecarStatus.running,
        ]),
      );

      await sub.cancel();
      await service.stop();
    });

    test('子进程启动抛异常 → failed(startFailed) 且不激活巡检', () async {
      final service = buildService();
      executor.startError = Exception('spawn boom');

      final states = <SidecarState>[];
      final sub = service.states.listen(states.add);

      await service.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(service.currentState.status, SidecarStatus.failed);
      expect(service.currentState.reason, SidecarFailureReason.startFailed);
      expect(
        service.currentState.detail,
        contains('Failed to start WebUI child process'),
      );
      expect(service.currentState.detail, contains('spawn boom'));
      expect(executor.startCalls.length, 1);
      expect(
        states.any((state) => state.status == SidecarStatus.starting),
        isTrue,
      );
      expect(
        executor.runCalls.any((call) => call[0] == 'taskkill'),
        isFalse,
      );

      await sub.cancel();
    });

    test('自愈重启中启动抛异常 → 继续自愈直至连续失败上限', () async {
      final service = buildService();
      await service.start();
      expect(service.currentState.status, SidecarStatus.running);

      executor.startError = Exception('spawn boom on heal');
      spawned.first.completeExit(1);

      await _waitFor(
        () => service.currentState.status == SidecarStatus.failed,
        label: '自愈达上限',
      );

      expect(service.currentState.reason, SidecarFailureReason.startFailed);
      expect(
        service.currentState.detail,
        contains('consecutive failures reached limit'),
      );
      expect(
        service.currentState.detail,
        contains('Process start exception'),
      );

      await service.stop();
    });

    test('自愈重启遇端口被陌生服务占用 → 持续自愈直至连续失败上限', () async {
      final service = buildService();
      await service.start();
      expect(service.currentState.status, SidecarStatus.running);

      prober.isOpen = true;
      health.chainResponse = false;

      final seen = <SidecarState>[];
      final sub = service.states.listen(seen.add);

      spawned.first.completeExit(1);

      await _waitFor(
        () => service.currentState.status == SidecarStatus.failed,
        label: '端口占用自愈收敛',
      );

      expect(
        seen.any(
          (state) =>
              state.reason == SidecarFailureReason.portOccupied &&
              (state.detail ?? '').contains('already occupied'),
        ),
        isTrue,
      );
      expect(service.currentState.reason, SidecarFailureReason.startFailed);
      expect(
        service.currentState.detail,
        contains('consecutive failures reached limit'),
      );
      expect(
        service.currentState.detail,
        contains('Port 8787 occupied during restart'),
      );
      expect(executor.startCalls.length, 1);

      await sub.cancel();
      await service.stop();
    });

    test('未注入 backoffCalculator → 走默认指数退避（attempt 1 = 1s）', () async {
      prober.isOpen = true;
      final service = buildService(defaultBackoff: true);
      final stopwatch = Stopwatch()..start();
      final timeline = <MapEntry<String, Duration>>[];
      final sub = service.states.listen(
        (state) => timeline.add(
          MapEntry<String, Duration>(state.detail ?? '${state.status}', stopwatch.elapsed),
        ),
      );

      await service.start();
      expect(service.currentState.detail, 'Takeover mode');

      health.tickResponse = false;
      await _waitFor(
        () => timeline.any((entry) => entry.key == 'restarting (attempt 1)'),
        label: '巡检连续失败触发自愈',
      );

      final restartIndex = timeline.indexWhere(
        (entry) => entry.key == 'restarting (attempt 1)',
      );
      final restartAt = timeline[restartIndex].value;

      await _waitFor(
        () => timeline.any(
          (entry) => entry.key == 'Takeover mode' && entry.value > restartAt,
        ),
        label: '退避结束后重新接管',
      );
      final resumedAt = timeline
          .firstWhere(
            (entry) => entry.key == 'Takeover mode' && entry.value > restartAt,
          )
          .value;
      final gap = resumedAt - restartAt;

      // 默认退避 = min(30, 2^(attempt-1)) 秒 → attempt 1 为 1 秒。
      expect(gap.inMilliseconds, greaterThanOrEqualTo(900));
      expect(gap.inMilliseconds, lessThan(5000));

      health.tickResponse = true;
      await _waitFor(
        () => service.currentState.detail == 'Takeover mode',
        label: '巡检恢复正常',
      );

      await sub.cancel();
      await service.stop();
    });
  });

  group('接管模式 watchdog 巡检', () {
    late _FakePortProber prober;
    late _ScriptedHealthChecker health;
    late _FakeProcessExecutor executor;
    late _FakeSidecarFileSystem fs;

    setUp(() {
      prober = _FakePortProber()..isOpen = true;
      health = _ScriptedHealthChecker(prober);
      executor = _FakeProcessExecutor(() => _FakeProcess(pid: 4321));
      fs = _FakeSidecarFileSystem();
    });

    DefaultWebuiSidecarService buildService({
      Duration healthTimeout = const Duration(milliseconds: 120),
      Duration healthInterval = const Duration(milliseconds: 40),
      Duration takeoverInterval = const Duration(milliseconds: 10),
      Duration stopGracePeriod = const Duration(milliseconds: 10),
    }) {
      final service = DefaultWebuiSidecarService(
        getConfig: () => const SidecarConfig(
          enabled: true,
          host: '127.0.0.1',
          port: 8787,
          password: 'tok',
        ),
        processExecutor: executor,
        fileSystem: fs,
        healthChecker: health,
        portProber: prober,
        healthTimeout: healthTimeout,
        healthInterval: healthInterval,
        takeoverInterval: takeoverInterval,
        stopGracePeriod: stopGracePeriod,
        backoffCalculator: (_) => Duration.zero,
      );
      health.statusGetter = () => service.currentState.status;
      return service;
    }

    test('接管巡检健康：保持 running 且 stop 后巡检停止', () async {
      final service = buildService();
      await service.start();

      expect(service.currentState.status, SidecarStatus.running);
      expect(service.currentState.pid, isNull);
      expect(service.currentState.detail, 'Takeover mode');
      final chainCallsAfterStart = health.chainCalls;

      await _waitFor(() => health.tickCalls >= 3, label: '巡检至少 3 次');

      expect(health.chainCalls, chainCallsAfterStart);
      expect(service.currentState.status, SidecarStatus.running);
      expect(service.currentState.detail, 'Takeover mode');
      expect(executor.startCalls, isEmpty);

      await service.stop();
      expect(service.currentState.status, SidecarStatus.stopped);

      final ticksAtStop = health.tickCalls;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(health.tickCalls, ticksAtStop);
    });

    test('接管巡检连续 3 次失败 → 撤除巡检并触发自愈，自愈后重新武装', () async {
      final service = buildService();
      final seen = <String>[];
      final sub = service.states.listen(
        (state) => seen.add(state.detail ?? '${state.status}'),
      );

      await service.start();
      await _waitFor(() => seen.isNotEmpty, label: '接管态广播');
      expect(seen.first, 'Takeover mode');

      health.tickResponse = false;
      await _waitFor(
        () => seen.contains('restarting (attempt 1)'),
        label: '3 连败触发自愈',
      );

      health.tickResponse = true;
      await _waitFor(
        () =>
            seen.where((detail) => detail == 'Takeover mode').length >= 2 &&
            service.currentState.detail == 'Takeover mode',
        label: '自愈后重新接管',
      );

      expect(
        seen,
        containsAllInOrder(<String>[
          'Takeover mode',
          'restarting (attempt 1)',
          'Takeover mode',
        ]),
      );
      expect(prober.probeCalls.length, greaterThanOrEqualTo(2));
      expect(executor.startCalls, isEmpty);

      await sub.cancel();
      await service.stop();
    });

    test('接管巡检重叠：自愈重启期间旧巡检在非 running 态自行撤除', () async {
      final service = buildService();
      final seen = <SidecarStatus>[];
      final sub = service.states.listen((state) => seen.add(state.status));

      await service.start();
      expect(service.currentState.detail, 'Takeover mode');

      // 巡检调用挂起 → 同一计时器的多次巡检重叠在飞行中。
      health.tickHold = true;
      await _waitFor(
        () => health.tickPending.length >= 5,
        label: '巡检重叠堆积',
      );

      // 第 3 次失败：撤除计时器并触发自愈链 A（端口仍占用 + 健康 → 重新武装计时器）。
      health.tickPending.removeAt(0).complete(false);
      health.tickPending.removeAt(0).complete(false);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      health.tickPending.removeAt(0).complete(false);
      await _waitFor(() => health.chainCalls >= 2, label: '自愈链 A 端口探测');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 第 4 次失败：端口已空闲 → 自愈链 B 走 spawn 分支进入 starting，
      // 此时计时器仍在巡检 → 下一拍命中「非 running 即自我撤除」守卫分支。
      health.chainResponse = false;
      prober.isOpen = false;
      final startCallsBefore = executor.startCalls.length;
      health.tickPending.removeAt(0).complete(false);

      await _waitFor(
        () => executor.startCalls.length > startCallsBefore,
        label: '自愈链 B 拉起子进程',
      );
      await _waitFor(
        () => seen.contains(SidecarStatus.starting),
        label: '进入 starting',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final ticksAfterGuard = health.tickCalls;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(health.tickCalls, ticksAfterGuard);

      await _waitFor(
        () =>
            service.currentState.status == SidecarStatus.failed &&
            (service.currentState.detail ?? '').contains('Auto-healing stopped'),
        label: '自愈循环收敛到连续失败上限',
      );
      expect(service.currentState.reason, SidecarFailureReason.startFailed);
      expect(
        service.currentState.detail,
        contains('Auto-healing stopped'),
      );

      await sub.cancel();
      await service.stop();
    });
  });
}
