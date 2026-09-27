import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/memory.dart';
import 'package:hermes_ui/features/memory/memory_api.dart';
import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';
import 'package:hermes_ui/features/memory/memory_page.dart';
import 'package:hermes_ui/features/shared/wide_nav_rail.dart';

import '../../helpers/fake_memory_api.dart';

/// 批 3 · P6 守卫：记忆页宽屏（≥900）顶部分段控件 → 左 220 分区导航 +
/// 正文字号套用 `markdownBodyFontSizeFor`（宽屏 13.5 / 窄屏 15，代码块 12 / 13）；
/// 正文维持既有 720 限宽居中；窄屏（<900）分段控件与正文逐像素不变
/// （像素级证据见 `test/screenshots/narrow_pages_shots_test.dart`）。

const String _soulMarkdown = '# 智能体灵魂\n\n- 规则一\n- 规则二';
const String _projectMarkdown =
    '# 项目上下文\n\n正文段落。\n\n```\nC:/tmp/f.bat test\n```';

MemoryResponse _response({bool withProject = true}) => MemoryResponse(
  memory: '我的笔记正文',
  user: '用户画像正文',
  soul: _soulMarkdown,
  projectContext: withProject ? _projectMarkdown : null,
);

Future<void> _pump(
  WidgetTester tester,
  FakeMemoryApi api, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, _) => const MemoryPage())],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        memoryApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder get _rail => find.byKey(const ValueKey('memory-nav-rail'));

/// 顶部分段控件（T 是页面私有枚举，故用 predicate 而非 byType）。
Finder get _segmented => find.byWidgetPredicate(
  (w) => w is CupertinoSlidingSegmentedControl<Object?>,
);

/// 当前 markdown 正文样式表。
MarkdownStyleSheet? _styleSheet(WidgetTester tester) =>
    tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet;

