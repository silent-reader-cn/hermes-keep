# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#103 @77211b2、#104 @caaafa1、#105 @5ea4b14、#106 @d99d120、#107 @92e7449、#108 @d8b9973、#109 @a922086 已收口誊写至 `.todo/20260914.md`，其中 #103/#105/#106/#107/#108/#109 待主人真机/实机复验；#110 099131e、#111 b9b7ae0 已收口誊写至 `.todo/20260914.md`（#110/#111 待主人真机复验）；#76 二期 @8b4fab1 已收口誊写至 `.todo/20260914.md`（打包瘦身，安装包产物已本机取证）；#87/#88 已收口誊写至 `.todo/20260907.md` @f01c91d；#91 @0076554；#93 @0a69ee2；#95 @da21ea2；#96/#97 APK 安装权限与分享按钮已收口誊写至 20260907.md，随补丁批次 commit；#98 @5c19de7 与 #99 交付 @b9df051（含诊断原档）已收口誊写至 `.todo/20260908.md`；#116 @v0.1.47、#117 @本轮提交 已收口誊写至 `.todo/20260914.md`；#114 P0（展开态真应用图标/倒计时方向/small icon 剪影）@49062b4 已收口誊写至 `.todo/20260914.md`（待主人真机复验））

## #112 live 中途归档组锚点成「死锚」→ 幽灵工具卡 + 相邻合并不了（主人 2026-09-14 报告截图，Leader 取证）

- 现象：会话 `59b5ab1f735b`「等它跑一会」正文下方三张连续卡：终端×2思考×2 / 待办列表×1思考×1 / 终端×1思考×1。中间无任何正文，按「text 唯一分隔符」应只有一张卡。
- 取证（state.db 消息流 + tool_call.dart 分组管线逐步复算）：
  - 消息序：621「已扇出…」todo+think、623「等它跑一会」terminal+think(68)、625 无文本 terminal+think(479)、627「还在读码…」terminal+think(272)。
  - 正确分组（withThinkingRows 区间语义）：623→627 区间 = tools(623)+tools(625)+think(625)+think(627) = 终端×2 思考×2 —— 即截图第 1 张卡（D），**这条是对的**。
  - 第 2 张「待办×1思考×1」= 上一张卡（C，621 区间）内容的**整卡复制**；第 3 张「终端×1思考×1」= D 区间的前缀子集。DB 里 621 之后根本没有第二个 todo_list —— 两张均为**幽灵卡（重复渲染）**，不是聚合算法漏合。
- 根因链：
  1. live 回合中 `_archiveLiveToolCallsIfNeeded/_archiveLiveReasoningIfNeeded`（chat_controller.dart:3922/3949）会把累积的 live 工具/思考以 `anchor=stream.streamingAssistantMessageId ?? toolCallAnchorMessageId` 落入 completedToolCallGroups。
  2. 回合结束走服务端 transcript 刷新：state.db 读取路径**不携带 message_id**（api/models.py:7591 optional 列表无 id/message_id）→ 重载消息 `ChatMessage.messageId=null` → 服务端派生组锚点全部落在 `raw:<idx>` 空间；锚点也随分页 offset 漂移。
  3. `ToolCallGroup.merging` 以 `'anchor:isAboveContent'` 为 key（tool_call.dart:552）——live 归档组锚点（流式 id 空间）与派生组锚点（raw: 空间）对不上 → 不合并，两组并存；`withThinkingRows` 尾部把未映射 raw 组原样保留（tool_call.dart:532-537）。
  4. `coalescingAdjacent` canMerge 要求双方 `anchorIndex >= 0`（tool_call.dart:790-793）——死锚组永远拒绝合并，作为独立卡挤在旁边 →「明明连续却没合并」。渲染层挂载匹配同样要求锚点命中 messageId/anchorId（chat_message_list.dart:1854-1855），死锚组经 turn.allToolGroups 或兜底路径仍可见。
  5. `_reanchorGroupsToMessages`（chat_controller.dart:3989-3998）只救 `local-`/`unanchored`/oldStreamingId，且仅 `_applyCompletedStreamSession` 路径调用；`_handleStreamEnd→_completeCurrentResponse`（done 无 refresh 路径）与全量重载/缓存回放路径**均不 re-anchor**。
