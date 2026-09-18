import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/widgets/focus_gated_ticker_mode.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';

/// #141 方案 A 守卫：窗口失焦时整棵子树的动画 ticker 必须被静音。
///
/// 断言口径取 `transientCallbackCount`（当前活跃 ticker 数）而不是「某个 widget
/// 在不在树上」—— 本案的实质危害不是「转圈可见」，而是「ticker 活着 → 引擎按
/// 显示器刷新率持续出帧」。实测锁屏（窗口不可见）状态下空转烧约 1 个 CPU 核与
/// ~73% GPU 3D 引擎，连续 38 分钟恒定不降。故「失焦后活跃 ticker 数为 0」是这条
/// 修复的硬约束，而 `CupertinoActivityIndicator` 内部正是
/// `SingleTickerProviderStateMixin` + `_controller.repeat()`，受 TickerMode 管控。
Future<ProviderContainer> _pump(WidgetTester tester, {Widget? child}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: FocusGatedTickerMode(
          child: child ?? const CupertinoActivityIndicator(),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;

  void bump() => setState(() => n++);

  @override
  Widget build(BuildContext context) => Text('$n');
}

void main() {
  group('FocusGatedTickerMode（#141 方案 A）', () {
    testWidgets('聚焦时子树内无限动画的 ticker 处于活跃态', (tester) async {
      await _pump(tester);
      expect(
        tester.binding.transientCallbackCount,
        greaterThan(0),
        reason: '前置：聚焦时 CupertinoActivityIndicator 的 ticker 应在跑',
      );
    });

    testWidgets('失焦时 ticker 全部被静音 —— 子树不再请求新帧', (tester) async {
      final container = await _pump(tester);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      container.read(windowFocusedProvider.notifier).state = false;
      await tester.pump();

      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: '失焦后不得有活跃 ticker —— 否则引擎按刷新率空转（本案根因）',
      );
    });

    testWidgets('重新聚焦后动画恢复（不永久静音）', (tester) async {
      final container = await _pump(tester);

      container.read(windowFocusedProvider.notifier).state = false;
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      container.read(windowFocusedProvider.notifier).state = true;
      await tester.pump();
      expect(
        tester.binding.transientCallbackCount,
        greaterThan(0),
        reason: '重新聚焦应恢复动画（TickerMode 不倒退、不丢时间）',
      );
    });

    testWidgets('静音只针对 ticker：setState 驱动的真实内容更新照常渲染', (tester) async {
      final key = GlobalKey<_CounterState>();
      final container = await _pump(tester, child: _Counter(key: key));

      container.read(windowFocusedProvider.notifier).state = false;
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      key.currentState!.bump();
      await tester.pump();

      expect(
        find.text('1'),
        findsOneWidget,
        reason: '内容更新（流式正文同路径）不得被静音影响',
      );
    });
  });
}
