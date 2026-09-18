import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_session_list_api.dart';

ServerConnection _conn() {
  return ServerConnection(
    id: 'c1',
    name: 'Test',
    baseUrl: 'http://test.local:30002',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

class _StubActiveConnection extends ActiveConnectionController {
  _StubActiveConnection(this._connection);
  final ServerConnection _connection;
  @override
  ServerConnection? build() => _connection;
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

ProviderContainer _makeContainer(
  FakeSessionListApi sessionApi, {
  FakeChatApi? chatApi,
}) {
  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      if (chatApi != null) chatApiProvider.overrideWithValue(chatApi),
      sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      activeConnectionProvider.overrideWith(
        () => _StubActiveConnection(_conn()),
      ),
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => FakeOnboardingLoginApi(),
      ),
    ],
  );
}

void main() {
  group('SessionSummary.withStreaming', () {
    test('置位 isStreaming 与 activeStreamId', () {
      const summary = SessionSummary(
        sessionId: 's1',
        title: '测试会话',
        messageCount: 5,
      );
      final streaming = summary.withStreaming(
        isStreaming: true,
        activeStreamId: 'stream-123',
      );
      expect(streaming.isStreaming, isTrue);
      expect(streaming.activeStreamId, 'stream-123');
      expect(streaming.title, '测试会话');
      expect(streaming.messageCount, 5);

      final idle = streaming.withStreaming(isStreaming: false);
      expect(idle.isStreaming, isFalse);
      expect(idle.activeStreamId, isNull);
      expect(idle.title, '测试会话');
      expect(idle.messageCount, 5);
    });
  });

  group('SessionListController.markStreaming', () {
    test('本地乐观置位即时更新 sessions / searchResults / archivedSessions', () async {
      final session = const SessionSummary(
        sessionId: 's1',
        title: '会话 1',
        createdAt: 1000,
        messageCount: 2,
      );
      final api = FakeSessionListApi(sessions: [session]);
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      // 乐观标记为流式
      controller.markStreaming('s1', true, activeStreamId: 'stream-abc');

      var state = container.read(sessionListControllerProvider).valueOrNull!;
      var s1 = state.sessions.firstWhere((s) => s.sessionId == 's1');
      expect(s1.isStreaming, isTrue);
      expect(s1.activeStreamId, 'stream-abc');

      // 标记为结束流式
      controller.markStreaming('s1', false);
      state = container.read(sessionListControllerProvider).valueOrNull!;
      s1 = state.sessions.firstWhere((s) => s.sessionId == 's1');
      expect(s1.isStreaming, isFalse);
      expect(s1.activeStreamId, isNull);
    });

    test('流式进行中执行 refresh() 不会因服务端全量列表延迟而冲掉流式指示', () async {
      final session = const SessionSummary(
        sessionId: 's1',
        title: '会话 1',
        createdAt: 1000,
        messageCount: 2,
        isStreaming: false,
      );
      final api = FakeSessionListApi(sessions: [session]);
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      // 开启流式
      controller.markStreaming('s1', true, activeStreamId: 'stream-active');

      // 模拟全量刷新（服务端 sessions 返回的数据仍为 isStreaming: false）
      await controller.refresh();

      final state = container.read(sessionListControllerProvider).valueOrNull!;
      final s1 = state.sessions.firstWhere((s) => s.sessionId == 's1');
      expect(s1.isStreaming, isTrue);
      expect(s1.activeStreamId, 'stream-active');
    });

    test('后台单会话状态校验纠偏：服务端确认结束时自动恢复静止态', () async {
      final session = const SessionSummary(
        sessionId: 's1',
        title: '会话 1',
        createdAt: 1000,
        messageCount: 2,
      );
      final api = FakeSessionListApi(sessions: [session]);
      // 服务端返回该会话已不再流式
      api.statusResponses['s1'] = const SessionStatusResponse(
        sessionId: 's1',
        isStreaming: false,
        activeStreamId: null,
      );
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.markStreaming(
        's1',
        true,
        activeStreamId: 'stream-old',
        verifyInBackground: true,
      );

      // 等待后台异步校验完成
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(api.statusCalls, contains('s1'));
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      final s1 = state.sessions.firstWhere((s) => s.sessionId == 's1');
      expect(s1.isStreaming, isFalse);
      expect(s1.activeStreamId, isNull);
    });

    test('后台单会话状态校验异常时静默容错，保留本地乐观状态', () async {
      final session = const SessionSummary(
        sessionId: 's1',
        title: '会话 1',
        createdAt: 1000,
        messageCount: 2,
      );
      final api = FakeSessionListApi(sessions: [session]);
      api.statusError = HttpException(500, null, message: 'Status error');
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.markStreaming(
        's1',
        true,
        activeStreamId: 'stream-1',
        verifyInBackground: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      final state = container.read(sessionListControllerProvider).valueOrNull!;
      final s1 = state.sessions.firstWhere((s) => s.sessionId == 's1');
      expect(s1.isStreaming, isTrue);
      expect(s1.activeStreamId, 'stream-1');
      expect(state.actionError, isNull);
    });
  });

  group('ChatController 与 SessionListController 联动', () {
    test('发送并建流后，会话列表行即时同步 activeStreamId 与 streaming 指示', () async {
      final chatApi = FakeChatApi();
      chatApi.startChatResult = {'stream_id': 'stream-999', 'session_id': 's1'};
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(sessionId: 's1', title: '会话 1', createdAt: 1000),
        ],
      );
      final container = _makeContainer(sessionApi, chatApi: chatApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final chatController = container.read(chatControllerProvider('s1').notifier);

      await chatController.send('测试发送');

      final listState =
          container.read(sessionListControllerProvider).valueOrNull!;
      final s1 = listState.sessions.firstWhere((s) => s.sessionId == 's1');
      expect(s1.isStreaming, isTrue);
      expect(s1.activeStreamId, 'stream-999');

      // done + stream_end 完成回合后恢复静止
      chatApi.emit(
        const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
      );
      chatApi.emit(const StreamEndSseEvent());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final endState =
          container.read(sessionListControllerProvider).valueOrNull!;
      final endS1 = endState.sessions.firstWhere((s) => s.sessionId == 's1');
      expect(endS1.isStreaming, isNot(true));
      expect(endS1.activeStreamId, isNull);
    });
  });

  group('SessionListPage UI widget 流式指示', () {
    testWidgets('流式状态下无需下拉，会话行立即渲染 CupertinoActivityIndicator', (tester) async {
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(
            sessionId: 's1',
            title: '正在回答的会话',
            createdAt: 1000,
            isStreaming: true,
            activeStreamId: 'stream-1',
          ),
          const SessionSummary(
            sessionId: 's2',
            title: '静止会话',
            createdAt: 900,
            isStreaming: false,
          ),
        ],
      );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            activeConnectionProvider.overrideWith(
              () => _StubActiveConnection(_conn()),
            ),
            onboardingApiFactoryProvider.overrideWithValue(
              (baseUrl, headers) => FakeOnboardingLoginApi(),
            ),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();

      // s1 处于流式状态 → 渲染 CupertinoActivityIndicator 与 Active 语义
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Active'), findsOneWidget);

      // s2 静止 → 渲染普通省略号图标
      expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);
    });
  });

  group('流式状态看门狗（#141 P2-1）', () {
    /// 缩短看门狗超时，避免用例真等 5 分钟。
    void useShortTimeout() {
      sessionStreamingWatchdogTimeout = const Duration(milliseconds: 40);
      addTearDown(
        () => sessionStreamingWatchdogTimeout = const Duration(minutes: 5),
      );
    }

    SessionSummary s1Of(ProviderContainer c) => c
        .read(sessionListControllerProvider)
        .valueOrNull!
        .sessions
        .firstWhere((s) => s.sessionId == 's1');

    Future<SessionListController> setup(
      ProviderContainer container,
      FakeSessionListApi api,
    ) async {
      await container.read(sessionListControllerProvider.future);
      return container.read(sessionListControllerProvider.notifier);
    }

    const session = SessionSummary(
      sessionId: 's1',
      title: '会话 1',
      createdAt: 1000,
      messageCount: 2,
    );

    test('看门狗到期且服务端确认非流式 → 自动清除（失焦无人收尾的兜底）', () async {
      useShortTimeout();
      final api = FakeSessionListApi(sessions: [session]);
      api.statusResponses['s1'] = const SessionStatusResponse(
        sessionId: 's1',
        isStreaming: false,
        activeStreamId: null,
      );
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container, api);
      // 不带 verifyInBackground：模拟窗口失焦时收不到任何收尾事件。
      controller.markStreaming('s1', true, activeStreamId: 'stream-stale');
      expect(s1Of(container).isStreaming, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(api.statusCalls, contains('s1'), reason: '看门狗到期应主动向服务端求证');
      expect(s1Of(container).isStreaming, isFalse, reason: '服务端确认结束即清除指示');
      expect(s1Of(container).activeStreamId, isNull);
    });

    test('看门狗到期但服务端仍报流式 → 保留指示并续期（不误伤长任务）', () async {
      useShortTimeout();
      final api = FakeSessionListApi(sessions: [session]);
      api.statusResponses['s1'] = const SessionStatusResponse(
        sessionId: 's1',
        isStreaming: true,
        activeStreamId: 'stream-live',
      );
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container, api);
      controller.markStreaming('s1', true, activeStreamId: 'stream-live');

      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(
        api.statusCalls.length,
        greaterThanOrEqualTo(2),
        reason: '服务端仍流式时应续期，后续继续求证',
      );
      expect(s1Of(container).isStreaming, isTrue, reason: '真在跑的长任务不得被误清');
    });

    test('看门狗求证失败 → 保留乐观状态但续期重试（不永久卡住）', () async {
      useShortTimeout();
      final api = FakeSessionListApi(sessions: [session]);
      api.statusError = HttpException(500, null, message: 'Status error');
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container, api);
      controller.markStreaming('s1', true, activeStreamId: 'stream-x');

      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(
        api.statusCalls.length,
        greaterThanOrEqualTo(2),
        reason: '求证失败也必须续期 —— 否则状态永久卡住（本轮修复的起因）',
      );
      expect(s1Of(container).isStreaming, isTrue, reason: '求证失败时保留乐观状态');
    });

    test('显式清除后看门狗取消，不再发起求证', () async {
      useShortTimeout();
      final api = FakeSessionListApi(sessions: [session]);
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container, api);
      controller.markStreaming('s1', true, activeStreamId: 'stream-y');
      controller.markStreaming('s1', false);

      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(api.statusCalls, isEmpty, reason: '已显式清除，看门狗应已取消');
    });
  });
}