- 修复方向（拍板前不动码）：
  - A（主修·归档即锚定）：live 归档时点统一把锚点 re-anchor 到当前 messages 的 assistant anchorID（`TranscriptTurnClassifier.anchorID`）空间，而非流式临时 id；refresh/重载完成后对 completedToolCallGroups 全量扫「锚点当前 anchor 集合」的组二次 re-anchor（不再只认 local- 前缀）。
  - B（去重兜底）：`ToolCallGroup.merging`/`coalescingAdjacent` 前，对两组做内容指纹比对（stable tool-call id 集合 + think 文本指纹，复用 `_toolCallFingerprint`）——子集/相等者丢弃或合并，防锚点空间漂移导致的重复卡。
  - C（可选加固）：`coalescingAdjacent` 对 `anchorIndex<0` 的组按 `isAboveContent` + 最近有锚组归并，防未来新泄漏场景再冒卡。
- 禁区：不动「text 唯一分隔符」时间线语义（#20/#34/#54 既定）；liveTimelineProvider 流式期间表现正确，勿动；金照不受影响（幽灵卡系数据路径产物）。
- 测试：`test/core/models/tool_call_test.dart` 增补「归档组锚=流式 id + 派生组锚=raw: → re-anchor/指纹去重后单卡」；controller 测试模拟 done→refresh 序列断言 completedToolCallGroups 无死锚残留。
- 验收：analyze 零告警 + test 全绿 + 金照零破坏；实机取证=主人重进该会话，「等它跑一会」下方仅 1 张卡（终端×2 思考×2）。

---

## #113 保活设置页「WorkManager 状态」行是静态绿勾（不反映真实注册状态）

- 位置：`lib/features/notifications/background_keepalive_settings_page.dart:141-157`（`key: settings-bg-workmanager-status` 的 `CupertinoListTile`）——trailing 恒为 `CupertinoIcons.checkmark_seal_fill` 绿勾，subtitle 恒为 `l10n.bgWorkManagerStatusSubtitle`，**无任何数据源**。
- 复现：任意平台打开「设置 → 后台保活」即见绿勾；2026-09-14 release 包 WorkManager 注册失败（#110）时该行**仍显示绿勾**——状态行与真实 `ProductionBackgroundKeepaliveService.wmReady` 完全解耦。
- 现状 vs 预期：现状 = 静态绿勾（误导，是 #110 长期未被发现的旁因之一）；预期 = 反映真实三态：`wmReady == true` → 绿勾 + 现有文案；未就绪 → 红/橙标识 + 失败归因（可直接复用 #110 交付的 `WorkManagerRegistrationProbe.describe()`：initialized/creation/error）；非 Android（Windows 等）→ 「不适用」，不得误报「未就绪」。
- 范围：仅该行 + 一个只读状态 provider（`backgroundKeepaliveServiceProvider` 已可读，`wmReady` 需接口层暴露或 `is ProductionBackgroundKeepaliveService` 判定）；**不动**保活开关 / 前台服务 / 通知链路；若新增 l10n 文案须 zh+en 同补并跑多语言用例。
- 验收：未就绪时不再显示绿勾且 subtitle 含探针归因；就绪 / 未就绪 / 不适用三态正确；widget 用例覆盖三态；analyze 零告警 + test 全绿 + 金照零变更。
- 状态：待开工（2026-09-14 由 #110 复盘登记，未动码）。

## #114 P1 实况通知（灵动岛）内容升级：当前动作文案 + ProgressStyle 增强 + 回合状态回调链路（P0 已收口 @49062b4）

> 主人 2026-09-14 报告（HyperOS 超级岛展开态截图）。选型对比页：`sketches/live-update-icons.html` + `live-update-icons-preview.png`。
> **P0（展开态真应用图标 / 倒计时方向 / small icon 剪影）已交付 @49062b4，已誊写归档至 `.todo/20260914.md`，待主人真机复验。**

### P1 — 待主人拍板后开工

