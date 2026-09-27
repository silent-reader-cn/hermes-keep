import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/features/downloads/download_models.dart';
import 'package:hermes_ui/features/downloads/download_page.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_download_service.dart';

// ---------------------------------------------------------------------------
// 批 2 · P5 守卫：宽屏（≥900）两列网格；窄屏单列列表逐像素不变。
//
// 两条用例都断**几何**（列数 / 卡面宽 / 卡面左边界），不看文本：样式改动的回归
// 用文本断言抓不到。断言对象是**画出来的卡面**（半径 10 的白卡），不是
// 带外边距的外层盒子 —— 后者宽窄屏都是整列宽，断不出「几列」。
// ---------------------------------------------------------------------------

const Size _wideViewport = Size(1280, 900);
const Size _narrowViewport = Size(390, 1600);

/// 窄屏单列的历史几何：外层 ListView 上下留 8、卡片自带 16 水平外边距
/// ⇒ 卡面左边界 16、卡面宽 = 屏宽 - 32。
const double _narrowCardLeft = 16;
const double _narrowHorizontalInset = 32;

/// 宽屏网格几何：最外层左右各留 10，卡片自带 6 外边距、卡面再内收 12
/// ⇒ 列宽 (屏宽 - 20) / 2，卡面宽 = 列宽 - 12、两卡面间距 12。
/// （套进宽屏外壳后内容区 960，卡面宽 ≈458 —— 与设计稿「≈460」一致。）
const double _wideGridPadding = 10;
const double _wideCardMargin = 6;

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// 4 条任务覆盖 4 种形态（排队 / 下载中带进度 / 失败 / 已取消），
/// 一律不带 `savedPath`：页面只在有落盘路径时才查 `File.existsSync()`，
/// 守卫测试不碰真实文件系统。
List<DownloadTask> _tasks() {
  const base = 1780000000000;
  return const [
    DownloadTask(
      id: 'q1',
      sourceUrl: 'https://hermes.example.com/files/a.bin',
      fileName: 'wide-batch2-a.bin',
      mimeType: 'application/octet-stream',
      status: DownloadStatus.queued,
      receivedBytes: 0,
      expectedBytes: 1024,
      createdAt: base,
    ),
    DownloadTask(
      id: 'd1',
      sourceUrl: 'https://hermes.example.com/files/b.bin',
      fileName: 'wide-batch2-b.bin',
      mimeType: 'application/octet-stream',
      status: DownloadStatus.downloading,
      receivedBytes: 512,
      expectedBytes: 1024,
      createdAt: base + 1,
    ),
    DownloadTask(
      id: 'f1',
      sourceUrl: 'https://hermes.example.com/files/c.bin',
      fileName: 'wide-batch2-c.bin',
      mimeType: 'application/octet-stream',
      status: DownloadStatus.failed,
      receivedBytes: 12,
      expectedBytes: 1024,
      failureMessage: '连接中断',
      createdAt: base + 2,
    ),
    DownloadTask(
      id: 'x1',
      sourceUrl: 'https://hermes.example.com/files/d.bin',
      fileName: 'wide-batch2-d.bin',
      mimeType: 'application/octet-stream',
      status: DownloadStatus.cancelled,
      receivedBytes: 3,
      expectedBytes: 1024,
      createdAt: base + 3,
    ),
  ];
}

/// 卡片 key 按**页内显示顺序**（createdAt 倒序 ⇒ x1 最上）列出：
/// 单列用例顺带钉住「新任务在上」的既有排序。
const List<String> _cardKeys = [
  'download-task-x1',
  'download-task-f1',
  'download-task-d1',
  'download-task-q1',
];

/// 卡面（半径 10 的白卡）矩形：判定「几列」的几何依据。
///
/// 取 [DecoratedBox] 而非外层 `Container`：Container 的 render object 是包住
/// 外边距的那层 Padding（宽窄屏都是整列宽，断不出列数），装饰盒才是画出来的卡面。
Rect _cardSurface(WidgetTester tester, String key) {
  final surface = find
      .descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(10),
        ),
      )
      .first;
  return tester.getRect(surface);
}

Future<void> _pump(WidgetTester tester, Size size) async {
  final db = AppDatabase.memory();
  final tempDir = Directory.systemTemp.createTempSync('dl_wide_grid_test_');
  addTearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    await db.close();
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...createDownloadTestOverrides(db: db, tempDir: tempDir),
        downloadTasksProvider.overrideWithValue(_tasks()),
      ],
      child: CupertinoApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: _delegates,
        theme: buildCupertinoTheme(Brightness.light),
        home: const DownloadPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('宽屏：两列网格（2 行 × 2 列，卡面宽 = 列宽 - 12）', (tester) async {
    await _pump(tester, _wideViewport);

    expect(find.byKey(const ValueKey('downloads-grid-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('downloads-list-view')), findsNothing);

    final surfaces = [
      for (final key in _cardKeys) _cardSurface(tester, key),
    ];
    expect(surfaces.length, 4);

    final columnWidth = (_wideViewport.width - 2 * _wideGridPadding) / 2;
    final surfaceWidth = columnWidth - 2 * _wideCardMargin;

    final rows = <int, List<Rect>>{};
    for (final rect in surfaces) {
      rows.putIfAbsent(rect.top.round(), () => <Rect>[]).add(rect);
    }
    expect(rows.length, 2, reason: '4 张卡应排成 2 行');
    for (final row in rows.values) {
      expect(row.length, 2, reason: '每行 2 列');
      final sorted = [...row]..sort((a, b) => a.left.compareTo(b.left));
      for (final rect in sorted) {
        expect(rect.width, closeTo(surfaceWidth, 0.6));
        expect(rect.height, row.first.height, reason: '同行卡面等高');
      }
      // 同一行两列：卡面间距 12。
      expect(sorted[1].left - sorted[0].right, closeTo(12, 0.6));
    }

    // 两条列线：首列贴 16（10 留白 + 6 外边距），次列在其整列宽之后。
    final leftEdges = {for (final rect in surfaces) rect.left.round()}.toList()
      ..sort();
    expect(leftEdges.length, 2, reason: '只有两条列线');
    expect(leftEdges.first, _wideGridPadding + _wideCardMargin);
    expect(
      leftEdges.last,
      closeTo(_wideGridPadding + columnWidth + _wideCardMargin, 0.6),
    );
  });

  testWidgets('窄屏：单列列表逐像素不变（卡面左 16、宽 = 屏宽 - 32）', (tester) async {
    await _pump(tester, _narrowViewport);

    expect(find.byKey(const ValueKey('downloads-list-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('downloads-grid-view')), findsNothing);

    final surfaces = [
      for (final key in _cardKeys) _cardSurface(tester, key),
    ];
    expect(surfaces.length, 4);

    // 单列：左边界与宽度全等、top 递增（一行一卡）。
    expect(surfaces.map((r) => r.left).toSet(), {_narrowCardLeft});
    for (final rect in surfaces) {
      expect(rect.width, _narrowViewport.width - _narrowHorizontalInset);
    }
    final tops = surfaces.map((r) => r.top).toList();
    expect(tops, [...tops]..sort(), reason: '单列按顺序纵向排布');
    expect(tops.toSet().length, 4, reason: '一行一卡');
  });
}
