import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/ui_scale_provider.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';
import 'package:hermes_ui/core/models/insights.dart';
import 'package:hermes_ui/core/models/kanban.dart';
import 'package:hermes_ui/core/models/memory.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/skills.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_page.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_providers.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/features/downloads/download_controller.dart';
import 'package:hermes_ui/features/downloads/download_models.dart';
import 'package:hermes_ui/features/downloads/download_page.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/features/git/git_api.dart';
import 'package:hermes_ui/features/git/git_page.dart';
import 'package:hermes_ui/features/insights/insights_api.dart';
import 'package:hermes_ui/features/insights/insights_page.dart';
import 'package:hermes_ui/features/kanban/kanban_page.dart';
import 'package:hermes_ui/features/kanban/kanban_providers.dart';
import 'package:hermes_ui/features/memory/memory_api.dart';
import 'package:hermes_ui/features/memory/memory_page.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/prompts/widgets/saved_prompts_sheet.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/skills/skills_api.dart';
import 'package:hermes_ui/features/skills/skills_page.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/features/workspace/workspace_page.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_page.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_git_api.dart';
import '../helpers/fake_insights_api.dart';
import '../helpers/fake_kanban_api.dart';
import '../helpers/fake_memory_api.dart';
import '../helpers/fake_prompts_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/fake_skills_api.dart';
import '../helpers/fake_tasks_api.dart';
import '../helpers/fake_workspace_api.dart';
import '../helpers/fake_workspace_manager_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 功能页宽屏「落码前现状 / 落码后复验」真渲染工装（**非金照基线，不参与 CI**）
//
// 用法：
//   PAGES_SHOTS=1 C:/tmp/f.bat test test/screenshots/pages_shots_test.dart \
//       --update-goldens
// 产物：`.shots/pages/<页名>-<light|dark>.png`（1280×800 逻辑 @2x = 2560×1600）
//       `.shots/` 已被 .gitignore 排除，不会污染仓库。
//
// 一页一命令出全套：每个功能页两条用例（浅色 / 暗色），**一次运行同时出两套**，
// 不需要跑两遍。不设 `PAGES_SHOTS=1` 时全部 skip（`skip: !_capture`），
// 不参与金照比对、不影响 `flutter test` 全量结果。
//
// 覆盖页（10）：设置 / 记忆 / 技能 / 工作区 / 工作区管理 / 任务 / 下载 / Git /
// 诊断 / 提示词 ⇒ 每页浅色 + 暗色各一张 = 20 张；
// 补充图若干组（批 4A / 4B / 4C 各自新增，以下方实际用例为准）：
//   记忆「我的笔记」分区 · **窄屏**工作区整页预览 · 工作区宽屏双栏就地预览 ·
//   Git 宽屏双栏 diff 右栏 · 技能「左列表 + 右详情」 · 任务「右栏输出常驻 · 切任务」 ·
//   诊断「级别筛选」与「右栏内联详情」（各浅/暗）。
// 任务输出面板 / 技能详情 / Git diff / 诊断详情以**页内展开态**同框呈现（主图即含），不另出图。
//
// 真实性约定（同 readme_shots_test）：真字体（[loadHermesGoldenFonts]，否则
// 中文渲染成方块）、真实 shell（AdaptiveShell 全壳，含侧栏与宽屏双栏）、
// 演示数据全部是具体内容（真实仓库路径 / 技能名 / 日志行），无 Item 1 /
// Lorem ipsum / TODO 这类占位。
//
// 等宽中文：git diff 与诊断日志是 monospace 文本且含中文，flutter_tester 同族
// 多注册「先注册者胜」→ 必须在 loadHermesGoldenFonts() 之前把 CJK 抢先注册为
// monospace 族首（见 [_registerMonospaceCjk]），否则这些页的中文是豆腐块。
//
// 与产品代码的关系：
// - **不修改任何 lib/ 代码**，只注入 fake API + 演示数据；
// - 「诊断」在产品里没有顶层路由（由设置页 push 进入 DiagnosticsPage）；
//   「提示词」在产品里是聊天输入栏的底部 Sheet（宽屏改用 popover）——
//   本工装为此自建了两条**测试专用路由** `/diagnostics` `/prompts` 以便逐页
//   出图；提示词页直接渲染真实组件 [SavedPromptsSheet]，宽屏 popover 形态
//   见 `lib/features/chat/widgets/chat_input_bar.dart::_showSavedPromptsSheet`。
//   提示词页上半部留白即「该路由无页面内容」的直接体现，不是渲染失败。
//
// 目检发现（**产品现状，非本工装引入**，已随图交重设计裁量）：
// 1. Git 暗色：diff 块底色固定 CupertinoColors.secondarySystemBackground
//    （实际 #F2F2F7），文字用暗色 label（近白）⇒ 浅底浅字、几乎不可读；
//    git_page.dart 已自注「旧暗问题待裁」；
// 2. 任务输出面板与记忆「我的笔记 / 用户画像」分区：正文是 markdown 原文
//    裸显（`#` `**` `|` 直接可见），只有「项目上下文 / 智能体灵魂」走
//    MarkdownBody 渲染；
// 3. 工作区页顶部「位置：根目录」与紧随的面包屑首块「根目录」语义重复。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip，CI / 日常 flutter test 零影响。
final bool _capture = Platform.environment['PAGES_SHOTS'] == '1';
const String _skipReason = '设置 PAGES_SHOTS=1 才生成功能页宽屏目检图';

/// 演示用服务器（example 保留域，无真实主机）。
const String _demoBaseUrl = 'https://hermes.example.com:8787';

/// 演示会话 ID（工作区 / Git / 看板等按会话定位的页共用）。
const String _demoSessionId = 's-demo-1';

/// 演示工作区路径（与 [demoSessionListApi] 会话归属一致）。
const String _demoWorkspacePath = r'D:\projects\hermes-ui';

/// 演示活跃连接。
Future<ConnectionStore> demoConnectionStore() async {
  final store = ConnectionStore(storage: InMemorySecureStorage());
  await store.save(
    ServerConnection(
      id: 'c1',
      name: 'Home 服务器',
      baseUrl: _demoBaseUrl,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');
  return store;
}

/// 会话列表数据（侧栏 = 全壳的一部分，任何一页都要有真实内容才不空）。
FakeSessionListApi demoSessionListApi() {
  final fixed = DateTime(2026, 9, 12, 12, 0);
  double at(Duration ago) => fixed.subtract(ago).millisecondsSinceEpoch / 1000.0;
  return FakeSessionListApi(
    sessions: [
      SessionSummary(
        sessionId: _demoSessionId,
        title: '产品发布计划：多平台体验统一路线图',
        pinned: true,
        messageCount: 23,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(minutes: 30)),
      ),
      SessionSummary(
        sessionId: 's-demo-2',
        title: '宽屏重设计：逐页现状截图与落码复验',
        messageCount: 41,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(hours: 1)),
      ),
      SessionSummary(
        sessionId: 's-demo-3',
        title: '首连宽限状态机与端口顺延复盘',
        messageCount: 8,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(hours: 3)),
      ),
      SessionSummary(
        sessionId: 's-demo-4',
        title: 'Android 实况通知图标 24px 可读性实测',
        messageCount: 17,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(days: 1, hours: 2)),
      ),
      SessionSummary(
        sessionId: 's-demo-5',
        title: '发布包瘦身：embedded python 解绑',
        messageCount: 12,
        projectId: 'p-demo-reading',
        lastMessageAt: at(const Duration(days: 2)),
      ),
      SessionSummary(
        sessionId: 's-demo-6',
        title: 'Git 变更面板 diff 折叠体验',
        messageCount: 6,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(days: 5)),
      ),
    ],
  );
}

/// 侧栏工作区选择器 + 输入区元信息 chip 要读目录数据，统一喂一份固定清单。
final demoWorkspaceOverrides = <Override>[
  workspaceRootsProvider.overrideWith(
    (ref) => Future.value(const [
      WorkspaceRoot(path: _demoWorkspacePath, name: 'hermes-ui'),
      WorkspaceRoot(path: r'D:\projects\book-hub', name: 'book-hub'),
      WorkspaceRoot(path: r'D:\worktrees\hermes-shots-13pages', name: 'shots-13pages'),
    ]),
  ),
  availableModelIdsProvider.overrideWith(
    (ref) => Future.value(const ['claude-opus-4.6', 'gemini-3.8-flash-high']),
  ),
];

/// 项目 API stub（会话行副标题要 projectId → 项目名，避免真实请求）。
class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async => const ProjectsResponse(
    projects: [
      ProjectSummary(projectId: 'p-demo-hermes', name: 'Hermes'),
      ProjectSummary(projectId: 'p-demo-reading', name: '读书'),
    ],
  );

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

// ---------------------------------------------------------------------------
// 记忆：四个分区（我的笔记 / 用户画像 / 智能体灵魂 / 项目上下文）
// ---------------------------------------------------------------------------

