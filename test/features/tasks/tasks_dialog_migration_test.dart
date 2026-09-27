import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/widgets/hermes_dialog.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/features/workspace/workspace_page.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';

import '../../helpers/fake_download_service.dart';
import '../../helpers/fake_tasks_api.dart';
import '../../helpers/fake_workspace_api.dart';

// ---------------------------------------------------------------------------
// 批 5 · C3 守卫 —— 其余 feature 弹窗调用点迁到 D1 四档宽（`showHermesDialog`）。
//
// 三层，逐层钉不同的东西：
//
// 1. **源码契约**：11 个受迁移文件里不得再出现 `showCupertinoDialog(` /
//    `CupertinoAlertDialog(` / `CupertinoDialogAction(` ——
//    「半迁移」（标题正文换了、动作还留着 CupertinoDialogAction）也会被抓。
// 2. **逐处分档表**：每处 `kind:` 与语义分档一一对应。拿 `kind.width` 比自己
//    是自证；这里写死**期望的档位名**，改错档 → 精确指名报错。
// 3. **真渲染**：宽屏（1280）出 `HermesDialogCard` 且**卡片实际布局宽度 ==
//    档位绝对值**（380/560，不拿 `kind.width` 自证）、系统 alert 必须不在；
//    窄屏（800）反过来 —— 仍是 `CupertinoAlertDialog`（内部 270 定宽），
//    一张卡片都不许出现。两个视口都走**真实调用点**（真页面 + 真触发器），
//    不构造测试专用弹窗。
//
// 为什么窄屏要盯 `CupertinoPopupSurface` 的 270：`CupertinoAlertDialog` 的宽度
// 写死在它自己内部（定宽 `SizedBox`，不是约束）—— 这正是「宽屏必须自绘卡片」
// 的技术原因，也是「窄屏逐像素不变」最容易被人「顺手加个 SizedBox」破坏的地方。
// ---------------------------------------------------------------------------

/// 宽屏（≥900）视口。
const Size _kWide = Size(1280, 800);

/// 窄屏（<900）视口 —— 即 flutter_test 默认 800×600。
const Size _kNarrow = Size(800, 600);

/// 受迁移文件清单（与任务书文件级分区逐字对应）。
const List<String> _migratedFiles = <String>[
  'lib/features/tasks/tasks_page.dart',
  'lib/features/workspace/workspace_page.dart',
  'lib/features/workspace_manager/workspace_manager_page.dart',
  'lib/features/workspace_manager/file_preview_page.dart',
  'lib/features/projects/project_picker_sheet.dart',
  'lib/features/kanban/kanban_page.dart',
  'lib/features/insights/insights_page.dart',
  'lib/features/skills/skills_page.dart',
  'lib/features/diagnostics/diagnostics_page.dart',
  'lib/features/diagnostics/diagnostics_detail_sheet.dart',
];

/// **逐处分档表**（文件 → 文件内按出现顺序的档位）。
///
/// 分档口径（D1）：
/// - `confirm`（380）—— 确认 / 警告 / 清空 / 移除；
/// - `picker`（460）—— 单选 / 列表型；
/// - `form`（560）—— 含输入框等可编辑字段；
/// - `wideForm`（760）—— 宽表单 / 长文预览。
///
/// 本批实点用到的两档：confirm 16 处、form 2 处（两个重命名 / 新建项目输入框）。
/// `picker` / `wideForm` 本批无天然用点（无单选列表、无长文预览）。
const Map<String, List<String>> _kExpectedKinds = <String, List<String>>{
  'lib/features/tasks/tasks_page.dart': <String>['confirm', 'confirm'],
  'lib/features/workspace/workspace_page.dart': <String>[
    'confirm', // 删除文件
    'form', // 重命名（输入框）
    'confirm', // 提示 / 错误
  ],
  'lib/features/workspace_manager/workspace_manager_page.dart': <String>[
    'form', // 重命名工作区（输入框）
    'confirm', // 移除工作区
    'confirm', // 提示 / 错误
  ],
  'lib/features/workspace_manager/file_preview_page.dart': <String>['confirm'],
  'lib/features/projects/project_picker_sheet.dart': <String>[
    'form', // 新建 / 重命名项目（输入框）
    'confirm', // 删除项目
  ],
  'lib/features/kanban/kanban_page.dart': <String>[
    'confirm', // 看板页操作失败
    'confirm', // 卡片详情页操作失败
  ],
  'lib/features/insights/insights_page.dart': <String>['confirm'],
  'lib/features/skills/skills_page.dart': <String>['confirm'],
  'lib/features/diagnostics/diagnostics_page.dart': <String>[
    'confirm', // 清空日志
    'confirm', // 复制 / 导出提示
  ],
  'lib/features/diagnostics/diagnostics_detail_sheet.dart': <String>['confirm'],
};

/// 从源码里按出现顺序抽出 `kind: HermesDialogKind.xxx`。
List<String> _kindsOf(String source) => RegExp(
  r'kind:\s*HermesDialogKind\.(\w+)',
).allMatches(source).map((m) => m.group(1)!).toList();

