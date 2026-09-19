# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式，
版本号遵循 [SemVer](https://semver.org/lang/zh-CN/)。

## [Unreleased]

> 逐版变更明细以 [GitHub Releases](https://github.com/silent-reader-cn/hermes-keep/releases) 的 Release notes 为准（每个 tag 一份）；
> 本文件自 `0.1.0` 起未逐版维护，只保留里程碑与当前进行中的事项。

### 仓库与口径

- 仓库更名为 `hermes-keep`（原 `hermes-ui`）。旧链接由 GitHub 自动重定向，**已发布版本的应用内检查更新不受影响**（实测旧 API 端点 301 → 正确返回最新 Release）
- README：Android 下载资产名与实物对齐（`app-release.apk`，原误写 `*-arm64.apk`）；新增「为什么选它 / Why this one」定位段
- README：测试规模口径更新为实测值（原写 2,400+，现 4,800+）
- `pubspec.yaml`：补齐 `description`（原为 Flutter 模板默认值 `A new Flutter project.`）
- `.gitignore`：忽略 `key.properties`，避免签名口令误入公开仓库

## [0.1.0] - 2026-08-17

### 里程碑

Phase 1-6 全功能完成 + Android 后台回合完成通知。
**722 个测试全绿（60 个文件）、`flutter analyze` 零告警、Android debug APK 可构建。**

### 新增

**核心基建（Phase 1）**

- `core/models/`：24 个数据模型文件，手写 `fromJson` 容错解码（对齐 Hermex tolerant 策略，畸形输入绝不 crash）
- `core/api/`：dio 封装 + 认证头 + 10 个域扩展（server/sessions/chat/cron/git/kanban/memory_skills/server_panels/workspace/upload）+ endpoints 端点表
- SSE 客户端（心跳、断线重连、消息顺序）+ WebSocket 客户端（Kanban 事件流）
- 异常体系（ApiException 及子类，超限/网络/认证等语义化错误）

**App 壳与连接管理（Phase 2）**

- CupertinoApp 壳：深浅色主题三态（跟随系统/浅色/深色）、go_router 路由表、中英本地化
- 多服务器连接管理：增删改切换、凭据存 flutter_secure_storage、自定义 Header、用户名/密码
- Onboarding 三步向导（未配置服务器时自动重定向）

**会话与聊天（Phase 3）**

- 会话列表：防抖远程搜索、无限滚动分页、分区（置顶/今天/昨天/更早）、pin/archive/branch/delete、新建会话
- 聊天核心：SSE 流式渲染、9 态聊天状态机、思考/工具调用卡片（错误/警告态）、Markdown + 代码块、流式期间 steer / 停止、模型选择器

**任务/技能/记忆/设置（Phase 4）**

- 任务（Cron）：列表、创建/编辑/启停/删除、手动触发、输出查看、状态徽标
- 技能浏览（搜索/分类/详情）、记忆只读浏览（4 分区）
- 设置页四分组：外观/服务器/模型（默认模型 + 推理强度）/关于

**工作区/Git/看板/统计（Phase 5）**

- 工作区文件树浏览、下载、上传入口（file picker 平台通道后置）、删除/重命名（服务端 501 占位）
- Git 面板：分支切换、status/diff/commit/fetch/pull/push
- Kanban 看板浏览与卡片操作（WS 事件流）
- Insights 统计：指标卡片、fl_chart 柱状图、模型拆分、峰值活动
- 跨天测试修复（时间相关用例）

**Android 通知（Phase 6）**

- 回合完成后台系统通知：前台不发/后台发、点击回跳对应会话、回前台自动清除、预览单行化截断（120 字符）、固定通知 ID 防堆积
- Android 13+ POST_NOTIFICATIONS 权限适配、通知失败绝不影响聊天主流程
- 通知行为对齐 hermes-android v2.0.1 的 Background turn notifications 思路

### 开发阶段记录（v0.1.0 之前，合并）

- 2026-08-16：工具链就绪（Flutter 3.47.0 / JDK 17 / Android SDK 36）；脚手架 + 依赖 + lint 入仓
- 2026-08-16：预研规格 4 份验收通过（models_spec 145 模型 / api_spec 123 端点 / chat_spec 9 态状态机 / app_shell_spec）
- 2026-08-16 ~ 08-17：Phase 1 → Phase 6 分批提交（394 → 423 → 494 → 583 → 696 → 722 测试），详见 git 历史
