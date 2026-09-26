import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/locale/locale_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../diagnostics/diagnostics_models.dart';
import '../diagnostics/diagnostics_service.dart';

/// 原生 Live Updates 通道名（与 MainActivity.kt LIVE_UPDATE_CHANNEL 对齐）。
const MethodChannel kLiveUpdateChannel = MethodChannel(
  'com.silentreader.hermes_ui/live_update',
);

/// 实况通知「当前动作」（#120）：面向状态栏/岛的一句话活动文案。
///
/// 与 `ChatPhase` 的九态不同，这里是**通知可读性导向**的粗粒度动作：推理／
/// 工具／输出／等待回复／等待批准／已完成／已中断。
///
/// #129 起补齐 #48 定稿五态的「已完成 / 已中断」：收尾不再一律撤岛，
/// 由 chat 侧上报完成态、岛上停留 15s 后再报 `activity: null` 撤销；
/// `notifyActivity(activity: null)` 仍是唯一的「撤销」表达。
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

  /// 回合已完成（#129）：正常收尾（done / stream_end），
  /// 在岛上停留一段（chat 侧 15s）后自动撤销。
  completed,

  /// 回合已中断（#129）：cancel / error 收尾。
  interrupted,
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
    DateTime Function()? now,
    Duration? downloadCompletedDwell,
  }) : _channel = channel ?? kLiveUpdateChannel,
       // ignore: prefer_initializing_formals
       _androidPlatformOverride = androidPlatformOverride,
       _now = now ?? DateTime.now,
       _downloadCompletedDwell =
           downloadCompletedDwell ?? kDownloadCompletedDwell;

  /// 单例实例访问（对齐 BackgroundKeepaliveService.instance 风格；测试可替换）。
  static LiveUpdateService instance = LiveUpdateService();

  /// 实况通知固定 ID（同一条常驻刷新，不与回合通知 1001/1101/1201 冲突）。
  static const int kLiveUpdateNotificationId = 1501;

  /// 原生通知渠道 ID（importance=LOW、无角标，见 MainActivity.kt）。
  static const String kLiveUpdateChannelId = 'live';

  /// #114-P1 工具调用落点上限（clamp 防溢出）。
  ///
  /// B 案（2026-09-19）起 Dart 侧不再上报落点（小米超级岛不渲染 points、且点数
  /// 会改变系统 progressMax 使条跳变），Kotlin 侧参数与 clamp 保留以支持回退。
  static const int kMaxProgressPoints = 20;

  /// 设置开关 prefs key（默认开启：渐进增强、低版本自动无感）。
  static const String prefsKeyLiveUpdateEnabled = 'bg_live_update_enabled';

  /// #158 下载完成态在岛上的停留时长。
  ///
  /// 对齐 chat 侧回合完成态的 [ChatController.liveActivityDwell]（主人拍板 15s）：
  /// 完成是离散事件，无停留则岛会「闪一下就没」，用户来不及看见。
  static const Duration kDownloadCompletedDwell = Duration(seconds: 15);

  final MethodChannel _channel;

  /// Android 平台判定覆盖（测试注入用；null = 真实 defaultTargetPlatform）。
  final bool? _androidPlatformOverride;

  /// 当前时间获取器（测试注入用，禁 Timer 铁律下做确定性节流单测）。
  final DateTime Function() _now;

  /// 上次成功展示的 (title, text, chip, trackerIcon, subText, indeterminate, progressPercent) 幂等缓存；null = 当前无展示中的实况通知。
  ///
  /// B 案（2026-09-19）：出参第 5 位由工具落点数换成 subText —— 进度条上的落点
  /// 蓝点在小米超级岛上根本不渲染（真机取证），且点数会改变系统的 progressMax
  /// 使条本身跳变，故整套停用，位置让给真正有信息量的次级文案。
  (String, String, String, String, String?, bool, int)? _lastShown;

  /// #114-P1 动态 tracker 图标键（thinking / tool / output / waiting_reply / waiting_approval）。
  String _trackerIconKey = 'thinking';

  /// chat 侧上报的**当前活动会话标题**（B 案接线：最大字号位承载会话身份）。
  ///
  /// 此前该参数一路传到服务层却在 [_compose] 里被丢弃，导致展开态最大字号长期
  /// 显示恒定文案「Hermes · 回合进行中」，用户最需要的「哪个会话在跑」完全缺席
  /// （真机取证 2026-09-19）。回合收尾时清空。
  String? _activityTitle;

  /// 当前活动种类（#123 用于区分等待态与普通回合活动，支持高优先级抢占与自然回落）。
  LiveUpdateActivity? _activity;

  /// 来源一：会话列表活跃会话数（多会话总览兜底）。
  int _listActiveCount = 0;

  /// 来源一：首个非空会话标题（无实时活动时的身份来源）。
  String? _listTitle;

  /// 来源一：活跃会话标题明细（用于精确统计「另有 N 个会话」）。
  List<String> _listTitles = const [];

  /// 来源二：回合实时活动正文（null = 当前无实时活动）。
  String? _activityText;

  /// 来源二：回合实时活动对应的状态栏 chip 短文案。
  String? _activityChip;

  /// 来源三：下载状态字段（#123）。
  String? _downloadFileName;
  int _downloadReceived = 0;
  int _downloadExpected = 0;
  int _downloadQueuedCount = 0;
  int _downloadPercent = 0;

  @visibleForTesting
  int get downloadReceived => _downloadReceived;

  /// 下载通知节流：上次实际推送时间与百分比（防 notify 风暴，首次调用不受限）。
  DateTime? _lastDownloadNotifyTime;
  int? _lastDownloadNotifiedPercent;

  /// #158 下载完成态：文件名 + 展示起点。
  ///
  /// 与「进行中」字段分开存放，使 `clearDownloadProgress()`（下载完成/失败/取消
  /// 都会调）清场时**不会误伤**刚上岛的完成态 —— 此前完成态根本没有表达，
  /// 下载一结束岛就被撤销（主人报「下载完成没有灵动岛提示」）。
  String? _downloadCompletedFileName;
  DateTime? _downloadCompletedAt;

  /// 完成态到期撤岛的定时器（新完成事件重置；`cancelAll` 一并取消）。
  Timer? _downloadCompletedDismissTimer;

  /// 完成态停留时长（测试可注入缩短，避免真等 15s）。
  final Duration _downloadCompletedDwell;

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
      developer.log(
        'LiveUpdateService.isSupported 失败: $e',
        name: 'live_update',
      );
      return false;
    }
  }

  /// 岛正文工具名转译（与工具卡聚合同源，见 tool_call.dart:251）。
  static String _localizedToolName(AppLocalizations l10n, String raw) {
    final name = raw.trim();
    if (name.isEmpty) return '';
    // 与工具卡 MCP 归并口径一致（聚合层统一「外部工具」）。
    if (name.startsWith('mcp__')) return l10n.externalToolsLabel;
    return l10n.localizeToolName(name);
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
      // 收尾：清活动态并刷新（等待态撤销后回落下载/列表链路，全空时 _flush 内调 cancelAll）。
      _activity = null;
      _activityText = null;
      _activityChip = null;
      _activityTitle = null;
      _trackerIconKey = 'thinking';
      await _flush();
      return;
    }
    _activity = activity;
    // B 案：记录活动会话标题，供 [_compose] 作为最大字号位的主文案。
    final trimmedTitle = title.trim();
    _activityTitle = trimmedTitle.isEmpty ? null : trimmedTitle;
    final l10n = AppLocalizations(LocaleResolver.resolve());
    _activityText = switch (activity) {
      LiveUpdateActivity.thinking => l10n.liveUpdateActivityThinking,
      LiveUpdateActivity.tool => l10n.liveUpdateActivityTool(
        _localizedToolName(l10n, detail),
      ),
      LiveUpdateActivity.output => l10n.liveUpdateActivityOutput,
      LiveUpdateActivity.waitingReply => l10n.liveUpdateActivityWaitingReply,
      LiveUpdateActivity.waitingApproval =>
        l10n.liveUpdateActivityWaitingApproval,
      LiveUpdateActivity.completed => l10n.liveUpdateActivityCompleted,
      LiveUpdateActivity.interrupted => l10n.liveUpdateActivityInterrupted,
    };
    _activityChip = switch (activity) {
      LiveUpdateActivity.waitingReply => l10n.liveUpdateChipReply,
      LiveUpdateActivity.waitingApproval => l10n.liveUpdateChipApproval,
      // #129 #48 定稿五态：已完成 / 已中断（英文 ≤6 字符）。
      LiveUpdateActivity.completed => l10n.liveUpdateChipDone,
      LiveUpdateActivity.interrupted => l10n.liveUpdateChipStopped,
      _ => l10n.liveUpdateChip,
    };
    _trackerIconKey = switch (activity) {
      LiveUpdateActivity.thinking => 'thinking',
      LiveUpdateActivity.tool => 'tool',
      LiveUpdateActivity.output => 'output',
      LiveUpdateActivity.waitingReply => 'waiting_reply',
      LiveUpdateActivity.waitingApproval => 'waiting_approval',
      LiveUpdateActivity.completed => 'completed',
      LiveUpdateActivity.interrupted => 'interrupted',
    };
    await _flush();
  }

  /// 下载进度上报（#123）：有真实进度时以确定进度条（determinate）展示。
  ///
  /// 返回 true 表示本次由实况通知（岛）承载，调用方据此抑制 1401 常规通知。
  Future<bool> notifyDownloadProgress({
    required String fileName,
    required int receivedBytes,
    required int expectedBytes,
    int queuedCount = 0,
  }) async {
    if (!_isAndroid) return false;
    if (!await isSupported()) return false;

    final percent = expectedBytes > 0
        ? (receivedBytes * 100 ~/ expectedBytes).clamp(0, 100)
        : 0;

    _downloadFileName = fileName;
    _downloadReceived = receivedBytes;
    _downloadExpected = expectedBytes;
    _downloadQueuedCount = queuedCount;
    _downloadPercent = percent;

    final lastTime = _lastDownloadNotifyTime;
    final lastPercent = _lastDownloadNotifiedPercent;
    final now = _now();

    if (lastTime != null && lastPercent != null) {
      final elapsedMs = now.difference(lastTime).inMilliseconds;
      final percentDiff = (percent - lastPercent).abs();
      if (elapsedMs < 500 && percentDiff < 1) {
        return true;
      }
    }

    _lastDownloadNotifyTime = now;
    _lastDownloadNotifiedPercent = percent;
    await _flush();
    return true;
  }

  /// 清除下载**进行中**进度态并刷新实况通知（自然回落回合活动 / 撤销 / 列表总览）。
  ///
  /// 只清进行中字段：完成态（#158）由 [notifyDownloadCompleted] 自己按停留窗口
  /// 到期撤销，否则「完成 → clearDownloadProgress」这条既有调用序会把刚上岛的
  /// 完成提示立刻抹掉（下载链路两条路径都在完成通知后紧跟本方法）。
  Future<void> clearDownloadProgress() async {
    if (!_isAndroid) return;
    _downloadFileName = null;
    _downloadReceived = 0;
    _downloadExpected = 0;
    _downloadQueuedCount = 0;
    _downloadPercent = 0;
    _lastDownloadNotifyTime = null;
    _lastDownloadNotifiedPercent = null;
    await _flush();
  }

  /// 下载完成态上岛（#158）：正文「{文件名} 下载完成」+ chip「已完成」+ 确定进度条
  /// 100%（与回合完成态同款满载表达），停留 [kDownloadCompletedDwell] 后自动撤岛。
  ///
  /// 优先级见 [_compose]：等待态 > 下载完成（窗口内） > 下载进行中 > 回合活动 >
  /// 列表总览。完成态与进行态可同时存在（队列里还有任务在跑）——窗口内让位给
  /// 「完成了什么」，窗口过后自然回落到下一个任务的进度条。
  ///
  /// LIVE 是增强功能：非 Android / 低版本由 [_flush] 内部静默降级，调用方无感。
  Future<void> notifyDownloadCompleted({required String fileName}) async {
    if (!_isAndroid) return;
    final name = fileName.trim();
    if (name.isEmpty) return;
    _downloadCompletedFileName = name;
    _downloadCompletedAt = _now();
    _scheduleDownloadCompletedDismiss();
    await _flush();
  }

  /// #158 完成态到期撤岛：清字段并刷新（无其他活动时由 [_flush] 落到 cancelAll）。
  void _scheduleDownloadCompletedDismiss() {
    _downloadCompletedDismissTimer?.cancel();
    _downloadCompletedDismissTimer = Timer(_downloadCompletedDwell, () {
      _downloadCompletedDismissTimer = null;
      if (_downloadCompletedAt == null) return;
      _clearDownloadCompleted();
      unawaited(_flush());
    });
  }

  /// 清理完成态字段与定时器（到期 / 撤回 / 撤销时调用）。
  void _clearDownloadCompleted() {
    _downloadCompletedDismissTimer?.cancel();
    _downloadCompletedDismissTimer = null;
    _downloadCompletedFileName = null;
    _downloadCompletedAt = null;
  }

  /// 惰性过期：进程被冻结 / 定时器未按时触发时，下次刷新照样能把过期完成态清掉，
  /// 避免岛永久停在「已完成」。
  void _expireDownloadCompletedIfStale() {
    final startedAt = _downloadCompletedAt;
    if (startedAt == null) return;
    if (_now().difference(startedAt) < _downloadCompletedDwell) return;
    _clearDownloadCompleted();
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
    _listTitles = List<String>.unmodifiable(titles);
    _listTitle = titles.firstWhere(
      (t) => t.trim().isNotEmpty,
      orElse: () => '',
    );
    await _flush();
  }

  /// 当前应作为最大字号主文案的**会话身份**（B 案）：活动会话标题优先，其次
  /// 列表链路首个会话标题；都没有返回空串（调用方回退通用文案）。
  String _sessionIdentity() {
    final activity = (_activityTitle ?? '').trim();
    if (activity.isNotEmpty) return activity;
    return (_listTitle ?? '').trim();
  }

  /// 次级信息（subText）：「另有 N 个会话」。
  ///
  /// 精准口径：只统计**与当前身份不同**的活跃会话标题（列表链路逐条上报），故
  /// 不会把当前会话自己算成「另有」；标题明细缺失时退回「活跃数 - 1」近似。
  /// 无多会话时返回 null（不占 subText 槽）。
  String? _otherSessionsSubText(
    AppLocalizations l10n,
    String identity,
    int count,
  ) {
    // 身份缺失时 title 已回落「· N 个会话」通用文案，再报一次「另有」即同一句
    // 话占两处 —— 故此时不占 subText 槽。
    if (identity.trim().isEmpty) return null;
    final resolved = _listTitles.isEmpty
        ? (count > 1 ? count - 1 : 0)
        : _listTitles
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty && t != identity)
              .toSet()
              .length;
    if (resolved <= 0) return null;
    return l10n.liveUpdateSubTextExtraSessions(resolved);
  }

  /// 合成当前应展示的 (title, text, chip, trackerIcon, subText, indeterminate, progressPercent)；null = 应撤销。
  ///
  /// 优先级：等待态（抢占一切） > 下载完成（#158，停留窗口内） > 下载进行中 >
  /// 回合其他活动 > 列表总览 > 撤销。
  /// **B 案「身份优先」（2026-09-19，主人拍板）**：最大字号位（title）恒定承载
  /// 会话身份 —— 有实时活动用活动会话标题，否则回落列表链路首个会话标题，都没有
  /// 才退回通用文案。真机取证显示小米超级岛会自行在头部显示 App 名与计时器，故
  /// subText 只放系统不会替我们说的话（「另有 N 个会话」），不放 App 名 —— 否则
  /// 一屏会出现两遍「Hermes」。
  (String, String, String, String, String?, bool, int)? _compose() {
    final l10n = AppLocalizations(LocaleResolver.resolve());
    final count = _listActiveCount;
    final identity = _sessionIdentity();
    final title = identity.isNotEmpty
        ? identity
        : (count > 1 ? l10n.liveUpdateTitleMulti(count) : l10n.liveUpdateTitle);
    final subText = _otherSessionsSubText(l10n, identity, count);

    // 1. 等待态（waitingReply / waitingApproval）：需主人行动，抢占一切。
    final isWaiting =
        _activity == LiveUpdateActivity.waitingReply ||
        _activity == LiveUpdateActivity.waitingApproval;
    final activityText = _activityText;
    if (isWaiting && activityText != null && activityText.trim().isNotEmpty) {
      return (
        title,
        activityText,
        _activityChip ?? l10n.liveUpdateChip,
        _trackerIconKey,
        subText,
        true,
        0,
      );
    }

    // 2. 下载完成态（#158，窗口内）：比进行中进度优先 —— 完成是离散事件，
    //    队列连续下载时若被下一个任务的进度条压住，用户就看不到「刚下完了什么」。
    final downloadCompletedName = _downloadCompletedFileName;
    if (downloadCompletedName != null &&
        downloadCompletedName.trim().isNotEmpty) {
      return (
        title,
        l10n.liveUpdateActivityDownloadCompleted(downloadCompletedName),
        // chip 复用 #48 定稿五态的「已完成」（≤6 字符，英文 Done）。
        l10n.liveUpdateChipDone,
        'completed',
        subText,
        false,
        100,
      );
    }

    // 3. 下载进行中（#123）。
    final downloadFileName = _downloadFileName;
    if (downloadFileName != null && downloadFileName.trim().isNotEmpty) {
      final hasTotal = _downloadExpected > 0;
      final baseText = hasTotal
          ? l10n.liveUpdateActivityDownload(downloadFileName, _downloadPercent)
          : l10n.liveUpdateActivityDownloadUnknownSize(downloadFileName);
      final queueSuffix = _downloadQueuedCount > 0
          ? l10n.liveUpdateDownloadQueuedSuffix(_downloadQueuedCount)
          : '';
      final text = '$baseText$queueSuffix';
      return (
        title,
        text,
        l10n.liveUpdateDownloadChip,
        'download',
        subText,
        !hasTotal,
        hasTotal ? _downloadPercent : 0,
      );
    }

    // 4. 回合其他活动（thinking / tool / output / completed / interrupted）。
    if (activityText != null && activityText.trim().isNotEmpty) {
      // #129：已完成态用**确定进度条 100%**（满载=完成、停止动画）；
      // 其余活动保持 indeterminate —— B 案起条只表达「在跑」，不再叠工具落点。
      final isCompleted = _activity == LiveUpdateActivity.completed;
      return (
        title,
        activityText,
        _activityChip ?? l10n.liveUpdateChip,
        _trackerIconKey,
        subText,
        !isCompleted,
        isCompleted ? 100 : 0,
      );
    }

    // 5. 会话列表总览。
    if (count > 0) {
      return (
        title,
        l10n.liveUpdateDefaultText,
        l10n.liveUpdateChip,
        _trackerIconKey,
        subText,
        true,
        0,
      );
    }

    // 6. 撤销。
    return null;
  }

  /// 单一出口：读开关 → 合成 → 幂等比较 → 资格判定 → show / cancel。
  Future<void> _flush() async {
    if (!_isAndroid) return;
    // #158 完成态窗口过期先清场，使「已完成 → 回落进行中进度 / 列表总览 / 撤销」
    // 在任意刷新入口下都成立（定时器与惰性过期双保险）。
    _expireDownloadCompletedIfStale();
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(prefsKeyLiveUpdateEnabled) ?? true;
      if (!enabled) return;
      final composed = _compose();
      if (composed == null) {
        await cancelAll();
        return;
      }
      // 幂等：文案/图标/subText/确定性/百分比 7 字段未变则不重复 notify（防 SSE/列表/下载刷新抖动风暴），
      // 且先于 isSupported 通道往返——同文案/百分比高频同步须零平台通道调用。
      if (_lastShown == composed) return;
      if (!await isSupported()) return;
      final (
        title,
        text,
        chip,
        trackerIcon,
        subText,
        indeterminate,
        progressPercent,
      ) = composed;
      final shown = await _channel.invokeMethod<bool>('show', {
        'id': kLiveUpdateNotificationId,
        'channelId': kLiveUpdateChannelId,
        'title': title,
        'text': text,
        // 状态栏 chip 短文案（≤6 字符硬约束，Kotlin 侧再兜底截断）。
        'shortCriticalText': chip,
        // B 案次级信息（可空：多会话时为「另有 N 个会话」）。
        'subText': subText,
        'indeterminate': indeterminate,
        'trackerIcon': trackerIcon,
        'progressPercent': progressPercent,
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
    _activity = null;
    _activityText = null;
    _activityChip = null;
    _activityTitle = null;
    _trackerIconKey = 'thinking';
    // #158：完成态与到期定时器一并清（避免撤岛后残留窗口把岛又拉起来）。
    _clearDownloadCompleted();
    try {
      await _channel.invokeMethod<void>('cancel', {
        'id': kLiveUpdateNotificationId,
      });
    } on Object catch (e) {
      developer.log('LiveUpdateService.cancelAll 失败: $e', name: 'live_update');
    }
  }
}
