import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'install_detector.dart';

/// 安装事件类型。
enum InstallerEventType {
  manifest,
  stageStart,
  progress,
  log,
  stageSuccess,
  stageFailure,
}

/// 安装事件帧。
class InstallerEvent {
  const InstallerEvent({
    required this.type,
    this.stage,
    this.title,
    this.message,
    this.progress,
    this.reason,
    this.stages,
    this.raw = '',
  });

  final InstallerEventType type;
  final String? stage;
  final String? title;
  final String? message;
  final double? progress; // 0.0 ~ 1.0
  final String? reason;
  final List<String>? stages;
  final String raw;

  factory InstallerEvent.manifest(List<String> stages, {String raw = ''}) =>
      InstallerEvent(
        type: InstallerEventType.manifest,
        stages: stages,
        raw: raw,
      );

  factory InstallerEvent.stageStart(
    String stage, {
    String? title,
    String? message,
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.stageStart,
        stage: stage,
        title: title,
        message: message,
        raw: raw,
      );

  factory InstallerEvent.progress(
    String stage,
    double progress, {
    String? message,
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.progress,
        stage: stage,
        progress: progress,
        message: message,
        raw: raw,
      );

  factory InstallerEvent.log(
    String message, {
    String? stage,
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.log,
        stage: stage,
        message: message,
        raw: raw,
      );

  factory InstallerEvent.stageSuccess(
    String stage, {
    String? message,
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.stageSuccess,
        stage: stage,
        message: message,
        raw: raw,
      );

  factory InstallerEvent.stageFailure(
    String stage,
    String reason, {
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.stageFailure,
        stage: stage,
        reason: reason,
        raw: raw,
      );

  /// 逐行解析 stdout / stderr 为事件帧（非 JSON 字符串优雅降级为 log）。
  factory InstallerEvent.parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return InstallerEvent.log('', raw: line);
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        // 1. 处理 { "ok": false, "stage": ..., "reason": ... }
        if (decoded['ok'] == false) {
          return InstallerEvent.stageFailure(
            decoded['stage']?.toString() ?? 'unknown',
            decoded['reason']?.toString() ??
                decoded['message']?.toString() ??
                decoded['error']?.toString() ??
                'Stage failed',
            raw: line,
          );
        }

        // 2. 处理 { "ok": true, "stage": ... }
        if (decoded['ok'] == true && decoded['event'] == null) {
          return InstallerEvent.stageSuccess(
            decoded['stage']?.toString() ?? '',
            message: decoded['message']?.toString(),
            raw: line,
          );
        }

        // 3. 处理具名 event 结构
        final event =
            decoded['event']?.toString() ?? decoded['type']?.toString();
        switch (event) {
          case 'manifest':
            final list = (decoded['stages'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const [];
            return InstallerEvent.manifest(list, raw: line);
          case 'stage_start':
          case 'start':
            return InstallerEvent.stageStart(
              decoded['stage']?.toString() ?? '',
              title:
                  decoded['title']?.toString() ?? decoded['name']?.toString(),
              message: decoded['message']?.toString(),
              raw: line,
            );
          case 'progress':
            final pct = decoded['percent'] ?? decoded['progress'];
            double progressVal = 0.0;
            if (pct is num) {
              progressVal = pct > 1.0 ? pct / 100.0 : pct.toDouble();
            }
            return InstallerEvent.progress(
              decoded['stage']?.toString() ?? '',
              progressVal,
              message: decoded['message']?.toString(),
              raw: line,
            );
          case 'stage_success':
          case 'stage_done':
          case 'done':
            return InstallerEvent.stageSuccess(
              decoded['stage']?.toString() ?? '',
              message: decoded['message']?.toString(),
              raw: line,
            );
          case 'stage_failure':
          case 'error':
            return InstallerEvent.stageFailure(
              decoded['stage']?.toString() ?? '',
              decoded['reason']?.toString() ??
                  decoded['message']?.toString() ??
                  'Stage failed',
              raw: line,
            );
          case 'log':
          default:
            return InstallerEvent.log(
              decoded['message']?.toString() ??
                  decoded['line']?.toString() ??
                  trimmed,
              stage: decoded['stage']?.toString(),
              raw: line,
            );
        }
      }
    } catch (_) {
      // 非 JSON 格式 → 降级为 log
    }
    return InstallerEvent.log(trimmed, raw: line);
  }
}

/// HTTP 脚本下载器抽象（测试可注入 fake）。
abstract interface class ScriptDownloader {
  Future<String> downloadScript(String url);
}

/// 默认生产脚本下载器（基于 HttpClient）。
class SystemScriptDownloader implements ScriptDownloader {
  const SystemScriptDownloader();

  @override
  Future<String> downloadScript(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return await res.transform(utf8.decoder).join();
      }
      throw HttpException('Failed to download script: HTTP ${res.statusCode}');
    } finally {
      client.close();
    }
  }
}

/// PowerShell 安装器接口。
abstract interface class PowershellInstaller {
  static const String defaultScriptUrl =
      'https://hermes-agent.nousresearch.com/install.ps1';

  /// 确保 install.ps1 脚本已缓存到本地。
  Future<String> ensureScriptCached({
    String url = defaultScriptUrl,
    String? destinationPath,
  });

  /// 获取官方支持的 stage 列表清单。
  Future<List<String>> getManifest({String? scriptPath});

  /// 运行单个 stage，逐行流式产生事件帧。
  Stream<InstallerEvent> runStage(
    String stageName, {
    String? scriptPath,
    String? hermesHome,
  });
}

/// [PowershellInstaller] 生产默认实现。
class DefaultPowershellInstaller implements PowershellInstaller {
  DefaultPowershellInstaller({
    this.processExecutor = const SystemProcessExecutor(),
    this.fileSystem = const SystemFileSystemAdapter(),
    this.downloader = const SystemScriptDownloader(),
  });

  final ProcessExecutor processExecutor;
  final FileSystemAdapter fileSystem;
  final ScriptDownloader downloader;

  String get _defaultScriptPath {
    final base = fileSystem.localAppData;
    if (base.isEmpty) return 'install.ps1';
    return '$base\\hermes\\install.ps1';
  }

  @override
  Future<String> ensureScriptCached({
    String url = PowershellInstaller.defaultScriptUrl,
    String? destinationPath,
  }) async {
    final targetPath = destinationPath ?? _defaultScriptPath;
    if (fileSystem.fileExists(targetPath)) {
      return targetPath;
    }

    // 确保父目录存在
    final lastSlash = targetPath.lastIndexOf(Platform.pathSeparator);
    if (lastSlash > 0) {
      final dir = targetPath.substring(0, lastSlash);
      await fileSystem.createDirectory(dir);
    }

    try {
      final content = await downloader.downloadScript(url);
      await fileSystem.writeString(targetPath, content);
      return targetPath;
    } catch (e) {
      // 若下载失败且本地不存在，抛出带提示的异常
      throw Exception(
        '下载官方 install.ps1 失败，请检查网络或手动下载并放置到: $targetPath\n原因: $e',
      );
    }
  }

  @override
  Future<List<String>> getManifest({String? scriptPath}) async {
    final path = scriptPath ?? _defaultScriptPath;
    try {
      final res = await processExecutor.run('powershell', [
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        path,
        '-Manifest',
        '-NonInteractive',
        '-Json',
      ]);
      if (res.exitCode == 0) {
        final lines = LineSplitter.split(res.stdout.toString());
        for (final line in lines) {
          final event = InstallerEvent.parseLine(line);
          if (event.type == InstallerEventType.manifest &&
              event.stages != null &&
              event.stages!.isNotEmpty) {
            return event.stages!;
          }
        }
      }
    } catch (_) {
      // 忽略异常，降级到默认清单
    }
    return const ['prereqs', 'agent', 'deps'];
  }

  @override
  Stream<InstallerEvent> runStage(
    String stageName, {
    String? scriptPath,
    String? hermesHome,
  }) {
    final controller = StreamController<InstallerEvent>();
    final path = scriptPath ?? _defaultScriptPath;
    final home = hermesHome ??
        (fileSystem.localAppData.isNotEmpty
            ? '${fileSystem.localAppData}\\hermes'
            : null);

    controller.add(InstallerEvent.stageStart(
      stageName,
      title: 'Executing stage: $stageName',
    ));

    final args = <String>[
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      path,
      '-Stage',
      stageName,
      '-NonInteractive',
      '-Json',
    ];
    if (home != null && home.isNotEmpty) {
      args.addAll(['-HermesHome', home]);
    }

    unawaited(() async {
      Process? process;
      try {
        process = await processExecutor.start('powershell', args);
      } catch (e) {
        controller.add(InstallerEvent.stageFailure(
          stageName,
          '无法启动 PowerShell 进程: $e',
        ));
        await controller.close();
        return;
      }

      var hadFailure = false;
      void handleLine(String line) {
        final event = InstallerEvent.parseLine(line);
        if (event.type == InstallerEventType.stageFailure) {
          hadFailure = true;
        }
        controller.add(event);
      }

      final outSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine);

      final errSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          handleLine(line);
        }
      });

      // ⚠️ asFuture 必须在流 close 之前挂上：进程退出后 stdout/stderr 已 done，
      // 此时再调 asFuture 永远不会收到完成事件 → Future.wait 永不 resolve
      //（stdout 零输出的 stage 会静默卡死，既无成功终帧也无失败终帧）。
      final outDone = outSub.asFuture<void>();
      final errDone = errSub.asFuture<void>();
      final exitCode = await process.exitCode;
      await Future.wait([outDone, errDone]);

      if (exitCode != 0 && !hadFailure) {
        controller.add(InstallerEvent.stageFailure(
          stageName,
          'PowerShell 退出异常，退出码: $exitCode',
        ));
      } else if (exitCode == 0 && !hadFailure) {
        controller.add(InstallerEvent.stageSuccess(
          stageName,
          message: 'Stage $stageName completed successfully',
        ));
      }
      await controller.close();
    }());

    return controller.stream;
  }
}

/// [PowershellInstaller] Provider。
final powershellInstallerProvider = Provider<PowershellInstaller>(
  (ref) => DefaultPowershellInstaller(),
);
