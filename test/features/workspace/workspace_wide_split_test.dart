import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/workspace/workspace_page.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';

import '../../helpers/fake_download_service.dart';
import '../../helpers/fake_workspace_api.dart';

// ---------------------------------------------------------------------------
// 批 4 · P3 工作区宽屏双栏守卫（左 340 文件树 + 右预览铺满）
//
// 断言对象（缺一不可）：
// 1. 宽屏（≥900）双栏出现：左栏恰为 340、右栏 = 视口 − 左栏（铺满、无阅读限宽夹层）
// 2. 宽屏选中态走 L2（灰底 + 蓝字），且**不再 push 整页预览**
// 3. 宽屏右栏工具型内容不限宽：长行不换行、可横向滚（maxScrollExtent > 0）
// 4. 窄屏（<900）逐像素不变量：无任何宽屏键、仍是单列 + 行菜单 → 整页预览
// ---------------------------------------------------------------------------

/// 宽屏视口：物理 2000×1400 @2x ⇒ 逻辑 1000×700（≥ kWideBreakpoint=900）。
const Size _widePhysical = Size(2000, 1400);

/// 窄屏对照视口：物理 1600×1200 @2x ⇒ 逻辑 800×600（< 900，与 flutter_test 默认同尺寸）。
const Size _narrowPhysical = Size(1600, 1200);

/// 逻辑视口宽度（断言「铺满」用）。
const double _wideLogicalWidth = 1000.0;
const double _narrowLogicalWidth = 800.0;

/// 一条远超右栏宽度的代码行（验证「不换行 + 可横向滚」）。
final String _longLine =
    'final veryLongDeclaration = const <String>['
    '${List<String>.generate(40, (i) => "'segment_$i'").join(', ')}'
    ']; // 这一行远长于右栏宽度：工具型内容不换行，靠横向滚动读';

Future<FakeWorkspaceApi> _pumpWorkspace(
  WidgetTester tester, {
  required Size physicalSize,
  required Map<String, List<WorkspaceEntry>> directories,
  Map<String, FileResponse> fileContents = const {},
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final api = FakeWorkspaceApi(directories: directories);
  api.fileContents.addAll(fileContents);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        workspaceApiFactoryProvider.overrideWithValue((_) => api),
        ...createDownloadTestOverrides(),
      ],
      child: const CupertinoApp(home: WorkspacePage(sessionId: 's1')),
    ),
  );
  // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
  await tester.pump();
  await tester.pump();
  return api;
}

Map<String, List<WorkspaceEntry>> _demoTree() => {
  '.': [
    const WorkspaceEntry(
      name: 'lib',
      path: 'lib',
      type: 'directory',
      isDirectory: true,
    ),
    const WorkspaceEntry(name: 'a.txt', path: 'a.txt', size: 18),
    const WorkspaceEntry(name: 'b.txt', path: 'b.txt', size: 24),
  ],
  'lib': [
    const WorkspaceEntry(name: 'main.dart', path: 'lib/main.dart', size: 42),
  ],
};

/// 取某个 key 下 Scrollable 的滚动范围（证明「真的能滚」而不是「看起来能滚」）。
double _maxScrollExtentOf(WidgetTester tester, String key) {
  final state = tester.state<ScrollableState>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Scrollable),
    ),
  );
  return state.position.maxScrollExtent;
}

