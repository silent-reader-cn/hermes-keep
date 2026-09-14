# AGENTS.md — hermes-ui 执行契约（编码规范）

> 本文档是**执行契约**：本仓库的代码/样式/测试/Git 硬规范，任何进本仓库写代码的人或代理必读。
> 并行子代理纪律（任务书 / 扇出 / 盯盘 / 复验 / 兜底后端）不在本文档，见 `HERMES.md` §6。
> 与代码风格冲突时以本文档为准；协作与方向见 `HERMES.md`（主人 ↔ 柚子），与本文档冲突时本文档的硬规则优先。
> 历史说明：曾因 Hermes 对 `AGENTS.md` 文件名的审批机制在 QQ 渠道不可用而以 `AGENT_.md` 落盘，现已正名。

## 1. 项目简介

将 Hermex（iOS 原生 SwiftUI，MIT 开源）移植为 Flutter + Cupertino 的全平台客户端。
API 契约对齐 nesquena/hermes-webui（主人 fork 跑在 :30002，经 frp 暴露公网）。

- 蓝本源码（只读参考，不进仓库）：`.reference/hermex-src/`（即 uzairansaruzi/hermex 的 HermesMobile 目录）
- 上游 hermes-webui：https://github.com/nesquena/hermes-webui
- 优先平台：Android + Windows；后置：macOS / Linux / Web
- 公开仓库：https://github.com/silent-reader-cn/hermes-ui

## 2. 技术栈（锁死，不得私自更换）

| 领域 | 选型 | 说明 |
|---|---|---|
| 框架 | Flutter 3.x stable + Dart 3.x (`sdk: ^3.13.0`) | 六平台单代码库 |
| UI | **全部 Cupertino widgets** | CupertinoApp / PageScaffold / ListSection / ListTile / NavigationBar / TextField / Switch / Slider / Picker / AlertDialog / SlidingSegmentedControl / ActivityIndicator；**禁止 Material widgets 混入业务 UI**（仅 App 壳桥接层例外） |
| 状态管理 | flutter_riverpod 2.6.x | Notifier / AsyncNotifier / Provider |
| 网络 | dio + 自封装 sse_client + web_socket_channel | HTTP / SSE 流式 / WS（Kanban） |
| 路由 | go_router 17.5.x | ShellRoute 单 Navigator，外壳见 `DESIGN.md` |
| Markdown | flutter_markdown 0.7.x | 自定义渲染器 |
| 离线缓存 | drift 2.34.x + drift_flutter + sqlite3 | SQLite，会话只读缓存 |
| 安全存储 | flutter_secure_storage 11.x | API Key / 凭据，禁硬编码、禁进日志 |
| 本地持久化 | shared_preferences 2.5.x + path_provider | 轻量配置、窗口记忆等 |
| 桌面能力 | window_manager + tray_manager + hotkey_manager | 窗口记忆、系统托盘、全局快捷键 |
| 通知 | flutter_local_notifications 22.3.x | Android 后台回合通知 |
| 媒体/文件 | media_kit 1.2.x + media_kit_video 2.0.x + media_kit_libs_video + file_picker 12.x | 音视频预览、附件选择 |
| 剪贴板 | super_clipboard 0.1.x | 粘贴附件/文本（clipboard_paste） |
| 图表 | fl_chart 1.2.x | Insights 统计 |
| 字体 | MiSans (Regular/Medium) | 见 §5 样式规范 |
| 测试 | flutter_test + mocktail + fake_async + golden_toolkit + build_runner/drift_dev | 单元/widget/契约/金照 |

> 完整依赖以 `pubspec.yaml` 为准；新增依赖需对齐本表选型，不得私自引入 Material 体系或替代状态管理方案。

## 3. 目录结构（以实盘为准，2026-08-24 快照）

