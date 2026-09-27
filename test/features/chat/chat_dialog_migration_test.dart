import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/hermes_dialog.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/providers/clipboard_paste_provider.dart';
import 'package:hermes_ui/core/providers/file_picker_provider.dart';
import 'package:hermes_ui/core/utils/clipboard_paste.dart';
import 'package:hermes_ui/core/utils/file_picker.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/selection_provider.dart';
import 'package:hermes_ui/features/chat/widgets/message_action_menu.dart';
import 'package:hermes_ui/features/chat/widgets/selection_chips.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_prompts_api.dart';
import '../../helpers/fake_session_list_api.dart';

// ---------------------------------------------------------------------------
// 批 5 · C2 守卫：session / chat 系弹窗调用点迁移到 `showHermesDialog` 四档宽（D1）。
//
// 三条契约，逐条钉死：
//
// 1. **迁移完备** —— 四个文件里 `showCupertinoDialog` 零残留（源级扫描；防「改一半」，
//    也防后续新弹窗又走回老路）；
// 2. **分档即契约** —— 每处 `kind` 与迁移表逐值对齐，且宽度用**绝对值**
//    （380 / 460 / 560 / 760）断言，不拿 `kind.width` 自证 —— 枚举被改坏时
//    这层守卫照样能发现；
// 3. **一份内容、两种形态** —— 宽屏（≥900）真渲染 `HermesDialogCard` 且宽 = 档位；
//    窄屏（<900）仍是**原系统 `CupertinoAlertDialog`**，路由仍是
//    `CupertinoDialogRoute` 而**不是** `HermesDialogRoute`（「窄屏逐像素不变」
//    的可判结构判据）。
//
// 所有断言都打在**真实调用点**上（真页面 / 真面板 / 真菜单），不是另写一份
// `showHermesDialog` 调用 —— 否则守卫测的是基础设施，而不是「调用点迁没迁对」。
// ---------------------------------------------------------------------------

/// 宽屏（≥900）视口。
const Size _kWide = Size(1280, 800);

/// 窄屏（<900）视口 —— 就是 flutter_test 默认 800×600。
const Size _kNarrow = Size(800, 600);

/// 四档宽度的**绝对**期望值（不写 `kind.width`，见文件头注释第 2 条）。
///
/// 注：本批 12 处迁移**没有**用到 `picker`（460）—— 这四个文件里「从一组选项里选一个」
/// 的形态全是底部操作表 / 悬浮面板（`CupertinoActionSheet` / `showCupertinoPopover`，
/// 见文件末尾「未迁移」清单），不是 alert 系弹窗，故 460 档本批无消费者。
/// 该档不在本文件断言，避免留下未被引用的常量。
const double _kConfirmWidth = 380.0;
const double _kFormWidth = 560.0;
const double _kWideFormWidth = 760.0;

/// 迁移表的机器可读部分：四个文件 → 文件内**按出现顺序**的档位。
///
/// 顺序敏感是有意的：改档「改在哪一处」是这类回归里最容易被糊过去的细节
/// （把「导出失败」错改宽档会被本表当场抓住）。
const Map<String, List<HermesDialogKind>> _kMigrationTable =
    <String, List<HermesDialogKind>>{
      'lib/features/session_list/session_list_page.dart': <HermesDialogKind>[
        HermesDialogKind.wideForm, // 导出成功（长文本预览）
        HermesDialogKind.confirm, // 导出内容超限已落盘
        HermesDialogKind.confirm, // 导出失败
        HermesDialogKind.confirm, // 删除会话（破坏性）
        HermesDialogKind.confirm, // 批量归档
        HermesDialogKind.confirm, // 批量删除（破坏性）
        HermesDialogKind.confirm, // 操作失败
      ],
      'lib/features/chat/widgets/chat_input_bar.dart': <HermesDialogKind>[
        HermesDialogKind.confirm, // 输入栏错误提示
        HermesDialogKind.confirm, // 停止生成二次确认（破坏性）
      ],
      'lib/features/chat/widgets/selection_chips.dart': <HermesDialogKind>[
        HermesDialogKind.form, // 选区重命名（含 CupertinoTextField）
      ],
      'lib/features/chat/widgets/message_action_menu.dart': <HermesDialogKind>[
        HermesDialogKind.confirm, // 截断确认（窄屏 sheet 路径）
        HermesDialogKind.confirm, // 截断确认（宽屏悬浮面板路径）
      ],
    };

