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
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_chat_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 用户图片附件气泡 · **真渲染取证工装**（非金照基线，不参与 CI 比对）
//
// 用法：
//   BUBBLE_SHOTS=1 [BUBBLE_SHOT_TAG=cur] C:/tmp/f.bat test
//     test/screenshots/attach_bubble_shots_test.dart --update-goldens
//
// 产物：`.shots/attach-bubble/<场景>-<tag>.png`（仓库根，.gitignore 覆盖）
//
// 覆盖的三件事（主人 2026-10-07 报告）：
//   ① 非正方形图片被塞进正方形容器（cover 裁切成方）—— 现状真图 + 候选档对比；
//   ② 返回再点开同消息后图片消失（闸门放行态没跨导航保留）；
//   ③ 关闭自动加载时，加载按钮与提醒不在 placeholder 正中间。
//
// 图片字节由 `mediaFileProvider` 直接注入 `BUBBLE_SHOTS_DIR` 下的真实 PNG，
// 所以瓦片里是真的像素、不是灰块。
// ---------------------------------------------------------------------------

final bool _capture = Platform.environment['BUBBLE_SHOTS'] == '1';
const String _skipReason = '设置 BUBBLE_SHOTS=1 才生成真渲染取证图';

/// 档位标签（同一工装跑多档候选时只改文件名，不改代码）。
final String _tag = Platform.environment['BUBBLE_SHOT_TAG'] ?? 'cur';

/// 非方图目录（默认 C:\tmp\attach-bubble：竖 3:4 / 横 4:3 / 超宽 16:9）。
final String _imageDir =
    Platform.environment['BUBBLE_SHOTS_DIR'] ?? r'C:\tmp\attach-bubble';

const String _sessionId = 's-demo-1';

/// 演示附件目录（真实 Windows 绝对路径形态 —— 附件区走 /api/media）。
const String _attachDir =
    r'C:\Users\Admin\AppData\Local\hermes\webui_30002\attachments\s-demo-1';

const String kPortrait = 'ns-portrait-3x4.png';
const String kLandscape = 'ns-landscape-4x3.png';
const String kUltrawide = 'ns-ultrawide-16x9.png';

/// 关闭自动加载图片（主人报告 ②③ 时的设置态）。
class _GateOff extends AutoLoadImagesController {
  @override
  bool build() => false;
}

class _FixedActiveConnection extends ActiveConnectionController {
  @override
  ServerConnection? build() => _demoConnection();
}

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

List<SessionSummary> _demoSessions() {
  final fixed = DateTime(2026, 9, 12, 12, 0);
  double at(Duration ago) =>
      fixed.subtract(ago).millisecondsSinceEpoch / 1000.0;
  return [
    SessionSummary(
      sessionId: _sessionId,
      title: '非正方形图片在气泡里的排布 …',
      pinned: true,
      messageCount: 12,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(minutes: 2)),
    ),
    SessionSummary(
      sessionId: 's-demo-2',
      title: '上次修改的各个弹窗界面 工作区和模型…',
      messageCount: 8,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(minutes: 26)),
    ),
  ];
}

/// 三条用户消息 + 两条对照：① 三张非方图混排；② 单张竖图；③ 两张 + pdf。
Map<String, Object?> _sessionWithAttachments() {
  String abs(String name) => '$_attachDir\\$name';
  return {
    'session': {
      'session_id': _sessionId,
      'title': '非正方形图片在气泡里的排布 …',
      'workspace': r'D:\projects\hermes-ui',
      'model': 'deepseek-v4.1-flash',
      'context_length': 200000,
      'threshold_tokens': 160000,
      'last_prompt_tokens': 124000,
      'message_count': 5,
      'messages': [
        {
          'role': 'user',
          'content':
              '三张图比例都不一样，现在是这个效果：\n\n'
              '[Attached files: ${abs(kPortrait)}, ${abs(kLandscape)}, '
              '${abs(kUltrawide)}]',
          'message_id': 'u0',
        },
        {'role': 'assistant', 'content': '收到，我看下排布。', 'message_id': 'a0'},
        {
          'role': 'user',
          'content':
              '单独一张竖图是这样：\n\n'
              '[Attached files: ${abs(kPortrait)}]',
          'message_id': 'u1',
        },
        {
          'role': 'user',
          'content':
              '再混一个 pdf：\n\n'
              '[Attached files: ${abs(kUltrawide)}, ${abs(kPortrait)}, '
              '${abs('设计稿.pdf')}]',
          'message_id': 'u2',
        },
      ],
    },
  };
}

