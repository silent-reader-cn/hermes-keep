# AGENTS.md — hermes-ui 执行契约（编码规范）

> 本文档是**执行契约**：本仓库的代码/样式/测试/Git 硬规范，任何进本仓库写代码的人或代理必读。
> 并行子代理纪律（任务书 / 扇出 / 盯盘 / 复验 / 兜底后端）不在本文档，见 `HERMES.md` §6。
> 与代码风格冲突时以本文档为准；协作与方向见 `HERMES.md`（主人 ↔ 柚子），与本文档冲突时本文档的硬规则优先。

## 1. 项目简介

Hermes Agent 的**跨平台客户端**：Flutter + Cupertino 单代码库，Android + Windows 优先，后置 macOS / Linux / Web。目标是「一次开发、各处一致的 Hermes 体验」，不是蓝本的逐像素复刻。

- API 契约：对齐 `nesquena/hermes-webui` 的 HTTP / SSE / WS 接口（主人 fork 跑在 :30002，经 frp 暴露公网）；端点以本仓 `lib/core/api/endpoints.dart` 为准
- UI 蓝本（只读参考，不进仓库）：`.reference/hermex-src/`（即 uzairansaruzi/hermex 的 HermesMobile 目录）——**取交互与信息架构，不照搬 iOS 专属能力**
- 上游 hermes-webui：https://github.com/nesquena/hermes-webui
- 公开仓库与对外口径：https://github.com/silent-reader-cn/hermes-ui（`README.md` / `README.zh-CN.md`）
- 外壳与路由设计：`DESIGN.md`

## 2. 技术栈（锁死，不得私自更换）

| 领域 | 选型 | 说明 |
|---|---|---|
| 框架 | Flutter 3.x stable + Dart 3.x (`sdk: ^3.13.0`) | 六平台单代码库 |
| UI | **全部 Cupertino widgets** | CupertinoApp / CupertinoPageScaffold / ListSection / ListTile / NavigationBar / TextField / Switch / Slider / Picker / AlertDialog / SlidingSegmentedControl / ActivityIndicator；**业务 UI 禁 Material 组件**，例外清单见表注 ③ |
| 状态管理 | flutter_riverpod 2.6.x | Notifier / AsyncNotifier / Provider |
| 网络 | dio + 自封装 sse_client + web_socket_channel | HTTP / SSE 流式 / WS（Kanban） |
| 路由 | go_router 17.5.x | ShellRoute 单 Navigator，转场统一 `HermesPage`，外壳见 `DESIGN.md` |
| Markdown | flutter_markdown（**third_party vendored 补丁**）+ markdown + mermaid_flutter | 自定义渲染器、mermaid 图、选择上下文卡片 |
| 离线缓存 | drift 2.34.x + drift_flutter（`sqlite3` 在 dev_dependencies） | SQLite，会话只读缓存 |
| 安全存储 | flutter_secure_storage 11.x | API Key / 凭据，禁硬编码、禁进日志 |
| 本地持久化 | shared_preferences 2.5.x + path_provider | 轻量配置、窗口记忆等 |
| 桌面能力 | window_manager + tray_manager + hotkey_manager | 窗口记忆、系统托盘、全局快捷键 |
| 后台任务 | workmanager 0.10.x + flutter_foreground_task 8.x | Android 后台回合 worker + 前台服务保活 |
| 通知 | flutter_local_notifications 22.3.x | Android 后台回合通知 |
| 媒体/文件 | media_kit 1.2.x + media_kit_video 2.0.x + media_kit_libs_video + pdfrx 2.6.x + file_picker 12.x | 音视频 / PDF 预览、附件选择 |
| 剪贴板 | super_clipboard 0.1.x + pasteboard 0.5.x | 粘贴附件/文本（clipboard_paste） |
| 外链与意图 | url_launcher 6.x + android_intent_plus 5.x | 外部浏览器、APK 安装意图 |
| 自更新与打包 | package_info_plus + archive + xml + crypto | 版本检查、sidecar 打包产物处理（实现见 `core/update/`、`core/install/`） |
| 基础工具 | meta | 注解与不可变标注 |
| 图表 | fl_chart 1.2.x | Insights 统计 |
| 图标 | cupertino_icons | iOS 风格图标集 |
| Material 桥接 | material_ui 1.2.x | **仅供 Localizations delegate 桥接**，不作为业务组件来源 |
| 字体 | MiSans (Regular/Medium) | 见 §5 样式规范 |
| 测试 | flutter_test + mocktail + fake_async + golden_toolkit + flutter_driver + build_runner/drift_dev | 单元/widget/契约/金照/集成 |

