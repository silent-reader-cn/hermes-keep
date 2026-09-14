# Hermex Models → Dart 模型翻译规格（models_spec）

> 依据：`.reference/hermex-src/Models/` 下全部 23 个 Swift 文件（逐一精读），
> 对齐 `AGENTS.md` 第 6 节「模型与 API 约定」。
> 本文件是规格不是代码：字段名、类型、JSON 键、容错规则必须精确，编码子代理按此直接写 Dart。
> 生成日期：2026-08-16。

## 0. 总则（先读）

### 0.1 Hermex 的 JSON 键映射机制（决定性事实）

Hermex 的 `APIClient` 全局配置：

```swift
decoder.keyDecodingStrategy = .convertFromSnakeCase   // 解码：camelCase 属性 ← snake_case JSON 键
encoder.keyEncodingStrategy = .convertToSnakeCase     // 编码：camelCase 属性 → snake_case JSON 键
```

因此 **服务器实际发送/接收的 JSON 键一律是 snake_case**（除非模型里显式写了 `CodingKeys` 的 rawValue 字符串）。Dart 端没有这种全局策略，必须在 `fromJson`/`toJson` 里直接写 snake_case 键名。规则：

1. **默认映射**：Swift 属性 `someFieldName`（未显式指定 rawValue）→ JSON 键 `some_field_name`。
2. **显式 rawValue**：`case turnTps = "_turnTps"` → JSON 键 `_turnTps`，原样保留（含大小写、下划线前缀）。
3. **双键/多键容错**：Swift 代码中形如 `A ?? B ?? C` 的多键尝试，Dart 端按 **同一顺序逐一尝试**，取第一个非 null。主键一律先写 snake_case（真实服务器格式），再写 camelCase 别名（兼容网关/旧版/直接 payload 解码路径）。
4. Dart `toJson` 输出 snake_case（与 `.convertToSnakeCase` 对齐）；显式 rawValue 键原样输出。

> 例外说明：Swift 里 `CodingKeys` 显式写 snake_case rawValue 的键（如 `kickoffPromptSnake = "kickoff_prompt"`）在全局 convertFromSnakeCase 下实际匹配不到原始 snake 键——它存在的意义是兼容**不走 APIClient 默认 decoder 的路径**（SSE 直解、`streamPayload` 的默认 `JSONDecoder()` 等）。Dart 端统一按「snake 优先、camel 其次」处理即可覆盖所有路径，无需区分。

### 0.2 容错总纲（AGENTS.md §6 落地）

- 手写 `fromJson` / `toJson`，**不用 json_serializable**。
- 未知字段一律忽略。
- 字段缺失 → 该字段为 null（可空字段）或默认值（见各模型表）。
- 类型不符 → 用 `lossy_*` 工具做宽容转换；转换失败 → null，**绝不 throw**。
- 嵌套模型解码失败（如单个附件畸形）→ 用「JSONValue 兜底逐项重解」策略，**不因单个坏元素丢弃整个数组**。
- 全部模型实现 `==`/`hashCode`（`Equatable` 语义），列表模型实现 `toString` 便于调试。

### 0.3 文件组织（Dart 侧）

| Swift 文件 | Dart 文件（lib/core/models/） |
|---|---|
| JSONValue.swift | `json_value.dart` |
| ChatMessage.swift（含 lossy 扩展） | `chat_message.dart` + `../utils/lossy_json.dart` |
| MessageAttachment.swift | `message_attachment.dart` |
| ToolCall.swift | `tool_call.dart` |
| Session.swift | `session.dart` |
| Approval.swift | `approval.dart` |
| Clarification.swift | `clarification.dart` |
| Cron.swift | `cron.dart` |
| Memory.swift | `memory.dart` |
| Skills.swift | `skills.dart` |
| Goal.swift | `goal.dart` |
| Workspace.swift | `workspace.dart` |
| GitWorkspace.swift | `git_workspace.dart` |
| Kanban.swift | `kanban.dart` |
| ServerCatalog.swift | `server_catalog.dart` |
| ServerInfo.swift | `server_info.dart` |
| ContextWindowSnapshot.swift | `context_window_snapshot.dart` |
| UploadResponse.swift | `upload_response.dart` |
| TranscribeResponse.swift | `transcribe_response.dart` |
| ServerAccount.swift | `server_account.dart` |
| ModelFavoritesStore.swift | `model_favorite.dart` |
| TurnFileChangeSummary.swift | `turn_file_change.dart`（纯客户端，无 JSON） |
| AttachmentAudioDetection.swift | `attachment_audio_detection.dart`（纯逻辑，无 JSON） |

---

## 1. JSONValue：通用 JSON 类型（Swift enum → Dart sealed class）

### 1.1 结论：用 sealed class，不用 dynamic 包装

**建议 sealed class**（Dart 3 原生），理由：

- Swift 是 `enum JSONValue`（string/number/bool/object/array/null），sealed class 的语义一一对应，且 Dart 3 的 `switch` 穷尽检查在编译期保证所有分支被处理，杜绝漏分支。
- 类型安全：`JsonNumber.value` 是 `double`，不会像 `dynamic` 一样在运行时才炸。
- 支持在同一个文件内提供 Swift 等价辅助方法（`stringValue`、`compactJsonString`、`lossyString` 等），后续模型（ChatMessage content、ToolCall args、KanbanDispatchResult）都要用。
- 禁止 `dynamic` 滥用是 AGENTS.md §4 的硬约束；JSON 解析边界用 sealed class 即可覆盖全部需求。

### 1.2 Dart 设计（lib/core/models/json_value.dart）

```dart
/// 通用 JSON 值。对应 Swift `enum JSONValue`。
/// 解析顺序与 Swift 完全一致：null → bool → number → string → array → object。
sealed class JsonValue {
  const JsonValue();

  factory JsonValue.fromJson(Object? json) {
    if (json == null) return const JsonNull();
    if (json is bool) return JsonBool(json);
    if (json is num) return JsonNumber(json.toDouble());
    if (json is String) return JsonString(json);
    if (json is List) {
      return JsonArray(json.map(JsonValue.fromJson).toList(growable: false));
    }
    if (json is Map) {
      return JsonObject(json.map(
        (k, v) => MapEntry(k.toString(), JsonValue.fromJson(v)),
      ));
    }
    return const JsonNull(); // 类型不符兜底，绝不 throw
  }

  Object? toJson();
}

final class JsonString extends JsonValue {
  const JsonString(this.value);
  final String value;
  @override
  Object? toJson() => value;
}

final class JsonNumber extends JsonValue {
  const JsonNumber(this.value);
  final double value;
  @override
  Object? toJson() => value;
}

final class JsonBool extends JsonValue {
  const JsonBool(this.value);
  final bool value;
  @override
  Object? toJson() => value;
}

final class JsonObject extends JsonValue {
  const JsonObject(this.value);
  final Map<String, JsonValue> value;
  @override
  Object? toJson() => value.map((k, v) => MapEntry(k, v.toJson()));
}

final class JsonArray extends JsonValue {
  const JsonArray(this.value);
  final List<JsonValue> value;
  @override
  Object? toJson() => value.map((e) => e.toJson()).toList(growable: false);
}

final class JsonNull extends JsonValue {
  const JsonNull();
  @override
  Object? toJson() => null;
}
```

### 1.3 辅助方法（同文件，对应 Swift `private extension JSONValue`）

```dart
extension JsonValueX on JsonValue {
  /// 尽力转 String：string 原样 / number 转字符串 / bool → 'true'|'false' / 其余 null。
  /// 对应 Swift `stringValue`（注意 Swift 的 number 分支用 `formatted()`，Dart 用 toString()，
  /// 数值格式细节不影响业务逻辑，统一 toString）。
  String? get stringValue {
    return switch (this) {
      JsonString(:final value) => value,
      JsonNumber(:final value) => value.toString(),
      JsonBool(:final value) => value ? 'true' : 'false',
      _ => null,
    };
  }

  /// 对应 Swift `lossyString` / `clarificationLossyString`（Approval / Clarification 数组元素转字符串）。
  String? get lossyString => stringValue;

  /// 紧凑 JSON 字符串（对应 Swift `compactJSONString`）。实现：jsonEncode(toJson())。
  String? get compactJsonString {
    try {
      return jsonEncode(toJson());
    } catch (_) {
      return null;
    }
  }

  /// 仅当自身是 object 时返回其字段表（对应 Swift `objectValue`）。
  Map<String, JsonValue>? get objectValue =>
      this is JsonObject ? (this as JsonObject).value : null;
}
```

### 1.4 示例

```json
{"name": "write_file", "path": "/tmp/a.txt", "lines": 42, "overwrite": true, "tags": ["x", null]}
```

`JsonValue.fromJson` 解析为 `JsonObject`，`value['lines']` 为 `JsonNumber(42.0)`，`value['tags']` 为 `JsonArray`（含 `JsonNull`）。

---

## 2. 容错解码工具：lossy_json.dart（Swift decodeLossy* 的 Dart 等价）

Swift 辅助函数在 `ChatMessage.swift` 与 `Cron.swift` 中定义为 `KeyedDecodingContainer` 扩展。Dart 无容器概念，等价物为 **`Map<String, Object?>` 上的顶层函数**，放在 `lib/core/utils/lossy_json.dart`。

### 2.1 函数清单（签名 + 语义，逐条对齐 Swift 实现）

```dart
/// === decodeLossyStringIfPresent ===
/// 顺序：String 原样 → int → '\(v)' → double → '\(v)' → bool → 'true'/'false' → 其余 null。
String? lossyString(Map<String, Object?> json, String key);

/// === decodeLossyDoubleIfPresent ===
/// 顺序：double 原样 → String(trim) 尝试 double.parse，失败 null。注意：Swift 不处理 int
/// 分支（Int 会走 String 分支？不——Swift 的 decodeIfPresent(Double) 对整数字面量也能成功，
/// Dart 的 jsonDecode 把整数解为 int，所以必须先补 int 分支：int → toDouble()）。
double? lossyDouble(Map<String, Object?> json, String key);

/// === decodeFlexibleDoubleIfPresent（Cron.swift / Memory.swift 用）===
/// 顺序：double 原样 → int → toDouble() → String(trim) → double.parse → 其余 null。
double? flexibleDouble(Map<String, Object?> json, String key);

/// === decodeLossyIntIfPresent ===
/// 顺序：int 原样 → double（有限，截断向零 + 64 位溢出检查）→ String(trim)：
///   int.parse 优先，失败则 double.parse 再截断 + 溢出检查 → 其余 null。
/// 溢出规则（对齐 Swift Int(exactly:)）：超出 int64 范围返回 null，绝不 crash。
int? lossyInt(Map<String, Object?> json, String key);

/// === decodeLossyBoolIfPresent ===
/// 顺序：bool 原样 → int：0→false / 1→true / 其他→null →
/// String(trim+lowercase)：'true'|'1'|'yes'→true，'false'|'0'|'no'→false，其他→null。
bool? lossyBool(Map<String, Object?> json, String key);

/// 多键顺序尝试：依次对 keys 调用 fn，返回第一个非 null（对应 Swift `A ?? B` 模式）。
/// 用法：lossyStringAny(json, ['kickoff_prompt', 'kickoffPrompt'])
T? firstKey<T>(Map<String, Object?> json, List<String> keys, T? Function(Map<String, Object?>, String) fn);

/// === decodeStringArray（Approval / Clarification 的私有等价）===
/// 按 keys 顺序尝试：1) List<String> 原样；2) List<JsonValue> → 逐元素 lossyString 过滤 null；
/// 3) 单个字符串 → 包装成单元素数组；全部失败 → null。
List<String>? lossyStringArray(Map<String, Object?> json, List<String> keys);

/// 普通可选字段读取（对应 decodeIfPresent 无转换路径）：类型不符返回 null。
String? optString(Map<String, Object?> json, String key);
int? optInt(Map<String, Object?> json, String key);
double? optDouble(Map<String, Object?> json, String key);
bool? optBool(Map<String, Object?> json, String key);
/// T? 嵌套模型读取（对应 `try? decodeIfPresent(T.self)`）：解码失败返回 null。
T? optModel<T>(Map<String, Object?> json, String key, T Function(Map<String, Object?>) fromJson);
/// List<T>? 嵌套数组读取：整数组解码失败返回 null（注意：不等价于逐项兜底，
/// 逐项兜底见各模型的 decodeXxxTolerantly 模式）。
List<T>? optModelList<T>(Map<String, Object?> json, String key, T Function(Map<String, Object?>) fromJson);
```

### 2.2 实现要点（编码子代理必须遵守）

- **int 溢出检查**：`double.toInt()` 对超出 int64 的值行为未定义，必须先判断
  `v >= -9223372036854775808.0 && v < 9223372036854775808.0`（严格小于上界），再 `.truncate().toInt()`；
  字符串路径 `double.parse` 后走同一检查。
- **double 的 int 分支**：Dart `jsonDecode` 把 `42` 解为 `int`，而 Swift 的 `decodeIfPresent(Double)` 能吃掉整数——所以 `lossyDouble`/`flexibleDouble` 必须显式处理 `int`（`(v as num).toDouble()`），否则 `"age_seconds": 120` 会漏解。这是 Dart 端特有的坑。
- 所有函数对 key 缺失返回 null；`json` 里值为 `null` 时一律返回 null。
- 每个函数配单测（AGENTS.md §8）：畸形输入矩阵（缺失/错型/字符串数字/超大数/混合数组）。

