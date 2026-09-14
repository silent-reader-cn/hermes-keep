import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/session_list/session_list_header.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_session_list_api.dart';

/// 秒级时间戳辅助（会话模型时间字段为 epoch 秒）。
double sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary buildSession(
  String id,
  String title, {
  bool pinned = false,
  DateTime? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    lastMessageAt: sec(at ?? DateTime.now()),
  );
}

/// 构造测试用服务器连接（自动重登用例注入 active 连接）。
ServerConnection _buildConn({String? password}) {
  return ServerConnection(
    id: 'conn-test',
    name: 'Test',
    baseUrl: 'http://test.local:30002',
    password: password,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
///
/// [active] 非空时注入激活连接（自动重登用例携带已保存密码）；
/// [loginApi] 非空时注入登录 fake（记录自动重登调用）。
ProviderContainer makeContainer(
  FakeSessionListApi api, {
  ServerConnection? active,
  FakeOnboardingLoginApi? loginApi,
}) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      // 列表页 now 会 watch 项目（项目筛选 chips）：注入空列表 stub，
      // 避免真实 ApiClient 发出 dio 请求残留超时 Timer。
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      if (active != null)
        activeConnectionProvider.overrideWith(
          () => _StubActiveConnection(active),
        ),
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => loginApi ?? FakeOnboardingLoginApi(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 固定返回注入连接的 active 控制器 stub（跳过异步加载，测试可控）。
class _StubActiveConnection extends ActiveConnectionController {
  _StubActiveConnection(this._connection);

  final ServerConnection _connection;

  @override
  ServerConnection? build() => _connection;
}

void main() {
  group('buildSessionSections 分区', () {
    test('置顶 / 今天 / 昨天 / 更早 分组，组内时间倒序，空组剔除', () {
      final now = DateTime(2026, 8, 16, 12);
      final pinned = buildSession('p1', '置顶会话', pinned: true, at: now);
      final today = buildSession(
        't1',
        '今天会话',
        at: now.subtract(const Duration(hours: 1)),
      );
      final yesterday = buildSession(
        'y1',
        '昨天会话',
        at: now.subtract(const Duration(days: 1)),
      );
      final earlier = buildSession(
        'e1',
        '更早会话',
        at: now.subtract(const Duration(days: 10)),
      );
      final noTimestamp = buildSession(
        'n1',
        '无时间戳',
        at: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final sections = buildSessionSections([
        noTimestamp,
        earlier,
        yesterday,
        today,
        pinned,
      ], now: now);

      expect(sections.map((s) => s.title).toList(), ['置顶', '今天', '昨天', '更早']);
      expect(sections[0].sessions.map((s) => s.sessionId), ['p1']);
      expect(sections[1].sessions.map((s) => s.sessionId), ['t1']);
      expect(sections[2].sessions.map((s) => s.sessionId), ['y1']);
      // 更早：e1（10 天前）在前，无时间戳（0）在后
      expect(sections[3].sessions.map((s) => s.sessionId), ['e1', 'n1']);
    });

    test('全空输入 → 无分区', () {
      expect(
        buildSessionSections(const [], now: DateTime(2026, 1, 1)),
        isEmpty,
      );
    });
  });

  group('SessionListController 状态机', () {
    test('初始加载成功：AsyncData + 首屏分页窗口 + 派生可见列表', () async {
      final api = FakeSessionListApi(
        sessions: [buildSession('s1', 'A'), buildSession('s2', 'B')],
      );
      final container = makeContainer(api);

      await container.read(sessionListControllerProvider.future);
      final state = container.read(sessionListControllerProvider).valueOrNull!;

      expect(api.fetchCount, 1);
      expect(state.sessions, hasLength(2));
      expect(state.visibleCount, 2);
      expect(state.hasMore, isFalse);
      expect(state.searchQuery, isNull);
      expect(
        container
            .read(sessionListVisibleSessionsProvider)
            .map((s) => s.sessionId),
        ['s1', 's2'],
      );
    });

    test('初始加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      // 非内置连接：冷启动会先静默补偿一次（#111），持续失败后仍落 AsyncError。
      final container = makeContainer(api, active: _buildConn());

      await expectLater(
        container.read(sessionListControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(sessionListControllerProvider).hasError, isTrue);
      expect(container.read(sessionListControllerProvider).valueOrNull, isNull);
      // 首屏 1 次 + 冷启动补偿 1 次（补偿仍失败才落错误态）。
      expect(api.fetchCount, 2);

      api.fetchError = null;
      await container.read(sessionListControllerProvider.notifier).refresh();

      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions, hasLength(1));
      expect(state.visibleCount, 1);
    });

    test('初始 401 + 保存密码 → 自动重登成功 → 列表正常（fetch 2 / login 1）', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.fetchError = const UnauthorizedException();
      api.fetchErrorCap = 1; // 首次抛 401，重登后恢复
      final loginApi = FakeOnboardingLoginApi();
      final container = makeContainer(
        api,
        active: _buildConn(password: 'secret'),
        loginApi: loginApi,
      );

      await container.read(sessionListControllerProvider.future);
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions, hasLength(1));
      expect(api.fetchCount, 2);
      expect(loginApi.loginCalls, 1);
      expect(loginApi.lastPassword, 'secret');
    });

    test('初始 401 + 无密码 → 直接报错，不自动重登', () async {
      final api = FakeSessionListApi();
      api.fetchError = const UnauthorizedException();
      final loginApi = FakeOnboardingLoginApi();
      final container = makeContainer(
        api,
        active: _buildConn(),
        loginApi: loginApi,
      );

      await expectLater(
        container.read(sessionListControllerProvider.future),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(loginApi.loginCalls, 0);
      expect(api.fetchCount, 1);
    });

    test('初始 401 + 重登失败（密码错）→ 报错，login 1 次不再重试', () async {
      final api = FakeSessionListApi();
      api.fetchError = const UnauthorizedException();
      final loginApi = FakeOnboardingLoginApi()
        ..loginError = const UnauthorizedException();
      final container = makeContainer(
        api,
        active: _buildConn(password: 'wrong'),
        loginApi: loginApi,
      );

      await expectLater(
        container.read(sessionListControllerProvider.future),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(loginApi.loginCalls, 1);
      expect(api.fetchCount, 1);
    });

    test('401 → 重登成功但重试仍 401 → 报错不递归（fetch 2 / login 1）', () async {
      final api = FakeSessionListApi();
      api.fetchError = const UnauthorizedException();
      api.fetchErrorCap = 2; // 首轮 + 重登后重试各抛一次
      final loginApi = FakeOnboardingLoginApi();
      final container = makeContainer(
        api,
        active: _buildConn(password: 'secret'),
        loginApi: loginApi,
      );

      await expectLater(
        container.read(sessionListControllerProvider.future),
        throwsA(isA<UnauthorizedException>()),
      );
      // 防递归核心断言：登录只发生一次，不再无限循环
      expect(loginApi.loginCalls, 1);
      expect(api.fetchCount, 2);
    });

    test('分页：loadMore 每页 +50 展开窗口，耗尽后幂等', () async {
      final api = FakeSessionListApi(
        sessions: [
          for (var i = 0; i < 120; i++)
            SessionSummary(
              sessionId: 's$i',
              title: '会话 $i',
              createdAt: 1000.0 + i,
            ),
        ],
      );
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      var state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.visibleCount, 50);
      expect(state.hasMore, isTrue);

      await controller.loadMore();
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.visibleCount, 100);
      expect(state.hasMore, isTrue);

      await controller.loadMore();
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.visibleCount, 120);
      expect(state.hasMore, isFalse);

      await controller.loadMore();
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.visibleCount,
        120,
      );

      expect(
        container.read(sessionListVisibleSessionsProvider),
        hasLength(120),
      );
    });

    test('搜索：命中 → 搜索模式展示命中；清空 → 恢复普通列表', () async {
      final api = FakeSessionListApi(
        sessions: [buildSession('s1', 'A'), buildSession('s2', 'B')],
      );
      api.searchResults['bug'] = [buildSession('r1', '修复 bug')];
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      await controller.search('bug');
      var state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(api.searchQueries, ['bug']);
      expect(state.searchQuery, 'bug');
      expect(state.isSearching, isFalse);
      expect(state.searchResults!.map((s) => s.sessionId), ['r1']);
      expect(
        container
            .read(sessionListVisibleSessionsProvider)
            .map((s) => s.sessionId),
        ['r1'],
      );

      await controller.search('');
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.searchQuery, isNull);
      expect(state.searchResults, isNull);
      expect(container.read(sessionListVisibleSessionsProvider), hasLength(2));
    });

    test('搜索失败：actionError + 空结果；clearActionError 清除', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.searchError = HttpException(500, null, message: '搜索服务不可用');
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      await controller.search('bug');
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.searchQuery, 'bug');
      expect(state.isSearching, isFalse);
      expect(state.searchResults, isEmpty);
      expect(state.actionError, contains('搜索服务不可用'));

      await controller.clearActionError();
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        isNull,
      );
    });

    test('置顶：调 pin API 并本地更新 → 归入「置顶」分区', () async {
      final s1 = buildSession('s1', 'A');
      final api = FakeSessionListApi(sessions: [s1]);
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final ok = await controller.setPinned(s1, true);
      expect(ok, isTrue);
      expect(api.pinCalls, ['s1:true']);
      final updated = container
          .read(sessionListControllerProvider)
          .valueOrNull!
          .sessions
          .single;
      expect(updated.pinned, isTrue);
      final sections = container.read(sessionListSectionsProvider);
      expect(sections.single.title, '置顶');
    });

    test('归档：调 archive API 并从列表移除', () async {
      final api = FakeSessionListApi(
        sessions: [buildSession('s1', 'A'), buildSession('s2', 'B')],
      );
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final ok = await controller.setArchived(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .first,
        true,
      );
      expect(ok, isTrue);
      expect(api.archiveCalls, ['s1:true']);
      expect(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .map((s) => s.sessionId),
        ['s2'],
      );
    });

    test('删除：调 delete API 并从列表移除', () async {
      final api = FakeSessionListApi(
        sessions: [buildSession('s1', 'A'), buildSession('s2', 'B')],
      );
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final ok = await controller.delete(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .first,
      );
      expect(ok, isTrue);
      expect(api.deleteCalls, ['s1']);
      expect(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .map((s) => s.sessionId),
        ['s2'],
      );
    });

    test('分支：调 branch API，返回新 ID 并插入列表顶部', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.branchResponse = const SessionBranchResponse(
        sessionId: 'b1',
        title: '分支副本',
      );
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final id = await controller.branch(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .single,
      );
      expect(id, 'b1');
      expect(api.branchCalls, ['s1']);
      final sessions = container
          .read(sessionListControllerProvider)
          .valueOrNull!
          .sessions;
      expect(sessions.first.sessionId, 'b1');
      expect(sessions.first.title, '分支副本');
    });

    test('分支无返回标题：本地兜底 "原标题 (fork)"，即时插入且时间戳兜底',
        () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.branchResponse = const SessionBranchResponse(sessionId: 'b1');
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);
      final before = DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0;

      final id = await controller.branch(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .single,
      );
      expect(id, 'b1');
      final sessions = container
          .read(sessionListControllerProvider)
          .valueOrNull!
          .sessions;
      final inserted = sessions.first;
      expect(inserted.sessionId, 'b1');
      // 服务端未返回标题 → 本地对齐 hermes-webui 命名 "<原标题> (fork)"
      expect(inserted.title, 'A (fork)');
      // 时间戳兜底：缺失 createdAt 时填充 now，新会话立即归「今天」分区
      // 顶部（否则落「更早」末尾，列表看不到，需手动下拉刷新才出现）。
      expect(inserted.createdAt, isNotNull);
      expect(inserted.createdAt!, greaterThanOrEqualTo(before - 5));
      final sections = buildSessionSections(sessions);
      expect(sections.first.title, '今天');
      expect(sections.first.sessions.first.sessionId, 'b1');
    });

    test('分支失败（服务器未返回 ID）：actionError，列表不变', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.branchResponse = const SessionBranchResponse();
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final id = await controller.branch(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .single,
      );
      expect(id, isNull);
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.actionError, isNotNull);
      expect(state.sessions, hasLength(1));
    });

    test('新建会话：调 create API，返回新 ID 并插入顶部', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.createdSession = const SessionSummary(sessionId: 'n1', title: '新会话');
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final id = await controller.createSession();
      expect(id, 'n1');
      expect(api.createCount, 1);
      final sessions = container
          .read(sessionListControllerProvider)
          .valueOrNull!
          .sessions;
      expect(sessions.first.sessionId, 'n1');
    });

    test('行操作失败：actionError 提示，列表不变', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.pinError = HttpException(500, null, message: '置顶服务不可用');
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final ok = await controller.setPinned(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .single,
        true,
      );
      expect(ok, isFalse);
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.actionError, contains('置顶服务不可用'));
      expect(state.sessions, hasLength(1));
      expect(api.pinCalls, ['s1:true']);
    });
  });

  group('SessionListPage widget', () {
    Future<void> pumpSessionList(
      WidgetTester tester,
      FakeSessionListApi api, {
      ServerConnection? active,
    }) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
          GoRoute(
            path: '/chat',
            builder: (_, _) => const _ChatStub(sessionId: ''),
          ),
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
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            // 非内置连接：冷启动首屏失败会触发一次静默补偿（#111），需要
            // 注入 stub 避免真实 connections provider 读 secure storage。
            if (active != null)
              activeConnectionProvider.overrideWith(
                () => _StubActiveConnection(active),
              ),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
    }

    testWidgets('列表渲染：分区标题 + 会话行 + 置顶图标 + 悬浮按钮', (tester) async {
      // 用当天中午作基准，避免凌晨运行时「now - 2h」跨天落到昨天导致分区断言失败
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('p1', '置顶会话', pinned: true, at: noon),
          buildSession(
            't1',
            '今天会话',
            at: noon.subtract(const Duration(hours: 2)),
          ),
          buildSession(
            'e1',
            '更早会话',
            at: noon.subtract(const Duration(days: 5)),
          ),
        ],
      );
      await pumpSessionList(tester, api);

      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('更早'), findsOneWidget);
      expect(find.text('置顶会话'), findsOneWidget);
      expect(find.text('今天会话'), findsOneWidget);
      expect(find.text('更早会话'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.pin_fill), findsOneWidget);
      expect(find.byKey(const ValueKey('session-list-new')), findsOneWidget);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染列表', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '到了')]);
      api.fetchGate = Completer<void>();
      await pumpSessionList(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('到了'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('空态：暂无会话 + 新建会话入口', (tester) async {
      await pumpSessionList(tester, FakeSessionListApi());

      expect(find.text('暂无会话'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-list-empty-new')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('session-list-new')), findsOneWidget);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '恢复的会话')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      // 非内置连接：错误态要等冷启动补偿（#111）退避跑完才出现。
      await pumpSessionList(tester, api, active: _buildConn());
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('session-list-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('恢复的会话'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('点击会话行 → 跳转 /chat/:sessionId', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '第一个会话')]);
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-row-s1')));
      await tester.pumpAndSettle();

      expect(find.text('chat-s1'), findsOneWidget);
    });

    testWidgets('新建会话：悬浮 + 按钮创建并跳转 /chat/:id', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '已有会话')]);
      api.createdSession = const SessionSummary(
        sessionId: 'n1',
        title: '新建的会话',
      );
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-list-new')));
      await tester.pumpAndSettle();

      expect(api.createCount, 1);
      expect(find.text('chat-n1'), findsOneWidget);
    });

    testWidgets('搜索：350ms 防抖后远程搜索并展示命中', (tester) async {
      final now = DateTime.now();
      final api = FakeSessionListApi(
        sessions: [
          buildSession('s1', '第一个会话', at: now),
          buildSession('s2', '第二个会话', at: now),
        ],
      );
      api.searchResults['bug'] = [buildSession('r1', '修复 bug 的会话')];
      await pumpSessionList(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        'bug',
      );
      // 防抖窗口内不触发
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.searchCount, 0);

      // 防抖到期 → 远程搜索 → 展示命中、隐藏普通列表
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump();
      expect(api.searchCount, 1);
      expect(api.searchQueries, ['bug']);
      expect(find.text('搜索结果'), findsOneWidget);
      expect(find.text('修复 bug 的会话'), findsOneWidget);
      expect(find.text('第一个会话'), findsNothing);
    });

    testWidgets('下拉刷新：重新拉取列表', (tester) async {
      // CupertinoSliverRefreshControl 需要弹跳式（iOS）滚动物理才会上抛负偏移，
      // 测试默认 Android 平台（钳制物理）不会触发 —— 显式切到 iOS。
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final api = FakeSessionListApi(sessions: [buildSession('s1', '会话一')]);
      await pumpSessionList(tester, api);
      expect(api.fetchCount, 1);

      // 分步拖拽 + 每次 pump（让刷新指示器完成布局、越过触发阈值）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('session-list-scroll'))),
      );
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // 测试结束前还原平台（框架会在 teardown 前校验 foundation 变量已复位）。
      debugDefaultTargetPlatformOverride = null;
      expect(api.fetchCount, 2);
    });

    testWidgets('行操作：ellipsis 弹菜单 → 置顶生效', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '会话一')]);
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();
      expect(find.text('归档'), findsOneWidget);
      expect(find.text('分支'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('session-action-pin')));
      await tester.pumpAndSettle();

      expect(api.pinCalls, ['s1:true']);
      // 菜单关闭（归档文本消失），置顶后分区标题出现
      expect(find.text('归档'), findsNothing);
      expect(find.text('置顶'), findsOneWidget);
    });

    testWidgets('删除：确认弹窗 → 确认后移除行并显示空态', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '会话一')]);
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-action-delete')));
      await tester.pumpAndSettle();

      expect(find.text('删除会话'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('session-delete-confirm')));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, ['s1']);
      expect(find.text('暂无会话'), findsOneWidget);
    });

    testWidgets('行操作失败：弹窗展示错误并可在点击「好」后关闭', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '会话一')]);
      api.pinError = HttpException(500, null, message: '置顶服务不可用');
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-action-pin')));
      await tester.pumpAndSettle();

      expect(find.text('操作失败'), findsOneWidget);
      expect(find.textContaining('置顶服务不可用'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('操作失败'), findsNothing);
    });

    group('会话列表头部重构（移动端大标题 vs 桌面单行头部）', () {
      testWidgets('移动模式：渲染「会话」大标题，且头部与搜索栏之间无 0.5px 分隔线', (tester) async {
        final api = FakeSessionListApi(sessions: [buildSession('s1', '测试会话')]);
        await pumpSessionList(tester, api);

        // 包含大标题文字
        expect(find.text('会话'), findsWidgets);

        // 头部内不存在 0.5px 底部分隔线 Container
        final separatorFinder = find.descendant(
          of: find.byKey(const ValueKey('session-list-header')),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxHeight == 0.5,
          ),
        );
        expect(separatorFinder, findsNothing);
      });

      testWidgets('桌面侧栏模式：无「会话」大标题文字，搜索框与筛选/新建按钮同行并对齐', (tester) async {
        final api = FakeSessionListApi(sessions: [buildSession('s1', '测试会话')]);
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const SessionListPage(
                showUtilityRows: false,
                showSettingsTrailing: false,
                showFab: false,
              ),
            ),
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
              projectApiFactoryProvider.overrideWithValue(
                (_) => _StubProjectApi(),
              ),
            ],
            child: CupertinoApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        await tester.pump();

        // 1. 彻底移除「会话」大标题文本
        expect(find.text('会话'), findsNothing);

        // 2. 搜索框、筛选按钮、新建按钮均存在且仅渲染一个搜索框
        expect(
          find.byKey(const ValueKey('session-list-search')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('session-list-filter-trigger')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('session-list-header-new')),
          findsOneWidget,
        );

        // 3. 搜索框、筛选按钮、新建按钮与搜索框同行（垂直中心对齐）
        final searchRect = tester.getRect(
          find.byKey(const ValueKey('session-list-search')),
        );
        final filterRect = tester.getRect(
          find.byKey(const ValueKey('session-list-filter-trigger')),
        );
        final newRect = tester.getRect(
          find.byKey(const ValueKey('session-list-header-new')),
        );

        // 垂直居中对齐误差在合理阈值内
        expect(
          (searchRect.center.dy - filterRect.center.dy).abs(),
          lessThanOrEqualTo(2.0),
        );
        expect(
          (searchRect.center.dy - newRect.center.dy).abs(),
          lessThanOrEqualTo(2.0),
        );
        expect((filterRect.top - newRect.top).abs(), lessThanOrEqualTo(2.0));
        // 水平顺序：搜索框在左，筛选在中间，加号在右侧
        expect(searchRect.right, lessThanOrEqualTo(filterRect.left));
        expect(filterRect.right, lessThanOrEqualTo(newRect.left));

        // 4. 筛选按钮可正常触发筛选弹层
        await tester.tap(
          find.byKey(const ValueKey('session-list-filter-trigger')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('session-filter-sheet')),
          findsOneWidget,
        );
        await tester.tap(find.text('全部'));
        await tester.pumpAndSettle();

        // 5. 新建按钮可正常触发创建并跳转
        api.createdSession = const SessionSummary(
          sessionId: 'desktop-new-1',
          title: '桌面新建',
        );
        await tester.tap(find.byKey(const ValueKey('session-list-header-new')));
        await tester.pumpAndSettle();
        expect(api.createCount, 1);
        expect(find.text('chat-desktop-new-1'), findsOneWidget);
      });

      testWidgets('窄屏大标题模式：快捷导航 ▾ 贴在「会话」大标题右侧，筛选和设置在右侧', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final api = FakeSessionListApi(
          sessions: [
            buildSession('s1', '会话 1'),
          ],
        );

        await pumpSessionList(tester, api);
        await tester.pumpAndSettle();

        final narrowNavRect = tester.getRect(
          find.byKey(const ValueKey('session-list-narrow-nav')),
        );
        final filterRect = tester.getRect(
          find.byKey(const ValueKey('session-list-filter-trigger')),
        );
        final settingsRect = tester.getRect(
          find.byKey(const ValueKey('session-list-settings')),
        );

        // 验证水平排列结构: [会话 ▾] —————————— [筛选] [设置]
        // 1. 下拉按钮紧随标题右侧（left 大于 20，小于 150）
        expect(narrowNavRect.left, greaterThan(20.0));
        expect(narrowNavRect.left, lessThan(150.0));

        // 2. 下拉按钮与右侧操作栏之间存在明显空隙
        expect(narrowNavRect.right, lessThan(filterRect.left));

        // 3. 右侧操作栏为 [筛选] [设置]
        expect(filterRect.right, lessThanOrEqualTo(settingsRect.left));

        // 4. 垂直居中对齐
        expect(
          (narrowNavRect.center.dy - filterRect.center.dy).abs(),
          lessThanOrEqualTo(1.0),
        );
        expect(
          (filterRect.center.dy - settingsRect.center.dy).abs(),
          lessThanOrEqualTo(1.0),
        );
      });
    });
  });

  group('SessionListHeaderDelegate 独立组件单测', () {
    test('移动端模式：minExtent=barHeight, maxExtent=barHeight+largeTitleHeight', () {
      const delegate = SessionListHeaderDelegate(
        title: '会话',
        topPadding: 20,
        compactHeader: false,
      );
      expect(delegate.minExtent, 20 + 44.0);
      expect(delegate.maxExtent, 20 + 44.0 + 52.0);
    });

    test('桌面端模式：minExtent==maxExtent==topPadding+50.0', () {
      const delegate = SessionListHeaderDelegate(
        title: '会话',
        topPadding: 10,
        compactHeader: true,
      );
      expect(delegate.minExtent, 10 + 50.0);
      expect(delegate.maxExtent, 10 + 50.0);
    });

    test('shouldRebuild 涵盖 compactHeader 与 searchField 差异', () {
      const d1 = SessionListHeaderDelegate(title: 'A', compactHeader: false);
      const d2 = SessionListHeaderDelegate(title: 'A', compactHeader: true);
      const d3 = SessionListHeaderDelegate(
        title: 'A',
        compactHeader: true,
        searchField: SizedBox(),
      );

      expect(d1.shouldRebuild(d2), isTrue);
      expect(d2.shouldRebuild(d3), isTrue);
      expect(d1.shouldRebuild(d1), isFalse);
    });

    test('shouldRebuild 涵盖 titleTrailing 差异', () {
      const d1 = SessionListHeaderDelegate(title: 'A');
      const d2 = SessionListHeaderDelegate(
        title: 'A',
        titleTrailing: SizedBox(key: ValueKey('trailing')),
      );

      expect(d1.shouldRebuild(d2), isTrue);
      expect(d2.shouldRebuild(d1), isTrue);
    });

    testWidgets('titleTrailing 紧贴大标题右侧并在滚动时平滑过渡', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: CustomScrollView(
              controller: scrollController,
              slivers: const [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: SessionListHeaderDelegate(
                    title: '会话',
                    titleTrailing: SizedBox(
                      key: ValueKey('test-title-trailing'),
                      width: 44,
                      height: 44,
                    ),
                    actions: [
                      SizedBox(
                        key: ValueKey('test-action-button'),
                        width: 44,
                        height: 44,
                      ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 1000),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final trailingFinder = find.byKey(const ValueKey('test-title-trailing'));
      final actionFinder = find.byKey(const ValueKey('test-action-button'));
      expect(trailingFinder, findsOneWidget);
      expect(actionFinder, findsOneWidget);

      final expandedTrailingRect = tester.getRect(trailingFinder);
      final expandedActionRect = tester.getRect(actionFinder);

      // 展开态：trailing 在左侧标题之后，action 在屏幕右侧
      expect(expandedTrailingRect.left, greaterThan(20.0));
      expect(expandedTrailingRect.right, lessThan(expandedActionRect.left));
      expect(expandedActionRect.right, lessThanOrEqualTo(400.0));

      // 展开态：trailing 与 action 垂直居中对齐
      expect(
        (expandedTrailingRect.center.dy - expandedActionRect.center.dy).abs(),
        lessThanOrEqualTo(1.0),
      );

      // 向上滚动收起
      scrollController.jumpTo(100);
      await tester.pumpAndSettle();

      final collapsedTrailingRect = tester.getRect(trailingFinder);
      final collapsedActionRect = tester.getRect(actionFinder);

      // 收起态：trailing 与 action 同轴上升至导航栏高度
      expect(
        collapsedTrailingRect.center.dy,
        lessThan(expandedTrailingRect.center.dy),
      );
      expect(
        (collapsedTrailingRect.center.dy - collapsedActionRect.center.dy).abs(),
        lessThanOrEqualTo(1.0),
      );
      // 收起态中标题比大标题短，trailing 水平位置也向左收缩
      expect(collapsedTrailingRect.left, lessThan(expandedTrailingRect.left));
    });
  });
}

/// 聊天页占位（widget 测试用，显示收到的 sessionId 以断言跳转目标）。
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