> ① 版本号只示意「锁在哪个大版本」，逐条版本以 `pubspec.yaml` 为准，本文不再逐个维护。
> ② `third_party/flutter_markdown` 是 vendored + 打过补丁的分叉（修 link-wrapped 图片崩溃），经 `dependency_overrides` 生效，说明见该目录 `PATCH_NOTES.md`。第三方补丁一律放 `third_party/` 并在 `pubspec.yaml` 注明原因与移除条件。
> ③ **Material 例外清单**（业务 UI 一律 Cupertino，以下为既有例外，新增需写明理由）：`material_ui` 的 Localizations delegate 桥接（`app/app.dart`）、第三方 mermaid 渲染（`mermaid_flutter` 依赖 Material）、壳层初始化与系统主题监听（`main.dart` / `app/theme/theme_provider.dart`）。当前全仓 0 处 Material `Scaffold` / `MaterialApp`，37 处页面脚手架均为 `CupertinoPageScaffold`。
> ④ 新增依赖需对齐本表选型，不得私自引入 Material 体系或替代状态管理方案。

## 3. 目录与边界（约定）

> 逐文件明细**不再手抄**（手抄清单必漂：上一版写着 17 个 feature / ~80 测试文件，实盘已是 20 / 292）。实盘快照见 `docs/REPO_MAP.md`，`python tools/gen_repo_map.py` 重新生成；本节只钉约定与边界。

```
lib/
├── main.dart / driver_main.dart   # driver_main 供 flutter_driver 集成测试
├── l10n/                          # ARB（app_en.arb / app_zh.arb）+ app_localizations facade
├── app/                           # 外壳与主题：app / router / deep_link / shell / theme / widgets / locale
├── core/                          # 无 UI 的领域与基础设施
│   ├── api/                       # ApiClient + 域扩展 + endpoints / sse_client / ws_client
│   ├── models/                    # 手写 fromJson/toJson 容错模型
│   ├── cache/                     # drift 只读缓存
│   ├── connections/               # 多服务器连接与切换
│   ├── install/                   # 内置 WebUI 探测与安装
│   ├── update/                    # 应用自更新（版本检查 / APK 安装）
│   └── providers/  utils/
├── features/                      # 20 个 feature，各成目录（清单见 REPO_MAP.md）
test/                              # 镜像 lib/ + helpers/ + golden/ + fixtures/
third_party/flutter_markdown/      # vendored 补丁分叉（dependency_overrides）
tools/                             # fake_gateway（契约模拟）/ icon_pipeline / 维护脚本
docs/                              # specs/ + PROTOCOL_NOTES.md + REPO_MAP.md + screenshots/
```

**硬约定**：

- 新增 feature 必须在 `lib/features/<name>/` 自成目录，Provider 与页面同目录；跨 feature 复用进 `features/shared/`
- 第三方补丁一律放 `third_party/`，并在 `pubspec.yaml` 的 `dependency_overrides` 注明原因与移除条件（范例：`third_party/flutter_markdown`）
- 顶层页转场统一 `HermesPage`（`app/widgets/hermes_page_route.dart`），不要退回 go_router 默认转场
- 目录/规模类事实以 `docs/REPO_MAP.md` 为准；改结构后顺手重生成，别再往本文档抄清单

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
| 18 | **诊断** Diagnostics | 无独立路由，设置页进入 | `features/diagnostics/` | — | 请求/响应诊断抓取与详情 |
| 19 | **下载** Downloads | `/downloads` 进壳 | `features/downloads/` | — | 下载任务列表/确认框/落盘保存 |
| 20 | **内置服务** WebUI Sidecar | 无独立路由，设置区 + 托盘 + 引导页内置 tab | `features/webui_sidecar/` | — | Windows 内置 WebUI 启停/端口/凭据/状态 |