---

## 3. 聊天核心模型

### 3.1 ChatMessage（Swift: ChatMessage.swift）

**Dart 类**：`ChatMessage`（lib/core/models/chat_message.dart）
**Identifiable**：`id` getter = `messageId ?? '$role-$timestamp-$content'`（对应 Swift 计算属性）。

| Dart 字段 | 类型 | JSON 键（按尝试顺序） | 容错规则 |
|---|---|---|---|
| role | String? | `role` | lossyString |
| content | String? | `content` | **特殊：content 可为字符串 / 数组 / 任意 JSONValue**（见下） |
| timestamp | double? | `_ts` → `timestamp` | lossyDouble，**先试 `_ts`**（Swift 顺序） |
| messageId | String? | `message_id` | lossyString |
| name | String? | `name` | lossyString |
| toolCallId | String? | `tool_call_id` | lossyString |
| toolUseId | String? | `tool_use_id` | lossyString |
| toolCalls | List\<JsonValue>? | `tool_calls` | optModelList(JsonValue.fromJson)；失败 null |
| contentParts | List\<JsonValue>? | （派生，不直接读 JSON） | 由 content 解码派生（见下） |
| reasoning | String? | `reasoning` | lossyString |
| attachments | List\<MessageAttachment>? | `attachments` | **特殊：decodeAttachmentsTolerantly 逐项兜底**（见下） |
| turnTps | double? | `_turnTps` | lossyDouble（显式 rawValue，含下划线前缀） |

**content 容错解码（对应 decodeContentTolerantly）**，Dart 端 `fromJson` 内联实现：

```
1. lossyString(json, 'content') 非 null → (text: 该字符串, parts: null)
2. 否则读 JsonValue.fromJson(json['content'])：
   - 是 JsonArray → text = 逐元素拼接（元素为 JsonString 直接用；为 JsonObject 且 type=='text'
     时取 text 字段；其余跳过），trim 后空则 null；parts = 原数组
   - 其他 JsonValue → text = value.compactJsonString，parts = null
3. 都没有 → (null, null)
```

**attachments 容错解码（对应 decodeAttachmentsTolerantly）**：

```
1. 快路径：整数组直接逐项解码 [MessageAttachment]（每项 try，坏项跳过——见 3.2 的裸字符串/坏形状容忍）
2. 慢路径：整个数组先解为 List<JsonValue>，逐项 JsonValue.fromJson → 若该项是 object/string
   则再递归 MessageAttachment.fromJson（用该项 toJson 后的 Map），坏项丢弃
3. 都失败 → null
```

**attachments 与 `[Attached files: ...]` 标记合并**（对应 `attachments(_:enrichedByMarkerIn:)`）：解码后若 content 含尾部 `[Attached files: …]` 标记，解析出推断附件，与解码附件按 `identityKey`（name/path 的 basename 小写）合并补全缺的 path/mime/size/isImage。此逻辑放 `MessageAttachment.inferredFromAttachedFilesMarker`（见 3.2）与 ChatMessage 私有合并函数；显示层另用 `contentWithoutAttachedFilesMarker` 去掉标记。纯客户端逻辑，无 JSON。

**示例 JSON**：

```json
{
  "role": "assistant",
  "content": [{"type": "text", "text": "完成了。"}],
  "_ts": 1723700000.5,
  "message_id": "msg-42",
  "tool_calls": [{"id": "call_1", "function": {"name": "write_file", "arguments": "{\"path\":\"/tmp/a.txt\"}"}}],
  "_turnTps": 12.3,
  "attachments": [{"name": "a.png", "path": "/tmp/a.png", "mime": "image/png", "size": 1024, "is_image": true}]
}
```

### 3.2 MessageAttachment（Swift: MessageAttachment.swift）

**Dart 类**：`MessageAttachment`（lib/core/models/message_attachment.dart）

| Dart 字段 | 类型 | JSON 键（按尝试顺序） | 容错规则 |
|---|---|---|---|
| name | String? | `name` → `filename` | lossyString；**支持裸字符串解码**（见下） |
| path | String? | `path` | lossyString |
| mime | String? | `mime` | lossyString |
| size | int? | `size` | lossyInt |
| isImage | bool? | `is_image` | lossyBool |

**裸字符串解码**（对应 Swift 单值容器分支）：若整个元素是字符串（旧服务器把附件存成裸文件名），则 `name = 该字符串`，其余字段 null。

**纯客户端辅助**（无 JSON）：
- `identityKey`：name/path 中第一个非空值的 basename（最后一个 `/` 后一段）小写；都空 → null。
- `inferredFromAttachedFilesMarker(content)`：解析尾部 `[Attached files: ref1, ref2]` 标记生成附件列表；`contentWithoutAttachedFilesMarker(content)` 移除标记。正则/手写解析均可，规则：反向找 `[Attached files:`，到 `]` 结束，`]` 后只能剩空白；逗号分隔 trim 非空。
- `isImageReference`：扩展名 ∈ {jpg,jpeg,png,gif,webp,heic,heif,bmp,tiff,tif}。
- `toJsonValue()`（对应 `toJSONValue`，聊天发送用）：`{"name":…, "path":…, "mime":…, "size":…, "is_image":…}`。
- `chatMessageText(draft, attachments)`：拼接 `[Attached files: …]` 后缀。

**示例 JSON**（对象形态；另需单测覆盖裸字符串形态 `"legacy_file.txt"`）：

```json
{"name": "photo.png", "path": "/uploads/photo.png", "mime": "image/png", "size": 204800, "is_image": true}
```

### 3.3 ToolCall（Swift: ToolCall.swift）

**Dart 类**：`ToolCall`（lib/core/models/tool_call.dart）。**非 JSON 模型**（纯客户端/流式状态），无 fromJson；提供命名构造。

| Dart 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| id | String | `live-tool-<uuid>` | 构造默认 |
| name | String? | null | |
| preview | String? | null | |
| args | Map\<String, JsonValue>? | null | |
| duration | double? | null | |
| isError | bool? | null | |
| isCompleted | bool | false | |
| startedAt | double | DateTime.now().millisecondsSinceEpoch / 1000 | |

派生：`displayName` = trim 后非空 name 否则 `'Tool'`。

### 3.4 PersistedToolCall（Swift: ToolCall.swift）

**Dart 类**：`PersistedToolCall`（同文件）。服务端存档模型，有 fromJson。

| Dart 字段 | 类型 | JSON 键（按尝试顺序） | 容错规则 |
|---|---|---|---|
| name | String? | `name` | lossyString |
| snippet | String? | `snippet` | lossyString |
| tid | String? | `tid` | lossyString |
| assistantMsgIdx | int? | `assistant_msg_idx` → `assistantMsgIdx` | lossyInt |
| args | Map\<String, JsonValue>? | `args` | optModel(JsonValue) 后取 objectValue；失败 null |

派生：`toolCall(fallbackIndex)` → ToolCall(id: tid 非空 ? tid : `persisted-tool-$fallbackIndex`, name, preview: snippet, args, isCompleted: true)。

**示例 JSON**：

```json
{"name": "write_file", "snippet": "Wrote /tmp/a.txt", "tid": "call_9", "assistant_msg_idx": 3, "args": {"path": "/tmp/a.txt"}}
```

### 3.5 ToolCallGroup（Swift: ToolCall.swift）

**Dart 类**：`ToolCallGroup`（同文件）。纯客户端模型，无 JSON。

| Dart 字段 | 类型 | 说明 |
|---|---|---|
| id | String | 默认 uuid；`live(anchorMessageID:, toolCalls:)` → `live-tools-<anchor ?? unanchored>` |
| anchorMessageID | String? | |
| toolCalls | List\<ToolCall> | |

派生：`activityTitle`（`Activity: N tools`）、`isComplete`（全部 isCompleted）、`hasFailedTool`（任一 isError==true）。
静态聚合逻辑 `ToolCallGroup.groups(persistedToolCalls:messages:messageOffset:)`、`merging`、`coalescingByAssistantTurn`、`TranscriptTurnClassifier` 全部为纯 Dart 工具（放同文件或 `turn_classifier.dart`），无 JSON；翻译时保持判定顺序：isUserTurnBoundary（user 且有可见内容或附件）→ turn key 划分。

---
## 4. Session 家族（Swift: Session.swift，16 个模型）

> 所有字段的 JSON 键均为默认 snake_case 映射（APIClient 全局 convertFromSnakeCase），
> 仅 `SessionDetail` 的 `_messages_truncated`/`_messages_offset` 与 `compression_anchor_*` 有显式双键。

### 4.1 响应信封（简单模型，共用规则）

| Swift | Dart 类 | 字段（Dart）→ JSON 键 → 容错 |
|---|---|---|
| SessionsResponse | `SessionsResponse` | `sessions: List<SessionSummary>?` ← `sessions`（optModelList）；`cliCount: int?` ← `cli_count`（lossyInt）；`archivedCount: int?` ← `archived_count`（lossyInt）；`serverTime: double?` ← `server_time`（lossyDouble）；`serverTz: String?` ← `server_tz`（lossyString） |
| SessionSearchResponse | `SessionSearchResponse` | `sessions: List<SessionSummary>?` ← `sessions`；`query: String?` ← `query`（lossyString）；`count: int?` ← `count`（lossyInt） |
| SessionResponse | `SessionResponse` | `session: SessionDetail?` ← `session`（optModel） |
| SessionMutationResponse | `SessionMutationResponse` | `ok: bool?` ← `ok`（lossyBool）；`session: SessionSummary?` ← `session`（optModel）；`error: String?` ← `error`（lossyString） |
| ProjectsResponse | `ProjectsResponse` | `projects: List<ProjectSummary>?` ← `projects`（optModelList） |
| ProjectMutationResponse | `ProjectMutationResponse` | `ok: bool?` ← `ok`；`project: ProjectSummary?` ← `project`（optModel）；`error: String?` ← `error` |
| SessionBranchResponse | `SessionBranchResponse` | `sessionId: String?` ← `session_id`；`title: String?` ← `title`；`parentSessionId: String?` ← `parent_session_id`；`error: String?` ← `error`（均 lossyString） |
| SessionCompressResponse | `SessionCompressResponse` | `ok: bool?` ← `ok`；`session: SessionDetail?` ← `session`（optModel）；`summary: SessionCompressionSummary?` ← `summary`（optModel）；`focusTopic: String?` ← `focus_topic`；`error: String?` ← `error` |
| SessionCompressionSummary | `SessionCompressionSummary` | `headline: String?` ← `headline`；`tokenLine: String?` ← `token_line`；`note: String?` ← `note`；`referenceMessage: String?` ← `reference_message`（均 lossyString）。派生 `compressedTokenEstimate`：tokenLine 按 `→` / `->` 取末段数字 |
| SessionUndoResponse | `SessionUndoResponse` | `ok: bool?` ← `ok`；`removedCount: int?` ← `removed_count`（lossyInt）；`removedPreview: String?` ← `removed_preview`；`error: String?` ← `error` |
| SessionRetryResponse | `SessionRetryResponse` | `ok: bool?` ← `ok`；`lastUserText: String?` ← `last_user_text`；`removedCount: int?` ← `removed_count`；`error: String?` ← `error` |
| SessionStatusResponse | `SessionStatusResponse` | `sessionId: String?` ← `session_id`；`activeStreamId: String?` ← `active_stream_id`；`isStreaming: bool?` ← `is_streaming`（lossyBool）；`pendingUserMessage: String?` ← `pending_user_message`；`error: String?` ← `error` |

### 4.2 ProjectSummary

**Dart 类**：`ProjectSummary`。`id` = `projectId ?? name ?? '<uuid>'`。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| projectId | String? | `project_id` | lossyString |
| name | String? | `name` | lossyString |
| color | String? | `color` | lossyString |
| createdAt | double? | `created_at` | lossyDouble |

**示例 JSON**：`{"project_id": "p1", "name": "hermex", "color": "#4f46e5", "created_at": 1723700000}`

### 4.3 SessionSummary

**Dart 类**：`SessionSummary`。`id` = `sessionId` 非空直接用，否则 `session-<title或untitled>-<createdAt??updatedAt??lastMessageAt??0>`。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| sessionId | String? | `session_id` | lossyString |
| title | String? | `title` | lossyString |
| workspace | String? | `workspace` | lossyString |
| model | String? | `model` | lossyString |
| modelProvider | String? | `model_provider` | lossyString |
| messageCount | int? | `message_count` | lossyInt |
| createdAt | double? | `created_at` | lossyDouble |
| updatedAt | double? | `updated_at` | lossyDouble |
| lastMessageAt | double? | `last_message_at` | lossyDouble |
| pinned | bool? | `pinned` | lossyBool |
| archived | bool? | `archived` | lossyBool |
| projectId | String? | `project_id` | lossyString |
| profile | String? | `profile` | lossyString |
| inputTokens | int? | `input_tokens` | lossyInt |
| outputTokens | int? | `output_tokens` | lossyInt |
| estimatedCost | double? | `estimated_cost` | lossyDouble |
| activeStreamId | String? | `active_stream_id` | lossyString |
| isStreaming | bool? | `is_streaming` | lossyBool |
| isCliSession | bool? | `is_cli_session` | lossyBool |
| userMessageCount | int? | `user_message_count` | lossyInt |
| hasPendingUserMessage | bool? | `has_pending_user_message` | lossyBool |
| pendingStartedAt | double? | `pending_started_at` | lossyDouble |
| worktreePath | String? | `worktree_path` | lossyString |
| sourceTag | String? | `source_tag` | lossyString |
| rawSource | String? | `raw_source` | lossyString |
| sessionSource | String? | `session_source` | lossyString |
| sourceLabel | String? | `source_label` | lossyString |
| parentSessionId | String? | `parent_session_id` | lossyString |
| relationshipType | String? | `relationship_type` | lossyString |
| readOnly | bool? | `read_only` | lossyBool |
| isReadOnly | bool? | `is_read_only` | lossyBool |
| matchType | String? | `match_type` | lossyString |

