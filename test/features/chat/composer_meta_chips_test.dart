import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';
import 'package:hermes_ui/app/widgets/adaptive_action_menu.dart';
import 'package:hermes_ui/app/widgets/popover_dropdown.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/composer_meta_chips.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      ComposerTwoPaneController.keyTwoPane: false,
    });
  });

  Widget buildTestApp({
    required Widget child,
    List<dynamic> overrides = const [],
    Brightness brightness = Brightness.light,
  }) {
    return ProviderScope(
      overrides: [
        for (final o in overrides) o,
      ],
      child: CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        home: CupertinoPageScaffold(
          child: child,
        ),
      ),
    );
  }

  group('输入区「工作区 / 模型」元信息 chip（#145）', () {
    testWidgets('经典 Row 模式：chip 渲染在发送按钮左侧', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: false,
      });
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/ws',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/ws', name: 'MyProject'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      // 验证两枚 chip 均在树中
      final wsChip = find.byKey(const ValueKey('composer-workspace-chip'));
      final modelChip = find.byKey(const ValueKey('composer-model-chip'));
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));

      expect(wsChip, findsOneWidget);
      expect(modelChip, findsOneWidget);
      expect(sendBtn, findsOneWidget);

      // 位置断言：wsChip.dx < modelChip.dx < sendBtn.dx
      final wsDx = tester.getTopLeft(wsChip).dx;
      final modelDx = tester.getTopLeft(modelChip).dx;
      final sendDx = tester.getTopLeft(sendBtn).dx;

      expect(wsDx, lessThan(modelDx));
      expect(modelDx, lessThan(sendDx));
    });

    testWidgets('两段式模式：chip 渲染在发送按钮左侧且在 PerfMonitorPanel 之后', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/ws',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/ws', name: 'MyProject'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      final wsChip = find.byKey(const ValueKey('composer-workspace-chip'));
      final modelChip = find.byKey(const ValueKey('composer-model-chip'));
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));

      expect(wsChip, findsOneWidget);
      expect(modelChip, findsOneWidget);
      expect(sendBtn, findsOneWidget);

      final wsDx = tester.getTopLeft(wsChip).dx;
      final modelDx = tester.getTopLeft(modelChip).dx;
      final sendDx = tester.getTopLeft(sendBtn).dx;

      expect(wsDx, lessThan(modelDx));
      expect(modelDx, lessThan(sendDx));
    });

    testWidgets('正常态：会话已设值显示「键名 + 值」，实名匹配与模型正常展示', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/alpha',
          'model': 'claude-3-5-sonnet',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/alpha', name: 'AlphaProject'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['claude-3-5-sonnet']),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      // 键名与值都在文本中可见
      expect(find.text('工作区'), findsOneWidget);
      expect(find.text('AlphaProject'), findsOneWidget);
      expect(find.text('模型'), findsOneWidget);
      expect(find.text('claude-3-5-sonnet'), findsOneWidget);

      // 非虚线描边：chip 内部不得包含 DashedRRectPainter
      final chipPaints = tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey('composer-workspace-chip')),
          matching: find.byType(CustomPaint),
        ),
      );
      final dashedPainters = chipPaints
          .map((p) => p.painter)
          .whereType<DashedRRectPainter>()
          .toList();
      expect(dashedPainters, isEmpty);
    });

    testWidgets('无值态：会话未设值显示虚线描边 + 选择工作区 / 跟随默认模型', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': null,
          'model': null,
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => const <WorkspaceRoot>[]),
            availableModelIdsProvider.overrideWith((ref) => const <String>[]),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('选择工作区'), findsOneWidget);
      expect(find.text('跟随默认模型'), findsOneWidget);

      // 虚线绘制器生效
      final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final dashedPainters = customPaints
          .map((p) => p.painter)
          .whereType<DashedRRectPainter>()
          .toList();
      expect(dashedPainters.length, greaterThanOrEqualTo(2));
    });

    testWidgets('工作区失效态：roots 列表非空且找不到该 path 判定为失效（红字提示）', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/deleted',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/existing', name: 'Existing'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      // 显示工作区已失效文案
      expect(find.text('工作区已失效'), findsOneWidget);
      // 原路径不作为正常值渲染
      expect(find.text('/path/to/deleted'), findsNothing);
    });

    testWidgets('容错判定：roots 列表为空时绝对不误判失效', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/some-ws',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            // 空列表：可能离线或尚未加载
            workspaceRootsProvider.overrideWith((ref) => const <WorkspaceRoot>[]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      // 不得显示失效
      expect(find.text('工作区已失效'), findsNothing);
      expect(find.text('/path/to/some-ws'), findsOneWidget);
    });

    testWidgets('容错判定：roots 加载失败时绝对不误判失效', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/offline-ws',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            // 加载抛错异常
            workspaceRootsProvider.overrideWith((ref) => throw Exception('Network error')),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      // 不得显示失效
      expect(find.text('工作区已失效'), findsNothing);
      expect(find.text('/path/to/offline-ws'), findsOneWidget);
    });

    testWidgets('悬停态：鼠标悬停时描边加深一档', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/ws',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/ws', name: 'MyProject'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const ValueKey('composer-workspace-chip'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      // 移入 chip
      await gesture.moveTo(tester.getCenter(chipFinder));
      await tester.pump();

      // 验证 hover 时的边框色 (#B4B9C4)
      final container = tester.widget<Container>(
        find.descendant(of: chipFinder, matching: find.byType(Container)).first,
      );
      final border = (container.decoration as BoxDecoration).border as Border;
      expect(border.top.color, const Color(0xFFB4B9C4));

      // 移出
      await gesture.moveTo(Offset.zero);
      await tester.pump();

      final containerNormal = tester.widget<Container>(
        find.descendant(of: chipFinder, matching: find.byType(Container)).first,
      );
      final borderNormal = (containerNormal.decoration as BoxDecoration).border as Border;
      expect(borderNormal.top.color, LightSurfaces.cardBorder);
    });

    testWidgets('点击工作区 chip 弹出下拉并切换工作区（调用 updateSessionSettings）', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/ws-a',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/ws-a', name: 'Project A'),
                  const WorkspaceRoot(path: '/path/to/ws-b', name: 'Project B'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: const ChatPage(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      // 点击工作区 chip
      await tester.tap(find.byKey(const ValueKey('composer-workspace-chip')));
      await tester.pumpAndSettle();

      // 验证浮层出现，包含两项工作区和默认项
      final itemB = find.byKey(const ValueKey('composer-workspace-item-/path/to/ws-b'));
      expect(itemB, findsOneWidget);

      // 点击项 B
      await tester.tap(itemB);
      await tester.pumpAndSettle();

      // 验证调用了 updateSessionSettings，参数正确
      expect(fakeApi.updateSessionCalls, 1);
      expect(fakeApi.lastUpdatedWorkspace, '/path/to/ws-b');
      // 浮层已收起
      expect(find.byKey(const ValueKey('composer-workspace-item-/path/to/ws-b')), findsNothing);
    });

    testWidgets('点击模型 chip 弹出下拉并切换模型（调用 selectModel）', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/ws',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      late WidgetRef refCapture;
      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/ws', name: 'MyProject'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o', 'claude-3-5-sonnet']),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              refCapture = ref;
              return const ChatPage(sessionId: 's1');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击模型 chip
      await tester.tap(find.byKey(const ValueKey('composer-model-chip')));
      await tester.pumpAndSettle();

      // 浮层出现模型项
      final modelItem = find.byKey(const ValueKey('composer-model-item-claude-3-5-sonnet'));
      expect(modelItem, findsOneWidget);

      // 点击切换
      await tester.tap(modelItem);
      await tester.pumpAndSettle();

      // 验证模型已切换
      expect(refCapture.read(chatControllerProvider('s1')).model, 'claude-3-5-sonnet');
      expect(find.text('claude-3-5-sonnet'), findsOneWidget);
    });

    testWidgets('点击模型跟随默认模型：切换为 null', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/ws',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      late WidgetRef refCapture;
      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/ws', name: 'MyProject'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              refCapture = ref;
              return const ChatPage(sessionId: 's1');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击模型 chip
      await tester.tap(find.byKey(const ValueKey('composer-model-chip')));
      await tester.pumpAndSettle();

      // 点击「跟随服务器默认」
      final defaultItem = find.byKey(const ValueKey('composer-model-item-default'));
      expect(defaultItem, findsOneWidget);
      await tester.tap(defaultItem);
      await tester.pumpAndSettle();

      // 验证模型已清空
      expect(refCapture.read(chatControllerProvider('s1')).model, isNull);
    });

    testWidgets('失败可见（RED 校验守卫）：updateSessionSettings 失败必须弹出轻提示，不得静默失败', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/ws-a',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };
      // 模拟更新会话接口报错失败
      fakeApi.mutationThrows = HttpException(
        500,
        '{"error":"Server error"}',
      );

      late WidgetRef refCapture;
      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/ws-a', name: 'Project A'),
                  const WorkspaceRoot(path: '/path/to/ws-b', name: 'Project B'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              refCapture = ref;
              return const ChatPage(sessionId: 's1');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 打开工作区下拉并选择
      await tester.tap(find.byKey(const ValueKey('composer-workspace-chip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-workspace-item-/path/to/ws-b')));
      await tester.pumpAndSettle();

      // 断言轻提示 noticeMessage 被触发，文案为操作失败，非静默失败！
      final notice = refCapture.read(chatControllerProvider('s1')).noticeMessage;
      expect(notice, '操作失败');
    });

    testWidgets('宽度与退化：小宽度时 LayoutBuilder 自动丢掉键名只留图标与值', (tester) async {
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/path/to/ws',
          'model': 'gpt-4o',
          'messages': const [],
        },
      };

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            chatApiProvider.overrideWithValue(fakeApi),
            workspaceRootsProvider.overrideWith((ref) => [
                  const WorkspaceRoot(path: '/path/to/ws', name: 'MyProject'),
                ]),
            availableModelIdsProvider.overrideWith((ref) => ['gpt-4o']),
          ],
          child: const SizedBox(
            width: 220, // 紧凑宽度 < 260
            child: ComposerMetaChips(sessionId: 's1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 键名「工作区」和「模型」应被省略
      expect(find.text('工作区'), findsNothing);
      expect(find.text('模型'), findsNothing);

      // 但值依然正常展示
      expect(find.text('MyProject'), findsOneWidget);
      expect(find.text('gpt-4o'), findsOneWidget);
    });
  });

  group('浮层家族重排：宽屏（≥900）双行工作区 / 单行模型，窄屏逐像素不变', () {
    // 宽屏视口（1400×900）：越过 kAdaptiveBreakpoint=900。
    void useWideViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Widget appWith({
      required FakeChatApi fakeApi,
      String? workspace = '/path/to/ws-a',
      String? model = 'gpt-4o',
      List<WorkspaceRoot> roots = const [
        WorkspaceRoot(path: '/path/to/ws-a', name: 'Project A'),
        WorkspaceRoot(path: '/path/to/ws-b', name: 'Project B'),
      ],
      List<String> models = const ['gpt-4o', 'claude-3-5-sonnet'],
      Brightness brightness = Brightness.light,
    }) {
      fakeApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': workspace,
          'model': model,
          'messages': const [],
        },
      };
      return buildTestApp(
        brightness: brightness,
        overrides: [
          chatApiProvider.overrideWithValue(fakeApi),
          workspaceRootsProvider.overrideWith((ref) => roots),
          availableModelIdsProvider.overrideWith((ref) => models),
        ],
        child: const ChatPage(sessionId: 's1'),
      );
    }

    testWidgets('① 宽屏工作区项：名称与路径是两个独立文本节点、分占两行且左对齐；② 当前项竖条存在', (
      tester,
    ) async {
      useWideViewport(tester);
      await tester.pumpWidget(appWith(fakeApi: FakeChatApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-workspace-chip')));
      await tester.pumpAndSettle();

      // 弹层宽 300（宽屏口径）
      expect(tester.getSize(find.byType(PopoverDropdownCard)).width, 300.0);

      final itemB = find.byKey(
        const ValueKey('composer-workspace-item-/path/to/ws-b'),
      );
      expect(itemB, findsOneWidget);

      final nameB = find.descendant(of: itemB, matching: find.text('Project B'));
      final pathB = find.descendant(
        of: itemB,
        matching: find.text('/path/to/ws-b'),
      );
      // 两个独立文本节点同时存在
      expect(nameB, findsOneWidget);
      expect(pathB, findsOneWidget);
      // 各占一行：路径在名称下方
      expect(
        tester.getTopLeft(pathB).dy,
        greaterThan(tester.getTopLeft(nameB).dy),
        reason: '路径必须是独立的第二行，而不是与名称拼成同一个字符串',
      );
      // 与名称左对齐
      expect(
        (tester.getTopLeft(pathB).dx - tester.getTopLeft(nameB).dx).abs(),
        lessThan(0.5),
      );
      // 行高 46（变体 A）
      expect(tester.getSize(itemB).height, 46.0);
      // 图标
      expect(
        find.descendant(of: itemB, matching: find.byIcon(CupertinoIcons.folder)),
        findsOneWidget,
      );

      // ② 当前项（ws-a）竖条存在且与行同高居中
      final bar = find.byKey(const ValueKey('composer-menu-selected-bar'));
      expect(bar, findsOneWidget);
      final itemA = find.byKey(
        const ValueKey('composer-workspace-item-/path/to/ws-a'),
      );
      expect(
        tester.getRect(bar).center.dy,
        closeTo(tester.getRect(itemA).center.dy, 1.0),
      );
      // 竖条只属于当前项
      expect(
        find.descendant(of: itemA, matching: bar),
        findsOneWidget,
      );
      expect(find.descendant(of: itemB, matching: bar), findsNothing);

      // 元操作独立成群：分组线 + uturn 图标
      expect(
        find.descendant(
          of: find.byType(PopoverDropdownCard),
          matching: find.byType(ActionMenuDivider),
        ),
        findsOneWidget,
      );
      final defaultItem = find.byKey(
        const ValueKey('composer-workspace-item-default'),
      );
      expect(
        find.descendant(
          of: defaultItem,
          matching: find.byIcon(CupertinoIcons.arrow_uturn_left),
        ),
        findsOneWidget,
      );
      // 元操作行单行 36（无路径副行）
      expect(tester.getSize(defaultItem).height, 36.0);
    });

    testWidgets('③ 窄屏（<900）：弹层仍 228 宽、行仍单行拼接串、无图标无竖条', (tester) async {
      // 默认测试视口 800×600 < 900
      await tester.pumpWidget(appWith(fakeApi: FakeChatApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-workspace-chip')));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(PopoverDropdownCard)).width, 228.0);

      final itemA = find.byKey(
        const ValueKey('composer-workspace-item-/path/to/ws-a'),
      );
      expect(itemA, findsOneWidget);
      // 旧结构：名称与路径拼成一个字符串
      expect(
        find.descendant(
          of: itemA,
          matching: find.text('Project A (/path/to/ws-a)'),
        ),
        findsOneWidget,
      );
      // 不得出现路径副行 / 行内图标 / 选中竖条 / 分组线
      expect(
        find.descendant(of: itemA, matching: find.text('/path/to/ws-a')),
        findsNothing,
      );
      expect(
        find.descendant(of: itemA, matching: find.byIcon(CupertinoIcons.folder)),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('composer-menu-selected-bar')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(PopoverDropdownCard),
          matching: find.byType(ActionMenuDivider),
        ),
        findsNothing,
      );
    });

    testWidgets('④ 宽屏模型项仍单行（无路径副行），图标 sparkles、行高 36；元操作换 uturn', (
      tester,
    ) async {
      useWideViewport(tester);
      await tester.pumpWidget(appWith(fakeApi: FakeChatApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-model-chip')));
      await tester.pumpAndSettle();

      final modelItem = find.byKey(
        const ValueKey('composer-model-item-claude-3-5-sonnet'),
      );
      expect(modelItem, findsOneWidget);
      expect(tester.getSize(modelItem).height, 36.0);
      // 单行：行内只有一个文本节点（无路径副行）
      expect(
        find.descendant(of: modelItem, matching: find.byType(Text)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: modelItem,
          matching: find.byIcon(CupertinoIcons.sparkles),
        ),
        findsOneWidget,
      );

      // 元操作独立成群：分组线 + uturn 图标
      final defaultItem = find.byKey(
        const ValueKey('composer-model-item-default'),
      );
      expect(
        find.descendant(
          of: defaultItem,
          matching: find.byIcon(CupertinoIcons.arrow_uturn_left),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PopoverDropdownCard),
          matching: find.byType(ActionMenuDivider),
        ),
        findsOneWidget,
      );
    });

    testWidgets('⑤ 宽屏暗色：两态各自定色（名称/竖条 activeBlue、路径 secondaryLabel），走 CupertinoButton 分支不溢出', (
      tester,
    ) async {
      useWideViewport(tester);
      await tester.pumpWidget(
        appWith(fakeApi: FakeChatApi(), brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-workspace-chip')));
      await tester.pumpAndSettle();

      final itemA = find.byKey(
        const ValueKey('composer-workspace-item-/path/to/ws-a'),
      );
      expect(itemA, findsOneWidget);
      expect(tester.getSize(itemA).height, 46.0);

      final nameFinder = find.descendant(
        of: itemA,
        matching: find.text('Project A'),
      );
      final pathFinder = find.descendant(
        of: itemA,
        matching: find.text('/path/to/ws-a'),
      );
      final nameText = tester.widget<Text>(nameFinder);
      final pathText = tester.widget<Text>(pathFinder);

      // 当前项名称：暗色 activeBlue + w600 + kFontBody
      expect(nameText.style!.color!.toARGB32(), 0xFF0A84FF);
      expect(nameText.style!.fontWeight, FontWeight.w600);
      expect(nameText.style!.fontSize, kFontBody);
      // 路径：次级色（暗色 secondaryLabel）+ kFontCaption
      expect(
        pathText.style!.color,
        CupertinoColors.secondaryLabel.resolveFrom(
          tester.element(pathFinder),
        ),
      );
      expect(pathText.style!.fontSize, kFontCaption);

      // 竖条同色 activeBlue
      final bar = find.byKey(const ValueKey('composer-menu-selected-bar'));
      final barBox = tester.widget<Container>(bar);
      expect(
        (barBox.decoration! as BoxDecoration).color!.toARGB32(),
        0xFF0A84FF,
      );
    });
  });
}
