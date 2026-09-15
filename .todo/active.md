# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#103 @77211b2、#104 @caaafa1、#105 @5ea4b14、#106 @d99d120、#107 @92e7449、#108 @d8b9973、#109 @a922086 已收口誊写至 `.todo/20260914.md`，其中 #103/#105/#106/#107/#108/#109 待主人真机/实机复验；#110 099131e、#111 b9b7ae0 已收口誊写至 `.todo/20260914.md`（#110/#111 待主人真机复验）；#76 二期 @8b4fab1 已收口誊写至 `.todo/20260914.md`（打包瘦身，安装包产物已本机取证）；#87/#88 已收口誊写至 `.todo/20260907.md` @f01c91d；#91 @0076554；#93 @0a69ee2；#95 @da21ea2；#96/#97 APK 安装权限与分享按钮已收口誊写至 20260907.md，随补丁批次 commit；#98 @5c19de7 与 #99 交付 @b9df051（含诊断原档）已收口誊写至 `.todo/20260908.md`；#116 @v0.1.47、#117 @本轮提交 已收口誊写至 `.todo/20260914.md`；#114 P0（展开态真应用图标/倒计时方向/small icon 剪影）@49062b4 已收口誊写至 `.todo/20260914.md`（待主人真机复验）；#121 @a299b60（live 回合中途恢复正文重复塞段）已收口誊写至 `.todo/20260915.md`（待主人真机复验）；#112 @d3b1c58（死锚 re-anchor + 指纹去重）、#113 @5ecb39a（WorkManager 状态行三态）、#114 P1 @846d010（ProgressStyle 动态 tracker icon + 落点）已收口誊写至 `.todo/20260915.md`（待主人真机复验）；#122 @8d640f1（更新检查读真实版本 + 硬编码漂移护栏，随 v0.1.50 发布）已收口誊写至 `.todo/20260915.md`（待主人真机复验）；#123 @42d6d71（下载进度上岛 determinate 真进度 + 岛上工具名转译）、#124 @fb2484f（澄清弹窗消失重现 + 通知重复 + 等待态下岛）已收口誊写至 `.todo/20260915.md`（待主人真机复验））

## #125 长会话上滚分页：一次操作触发多次加载 + 加载后破坏滚动位置

**分类**：问题（bug）　**状态**：代码已交付（待主人真机复验）　**发现**：2026-09-15（主人报告）

### 位置（源码行号）
- 触发判据 + 滞回武装：`lib/features/chat/widgets/chat_message_list.dart` 的 `_onScroll`
- 加载入口 + 零推进封顶：同文件 `_loadOlderMessages`
- 位置恢复链 + 粗定位引子：同文件 `_restoreOlderScrollPosition`
- 收敛预算常量：同文件 `_maxOlderRestoreAttempts` / `_olderLoadRearmThreshold` / `_olderLoadStalledLimit`
- 分页状态写入（到底判定）：`lib/features/chat/chat_controller.dart` 的 `loadMessages` 分页分支

### 复现（真机长会话）
1. 打开长会话（历史 > 2 页，建议 ≥150 条，含代码块/工具卡）。
2. 持续上滚触发第一次分页（视口 `pixels <= 80`）。
3. 继续上滚重复触发第 2、3、4 次分页。

### 根因（实测取证，非推断）

**根因一（主因，同时解释两个现象）：前插一页把锚点推出 lazy 构建范围 → 收敛链空转、从不 jumpTo**
分页触发时捕获「视口顶缘条目 + 其视口 dy」作几何锚点（PATCH#93）。但前插一页可达数千像素，锚点条目被推到 lazy `ListView` 的构建范围（视口 ± cacheExtent）之外，而构建范围只随 `pixels` 移动 —— 纯「等帧」永远不会把它建出来。`_topEdgeAnchorDy` 恒为 null，收敛链既不归位、也不报错，一路空转到预算耗尽，`pixels` 停在原位（顶部带内）。
实测（widget test，50 条/页 ≈ 5300px）：`pixels` 停在 **79.5 / -2.6**，`attempts` 撞满预算 6，链一次 `jumpTo` 都没执行。由此同时产生主人的两个现象：
- 「加载后 y 轴被推走」＝ 视口停在历史头部，而内容已被前插；
- 「容易触发多次加载」＝ 视口仍在 `pixels <= 80` 带内，用户任何轻微上滚立刻再命中触发条件 → 连环加载。

**根因二：收敛帧预算计数器跨分页单调累加**
`_olderRestoreAttempts` 只在 session 切换（`didUpdateWidget`）归零，每次分页开始不重置；成功收敛与预算耗尽两条路径也都不重置。故它单调累加，撞满 `_maxOlderRestoreAttempts` 后每次分页首帧即判定「预算已尽」而放弃归位。
反向验证：仅禁掉这一行重置 → 测试立刻报「第 6 次分页实际已用 6 帧」。