派生（纯客户端，翻译为 getter）：`isDelegatedSubagentSession`（sourceTag/rawSource/sessionSource/sourceLabel 任一 normalize 后含 `subagent`）、`isClaudeCodeSession`（sourceTag/rawSource 含 `claude_code`）、`isSessionReadOnly`（subagent 或 readOnly==true 或 isReadOnly==true）、`isCronSession`（sessionId 小写以 `cron_` 开头，或四个 source 标记含 `cron`）、`isEmptySidebarPlaceholder`（占位标题且无 sidebar 状态且无消息数）、`shouldAppearInSessionList`。`AutomatedSessionVisibility`（showsCron/showsCli/showsClaudeCode/showsSubagents）为纯 UI 配置类。

**示例 JSON**：

```json
{
  "session_id": "abc123", "title": "帮我写个脚本", "workspace": "/home/u/proj",
  "model": "gpt-4o", "model_provider": "openai", "message_count": 12,
  "created_at": 1723700000.0, "updated_at": 1723700100.0, "last_message_at": 1723700099.0,
  "pinned": false, "archived": false, "project_id": null, "profile": "default",
  "input_tokens": 1234, "output_tokens": 567, "estimated_cost": 0.0123,
  "is_cli_session": false, "user_message_count": 5, "has_pending_user_message": false,
  "source_label": null, "read_only": false
}
```

### 4.4 SessionDetail

**Dart 类**：`SessionDetail`。`id` 规则同 SessionSummary。字段 = SessionSummary 全部字段（除 matchType、hasPendingUserMessage 外，见下表差异）+ 下列专属字段：

| Dart 字段 | 类型 | JSON 键（按尝试顺序） | 容错 |
|---|---|---|---|
| pendingUserMessage | String? | `pending_user_message` | lossyString |
| pendingAttachments | List\<JsonValue>? | `pending_attachments` | optModelList(JsonValue.fromJson) |
| contextLength | int? | `context_length` | lossyInt |
| thresholdTokens | int? | `threshold_tokens` | lossyInt |
| lastPromptTokens | int? | `last_prompt_tokens` | lossyInt |
| messages | List\<ChatMessage>? | `messages` | **decodeMessagesTolerantly**（同 3.1 attachments 的两级兜底模式） |
| toolCalls | List\<PersistedToolCall>? | `tool_calls` | **decodeToolCallsTolerantly**（同上） |
| messagesTruncated | bool? | `_messages_truncated` → `_messagesTruncated` → `messages_truncated` | lossyBool，三键顺序 |
| messagesOffset | int? | `_messages_offset` → `_messagesOffset` → `messages_offset` | lossyInt，三键顺序 |
| compressionAnchorVisibleIdx | int? | `compression_anchor_visible_idx` → `compressionAnchorVisibleIdx` | lossyInt |
| compressionAnchorMessageKey | CompressionAnchorMessageKey? | `compression_anchor_message_key` → `compressionAnchorMessageKey` | optModel，两键 |
| compressionAnchorSummary | String? | `compression_anchor_summary` → `compressionAnchorSummary` | lossyString |

其余字段与 SessionSummary 同表同规则（含 `is_cli_session`、`pending_started_at` 等）。

**示例 JSON**（节选）：

```json
{
  "session_id": "abc123", "title": "帮我写个脚本",
  "context_length": 200000, "threshold_tokens": 160000, "last_prompt_tokens": 54321,
  "messages": [{"role": "user", "content": "你好", "_ts": 1723700000.0}],
  "tool_calls": [{"name": "write_file", "snippet": "...", "tid": "call_9", "assistant_msg_idx": 3}],
  "_messages_truncated": false, "_messages_offset": 0,
  "compression_anchor_visible_idx": 40,
  "compression_anchor_message_key": {"role": "user", "ts": 1723700000.0, "text": "摘要...", "attachments": 0}
}
```

### 4.5 CompressionAnchorMessageKey

**Dart 类**：`CompressionAnchorMessageKey`。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| role | String? | `role` | lossyString |
| ts | double? | `ts` | lossyDouble |
| text | String? | `text` | lossyString |
| attachments | int? | `attachments` | lossyInt |

---

## 5. Approval（Swift: Approval.swift）

### 5.1 ApprovalChoice

**Dart 枚举**：`enum ApprovalChoice { once, session, always, deny }`。
解析：`ApprovalChoice? approvalChoiceFromJson(Object? v)` —— 字符串匹配 4 个 rawValue，未知 → null（对齐 Swift `try? decodeIfPresent`）。

### 5.2 ApprovalPendingResponse

**Dart 类**：`ApprovalPendingResponse`。

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| pending | PendingApproval? | `pending` | optModel |
| pendingCount | int? | `pending_count` → `pendingCount` | lossyInt |

静态 `streamPayload(Map json)`（对齐 Swift）：先解自身（pending 或 pendingCount 非 null 即用）；否则直接解 `PendingApproval`，非空则包装 `(pending, 1)`；否则 `(null, null)`。

### 5.3 PendingApproval

**Dart 类**：`PendingApproval`。`id` = approvalId 非空 ? approvalId : `$command-$description-${displayPatternKeys.join(',')}`。

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| approvalId | String? | `approval_id` → `approvalId` → `id` | lossyString + trim 非空归一（**三键**） |
| command | String? | `command` | lossyString |
| description | String? | `description` | lossyString |
| patternKey | String? | `pattern_key` → `patternKey` | lossyString |
| patternKeys | List\<String>? | `pattern_keys` → `patternKeys` | lossyStringArray |

派生：`displayPatternKeys`（patternKeys 过滤空 trim 后非空用，否则 patternKey 单元素）；`isEmpty`（5 字段全空）。

**示例 JSON**：

```json
{
  "approval_id": "ap_7", "command": "bash",
  "description": "Run destructive command?",
  "pattern_key": "rm -rf", "pattern_keys": ["rm -rf", "git push --force"]
}
```

### 5.4 ApprovalRespondResponse / SessionYoloResponse

**Dart 类**：`ApprovalRespondResponse`。

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| ok | bool? | `ok` | lossyBool |
| choice | ApprovalChoice? | `choice` | 字符串枚举解析，未知 null |
| staleCleared | bool? | `stale_cleared` → `staleCleared` | lossyBool |
| relayed | bool? | `relayed` | lossyBool |
| stale | bool? | `stale` | lossyBool |

**Dart 类**：`SessionYoloResponse`：`ok` ← `ok`；`yoloEnabled` ← `yolo_enabled` → `yoloEnabled`（lossyBool）。

**示例 JSON**（ApprovalRespondResponse）：

```json
{"ok": true, "choice": "always", "stale_cleared": false, "relayed": false, "stale": false}
```

---

## 6. Clarification（Swift: Clarification.swift）

### 6.1 ClarificationPendingResponse

同 5.2 模式：`pending: PendingClarification?` ← `pending`；`pendingCount: int?` ← `pending_count` → `pendingCount`。静态 `streamPayload` 同 5.2。

### 6.2 PendingClarification

**Dart 类**：`PendingClarification`。`id` = clarifyId 非空 ? clarifyId : `$sessionId-$question-$requestedAt`。

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| clarifyId | String? | `clarify_id` → `clarifyId` | lossyString |
| question | String? | `question` | lossyString |
| choicesOffered | List\<String>? | `choices_offered` → `choicesOffered` | lossyStringArray（支持 JSONValue 数组逐项 lossyString、单字符串包数组） |
| sessionId | String? | `session_id` → `sessionId` | lossyString |
| kind | String? | `kind` | lossyString |
| requestedAt | double? | `requested_at` → `requestedAt` | lossyDouble |
| timeoutSeconds | int? | `timeout_seconds` → `timeoutSeconds` | lossyInt |
| expiresAt | double? | `expires_at` → `expiresAt` | lossyDouble |

派生：`displayChoices`（trim 过滤空）、`displayQuestion`（空则默认文案）、`isEmpty`（8 字段全空）。

**示例 JSON**：

```json
{
  "clarify_id": "cl_3", "question": "选哪个方案？",
  "choices_offered": ["方案A", "方案B"], "session_id": "abc123", "kind": "choice",
  "requested_at": 1723700000.0, "timeout_seconds": 300, "expires_at": 1723700300.0
}
```

### 6.3 ClarificationRespondResponse

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| ok | bool? | `ok` | lossyBool |
| response | String? | `response` | lossyString |
| stale | bool? | `stale` | lossyBool |
| staleCleared | bool? | `stale_cleared` → `staleCleared` | lossyBool |
| relayed | bool? | `relayed` | lossyBool |

---

## 7. Cron（Swift: Cron.swift，11 个 JSON 模型）

### 7.1 响应信封

| Swift | Dart 类 | 字段 → JSON 键 → 容错 |
|---|---|---|
| CronJobsResponse | `CronJobsResponse` | `jobs: List<CronJob>?` ← `jobs`（optModelList） |
| CronMutationResponse | `CronMutationResponse` | `ok: bool?` ← `ok`；`job: CronJob?` ← `job`（optModel）；`error: String?` ← `error` |
| CronStatusResponse | `CronStatusResponse` | `jobId: String?` ← `job_id`（optString）；`elapsed: double?` ← `elapsed`（flexibleDouble）；`error: String?` ← `error`（optString）；`running` **特殊**：先试 `running` 为 bool（lossyBool），否则试 `running` 为 `Map<String, double>` → runningJobs（**同一个键两种类型**） |
| CronOutputResponse | `CronOutputResponse` | `jobId: String?` ← `job_id`（optString）；`outputs: List<CronOutputItem>?` ← `outputs`（optModelList） |
| CronOutputItem | `CronOutputItem` | `filename: String?` ← `filename`（optString）；`content: String?` ← `content`（optString）；`id` = filename ?? uuid |
| CronDeliveryOptionsResponse | `CronDeliveryOptionsResponse` | `platforms: List<CronDeliveryOption>?` ← `platforms`（optModelList） |
| CronDeliveryOption | `CronDeliveryOption` | `value: String?` ← `value`（lossyString）；`label: String?` ← `label`（lossyString）；`id` = value ?? label ?? uuid |
| CronRepeat | `CronRepeat` | `times: int?` ← `times`（lossyInt）；`completed: int?` ← `completed`（lossyInt） |

### 7.2 CronJob

**Dart 类**：`CronJob`。`id` = jobId ?? name ?? uuid。

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| jobId | String? | `id` → `job_id` | lossyString（**先 `id` 后 `job_id`**，Swift 顺序） |
| name | String? | `name` | lossyString |
| prompt | String? | `prompt` | lossyString |
| schedule | CronSchedule? | `schedule` | optModel |
| scheduleDisplay | String? | `schedule_display` | lossyString |
| enabled | bool? | `enabled` | lossyBool |
| state | String? | `state` | lossyString |
| nextRunAt | CronDateValue? | `next_run_at` | optModel（解析失败 null，不 throw） |
| lastRunAt | CronDateValue? | `last_run_at` | optModel |
| lastStatus | String? | `last_status` | lossyString |
| lastError | String? | `last_error` | lossyString |
| lastDeliveryError | String? | `last_delivery_error` | lossyString |
| repeatInfo | CronRepeat? | `repeat` | optModel（**显式 rawValue `repeat`**，注意不是 `repeat_info`） |
| deliver | String? | `deliver` | lossyString |
| skills | List\<String>? | `skills` | optModelList(String) |
| model | String? | `model` | lossyString |
| provider | String? | `provider` | lossyString |
| profile | String? | `profile` | lossyString |
| toastNotifications | bool? | `toast_notifications` | lossyBool |

派生：`displayName`（name → scheduleText → 'Untitled Task'）、`scheduleText`（scheduleDisplay ?? schedule.displayText）、`editableScheduleText`（schedule.expression ?? expr ?? runAt ?? every ?? scheduleDisplay）、`status`（CronJobStatus 枚举：needsAttention 两个分支 / paused / off / error / active 判定顺序照抄 Swift）、`isRecurring`（schedule.kind ∈ {cron, interval}）。

### 7.3 CronSchedule

**Dart 类**：`CronSchedule`。**支持裸字符串解码**：整个元素是字符串时 → expression = 该字符串，其余 null。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| kind | String? | `kind` | lossyString |
| expression | String? | `expression` | lossyString |
| expr | String? | `expr` | lossyString |
| runAt | String? | `run_at` | lossyString |
| every | String? | `every` | lossyString |

派生：`displayText` = expression ?? expr ?? runAt ?? every ?? kind。

