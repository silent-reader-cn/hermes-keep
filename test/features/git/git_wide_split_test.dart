import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';
import 'package:hermes_ui/features/git/git_api.dart';
import 'package:hermes_ui/features/git/git_page.dart';

import '../../helpers/fake_git_api.dart';

// ---------------------------------------------------------------------------
// 批 4 · P9 Git 宽屏双栏守卫（左 380 变更列表 + 右 diff 铺满）
//
// 断言对象（缺一不可）：
// 1. 宽屏（≥900）双栏出现：左栏恰为 380、右栏 = 视口 − 左栏（铺满、无阅读限宽夹层）
// 2. 左栏保留四段结构（已暂存 / 未暂存 / 分支树 / 提交）
// 3. 点文件 → diff 进**右栏**（左栏不再内联展开）+ 左栏 L2 选中态
// 4. diff 工具型内容不限宽：长行不换行、可横向滚（maxScrollExtent > 0）
// 5. 窄屏（<900）逐像素不变量：无任何宽屏键、diff 仍在原列表内就地展开
// 6. 暗色 diff 底色仍走**解析后**的 secondarySystemBackground（防回退未 resolve 的
//    动态色 —— 那是「白字叠浅底」的老 bug）
// ---------------------------------------------------------------------------

/// 宽屏视口：物理 2000×1400 @2x ⇒ 逻辑 1000×700（≥ kWideBreakpoint=900）。
const Size _widePhysical = Size(2000, 1400);

/// 窄屏对照视口：物理 1600×1200 @2x ⇒ 逻辑 800×600（< 900，与 flutter_test 默认同尺寸）。
const Size _narrowPhysical = Size(1600, 1200);

const double _wideLogicalWidth = 1000.0;
const double _narrowLogicalWidth = 800.0;

const String _stagedPath = 'lib/app/theme/light_surfaces.dart';
const String _unstagedPath = 'lib/features/session_list/session_list_page.dart';

/// 一条远超右栏宽度的 diff 行（验证「不换行 + 可横向滚」）。
final String _longDiffLine =
    '+  static const Color veryLongTokenName = Color(0xFF005FB8); '
    '// 这一行远长于右栏宽度：diff 是工具型内容，不换行，靠横向滚动读。';

String _demoDiff() =>
    'diff --git a/$_unstagedPath b/$_unstagedPath\n'
    'index 38f8a4c..b71d2e0 100644\n'
    '--- a/$_unstagedPath\n'
    '+++ b/$_unstagedPath\n'
    '@@ -1,3 +1,4 @@\n'
    '$_longDiffLine\n';

GitStatus _demoStatus() => GitStatus(
  isGit: true,
  branch: 'main',
  upstream: 'origin/main',
  ahead: 1,
  behind: 0,
  totals: const GitTotals(changed: 2, staged: 1, unstaged: 1, untracked: 0),
  files: [
    GitFile(
      path: _stagedPath,
      status: 'M',
      staged: true,
      additions: 3,
      deletions: 1,
    ),
    GitFile(
      path: _unstagedPath,
      status: 'M',
      unstaged: true,
      additions: 120,
      deletions: 8,
    ),
  ],
);

Future<FakeGitApi> _pumpGit(
  WidgetTester tester, {
  required Size physicalSize,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final api = FakeGitApi(status: _demoStatus())
    ..diffResponse = GitDiffResponse(
      diff: GitDiff(path: _unstagedPath, diff: _demoDiff()),
    );

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const GitPage(sessionId: 's1'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        gitApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp.router(
        routerConfig: router,
        theme: buildCupertinoTheme(brightness),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return api;
}

/// 取某个 key 下 Scrollable 的滚动范围（证明「真的能滚」）。
double _maxScrollExtentOf(WidgetTester tester, String key) {
  final state = tester.state<ScrollableState>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Scrollable),
    ),
  );
  return state.position.maxScrollExtent;
}

