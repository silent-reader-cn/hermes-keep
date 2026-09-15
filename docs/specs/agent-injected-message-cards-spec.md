# Agent 代发消息折叠卡片规格（hermes-ui）

> 目标：把所有 **agent 代发用户消息** 在聊天流里折成紧凑卡片，默认折叠、点击展开；不在 `hermes-agent` 砍输出，只在 Flutter 端做 UI 收敛。对齐 `D:\hermes-webui` 的 Background process 折叠并扩展到全量类型。
> 分支：`feat/desktop-ui-polish`；Cupertino 全量；Riverpod；`flutter analyze` 零告警。

## 1. hermes-agent 代发注入全量清单

> 判定：`role == user`（少数为 `system`）且 `content.lstrip().startswith('[')` 的系统合成消息，文本特征以 `[IMPORTANT:` / `[SYSTEM:` / `[Background` 为主。下表每行给触发点与样例，`role` 为持久化后的 `ChatMessage.role`。

| # | 类别 | 触发点（源码+行号） | 注入样例（首行） | role | 噪音 |
|---|---|---|---|---|---|
| 1 | Background process 单条完成 | `tools/process_registry.py:2916 format_process_notification` / `gateway/run.py:3931 _format_gateway_process_notification` | `[IMPORTANT: Background process proc_xxx completed normally (exit code 0).` / `failed to start` / `terminated by signal` / `marked lost` / `exited` | `user` | 高（刷屏+大输出） |
| 2 | Background process 命中 watch | 同上 `evt_type == watch_match` | `[IMPORTANT: Background process proc_xxx matched watch pattern "xxx"` | `user` | 中 |
| 3 | Background process 聚合（多条） | `gateway/run.py:25435`（`N background processes completed for this session`） | `[IMPORTANT: 3 background processes completed for this session.` | `user` | 中 |
| 4 | Subagent 聚合完成 | `gateway/run.py:25653`（`N background subagent delegations completed`）| `[IMPORTANT: 2 background subagent delegations completed — ...]` | `user` | 中 |
| 5 | Overflow / watch_disabled | `gateway/run.py:3931` 分支 | `[IMPORTANT: <overflow human-readable message>]` | `user` | 低 |
| 6 | Cron 任务提示 | `cron/scheduler.py:4139`（`[IMPORTANT: You are running as a scheduled cron job. DELIVERY: ... SILENT:`）| `[IMPORTANT: You are running as a scheduled cron job. DELIVERY: ...` | `system`（经 prompt 注入，转为首条上下文）| 低（cron 会话首条） |
| 7 | Skill 单体触发 | `agent/skill_commands.py:54 _SKILL_INVOCATION_PREFIX` / `695` | `[IMPORTANT: The user has invoked the "xxx" skill, indicating they want ...]` | `user` | 中 |
| 8 | Skill 束触发 | `agent/skill_bundles.py:347` | `[IMPORTANT: The user has invoked the "xxx" skill bundle, loading N skills together ...]` | `user` | 中 |
| 9 | Topic/channel 自动加载 skill | `gateway/run.py:19119` | `[IMPORTANT: The "xxx" skill is auto-loaded. ...]` | `user` | 低 |
|10 | MCP 重载通知 | `gateway/run.py:23419` / `cli.py:14055` | `[IMPORTANT: MCP servers have been reloaded. ... The tool list ...]` | `user` | 低 |
|11 | 上下文压缩摘要（非折叠对象，反面教材） | `agent/context_compressor.py:194 _BACKGROUND_PROCESS_NOTIFICATION_PREFIX` / 压缩摘要检测 | 压缩摘要含 `[IMPORTANT: Background process` 时仅作“包含”判定，不折叠整条消息 | — | — |

> 备注：conversation_loop 的 `_LENGTH_CONTINUATION_*` / `todo_tool.TODO_INJECTION_HEADER` 为压缩后内部重注，非持久化 `user` 消息，不进入聊天列表折叠范围。

### 1.1 当前 hermes-webui 已处理 vs 遗漏

