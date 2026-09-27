import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';
import 'package:hermes_ui/app/shell/sidebar_secondary_tools.dart';
import 'package:hermes_ui/app/shell/sidebar_tools_list.dart';
import 'package:hermes_ui/app/shell/sidebar_utility_toolbar.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/layout_tokens.dart';
import 'package:hermes_ui/app/widgets/icon_hover_disk.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// G3 落地试点守卫：侧栏三个工具行部件的「图标钮 hover 28 圆底」+ 光标语义。
///
/// 契约：`sketches/wide-global-rules-decision.html` §G3 —— 图标钮 hover 给
/// 28×28 **圆**底（`rgba(120,120,128,.16)`，与 L2 选中底同值）；可点 → 手型、
/// 禁用 → 禁止符；选中态优先（选中不叠圆底）；所有改动只在宽屏分支生效。
class _EmptyTasksController extends TasksController {
  @override
  Future<TasksState> build() async {
    ref.watch(tasksApiFactoryProvider);
    return const TasksState(jobs: <CronJob>[]);
  }
}

class _EmptyProjectsController extends ProjectsController {
  @override
  Future<List<ProjectSummary>> build() async => const [];
}

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

const String _titleAlpha = 'Alpha 当前会话';
const String _titleBeta = 'Beta 会话语';

ProviderContainer _container() {
  final api = FakeSessionListApi(
    sessions: const [
      SessionSummary(sessionId: 'alpha', title: _titleAlpha),
      SessionSummary(sessionId: 'beta', title: _titleBeta),
    ],
  );
  return ProviderContainer(
    overrides: [
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectsProvider.overrideWith(_EmptyProjectsController.new),
      tasksControllerProvider.overrideWith(_EmptyTasksController.new),
    ],
  );
}

