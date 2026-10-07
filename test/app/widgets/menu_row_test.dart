import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';
import 'package:hermes_ui/app/widgets/menu_row.dart';

/// `MenuRow` 守卫：**行布局必须与主题无关**。
///
/// 背景：菜单行此前浅色走 `CupertinoListTile`、暗色走 `CupertinoButton`。
/// `CupertinoListTile` 把 title 装进
/// `Column(mainAxisAlignment: spaceBetween, mainAxisSize: max)`，外层定高
/// （30 / 36 / 46）压下来时内容被顶到上沿；`CupertinoButton` 则居中。
/// 实测浅色行内容比行中心高 8pt、暗色 0pt —— 同一个菜单项在两态下布局不同。
///
/// 本文件把「两态布局逐像素一致 + 内容垂直居中」钉死：一旦有人再按主题分支
/// 切换行的实现，这里会红。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host({
    required Widget child,
    required Brightness brightness,
  }) => CupertinoApp(
    theme: CupertinoThemeData(brightness: brightness),
    home: CupertinoPageScaffold(
      child: Center(child: SizedBox(width: 240, child: child)),
    ),
  );

  Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);

  group('两态布局一致', () {
    for (final height in <double>[30, 36, 46]) {
      testWidgets('行高 $height：浅/深两态的行与内容矩形完全相同', (tester) async {
        final measured = <Brightness, Map<String, Rect>>{};
        for (final brightness in [Brightness.light, Brightness.dark]) {
          await tester.pumpWidget(
            host(
              brightness: brightness,
              child: MenuRow(
                key: const ValueKey('row'),
                height: height,
                icon: CupertinoIcons.folder,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onTap: () {},
                child: const Text('H', style: TextStyle(fontSize: kFontBody)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          measured[brightness] = {
            'row': rectOf(tester, find.byKey(const ValueKey('row'))),
            'text': rectOf(tester, find.text('H')),
            'icon': rectOf(tester, find.byIcon(CupertinoIcons.folder)),
          };
        }
        final light = measured[Brightness.light]!;
        final dark = measured[Brightness.dark]!;
        expect(light['row'], dark['row']);
        expect(light['text'], dark['text'],
            reason: '两态内容矩形必须一致（此前浅色内容被顶到上沿）');
        expect(light['icon'], dark['icon']);
      });
    }
  });

  group('内容垂直居中', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('${brightness.name}：单行内容 / 图标 / 双行内容都居中', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            brightness: brightness,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MenuRow(
                  key: const ValueKey('single'),
                  height: 30,
                  icon: CupertinoIcons.pin,
                  onTap: () {},
                  child: const Text(
                    '单行',
                    style: TextStyle(fontSize: kFontBody),
                  ),
                ),
                MenuRow(
                  key: const ValueKey('double'),
                  height: 46,
                  icon: CupertinoIcons.folder,
                  onTap: () {},
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('名称', style: TextStyle(fontSize: kFontBody)),
                      SizedBox(height: 4),
                      Text('路径', style: TextStyle(fontSize: kFontCaption)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final single = rectOf(tester, find.byKey(const ValueKey('single')));
        final singleText = rectOf(tester, find.text('单行'));
        expect(singleText.center.dy, moreOrLessEquals(single.center.dy, epsilon: 0.5),
            reason: '单行文本必须与行中心对齐');
        final singleIcon = rectOf(tester, find.byIcon(CupertinoIcons.pin));
        expect(singleIcon.center.dy, moreOrLessEquals(single.center.dy, epsilon: 0.5));

        final doubleRow = rectOf(tester, find.byKey(const ValueKey('double')));
        final nameRect = rectOf(tester, find.text('名称'));
        final pathRect = rectOf(tester, find.text('路径'));
        final contentCenter = (nameRect.top + pathRect.bottom) / 2;
        expect(contentCenter, moreOrLessEquals(doubleRow.center.dy, epsilon: 0.5),
            reason: '双行内容作为整体必须与行中心对齐');
      });
    }
  });

  group('交互', () {
    testWidgets('按下时最近祖先 ColoredBox 换成按下色（既有视觉契约）', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        host(
          brightness: Brightness.light,
          child: MenuRow(
            height: 30,
            onTap: () => tapped++,
            child: const Text('动作'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('动作')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final pressed = tester
          .widget<ColoredBox>(
            find
                .ancestor(
                  of: find.text('动作'),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color;
      expect(pressed, isNot(LightSurfaces.card));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('enabled=false：点了不回调', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        host(
          brightness: Brightness.light,
          child: MenuRow(
            height: 30,
            enabled: false,
            onTap: () => tapped++,
            child: const Text('禁用项'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('禁用项'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tapped, 0);
    });
  });
}
