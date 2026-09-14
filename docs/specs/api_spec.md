# Hermex → Flutter API 层翻译规格（endpoints.dart + api_client.dart）

> 状态：规格定稿（2026-08-16）
> 来源：`.reference/hermex-src/Networking/` 全部 22 个 Swift 文件精读（Endpoints.swift 590 行全读；APIClient.swift / APIClient+Chat / +Sessions / +Cron / +Workspace / +Git / +Kanban / +Memory / +Projects / +Skills / +SessionExport / +ServerPanels / +Upload / +Transcribe / +TTS / SSEClient.swift / KanbanEventStreamClient.swift / CustomHeader.swift / MultipartFormData.swift / APIError.swift / CacheFallbackPolicy.swift）
> 用途：编码子代理按本文档直接编写 `lib/core/api/endpoints.dart` 与 `lib/core/api/api_client.dart`，不需要再读 Swift 源码
> 强制约束：`AGENTS.md` 第 6 节（端点表与 Endpoints.swift 一一对应；模型手写 fromJson/toJson 容错解码；API Key 存 flutter_secure_storage，禁止硬编码、禁止进日志）；SSE 部分引用 `docs/PROTOCOL_NOTES.md`，不重复编写

---

## 0. 总览（编码前必读）

| 项 | 结论 |
|---|---|
| 端点总数 | **123 个**（Endpoints.swift 全部 case，一个不漏，见第 1 节分域表） |
| 认证方式 | **Cookie 会话**（主）+ **用户自定义 Header**（辅，反向代理用）。**不是**客户端生成的 API key header，header 名不固定（用户配置，如 `Authorization` / `X-Api-Key`）。详见 §2.2 |
| base URL | `http(s)://<host>:<port>`，端点 path 直接拼接；kanban 的 `{slug}`/`{cardId}` 路径段需特殊百分号编码（§2.4） |
| 错误归一化 | 5 类 ApiException 对齐 APIError.swift + 4 个语义标记（§2.3） |
| SSE | chat/approval/clarify 三个流 + chat replay 参数 → **见 `docs/PROTOCOL_NOTES.md`**；kanban events 流是独立帧协议（§3） |
| 上传 | multipart 字段名 `session_id`（仅 upload）+ `file`；服务端上限 **10 附件 / 64 MiB 总量**；Hermex 客户端预检 **20 MB/文件**（§4） |
| JSON 编解码 | 全局 snake_case ↔ camelCase（Swift 的 convertFromSnakeCase / convertToSnakeCase 等价物）；模型容错解码（§5） |

特殊注意点（详见正文）：
1. `chatCancel` 是 **GET** 不是 POST（`GET /api/chat/cancel?stream_id=…`）
2. `sessionYolo` 同一路径两种方法：GET 查状态（query `session_id`，可选）、POST 设状态（body `{session_id, enabled}`，无 query）
3. `reasoning` / `settings` / `updatesCheck` 也是同一路径双方法（GET 查、POST 写，body 形状不同）
4. `exportSession` / `rawFile` / `media` / `tts` 返回**原始字节/文件**而非 JSON，Accept 要改 `*/*`，文件名从 `Content-Disposition` 解析
5. `transcribe` 非 2xx 也要先尝试解码 `{ok, transcript, error}` body（服务端 503/400/413 都带 JSON error）
6. kanban 全部响应校验 `Content-Type: application/json`，非 JSON 抛 `KanbanResponseError.nonJSONContentType` 等价物
7. `kanbanCardStatus` 客户端守卫：status 不得为 `running`（running 只能由 dispatcher 设置）
8. `kanbanDispatch` 响应校验 `hasKnownCategory`（8 个计数全空 → 报错）
9. git commit-message 两个端点超时 **120s**（LLM 生成），其余默认 60s
10. `applyUpdate` 会重启服务端，调用方要容忍短暂断连并事后重轮询
11. 跨域重定向必须剥离自定义 header（防泄密），同域重定向保留

---

## 1. endpoints.dart 端点表（123 个，按域分组）

> 约定：`dartEndpointName` = Swift case 名的 camelCase（常量），如 `Endpoint.sessions` → `sessions`。
> 路径模板中 `{param}` 为路径段占位（需百分号编码，规则见 §2.4）；`?q=` 为查询参数；body 为 JSON 对象（键名为 **snake_case** 线上格式）；返回列注明 Swift 响应类型 → Dart 模型名规划（`core/models/`，未列出的随实现定义，均走容错 fromJson）。
> SSE 端点返回列标 `SSE → 见 PROTOCOL_NOTES.md`。

### 1.1 server（健康/认证/登出） — 4 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `health` | GET | `/health` | — | — | `HealthResponse` {status, sessions, active_streams, uptime_seconds} |
| `authStatus` | GET | `/api/auth/status` | — | — | `AuthStatusResponse` {auth_enabled, password_auth_enabled, …} |
| `login` | POST | `/api/auth/login` | — | `{password}` | `LoginResponse` {ok, …}；**成功即种会话 cookie**（§2.2） |
| `logout` | POST | `/api/auth/logout` | — | `{}`（空对象） | `LoginResponse` |