- 已处理：`static/ui.js:15337 isProcessNoticeText = /^\\[IMPORTANT: Background process /` 仅折叠类别 1（含 watch_match 的同一前缀），聚合 3/4 在 webui 以同样前缀命中故亦被折叠；样式 `static/style.css:2330 .process-notice-*` + 折叠态 `Set` + `renderMessages` 分支 `process-wakeup-notice`。
- 遗漏：类别 6/7/8/9/10 均以 `[IMPORTANT:` 开头但非 `Background process`，在 webui 仍以普通 user 气泡展开，易与真实用户输入混淆且刷屏。本规格要求 hermes-ui **全量折叠 1-10**（6 为 system 可同卡片样式或 system 样式复用，见 §3）。

## 2. Flutter 端检测与分类

### 2.1 检测入口

- 位置：`lib/features/chat/widgets/message_bubble.dart` 内 `ChatMessageBubble.build` 的 `role` 分支前，或抽 `lib/features/chat/widgets/injected_notice_card.dart` + `lib/core/utils/injected_message.dart` 分类器。
- 触发条件：`(message.role == 'user' || message.role == 'system') && _isInjectedNotice(content)`；`local_notice` 不参与。

### 2.2 前缀/正则（大小写/空白容错）

```dart
// 统一先 trimLeft，再 case-insensitive 前缀匹配
bool _isInjectedNotice(String text) {
  final t = text.trimLeft();
  if (!t.startsWith('[')) return false;
  final lower = t.toLowerCase();
  return lower.startsWith('[important: background process') // 1,2,3,4,5
      || lower.startsWith('[important: you are running as a scheduled cron') // 6
      || lower.startsWith('[important: the user has invoked the') // 7,8 (含 bundle)
      || lower.startsWith('[important: the \"') // 9 auto-loaded 兜底（the "xxx" skill is auto-loaded）
      || lower.startsWith('[important: mcp servers have been reloaded') // 10
      || lower.startsWith('[important:') && _containsAny(lower, ['background process','mcp servers','cron job','skill']) // 泛化兜底
      || lower.startsWith('[system: background process'); // 兼容历史 [SYSTEM: ...] 形态
}
```

- 禁止裸 `contains('[IMPORTANT:')` 全量折叠，避免误伤用户手打的 `[IMPORTANT:` 文本；必须结合上述白名单关键词二次确认。
- 历史兼容：`context_compressor._BACKGROUND_PROCESS_NOTIFICATION_PREFIX = "[IMPORTANT: Background process "` 为权威前缀，检测与此对齐。

### 2.3 摘要标题提取（对齐 webui `_formatProcessNoticeSummary`）

- Background process 卡：`Background process {sid} · {status} (exit {code})` 格式
  - `sid`：首行 `Background process (\S+)` 捕获，`>22` 时 `slice(0,10)+'…'+slice(-8)`。
  - `exitCode`：`\(exit[_\s]*code\s*[:=]?\s*(-?\d+)\)` 等三式择一。
  - `status` 词：`completed normally/completed→completed`、`failed to start`、`terminated/killed→terminated`、`marked lost/lost→lost`、`matched watch pattern→matched`、`exited→exited`，否则取 `Background process ...` 后首句；中英映射见 `AppLocalizations`。
- Skill/Cron/MCP 卡：取首行去括号后截断 `≤64` 字符
  - Skill：`Skill · {skillName}`（`\"...\"` 内提取，`bundle` 追加 `bundle`）
  - Cron：`Scheduled task`
  - MCP：`MCP servers reloaded`
  - 兜底：首行去 `[IMPORTANT:` 前缀后 `≤48` 字符。

## 3. 卡片设计（Cupertino）

### 3.1 视觉基线（复用 webui `process-wakeup-notice`）

