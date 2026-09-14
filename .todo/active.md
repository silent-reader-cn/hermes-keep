# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#87/#88 已收口誊写至 `.todo/20260907.md` @f01c91d；#91 @0076554；#93 @0a69ee2；#95 @da21ea2；#96/#97 APK 安装权限与分享按钮已收口誊写至 20260907.md，随补丁批次 commit；#98 @5c19de7 与 #99 交付 @b9df051（含诊断原档）已收口誊写至 `.todo/20260908.md`）

---

## #76 二期（待一期真机复验后另批开工）

- 内置服务砍 embedded Python 打包瘦身（方案已定 · 未开工），见 `.todo/20260907.md` #76 条目。

---

## #103 引导页高级设置布局：端口/IP 输入框对齐 + 密码行两行式（主人 2026-09-09 反馈）

- 位置：`lib/features/onboarding/widgets/builtin_tab.dart` 高级设置区（`_buildAdvancedSettingsContent` / `_buildPasswordTile`，约 701-971 行）；同步 `lib/features/settings/webui_sidecar_section.dart`（`_buildPasswordTile` 同款分叉，171-365 / 366-518 行）。
- 复现：引导页 → 内置服务 Tab → 展开高级设置。截图现象：①监听端口输入框（maxWidth 100）比监听 IP（maxWidth 140）窄，两框右缘参差；②密码行 `title + trailing: Row(圆点+重新生成+复制+编辑)` 与 460 宽列 + ListTile 左右 padding 打架，`WebUI 密码` title 被挤到几乎看不见。
- 现状 vs 预期：现状=输入框宽度不一、密码标签被挤没；预期=端口/IP 等宽右对齐、密码标签完整可见、操作区独立成行。
- 修复（CupertinoListTile 内重构，不动逻辑/文案/Key）：
  1. 端口输入框 `maxWidth: 100 → 140`，与 IP 等宽（两文件四处统一 140）；
  2. 密码 Tile 两态（编辑态/展示态）`trailing` 只留轻量元素（编辑态=输入框；展示态=圆点 `••••••••`），三按钮 / 输入框+三按钮搬进 `subtitle: Column` 第二行（`Row(mainAxisSize.min)`，按钮 Key/padding/onPressed 原样）；
  3. `config` 未使用参数保留（签名兼容，避免调用点改动）。
- 验收：`C:/tmp/f.bat analyze` 零告警；`onboarding_builtin_tab_test.dart` + `webui_sidecar_section_test.dart` 全绿（28 用例）；settings 金照 light/dark 通过（布局在金照覆盖范围外，未触发更新）。
- 状态：已交付 main 待主人真机复验（窄屏/宽屏双栏右列 460 下验证标签与按钮是否换行）。

---

## #104 引导页/设置页 WebUI 密码行改内联密码框（主人 2026-09-09 选方案 B）

- 位置：`lib/features/onboarding/widgets/builtin_tab.dart`（`_buildPasswordTile`，约 820-980 行）；同步 `lib/features/settings/webui_sidecar_section.dart`（`_buildPasswordTile`，约 366-527 行）。
- 现状 vs 预期：现状=密码行 subtitle 塞三文字按钮（重新生成/复制/编辑）+ 灰字提示 + 右侧圆点，编辑态整行三倍高跳变，与端口/IP 右对齐输入框不是一个画风；预期=密码行与端口/IP 统一为右对齐内联 `CupertinoTextField`，无 subtitle（仅校验失败时红字），无任何文字按钮（含重新生成按钮一并删除，首次随机密码由 `WebuiSidecarConfigStorage.load()` 为空时自动生成落盘保留），框内 suffix 一只眼睛图标切显隐，复制靠系统长按选中。
- 规格（两文件同构，仅默认显隐不同）：
  1. `CupertinoListTile(title: WebUI 密码，subtitle: 仅 _passwordError 非空时红字)`，`trailing: ConstrainedBox(maxWidth 200) > Row(Expanded CupertinoTextField + 眼睛 CupertinoButton)`；Key 保留 `*-password-input`，新增 `onboarding-sidecar-password-visibility-btn` / `settings-webui-password-visibility-btn`；删除 `regen/copy/edit/save/cancel/display` 五 Key 与 `_isEditingPassword/_copiedNotice/Timer/Clipboard` 相关状态逻辑（`dart:async` 中 Timer 停用但 `unawaited` 仍用则保留 import，`services.dart` 无他用则删）。
  2. 引导页 `_passwordObscured` 初值 false（默认明文，方便复制），图标 `eye_slash`；设置页初值 true（默认遮罩），图标 `eye`；点眼睛 `setState` 翻转。
  3. 编辑即改：`onChanged` 清错，`onSubmitted` + 失焦 `_submitPassword`（trim；空→红字 `webuiPasswordEmpty` 不写回；非空且与 provider 不同才 `setPassword`）；联动 `ref.listen` 改为「未聚焦时跟随 provider」。
  4. `generateRandomPassword` 保留给首次生成；`agentGatePasswordHint/agentGateRegeneratePassword` 文案保留（他处无引用亦不删，避 l10n churn）。