### 1.2 sessions（会话管理） — 18 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `sessions` | GET | `/api/sessions` | `include_archived=1`（仅 opt-in 时发）、`archived_limit=N`（仅随 include_archived 发） | — | `SessionsResponse` {sessions[], cli_count, archived_count?, count?} |
| `sessionsSearch` | GET | `/api/sessions/search` | `q`、`content=1\|0`、`depth` | — | `SessionSearchResponse` |
| `session` | GET | `/api/session` | `session_id`、`messages=1\|0`、`msg_limit?`、`msg_before?`、`expand_renderable=1`（可选，冷加载才发） | — | `SessionResponse` {session} |
| `sessionStatus` | GET | `/api/session/status` | `session_id` | — | `SessionStatusResponse` |
| `newSession` | POST | `/api/session/new` | — | `{workspace?, model?, model_provider?, profile?}` | `SessionResponse` |
| `renameSession` | POST | `/api/session/rename` | — | `{session_id, title}` | `SessionMutationResponse` |
| `deleteSession` | POST | `/api/session/delete` | — | `{session_id}` | `SessionMutationResponse` |
| `pinSession` | POST | `/api/session/pin` | — | `{session_id, pinned}` | `SessionMutationResponse` |
| `archiveSession` | POST | `/api/session/archive` | — | `{session_id, archived}` | `SessionMutationResponse` |
| `branchSession` | POST | `/api/session/branch` | — | `{session_id, keep_count?, title?}` | `SessionBranchResponse` |
| `compressSession` | POST | `/api/session/compress` | — | `{session_id, focus_topic?}` | `SessionCompressResponse` |
| `undoSession` | POST | `/api/session/undo` | — | `{session_id}` | `SessionUndoResponse` |
| `retrySession` | POST | `/api/session/retry` | — | `{session_id}` | `SessionRetryResponse` |
| `truncateSession` | POST | `/api/session/truncate` | — | `{session_id, keep_count}` | `SessionResponse` |
| `updateSession` | POST | `/api/session/update` | — | `{session_id, workspace?, model?, model_provider?}` | `SessionResponse` |
| `moveSession` | POST | `/api/session/move` | — | `{session_id, project_id?}` | `SessionMutationResponse` |
| `sessionYolo` | GET | `/api/session/yolo` | `session_id`（可选，nil 时无 query） | — | `SessionYoloResponse` |
| `sessionYolo` | POST | `/api/session/yolo` | **无**（调用方传 nil） | `{session_id, enabled}` | `SessionYoloResponse` |
| `exportSession` | GET | `/api/session/export` | `session_id`、`format=html\|json` | — | **文件下载**（text/html 或 application/json），非 JSON；Accept=`*/*`；文件名从 `Content-Disposition` 的 `filename=` 解析（缺失时回退 `<标题>.<ext>` → `hermes-<id>.<ext>`） |

### 1.3 projects（项目分组） — 4 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `projects` | GET | `/api/projects` | — | — | `ProjectsResponse` |
| `createProject` | POST | `/api/projects/create` | — | `{name, color?}` | `ProjectMutationResponse` |
| `renameProject` | POST | `/api/projects/rename` | — | `{project_id, name, color?}` | `ProjectMutationResponse` |
| `deleteProject` | POST | `/api/projects/delete` | — | `{project_id}` | `ProjectMutationResponse` |

### 1.4 chat（对话/流/背景任务） — 9 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `chatStart` | POST | `/api/chat/start` | — | `{session_id, message, workspace?, model?, model_provider?, profile?, explicit_model_pick?, attachments?}`；attachments 元素形状 `{name, path, mime, size?, is_image}`（§4.3） | `ChatStartResponse`（含 stream_id 等） |
| `chatStream` | GET | `/api/chat/stream` | `stream_id`；重放时追加 `replay=1&after_seq=N`（N=max(0, seq)） | — | **SSE → PROTOCOL_NOTES.md** |
| `chatCancel` | GET | `/api/chat/cancel` | `stream_id` | — | `ChatCancelResponse` ⚠️ **GET** |
| `chatStreamStatus` | GET | `/api/chat/stream/status` | `stream_id` | — | `ChatStreamStatusResponse` |
| `chatSteer` | POST | `/api/chat/steer` | — | `{session_id, text}` | `ChatSteerResponse` |
| `submitGoal` | POST | `/api/goal` | — | `{session_id, args, workspace?, model?, model_provider?, profile?}` | `GoalSubmissionResponse` |
| `btw` | POST | `/api/btw` | — | `{session_id, question}` | `BtwStartResponse` |
| `background` | POST | `/api/background` | — | `{session_id, prompt}` | `BackgroundStartResponse` |
| `backgroundStatus` | GET | `/api/background/status` | `session_id` | — | `BackgroundStatusResponse` |

