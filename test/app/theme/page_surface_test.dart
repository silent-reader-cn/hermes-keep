import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/page_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 与实现同口径的 WCAG 对比度（对纯白），用于断言派生描边的可见度。
double _contrastVsWhite(Color color) {
  final argb = color.toARGB32();
  double channel(int v) {
    final s = v / 255.0;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  final lum =
      0.2126 * channel((argb >> 16) & 0xFF) +
      0.7152 * channel((argb >> 8) & 0xFF) +
      0.0722 * channel(argb & 0xFF);
  return (1.0 + 0.05) / (lum + 0.05);
}

void main() {
  // LightSurfaces 是全局令牌（250 处引用读它），测试之间必须复位，
  // 否则一个用例的选色会污染后续所有用例。
  tearDown(LightSurfaces.resetUserSurface);

  group('parseHexColor / hexFromColor「容错解析」', () {
    test('接受 #RRGGBB / RRGGBB / #RGB / 小写 / 首尾空白', () {
      expect(parseHexColor('#F2F2F2'), const Color(0xFFF2F2F2));
      expect(parseHexColor('F2F2F2'), const Color(0xFFF2F2F2));
      expect(parseHexColor('f2f2f2'), const Color(0xFFF2F2F2));
      expect(parseHexColor('  #f2f2f2  '), const Color(0xFFF2F2F2));
      // #RGB 简写按每字符重复展开。
      expect(parseHexColor('#abc'), const Color(0xFFAABBCC));
    });

    test('非法输入一律返回 null，绝不抛异常（直接接在输入框上）', () {
      for (final raw in ['', '  ', '#', '#F2F2', '#F2F2F2F2', 'GGGGGG', 'xyz']) {
        expect(parseHexColor(raw), isNull, reason: 'raw=「$raw」应判非法');
      }
    });

    test('hexFromColor 回显为 #RRGGBB', () {
      expect(hexFromColor(const Color(0xFFF2F2F2)), '#F2F2F2');
      expect(hexFromColor(const Color(0xFF0A0B0C)), '#0A0B0C');
    });
  });

  group('默认档「中性同深」（主人 2026-10-06 拍板）', () {
    test('状态默认：浅色 neutral，深色 system（不覆盖）', () {
      const state = PageSurfaceState();
      expect(state.lightPreset, PageSurfacePreset.neutral);
      expect(state.darkPreset, DarkSurfacePreset.system);
      expect(state.lightPage, const Color(0xFFF2F2F2));
      expect(state.darkPage, isNull);
    });

    test('全局令牌默认即中性同深（去掉了原 #F2F2F7 的蓝味）', () {
      expect(LightSurfaces.page.toARGB32(), 0xFFF2F2F2);
      expect(LightSurfaces.page, isNot(LightSurfaces.kLegacyIosPage));
      // 蓝通道不再高于红绿（原 #F2F2F7 的 B 比 R/G 高 5）。
      final argb = LightSurfaces.page.toARGB32();
      final b = argb & 0xFF;
      final r = (argb >> 16) & 0xFF;
      final g = (argb >> 8) & 0xFF;
      expect(b, r);
      expect(b, g);
    });

    test('默认描边对白卡与原 #CCD0DA 同档（≈1.5439:1）', () {
      final contrast = _contrastVsWhite(LightSurfaces.cardBorder);
      expect(contrast, closeTo(LightSurfaces.kBorderContrastVsWhite, 0.02));
    });

    test('深色未覆盖时回落原生分组背景（保留动态色语义）', () {
      expect(
        LightSurfaces.darkPage,
        CupertinoColors.systemGroupedBackground,
      );
      expect(LightSurfaces.hasDarkOverride, isFalse);
    });
  });

  group('applyUserSurface「页底色写入与描边派生」', () {
    test('写入后 page / cardBorder / divider 同步，且 divider 与 cardBorder 同值', () {
      LightSurfaces.applyUserSurface(light: const Color(0xFFF1EFEA));
      expect(LightSurfaces.page, const Color(0xFFF1EFEA));
      expect(LightSurfaces.divider, LightSurfaces.cardBorder);
      expect(LightSurfaces.hasLightOverride, isTrue);
    });

    test('任意档位的派生描边都保持「对白卡同档可见」', () {
      for (final preset in PageSurfacePreset.values) {
        if (preset.isCustom) continue;
        LightSurfaces.applyUserSurface(light: preset.color!);
        expect(
          _contrastVsWhite(LightSurfaces.cardBorder),
          closeTo(LightSurfaces.kBorderContrastVsWhite, 0.02),
          reason: '${preset.name} 的描边应保持与原设计同档可见度',
        );
      }
    });

    test('选「iOS 分组灰」档完整还原改造前（page #F2F2F7 + border #CCD0DA）', () {
      LightSurfaces.applyUserSurface(light: LightSurfaces.kLegacyIosPage);
      expect(LightSurfaces.page, const Color(0xFFF2F2F7));
      expect(LightSurfaces.cardBorder, const Color(0xFFCCD0DA));
    });

    test('暖色底的描边继承色相（不与底色分家）', () {
      LightSurfaces.applyUserSurface(light: const Color(0xFFF1EFEA));
      final argb = LightSurfaces.cardBorder.toARGB32();
      final r = (argb >> 16) & 0xFF;
      final b = argb & 0xFF;
      expect(r, greaterThanOrEqualTo(b), reason: '暖底 ⇒ 描边 R 通道不应低于 B');
    });

    test('暗色传 null 表示不覆盖；传值后 hasDarkOverride 为真', () {
      LightSurfaces.applyUserSurface(light: const Color(0xFFF2F2F2));
      expect(LightSurfaces.hasDarkOverride, isFalse);
      LightSurfaces.applyUserSurface(
        light: const Color(0xFFF2F2F2),
        dark: const Color(0xFF141414),
      );
      expect(LightSurfaces.hasDarkOverride, isTrue);
      expect(LightSurfaces.darkPage, const Color(0xFF141414));
    });
  });

  group('PageSurfaceController「持久化」', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('applySelection 一次性写入并落盘', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(pageSurfaceProvider.notifier);

      await controller.applySelection(
        lightPreset: PageSurfacePreset.warmNeutral,
        lightCustomHex: '#F1EFEA',
        darkPreset: DarkSurfacePreset.deeper,
        darkCustomHex: '#141414',
      );
      expect(container.read(pageSurfaceProvider).lightPreset,
          PageSurfacePreset.warmNeutral);
      // 令牌同步生效（全 App 250 处引用读的就是它）。
      expect(LightSurfaces.page, const Color(0xFFF1EFEA));
      expect(LightSurfaces.darkPage, const Color(0xFF141414));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageSurfaceController.lightKey), 'warmNeutral');
      expect(prefs.getString(PageSurfaceController.darkKey), 'deeper');
    });

    test('自定义档：合法 hex 生效，非法 hex 回落默认档（不灌脏值进令牌）', () {
      const valid = PageSurfaceState(
        lightPreset: PageSurfacePreset.custom,
        lightCustomHex: '#E8E4DC',
      );
      expect(valid.lightPage, const Color(0xFFE8E4DC));
      expect(valid.hasInvalidLightHex, isFalse);

      const invalid = PageSurfaceState(
        lightPreset: PageSurfacePreset.custom,
        lightCustomHex: 'nope',
      );
      expect(invalid.lightPage, PageSurfacePreset.neutral.color);
      expect(invalid.hasInvalidLightHex, isTrue);
    });

    test('已知档名可从磁盘还原（未知/缺失回落默认）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PageSurfaceController.lightKey: 'warmPaper',
        PageSurfaceController.lightCustomKey: '#F6F3EE',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(pageSurfaceProvider);
      // _load 是 unawaited 的，等一轮微任务让磁盘值落地。
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pageSurfaceProvider).lightPreset,
          PageSurfacePreset.warmPaper);
    });
  });
}
