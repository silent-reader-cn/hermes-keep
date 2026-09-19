import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'github_release.dart';
import 'version_info.dart';

/// SharedPreferences 键：自动检查更新是否开启（默认 true）。
const String kAutoCheckUpdateEnabledKey = 'auto_check_update_enabled';

/// SharedPreferences 键：上次检查更新时间（ISO8601 格式）。
const String kLastUpdateCheckAtKey = 'last_update_check_at';

/// GitHub 最新 Release 接口 URL。
const String kGithubReleasesLatestUrl =
    'https://api.github.com/repos/silent-reader-cn/hermes-keep/releases/latest';

/// 本应用公开仓库主页（设置 → 关于 → Hermes UI 点击后外部浏览器打开）。
const String kHermesUiRepoUrl = 'https://github.com/silent-reader-cn/hermes-keep';

/// 默认版本解析器：从 `package_info_plus` 读取**真实安装版本**。
///
/// 返回 `<version>+<buildNumber>`（如 `0.1.50+56`），与设置页展示的版本同源。
/// 任何异常（平台通道缺失、单测环境等）都退回 [appVersion] 兜底常量——
/// 更新检查是增强功能，绝不能因版本解析失败而崩。
Future<String> platformAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    if (version.isEmpty) return appVersion;
    final build = info.buildNumber.trim();
    return build.isEmpty ? version : '$version+$build';
  } catch (_) {
    return appVersion;
  }
}

/// 更新检测结果状态。
enum UpdateCheckStatus {
  /// 发现新版本。
  hasUpdate,

  /// 已是最新版本。
  upToDate,

  /// 频控跳过（24h 内已检测过）。
  skippedThrottled,

  /// 开关关闭跳过。
  skippedDisabled,

  /// 静默检查失败（限流/断网等完全静默）。
  failedSilent,

  /// 手动检查失败。
  failed,
}

/// 更新检测结果对象。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.latestVersion,
    this.release,
    this.error,
  });

  /// 检测状态。
  final UpdateCheckStatus status;

  /// 当前应用版本。
  final String currentVersion;

  /// 检测到的远端最新版本号。
  final String? latestVersion;

  /// 远端 Release 对象。
  final GithubRelease? release;

  /// 异常信息。
  final Object? error;

  /// 是否存在新版本。
  bool get hasUpdate => status == UpdateCheckStatus.hasUpdate;

  factory UpdateCheckResult.updateAvailable({
    required String currentVersion,
    required GithubRelease release,
  }) =>
      UpdateCheckResult(
        status: UpdateCheckStatus.hasUpdate,
        currentVersion: currentVersion,
        latestVersion: release.tagName,
        release: release,
      );

  factory UpdateCheckResult.upToDate({
    required String currentVersion,
    GithubRelease? release,
  }) =>
      UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        currentVersion: currentVersion,
        latestVersion: release?.tagName,
        release: release,
      );

  factory UpdateCheckResult.skippedThrottled({
    required String currentVersion,
  }) =>
      UpdateCheckResult(
        status: UpdateCheckStatus.skippedThrottled,
        currentVersion: currentVersion,
      );

  factory UpdateCheckResult.skippedDisabled({
    required String currentVersion,
  }) =>
      UpdateCheckResult(
        status: UpdateCheckStatus.skippedDisabled,
        currentVersion: currentVersion,
      );

  factory UpdateCheckResult.failed({
    required String currentVersion,
    required Object error,
    required bool isSilent,
  }) =>
      UpdateCheckResult(
        status: isSilent
            ? UpdateCheckStatus.failedSilent
            : UpdateCheckStatus.failed,
        currentVersion: currentVersion,
        error: error,
      );
}

/// GitHub Releases 更新检测服务。
class UpdateCheckerService {
  UpdateCheckerService({
    Dio? dio,
    String? currentVersion,
    Future<String> Function()? currentVersionResolver,
    Future<SharedPreferences> Function()? prefsResolver,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: const {
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': 'hermes-ui',
                },
              ),
            ),
        _injectedCurrentVersion = currentVersion,
        _currentVersionResolver = currentVersionResolver ?? platformAppVersion,
        _prefsResolver = prefsResolver ?? SharedPreferences.getInstance;

  final Dio _dio;

  /// 显式注入的当前版本（测试用）；null = 运行时从系统解析真实版本。
  final String? _injectedCurrentVersion;

  /// 运行时版本解析器（默认 [platformAppVersion]）。
  final Future<String> Function() _currentVersionResolver;

  final Future<SharedPreferences> Function() _prefsResolver;