void main() {
  group('工作区 · 宽屏双栏（≥900）', () {
    testWidgets('左 340 文件树 + 右预览同时出现，右栏铺满到视口右缘', (tester) async {
      await _pumpWorkspace(
        tester,
        physicalSize: _widePhysical,
        directories: _demoTree(),
      );

      final tree = find.byKey(const ValueKey('workspace-wide-tree'));
      final pane = find.byKey(const ValueKey('workspace-wide-preview-pane'));
      expect(tree, findsOneWidget);
      expect(pane, findsOneWidget);

      final treeRect = tester.getRect(tree);
      final paneRect = tester.getRect(pane);
      // 左栏宽度 = 设计稿 340（数值即契约）。
      expect(treeRect.width, kWideWorkspaceTreeWidth);
      expect(kWideWorkspaceTreeWidth, 340.0);
      // 右栏 = 视口 − 左栏（铺满、无任何内容限宽夹层）。
      expect(paneRect.width, _wideLogicalWidth - kWideWorkspaceTreeWidth);
      expect(
        paneRect.right,
        moreOrLessEquals(_wideLogicalWidth, epsilon: 0.01),
      );
      // 两栏相邻（0.5px 发丝线画在左栏内，不留缝）。
      expect(paneRect.left, moreOrLessEquals(treeRect.right, epsilon: 0.01));

      // 未选文件时右栏是占位态（不是空白）。
      expect(
        find.byKey(const ValueKey('workspace-wide-preview-empty')),
        findsOneWidget,
      );
      // 左栏是文件树本体（行仍是同一批行）。
      expect(find.byKey(const ValueKey('workspace-row-a.txt')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-row-lib')), findsOneWidget);
    });

    testWidgets('点文件 → 右栏就地预览（不 push 整页）+ 左栏 L2 选中态', (tester) async {
      await _pumpWorkspace(
        tester,
        physicalSize: _widePhysical,
        directories: _demoTree(),
        fileContents: {
          'a.txt': const FileResponse(
            path: 'a.txt',
            name: 'a.txt',
            size: 18,
            lines: 1,
            content: 'hello wide preview',
          ),
        },
      );

      await tester.tap(find.byKey(const ValueKey('workspace-row-a.txt')));
      await tester.pump();
      await tester.pump();

      // 内容进右栏 —— 整页预览页**没有**被 push（`preview-scroll` 是预览页的 key）。
      expect(find.text('hello wide preview'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-scroll')), findsNothing);
      // 右栏标题行显示文件名。
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('workspace-wide-preview-title')),
            )
            .data,
        'a.txt',
      );

      // 左栏选中态：L2 中性灰底 + 蓝字。
      final selected = find.byKey(
        const ValueKey('workspace-row-selected-a.txt'),
      );
      expect(selected, findsOneWidget);
      expect(
        tester.widget<ColoredBox>(selected).color,
        LightSurfaces.selectedSurface,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('workspace-row-a.txt')),
                matching: find.text('a.txt'),
              ),
            )
            .style
            ?.color,
        LightSurfaces.selectionForeground,
      );
      // 其它行不受影响（单选）。
      expect(
        find.byKey(const ValueKey('workspace-row-selected-b.txt')),
        findsNothing,
      );

      // 换一个文件：右栏就地在同一个面板内换内容，左栏选中态跟着走。
      await tester.tap(find.byKey(const ValueKey('workspace-row-b.txt')));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('workspace-row-selected-b.txt')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-row-selected-a.txt')),
        findsNothing,
      );
    });

    testWidgets('右栏工具型内容：铺满不限宽 + 长行不换行可横向滚', (tester) async {
      await _pumpWorkspace(
        tester,
        physicalSize: _widePhysical,
        directories: _demoTree(),
        fileContents: {
          'a.txt': FileResponse(
            path: 'a.txt',
            name: 'a.txt',
            size: _longLine.length,
            lines: 1,
            content: _longLine,
          ),
        },
      );

      await tester.tap(find.byKey(const ValueKey('workspace-row-a.txt')));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('workspace-wide-preview-empty')),
        findsNothing,
      );
      // 横向常显滚动条存在（G4：宽屏常显）。
      expect(
        find.byKey(const ValueKey('workspace-wide-preview-hscroll')),
        findsOneWidget,
      );

      // 正文一行铺开（不换行）：渲染宽度越出右栏 ⇒ 只有「不限宽」才可能。
      final paneWidth = tester
          .getRect(find.byKey(const ValueKey('workspace-wide-preview-pane')))
          .width;
      final textWidth = tester
          .getSize(find.byKey(const ValueKey('preview-text')))
          .width;
      expect(paneWidth, 660.0);
      expect(textWidth, greaterThan(paneWidth));

      // 真能横滚（滚动范围 > 0），而不是「看起来宽但被裁掉」。
      expect(
        _maxScrollExtentOf(tester, 'workspace-wide-preview-hscroll'),
        greaterThan(0),
      );

      // 「无额外限宽」：右栏内不得出现比右栏更窄的有限宽上限（阅读型 760 夹层等）。
      final clamps = tester.widgetList<ConstrainedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('workspace-wide-preview-pane')),
          matching: find.byType(ConstrainedBox),
        ),
      );
      for (final clamp in clamps) {
        final maxWidth = clamp.constraints.maxWidth;
        if (maxWidth.isFinite) {
          expect(maxWidth, greaterThanOrEqualTo(paneWidth));
        }
      }
    });

    testWidgets('左栏仍可导航：点目录进子目录，右栏预览不受影响', (tester) async {
      await _pumpWorkspace(
        tester,
        physicalSize: _widePhysical,
        directories: _demoTree(),
        fileContents: {
          'a.txt': const FileResponse(path: 'a.txt', content: 'kept in pane'),
        },
      );

      await tester.tap(find.byKey(const ValueKey('workspace-row-a.txt')));
      await tester.pump();
      await tester.pump();
      expect(find.text('kept in pane'), findsOneWidget);

      await tester.tap(find.text('lib'));
      await tester.pump();
      await tester.pump();

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('kept in pane'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-wide-preview-pane')),
        findsOneWidget,
      );
    });
  });

  group('工作区 · 窄屏不变量（<900）', () {
    testWidgets('仍是单列文件树：无任何宽屏键，列表占满视口宽', (tester) async {
      await _pumpWorkspace(
        tester,
        physicalSize: _narrowPhysical,
        directories: _demoTree(),
      );

      expect(find.byKey(const ValueKey('workspace-wide-tree')), findsNothing);
      expect(
        find.byKey(const ValueKey('workspace-wide-tree-scroll')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workspace-wide-preview-pane')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workspace-wide-preview-empty')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workspace-wide-preview-title')),
        findsNothing,
      );

      // 单列：行清单铺满整幅视口宽（insetGrouped 左右各 20 内边距 ⇒ 800 − 40）。
      expect(
        tester.getRect(find.byKey(const ValueKey('workspace-row-a.txt'))).width,
        _narrowLogicalWidth - 40,
      );
      // 无选中态（窄屏没有「就地预览」这回事）。
      expect(
        find.byKey(const ValueKey('workspace-row-selected-a.txt')),
        findsNothing,
      );
    });

    testWidgets('仍是「行菜单 → 整页预览」：点文件弹菜单，预览走 push', (tester) async {
      final api = await _pumpWorkspace(
        tester,
        physicalSize: _narrowPhysical,
        directories: _demoTree(),
        fileContents: {
          'a.txt': const FileResponse(
            path: 'a.txt',
            content: 'narrow full page preview',
          ),
        },
      );

      // 点文件行 → 原样弹操作菜单（不是就地预览）。
      await tester.tap(find.byKey(const ValueKey('workspace-row-a.txt')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-action-preview')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('workspace-action-preview')));
      await tester.pumpAndSettle();

      // 整页预览页被 push 且内容来自 /api/file。
      expect(find.byKey(const ValueKey('preview-scroll')), findsOneWidget);
      expect(find.text('narrow full page preview'), findsOneWidget);
      expect(api.fetchFileCalls, ['s1|a.txt']);
    });
  });
}
