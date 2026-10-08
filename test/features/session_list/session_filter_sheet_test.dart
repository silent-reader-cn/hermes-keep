import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  SessionSummary session(
    String id,
    String title, {
    String? sourceLabel,
    String? projectId,
    bool archived = false,
  }) {
    return SessionSummary(
      sessionId: id,
      title: title,
      sourceLabel: sourceLabel,
      projectId: projectId,
      archived: archived,
      createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 3600,
    );
  }

  Future<void> pumpList(
    WidgetTester tester,
    FakeSessionListApi api, {
    ProjectApi? projectApi,
    List<WorkspaceRoot> workspaces = const [],
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const SessionListPage())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue(
            (_) => projectApi ?? _FakeProjectApi(),
          ),
          // 宽屏两列用例需要「工作区」段出现；不覆盖时该 Provider 会走真实网络。
          if (workspaces.isNotEmpty)
            workspaceRootsProvider.overrideWith(
              (ref) => Future<List<WorkspaceRoot>>.value(workspaces),
            ),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('筛选弹窗三段等宽与选中回调', () {
    testWidgets('三段等宽：会话/渠道/项目 section 同宽同边距', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram', projectId: 'p1'),
          session('s2', '会话二', sourceLabel: 'qq', projectId: 'p2'),
        ],
      );
      final projectApi = _FakeProjectApi(
        projects: const [
          ProjectSummary(projectId: 'p1', name: '项目一'),
          ProjectSummary(projectId: 'p2', name: '项目二'),
        ],
      );
      await pumpList(tester, api, projectApi: projectApi);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sessionsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-sessions')),
      );
      final channelsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-channels')),
      );
      final projectsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-projects')),
      );

      // 三段等宽（同一横向内边距 → width 相等）
      expect(sessionsSection.width, closeTo(channelsSection.width, 1.0));
      expect(sessionsSection.width, closeTo(projectsSection.width, 1.0));
      // 同左对齐（insetGrouped 统一 16 边距）
      expect(sessionsSection.left, closeTo(channelsSection.left, 1.0));
      expect(sessionsSection.left, closeTo(projectsSection.left, 1.0));
      // 三段可见
      expect(
        find.byKey(const ValueKey('filter-section-sessions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('filter-section-channels')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('filter-section-projects')),
        findsOneWidget,
      );
    });

    testWidgets('渠道列表行：纵向单选，checkmark 选中态', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 渠道以列表行呈现，点击来源后弹层关闭并过滤
      expect(
        find.byKey(const ValueKey('filter-chip-telegram')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('filter-chip-qq')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-chip-telegram')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-filter-sheet')), findsNothing);
      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsNothing);
    });

    testWidgets('项目列表行：选中回调正确，项目筛选生效', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', projectId: 'p1'),
          session('s2', '会话二', projectId: 'p2'),
        ],
      );
      final projectApi = _FakeProjectApi(
        projects: const [
          ProjectSummary(projectId: 'p1', name: '项目一'),
          ProjectSummary(projectId: 'p2', name: '项目二'),
        ],
      );
      await pumpList(tester, api, projectApi: projectApi);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('project-chip-p1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('project-chip-p1')));
      await tester.pumpAndSettle();
      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsNothing);
    });

    testWidgets('选中态：在对应筛选下进入弹层，选中行展示 checkmark', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一', sourceLabel: 'telegram')],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-chip-telegram')));
      await tester.pumpAndSettle();

      // 再次打开应显示清除筛选项
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sheet-filter-clear')), findsOneWidget);
      // telegram 选中行应带系统 checkmark（CupertinoIcons.check_mark）
      expect(find.byIcon(CupertinoIcons.check_mark), findsWidgets);
    });

    testWidgets('去白条：弹层背景为 grouped 无底部白条残留', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一', sourceLabel: 'telegram')],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 弹层根容器存在且可滚动内容紧凑（SizedBox 8 而非 16）
      final sheet = find.byKey(const ValueKey('session-filter-sheet'));
      expect(sheet, findsOneWidget);
      final sheetBox = tester.getRect(sheet);
      // 不应占满全屏（紧凑高度）
      expect(sheetBox.height, lessThan(600));
    });

    testWidgets(
      '分割线全宽：dividerMargin 与 additionalDividerMargin 均置 0（起点=容器左缘）',
      (tester) async {
        final api = FakeSessionListApi(
          sessions: [
            session('s1', '会话一', sourceLabel: 'telegram', projectId: 'p1'),
            session('s2', '会话二', sourceLabel: 'qq', projectId: 'p2'),
          ],
        );
        final projectApi = _FakeProjectApi(
          projects: const [
            ProjectSummary(projectId: 'p1', name: '项目一'),
            ProjectSummary(projectId: 'p2', name: '项目二'),
          ],
        );
        await pumpList(tester, api, projectApi: projectApi);
        await tester.tap(
          find.byKey(const ValueKey('session-list-filter-trigger')),
        );
        await tester.pumpAndSettle();

        final sessionsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-sessions')),
        );
        final channelsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-channels')),
        );
        final projectsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-projects')),
        );

        // #28 分割线全宽：divider 起点 = dividerMargin + additionalDividerMargin
        // → 两者均置 0，分割线从容器（children group）左缘起笔全长贯穿。
        expect(sessionsSection.dividerMargin, equals(0.0));
        expect(sessionsSection.additionalDividerMargin, equals(0.0));
        expect(channelsSection.dividerMargin, equals(0.0));
        expect(channelsSection.additionalDividerMargin, equals(0.0));
        expect(projectsSection.dividerMargin, equals(0.0));
        expect(projectsSection.additionalDividerMargin, equals(0.0));
      },
    );

    testWidgets('分割线坐标探针：筛选弹层内分隔线起点 x == 容器左缘', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 渠道分区（telegram/qq 两行 → 中间有一条分隔线）
      final section = find.byKey(const ValueKey('filter-section-channels'));
      expect(section, findsOneWidget);
      // 取分区内高度 ≤ 1 的分隔线 Container（SDK 以 constraints 承载高度）
      final divider = find.descendant(
        of: section,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints != null &&
              w.constraints!.maxHeight <= 1.0 &&
              w.margin != null,
        ),
      );
      expect(divider, findsWidgets);
      final dividerRect = tester.getRect(divider.first);
      // 容器左缘 = section 整体的 left + 16（insetGrouped margin.left）
      final sectionRect = tester.getRect(section);
      final containerLeft = sectionRect.left + 16;
      expect(dividerRect.left, closeTo(containerLeft, 0.5));
    });

    testWidgets('深色模式：分割线颜色保持 CupertinoColors.separator 解析色', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _FakeProjectApi(),
            ),
          ],
          child: CupertinoApp.router(
            theme: const CupertinoThemeData(brightness: Brightness.dark),
            routerConfig: GoRouter(
              initialLocation: '/',
              routes: [
                GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final section = find.byKey(const ValueKey('filter-section-channels'));
      final expected = CupertinoColors.separator.resolveFrom(
        tester.element(section),
      );
      final divider = find.descendant(
        of: section,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints != null &&
              w.constraints!.maxHeight <= 1.0 &&
              w.margin != null,
        ),
      );
      expect(divider, findsWidgets);
      for (final e in divider.evaluate().take(10)) {
        final container = e.widget as Container;
        if (container.constraints != null &&
            container.constraints!.maxHeight <= 1.0) {
          expect(container.color, equals(expected));
        }
      }
    });
  });

  group('选中标记统一（全弹层右侧勾 · 设计稿 §4 缺陷修复）', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('全部/已归档：选中行右侧勾 + 中性灰底；未选中行无标记', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一'),
          session('s2', '已归档一', archived: true),
        ],
      );
      await pumpList(tester, api);
      await openSheet(tester);

      final allRow = find.byKey(const ValueKey('sheet-filter-all'));
      final archivedRow = find.byKey(const ValueKey('sheet-filter-archived'));
      expect(allRow, findsOneWidget);
      expect(archivedRow, findsOneWidget);

      // 「全部」默认选中 → 右侧勾（activeBlue），行底为中性灰选中底。
      final allTick = find.descendant(
        of: allRow,
        matching: find.byIcon(CupertinoIcons.check_mark),
      );
      expect(allTick, findsOneWidget);
      expect(
        tester.widget<Icon>(allTick).color,
        equals(CupertinoColors.activeBlue.resolveFrom(tester.element(allRow))),
      );
      expect(
        tester
            .widget<CupertinoListTile>(
              find.descendant(
                of: allRow,
                matching: find.byType(CupertinoListTile),
              ),
            )
            .backgroundColor,
        equals(LightSurfaces.selectedSurface),
      );

      // 「已归档」未选中 → 行内无任何图标（不再是左侧空心方框）。
      expect(
        find.descendant(of: archivedRow, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(
        tester
            .widget<CupertinoListTile>(
              find.descendant(
                of: archivedRow,
                matching: find.byType(CupertinoListTile),
              ),
            )
            .backgroundColor,
        equals(LightSurfaces.card),
      );

      // 方框 checkbox 系图标在本弹层彻底消失（同一单选语义只剩一种控件）。
      expect(find.byIcon(CupertinoIcons.checkmark_square), findsNothing);
      expect(find.byIcon(CupertinoIcons.checkmark_square_fill), findsNothing);
    });

    testWidgets('单选互斥：勾随选择移动，行底同步', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话'),
          session('s2', '已归档会话', archived: true),
        ],
      );
      await pumpList(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('sheet-filter-archived')));
      await tester.pumpAndSettle();
      await openSheet(tester);

      final allRow = find.byKey(const ValueKey('sheet-filter-all'));
      final archivedRow = find.byKey(const ValueKey('sheet-filter-archived'));
      expect(
        find.descendant(
          of: archivedRow,
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: allRow,
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsNothing,
      );

      // 反选「全部」→ 勾回到「全部」行。
      await tester.tap(allRow);
      await tester.pumpAndSettle();
      await openSheet(tester);
      expect(
        find.descendant(
          of: allRow,
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: archivedRow,
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsNothing,
      );
    });
  });

  group('宽屏筛选卡片（设计稿 §4：居中卡片 560 + 两列，窄屏反之）', () {
    /// 宽屏视口（flutter 测试默认 800×600 属窄屏，< kAdaptiveBreakpoint）。
    void useWideViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    Future<void> openFilter(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('宽屏：居中卡片 560（非贴底 sheet）、圆角 14 + 1px 描边、右上角「完成」', (
      tester,
    ) async {
      useWideViewport(tester);
      final api = FakeSessionListApi(sessions: [session('s1', '会话一')]);
      await pumpList(tester, api);
      await openFilter(tester);

      // 宽屏不再复用窄屏底部 sheet（两态是两套宿主容器，ValueKey 亦分离）。
      expect(find.byKey(const ValueKey('session-filter-sheet')), findsNothing);
      final card = find.byKey(const ValueKey('session-filter-card'));
      expect(card, findsOneWidget);

      final rect = tester.getRect(card);
      expect(rect.width, equals(560.0));
      // 1200 宽窗口水平居中：left = (1200 - 560) / 2。
      expect(rect.left, closeTo(320.0, 1.0));
      // 垂直居中（不再是贴底弹层）。
      expect(rect.center.dy, closeTo(400.0, 1.0));

      final deco = tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
      expect(deco.borderRadius, equals(BorderRadius.circular(14)));
      expect(deco.border!.top.width, equals(1.0));
      expect(deco.border!.top.color, equals(LightSurfaces.cardBorder));
      expect(
        tester
            .widget<ClipRRect>(
              find.ancestor(of: card, matching: find.byType(ClipRRect)),
            )
            .borderRadius,
        equals(BorderRadius.circular(14)),
      );

      // 右上角「完成」＝快捷关闭（文本按钮，区别于窄屏的 × 图标）。
      final done = find.byKey(const ValueKey('session-filter-sheet-close'));
      expect(done, findsOneWidget);
      expect(
        find.descendant(of: done, matching: find.text('完成')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: done, matching: find.byType(Icon)),
        findsNothing,
      );
    });

    testWidgets('两列分区：显示/会话 在左，工作区/渠道/项目 在右，一屏放完不滚动', (tester) async {
      useWideViewport(tester);
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram', projectId: 'p1'),
        ],
      );
      final projectApi = _FakeProjectApi(
        projects: const [ProjectSummary(projectId: 'p1', name: '项目一')],
      );
      await pumpList(
        tester,
        api,
        projectApi: projectApi,
        workspaces: const [
          WorkspaceRoot(path: '/projects/alpha', name: 'Alpha'),
        ],
      );
      await openFilter(tester);

      final left = find.byKey(const ValueKey('session-filter-column-settings'));
      final right = find.byKey(const ValueKey('session-filter-column-facets'));
      expect(left, findsOneWidget);
      expect(right, findsOneWidget);

      final leftRect = tester.getRect(left);
      final rightRect = tester.getRect(right);
      // 并列两列：左列整体在右列左侧，同宽同顶。
      expect(leftRect.right, lessThanOrEqualTo(rightRect.left));
      expect(leftRect.width, closeTo(rightRect.width, 1.0));
      expect(leftRect.top, closeTo(rightRect.top, 1.0));
      // 两列都在卡片内。
      final cardRect = tester.getRect(
        find.byKey(const ValueKey('session-filter-card')),
      );
      expect(leftRect.left, greaterThanOrEqualTo(cardRect.left));
      expect(rightRect.right, lessThanOrEqualTo(cardRect.right + 0.5));

      // 列归属：设置项在左，实体筛选在右。
      expect(
        find.descendant(
          of: left,
          matching: find.byKey(const ValueKey('filter-section-display')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: left,
          matching: find.byKey(const ValueKey('filter-section-sessions')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: right,
          matching: find.byKey(const ValueKey('filter-section-workspaces')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: right,
          matching: find.byKey(const ValueKey('filter-section-channels')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: right,
          matching: find.byKey(const ValueKey('filter-section-projects')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: right,
          matching: find.byKey(const ValueKey('filter-section-display')),
        ),
        findsNothing,
      );

      // 右列顺序照推荐稿：工作区 → 渠道 → 项目。
      final wsTop = tester
          .getRect(find.byKey(const ValueKey('filter-section-workspaces')))
          .top;
      final chTop = tester
          .getRect(find.byKey(const ValueKey('filter-section-channels')))
          .top;
      final prTop = tester
          .getRect(find.byKey(const ValueKey('filter-section-projects')))
          .top;
      expect(wsTop, lessThan(chTop));
      expect(chTop, lessThan(prTop));

      // 一屏放完：卡内滚动区没有可滚动余量（宽屏专属布局的收益）。
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('session-filter-card')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, 0.0);
    });

    testWidgets('宽屏：点「完成」关闭卡片；点渠道行关闭并过滤', (tester) async {
      useWideViewport(tester);
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);
      await openFilter(tester);

      await tester.tap(find.byKey(const ValueKey('session-filter-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-filter-card')), findsNothing);

      await openFilter(tester);
      await tester.tap(find.byKey(const ValueKey('filter-chip-telegram')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-filter-card')), findsNothing);
      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsNothing);
    });

    testWidgets('窄屏（< 900）仍走底部 sheet：480 限宽、顶部圆角 16、分区竖排；无宽屏卡片', (
      tester,
    ) async {
      // 不设视口 → 800×600 属窄屏。
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram', projectId: 'p1'),
          session('s2', '会话二', sourceLabel: 'qq', projectId: 'p2'),
        ],
      );
      final projectApi = _FakeProjectApi(
        projects: const [
          ProjectSummary(projectId: 'p1', name: '项目一'),
          ProjectSummary(projectId: 'p2', name: '项目二'),
        ],
      );
      await pumpList(tester, api, projectApi: projectApi);
      await openFilter(tester);

      expect(find.byKey(const ValueKey('session-filter-card')), findsNothing);
      final sheet = find.byKey(const ValueKey('session-filter-sheet'));
      expect(sheet, findsOneWidget);
      final rect = tester.getRect(sheet);
      expect(rect.width, equals(480.0));
      expect(rect.bottom, closeTo(600.0, 1.0));
      expect(
        (tester.widget<DecoratedBox>(sheet).decoration as BoxDecoration)
            .borderRadius,
        equals(const BorderRadius.vertical(top: Radius.circular(16))),
      );

      // 分区竖排：同一左缘、自上而下。
      final display = tester.getRect(
        find.byKey(const ValueKey('filter-section-display')),
      );
      final sessions = tester.getRect(
        find.byKey(const ValueKey('filter-section-sessions')),
      );
      final channels = tester.getRect(
        find.byKey(const ValueKey('filter-section-channels')),
      );
      final projects = tester.getRect(
        find.byKey(const ValueKey('filter-section-projects')),
      );
      expect(display.top, lessThan(sessions.top));
      expect(sessions.top, lessThan(channels.top));
      expect(channels.top, lessThan(projects.top));
      expect(sessions.left, closeTo(display.left, 0.5));
      expect(sessions.left, closeTo(channels.left, 0.5));

      // 标记统一在两态都生效（窄屏唯一授权的像素变化）。
      expect(find.byIcon(CupertinoIcons.checkmark_square), findsNothing);
      expect(find.byIcon(CupertinoIcons.checkmark_square_fill), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sheet-filter-all')),
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsOneWidget,
      );
    });

    /// 段卡片 1px 描边必须**真的画出来**（不被行底盖掉）。
    ///
    /// 回归背景（主人 2026-10-08 实机反馈「为什么只有两个全部项的外框正常？
    /// 其他行都没边框了」）：`CupertinoListSection.insetGrouped` 把 decoration
    /// （含描边）画在**子项之下**，而未选中行底是不透明白、又铺满整段宽度，
    /// 于是段的描边被整段盖掉 —— 整屏只剩「显示」段（该行从未传 backgroundColor）
    /// 与选中行（半透明灰底让描边透出）看得见外框。本用例直接取渲染像素，在
    /// 「未选中行」高度上量段左缘 1px 描边与行内白底的亮度差。
    testWidgets('段描边不被行底盖掉：未选中行处段左缘 1px 描边可见（像素取样）', (tester) async {
      useWideViewport(tester);
      final api = FakeSessionListApi(sessions: [session('s1', '会话一')]);
      await pumpList(
        tester,
        api,
        workspaces: const [
          WorkspaceRoot(path: '/projects/alpha', name: 'Alpha'),
        ],
      );
      await openFilter(tester);

      final frame = await captureFrame(tester);
      // 左列「会话」段：已归档行未选中（默认模式 = all）。
      expectSegStrokeVisible(
        frame,
        sectionRect: tester.getRect(
          find.byKey(const ValueKey('filter-section-sessions')),
        ),
        rowRect: tester.getRect(
          find.byKey(const ValueKey('sheet-filter-archived')),
        ),
        label: '左列「会话」段',
      );
      // 右列「工作区」段：Alpha 行未选中（选中项是「全部工作区」）。
      expectSegStrokeVisible(
        frame,
        sectionRect: tester.getRect(
          find.byKey(const ValueKey('filter-section-workspaces')),
        ),
        rowRect: tester.getRect(
          find.byKey(const ValueKey('workspace-chip-/projects/alpha')),
        ),
        label: '右列「工作区」段',
      );
    });


  });

  group('subagent 显示开关（默认关闭）', () {
    SessionSummary subagentSession(String id, String title) {
      return SessionSummary(
        sessionId: id,
        title: title,
        sourceLabel: 'Subagent',
        sourceTag: 'subagent',
        rawSource: 'subagent',
        createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 1800,
      );
    }

    // #27 症状 A 实证：服务端委派 subagent 子会话 source 四字段不保证含
    // 'subagent'（session_source 归一为 'other'），仅 title 带 Subagent 字样
    // → title-only fixture：source 无 subagent 标记，仅标题「Subagent Session」。
    SessionSummary titleOnlySubagentSession(String id, String title) {
      return SessionSummary(
        sessionId: id,
        title: title,
        sessionSource: 'other',
        createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 1800,
      );
    }

    testWidgets('默认关闭：开关为 off，Subagent 渠道不出现', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isFalse);
      // 隐藏时渠道列表剔除 Subagent，普通渠道保留
      expect(find.byKey(const ValueKey('filter-chip-Subagent')), findsNothing);
      expect(
        find.byKey(const ValueKey('filter-chip-telegram')),
        findsOneWidget,
      );
      // 列表默认不展示子代理会话
      expect(find.text('子代理会话'), findsNothing);
    });

    testWidgets('切换开关：弹层不关闭、即时生效、持久化到 SharedPreferences', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      await tester.pumpAndSettle();

      // 弹层保持打开，开关即时翻转
      expect(
        find.byKey(const ValueKey('session-filter-sheet')),
        findsOneWidget,
      );
      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isTrue);
      // Subagent 渠道恢复出现
      expect(
        find.byKey(const ValueKey('filter-chip-Subagent')),
        findsOneWidget,
      );
      // 持久化
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_list_show_subagent'), isTrue);

      // 关闭弹层后列表展示子代理会话
      await tester.tap(
        find.byKey(const ValueKey('session-filter-sheet-close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('子代理会话'), findsOneWidget);
      expect(find.text('普通会话'), findsOneWidget);
    });

    testWidgets('预置 prefs=true：打开弹层开关即开，Subagent 渠道出现', (tester) async {
      SharedPreferences.setMockInitialValues({
        'session_list_show_subagent': true,
      });
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isTrue);
      expect(
        find.byKey(const ValueKey('filter-chip-Subagent')),
        findsOneWidget,
      );
    });

    testWidgets('#27 title-only：关闭开关隐藏仅标题带 Subagent 的会话（含搜索命中）',
        (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          titleOnlySubagentSession('sub1', 'Subagent Session'),
        ],
      );
      await pumpList(tester, api);
      // 默认关闭：列表不展示标题含 Subagent 的会话
      expect(find.text('Subagent Session'), findsNothing);
      expect(find.text('普通会话'), findsOneWidget);

      // 打开开关 → 恢复显示
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session-filter-sheet-close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subagent Session'), findsOneWidget);

      // 再关回 → 隐藏
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session-filter-sheet-close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subagent Session'), findsNothing);

      // 搜索命中同样被过滤（关闭状态下）
      api.searchResults['Subagent'] = [
        titleOnlySubagentSession('sub1', 'Subagent Session'),
      ];
      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        'Subagent',
      );
      // 防抖窗口 + 搜索完成
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      await tester.pump();
      expect(find.text('Subagent Session'), findsNothing);
    });
  });
}

