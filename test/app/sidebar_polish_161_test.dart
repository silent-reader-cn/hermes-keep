import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/sidebar_brand_bar.dart';
import 'package:hermes_ui/app/shell/sidebar_tools_list.dart';
import 'package:hermes_ui/core/models/cron.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #161：宽屏侧栏打磨 —— ⑤「定时任务」待办计数徽标、④品牌行副标题。
///
/// ①当前会话高亮 的渲染由 `_SessionRow.isCurrent` 承载（私有 widget），
/// 本文件以「provider → 徽标/文案」的可观测契约为主；高亮的像素回归由
/// `docs/screenshots/wide-sessions.png` 与 session_list 域用例共同守卫。
class _EmptyTasksController extends TasksController {
  @override
  Future<TasksState> build() async {
    ref.watch(tasksApiFactoryProvider);
    return const TasksState(jobs: <CronJob>[]);
  }
}

class _TwoJobsTasksController extends TasksController {
  @override
  Future<TasksState> build() async {
    ref.watch(tasksApiFactoryProvider);
    return const TasksState(
      jobs: <CronJob>[
        CronJob(jobId: 'a', name: '备份'),
        CronJob(jobId: 'b', name: '周报'),
      ],
    );
  }
}

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

Widget _host(Widget child, {TasksController Function()? tasks}) {
  return ProviderScope(
    overrides: [if (tasks != null) tasksControllerProvider.overrideWith(tasks)],
    child: CupertinoApp(
      locale: const Locale('zh'),
      localizationsDelegates: _delegates,
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: CupertinoPageScaffold(child: child),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('#161-⑤ 定时任务待办计数徽标', () {
    testWidgets('有任务时渲染徽标并显示数量', (tester) async {
      tester.view.physicalSize = const Size(340, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 340,
            child: SidebarToolsList(currentLocation: '/'),
          ),
          tasks: _TwoJobsTasksController.new,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sidebar-tool-badge-tasks')),
        findsOneWidget,
        reason: '任务数 > 0 时应出现徽标',
      );
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('无任务时不渲染徽标（badge<=0 隐藏）', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 340,
            child: SidebarToolsList(currentLocation: '/'),
          ),
          tasks: _EmptyTasksController.new,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sidebar-tool-badge-tasks')),
        findsNothing,
      );
    });

    test('tasksJobCountProvider 反映任务条数', () async {
      final container = ProviderContainer(
        overrides: [
          tasksControllerProvider.overrideWith(_TwoJobsTasksController.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(tasksControllerProvider.future);
      expect(container.read(tasksJobCountProvider), 2);
    });
  });

  group('#161-④ 品牌行副标题', () {
    testWidgets('无会话时不渲染副标题（不显示「0 个会话」）', (tester) async {
      await tester.pumpWidget(_host(const SidebarBrandBar()));
      await tester.pumpAndSettle();

      expect(find.text('Hermes'), findsOneWidget);
      expect(find.textContaining('个会话'), findsNothing);
    });
  });

  group('#161-③ 未分组文案', () {
    test('中文为「未分组」、英文为 Ungrouped', () async {
      expect(const AppLocalizations(Locale('zh')).ungroupedSection, '未分组');
      expect(
        const AppLocalizations(Locale('en')).ungroupedSection,
        'Ungrouped',
      );
    });

    test('会话数文案：中文「N 个会话」', () {
      expect(
        const AppLocalizations(Locale('zh')).sessionsCountLabel(6),
        '6 个会话',
      );
      expect(
        const AppLocalizations(Locale('en')).sessionsCountLabel(6),
        '6 sessions',
      );
    });
  });
}
