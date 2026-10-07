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
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/chat/widgets/user_attachment_block.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_chat_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 附件气泡 / 侧栏高亮 **设计稿对比工装**（非金照基线，不参与 CI 比对）
//
// 用法：
//   ATTACH_SHOTS=1 [ATTACH_DARK=1] C:/tmp/f.bat test
//     test/screenshots/attach_hl_shots_test.dart --update-goldens \
//     --dart-define=ATTACH_LAYOUT=<0..3> --dart-define=SIDEBAR_HL=<0..3>
//
// 产物：`.shots/attach-hl/attach-l<n>-hl<n>[-dark].png`（仓库根，.gitignore 覆盖）
//
// 为什么需要它：两处待改的观感（用户气泡里的图片附件、宽屏侧栏的当前会话高亮）
// 都必须让主人在**真界面**上对比，而不是看复刻稿。图片字节由
// `mediaFileProvider` 直接注入真实 PNG（`ATTACH_SHOTS_DIR` 下的三张截图），
// 所以宫格里的缩略图是真的、不是灰块。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip，日常 flutter test / CI 零影响。
final bool _capture = Platform.environment['ATTACH_SHOTS'] == '1';
const String _skipReason = '设置 ATTACH_SHOTS=1 才生成设计稿对比图';

/// ATTACH_DARK=1 时出暗色套件（文件名加 -dark 后缀）。
final bool _dark = Platform.environment['ATTACH_DARK'] == '1';

/// 图片来源目录（三张真实截图；默认 C:\tmp\attach-hl）。
final String _imageDir =
    Platform.environment['ATTACH_SHOTS_DIR'] ?? r'C:\tmp\attach-hl';

/// 演示会话 id（同时用于「当前会话」高亮与附件 URL）。
const String _sessionId = 's-demo-1';

/// 演示附件所在的（假的）服务端收件箱路径——与真实 Windows 形态一致，
/// 用于验证「Windows 绝对路径也能解析出 path」这条修复。
const String _attachDir =
    r'C:\Users\Admin\AppData\Local\hermes\webui_30002\attachments\s-demo-1';

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

/// 直接给「活跃连接」喂一个**已就绪**的值。
///
/// 真实链路里它由 [ActiveConnectionController] 异步加载，首帧是 null ⇒
/// 气泡拿不到 baseUrl、图片会先落到「本地文件不存在」占位（测试里就是一片
/// overflow 异常 + 空白瓦片）。工装要的是稳定终态，故这里跳过加载态。
class _FixedActiveConnection extends ActiveConnectionController {
  @override
  ServerConnection? build() => _demoConnection();
}

List<SessionSummary> _demoSessions() {
  final fixed = DateTime(2026, 9, 12, 12, 0);
  double at(Duration ago) =>
      fixed.subtract(ago).millisecondsSinceEpoch / 1000.0;
  return [
    SessionSummary(
      sessionId: _sessionId,
      title: '带有图片的聊天弹窗你重新设计一下 …',
      pinned: true,
      isStreaming: true,
      messageCount: 12,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(minutes: 2)),
    ),
    SessionSummary(
      sessionId: 's-demo-2',
      title: '上次修改的各个弹窗界面 工作区和模型…',
      isStreaming: true,
      messageCount: 8,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(minutes: 26)),
    ),
    SessionSummary(
      sessionId: 's-demo-3',
      title: 'full width Attached files',
      messageCount: 5,
      workspace: r'D:\data\etl',
      lastMessageAt: at(const Duration(minutes: 41)),
    ),
    SessionSummary(
      sessionId: 's-demo-4',
      title: 'Attached files Users Admin',
      messageCount: 3,
      workspace: r'D:\projects\book-hub',
      lastMessageAt: at(const Duration(hours: 12)),
    ),
    SessionSummary(
      sessionId: 's-demo-5',
      title: '内置服务首连成功率排查',
      messageCount: 21,
      workspace: r'D:\projects\hermes-ui',
      lastMessageAt: at(const Duration(hours: 30)),
    ),
  ];
}

