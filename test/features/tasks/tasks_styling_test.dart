import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/contrast_utils.dart';
import '../../helpers/fake_tasks_api.dart';

CronJob _buildJob(
  String id, {
  String? name,
  String? state,
  CronDateValue? lastRunAt,
}) {
  return CronJob(
    jobId: id,
    name: name ?? '任务 $id',
    prompt: '提示词 $id',
    schedule: const CronSchedule(expression: '0 9 * * *'),
    state: state,
    lastRunAt: lastRunAt,
  );
}

Future<void> _pumpTasksPage(
  WidgetTester tester,
  FakeTasksApi api, {
  Brightness brightness = Brightness.light,
  bool highContrast = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        tasksApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          highContrast: highContrast,
        ),
        child: CupertinoApp(
          theme: CupertinoThemeData(brightness: brightness),
          home: const TasksPage(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpTasksEditPage(
  WidgetTester tester,
  FakeTasksApi api, {
  CronJob? job,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        tasksApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: TasksEditPage(job: job),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('TasksPage 浅色模式表面令牌与对比度', () {
    testWidgets(
      '分组卡片：LightSurfaces.card 面 + cardBorder 边框 + divider + textSecondary 标题',
      (tester) async {
        final api = FakeTasksApi(
          jobs: [
            _buildJob('j1', name: '运行中任务', state: 'running'),
            _buildJob('j2', name: '正常任务'),
            _buildJob(
              'j3',
              name: '带运行记录任务',
              lastRunAt: CronDateValue(DateTime(2026, 8, 20, 9, 30)),
            ),
            _buildJob('j4', name: '暂停任务', state: 'paused'),
          ],
        );
        await _pumpTasksPage(tester, api, brightness: Brightness.light);

        // 验证 CupertinoPageScaffold 背景为 LightSurfaces.page
        final scaffold = tester.widget<CupertinoPageScaffold>(
          find.byType(CupertinoPageScaffold),
        );
        expect(scaffold.backgroundColor, LightSurfaces.page);

        // 验证 CupertinoListSection.insetGrouped 令牌
        final sections = tester.widgetList<CupertinoListSection>(
          find.byType(CupertinoListSection),
        );
        expect(sections.length, 2); // 正常组与暂停组

        for (final section in sections) {
          expect(section.backgroundColor, LightSurfaces.page);
          expect(section.separatorColor, LightSurfaces.divider);
          expect(section.clipBehavior, Clip.hardEdge);

          final decoration = section.decoration!;
          expect(decoration.color, LightSurfaces.card);
          expect(decoration.borderRadius, BorderRadius.circular(10));
          expect(
            decoration.border,
            Border.all(color: LightSurfaces.cardBorder, width: 0.5),
          );
        }

        // 验证分组头部标题颜色与对比度
        final headerFinder = find.text('正常（3）');
        final headerText = tester.widget<Text>(headerFinder);
        expect(headerText.style?.color, LightSurfaces.textSecondary);
        final headerContrast = contrastRatio(
          LightSurfaces.textSecondary,
          LightSurfaces.page,
        );
        expect(headerContrast, greaterThanOrEqualTo(4.5));
        expect(headerContrast, closeTo(4.82, 0.05));

        // 验证行副标题颜色与对比度（在白卡上）
        final subtitleFinder = find.text('0 9 * * * · 上次运行 09:30');
        final subtitleText = tester.widget<Text>(subtitleFinder);
        expect(subtitleText.style?.color, LightSurfaces.textSecondary);
        final subtitleContrast = contrastRatio(
          LightSurfaces.textSecondary,
          LightSurfaces.card,
        );
        expect(subtitleContrast, greaterThanOrEqualTo(4.5));
        expect(subtitleContrast, closeTo(5.38, 0.05));

        // 验证行尾操作按钮图标颜色与功能图标对比度（>= 3:1）
        final actionFinder = find.byKey(const ValueKey('tasks-actions-j1'));
        final actionIcon = tester.widget<Icon>(
          find.descendant(of: actionFinder, matching: find.byType(Icon)),
        );
        expect(actionIcon.color, LightSurfaces.textSecondary);
        expect(
          passesAA(actionIcon.color!, LightSurfaces.card, threshold: 3.0),
          isTrue,
        );

        // 验证状态色在白卡上的对比度全量达标 AA
        final element = tester.element(
          find.byKey(const ValueKey('tasks-row-j1')),
        );
        expect(
          contrastRatio(
            statusGreenText.resolveFrom(element),
            LightSurfaces.card,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(
            statusBlueText.resolveFrom(element),
            LightSurfaces.card,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(
            statusOrangeText.resolveFrom(element),
            LightSurfaces.card,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(
            statusGreyText.resolveFrom(element),
            LightSurfaces.card,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(statusRedText.resolveFrom(element), LightSurfaces.card),
          greaterThanOrEqualTo(4.5),
        );
      },
    );

    testWidgets('空态与错误态：功能图标 >= 3:1，提示文字 >= 4.5:1', (tester) async {
      // 1. 空态
      final emptyApi = FakeTasksApi();
      await _pumpTasksPage(tester, emptyApi, brightness: Brightness.light);

      final clockIconFinder = find.byIcon(CupertinoIcons.clock);
      final clockIcon = tester.widget<Icon>(clockIconFinder);
      expect(clockIcon.color, LightSurfaces.textSecondary);
      expect(
        passesAA(clockIcon.color!, LightSurfaces.page, threshold: 3.0),
        isTrue,
      );

      final promptFinder = find.textContaining('创建定时任务');
      final promptText = tester.widget<Text>(promptFinder);
      expect(promptText.style?.color, LightSurfaces.textSecondary);
      expect(
        passesAA(promptText.style!.color!, LightSurfaces.page, threshold: 4.5),
        isTrue,
      );

      // 2. 错误态
      final errorApi = FakeTasksApi();
      errorApi.fetchError = NetworkException(
        NetworkExceptionKind.cannotConnect,
      );
      await _pumpTasksPage(tester, errorApi, brightness: Brightness.light);

      final warnIconFinder = find.byIcon(
        CupertinoIcons.exclamationmark_triangle,
      );
      final warnIcon = tester.widget<Icon>(warnIconFinder);
      expect(warnIcon.color, LightSurfaces.textSecondary);
      expect(
        passesAA(warnIcon.color!, LightSurfaces.page, threshold: 3.0),
        isTrue,
      );

      final errorMsgFinder = find.textContaining('无法连接');
      final errorMsgText = tester.widget<Text>(errorMsgFinder);
      final errElement = tester.element(errorMsgFinder);
      expect(
        errorMsgText.style?.color?.toARGB32(),
        statusRedText.resolveFrom(errElement).toARGB32(),
      );
      expect(
        contrastRatio(
          statusRedText.resolveFrom(errElement),
          LightSurfaces.page,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('TasksPage 行按下反馈与交互隔离', () {
    testWidgets('浅色模式下按下产生 LightSurfaces.pressed，松开与取消即时复原', (tester) async {
      final api = FakeTasksApi(jobs: [_buildJob('j1', name: '任务一')]);
      api.outputResponse = const CronOutputResponse(
        jobId: 'j1',
        outputs: [CronOutputItem(filename: 'a.log', content: 'ok')],
      );
      await _pumpTasksPage(tester, api, brightness: Brightness.light);

      final rowFinder = find.byKey(const ValueKey('tasks-row-j1'));
      DecoratedBox getRowBox() {
        return tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: rowFinder,
                matching: find.byType(DecoratedBox),
              ),
            )
            .firstWhere(
              (b) =>
                  (b.decoration as BoxDecoration).shape == BoxShape.rectangle,
            );
      }

      // 静止态：DecoratedBox 颜色为 null（透明，露出卡片白底）
      expect((getRowBox().decoration as BoxDecoration).color, isNull);

      // 按下：背景变 LightSurfaces.pressed，泵 150ms 以满足 TapGestureRecognizer 超时
      final center = tester.getCenter(rowFinder);
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        (getRowBox().decoration as BoxDecoration).color,
        LightSurfaces.pressed,
      );

      // 抬起：背景复原为 null，且正常弹出输出面板
      await gesture.up();
      await tester.pumpAndSettle();
      expect((getRowBox().decoration as BoxDecoration).color, isNull);
      expect(find.byKey(const ValueKey('tasks-output-sheet')), findsOneWidget);
      expect(api.outputCalls, ['j1:5']);

      // 关闭输出面板
      await tester.tap(find.byKey(const ValueKey('tasks-output-close')));
      await tester.pumpAndSettle();
      api.outputCalls.clear();

      // 测试取消手势（例如滑出触控区）
      final cancelGesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        (getRowBox().decoration as BoxDecoration).color,
        LightSurfaces.pressed,
      );
      await cancelGesture.cancel();
      await tester.pumpAndSettle();
      expect((getRowBox().decoration as BoxDecoration).color, isNull);
      // 取消手势不触发打开输出面板
      expect(find.byKey(const ValueKey('tasks-output-sheet')), findsNothing);
      expect(api.outputCalls, isEmpty);
    });

    testWidgets('点击行尾 ellipsis 操作按钮仅弹出菜单，不触发行按下打开输出', (tester) async {
      final api = FakeTasksApi(jobs: [_buildJob('j1', name: '任务一')]);
      await _pumpTasksPage(tester, api, brightness: Brightness.light);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();

      expect(find.text('运行'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-output-sheet')), findsNothing);
      expect(api.outputCalls, isEmpty);
    });
  });

  group('输出面板样式与模态规范', () {
    testWidgets('浅色输出面板：page 底 + card 内容 + 0.5 描边 + divider + 480 约束 + 默认遮罩', (
      tester,
    ) async {
      final api = FakeTasksApi(jobs: [_buildJob('j1', name: '任务一')]);
      api.outputResponse = const CronOutputResponse(
        jobId: 'j1',
        outputs: [CronOutputItem(filename: 'out.txt', content: 'hello world')],
      );
      await _pumpTasksPage(tester, api, brightness: Brightness.light);

      await tester.tap(find.byKey(const ValueKey('tasks-row-j1')));
      await tester.pumpAndSettle();

      // 验证面板外层容器与圆角
      final sheetFinder = find.byKey(const ValueKey('tasks-output-sheet'));
      final sheetContainer = tester.widget<Container>(sheetFinder);
      final sheetDec = sheetContainer.decoration as BoxDecoration;
      expect(sheetDec.color, LightSurfaces.page);
      expect(
        sheetDec.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(16)),
      );
      expect(sheetContainer.constraints?.maxWidth, 480);
      expect(tester.getSize(sheetFinder).width, 480);
      expect(sheetContainer.clipBehavior, Clip.hardEdge);

      // 验证关闭按钮图标与对比度
      final closeBtnFinder = find.byKey(const ValueKey('tasks-output-close'));
      final closeIcon = tester.widget<Icon>(
        find.descendant(of: closeBtnFinder, matching: find.byType(Icon)),
      );
      expect(closeIcon.color, LightSurfaces.textSecondary);
      expect(
        passesAA(closeIcon.color!, LightSurfaces.page, threshold: 3.0),
        isTrue,
      );

      // 验证内容区白色卡片背景与描边
      final contentTextFinder = find.text('hello world');
      expect(contentTextFinder, findsOneWidget);
      final contentCard = tester.widget<Container>(
        find
            .ancestor(of: contentTextFinder, matching: find.byType(Container))
            .first,
      );
      final contentDec = contentCard.decoration as BoxDecoration;
      expect(contentDec.color, LightSurfaces.card);
      expect(
        contentDec.border,
        Border.all(color: LightSurfaces.divider, width: 0.5),
      );

      // 验证遮罩使用系统默认 kCupertinoModalBarrierColor (0x33000000)
      final barrierFinder = find.byType(ModalBarrier);
      expect(barrierFinder, findsWidgets);
      final barrier = tester.widget<ModalBarrier>(barrierFinder.last);
      expect(barrier.color?.toARGB32(), 0x33000000);
    });
  });

  group('TasksEditPage 表单浅色与输入框规范', () {
    testWidgets(
      '输入框：白色 card 面 + 0.5 cardBorder + placeholder 样式 + textSecondary 标签 + 浅色分隔线底栏',
      (tester) async {
        await _pumpTasksEditPage(
          tester,
          FakeTasksApi(),
          brightness: Brightness.light,
        );

        final scaffold = tester.widget<CupertinoPageScaffold>(
          find.byType(CupertinoPageScaffold),
        );
        expect(scaffold.backgroundColor, LightSurfaces.page);

        // 验证浅色 CupertinoNavigationBar 使用 LightSurfaces.divider 底部线且保留 width: 0.0
        final navBar = tester.widget<CupertinoNavigationBar>(
          find.byType(CupertinoNavigationBar),
        );
        expect(navBar.backgroundColor, LightSurfaces.page);
        expect(
          navBar.border,
          const Border(
            bottom: BorderSide(color: LightSurfaces.divider, width: 0.0),
          ),
        );
        expect(navBar.border?.bottom.color, LightSurfaces.divider);
        expect(navBar.border?.bottom.width, 0.0);

        // 验证输入框装饰与占位文本样式
        final fields = tester.widgetList<CupertinoTextField>(
          find.byType(CupertinoTextField),
        );
        expect(fields.length, 3); // name, schedule, prompt

        for (final field in fields) {
          final dec = field.decoration!;
          expect(dec.color, LightSurfaces.card);
          expect(dec.borderRadius, BorderRadius.circular(5));
          expect(
            dec.border,
            Border.all(color: LightSurfaces.cardBorder, width: 0.5),
          );
          expect(field.placeholderStyle?.color, LightSurfaces.placeholder);
          expect(
            passesAA(LightSurfaces.placeholder, LightSurfaces.card),
            isTrue,
          );
        }

        // 验证字段标签文字与对比度（从当前页面 l10n 获取）
        final pageContext = tester.element(find.byType(TasksEditPage));
        final l10n = AppLocalizations.of(pageContext);
        final labelTexts = [
          l10n.taskName,
          l10n.scheduleExpression,
          l10n.promptLabel,
        ];
        for (final label in labelTexts) {
          final labelText = tester.widget<Text>(find.text(label));
          expect(labelText.style?.color, LightSurfaces.textSecondary);
          expect(
            passesAA(LightSurfaces.textSecondary, LightSurfaces.page),
            isTrue,
          );
        }
      },
    );
  });

  group('操作按钮与弹窗浅色对比度达标（>= 4.5:1）', () {
    testWidgets('空态新建任务与错误重试实心按钮：有效填充与文字对比度 >= 4.5:1 且填充对页面底色 >= 4.5:1', (
      tester,
    ) async {
      // 1. 空态新建任务实心按钮（CupertinoButton.filled）
      final emptyApi = FakeTasksApi();
      await _pumpTasksPage(tester, emptyApi, brightness: Brightness.light);

      final createBtnFinder = find.byKey(const ValueKey('tasks-empty-create'));
      expect(createBtnFinder, findsOneWidget);
      final createDecBox = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: createBtnFinder,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final createFill = (createDecBox.decoration as ShapeDecoration).color!;
      final createTextElement = tester.element(
        find.descendant(of: createBtnFinder, matching: find.byType(Text)),
      );
      final createTextColor = DefaultTextStyle.of(createTextElement)
          .style
          .color!;

      expect(
        createFill.toARGB32(),
        statusBlueText.resolveFrom(createTextElement).toARGB32(),
      );
      expect(createTextColor.toARGB32(), CupertinoColors.white.toARGB32());
      expect(passesAA(createTextColor, createFill, threshold: 4.5), isTrue);
      expect(
        contrastRatio(createTextColor, createFill),
        greaterThanOrEqualTo(4.5),
      );
      expect(passesAA(createFill, LightSurfaces.page, threshold: 4.5), isTrue);
      expect(
        contrastRatio(createFill, LightSurfaces.page),
        greaterThanOrEqualTo(4.5),
      );

      // 2. 错误重试实心按钮（CupertinoButton.filled）
      final errorApi = FakeTasksApi();
      errorApi.fetchError = NetworkException(
        NetworkExceptionKind.cannotConnect,
      );
      await _pumpTasksPage(tester, errorApi, brightness: Brightness.light);

      final retryBtnFinder = find.byKey(const ValueKey('tasks-retry'));
      expect(retryBtnFinder, findsOneWidget);
      final retryDecBox = tester.widget<DecoratedBox>(
        find
            .descendant(of: retryBtnFinder, matching: find.byType(DecoratedBox))
            .first,
      );
      final retryFill = (retryDecBox.decoration as ShapeDecoration).color!;
      final retryTextElement = tester.element(
        find.descendant(of: retryBtnFinder, matching: find.byType(Text)),
      );
      final retryTextColor = DefaultTextStyle.of(retryTextElement).style.color!;

      expect(
        retryFill.toARGB32(),
        statusBlueText.resolveFrom(retryTextElement).toARGB32(),
      );
      expect(retryTextColor.toARGB32(), CupertinoColors.white.toARGB32());
      expect(passesAA(retryTextColor, retryFill, threshold: 4.5), isTrue);
      expect(
        contrastRatio(retryTextColor, retryFill),
        greaterThanOrEqualTo(4.5),
      );
      expect(passesAA(retryFill, LightSurfaces.page, threshold: 4.5), isTrue);
      expect(
        contrastRatio(retryFill, LightSurfaces.page),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets(
      '编辑器启用状态保存按钮文案在浅色背景上对比度 >= 4.5:1，且输入框使用 LightSurfaces.selection',
      (tester) async {
        // 1. 已启用状态保存按钮（提供已有任务，_canSave 为 true）
        final job = _buildJob('j1', name: '现有任务');
        await _pumpTasksEditPage(
          tester,
          FakeTasksApi(),
          job: job,
          brightness: Brightness.light,
        );

        final saveFinder = find.byKey(const ValueKey('tasks-form-save'));
        final saveButton = tester.widget<CupertinoButton>(saveFinder);
        expect(saveButton.onPressed, isNotNull);

        final saveTextElement = tester.element(
          find.descendant(of: saveFinder, matching: find.byType(Text)),
        );
        final saveTextColor = DefaultTextStyle.of(saveTextElement).style.color!;
        expect(
          saveTextColor.toARGB32(),
          statusBlueText.resolveFrom(saveTextElement).toARGB32(),
        );
        expect(
          passesAA(saveTextColor, LightSurfaces.page, threshold: 4.5),
          isTrue,
        );
        expect(
          contrastRatio(saveTextColor, LightSurfaces.page),
          greaterThanOrEqualTo(4.5),
        );

        // 验证输入框 DefaultSelectionStyle 选中色覆盖为 LightSurfaces.selection
        final nameFieldElement = tester.element(
          find.byKey(const ValueKey('tasks-form-name')),
        );
        final selectionStyle = DefaultSelectionStyle.of(nameFieldElement);
        expect(selectionStyle.selectionColor, LightSurfaces.selection);

        // 2. 禁用状态：清理旧树隔离测试夹具，空表单 _canSave 为 false 保留原生禁用行为（onPressed == null）
        await tester.pumpWidget(const SizedBox());
        await _pumpTasksEditPage(
          tester,
          FakeTasksApi(),
          brightness: Brightness.light,
        );
        final disabledSaveFinder = find.byKey(
          const ValueKey('tasks-form-save'),
        );
        final disabledSaveButton = tester.widget<CupertinoButton>(
          disabledSaveFinder,
        );
        expect(disabledSaveButton.onPressed, isNull);
      },
    );

    testWidgets('真实交互弹出任务删除对话框与错误对话框：普通动作与破坏性动作文字在浅色弹窗底色上对比度 >= 4.5:1', (
      tester,
    ) async {
      // 1. 真实交互打开删除确认对话框
      final api = FakeTasksApi(jobs: [_buildJob('j1', name: '待删任务')]);
      await _pumpTasksPage(tester, api, brightness: Brightness.light);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-delete')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);

      // 取消操作（普通动作）：LightSurfaces.menuAction
      final cancelFinder = find.byKey(const ValueKey('tasks-delete-cancel'));
      final cancelAction = tester.widget<CupertinoDialogAction>(cancelFinder);
      expect(cancelAction.textStyle?.color, LightSurfaces.menuAction);
      expect(
        passesAA(
          cancelAction.textStyle!.color!,
          const Color(0xFFF2F2F2),
          threshold: 4.5,
        ),
        isTrue,
      );
      expect(
        passesAA(
          cancelAction.textStyle!.color!,
          LightSurfaces.page,
          threshold: 4.5,
        ),
        isTrue,
      );
      expect(
        contrastRatio(cancelAction.textStyle!.color!, LightSurfaces.page),
        greaterThanOrEqualTo(4.5),
      );

      // 删除操作（破坏性动作）：statusRedText
      final confirmFinder = find.byKey(const ValueKey('tasks-delete-confirm'));
      final confirmAction = tester.widget<CupertinoDialogAction>(confirmFinder);
      expect(confirmAction.isDestructiveAction, isTrue);
      final confirmElement = tester.element(confirmFinder);
      final expectedRed = statusRedText.resolveFrom(confirmElement);
      expect(
        confirmAction.textStyle?.color?.toARGB32(),
        expectedRed.toARGB32(),
      );
      expect(
        passesAA(
          confirmAction.textStyle!.color!,
          const Color(0xFFF2F2F2),
          threshold: 4.5,
        ),
        isTrue,
      );
      expect(
        passesAA(
          confirmAction.textStyle!.color!,
          LightSurfaces.page,
          threshold: 4.5,
        ),
        isTrue,
      );
      expect(
        contrastRatio(confirmAction.textStyle!.color!, LightSurfaces.page),
        greaterThanOrEqualTo(4.5),
      );

      // 点击取消正常关闭对话框且不调用删除
      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(api.deleteCalls, isEmpty);

      // 2. 真实交互触发操作失败错误对话框（HttpException 非 const）
      api.runError = HttpException(500, null, message: '操作不可用');
      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-run')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);

      final okFinder = find.byKey(const ValueKey('tasks-error-ok'));
      final okAction = tester.widget<CupertinoDialogAction>(okFinder);
      expect(okAction.textStyle?.color, LightSurfaces.menuAction);
      expect(
        passesAA(
          okAction.textStyle!.color!,
          const Color(0xFFF2F2F2),
          threshold: 4.5,
        ),
        isTrue,
      );
      expect(
        passesAA(
          okAction.textStyle!.color!,
          LightSurfaces.page,
          threshold: 4.5,
        ),
        isTrue,
      );
      expect(
        contrastRatio(okAction.textStyle!.color!, LightSurfaces.page),
        greaterThanOrEqualTo(4.5),
      );

      await tester.tap(okFinder);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });
  });

  group('暗色模式像素一致性与默认行为保留', () {
    testWidgets('暗色任务列表保留原始默认面、未解析语义色与原生交互', (tester) async {
      final api = FakeTasksApi(
        jobs: [
          _buildJob(
            'j1',
            name: '暗色任务',
            lastRunAt: CronDateValue(DateTime(2026, 8, 20, 9, 30)),
          ),
        ],
      );
      await _pumpTasksPage(tester, api, brightness: Brightness.dark);

      // 验证 scaffold 保持原始 null（使用主题纯黑）
      final scaffold = tester.widget<CupertinoPageScaffold>(
        find.byType(CupertinoPageScaffold),
      );
      expect(scaffold.backgroundColor, isNull);

      // 验证 CupertinoListSection.insetGrouped 保持默认 null decoration 和 separatorColor，且 clipBehavior 为 SDK 默认 hardEdge
      final section = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(section.backgroundColor, CupertinoColors.systemGroupedBackground);
      expect(section.decoration, isNull);
      expect(section.separatorColor, isNull);
      expect(section.clipBehavior, Clip.hardEdge);

      // 验证副标题颜色解析保留 secondaryText 原有语义色
      final subtitleFinder = find.text('0 9 * * * · 上次运行 09:30');
      final subtitleText = tester.widget<Text>(subtitleFinder);
      final subElement = tester.element(subtitleFinder);
      expect(
        subtitleText.style?.color?.toARGB32(),
        secondaryText.resolveFrom(subElement).toARGB32(),
      );

      // 验证操作按钮图标保持 CupertinoColors.systemGrey 原有语义色
      final actionFinder = find.byKey(const ValueKey('tasks-actions-j1'));
      final actionIcon = tester.widget<Icon>(
        find.descendant(of: actionFinder, matching: find.byType(Icon)),
      );
      expect(
        actionIcon.color?.toARGB32(),
        CupertinoColors.systemGrey.resolveFrom(subElement).toARGB32(),
      );

      // 验证暗色模式下 GestureDetector 无按下态包裹层，直接透传 child
      final rowFinder = find.byKey(const ValueKey('tasks-row-j1'));
      final detector = tester.widget<GestureDetector>(
        find.descendant(of: rowFinder, matching: find.byType(GestureDetector)),
      );
      expect(detector.child, isA<Padding>());
      expect(detector.onTapDown, isNull);
      expect(detector.onTapUp, isNull);
      expect(detector.onTapCancel, isNull);
    });

    testWidgets(
      '暗色表单保持 CupertinoTextField 默认 decoration 与 placeholderStyle 及默认 border',
      (tester) async {
        await _pumpTasksEditPage(
          tester,
          FakeTasksApi(),
          brightness: Brightness.dark,
        );

        final scaffold = tester.widget<CupertinoPageScaffold>(
          find.byType(CupertinoPageScaffold),
        );
        expect(scaffold.backgroundColor, isNull);

        // 验证暗色 CupertinoNavigationBar 使用构造函数原始默认 border
        final navBar = tester.widget<CupertinoNavigationBar>(
          find.byType(CupertinoNavigationBar),
        );
        expect(navBar.backgroundColor, isNull);
        expect(navBar.border, const CupertinoNavigationBar().border);

        const defaultField = CupertinoTextField();
        final fields = tester.widgetList<CupertinoTextField>(
          find.byType(CupertinoTextField),
        );
        for (final field in fields) {
          expect(field.decoration, defaultField.decoration);
          expect(field.placeholderStyle, defaultField.placeholderStyle);
        }

        final pageContext = tester.element(find.byType(TasksEditPage));
        final l10n = AppLocalizations.of(pageContext);
        final labelFinder = find.text(l10n.taskName);
        final labelText = tester.widget<Text>(labelFinder);
        final element = tester.element(labelFinder);
        expect(
          labelText.style?.color?.toARGB32(),
          secondaryText.resolveFrom(element).toARGB32(),
        );
      },
    );

    testWidgets('暗色输出面板保留原始 surface 与约束（无 480 限制）', (tester) async {
      final api = FakeTasksApi(jobs: [_buildJob('j1', name: '暗色任务')]);
      api.outputResponse = const CronOutputResponse(
        jobId: 'j1',
        outputs: [CronOutputItem(filename: 'd.txt', content: 'dark content')],
      );
      await _pumpTasksPage(tester, api, brightness: Brightness.dark);

      await tester.tap(find.byKey(const ValueKey('tasks-row-j1')));
      await tester.pumpAndSettle();

      final sheetFinder = find.byKey(const ValueKey('tasks-output-sheet'));
      final sheetContainer = tester.widget<Container>(sheetFinder);
      final sheetDec = sheetContainer.decoration as BoxDecoration;
      final element = tester.element(sheetFinder);

      expect(
        sheetDec.color?.toARGB32(),
        CupertinoColors.secondarySystemBackground
            .resolveFrom(element)
            .toARGB32(),
      );
      // 暗色面板无 maxWidth 限制（继承原宽）
      expect(sheetContainer.constraints?.maxWidth, double.infinity);
      expect(sheetContainer.clipBehavior, Clip.none);

      final closeBtnFinder = find.byKey(const ValueKey('tasks-output-close'));
      final closeIcon = tester.widget<Icon>(
        find.descendant(of: closeBtnFinder, matching: find.byType(Icon)),
      );
      expect(
        closeIcon.color?.toARGB32(),
        CupertinoColors.tertiaryLabel.resolveFrom(element).toARGB32(),
      );

      final darkContentFinder = find.text('dark content');
      expect(darkContentFinder, findsOneWidget);
      final darkContentCard = tester.widget<Container>(
        find
            .ancestor(of: darkContentFinder, matching: find.byType(Container))
            .first,
      );
      final darkContentDec = darkContentCard.decoration as BoxDecoration;
      expect(
        darkContentDec.color?.toARGB32(),
        CupertinoColors.tertiarySystemBackground
            .resolveFrom(element)
            .toARGB32(),
      );
      expect(
        (darkContentDec.border as Border).top.color.toARGB32(),
        CupertinoColors.separator.resolveFrom(element).toARGB32(),
      );
    });

    testWidgets('暗色增强对比度模式（highContrast）正确解析对应变体', (tester) async {
      final api = FakeTasksApi(
        jobs: [
          _buildJob(
            'j1',
            name: '高对比度任务',
            lastRunAt: CronDateValue(DateTime(2026, 8, 20, 9, 30)),
          ),
        ],
      );
      await _pumpTasksPage(
        tester,
        api,
        brightness: Brightness.dark,
        highContrast: true,
      );

      final subtitleFinder = find.text('0 9 * * * · 上次运行 09:30');
      final subtitleText = tester.widget<Text>(subtitleFinder);
      final element = tester.element(subtitleFinder);

      // 断言目标测试上下文确实具有 MediaQuery.highContrastOf(element) == true
      expect(MediaQuery.highContrastOf(element), isTrue);

      // 验证高对比度下 resolve 出正确的 highContrast 颜色
      expect(
        subtitleText.style?.color?.toARGB32(),
        secondaryText.resolveFrom(element).toARGB32(),
      );
      expect(
        subtitleText.style?.color?.toARGB32(),
        const Color(0xADEBEBF5).toARGB32(),
      );

      final actionFinder = find.byKey(const ValueKey('tasks-actions-j1'));
      final actionIcon = tester.widget<Icon>(
        find.descendant(of: actionFinder, matching: find.byType(Icon)),
      );
      expect(
        actionIcon.color?.toARGB32(),
        CupertinoColors.systemGrey.resolveFrom(element).toARGB32(),
      );
      expect(actionIcon.color?.toARGB32(), const Color(0xFFAEAEB2).toARGB32());
    });

    testWidgets('暗色模式实心按钮、弹窗动作与表单保留原生暗色主题解析与环境选区样式', (tester) async {
      // 1. 实心按钮：空态与重试保留原生 activeBlue 暗色解析填充与 SDK 默认白色前景
      final errorApi = FakeTasksApi();
      errorApi.fetchError = NetworkException(
        NetworkExceptionKind.cannotConnect,
      );
      await _pumpTasksPage(tester, errorApi, brightness: Brightness.dark);

      final retryBtnFinder = find.byKey(const ValueKey('tasks-retry'));
      final retryDecBox = tester.widget<DecoratedBox>(
        find
            .descendant(of: retryBtnFinder, matching: find.byType(DecoratedBox))
            .first,
      );
      final darkRetryFill = (retryDecBox.decoration as ShapeDecoration).color!;
      final darkRetryTextElement = tester.element(
        find.descendant(of: retryBtnFinder, matching: find.byType(Text)),
      );
      final darkRetryTextColor = DefaultTextStyle.of(darkRetryTextElement)
          .style
          .color!;
      // 暗色 activeBlue 解析后值（0xFF0A84FF）与 SDK 原始 primaryContrastingColor（白色）
      expect(
        darkRetryFill.toARGB32(),
        CupertinoColors.activeBlue.resolveFrom(darkRetryTextElement).toARGB32(),
      );
      expect(darkRetryTextColor.toARGB32(), CupertinoColors.white.toARGB32());

      // 2. 暗色删除对话框：textStyle 保持 null，交由原生样式处理
      final api = FakeTasksApi(jobs: [_buildJob('j1', name: '暗色任务')]);
      await _pumpTasksPage(tester, api, brightness: Brightness.dark);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-delete')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      final cancelAction = tester.widget<CupertinoDialogAction>(
        find.byKey(const ValueKey('tasks-delete-cancel')),
      );
      expect(cancelAction.textStyle, isNull);
      final confirmAction = tester.widget<CupertinoDialogAction>(
        find.byKey(const ValueKey('tasks-delete-confirm')),
      );
      expect(confirmAction.textStyle, isNull);
      expect(confirmAction.isDestructiveAction, isTrue);

      await tester.tap(find.byKey(const ValueKey('tasks-delete-cancel')));
      await tester.pumpAndSettle();

      // 3. 暗色错误对话框：OK 动作 textStyle 保持 null（HttpException 非 const）
      api.runError = HttpException(500, null, message: '暗色操作失败');
      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-run')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      final okAction = tester.widget<CupertinoDialogAction>(
        find.byKey(const ValueKey('tasks-error-ok')),
      );
      expect(okAction.textStyle, isNull);

      await tester.tap(find.byKey(const ValueKey('tasks-error-ok')));
      await tester.pumpAndSettle();

      // 4. 暗色表单保存按钮与选区样式：保留原生 activeBlue 解析值，继承 CupertinoApp 原生 DefaultSelectionStyle
      final job = _buildJob('j1', name: '暗色任务');
      await _pumpTasksEditPage(
        tester,
        FakeTasksApi(),
        job: job,
        brightness: Brightness.dark,
      );

      final saveFinder = find.byKey(const ValueKey('tasks-form-save'));
      final saveTextElement = tester.element(
        find.descendant(of: saveFinder, matching: find.byType(Text)),
      );
      final saveTextColor = DefaultTextStyle.of(saveTextElement).style.color!;
      expect(
        saveTextColor.toARGB32(),
        CupertinoColors.activeBlue.resolveFrom(saveTextElement).toARGB32(),
      );

      final pageElement = tester.element(find.byType(TasksEditPage));
      final ambientStyle = DefaultSelectionStyle.of(pageElement);
      final nameFieldElement = tester.element(
        find.byKey(const ValueKey('tasks-form-name')),
      );
      final fieldSelectionStyle = DefaultSelectionStyle.of(nameFieldElement);
      expect(fieldSelectionStyle.selectionColor, ambientStyle.selectionColor);
      expect(fieldSelectionStyle.cursorColor, ambientStyle.cursorColor);
    });
  });
}
