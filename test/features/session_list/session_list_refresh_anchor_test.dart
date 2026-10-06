// 守卫：自动刷新「无感」—— 视口锚点保持 + 滚动中不换内容（主人 2026-10-06 反馈）。
//
// 现象：侧栏会话分类列表在自动刷新时会「自己滚一下」。根因不是 pixels 变了，
// 而是刷新换掉了列表内容（新会话插到上方 / 组内重排），屏上的行被整体位移。
//
// 本文件从页面层钉住两件事：
// ① 刷新前后「视口顶缘可见行」的 renderId 与 dy 保持不变（几何锚点归位）；
// ② 用户正在拖动/惯性滚动时不换内容（settle 之后才应用，避免手指底下被替换）。

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

/// 视口顶缘可见行（renderId + 全局 dy）—— 与页面内 `_captureTopVisibleAnchor`
/// 同口径：完全在滚动视图上方的行不算，其余取最靠上的一条。
({String id, double dy})? _topVisibleRow(WidgetTester tester) {
  final scrollViewTop = tester
      .getTopLeft(find.byKey(const ValueKey('session-list-scroll')))
      .dy;
  ({String id, double dy})? best;
  for (final element in find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('session-row-');
  }).evaluate()) {
    final key = element.widget.key! as ValueKey<String>;
    final id = key.value.substring('session-row-'.length);
    final finder = find.byKey(key);
    final top = tester.getTopLeft(finder).dy;
    final bottom = tester.getBottomLeft(finder).dy;
    if (bottom <= scrollViewTop) continue;
    if (best == null || top < best.dy) best = (id: id, dy: top);
  }
  return best;
}

