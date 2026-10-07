import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_ui/app/widgets/adaptive_sliver_navigation_bar.dart';
import 'package:hermes_ui/app/widgets/narrow_navigation_dropdown.dart';
import 'package:hermes_ui/app/widgets/popover_anchor.dart';

/// 导航栏槽位「同帧重持 GlobalKey」安全性 —— 同类隐患护栏 + 锚点解算件契约。
///
/// ## 机制（与 `chat_actions_trailing_invariants_test.dart` 同源）
/// Cupertino 导航栏在路由转场时走 Hero 飞行，`_NavigationBarComponentsTransition`
/// 会直接重建用户传进 `leading` / `middle` / `trailing` 的 widget（取的是
/// `trailingKey.currentWidget.child`，框架注释明写「…still present in the widget tree
/// during the hero transitions, it would cause global key duplications」）。于是这些槽位
/// 里的**任何 GlobalKey** 都会同帧被「静态顶栏 + 飞行穿梭层」两处 build：
/// - debug：撞 `BuildOwner._debugVerifyGlobalKeyReservation`；
/// - release：`Element._retakeInactiveElement` 把元素从原处抽走 ⇒ 按钮连元素一起消失。
/// 这正是主人报的「聊天页右上角三点有时候消失、只剩左边打开项目文件夹按钮」的真凶。
///
/// ## 本文件覆盖什么
/// 全仓 GlobalKey 盘点后，除已修的 chat 顶栏外，**唯一还挂在「可能进导航栏槽位」的
/// widget 上的锚点**是 `NarrowNavigationDropdownButton._anchorKey`（会被
/// `AdaptiveSliverNavigationBar` 窄屏自绘头 / 会话列表页头渲染）。本文件：
/// 1. 窄屏自绘头（真实 `AdaptiveSliverNavigationBar`）：转场前后 ▾ 都在且可点；
/// 2. 把 ▾ 放进**真 `CupertinoNavigationBar.trailing`**（宽屏、Hero 链路）：转场不丢元素
///    —— 这条是「同类隐患」的探针：旧 GlobalKey 实现下它会红（RED 校验见提交说明）；
/// 3. 宽屏下点开菜单：锚点矩形仍精确贴住 ▾（验证 anchorRect 通路，不是屏幕原点兜底）；
/// 4. `resolvePopoverAnchorRect` 契约：命中返回真实矩形、未命中返回 null。
///
/// 注：窄屏下 `AdaptiveActionMenu.show` 走 `CupertinoActionSheet`（不需要锚点），
/// 所以第 2/3 条刻意把 ▾ 放到 ≥900 宽的 `CupertinoNavigationBar` 里跑 popover 通路。
const ValueKey<String> _dropdownKey = ValueKey('narrow-nav-dropdown');

/// 带 `CupertinoNavigationBar` 的中转页：Hero 飞行要求两端都有 transitionable 的导航栏。
Widget _stubPage() => const CupertinoPageScaffold(
  navigationBar: CupertinoNavigationBar(middle: Text('中转页')),
  child: Center(child: Text('中转页')),
);

/// 窄屏页：真 `AdaptiveSliverNavigationBar`（`titleTrailing` 内是真 ▾）。
Widget _narrowHeaderPage() => const CupertinoPageScaffold(
  child: CustomScrollView(
    slivers: [
      AdaptiveSliverNavigationBar(title: '会话'),
      SliverToBoxAdapter(child: SizedBox(height: 1600)),
    ],
  ),
);

/// 宽屏页：把 ▾ 放进真 `CupertinoNavigationBar.trailing`（Hero 链路上的槽位）。
Widget _wideNavBarPage() => const CupertinoPageScaffold(
  navigationBar: CupertinoNavigationBar(
    middle: Text('会话'),
    trailing: NarrowNavigationDropdownButton(),
  ),
  child: Center(child: Text('会话')),
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  required Size size,
  required Widget Function() page,
  String initialLocation = '/page',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/page', builder: (context, state) => page()),
      GoRoute(path: '/stub', builder: (context, state) => _stubPage()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(child: CupertinoApp.router(routerConfig: router)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}

/// 转场中间帧 + 结束帧都要求 ▾ 仍挂在自己的导航栏/头部矩形内。
void expectDropdownIntact(
  WidgetTester tester,
  String label, {
  bool requireHit = true,
}) {
  final finder = find.byKey(_dropdownKey);
  expect(finder, findsWidgets, reason: '$label：▾ 元素不应整棵消失');
  final rect = tester.getRect(finder.first);
  expect(rect.width, greaterThan(0), reason: '$label：▾ 宽度应 > 0');
  expect(rect.height, greaterThan(0), reason: '$label：▾ 高度应 > 0');
  if (requireHit) {
    expect(
      finder.hitTestable(),
      findsWidgets,
      reason: '$label：▾ 应可点（被抽走或挤出时会失去命中）',
    );
  }
}

/// ⚠️ 阳性对照页：**由页面 State 持有**的 GlobalKey，作为 slot widget 直接传进
/// `CupertinoNavigationBar.trailing` —— 这正是 chat 顶栏修复前的形状（`_actionsKey`
/// 归 `ChatPageState` 所有）。穿梭层取的是「用户传进槽位的那个 widget」，于是**同一把
/// key 实例**会同时出现在静态顶栏与飞行层 ⇒ 同帧重持。
class _LegacyKeyedPage extends StatefulWidget {
  const _LegacyKeyedPage();

  @override
  State<_LegacyKeyedPage> createState() => _LegacyKeyedPageState();
}

class _LegacyKeyedPageState extends State<_LegacyKeyedPage> {
  final GlobalKey _pageOwnedKey = GlobalKey();

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('会话'),
      trailing: KeyedSubtree(
        key: _pageOwnedKey,
        child: const Icon(CupertinoIcons.ellipsis),
      ),
    ),
    child: const Center(child: Text('会话')),
  );
}

