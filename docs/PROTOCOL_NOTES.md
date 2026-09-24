# Hermes WebUI 流式协议笔记（SSE / Chat）

> 来源：Hermex `.reference/hermex-src/Networking/SSEClient.swift`（2026-08-16 精读整理）
> 用途：Flutter 端 `core/api/sse_client.dart` 与 `features/chat` 状态机的翻译依据；验收标准。

## 1. SSE 连接

- URL：由 chat/start 返回的 stream 端点（`/api/chat/stream/{id}`）
- 请求头（内置，不可被自定义头覆盖）：
  ```
  Accept: text/event-stream
  Cache-Control: no-cache, no-transform
  Accept-Encoding: identity
  ```
- 自定义头（认证等）合并在内置头**之下**（碰撞时内置头胜出）
- Cookie：共享 cookie 存储、`AcceptPolicy = always`、`httpShouldSetCookies = true`
- 缓存策略：`reloadIgnoringLocalAndRemoteCacheData`（禁止本地缓存）
- 连接错误处理：直接 shutdown（不做重连，由上层决定）

## 2. SSE 事件类型 → Dart 事件映射（完整清单）

| 事件名 | 载荷字段 | Dart 事件 |
|---|---|---|
| `token` | `{text}` | Token(text) |
| `interim_assistant` | `{text, already_streamed}` | InterimAssistant(text, alreadyStreamed) |
| `reasoning` | `{text}` | Reasoning(text) |
| `tool` | ToolStreamEvent（见下） | ToolStarted(evt) |
| `tool_complete` | ToolStreamEvent（见下） | ToolCompleted(evt) |
| `title` | `{session_id, title}` | Title(sessionId, title) |
| `metering` | `{tps, tps_available, estimated, session_id}` | Metering(tps, tpsAvailable, estimated, sessionId) |
| `done` | DonePayload.event（缺失/畸形 → MalformedDone，按「回合已收尾」处理） | Done(event) |
| `initial` | 含澄清标记 → ClarificationPending，否则 ApprovalPending | （分流） |
| `approval` | ApprovalPendingResponse | ApprovalPending |
| `clarify` | ClarificationPendingResponse | ClarificationPending |
| `pending_steer_leftover` | `{text}` | PendingSteerLeftover(text) |
| `stream_end` | — | StreamEnd |
| `cancel` | — | Cancelled |
| `error` / `apperror` | `{error}` 或 `{message}`（两种形状都解） | Error(text) |
| 未知事件 | — | Ignored（静默丢弃） |

## 3. ToolStreamEvent（工具开始/完成共用）

容错字段（全部可空，逐个尝试）：
```
event_type, name, preview, args(Map<String,JSONValue>), duration(Double),
is_error(Bool), stable_id ← 依次取 tid / id / tool_call_id / tool_use_id / call_id 的第一个非空
```

## 4. 其余事件载荷

- **InterimAssistantStreamEvent**: `{text, already_streamed}`
- **MeteringStreamEvent**: `{tps, tps_available, estimated, session_id}`
  - 可展示 tps = tps_available==true && estimated!=true && tps>0 且有限
- **TitleStreamEvent**: `{session_id, title}`
- **DonePayload**: 内含 `event` 字段（event 即 done 事件详情；malformed → `MalformedDoneSseEvent`）
  - done 帧可含全量 session（实测 ~9.7 MB 单帧），慢链路/服务端写超时会截断它；
    截断**不代表回合没结束**（done 是终结帧），故按收尾语义处理而非传输错误
- **ApprovalPendingResponse / ClarificationPendingResponse**：见对应 Swift 模型（approval/clarify 流专用）

## 5. 解码策略（对齐 Hermex 容错）

- 单个事件解码失败 → 返回安全默认值（如空文本），**不中断流**
- done 畸形是唯一**不按传输错误、而按回合收尾**处理的特例（`MalformedDoneSseEvent`）：
  控制层只做一次 status 探活（服务端仍在写 → 正常 resume），否则用 REST transcript 收尾；
  **绝不走 journal 回放**（回放会把同一张巨帧原样重发）
- 未知事件类型 → ignored，不报错
- 所有字符串字段用 lossy 解码（类型不符→nil，不 throw）

## 6. 验收标准（Flutter 端 sse_client）

- [ ] 事件名→事件映射与上表完全一致
- [ ] 畸形载荷不崩流
- [ ] done 畸形 → MalformedDone（控制层按收尾处理：探活 → REST transcript 收尾，不回放）
- [ ] 自定义头与内置头合并顺序正确
- [ ] 单测覆盖每个事件类型 + 畸形输入
