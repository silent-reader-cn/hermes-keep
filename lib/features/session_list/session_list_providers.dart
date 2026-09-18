import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_sessions.dart';
import '../../core/api/api_client_workspace.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/custom_header.dart';
import '../../core/cache/cache_providers.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/models/session.dart';
import '../../core/models/workspace.dart';
import '../desktop/desktop_lifecycle_observer.dart';
import '../onboarding/onboarding_providers.dart';
import '../settings/cron_visibility_settings.dart';

/// 会话列表所需的最小服务器 API 面（sessions 域 18 个端点中的 9 个 + workspace 域）。
///
/// 生产实现 [SessionListApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络/事件循环（对齐 onboarding 的
/// `OnboardingServerApi` 模式）。
abstract interface class SessionListApi {
  /// GET /api/sessions → 全部会话（服务端一次全量返回，无分页参数）。
  Future<SessionsResponse> fetchSessions({
    bool includeArchived = false,
    int? archivedLimit,
  });

  /// GET /api/sessions/search?q=…（标题 + 内容搜索）。
  Future<SessionSearchResponse> searchSessions({required String query});

  /// POST /api/session/new {workspace?} → 新会话摘要。
  Future<SessionSummary> createSession({String? workspace});

  /// GET /api/workspaces → 全部已注册工作区。
  Future<List<WorkspaceRoot>> fetchWorkspaces();

  /// POST /api/session/pin {session_id, pinned}。
  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  });

  /// POST /api/session/archive {session_id, archived}。
  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  });

  /// POST /api/session/delete {session_id}。
  Future<SessionMutationResponse> deleteSession(String sessionId);

  /// POST /api/session/branch {session_id} → 新分支会话。
  Future<SessionBranchResponse> branchSession(String sessionId);

  /// POST /api/session/move {session_id, project_id}；project_id 为 null = 移出项目。
  Future<SessionMutationResponse> moveSession({
    required String sessionId,
    String? projectId,
  });

  /// GET /api/session/status?session_id=… → 单会话状态校验与流式状态。
  Future<SessionStatusResponse> fetchSessionStatus(String sessionId);
}

/// [SessionListApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class SessionListApiClient implements SessionListApi {
  SessionListApiClient(this._client);

  final ApiClient _client;

  @override
  Future<SessionsResponse> fetchSessions({
    bool includeArchived = false,
    int? archivedLimit,
  }) async {
    return _client.sessions(
      includeArchived: includeArchived,
      archivedLimit: archivedLimit,
    );
  }

  @override
  Future<SessionSearchResponse> searchSessions({required String query}) async {
    return _client.searchSessions(query: query);
  }

  @override
  Future<SessionSummary> createSession({String? workspace}) async {
    // ⚠️ 2026-08：_client.createSession() 已返回 typed SessionResponse，
    // 这里直接取 session 字段；曾把 raw 经 _asMap 二次解析（raw 非 Map →
    // 空 map）导致下方容错链全部落空，恒返回空 SessionSummary。
    final response = await _client.createSession(workspace: workspace);
    final detail = response.session;
    return detail == null
        ? const SessionSummary()
        : SessionSummary.fromDetail(detail);
  }

  @override
  Future<List<WorkspaceRoot>> fetchWorkspaces() async {
    final response = await _client.workspaces();
    return response.workspaces ?? const [];
  }

  @override
  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    return _client.pinSession(sessionId: sessionId, pinned: pinned);
  }

  @override
  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    return _client.archiveSession(sessionId: sessionId, archived: archived);
  }

  @override
  Future<SessionMutationResponse> deleteSession(String sessionId) async {
    return _client.deleteSession(sessionId);
  }

  @override
  Future<SessionBranchResponse> branchSession(String sessionId) async {
    return _client.branchSession(sessionId: sessionId);
  }

  @override
  Future<SessionMutationResponse> moveSession({
    required String sessionId,
    String? projectId,
  }) async {
    return _client.moveSession(sessionId: sessionId, projectId: projectId);
  }

  @override
  Future<SessionStatusResponse> fetchSessionStatus(String sessionId) async {
    return _client.sessionStatus(sessionId);
  }
}

/// 构建 [SessionListApi] 的工厂（测试可 override 注入 fake）。
typedef SessionListApiFactory = SessionListApi Function(ApiClient client);

final sessionListApiFactoryProvider = Provider<SessionListApiFactory>(
  (ref) => SessionListApiClient.new,
);

/// 会话列表分区（对齐 Hermex `SessionListSection.Kind`：scheduled/pinned/today/yesterday/earlier）。
class SessionListSection {
  const SessionListSection({required this.title, required this.sessions});

  /// 分区标题（定时 / 置顶 / 今天 / 昨天 / 更早；搜索模式为「搜索结果」）。
  final String title;

  /// 分区内的会话（已按时间倒序）。
  final List<SessionSummary> sessions;
}

/// 会话列表筛选模式：全部 / 已归档 / 来源标签 / 项目。
enum SessionListFilterMode { all, archived, source, project }

/// 会话列表状态（AsyncNotifier 的 AsyncData 载荷）。
///
/// 分页说明：服务端 `GET /api/sessions` 一次全量返回（无 offset/limit 参数，
/// Hermex 原生亦为一次拉取），因此「分页」在客户端做分块渲染——[visibleCount]
/// 是 [displaySessions] 前 N 条的可见窗口，[loadMore] 展开窗口，配合无限滚动。
class SessionListState {
  const SessionListState({
    this.sessions = const [],
    this.visibleCount = 0,
    this.searchQuery,
    this.searchResults,
    this.isSearching = false,
    this.actionError,
    this.filterMode = SessionListFilterMode.all,
    this.filterValue,
    this.archivedSessions = const [],
    this.archivedCount,
    this.selectedSessionIds = const {},
    this.isSelectionMode = false,
    this.lastRefreshAt,
    this.lastAttemptAt,
    this.refreshing = false,
    this.consecutiveFailures = 0,
    this.showSubagent = false,
  });

  /// 普通模式全部已加载会话（服务端顺序：新的在前）。
  final List<SessionSummary> sessions;

  /// 分页窗口：`displaySessions` 前 [visibleCount] 条可见。
  final int visibleCount;

  /// 非空 = 搜索模式。
  final String? searchQuery;

  /// 远程搜索命中结果。
  final List<SessionSummary>? searchResults;

  /// 远程搜索请求进行中。
  final bool isSearching;

  /// 最近一次行操作/搜索错误（UI 弹窗展示后调用 [SessionListController.clearActionError] 清除）。
  final String? actionError;

  /// 当前筛选模式（默认全部）。
  final SessionListFilterMode filterMode;

  /// 筛选模式的对应值：来源筛选 = sourceLabel；项目筛选 = projectId；其余为 null。
  final String? filterValue;

  /// 归档会话（`fetchSessions(includeArchived: true)` 的结果，仅归档模式展示）。
  final List<SessionSummary> archivedSessions;

  /// 服务端归档总数（普通模式响应不返回 archived_count 时为 null，UI 不显示计数）。
  final int? archivedCount;

  /// 多选模式下已勾选的会话 ID 集合。
  final Set<String> selectedSessionIds;

  /// 是否处于多选模式（长按行进入）。
  final bool isSelectionMode;

  /// 最近一次成功刷新时间（UTC）。
  final DateTime? lastRefreshAt;

  /// 最近一次刷新尝试时间（含失败）。
  final DateTime? lastAttemptAt;

  /// 当前是否有刷新在途（供 UI 展示菊花与禁用按钮）。
  final bool refreshing;

  /// 连续失败次数（指数退避用；成功清零）。
  final int consecutiveFailures;

  /// 是否在列表中显示 subagent 会话（全局视图过滤；默认 false = 隐藏）。
  final bool showSubagent;

  /// 客户端分块页大小。
  static const int pageSize = 50;