double _rowDy(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('session-row-$id'))).dy;

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
    FakeSessionListApi api, {
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const SessionListPage(showUtilityRows: false, showFab: false),
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

  group('自动刷新：视口锚点保持（无感刷新）', () {
    testWidgets('刷新把新会话插到上方后，顶部可见行 renderId 与 dy 不变（连做两轮）', (tester) async {
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

      // 滚动进列表中部（远离顶部与底部：底部有 hasMore 判据，本用例不涉及分页）。
      await tester.drag(
        find.byKey(const ValueKey('session-list-scroll')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(_pixels(tester), greaterThan(0.0));

      for (var round = 1; round <= 2; round++) {
        final before = _topVisibleRow(tester);
        expect(before, isNotNull, reason: '第 $round 轮：刷新前应有可见行');
        final pixelsBefore = _pixels(tester);
        debugPrint(
          'ANCHOR#$round BEFORE refresh: id=${before!.id} '
          'dy=${before.dy.toStringAsFixed(2)} pixels=${pixelsBefore.toStringAsFixed(2)}',
        );

        // 刷新内容变化：新会话（最新活动）插到组内最上方 ⇒ 其下所有行下移一行高。
        api.sessions = [
          _session('new-$round', workspace: '/ws/main', at: now),
          ...api.sessions,
        ];
        await container
            .read(sessionListControllerProvider.notifier)
            .refreshIfStale(force: true);
        await tester.pumpAndSettle();

        final after = _topVisibleRow(tester);
        expect(after, isNotNull, reason: '第 $round 轮：刷新后应有可见行');
        debugPrint(
          'ANCHOR#$round AFTER  refresh: id=${after!.id} '
          'dy=${after.dy.toStringAsFixed(2)} pixels=${_pixels(tester).toStringAsFixed(2)}',
        );

        expect(after.id, before.id, reason: '第 $round 轮：刷新后顶部可见行必须还是同一行（无感刷新）');
        expect(
          after.dy,
          closeTo(before.dy, 0.5),
          reason: '第 $round 轮：该行的视口 dy 必须逐像素保持（几何锚点归位）',
        );
        // 新内容确实已经进来了（证明刷新真的换了内容，而不是没刷新）：
        // 控制器已收到新会话 + 视口被向上补偿了一行（锚点上方多了一行）。
        final sessions = container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions;
        expect(
          sessions.map((s) => s.sessionId),
          contains('new-$round'),
          reason: '第 $round 轮：刷新必须真的换内容（防过度修复把刷新变成 no-op）',
        );
        expect(
          _pixels(tester),
          greaterThan(pixelsBefore),
          reason: '第 $round 轮：锚点上方多了一行 ⇒ 视口必须被精确补偿（几何归位的直接证据）',
        );
      }
    });

    testWidgets('刷新改变组内顺序时锚点同样保持（同一行 dy 不变，pixels 被补偿）', (tester) async {
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

      await tester.drag(
        find.byKey(const ValueKey('session-list-scroll')),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();

      final anchor = _topVisibleRow(tester)!;
      final pixelsBefore = _pixels(tester);

      // 只把**锚点下方**的两行互换（组内重排）：锚点行位置不受影响 ⇒
      // 不该发生任何补偿滚动（「偏移真的变了才动」）。
      final reordered = [...api.sessions];
      final last = reordered.removeAt(reordered.length - 1);
      reordered.insert(reordered.length - 1, last);
      api.sessions = reordered;
      await container
          .read(sessionListControllerProvider.notifier)
          .refreshIfStale(force: true);
      await tester.pumpAndSettle();

      expect(
        _rowDy(tester, anchor.id),
        closeTo(anchor.dy, 0.5),
        reason: '锚点行必须停在同一视口位置',
      );
      expect(
        _pixels(tester),
        closeTo(pixelsBefore, 0.5),
        reason: '锚点上方没有增删 ⇒ 不该做任何补偿滚动（避免无意义滚动）',
      );
    });

    testWidgets('滚动内容长度不变时不做无意义滚动（pixels 不动）', (tester) async {
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

      await tester.drag(
        find.byKey(const ValueKey('session-list-scroll')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      final pixelsBefore = _pixels(tester);

      // 只改标题/消息数等字段：布局签名不变。
      api.sessions = [
        for (var i = 0; i < 40; i++)
          SessionSummary(
            sessionId: 'old-$i',
            title: '会话 $i（已更新标题）',
            messageCount: i + 1,
            workspace: '/ws/main',
            lastMessageAt: _sec(now.subtract(Duration(minutes: i))),
          ),
      ];
      await container
          .read(sessionListControllerProvider.notifier)
          .refreshIfStale(force: true);
      await tester.pumpAndSettle();

      expect(_pixels(tester), closeTo(pixelsBefore, 0.5));
    });
  });

  group('滚动/拖动中不换内容（settle 后再应用）', () {
    testWidgets('拖动中刷新：内容挂起，settle 后应用且锚点保持', (tester) async {
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

      // 手指按住并拖动（模拟用户正在浏览）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('session-list-scroll'))),
      );
      // 分两段：第一段穿越 touch slop（DragStartBehavior.start 会丢弃接受前的
      // 位移，单发大步长等于没拖），第二段才是真实滚动。
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -160));
      await tester.pump();
      expect(_pixels(tester), greaterThan(0.0));

      final anchor = _topVisibleRow(tester)!;
      final pixelsDuringDrag = _pixels(tester);

      // 刷新落到「手指还在拖」的窗口里。
      api.sessions = [
        _session('new-mid-drag', workspace: '/ws/main', at: now),
        ...api.sessions,
      ];
      await container
          .read(sessionListControllerProvider.notifier)
          .refreshIfStale(force: true);
      await tester.pump();
      await tester.pump();

      final rowHeight = tester
          .getSize(find.byKey(ValueKey('session-row-${anchor.id}')))
          .height;
      expect(_pixels(tester), closeTo(pixelsDuringDrag, 0.5));
      expect(
        _rowDy(tester, anchor.id),
        closeTo(anchor.dy, 0.5),
        reason: '拖动中不得把新内容塞进手指底下（挂起到 settle）',
      );

      // 松手 → settle → 新内容应用，且锚点行位置保持。
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        _pixels(tester),
        closeTo(pixelsDuringDrag + rowHeight, 1.0),
        reason: 'settle 后挂起内容必须补上（不得永久挂起）：锚点上方多一行 ⇒ 视口被补偿一行高',
      );
      expect(
        _rowDy(tester, anchor.id),
        closeTo(anchor.dy, 0.5),
        reason: 'settle 应用新内容后锚点行必须停在同一视口位置',
      );
    });
  });

  group('下拉刷新（语义 D：换筛选回顶之外的另一条重置路径）', () {
    testWidgets('下拉刷新换新内容后仍回到顶部，不被锚点归位拉走', (tester) async {
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

      // 下拉刷新会拉到「已换新」的列表（多一条最新会话，插在最上方）。
      api.sessions = [
        _session(
          'new-pull',
          workspace: '/ws/main',
          at: now.add(const Duration(hours: 1)),
        ),
        ...api.sessions,
      ];
      await tester.drag(
        find.byKey(const ValueKey('session-list-scroll')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();

      expect(api.fetchCount, greaterThan(1), reason: '下拉手势必须真的触发了一次刷新');
      expect(
        _pixels(tester),
        lessThanOrEqualTo(0.0),
        reason: '下拉刷新是「回顶」语义：任何锚点补偿都不得把列表留在滚动态',
      );
      expect(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .map((s) => s.sessionId),
        contains('new-pull'),
        reason: '下拉刷新必须真的把新内容换进来',
      );
    });
  });

  group('组顺序不随活动变化（列表页层）', () {
    testWidgets('在 beta 工作区发消息后，alpha 组仍在 beta 组上方', (tester) async {
      final now = DateTime(2026, 10, 6, 12);
      final api = FakeSessionListApi(
        sessions: [
          _session('a1', workspace: '/ws/alpha', at: now),
          _session(
            'a2',
            workspace: '/ws/alpha',
            at: now.subtract(const Duration(minutes: 5)),
          ),
          _session(
            'b1',
            workspace: '/ws/beta',
            at: now.subtract(const Duration(hours: 2)),
          ),
          _session(
            'b2',
            workspace: '/ws/beta',
            at: now.subtract(const Duration(hours: 3)),
          ),
        ],
      );
      final container = await pumpSessionList(tester, api);

      double headerDy(String workspacePath) => tester
          .getTopLeft(
            find.byKey(ValueKey('session-section-header-$workspacePath')),
          )
          .dy;

      expect(headerDy('/ws/alpha'), lessThan(headerDy('/ws/beta')));

      // beta 里来了新消息（活动时间变成最新）：组顺序必须一动不动。
      api.sessions = [
        _session(
          'a1',
          workspace: '/ws/alpha',
          at: now.subtract(const Duration(hours: 4)),
        ),
        _session(
          'a2',
          workspace: '/ws/alpha',
          at: now.subtract(const Duration(hours: 4, minutes: 5)),
        ),
        _session('b1', workspace: '/ws/beta', at: now),
        _session(
          'b2',
          workspace: '/ws/beta',
          at: now.subtract(const Duration(hours: 3)),
        ),
      ];
      await container
          .read(sessionListControllerProvider.notifier)
          .refreshIfStale(force: true);
      await tester.pumpAndSettle();

      expect(
        headerDy('/ws/alpha'),
        lessThan(headerDy('/ws/beta')),
        reason: '发消息只改活动时间 ⇒ 工作区组顺序不得变化',
      );
      expect(
        _rowDy(tester, 'b1'),
        lessThan(_rowDy(tester, 'b2')),
        reason: '组内仍按时间倒序',
      );
    });
  });
}
