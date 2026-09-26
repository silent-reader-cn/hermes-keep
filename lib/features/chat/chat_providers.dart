import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/connections/connection_providers.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/tool_call.dart';
import '../settings/tool_group_settings.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_server_api.dart';
import 'chat_state.dart';

/// 聊天状态指示行持久化键。
const String kChatStatusLineKey = 'settings.chatStatusLine';

/// 聊天状态指示行偏好设置 Provider（持久化到 shared_preferences，默认开启）。
final chatStatusLineProvider = NotifierProvider<ChatStatusLineController, bool>(
  ChatStatusLineController.new,
);

/// 聊天状态指示行控制器。
class ChatStatusLineController extends Notifier<bool> {
  static const String keyChatStatusLine = kChatStatusLineKey;

  static Future<bool> loadStatusLinePref({
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keyChatStatusLine) ?? true;
    } catch (_) {
      return true;
    }
  }

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    try {
      final value = await loadStatusLinePref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  Future<void> load() => _load();

  Future<void> setEnabled(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyChatStatusLine, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}

/// 持久化 key：审批实时推送。
const String kApprovalStreamEnabledKey = 'approval_stream_enabled';

/// 审批实时推送（SSE）开关 Provider（持久化到 shared_preferences，默认开启 true）。
final approvalStreamEnabledProvider =
    NotifierProvider<ApprovalStreamEnabledController, bool>(
      ApprovalStreamEnabledController.new,
    );

/// 控制审批实时推送开关及本地持久化的 Notifier。
class ApprovalStreamEnabledController extends Notifier<bool> {
  static const String key = kApprovalStreamEnabledKey;

  /// 读取开关偏好的静态辅助方法。
  static Future<bool> loadPref({SharedPreferences? customPrefs}) async {
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
      final value = await loadPref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // 单元测试无 SharedPreferences 时静默忽略
    }
  }

  Future<void> load() => _load();

  Future<void> setEnabled(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // 单元测试环境忽略
    }
  }
}

/// 看门狗阈值配置（chat_spec.md §5.3；测试可 override 缩短阈值）。
class ChatWatchdogConfig {
  const ChatWatchdogConfig({
    this.watchdogInterval = const Duration(seconds: 1),
    this.progressStaleThreshold = const Duration(seconds: 5),
    this.transportStaleThreshold = const Duration(seconds: 12),
    this.forceReconnectThreshold = const Duration(seconds: 18),
    this.forceReconnectWithRunningToolsThreshold = const Duration(seconds: 25),
    this.statusPollCooldown = const Duration(seconds: 4),
    this.heartbeatInterval = const Duration(seconds: 5),
    this.transportFreshThreshold = const Duration(seconds: 10),
    this.reconnectBackoffDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
    this.maxReconnectAttempts = 6,
    this.maxMalformedDoneSettleAttempts = 3,
    this.reconnectJitterMax = const Duration(milliseconds: 1500),
    this.fullReconnectCooldown = const Duration(seconds: 60),
    this.recoverySentinelInterval = const Duration(seconds: 60),
    this.resumeProbeRetries = 2,
    this.resumeProbeRetryDelay = const Duration(seconds: 2),
    this.deadZoneStallThreshold = const Duration(seconds: 15),
    this.deadZoneCooldown = const Duration(seconds: 30),
    this.random,
    this.customJitter,
  });

  /// 前台看门狗心跳间隔。
  final Duration watchdogInterval;

  /// 距上次进度 ≥ 该值（且传输 ≥ [transportStaleThreshold]）→ checking。
  final Duration progressStaleThreshold;

  /// 距上次传输活动 ≥ 该值 → 触发 status 检查。
  final Duration transportStaleThreshold;

  /// 距上次传输活动 ≥ 该值（无运行中工具）或运行中工具无进度 ≥ 该值 → 强制重连 / 探活。
  final Duration forceReconnectThreshold;

  /// 距上次传输活动或运行中工具无进度 ≥ 该值（有运行中工具）→ 强制重连。
  final Duration forceReconnectWithRunningToolsThreshold;

  /// status 轮询冷却。
  final Duration statusPollCooldown;

  /// 服务端心跳间隔（PROTOCOL_NOTES §2，缺省 5s）。
  final Duration heartbeatInterval;

