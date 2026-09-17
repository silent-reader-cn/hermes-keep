import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 无障碍显示偏好（#140 P2-b）。
///
/// 目前只有一项：[forceHighContrast]。默认 `false`。
///
/// **默认关闭的语义是「不干预」而非「强制关掉」**：关闭时应用完全不碰
/// `MediaQuery.highContrast`，系统辅助功能高对比度照常生效；打开时把
/// `highContrast` 强制为 `true`，让全部 Cupertino 动态色（含
/// `statusGreyText` / `CupertinoColors.systemGrey` 等）切到更强变体。
///
/// 之所以做成开关：本仓深色档的颜色字面量（如 `#8E8E93`）原本逐字节钉死，
/// 换成 [CupertinoColors.systemGrey] 会顺带拿走它的高对比度变体
/// （`#6C6C70` / `#AEAEB2`）——那对开启高对比的用户是好事，对没开的用户
/// 是意外变更。开关把「要不要」交给用户，默认态与既有像素逐字节一致。
class AccessibilitySettings {
  const AccessibilitySettings({this.forceHighContrast = false});

  /// 是否强制使用 Cupertino 的高对比度色变体。
  final bool forceHighContrast;

  AccessibilitySettings copyWith({bool? forceHighContrast}) {
    return AccessibilitySettings(
      forceHighContrast: forceHighContrast ?? this.forceHighContrast,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccessibilitySettings &&
          runtimeType == other.runtimeType &&
          forceHighContrast == other.forceHighContrast;

  @override
  int get hashCode => forceHighContrast.hashCode;

  @override
  String toString() =>
      'AccessibilitySettings(forceHighContrast: $forceHighContrast)';
}

/// 无障碍显示偏好 Provider（持久化到 shared_preferences）。
final accessibilitySettingsProvider =
    NotifierProvider<AccessibilitySettingsController, AccessibilitySettings>(
      AccessibilitySettingsController.new,
    );

/// 无障碍显示偏好 Controller。
class AccessibilitySettingsController extends Notifier<AccessibilitySettings> {
  /// 持久化键。
  static const String keyForceHighContrast = 'force_high_contrast';

  /// 读取「强制高对比度」偏好；缺失时 `false`（不干预）。
  ///
  /// 支持注入 [customPrefs] 以便测试使用 `SharedPreferences.setMockInitialValues`。
  static Future<bool> loadForcePref({SharedPreferences? customPrefs}) async {
    final prefs = customPrefs ?? await SharedPreferences.getInstance();
    return prefs.getBool(keyForceHighContrast) ?? false;
  }

  /// 写入「强制高对比度」偏好。
  static Future<void> saveForcePref(
    bool value, {
    SharedPreferences? customPrefs,
  }) async {
    final prefs = customPrefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(keyForceHighContrast, value);
  }

  @override
  AccessibilitySettings build() {
    unawaited(_load());
    return const AccessibilitySettings();
  }

  Future<void> _load() async {
    state = AccessibilitySettings(forceHighContrast: await loadForcePref());
  }

  /// 更新开关并立即持久化。
  Future<void> setForceHighContrast(bool value) async {
    state = state.copyWith(forceHighContrast: value);
    await saveForcePref(value);
  }
}
