import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/shell/empty_detail_pane.dart';
import 'package:hermes_ui/app/widgets/hermes_page_route.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/shared/app_back_button.dart';
import 'package:hermes_ui/features/shared/app_navigation.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';

class _ShellProbe extends StatelessWidget {
  const _ShellProbe({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const AppBackButton(),
        middle: Text('Chat $sessionId'),
      ),
      child: Center(
        child: Text(
          'canPop=${context.canPop()}',
          key: const ValueKey('chat-canpop'),
        ),
      ),
    );
  }
}

class _SettingsStub extends StatelessWidget {
  const _SettingsStub();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        leading: AppBackButton(),
        middle: Text('Settings Page'),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'canPop=${context.canPop()}',
              key: const ValueKey('settings-canpop'),
            ),
            CupertinoButton(
              key: const ValueKey('goto-tasks-from-settings'),
              onPressed: () => openAdaptiveRoute(context, '/tasks'),
              child: const Text('To Tasks'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TasksStub extends StatelessWidget {
  const _TasksStub();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        leading: AppBackButton(),
        middle: Text('Tasks Page'),
      ),
      child: Center(
        child: Text(
          'canPop=${context.canPop()}',
          key: const ValueKey('tasks-canpop'),
        ),
      ),
    );
  }
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

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => _ShellProbe(
          child: AdaptiveShell(state: state, child: child),
        ),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('home'),
              builder: (_) => const SessionListPage(),
            ),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            pageBuilder: (context, state) => HermesPage<void>(
              key: ValueKey('chat-${state.pathParameters['sessionId']}'),
              builder: (_) =>
                  _ChatStub(sessionId: state.pathParameters['sessionId'] ?? ''),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('settings'),
              builder: (_) => const _SettingsStub(),
            ),
          ),
          GoRoute(
            path: '/tasks',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('tasks'),
              builder: (_) => const _TasksStub(),
            ),
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeSessionListApi api,
  required Size viewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final router = _buildRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        sessionListApiFactoryProvider.overrideWithValue((_) => api),
        projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      ],
      child: CupertinoApp.router(
        routerConfig: router,
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
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('宽屏右侧面板导航栈与清栈测试（#77）', () {
    testWidgets('宽屏视口（1280×800）：侧栏 tap 模块入口 push 入栈，模块页出现，ShellRoute 单实例=1，返回回退到 home', (
      tester,
    ) async {
      final api = FakeSessionListApi(
        sessions: [
          SessionSummary(
            sessionId: 's1',
            title: '测试会话',
            lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        ],
      );
      await _pumpApp(tester, api: api, viewport: const Size(1280, 800));

      // 初始处于根路径：右侧展示 EmptyDetailPane，Shell 实例为 1
      expect(find.byType(EmptyDetailPane), findsOneWidget);
      expect(find.byType(_ShellProbe), findsOneWidget);

      // 点击侧栏设置入口（push）
      await tester.tap(find.byKey(const ValueKey('sidebar-secondary-settings')));
      await tester.pumpAndSettle();

      // 断言模块页出现，栈深度积累（canPop=true），Shell 仍为单实例（不叠 shell）
      expect(find.text('Settings Page'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-canpop')), findsOneWidget);
      expect(find.text('canPop=true'), findsOneWidget);
      expect(find.byType(EmptyDetailPane), findsNothing);
      expect(find.byType(_ShellProbe), findsOneWidget);

      // 点击返回（AppBackButton）
      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();

      // 断言返回回退到 home，模块页消失，EmptyDetailPane 重新展示，Shell 保持单实例
      expect(find.text('Settings Page'), findsNothing);
      expect(find.byType(EmptyDetailPane), findsOneWidget);
      expect(find.byType(_ShellProbe), findsOneWidget);
    });

    testWidgets('宽屏视口：push 两级模块页后逐级 pop 回退', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          SessionSummary(
            sessionId: 's1',
            title: '测试会话',
            lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        ],
      );
      await _pumpApp(tester, api: api, viewport: const Size(1280, 800));

      // 1. 点击侧栏设置（第一级 push）
      await tester.tap(find.byKey(const ValueKey('sidebar-secondary-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Settings Page'), findsOneWidget);
      expect(find.text('canPop=true'), findsOneWidget);
      expect(find.byType(_ShellProbe), findsOneWidget);

      // 2. 从设置页跳转任务管理（第二级 push，通过 openAdaptiveRoute）
      await tester.tap(find.byKey(const ValueKey('goto-tasks-from-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Tasks Page'), findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-canpop')), findsOneWidget);
      expect(find.text('canPop=true'), findsOneWidget);
      expect(find.text('Settings Page'), findsNothing);
      expect(find.byType(_ShellProbe), findsOneWidget);

      // 3. 第一次 pop：从 Tasks 回退到 Settings
      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();
      expect(find.text('Tasks Page'), findsNothing);
      expect(find.text('Settings Page'), findsOneWidget);
      expect(find.text('canPop=true'), findsOneWidget);
      expect(find.byType(_ShellProbe), findsOneWidget);

      // 4. 第二次 pop：从 Settings 回退到 home
      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();
      expect(find.text('Settings Page'), findsNothing);
      expect(find.byType(EmptyDetailPane), findsOneWidget);
      expect(find.byType(_ShellProbe), findsOneWidget);
    });

    testWidgets('宽屏视口：push 模块页后 tap 会话入口（go 聊天）→ 栈清空（canPop=false），返回走 fallback', (
      tester,
    ) async {
      final api = FakeSessionListApi(
        sessions: [
          SessionSummary(
            sessionId: 's1',
            title: '测试会话',
            lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        ],
      );
      await _pumpApp(tester, api: api, viewport: const Size(1280, 800));

      // 1. 点击侧栏设置进入设置页（push 积累栈）
      await tester.tap(find.byKey(const ValueKey('sidebar-secondary-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Settings Page'), findsOneWidget);
      expect(find.text('canPop=true'), findsOneWidget);

      // 2. 在侧栏点击会话条目（宽屏下 _openChatRoute 走 go('/chat/s1')，清空历史栈）
      await tester.tap(find.byKey(const ValueKey('session-row-s1')));
      await tester.pumpAndSettle();

      // 断言已进入 Chat 页面，设置页已销毁，栈已清空（canPop=false）
      expect(find.text('Chat s1'), findsOneWidget);
      expect(find.text('Settings Page'), findsNothing);
      expect(find.byKey(const ValueKey('chat-canpop')), findsOneWidget);
      expect(find.text('canPop=false'), findsOneWidget);
      expect(find.byType(_ShellProbe), findsOneWidget);

      // 3. 点击聊天页 AppBackButton：由于 canPop=false，触发 fallback 走 context.go('/')
      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();

      // 断言回到根路径主页
      expect(find.text('Chat s1'), findsNothing);
      expect(find.byType(EmptyDetailPane), findsOneWidget);
      expect(find.text('测试会话'), findsOneWidget);
      expect(find.byType(_ShellProbe), findsOneWidget);
    });
  });
}
