import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 当前宿主的金照基线平台键：`windows` / `linux` / `macos`。
///
/// **金照是渲染环境的产物**：字体度量、CJK 字形回退、抗锯齿都随宿主平台变。
/// 因此基线按平台分目录存放（`test/golden/goldens/<平台>/`），各平台只与自己
/// 那份比对。
String get goldenPlatformKey => _platformKey();

String _platformKey() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  return Platform.operatingSystem;
}

/// 金照基线 key（相对 `test/golden/`）：`goldens/<平台>/<name>.png`。
///
/// key 里带平台段，故 `--update-goldens` 天然只写当前平台那一份，不会互相覆盖。
String goldenKey(String name) => 'goldens/$goldenPlatformKey/$name.png';

/// 当前平台是否已有 [name] 的金照基线。
bool hasGoldenBaseline(String name) =>
    File('test/golden/goldens/$goldenPlatformKey/$name.png').existsSync();

/// 无本平台基线时标记用例为「跳过」并返回 true（调用方应立即 return）。
///
/// 跳过而非失败：基线缺失是「本平台尚未建立该基线」的**已知缺口**，不是回归。
/// 拿别的平台的基线来比才是必然假红——2026-09-14 前 26 张金照在 CI（Linux）
/// 全红、本机（Windows）全绿，根因即此。
///
/// **`--update-goldens` 下必须放行**：[autoUpdateGoldenFiles] 为真时若仍跳过，
/// `matchesGoldenFile` 永不执行、基线永远生成不出来（首版即踩此坑：生成跑完
/// artifact 里只有既有的 windows/，linux/ 一张没有）。
///
/// 补基线：`flutter test --update-goldens test/golden/`，随后提交
/// `test/golden/goldens/<平台>/`。
bool skipIfNoGoldenBaseline(String name) {
  // 生成模式下不能跳过（此全局只可读：框架禁止测试内改写它）。
  if (autoUpdateGoldenFiles) {
    return false;
  }
  if (hasGoldenBaseline(name)) {
    return false;
  }
  markTestSkipped(
    '当前平台 $goldenPlatformKey 尚无金照基线 '
    '($goldenPlatformKey/$name.png)：跑 flutter test --update-goldens '
    'test/golden/ 生成后提交即可',
  );
  return true;
}
