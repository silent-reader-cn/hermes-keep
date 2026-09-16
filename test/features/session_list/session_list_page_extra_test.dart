import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_session_list_api.dart';

/// 秒级时间戳辅助。
double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(
  String? id,
  String? title, {
  bool pinned = false,
  bool archived = false,
  int? messageCount,
  double? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    archived: archived,
    messageCount: messageCount,
    lastMessageAt: at ?? _sec(DateTime.now()),
  );
}

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(middle: Text('chat-$sessionId')),
    child: const SizedBox(),
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

/// dio mock adapter：按路径返回预设响应，记录全部请求。
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({required this.responder});

  ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

/// 只取导出端点请求（页面同时会拉起 /api/sessions/events SSE）。
List<RequestOptions> _exportRequests(_MockAdapter adapter) => adapter.requests
    .where((r) => r.uri.path.contains('/api/session/export'))
    .toList();

ApiClient _adapterClient(_MockAdapter adapter) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = adapter;
  final publicDio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  publicDio.httpClientAdapter = adapter;
  return ApiClient(
    baseUrl: 'http://hermes.local:8787',
    dio: dio,
    publicMediaDio: publicDio,
  );
}

void main() {
  setUp(() => SafeClipboard.resetOverridesForTesting());
  tearDown(() => SafeClipboard.resetOverridesForTesting());

  Future<void> pumpList(
    WidgetTester tester,
    FakeSessionListApi api, {
    ApiClient? client,
    Size size = const Size(800, 1200),
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
        GoRoute(
          path: '/chat',
          builder: (_, _) => const _ChatStub(sessionId: ''),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            client ?? ApiClient(baseUrl: 'http://test.local:30002'),
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

  /// 打开首行行操作菜单。
  Future<void> openRowActions(WidgetTester tester, String sessionId) async {
    await tester.tap(find.byKey(ValueKey('session-actions-$sessionId')));
    await tester.pumpAndSettle();
  }

  group('会话导出弹层 _showExportFormat（page 1082-1187）', () {
    testWidgets('行菜单「导出」→ 弹出 Markdown / JSON 两个格式动作', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api);
      await openRowActions(tester, 's1');

      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();

      expect(find.text('导出会话'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-export-markdown')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('session-export-json')), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
    });

    testWidgets('取消导出弹层（返回 null）→ 不发任何导出请求', (tester) async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('body', 200),
      );
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api, client: _adapterClient(adapter));
      await openRowActions(tester, 's1');
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();

      // 点击遮罩关闭弹层 → format == null → 直接 return
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('导出会话'), findsNothing);
      // 会话事件 SSE（/api/sessions/events）不计入：只断言导出端点未被调用。
      expect(_exportRequests(adapter), isEmpty);
      expect(find.text('导出成功'), findsNothing);
    });

    testWidgets('选 Markdown → 请求 format=md 并展示导出内容', (tester) async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('md-export-body', 200),
      );
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api, client: _adapterClient(adapter));
      await openRowActions(tester, 's1');
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('session-export-markdown')));
      await tester.pumpAndSettle();

      final exportRequests = _exportRequests(adapter);
      expect(exportRequests, hasLength(1));
      final uri = exportRequests.single.uri;
      expect(uri.path, contains('/api/session/export'));
      expect(uri.query, contains('format=md'));
      expect(uri.query, contains('session_id=s1'));
      expect(find.text('markdown 导出成功'), findsOneWidget);
      expect(find.text('md-export-body'), findsOneWidget);
      expect(find.text('复制内容'), findsOneWidget);

      // 「关闭」直接收起成功弹窗。
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('markdown 导出成功'), findsNothing);
    });

    testWidgets('导出弹层「取消」按钮 → 关闭且不发导出请求', (tester) async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('body', 200),
      );
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api, client: _adapterClient(adapter));
      await openRowActions(tester, 's1');
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('导出会话'), findsNothing);
      expect(_exportRequests(adapter), isEmpty);
    });

    testWidgets('选 JSON → 请求 format=json；内容为空时展示空态文案', (tester) async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('', 200),
      );
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api, client: _adapterClient(adapter));
      await openRowActions(tester, 's1');
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('session-export-json')));
      await tester.pumpAndSettle();

      expect(_exportRequests(adapter).single.uri.query, contains('format=json'));
      expect(find.text('json 导出成功'), findsOneWidget);
      expect(find.text('导出内容为空'), findsOneWidget);
    });

    testWidgets('成功弹窗「复制内容」→ 超限落盘并弹出二次提示', (tester) async {
      // maxBytesOverride = 0 → 一律走文件落盘分支（避免真实剪贴板插件）。
      final dir = Directory.systemTemp.createTempSync('hermes_export_extra');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      SafeClipboard.maxBytesOverride = 0;
      SafeClipboard.destinationDirOverride = dir;

      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('body-to-save', 200),
      );
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api, client: _adapterClient(adapter));
      await openRowActions(tester, 's1');
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-export-markdown')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('复制内容'));
      await tester.pumpAndSettle();

      expect(find.text('导出成功'), findsWidgets);
      expect(find.text('好'), findsOneWidget);
      final saved = dir.listSync().whereType<File>().toList();
      expect(saved, hasLength(1));
      expect(saved.single.readAsStringSync(), 'body-to-save');

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('好'), findsNothing);
    });

    testWidgets('导出失败（非 2xx）→ 展示「导出失败」+ 错误信息', (tester) async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('server exploded', 500),
      );
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api, client: _adapterClient(adapter));
      await openRowActions(tester, 's1');
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('session-export-markdown')));
      await tester.pumpAndSettle();

      expect(find.text('导出失败'), findsOneWidget);
      expect(find.text('服务器返回 HTTP 500。'), findsOneWidget);
      expect(find.text('好'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('导出失败'), findsNothing);
    });
  });

  group('行菜单：分支 / 归档 / 恢复归档 / 删除取消（page 1004-1066、1215）', () {
    testWidgets('「分支」→ controller.branch 成功并跳转 /chat/<新 id>', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api);
      await openRowActions(tester, 's1');

      await tester.tap(find.byKey(const ValueKey('session-action-branch')));
      await tester.pumpAndSettle();

      expect(api.branchCalls, ['s1']);
      expect(find.text('chat-branch-1'), findsOneWidget);
    });

    testWidgets('「分支」失败 → 不跳页，弹出操作失败提示', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      api.branchError = HttpException(500, 'x', message: '分支服务故障');
      await pumpList(tester, api);
      await openRowActions(tester, 's1');

      await tester.tap(find.byKey(const ValueKey('session-action-branch')));
      await tester.pumpAndSettle();

      expect(find.text('操作失败'), findsOneWidget);
      expect(find.text('分支服务故障'), findsOneWidget);
      expect(find.textContaining('chat-'), findsNothing);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
    });

    testWidgets('「归档」→ setArchived(true) 并从列表移除', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', '会话 1'), _session('s2', '会话 2')],
      );
      await pumpList(tester, api);
      await openRowActions(tester, 's1');

      await tester.tap(find.byKey(const ValueKey('session-action-archive')));
      await tester.pumpAndSettle();

      expect(api.archiveCalls, ['s1:true']);
      expect(find.byKey(const ValueKey('session-row-s1')), findsNothing);
      expect(find.byKey(const ValueKey('session-row-s2')), findsOneWidget);
    });

    testWidgets('已归档行 →「恢复归档」→ setArchived(false)', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_session('a1', '归档会话', archived: true)],
      );
      await pumpList(tester, api);

      // 切到「已归档」筛选视图
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sheet-filter-archived')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-row-a1')), findsOneWidget);

      await openRowActions(tester, 'a1');
      expect(
        find.byKey(const ValueKey('session-action-unarchive')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('session-action-unarchive')),
      );
      await tester.pumpAndSettle();

      expect(api.archiveCalls, ['a1:false']);
    });

    testWidgets('删除确认框「取消」→ 不调用 delete', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api);
      await openRowActions(tester, 's1');

      await tester.tap(find.byKey(const ValueKey('session-action-delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('确定删除'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('session-delete-cancel')));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, isEmpty);
      expect(find.byKey(const ValueKey('session-row-s1')), findsOneWidget);
    });
  });

  group('批量操作确认框取消（page 1243、1279）', () {
    Future<void> enterSelectionMode(
      WidgetTester tester,
      FakeSessionListApi api,
    ) async {
      await pumpList(tester, api);
      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batch-select-all')), findsOneWidget);
    }

    testWidgets('批量归档确认框「取消」→ 不调用 archiveSession', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await enterSelectionMode(tester, api);

      await tester.tap(find.byKey(const ValueKey('batch-archive')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batch-archive-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('batch-archive-cancel')));
      await tester.pumpAndSettle();

      expect(api.archiveCalls, isEmpty);
      expect(find.byKey(const ValueKey('session-row-s1')), findsOneWidget);
    });

    testWidgets('批量删除确认框「取消」→ 不调用 deleteSession', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await enterSelectionMode(tester, api);

      await tester.tap(find.byKey(const ValueKey('batch-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batch-delete-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('batch-delete-cancel')));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, isEmpty);
      expect(find.byKey(const ValueKey('session-row-s1')), findsOneWidget);
    });

    testWidgets('批量归档确认「确认」→ 调用 archiveSession（对照组）', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await enterSelectionMode(tester, api);

      await tester.tap(find.byKey(const ValueKey('batch-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-archive-confirm')));
      await tester.pumpAndSettle();

      expect(api.archiveCalls, ['s1:true']);
    });
  });

  group('空态 / 错误态 / 标题兜底（page 714-767、1336-1339、1676-1682）', () {
    testWidgets('空列表 → 空态按钮可新建会话并跳转', (tester) async {
      final api = FakeSessionListApi();
      api.createdSession = const SessionSummary(
        sessionId: 'empty-new-1',
        title: '空态新建',
      );
      await pumpList(tester, api);

      expect(find.text('暂无会话'), findsOneWidget);
      final emptyButton = find.byKey(const ValueKey('session-list-empty-new'));
      expect(emptyButton, findsOneWidget);

      await tester.tap(emptyButton);
      await tester.pumpAndSettle();

      expect(api.createCount, 1);
      expect(api.lastCreatedWorkspace, isNull);
      expect(find.text('chat-empty-new-1'), findsOneWidget);
    });

    testWidgets('非 ApiException 错误 → 错误态展示 error.toString()', (tester) async {
      final api = FakeSessionListApi()..fetchError = StateError('boom');
      await pumpList(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('Bad state: boom'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-list-retry')),
        findsOneWidget,
      );
    });

    testWidgets('ApiException 错误 → 展示归一化 message', (tester) async {
      final api = FakeSessionListApi()
        ..fetchError = HttpException(500, 'x', message: '服务器内部错误');
      await pumpList(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('服务器内部错误'), findsOneWidget);
    });

    testWidgets('标题为空 / 空白 → 行内回落到「未命名会话」', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          _session('n1', null, messageCount: 3),
          _session('n2', '   ', messageCount: 1),
        ],
      );
      await pumpList(tester, api);

      expect(find.text('未命名会话'), findsNWidgets(2));
    });
  });

  group('窄屏大标题点击 = 打开快捷导航下拉（page 327-328）', () {
    testWidgets('点击「会话」大标题 → 展开 ▾ 同一快捷导航下拉', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(tester, api, size: const Size(700, 1200));

      expect(
        find.byKey(const ValueKey('session-list-narrow-nav')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsNothing);

      final title = find.text('会话');
      expect(title, findsWidgets);
      await tester.tap(title.first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('narrow-nav-workspaces')),
        findsOneWidget,
      );
    });

    testWidgets('宽屏（≥900）无 ▾ 也不接线标题点击 → 点击标题不弹下拉', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      await pumpList(
        tester,
        api,
        size: const Size(1200, 1200),
      );

      expect(
        find.byKey(const ValueKey('session-list-narrow-nav')),
        findsNothing,
      );
    });
  });

  group('FAB 工作区扇出（page 933-938、2208-2211、2490-2502）', () {
    testWidgets('长按弹出后指针取消 → 菜单收起且不建会话', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      api.workspaces = [const WorkspaceRoot(path: '/ws/code', name: 'Code')];
      await pumpList(tester, api);

      final fabFinder = find.byKey(const ValueKey('session-list-new'));
      final gesture = await tester.startGesture(tester.getCenter(fabFinder));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsOneWidget);

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsNothing);
      expect(api.createCount, 0);
    });

    testWidgets('无名工作区 → 显示名由 path 末段派生（含无斜杠与仅斜杠）', (tester) async {
      final api = FakeSessionListApi(sessions: [_session('s1', '会话 1')]);
      api.workspaces = const [
        WorkspaceRoot(path: '/deep/nest/code'),
        WorkspaceRoot(path: 'plain'),
        WorkspaceRoot(path: '/'),
      ];
      await pumpList(tester, api);

      final fabFinder = find.byKey(const ValueKey('session-list-new'));
      final gesture = await tester.startGesture(tester.getCenter(fabFinder));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('fab-workspace-item-/deep/nest/code')),
        findsOneWidget,
      );
      expect(find.text('code'), findsOneWidget);
      expect(find.text('plain'), findsOneWidget);

      await gesture.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets('computeFabWorkspaceLayout：无可行角度时回落首圈窗口', (tester) async {
      // 屏幕有尺寸但 FAB 贴近上边缘 → 上边界约束把首圈窗口判死。
      final topEdge = computeFabWorkspaceLayout(
        total: 1,
        fabCenter: const Offset(500, 20),
        screenSize: const Size(800, 1000),
      );
      expect(topEdge, hasLength(1));
      expect(topEdge.single.radius, kFabWorkspaceFirstRadius);
      expect(topEdge.single.ringIndex, 0);

      // 无屏幕信息 + FAB 在最左上 → 左边界约束判死。
      final leftEdge = computeFabWorkspaceLayout(
        total: 2,
        fabCenter: const Offset(-100, -100),
      );
      expect(leftEdge, hasLength(2));
      expect(
        leftEdge.every((g) => g.radius == kFabWorkspaceFirstRadius),
        isTrue,
      );

      expect(
        computeFabWorkspaceLayout(total: 0, fabCenter: Offset.zero),
        isEmpty,
      );
    });

    testWidgets('getFabWorkspaceItemGeometry 与整表布局一致', (tester) async {
      const center = Offset(400, 800);
      final layout = computeFabWorkspaceLayout(
        total: 3,
        fabCenter: center,
        screenSize: const Size(800, 1000),
      );
      for (var i = 0; i < 3; i++) {
        final single = getFabWorkspaceItemGeometry(i, 3, center);
        expect(single.center, layout[i].center);
        expect(single.angleDeg, layout[i].angleDeg);
      }
    });
  });
}
