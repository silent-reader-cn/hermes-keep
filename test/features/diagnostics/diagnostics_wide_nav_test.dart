import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/layout_tokens.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_detail_sheet.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_page.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_providers.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/features/shared/wide_nav_rail.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 批 4C · P10 守卫：诊断页宽屏（≥900）只把**顶部 chips 行**搬进左 220 导航
/// （级别「全部 + V/D/I/W/E」→ 级别色与计数全保留、时间范围同列在下），
/// 右栏（调试模式开关 / 搜索框 / 计数 / 导出 / 清空日志 / 日志表）一律留原位、
/// 日志表铺满，详情在右栏内展开；窄屏（<900）逐像素不变。
///
/// 窄屏「逐像素不变」的硬证据不在这里（本文件是结构守卫）：改动前后用一次性工装
/// 对 400/880 × 浅/暗 × {列表, 整页详情} 共 8 张 PNG 做逐像素比对，**sha256 全等**
/// （图与工装留档在 `.shots/b4c-narrow-before/` 与
/// `.shots/b4c-narrow/harness_diag_narrow_shots_test.dart.txt`，两处均被 .gitignore
/// 排除、不进仓库；工装是临时的，未落进 `test/` —— 文件级分区只允许本文件新增）。
///
/// 口径注记：
/// 1. 左栏计数 = **库内各级日志条数**（稳定的「级别分布」读数，不做级别/时间/搜索
///    过滤）；右栏计数 = `筛选后 / 总数`。两者分工不同，本文件分别钉住。
/// 2. 左栏「全部」= 级别全集选中（既有筛选状态是集合多选、末项不可撤，故「全部」
///    只做「补齐缺口」）；默认筛选即全集，故默认态下 6 项都展示各自的级别色。
/// 3. 左栏时间范围含「全部」（与窄屏 4 枚时间 chips 一一对应）—— 若省掉它，
///    默认态（timeFilter=all）在左栏将没有任何选中项，且真机上可选的筛选丢一档。

const Size _wide = Size(1280, 800);
const Size _narrow = Size(400, 900);

/// 演示日志：V1 / D2 / I3 / W2 / E1 = 9 条（各级计数互不相同，便于钉住「哪一行是哪个数」）。
Future<DiagnosticsService> _demoService() async {
  final prefs = await SharedPreferences.getInstance();
  final service = DiagnosticsService(customPrefs: prefs);
  await service.init(prefs: prefs);
  await service.setEnabled(true);
  // 演示日志锚定**今天**，不要写死日期：本文件有断言「切『今天』后仍留全部」
  // （见下方 `左栏时间范围：切「今天」` 用例），原来写死 2026-09-27 ——
  // 一旦跨过那一天，9 条数据全部落在「今天」之外，那条用例就**每天必红**
  // （2026-09-28 00:04 实测踩到）。
  // 时刻取今天正午：最早一条是 base-9min，仍稳落在今天之内；不依赖运行时刻
  // （凌晨/深夜跑都成立），也不影响其余用例（本文件无「时:分」文本断言）。
  final today = DateTime.now();
  final base = DateTime(today.year, today.month, today.day, 12);
  var seq = 0;
  void log(DiagnosticsLogLevel level, String tag, String message) {
    seq += 1;
    service.log(
      level: level,
      tag: tag,
      message: message,
      timestamp: base.subtract(Duration(minutes: seq)),
      details: {'seq': seq},
    );
  }

  log(DiagnosticsLogLevel.verbose, 'sse', '原始事件帧：token ×42（逐帧诊断）');
  for (var i = 0; i < 2; i++) {
    log(
      DiagnosticsLogLevel.debug,
      'dio',
      'GET /api/sessions → 200（第 ${i + 1} 次）',
    );
  }
  for (var i = 0; i < 3; i++) {
    log(DiagnosticsLogLevel.info, 'app', '服务自检通过（第 ${i + 1} 项）');
  }
  for (var i = 0; i < 2; i++) {
    log(DiagnosticsLogLevel.warn, 'keepalive', '心跳超时（第 ${i + 1} 次），已重连');
  }
  log(
    DiagnosticsLogLevel.error,
    'dio',
    'GET /api/workspace/download → 断流（已自动重试 1 次）',
  );

  // 让 500ms 落库防抖计时器先结算，后续用例不再被它打扰。
  await Future<void>.delayed(const Duration(milliseconds: 600));
  return service;
}

