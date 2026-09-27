import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/layout_tokens.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/widgets/icon_hover_disk.dart';

/// G3 图标钮悬停圆底守卫。
///
/// 像素级断言（把 painter 自己栅格化后读像素）—— 文本断言只能证明「有没有画」，
/// 这里连「画的是直径 28 的**圆**、不是方块」一起钉住。
const Key _boxKey = ValueKey('disk-box');

/// 圆底透明度只有 16%（alpha ≈ 41），故「可见」阈值取 4（≈10% 覆盖）就够，
/// 且足以把纯抗锯齿的 0 覆盖像素排除掉。
const int _alphaFloor = 4;

class _Probe {
  const _Probe({
    required this.bounds,
    required this.center,
    required this.corners,
  });

  /// alpha > [_alphaFloor] 的像素包围盒（= 圆的实际可见直径）。
  final Rect bounds;

  /// 画布中心像素的 straight RGBA。
  final List<int> center;

  /// 四角像素的 alpha（画布四角在圆外时必须为 0 ⇒ 是圆不是方）。
  final List<int> corners;
}

/// 把 [painter] 栅格化到 [size] 画布，读回包围盒 / 中心像素 / 四角 alpha。
///
/// **必须放在 [WidgetTester.runAsync] 里调用**：`Picture.toImage` / `toByteData`
/// 是引擎异步调用，widget 测试跑在 fake-async 区里 —— 不套 `runAsync` 的话这两个
/// Future 永不完成，用例直接挂住（实测踩过）。
Future<_Probe> _rasterize(CustomPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final w = size.width.round();
  final h = size.height.round();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final bytes = data!.buffer.asUint8List();

  int alphaAt(int x, int y) => bytes[(y * w + x) * 4 + 3];

  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (alphaAt(x, y) > _alphaFloor) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  final centerIdx = ((h ~/ 2) * w + w ~/ 2) * 4;
  final probe = _Probe(
    bounds: maxX < 0
        ? Rect.zero
        : Rect.fromLTRB(
            minX.toDouble(),
            minY.toDouble(),
            maxX + 1.0,
            maxY + 1.0,
          ),
    center: bytes.sublist(centerIdx, centerIdx + 4),
    corners: [
      alphaAt(0, 0),
      alphaAt(w - 1, 0),
      alphaAt(0, h - 1),
      alphaAt(w - 1, h - 1),
    ],
  );

  picture.dispose();
  image.dispose();
  return probe;
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  bool selected = false,
  bool? externalHover,
}) async {
  tester.view.physicalSize = Size(width, 400.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CupertinoApp(
      home: CupertinoPageScaffold(
        child: Center(
          child: IconHoverDisk(
            selected: selected,
            hovered: externalHover,
            child: const SizedBox(
              key: _boxKey,
              width: 40.0,
              height: 40.0,
              child: ColoredBox(color: Color(0xFF007AFF)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 圆底画布的 painter（null = 没画圆底）。
///
/// 窄屏透传时连画布都不存在（`IconHoverDisk` 直接返回 child）—— 那同样是
/// 「没有圆底」，故用 `evaluate().isEmpty` 兜住。
CustomPainter? _disk(WidgetTester tester) {
  final finder = find.byKey(kIconHoverDiskPaintKey);
  final matches = finder.evaluate();
  if (matches.isEmpty) {
    return null;
  }
  return tester.widget<CustomPaint>(finder).painter;
}

/// 建一条鼠标指针。
///
/// **一个测试只建一条**：`PointerAddedEvent` 必须与 `PointerRemovedEvent` 配对
/// （`MouseTracker._shouldMarkStateDirty` 的硬断言），同一测试里反复
/// `createGesture(...).addPointer()` 会直接踩断言 —— 挪动鼠标改用同一条
/// gesture 的 `moveTo`。
Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  return gesture;
}

/// 把鼠标移到 [target] 并推进一帧（悬停生效）。
Future<void> _hover(WidgetTester tester, TestGesture mouse, Offset target) async {
  await mouse.moveTo(target);
  await tester.pump();
}

void main() {
  group('宽屏（≥900）· 自接管悬停', () {
    testWidgets('悬停前无圆底 → 悬停后出现 → 移开撤销（同一 widget 的前后变化）', (tester) async {
      await _pump(tester, width: 1200.0);
      expect(_disk(tester), isNull, reason: '未悬停不该有圆底');

      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(find.byKey(_boxKey)));
      expect(_disk(tester), isNotNull, reason: '悬停应出现圆底');

      await _hover(tester, mouse, const Offset(2.0, 2.0));
      expect(_disk(tester), isNull, reason: '鼠标离开应撤掉圆底');
    });

    testWidgets('圆底几何：直径 28、正中、是圆不是方、色同 L2 选中底', (tester) async {
      await _pump(tester, width: 1200.0);
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(find.byKey(_boxKey)));
      final painter = _disk(tester)!;

      // 60×60 画布 → 圆心 (30,30)、半径 14 ⇒ 可见包围盒恰为 28×28（居中）。
      final probe = (await tester.runAsync(
        () => _rasterize(painter, const Size(60.0, 60.0)),
      ))!;
      expect(probe.bounds, const Rect.fromLTRB(16.0, 16.0, 44.0, 44.0));
      expect(probe.bounds.width, kIconButtonHoverSize);
      expect(probe.bounds.height, kIconButtonHoverSize);

      // 中心像素色 = rgba(120,120,128,.16)。容差放到 ±6：引擎先按 alpha 预乘
      // 再还原成 8bit straight，往返一次有量化损失（实测蓝通道 128→124）；
      // 「色值精确等于 #29787880」由下面的契约用例单独钉死。
      const expected = <int>[120, 120, 128, 41];
      for (var i = 0; i < 4; i++) {
        expect(
          (probe.center[i] - expected[i]).abs(),
          lessThanOrEqualTo(6),
          reason: '通道 $i 实测 ${probe.center[i]} vs 期望 ${expected[i]}',
        );
      }

      // 28×28 画布（圆正好内切）→ 铺满画布，但四角必须透明（圆不是方）。
      final inscribed = (await tester.runAsync(
        () => _rasterize(painter, const Size(28.0, 28.0)),
      ))!;
      expect(inscribed.bounds, const Rect.fromLTRB(0.0, 0.0, 28.0, 28.0));
      for (final corner in inscribed.corners) {
        expect(corner, 0, reason: '四角在圆外 ⇒ 画的是圆');
      }
      expect(probe.center[3], greaterThan(_alphaFloor));
    });

    testWidgets('选中优先：选中态悬停不叠圆底（免得读成「更深的选中」）', (tester) async {
      await _pump(tester, width: 1200.0, selected: true);
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(find.byKey(_boxKey)));
      expect(_disk(tester), isNull);
    });
  });

  group('外部接管模式（[hovered] 非 null）', () {
    testWidgets('按外部布尔值画/不画，且不自己挂 MouseRegion', (tester) async {
      await _pump(tester, width: 1200.0, externalHover: true);
      expect(_disk(tester), isNotNull);
      expect(
        find.descendant(
          of: find.byType(IconHoverDisk),
          matching: find.byType(MouseRegion),
        ),
        findsNothing,
        reason: '外部接管时悬停判定/光标归调用方，本组件不该再插一层',
      );

      await _pump(tester, width: 1200.0, externalHover: false);
      expect(_disk(tester), isNull);

      // 选中优先在外部模式下同样成立。
      await _pump(tester, width: 1200.0, externalHover: true, selected: true);
      expect(_disk(tester), isNull);
    });
  });

  group('窄屏（<900）逐像素不变', () {
    testWidgets('窄屏悬停不出现圆底（G3 只在宽屏生效）', (tester) async {
      await _pump(tester, width: 899.0);
      expect(_disk(tester), isNull);

      // 鼠标真的压在图标盒正中 —— 若门控被去掉，这里会变红。
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(find.byKey(_boxKey)));
      expect(_disk(tester), isNull);
      expect(
        find.descendant(
          of: find.byType(IconHoverDisk),
          matching: find.byType(MouseRegion),
        ),
        findsNothing,
        reason: '窄屏连 MouseRegion 都不该挂',
      );
    });

    testWidgets('窄屏：child 的矩形与不包本组件时逐字段相等', (tester) async {
      tester.view.physicalSize = const Size(899.0, 400.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: SizedBox(
                key: _boxKey,
                width: 40.0,
                height: 40.0,
                child: ColoredBox(color: Color(0xFF007AFF)),
              ),
            ),
          ),
        ),
      );
      final bareRect = tester.getRect(find.byKey(_boxKey));

      await _pump(tester, width: 899.0);
      expect(tester.getRect(find.byKey(_boxKey)), bareRect);
    });

    testWidgets('手机竖屏 390：悬停同样无圆底', (tester) async {
      await _pump(tester, width: 390.0);
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, tester.getCenter(find.byKey(_boxKey)));
      expect(_disk(tester), isNull);
    });
  });

  test('圆底色值契约：rgba(120,120,128,.16) —— 与 L2 选中底同值', () {
    expect(LightSurfaces.selectedSurface.toARGB32(), 0x29787880);
  });
}