const String _demoMemoryNotes = '''
# 我的笔记

## 协作节奏
- 主人拍方向、柚子（Leader）拆任务、子代理并行执行、Leader 独立复验后统一提交
- 每轮收口必须留「判据」：命令 + 阈值 + 实测输出，不接受「应该没问题」

## 当前主线
1. **宽屏重设计**：先逐页出「落码前现状」真渲染图，逐页落码后同角度复验
2. 打包链路：Windows 安装包 + Android arm64 单 ABI，验包脚本进发布流程
3. CI 七 job 全绿是底线，红了当天修，不允许长期挂着

## 坑位记录
- `flutter test` 与 `flutter analyze` 抢 build 锁 → 并发跑会偶发时序失败
- drift 单例：`AppDatabase.production()` 二次构造会撞隔离冲突
- monospace 字族在 flutter_tester 里按「先注册者胜」解析，中文会变方块
''';

const String _demoUserProfile = '''
# 用户画像

## 技术背景
- 全栈工程师，主力 Flutter / Dart，服务端熟 Python（FastAPI、drift 之外的 ORM 都碰过）
- 本机 Windows 11，开发目录 `D:\\projects\\*`；工具链全走 git-bash

## 沟通偏好
- **结论先行**：先给判断，再给依据；不要铺垫
- 中文为主，技术名词保留英文原词（不要翻译成「协程调度器」这类）
- 汇报格式固定：做了什么 / 验证了什么 / 剩什么没做

## 协作红线
- 子代理交付前禁止 commit / push，统一由 Leader 提交
- 任何「完成」都要有可复现的实测命令，不接受自述
- 不许用 Item 1 / Lorem ipsum 这类占位数据糊弄演示
''';

const String _demoSoul = '''
# 智能体灵魂

## 身份
Hermes Agent（Hermex Flutter 移植版的常驻助手），与主人单线协作。

## 原则
1. **先把活干完**：交付物是能跑的东西，不是计划书
2. **不确定就说不确定**：宁可标注存疑，也不编造结论
3. **最小改动面**：改 `lib/` 之前先问「这真是根因吗」
4. **可复现**：每条结论都带命令与输出

## 语气
- 直接、少形容词；不寒暄、不复述需求
- 长任务给进度锚点，不刷屏
''';

const String _demoProjectContext = '''
# 项目上下文：hermes-ui

## 这是什么
把 iOS 原生 **Hermex**（SwiftUI，MIT）移植成 Flutter + Cupertino 的全平台客户端，
API 契约对齐 `nesquena/hermes-webui`。优先平台 Android + Windows。

## 目录约定
| 目录 | 职责 |
| --- | --- |
| `lib/app/shell/` | 外壳：AdaptiveShell / SessionSidebar / 导航轨（kAdaptiveBreakpoint = 900） |
| `lib/features/*` | 20 个功能页，一页一目录 |
| `lib/core/models/` | 手写 fromJson/toJson 容错模型 |
| `test/golden/goldens/<平台>/` | 金照基线，按平台分目录 |

## 硬规则
- **Cupertino-only**：业务 UI 不混 Material（`import 'package:flutter/material.dart'` 仅限 `Tooltip` 等例外）
- Riverpod 命名后缀：`xxxProvider` / `xxxController`
- 截图工装用 `matchesGoldenFile` + `--update-goldens`，且必须 env-gated

## 当前工作区
`D:\\projects\\hermes-ui` — 分支 `feat/shots-13pages`（隔离 worktree
`D:\\worktrees\\hermes-shots-13pages`），基线 `cf57127`。
''';

MemoryResponse demoMemoryResponse() {
  final mtime = DateTime(2026, 9, 26, 21, 40).millisecondsSinceEpoch / 1000.0;
  return MemoryResponse(
    memory: _demoMemoryNotes,
    user: _demoUserProfile,
    soul: _demoSoul,
    memoryPath: r'C:\Users\Admin\AppData\Local\hermes\memories\memory.md',
    userPath: r'C:\Users\Admin\AppData\Local\hermes\memories\user.md',
    soulPath: r'C:\Users\Admin\AppData\Local\hermes\memories\soul.md',
    memoryMtime: mtime - 5400,
    userMtime: mtime - 86400,
    soulMtime: mtime - 172800,
    projectContext: _demoProjectContext,
    projectContextName: 'hermes-ui',
    projectContextPath: r'D:\projects\hermes-ui\.hermes\context.md',
    projectContextWorkspace: _demoWorkspacePath,
    projectContextMtime: mtime,
    projectContextShadowed: false,
    externalNotesEnabled: true,
  );
}

// ---------------------------------------------------------------------------
// 技能：分类分组 + 单行展开详情
// ---------------------------------------------------------------------------

List<SkillSummary> demoSkills() => const [
  SkillSummary(
    name: 'hermex-flutter-codebase',
    category: '软件与工程',
    description:
        'Hermex Flutter 移植仓的代码导航与移植约束：外壳结构、Riverpod 后缀规范、'
        'Cupertino-only 纪律、金照基线目录约定。',
    path: r'C:\Users\Admin\AppData\Local\hermes\skills\hermex-flutter-codebase\SKILL.md',
    tags: ['flutter', 'cupertino', 'riverpod'],
    relatedSkills: ['hermes-agent', 'systematic-debugging'],
  ),
  SkillSummary(
    name: 'windows-services',
    category: '软件与工程',
    description: '用 NSSM 把脚本注册成 Windows 服务/守护进程：安装、日志重定向、失败重启策略。',
    path: r'C:\Users\Admin\AppData\Local\hermes\skills\windows-services\SKILL.md',
    tags: ['windows', 'nssm'],
    relatedSkills: ['modem-sms-daemon'],
  ),
  SkillSummary(
    name: 'systematic-debugging',
    category: '软件与工程',
    description: '四阶段根因调试：先理解现象与判据，再定位根因，最后才动手改；禁止猜着改。',
    path: r'C:\Users\Admin\AppData\Local\hermes\skills\systematic-debugging\SKILL.md',
    tags: ['debug', 'root-cause'],
    relatedSkills: ['code-audit'],
  ),
  SkillSummary(
    name: 'flutter-android-release',
    category: '软件与工程',
    description: 'Android release 打包：升版本号 → arm64 单 ABI 编译 → 验包原生库齐全 → git tag。',
    path: r'C:\Users\Admin\AppData\Local\hermes\skills\flutter-android-release\SKILL.md',
    tags: ['android', 'release'],
    relatedSkills: ['flutter-windows-release'],
  ),
  SkillSummary(
    name: 'parallel-subagent-project-governance',
    category: '协作与治理',
    description: '多并行子代理做大项目的治理规范：规格先行、文件分区、验收合并、steer 纠偏、独立复验。',
    path:
        r'C:\Users\Admin\AppData\Local\hermes\skills\parallel-subagent-project-governance\SKILL.md',
    tags: ['delegation', 'governance'],
    relatedSkills: ['merge-reconciler'],
  ),
  SkillSummary(
    name: 'parallel-subagent-project-governance-legacy',
    category: '协作与治理',
    description: '旧版并行治理（已被上一条取代，保留以备回滚对照）。',
    path:
        r'C:\Users\Admin\AppData\Local\hermes\skills\parallel-subagent-project-governance-legacy\SKILL.md',
    disabled: true,
    tags: ['deprecated'],
  ),
  SkillSummary(
    name: 'client-facing-documents',
    category: '文档与交付',
    description: '对外 Word/PDF 交付文档（方案 / 提案 / 合同）的中文排版配方 + 渲染目检流程。',
    path: r'C:\Users\Admin\AppData\Local\hermes\skills\client-facing-documents\SKILL.md',
    tags: ['docx', 'pdf', '中文排版'],
    relatedSkills: ['docx'],
  ),
  SkillSummary(
    name: 'grounded-citations',
    category: '文档与交付',
    description: '让答案与文档建立在可核验的引用上：来源分级、引用格式、不可核实时的降级表达。',
    path: r'C:\Users\Admin\AppData\Local\hermes\skills\grounded-citations\SKILL.md',
    tags: ['citation', 'research'],
  ),
];

// ---------------------------------------------------------------------------
// 工作区：文件树（真实仓库路径 + 真实体积）
// ---------------------------------------------------------------------------

const double _demoDirMtime = 1758840000; // 2026-09-26 前后（Unix 秒）

Map<String, List<WorkspaceEntry>> demoWorkspaceDirectories() => {
  '.': const [
    WorkspaceEntry(name: 'lib', path: 'lib', type: 'dir', isDirectory: true, modified: _demoDirMtime),
    WorkspaceEntry(name: 'test', path: 'test', type: 'dir', isDirectory: true, modified: _demoDirMtime),
    WorkspaceEntry(name: 'docs', path: 'docs', type: 'dir', isDirectory: true, modified: _demoDirMtime),
    WorkspaceEntry(name: 'assets', path: 'assets', type: 'dir', isDirectory: true, modified: _demoDirMtime),
    WorkspaceEntry(
      name: 'pubspec.yaml',
      path: 'pubspec.yaml',
      type: 'file',
      isDirectory: false,
      size: 3184,
      modified: _demoDirMtime - 1800,
    ),
    WorkspaceEntry(
      name: 'AGENTS.md',
      path: 'AGENTS.md',
      type: 'file',
      isDirectory: false,
      size: 18420,
      modified: _demoDirMtime - 6200,
    ),
    WorkspaceEntry(
      name: 'analysis_options.yaml',
      path: 'analysis_options.yaml',
      type: 'file',
      isDirectory: false,
      size: 1266,
      modified: _demoDirMtime - 86400,
    ),
    WorkspaceEntry(
      name: 'REPO_MAP.md',
      path: 'REPO_MAP.md',
      type: 'file',
      isDirectory: false,
      size: 9642,
      modified: _demoDirMtime - 172800,
    ),
  ],
  'lib': const [
    WorkspaceEntry(name: 'app', path: 'lib/app', type: 'dir', isDirectory: true, modified: _demoDirMtime),
    WorkspaceEntry(name: 'core', path: 'lib/core', type: 'dir', isDirectory: true, modified: _demoDirMtime),
    WorkspaceEntry(name: 'features', path: 'lib/features', type: 'dir', isDirectory: true, modified: _demoDirMtime),
    WorkspaceEntry(name: 'l10n', path: 'lib/l10n', type: 'dir', isDirectory: true, modified: _demoDirMtime),
    WorkspaceEntry(
      name: 'main.dart',
      path: 'lib/main.dart',
      type: 'file',
      isDirectory: false,
      size: 8420,
      modified: _demoDirMtime - 7200,
    ),
  ],
};

