# hermes-ui 本地缓存机制盘点报告 + 媒体缓存复用设计方案

- 日期：2026-08-21
- 范围：只读排查 + 文档级设计，**未修改任何 `lib/` 代码**
- 技术栈背景：drift(SQLite) 离线缓存 / flutter_secure_storage 安全存储 / dio 网络 / flutter_riverpod 状态；
  后端 hermes-webui 跑在 `:30002`，认证走 session cookie（`/api/media` 启用 auth 时强制 cookie 校验）

---

## 0. 结论速览（TL;DR）

| # | 问题 | 现状结论 |
|---|---|---|
| 1 | 会话列表有本地缓存吗？重启后能复用吗？ | **有代码、无实效**：`CacheService.writeSessions/readSessions` 已接线（成功写、网络失败读兜底），但 `appDatabaseProvider` 默认是 **`AppDatabase.memory()` 内存库**，`main.dart` 从未 override 成 `AppDatabase.production()` → 缓存只活在当前进程，**重启即清空，无法复用** |
| 2 | 会话内容（消息）缓存吗？重进历史会话走网络吗？ | 消息缓存已接线（loadMessages 成功写、done/stream_end 再写、加载失败读缓存兜底），但同样落在内存库 → 进程内可离线看，**重启丢**；**重进历史会话默认永远走 `GET /api/session` 网络**（有缓存也不先读，只有请求失败才回退缓存） |
| 3 | 图片/附件加载后落本地缓存吗？反复查看重复下载吗？ | 图片用 `Image.network` 直接拉取，**无磁盘缓存**。同一进程内反复查看同一 URL 靠 Flutter 内存 ImageCache（LRU，默认 ~1000 张/100MB）**不重复下载**；**重启/杀进程后全部重新下载**。附件（非图片）只有芯片 UI，无下载、无缓存 |
| 3b |（衍生高危发现）| `Image.network` **不走 dio 拦截器、不带 cookie**；后端 `/api/media` 在启用 auth 时强制 cookie 校验（401）→ 图片大概率**加载失败**，需验证（见 §2.4） |
| 4 | cache_service / drift 表结构覆盖了什么？ | 2 张表：`cached_sessions`（sessionId/title/payload/cachedAt）、`cached_messages`（messageId/sessionId/payload/cachedAt），schemaVersion=1；**无媒体表、无 serverURL 隔离列、无容量/LRU 字段**（详见 §2.1） |
| 5 | 媒体本地缓存设计方案 | 见 §3：**文件系统介质 + URL 哈希 key + LRU 容量上限 + TTL，经 ApiClient（dio 拦截器带 cookie）下载**，渲染改用 Image.file |

> ⚠️ 一句话根因：**缓存基建（drift 文件库）已写好但从未启用**——`persistentAppDatabaseProvider`（`AppDatabase.production()`）是存在的，只是没有任何宿主 override。第 3 问媒体缓存则是**完全空白**。

---

## 1. 现状盘点：接线全貌

```
main.dart（runApp ProviderScope）
  └─ overrides: 只有 turnNotificationHook —— ❌ 无 appDatabaseProvider 覆盖
        ↓
appDatabaseProvider（lib/core/cache/cache_providers.dart:8）
  └─ AppDatabase.memory()  ← ⚠️ 生产跑内存库（重启丢）
  └─ persistentAppDatabaseProvider（:17, AppDatabase.production()）← 存在但无人使用
        ↓
cacheServiceProvider（:24）→ CacheService(database)
        ↓
用法（仅两处，均已接线）：
  ① session_list_providers.dart:358  writeSessions（网络成功后）
     session_list_providers.dart:379  readSessions（网络失败兜底）
  ② chat_controller.dart:514/1353/1591 _writeCacheMessages（loadMessages 成功 / done / stream_end）
     chat_controller.dart:531         readMessages（loadMessages 失败兜底）
```

其余缓存相关 Provider：

- `offlineCacheEnabledProvider`（cache_providers.dart:28，默认 `true`）：**全局搜索没有任何 read 消费点**——开关形同虚设。
- `CachedSessionData`（:30）：同样无消费点。

---

## 2. 现状盘点：分项细节

### 2.1 drift 表结构（`lib/core/cache/app_database.dart`，schemaVersion = 1）