Future<void> _selectUnstagedFile(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('git-file-$_unstagedPath')));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('Git · 宽屏双栏（≥900）', () {
    testWidgets('左 380 变更列表（四段保留）+ 右 diff 铺满到视口右缘', (tester) async {
      await _pumpGit(tester, physicalSize: _widePhysical);

      final changes = find.byKey(const ValueKey('git-wide-changes'));
      final pane = find.byKey(const ValueKey('git-wide-diff-pane'));
      expect(changes, findsOneWidget);
      expect(pane, findsOneWidget);

      final changesRect = tester.getRect(changes);
      final paneRect = tester.getRect(pane);
      // 左栏宽度 = 设计稿 380（数值即契约）。
      expect(changesRect.width, kWideGitChangesWidth);
      expect(kWideGitChangesWidth, 380.0);
      // 右栏 = 视口 − 左栏（铺满、无任何内容限宽夹层）。
      expect(paneRect.width, _wideLogicalWidth - kWideGitChangesWidth);
      expect(
        paneRect.right,
        moreOrLessEquals(_wideLogicalWidth, epsilon: 0.01),
      );
      expect(paneRect.left, moreOrLessEquals(changesRect.right, epsilon: 0.01));

      // 四段结构原样保留在左栏内：已暂存 / 未暂存 / 分支树 / 提交。
      expect(
        find.descendant(of: changes, matching: find.text('已暂存')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: changes, matching: find.text('未暂存')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: changes, matching: find.text('分支树')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('git-branch-tree-section')),
        findsOneWidget,
      );
      // 「提交」既是分区标题也是按钮文案 ⇒ 左栏内两处。
      expect(
        find.descendant(of: changes, matching: find.text('提交')),
        findsNWidgets(2),
      );

      // 未选文件时右栏是占位态。
      expect(find.byKey(const ValueKey('git-wide-diff-empty')), findsOneWidget);
      // 右栏此刻没有 diff 块。
      expect(find.byKey(const ValueKey('git-diff')), findsNothing);
    });

    testWidgets('点文件 → diff 进右栏（左栏不再内联）+ 左栏 L2 选中态', (tester) async {
      await _pumpGit(tester, physicalSize: _widePhysical);
      await _selectUnstagedFile(tester);

      final pane = find.byKey(const ValueKey('git-wide-diff-pane'));
      // diff 只在右栏：左栏内不得再出现 git-diff。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('git-wide-changes')),
          matching: find.byKey(const ValueKey('git-diff')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: pane,
          matching: find.byKey(const ValueKey('git-diff')),
        ),
        findsOneWidget,
      );
      // 右栏标题行 = 该文件路径。
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('git-wide-diff-path')))
            .data,
        _unstagedPath,
      );
      expect(find.byKey(const ValueKey('git-wide-diff-empty')), findsNothing);

      // 左栏选中态：L2 中性灰底。
      final tile = tester.widget<CupertinoListTile>(
        find.byKey(const ValueKey('git-file-$_unstagedPath')),
      );
      expect(tile.backgroundColor, LightSurfaces.selectedSurface);
      // 未选中的另一行不着色。
      final stagedTile = tester.widget<CupertinoListTile>(
        find.byKey(const ValueKey('git-file-$_stagedPath')),
      );
      expect(stagedTile.backgroundColor, isNull);

      // 点击被点文件仍是「切换选中」（第二次点击折叠 → 右栏回占位，左栏高亮消失）。
      await _selectUnstagedFile(tester);
      expect(find.byKey(const ValueKey('git-diff')), findsNothing);
      expect(
        tester
            .widget<CupertinoListTile>(
              find.byKey(const ValueKey('git-file-$_unstagedPath')),
            )
            .backgroundColor,
        isNull,
      );
    });

    testWidgets('右栏 diff 铺满不限宽：长行不换行、可横向滚', (tester) async {
      await _pumpGit(tester, physicalSize: _widePhysical);
      await _selectUnstagedFile(tester);

      expect(
        find.byKey(const ValueKey('git-wide-diff-hscroll')),
        findsOneWidget,
      );

      final paneWidth = tester
          .getRect(find.byKey(const ValueKey('git-wide-diff-pane')))
          .width;
      final textWidth = tester
          .getSize(find.byKey(const ValueKey('git-wide-diff-text')))
          .width;
      expect(paneWidth, 620.0);
      // 长行铺开（不换行）：渲染宽度越出右栏 ⇒ 只有「不限宽」才可能。
      expect(textWidth, greaterThan(paneWidth));
      // 真能横滚。
      expect(
        _maxScrollExtentOf(tester, 'git-wide-diff-hscroll'),
        greaterThan(0),
      );

      // 「无额外限宽」：右栏内不得出现比右栏更窄的有限宽上限。
      final clamps = tester.widgetList<ConstrainedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('git-wide-diff-pane')),
          matching: find.byType(ConstrainedBox),
        ),
      );
      for (final clamp in clamps) {
        if (clamp.constraints.maxWidth.isFinite) {
          expect(clamp.constraints.maxWidth, greaterThanOrEqualTo(paneWidth));
        }
      }
    });

    testWidgets('暗色 diff 底色仍为**解析后**的 secondarySystemBackground（防回退）', (
      tester,
    ) async {
      await _pumpGit(
        tester,
        physicalSize: _widePhysical,
        brightness: Brightness.dark,
      );
      await _selectUnstagedFile(tester);

      final diff = find.byKey(const ValueKey('git-diff'));
      final element = tester.element(diff);
      final resolved = CupertinoDynamicColor.resolve(
        CupertinoColors.secondarySystemBackground,
        element,
      );
      expect(tester.widget<Container>(diff).color, resolved);
      // 未解析时暗色会落到浅色页面值 —— 那正是老 bug，这里必须不等。
      expect(tester.widget<Container>(diff).color, isNot(LightSurfaces.page));
    });
  });

  group('Git · 窄屏不变量（<900）', () {
    testWidgets('仍是竖排堆叠：无任何宽屏键', (tester) async {
      await _pumpGit(tester, physicalSize: _narrowPhysical);

      expect(find.byKey(const ValueKey('git-wide-changes')), findsNothing);
      expect(
        find.byKey(const ValueKey('git-wide-changes-scroll')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('git-wide-diff-pane')), findsNothing);
      expect(find.byKey(const ValueKey('git-wide-diff-empty')), findsNothing);
      expect(find.byKey(const ValueKey('git-wide-diff-path')), findsNothing);
      expect(find.byKey(const ValueKey('git-wide-diff-text')), findsNothing);

      // 竖排：变更分区铺满整幅视口宽（insetGrouped 左右各 20 ⇒ 800 − 40）。
      expect(
        tester
            .getRect(find.byKey(const ValueKey('git-file-$_stagedPath')))
            .width,
        _narrowLogicalWidth - 40,
      );
    });

    testWidgets('点文件 → diff 仍在原列表内就地展开（不是右栏）', (tester) async {
      await _pumpGit(tester, physicalSize: _narrowPhysical);
      await _selectUnstagedFile(tester);

      final diff = find.byKey(const ValueKey('git-diff'));
      expect(diff, findsOneWidget);
      // 就地展开：diff 挂在整页滚动视图 `git-scroll` 之下。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('git-scroll')),
          matching: diff,
        ),
        findsOneWidget,
      );
      // 窄屏不显示选中底（逐像素不变）。
      expect(
        tester
            .widget<CupertinoListTile>(
              find.byKey(const ValueKey('git-file-$_unstagedPath')),
            )
            .backgroundColor,
        isNull,
      );
      // 浅色 diff 底色仍是页面色。
      expect(tester.widget<Container>(diff).color, LightSurfaces.page);
    });
  });
}
