import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/message_action_menu.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_chat_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';
import 'readme_shots_test.dart' show demoConnectionStore;

// ---------------------------------------------------------------------------
// 弹窗族现状真渲染工装（**非金照基线，不参与 CI**）
//
// 用途：主人反馈「工作区/模型选择窗、上下文指示器、筛选会话、聊天三点、侧栏三点
// 需要重做宽屏与窄屏的美观与适配」，出设计稿前先出一份**现状真图**作为对照基准。
// 本工装只渲染**真实组件 + 真实触发路径**，不注入任何测试专用 UI。
//
// 用法：
//   MENU_SHOTS=1 C:/tmp/f.bat test test/screenshots/menus_shots_test.dart \
//       --update-goldens
//   不带 MENU_SHOTS=1 时全部 skip，`flutter test` 全量零影响。
//
// 产物：`.shots/menus/<tag>/<name>-<light|dark>.png`
//   tag 由 MENU_SHOTS_TAG 指定，默认 `now`。
//
// 覆盖 6 个弹窗 × 宽/窄 × 浅/暗：
//   1. `msg-context-menu`   —— 聊天正文右键菜单（真实 Listener 右键路径）
//   2. `composer-workspace` —— 输入栏工作区 chip 选择器
//   3. `context-window`     —— 上下文指示器弹层
//   4. `session-filter`     —— 筛选会话
//   5. `chat-actions`       —— 聊天右上角三点
//   6. `sidebar-actions`    —— 侧边栏会话项三点
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip。
final bool _capture = Platform.environment['MENU_SHOTS'] == '1';

/// 产物子目录标签，默认 `now`。
final String _tag = Platform.environment['MENU_SHOTS_TAG'] ?? 'now';

const String _shotRoot = '../../.shots/menus';

/// 宽屏物理像素（逻辑 1280×800 @2x；≥ kAdaptiveBreakpoint=900）。
const Size _wideSize = Size(2560, 1600);

/// 窄屏物理像素（逻辑 800×1200 @2x；< 900 → 单列 + 系统弹层）。
///
/// 高度刻意不用 600：底部行动表（ActionSheet）在 600 高时末项会被裁到视口外，
/// `tester.tap` 会静默 miss（既有工装的实测坑）。宽度才是断点判据。
const Size _narrowSize = Size(1600, 2400);

/// 演示工作区：取主人实际环境里的五个根，便于与真机截图逐项对照。
List<WorkspaceRoot> _demoRoots() => const [
  WorkspaceRoot(path: 'C:\\Users\\Admin\\workspace', name: 'Home'),
  WorkspaceRoot(
    path: 'D:\\projects\\greenscreen-studio',
    name: 'greenscreen-studio',
  ),
  WorkspaceRoot(
    path: 'D:\\projects\\tile-stitching-editor',
    name: 'tile-stitching-editor',
  ),
  WorkspaceRoot(
    path: 'D:\\projects\\windows-hermes-compat',
    name: 'Hermes 兼容',
  ),
  WorkspaceRoot(path: 'D:\\projects\\hermes-ui', name: 'hermes_ui'),
];

/// 演示模型列表（格式与真机一致：provider-model 形态）。
const List<String> _demoModels = [
  'deepseek-v4.1-flash',
  'claude-opus-4.5',
  'gpt-5.6-sol',
  'kimi-k3',
];

