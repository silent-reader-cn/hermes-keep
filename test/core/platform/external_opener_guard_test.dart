import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 护栏：`explorer` / `open` / `xdg-open` 这类**外部文件管理器调用**必须经
/// `ExternalOpener` 接缝，禁止在 `lib/` 或 `test/` 里裸调 `Process.run`。
///
/// ## 为什么需要这条护栏
///
/// `Process.run('explorer', ...)` 是真实系统副作用：单测里走到它就是**真的在开发机上
/// 弹出一个资源管理器窗口**。历史上 `download_page_extra_test.dart` 正是如此，每次跑
/// 那组测试都多一个窗口，无人值守反复跑就会在桌面堆一大堆。接缝本身（带测试环境硬闸门）
/// 只能拦住「经由接缝」的调用，拦不住新代码直接裸调——这条扫描就是补上那一半。
///
/// 误报排除：只扫**代码行**，`//` 注释行跳过（文档里出现命令样例是允许的）。
void main() {
  test('lib/ 与 test/ 内禁止裸调 explorer / open / xdg-open（须走 ExternalOpener 接缝）', () {
    // 本文件自身含有用于扫描的 pattern 字面量，按文件名排除。
    const exemptNames = <String>{'external_opener_guard_test.dart'};

    final pattern = RegExp(
      r'''Process\.(run|start|runSync)\(\s*["'](explorer|open|xdg-open)["']''',
    );

    final offenders = <String>[];
    for (final root in <String>['lib', 'test']) {
      final dir = Directory(root);
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'flutter test 的工作目录应为项目根（找不到 $root/）',
      );
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (exemptNames.contains(entity.uri.pathSegments.last)) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (pattern.hasMatch(line)) {
            offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '以下位置裸调了系统文件管理器命令——单测一旦走到就会真弹窗口，'
          '请改为经 ExternalOpener 接缝（注入 processRunner 以便断言）：\n'
          '${offenders.join('\n')}',
    );
  });
}