### 7.4 CronDateValue

**Dart 类**：`CronDateValue`（lib/core/models/cron.dart）。包装 `DateTime date`。**特殊解码**（Swift 单值容器）：
1. 值为 num（int/double）→ `DateTime.fromMillisecondsSinceEpoch((v * 1000).round())`（Unix 秒）；
2. 值为 String → 先 `double.tryParse`（数值时间戳），失败再试 ISO8601（`DateTime.tryParse` 覆盖 `2026-08-16T10:00:00Z` 与带毫秒形式）；
3. 全部失败 → 返回 null（Swift 是 throw，但父模型用 `try?` 吞掉，Dart 端让 fromJson 返回 null 即可）。

**示例 JSON**（CronJob）：

```json
{
  "id": "cron_9", "name": "每日备份", "prompt": "备份数据",
  "schedule": "0 3 * * *", "schedule_display": "每天 03:00", "enabled": true,
  "state": "active", "next_run_at": 1723798800.0, "last_run_at": "2026-08-15T03:00:00Z",
  "last_status": "success", "last_error": null, "repeat": {"times": 30, "completed": 12},
  "deliver": "local", "skills": ["backup"], "model": "gpt-4o", "provider": "openai",
  "profile": "default", "toast_notifications": true
}
```

---

## 8. Memory（Swift: Memory.swift）

### 8.1 MemorySection

**Dart 枚举**：`enum MemorySection { memory, user, soul }`。解析：字符串匹配，未知 → null（对齐 Swift `MemorySection(rawValue:)`）。

### 8.2 MemoryResponse

**Dart 类**：`MemoryResponse`（17 字段全可空）。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| memory | String? | `memory` | optString |
| user | String? | `user` | optString |
| soul | String? | `soul` | optString |
| memoryPath | String? | `memory_path` | optString |
| userPath | String? | `user_path` | optString |
| soulPath | String? | `soul_path` | optString |
| memoryMtime | double? | `memory_mtime` | flexibleDouble |
| userMtime | double? | `user_mtime` | flexibleDouble |
| soulMtime | double? | `soul_mtime` | flexibleDouble |
| projectContext | String? | `project_context` | optString |
| projectContextName | String? | `project_context_name` | optString |
| projectContextPath | String? | `project_context_path` | optString |
| projectContextWorkspace | String? | `project_context_workspace` | optString |
| projectContextMtime | double? | `project_context_mtime` | flexibleDouble |
| projectContextShadowed | bool? | `project_context_shadowed` | **特殊**：bool 原样；否则若为 List → `(list.isNotEmpty)`；否则 null |
| externalNotesEnabled | bool? | `external_notes_enabled` | optBool |

**示例 JSON**：

```json
{
  "memory": "用户偏好…", "user": "…", "soul": "…",
  "memory_path": "/home/u/.hermes/memory.md", "memory_mtime": 1723700000.0,
  "project_context": "…", "project_context_name": "hermex",
  "project_context_path": "/home/u/proj", "project_context_workspace": "default",
  "project_context_shadowed": true, "external_notes_enabled": false
}
```

### 8.3 MemoryWriteResponse

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| ok | bool? | `ok` | optBool |
| section | MemorySection? | `section` | 字符串枚举解析（未知 null） |
| path | String? | `path` | optString |
| error | String? | `error` | optString |

---

## 9. Skills（Swift: Skills.swift）

### 9.1 SkillsResponse / SkillSummary

`SkillsResponse`：`skills: List<SkillSummary>?` ← `skills`。
`SkillSummary`：`id` = name ?? uuid。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| name | String? | `name` | optString |
| category | String? | `category` | optString |
| description | String? | `description` | optString |
| path | String? | `path` | optString |
| disabled | bool? | `disabled` | optBool |
| tags | List\<String>? | `tags` | optModelList(String) |
| relatedSkills | List\<String>? | `related_skills` | optModelList(String) |

**示例 JSON**：`{"name": "hermes-agent", "category": "autonomous-ai-agents", "description": "…", "path": "/skills/hermes-agent", "disabled": false, "tags": ["hermes"], "related_skills": ["codex"]}`

### 9.2 ToggleSkillRequest / ToggleSkillResponse

`ToggleSkillRequest`（编码用，toJson 输出 snake_case）：`name: String`（必填）、`enabled: bool`（必填）。
`ToggleSkillResponse`：`ok: bool?` ← `ok`；`name: String?` ← `name`；`enabled: bool?` ← `enabled`（均 lossy）。

### 9.3 SkillDetailResponse（linked_files 特殊）

**Dart 类**：`SkillDetailResponse`。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| name | String? | `name` | optString |
| content | String? | `content` | optString |
| linkedFiles | List\<String>? | `linked_files` | **特殊多形态**（见下） |

**linkedFiles 解码**（对齐 Swift `decodeLinkedFiles`）：
1. 先试 `Map<String, String>` → 取 keys 排序后列表（空 → null）；
2. 否则试 `JsonValue` → 递归收集字符串名（string→自身；array→逐项递归；object→每个 key：值是 array/其他 → 递归收集，值是 string → 取 key 本身），去重排序；
3. 都没有 → null。

`SkillLinkedFileResponse`：`content: String?` ← `content`；`path: String?` ← `path`。

**示例 JSON**：

```json
{"name": "hermes-agent", "content": "SKILL.md 内容…", "linked_files": {"references/api.md": "…", "templates/x.md": "…"}}
```

> 其余（SkillSlashSuggestion / SkillSlashInvocation / SlashSkillFormatter）为纯客户端逻辑：`slug(for:)` 生成 `/skill` 斜杠名（小写、空白与下划线转 `-`、只留 [a-z0-9-]、去重连字符、trim 两端 `-`）；`suggestions(from:)` / `matching` / `invocation` / `messageText` 照抄。翻译为 `slash_skill_formatter.dart`。

---

## 10. Goal（Swift: Goal.swift）

### 10.1 GoalSubmissionResponse

**Dart 类**：`GoalSubmissionResponse`。

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| ok | bool? | `ok` | lossyBool |
| action | String? | `action` | lossyString |
| message | String? | `message` | lossyString |
| goal | SubmittedGoal? | `goal` | optModel |
| kickoffPrompt | String? | `kickoff_prompt` → `kickoffPrompt` | lossyString 双键 |
| decision | GoalDecision? | `decision` | optModel |

派生：`displayMessage`（message trim 空 → null）、`kickoffPromptText`（同）。

### 10.2 SubmittedGoal（全字段 camel/snake 双键）

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| goal | String? | `goal` | lossyString |
| status | String? | `status` | lossyString |
| turnsUsed | int? | `turns_used` → `turnsUsed` | lossyInt |
| maxTurns | int? | `max_turns` → `maxTurns` | lossyInt |
| lastVerdict | String? | `last_verdict` → `lastVerdict` | lossyString |
| lastReason | String? | `last_reason` → `lastReason` | lossyString |
| pausedReason | String? | `paused_reason` → `pausedReason` | lossyString |

### 10.3 GoalDecision

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| status | String? | `status` | lossyString |
| shouldContinue | bool? | `should_continue` → `shouldContinue` | lossyBool |
| continuationPrompt | String? | `continuation_prompt` → `continuationPrompt` | lossyString |
| verdict | String? | `verdict` | lossyString |
| reason | String? | `reason` | lossyString |
| message | String? | `message` | lossyString |
| messageKey | String? | `message_key` → `messageKey` | lossyString |
| messageArgs | List\<JsonValue>? | `message_args` → `messageArgs` | optModelList(JsonValue.fromJson) |

**示例 JSON**（GoalSubmissionResponse）：

```json
{
  "ok": true, "action": "accepted", "message": "目标已提交",
  "goal": {"goal": "修复 bug", "status": "running", "turns_used": 3, "max_turns": 20, "last_verdict": "continue", "last_reason": "正常推进"},
  "kickoff_prompt": "开始执行", "decision": {"status": "continue", "should_continue": true, "verdict": "continue", "reason": "…", "message": "…", "message_key": "goal.continue", "message_args": []}
}
```

---

## 11. Workspace（Swift: Workspace.swift）

### 11.1 信封与简单模型

| Swift | Dart 类 | 字段 → JSON 键 → 容错 |
|---|---|---|
| WorkspacesResponse | `WorkspacesResponse` | `workspaces: List<WorkspaceRoot>?` ← `workspaces`；`last: String?` ← `last`（optString） |
| WorkspaceSuggestionsResponse | `WorkspaceSuggestionsResponse` | `suggestions: List<String>?` ← `suggestions`；`prefix: String?` ← `prefix` |
| WorkspaceMutationResponse | `WorkspaceMutationResponse` | `ok: bool?` ← `ok`；`workspaces: List<WorkspaceRoot>?` ← `workspaces`；`error: String?` ← `error` |
| DirectoryListResponse | `DirectoryListResponse` | `entries: List<WorkspaceEntry>?` ← `entries`；`path: String?` ← `path`；`workspace: String?` ← `workspace`；`error: String?` ← `error` |
| FileResponse | `FileResponse` | `content: String?` ← `content`；`path` ← `path`；`name` ← `name`；`language: String?` ← `language`；`size: int?` ← `size`（lossyInt）；`lines: int?` ← `lines`（lossyInt）；`error` ← `error` |
| WorkspaceMutationRejection | （本地错误类型，无 JSON） | `serverMessage: String?`，翻译为 Dart 异常类 |

### 11.2 WorkspaceRoot（支持裸字符串）

**Dart 类**：`WorkspaceRoot`：`path: String?`、`name: String?`。
**解码**：整个元素是字符串 → `path = 该字符串, name = null`；否则对象 `path`/`name`（optString）。

**示例 JSON**：`{"path": "/home/u/proj", "name": "proj"}`（另测裸字符串 `"/home/u/proj"`）。

### 11.3 WorkspaceEntry

**Dart 类**：`WorkspaceEntry`。`id` = path ?? name ?? uuid；`isBrowsableDirectory` = isDirectory==true || type=='dir'。

| Dart 字段 | 类型 | JSON 键（顺序） | 容错 |
|---|---|---|---|
| name | String? | `name` | optString |
| path | String? | `path` | optString |
| type | String? | `type` | optString |
| size | int? | `size` | optInt |
| modified | double? | `modified` | optDouble |
| isDirectory | bool? | `is_directory` → `is_dir` | optBool 双键 |

**示例 JSON**：`{"name": "src", "path": "/home/u/proj/src", "type": "dir", "size": null, "modified": 1723700000.0, "is_directory": true}`

### 11.4 请求 DTO（编码用）

| Swift | Dart 类 | toJson（snake_case） |
|---|---|---|
| AddWorkspaceRequest | `AddWorkspaceRequest` | `{path, name?, create?}`（path 必填 String） |
| RemoveWorkspaceRequest | `RemoveWorkspaceRequest` | `{path}` |
| RenameWorkspaceRequest | `RenameWorkspaceRequest` | `{path, name}` |
| ReorderWorkspacesRequest | `ReorderWorkspacesRequest` | `{paths: List<String>}` |

---

## 12. 其余小模型

### 12.1 ContextWindowSnapshot（Swift: ContextWindowSnapshot.swift）

**Dart 类**：`ContextWindowSnapshot`（lib/core/models/context_window_snapshot.dart）。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| contextLength | int? | `context_length` | lossyInt |
| thresholdTokens | int? | `threshold_tokens` | lossyInt |
| lastPromptTokens | int? | `last_prompt_tokens` | lossyInt |
| inputTokens | int? | `input_tokens` | lossyInt |
| outputTokens | int? | `output_tokens` | lossyInt |
| estimatedCost | double? | `estimated_cost` | lossyDouble |
| tokensPerSecond | double? | `tps` | lossyDouble（**键是 `tps`**） |

派生：`tokensUsed`（lastPromptTokens ?? inputTokens）、`percentage`（used/contextLength，除数≤0 → null）、`replacingTokensUsed(int?)`（copyWith）、`compactIndicator`/`tokensLabel`/`formatTokens`（1_000_000 → `%.1fM`、1_000 → `%.1fK`）等格式化逻辑翻译为 `context_window_formatter.dart`。

**示例 JSON**：

```json
{"context_length": 200000, "threshold_tokens": 160000, "last_prompt_tokens": 54321, "input_tokens": 60000, "output_tokens": 1000, "estimated_cost": 0.0123, "tps": 24.5}
```

### 12.2 UploadResponse / PendingAttachment（Swift: UploadResponse.swift）

`UploadResponse`：`filename: String?` ← `filename`；`path` ← `path`；`size: int?` ← `size`（lossyInt）；`mime: String?` ← `mime`；`isImage: bool?` ← `is_image`（lossyBool）；`error: String?` ← `error`。
`PendingAttachment`（本地模型，无 fromJson）：`id`（uuid）、`name`、`path`、`mime`、`size: int?`、`isImage: bool`、`thumbnailData: Uint8List?`；`toJsonValue()` → `{"name", "path", "mime", "size", "is_image"}`；`chatReference`、`chatMessageText` 照抄。上传上限 20 MiB。

**示例 JSON**（UploadResponse）：`{"filename": "a.png", "path": "/uploads/a.png", "size": 204800, "mime": "image/png", "is_image": true}`

### 12.3 ServerInfo 三件套（Swift: ServerInfo.swift）