| 表 | 列 | 主键 | 说明 |
|---|---|---|---|
| `CachedSessions` | `sessionId` text / `title` text / `payload` text(JSON) / `cachedAt` int | `sessionId` | payload 存整个 `SessionSummary.toJson` 快照 |
| `CachedMessages` | `messageId` text / `sessionId` text / `payload` text(JSON) / `cachedAt` int | `messageId` | 注释明确「纯文本 payload，避免把富媒体写入离线库」——二进制不进库是**既定设计** |

要点：

- 无任何索引（除主键）、无外键、无 serverURL 维度。Swift 蓝本（`.reference/hermex-src/Persistence/CacheStore.swift`）按 `serverURLString + sessionID` 双键隔离多服务器缓存，**Dart 端没有** → 切换服务器后缓存会串（A 服务器的会话/消息可能被 B 服务器当成离线兜底读走）。
- `CachedMessages.messageId` 是全局主键：不同会话若出现相同 messageId 会互相覆盖（后端 messageId 通常全局唯一，风险低，但会话删除后缓存行不会联动清理）。
- 生产文件库：`AppDatabase.production()` → `driftDatabase(name: 'hermes_cache')`（drift_flutter，Windows 走 sqlite3，路径由 drift_flutter 管理）。测试库 `AppDatabase.memory()` 用 `NativeDatabase.memory()`。
- 容量/时间策略现状：`CacheService`（cache_service.dart）内 `maxSessions = 50`、`ttl = 7 天`（仅 `readSessions` 过滤用过期的，删除动作只在下次 `writeSessions` 全量重写时隐式发生）；消息侧写入取最近 **50 条**、读取 `limit(50)`、**无 TTL**。
  - 对照蓝本：`CachePolicy.ttl = 7*24*3600`、`maxMessages = 5000`、过期主动清理 + 超量 LRU 淘汰（`evictOldestMessagesIfNeeded`）——Dart 端只有「截断无淘汰」。
- 会话缓存写入是**全量覆盖**：`writeSessions` 先 `delete` 全表再插入 top-50（session_list_providers 每次 fetchSessions 成功都触发 → 每次启动首次拉全会重写一次）。

### 2.2 会话列表缓存行为（问答 1）

- 写：`SessionListController._loadFirstPage` 网络成功后 `writeSessions(sessions)`（try/catch 包裹，缓存失败不阻塞在线列表）。
- 读：仅当 `ApiException.shouldUseCache(error)`（NetworkException 的 cannotFindHost/cannotConnect/offline/timedOut，或 HTTP 408/502/503/504；401/业务错**不**落缓存路径）→ `readSessions()`（7 天 TTL 过滤）→ 命中则展示 + `actionError: '离线缓存：当前显示最近缓存的会话'`。
- 是否会「先读缓存、后刷网络」的 stale-while-revalidate？**否**：在线时永远只走网络，缓存纯粹是离线/故障兜底。
- 重启后能复用吗？**不能**（内存库，§2.1）。把 `appDatabaseProvider` override 到 `persistentAppDatabaseProvider` 后即可跨重启复用——这是所有缓存复活的最小改动点。

### 2.3 会话消息缓存行为（问答 2）

- 写触点（chat_controller.dart）：
  - `loadMessages()` 首屏加载成功 → `_writeCacheMessages(sessionId, loaded)`（:514，`unawaited` 旁路写）
  - SSE `done` 事件收尾 → 写 `state.messages`（:1353）
  - SSE `stream_end` 收尾 → 写（:1591）
  - `_writeCacheMessages` 取最近 50 条 → `_messageToCacheJson`（`message.toJson()` + 补 `id`/`message_id`）→ `upsert`（insertOnConflictUpdate by messageId）
- 读回退：`loadMessages` 抛 ApiException 且 `messageBefore == null`（**仅首页加载**，翻页加载更早消息不回退缓存）且 `shouldUseCache` → `readMessages(sessionId)` → `ChatMessage.fromJson` → 排序（消息含 timestamp 按 timestamp 升序；否则把 cachedAt 倒序结果整体 reverse）→ `isViewingCachedData: true` + `isShowingOfflineCache: true`（chat_page 显示离线横幅，`canSendProvider` 禁发——需要先重连）。
- 重进历史会话是否走网络？**走**：每次 `loadMessages` 都 `GET /api/session?messages=1&message_limit=…`（ChatApiClient.session），缓存不参与主线；仅网络失败才读缓存。不存在「离线也能正常浏览聊天记录」的体验（离线时只有最近看过的 ≤50 条可用，且仅限进程生存期）。
- 跨进程复用（重启后离线浏览）需要：①生产文件库接线；②可选：进入会话页时先读缓存渲染再网络刷新。