/// 单条消息（近景工装用）。
ChatMessage _message({
  required String id,
  required List<String> refs,
  String text = '看这几张图：',
}) {
  final abs = refs.map((e) => '$_attachDir\\$e').join(', ');
  return ChatMessage.fromJson({
    'role': 'user',
    'content': '$text\n\n[Attached files: $abs]',
    'message_id': id,
  });
}

List<File> _imageFiles() {
  final files =
      Directory(_imageDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) throw StateError('BUBBLE_SHOTS_DIR 下没有 PNG：$_imageDir');
  return files;
}

/// 按 URL 的 `path` 查询参数挑真实图片字节。
///
/// ⚠️ 不能拿整条 URL 做 `endsWith(<文件名>)`：`/api/media?path=…&session_id=…`
/// 的 path 后面还挂着 session_id ⇒ 永远匹配不上、静默落到 `files.first`，
/// 于是「三张不同图」会被渲染成同一张（本工装第一版就这么错过）。
File _imageFileForUrl(String url) {
  final files = _imageFiles();
  var probe = url;
  try {
    final uri = Uri.parse(url);
    probe = uri.queryParameters['path'] ?? url;
  } catch (_) {
    // 非法 URL：退回原串比对
  }
  for (final file in files) {
    final base = file.uri.pathSegments.last;
    if (probe.endsWith(base) || url.endsWith(base)) return file;
  }
  return files.first;
}

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async => const ProjectsResponse(
    projects: [ProjectSummary(projectId: 'p-demo-hermes', name: 'Hermes')],
  );

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

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 图片缓存预热：flutter_test 的 fake async 不推进 `Image.file` 的文件 IO +
  /// 解码，必须在 runAsync 里先 precache，否则瓦片永远停在 loading 白块。
  Future<void> precacheAll(WidgetTester tester) async {
    await tester.pumpWidget(const CupertinoApp(home: SizedBox.shrink()));
    final warm = tester.element(find.byType(SizedBox));
    await tester.runAsync(() async {
      for (final file in _imageFiles()) {
        await precacheImage(FileImage(file), warm);
      }
    });
  }

  Future<void> shoot(WidgetTester tester, String name) => expectLater(
    find.byType(CupertinoApp),
    matchesGoldenFile('../../.shots/attach-bubble/$name-$_tag.png'),
  );

  List<Override> overrides({
    required ConnectionStore store,
    required FakeChatApi chatApi,
    bool gateOff = false,
  }) => [
    connectionStoreProvider.overrideWithValue(store),
    activeConnectionProvider.overrideWith(_FixedActiveConnection.new),
    apiClientProvider.overrideWithValue(
      ApiClient(baseUrl: 'https://hermes.example.com:8787'),
    ),
    chatApiProvider.overrideWithValue(chatApi),
    sessionListApiFactoryProvider.overrideWithValue(
      (_) => FakeSessionListApi(sessions: _demoSessions()),
    ),
    projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
    activeChatSessionIdProvider.overrideWith((ref) => _sessionId),
    mediaFileProvider.overrideWith((ref, url) async => _imageFileForUrl(url)),
    workspaceRootsProvider.overrideWith(
      (ref) => Future.value(const [
        WorkspaceRoot(path: r'D:\projects\hermes-ui', name: 'hermes-ui'),
      ]),
    ),
    availableModelIdsProvider.overrideWith(
      (ref) => Future.value(const ['deepseek-v4.1-flash']),
    ),
    if (gateOff) autoLoadImagesProvider.overrideWith(_GateOff.new),
  ];

  /// 真界面（壳 + 聊天页）整屏定格。
  Future<void> captureApp(
    WidgetTester tester, {
    required String name,
    required Size physicalSize,
    bool gateOff = false,
    bool dark = false,
  }) async {
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await precacheAll(tester);

    final store = await _demoConnectionStore();
    final chatApi = FakeChatApi()..sessionResult = _sessionWithAttachments();
    final router = GoRouter(
      initialLocation: '/chat/$_sessionId',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: [
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
        overrides: overrides(store: store, chatApi: chatApi, gateOff: gateOff),
        child: CupertinoApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(dark ? Brightness.dark : Brightness.light),
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
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    await shoot(tester, name);
  }

  /// 近景（单条消息气泡）：dpr 3 ⇒ 96pt 瓦片在图上 ≈ 288px，看裁切/居中都够。
  Future<void> captureMessage(
    WidgetTester tester, {
    required String name,
    required List<ChatMessage> messages,
    double surfaceWidth = 520,
    bool gateOff = false,
  }) async {
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    tester.view.physicalSize = Size(surfaceWidth * 3, 620 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await precacheAll(tester);
    final store = await _demoConnectionStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(
          store: store,
          chatApi: FakeChatApi(),
          gateOff: gateOff,
        ),
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(Brightness.light),
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: CupertinoPageScaffold(
            backgroundColor: const Color(0xFFF2F2F7),
            child: Center(
              child: SizedBox(
                width: surfaceWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in messages)
                      ChatMessageBubble(
                        message: m,
                        baseUrl: _demoConnection().baseUrl,
                        sessionId: _sessionId,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    await shoot(tester, name);
  }

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);

  // ------------------------------------------------------------------ 整屏 --
  testWidgets('宽屏 · 聊天（非方图三连 + 单图 + 混 pdf）', (tester) async {
    await captureApp(
      tester,
      name: 'wide',
      physicalSize: const Size(2560, 1600),
    );
  }, skip: !_capture);

  testWidgets('手机 400 · 聊天（非方图三连）', (tester) async {
    await captureApp(
      tester,
      name: 'phone',
      physicalSize: const Size(800, 1600),
    );
  }, skip: !_capture);

  testWidgets('宽屏 · 关闭自动加载（闸门占位）', (tester) async {
    await captureApp(
      tester,
      name: 'wide-gate',
      physicalSize: const Size(2560, 1600),
      gateOff: true,
    );
  }, skip: !_capture);

  // ------------------------------------------------------------------ 近景 --
  testWidgets('近景 · 三张非方图（cover 裁切成方）', (tester) async {
    await captureMessage(
      tester,
      name: 'closeup-grid',
      messages: [
        _message(id: 'u0', refs: [kPortrait, kLandscape, kUltrawide]),
      ],
    );
  }, skip: !_capture);

  testWidgets('近景 · 单张竖图（contain）', (tester) async {
    await captureMessage(
      tester,
      name: 'closeup-single',
      messages: [
        _message(id: 'u1', refs: [kPortrait]),
      ],
    );
  }, skip: !_capture);

  testWidgets('近景 · 关闭自动加载：单图 placeholder + 三张瓦片', (tester) async {
    await captureMessage(
      tester,
      name: 'closeup-gate',
      gateOff: true,
      messages: [
        _message(id: 'u0', refs: [kPortrait, kLandscape, kUltrawide]),
        _message(id: 'u1', refs: [kLandscape]),
      ],
    );
  }, skip: !_capture);

  testWidgets('近景 · 关闭自动加载：逐张点开加载 → 返回 → 再点开同消息', (tester) async {
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    const surfaceWidth = 520.0;
    tester.view.physicalSize = const Size(surfaceWidth * 3, 620 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await precacheAll(tester);
    final store = await _demoConnectionStore();
    // 会话里**只留这一条**消息（三张非方图）：返回再进后整条消息都在画面里，
    // 「点过的图是否还在」一眼可判，不用滚动找。
    final onlyOne = {
      'session': {
        'session_id': _sessionId,
        'title': '返回再点开同消息 …',
        'workspace': r'D:\projects\hermes-ui',
        'model': 'deepseek-v4.1-flash',
        'message_count': 1,
        'messages': [
          {
            'role': 'user',
            'content':
                '这三张我都点开看过了：\n\n'
                '[Attached files: $_attachDir\\$kPortrait, '
                '$_attachDir\\$kLandscape, $_attachDir\\$kUltrawide]',
            'message_id': 'u0',
          },
        ],
      },
    };
    final router = GoRouter(
      initialLocation: '/chat/$_sessionId',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const SizedBox.shrink(),
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
        overrides: overrides(
          store: store,
          chatApi: FakeChatApi()..sessionResult = onlyOne,
          gateOff: true,
        ),
        child: CupertinoApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(Brightness.light),
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
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // 1) 逐张点「点击加载」（三张瓦片全部点过）。
    const gateKey = ValueKey('chat-inline-media-tap-to-load');
    var tapped = 0;
    while (tapped < 5 && find.byKey(gateKey).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(gateKey).first, warnIfMissed: false);
      tapped++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (tapped == 0) {
      throw StateError('闸门占位没出现：autoLoad 关闭态没生效');
    }
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(milliseconds: 400));

    // 2) 返回会话列表，再点开同一会话（同一条消息）。
    router.go('/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    router.go('/chat/$_sessionId');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    await shoot(tester, 'closeup-reenter');
  }, skip: !_capture);
}