| Swift | Dart 类 | 字段 → JSON 键 → 容错 |
|---|---|---|
| HealthResponse | `HealthResponse` | `status: String?` ← `status`；`sessions: int?` ← `sessions`（lossyInt）；`activeStreams: int?` ← `active_streams`（lossyInt）；`uptimeSeconds: double?` ← `uptime_seconds`（lossyDouble） |
| AuthStatusResponse | `AuthStatusResponse` | `authEnabled: bool?` ← `auth_enabled`；`loggedIn: bool?` ← `logged_in`；`passwordAuthEnabled: bool?` ← `password_auth_enabled`；`passkeysEnabled: bool?` ← `passkeys_enabled`；`passwordlessEnabled: bool?` ← `passwordless_enabled`（均 lossyBool） |
| LoginResponse | `LoginResponse` | `ok: bool?` ← `ok`（lossyBool）；`message: String?` ← `message`；`error: String?` ← `error` |

### 12.4 TranscribeResponse（Swift: TranscribeResponse.swift）

`TranscribeResponse`：`ok: bool?` ← `ok`；`transcript: String?` ← `transcript`；`error: String?` ← `error`（全可空）。

**示例 JSON**：`{"ok": true, "transcript": "你好世界"}`（另测失败形态 `{"error": "STT not configured"}`）。

---

## 13. GitWorkspace（Swift: GitWorkspace.swift，17 个 JSON 模型）

> GitWorkspace.swift 头部注释明确：共享 decoder 用 `.convertFromSnakeCase`，所以除显式 CodingKeys 外全部走 snake_case。
> 该文件所有字符串/数字字段均为 lossy 或 opt 解码，不再逐格重复容错列（统一：lossyString/lossyInt/lossyBool/lossyDouble，optModel/optModelList）。

### 13.1 git-info 与 git/status 家族

| Swift | Dart 类 | 字段（Dart）→ JSON 键 |
|---|---|---|
| GitInfoResponse | `GitInfoResponse` | `git: GitInfo?` ← `git` |
| GitInfo | `GitInfo` | `branch: String?` ← `branch`；`dirty: int?` ← `dirty`；`modified: int?` ← `modified`；`untracked: int?` ← `untracked`；`ahead: int?` ← `ahead`；`behind: int?` ← `behind`；`isGit: bool?` ← `is_git` |
| GitStatusResponse | `GitStatusResponse` | `git: GitStatus?` ← `git` |
| GitStatus | `GitStatus` | `isGit: bool?` ← `is_git`；`branch: String?` ← `branch`；`upstream: String?` ← `upstream`；`ahead: int?` ← `ahead`；`behind: int?` ← `behind`；`totals: GitTotals?` ← `totals`；`files: List<GitFile>?` ← `files`；`truncated: bool?` ← `truncated`。派生：`trackedFiles`（files 过滤 isIgnoredFile）、`changedCount`（totals.changed ?? trackedFiles.length）、`totalAdditions/totalDeletions` |
| GitTotals | `GitTotals` | `changed/staged/unstaged/untracked/conflicts: int?` ← 同名键（lossyInt） |
| GitFile | `GitFile` | 见 13.2 |
| GitRemoteActionResponse | `GitRemoteActionResponse` | `ok: bool?` ← `ok`；`message: String?` ← `message`；`status: GitStatus?` ← `status` |
| GitMutationResponse | `GitMutationResponse` | `ok: bool?` ← `ok`；`git: GitStatus?` ← `git`；派生 `resolvedStatus` = git |
| GitCommitResponse | `GitCommitResponse` | `ok: bool?` ← `ok`；`commit: String?` ← `commit`；`paths: List<String>?` ← `paths`；`status: GitStatus?` ← `status`；`git: GitStatus?` ← `git`（**双键**）；派生 `resolvedStatus` = status ?? git、`shortSHA`（trim） |
| GitCommitMessageResponse | `GitCommitMessageResponse` | `ok: bool?` ← `ok`；`message: String?` ← `message`；`truncated: bool?` ← `truncated` |

### 13.2 GitFile

**Dart 类**：`GitFile`。`id` = 第一个非空（path ?? workspacePath ?? oldPath，trim 后非空）否则 uuid（**init 时计算**）。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| id | String | （派生） | 见上 |
| path | String? | `path` | lossyString |
| oldPath | String? | `old_path` | lossyString |
| workspacePath | String? | `workspace_path` | lossyString |
| status | String? | `status` | lossyString |
| staged | bool? | `staged` | lossyBool |
| unstaged | bool? | `unstaged` | lossyBool |
| untracked | bool? | `untracked` | lossyBool |
| ignored | bool? | `ignored` | lossyBool |
| conflict | bool? | `conflict` | lossyBool |
| additions | int? | `additions` | lossyInt |
| deletions | int? | `deletions` | lossyInt |
| binary | bool? | `binary` | lossyBool |

派生（翻译为 getter + `GitFileChangeKind` 枚举）：
- `changeKind`（enum：conflict/untracked/added/deleted/renamed/modified/ignored/unknown）：判定顺序照抄 Swift——conflict==true → conflict；isIgnoredFile → ignored；untracked==true → untracked；status 首字符大写 A/D/R/M/T 分支；否则 staged||unstaged → modified，再否则 unknown。
- `isIgnoredFile` = ignored==true || status 大小写不敏感 == 'Ignored'。
- `displayPath` = (path ?? workspacePath ?? '').trim 非空 ? 它 : (oldPath ?? '')。
- `fileName` / `parentDirectory` / `preferredDiffKind`（staged==true && unstaged!=true ? 'staged' : 'unstaged'）。

**示例 JSON**：

```json
{
  "path": "lib/main.dart", "old_path": null, "workspace_path": "lib/main.dart",
  "status": "M", "staged": false, "unstaged": true, "untracked": false,
  "ignored": false, "conflict": false, "additions": 12, "deletions": 3, "binary": false
}
```

### 13.3 git/branches 家族

| Swift | Dart 类 | 字段 → JSON 键 |
|---|---|---|
| GitBranchesResponse | `GitBranchesResponse` | `branches: GitBranches?` ← `branches` |
| GitBranches | `GitBranches` | `isGit: bool?` ← `is_git`；`current: String?` ← `current`；`detached: bool?` ← `detached`；`head: String?` ← `head`；`local: List<GitBranchRef>?` ← `local`；`remote: List<GitBranchRef>?` ← `remote`；`upstream: String?` ← `upstream`；`ahead/behind: int?` ← 同名 |
| GitBranchRef | `GitBranchRef` | `name: String?` ← `name`；`sha: String?` ← `sha`；`updated: int?` ← `updated`（lossyInt）；`updatedRelative: String?` ← `updated_relative`；`author: String?` ← `author`；`subject: String?` ← `subject`；`upstream: String?` ← `upstream`；`ahead/behind: int?` |
| GitCheckoutResponse | `GitCheckoutResponse` | `ok: bool?` ← `ok`；`message: String?` ← `message`；`status: GitStatus?` ← `status`；`git: GitStatus?` ← `git`；`branches: GitBranches?` ← `branches`；`currentBranch: String?` ← `current_branch`；`stashName: String?` ← `stash_name`；`stashed: bool?` ← `stashed`；`restoredStash: GitRestoredStash?` ← `restored_stash`；`restoreFailed: bool?` ← `restore_failed`；`restoreError: String?` ← `restore_error`；`restoreStash: GitRestoredStash?` ← `restore_stash`；派生 `resolvedStatus` = status ?? git |
| GitRestoredStash | `GitRestoredStash` | `ref: String?` ← `ref`；`branch: String?` ← `branch`；`message: String?` ← `message` |

### 13.4 git/diff

| Swift | Dart 类 | 字段 → JSON 键 |
|---|---|---|
| GitDiffResponse | `GitDiffResponse` | `diff: GitDiff?` ← `diff` |
| GitDiff | `GitDiff` | `path: String?` ← `path`；`kind: String?` ← `kind`；`binary: bool?` ← `binary`；`tooLarge: bool?` ← `too_large`；`additions: int?` ← `additions`；`deletions: int?` ← `deletions`；`diff: String?` ← `diff` |

**示例 JSON**（GitDiff）：`{"path": "lib/main.dart", "kind": "modified", "binary": false, "too_large": false, "additions": 12, "deletions": 3, "diff": "@@ -1,3 +1,4 @@…"}`

> 本地模型：`GitBranchMode`（enum local/remote）、`GitCheckoutTarget`（ref/mode/newBranch?/track，id = `mode:ref:newBranch`）为纯客户端，无 JSON。

---

## 14. Kanban（Swift: Kanban.swift，27 个 JSON 模型）

> Kanban 桥是独立版本化的外部服务，Swift 注释明确「每个字段保持可选，服务器加字段/改名绝不导致整体解码失败」。
> 注意 Kanban 大量使用**显式 CodingKeys**（`cardID = "id"`、`taskId`、`runId`、`latestEventId`、`parentId`、`childId`、`commentId`、`workerPid`、`worker`、`tasks`、`parents`、`children`、`endedAt`）——这些键**原样保留**，不走 snake_case 转换。

### 14.1 配置 / 看板列表

| Swift | Dart 类 | 字段（Dart）→ JSON 键 → 容错 |
|---|---|---|
| KanbanConfiguration | `KanbanConfiguration` | `columns: List<String>?` ← `columns`（optModelList）；`assignees: List<String>?` ← `assignees`（**特殊**：先试 List<KanbanAssigneeValue>（元素可为字符串或 {name} 对象）取 name 列表，见下）；`defaultTenant: String?` ← `default_tenant`；`laneByProfile: bool?` ← `lane_by_profile`；`includeArchivedByDefault: bool?` ← `include_archived_by_default`；`renderMarkdown: bool?` ← `render_markdown`；`readOnly: bool?` ← `read_only` |
| KanbanBoardsResponse | `KanbanBoardsResponse` | `boards: List<KanbanBoard>?` ← `boards`；`current: String?` ← `current`；`readOnly: bool?` ← `read_only` |
| KanbanBoard | `KanbanBoard` | `slug/name/description/icon/color: String?` ← 同名；`isCurrent: bool?` ← `is_current`；`total: int?` ← `total`；`counts: Map<String,int>?` ← `counts`（optModel）；`readOnly: bool?` ← `read_only` |
| KanbanBoardMutationEnvelope | `KanbanBoardMutationEnvelope` | `board: KanbanBoard?` ← `board`；`current: String?` ← `current`；`readOnly: bool?` ← `read_only` |

**KanbanAssigneeValue**（私有辅助，Dart 里做成解析函数 `String? kanbanAssigneeName(Object? v)`）：元素是字符串 → 自身；是对象 → `name`（lossyString）。`assignees`/`KanbanAssigneeHistory.assignees` 都用它。

**示例 JSON**（KanbanBoard）：`{"slug": "dev", "name": "开发", "description": "…", "icon": "🛠️", "color": "#4f46e5", "is_current": true, "total": 42, "counts": {"todo": 10, "running": 3}, "read_only": false}`

### 14.2 看板快照 / 列 / 卡

| Swift | Dart 类 | 字段（Dart）→ JSON 键 → 容错 |
|---|---|---|
| KanbanBoardSnapshot | `KanbanBoardSnapshot` | `columns: List<KanbanColumn>?` ← `columns`；`tenants: List<String>?` ← `tenants`；`assignees: List<String>?` ← `assignees`（字符串数组）；`filters: KanbanAppliedFilters?` ← `filters`；`changed: bool?` ← `changed`；`latestEventID: int?` ← `latestEventId`（**显式 camel 键**）；`readOnly: bool?` ← `read_only` |
| KanbanColumn | `KanbanColumn` | `name: String?` ← `name`；`cards: List<KanbanCard>?` ← `tasks`（**键是 `tasks`**） |
| KanbanCard | `KanbanCard` | 见 14.3 |
| KanbanAppliedFilters | `KanbanAppliedFilters` | `tenant: String?` ← `tenant`；`assignee: String?` ← `assignee`；`includeArchived: bool?` ← `include_archived`；`onlyMine: bool?` ← `only_mine`；`profile: String?` ← `profile` |

**示例 JSON**（KanbanBoardSnapshot）：`{"columns": [{"name": "todo", "tasks": []}], "tenants": ["t1"], "assignees": ["alice"], "filters": {"tenant": null, "assignee": "alice", "include_archived": false, "only_mine": false, "profile": null}, "changed": true, "latestEventId": 99, "read_only": false}`

### 14.3 KanbanCard

**Dart 类**：`KanbanCard`。

| Dart 字段 | 类型 | JSON 键 | 容错 |
|---|---|---|---|
| cardID | String? | `id` | lossyString（显式键） |
| title | String? | `title` | lossyString |
| status | KanbanStatus? | `status` | lossyString → `KanbanStatus(rawValue:)` |
| assignee | String? | `assignee` | lossyString |
| body | String? | `body` | lossyString |
| tenant | String? | `tenant` | lossyString |
| priority | int? | `priority` | lossyInt |
| commentCount | int? | `comment_count` | lossyInt |
| linkCounts | KanbanLinkCounts? | `link_counts` | optModel |
| ageSeconds | double? | `age_seconds` | lossyDouble |
| createdAt | String? | `created_at` | lossyString |
| updatedAt | String? | `updated_at` | lossyString |
| workspaceKind | String? | `workspace_kind` | lossyString |
| workspacePath | String? | `workspace_path` | lossyString |
| skills | List\<String>? | `skills` | optModelList(String) |
| maxRuntimeSeconds | int? | `max_runtime_seconds` | lossyInt |
| currentRunID | String? | `currentRunId` | lossyString（显式键） |
| claimLock | String? | `claim_lock` | lossyString |
| claimExpires | String? | `claim_expires` | lossyString |
| workerID | String? | `workerPid` | lossyString（显式键） |

