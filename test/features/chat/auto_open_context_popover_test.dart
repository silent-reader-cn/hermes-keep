import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/app/widgets/hermes_page_route.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_input_bar.dart';
import 'package:hermes_ui/features/chat/widgets/context_window_popover.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_session_list_api.dart';

ApiClient _buildTestClient() {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = _StubAdapter();
  return ApiClient(baseUrl: 'http://test.local:30002', dio: dio);
}

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/api/workspaces')) {
      return ResponseBody.fromString(
        jsonEncode({
          'workspaces': [
            {'path': '/home/user/workspace-1', 'name': 'Workspace 1'},
          ],
          'last': '/home/user/workspace-1',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
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

class _CustomRecentlyCreatedNotifier
    extends RecentlyCreatedSessionIdController {
  _CustomRecentlyCreatedNotifier(this._initial);
  final String? _initial;

  @override
  String? build() => _initial;
}

class _CustomAutoOpenContextNotifier
    extends AutoOpenContextOnNewSessionController {
  _CustomAutoOpenContextNotifier(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('新建会话自动打开 ContextWindowPopover', () {
    testWidgets('新建会话（recentlyCreatedSessionId 匹配）进入后自动弹出弹窗并清除标志', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's-new-1',
          'workspace': '/home/user/workspace-1',
          'model': 'gpt-4o',
          'context_length': 128000,
          'context_tokens': 1000,
        },
      };

      final client = _buildTestClient();
      final recentController = _CustomRecentlyCreatedNotifier('s-new-1');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
            recentlyCreatedSessionIdProvider.overrideWith(
              () => recentController,
            ),
            autoOpenContextOnNewSessionProvider.overrideWith(
              () => _CustomAutoOpenContextNotifier(true),
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's-new-1'),
              ),
            ),
          ),
        ),
      );

      // 初次渲染 + 异步消息加载 + postFrame 触发弹窗
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // 验证 ContextWindowPopover 已自动打开
      expect(find.byType(ContextWindowPopover), findsOneWidget);

      // 验证 recentlyCreatedSessionId 已被清空（防重复）
      expect(recentController.state, isNull);

      // 清理 overlay
      AdaptivePopover.closeTopOverlay();
      await tester.pumpAndSettle();
    });

    testWidgets('宽屏（>=900）下开关开启也不自动弹窗 —— 该设置视为未开启', (tester) async {
      // 宽屏的上下文弹层只剩读数（「当前模型 / 工作区」两个入口 2026-10-07 已移除）⇒
      // 自动弹出来没有任何可设置项 ⇒ 主人在宽屏下把开关打开也**一律视为未开启**。
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's-new-1',
          'workspace': '/home/user/workspace-1',
          'model': 'gpt-4o',
          'context_length': 128000,
          'context_tokens': 1000,
        },
      };

      final client = _buildTestClient();
      final recentController = _CustomRecentlyCreatedNotifier('s-new-1');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
            recentlyCreatedSessionIdProvider.overrideWith(
              () => recentController,
            ),
            autoOpenContextOnNewSessionProvider.overrideWith(
              () => _CustomAutoOpenContextNotifier(true),
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's-new-1'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // 宽屏 + 开关开启 ⇒ **不**弹窗
      expect(find.byType(ContextWindowPopover), findsNothing);
      // 「新建会话」标志照旧被消费（与开关无关的既有语义不受本改动影响）
      expect(recentController.state, isNull);
    });

    testWidgets('设置开关关闭时，新建会话不自动弹窗', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's-new-2',
          'workspace': '/home/user/workspace-1',
          'model': 'gpt-4o',
          'context_length': 128000,
          'context_tokens': 1000,
        },
      };

      final client = _buildTestClient();
      final recentController = _CustomRecentlyCreatedNotifier('s-new-2');
      final switchController = _CustomAutoOpenContextNotifier(false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
            recentlyCreatedSessionIdProvider.overrideWith(
              () => recentController,
            ),
            autoOpenContextOnNewSessionProvider.overrideWith(
              () => switchController,
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's-new-2'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // 验证弹窗未打开
      expect(find.byType(ContextWindowPopover), findsNothing);
    });

    testWidgets('进入已有历史会话（非新建）不自动弹窗', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's-existing',
          'workspace': '/home/user/workspace-1',
          'model': 'gpt-4o',
          'context_length': 128000,
          'context_tokens': 1000,
        },
      };

      final client = _buildTestClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's-existing'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // 验证已有会话不弹窗
      expect(find.byType(ContextWindowPopover), findsNothing);
    });

    testWidgets('自动弹窗仅触发一次，切出再切回不重复弹', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's-once',
          'workspace': '/home/user/workspace-1',
          'model': 'gpt-4o',
          'context_length': 128000,
          'context_tokens': 1000,
        },
      };

      final client = _buildTestClient();
      final recentController = _CustomRecentlyCreatedNotifier('s-once');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
            recentlyCreatedSessionIdProvider.overrideWith(
              () => recentController,
            ),
            autoOpenContextOnNewSessionProvider.overrideWith(
              () => _CustomAutoOpenContextNotifier(true),
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's-once'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(ContextWindowPopover), findsOneWidget);

      // 关闭弹层
      AdaptivePopover.closeTopOverlay();
      await tester.pumpAndSettle();
      expect(find.byType(ContextWindowPopover), findsNothing);

      // 切换到另一个会话
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
            recentlyCreatedSessionIdProvider.overrideWith(
              () => recentController,
            ),
            autoOpenContextOnNewSessionProvider.overrideWith(
              () => _CustomAutoOpenContextNotifier(true),
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's-other'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ContextWindowPopover), findsNothing);

      // 再次切回 s-once
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
            recentlyCreatedSessionIdProvider.overrideWith(
              () => recentController,
            ),
            autoOpenContextOnNewSessionProvider.overrideWith(
              () => _CustomAutoOpenContextNotifier(true),
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's-once'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 重进不再弹窗
      expect(find.byType(ContextWindowPopover), findsNothing);
    });

    testWidgets('首帧 snapshot 尚空时，待 snapshot 就绪后自动触发弹窗', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeChatApi = FakeChatApi();
      // 初始 sessionResult 无 contextWindow 信息（snapshot 为 null）
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's-delayed',
          'workspace': '/home/user/workspace-1',
          'model': 'gpt-4o',
        },
      };

      final client = _buildTestClient();
      final recentController = _CustomRecentlyCreatedNotifier('s-delayed');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
            recentlyCreatedSessionIdProvider.overrideWith(
              () => recentController,
            ),
            autoOpenContextOnNewSessionProvider.overrideWith(
              () => _CustomAutoOpenContextNotifier(true),
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's-delayed'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // snapshot 为空时弹窗未打开
      expect(find.byType(ContextWindowPopover), findsNothing);

      // 模拟更新 session 数据带有 snapshot
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's-delayed',
          'workspace': '/home/user/workspace-1',
          'model': 'gpt-4o',
          'context_length': 128000,
          'context_tokens': 1000,
        },
      };
      final element = tester.element(find.byType(ChatInputBar));
      final container = ProviderScope.containerOf(element);
      await container.read(chatControllerProvider('s-delayed').notifier).loadMessages();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // snapshot 到达后弹窗自动打开
      expect(find.byType(ContextWindowPopover), findsOneWidget);

      AdaptivePopover.closeTopOverlay();
      await tester.pumpAndSettle();
    });

    testWidgets('端到端流程：SessionListPage 点击新建会话 → 进入 /chat/:id 并自动打开弹窗', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeSessionApi = FakeSessionListApi(
        sessions: [
          SessionSummary(
            sessionId: 's-old',
            title: '旧会话',
            lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        ],
      );
      fakeSessionApi.createdSession = SessionSummary(
        sessionId: 's-brand-new',
        title: '新会话',
        lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
      );

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's-brand-new',
          'workspace': '/home/user/workspace-1',
          'model': 'gpt-4o',
          'context_length': 128000,
          'context_tokens': 1000,
        },
      };

      final client = _buildTestClient();

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
          GoRoute(
            path: '/chat/:sessionId',
            pageBuilder: (_, state) => HermesPage<void>(
              key: ValueKey('chat-${state.pathParameters['sessionId']}'),
              builder: (_) => CupertinoPageScaffold(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ChatInputBar(
                    sessionId: state.pathParameters['sessionId'] ?? '',
                  ),
                ),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            sessionListApiFactoryProvider.overrideWithValue(
              (_) => fakeSessionApi,
            ),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            chatApiProvider.overrideWithValue(fakeChatApi),
            autoOpenContextOnNewSessionProvider.overrideWith(
              () => _CustomAutoOpenContextNotifier(true),
            ),
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

      // 点击新建会话按钮（FAB）
      final newButtonFinder = find.byKey(const ValueKey('session-list-new'));
      expect(newButtonFinder, findsOneWidget);

      await tester.tap(newButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // 验证自动打开 ContextWindowPopover
      expect(find.byType(ContextWindowPopover), findsOneWidget);

      // 清理 overlay
      AdaptivePopover.closeTopOverlay();
      await tester.pumpAndSettle();
    });
  });
}