Future<void> _pump(
  WidgetTester tester,
  DiagnosticsService service, {
  required Size size,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [diagnosticsServiceProvider.overrideWithValue(service)],
      child: CupertinoApp(
        debugShowCheckedModeBanner: false,
        theme: buildCupertinoTheme(brightness),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: const DiagnosticsPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder get _rail => find.byKey(const ValueKey('diagnostics-nav-rail'));
Finder get _logList => find.byKey(const ValueKey('diagnostics-log-list'));
Finder get _wideDetail => find.byKey(const ValueKey('diagnostics-wide-detail'));

Finder _levelRow(String code) =>
    find.byKey(ValueKey('diagnostics-nav-level-$code'));
Finder _timeRow(DiagnosticsTimeFilter filter) =>
    find.byKey(ValueKey('diagnostics-nav-time-${filter.name}'));

/// 行内名称/字母的 [Text]。
Text _textIn(WidgetTester tester, Finder row, String text) =>
    tester.widget<Text>(find.descendant(of: row, matching: find.text(text)));

/// 级别字母色块的底色（选中时的级别 tint）。
Color _blockTint(WidgetTester tester, Finder row, String letter) {
  final container = tester.widget<Container>(
    find
        .ancestor(
          of: find.descendant(of: row, matching: find.text(letter)),
          matching: find.byType(Container),
        )
        .first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('诊断页宽屏筛选导航（批 4C · P10）', () {
    late DiagnosticsService service;
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('diag_wide_nav_test_');
      SafeClipboard.destinationDirOverride = tempDir;
      service = await _demoService();
    });

    tearDown(() {
      SafeClipboard.resetOverridesForTesting();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
      service.clearMemoryOnly();
    });

    testWidgets('宽屏 1280：左 220 筛选导航（6 项含级别色与计数）+ 右栏五类元素原地 + 日志表铺满', (
      tester,
    ) async {
      await _pump(tester, service, size: _wide);

      // ── 左栏：宽 220、贴左缘、右侧分栏线 ──
      expect(_rail, findsOneWidget, reason: '宽屏必须有左栏筛选导航');
      final railRect = tester.getRect(_rail);
      expect(railRect.width, kWideNavRailWidth);
      expect(railRect.width, 220);
      expect(railRect.left, 0);

      // ── 左栏 6 项：全部 + V/D/I/W/E，每项「字母色块 + 名称 + 计数」──
      const levelCodes = ['V', 'D', 'I', 'W', 'E'];
      expect(find.byKey(const ValueKey('diagnostics-nav-all')), findsOneWidget);
      expect(
        find.descendant(of: _rail, matching: find.byType(WideNavRailRow)),
        findsNothing,
        reason: '本页左栏行自带字母色块与计数，不用共享骨架的 icon/label 行',
      );
      for (final code in levelCodes) {
        expect(_levelRow(code), findsOneWidget, reason: '左栏应有 $code 级别项');
      }

      // 名称（中文，与真机 chips 的级别一一对应）与计数（库内各级条数）
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('diagnostics-nav-all')),
          matching: find.text('全部'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('diagnostics-nav-all')),
          matching: find.text('9'),
        ),
        findsOneWidget,
        reason: '「全部」计数 = 库内总条数 9',
      );
      const names = {'V': '详细', 'D': '调试', 'I': '信息', 'W': '警告', 'E': '错误'};
      const counts = {'V': '1', 'D': '2', 'I': '3', 'W': '2', 'E': '1'};
      for (final entry in names.entries) {
        expect(
          find.descendant(
            of: _levelRow(entry.key),
            matching: find.text(entry.value),
          ),
          findsOneWidget,
          reason: '${entry.key} 行名称应为「${entry.value}」',
        );
        expect(
          find.descendant(
            of: _levelRow(entry.key),
            matching: find.text(counts[entry.key]!),
          ),
          findsOneWidget,
          reason: '${entry.key} 行计数应为 ${counts[entry.key]}',
        );
      }

      // ── 级别色逐项核对（选中态才显级别色：默认筛选 = 全集选中）──
      const tints = {
        'V': 0xFFF2F2F7,
        'D': 0xFFF3F2FF,
        'I': 0xFFE0ECFF,
        'W': 0xFFFFF4E8,
        'E': 0xFFFFF4F3,
      };
      const fg = {
        'V': 0xFF595959,
        'D': 0xFF4A6B82,
        'I': 0xFF005FB8,
        'W': 0xFFB25000,
        'E': 0xFFB3001B,
      };
      for (final code in levelCodes) {
        expect(
          _blockTint(tester, _levelRow(code), code).toARGB32(),
          tints[code],
          reason: '$code 色块底 must be 各级 tint',
        );
        expect(
          _textIn(tester, _levelRow(code), code).style?.color?.toARGB32(),
          fg[code],
          reason:
              '$code 字母色 must be 各级 textColor'
              '（debug 专有蓝灰 #4A6B82）',
        );
      }
      // 「全部」行：蓝 tint + 蓝字（与真机 chips 的 info 蓝同源）
      expect(
        _blockTint(
          tester,
          find.byKey(const ValueKey('diagnostics-nav-all')),
          '全',
        ).toARGB32(),
        0xFFE0ECFF,
      );
      expect(
        _textIn(
          tester,
          find.byKey(const ValueKey('diagnostics-nav-all')),
          '全',
        ).style?.color?.toARGB32(),
        0xFF005FB8,
      );

      // 选中态走 L2：行底中性灰 .16、名称为 #005FB8
      expect(
        _textIn(tester, _levelRow('I'), '信息').style?.color?.toARGB32(),
        LightSurfaces.selectionForeground.toARGB32(),
      );

      // ── 时间范围同列在下：4 项（含「全部」，与窄屏 chips 一一对应）──
      expect(
        find.descendant(of: _rail, matching: find.text('时间范围')),
        findsOneWidget,
      );
      for (final filter in DiagnosticsTimeFilter.values) {
        expect(_timeRow(filter), findsOneWidget);
      }
      const timeLabels = {
        DiagnosticsTimeFilter.all: '全部',
        DiagnosticsTimeFilter.today: '今天',
        DiagnosticsTimeFilter.last7Days: '近 7 天',
        DiagnosticsTimeFilter.custom: '自定义',
      };
      for (final entry in timeLabels.entries) {
        expect(
          find.descendant(
            of: _timeRow(entry.key),
            matching: find.text(entry.value),
          ),
          findsOneWidget,
        );
      }
      // 默认 timeFilter=all ⇒ 「全部」选中（L2 蓝字）
      expect(
        _textIn(
          tester,
          _timeRow(DiagnosticsTimeFilter.all),
          '全部',
        ).style?.color?.toARGB32(),
        LightSurfaces.selectionForeground.toARGB32(),
      );
      // 未选中的时间项：灰字（非蓝）
      expect(
        _textIn(
          tester,
          _timeRow(DiagnosticsTimeFilter.today),
          '今天',
        ).style?.color,
        isNot(LightSurfaces.selectionForeground),
      );
      // 时间行在级别行之下
      expect(
        tester.getRect(_timeRow(DiagnosticsTimeFilter.all)).top,
        greaterThan(tester.getRect(_levelRow('E')).top),
      );

      // ── 右栏五类元素仍在原位（开关 / 搜索 / 计数 / 导出 / 清空）──
      expect(
        find.byKey(const ValueKey('diagnostics-switch-tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('diagnostics-switch-enable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('diagnostics-search-field')),
        findsOneWidget,
      );
      expect(find.text('9 / 9'), findsOneWidget, reason: '右栏计数语义保留');
      expect(
        find.byKey(const ValueKey('diagnostics-export-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('diagnostics-clear-btn')),
        findsOneWidget,
      );
      // 按 y 序：开关 → 搜索 → 计数/导出/清空 → 日志表（全部在右栏内）
      final ys = [
        tester
            .getRect(find.byKey(const ValueKey('diagnostics-switch-tile')))
            .top,
        tester
            .getRect(find.byKey(const ValueKey('diagnostics-search-field')))
            .top,
        tester
            .getRect(find.byKey(const ValueKey('diagnostics-export-btn')))
            .top,
        tester.getRect(_logList).top,
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: '右栏元素次序不变');
      }
      for (final finder in [
        find.byKey(const ValueKey('diagnostics-search-field')),
        find.byKey(const ValueKey('diagnostics-export-btn')),
        _logList,
      ]) {
        expect(
          tester.getRect(finder).left,
          greaterThanOrEqualTo(railRect.right),
          reason: '右栏元素不得越过左栏',
        );
      }

      // ── 日志表铺满右栏（表格型内容不限宽）──
      final listRect = tester.getRect(_logList);
      expect(listRect.left, railRect.right, reason: '日志表左缘贴左栏');
      expect(
        listRect.width,
        _wide.width - kWideNavRailWidth,
        reason: '日志表吃满右栏（1280 − 220 = 1060）',
      );
      expect(listRect.right, _wide.width);
      expect(
        listRect.width,
        greaterThan(kReadingMaxWidth),
        reason: '日志表宽度必须超过阅读限宽档（表格型内容铺满右栏）',
      );
      // 无 760 阅读限宽这类「内容盒」包住日志表
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ConstrainedBox && w.constraints.maxWidth == kReadingMaxWidth,
        ),
        findsNothing,
        reason: '日志表是表格型内容，不得套阅读限宽 760',
      );
    });

    testWidgets('宽屏：点日志行 → 详情在右栏内展开（不 push 整页）；返回恢复日志表', (tester) async {
      await _pump(tester, service, size: _wide);
      expect(_wideDetail, findsNothing);

      await tester.tap(
        find.text('GET /api/workspace/download → 断流（已自动重试 1 次）'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_wideDetail, findsOneWidget, reason: '详情在右栏内展开');
      expect(
        find.byType(DiagnosticsDetailSheet),
        findsNothing,
        reason: '宽屏不得再 push 整页详情',
      );
      expect(_logList, findsNothing, reason: '详情展开时右栏让位给详情');
      // 详情内容与窄屏 sheet 同源：级别标签 / tag / 消息 / 详情 JSON
      expect(find.text('ERROR'), findsOneWidget);
      expect(
        find.text('GET /api/workspace/download → 断流（已自动重试 1 次）'),
        findsOneWidget,
      );
      expect(find.text('描述'), findsOneWidget);
      // 详情落在右栏区域内（在左栏右侧、在右栏顶部工具行之下）
      final detailRect = tester.getRect(_wideDetail);
      expect(detailRect.left, greaterThanOrEqualTo(220));
      expect(
        detailRect.top,
        greaterThan(
          tester
              .getRect(find.byKey(const ValueKey('diagnostics-export-btn')))
              .top,
        ),
      );
      // 工具行（开关 / 搜索 / 计数 / 导出 / 清空）仍然原位可见
      expect(
        find.byKey(const ValueKey('diagnostics-switch-tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('diagnostics-search-field')),
        findsOneWidget,
      );
      expect(find.text('9 / 9'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('diagnostics-export-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('diagnostics-clear-btn')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('diagnostics-wide-detail-back')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_wideDetail, findsNothing);
      expect(_logList, findsOneWidget, reason: '返回后日志表回来');
    });

    testWidgets('宽屏：进入多选收起内联详情；再点行是勾选而非详情', (tester) async {
      await _pump(tester, service, size: _wide);

      await tester.tap(find.text('服务自检通过（第 1 项）'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_wideDetail, findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('diagnostics-enter-selection-btn')),
      );
      await tester.pump();
      expect(_wideDetail, findsNothing, reason: '多选态收起详情');
      expect(
        find.byKey(const ValueKey('diagnostics-copy-selected-btn')),
        findsOneWidget,
      );

      await tester.tap(find.text('服务自检通过（第 1 项）'));
      await tester.pump();
      expect(_wideDetail, findsNothing, reason: '多选态点行只勾选');
      expect(find.text('已选择 1 条'), findsOneWidget);
    });

    testWidgets('左栏筛选：点级别取消选中 → 该行回灰底灰字；点「全部」补齐', (tester) async {
      await _pump(tester, service, size: _wide);

      // 取消「信息」
      await tester.tap(_levelRow('I'));
      await tester.pump();
      expect(
        _textIn(tester, _levelRow('I'), 'I').style?.color?.toARGB32(),
        LightSurfaces.textSecondary.toARGB32(),
        reason: '未选中 → 灰字（chips 既有规则）',
      );
      expect(
        _blockTint(tester, _levelRow('I'), 'I').toARGB32(),
        LightSurfaces.page.toARGB32(),
      );
      expect(
        _textIn(tester, _levelRow('I'), '信息').style?.color?.toARGB32(),
        isNot(LightSurfaces.selectionForeground.toARGB32()),
      );
      // 其余级别仍显色
      expect(_blockTint(tester, _levelRow('W'), 'W').toARGB32(), 0xFFFFF4E8);
      // 计数不受级别筛选影响（级别分布读数）
      expect(
        find.descendant(of: _levelRow('I'), matching: find.text('3')),
        findsOneWidget,
      );
      // 右栏筛选计数随之下落：9 − 3（I）= 6
      expect(find.text('6 / 9'), findsOneWidget);

      // 「全部」补齐
      await tester.tap(find.byKey(const ValueKey('diagnostics-nav-all')));
      await tester.pump();
      expect(
        _textIn(tester, _levelRow('I'), 'I').style?.color?.toARGB32(),
        0xFF005FB8,
      );
      expect(find.text('9 / 9'), findsOneWidget);
    });

    testWidgets('左栏时间范围：切「今天」→ 选中态迁移且筛选生效', (tester) async {
      await _pump(tester, service, size: _wide);

      await tester.tap(_timeRow(DiagnosticsTimeFilter.today));
      await tester.pump();
      expect(
        _textIn(
          tester,
          _timeRow(DiagnosticsTimeFilter.today),
          '今天',
        ).style?.color,
        LightSurfaces.selectionForeground,
      );
      expect(
        _textIn(tester, _timeRow(DiagnosticsTimeFilter.all), '全部').style?.color,
        isNot(LightSurfaces.selectionForeground),
      );
      // 演示日志锚定今天（见 _demoService），选「今天」后按天过滤仍留全部
      // （时间过滤口径由 providers 承担，此处只钉「切换生效、选中态正确」）。
      expect(find.text('9 / 9'), findsOneWidget);
    });

    testWidgets('宽屏：关闭调试模式且无日志 → 无左栏（与窄屏「无日志不显示筛选」同口径）', (tester) async {
      await service.setEnabled(false);
      await service.clear();
      await _pump(tester, service, size: _wide);
      await tester.pump(const Duration(milliseconds: 700));

      expect(_rail, findsNothing, reason: '无日志且未开启 → 不出现筛选入口');
      expect(
        find.byKey(const ValueKey('diagnostics-switch-tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('diagnostics-search-field')),
        findsNothing,
      );
      expect(find.text('打开调试模式后开始记录'), findsOneWidget);
    });

    testWidgets('断点：899 无左栏（窄屏单列）／900 有左栏', (tester) async {
      await _pump(tester, service, size: const Size(899, 900));
      expect(_rail, findsNothing);
      expect(_wideDetail, findsNothing);

      await _pump(tester, service, size: const Size(900, 900));
      expect(_rail, findsOneWidget);
      expect(tester.getRect(_rail).width, 220);
    });

    testWidgets('窄屏 400：无左栏、chips 行仍是 9 枚（含时间「全部」）、五类元素与日志表原样', (tester) async {
      await _pump(tester, service, size: _narrow);

      expect(_rail, findsNothing, reason: '窄屏不得出现左栏筛选导航');
      expect(_wideDetail, findsNothing);

      // chips 行：5 枚级别 + 4 枚时间（顺序不变）
      for (final code in ['V', 'D', 'I', 'W', 'E']) {
        expect(
          find.byKey(ValueKey('diagnostics-filter-level-$code')),
          findsOneWidget,
        );
      }
      for (final filter in DiagnosticsTimeFilter.values) {
        expect(
          find.byKey(ValueKey('diagnostics-filter-time-${filter.name}')),
          findsOneWidget,
        );
      }
      // 右栏五类元素与日志表原样
      expect(
        find.byKey(const ValueKey('diagnostics-switch-tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('diagnostics-search-field')),
        findsOneWidget,
      );
      expect(find.text('9 / 9'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('diagnostics-export-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('diagnostics-clear-btn')),
        findsOneWidget,
      );
      expect(_logList, findsOneWidget);
      // 窄屏卡片/搜索框仍是 16 内边距（未被任何限宽/居中改动）
      expect(
        tester
            .getRect(find.byKey(const ValueKey('diagnostics-search-field')))
            .left,
        16,
      );

      // 窄屏点日志行 → 仍是整页 push
      await tester.tap(
        find.text('GET /api/workspace/download → 断流（已自动重试 1 次）'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DiagnosticsDetailSheet), findsOneWidget);
      expect(_wideDetail, findsNothing, reason: '窄屏不走右栏内联详情');
      expect(_logList, findsNothing, reason: '窄屏详情整页覆盖（既有行为）');
    });
  });
}
