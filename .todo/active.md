# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#103 @77211b2、#104 @caaafa1、#105 @5ea4b14、#106 @d99d120、#107 @92e7449、#108 @d8b9973、#109 @a922086 已收口誊写至 `.todo/20260914.md`，其中 #103/#105/#106/#107/#108/#109 待主人真机/实机复验；#110 099131e、#111 b9b7ae0 已收口誊写至 `.todo/20260914.md`（#110/#111 待主人真机复验）；#76 二期 @8b4fab1 已收口誊写至 `.todo/20260914.md`（打包瘦身，安装包产物已本机取证）；#87/#88 已收口誊写至 `.todo/20260907.md` @f01c91d；#91 @0076554；#93 @0a69ee2；#95 @da21ea2；#96/#97 APK 安装权限与分享按钮已收口誊写至 20260907.md，随补丁批次 commit；#98 @5c19de7 与 #99 交付 @b9df051（含诊断原档）已收口誊写至 `.todo/20260908.md`）

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
