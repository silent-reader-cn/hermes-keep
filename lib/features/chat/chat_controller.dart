import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sse_client.dart';
import '../../core/cache/cache_providers.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/context_window_snapshot.dart';
import '../../core/models/json_value.dart';
import '../../core/models/message_attachment.dart';
import '../../core/models/session.dart';
import '../../core/models/tool_call.dart';
import '../../core/models/upload_response.dart';
import '../../core/utils/uuid.dart';
import '../../core/connections/connection_providers.dart';
import '../desktop/desktop_settings.dart';
import '../diagnostics/diagnostics_models.dart';
import '../diagnostics/diagnostics_service.dart';
import '../notifications/notification_providers.dart';
import '../session_list/session_list_providers.dart';
import '../settings/smooth_streaming_settings.dart';
import '../settings/tool_group_settings.dart';
import 'chat_diff_merge.dart';
import 'chat_models.dart';
import 'chat_providers.dart';
import 'chat_server_api.dart';
import 'chat_session_channel.dart';
import 'chat_state.dart';

/// 回合完成 → 会话列表刷新的节流窗口。
///
/// 存量会话（非新建）回合完成也需刷新列表（#30）；窗口内多次完成
/// （同会话重复完成 / 并发多会话完成）合并为一次刷新，防高频抖动。
/// 不用 Timer 延迟触发（testWidgets/FakeAsync 下残留 Timer 会误报
/// "Timer still pending"），采用「前沿冷却 + 窗口内合并」的时间戳方案。
const Duration _sessionListRefreshThrottleWindow = Duration(milliseconds: 1500);

/// 聊天主控制器（chat_spec.md §1/§2：九态状态机 + 消息组装 + 断线恢复）。
///
/// 唯一写 `List<ChatMessage>` 的类；SSE 事件经 [_handleSseEvent] 同步串行
/// 处理；token 走「缓冲(16ms 合并) → 词级 reveal(48ms)」三段式；done 双重
/// 收尾；transportError 走「挂起 → status 检查 → 重连/replay/finalize」。
class ChatController extends FamilyNotifier<ChatState, String> {
  // -------------------------------------------------------------------------
  // 私有非状态（对齐 Swift @ObservationIgnored：Timer/游标不进 state）
  // -------------------------------------------------------------------------

  /// token 合并延迟（16ms）。
  static const mergeDelay = Duration(milliseconds: 16);

  /// 词级 reveal 间隔（标准档 64ms）。
  static const revealInterval = Duration(milliseconds: 64);

  /// 每 tick 最多 reveal 的词单元数（标准档 2）。
  static const maxWordUnitsPerTick = 2;

  /// reveal 最大滞后（标准档 3s；积压超过该时长一次性排空）。
  static const maxRevealLag = Duration(seconds: 3);

  /// reveal 队列词单元硬上限（超限直接落全文，防后台/锁屏积压爆吐卡死）。
  static const maxRevealQueueUnits = 2000;

  /// Live 流式期间上下文窗口读数轮询频率（2s）。
  static const contextWindowPollInterval = Duration(seconds: 2);

  ChatServerApi? _api;
  Timer? _mergeTimer;
  Timer? _revealTimer;
  Timer? _watchdogTimer;
  Timer? _transcriptRefreshTimer;
  Timer? _clarifyPollTimer;
  Timer? _approvalPollTimer;
  Timer? _reconnectTimer;
  Timer? _statusPollJitterTimer;
  Timer? _forceReconnectJitterTimer;
  Timer? _recoverySentinelTimer;
  Timer? _resumeProbeRetryTimer;

  /// 最近一次 afterSeq=0 全量重连的 streamId（用于限频）。
  String? _lastFullReconnectStreamId;

  /// 最近一次 afterSeq=0 全量重连的时刻（用于限频 60s）。
  DateTime? _lastFullReconnectTime;

  /// 传输错误重连尝试次数（收到任意成功事件重置为 0）。
  int _reconnectAttempts = 0;

  /// 本回合收尾帧（done）连续解析失败次数（回合收尾 / 新回合起始归零）。
  int _malformedDoneStreak = 0;

  /// 词级 reveal 队列（合并缓冲产出、逐 tick 消费）。
  final List<String> _revealQueue = [];

  /// live 时间线断点序列号（单调递增，用于渲染 key；新回合归零）。
  int _timelineSequence = 0;

  /// reveal 队列开始积压的时刻（最大滞后判定）。
  DateTime? _revealQueueStart;

  /// 最近一次内容新增（看门狗 5s 阈值）。
  DateTime? _lastProgress;

  /// 最近一次传输活动（看门狗 12s/18s/25s 阈值）。
  DateTime? _lastTransportActivity;

  /// prefill 等待期间超时阈值（连续无进度 ≥90s 自愈清 prefill 态）。
  static const Duration _prefillStaleTimeout = Duration(seconds: 90);

  /// 最近一次进入 prefill loading / notConfigured 的起始时刻。
  DateTime? _prefillSince;

  /// 最近一次 live 上下文窗口轮询请求发起的时刻。
  DateTime? _lastContextPollTime;

  /// 标记是否有上下文轮询请求正在途中，防并发重复请求。
  bool _isContextPolling = false;

  // #156 压缩上下文（异步 start + status 轮询）。
  Timer? _compressPollTimer;
  int _compressPollAttempt = 0;
  int _compressPollErrors = 0;
  bool _compressPollInFlight = false;
  bool _compressResumeChecked = false;

  /// status 轮询冷却截止。
  DateTime? _statusCheckCooldownUntil;

  /// 最近一次从后台/锁屏恢复的时刻（用于诊断统计 resume→首字耗时）。
  DateTime? _resumedAt;

  /// 异步操作代数守卫（防双 finalize / 覆盖新流）。
  int _generation = 0;

  bool _disposed = false;

  /// App 生命周期非 resumed（后台/锁屏/隐藏）期间暂停 reveal/merge 消费，
  /// resumed 后直接铺全文并重新校准看门狗基线。
  bool _appPaused = false;

  /// 回合实时活动（#120 实况通知/灵动岛）：最近一次上报的活动、detail 与标题。
  ///
  /// **标题必须进去重键**（#144）：岛的最大字号位承载会话身份（B 案），若去重只看
  /// (activity, detail)，则「标题变了而活动没变」的上报会被静默按掉 —— 新会话发
  /// 首条消息时岛的标题会长期停在占位值（主人 2026-09-20 报告：一直是 untitled）。
  ChatLiveActivity? _liveActivity;
  String _liveActivityDetail = '';
  String _liveActivityTitle = '';

  /// #124：已发出通知的 clarify_id，避免轮询/重连重建卡片时重复弹系统通知。
  String? _notifiedClarifyId;

  /// #124：轮询 pending 为空的连续次数，用于抗抖。
  int _emptyPendingStreak = 0;

  /// #127 静默兜底：最近一次用户动作（发消息/作答）时刻 —— 兜底巡检的激活窗口起点。
  DateTime? _lastUserActionAt;

  /// #127 静默兜底：冷却截止时刻，避免连续触发重复拉取。
  DateTime? _stallGuardCooldownUntil;

  /// #142 死区兜底：冷却截止时刻，避免连续触发重复拉取。
  DateTime? _deadZoneCooldownUntil;

  /// #127 静默兜底：是否「已发出请求/作答但尚未收到任何服务端进展」。
  /// 由 `_markUserAction`（发送/作答）置 true、`_markProgress`（收到进展）
  /// 置 false —— 兜底巡检只在这个未决期待存在时动手，避免回合正常收尾后
  /// 仍多拉一次（实测会把「无残留请求」类用例打红）。
  bool _awaitingServerContent = false;

  /// #127：等待态结束走恢复路径的次数（@visibleForTesting 观测点）。
  int _promptResolvedResumes = 0;

  /// #127 静默兜底：用户动作后多久内允许兜底激活（超出视为空闲会话，不打扰）。
  static const Duration _stallGuardActiveWindow = Duration(seconds: 90);

  /// #127 静默兜底：多久没有任何服务端进展即视为「疑似静止」。
  static const Duration _stallGuardStallThreshold = Duration(seconds: 15);

  /// #127 静默兜底：两次兜底拉取的最小间隔。
  static const Duration _stallGuardCooldown = Duration(seconds: 20);

  /// 重放期间是否需要逐帧重建时间线断点（仅断点为空的恢复场景为 true）。
  /// 正常 live 重连断点仍在：重放帧全命中时不再补点，避免已展示段在时间线
  /// 尾部重复叠加成簇（底部连续思考/文本卡簇的放大源）。
  bool _replayRebuildTimeline = false;

  /// SSE 连接当前是否存活（409 恢复路径判断是否需要重连）。
  bool _streamConnected = false;

  /// loadYoloState 一次性守卫（页面每次 build 都会触发，仅首次真正拉取）。
  bool _yoloLoaded = false;

  /// P4：新会话创建后待通过 done/stream_end 二次刷新的会话 id 集合。
  ///
  /// 仅用于「首轮完成后才落库」的异步后端：startChat 阶段已做立即+600ms
  /// 双次补拉，若服务端仍未落库，则在 done/stream_end 成功收尾时再做一次
  /// 强制刷新，避免用户需手动下拉。
  final Set<String> _pendingNewSessionIds = {};

  DateTime _now() => ref.read(chatClockProvider)();

  ChatWatchdogConfig get _watchdogConfig =>
      ref.read(chatWatchdogConfigProvider);

  bool get _coalesceTools => ref.read(toolGroupCoalesceProvider);

  bool get _smoothStreaming => ref.read(smoothStreamingProvider);

  SmoothStreamingSpeedPreset get _smoothStreamingSpeed =>
      ref.read(smoothStreamingSpeedProvider);

  List<PersistedToolCall>? _lastPersistedToolCalls;

  double _nowSeconds() => _now().millisecondsSinceEpoch / 1000;

  @override
  ChatState build(String sessionId) {
    _api = ref.read(chatApiProvider);
    _disposed = false;
    _streamConnected = false;
    _generation++;
    _lastProgress = null;
    _lastTransportActivity = null;
    _prefillSince = null;
    _statusCheckCooldownUntil = null;
    _revealQueue.clear();
    _revealQueueStart = null;
    _appPaused = false;
    _liveActivity = null;
    _liveActivityDetail = '';
    _liveActivityTitle = '';
    _notifiedClarifyId = null;
    _emptyPendingStreak = 0;
    _lastUserActionAt = null;
    _stallGuardCooldownUntil = null;
    _deadZoneCooldownUntil = null;
    _awaitingServerContent = false;
    _cancelRecoverySentinel();
    _cancelResumeProbeRetry();
    _lastContextPollTime = null;
    _isContextPolling = false;
    _startWatchdog();
    _cancelCompressionPolling();
    _compressPollAttempt = 0;
    _compressPollErrors = 0;
    _compressResumeChecked = false;
    ref.onDispose(_dispose);
    // #144 标题跟进闸：标题是岛的最大字号位主文案，凡其变化（SSE title 事件 /
    // 会话详情加载 / 改名 / 收尾补拉）都立刻按当前活动补报一次，不等下一个活动
    // 事件 —— 否则标题更新会被活动去重门挡住，岛一直停在占位标题。
    listenSelf((previous, next) {
      if (previous == null || previous.displayTitle == next.displayTitle) {
        return;
      }
      _reReportForTitleChange();
    });
    // 后台/锁屏暂停 reveal 消费、resumed 铺全文并重新校准 watchdog 基线。
    ref.listen<AppLifecycleState>(appLifecycleStateProvider, (previous, next) {
      _handleAppLifecycleChange(previous, next);
    });
    ref.listen(toolGroupCoalesceProvider, (prev, next) {
      if (prev != next) {
        _recomputeToolGroups(next);
      }
    });
    ref.listen(smoothStreamingProvider, (prev, next) {
      if (prev != next && !next) {
        _flushPendingRevealToFullText();
      }
    });
    ref.listen(smoothStreamingSpeedProvider, (prev, next) {
      if (prev != next) {
        _handleSpeedPresetChanged();
      }
    });
    ref.listen(approvalStreamEnabledProvider, (prev, next) {
      if (prev != next) {
        if (next) {
          if (sessionId.isNotEmpty) {
            _startApprovalChannel(sessionId);
          }
        } else {
          _stopApprovalChannel();
        }
      }
    });
    if (sessionId.isNotEmpty) {
      _startClarifyChannel(sessionId);
      _startApprovalChannel(sessionId);
      _startSessionContentChannel(sessionId);
      // build 期间 state 未初始化，推迟到微任务再加载（读 state 安全）。
      scheduleMicrotask(() {
        if (_disposed) return;
        unawaited(loadMessages());
      });
    }
    return ChatState.initial(sessionId: sessionId);
  }

  void _recomputeToolGroups(bool coalesce) {
    final serverDerivedGroups = ToolCallGroup.groups(
      persistedToolCalls: _lastPersistedToolCalls ?? const [],
      messages: state.messages,
      messageOffset: state.messagesOffset,
      coalesce: coalesce,
    );
    final reanchoredExistingToolGroups = _reanchorGroupsToMessages(
      state.completedToolCallGroups,
      state.messages,
      messageOffset: state.messagesOffset,
    );
    if (serverDerivedGroups.isNotEmpty) {
      state = state.copyWith(completedToolCallGroups: serverDerivedGroups);
    } else if (reanchoredExistingToolGroups.isNotEmpty) {
      final nextToolGroups = ToolCallGroup.merging(
        primaryGroups: serverDerivedGroups,
        fallbackGroups: reanchoredExistingToolGroups,
      );
      state = state.copyWith(completedToolCallGroups: nextToolGroups);
    }
  }

  void _handleSpeedPresetChanged() {
    if (_revealTimer != null) {
      _revealTimer?.cancel();
      _revealTimer = null;
      if (_revealQueue.isNotEmpty && !_appPaused && _smoothStreaming) {
        _startRevealTimerIfNeeded();
      }
    }
  }

  void _dispose() {
    _disposed = true;
    _generation++;
    _mergeTimer?.cancel();
    _revealTimer?.cancel();
    _watchdogTimer?.cancel();
    _prefillSince = null;
    _transcriptRefreshTimer?.cancel();
    _cancelReconnectTimer();
    // #129：完成/中断态停留计时器随控制器销毁一并清理。
    _cancelLiveActivityDismiss();
    _cancelJitterTimers();
    _cancelRecoverySentinel();
    _cancelResumeProbeRetry();
    _resetFullReconnectThrottle();
    _lastContextPollTime = null;
    _isContextPolling = false;
    _stopClarifyChannel();
    // #156：压缩轮询随控制器销毁一并停止。
    _cancelCompressionPolling();
    _stopApprovalChannel();
    _stopSessionContentChannel();
    _api?.stopStream();
  }

  // -------------------------------------------------------------------------
  // 用户动作
  // -------------------------------------------------------------------------

  /// 发送新消息；流式期间按 [behavior] 处理（默认 steer）。
  ///
  /// [attachments] 为随消息一并提交的待发附件（已上传到服务端，
  /// 以 `{name, path, mime, size, is_image}` 传给 `/api/chat/start`）。
  Future<bool> send(
    String text, {
    StreamingSendBehavior behavior = StreamingSendBehavior.steer,
    List<PendingAttachment> attachments = const [],
  }) async {
    final current = state;
    if (current.isViewingCachedData) {
      _setSendError('Reconnect to the server to send a message.');
      return false;
    }
    // #156：压缩上下文会重写 transcript（插摘要锚点 + 裁剪轮次），此时发出
    // 新回合会与服务端压缩线程互相覆盖 —— 服务端不拦，故客户端自守。
    if (current.isCompressingContext) {
      _setSendError('正在压缩上下文，请稍候再发送。');
      return false;
    }
    _cancelReconnectTimer();
    _cancelJitterTimers();
    _cancelRecoverySentinel();
    _cancelResumeProbeRetry();
    _resetFullReconnectThrottle();
    _reconnectAttempts = 0;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return false;
    if (current.stream.activeStreamId != null) {
      return _submitStreamingMessage(trimmed, behavior);
    }
    return _sendMessage(trimmed, attachments: attachments);
  }

  /// 停止当前响应（保留已流出文本，不删除）。
  Future<bool> stop() async {
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return false;
    state = state.copyWith(stream: state.stream.copyWith(isCancelling: true));
    final gen = _generation;
    try {
      final response = await _api!.cancelChat(streamId);
      if (_disposed || gen != _generation) return false;
      if (response.ok == true || response.cancelled == true) {
        _finishStream(endPhase: ChatPhase.cancelled);
        return true;
      }
      state = state.copyWith(
        stream: state.stream.copyWith(isCancelling: false),
        sendErrorMessage: response.error ?? '服务器未能停止当前响应。',
      );
      return false;
    } on ApiException catch (error) {
      if (_disposed || gen != _generation) return false;
      state = state.copyWith(
        stream: state.stream.copyWith(isCancelling: false),
        sendErrorMessage: error.message,
      );
      return false;
    }
  }

  /// 显式选择模型（发送时带 explicit_model_pick）。
  void selectModel(String? model, {String? modelProvider}) {
    state = state.copyWith(
      model: model,
      clearModel: model == null,
      modelProvider: modelProvider,
      clearModelProvider: modelProvider == null,
      explicitModelPick: model != null,
    );
  }

  /// 清除当前展示的错误。
  void dismissError() {
    state = state.copyWith(
      clearSendErrorMessage: true,
      clearErrorMessage: true,
    );
  }

  /// 关闭离线缓存横幅。
  void dismissOfflineCache() {
    state = state.copyWith(isShowingOfflineCache: false);
  }