/// 探针开关：只有显式设了环境变量才跑（阳性对照**不是**常驻断言 —— 上游 Flutter 若改了
/// Hero 组件复用策略它会失效；它是取证工具，需要时跑一次看打印）。
bool get _probeEnabled => Platform.environment['NAV_SLOT_KEY_PROBE'] == '1';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('窄屏自绘头：▾ 在真转场中不丢元素', () {
    testWidgets('会话页（AdaptiveSliverNavigationBar 窄屏）→ 中转页 → 返回', (
      tester,
    ) async {
      final router = await _pump(
        tester,
        size: const Size(430, 900),
        page: _narrowHeaderPage,
      );
      expectDropdownIntact(tester, '转场前');

      router.go('/stub');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byKey(_dropdownKey), findsNothing, reason: '已离场应卸载');

      router.go('/page');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expectDropdownIntact(tester, '返回后');
      expect(tester.takeException(), isNull, reason: '不得出现同帧重持键异常');
    });
  });

  group('宽屏放进真导航栏槽位（同类隐患探针）', () {
    testWidgets('CupertinoNavigationBar.trailing = ▾：转场中间帧与结束帧都在', (
      tester,
    ) async {
      final router = await _pump(
        tester,
        size: const Size(1280, 900),
        page: _wideNavBarPage,
      );
      expectDropdownIntact(tester, '转场前');

      router.go('/stub');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectDropdownIntact(tester, '转场中(100ms)', requireHit: false);
      await tester.pumpAndSettle();

      router.go('/page');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectDropdownIntact(tester, '返回转场中(100ms)', requireHit: false);
      await tester.pumpAndSettle();
      expectDropdownIntact(tester, '转场结束后');
      expect(tester.takeException(), isNull, reason: '不得出现同帧重持键异常');
    });

    testWidgets('宽屏点开菜单：弹层仍精确贴住 ▾（anchorRect 通路）', (tester) async {
      await _pump(tester, size: const Size(1280, 900), page: _wideNavBarPage);
      final button = tester.getRect(find.byKey(_dropdownKey).first);

      await tester.tap(find.byKey(_dropdownKey).first);
      await tester.pumpAndSettle();

      final taskItem = find.byKey(const ValueKey('narrow-nav-tasks'));
      expect(taskItem, findsOneWidget, reason: '菜单应弹出（任务入口默认可见）');
      final menu = tester.getRect(taskItem);
      // align: end ⇒ 弹层右缘应贴住锚点右缘（允许 popover 内边距/滚动条的少量偏差）。
      expect(
        (menu.right - button.right).abs(),
        lessThan(48),
        reason: '锚点没生效时会退回屏幕原点：menu=$menu button=$button',
      );
      expect(menu.top, greaterThan(button.top), reason: '默认应开在锚点下方');
    });
  });

  group('resolvePopoverAnchorRect 契约', () {
    testWidgets('命中 ValueKey → 返回真实矩形；未命中 → null', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: Container(
                  key: const ValueKey('probe-anchor'),
                  width: 120,
                  height: 44,
                  color: CupertinoColors.systemBlue,
                ),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(
        find.byKey(const ValueKey('probe-anchor')),
      );
      final overlay = Overlay.of(context);
      final rect = resolvePopoverAnchorRect(
        context,
        overlay,
        const ValueKey('probe-anchor'),
      );
      expect(rect, isNotNull);
      expect(rect!.width, 120);
      expect(rect.height, 44);
      final expected = tester.getRect(
        find.byKey(const ValueKey('probe-anchor')),
      );
      expect(rect.left, closeTo(expected.left, 0.01));
      expect(rect.top, closeTo(expected.top, 0.01));

      expect(
        resolvePopoverAnchorRect(context, overlay, const ValueKey('nope')),
        isNull,
        reason: '未命中必须返回 null（调用方放弃弹层，而不是退到屏幕原点）',
      );
    });
  });
  group('阳性对照（env 门控 NAV_SLOT_KEY_PROBE=1）', () {
    testWidgets('页面 State 持有的 GlobalKey 传进导航栏槽位 → 转场同帧重持', (tester) async {
      final router = await _pump(
        tester,
        size: const Size(1280, 900),
        page: _LegacyKeyedPage.new,
      );
      router.go('/stub');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final ex = tester.takeException();
      debugPrint(
        'NAV_SLOT_KEY_PROBE: 转入含键页/离开时 exception = '
        '${ex == null ? "null（未观测到重持，机制可能已变）" : ex.toString().split("\n").first}',
      );

      router.go('/page');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final ex2 = tester.takeException();
      debugPrint(
        'NAV_SLOT_KEY_PROBE: 回到含键页时 exception = '
        '${ex2 == null ? "null（未观测到重持，机制可能已变）" : ex2.toString().split("\n").first}',
      );
      // 取证工具：只打印不断言（避免上游变更让 CI 变红）。
    }, skip: !_probeEnabled);
  });
}