- 外容器：`Container` `decoration: BoxDecoration(border: Border.all(color: CupertinoColors.separator), borderRadius: 8, color: CupertinoColors.secondarySystemBackground)`，`padding: 8`，`margin` 沿用气泡 `Padding(horizontal:12, vertical:5)`。
- 标题行（`.process-notice-head`）：`Row(spaceBetween)` 左 `Icon(CupertinoIcons.command / hammer / clock / cube)` + `Text(summary, maxLines:1, overflow: ellipsis, fontSize:11, fontWeight:700, letterSpacing:0.04em, uppercase)` 右 `CupertinoButton`（`padding: 2×8, fontSize:11, border: 1px separator, radius:5`）。
- 正文：`Container` `padding:6×8, border: separator, radius:6, color: codeBg/transparent, fontFamily: MiSans mono fallback, fontSize:12, height:1.5, maxHeight:400, overflow:auto`（Flutter 用 `ConstrainedBox(maxHeight:400)` + `SingleChildScrollView` 或 `SelectableText`）。
- 展开态：正文可见；收起态：`hidden`（Flutter 用 `Visibility` / 条件渲染），按钮文案 `Show output / Hide output`（本地化）。
- 深色适配：全部色走 `CupertinoDynamicColor`（`separator`, `secondarySystemBackground`, `label/secondaryLabel`），不在代码里写死 hex。

### 3.2 类型差异化图标/色

| 类型 | 图标 | 标题前缀 |
|---|---|---|
| Background process | `CupertinoIcons.terminal` | Background process |
| Skill / bundle / auto-loaded | `CupertinoIcons.hammer` / `star` | Skill |
| Cron | `CupertinoIcons.clock` | Scheduled task |
| MCP | `CupertinoIcons.cube_box` | MCP |

> 统一字号/间距/圆角，不为每类另起一套尺寸，仅图标与标题前缀区分。

### 3.3 交互与无障碍

- 点击右按钮展开/收起；展开状态按 `message.id`（`messageId ?? role-ts-content`）存于内存 `Set<String>`（列表级 `State`），滚动复用不丢状态（key 仍用 `message.id`）。
- 语义：`Semantics(button: true, label: summary)`，标题 `header:true`。
- 复制：卡片底部保留消息 `copy` 能力（沿用 `message_action_menu` 的 `copy` / `copy_md`）。

## 4. 设置开关

- 建议：**扩展** 而非新增——`collapse_process_notices` 已在 webui 存在，Flutter 侧沿用同一语义并扩大范围为“折叠所有 agent 代发通知”（文案改泛化），避免双开关混淆。
- 键名：`collapse_injected_notices`（Dart 侧）兼容读 `collapse_process_notices` 旧键；持久化 `SharedPreferences`，键 `collapse_injected_notices`，默认 `true`。
- 位置：`SettingsPage` 的 appearance/通用段新增一行（`CupertinoSwitch` 或 `Checkbox`，跟随现有设置样式），`onChanged` 立即 `setState` 并重建列表。
- i18n：`AppLocalizations` 新增 `collapseInjectedNoticesLabel / Description` 与卡片标题/按钮文案（中英）。

## 5. 文件级改动清单

| 文件 | 改动 |
|---|---|
| `lib/core/utils/injected_message.dart` **新建** | 分类器 `isInjectedNotice`, `InjectedNoticeKind` enum, `extractSummary`（含 sid 截断/exitCode/状态映射） |
| `lib/features/chat/widgets/injected_notice_card.dart` **新建** | `InjectedNoticeCard(message, expanded, onToggle)` 纯展示卡片（Cupertino 样式，见 §3） |
| `lib/features/chat/widgets/message_bubble.dart` | 在 `build` 首行检测 `isInjectedNotice` → 直接 `return InjectedNoticeCard`（`user/system` 分支前），保留 `local_notice` 分支 |
| `lib/features/chat/widgets/chat_message_list.dart` | 持有 `Set<String> _expandedNoticeIds`，按 `message.id` 透传 `expanded/onToggle` 给卡片；`ListView.builder` 的 `key` 保持 `ValueKey(message.id)` |
| `lib/features/settings/settings_page.dart` | 新增开关行，读写 `SharedPreferences` 键 `collapse_injected_notices`（兼容旧键），默认开 |
| `lib/l10n/app_localizations.dart` | 新增 8~10 条文案（见 §4 + §2.3 中英映射） |
| `test/features/chat/injected_message_test.dart` **新建** | 分类器单测：每类各 2 条正例 + 大小写/前空白/截断边界 + 误伤用例（用户手打 `[IMPORTANT: hello]` 不应折叠） |
| `test/features/chat/injected_notice_card_test.dart` **新建** | 卡片 widget 测试：默认折叠/展开切换、标题 sid 截断、按钮本地化 |
| `docs/PROTOCOL_NOTES.md` | 可选：追加一节“Agent 代发消息与折叠约定” |

