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

## #128 窄屏点击大标题 = 点击右侧快捷导航 ▾

**分类**：方向（交互一致性）　**状态**：代码已交付 @9a97db6（待主人真机复验）　**发现**：2026-09-15（主人截图报告）

### 现象（现状 vs 预期）
- **现状**：窄屏（width < 900）各页大标题右侧的 ▾（`NarrowNavigationDropdownButton`，44×44 热区）是唯一入口；点击标题文字「会话」等**无任何反应**，必须精准点到那个小三角。
- **预期**：点击大标题文字 = 点击它右侧的 ▾（打开同一个快捷导航下拉菜单，弹层锚点与位置不变）。滚动后收起态的中标题同样可点。

### 位置（源码行号）
| 角色 | 文件 | 关键行 |
|---|---|---|
| 会话列表页头部（基准） | `lib/features/session_list/session_list_header.dart` | 大标题 253-269、收起态中标题 235-251、▾ 271-276 |
| 其他功能页共用头部 | `lib/app/widgets/large_title_sliver_header.dart` | 大标题 300-329、收起态中标题 244-296、▾ 334-345、`_wrapTitle` 126-133 |
| 窄屏 ▾ 落地处 | `lib/app/widgets/adaptive_sliver_navigation_bar.dart` | 116-118（`const NarrowNavigationDropdownButton()`） |
| ▾ 组件（打开逻辑） | `lib/app/widgets/narrow_navigation_dropdown.dart` | `_openMenu` 45-106、build 108-127 |
| 会话页自建 ▾ | `lib/features/session_list/session_list_page.dart` | 302 |
| 双击回顶（唯一使用者） | `lib/features/settings/settings_page.dart` | 94（`onTitleDoubleTap: _scrollToTop`） |

覆盖页面：`AdaptiveSliverNavigationBar` 全部窄屏使用者 —— tasks / kanban / workspaces / workspace / skills / insights / memory / git / settings / session_list（共 10 处入口）。

### 实现要点
1. 新增「打开请求」通道：`NarrowNavigationDropdownButton` 增加可选 `Listenable openSignal`（页面/导航栏持有的 `ValueNotifier<int>`），监听后调用既有 `_openMenu`；不改弹层锚点（仍在 ▾）。
2. `AdaptiveSliverNavigationBar` 改 StatefulWidget 持有该 notifier（9 个页面零改动），窄屏把 `onTitleTap` 传给 delegate；`showNarrowNavigationDropdown == false` 的页面不接线（点击仍无效）。
3. 两个 delegate 各增 `onTitleTap`：`_wrapTitle` 同时挂 `onTap`（打开菜单）与既有 `onDoubleTap`（回顶）。**主人拍板：保留双击回顶，单击因双击判定窗口延迟约 0.3s，全页面一致。**
4. 热区 = 标题文字盒自然宽（展开态 34pt 行 / 收起态 17pt 行），**不含**标题左侧 20pt 留白与右上角 actions 区（防误触、防抢按钮点击）；仅注册 tap 手势，不影响滚动手势竞技场。
5. 宽屏（≥ 900）与横屏（无大标题行）行为不变。

### 交付实现（2026-09-15）
| 文件 | 改动 |
|---|---|
| `lib/app/widgets/narrow_navigation_dropdown.dart` | 新增 `Listenable? openSignal`：被通知即等同点击 ▾，复用同一 `_openMenu`/锚点；`initState`/`didUpdateWidget`/`dispose` 全生命周期管监听 |
| `lib/app/widgets/adaptive_sliver_navigation_bar.dart` | 改 StatefulWidget 持有 `ValueNotifier<int>` 通道（9 个页面零改动）；窄屏把 `onTitleTap` 接线给 delegate，`titleTrailing` 传 `openSignal` |
| `lib/app/widgets/large_title_sliver_header.dart` | 新增 `onTitleTap`（含 `shouldRebuild` 比较）；`_wrapTitle` 同时挂 `onTap` + `onDoubleTap` |
| `lib/features/session_list/session_list_header.dart` | 新增 `onTitleTap`；大标题 / 收起态中标题抽出 `_largeTitleLabel` / `_collapsedTitleLabel`，未接线时不加 GestureDetector（命中零变化） |
| `lib/features/session_list/session_list_page.dart` | 页面持有通道 + `_requestNarrowNavMenu`（tear-off 稳定，避免 delegate 每帧 rebuild）；条件与 ▾ 同源 `!isWide && !isSearchMode` |
| `test/app/narrow_title_tap_test.dart` | 新增 9 例（含 1 源码接线护栏） |

### 验收
- [x] 窄屏会话列表页：点「会话」→ 弹层与点 ▾ 完全一致（同 items、同位置、同 key）
- [x] 其余功能页同断言（`AdaptiveSliverNavigationBar` 头部路径，测试覆盖同组件）
- [x] 滚动后收起态中标题可点（同菜单）
- [x] 设置页：单击标题 → 菜单（≤ 双击窗口内到位）；双击标题 → 回顶且**不**弹菜单
- [x] `showsAny == false`（无 ▾）时点标题无弹层；`showNarrowNavigationDropdown: false` 同理
- [x] 宽屏（≥ 900）零变化；`session_title_alignment_test` 几何不回归
- [x] 反向验证：禁掉 `onTap: onTitleTap` 3 处 → 5 例变红（负向用例仍绿），护栏非空转
- [x] `flutter analyze` 零告警 + 全量 `flutter test` 3002 通过（金照零变更）
- [ ] 主人真机复验：窄屏点「会话」/「技能」/「设置」等标题都能弹出右侧 ▾ 的菜单