  /// 重命名当前会话，并立即更新聊天页标题。
  Future<bool> renameSession(String title) async {
    final trimmed = title.trim();
    if (state.sessionId.isEmpty || state.isReadOnly || trimmed.isEmpty) {
      return false;
    }
    try {
      final response = await _api!.renameSession(
        sessionId: state.sessionId,
        title: trimmed,
      );
      if (response.ok == false) {
        _setSendError(response.error ?? '重命名会话失败。');
        return false;
      }
      state = state.copyWith(displayTitle: trimmed);
      _syncSessionListRename(trimmed);
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 更新当前会话的置顶状态（成功后免网络同步会话列表）。
  Future<bool> setPinned(bool pinned) => _mutateSession(
    () => _api!.pinSession(sessionId: state.sessionId, pinned: pinned),
    failure: '置顶状态更新失败。',
    onSuccess: (id) => _syncSessionListPinned(id, pinned),
  );

  /// 更新当前会话的归档状态（成功后免网络同步会话列表）。
  Future<bool> setArchived(bool archived) => _mutateSession(
    () => _api!.archiveSession(sessionId: state.sessionId, archived: archived),
    failure: '归档状态更新失败。',
    onSuccess: (id) => _syncSessionListArchived(id, archived),
  );

  Future<bool> _mutateSession(
    Future<SessionMutationResponse> Function() request, {
    required String failure,
    void Function(String sessionId)? onSuccess,
  }) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    try {
      final response = await request();
      if (response.ok == false) {
        _setSendError(response.error ?? failure);
        return false;
      }
      final callback = onSuccess;
      if (callback != null) callback(state.sessionId);
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 删除当前会话。
  Future<bool> deleteSession() async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    final deletedId = state.sessionId;
    try {
      final response = await _api!.deleteSession(deletedId);
      if (response.ok == false) {
        _setSendError(response.error ?? '删除会话失败。');
        return false;
      }
      _syncSessionListDeleted(deletedId);
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 从当前会话创建分支，返回新会话 ID。
  ///
  /// [keepCount] 非空时仅复制前 N 条消息（消息级分支）。
  Future<String?> branchSession({int? keepCount}) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return null;
    final parentId = state.sessionId;
    try {
      final response = await _api!.branchSession(
        parentId,
        keepCount: keepCount,
      );
      if (response.sessionId == null) {
        _setSendError(response.error ?? '创建会话分支失败。');
      } else {
        _syncSessionListBranched(response, parentId: parentId);
      }
      return response.sessionId;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return null;
    }
  }

  /// 从此处创建分支：保留 [messageIndex] 之前（含）的消息分支出新会话。
  Future<String?> branchAt(int messageIndex) async {
    final messages = state.messages;
    if (messageIndex < 0 || messageIndex >= messages.length) return null;
    return branchSession(keepCount: messageIndex + 1);
  }

  // ---------------------------------------------------------------------------
  // #156 压缩上下文（异步 start + 轮询 status）
  // ---------------------------------------------------------------------------
  //
  // 不再走同步 `POST /api/session/compress`：该接口在大上下文 / 反向代理（frp）
  // 下会超时 —— 客户端 60s 判失败并复位状态，而服务端仍在压缩，于是「状态撒谎
  // + 用户重复触发」。服务端为此提供 start + status 两件套（官方 WebUI 已全面
  // 改走异步版，见 webui CHANGELOG PR #2128）。
  //
  // 压缩状态挂在 ChatState（isCompressingContext）而非 UI 局部：弹窗关掉、
  // 页面切走都仍在会话状态里，指示器据此持续转圈（主人 #156 诉求）。

  /// 轮询节奏对齐官方 WebUI（commands.js `_pollManualCompressionResult`）：
  /// 初始 700ms，每次 +300ms，上限 2000ms。
  static const int _compressPollInitialMs = 700;
  static const int _compressPollStepMs = 300;
  static const int _compressPollMaxMs = 2000;

  /// 轮询次数兜底（按平均 1.6s ≈ 24 分钟）：正常压缩远早于此收敛，此上限只为
  /// 防止异常情况下（服务端 job 长期 running）留下永不停止的轮询。
  static const int _compressPollMaxAttempts = 900;

  /// 连续轮询失败上限：容忍网络抖动，超过即收敛并显式报错，绝不静默挂死。
  static const int _compressPollMaxErrors = 5;

  /// 启动异步压缩；返回是否已进入压缩态（立刻返回，不等压缩完成）。
  ///
  /// 幂等：本地已在压缩中直接返回 true；服务端对重复 start 也幂等复用
  /// 同一 running job。
  Future<bool> startCompression({String? focusTopic}) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    if (state.isViewingCachedData) {
      _setSendError('Reconnect to the server to compress.');
      return false;
    }
    if (state.isCompressingContext) return true;
    if (state.stream.activeStreamId != null) {
      _setSendError('回合进行中，请等本回合结束后再压缩。');
      return false;
    }
    final api = _api;
    if (api == null) return false;
    final sid = state.sessionId;
    final trimmed = focusTopic?.trim();
    try {
      final started = await api.startSessionCompression(
        sessionId: sid,
        focusTopic: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      );
      if (_disposed) return false;
      if (started.isFailed) {
        _setSendError(started.error ?? '压缩会话失败。');
        return false;
      }
      if (started.isDone) {
        // 罕见：job 在本次请求内就跑完（done 载荷即完整压缩结果）。
        await _applyCompressionResult(started.result);
        return false;
      }
      if (!started.isRunning) {
        _setSendError(started.error ?? '压缩会话失败。');
        return false;
      }
      state = state.copyWith(isCompressingContext: true);
      _startCompressionPolling();
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _setSendError(error.message);
      return false;
    }
  }

  /// 进入 / 切回会话时探测服务端是否仍在压缩（#156 恢复链）。
  ///
  /// controller 常驻，本地态在切换会话期间本就保真，故此处只为覆盖**本地态
  /// 丢失**的场景（App 重启、轮询达上限收敛、job 早于本地状态存在）：服务端
  /// running 则接管轮询、重新点亮指示器。
  ///
  /// done / idle 一律静默 —— 压缩结果早已落库，避免每次进入会话都触发一次
  /// 多余刷新与提示。
  Future<void> resumeCompressionIfRunning() async {
    final sid = state.sessionId;
    if (sid.isEmpty || _disposed) return;
    if (state.isCompressingContext || _compressResumeChecked) return;
    _compressResumeChecked = true;
    try {
      final api = _api;
      if (api == null) return;
      final status = await api.compressionStatus(sid);
      if (_disposed) return;
      if (!status.isRunning) return;
      state = state.copyWith(isCompressingContext: true);
      _startCompressionPolling();
    } on ApiException {
      // 探测失败静默（不影响正常使用）；下次进入会话再探。
      _compressResumeChecked = false;
    }
  }

  void _startCompressionPolling() {
    _cancelCompressionPolling();
    _compressPollAttempt = 0;
    _compressPollErrors = 0;
    _scheduleCompressionPoll();
  }

  void _scheduleCompressionPoll() {
    final delayMs =
        (_compressPollInitialMs + _compressPollAttempt * _compressPollStepMs)
            .clamp(_compressPollInitialMs, _compressPollMaxMs);
    _compressPollTimer?.cancel();
    _compressPollTimer = Timer(Duration(milliseconds: delayMs), () {
      unawaited(_pollCompressionStatus());
    });
  }

  Future<void> _pollCompressionStatus() async {
    if (_disposed || !state.isCompressingContext) return;
    final sid = state.sessionId;
    if (sid.isEmpty || _compressPollInFlight) return;
    final api = _api;
    if (api == null) {
      _finishCompressionWithError('连接不可用，已停止跟踪压缩。');
      return;
    }
    _compressPollInFlight = true;
    try {
      final status = await api.compressionStatus(sid);
      if (_disposed) return;
      _compressPollAttempt++;
      _compressPollErrors = 0;
      if (status.isRunning) {
        if (_compressPollAttempt >= _compressPollMaxAttempts) {
          _finishCompressionWithError('压缩任务长时间未完成，已停止跟踪。');
          return;
        }
        _scheduleCompressionPoll();
        return;
      }
      if (status.isDone) {
        await _applyCompressionResult(status.result);
        return;
      }
      if (status.isFailed) {
        _finishCompressionWithError(status.error ?? '压缩会话失败。');
        return;
      }
      // idle：服务端已无该会话的压缩任务（结果过期 / 服务重启 / 从未启动）——
      // 收敛本地态，避免永久转圈。
      _cancelCompressionPolling();
      state = state.copyWith(isCompressingContext: false);
    } on ApiException catch (error) {
      if (_disposed) return;
      _compressPollErrors++;
      if (_compressPollErrors >= _compressPollMaxErrors) {
        _finishCompressionWithError(error.message);
        return;
      }
      // 单次抖动：继续按退避重试。
      _compressPollAttempt++;
      _scheduleCompressionPoll();
    } finally {
      _compressPollInFlight = false;
    }
  }

  /// 压缩成功收尾：复位状态 + 刷新 transcript + 轻提示。
  ///
  /// 语义对齐原同步路径（`setNotice('会话已压缩')` → `loadMessages()` →
  /// 用摘要 token 估算覆盖 snapshot）。
  Future<void> _applyCompressionResult(SessionCompressResponse? result) async {
    _cancelCompressionPolling();
    if (_disposed) return;
    state = state.copyWith(isCompressingContext: false);
    if (result == null) return;
    if (state.sessionId.isEmpty) return;
    setNotice('会话已压缩');
    await loadMessages();
    if (_disposed) return;
    // 对齐 Swift：用压缩摘要的 token 估算覆盖 snapshot 的 lastPromptTokens
    final estimate = result.summary?.compressedTokenEstimate;
    if (estimate != null && estimate > 0) {
      final prev = state.contextWindowSnapshot;
      if (prev != null) {
        state = state.copyWith(
          contextWindowSnapshot: prev.replacingTokensUsed(estimate),
        );
      } else {
        state = state.copyWith(
          contextWindowSnapshot: ContextWindowSnapshot(
            lastPromptTokens: estimate,
            contextLength: prev?.contextLength,
            thresholdTokens: prev?.thresholdTokens,
          ),
        );
      }
    }
  }

  void _finishCompressionWithError(String message) {
    _cancelCompressionPolling();
    if (_disposed) return;
    state = state.copyWith(isCompressingContext: false);
    _setSendError(message);
  }

  void _cancelCompressionPolling() {
    _compressPollTimer?.cancel();
    _compressPollTimer = null;
    _compressPollInFlight = false;
  }


  /// 从此处截断：保留 [messageIndex] 及其之前的全部消息，删除其后所有。
  ///
  /// [includeTarget] 为 true 时（默认）keep_count = index + 1（含自己保留）；
  /// 为 false 时 keep_count = index（不含自己保留，删除被编辑消息及其后全部，用于编辑重发）。
  /// 服务端 keep_count 从开头保留条数；越界或只读返回 false。
  Future<bool> truncateAt(int messageIndex, {bool includeTarget = true}) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    final messages = state.messages;
    if (messageIndex < 0 || messageIndex >= messages.length) return false;
    final keepCount = includeTarget ? messageIndex + 1 : messageIndex;
    if (keepCount < 0) return false;
    try {
      final response = await _api!.truncateSession(
        sessionId: state.sessionId,
        keepCount: keepCount,
      );
      if (response.session == null) {
        _setSendError('截断会话失败。');
        return false;
      }
      await loadMessages();
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 用 [text] 预填输入框（编辑/重试复用；不自动发送）。
  void prefillComposer(String text) {
    if (state.sessionId.isEmpty || state.isReadOnly) return;
    state = state.copyWith(composerPrefill: text);
  }

  /// 撤销上一轮（删除最后一轮用户消息及其后全部）；成功后刷新消息列表。
  Future<bool> undoLastTurn() async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    try {
      final response = await _api!.undoSession(state.sessionId);
      if (response.ok == false) {
        _setSendError(response.error ?? '撤销上一轮失败。');
        return false;
      }
      await loadMessages();
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 重试上一轮：服务端删除最后一轮并返回该轮用户消息原文。
  ///
  /// 成功时把文本写入 [ChatState.composerPrefill]（UI 回填输入框，不自动发送），
  /// 并刷新消息列表；返回该文本供调用方直接使用。
  Future<String?> retryLastTurn() async {
    if (state.sessionId.isEmpty || state.isReadOnly) return null;
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat',
      message: 'Retrying last turn for session: ${state.sessionId}',
    );
    try {
      final response = await _api!.retrySession(state.sessionId);
      final lastText = response.lastUserText;
      if (response.ok == false || lastText == null || lastText.isEmpty) {
        _setSendError(response.error ?? '重试上一轮失败。');
        return null;
      }
      state = state.copyWith(composerPrefill: lastText);
      await loadMessages();
      return lastText;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return null;
    }
  }

  /// 更新会话设置（workspace / model）；成功后乐观更新本地元数据并轻提示。
  ///
  /// 模型列表由 [chatAvailableModelsProvider] 注入、无服务端状态可刷新，
  /// 这里仅同步 state.model/modelProvider 供后续发送使用。
  Future<bool> updateSessionSettings({String? workspace, String? model}) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    final trimmedWorkspace = workspace?.trim();
    final trimmedModel = model?.trim();
    try {
      final response = await _api!.updateSession(
        sessionId: state.sessionId,
        workspace: (trimmedWorkspace == null || trimmedWorkspace.isEmpty)
            ? null
            : trimmedWorkspace,
        model: (trimmedModel == null || trimmedModel.isEmpty)
            ? null
            : trimmedModel,
      );
      final updated = response.session;
      state = state.copyWith(
        workspace: updated?.workspace ?? trimmedWorkspace ?? state.workspace,
        model: updated?.model ?? trimmedModel ?? state.model,
        modelProvider: updated?.modelProvider ?? state.modelProvider,
      );
      setNotice('设置已保存');
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 切换 YOLO 模式；成功后乐观更新开关状态。
  Future<bool> toggleYolo(bool enabled) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    try {
      final response = await _api!.setYolo(
        sessionId: state.sessionId,
        enabled: enabled,
      );
      if (response.ok == false) {
        _setSendError('YOLO 状态更新失败。');
        return false;
      }
      state = state.copyWith(yoloEnabled: response.yoloEnabled ?? enabled);
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 拉取当前会话 YOLO 状态（页面初始化调用；一次性守卫，失败静默）。
  Future<void> loadYoloState() async {
    if (_yoloLoaded || state.sessionId.isEmpty) return;
    _yoloLoaded = true;
    final gen = _generation;
    try {
      final response = await _api!.getYolo(state.sessionId);
      if (_disposed || gen != _generation) return;
      if (response.yoloEnabled != null) {
        state = state.copyWith(yoloEnabled: response.yoloEnabled);
      }
    } on ApiException {
      // YOLO 状态拉取失败静默（保持关闭默认值）。
    }
  }

  /// 加载更早的消息（分页）。
  Future<void> loadOlderMessages() async {
    final offset = state.messagesOffset;
    if (offset <= 0) return;
    await loadMessages(messageBefore: offset);
  }

  /// 跨端/跨设备聊天记录同步补齐（diff patch 类 VDOM 思路）。
  ///
  /// 从服务器拉取最新消息并与本地 [state.messages] 进行 diff 合并，
  /// 补全缺失消息、原地更新已变化消息，静默容错不弹全局错误。
  Future<void> syncMissingMessages({int limit = 50}) async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty || _disposed) return;
    final api = _api;
    if (api == null) return;
    // 若当前正在发送或活跃流式接收中，避免与实时消息状态竞争。
    // 注意：死区场景下（phase == streaming 但 activeStreamId == null）无活跃底层流，
    // 允许通过 syncMissingMessages 向服务端求证，因此仅在 activeStreamId != null 时早退。
    if (state.stream.activeStreamId != null ||
        state.phase == ChatPhase.sending) {
      return;
    }
    final gen = _generation;
    try {
      final response = await api.session(
        sessionId: sessionId,
        includeMessages: true,
        messageLimit: limit,
        expandRenderable: true,
      );
      if (_disposed || gen != _generation) return;
      final detail = response.session;
      if (detail == null) return;
      final serverMessages = detail.messages ?? const <ChatMessage>[];
      final mergedMessages = diffMergeMessages(
        localMessages: state.messages,
        serverMessages: serverMessages,
        liveStreamingMessageId: state.stream.streamingAssistantMessageId,
      );
      _applySessionDetail(detail: detail, mergedMessages: mergedMessages);
    } on Object {
      // 同步失败静默容错（不弹全局错误）
    }
  }

  /// 加载会话 transcript（冷启动 / 重载 / 分页）。
  Future<void> loadMessages({int? messageBefore}) async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    final api = _api;
    if (api == null) return;
    final gen = _generation;
    try {
      final response = await api.session(
        sessionId: sessionId,
        includeMessages: true,
        messageLimit: 50,
        messageBefore: messageBefore,
        expandRenderable: messageBefore == null,
      );
      if (_disposed || gen != _generation) return;
      final detail = response.session;
      if (detail == null) return;
      final loaded = detail.messages ?? const <ChatMessage>[];
      if (messageBefore != null) {
        final existingIds = state.messages
            .map((m) => m.messageId)
            .whereType<String>()
            .toSet();
        final existingFingerprints = state.messages
            .where((m) => m.messageId == null)
            .map((m) => '${m.role}:${m.timestamp}:${m.content}')
            .toSet();
        final fresh = loaded.where((m) {
          if (m.messageId != null) {
            return !existingIds.contains(m.messageId);
          }
          return !existingFingerprints.contains(
            '${m.role}:${m.timestamp}:${m.content}',
          );
        }).toList();
        final allMessages = [...fresh, ...state.messages];
        final fallbackOffset = state.messagesOffset - loaded.length;
        final newOffset =
            detail.messagesOffset ?? (fallbackOffset < 0 ? 0 : fallbackOffset);
        final persistedToolCalls =
            detail.toolCalls ?? const <PersistedToolCall>[];
        _lastPersistedToolCalls = persistedToolCalls;
        _recordPersistedMessageCount(detail.messageCount);
        final serverDerivedGroups = ToolCallGroup.groups(
          persistedToolCalls: persistedToolCalls,
          messages: allMessages,
          messageOffset: newOffset,
          coalesce: _coalesceTools,
        );
        final reanchoredExistingToolGroups = _reanchorGroupsToMessages(
          state.completedToolCallGroups,
          allMessages,
          messageOffset: newOffset,
        );
        final nextToolGroups = ToolCallGroup.merging(
          primaryGroups: serverDerivedGroups,
          fallbackGroups: reanchoredExistingToolGroups,
        );
        final serverDerivedReasoning = ReasoningGroup.groups(
          messages: allMessages,
          messageOffset: newOffset,
        );
        final reanchoredExistingReasoningGroups = _reanchorReasoningToMessages(
          state.completedReasoningGroups,
          allMessages,
          messageOffset: newOffset,
        );
        final nextReasoningGroups = ReasoningGroup.merging(
          primaryGroups: serverDerivedReasoning,
          fallbackGroups: reanchoredExistingReasoningGroups,
        );
        final bool exhausted = fresh.isEmpty;
        state = state.copyWith(
          messages: allMessages,
          messagesOffset: newOffset,
          hasOlderMessages:
              !exhausted &&
              detail.messageCount != null &&
              detail.messageCount! > state.messages.length + fresh.length,
          completedToolCallGroups: nextToolGroups,
          completedReasoningGroups: nextReasoningGroups,
        );
      } else {
        // 全量重载：diff-merge 调和本地与服务端消息
        // 若当前展示的是离线缓存回放数据，fresh 在线消息直接替换旧缓存
        final local = state.isViewingCachedData
            ? const <ChatMessage>[]
            : state.messages;
        final mergedMessages = diffMergeMessages(
          localMessages: local,
          serverMessages: loaded,
          liveStreamingMessageId: state.stream.streamingAssistantMessageId,
        );
        _applySessionDetail(detail: detail, mergedMessages: mergedMessages);
      }
    } on ApiException catch (error) {
      if (_disposed || gen != _generation) return;
      if (messageBefore == null && ApiException.shouldUseCache(error)) {
        List<Map<String, Object?>> cachedMaps = const [];
        try {
          cachedMaps = await ref
              .read(cacheServiceProvider)
              .readMessages(sessionId);
        } catch (_) {
          // 缓存读取异常静默，继续维持无缓存错误态
        }
        if (cachedMaps.isNotEmpty) {
          final parsed = cachedMaps
              .map((map) => ChatMessage.fromJson(map))
              .toList(growable: true);
          final hasTimestamps = parsed.any(
            (m) => m.timestamp != null && m.timestamp! > 0,
          );
          final List<ChatMessage> cachedMessages;
          if (hasTimestamps) {
            parsed.sort((a, b) {
              final tsA = a.timestamp ?? 0;
              final tsB = b.timestamp ?? 0;
              return tsA.compareTo(tsB);
            });
            cachedMessages = parsed;
          } else {
            // readMessages 按 cachedAt 倒序返回，反转恢复时间正序
            cachedMessages = parsed.reversed.toList(growable: false);
          }
          _lastPersistedToolCalls = const [];
          final serverDerivedGroups = ToolCallGroup.groups(
            persistedToolCalls: const [],
            messages: cachedMessages,
            messageOffset: 0,
            coalesce: _coalesceTools,
          );
          final serverDerivedReasoning = ReasoningGroup.groups(
            messages: cachedMessages,
            messageOffset: 0,
          );
          state = state.copyWith(
            messages: cachedMessages,
            completedToolCallGroups: serverDerivedGroups,
            completedReasoningGroups: serverDerivedReasoning,
            isViewingCachedData: true,
            isShowingOfflineCache: true,
            clearErrorMessage: true,
            clearSendErrorMessage: true,
          );
          return;
        }
      }
      // 无缓存或非网络类错误（401/业务错误）：保持现状错误态
      state = state.copyWith(errorMessage: error.message);
    }
  }

  void _applySessionDetail({
    required SessionDetail detail,
    required List<ChatMessage> mergedMessages,
  }) {
    // #147 家族：幽灵行退役。流已结束（无活跃流）时，客户端 `stream-` 临时行若其
    // 正文已被权威行覆盖，必须退场 —— 否则它作为独立一行再渲染一遍整轮正文，并把
    // 工具组锚点拖进「临时锚空间」（回前台后卡片锚到 raw:N，再刷新即漂到末条
    // assistant = 主人报的「回合末尾攒一张 tools 超多且位置错误的大卡」）。
    // 活跃流期间不改行为（#121 的 live 承接语义保持）。
    final effectiveMessages = state.stream.activeStreamId == null
        ? _retireStaleLiveRows(mergedMessages)
        : mergedMessages;
    final persistedToolCalls = detail.toolCalls ?? const <PersistedToolCall>[];
    _lastPersistedToolCalls = persistedToolCalls;
    _recordPersistedMessageCount(detail.messageCount);
    final newOffset = detail.messagesOffset ?? state.messagesOffset;
    final serverDerivedGroups = ToolCallGroup.groups(
      persistedToolCalls: persistedToolCalls,
      messages: effectiveMessages,
      messageOffset: newOffset,
      coalesce: _coalesceTools,
    );
    final serverDerivedReasoning = ReasoningGroup.groups(
      messages: effectiveMessages,
      messageOffset: newOffset,
    );
    List<ToolCallGroup> nextCompletedGroups;
    List<ToolCall> nextLiveToolCalls = state.liveToolCalls;
    final String nextLiveReasoning = state.liveReasoningText;
    final hasServerTools =
        persistedToolCalls.isNotEmpty || serverDerivedGroups.isNotEmpty;
    // live 活跃（有活跃流且未完成）时不得清空 liveToolCalls：live 时间线断点
    // （liveTimelinePoints，tools 段 start = liveToolCalls 下标）仍然保留，
    // 清空会导致后续切片全部 clamp 到空数组 → 工具行被吞、仅剩 think 行
    // （think 走 liveReasoningText 独立切片故不受影响）。收尾/done 后再归档。
    final isLiveActive =
        state.stream.activeStreamId != null &&
        !state.stream.hasCompletedResponse;

    final existingToolGroups = _reanchorGroupsToMessages(
      state.completedToolCallGroups,
      effectiveMessages,
      messageOffset: newOffset,
      oldStreamingId: state.stream.streamingAssistantMessageId,
    );
    final existingReasoningGroups = _reanchorReasoningToMessages(
      state.completedReasoningGroups,
      effectiveMessages,
      messageOffset: newOffset,
      oldStreamingId: state.stream.streamingAssistantMessageId,
    );

    if (hasServerTools) {
      // 服务端 transcript 已含工具 → 以服务端为准合并已有完成组保底；
      // 非 live 态才清空 live（历史/收尾路径），live 活跃时保留继续切片展示。
      nextCompletedGroups = ToolCallGroup.merging(
        primaryGroups: serverDerivedGroups,
        // live 派生的归档组（`live-tools-*`）在服务端已给出该回合工具真身时退场：
        // 整堆（一轮全部工具，`isAboveContent` 恒 false）一旦作为 fallback 参与
        // 合并，就会把别段的工具搬进同一张卡、并把卡位从「首条正文之上」降级到
        // 正文之下（#147 家族：位置错误 + tools 超多）。服务端未覆盖其工具时仍
        // 保留（防 transcript 窗口缺工具造成丢内容）。
        fallbackGroups: [
          for (final group in existingToolGroups)
            if (!_isStaleLiveGroupCoveredByServer(group, serverDerivedGroups))
              group,
        ],
      );
      nextLiveToolCalls = isLiveActive ? state.liveToolCalls : const [];
    } else {
      if (state.liveToolCalls.isNotEmpty) {
        final anchor = _resolveLiveArchiveAnchor(
          messages: effectiveMessages,
          messageOffset: newOffset,
          candidateId:
              state.stream.toolCallAnchorMessageId ??
              state.stream.streamingAssistantMessageId,
        );
        final liveGroup = ToolCallGroup.live(
          anchorMessageID: anchor,
          toolCalls: List<ToolCall>.of(state.liveToolCalls),
        );
        nextCompletedGroups = ToolCallGroup.merging(
          primaryGroups: existingToolGroups,
          fallbackGroups: [liveGroup],
        );
        // live 时间线需要保留 liveToolCalls 继续切片展示（重连/恢复场景）；
        // 归档组仅作流式结束后的 transcript fallback，不双显（transcript 会跳过
        // 流式消息自身）。
      } else {
        nextCompletedGroups = existingToolGroups;
      }
    }

    final liveReasoningList = <ReasoningGroup>[];
    if (state.liveReasoningText.isNotEmpty) {
      final anchor = _resolveLiveArchiveAnchor(
        messages: effectiveMessages,
        messageOffset: newOffset,
        candidateId:
            state.stream.reasoningAnchorMessageId ??
            state.stream.streamingAssistantMessageId,
      );
      liveReasoningList.add(
        ReasoningGroup(anchorMessageId: anchor, text: state.liveReasoningText),
      );
      // 同工具：保留 liveReasoningText 供 live 时间线切片，档案组仅收尾 fallback。
    }
    var nextCompletedReasoning = ReasoningGroup.merging(
      primaryGroups: serverDerivedReasoning,
      fallbackGroups: [...existingReasoningGroups, ...liveReasoningList],
    );
    // 历史思考归档：从已加载消息的 reasoning 字段提取，补入 completedReasoningGroups
    final persistedReasoning = _reasoningGroupsFromMessages(
      effectiveMessages,
      newOffset,
    );
    if (persistedReasoning.isNotEmpty) {
      final existingAnchors = nextCompletedReasoning
          .map((g) => '${g.anchorMessageId ?? ''}:${g.text}')
          .toSet();
      for (final g in persistedReasoning) {
        final key = '${g.anchorMessageId ?? ''}:${g.text}';
        if (!existingAnchors.contains(key)) {
          nextCompletedReasoning = [...nextCompletedReasoning, g];
        }
      }
    }

    nextCompletedGroups = _reanchorGroupsToMessages(
      nextCompletedGroups,
      effectiveMessages,
      messageOffset: newOffset,
      oldStreamingId: state.stream.streamingAssistantMessageId,
    );
    nextCompletedReasoning = _reanchorReasoningToMessages(
      nextCompletedReasoning,
      effectiveMessages,
      messageOffset: newOffset,
      oldStreamingId: state.stream.streamingAssistantMessageId,
    );

    state = state.copyWith(
      messages: effectiveMessages,
      messagesOffset: detail.messagesOffset ?? state.messagesOffset,
      hasOlderMessages:
          detail.messageCount != null &&
          detail.messageCount! > effectiveMessages.length,
      displayTitle: _resolveTitle(detail),
      workspace: detail.workspace ?? state.workspace,
      model: detail.model ?? state.model,
      modelProvider: detail.modelProvider ?? state.modelProvider,
      profile: detail.profile ?? state.profile,
      isReadOnly: detail.readOnly == true || detail.isReadOnly == true,
      hasPendingUserMessage:
          detail.pendingUserMessage?.trim().isNotEmpty == true ||
          detail.pendingAttachments?.isNotEmpty == true,
      parentSessionId: detail.parentSessionId,
      contextWindowSnapshot: ContextWindowSnapshot(
        contextLength: detail.contextLength,
        thresholdTokens: detail.thresholdTokens,
        lastPromptTokens: detail.lastPromptTokens,
        inputTokens: detail.inputTokens,
        outputTokens: detail.outputTokens,
        estimatedCost: detail.estimatedCost,
        tokensPerSecond:
            state.stream.liveTokensPerSecond ??
            state.contextWindowSnapshot?.tokensPerSecond,
      ),
      completedToolCallGroups: nextCompletedGroups,
      liveToolCalls: nextLiveToolCalls,
      completedReasoningGroups: nextCompletedReasoning,
      liveReasoningText: nextLiveReasoning,
      responseCompletionNeedsTranscriptRefresh: false,
      isViewingCachedData: false,
      isShowingOfflineCache: false,
    );
    unawaited(_writeCacheMessages(state.sessionId, effectiveMessages));
    final activeStreamId = detail.activeStreamId;
    if (activeStreamId != null &&
        activeStreamId.isNotEmpty &&
        state.stream.activeStreamId == null) {
      _lastContextPollTime = _now();
      state = state.copyWith(
        phase: ChatPhase.streaming,
        turnStartedMillis:
            state.turnStartedMillis ?? _now().millisecondsSinceEpoch,
        stream: state.stream.copyWith(activeStreamId: activeStreamId),
      );
      _syncSessionStreaming(
        state.sessionId,
        true,
        activeStreamId: activeStreamId,
      );
      unawaited(_reconnectIfNeeded());
    }
  }

  /// done 后补拉 transcript：status → active==false → loadMessages。
  Future<void> refreshTranscriptIfCompleted(String streamId) async {
    // 已开启新流则跳过；无流（已完成）或仍是旧流则继续。
    if (state.stream.activeStreamId != null &&
        state.stream.activeStreamId != streamId) {
      return;
    }
    final gen = _generation;
    try {
      final status = await _api!.chatStreamStatus(streamId);
      if (_disposed || gen != _generation) return;
      if (status.active == true) return; // 仍在流中，稍后再试
      await loadMessages();
      if (_disposed || gen != _generation) return;
      state = state.copyWith(responseCompletionNeedsTranscriptRefresh: false);
    } on ApiException {
      // 状态检查失败：静默（下次会话加载会补上）。
    }
  }

  /// 审批卡片作答。
  Future<bool> respondToApproval(String choice) async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return false;
    final gen = _generation;
    _markUserAction();
    try {
      await _api!.respondApproval(sessionId: sessionId, choice: choice);
      if (_disposed || gen != _generation) return false;
      _clearApprovalCard();
      // #127：等待态结束 → 接回推送通道（见 _resumeChannelsAfterPromptResolved）。
      _resumeChannelsAfterPromptResolved();
      return true;
    } on ApiException {
      if (_disposed || gen != _generation) return false;
      return false;
    }
  }

  /// 澄清卡片作答。
  Future<bool> respondToClarification(String response) async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return false;
    final gen = _generation;
    _markUserAction();
    try {
      await _api!.respondClarification(
        sessionId: sessionId,
        response: response,
      );
      if (_disposed || gen != _generation) return false;
      _clearClarificationCard();
      // #127：等待态结束 → 接回推送通道（见 _resumeChannelsAfterPromptResolved）。
      _resumeChannelsAfterPromptResolved();
      return true;
    } on ApiException {
      if (_disposed || gen != _generation) return false;
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // 发送内部实现
  // -------------------------------------------------------------------------

  Future<bool> _sendMessage(
    String text, {
    List<PendingAttachment> attachments = const [],
  }) async {
    final api = _api;
    if (api == null) return false;
    _markUserAction();
    _archiveLiveReasoningIfNeeded();
    _archiveLiveToolCallsIfNeeded();
    final messageId = 'local-${uuidV4()}';
    final optimistic = ChatMessage(
      role: 'user',
      content: text,
      messageId: messageId,
      timestamp: _nowSeconds(),
      // 乐观消息直接带附件元数据：发送后立即可见附件卡片（对齐 WebUI 回显行为，
      // 服务端重放后由 attachments/文本标记再次兜底）。
      attachments: attachments.isEmpty
          ? null
          : [
              for (final a in attachments)
                MessageAttachment(
                  name: a.name,
                  path: a.path,
                  mime: a.mime,
                  size: a.size,
                  isImage: a.isImage,
                ),
            ],
    );
    _malformedDoneStreak = 0;
    state = state.copyWith(
      phase: ChatPhase.sending,
      messages: [...state.messages, optimistic],
      clearSendErrorMessage: true,
      clearErrorMessage: true,
      clearPrefillStatus: true,
      clearPrefillLabel: true,
      turnStartedMillis: _now().millisecondsSinceEpoch,
    );
    // #120：回合开始即上报「思考中」——岛在发送瞬间就出现，不等首个 SSE 事件。
    _reportLiveActivity(ChatLiveActivity.thinking, force: true);
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat',
      message:
          'Message sending initiated (phase: sending, session: ${state.sessionId})',
    );
    final gen = ++_generation;
    try {
      final response = await api.startChat(
        sessionId: state.sessionId,
        message: text,
        workspace: state.workspace,
        model: state.model,
        modelProvider: state.modelProvider,
        profile: state.profile,
        explicitModelPick: state.explicitModelPick,
        attachments: attachments.isEmpty
            ? null
            : [
                for (final a in attachments)
                  a.toJsonValue().toJson() as Map<String, Object?>,
              ],
      );
      if (_disposed || gen != _generation) return false;
      final streamId = response.streamId;
      final sessionId = response.sessionId;
      if (streamId == null || streamId.isEmpty) {
        _rollbackOptimisticMessage(messageId);
        state = state.copyWith(
          phase: ChatPhase.idle,
          sendErrorMessage: response.error ?? '服务器未返回流 ID，发送失败。',
          clearTurnStartedMillis: true,
        );
        return false;
      }
      if (sessionId != null &&
          sessionId.isNotEmpty &&
          state.sessionId.isEmpty) {
        final newSessionId = sessionId;
        state = state.copyWith(sessionId: newSessionId);
        _onNewSessionCreated(newSessionId, text);
        _startClarifyChannel(newSessionId);
        _startApprovalChannel(newSessionId);
        _startSessionContentChannel(newSessionId);
      }
      _beginStream(streamId);
      return true;
    } on ApiException catch (error) {
      if (_disposed || gen != _generation) return false;
      if (error is HttpException && error.indicatesActiveStream) {
        // 409 已有活动流：服务端未接受本条消息 → 回滚 → 接管已有流。
        _rollbackOptimisticMessage(messageId);
        await _recoverExistingStream(error.activeStreamId!);
        return false;
      }
      _rollbackOptimisticMessage(messageId);
      state = state.copyWith(
        phase: ChatPhase.idle,
        sendErrorMessage: error.message,
        clearTurnStartedMillis: true,
      );
      return false;
    }
  }

  /// 流式期间发送：steer / interrupt / queue 三行为（chat_spec.md §4.2）。
  Future<bool> _submitStreamingMessage(
    String text,
    StreamingSendBehavior behavior,
  ) async {
    switch (behavior) {
      case StreamingSendBehavior.steer:
        return _steer(text);
      case StreamingSendBehavior.interrupt:
        state = state.copyWith(
          queuedSlashMessages: [text, ...state.queuedSlashMessages],
        );
        final stopped = await stop();
        if (!stopped && state.stream.activeStreamId != null) {
          _pinNotice(
            'Could not stop the current response — your message is queued for the next turn.',
          );
        }
        return false;
      case StreamingSendBehavior.queue:
        state = state.copyWith(
          queuedSlashMessages: [...state.queuedSlashMessages, text],
        );
        _pinNotice(
          'Queued for next turn (#${state.queuedSlashMessages.length})',
        );
        return false;
    }
  }

  Future<bool> _steer(String text) async {
    final gen = _generation;
    try {
      final response = await _api!.steerChat(
        sessionId: state.sessionId,
        text: text,
      );
      if (_disposed || gen != _generation) return false;
      if (response.accepted == true) {
        _markProgress();
        state = state.copyWith(
          phase: ChatPhase.steered,
          steerHints: [...state.steerHints, text],
        );
        return true;
      }
      _queueSteerFailure(text);
      unawaited(cancelActiveStream());
      return false;
    } on ApiException {
      if (_disposed || gen != _generation) return false;
      _queueSteerFailure(text);
      unawaited(cancelActiveStream());
      return false;
    }
  }

  void _queueSteerFailure(String text) {
    state = state.copyWith(
      queuedSlashMessages: [...state.queuedSlashMessages, text],
      pinnedLocalNotices: [
        ...state.pinnedLocalNotices,
        'Steer was unavailable — your message has been queued for the next turn.',
      ],
    );
  }

  /// 停止当前流（steer 失败路径；finishStream 会顺次发送队列）。
  Future<void> cancelActiveStream() async {
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return;
    await _api?.cancelChat(streamId);
    if (_disposed) return;
    _notifySessionError('响应已取消', state.displayTitle);
    _finishStream(endPhase: ChatPhase.cancelled);
  }

  /// 流结束后顺次发送队列首条（发送失败回队首并停止连锁，防死循环）。
  Future<void> _drainQueuedSlashMessage() async {
    final queued = state.queuedSlashMessages;
    if (queued.isEmpty) return;
    if (state.stream.activeStreamId != null) return;
    final next = queued.first;
    state = state.copyWith(queuedSlashMessages: queued.sublist(1));
    final sent = await _sendMessage(next);
    if (!sent) {
      state = state.copyWith(
        queuedSlashMessages: [next, ...state.queuedSlashMessages],
      );
    }
  }

  void _beginStream(String streamId) {
    _timelineSequence = 0;
    _replayRebuildTimeline = false;
    _prefillSince = null;
    state = state.copyWith(
      phase: ChatPhase.streaming,
      clearSendErrorMessage: true,
      clearErrorMessage: true,
      clearPrefillStatus: true,
      clearPrefillLabel: true,
      liveTimelinePoints: const [],
      turnStartedMillis:
          state.turnStartedMillis ?? _now().millisecondsSinceEpoch,
      stream: state.stream.copyWith(
        activeStreamId: streamId,
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
        hasCompletedResponse: false,
        isCancelling: false,
        clearLastEventId: true,
        isReplayConnection: false,
        matchedPrefixLength: 0,
        matchedReasoningLength: 0,
        replayToolMatchIndex: 0,
        replayAfterSeq: 0,
      ),
      pendingAction: const ChatPendingActionState(),
      responseCompletionNeedsTranscriptRefresh: false,
    );
    // 空流式气泡立即锚定（思考中指示器依赖它）。
    _ensureStreamingAssistantMessage();
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat',
      message:
          'Stream started (phase: streaming, streamId: $streamId, session: ${state.sessionId})',
    );
    _syncSessionStreaming(
      state.sessionId,
      true,
      activeStreamId: streamId,
      verifyInBackground: true,
    );
    _connectStream(streamId);
    _lastContextPollTime = _now();
    _markProgress();
    _recordTransportActivity();
  }