## 6. 易错点

- `message.role` 可能为 `null`（容错解码），分类器必须 `role?.toLowerCase()` 判空，不抛。
- `ListView.builder` 复用：展开态不可存于卡片内部 `State`，必须上提到 `ChatMessageList` 的 `Set`，否则滚动复用错乱。
- `SharedPreferences` 异步：首帧未就绪时按 `true` 渲染，`FutureBuilder` 或 `initState` 预读后 `setState` 纠正，不阻塞列表。
- `analysis_options` 零告警：`prefer_single_quotes`、`avoid_print`、`always_declare_return_types` 等；`const` 仅在真 const 构造上加。
- 深色模式：禁止硬编码色值，全部走 `CupertinoColors.*.resolveFrom(context)`。
- 性能：分类器为纯字符串操作，禁止在 `build` 里做正则编译（预编译 `RegExp` 为 `static final`）。
- 测试：`flutter test` 需覆盖畸形 `content == null` / 空白 / 超长首行（>300 字符）不崩溃。

## 7. 验收

- `flutter analyze` 零告警（含 info）
- `flutter test` 全绿（含新增单测 + 原有用例无回归）
- 手工：各类别消息各一条在聊天列表中均以卡片折叠展示，展开后可见完整原文，开关关闭后退化为普通气泡，深浅模式均正常
- 与 `D:\hermes-webui\static\ui.js` 的 Background process 摘要（sid 截断/exit code/状态词）一致

## 8. 参考源码锚点

- `C:\Users\Admin\AppData\Local\hermes\hermes-agent\tools\process_registry.py:2916` `format_process_notification`
- `C:\Users\Admin\AppData\Local\hermes\hermes-agent\gateway\run.py:3931` `_format_gateway_process_notification` / `25435` 聚合 / `25653` subagent 聚合
- `C:\Users\Admin\AppData\Local\hermes\hermes-agent\cron\scheduler.py:4139`
- `C:\Users\Admin\AppData\Local\hermes\hermes-agent\agent\skill_commands.py:54` / `695` / `agent/skill_bundles.py:347` / `gateway/run.py:19119`
- `D:\hermes-webui\static\ui.js:15337` `_formatProcessNoticeSummary` / `_toggleProcessNotice` / `isProcessNoticeText` / `15846` `process-wakeup-notice` 分支
- `D:\hermes-webui\static\style.css:2330` `.process-notice-*`

## 9. 扩展：全量 [System: / System note: ] 6+ 新增类型（2026-08-22）

> 本次扩展把 `agent/conversation_loop.py:1110/1116/1123/1156` 与 `gateway/run.py:1331/6312/19024` 以及 `agent/memory_manager.py` 的 `[System: ...] / [System note: ...]` 全量纳入折叠，不再原样蓝泡。`context_compressor.py:902` 的 `_synthetic_user_row` 前缀亦以白名单对齐。

### 9.1 新增类别（7 kind，覆盖 ≥6 种注入形态）

