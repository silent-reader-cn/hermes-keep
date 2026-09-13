import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';

/// 聊天气泡 Markdown 样式契约测试。
///
/// 修复目标（regression 防回归）：
/// 1. 深浅色一致性：标题/加粗/代码/引用/表格全部使用**解析后的** label/link
///    语义色（不得保留未解析的动态色 → 暗黑下画浅色变体黑字）；
/// 2. 加粗不放大：strong/em/del 与正文同基准 15pt（不得继承主题 17pt）；
/// 3. 标题层级收敛：h1=20 / h2=18 / h3=16 / h4-h6=15，w600。
void main() {
  Future<BuildContext> pumpStyleContext(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: const SizedBox.shrink(),
      ),
    );
    return tester.element(find.byType(SizedBox));
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final themeName = brightness == Brightness.light ? '浅色' : '深色';

    testWidgets('assistant 样式 $themeName：全部文本色=解析后 label，标题阶梯收敛，加粗不放大', (
      tester,
    ) async {
      final context = await pumpStyleContext(tester, brightness);
      final label = CupertinoColors.label.resolveFrom(context);
      final link = CupertinoColors.link.resolveFrom(context);
      final grey5 = CupertinoColors.systemGrey5.resolveFrom(context);
      final sheet = buildAssistantMarkdownStyleSheet(context);

      // 基础：正文 / 列表 / 引用 = 15pt label
      expect(sheet.p!.fontSize, 15);
      expect(sheet.p!.color, label);
      expect(sheet.listBullet!.fontSize, 15);
      expect(sheet.listBullet!.color, label);
      expect(sheet.blockquote!.fontSize, 15);
      expect(sheet.blockquote!.color, label);

      // 加粗/斜体/删除线：同 15pt 基准、仅字重/字形变化
      expect(sheet.strong!.fontSize, 15);
      expect(sheet.strong!.fontWeight, FontWeight.w600);
      expect(sheet.strong!.color, label);
      expect(sheet.em!.fontSize, 15);
      expect(sheet.em!.fontStyle, FontStyle.italic);
      expect(sheet.del!.fontSize, 15);
      expect(sheet.del!.decoration, TextDecoration.lineThrough);

      // 标题阶梯：20/18/16/15/15/15，全部 w600 + label
      const sizes = [20.0, 18.0, 16.0, 15.0, 15.0, 15.0];
      for (var i = 0; i < 6; i++) {
        final h = [
          sheet.h1,
          sheet.h2,
          sheet.h3,
          sheet.h4,
          sheet.h5,
          sheet.h6,
        ][i];
        expect(h!.fontSize, sizes[i], reason: 'h${i + 1} 字号');
        expect(h.fontWeight, FontWeight.w600, reason: 'h${i + 1} 字重');
        expect(h.color, label, reason: 'h${i + 1} 颜色');
      }

      // 链接：解析后 link 色 + 下划线
      expect(sheet.a!.color, link);
      expect(sheet.a!.decoration, TextDecoration.underline);

      // 内联代码：13pt monospace + label + grey5 底
      expect(sheet.code!.fontSize, 13);
      expect(sheet.code!.fontFamily, 'monospace');
      expect(sheet.code!.color, label);
      expect(sheet.code!.backgroundColor, grey5);
      expect(
        (sheet.codeblockDecoration! as BoxDecoration).color,
        grey5,
        reason: '代码块底必须 resolve（BoxDecoration 不自动解析）',
      );

      // 表格：表头 w600/label，表体 14pt label，边框 separator resolve
      expect(sheet.tableHead!.fontWeight, FontWeight.w600);
      expect(sheet.tableHead!.color, label);
      expect(sheet.tableBody!.fontSize, 14);
      expect(
        sheet.tableBorder!.top.color,
        CupertinoColors.separator.resolveFrom(context),
      );
    });

    testWidgets('user 样式 $themeName：统一白字、加粗同号', (tester) async {
      final context = await pumpStyleContext(tester, brightness);
      final sheet = buildUserMarkdownStyleSheet(context);
      const white = CupertinoColors.white;

      expect(sheet.p!.fontSize, 15);
      expect(sheet.p!.color, white);
      expect(sheet.strong!.fontSize, 15);
      expect(sheet.strong!.fontWeight, FontWeight.w600);
      expect(sheet.strong!.color, white);
      expect(sheet.h1!.fontSize, 20);
      expect(sheet.h1!.fontWeight, FontWeight.w600);
      expect(sheet.h1!.color, white);
      expect(sheet.code!.fontSize, 13);
      expect(sheet.code!.fontFamily, 'monospace');
      expect(sheet.code!.color, white);
    });
  }

  testWidgets('渲染冒烟：markdown 全文（标题/加粗/代码/引用/列表/表格）正常渲染', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) => MarkdownBody(
            data: '# 标题\n\n正文 **加粗** 与 `代码`。\n\n> 引用\n\n- 列表\n\n| a | b |\n|---|---|\n| 1 | 2 |',
            styleSheet: buildAssistantMarkdownStyleSheet(context),
            builders: createAssistantMarkdownBuilders(context),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('标题'), findsWidgets);
    expect(find.textContaining('加粗'), findsOneWidget);
    expect(find.text('代码'), findsOneWidget);
  });

  group('行内代码 pill 样式专项测试', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final themeName = brightness == Brightness.light ? '浅色' : '深色';

      testWidgets(
        'assistant 行内代码 $themeName：pill 圆角 4、padding 水平 4 垂直 1、背景 grey5',
        (tester) async {
          late BuildContext capturedContext;
          await tester.pumpWidget(
            CupertinoApp(
              theme: CupertinoThemeData(brightness: brightness),
              home: Builder(
                builder: (context) {
                  capturedContext = context;
                  return MarkdownBody(
                    data: '这是 `Actions` 测试。',
                    selectable: true,
                    styleSheet: buildAssistantMarkdownStyleSheet(context),
                    builders: createAssistantMarkdownBuilders(context),
                  );
                },
              ),
            ),
          );

          final grey5 = CupertinoColors.systemGrey5.resolveFrom(
            capturedContext,
          );
          final label = CupertinoColors.label.resolveFrom(capturedContext);

          // 查找渲染为 pill 的 Container
          final containerFinder = find.ancestor(
            of: find.text('Actions'),
            matching: find.byType(Container),
          );
          expect(containerFinder, findsOneWidget);

          final container = tester.widget<Container>(containerFinder);
          final decoration = container.decoration as BoxDecoration?;
          expect(decoration, isNotNull);
          expect(decoration!.color, grey5);
          expect(
            decoration.borderRadius,
            const BorderRadius.all(Radius.circular(kInlineCodeBorderRadius)),
          );
          expect(container.padding, kInlineCodePadding);

          // 文本属性校验
          final textWidget = tester.widget<Text>(find.text('Actions'));
          expect(textWidget.style!.fontSize, 13);
          expect(textWidget.style!.height, 1.4);
          expect(textWidget.style!.fontFamily, 'monospace');
          expect(textWidget.style!.color, label);
          expect(textWidget.style!.backgroundColor, const Color(0x00000000));
        },
      );

      testWidgets('user 行内代码 $themeName：pill 背景白 0.22、字色白', (tester) async {
        await tester.pumpWidget(
          CupertinoApp(
            theme: CupertinoThemeData(brightness: brightness),
            home: Builder(
              builder: (context) {
                return MarkdownBody(
                  data: '用户输入 `ping -c 3` 命令',
                  selectable: true,
                  styleSheet: buildUserMarkdownStyleSheet(context),
                  builders: createUserMarkdownBuilders(context),
                );
              },
            ),
          ),
        );

        final containerFinder = find.ancestor(
          of: find.text('ping -c 3'),
          matching: find.byType(Container),
        );
        expect(containerFinder, findsOneWidget);

        final container = tester.widget<Container>(containerFinder);
        final decoration = container.decoration as BoxDecoration?;
        expect(decoration, isNotNull);
        expect(
          decoration!.color,
          brightness == Brightness.light
              ? LightSurfaces.userDetail
              : CupertinoColors.white.withValues(alpha: 0.22),
        );
        expect(
          decoration.borderRadius,
          const BorderRadius.all(Radius.circular(4.0)),
        );
        expect(container.padding, kInlineCodePadding);

        final textWidget = tester.widget<Text>(find.text('ping -c 3'));
        expect(textWidget.style!.color, CupertinoColors.white);
        expect(textWidget.style!.backgroundColor, const Color(0x00000000));
      });
    }

    testWidgets('块级代码与行内代码混合渲染：块级保留滚动条与 codeblockDecoration，行内保持 pill', (
      tester,
    ) async {
      late BuildContext capturedContext;
      const markdown = '''
前置行内 `inline1` 说明。

```dart
void main() {
  print('hello');
}
```

后置行内 `inline2` 说明。
''';

      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return MarkdownBody(
                data: markdown,
                selectable: true,
                styleSheet: buildAssistantMarkdownStyleSheet(context),
                builders: createAssistantMarkdownBuilders(context),
              );
            },
          ),
        ),
      );

      final grey5 = CupertinoColors.systemGrey5.resolveFrom(capturedContext);

      // inline1 与 inline2 均应渲染为 pill Container (padding 4,1, radius 4, bg grey5)
      final inline1Container = tester.widget<Container>(
        find.ancestor(
          of: find.text('inline1'),
          matching: find.byType(Container),
        ),
      );
      expect(inline1Container.padding, kInlineCodePadding);
      expect(
        (inline1Container.decoration as BoxDecoration).borderRadius,
        const BorderRadius.all(Radius.circular(4.0)),
      );
      expect((inline1Container.decoration as BoxDecoration).color, grey5);

      final inline2Container = tester.widget<Container>(
        find.ancestor(
          of: find.text('inline2'),
          matching: find.byType(Container),
        ),
      );
      expect(inline2Container.padding, kInlineCodePadding);
      expect((inline2Container.decoration as BoxDecoration).color, grey5);

      // 块级代码应包含 SingleChildScrollView (横向滚动)
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.textContaining("print('hello');"), findsOneWidget);
    });

    testWidgets('同段落多处行内代码：全部转为 pill 且富文本不报错', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) => MarkdownBody(
              data: '包含 `Alpha`、`Beta` 与 `Gamma` 三个行内 pill。',
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
    });

    testWidgets('无语言标记的围栏代码块与缩进代码块：正确识别为块级而不被误转为行内 pill', (tester) async {
      const markdown = '''
行内 `start` 开始。

```
untyped block line 1
untyped block line 2
```

    indented block line 1
    indented block line 2

行内 `end` 结束。
''';

      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (context) => MarkdownBody(
              data: markdown,
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // start 与 end 渲染为 pill
      expect(
        find.ancestor(of: find.text('start'), matching: find.byType(Container)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.text('end'), matching: find.byType(Container)),
        findsOneWidget,
      );

      // 两个块级代码均通过 SingleChildScrollView 渲染
      expect(find.byType(SingleChildScrollView), findsNWidgets(2));
      expect(find.textContaining('untyped block line 1'), findsOneWidget);
      expect(find.textContaining('indented block line 1'), findsOneWidget);
    });

    testWidgets('双反引号包裹的行内代码 `` `code` `` 正确渲染为 pill', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (context) => MarkdownBody(
              data: '测试 `` `embedded backtick` `` 行内代码',
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.ancestor(
          of: find.text('`embedded backtick`'),
          matching: find.byType(Container),
        ),
        findsOneWidget,
      );
    });
  });
}
