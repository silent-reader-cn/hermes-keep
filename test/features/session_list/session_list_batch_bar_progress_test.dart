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

/// #174 批量操作进度：批量栏 UI 守卫。
///
/// 主人报告的是「点了归档/删除没进度提示，只能干等」—— 本文件钉死三件事：
/// 1. 在途时批量栏原地切成进度形态（「归档中 1/2」+ 转圈）；
/// 2. 在途时四个按钮**全部禁用**（含全选 —— 防连点触发第二批）；
/// 3. 完成后给一次轻量结果提示（2s 自动消失），空闲态文案不变。
double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(String id, String title) => SessionSummary(
  sessionId: id,
  title: title,
  lastMessageAt: _sec(DateTime.now()),
);

/// 空项目 API stub：避免真实 [ApiClient] 发出 dio 请求残留超时 Timer。
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

Future<void> _pumpList(WidgetTester tester, FakeSessionListApi api) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
      GoRoute(
        path: '/chat/:sessionId',
        builder: (_, _) => const SizedBox.shrink(),
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

SessionListController _controllerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(SessionListPage)),
    ).read(sessionListControllerProvider.notifier);

CupertinoButton _button(WidgetTester tester, String key) =>
    tester.widget<CupertinoButton>(find.byKey(ValueKey(key)));

/// 「删除」按钮文字的显式颜色：null = 交给 CupertinoButton 的禁用灰。
Color? _deleteTextColor(WidgetTester tester) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('batch-delete')),
            matching: find.byType(Text),
          )
          .first,
    )
    .style
    ?.color;

void main() {
  group('#174 批量栏进度形态', () {
    testWidgets('归档在途：批量栏切进度文案 + 按钮全禁用', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', 'A'), _session('s2', 'B')],
      );
      await _pumpList(tester, api);
      final controller = _controllerOf(tester);

      controller.toggleSelection('s1');
      controller.toggleSelection('s2');
      await tester.pump();
      expect(find.text('已选 2 个'), findsOneWidget);

      api.gate('s1');
      api.gate('s2');
      final future = controller.batchArchive();
      await tester.pump();

      // 进度文案 + 转圈
      expect(find.text('归档中 0/2'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsWidgets);

      // 四个按钮全部禁用（防连点触发第二批）
      expect(_button(tester, 'batch-select-all').onPressed, isNull);
      expect(_button(tester, 'batch-archive').onPressed, isNull);
      expect(_button(tester, 'batch-delete').onPressed, isNull);
      expect(_button(tester, 'batch-move').onPressed, isNull);

      // 禁用态「删除」不得再硬编码红色（否则看起来还能点）——交给统一灰
      expect(_deleteTextColor(tester), isNull);

      // 逐条推进
      api.gate('s1').complete();
      await tester.pump();
      expect(find.text('归档中 1/2'), findsOneWidget);

      // 像素级守卫：已走段必须**真的有尺寸**且随进度生长。
      // （无 child 的 ColoredBox 在 loose 约束下宽高为 0 ⇒ 渲染成「看不见的进度」，
      //   纯文本断言抓不到，是靠真渲染目检才发现的缺陷。）
      final track = tester.getSize(
        find.byKey(const ValueKey('batch-progress-track')),
      );
      final fill = tester.getSize(
        find.byKey(const ValueKey('batch-progress-fill')),
      );
      expect(fill.height, 3, reason: 'fill 必须真占高度，否则进度条渲染成空条');
      expect(
        fill.width,
        closeTo(track.width / 2, 1),
        reason: '1/2 进度 ⇒ 已走段应为轨道半宽',
      );

      api.gate('s2').complete();
      await future;
      await tester.pump();

      // 收尾：退出多选 ⇒ 批量栏收拢
      expect(find.textContaining('归档中'), findsNothing);
      expect(find.text('已选 2 个'), findsNothing);
    });

    testWidgets('空闲态：文案仍是「已选 N 个」，按钮恢复可点', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      await _pumpList(tester, api);
      final controller = _controllerOf(tester);

      controller.toggleSelection('s1');
      await tester.pump();

      expect(find.text('已选 1 个'), findsOneWidget);
      expect(find.textContaining('归档中'), findsNothing);
      expect(_button(tester, 'batch-archive').onPressed, isNotNull);
      expect(_button(tester, 'batch-delete').onPressed, isNotNull);
      // 可点时才涂红（禁用走统一灰）——两条口径合起来钉住 #174 的按钮态契约
      expect(_deleteTextColor(tester), isNotNull);
    });

    testWidgets('走真实 UI 路径完成归档：结果提示出现并在 2 秒后消失', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', 'A'), _session('s2', 'B')],
      );
      await _pumpList(tester, api);
      final controller = _controllerOf(tester);

      controller.toggleSelection('s1');
      controller.toggleSelection('s2');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('batch-archive')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('batch-archive-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('batch-archive-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 完成反馈（全成功 ⇒ 轻提示；失败走既有 actionError 弹窗）
      expect(
        find.byKey(const ValueKey('batch-result-notice')),
        findsOneWidget,
      );
      expect(find.text('已归档 2 个会话'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('batch-result-notice')), findsNothing);
    });
  });
}