**外壳叫法定死：** `AdaptiveShell` 自适应外壳 / `SessionSidebar` 会话侧边栏 / `SidebarUtilityToolbar` 侧边栏工具条 / `SidebarResizeHandle` 拖拽手柄 / `EmptyDetailPane` 空态占位 / 断点 `kAdaptiveBreakpoint = 900`。
**禁止混叫：** 不说“首页/主页/列表页”混指会话列表；不说“文件/空间”混指工作区——`/workspace/:id` 叫**会话工作区**，`/workspaces` 叫**工作区管理**。

## 4. Dart 代码风格（强制）

- 文件：`snake_case.dart`；类/枚举：`PascalCase`；变量/函数：`camelCase`；常量：`lowerCamelCase`
- 每个文件一个主类型；import 顺序：`dart:` → `package:` → 相对路径，空行分隔
- 私有成员一律 `_` 前缀；公开 API 必须有 doc comment（`///`）
- `const` 能加就加；`final` 优先于 `var`
- **平台语义一律走注入接缝**：不得直接读 `Platform.isWindows` / `Platform.pathSeparator` / `File(x).parent` 做决策或拼路径——它们套用**宿主**规则，而宿主（CI = Linux）往往不是被测语义所在平台。决策读注入的 `isWindows`（`SidecarFileSystem.isWindows`、`InstallDetector.isWindows`、`DefaultSidecarFileSystem(customIsWindows:)`、`DefaultInstallDetector` 的 `FileSystemAdapter.isWindows`），路径拼接用 `lib/core/platform_paths.dart` 的 `platformPathSeparator` / `platformParentDir`；宿主平台只允许出现在「默认值来源」这一处
- 禁止 `dynamic` 滥用（JSON 解析边界除外）；禁止 `print()` 调试（用 `dart:developer log`）
- 字符串用单引号；格式化用 `dart format`（跟随 `flutter_lints` 默认，不自定义行宽）
- 错误处理：业务层抛自定义异常（继承 `ApiException`），UI 层 catch 展示；不吞异常
- 异步：优先 `async/await`，禁止裸 `Future` 忽略（加 `unawaited` 或注释说明）
- `analysis_options.yaml` 启用 `package:flutter_lints/flutter.yaml` + 项目追加规则，`flutter analyze` 必须零告警才算完成

lint 取舍**以 `analysis_options.yaml` 为准**（`include: package:flutter_lints/flutter.yaml` + 项目追加 + `analyzer.exclude` 排除 `build/**`、各平台壳目录、`.reference/**`）；本文档只记刻意偏离：

- 额外开启：`avoid_print` / `prefer_single_quotes` / `prefer_final_locals` / `prefer_const_constructors` / `always_declare_return_types` / `unawaited_futures` / `discarded_futures`
- 刻意放宽：`avoid_dynamic_calls: false`（JSON 容错解码是设计，不追求 strict 模式）
- `dart format` 目前**不是 CI 门禁**（CI 只跑 analyze + test）；格式化改动单独成 commit，别夹带无关重排

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
> **用法纪律**：动态色必须 `statusGreenText.resolveFrom(context)` 解析后再用，禁止直接塞进 `const TextStyle` 的 color——不解析时暗色下会退化成浅色变体，对比度不达标（`status_colors.dart` 顶部注释已写明）。`highContrast*` 变体由 `withBrightnessAndContrast` 自动覆盖，无需手写。

### 5.3 布局与外壳

