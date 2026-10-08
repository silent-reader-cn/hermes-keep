import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/widgets/user_attachment_block.dart';

/// **justified 宫格（多图单行等高）排布算式守卫**（主人 2026-10-08 拍板档 4）。
///
/// 被测：`UserAttachmentBlock.justifiedRows`（纯函数，与渲染环境无关）。
///
/// 校准用比例（与截图工装 C:\tmp\attach-bubble 下的图一一对应）：
/// - 竖 3:4  = 0.75
/// - 横 4:3  = 4/3
/// - 超宽 16:9 = 16/9
/// - 方 1:1  = 1.0
///
/// 若退回「96×96 方形 cover 裁切」，本文件里「行内等高」「整行填满」「不裁切」
/// 三类判据会怎样：方形实现没有行/比例的概念（每张恒等宽 96），
/// `justifiedRows` 不存在 ⇒ 编译即红；等价地，几何守卫
/// `user_attachment_justified_test.dart` 里的「渲染宽高比 == 源图宽高比」
/// 在方形实现下实测 33% 偏差 ⇒ 红（RED 实测见交付说明）。
const double _portrait = 0.75;
const double _landscape = 4 / 3;
const double _ultrawide = 16 / 9;
const double _square = 1.0;

/// 造 N 张的混比例序列（循环 竖/横/超宽/方）。
List<double> _mixed(int count) {
  const pool = [_portrait, _landscape, _ultrawide, _square];
  return [for (var i = 0; i < count; i++) pool[i % pool.length]];
}

double _rowWidth(List<double> row) =>
    row.fold<double>(0, (total, width) => total + width) +
    UserAttachmentBlock.tileGap * (row.length - 1);

/// 行高（行内各张 width/ratio 应恒等）。
double _rowHeight(List<double> row, double ratio) => row.first / ratio;

