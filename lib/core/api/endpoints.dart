import 'dart:convert';

/// 单个查询参数（name/value 均为原始值，构建 URL 时统一百分号编码）。
class QueryParam {
  const QueryParam(this.name, this.value);

  final String name;
  final String value;
}

/// Hermes WebUI 端点（对齐 `.reference/hermex-src/Networking/Endpoints.swift`，共 125 个）。
///
/// - [path] 为相对路径模板；kanban 的 `{slug}` / `{cardId}` 占位符经 [pathParams]
///   替换，且按「RFC 3986 unreserved 减掉 `.`」的规则编码（点号也编码，防止
///   `.` / `..` 路径段注入，见 api_spec.md §2.4）。
/// - [query] 为查询参数；值为原始字符串，由 [url] 统一编码。
/// - 同一路径双方法端点（sessionYolo / reasoning / settings / updatesCheck）共用
///   同一 [Endpoint]，HTTP 方法由 ApiClient 侧决定。
class Endpoint {
  const Endpoint(
    this.path, {
    this.pathParams = const {},
    this.query = const [],
  });

  /// 相对路径模板（不含 base URL；`{param}` 为路径段占位）。
  final String path;

  /// 路径段占位符 → 原始值（仅 kanban slug/cardId 使用，按特殊规则编码）。
  final Map<String, String> pathParams;

  /// 查询参数列表。
  final List<QueryParam> query;

  /// 拼出完整 URL：`baseUrl`（不含尾斜杠）+ path + query。
  ///
  /// kanban 路径段用 [encodePathSegment]（点号编码）。注意：Dart 的 `Uri`
  /// 按 RFC 3986 §6.2.2.2 会把路径中百分号编码的 **unreserved** 字符（含 `.`）
  /// 归一化解码（`%2F` 等 reserved 字符的编码则原样保留），因此最终 URL 中
  /// 点号以字面量出现——段完整性由 `%2F`/`%20` 的编码保留保证（`..` 也无法
  /// 逃逸出当前路径），服务端解码后仍还原原值。
  /// 查询参数用手写 `Uri.encodeComponent` 编码（空格 → `%20`，对齐 Swift
  /// URLComponents/URLQueryItem 行为，而非 `+`）。
  Uri url(String baseUrl) {
    var resolved = path;
    for (final entry in pathParams.entries) {
      resolved = resolved.replaceFirst(
        '{${entry.key}}',
        encodePathSegment(entry.value),
      );
    }
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.parse('$base$resolved');
    if (query.isEmpty) return uri;
    final queryString = query
        .map(
          (q) =>
              '${Uri.encodeComponent(q.name)}=${Uri.encodeComponent(q.value)}',
        )
        .join('&');
    return Uri.parse('$uri?$queryString');
  }