| # | 新增 kind | 触发点 | 注入样例（首行，大小写/空白容错） | 摘要（zh / en） | 图标 |
|---|---|---|---|---|---|
| 11 | `continuationNetworkCut` | `conversation_loop.py:1110 _LENGTH_CONTINUATION_NETWORK_STUB` | `[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]` | 网络中断续写 / Continue — network error | `arrow_2_circlepath` |
| 12 | `continuationOutputLimit` | `conversation_loop.py:1116 _LENGTH_CONTINUATION_OUTPUT_LIMIT` | `[System: Your previous response was truncated by the output length limit. Continue exactly where you left off.]` | 输出截断续写 / Continue — output limit | `arrow_2_circlepath` |
| 13 | `continuationToolTooLarge` | `conversation_loop.py:1123 _LENGTH_CONTINUATION_DROPPED_TOOLS_PREFIX` | `[System: Your previous tool call (patch) was too large and the stream timed out ...]` | 工具调用过大续写 / Continue — tool too large | `arrow_2_circlepath` |
| 14 | `codexNudge` | `conversation_loop.py:1156 _CODEX_INCOMPLETE_NUDGE` / `1168 _CODEX_ACK_CONTINUATION_NUDGE` / 裸 `_DROPPED_TOOLCALL_NUDGE_CONTENT` / `_EMPTY_TOOL_RESPONSE_NUDGE` | `[System: Your previous response contained only internal reasoning ...]` / `[System: Continue now. Execute the required tool calls ...]` / `Your previous turn indicated a tool call but none was included.` | 继续执行 / Continue execution | `lightbulb` |
| 15 | `gatewayRecovery` | `gateway/run.py:1331 _prepare_resume_pending_message` / `6312` pending IGNORE | `[System note: The previous turn was interrupted by ...; the gateway is now back online. ...]` / `[System note: A new message has arrived. The conversation history contains pending tool outputs ... IGNORE those pending results.]` | 网关已恢复 / Gateway recovered | `info_circle` |
| 16 | `sessionReset` | `gateway/run.py:19024 suspended/daily/resume_pending_expired/idle` / `19966 first-contact` | `[System note: The user's previous session was stopped and suspended. ...]` / `... automatically reset by the daily schedule ...` / `... expired due to inactivity ...` / `... could not be recovered after a restart ...` / `[System note: This is the user's very first message ever. ...]` | 会话已重置 / Session reset | `info_circle` |
| 17 | `memoryRecall` | `agent/memory_manager.py:356` / `context_compressor.py:902`（含 `<memory-context>` 包裹） | `[System note: The following is recalled memory context, NOT new user input. Treat as authoritative reference data ...]` | 记忆上下文 / Memory recall | `info_circle` |

### 9.2 检测与分类增量

- `isInjectedNotice`：新增 `[System:` / `[System note:` 白名单，记忆类支持 `<memory-context>` 包裹与不以 `[` 开头的裸 nudge（`your previous turn indicated a tool call ...` / `you just executed tool calls but returned an empty response`）的窄白名单，避免误伤用户手打 `[System: hello]`。
- `classify`：新增 7 kind 优先分支（在 overflow 兜底之前），`[System note: This is the user's very first message ever.]` 归 `sessionReset`，`pending IGNORE` 归 `gatewayRecovery`。
- 全部正则保持 `static final` 预编译，`_isInjectedNoticeText` / `classify` 纯字符串操作。

### 9.3 摘要与视觉

- 摘要为固定本地化标题（不截原文）：`continuation→网络中断续写/输出截断续写/工具调用过大续写`、`codex→继续执行`、`gateway→网关已恢复`、`session→会话已重置`、`memory→记忆上下文`（en 侧 `Continue — network error / output limit / tool too large / Continue execution / Gateway recovered / Session reset / Memory recall`）。
- 淡色卡片：复用 §3.1 `secondarySystemBackground` + `separator` + `secondaryLabel`（`CupertinoDynamicColor`），不引入新色板。
- 图标映射：`continuation→arrow_2_circlepath`、`codex→lightbulb`、`gateway/session/memory→info_circle`，其余沿用 `command/hammer/clock/cube`。

### 9.4 测试与验收增量

- 用例包含 `[System: The previous response was cut off ...]`（network cut）中英文摘要断言，及 `gatewayRecovery / sessionReset / memoryRecall / codexNudge` 全覆盖。
- `C:/tmp/f.bat analyze` 零告警，`C:/tmp/f.bat test` 全绿。

## 10. 扩展：异步委派家族 `[ASYNC DELEGATION …]`（2026-09-16）

> 背景（主人报告）：`[ASYNC DELEGATION TASK FAILED …]` 这类「后台扇出里某个子代理已经死了、兄弟还在跑」的提前告警，
> 原先**完全不折叠**，以普通蓝色 user 气泡把整段英文报文（含 Task/Status/Error/Live transcript 四段）裸铺在聊天里，
> 与真实用户输入混淆、且刷屏。本次把该家族三形态全部收进同一套折叠卡片。