  /// 传输保持活跃（fresh）的判定上限（默认取 [heartbeatInterval] * 2 = 10s）。
  /// 在此窗口内持续收到心跳/帧，表明底层连接健康，工具长时间执行不应被误判为掉线。
  final Duration transportFreshThreshold;

  /// 传输错误重连退避序列（建议 1s, 2s, 4s, 8s, 16s, 30s 封顶）。
  final List<Duration> reconnectBackoffDelays;

  /// 传输错误最大自动重连尝试次数（达到后停止自动重连）。
  final int maxReconnectAttempts;

  /// 收尾帧（done）连续解析失败的最大容忍次数：超过即熔断——按 REST transcript
  /// 收尾 + 显式报错，不再尝试任何恢复（默认 3，测试可 override）。
  final int maxMalformedDoneSettleAttempts;

  /// 强制重连/轮询探活的最大随机错峰延迟（防多会话并发风暴；默认 1500ms，测试可 override 为 Duration.zero）。
  final Duration reconnectJitterMax;

  /// 同会话同 streamId 全量重连（afterSeq=0）冷却时长（默认 60s，测试可 override 缩短）。
  final Duration fullReconnectCooldown;

  /// 重连预算耗尽哨兵的巡检间隔（默认 60s；后台/锁屏豁免，测试可 override 缩短）。
  final Duration recoverySentinelInterval;

  /// resume 主动探活失败后的额外重试次数（默认 2，测试可 override）。
  final int resumeProbeRetries;

  /// resume 主动探活重试间隔（默认 2s，等待 WiFi/frp 就绪，测试可 override）。
  final Duration resumeProbeRetryDelay;

  /// 死区兜底巡检阈值（处于进行中相位但 activeStreamId 为空、且距上次进展 ≥ 该值 → 触发死区恢复）。
  final Duration deadZoneStallThreshold;

  /// 死区兜底巡检触发后的冷却时长（防频繁触发向服务端拉取）。
  final Duration deadZoneCooldown;

  /// 可选随机数发生器（测试可注入确定性 Random）。
  final Random? random;

  /// 可选自定义错峰延迟计算（测试可 override）。
  final Duration Function([int? attempt])? customJitter;

  /// 默认共享随机数发生器。
  static final Random _defaultRandom = Random();

  /// 实际最大自动重连尝试次数。
  int get effectiveMaxReconnectAttempts => maxReconnectAttempts;

  /// 实际熔断阈值（收尾帧连续解析失败上限）。
  int get effectiveMaxMalformedDoneSettleAttempts =>
      maxMalformedDoneSettleAttempts;

  /// 获取指定尝试序号的退避等待时长（attempt 从 0 开始）。
  Duration backoffDelayForAttempt(int attempt) {
    if (reconnectBackoffDelays.isEmpty) return Duration.zero;
    final index = attempt.clamp(0, reconnectBackoffDelays.length - 1);
    return reconnectBackoffDelays[index];
  }

  /// 获取本次重试/探活的错峰延迟。
  Duration jitterForAttempt([int? attempt]) {
    if (customJitter != null) return customJitter!(attempt);
    if (reconnectJitterMax <= Duration.zero) return Duration.zero;
    final maxMs = reconnectJitterMax.inMilliseconds;
    if (maxMs <= 0) return Duration.zero;
    final rng = random ?? _defaultRandom;
    return Duration(milliseconds: rng.nextInt(maxMs));
  }
}

/// 看门狗配置 Provider（测试可 override）。
final chatWatchdogConfigProvider = Provider<ChatWatchdogConfig>(
  (ref) => const ChatWatchdogConfig(),
);

/// 时钟 Provider（看门狗/时间戳用；测试可 override 注入可控假时钟）。
final chatClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 回合完成 → 会话列表刷新的节流状态。
///
/// 挂在 Provider 上：同一 ProviderContainer 内所有 ChatController 实例
/// （不同会话并发完成）共享节流窗口，合并为一次列表刷新；跨容器
/// （测试）天然隔离，避免模块级状态泄漏。
class SessionListRefreshThrottleState {
  /// 最近一次回合完成触发的会话列表刷新时间。
  DateTime? lastRefreshAt;
}

/// #30：回合完成 → 会话列表刷新节流状态 Provider。
final sessionListRefreshThrottleProvider =
    Provider<SessionListRefreshThrottleState>(
      (ref) => SessionListRefreshThrottleState(),
    );