```
lib/
├── main.dart / driver_main.dart
├── l10n/app_localizations.dart
├── app/
│   ├── app.dart / router.dart / deep_link.dart
│   ├── shell/                      # 自适应双栏外壳（DESIGN.md）
│   │   ├── adaptive_shell.dart
│   │   ├── session_sidebar.dart
│   │   ├── sidebar_utility_toolbar.dart
│   │   ├── sidebar_resize_handle.dart
│   │   └── empty_detail_pane.dart
│   ├── theme/
│   │   ├── cupertino_theme.dart
│   │   ├── status_colors.dart
│   │   └── theme_provider.dart
│   └── widgets/                    # 通用 Cupertino 弹层/菜单/导航
│       ├── adaptive_action_menu.dart
│       ├── adaptive_popover.dart
│       ├── adaptive_sliver_navigation_bar.dart
│       ├── cupertino_popover.dart
│       ├── narrow_navigation_dropdown.dart
│       └── popover_dropdown.dart
├── core/
│   ├── api/                        # ApiClient + 12 域扩展 + 基础设施
│   │   ├── api_client.dart + api_client_chat/cron/extensions/git/kanban/mcp/memory_skills/prompts/server_panels/sessions/upload/workspace.dart
│   │   ├── api_exception.dart / cookie_store.dart / custom_header.dart
│   │   └── endpoints.dart / sse_client.dart / ws_client.dart
│   ├── models/                     # 28 数据模型（手写 fromJson/toJson 容错）
│   │   └── approval/auxiliary_model/chat_message/clarification/context_window_snapshot/cron/extensions/git_workspace/goal/insights/json_value/kanban/mcp/memory/message_attachment/model_favorite/saved_prompt/server_account/server_catalog/server_info/session/skills/slash_skill_formatter/tool_call/transcribe_response/turn_file_change/upload_response/workspace.dart
│   ├── cache/                      # drift 数据库（app_database*.dart + cache_service/media_cache_service/cache_providers）
│   ├── connections/                # 多服务器连接与切换（server_connection/connection_store/connection_providers）
│   ├── providers/                  # 跨域 provider（file_picker_provider/clipboard_paste_provider）
│   └── utils/                      # 工具（accessibility/lossy_json/equality/uuid/selected_context/injected_message/context_window_formatter/clipboard_paste/file_picker/attachment_audio_detection）
└── features/                       # 17 个 feature，各成目录，Provider 与页面同目录；跨 feature 复用进 shared/
    ├── onboarding/       # 引导页/连接向导（/onboarding 独立全屏）
    ├── session_list/     # 会话列表（/，8 文件：page/header/utility_rows/disclosure/entry_visibility/subtitle_settings/auto_refresh/providers）
    ├── chat/             # 聊天（/chat*，23 文件：page/controller/state/models/providers/server_api/selection_provider + widgets/*）
    ├── tasks/            # 定时任务（/tasks）
    ├── skills/           # 技能（/skills）
    ├── memory/           # 记忆（/memory）
    ├── workspace/        # 会话工作区（/workspace/:sessionId，单会话文件）
    ├── workspace_manager/# 工作区管理（/workspaces，注册表级 5 文件：page/api/providers/add_sheet/preview）
    ├── kanban/           # 看板（/kanban）
    ├── insights/         # 洞察/用量（/insights）
    ├── settings/         # 设置（/settings，10 文件：page/providers/subpages + 6 子区 profile/extensions/mcp/auxiliary_models/cron_visibility/injected_notice/tool_group）
    ├── git/              # Git 面板（/git/:sessionId，4 文件：page/api/providers/branch_tree）
    ├── prompts/          # 提示词库（无独立路由，Chat 输入栏 Sheet）
    ├── projects/         # 项目（无独立路由，列表顶部 Picker Sheet）
    ├── notifications/    # 通知（无路由，后台服务 3 文件）
    ├── desktop/          # 桌面能力（无路由，6 文件：window_memory/title/tray/shortcuts/lifecycle/settings）
    └── shared/           # 共享组件（app_back_button 等跨 feature 复用）

test/                               # 镜像 lib/ 结构（~80+ 文件：app/* + core/api+cache+connections+models+utils + features/*）
assets/
├── branding/                       # hermes-agent-icon-1024.png + tray_icon.ico / tray_icon_16.png / tray_icon_32.png
└── fonts/  MiSans-Regular.ttf / MiSans-Medium.ttf (+ LICENSE/OFL.txt)
tools/
├── fake_gateway/  main.py + smoke_test.py + requirements.txt  # 契约模拟服务器
└── icon_pipeline/ generate_icons.py
docs/
├── PROTOCOL_NOTES.md               # SSE/WS 协议笔记
├── QA.md / RELEASE.md / auto_reauth_spec.md / cache_audit_report.md / PLAN-session-gaps-phase2-2026-08.md
└── specs/  11 规格 + 1 目录：agent-injected-message-cards/api_spec/app_shell_spec/backend-api-catalog(+backend-api-details/)/chat_spec/models_spec/saved-prompts/selected-context/session-auto-refresh/settings-extensions-mcp-aux/workspace_manager_spec
.reference/hermex-src/              # 蓝本只读参考，不进仓库（HermesMobile: Features 12 / Models 23 / Networking 22 + Config/Auth/...）
```

> 新增 feature 必须在 `lib/features/<name>/` 下自成目录，Provider 与页面同目录；跨 feature 复用进 `features/shared/`。