/// 本批**明确不迁移**的非 alert 系弹层（逐处 + 计数契约）。
///
/// 它们不是 `CupertinoAlertDialog`，形态与语义都不属于 D1 的「四档宽弹窗」：
/// 自绘底部面板 / 系统底部操作表 / 锚定悬浮面板各有自己的宽度与定位规则
/// （`showCupertinoModalPopup` 的自绘 sheet、`CupertinoActionSheet`、
/// `showCupertinoPopover`），强行塞进 alert 三槽位（title/content/actions）会改掉
/// 形态与命中路径。**这段是刻意保留的清单**，不是漏改：
///
/// | 文件 | 未迁移处 | 形态 | 为什么不迁 |
/// |---|---|---|---|
/// | session_list_page.dart | `_showFilterSheet` | 自绘筛选面板（`showCupertinoModalPopup`） | 面板型，含分组/多选控件，无 title/content/actions 三槽位 |
/// | session_list_page.dart | `_showExportFormat` | `CupertinoActionSheet`（导出格式二选一） | 底部操作表（含 cancelButton），非 alert |
/// | chat_input_bar.dart | `_showSavedPromptsSheet` 宽屏分支 | `showCupertinoPopover` 锚定气泡 | 悬浮气泡，锚在书签按钮上方 |
/// | chat_input_bar.dart | `_showSavedPromptsSheet` 窄屏分支 | `showCupertinoModalPopup` 自绘 Sheet | 面板型（SavedPromptsSheet） |
/// | chat_input_bar.dart | `_showContextPopover` | `showCupertinoPopover`（260×520） | 悬浮气泡，含自绘内容 |
/// | message_action_menu.dart | `_showMessageActionSheet` | `CupertinoActionSheet` | 底部操作表（§D1 之外的触屏档，行高 44） |
/// | message_action_menu.dart | `_showMessageActionPopover` | `showCupertinoPopover`（§D3 鼠标档） | 右键悬浮面板，行高 30 + 快捷键列 |
///
/// 计数口径：只认**调用形态**（`名(` / `名<类型>(`），不认文档引用
/// （`[名]` / `` `名` ``）—— 所以本表的数字是「真实调用点数」，不被注释干扰。
final Map<String, Map<String, int>> _kUnmigratedPopups =
    <String, Map<String, int>>{
      'lib/features/session_list/session_list_page.dart': <String, int>{
        'showCupertinoModalPopup': 2,
        'showCupertinoPopover': 0,
      },
      'lib/features/chat/widgets/chat_input_bar.dart': <String, int>{
        'showCupertinoModalPopup': 1,
        'showCupertinoPopover': 2,
      },
      'lib/features/chat/widgets/selection_chips.dart': <String, int>{
        'showCupertinoModalPopup': 0,
        'showCupertinoPopover': 0,
      },
      'lib/features/chat/widgets/message_action_menu.dart': <String, int>{
        'showCupertinoModalPopup': 1,
        'showCupertinoPopover': 1,
      },
    };

/// 宽屏断言：居中卡片在、系统 alert 不在、宽度 = 档位绝对值、路由是宽屏特化路由。
void _expectWideCard(WidgetTester tester, double width) {
  expect(find.byType(HermesDialogCard), findsOneWidget, reason: '宽屏必须走居中卡片');
  expect(
    find.byType(CupertinoAlertDialog),
    findsNothing,
    reason: '宽屏不得再出系统 alert（其内部是 270 定宽，正是本批要消掉的形态）',
  );
  final card = find.byKey(kHermesDialogCardKey);
  expect(card, findsOneWidget);
  expect(tester.getSize(card).width, width, reason: '档位宽度是契约，取绝对值（$width）');
  expect(
    ModalRoute.of(tester.element(card)),
    isA<HermesDialogRoute<Object?>>(),
  );
}

/// 窄屏断言：仍是原系统 `CupertinoAlertDialog`，且**不是**宽屏特化路由。
void _expectNarrowSystemAlert(WidgetTester tester) {
  final alert = find.byType(CupertinoAlertDialog);
  expect(alert, findsOneWidget, reason: '窄屏必须仍走原系统弹窗路径');
  expect(find.byType(HermesDialogCard), findsNothing);
  final route = ModalRoute.of(tester.element(alert));
  expect(route, isA<CupertinoDialogRoute<Object?>>());
  expect(
    route,
    isNot(isA<HermesDialogRoute<Object?>>()),
    reason: '窄屏不得混进宽屏特化路由（否则「逐像素不变」立即失守）',
  );
}

