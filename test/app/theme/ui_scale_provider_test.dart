import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/layout_tokens.dart';
import 'package:hermes_ui/app/theme/ui_scale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HiDPI / 界面缩放（主人 2026-09-27 需求）守卫。
///
/// 覆盖四件事：① 四档位与持久化；② [applyUiScale] 的覆写语义（100% 档必须原样
/// 返回、否则会改变既有像素）；③ **A 方案** —— 宽窄屏判定跑在**缩放后**的逻辑宽上
/// （150% 下 1280 窗口 = 853 逻辑宽 < 900 => 转窄屏单栏）；④ **真放大** ——
/// 第一版只覆写 MediaQuery 数据（size/dpr），渲染坐标系由引擎真实 dpr 决定，
/// 于是字体与所有尺寸**一个像素都没变**（主人 2026-10-08 实测反馈「百分比缩放
/// 对字体和布局无效」）。④ 用几何测量 + 命中测试把这层锁死。
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

  group('applyUiScale 真放大（缺了这层，缩放就是「数据改了但屏幕没变」）', () {
    /// 在 2560×1600 @2x（逻辑 1280×800）里量三件事：
    /// - `fill`：内层内容撑满后的**布局**尺寸（应 = 真实逻辑视口 / factor）；
    /// - `box`：固定 100×100 的盒子在**屏幕上**的矩形（含祖先 Transform）；
    /// - `text`：一段文字的屏幕矩形（字体是否真变大）；
    /// - `taps`：点屏幕四角 + 中心，命中内层内容的次数。
    Future<
      ({Size fill, Rect box, Rect text, int taps})
    >
    measure(WidgetTester tester, AppUiScale scale) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      var taps = 0;
      await tester.pumpWidget(
        CupertinoApp(
          builder: (context, child) =>
              applyUiScale(context, child ?? const SizedBox.shrink(), scale),
          home: SizedBox.expand(
            child: GestureDetector(
              key: const Key('fill'),
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: Key('box'),
                  width: 100,
                  height: 100,
                  child: Text(
                    'Ab缩放',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final logicalView = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final p in [
        const Offset(10, 10),
        Offset(logicalView.width - 10, 10),
        Offset(10, logicalView.height - 10),
        Offset(logicalView.width - 10, logicalView.height - 10),
        Offset(logicalView.width / 2, logicalView.height / 2),
      ]) {
        await tester.tapAt(p);
        await tester.pump();
      }
      return (
        fill: tester.getSize(find.byKey(const Key('fill'))),
        box: tester.getRect(find.byKey(const Key('box'))),
        text: tester.getRect(find.text('Ab缩放')),
        taps: taps,
      );
    }

    testWidgets('150%：内容按 1.5 倍画到屏幕上，内层布局仍按缩小视口', (tester) async {
      final base = await measure(tester, AppUiScale.x1);
      final scaled = await measure(tester, AppUiScale.x150);

      // ① 内层布局空间 = 真实逻辑视口 / 1.5（A 方案的判定空间就在这里）。
      expect(scaled.fill.width, closeTo(1280 / 1.5, 0.05));
      expect(scaled.fill.height, closeTo(800 / 1.5, 0.05));
      // ② 屏幕上真的变大了 1.5 倍（固定尺寸盒子 + 文字，两者都查）。
      expect(scaled.box.size.width, closeTo(150, 0.01));
      expect(scaled.box.size.height, closeTo(150, 0.01));
      expect(scaled.text.width / base.text.width, closeTo(1.5, 0.02));
      expect(scaled.text.height / base.text.height, closeTo(1.5, 0.02));
      // ③ 放大后整屏都可命中（Transform 自身尺寸 = 真实视口）。
      expect(scaled.taps, 5);
      expect(base.taps, 5);
    });

    testWidgets('125% / 200% 同口径（系数即倍数，文字物理大小随档位单调增）', (
      tester,
    ) async {
      final base = await measure(tester, AppUiScale.x1);
      final x125 = await measure(tester, AppUiScale.x125);
      final x2 = await measure(tester, AppUiScale.x2);

      expect(x125.box.size.width, closeTo(125, 0.01));
      expect(x2.box.size.width, closeTo(200, 0.01));
      expect(x125.text.height / base.text.height, closeTo(1.25, 0.02));
      expect(x2.text.height / base.text.height, closeTo(2.0, 0.02));
      expect([x125.taps, x2.taps], [5, 5]);
    });
  });
}