- 自适应阈值：`kAdaptiveBreakpoint = 900.0`，`MediaQuery.sizeOf(context).width >= 900` 为宽屏（`DESIGN.md` §2，避开 Flutter 测试默认 800×600 视口）
- 宽屏：`AdaptiveShell` → 左 320px `SessionSidebar`（工具条 + 完整 `SessionListPage` + 1px separator）+ 右 `Expanded` 内容区；窄屏直接透传 `child`
- 路由进壳（`router.dart` 为准，`ShellRoute` 内）：`/`、`/chat`、`/chat/:sessionId`、`/settings`、`/tasks`、`/skills`、`/memory`、`/workspace/:sessionId`、`/workspaces`、`/kanban`、`/git/:sessionId`、`/insights`、`/downloads`；顶层独立不进壳：`/onboarding`、`/install-guide`（`DESIGN.md` §4）
- 品牌资产：`assets/branding/hermes-agent-icon-1024.png`、`tray_icon.ico` / `tray_icon_16.png` / `tray_icon_32.png`

### 5.4 无障碍与本地化

- 无障碍：`lib/core/utils/accessibility.dart` 提供 `AccessibleButton` 与 haptic helpers；逐步迁移既有图标按钮，需通过动态字号与对比度审计（`test/features/contrast_scan_test.dart`、`a11y_text_scale_test.dart`）
- 本地化：ARB 已落地（`lib/l10n/app_en.arb` / `app_zh.arb` + `app_localizations.dart` facade），`supportedLocales: en/zh` + Cupertino/Material/Widgets delegates 见 `lib/app/app.dart`；新增文案走 ARB，豁免范围见 `docs/specs/l10n-exemptions.md`；语言解析（自动/中文/English）在 `lib/app/locale/`

## 6. 模型与 API 约定（对齐 Hermex 容错策略）