### 1.5 approval（工具审批） — 3 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `approvalPending` | GET | `/api/approval/pending` | `session_id` | — | `ApprovalPendingResponse` |
| `approvalStream` | GET | `/api/approval/stream` | `session_id` | — | **SSE → PROTOCOL_NOTES.md**（`initial`/`approval` 事件） |
| `approvalRespond` | POST | `/api/approval/respond` | — | `{session_id, choice, approval_id?}` | `ApprovalRespondResponse`；409 + `{stale:true}` = 提示已过期（§2.3） |

### 1.6 clarify（澄清） — 3 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `clarifyPending` | GET | `/api/clarify/pending` | `session_id` | — | `ClarificationPendingResponse` |
| `clarifyStream` | GET | `/api/clarify/stream` | `session_id` | — | **SSE → PROTOCOL_NOTES.md**（`initial`/`clarify` 事件） |
| `clarifyRespond` | POST | `/api/clarify/respond` | — | `{session_id, response, clarify_id?}` | `ClarificationRespondResponse`；409 + `{stale:true}` 同上 |

### 1.7 workspace（工作区/文件） — 10 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `workspaces` | GET | `/api/workspaces` | — | — | `WorkspacesResponse` |
| `workspaceSuggestions` | GET | `/api/workspaces/suggest` | `prefix` | — | `WorkspaceSuggestionsResponse` |
| `workspaceAdd` | POST | `/api/workspaces/add` | — | `{path, name?, create?}` | `WorkspaceMutationResponse` |
| `workspaceRemove` | POST | `/api/workspaces/remove` | — | `{path}` | `WorkspaceMutationResponse` |
| `workspaceRename` | POST | `/api/workspaces/rename` | — | `{path, name}` | `WorkspaceMutationResponse` |
| `workspaceReorder` | POST | `/api/workspaces/reorder` | — | `{paths: [String]}` | `WorkspaceMutationResponse` |
| `directoryList` | GET | `/api/list` | `session_id`、`path?` | — | `DirectoryListResponse` |
| `file` | GET | `/api/file` | `session_id`、`path` | — | `FileResponse` |
| `rawFile` | GET | `/api/file/raw` | `session_id`、`path` | — | 原始字节 `Data`（二进制，非 JSON） |
| `media` | GET | `/api/media` | `session_id`、`path` | — | 原始字节 `Data`（图片/媒体） |

> 附：`remoteTranscriptMediaData(url)` 不是 Endpoints case，但属于 API 层行为——外部（跨域）媒体 URL 下载**不带**自定义 header、**不带** cookie（用独立公共会话）；同域 URL 走带 header 的正常会话。dio 端等价：同域 → 主 dio；跨域 → 无 header 的裸 dio。

### 1.8 git — 16 个（全部以 `session_id` 定位工作区）

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `gitInfo` | GET | `/api/git-info` | `session_id` | — | `GitInfoResponse` |
| `gitStatus` | GET | `/api/git/status` | `session_id` | — | `GitStatusResponse` |
| `gitBranches` | GET | `/api/git/branches` | `session_id` | — | `GitBranchesResponse` |
| `gitDiff` | GET | `/api/git/diff` | `session_id`、`path`、`kind`（默认 `unstaged`） | — | `GitDiffResponse` |
| `gitFetch` | POST | `/api/git/fetch` | — | `{session_id}` | `GitRemoteActionResponse` |
| `gitPull` | POST | `/api/git/pull` | — | `{session_id}` | `GitRemoteActionResponse` |
| `gitPush` | POST | `/api/git/push` | — | `{session_id}` | `GitRemoteActionResponse` |
| `gitCheckout` | POST | `/api/git/checkout` | — | `{session_id, ref, mode, new_branch?, track?, dirty_mode?}`；mode∈`local\|remote\|new`（本地+new_branch 时自动用 `new`），dirty_mode 固定发 `"block"` | `GitCheckoutResponse` |
| `gitStashCheckout` | POST | `/api/git/stash-checkout` | — | `{session_id, ref, mode, new_branch?, track?}`（**无 dirty_mode**） | `GitCheckoutResponse` |
| `gitStage` | POST | `/api/git/stage` | — | `{session_id, paths: [String]}` | `GitMutationResponse` |
| `gitUnstage` | POST | `/api/git/unstage` | — | `{session_id, paths}` | `GitMutationResponse` |
| `gitDiscard` | POST | `/api/git/discard` | — | `{session_id, paths, delete_untracked}`（默认 false） | `GitMutationResponse` |
| `gitCommit` | POST | `/api/git/commit` | — | `{session_id, message}` | `GitCommitResponse` |
| `gitCommitSelected` | POST | `/api/git/commit-selected` | — | `{session_id, message, paths}` | `GitCommitResponse` |
| `gitCommitMessage` | POST | `/api/git/commit-message` | — | `{session_id}`；**超时 120s** | `GitCommitMessageResponse` |
| `gitCommitMessageSelected` | POST | `/api/git/commit-message-selected` | — | `{session_id, paths}`；**超时 120s** | `GitCommitMessageResponse` |