Future<void> _pumpWidget(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(),
      child: CupertinoApp(
        locale: const Locale('zh'),
        localizationsDelegates: _delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: buildCupertinoTheme(Brightness.light),
        home: CupertinoPageScaffold(child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 设定视口宽度后挂 [child]（宽度决定宽/窄分支；[childWidth] 用来把部件塞进窄盒）。
Future<void> _pumpAt(
  WidgetTester tester, {
  required double width,
  required Widget child,
  double? childWidth,
}) async {
  tester.view.physicalSize = Size(width, 800.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await _pumpWidget(
    tester,
    childWidth == null
        ? child
        : Center(child: SizedBox(width: childWidth, child: child)),
  );
}

/// 建一条鼠标指针。
///
/// **一个测试只建一条**：`PointerAddedEvent` 必须与 `PointerRemovedEvent` 配对
/// （`MouseTracker._shouldMarkStateDirty` 的硬断言），同一测试里反复
/// `createGesture(...).addPointer()` 会直接踩断言 —— 挪动鼠标改用同一条 gesture。
Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  return gesture;
}

/// 把鼠标移到 [target] 并推进一帧（悬停生效）。
Future<void> _hover(WidgetTester tester, TestGesture mouse, Offset target) async {
  await mouse.moveTo(target);
  await tester.pump();
}

/// [scope] **内部**的圆底画布 painter（工具行是「圆底包图标」⇒ 圆底在行内）。
CustomPainter? _diskIn(WidgetTester tester, Finder scope) {
  final finder = find.descendant(
    of: scope,
    matching: find.byKey(kIconHoverDiskPaintKey),
  );
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<CustomPaint>(finder.first).painter;
}

/// [inner] **外圈**的圆底画布 painter（图标钮是「圆底包整颗按钮」⇒ 圆底是按钮的父层）。
CustomPainter? _diskAbove(WidgetTester tester, Finder inner) {
  final finder = find.ancestor(
    of: inner,
    matching: find.byKey(kIconHoverDiskPaintKey),
  );
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<CustomPaint>(finder.first).painter;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('侧栏工具行（SidebarToolsList）', () {
    const rowKey = ValueKey('sidebar-tool-tasks');

    testWidgets('宽屏：悬停整行 → 图标后出现 28 圆底（位置正对图标）', (tester) async {
      await _pumpAt(
        tester,
        width: 1100.0,
        child: const SizedBox(
          width: 320.0,
          child: SidebarToolsList(currentLocation: '/'),
        ),
      );
      final row = find.byKey(rowKey);
      final diskFinder = find.descendant(
        of: row,
        matching: find.byKey(kIconHoverDiskPaintKey),
      );

      expect(_diskIn(tester, row), isNull, reason: '未悬停无圆底');
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(row));
      expect(_diskIn(tester, row), isNotNull, reason: '悬停整行应点亮图标圆底');

      // 圆底画布正对图标（不是行中央）。
      final iconCenter = tester.getCenter(
        find.descendant(of: row, matching: find.byType(Icon)),
      );
      final diskCenter = tester.getCenter(diskFinder);
      expect(diskCenter.dx, moreOrLessEquals(iconCenter.dx, epsilon: 0.01));
      expect(diskCenter.dy, moreOrLessEquals(iconCenter.dy, epsilon: 0.01));

      // 移开 → 撤销。
      await _hover(tester, mouse, const Offset(2.0, 2.0));
      expect(_diskIn(tester, row), isNull);
    });

    testWidgets('选中优先：当前页行的悬停不叠圆底', (tester) async {
      await _pumpAt(
        tester,
        width: 1100.0,
        child: const SizedBox(
          width: 320.0,
          child: SidebarToolsList(currentLocation: '/tasks'),
        ),
      );
      final row = find.byKey(rowKey);
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(row));
      expect(_diskIn(tester, row), isNull, reason: '选中态已有灰底 + 蓝字，不许再叠 16% 圆底');
    });

    testWidgets('窄屏（340）：悬停整行不出现圆底', (tester) async {
      await _pumpAt(
        tester,
        width: 340.0,
        child: const SizedBox(
          width: 320.0,
          child: SidebarToolsList(currentLocation: '/'),
        ),
      );
      final row = find.byKey(rowKey);
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(row));
      expect(_diskIn(tester, row), isNull);
    });
  });

  group('底部工具条 / 次级图标', () {
    testWidgets('宽屏：SidebarUtilityToolbar 图标钮悬停出现圆底', (tester) async {
      await _pumpAt(
        tester,
        width: 1100.0,
        childWidth: 520.0,
        child: const SidebarUtilityToolbar(currentLocation: '/tasks'),
      );
      final button = find.byKey(const ValueKey('sidebar-utility-settings'));

      expect(_diskAbove(tester, button), isNull);
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(button));
      expect(_diskAbove(tester, button), isNotNull);
    });

    testWidgets('窄屏：SidebarUtilityToolbar 悬停不出现圆底', (tester) async {
      await _pumpAt(
        tester,
        width: 560.0,
        childWidth: 520.0,
        child: const SidebarUtilityToolbar(currentLocation: '/tasks'),
      );
      final button = find.byKey(const ValueKey('sidebar-utility-settings'));
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(button));
      expect(_diskAbove(tester, button), isNull);
    });

    testWidgets('宽屏：SidebarSecondaryTools 图标悬停出现圆底（选中行不叠）', (tester) async {
      await _pumpAt(
        tester,
        width: 1100.0,
        childWidth: 320.0,
        child: const Align(
          alignment: Alignment.centerRight,
          child: SidebarSecondaryTools(currentLocation: '/'),
        ),
      );
      // 首个次级图标（默认顺序里的工作区类入口）。
      final icons = find.byType(SidebarSecondaryTools);
      expect(icons, findsOneWidget);
      final firstButton = find
          .descendant(of: icons, matching: find.byType(CupertinoButton))
          .first;

      expect(_diskAbove(tester, firstButton), isNull);
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(firstButton));
      expect(_diskAbove(tester, firstButton), isNotNull);
    });
  });

  group('G3 光标语义（只在宽屏分支生效）', () {
    testWidgets('宽屏：侧栏会话行 = 手型', (tester) async {
      tester.view.physicalSize = const Size(1280.0, 800.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpWidget(
        tester,
        const SessionSidebar(currentLocation: '/tasks'),
      );

      final row = find.byKey(const ValueKey('session-row-alpha'));
      final regions = tester.widgetList<MouseRegion>(
        find.descendant(of: row, matching: find.byType(MouseRegion)),
      );
      final rowRegion = regions.firstWhere(
        (region) => region.onEnter != null || region.onExit != null,
        orElse: () => throw StateError('会话行外层 MouseRegion 不见了'),
      );
      // MouseRegion 的 cursor 是**未解析**的属性：这里断言拿到的正是 G3 令牌，
      // 再解析一次确认它在「无状态」下等价于手型。
      expect(rowRegion.cursor, same(kPointerCursor));
      expect(
        (rowRegion.cursor as WidgetStateMouseCursor).resolve(<WidgetState>{}),
        SystemMouseCursors.click,
      );
    });

    testWidgets('窄屏：会话行保持默认光标（defer），逐像素不变', (tester) async {
      // 默认测试视口 800×600 < 900 ⇒ 单栈。
      await _pumpWidget(tester, const SessionListPage());

      final row = find.byKey(const ValueKey('session-row-alpha'));
      final regions = tester.widgetList<MouseRegion>(
        find.descendant(of: row, matching: find.byType(MouseRegion)),
      );
      final rowRegion = regions.firstWhere(
        (region) => region.onEnter != null || region.onExit != null,
        orElse: () => throw StateError('会话行外层 MouseRegion 不见了'),
      );
      expect(rowRegion.cursor, MouseCursor.defer);
    });

    testWidgets('宽屏：侧栏图标钮把 kPointerCursor 交给 CupertinoButton（整颗按钮生效）', (tester) async {
      await _pumpAt(
        tester,
        width: 1100.0,
        childWidth: 520.0,
        child: const SidebarUtilityToolbar(currentLocation: '/settings'),
      );
      final button = find.byKey(const ValueKey('sidebar-utility-settings'));
      expect(
        tester.widget<CupertinoButton>(button).mouseCursor,
        same(kPointerCursor),
      );
    });

    testWidgets('包一层圆底不改按钮布局（仍铺满 Expanded 槽位，不缩回最小宽）', (tester) async {
      await _pumpAt(
        tester,
        width: 1100.0,
        childWidth: 520.0,
        child: const SidebarUtilityToolbar(currentLocation: '/tasks'),
      );
      final size = tester.getSize(
        find.byKey(const ValueKey('sidebar-utility-settings')),
      );
      // 这条守卫针对的是实现选型：圆底若用 `Stack`（默认 loose fit）包按钮，
      // 会把 Expanded 的紧约束放开 ⇒ 按钮缩回自身最小宽 40、命中区跟着缩水。
      // 现用 `CustomPaint`（proxy box）约束原样透传 ⇒ 仍铺满槽位（≈520/N）。
      expect(size.width, greaterThan(60.0), reason: '被包住的按钮不许缩回 40');
      expect(size.height, 32.0);
    });
  });
}
