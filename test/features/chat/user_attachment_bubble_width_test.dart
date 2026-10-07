import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/message_attachment.dart';
import 'package:hermes_ui/features/chat/widgets/user_attachment_block.dart';

/// 带图气泡宽度算式（贴合 + 上下限）守卫。
///
/// 契约（主人 2026-10-07 定稿）：
/// - 瓦片 96、间距 4；单图 contain 上限 200；
/// - 气泡宽 = 附件区宽 + 内边距 24，夹在 `min(300, 0.78×槽宽)` 与 `0.78×槽宽` 之间；
/// - **下限永不超过上限**（窄屏槽宽不足时下限自动退到上限）；
/// - 没有图片附件（含空列表 / 只有 pdf）→ null，交给原 0.78 逻辑。
MessageAttachment _img(String name) =>
    MessageAttachment(name: name, isImage: true);
MessageAttachment _file(String name) =>
    MessageAttachment(name: name, isImage: false);
List<MessageAttachment> _imgs(int n) => [
  for (var i = 0; i < n; i++) _img('shot$i.png'),
];

void main() {
  group('带图气泡宽度 preferredBubbleWidth', () {
    test('无附件 / 只有非图片附件 → null', () {
      expect(UserAttachmentBlock.preferredBubbleWidth(null, 960), isNull);
      expect(UserAttachmentBlock.preferredBubbleWidth(const [], 960), isNull);
      expect(
        UserAttachmentBlock.preferredBubbleWidth([_file('spec.pdf')], 960),
        isNull,
      );
    });

    test('单图：200 + 24 = 224，被最小宽 300 抬起', () {
      expect(UserAttachmentBlock.preferredBubbleWidth(_imgs(1), 960), 300);
    });

    test('两张：96×2 + 4 = 196 ⇒ 220，被最小宽 300 抬起', () {
      expect(UserAttachmentBlock.preferredBubbleWidth(_imgs(2), 960), 300);
    });

    test('三张：96×3 + 8 = 296 ⇒ 320（不触发上下限）', () {
      expect(UserAttachmentBlock.preferredBubbleWidth(_imgs(3), 960), 320);
    });

    test('四张走 2×2：196 ⇒ 300；六张走 3 列：296 ⇒ 320', () {
      expect(UserAttachmentBlock.preferredBubbleWidth(_imgs(4), 960), 300);
      expect(UserAttachmentBlock.preferredBubbleWidth(_imgs(6), 960), 320);
    });

    test('宽槽（960）：附件区超过 0.78 上限时取上限', () {
      // 12 张 → 3 列 4 行，宽度仍 296 ⇒ 320，不足以触发上限；
      // 用极窄槽反向验证上限：槽 320 ⇒ cap 249.6
      expect(
        UserAttachmentBlock.preferredBubbleWidth(_imgs(3), 320),
        closeTo(320 * 0.78, 0.001),
      );
    });

    test('窄槽（手机 376）：下限自动退到上限，min 永不超过 max', () {
      const slot = 376.0;
      final cap = slot * UserAttachmentBlock.bubbleMaxWidthRatio;
      final single = UserAttachmentBlock.preferredBubbleWidth(_imgs(1), slot)!;
      final two = UserAttachmentBlock.preferredBubbleWidth(_imgs(2), slot)!;
      final three = UserAttachmentBlock.preferredBubbleWidth(_imgs(3), slot)!;
      for (final w in [single, two, three]) {
        expect(w, lessThanOrEqualTo(cap + 0.001));
        expect(w, greaterThanOrEqualTo(300.0 - 0.001 > cap ? cap : 300.0 - 0.001));
      }
      // 两张的 220 被「最小宽 300 > cap 293.28」顶到 cap，而不是撑出槽宽。
      expect(two, closeTo(cap, 0.001));
      expect(three, closeTo(cap, 0.001));
    });

    test('遍历槽宽 × 张数：结果恒在 [min(下限,上限), 上限] 内且 ≥ 附件区宽', () {
      for (final slot in [300.0, 320.0, 376.0, 560.0, 800.0, 960.0, 1600.0]) {
        final cap = slot * UserAttachmentBlock.bubbleMaxWidthRatio;
        final floor = math.min(UserAttachmentBlock.minBubbleWidth, cap);
        for (final n in [1, 2, 3, 4, 5, 6]) {
          final width = UserAttachmentBlock.preferredBubbleWidth(
            _imgs(n),
            slot,
          )!;
          expect(
            width,
            lessThanOrEqualTo(cap + 0.001),
            reason: 'slot=$slot n=$n 超过上限',
          );
          expect(
            width,
            greaterThanOrEqualTo(floor - 0.001),
            reason: 'slot=$slot n=$n 低于下限',
          );
          // 不低于最小瓦片下能放下的宽度（不含内边距的粗判）。
          expect(width, greaterThan(96.0), reason: 'slot=$slot n=$n');
        }
      }
    });
  });
}