/// 聊天服务器 API（生产 [ChatApiClient] 包 ApiClient；测试可 override 注入 fake）。
final chatApiProvider = Provider<ChatServerApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return ChatApiClient(client);
});

/// 聊天控制器（family by sessionId；空串 = 新会话）。
final chatControllerProvider =
    NotifierProvider.family<ChatController, ChatState, String>(
      ChatController.new,
    );

/// 回合完成回调（done / stream_end 成功收尾时由 [ChatController] 调用）。
///
/// 默认 no-op（测试不受影响）；生产由 main.dart 用
/// notifications 的 [turnNotificationHookProvider] override 注入，
/// 实现「后台发通知、前台不发」。
typedef ChatTurnCompletedCallback = void Function(
  String sessionId,
  String title,
  String preview,
);

/// 回合完成回调 Provider（notifications feature 注入点）。
final chatTurnCompletedCallbackProvider = Provider<ChatTurnCompletedCallback>(
  (ref) => (sessionId, title, preview) {},
);

/// 澄清请求回调（clarify 事件触发时由 [ChatController] 调用）。
typedef ChatClarificationNeededCallback = void Function(
  String sessionId,
  String question,
);

/// 澄清请求回调 Provider（notifications feature 注入点）。
final chatClarificationNeededCallbackProvider =
    Provider<ChatClarificationNeededCallback>(
      (ref) => (sessionId, question) {},
    );

/// 会话异常回调（cancel / error / 重连失败时由 [ChatController] 调用）。
typedef ChatSessionErrorCallback = void Function(
  String sessionId,
  String title,
  String preview,
);

/// 会话异常回调 Provider（notifications feature 注入点）。
final chatSessionErrorCallbackProvider = Provider<ChatSessionErrorCallback>(
  (ref) => (sessionId, title, preview) {},
);

/// 回合实时活动（#120：实况通知/灵动岛正文与状态栏 chip 的来源）。
///
/// 与「相位」的区别：相位是 UI 主分支（九态），活动是**面向岛的一句话动作**
/// （思考中／调用工具／输出中／等待回复／等待批准）。二者由 ChatController
/// 在同一批事件点同时推进，活动粒度更粗、只为通知可读性服务。
enum ChatLiveActivity {
  /// 推理中（reasoning 事件持续到达）。
  thinking,

  /// 工具调用中（tool_started；[ChatLiveActivityCallback] 的 detail 带工具名）。
  tool,

  /// 正文输出中（token 事件）。
  output,

  /// 等待主人回复（澄清卡片已弹出，[ChatPhase.clarifyPending]）。
  waitingReply,

  /// 等待主人批准（审批卡片已弹出，[ChatPhase.approvalPending]）。
  waitingApproval,

  /// 回合完成（#129）：done / stream_end 正常收尾 → 岛上显示「已完成」，
  /// 停留（见 ChatController.liveActivityDwell）后自动撤岛。
  completed,

  /// 回合中断（#129）：cancel / error 收尾 → 岛上显示「已中断」，同样停留。
  interrupted,

  /// 撤销实况通知（完成/中断态停留到期，或需立即撤岛时）。
  finished,
}

/// 回合实时活动回调（活动变化时由 [ChatController] 调用）。
///
/// [detail]：工具名等补充信息（无则空串）。
typedef ChatLiveActivityCallback = void Function(
  String sessionId,
  String title,
  ChatLiveActivity activity,
  String detail,
);

/// 回合实时活动回调 Provider（notifications feature 注入点）。
///
/// 默认 no-op（测试不受影响）；生产由 main.dart 用 notifications 的
/// `chatLiveActivityHookProvider` override 注入，驱动实况通知（LIVE）。
final chatLiveActivityCallbackProvider = Provider<ChatLiveActivityCallback>(
  (ref) => (sessionId, title, activity, detail) {},
);

/// 当前相位（UI 主分支只 switch 它）。
final chatPhaseProvider = Provider.family<ChatPhase, String>((ref, sessionId) {
  return ref.watch(chatControllerProvider(sessionId)).phase;
});