- 内容升级：`contentText` 由「会话标题」→「**当前动作**」（思考中／调用终端…／输出中）。官方 UX 明确要求"算不出进度时给主动占位文案"，现行静态「正在生成回复…」不达标。
- `ProgressStyle` 增强：`setProgressTrackerIcon` 随状态动态换（20dp，或官方 sample 的 40×20 胶囊）；`addProgressPoint` 每次工具调用落一点使内容随回合增长。**进度条保持 indeterminate**——agent 回合无真实百分比、段长不可预测，套 `Segment` 会出现"条走完还在跑"（截图里那条 1/5 填充已在造假进度，勿加剧）。
- 前置改造（成本大头）：现通知**仅在活跃会话集合变化时**刷新（`lib/features/session_list/session_auto_refresh.dart:164-186`，集合相同即早退），阶段变化根本不触发。需新建回合实时状态回调链路（对标 `turnNotificationHookProvider`），并把 `ChatPhase`（`lib/features/chat/chat_state.dart:11`）的等待态（`clarifyPending` 待回复／`approvalPending` 待批准）一并上岛——那是主人离开时最需要被叫回的状态。
- 参考：同赛道标杆 Capsulyric（小米 15 / HyperOS 3.0.300.7 实机验证：走 AOSP Live Update 通道即可映射到超级岛，**无需 Root/Shizuku**；小米私有超级岛接口才需特权，不碰）。

## #115 新建会话自动打开上下文弹窗：抢在页面入场滑动（300ms）中途弹出 → 弹窗冻结在半程锚点坐标（主人 2026-09-14 报告）

> 主人原话：新建会话自动打开上下文弹窗后，总是新建会话页面弹出的滑动动画**播放到一半**的时候弹窗，导致弹窗可能停在「动画半程的上下文指示器位置」上；应等新聊天页入场动画播完再弹。

- 位置（触发链，2026-09-14 源码级取证，未实机复现）：
  - 标记（唯一触发源）：`lib/features/session_list/session_list_page.dart:776-781`（`createSession` → `markCreated(id)` → `_openChatRoute`）；`_openChatRoute`（:964-971）宽屏 `context.go('/chat/:id')`、窄屏 `context.push(...)`。全仓 `markCreated` 仅此一处；`_onBranch`（:1165-1174）不标记 → **不存在第二条自动打开链**。
  - 消费：`lib/features/chat/widgets/chat_input_bar.dart` —— `_checkRecentlyCreatedOnMount`（:104-118，命中且开关开 → `_pendingAutoOpen = true`）；两条打开路径都**不看路由动画状态**：① initState 首个 postFrame 调 `_tryAutoOpenContextPopover`（:90-101 → :120-128）；② `_bindAutoOpenListener`（:197-209）首个 `contextWindowSnapshot` 到达时 postFrame 打开。最终都 `unawaited(_showContextPopover())`（:613-635，`anchorKey: _contextIndicatorKey`、`preferredWidth: 260`、默认 `PopoverAlign.end`）。
  - 定位机制（根因所在）：`lib/app/widgets/adaptive_popover.dart:88-115` 在 `showAdaptivePopover` **调用瞬间**用 `anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox)` **快照**锚点矩形；:207-228 把冻结值交给 `_AdaptivePopoverHost`，:298-362 用静态 `Positioned(left/top/bottom)` 布局。**无 LayerLink / CompositedTransformFollower**，弹层插入根 Overlay（不随页面转场平移），且 `_AdaptivePopoverHost` 无入场动画、entry 无重建触发 → 坐标一旦算出即**永久冻结**（动画结束后不会自己挪回）。
  - 转场参数：`lib/app/widgets/hermes_page_route.dart:22-23` 300ms、`Curves.easeOut`；:80-88 push 时 `Offset(1.0,0)→0`（整页自右滑入，纯水平）；`lib/app/router.dart:106-114` `/chat/:sessionId` 走 `HermesPage`；宽屏同一转场（`lib/app/shell/adaptive_shell.dart:280-295`，详情区 `widget.child` 即转场页）。Flutter SDK `widgets/routes.dart` 的 `TransitionRoute` 无 `disableAnimations` 短路（本仓未设 `animationBehavior`）→ 这段滑动**恒为 300ms**，时长可预期。