/// dio mock adapter（导出链路走 `apiClientProvider`，不是 fake session api）。
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({required this.responder});

  ResponseBody Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => responder(options);

  @override
  void close({bool force = false}) {}
}

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

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(String id, String title) => SessionSummary(
  sessionId: id,
  title: title,
  lastMessageAt: _sec(DateTime.now()),
);

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

/// 会话列表宿主（真 `SessionListPage` + 真 l10n + go_router）。
Future<FakeSessionListApi> _pumpSessionList(
  WidgetTester tester, {
  required Size size,
  ApiClient? client,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = FakeSessionListApi(
    sessions: <SessionSummary>[_session('s1', '会话一')],
  );
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
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
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          client ?? ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        sessionListApiFactoryProvider.overrideWithValue((_) => api),
        projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      ],
      child: CupertinoApp.router(
        routerConfig: router,
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
  await tester.pump();
  await tester.pump();
  return api;
}

/// 打开首行行操作菜单。
Future<void> _openRowActions(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
  await tester.pumpAndSettle();
}

/// 进入多选模式（长按首行）并打开批量归档确认框。
Future<void> _openBatchArchiveDialog(WidgetTester tester) async {
  await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-archive')));
  await tester.pumpAndSettle();
}

/// 消息操作菜单宿主（直调 [showMessageActionMenu]；`position` 非空 = 宽屏悬浮面板路径）。
Future<void> _pumpMessageMenuHost(
  WidgetTester tester, {
  required Size size,
  required Offset? position,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: Builder(
            builder: (context) => Center(
              child: CupertinoButton(
                key: const ValueKey('open-message-menu'),
                onPressed: () => showMessageActionMenu(
                  context,
                  message: const ChatMessage(
                    role: 'assistant',
                    content: '正文',
                    messageId: 'm1',
                  ),
                  position: position,
                ),
                child: const Text('打开菜单'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 点开菜单里的「截断」并等确认框入场。
Future<void> _openTruncateConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-message-menu')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const ValueKey('msg-action-truncate')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 选区条宿主（真 `SelectionChipPanel` + 一条待发选区）。
Future<void> _pumpSelectionChips(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(pendingSelectionsProvider('s1').notifier).add('hello');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(child: SelectionChipPanel(sessionId: 's1')),
      ),
    ),
  );
  await tester.pump();
}

/// 打开选区重命名弹窗。
Future<void> _openRenameDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('selection-rename-ctx-1')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 输入栏宿主：真 `ChatPage`（停止确认框的唯一真实入口）。
Future<FakeChatApi> _pumpChatPage(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final chatApi = FakeChatApi();
  chatApi.sessionResult = <String, Object?>{
    'session': <String, Object?>{
      'session_id': 's1',
      'messages': const <Object?>[],
    },
  };
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        chatApiProvider.overrideWithValue(chatApi),
        promptsApiFactoryProvider.overrideWithValue(
          (_) => FakePromptsApi(initialPrompts: const []),
        ),
        filePickerServiceProvider.overrideWithValue(FakeFilePickerService()),
        clipboardPasteServiceProvider.overrideWithValue(
          FakeClipboardPasteService(),
        ),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
      ],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return chatApi;
}

/// 发一条消息进入流式（停止按钮出现）→ 点停止 → 弹确认框。
Future<void> _openStopConfirm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('chat-input-field')),
    '测试问题',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('chat-send-button')));
  await tester.pump();
  await tester.pump();
  expect(find.byKey(const ValueKey('chat-stop-button')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('chat-stop-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SafeClipboard.resetOverridesForTesting();
  });
  tearDown(() {
    SafeClipboard.resetOverridesForTesting();
  });

  group('C2 · 源级守卫：迁移完备 + 分档表即契约', () {
    test('四个文件里 showCupertinoDialog 零残留', () {
      for (final path in _kMigrationTable.keys) {
        final source = File(path).readAsStringSync();
        expect(
          'showCupertinoDialog'.allMatches(source).length,
          0,
          reason: '$path 仍有 showCupertinoDialog 残留（本批应全部迁到 showHermesDialog）',
        );
      }
    });

    test('逐处分档与迁移表一致（顺序敏感）', () {
      final pattern = RegExp(r'kind:\s*HermesDialogKind\.(\w+)');
      for (final entry in _kMigrationTable.entries) {
        final source = File(entry.key).readAsStringSync();
        final actual = pattern
            .allMatches(source)
            .map((m) => m.group(1))
            .toList(growable: false);
        expect(
          actual,
          entry.value.map((k) => k.name).toList(growable: false),
          reason: '${entry.key} 的逐处分档与迁移表不符',
        );
      }
    });

    // 【五路合成后改钉 2026-09-27】原断言「排除的两个文件仍是原调用」只在**隔离 worktree**
    // 期有意义（那是防撞车的自查）；五路合成后这两个文件已由 **C5** 合法迁移（C5 的分区
    // 正是它们），排他性断言必然失败。撞车风险由「worktree 隔离 + 文件级分区」在**流程上**
    // 保证，不靠测试断言 —— 这里改为断言**本片分区完备**（正向、与合并状态无关）。
    test('本片分区完备：四个文件的旧调用已清零（排除文件归 C5，不在本片断言内）', () {
      const migrated = <String>[
        'lib/features/session_list/session_list_page.dart',
        'lib/features/chat/widgets/chat_input_bar.dart',
        'lib/features/chat/widgets/selection_chips.dart',
        'lib/features/chat/widgets/message_action_menu.dart',
      ];
      for (final path in migrated) {
        final source = File(path).readAsStringSync();
        expect(
          'showCupertinoDialog'.allMatches(source),
          isEmpty,
          reason: '$path 属本片分区，不应再有旧调用',
        );
      }
    });

    test('非 alert 系弹层按清单保持原状（本批不迁移它们）', () {
      for (final entry in _kUnmigratedPopups.entries) {
        final source = File(entry.key).readAsStringSync();
        for (final pair in entry.value.entries) {
          // 只认调用形态：`名(` 或 `名<类型>(`（文档引用 `[名]` / `名` 不计）。
          final calls = RegExp('${pair.key}\\s*[<(]').allMatches(source).length;
          expect(
            calls,
            pair.value,
            reason:
                '${entry.key} 的 ${pair.key} 调用点数变了 —— '
                '本批只迁 alert 系弹窗（见文件末尾「未迁移」清单）',
          );
        }
      }
    });
  });

  group('C2 · 宽屏真渲染：deck 分档各自命中（绝对宽度）', () {
    testWidgets('会话列表 · 批量归档确认框 → 380', (tester) async {
      await _pumpSessionList(tester, size: _kWide);
      await _openBatchArchiveDialog(tester);
      _expectWideCard(tester, _kConfirmWidth);
    });

    testWidgets('会话列表 · 批量删除确认框 → 380（破坏性动作仍标红）', (tester) async {
      await _pumpSessionList(tester, size: _kWide);
      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-delete')));
      await tester.pumpAndSettle();
      _expectWideCard(tester, _kConfirmWidth);
      expect(
        find.byKey(const ValueKey('batch-delete-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('会话列表 · 行菜单删除确认框 → 380', (tester) async {
      await _pumpSessionList(tester, size: _kWide);
      await _openRowActions(tester);
      await tester.tap(find.byKey(const ValueKey('session-action-delete')));
      await tester.pumpAndSettle();
      _expectWideCard(tester, _kConfirmWidth);
      expect(
        find.byKey(const ValueKey('session-delete-cancel')),
        findsOneWidget,
      );
    });

    testWidgets('会话列表 · 导出成功（长文本预览）→ 760 宽表单档', (tester) async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('md-export-body', 200),
      );
      await _pumpSessionList(
        tester,
        size: _kWide,
        client: _adapterClient(adapter),
      );
      await _openRowActions(tester);
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-export-markdown')));
      await tester.pumpAndSettle();

      _expectWideCard(tester, _kWideFormWidth);
      expect(find.text('md-export-body'), findsOneWidget);
    });

    testWidgets('会话列表 · 导出失败提示 → 380', (tester) async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('server exploded', 500),
      );
      await _pumpSessionList(
        tester,
        size: _kWide,
        client: _adapterClient(adapter),
      );
      await _openRowActions(tester);
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-export-markdown')));
      await tester.pumpAndSettle();

      _expectWideCard(tester, _kConfirmWidth);
      expect(find.text('导出失败'), findsOneWidget);
    });

    testWidgets('消息菜单 · 宽屏悬浮面板的截断确认 → 380', (tester) async {
      await _pumpMessageMenuHost(
        tester,
        size: _kWide,
        position: const Offset(500, 300),
      );
      await _openTruncateConfirm(tester);
      _expectWideCard(tester, _kConfirmWidth);
      expect(
        find.byKey(const ValueKey('msg-truncate-confirm')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('msg-truncate-cancel')), findsOneWidget);
    });

    testWidgets('消息菜单 · 宽屏视口下的 ActionSheet 路径截断确认 → 380', (tester) async {
      await _pumpMessageMenuHost(tester, size: _kWide, position: null);
      await _openTruncateConfirm(tester);
      _expectWideCard(tester, _kConfirmWidth);
    });

    testWidgets('选区条 · 重命名弹窗（含输入框）→ 560 表单档', (tester) async {
      await _pumpSelectionChips(tester, size: _kWide);
      await _openRenameDialog(tester);
      _expectWideCard(tester, _kFormWidth);
      expect(
        find.byKey(const ValueKey('selection-rename-field')),
        findsOneWidget,
        reason: '输入框必须还在（迁移只换形态，不换内容）',
      );
    });

    testWidgets('输入栏 · 停止生成确认框 → 380', (tester) async {
      await _pumpChatPage(tester, size: _kWide);
      await _openStopConfirm(tester);
      _expectWideCard(tester, _kConfirmWidth);
      expect(find.text('停止生成？'), findsOneWidget);
      expect(find.text('确定要停止当前回复吗？已生成的内容会保留。'), findsOneWidget);
    });
  });

  group('C2 · 窄屏（<900）：仍走原系统弹窗，逐像素不变的结构判据', () {
    testWidgets('会话列表 · 批量归档确认框仍是 CupertinoAlertDialog（且 key 契约保留）', (
      tester,
    ) async {
      await _pumpSessionList(tester, size: _kNarrow);
      await _openBatchArchiveDialog(tester);
      _expectNarrowSystemAlert(tester);
      expect(find.text('批量归档'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('batch-archive-cancel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch-archive-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('会话列表 · 批量删除确认框仍是 CupertinoAlertDialog', (tester) async {
      await _pumpSessionList(tester, size: _kNarrow);
      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-delete')));
      await tester.pumpAndSettle();
      _expectNarrowSystemAlert(tester);
      expect(find.byKey(const ValueKey('batch-delete-cancel')), findsOneWidget);
    });

    testWidgets('会话列表 · 导出成功弹窗仍是 CupertinoAlertDialog', (tester) async {
      final adapter = _MockAdapter(
        responder: (_) => ResponseBody.fromString('md-export-body', 200),
      );
      await _pumpSessionList(
        tester,
        size: _kNarrow,
        client: _adapterClient(adapter),
      );
      await _openRowActions(tester);
      await tester.tap(find.byKey(const ValueKey('session-action-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-export-markdown')));
      await tester.pumpAndSettle();

      _expectNarrowSystemAlert(tester);
      expect(find.text('md-export-body'), findsOneWidget);
      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
    });

    testWidgets('消息菜单 · 窄屏 ActionSheet 的截断确认仍是 CupertinoAlertDialog', (
      tester,
    ) async {
      await _pumpMessageMenuHost(tester, size: _kNarrow, position: null);
      await _openTruncateConfirm(tester);
      _expectNarrowSystemAlert(tester);
      expect(
        find.byKey(const ValueKey('msg-truncate-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('选区条 · 重命名弹窗仍是 CupertinoAlertDialog', (tester) async {
      await _pumpSelectionChips(tester, size: _kNarrow);
      await _openRenameDialog(tester);
      _expectNarrowSystemAlert(tester);
      expect(
        find.byKey(const ValueKey('selection-rename-field')),
        findsOneWidget,
      );
    });

    testWidgets('输入栏 · 停止生成确认框仍是 CupertinoAlertDialog', (tester) async {
      await _pumpChatPage(tester, size: _kNarrow);
      await _openStopConfirm(tester);
      _expectNarrowSystemAlert(tester);
      expect(find.text('停止生成？'), findsOneWidget);
      expect(find.text('确定要停止当前回复吗？已生成的内容会保留。'), findsOneWidget);
    });
  });
}