  /// 来源标签的 distinct 列表（从普通模式列表收集，空标签剔除；
  /// 隐藏 subagent 会话时其 `Subagent` 来源标签一并剔除，保持与视图一致）。
  List<String> get sourceLabels {
    final seen = <String>{};
    final labels = <String>[];
    for (final session in sessions) {
      if (!showSubagent && session.isDelegatedSubagentSession) continue;
      final label = session.sourceLabel?.trim();
      if (label == null || label.isEmpty || seen.contains(label)) continue;
      seen.add(label);
      labels.add(label);
    }
    return labels;
  }

  /// 当前展示的会话（搜索模式 = 搜索命中；否则按筛选模式取对应子集）。
  ///
  /// 自动过滤空占位会话（`shouldAppearInSessionList`：无消息且无 sidebar 状态的
  /// Untitled 会话不展示，对齐 Hermex 蓝本与后端 `#1171` 规范）。另外
  /// [showSubagent] 为 false（默认）时隐藏所有 subagent 会话
  /// （`isDelegatedSubagentSession`）：它是全局视图过滤，独立于 [filterMode]
  /// 三段单选，对搜索命中同样生效。
  List<SessionSummary> get displaySessions {
    final query = searchQuery?.trim();
    final List<SessionSummary> base;
    if (query != null && query.isNotEmpty) {
      base = searchResults ?? const [];
    } else {
      switch (filterMode) {
        case SessionListFilterMode.archived:
          base = archivedSessions;
        case SessionListFilterMode.source:
          final label = filterValue;
          if (label == null || label.isEmpty) {
            base = sessions;
          } else {
            base = sessions
                .where((s) => s.sourceLabel?.trim() == label)
                .toList();
          }
        case SessionListFilterMode.project:
          final projectId = filterValue;
          if (projectId == null || projectId.isEmpty) {
            base = sessions;
          } else {
            base = sessions.where((s) => s.projectId == projectId).toList();
          }
        case SessionListFilterMode.all:
          base = sessions;
      }
    }
    return base
        .where((s) => s.shouldAppearInSessionList)
        .where((s) => showSubagent || !s.isDelegatedSubagentSession)
        .toList();
  }

  /// 是否还有更多可分页内容。
  bool get hasMore => visibleCount < displaySessions.length;

  SessionListState copyWith({
    List<SessionSummary>? sessions,
    int? visibleCount,
    String? Function()? searchQuery,
    List<SessionSummary>? Function()? searchResults,
    bool? isSearching,
    String? Function()? actionError,
    SessionListFilterMode? filterMode,
    String? Function()? filterValue,
    List<SessionSummary>? archivedSessions,
    int? Function()? archivedCount,
    Set<String>? selectedSessionIds,
    bool? isSelectionMode,
    DateTime? Function()? lastRefreshAt,
    DateTime? Function()? lastAttemptAt,
    bool? refreshing,
    int? consecutiveFailures,
    bool? showSubagent,
  }) {
    return SessionListState(
      sessions: sessions ?? this.sessions,
      visibleCount: visibleCount ?? this.visibleCount,
      searchQuery: searchQuery != null ? searchQuery() : this.searchQuery,
      searchResults: searchResults != null
          ? searchResults()
          : this.searchResults,
      isSearching: isSearching ?? this.isSearching,
      actionError: actionError != null ? actionError() : this.actionError,
      filterMode: filterMode ?? this.filterMode,
      filterValue: filterValue != null ? filterValue() : this.filterValue,
      archivedSessions: archivedSessions ?? this.archivedSessions,
      archivedCount: archivedCount != null
          ? archivedCount()
          : this.archivedCount,
      selectedSessionIds: selectedSessionIds ?? this.selectedSessionIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      lastRefreshAt: lastRefreshAt != null
          ? lastRefreshAt()
          : this.lastRefreshAt,
      lastAttemptAt: lastAttemptAt != null
          ? lastAttemptAt()
          : this.lastAttemptAt,
      refreshing: refreshing ?? this.refreshing,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      showSubagent: showSubagent ?? this.showSubagent,
    );
  }

  @override
  String toString() =>
      'SessionListState(sessions: ${sessions.length}, visibleCount: $visibleCount, '
      'searchQuery: $searchQuery, searchResults: ${searchResults?.length})';
}

/// 批量操作结果统计。
class BatchMutationResult {
  const BatchMutationResult({this.succeeded = 0, this.failed = 0});

  /// 成功操作数。
  final int succeeded;

  /// 失败操作数。
  final int failed;

  @override
  String toString() =>
      'BatchMutationResult(succeeded: $succeeded, failed: $failed)';
}

/// 会话列表控制器：加载 / 刷新 / 搜索 / 筛选 / 分页 / 行操作 / 批量操作。
///
/// AsyncValue 语义：`AsyncData` 携带 [SessionListState]；初始加载与下拉刷新
/// 失败 → `AsyncError`（UI 展示错误态 + 重试）；行操作失败不改变列表，
/// 只设置 [SessionListState.actionError] 供弹窗提示。
final sessionListControllerProvider =
    AsyncNotifierProvider<SessionListController, SessionListState>(
      SessionListController.new,
    );

/// 流式状态看门狗超时：本地乐观置位后若长时间收不到任何收尾确认
/// （窗口失焦时 SSE 与周期轮询均已停），到点主动向服务端求证一次。
/// 取值需远大于正常回合时长，避免误伤长任务；测试可覆写以缩短等待。
Duration sessionStreamingWatchdogTimeout = const Duration(minutes: 5);

class SessionListController extends AsyncNotifier<SessionListState> {
  /// 页大小（客户端分块）。
  static const int pageSize = SessionListState.pageSize;

  /// subagent 会话显隐持久化 key（默认关闭：false = 隐藏）。
  static const String keyShowSubagent = 'session_list_show_subagent';

