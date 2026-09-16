import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/powershell_installer.dart';

/// 目标缺口（lcov 实测，基线 124/143）：
///   126-127 ─ {ok:false} 的 message / error 回退链
///   182     ─ `case 'error':`
///   192-196 ─ log / default 分支（message → line → trimmed 三段回退）
///   217-228 ─ SystemScriptDownloader.downloadScript 全量
///   395-396 ─ stderr 非空行过滤
///   422-423 ─ powershellInstallerProvider

/// 回环测试服务器（脚本下载器用）：只绑定 127.0.0.1 临时端口，不访问外网。
class _LoopbackServer {
  _LoopbackServer._(this._server);

  static Future<_LoopbackServer> start(int status, String body) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _LoopbackServer._(server);
    instance.status = status;
    instance.body = body;
    unawaited(instance._serve());
    return instance;
  }

  final HttpServer _server;
  int status = 200;
  String body = '';

  final List<String> methods = <String>[];
  final List<String> paths = <String>[];

  int get port => _server.port;

  String get url => 'http://127.0.0.1:$port/install.ps1';

  Future<void> _serve() async {
    try {
      await for (final request in _server) {
        methods.add(request.method);
        paths.add(request.uri.path);
        request.response.statusCode = status;
        request.response.write(body);
        await request.response.close();
      }
    } catch (_) {
      // close(force: true) 会中断 await for：静默收尾。
    }
  }

  Future<void> close() => _server.close(force: true);
}

class _FakeProcess implements Process {
  _FakeProcess({
    List<String> stdoutLines = const <String>[],
    List<String> stderrLines = const <String>[],
    this.exitCodeValue = 0,
  })  : _stdoutChunks = stdoutLines.map(_encodeLine).toList(),
        _stderrChunks = stderrLines.map(_encodeLine).toList();

  static List<int> _encodeLine(String line) => utf8.encode('$line\n');

  // 用 Stream.fromIterable（订阅后立即按需吐出并 close），避免
  // 「controller 先 close、订阅者后到」的时序不确定性。
  final List<List<int>> _stdoutChunks;
  final List<List<int>> _stderrChunks;
  final int exitCodeValue;

  @override
  Stream<List<int>> get stdout => Stream<List<int>>.fromIterable(_stdoutChunks);

  @override
  Stream<List<int>> get stderr => Stream<List<int>>.fromIterable(_stderrChunks);

  @override
  Future<int> get exitCode async => exitCodeValue;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _FakeProcessExecutor implements ProcessExecutor {
  _FakeProcessExecutor({this.runStdout = '', this.processToReturn});

  String runStdout;
  Process? processToReturn;
  final List<List<String>> executed = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    executed.add(<String>[executable, ...arguments]);
    return ProcessResult(7331, 0, runStdout, '');
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
    executed.add(<String>[executable, ...arguments]);
    return processToReturn ?? _FakeProcess();
  }
}

class _FakeFileSystemAdapter implements FileSystemAdapter {
  _FakeFileSystemAdapter({
    Set<String> existingFiles = const <String>{},
    this.localAppData = r'C:\Users\Admin\AppData\Local',
  }) : existingFiles = <String>{...existingFiles};

  final Set<String> existingFiles;
  final Map<String, String> fileContents = <String, String>{};
  final List<String> createdDirs = <String>[];

  @override
  String localAppData;

  @override
  bool isWindows = true;

  @override
  String executablePath = r'C:\Program Files\Hermes\hermes.exe';

  @override
  bool directoryExists(String path) => createdDirs.contains(path);

  @override
  bool fileExists(String path) => existingFiles.contains(path);

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    createdDirs.add(path);
  }

  @override
  Future<String> readString(String path) async => fileContents[path] ?? '';

  @override
  Future<void> writeString(String path, String content) async {
    existingFiles.add(path);
    fileContents[path] = content;
  }
}