- 所有模型手写 `fromJson` / `toJson`（**不用 json_serializable codegen**），保持可控容错
- 容错规则：未知字段忽略；字段缺失/类型不符时给**安全默认值**，绝不 crash；可空字段用 `?`
- 端点表以本仓 `lib/core/api/endpoints.dart` 为准（当前 125 个端点）；权威契约是 hermes-webui 的真实 HTTP / SSE / WS 行为，`.reference/hermex-src/Networking/Endpoints.swift` 仅作命名对照，冲突时以真实响应为准
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
C:/tmp/f.bat test --update-goldens   # 布局/样式变更后刷新金照（只写当前平台目录）
C:/tmp/f.bat build apk --debug
python tools/patch_android_gradle_namespace.py   # pub get 之后、build apk 之前（幂等）
python tools/fake_gateway/smoke_test.py
```

> Windows 宿主在 MSYS bash 下跑 flutter/dart 需走封装 bat `C:/tmp/f.bat`，避免 HOME/PATH 污染。详见 `windows-terminal` skill 的 `references/flutter-toolchain-msys-setup.md`。

> **APK 构建前必须补 Android namespace**：`super_clipboard` 家族（`irondash_engine_context` / `super_native_extensions`）已停维护且未声明 AGP 8+ 必需的 `namespace`，干净 pub-cache 会让 `flutter build apk` 在 Gradle 配置期直接失败。每次 `pub get` 后跑一次 `python tools/patch_android_gradle_namespace.py`（幂等，CI 的 android-debug 已内置该步）。详见脚本模块文档。
>
> **金照基线按平台分目录**：`test/golden/goldens/<windows|linux|macos>/`（逻辑见 `test/golden/golden_platform.dart`）。金照是**渲染环境**的产物——字体度量、CJK 字形回退随宿主平台变，故各平台只与自己那份比对；本平台**无基线时用例自动 skip**（记 `markTestSkipped`）而非失败，杜绝「拿 Windows 基线在 Linux 上比」的必然假红。补某平台基线：在该平台跑 `flutter test --update-goldens test/golden/` 后提交对应目录；CI 亦可 `workflow_dispatch` 选 `update_goldens=true` 生成并下载 artifact。金照字体源见 `golden_helpers.dart`（Windows 用系统 SimHei，其余平台退回仓库自带 MiSans）。

### 8.3 CI 流水线（`.github/workflows/ci.yml`）

| Job | runs-on | 触发 | 步骤 |
|---|---|---|---|
| analyze-test | ubuntu | push main / tag `v*` / PR / 手动 | checkout → flutter-action 3.47.0 stable → setup-java 17 → `flutter pub get` → `flutter analyze` → `flutter test`（`update_goldens=true` 时改跑 `--update-goldens test/golden/` 并上传基线 artifact；失败时上传 `test/golden/failures/` 诊断产物） |
| android-debug | ubuntu | **独立**（不 `needs: analyze-test`） | 同上 → `flutter build apk --debug` |
| fake-gateway | ubuntu | 独立 | checkout → setup-python 3.12 → `pip install -r tools/fake_gateway/requirements.txt` → `python tools/fake_gateway/smoke_test.py`（脚本按 `__file__` 解析 main.py，任意 cwd 可调用；子进程输出在失败时回显） |
| windows-installer | windows | **独立**，仅 main / tag / 手动 | Inno Setup（choco）→ `flutter build windows --release` → 组装 WebUI sidecar → 编译安装包 → 上传 `hermes-ui-windows-setup` 产物 |

> 两个建包 job **刻意不依赖** analyze-test：测试红不该连坐掉「包能不能构建」的验证（连坐期间 129 次 run 里它们从未真正执行过一次）。
> 合并到 main 前必须全绿（analyze-test / fake-gateway；android-debug 与 windows-installer 按上表触发条件）；新增端点/模型需同步更新 `tools/fake_gateway` 契约。CI 带 `concurrency`，同 ref 的旧跑会被取消。

### 8.4 完成标准

完成标准见 §11 完成定义（DoD），本节不重复。

## 9. Git 规范

- 分支：`feat/<模块>` 或 `agy/<任务>`；提交信息：`<type>(<scope>): <subject>`（type: feat/fix/refactor/test/docs/chore）
- 提交前 `git status` 确认只 add 相关文件；禁止 `git add -A` 混入无关文件
- 合并到 main 前必须：analyze 通过 + 测试通过 + 无 TODO 遗留（有意遗留的 TODO 要标注负责人）
- 任务前先 commit 当前进度；并行子代理禁止自行 commit，由 Leader 统一提交（并行纪律见 `HERMES.md` §6）

## 10. 参考优先级

1. 本 AGENTS.md（强制规范，最高优先）
2. `lib/core/api/endpoints.dart` + `docs/PROTOCOL_NOTES.md` + hermes-webui 真实响应（**能力与行为的权威来源**）
3. `.reference/hermex-src/`（UI 与交互蓝本：取信息架构与手感，不照搬 iOS 专属能力，也不照搬其业务定义）
4. Flutter / Riverpod 官方文档

> 旧口径「如与 Hermex 行为冲突则以 Hermex 为准（它是产品定义）」已作废：Hermex 是蓝本参考实现，产品能力以 Hermes 官方与本仓对外定位为准。

## 11. 完成定义（DoD）

- [ ] `C:/tmp/f.bat analyze` 零告警
- [ ] `C:/tmp/f.bat test` 全绿（新增代码有测试）
- [ ] 无 Material 组件混入业务 UI（既有例外见 §2 表注 ③）
- [ ] 行为与 `docs/PROTOCOL_NOTES.md` / hermes-webui 真实响应一致；UI 对齐蓝本交互
- [ ] 提交信息规范、分支正确
- [ ] CI 全绿（analyze-test / android-debug / fake-gateway / windows-installer，后者按 §8.3 触发条件）

## 12. 索引（去哪看）

- 协作与方向：`HERMES.md`（主人 ↔ 柚子）
- 并行执行规范（任务书 / worktree 扇出 / 复验清单）：`HERMES.md` §6
- 外壳与路由设计：`DESIGN.md`
- 规格与协议：`docs/specs/` + `docs/PROTOCOL_NOTES.md`
- 目录明细（自动生成，勿手改）：`docs/REPO_MAP.md`（`python tools/gen_repo_map.py`）
- 对外发布口径：`README.md` / `README.zh-CN.md` / `CHANGELOG.md` / `THIRD-PARTY-NOTICES.md`
- 流水线：`.github/workflows/ci.yml`（四 job）