  /// 读取 subagent 会话显隐偏好（默认 false）；[customPrefs] 供测试注入。
  static Future<bool> loadShowSubagentPref({
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keyShowSubagent) ?? false;
    } catch (_) {
      // 测试环境无 shared_preferences 插件时静默回落为 false。
      return false;
    }
  }

  /// 自动重登进行中标记（防并发重复登录）。
  bool _reauthInFlight = false;

  /// 刷新在途标记（并发互斥）。
  bool _refreshInFlight = false;

  /// 刷新重试标记（在途时收到刷新请求则置位，当前轮结束后自动补拉一次）。
  bool _refreshDirty = false;

  /// 控制器是否已释放标记。
  bool _disposed = false;

  /// 会话变更推送事件（SSE）800ms 防抖计时器。
  Timer? _eventsDebounceTimer;

  /// 阶梯补拉活跃计时器集合。
  final List<Timer> _activeLadderTimers = [];

  @visibleForTesting
  bool get isRefreshDirtyForTesting => _refreshDirty;

  @visibleForTesting
  bool get isRefreshInFlightForTesting => _refreshInFlight;

  @visibleForTesting
  Timer? get eventsDebounceTimerForTesting => _eventsDebounceTimer;

  /// 用户是否已手动切换过 subagent 开关（防后台偏好加载覆盖即时操作）。
  bool _showSubagentCustomized = false;

  /// 冷启动静默宽限是否已启动标记。
  bool _hasStartedGrace = false;

  /// 本地记录的活跃流式会话映射（sessionId -> activeStreamId）。
  ///
  /// 用于本地乐观置位与跨全量刷新保持流式指示，流结束或后台纠偏后移除。
  final Map<String, String?> _streamingSessions = {};

  /// sessionId → 该会话的流式状态看门狗定时器。
  final Map<String, Timer> _streamingWatchdogs = {};

  /// 将本地活跃流式状态覆盖到会话列表上（避免全量拉取响应时因服务端延迟抖动丢失流式状态）。
  List<SessionSummary> _overlayStreaming(List<SessionSummary> list) {
    if (_streamingSessions.isEmpty) return list;
    return [
      for (final s in list)
        if (s.sessionId != null && _streamingSessions.containsKey(s.sessionId))
          s.withStreaming(
            isStreaming: true,
            activeStreamId: _streamingSessions[s.sessionId],
          )
        else
          s,
    ];
  }

  /// Provider 侧的单测用单次调度与获焦 debounce（真正的 30s 周期在
  /// Observer 的 State 侧 `Timer.periodic`）。
  Timer? _autoRefreshTimer;
  Timer? _focusDebounceTimer;

  SessionListApi get _api =>
      ref.read(sessionListApiFactoryProvider)(ref.read(apiClientProvider));

  /// 判断当前激活连接是否为内置 sidecar 连接。
  bool _isBuiltinConnection() {
    final active = ref.read(activeConnectionProvider);
    return active != null &&
        (active.kind == ConnectionKind.builtin ||
            active.id == ServerConnection.builtinId);
  }

  @override
  Future<SessionListState> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(sessionListApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    ref.onDispose(() {
      _disposed = true;
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
      _focusDebounceTimer?.cancel();
      _focusDebounceTimer = null;
      _eventsDebounceTimer?.cancel();
      _eventsDebounceTimer = null;
      for (final t in _activeLadderTimers) {
        t.cancel();
      }
      _activeLadderTimers.clear();
      for (final t in _streamingWatchdogs.values) {
        t.cancel();
      }
      _streamingWatchdogs.clear();
    });
    final loaded = await _loadFirstPage(api, isColdStart: true);
    // 首屏状态就绪后再后台读取本地「显示 subagent 会话」偏好并回填
    // （不阻塞 build 完成；对齐 CronVisibilityController 的异步加载模式，
    // widget 测试无 prefs mock 时 SharedPreferences.getInstance() 会挂起，
    // 不能直接 await 在 build 里）。
    unawaited(_applyStoredShowSubagent());
    return loaded;
  }

  /// 读取本地偏好并回填 [SessionListState.showSubagent]；仅当用户尚未手动
  /// 切换过（[_showSubagentCustomized]）时生效，避免覆盖即时操作。
  Future<void> _applyStoredShowSubagent() async {
    final value = await loadShowSubagentPref();
    if (_showSubagentCustomized) return;
    final current = state.valueOrNull;
    if (current == null || current.showSubagent == value) return;
    state = AsyncData(current.copyWith(showSubagent: value));
  }

  /// 轮询重试退避间隔（秒）：30 * 2^n capped 120s。
  static Duration nextAutoRefreshDelay(int consecutiveFailures) {
    if (consecutiveFailures <= 0) return const Duration(seconds: 30);
    final exp = 30 * (1 << consecutiveFailures);
    return Duration(seconds: exp.clamp(30, 120));
  }

  /// 启动可见性驱动轮询（幂等）；外部可传入自定义周期（测试注入）。
  /// 真正的 30s 周期由 [SessionAutoRefreshObserver] 的 State Timer 驱动，
  /// 此方法仅为 Controller 单测提供单次调度入口，避免 Provider 侧持有
  /// `Timer.periodic` 导致测试 tree dispose 后 `!timersPending` 失败。
  void scheduleAutoRefresh({Duration? period}) {
    _autoRefreshTimer?.cancel();
    final effective =
        period ??
        nextAutoRefreshDelay(state.valueOrNull?.consecutiveFailures ?? 0);
    _autoRefreshTimer = Timer(effective, () {
      _autoRefreshTimer = null;
      unawaited(refreshIfStale());
    });
  }

  /// 停止周期轮询。
  void cancelAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// 取消获焦 debounce。
  void cancelFocusDebounce() {
    _focusDebounceTimer?.cancel();
    _focusDebounceTimer = null;
  }

  /// 指数退避：上次尝试刚记录但尚未建立成功时 caller 可根据此值决定下次调度。
  Duration get currentBackoffDelay =>
      nextAutoRefreshDelay(state.valueOrNull?.consecutiveFailures ?? 0);

  /// 条件刷新：命中任一门槛则 no-op。[force] 跳过 10s 去重窗口。
  Future<void> refreshIfStale({bool force = false}) async {
    // 冷启动/错误态：state 为 null 或 hasError → 直接强制刷新。
    if (state.valueOrNull == null || state.hasError) {
      await refresh();
      return;
    }
    final current = state.valueOrNull!;
    if (_refreshInFlight || current.refreshing) {
      _refreshDirty = true;
      return;
    }
    final query = current.searchQuery?.trim();
    if (query != null && query.isNotEmpty) return;
    if (current.filterMode == SessionListFilterMode.archived) return;
    if (!force) {
      final last = current.lastRefreshAt;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 10)) {
        return;
      }
    }
    await refresh();
  }

  /// 收到会话变更推送事件（SSE）后的统一回调入口。
  /// 内部 800ms debounce（Timer 重置式合并）→ refreshIfStale(force: true)。
  void onSessionsChangedEvent({
    int? version,
    String? reason,
    String? profile,
    String? sessionId,
  }) {
    _eventsDebounceTimer?.cancel();
    _eventsDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      _eventsDebounceTimer = null;
      unawaited(refreshIfStale(force: true));
    });
  }

  /// 获焦/前台恢复时带 1s debounce 的调度+刷新。
  void scheduleFocusRefresh() {
    _focusDebounceTimer?.cancel();
    _focusDebounceTimer = Timer(const Duration(seconds: 1), () {
      unawaited(refreshIfStale());
    });
  }

  /// 冷启动首屏"快速失败"静默重试的退避间隔（#111）。
  static const Duration coldStartRetryBackoff = Duration(milliseconds: 1500);

  /// 冷启动首屏失败是否值得静默重试一次（#111）。
  ///
  /// 只补偿**网络类快速失败**：
  /// - `cannotConnect` / `cannotFindHost` / `offline`：连接层抖动（sidecar
  ///   刚拉起、frp 隧道刚重连、进程刚被系统回收）一次重试即可自愈；
  /// - `502/503/504`：网关侧瞬断。
  ///
  /// 明确不补偿：`timedOut`（receiveTimeout 已耗尽 120s 预算，再等一轮会让
  /// 首屏空窗翻倍——此时走离线缓存 / 冷启动静默宽限更友好）、`401`（走自动
  /// 重登链）、`500`（服务端逻辑错，重试大概率同样失败，保持错误态让用户
  /// 看到真因）。
  static bool shouldRetryColdStartFetch(ApiException error) {
    if (error is NetworkException) {
      return error.kind == NetworkExceptionKind.cannotConnect ||
          error.kind == NetworkExceptionKind.cannotFindHost ||
          error.kind == NetworkExceptionKind.offline;
    }
    if (error is HttpException) {
      return const {502, 503, 504}.contains(error.statusCode);
    }
    return false;
  }

  /// 首屏拉取：冷启动 + 网络类快速失败 → 退避 [coldStartRetryBackoff] 后
  /// 静默重试一次（仅一次，防雪崩；401 原样抛出交给自动重登链）。
  ///
  /// **内置连接不补偿**：其冷启动有专属的静默宽限状态机（#72，轮询
  /// `/health` + 显示离线缓存，本身就不会红屏），首屏失败是宽限的触发条件，
  /// 抢先重试会绕过该契约；远程/自建连接没有宽限，才是本条补偿的对象。
  Future<SessionsResponse> _fetchSessionsFirstPage(
    SessionListApi api, {
    required bool isColdStart,
  }) async {
    try {
      return await api.fetchSessions();
    } on ApiException catch (error) {
      // 顺序有意：先跑纯函数判据，再读连接状态（读 provider 有副作用/可能抛）。
      final compensate =
          isColdStart &&
          shouldRetryColdStartFetch(error) &&
          !_isBuiltinConnectionOrUnknown();
      if (!compensate) rethrow;
      await Future<void>.delayed(coldStartRetryBackoff);
      return api.fetchSessions();
    }
  }

  /// [_isBuiltinConnection] 的容错版：连接状态读不到（初始化极早期、
  /// 无 flutter_secure_storage 插件的测试容器）时按「内置」保守处理，
  /// 即不补偿——不确定就不改变既有行为。
  bool _isBuiltinConnectionOrUnknown() {
    try {
      return _isBuiltinConnection();
    } on Object {
      return true;
    }
  }

  /// 加载第一页；401 时自动用保存的密码重登一次再重试
  /// （防递归：`[allowAutoReauth]` 只放行一轮）。
  Future<SessionListState> _loadFirstPage(
    SessionListApi api, {
    bool allowAutoReauth = true,
    bool showSubagent = false,
    bool isColdStart = false,
  }) async {
    try {
      final response = await _fetchSessionsFirstPage(
        api,
        isColdStart: isColdStart,
      );
      final rawSessions = response.sessions ?? const <SessionSummary>[];
      final sessions = _overlayStreaming(rawSessions);
      try {
        await ref.read(cacheServiceProvider).writeSessions(sessions);
      } on Exception {
        // 缓存不可用（例如测试环境没有 path_provider）不阻塞在线列表。
      }
      return SessionListState(
        sessions: sessions,
        visibleCount: min(pageSize, sessions.length),
        // 普通模式响应不返回 archived_count 时为 null（UI 不显示计数）。
        archivedCount: response.archivedCount,
        showSubagent: showSubagent,
      );
    } on UnauthorizedException {
      // 会话过期/未登录：有保存密码时自动重登一次，成功后重试。
      // 重登失败或重试仍 401 → 直接抛错（不递归），UI 展示错误 + 重试。
      if (allowAutoReauth && await _tryAutoReauth()) {
        return _loadFirstPage(
          api,
          allowAutoReauth: false,
          showSubagent: showSubagent,
          isColdStart: isColdStart,
        );
      }
      rethrow;
    } on ApiException catch (error, stackTrace) {
      if (ApiException.shouldUseCache(error)) {
        List<SessionSummary> cached = const [];
        try {
          cached = await ref.read(cacheServiceProvider).readSessions();
        } on Exception {
          // 缓存不可用时继续抛出原网络错误。
        }
        if (cached.isNotEmpty) {
          final sessions = _overlayStreaming(cached);
          // 内置连接在冷启动期间遇到可缓存网络错误 → 进入静默宽限，暂不弹模态 actionError
          if (isColdStart && _isBuiltinConnection()) {
            _hasStartedGrace = true;
            String? healthUrl;
            try {
              final client = ref.read(apiClientProvider);
              // ApiClient 构造期已用 _normalizeBaseUrl 循环剥净尾斜杠
              //（api_client.dart:161），这里无需再判尾斜杠 —— 原先的三元
              // else 分支恒成立，属死分支，已简化。
              final rawUrl = '${client.baseUrl}/health';
              healthUrl = rawUrl.replaceAll('://0.0.0.0', '://127.0.0.1');
            } catch (_) {}
            ref
                .read(coldStartGraceControllerProvider.notifier)
                .startGrace(
                  pendingActionError: '离线缓存：当前显示最近缓存的会话',
                  healthUrl: healthUrl,
                );
            return SessionListState(
              sessions: sessions,
              visibleCount: min(pageSize, sessions.length),
              showSubagent: showSubagent,
            );
          }
          return SessionListState(
            sessions: sessions,
            visibleCount: min(pageSize, sessions.length),
            actionError: '离线缓存：当前显示最近缓存的会话',
            showSubagent: showSubagent,
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// 用当前激活连接的已保存密码重新登录（种新 cookie）。
  ///
  /// 无密码 / 登录失败 / 已有重登在进行 → 返回 false（不做自动重登）。
  Future<bool> _tryAutoReauth() async {
    if (_reauthInFlight) return false;
    final connection = ref.read(activeConnectionProvider);
    if (connection == null) return false;
    final password = connection.password;
    if (password == null || password.isEmpty) return false;
    _reauthInFlight = true;
    try {
      final factory = ref.read(onboardingApiFactoryProvider);
      final api = factory(connection.baseUrl, [
        for (final entry in connection.customHeaders.entries)
          CustomHeader(name: entry.key, value: entry.value),
      ]);
      await api.login(password);
      return true;
    } on Exception {
      return false;
    } finally {
      _reauthInFlight = false;
    }
  }

  /// 下拉刷新 / 错误态重试：重新加载第一页并重置分页窗口。
  Future<void> refresh() async {
    if (_refreshInFlight) {
      _refreshDirty = true;
      return;
    }
    _refreshInFlight = true;
    if (_hasStartedGrace) {
      _hasStartedGrace = false;
      ref.read(coldStartGraceControllerProvider.notifier).cancelGrace();
    }
    final previous = state.valueOrNull;
    final hadData = previous != null;
    if (hadData) {
      state = AsyncData(
        previous.copyWith(
          refreshing: true,
          lastAttemptAt: () => DateTime.now().toUtc(),
        ),
      );
    }
    try {
      final api = _api;
      final now = DateTime.now().toUtc();
      // 保留用户当前的 subagent 显隐开关，避免刷新把已开启的开关重置为默认。
      final result = await _loadFirstPage(
        api,
        showSubagent: previous?.showSubagent ?? false,
        isColdStart: false,
      );
      // 离线缓存兜底返回的也算作“失败但有缓存”（actionError 以 离线缓存 开头），需走失败分支
      final isCachedFallback =
          result.actionError != null && result.actionError!.startsWith('离线缓存');
      if (isCachedFallback && hadData) {
        final prev = previous;
        final failed = prev.copyWith(
          refreshing: false,
          lastAttemptAt: () => now,
          consecutiveFailures: prev.consecutiveFailures + 1,
          // 保持缓存覆盖的会话/可见窗口一致
          sessions: result.sessions,
          visibleCount: result.visibleCount,
          actionError: () => result.actionError,
        );
        state = AsyncData(failed);
        return;
      }
      // 刷新语义是「重载第一页数据」，不该顺带重置用户的视图态：
      // _loadFirstPage 返回的是全新 state（不含 searchQuery / searchResults /
      // filterMode / filterValue / archivedSessions），以 result 作 copyWith
      // 基底会把搜索态、归档态、来源/项目筛选静默清掉。注意失败分支用的是
      // previous.copyWith（保留），即「成功丢、失败不丢」的不对称 —— 此处补回。
      final withRefresh = result.copyWith(
        searchQuery: () => previous?.searchQuery,
        searchResults: () => previous?.searchResults,
        filterMode: previous?.filterMode ?? SessionListFilterMode.all,
        filterValue: () => previous?.filterValue,
        archivedSessions: previous?.archivedSessions,
        archivedCount: () => previous?.archivedCount,
        lastRefreshAt: () => now,
        lastAttemptAt: () => now,
        refreshing: false,
        consecutiveFailures: 0,
      );
      state = AsyncData(withRefresh);
    } on Exception catch (error, stackTrace) {
      if (hadData) {
        final now = DateTime.now().toUtc();
        final prev = previous;
        final failed = prev.copyWith(
          refreshing: false,
          lastAttemptAt: () => now,
          consecutiveFailures: prev.consecutiveFailures + 1,
        );
        state = AsyncData(failed);
      } else {
        state = AsyncError(error, stackTrace);
      }
    } finally {
      _refreshInFlight = false;
      if (_refreshDirty) {
        _refreshDirty = false;
        unawaited(refresh().catchError((Object _) {}));
      }
    }
  }

  /// 分页加载：展开可见窗口（客户端分块；服务端无分页参数）。
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    final next = current.visibleCount + pageSize;
    state = AsyncData(
      current.copyWith(
        visibleCount: next < current.displaySessions.length
            ? next
            : current.displaySessions.length,
      ),
    );
  }

  /// 搜索（UI 已做防抖）：query 为空 → 退出搜索模式恢复普通列表。
  Future<void> search(String query) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = AsyncData(
        current.copyWith(
          searchQuery: () => null,
          searchResults: () => null,
          isSearching: false,
          visibleCount: min(pageSize, current.sessions.length),
        ),
      );
      return;
    }
    state = AsyncData(
      current.copyWith(searchQuery: () => trimmed, isSearching: true),
    );
    try {
      final response = await _api.searchSessions(query: trimmed);
      final rawResults = response.sessions ?? const <SessionSummary>[];
      final results = _overlayStreaming(rawResults);
      state = AsyncData(
        current.copyWith(
          searchQuery: () => trimmed,
          searchResults: () => results,
          isSearching: false,
          visibleCount: min(pageSize, results.length),
        ),
      );
    } on ApiException catch (error) {
      state = AsyncData(
        current.copyWith(
          searchQuery: () => trimmed,
          searchResults: () => const <SessionSummary>[],
          isSearching: false,
          actionError: () => error.message,
        ),
      );
    }
  }

  /// 清除行操作错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  /// 冷启动静默宽限超时或失败：补落暂存的 actionError（若当前尚未产生错误）。
  void applyGraceTimeout(String message) {
    _hasStartedGrace = false;
    if (!state.hasValue) return;
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.actionError == null) {
      state = AsyncData(
        current.copyWith(
          actionError: () => message,
          consecutiveFailures: current.consecutiveFailures + 1,
        ),
      );
    }
  }

  /// 切换筛选模式；来源/项目筛选为本地过滤（无需新请求），
  /// 归档模式触发 [fetchArchived] 拉取归档会话。切换时重置分页窗口并退出多选。
  Future<void> setFilter(SessionListFilterMode mode, {String? value}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final filtered = current.copyWith(
      filterMode: mode,
      filterValue: () => value,
      selectedSessionIds: const {},
      isSelectionMode: false,
    );
    state = AsyncData(
      filtered.copyWith(
        visibleCount: min(pageSize, filtered.displaySessions.length),
      ),
    );
    if (mode == SessionListFilterMode.archived) {
      await fetchArchived();
    }
  }

  /// 切换 subagent 会话显示并持久化（默认关闭；全局视图过滤，
  /// 独立于 [setFilter] 的三段单选，切换即时生效无需重拉列表）。
  Future<void> setShowSubagent(bool value) async {
    _showSubagentCustomized = true;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(showSubagent: value));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyShowSubagent, value);
    } catch (_) {
      // 测试环境无 shared_preferences 插件时静默（对齐 CronVisibilityController）。
    }
  }

  /// 拉取归档会话（`fetchSessions(includeArchived: true)`）并保存归档列表与计数；
  /// 失败时仅设置 [SessionListState.actionError]，保留旧归档数据。
  Future<void> fetchArchived() async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final response = await _api.fetchSessions(includeArchived: true);
      final rawArchived = response.sessions ?? const <SessionSummary>[];
      final archived = _overlayStreaming(rawArchived);
      state = AsyncData(
        current.copyWith(
          archivedSessions: archived,
          archivedCount: () => response.archivedCount ?? current.archivedCount,
          visibleCount: min(pageSize, archived.length),
        ),
      );
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
    }
  }

  /// 切换某会话的勾选状态；首个勾选进入多选模式，最后一个取消时退出多选模式。
  void toggleSelection(String sessionId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final selected = {...current.selectedSessionIds};
    var isSelectionMode = current.isSelectionMode;
    if (selected.contains(sessionId)) {
      selected.remove(sessionId);
      if (selected.isEmpty) isSelectionMode = false;
    } else {
      selected.add(sessionId);
      isSelectionMode = true;
    }
    state = AsyncData(
      current.copyWith(
        selectedSessionIds: selected,
        isSelectionMode: isSelectionMode,
      ),
    );
  }

  /// 全选当前筛选视图内的全部会话（进入多选模式）。
  void selectAllInSection() {
    final current = state.valueOrNull;
    if (current == null) return;
    final ids = current.displaySessions
        .map((s) => s.sessionId)
        .whereType<String>()
        .toSet();
    state = AsyncData(
      current.copyWith(selectedSessionIds: ids, isSelectionMode: true),
    );
  }

  /// 退出多选模式并清空勾选。
  void clearSelection() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(selectedSessionIds: const {}, isSelectionMode: false),
    );
  }

  /// 批量归档选中的会话（[archived] 为 false 时 = 恢复归档）；
  /// 成功项从当前视图移除，失败项计入 [BatchMutationResult.failed]
  /// 并设置 [SessionListState.actionError]。操作结束清空勾选。
  Future<BatchMutationResult> batchArchive({bool archived = true}) async {
    final current = state.valueOrNull;
    if (current == null) return const BatchMutationResult();
    final ids = current.selectedSessionIds.toList();
    if (ids.isEmpty) return const BatchMutationResult();
    var succeeded = 0;
    var failed = 0;
    final successIds = <String>[];
    for (final id in ids) {
      try {
        await _api.archiveSession(sessionId: id, archived: archived);
        succeeded++;
        successIds.add(id);
      } on ApiException {
        failed++;
      }
    }
    await _applyBatchChanges(successIds: successIds, removeFromLists: true);
    if (failed > 0) {
      await _setActionError('批量${archived ? '归档' : '恢复'}：$failed 个会话操作失败');
    }
    return BatchMutationResult(succeeded: succeeded, failed: failed);
  }

  /// 批量删除选中的会话；成功项从列表移除，清空勾选。
  Future<BatchMutationResult> batchDelete() async {
    final current = state.valueOrNull;
    if (current == null) return const BatchMutationResult();
    final ids = current.selectedSessionIds.toList();
    if (ids.isEmpty) return const BatchMutationResult();
    var succeeded = 0;
    var failed = 0;
    final successIds = <String>[];
    for (final id in ids) {
      try {
        await _api.deleteSession(id);
        succeeded++;
        successIds.add(id);
      } on ApiException {
        failed++;
      }
    }
    await _applyBatchChanges(successIds: successIds, removeFromLists: true);
    if (failed > 0) {
      await _setActionError('批量删除：$failed 个会话失败');
    }
    return BatchMutationResult(succeeded: succeeded, failed: failed);
  }

  /// 批量把选中的会话移动到 [projectId]（null = 移出项目）；
  /// 成功项本地刷新 projectId，清空勾选。
  Future<BatchMutationResult> batchMove(String? projectId) async {
    final current = state.valueOrNull;
    if (current == null) return const BatchMutationResult();
    final ids = current.selectedSessionIds.toList();
    if (ids.isEmpty) return const BatchMutationResult();
    var succeeded = 0;
    var failed = 0;
    final successIds = <String>[];
    for (final id in ids) {
      try {
        await _api.moveSession(sessionId: id, projectId: projectId);
        succeeded++;
        successIds.add(id);
      } on ApiException {
        failed++;
      }
    }
    await _applyBatchChanges(
      successIds: successIds,
      projectId: projectId,
      updateProjectId: true,
    );
    if (failed > 0) {
      await _setActionError('批量移动：$failed 个会话失败');
    }
    return BatchMutationResult(succeeded: succeeded, failed: failed);
  }

  /// 移动单个会话到项目（null = 移出项目）；成功后本地刷新该行 projectId。
  Future<bool> moveToProject(SessionSummary session, String? projectId) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return false;
    }
    try {
      await _api.moveSession(sessionId: id, projectId: projectId);
      await _updateSession(
        id,
        (s) => _replaced(s, projectId: projectId, updateProjectId: true),
      );
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 置顶 / 取消置顶；成功后本地更新该行（自动归入「置顶」分区）。
  Future<bool> setPinned(SessionSummary session, bool pinned) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return false;
    }
    try {
      await _api.pinSession(sessionId: id, pinned: pinned);
      await _updateSession(id, (s) => _replaced(s, pinned: pinned));
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 归档 / 取消归档；归档成功后从普通列表移除该行（列表默认不含已归档会话），
  /// 取消归档后从归档视图移除该行并更新普通列表。
  Future<bool> setArchived(SessionSummary session, bool archived) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return false;
    }
    try {
      await _api.archiveSession(sessionId: id, archived: archived);
      if (archived) {
        await _removeSession(id);
        await _adjustArchivedCount(1);
      } else {
        await _updateSession(id, (s) => _replaced(s, archived: false));
        await _removeArchived(id);
        await _adjustArchivedCount(-1);
      }
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 删除会话；成功后从列表移除。
  Future<bool> delete(SessionSummary session) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return false;
    }
    try {
      await _api.deleteSession(id);
      await _removeSession(id);
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 分支（复制）会话；成功返回新会话 ID（UI 跳转 /chat/:id）并插入列表顶部。
  Future<String?> branch(SessionSummary session) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return null;
    }
    try {
      final response = await _api.branchSession(id);
      final newId = response.sessionId;
      if (newId == null || newId.isEmpty) {
        await _setActionError(response.error ?? '服务器未返回分支会话 ID');
        return null;
      }
      final hasTitle =
          response.title != null && response.title!.trim().isNotEmpty;
      // 服务端未返回标题时本地兜底加 fork 后缀（对齐 hermes-webui
      // 默认命名 "<original title> (fork)"，避免刷新前后标题跳变）。
      final baseTitle = session.title == null || session.title!.trim().isEmpty
          ? null
          : session.title!.trim();
      await _insertSession(
        SessionSummary(
          sessionId: newId,
          title: hasTitle
              ? response.title
              : (baseTitle == null ? null : '$baseTitle (fork)'),
        ),
      );
      return newId;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return null;
    }
  }

  /// 新建会话（POST /api/session/new）；成功返回新会话 ID（UI 跳转 /chat/:id）。
  Future<String?> createSession({String? workspace}) async {
    try {
      final session = await _api.createSession(workspace: workspace);
      final id = session.sessionId;
      if (id == null || id.isEmpty) {
        await _setActionError('服务器未返回会话 ID');
        return null;
      }
      await _insertSession(session);
      return id;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return null;
    }
  }

  /// 新会话首条消息后会话列表即时可见（阶梯补拉）。
  ///
  /// 阶梯补拉：立即 / +600ms / +2.5s / +5.5s 各一次 `refreshIfStale(force: true)`；
  /// 任一枪的响应里已含目标 `newSessionId` 则终止后续枪。
  Future<void> handleNewChatSession(
    String newSessionId, {
    String? titleHint,
  }) async {
    if (newSessionId.isEmpty) return;

    bool containsSession() {
      final sessions = state.valueOrNull?.sessions;
      if (sessions == null) return false;
      return sessions.any(
        (s) => s.sessionId == newSessionId || s.id == newSessionId,
      );
    }

    // 立即执行第 1 枪 (0ms)
    await refreshIfStale(force: true);
    if (_disposed || containsSession()) return;

    final sessionTimers = <Timer>[];
    void cancelAll() {
      for (final t in sessionTimers) {
        t.cancel();
        _activeLadderTimers.remove(t);
      }
      sessionTimers.clear();
    }

    void scheduleStep(Duration delay) {
      late final Timer timer;
      timer = Timer(delay, () async {
        _activeLadderTimers.remove(timer);
        if (_disposed || containsSession()) {
          cancelAll();
          return;
        }
        await refreshIfStale(force: true);
        if (_disposed || containsSession()) {
          cancelAll();
        }
      });
      sessionTimers.add(timer);
      _activeLadderTimers.add(timer);
    }

    // 阶梯调度：+600ms / +2.5s / +5.5s
    scheduleStep(const Duration(milliseconds: 600));
    scheduleStep(const Duration(milliseconds: 2500));
    scheduleStep(const Duration(milliseconds: 5500));
  }

  /// 标记指定会话的流式状态（本地乐观置位 + 可选后台单会话校验）。
  ///
  /// [isStreaming] 为 true 时置位 `isStreaming` 与 `activeStreamId`；
  /// 为 false 时清空流式状态。
  /// 若 [verifyInBackground] 为 true 且处于流式状态，会异步调用
  /// `GET /api/session/status?session_id=` 单点校验/纠偏，
  /// 避免全量 `GET /api/sessions` 造成的分页窗口抖动与网络浪费。
  void markStreaming(
    String sessionId,
    bool isStreaming, {
    String? activeStreamId,
    bool verifyInBackground = false,
  }) {
    if (sessionId.isEmpty) return;
    if (isStreaming) {
      _streamingSessions[sessionId] = activeStreamId;
      _armStreamingWatchdog(sessionId);
    } else {
      _streamingSessions.remove(sessionId);
      _cancelStreamingWatchdog(sessionId);
    }
    final current = state.valueOrNull;
    if (current == null) return;

    final updatedSessions = [
      for (final s in current.sessions)
        s.sessionId == sessionId
            ? s.withStreaming(
                isStreaming: isStreaming,
                activeStreamId: activeStreamId,
              )
            : s,
    ];
    final updatedSearch = current.searchResults == null
        ? null
        : () => [
            for (final s in current.searchResults!)
              s.sessionId == sessionId
                  ? s.withStreaming(
                      isStreaming: isStreaming,
                      activeStreamId: activeStreamId,
                    )
                  : s,
          ];
    final updatedArchived = [
      for (final s in current.archivedSessions)
        s.sessionId == sessionId
            ? s.withStreaming(
                isStreaming: isStreaming,
                activeStreamId: activeStreamId,
              )
            : s,
    ];

    state = AsyncData(
      current.copyWith(
        sessions: updatedSessions,
        searchResults: updatedSearch,
        archivedSessions: updatedArchived,
      ),
    );

    if (verifyInBackground && isStreaming) {
      unawaited(_verifySessionStatus(sessionId));
    }
  }

  /// 为某会话武装流式状态看门狗（同会话重复调用即续期）。
  ///
  /// 到点后若该会话仍在 [_streamingSessions] 中，说明这段时间内没有任何
  /// 收尾确认到达（窗口失焦时 SSE 与周期轮询都会停），于是主动向服务端
  /// 求证一次；服务端确认非流式即清除，避免侧栏 loading 圈永久旋转。
  void _armStreamingWatchdog(String sessionId) {
    _cancelStreamingWatchdog(sessionId);
    _streamingWatchdogs[sessionId] = Timer(sessionStreamingWatchdogTimeout, () {
      _streamingWatchdogs.remove(sessionId);
      if (_disposed) return;
      if (!_streamingSessions.containsKey(sessionId)) return;
      unawaited(_verifySessionStatus(sessionId));
    });
  }

  /// 取消某会话的流式状态看门狗。
  void _cancelStreamingWatchdog(String sessionId) {
    _streamingWatchdogs.remove(sessionId)?.cancel();
  }

  /// 后台单会话状态校验与纠偏（GET /api/session/status?session_id=）。
  Future<void> _verifySessionStatus(String sessionId) async {
    try {
      final status = await _api.fetchSessionStatus(sessionId);
      final serverIsStreaming =
          status.isStreaming == true ||
          (status.activeStreamId != null && status.activeStreamId!.isNotEmpty);

      // 如果服务端已确认非流式且未指定 activeStreamId，则纠偏清空
      if (!serverIsStreaming) {
        markStreaming(sessionId, false);
      } else if (status.activeStreamId != null &&
          status.activeStreamId!.isNotEmpty &&
          _streamingSessions[sessionId] != status.activeStreamId) {
        markStreaming(
          sessionId,
          true,
          activeStreamId: status.activeStreamId,
          verifyInBackground: false,
        );
      } else {
        // 服务端确认仍在流式：续期看门狗，下一轮继续求证。
        _armStreamingWatchdog(sessionId);
      }
    } catch (_) {
      // 网络波动或测试桩未注入 status 时静默，保留本地乐观状态；
      // 但看门狗必须续期 —— 否则一次失败就让状态永久卡住。
      if (_streamingSessions.containsKey(sessionId)) {
        _armStreamingWatchdog(sessionId);
      }
    }
  }

  // -------------------------------------------------------------------------
  // 本地状态更新原语
  // -------------------------------------------------------------------------

  Future<void> _updateSession(
    String id,
    SessionSummary Function(SessionSummary) transform,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        sessions: [
          for (final s in current.sessions)
            s.sessionId == id ? transform(s) : s,
        ],
        searchResults: current.searchResults == null
            ? null
            : () => [
                for (final s in current.searchResults!)
                  s.sessionId == id ? transform(s) : s,
              ],
        archivedSessions: [
          for (final s in current.archivedSessions)
            s.sessionId == id ? transform(s) : s,
        ],
      ),
    );
  }

  Future<void> _removeSession(String id) async {
    _streamingSessions.remove(id);
    _cancelStreamingWatchdog(id);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        sessions: current.sessions.where((s) => s.sessionId != id).toList(),
        searchResults: current.searchResults == null
            ? null
            : () => current.searchResults!
                  .where((s) => s.sessionId != id)
                  .toList(),
        archivedSessions: current.archivedSessions
            .where((s) => s.sessionId != id)
            .toList(),
        selectedSessionIds: {...current.selectedSessionIds}..remove(id),
      ),
    );
  }

  /// 聊天页行操作免网络本地同步（无状态未就绪时静默 no-op）。
  ///
  /// 调用方：聊天页菜单成功后直接同步列表，避免 pop 回列表等 30s 轮询。
  /// [archived] 语义对齐 [setArchived] 单项逻辑：
  /// - true → 从普通列表移除 + archivedCount+1（归档视图下次进入时 fetchArchived 重拉）；
  /// - false → 本地反归档：普通列表该行 archived=false（若不存在则不插入，
  ///   等全量刷新补全，避免凭空造行），同时从归档视图移除 + archivedCount-1。
  void applyExternalRename(String id, String title) {
    final current = state.valueOrNull;
    if (current == null || id.isEmpty) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    SessionSummary replacer(SessionSummary s) => s.replacingTitle(trimmed);
    _syncLocalSession(id, replacer);
  }

  /// 聊天页置顶同步（成功后调用；失败不调用，列表保持旧值）。
  void applyExternalPinned(String id, bool pinned) {
    final current = state.valueOrNull;
    if (current == null || id.isEmpty) return;
    SessionSummary replacer(SessionSummary s) =>
        _replaced(s, pinned: pinned);
    _syncLocalSession(id, replacer);
  }

  /// 聊天页归档/取消归档同步（成功后调用）。
  ///
  /// 归档成功后即使身处归档筛选视图，也从普通列表移除（对齐 [setArchived]）；
  /// 归档视图自身不做本地增删（下次进入 fetchArchived 重拉为准）。
  void applyExternalArchived(String id, bool archived) {
    final current = state.valueOrNull;
    if (current == null || id.isEmpty) return;
    if (archived) {
      state = AsyncData(
        current.copyWith(
          sessions:
              current.sessions.where((s) => s.sessionId != id).toList(),
          searchResults: current.searchResults == null
              ? null
              : () => current.searchResults!
                    .where((s) => s.sessionId != id)
                    .toList(),
          archivedSessions: current.archivedSessions
              .where((s) => s.sessionId != id)
              .toList(),
          selectedSessionIds: {...current.selectedSessionIds}..remove(id),
        ),
      );
      unawaited(_adjustArchivedCount(1));
      return;
    }
    SessionSummary replacer(SessionSummary s) =>
        _replaced(s, archived: false);
    _syncLocalSession(id, replacer);
    unawaited(_removeArchived(id));
    unawaited(_adjustArchivedCount(-1));
  }

  /// 聊天页删除同步（成功后调用）：三视图移除 + 取消勾选残留。
  void applyExternalDeleted(String id) {
    final current = state.valueOrNull;
    if (current == null || id.isEmpty) return;
    _streamingSessions.remove(id);
    _cancelStreamingWatchdog(id);
    state = AsyncData(
      current.copyWith(
        sessions: current.sessions.where((s) => s.sessionId != id).toList(),
        searchResults: current.searchResults == null
            ? null
            : () => current.searchResults!
                  .where((s) => s.sessionId != id)
                  .toList(),
        archivedSessions: current.archivedSessions
            .where((s) => s.sessionId != id)
            .toList(),
        selectedSessionIds: {...current.selectedSessionIds}..remove(id),
      ),
    );
  }

  /// 聊天页分支同步（成功后调用）：新会话插到列表顶部（对齐 [_insertSession]
  /// 的「缺时间戳兜底现在」规则，避免落入「更早」分区底部看不见）。
  void applyExternalBranched(SessionSummary session) {
    final current = state.valueOrNull;
    if (current == null) return;
    final id = session.sessionId;
    if (id == null || id.isEmpty) return;
    if (current.sessions.any((s) => s.sessionId == id)) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0;
    var withStamp =
        session.createdAt == null ? session.copyWith(createdAt: now) : session;
    if (_streamingSessions.containsKey(id)) {
      withStamp = withStamp.withStreaming(
        isStreaming: true,
        activeStreamId: _streamingSessions[id],
      );
    }
    state = AsyncData(
      current.copyWith(
        sessions: [withStamp, ...current.sessions],
        visibleCount: current.visibleCount + 1,
      ),
    );
  }

  /// 三视图本地行替换原语：普通 + 搜索命中 + 归档视图同步改行。
  ///
  /// 注：「归档时把该行从归档视图剔除」的场景由 [_removeArchived] 独立承担；
  /// 原先的 `dropArchived` 参数在全仓**无任何 true 调用**（三个调用点都是
  /// false），属死参数，连同其恒不执行的分支一并移除。
  void _syncLocalSession(
    String id,
    SessionSummary Function(SessionSummary) transform,
  ) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        sessions: [
          for (final s in current.sessions)
            s.sessionId == id ? transform(s) : s,
        ],
        searchResults: current.searchResults == null
            ? null
            : () => [
                for (final s in current.searchResults!)
                  s.sessionId == id ? transform(s) : s,
              ],
        archivedSessions: [
          for (final s in current.archivedSessions)
            s.sessionId == id ? transform(s) : s,
        ],
      ),
    );
  }

  /// 从归档视图移除指定会话（取消归档后调用）。
  Future<void> _removeArchived(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        archivedSessions: current.archivedSessions
            .where((s) => s.sessionId != id)
            .toList(),
      ),
    );
  }

  /// 本地增/减归档计数（服务端未返回 archived_count 时为 null，不显示计数）。
  Future<void> _adjustArchivedCount(int delta) async {
    final current = state.valueOrNull;
    if (current == null || current.archivedCount == null) return;
    state = AsyncData(
      current.copyWith(
        archivedCount: () => max(0, current.archivedCount! + delta),
      ),
    );
  }

  /// 批量操作收尾：对成功项执行本地更新（移除列表项或刷新 projectId），
  /// 并清空勾选退出多选模式（失败项保留在列表中，由 actionError 提示）。
  Future<void> _applyBatchChanges({
    required List<String> successIds,
    bool removeFromLists = false,
    String? projectId,
    bool updateProjectId = false,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final successSet = successIds.toSet();
    List<SessionSummary> Function(List<SessionSummary>) apply;
    if (removeFromLists) {
      apply = (list) =>
          list.where((s) => !successSet.contains(s.sessionId)).toList();
    } else if (updateProjectId) {
      apply = (list) => [
        for (final s in list)
          successSet.contains(s.sessionId)
              ? _replaced(s, projectId: projectId, updateProjectId: true)
              : s,
      ];
    } else {
      return;
    }
    state = AsyncData(
      current.copyWith(
        sessions: apply(current.sessions),
        searchResults: current.searchResults == null
            ? null
            : () => apply(current.searchResults!),
        archivedSessions: apply(current.archivedSessions),
        selectedSessionIds: const {},
        isSelectionMode: false,
      ),
    );
  }

  Future<void> _insertSession(SessionSummary session) async {
    final current = state.valueOrNull;
    if (current == null) return;
    // 服务端新建/分支响应通常不带时间戳；缺失时兜底为“现在”，
    // 否则新会话落入「更早」分区最底部（排序 0），列表里看不到，
    // 要等手动下拉刷新（服务端带真时间戳）才出现在「今天」顶部。
    final now = DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0;
    var withStamp = session.createdAt == null
        ? session.copyWith(createdAt: now)
        : session;
    if (withStamp.sessionId != null &&
        _streamingSessions.containsKey(withStamp.sessionId)) {
      withStamp = withStamp.withStreaming(
        isStreaming: true,
        activeStreamId: _streamingSessions[withStamp.sessionId],
      );
    }
    state = AsyncData(
      current.copyWith(
        sessions: [withStamp, ...current.sessions],
        visibleCount: current.visibleCount + 1,
      ),
    );
  }

  Future<void> _setActionError(String message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(actionError: () => message));
  }

  static SessionSummary _replaced(
    SessionSummary session, {
    bool? pinned,
    bool? archived,
    String? projectId,
    bool updateProjectId = false,
  }) {
    return SessionSummary(
      sessionId: session.sessionId,
      title: session.title,
      workspace: session.workspace,
      model: session.model,
      modelProvider: session.modelProvider,
      messageCount: session.messageCount,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      lastMessageAt: session.lastMessageAt,
      pinned: pinned ?? session.pinned,
      archived: archived ?? session.archived,
      projectId: updateProjectId ? projectId : session.projectId,
      profile: session.profile,
      inputTokens: session.inputTokens,
      outputTokens: session.outputTokens,
      estimatedCost: session.estimatedCost,
      activeStreamId: session.activeStreamId,
      isStreaming: session.isStreaming,
      isCliSession: session.isCliSession,
      userMessageCount: session.userMessageCount,
      hasPendingUserMessage: session.hasPendingUserMessage,
      pendingStartedAt: session.pendingStartedAt,
      worktreePath: session.worktreePath,
      sourceTag: session.sourceTag,
      rawSource: session.rawSource,
      sessionSource: session.sessionSource,
      sourceLabel: session.sourceLabel,
      parentSessionId: session.parentSessionId,
      relationshipType: session.relationshipType,
      readOnly: session.readOnly,
      isReadOnly: session.isReadOnly,
      matchType: session.matchType,
    );
  }
}