/// 文本文件内容（工作区「预览」用；真实感内容，便于核对宽屏阅读宽度）。
const String _demoDartFileContent = '''
import 'package:flutter/cupertino.dart';
import 'package:hermes_ui/core/models/session.dart';

/// 会话行（宽屏紧凑形态 / 窄屏完整形态共用）。
class SessionRowTile extends StatelessWidget {
  const SessionRowTile({
    super.key,
    required this.session,
    required this.current,
  });

  final SessionSummary session;

  /// 当前会话：左侧 2px 蓝条 + 内描边（#150）。
  final bool current;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return CupertinoListTile(
      title: Text(
        session.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        session.relativeTimeText,
        style: TextStyle(
          fontSize: 12,
          color: isLight
              ? LightSurfaces.textSecondary
              : CupertinoColors.secondaryLabel,
        ),
      ),
      onTap: () => context.push('/chat/\${session.sessionId}'),
    );
  }
}
''';

// ---------------------------------------------------------------------------
// 工作区管理：注册表（4 个真实工作区）
// ---------------------------------------------------------------------------

List<WorkspaceRoot> demoWorkspaceRoots() => const [
  WorkspaceRoot(path: _demoWorkspacePath, name: 'hermes-ui'),
  WorkspaceRoot(path: r'D:\worktrees\hermes-shots-13pages', name: 'shots-13pages'),
  WorkspaceRoot(path: r'D:\projects\book-hub', name: 'book-hub'),
  WorkspaceRoot(path: r'D:\projects\media-studio', name: 'media-studio'),
];

// ---------------------------------------------------------------------------
// 任务：定时任务列表 + 输出
// ---------------------------------------------------------------------------

DateTime _demoClock(Duration ago) =>
    DateTime(2026, 9, 27, 9, 5).subtract(ago);

List<CronJob> demoCronJobs() {
  final next = _demoClock(const Duration(minutes: -55));
  final last = _demoClock(const Duration(hours: 2));
  return [
    CronJob(
      jobId: 'job-1',
      name: 'Hermes 仓 CI 巡检',
      prompt: '检查 hermes-ui main 分支最近一次 CI 是否全绿；红了给出失败 job 与首条根因日志。',
      schedule: const CronSchedule(kind: 'cron', expression: '0 8 * * *'),
      scheduleDisplay: '每天 08:00',
      enabled: true,
      state: 'active',
      nextRunAt: CronDateValue(next),
      lastRunAt: CronDateValue(last),
      lastStatus: 'ok',
      deliver: 'local',
      skills: const ['parallel-subagent-project-governance'],
      model: 'claude-opus-4.6',
      provider: 'anthropic',
      profile: 'default',
    ),
    CronJob(
      jobId: 'job-2',
      name: '用量周报（近 7 天 token / 成本）',
      prompt: '汇总最近 7 天各模型 token 与成本，输出三行结论 + 一张近 14 天柱状图数据。',
      schedule: const CronSchedule(kind: 'cron', expression: '0 9 * * 1'),
      scheduleDisplay: '每周一 09:00',
      enabled: true,
      state: 'active',
      nextRunAt: CronDateValue(next.add(const Duration(days: 2))),
      lastRunAt: CronDateValue(last.subtract(const Duration(days: 1))),
      lastStatus: 'ok',
      deliver: 'telegram',
      model: 'gemini-3.8-flash-high',
      provider: 'google',
    ),
    CronJob(
      jobId: 'job-3',
      name: 'B 站 UP 主新视频盯梢',
      prompt: '盯 3 个 UP 主更新；有新视频给出标题、时长、与上一条的差异点。',
      schedule: const CronSchedule(kind: 'interval', every: '30m'),
      scheduleDisplay: '每 30 分钟',
      enabled: true,
      state: 'active',
      nextRunAt: CronDateValue(next.add(const Duration(minutes: 25))),
      lastRunAt: CronDateValue(last.subtract(const Duration(minutes: 5))),
      lastStatus: 'error',
      lastError: 'HTTP 412（风控）：需要带完整浏览器指纹重试',
      deliver: 'local',
      skills: const ['bilibili-up-watchdog'],
    ),
    CronJob(
      jobId: 'job-4',
      name: '磁盘空间巡检（低于 10% 告警）',
      prompt: '检查 D: 与 C: 剩余空间；低于 10% 时列出占用前 10 的目录。',
      schedule: const CronSchedule(kind: 'cron', expression: '0 */6 * * *'),
      scheduleDisplay: '每 6 小时',
      enabled: true,
      state: 'active',
      nextRunAt: CronDateValue(next.add(const Duration(hours: 3))),
      lastRunAt: CronDateValue(last),
      lastStatus: 'ok',
      deliver: 'local',
    ),
    CronJob(
      jobId: 'job-5',
      name: '构建缓存清理（保留最近 3 个）',
      prompt: '清理 build/ 与 .dart_tool/ 中超过 7 天未使用的产物，保留最近 3 个构建。',
      schedule: const CronSchedule(kind: 'cron', expression: '30 4 * * *'),
      scheduleDisplay: '每天 04:30',
      enabled: false,
      state: 'paused',
      nextRunAt: CronDateValue(next.add(const Duration(hours: 19))),
      lastRunAt: CronDateValue(last.subtract(const Duration(days: 3))),
      lastStatus: 'ok',
      deliver: 'local',
    ),
    CronJob(
      jobId: 'job-6',
      name: '价格监控（目标价触发）',
      prompt: '盯两款目标产品价格；低于目标价立刻播报，附历史最低价对照。',
      schedule: const CronSchedule(kind: 'cron', expression: '0 10,22 * * *'),
      scheduleDisplay: '每天 10:00、22:00',
      enabled: true,
      state: 'active',
      nextRunAt: CronDateValue(next.add(const Duration(hours: 1))),
      lastRunAt: CronDateValue(last.subtract(const Duration(hours: 4))),
      lastStatus: 'ok',
      deliver: 'telegram',
      skills: const ['product-price-monitor'],
    ),
  ];
}

CronOutputResponse demoCronOutput() => const CronOutputResponse(
  jobId: 'job-1',
  outputs: [
    CronOutputItem(
      filename: '2026-09-27T08-00-11+cron-job-1.md',
      content: '''
# CI 巡检报告 · 2026-09-27 08:00

**结论**：全绿（run `36102984755`，7 个 job 全部 success，耗时 12m18s）。

| job | 结果 | 耗时 |
| --- | --- | --- |
| changes | success | 8s |
| guard | success | 21s |
| analyze-test | success | 9m42s |
| android-debug | success | 6m05s |
| fake-gateway | success | 1m12s |
| windows-installer | success | 11m31s |
| coverage | success | 4m07s |

## 观察
- `analyze-test` 比昨天慢 40s，落在新增的 3 个宽屏用例上，可接受。
- `coverage` 覆盖率 78.4%（较昨天 +0.3）。
''',
    ),
    CronOutputItem(
      filename: '2026-09-26T08-00-09+cron-job-1.md',
      content: '''
# CI 巡检报告 · 2026-09-26 08:00

**结论**：1 个 job 失败 —— `analyze-test`。

首条根因日志：

```
Error: test/features/downloads/download_page_test.dart:41:7
  Undefined name 'kDiagnosticsEnabledKey'.
```

判定：测试改了 helper 但没同步 import，属于本地未跑全量；已在 `03cae93` 修复。
''',
    ),
  ],
);

// ---------------------------------------------------------------------------
// 下载：至少 3 条，含一条进行中带进度
// ---------------------------------------------------------------------------

class _DemoDownloadController extends DownloadController {
  _DemoDownloadController(this._tasks);

  final List<DownloadTask> _tasks;

  /// 直接给固定状态：不碰 drift 仓储 / 临时目录 / 平台插件，
  /// 出图不需要真实队列逻辑。
  @override
  DownloadState build() =>
      DownloadState(tasks: _tasks, isInitialized: true);
}

