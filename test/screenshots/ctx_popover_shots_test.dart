import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_chat_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 上下文窗口弹层（ContextWindowPopover）**真界面**对比工装（非金照基线，不参与 CI）
//
// 用途：主人反馈「宽屏下上下文窗口指示器弹窗太大 —— 大字体 / 宽间距 / 大圆角，
// 和整个界面不兼容」，需要在**真界面衬托下**看改前 / 改后。
//
// 关键点：本弹层由 `_showContextPopover` 打开，而它在 `snapshot == null` 时直接
// return —— 所以宿主机必须是一个**真加载出会话**的聊天页（连接就绪 + fake API
// 喂真实读数），否则点了也弹不出来（`menus_shots_test.dart` 的 `_chatHome` 就是
// 这种空壳宿主，本工装因此不复用它的 home）。
//
// 读数刻意取主人真机截图里的那一组：1.0M / 已用 526.2K / 输入 66.5M /
// 输出 276.8K / 阈值 750.0K (75%) / $0.0000。
//
// 用法：
//   CTX_SHOTS=1 [CTX_SHOTS_TAG=before|after] C:/tmp/f.bat test \
//     test/screenshots/ctx_popover_shots_test.dart --update-goldens
//   不带 CTX_SHOTS=1 时全部 skip，`flutter test` 全量零影响。
//
// 产物：`.shots/ctx-popover/<tag>/ctx-<wide|narrow>-<light|dark>.png`
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip。
final bool _capture = Platform.environment['CTX_SHOTS'] == '1';

/// 产物子目录标签，默认 `now`。
final String _tag = Platform.environment['CTX_SHOTS_TAG'] ?? 'now';

const String _shotRoot = '../../.shots/ctx-popover';

/// 演示会话 id（路由参数 / 侧栏当前会话高亮共用）。
const String _sessionId = 's1';

ServerConnection _demoConnection() => ServerConnection(
  id: 'c1',
  name: 'Home 服务器',
  baseUrl: 'https://hermes.example.com:8787',
  createdAt: DateTime.utc(2026, 1, 1),
);

Future<ConnectionStore> _demoConnectionStore() async {
  final store = ConnectionStore(storage: InMemorySecureStorage());
  await store.save(_demoConnection());
  await store.setActive('c1');
  return store;
}

/// 直接给「活跃连接」喂一个**已就绪**的值（真实链路首帧是 null，聊天页会空壳）。
class _FixedActiveConnection extends ActiveConnectionController {
  @override
  ServerConnection? build() => _demoConnection();
}

/// 演示会话列表（取主人真机列表里的条目，便于逐项对照）。
List<SessionSummary> _demoSessions() {
  final fixed = DateTime(2026, 10, 7, 15, 0);
  double at(Duration ago) => fixed.subtract(ago).millisecondsSinceEpoch / 1000.0;
  return <SessionSummary>[
    SessionSummary(
      sessionId: _sessionId,
      title: '现在的宽屏界面下 上下文窗口指示器弹窗显得太大…',
      messageCount: 12,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(minutes: 1)),
    ),
    SessionSummary(
      sessionId: 's2',
      title: '软件底色灰蓝候选渲染方案（fork）',
      messageCount: 37,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(hours: 3)),
    ),
    SessionSummary(
      sessionId: 's3',
      title: '恢复宽屏界面设计会话进度',
      messageCount: 9,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(hours: 27)),
    ),
    SessionSummary(
      sessionId: 's4',
      title: '测试重复打开资源管理器问题排查',
      messageCount: 5,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(days: 3)),
    ),
  ];
}