/// 当前分页窗口内的可见会话（普通模式 = 分块；搜索模式 = 命中结果分块）。
final sessionListVisibleSessionsProvider = Provider<List<SessionSummary>>((
  ref,
) {
  final state = ref.watch(sessionListControllerProvider).valueOrNull;
  if (state == null) return const [];
  final all = state.displaySessions;
  final end = state.visibleCount < all.length ? state.visibleCount : all.length;
  return all.sublist(0, end);
});

/// 是否正在刷新（供 Header 按钮转菊花/禁用）。
final sessionListRefreshingProvider = Provider<bool>(
  (ref) =>
      ref.watch(sessionListControllerProvider).valueOrNull?.refreshing == true,
);

/// 会话分区（置顶 / 今天 / 昨天 / 更早）；搜索模式为单个「搜索结果」分区。
final sessionListSectionsProvider = Provider<List<SessionListSection>>((ref) {
  final visible = ref.watch(sessionListVisibleSessionsProvider);
  final query = ref
      .watch(sessionListControllerProvider)
      .valueOrNull
      ?.searchQuery;
  final isSearching = query != null && query.trim().isNotEmpty;
  if (isSearching) {
    return [SessionListSection(title: '搜索结果', sessions: visible)];
  }
  final showCron = ref.watch(cronVisibilityProvider).showCron;
  return buildSessionSections(
    visible,
    showCron: showCron,
    now: ref.watch(sessionListNowProvider)(),
  );
});