派生：`staleness`（KanbanStaleness 枚举 none/warning/critical：running ≥3600s critical / ≥600s warning；ready ≥3600s warning；blocked ≥86400s critical / ≥3600s warning；无 status/age → none）、`replacingStatus(String)`（copyWith；非 running 时清空 currentRunID/claimLock/claimExpires/workerID）。
**KanbanStatus**：**类**（不是 Dart enum，因需保留未知值）——`class KanbanStatus { final String rawValue; }`，`isSupported` = rawValue.lowercase ∈ {triage,todo,blocked,ready,running,done,archived}。

**示例 JSON**：

```json
{
  "id": "card_1", "title": "实现登录页", "status": "ready", "assignee": "alice",
  "body": "…", "tenant": "t1", "priority": 1, "comment_count": 2,
  "link_counts": {"parents": 1, "children": 0}, "age_seconds": 1200.0,
  "created_at": "2026-08-15T10:00:00Z", "updated_at": "2026-08-15T10:20:00Z",
  "workspace_kind": "hermes", "workspace_path": "/home/u/proj", "skills": ["dart"],
  "max_runtime_seconds": 600, "currentRunId": null, "claim_lock": null,
  "claim_expires": null, "workerPid": null
}
```

### 14.4 卡片详情 / 评论 / 事件 / 运行 / 日志

| Swift | Dart 类 | 字段（Dart）→ JSON 键 → 容错 |
|---|---|---|
| KanbanCardDetailEnvelope | `KanbanCardDetailEnvelope` | `card: KanbanCard?` ← `task`（**键是 `task`**）；`comments: List<KanbanComment>?` ← `comments`；`events: List<KanbanDetailEvent>?` ← `events`；`links: KanbanDependencyLinks?` ← `links`；`runs: List<KanbanDispatchRun>?` ← `runs`；`readOnly: bool?` ← `read_only` |
| KanbanCardMutationEnvelope | `KanbanCardMutationEnvelope` | `card: KanbanCard?` ← `task`；`readOnly: bool?` ← `read_only` |
| KanbanComment | `KanbanComment` | `commentID: String?` ← `id`；`cardID: String?` ← `taskId`；`author: String?` ← `author`；`body: String?` ← `body`；`createdAt: String?` ← `created_at`；派生 `presentationID` = commentID ?? [cardID,author,createdAt,body].join('\|') |
| KanbanDetailEvent | `KanbanDetailEvent` | `eventID: String?` ← `id`；`cardID: String?` ← `taskId`；`runID: String?` ← `run_id`；`kind: String?` ← `kind`；`createdAt: String?` ← `created_at`；`payload: KanbanDetailEventPayload?` ← `payload`；派生 `presentationID` 同 |
| KanbanDetailEventPayload | `KanbanDetailEventPayload` | `status: String?` ← `status`；`reason: String?` ← `reason`；`summary: String?` ← `summary`；`fields: List<String>?` ← `fields` |
| KanbanDependencyLinks | `KanbanDependencyLinks` | `prerequisites: List<String>?` ← `parents`；`dependents: List<String>?` ← `children` |
| KanbanDispatchRun | `KanbanDispatchRun` | `runID: String?` ← `id` → `runId`（双键）；`status: String?` ← `status`；`outcome: String?` ← `outcome`；`summary: String?` ← `summary`；`error: String?` ← `error`；`startedAt: String?` ← `started_at`；`finishedAt: String?` ← `endedAt` → `finished_at`（双键）；`workerID: String?` ← `workerPid` → `worker`（双键）；`logTail: String?` ← `log_tail`；派生 `presentationID` 同 |
| KanbanWorkerLog | `KanbanWorkerLog` | `cardID: String?` ← `taskId`；`exists: bool?` ← `exists`；`sizeBytes: int?` ← `size_bytes`；`content: String?` ← `content`；`truncated: bool?` ← `truncated`（`path` 字段刻意不保留） |
| KanbanAddCommentResponse | `KanbanAddCommentResponse` | `ok: bool?` ← `ok`；`commentID: String?` ← `commentId`；`readOnly: bool?` ← `read_only` |
| KanbanLinkCounts | `KanbanLinkCounts` | `parents: int?` ← `parents`；`children: int?` ← `children` |
| KanbanStats | `KanbanStats` | `total: int?` ← `total`；`byStatus: Map<String,int>?` ← `by_status`；`byAssignee: Map<String,int>?` ← `by_assignee` |
| KanbanAssigneeHistory | `KanbanAssigneeHistory` | `assignees: List<String>?` ← `assignees`（KanbanAssigneeValue 解析） |

**示例 JSON**（KanbanCardDetailEnvelope 节选）：

```json
{
  "task": {"id": "card_1", "title": "实现登录页", "status": "ready"},
  "comments": [{"id": "c1", "taskId": "card_1", "author": "alice", "body": "看看", "created_at": "2026-08-15T10:00:00Z"}],
  "events": [{"id": "e1", "taskId": "card_1", "run_id": "run_2", "kind": "status_change", "created_at": "…", "payload": {"status": "ready", "reason": "…", "summary": "…", "fields": ["a"]}}],
  "links": {"parents": ["card_0"], "children": []},
  "runs": [{"id": "run_2", "status": "completed", "outcome": "success", "summary": "…", "started_at": "…", "endedAt": "…", "workerPid": "1234", "log_tail": "…"}],
  "read_only": false
}
```

### 14.5 事件流 / 批量操作 / dispatch

| Swift | Dart 类 | 字段（Dart）→ JSON 键 → 容错 |
|---|---|---|
| KanbanEventsEnvelope | `KanbanEventsEnvelope` | `events: List<KanbanEvent>?` ← `events`；`cursor: int?` ← `cursor`；`latestEventID: int?` ← `latestEventId`；`readOnly: bool?` ← `read_only` |
| KanbanEvent | `KanbanEvent` | `eventID: int?` ← `id`（lossyInt）；`cardID: String?` ← `taskId`；`runID: String?` ← `runId`；`kind: String?` ← `kind`；`createdAt: int?` ← `created_at`（lossyInt）。payload 刻意不保留 |
| KanbanBulkActionEnvelope | `KanbanBulkActionEnvelope` | `results: List<KanbanBulkActionResult>?` ← `results`；`readOnly: bool?` ← `read_only` |
| KanbanBulkActionResult | `KanbanBulkActionResult` | `cardID: String?` ← `id`；`ok: bool?` ← `ok`；`error: String?` ← `error`。**整元素非对象时三字段全 null**（Swift 用 try? 容器） |
| KanbanDependencyMutationEnvelope | `KanbanDependencyMutationEnvelope` | `ok: bool?` ← `ok`；`changed: bool?` ← `changed`；`prerequisiteID: String?` ← `parentId`；`dependentID: String?` ← `childId`；`readOnly: bool?` ← `read_only` |
| KanbanDispatchResult | `KanbanDispatchResult` | 8 个计数：`spawned/promoted/reclaimed/skipped_unassigned/skipped_nonspawnable/auto_blocked/timed_out/crashed`，每个键值**特殊**：值为数组 → 取数组长度；值为数字 → 截断转 int（有限检查）；值为字符串 → int.parse(trim)；bool/object/null → null（对齐 Swift `KanbanDispatchResult.count`） |

**示例 JSON**（KanbanEventsEnvelope）：`{"events": [{"id": 1, "taskId": "card_1", "runId": "run_2", "kind": "created", "created_at": 1723700000}], "cursor": 5, "latestEventId": 5, "read_only": false}`

> 请求 DTO（编码为 query 参数 + 少量 body，翻译为 Dart 类带 `queryParameters` 方法）：`KanbanBoardRequest`（board/tenant?/assignee?/includeArchived/onlyMine/since? → `board, tenant, assignee, include_archived=true, only_mine=true, since`）、`KanbanEventsRequest`（board/since/limit clamp 1..200）、`KanbanEventsStreamRequest`、`KanbanWorkerLogRequest`（tailBytes clamp 1..2_000_000 → `tail`）、`KanbanDispatchRequest`（dry_run=true/false、max=8）、`KanbanCreateCardRequest`（body 字段：board/title/body?/status/priority?/assignee?/tenant?/workspace_kind/workspace_path?/skills?/max_runtime_seconds?/prerequisite_id?/idempotency_key，board 走 query）、`KanbanEditCardRequest`、`KanbanCardStatusRequest`、`KanbanCardActionRequest`（reason?）、`KanbanDependencyMutationRequest`（prerequisite_id/dependent_id）、`KanbanAddCommentRequest`、`KanbanCreateBoardRequest`/`KanbanEditBoardRequest`（slug/name/description/icon/color）、`KanbanBoardMutationRequest`（slug）。请求体编码一律 snake_case（对应 Swift `.convertToSnakeCase`）。`KanbanBulkAction` 为 sealed 类（changeStatus/assignProfile/setPriority/archiveCards）。
> 校验器（KanbanCardDetailValidator / KanbanCardMutationValidator / KanbanDependencyMutationValidator / KanbanCompatibilityValidator）与错误枚举（KanbanContractViolation / KanbanResponseError）翻译为 Dart 异常与校验函数，抛 `ApiException` 子类。

---

## 15. ServerCatalog（Swift: ServerCatalog.swift，29 个 JSON 模型）

### 15.1 Chat 流控制 / 后台任务 / 命令

| Swift | Dart 类 | 字段（Dart）→ JSON 键 → 容错 |
|---|---|---|
| ChatStartResponse | `ChatStartResponse` | `streamId: String?` ← `stream_id`；`sessionId: String?` ← `session_id`；`error: String?` ← `error` |
| ChatCancelResponse | `ChatCancelResponse` | `ok: bool?` ← `ok`；`cancelled: bool?` ← `cancelled`；`streamId: String?` ← `stream_id`；`error` ← `error` |
| ChatStreamStatusResponse | `ChatStreamStatusResponse` | `active: bool?` ← `active`；`streamId: String?` ← `stream_id`；`replayAvailable: bool?` ← `replay_available`；`journal: RunJournalStatus?` ← `journal` |
| RunJournalStatus | `RunJournalStatus` | `terminal: bool?` ← `terminal`；`terminalState: String?` ← `terminal_state` |
| ChatSteerResponse | `ChatSteerResponse` | `accepted: bool?` ← `accepted`；`fallback: String?` ← `fallback`；`streamId: String?` ← `stream_id`；`error` ← `error` |
| BtwStartResponse | `BtwStartResponse` | `streamId/sessionId/parentSessionId/error` ← `stream_id/session_id/parent_session_id/error` |
| BackgroundStartResponse | `BackgroundStartResponse` | `taskId: String?` ← `task_id`；`streamId` ← `stream_id`；`sessionId` ← `session_id`；`error` |
| BackgroundStatusResponse | `BackgroundStatusResponse` | `results: List<BackgroundResult>?` ← `results` |
| BackgroundResult | `BackgroundResult` | `taskId: String?` ← `task_id`；`prompt: String?` ← `prompt`；`answer: String?` ← `answer`；`completedAt: double?` ← `completed_at`（lossyDouble） |
| CommandsResponse | `CommandsResponse` | `commands: List<AgentCommand>?` ← `commands` |
| AgentCommand | `AgentCommand` | `name: String?` ← `name`；`description: String?` ← `description`；`category: String?` ← `category`；`aliases: List<String>?` ← `aliases`；`argsHint: String?` ← `args_hint`；`subcommands: List<String>?` ← `subcommands`；`cliOnly: bool?` ← `cli_only`；`gatewayOnly: bool?` ← `gateway_only`。`id` = name ?? uuid |

**示例 JSON**（ChatStartResponse）：`{"stream_id": "s_9", "session_id": "abc123"}`

### 15.2 Models / Providers（模型目录）

| Swift | Dart 类 | 字段（Dart）→ JSON 键 → 容错 |
|---|---|---|
| ModelsResponse | `ModelsResponse` | `groups: List<JsonValue>?` ← `groups`；`models: List<JsonValue>?` ← `models`；`defaultModel: String?` ← `default_model`；`activeProvider: String?` ← `active_provider`。派生 `catalogGroups` 见 15.4 |
| ProvidersResponse | `ProvidersResponse` | `providers: List<ProviderSummary>?` ← `providers`；`activeProvider: String?` ← `active_provider` |
| ProviderSummary | `ProviderSummary` | `id: String?` ← `id`；`displayName: String?` ← `display_name`；`hasKey: bool?` ← `has_key`；`configurable: bool?` ← `configurable`；`isSelfHosted: bool?` ← `is_self_hosted`；`baseUrl: String?` ← `base_url`；`isPluginProvider: bool?` ← `is_plugin_provider`；`isOauth: bool?` ← `is_oauth`；`isCustom: bool?` ← `is_custom`；`keySource: String?` ← `key_source`；`authError: String?` ← `auth_error`；`models: List<ProviderModel>?` ← `models`；`modelsTotal: int?` ← `models_total` |
| ProviderModel | `ProviderModel` | `id: String?` ← `id`；`label: String?` ← `label`。**支持裸字符串**：元素为字符串 → id=label=该字符串 |
| DefaultModelResponse | `DefaultModelResponse` | `ok: bool?` ← `ok`；`model: String?` ← `model` |
| ModelsLiveResponse | `ModelsLiveResponse` | `provider: String?` ← `provider`；`models: List<JsonValue>?` ← `models`；`count: int?` ← `count`（lossyInt）。派生 `liveOptions` 见 15.4 |