### 1.9 models（模型/命令/设置/更新） — 9 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `models` | GET | `/api/models` | — | — | `ModelsResponse`（缓存目录） |
| `modelsLive` | GET | `/api/models/live` | — | — | `ModelsLiveResponse`（实时未缓存，服务端回显 provider） |
| `commands` | GET | `/api/commands` | — | — | `CommandsResponse` |
| `defaultModel` | POST | `/api/default-model` | — | `{model}` | `DefaultModelResponse` |
| `reasoning` | GET | `/api/reasoning` | `model?`、`provider?`（非空才发） | — | `ReasoningStatusResponse` |
| `reasoning` | POST | `/api/reasoning` | — | `{effort}` **或** `{display}`（两个独立调用） | `ReasoningStatusResponse` |
| `providers` | GET | `/api/providers` | — | — | `ProvidersResponse` |
| `settings` | GET | `/api/settings` | — | — | `SettingsResponse` |
| `settings` | POST | `/api/settings` | — | `{show_cli_sessions}` **或** `{show_claude_code_sessions}`（服务端按发送的键合并，响应仍是完整 settings） | `SettingsResponse` |
| `updatesCheck` | GET | `/api/updates/check` | — | — | `UpdatesCheckResponse`（缓存状态） |
| `updatesCheck` | POST | `/api/updates/check` | — | `{force: true}` | `UpdatesCheckResponse`（触发真实 git fetch） |
| `updatesApply` | POST | `/api/updates/apply` | — | `{target: "webui"}`（默认 webui，无 agent/force/summary） | `UpdatesApplyResponse`；**服务端会重启**，容忍断连 |

### 1.10 profiles（人格/档案） — 5 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `personalities` | GET | `/api/personalities` | — | — | `PersonalitiesResponse` |
| `setPersonality` | POST | `/api/personality/set` | — | `{session_id, name}` | `PersonalitySetResponse` |
| `profiles` | GET | `/api/profiles` | — | — | `ProfilesResponse` |
| `switchProfile` | POST | `/api/profile/switch` | — | `{name}` | `ProfileSwitchResponse` |
| `createProfile` | POST | `/api/profile/create` | — | `{name, clone_config, default_model?, model_provider?, base_url?, api_key?}`（clone_config 总是发；clone_from 故意不发=从当前 profile 克隆；单 profile 模式 403） | `ProfileCreateResponse` |

### 1.11 insights — 1 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `insights` | GET | `/api/insights` | `days` | — | `InsightsResponse` |

### 1.12 cron — 10 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `crons` | GET | `/api/crons` | — | — | `CronJobsResponse` |
| `cronCreate` | POST | `/api/crons/create` | — | `{prompt, schedule, name?, deliver?, skills: [String], model?, provider?, profile?, toast_notifications}` | `CronMutationResponse` |
| `cronUpdate` | POST | `/api/crons/update` | — | `{job_id, prompt?, schedule?, name?, deliver?, skills?, model?, provider?, profile?, toast_notifications?}`（全可空） | `CronMutationResponse` |
| `cronDelete` | POST | `/api/crons/delete` | — | `{job_id, reason?}`（reason 传 nil） | `CronMutationResponse` |
| `cronRun` | POST | `/api/crons/run` | — | `{job_id, reason?}`（nil） | `CronMutationResponse` |
| `cronPause` | POST | `/api/crons/pause` | — | `{job_id, reason?}`（可空） | `CronMutationResponse` |
| `cronResume` | POST | `/api/crons/resume` | — | `{job_id, reason?}`（nil） | `CronMutationResponse` |
| `cronStatus` | GET | `/api/crons/status` | `job_id?`（nil 时不发） | — | `CronStatusResponse` |
| `cronOutput` | GET | `/api/crons/output` | `job_id`、`limit?`（默认 5） | — | `CronOutputResponse` |
| `cronDeliveryOptions` | GET | `/api/crons/delivery-options` | — | — | `CronDeliveryOptionsResponse` |

### 1.13 kanban — 23 个

