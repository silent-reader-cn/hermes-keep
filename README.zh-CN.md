<div align="center">

# Hermes UI

**多平台统一、流畅的 Hermes 体验。**

基于 Flutter + Cupertino 的 [Hermes Agent](https://hermes-agent.nousresearch.com/docs) 客户端——一套代码，桌面与手机体验一致。

[![CI](https://github.com/silent-reader-cn/hermes-ui/actions/workflows/ci.yml/badge.svg)](https://github.com/silent-reader-cn/hermes-ui/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/silent-reader-cn/hermes-ui)](https://github.com/silent-reader-cn/hermes-ui/releases)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android-lightgrey)

[English](README.md) | **简体中文**

</div>

---

## 截图

暗色与浅色主题并排呈现；同一套演示数据由工装双份生成（`README_SHOTS=1`、`README_DARK=1`）。

<div align="center">

### Windows 桌面 —— 流式聊天（暗色）

<img src="docs/screenshots/wide-chat-dark.png" width="86%" alt="Hermes UI Windows 桌面暗色：左会话列表 + 右流式聊天双栏"/>

| 会话列表 | 看板 | 用量统计 |
|---|---|---|
| <img src="docs/screenshots/wide-sessions-dark.png" width="280" alt="暗色会话列表"/> | <img src="docs/screenshots/wide-kanban-dark.png" width="280" alt="暗色看板"/> | <img src="docs/screenshots/wide-insights-dark.png" width="280" alt="暗色用量统计"/> |

### 浅色主题

| 聊天 | 会话列表 | 看板 |
|---|---|---|
| <img src="docs/screenshots/wide-chat.png" width="280" alt="浅色聊天页"/> | <img src="docs/screenshots/wide-sessions.png" width="280" alt="浅色会话列表"/> | <img src="docs/screenshots/wide-kanban.png" width="280" alt="浅色看板"/> |

### Android 手机（暗色）

| 聊天 | 会话列表 | 用量统计 |
|---|---|---|
| <img src="docs/screenshots/phone-chat-dark.png" width="180" alt="安卓聊天页"/> | <img src="docs/screenshots/phone-sessions-dark.png" width="180" alt="安卓会话列表"/> | <img src="docs/screenshots/phone-insights-dark.png" width="180" alt="安卓用量统计"/> |

</div>

> 全部截图由 App 自身的 golden 截图工装生成（`test/screenshots/`，演示数据），与每次发布逐像素一致。

## 功能亮点

- **内置 WebUI Sidecar（Windows）** —— 安装包自带完整 WebUI 后端与嵌入式 Python 3.11 运行时：无需预装 Python、Git 或任何编译环境，一键启动并连接（Clash Verge 式体验）。
- **智能解释器复用** —— 启动时自动检测本机已有的 Hermes Agent 安装，优先借用其虚拟环境（自带全套 Agent 依赖，开箱即可聊天）；未检测到时回退到内置嵌入式 Python，仍可浏览只读会话历史。
- **流式聊天** —— SSE 流式渲染、Markdown + 代码块、思考与工具调用卡片、回合中途 steer / 停止、模型选择器、会话级草稿。
- **会话管理** —— 防抖搜索、置顶 / 归档 / 分支 / 删除、分区列表（置顶 / 今天 / 更早）、离线缓存。
- **任务（Cron）** —— 创建 / 编辑 / 启停 / 手动触发 / 查看输出，运行状态徽标。
- **技能与记忆** —— 技能浏览与筛选；记忆面板支持编辑与写回。
- **工作区与 Git** —— 工作区文件浏览 / 上传 / 下载；分支切换、status、diff、提交、fetch / pull / push。
- **看板（Kanban）** —— 看板与卡片跨列长按拖拽。
- **统计（Insights）** —— 会话 / 消息 / 令牌 / 费用指标、模型拆分、近 14 天令牌图表。
- **通知** —— Android 后台回合完成通知，点击直达对应会话。
- **桌面体验** —— 托盘图标、全局快捷键、窗口状态记忆、开机自启（Windows）。
- **多语言** —— English / 简体中文 / 跟随系统。

## 安装

### Windows

1. 从 [Releases](https://github.com/silent-reader-cn/hermes-ui/releases) 页面下载最新安装包（`*.exe`）并运行。
2. 启动 **Hermes UI**，在引导页选择 **内置服务** → **启动并连接**，完成——WebUI 后端自动拉起。

聊天功能需要本机安装 [Hermes Agent](https://hermes-agent.nousresearch.com/docs)。未检测到时引导页会出现提示卡并附安装指南链接；此时 App 仍可用（会话历史只读），尝试聊天会明确提示缺少的内容。

### Android

从 [Releases](https://github.com/silent-reader-cn/hermes-ui/releases) 页面下载 `*-arm64.apk`（Android 7.0+），连接局域网内或经隧道暴露的 Hermes 服务器即可。

### 从源码构建

```bash
git clone https://github.com/silent-reader-cn/hermes-ui.git
cd hermes-ui
flutter pub get

# Windows 桌面
flutter run -d windows

# Android 真机 / 模拟器
flutter run -d <device-id>
```

环境要求：Flutter 3.47+（stable）；Android 构建需 JDK 17 + Android SDK 36；Windows 构建需 Visual Studio Build Tools 2022（含 C++ 桌面工作负载）。

## 连接服务器

两种连接模式，在引导页或「设置 → 服务器」中配置：

| 模式 | 适用场景 | 所需信息 |
|---|---|---|
| **内置服务**（Windows） | App 与 Hermes 装在同一台机器 | 无需任何输入——自动启动并连接内置 WebUI |
| **远程服务器** | 已在其他位置运行 hermes-webui（或内置 sidecar）：家庭服务器、VPS 或另一台 PC | 主机、端口与密码（或用户名 + 密码 / API Key） |

支持多服务器配置一键切换；凭据存储于系统安全存储区。

API 契约对齐 **[nesquena/hermes-webui](https://github.com/nesquena/hermes-webui)**（MIT，社区版 Hermes WebUI）。

> **声明**：本项目为独立社区项目，与 Nous Research 无隶属或背书关系。

## 技术栈

| 领域 | 选型 |
|---|---|
| 框架 | Flutter 3.47+ / Dart 3.13+ |
| UI | 全量 Cupertino 组件（业务 UI 不混入 Material） |
| 状态管理 | flutter_riverpod 2.x |
| 网络 | dio 5.x + 自封装 SSE 客户端 + web_socket_channel |
| 路由 | go_router 17.x |
| Markdown | flutter_markdown（自定义渲染器） |
| 本地存储 | drift（SQLite）+ flutter_secure_storage |
| 图表 | fl_chart |
| 测试 | flutter_test + mocktail + fake_async |

## 项目状态

活跃开发中：2,400+ 自动化测试全绿、`flutter analyze` 零告警。发布产物为 CI 构建的 Windows 安装包（内置 WebUI sidecar）与 Android arm64 APK。变更详情见 [更新日志](CHANGELOG.md)。

## 开源协议

本项目基于 [MIT License](LICENSE) 发布。内置的第三方组件（hermes-webui 服务端、嵌入式 Python 及其依赖）保留其原始协议，声明汇总见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

## 致谢

- [Hermes Agent](https://github.com/NousResearch/hermes-agent)（Nous Research）—— 本客户端所对接的 Agent 引擎。
- [nesquena/hermes-webui](https://github.com/nesquena/hermes-webui) —— 本项目 API 对齐的社区 WebUI，其服务端随 Windows 安装包内置分发。
- [uzairansaruzi/hermex](https://github.com/uzairansaruzi/hermex) —— 早期 UI 灵感来源（iOS SwiftUI 客户端，MIT）。