**示例 JSON**（ProviderSummary）：`{"id": "openai", "display_name": "OpenAI", "has_key": true, "configurable": true, "is_self_hosted": false, "base_url": null, "is_plugin_provider": false, "is_oauth": false, "is_custom": false, "key_source": "env_file", "auth_error": null, "models": [{"id": "gpt-4o", "label": "GPT-4o"}], "models_total": 12}`

### 15.3 设置 / 更新 / 推理 / 人格 / 档案

| Swift | Dart 类 | 字段（Dart）→ JSON 键 → 容错 |
|---|---|---|
| SettingsResponse | `SettingsResponse` | `botName: String?` ← `bot_name`；`webuiVersion` ← `webui_version`；`agentVersion` ← `agent_version`；`theme` ← `theme`；`checkForUpdates: bool?` ← `check_for_updates`；`showCliSessions: bool?` ← `show_cli_sessions`；`showClaudeCodeSessions: bool?` ← `show_claude_code_sessions`；`maxTokens: int?` ← `max_tokens`；`maxTokensEffective: int?` ← `max_tokens_effective`；`authEnabled` ← `auth_enabled`；`passwordAuthEnabled` ← `password_auth_enabled`；`passkeysEnabled` ← `passkeys_enabled`；`passwordlessEnabled` ← `passwordless_enabled` |
| UpdatesCheckResponse | `UpdatesCheckResponse` | `webui: UpdateTargetInfo?` ← `webui`；`agent: UpdateTargetInfo?` ← `agent`；`checkedAt: double?` ← `checked_at`；`disabled: bool?` ← `disabled` |
| UpdateTargetInfo | `UpdateTargetInfo` | `name: String?` ← `name`；`behind: int?` ← `behind`；`currentSha: String?` ← `current_sha`；`latestSha: String?` ← `latest_sha`；`branch: String?` ← `branch`；`repoUrl: String?` ← `repo_url`；`compareUrl: String?` ← `compare_url`；`error: String?` ← `error`；`staleCheck: bool?` ← `stale_check` |
| UpdatesApplyResponse | `UpdatesApplyResponse` | `ok: bool?` ← `ok`；`message: String?` ← `message`；`target: String?` ← `target`；`conflict: bool?` ← `conflict`；`diverged: bool?` ← `diverged`；`restartBlocked: bool?` ← `restart_blocked`；`restartScheduled: bool?` ← `restart_scheduled`；`stashConflict: bool?` ← `stash_conflict`；`activeStreams: int?` ← `active_streams`；`activeRuns: int?` ← `active_runs`。派生 `outcome`（枚举 applying/restartBlocked/failed：先判 restartBlocked 再 ok，顺序照抄） |
| ReasoningStatusResponse | `ReasoningStatusResponse` | `ok: bool?` ← `ok`；`showReasoning: bool?` ← `show_reasoning`；`reasoningEffort: String?` ← `reasoning_effort`；`effort: String?` ← `effort`；`supportedEfforts: List<String>?` ← `supported_efforts`；`supportsReasoningEffort: bool?` ← `supports_reasoning_effort`；`error` ← `error`。派生 `effectiveEffort` = reasoningEffort ?? effort、`normalizedSupportedEfforts`（trim+lowercase+去重保序） |
| PersonalitiesResponse | `PersonalitiesResponse` | `personalities: List<PersonalitySummary>?` ← `personalities` |
| PersonalitySummary | `PersonalitySummary` | `name: String?` ← `name`；`description: String?` ← `description`；`id` = name ?? uuid |
| PersonalitySetResponse | `PersonalitySetResponse` | `ok: bool?` ← `ok`；`personality: String?` ← `personality`；`prompt: String?` ← `prompt`；`error` ← `error` |
| ProfilesResponse | `ProfilesResponse` | `profiles: List<ProfileSummary>?` ← `profiles`；`active: String?` ← `active`；`singleProfileMode: bool?` ← `single_profile_mode` |
| ProfileCreateResponse | `ProfileCreateResponse` | `ok: bool?` ← `ok`；`profile: ProfileSummary?` ← `profile`；`error` ← `error` |
| ProfileSwitchResponse | `ProfileSwitchResponse` | `profiles: List<ProfileSummary>?` ← `profiles`；`active: String?` ← `active`；`defaultModel: String?` ← `default_model`；`defaultWorkspace: String?` ← `default_workspace`；`error` ← `error` |
| ProfileSummary | `ProfileSummary` | `name: String?` ← `name`；`path: String?` ← `path`；`isDefault: bool?` ← `is_default`；`isActive: bool?` ← `is_active`；`gatewayRunning: bool?` ← `gateway_running`；`model: String?` ← `model`；`provider: String?` ← `provider`；`hasEnv: bool?` ← `has_env`；`skillCount: int?` ← `skill_count`。`id` = name ?? path ?? uuid；派生 `displayName`（空→'Profile'，'default'→'Default'）、`normalizedName` |

**示例 JSON**（ProfileSummary）：`{"name": "work", "path": "/home/u/.hermes/profiles/work", "is_default": false, "is_active": true, "gateway_running": true, "model": "gpt-4o", "provider": "openai", "has_env": false, "skill_count": 5}`

### 15.4 ModelCatalog（纯客户端解析，无独立 JSON）

`ModelsResponse.groups` 是 `List<JsonValue>`，Dart 端翻译 `ModelCatalogParser`：

- `ModelCatalogGroup`：`id/name: String`、`providerID: String?`、`models/extraModels: List<ModelCatalogOption>`。
- `ModelCatalogOption`：`id/displayName: String`、`providerID: String?`；`favoriteKey` = (id, providerID)。
- 解析 `groups` 数组（对应 Swift `parseGroups`）：每项须为 JsonObject；`provider_id`/`name` 取 stringValue（trim 空 → null，name 缺省用 providerID，再缺省 'Models'）；`models`/`extra_models` 为 JsonArray → 逐项 object，`id` 必填非空，`displayName` = name ?? label ?? id，`providerID` = 元素 provider_id ?? 组 providerID；models 为空 → 整组丢弃。组 `id` = providerID ?? `$name-$index`。
- `ModelsLiveResponse.liveOptions`：同解析器（providerID 用 normalizedProvider），`mergingLiveModels` 照抄。

---

## 16. 本地持久化模型

### 16.1 ServerAccount（Swift: ServerAccount.swift）

**Dart 类**：`ServerAccount`（lib/core/models/server_account.dart）。本地 Keychain 持久化 JSON blob（非服务端 API），但同样手写 fromJson/toJson。

| Dart 字段 | 类型 | JSON 键 | 容错 / 默认 |
|---|---|---|---|
| id | String | `id` | **必填**：`id` 缺失时用 `url_string`；两者都缺 → **解码失败**（抛 FormatException，由上层捕获——对齐 Swift 的 dataCorruptedError；注意这是全文档唯一允许解码失败的模型） |
| urlString | String | `url_string` | 缺失时用 id |
| displayName | String | `display_name` | 缺失 → `''` |
| initials | String | `initials` | 缺失 → `''` |
| headerLogoColorHex | String | `header_logo_color_hex` | 缺失 → 默认色值（Swift `HeaderLogoColor.defaultHex`，实现时取 #4f46e5 或查蓝本常量） |
| customHeadersRef | String? | `custom_headers_ref` | 缺失 → null |
| createdAt | DateTime | `created_at` | 缺失 → epoch 0（`DateTime.fromMillisecondsSinceEpoch(0)`） |
| updatedAt | DateTime | `updated_at` | 缺失 → = createdAt |

时间戳格式：本地 blob 用 ISO8601 字符串（Swift Date 编码默认），Dart 用 `DateTime.tryParse`；解析失败回退 epoch 0。`ServerRegistry`/`Snapshot`（servers + activeServerID）翻译为 `ServerRegistry`（flutter_secure_storage 持久化，`activate/setActive/remove/update/forgetActiveServer` 方法照抄；`activeServerID` ← `active_server_id`）。

**示例 JSON**：

```json
{
  "id": "http://192.168.1.5:30002", "url_string": "http://192.168.1.5:30002",
  "display_name": "Home", "initials": "H", "header_logo_color_hex": "#4f46e5",
  "custom_headers_ref": "http://192.168.1.5:30002",
  "created_at": "2026-08-01T08:00:00Z", "updated_at": "2026-08-15T12:00:00Z"
}
```

### 16.2 ModelFavoriteKey（Swift: ModelFavoritesStore.swift）

**Dart 类**：`ModelFavoriteKey`（lib/core/models/model_favorite.dart）：`modelID: String`（← `model_id`）、`providerID: String?`（← `provider_id`），实现 == / hashCode。`ModelFavoritesStore` / `ModelRecentsStore` 翻译为基于 `flutter_secure_storage` 或 drift 的本地存储类（key：`hermes.mobile.favoriteModels` / `hermes.mobile.recentModels`，limit 5；去重 + 上限逻辑照抄；`visibleFavoriteOptions/visibleRecentOptions` 依赖 ModelCatalog 解析）。

**示例 JSON**（存储 blob 数组元素）：`{"model_id": "gpt-4o", "provider_id": "openai"}`

---

## 17. 纯客户端逻辑（无 JSON，翻译为工具文件）

| Swift 文件 | Dart 工具文件 | 内容 |
|---|---|---|
| TurnFileChangeSummary.swift | `lib/core/models/turn_file_change.dart` | `TurnFileChange`（path/additions/deletions/action/changeKind/gitFile，id=path；`Action` 枚举 edited/added/deleted/renamed）、`TurnFileChangeSummary`（changes + 派生统计）、`TurnFileChangeAggregator`（工具名→action 映射表、args 路径提取（path/file_path/filename 键 + paths 数组 + edits 数组）、路径归一化（去引号括号、去 ~/ 与 ./、长度 ≤240、拒绝 `://`、忽略 .git/node_modules 等组件）、git/status 匹配与绝对/相对判定）。无 fromJson |
| AttachmentAudioDetection.swift | `lib/core/utils/attachment_audio_detection.dart` | `audioExtensions` 集合（m4a/mp3/wav/aac/caf/ogg/oga/opus/flac）；`isAudio(isImage,mime,name,path)` 判定顺序照抄（isImage==true 直接 false → mime 前缀 audio/ → name 扩展名 → path 扩展名）；`AudioDurationFormatter`（m:ss / h:mm:ss，非有限/负数 → 0:00） |

---

## 18. 模型清单与特殊容错点汇总

### 18.1 覆盖统计

共 **23 个 Swift 文件 → 145 个 Dart 模型**，分布：

| 文件 | 模型数 | 文件 | 模型数 |
|---|---|---|---|
| Session.swift | 16 | ServerCatalog.swift | 29 |
| GitWorkspace.swift | 17 | Kanban.swift | 27 |
| Cron.swift | 11 | Workspace.swift | 11 |
| ServerInfo.swift | 3 | Skills.swift | 6 |
| Clarification.swift | 3 | Approval.swift | 5 |
| Goal.swift | 3 | Memory.swift | 3 |
| ChatMessage.swift | 1 | MessageAttachment.swift | 1 |
| ToolCall.swift | 3 | ContextWindowSnapshot.swift | 1 |
| UploadResponse.swift | 2 | TranscribeResponse.swift | 1 |
| ServerAccount.swift | 1 | ModelFavoritesStore.swift | 1 |
| JSONValue.swift | 1（+6 sealed 子类） | TurnFileChangeSummary / AttachmentAudioDetection | 纯逻辑 |

### 18.2 特殊容错点清单（编码子代理重点核对）