路径段占位：`/api/kanban/boards/{slug}`、`/api/kanban/tasks/{cardId}`（cardId/slug 需百分号编码，§2.4）。
**除路径段外所有 kanban 调用都带 `board` 查询参数**（bulk/status/comment 等请求体不含 board，board 在 query）。

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `kanbanConfig` | GET | `/api/kanban/config` | — | — | `KanbanConfiguration` |
| `kanbanBoards` | GET | `/api/kanban/boards` | — | — | `KanbanBoardsResponse` |
| `kanbanCreateBoard` | POST | `/api/kanban/boards` | — | `{slug, name, description, icon, color}` | `KanbanBoardMutationEnvelope` |
| `kanbanEditBoard` | PATCH | `/api/kanban/boards/{slug}` | — | `{name, description, icon, color}`（无 slug） | `KanbanBoardMutationEnvelope` |
| `kanbanArchiveBoard` | DELETE | `/api/kanban/boards/{slug}` | — | 无 | `KanbanBoardMutationEnvelope` |
| `kanbanMakeBoardActive` | POST | `/api/kanban/boards/{slug}/switch` | — | 无 | `KanbanBoardMutationEnvelope` |
| `kanbanDispatch` | POST | `/api/kanban/dispatch` | `board`、`dry_run=true\|false`、`max=8`（固定） | 无 | `KanbanDispatchResult` {spawned, promoted, reclaimed, skipped_unassigned, skipped_nonspawnable, auto_blocked, timed_out, crashed}；**8 个全空 → 报错** |
| `kanbanBoard` | GET | `/api/kanban/board` | `board`、`tenant?`、`assignee?`、`include_archived=true`（可选）、`only_mine=true`（可选）、`since?` | — | `KanbanBoardSnapshot` |
| `kanbanStats` | GET | `/api/kanban/stats` | `board` | — | `KanbanStats` |
| `kanbanAssignees` | GET | `/api/kanban/assignees` | `board` | — | `KanbanAssigneeHistory` |
| `kanbanEvents` | GET | `/api/kanban/events` | `board`、`since`（max(0)）、`limit`（clamp 1–200，默认 200） | — | `KanbanEventsEnvelope` {events[], cursor, latest_event_id(latestEventId), read_only} |
| `kanbanEventsStream` | GET | `/api/kanban/events/stream` | `board`、`since` | — | **SSE（独立帧协议 hello/events，见 §3）** |
| `kanbanCardDetail` | GET | `/api/kanban/tasks/{cardId}` | `board` | — | `KanbanCardDetailEnvelope` |
| `kanbanWorkerLog` | GET | `/api/kanban/tasks/{cardId}/log` | `board`、`tail`（默认 65536，clamp 1–2_000_000） | — | `KanbanWorkerLog` |
| `kanbanAddComment` | POST | `/api/kanban/tasks/{cardId}/comments` | `board` | `{body}` | `KanbanAddCommentResponse` |
| `kanbanCreateCard` | POST | `/api/kanban/tasks` | `board` | `{title, body?, status, priority?, assignee?, tenant?, workspace_kind, workspace_path?, skills?, max_runtime_seconds?, parents?（=[prerequisite_id]）, idempotency_key}` | `KanbanCardMutationEnvelope` |
| `kanbanBulkAction` | POST | `/api/kanban/tasks/bulk` | `board` | `{ids: [String], archive?=true \| status? \| assignee?（空串当无） \| priority?}`（四选一） | `KanbanBulkActionEnvelope` {results[{id, ok, error}], read_only} |
| `kanbanEditCard` | PATCH | `/api/kanban/tasks/{cardId}` | `board` | `{title, body, tenant（可显式 null）, priority, assignee（可显式 null）, status?}` | `KanbanCardMutationEnvelope` |
| `kanbanCardStatus` | PATCH | `/api/kanban/tasks/{cardId}` | `board` | `{status}`；**status≠running 守卫（running 必须走 dispatcher）** | `KanbanCardMutationEnvelope` |
| `kanbanBlockCard` | POST | `/api/kanban/tasks/{cardId}/block` | `board` | `{reason?}` | `KanbanCardMutationEnvelope` |
| `kanbanUnblockCard` | POST | `/api/kanban/tasks/{cardId}/unblock` | `board` | `{}`（reason 传 nil 不发键） | `KanbanCardMutationEnvelope` |
| `kanbanAddDependency` | POST | `/api/kanban/links` | `board` | `{parent_id, child_id}` | `KanbanDependencyMutationEnvelope` |
| `kanbanRemoveDependency` | POST | `/api/kanban/links/delete` | `board` | `{parent_id, child_id}` | `KanbanDependencyMutationEnvelope` |

### 1.14 memory — 2 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `memory` | GET | `/api/memory` | — | — | `MemoryResponse` |
| `memoryWrite` | POST | `/api/memory/write` | — | `{section, content}`（section 为字符串枚举，如 profile/task/…，以 Swift `MemorySection` 为准） | `MemoryWriteResponse` |

### 1.15 skills — 3 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `skills` | GET | `/api/skills` | — | — | `SkillsResponse` |
| `skillContent` | GET | `/api/skills/content` | `name`、`file?` | — | `SkillDetailResponse` |
| `toggleSkill` | POST | `/api/skills/toggle` | — | `{name, enabled}` | `ToggleSkillResponse` |

### 1.16 upload / tts / transcribe — 3 个

| Dart 常量 | 方法 | 路径模板 | 查询参数 | 请求体 | 返回 |
|---|---|---|---|---|---|
| `upload` | POST | `/api/upload` | — | multipart：文本字段 `session_id` + 文件字段 `file`（§4） | `UploadResponse` {filename, path, size, mime, is_image, error} |
| `transcribe` | POST | `/api/transcribe` | — | multipart：仅文件字段 `file`（§4） | `TranscribeResponse` {ok, transcript, error}；**非 2xx 也先解 body** |
| `tts` | POST | `/api/tts` | — | JSON `{text, voice}`（engine 默认 edge，rate/pitch 不发） | **原始音频字节**（audio/mpeg），Accept=`*/*`；服务端全量缓冲非分块 |

---

## 2. ApiClient 类设计（api_client.dart）

### 2.1 结构（dio 封装）

