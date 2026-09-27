import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'test_environment.dart';

/// 外部打开器接缝：把「用系统文件管理器打开某个路径」这件事收敛到一处。
///
/// ## 为什么必须有这道接缝
///
/// `explorer` / `open` / `xdg-open` 是**真实系统副作用**。在单测里直接调用
/// `Process.run('explorer', ...)`，每跑一次测试就会在开发机上真弹出一个资源管理器
/// 窗口，无人值守反复跑就会在桌面堆一大堆。历史上
/// `test/features/downloads/download_page_extra_test.dart` 正是如此（该用例还专门留了
/// 一句「本用例会真实调用资源管理器」的注释）。
///
/// ## 约定（铁律）
///
/// 1. `lib/` 内**禁止**裸调 `Process.run('explorer' | 'open' | 'xdg-open', ...)`，
///    一律经本类；护栏测试 `test/core/platform/external_opener_guard_test.dart` 兜底。
/// 2. 单测要断言「打开行为」时，注入 [processRunner] 记录调用，断言命令行拼装
///    （比原来「只要不抛异常就算过」覆盖面更大）。
/// 3. 未注入 runner 的 [ExternalOpener] 在 `flutter test` 环境下会被
///    **自动拦截**（见 [isTestEnvironment]），绝不拉起真实窗口——漏注入的测试
///    最多少一次断言，不会污染开发机。
class ExternalOpener {
  ExternalOpener({
    Future<void> Function(String executable, List<String> arguments)?
    processRunner,
    bool? isWindows,
    bool? isMacOS,
    bool? isLinux,
    void Function(String message)? onBlocked,
  }) : // 不用 initializing formal：那会把命名参数暴露成 `_processRunner:`，
       // 调用方写起来难看，故保留公开参数名 `processRunner` 转发到私有字段。
       // ignore: prefer_initializing_formals
       _processRunner = processRunner,
       _isWindows = isWindows ?? _platformIsWindows,
       _isMacOS = isMacOS ?? _platformIsMacOS,
       _isLinux = isLinux ?? _platformIsLinux,
       _onBlocked = onBlocked ?? debugPrint;

  /// 注入的系统调用执行器；为 null 表示「用真实的 [Process.run]」。
  final Future<void> Function(String executable, List<String> arguments)?
  _processRunner;

  final bool _isWindows;
  final bool _isMacOS;
  final bool _isLinux;

  /// 闸门拦截时的上报回调（默认 `debugPrint`，测试可注入以断言拦截发生过）。
  final void Function(String message) _onBlocked;

  static bool get _platformIsWindows => !kIsWeb && Platform.isWindows;
  static bool get _platformIsMacOS => !kIsWeb && Platform.isMacOS;
  static bool get _platformIsLinux => !kIsWeb && Platform.isLinux;

  /// 当前是否运行在 `flutter test` 里（判据见 `test_environment.dart`）。
  static bool get isTestEnvironment => isRunningUnderTest;

  /// 在文件管理器中**定位并高亮**某个文件（Windows 资源管理器 / macOS Finder）。
  Future<void> revealInFileManager(String path) async {
    if (_isWindows) {
      await _launch('explorer', <String>['/select,', path]);
      return;
    }
    if (_isMacOS) {
      await _launch('open', <String>['-R', path]);
      return;
    }
    if (_isLinux) {
      // xdg-open 没有「定位高亮」语义，退化为打开其所在目录。
      final parent = File(path).parent.path;
      await _launch('xdg-open', <String>[parent.isEmpty ? path : parent]);
    }
  }

  /// 用系统文件管理器**打开目录**。
  Future<void> openDirectory(String path) async {
    if (_isWindows) {
      await _launch('explorer', <String>[path]);
      return;
    }
    if (_isMacOS) {
      await _launch('open', <String>[path]);
      return;
    }
    if (_isLinux) {
      await _launch('xdg-open', <String>[path]);
    }
  }

  Future<void> _launch(String executable, List<String> arguments) async {
    final runner = _processRunner;
    if (runner != null) {
      await runner(executable, arguments);
      return;
    }
    if (isTestEnvironment) {
      // 测试环境硬闸门：绝不拉起真实系统窗口（否则无人值守跑测试会在桌面堆窗口）。
      _onBlocked(
        '[external_opener] 测试环境已拦截系统调用: '
        '$executable ${arguments.join(' ')}',
      );
      return;
    }
    await Process.run(executable, arguments);
  }
}

/// 全局外部打开器（生产默认实例；单测可通过 `overrideWithValue` 注入记录型实现）。
final externalOpenerProvider = Provider<ExternalOpener>(
  (ref) => ExternalOpener(),
);