/// 承载弹层的会话：读数与主人真机截图逐项一致。
Map<String, Object?> _sessionData() => <String, Object?>{
  'session': <String, Object?>{
    'session_id': _sessionId,
    'title': '现在的宽屏界面下 上下文窗口指示器弹窗显得太大…',
    'workspace': r'D:\projects\hermes-ui',
    'model': 'deepseek-v4.1-flash',
    'context_length': 1000000,
    'threshold_tokens': 750000,
    'last_prompt_tokens': 526200,
    'input_tokens': 66500000,
    'output_tokens': 276800,
    'estimated_cost': 0.0,
    'message_count': 4,
    'messages': <Object?>[
      <String, Object?>{
        'role': 'user',
        'content':
            '在现在的宽屏界面下 上下文窗口指示器弹窗显得太大了 这种大字体宽间距大圆角 '
            '一看就和整个界面不太兼容 你把他调的更小更紧凑出个在整个界面衬托下的视觉渲染给我看看',
        'message_id': 'u1',
      },
      <String, Object?>{
        'role': 'assistant',
        'content':
            '收到。现状是宽 300、头部大数字 21pt、行内距 4、下拉触发器上下内距 8、'
            '卡片圆角 14 —— 我先拍一张现状真图当基准，再收一档给你对比。',
        'message_id': 'a1',
      },
      <String, Object?>{
        'role': 'user',
        'content': '好，圆角和字号都要跟着整个界面走。',
        'message_id': 'u2',
      },
      <String, Object?>{
        'role': 'assistant',
        'content':
            '明白：字号回梯子（17 / 12.5 / 12），行高收一档，圆角对齐独立卡令牌，'
            '窄屏路径逐像素不动。',
        'message_id': 'a2',
      },
    ],
  },
};

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
    LocaleResolver.reset(mode: AppLocaleMode.zh);
  });

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Size physicalSize,
    required Brightness brightness,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final store = await _demoConnectionStore();
    final chatApi = FakeChatApi()..sessionResult = _sessionData();
    final router = GoRouter(
      initialLocation: '/chat/$_sessionId',
      routes: <RouteBase>[
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => const SessionListPage(),
            ),
            GoRoute(
              path: '/chat/:sessionId',
              builder: (context, state) =>
                  ChatPage(sessionId: state.pathParameters['sessionId'] ?? ''),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          connectionStoreProvider.overrideWithValue(store),
          activeConnectionProvider.overrideWith(_FixedActiveConnection.new),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'https://hermes.example.com:8787'),
          ),
          chatApiProvider.overrideWithValue(chatApi),
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => FakeSessionListApi(sessions: _demoSessions()),
          ),
          activeChatSessionIdProvider.overrideWith((ref) => _sessionId),
          workspaceRootsProvider.overrideWith(
            (ref) => Future.value(const <WorkspaceRoot>[
              WorkspaceRoot(path: r'D:\projects\hermes-ui', name: 'hermes-ui'),
              WorkspaceRoot(
                path: r'D:\projects\greenscreen-studio',
                name: 'greenscreen-studio',
              ),
            ]),
          ),
          availableModelIdsProvider.overrideWith(
            (ref) => Future.value(const <String>[
              'deepseek-v4.1-flash',
              'claude-opus-4.5',
              'gpt-5.6-sol',
            ]),
          ),
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
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
        ),
      ),
    );
    await _settle(tester, 8);

    // 打开上下文弹层（真实触发路径：点输入栏右侧的圆环指示器）。
    final indicator = find.byKey(
      const ValueKey('chat-context-indicator-button'),
    );
    expect(indicator, findsOneWidget, reason: '指示器入口没找到');
    await tester.tap(indicator);
    // 弹层入场（Cupertino 弹簧 ≈250ms）+ 浮层定位结算后再截。
    await _settle(tester, 10);

    Directory('$_shotRoot/$_tag').createSync(recursive: true);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('$_shotRoot/$_tag/$name.png'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  // 宽屏逻辑 1280×800 @2x（≥ kAdaptiveBreakpoint=900）；窄屏逻辑 800×1200。
  const Size widePhysical = Size(2560, 1600);
  const Size narrowPhysical = Size(1600, 2400);

  testWidgets('宽屏浅色 · 上下文弹层', (tester) async {
    await capture(
      tester,
      name: 'ctx-wide-light',
      physicalSize: widePhysical,
      brightness: Brightness.light,
    );
  }, skip: !_capture);

  testWidgets('宽屏暗色 · 上下文弹层', (tester) async {
    await capture(
      tester,
      name: 'ctx-wide-dark',
      physicalSize: widePhysical,
      brightness: Brightness.dark,
    );
  }, skip: !_capture);

  testWidgets('窄屏浅色 · 上下文弹层', (tester) async {
    await capture(
      tester,
      name: 'ctx-narrow-light',
      physicalSize: narrowPhysical,
      brightness: Brightness.light,
    );
  }, skip: !_capture);

  testWidgets('窄屏暗色 · 上下文弹层', (tester) async {
    await capture(
      tester,
      name: 'ctx-narrow-dark',
      physicalSize: narrowPhysical,
      brightness: Brightness.dark,
    );
  }, skip: !_capture);
}