- 复现：设置 → 对话 → 打开「新建会话自动打开上下文」（`ValueKey('settings-switch-auto-open-context')`）→ 宽屏（≥900）点侧栏「新建会话」→ 聊天页自右滑入的 300ms 内，上下文弹窗立刻出现。
- 现状 vs 预期：
  - 现状：弹窗锚点取「滑动半程」的指示器坐标；弹层在根 Overlay 且坐标冻结、无跟随 → 弹窗定格在半程位置。宽屏（详情区宽 1600、弹层 260 + `align.end`）半程 `anchorRect.right` 被推到屏外，`left` 被 clamp 到 `safeRight - effectiveWidth` → **弹窗贴屏幕右缘**，而指示器静止态在左侧数百像素处（1200 宽详情区半程位移 ≈ 600px，1600 宽 ≈ 800px；含 clamp 后残差为推算值，非实测）→ 即主人所见「弹窗停在动画半程的指示器位置上」。窄屏（如 390 宽）弹层宽度接近屏宽、clamp 上限贴近静止值，残差仅数像素 → **症状以宽屏/桌面为主**。垂直方向不受影响（滑动为纯水平，`anchorRect.top` 全程不变）。
  - 预期：自动打开路径**等本页入场转场播完**（`ModalRoute.of(context)!.animation!.status == AnimationStatus.completed`）再弹，锚点取静止态坐标；手动点按指示器（:748 / :1134 `onTap: _showContextPopover`）行为不变（人手点按时页面已静止），无新增延迟。
- 修复方向（待主人拍板，先不动码）：
  - A（推荐·最小）：`chat_input_bar.dart` 新增 `Future<void> _awaitEntranceTransition()`——取 `ModalRoute.of(context)?.animation`；为 `null` 或 `isCompleted` 时立即返回；否则一次性 `addStatusListener` 等 `AnimationStatus.completed`，并加**超时兜底**（建议 `route.transitionDuration + 200ms`，或固定 600ms）后照常打开，`finally` 移除监听；`_tryAutoOpenContextPopover` 与 listener 回调 `await` 后再 `_showContextPopover()`，全程 `mounted` 守卫（等待期间 `_pendingAutoOpen` 已置 false，天然防重复弹出）。**禁用 `route.completed`**：SDK `TransitionRoute.completed`（`routes.dart:115-121`）只在路由被 pop 后完成，语义不符。
  - B（可选加固，非本次必需）：`showAdaptivePopover` 增加「实时跟随锚点」模式（`LayerLink` + `CompositedTransformFollower`）——影响全仓弹层调用方（会话菜单/工作区/模型下拉等），风险面大。
  - C（不推荐）：固定 `Future.delayed(350ms)`——与转场时长硬耦合，改时长即回归。
- 禁区：不动「新建会话」业务流程与 `markCreated` 标记/清除时序（:108-112 的 microtask clear）；不动手动点按弹窗路径；不动路由转场 300ms（主人 2026-09-02 拍板值）。
- 测试：新增 widget 用例——用 `HermesPageRoute` push 一个含 `ChatInputBar` 的页面（预置 `markCreated(sid)` + 开关开启 + snapshot 就绪），`pump(150ms)` 断言弹层**尚未**出现（`AdaptivePopover.activeOverlayCount == 0`），`pumpAndSettle()` 后断言弹层出现；再补一条「快照在动画已完成后才到达 → 立即弹出」守住 listener 分支不被延迟吞掉。
- 验收：`C:/tmp/f.bat analyze` 零告警 + `C:/tmp/f.bat test` 全绿（金照零变更）；**实机取证（本机 Windows 宽窗）**：开开关 + 新建会话 → 弹窗在滑入完成后出现、水平位置与指示器静止态对齐（右缘 ≈ 指示器右缘，而非贴屏幕右缘）；窄屏同流程无错位；手动点图标无延迟。
- 状态：待开工（2026-09-14 主人报告，柚子源码级取证；未实机复现、未动码）。

---

## #118 自动检查更新形同虚设：无启动检查 + 结果无人消费 + 版本基准常量漂移（主人 2026-09-14 报告，柚子源码级取证 + 探针实测）

> 主人原话：自动检查更新的时机是什么？感觉现在的自动检查更新无效。