/// 是否可发送（idle 且非缓存模式且无停止在途）。
final canSendProvider = Provider.family<bool, String>((ref, sessionId) {
  final state = ref.watch(chatControllerProvider(sessionId));
  return state.phase == ChatPhase.idle &&
      !state.isViewingCachedData &&
      !state.isShowingOfflineCache &&
      !state.stream.isCancelling;
});

final _transcriptCache = <String, List<TranscriptMessage>>{};

bool _listEqualsTranscript(
  List<TranscriptMessage> a,
  List<TranscriptMessage> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 活跃回合 live 层对本回合服务端行的正文覆盖情况（#121）。
///
/// live（流式）层渲染的是流式消息的累积正文；回合中途 transcript 重载会把本回合
/// 已落库的 assistant 行并入消息列表，若这些行再按常规 transcript 行渲染，同一段
/// 正文就会出现两遍（真机表现：首行吞掉全轮正文 + 其后各行正文重复一次）。
/// 仅在「行正文已被 live 正文覆盖」时跳过，故不会隐藏 live 未渲染的内容。
class _LiveCoverage {
  const _LiveCoverage({required this.liveContent, required this.turnStartIndex});

  /// live 层当前渲染的正文（流式消息 content，已 trim）。
  final String liveContent;

  /// 本回合起点：最后一个可见 user 行下标（无 user 边界时为 -1）。
  final int turnStartIndex;

  bool covers(ChatMessage message) {
    if (message.role != 'assistant') return false;
    final text = message.content?.trim() ?? '';
    if (text.isEmpty) return false;
    return liveContent.contains(text);
  }
}

/// live 层存活且已有正文时返回覆盖信息；否则 null（此时按原样渲染）。
_LiveCoverage? _liveCoverage(List<ChatMessage> messages, String? streamingId) {
  if (streamingId == null || streamingId.isEmpty) return null;
  String? liveContent;
  for (final message in messages) {
    if (message.messageId != streamingId) continue;
    final content = message.content?.trim() ?? '';
    if (content.isNotEmpty) liveContent = content;
    break;
  }
  if (liveContent == null) return null;
  var turnStartIndex = -1;
  for (var i = messages.length - 1; i >= 0; i--) {
    if (TranscriptTurnClassifier.isUserTurnBoundary(messages[i])) {
      turnStartIndex = i;
      break;
    }
  }
  return _LiveCoverage(
    liveContent: liveContent,
    turnStartIndex: turnStartIndex,
  );
}

/// 展示层转录消息（过滤 tool 消息 / 纯工具结果消息 / 流式消息；renderId 稳定）。
final transcriptMessagesProvider =
    Provider.family<List<TranscriptMessage>, String>((ref, sessionId) {
      final state = ref.watch(chatControllerProvider(sessionId));
      final messages = state.messages;
      final offset = state.messagesOffset;
      final streamingId = state.stream.streamingAssistantMessageId;
      final completedToolGroups = state.completedToolCallGroups;
      // #121：活跃回合的 live 层已渲染的正文，transcript 不得再渲染一遍。
      // 只在 live 层存活（流式消息仍在消息列表里且已有正文）时生效；
      // 未被 live 覆盖的行照常渲染，故不会丢内容。
      final liveCoverage = _liveCoverage(messages, streamingId);
      final result = <TranscriptMessage>[];
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        if (message.role == 'tool') continue;
        if (TranscriptTurnClassifier.isToolResultOnlyMessage(message)) continue;
        if (message.messageId != null && message.messageId == streamingId) {
          continue;
        }
        if (liveCoverage != null &&
            i > liveCoverage.turnStartIndex &&
            liveCoverage.covers(message)) {
          continue;
        }

        // Hermex parity: do not create a visible row for empty internal messages.
        // Attachment-only user messages remain visible; reasoning/tool groups are
        // rendered on their anchored assistant row even when its text is empty.
        final hasVisibleContent = message.content?.trim().isNotEmpty == true;
        final hasAttachments = message.attachments?.isNotEmpty == true;
        final anchorId = TranscriptTurnClassifier.anchorID(
          message,
          at: i,
          messageOffset: offset,
        );
        final hasToolGroups = completedToolGroups.any(
          (group) =>
              group.anchorMessageID == message.messageId ||
              group.anchorMessageID == anchorId,
        );
        // 空内容消息仅当挂载工具组/思考组/附件时才保留为可见行；纯 reasoning
        // 挂载不保留——思考已由 withThinkingRows 融进工具组（think 子卡行，纯
        // 思考消息会补 persisted-think- 工具组走 hasToolGroups），独立
        // ReasoningGroup 不再渲染，仅靠 reasoning 挂载会导致「空气泡」
        //（agy 纯工具回合 c='' 消息被保留却渲染成 0 高度气泡 + padding 占位）。
        if (!hasVisibleContent && !hasAttachments && !hasToolGroups) {
          continue;
        }
        result.add(
          TranscriptMessage(
            loadedIndex: i,
            renderId: 'transcript:${offset + i}',
            anchorId: anchorId,
            message: message,
          ),
        );
      }
      final previous = _transcriptCache[sessionId];
      if (previous != null && _listEqualsTranscript(previous, result)) {
        return previous;
      }
      _transcriptCache[sessionId] = result;
      return result;
    });

