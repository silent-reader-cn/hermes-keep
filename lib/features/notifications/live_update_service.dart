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

/// 实况通知「当前动作」（#120）：面向状态栏/岛的一句话活动文案。
///
/// 与 `ChatPhase` 的九态不同，这里是**通知可读性导向**的粗粒度动作：推理／
/// 工具／输出／等待回复／等待批准。收尾态不在此枚举内——服务层用
/// `notifyActivity(activity: null)` 表达「撤销」。
enum LiveUpdateActivity {
  /// 推理中。
  thinking,

  /// 工具调用中（[LiveUpdateService.notifyActivity] 的 detail 带工具名）。
  tool,

  /// 正文输出中。
  output,

  /// 等待主人回复（澄清卡片已弹出）。
  waitingReply,

  /// 等待主人批准（审批卡片已弹出）。
  waitingApproval,
}

/// #105 安卓 16 Live Updates（Promoted Ongoing 实况通知/状态栏 chip/
/// HyperOS 3.1 超级岛）服务——经原生 MethodChannel 驱动（flutter_local_notifications
/// v22.3 不支持 Promoted Ongoing/ProgressStyle，上游 issue #2773 open）。
///
/// 行为契约：
/// - 仅 Android 生效；任何异常静默吞掉（实况通知是增强功能，绝不影响主流程）；
/// - 两个上报来源，合成**单条**通知（[LiveUpdateService.notifyActivity] /
///   [LiveUpdateService.sync]），唯一出口 [_flush]：
///   1. **回合实时活动**（#120，优先）：活动或相位变化即刻刷新正文与 chip，
///      解决「后台/阶段变化不刷新」与「退后台延迟上岛」；
///   2. **会话列表总览**（既有，保留为兜底）：活跃会话集合变化时上报计数与
///      首个会话标题。
/// - #114-P1 ProgressStyle 增强：tracker icon 随状态动态换；点数是「已发生的
///   工具调用落点」，非完成度，进度条仍保持 indeterminate。
/// - 幂等：与上次展示的 (title, text, chip, trackerIcon, progressPoints) 相同则跳过 notify
///   （防 SSE 高频抖动 notify 风暴）；文案相同的高频上报须零平台通道调用；
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

  /// #114-P1 工具调用落点上限（clamp 防溢出）。
  static const int kMaxProgressPoints = 20;

  /// 设置开关 prefs key（默认开启：渐进增强、低版本自动无感）。
  static const String prefsKeyLiveUpdateEnabled = 'bg_live_update_enabled';

  final MethodChannel _channel;

  /// Android 平台判定覆盖（测试注入用；null = 真实 defaultTargetPlatform）。
  final bool? _androidPlatformOverride;

  /// 上次成功展示的 (title, text, chip, trackerIcon, progressPoints) 幂等缓存；null = 当前无展示中的实况通知。
  (String, String, String, String, int)? _lastShown;

  /// #114-P1 动态 tracker 图标键（thinking / tool / output / waiting_reply / waiting_approval）。
  String _trackerIconKey = 'thinking';

  /// #114-P1 当前回合工具调用累计落点数（非完成度，回合收尾归零）。
  int _progressPoints = 0;

  /// 来源一：会话列表活跃会话数（多会话总览兜底）。
  int _listActiveCount = 0;

  /// 来源一：首个非空会话标题（列表链路正文）。
  String? _listTitle;

  /// 来源二：回合实时活动正文（null = 当前无实时活动）。
  String? _activityText;

  /// 来源二：回合实时活动对应的状态栏 chip 短文案。
  String? _activityChip;

  bool get _isAndroid =>
      _androidPlatformOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// 当前设备是否支持 Promoted Ongoing（安卓 16+ 且用户允许实况通知）。
  ///
  /// 不缓存：用户可能在系统设置中随时开/关实况通知资格，且本方法仅在
  /// 文案变化时被动调用（非 token 级高频），单次 channel 往返可忽略。
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

  /// 回合实时活动上报（#120）：[activity] 为 null 表示回合收尾（撤销）。
  ///
  /// 文案与语言经 [AppLocalizations]（服务层无 BuildContext，取
  /// LocaleResolver.resolve()，对齐 turn_notification_service 风格）。
  /// [detail] 用于工具名等补充（工具活动为空时退化为通用「正在调用工具…」）。
  Future<void> notifyActivity({
    required String sessionId,
    required String title,
    required LiveUpdateActivity? activity,
    String detail = '',
  }) async {
    if (!_isAndroid) return;
    if (activity == null) {
      // 收尾：清活动态并撤销（多会话时由列表链路的下一次上报重新点亮）。
      _trackerIconKey = 'thinking';
      _progressPoints = 0;
      await cancelAll();
      return;
    }
    final l10n = AppLocalizations(LocaleResolver.resolve());
    _activityText = switch (activity) {
      LiveUpdateActivity.thinking => l10n.liveUpdateActivityThinking,
      LiveUpdateActivity.tool => l10n.liveUpdateActivityTool(detail),
      LiveUpdateActivity.output => l10n.liveUpdateActivityOutput,
      LiveUpdateActivity.waitingReply => l10n.liveUpdateActivityWaitingReply,
      LiveUpdateActivity.waitingApproval =>
        l10n.liveUpdateActivityWaitingApproval,
    };
    _activityChip = switch (activity) {
      LiveUpdateActivity.waitingReply => l10n.liveUpdateChipReply,
      LiveUpdateActivity.waitingApproval => l10n.liveUpdateChipApproval,
      _ => l10n.liveUpdateChip,
    };
    _trackerIconKey = switch (activity) {
      LiveUpdateActivity.thinking => 'thinking',
      LiveUpdateActivity.tool => 'tool',
      LiveUpdateActivity.output => 'output',
      LiveUpdateActivity.waitingReply => 'waiting_reply',
      LiveUpdateActivity.waitingApproval => 'waiting_approval',
    };
    if (activity == LiveUpdateActivity.tool) {
      if (_progressPoints < kMaxProgressPoints) {
        _progressPoints++;
      }
    }
    await _flush();
  }

  /// 会话列表链路上报（既有入口）：活跃会话数 + 标题列表。
  ///
  /// 保留为**多会话总览兜底**；有实时活动时由活动文案优先（见 [_compose]）。
  Future<void> sync({
    required int activeCount,
    List<String> titles = const [],
  }) async {
    if (!_isAndroid) return;
    _listActiveCount = activeCount;
    _listTitle = titles.firstWhere(
      (t) => t.trim().isNotEmpty,
      orElse: () => '',
    );
    await _flush();
  }

  /// 合成当前应展示的 (title, text, chip, trackerIcon, progressPoints)；null = 应撤销。
  ///
  /// 优先级：实时活动 > 列表总览 > 撤销。
  (String, String, String, String, int)? _compose() {
    final l10n = AppLocalizations(LocaleResolver.resolve());
    final count = _listActiveCount;
    final title = count > 1
        ? l10n.liveUpdateTitleMulti(count)
        : l10n.liveUpdateTitle;

    final activityText = _activityText;
    if (activityText != null && activityText.trim().isNotEmpty) {
      return (
        title,
        activityText,
        _activityChip ?? l10n.liveUpdateChip,
        _trackerIconKey,
        _progressPoints,
      );
    }
    if (count > 0) {
      final listTitle = (_listTitle ?? '').trim();
      return (
        title,
        listTitle.isNotEmpty ? listTitle : l10n.liveUpdateDefaultText,
        l10n.liveUpdateChip,
        _trackerIconKey,
        _progressPoints,
      );
    }
    return null;
  }

  /// 单一出口：读开关 → 合成 → 幂等比较 → 资格判定 → show / cancel。
  Future<void> _flush() async {
    if (!_isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(prefsKeyLiveUpdateEnabled) ?? true;
      if (!enabled) return;
      final composed = _compose();
      if (composed == null) {
        await cancelAll();
        return;
      }
      // 幂等：文案/图标/点数 5 字段未变则不重复 notify（防 SSE/列表刷新抖动风暴），且先于
      // isSupported 通道往返——同文案高频同步须零平台通道调用。
      if (_lastShown == composed) return;
      if (!await isSupported()) return;
      final (title, text, chip, trackerIcon, progressPoints) = composed;
      final shown = await _channel.invokeMethod<bool>('show', {
        'id': kLiveUpdateNotificationId,
        'channelId': kLiveUpdateChannelId,
        'title': title,
        'text': text,
        // 状态栏 chip 短文案（≤6 字符硬约束，Kotlin 侧再兜底截断）。
        'shortCriticalText': chip,
        // 回合无确定进度 → 不定量动画（Kotlin 侧勿伪造百分比）。
        'indeterminate': true,
        'trackerIcon': trackerIcon,
        'progressPoints': progressPoints,
      });
      if (shown == true) {
        _lastShown = composed;
      }
    } on Object catch (e, st) {
      developer.log(
        'LiveUpdateService._flush 失败: $e',
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

  /// 撤销实况通知并清空幂等缓存与活动态（回合结束 / 开关关闭 / 完成态兜底）。
  ///
  /// 与 sync(0) 的自动 cancel 等效，供外部链路显式兜底调用。**不依赖内存缓存
  /// 门控**：实况通知由系统托管、可跨进程存活（app 被杀后仍在），冷启动后
  /// 首次 sync(0) 必须无条件原生 cancel 一次以清除残留；原生 cancel 对不存在的
  /// 通知是无操作，且 sync 调用本身按会话集合变化边沿触发，无 notify 风暴风险。
  Future<void> cancelAll() async {
    if (!_isAndroid) return;
    _lastShown = null;
    _activityText = null;
    _activityChip = null;
    _trackerIconKey = 'thinking';
    _progressPoints = 0;
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
