import 'dart:io';

import 'package:flutter/foundation.dart';

/// 是否运行在 `flutter test` 里。
///
/// `flutter_test` 会往测试进程注入 `FLUTTER_TEST=true`（实测可读：
/// `FLUTTER_TEST_KEYS=[FLUTTER_TEST, FLUTTER_ROOT, FLUTTER_TOOLS_DIR]`），
/// 这是运行时判断「当前是自动化测试」的可靠判据；产品运行时该变量不存在。
///
/// ## 用途：系统副作用的统一硬闸门
///
/// 凡**默认实现带真实系统副作用**的接缝（外部文件管理器、子进程执行器、
/// 注册表写入……）都读这个判据，在测试环境里拒绝真跑。理由：单测一旦走到真实
/// 副作用，会在开发机上弹窗口 / 写注册表 / 跑安装脚本，且无人值守反复跑会积攒。
///
/// 两种处置口径（按返回值语义选，勿混用）：
/// - 返回 `void`（如外部打开器）：**静默拦截 + 上报**（`debugPrint` / 注入回调）；
/// - 返回真实结果（如 `ProcessResult`）：**显式抛 `StateError`**——假装返回空结果
///   等于伪造事实，比真跑更危险。
bool get isRunningUnderTest =>
    !kIsWeb && (Platform.environment['FLUTTER_TEST'] ?? '') == 'true';