CronJob _job(String id) => CronJob(
  jobId: id,
  name: '任务 $id',
  prompt: '提示词 $id',
  schedule: const CronSchedule(expression: '0 9 * * *'),
  enabled: true,
  state: 'completed',
);

WorkspaceEntry _entry(String name) =>
    WorkspaceEntry(name: name, path: name, size: 1024);

/// 挂定时任务页（真页面 + fake API）。
Future<void> _pumpTasks(
  WidgetTester tester,
  Size size,
  FakeTasksApi api,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        tasksApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: const CupertinoApp(
        theme: CupertinoThemeData(brightness: Brightness.light),
        home: TasksPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// 挂工作区页（真页面 + fake API）。
Future<void> _pumpWorkspace(
  WidgetTester tester,
  Size size,
  FakeWorkspaceApi api,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        workspaceApiFactoryProvider.overrideWithValue((_) => api),
        ...createDownloadTestOverrides(),
      ],
      child: const CupertinoApp(
        theme: CupertinoThemeData(brightness: Brightness.light),
        home: WorkspacePage(sessionId: 's1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// 行菜单 → 目标动作（宽窄屏同一套 key）。
Future<void> _openRowAction(
  WidgetTester tester, {
  required Key rowActions,
  required Key action,
}) async {
  await tester.tap(find.byKey(rowActions));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(action));
  await tester.pumpAndSettle();
}

Future<void> _openTasksDelete(WidgetTester tester) => _openRowAction(
  tester,
  rowActions: const ValueKey('tasks-actions-j1'),
  action: const ValueKey('tasks-action-delete'),
);

Future<void> _openWorkspaceRename(WidgetTester tester) => _openRowAction(
  tester,
  rowActions: const ValueKey('workspace-actions-a.txt'),
  action: const ValueKey('workspace-action-rename'),
);

Future<void> _openWorkspaceDelete(WidgetTester tester) => _openRowAction(
  tester,
  rowActions: const ValueKey('workspace-actions-a.txt'),
  action: const ValueKey('workspace-action-delete'),
);

/// 宽屏断言：卡片在、系统 alert 不在、卡片实际宽度 == [expected]。
void _expectWideCard(WidgetTester tester, double expected) {
  expect(find.byType(HermesDialogCard), findsOneWidget);
  expect(find.byType(CupertinoAlertDialog), findsNothing);
  final card = find.byKey(kHermesDialogCardKey);
  expect(card, findsOneWidget);
  expect(
    tester.getSize(card).width,
    expected,
    reason: '宽屏卡片实际布局宽度必须是 $expected（档位绝对值，非 kind.width 自证）',
  );
}

/// 窄屏断言：仍是系统 alert（270 定宽）、卡片一个都不许有。
void _expectNarrowAlert(WidgetTester tester) {
  expect(find.byType(HermesDialogCard), findsNothing);
  expect(find.byKey(kHermesDialogCardKey), findsNothing);
  expect(find.byType(CupertinoAlertDialog), findsOneWidget);
  expect(tester.getSize(find.byType(CupertinoPopupSurface)).width, 270.0);
}

void main() {
  group('C3 源码契约 · 迁移完整性', () {
    for (final path in _migratedFiles) {
      test('$path 不再直连 Cupertino 弹窗件', () {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('showCupertinoDialog('),
          isFalse,
          reason: '$path 仍有 showCupertinoDialog 调用点未迁移',
        );
        expect(
          source.contains('CupertinoAlertDialog('),
          isFalse,
          reason: '$path 仍直接构造 CupertinoAlertDialog',
        );
        expect(
          source.contains('CupertinoDialogAction('),
          isFalse,
          reason: '$path 仍有 CupertinoDialogAction（半迁移：动作没换成 HermesDialogAction）',
        );
        expect(
          source.contains('showHermesDialog'),
          isTrue,
          reason: '$path 应当经 showHermesDialog 出弹窗',
        );
      });
    }

    test('迁移文件数 == 10（11 个分区文件里 git_page 无 Cupertino 弹窗调用点）', () {
      expect(_migratedFiles.length, 10);
    });
  });

  group('C3 逐处分档表 · kind 即契约', () {
    _kExpectedKinds.forEach((path, expected) {
      test('$path → ${expected.join(" / ")}', () {
        final actual = _kindsOf(File(path).readAsStringSync());
        expect(
          actual,
          expected,
          reason: '$path 的 kind 序列必须与语义分档表逐处一致（改错档即变红）',
        );
      });
    });

    test('全仓只用四档成员名（无拼写漂移的档位）', () {
      const whitelist = <String>{'confirm', 'picker', 'form', 'wideForm'};
      for (final path in _migratedFiles) {
        for (final kind in _kindsOf(File(path).readAsStringSync())) {
          expect(
            whitelist,
            contains(kind),
            reason: '$path 出现非四档成员：$kind',
          );
        }
      }
    });
  });

  group('C3 真渲染 · 宽屏出卡片且宽=档位 / 窄屏仍是系统 alert', () {
    group('tasks_page.dart', () {
      testWidgets('宽屏 1280 · 删除任务确认 → 380 卡片，确认后仍调删除 API', (
        tester,
      ) async {
        final api = FakeTasksApi(jobs: <CronJob>[_job('j1')]);
        await _pumpTasks(tester, _kWide, api);
        await _openTasksDelete(tester);

        _expectWideCard(tester, 380.0);
        expect(find.text('删除任务'), findsOneWidget);
        // 宽屏动作件是自绘 `CupertinoButton`（带同一颗 key），可点。
        final confirm = tester.widget<CupertinoButton>(
          find.byKey(const ValueKey('tasks-delete-confirm')),
        );
        expect(confirm.onPressed, isNotNull);
        await tester.tap(find.byKey(const ValueKey('tasks-delete-confirm')));
        await tester.pumpAndSettle();
        expect(api.deleteCalls, <String>['j1']);
      });

      testWidgets('宽屏 1280 · 操作失败告警 → 380 卡片', (tester) async {
        final api = FakeTasksApi(jobs: <CronJob>[_job('j1')]);
        api.runError = HttpException(500, null, message: '触发服务不可用');
        await _pumpTasks(tester, _kWide, api);
        await _openRowAction(
          tester,
          rowActions: const ValueKey('tasks-actions-j1'),
          action: const ValueKey('tasks-action-run'),
        );

        _expectWideCard(tester, 380.0);
        expect(find.text('操作失败'), findsOneWidget);
      });

      testWidgets('窄屏 800 · 删除任务确认 → 仍是系统 alert（270）', (tester) async {
        final api = FakeTasksApi(jobs: <CronJob>[_job('j1')]);
        await _pumpTasks(tester, _kNarrow, api);
        await _openTasksDelete(tester);

        _expectNarrowAlert(tester);
        expect(find.text('删除任务'), findsOneWidget);
        expect(
          tester
              .widget<CupertinoDialogAction>(
                find.byKey(const ValueKey('tasks-delete-confirm')),
              )
              .onPressed,
          isNotNull,
        );
      });

      testWidgets('窄屏 800 · 操作失败告警 → 仍是系统 alert（270）', (tester) async {
        final api = FakeTasksApi(jobs: <CronJob>[_job('j1')]);
        api.runError = HttpException(500, null, message: '触发服务不可用');
        await _pumpTasks(tester, _kNarrow, api);
        await _openRowAction(
          tester,
          rowActions: const ValueKey('tasks-actions-j1'),
          action: const ValueKey('tasks-action-run'),
        );

        _expectNarrowAlert(tester);
        expect(find.text('操作失败'), findsOneWidget);
      });
    });

    group('workspace_page.dart', () {
      testWidgets('宽屏 1280 · 重命名（form）→ 560 卡片 + 输入框可用', (tester) async {
        final api = FakeWorkspaceApi(
          directories: <String, List<WorkspaceEntry>>{
            '.': <WorkspaceEntry>[_entry('a.txt')],
          },
        );
        await _pumpWorkspace(tester, _kWide, api);
        await _openWorkspaceRename(tester);

        _expectWideCard(tester, 560.0);
        expect(
          find.byKey(const ValueKey('workspace-rename-field')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('workspace-rename-field')),
          'b.txt',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('workspace-rename-save')));
        await tester.pumpAndSettle();
        expect(api.renameCalls, <String>['s1|a.txt|b.txt']);
      });

      testWidgets('宽屏 1280 · 删除文件 → 380 卡片，确认后仍调删除 API', (tester) async {
        final api = FakeWorkspaceApi(
          directories: <String, List<WorkspaceEntry>>{
            '.': <WorkspaceEntry>[_entry('a.txt')],
          },
        );
        await _pumpWorkspace(tester, _kWide, api);
        await _openWorkspaceDelete(tester);

        _expectWideCard(tester, 380.0);
        expect(find.text('删除文件'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('workspace-delete-confirm')),
        );
        await tester.pumpAndSettle();
        expect(api.deleteCalls, <String>['s1|a.txt']);
      });

      testWidgets('窄屏 800 · 重命名 → 仍是系统 alert（270）', (tester) async {
        final api = FakeWorkspaceApi(
          directories: <String, List<WorkspaceEntry>>{
            '.': <WorkspaceEntry>[_entry('a.txt')],
          },
        );
        await _pumpWorkspace(tester, _kNarrow, api);
        await _openWorkspaceRename(tester);

        _expectNarrowAlert(tester);
        expect(
          find.byKey(const ValueKey('workspace-rename-field')),
          findsOneWidget,
        );
      });

      testWidgets('窄屏 800 · 删除文件 → 仍是系统 alert（270）', (tester) async {
        final api = FakeWorkspaceApi(
          directories: <String, List<WorkspaceEntry>>{
            '.': <WorkspaceEntry>[_entry('a.txt')],
          },
        );
        await _pumpWorkspace(tester, _kNarrow, api);
        await _openWorkspaceDelete(tester);

        _expectNarrowAlert(tester);
        expect(find.text('删除文件'), findsOneWidget);
      });
    });
  });
}
