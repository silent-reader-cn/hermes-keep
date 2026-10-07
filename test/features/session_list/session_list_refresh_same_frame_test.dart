// 守卫：刷新「无感」的**同帧**要求 —— 内容换新与几何补偿必须落在同一帧。
//
// 现象（主人 2026-10-07）：侧栏会话列表刷新会「闪一下」。
// 根因：`_applySections` 只把新内容挂上屏，几何补偿（`jumpTo`）发生在**同一帧的
// post-frame**，而 post-frame 时本帧已绘制提交 ⇒ 屏上先露出一帧「整列下移一行」
// 的错位画面，下一帧才归位。单看 `pumpAndSettle` 之后的位置是**看不出来**的
// （终态正确），所以旧守卫（session_list_refresh_anchor_test）全绿也没能拦住它。
//
// 本文件按「逐帧」口径钉住：内容换新后的**第一帧**就必须已经在正确位置。
// 同时钉住「顶部不补偿」（新会话该被看见）与「补偿真的发生了」（pixels 变了），
// 避免用「不刷新 / 不换内容」把测试糊绿。

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
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(
  String id, {
  required String workspace,
  required DateTime at,
}) {
  return SessionSummary(
    sessionId: id,
    title: id,
    workspace: workspace,
    lastMessageAt: _sec(at),
  );
}

/// 分组方式固定为「工作区」（避免屏宽兜底 + SharedPreferences 异步回填的抖动）。
class _WorkspaceGroupingNotifier extends SessionGroupingModeController {
  @override
  SessionGroupingMode? build() => SessionGroupingMode.workspace;
}

class _ChatStub extends StatelessWidget {
  const _ChatStub();

  @override
  Widget build(BuildContext context) =>
      const CupertinoPageScaffold(child: SizedBox(key: ValueKey('chat-stub')));
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

/// 视口顶缘可见行（与页面内 `_captureTopVisibleAnchor` 同口径）。
({String id, double dy})? _topVisibleRow(WidgetTester tester) {
  final scrollViewTop = tester
      .getTopLeft(find.byKey(const ValueKey('session-list-scroll')))
      .dy;
  ({String id, double dy})? best;
  for (final element in find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('session-row-');
      })
      .evaluate()) {
    final key = element.widget.key! as ValueKey<String>;
    final id = key.value.substring('session-row-'.length);
    final finder = find.byKey(key);
    final top = tester.getTopLeft(finder).dy;
    final bottom = tester.getBottomLeft(finder).dy;
    if (bottom <= scrollViewTop) continue;
    if (best == null || top - scrollViewTop < best.dy) {
      best = (id: id, dy: top - scrollViewTop);
    }
  }
  return best;
}

double _pixels(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpSessionList(
    WidgetTester tester,
    FakeSessionListApi api,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const SizedBox(
            width: 320,
            child: SessionListPage(showUtilityRows: false, showFab: false),
          ),
        ),
        GoRoute(path: '/chat', builder: (_, _) => const _ChatStub()),
        GoRoute(path: '/chat/:sessionId', builder: (_, _) => const _ChatStub()),
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
          sessionGroupingModeProvider.overrideWith(
            _WorkspaceGroupingNotifier.new,
          ),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(SessionListPage)),
    );
  }

  testWidgets('刷新插入新行：内容换新的**第一帧**就必须已归位（不得有一帧错位）', (tester) async {
    final now = DateTime(2026, 10, 6, 12);
    final api = FakeSessionListApi(
      sessions: [
        for (var i = 0; i < 40; i++)
          _session(
            'old-$i',
            workspace: '/ws/main',
            at: now.subtract(Duration(minutes: i)),
          ),
      ],
    );
    final container = await pumpSessionList(tester, api);

    // 滚进列表中部：此时才启用锚点语义（顶部不锚定）。
    await tester.drag(
      find.byKey(const ValueKey('session-list-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    final before = _topVisibleRow(tester);
    expect(before, isNotNull, reason: '刷新前应有可见行');
    final pixelsBefore = _pixels(tester);
    expect(pixelsBefore, greaterThan(0.0), reason: '须已滚进内容里，锚点语义才成立');

    // 刷新：新会话插到组内最上方 ⇒ 其下所有行在新布局中下移一行。
    api.sessions = [
      _session(
        'new-1',
        workspace: '/ws/main',
        at: now.add(const Duration(minutes: 1)),
      ),
      ...api.sessions,
    ];
    await container
        .read(sessionListControllerProvider.notifier)
        .refreshIfStale(force: true);

    // ── 关键：只推一帧就断言（`pumpAndSettle` 会把中间帧全部越过去）──
    await tester.pump(const Duration(milliseconds: 16));
    final firstFrame = _topVisibleRow(tester);
    expect(firstFrame, isNotNull, reason: '换新后第一帧应有可见行');
    expect(
      firstFrame!.id,
      before!.id,
      reason: '第一帧的顶缘可见行必须仍是同一行（否则屏上先闪了一次换行）',
    );
    expect(
      firstFrame.dy,
      closeTo(before.dy, 0.5),
      reason: '第一帧该行的视口 dy 必须逐像素保持 —— 内容换新与几何补偿须同帧落地',
    );

    // 换新确实发生（防「把刷新变成 no-op」糊绿），且补偿真的动了视口。
    final sessions = container
        .read(sessionListControllerProvider)
        .valueOrNull!
        .sessions;
    expect(
      sessions.map((s) => s.sessionId),
      contains('new-1'),
      reason: '刷新必须真的换内容',
    );
    expect(
      _pixels(tester),
      greaterThan(pixelsBefore),
      reason: '锚点上方多了一行 ⇒ pixels 必须被同步补偿（同帧补偿的直接证据）',
    );

    // 收敛后仍然稳定（后续帧不再抖动）。
    await tester.pumpAndSettle();
    final settled = _topVisibleRow(tester);
    expect(settled!.id, before.id);
    expect(settled.dy, closeTo(before.dy, 0.5));
  });

  testWidgets('顶部（未滚动）刷新不补偿：新会话应直接出现在顶部', (tester) async {
    final now = DateTime(2026, 10, 6, 12);
    final api = FakeSessionListApi(
      sessions: [
        for (var i = 0; i < 40; i++)
          _session(
            'old-$i',
            workspace: '/ws/main',
            at: now.subtract(Duration(minutes: i)),
          ),
      ],
    );
    final container = await pumpSessionList(tester, api);
    expect(_pixels(tester), 0.0);

    final before = _topVisibleRow(tester);
    expect(before!.id, 'old-0');

    api.sessions = [
      _session(
        'new-1',
        workspace: '/ws/main',
        at: now.add(const Duration(minutes: 1)),
      ),
      ...api.sessions,
    ];
    await container
        .read(sessionListControllerProvider.notifier)
        .refreshIfStale(force: true);
    await tester.pump(const Duration(milliseconds: 16));

    // 顶部语义：留在顶部看新内容，不做锚定补偿。
    expect(_pixels(tester), 0.0, reason: '顶部刷新不得被补偿推下去');
    expect(_topVisibleRow(tester)!.id, 'new-1', reason: '新会话应直接出现在顶部');

    await tester.pumpAndSettle();
    expect(_pixels(tester), 0.0);
    expect(_topVisibleRow(tester)!.id, 'new-1');
  });
}
