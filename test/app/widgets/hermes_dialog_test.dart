import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/widgets/hermes_dialog.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/features/downloads/download_confirm_dialog.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_tasks_api.dart';

// ---------------------------------------------------------------------------
// 批 5A 弹窗基础设施守卫（D1 四档宽 / D2 表单横排 / 窄屏逐像素不变）。
//
// 这些守卫钉死的是**结构性契约**，不是「看起来差不多」：
// - 四档宽：卡片实际布局宽度 == 380/460/560/760，且水平垂直都居中；
// - 窄屏原路径：仍出 `CupertinoAlertDialog`（内含 270 定宽），
//   路由是 `CupertinoDialogRoute` 而**不是** `HermesDialogRoute`；
// - 表单横排：宽屏 label 槽宽 88 + 与控件同一行；窄屏竖排 + 间距 6；
// - 两个样板弹窗（下载确认框 / 新建定时任务）各自在宽窄两档走对路径。
// ---------------------------------------------------------------------------

/// 宽屏（≥900）视口。
const Size _kWide = Size(1280, 800);

/// 窄屏（<900）视口 —— 就是 flutter_test 默认 800×600。
const Size _kNarrow = Size(800, 600);

/// 四档宽度的**绝对**期望值（380/460/560/760）。
///
/// 刻意写死、不写 `kind.width`：拿 `kind.width` 比 `kind.width` 是**自证**
/// —— 枚举值被改坏时守卫照样全绿（批 5A 的 RED 校验实测踩过这个坑：
/// 把 form 从 560 改成 480，只有这张表能发现）。
const Map<HermesDialogKind, double> _kWaist = <HermesDialogKind, double>{
  HermesDialogKind.confirm: 380.0,
  HermesDialogKind.picker: 460.0,
  HermesDialogKind.form: 560.0,
  HermesDialogKind.wideForm: 760.0,
};