### 10.1 触发点（运行版源码，权威）

| 形态 | 生成函数（`hermes-agent/tools/process_registry_notifications.py`） | 触发条件 |
|---|---|---|
| `TASK FAILED` | `_format_task_failure_notice()` L152 | `evt["task_failure_notice"] is True`（`tools/async_delegation.push_task_failure_notice`） |
| `BATCH COMPLETE` | `_format_batch_delegation()` L171 | `evt["is_batch"]` 或 `results` 为 list |
| `COMPLETE` | `_format_async_delegation()` L238 | 单条子代理收口（其余分支） |

> 该前缀同时被 `agent/context_compressor.py` 的 `_synthetic_prefixes`（L901-905，含 `"[ASYNC DELEGATION"`）列为
> producer-owned 合成行 —— 故检测用**整串前缀白名单**，无需关键词二次确认（现实输入不可能手打）。

### 10.2 三形态与摘要

| kind | 首行（实产，em dash `—`） | 摘要 zh | 摘要 en | 图标 |
|---|---|---|---|---|
| `subagentTaskFailed` | `[ASYNC DELEGATION TASK FAILED — deleg_841a0035, task 1/3]` | `委派任务 deleg_841a0035 · 任务 1/3 失败` | `Subagent deleg_841a0035 · task 1/3 failed` | `exclamationmark_triangle` |
| `subagentBatchComplete` | `[ASYNC DELEGATION BATCH COMPLETE — deleg_x]` | `委派任务 deleg_x · 批次完成` | `Subagent deleg_x · batch complete` | `command` |
| `subagentComplete` | `[ASYNC DELEGATION COMPLETE — deleg_y]` | `委派任务 deleg_y · 已完成` | `Subagent deleg_y · completed` | `command` |

- 摘要骨架对齐后台进程卡：`<类型别名> <id> · <状态>`（对照 `后台进程 PROC_x · 已完成 (EXIT 0)`）。
- **分类必须在 `background subagent` 兜底之前**：`COMPLETE` 形态的引导句 `A background subagent you dispatched earlier…`
  会被旧兜底吞成 `subagentAggregated`（旧行为摘要退化为 `[ASYNC DELEGATION COMPLETE — deleg_y` 原始串），必须先行判定。
- 容错：分隔符认 `—` / `–` / `-`（连字符与 en dash 历史兼容）；id >22 字符按「前 10…后 8」中段省略（与 sid 同规则，
  抽 `_elideMiddle` 双族复用）；首行不符合实产模板时回退首行截断（≤64）且**去掉孤立 `[`**（`_firstLineStripped`
  只认 `[IMPORTANT:`/`[SYSTEM:` 前缀，对本族会留一个左括号）。

### 10.3 失败态配色（唯一一处类型着色）

- `subagentTaskFailed` 的图标与标题走红、卡片底色转错误色，**复用工具卡（`tool_call_card.dart`）同一套 token**：
  浅色 `statusRedText` + `LightSurfaces.tintError`，深色 `CupertinoColors.systemRed` + 同色 8% alpha。
- 其余所有 kind 维持中性次要色（`secondaryLabel` / `card` + `secondarySystemBackground`），不新增色板。
- 理由：「兄弟还在跑、这个已经死了」是需要**立刻**被看见的告警，全族同款淡色会让失败与完成在滚动中不可区分；
  同时沿用本 App 既有失败语义色，不引入第二套红。

### 10.4 验收增量

- `test/core/utils/injected_message_test.dart`：三形态检测/分类/中英摘要、id 省略、畸形首行回退、
  `-`/`–` 分隔符容错、`[IMPORTANT: N background subagent delegations completed]` 仍归 `subagentAggregated`（防回归）。
- `test/features/chat/injected_notice_card_extra_test.dart`：三形态图标分派 + 失败态折叠标题（大写渲染与语义标签）+
  失败/中性配色断言（深浅双模式）+ 展开态正文原文一致性。
- `C:/tmp/f.bat analyze` 零告警，`C:/tmp/f.bat test` 全绿。