```dart
/// 全局单例（Riverpod Provider 暴露），等价于 Swift 的 actor APIClient
class ApiClient {
  ApiClient({required String baseUrl, ...});

  final Dio _dio;                    // 主客户端：cookie + 自定义头 + 默认 Accept
  final Dio _publicMediaDio;         // 等价 publicMediaSession：无 cookie、无自定义头（仅外部媒体下载）
  final CustomHeaderStore _headerStore; // 内存快照，改后即时生效（不重建 client）
  final Duration _defaultTimeout;    // 60s
  static const _commitMessageTimeout = Duration(seconds: 120);
}
```

- 文件拆分建议：`core/api/api_client.dart`（基类 + 请求原语）、`core/api/api_client_chat.dart`、`api_client_sessions.dart`、`api_client_cron.dart`、`api_client_kanban.dart` 等镜像 Swift 扩展（AGENTS.md §3-§4 允许，保持每个文件一个主类型）。
- 请求原语（镜像 Swift 的 `send` / `sendData` / `sendDataReturningResponse`）：
  - `Future<T> send<T>(Endpoint e, {String method, Map<String, dynamic>? body, Duration? timeout})` — JSON 编解码 + 错误归一化
  - `Future<Uint8List> sendData(...)` — 返回原始字节（rawFile/media/tts）
  - `Future<({Uint8List data, Headers headers})> sendDataReturningResponse(...)` — exportSession 需要读 `Content-Disposition`
- 编码/解码：dio 用 `jsonEncode` 手动序列化 body（模型自带 `toJson()`，手写、snake_case 键名，见 §5）；响应 `jsonDecode` 后走模型 `fromJson`。**不要**用 dio 的 `Map` 自动序列化 + json_serializable。
- 请求级默认（对齐 `sendDataReturningResponse`）：
  - `Accept: application/json`；文件下载端点（export/tts）改 `*/*`
  - 有 body 时 `Content-Type: application/json`
  - 禁用缓存（`Cache-Control: no-cache` 或 dio `cache` 关闭；对齐 reloadIgnoringLocalCacheData）
- 超时：默认 60s；`gitCommitMessage` / `gitCommitMessageSelected` 传 120s。

### 2.2 认证方式（重要结论）

**结论：主认证 = 服务端会话 Cookie；辅认证 = 用户配置的自定义 Header（名字不固定）。没有客户端自动生成的 API key header。**

依据（APIClient.swift L282-296、CustomHeader.swift 全文、AuthManager.swift）：
1. **Cookie 会话**：`POST /api/auth/login {"password": …}` 成功后服务端种 cookie（`httpCookieStorage = .shared`、`httpCookieAcceptPolicy = .always`、`httpShouldSetCookies = true`）。此后每个请求（含 SSE）自动携带 cookie。401 → `unauthorized`。
   - Flutter 端：dio 本身不管理 cookie，用 `dio_cookie_jar` + `cookie_jar`（或等价方案）持久化到本地存储；cookie 与当前服务器绑定。
2. **自定义 Header**（CustomHeader.swift）：用户为反向代理（Authentik 等）配置的任意 header 列表（如 `Authorization: Bearer …`、`X-Api-Key: …`），**每次请求构建时**从 `CustomHeaderStore` 快照读取（改 header 不用重建 client），按 RFC 7230 校验（name 为合法 token、value 无换行、空行跳过）后注入。
   - Flutter 端：`CustomHeaderStore` 内存快照（Provider）+ `flutter_secure_storage` 持久化（**per-server 作用域**，换服务器不串 header，AGENTS.md §6：API Key 禁硬编码、禁日志）；dio `Interceptor` 在 `onRequest` 注入。
3. **合并顺序**：自定义 header 先注入，内置头（Accept/Content-Type）后设置——**内置头永远赢**（SSE 同理，见 PROTOCOL_NOTES.md §1）。
4. **跨域重定向剥离**（CrossOriginHeaderStripper，#277）：同域 → 跨域 3xx 重定向时按名字剥离全部自定义 header 再跟随（dio 默认 `followRedirects=true`，需在 `onRedirect` 拦截实现等价逻辑）；同域重定向保留 header。外部 URL 下载（`remoteTranscriptMediaData` 的跨域分支）根本不发自定义头。
5. **baseURL 同域判定**：scheme + host + 归一化端口（无端口时 http=80 / https=443）全等才算同域。

### 2.3 错误归一化（APIError.swift → Dart ApiException）

```dart
sealed class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
}

class InvalidServerUrlException extends ApiException { ... }       // invalidServerURL
class NetworkException extends ApiException { ... }                // network(underlying) —— 按底层错误分类给中文提示（超时/DNS/连不上/离线/TLS/取消）
class HttpException extends ApiException {
  final int statusCode;
  final String? body;
  final String? serverCode;      // body JSON {code}
  final String? serverMessage;   // body JSON {error|message|detail} 首个非空
  final String? activeStreamId;  // 仅 409：body {active_stream_id}
  final bool stale;              // 仅 409：body {stale: true}
}
class DecodingException extends ApiException { ... }              // decoding(underlying)
class UnauthorizedException extends ApiException { ... }          // 401
```

