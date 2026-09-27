import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/insights.dart';
import 'package:hermes_ui/core/models/kanban.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/insights/insights_api.dart';
import 'package:hermes_ui/features/insights/insights_page.dart';
import 'package:hermes_ui/features/kanban/kanban_page.dart';
import 'package:hermes_ui/features/kanban/kanban_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';

import 'package:hermes_ui/features/settings/perf_monitor_settings.dart';

import '../helpers/fake_chat_api.dart';
import '../helpers/fake_system_health.dart';
import '../helpers/fake_insights_api.dart';
import '../helpers/fake_kanban_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// README 截图工装（非金照基线，不参与 CI 比对）
//
// 用法：README_SHOTS=1 [README_DARK=1] [README_LANG=en] C:/tmp/f.bat test
//         test/screenshots/readme_shots_test.dart --update-goldens
// 产物：中文（默认，路径不变）docs/screenshots/*.png；英文 README_LANG=en 落
//       docs/screenshots/en/*.png。浅色原名；README_DARK=1 出暗色 *-dark.png；
//       宽屏 2560×1600 / 窄屏 780×1688
//
// 双语各出一整套：界面文案由 locale 驱动，演示数据（会话标题/聊天正文/看板卡片/
// 项目名/连接名）按语言给两套中性文案——英文 README 不得出现中文界面。
//
// 与金照同源的真字体（MiSans）与 fake 数据，但页面在 AdaptiveShell 外壳内
// 组装，还原真实导航形态；数据全部为演示文案，无真实隐私。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip，CI / 日常 flutter test 零影响。
final bool _capture = Platform.environment['README_SHOTS'] == '1';
const String _skipReason = '设置 README_SHOTS=1 才生成 README 截图';

/// README_DARK=1 时输出暗色主题套件（文件名加 -dark 后缀）。
final bool _dark = Platform.environment['README_DARK'] == '1';

/// README_LANG=en 时出英文套件（界面 locale 与演示数据双切换）。
final bool _en = Platform.environment['README_LANG'] == 'en';

/// 当前套件语言模式：同时喂 LocaleResolver，保证 widget 树外文案同语言。
final AppLocaleMode _localeMode = _en ? AppLocaleMode.en : AppLocaleMode.zh;

/// 产物目录（仓库根下，README 相对引用）；英文套件落 en/ 子目录，中文路径不变。
final String _outDir = _en ? 'docs/screenshots/en' : 'docs/screenshots';

/// 演示会话标题（zh / en 两套中性文案，下标与 [demoSessionApi] 顺序一致）。
const List<String> _demoTitlesZh = [
  '产品发布计划：多平台体验统一路线图',
  '帮我写一段 Python 数据清洗脚本',
  '本周行业资讯汇总与摘要',
  'Flutter 深色模式对比度优化建议',
  '旅行攻略：周末短途行程规划',
  '英文邮件润色与语气调整',
];

const List<String> _demoTitlesEn = [
  'Product launch plan: unified multi-platform roadmap',
  'Write a Python data-cleaning script',
  'Weekly industry roundup and summary',
  'Flutter dark-mode contrast review',
  'Weekend short-trip travel plan',
  'Polishing an English email and tuning the tone',
];

/// 当前套件的演示会话标题。
List<String> get _demoTitles => _en ? _demoTitlesEn : _demoTitlesZh;