void main() {
  group('记忆页宽屏分区导航（批 3 · P6）', () {
    testWidgets('宽屏 1280：左 220 分区导航 + 正文 720 限宽居中（分段控件消失）', (tester) async {
      await _pump(
        tester,
        FakeMemoryApi(response: _response()),
        size: const Size(1280, 800),
      );

      // 顶部分段控件不再出现，左栏导航出现
      expect(_segmented, findsNothing, reason: '宽屏不再有顶部分段控件');
      expect(_rail, findsOneWidget);
      final railRect = tester.getRect(_rail);
      expect(railRect.width, 220);
      expect(railRect.left, 0);

      // 四个分区（l10n 真值），默认选中「项目上下文」
      final rows = find.descendant(
        of: _rail,
        matching: find.byType(WideNavRailRow),
      );
      expect(rows, findsNWidgets(4));
      for (final label in ['我的笔记', '用户画像', '智能体灵魂', '项目上下文']) {
        expect(
          find.descendant(of: _rail, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('memory-tab-project')),
        findsOneWidget,
        reason: '工装 / 测试按 key 定位分区（与窄屏分段控件同一套 key）',
      );
      final selected = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('memory-tab-project')),
          matching: find.text('项目上下文'),
        ),
      );
      expect(selected.style?.color, const Color(0xFF005FB8), reason: 'L2 选中蓝字');

      // 正文维持既有 720 限宽居中（本批不改宽度）
      final box = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 720,
        ),
      );
      expect(box.width, 720);
      expect(
        box.left - 220,
        closeTo(1280 - box.right, 0.01),
        reason: '正文左右留白相等（居中）',
      );
    });

    testWidgets('宽屏：正文 13.5 / 列表符 13.5 / 代码块 12；纯文本分区同档 13.5', (tester) async {
      await _pump(
        tester,
        FakeMemoryApi(response: _response()),
        size: const Size(1280, 800),
      );

      final style = _styleSheet(tester)!;
      expect(
        style.p?.fontSize,
        13.5,
        reason: '宽屏正文走 kWideMarkdownBodyFontSize',
      );
      expect(style.listBullet?.fontSize, 13.5);
      expect(style.code?.fontSize, 12, reason: '代码块随正文收一档 13 → 12');

      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();
      final body = tester.widget<Text>(find.text('我的笔记正文'));
      expect(body.style?.fontSize, 13.5, reason: '纯文本分区同档');
    });

    testWidgets('窄屏 400：分段控件仍在、无左导航；正文 15 / 代码块 13', (tester) async {
      await _pump(
        tester,
        FakeMemoryApi(response: _response()),
        size: const Size(400, 900),
      );

      expect(_rail, findsNothing, reason: '窄屏无左导航');
      expect(_segmented, findsOneWidget, reason: '窄屏仍是顶部分段控件');
      expect(find.byKey(const ValueKey('memory-tab-project')), findsOneWidget);

      final style = _styleSheet(tester)!;
      expect(style.p?.fontSize, 15, reason: '窄屏正文维持 15（逐像素不变）');
      expect(style.listBullet?.fontSize, 15);
      expect(style.code?.fontSize, 13);
    });

    testWidgets('断点：899 窄屏分段／900 宽屏导航', (tester) async {
      await _pump(
        tester,
        FakeMemoryApi(response: _response()),
        size: const Size(899, 900),
      );
      expect(_rail, findsNothing);
      expect(_segmented, findsOneWidget);

      await _pump(
        tester,
        FakeMemoryApi(response: _response()),
        size: const Size(900, 900),
      );
      expect(_rail, findsOneWidget);
      expect(_segmented, findsNothing);
    });

    testWidgets('宽屏：点左栏切分区渲染 markdown', (tester) async {
      await _pump(
        tester,
        FakeMemoryApi(response: _response()),
        size: const Size(1280, 800),
      );

      await tester.tap(find.byKey(const ValueKey('memory-tab-soul')));
      await tester.pump();
      expect(find.text('规则一'), findsOneWidget);
      expect(find.text('正文段落。'), findsNothing);
    });

    testWidgets('宽屏：无项目上下文 ⇒ 该项从导航消失并回落到「我的笔记」', (tester) async {
      await _pump(
        tester,
        FakeMemoryApi(response: _response(withProject: false)),
        size: const Size(1280, 800),
      );

      expect(find.byKey(const ValueKey('memory-tab-project')), findsNothing);
      expect(
        find.descendant(of: _rail, matching: find.byType(WideNavRailRow)),
        findsNWidgets(3),
      );
      expect(find.text('我的笔记正文'), findsOneWidget);
    });
  });
    // ── 标题阶梯守卫（Leader 补）：记忆页是非气泡 markdown，必须让 h1-h6 从 body 派生，
    //    否则会沿用 flutter_markdown 包自带默认标题（h1≈30），宽屏缩档后「正文正常、标题巨大」。
    testWidgets('宽屏：h1/h2/h3 从 body 派生（+5/+3/+1），不是包默认大字号', (tester) async {
      await _pump(tester, FakeMemoryApi(response: _response()), size: const Size(1280, 800));
      final s = _styleSheet(tester);
      expect(s, isNotNull, reason: '宽屏应渲染 markdown 正文');
      expect(s!.h1!.fontSize, kWideMarkdownBodyFontSize + 5); // 18.5
      expect(s.h2!.fontSize, kWideMarkdownBodyFontSize + 3); // 16.5
      expect(s.h3!.fontSize, kWideMarkdownBodyFontSize + 1); // 14.5
      expect(s.p!.fontSize, kWideMarkdownBodyFontSize); // 13.5
      expect(s.h1!.fontWeight, kMarkdownStrongWeight);
      expect(s.h1!.fontSize, lessThan(24)); // 回归护栏：不得回到包默认的字号量级
    });

    testWidgets('窄屏：标题阶梯维持 15 档（+5/+3/+1），正文 15', (tester) async {
      await _pump(tester, FakeMemoryApi(response: _response()), size: const Size(390, 800));
      final s = _styleSheet(tester);
      expect(s!.p!.fontSize, kMarkdownBodyFontSize); // 15
      expect(s.h1!.fontSize, kMarkdownBodyFontSize + 5); // 20
    });

}