/// [completedDir] 下必须真实存在同名文件：下载页用 `File.existsSync()`
/// 判定「已完成 / 文件已被移动或删除」，纯字符串路径会渲染成误报的失败态。
List<DownloadTask> demoDownloadTasks({required String completedDir}) {
  final now = DateTime(2026, 9, 27, 10, 12).millisecondsSinceEpoch;
  return [
    DownloadTask(
      id: 'dl-1',
      sourceUrl: '$_demoBaseUrl/api/workspace/download?session=s-demo-1&path=build/app-release.apk',
      fileName: 'HermesUI-0.1.51-arm64.apk',
      mimeType: 'application/vnd.android.package-archive',
      status: DownloadStatus.downloading,
      receivedBytes: 61865984,
      expectedBytes: 91801917,
      createdAt: now - 9000,
      sessionId: _demoSessionId,
    ),
    DownloadTask(
      id: 'dl-2',
      sourceUrl: '$_demoBaseUrl/api/workspace/download?session=s-demo-1&path=dist/windows',
      fileName: 'HermesUI-0.1.51-x64-setup.exe',
      mimeType: 'application/vnd.microsoft.portable-executable',
      status: DownloadStatus.queued,
      receivedBytes: 0,
      expectedBytes: 45374462,
      createdAt: now - 18000,
      sessionId: _demoSessionId,
    ),
    DownloadTask(
      id: 'dl-3',
      sourceUrl: '$_demoBaseUrl/files/ci/36102984755/analyze-summary.txt',
      fileName: 'analyze-summary.txt',
      mimeType: 'text/plain',
      status: DownloadStatus.completed,
      receivedBytes: 12844,
      expectedBytes: 12844,
      savedPath: '$completedDir${Platform.pathSeparator}analyze-summary.txt',
      createdAt: now - 5400000,
      completedAt: now - 5394000,
    ),
    DownloadTask(
      id: 'dl-4',
      sourceUrl: '$_demoBaseUrl/files/release/v0.1.51/app-release.apk',
      fileName: 'app-release-old.apk',
      mimeType: 'application/vnd.android.package-archive',
      status: DownloadStatus.failed,
      receivedBytes: 3145728,
      expectedBytes: 91801917,
      failureMessage: '连接中断：Connection closed before full header was received',
      createdAt: now - 86400000,
      completedAt: now - 86398000,
      attemptCount: 3,
    ),
    DownloadTask(
      id: 'dl-5',
      sourceUrl: '$_demoBaseUrl/files/shots/wide-insights.png',
      fileName: 'wide-insights.png',
      mimeType: 'image/png',
      status: DownloadStatus.completed,
      receivedBytes: 486213,
      expectedBytes: 486213,
      savedPath: '$completedDir${Platform.pathSeparator}wide-insights.png',
      createdAt: now - 172800000,
      completedAt: now - 172799000,
    ),
  ];
}

// ---------------------------------------------------------------------------
// 统计：8 项指标 + 14 天令牌 + 活动峰值 + 模型拆分（宽屏 Bento 目检数据）
// ---------------------------------------------------------------------------

InsightsResponse demoInsightsResponse() {
  return const InsightsResponse(
    periodDays: 30,
    totalSessions: 68,
    totalMessages: 1420,
    totalInputTokens: 10400000,
    totalOutputTokens: 1400000,
    totalTokens: 11800000,
    totalCost: 4.8642,
    totalCacheReadTokens: 2400000,
    totalCacheHitPercent: 62.5,
    models: [
      InsightsModelBreakdown(
        model: 'gpt-5.2-codex',
        totalTokens: 4960000,
        tokenShare: 42,
      ),
      InsightsModelBreakdown(
        model: 'claude-sonnet-4.5',
        totalTokens: 3900000,
        tokenShare: 33,
      ),
      InsightsModelBreakdown(
        model: 'deepseek-v4.1',
        totalTokens: 2124000,
        tokenShare: 18,
      ),
      InsightsModelBreakdown(
        model: 'gpt-4o-mini',
        totalTokens: 826000,
        tokenShare: 7,
      ),
    ],
    dailyTokens: [
      InsightsDailyToken(
        date: '2026-08-26',
        inputTokens: 350200,
        outputTokens: 61800,
        sessions: 3,
        cost: 0.037,
      ),
      InsightsDailyToken(
        date: '2026-08-27',
        inputTokens: 270300,
        outputTokens: 47700,
        sessions: 2,
        cost: 0.029,
      ),
      InsightsDailyToken(
        date: '2026-08-28',
        inputTokens: 736950,
        outputTokens: 130050,
        sessions: 5,
        cost: 0.078,
      ),
      InsightsDailyToken(
        date: '2026-08-29',
        inputTokens: 853400,
        outputTokens: 150600,
        sessions: 6,
        cost: 0.09,
      ),
      InsightsDailyToken(
        date: '2026-08-30',
        inputTokens: 431800,
        outputTokens: 76200,
        sessions: 3,
        cost: 0.046,
      ),
      InsightsDailyToken(
        date: '2026-08-31',
        inputTokens: 621350,
        outputTokens: 109650,
        sessions: 4,
        cost: 0.066,
      ),
      InsightsDailyToken(
        date: '2026-09-01',
        inputTokens: 562700,
        outputTokens: 99300,
        sessions: 4,
        cost: 0.06,
      ),
      InsightsDailyToken(
        date: '2026-09-02',
        inputTokens: 836400,
        outputTokens: 147600,
        sessions: 6,
        cost: 0.089,
      ),
      InsightsDailyToken(
        date: '2026-09-03',
        inputTokens: 413100,
        outputTokens: 72900,
        sessions: 3,
        cost: 0.044,
      ),
      InsightsDailyToken(
        date: '2026-09-04',
        inputTokens: 682550,
        outputTokens: 120450,
        sessions: 5,
        cost: 0.072,
      ),
      InsightsDailyToken(
        date: '2026-09-05',
        inputTokens: 1037000,
        outputTokens: 183000,
        sessions: 7,
        cost: 0.11,
      ),
      InsightsDailyToken(
        date: '2026-09-06',
        inputTokens: 400350,
        outputTokens: 70650,
        sessions: 3,
        cost: 0.042,
      ),
      InsightsDailyToken(
        date: '2026-09-07',
        inputTokens: 588200,
        outputTokens: 103800,
        sessions: 4,
        cost: 0.062,
      ),
      InsightsDailyToken(
        date: '2026-09-08',
        inputTokens: 1045500,
        outputTokens: 184500,
        sessions: 7,
        cost: 0.111,
      ),
    ],
    activityByDay: [
      InsightsActivityByDay(day: '2026-09-05', sessions: 7),
      InsightsActivityByDay(day: '2026-09-08', sessions: 7),
      InsightsActivityByDay(day: '2026-09-02', sessions: 6),
    ],
    activityByHour: [
      InsightsActivityByHour(hour: 21, sessions: 7),
      InsightsActivityByHour(hour: 10, sessions: 5),
      InsightsActivityByHour(hour: 15, sessions: 4),
    ],
  );
}

// ---------------------------------------------------------------------------
// 看板：分列卡片 + 卡片详情（描述 / 评论 —— 宽屏字号档目检数据）
// ---------------------------------------------------------------------------

const KanbanCard _demoKanbanCard = KanbanCard(
  cardID: 'kb-2',
  title: '首连宽限状态机复盘',
  status: KanbanStatus('todo'),
  assignee: 'dev-a',
  commentCount: 2,
  linkCounts: KanbanLinkCounts(parents: 1),
  body:
      '对照 #72 的 4s 宽限窗口，确认冷启动补报路径不丢事件。\n'
      '判据：探活失败后的 500ms 重试仍能拿到 resolved 状态，且 expired '
      '分支补出真错误而不是「离线缓存」文案。',
);

FakeKanbanApi demoKanbanApi() {
  return FakeKanbanApi(
    boards: const [
      KanbanBoard(slug: 'default', name: '主看板'),
      KanbanBoard(slug: 'infra', name: '基础设施'),
      KanbanBoard(slug: 'release', name: '发版'),
    ],
    currentSlug: 'default',
    snapshots: const {
      'default': KanbanBoardSnapshot(
        columns: [
          KanbanColumn(
            name: 'triage',
            cards: [
              KanbanCard(
                cardID: 'kb-1',
                title: '通知小图标 24dp 逐像素复核',
                status: KanbanStatus('triage'),
              ),
              KanbanCard(
                cardID: 'kb-9',
                title: 'CI windows-installer 产物回读',
                status: KanbanStatus('triage'),
                assignee: 'dev-c',
              ),
            ],
          ),
          KanbanColumn(
            name: 'todo',
            cards: [
              _demoKanbanCard,
              KanbanCard(
                cardID: 'kb-3',
                title: 'Android 通知点击直达深链验证',
                status: KanbanStatus('todo'),
                assignee: 'dev-b',
              ),
              KanbanCard(
                cardID: 'kb-4',
                title: '侧栏保活三态文案校对',
                status: KanbanStatus('todo'),
              ),
            ],
          ),
          KanbanColumn(
            name: 'ready',
            cards: [
              KanbanCard(
                cardID: 'kb-5',
                title: '时间线卡片穿插回归',
                status: KanbanStatus('ready'),
                assignee: 'dev-a',
                commentCount: 4,
                linkCounts: KanbanLinkCounts(parents: 2),
              ),
            ],
          ),
          KanbanColumn(
            name: 'running',
            cards: [
              KanbanCard(
                cardID: 'kb-6',
                title: '宽屏批次 2 三页落码',
                status: KanbanStatus('running'),
                assignee: 'dev-a',
                commentCount: 3,
              ),
            ],
          ),
          KanbanColumn(
            name: 'done',
            cards: [
              KanbanCard(
                cardID: 'kb-7',
                title: '柱状图 X 轴标签重叠修复',
                status: KanbanStatus('done'),
                commentCount: 2,
              ),
              KanbanCard(
                cardID: 'kb-8',
                title: 'sidecar 解释器探测顺序回归',
                status: KanbanStatus('done'),
                assignee: 'dev-b',
              ),
            ],
          ),
        ],
      ),
    },
    details: const {
      'kb-2': KanbanCardDetailEnvelope(
        card: _demoKanbanCard,
        comments: [
          KanbanComment(
            commentID: 'c-1',
            cardID: 'kb-2',
            author: 'dev-b',
            body: '复现到了：冷启动第 2 次探活就把宽限窗口吃掉，第 3 次才补真错误。',
            createdAt: '2026-09-27T09:41:00+08:00',
          ),
          KanbanComment(
            commentID: 'c-2',
            cardID: 'kb-2',
            author: 'dev-a',
            body: '已按 4s + 500ms 重排，补报只走一次，等闲时再跑一轮回归。',
            createdAt: '2026-09-27T10:05:00+08:00',
          ),
        ],
      ),
    },
  );
}