/// 演示用激活连接（域名用 example 保留域，无真实主机）。
Future<ConnectionStore> demoConnectionStore() async {
  final storage = InMemorySecureStorage();
  final store = ConnectionStore(storage: storage);
  await store.save(
    ServerConnection(
      id: 'c1',
      name: _en ? 'Home server' : 'Home 服务器',
      baseUrl: 'https://hermes.example.com:8787',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');
  return store;
}

/// 演示会话列表数据（中性文案，固定时钟防漂移）。
/// #145：侧栏工作区选择器与输入区元信息 chip 都要读目录数据。截图工装注入
/// 一份固定清单，否则组件遇空列表会自渲染为零尺寸——图里看不到它们。
final demoWorkspaceOverrides = <Override>[
  workspaceRootsProvider.overrideWith(
    (ref) => Future.value(const [
      WorkspaceRoot(path: r'D:\projects\hermes-ui', name: 'hermes-ui'),
      WorkspaceRoot(path: r'D:\projects\book-hub', name: 'book-hub'),
    ]),
  ),
  availableModelIdsProvider.overrideWith(
    (ref) => Future.value(const ['claude-opus-4.6', 'gemini-3.8-flash-high']),
  ),
];

FakeSessionListApi demoSessionApi() {
  final fixed = DateTime(2026, 9, 12, 12, 0);
  double at(Duration ago) =>
      fixed.subtract(ago).millisecondsSinceEpoch / 1000.0;
  return FakeSessionListApi(
    sessions: [
      SessionSummary(
        sessionId: 's-demo-1',
        title: _demoTitles[0],
        pinned: true,
        messageCount: 23,
        projectId: 'p-demo-hermes',
        workspace: r'D:\projects\hermes-ui',
        lastMessageAt: at(const Duration(minutes: 30)),
      ),
      SessionSummary(
        sessionId: 's-demo-2',
        title: _demoTitles[1],
        messageCount: 8,
        workspace: r'D:\data\etl',
        lastMessageAt: at(const Duration(hours: 1)),
      ),
      SessionSummary(
        sessionId: 's-demo-3',
        title: _demoTitles[2],
        messageCount: 5,
        projectId: 'p-demo-reading',
        lastMessageAt: at(const Duration(hours: 3)),
      ),
      SessionSummary(
        sessionId: 's-demo-4',
        title: _demoTitles[3],
        messageCount: 41,
        projectId: 'p-demo-hermes',
        workspace: r'D:\projects\hermes-ui',
        lastMessageAt: at(const Duration(days: 1, hours: 2)),
      ),
      SessionSummary(
        sessionId: 's-demo-5',
        title: _demoTitles[4],
        messageCount: 12,
        projectId: 'p-demo-reading',
        lastMessageAt: at(const Duration(days: 2)),
      ),
      SessionSummary(
        sessionId: 's-demo-6',
        title: _demoTitles[5],
        messageCount: 3,
        lastMessageAt: at(const Duration(days: 5)),
      ),
    ],
  );
}

/// 演示聊天会话（zh / en 两套）。
///
/// 刻意给足内容，否则截图工装里的「演示图」看不出真实观感：
/// - **正文要长**：标题 / 列表 / 表格 / 代码块都用上，宽屏右侧才有东西可看；
/// - **上下文要有值**：喂 context_length / last_prompt_tokens 等 ⇒ 底栏上下文
///   指示器环上有百分比（124000 / 200000 = 62%），不再是空「·」；
/// - 消息条数 ≥ 4，两轮问答，接近真实会话。
Map<String, Object?> demoChatSessionJson({required bool en}) {
  return {
    'session': {
      'session_id': 's-demo-1',
      'title': _demoTitles[0],
      // 让输入区 chip 显示真实值（而非虚线空态）。
      'workspace': r'D:\projects\hermes-ui',
      'model': 'claude-opus-4.6',
      // 上下文用量：62%（指示器环上直接可见）。
      'context_length': 200000,
      'threshold_tokens': 160000,
      'last_prompt_tokens': 124000,
      'input_tokens': 128400,
      'output_tokens': 24600,
      'estimated_cost': 0.86,
      'message_count': 4,
      'messages': [
        {
          'role': 'user',
          'content': en
              ? 'Lay out next month\'s release priorities for the Hermes '
                    'client, plus an Android verification checklist.\n\n'
                    'Context: the built-in service just shipped and its '
                    'first-connect rate is still flaky; the session timeline '
                    'has been reworked twice.'
              : '帮我梳理一下 Hermes 客户端下个月的发布重点，并给出 Android 侧的\n'
                    '验证清单。\n\n'
                    '背景：内置服务刚上线，首连成功率还不稳；会话时间线最近改过两轮。',
          'message_id': 'u1',
        },
        {
          'role': 'assistant',
          'content': en
              ? '## Next month\'s priorities\n\n'
                    '**In one line**: harden the *first-connect* and '
                    '*turn-timeline* paths, everything else is small fixes.\n\n'
                    '### 1. Built-in service\n'
                    '- Cold-start grace window: 4s → 6s, probe every 500ms\n'
                    '- Port 8787 busy: fall back to the next free port and '
                    'show the real port in Settings\n'
                    '- New "service self-check" entry: agent / model / port '
                    'in one pass\n\n'
                    '### 2. Turn timeline consistency\n\n'
                    '| Case | Today | Target |\n'
                    '| --- | --- | --- |\n'
                    '| Thinking and tool cards interleaved | occasionally '
                    'out of order | strictly event-time order |\n'
                    '| Paging up in long sessions | viewport jumps | anchor '
                    'stays put |\n\n'
                    '### 3. Android background notifications\n\n'
                    '```bash\n'
                    'flutter build apk --release \\\\\n'
                    '  --target-platform android-arm64\n'
                    '```\n\n'
                    'Tapping a notification must land on the right session; '
                    'if the permission is denied, degrade to an in-app hint — '
                    'never fail silently.\n\n'
                    'The checklist is synced to the "Release prep" column on '
                    'the board — **8 items**.'
              : '## 下月发布重点\n\n'
                    '**一句话**：把「首次连接」与「回合时间线」两条链路磨稳，'
                    '其余只做小修。\n\n'
                    '### 1. 内置服务体验\n'
                    '- 首连成功率：冷启动宽限 4s → 6s，探活间隔 500ms\n'
                    '- 端口占用：8787 被占时自动顺延，并在设置页显示实际端口\n'
                    '- 自检入口：设置页新增「服务自检」，一次跑通 agent / '
                    '模型 / 端口三项\n\n'
                    '### 2. 会话时间线一致性\n\n'
                    '| 场景 | 现状 | 目标 |\n'
                    '| --- | --- | --- |\n'
                    '| 思考卡与工具卡穿插 | 偶发顺序倒置 | 严格按事件时间线 |\n'
                    '| 长会话上滚分页 | 视口跳动 | 锚点稳定不跳 |\n\n'
                    '### 3. Android 后台通知\n\n'
                    '```bash\n'
                    'flutter build apk --release \\\\\n'
                    '  --target-platform android-arm64\n'
                    '```\n\n'
                    '通知点击必须直达对应会话；权限被拒时降级为应用内提示，'
                    '不能静默失败。\n\n'
                    '验证清单已同步到看板「发布准备」列，共 **8 项**。',
          'message_id': 'a1',
        },
        {
          'role': 'user',
          'content': en
              ? 'Sort the checklist by priority — I need to assign people.'
              : '验证清单按优先级排一下，我安排人手。',
          'message_id': 'u2',
        },
        {
          'role': 'assistant',
          'content': en
              ? 'Sorted: **P0** first-connect grace window, notification '
                    'deep-link, timeline ordering (3 items); **P1** paging '
                    'anchor, self-check entry, port fallback (3 items); '
                    '**P2** copy and icon polish (2 items). The board column '
                    'is updated.'
              : '已按优先级排好：**P0** 首连宽限、通知直达、时间线顺序（3 项）；'
                    '**P1** 分页锚点、自检入口、端口顺延（3 项）；'
                    '**P2** 文案与图标打磨（2 项）。看板列已更新。',
          'message_id': 'a2',
        },
      ],
    },
  };
}

/// 演示用量数据：30 天周期、21 根柱（覆盖图表截取窗口 14 根，标签
/// 抽稀逻辑同时受验），数值勾稽自洽（输入+输出=总）。
InsightsResponse demoInsights() {
  int inp(int i) => 300000 + ((i * 97) % 5) * 60000;
  int outp(int i) => 40000 + ((i * 53) % 4) * 9000;
  return InsightsResponse(
    periodDays: 30,
    totalSessions: 68,
    totalMessages: 1420,
    totalInputTokens: 8600000,
    totalOutputTokens: 1240000,
    totalTokens: 9840000,
    totalCost: 4.86,
    totalCacheReadTokens: 2400000,
    totalCacheHitPercent: 62.5,
    models: const [
      InsightsModelBreakdown(
        model: 'demo-model-A',
        totalTokens: 6400000,
        tokenShare: 65,
      ),
      InsightsModelBreakdown(
        model: 'demo-model-B',
        totalTokens: 3440000,
        tokenShare: 35,
      ),
    ],
    // 页面取数组尾部 14 条为「近 14 天」窗口并反转绘制（新在左），
    // 故这里按日期升序给 21 天，尾部即最新。
    dailyTokens: [
      for (var i = 0; i < 21; i++)
        InsightsDailyToken(
          date: DateTime(
            2026,
            8,
            19,
          ).add(Duration(days: i)).toIso8601String().substring(0, 10),
          inputTokens: inp(i),
          outputTokens: outp(i),
          sessions: 3 + i % 7,
          cost: 0.02 + i * 0.01,
        ),
    ],
    activityByDay: const [
      InsightsActivityByDay(day: '2026-09-06', sessions: 10),
    ],
    activityByHour: const [InsightsActivityByHour(hour: 21, sessions: 4)],
  );
}

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 以 [location] 为初始路由挂载 AdaptiveShell 全壳并截图到 [name]。
  Future<void> captureShellShot(
    WidgetTester tester, {
    required String name,
    required String location,
    required Size physicalSize,
    List<Override> overrides = const [],
  }) async {
    LocaleResolver.reset(mode: _localeMode);
    tester.view.physicalSize = physicalSize;
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
              path: '/chat/:sessionId',
              builder: (context, state) =>
                  ChatPage(sessionId: state.pathParameters['sessionId'] ?? ''),
            ),
            GoRoute(
              path: '/kanban',
              builder: (context, state) => const KanbanPage(),
            ),
            GoRoute(
              path: '/insights',
              builder: (context, state) => const InsightsPage(),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'https://hermes.example.com:8787'),
          ),
          // 会话行副标题需要项目名（projectId→name），统一喂 stub 避免真实请求。
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
          ...overrides,
        ],
        child: CupertinoApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(
            _dark ? Brightness.dark : Brightness.light,
          ),
          locale: _en ? const Locale('en') : const Locale('zh'),
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

    // matchesGoldenFile + --update-goldens 负责写盘（路径相对本文件目录）。
    // 暗色套件加 -dark 后缀，与浅色互不覆盖。
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('../../$_outDir/$name${_dark ? '-dark' : ''}.png'),
    );
  }

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);

  testWidgets('宽屏 · 聊天（hero）', (tester) async {
    // 性能监控面板要开关 + 数据才占位；截图工装喂固定系统指标。
    SharedPreferences.setMockInitialValues({kShowPerfMonitorKey: true});
    final api = FakeChatApi()..sessionResult = demoChatSessionJson(en: _en);
    await captureShellShot(
      tester,
      name: 'wide-chat',
      location: '/chat/s-demo-1',
      physicalSize: const Size(2560, 1600),
      overrides: [
        chatApiProvider.overrideWithValue(api),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => demoSessionApi(),
        ),
        apiClientProvider.overrideWithValue(buildSystemHealthApiClient()),
        ...demoWorkspaceOverrides,
      ],
    );
  }, skip: !_capture);

  testWidgets('宽屏 · 会话列表', (tester) async {
    await captureShellShot(
      tester,
      name: 'wide-sessions',
      location: '/',
      physicalSize: const Size(2560, 1600),
      overrides: [
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => demoSessionApi(),
        ),
        ...demoWorkspaceOverrides,
      ],
    );
  }, skip: !_capture);

  testWidgets('宽屏 · 看板', (tester) async {
    final api = FakeKanbanApi(
      boards: [
        KanbanBoard(slug: 'default', name: _en ? 'Release plan' : '发布计划'),
      ],
      currentSlug: 'default',
      snapshots: {
        'default': KanbanBoardSnapshot(
          columns: [
            KanbanColumn(
              name: 'todo',
              cards: [
                KanbanCard(
                  cardID: 'c1',
                  title: _en
                      ? 'First-connect grace state machine review'
                      : '首连宽限状态机复盘',
                  status: const KanbanStatus('todo'),
                  assignee: 'dev-a',
                ),
                KanbanCard(
                  cardID: 'c2',
                  title: _en
                      ? 'Verify Android notification deep-link'
                      : 'Android 通知点击直达深链验证',
                  status: const KanbanStatus('todo'),
                  assignee: 'dev-b',
                ),
              ],
            ),
            KanbanColumn(
              name: 'ready',
              cards: [
                KanbanCard(
                  cardID: 'c3',
                  title: _en
                      ? 'Timeline card interleaving regression'
                      : '时间线卡片穿插回归',
                  status: const KanbanStatus('ready'),
                  assignee: 'dev-a',
                ),
              ],
            ),
            KanbanColumn(
              name: 'done',
              cards: [
                KanbanCard(
                  cardID: 'c4',
                  title: _en
                      ? 'Fix overlapping chart X-axis labels'
                      : '柱状图 X 轴标签重叠修复',
                  status: const KanbanStatus('done'),
                  linkCounts: const KanbanLinkCounts(parents: 1),
                ),
              ],
            ),
          ],
        ),
      },
    );
    await captureShellShot(
      tester,
      name: 'wide-kanban',
      location: '/kanban',
      physicalSize: const Size(2560, 1600),
      overrides: [
        kanbanApiFactoryProvider.overrideWithValue((_) => api),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => demoSessionApi(),
        ),
        ...demoWorkspaceOverrides,
      ],
    );
  }, skip: !_capture);

  testWidgets('宽屏 · 用量统计', (tester) async {
    await captureShellShot(
      tester,
      name: 'wide-insights',
      location: '/insights',
      physicalSize: const Size(2560, 1600),
      overrides: [
        insightsApiFactoryProvider.overrideWithValue(
          (_) => FakeInsightsApi(response: demoInsights()),
        ),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => demoSessionApi(),
        ),
        ...demoWorkspaceOverrides,
      ],
    );
  }, skip: !_capture);

  testWidgets('窄屏 · 聊天', (tester) async {
    // 与宽屏**共用同一份丰富演示数据**：主人要按同内容比对窄屏是否受影响。
    SharedPreferences.setMockInitialValues({kShowPerfMonitorKey: true});
    final api = FakeChatApi()..sessionResult = demoChatSessionJson(en: _en);
    await captureShellShot(
      tester,
      name: 'phone-chat',
      location: '/chat/s-demo-1',
      physicalSize: const Size(780, 1688),
      overrides: [
        chatApiProvider.overrideWithValue(api),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => demoSessionApi(),
        ),
        apiClientProvider.overrideWithValue(buildSystemHealthApiClient()),
        ...demoWorkspaceOverrides,
      ],
    );
  }, skip: !_capture);

  testWidgets('窄屏 · 会话列表', (tester) async {
    await captureShellShot(
      tester,
      name: 'phone-sessions',
      location: '/',
      physicalSize: const Size(780, 1688),
      overrides: [
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => demoSessionApi(),
        ),
        ...demoWorkspaceOverrides,
      ],
    );
  }, skip: !_capture);

  testWidgets('窄屏 · 用量统计', (tester) async {
    await captureShellShot(
      tester,
      name: 'phone-insights',
      location: '/insights',
      physicalSize: const Size(780, 1688),
      overrides: [
        insightsApiFactoryProvider.overrideWithValue(
          (_) => FakeInsightsApi(
            response: const InsightsResponse(
              periodDays: 30,
              totalSessions: 68,
              totalMessages: 1420,
              totalInputTokens: 8600000,
              totalOutputTokens: 1240000,
              totalTokens: 9840000,
              totalCost: 4.86,
              totalCacheReadTokens: 2400000,
              totalCacheHitPercent: 62.5,
              models: [
                InsightsModelBreakdown(
                  model: 'demo-model-A',
                  totalTokens: 6400000,
                  tokenShare: 65,
                ),
                InsightsModelBreakdown(
                  model: 'demo-model-B',
                  totalTokens: 3440000,
                  tokenShare: 35,
                ),
              ],
              dailyTokens: [
                InsightsDailyToken(
                  date: '2026-09-05',
                  inputTokens: 420000,
                  outputTokens: 52000,
                  sessions: 6,
                ),
                InsightsDailyToken(
                  date: '2026-09-06',
                  inputTokens: 380000,
                  outputTokens: 49000,
                  sessions: 5,
                ),
                InsightsDailyToken(
                  date: '2026-09-07',
                  inputTokens: 510000,
                  outputTokens: 61000,
                  sessions: 8,
                ),
                InsightsDailyToken(
                  date: '2026-09-08',
                  inputTokens: 300000,
                  outputTokens: 38000,
                  sessions: 4,
                ),
                InsightsDailyToken(
                  date: '2026-09-09',
                  inputTokens: 460000,
                  outputTokens: 55000,
                  sessions: 7,
                ),
                InsightsDailyToken(
                  date: '2026-09-10',
                  inputTokens: 520000,
                  outputTokens: 63000,
                  sessions: 9,
                ),
                InsightsDailyToken(
                  date: '2026-09-11',
                  inputTokens: 610000,
                  outputTokens: 72000,
                  sessions: 10,
                ),
              ],
              activityByDay: [
                InsightsActivityByDay(day: '2026-09-11', sessions: 10),
              ],
              activityByHour: [InsightsActivityByHour(hour: 21, sessions: 4)],
            ),
          ),
        ),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => demoSessionApi(),
        ),
        ...demoWorkspaceOverrides,
      ],
    );
  }, skip: !_capture);
}

/// 项目 API 空 stub（会话列表 watch 项目 chips，避免真实请求）。
class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async => ProjectsResponse(
    projects: [
      const ProjectSummary(projectId: 'p-demo-hermes', name: 'Hermes'),
      ProjectSummary(projectId: 'p-demo-reading', name: _en ? 'Reading' : '读书'),
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
