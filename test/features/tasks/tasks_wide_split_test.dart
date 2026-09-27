import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';

import '../../helpers/fake_tasks_api.dart';

/// 批 4 · P4 守卫：任务页宽屏（≥900）**左 360 列表 + 右「任务输出」常驻**（撤 sheet）；
/// 窄屏（<900）原样保留底部 sheet，逐像素不变（像素级证据见交付报告里
/// `.shots/b4a` 前后对照工装：400 / 880 × 浅暗 × 默认/输出面板共 16 张逐像素一致，
/// 其中含「点行弹 sheet」与「点行换右栏」两条路径）。
///
/// 规范出处：`sketches/wide-pages-batch4-decision.html` §P4。
/// 「撤 sheet」只撤宽屏的**弹层外壳**：`_TaskOutputSheet` 组件保留（窄屏在用），
/// 宽屏右栏与窄屏 sheet 共用同一份正文（`_TaskOutputBody`）。

/// 每个任务返回各自内容的 fake（真 fake 的 `outputResponse` 是单值，
/// 无法区分「切任务是否真的换了右栏内容」）。
class _PerJobTasksApi extends FakeTasksApi {
  _PerJobTasksApi({super.jobs});

  @override
  Future<CronOutputResponse> fetchOutput(String jobId, {int? limit}) async {
    await super.fetchOutput(jobId, limit: limit);
    return CronOutputResponse(
      jobId: jobId,
      outputs: [
        CronOutputItem(filename: '$jobId.md', content: '输出内容 $jobId'),
      ],
    );
  }
}

CronJob _job(String id, {String? name, bool paused = false}) => CronJob(
  jobId: id,
  name: name ?? '任务 $id',
  prompt: '提示词 $id',
  schedule: const CronSchedule(expression: '0 9 * * *'),
  state: paused ? 'paused' : 'completed',
  enabled: !paused,
);

List<CronJob> _jobs() => [
  _job('j1', name: '每日仓库健康巡检'),
  _job('j2', name: '周报草稿生成'),
  _job('j3', name: '构建缓存清理', paused: true),
];

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  Brightness brightness = Brightness.light,
  FakeTasksApi? api,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        tasksApiFactoryProvider.overrideWithValue(
          (_) => api ?? _PerJobTasksApi(jobs: _jobs()),
        ),
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: const TasksPage(),
      ),
    ),
  );
  // 首帧（AsyncLoading）→ AsyncData → 右栏 post-frame 取输出
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// 左栏容器（窄屏**不应**存在）。
Finder get _rail => find.byKey(const ValueKey('tasks-rail'));

/// 右栏「任务输出」常驻面板（窄屏**不应**存在）。
Finder get _pane => find.byKey(const ValueKey('tasks-output-pane'));

/// 窄屏底部 sheet（宽屏**不应**存在）。
Finder get _sheet => find.byKey(const ValueKey('tasks-output-sheet'));

Finder _railRow(String id) => find.byKey(ValueKey('tasks-rail-row-$id'));

/// 取某任务左栏行的名字文字（断言 L2 选中态用）。
Text _railName(WidgetTester tester, String id, String name) =>
    tester.widget<Text>(
      find.descendant(of: _railRow(id), matching: find.text(name)),
    );

/// 取某任务左栏行自身的按钮（断言 L2 选中底；行内还有行菜单按钮，故按 key 取）。
CupertinoButton _railTap(WidgetTester tester, String id) =>
    tester.widget<CupertinoButton>(
      find.byKey(ValueKey('tasks-rail-tap-$id')),
    );