// ---------------------------------------------------------------------------
// Git：变更列表 + 单个文件 diff
// ---------------------------------------------------------------------------

const String _demoDiffFilePath = 'lib/features/chat/widgets/chat_input_bar.dart';

GitStatusResponse demoGitStatus() => GitStatusResponse(
  git: GitStatus(
    isGit: true,
    branch: 'feat/shots-13pages',
    upstream: 'origin/main',
    ahead: 2,
    behind: 1,
    totals: const GitTotals(changed: 6, staged: 2, unstaged: 3, untracked: 1),
    files: [
      GitFile(
        path: _demoDiffFilePath,
        status: 'M',
        staged: true,
        unstaged: true,
        additions: 34,
        deletions: 11,
      ),
      GitFile(
        path: 'lib/features/session_list/session_list_page.dart',
        status: 'M',
        unstaged: true,
        additions: 18,
        deletions: 6,
      ),
      GitFile(
        path: 'lib/features/downloads/download_page.dart',
        status: 'M',
        staged: true,
        additions: 9,
        deletions: 2,
      ),
      GitFile(
        path: 'lib/app/shell/sidebar_utility_toolbar.dart',
        status: 'M',
        unstaged: true,
        additions: 5,
        deletions: 5,
      ),
      GitFile(
        path: 'test/screenshots/pages_shots_test.dart',
        status: 'A',
        staged: true,
        additions: 812,
        deletions: 0,
      ),
      GitFile(
        path: 'docs/screenshots/wide-chat.png',
        status: '??',
        untracked: true,
      ),
    ],
  ),
);

GitBranchesResponse demoGitBranches() => const GitBranchesResponse(
  branches: GitBranches(
    isGit: true,
    current: 'feat/shots-13pages',
    local: [
      GitBranchRef(name: 'feat/shots-13pages'),
      GitBranchRef(name: 'main'),
      GitBranchRef(name: 'dev'),
    ],
  ),
);

GitDiffResponse demoGitDiff() => const GitDiffResponse(
  diff: GitDiff(
    path: _demoDiffFilePath,
    kind: 'unstaged',
    additions: 34,
    deletions: 11,
    diff: '''
diff --git a/lib/features/chat/widgets/chat_input_bar.dart b/lib/features/chat/widgets/chat_input_bar.dart
index 3f8a41c..b71d2e0 100644
--- a/lib/features/chat/widgets/chat_input_bar.dart
+++ b/lib/features/chat/widgets/chat_input_bar.dart
@@ -638,6 +638,22 @@ class _ChatInputBarState extends ConsumerState<ChatInputBar> {
     });
   }
 
+  /// 宽屏（≥900）：收藏提示词改弹出局部气泡，避免底部弹层遮蔽内容区。
+  Future<void> _showSavedPromptsSheet() async {
+    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
+    if (isWide) {
+      await showCupertinoPopover(
+        context: context,
+        anchorKey: _bookmarkKey,
+        builder: (popoverContext, close) => SavedPromptsPanel(
+          onInsert: _insertPromptText,
+          getCurrentInput: () => _textController.text,
+          onInserted: close,
+        ),
+      );
+      return;
+    }
+    await showCupertinoModalPopup<void>(
+      context: context,
+      builder: (sheetContext) => SavedPromptsSheet(
+        onInsert: _insertPromptText,
+        getCurrentInput: () => _textController.text,
+      ),
+    );
+  }
+
@@ -812,9 +828,9 @@ class _ChatInputBarState extends ConsumerState<ChatInputBar> {
               key: const ValueKey('chat-bookmark'),
               label: l10n.savedPromptsTitle,
               padding: EdgeInsets.zero,
-              onPressed: _showSavedPrompts,
+              onPressed: _showSavedPromptsSheet,
               child: Icon(
-                CupertinoIcons.bookmark,
+                CupertinoIcons.book,
                 size: 20,
                 color: bookmarkColor,
               ),
''',
  ),
);

// ---------------------------------------------------------------------------
// 诊断：分段 + 日志表
// ---------------------------------------------------------------------------

Future<DiagnosticsService> demoDiagnosticsService() async {
  final prefs = await SharedPreferences.getInstance();
  final service = DiagnosticsService(customPrefs: prefs);
  await service.init(prefs: prefs);
  await service.setEnabled(true);
  final base = DateTime(2026, 9, 27, 10, 9, 30);
  void log(
    Duration ago,
    DiagnosticsLogLevel level,
    String tag,
    String message, {
    int? durationMs,
    Map<String, Object?>? details,
    String? errorKind,
  }) {
    service.log(
      level: level,
      tag: tag,
      message: message,
      timestamp: base.subtract(ago),
      durationMs: durationMs,
      details: details,
      errorKind: errorKind,
    );
  }

  log(
    const Duration(minutes: 6),
    DiagnosticsLogLevel.info,
    'app',
    '服务自检通过：agent venv / 模型目录 / 端口 8787 三项正常',
    durationMs: 412,
    details: {
      'agent_dir': r'D:\projects\hermes-ui\server\.venv',
      'model': 'claude-opus-4.6',
      'port': 8787,
    },
  );
  log(
    const Duration(minutes: 5, seconds: 12),
    DiagnosticsLogLevel.debug,
    'dio',
    'GET /api/sessions → 200',
    durationMs: 268,
    details: {'count': 68, 'cached': false},
  );
  log(
    const Duration(minutes: 4, seconds: 40),
    DiagnosticsLogLevel.debug,
    'sse',
    'SSE 已连接（/api/sessions/s-demo-1/stream）',
    durationMs: 96,
    details: {'reconnect': false, 'token': 'cancel-token-7f21'},
  );
  log(
    const Duration(minutes: 3, seconds: 21),
    DiagnosticsLogLevel.info,
    'chat',
    '回合完成：2 轮问答 / 12 次工具调用 / 34.2s',
    durationMs: 34210,
    details: {'input_tokens': 128400, 'output_tokens': 24600},
  );
  log(
    const Duration(minutes: 2, seconds: 48),
    DiagnosticsLogLevel.warn,
    'keepalive',
    'WorkManager 初始化略慢（1.8s），已降级为前台服务兜底',
    durationMs: 1804,
    details: {'probePluginChain': true, 'workManagerStatus': 'ready'},
  );
  log(
    const Duration(minutes: 1, seconds: 55),
    DiagnosticsLogLevel.error,
    'dio',
    'GET /api/workspace/download → 断流（已自动重试 1 次）',
    durationMs: 60021,
    errorKind: 'connectionClosed',
    details: {
      'url': '/api/workspace/download',
      'received': 3145728,
      'expected': 91801917,
      'retry': 1,
    },
  );
  log(
    const Duration(minutes: 1, seconds: 12),
    DiagnosticsLogLevel.info,
    'downloads',
    '断点续传已恢复：已存 61.9 MB / 共 91.8 MB，续传起点 61865984',
    durationMs: 1420,
    details: {'file': 'HermesUI-0.1.51-arm64.apk', 'range': 'bytes=61865984-'},
  );
  log(
    const Duration(seconds: 38),
    DiagnosticsLogLevel.warn,
    'sse',
    'SSE 心跳超时（15s），触发一次重连',
    durationMs: 15012,
    details: {'attempt': 1, 'backoff_ms': 500},
  );
  log(
    const Duration(seconds: 12),
    DiagnosticsLogLevel.debug,
    'global_error',
    '已捕获渲染期异常并降级为文本渲染',
    errorKind: 'incrementalParseError',
    details: {'widget': 'MarkdownBody', 'fallback': 'Text'},
  );
  log(
    const Duration(seconds: 4),
    DiagnosticsLogLevel.info,
    'app',
    '窗口尺寸变更：2340×1440 → 2560×1600（进入宽屏双栏）',
    durationMs: 34,
    details: {'breakpoint': 900, 'layout': 'wide'},
  );
  return service;
}

