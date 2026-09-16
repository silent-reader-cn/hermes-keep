import 'dart:ui' show PictureRecorder;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';
import 'package:hermes_ui/features/git/git_branch_tree.dart';

/// 分支节点 Container 的 ValueKey。
ValueKey<String> nodeKey(String name) => ValueKey('git-branch-node-$name');

/// 切换按钮的 ValueKey。
ValueKey<String> switchKey(String name) => ValueKey('git-branch-switch-$name');

GitBranches branchesOf({
  List<GitBranchRef> local = const [],
  List<GitBranchRef> remote = const [],
  String? current,
}) => GitBranches(isGit: true, current: current, local: local, remote: remote);

Future<void> pumpTree(
  WidgetTester tester,
  GitBranchTree tree, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      theme: CupertinoThemeData(brightness: brightness),
      home: CupertinoPageScaffold(child: SingleChildScrollView(child: tree)),
    ),
  );
  await tester.pump();
}

/// 取某个文本「最内层」的 Container 祖先（上游分支 chip 等）。
Container containerAround(WidgetTester tester, String text) {
  return tester.widget<Container>(
    find
        .ancestor(of: find.text(text), matching: find.byType(Container))
        .first,
  );
}

void main() {
  group('GitBranchTree 加载 / 空 / 错误态', () {
    testWidgets('isLoading 且列表为空 → 加载指示器，不显示空态文案', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(branches: branchesOf(), isLoading: true),
      );

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('未找到分支'), findsNothing);
      // 无分支时连本地/远程分段控件都不渲染。
      expect(
        find.byKey(const ValueKey('git-branch-mode-segmented')),
        findsNothing,
      );
    });

    testWidgets('isLoading 但列表非空 → 渲染分支行（加载态让位）', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [GitBranchRef(name: 'main')],
          ),
          isLoading: true,
        ),
      );

      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byKey(nodeKey('main')), findsOneWidget);
    });

    testWidgets('branches 为 null → 空态文案', (tester) async {
      await pumpTree(tester, const GitBranchTree(branches: null));

      expect(find.text('未找到分支'), findsOneWidget);
      expect(find.text('分支树'), findsOneWidget);
    });

    testWidgets('分支列表全空（含空名）→ 空态文案', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            local: const [GitBranchRef(name: ''), GitBranchRef(name: '  ')],
            remote: const [],
          ),
        ),
      );

      expect(find.text('未找到分支'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('git-branch-mode-segmented')),
        findsNothing,
      );
    });

    testWidgets('errorMessage 非空且列表为空 → 错误条 + 重试回调', (tester) async {
      var reloads = 0;
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(),
          errorMessage: '工作区不可用',
          onReload: () => reloads++,
        ),
      );

      expect(find.text('工作区不可用'), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.exclamationmark_triangle),
        findsOneWidget,
      );
      expect(find.text('未找到分支'), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(reloads, 1);
    });

    testWidgets('errorMessage 非空但列表非空 → 正常渲染分支（错误条让位）', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [GitBranchRef(name: 'main')],
          ),
          errorMessage: '陈旧错误',
          onReload: () {},
        ),
      );

      expect(find.text('陈旧错误'), findsNothing);
      expect(find.byKey(nodeKey('main')), findsOneWidget);
    });

    testWidgets('错误条：无 onReload → 不渲染重试按钮', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(),
          errorMessage: '加载失败',
        ),
      );

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('错误条浅色：文案用 statusRedText；非运行态按钮用 userDetail', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(),
          errorMessage: '网络错误',
          onReload: () {},
        ),
      );

      final context = tester.element(find.text('网络错误'));
      expect(
        tester.widget<Text>(find.text('网络错误')).style?.color,
        statusRedText.resolveFrom(context),
      );
      final retry = tester.widget<Text>(find.text('重试'));
      expect(retry.style?.color, LightSurfaces.userDetail);
      expect(
        tester
            .widget<CupertinoButton>(
              find.ancestor(
                of: find.text('重试'),
                matching: find.byType(CupertinoButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('错误条：isActionRunning → 重试按钮禁用 + 文案次要色', (tester) async {
      var reloads = 0;
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(),
          errorMessage: '网络错误',
          isActionRunning: true,
          onReload: () => reloads++,
        ),
      );

      final button = tester.widget<CupertinoButton>(
        find.ancestor(
          of: find.text('重试'),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(
        tester.widget<Text>(find.text('重试')).style?.color,
        LightSurfaces.textSecondary,
      );

      await tester.tap(find.text('重试'), warnIfMissed: false);
      await tester.pump();
      expect(reloads, 0);
    });

    testWidgets('错误条暗色：重试文案颜色交回主题（null）', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(),
          errorMessage: '网络错误',
          onReload: () {},
        ),
        brightness: Brightness.dark,
      );

      expect(tester.widget<Text>(find.text('重试')).style?.color, isNull);
      expect(find.text('网络错误'), findsOneWidget);
    });
  });

  group('GitBranchTree 分支元数据渲染', () {
    testWidgets('完整元数据：短 SHA 截断 7 位 + 说明 + 相对时间 + 上游 + 领先落后', (
      tester,
    ) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [
              GitBranchRef(
                name: 'main',
                sha: 'abcdef1234567890',
                subject: 'fix: 修复登录',
                updatedRelative: '2 小时前',
                upstream: 'origin/main',
                ahead: 2,
                behind: 3,
              ),
            ],
          ),
          currentBranch: 'main',
        ),
      );

      expect(find.text('main'), findsOneWidget);
      expect(find.text('abcdef1'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('abcdef1')).style?.fontFamily,
        'monospace',
      );
      expect(find.text('fix: 修复登录'), findsOneWidget);
      expect(find.text('2 小时前'), findsOneWidget);
      expect(find.text('origin/main'), findsOneWidget);
      expect(find.text('↑2'), findsOneWidget);
      expect(find.text('↓3'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.cloud), findsOneWidget);
    });

    testWidgets('SHA 长度 ≤ 7 → 原样显示（不截断）', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(local: const [GitBranchRef(name: 'dev', sha: 'abc1234')]),
        ),
      );

      expect(find.text('abc1234'), findsOneWidget);
      expect(find.text('abc123'), findsNothing);
    });

    testWidgets('SHA 为空串 → 不渲染 SHA 徽标，其余元数据照常', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            local: const [
              GitBranchRef(name: 'dev', sha: '', subject: 'chore: y'),
            ],
          ),
        ),
      );

      final mono = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.style?.fontFamily == 'monospace');
      expect(mono, isEmpty);
      expect(find.text('chore: y'), findsOneWidget);
      expect(find.text('dev'), findsOneWidget);
    });

    testWidgets('无 sha / 无说明 / 无相对时间 → 第二行整体不渲染', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(branches: branchesOf(local: const [GitBranchRef(name: 'dev')])),
      );

      expect(find.text('dev'), findsOneWidget);
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => t.style?.fontFamily == 'monospace'),
        isEmpty,
      );
      expect(find.byIcon(CupertinoIcons.cloud), findsNothing);
    });

    testWidgets('暗色：SHA 徽标 / 提交说明 / 相对时间走暗色专用色', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [
              GitBranchRef(
                name: 'main',
                sha: 'abcdef1234567890',
                subject: 'fix: 修复登录',
                updatedRelative: '2 小时前',
              ),
            ],
          ),
          currentBranch: 'main',
        ),
        brightness: Brightness.dark,
      );

      final context = tester.element(find.byType(GitBranchTree));
      final badge = containerAround(tester, 'abcdef1');
      final decoration = badge.decoration as BoxDecoration;
      expect(
        decoration.color,
        CupertinoColors.secondarySystemBackground.resolveFrom(context),
      );
      expect(
        decoration.border?.top.color,
        CupertinoColors.separator.resolveFrom(context),
      );
      expect(decoration.border?.top.width, 0.5);

      expect(
        tester.widget<Text>(find.text('abcdef1')).style?.color,
        secondaryText.resolveFrom(context),
      );
      expect(
        tester.widget<Text>(find.text('fix: 修复登录')).style?.color,
        secondaryText.resolveFrom(context),
      );
      expect(
        tester.widget<Text>(find.text('2 小时前')).style?.color,
        secondaryText.resolveFrom(context),
      );
    });

    testWidgets('暗色空态：主/次文案均用暗色专用色', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(branches: branchesOf()),
        brightness: Brightness.dark,
      );

      final context = tester.element(find.byType(GitBranchTree));
      expect(find.text('未找到分支'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('未找到分支')).style?.color,
        secondaryText.resolveFrom(context),
      );
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((w) => w.painter is BranchRailPainter),
        isEmpty,
      );
    });

    testWidgets('浅色空态：文案用 LightSurfaces.textSecondary', (tester) async {
      await pumpTree(tester, GitBranchTree(branches: branchesOf()));

      expect(
        tester.widget<Text>(find.text('未找到分支')).style?.color,
        LightSurfaces.textSecondary,
      );
    });

    testWidgets('upstream 为纯空白 → 不渲染上游 chip', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            local: const [GitBranchRef(name: 'dev', upstream: '   ')],
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.cloud), findsNothing);
      expect(find.text('   '), findsNothing);
    });

    testWidgets('ahead / behind 为 null 或 0 → 不渲染箭头', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            local: const [
              GitBranchRef(name: 'a', ahead: 0, behind: 0),
              GitBranchRef(name: 'b', ahead: null, behind: null),
            ],
          ),
        ),
      );

      expect(find.textContaining('↑'), findsNothing);
      expect(find.textContaining('↓'), findsNothing);
    });

    testWidgets('name 为 null 或纯空白的分支被过滤', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'dev',
            local: const [
              GitBranchRef(name: null),
              GitBranchRef(name: '   '),
              GitBranchRef(name: 'dev'),
            ],
          ),
        ),
      );

      expect(find.byKey(nodeKey('dev')), findsOneWidget);
      expect(find.text('本地 (1)'), findsOneWidget);
      // 空名分支不会落到「未知分支」兜底文案。
      expect(find.text('未知分支'), findsNothing);
    });
  });

  group('GitBranchTree 当前分支判定与切换按钮', () {
    testWidgets('currentBranch 为 null → 回退 branches.current 高亮', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'dev',
            local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
          ),
        ),
      );

      final devNode = tester.widget<Container>(find.byKey(nodeKey('dev')));
      expect(devNode.color, LightSurfaces.selection);
      expect(find.byKey(switchKey('dev')), findsNothing);
      expect(find.byKey(switchKey('main')), findsOneWidget);
      expect(tester.widget<Container>(find.byKey(nodeKey('main'))).color, isNull);
    });

    testWidgets('currentBranch 显式传入优先于 branches.current', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
          ),
          currentBranch: 'dev',
        ),
      );

      expect(
        tester.widget<Container>(find.byKey(nodeKey('dev'))).color,
        LightSurfaces.selection,
      );
      expect(find.byKey(switchKey('main')), findsOneWidget);
    });

    testWidgets('current 与任何分支都不匹配 → 全部显示切换按钮、无高亮', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'gone',
            local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
          ),
        ),
      );

      expect(find.byKey(nodeKey('main')), findsOneWidget);
      expect(find.byKey(nodeKey('dev')), findsOneWidget);
      expect(find.byKey(switchKey('main')), findsOneWidget);
      expect(find.byKey(switchKey('dev')), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsNothing);
    });

    testWidgets('点击切换按钮 → onCheckout 收到分支名', (tester) async {
      String? tapped;
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
          ),
          onCheckout: (name) => tapped = name,
        ),
      );

      await tester.tap(find.byKey(switchKey('dev')));
      await tester.pump();

      expect(tapped, 'dev');
    });

    testWidgets('onCheckout 为 null → 点击切换按钮不抛错', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
          ),
        ),
      );

      await tester.tap(find.byKey(switchKey('dev')));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('isActionRunning → 切换按钮禁用且文案次要色', (tester) async {
      var taps = 0;
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
          ),
          isActionRunning: true,
          onCheckout: (_) => taps++,
        ),
      );

      final button = tester.widget<CupertinoButton>(
        find.byKey(switchKey('dev')),
      );
      expect(button.onPressed, isNull);
      final label = tester.widget<Text>(
        find.descendant(
          of: find.byKey(switchKey('dev')),
          matching: find.text('切换'),
        ),
      );
      expect(label.style?.color, LightSurfaces.textSecondary);

      await tester.tap(find.byKey(switchKey('dev')), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('暗色：切换按钮底色用系统蓝半透明 + 文案 activeBlue', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
          ),
        ),
        brightness: Brightness.dark,
      );

      final context = tester.element(find.byKey(nodeKey('dev')));
      final button = tester.widget<CupertinoButton>(find.byKey(switchKey('dev')));
      expect(
        button.color,
        CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12),
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(switchKey('dev')),
                matching: find.text('切换'),
              ),
            )
            .style
            ?.color,
        CupertinoColors.activeBlue.resolveFrom(context),
      );
    });
  });

  group('GitBranchTree 上游 chip 双主题', () {
    GitBranchTree treeWithUpstream() => GitBranchTree(
      branches: branchesOf(
        current: 'main',
        local: const [
          GitBranchRef(name: 'main', upstream: 'origin/main'),
        ],
      ),
      currentBranch: 'main',
    );

    testWidgets('浅色：chip 底色 page + 发丝边框，cloud 图标/文本用 textSecondary', (
      tester,
    ) async {
      await pumpTree(tester, treeWithUpstream());

      final chip = containerAround(tester, 'origin/main');
      final decoration = chip.decoration as BoxDecoration;
      expect(decoration.color, LightSurfaces.page);
      expect(decoration.border?.top.color, LightSurfaces.cardBorder);
      expect(decoration.border?.top.width, 0.5);

      expect(
        tester.widget<Icon>(find.byIcon(CupertinoIcons.cloud)).color,
        LightSurfaces.textSecondary,
      );
      expect(
        tester.widget<Text>(find.text('origin/main')).style?.color,
        LightSurfaces.textSecondary,
      );
    });

    testWidgets('暗色：chip 底色 systemGrey5 无边框，图标/文本用 secondaryText', (
      tester,
    ) async {
      await pumpTree(tester, treeWithUpstream(), brightness: Brightness.dark);

      final context = tester.element(find.byKey(nodeKey('main')));
      final chip = containerAround(tester, 'origin/main');
      final decoration = chip.decoration as BoxDecoration;
      expect(decoration.color, CupertinoColors.systemGrey5.resolveFrom(context));
      expect(decoration.border, isNull);

      expect(
        tester.widget<Icon>(find.byIcon(CupertinoIcons.cloud)).color,
        secondaryText.resolveFrom(context),
      );
      expect(
        tester.widget<Text>(find.text('origin/main')).style?.color,
        secondaryText.resolveFrom(context),
      );
    });
  });

  group('GitBranchTree 本地 / 远程分段', () {
    GitBranchTree treeWithBothModes() => GitBranchTree(
      branches: branchesOf(
        current: 'main',
        local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
        remote: const [
          GitBranchRef(
            name: 'origin/main',
            upstream: 'main',
            ahead: 1,
            behind: 1,
            sha: 'deadbeefcafe',
          ),
          GitBranchRef(name: 'origin/feature'),
        ],
      ),
      currentBranch: 'main',
      onCheckout: (_) {},
    );

    testWidgets('分段计数与远程分段渲染：远程无切换按钮、不参与当前高亮', (tester) async {
      await pumpTree(tester, treeWithBothModes());

      expect(find.text('本地 (2)'), findsOneWidget);
      expect(find.text('远程 (2)'), findsOneWidget);
      expect(find.byKey(nodeKey('main')), findsOneWidget);

      await tester.tap(find.text('远程 (2)'));
      await tester.pumpAndSettle();

      expect(find.byKey(nodeKey('origin/main')), findsOneWidget);
      expect(find.byKey(nodeKey('origin/feature')), findsOneWidget);
      expect(find.byKey(nodeKey('main')), findsNothing);
      // 远程分支永远不给切换按钮，也永远不算「当前分支」。
      expect(find.byKey(switchKey('origin/main')), findsNothing);
      expect(
        tester.widget<Container>(find.byKey(nodeKey('origin/main'))).color,
        isNull,
      );
      expect(find.text('当前'), findsNothing);
      expect(find.text('origin/main'), findsOneWidget);
      expect(find.text('↑1'), findsOneWidget);
      expect(find.text('deadbee'), findsOneWidget);
    });

    testWidgets('分段可切回本地', (tester) async {
      await pumpTree(tester, treeWithBothModes());

      await tester.tap(find.text('远程 (2)'));
      await tester.pumpAndSettle();
      expect(find.byKey(nodeKey('origin/feature')), findsOneWidget);

      await tester.tap(find.text('本地 (2)'));
      await tester.pumpAndSettle();
      expect(find.byKey(nodeKey('main')), findsOneWidget);
      expect(find.byKey(nodeKey('origin/feature')), findsNothing);
      expect(
        tester.widget<Container>(find.byKey(nodeKey('main'))).color,
        LightSurfaces.selection,
      );
    });

    testWidgets('仅远程有数据：默认本地分段 → 空态（分段控件仍显示）', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            remote: const [GitBranchRef(name: 'origin/main')],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('git-branch-mode-segmented')),
        findsOneWidget,
      );
      expect(find.text('本地 (0)'), findsOneWidget);
      expect(find.text('远程 (1)'), findsOneWidget);
      expect(find.text('未找到分支'), findsOneWidget);

      await tester.tap(find.text('远程 (1)'));
      await tester.pumpAndSettle();
      expect(find.byKey(nodeKey('origin/main')), findsOneWidget);
      expect(find.text('未找到分支'), findsNothing);
    });
  });

  group('BranchRailPainter', () {
    testWidgets('paint 覆盖首/末/当前/衍生全部组合且落成真实位图', (tester) async {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      for (final isFirst in [true, false]) {
        for (final isLast in [true, false]) {
          for (final isCurrent in [true, false]) {
            for (final isBranchOff in [true, false]) {
              BranchRailPainter(
                isCurrent: isCurrent,
                isFirst: isFirst,
                isLast: isLast,
                laneColor: const Color(0xFF007AFF),
                isBranchOff: isBranchOff,
                trackColor: const Color(0xFFC6C6C8),
              ).paint(canvas, const Size(28, 48));
            }
          }
        }
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(28, 48);

      expect(image.width, 28);
      expect(image.height, 48);
      image.dispose();
      picture.dispose();
    });

    test('shouldRepaint：六字段任一变化即重绘', () {
      const base = BranchRailPainter(
        isCurrent: false,
        isFirst: false,
        isLast: false,
        laneColor: Color(0xFF007AFF),
        isBranchOff: false,
        trackColor: Color(0xFFC6C6C8),
      );

      expect(
        base.shouldRepaint(
          const BranchRailPainter(
            isCurrent: false,
            isFirst: false,
            isLast: false,
            laneColor: Color(0xFF007AFF),
            isBranchOff: false,
            trackColor: Color(0xFFC6C6C8),
          ),
        ),
        isFalse,
      );
      expect(
        base.shouldRepaint(
          const BranchRailPainter(
            isCurrent: true,
            isFirst: false,
            isLast: false,
            laneColor: Color(0xFF007AFF),
            isBranchOff: false,
            trackColor: Color(0xFFC6C6C8),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const BranchRailPainter(
            isCurrent: false,
            isFirst: false,
            isLast: false,
            laneColor: Color(0xFF34C759),
            isBranchOff: false,
            trackColor: Color(0xFFC6C6C8),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const BranchRailPainter(
            isCurrent: false,
            isFirst: false,
            isLast: false,
            laneColor: Color(0xFF007AFF),
            isBranchOff: false,
            trackColor: Color(0xFF000000),
          ),
        ),
        isTrue,
      );
    });

    testWidgets('树内每个分支行都挂上真实 painter 实例', (tester) async {
      await pumpTree(
        tester,
        GitBranchTree(
          branches: branchesOf(
            current: 'main',
            local: const [GitBranchRef(name: 'main'), GitBranchRef(name: 'dev')],
          ),
          currentBranch: 'main',
        ),
      );

      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<BranchRailPainter>()
          .toList();

      expect(painters, hasLength(2));
      expect(painters.first.isCurrent, isTrue);
      expect(painters.first.isFirst, isTrue);
      expect(painters.first.isLast, isFalse);
      expect(painters.first.isBranchOff, isFalse);
      expect(painters.last.isCurrent, isFalse);
      expect(painters.last.isLast, isTrue);
      expect(painters.last.isBranchOff, isTrue);
    });
  });
}