- 现状 · 唯一触发时机（临时 widget 探针实跑取证，探针已删、工作区干净）：
  - 全仓仅 `lib/features/settings/settings_page.dart:2202` watch `autoCheckUpdateEnabledProvider`；检查由该 Notifier 的 `build()` 发起（`lib/core/update/update_providers.dart:23-37`）。`lib/main.dart` / `lib/app.dart` 零涉更新模块 → **冷启动 / 开机自启 / 托盘 / 后台都不检查**。
  - PROBE A：进「设置」页且**完全不滚动** → `checkForUpdates(isManual:false)` 被调用 1 次（`SliverToBoxAdapter` 立即 build，无需滚到关于区）。
  - PROBE B：开关 off → 不发起。PROBE C：同一 App 运行期间离开再回设置页 → 总次数仍为 **1**（provider 非 autoDispose 常驻，`update_providers.dart:48-51`）。
  - 频控 24h：与上次检查间隔 <24h 直接跳过（`update_checker_service.dart:206-214`）；**失败也写时间戳**（catch 内 `_recordCheckTime`，:255）→ 一次网络抖动即锁死 24h。
- 根因 1 · 结果无人消费（"跑了但没人听"）：`update_providers.dart:35` `unawaited(service.checkForUpdates(isManual: false))` 返回值直接丢弃；全仓 `hasUpdate` 仅在 `settings_page.dart:2129` 手动路径被用 → 静默检查即使发现新版本也**无任何 UI 反馈**（无红点 / badge / toast），自动检查实质空转。
- 根因 2 · 版本基准硬编码漂移（硬伤）：`lib/core/update/version_info.dart:5` `appVersion = '0.1.31'`，自 #101 交付（f4d53d1）后从未随发版更新；登记时（2026-09-14）`pubspec.yaml:19` 已达 `0.1.48+54`（常量未纳发版流程 → 漂移随每次发布继续扩大）、远端 latest Release `v0.1.47`。PROBE D 实测 `newer('v0.1.47', appVersion) == true` → **即使装的正是 v0.1.47 也永远判「有新版本」**（手动检查必误报）。而设置页版本号走另一条路径（`settings_providers.dart:25` `appVersionProvider` 动态读 pubspec）→ 同一页面「显示 0.1.47 / 判定基准 0.1.31」自相矛盾。
- 根因 3 · 开关重开不触发：`AutoCheckUpdateController.setEnabled`（`update_providers.dart:40-44`）只改 state 不检查，仅 Notifier 首次 build 查一次；关掉再打开无任何反应。
- 复现：① 装任意 release 包后**从不进设置页** → 永远不检查；② 进设置页（不滚动）→ 检查确已发生但界面零提示；③ 当前版本为最新时点「设置 → 关于 → 检查更新」→ 误报「发现新版本 v0.1.47」。
- 现状 vs 预期：现状 = 不进设置页永不检查、检查到也不提示、基准漂移必误报；预期 = 启动后自动检查一次 + 发现新版本有可见入口 + 判定基准与实际版本一致。
- 修复方向（待主人拍板，先不动码）：
  - A（必做·消漂移）：`appVersion` 改由 pubspec / 平台通道动态取（或发版脚本强制同步），并加契约测试断言常量与 `pubspec.yaml` 一致。
  - B（必做·结果可见）：静默检查结果落 `updateAvailableProvider`，设置入口挂红点；或首次发现新版本弹一次可关闭提示。
  - C（时机前移）：启动后延迟数秒做一次（桌面端可加托盘菜单入口），设置页保留。
  - D（频控分账）：失败不写 `last_check_at`（或只写短重试窗口），避免一次网络抖动锁死 24h。
- 禁区：不动 `_checkUpdate` 手动弹窗交互与双端资产匹配（`handleDownloadOrOpenRelease`，含安卓确认框）；不动 24h 频控阈值本身（只改失败记账）；不动既有 l10n key 命名（新增文案须 zh+en 同补）。
- 测试：`test/core/update/` 增补——prod 启动触发一次 / 开关关闭不触发 / 24h 内跳过 / 失败不锁频；新增「`appVersion` 常量 == pubspec version」契约用例；「发现新版本 → 红点或提示出现」widget 用例。
- 验收：`C:/tmp/f.bat analyze` 零告警 + `C:/tmp/f.bat test` 全绿（金照零变更）；实机取证 = 本机 Windows 冷启动后不做任何操作，若远端有新版则出现可见提示；当前版本为最新时手动检查显示「已是最新版本」而非误报。
- 状态：待开工（2026-09-14 主人报告，柚子源码级取证 + 探针实测；未动码）。

---
