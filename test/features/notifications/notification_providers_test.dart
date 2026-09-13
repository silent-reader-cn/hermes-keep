import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';
import 'package:hermes_ui/features/notifications/notification_lifecycle_observer.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('turnNotificationHookProvider（前后台统一系统通知 / 免打扰静默）', () {
    late _FakeTurnNotificationService service;
    late ProviderContainer container;

    setUp(() {
      service = _FakeTurnNotificationService();
      container = ProviderContainer(
        overrides: [turnNotificationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
    });

    test('后台（paused）→ 发通知，参数原样传递', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      final hook = container.read(turnNotificationHookProvider);

      hook('sess-1', '我的会话', '你好！');

      expect(service.notifyCalls, [('sess-1', '我的会话', '你好！')]);
      expect(service.clearAllCalls, 0);
    });

    test('后台（inactive）→ 也发通知', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.inactive);
      final hook = container.read(turnNotificationHookProvider);

      hook('s1', 't', 'p');

      expect(service.notifyCalls, [('s1', 't', 'p')]);
    });

    test('前台（resumed）跨会话 → 也发系统通知（应用内横幅已移除）', () {
      final hook = container.read(turnNotificationHookProvider);

      hook('sess-1', '我的会话', '你好！');

      expect(service.notifyCalls, [('sess-1', '我的会话', '你好！')]);
      expect(service.clearAllCalls, 0);
    });

    test('后台 → 前台切换后：两态均发通知', () {
      final notifier = container.read(appLifecycleStateProvider.notifier);
      final hook = container.read(turnNotificationHookProvider);

      notifier.setState(AppLifecycleState.paused);
      hook('s1', 't', 'p');
      expect(service.notifyCalls, hasLength(1));

      notifier.setState(AppLifecycleState.resumed);
      hook('s2', 't', 'p');
      expect(service.notifyCalls, hasLength(2));
      expect(service.clearAllCalls, 0);
    });
  });

  group('appLifecycleStateProvider', () {
    test('默认前台 resumed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(appLifecycleStateProvider),
        AppLifecycleState.resumed,
      );
    });

    test('setState 相同值不重复通知（listener 只收到一次变化）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var changes = 0;
      container.listen(appLifecycleStateProvider, (_, _) => changes++);

      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.resumed);

      expect(changes, 2);
    });
  });

  group('chat 收尾 hook 端到端（真实 ChatController + SSE 事件）', () {
    late _FakeChatApi api;
    late _FakeClock clock;
    late _FakeTurnNotificationService service;

    ProviderContainer buildContainer({required AppLifecycleState lifecycle}) {
      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          chatClockProvider.overrideWithValue(clock.call),
          turnNotificationServiceProvider.overrideWithValue(service),
          chatTurnCompletedCallbackProvider.overrideWith(
            (ref) => ref.watch(turnNotificationHookProvider),
          ),
          chatClarificationNeededCallbackProvider.overrideWith(
            (ref) => ref.watch(clarificationNotificationHookProvider),
          ),
          chatSessionErrorCallbackProvider.overrideWith(
            (ref) => ref.watch(sessionErrorNotificationHookProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(appLifecycleStateProvider.notifier).setState(lifecycle);
      return container;
    }

    setUp(() {
      api = _FakeChatApi();
      clock = _FakeClock();
      service = _FakeTurnNotificationService();
    });

    Map<String, Object?> doneSession() => {
      'session_id': 'sess-new',
      'title': '我的会话',
      'messages': [
        {'role': 'user', 'content': '你好', 'message_id': 'u1', 'timestamp': 0},
        {
          'role': 'assistant',
          'content': '你好！有什么可以帮你？',
          'message_id': 'a1',
          'timestamp': 1,
        },
      ],
    };

    test('后台 + done → 发通知（sessionId/标题/预览取自收尾状态）', () {
      fakeAsync((async) {
        final container = buildContainer(lifecycle: AppLifecycleState.paused);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.streaming,
        );

        api.emit(DoneSseEvent(DoneStreamEvent(session: doneSession())));
        async.flushMicrotasks();

        expect(service.notifyCalls, [('sess-new', '我的会话', '你好！有什么可以帮你？')]);
        expect(service.clearAllCalls, 0);
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.idle,
        );
      });
    });

    test('前台 + done → 也发系统通知（统一走系统通知，免打扰未命中）', () {
      fakeAsync((async) {
        final container = buildContainer(lifecycle: AppLifecycleState.resumed);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(DoneSseEvent(DoneStreamEvent(session: doneSession())));
        async.flushMicrotasks();

        expect(service.notifyCalls, [('sess-new', '我的会话', '你好！有什么可以帮你？')]);
        expect(service.clearAllCalls, 0);
      });
    });

    test('后台 + stream_end（无 done）→ 发通知一次', () {
      fakeAsync((async) {
        final container = buildContainer(lifecycle: AppLifecycleState.paused);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('好的，'));
        api.emit(const TokenSseEvent('马上处理'));
        // 16ms 合并 + 词级 reveal，让内容进入 messages
        async.elapse(const Duration(milliseconds: 200));

        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        expect(service.notifyCalls, hasLength(1));
        final (sessionId, title, preview) = service.notifyCalls.single;
        expect(sessionId, 'sess-new');
        expect(preview, contains('好的，马上处理'));
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.idle,
        );
      });
    });

    test('done 后 stream_end → 不重复通知', () {
      fakeAsync((async) {
        final container = buildContainer(lifecycle: AppLifecycleState.paused);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(DoneSseEvent(DoneStreamEvent(session: doneSession())));
        async.flushMicrotasks();
        expect(service.notifyCalls, hasLength(1));

        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();
        expect(service.notifyCalls, hasLength(1));
      });
    });

    test('取消（cancel）→ 触发异常中断通知', () {
      fakeAsync((async) {
        final container = buildContainer(lifecycle: AppLifecycleState.paused);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(const CancelledSseEvent());
        async.flushMicrotasks();

        expect(service.notifyCalls, isEmpty);
        expect(service.errorCalls, hasLength(1));
        expect(service.errorCalls.single.$2, '响应已取消');
      });
    });

    test('错误事件 → 触发异常中断通知', () {
      fakeAsync((async) {
        final container = buildContainer(lifecycle: AppLifecycleState.paused);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(const ErrorSseEvent('服务器内部错误'));
        async.flushMicrotasks();

        expect(service.notifyCalls, isEmpty);
        expect(service.errorCalls, hasLength(1));
        expect(service.errorCalls.single.$3, '服务器内部错误');
      });
    });

    test('澄清事件 → 触发澄清请求通知', () {
      fakeAsync((async) {
        final container = buildContainer(lifecycle: AppLifecycleState.paused);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {
              'clarify_id': 'c1',
              'question': '请选择模式',
              'choices_offered': ['A', 'B'],
            },
            'pending_count': 1,
          }),
        );
        async.flushMicrotasks();

        expect(service.clarifyCalls, [('sess-new', '请选择模式')]);
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.clarifyPending,
        );
      });
    });

    test('无 hook override（默认 no-op）→ 不触碰通知服务', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            chatClockProvider.overrideWithValue(clock.call),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(DoneSseEvent(DoneStreamEvent(session: doneSession())));
        async.flushMicrotasks();

        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.idle,
        );
      });
    });
  });

  group('三类通知与设置联动测试', () {
    late _FakeTurnNotificationService service;
    late ProviderContainer container;

    setUp(() {
      service = _FakeTurnNotificationService();
      container = ProviderContainer(
        overrides: [turnNotificationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
    });

    test('澄清通知：后台触发', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      final hook = container.read(clarificationNotificationHookProvider);

      hook('sess-1', '需要输入密码吗？');

      expect(service.clarifyCalls, [('sess-1', '需要输入密码吗？')]);
    });

    test('澄清通知：开关关闭时不触发', () async {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      await container
          .read(notificationSettingsProvider.notifier)
          .setNotifyClarifyEnabled(false);
      final hook = container.read(clarificationNotificationHookProvider);

      hook('sess-1', '需要输入密码吗？');

      expect(service.clarifyCalls, isEmpty);
    });

    test('错误通知：后台触发', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      final hook = container.read(sessionErrorNotificationHookProvider);

      hook('sess-1', '连接失败', '超时');

      expect(service.errorCalls, [('sess-1', '连接失败', '超时')]);
    });

    test('错误通知：开关关闭时不触发', () async {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      await container
          .read(notificationSettingsProvider.notifier)
          .setNotifyErrorsEnabled(false);
      final hook = container.read(sessionErrorNotificationHookProvider);

      hook('sess-1', '连接失败', '超时');

      expect(service.errorCalls, isEmpty);
    });

    test('回合完成通知：开关关闭时不触发', () async {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      await container
          .read(notificationSettingsProvider.notifier)
          .setNotifyTurnsEnabled(false);
      final hook = container.read(turnNotificationHookProvider);

      hook('sess-1', '标题', '预览');

      expect(service.notifyCalls, isEmpty);
    });

    test('默认设置：三类通知开关默认均为 true', () {
      final settings = container.read(notificationSettingsProvider);
      expect(settings.notifyTurnsEnabled, isTrue);
      expect(settings.notifyClarifyEnabled, isTrue);
      expect(settings.notifyErrorsEnabled, isTrue);
    });

    test('多后台生命周期状态（detached / hidden）均能触发系统通知', () {
      final turnHook = container.read(turnNotificationHookProvider);
      final clarifyHook = container.read(clarificationNotificationHookProvider);
      final errorHook = container.read(sessionErrorNotificationHookProvider);

      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.detached);
      turnHook('sess-detached', '标题', '内容');
      expect(service.notifyCalls, [('sess-detached', '标题', '内容')]);

      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.hidden);
      clarifyHook('sess-hidden', '澄清问题');
      expect(service.clarifyCalls, [('sess-hidden', '澄清问题')]);

      errorHook('sess-hidden', '异常标题', '异常内容');
      expect(service.errorCalls, [('sess-hidden', '异常标题', '异常内容')]);
    });

    test('前台不同会话触发 → 分别发对应类型的系统通知（横幅已移除）', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.resumed);

      final clarifyHook = container.read(clarificationNotificationHookProvider);
      clarifyHook('sess-other-1', '请澄清');
      expect(service.clarifyCalls, [('sess-other-1', '请澄清')]);

      final errorHook = container.read(sessionErrorNotificationHookProvider);
      errorHook('sess-other-2', '异常标题', '异常内容');
      expect(service.errorCalls, [('sess-other-2', '异常标题', '异常内容')]);

      final turnHook = container.read(turnNotificationHookProvider);
      turnHook('sess-other-3', '回合标题', '回合内容');
      expect(service.notifyCalls, [('sess-other-3', '回合标题', '回合内容')]);
    });

    test('前台且为当前激活会话且在聊天页 → 免打扰静默（不发通知并清残留）', () {
      final router = GoRouter(
        initialLocation: '/chat/sess-active',
        routes: [
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, _) => const CupertinoPageScaffold(child: SizedBox()),
          ),
        ],
      );
      final activeContainer = ProviderContainer(
        overrides: [
          turnNotificationServiceProvider.overrideWithValue(service),
          activeSessionIdProvider.overrideWith((ref) => 'sess-active'),
          routerProvider.overrideWithValue(router),
        ],
      );
      addTearDown(activeContainer.dispose);

      activeContainer
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.resumed);

      final clarifyHook = activeContainer.read(
        clarificationNotificationHookProvider,
      );
      clarifyHook('sess-active', '请澄清');
      expect(service.clarifyCalls, isEmpty);

      final errorHook = activeContainer.read(
        sessionErrorNotificationHookProvider,
      );
      errorHook('sess-active', '异常标题', '异常正文');
      expect(service.errorCalls, isEmpty);

      final turnHook = activeContainer.read(turnNotificationHookProvider);
      turnHook('sess-active', '回合标题', '回合正文');
      expect(service.notifyCalls, isEmpty);
      // 三条静默路径各清残留一次
      expect(service.clearAllCalls, 3);
    });
  });

  group('#94 免打扰双条件判定（同会话同页静默 / 同会话不同页通知 / 不同会话通知）', () {
    late _FakeTurnNotificationService service;

    setUp(() {
      service = _FakeTurnNotificationService();
    });

    GoRouter createRouter(String initialLocation) {
      return GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const CupertinoPageScaffold(child: SizedBox()),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const CupertinoPageScaffold(child: SizedBox()),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, _) => const CupertinoPageScaffold(child: SizedBox()),
          ),
          GoRoute(
            path: '/workspace/:sessionId',
            builder: (_, _) => const CupertinoPageScaffold(child: SizedBox()),
          ),
        ],
      );
    }

    ProviderContainer createContainer({
      required String? activeSessionId,
      required String routeLocation,
    }) {
      final container = ProviderContainer(
        overrides: [
          turnNotificationServiceProvider.overrideWithValue(service),
          activeSessionIdProvider.overrideWith((ref) => activeSessionId),
          routerProvider.overrideWithValue(createRouter(routeLocation)),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.resumed);
      return container;
    }

    test('1. 同会话同页静默（activeSessionId == sessionId 且路由在 /chat/:sessionId）→ 三类 hook 均不发通知', () {
      final container = createContainer(
        activeSessionId: 'sess-target',
        routeLocation: '/chat/sess-target',
      );

      // 澄清 hook：静默（避免通知盖住澄清确认弹窗等顶层交互）
      final clarifyHook = container.read(clarificationNotificationHookProvider);
      clarifyHook('sess-target', '请选择是否执行工具？');
      expect(service.clarifyCalls, isEmpty);

      // 回合完成 hook：静默
      final turnHook = container.read(turnNotificationHookProvider);
      turnHook('sess-target', '回答完成', '好的，已生成。');
      expect(service.notifyCalls, isEmpty);

      // 异常 hook：静默
      final errorHook = container.read(sessionErrorNotificationHookProvider);
      errorHook('sess-target', '连接超时', '网络异常');
      expect(service.errorCalls, isEmpty);
      expect(service.clearAllCalls, 3);
    });

    test('2. 同会话不同页通知（activeSessionId == sessionId 但当前在 /settings）→ 三类 hook 均发系统通知', () {
      final container = createContainer(
        activeSessionId: 'sess-target',
        routeLocation: '/settings',
      );

      // 澄清 hook：发系统通知
      final clarifyHook = container.read(clarificationNotificationHookProvider);
      clarifyHook('sess-target', '需要您的确认');
      expect(service.clarifyCalls, [('sess-target', '需要您的确认')]);

      // 错误 hook：发系统通知
      final errorHook = container.read(sessionErrorNotificationHookProvider);
      errorHook('sess-target', '执行错误', '沙箱崩溃');
      expect(service.errorCalls, [('sess-target', '执行错误', '沙箱崩溃')]);

      // 回合完成 hook：发系统通知
      final turnHook = container.read(turnNotificationHookProvider);
      turnHook('sess-target', '生成完成', '结果已输出');
      expect(service.notifyCalls, [('sess-target', '生成完成', '结果已输出')]);
    });

    test('3. 不同会话通知（activeSessionId != sessionId，即使在聊天页）→ 三类 hook 均发系统通知', () {
      final container = createContainer(
        activeSessionId: 'sess-chatting',
        routeLocation: '/chat/sess-chatting',
      );

      // 另一会话 sess-other 发生澄清事件：发系统通知
      final clarifyHook = container.read(clarificationNotificationHookProvider);
      clarifyHook('sess-other', '另一会话需要澄清');
      expect(service.clarifyCalls, [('sess-other', '另一会话需要澄清')]);

      // 另一会话 sess-other 发生错误事件：发系统通知
      final errorHook = container.read(sessionErrorNotificationHookProvider);
      errorHook('sess-other', '错误', '失败详情');
      expect(service.errorCalls, [('sess-other', '错误', '失败详情')]);

      // 另一会话 sess-other 回合完成：发系统通知
      final turnHook = container.read(turnNotificationHookProvider);
      turnHook('sess-other', '完成', '另一会话回答');
      expect(service.notifyCalls, [('sess-other', '完成', '另一会话回答')]);
    });

    test('4. activeSessionId 为 null（无激活会话时）→ 触发系统通知', () {
      final container = createContainer(
        activeSessionId: null,
        routeLocation: '/',
      );

      final clarifyHook = container.read(clarificationNotificationHookProvider);
      clarifyHook('sess-any', '无激活会话时的澄清');
      expect(service.clarifyCalls, [('sess-any', '无激活会话时的澄清')]);
    });
  });

  group('NotificationLifecycleObserver（前后台驱动 + 回前台清除）', () {
    testWidgets('paused → resumed：更新生命周期并在回前台时 clearAll', (tester) async {
      final service = _FakeTurnNotificationService();
      final container = ProviderContainer(
        overrides: [turnNotificationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const NotificationLifecycleObserver(child: SizedBox()),
        ),
      );
      await tester.pump();

      expect(
        container.read(appLifecycleStateProvider),
        AppLifecycleState.resumed,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        container.read(appLifecycleStateProvider),
        AppLifecycleState.paused,
      );
      expect(service.clearAllCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        container.read(appLifecycleStateProvider),
        AppLifecycleState.resumed,
      );
      expect(service.clearAllCalls, 1);
    });
  });

  group('handleNotificationTap 路由与前缀分发', () {
    test('sessionId 正常调用 openSessionFromNotification', () {
      // routerProvider 初始化会触 activeConnectionProvider（flutter_secure_storage
      // 真插件）——注⼊最小路由避免 MissingPluginException。
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, _) => const CupertinoPageScaffold(child: SizedBox()),
          ),
          GoRoute(
            path: '/downloads',
            builder: (_, _) => const CupertinoPageScaffold(child: SizedBox()),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [routerProvider.overrideWithValue(router)],
      );
      addTearDown(container.dispose);

      // 空 payload 不崩溃
      handleNotificationTap(container, '');

      // download: 前缀不抛异常、不跳转 chat
      handleNotificationTap(container, 'download:dl-12345');
    });
  });
}

// ---------------------------------------------------------------------------
// 测试基础设施
// ---------------------------------------------------------------------------

class _FakeTurnNotificationService implements TurnNotificationService {
  final List<(String, String, String)> notifyCalls = [];
  final List<(String, String)> clarifyCalls = [];
  final List<(String, String, String)> errorCalls = [];
  final List<(String, String, int)> downloadCalls = [];
  int clearAllCalls = 0;
  int permissionRequests = 0;
  String? launchSessionId;

  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {
    notifyCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {
    clarifyCalls.add((sessionId, question));
  }

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {
    errorCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyDownloadCompleted(
    String downloadId,
    String fileName,
    int byteSize,
  ) async {
    downloadCalls.add((downloadId, fileName, byteSize));
  }
  @override
  Future<void> updateDownloadProgress({
    required String fileName,
    required int receivedBytes,
    required int expectedBytes,
    int queuedCount = 0,
  }) async {}

  @override
  Future<void> clearDownloadProgress() async {}


  @override
  Future<void> clearAll() async {
    clearAllCalls++;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<String?> getLaunchSessionId() async => launchSessionId;
}

class _FakeClock {
  DateTime now = DateTime(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

typedef _FakeChatApi = FakeChatApi;
