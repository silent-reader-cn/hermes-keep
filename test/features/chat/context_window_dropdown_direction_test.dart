import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/widgets/popover_dropdown.dart';
import 'package:hermes_ui/core/models/context_window_snapshot.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/context_window_popover.dart';

import '../../helpers/fake_chat_api.dart';

/// ContextWindowPopover 两个下拉菜单「优先向上展开 + 顶部越界保护（回落向下）」
/// 的展开方向与边界 clamp 行为验证。
///
/// 菜单行高 44（CupertinoButton 默认 minimumSize）——高度估算见
/// `_estimateMenuHeight`；本组用例通过实际布局几何断言展开方向，不依赖估算值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSnapshot = ContextWindowSnapshot.fromJson({
    'context_length': 128000,
    'last_prompt_tokens': 1200,
  });

  const modelTriggerKey = ValueKey('context-popover-model-trigger');

  Widget wrap({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: CupertinoApp(
        home: CupertinoPageScaffold(child: child),
      ),
    );
  }

  List<Override> modelOverrides({required int count}) {
    final fakeChat = FakeChatApi();
    fakeChat.sessionResult = {
      'session': {'session_id': 's1', 'workspace': null},
    };
    return [
      chatApiProvider.overrideWithValue(fakeChat),
      chatAvailableModelsProvider.overrideWithValue(
        List.generate(count, (i) => 'model-v$i'),
      ),
    ];
  }

  Widget popover() {
    return ContextWindowPopover(
      sessionId: 's1',
      snapshot: testSnapshot,
      currentModel: null,
      onClose: () {},
    );
  }

  Future<void> openModelMenu(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('context-popover-model-trigger')),
    );
    await tester.pumpAndSettle();
  }

  Rect cardRect(WidgetTester tester) =>
      tester.getRect(find.byType(PopoverDropdownCard));

  group('下拉菜单展开方向（优先向上）', () {
    testWidgets('弹层居中：菜单底边紧贴触发器顶部上方 8px，向上展开', (tester) async {
      await tester.pumpWidget(
        wrap(
          overrides: modelOverrides(count: 3),
          child: Center(child: popover()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final trigger = tester.getRect(find.byKey(modelTriggerKey));
      await openModelMenu(tester);

      final card = cardRect(tester);
      // 菜单底边 = 触发器顶部 − 8（容差 2）
      expect((trigger.top - card.bottom - 8).abs(), lessThan(2.0));
      // 确实展开在触发器的上方
      expect(card.bottom, lessThan(trigger.top));
      // 顶部未越过屏幕安全区
      expect(card.top, greaterThanOrEqualTo(8));
      // 首行选项可见可点
      expect(
        find.byKey(const ValueKey('context-popover-model-model-v0')),
        findsOneWidget,
      );
    });

    testWidgets('弹层贴顶 + 菜单估算高超顶：回落向下展开（老 offset 行为）', (tester) async {
      await tester.pumpWidget(
        wrap(
          overrides: modelOverrides(count: 20),
          child: Align(alignment: Alignment.topCenter, child: popover()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final trigger = tester.getRect(find.byKey(modelTriggerKey));
      // 顶部空间不足（估算高 200 + 8 间隔后仍低于安全区顶部），应回落向下
      expect(
        trigger.top - 200 - 8,
        lessThan(8),
        reason: '前置条件：触发器上方放不下 200 高的菜单',
      );
      await openModelMenu(tester);

      final card = cardRect(tester);
      // 向下展开 = 统一口径：卡片顶边 = 触发器**底边** + 8。
      // （旧实现 `trigger.top + 38` 在触发器实高 44 时等价于「底边 − 6」，
      // 菜单会压住触发器 6pt；统一为上下各 8 后不再重叠。）
      expect((card.top - (trigger.bottom + 8)).abs(), lessThan(2.0));
      expect(card.top, greaterThanOrEqualTo(trigger.top));
      // 底部不越界（滚动兜底）
      expect(card.bottom, lessThanOrEqualTo(600));
      expect(
        find.byKey(const ValueKey('context-popover-model-model-v0')),
        findsOneWidget,
      );
    });

    testWidgets('顶部安全区 padding 抬高后触发回落（同一布局无 padding 时向上）', (
      tester,
    ) async {
      // 3 模型 + 1 默认行 = 4 行 → 估算高 4×44+2 = 178
      // 触发器贴顶约 y≈213（24 顶距 + 弹层内部偏移），
      // 无 padding：upTop ≈ 213−178−8 = 27 ≥ 8 → 向上
      // padding 44：safeTop = 52 → 27 < 52 → 回落向下
      final layout = Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: popover(),
        ),
      );

      // 无安全区：向上
      await tester.pumpWidget(
        wrap(
          overrides: modelOverrides(count: 3),
          child: layout,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final triggerNoPad = tester.getRect(find.byKey(modelTriggerKey));
      expect(triggerNoPad.top - 178 - 8, greaterThanOrEqualTo(8));
      await openModelMenu(tester);
      final cardUp = cardRect(tester);
      expect((triggerNoPad.top - cardUp.bottom - 8).abs(), lessThan(2.0));
      // 收起菜单，避免旧 OverlayEntry 的 barrier 在重 pump 后残留拦截点击
      await tester.tapAt(const Offset(100, 500));
      await tester.pumpAndSettle();

      // 同样的贴顶布局 + 系统顶部 padding 44（模拟状态栏，safeTop=52）：
      // 估算高 178 + 8 后不够 → 回落向下
      tester.view.padding = const FakeViewPadding(top: 44);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(
        wrap(
          overrides: modelOverrides(count: 3),
          child: layout,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final triggerWithPad = tester.getRect(find.byKey(modelTriggerKey));
      expect(
        triggerWithPad.top - 178 - 8,
        lessThan(44 + 8),
        reason: '前置条件：含安全区时上方放不下估算高 178 的菜单',
      );
      await openModelMenu(tester);
      final cardDown = cardRect(tester);
      expect((cardDown.top - (triggerWithPad.bottom + 8)).abs(), lessThan(2.0));
    });

    testWidgets('向下空间也不足：收紧菜单高度（保底 ≥ 一行，滚动兜底）', (tester) async {
      tester.view.physicalSize = const Size(400, 410);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrap(
          overrides: modelOverrides(count: 20),
          child: Align(alignment: Alignment.topCenter, child: popover()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final trigger = tester.getRect(find.byKey(modelTriggerKey));
      await openModelMenu(tester);

      final card = cardRect(tester);
      // 回落向下（统一口径）：卡片顶边 = 触发器底边 + 8
      expect((card.top - (trigger.bottom + 8)).abs(), lessThan(2.0));
      // 高度收紧：取该侧可用高度与上限的较小者，且**裁在行边界**上
      // （行高 44 的整数倍 + 卡片边框 2）—— 绝不出现半行。
      final availableBelow = 410 - (trigger.bottom + 8) - 8;
      expect(card.height, lessThanOrEqualTo(availableBelow));
      expect(card.height, greaterThanOrEqualTo(2 + 44));
      expect((card.height - 2) % 44, 0, reason: '切口必须落在行边界上');
      expect(card.bottom, lessThanOrEqualTo(410));
      // 内容仍可滚动访问（滚动兜底）
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('context-popover-model-model-v19')),
        -50.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('context-popover-model-model-v19')),
        findsOneWidget,
      );
    });
  });

  group('下拉菜单水平边界 clamp', () {
    testWidgets('右缘越界：菜单左缘 clamp 到 屏幕右缘 − 菜单宽', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrap(
          overrides: modelOverrides(count: 3),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 70),
              child: popover(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final trigger = tester.getRect(find.byKey(modelTriggerKey));
      // 前置条件：左缘对齐会让菜单右缘超出 320 − 8
      expect(trigger.left + 228, greaterThan(320 - 8));
      await openModelMenu(tester);

      final card = cardRect(tester);
      // 菜单左缘 = 320 − 8 − 228 = 84
      expect((card.left - (320 - 8 - 228)).abs(), lessThan(2.0));
      expect(card.left, lessThan(trigger.left));
      expect(card.right, lessThanOrEqualTo(320 - 8 + 2));
      // 纵向方向不受影响，仍向上展开
      expect((trigger.top - card.bottom - 8).abs(), lessThan(2.0));
    });
  });
}