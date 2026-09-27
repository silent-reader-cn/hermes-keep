import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/insights.dart';
import 'package:hermes_ui/features/insights/insights_api.dart';
import 'package:hermes_ui/features/insights/insights_page.dart';

import '../../helpers/fake_insights_api.dart';

// ---------------------------------------------------------------------------
// 批 2 · P7 守卫：宽屏（≥900）指标 4 列 × 2 行 Bento + 图表两列；窄屏单列不变。
//
// 断言口径：
// - 宽屏看**几何**（格子数 / 行列排布 / 值贴格子左侧 14pt），不看文本；
// - 窄屏钉**旧行为**（一行一格、值被推到行尾、图表在上、活动/模型在下）。
// ---------------------------------------------------------------------------

const Size _wideViewport = Size(1280, 900);

/// 窄屏判据只看宽度（<900）；高度给足，让四段 ListSection 全部构建出来
/// （CustomScrollView 的 sliver 子项按可见性构建，矮视口下下方的段根本不建）。
const Size _narrowViewport = Size(390, 1600);

/// 8 项指标给**互不相同**的值：守卫靠「值的几何位置」判定格数与排布，
/// 值重复会让 find.text 命中多个而无法定位单格。
InsightsResponse _response() => const InsightsResponse(
  periodDays: 30,
  totalSessions: 68,
  totalMessages: 1420,
  totalInputTokens: 8600000,
  totalOutputTokens: 1240000,
  totalTokens: 9840000,
  totalCost: 4.8642,
  totalCacheReadTokens: 2400000,
  totalCacheHitPercent: 62.5,
  models: [
    InsightsModelBreakdown(model: 'gpt-5.2-codex', totalTokens: 1000, tokenShare: 42),
  ],
  dailyTokens: [
    InsightsDailyToken(
      date: '2026-09-08',
      inputTokens: 100,
      outputTokens: 50,
      sessions: 2,
      cost: 0.01,
    ),
  ],
  activityByDay: [InsightsActivityByDay(day: '2026-09-05', sessions: 7)],
  activityByHour: [InsightsActivityByHour(hour: 21, sessions: 7)],
);

/// 8 格的值（顺序与页面一致）。
const List<String> _metricValues = [
  '68',
  '1,420',
  '8.6M',
  '1.24M',
  '9.84M',
  r'$4.8642',
  '62.5%',
  '2.4M',
];

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, _) => const InsightsPage())],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        insightsApiFactoryProvider.overrideWithValue(
          (_) => FakeInsightsApi(response: _response()),
        ),
      ],
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）。
  await tester.pump();
  await tester.pump();
}

/// 值所在 Bento 格（半径 10 的白卡）的矩形：Bento 格的判据就是这层卡片。
Rect _cellRect(WidgetTester tester, String value) {
  final cell = find
      .ancestor(
        of: find.text(value),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(10),
        ),
      )
      .first;
  return tester.getRect(cell);
}

/// 页面顶部内容宽度（无外壳，与视口同宽，左右各 16 留白）。
double _contentWidth(Size viewport) => viewport.width - 32;

void main() {
  group('P7 统计宽屏 Bento', () {
    testWidgets('宽屏：指标为 4 列 × 2 行 Bento（断格数与行列几何）', (tester) async {
      await _pump(tester, _wideViewport);

      final cells = [
        for (final value in _metricValues) _cellRect(tester, value),
      ];
      expect(cells.length, 8);

      // 两行：按 top 归并（同一行 top 相同）。
      final rows = <int, List<Rect>>{};
      for (final rect in cells) {
        rows.putIfAbsent(rect.top.round(), () => <Rect>[]).add(rect);
      }
      expect(rows.length, 2, reason: 'Bento 应为 2 行');
      for (final entry in rows.entries) {
        expect(entry.value.length, 4, reason: '每行 4 列，实际 ${entry.value.length}');
      }

      // 列宽 = (内容宽 - 3 × 12 间距) / 4，行高一致（IntrinsicHeight 拉平）。
      final expectedWidth = (_contentWidth(_wideViewport) - 3 * 12) / 4;
      for (final row in rows.values) {
        final sorted = [...row]..sort((a, b) => a.left.compareTo(b.left));
        for (final rect in sorted) {
          expect(rect.width, closeTo(expectedWidth, 0.6));
        }
        expect(sorted.map((r) => r.height.round()).toSet().length, 1);

        // 列间距 12：相邻格子右边界 + 12 = 下一格左边界。
        for (var i = 1; i < sorted.length; i++) {
          expect(sorted[i].left - sorted[i - 1].right, closeTo(12, 0.6));
        }
      }

      // 行间距 12。
      final tops = rows.keys.toList()..sort();
      final firstRow = rows[tops[0]]!;
      final secondRow = rows[tops[1]]!;
      final firstBottom = firstRow.first.bottom;
      expect(secondRow.first.top - firstBottom, closeTo(12, 0.6));

      // 值就在格子内（贴格子左内边距 14），不再被推到行尾。
      for (final value in _metricValues) {
        final valueRect = tester.getRect(find.text(value));
        final cell = _cellRect(tester, value);
        expect(valueRect.left - cell.left, closeTo(14, 0.6));
      }
    });

    testWidgets('宽屏：图表与活动/模型为两列（右列在图表右侧）', (tester) async {
      await _pump(tester, _wideViewport);

      final chartTitle = tester.getRect(find.text('近 30 天令牌'));
      final activityTitle = tester.getRect(find.text('活动'));
      final modelsTitle = tester.getRect(find.text('模型'));
      final half = _contentWidth(_wideViewport) / 2;

      // 左列 = 柱状图，右列 = 活动 / 模型（同一行起、右列两卡纵排）。
      expect(chartTitle.left, lessThan(half));
      expect(activityTitle.left, greaterThan(half));
      expect(activityTitle.top, closeTo(chartTitle.top, 1));
      expect(modelsTitle.left, closeTo(activityTitle.left, 0.6));
      expect(modelsTitle.top, greaterThan(activityTitle.top));
    });

    testWidgets('窄屏：单列结构不变（一行一格 + 值在行尾 + 图表在上）', (tester) async {
      await _pump(tester, _narrowViewport);

      // 8 行：top 互不相同且递增（单列）。
      final values = [
        for (final value in _metricValues) tester.getRect(find.text(value)),
      ];
      final tops = values.map((r) => r.top.round()).toList();
      expect(tops.toSet().length, 8, reason: '窄屏指标应一行一格');
      final sortedTops = [...tops]..sort();
      expect(tops, sortedTops, reason: '窄屏指标行按顺序纵向排布');

      // 旧行为：值被推到行尾（同一右边界，且落在内容区右半边）。
      final rights = values.map((r) => r.right).toSet();
      expect(rights.length, 1, reason: '窄屏值应共用同一右边界（trailing）');
      expect(rights.first, greaterThan(_contentWidth(_narrowViewport) * 0.75));

      // 窄屏仍是 ListSection 结构（4 段：指标 / 图表 / 活动 / 模型）。
      expect(find.byType(CupertinoListSection), findsNWidgets(4));

      // 图表在上、模型在下（单列纵向顺序不变）。
      final chartTitle = tester.getRect(find.text('近 30 天令牌'));
      final modelsTitle = tester.getRect(find.text('模型'));
      expect(chartTitle.top, lessThan(modelsTitle.top));
      expect(chartTitle.left, closeTo(modelsTitle.left, 0.6));
    });
  });
}