void main() {
  group('任务页宽屏双栏（批 4 · P4）', () {
    testWidgets('宽屏 1280：左 360 列表 + 右「任务输出」常驻，首批任务输出自动上屏', (tester) async {
      final api = _PerJobTasksApi(jobs: _jobs());
      await _pump(tester, size: const Size(1280, 800), api: api);

      expect(_rail, findsOneWidget, reason: '宽屏应有左栏');
      final rail = tester.getRect(_rail);
      expect(rail.width, 360, reason: '左栏固定 360');
      expect(rail.left, 0, reason: '左栏贴页面左缘');

      // 左栏：三条任务 + 两组分组标题（正常 / 已暂停，与窄屏同口径）
      for (final id in ['j1', 'j2', 'j3']) {
        expect(_railRow(id), findsOneWidget, reason: '$id 应在左栏');
      }
      expect(
        find.descendant(of: _rail, matching: find.text('正常（2）')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _rail, matching: find.text('已暂停（1）')),
        findsOneWidget,
      );

      // 右栏：常驻面板 + 标题 + 输出正文；宽屏**不弹 sheet**
      expect(_pane, findsOneWidget, reason: '宽屏应有常驻输出面板');
      expect(_sheet, findsNothing, reason: '宽屏不再走 sheet');
      expect(find.text('任务输出'), findsOneWidget);
      expect(find.text('输出内容 j1'), findsOneWidget, reason: '首个任务输出常驻上屏');
      expect(find.text('输出内容 j2'), findsNothing);

      // 首批输出只取一次（post-frame 补帧，不在 build 里发请求）
      expect(api.outputCalls, ['j1:5']);

      // 右栏在左栏右侧，且面板宽度吃满剩余空间
      final pane = tester.getRect(_pane);
      expect(pane.left, greaterThanOrEqualTo(rail.right - 0.01));
      expect(pane.width, closeTo(1280 - 360, 1));
    });

    testWidgets('宽屏：切任务即换右栏内容（各任务的输出互不串档）', (tester) async {
      final api = _PerJobTasksApi(jobs: _jobs());
      await _pump(tester, size: const Size(1280, 800), api: api);

      expect(find.text('输出内容 j1'), findsOneWidget);

      await tester.tap(_railRow('j2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('输出内容 j2'), findsOneWidget, reason: '切到 j2 应显示 j2 输出');
      expect(find.text('输出内容 j1'), findsNothing);
      expect(api.outputCalls, ['j1:5', 'j2:5']);
    });

    testWidgets('宽屏：选中态 L2（灰底 + #005FB8 蓝字）', (tester) async {
      await _pump(tester, size: const Size(1280, 800));

      expect(
        _railName(tester, 'j1', '每日仓库健康巡检').style?.color,
        const Color(0xFF005FB8),
      );
      expect(_railTap(tester, 'j1').color, LightSurfaces.selectedSurface);
      expect(_railTap(tester, 'j2').color, CupertinoColors.transparent);

      await tester.tap(_railRow('j2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        _railName(tester, 'j2', '周报草稿生成').style?.color,
        const Color(0xFF005FB8),
      );
      expect(_railTap(tester, 'j2').color, LightSurfaces.selectedSurface);
      expect(
        _railName(tester, 'j1', '每日仓库健康巡检').style?.color,
        const Color(0xFF3A3A3C),
        reason: '未选中行回落左栏常规文字色',
      );
    });

    testWidgets('宽屏：行菜单「查看输出」不弹 sheet，只切右栏', (tester) async {
      final api = _PerJobTasksApi(jobs: _jobs());
      await _pump(tester, size: const Size(1280, 800), api: api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j2')));
      await tester.pumpAndSettle();
      expect(find.text('查看输出'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tasks-action-output')));
      await tester.pumpAndSettle();

      expect(_sheet, findsNothing, reason: '宽屏菜单里的「查看输出」也不弹层');
      expect(find.text('输出内容 j2'), findsOneWidget);
      expect(api.outputCalls, ['j1:5', 'j2:5']);
    });

    testWidgets('宽屏：行菜单其余操作原样可用（撤的只是输出 sheet）', (tester) async {
      final api = _PerJobTasksApi(jobs: _jobs());
      await _pump(tester, size: const Size(1280, 800), api: api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      expect(find.text('运行'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tasks-action-run')));
      await tester.pumpAndSettle();
      expect(api.runCalls, ['j1']);
    });

    testWidgets('断点 899 为窄屏：无左栏 / 无面板，点行弹底部 sheet', (tester) async {
      await _pump(tester, size: const Size(899, 900));

      expect(_rail, findsNothing, reason: '899 < 900 ⇒ 窄屏');
      expect(_pane, findsNothing);
      expect(_sheet, findsNothing, reason: '未点行时不该有 sheet');

      await tester.tap(find.byKey(const ValueKey('tasks-row-j1')));
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget, reason: '窄屏点行仍是底部 sheet');
      expect(find.text('输出内容 j1'), findsOneWidget);
    });

    testWidgets('断点 900 为宽屏：左栏 + 常驻面板，点行不弹 sheet', (tester) async {
      await _pump(tester, size: const Size(900, 900));

      expect(_rail, findsOneWidget, reason: '900 ≥ 900 ⇒ 宽屏');
      expect(_pane, findsOneWidget);
      expect(_sheet, findsNothing);

      await tester.tap(_railRow('j2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_sheet, findsNothing, reason: '宽屏点行不弹 sheet');
      expect(find.text('输出内容 j2'), findsOneWidget);
    });

    testWidgets('窄屏 800：sheet 路径与组件原样保留（含关闭按钮与 480 限宽）', (tester) async {
      final api = _PerJobTasksApi(jobs: _jobs());
      await _pump(tester, size: const Size(800, 1200), api: api);

      expect(_rail, findsNothing, reason: '窄屏无左栏');
      expect(_pane, findsNothing, reason: '窄屏无常驻面板');

      await tester.tap(find.byKey(const ValueKey('tasks-row-j1')));
      await tester.pumpAndSettle();

      expect(_sheet, findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-output-close')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
        ),
        findsOneWidget,
        reason: '浅色 sheet 的 480 限宽保留',
      );
      expect(find.text('输出内容 j1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tasks-output-close')));
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
    });

    testWidgets('窄屏 800：任务行几何逐像素不变（卡片外边距 20 / 行内 16 内缩）', (tester) async {
      await _pump(tester, size: const Size(800, 1200));

      final row = tester.getRect(find.byKey(const ValueKey('tasks-row-j1')));
      // 20 = `CupertinoListSection.insetGrouped` 默认水平外边距（实测值）；
      // 这条断言钉的是「窄屏几何未被我改动」—— 改动前后 400 / 880 × 浅暗 ×
      // 默认/输出面板共 16 张真渲染逐像素一致（见交付报告 .shots/b4a 对照）。
      expect(row.left, 20, reason: '窄屏卡片左缘 = 视口 + 20');
      expect(800 - row.right, 20, reason: '窄屏卡片右缘 = 视口 − 20（左右相等）');
    });
  });
}
