import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/locale/locale_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../diagnostics/diagnostics_models.dart';
import '../diagnostics/diagnostics_service.dart';

/// 原生 Live Updates 通道名（与 MainActivity.kt LIVE_UPDATE_CHANNEL 对齐）。
const MethodChannel kLiveUpdateChannel =
    MethodChannel('com.silentreader.hermes_ui/live_update');

/// #105 安卓 16 Live Updates（Promoted Ongoing 实况通知/状态栏 chip/
/// HyperOS 3.1 超级岛）服务——经原生 MethodChannel 驱动（flutter_local_notifications
/// v22.3 不支持 Promoted Ongoing/ProgressStyle，上游 issue #2773 open）。
///
/// 行为契约：
/// - 仅 Android 生效；任何异常静默吞掉（实况通知是增强功能，绝不影响主流程）；
/// - [sync] 为活跃回合数变化的幂等入口：与上次展示的 (title,text) 相同则跳过
///   notify（参考保活常驻通知 `_lastOngoingText` 的做法，避免 SSE 高频抖动 notify 风暴）；
/// - 低版本安卓 `isSupported()==false` 时不发通知（不产生与保活常驻通知重复的
///   普通 ongoing 通知，自动降级无感）；
/// - 设置开关 `bg_live_update_enabled`（默认 true，关=回退现状）。
class LiveUpdateService {
  LiveUpdateService({
    MethodChannel? channel,
    bool? androidPlatformOverride,
  }) : _channel = channel ?? kLiveUpdateChannel,
       // ignore: prefer_initializing_formals
       _androidPlatformOverride = androidPlatformOverride;

  /// 单例实例访问（对齐 BackgroundKeepaliveService.instance 风格；测试可替换）。
  static LiveUpdateService instance = LiveUpdateService();

  /// 实况通知固定 ID（同一条常驻刷新，不与回合通知 1001/1101/1201 冲突）。
  static const int kLiveUpdateNotificationId = 1501;

  /// 原生通知渠道 ID（importance=LOW、无角标，见 MainActivity.kt）。
  static const String kLiveUpdateChannelId = 'live';

  /// 设置开关 prefs key（默认开启：渐进增强、低版本自动无感）。
  static const String prefsKeyLiveUpdateEnabled = 'bg_live_update_enabled';

  final MethodChannel _channel;

  /// Android 平台判定覆盖（测试注入用；null = 真实 defaultTargetPlatform）。
  final bool? _androidPlatformOverride;

  /// 上次成功展示的 (title,text) 幂等缓存；null = 当前无展示中的实况通知。
  (String, String)? _lastShown;

  bool get _isAndroid =>
      _androidPlatformOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// 当前设备是否支持 Promoted Ongoing（安卓 16+ 且用户允许实况通知）。
  ///
  /// 不缓存：用户可能在系统设置中随时开/关实况通知资格，且本方法仅在
  /// sync 文案变化时被动调用（非 token 级高频），单次 channel 往返可忽略。
  Future<bool> isSupported() async {
    if (!_isAndroid) return false;
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } on Object catch (e) {
      developer.log('LiveUpdateService.isSupported 失败: $e',
          name: 'live_update');
      return false;
    }
  }

  /// 幂等同步实况通知：[activeCount]<=0 → cancel；>0 → 组装本地化文案后 show。
  ///
  /// 文案与语言经 [AppLocalizations]（服务层无 BuildContext，取
  /// LocaleResolver.resolve()，对齐 turn_notification_service 风格）。
  Future<void> sync({
    required int activeCount,
    List<String> titles = const [],
  }) async {
    if (!_isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(prefsKeyLiveUpdateEnabled) ?? true;
      if (!enabled) return;
      if (activeCount <= 0) {
        await cancelAll();
        return;
      }
      final l10n = AppLocalizations(LocaleResolver.resolve());
      final title = activeCount > 1
          ? l10n.liveUpdateTitleMulti(activeCount)
          : l10n.liveUpdateTitle;
      final firstTitle = titles.firstWhere(
        (t) => t.trim().isNotEmpty,
        orElse: () => '',
      );
      final text = firstTitle.trim().isNotEmpty
          ? firstTitle.trim()
          : l10n.liveUpdateDefaultText;
      // 幂等：文案未变则不重复 notify（防 SSE/列表刷新抖动风暴），且先于
      // isSupported 通道往返——同文案高频同步须零平台通道调用。
      if (_lastShown == (title, text)) return;
      if (!await isSupported()) return;
      final shown = await _channel.invokeMethod<bool>('show', {
        'id': kLiveUpdateNotificationId,
        'channelId': kLiveUpdateChannelId,
        'title': title,
        'text': text,
        // 状态栏 chip 短文案（≤6 字符硬约束，Kotlin 侧再兜底截断）。
        'shortCriticalText': l10n.liveUpdateChip,
        // 回合无确定进度 → 不定量动画（Kotlin 侧勿伪造百分比）。
        'indeterminate': true,
      });
      if (shown == true) {
        _lastShown = (title, text);
      }
    } on Object catch (e, st) {
      developer.log(
        'LiveUpdateService.sync 失败: $e',
        name: 'live_update',
        error: e,
        stackTrace: st,
      );
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'live_update',
        message: '实况通知同步失败（已静默降级）',
        errorKind: e.toString(),
      );
    }
  }

  /// 撤销实况通知并清空幂等缓存（回合结束 / 开关关闭 / 完成态通知兜底）。
  ///
  /// 与 sync(0) 的自动 cancel 等效，供外部链路显式兜底调用。**不依赖内存缓存
  /// 门控**：实况通知由系统托管、可跨进程存活（app 被杀后仍在），冷启动后
  /// 首次 sync(0) 必须无条件原生 cancel 一次以清除残留；原生 cancel 对不存在的
  /// 通知是无操作，且 sync 调用本身按会话集合变化边沿触发，无 notify 风暴风险。
  Future<void> cancelAll() async {
    if (!_isAndroid) return;
    _lastShown = null;
    try {
      await _channel.invokeMethod<void>('cancel', {
        'id': kLiveUpdateNotificationId,
      });
    } on Object catch (e) {
      developer.log('LiveUpdateService.cancelAll 失败: $e',
          name: 'live_update');
    }
  }
}