**根因三：触发判据无滞回**
`pixels <= 80` 是纯固定像素阈值，只判位置、不判方向位移与冷却；唯一防线是请求返回即释放的在途锁 → 视口只要留在带内，后续滚动事件就会再打一发。
**叠加**：零新增分页（服务端该游标已无更早消息）不判定到底，`hasOlderMessages` 可长期为 true，被滚动事件反复触发同一页请求。

### 修复（`chat_message_list.dart` + `chat_controller.dart`）
| # | 改动 |
|---|------|
| 1 | 每次分页开始重置 `_olderRestoreAttempts = 0` 并清锚点残留（根因二） |
| 2 | 锚点不可见时，首帧用 extent 增量做**粗定位引子**把锚点带回构建范围，随后仍由锚点法逐帧精修 —— 估算只当引子、终值精度由锚点保证（根因一，区别于 PATCH#93 把估算当终值） |
| 3 | 顶部触发滞回：`pixels <= 80` 触发一次后解除武装，视口离开顶部带（`pixels > 200`）才重新武装（根因三） |
| 4 | 收敛预算 3 → 6 帧（长内容条目异步撑高需更多帧） |
| 5 | 分页返回 `fresh` 为空 → `hasOlderMessages = false`（服务端已无更早消息，判定到底） |
| 6 | 连续零推进（游标与条数都不变 = 无历史或请求失败）达 2 次封顶停手；单次零推进保持武装以便重试 |

### 回归测试（新增 `test/features/chat/chat_pagination_repeated_load_test.dart`）
`FakeChatApi` 新增 `sessionResultBuilder`（按 `messageBefore` 逐页回吐）与 `sessionMessageBefore` 记录；`ChatMessageListState` 暴露 `olderRestoreAttempts` / `olderLoadArmed` 白盒断言点。
- **RED-125-1** 连续 6 次分页：`attempts` 每次从 0 重启（修复后恒为 1，不再累加）、收敛链收工、每轮成功加载一页
- **RED-125-2** 分页后视口必须被补偿离开顶部带（`pixels > 200`）且只打一发请求
- **RED-125-3** 零新增分页 → `hasOlderMessages` 收敛为 false
- **RED-125-4** 零新增后反复滚动 → 分页请求次数有界（≤ 2）

**每个用例都做了反向验证**（逐条禁用对应修复 → 用例变红），确认护栏非空转，非「永远绿」的假测试。

### 验收
- [x] `flutter analyze` 零告警（含 info）
- [x] 新增 4 用例全绿
- [x] 反向验证：三条修复各自可被测试捕获
- [x] 全量 `flutter test` 无回归（2988 通过；唯一失败为 version 兜底常量漂移，已顺手修，见 #126）
- [ ] 主人真机复验：长会话连续上滚 5 次，位置不跳、无重复请求

### 遗留观察
- 测试中「连续第 7 轮上滚」未再触发加载（`pixels`/`maxScrollExtent` 完全不变），疑为 widget test 连续手势连发所致，非产品逻辑；测试已收敛到 6 轮。真机复验时留意是否存在真实的「加载到某一页后不再触发」。

## #126 回到前台清通知静默失效（clearAll 未初始化插件）+ 版本兜底常量漂移

**分类**：问题（bug）　**状态**：代码已交付（待主人真机复验）　**发现**：2026-09-15（主人贴日志报告）

### 位置
- `lib/features/notifications/turn_notification_service.dart` 的 `clearAll()`
- 触发路径：`lib/features/notifications/notification_lifecycle_observer.dart` 的 `resumed` 分支（App 回到前台自动清通知）
- 参照实现：同文件 `clearDownloadProgress()` / `requestPermission()` 都先 `await _ensureInitialized();`

### 根因
`clearAll()` 是全类唯一漏调 `_ensureInitialized()` 的方法（该守卫幂等：`if (_initialized) return;`）。App 冷启动/回到前台时插件尚未初始化，`_plugin.cancelAll()` 抛
`Bad state: Flutter Local Notifications must be initialized before use`；异常被下方 `catch` 吞掉（只留一条 error 日志），清除通知**静默失效**，旧通知残留在通知栏。
主人贴出的日志正是这条路：`[ERROR] [notifications] 清除通知失败 [error: Bad state: ... must be initialized before use]`。

### 修复
`clearAll()` 开头补 `await _ensureInitialized();`（与同类方法对齐）。

### 验收
- [x] 新增回归用例「未初始化时先初始化插件再取消」（`turn_notification_service_test.dart` 的 `clearAll` group）
- [x] 反向验证：禁掉该行 → 用例变红（护栏非空转）
- [x] `turn_notification_service_test.dart` 全绿（31 例）
- [ ] 主人真机复验：回到前台后通知栏不再残留旧通知，诊断日志不再出现「清除通知失败」

