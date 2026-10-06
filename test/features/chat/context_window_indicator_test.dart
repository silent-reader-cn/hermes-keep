import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/context_window_snapshot.dart';
import 'package:hermes_ui/features/chat/widgets/context_window_indicator.dart';

void main() {
  Widget wrap(Widget child) =>
      CupertinoApp(home: CupertinoPageScaffold(child: child));

  group('ContextWindowIndicator 文本/颜色联动', () {
    testWidgets('无 snapshot -> 中心点且 disabled', (tester) async {
      await tester.pumpWidget(
        wrap(const ContextWindowIndicator(snapshot: null, onTap: null)),
      );
      expect(find.text('\u00b7'), findsOneWidget);
      final btn = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('chat-context-indicator-button')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('snapshot 无 percentage 仍显示点但可点击', (tester) async {
      var tapped = false;
      final snap =
          ContextWindowSnapshot.fromJson({'threshold_tokens': 1000});
      await tester.pumpWidget(
        wrap(
          ContextWindowIndicator(
            snapshot: snap,
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.text('\u00b7'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('chat-context-indicator-button')),
      );
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('27% 正常显示百分比', (tester) async {
      final snap = ContextWindowSnapshot.fromJson({
        'context_length': 200000,
        'last_prompt_tokens': 54321,
      });
      await tester.pumpWidget(
        wrap(ContextWindowIndicator(snapshot: snap, onTap: () {})),
      );
      expect(find.text('27'), findsOneWidget);
    });

    testWidgets('done 更新后 indicator 即时刷新（重建）', (tester) async {
      final low = ContextWindowSnapshot.fromJson(
        {'context_length': 100, 'last_prompt_tokens': 10},
      );
      final high = ContextWindowSnapshot.fromJson(
        {'context_length': 100, 'last_prompt_tokens': 80},
      );
      await tester.pumpWidget(
        wrap(ContextWindowIndicator(snapshot: low, onTap: () {})),
      );
      expect(find.text('10'), findsOneWidget);
      await tester.pumpWidget(
        wrap(ContextWindowIndicator(snapshot: high, onTap: () {})),
      );
      await tester.pump();
      expect(find.text('80'), findsOneWidget);
    });

    testWidgets('尺寸对齐发送按钮图标 (ringSize=22, tapTargetSize=44, fontSize=7)', (tester) async {
      expect(ContextWindowIndicator.ringSize, 22.0);
      expect(ContextWindowIndicator.tapTargetSize, 44.0);

      final snap = ContextWindowSnapshot.fromJson({
        'context_length': 1000,
        'last_prompt_tokens': 500,
      });
      await tester.pumpWidget(
        wrap(ContextWindowIndicator(snapshot: snap, onTap: () {})),
      );

      final textWidget = tester.widget<Text>(find.text('50'));
      expect(textWidget.style?.fontSize, 7.0);
      expect(textWidget.style?.fontWeight, FontWeight.w600);

      final ringBox = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byType(CustomPaint),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(ringBox.width, 22.0);
      expect(ringBox.height, 22.0);

      final button = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('chat-context-indicator-button')),
      );
      expect(button.minimumSize, const Size(44.0, 44.0));
    });
  });


  group('环径分档：与同一行兄弟图标等大（宽屏 18 / 窄屏 22）', () {
    final snap = ContextWindowSnapshot.fromJson({
      'context_length': 200000,
      'last_prompt_tokens': 84000,
    });

    Future<void> pumpAt(
      WidgetTester tester,
      double width, {
      bool compressing = false,
      double? size,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrap(
          ContextWindowIndicator(
            snapshot: snap,
            onTap: () {},
            isCompressing: compressing,
            size: size,
          ),
        ),
      );
      await tester.pump();
    }

    /// 承载记号的那个内层 SizedBox 的边长 = 实际环径。
    /// [find.ancestor] 由近及远返回，故 `.first` 即紧邻的记号盒（外层命中区不算）。
    double glyphSide(WidgetTester tester, Finder inner) => tester
        .widget<SizedBox>(
          find.ancestor(of: inner, matching: find.byType(SizedBox)).first,
        )
        .width!;

    Finder ringInk() => find.byType(CustomPaint);

    testWidgets('常量口径：窄屏基准 22、宽屏 18', (tester) async {
      expect(ContextWindowIndicator.ringSize, 22.0);
      expect(ContextWindowIndicator.wideRingSize, 18.0);
    });

    testWidgets('窄屏（<900）保持 22，逐像素不变', (tester) async {
      await pumpAt(tester, 800);
      expect(glyphSide(tester, ringInk()), 22.0);
    });

    testWidgets('宽屏（>=900）收到 18', (tester) async {
      await pumpAt(tester, 1280);
      expect(glyphSide(tester, ringInk()), 18.0);
    });

    testWidgets('断点边界：899 仍窄屏 / 900 起宽屏', (tester) async {
      await pumpAt(tester, 899);
      expect(glyphSide(tester, ringInk()), 22.0);
      await pumpAt(tester, 900);
      expect(glyphSide(tester, ringInk()), 18.0);
    });

    testWidgets('显式 size 优先于布局分档', (tester) async {
      await pumpAt(tester, 1280, size: 26);
      expect(glyphSide(tester, ringInk()), 26.0);
    });

    testWidgets('压缩中记号同步分档且半径等比缩放（切换不跳位）', (tester) async {
      await pumpAt(tester, 1280, compressing: true);
      expect(
        glyphSide(tester, find.byType(CupertinoActivityIndicator)),
        18.0,
      );
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .radius,
        closeTo(10 * 18 / 22, 0.001),
      );

      await pumpAt(tester, 800, compressing: true);
      expect(
        glyphSide(tester, find.byType(CupertinoActivityIndicator)),
        22.0,
      );
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .radius,
        10.0,
      );
    });

    testWidgets('命中区不随环径缩水（a11y 44 恒定）', (tester) async {
      await pumpAt(tester, 1280);
      final button = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('chat-context-indicator-button')),
      );
      expect(button.minimumSize, const Size(44.0, 44.0));
    });
  });
}