  /// 建立 SSE 连接。replayAfterSeq → `?replay=1&after_seq=N`（保留 lastEventID）；
  /// [fullReconnect] → 不带 replay 参数但从 0 重放（靠 §6.4 去重）。
  void _connectStream(
    String streamId, {
    int? replayAfterSeq,
    bool fullReconnect = false,
  }) {
    final api = _api;
    if (api == null) return;
    if (_streamConnected || replayAfterSeq != null || fullReconnect) {
      api.stopStream();
      _streamConnected = false;
    }
    final useReplay = replayAfterSeq != null || fullReconnect;
    final effectiveReplayAfterSeq =
        replayAfterSeq ??
        (fullReconnect ? _replayAfterSeq(state.stream.lastEventId) : 0);
    state = state.copyWith(
      // 旧时间线断点保留（见 _replayRebuildTimeline 语义）：重放帧对已展示
      // 内容不再向尾部叠加重复断点，成簇卡片的放大源被切断。
      stream: state.stream.copyWith(
        isReplayConnection: useReplay,
        matchedPrefixLength: 0,
        matchedReasoningLength: 0,
        replayToolMatchIndex: 0,
        replayAfterSeq: effectiveReplayAfterSeq,
        clearLastEventId: true,
      ),
    );
    // 重放是否需要逐帧重建时间线：仅「断点为空的恢复场景」（如重启后 resume，
    // 断点丢失但内容已在服务端占位行中）需要；正常 live 重连时断点仍在，
    // 重放帧全命中时若再补点，会把已展示段重复叠加到时间线尾部（卡簇）。
    // 工具断点依赖 _appendToolCall 正常路径，此处旗标只约束 text/think 补点。
    _replayRebuildTimeline = useReplay && state.liveTimelinePoints.isEmpty;
    _streamConnected = true;
    unawaited(
      api.startStream(
        streamId,
        replayAfterSeq: replayAfterSeq,
        onEvent: _handleSseEvent,
        onEventId: (id) {
          if (_disposed) return;
          _resetReconnectBackoff();
          state = state.copyWith(
            stream: state.stream.copyWith(lastEventId: id),
          );
          _recordTransportActivity();
        },
        onTransportError: (message) {
          if (_disposed) return;
          _streamConnected = false;
          _handleTransportError(message);
        },
        onClosed: () {
          _streamConnected = false;
          _recordTransportActivity();
          // #100 F4：非完成态下传输关闭不应留下 recovery 闩锁（checking/
          // reconnecting 挂起会封死 resume 主动探活入口），复位回 idle。
          if (!state.stream.hasCompletedResponse &&
              state.stream.activeStreamId != null &&
              state.stream.recovery != ActiveStreamRecoveryState.reconnecting &&
              state.stream.recovery != ActiveStreamRecoveryState.idle) {
            state = state.copyWith(
              stream: state.stream.copyWith(
                recovery: ActiveStreamRecoveryState.idle,
              ),
            );
          }
          if (!state.stream.hasCompletedResponse &&
              state.stream.activeStreamId != null &&
              state.stream.recovery == ActiveStreamRecoveryState.idle &&
              (_reconnectTimer == null || !_reconnectTimer!.isActive) &&
              _resumeProbeRetryTimer == null) {
            unawaited(
              _checkStatusAndReconnect(
                resumeRetries: _watchdogConfig.resumeProbeRetries,
              ),
            );
          }
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SSE 事件分发（同步串行；先记录传输活动，有新增再 markProgress）
  // -------------------------------------------------------------------------

  void _handleSseEvent(SseEvent event) {
    if (_disposed) return;
    _recordTransportActivity();
    _resetReconnectBackoff();
    final stream = state.stream;
    if (stream.isReplayConnection && stream.replayAfterSeq > 0) {
      final currentSeq = _replayAfterSeq(stream.lastEventId);
      if (currentSeq > 0 && currentSeq <= stream.replayAfterSeq) {
        // 重连回放帧：seq <= replayAfterSeq 说明断线前已处理过，
        // 幂等忽略内容帧（token / interim / reasoning / tool / steer），
        // 避免重复推流和 UI 闪动。心跳与终结事件仍正常分发。
        switch (event) {
          case TokenSseEvent() ||
              InterimAssistantSseEvent() ||
              ReasoningSseEvent() ||
              ToolStartedSseEvent() ||
              ToolCompletedSseEvent() ||
              PendingSteerLeftoverSseEvent():
            return;
          default:
            break;
        }
      }
    }
    switch (event) {
      case TokenSseEvent(:final text):
        if (_appendAssistantToken(text)) _markProgress();
        _reportLiveActivity(ChatLiveActivity.output);
      case InterimAssistantSseEvent(:final text, :final alreadyStreamed):
        _handleInterimAssistant(text, alreadyStreamed);
      case ReasoningSseEvent(:final text):
        if (_appendReasoning(text)) _markProgress();
        _reportLiveActivity(ChatLiveActivity.thinking);
      case ToolStartedSseEvent(:final event):
        _appendToolCall(event);
        _reportLiveActivity(ChatLiveActivity.tool, detail: event.name ?? '');
      case ToolCompletedSseEvent(:final event):
        _completeToolCall(event);
        // 工具完成 → 回到推理（下一段可能是新工具或正文）。
        _reportLiveActivity(ChatLiveActivity.thinking);
      case TitleSseEvent(:final sessionId, :final title):
        _handleTitle(sessionId, title);
      case MeteringSseEvent(
        :final tps,
        :final tpsAvailable,
        :final estimated,
        :final sessionId,
      ):
        _handleMetering(
          tps: tps,
          tpsAvailable: tpsAvailable,
          estimated: estimated,
          sessionId: sessionId,
        );
      case DoneSseEvent(:final event):
        _applyDone(event);
        _reportTurnSettled();
      case ContextStatusSseEvent(:final status, :final label):
        _handleContextStatus(status, label);
      case ApprovalPendingSseEvent(:final payload):
        _applyApprovalUpdate(payload);
        // #120：等待批准——主人离开时最需要被叫回的状态。
        _reportLiveActivity(ChatLiveActivity.waitingApproval);
      case ClarificationPendingSseEvent(:final payload):
        _applyClarificationUpdate(payload);
        // #120：等待回复——主人离开时最需要被叫回的状态。
        _reportLiveActivity(ChatLiveActivity.waitingReply);
      case PendingSteerLeftoverSseEvent(:final text):
        _handlePendingSteerLeftover(text);
      case StreamEndSseEvent():
        _handleStreamEnd();
        _reportTurnSettled();
      case CancelledSseEvent():
        _handleCancelled();
        // #129：中断语义（岛上 chip「已中断」），不是「已完成」。
        _reportTurnSettled(interrupted: true);
      case ErrorSseEvent(:final message):
        _handleErrorEvent(message);
        // #129：异常中断 → 岛上 chip「已中断」。
        _reportTurnSettled(interrupted: true);
      case TransportErrorSseEvent(:final message):
        _handleTransportError(message);
      case MalformedDoneSseEvent(:final message):
        // #155：done 是终结帧 —— 载荷没吃全 ≠ 回合没结束。按「收尾」处理，
        // 不进传输错误的回放/重连链（详见 _handleMalformedDone）。
        unawaited(_handleMalformedDone(message));
      case HeartbeatSseEvent():
        _handleHeartbeat();
      case IgnoredSseEvent():
        break;
    }
  }

  // -------------------------------------------------------------------------
  // token 三段式缓冲（合并 → 词级 reveal）
  // -------------------------------------------------------------------------

  /// 去重（replay 连接）→ 入 pendingAssistantTokenChunks → 调度 16ms 合并。
  /// 返回是否有真实新增（看门狗进度信号）。
  bool _appendAssistantToken(String text) {
    if (text.isEmpty) return false;
    var remainder = text;
    final stream = state.stream;
    if (stream.isReplayConnection) {
      // 打点前记录匹配游标：重放帧即使全命中（remainder 空），也要用它
      // 重建 text 段断点（该帧在最终 content 中的起点）。
      final prevCursor = stream.matchedPrefixLength;
      final deduped = deduplicatedReplayToken(
        token: text,
        existingContent: _currentStreamingContent(),
        matchedPrefixLength: stream.matchedPrefixLength,
      );
      remainder = deduped.remainder;
      state = state.copyWith(
        stream: state.stream.copyWith(
          matchedPrefixLength: deduped.newCursor,
          isReplayConnection: deduped.stillReplay,
        ),
      );
      if (remainder.isEmpty) {
        // 重放帧（fullReconnect 从 0 重放）文本全部命中断线前已 flush 的内容：
        // 内容不再追加。断点补建仅在「断点为空的恢复场景」（
        // _replayRebuildTimeline）执行，避免时间线为空 + 归档锚定 →
        // liveTimeline=null → 旧分组式气泡沉底；正常 live 重连断点仍在，
        // 此时补点会把已展示段重复叠加到时间线尾部（成簇卡片）。
        // #147：与主路径同一条「内容性」判据 —— 纯空白重放帧同样不建点，
        // 保证「存在 text 断点 ⇒ 内容性正文到达过」这条不变量无例外。
        if (_replayRebuildTimeline && text.trim().isNotEmpty) {
          _ensureTimelinePoint(
            LiveSegmentKind.text,
            prevCursor,
            contentful: true,
          );
        }
        return false;
      }
    }
    // 时间线断点：在「事件到达」时记录（而非 flush 时），保证与真实事件顺序一致；
    // start 取缓冲全量（content + 待合并 + 待揭示），使切片与最终 content 对齐。
    //
    // #147：纯空白正文（'\n\n' / 空格 token）**不建断点**。「是否内容性正文」必须
    // 在事件到达时判定 —— 此刻 token 文本就在手上；若把它留给渲染端按「已 reveal
    // 的 content」去猜，则 reveal 滞后（后台冻结 / 回前台重放补课 / 打字机落后）期间
    // 内容性正文会被 clamp 成空段，渲染端据此拒绝切卡 ⇒ 相邻工具挤成一张大卡。
    // 不建点的效果与 #62 一致：空白不构成分隔符，相邻工具仍并一张卡。
    if (remainder.trim().isNotEmpty) {
      _ensureTimelinePoint(
        LiveSegmentKind.text,
        _currentStreamingContent().length,
        contentful: true,
      );
    }
    state = state.copyWith(
      pendingAssistantTokenChunks: [
        ...state.pendingAssistantTokenChunks,
        remainder,
      ],
    );
    if (_resumedAt != null) {
      final elapsed = _now().difference(_resumedAt!);
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat_resume',
        message:
            'First token received after resume in ${elapsed.inMilliseconds}ms',
      );
      _resumedAt = null;
    }
    _scheduleMerge();
    return true;
  }

  /// 生命周期变化处理（修复①背景/锁屏暂停消费 + 修复③watchdog 基线校准）。
  ///
  /// - 移动端（Android/iOS）：非 resumed（后台/锁屏/隐藏）暂停 16ms 合并与
  ///   逐词 reveal 消费，避免后台空转 CPU 与解锁后积压爆吐。
  /// - 桌面端（Windows/macOS/Linux）：引擎语义是「窗口失焦→inactive、
  ///   最小化/隐藏→hidden」（windows_lifecycle_manager UpdateState）。失焦窗口
  ///   仍然完整可见，冻结 reveal 会让打字机在用户眼前停摆、回焦再整段爆铺并
  ///   诱发 resume 探活重放叠影——因此仅 hidden/detached（真不可见）才暂停，
  ///   inactive 照常流式消费。
  /// - resumed：先直接铺全文（积压缓冲一次性落消息），再重新校准看门狗基线，
  ///   避免锁屏冻结计时器在解锁瞬间被误判为断线超时触发重连。
  void _handleAppLifecycleChange(
    AppLifecycleState? previous,
    AppLifecycleState next,
  ) {
    final bool nowPaused;
    if (isDesktopPlatform()) {
      nowPaused =
          next == AppLifecycleState.hidden ||
          next == AppLifecycleState.detached;
    } else {
      nowPaused = next != AppLifecycleState.resumed;
    }
    if (nowPaused == _appPaused) {
      if (next == AppLifecycleState.resumed) {
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.info,
          tag: 'chat_resume',
          message:
              'believed-state early-return reconcile (session: ${state.sessionId})',
        );
        _reconnectAttempts = 0;
        _cancelReconnectTimer();
        _cancelResumeProbeRetry();
        _resetFullReconnectThrottle();
        _statusCheckCooldownUntil = null;
      }
      return;
    }
    _appPaused = nowPaused;
    if (nowPaused) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat',
        message:
            'App lifecycle paused/hidden: reveal & merge consumption paused',
      );
      _mergeTimer?.cancel();
      _mergeTimer = null;
      _revealTimer?.cancel();
      _revealTimer = null;
      try {
        final keepalive = ref.read(backgroundKeepaliveServiceProvider);
        final notifSettings = ref.read(notificationSettingsProvider);
        final isStreaming =
            state.stream.activeStreamId != null ||
            state.phase == ChatPhase.streaming ||
            state.phase == ChatPhase.steered ||
            state.phase == ChatPhase.sending;
        unawaited(
          keepalive.onAppLifecycleChanged(
            state: next,
            activeSessionId: state.sessionId,
            activeStreamId: state.stream.activeStreamId,
            isStreaming: isStreaming,
            foregroundServiceEnabled: notifSettings.bgForegroundServiceEnabled,
          ),
        );
      } catch (_) {}
      // #120 / #124：退后台/锁屏立刻上报一次当前活动，使实况通知（灵动岛）即时出现
      // ——不再依赖会话列表刷新（后台期间列表轮询与 SSE 均已停）。收尾后 phase
      // 可能已回 idle，但卡片仍在等主人，此时切后台也必须能上岛。
      if (_hasActiveTurn || state.pendingAction.hasPendingPrompt) {
        _reportLiveActivity(_inferLiveActivity(), force: true);
      }
      return;
    }
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat',
      message:
          'App lifecycle resumed: flushing pending text + watchdog rebaseline',
    );
    try {
      final keepalive = ref.read(backgroundKeepaliveServiceProvider);
      unawaited(
        keepalive.stopForegroundService()
        // 停止失败仅诊断日志（K 修复规格：仅开关路径需回滚，见
        // setBgForegroundServiceEnabled）；fire-and-forget 调用自吞。
        .catchError((Object _) {}),
      );
      if (state.sessionId.isNotEmpty) {
        unawaited(keepalive.cancelOneOffPoll(state.sessionId));
      }
    } catch (_) {}
    // #100 F1 / #142 B2：解锁/回前台 = 人类在场 → 无条件重置恢复状态，
    // 拆掉「预算烧尽 + recovery 闩锁」死锁：重连预算归零、退避/探活重试定时器清除、
    // recovery 非 idle 强制复位（resume 主动探活只认 idle，不复位则永久跳过）。
    _reconnectAttempts = 0;
    _cancelReconnectTimer();
    _cancelResumeProbeRetry();
    _resetFullReconnectThrottle();
    final recovery = state.stream.recovery;
    if (recovery == ActiveStreamRecoveryState.checking ||
        recovery == ActiveStreamRecoveryState.reconnecting) {
      state = state.copyWith(
        stream: state.stream.copyWith(recovery: ActiveStreamRecoveryState.idle),
      );
    }
    // #29 后台恢复主动探测：重基线前捕获「后台空窗」——后台冻结点到 resumed
    // 时刻的传输停滞时长（SSE 后台静默断线无 onTransportError/onClosed 事件，
    // 只能靠时间差识别，`_lastTransportActivity` 即断线状态快照）。
    final lastActivity = _lastTransportActivity;
    final transportGap = lastActivity == null
        ? Duration.zero
        : _now().difference(lastActivity);
    // 直接铺全文：先入队（queue）的文本在前、pending 在后，保持到达顺序。
    _flushPendingRevealToFullText();
    _startRevealTimerIfNeeded();
    // 看门狗基线重新校准：锁屏冻结期间的时间差不参与超时判定。
    _lastProgress = _now();
    _lastTransportActivity = _now();
    _statusCheckCooldownUntil = null;
    final stream = state.stream;
    final isStreamingActive =
        stream.activeStreamId != null &&
        !stream.hasCompletedResponse &&
        !state.pendingAction.hasPendingPrompt;
    if (isStreamingActive) {
      _resumedAt = _now();
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat_resume',
        message:
            'App lifecycle resumed (transportGap: ${transportGap.inMilliseconds}ms, streamId: ${stream.activeStreamId})',
      );
    }
    // resume 立即主动查 stream status（不等 watchdog 12s 阈值）：
    // 空窗达到阈值（生产环境 gap >= 2s，测试 override 时取其较小值）且 recovery == idle 时立即探测，
    // 弱网/后台空窗目标 resume→首个新字 ≤3s；死流/超时立即重连或补差，健康流 loadMessages
    // 顺带把后台期间新内容落地——「切回立即呈现最新状态」。
    final resumeProbeThreshold =
        _watchdogConfig.transportStaleThreshold < const Duration(seconds: 2)
        ? _watchdogConfig.transportStaleThreshold
        : const Duration(seconds: 2);
    if (isStreamingActive &&
        stream.recovery == ActiveStreamRecoveryState.idle &&
        transportGap >= resumeProbeThreshold) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat_resume',
        message:
            'Resume active-probe triggered (transportGap: ${transportGap.inMilliseconds}ms, streamId: ${stream.activeStreamId})',
      );
      unawaited(
        _checkStatusAndReconnect(
          resumeRetries: _watchdogConfig.resumeProbeRetries,
        ),
      );
    }
    // #142 B3：若检测到死区特征立即调用一次死区恢复（不等 watchdog 15s 阈值）
    final isDeadZone =
        state.stream.activeStreamId == null &&
        _phaseIndicatesOngoingTurn &&
        !state.pendingAction.hasPendingPrompt;
    if (isDeadZone) {
      _recoverOrphanedStreamingPhaseIfNeeded(ignoreStallThreshold: true);
    }
  }

  /// 把 merge/reveal 积压一次性写入消息（保持时间顺序：queue 先、pending 后）。
  void _flushPendingRevealToFullText() {
    _mergeTimer?.cancel();
    _mergeTimer = null;
    _revealTimer?.cancel();
    _revealTimer = null;
    final text = _revealQueue.join() + state.pendingAssistantTokenChunks.join();
    _revealQueue.clear();
    _revealQueueStart = null;
    state = state.copyWith(
      pendingAssistantTokenChunks: const [],
      isRevealQueueEmpty: true,
    );
    if (text.isNotEmpty) {
      _appendToStreamingMessage(text);
    }
  }

  void _scheduleMerge() {
    if (_appPaused) return; // 后台/锁屏不调度合并（resumed 统一铺全文）
    _mergeTimer ??= Timer(mergeDelay, () {
      _mergeTimer = null;
      _mergePendingTokens();
    });
  }

  void _mergePendingTokens() {
    final chunks = state.pendingAssistantTokenChunks;
    if (chunks.isNotEmpty) {
      final text = chunks.join();
      if (!_smoothStreaming) {
        state = state.copyWith(
          pendingAssistantTokenChunks: const [],
          isRevealQueueEmpty: true,
        );
        if (text.isNotEmpty) {
          _appendToStreamingMessage(text);
          _markProgress();
        }
      } else {
        final units = splitIntoWordUnits(
          text,
          cjkChunkSize: _smoothStreamingSpeed.cjkChunkSize,
        );
        _revealQueue.addAll(units);
        if (_revealQueue.length > maxRevealQueueUnits) {
          // 修复②队列硬上限：积压超过阈值直接落全文（一次铺完不再逐词），
          // 防止后台/锁屏期间无上限积压导致解锁后爆吐 + 卡死。
          final overflow = _revealQueue.join();
          _revealQueue.clear();
          _revealQueueStart = null;
          state = state.copyWith(
            pendingAssistantTokenChunks: const [],
            isRevealQueueEmpty: true,
          );
          if (overflow.isNotEmpty) {
            _appendToStreamingMessage(overflow);
            _markProgress();
          }
        } else {
          _revealQueueStart ??= _now();
          state = state.copyWith(
            pendingAssistantTokenChunks: const [],
            isRevealQueueEmpty: _revealQueue.isEmpty,
          );
          _startRevealTimerIfNeeded();
        }
      }
    }
    // 同一 tick 内 token 先、reasoning 后。
    _flushReasoningChunks();
  }

  void _startRevealTimerIfNeeded() {
    if (_appPaused) return; // 后台/锁屏不启动逐词消费
    if (_revealTimer != null) return;
    _revealTimer = Timer.periodic(
      _smoothStreamingSpeed.revealInterval,
      (_) => _drainReveal(),
    );
  }

  /// 根据积压量与档位配置计算每 tick reveal 词单元数。
  ///
  /// - 慢档（1-3 档）：固定每 tick 单元数，不随积压自适应加速。
  /// - 快档（4-5 档）：保留自适应加速（base=档位单元数，上限 32）。
  @visibleForTesting
  static int adaptiveWordUnitsPerTick(
    int backlog, [
    SmoothStreamingSpeedPreset speed = SmoothStreamingSpeedPreset.standard,
  ]) {
    if (backlog <= 0) return 0;
    if (!speed.isAdaptive) {
      return backlog < speed.wordUnitsPerTick
          ? backlog
          : speed.wordUnitsPerTick;
    }
    if (backlog < speed.wordUnitsPerTick) return backlog;
    if (backlog <= 8) return speed.wordUnitsPerTick;
    // backlog >= 9 时平滑递增，积压越多消耗越快，上限 32
    return (speed.wordUnitsPerTick + (backlog - 8) ~/ 12).clamp(
      speed.wordUnitsPerTick,
      32,
    );
  }

  void _drainReveal() {
    if (_appPaused) return; // 后台/锁屏暂停逐词消费（resumed 统一铺全文）
    if (!_smoothStreaming) {
      _flushPendingRevealToFullText();
      return;
    }
    if (_revealQueue.isEmpty) {
      _revealTimer?.cancel();
      _revealTimer = null;
      _revealQueueStart = null;
      if (!state.isRevealQueueEmpty) {
        state = state.copyWith(isRevealQueueEmpty: true);
      }
      return;
    }
    final speed = _smoothStreamingSpeed;
    final count = adaptiveWordUnitsPerTick(_revealQueue.length, speed);
    final effectiveCount = count < _revealQueue.length
        ? count
        : _revealQueue.length;
    final units = _revealQueue.sublist(0, effectiveCount);
    _revealQueue.removeRange(0, effectiveCount);
    _appendToStreamingMessage(
      units.join(),
      isRevealQueueEmpty: _revealQueue.isEmpty,
    );
    _markProgress();
    // 最大滞后：积压超过档位时限一次性排空。
    final start = _revealQueueStart;
    if (_revealQueue.isNotEmpty &&
        start != null &&
        _now().difference(start) >= speed.maxRevealLag) {
      final rest = _revealQueue.join();
      _revealQueue.clear();
      _revealQueueStart = null;
      _appendToStreamingMessage(rest, isRevealQueueEmpty: true);
      _markProgress();
    }
  }

  /// 完成路径全量 flush：取消待定 tick，把缓冲全部写入消息。
  void flushPendingStreamingContent() {
    _mergeTimer?.cancel();
    _mergeTimer = null;
    _revealTimer?.cancel();
    _revealTimer = null;
    final text = state.pendingAssistantTokenChunks.join() + _revealQueue.join();
    _revealQueue.clear();
    _revealQueueStart = null;
    if (text.isNotEmpty) {
      state = state.copyWith(
        pendingAssistantTokenChunks: const [],
        isRevealQueueEmpty: true,
      );
      _appendToStreamingMessage(text);
    } else {
      state = state.copyWith(isRevealQueueEmpty: true);
    }
    _flushReasoningChunks();
  }

  void _flushReasoningChunks() {
    final chunks = state.pendingReasoningChunks;
    if (chunks.isEmpty) return;
    final text = chunks.join();
    state = state.copyWith(
      pendingReasoningChunks: const [],
      liveReasoningText: state.liveReasoningText + text,
    );
  }

  String _currentReasoningContent() {
    var base = state.liveReasoningText;
    if (state.pendingReasoningChunks.isNotEmpty) {
      base += state.pendingReasoningChunks.join();
    }
    return base;
  }

  /// reasoning：去重 → 入 pendingReasoningChunks → 合并 tick 整块 flush。
  bool _appendReasoning(String text) {
    if (text.isEmpty) return false;
    var remainder = text;
    final stream = state.stream;
    if (stream.isReplayConnection) {
      // 打点前记录匹配游标：重放帧全命中（remainder 空）时用它重建
      // thinking 段断点（该帧在最终 reasoning 文本中的起点）。
      final prevCursor = stream.matchedReasoningLength;
      final deduped = deduplicatedReplayText(
        text: text,
        existingContent: _currentReasoningContent(),
        matchedLength: stream.matchedReasoningLength,
      );
      remainder = deduped.remainder;
      state = state.copyWith(
        stream: state.stream.copyWith(
          matchedReasoningLength: deduped.newCursor,
          isReplayConnection: deduped.stillReplay,
        ),
      );
      if (remainder.isEmpty) {
        // same 重放帧：内容命中已有思考。断点补建仅在「断点为空的恢复场景」
        // （_replayRebuildTimeline）执行，避免时间线为空导致时间线回退；
        // 正常 live 重连断点仍在，补点会把已展示思考段叠加到时间线尾部
        // （底部连续思考卡簇的放大源）。
        if (_replayRebuildTimeline) {
          _ensureTimelinePoint(LiveSegmentKind.thinking, prevCursor);
        }
        return false;
      }
    }
    // 与工具事件一致：reasoning 先到时也立即锚定空流式气泡（思考中指示器兜底）。
    _ensureStreamingAssistantMessage();
    // 时间线断点：事件到达时记录（对齐真实顺序）；start 含待 flush 块长度。
    final start = _currentReasoningContent().length;
    _ensureTimelinePoint(LiveSegmentKind.thinking, start);
    state = state.copyWith(
      pendingReasoningChunks: [...state.pendingReasoningChunks, remainder],
    );
    _scheduleMerge();
    return true;
  }

  // -------------------------------------------------------------------------
  // 消息组装
  // -------------------------------------------------------------------------

  /// 流式 assistant 消息锚定：不存在则创建并记住 ID。
  void _ensureStreamingAssistantMessage() {
    if (state.stream.streamingAssistantMessageId != null) return;
    final message = ChatMessage(
      role: 'assistant',
      content: '',
      messageId: 'stream-${uuidV4()}',
      timestamp: _nowSeconds(),
    );
    state = state.copyWith(
      messages: [...state.messages, message],
      stream: state.stream.copyWith(
        streamingAssistantMessageId: message.messageId,
      ),
    );
  }

  /// 时间线断点：段切换时追加（同 kind 连续追加并入同段，不重复建点）。
  ///
  /// 断点按 SSE 事件到达顺序记录；[start] 为该段缓冲起始游标，渲染层据此
  /// 对 content / liveReasoningText / liveToolCalls 切片穿插展示。
  ///
  /// [contentful]：text 断点专用 —— 建立时「到达的是内容性正文」（#147）。
  /// 调用方在 token 文本就在手上时置位；空白 token 一律不建点，故 controller
  /// 建的 text 断点恒为 true，渲染层因此可以**脱离 reveal 进度**切卡。
  void _ensureTimelinePoint(
    LiveSegmentKind kind,
    int start, {
    bool contentful = false,
  }) {
    final points = state.liveTimelinePoints;
    if (points.isNotEmpty && points.last.kind == kind) return;
    state = state.copyWith(
      liveTimelinePoints: [
        ...points,
        LiveTimelinePoint(
          kind: kind,
          start: start,
          sequence: ++_timelineSequence,
          contentful: contentful,
        ),
      ],
    );
  }

  /// 以 messageId == streamingAssistantMessageId 定位，原地替换（content 追加）。
  ///
  /// [establishPoint] = true 时（interim_assistant 新段落路径）在追加前建立
  /// text 断点（start=缓冲全量）；默认 false —— flush/reveal 只是推进既有
  /// text 段的 content，不产生新段，若在此建点会用「已 flush 进度」把同一
  /// 段文本在工具断点之后劈开（「一致性问题」的「一」「致」之间插卡）。
  void _appendToStreamingMessage(
    String text, {
    bool? isRevealQueueEmpty,
    bool establishPoint = false,
  }) {
    if (text.isEmpty) return;
    _ensureStreamingAssistantMessage();
    final id = state.stream.streamingAssistantMessageId!;
    var index = state.messages.indexWhere((m) => m.messageId == id);
    if (index == -1) {
      // 防御重锚：diff-merge 吸收匹配后流式临时消息可能被服务端权威行替换
      //（isMessageMatch 内容吸收），锚点重指最后一条 assistant，保证后续
      // 内容继续追加而不是静默丢失。
      for (var i = state.messages.length - 1; i >= 0; i--) {
        if (state.messages[i].role == 'assistant' &&
            state.messages[i].messageId != null) {
          index = i;
          state = state.copyWith(
            stream: state.stream.copyWith(
              streamingAssistantMessageId: state.messages[i].messageId,
            ),
          );
          break;
        }
      }
    }
    if (index == -1) return;
    final current = state.messages[index];
    // 兜底断点仅限「新段落」追加路径（interim_assistant）：start 取缓冲全量
    // （含待合并/待揭示），使段边界与最终 content 对齐。常规 flush/reveal
    // 路径不建点——text 段在 token 事件到达时已定义（_appendAssistantToken），
    // 这里若按已 flush 长度建点会劈段（「一」「致」之间插工具卡的根因）。
    if (establishPoint) {
      _ensureTimelinePoint(
        LiveSegmentKind.text,
        _currentStreamingContent().length,
        // 本路径只由 `_handleInterimAssistant` 触发，且上游已判过
        // `text.trim().isNotEmpty` ⇒ 到达的就是内容性正文（#147）。
        contentful: true,
      );
    }
    final next = List<ChatMessage>.of(state.messages);
    next[index] = current.copyWith(content: '${current.content ?? ''}$text');
    state = state.copyWith(
      messages: next,
      streamingScrollTrigger: state.streamingScrollTrigger + 1,
      isRevealQueueEmpty: isRevealQueueEmpty ?? state.isRevealQueueEmpty,
    );
  }

  String _currentStreamingContent() {
    final id = state.stream.streamingAssistantMessageId;
    String base = '';
    if (id != null) {
      for (final message in state.messages) {
        if (message.messageId == id) {
          base = message.content ?? '';
          break;
        }
      }
    } else if (state.messages.isNotEmpty) {
      for (var i = state.messages.length - 1; i >= 0; i--) {
        final message = state.messages[i];
        if (message.role == 'assistant') {
          base = message.content ?? '';
          break;
        }
      }
    }
    // 包含待合并与待揭示队列，避免重连去重时把待吐内容误作新内容
    if (state.pendingAssistantTokenChunks.isNotEmpty) {
      base += state.pendingAssistantTokenChunks.join();
    }
    if (_revealQueue.isNotEmpty) {
      base += _revealQueue.join();
    }
    return base;
  }

  /// interim_assistant：already_streamed 过滤 + 先 flush 再追加 + 分隔符规则。
  bool _handleInterimAssistant(String text, bool alreadyStreamed) {
    if (alreadyStreamed) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    flushPendingStreamingContent();
    final stream = state.stream;
    if (stream.streamingAssistantMessageId == null) {
      return _appendAssistantToken(text);
    }
    final currentContent = _currentStreamingContent();
    String append;
    if (stream.isReplayConnection) {
      // 修复④：与 token 路径共用 matchedPrefixLength 游标并回写，interim
      // 整段去重不再恒 0 失效（否则整段重复文本直接入 content）。
      final deduped = deduplicatedReplayText(
        text: text,
        existingContent: currentContent,
        matchedLength: stream.matchedPrefixLength,
      );
      append = deduped.remainder;
      // 整段吸收：游标错位（中段重放/多次重连叠加）时残余段常是已展示
      // 内容的后缀碎片，overlap 启发式会把它当新内容拼出「归档-#42 归档」
      // 式重复。凡残余段已被现有内容整体包含，一律吞掉并保持 replay 态，
      // 由后续帧的 offset 对齐自然衔接。
      if (append.isNotEmpty && currentContent.contains(append)) {
        append = '';
      }
      state = state.copyWith(
        stream: state.stream.copyWith(
          matchedPrefixLength: deduped.newCursor,
          isReplayConnection: deduped.stillReplay,
        ),
      );
      if (append.isEmpty) return false;
      // replay 直连：直接拼接不加分隔符。
    } else {
      // 1. 整段包含：已展示内容已包含本快照全量 → 吞掉（语义同 replay 分支兜底）
      if (currentContent.contains(text)) return false;

      // 2. 快照前缀重叠：currentContent 后缀与 text 前缀最大重叠（overlap >= 2 时只追加残余）
      var overlap = 0;
      final maxK = currentContent.length < text.length
          ? currentContent.length
          : text.length;
      for (var k = maxK; k >= 2; k--) {
        if (currentContent.endsWith(text.substring(0, k))) {
          overlap = k;
          break;
        }
      }

      if (overlap >= 2) {
        append = text.substring(overlap);
        // 3. 短片段防误判：残余 append 去空白后为空 → 吞掉
        if (append.trim().isEmpty) return false;
      } else {
        // 4. 未命中任何去重 → 维持现状新段落
        append = currentContent.isEmpty ? text : '\n\n$text';
      }
    }
    // interim 独立新段落或快照残余拼接：需建 text 断点；start 由
    // _appendToStreamingMessage 内部按缓冲全量取，保证段边界对齐最终 content。
    _appendToStreamingMessage(append, establishPoint: true);
    _markProgress();
    return true;
  }

  // -------------------------------------------------------------------------
  // 工具调用
  // -------------------------------------------------------------------------

  void _appendToolCall(ToolStreamEvent evt) {
    final stream = state.stream;
    if (stream.isReplayConnection) {
      final stableId = evt.stableId;
      if (stableId != null) {
        if (state.liveToolCalls.any((t) => t.id == stableId) ||
            state.completedToolCallGroups.any(
              (g) => g.toolCalls.any((t) => t.id == stableId),
            )) {
          return;
        }
      } else {
        var idx = stream.replayToolMatchIndex;
        while (idx < state.liveToolCalls.length) {
          if (_sameToolSignature(state.liveToolCalls[idx], evt)) {
            state = state.copyWith(
              stream: state.stream.copyWith(replayToolMatchIndex: idx + 1),
            );
            return;
          }
          idx++;
        }
      }
    }
    _ensureStreamingAssistantMessage();
    // 时间线断点：工具段切换（真实追加前记录，liveToolCalls 下标即段起点；
    // replay 去重命中已在上文 return，不会误建点）。
    _ensureTimelinePoint(LiveSegmentKind.tools, state.liveToolCalls.length);
    final tool = ToolCall(
      id: evt.stableId,
      name: evt.name,
      preview: evt.preview,
      args: evt.jsonArgs ?? _argsToJsonValue(evt.args),
      isCompleted: false,
    );
    final anchor =
        state.stream.toolCallAnchorMessageId ??
        state.stream.streamingAssistantMessageId;
    state = state.copyWith(
      liveToolCalls: [...state.liveToolCalls, tool],
      stream: state.stream.copyWith(toolCallAnchorMessageId: anchor),
    );
    _markProgress();
  }

  void _completeToolCall(ToolStreamEvent evt) {
    final stableId = evt.stableId;
    final calls = state.liveToolCalls;
    var index = -1;
    if (stableId != null) {
      index = calls.indexWhere((t) => t.id == stableId);
    }
    if (index == -1 && evt.name != null) {
      // 匹配 name 相同的最后一个未完成项。
      for (var i = calls.length - 1; i >= 0; i--) {
        if (calls[i].name == evt.name && !calls[i].isCompleted) {
          index = i;
          break;
        }
      }
    }
    if (index != -1) {
      final existing = calls[index];
      if (state.stream.isReplayConnection && existing.isCompleted) return;
      final next = List<ToolCall>.of(calls);
      next[index] = ToolCall(
        id: existing.id,
        name: evt.name ?? existing.name,
        preview: evt.preview ?? existing.preview,
        args:
            evt.jsonArgs ??
            (evt.args != null ? _argsToJsonValue(evt.args) : existing.args),
        duration: evt.duration,
        isError: evt.isError,
        isCompleted: true,
        startedAt: existing.startedAt,
      );
      state = state.copyWith(liveToolCalls: next);
    } else {
      if (state.stream.isReplayConnection &&
          stableId != null &&
          state.completedToolCallGroups.any(
            (g) => g.toolCalls.any((t) => t.id == stableId),
          )) {
        return;
      }
      // 匹配不到 → append 已完成项（服务器只发了完成事件）。
      state = state.copyWith(
        liveToolCalls: [
          ...calls,
          ToolCall(
            id: stableId,
            name: evt.name,
            preview: evt.preview,
            args: evt.jsonArgs ?? _argsToJsonValue(evt.args),
            duration: evt.duration,
            isError: evt.isError,
            isCompleted: true,
          ),
        ],
      );
    }
    _markProgress();
  }

  Map<String, JsonValue>? _argsToJsonValue(Map<String, Object?>? args) {
    if (args == null || args.isEmpty) return null;
    return args.map((k, v) => MapEntry(k, JsonValue.fromJson(v)));
  }

  bool _sameToolSignature(ToolCall call, ToolStreamEvent evt) {
    if (call.name != evt.name) return false;
    if (call.preview != evt.preview) return false;
    final argsA = call.args == null
        ? '{}'
        : jsonEncode(call.args!.map((k, v) => MapEntry(k, v.toJson())));
    final argsB = evt.args == null ? '{}' : jsonEncode(evt.args);
    return argsA == argsB;
  }

  // -------------------------------------------------------------------------
  // title / metering / approval / clarify / steer leftover
  // -------------------------------------------------------------------------

  void _handleTitle(String? sessionId, String? title) {
    if (sessionId == null || sessionId.isEmpty || title == null) return;
    if (state.sessionId.isNotEmpty && sessionId != state.sessionId) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(displayTitle: trimmed);
  }

  void _handleMetering({
    double? tps,
    required bool tpsAvailable,
    required bool estimated,
    String? sessionId,
  }) {
    if (sessionId != null &&
        sessionId.isNotEmpty &&
        state.sessionId.isNotEmpty &&
        sessionId != state.sessionId) {
      return;
    }
    if (tpsAvailable && !estimated && tps != null && tps.isFinite && tps > 0) {
      state = state.copyWith(
        stream: state.stream.copyWith(liveTokensPerSecond: tps),
      );
      // 同步更新 snapshot 的 tps，确保 popover 阈值色与 indicator 一致
      // 且即使仅有 metering 也能实时更新 cost/tps 相关行。
      final prev = state.contextWindowSnapshot;
      if (prev != null) {
        state = state.copyWith(
          contextWindowSnapshot: prev.replacingTokensPerSecond(tps),
        );
      } else {
        // 无历史 snapshot 时，用 tps 创建空壳（至少保留 tps 可展示）
        state = state.copyWith(
          contextWindowSnapshot: ContextWindowSnapshot(tokensPerSecond: tps),
        );
      }
    }
  }

  void _applyApprovalUpdate(Map<String, Object?> payload) {
    final pending = payload['pending'];
    if (pending is Map) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.warn,
        tag: 'chat',
        message:
            'Phase changed to approvalPending (session: ${state.sessionId})',
      );
      state = state.copyWith(
        phase: ChatPhase.approvalPending,
        pendingAction: state.pendingAction.copyWith(
          approvalPrompt: Map<String, Object?>.from(pending),
        ),
      );
      _reportLiveActivity(ChatLiveActivity.waitingApproval);
    } else {
      _clearApprovalCard();
    }
    _markProgress();
  }

  void _applyClarificationUpdate(Map<String, Object?> payload) {
    final pending = payload['pending'];
    if (pending is Map) {
      final clarifyIdRaw = pending['clarify_id'] ?? pending['clarifyId'];
      final clarifyId = clarifyIdRaw?.toString().trim();
      final bool isNew;
      if (clarifyId != null && clarifyId.isNotEmpty) {
        isNew = clarifyId != _notifiedClarifyId;
      } else {
        isNew =
            state.phase != ChatPhase.clarifyPending ||
            state.pendingAction.clarificationPrompt == null;
      }
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.warn,
        tag: 'chat',
        message:
            'Phase changed to clarifyPending (session: ${state.sessionId})',
      );
      state = state.copyWith(
        phase: ChatPhase.clarifyPending,
        pendingAction: state.pendingAction.copyWith(
          clarificationPrompt: Map<String, Object?>.from(pending),
        ),
      );
      _reportLiveActivity(ChatLiveActivity.waitingReply);
      if (isNew) {
        if (clarifyId != null && clarifyId.isNotEmpty) {
          _notifiedClarifyId = clarifyId;
        }
        final q = (pending['question'] as String?)?.trim();
        _notifyClarificationNeeded(
          q != null && q.isNotEmpty ? q : 'Agent 需要你澄清问题',
        );
      }
    } else {
      _clearClarificationCard();
    }
    _markProgress();
  }

  /// 澄清卡片超时收卡 + 提示。
  void handleClarificationTimeout() {
    if (_disposed) return;
    _clearClarificationCard();
    setNotice('澄清已超时');
    // #127：等待态结束 → 接回推送通道（agent 可能已继续续跑）。
    _resumeChannelsAfterPromptResolved();
  }

  /// 等待态（澄清/审批）结束 → 把推送通道接回来（#127）。
  ///
  /// 等待期间 App 往往在后台（用户从系统通知点回），两条 SSE（回合流 +
  /// 会话内容通道 `/api/session/stream`）都会在后台静默断线（无
  /// onTransportError/onClosed 事件，只能靠时间差识别）；而
  /// `_handleAppLifecycleChange` 的 resumed 主动探活被
  /// `!state.pendingAction.hasPendingPrompt` 门控挡掉（等待态下主动探活会
  /// 误判），清卡路径本身也**没有任何地方**重建通道 → 服务端继续输出却推
  /// 不到界面 = 「选完澄清回复后聊天不再更新」。
  /// 作答/超时即视为等待态结束，此处主动补一次探活 + 重建会话内容通道
  /// （服务端开新回合由该通道的 onServerTurnStarted 接管）。
  void _resumeChannelsAfterPromptResolved() {
    if (_disposed) return;
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    _promptResolvedResumes++;
    if (state.stream.activeStreamId != null) {
      return; // 有活跃流：交给 watchdog 的 transport-stale 链与兜底巡检。
    }
    // 只重建会话内容通道（内部 stop-then-start，幂等）：它是「服务端开新
    // 回合 → 客户端接管」的入口（onServerTurnStarted），也是澄清续跑真正
    // 依赖的通道。
    //
    // 刻意**不**在这里立刻 `_checkStatusAndReconnect()`：作答刚提交时服务端
    // 可能尚未开新回合，此刻探活会拿到 active=false，而既有分支会把 phase
    // 误落成 idle（实测把「作答后回 streaming」用例打红）。断线后的最终
    // 兜底交给 `_runStallGuardIfNeeded`（未决期待 + 无进展 → 主动拉取）。
    _startSessionContentChannel(sessionId);
  }

  /// 等待态结束走恢复路径的次数（#127 回归观测点）。
  @visibleForTesting
  int get promptResolvedResumes => _promptResolvedResumes;

  void _clearApprovalCard() {
    state = state.copyWith(
      phase: state.stream.hasActiveStream
          ? ChatPhase.streaming
          : ChatPhase.idle,
      pendingAction: state.pendingAction.copyWith(clearApproval: true),
    );
    _reportLiveActivityAfterClearPrompt();
  }

  void _clearClarificationCard() {
    state = state.copyWith(
      phase: state.stream.hasActiveStream
          ? ChatPhase.streaming
          : ChatPhase.idle,
      pendingAction: state.pendingAction.copyWith(clearClarification: true),
    );
    _reportLiveActivityAfterClearPrompt();
  }

  void _reportLiveActivityAfterClearPrompt() {
    if (_hasActiveTurn || state.pendingAction.hasPendingPrompt) {
      _reportLiveActivity(_inferLiveActivity());
    } else {
      // #129：等待态结束且回合已收 → 与回合收尾同口径（「已完成」停留 15s
      // 再撤岛），不再直接撤岛。
      _reportLiveActivity(ChatLiveActivity.completed);
      _scheduleLiveActivityDismiss();
    }
  }

  void _handleContextStatus(ContextPrefillStatus status, String? label) {
    if (state.stream.activeStreamId == null ||
        state.stream.hasCompletedResponse) {
      return;
    }
    state = state.copyWith(prefillStatus: status, prefillLabel: label);
    _markProgress();
    if (status == ContextPrefillStatus.loading ||
        status == ContextPrefillStatus.notConfigured) {
      _prefillSince = _now();
    } else {
      _prefillSince = null;
    }
  }

  /// 启动独立 Clarify SSE 流 + 轮询兜底通道。
  void _startClarifyChannel(String sessionId) {
    if (sessionId.isEmpty) return;
    _stopClarifyChannel();
    _emptyPendingStreak = 0;
    _connectClarifyStream(sessionId);
    _startClarifyPolling(sessionId);
  }

  /// 停止 Clarify SSE 流与轮询。
  void _stopClarifyChannel() {
    try {
      (_api ?? ref.read(chatApiProvider))?.stopClarifyStream();
    } catch (_) {}
    _clarifyPollTimer?.cancel();
    _clarifyPollTimer = null;
    _emptyPendingStreak = 0;
  }

  /// 连接 `/api/clarify/stream?session_id=` 独立 SSE 流。
  void _connectClarifyStream(String sessionId) {
    if (_disposed || sessionId.isEmpty) return;
    try {
      final api = ref.read(chatApiProvider);
      unawaited(
        api.startClarifyStream(
          sessionId,
          onEvent: (event) {
            if (_disposed) return;
            if (event is ClarificationPendingSseEvent) {
              _applyClarificationUpdate(event.payload);
            }
          },
          onTransportError: (_) {
            // 静默容错，由轮询兜底
          },
          onClosed: () {},
        ),
      );
    } catch (_) {
      // 静默容错
    }
  }

  /// 启动静默轮询兜底（20s 周期，会话打开时拉取）。
  void _startClarifyPolling(String sessionId) {
    _clarifyPollTimer?.cancel();
    _clarifyPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_pollClarifyPending(sessionId));
    });
    scheduleMicrotask(() => _pollClarifyPending(sessionId));
  }

  /// 静默拉取 `/api/clarify/pending`。
  Future<void> _pollClarifyPending(String sessionId) async {
    if (_disposed || state.sessionId != sessionId) return;
    final gen = _generation;
    try {
      final api = ref.read(chatApiProvider);
      final response = await api.clarifyPending(sessionId);
      if (_disposed || gen != _generation || state.sessionId != sessionId) {
        return;
      }
      if (response.pending != null) {
        _emptyPendingStreak = 0;
        final p = response.pending!;
        _applyClarificationUpdate({
          'pending': {
            'clarify_id': p.clarifyId,
            'question': p.question,
            'choices_offered': p.choicesOffered,
            'session_id': p.sessionId ?? sessionId,
            'kind': p.kind,
            'requested_at': p.requestedAt,
            'timeout_seconds': p.timeoutSeconds,
            'expires_at': p.expiresAt,
          },
          'pending_count': response.pendingCount ?? 1,
        });
      } else if (state.pendingAction.clarificationPrompt != null) {
        _emptyPendingStreak++;
        if (_emptyPendingStreak >= 2) {
          _emptyPendingStreak = 0;
          _clearClarificationCard();
        }
      } else {
        _emptyPendingStreak = 0;
      }
    } catch (_) {
      // 静默容错
    }
  }

  /// 启动独立 Approval SSE 流 + 轮询兜底通道。
  void _startApprovalChannel(String sessionId) {
    if (sessionId.isEmpty) return;
    _stopApprovalChannel();
    final enabled = ref.read(approvalStreamEnabledProvider);
    if (!enabled) return;
    _connectApprovalStream(sessionId);
    _startApprovalPolling(sessionId);
  }

  /// 停止 Approval SSE 流与轮询。
  void _stopApprovalChannel() {
    try {
      (_api ?? ref.read(chatApiProvider))?.stopApprovalStream();
    } catch (_) {}
    _approvalPollTimer?.cancel();
    _approvalPollTimer = null;
  }

  /// 连接 `/api/approval/stream?session_id=` 独立 SSE 流。
  void _connectApprovalStream(String sessionId) {
    if (_disposed || sessionId.isEmpty) return;
    try {
      final api = ref.read(chatApiProvider);
      unawaited(
        api.startApprovalStream(
          sessionId,
          onEvent: (event) {
            if (_disposed) return;
            if (event is ApprovalPendingSseEvent) {
              _applyApprovalUpdate(event.payload);
            }
          },
          onTransportError: (_) {
            // 静默容错，由轮询兜底
          },
          onClosed: () {},
        ),
      );
    } catch (_) {
      // 静默容错
    }
  }

  /// 启动静默轮询兜底（20s 周期，会话打开时拉取）。
  void _startApprovalPolling(String sessionId) {
    _approvalPollTimer?.cancel();
    _approvalPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_pollApprovalPending(sessionId));
    });
    scheduleMicrotask(() => _pollApprovalPending(sessionId));
  }

  /// 静默拉取 `/api/approval/pending`。
  Future<void> _pollApprovalPending(String sessionId) async {
    if (_disposed || state.sessionId != sessionId) return;
    final gen = _generation;
    try {
      final api = ref.read(chatApiProvider);
      final response = await api.approvalPending(sessionId);
      if (_disposed || gen != _generation || state.sessionId != sessionId) {
        return;
      }
      if (response.pending != null) {
        final p = response.pending!;
        _applyApprovalUpdate({
          'pending': p.toJson(),
          'pending_count': response.pendingCount ?? 1,
        });
      } else if (state.pendingAction.approvalPrompt != null) {
        _clearApprovalCard();
      }
    } catch (_) {
      // 静默容错
    }
  }

  void _handlePendingSteerLeftover(String text) {
    if (text.trim().isEmpty) return;
    state = state.copyWith(
      queuedSlashMessages: [...state.queuedSlashMessages, text],
      pinnedLocalNotices: [
        ...state.pinnedLocalNotices,
        'Steering hint was not consumed — it has been queued for the next message.',
      ],
    );
    _markProgress();
  }

  // -------------------------------------------------------------------------
  // done / stream_end / cancel / error 收尾
  // -------------------------------------------------------------------------

  void _applyDone(DoneStreamEvent event) {
    flushPendingStreamingContent();
    final completedStreamId = state.stream.activeStreamId;
    final currentStreamingId = state.stream.streamingAssistantMessageId;
    final rawSession = event.session;
    final hasCompletedTranscript =
        rawSession != null &&
        rawSession['messages'] is List &&
        (rawSession['messages'] as List).isNotEmpty;
    if (hasCompletedTranscript) {
      _applyCompletedStreamSession(rawSession, currentStreamingId);
    }
    final rawUsage = event.usage;
    ContextWindowSnapshot? snapshot =
        event.usageSnapshot ??
        (rawUsage != null ? ContextWindowSnapshot.fromJson(rawUsage) : null);
    // 若 usage 缺失关键字段，尝试从 session detail 或历史 snapshot 回退补齐
    if (snapshot != null) {
      final prev = state.contextWindowSnapshot;
      final detailFallback = hasCompletedTranscript
          ? SessionDetail.fromJson(rawSession)
          : null;
      // 回退 contextLength / threshold / tokens
      final merged = ContextWindowSnapshot(
        contextLength:
            snapshot.contextLength ??
            detailFallback?.contextLength ??
            prev?.contextLength,
        thresholdTokens:
            snapshot.thresholdTokens ??
            detailFallback?.thresholdTokens ??
            prev?.thresholdTokens,
        lastPromptTokens:
            snapshot.lastPromptTokens ??
            detailFallback?.lastPromptTokens ??
            prev?.lastPromptTokens,
        inputTokens:
            snapshot.inputTokens ??
            detailFallback?.inputTokens ??
            prev?.inputTokens,
        outputTokens:
            snapshot.outputTokens ??
            detailFallback?.outputTokens ??
            prev?.outputTokens,
        estimatedCost:
            snapshot.estimatedCost ??
            detailFallback?.estimatedCost ??
            prev?.estimatedCost,
        tokensPerSecond: snapshot.tokensPerSecond ?? prev?.tokensPerSecond,
      );
      // 若回退后仍有有效百分比，则使用合并后；否则保留原始
      snapshot = merged;
    } else if (hasCompletedTranscript) {
      // usage 缺失但有完整 transcript：直接从 session detail 构建
      // ignore: unnecessary_non_null_assertion
      final detail = SessionDetail.fromJson(rawSession!);
      snapshot = ContextWindowSnapshot(
        contextLength: detail.contextLength,
        thresholdTokens: detail.thresholdTokens,
        lastPromptTokens: detail.lastPromptTokens,
        inputTokens: detail.inputTokens,
        outputTokens: detail.outputTokens,
        estimatedCost: detail.estimatedCost,
        tokensPerSecond: state.contextWindowSnapshot?.tokensPerSecond,
      );
      // 若回退的 tps 存在，同步到 snapshot
      final prevTps =
          state.stream.liveTokensPerSecond ??
          state.contextWindowSnapshot?.tokensPerSecond;
      if (prevTps != null && snapshot.tokensPerSecond == null) {
        snapshot = snapshot.replacingTokensPerSecond(prevTps);
      }
    }
    if (snapshot != null &&
        (snapshot.contextLength != null ||
            snapshot.inputTokens != null ||
            snapshot.lastPromptTokens != null ||
            snapshot.tokensPerSecond != null)) {
      state = state.copyWith(contextWindowSnapshot: snapshot);
      final tps = snapshot.tokensPerSecond;
      if (tps != null && tps.isFinite && tps > 0) {
        _applyTurnTps(currentStreamingId, tps);
      }
    }
    _completeCurrentResponse(
      needsTranscriptRefresh: !hasCompletedTranscript,
      completedStreamId: completedStreamId,
    );
    // 回合完成（done）：通知 hook（仅后台发通知，见 notifications feature）。
    _notifyTurnCompleted();
    _triggerSessionListRefreshForCompleted(state.sessionId);
    unawaited(_writeCacheMessages(state.sessionId, state.messages));
  }

  void _applyCompletedStreamSession(
    Map<String, Object?> rawSession,
    String? currentStreamingId,
  ) {
    final detail = SessionDetail.fromJson(rawSession);
    final loaded = detail.messages ?? const <ChatMessage>[];
    final merged = _mergingLoadedMessages(
      loaded,
      state.messages,
      currentStreamingId,
    );
    final persisted = detail.toolCalls ?? const <PersistedToolCall>[];
    _lastPersistedToolCalls = persisted;
    _recordPersistedMessageCount(detail.messageCount);
    final persistedGroups = ToolCallGroup.groups(
      persistedToolCalls: persisted,
      messages: merged,
      messageOffset: state.messagesOffset,
      coalesce: _coalesceTools,
    );
    final liveGroups = _archiveLiveToolCallsToGroups();
    final reanchoredLiveGroups = _reanchorGroupsToMessages(
      liveGroups,
      merged,
      messageOffset: state.messagesOffset,
      oldStreamingId: currentStreamingId,
    );
    final groups = ToolCallGroup.merging(
      primaryGroups: persistedGroups,
      fallbackGroups: reanchoredLiveGroups,
    );
    final serverDerivedReasoning = ReasoningGroup.groups(
      messages: merged,
      messageOffset: state.messagesOffset,
    );
    final liveReasoning = _archiveLiveReasoningToGroups();
    final reanchoredLiveReasoning = _reanchorReasoningToMessages(
      liveReasoning,
      merged,
      messageOffset: state.messagesOffset,
      oldStreamingId: currentStreamingId,
    );
    final reasoningGroups = ReasoningGroup.merging(
      primaryGroups: serverDerivedReasoning,
      fallbackGroups: reanchoredLiveReasoning,
    );
    final title = detail.title?.trim();
    // 同步上下文快照（对齐 Swift applyCompletedStreamSession）
    final snapshotFromDetail = ContextWindowSnapshot(
      contextLength: detail.contextLength,
      thresholdTokens: detail.thresholdTokens,
      lastPromptTokens: detail.lastPromptTokens,
      inputTokens: detail.inputTokens,
      outputTokens: detail.outputTokens,
      estimatedCost: detail.estimatedCost,
      tokensPerSecond:
          state.stream.liveTokensPerSecond ??
          state.contextWindowSnapshot?.tokensPerSecond,
    );
    final hasSnapshotValues =
        snapshotFromDetail.contextLength != null ||
        snapshotFromDetail.thresholdTokens != null ||
        snapshotFromDetail.lastPromptTokens != null ||
        snapshotFromDetail.inputTokens != null;
    state = state.copyWith(
      messages: merged,
      messagesOffset: detail.messagesOffset ?? state.messagesOffset,
      hasOlderMessages:
          detail.messageCount != null && detail.messageCount! > merged.length,
      displayTitle: (title == null || title.isEmpty)
          ? state.displayTitle
          : title,
      workspace: detail.workspace ?? state.workspace,
      model: detail.model ?? state.model,
      modelProvider: detail.modelProvider ?? state.modelProvider,
      profile: detail.profile ?? state.profile,
      completedToolCallGroups: groups,
      completedReasoningGroups: reasoningGroups,
      liveToolCalls: const [],
      liveReasoningText: '',
      stream: state.stream.copyWith(
        clearStreamingAssistantMessageId: true,
        clearToolCallAnchorMessageId: true,
        clearReasoningAnchorMessageId: true,
      ),
    );
    if (hasSnapshotValues) {
      state = state.copyWith(contextWindowSnapshot: snapshotFromDetail);
    }
  }

  /// 服务端 transcript 与本地合并：local- 乐观消息保留插回；本地流式内容
  /// 与服务端取「更长/更新的」，前缀包含去重（chat_spec.md §5.5 最低档）。
  List<ChatMessage> _mergingLoadedMessages(
    List<ChatMessage> loaded,
    List<ChatMessage> current,
    String? streamingMessageId,
  ) {
    if (loaded.isEmpty) return List<ChatMessage>.from(current);
    if (current.isEmpty) return loaded;
    final result = List<ChatMessage>.from(loaded);
    if (streamingMessageId != null) {
      ChatMessage? localStreaming;
      for (final message in current) {
        if (message.messageId == streamingMessageId) {
          localStreaming = message;
          break;
        }
      }
      if (localStreaming != null) {
        final localContent = localStreaming.content ?? '';
        var lastAssistantIndex = -1;
        for (var i = result.length - 1; i >= 0; i--) {
          if (result[i].role == 'assistant') {
            lastAssistantIndex = i;
            break;
          }
        }
        if (lastAssistantIndex != -1) {
          final serverContent = result[lastAssistantIndex].content ?? '';
          if (localContent.isNotEmpty &&
              serverContent.startsWith(localContent)) {
            // 服务端已含本地全部内容 → 丢弃本地流式消息。
          } else if (localContent.isNotEmpty &&
              (serverContent.isEmpty ||
                  localContent.startsWith(serverContent))) {
            result[lastAssistantIndex] = result[lastAssistantIndex].copyWith(
              content: localContent,
            );
          }
        } else if (localContent.isNotEmpty) {
          result.add(localStreaming);
        }
      }
    }
    final loadedIds = result
        .map((m) => m.messageId)
        .whereType<String>()
        .toSet();
    final localToInsert = current
        .where(
          (m) =>
              (m.messageId ?? '').startsWith('local-') &&
              !loadedIds.contains(m.messageId) &&
              !_duplicatesLoadedUserMessage(m, result),
        )
        .toList();
    if (localToInsert.isNotEmpty) {
      var insertAt = result.length;
      for (var i = result.length - 1; i >= 0; i--) {
        if (result[i].role == 'user' &&
            TranscriptTurnClassifier.isUserTurnBoundary(result[i])) {
          insertAt = i + 1;
          break;
        }
      }
      result.insertAll(insertAt, localToInsert);
    }
    return result;
  }

  /// local- 乐观 user 消息与加载 transcript 的最后一条 user 消息内容相同
  /// （服务端已确认该消息）→ 视为重复，不再保留。
  bool _duplicatesLoadedUserMessage(
    ChatMessage local,
    List<ChatMessage> loaded,
  ) {
    if (local.role != 'user') return false;
    final localContent = local.content?.trim();
    if (localContent == null || localContent.isEmpty) return false;
    for (var i = loaded.length - 1; i >= 0; i--) {
      final message = loaded[i];
      if (message.role == 'user' &&
          (message.content ?? '').trim() == localContent) {
        return true;
      }
    }
    return false;
  }

  void _applyTurnTps(String? currentStreamingId, double tps) {
    var index = -1;
    if (currentStreamingId != null) {
      index = state.messages.indexWhere(
        (m) => m.messageId == currentStreamingId,
      );
    }
    if (index == -1) {
      for (var i = state.messages.length - 1; i >= 0; i--) {
        if (state.messages[i].role == 'assistant') {
          index = i;
          break;
        }
      }
    }
    if (index == -1) return;
    final next = List<ChatMessage>.of(state.messages);
    next[index] = next[index].copyWith(turnTps: tps);
    state = state.copyWith(messages: next);
  }

  /// completeCurrentResponse：结束流（activeStreamId=null、hasCompletedResponse=true）。
  void _completeCurrentResponse({
    required bool needsTranscriptRefresh,
    String? completedStreamId,
  }) {
    _api?.stopStream();
    _syncSessionStreaming(state.sessionId, false);
    _prefillSince = null;
    // 幽灵行退役（先于归档/重锚）：live 身份随收尾失效，客户端临时行若正文已被
    // 权威行覆盖即退场。否则 ① 它作为独立一行重复渲染整轮正文；② 工具组锚点留在
    // 「临时锚空间」（raw:N），下一次刷新即漂到末条 assistant（位置错误）。
    final settledMessages = _retireStaleLiveRows(state.messages);
    final nextToolGroups = _archiveLiveToolCallsToGroups(
      messages: settledMessages,
    );
    final nextReasoningGroups = _archiveLiveReasoningToGroups(
      messages: settledMessages,
    );
    final reanchoredToolGroups = _reanchorGroupsToMessages(
      nextToolGroups,
      settledMessages,
      messageOffset: state.messagesOffset,
      oldStreamingId: state.stream.streamingAssistantMessageId,
    );
    final reanchoredReasoningGroups = _reanchorReasoningToMessages(
      nextReasoningGroups,
      settledMessages,
      messageOffset: state.messagesOffset,
      oldStreamingId: state.stream.streamingAssistantMessageId,
    );
    state = state.copyWith(
      phase: ChatPhase.idle,
      messages: settledMessages,
      completedToolCallGroups: reanchoredToolGroups,
      completedReasoningGroups: reanchoredReasoningGroups,
      liveToolCalls: const [],
      liveReasoningText: '',
      liveTimelinePoints: const [],
      clearSteerHints: true,
      clearPrefillStatus: true,
      clearPrefillLabel: true,
      stream: state.stream.copyWith(
        clearActiveStreamId: true,
        clearLastEventId: true,
        clearStreamingAssistantMessageId: true,
        clearToolCallAnchorMessageId: true,
        clearReasoningAnchorMessageId: true,
        clearLiveTokensPerSecond: true,
        hasCompletedResponse: true,
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
        isReplayConnection: false,
        matchedPrefixLength: 0,
        matchedReasoningLength: 0,
        replayToolMatchIndex: 0,
        replayAfterSeq: 0,
      ),
      // #124：流完成不等于澄清已解决（chat_spec §2.3）。
      // 保持澄清卡片，仅清空 approvalPrompt。
      pendingAction: state.pendingAction.copyWith(clearApproval: true),
      responseCompletionNeedsTranscriptRefresh: needsTranscriptRefresh,
    );
    if (needsTranscriptRefresh && completedStreamId != null) {
      _scheduleTranscriptRefresh(completedStreamId);
    }
    _markProgress();
  }

  void _scheduleTranscriptRefresh(String streamId) {
    _transcriptRefreshTimer?.cancel();
    _transcriptRefreshTimer = Timer(const Duration(milliseconds: 500), () {
      _transcriptRefreshTimer = null;
      unawaited(refreshTranscriptIfCompleted(streamId));
    });
  }

  /// 回合完成 → 通知 hook（仅 done / stream_end 成功收尾触发；
  /// cancel / error / transportError 路径不调用）。
  ///
  /// sessionId 为空（新会话尚未确定）时跳过：通知点击需要可跳转的会话。
  void _notifyTurnCompleted() {
    if (_disposed) return;
    final current = state;
    final sessionId = current.sessionId;
    if (sessionId.isEmpty) return;
    final title = current.displayTitle;
    final preview = _lastAssistantContent(current);
    ref.read(chatTurnCompletedCallbackProvider)(sessionId, title, preview);
  }

  /// 澄清请求通知。
  void _notifyClarificationNeeded(String question) {
    if (_disposed) return;
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    ref.read(chatClarificationNeededCallbackProvider)(sessionId, question);
  }

  /// 异常中断通知。
  void _notifySessionError(String title, String preview) {
    if (_disposed) return;
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    ref.read(chatSessionErrorCallbackProvider)(sessionId, title, preview);
  }

  // -------------------------------------------------------------------------
  // #120 回合实时活动 → 实况通知（灵动岛）
  // -------------------------------------------------------------------------

  /// 上报回合实时活动。
  ///
  /// 与上次相同则跳过：token 级高频事件（输出中）不得穿透到平台通道。
  /// **去重键 = (活动, detail, 标题)**（#144）—— 标题是岛的最大字号位主文案，
  /// 它的变化必须穿透，否则新会话的岛会停在占位标题。
  /// [force] 供生命周期变化点使用——退后台时即使活动未变也要上报一次。
  /// 新会话（sessionId 为空）跳过：通知点击需要可跳转的会话。
  void _reportLiveActivity(
    ChatLiveActivity activity, {
    String detail = '',
    bool force = false,
  }) {
    if (_disposed) return;
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    final title = state.displayTitle;
    // #129 等待态豁免去重：等待态是「需主人行动」的报警态，一旦被外部链路撤岛
    // （后台兜底 / 列表归零 / 开关），去重表会让后续澄清轮询重建卡片的上报被
    // 静默跳过 → 岛再也回不来（#124 E 的「轮询重建即自动回岛」因此空转）。
    // 放行等待态使其每次上报都重新合成；服务层 `_lastShown` 幂等仍兜住平台通道
    // 调用（文案未变 → 零通道往返），故无 notify 风暴风险。
    final sticky =
        activity == ChatLiveActivity.waitingReply ||
        activity == ChatLiveActivity.waitingApproval;
    if (!force &&
        !sticky &&
        _liveActivity == activity &&
        _liveActivityDetail == detail &&
        _liveActivityTitle == title) {
      return;
    }
    // #129：出现新的进行中/等待活动 → 取消「已完成/已中断」的停留计时
    // （新活动已接管岛，停留不再需要）。
    if (activity != ChatLiveActivity.completed &&
        activity != ChatLiveActivity.interrupted) {
      _cancelLiveActivityDismiss();
    }
    _liveActivity = activity;
    _liveActivityDetail = detail;
    _liveActivityTitle = title;
    try {
      ref.read(chatLiveActivityCallbackProvider)(
        sessionId,
        title,
        activity,
        detail,
      );
    } catch (_) {}
  }

  /// #144：标题变化后按当前活动补报一次（去重键含标题，故必然穿透）。
  ///
  /// 无进行中活动、或完成/中断态已停留到期撤岛（[ChatLiveActivity.finished]）
  /// 时不补报 —— 不因一次改名或收尾补拉把已撤销的岛重新点亮。
  void _reReportForTitleChange() {
    if (_disposed) return;
    final current = _liveActivity;
    if (current == null || current == ChatLiveActivity.finished) return;
    _reportLiveActivity(current, detail: _liveActivityDetail);
  }

  /// #124：收尾时若仍有「等主人行动」的报警态，直接报 finished 会把岛上的
  /// 「请回复/请批准」一起抹掉（主人实测：从「生成中」切「请回复」会下岛）。
  /// 有等待态时改报等待态，让岛停在正确状态。
  ///
  /// #129：无等待态时不再直接撤岛，改报「已完成 / 已中断」并停留
  /// [liveActivityDwell]（主人拍板 15s）后自动撤岛；[interrupted] 用于
  /// cancel / error 收尾，语义为「已中断」而非「已完成」。
  void _reportTurnSettled({bool interrupted = false}) {
    final pending = state.pendingAction;
    if (pending.clarificationPrompt != null) {
      _reportLiveActivity(ChatLiveActivity.waitingReply);
      return;
    }
    if (pending.approvalPrompt != null) {
      _reportLiveActivity(ChatLiveActivity.waitingApproval);
      return;
    }
    _reportLiveActivity(
      interrupted ? ChatLiveActivity.interrupted : ChatLiveActivity.completed,
    );
    _scheduleLiveActivityDismiss();
  }

  /// #129「已完成 / 已中断」态在岛上的停留时长（主人拍板 15s）。
  static const Duration liveActivityDwell = Duration(seconds: 15);

  Timer? _liveActivityDismissTimer;

  /// #129：完成/中断态上岛后停留 [liveActivityDwell]，到期再报 finished 撤岛。
  void _scheduleLiveActivityDismiss() {
    _liveActivityDismissTimer?.cancel();
    _liveActivityDismissTimer = Timer(liveActivityDwell, () {
      _liveActivityDismissTimer = null;
      if (_disposed) return;
      // 停留期间若已转回进行中/等待态（新回合或等待态接管），不撤岛。
      final current = _liveActivity;
      if (current != ChatLiveActivity.completed &&
          current != ChatLiveActivity.interrupted) {
        return;
      }
      _reportLiveActivity(ChatLiveActivity.finished);
    });
  }

  void _cancelLiveActivityDismiss() {
    _liveActivityDismissTimer?.cancel();
    _liveActivityDismissTimer = null;
  }

  /// 推断当前活动（退后台强制上报与等待态判定用）。
  ChatLiveActivity _inferLiveActivity() {
    final pending = state.pendingAction;
    if (pending.clarificationPrompt != null) {
      return ChatLiveActivity.waitingReply;
    }
    if (pending.approvalPrompt != null) {
      return ChatLiveActivity.waitingApproval;
    }
    final current = _liveActivity;
    if (current != null && current != ChatLiveActivity.finished) {
      return current;
    }
    return ChatLiveActivity.thinking;
  }

  /// #142 A2：当前相位是否表示回合进行中（死区关键判据）。
  /// 刻意不含 approvalPending / clarifyPending —— 那两个由 hasPendingPrompt 门控覆盖。
  bool get _phaseIndicatesOngoingTurn =>
      state.phase == ChatPhase.sending ||
      state.phase == ChatPhase.streaming ||
      state.phase == ChatPhase.steered ||
      state.phase == ChatPhase.recovering;

  /// 当前是否处于「回合进行中」（对齐保活上报的 isStreaming 判定）。
  bool get _hasActiveTurn =>
      state.stream.activeStreamId != null ||
      state.phase == ChatPhase.sending ||
      state.phase == ChatPhase.streaming ||
      state.phase == ChatPhase.steered ||
      state.phase == ChatPhase.approvalPending ||
      state.phase == ChatPhase.clarifyPending ||
      state.phase == ChatPhase.recovering;

  /// 最近一条非空 assistant 消息内容（通知预览用）；无则空串。
  String _lastAssistantContent(ChatState state) {
    for (final message in state.messages.reversed) {
      final content = message.content ?? '';
      if (message.role == 'assistant' && content.trim().isNotEmpty) {
        return content;
      }
    }
    return '';
  }

  void _handleStreamEnd() {
    final wasCompleted = state.stream.hasCompletedResponse;
    if (!wasCompleted) {
      _completeCurrentResponse(
        needsTranscriptRefresh: false,
        completedStreamId: state.stream.activeStreamId,
      );
      // 回合完成（stream_end，done 未先到）：通知 hook。
      // done 已收尾时 wasCompleted 为 true，不会重复通知。
      _notifyTurnCompleted();
      _triggerSessionListRefreshForCompleted(state.sessionId);
    }
    _finishStream();
    unawaited(_writeCacheMessages(state.sessionId, state.messages));
  }

  void _handleCancelled() {
    _syncSessionStreaming(state.sessionId, false);
    if (!state.stream.hasCompletedResponse) {
      _completeCurrentResponse(
        needsTranscriptRefresh: false,
        completedStreamId: state.stream.activeStreamId,
      );
      _notifySessionError('响应已取消', state.displayTitle);
    }
    _finishStream(endPhase: ChatPhase.cancelled);
  }

  void _handleErrorEvent(String message) {
    _syncSessionStreaming(state.sessionId, false);
    if (!state.stream.hasCompletedResponse) {
      state = state.copyWith(sendErrorMessage: message);
      _completeCurrentResponse(
        needsTranscriptRefresh: false,
        completedStreamId: state.stream.activeStreamId,
      );
      _notifySessionError('响应出错', message);
      _finishStream(endPhase: ChatPhase.error);
    } else {
      // done 已收尾：不显示错误，仅清理残留。
      _finishStream();
    }
  }

  /// finishStream：清残留（flush、卡片、pinned notices、队列顺次发送），
  /// 相位经瞬态 endPhase 后立即回 idle。
  void _finishStream({ChatPhase endPhase = ChatPhase.idle}) {
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat',
      message:
          'Stream finished (endPhase: ${endPhase.name}, session: ${state.sessionId})',
    );
    _syncSessionStreaming(state.sessionId, false);
    flushPendingStreamingContent();
    _resetReconnectBackoff();
    _cancelJitterTimers();
    _resetFullReconnectThrottle();
    _malformedDoneStreak = 0;
    _prefillSince = null;
    var messages = state.messages;
    if (state.pinnedLocalNotices.isNotEmpty) {
      final notices = state.pinnedLocalNotices
          .map(
            (text) => ChatMessage(
              role: 'local_notice',
              content: text,
              messageId: 'local-notice-${uuidV4()}',
              timestamp: _nowSeconds(),
            ),
          )
          .toList();
      messages = [...messages, ...notices];
    }
    state = state.copyWith(
      phase: endPhase,
      messages: messages,
      pinnedLocalNotices: const [],
      clearSteerHints: true,
      clearPrefillStatus: true,
      clearPrefillLabel: true,
      clearTurnStartedMillis: true,
      liveTimelinePoints: const [],
      // #124：流收尾不等于澄清已解决（chat_spec §2.3「approval/clarify 是主流报警
      // 事件，流不中断」）。重连/收尾时保留澄清态，避免卡片消失后又被 20s 轮询
      // 拉回造成「消失→重现」闪烁。撤销只由作答成功 / 服务端 pending 明确为空 /
      // 真超时三条路径驱动（分别在 respondToClarification、_pollClarifyPending、
      // handleClarificationTimeout 内）。
      pendingAction: state.pendingAction.copyWith(clearApproval: true),
      stream: state.stream.copyWith(
        clearActiveStreamId: true,
        clearLastEventId: true,
        clearStreamingAssistantMessageId: true,
        clearToolCallAnchorMessageId: true,
        clearReasoningAnchorMessageId: true,
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
        isCancelling: false,
        isReplayConnection: false,
        matchedPrefixLength: 0,
        matchedReasoningLength: 0,
        replayToolMatchIndex: 0,
        replayAfterSeq: 0,
      ),
    );
    _api?.stopStream();
    _cancelStreamTimers();
    _markProgress();
    try {
      final keepalive = ref.read(backgroundKeepaliveServiceProvider);
      unawaited(
        keepalive.stopForegroundService()
        // 停止失败仅诊断日志（K 修复规格：仅开关路径需回滚，见
        // setBgForegroundServiceEnabled）；fire-and-forget 调用自吞。
        .catchError((Object _) {}),
      );
      if (state.sessionId.isNotEmpty) {
        unawaited(keepalive.cancelOneOffPoll(state.sessionId));
      }
    } catch (_) {}
    // 瞬态相位：收尾完成后立即回 idle。
    if (endPhase != ChatPhase.idle) {
      state = state.copyWith(phase: ChatPhase.idle);
    }
    // done 后未收到 title → 补拉一次标题。
    if (state.stream.hasCompletedResponse &&
        state.displayTitle == 'Untitled Session') {
      unawaited(_refreshCompletedResponseTitleIfNeeded());
    }
    // 队列顺次发送。
    if (state.queuedSlashMessages.isNotEmpty) {
      unawaited(_drainQueuedSlashMessage());
    }
  }

  void _cancelStreamTimers() {
    _mergeTimer?.cancel();
    _mergeTimer = null;
    _revealTimer?.cancel();
    _revealTimer = null;
    _revealQueue.clear();
    _revealQueueStart = null;
    _lastContextPollTime = null;
    _isContextPolling = false;
  }

  Future<void> _refreshCompletedResponseTitleIfNeeded() async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    final gen = _generation;
    try {
      final response = await _api!.session(
        sessionId: sessionId,
        includeMessages: false,
      );
      if (_disposed || gen != _generation) return;
      final title = response.session?.title?.trim();
      if (title != null && title.isNotEmpty) {
        state = state.copyWith(displayTitle: title);
      }
    } on ApiException {
      // 标题补拉失败静默。
    }
  }

  /// 聊天页改名成功 → 免网络同步会话列表对应行标题。
  ///
  /// 失败路径不调用（列表保持旧值等下次全量刷新纠偏）；列表 provider
  /// 尚未就绪（无激活连接/未初始化）时静默跳过。
  void _syncSessionListRename(String title) {
    if (_disposed || state.sessionId.isEmpty) return;
    if (!ref.exists(sessionListControllerProvider)) return;
    try {
      ref
          .read(sessionListControllerProvider.notifier)
          .applyExternalRename(state.sessionId, title);
    } catch (_) {}
  }

  /// 聊天页置顶成功 → 免网络同步会话列表对应行。
  void _syncSessionListPinned(String id, bool pinned) {
    if (_disposed || id.isEmpty) return;
    try {
      ref
          .read(sessionListControllerProvider.notifier)
          .applyExternalPinned(id, pinned);
    } catch (_) {}
  }

  /// 聊天页归档/取消归档成功 → 免网络同步会话列表
  /// （归档后返回列表不再看到该行，无需等 30s 轮询）。
  void _syncSessionListArchived(String id, bool archived) {
    if (_disposed || id.isEmpty) return;
    try {
      ref
          .read(sessionListControllerProvider.notifier)
          .applyExternalArchived(id, archived);
    } catch (_) {}
  }

  /// 聊天页删除成功 → 免网络同步会话列表（返回列表不再看到该行）。
  void _syncSessionListDeleted(String id) {
    if (_disposed || id.isEmpty) return;
    try {
      ref.read(sessionListControllerProvider.notifier).applyExternalDeleted(id);
    } catch (_) {}
  }

  /// 聊天页分支成功 → 新会话插到列表顶部（免一次全量拉取）。
  ///
  /// 标题：服务端返回优先，缺失时兜底 `<当前标题> (fork)`
  /// （对齐列表侧 branch 的本地命名，避免刷新前后跳变）。
  void _syncSessionListBranched(
    SessionBranchResponse response, {
    required String parentId,
  }) {
    if (_disposed) return;
    final newId = response.sessionId;
    if (newId == null || newId.isEmpty) return;
    final serverTitle = response.title?.trim();
    final baseTitle = state.displayTitle.trim().isEmpty
        ? null
        : state.displayTitle.trim();
    final resolvedTitle = (serverTitle != null && serverTitle.isNotEmpty)
        ? serverTitle
        : (baseTitle == null ? null : '$baseTitle (fork)');
    try {
      ref
          .read(sessionListControllerProvider.notifier)
          .applyExternalBranched(
            SessionSummary(
              sessionId: newId,
              title: resolvedTitle,
              parentSessionId: response.parentSessionId ?? parentId,
            ),
          );
    } catch (_) {}
  }

  void _onNewSessionCreated(String newSessionId, String hint) {
    _pendingNewSessionIds.add(newSessionId);
    // Guard: no active connection in tests/offline -> skip list refresh (avoid "尚未配置服务器连接" throw).
    try {
      final active = ref.read(activeConnectionProvider);
      if (active == null) return;
    } catch (_) {
      return;
    }
    try {
      final notifier = ref.read(sessionListControllerProvider.notifier);
      unawaited(
        notifier
            .handleNewChatSession(newSessionId, titleHint: hint)
            .catchError((_) {}),
      );
    } catch (_) {
      // Provider 未就绪（如无激活连接）时静默，列表会在下次进入时拉取。
    }
  }

  void _triggerSessionListRefreshForCompleted(String sessionId) {
    if (sessionId.isEmpty) return;
    final throttle = ref.read(sessionListRefreshThrottleProvider);
    // 新建会话（pending）双次补拉语义：收尾时必须强制刷新一次，不参与
    // 存量会话节流；其刷新时间戳同时作为容器级冷却，窗口内其他完成合并
    // 跳过，避免重复拉取。
    if (_pendingNewSessionIds.remove(sessionId)) {
      throttle.lastRefreshAt = _now();
      _fireSessionListRefresh();
      return;
    }
    // 存量会话：回合完成同样刷新列表（#30）。节流窗口内（同会话重复 /
    // 并发多会话）合并进先到的刷新，窗口外直接触发。
    final now = _now();
    final last = throttle.lastRefreshAt;
    if (last != null &&
        now.difference(last) < _sessionListRefreshThrottleWindow) {
      return;
    }
    throttle.lastRefreshAt = now;
    _fireSessionListRefresh();
  }

  /// 实际执行会话列表强制刷新（弱网/离线静默，不抛错）。
  void _fireSessionListRefresh() {
    if (_disposed) return;
    try {
      final active = ref.read(activeConnectionProvider);
      if (active == null) return;
    } catch (_) {
      return;
    }
    try {
      final notifier = ref.read(sessionListControllerProvider.notifier);
      unawaited(notifier.refreshIfStale(force: true).catchError((_) {}));
    } catch (_) {}
  }

  /// 实时同步单个会话流式状态到会话列表（乐观置位 / 清除 + 后台纠偏）。
  void _syncSessionStreaming(
    String sessionId,
    bool isStreaming, {
    String? activeStreamId,
    bool verifyInBackground = false,
  }) {
    if (sessionId.isEmpty || _disposed) return;
    try {
      final active = ref.read(activeConnectionProvider);
      if (active == null) return;
    } catch (_) {
      return;
    }
    try {
      final notifier = ref.read(sessionListControllerProvider.notifier);
      notifier.markStreaming(
        sessionId,
        isStreaming,
        activeStreamId: activeStreamId,
        verifyInBackground: verifyInBackground,
      );
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // transportError 断线恢复（chat_spec.md §5.3）
  // -------------------------------------------------------------------------

  /// 取消挂起的重连退避定时器。
  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// 取消挂起的看门狗错峰定时器（状态轮询与强制重连）。
  void _cancelJitterTimers() {
    _statusPollJitterTimer?.cancel();
    _statusPollJitterTimer = null;
    _forceReconnectJitterTimer?.cancel();
    _forceReconnectJitterTimer = null;
  }

  /// 重置 afterSeq=0 全量重连的冷却限频。
  void _resetFullReconnectThrottle() {
    _lastFullReconnectStreamId = null;
    _lastFullReconnectTime = null;
  }

  /// 任何成功事件重置退避（SSE 连接成功 / 收到任意 event / 收到 status 正常响应）。
  void _resetReconnectBackoff() {
    _reconnectAttempts = 0;
    _cancelReconnectTimer();
    _cancelRecoverySentinel();
    _cancelResumeProbeRetry();
  }

  /// 取消重连预算耗尽哨兵（#100）。
  void _cancelRecoverySentinel() {
    _recoverySentinelTimer?.cancel();
    _recoverySentinelTimer = null;
  }

  /// 取消 resume 探活重试定时器（#100）。
  void _cancelResumeProbeRetry() {
    _resumeProbeRetryTimer?.cancel();
    _resumeProbeRetryTimer = null;
  }

  /// 重连预算耗尽时启动哨兵（#100：耗尽后全链路静默的观测性 + 前台自愈）。
  /// 每 [ChatWatchdogConfig.recoverySentinelInterval] 巡检一次：条件消失自毁，
  /// 否则 WARN + status 探活（isThrottledFallback：失败不烧预算转强连）。
  void _startRecoverySentinelIfExhausted() {
    if (_disposed) return;
    if (_reconnectAttempts < _watchdogConfig.effectiveMaxReconnectAttempts) {
      return;
    }
    _recoverySentinelTimer ??= Timer.periodic(
      _watchdogConfig.recoverySentinelInterval,
      (_) => _recoverySentinelTick(),
    );
  }

  void _recoverySentinelTick() {
    if (_disposed ||
        _appPaused ||
        state.stream.activeStreamId == null ||
        state.stream.hasCompletedResponse ||
        state.pendingAction.hasPendingPrompt ||
        _reconnectAttempts < _watchdogConfig.effectiveMaxReconnectAttempts) {
      _cancelRecoverySentinel();
      return;
    }
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.warn,
      tag: 'chat_reconnect',
      message:
          'Recovery exhausted, re-probing (attempts: $_reconnectAttempts, session: ${state.sessionId})',
    );
    unawaited(_checkStatusAndReconnect(isThrottledFallback: true));
  }

  /// 收尾帧（done）载荷解析失败的处理（#155）。
  ///
  /// done 是**终结帧**：解析失败只说明这一帧没吃全（该帧可含全量 session，实测
  /// ~9.7 MB，慢链路/服务端写超时会把它截断），**不代表回合还在跑**。故按「收尾」
  /// 语义处理，而不是走传输错误的恢复链：
  ///
  /// 1. 停流 + 撤掉一切恢复定时器。**绝不回放**：journal 回放会把同一张巨帧原样
  ///    重发，且回合结束后回放仍可用（`replay_available` 只看 journal 是否存在），
  ///    旧实现会在这里反复重吃 9.7 MB —— 既不收敛也不报错，界面永远停在「生成中」；
  /// 2. 探活一次：服务端确实还在写 → 正常 resume（断点未知时不做全量重连，避免整段
  ///    重放把巨帧再拉一遍）；已结束（绝大多数）→ 用 REST transcript 收尾；
  /// 3. 连续失败达熔断阈值 → 按 transcript 收尾 + 显式报错，绝不静默挂死。
  Future<void> _handleMalformedDone(String message) async {
    if (_disposed) return;
    if (state.stream.activeStreamId == null ||
        state.stream.hasCompletedResponse) {
      // 已收尾 / 本就没有活动流：仅清理，不进任何恢复链。
      _finishStream();
      return;
    }
    final streamId = state.stream.activeStreamId!;
    _malformedDoneStreak++;
    final breaker = _malformedDoneStreak >
        _watchdogConfig.effectiveMaxMalformedDoneSettleAttempts;
    DiagnosticsService.instance.log(
      level: breaker ? DiagnosticsLogLevel.error : DiagnosticsLogLevel.warn,
      tag: 'chat_reconnect',
      message:
          'Malformed done frame handled as turn end (streak: $_malformedDoneStreak, '
          'breaker: $breaker, streamId: $streamId, session: ${state.sessionId}): $message',
    );
    _api?.stopStream();
    _cancelReconnectTimer();
    _cancelJitterTimers();
    _cancelRecoverySentinel();
    _cancelResumeProbeRetry();
    if (breaker) {
      await _settleTurnFromTranscript(
        streamId,
        notice: '收尾数据不完整（已重试多次），已按服务器记录收尾。',
        interrupted: true,
      );
      return;
    }
    state = state.copyWith(
      stream: state.stream.copyWith(
        isSuspended: true,
        recovery: ActiveStreamRecoveryState.checking,
      ),
    );
    final gen = _generation;
    try {
      final status = await _api!.chatStreamStatus(streamId);
      if (_disposed || gen != _generation) return;
      if (state.stream.activeStreamId != streamId) return;
      if (status.active == true &&
          _replayAfterSeq(state.stream.lastEventId) > 0) {
        await _loadMessagesAndResume(streamId);
        return;
      }
      await _settleTurnFromTranscript(
        streamId,
        notice: null,
        interrupted: false,
      );
    } on ApiException {
      if (_disposed || gen != _generation) return;
      if (state.stream.activeStreamId != streamId) return;
      // 探活本身失败 = 真·网络故障：交给既有（带预算上限的）恢复链。
      _handleTransportError(message);
    }
  }

  /// 用 REST transcript 收尾回合（收尾帧损坏时的权威收尾路径）。
  ///
  /// 与 [_finalizeAfterRecovery] 的差别：本路径**从不回放**，只在确有必要时显式
  /// 提示；并以「transcript 是否前进」判断是否有丢尾风险（前进 = 服务端已落库）。
  Future<void> _settleTurnFromTranscript(
    String streamId, {
    required String? notice,
    required bool interrupted,
  }) async {
    final serverAssistantIdsBefore = _serverAssistantMessageIds();
    await loadMessages();
    if (_disposed) return;
    if (state.stream.activeStreamId != streamId) return;
    final hasAssistantResponse = state.messages.any(
      (m) => m.role == 'assistant',
    );
    if (!hasAssistantResponse) {
      state = state.copyWith(sendErrorMessage: '连接已断开，未能恢复流。');
      _notifySessionError('连接已断开', '未能恢复流，会话已终止。');
      _finishStream(endPhase: ChatPhase.error);
      _reportTurnSettled(interrupted: true);
      return;
    }
    _completeCurrentResponse(
      needsTranscriptRefresh: false,
      completedStreamId: streamId,
    );
    // 判据＝**服务端新落库**的 assistant 消息是否出现。本地流式占位消息
    // （`stream-*`）合并后会一直排在列表末尾，拿「末条 assistant 指纹」当判据
    // 会永远判成「没前进」（实测踩过）。
    final transcriptAdvanced = _serverAssistantMessageIds()
        .difference(serverAssistantIdsBefore)
        .isNotEmpty;
    final effectiveNotice =
        notice ??
        (transcriptAdvanced ? null : '收尾数据不完整，已按当前记录收尾。');
    if (effectiveNotice != null) {
      state = state.copyWith(sendErrorMessage: effectiveNotice);
    }
    _notifyTurnCompleted();
    _triggerSessionListRefreshForCompleted(state.sessionId);
    _finishStream();
    unawaited(_writeCacheMessages(state.sessionId, state.messages));
    _reportTurnSettled(interrupted: interrupted);
  }

  /// transcript 中「服务端落库」的 assistant 消息 id 集合（排除本地流式占位）。
  ///
  /// 占位 id 形如 `stream-<uuid>`（全仓既有约定，见锚定/合并逻辑），合并后会留在
  /// 列表尾部 ⇒ **不能**以「末条 assistant 的指纹」判断 transcript 是否前进。
  Set<String> _serverAssistantMessageIds() {
    final ids = <String>{};
    for (final message in state.messages) {
      final id = message.messageId;
      if (message.role != 'assistant' || id == null) continue;
      if (id.startsWith('stream-')) continue;
      ids.add(id);
    }
    return ids;
  }

  void _handleTransportError(String message) {
    final stream = state.stream;
    if (stream.activeStreamId == null || stream.hasCompletedResponse) {
      // 无连接可恢复：显示错误 + finishStream。
      _syncSessionStreaming(state.sessionId, false);
      state = state.copyWith(sendErrorMessage: message);
      _finishStream(endPhase: ChatPhase.error);
      return;
    }
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.warn,
      tag: 'chat',
      message: 'Transport error handled, phase -> recovering: $message',
    );
    // 挂起：lastEventID 已由 onEventId 记录；快照即当前 state。
    state = state.copyWith(
      phase: ChatPhase.recovering,
      stream: stream.copyWith(
        isSuspended: true,
        recovery: ActiveStreamRecoveryState.checking,
      ),
    );
    _api?.stopStream();
    _cancelJitterTimers();

    final maxAttempts = _watchdogConfig.effectiveMaxReconnectAttempts;
    if (_reconnectAttempts >= maxAttempts) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.warn,
        tag: 'chat_reconnect',
        message:
            'Transport error: max reconnect attempts ($_reconnectAttempts) reached, stopping auto-reconnect',
      );
      // #100：预算耗尽不再纯静默——哨兵周期巡检（前台自愈 + 观测性）。
      _startRecoverySentinelIfExhausted();
      return;
    }

    final delay = _watchdogConfig.backoffDelayForAttempt(_reconnectAttempts);
    _reconnectAttempts++;
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat_reconnect',
      message:
          'Scheduling reconnect attempt $_reconnectAttempts with delay ${delay.inMilliseconds}ms (streamId: ${stream.activeStreamId})',
    );
    _cancelReconnectTimer();
    final gen = _generation;
    _reconnectTimer = Timer(delay, () {
      if (_disposed || gen != _generation) return;
      _reconnectTimer = null;
      unawaited(_reconnectIfNeeded());
    });
  }

  Future<void> _reconnectIfNeeded() async {
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return;
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat_reconnect',
      message: 'Stream reconnection checking status (streamId: $streamId)',
    );
    final gen = _generation;
    try {
      final status = await _api!.chatStreamStatus(streamId);
      if (_disposed || gen != _generation) return;
      _resetReconnectBackoff();
      if (status.active == true) {
        // 全量重连：loadMessages 后恢复（带 replay 若快照有 lastEventID）。
        await _loadMessagesAndResume(streamId);
        return;
      }
      if (status.replayAvailable == true) {
        final afterSeq = _replayAfterSeq(state.stream.lastEventId);
        state = state.copyWith(
          stream: state.stream.copyWith(
            isSuspended: false,
            recovery: ActiveStreamRecoveryState.reconnecting,
          ),
        );
        if (afterSeq > 0) {
          _connectStream(streamId, replayAfterSeq: afterSeq);
        } else {
          _connectStream(streamId, fullReconnect: true);
        }
        state = state.copyWith(
          stream: state.stream.copyWith(
            isSuspended: false,
            recovery: ActiveStreamRecoveryState.idle,
          ),
          phase: ChatPhase.streaming,
        );
        _markProgress();
        return;
      }
      // 非 active 且无 replay：loadMessages → 有 assistant 响应按 transcript
      // complete，否则 finalize 为失败。
      await _finalizeAfterRecovery(streamId);
    } on ApiException {
      if (_disposed || gen != _generation) return;
      // status 失败 → 强制尝试 replay。
      _forceReconnect(streamId);
    }
  }

  Future<void> _loadMessagesAndResume(String streamId) async {
    await loadMessages();
    if (_disposed) return;
    if (state.stream.activeStreamId != streamId) return;
    // 重锚定：加载的 transcript 里当前回合最后一条 assistant 消息。
    final currentAnchor = state.stream.streamingAssistantMessageId;
    if (currentAnchor == null ||
        !state.messages.any((m) => m.messageId == currentAnchor)) {
      String? anchorId;
      for (var i = state.messages.length - 1; i >= 0; i--) {
        final message = state.messages[i];
        if (message.role == 'assistant' && message.messageId != null) {
          anchorId = message.messageId;
          break;
        }
      }
      if (anchorId != null) {
        state = state.copyWith(
          stream: state.stream.copyWith(streamingAssistantMessageId: anchorId),
        );
      }
    }
    final afterSeq = _replayAfterSeq(state.stream.lastEventId);
    if (afterSeq > 0) {
      _connectStream(streamId, replayAfterSeq: afterSeq);
    } else {
      _connectStream(streamId, fullReconnect: true);
    }
    state = state.copyWith(
      stream: state.stream.copyWith(
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
      ),
      phase: ChatPhase.streaming,
    );
    _markProgress();
  }

  Future<void> _finalizeAfterRecovery(String streamId) async {
    await loadMessages();
    if (_disposed) return;
    if (state.stream.activeStreamId != streamId) return;
    final hasAssistantResponse = state.messages.any(
      (m) => m.role == 'assistant',
    );
    if (hasAssistantResponse) {
      _completeCurrentResponse(
        needsTranscriptRefresh: false,
        completedStreamId: streamId,
      );
      _finishStream();
    } else {
      state = state.copyWith(sendErrorMessage: '连接已断开，未能恢复流。');
      _notifySessionError('连接已断开', '未能恢复流，会话已终止。');
      _finishStream(endPhase: ChatPhase.error);
    }
  }

  /// 强制重连（status 失败 / 看门狗超时；带 replay 若可用）。
  void _forceReconnect(String streamId, {int jitterMs = 0}) {
    if (_disposed) return;
    if (_reconnectAttempts >= _watchdogConfig.effectiveMaxReconnectAttempts) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.warn,
        tag: 'chat_reconnect',
        message:
            'Force reconnect suppressed: max reconnect attempts ($_reconnectAttempts) reached',
      );
      // #100：预算耗尽不再纯静默——哨兵周期巡检（前台自愈 + 观测性）。
      _startRecoverySentinelIfExhausted();
      return;
    }
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat_reconnect',
        message:
            'Force reconnect suppressed: backoff timer is currently pending',
      );
      return;
    }
    final afterSeq = _replayAfterSeq(state.stream.lastEventId);

    // afterSeq == 0 全量重连限频（T2 冷却保护，防重连风暴放大器）
    if (afterSeq == 0) {
      final now = _now();
      if (_lastFullReconnectStreamId == streamId &&
          _lastFullReconnectTime != null &&
          now.difference(_lastFullReconnectTime!) <
              _watchdogConfig.fullReconnectCooldown) {
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.warn,
          tag: 'chat_reconnect',
          message:
              'fullReconnect throttled for stream $streamId (afterSeq: 0), falling back to status check',
        );
        unawaited(_checkStatusAndReconnect(isThrottledFallback: true));
        return;
      }
      _lastFullReconnectStreamId = streamId;
      _lastFullReconnectTime = now;
    }

    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.warn,
      tag: 'chat_reconnect',
      message:
          'Force reconnecting stream (streamId: $streamId, afterSeq: $afterSeq, jitterMs: $jitterMs)',
    );
    _recordTransportActivity();
    state = state.copyWith(
      stream: state.stream.copyWith(
        isSuspended: true,
        recovery: ActiveStreamRecoveryState.reconnecting,
      ),
    );
    _api?.stopStream();
    if (afterSeq > 0) {
      _connectStream(streamId, replayAfterSeq: afterSeq);
    } else {
      _connectStream(streamId, fullReconnect: true);
    }
    state = state.copyWith(
      stream: state.stream.copyWith(
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
      ),
      phase: ChatPhase.streaming,
    );
    _markProgress();
  }

  /// lastEventID 冒号后序号解析（§5.4）；解析失败 → 0。
  int _replayAfterSeq(String? lastEventId) {
    if (lastEventId == null) return 0;
    final idx = lastEventId.lastIndexOf(':');
    final part = idx == -1 ? lastEventId : lastEventId.substring(idx + 1);
    return int.tryParse(part.trim()) ?? 0;
  }

  // -------------------------------------------------------------------------
  // 看门狗（前台 1s 心跳；5s/12s/18s/25s 阈值；冷却 ≥4s）
  // -------------------------------------------------------------------------

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogConfig.watchdogInterval, (_) {
      _recoverStalePrefillIfNeeded();
      _recoverStaleStreamIfNeeded();
      _pollContextWindowIfNeeded();
      unawaited(_runStallGuardIfNeeded());
      _recoverOrphanedStreamingPhaseIfNeeded();
    });
  }

  /// 记录一次用户动作（#127 静默兜底的激活窗口起点）。
  void _markUserAction() {
    _lastUserActionAt = _now();
    _stallGuardCooldownUntil = null;
    _awaitingServerContent = true;
  }

  /// 静默兜底巡检（#127）：通道静默断线 + 无人恢复时的最后一道防线。
  ///
  /// 现有恢复链**全是事件驱动**的：resumed 探活、transport-stale 重连、
  /// 作答后接回通道……任一环节漏掉就表现为「界面永远静止」（「选完澄清
  /// 回复后聊天不再更新」正是如此：等待态下 resumed 探活被
  /// `!hasPendingPrompt` 门控挡掉，而清卡路径不重建通道）。
  /// 本巡检不依赖任何单一事件：只要「用户刚有过动作（发消息/作答）」而
  /// 「一段时间内没有任何服务端进展」，就主动拉一次会话把内容兜回来
  /// （`syncMissingMessages` 顺带能接管服务端新开的流）。
  /// 三重门控保证低频、不打扰：仅前台 + 仅无活跃流（有流交给 watchdog 的
  /// transport-stale 链，避免双路争抢）+ 仅用户动作后的活动窗口内 + 冷却。
  Future<void> _runStallGuardIfNeeded() async {
    if (_disposed || _appPaused) return;
    if (state.sessionId.isEmpty) return;
    // 有活跃流：交给 watchdog 的 transport-stale 重连链。
    if (state.stream.activeStreamId != null) return;
    // 正等用户作答：不该催（卡片自己的生命周期负责）。
    if (state.pendingAction.hasPendingPrompt) return;
    // 没有未决期待（收到过内容 / 回合已正常收尾）→ 不打扰。
    if (!_awaitingServerContent) return;
    // 仅在「用户刚有过动作」的窗口内激活 → 空闲会话永不触发。
    final actionAt = _lastUserActionAt;
    if (actionAt == null) return;
    final now = _now();
    if (now.difference(actionAt) > _stallGuardActiveWindow) return;
    if (_stallGuardCooldownUntil != null &&
        now.isBefore(_stallGuardCooldownUntil!)) {
      return;
    }
    // 静止判据：距「最近一次进展」超过阈值。尚无进展记录（或进展发生在
    // 本次动作之前）时以动作时刻为基线 —— 否则刚动作就会因
    // `_lastProgress == null` 被立刻判定静止。
    final lastProgress = _lastProgress;
    final baseline = (lastProgress == null || lastProgress.isBefore(actionAt))
        ? actionAt
        : lastProgress;
    if (now.difference(baseline) < _stallGuardStallThreshold) return;
    _stallGuardCooldownUntil = now.add(_stallGuardCooldown);
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat_stall_guard',
      message:
          'Stall guard: 用户动作后 ${now.difference(actionAt).inSeconds}s 无进展且无活跃流，主动拉取会话兜底',
    );
    await syncMissingMessages();
  }

  /// 死区兜底巡检（#142 A4）：消灭「streaming 但 activeStreamId == null」死区。
  ///
  /// 当「本地以为还在跑」但「流标识已丢」且「长时间无任何进展」时，
  /// 主动 [syncMissingMessages] 向服务端求证一次（该调用顺带能接管服务端新开的流）。
  void _recoverOrphanedStreamingPhaseIfNeeded({
    bool ignoreStallThreshold = false,
  }) {
    if (_disposed) return;
    if (_appPaused) return; // 后台不动作
    if (state.sessionId.isEmpty) return;
    if (state.stream.activeStreamId != null) return; // 有流 → 归 transport 链
    if (state.stream.hasCompletedResponse) return; // 已收尾
    if (state.pendingAction.hasPendingPrompt) return; // 等主人作答 → 不催
    if (!_phaseIndicatesOngoingTurn) return; // ← 死区关键判据
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    final lastProgress = _lastProgress;
    if (!ignoreStallThreshold) {
      if (lastProgress == null) return; // 从未有进展 → 交给既有 stall guard
      final now = _now();
      if (now.difference(lastProgress) <
          _watchdogConfig.deadZoneStallThreshold) {
        return;
      }
    }
    final now = _now();
    final cooldown = _deadZoneCooldownUntil;
    if (cooldown != null && now.isBefore(cooldown)) return;
    _deadZoneCooldownUntil = now.add(_watchdogConfig.deadZoneCooldown);
    final lastProgressAgeMs = lastProgress == null
        ? -1
        : now.difference(lastProgress).inMilliseconds;
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat_deadzone',
      message:
          'Deadzone recovery triggered: activeStreamId: null, phase: ${state.phase.name}, lastProgressAge: ${lastProgressAgeMs}ms, sessionId: ${state.sessionId}',
    );
    unawaited(syncMissingMessages());
  }

  void _recoverStalePrefillIfNeeded() {
    if (_disposed || _appPaused) return;
    final status = state.prefillStatus;
    if (status != ContextPrefillStatus.loading &&
        status != ContextPrefillStatus.notConfigured) {
      _prefillSince = null;
      return;
    }
    final since = _prefillSince;
    if (since == null) {
      _prefillSince = _now();
      return;
    }
    if (_now().difference(since) >= _prefillStaleTimeout) {
      _prefillSince = null;
      state = state.copyWith(clearPrefillStatus: true, clearPrefillLabel: true);
      if (state.stream.activeStreamId != null &&
          !state.stream.hasCompletedResponse) {
        unawaited(_checkStatusAndReconnect());
      }
    }
  }

  void _recoverStaleStreamIfNeeded() {
    if (_disposed) return;
    if (_appPaused) return; // 修复③后台/锁屏豁免看门狗（冻结计时器不判超时）
    if (state.stream.activeStreamId == null) return;
    if (state.stream.hasCompletedResponse) return;
    if (state.pendingAction.hasPendingPrompt) return; // 卡片期间暂停
    final config = _watchdogConfig;
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    if (_reconnectAttempts >= config.effectiveMaxReconnectAttempts) return;
    final now = _now();
    final lastProgress = _lastProgress;
    final lastTransport = _lastTransportActivity;
    final hasRunningTools = _hasRunningTools;

    final isTransportFresh =
        lastTransport != null &&
        now.difference(lastTransport) < config.transportFreshThreshold;

    final isNormalStale =
        lastProgress != null &&
        now.difference(lastProgress) >= config.progressStaleThreshold &&
        lastTransport != null &&
        now.difference(lastTransport) >= config.transportStaleThreshold;
    final isToolProgressStale =
        !isTransportFresh &&
        hasRunningTools &&
        lastProgress != null &&
        now.difference(lastProgress) >= config.forceReconnectThreshold;

    if (isNormalStale || isToolProgressStale) {
      final cooldown = _statusCheckCooldownUntil;
      if ((cooldown == null || now.isAfter(cooldown)) &&
          (_statusPollJitterTimer == null ||
              !_statusPollJitterTimer!.isActive)) {
        final jitter = config.jitterForAttempt();
        _statusCheckCooldownUntil = now.add(config.statusPollCooldown + jitter);
        if (jitter <= Duration.zero) {
          DiagnosticsService.instance.log(
            level: DiagnosticsLogLevel.warn,
            tag: 'chat_watchdog',
            message:
                'Watchdog detected stale stream activity${hasRunningTools ? ' during tool execution' : ''}, polling status (session: ${state.sessionId})',
          );
          state = state.copyWith(
            stream: state.stream.copyWith(
              recovery: ActiveStreamRecoveryState.checking,
            ),
          );
          unawaited(_checkStatusAndReconnect());
        } else {
          final streamId = state.stream.activeStreamId;
          final gen = _generation;
          _statusPollJitterTimer = Timer(jitter, () {
            _statusPollJitterTimer = null;
            if (_disposed || gen != _generation) return;
            if (_appPaused) return;
            if (state.stream.activeStreamId != streamId) return;
            if (state.stream.hasCompletedResponse) return;
            if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
            if (_reconnectAttempts >= config.effectiveMaxReconnectAttempts) {
              return;
            }
            if (_forceReconnectJitterTimer != null &&
                _forceReconnectJitterTimer!.isActive) {
              return;
            }

            DiagnosticsService.instance.log(
              level: DiagnosticsLogLevel.warn,
              tag: 'chat_watchdog',
              message:
                  'Watchdog detected stale stream activity${hasRunningTools ? ' during tool execution' : ''}, polling status (session: ${state.sessionId})',
            );
            state = state.copyWith(
              stream: state.stream.copyWith(
                recovery: ActiveStreamRecoveryState.checking,
              ),
            );
            unawaited(_checkStatusAndReconnect());
          });
        }
      }
    }

    final forceThreshold = hasRunningTools
        ? config.forceReconnectWithRunningToolsThreshold
        : config.forceReconnectThreshold;
    final isTransportForce =
        lastTransport != null &&
        now.difference(lastTransport) >= forceThreshold;
    final isToolProgressForce =
        !isTransportFresh &&
        hasRunningTools &&
        lastProgress != null &&
        now.difference(lastProgress) >=
            config.forceReconnectWithRunningToolsThreshold;

    if (isTransportForce || isToolProgressForce) {
      if (_forceReconnectJitterTimer == null ||
          !_forceReconnectJitterTimer!.isActive) {
        final jitter = config.jitterForAttempt();
        final streamId = state.stream.activeStreamId!;
        if (jitter <= Duration.zero) {
          DiagnosticsService.instance.log(
            level: DiagnosticsLogLevel.error,
            tag: 'chat_watchdog',
            message:
                'Watchdog force reconnecting due to ${isToolProgressForce ? 'tool progress hang' : 'transport silence'} (session: ${state.sessionId})',
          );
          _forceReconnect(streamId, jitterMs: 0);
        } else {
          final gen = _generation;
          _forceReconnectJitterTimer = Timer(jitter, () {
            _forceReconnectJitterTimer = null;
            if (_disposed || gen != _generation) return;
            if (_appPaused) return;
            if (state.stream.activeStreamId != streamId) return;
            if (state.stream.hasCompletedResponse) return;
            if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
            if (_reconnectAttempts >= config.effectiveMaxReconnectAttempts) {
              return;
            }

            DiagnosticsService.instance.log(
              level: DiagnosticsLogLevel.error,
              tag: 'chat_watchdog',
              message:
                  'Watchdog force reconnecting due to ${isToolProgressForce ? 'tool progress hang' : 'transport silence'} (session: ${state.sessionId})',
            );
            _forceReconnect(streamId, jitterMs: jitter.inMilliseconds);
          });
        }
      }
    }
  }

  bool get _hasRunningTools => state.liveToolCalls.any((t) => !t.isCompleted);

  Future<void> _checkStatusAndReconnect({
    bool isThrottledFallback = false,
    int resumeRetries = 0,
  }) async {
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return;
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat_resume',
      message:
          'Checking stream status (streamId: $streamId, session: ${state.sessionId})',
    );
    final gen = _generation;
    try {
      final status = await _api!.chatStreamStatus(streamId);
      if (_disposed || gen != _generation) return;
      _resetReconnectBackoff();
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat_resume',
        message:
            'Stream status checked: active=${status.active}, replayAvailable=${status.replayAvailable}',
      );
      if (status.active == true) {
        await _loadMessagesAndResume(streamId);
      } else if (status.replayAvailable == true) {
        final afterSeq = _replayAfterSeq(state.stream.lastEventId);
        state = state.copyWith(
          stream: state.stream.copyWith(
            recovery: ActiveStreamRecoveryState.reconnecting,
          ),
        );
        _connectStream(
          streamId,
          replayAfterSeq: afterSeq == 0 ? null : afterSeq,
        );
        state = state.copyWith(
          stream: state.stream.copyWith(
            recovery: ActiveStreamRecoveryState.idle,
          ),
          phase: ChatPhase.streaming,
        );
        _markProgress();
      } else {
        await _finalizeAfterRecovery(streamId);
      }
    } on ApiException catch (e) {
      if (_disposed || gen != _generation) return;
      // #100 F2：resume 探活带重试预算——解锁瞬间 WiFi/frp 可能未就绪，
      // 失败立即转强连只会白烧重连预算；间隔重试等网络就绪。
      if (resumeRetries > 0) {
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.warn,
          tag: 'chat_resume',
          message:
              'Status check failed: $e, retrying in ${_watchdogConfig.resumeProbeRetryDelay.inMilliseconds}ms (retries left: $resumeRetries)',
        );
        _resumeProbeRetryTimer?.cancel();
        _resumeProbeRetryTimer = Timer(
          _watchdogConfig.resumeProbeRetryDelay,
          () {
            _resumeProbeRetryTimer = null;
            if (_disposed || gen != _generation) return;
            if (_appPaused) return;
            if (state.stream.activeStreamId != streamId) return;
            unawaited(
              _checkStatusAndReconnect(resumeRetries: resumeRetries - 1),
            );
          },
        );
        return;
      }
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.warn,
        tag: 'chat_resume',
        message: 'Status check failed: $e, falling back to force reconnect',
      );
      if (!isThrottledFallback) {
        _forceReconnect(streamId);
      }
    }
  }

  void _handleHeartbeat() {
    // 心跳证明传输存活：checking → idle；绝不 demote reconnecting。
    if (state.stream.recovery == ActiveStreamRecoveryState.checking) {
      state = state.copyWith(
        stream: state.stream.copyWith(recovery: ActiveStreamRecoveryState.idle),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Live 流式上下文窗口轮询（N = 2s；活跃流期间轮询；空闲零请求）
  // -------------------------------------------------------------------------

  /// Live 流式期间每 2s 轮询一次会话详情以实时刷新上下文窗口指示器读数。
  void _pollContextWindowIfNeeded() {
    if (_disposed) return;
    if (_appPaused) return;
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return;
    if (state.stream.hasCompletedResponse) return;
    if (state.sessionId.isEmpty) return;
    if (_isContextPolling) return;

    final now = _now();
    final lastPoll = _lastContextPollTime;
    if (lastPoll != null &&
        now.difference(lastPoll) < contextWindowPollInterval) {
      return;
    }

    _lastContextPollTime = now;
    unawaited(_pollContextWindow(streamId));
  }

  Future<void> _pollContextWindow(String streamId) async {
    final api = _api;
    if (api == null) return;
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    final gen = _generation;
    _isContextPolling = true;
    try {
      final response = await api.session(
        sessionId: sessionId,
        includeMessages: false,
      );
      if (_disposed || gen != _generation) return;
      if (state.stream.activeStreamId != streamId ||
          state.stream.hasCompletedResponse) {
        return;
      }
      final detail = response.session;
      if (detail == null) return;

      final prev = state.contextWindowSnapshot;
      final snapshot = ContextWindowSnapshot(
        contextLength: detail.contextLength ?? prev?.contextLength,
        thresholdTokens: detail.thresholdTokens ?? prev?.thresholdTokens,
        lastPromptTokens: detail.lastPromptTokens ?? prev?.lastPromptTokens,
        inputTokens: detail.inputTokens ?? prev?.inputTokens,
        outputTokens: detail.outputTokens ?? prev?.outputTokens,
        estimatedCost: detail.estimatedCost ?? prev?.estimatedCost,
        tokensPerSecond:
            state.stream.liveTokensPerSecond ?? prev?.tokensPerSecond,
      );
      final hasSnapshotValues =
          snapshot.contextLength != null ||
          snapshot.thresholdTokens != null ||
          snapshot.lastPromptTokens != null ||
          snapshot.inputTokens != null ||
          snapshot.outputTokens != null ||
          snapshot.estimatedCost != null;
      if (hasSnapshotValues) {
        state = state.copyWith(contextWindowSnapshot: snapshot);
      }
    } on Object {
      // 轮询静默容错：网络波动或临时异常不打断流式渲染，不报全局错误
    } finally {
      _isContextPolling = false;
    }
  }

  // -------------------------------------------------------------------------
  // 归档 / 辅助
  // -------------------------------------------------------------------------

  /// 从消息列表的 reasoning 字段提取历史推理组（按 assistant 消息锚定）。
  List<ReasoningGroup> _reasoningGroupsFromMessages(
    List<ChatMessage> messages,
    int messageOffset,
  ) {
    final groups = <ReasoningGroup>[];
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final reasoning = msg.reasoning?.trim();
      if (reasoning == null || reasoning.isEmpty) continue;
      if (msg.role != 'assistant') continue;
      final anchor = TranscriptTurnClassifier.anchorID(
        msg,
        at: i,
        messageOffset: messageOffset,
      );
      groups.add(ReasoningGroup(anchorMessageId: anchor, text: reasoning));
    }
    return groups;
  }

  void _archiveLiveReasoningIfNeeded() {
    if (state.liveReasoningText.isEmpty) return;
    final groups = _archiveLiveReasoningToGroups();
    state = state.copyWith(
      liveReasoningText: '',
      liveTimelinePoints: const [],
      completedReasoningGroups: groups,
    );
  }

  /// 幽灵行退役：把「已被权威行覆盖」的客户端临时 assistant 行摘掉。
  ///
  /// 只动 assistant 行（乐观 user 行不动），且只在**正文确实被权威行覆盖**时摘
  /// （防丢内容）：否则保留原样。空白压缩后做包含判定 —— 服务端逐轮行拼起来应
  /// 覆盖 live 行的整轮正文。
  List<ChatMessage> _retireStaleLiveRows(List<ChatMessage> messages) {
    if (messages.length < 2) return messages;
    final authoritative = StringBuffer();
    for (final message in messages) {
      if (_isClientTempRow(message)) continue;
      authoritative.write(_squeezeWhitespace(message.content ?? ''));
    }
    final authoritativeText = authoritative.toString();
    if (authoritativeText.isEmpty) return messages;
    // 空内容临时行（纯工具/纯思考轮）只在窗口里确实存在权威 assistant 行时退场，
    // 避免分页窗口边缘把「本地唯一那一行」误摘。
    final hasAuthoritativeAssistant = messages.any(
      (m) => m.role == 'assistant' && !_isClientTempRow(m),
    );
    final kept = <ChatMessage>[];
    for (final message in messages) {
      if (!_isClientTempRow(message)) {
        kept.add(message);
        continue;
      }
      final own = _squeezeWhitespace(message.content ?? '');
      // 注意判定顺序：空串被任何字符串 contains ⇒ 必须先判空。空内容临时行是
      // **纯工具/纯思考轮**的挂载行（工具组锚在它身上、由它渲染），有权威行兜底
      // 才退场；否则摘掉即等于整卡消失（todo.md #15 复现 2 的回归点）。
      if (own.isEmpty) {
        if (hasAuthoritativeAssistant) continue;
        kept.add(message);
        continue;
      }
      if (authoritativeText.contains(own)) continue;
      kept.add(message);
    }
    return kept;
  }

  bool _isClientTempRow(ChatMessage message) {
    if (message.role != 'assistant') return false;
    final id = message.messageId ?? '';
    return id.startsWith('stream-') || id.startsWith('local-');
  }

  String _squeezeWhitespace(String value) =>
      value.replaceAll(RegExp(r'\s+'), '');

  /// live 派生的归档组（`live-tools-*`）是否已被服务端分组覆盖（可安全退场）。
  ///
  /// 非 live 派生组一律返回 false（不动历史归档组的行为）。
  bool _isStaleLiveGroupCoveredByServer(
    ToolCallGroup group,
    List<ToolCallGroup> serverGroups,
  ) {
    if (!group.id.startsWith('live-tools-')) return false;
    if (serverGroups.isEmpty) return false;
    return group.isCoveredByOthers(serverGroups);
  }

  /// 最后一个用户回合内「首条带正文的 assistant」锚（整回合大卡的合法卡位）。
  ///
  /// 与 `ToolCallGroup.coalescingByAssistantTurn` 的 `firstTextAssistantAnchor`
  /// 同源：live 堆需要兜底卡位时用它，绝不回落到「末条 assistant」（那是把整轮
  /// 工具甩到回合末尾）。找不到时回落到本回合首条 assistant。
  String? _lastTurnFirstTextAnchor(List<ChatMessage> messages, int offset) {
    if (messages.isEmpty) return null;
    var start = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (TranscriptTurnClassifier.isUserTurnBoundary(messages[i])) {
        start = i;
        break;
      }
    }
    String? earliestAssistant;
    for (var i = start; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != 'assistant') continue;
      final anchor = TranscriptTurnClassifier.anchorID(
        message,
        at: i,
        messageOffset: offset,
      );
      earliestAssistant ??= anchor;
      if ((message.content ?? '').trim().isNotEmpty) return anchor;
    }
    return earliestAssistant;
  }

  String? _resolveLiveArchiveAnchor({
    required List<ChatMessage> messages,
    int? messageOffset,
    String? candidateId,
  }) {
    final offset = messageOffset ?? 0;
    if (candidateId != null && candidateId.isNotEmpty) {
      // 1. 如果 candidateId 命中某个消息的 messageId
      final index = messages.indexWhere((m) => m.messageId == candidateId);
      if (index != -1) {
        return TranscriptTurnClassifier.anchorID(
          messages[index],
          at: index,
          messageOffset: offset,
        );
      }
      // 2. 如果 candidateId 本身就是某个消息的 anchorID（例如 raw:1 或持久化 uuid）
      for (var i = 0; i < messages.length; i++) {
        final aid = TranscriptTurnClassifier.anchorID(
          messages[i],
          at: i,
          messageOffset: offset,
        );
        if (aid == candidateId) {
          return candidateId;
        }
      }
    }
    // 3. 回退到当前/最后一个 assistant 消息的 anchorID
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'assistant') {
        return TranscriptTurnClassifier.anchorID(
          messages[i],
          at: i,
          messageOffset: offset,
        );
      }
    }
    // 4. 若无 assistant 消息，且 candidateId 并非临时 ID，保留 candidateId
    if (candidateId != null &&
        !candidateId.startsWith('stream-') &&
        !candidateId.startsWith('local-') &&
        candidateId != 'unanchored') {
      return candidateId;
    }
    // 5. 若为临时流式 ID 且当前没有 assistant 消息，尝试以当前消息槽位推断 raw 锚点
    if (messages.isNotEmpty) {
      return 'raw:${(offset < 0 ? 0 : offset) + messages.length}';
    }
    return null;
  }

  List<ReasoningGroup> _archiveLiveReasoningToGroups({
    String? overrideAnchor,
    List<ChatMessage>? messages,
  }) {
    if (state.liveReasoningText.isEmpty) return state.completedReasoningGroups;
    final anchor = _resolveLiveArchiveAnchor(
      messages: messages ?? state.messages,
      messageOffset: state.messagesOffset,
      candidateId:
          overrideAnchor ??
          state.stream.reasoningAnchorMessageId ??
          state.stream.streamingAssistantMessageId,
    );
    final group = ReasoningGroup(
      anchorMessageId: anchor,
      text: state.liveReasoningText,
    );
    return ReasoningGroup.merging(
      primaryGroups: state.completedReasoningGroups,
      fallbackGroups: [group],
    );
  }

  void _archiveLiveToolCallsIfNeeded() {
    if (state.liveToolCalls.isEmpty) return;
    final groups = _archiveLiveToolCallsToGroups();
    state = state.copyWith(
      liveToolCalls: const [],
      liveTimelinePoints: const [],
      completedToolCallGroups: groups,
    );
  }

  List<ToolCallGroup> _archiveLiveToolCallsToGroups({
    String? overrideAnchor,
    List<ChatMessage>? messages,
  }) {
    if (state.liveToolCalls.isEmpty) return state.completedToolCallGroups;
    final sourceMessages = messages ?? state.messages;
    // 服务端真身已覆盖本轮 live 工具（回前台补拉后的收尾路径）→ 不再造整堆组：
    // 否则一整轮工具会被塞进一个 `live-tools-*` 组，并锚到临时锚（幽灵行）或
    // 末条 assistant 上 —— 主人现象「回合末尾攒一张 tools 超多、位置错误的卡」。
    final alreadyCoveredByServer = [
      for (final group in state.completedToolCallGroups)
        if (!group.id.startsWith('live-tools-')) group,
    ];
    if (alreadyCoveredByServer.isNotEmpty) {
      final pile = ToolCallGroup.live(
        toolCalls: List<ToolCall>.of(state.liveToolCalls),
      );
      if (pile.isCoveredByOthers(alreadyCoveredByServer)) {
        return state.completedToolCallGroups;
      }
    }
    final anchor = _resolveLiveArchiveAnchor(
      messages: sourceMessages,
      messageOffset: state.messagesOffset,
      candidateId:
          overrideAnchor ??
          state.stream.toolCallAnchorMessageId ??
          state.stream.streamingAssistantMessageId,
    );
    final group = ToolCallGroup.live(
      anchorMessageID: anchor,
      toolCalls: List<ToolCall>.of(state.liveToolCalls),
    );
    return ToolCallGroup.merging(
      primaryGroups: state.completedToolCallGroups,
      fallbackGroups: [group],
    );
  }

  List<ToolCallGroup> _reanchorGroupsToMessages(
    List<ToolCallGroup> groups,
    List<ChatMessage> messages, {
    int? messageOffset,
    String? oldStreamingId,
    String? fallbackAnchorId,
  }) {
    if (groups.isEmpty) return groups;
    final offset = messageOffset ?? 0;
    final validAnchors = <String>{};
    for (var i = 0; i < messages.length; i++) {
      validAnchors.add(
        TranscriptTurnClassifier.anchorID(
          messages[i],
          at: i,
          messageOffset: offset,
        ),
      );
      final mid = messages[i].messageId;
      if (mid != null &&
          !mid.startsWith('stream-') &&
          !mid.startsWith('local-') &&
          mid != 'unanchored') {
        validAnchors.add(mid);
      }
    }

    String? latestAssistantAnchor;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'assistant') {
        latestAssistantAnchor = TranscriptTurnClassifier.anchorID(
          messages[i],
          at: i,
          messageOffset: offset,
        );
        break;
      }
    }

    return groups.map((g) {
      final anchor = g.anchorMessageID;
      final isDead =
          anchor == null ||
          anchor == oldStreamingId ||
          anchor.startsWith('stream-') ||
          anchor.startsWith('local-') ||
          anchor == 'unanchored' ||
          !validAnchors.contains(anchor);

      if (!isDead) {
        return g;
      }

      // live 派生的归档组（`live-tools-*`）：整轮工具被堆在一组、卡位恒 false。
      final isLiveDerived = g.id.startsWith('live-tools-');
      String? newAnchor;

      if (anchor != null && anchor.isNotEmpty) {
        final idx = messages.indexWhere((m) => m.messageId == anchor);
        if (idx != -1) {
          newAnchor = TranscriptTurnClassifier.anchorID(
            messages[idx],
            at: idx,
            messageOffset: offset,
          );
        }
      }
      if (newAnchor == null &&
          oldStreamingId != null &&
          oldStreamingId.isNotEmpty) {
        final idx = messages.indexWhere((m) => m.messageId == oldStreamingId);
        if (idx != -1) {
          newAnchor = TranscriptTurnClassifier.anchorID(
            messages[idx],
            at: idx,
            messageOffset: offset,
          );
        }
      }

      if (newAnchor == null && anchor != null && anchor.startsWith('raw:')) {
        final rawNum = int.tryParse(anchor.substring(4));
        if (rawNum != null) {
          final localIdx = rawNum - offset;
          if (localIdx >= 0 && localIdx < messages.length) {
            newAnchor =
                TranscriptTurnClassifier.assistantAnchorID(
                  localIdx,
                  messages,
                  messageOffset: offset,
                ) ??
                TranscriptTurnClassifier.anchorID(
                  messages[localIdx],
                  at: localIdx,
                  messageOffset: offset,
                );
          }
        }
      }

      if (newAnchor == null) {
        if (fallbackAnchorId != null &&
            validAnchors.contains(fallbackAnchorId)) {
          newAnchor = fallbackAnchorId;
        } else if (isLiveDerived) {
          // live 派生的整堆组**不得**回落「末条 assistant」——那会把整轮工具甩到
          // 回合末尾（主人看到的「位置错误」）；改钉本回合「首条带正文的
          // assistant」，与 `coalescingByAssistantTurn` 的整回合大卡卡位同源。
          newAnchor = _lastTurnFirstTextAnchor(messages, offset);
        } else if (latestAssistantAnchor != null) {
          newAnchor = latestAssistantAnchor;
        }
      }

      if (newAnchor != null && validAnchors.contains(newAnchor)) {
        return ToolCallGroup(
          id: g.id.startsWith('live-tools-') ? 'live-tools-$newAnchor' : g.id,
          anchorMessageID: newAnchor,
          precedingMessageID: g.precedingMessageID,
          isAboveContent: g.isAboveContent,
          toolCalls: g.toolCalls,
        );
      }

      return g;
    }).toList();
  }

  List<ReasoningGroup> _reanchorReasoningToMessages(
    List<ReasoningGroup> groups,
    List<ChatMessage> messages, {
    int? messageOffset,
    String? oldStreamingId,
    String? fallbackAnchorId,
  }) {
    if (groups.isEmpty) return groups;
    final offset = messageOffset ?? 0;
    final validAnchors = <String>{};
    for (var i = 0; i < messages.length; i++) {
      validAnchors.add(
        TranscriptTurnClassifier.anchorID(
          messages[i],
          at: i,
          messageOffset: offset,
        ),
      );
      final mid = messages[i].messageId;
      if (mid != null &&
          !mid.startsWith('stream-') &&
          !mid.startsWith('local-') &&
          mid != 'unanchored') {
        validAnchors.add(mid);
      }
    }

    String? latestAssistantAnchor;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'assistant') {
        latestAssistantAnchor = TranscriptTurnClassifier.anchorID(
          messages[i],
          at: i,
          messageOffset: offset,
        );
        break;
      }
    }

    return groups.map((g) {
      final anchor = g.anchorMessageId;
      final isDead =
          anchor == null ||
          anchor == oldStreamingId ||
          anchor.startsWith('stream-') ||
          anchor.startsWith('local-') ||
          anchor == 'unanchored' ||
          !validAnchors.contains(anchor);

      if (!isDead) {
        return g;
      }

      String? newAnchor;

      if (anchor != null && anchor.isNotEmpty) {
        final idx = messages.indexWhere((m) => m.messageId == anchor);
        if (idx != -1) {
          newAnchor = TranscriptTurnClassifier.anchorID(
            messages[idx],
            at: idx,
            messageOffset: offset,
          );
        }
      }
      if (newAnchor == null &&
          oldStreamingId != null &&
          oldStreamingId.isNotEmpty) {
        final idx = messages.indexWhere((m) => m.messageId == oldStreamingId);
        if (idx != -1) {
          newAnchor = TranscriptTurnClassifier.anchorID(
            messages[idx],
            at: idx,
            messageOffset: offset,
          );
        }
      }

      if (newAnchor == null && anchor != null && anchor.startsWith('raw:')) {
        final rawNum = int.tryParse(anchor.substring(4));
        if (rawNum != null) {
          final localIdx = rawNum - offset;
          if (localIdx >= 0 && localIdx < messages.length) {
            newAnchor =
                TranscriptTurnClassifier.assistantAnchorID(
                  localIdx,
                  messages,
                  messageOffset: offset,
                ) ??
                TranscriptTurnClassifier.anchorID(
                  messages[localIdx],
                  at: localIdx,
                  messageOffset: offset,
                );
          }
        }
      }

      if (newAnchor == null) {
        if (fallbackAnchorId != null &&
            validAnchors.contains(fallbackAnchorId)) {
          newAnchor = fallbackAnchorId;
        } else if (latestAssistantAnchor != null) {
          newAnchor = latestAssistantAnchor;
        }
      }

      if (newAnchor != null && validAnchors.contains(newAnchor)) {
        return ReasoningGroup(anchorMessageId: newAnchor, text: g.text);
      }

      return g;
    }).toList();
  }

  void _rollbackOptimisticMessage(String messageId) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.messageId != messageId).toList(),
    );
  }

  void _pinNotice(String text) {
    state = state.copyWith(
      pinnedLocalNotices: [...state.pinnedLocalNotices, text],
    );
  }

  void _setSendError(String message) {
    state = state.copyWith(sendErrorMessage: message);
  }

  /// 轻提示（成功类会话操作结果）。
  void setNotice(String message) {
    state = state.copyWith(noticeMessage: message);
  }

  /// 清除轻提示。
  void dismissNotice() {
    state = state.copyWith(clearNoticeMessage: true);
  }

  ///
  /// 若指定 [index]，仅移除该位置的单条 steer 提示；若未指定（或越界），清空全部 steer 提示。
  void clearSteerHint({int? index}) {
    if (index == null) {
      state = state.copyWith(clearSteerHints: true);
      return;
    }
    if (index < 0 || index >= state.steerHints.length) return;
    final updated = List<String>.from(state.steerHints)..removeAt(index);
    state = state.copyWith(steerHints: updated);
  }

  /// 清除重试回填预填值（输入栏已消费后调用）。
  void clearComposerPrefill() {
    state = state.copyWith(clearComposerPrefill: true);
  }

  void _markProgress() {
    _lastProgress = _now();
    _prefillSince = null;
    _awaitingServerContent = false;
    // steered 是子相位：收到任意 progress 事件回到 streaming。
    if (state.phase == ChatPhase.steered) {
      state = state.copyWith(phase: ChatPhase.streaming);
    }
    if (state.stream.recovery == ActiveStreamRecoveryState.checking) {
      state = state.copyWith(
        stream: state.stream.copyWith(recovery: ActiveStreamRecoveryState.idle),
      );
    }
  }

  void _recordTransportActivity() {
    _lastTransportActivity = _now();
    _cancelJitterTimers();
  }

  Future<void> _recoverExistingStream(String activeStreamId) async {
    _resetReconnectBackoff();
    await loadMessages();
    if (_disposed) return;
    if (state.stream.activeStreamId == null) {
      state = state.copyWith(
        turnStartedMillis:
            state.turnStartedMillis ?? _now().millisecondsSinceEpoch,
        stream: state.stream.copyWith(activeStreamId: activeStreamId),
      );
    }
    if (state.stream.activeStreamId == activeStreamId && !_streamConnected) {
      _connectStream(activeStreamId, fullReconnect: true);
    }
    state = state.copyWith(
      phase: ChatPhase.streaming,
      turnStartedMillis:
          state.turnStartedMillis ?? _now().millisecondsSinceEpoch,
      stream: state.stream.copyWith(
        hasCompletedResponse: false,
        isSuspended: false,
      ),
    );
    _syncSessionStreaming(
      state.sessionId,
      true,
      activeStreamId: activeStreamId,
      verifyInBackground: true,
    );
    _markProgress();
  }

  String? _lastAssistantMessageId(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == 'assistant' && m.messageId != null) return m.messageId;
    }
    return null;
  }

  String _resolveTitle(SessionDetail detail) {
    final title = detail.title?.trim();
    if (title == null || title.isEmpty) return 'Untitled Session';
    return title;
  }

  // -------------------------------------------------------------------------
  // replay 去重（chat_spec.md §5.6；token 粒度 + reasoning 同构）
  // -------------------------------------------------------------------------

  /// token 粒度去重。返回剩余文本 + 新游标 + 是否仍处于 replay 匹配。
  @visibleForTesting
  static ({String remainder, int newCursor, bool stillReplay})
  deduplicatedReplayToken({
    required String token,
    required String existingContent,
    required int matchedPrefixLength,
  }) {
    if (existingContent.isEmpty) {
      return (remainder: token, newCursor: 0, stillReplay: false);
    }
    var cursor = matchedPrefixLength;
    if (cursor < 0) cursor = 0;
    if (cursor > existingContent.length) cursor = existingContent.length;
    final expectedRemainder = existingContent.substring(cursor);

    if (expectedRemainder.isNotEmpty && expectedRemainder.startsWith(token)) {
      // 纯重复：游标前进。（保持 replay 态直到不匹配帧自然退出：重放流
      // 中途「追平」不代表重放结束，提前关闸会让后续旧事件帧裸追加。）
      final newCursor = cursor + token.length;
      return (
        remainder: '',
        newCursor: newCursor >= existingContent.length ? 0 : newCursor,
        stillReplay: true,
      );
    }
    if (expectedRemainder.isNotEmpty && token.startsWith(expectedRemainder)) {
      // 残余拼接。
      return (
        remainder: token.substring(expectedRemainder.length),
        newCursor: 0,
        stillReplay: true,
      );
    }
    if (existingContent.endsWith(token) || existingContent.startsWith(token)) {
      // 完全重复。
      return (remainder: '', newCursor: 0, stillReplay: true);
    }
    if (token.startsWith(existingContent)) {
      return (
        remainder: token.substring(existingContent.length),
        newCursor: 0,
        stillReplay: true,
      );
    }
    // 最大重叠扫描（existingContent 后缀 ∩ token 前缀，从大到小）。
    // 修复：单字重叠（CJK 根/因等）会导致死循环重复，需 >=2 才算有效重叠
    final maxLen = existingContent.length < token.length
        ? existingContent.length
        : token.length;
    var overlap = 0;
    for (var len = maxLen; len > 0; len--) {
      if (len == 1) continue; // 单字重叠不算，避免 CJK 单字误判
      if (existingContent.endsWith(token.substring(0, len))) {
        overlap = len;
        break;
      }
    }
    if (overlap > 0) {
      return (
        remainder: token.substring(overlap),
        newCursor: 0,
        stillReplay: true,
      );
    }
    // 皆不匹配 → 原样返回，关闭 replay。
    return (remainder: token, newCursor: 0, stillReplay: false);
  }

  /// reasoning 粒度去重（同构，游标基于已 flush 的 liveReasoningText）。
  @visibleForTesting
  static ({String remainder, int newCursor, bool stillReplay})
  deduplicatedReplayText({
    required String text,
    required String existingContent,
    required int matchedLength,
  }) {
    return deduplicatedReplayToken(
      token: text,
      existingContent: existingContent,
      matchedPrefixLength: matchedLength,
    );
  }

  /// 词单元切分：空白携带在单元尾部；无空白的 CJK 长串按 [cjkChunkSize] 切分。
  /// 拼接（join）与原始文本完全一致。
  @visibleForTesting
  static List<String> splitIntoWordUnits(String text, {int cjkChunkSize = 8}) {
    if (text.isEmpty) return const [];
    final units = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(ch);
      final isWhitespace = RegExp(r'\s').hasMatch(ch);
      if (isWhitespace || (isCjkRune(rune) && buffer.length >= cjkChunkSize)) {
        units.add(buffer.toString());
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) units.add(buffer.toString());
    return units;
  }

  /// CJK 统一表意文字 / 假名 / 谚文范围判定。
  static bool isCjkRune(int rune) {
    return (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF);
  }

  /// 缓存写入：写入最近至多 50 条消息（错误时不影响聊天主流程）。
  Future<void> _writeCacheMessages(
    String sessionId,
    List<ChatMessage> messages,
  ) async {
    if (sessionId.isEmpty || messages.isEmpty) return;
    try {
      final cacheService = ref.read(cacheServiceProvider);
      final authoritative = messages.where((m) {
        final id = m.messageId ?? m.id;
        if (id.startsWith('local-') || id.startsWith('stream-')) {
          return false;
        }
        return true;
      }).toList();
      if (authoritative.isEmpty) return;
      final takeCount = authoritative.length > 50 ? 50 : authoritative.length;
      final recentMessages = authoritative.sublist(
        authoritative.length - takeCount,
      );
      final maps = recentMessages.map(_messageToCacheJson).toList();
      await cacheService.writeMessages(sessionId: sessionId, messages: maps);
    } catch (_) {
      // 写缓存失败不得影响聊天主流程（缓存旁路设计，不吞异常原则下此处属旁路容错）。
    }
  }

  static Map<String, Object?> _messageToCacheJson(ChatMessage message) {
    final json = message.toJson();
    final id = message.messageId ?? message.id;
    json['id'] = id;
    json['message_id'] ??= id;
    return json;
  }

  // -------------------------------------------------------------------------
  // #108 会话内容与自唤醒实时同步（/api/session/stream）
  // -------------------------------------------------------------------------

  ChatSessionChannel? _sessionContentChannel;
  Timer? _sessionContentSyncDebounceTimer;
  int? _persistedMessageCount;

  @visibleForTesting
  ChatSessionChannel? get sessionContentChannelForTesting =>
      _sessionContentChannel;

  @visibleForTesting
  int? get persistedMessageCountForTesting => _persistedMessageCount;

  @visibleForTesting
  void setPersistedMessageCountForTesting(int? count) =>
      _persistedMessageCount = count;

  @visibleForTesting
  void setSessionContentChannelForTesting(ChatSessionChannel? channel) =>
      _sessionContentChannel = channel;

  @visibleForTesting
  void onSessionContentUpdatedForTesting(int serverCount) =>
      _onSessionContentUpdated(serverCount, sessionId: state.sessionId);

  @visibleForTesting
  void onServerTurnStartedForTesting(
    String streamId, {
    bool recovered = false,
    double? pendingStartedAt,
  }) => _onServerTurnStarted(
    streamId,
    sessionId: state.sessionId,
    recovered: recovered,
    pendingStartedAt: pendingStartedAt,
  );

  @visibleForTesting
  void onSessionBgTaskCompleteForTesting(Map<String, Object?> payload) =>
      _onSessionBgTaskComplete(payload, sessionId: state.sessionId);

  @visibleForTesting
  void scheduleSessionContentSyncForTesting() => _scheduleSessionContentSync();

  @visibleForTesting
  set prefillSinceForTesting(DateTime? value) => _prefillSince = value;

  @visibleForTesting
  DateTime? get prefillSinceForTesting => _prefillSince;

  @visibleForTesting
  void handleSseEventForTesting(SseEvent event) => _handleSseEvent(event);

  @visibleForTesting
  void recoverStalePrefillForTesting() => _recoverStalePrefillIfNeeded();

  @visibleForTesting
  Future<void> recoverExistingStreamForTesting(String activeStreamId) =>
      _recoverExistingStream(activeStreamId);

  @visibleForTesting
  int get reconnectAttemptsForTesting => _reconnectAttempts;

  @visibleForTesting
  set reconnectAttemptsForTesting(int value) => _reconnectAttempts = value;

  @visibleForTesting
  void setLastProgressForTesting(DateTime? value) => _lastProgress = value;

  @visibleForTesting
  DateTime? get deadZoneCooldownUntilForTesting => _deadZoneCooldownUntil;

  @visibleForTesting
  void setAppPausedForTesting(bool value) => _appPaused = value;

  @visibleForTesting
  void setStateForTesting(ChatState newState) => state = newState;

  @visibleForTesting
  void recoverOrphanedStreamingPhaseForTesting({
    bool ignoreStallThreshold = false,
  }) => _recoverOrphanedStreamingPhaseIfNeeded(
    ignoreStallThreshold: ignoreStallThreshold,
  );

  @visibleForTesting
  void setLastContextPollTimeForTesting(DateTime? value) =>
      _lastContextPollTime = value;

  void _recordPersistedMessageCount(int? count) {
    if (count != null) {
      _persistedMessageCount = count;
    }
  }

  /// 启动当前打开会话的 `/api/session/stream` 内容同步通道。
  void _startSessionContentChannel(String sessionId) {
    if (_disposed || sessionId.isEmpty) return;
    _stopSessionContentChannel();

    // 门控：开关关闭则不建连
    try {
      final enabled = ref.read(sessionContentStreamEnabledProvider);
      if (!enabled) return;
    } catch (_) {
      // 单元测试环境若无 provider 默认放行
    }

    ApiClient? client;
    final api = _api;
    if (api is ChatApiClient) {
      client = api.client;
    }
    if (client == null) return;

    final channel = ChatSessionChannel(
      dio: client.dio,
      baseUrl: client.baseUrl,
      sessionId: sessionId,
      knownCountProvider: () => _persistedMessageCount ?? state.messages.length,
      isEnabled: () {
        try {
          return ref.read(sessionContentStreamEnabledProvider);
        } catch (_) {
          return true;
        }
      },
      onSessionUpdated: (serverCount) {
        _onSessionContentUpdated(serverCount, sessionId: sessionId);
      },
      onServerTurnStarted: (streamId, {recovered = false, pendingStartedAt}) {
        _onServerTurnStarted(
          streamId,
          sessionId: sessionId,
          recovered: recovered,
          pendingStartedAt: pendingStartedAt,
        );
      },
      onBgTaskComplete: (payload) {
        _onSessionBgTaskComplete(payload, sessionId: sessionId);
      },
    );

    _sessionContentChannel = channel;
    channel.start();
  }

  /// 停止当前会话的内容同步通道与去抖计时器。
  void _stopSessionContentChannel() {
    _sessionContentSyncDebounceTimer?.cancel();
    _sessionContentSyncDebounceTimer = null;
    _sessionContentChannel?.stop();
    _sessionContentChannel?.dispose();
    _sessionContentChannel = null;
  }

  /// 处理 `session-updated` 帧：仅当前屏会话 + 无活跃回合 + count > 本地持久 count 时，
  /// 经 1s 防抖去抖触发 [syncMissingMessages]。
  void _onSessionContentUpdated(int serverCount, {required String sessionId}) {
    if (_disposed || state.sessionId != sessionId) return;

    // 若当前正在发送或流式接收中，避免与实时消息状态竞争
    if (state.stream.activeStreamId != null ||
        state.phase == ChatPhase.streaming ||
        state.phase == ChatPhase.sending) {
      return;
    }

    final localCount = _persistedMessageCount ?? state.messages.length;
    if (serverCount <= localCount) return;

    _scheduleSessionContentSync();
  }

  /// 调度增量消息同步（1s 去抖合并）。
  void _scheduleSessionContentSync() {
    if (_disposed) return;
    _sessionContentSyncDebounceTimer?.cancel();
    _sessionContentSyncDebounceTimer = Timer(const Duration(seconds: 1), () {
      if (_disposed) return;
      unawaited(syncMissingMessages());
    });
  }

  /// 处理 `server_turn_started` 帧：当前会话匹配且无活跃回合时 attach 服务端自唤醒回合。
  void _onServerTurnStarted(
    String streamId, {
    required String sessionId,
    bool recovered = false,
    double? pendingStartedAt,
  }) {
    if (_disposed || state.sessionId != sessionId) return;

    // 同 streamId 幂等 bail
    if (state.stream.activeStreamId == streamId) return;

    // 当前有活跃 stream 或非空闲状态时不抢占
    if (state.stream.activeStreamId != null ||
        state.phase == ChatPhase.streaming ||
        state.phase == ChatPhase.sending) {
      return;
    }

    if (recovered) {
      unawaited(
        _attachRecoveredServerTurn(
          streamId,
          pendingStartedAt: pendingStartedAt,
        ),
      );
    } else {
      if (pendingStartedAt != null) {
        state = state.copyWith(
          turnStartedMillis: (pendingStartedAt * 1000).toInt(),
        );
      }
      _beginStream(streamId);
    }
  }

  /// 恢复附加 mid-flight 的服务端自唤醒回合（带 replay 参数重放）。
  Future<void> _attachRecoveredServerTurn(
    String streamId, {
    double? pendingStartedAt,
  }) async {
    _resetReconnectBackoff();
    await loadMessages();
    if (_disposed || state.sessionId.isEmpty) return;

    final startedMillis = pendingStartedAt != null
        ? (pendingStartedAt * 1000).toInt()
        : (state.turnStartedMillis ?? _now().millisecondsSinceEpoch);

    state = state.copyWith(
      phase: ChatPhase.streaming,
      clearSendErrorMessage: true,
      clearErrorMessage: true,
      clearPrefillStatus: true,
      clearPrefillLabel: true,
      turnStartedMillis: startedMillis,
      stream: state.stream.copyWith(
        activeStreamId: streamId,
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
        hasCompletedResponse: false,
        isCancelling: false,
      ),
      pendingAction: const ChatPendingActionState(),
      responseCompletionNeedsTranscriptRefresh: false,
    );

    // 重锚定 assistant 消息或确保气泡
    final lastAssistant = _lastAssistantMessageId(state.messages);
    if (lastAssistant != null) {
      state = state.copyWith(
        stream: state.stream.copyWith(
          streamingAssistantMessageId: lastAssistant,
        ),
      );
    } else {
      _ensureStreamingAssistantMessage();
    }

    _syncSessionStreaming(
      state.sessionId,
      true,
      activeStreamId: streamId,
      verifyInBackground: true,
    );

    // 以 replayAfterSeq: 0 进行 attach，重放流式 token
    _connectStream(streamId, replayAfterSeq: 0);
    _lastContextPollTime = _now();
    _markProgress();
    _recordTransportActivity();
  }

  /// 处理 `bg_task_complete` 帧：记入 DiagnosticsService log，并触发增量消息拉取（1s 去抖）。
  void _onSessionBgTaskComplete(
    Map<String, Object?> payload, {
    required String sessionId,
  }) {
    if (_disposed || state.sessionId != sessionId) return;
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.info,
      tag: 'chat_session_channel',
      message:
          'Background task complete received for session $sessionId: $payload',
    );
    _scheduleSessionContentSync();
  }
}