// ---------------------------------------------------------------------------
// 提示词：收藏提示词（含长正文）
// ---------------------------------------------------------------------------

List<SavedPrompt> demoSavedPrompts() {
  final base = DateTime(2026, 9, 20, 10, 0).millisecondsSinceEpoch / 1000.0;
  return [
    SavedPrompt(
      id: 'sp-1',
      label: '子代理任务书模板',
      text:
          '在隔离 worktree 里完成 <目标>。\n'
          '必读：AGENTS.md / HERMES.md / <关键代码路径>。\n'
          '硬要求：只改 <文件分区>；不 commit；不碰主仓。\n'
          '交付前自检：analyze 零告警 + 定向测试全绿 + 真跑一遍主路径。\n'
          '汇报：改了哪些文件 / 一条命令用法 / 实测结论 / 存疑项。',
      createdAt: base,
    ),
    SavedPrompt(
      id: 'sp-2',
      label: 'PR 描述（中文）',
      text:
          '## 现象\n<用户可见的现象 + 复现步骤>\n\n'
          '## 根因\n<一句话根因 + 判据命令>\n\n'
          '## 改法\n<最小改动面说明>\n\n'
          '## 验证\n- flutter analyze：零告警\n'
          '- flutter test：<N> 全绿\n- 金照：零变更 / 已更新（附原因）',
      createdAt: base - 3600,
    ),
    SavedPrompt(
      id: 'sp-3',
      label: '发布前检查清单',
      text:
          '1. 版本号 bump（pubspec version + build number）\n'
          '2. analyze 零告警 / 全量测试全绿\n'
          '3. Android：arm64 单 ABI，验包脚本确认原生库齐全\n'
          '4. Windows：安装包体积记录 + exe 冒烟 10s 存活\n'
          '5. Release 附件回读：state=uploaded 且体积逐字节一致\n'
          '6. 检查更新能读到新 tag（releases/latest）',
      createdAt: base - 7200,
    ),
    SavedPrompt(
      id: 'sp-4',
      label: '代码审计开场',
      text:
          '对 <模块> 做一次安全审计：先建立上下文（入口 / 数据流 / 信任边界），'
          '再逐条列举可疑点，每条必须给出「攻击路径 + PoC 或反证」；'
          '无法构造 PoC 的降级标注为「理论风险」。',
      createdAt: base - 86400,
    ),
    SavedPrompt(
      id: 'sp-5',
      label: '截图工装（宽屏逐页）',
      text:
          'PAGES_SHOTS=1 C:/tmp/f.bat test test/screenshots/pages_shots_test.dart --update-goldens\n'
          '产物：.shots/pages/<页名>-<light|dark>.png（1280×800 逻辑 @2x）\n'
          '必须逐张目检：中文非方块、非白屏、非异常报错页、宽屏无溢出。',
      createdAt: base - 172800,
    ),
    SavedPrompt(
      id: 'sp-6',
      label: '复盘三问',
      text:
          '1. 这次失败的**判据**错在哪？（是判据错，还是执行错？）\n'
          '2. 同一个坑下次靠什么**自动化**拦住？\n'
          '3. 有没有更早发现它的**观测点**（日志 / 探针 / 测试）？',
      createdAt: base - 259200,
    ),
  ];
}

// ---------------------------------------------------------------------------
// 工装
// ---------------------------------------------------------------------------

/// 宽屏截图物理像素（逻辑 1280×800 @2x；≥ kAdaptiveBreakpoint=900 → 双栏）。
const Size _wideSize = Size(2560, 1600);

/// 窄屏截图物理像素（逻辑 800×600 @2x；< 900 → 单列）。
///
/// 用途只有一个：批 4 把「列表 → 整页详情」在宽屏改成就地/双栏后，少数页面
/// （如工作区**整页预览**）的整页形态只剩窄屏路径 —— 那几张图改在窄屏出，
/// 顺带把「窄屏逐像素不变」留成可视证据。
const Size _narrowSize = Size(1600, 1200);

/// 提示词页：产品里没有顶层路由（聊天输入栏底部 Sheet / 宽屏 popover），
/// 这里直接渲染真实组件 [SavedPromptsSheet]，按底部弹层形态贴底呈现。
class _PromptsPage extends StatelessWidget {
  const _PromptsPage();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: LightSurfaces.resolve(
        context,
        LightSurfaces.page,
        dark: CupertinoColors.systemGroupedBackground,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SavedPromptsSheet(onInsert: (_) {}),
      ),
    );
  }
}

/// 在本 isolate 内把 CJK 字体抢先注册为 monospace 族首。
///
/// flutter_tester 同族多注册「先注册者胜」且族内无按字形回退（见
/// golden_helpers.dart 已知坑）：git diff 与诊断日志都是等宽文本且含中文，
/// 不抢先注册就会渲染成豆腐块。仅影响本文件（非金照基线），不改既有金照。
Future<void> _registerMonospaceCjk() async {
  final path = firstExistingFont(cjkFallbackFontCandidates);
  if (path == null) return;
  final bytes = File(path).readAsBytesSync();
  await (FontLoader('monospace')
        ..addFont(Future.value(ByteData.sublistView(bytes))))
      .load();
}

/// 宽屏「切任务」目检用 fake：每个任务返回**各自**的输出正文。
///
/// 真 `FakeTasksApi.outputResponse` 是单值 —— 切任务后右栏仍是同一份内容，
/// 目检会误读成「切换没生效」。本类只服务于批 4A 新增的「任务 · 宽屏输出常驻」
/// 一图，不改既有用例（既有用例继续用 `FakeTasksApi` + `demoCronOutput()`）。
class _PerJobOutputTasksApi extends FakeTasksApi {
  _PerJobOutputTasksApi({super.jobs});

  @override
  Future<CronOutputResponse> fetchOutput(String jobId, {int? limit}) async {
    await super.fetchOutput(jobId, limit: limit);
    if (jobId == 'job-2') {
      return const CronOutputResponse(
        jobId: 'job-2',
        outputs: [
          CronOutputItem(
            filename: '2026-09-27T09-00-22+cron-job-2.md',
            content:
                '# 用量周报 · 2026-09-27（周一 09:00）\n\n'
                '本周 token 消耗 4,812,904（输入 3.9M / 输出 0.9M），较上周 −7.3%。\n'
                '成本估算 \$18.42（基线 \$19.87，未超阈值）。\n\n'
                '| 模型 | 调用 | 成本 |\n| --- | --- | --- |\n'
                '| gpt-6-astra | 1,204 | \$11.08 |\n'
                '| deepseek-v4 | 2,880 | \$7.34 |',
          ),
        ],
      );
    }
    return demoCronOutput();
  }
}

