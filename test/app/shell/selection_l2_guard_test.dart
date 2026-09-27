import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';
import 'package:hermes_ui/app/shell/sidebar_secondary_tools.dart';
import 'package:hermes_ui/app/shell/sidebar_utility_toolbar.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// L2 选中态渲染守卫（浅色档落码；暗色档与窄屏逐像素不变）。
///
/// 契约：`sketches/selection-light-mode-proposal.html` §3/§4 ——
/// hover 底 `rgba(120,120,128,.10)`、选中底 `rgba(120,120,128,.16)` +
/// 前景（文字**和**图标）`#005FB8`、当前态另加内描边 `rgba(0,95,184,.28)`。
/// 令牌取值守卫见 `test/app/theme/selection_l2_tokens_test.dart`。
class _EmptyProjectsController extends ProjectsController {
  @override
  Future<List<ProjectSummary>> build() async => const [];
}

/// 会话行边界：alpha = 当前会话（activeChatSessionId）、beta = 选中、gamma = 普通。
const String _titleAlpha = 'Alpha 当前会话';
const String _titleBeta = 'Beta 选中会话';
const String _titleGamma = 'Gamma 悬停会话';

ProviderContainer _container() {
  final api = FakeSessionListApi(
    sessions: const [
      SessionSummary(
        sessionId: 'alpha',
        title: _titleAlpha,
        workspace: '/demo/alpha',
        messageCount: 8,
      ),
      SessionSummary(
        sessionId: 'beta',
        title: _titleBeta,
        workspace: '/demo/alpha',
        messageCount: 5,
      ),
      SessionSummary(
        sessionId: 'gamma',
        title: _titleGamma,
        workspace: '/demo/alpha',
        messageCount: 3,
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
  return container;
}

/// 宽屏（≥900）挂整条侧栏：紧凑行 + 「当前会话」高亮链路全通。
Future<ProviderContainer> _pumpSidebar(
  WidgetTester tester, {
  required Brightness brightness,
  double width = 1280.0,
  bool selectBeta = true,
}) async {
  tester.view.physicalSize = Size(width, 900.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = _container();
  container.read(activeChatSessionIdProvider.notifier).state = 'alpha';
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: const SessionSidebar(currentLocation: '/tasks'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (selectBeta) {
    // 选中态通过控制器进入（侧栏紧凑行同样吃 state.selectedSessionIds）。
    container.read(sessionListControllerProvider.notifier).toggleSelection('beta');
    await tester.pump();
  }
  return container;
}

/// 窄屏单栈：默认 800×600 视口（< kAdaptiveBreakpoint）⇒ compact == false。
Future<void> _pumpNarrow(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  final container = _container();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: const SessionListPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required Brightness brightness,
  required Widget child,
}) async {
  tester.view.physicalSize = const Size(560.0, 240.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = _container();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: CupertinoPageScaffold(
          child: Center(child: SizedBox(width: 520.0, child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('session-row-$id'));

/// 会话行自身的 [ShapeDecoration]（颜色即高亮底，暗色/窄屏皆有独立断言）。
ShapeDecoration _rowDecoration(WidgetTester tester, String id) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: _row(id),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is ShapeDecoration &&
            (widget.decoration as ShapeDecoration).color != null,
      ),
    ),
  );
  return box.decoration as ShapeDecoration;
}

RoundedSuperellipseBorder _rowShape(WidgetTester tester, String id) =>
    _rowDecoration(tester, id).shape as RoundedSuperellipseBorder;

/// 该行当前是否有着色底。
///
/// K1（主人 2026-09-27 拍板）之后，「已勾选但非当前」的行**不再有着色面**，
/// 故 `_rowDecoration` 会因 finder 匹配 0 个而抛 `Bad state: No element` ——
/// 否定断言一律改用本 helper。
bool _rowHasSurface(WidgetTester tester, String id) =>
    find
        .descendant(
          of: _row(id),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is ShapeDecoration &&
                (widget.decoration as ShapeDecoration).color != null,
          ),
        )
        .evaluate()
        .isNotEmpty;

Color? _rowTitleColor(WidgetTester tester, String id, String title) =>
    tester
        .widget<Text>(
          find.descendant(of: _row(id), matching: find.text(title)),
        )
        .style
        ?.color;

/// 全树里是否存在指定底色的行（暗色「无 hover 底」等否定断言用）。
Finder _anySurface(Color color) => find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is ShapeDecoration &&
      (widget.decoration as ShapeDecoration).color == color,
);

/// 鼠标悬停到 [id] 行（触发 MouseRegion.onEnter）。
Future<void> _hover(WidgetTester tester, String id) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(_row(id)));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('宽屏浅色 · 三态（hover / 选中 / 当前）', () {
    testWidgets('K1 · 已勾选行不再着色（无底、字不转蓝）—— 那套语言留给「当前」独占', (tester) async {
      await _pumpSidebar(tester, brightness: Brightness.light);

      // K1：宽屏多选态不再用「灰底 + 蓝字」表达「已勾选」（那是「当前查看」的
      // 语言，两者同框时无从分辨）；选择语义由左侧勾选框独立承担。
      expect(_rowHasSurface(tester, 'beta'), isFalse);
      expect(_rowTitleColor(tester, 'beta', _titleBeta), isNull);

      // 悬停已勾选行 ⇒ 只给 hover 底（不再被「选中底」压住）。
      await _hover(tester, 'beta');
      expect(_rowDecoration(tester, 'beta').color, LightSurfaces.hoverSurface);
    });

    testWidgets('高亮行内的图标（悬停出现的「⋯」）同样转 #005FB8', (tester) async {
      // 多选模式下 onActions 为 null（无「⋯」按钮），故用「当前会话」行验证
      // 图标转蓝路径：同一 l2Selection 判定驱动文字与图标。
      await _pumpSidebar(tester, brightness: Brightness.light, selectBeta: false);
      await _hover(tester, 'alpha');

      final key = find.byKey(const ValueKey('session-inline-actions-alpha'));
      expect(key, findsOneWidget);
      final icon = tester.widget<Icon>(
        find.descendant(of: key, matching: find.byType(Icon)),
      );
      expect(icon.color, LightSurfaces.selectionForeground);

      // 未高亮行的同一按钮仍是次级灰（前景不因 hover 变色）。
      final gammaAction = find.byKey(const ValueKey('session-inline-actions-gamma'));
      expect(gammaAction, findsNothing);
    });

    testWidgets('hover 行底 = rgba(120,120,128,.10)、前景不变（不转蓝）', (tester) async {
      await _pumpSidebar(tester, brightness: Brightness.light);
      expect(_anySurface(LightSurfaces.hoverSurface), findsNothing);

      await _hover(tester, 'gamma');
      expect(_rowDecoration(tester, 'gamma').color, LightSurfaces.hoverSurface);
      expect(_rowTitleColor(tester, 'gamma', _titleGamma), isNull);
      // hover 与选中的差别 = 有蓝字 vs 无蓝字。
      expect(_rowTitleColor(tester, 'gamma', _titleGamma), isNot(LightSurfaces.selectionForeground));
    });

    testWidgets('当前会话 = 选中 + 内描边 rgba(0,95,184,.28)，2px 蓝条保留', (tester) async {
      await _pumpSidebar(tester, brightness: Brightness.light);

      expect(_rowDecoration(tester, 'alpha').color, LightSurfaces.selectedSurface);
      final side = _rowShape(tester, 'alpha').side;
      expect(side.color, LightSurfaces.currentStroke);
      expect(side.width, 1.0);
      expect(_rowTitleColor(tester, 'alpha', _titleAlpha), LightSurfaces.selectionForeground);

      // 非当前行不得有描边（K1 后已勾选行连底都没有 ⇒ 直接断言无着色面）。
      expect(_rowHasSurface(tester, 'beta'), isFalse);

      // 左侧 2px 蓝条（#161 既有语义）保留。
      final bars = tester
          .widgetList<Container>(
            find.descendant(of: _row('alpha'), matching: find.byType(Container)),
          )
          .where((c) => c.constraints?.maxWidth == 2.0);
      expect(bars, isNotEmpty);
    });

    testWidgets('侧栏工具行选中态 = 中性灰底 + 蓝图标（浅色）', (tester) async {
      await _pumpSidebar(tester, brightness: Brightness.light);
      final key = find.byKey(const ValueKey('sidebar-tool-tasks'));
      expect(
        tester.widget<CupertinoButton>(key).color,
        LightSurfaces.selectedSurface,
      );
      // statusBlueText 是 CupertinoDynamicColor（浅色档 = #005FB8）⇒ 比 toARGB32。
      expect(
        tester
            .widget<Icon>(find.descendant(of: key, matching: find.byType(Icon)))
            .color!
            .toARGB32(),
        LightSurfaces.selectionForeground.toARGB32(),
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: key, matching: find.byType(Text)).first,
            )
            .style
            ?.color
            ?.toARGB32(),
        LightSurfaces.selectionForeground.toARGB32(),
      );
    });

    testWidgets('底部工具条与次级图标选中态同为 L2', (tester) async {
      await _pumpToolbar(
        tester,
        brightness: Brightness.light,
        child: const SidebarUtilityToolbar(currentLocation: '/settings'),
      );
      final utility = find.byKey(const ValueKey('sidebar-utility-settings'));
      expect(
        tester.widget<CupertinoButton>(utility).color,
        LightSurfaces.selectedSurface,
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: utility, matching: find.byType(Icon)),
            )
            .color!
            .toARGB32(),
        LightSurfaces.selectionForeground.toARGB32(),
      );

      await _pumpToolbar(
        tester,
        brightness: Brightness.light,
        child: const SidebarSecondaryTools(currentLocation: '/settings'),
      );
      final secondary = find.byKey(const ValueKey('sidebar-secondary-settings'));
      expect(
        tester.widget<CupertinoButton>(secondary).color,
        LightSurfaces.selectedSurface,
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: secondary, matching: find.byType(Icon)),
            )
            .color!
            .toARGB32(),
        LightSurfaces.selectionForeground.toARGB32(),
      );
    });
  });

  group('暗色档逐字节不变', () {
    testWidgets('已勾选行不着色（K1 与浅色一致）· 无内描边、无 hover 底；「当前」用暗色蓝前景', (tester) async {
      await _pumpSidebar(tester, brightness: Brightness.dark);

      // K1：暗色的多选行同样不着色（只靠勾选框），与浅色同一套语义。
      expect(_rowHasSurface(tester, 'beta'), isFalse);
      expect(_rowShape(tester, 'alpha').side, BorderSide.none);
      expect(_rowTitleColor(tester, 'beta', _titleBeta), isNot(LightSurfaces.selectionForeground));
      // 明暗同一套逻辑：暗色「当前」行的前景是暗色蓝 #0A84FF（不是浅色的 #005FB8）。
      expect(_rowTitleColor(tester, 'alpha', _titleAlpha)?.toARGB32(), 0xFF0A84FF);

      await _hover(tester, 'gamma');
      expect(_anySurface(LightSurfaces.hoverSurface), findsNothing);
      expect(_anySurface(LightSurfaces.selectedSurface), findsNothing);
      // 暗色非高亮行没有底色（亮色分支的 hover/pressed 底不参与）。
      expect(
        find.descendant(
          of: _row('gamma'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is ShapeDecoration &&
                (widget.decoration as ShapeDecoration).color != null,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('侧栏工具行 / 底部工具条选中态仍是 primary 12% + primaryColor', (tester) async {
      await _pumpSidebar(tester, brightness: Brightness.dark);
      final row = find.byKey(const ValueKey('sidebar-tool-tasks'));
      final primary = CupertinoTheme.of(
        tester.element(row),
      ).primaryColor;
      expect(
        tester.widget<CupertinoButton>(row).color,
        primary.withValues(alpha: 0.12),
      );
      expect(
        tester
            .widget<Icon>(find.descendant(of: row, matching: find.byType(Icon)))
            .color,
        primary,
      );

      await _pumpToolbar(
        tester,
        brightness: Brightness.dark,
        child: const SidebarUtilityToolbar(currentLocation: '/settings'),
      );
      final utility = find.byKey(const ValueKey('sidebar-utility-settings'));
      final darkPrimary = CupertinoTheme.of(
        tester.element(utility),
      ).primaryColor;
      expect(
        tester.widget<CupertinoButton>(utility).color,
        darkPrimary.withValues(alpha: 0.12),
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: utility, matching: find.byType(Icon)),
            )
            .color,
        darkPrimary,
      );
    });
  });

  group('窄屏（compact == false）逐像素不变', () {
    testWidgets('浅色长按选中仍是旧浅蓝 #E0ECFF、无内描边、文字不转蓝', (tester) async {
      await _pumpNarrow(tester, brightness: Brightness.light);
      await tester.longPress(find.text(_titleAlpha));
      await tester.pump();

      expect(_rowDecoration(tester, 'alpha').color, LightSurfaces.selection);
      expect(_rowShape(tester, 'alpha').side, BorderSide.none);
      expect(_rowTitleColor(tester, 'alpha', _titleAlpha), isNull);
      expect(_anySurface(LightSurfaces.selectedSurface), findsNothing);

      // 窄屏行不接鼠标悬停（onEnter 仅 compact 挂）⇒ 永不出现 hover 底。
      await _hover(tester, 'beta');
      expect(_anySurface(LightSurfaces.hoverSurface), findsNothing);
    });

    testWidgets('暗色窄屏选中仍是 0xFF2C2C2E', (tester) async {
      await _pumpNarrow(tester, brightness: Brightness.dark);
      await tester.longPress(find.text(_titleAlpha));
      await tester.pump();

      expect(_rowDecoration(tester, 'alpha').color, const Color(0xFF2C2C2E));
      expect(_rowShape(tester, 'alpha').side, BorderSide.none);
    });
  });
}