class _FakeProjectApi implements ProjectApi {
  _FakeProjectApi({this.projects = const []});

  List<ProjectSummary> projects;

  @override
  Future<ProjectsResponse> fetchProjects() async =>
      ProjectsResponse(projects: projects);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true, project: null);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse();

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse();
}

// ---------------------------------------------------------------------------
// 渲染像素取样（段描边守卫用）
// ---------------------------------------------------------------------------

/// 一帧画面的原始像素 + 逻辑尺寸（测试视口 1:1：物理像素 == 逻辑像素）。
typedef CapturedFrame = ({ByteData bytes, int width, int height});

/// 取当前画面（`RenderView` 根层；`pixelRatio: 1` ⇒ 1 像素 = 1 逻辑像素）。
Future<CapturedFrame> captureFrame(WidgetTester tester) async {
  final renderView = tester.binding.renderViews.first;
  final layer = renderView.debugLayer! as OffsetLayer;
  late CapturedFrame frame;
  await tester.runAsync(() async {
    final image = await layer.toImage(renderView.paintBounds, pixelRatio: 1.0);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    frame = (
      bytes: bytes,
      width: renderView.paintBounds.width.round(),
      height: renderView.paintBounds.height.round(),
    );
  });
  return frame;
}

/// (x, y) 处亮度（0-255，Rec.601 近似；渲染为不透明色，忽略 alpha）。
int frameLumAt(CapturedFrame frame, int x, int y) {
  final i = (y * frame.width + x) * 4;
  return (frame.bytes.getUint8(i) * 299 +
          frame.bytes.getUint8(i + 1) * 587 +
          frame.bytes.getUint8(i + 2) * 114) ~/
      1000;
}