### 3.1 统一叫法表（界面/功能 ↔ 路由 ↔ 目录 ↔ 蓝本对照）

> 日常叫法统一用「中文名」，代码/路由/目录用「英文名」。窄屏/宽屏、外壳组件亦定死，避免「首页/列表页/文件/空间」混叫。

| # | 统一叫法 | 路由 | Flutter 目录 | Hermex 蓝本 `Features/*` | 职责一句话 |
|---|---|---|---|---|---|
| 1 | **引导页/连接向导** Onboarding | `/onboarding` 独立全屏不进壳 | `features/onboarding/` | `Onboarding` | 填 baseUrl、登录、自定义 Header、保存并激活连接 |
| 2 | **会话列表** Session List | `/` 进壳，宽屏左栏常驻 | `features/session_list/` | `SessionList` | 搜索/筛选/分页/置顶/归档/删除/分支/批量操作、项目过滤入口 |
| 3 | **聊天** Chat | `/chat`、`/chat/:sessionId?q=&match=` | `features/chat/` + `widgets/` | `Chat` | SSE 流式消息、审批/澄清/工具调用、上下文圆环、媒体气泡、深链高亮定位 |
| 4 | **定时任务** Tasks | `/tasks` | `features/tasks/` | `Tasks` | Cron 列表/创建/启停/删除 |
| 5 | **技能** Skills | `/skills` | `features/skills/` | `Skills` | Slash Skills 管理 |
| 6 | **记忆** Memory | `/memory` | `features/memory/` | `Memory` | 记忆条目 CRUD |
| 7 | **会话工作区** Workspace | `/workspace/:sessionId` | `features/workspace/` | `Workspace` | 单会话文件浏览/上传/预览 |
| 8 | **工作区管理** Workspace Manager | `/workspaces` | `features/workspace_manager/` | `Workspace` 拆出 | 注册表级多工作区管理 + 文件预览页 |
| 9 | **看板** Kanban | `/kanban` | `features/kanban/` | `Kanban` | WS 事件流看板 |
| 10 | **洞察/用量** Insights | `/insights` | `features/insights/` | `Insights` | fl_chart 用量统计 |
| 11 | **设置** Settings | `/settings` | `features/settings/` | `Settings` | 档案/模型/扩展/MCP/辅助模型/注入提示等 6 子区 |
| 12 | **Git 面板** Git | `/git/:sessionId` | `features/git/` | `Workspace` 内嵌 | 分支树/状态 |
| 13 | **提示词库** Saved Prompts | 无独立路由，Chat 输入栏 Sheet | `features/prompts/` | Chat 内 | 收藏提示词 |
| 14 | **项目** Projects | 无独立路由，列表顶部 Picker Sheet | `features/projects/` | SessionList 关联 | 项目筛选/切换 |
| 15 | **通知** Notifications | 无路由，后台服务 | `features/notifications/` | `LiveActivities` 对位 | Android 后台回合完成通知 |
| 16 | **桌面能力** Desktop | 无路由 | `features/desktop/` | — | window_manager / tray_manager / hotkey_manager |
| 17 | **共享组件** Shared | — | `features/shared/` | `Shared` | 跨 feature 复用（AppBackButton 等） |

**外壳叫法定死：** `AdaptiveShell` 自适应外壳 / `SessionSidebar` 会话侧边栏 / `SidebarUtilityToolbar` 侧边栏工具条 / `SidebarResizeHandle` 拖拽手柄 / `EmptyDetailPane` 空态占位 / 断点 `kAdaptiveBreakpoint = 900`。
**禁止混叫：** 不说“首页/主页/列表页”混指会话列表；不说“文件/空间”混指工作区——`/workspace/:id` 叫**会话工作区**，`/workspaces` 叫**工作区管理**。

## 4. Dart 代码风格（强制）

- 文件：`snake_case.dart`；类/枚举：`PascalCase`；变量/函数：`camelCase`；常量：`lowerCamelCase`
- 每个文件一个主类型；import 顺序：`dart:` → `package:` → 相对路径，空行分隔
- 私有成员一律 `_` 前缀；公开 API 必须有 doc comment（`///`）
- `const` 能加就加；`final` 优先于 `var`
- 禁止 `dynamic` 滥用（JSON 解析边界除外）；禁止 `print()` 调试（用 `dart:developer log`）
- 字符串用单引号；格式化用 `dart format`（跟随 `flutter_lints` 默认，不自定义行宽）
- 错误处理：业务层抛自定义异常（继承 `ApiException`），UI 层 catch 展示；不吞异常
- 异步：优先 `async/await`，禁止裸 `Future` 忽略（加 `unawaited` 或注释说明）
- `analysis_options.yaml` 启用 `package:flutter_lints/flutter.yaml` + 项目追加规则，`flutter analyze` 必须零告警才算完成

