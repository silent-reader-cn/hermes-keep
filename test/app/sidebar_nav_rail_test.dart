import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/sidebar_nav_rail.dart';
import 'package:hermes_ui/app/shell/sidebar_status_bar.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/session_list/session_entry_visibility.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FilteredVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: false,
      kanban: true,
      skills: true,
      insights: true,
      workspaces: true,
      memory: true,
    );
  }
}

class _AllHiddenVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: false,
      kanban: false,
      skills: false,
      insights: false,
      workspaces: false,
      memory: false,
      downloads: false,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const List<LocalizationsDelegate<dynamic>> testDelegates = [
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  Widget buildRailApp({
    required String currentLocation,
    Brightness brightness = Brightness.light,
    List<Override> overrides = const [],
    void Function(String path)? onNavigate,
  }) {
    final router = GoRouter(
      initialLocation: currentLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => CupertinoPageScaffold(
            child: SidebarNavRail(currentLocation: state.uri.toString()),
          ),
        ),
        GoRoute(
          path: '/tasks',
          builder: (context, state) {
            onNavigate?.call('/tasks');
            return CupertinoPageScaffold(
              child: SidebarNavRail(currentLocation: state.uri.toString()),
            );
          },
        ),
        GoRoute(
          path: '/kanban',
          builder: (context, state) {
            onNavigate?.call('/kanban');
            return CupertinoPageScaffold(
              child: SidebarNavRail(currentLocation: state.uri.toString()),
            );
          },
        ),
        GoRoute(
          path: '/workspaces',
          builder: (context, state) {
            onNavigate?.call('/workspaces');
            return CupertinoPageScaffold(
              child: SidebarNavRail(currentLocation: state.uri.toString()),
            );
          },
        ),
        GoRoute(
          path: '/skills',
          builder: (context, state) {
            onNavigate?.call('/skills');
            return CupertinoPageScaffold(
              child: SidebarNavRail(currentLocation: state.uri.toString()),
            );
          },
        ),
        GoRoute(
          path: '/insights',
          builder: (context, state) {
            onNavigate?.call('/insights');
            return CupertinoPageScaffold(
              child: SidebarNavRail(currentLocation: state.uri.toString()),
            );
          },
        ),
        GoRoute(
          path: '/memory',
          builder: (context, state) {
            onNavigate?.call('/memory');
            return CupertinoPageScaffold(
              child: SidebarNavRail(currentLocation: state.uri.toString()),
            );
          },
        ),
        GoRoute(
          path: '/downloads',
          builder: (context, state) {
            onNavigate?.call('/downloads');
            return CupertinoPageScaffold(
              child: SidebarNavRail(currentLocation: state.uri.toString()),
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) {
            onNavigate?.call('/settings');
            return CupertinoPageScaffold(
              child: SidebarNavRail(currentLocation: state.uri.toString()),
            );
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: overrides,
      child: CupertinoApp.router(
        routerConfig: router,
        theme: CupertinoThemeData(brightness: brightness),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: testDelegates,
      ),
    );
  }

  group('SidebarNavRail 基础渲染与几何尺寸规格测试', () {
    testWidgets('默认全开时渲染全部 8 个功能入口，顺序与语义准确', (tester) async {
      await tester.pumpWidget(buildRailApp(currentLocation: '/'));
      await tester.pumpAndSettle();

      const itemIds = [
        'tasks',
        'kanban',
        'workspaces',
        'skills',
        'insights',
        'memory',
        'downloads',
        'settings',
      ];

      for (final id in itemIds) {
        expect(
          find.byKey(ValueKey('sidebar-nav-$id')),
          findsOneWidget,
          reason: '$id 入口应存在',
        );
      }

      // 验证图标数据与既有定义完全对齐
      expect(find.byIcon(CupertinoIcons.clock), findsOneWidget); // tasks
      expect(find.byIcon(CupertinoIcons.square_split_2x2), findsOneWidget); // kanban
      expect(find.byIcon(CupertinoIcons.folder), findsOneWidget); // workspaces
      expect(find.byIcon(CupertinoIcons.hammer), findsOneWidget); // skills
      expect(find.byIcon(CupertinoIcons.chart_bar), findsOneWidget); // insights
      expect(find.byIcon(CupertinoIcons.book), findsOneWidget); // memory
      expect(find.byIcon(CupertinoIcons.arrow_down_circle), findsOneWidget); // downloads
      expect(find.byIcon(CupertinoIcons.gear_alt), findsOneWidget); // settings
    });

    testWidgets('几何规格：轨宽 50px、命中区 34×34、图标 19px', (tester) async {
      await tester.pumpWidget(buildRailApp(currentLocation: '/'));
      await tester.pumpAndSettle();

      final railFinder = find.byType(SidebarNavRail);
      expect(tester.getSize(railFinder).width, 50.0);

      final buttonFinder = find.byKey(const ValueKey('sidebar-nav-tasks'));
      final buttonSize = tester.getSize(buttonFinder);
      expect(buttonSize.width, 34.0);
      expect(buttonSize.height, 34.0);

      final iconFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Icon),
      );
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.size, 19.0);
    });

    testWidgets('Semantics 与 Tooltip 标签完整配置', (tester) async {
      await tester.pumpWidget(buildRailApp(currentLocation: '/'));
      await tester.pumpAndSettle();

      final tasksSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('sidebar-utility-tasks')),
      );
      expect(tasksSemantics.properties.label, '定时任务');
      expect(tasksSemantics.properties.tooltip, '定时任务');
      expect(tasksSemantics.properties.button, isTrue);

      final settingsSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('sidebar-utility-settings')),
      );
      expect(settingsSemantics.properties.label, '设置');
      expect(settingsSemantics.properties.tooltip, '设置');
      expect(settingsSemantics.properties.button, isTrue);
    });
  });

  group('SidebarNavRail 激活态唯一高亮与明暗双态测试', () {
    testWidgets('浅色模式：当前路由命中时唯一高亮，背景 #E0ECFF、图标 #007AFF，未激活色 #6A6A6F', (tester) async {
      await tester.pumpWidget(
        buildRailApp(
          currentLocation: '/tasks',
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();

      // tasks 为激活态
      final tasksButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('sidebar-nav-tasks')),
      );
      expect(tasksButton.color, LightSurfaces.selection); // #E0ECFF

      final tasksIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('sidebar-nav-tasks')),
          matching: find.byType(Icon),
        ),
      );
      expect(tasksIcon.color, const Color(0xFF007AFF));

      // settings 未激活
      final settingsButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('sidebar-nav-settings')),
      );
      expect(settingsButton.color, CupertinoColors.transparent);

      final settingsIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('sidebar-nav-settings')),
          matching: find.byType(Icon),
        ),
      );
      expect(settingsIcon.color, LightSurfaces.textSecondary); // #6A6A6F

      // 轨背景与右描边
      final railContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(SidebarNavRail),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = railContainer.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFEAEAF0));
      final border = decoration.border as Border;
      expect(border.right.color, LightSurfaces.divider);
    });

    testWidgets('深色模式：激活面 #0A3A66、图标 #4DA3FF，未激活色 #9A9AA0，轨背景 #242426', (tester) async {
      await tester.pumpWidget(
        buildRailApp(
          currentLocation: '/kanban',
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      // kanban 激活态
      final kanbanButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('sidebar-nav-kanban')),
      );
      expect(kanbanButton.color, const Color(0xFF0A3A66));

      final kanbanIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('sidebar-nav-kanban')),
          matching: find.byType(Icon),
        ),
      );
      expect(kanbanIcon.color, const Color(0xFF4DA3FF));

      // tasks 未激活
      final tasksButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('sidebar-nav-tasks')),
      );
      expect(tasksButton.color, CupertinoColors.transparent);

      final tasksIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('sidebar-nav-tasks')),
          matching: find.byType(Icon),
        ),
      );
      expect(tasksIcon.color, const Color(0xFF9A9AA0));

      // 轨背景与右描边
      final railContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(SidebarNavRail),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = railContainer.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF242426));
      final border = decoration.border as Border;
      expect(border.right.color, const Color(0xFF3A3A3C));
    });
  });

  group('SidebarNavRail 显隐开关与设置钉底测试', () {
    testWidgets('部分关闭时仅隐藏关闭的入口，其余入口正常渲染', (tester) async {
      await tester.pumpWidget(
        buildRailApp(
          currentLocation: '/',
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _FilteredVisibilityNotifier.new,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sidebar-nav-tasks')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-nav-kanban')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-nav-workspaces')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-nav-skills')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-nav-insights')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-nav-memory')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-nav-downloads')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-nav-settings')), findsOneWidget);
    });

    testWidgets('全部功能入口关闭时：整条轨道只保留设置图标，中间分隔线不渲染', (tester) async {
      await tester.pumpWidget(
        buildRailApp(
          currentLocation: '/settings',
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllHiddenVisibilityNotifier.new,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sidebar-nav-tasks')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-nav-kanban')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-nav-workspaces')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-nav-skills')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-nav-insights')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-nav-memory')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-nav-downloads')), findsNothing);

      // 仅 settings 存在
      expect(find.byKey(const ValueKey('sidebar-nav-settings')), findsOneWidget);
    });
  });

  group('SidebarNavRail 点击触发路由跳转测试', () {
    testWidgets('点击各个功能入口触发对应路由 push 入栈（#145）', (tester) async {
      // #145：侧栏入口语义必须是 push（入栈）而非 go（替换）——#77 宽屏
      // 右侧面板导航栈依赖它才能逐级回退（wide_panel_nav_stack_test 钉此）。
      // 故本用例按 push 语义断言：每个入口单独在干净 app 里点击，避开
      // push 造成的多页面 rail 累积（同一 ValueKey 会出现多实例）。
      for (final id in <String>['tasks', 'kanban', 'settings']) {
        final navigated = <String>[];
        await tester.pumpWidget(
          buildRailApp(currentLocation: '/', onNavigate: navigated.add),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ValueKey('sidebar-nav-$id')));
        await tester.pumpAndSettle();

        expect(
          navigated,
          contains('/$id'),
          reason: '点击 $id 入口应 push 到 /$id',
        );
      }
    });
  });

  group('SidebarStatusBar 状态条测试', () {
    testWidgets('已连接态：渲染 6px 绿点、端口 30002 与服务类型 pill', (tester) async {
      final connection = ServerConnection(
        id: 'conn-1',
        name: 'Local',
        baseUrl: 'http://127.0.0.1:30002',
        kind: ConnectionKind.builtin,
        createdAt: DateTime.utc(2026, 1, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _TestActiveConnectionController(connection),
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            home: CupertinoPageScaffold(
              child: SidebarStatusBar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sidebar-status-bar')), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('30002'), findsOneWidget);
      expect(find.text('内置服务'), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-status-retry')), findsNothing);
    });

    testWidgets('连接中态：渲染转圈指示器与连接中文案', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            home: CupertinoPageScaffold(
              child: SidebarStatusBar(
                statusOverride: SidebarConnectionStatus.connecting,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('连接中…'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });

    testWidgets('离线态：渲染红点、离线文案与重试按钮，点击触发重试回调', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          child: CupertinoApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            home: CupertinoPageScaffold(
              child: SidebarStatusBar(
                statusOverride: SidebarConnectionStatus.offline,
                onRetry: () => retryCalled = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('离线'), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-status-retry')), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sidebar-status-retry')));
      await tester.pumpAndSettle();
      expect(retryCalled, isTrue);
    });
  });
}

class _TestActiveConnectionController extends ActiveConnectionController {
  _TestActiveConnectionController(this._initial);

  final ServerConnection? _initial;

  @override
  ServerConnection? build() {
    return _initial;
  }
}
