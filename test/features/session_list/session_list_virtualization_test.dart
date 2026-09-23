import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_session_list_api.dart';

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
  Widget build(BuildContext context) => Text('chat-$sessionId');
}

void main() {
  Future<void> pumpSessionList(
    WidgetTester tester,
    FakeSessionListApi api, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
        GoRoute(
          path: '/chat/:sessionId',
          builder: (_, state) =>
              _ChatStub(sessionId: state.pathParameters['sessionId'] ?? ''),
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
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('会话列表 Sliver 真虚拟化探针', () {
    testWidgets('200+ 会话首帧仅构建视口与预加载范围行（< 25），非全量 50/200 铺开', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final sessions = [
        for (var i = 0; i < 200; i++)
          SessionSummary(
            sessionId: 'sess-$i',
            title: '会话标题 #$i',
            workspace: '/ws/main',
            createdAt: now - (i * 60),
            messageCount: i,
          ),
      ];

      final api = FakeSessionListApi(sessions: sessions);
      await pumpSessionList(tester, api);

      // 统计首帧实际进入 element 树的 session row 数量
      final rowFinder = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('session-row-'),
      );

      final builtCount = rowFinder.evaluate().length;

      // 视口高 844，除去 header/search (~150px)，每行约 55px，视口约 12 行 + 预加载 ~5-8 行
      // 探针断言：实际构建数必须在 8~22 范围内，远小于 visibleCount(50) 或 全量(200)
      expect(
        builtCount,
        lessThanOrEqualTo(22),
        reason: '首帧构建数 ($builtCount) 超过视口+缓存预估上限 (22)，未实现真虚拟化',
      );
      expect(
        builtCount,
        greaterThanOrEqualTo(8),
        reason: '首帧构建数 ($builtCount) 低于视口所需行数 (8)',
      );

      // 顶部会话可见，靠后会话未构建
      expect(find.byKey(const ValueKey('session-row-sess-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-row-sess-45')), findsNothing);
      expect(find.byKey(const ValueKey('session-row-sess-199')), findsNothing);
    });

    testWidgets('向下滚动触发懒加载构建，离开视口旧行被回收', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final sessions = [
        for (var i = 0; i < 100; i++)
          SessionSummary(
            sessionId: 'scroll-sess-$i',
            title: '滚动测试会话 #$i',
            workspace: '/ws/main',
            createdAt: now - (i * 60),
          ),
      ];

      final api = FakeSessionListApi(sessions: sessions);
      await pumpSessionList(tester, api);

      // 初始：sess-0 在视口
      expect(
        find.byKey(const ValueKey('session-row-scroll-sess-0')),
        findsOneWidget,
      );

      // 向下大幅滚动
      await tester.drag(
        find.byKey(const ValueKey('session-list-scroll')),
        const Offset(0, -1200),
      );
      await tester.pump();

      // sess-0 已离开视口并被回收
      expect(
        find.byKey(const ValueKey('session-row-scroll-sess-0')),
        findsNothing,
      );

      // 滚动后中间会话已懒加载构建
      final scrolledRows = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith(
              'session-row-scroll-sess-',
            ),
      );
      expect(scrolledRows.evaluate().length, lessThanOrEqualTo(22));
    });

    testWidgets('跨多个分区（置顶/工作区各分区）均保持独立 Sliver 虚拟化', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final secNoon = noon.millisecondsSinceEpoch / 1000.0;
      final sessions = [
        // 置顶组 3 个
        for (var i = 0; i < 3; i++)
          SessionSummary(
            sessionId: 'pin-$i',
            title: '置顶会话 $i',
            pinned: true,
            createdAt: secNoon,
          ),
        // 工作区 A 组 30 个
        for (var i = 0; i < 30; i++)
          SessionSummary(
            sessionId: 'today-$i',
            title: '今天会话 $i',
            workspace: '/ws/proj_a',
            createdAt: secNoon - (i * 60),
          ),
        // 工作区 B 组 20 个
        for (var i = 0; i < 20; i++)
          SessionSummary(
            sessionId: 'yest-$i',
            title: '昨天会话 $i',
            workspace: '/ws/proj_b',
            createdAt: secNoon - 86400 - (i * 60),
          ),
      ];

      final api = FakeSessionListApi(sessions: sessions);
      await pumpSessionList(tester, api);

      // 分区标题可见
      expect(find.text('置顶'), findsOneWidget);
      // 组头（11.5px 加粗）与会话行副标题都显示工作区名，故同名文本会出现多次；
      // 本断言只验证「该工作区名在列表中可见」。
      expect(find.text('proj_a'), findsAtLeastNWidgets(1));

      // 置顶全部可见（3 个）
      expect(find.byKey(const ValueKey('session-row-pin-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-row-pin-2')), findsOneWidget);

      // proj_a 部分可见，proj_b 尚未进入视口
      expect(find.byKey(const ValueKey('session-row-today-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-row-yest-10')), findsNothing);
    });

    testWidgets('滚动到底部 loadMore 扩展 visibleCount，分页状态无缝衔接', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final sessions = [
        for (var i = 0; i < 80; i++)
          SessionSummary(
            sessionId: 'page-sess-$i',
            title: '分页会话 $i',
            workspace: '/ws/main',
            createdAt: now - (i * 60),
          ),
      ];

      final api = FakeSessionListApi(sessions: sessions);
      await pumpSessionList(tester, api);

      // 滚动到底部触发 loadMore 并滑动到末尾
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('session-row-page-sess-79')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // 滚动到底部后，最后一项已构建（#147：分组列表底部不再显示「没有更多了」）
      expect(
        find.byKey(const ValueKey('session-row-page-sess-79')),
        findsOneWidget,
      );
      expect(find.textContaining('没有更多'), findsNothing);
    });
  });
}