void main() {
  const gap = UserAttachmentBlock.tileGap;
  const minHeight = UserAttachmentBlock.kJustifiedMinRowHeight;
  const maxHeight = UserAttachmentBlock.kJustifiedMaxRowHeight;

  group('justifiedRows · 行内等高 / 整行填满 / 不裁切不留白', () {
    test('3 张混比例（竖 3:4 + 横 4:3 + 超宽 16:9）：与拍板参考图一致的单行', () {
      final rows = UserAttachmentBlock.justifiedRows(const [
        _portrait,
        _landscape,
        _ultrawide,
      ], available: 296);
      expect(rows.length, 1, reason: '拍板的档 4 参考图是整行三张，不得拆行');
      final row = rows.single;
      // 行内等比 ⇒ 同一行所有瓦片共享同一个「宽 / 比例」= 行高（等高）。
      for (var i = 0; i < row.length; i++) {
        expect(
          row[i] / const [_portrait, _landscape, _ultrawide][i],
          closeTo(_rowHeight(row, _portrait), 1e-9),
          reason: '第 $i 张行高应与同行一致',
        );
      }
      // 不裁切不留白：每张宽 = 行高 × 源图宽高比（盒比 == 图比）。
      final height = _rowHeight(row, _portrait);
      expect(row[0], closeTo(height * _portrait, 1e-9));
      expect(row[1], closeTo(height * _landscape, 1e-9));
      expect(row[2], closeTo(height * _ultrawide, 1e-9));
      // 整行（含间距）严丝合缝 == 可用宽。
      expect(_rowWidth(row), closeTo(296, 1e-6));
      // 行高落在参考图实测档位（~70–75pt）。
      expect(height, closeTo(74.6, 0.5));
    });

    test('2 / 3 / 4 / 6 张混比例：每行等高、每行填满、总宽不溢出', () {
      for (final count in [2, 3, 4, 6]) {
        for (final available in [269.28, 276.0, 296.0]) {
          final ratios = _mixed(count);
          final rows = UserAttachmentBlock.justifiedRows(
            ratios,
            available: available,
          );
          expect(
            rows.fold<int>(0, (total, row) => total + row.length),
            count,
            reason: 'n=$count 不得丢图',
          );
          var index = 0;
          for (final row in rows) {
            // 行内等高（容差 0.001px：浮点即可）。
            final height = row.first / ratios[index];
            for (var i = 0; i < row.length; i++) {
              expect(
                row[i] / ratios[index + i],
                closeTo(height, 0.001),
                reason: 'n=$count available=$available 第 $i 张不等高',
              );
              expect(row[i], greaterThan(0), reason: '不得出现 0 宽瓦片');
            }
            final width = _rowWidth(row);
            expect(
              width,
              lessThanOrEqualTo(available + 1e-6),
              reason: 'n=$count available=$available 行宽溢出',
            );
            // 未被上限收高 ⇒ 必须正好填满（不留白）；收高 ⇒ 变窄居中。
            if (height < maxHeight - 1e-9) {
              expect(
                width,
                closeTo(available, 1e-6),
                reason: 'n=$count available=$available 未收高却没填满',
              );
            } else {
              expect(width, lessThanOrEqualTo(available + 1e-6));
            }
            index += row.length;
          }
        }
      }
    });

    test('6 张 4:3：不再被压成一行的 ~34pt，按下限切成多行且行高有底', () {
      final ratios = List<double>.filled(6, _landscape);
      final rows = UserAttachmentBlock.justifiedRows(ratios, available: 296);
      expect(rows.length, greaterThan(1), reason: '6 张 4:3 必须分行');
      final heights = [for (final row in rows) _rowHeight(row, _landscape)];
      debugPrint(
        'EVIDENCE 6x4:3@296 rows=${rows.length} heights='
        '${heights.map((h) => h.toStringAsFixed(2)).toList()}',
      );
      for (final height in heights) {
        expect(
          height,
          greaterThan(60),
          reason: '全挤一行只有 ≈34.5pt —— 正是主人报告的塌陷观感',
        );
        expect(height, lessThanOrEqualTo(maxHeight));
      }
      // 未被压成一行的判据：行高的最大值必须显著高于「一行装 6 张」的高度。
      final oneRowHeight = (296 - gap * 5) / (_landscape * 6);
      expect(oneRowHeight, lessThan(40));
      expect(heights.reduce((a, b) => a > b ? a : b), greaterThan(60));
    });

    test('行高上限：单张竖图/超宽图单独成行时收到 200 并整行变窄（居中留白）', () {
      // 单张竖 3:4：填满宽的自然行高 = 296 / 0.75 ≈ 394.7 > 200 ⇒ 收高，宽 150。
      final tall = UserAttachmentBlock.justifiedRows(const [
        _portrait,
      ], available: 296);
      expect(tall.length, 1);
      expect(_rowHeight(tall.single, _portrait), closeTo(maxHeight, 1e-9));
      expect(tall.single.single, closeTo(maxHeight * _portrait, 1e-9));
      expect(_rowWidth(tall.single), lessThan(296));

      // 单张超宽 16:9：自然行高 296/1.778 ≈ 166.5 ≤ 200 ⇒ 填满，不收高。
      final wide = UserAttachmentBlock.justifiedRows(const [
        _ultrawide,
      ], available: 296);
      expect(
        _rowHeight(wide.single, _ultrawide),
        closeTo(296 / _ultrawide, 1e-9),
      );
      expect(_rowWidth(wide.single), closeTo(296, 1e-6));
    });

    test('未就绪占位（比例未知 = 全 1.0）：首帧就是稳定方阵、整行铺满', () {
      final rows = UserAttachmentBlock.justifiedRows(
        List<double>.filled(3, 1.0),
        available: 296,
      );
      expect(rows, hasLength(1));
      for (final width in rows.single) {
        expect(width, closeTo((296 - gap * 2) / 3, 1e-9));
        expect(width, greaterThan(0));
      }
      expect(_rowWidth(rows.single), closeTo(296, 1e-6));
    });

    test('病态输入（0 / 负 / NaN / 无穷 / 极端比例 / 极窄可用宽）不溢出、不 NaN', () {
      final cases = <List<double>>[
        const [1e-6, 1e6, _portrait, _landscape],
        const [1000, 1000, 1000],
        const [0, -3, double.nan, double.infinity, 1.0],
        const [0.001],
        const [double.infinity],
      ];
      for (final ratios in cases) {
        for (final available in [0.5, 1.0, 4.0, 40.0, 120.0, 296.0, 1280.0]) {
          final rows = UserAttachmentBlock.justifiedRows(
            ratios,
            available: available,
          );
          expect(
            rows.fold<int>(0, (total, row) => total + row.length),
            ratios.length,
            reason: 'ratios=$ratios available=$available 丢图',
          );
          for (final row in rows) {
            for (final width in row) {
              expect(
                width.isFinite,
                isTrue,
                reason: 'ratios=$ratios available=$available 出现非有限宽',
              );
              expect(
                width,
                greaterThanOrEqualTo(0),
                reason: 'ratios=$ratios available=$available 出现负宽',
              );
            }
            expect(
              _rowWidth(row),
              lessThanOrEqualTo(available + 1e-6),
              reason: 'ratios=$ratios available=$available 行宽溢出',
            );
          }
        }
      }
    });

    test('下限/上限常量可调且自洽（min < max，均为有限正数）', () {
      expect(minHeight, greaterThan(0));
      expect(maxHeight, greaterThan(minHeight));
      expect(minHeight.isFinite && maxHeight.isFinite, isTrue);
      // 阈值可被调用方覆盖（便于按真机观感微调）：
      final relaxed = UserAttachmentBlock.justifiedRows(
        List<double>.filled(6, _landscape),
        available: 296,
        minRowHeight: 30,
      );
      expect(relaxed, hasLength(1), reason: '阈值调到 30 时 6 张应刚好挤进一行');
    });
  });
}