- 测试更新：`onboarding_builtin_tab_test.dart` TASK U2 密码段（约 580-610 行）改新流程（框有值→眼睛切显隐→改字 done 写回→空字红字）；`webui_sidecar_section_test.dart` 密码两用例（约 394-549 行）重写（默认遮罩→眼睛明文→改字提交写回→空字红字，删复制/重生成断言）。
- 验收：`C:/tmp/f.bat analyze` 零告警；两密码用例文件全绿；`--update-goldens` 仅布局金照受影响时刷新（onboarding 金照大概率命中）。
- 状态：规格已落盘，待实现。

---

## #105 方向：安卓灵动岛（小米超级岛 / Android 16 Live Updates）（主人 2026-09-13 问询，柚子调研后待拍板）

- 调研结论（来源：小米澎湃OS开发者平台 dev.mi.com 超级岛文档 2026-01 更新版；XimiTime 2026-01-30 HyperOS 3.1 报道；阿里云 EMAS 小米超级岛推送指南）：
  1. **路线 A（推荐）＝ Android 16 原生 Live Updates（ProgressStyle）**。HyperOS 3.1 已支持该原生 API，第三方 app 无需小米专属代码即可上岛；Pixel/三星等安卓 16 机型同样受益。技术前提：targetSdk ≥ 36 + 通知带 LIVE 标注 + 进度走 ProgressStyle；本仓 compileSdk=37 已够，targetSdk 走 `flutter.targetSdkVersion` 需确认 Flutter 工具链实际解析值，不足则升。
  2. **路线 B＝小米「超级岛/焦点通知」官方通道**（`miui.focus.param` 扩展参数 + 岛模板库）。效果最精细，但准入门槛重：小米开发者账号 → 场景预审 → 完整方案审核 → 设备白名单联调 → 提交正式 APK 上线验证才开正式权限；且要求应用已创建/上架。适合正式发布上架后再铺，现阶段（自分发 APK）不走。
  3. 准入合规：本项目场景「回合进行中 / 等待用户确认」= 用户主动发起 + 明确生命周期 + 需实时关注，符合小米准入原则，预审无硬伤。
- 现状底子：`lib/features/notifications/turn_notification_service.dart` 已用 flutter_local_notifications ^22.3.0 发 ongoing 通知，`main.dart:455` 已有 `syncOngoingNotification(activeCount, titles)` 聚合活跃回合——Live Update 的语义（进度条、状态栏胶囊 chip、完成即收）正好替换/升级这条链路，**不需要新增服务端能力**。
- 范围（路线 A 落地时）：
  1. 回合开始 → POST_NOTIFICATIONS + 建 LIVE ongoing 通知（ProgressStyle：计时器或不定量进度，标题=活跃回合数/会话名，状态栏显示 chip）；
  2. 需要用户确认（clarification）→ 岛展开提示 + 点击唤起 app（沿用现有 deep-link response 接线）；
  3. 回合完成 → 收岛 + 发普通完成通知（现行为保留）；
  4. `flutter_local_notifications` 对 ProgressStyle 若覆盖不全，Kotlin 侧（MainActivity 同级新增 Plugin/MethodChannel）兜底直建 Notification；
  5. 设置页开关：灵动岛/实况通知 开-关（主人铁律：新功能须有设置开关），关闭回退为现有普通 ongoing 通知。
