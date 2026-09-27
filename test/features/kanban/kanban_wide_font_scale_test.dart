import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/kanban.dart';
import 'package:hermes_ui/features/kanban/kanban_page.dart';
import 'package:hermes_ui/features/kanban/kanban_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_kanban_api.dart';

// ---------------------------------------------------------------------------
// 批 2 · P8 守卫：看板卡片描述 / 评论正文字号走仓库既有宽屏档
// （markdownBodyFontSizeFor：宽屏 13.5 / 窄屏 15），卡片标题宽屏 15 → 14；
// **列宽与横向滚一律不动**（列宽恒 280，宽窄屏同值）。
// ---------------------------------------------------------------------------

const Size _wideViewport = Size(1280, 900);
const Size _narrowViewport = Size(390, 1600);

const String _cardTitle = '首连宽限状态机复盘';
const String _description = '对照 #72 的 4s 宽限窗口，确认冷启动补报路径不丢事件。';
const String _comment = '复现到了：冷启动第 2 次探活就把宽限窗口吃掉。';

const KanbanCard _card = KanbanCard(
  cardID: 'kb-1',
  title: _cardTitle,
  status: KanbanStatus('todo'),
  assignee: 'dev-a',
  body: _description,
);

FakeKanbanApi _api() => FakeKanbanApi(
  boards: const [KanbanBoard(slug: 'default', name: '主看板')],
  currentSlug: 'default',
  snapshots: const {
    'default': KanbanBoardSnapshot(
      columns: [
        KanbanColumn(name: 'todo', cards: [_card]),
        KanbanColumn(name: 'ready', cards: []),
      ],
    ),
  },
  details: const {
    'kb-1': KanbanCardDetailEnvelope(
      card: _card,
      comments: [
        KanbanComment(
          commentID: 'c-1',
          cardID: 'kb-1',
          author: 'dev-b',
          body: _comment,
          createdAt: '2026-09-27T09:41:00+08:00',
        ),
      ],
    ),
  },
);

Future<FakeKanbanApi> _pump(WidgetTester tester, Size size) async {
  final api = _api();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    api.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        kanbanApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        home: const KanbanPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return api;
}

double? _fontSize(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.fontSize;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('宽屏：描述/评论 13.5、卡片标题 14，列宽仍 280', (tester) async {
    await _pump(tester, _wideViewport);

    // 列宽不动的判据：卡片块（含内边距）宽度恒为 280。
    expect(
      tester.getRect(find.byKey(const ValueKey('kanban-card-kb-1'))).width,
      280,
    );
    expect(_fontSize(tester, _cardTitle), 14);

    await tester.tap(find.byKey(const ValueKey('kanban-card-kb-1')));
    await tester.pumpAndSettle();

    expect(_fontSize(tester, _description), 13.5);
    expect(_fontSize(tester, _comment), 13.5);
  });

  testWidgets('窄屏：描述/评论 15、卡片标题 15，列宽仍 280（逐像素不变）', (tester) async {
    await _pump(tester, _narrowViewport);

    expect(
      tester.getRect(find.byKey(const ValueKey('kanban-card-kb-1'))).width,
      280,
    );
    expect(_fontSize(tester, _cardTitle), 15);

    await tester.tap(find.byKey(const ValueKey('kanban-card-kb-1')));
    await tester.pumpAndSettle();

    expect(_fontSize(tester, _description), 15);
    expect(_fontSize(tester, _comment), 15);
  });
}
