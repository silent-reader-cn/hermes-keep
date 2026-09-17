import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';

import '../../helpers/contrast_utils.dart';

/// 聊天状态行的指示点/转圈色（#140 追加项）。
///
/// 这些色是**图形对象**（传达连接/等待/生成状态），按 WCAG 1.4.11 需 >= 3:1；
/// 本组令牌按文字档（>= 4.5:1）设计，用在这里是超额达标。
///
/// 背景取自实际承载面：浅色页底 #F2F2F7 / 白卡 #FFFFFF，
/// 深色纯黑 #000000 / elevation 暗卡 #1C1C1E。
const _lightSurfaces = [LightSurfaces.page, LightSurfaces.card];
const _darkSurfaces = [Color(0xFF000000), Color(0xFF1C1C1E)];

const _indicatorTokens = <String, CupertinoDynamicColor>{
  'statusGreenText': statusGreenText,
  'statusOrangeText': statusOrangeText,
  'statusYellowText': statusYellowText,
  'statusRedText': statusRedText,
};

void main() {
  group('状态行指示色：浅色档在浅色面上可读', () {
    for (final entry in _indicatorTokens.entries) {
      for (final surface in _lightSurfaces) {
        test('${entry.key} 浅色档对 ${_hex(surface)} >= 4.5:1', () {
          expect(
            contrastRatio(entry.value.color, surface),
            greaterThanOrEqualTo(4.5),
          );
        });
      }
    }
  });

  group('状态行指示色：深色档在暗面上可读', () {
    for (final entry in _indicatorTokens.entries) {
      for (final surface in _darkSurfaces) {
        test('${entry.key} 深色档对 ${_hex(surface)} >= 4.5:1', () {
          expect(
            contrastRatio(entry.value.darkColor, surface),
            greaterThanOrEqualTo(4.5),
          );
        });
      }
    }
  });

  group('状态行指示色：高对比档同样达标', () {
    test('浅色高对比档对页底 >= 4.5:1', () {
      for (final entry in _indicatorTokens.entries) {
        expect(
          contrastRatio(entry.value.highContrastColor, LightSurfaces.page),
          greaterThanOrEqualTo(4.5),
          reason: entry.key,
        );
      }
    });

    test('深色高对比档对黑底 >= 4.5:1', () {
      for (final entry in _indicatorTokens.entries) {
        expect(
          contrastRatio(
            entry.value.darkHighContrastColor,
            const Color(0xFF000000),
          ),
          greaterThanOrEqualTo(4.5),
          reason: entry.key,
        );
      }
    });
  });

  group('回归证据：原生 system 色为何不能用在这条状态行上', () {
    test('systemYellow / systemOrange / systemGreen 浅色档对页底均 < 3:1', () {
      for (final raw in [
        CupertinoColors.systemYellow,
        CupertinoColors.systemOrange,
        CupertinoColors.systemGreen,
      ]) {
        expect(
          contrastRatio(raw.color, LightSurfaces.page),
          lessThan(3),
          reason: '若此断言变红，说明 Flutter 原生色已改善，可简化状态行取色',
        );
      }
    });

    test('systemYellow 是最差的一档（< 1.5:1）', () {
      expect(
        contrastRatio(CupertinoColors.systemYellow.color, LightSurfaces.page),
        lessThan(1.5),
      );
    });
  });

  group('源码接线护栏：状态行指示色不得退回裸 system 色', () {
    final source = File('lib/features/chat/widgets/chat_message_list.dart')
        .readAsStringSync();

    for (final name in [
      'systemRed',
      'systemOrange',
      'systemYellow',
      'systemGreen',
    ]) {
      test('$name 仅作为 resolve 的 dark 档出现', () {
        expect(
          source.contains('color: CupertinoColors.$name,'),
          isFalse,
          reason: '裸 system 色在浅色面上不可读，必须经 LightSurfaces.resolve',
        );
        expect(
          source.contains('dark: CupertinoColors.$name,'),
          isTrue,
          reason: '深色档应保持原 system 色（逐字节不变）',
        );
      });
    }

    test('四个状态令牌均被状态行引用', () {
      for (final token in [
        'statusRedText',
        'statusOrangeText',
        'statusYellowText',
        'statusGreenText',
      ]) {
        expect(source.contains(token), isTrue, reason: token);
      }
    });
  });
}

String _hex(Color c) {
  final v = c.toARGB32();
  return '#${v.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}