### 同批顺手修（本轮全量测试暴露的 pre-existing 失败）
`lib/core/update/version_info.dart` 的兜底常量 `appVersion` 停在 `'0.1.50'`，而 `pubspec.yaml` 已是 `0.1.51+57` → `version_info_test` 的「兜底常量与 pubspec 一致」护栏（#122 引入）失败。已改为 `'0.1.51'`。这是 v0.1.51 发布时的同步疏漏，与 #125/#126 无因果关系。

## #127 澄清作答后聊天不再更新（等待态结束未接回推送通道）+ 静默兜底巡检 guard

**分类**：问题（bug）+ 系统性加固　**状态**：代码已交付（待主人真机复验）　**发现**：2026-09-15（主人贴日志并报告现象）

### 现象
选择完澄清回复后，聊天界面不再更新（agent 后续输出到不了界面）。主人最初怀疑与 `清除通知失败` 日志同源。

### 取证（先排除误判）
`清除通知失败` 那条异常**不可能**导致聊天停止更新：调用点是 `unawaited(...clearAll())`（notification_lifecycle_observer），且 `clearAll` 内部把异常整个 catch 掉（只留日志）——异常传不出去也不阻塞生命周期回调。故另立本条目，通知问题见 #126。

### 根因（源码级证据链）
1. `chat_controller.dart` 的 `_handleAppLifecycleChange` resumed 分支（约 1714-1718）：`isStreamingActive` 要求 `!state.pendingAction.hasPendingPrompt` —— **澄清等待态下主动探活/重连被门控挡掉**（该排除来自早期 `6ad6f09`，长期潜伏）。
2. 等待期间 App 通常在后台（用户从系统通知点回），两条 SSE（回合流 + `/api/session/stream` 会话内容通道）会**静默断线**（无 `onTransportError`/`onClosed`，只能靠时间差识别）。
3. `respondToClarification` / `respondToApproval` 作答成功后只 `_clearXxxCard()`，**清卡路径不重建任何通道**；而 `_checkStatusAndReconnect` 入口是 `activeStreamId == null` 即 return，会话内容通道也只在 sessionId 变化时重建。
→ 通道断了没人接回来 ⇒ 服务端继续输出而界面静止。

### 修复
1. **等待态结束接回通道**：新增 `_resumeChannelsAfterPromptResolved()`（作答成功 + 澄清超时调用）——重建会话内容通道（内部 stop-then-start，幂等；服务端开新回合由它的 `onServerTurnStarted` 接管）。
   **注（设计收敛）**：初版还在此立刻 `_checkStatusAndReconnect()`，全量回归打红 `chat_controller_test` 的「作答后回 streaming」（`Expected streaming, Actual idle`）——作答刚提交时服务端尚未开新回合，探活拿到 `active=false`，既有分支把 phase 误落 idle。故撤掉立刻探活，断线最终交给兜底巡检（15s 内）。
2. **静默兜底巡检 guard（主人要求）**：`_runStallGuardIfNeeded()` 挂进既有 1s watchdog。**不依赖任何单一事件**——满足「存在未决期待」且长时间（15s）无任何服务端进展、无活跃流时，主动 `syncMissingMessages()` 拉会话把内容兜回来（该调用顺带能接管服务端新开的流）。
   四重门控保证低频不打扰：仅前台 + 仅无活跃流（有流交给 transport-stale 链，避免双路争抢）+ **仅 `_awaitingServerContent`（发送/作答后尚未收到任何进展）** + 动作后 90s 激活窗口内（空闲会话永不触发）+ 20s 冷却。静止基线取「最近进展与动作时刻的较晚者」，避免刚动作即误判。
   **注（设计收敛）**：初版只有时间判据，全量回归打红 `chat_context_window_poll_test` 的「无残留请求」（`Expected 2, Actual 3`）——回合正常收尾后仍会多拉一次；故引入 `_awaitingServerContent`（`_markUserAction` 置 true / `_markProgress` 置 false）。

### 验收
- [x] `flutter analyze` 零告警
- [x] 用例 13「作答后主动探活」——反向验证：禁掉该调用即变红
- [x] 用例 14「动作后长时间无进展 → 兜底拉取」——反向验证：禁掉巡检即变红
- [x] 用例 15「门控：阈值内不抢跑拉取」
- [x] `clarify_lifecycle_test.dart` 15 例全绿
- [ ] 主人真机复验：从系统通知点回 → 选澄清 → agent 续跑应正常逐字更新；若仍出现静止，诊断日志应出现 `chat_stall_guard` 兜底记录