### 2.4 图片/附件加载链路（问答 3）

链路：`MEDIA:<ref>` / 裸 `file://` → `ChatMediaParser` 转 Markdown → flutter_markdown `imageBuilder` → `ChatInlineMediaWidget`（chat_media_view.dart）→ `ChatMediaResolver.resolveMediaUrl`：

- `data:image/*` → `Image.memory(base64)`（消息自带，无网络）
- `http(s)://` 完整 URL 或拼出的 `{baseUrl}/api/media?path=…&session_id=…` → **`Image.network(resolvedUrl, headers: customHeaders)`**
- 本地 `file://` 存在 → `Image.file`

缓存行为：

1. **无磁盘缓存**。`Image.network` 只进 Flutter 全局 `ImageCache`（进程内存，默认最大 1000 张 / 100MB / LRU）→ 同进程内重复查看同一 URL 命中内存不重复下载；**重启后重新下载**。
2. Lightbox（点击放大）用同一 resolvedUrl + headers 再 `Image.network` → ImageProvider key 相同 → 内存命中，不会二次下载（进程内）。
3. 附件芯片（`ChatAttachmentChipView`）只渲染图标 + 文件名，**无打开/下载动作**；用户消息的图片附件（path 为上传后的相对路径）同样走 `ChatInlineMediaWidget`。

**⚠️ 高危发现（需验证）——`Image.network` 不带 session cookie，`/api/media` 大概率 401：**

- `customHeaders` 来自 `ServerConnection.customHeaders`（用户配置的反向代理头，如 `Authorization: Bearer …`，connection_providers.dart:141 + message_bubble.dart:62），**cookie 从不进 customHeaders**——cookie 只存在于 `CookieStore`，由 dio 拦截器注入（api_client.dart:380），`Image.network` 用的是 Flutter 自带 HttpClient，**不经 dio 拦截器**。
- 后端 `api/routes.py` `_handle_media`（:18702）：`if is_auth_enabled(): parse_cookie + verify_session`，否则 **401**。主人 fork `:30002` 启用登录（skill 记录「密码被拒绝」场景），因此图片加载大概率失败，除非：①服务器未开 auth；②customHeaders 恰好带了后端认可的认证头。
- 验证方法：登录后抓 cookie，`curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:30002/api/media?path=<encoded>&session_id=<sid>" -H "Cookie: <hermes-session=...>"`。
- 这与媒体缓存设计直接相关：**媒体下载必须改走 ApiClient（dio），才能继承 cookie/自定义头/401 自动重登**（见 §3.6）。

### 2.5 测试现状

- `test/core/cache/cache_service_test.dart`：service 层单测（round-trip / 50 条截断 / 7 天 TTL / 全量覆盖 / upsert / 排序契约），全走 `AppDatabase.memory()`——**掩盖了「生产内存库」问题**（测试环境 path_provider 不可用，注释也说明缓存故障不阻塞）。
- `test/features/chat/chat_offline_cache_test.dart`：写缓存触点（首屏成功 / done 事件）、读缓存回退（网络错误 → 缓存展示 + isViewingCachedData）。
- `test/helpers/` 无 fake database 文件（有 `in_memory_secure_storage.dart` 与各 fake API；golden 测试用 `connectionStoreProvider.overrideWithValue` + InMemorySecureStorage）。
- 无任何媒体加载/缓存测试。

---

## 3. 设计方案：「图片/附件本地缓存」

### 3.1 目标与非目标

目标：

- 图片（`/api/media` 与任意 http(s) 图片）**首次加载后落磁盘**，重启/重进会话零重复下载；
- 离线时可回看已缓存图片（占位符兜底，不重复 401）；
- 下载/缓存全链路复用现有认证（cookie + 自定义头 + 401 自动重登）。

非目标（本期不做）：视频/音频流式缓存、附件（非图片）批量下载、跨设备同步、服务端缓存协商（ETag/Last-Modified）。

