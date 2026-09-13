import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';
import 'package:hermes_ui/features/git/git_api.dart';
import 'package:hermes_ui/features/git/git_branch_tree.dart';
import 'package:hermes_ui/features/git/git_page.dart';

import '../../helpers/fake_git_api.dart';

GitStatus sampleStatus() {
  return GitStatus(
    isGit: true,
    branch: 'main',
    upstream: 'origin/main',
    ahead: 1,
    behind: 0,
    totals: const GitTotals(changed: 2, staged: 1, unstaged: 1),
    files: [
      GitFile(
        path: 'a.txt',
        status: 'M',
        staged: true,
        additions: 2,
        deletions: 1,
      ),
      GitFile(path: 'b.txt', status: 'M', unstaged: true, additions: 1),
    ],
  );
}

void main() {
  group('GitPage & GitBranchTree 浅深双主题回归测试', () {
    Future<void> pumpGitPage(
      WidgetTester tester,
      FakeGitApi api, {
      required Brightness brightness,
    }) async {
      await tester.pumpWidget(const SizedBox());
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const GitPage(sessionId: 's1'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            gitApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp.router(
            theme: CupertinoThemeData(brightness: brightness),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('light: GitPage 列表分区具备卡片底色与 0.5px 发丝线边框', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api, brightness: Brightness.light);

      final sections = tester.widgetList<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(sections.isNotEmpty, isTrue);
      for (final s in sections) {
        final box = s.decoration as BoxDecoration;
        expect(box.color, LightSurfaces.card);
        expect(box.border?.top.color, LightSurfaces.cardBorder);
        expect(box.border?.top.width, 0.5);
      }
    });

    testWidgets('dark: GitPage 列表分区保持原生深色样式（decoration 为 null）', (
      tester,
    ) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api, brightness: Brightness.dark);

      final sections = tester.widgetList<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(sections.isNotEmpty, isTrue);
      for (final s in sections) {
        expect(s.decoration, isNull);
      }
    });

    testWidgets(
      'light: GitPage 提交输入框占位符使用 LightSurfaces.placeholder 且保持 w400',
      (tester) async {
        final api = FakeGitApi(status: sampleStatus());
        await pumpGitPage(tester, api, brightness: Brightness.light);

        await tester.drag(
          find.byKey(const ValueKey('git-scroll')),
          const Offset(0, -400),
        );
        await tester.pump();

        final textField = tester.widget<CupertinoTextField>(
          find.byKey(const ValueKey('git-commit-message')),
        );
        expect(textField.placeholderStyle?.color, LightSurfaces.placeholder);
        expect(textField.placeholderStyle?.fontWeight, FontWeight.w400);

        final commitBtn = tester.widget<CupertinoButton>(
          find.byKey(const ValueKey('git-commit-button')),
        );
        expect(commitBtn.color, LightSurfaces.userDetail);
      },
    );

    for (final highContrast in [false, true]) {
      testWidgets('dark: 提交输入框保持 SDK 默认，highContrast=$highContrast', (
        tester,
      ) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(highContrast: highContrast);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await pumpGitPage(
          tester,
          FakeGitApi(status: sampleStatus()),
          brightness: Brightness.dark,
        );
        await tester.drag(
          find.byKey(const ValueKey('git-scroll')),
          const Offset(0, -400),
        );
        await tester.pump();

        final fieldFinder = find.byKey(const ValueKey('git-commit-message'));
        final field = tester.widget<CupertinoTextField>(fieldFinder);
        final context = tester.element(fieldFinder);
        expect(
          field.placeholderStyle,
          const CupertinoTextField().placeholderStyle!.copyWith(
            color: CupertinoColors.placeholderText.resolveFrom(context),
          ),
        );
        expect(field.decoration, const CupertinoTextField().decoration);
        expect(
          tester
              .widget<CupertinoButton>(
                find.byKey(const ValueKey('git-commit-button')),
              )
              .color,
          isNull,
        );
      });
    }

    testWidgets('light/dark: Diff 区域在浅色模式用 page，暗色模式严格保留原始 0xFFF2F2F7', (
      tester,
    ) async {
      // 浅色模式
      final lightApi = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, lightApi, brightness: Brightness.light);

      await tester.tap(find.text('a.txt'));
      await tester.pump();
      await tester.pump();

      final lightDiff = tester.widget<Container>(
        find.byKey(const ValueKey('git-diff')),
      );
      expect(lightDiff.color, LightSurfaces.page);

      // 深色模式
      final darkApi = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, darkApi, brightness: Brightness.dark);

      await tester.tap(find.text('a.txt'));
      await tester.pump();
      await tester.pump();

      final darkDiff = tester.widget<Container>(
        find.byKey(const ValueKey('git-diff')),
      );
      // 暗色逐字节硬值锁定：原始未解析动态色在底层渲染为 0xFFF2F2F7
      expect(darkDiff.color!.toARGB32(), 0xFFF2F2F7);
    });

    testWidgets('light/dark: 操作错误横幅在浅色用 tintError + 发丝边框，暗色锁死 0x1FFF3B30 无边框', (
      tester,
    ) async {
      // 浅色模式错误横幅
      final lightApi = FakeGitApi(status: sampleStatus());
      lightApi.unstageError = Exception('unstage fail');
      await pumpGitPage(tester, lightApi, brightness: Brightness.light);

      await tester.tap(find.text('取消暂存'));
      await tester.pump();
      await tester.pump();

      final lightBannerFinder = find.byKey(const ValueKey('git-action-error'));
      expect(lightBannerFinder, findsOneWidget);

      final lightBannerContainer = tester.widget<Container>(
        find
            .descendant(of: lightBannerFinder, matching: find.byType(Container))
            .first,
      );
      final lightBannerBox = lightBannerContainer.decoration as BoxDecoration;
      expect(lightBannerBox.color, LightSurfaces.tintError);
      expect(lightBannerBox.border?.top.color, LightSurfaces.cardBorder);
      expect(lightBannerBox.border?.top.width, 0.5);

      // 深色模式错误横幅
      final darkApi = FakeGitApi(status: sampleStatus());
      darkApi.unstageError = Exception('unstage fail');
      await pumpGitPage(tester, darkApi, brightness: Brightness.dark);

      await tester.tap(find.text('取消暂存'));
      await tester.pump();
      await tester.pump();

      final darkBannerFinder = find.byKey(const ValueKey('git-action-error'));
      expect(darkBannerFinder, findsOneWidget);

      final darkBannerContainer = tester.widget<Container>(
        find
            .descendant(of: darkBannerFinder, matching: find.byType(Container))
            .first,
      );
      final darkBannerBox = darkBannerContainer.decoration as BoxDecoration;
      expect(darkBannerBox.border, isNull);
      // 暗色原值锁定：systemRed 0xFFFF3B30 取 0.12 alpha 得到 0x1FFF3B30
      expect(darkBannerBox.color!.toARGB32(), 0x1FFF3B30);

      final bannerText = tester.widget<Text>(
        find.descendant(of: darkBannerFinder, matching: find.byType(Text)),
      );
      expect(bannerText.style?.color?.toARGB32(), 0xFFFF3B30);
    });

    testWidgets('light/dark: 干净工作区指示图标浅色使用 statusGreenText，暗色保持 systemGreen', (
      tester,
    ) async {
      const cleanStatus = GitStatus(isGit: true, branch: 'main');

      final lightApi = FakeGitApi(status: cleanStatus);
      await pumpGitPage(tester, lightApi, brightness: Brightness.light);

      final lightIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.checkmark_circle),
      );
      expect(lightIcon.color!.toARGB32(), statusGreenText.color.toARGB32());

      final darkApi = FakeGitApi(status: cleanStatus);
      await pumpGitPage(tester, darkApi, brightness: Brightness.dark);

      final darkIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.checkmark_circle),
      );
      expect(
        darkIcon.color!.toARGB32(),
        CupertinoColors.systemGreen.toARGB32(),
      );
    });

    testWidgets('light: GitBranchTree 当前分支高亮底色与 checkmark 满足无障碍', (
      tester,
    ) async {
      await tester.pumpWidget(
        const CupertinoApp(
          theme: CupertinoThemeData(brightness: Brightness.light),
          home: CupertinoPageScaffold(
            child: GitBranchTree(
              branches: GitBranches(
                isGit: true,
                current: 'main',
                local: [
                  GitBranchRef(name: 'main'),
                  GitBranchRef(name: 'dev'),
                ],
              ),
              currentBranch: 'main',
            ),
          ),
        ),
      );
      await tester.pump();

      final mainNode = tester.widget<Container>(
        find.byKey(const ValueKey('git-branch-node-main')),
      );
      expect(mainNode.color, LightSurfaces.selection);

      final devButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('git-branch-switch-dev')),
      );
      expect(devButton.color, LightSurfaces.selection);

      final section = tester.widget<CupertinoListSection>(
        find.byKey(const ValueKey('git-branch-tree-section')),
      );
      final sectionBox = section.decoration as BoxDecoration;
      expect(sectionBox.color, LightSurfaces.card);
      expect(sectionBox.border?.top.color, LightSurfaces.cardBorder);
      expect(sectionBox.border?.top.width, 0.5);

      // checkmark_alt 在浅色 selection 背景上升级为 statusGreenText (0xFF1E7A34)
      final checkIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.checkmark_alt),
      );
      expect(checkIcon.color!.toARGB32(), statusGreenText.color.toARGB32());
    });

    testWidgets('dark: GitBranchTree 当前分支与切换按钮保持原始系统蓝与透明度', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          theme: CupertinoThemeData(brightness: Brightness.dark),
          home: CupertinoPageScaffold(
            child: GitBranchTree(
              branches: GitBranches(
                isGit: true,
                current: 'main',
                local: [
                  GitBranchRef(name: 'main'),
                  GitBranchRef(name: 'dev'),
                ],
              ),
              currentBranch: 'main',
            ),
          ),
        ),
      );
      await tester.pump();

      final mainNode = tester.widget<Container>(
        find.byKey(const ValueKey('git-branch-node-main')),
      );
      final expectedDarkNodeColor = CupertinoColors.systemBlue
          .resolveFrom(
            tester.element(find.byKey(const ValueKey('git-branch-node-main'))),
          )
          .withValues(alpha: 0.07);
      expect(mainNode.color, expectedDarkNodeColor);

      final devButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('git-branch-switch-dev')),
      );
      final expectedDarkButtonColor = CupertinoColors.systemBlue
          .resolveFrom(
            tester.element(find.byKey(const ValueKey('git-branch-switch-dev'))),
          )
          .withValues(alpha: 0.12);
      expect(devButton.color, expectedDarkButtonColor);

      final section = tester.widget<CupertinoListSection>(
        find.byKey(const ValueKey('git-branch-tree-section')),
      );
      expect(section.decoration, isNull);

      // checkmark_alt 在暗色下保持原始 systemGreen (0xFF30D158)
      final checkIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.checkmark_alt),
      );
      expect(checkIcon.color!.toARGB32(), 0xFF30D158);
    });

    testWidgets(
      'dark: CupertinoThemeData 未指定 brightness 时通过 MediaQuery 平台回退正确解析为暗色',
      (tester) async {
        await tester.pumpWidget(
          const CupertinoApp(
            theme: CupertinoThemeData(), // brightness 未指定（null）
            home: MediaQuery(
              data: MediaQueryData(platformBrightness: Brightness.dark),
              child: CupertinoPageScaffold(
                child: GitBranchTree(
                  branches: GitBranches(
                    isGit: true,
                    current: 'main',
                    local: [
                      GitBranchRef(name: 'main'),
                      GitBranchRef(name: 'dev'),
                    ],
                  ),
                  currentBranch: 'main',
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final section = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('git-branch-tree-section')),
        );
        expect(section.decoration, isNull);

        final mainNode = tester.widget<Container>(
          find.byKey(const ValueKey('git-branch-node-main')),
        );
        expect(mainNode.color, isNot(LightSurfaces.selection));
        final expectedDarkNodeColor = CupertinoColors.systemBlue
            .resolveFrom(
              tester.element(
                find.byKey(const ValueKey('git-branch-node-main')),
              ),
            )
            .withValues(alpha: 0.07);
        expect(mainNode.color, expectedDarkNodeColor);
      },
    );

    testWidgets('dark: 高对比度模式下 GitBranchTree 仍保持原生暗色卡片及原值', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          theme: CupertinoThemeData(brightness: Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              platformBrightness: Brightness.dark,
              highContrast: true,
            ),
            child: CupertinoPageScaffold(
              child: GitBranchTree(
                branches: GitBranches(
                  isGit: true,
                  current: 'main',
                  local: [
                    GitBranchRef(name: 'main'),
                    GitBranchRef(name: 'dev'),
                  ],
                ),
                currentBranch: 'main',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final section = tester.widget<CupertinoListSection>(
        find.byKey(const ValueKey('git-branch-tree-section')),
      );
      expect(section.decoration, isNull);

      final mainNode = tester.widget<Container>(
        find.byKey(const ValueKey('git-branch-node-main')),
      );
      expect(mainNode.color, isNot(LightSurfaces.selection));
    });
  });
}