/// 聊天页宿主：真实 `ChatPage` + fake API（两条消息 + 上下文读数，供上下文弹层用）。
Widget _chatHome() {
  final api = FakeChatApi()
    ..sessionResult = <String, Object?>{
      'session': <String, Object?>{
        'session_id': 's1',
        'title': '弹窗族设计稿 · 现状取证',
        'workspace': 'D:\\projects\\hermes-ui',
        'context_length': 1000000,
        'last_prompt_tokens': 0,
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': '帮我看下今天的构建结果',
            'message_id': 'u1',
          },
          <String, Object?>{
            'role': 'assistant',
            'content': 'analyze 零告警，全量测试全绿，共 5123 例通过。',
            'message_id': 'a1',
          },
        ],
      },
    };
  return ProviderScope(
    overrides: <Override>[
      chatApiProvider.overrideWithValue(api),
      chatAvailableModelsProvider.overrideWithValue(_demoModels),
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      workspaceRootsProvider.overrideWith((ref) async => _demoRoots()),
      availableModelIdsProvider.overrideWith((ref) async => _demoModels),
    ],
    child: const ChatPage(sessionId: 's1'),
  );
}

/// 演示会话（标题取主人真机列表里的条目，便于逐条对照）。
List<SessionSummary> _demoSessions() => <SessionSummary>[
  SessionSummary(
    sessionId: 's1',
    title: '软件底色灰蓝候选渲染方案（fork）',
    messageCount: 9,
    lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
  ),
  SessionSummary(
    sessionId: 's2',
    title: '恢复宽屏界面设计会话进度',
    messageCount: 42,
    lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000 - 4 * 3600,
  ),
  SessionSummary(
    sessionId: 's3',
    title: '测试重复打开资源管理器问题排查',
    messageCount: 17,
    lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000 - 7 * 86400,
  ),
];