/// 会话分区参考时间工厂（生产返回 [DateTime.now] 实时时钟）。
///
/// 金照/分组测试可 override 成固定日历日，避免相对时间戳跨午夜漂移
/// （「昨天」会话在凌晨变成「今天」导致金照不稳定）。
final sessionListNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 按类型与时间把会话分组为 置顶 / 今天 / 昨天 / 更早，组内时间倒序；空组剔除。
///
/// 分组规则：
/// 1. 定时会话：当 [showCron] 为 false 时直接过滤忽略；当 [showCron] 为 true 时，
///    不再独立成「定时」分区，而是融流按时间戳归入「今天」/「昨天」/「更早」（即使 pinned 也按时间归入）。
/// 2. 置顶：非 cron 且 `pinned == true` 进入「置顶」分区。
/// 3. 时间分区：非置顶会话（及开启 showCron 时的 cron 会话）按时间归入「今天」/「昨天」/「更早」。
///
/// [now] 仅供测试注入固定参考时间；生产使用 [DateTime.now]。
List<SessionListSection> buildSessionSections(
  List<SessionSummary> sessions, {
  bool showCron = false,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final sorted = [...sessions]
    ..sort((a, b) => _sortTimestamp(b).compareTo(_sortTimestamp(a)));
  final pinned = <SessionSummary>[];
  final today = <SessionSummary>[];
  final yesterday = <SessionSummary>[];
  final earlier = <SessionSummary>[];
  for (final session in sorted) {
    if (session.isCronSession && !showCron) {
      continue;
    }
    if (session.pinned == true && !session.isCronSession) {
      pinned.add(session);
      continue;
    }
    final timestamp = _timestamp(session);
    if (timestamp == null) {
      earlier.add(session);
      continue;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(
      (timestamp * 1000).round(),
    );
    if (_isSameDay(date, reference)) {
      today.add(session);
    } else if (_isSameDay(date, reference.subtract(const Duration(days: 1)))) {
      yesterday.add(session);
    } else {
      earlier.add(session);
    }
  }
  return [
    if (pinned.isNotEmpty) SessionListSection(title: '置顶', sessions: pinned),
    if (today.isNotEmpty) SessionListSection(title: '今天', sessions: today),
    if (yesterday.isNotEmpty)
      SessionListSection(title: '昨天', sessions: yesterday),
    if (earlier.isNotEmpty) SessionListSection(title: '更早', sessions: earlier),
  ];
}

/// 会话时间戳：lastMessageAt ?? updatedAt ?? createdAt（秒）。
double? _timestamp(SessionSummary session) =>
    session.lastMessageAt ?? session.updatedAt ?? session.createdAt;

/// 排序用时间戳：缺失按 0（最旧）处理。
double _sortTimestamp(SessionSummary session) => _timestamp(session) ?? 0;

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 工作区最近使用频率排序与截断。
///
/// 规则：
/// 1. 剔除 path 为空串或 null 的项；
/// 2. 统计各工作区在 [sessions] 中的使用次数（frequency）；
/// 3. 获取各工作区在 [sessions] 中最近使用的时间戳（recency：max of lastMessageAt / updatedAt / createdAt）；
/// 4. 排序：使用次数多的排前；次数相同时最近使用时间新的排前；均相同则保持在 [registered] 中的原始顺序；
/// 5. [maxItems] 非 null 时取前 [maxItems] 个，为 null（默认）时不限量。
List<WorkspaceRoot> rankWorkspaces({
  required List<WorkspaceRoot> registered,
  required List<SessionSummary> sessions,
  int? maxItems,
}) {
  final valid = registered
      .where((w) => w.path != null && w.path!.trim().isNotEmpty)
      .toList();
  if (valid.isEmpty) return const [];

  final freqMap = <String, int>{};
  final recencyMap = <String, double>{};

  for (final s in sessions) {
    final ws = s.workspace?.trim();
    if (ws == null || ws.isEmpty) continue;
    freqMap[ws] = (freqMap[ws] ?? 0) + 1;
    final time = s.lastMessageAt ?? s.updatedAt ?? s.createdAt ?? 0.0;
    final existing = recencyMap[ws] ?? 0.0;
    if (time > existing) {
      recencyMap[ws] = time;
    }
  }

  final ranked = List<WorkspaceRoot>.from(valid);
  ranked.sort((a, b) {
    final pathA = a.path!.trim();
    final pathB = b.path!.trim();
    final freqA = freqMap[pathA] ?? 0;
    final freqB = freqMap[pathB] ?? 0;
    if (freqA != freqB) {
      return freqB.compareTo(freqA);
    }
    final recA = recencyMap[pathA] ?? 0.0;
    final recB = recencyMap[pathB] ?? 0.0;
    if (recA != recB) {
      return recB.compareTo(recA);
    }
    return 0;
  });

  return maxItems == null ? ranked : ranked.take(maxItems).toList();
}