/// 当前流式 assistant 消息（独立流式气泡渲染层）。
final streamingMessageProvider = Provider.family<ChatMessage?, String>((
  ref,
  sessionId,
) {
  final state = ref.watch(chatControllerProvider(sessionId));
  final id = state.stream.streamingAssistantMessageId;
  if (id == null) return null;
  for (final message in state.messages) {
    if (message.messageId == id) return message;
  }
  return null;
});

/// 工具调用组（已归档 + 实时组合，按 assistant 回合分组或按消息穿插）。
final toolGroupsProvider = Provider.family<List<ToolCallGroup>, String>((
  ref,
  sessionId,
) {
  final state = ref.watch(chatControllerProvider(sessionId));
  final coalesce = ref.watch(toolGroupCoalesceProvider);
  final liveAnchor =
      state.stream.toolCallAnchorMessageId ??
      state.stream.streamingAssistantMessageId;
  // live 工具组遵循聚合设置：开启时累积为一张卡（整轮聚合）；
  // 关闭时按次拆分（每个工具调用一张卡），不再「总是按回合聚合」。
  final live = state.liveToolCalls.isEmpty
      ? const <ToolCallGroup>[]
      : coalesce
      ? [
          ToolCallGroup.live(
            anchorMessageID: liveAnchor,
            toolCalls: state.liveToolCalls,
          ),
        ]
      : [
          for (final call in state.liveToolCalls)
            ToolCallGroup.live(anchorMessageID: liveAnchor, toolCalls: [call]),
        ];
  final raw = [...state.completedToolCallGroups, ...live];
  if (raw.length <= 1) return raw;
  if (!coalesce) {
    // 关闭 ≠ 完全不聚合：仅相邻（无 text/think 打断）组合并，支持穿插呈现。
    // completed 已由 controller 按相邻语义生成；live 已逐卡拆分，直接返回。
    return raw;
  }
  return ToolCallGroup.coalescingByAssistantTurn(
    raw,
    messages: state.messages,
    messageOffset: state.messagesOffset,
  );
});