映射规则（镜像 APIError.swift）：
- dio `DioException` 分类：连接/超时类 → `NetworkException`（细分：timedOut / cannotFindHost+DNS / cannotConnect+连接丢失 / 离线 / TLS / cancelled）；`cancel` 保持取消语义；其余 → `NetworkException.other`。
- 非 2xx：401 → `UnauthorizedException`；其余 → `HttpException(statusCode, body)`，body 尝试 JSON 解析 `{error?, message?, detail?, code?, stale?, active_stream_id?}`（`serverMessage` 取 error→message→detail 首个非空；解析失败字段置 null）。
- 状态码 -1（响应不可读）→ `HttpException(statusCode: -1)`。
- JSON 解码失败 → `DecodingException`。

语义标记（Swift `APIError` 扩展属性，Dart 放 HttpException 的便捷 getter）：
- `indicatesExpiredPendingPrompt`：status==409 && `stale==true` → 审批/澄清"提示已过期"友好态
- `activeStreamId`：status==409 && `active_stream_id` 非空 → 已有活跃流
- `indicatesMissingStream`：status==404 && serverMessage 含 "stream not found"（大小写不敏感）
- `isVanishedSession`：status==404 && serverMessage 含 "Session not found" → 会话已消失

dio 侧注意：`DioException.response` 携带原始 body；**错误路径也必须能取到 body 字符串**（对齐 Swift 的 `String(data:encoding:.utf8)`）。

缓存兜底（CacheFallbackPolicy.swift，供上层离线策略使用，API 层只需暴露判定）：`shouldUseCache(error)` = 网络错误∈{notConnectedToInternet, networkConnectionLost, cannotConnectToHost, dnsLookupFailed, cannotFindHost, dataNotAllowed, timedOut} 或 HTTP∈{408, 502, 503, 504}。

### 2.4 base URL 处理与路径构建

- `Endpoint.url(relativeTo: baseUrl)` 等价：`baseUrl`（**不含尾斜杠**）+ path 直接拼接；query 用 `Uri` 编码。
- **kanban 路径段特殊编码**（Endpoints.swift L563-590）：`{cardId}` / `{slug}` 用 RFC 3986 unreserved 字符集 **减掉 `.`**（即仅 `A-Z a-z 0-9 - _ ~`）做 percent-encoding——**点号也被编码**（防止 `.`/`..` 路径段注入），服务端解码后还原原值。dart 端：`Uri.encodeComponent` 会保留 `-_.~`，需自行再替换 `.` → `%2E`，或手写白名单编码函数。
- 其余 path 为静态模板，无参数拼接。

### 2.5 kanban 专属守卫（对齐 APIClient+Kanban.swift）

- `kanbanJSON` 原语：请求后校验响应头 `Content-Type` 以 `application/json` 开头，否则抛 `KanbanResponseError.nonJSONContentType`（ApiException 子类或自定义异常，业务层 catch）。
- `kanbanDispatch`：结果 8 个计数全 nil → 抛错（`hasKnownCategory == false`）。
- `kanbanCardStatus`：status trim+lowercase 后 == `"running"` → 抛 `KanbanRequestError.runningStatusRequiresDispatcher`（不发请求）。

---

## 3. SSE 客户端与 PROTOCOL_NOTES.md 的关系

- **chat / approval / clarify 三个 SSE 流**（`chatStream`、`approvalStream`、`clarifyStream`）的事件类型映射、载荷结构、容错解码策略、请求头、cookie 行为全部以 `docs/PROTOCOL_NOTES.md` 为准，**本规格不重写**。SSE 客户端实现（`core/api/sse_client.dart`）直接按该文档验收标准编写。
- SSE URL 构建：`chatStream` 带 `stream_id`（重放时 `replay=1&after_seq=N`）；`approvalStream`/`clarifyStream` 带 `session_id`（见 §1.4/1.5 表）。
- **kanban events 流例外**（PROTOCOL_NOTES.md 未覆盖）：`kanbanEventsStream` 是独立帧协议，事件名只有 `hello`（`{cursor, board}`）与 `events`（`{events[], cursor}`，帧 id 取 SSE `lastEventId`），其余事件类型 → ignored，畸形帧 → malformed；`hello.cursor`/`events.cursor` 必须 ≥0。实现参照 `KanbanEventStreamClient.swift`（可用同一 SSE 底座），建议后续单独补一份 kanban 流笔记或直接以该 Swift 文件为准。
- SSE 通用请求头（三个内置头 + 自定义头合并，内置胜出）：`Accept: text/event-stream`、`Cache-Control: no-cache, no-transform`、`Accept-Encoding: identity`（PROTOCOL_NOTES.md §1 已列，实现时照抄）。

---

## 4. 上传 multipart 约束

### 4.1 字段与格式（MultipartFormData.swift + APIClient+Upload/Transcribe）

- boundary：`Boundary-<UUID>`（如 `Boundary-6F1E…`）。
- 文本字段（仅 upload）：
  ```
  --<boundary>\r\n
  Content-Disposition: form-data; name="session_id"\r\n
  \r\n
  <sessionID>\r\n
  ```