1. **JSONValue 解析顺序**：null → bool → num → String → List → Map，任何类型都不得 throw（§1）。
2. **lossy 函数 Dart 特有坑**：`jsonDecode` 整数解为 `int`，`lossyDouble`/`flexibleDouble` 必须补 int→double 分支；`lossyInt` 必须做 int64 溢出检查（超大 double/字符串 → null 而非 crash）（§2）。
3. **裸字符串解码**（整个 JSON 值是字符串）：MessageAttachment、WorkspaceRoot、CronSchedule、ProviderModel、KanbanAssigneeValue（§3.2/11.2/7.3/15.2/14.1）。
4. **content 多形态**：ChatMessage.content 可为字符串 / 内容部件数组 / 任意 JSON（§3.1）。
5. **数组逐项兜底**：ChatMessage.attachments、SessionDetail.messages / toolCalls 两级解码（快路径整数组 → 慢路径 JSONValue 逐项），坏元素丢弃不拖垮整体（§3.1/4.4）。
6. **双键/三键/四键尝试**：Goal 全家族、Clarification/Approval 全家族、SessionDetail 的 `_messages_*` 三键、`compression_anchor_*` 双键、KanbanDispatchRun 双键——顺序必须与 Swift 一致（§10/5/6/4.4/14.4）。
7. **显式特殊键名**：`_turnTps`/`_ts`（ChatMessage）、`tps`（ContextWindowSnapshot）、`repeat`（CronJob）、`tasks`/`id`/`taskId`/`runId`/`latestEventId`/`parentId`/`childId`/`commentId`/`workerPid`/`worker`/`parents`/`children`/`endedAt`（Kanban）——原样保留大小写，**不转 snake**（§3.1/12.1/7.2/14）。
8. **同一键两种类型**：CronStatusResponse.running（bool 或 Map<String,double>）、MemoryResponse.projectContextShadowed（bool 或 List）、SkillDetailResponse.linked_files（Map<String,String> 或 JsonValue 多形态）、KanbanDispatchResult 计数（数组/数字/字符串）（§7.1/8.2/9.3/14.5）。
9. **枚举未知值**：ApprovalChoice / MemorySection 未知 → null；KanbanStatus 未知值**保留原文**（类而非枚举）（§5.1/8.1/14.3）。
10. **日期多形态**：CronDateValue（数字/数字字符串/ISO8601）（§7.4）；ServerAccount 时间戳 ISO8601 解析失败回退 epoch 0（§16.1）。
11. **唯一允许解码失败**：ServerAccount 无 id 且无 url_string → 抛错（§16.1）。
12. **id 派生规则**：所有 Identifiable 模型 id 优先真实 ID，其次字段拼接，最后 uuid 兜底（各节注明）。

---

## 附录 A：信封类模型示例速查（每个模型 1 行示例）

> 正文各节已给出核心模型的完整示例；本节为全部简单信封模型补齐示例（字段形状与正文字段表一一对应，键名 snake_case）。

### A.1 Session 信封（§4.1，12 个）

```json
// SessionsResponse
{"sessions": [{"session_id": "abc123", "title": "t"}], "cli_count": 2, "archived_count": 5, "server_time": 1723700000.0, "server_tz": "Asia/Shanghai"}
// SessionSearchResponse
{"sessions": [], "query": "bug", "count": 0}
// SessionResponse
{"session": {"session_id": "abc123"}}
// SessionMutationResponse
{"ok": true, "session": {"session_id": "abc123"}, "error": null}
// ProjectsResponse
{"projects": [{"project_id": "p1", "name": "hermex"}]}
// ProjectMutationResponse
{"ok": true, "project": {"project_id": "p1"}, "error": null}
// SessionBranchResponse
{"session_id": "abc123", "title": "分支", "parent_session_id": "abc122", "error": null}
// SessionCompressResponse
{"ok": true, "session": {"session_id": "abc123"}, "summary": {"headline": "已压缩", "token_line": "128k -> 42k", "note": "…", "reference_message": "…"}, "focus_topic": "bug", "error": null}
// SessionUndoResponse
{"ok": true, "removed_count": 2, "removed_preview": "…", "error": null}
// SessionRetryResponse
{"ok": true, "last_user_text": "继续", "removed_count": 2, "error": null}
// SessionStatusResponse
{"session_id": "abc123", "active_stream_id": "s_9", "is_streaming": true, "pending_user_message": null, "error": null}
```

### A.2 Cron 信封（§7.1，8 个）

```json
// CronJobsResponse
{"jobs": [{"id": "cron_9", "name": "备份"}]}
// CronMutationResponse
{"ok": true, "job": {"id": "cron_9"}, "error": null}
// CronStatusResponse
{"job_id": "cron_9", "running": true, "elapsed": 12.5, "error": null}
// CronStatusResponse（running 为 Map 形态）
{"job_id": "cron_9", "running": {"cron_9": 12.5}, "elapsed": 12.5}
// CronOutputResponse
{"job_id": "cron_9", "outputs": [{"filename": "out.txt", "content": "…"}]}
// CronDeliveryOptionsResponse
{"platforms": [{"value": "local", "label": "本地"}, {"value": "telegram", "label": "Telegram"}]}
// CronRepeat（内嵌于 CronJob.repeat）
{"times": 30, "completed": 12}
```

### A.3 GitWorkspace 信封（§13.1/13.3/13.4）

```json
// GitInfoResponse
{"git": {"branch": "main", "dirty": 2, "modified": 1, "untracked": 1, "ahead": 0, "behind": 1, "is_git": true}}
// GitInfoResponse（非仓库）
{"git": null}
// GitStatusResponse
{"git": {"is_git": true, "branch": "main", "upstream": "origin/main", "ahead": 0, "behind": 1, "totals": {"changed": 3, "staged": 1, "unstaged": 2, "untracked": 1, "conflicts": 0}, "files": [{"path": "lib/main.dart", "status": "M"}], "truncated": false}}
// GitBranchesResponse
{"branches": {"is_git": true, "current": "main", "detached": false, "head": "abc1234", "local": [{"name": "main", "sha": "abc1234", "updated": 1723700000, "updated_relative": "2 小时前", "author": "me", "subject": "fix", "upstream": "origin/main", "ahead": 0, "behind": 0}], "remote": [], "upstream": "origin/main", "ahead": 0, "behind": 0}}
// GitRemoteActionResponse
{"ok": true, "message": "已推送", "status": {"is_git": true, "branch": "main"}}
// GitCheckoutResponse
{"ok": true, "message": "已切换", "status": {"is_git": true, "branch": "dev"}, "current_branch": "dev", "stash_name": null, "stashed": false, "restored_stash": null, "restore_failed": false, "restore_error": null}
// GitMutationResponse
{"ok": true, "git": {"is_git": true, "branch": "main"}}
// GitCommitResponse
{"ok": true, "commit": "abc1234", "paths": ["lib/main.dart"], "status": {"is_git": true, "branch": "main"}}
// GitCommitMessageResponse
{"ok": true, "message": "feat: …", "truncated": false}
// GitDiffResponse
{"diff": {"path": "lib/main.dart", "kind": "modified", "binary": false, "too_large": false, "additions": 12, "deletions": 3, "diff": "@@ …"}}
```

### A.4 ServerCatalog 信封（§15.1/15.3）

```json
// ChatCancelResponse
{"ok": true, "cancelled": true, "stream_id": "s_9", "error": null}
// ChatStreamStatusResponse
{"active": true, "stream_id": "s_9", "replay_available": false, "journal": {"terminal": true, "terminal_state": "completed"}}
// ChatSteerResponse
{"accepted": true, "fallback": null, "stream_id": "s_9", "error": null}
// BtwStartResponse
{"stream_id": "s_10", "session_id": "abc124", "parent_session_id": "abc123", "error": null}
// BackgroundStartResponse
{"task_id": "t_1", "stream_id": "s_11", "session_id": "abc125", "error": null}
// BackgroundStatusResponse
{"results": [{"task_id": "t_1", "prompt": "…", "answer": "…", "completed_at": 1723700000.0}]}
// CommandsResponse
{"commands": [{"name": "skill", "description": "…", "category": "skills", "aliases": ["/s"], "args_hint": "<name>", "subcommands": ["list"], "cli_only": false, "gateway_only": false}]}
// DefaultModelResponse
{"ok": true, "model": "gpt-4o"}
// ModelsLiveResponse
{"provider": "openai", "models": [{"id": "gpt-4o", "label": "GPT-4o"}], "count": 12}
// UpdatesCheckResponse
{"webui": {"name": "hermes-webui", "behind": 3, "current_sha": "a", "latest_sha": "b", "branch": "main", "repo_url": "https://github.com/nesquena/hermes-webui", "compare_url": "…", "error": null, "stale_check": false}, "agent": null, "checked_at": 1723700000.0, "disabled": false}
// UpdatesApplyResponse
{"ok": true, "message": "重启中", "target": "webui", "conflict": false, "diverged": false, "restart_blocked": false, "restart_scheduled": true, "stash_conflict": false, "active_streams": 0, "active_runs": 0}
// ReasoningStatusResponse
{"ok": true, "show_reasoning": true, "reasoning_effort": "medium", "effort": "medium", "supported_efforts": ["low", "medium", "high"], "supports_reasoning_effort": true, "error": null}
// PersonalitiesResponse
{"personalities": [{"name": "default", "description": "…"}]}
// PersonalitySetResponse
{"ok": true, "personality": "default", "prompt": "…", "error": null}
// ProfilesResponse
{"profiles": [{"name": "work", "path": "…", "is_default": false, "is_active": true, "gateway_running": true, "model": "gpt-4o", "provider": "openai", "has_env": false, "skill_count": 5}], "active": "work", "single_profile_mode": false}
// ProfileCreateResponse
{"ok": true, "profile": {"name": "work"}, "error": null}
// ProfileSwitchResponse
{"profiles": [], "active": "work", "default_model": "gpt-4o", "default_workspace": "default", "error": null}
// SettingsResponse
{"bot_name": "Hermes", "webui_version": "1.2.3", "agent_version": "0.9.0", "theme": "dark", "check_for_updates": true, "show_cli_sessions": false, "show_claude_code_sessions": true, "max_tokens": 8192, "max_tokens_effective": 4096, "auth_enabled": true, "password_auth_enabled": true, "passkeys_enabled": false, "passwordless_enabled": false}
// ModelsResponse
{"groups": [{"provider_id": "openai", "name": "OpenAI", "models": [{"id": "gpt-4o", "name": "GPT-4o", "provider_id": "openai"}], "extra_models": []}], "models": [], "default_model": "gpt-4o", "active_provider": "openai"}
```

### A.5 其余小模型

```json
// HealthResponse
{"status": "ok", "sessions": 3, "active_streams": 1, "uptime_seconds": 86400.0}
// AuthStatusResponse
{"auth_enabled": true, "logged_in": true, "password_auth_enabled": true, "passkeys_enabled": false, "passwordless_enabled": false}
// LoginResponse
{"ok": true, "message": "登录成功", "error": null}
// WorkspacesResponse
{"workspaces": [{"path": "/home/u/proj", "name": "proj"}], "last": "/home/u/proj"}
// WorkspaceSuggestionsResponse
{"suggestions": ["/home/u/proj", "/home/u/other"], "prefix": "/home/u"}
// WorkspaceMutationResponse
{"ok": true, "workspaces": [{"path": "/home/u/proj"}], "error": null}
// DirectoryListResponse
{"entries": [{"name": "src", "path": "/home/u/proj/src", "type": "dir", "size": null, "modified": 1723700000.0, "is_directory": true}], "path": "/home/u/proj", "workspace": "proj", "error": null}
// FileResponse
{"content": "void main() {}", "path": "/home/u/proj/lib/main.dart", "name": "main.dart", "language": "dart", "size": 1024, "lines": 42, "error": null}
// SkillsResponse
{"skills": [{"name": "hermes-agent", "category": "autonomous-ai-agents", "description": "…", "path": "/skills/hermes-agent", "disabled": false, "tags": ["hermes"], "related_skills": ["codex"]}]}
// ToggleSkillResponse
{"ok": true, "name": "hermes-agent", "enabled": true}
// SkillLinkedFileResponse
{"content": "…", "path": "references/api.md"}
// MemoryWriteResponse
{"ok": true, "section": "memory", "path": "/home/u/.hermes/memory.md", "error": null}
// ModelsResponse（见 A.4 末行）
// PendingAttachment 本地模型（无 JSON，toJsonValue 输出）
{"name": "a.png", "path": "/tmp/a.png", "mime": "image/png", "size": 204800, "is_image": true}
// ApprovalPendingResponse
{"pending": {"approval_id": "ap_7", "command": "bash", "description": "…"}, "pending_count": 1}
// ClarificationPendingResponse
{"pending": {"clarify_id": "cl_3", "question": "…"}, "pending_count": 1}
// ClarificationRespondResponse
{"ok": true, "response": "方案A", "stale": false, "stale_cleared": false, "relayed": false}
// SessionYoloResponse
{"ok": true, "yolo_enabled": true}
// KanbanBoardsResponse
{"boards": [{"slug": "dev", "name": "开发", "description": "…", "icon": "🛠️", "color": "#4f46e5", "is_current": true, "total": 42, "counts": {"todo": 10, "running": 3}, "read_only": false}], "current": "dev", "read_only": false}
// KanbanBoardMutationEnvelope
{"board": {"slug": "dev"}, "current": "dev", "read_only": false}
// KanbanBulkActionEnvelope
{"results": [{"id": "card_1", "ok": true, "error": null}], "read_only": false}
// KanbanDependencyMutationEnvelope
{"ok": true, "changed": true, "parentId": "card_0", "childId": "card_1", "read_only": false}
// KanbanDispatchResult
{"spawned": 2, "promoted": 1, "reclaimed": 0, "skipped_unassigned": 0, "skipped_nonspawnable": 0, "auto_blocked": 0, "timed_out": 0, "crashed": 0}
// KanbanStats
{"total": 42, "by_status": {"todo": 10}, "by_assignee": {"alice": 3}}
// KanbanAssigneeHistory
{"assignees": ["alice", "bob"]}
// KanbanWorkerLog
{"taskId": "card_1", "exists": true, "size_bytes": 1024, "content": "…", "truncated": false}
// KanbanAddCommentResponse
{"ok": true, "commentId": "c2", "read_only": false}
```