- 兼容性（2026-09-13 主人问询后核实，来源 developer.android.com Live Updates 文档 2026-08-07 版）：**不影响低版本安装与使用**。走 `NotificationCompat#setRequestPromotedOngoing` + `ProgressStyle` 兼容层属渐进增强：安卓 16+/HyperOS 3.1 上岛出 chip；安卓 8~15 自动降级为现有普通 ongoing 通知；`POST_PROMOTED_NOTIFICATIONS` 权限在低版本被忽略无副作用。minSdk=24（本机 Flutter 工具链实测值）不动，targetSdk 无须强拉 36，compileSdk=37 已够。进度条视觉细节低版本缺失但本仓通知为文字语义，降级无损。
- 风险/未知：① HyperOS 3.1 原生 Live Updates→超级岛的映射质量仅有第三方报道，需主人手机实机取证；② 主人机器澎湃 OS 版本未确认（OS3 才有岛，OS2 只有焦点通知、无岛）；③ 岛默认 1h 兜底消失、展开态 5s 收起，回合超时体验需设计兜底；④ 小米保活链路（#27）当时实机取证未闭环，LIVE 通知同样依赖后台存活，同链路风险。
- 验收：安卓 16 模拟器看 ProgressStyle 渲染 + 主人 HyperOS 实机看是否上岛出 chip；analyze 零告警；通知相关既有测试（turn_notification）全绿；金照不受影响。
- 状态：**已交付** main @5ea4b14（子代理执行 + Leader 独立复验：analyze 零告警、2844 全绿、金照零变更——新开关在保活二级页不在金照覆盖内；Leader 修复 Kotlin chip 截断 bug：TextUtils.ellipsize 按像素非字符数，改为 take(6)）。**待主人 HyperOS 实机复验**（debug APK 构建中）：①发回合 → 状态栏 chip/岛摘要态出现「Hermes · 回合进行中」；②回合结束 → LIVE 撤销；③设置→后台保活页 → 「实况通知（灵动岛）」开关可关，关后仅剩普通常驻通知。若 OS 版本 <3.1 或系统未开放实况通知资格，预期=无岛、行为与旧版一致（降级无感）。

---

## #106 会话列表实时化：订阅 /api/sessions/events 推送 + 刷新补拉兜底（方案 D，主人 2026-09-14 拍板）

- 背景实测取证（2026-09-14，Leader 直连 30002 全程 API 采样，原始档 `D:\tmp\session_visibility_trace.json` / `sessions_events_probe*.py`）：
  1. 新建会话全程：`POST /api/session/new`(title="Untitled", 0 消息) → 列表 ABSENT（`isEmptySidebarPlaceholder` 设计过滤，session.dart:862-886）→ `POST /api/chat/start` 同步返回最终 title+stream_id → **+5~8s 才在 GET /api/sessions 可见**（pending 落行 + 服务端懒缓存重建）。
  2. 服务端 `/api/sessions/events`（routes.py:13305，session_events.py）推 `sessions_changed {type,version,reason,profile?,session_id?}`，5s keepalive；实测 `session_new` 在创建后 ~900ms 即推送。触发点覆盖 new/rename/archive/delete/pin/move/branch/duplicate/import/cron_complete/attention_resolved，**回合完成不推**（实测 turn done 后 12s 无 push——存量会话收尾仍靠客户端 done→force 路径，已有）。
  3. 服务端会话列表缓存（route_session_list_cache.py）：空闲 TTL 2.5s；**任一 stream 活跃时 freeze 到 45s**（#4808），stale-while-revalidate——首个 stale 请求拿旧数据后台重建，实测新会话首可见因此延迟 ~5s。即：**客户端现有 0ms+600ms 双枪（session_list_providers.dart:1142-1145）必然打在缓存旧数据上**，之后退化 30s 轮询；且 force 撞 `_refreshInFlight` 被静默吞（providers:535/665，无补拉）。
