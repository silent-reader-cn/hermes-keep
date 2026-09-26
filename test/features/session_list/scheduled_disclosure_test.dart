import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/features/session_list/scheduled_session_disclosure.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/settings/cron_visibility_settings.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';

import 'package:hermes_ui/app/shell/session_sidebar.dart';

/// #161：侧栏「定时任务」行带待办计数徽标 ⇒ `SidebarToolsList` 会 watch
/// `tasksJobCountProvider`（build 会真发 `fetchJobs`）。这些用例不关心任务数据，
/// 注入空任务避免真实请求留下 Dio 超时 timer（表现为 `!timersPending`）。
class _EmptyTasksController extends TasksController {
  @override
  Future<TasksState> build() async {
    ref.watch(tasksApiFactoryProvider);
    return const TasksState(jobs: <CronJob>[]);
  }
}

/// 秒级时间戳辅助（会话模型时间字段为 epoch 秒）。
double sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary buildSession(
  String id,
  String title, {
  bool pinned = false,
  DateTime? at,
  String? sourceLabel,
  String? workspace,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    workspace: workspace ?? '/ws/main',
    lastMessageAt: sec(at ?? DateTime.now()),
    sourceLabel: sourceLabel,
  );
}

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

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

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: Text(
          'ChatPage: $sessionId',
          key: const ValueKey('chat-page-stub'),
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScheduledSessionDisclosure 独立组件测试（已废弃组件向下兼容）', () {
    testWidgets('默认状态收起：展示标题、数量与折叠 chevron，不展示子项', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ScheduledSessionDisclosure(
              title: '定时',
              count: 3,
              children: [Text('会话 1'), Text('会话 2'), Text('会话 3')],
            ),
          ),
        ),
      );

      // 标题与数量展示
      expect(find.text('定时'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // 折叠图标 chevron_right
      expect(
        find.descendant(
          of: find.byType(ScheduledSessionDisclosure),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ScheduledSessionDisclosure),
          matching: find.byIcon(CupertinoIcons.chevron_down),
        ),
        findsNothing,
      );
      // 子项收起不展示
      expect(find.text('会话 1'), findsNothing);
      expect(find.text('会话 2'), findsNothing);
      expect(find.text('会话 3'), findsNothing);
      expect(
        find.byKey(const ValueKey('scheduled-disclosure-collapsed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scheduled-disclosure-section')),
        findsNothing,
      );
    });

    testWidgets('点击标题行 → 展开展示子项；再次点击 → 收起', (tester) async {
      final expansionEvents = <bool>[];

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ScheduledSessionDisclosure(
              title: '定时',
              count: 2,
              onExpansionChanged: expansionEvents.add,
              children: const [Text('会话 A'), Text('会话 B')],
            ),
          ),
        ),
      );

      // 初始收起
      expect(find.text('会话 A'), findsNothing);
      expect(find.text('会话 B'), findsNothing);

      // 点击展开
      await tester.tap(
        find.byKey(const ValueKey('scheduled-disclosure-header')),
      );
      await tester.pumpAndSettle();

      expect(expansionEvents, [true]);
      expect(
        find.descendant(
          of: find.byType(ScheduledSessionDisclosure),
          matching: find.byIcon(CupertinoIcons.chevron_down),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ScheduledSessionDisclosure),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsNothing,
      );
      expect(find.text('会话 A'), findsOneWidget);
      expect(find.text('会话 B'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('scheduled-disclosure-section')),
        findsOneWidget,
      );

      // 再次点击收起
      await tester.tap(
        find.byKey(const ValueKey('scheduled-disclosure-header')),
      );
      await tester.pumpAndSettle();

      expect(expansionEvents, [true, false]);
      expect(
        find.descendant(
          of: find.byType(ScheduledSessionDisclosure),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ScheduledSessionDisclosure),
          matching: find.byIcon(CupertinoIcons.chevron_down),
        ),
        findsNothing,
      );
      expect(find.text('会话 A'), findsNothing);
      expect(find.text('会话 B'), findsNothing);
    });

    testWidgets('支持 initialExpanded = true 初始化展开', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ScheduledSessionDisclosure(
              title: '定时',
              initialExpanded: true,
              children: [Text('直接可见会话')],
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(ScheduledSessionDisclosure),
          matching: find.byIcon(CupertinoIcons.chevron_down),
        ),
        findsOneWidget,
      );
      expect(find.text('直接可见会话'), findsOneWidget);
    });
  });

  group('SessionListPage 定时融流与开关联动集成测试', () {
    Future<ProviderContainer> pumpSessionListPage(
      WidgetTester tester,
      FakeSessionListApi api, {
      Locale locale = const Locale('zh'),
      bool showCron = false,
    }) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const SessionSidebar(currentLocation: '/'),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, state) =>
                _ChatStub(sessionId: state.pathParameters['sessionId'] ?? ''),
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          tasksControllerProvider.overrideWith(_EmptyTasksController.new),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        ],
      );

      if (showCron) {
        await container.read(cronVisibilityProvider.notifier).setShowCron(true);
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp.router(
            routerConfig: router,
            locale: locale,
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
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
      return container;
    }

    testWidgets('默认 showCron=false：定时会话不显示，无「定时」分区', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('cron_1', '每日自动同步', at: noon),
          buildSession('p1', '置顶重要会话', pinned: true, at: noon),
          buildSession(
            't1',
            '今天普通会话',
            at: noon.subtract(const Duration(hours: 2)),
          ),
        ],
      );

      await pumpSessionListPage(tester, api, showCron: false);

      expect(find.text('定时'), findsNothing);
      expect(find.text('置顶'), findsOneWidget);
      // 组头（11.5px 加粗）与会话行副标题都显示工作区名，故同名文本会出现多次；
      // 本断言只验证「该工作区名在列表中可见」。
      expect(find.text('main'), findsAtLeastNWidgets(1));
      expect(find.text('置顶重要会话'), findsOneWidget);
      expect(find.text('今天普通会话'), findsOneWidget);
      expect(find.text('每日自动同步'), findsNothing);
      expect(find.byType(ScheduledSessionDisclosure), findsNothing);
    });

    testWidgets('开启 showCron=true：定时会话融流进时间分区，不再有独立「定时」折叠面板', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('cron_1', '每日自动同步', at: noon),
          buildSession('p1', '置顶重要会话', pinned: true, at: noon),
          buildSession(
            't1',
            '今天普通会话',
            at: noon.subtract(const Duration(hours: 2)),
          ),
        ],
      );

      await pumpSessionListPage(tester, api, showCron: true);

      // 无「定时」分区，无 ScheduledSessionDisclosure
      expect(find.text('定时'), findsNothing);
      expect(find.byType(ScheduledSessionDisclosure), findsNothing);

      // 分区为 置顶 与 main
      expect(find.text('置顶'), findsOneWidget);
      // 组头（11.5px 加粗）与会话行副标题都显示工作区名，故同名文本会出现多次；
      // 本断言只验证「该工作区名在列表中可见」。
      expect(find.text('main'), findsAtLeastNWidgets(1));

      // 定时会话与普通会话一起在「main」分区直接渲染展示
      expect(find.text('置顶重要会话'), findsOneWidget);
      expect(find.text('每日自动同步'), findsOneWidget);
      expect(find.text('今天普通会话'), findsOneWidget);
    });

    testWidgets('融流展示后点击定时会话行 → 跳转 /chat/:sessionId', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [buildSession('cron_1', '每日自动同步', at: noon)],
      );

      await pumpSessionListPage(tester, api, showCron: true);

      // 直接点击会话行
      await tester.tap(find.text('每日自动同步'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-page-stub')), findsOneWidget);
      expect(find.text('ChatPage: cron_1'), findsOneWidget);
    });

    testWidgets('融流展示后行快捷操作 ellipsis 菜单正常工作', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [buildSession('cron_1', '每日自动同步', at: noon)],
      );

      await pumpSessionListPage(tester, api, showCron: true);

      // #158：会话项分「桌面侧栏朴素行（无 ⋯，靠长按/右键）/ 窄屏白卡（保留 ⋯）」
      // 两种形态。本用例的视口是默认窄屏 ⇒ 走卡片形态，行尾「⋯」依然存在，
      // 故仍用点击 ⋯ 的方式打开操作菜单。
      await tester.tap(find.byKey(const ValueKey('session-actions-cron_1')));
      await tester.pumpAndSettle();

      // 确认弹出了 CupertinoActionSheet
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('session-action-pin')), findsOneWidget);
    });

    testWidgets('搜索模式下定时会话直接进入「搜索结果」，无独立定时折叠分区', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('cron_1', '自动备份同步', at: noon),
          buildSession('t1', '备份相关讨论', at: noon),
        ],
      );
      api.searchResults['备份'] = [
        buildSession('cron_1', '自动备份同步', at: noon),
        buildSession('t1', '备份相关讨论', at: noon),
      ];

      await pumpSessionListPage(tester, api);

      // #149：宽屏侧栏的搜索框在品牌行内（默认收起）→ 先点搜索图标展开
      await tester.tap(find.byKey(const ValueKey('sidebar-brand-search')));
      await tester.pumpAndSettle();
      // 输入搜索词
      await tester.enterText(
        find.byKey(const ValueKey('sidebar-brand-search-field')),
        '备份',
      );
      // 350ms 防抖 + 异步搜索响应
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump();

      // 搜索模式下展示「搜索结果」单一分区
      expect(find.text('搜索结果'), findsOneWidget);
      expect(find.text('定时'), findsNothing);
      expect(find.text('自动备份同步'), findsOneWidget);
      expect(find.text('备份相关讨论'), findsOneWidget);
    });
  });
}