  /// kanban 路径段编码：仅保留 `A-Z a-z 0-9 - _ ~`，其余（含 `.`）按 UTF-8
  /// 字节百分号编码（RFC 3986 unreserved 减掉 `.`，Endpoints.swift L563-590）。
  static String encodePathSegment(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune < 128 && _pathSegmentAllowedCodeUnits.contains(rune)) {
        buffer.writeCharCode(rune);
      } else {
        for (final byte in utf8.encode(String.fromCharCode(rune))) {
          buffer.write(
            '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          );
        }
      }
    }
    return buffer.toString();
  }

  static final Set<int> _pathSegmentAllowedCodeUnits = {
    for (var c = 'a'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++) c,
    for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) c,
    for (var c = '0'.codeUnitAt(0); c <= '9'.codeUnitAt(0); c++) c,
    0x2D, // -
    0x5F, // _
    0x7E, // ~
  };

  // ---------------------------------------------------------------------------
  // 1.1 server — 5 个
  // ---------------------------------------------------------------------------

  static const health = Endpoint('/health');
  static const authStatus = Endpoint('/api/auth/status');
  static const login = Endpoint('/api/auth/login');
  static const logout = Endpoint('/api/auth/logout');

  /// GET /api/system/health（系统健康状态：CPU/内存/磁盘）。
  static const systemHealth = Endpoint('/api/system/health');

  // ---------------------------------------------------------------------------
  // 1.2 sessions — 18 个
  // ---------------------------------------------------------------------------

  /// `include_archived` 为 opt-in（issue #17）：关闭时请求保持与默认一致；
  /// `archived_limit` 仅随 `include_archived=1` 发送。
  /// 始终带 `sidebar_source=webui`（对齐 WebUI 前端 `sessions.js:_sessionListQueryString`）：
  /// 服务端据此过滤掉 CLI/agy 等只读导入会话，避免测试痕迹污染会话列表。
  static Endpoint sessions({bool includeArchived = false, int? archivedLimit}) {
    return Endpoint(
      '/api/sessions',
      query: [
        if (includeArchived) const QueryParam('include_archived', '1'),
        if (archivedLimit != null)
          QueryParam('archived_limit', '$archivedLimit'),
        const QueryParam('sidebar_source', 'webui'),
      ],
    );
  }

  static Endpoint sessionsSearch({
    required String query,
    required bool content,
    required int depth,
  }) {
    return Endpoint(
      '/api/sessions/search',
      query: [
        QueryParam('q', query),
        QueryParam('content', content ? '1' : '0'),
        QueryParam('depth', '$depth'),
      ],
    );
  }

  static Endpoint session({
    required String sessionId,
    required bool includeMessages,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) {
    return Endpoint(
      '/api/session',
      query: [
        QueryParam('session_id', sessionId),
        QueryParam('messages', includeMessages ? '1' : '0'),
        if (messageLimit != null) QueryParam('msg_limit', '$messageLimit'),
        if (messageBefore != null) QueryParam('msg_before', '$messageBefore'),
        if (expandRenderable) const QueryParam('expand_renderable', '1'),
      ],
    );
  }

  static Endpoint sessionStatus(String sessionId) {
    return Endpoint(
      '/api/session/status',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  static const newSession = Endpoint('/api/session/new');
  static const renameSession = Endpoint('/api/session/rename');
  static const deleteSession = Endpoint('/api/session/delete');
  static const pinSession = Endpoint('/api/session/pin');
  static const archiveSession = Endpoint('/api/session/archive');
  static const branchSession = Endpoint('/api/session/branch');
  static const compressSession = Endpoint('/api/session/compress');

  /// POST /api/session/compress/start（#156 异步压缩：立刻返回，后台线程执行；
  /// 重复调用幂等复用同一 running job）。
  ///
  /// 同步版 [compressSession] 会在反向代理（frp 等）下超时 —— 服务端官方
  /// 为此提供 start + status 两件套，官方前端也已全面改走异步版。
  static const startSessionCompression = Endpoint(
    '/api/session/compress/start',
  );

  /// GET /api/session/compress/status?session_id=（#156 轮询异步压缩进度）。
  static Endpoint sessionCompressionStatus(String sessionId) {
    return Endpoint(
      '/api/session/compress/status',
      query: [QueryParam('session_id', sessionId)],
    );
  }
  static const undoSession = Endpoint('/api/session/undo');
  static const retrySession = Endpoint('/api/session/retry');
  static const truncateSession = Endpoint('/api/session/truncate');
  static const updateSession = Endpoint('/api/session/update');
  static const moveSession = Endpoint('/api/session/move');

  /// GET /api/sessions/events（会话变更 SSE 推送）。
  static const sessionEvents = Endpoint('/api/sessions/events');

  /// GET 查状态（query `session_id` 可选）；POST 设状态时传 null（无 query）。
  static Endpoint sessionYolo([String? sessionId]) {
    return Endpoint(
      '/api/session/yolo',
      query: [if (sessionId != null) QueryParam('session_id', sessionId)],
    );
  }

  /// `format` ∈ `html` | `json`。
  static Endpoint exportSession({
    required String sessionId,
    required String format,
  }) {
    return Endpoint(
      '/api/session/export',
      query: [
        QueryParam('session_id', sessionId),
        QueryParam('format', format),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 1.3 projects — 4 个
  // ---------------------------------------------------------------------------

  static const projects = Endpoint('/api/projects');
  static const createProject = Endpoint('/api/projects/create');
  static const renameProject = Endpoint('/api/projects/rename');
  static const deleteProject = Endpoint('/api/projects/delete');

  // ---------------------------------------------------------------------------
  // 1.4 chat — 9 个
  // ---------------------------------------------------------------------------

  static const chatStart = Endpoint('/api/chat/start');

  static Endpoint chatStream(String streamId) {
    return Endpoint(
      '/api/chat/stream',
      query: [QueryParam('stream_id', streamId)],
    );
  }

  /// 重放模式：追加 `replay=1&after_seq=N`（N = max(0, seq)）。
  static Endpoint chatStreamReplay(String streamId, int afterSeq) {
    return Endpoint(
      '/api/chat/stream',
      query: [
        QueryParam('stream_id', streamId),
        const QueryParam('replay', '1'),
        QueryParam('after_seq', '${afterSeq < 0 ? 0 : afterSeq}'),
      ],
    );
  }

  static Endpoint chatCancel(String streamId) {
    return Endpoint(
      '/api/chat/cancel',
      query: [QueryParam('stream_id', streamId)],
    );
  }

  static Endpoint chatStreamStatus(String streamId) {
    return Endpoint(
      '/api/chat/stream/status',
      query: [QueryParam('stream_id', streamId)],
    );
  }

  static const chatSteer = Endpoint('/api/chat/steer');
  static const submitGoal = Endpoint('/api/goal');
  static const btw = Endpoint('/api/btw');
  static const background = Endpoint('/api/background');

  static Endpoint backgroundStatus(String sessionId) {
    return Endpoint(
      '/api/background/status',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  // ---------------------------------------------------------------------------
  // 1.5 approval — 3 个
  // ---------------------------------------------------------------------------

  static Endpoint approvalPending(String sessionId) {
    return Endpoint(
      '/api/approval/pending',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  static Endpoint approvalStream(String sessionId) {
    return Endpoint(
      '/api/approval/stream',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  static const approvalRespond = Endpoint('/api/approval/respond');

  // ---------------------------------------------------------------------------
  // 1.6 clarify — 3 个
  // ---------------------------------------------------------------------------

  static Endpoint clarifyPending(String sessionId) {
    return Endpoint(
      '/api/clarify/pending',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  static Endpoint clarifyStream(String sessionId) {
    return Endpoint(
      '/api/clarify/stream',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  static const clarifyRespond = Endpoint('/api/clarify/respond');

  // ---------------------------------------------------------------------------
  // 1.6.1 session stream — 1 个 (#108)
  // ---------------------------------------------------------------------------

  /// GET /api/session/stream?session_id=&known_count=（会话内容与自唤醒实时同步）。
  static Endpoint sessionStream(String sessionId, [int? knownCount]) {
    return Endpoint(
      '/api/session/stream',
      query: [
        QueryParam('session_id', sessionId),
        if (knownCount != null) QueryParam('known_count', '$knownCount'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 1.7 workspace — 12 个
  // ---------------------------------------------------------------------------

  static const workspaces = Endpoint('/api/workspaces');

  static Endpoint workspaceSuggestions(String prefix) {
    return Endpoint(
      '/api/workspaces/suggest',
      query: [QueryParam('prefix', prefix)],
    );
  }

  static const workspaceAdd = Endpoint('/api/workspaces/add');
  static const workspaceRemove = Endpoint('/api/workspaces/remove');
  static const workspaceRename = Endpoint('/api/workspaces/rename');
  static const workspaceReorder = Endpoint('/api/workspaces/reorder');

  /// POST /api/file/delete {session_id, path, recursive?} → {ok, path}。
  static const fileDelete = Endpoint('/api/file/delete');

  /// POST /api/file/rename {session_id, path, new_name} → {ok, old_path, new_path}。
  static const fileRename = Endpoint('/api/file/rename');

  static Endpoint directoryList({required String sessionId, String? path}) {
    return Endpoint(
      '/api/list',
      query: [
        QueryParam('session_id', sessionId),
        if (path != null) QueryParam('path', path),
      ],
    );
  }

  static Endpoint file({required String sessionId, required String path}) {
    return Endpoint(
      '/api/file',
      query: [QueryParam('session_id', sessionId), QueryParam('path', path)],
    );
  }

  static Endpoint rawFile({required String sessionId, required String path}) {
    return Endpoint(
      '/api/file/raw',
      query: [QueryParam('session_id', sessionId), QueryParam('path', path)],
    );
  }

  static Endpoint media({required String sessionId, required String path}) {
    return Endpoint(
      '/api/media',
      query: [QueryParam('session_id', sessionId), QueryParam('path', path)],
    );
  }

  /// GET /api/folder/download?session_id=&path=（目录打包 zip 下载；
  /// `path` 缺省/为空 = 工作区根）。
  static Endpoint folderDownload({required String sessionId, String? path}) {
    return Endpoint(
      '/api/folder/download',
      query: [
        QueryParam('session_id', sessionId),
        if (path != null && path.isNotEmpty) QueryParam('path', path),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 1.8 git — 16 个
  // ---------------------------------------------------------------------------

  static Endpoint gitInfo(String sessionId) {
    return Endpoint(
      '/api/git-info',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  static Endpoint gitStatus(String sessionId) {
    return Endpoint(
      '/api/git/status',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  static Endpoint gitBranches(String sessionId) {
    return Endpoint(
      '/api/git/branches',
      query: [QueryParam('session_id', sessionId)],
    );
  }

  static Endpoint gitDiff({
    required String sessionId,
    required String path,
    String kind = 'unstaged',
  }) {
    return Endpoint(
      '/api/git/diff',
      query: [
        QueryParam('session_id', sessionId),
        QueryParam('path', path),
        QueryParam('kind', kind),
      ],
    );
  }

  static const gitFetch = Endpoint('/api/git/fetch');
  static const gitPull = Endpoint('/api/git/pull');
  static const gitPush = Endpoint('/api/git/push');
  static const gitCheckout = Endpoint('/api/git/checkout');
  static const gitStashCheckout = Endpoint('/api/git/stash-checkout');
  static const gitStage = Endpoint('/api/git/stage');
  static const gitUnstage = Endpoint('/api/git/unstage');
  static const gitDiscard = Endpoint('/api/git/discard');
  static const gitCommit = Endpoint('/api/git/commit');
  static const gitCommitSelected = Endpoint('/api/git/commit-selected');
  static const gitCommitMessage = Endpoint('/api/git/commit-message');
  static const gitCommitMessageSelected = Endpoint(
    '/api/git/commit-message-selected',
  );

  // ---------------------------------------------------------------------------
  // 1.9 models — 9 个（reasoning/settings/updatesCheck 为双方法端点）
  // ---------------------------------------------------------------------------

  static const models = Endpoint('/api/models');
  static const modelsLive = Endpoint('/api/models/live');
  static const modelsRefresh = Endpoint('/api/models/refresh');
  static const commands = Endpoint('/api/commands');
  static const defaultModel = Endpoint('/api/default-model');

  /// GET 查状态（`model`/`provider` 非空才发）；POST 写时传空参（无 query）。
  static Endpoint reasoning({String? model, String? provider}) {
    return Endpoint(
      '/api/reasoning',
      query: [
        if (model != null && model.isNotEmpty) QueryParam('model', model),
        if (provider != null && provider.isNotEmpty)
          QueryParam('provider', provider),
      ],
    );
  }

  static const providers = Endpoint('/api/providers');
  static const settings = Endpoint('/api/settings');
  static const updatesCheck = Endpoint('/api/updates/check');
  static const updatesApply = Endpoint('/api/updates/apply');

  // ---------------------------------------------------------------------------
  // 1.10 profiles — 5 个
  // ---------------------------------------------------------------------------

  static const personalities = Endpoint('/api/personalities');
  static const setPersonality = Endpoint('/api/personality/set');
  static const profiles = Endpoint('/api/profiles');
  static const switchProfile = Endpoint('/api/profile/switch');
  static const createProfile = Endpoint('/api/profile/create');

  // ---------------------------------------------------------------------------
  // 1.11 insights — 1 个
  // ---------------------------------------------------------------------------

  static Endpoint insights(int days) {
    return Endpoint('/api/insights', query: [QueryParam('days', '$days')]);
  }

  // ---------------------------------------------------------------------------
  // 1.12 cron — 10 个
  // ---------------------------------------------------------------------------

  static const crons = Endpoint('/api/crons');
  static const cronCreate = Endpoint('/api/crons/create');
  static const cronUpdate = Endpoint('/api/crons/update');
  static const cronDelete = Endpoint('/api/crons/delete');
  static const cronRun = Endpoint('/api/crons/run');
  static const cronPause = Endpoint('/api/crons/pause');
  static const cronResume = Endpoint('/api/crons/resume');

  static Endpoint cronStatus([String? jobId]) {
    return Endpoint(
      '/api/crons/status',
      query: [if (jobId != null) QueryParam('job_id', jobId)],
    );
  }

  static Endpoint cronOutput({required String jobId, int? limit}) {
    return Endpoint(
      '/api/crons/output',
      query: [
        QueryParam('job_id', jobId),
        if (limit != null) QueryParam('limit', '$limit'),
      ],
    );
  }

  static const cronDeliveryOptions = Endpoint('/api/crons/delivery-options');

  // ---------------------------------------------------------------------------
  // 1.13 kanban — 23 个（路径段 {slug}/{cardId} 用 encodePathSegment 编码）
  // ---------------------------------------------------------------------------

  static const kanbanConfig = Endpoint('/api/kanban/config');
  static const kanbanBoards = Endpoint('/api/kanban/boards');
  static const kanbanCreateBoard = Endpoint('/api/kanban/boards');

  static Endpoint kanbanEditBoard(String slug) {
    return Endpoint('/api/kanban/boards/{slug}', pathParams: {'slug': slug});
  }

  static Endpoint kanbanArchiveBoard(String slug) {
    return Endpoint('/api/kanban/boards/{slug}', pathParams: {'slug': slug});
  }

  static Endpoint kanbanMakeBoardActive(String slug) {
    return Endpoint(
      '/api/kanban/boards/{slug}/switch',
      pathParams: {'slug': slug},
    );
  }

  static Endpoint kanbanDispatch({
    required String board,
    required bool dryRun,
    int max = 8,
  }) {
    return Endpoint(
      '/api/kanban/dispatch',
      query: [
        QueryParam('board', board),
        QueryParam('dry_run', dryRun ? 'true' : 'false'),
        QueryParam('max', '$max'),
      ],
    );
  }

  static Endpoint kanbanBoard({
    required String board,
    String? tenant,
    String? assignee,
    bool includeArchived = false,
    bool onlyMine = false,
    String? since,
  }) {
    return Endpoint(
      '/api/kanban/board',
      query: [
        QueryParam('board', board),
        if (tenant != null) QueryParam('tenant', tenant),
        if (assignee != null) QueryParam('assignee', assignee),
        if (includeArchived) const QueryParam('include_archived', 'true'),
        if (onlyMine) const QueryParam('only_mine', 'true'),
        if (since != null) QueryParam('since', since),
      ],
    );
  }

  static Endpoint kanbanStats(String board) {
    return Endpoint('/api/kanban/stats', query: [QueryParam('board', board)]);
  }

  static Endpoint kanbanAssignees(String board) {
    return Endpoint(
      '/api/kanban/assignees',
      query: [QueryParam('board', board)],
    );
  }

  /// `since` 取 max(0)；`limit` clamp 到 1–200，默认 200。
  static Endpoint kanbanEvents({
    required String board,
    required int since,
    int limit = 200,
  }) {
    final clampedLimit = limit.clamp(1, 200);
    return Endpoint(
      '/api/kanban/events',
      query: [
        QueryParam('board', board),
        QueryParam('since', '${since < 0 ? 0 : since}'),
        QueryParam('limit', '$clampedLimit'),
      ],
    );
  }

  static Endpoint kanbanEventsStream({
    required String board,
    required int since,
  }) {
    return Endpoint(
      '/api/kanban/events/stream',
      query: [
        QueryParam('board', board),
        QueryParam('since', '${since < 0 ? 0 : since}'),
      ],
    );
  }

  static Endpoint kanbanCardDetail({
    required String board,
    required String cardId,
  }) {
    return Endpoint(
      '/api/kanban/tasks/{cardId}',
      pathParams: {'cardId': cardId},
      query: [QueryParam('board', board)],
    );
  }

  /// `tail` 默认 65536，clamp 到 1–2_000_000。
  static Endpoint kanbanWorkerLog({
    required String board,
    required String cardId,
    int tail = 65536,
  }) {
    final clampedTail = tail.clamp(1, 2000000);
    return Endpoint(
      '/api/kanban/tasks/{cardId}/log',
      pathParams: {'cardId': cardId},
      query: [QueryParam('board', board), QueryParam('tail', '$clampedTail')],
    );
  }

  static Endpoint kanbanAddComment({
    required String board,
    required String cardId,
  }) {
    return Endpoint(
      '/api/kanban/tasks/{cardId}/comments',
      pathParams: {'cardId': cardId},
      query: [QueryParam('board', board)],
    );
  }

  static Endpoint kanbanCreateCard(String board) {
    return Endpoint('/api/kanban/tasks', query: [QueryParam('board', board)]);
  }

  static Endpoint kanbanBulkAction(String board) {
    return Endpoint(
      '/api/kanban/tasks/bulk',
      query: [QueryParam('board', board)],
    );
  }

  static Endpoint kanbanEditCard({
    required String board,
    required String cardId,
  }) {
    return Endpoint(
      '/api/kanban/tasks/{cardId}',
      pathParams: {'cardId': cardId},
      query: [QueryParam('board', board)],
    );
  }

  static Endpoint kanbanCardStatus({
    required String board,
    required String cardId,
  }) {
    return Endpoint(
      '/api/kanban/tasks/{cardId}',
      pathParams: {'cardId': cardId},
      query: [QueryParam('board', board)],
    );
  }

  static Endpoint kanbanBlockCard({
    required String board,
    required String cardId,
  }) {
    return Endpoint(
      '/api/kanban/tasks/{cardId}/block',
      pathParams: {'cardId': cardId},
      query: [QueryParam('board', board)],
    );
  }

  static Endpoint kanbanUnblockCard({
    required String board,
    required String cardId,
  }) {
    return Endpoint(
      '/api/kanban/tasks/{cardId}/unblock',
      pathParams: {'cardId': cardId},
      query: [QueryParam('board', board)],
    );
  }

  static Endpoint kanbanAddDependency(String board) {
    return Endpoint('/api/kanban/links', query: [QueryParam('board', board)]);
  }

  static Endpoint kanbanRemoveDependency(String board) {
    return Endpoint(
      '/api/kanban/links/delete',
      query: [QueryParam('board', board)],
    );
  }

  // ---------------------------------------------------------------------------
  // 1.14 memory — 2 个
  // ---------------------------------------------------------------------------

  static const memory = Endpoint('/api/memory');
  static const memoryWrite = Endpoint('/api/memory/write');

  // ---------------------------------------------------------------------------
  // 1.15 skills — 3 个
  // ---------------------------------------------------------------------------

  static const skills = Endpoint('/api/skills');

  static Endpoint skillContent({required String name, String? file}) {
    return Endpoint(
      '/api/skills/content',
      query: [
        QueryParam('name', name),
        if (file != null) QueryParam('file', file),
      ],
    );
  }

  static const toggleSkill = Endpoint('/api/skills/toggle');

  // ---------------------------------------------------------------------------
  // 1.15b prompts — 3 个（GET/POST/DELETE 同路径）
  // ---------------------------------------------------------------------------

  static const prompts = Endpoint('/api/prompts');

  // ---------------------------------------------------------------------------
  // 1.16 upload / transcribe / tts — 3 个
  // ---------------------------------------------------------------------------

  static const upload = Endpoint('/api/upload');
  static const transcribe = Endpoint('/api/transcribe');
  static const tts = Endpoint('/api/tts');

  // ---------------------------------------------------------------------------
  // 1.17 extensions — 6 个
  // ---------------------------------------------------------------------------

  /// GET /api/extensions/status
  static const extensionsStatus = Endpoint('/api/extensions/status');

  /// GET /api/extensions/registry
  static const extensionsRegistry = Endpoint('/api/extensions/registry');

  /// POST /api/extensions/toggle
  static const extensionToggle = Endpoint('/api/extensions/toggle');

  /// POST /api/extensions/install
  static const extensionInstall = Endpoint('/api/extensions/install');

  /// POST /api/extensions/uninstall
  static const extensionUninstall = Endpoint('/api/extensions/uninstall');

  /// POST /api/extensions/sidecar-proxy-consent
  static const extensionSidecarProxyConsent = Endpoint(
    '/api/extensions/sidecar-proxy-consent',
  );

  // ---------------------------------------------------------------------------
  // 1.18 mcp — 5 个
  // ---------------------------------------------------------------------------

  /// GET /api/mcp/servers
  static const mcpServers = Endpoint('/api/mcp/servers');

  /// GET /api/mcp/tools
  static const mcpTools = Endpoint('/api/mcp/tools');

  /// PUT /api/mcp/servers/{name}
  static Endpoint mcpServerUpdate(String name) =>
      Endpoint('/api/mcp/servers/{name}', pathParams: {'name': name});

  /// PATCH /api/mcp/servers/{name}
  static Endpoint mcpServerToggle(String name) =>
      Endpoint('/api/mcp/servers/{name}', pathParams: {'name': name});

  /// DELETE /api/mcp/servers/{name}
  static Endpoint mcpServerDelete(String name) =>
      Endpoint('/api/mcp/servers/{name}', pathParams: {'name': name});

  // ---------------------------------------------------------------------------
  // 1.19 auxiliary models — 2 个
  // ---------------------------------------------------------------------------

  /// GET /api/model/auxiliary
  static const auxiliaryModels = Endpoint('/api/model/auxiliary');

  /// POST /api/model/set
  static const modelSet = Endpoint('/api/model/set');

  /// 复制一份并追加查询参数（内部辅助）。
  Endpoint withQuery(List<QueryParam> additional) {
    return Endpoint(
      path,
      pathParams: pathParams,
      query: [...query, ...additional],
    );
  }
}