### 3.2 缓存介质：文件系统（推荐）vs SQLite blob

| 维度 | 文件系统（`getApplicationSupportDirectory()/hermes_media/`） | SQLite blob（新表存 bytes） |
|---|---|---|
| 读放大 | 低：`Image.file` 直接解码，零拷贝 | 高：每次读 blob 出库为临时内存，大图反复读 |
| 与现有 drift 关系 | 互不干扰；drift 只存索引元数据 | 与消息缓存共享一个库，事务一致性好 |
| 容量管理 | 便宜（stat 目录、删文件） | 需要额外 LRU SQL + blob 读写 |
| 大文件（数 MB 图/PDF） | 无压力 | SQLite 页缓存压力大，拖慢 `readSessions/readMessages` |
| Web 平台 | 不可用（需降级内存/IndexedDB） | 可用（但 Web 的 drift 是 WASM sqlite） |

**结论：二进制 → 文件系统；drift 加一张 `cached_media` 元数据索引表**（文件路径、URL、mime、大小、访问时间）。这与现有 `CachedMessages`「纯文本 payload、富媒体不进库」注释的既定方向一致。

### 3.3 数据流（新增 MediaCacheService，不动现有 ApiClient 语义）

```
ChatInlineMediaWidget（渲染）
  │  resolvedUrl（含 baseUrl/session_id）
  ▼
MediaCacheService.get(resolvedUrl)          ← ConsumerWidget，AsyncValue<Uint8List/File>
  │  1) 查 cached_media 表 / 直接 stat 文件 → 命中 → 更新 last_accessed_at → 返回 File
  │  2) 未命中 → client.downloadData(Uri.parse(resolvedUrl))   ← 🔑 走 dio：同域带 cookie + 自定义头
  │                                                              + 401 autoReauth（已有机制，重登后自动重放）
  │  3) 2xx → 写文件（sha256 命名）+ upsert cached_media → 返回 File
  │     非 2xx（401/404）→ 不缓存，抛错走现有 _ImageErrorPlaceholder
  ▼
Image.file / Image.memory 渲染（替换现在的 Image.network）
```

- 渲染替换点：`chat_media_view.dart` 两个 `Image.network`（内联 + lightbox）→ 改为消费 MediaCacheService 结果的 `Image.file`。`data:image/*` 与 `file://` 分支不动。
- flutter_markdown `imageBuilder` 返回同步 Widget 的限制：`ChatInlineMediaWidget` 内部自持 `ConsumerWidget`/StatefulWidget 做异步取数即可，对外签名不变。
- 下载可以不做并发去重（同一 URL 并发）：简单起见首次实现用 per-URL 内存 `Future` 合并（Completer map），避免列表滚动时同图重复请求。

### 3.4 key 策略

- **主 key：`sha256(fullResolvedUrl)`**（hex 字符串）。
  - URL 已包含 `path` + `session_id` query 参数 → 天然区分「同一文件、不同会话授权」的取回；跨会话复用依赖 URL 一致（同 path 同 session 则同 key，合理）。
  - 相比「sessionId + messageId」：URL 更通用（同一图片可能被多个会话/多条消息引用，一条消息可能含多图）；messageId 只存在于历史消息，而流式期间 MEDIA: 已可渲染。
- 文件名：两种形态，ext 从 URL path 尾部或响应 Content-Type 推断（无则 `.bin`）：
  - **首次落盘/兜底**：`<sha256hex>.<ext>`；
  - **强制刷新落盘**（`MediaCacheService.refresh`，媒体预览的「刷新」按钮）：`<sha256hex>-<version>.<ext>`。
    ⚠️ 刷新**必须换名**，不能同名覆盖——`Image.file` 的 provider key 是 `FileImage(path, scale)`，
    **不含 mtime/size**（Flutter 3.47 `painting/image_provider.dart`），同名写回时 `Image` 不会
    重新 resolve，用户点刷新会「毫无反应」（`imageCache.evict` 也救不回已在监听的 ImageStream）。
    换名后索引 `filePath` 同步指向新文件、旧文件即刻删除；`_keyFromFileName` 因此按首个 `-` 之前取 key。
    `_get` 命中时也**必须按索引 filePath** 取文件（按固定名回算会让刷新后的每次访问都判未命中而重下）。
- drift 索引表结构（schemaVersion 1 → 2）：

