import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/insights.dart';
import 'package:hermes_ui/core/models/kanban.dart';
import 'package:hermes_ui/core/models/session.dart';
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
import '../helpers/fake_chat_api.dart';
import '../helpers/fake_insights_api.dart';
import '../helpers/fake_kanban_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// README 截图工装（非金照基线，不参与 CI 比对）
//
// 用法：README_SHOTS=1 C:/tmp/f.bat test test/screenshots/readme_shots_test.dart
// 产物：docs/screenshots/*.png（浅色，宽屏 2560×1600 / 窄屏 780×1688）
//
// 与金照同源的真字体（MiSans）与 fake 数据，但页面在 AdaptiveShell 外壳内
// 组装，还原真实导航形态；数据全部为演示文案，无真实隐私。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip，CI / 日常 flutter test 零影响。
final bool _capture = Platform.environment['README_SHOTS'] == '1';
const String _skipReason = '设置 README_SHOTS=1 才生成 README 截图';

/// 产物目录（仓库根下，README 相对引用）。
const String _outDir = 'docs/screenshots';

/// 演示用激活连接（域名用 example 保留域，无真实主机）。
Future<ConnectionStore> demoConnectionStore() async {
  final storage = InMemorySecureStorage();
  final store = ConnectionStore(storage: storage);
  await store.save(
    ServerConnection(
      id: 'c1',
      name: 'Home 服务器',
      baseUrl: 'https://hermes.example.com:8787',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');
  return store;
}

/// 演示会话列表数据（中性文案，固定时钟防漂移）。
FakeSessionListApi demoSessionApi() {
  final fixed = DateTime(2026, 9, 12, 12, 0);
  double at(Duration ago) =>
      fixed.subtract(ago).millisecondsSinceEpoch / 1000.0;
  return FakeSessionListApi(
    sessions: [
      SessionSummary(
        sessionId: 's-demo-1',
        title: '产品发布计划：多平台体验统一路线图',
        pinned: true,
        messageCount: 23,
        projectId: 'p-demo-hermes',
        workspace: r'D:\projects\hermes-ui',
        lastMessageAt: at(const Duration(minutes: 30)),
      ),
      SessionSummary(
        sessionId: 's-demo-2',
        title: '帮我写一段 Python 数据清洗脚本',
        messageCount: 8,
        workspace: r'D:\data\etl',
        lastMessageAt: at(const Duration(hours: 1)),
      ),
      SessionSummary(
        sessionId: 's-demo-3',
        title: '本周行业资讯汇总与摘要',
        messageCount: 5,
        projectId: 'p-demo-reading',
        lastMessageAt: at(const Duration(hours: 3)),
      ),
      SessionSummary(
        sessionId: 's-demo-4',
        title: 'Flutter 深色模式对比度优化建议',
        messageCount: 41,
        projectId: 'p-demo-hermes',
        workspace: r'D:\projects\hermes-ui',
        lastMessageAt: at(const Duration(days: 1, hours: 2)),
      ),
      SessionSummary(
        sessionId: 's-demo-5',
        title: '旅行攻略：周末短途行程规划',
        messageCount: 12,
        projectId: 'p-demo-reading',
        lastMessageAt: at(const Duration(days: 2)),
      ),
      SessionSummary(
        sessionId: 's-demo-6',
        title: '英文邮件润色与语气调整',
        messageCount: 3,
        lastMessageAt: at(const Duration(days: 5)),
      ),
    ],
  );
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
          date: DateTime(2026, 8, 19)
              .add(Duration(days: i))
              .toIso8601String()
              .substring(0, 10),
          inputTokens: inp(i),
          outputTokens: outp(i),
          sessions: 3 + i % 7,
          cost: 0.02 + i * 0.01,
        ),
    ],
    activityByDay: const [InsightsActivityByDay(day: '2026-09-06', sessions: 10)],
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
    pinGoldenLocale();
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

    // matchesGoldenFile + --update-goldens 负责写盘（路径相对本文件目录）。
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('../../$_outDir/$name.png'),
    );
  }

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);

  testWidgets('宽屏 · 聊天（hero）', (tester) async {
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's-demo-1',
        'title': '产品发布计划：多平台体验统一路线图',
        'messages': [
          {
            'role': 'user',
            'content': '帮我梳理一下 Hermes 客户端下个月的发布重点，'
                '并给出 Android 侧的验证清单。',
            'message_id': 'u1',
          },
          {
            'role': 'assistant',
            'content':
                '**下月发布重点**\n\n'
                '1. 内置服务体验打磨：首连成功率与冷启动宽限\n'
                '2. 会话时间线一致性：思考与工具卡片穿插\n'
                '3. Android 后台通知：回合完成直达会话\n\n'
                '```bash\n'
                'flutter build apk --release \\\n'
                '  --target-platform android-arm64\n'
                '```\n\n'
                '验证清单已同步到看板「发布准备」列，共 8 项。',
            'message_id': 'a1',
          },
        ],
      },
    };
    await captureShellShot(
      tester,
      name: 'wide-chat',
      location: '/chat/s-demo-1',
      physicalSize: const Size(2560, 1600),
      overrides: [
        chatApiProvider.overrideWithValue(api),
        sessionListApiFactoryProvider.overrideWithValue((_) => demoSessionApi()),
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
        sessionListApiFactoryProvider.overrideWithValue((_) => demoSessionApi()),
      ],
    );
  }, skip: !_capture);

  testWidgets('宽屏 · 看板', (tester) async {
    final api = FakeKanbanApi(
      boards: const [KanbanBoard(slug: 'default', name: '发布计划')],
      currentSlug: 'default',
      snapshots: {
        'default': const KanbanBoardSnapshot(
          columns: [
            KanbanColumn(
              name: 'todo',
              cards: [
                KanbanCard(
                  cardID: 'c1',
                  title: '首连宽限状态机复盘',
                  status: KanbanStatus('todo'),
                  assignee: 'dev-a',
                ),
                KanbanCard(
                  cardID: 'c2',
                  title: 'Android 通知点击直达深链验证',
                  status: KanbanStatus('todo'),
                  assignee: 'dev-b',
                ),
              ],
            ),
            KanbanColumn(
              name: 'ready',
              cards: [
                KanbanCard(
                  cardID: 'c3',
                  title: '时间线卡片穿插回归',
                  status: KanbanStatus('ready'),
                  assignee: 'dev-a',
                ),
              ],
            ),
            KanbanColumn(
              name: 'done',
              cards: [
                KanbanCard(
                  cardID: 'c4',
                  title: '柱状图 X 轴标签重叠修复',
                  status: KanbanStatus('done'),
                  linkCounts: KanbanLinkCounts(parents: 1),
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
        sessionListApiFactoryProvider.overrideWithValue((_) => demoSessionApi()),
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
        sessionListApiFactoryProvider.overrideWithValue((_) => demoSessionApi()),
      ],
    );
  }, skip: !_capture);

  testWidgets('窄屏 · 聊天', (tester) async {
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's-demo-2',
        'title': 'Python 数据清洗脚本',
        'messages': [
          {
            'role': 'user',
            'content': '写一个 pandas 去重并按日期排序的清洗脚本。',
            'message_id': 'u1',
          },
          {
            'role': 'assistant',
            'content':
                '好的，核心逻辑如下：\n\n'
                '```python\n'
                'df = (df.drop_duplicates(subset=["id"])\n'
                '        .sort_values("date"))\n'
                '```\n\n'
                '需要先安装 pandas：\n\n'
                '```bash\npip install pandas\n```\n\n'
                '运行后会输出清洗前后行数对比。',
            'message_id': 'a1',
          },
        ],
      },
    };
    await captureShellShot(
      tester,
      name: 'phone-chat',
      location: '/chat/s-demo-2',
      physicalSize: const Size(780, 1688),
      overrides: [
        chatApiProvider.overrideWithValue(api),
        sessionListApiFactoryProvider.overrideWithValue((_) => demoSessionApi()),
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
        sessionListApiFactoryProvider.overrideWithValue((_) => demoSessionApi()),
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
                InsightsDailyToken(date: '2026-09-05', inputTokens: 420000, outputTokens: 52000, sessions: 6),
                InsightsDailyToken(date: '2026-09-06', inputTokens: 380000, outputTokens: 49000, sessions: 5),
                InsightsDailyToken(date: '2026-09-07', inputTokens: 510000, outputTokens: 61000, sessions: 8),
                InsightsDailyToken(date: '2026-09-08', inputTokens: 300000, outputTokens: 38000, sessions: 4),
                InsightsDailyToken(date: '2026-09-09', inputTokens: 460000, outputTokens: 55000, sessions: 7),
                InsightsDailyToken(date: '2026-09-10', inputTokens: 520000, outputTokens: 63000, sessions: 9),
                InsightsDailyToken(date: '2026-09-11', inputTokens: 610000, outputTokens: 72000, sessions: 10),
              ],
              activityByDay: [InsightsActivityByDay(day: '2026-09-11', sessions: 10)],
              activityByHour: [InsightsActivityByHour(hour: 21, sessions: 4)],
            ),
          ),
        ),
        sessionListApiFactoryProvider.overrideWithValue((_) => demoSessionApi()),
      ],
    );
  }, skip: !_capture);
}

/// 项目 API 空 stub（会话列表 watch 项目 chips，避免真实请求）。
class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(
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
  Future<ProjectMutationResponse> deleteProject(
    String projectId,
  ) async => const ProjectMutationResponse(ok: true);
}