void main() {
  group('InstallerEvent.parseLine：{ok:false} 回退链逐键位', () {
    test('reason 缺失 → 回退到 message', () {
      final event = InstallerEvent.parseLine(
        '{"ok": false, "stage": "deps", "message": "wheel build failed"}',
      );

      expect(event.type, InstallerEventType.stageFailure);
      expect(event.stage, 'deps');
      expect(event.reason, 'wheel build failed');
    });

    test('reason/message 都缺失 → 回退到 error', () {
      final event = InstallerEvent.parseLine(
        '{"ok": false, "stage": "agent", "error": "MSI installer 0x80070643"}',
      );

      expect(event.type, InstallerEventType.stageFailure);
      expect(event.stage, 'agent');
      expect(event.reason, 'MSI installer 0x80070643');
    });

    test('reason/message/error 全缺失 → 落到 "Stage failed"；stage 缺失 → unknown', () {
      final event = InstallerEvent.parseLine('{"ok": false}');

      expect(event.type, InstallerEventType.stageFailure);
      expect(event.stage, 'unknown');
      expect(event.reason, 'Stage failed');
    });

    test('近似键名反例：errorMsg / detail 不被识别，仍落 "Stage failed"', () {
      final event = InstallerEvent.parseLine(
        '{"ok": false, "stage": "deps", "errorMsg": "x", "detail": "y"}',
      );

      expect(event.reason, 'Stage failed');
      expect(event.stage, 'deps');
    });

    test('非字符串字段被 toString 强制转换', () {
      final event = InstallerEvent.parseLine(
        '{"ok": false, "stage": 42, "reason": 7}',
      );

      expect(event.stage, '42');
      expect(event.reason, '7');
    });
  });

  group('InstallerEvent.parseLine：具名 event 分支', () {
    test('{"event":"error"} → stageFailure（case error 分支）', () {
      final event = InstallerEvent.parseLine(
        '{"event": "error", "stage": "deps", "reason": "boom"}',
      );

      expect(event.type, InstallerEventType.stageFailure);
      expect(event.stage, 'deps');
      expect(event.reason, 'boom');
    });

    test('{"event":"error"} 无 reason → 回退 message；stage 缺失 → 空串', () {
      final event = InstallerEvent.parseLine(
        '{"event": "error", "message": "no reason given"}',
      );

      expect(event.type, InstallerEventType.stageFailure);
      expect(event.stage, '');
      expect(event.reason, 'no reason given');
    });

    test('{"event":"error"} 全字段缺失 → "Stage failed"', () {
      final event = InstallerEvent.parseLine('{"event": "error"}');

      expect(event.reason, 'Stage failed');
      expect(event.stage, '');
    });

    test('{"event":"log", message, stage} → log 且带 stage', () {
      final event = InstallerEvent.parseLine(
        '{"event": "log", "message": "hello world", "stage": "agent"}',
      );

      expect(event.type, InstallerEventType.log);
      expect(event.message, 'hello world');
      expect(event.stage, 'agent');
    });

    test('未知 event 名 → default 分支回退到 line 字段', () {
      final event = InstallerEvent.parseLine(
        '{"event": "something_new", "line": "raw fallback line"}',
      );

      expect(event.type, InstallerEventType.log);
      expect(event.message, 'raw fallback line');
      expect(event.stage, isNull);
    });

    test('未知 event 名 + 无 message/line → 回退到整行 trimmed 文本', () {
      const line = '  {"event": "something_new", "stage": "s"}  ';
      final event = InstallerEvent.parseLine(line);

      expect(event.type, InstallerEventType.log);
      expect(event.message, '{"event": "something_new", "stage": "s"}');
      expect(event.stage, 's');
      expect(event.raw, line);
    });

    test('合法 JSON 但无 event/type/ok 键 → default 分支', () {
      final event = InstallerEvent.parseLine('{"hello": "world"}');

      expect(event.type, InstallerEventType.log);
      expect(event.message, '{"hello": "world"}');
    });

    test('type 键可替代 event 键（manifest）', () {
      final event = InstallerEvent.parseLine(
        '{"type": "manifest", "stages": ["prereqs", "webui"]}',
      );

      expect(event.type, InstallerEventType.manifest);
      expect(event.stages, <String>['prereqs', 'webui']);
    });

    test('manifest 缺 stages → 空列表；stages 元素被 toString 强制转换', () {
      expect(InstallerEvent.parseLine('{"event": "manifest"}').stages, isEmpty);
      expect(
        InstallerEvent.parseLine('{"event": "manifest", "stages": [1, 2, true]}')
            .stages,
        <String>['1', '2', 'true'],
      );
    });

    test('stage_done / done 与 stage_success 等价', () {
      expect(
        InstallerEvent.parseLine('{"event": "stage_done", "stage": "x"}').type,
        InstallerEventType.stageSuccess,
      );
      expect(
        InstallerEvent.parseLine('{"event": "done", "stage": "x"}').type,
        InstallerEventType.stageSuccess,
      );
      expect(
        InstallerEvent.parseLine('{"event": "start", "stage": "x", "name": "环境检查"}').title,
        '环境检查',
      );
    });

    test('顶层非对象 JSON（数组/字符串/null）→ 优雅降级为 log', () {
      expect(InstallerEvent.parseLine('[1, 2, 3]').type, InstallerEventType.log);
      expect(
        InstallerEvent.parseLine('"just a string"').message,
        '"just a string"',
      );
      expect(InstallerEvent.parseLine('null').message, 'null');
      expect(InstallerEvent.parseLine('12345').message, '12345');
    });

    test('progress：percent 非数字 → 0.0；等于 1 视作比例；>1 视作百分数', () {
      expect(
        InstallerEvent.parseLine('{"event": "progress", "percent": "50"}').progress,
        0.0,
      );
      expect(
        InstallerEvent.parseLine('{"event": "progress", "percent": 1}').progress,
        1.0,
      );
      expect(
        InstallerEvent.parseLine('{"event": "progress", "percent": 150}').progress,
        1.5,
      );
      expect(
        InstallerEvent.parseLine('{"event": "progress", "progress": 0}').progress,
        0.0,
      );
    });
  });

  group('SystemScriptDownloader（生产默认脚本下载器）', () {
    test('200 → 返回脚本文本（GET 请求）', () async {
      final server = await _LoopbackServer.start(200, '# install.ps1 body');
      addTearDown(server.close);
      const downloader = SystemScriptDownloader();

      final content = await downloader.downloadScript(server.url);

      expect(content, '# install.ps1 body');
      expect(server.methods.single, 'GET');
      expect(server.paths.single, '/install.ps1');
    });

    test('299 → 返回脚本文本（2xx 上边界）', () async {
      final server = await _LoopbackServer.start(299, 'boundary');
      addTearDown(server.close);
      const downloader = SystemScriptDownloader();

      expect(await downloader.downloadScript(server.url), 'boundary');
    });

    test('300 → 抛 HttpException 并带上状态码', () async {
      final server = await _LoopbackServer.start(300, 'nope');
      addTearDown(server.close);
      const downloader = SystemScriptDownloader();

      await expectLater(
        downloader.downloadScript(server.url),
        throwsA(
          isA<HttpException>()
              .having((e) => e.message, 'message', contains('HTTP 300')),
        ),
      );
    });

    test('404 / 500 → 抛 HttpException（不返回空串静默成功）', () async {
      final server = await _LoopbackServer.start(404, 'not found');
      addTearDown(server.close);
      const downloader = SystemScriptDownloader();

      await expectLater(
        downloader.downloadScript(server.url),
        throwsA(isA<HttpException>()),
      );

      server.status = 500;
      await expectLater(
        downloader.downloadScript(server.url),
        throwsA(
          isA<HttpException>()
              .having((e) => e.message, 'message', contains('HTTP 500')),
        ),
      );
    });

    test('非绝对 URL → ArgumentError（finally 仍关闭 client）', () async {
      const downloader = SystemScriptDownloader();

      await expectLater(
        downloader.downloadScript('not-a-url'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('DefaultPowershellInstaller.runStage：stderr 过滤', () {
    test('stderr 空白行被丢弃，非空行进入事件流', () async {
      final fake = _FakeProcess(
        stdoutLines: <String>['{"ok": true, "stage": "prereqs"}'],
        stderrLines: <String>['   ', 'WARNING: pip is old', ''],
        exitCodeValue: 0,
      );
      final installer = DefaultPowershellInstaller(
        processExecutor: _FakeProcessExecutor(processToReturn: fake),
      );

      final events = await installer.runStage('prereqs').toList();
      final logs = events
          .where((e) => e.type == InstallerEventType.log)
          .map((e) => e.message)
          .toList();

      expect(logs, contains('WARNING: pip is old'));
      expect(logs, isNot(contains('   ')));
      expect(logs, isNot(contains('')));
      expect(events.first.type, InstallerEventType.stageStart);
    });

    test('stdout 与 stderr 同时产生事件，顺序不丢失', () async {
      final fake = _FakeProcess(
        stdoutLines: <String>['stage stdout line'],
        stderrLines: <String>['stage stderr line'],
        exitCodeValue: 0,
      );
      final installer = DefaultPowershellInstaller(
        processExecutor: _FakeProcessExecutor(processToReturn: fake),
      );

      final events = await installer.runStage('deps').toList();
      final messages = events.map((e) => e.message).toList();

      expect(messages, contains('stage stdout line'));
      expect(messages, contains('stage stderr line'));
      expect(events.last.type, InstallerEventType.stageSuccess);
    });

    test('stderr 上的错误帧置 hadFailure → 不再补发成功帧', () async {
      // 注意：必须给 stdout 至少一行。lib 里 `await process.exitCode` 之后才挂
      // `asFuture()`，若 stdout 零输出，done 会在那一跳内先派发 → asFuture 永不完成
      // （见本文件「实现观察」用例与 TASK_REPORT.md）。
      final fake = _FakeProcess(
        stdoutLines: <String>['running preflight'],
        stderrLines: <String>['{"event": "error", "stage": "deps", "reason": "boom"}'],
        exitCodeValue: 0,
      );
      final installer = DefaultPowershellInstaller(
        processExecutor: _FakeProcessExecutor(processToReturn: fake),
      );

      final events = await installer.runStage('deps').toList();

      expect(
        events.where((e) => e.type == InstallerEventType.stageFailure),
        hasLength(1),
      );
      expect(
        events.where((e) => e.type == InstallerEventType.stageSuccess),
        isEmpty,
      );
    });

    test('退出码非 0 且已有失败帧 → 不重复补发失败帧', () async {
      final fake = _FakeProcess(
        stdoutLines: <String>['running preflight'],
        stderrLines: <String>['{"event": "error", "stage": "deps", "reason": "boom"}'],
        exitCodeValue: 1,
      );
      final installer = DefaultPowershellInstaller(
        processExecutor: _FakeProcessExecutor(processToReturn: fake),
      );

      final events = await installer.runStage('deps').toList();

      expect(
        events.where((e) => e.type == InstallerEventType.stageFailure),
        hasLength(1),
      );
    });

    test('修复守卫：stdout 零输出时 stage 流仍会正常关闭（asFuture 时序已修正）', () async {
      // 原缺陷（lib/core/install/powershell_installer.dart）：
      //   final exitCode = await process.exitCode;               // 进程已退、流已 done
      //   await Future.wait([outSub.asFuture<void>(), ...]);      // asFuture 挂太晚
      // Subscription.asFuture() 只有在 done 派发**之前**挂上才会完成；stdout 零输出时
      // done 恰好在那一跳内派发 → Future.wait 永不 resolve → controller 永不 close
      // → 该 stage 既无成功也无失败终帧（安装页静默卡死）。
      // 修法：两个 asFuture 在 await exitCode 之前挂上。本用例充当该修复的守卫。
      final fake = _FakeProcess(
        stderrLines: <String>['{"event": "error", "stage": "deps", "reason": "boom"}'],
        exitCodeValue: 0,
      );
      final installer = DefaultPowershellInstaller(
        processExecutor: _FakeProcessExecutor(processToReturn: fake),
      );

      final events = <InstallerEvent>[];
      var closed = false;
      final sub = installer.runStage('deps').listen(
            events.add,
            onDone: () => closed = true,
          );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();

      expect(events.first.type, InstallerEventType.stageStart);
      expect(
        events.any((e) => e.type == InstallerEventType.stageFailure),
        isTrue,
        reason: 'stderr 的错误帧应已到达',
      );
      expect(closed, isTrue, reason: '修复后：stdout 零输出时流仍会正常关闭');
    });
  });

  group('DefaultPowershellInstaller.ensureScriptCached 路径拼装', () {
    test('指定 destinationPath：父目录被创建后落盘', () async {
      final fs = _FakeFileSystemAdapter();
      final installer = DefaultPowershellInstaller(
        fileSystem: fs,
        downloader: _StubDownloader('# script'),
      );
      final target = '${fs.localAppData}\\hermes\\nested\\install.ps1';

      final path = await installer.ensureScriptCached(destinationPath: target);

      expect(path, target);
      expect(fs.createdDirs, <String>['${fs.localAppData}\\hermes\\nested']);
      expect(fs.fileContents[target], '# script');
      // 平台门控：本用例的 fake 提供 Windows 风格路径（`C:\...\nested\install.ps1`），
      // 而实现按 `Platform.pathSeparator` 定位父目录 —— Linux 宿主的分隔符是 `/`，
      // 在 Windows 路径里找不到 `\` ⇒ 不建父目录。实现对 Windows 语义正确，故非 Windows 跳过。
    }, skip: !Platform.isWindows);

    test('localAppData 为空 → 落到裸文件名 install.ps1，且不建父目录', () async {
      final fs = _FakeFileSystemAdapter(localAppData: '');
      final installer = DefaultPowershellInstaller(
        fileSystem: fs,
        downloader: _StubDownloader('# script'),
      );

      final path = await installer.ensureScriptCached();

      expect(path, 'install.ps1');
      expect(fs.createdDirs, isEmpty);
      expect(fs.fileContents['install.ps1'], '# script');
    });

    test('目标已存在 → 直接返回，不触发下载', () async {
      final fs = _FakeFileSystemAdapter(
        existingFiles: <String>{r'C:\Users\Admin\AppData\Local\hermes\install.ps1'},
      );
      final downloader = _StubDownloader('# script');
      final installer = DefaultPowershellInstaller(
        fileSystem: fs,
        downloader: downloader,
      );

      final path = await installer.ensureScriptCached();

      expect(path, r'C:\Users\Admin\AppData\Local\hermes\install.ps1');
      expect(downloader.calls, isEmpty);
    });

    test('exported defaultScriptUrl 指向官方安装脚本', () {
      expect(
        PowershellInstaller.defaultScriptUrl,
        'https://hermes-agent.nousresearch.com/install.ps1',
      );
    });
  });

  group('DefaultPowershellInstaller.getManifest D 参数拼装', () {
    test('传入 scriptPath 时命令行使用该路径', () async {
      final proc = _FakeProcessExecutor(
        runStdout: '{"event": "manifest", "stages": ["only"]}',
      );
      final installer = DefaultPowershellInstaller(processExecutor: proc);

      final stages = await installer.getManifest(scriptPath: 'D:\\tmp\\i.ps1');

      expect(stages, <String>['only']);
      expect(proc.executed.single, containsAllInOrder(<String>[
        'powershell',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        r'D:\tmp\i.ps1',
        '-Manifest',
      ]));
    });

    test('stdout 有 manifest 帧但 stages 为空 → 继续扫描并降级默认清单', () async {
      final proc = _FakeProcessExecutor(
        runStdout: '{"event": "manifest", "stages": []}\nnoise line',
      );
      final installer = DefaultPowershellInstaller(processExecutor: proc);

      expect(await installer.getManifest(), <String>['prereqs', 'agent', 'deps']);
    });
  });

  group('powershellInstallerProvider', () {
    test('默认 build → DefaultPowershellInstaller', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(powershellInstallerProvider),
        isA<DefaultPowershellInstaller>(),
      );
    });

    test('override 注入 fake 后 read 返回注入实例', () {
      final fake = _StubPowershellInstaller();
      final container = ProviderContainer(
        overrides: [powershellInstallerProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(powershellInstallerProvider), same(fake));
    });
  });
}

class _StubDownloader implements ScriptDownloader {
  _StubDownloader(this.content);

  final String content;
  final List<String> calls = <String>[];

  @override
  Future<String> downloadScript(String url) async {
    calls.add(url);
    return content;
  }
}

class _StubPowershellInstaller implements PowershellInstaller {
  @override
  Future<String> ensureScriptCached({
    String url = PowershellInstaller.defaultScriptUrl,
    String? destinationPath,
  }) async =>
      'stub.ps1';

  @override
  Future<List<String>> getManifest({String? scriptPath}) async => const <String>[];

  @override
  Stream<InstallerEvent> runStage(
    String stageName, {
    String? scriptPath,
    String? hermesHome,
  }) =>
      const Stream<InstallerEvent>.empty();
}