```dart
/// 媒体缓存元数据索引（二进制在文件系统）。
class CachedMedia extends Table {
  TextColumn get cacheKey => text()();            // sha256(fullUrl), PK
  TextColumn get url => text()();                 // 完整 URL（含 session_id）
  TextColumn get mimeType => text().nullable()();
  TextColumn get filePath => text()();            // 相对文件名（便于整体迁移）
  IntColumn get byteSize => integer()();
  IntColumn get cachedAt => integer()();
  IntColumn get lastAccessedAt => integer()();
  TextColumn get sessionId => text().nullable()(); // 业务维度（会话删除联动清理用）
  @override
  Set<Column<Object>> get primaryKey => {cacheKey};
}
```

### 3.5 失效策略

1. **容量上限（LRU）**：默认 `maxMediaCacheBytes = 200MB`（可配置）。写入成功后异步统计目录总字节（`Directory.list` stat 即可，图片缓存不频繁），超限按 `lastAccessedAt` 升序删文件 + 删索引，直至达标。低频清理也可以在 App 启动 + 每次写入后触发，避免定时器常驻。
2. **时间 TTL**：`mediaTtl = 30 天`（图片 > 会话 7 天合理：图片是内容资产而非状态）。读命中时若 `lastAccessedAt` 超过 TTL → 视为过期删除重下。
3. **孤儿清理**：启动扫描两遍——磁盘有文件但无索引（直接删）、索引有记录但文件丢失（删索引）。
4. **随会话删除联动（可选）**：`deleteSession` 成功后按 `session_id` 清媒体（保守做法：仅清理明确属于该会话的、且文件名不含其他引用依据的条目；简单期可只做 TTL/LRU，不做联动）。
5. 网络错误/401/404 **不写缓存**（只缓存 2xx 成功体），占位符行为与现状一致。

### 3.6 与 ApiClient 认证集成（关键点）

- **复用现有 `ApiClient.downloadData(Uri)`**（api_client.dart:264）：同域 → 主 dio（拦截器注入 cookie + 自定义头，见 :368-395）；跨域 → `_publicMediaDio` 裸客户端（防自定义头泄密，语义与现在一致）；401 → `_fetchWithAutoReauth` 触发保存密码重登后自动重放（connection_providers.dart:144 已注册 autoReauth）。**媒体下载零新增认证代码**。
- 不要给 `Image.network` 手拼 `Cookie: …` header（cookie 会过期、换服务器会串、且与 CookieStore 逻辑重复）——统一走 dio 才是与现有认证体系集成的方式。
- 可选增强：`downloadData` 后把响应 `Content-Type` 透出（现在只返回 `Uint8List`），供 mimeType/扩展名推断；如不想动 ApiClient 签名，可以从 path 后缀推断，够用。
- 401 现状修复后，现有 `customHeaders` 传入 `Image.network` 的路径可整体退役（headers 参数由 dio 层统一处理），`ChatInlineMediaWidget.customHeaders` 参数保留兼容测试即可。

### 3.7 Provider 与开关

```dart
final mediaCacheServiceProvider = Provider<MediaCacheService>((ref) {
  final db = ref.watch(appDatabaseProvider);        // 与现有缓存同库（接线后即文件库）
  final client = ref.watch(apiClientProvider);       // 跟随激活连接重建
  return MediaCacheService(db: db, client: client, rootDir: ...);
});
```

- 真正启用持久化的前提（最小改动，独立于媒体缓存）：`main.dart` 的 ProviderScope overrides 加 `appDatabaseProvider.overrideWith((ref) => ref.watch(persistentAppDatabaseProvider))`——这一步同时复活会话/消息缓存的重启复用。
- 可为媒体缓存提供 `mediaCacheEnabledProvider` 开关（参考现有 `offlineCacheEnabledProvider` 语义，把它一并接线）。

### 3.8 平台差异与测试计划

