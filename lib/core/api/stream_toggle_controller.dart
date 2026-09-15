import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 控制流开关状态及本地持久化的 Notifier 基类。
abstract class StreamToggleController extends Notifier<bool> {
  /// 持久化到 [SharedPreferences] 的 key。
  @protected
  String get storageKey;

  /// 读取指定 key 的开关偏好。读取失败或不存在时默认返回 true。
  @protected
  static Future<bool> loadPrefFor(
    String key, {
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? true;
    } catch (_) {
      return true;
    }
  }

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return true; // 默认 true
  }

  Future<void> _load() async {
    try {
      final value = await loadPrefFor(storageKey);
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // 单元测试无 SharedPreferences 时静默忽略
    }
  }

  /// 手动重新加载持久化偏好。
  Future<void> load() => _load();

  /// 更新开关状态并写入持久化存储。
  Future<void> setEnabled(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, value);
    } catch (_) {
      // 单元测试环境忽略
    }
  }
}