/// 带图片附件的会话：两条用户消息（三条截图 / 两条截图 + 一个 pdf）。
///
/// 消息体与真实服务端一致：`content` 尾部带 `[Attached files: <Windows 绝对
/// 路径>]` 标记、**没有**独立的 attachments 数组（实测这就是 App 走
/// 「标记推断」路径的真实形态，也是 Windows 路径解析缺陷的触发条件）。
Map<String, Object?> _sessionWithAttachments() {
  String abs(String name) => '$_attachDir\\$name';
  return {
    'session': {
      'session_id': _sessionId,
      'title': '带有图片的聊天弹窗你重新设计一下 …',
      'workspace': r'D:\projects\hermes-ui',
      'model': 'deepseek-v4.1-flash',
      'context_length': 200000,
      'threshold_tokens': 160000,
      'last_prompt_tokens': 124000,
      'message_count': 5,
      'messages': [
        {
          'role': 'user',
          'content': '先看下这条不带附件的普通消息，作为对照。',
          'message_id': 'u0',
        },
        {
          'role': 'assistant',
          'content': '好，我逐条看。左上那处是弹层内边距，第二处是行高。',
          'message_id': 'a0',
        },
        {
          'role': 'user',
          'content':
              '这两张是宽屏下的现状，另外那个 pdf 是设计稿：\n\n'
              '[Attached files: ${abs('pasted_image.png')}, '
              '${abs('pasted_image-1.png')}, ${abs('设计稿.pdf')}]',
          'message_id': 'u1',
        },
        {
          'role': 'assistant',
          'content': '看到了，弹窗宽度和列排布都记下了。',
          'message_id': 'a1',
        },
        {
          'role': 'user',
          'content':
              '上次修改的各个弹窗界面 工作区和模型选择弹出菜单 显示不完全，'
              '三点弹窗菜单各项没有垂直居中 ，你再检查下上次修改的其他弹窗'
              '是否有视觉问题\n\n'
              '[Attached files: ${abs('pasted_image.png')}, '
              '${abs('pasted_image-1.png')}, ${abs('pasted_image-2.png')}]',
          'message_id': 'u2',
        },
        {
          'role': 'assistant',
          'content': '收到，我去核对这三张里的问题。',
          'message_id': 'a2',
        },
      ],
    },
  };
}

/// 图片目录下的真实 PNG（预热用）。
List<File> _imageFiles() {
  final files = Directory(_imageDir)
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) throw StateError('ATTACH_SHOTS_DIR 下没有 PNG：$_imageDir');
  return files;
}

/// 按 URL 里的 `path=` 尾段挑真实图片文件（三张截图的字节）。
File _imageFileForUrl(String url) {
  final dir = Directory(_imageDir);
  final files = dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('ATTACH_SHOTS_DIR 下没有 PNG：$_imageDir');
  }
  String decoded;
  try {
    decoded = Uri.decodeComponent(url);
  } on FormatException {
    decoded = url;
  }
  for (final file in files) {
    final base = file.uri.pathSegments.last;
    if (decoded.endsWith(base)) return file;
  }
  return files.first;
}

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async => const ProjectsResponse(
    projects: [
      ProjectSummary(projectId: 'p-demo-hermes', name: 'Hermes'),
      ProjectSummary(projectId: 'p-demo-reading', name: '读书'),
    ],
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

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Size physicalSize,
  }) async {
    LocaleResolver.reset(mode: AppLocaleMode.zh);
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // 图片缓存预热：flutter_test 的 fake async 不会推进 `Image.file` 的
    // 文件 IO + 解码，必须在 runAsync 里先 precache；之后界面里的瓦片命中
    // 缓存即可同步绘制出真实像素（否则只剩 loading 白块）。
    await tester.pumpWidget(const CupertinoApp(home: SizedBox.shrink()));
    final warmContext = tester.element(find.byType(SizedBox));
    await tester.runAsync(() async {
      for (final file in _imageFiles()) {
        await precacheImage(FileImage(file), warmContext);
      }
    });

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
        overrides: [
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
          // 「当前会话」高亮：直接喂路由写入的那个 state（真实链路由
          // desktop_lifecycle_observer 依 location 写入）。
          activeChatSessionIdProvider.overrideWith((ref) => _sessionId),
          // 图片字节：注入真实 PNG，宫格里的缩略图不是灰块。
          mediaFileProvider.overrideWith(
            (ref, url) async => _imageFileForUrl(url),
          ),
          workspaceRootsProvider.overrideWith(
            (ref) => Future.value(const [
              WorkspaceRoot(path: r'D:\projects\hermes-ui', name: 'hermes-ui'),
              WorkspaceRoot(path: r'D:\projects\book-hub', name: 'book-hub'),
            ]),
          ),
          availableModelIdsProvider.overrideWith(
            (ref) =>
                Future.value(const ['deepseek-v4.1-flash', 'gemini-3.8-flash']),
          ),
        ],
        child: CupertinoApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(
            _dark ? Brightness.dark : Brightness.light,
          ),
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
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile(
        '../../.shots/attach-hl/$name'
        '-l$kUserAttachmentLayout-hl$kSidebarCurrentHighlight'
        '${_dark ? '-dark' : ''}.png',
      ),
    );
  }

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);

  testWidgets('宽屏 · 聊天（图片附件 + 侧栏高亮）', (tester) async {
    await capture(tester, name: 'attach-hl', physicalSize: const Size(2560, 1600));
  }, skip: !_capture);

  testWidgets('宽屏 · 聊天（窄窗 1100）', (tester) async {
    await capture(tester, name: 'attach-hl-narrow', physicalSize: const Size(2200, 1600));
  }, skip: !_capture);
}