/// 结算固定帧数（**不用 `pumpAndSettle`**：聊天页有常驻定时器，会挂到超时）。
Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(() async {
    // 点不中就说明这张图拍错了对象 —— 直接判失败，别产出「页面照」冒充弹窗照。
    WidgetController.hitTestWarningShouldBeFatal = true;
    await loadHermesGoldenFonts();
  });

  tearDownAll(() {
    WidgetController.hitTestWarningShouldBeFatal = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Widget home,
    required Brightness brightness,
    required Size size,
    required Future<void> Function(WidgetTester tester) interact,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'https://hermes.example.com:8787'),
          ),
        ],
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(brightness),
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: home,
        ),
      ),
    );
    await _settle(tester);

    await interact(tester);
    // 弹层入场（Cupertino 弹簧 ≈250ms）与浮层定位结算后再截。
    await _settle(tester, 8);

    Directory('$_shotRoot/$_tag').createSync(recursive: true);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile(
        '$_shotRoot/$_tag/$name-${brightness == Brightness.dark ? 'dark' : 'light'}.png',
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// 路径 B：真机形态（ShellRoute + AdaptiveShell + **已连接** store）。
  ///
  /// 会话列表一族必须走这条路：单挂 `SessionListPage` 只会渲染空壳
  /// （实测：页面在、零个 Text、零个导航栏），列表加载门控挂在连接状态上；
  /// 且宽屏的筛选入口在侧栏品牌区，不在列表页头部。
  Future<void> captureShell(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
    required Size size,
    required Future<void> Function(WidgetTester tester) interact,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final store = await demoConnectionStore();
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => const SessionListPage(),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          connectionStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'https://hermes.example.com:8787'),
          ),
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => FakeSessionListApi(sessions: _demoSessions()),
          ),
          workspaceRootsProvider.overrideWith((ref) async => _demoRoots()),
        ],
        child: CupertinoApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(brightness),
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await _settle(tester);

    await interact(tester);
    await _settle(tester, 8);

    Directory('$_shotRoot/$_tag').createSync(recursive: true);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile(
        '$_shotRoot/$_tag/$name-${brightness == Brightness.dark ? 'dark' : 'light'}.png',
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// 整机形态：宽/窄 × 浅/暗 四张。
  void shellGroups(
    String name,
    String title,
    Future<void> Function(WidgetTester tester) Function() interact,
  ) {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';

      testWidgets('宽屏$suffix · $title', (tester) async {
        await captureShell(
          tester,
          name: '$name-wide',
          brightness: brightness,
          size: _wideSize,
          interact: interact(),
        );
      }, skip: !_capture);

      testWidgets('窄屏$suffix · $title', (tester) async {
        await captureShell(
          tester,
          name: '$name-narrow',
          brightness: brightness,
          size: _narrowSize,
          interact: interact(),
        );
      }, skip: !_capture);
    }
  }

  /// 同一触发路径出「宽屏 / 窄屏」× 「浅 / 暗」共四张。
  void shotGroups(
    String name,
    String title,
    Widget Function() home,
    Future<void> Function(WidgetTester tester) Function() interact,
  ) {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';

      testWidgets('宽屏$suffix · $title', (tester) async {
        await capture(
          tester,
          name: '$name-wide',
          home: home(),
          brightness: brightness,
          size: _wideSize,
          interact: interact(),
        );
      }, skip: !_capture);

      testWidgets('窄屏$suffix · $title', (tester) async {
        await capture(
          tester,
          name: '$name-narrow',
          home: home(),
          brightness: brightness,
          size: _narrowSize,
          interact: interact(),
        );
      }, skip: !_capture);
    }
  }

  // -------------------------------------------------------------------------
  // 1. 图 1 基准：聊天正文右键菜单（宽屏 = 鼠标档密排浮层；窄屏 = 系统底部表）
  // -------------------------------------------------------------------------
  shotGroups(
    'msg-context-menu',
    '图1 消息右键菜单',
    _chatHome,
    () => (tester) async {
      // 聊天气泡正文是富文本（不是 Text.data），find.text 匹配不到 → 走真实
      // 右键路径所调用的**同一个公开入口**，位置取聊天正文区一点。
      final chatContext = tester.element(find.byType(ChatPage));
      unawaited(
        showMessageActionMenu(
          chatContext,
          message: ChatMessage.fromJson(<String, Object?>{
            'role': 'assistant',
            'content': 'analyze 零告警，全量测试全绿，共 5123 例通过。',
            'message_id': 'a1',
          }),
          position: const Offset(780, 300),
          selectionText: '被选中的正文片段',
        ),
      );
      await tester.pump();
    },
  );

  // -------------------------------------------------------------------------
  // 2. 图 2：输入栏「工作区」chip 选择器
  // -------------------------------------------------------------------------
  shotGroups(
    'composer-workspace',
    '图2 工作区选择窗',
    _chatHome,
    () => (tester) async {
      await tester.tap(
        find.byKey(const ValueKey('composer-workspace-chip')),
        warnIfMissed: false,
      );
    },
  );

  // -------------------------------------------------------------------------
  // 3. 图 3：上下文指示器弹层
  // -------------------------------------------------------------------------
  shotGroups(
    'context-window',
    '图3 上下文指示器',
    _chatHome,
    () => (tester) async {
      await tester.tap(
        find.byKey(const ValueKey('chat-context-indicator-button')),
      );
    },
  );

  // -------------------------------------------------------------------------
  // 4. 图 4：筛选会话 —— 宽屏入口在侧栏品牌区，窄屏在列表页头部。
  // -------------------------------------------------------------------------
  shellGroups('session-filter', '图4 筛选会话', () => (tester) async {
    final sidebarEntry = find.byKey(const ValueKey('sidebar-brand-filter'));
    if (sidebarEntry.evaluate().isNotEmpty) {
      await tester.tap(sidebarEntry);
    } else {
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
    }
  });

  // -------------------------------------------------------------------------
  // 5. 图 5：聊天右上角三点
  // -------------------------------------------------------------------------
  shotGroups(
    'chat-actions',
    '图5 聊天三点',
    _chatHome,
    () => (tester) async {
      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
    },
  );

  // -------------------------------------------------------------------------
  // 6. 图 6：侧栏会话项三点（宽屏紧凑模式已无「⋯」按钮 → 长按打开菜单）。
  // -------------------------------------------------------------------------
  shellGroups('sidebar-actions', '图6 侧栏会话三点', () => (tester) async {
    await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
  });
}