当前追加 lint（`analysis_options.yaml`）：

```yaml
avoid_print: true
prefer_single_quotes: true
prefer_final_locals: true
prefer_const_constructors: true
always_declare_return_types: true
unawaited_futures: true
discarded_futures: true
avoid_dynamic_calls: false  # 容错解码刻意放宽
```

## 5. 样式规范（Cupertino 主题与设计令牌）

### 5.1 主题

- 定义位置：`lib/app/theme/cupertino_theme.dart` → `buildCupertinoTheme(Brightness)`
- 主色：`Color(0xFF007AFF)`（Hermex iOS 蓝）
- 背景：浅色 `CupertinoColors.systemGroupedBackground`，深色 `Color(0xFF000000)` 纯黑；`barBackgroundColor` 跟随 scaffold（不透明，避免毛玻璃过渡）
- 全局字体：`kAppFontFamily = 'MiSans'`（`assets/fonts/MiSans-Regular.ttf` 400 / `MiSans-Medium.ttf` 500/600/700），`pubspec.yaml` 已注册
- `CupertinoTextThemeData` 显式绑定 `fontFamily` 与 `color: CupertinoColors.label`，覆盖 17pt 正文、10pt tabLabel、17pt navTitle(600)、34pt largeTitle(bold)、21pt picker 等

### 5.2 状态色（WCAG AA ≥4.5:1）

定义位置：`lib/app/theme/status_colors.dart`，全部为 `CupertinoDynamicColor.withBrightnessAndContrast`：

| 令牌 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| statusGreenText | #1E7A34 | #34C759 | 运行中/成功 |
| statusOrangeText | #B25000 | #FF9500 | 暂停/警告 |
| statusBlueText | #005FB8 | #0A84FF | 进行中/主色 |
| statusGreyText | #595959 | #8E8E93 | 关闭/离线 |
| statusTealText | #0E7C86 | #30B0C7 | 就绪 |
| statusRedText | #B3001B | #FF453A | 错误/失败详情（替代 systemRed 浅色对比不足） |
| secondaryText | #3C3C43/60% | #EBEBF5/72% | 副标/次要信息（浅 ~4.5:1，深 ~8.9:1） |

> 禁止直接用 `systemGreen/systemOrange/systemRed` 作文字色（浅底对比 ~2.0-3.4:1 不达标）；装饰圆点/图标可例外。

### 5.3 布局与外壳

- 自适应阈值：`kAdaptiveBreakpoint = 900.0`，`MediaQuery.sizeOf(context).width >= 900` 为宽屏（`DESIGN.md` §2，避开 Flutter 测试默认 800×600 视口）
- 宽屏：`AdaptiveShell` → 左 320px `SessionSidebar`（工具条 + 完整 `SessionListPage` + 1px separator）+ 右 `Expanded` 内容区；窄屏直接透传 `child`
- 路由进壳（`router.dart` 为准，`ShellRoute` 内）：`/`、`/chat`、`/chat/:sessionId`、`/settings`、`/tasks`、`/skills`、`/memory`、`/workspace/:sessionId`、`/workspaces`、`/kanban`、`/git/:sessionId`、`/insights`；`/onboarding` 顶层独立不进壳（`DESIGN.md` §4）
- 品牌资产：`assets/branding/hermes-agent-icon-1024.png`、`tray_icon.ico` / `tray_icon_16.png` / `tray_icon_32.png`

### 5.4 无障碍与本地化

- 无障碍：`lib/core/utils/accessibility.dart` 提供 `AccessibleButton` 与 haptic helpers；逐步迁移既有图标按钮，需通过动态字号与对比度审计（`test/features/contrast_scan_test.dart`、`a11y_text_scale_test.dart`）
- 本地化：`supportedLocales: en/zh` + Cupertino/Material/Widgets delegates + `AppLocalizationsDelegate`（`lib/app/app.dart`、`lib/l10n/`）；业务文案逐步 ARB 抽离，现阶段中英 facade 已可用

## 6. 模型与 API 约定（对齐 Hermex 容错策略）

