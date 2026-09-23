import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/contrast_utils.dart';
import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';

class _EmptyProjectsController extends ProjectsController {
  @override
  Future<List<ProjectSummary>> build() async => const [];
}

Future<ProviderContainer> _pumpPage(
  WidgetTester tester, {
  bool sidebar = false,
}) async {
  final api = FakeSessionListApi(
    sessions: const [
      SessionSummary(
        sessionId: 'alpha',
        title: 'Alpha session',
        pinned: true,
        workspace: '/demo/alpha',
        messageCount: 8,
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectsProvider.overrideWith(_EmptyProjectsController.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        // #149：sidebar 模式改挂整条侧栏（搜索/筛选/刷新入口在品牌行内）。
        home: sidebar
            ? const SessionSidebar(currentLocation: '/')
            : const SessionListPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _rowSurface(Color color) => find.descendant(
  of: find.byKey(const ValueKey('session-row-alpha')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is ShapeDecoration &&
        (widget.decoration as ShapeDecoration).color == color,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final sidebar in [false, true]) {
    testWidgets('页面、搜索、白卡和菜单对比度（sidebar=$sidebar）', (tester) async {
      await _pumpPage(tester, sidebar: sidebar);
      expect(
        tester
            .widget<CupertinoPageScaffold>(find.byType(CupertinoPageScaffold))
            .backgroundColor,
        LightSurfaces.page,
      );
      // #149：sidebar=true 改挂 SessionSidebar，搜索框在品牌行内（先展开）；
      // sidebar=false 走默认列表页，搜索框仍在列表头部。
      final searchKey = sidebar
          ? const ValueKey('sidebar-brand-search-field')
          : const ValueKey('session-list-search');
      if (sidebar) {
        await tester.tap(find.byKey(const ValueKey('sidebar-brand-search')));
        await tester.pumpAndSettle();
      }
      final search = tester.widget<CupertinoSearchTextField>(find.byKey(searchKey));
      expect(search.decoration!.color, LightSurfaces.card);
      expect(
        contrastRatio(
          search.placeholderStyle!.color!,
          search.decoration!.color!,
        ),
        greaterThanOrEqualTo(4.5),
      );
      final card =
          tester
                  .widget<DecoratedSliver>(find.byType(DecoratedSliver))
                  .decoration
              as ShapeDecoration;
      final outline = card.shape as RoundedSuperellipseBorder;
      expect(card.color, LightSurfaces.card);
      expect(outline.side.width, inInclusiveRange(0.5, 1));
      expect(outline.side.color, LightSurfaces.cardBorder);
      final menu = tester.widget<Icon>(find.byIcon(CupertinoIcons.ellipsis));
      expect(
        contrastRatio(menu.color!, card.color!),
        greaterThanOrEqualTo(4.5),
      );
      final headerColors = tester.widgetList<ColoredBox>(
        find.descendant(
          of: find.byKey(const ValueKey('session-list-header')),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(
        headerColors.any((box) => box.color == LightSurfaces.page),
        isTrue,
      );
    });
  }

  testWidgets('按下反馈取消后复原，长按选中仍显示勾选和批量操作', (tester) async {
    final container = await _pumpPage(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Alpha session')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(_rowSurface(LightSurfaces.pressed), findsOneWidget);
    await gesture.cancel();
    await tester.pump();
    expect(_rowSurface(LightSurfaces.pressed), findsNothing);
    await tester.longPress(find.text('Alpha session'));
    await tester.pump();
    expect(_rowSurface(LightSurfaces.selection), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-archive')), findsOneWidget);
    expect(
      container
          .read(sessionListControllerProvider)
          .requireValue
          .selectedSessionIds,
      contains('alpha'),
    );
    await tester.tap(find.byKey(const ValueKey('session-list-selection-done')));
    await tester.pump();
    expect(_rowSurface(LightSurfaces.selection), findsNothing);
  });

  testWidgets('筛选弹层使用页面底、卡片边框和可见的选择/按下底色', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('session-list-filter-trigger')));
    await tester.pumpAndSettle();
    final sheet = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('session-filter-sheet')),
    );
    expect((sheet.decoration as BoxDecoration).color, LightSurfaces.page);
    final section = tester.widget<CupertinoListSection>(
      find.byKey(const ValueKey('filter-section-sessions')),
    );
    expect(section.decoration!.color, LightSurfaces.card);
    expect(section.decoration!.border!.top.color, LightSurfaces.cardBorder);
    final tiles = tester.widgetList<CupertinoListTile>(
      find.descendant(
        of: find.byKey(const ValueKey('filter-section-sessions')),
        matching: find.byType(CupertinoListTile),
      ),
    );
    expect(
      tiles.any((tile) => tile.backgroundColor == LightSurfaces.selection),
      isTrue,
    );
    expect(
      tiles.every(
        (tile) => tile.backgroundColorActivated == LightSurfaces.pressed,
      ),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('session-filter-sheet-close')));
    await tester.pumpAndSettle();
  });
}
