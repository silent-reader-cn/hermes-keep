# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#103 @77211b2、#104 @caaafa1、#105 @5ea4b14、#106 @d99d120、#107 @92e7449、#108 @d8b9973、#109 @a922086 已收口誊写至 `.todo/20260914.md`，其中 #103/#105/#106/#107/#108/#109 待主人真机/实机复验；#87/#88 已收口誊写至 `.todo/20260907.md` @f01c91d；#91 @0076554；#93 @0a69ee2；#95 @da21ea2；#96/#97 APK 安装权限与分享按钮已收口誊写至 20260907.md，随补丁批次 commit；#98 @5c19de7 与 #99 交付 @b9df051（含诊断原档）已收口誊写至 `.todo/20260908.md`）

---

## #76 二期（待一期真机复验后另批开工）

- 内置服务砍 embedded Python 打包瘦身（方案已定 · 未开工），见 `.todo/20260907.md` #76 条目。

---


## #110 Android release：WorkManager 初始化失败（pigeon channel-error，保活周期轮询缺位）

- 现象：2026-09-14 诊断日志导出（release）冷启动即报 `PlatformException(channel-error, Unable to establish connection on channel: "dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.initialize")`，随后「后台保活服务部分就绪（ForegroundTask 就绪，WorkManager 失败）」；全仓 docs/.todo 首次出现，非历史遗留。
- 位置：`lib/features/notifications/background_keepalive_service.dart:336-368`（initialize try/catch）；调用点 `lib/main.dart:422-424`（`unawaited(...initialize())`）；依赖 `pubspec.yaml:65 workmanager: 0.10.9`（上游最新 0.10.10）。
- 根因链（源码实证）：channel 绑定发生在插件 `onAttachedToEngine()`→`WorkmanagerHostApi.setUp(...)`，但其前先构造 `WorkManagerWrapper(applicationContext)`（内部 `WorkManager.getInstance(context)`）——该步抛异常则注册整体失败、channel 永不绑定，Dart 侧只见 channel-error；GeneratedPluginRegistrant try/catch 吞掉只打 logcat。GeneratedPluginRegistrant.java:99 确认 workmanager 注册代码在（排除「依赖没装」）；manifest 无 WorkManagerInitializer 移除（排除 provider 冲突）。
- 与上游已知坑吻合：fluttercommunity/flutter_workmanager #656（2025-11 报、2026-08 closed）症状逐字相同（release 独有、debug 正常），maintainer 结论＝插件注册被干扰/陈旧构建/R8 keep，非 workmanager 本体。另 0.10.8/0.10.9 连发 Android 16 修复（expedited FGS 权限回收、one-off 卡 RUNNING），主人设备 HyperOS 安卓 16 相关嫌疑大。
- 影响范围：仅 15min 周期后台轮询 `hermes-bg-poll`（进程被杀/退后台后刷新活跃会话数的兜底）；前台常驻通知与 SSE 主链路（#73）不受影响。
- 取证（待主人手机连 adb，本机无 adb）：`adb logcat | grep -i "Error registering plugin"`——若见 `Error registering plugin workmanager_android, ...` → getInstance 抛异常实锤（顺栈定位）；若无 → 指向陈旧构建产物。
- 修复候选（按性价比）：① `flutter clean` + 重打 release 排除陈旧构建；② workmanager 升 0.10.10（0.10.9→10 为 patch 级）重验；③ 取证后再定 keep 规则/启动时序（可选：initialize 挪到 runApp 后并加一次延迟重试，当前冷启动即调可能与引擎 attach 竞态）。
- 验收：新 release 包诊断日志出现「后台保活服务初始化成功（WorkManager + ForegroundTask）」，且设置页能看到 `hermes-bg-poll` 周期任务在册；analyze 零告警 + test 全绿。
- 状态：待主人 adb 取证 + 决定修复路径（本条先记录，未开工）。

---

## #111 冷启动 GET /api/sessions 60s receiveTimeout 截断（服务端会话全量重建慢，客户端需超时保护）

- 现象：诊断日志同场——冷启动两路并发 GET `/api/sessions?sidebar_source=webui`，60.009s 后 dio `receiveTimeout` 截断报错；同时段 /api/reasoning 也要 9.5s（正常 <100ms），旁证服务端全进程被拖住。
- 位置：`lib/core/api/api_client.dart:63 defaultTimeout=60s`、`:140 receiveTimeout: defaultTimeout`（sessions/projects/models 全走主 dio）。
- 根因（服务端实证，fork 侧非本仓）：30002 会话库 `sessions/` 724 个 JSON/0.76GB（另 72 个 .bak，目录共 5GB）；缓存失效时 owner 请求同步等全量重建（api/routes.py:13021 路由 → :2639 `_get_cached_session_list_payload` → owner 分支 builder()），纯 JSON 解析本机实测 9.3s 起步，叠加 reconcile/CLI 合并/序列化/frp 出口（手机 4G→50001）即 60s+；ThreadingHTTPServer 下重建线程占 GIL 串行化全体请求。
- 客户端修复（本仓范围）：① `/api/sessions` 列表请求单独放宽 receiveTimeout（建议 120s，api_client 已有 `resolvedTimeout` 通道 :436/:514，按路径/调用点传入）；② 冷启动首屏失败静默退避重试一次（session_auto_refresh / 会话列表 provider 层，别红屏）；③ 可选：并发去重——冷启动多路并发 GET /api/sessions 合一。
- 服务端建议（转主人 fork 侧，另议）：90 天+ 会话归档拆分、清 .bak、重建分段让锁。
- 验收：release 冷启动弱网/4G 下会话列表不再出现 receiveTimeout 红色报错（首屏或宽限刷新成功）；新增/调整用例覆盖超时参数传递；analyze 零告警 + test 全绿。
- 状态：待开工（客户端小改，可与 #110 同批 release 验证）。

---