- 所有模型手写 `fromJson` / `toJson`（**不用 json_serializable codegen**），保持可控容错
- 容错规则：未知字段忽略；字段缺失/类型不符时给**安全默认值**，绝不 crash；可空字段用 `?`
- `endpoints.dart` 端点表必须与 `.reference/hermex-src/Networking/Endpoints.swift` 一一对应（约 150 端点）
- 响应形状以真实服务器为准；改动前先跑 `tools/fake_gateway` 契约测试（`smoke_test.py`）
- API Key 存 flutter_secure_storage，禁止硬编码、禁止进日志
- SSE 事件映射以 `docs/PROTOCOL_NOTES.md` 为准（token/interim_assistant/reasoning/tool/title/metering/done/initial/approval/clarify 等全量对照）

## 7. Riverpod 约定

- 业务状态用 `Notifier`/`AsyncNotifier` + `NotifierProvider`；派生状态用 `Provider`/`FutureProvider`
- Provider 文件与页面同目录（如 `features/chat/chat_providers.dart`）
- 所有 Provider 命名后缀 `Provider`；Notifier 类名后缀 `Controller`
- 页面组件（Widget）不直接持有网络逻辑，一律走 Provider

## 8. 测试要求与流水线（必写）

### 8.1 测试要求

- 每个模型：JSON 解析单测（含**畸形输入**容错用例）
- 每个 Controller：核心状态机单测（流式追加、错误恢复、重连）
- ApiClient 方法：用 mock（mocktail）测请求路径/参数/解析
- 页面：关键交互 widget 测试（会话列表、聊天发送、设置表单）
- 对比度/无障碍：`contrast_scan_test`、`a11y_text_scale` 等专项

### 8.2 本地流水线

```bash
C:/tmp/f.bat analyze          # 零告警（含 info）
C:/tmp/f.bat test             # 全绿
C:/tmp/f.bat test --update-goldens   # 布局/样式变更后刷新金照
C:/tmp/f.bat build apk --debug
python tools/fake_gateway/smoke_test.py
```

> Windows 宿主在 MSYS bash 下跑 flutter/dart 需走封装 bat `C:/tmp/f.bat`，避免 HOME/PATH 污染。详见 `windows-terminal` skill 的 `references/flutter-toolchain-msys-setup.md`。

### 8.3 CI 流水线（`.github/workflows/ci.yml`）

| Job | 触发 | 步骤 |
|---|---|---|
| analyze-test | push main / PR | checkout → flutter-action 3.47.0 stable → setup-java 17 → `flutter pub get` → `flutter analyze` → `flutter test` |
| android-debug | 依赖 analyze-test | 同上 → `flutter build apk --debug` |
| fake-gateway | 独立 | checkout → setup-python 3.12 → `pip install -r tools/fake_gateway/requirements.txt` → `python tools/fake_gateway/smoke_test.py` |

> 合并到 main 前必须三 job 全绿；新增端点/模型需同步更新 `tools/fake_gateway` 契约。

### 8.4 完成标准

`flutter test` 全绿 + `flutter analyze` 零告警 + 无 Material 混入 + 与 Hermex 对应功能行为一致 = 完成。

## 9. Git 规范

- 分支：`feat/<模块>` 或 `agy/<任务>`；提交信息：`<type>(<scope>): <subject>`（type: feat/fix/refactor/test/docs/chore）
- 提交前 `git status` 确认只 add 相关文件；禁止 `git add -A` 混入无关文件
- 合并到 main 前必须：analyze 通过 + 测试通过 + 无 TODO 遗留（有意遗留的 TODO 要标注负责人）
- 任务前先 commit 当前进度；并行子代理禁止自行 commit，由 Leader 统一提交（并行纪律见 `HERMES.md` §6）

## 10. 参考优先级

1. 本 AGENTS.md（强制规范，最高优先）
2. `.reference/hermex-src/`（蓝本实现，翻译而非发明）
3. Flutter / Riverpod 官方文档
4. 如与 Hermex 行为冲突：以 Hermex 行为为准（它是产品定义）

## 11. 完成定义（DoD）

- [ ] `C:/tmp/f.bat analyze` 零告警
- [ ] `C:/tmp/f.bat test` 全绿（新增代码有测试）
- [ ] 无 Material 组件混入业务 UI
- [ ] 与 Hermex 对应功能行为一致（对照 `.reference/hermex-src`）
- [ ] 提交信息规范、分支正确
- [ ] CI 三 job 全绿（analyze-test / android-debug / fake-gateway）

## 12. 索引（去哪看）

- 协作与方向：`HERMES.md`（主人 ↔ 柚子）
- 并行执行规范（任务书 / worktree 扇出 / 复验清单）：`HERMES.md` §6
- 外壳：`DESIGN.md`
- 规格：`docs/specs/` + `docs/PROTOCOL_NOTES.md`
- 流水线：`.github/workflows/ci.yml`