- 文件字段：
  ```
  --<boundary>\r\n
  Content-Disposition: form-data; name="file"; filename="<filename>"\r\n
  Content-Type: application/octet-stream\r\n
  \r\n
  <raw bytes>\r\n
  ```
- 结束：`--<boundary>--\r\n`（注意：结束边界带 `--` 后缀和 CRLF）。
- 请求头：`Content-Type: multipart/form-data; boundary=<boundary>`（自定义头先注入、此头后设以获胜——反向代理认证必须能看到它）。
- 字段名清单：`upload` = `session_id`（文本）+ `file`（文件）；`transcribe` = 仅 `file`。

### 4.2 大小/数量上限（客户端与服务端约束分列）

| 约束 | 值 | 来源 |
|---|---|---|
| 服务端 `/api/upload` 上限 | **最多 10 个附件 / 总大小 ≤ 64 MiB**（上传超限返回 4xx + `{error}` body） | 上游 hermes-webui（fork :30002） |
| Hermex 客户端预检 | **单文件 ≤ 20 MB**（`PendingAttachment.maximumUploadBytes = 20*1024*1024`，超限直接本地拒绝并提示） | Models/UploadResponse.swift L111-116 |
| 客户端附件数量预检 | 上传流程按 10 附件上限分批（对齐服务端） | ChatAttachmentCoordinator |

> 实现注意：iOS 端预检（20MB/文件）与服务端上限（64MiB 总量/10 个）并存且不等价——Flutter 端**两者都要实现**：单文件 20MB 本地拦截 + 总量 64MiB/10 附件服务端错误透传。transcribe 无客户端大小预检（服务端错误经 `{ok, transcript, error}` 透传）。

### 4.3 附件引用（chat/start 的 attachments 字段）

每个附件 = 一次 `/api/upload` 的响应形状直接透传（`PendingAttachment.toJSONValue()`，UploadResponse.swift L126-137）：
```json
{"name": "<文件名>", "path": "<服务器相对路径>", "mime": "<mime>", "size": 12345, "is_image": true}
```
- `name`/`path`/`mime` 必发；`size` 有值才发；`is_image` 总是发。
- 发送消息时若带附件，文本尾部追加 `\n\n[Attached files: <path 列表，逗号分隔>]`（ChatViewModel 行为，UI 层处理，API 层只透传 attachments 数组）。

---

## 5. 编解码与模型约定（对齐 AGENTS.md §6）

- 键名映射：Swift 全局 `convertToSnakeCase`（编码） / `convertFromSnakeCase`（解码）→ Dart 端模型手写 `fromJson`/`toJson`，**线上键名一律 snake_case**（如 `session_id`、`model_provider`、`toast_notifications`、`idempotency_key`、`workspace_kind`、`is_image`、`delete_untracked`、`expand_renderable`、`active_stream_id`）。
- 例外（Swift 显式 CodingKeys 保持原样的键，Dart 照抄）：kanban 响应的 `latestEventId`（camelCase！）、`KanbanEvent` 的 `id`/`taskId`/`runId`；SSE ToolStreamEvent 的 `tid`/`id`/`tool_call_id`/`tool_use_id`/`call_id`（见 PROTOCOL_NOTES.md §3）。
- 容错解码：未知字段忽略；字段缺失/类型不符 → 安全默认值（null/空串/0/false），**绝不 crash**；可空字段 `?`。JSON 解析边界允许 `dynamic`，其余禁止。
- `JSONValue` 等价物：Dart 用 `Object?`/`Map<String, Object?>` + 显式转换，或自建轻量 `JsonValue`；attachments 数组即 `List<Map<String, Object?>>`。
- 响应模型文件规划：`core/models/` 下按域建文件（session.dart / chat.dart / kanban.dart / cron.dart / …），一个文件一个主类型。

---

## 6. 编码子代理验收清单

- [ ] `endpoints.dart` 含全部 123 个常量，路径/query/方法与本表逐项一致（含双方法端点：sessionYolo、reasoning、settings、updatesCheck）
- [ ] `chatCancel` 是 GET；`kanbanEditBoard/EditCard/CardStatus` 是 PATCH；`kanbanArchiveBoard` 是 DELETE
- [ ] kanban 路径段 `{slug}`/`{cardId}` 按「字母数字 + `-_~`，点号编码」规则编码
- [ ] 自定义头注入 + 内置头获胜 + 跨域重定向剥离；cookie 持久化（dio_cookie_jar）
- [ ] 错误归一化 5 类 ApiException + 4 个语义标记齐全
- [ ] multipart：upload 带 `session_id`+`file`，transcribe 仅 `file`；单文件 20MB 本地预检 + 服务端 64MiB/10 附件错误透传
- [ ] 超时：默认 60s，git commit-message ×2 为 120s
- [ ] `flutter analyze` 零告警；`flutter test` 全绿（ApiClient 用 mocktail 测路径/参数/解析；模型含畸形输入用例）
- [ ] 本表与 `.reference/hermex-src/Networking/Endpoints.swift` 逐 case 核对无遗漏
