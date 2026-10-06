import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/adaptive_action_menu.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_session_list_api.dart';

/// 秒级时间戳辅助。
double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _buildSession(
  String id,
  String title, {
  bool pinned = false,
  bool archived = false,
  DateTime? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    archived: archived,
    lastMessageAt: _sec(at ?? DateTime.now()),
  );
}

void main() {
  Future<void> pumpSessionList(
    WidgetTester tester,
    FakeSessionListApi api, {
    Locale locale = const Locale('zh'),
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const SessionListPage(),
        ),
        GoRoute(
          path: '/workspace/:sessionId',
          builder: (_, state) => _WorkspaceStub(
            sessionId: state.pathParameters['sessionId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/git/:sessionId',
          builder: (_, state) => _GitStub(
            sessionId: state.pathParameters['sessionId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/chat/:sessionId',
          builder: (_, state) => _ChatStub(
            sessionId: state.pathParameters['sessionId'] ?? '',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue(
            (_) => _StubProjectApi(),
          ),
        ],
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
  }

  group('会话行操作菜单（工作区 / Git 入口）', () {

    testWidgets('打开行菜单 →「工作区」与「Git」两项均可见且带有对应 ValueKey', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('s1', '测试会话 1')],
      );
      await pumpSessionList(tester, api);

      // 点击行操作按钮（ellipsis）
      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();

      // 断言工作区与 Git 选项存在
      expect(find.byKey(const ValueKey('session-action-workspace')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-action-git')), findsOneWidget);
      expect(find.text('工作区'), findsAtLeastNWidgets(1));
      expect(find.text('Git'), findsOneWidget);

      // 现有选项也正常展示
      expect(find.byKey(const ValueKey('session-action-pin')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-action-archive')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-action-branch')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-action-export')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-action-move-project')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-action-delete')), findsOneWidget);
    });

    testWidgets('点击「工作区」→ 跳转到 /workspace/:sessionId 页面', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('sess-101', '代码工作区会话')],
      );
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-sess-101')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('session-action-workspace')));
      await tester.pumpAndSettle();

      // 菜单已关闭，进入工作区页面
      expect(find.text('workspace-sess-101'), findsOneWidget);
      expect(find.text('工作区占位: sess-101'), findsOneWidget);
    });

    testWidgets('点击「Git」→ 跳转到 /git/:sessionId 页面', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('sess-202', 'Git 管理会话')],
      );
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-sess-202')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('session-action-git')));
      await tester.pumpAndSettle();

      // 菜单已关闭，进入 Git 页面
      expect(find.text('git-sess-202'), findsOneWidget);
      expect(find.text('Git占位: sess-202'), findsOneWidget);
    });

    testWidgets('通过 push 跳转后，工作区页面 pop 返回时保留在列表页', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('sess-303', '返回测试会话')],
      );
      await pumpSessionList(tester, api);

      // 打开并跳转工作区
      await tester.tap(find.byKey(const ValueKey('session-actions-sess-303')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-action-workspace')));
      await tester.pumpAndSettle();
      expect(find.text('workspace-sess-303'), findsOneWidget);

      // 点击返回
      await tester.tap(find.byKey(const ValueKey('stub-back-button')));
      await tester.pumpAndSettle();

      // 回到列表页
      expect(find.text('返回测试会话'), findsOneWidget);
      expect(find.text('workspace-sess-303'), findsNothing);
    });

    testWidgets('通过 push 跳转后，Git 页面 pop 返回时保留在列表页', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('sess-404', 'Git 返回测试会话')],
      );
      await pumpSessionList(tester, api);

      // 打开并跳转 Git
      await tester.tap(find.byKey(const ValueKey('session-actions-sess-404')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-action-git')));
      await tester.pumpAndSettle();
      expect(find.text('git-sess-404'), findsOneWidget);

      // 点击返回
      await tester.tap(find.byKey(const ValueKey('stub-back-button')));
      await tester.pumpAndSettle();

      // 回到列表页
      expect(find.text('Git 返回测试会话'), findsOneWidget);
      expect(find.text('git-sess-404'), findsNothing);
    });

    testWidgets('英文语言环境下文案展示为 Workspace 与 Git', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('sess-en', 'English Session')],
      );
      await pumpSessionList(tester, api, locale: const Locale('en'));

      await tester.tap(find.byKey(const ValueKey('session-actions-sess-en')));
      await tester.pumpAndSettle();

      expect(find.text('Workspace'), findsOneWidget);
      expect(find.text('Git'), findsOneWidget);
    });
  });

  group('宽屏行操作菜单：补图标 + 语义分组（设计稿 §6）', () {
    Future<void> pumpWide(WidgetTester tester, FakeSessionListApi api) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpSessionList(tester, api);
    }

    testWidgets('宽屏浮层：每行带图标，按语义分四族（3 条 0.5px 分组线）', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('s1', '测试会话 1')],
      );
      await pumpWide(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();

      // 设计稿 §6 规格图标族：置顶/归档/移动到项目/导出/分支/工作区/Git/删除。
      for (final icon in const [
        CupertinoIcons.pin,
        CupertinoIcons.archivebox,
        CupertinoIcons.square_stack,
        CupertinoIcons.square_arrow_up,
        CupertinoIcons.arrow_branch,
        CupertinoIcons.folder,
        CupertinoIcons.trash,
      ]) {
        expect(find.byIcon(icon), findsWidgets, reason: '$icon 应出现在菜单行');
      }

      // 非归档会话：8 行、四族（第二/三/四族各一条分组线）。
      final rows = tester
          .widgetList<ActionMenuRow>(find.byType(ActionMenuRow))
          .toList();
      expect(rows.length, 8);
      expect(
        rows.every((row) => row.icon != null),
        isTrue,
        reason: '零图标的「一堵墙」是本条改动要消除的形态',
      );
      expect(find.byType(ActionMenuDivider), findsNWidgets(3));

      // 分组语义：危险动作独立成群（红色），图标为垃圾桶。
      final deleteRow = tester.widget<ActionMenuRow>(
        find.byKey(const ValueKey('session-action-delete')),
      );
      expect(deleteRow.isDestructive, isTrue);
      expect(deleteRow.icon, CupertinoIcons.trash);
      // 各族首项带 startsGroup，非首项不带（分组线不会重复画）。
      final moveRow = tester.widget<ActionMenuRow>(
        find.byKey(const ValueKey('session-action-move-project')),
      );
      final exportRow = tester.widget<ActionMenuRow>(
        find.byKey(const ValueKey('session-action-export')),
      );
      expect(moveRow.icon, CupertinoIcons.square_stack);
      expect(exportRow.icon, CupertinoIcons.square_arrow_up);
    });

    testWidgets('归档会话额外出现「取消归档」且与「归档」同族相邻', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('s1', '已归档会话', archived: true)],
      );
      await pumpWide(tester, api);

      // 默认「全部」不含已归档会话 → 先切到「已归档」筛选让该行出现。
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sheet-filter-archived')));
      await tester.pumpAndSettle();
      expect(find.text('已归档会话'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('session-action-unarchive')),
        findsOneWidget,
      );
      // 归档 → 取消归档 相邻（同族、无分组线分隔）：两者之间只有一条分隔线
      // 属后面的「移动到项目」，故这里断言二者顺序紧邻。
      final archiveTop = tester
          .getRect(find.byKey(const ValueKey('session-action-archive')))
          .top;
      final unarchiveTop = tester
          .getRect(find.byKey(const ValueKey('session-action-unarchive')))
          .top;
      expect(unarchiveTop, greaterThan(archiveTop));
      // 归档行与取消归档行之间没有分组线（同族内不画线）。
      final dividerTops = find
          .byType(ActionMenuDivider)
          .evaluate()
          .map(
            (e) => (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
          )
          .toList();
      expect(
        dividerTops.where((dy) => dy > archiveTop && dy < unarchiveTop).isEmpty,
        isTrue,
      );
      expect(find.byType(ActionMenuDivider), findsNWidgets(3));
      expect(find.byType(ActionMenuRow), findsNWidgets(9));
    });

    testWidgets('窄屏（< 900）仍走系统 ActionSheet：无图标行、无分组线（保持原样）', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_buildSession('s1', '测试会话 1')],
      );
      // 默认 800×600 → 窄屏。
      await pumpSessionList(tester, api);
      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byType(ActionMenuRow), findsNothing);
      expect(find.byType(ActionMenuDivider), findsNothing);
      // 项集与 ValueKey 不变（图标/分组字段在窄屏不参与渲染）。
      expect(find.byKey(const ValueKey('session-action-pin')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-action-move-project')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('session-action-delete')), findsOneWidget);
    });
  });
}

/// 工作区页占位。
class _WorkspaceStub extends StatelessWidget {
  const _WorkspaceStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('workspace-$sessionId'),
        leading: CupertinoButton(
          key: const ValueKey('stub-back-button'),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
      ),
      child: Center(child: Text('工作区占位: $sessionId')),
    );
  }
}

/// Git 页占位。
class _GitStub extends StatelessWidget {
  const _GitStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('git-$sessionId'),
        leading: CupertinoButton(
          key: const ValueKey('stub-back-button'),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
      ),
      child: Center(child: Text('Git占位: $sessionId')),
    );
  }
}

/// 聊天页占位。
class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('chat-$sessionId')),
      child: const Center(child: Text('聊天占位')),
    );
  }
}

/// 项目 API 空实现 stub：列表容器注入，避免真实 dio 请求。
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