- 目标：列表变更感知从「最坏 30s+」降到**亚秒~秒级**；消灭「force 被吞」与「双枪落空」。
- 范围（全部在 lib/features/session_list/ + 接线点，不碰服务端）：
  1. **新增 `SessionEventsSseClient`**（`lib/features/session_list/session_events_client.dart`）：dio 复用 `ApiClient.dio`（继承 cookie/CSRF 拦截器，同 clarify 流先例 chat_server_api.dart:348-376），订阅 `GET /api/sessions/events`；解析 `event: sessions_changed` 帧；**version 单调去重**（payload.version <= lastVersion → skip，防重放风暴）；profile 字段保守处理：非空且不等于当前激活 profile 也刷新（全量拉取代价可接受，宁多刷不漏刷）。
  2. **生命周期与门控**（对齐现有 30s 轮询门控语义 session_auto_refresh.dart:136-141）：`resumed && windowFocused && enableSessionEventsStream(设置开关，默认开)` 才持有连接；失焦/后台关流，回焦重连并立即 `refreshIfStale()` 一次（补空洞）；断线指数退避重连（复用 sse_client.dart 现有能力，勿新造轮子——先核实 SseClient 是否支持无 after_seq 的持久订阅，不支持则在 SessionEventsSseClient 内实现 1s*2^n 封顶 30s 重连）。
  3. **推送→刷新加防抖合并**：收到事件经 800ms debounce 合并多次 push（批量删除/多设备风暴）后 `refreshIfStale(force:true)`。
  4. **刷新补拉兜底（方案 A 并入）**：`SessionListController` 加 `_refreshDirty` 标记——`refreshIfStale(force:true)`/`refresh()` 撞 `_refreshInFlight` 时置位，当前轮 finally 里检查并自动补拉一次（只补一次，防连环）；`handleNewChatSession` 双枪改**阶梯补拉 0/+600ms/+2.5s/+5.5s**（覆盖服务端懒缓存重建窗），或**收到本会话 session_new push 即提前停止阶梯**。回合 done 的 force 同样受益于 dirty 兜底。
  5. **设置开关**（主人铁律）：设置页「会话」或「通用」组新增 `实时推送会话列表（实验）` CupertinoSwitch，持久化 key `session_events_stream_enabled` 默认 true；关闭 = 纯轮询旧行为（现链路零回归）。
  6. 30s 轮询保留为兜底（跨断网/服务端事件丢失），周期可考虑放宽到 60s——**本期不动**，保守。
- 现状 vs 预期：现状=新会话首条消息后要等 ~5-35s 列表才见（取决于轮询相位）、别的设备改名/归档/pin 后本机最长 30s（失焦则永久直到获焦）；预期=推送路径 <2s 内更新，推送不可用时无回归。
- 禁区：不动 `isEmptySidebarPlaceholder` 过滤语义（#1171 对齐蓝本）；不动 `_sessionListRefreshThrottleWindow` 1500ms 存量节流；不做乐观占位插入（设计已否决，dirty 补拉后无需）。
- 测试：
  1. 单测 `test/features/session_list/session_events_client_test.dart`：FakeHTTP 推 sessions_changed 帧 → 断言 debounce 后 refreshIfStale(force) 被调 1 次；version 回退帧被忽略；keepalive 注释帧不炸解析；开关关闭时不建连。
  2. 单测扩展 controller dirty 补拉：in-flight 时 force → 当前轮结束后自动补拉一次；无 in-flight 时不补。
  3. 回归：现有 session_list / auto_refresh 测试全绿；金照不受影响（无 UI 布局变更，设置页新行如需金照另行 --update-goldens 审查）。