/// 挂一个最小宿主：真主题 + 真中文本地化 + 一个开弹窗的按钮。
Future<void> _pumpDialogHost(
  WidgetTester tester, {
  required Size size,
  required Future<void> Function(BuildContext context) onOpen,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      // 每次挂宿主都换新 key：同类型根件会被框架「更新」而非重建，
      // 上一档留下的弹窗路由会赖在 Navigator 上（宿主复用陷阱）。
      key: UniqueKey(),
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        ...overrides,
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: CupertinoPageScaffold(
          child: Builder(
            builder: (context) => Center(
              child: CupertinoButton(
                key: const ValueKey('open-dialog'),
                onPressed: () => onOpen(context),
                child: const Text('打开弹窗'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 开弹窗 → 结算入场转场（CupertinoDialogRoute 弹簧 ≈250ms）。
Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-dialog')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 标准「确认框」内容（标题 + 正文 + 取消/确定）。
Future<void> _showConfirm(
  BuildContext context,
  HermesDialogKind kind, {
  void Function(BuildContext context)? onResult,
  bool Function()? canConfirm,
}) {
  return showHermesDialog<void>(
    context,
    kind: kind,
    title: (_) => const Text('删除会话'),
    content: (_) => const Text('删除选中的 3 个会话？此操作不可撤销。'),
    actions: <HermesDialogAction>[
      HermesDialogAction(
        key: const ValueKey('dialog-cancel'),
        builder: (_) => const Text('取消'),
        onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
      ),
      HermesDialogAction(
        key: const ValueKey('dialog-confirm'),
        isDefaultAction: true,
        builder: (_) => const Text('删除'),
        enabled: canConfirm,
        onPressed: (dialogContext) {
          onResult?.call(dialogContext);
          Navigator.of(dialogContext).pop();
        },
      ),
    ],
  );
}

void main() {
  group('D1 · 四档宽度即契约', () {
    test('枚举声明 380 / 460 / 560 / 760（与设计稿逐值对齐）', () {
      expect(
        HermesDialogKind.values.map((k) => k.width).toList(),
        <double>[380.0, 460.0, 560.0, 760.0],
      );
      expect(_kWaist.values.toList(), <double>[380.0, 460.0, 560.0, 760.0]);
    });
  });

  group('D1 · 宽屏四档各自命中', () {
    for (final kind in HermesDialogKind.values) {
      testWidgets('宽屏 1280 · ${kind.name} → ${kind.width.toInt()} 宽居中卡片', (
        tester,
      ) async {
        await _pumpDialogHost(
          tester,
          size: _kWide,
          onOpen: (context) => _showConfirm(context, kind),
        );
        await _openDialog(tester);

        // 卡片在，系统 alert 不在（宽屏绝不走 270 定宽那条路）。
        expect(find.byType(HermesDialogCard), findsOneWidget);
        expect(find.byType(CupertinoAlertDialog), findsNothing);

        final card = find.byKey(kHermesDialogCardKey);
        expect(card, findsOneWidget);
        // 绝对宽度（不拿 kind.width 自证）。
        expect(tester.getSize(card).width, _kWaist[kind]);

        // 居中：卡片几何中心 == 视口中心。
        final center = tester.getCenter(card);
        expect(center.dx, closeTo(_kWide.width / 2, 1.0));
        expect(center.dy, closeTo(_kWide.height / 2, 1.0));

        // 路由类型可判（后续批次找宽屏特化入口靠它）。
        expect(
          ModalRoute.of(tester.element(card)),
          isA<HermesDialogRoute<void>>(),
        );
      });
    }

    testWidgets('宽屏：同一张卡里两动作等宽横排（D1 底部动作行）', (tester) async {
      await _pumpDialogHost(
        tester,
        size: _kWide,
        onOpen: (context) => _showConfirm(context, HermesDialogKind.confirm),
      );
      await _openDialog(tester);

      final cancel = tester.getRect(find.byKey(const ValueKey('dialog-cancel')));
      final confirm = tester.getRect(
        find.byKey(const ValueKey('dialog-confirm')),
      );
      expect(cancel.width, closeTo(confirm.width, 1.0));
      expect(cancel.center.dy, closeTo(confirm.center.dy, 1.0));
      // 等宽横排 = 两个动作都在同一行上（不是上下堆叠）。
      expect(cancel.left, lessThan(confirm.left));
      expect(cancel.bottom, closeTo(confirm.bottom, 1.0));
    });
  });

  group('D1 · 窄屏仍走原路径（逐像素不变）', () {
    testWidgets('窄屏 800：CupertinoAlertDialog + 270 定宽，不出卡片', (tester) async {
      await _pumpDialogHost(
        tester,
        size: _kNarrow,
        onOpen: (context) => _showConfirm(context, HermesDialogKind.confirm),
      );
      await _openDialog(tester);

      // 卡片一个都不能有。
      expect(find.byType(HermesDialogCard), findsNothing);
      expect(find.byKey(kHermesDialogCardKey), findsNothing);

      // 原路径仍在：系统 alert。
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);

      // 宽度仍是 Cupertino 自己的 270 —— 且**不可从外面设**
      // （`CupertinoAlertDialog` 内部是 `SizedBox(width: 270)` 定宽，不是约束）。
      // 这正是宽屏必须自绘卡片的技术原因，钉在此处防止有人"顺手"套一个 SizedBox。
      expect(tester.getSize(find.byType(CupertinoPopupSurface)).width, 270.0);

      final route = ModalRoute.of(
        tester.element(find.byType(CupertinoAlertDialog)),
      );
      expect(route, isA<CupertinoDialogRoute<void>>());
      expect(route, isNot(isA<HermesDialogRoute<void>>()));
    });

    testWidgets('窄屏：四档 kind 全被忽略（宽度不随 kind 变）', (tester) async {
      for (final kind in HermesDialogKind.values) {
        await _pumpDialogHost(
          tester,
          size: _kNarrow,
          onOpen: (context) => _showConfirm(context, kind),
        );
        await _openDialog(tester);
        expect(find.byType(HermesDialogCard), findsNothing);
        expect(
          tester.getSize(find.byType(CupertinoPopupSurface)).width,
          270.0,
          reason: '${kind.name} 在窄屏不应改变系统弹窗宽度',
        );
        await tester.tap(find.byKey(const ValueKey('dialog-cancel')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
    });
  });

  group('HermesDialogAction · 语义', () {
    testWidgets('onPressed 收 dialog context，pop 结果回传调用点', (tester) async {
      bool? result;
      await _pumpDialogHost(
        tester,
        size: _kWide,
        onOpen: (context) async {
          result = await showHermesDialog<bool>(
            context,
            kind: HermesDialogKind.confirm,
            title: (_) => const Text('删除会话'),
            content: (_) => const Text('不可撤销'),
            actions: <HermesDialogAction>[
              HermesDialogAction(
                builder: (_) => const Text('取消'),
                onPressed: (dialogContext) =>
                    Navigator.of(dialogContext).pop(false),
              ),
              HermesDialogAction(
                isDefaultAction: true,
                builder: (_) => const Text('删除'),
                onPressed: (dialogContext) =>
                    Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );
      await _openDialog(tester);

      await tester.tap(find.text('删除'));
      // 退场是 Cupertino 弹簧模拟，结算时间不定 —— 直接等帧静止，
      // 路由完成 dismissed 才会 `didComplete(result)`。
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.byType(HermesDialogCard), findsNothing);
    });

    testWidgets('禁用态：宽屏卡片动作不可点、窄屏 alert 动作不可点', (tester) async {
      // 宽屏：动作件是自绘的 `CupertinoButton`（`CupertinoDialogAction`
      // 在 alert 之外没有手势识别器，故不是它）。
      await _pumpDialogHost(
        tester,
        size: _kWide,
        onOpen: (context) => _showConfirm(
          context,
          HermesDialogKind.form,
          canConfirm: () => false,
        ),
      );
      await _openDialog(tester);
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('dialog-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('dialog-cancel')),
            )
            .onPressed,
        isNotNull,
      );

      // 窄屏：动作件仍是 `CupertinoDialogAction`，禁用态一致。
      await _pumpDialogHost(
        tester,
        size: _kNarrow,
        onOpen: (context) => _showConfirm(
          context,
          HermesDialogKind.form,
          canConfirm: () => false,
        ),
      );
      await _openDialog(tester);
      expect(find.byType(HermesDialogCard), findsNothing);
      expect(
        tester
            .widget<CupertinoDialogAction>(
              find.byKey(const ValueKey('dialog-confirm')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('rebuildOn 触发后动作可用态跟着变', (tester) async {
      final changes = ValueNotifier<bool>(false);
      addTearDown(changes.dispose);
      await _pumpDialogHost(
        tester,
        size: _kWide,
        onOpen: (context) => showHermesDialog<void>(
          context,
          kind: HermesDialogKind.form,
          rebuildOn: changes,
          title: (_) => const Text('新建任务'),
          content: (_) => const Text('字段…'),
          actions: <HermesDialogAction>[
            HermesDialogAction(
              key: const ValueKey('dialog-save'),
              isDefaultAction: true,
              builder: (_) => const Text('保存'),
              enabled: () => changes.value,
              onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
      await _openDialog(tester);

      CupertinoButton saveAction() => tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('dialog-save')),
      );
      expect(saveAction().onPressed, isNull);

      changes.value = true;
      await tester.pump();

      expect(saveAction().onPressed, isNotNull);
    });
  });

  group('D2 · HermesFormRow 横排只在宽屏', () {
    Future<void> pumpRow(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 560,
                child: HermesFormRow(
                  label: Text('任务名称', key: ValueKey('row-label')),
                  child: SizedBox(
                    key: ValueKey('row-control'),
                    height: 34,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('宽屏：label 槽 88 + 间距 12 + 与控件同一行', (tester) async {
      await pumpRow(tester, _kWide);
      final label = tester.getRect(find.byKey(const ValueKey('row-label')));
      final control = tester.getRect(
        find.byKey(const ValueKey('row-control')),
      );

      // label 贴行首，控件左沿 = 88 + 12。
      expect(label.left, closeTo(0, 0.01));
      expect(control.left, closeTo(kFormLabelWidth + kFormLabelGap, 0.01));
      // 同行：竖直中心一致（默认 center 对齐）。
      expect(label.center.dy, closeTo(control.center.dy, 0.01));
      // 控件吃掉剩余宽度。
      expect(control.width, closeTo(560 - kFormLabelWidth - kFormLabelGap, 0.01));
    });

    testWidgets('窄屏：label 上 / 控件下（间距 6）+ 控件满宽', (tester) async {
      await pumpRow(tester, _kNarrow);
      final label = tester.getRect(find.byKey(const ValueKey('row-label')));
      final control = tester.getRect(
        find.byKey(const ValueKey('row-control')),
      );

      expect(label.left, closeTo(0, 0.01));
      expect(control.left, closeTo(0, 0.01));
      // 竖排：控件顶沿 - label 底沿 == kFormStackedGap。
      expect(control.top - label.bottom, closeTo(kFormStackedGap, 0.01));
      // 控件满宽（560）。
      expect(control.width, closeTo(560, 0.01));
    });

    testWidgets('窄屏：alignment 参数不参与（仍是竖排）', (tester) async {
      tester.view.physicalSize = _kNarrow;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: HermesFormRow(
              alignment: CrossAxisAlignment.start,
              label: Text('提示词', key: ValueKey('row-label')),
              child: SizedBox(key: ValueKey('row-control'), height: 34),
            ),
          ),
        ),
      );
      await tester.pump();
      final label = tester.getRect(find.byKey(const ValueKey('row-label')));
      final control = tester.getRect(
        find.byKey(const ValueKey('row-control')),
      );
      expect(control.top, greaterThan(label.bottom));
    });
  });

  group('样板落地 · 下载确认框（D1 380）', () {
    Future<void> pumpLauncher(WidgetTester tester, Size size) async {
      await _pumpDialogHost(
        tester,
        size: size,
        onOpen: (context) => showDownloadConfirmationDialog(
          context,
          fileName: 'report.pdf',
          mimeType: 'application/pdf',
          expectedBytes: 1024 * 1024,
        ),
      );
      await _openDialog(tester);
    }

    testWidgets('宽屏 1280：380 卡片 + 内容齐全', (tester) async {
      await pumpLauncher(tester, _kWide);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(tester.getSize(find.byKey(kHermesDialogCardKey)).width, 380.0);
      expect(find.text('下载文件'), findsOneWidget);
      expect(find.text('名称：report.pdf'), findsOneWidget);
      expect(find.text('信息：文档'), findsOneWidget);
      expect(find.text('值：1.0 MB'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('开始下载'), findsOneWidget);
    });

    testWidgets('窄屏 800：仍是系统 alert（逐像素不变）', (tester) async {
      await pumpLauncher(tester, _kNarrow);
      expect(find.byType(HermesDialogCard), findsNothing);
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(tester.getSize(find.byType(CupertinoPopupSurface)).width, 270.0);
      expect(find.text('名称：report.pdf'), findsOneWidget);
    });
  });

  group('样板落地 · 新建定时任务表单（D2 560 + 横排）', () {
    CronJob job(String id) => CronJob(
      jobId: id,
      name: 'Hermes 仓 CI 巡检',
      prompt: '巡检 analyze + 全量测试',
      schedule: const CronSchedule(expression: '0 9 * * *'),
      enabled: true,
      state: 'completed',
    );

    Future<void> pumpTasksPage(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            tasksApiFactoryProvider.overrideWithValue(
              (_) => FakeTasksApi(jobs: <CronJob>[job('j1')]),
            ),
          ],
          child: CupertinoApp(
            theme: buildCupertinoTheme(Brightness.light),
            locale: const Locale('zh'),
            supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: const TasksPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> tapCreate(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('tasks-create')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('宽屏 1280：560 卡片（不 push 整页）+ 字段横排', (tester) async {
      await pumpTasksPage(tester, _kWide);
      await tapCreate(tester);

      // 整页形态不再出现 —— 宽屏改弹卡片。
      expect(find.byType(TasksEditPage), findsNothing);
      expect(find.byType(HermesDialogCard), findsOneWidget);
      expect(tester.getSize(find.byKey(kHermesDialogCardKey)).width, 560.0);

      // 横排：label 与控件同一行（窄屏是上下两行）。
      final label = tester.getRect(find.text('名称'));
      final field = tester.getRect(
        find.byKey(const ValueKey('tasks-form-name')),
      );
      expect(label.center.dy, closeTo(field.center.dy, 0.5));
      expect(field.left - label.left, greaterThanOrEqualTo(kFormLabelWidth));

      // 底栏两个动作都在。
      expect(find.byKey(const ValueKey('tasks-form-cancel')), findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-form-save')), findsOneWidget);
    });

    testWidgets('宽屏：必填为空时保存禁用，填齐后可用', (tester) async {
      await pumpTasksPage(tester, _kWide);
      await tapCreate(tester);

      // 宽屏卡片底栏的保存钮是自绘 `CupertinoButton`（key 落在按钮上）。
      CupertinoButton saveAction() => tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('tasks-form-save')),
      );
      expect(saveAction().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-schedule')),
        '0 9 * * *',
      );
      await tester.pump();
      expect(saveAction().onPressed, isNull); // 提示词仍为空

      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-prompt')),
        '总结今天的工作',
      );
      await tester.pump();
      expect(saveAction().onPressed, isNotNull);
    });

    testWidgets('窄屏 800：仍 push 整页 TasksEditPage + 字段竖排', (tester) async {
      await pumpTasksPage(tester, _kNarrow);
      await tapCreate(tester);

      expect(find.byType(TasksEditPage), findsOneWidget);
      expect(find.byType(HermesDialogCard), findsNothing);

      // 竖排：label 在控件上方（控件顶沿 > label 底沿）。
      final label = tester.getRect(find.text('名称'));
      final field = tester.getRect(
        find.byKey(const ValueKey('tasks-form-name')),
      );
      expect(field.top, greaterThan(label.bottom));
      expect(field.left, closeTo(label.left, 0.01));
    });
  });
}
