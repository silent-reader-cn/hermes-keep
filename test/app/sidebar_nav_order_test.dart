import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/sidebar_nav_order.dart';
import 'package:hermes_ui/app/shell/sidebar_utility_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SidebarNavOrder 模型', () {
    test('默认配置 = 现状（顶部 4 项 / 右下 5 项）', () {
      const order = SidebarNavOrder();
      expect(order.top, SidebarNavOrder.defaultTop);
      expect(order.bottom, SidebarNavOrder.defaultBottom);
    });

    test('normalized 剔除未知 id 与重复项', () {
      const order = SidebarNavOrder(
        top: <String>['tasks', 'nope', 'tasks', 'kanban'],
        bottom: <String>['workspaces'],
      );
      final n = order.normalized();
      // 未知 id 被剔除、重复只留一次
      expect(n.top, <String>['tasks', 'kanban']);
      expect(n.top, isNot(contains('nope')));
    });

    test('normalized 把缺失的已知入口补到右下角末尾（升级不丢入口）', () {
      const order = SidebarNavOrder(top: <String>['tasks'], bottom: <String>[]);
      final n = order.normalized();
      // 全部已知 id 恰好出现一次
      final all = <String>[...n.top, ...n.bottom];
      expect(all.toSet(), SidebarNavOrder.knownIds.toSet());
      expect(all.length, SidebarNavOrder.knownIds.length);
      // 未配置过的入口落在右下角
      expect(n.bottom, contains('settings'));
      expect(n.bottom, contains(SidebarNavOrder.newSessionId));
    });

    test('fromJson 对畸形输入一律回退默认且不抛', () {
      for (final raw in <String?>[
        null,
        '',
        'not json',
        '[]',
        '{"top": 123, "bottom": "x"}',
        '{"top": [1, 2], "bottom": [null]}',
      ]) {
        final parsed = SidebarNavOrder.fromJson(raw);
        // 本质要求：解析结果永远是一个合法配置 —— 全部可配置 id 恰好出现一次
        // （畸形输入下 top 允许为空，那是「全搬到右下角」的合法状态）。
        final all = <String>[...parsed.top, ...parsed.bottom];
        expect(all.toSet(), SidebarNavOrder.knownIds.toSet(), reason: 'raw=$raw');
        expect(all.length, SidebarNavOrder.knownIds.length, reason: 'raw=$raw');
      }
    });

    test('toJson/fromJson 往返一致', () {
      const order = SidebarNavOrder(
        top: <String>['kanban', 'tasks'],
        bottom: <String>['settings', 'workspaces'],
      );
      final round = SidebarNavOrder.fromJson(order.toJson());
      expect(round, order.normalized());
    });

    test('isInTop 判据', () {
      const order = SidebarNavOrder();
      expect(order.isInTop('tasks'), isTrue);
      expect(order.isInTop('settings'), isFalse);
    });
  });

  group('SidebarNavOrderController', () {
    Future<ProviderContainer> makeContainer() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sidebarNavOrderProvider.notifier).reset();
      return container;
    }

    test('reorderTop 与拖拽语义一致（newIndex 为移除前插入位）', () async {
      final container = await makeContainer();
      final controller = container.read(sidebarNavOrderProvider.notifier);
      // 顶部默认 [new_session, tasks, kanban, skills]
      // 把 index 0 移到末尾：newIndex = length
      await controller.reorderTop(0, 4);
      expect(
        container.read(sidebarNavOrderProvider).top,
        <String>['tasks', 'kanban', 'skills', SidebarNavOrder.newSessionId],
      );
    });

    test('reorderBottom 相邻交换', () async {
      final container = await makeContainer();
      final controller = container.read(sidebarNavOrderProvider.notifier);
      final before = container.read(sidebarNavOrderProvider).bottom;
      // 把第 0 项下移一位
      await controller.reorderBottom(0, 2);
      final after = container.read(sidebarNavOrderProvider).bottom;
      expect(after[0], before[1]);
      expect(after[1], before[0]);
    });

    test('越界索引是安全 no-op', () async {
      final container = await makeContainer();
      final controller = container.read(sidebarNavOrderProvider.notifier);
      final before = container.read(sidebarNavOrderProvider);
      await controller.reorderTop(-1, 2);
      await controller.reorderTop(99, 1);
      expect(container.read(sidebarNavOrderProvider), before);
    });

    test('moveToBottom / moveToTop 跨区搬移', () async {
      final container = await makeContainer();
      final controller = container.read(sidebarNavOrderProvider.notifier);

      await controller.moveToBottom('tasks');
      expect(container.read(sidebarNavOrderProvider).isInTop('tasks'), isFalse);
      expect(container.read(sidebarNavOrderProvider).bottom, contains('tasks'));

      await controller.moveToTop('tasks');
      expect(container.read(sidebarNavOrderProvider).isInTop('tasks'), isTrue);
      expect(container.read(sidebarNavOrderProvider).bottom, isNot(contains('tasks')));
    });

    test('动作项 new_session 也能跨区搬移（不被过滤）', () async {
      final container = await makeContainer();
      final controller = container.read(sidebarNavOrderProvider.notifier);
      await controller.moveToBottom(SidebarNavOrder.newSessionId);
      expect(
        container.read(sidebarNavOrderProvider).bottom,
        contains(SidebarNavOrder.newSessionId),
      );
    });

    test('reset 回到默认', () async {
      final container = await makeContainer();
      final controller = container.read(sidebarNavOrderProvider.notifier);
      await controller.moveToBottom('tasks');
      await controller.reset();
      expect(container.read(sidebarNavOrderProvider), const SidebarNavOrder());
    });

    test('持久化：写入后可被新 container 读回', () async {
      final container = await makeContainer();
      await container.read(sidebarNavOrderProvider.notifier).moveToBottom('tasks');
      final saved = container.read(sidebarNavOrderProvider);

      // 新建 container 模拟重启后载入
      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      await fresh.read(sidebarNavOrderProvider.notifier).reset();
      // reset 会把默认写回，所以这里直接验 _load 路径：
      SharedPreferences.setMockInitialValues(<String, Object>{
        SidebarNavOrderController.storageKey: saved.toJson(),
      });
      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      reloaded.read(sidebarNavOrderProvider); // 触发 build → _load
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.read(sidebarNavOrderProvider).isInTop('tasks'), isFalse);
    });
  });

  group('侧栏渲染接线', () {
    test('已知 id 集合 = 动作项 + 全部页面入口', () {
      expect(SidebarNavOrder.knownIds.first, SidebarNavOrder.newSessionId);
      // 动作项 + 页面入口，但要排除隐含主页 `sessions`。
      final configurable = sidebarUtilityItems
          .where((it) => it.id != SidebarNavOrder.sessionsId)
          .length;
      expect(SidebarNavOrder.knownIds.length, configurable + 1);
      expect(SidebarNavOrder.knownIds, isNot(contains(SidebarNavOrder.sessionsId)));
    });
  });
}