- 验收：`C:/tmp/f.bat analyze` 零告警 + `C:/tmp/f.bat test` 全绿；实机取证=主人 Windows 端另开 WebUI 30002 改名/归档一个会话，Flutter 列表 <2s 跟随；手机新建会话发送后列表 <6s 稳定出现（对照现状最坏 35s）。
- 后续候选（同批调研产出，未拍板不开工，各自动机独立）：
  - a) `/api/approval/stream`：客户端 `approvalStreamUrl`（api_client_chat.dart:139）**零接线**，approval 靠主 stream 捎带——重连空窗/多设备审批不可见；clarify 已有独立 SSE 先例可镜像。
  - b) `/api/session/stream?session_id=&known_count=`：`session-updated`/`bg_task_complete` 帧（WebUI messages.js:7553 在用，server:7587），进入聊天页伴随订阅→复用 `syncMissingMessages`，治「双端同看一会话内容不同步」。
  - c) `/api/sessions/gateway/stream`：watcher 全量 `sessions_changed {sessions}`，依赖 show_cli_sessions+watcher 存活（30002 实测未启用，probe 路径先行），优先级最低。


---

## #107 接线 /api/approval/stream 独立 SSE（候选 a 立项，2026-09-14 主人「按推荐立项」）

- 位置：`lib/core/api/api_client_chat.dart:139` `approvalStreamUrl` 现为**零接线死代码**；镜像 clarify 独立流先例 `lib/features/chat/chat_server_api.dart:348-376`（连/断/重建 + pending 拉取兜底）。
- 现状 vs 预期：现状=approval 卡片只靠回合主 stream 捎带帧，SSE 断线重连空窗期、或他端（WebUI/CLI）触发的审批，本机 approval 状态不可见/残留；预期=进入会话即伴随订阅 `/api/approval/stream?session_id=`（帧：`initial{pending,pending_count}` + `approval{...}`，server routes.py:19308/19321），pending 有→置 `ChatPhase.approvalPending`，无→清卡；与主 stream 捎带路径幂等合并（同 approval_id 去重，不双渲染）。
- 生命周期：与回合流解耦（页面在挂→订阅，退页 dispose），断线重连退避同 #106 参数（1s*2^n 封顶 30s）；设置开关沿用 #106 的 `session_events_stream_enabled`? 独立键 `approval_stream_enabled` 更清晰（默认开），验收时再定。
- 验收：analyze 零告警；单测=Fake 推 approval 帧→phase 变、initial 空→清卡、重连补 initial；既有关卡/审批测试全绿。规格细化后与 #108 并行拆 worktree。

---

## #108 接线 /api/session/stream 会话内容增量同步（候选 b 立项，2026-09-14 主人「按推荐立项」）

- 位置：新伴随订阅（chat 页生命周期内），帧 `session-updated`（服务端比 `known_count` 后推增量计数）与 `bg_task_complete`；参照 WebUI `static/messages.js:7553` 消费法与 server routes.py:17429+ 语义；单会话 journal 变体 `/api/session/{sid}/events`（routes.py:13308/17587）与主 chat/stream 重叠，**不接**。
- 现状 vs 预期：现状=手机开着会话 A、电脑上继续聊 A，本机内容不动（回合外无推送）；`process` 后台任务完成（如 delegate 通知）只能靠下次进页 syncMissingMessages；预期=session-updated→复用 `chat_controller` 现有 `syncMissingMessages`（差值同步已实现），bg_task_complete→复用现有通知/卡片路径；known_count 用服务端持久 `message_count` 基准（勿用渲染窗口长度，messages.js:7540-7546 注释的坑）。
- 与 #106 关系：互补——#106 管列表行（结构变更），#108 管当前会话正文（内容追加）。
- 验收：analyze 零告警；单测=推 session-updated 触发 syncMissingMessages 一次、known_count 门槛生效（无差值不拉）；金照不受影响。规格细化后与 #107 并行拆 worktree。

---

**#106 状态（2026-09-14 收口）**：已交付 main @d99d120（agy worktree `agy/s106-events` 执行，Leader 独立复验：主仓 analyze 零告警 + 2853 全绿 + 金照零破坏；新增 9 用例）。**待主人真机复验**：①Windows 端开着 App，在 WebUI 30002 里改名/归档一个会话 → 列表 <2s 跟随；②手机新建会话发首条消息 → 列表 <6s 稳定出现（现状最坏 35s）；③设置页「定时会话」组出现「会话列表实时推送」开关，关闭后退化纯轮询旧行为。开关落点在 _CronSection（与 cron 显隐同组），主人若觉得语义错位可后续挪组。
