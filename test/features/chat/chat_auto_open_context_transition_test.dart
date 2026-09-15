import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/app/widgets/hermes_page_route.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_input_bar.dart';
import 'package:hermes_ui/features/chat/widgets/context_window_popover.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// #115 回归守卫：新建会话自动打开上下文弹窗必须等本页入场转场（300ms 滑动）
/// 播完再弹。
///
/// 根因：弹层定位（`showAdaptivePopover`）在调用瞬间一次性快照锚点 RenderBox
/// 坐标，弹层挂在根 Overlay 且不随页面平移——抢在转场中途弹出，弹窗会永久冻结
/// 在「半程」指示器坐标上（指示器位于输入栏左簇，位移不会被右缘 clamp 吸收）。

/// 全端点回 `{}` 200：上下文弹层内部会异步拉取模型/工作区列表。
class _CatchAllAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _mockApiClient() {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = _CatchAllAdapter();
  return ApiClient(baseUrl: 'http://test.local:30002', dio: dio);
}

/// 自动打开开关：置为开启且不触发 shared_preferences 异步加载（避免测试竞态）。
class _AutoOpenEnabled extends AutoOpenContextOnNewSessionController {
  @override
  bool build() => true;
}

/// 最近新建会话：恒为 's1'，使 ChatInputBar 挂载即进入「待自动打开」态。
class _RecentlyCreated extends RecentlyCreatedSessionIdController {
  @override
  String? build() => 's1';
}

ProviderContainer _buildContainer() {
  final api = FakeChatApi();
  api.sessionResult = {
    'session': {'session_id': 's1', 'messages': const []},
  };
  // 注意：不定 addTearDown 释放 —— 容器生命周期由测试体末尾显式 dispose
  // （ChatController 的 watchdog periodic timer 需随容器销毁取消，
  // 否则 flutter_test 的 timersPending 断言失败）。
  return ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      apiClientProvider.overrideWithValue(_mockApiClient()),
      autoOpenContextOnNewSessionProvider.overrideWith(_AutoOpenEnabled.new),
      recentlyCreatedSessionIdProvider.overrideWith(_RecentlyCreated.new),
    ],
  );
}

/// 卸载组件树（取消 PerfMonitorPanel 等 widget 级周期定时器）并销毁容器。
Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SizedBox()),
  );
  await tester.pump();
  container.dispose();
}

/// 宽屏形态的输入栏：左侧留出侧栏宽度，避免弹层右对齐被屏幕左缘 clamp 吸收
/// （真实宽屏双栏下指示器 x ≈ 侧栏 320 + 左簇内边距）。
Widget _wideChatInputBar() => const Padding(
  padding: EdgeInsets.only(left: 400),
  child: ChatInputBar(sessionId: 's1'),
);

/// 指示器按钮 key（手动点击路径复用）。
const ValueKey<String> _indicatorKey = ValueKey(
  'chat-context-indicator-button',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(AdaptivePopover.debugReset);

  void useWideViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('自动打开上下文弹窗等入场转场播完才弹，且右缘对齐静止态指示器', (tester) async {
    useWideViewport(tester);
    final container = _buildContainer();

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          navigatorKey: navKey,
          home: const CupertinoPageScaffold(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 走真实转场：HermesPageRoute（300ms 滑动）推入聊天输入栏所在页。
    unawaited(
      navKey.currentState!.push<void>(
        HermesPageRoute<void>(
          builder: (_) => CupertinoPageScaffold(child: _wideChatInputBar()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // 转场半程（150/300ms）：弹层不得出现（修复前此处会立刻弹出并错位）。
    expect(AdaptivePopover.activeOverlayCount, 0, reason: '入场转场半程不得弹出上下文弹窗');
    expect(find.byType(ContextWindowPopover), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(ContextWindowPopover), findsOneWidget);

    // 位置等价断言：自动打开（等转场播完）的弹层位置，必须与「手动点击指示器」
    // 在完全静止后的位置一致——修复前自动打开会落在转场半程坐标上（相差整段位移）。
    final autoRect = tester.getRect(find.byType(ContextWindowPopover));
    expect(AdaptivePopover.closeTopOverlay(), isTrue);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_indicatorKey));
    await tester.pumpAndSettle();
    expect(find.byType(ContextWindowPopover), findsOneWidget);
    final manualRect = tester.getRect(find.byType(ContextWindowPopover));
    expect(
      (autoRect.left - manualRect.left).abs(),
      lessThan(1.0),
      reason: '自动打开弹层 left 应与静止后手动打开一致',
    );
    expect(
      (autoRect.right - manualRect.right).abs(),
      lessThan(1.0),
      reason: '自动打开弹层 right 应与静止后手动打开一致',
    );

    await _teardown(tester, container);
  });

  testWidgets('路由动画已完成（首屏 didAdd）时自动打开即刻弹出，不被等待逻辑拖延', (tester) async {
    useWideViewport(tester);
    final container = _buildContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          home: CupertinoPageScaffold(child: _wideChatInputBar()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 30));

    // 60ms 内即应弹出：远早于 600ms 兜底超时，证明「动画已完成 → 立即返回」分支生效。
    expect(AdaptivePopover.activeOverlayCount, 1);
    expect(find.byType(ContextWindowPopover), findsOneWidget);

    await _teardown(tester, container);
  });
}
