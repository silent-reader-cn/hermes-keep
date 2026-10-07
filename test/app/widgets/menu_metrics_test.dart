import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/widgets/menu_metrics.dart';

/// `fitMenuHeight` 守卫：菜单**该被裁的时候不许出现半行**。
///
/// 这个纯函数是「弹层显示不完全」那一类缺陷的唯一收敛点：历史实现在选择器与
/// 上下文弹层里各自硬编码 `maxHeight: 200`，内容一超就在**行中间**切断
/// （实测：5 个工作区 × 46 的列表被切成 4 行 + 半行，第 5 项整项不可见）。
void main() {
  group('fitMenuHeight（行边界裁剪）', () {
    test('内容放得下：原样全放，不裁', () {
      // 5 个工作区双行（46）+ 分组线（0.5）+ 元操作（36）+ 卡片边框（2）
      final height = fitMenuHeight(
        rowHeights: const [46, 46, 46, 46, 46, 0.5, 36],
        available: 420,
      );
      expect(height, 46 * 5 + 0.5 + 36 + 2);
    });

    test('放不下：裁在行边界上（绝不留半行）', () {
      // 可用 200，前四行 46 × 4 = 184 + 边框 2 = 186；第五行放不下 → 停在 186.5 之前
      final height = fitMenuHeight(
        rowHeights: const [46, 46, 46, 46, 46, 0.5, 36],
        available: 200,
      );
      expect(height, 2 + 46 * 4);
      expect(height, lessThanOrEqualTo(200));
      // 关键：不是一个「4 行 + 半个第 5 行」的碎高度
      expect((height - 2) % 46, 0);
    });

    test('行高不等（分组线 0.5）：也停在整行边界', () {
      final height = fitMenuHeight(
        rowHeights: const [36, 36, 36, 0.5, 36],
        available: 100,
      );
      // 2 + 36 + 36 = 74；再加 36 会到 110 > 100 → 停在 74
      expect(height, 74);
    });

    test('连一行都放不下：退回一行（不塌成零），由外层有界约束兜底', () {
      final height = fitMenuHeight(
        rowHeights: const [46, 46],
        available: 20,
      );
      expect(height, 20);
    });

    test('空列表：只留卡片开销', () {
      expect(fitMenuHeight(rowHeights: const [], available: 100), 2);
    });
  });

  group('常量', () {
    test('上限与 adaptive popover 默认一致（420）', () {
      expect(kPopoverMenuMaxHeight, 420);
    });
  });
}
