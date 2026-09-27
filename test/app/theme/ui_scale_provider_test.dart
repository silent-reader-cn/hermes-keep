import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/layout_tokens.dart';
import 'package:hermes_ui/app/theme/ui_scale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HiDPI / 界面缩放（主人 2026-09-27 需求）守卫。
///
/// 覆盖三件事：① 四档位与持久化；② [applyUiScale] 的覆写语义（100% 档必须原样
/// 返回、否则会改变既有像素）；③ **A 方案** —— 宽窄屏判定跑在**缩放后**的逻辑宽上
/// （150% 下 1280 窗口 = 853 逻辑宽 < 900 => 转窄屏单栏）。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('AppUiScale 档位与持久化', () {
    test('四档系数与文案（100 / 125 / 150 / 200%）', () {
      expect(AppUiScale.values.length, 4);
      expect(
        [for (final s in AppUiScale.values) s.factor],
        [1.0, 1.25, 1.5, 2.0],
      );
      expect(
        [for (final s in AppUiScale.values) s.label],
        ['100%', '125%', '150%', '200%'],
      );
    });

    test('默认 100%（与改造前逐像素一致的前提）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(uiScaleProvider), AppUiScale.x1);
    });

    test('setScale 改状态并持久化到 prefs', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(uiScaleProvider.notifier).setScale(AppUiScale.x150);
      expect(container.read(uiScaleProvider), AppUiScale.x150);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UiScaleController.prefsKey), 'x150');
    });

    test('冷启动从 prefs 恢复', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_ui_scale': 'x2',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(uiScaleProvider); // 触发 build -> _load
      await Future<void>.delayed(Duration.zero);
      expect(container.read(uiScaleProvider), AppUiScale.x2);
    });
  });

  group('applyUiScale 覆写语义', () {
    testWidgets('100% 档原样返回（不新建 MediaQuery）', (tester) async {
      var identicalResult = false;
      const child = SizedBox.shrink();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1280, 800),
            devicePixelRatio: 2,
          ),
          child: Builder(
            builder: (context) {
              identicalResult = identical(
                applyUiScale(context, child, AppUiScale.x1),
                child,
              );
              return child;
            },
          ),
        ),
      );
      expect(
        identicalResult,
        isTrue,
        reason: '100% 档必须原样返回，否则会改变既有像素',
      );
    });

    testWidgets('缩放后 size 按系数缩小、dpr 按系数放大（物理像素不变）', (
      tester,
    ) async {
      late Size seenSize;
      late double seenDpr;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1280, 800),
            devicePixelRatio: 2,
          ),
          child: Builder(
            builder: (context) => applyUiScale(
              context,
              Builder(
                builder: (inner) {
                  final media = MediaQuery.of(inner);
                  seenSize = media.size;
                  seenDpr = media.devicePixelRatio;
                  return const SizedBox.shrink();
                },
              ),
              AppUiScale.x150,
            ),
          ),
        ),
      );
      expect(seenSize.width, closeTo(1280 / 1.5, 0.01));
      expect(seenSize.height, closeTo(800 / 1.5, 0.01));
      expect(seenDpr, closeTo(3.0, 0.01));
    });

    testWidgets('A 方案：宽窄屏判定跑在缩放后的逻辑宽上', (tester) async {
      Future<bool> wideAt(AppUiScale scale) async {
        var result = false;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(1280, 800),
              devicePixelRatio: 2,
            ),
            child: Builder(
              builder: (context) => applyUiScale(
                context,
                Builder(
                  builder: (inner) {
                    result = isWideLayout(inner);
                    return const SizedBox.shrink();
                  },
                ),
                scale,
              ),
            ),
          ),
        );
        return result;
      }

      // 1280 窗口：100% => 1280、125% => 1024（仍 >= 900）、
      // 150% => 853（< 900 转窄屏）、200% => 640。
      expect(await wideAt(AppUiScale.x1), isTrue);
      expect(await wideAt(AppUiScale.x125), isTrue);
      expect(await wideAt(AppUiScale.x150), isFalse);
      expect(await wideAt(AppUiScale.x2), isFalse);
    });
  });
}