void main() {
  setUpAll(() async {
    // CJK → monospace 族首必须在 loadHermesGoldenFonts() 之前。
    await _registerMonospaceCjk();
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 以 [location] 为初始路由挂载 AdaptiveShell 全壳，可选 [interact]
  /// 做一次页面内交互（展开详情 / 打开输出面板），再截图到
  /// `.shots/pages/<name>-<light|dark>.png`。
  Future<void> capturePage(
    WidgetTester tester, {
    required String name,
    required String location,
    required Brightness brightness,
    List<Override> overrides = const [],
    Size size = _wideSize,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final store = await demoConnectionStore();
    final router = GoRouter(
      initialLocation: location,
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const SessionListPage(),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
            ),
            GoRoute(
              path: '/memory',
              builder: (context, state) => const MemoryPage(),
            ),
            GoRoute(
              path: '/skills',
              builder: (context, state) => const SkillsPage(),
            ),
            GoRoute(
              path: '/workspace/:sessionId',
              builder: (context, state) => WorkspacePage(
                sessionId: state.pathParameters['sessionId'] ?? '',
              ),
            ),
            GoRoute(
              path: '/workspaces',
              builder: (context, state) => const WorkspaceManagerPage(),
            ),
            GoRoute(
              path: '/tasks',
              builder: (context, state) => const TasksPage(),
            ),
            GoRoute(
              path: '/downloads',
              builder: (context, state) => const DownloadPage(),
            ),
            GoRoute(
              path: '/insights',
              builder: (context, state) => const InsightsPage(),
            ),
            GoRoute(
              path: '/kanban',
              builder: (context, state) => const KanbanPage(),
            ),
            GoRoute(
              path: '/git/:sessionId',
              builder: (context, state) =>
                  GitPage(sessionId: state.pathParameters['sessionId'] ?? ''),
            ),
            // 产品无此两条顶层路由（诊断页由设置页 push 进入；提示词是
            // 聊天输入栏的弹层），这里自建以便逐页出图。
            GoRoute(
              path: '/diagnostics',
              builder: (context, state) => const DiagnosticsPage(),
            ),
            GoRoute(
              path: '/prompts',
              builder: (context, state) => const _PromptsPage(),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(ApiClient(baseUrl: _demoBaseUrl)),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => demoSessionListApi(),
          ),
          ...demoWorkspaceOverrides,
          // HiDPI 工装：用环境变量 UI_SCALE=x125|x150|x2 钉住缩放档位（默认 100%），
          // 使同一套工装能出任意档位的真实渲染图；不传则与既有出图逐像素一致。
          uiScaleProvider.overrideWith(() => _EnvUiScale(_envUiScale)),
          ...overrides,
        ],
        child: CupertinoApp.router(
          // HiDPI 工装：工装自建 app（绕过 HermesApp），故缩放要在**这里**接一次；
          // 与产品代码 app.dart 的接线语义相同（同一份 applyUiScale）。
          builder: (context, child) => applyUiScale(
            context,
            child ?? const SizedBox.shrink(),
            _envUiScale,
          ),
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(brightness),
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    if (interact != null) {
      await interact(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Directory('$_shotRoot/pages').createSync(recursive: true);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile(
        '$_shotRoot/pages/$name-${brightness == Brightness.dark ? 'dark' : 'light'}.png',
      ),
    );

    await unmountHermesPage(tester);
  }

  /// 同页浅色 + 暗色两图（一条用例出两套，避免跑两遍命令）。
  void shotPair(
    String title,
    Future<void> Function(
      WidgetTester tester,
      Brightness brightness,
    ) body,
  ) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
      testWidgets('宽屏$suffix · $title', (tester) async {
        await body(tester, brightness);
      }, skip: !_capture);
    }
  }

  /// 窄屏同款两图（`<900` 单列形态）。
  ///
  /// 批 4 把宽屏的「列表 → 整页详情」拆成双栏/就地后，**整页详情**只剩窄屏路径，
  /// 这类图改由本方法在窄屏出（[capturePage] 传 `size: _narrowSize`）。
  void narrowShotPair(
    String title,
    Future<void> Function(
      WidgetTester tester,
      Brightness brightness,
    ) body,
  ) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
      testWidgets('窄屏$suffix · $title', (tester) async {
        await body(tester, brightness);
      }, skip: !_capture);
    }
  }

  // -------------------------------------------------------------------------
  // 1. 设置
  // -------------------------------------------------------------------------
  shotPair('设置', (tester, brightness) async {
    final settingsApi = FakeSettingsApi();
    await capturePage(
      tester,
      name: 'settings',
      location: '/settings',
      brightness: brightness,
      overrides: [
        settingsApiFactoryProvider.overrideWithValue((_) => settingsApi),
        // 版本号走渲染演示值，避免 package_info_plus 平台通道。
        appVersionProvider.overrideWith((ref) async => '0.1.51+57'),
        updateCheckerServiceProvider.overrideWithValue(_DemoUpdateChecker()),
      ],
    );
  });

  // 设置 · 服务器分组 —— 字号语义审计的目检入口（表单标签 / 按钮 / 内置服务提示）
  shotPair('设置 · 服务器', (tester, brightness) async {
    final settingsApi = FakeSettingsApi();
    await capturePage(
      tester,
      name: 'settings-server',
      location: '/settings',
      brightness: brightness,
      interact: (t) async {
        // 宽屏下设置页是「左分类导航 + 右内容」，要点进分组才能看到该组控件。
        await t.tap(find.text('服务器').first);
        await t.pumpAndSettle();
      },
      overrides: [
        settingsApiFactoryProvider.overrideWithValue((_) => settingsApi),
        appVersionProvider.overrideWith((ref) async => '0.1.51+57'),
        updateCheckerServiceProvider.overrideWithValue(_DemoUpdateChecker()),
      ],
    );
  });

  // -------------------------------------------------------------------------
  // 2. 记忆（默认落「项目上下文」长 markdown + 补充「我的笔记」分区）
  // -------------------------------------------------------------------------
  shotPair('记忆', (tester, brightness) async {
    await capturePage(
      tester,
      name: 'memory',
      location: '/memory',
      brightness: brightness,
      overrides: [
        memoryApiFactoryProvider.overrideWithValue(
          (_) => FakeMemoryApi(response: demoMemoryResponse()),
        ),
      ],
    );
  });

  shotPair('记忆 · 我的笔记分区', (tester, brightness) async {
    await capturePage(
      tester,
      name: 'memory-notes',
      location: '/memory',
      brightness: brightness,
      overrides: [
        memoryApiFactoryProvider.overrideWithValue(
          (_) => FakeMemoryApi(response: demoMemoryResponse()),
        ),
      ],
      interact: (tester) async {
        await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 3. 技能（列表 + 展开详情）
  // -------------------------------------------------------------------------
  shotPair('技能', (tester, brightness) async {
    await capturePage(
      tester,
      name: 'skills',
      location: '/skills',
      brightness: brightness,
      overrides: [
        skillsApiFactoryProvider.overrideWithValue(
          (_) => FakeSkillsApi(skills: demoSkills()),
        ),
      ],
      interact: (tester) async {
        // 展开第一条（真实技能名）看「路径 + 相关技能」详情形态；
        // 取第一个分组内的技能，展开后详情正好落在视口里。
        await tester.tap(find.text('parallel-subagent-project-governance'));
      },
    );
  });

  // 3b. 技能 · 宽屏双栏（批 4A · P2）：左 320 列表（选中态 L2）+ 右详情限宽 744。
  // 点另一条真实技能名 → 右栏换内容、左栏列表不动（对照上一张「手风琴」形态）。
  shotPair('技能 · 宽屏双栏', (tester, brightness) async {
    await capturePage(
      tester,
      name: 'skills-wide-split',
      location: '/skills',
      brightness: brightness,
      overrides: [
        skillsApiFactoryProvider.overrideWithValue(
          (_) => FakeSkillsApi(skills: demoSkills()),
        ),
      ],
      interact: (tester) async {
        await tester.tap(find.text('grounded-citations'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. 工作区（文件树；补充一张文本文件预览）
  // -------------------------------------------------------------------------
  final workspaceApi = FakeWorkspaceApi(directories: demoWorkspaceDirectories());
  shotPair('工作区', (tester, brightness) async {
    await capturePage(
      tester,
      name: 'workspace',
      location: '/workspace/$_demoSessionId',
      brightness: brightness,
      overrides: [
        workspaceApiFactoryProvider.overrideWithValue((_) => workspaceApi),
      ],
    );
  });

  // 批 4 · P3 之后：「预览」在宽屏**就地进右栏**（见下方 workspace-wide-split），
  // 整页预览页（FilePreviewPage）只剩窄屏路径 —— 本图改在窄屏出，交互原样不动。
  narrowShotPair('工作区 · 整页预览', (tester, brightness) async {
    final api = FakeWorkspaceApi(directories: demoWorkspaceDirectories())
      ..fileContents['lib/main.dart'] = const FileResponse(
        path: 'lib/main.dart',
        name: 'main.dart',
        language: 'dart',
        size: 8420,
        lines: 42,
        content: _demoDartFileContent,
      );
    await capturePage(
      tester,
      name: 'workspace-preview',
      location: '/workspace/$_demoSessionId',
      brightness: brightness,
      size: _narrowSize,
      overrides: [workspaceApiFactoryProvider.overrideWithValue((_) => api)],
      interact: (tester) async {
        // 进入 lib/ → 点 main.dart 打开条目操作菜单 → 预览
        await tester.tap(find.text('lib'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('main.dart'));
        // 窄屏（800×600）视口矮，弹层入场动画未结算时「预览」项还在屏下 ——
        // 必须等它停稳再点，否则点到的是动画中途的坐标（旧宽屏图恰好侥幸不越界）。
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('workspace-action-preview')));
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
  });

  // 批 4 · P3：宽屏双栏「左 340 文件树 + 右预览铺满」（窄屏不受影响，见上两张）。
  shotPair('工作区 · 宽屏双栏就地预览', (tester, brightness) async {
    final api = FakeWorkspaceApi(directories: demoWorkspaceDirectories())
      ..fileContents['lib/main.dart'] = const FileResponse(
        path: 'lib/main.dart',
        name: 'main.dart',
        language: 'dart',
        size: 8420,
        lines: 42,
        content: _demoDartFileContent,
      );
    await capturePage(
      tester,
      name: 'workspace-wide-split',
      location: '/workspace/$_demoSessionId',
      brightness: brightness,
      overrides: [workspaceApiFactoryProvider.overrideWithValue((_) => api)],
      interact: (tester) async {
        // 宽屏点文件行 = 就地进右栏（不 push 整页预览）→ 左栏 L2 选中态 + 右栏代码。
        await tester.tap(find.text('lib'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('main.dart'));
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 5. 工作区管理
  // -------------------------------------------------------------------------
  shotPair('工作区管理', (tester, brightness) async {
    await capturePage(
      tester,
      name: 'workspaces',
      location: '/workspaces',
      brightness: brightness,
      overrides: [
        workspaceManagerApiFactoryProvider.overrideWithValue(
          (_) => FakeWorkspaceManagerApi(
            workspaces: demoWorkspaceRoots(),
            last: _demoWorkspacePath,
          ),
        ),
      ],
    );
  });

  // -------------------------------------------------------------------------
  // 6. 任务（列表 + 输出面板）
  // -------------------------------------------------------------------------
  shotPair('任务', (tester, brightness) async {
    final api = FakeTasksApi(jobs: demoCronJobs())
      ..outputResponse = demoCronOutput();
    await capturePage(
      tester,
      name: 'tasks',
      location: '/tasks',
      brightness: brightness,
      overrides: [tasksApiFactoryProvider.overrideWithValue((_) => api)],
      interact: (tester) async {
        await tester.tap(find.text('Hermes 仓 CI 巡检'));
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
  });

  // 6b. 任务 · 宽屏右栏输出常驻（批 4A · P4）：点**第二个**任务 → 左栏选中态换行、
  // 右栏内容跟着换（宽屏不弹 sheet，「切任务即换内容」的直接对照图）。
  shotPair('任务 · 宽屏输出常驻', (tester, brightness) async {
    final api = _PerJobOutputTasksApi(jobs: demoCronJobs());
    await capturePage(
      tester,
      name: 'tasks-wide-output',
      location: '/tasks',
      brightness: brightness,
      overrides: [tasksApiFactoryProvider.overrideWithValue((_) => api)],
      interact: (tester) async {
        await tester.tap(
          find.text('用量周报（近 7 天 token / 成本）'),
        );
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 7. 下载（固定状态列表：排队中 / 下载中带进度 / 已完成 / 失败）
  // -------------------------------------------------------------------------
  shotPair('下载', (tester, brightness) async {
    // 已完成条目要有真实落盘文件，否则页面显示「文件已被移动或删除」。
    final dir = Directory.systemTemp.createTempSync('pages_shots_downloads_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    File('${dir.path}${Platform.pathSeparator}analyze-summary.txt')
        .writeAsStringSync('hermes-ui CI 巡检摘要：7 job 全绿，耗时 12m18s\n');
    File('${dir.path}${Platform.pathSeparator}wide-insights.png')
        .writeAsBytesSync(List<int>.filled(512, 7));
    final tasks = demoDownloadTasks(completedDir: dir.path);
    await capturePage(
      tester,
      name: 'downloads',
      location: '/downloads',
      brightness: brightness,
      overrides: [
        // 固定状态注入：不启动真实队列（不碰 drift / 临时目录 / 平台插件）。
        downloadControllerProvider.overrideWith(
          () => _DemoDownloadController(tasks),
        ),
        downloadTasksProvider.overrideWithValue(tasks),
        activeDownloadsCountProvider.overrideWithValue(2),
      ],
    );
  });

  // -------------------------------------------------------------------------
  // 8. Git（变更列表 + 展开 diff）
  // -------------------------------------------------------------------------
  shotPair('Git', (tester, brightness) async {
    final api = FakeGitApi()
      ..statusResponse = demoGitStatus()
      ..diffResponse = demoGitDiff()
      ..branchesResponse = demoGitBranches();
    await capturePage(
      tester,
      name: 'git',
      location: '/git/$_demoSessionId',
      brightness: brightness,
      overrides: [gitApiFactoryProvider.overrideWithValue((_) => api)],
      interact: (tester) async {
        await tester.tap(find.text(_demoDiffFilePath));
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  // 批 4 · P9：宽屏双栏「左 380 变更列表（四段）+ 右 diff 铺满」。
  shotPair('Git · 宽屏双栏 diff 右栏', (tester, brightness) async {
    final api = FakeGitApi()
      ..statusResponse = demoGitStatus()
      ..diffResponse = demoGitDiff()
      ..branchesResponse = demoGitBranches();
    await capturePage(
      tester,
      name: 'git-wide-split',
      location: '/git/$_demoSessionId',
      brightness: brightness,
      overrides: [gitApiFactoryProvider.overrideWithValue((_) => api)],
      interact: (tester) async {
        // 点变更行 = diff 进右栏（左栏不再内联展开，四段结构同屏可读）。
        await tester.tap(find.text(_demoDiffFilePath));
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 9. 诊断（分段 + 日志表）
  // -------------------------------------------------------------------------
  shotPair('诊断', (tester, brightness) async {
    final service = await demoDiagnosticsService();
    await capturePage(
      tester,
      name: 'diagnostics',
      location: '/diagnostics',
      brightness: brightness,
      overrides: [diagnosticsServiceProvider.overrideWithValue(service)],
      interact: (tester) async {
        // 让诊断服务 500ms 防抖落库计时器结算，避免测试尾挂起 Timer。
        await tester.pump(const Duration(milliseconds: 700));
      },
    );
    service.clearMemoryOnly();
  });

  // -------------------------------------------------------------------------
  // 9b. 诊断 · 批 4C 宽屏改造补图（左栏筛选选中态 / 详情在右栏内展开）
  // -------------------------------------------------------------------------
  shotPair('诊断 · 左栏筛选选中态', (tester, brightness) async {
    final service = await demoDiagnosticsService();
    await capturePage(
      tester,
      name: 'diagnostics-level-filter',
      location: '/diagnostics',
      brightness: brightness,
      overrides: [diagnosticsServiceProvider.overrideWithValue(service)],
      interact: (tester) async {
        // 让诊断服务 500ms 防抖落库计时器结算，避免测试尾挂起 Timer。
        await tester.pump(const Duration(milliseconds: 700));
        // 撤掉 V / D / I，只留 W / E：未选中的级别必须回到灰底灰字
        // （chips 的既有显色规则「选中才显级别色」搬进左栏后不变）。
        for (final code in ['V', 'D', 'I']) {
          await tester.tap(find.byKey(ValueKey('diagnostics-nav-level-$code')));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 700));
      },
    );
    service.clearMemoryOnly();
  });

  shotPair('诊断 · 详情在右栏内展开', (tester, brightness) async {
    final service = await demoDiagnosticsService();
    await capturePage(
      tester,
      name: 'diagnostics-detail',
      location: '/diagnostics',
      brightness: brightness,
      overrides: [diagnosticsServiceProvider.overrideWithValue(service)],
      interact: (tester) async {
        await tester.pump(const Duration(milliseconds: 700));
        // 宽屏点日志行 → 详情在右栏内展开（不再整页 push）。
        await tester.tap(
          find.text('GET /api/workspace/download → 断流（已自动重试 1 次）'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
      },
    );
    service.clearMemoryOnly();
  });

  // -------------------------------------------------------------------------
  // 10. 提示词
  // -------------------------------------------------------------------------
  shotPair('提示词', (tester, brightness) async {
    await capturePage(
      tester,
      name: 'prompts',
      location: '/prompts',
      brightness: brightness,
      overrides: [
        promptsApiFactoryProvider.overrideWithValue(
          (_) => FakePromptsApi(initialPrompts: demoSavedPrompts()),
        ),
      ],
    );
  });

  // -------------------------------------------------------------------------
  // 11. 统计（指标 Bento + 图表两列 —— 批 2 P7）
  // -------------------------------------------------------------------------
  shotPair('统计', (tester, brightness) async {
    await capturePage(
      tester,
      name: 'insights',
      location: '/insights',
      brightness: brightness,
      overrides: [
        insightsApiFactoryProvider.overrideWithValue(
          (_) => FakeInsightsApi(response: demoInsightsResponse()),
        ),
      ],
    );
  });

  // -------------------------------------------------------------------------
  // 12. 看板（看板视图 + 卡片详情 —— 批 2 P8）
  // -------------------------------------------------------------------------
  shotPair('看板', (tester, brightness) async {
    final api = demoKanbanApi();
    addTearDown(api.dispose);
    await capturePage(
      tester,
      name: 'kanban',
      location: '/kanban',
      brightness: brightness,
      overrides: [kanbanApiFactoryProvider.overrideWithValue((_) => api)],
    );
  });

  shotPair('看板 · 卡片详情', (tester, brightness) async {
    final api = demoKanbanApi();
    addTearDown(api.dispose);
    await capturePage(
      tester,
      name: 'kanban-detail',
      location: '/kanban',
      brightness: brightness,
      overrides: [kanbanApiFactoryProvider.overrideWithValue((_) => api)],
      interact: (tester) async {
        await tester.tap(find.byKey(const ValueKey('kanban-card-kb-2')));
        await tester.pumpAndSettle();
      },
    );
  });

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);
}

/// 更新检查 no-op：设置页「关于」组会起一次静默检查，默认实现会真发
/// GitHub 请求（测试纪律：不出网；且失败日志会污染输出）。这里只关掉网络，
/// 其余（已是最新）语义保持真实。
class _DemoUpdateChecker extends UpdateCheckerService {
  @override
  Future<bool> isAutoCheckEnabled() async => true;

  @override
  Future<UpdateCheckResult> checkForUpdates({
    bool isManual = false,
    DateTime? now,
  }) async => UpdateCheckResult.skippedThrottled(currentVersion: '0.1.51+57');
}

/// 产物根目录（相对本文件：test/screenshots/ → 仓库根 .shots）。
const String _shotRoot = '../../.shots';

/// 工装环境变量：UI_SCALE=x125 / x150 / x2（缺省或非法 => 100%）。
AppUiScale get _envUiScale {
  final raw = Platform.environment['UI_SCALE'];
  for (final scale in AppUiScale.values) {
    if (scale.name == raw) return scale;
  }
  return AppUiScale.x1;
}

/// 把缩放档位钉到环境变量（不读 prefs、不持久化）——仅供出图工装使用。
class _EnvUiScale extends UiScaleController {
  _EnvUiScale(this.scale);

  final AppUiScale scale;

  @override
  AppUiScale build() => scale;
}