/// 断言「段左缘 1px 描边」在 [rowRect] 高度上可见：描边像素至少比行内底暗
/// [minDelta]。描边被不透明白底盖掉时两者都 ≈255（差值 0）。
void expectSegStrokeVisible(
  CapturedFrame frame, {
  required Rect sectionRect,
  required Rect rowRect,
  required String label,
  int minDelta = 12,
}) {
  // 行在段内（宽屏段 margin 只有 bottom ⇒ 行左缘与段左缘同列）。
  expect(rowRect.left, greaterThanOrEqualTo(sectionRect.left - 0.5));
  final y = rowRect.center.dy.round();
  final baseX = rowRect.left.round();
  // 参考点取「行内靠左但已越过描边」的位置（+8），避开文字与勾选标记。
  final inner = frameLumAt(frame, baseX + 8, y);
  // 描边比行底更暗（浅色）或更亮（暗色）都算「可见」⇒ 取左缘内侧 3 列与行内底的
  // 最大亮度差。刻意不取 x-1：那是卡片外（遮罩/页底色），会给出假通过。
  var maxDelta = 0;
  for (final x in [baseX, baseX + 1, baseX + 2]) {
    if (x < 0 || x >= frame.width) continue;
    final d = (frameLumAt(frame, x, y) - inner).abs();
    if (d > maxDelta) maxDelta = d;
  }
  expect(
    maxDelta,
    greaterThanOrEqualTo(minDelta),
    reason: '$label：行内底亮度 $inner，段左缘内侧最大亮度差 $maxDelta ⇒ 段描边不可见',
  );
}