  /// 已解析并缓存的真实版本（单实例内不变，避免每次检查都过一遍平台通道）。
  String? _resolvedCurrentVersion;

  /// 当前安装版本：注入值优先 → 已解析缓存 → 兜底常量。
  ///
  /// 注意：**不要**把它当成可靠值去与远端比对，比对请走
  /// [checkForUpdates]（内部用 [_resolveCurrentVersion] 拿真实版本）。
  String get currentVersion =>
      _injectedCurrentVersion ?? _resolvedCurrentVersion ?? appVersion;

  /// 解析当前安装版本（真实版本优先，异常退回 [appVersion]）。
  Future<String> _resolveCurrentVersion() async {
    final injected = _injectedCurrentVersion;
    if (injected != null && injected.isNotEmpty) return injected;

    final cached = _resolvedCurrentVersion;
    if (cached != null) return cached;

    String resolved;
    try {
      resolved = await _currentVersionResolver();
    } catch (_) {
      resolved = appVersion;
    }
    if (resolved.trim().isEmpty) resolved = appVersion;
    _resolvedCurrentVersion = resolved;
    return resolved;
  }

  /// 获取自动更新检查开关状态（默认 true）。
  Future<bool> isAutoCheckEnabled() async {
    try {
      final prefs = await _prefsResolver();
      return prefs.getBool(kAutoCheckUpdateEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 设置自动更新检查开关状态。
  Future<void> setAutoCheckEnabled(bool enabled) async {
    try {
      final prefs = await _prefsResolver();
      await prefs.setBool(kAutoCheckUpdateEnabledKey, enabled);
    } catch (_) {}
  }

  /// 获取上次检查更新时间。
  Future<DateTime?> getLastCheckTime() async {
    try {
      final prefs = await _prefsResolver();
      final str = prefs.getString(kLastUpdateCheckAtKey);
      if (str != null && str.isNotEmpty) {
        return DateTime.tryParse(str);
      }
    } catch (_) {}
    return null;
  }

  /// 记录本次检查时间。
  Future<void> _recordCheckTime(DateTime time) async {
    try {
      final prefs = await _prefsResolver();
      await prefs.setString(kLastUpdateCheckAtKey, time.toIso8601String());
    } catch (_) {}
  }

  /// 执行检查更新。
  ///
  /// - [isManual]: 是否为手动检查。若是手动检查，忽略 24h 频控与自动更新开关；
  /// - [now]: 当前时间注入（测试用）。
  Future<UpdateCheckResult> checkForUpdates({
    bool isManual = false,
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();

    if (!isManual) {
      final enabled = await isAutoCheckEnabled();
      if (!enabled) {
        return UpdateCheckResult.skippedDisabled(
          currentVersion: currentVersion,
        );
      }

      final lastCheck = await getLastCheckTime();
      if (lastCheck != null) {
        final diff = currentTime.difference(lastCheck);
        if (diff < const Duration(hours: 24)) {
          return UpdateCheckResult.skippedThrottled(
            currentVersion: currentVersion,
          );
        }
      }
    }

    try {
      final response = await _dio.get<dynamic>(
        kGithubReleasesLatestUrl,
        options: Options(
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'hermes-ui',
          },
        ),
      );

      await _recordCheckTime(currentTime);

      final dynamic data = response.data;
      final Map<String, dynamic> json;
      if (data is Map<String, dynamic>) {
        json = data;
      } else if (data is Map) {
        json = data.cast<String, dynamic>();
      } else {
        throw FormatException('Unexpected response format: ${data.runtimeType}');
      }

      final release = GithubRelease.fromJson(json);
      // 真实安装版本（#122）：只在**确实要比对**时才解析，早退/失败分支不触碰
      // 平台通道（既省一次通道往返，也避免多余异步步进影响测试时序）。
      final currentAppVersion = await _resolveCurrentVersion();
      final hasNewer = newer(release.tagName, currentAppVersion);

      if (hasNewer) {
        return UpdateCheckResult.updateAvailable(
          currentVersion: currentAppVersion,
          release: release,
        );
      } else {
        return UpdateCheckResult.upToDate(
          currentVersion: currentAppVersion,
          release: release,
        );
      }
    } catch (error) {
      await _recordCheckTime(currentTime);

      if (!isManual) {
        debugPrint('Silent update check failed: $error');
        return UpdateCheckResult.failed(
          currentVersion: currentVersion,
          error: error,
          isSilent: true,
        );
      } else {
        return UpdateCheckResult.failed(
          currentVersion: currentVersion,
          error: error,
          isSilent: false,
        );
      }
    }
  }
}