- Web：文件系统不可用 → `kIsWeb` 分支降级为内存 Map 缓存（进程内）或 IndexedDB（后续再做），UI 行为一致。
- Windows/Android：`path_provider.getApplicationSupportDirectory()`（drift_flutter 已有传递依赖，建议显式声明 path_provider）。
- 测试：
  1. `MediaCacheService` 单测：命中/未命中/并发合并/写失败容错/LRU 淘汰/TTL 过期——用 `AppDatabase.memory()` + 临时目录（`Directory.systemTemp`）+ fake ApiClient（或 Dio 假 adapter 回放 bytes）。
  2. 控制器回归：网络 401 → 不落缓存；200 → 落盘；缓存命中 → 不发网络请求（计数器断言）。
  3. 端到端契约（对齐现有 `tools/fake_gateway` 风格）：fake server 回放带 `Set-Cookie` 的登录 + `/api/media` 200，验证 dio 链路确实带上 cookie。
  4. golden：`ChatInlineMediaWidget` 已有注入连接的模式（InMemorySecureStorage + connectionStoreProvider override），媒体缓存用 fake MediaCacheService 注入即可保持黄金稳定。

### 3.9 分阶段落地路线

| 阶段 | 内容 | 验收 |
|---|---|---|
| P0（一行修复） | `main.dart` override `appDatabaseProvider → persistentAppDatabaseProvider` | 重启 App 后会话列表离线兜底仍然可用；`hermes_cache.sqlite` 出现在应用数据目录 |
| P1 | MediaCacheService + `cached_media` 表（schemaVersion=2）+ LRU/TTL | 单测全绿；同图二次渲染 0 网络请求 |
| P2 | `ChatInlineMediaWidget` 渲染切换（Image.network → 缓存文件） | 内联图 + Lightbox 走缓存路径；401 占位符行为不回归 |
| P3（可选） | 离线先显后刷：进入会话页先读缓存渲染再网络刷新（stale-while-revalidate）；会话删除联动清理 | 离线浏览历史会话体验完整 |

---

## 4. 附录

### 4.1 关键文件行号索引

| 文件 | 关键点 |
|---|---|
| `lib/core/cache/app_database.dart` | 两张表定义（:11-30）、schemaVersion=1（:45）、production/memory 工厂（:37-42） |
| `lib/core/cache/cache_providers.dart` | **内存库默认（:8-14）**、persistentAppDatabaseProvider（:17-21）、offlineCacheEnabledProvider（:28） |
| `lib/core/cache/cache_service.dart` | maxSessions=50 / ttl=7d（:13-14）、writeSessions 全量覆盖（:16-32）、readMessages 无 TTL（:66-75） |
| `lib/features/session_list/session_list_providers.dart` | 写缓存（:358）、读缓存兜底（:376-389） |
| `lib/features/chat/chat_controller.dart` | 读回退（:527-562）、写触点（:514/:1353/:1591）、_writeCacheMessages（:2196-2213） |
| `lib/features/chat/widgets/chat_media_view.dart` | Image.network 加载（:88-114）、Lightbox（:177-183）、附件芯片（:306-412） |
| `lib/features/chat/widgets/chat_media_parser.dart` | resolveMediaUrl 拼 /api/media（:141-200） |
| `lib/core/api/api_client.dart` | cookie/自定义头拦截器（:368-395）、downloadData（:264-287）、autoReauth（:123-144） |
| `lib/core/connections/connection_providers.dart` | customHeaders 来源（:141）、autoReauth 注册（:144-159） |
| `lib/core/api/api_exception.dart` | shouldUseCache 白名单（:17-35） |
| `.reference/hermex-src/Persistence/*` | 蓝本：按 serverURL+sessionID 隔离、TTL 7d、maxMessages 5000、LRU 淘汰 |
| `D:/hermes-webui/api/routes.py:18702` | **/api/media 启用 auth 时强制 cookie，否则 401** |

### 4.2 待验证清单（建议开工前用 curl/真机确认）

1. `curl -c cookies.txt -X POST http://127.0.0.1:30002/api/auth/login -d '{"password":"<pw>"}'` → `-b cookies.txt -o /dev/null -w "%{http_code}" "http://127.0.0.1:30002/api/media?path=<encoded>&session_id=<sid>"`：确认当前图片是否 401（验证 §2.4 高危发现）。
2. 确认 `getApplicationSupportDirectory()` 路径下 drift_flutter 实际落盘位置（`hermes_cache.sqlite`）在 Windows 上可写（P0 验收点）。
3. 确认 `/api/media` 对同 URL 的响应是否稳定（同 path 不同时间内容是否变化——决定缓存 key 是否够用；已知会话媒体由 session token 授权，内容不变）。