/// live 时间线（流式回合内 think/text/tools 按事件先后穿插的展示条目）。
///
/// 返回语义：
/// - `null`：非时间线模式（重连归档等无法还原段落边界的场景）→ 渲染层回退
///   旧的「分组式」流式气泡（思考卡 → 正文 → 工具卡），保证不丢内容；
/// - 空列表：流式存在但尚无任何可见内容 → 思考中指示器；
/// - 非空：按事件顺序排列的段落条目，渲染层逐条渲染。
///
/// 聚合开关语义与历史一致：coalesce=true 时同类型段落合并为一卡（挂在
/// 首现位置）；coalesce=false 时每段独立一卡（相邻工具段自然即「相邻合并」）。
final liveTimelineProvider = Provider.family<List<LiveTimelineEntry>?, String>((
  ref,
  sessionId,
) {
  final state = ref.watch(chatControllerProvider(sessionId));
  final id = state.stream.streamingAssistantMessageId;
  if (id == null) return null;
  ChatMessage? streamingMessage;
  for (final message in state.messages) {
    if (message.messageId == id) {
      streamingMessage = message;
      break;
    }
  }
  if (streamingMessage == null) return null;

  final content = streamingMessage.content ?? '';
  final reasoningText = state.liveReasoningText;
  final points = state.liveTimelinePoints;
  final hideReasoning = ref.watch(hideReasoningProvider);
  final toolCoalesce = ref.watch(toolGroupCoalesceProvider);

  // 断点为空但有锚定本流式消息的归档内容（重连/恢复路径）→ 无法还原段落
  // 边界，回退旧分组式气泡（内容与卡片由 legacy streamingTools 过滤承载）。
  if (points.isEmpty) {
    final hasAnchoredArchive =
        state.completedToolCallGroups.any((g) => g.anchorMessageID == id) ||
        state.completedReasoningGroups.any((g) => g.anchorMessageId == id);
    if (hasAnchoredArchive) return null;
    if (content.trim().isEmpty &&
        reasoningText.trim().isEmpty &&
        state.liveToolCalls.isEmpty) {
      return const <LiveTimelineEntry>[]; // 思考中指示器
    }
    // 防御兜底：内容非空但断点缺失 → 按「思考 → 正文 → 工具」单段呈现。
    return fallbackLiveTimelineEntries(
      streamingId: id,
      content: content,
      reasoningText: reasoningText,
      liveToolCalls: state.liveToolCalls,
      hideReasoning: hideReasoning,
      toolCoalesce: toolCoalesce,
    );
  }

  return buildLiveTimelineEntries(
    streamingId: id,
    content: content,
    reasoningText: reasoningText,
    points: points,
    liveToolCalls: state.liveToolCalls,
    hideReasoning: hideReasoning,
    toolCoalesce: toolCoalesce,
    // 打字机水位：队列仍有待揭文本（或尚在 16ms 合并窗内）⇒ 末段正文未吐完，
    // 其后的工具/思考条目挂起（见 buildLiveTimelineEntries「正文前沿闸门」）。
    hasUnrevealedText:
        !state.isRevealQueueEmpty ||
        state.pendingAssistantTokenChunks.isNotEmpty,
  );
});

/// 排队待发送消息数。
final queuedCountProvider = Provider.family<int, String>((ref, sessionId) {
  return ref
      .watch(chatControllerProvider(sessionId))
      .queuedSlashMessages
      .length;
});

/// 模型选择器可选项（默认空 = 仅"跟随服务器默认"；测试可 override）。
final chatAvailableModelsProvider = Provider<List<String>>((ref) => const []);

/// 聊天大纲条目（active.md §7 聊天大纲）。
///
/// 派生自 [transcriptMessagesProvider]，过滤 `role=='user'`，
/// 实时响应流式追加用户轮次。
class OutlineEntry {
  const OutlineEntry({
    required this.index,
    required this.renderId,
    required this.messageId,
    required this.preview,
    required this.loadedIndex,
  });

  /// 用户轮次序号（从 1 起）。
  final int index;

  /// transcript renderId（`transcript:${offset+loadedIndex}` 格式，
  /// 与 `_itemKeys` 中的 key 一一对应）。
  final String renderId;

  /// 消息 id（messageId 或 id；懒加载时定位用）。
  final String? messageId;

  /// 首 40 字预览（空内容时为"用户轮次 N"）。
  final String preview;

  /// 在 transcript 中的 loadedIndex（懒加载粗跳比率计算用）。
  final int loadedIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutlineEntry &&
          runtimeType == other.runtimeType &&
          renderId == other.renderId &&
          preview == other.preview &&
          index == other.index;

  @override
  int get hashCode => Object.hash(renderId, preview, index);
}

/// 大纲条目列表 Provider（by sessionId，实时响应 transcript 变化）。
final chatOutlineEntriesProvider = Provider.family<List<OutlineEntry>, String>((
  ref,
  sessionId,
) {
  final transcript = ref.watch(transcriptMessagesProvider(sessionId));
  var userIndex = 0;
  final result = <OutlineEntry>[];
  for (final entry in transcript) {
    if (entry.message.role != 'user') continue;
    userIndex++;
    final raw = entry.message.content?.trim() ?? '';
    final preview = raw.isEmpty
        ? '用户轮次 $userIndex'
        : (raw.length > 40 ? '${raw.substring(0, 40)}\u2026' : raw);
    result.add(
      OutlineEntry(
        index: userIndex,
        renderId: entry.renderId,
        messageId: entry.message.messageId?.isNotEmpty == true
            ? entry.message.messageId
            : entry.message.id,
        preview: preview,
        loadedIndex: entry.loadedIndex,
      ),
    );
  }
  return result;
});
