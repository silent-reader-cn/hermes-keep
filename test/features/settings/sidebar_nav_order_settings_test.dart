import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/sidebar_nav_order.dart';
import 'package:hermes_ui/features/settings/sidebar_nav_order_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #154：「侧栏导航入口」设置分组的交互守卫。
///
/// 只测**这一个分组**（独立挂载），不拉整张设置页 —— 分组自身行为完整可验，
/// 且不受设置页其它 provider 的网络行为干扰。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: SingleChildScrollView(child: SidebarNavOrderSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认渲染：两区标题 + 全部入口行都出现', (tester) async {
    await pumpSection(tester);

    // 两区小标题
    expect(find.text('侧栏最上方'), findsOneWidget);
    expect(find.text('侧栏右下角'), findsOneWidget);

    // 全部可配置入口各有一行
    for (final id in SidebarNavOrder.knownIds) {
      expect(
        find.byKey(ValueKey('settings-nav-order-$id')),
        findsOneWidget,
        reason: '入口 $id 应有设置行',
      );
    }
  });

  testWidgets('上移按钮把入口在区内前移一位', (tester) async {
    await pumpSection(tester);

    // 顶部默认 [new_session, tasks, ...] → 把 tasks 上移
    await tester.tap(find.byKey(const ValueKey('settings-nav-order-tasks-up')));
    await tester.pumpAndSettle();

    // 用行的 y 坐标验证相对顺序（比读 provider 更贴近真实呈现）
    final newSessionY = tester
        .getTopLeft(find.byKey(const ValueKey('settings-nav-order-new_session')))
        .dy;
    final tasksY = tester
        .getTopLeft(find.byKey(const ValueKey('settings-nav-order-tasks')))
        .dy;
    expect(tasksY, lessThan(newSessionY));
  });

  testWidgets('第一项的上移按钮禁用（不可点）', (tester) async {
    await pumpSection(tester);
    final first = SidebarNavOrder.defaultTop.first;
    final button = tester.widget<CupertinoButton>(
      find.byKey(ValueKey('settings-nav-order-$first-up')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('换区按钮把入口从上方移到右下角', (tester) async {
    await pumpSection(tester);

    await tester.tap(
      find.byKey(const ValueKey('settings-nav-order-tasks-zone')),
    );
    await tester.pumpAndSettle();

    // tasks 现在应排在右下角区（y 大于右下角区标题的 y）
    final bottomLabelY = tester.getTopLeft(find.text('侧栏右下角')).dy;
    final tasksY = tester
        .getTopLeft(find.byKey(const ValueKey('settings-nav-order-tasks')))
        .dy;
    expect(tasksY, greaterThan(bottomLabelY));
  });

  testWidgets('恢复默认：换区后再点恢复，回到最初顺序', (tester) async {
    await pumpSection(tester);

    await tester.tap(
      find.byKey(const ValueKey('settings-nav-order-tasks-zone')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-nav-order-reset')));
    await tester.pumpAndSettle();

    final topLabelY = tester.getTopLeft(find.text('侧栏最上方')).dy;
    final bottomLabelY = tester.getTopLeft(find.text('侧栏右下角')).dy;
    final tasksY = tester
        .getTopLeft(find.byKey(const ValueKey('settings-nav-order-tasks')))
        .dy;
    expect(tasksY, greaterThan(topLabelY));
    expect(tasksY, lessThan(bottomLabelY));
  });

  testWidgets('动作项 new_session 也有整行控件（可排序、可换区）', (tester) async {
    await pumpSection(tester);
    expect(
      find.byKey(const ValueKey('settings-nav-order-new_session')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-nav-order-new_session-zone')),
      findsOneWidget,
    );
  });
}