import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/widgets/adaptive_sliver_navigation_bar.dart';
import 'package:hermes_ui/app/widgets/narrow_navigation_dropdown.dart';
import 'package:hermes_ui/features/session_list/session_entry_visibility.dart';
import 'package:hermes_ui/features/session_list/session_list_header.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #128 窄屏「点击大标题 = 点击右侧 ▾」回归守卫。
///
/// 覆盖两条头部路径：
/// - `AdaptiveSliverNavigationBar`（tasks/kanban/workspaces/workspace/skills/
///   insights/memory/git/settings 共用）→ `LargeTitleSliverHeaderDelegate`；
/// - 会话列表页 `SessionListHeaderDelegate`。
///
/// 关键语义：点标题打开的是**同一个**下拉（同一组条目 key、同一弹层入口），
/// 而不是另起一套菜单。
class _DefaultVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() => const SessionEntryVisibility();
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

  Widget wrap(Widget home) {
    return ProviderScope(
      overrides: [
        sessionEntryVisibilityProvider.overrideWith(
          _DefaultVisibilityNotifier.new,
        ),
      ],
      child: CupertinoApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: testDelegates,
        home: home,
      ),
    );
  }

  Widget navBarScaffold({
    required String title,
    bool showDropdown = true,
    bool showMiddleOnNarrow = false,
    VoidCallback? onTitleDoubleTap,
  }) {
    return wrap(
      CupertinoPageScaffold(
        child: CustomScrollView(
          slivers: [
            AdaptiveSliverNavigationBar(
              title: title,
              leading: const SizedBox.shrink(),
              showNarrowNavigationDropdown: showDropdown,
              showMiddleOnNarrow: showMiddleOnNarrow,
              onTitleDoubleTap: onTitleDoubleTap,
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 1200, width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  void setNarrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('#128 窄屏点击大标题 = 点击 ▾（AdaptiveSliverNavigationBar）', () {
    testWidgets('窄屏：点大标题弹出与 ▾ 同一组快捷导航条目', (tester) async {
      setNarrow(tester);
      await tester.pumpWidget(navBarScaffold(title: '技能'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsNothing);

      await tester.tap(find.text('技能'));
      await tester.pumpAndSettle();

      // 与直接点 ▾ 完全同一组条目（同一 key）。
      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-workspaces')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-skills')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-insights')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-memory')), findsOneWidget);
    });

    testWidgets('窄屏：点 ▾ 与点标题得到同样的条目集合（同一入口）', (tester) async {
      setNarrow(tester);
      await tester.pumpWidget(navBarScaffold(title: '技能'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('narrow-nav-dropdown')));
      await tester.pumpAndSettle();
      final viaButton = <String>{
        for (final key in const [
          'narrow-nav-tasks',
          'narrow-nav-workspaces',
          'narrow-nav-skills',
          'narrow-nav-insights',
          'narrow-nav-memory',
        ])
          key,
      }.where((key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty).toSet();

      await tester.tap(find.byKey(const ValueKey('narrow-nav-cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('技能'));
      await tester.pumpAndSettle();
      final viaTitle = <String>{
        for (final key in const [
          'narrow-nav-tasks',
          'narrow-nav-workspaces',
          'narrow-nav-skills',
          'narrow-nav-insights',
          'narrow-nav-memory',
        ])
          key,
      }.where((key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty).toSet();

      expect(viaTitle, isNotEmpty);
      expect(viaTitle, equals(viaButton));
    });

    testWidgets('窄屏：滚动收起后点中标题同样打开菜单', (tester) async {
      setNarrow(tester);
      await tester.pumpWidget(
        navBarScaffold(title: '工作区', showMiddleOnNarrow: true),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // 收起态：中标题（Stack 中先绘制）+ 透明大标题共存，点中标题（first）。
      await tester.tap(find.text('工作区').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsOneWidget);
    });

    testWidgets('宽屏（>=900）：点标题不弹菜单（行为不变）', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(navBarScaffold(title: '技能'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-dropdown')), findsNothing);

      await tester.tap(find.text('技能'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsNothing);
    });

    testWidgets('窄屏但关闭下拉：无 ▾，点标题也不弹菜单', (tester) async {
      setNarrow(tester);
      await tester.pumpWidget(
        navBarScaffold(title: '技能', showDropdown: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-dropdown')), findsNothing);

      await tester.tap(find.text('技能'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsNothing);
    });

    testWidgets('窄屏：单击打开菜单 / 双击回顶互不串门（主人拍板的取舍）', (tester) async {
      setNarrow(tester);
      var doubleTapped = 0;
      await tester.pumpWidget(
        navBarScaffold(
          title: '设置',
          onTitleDoubleTap: () => doubleTapped++,
        ),
      );
      await tester.pumpAndSettle();

      // 单击：需越过双击判定窗口（kDoubleTapTimeout 300ms）才触发。
      await tester.tap(find.text('设置'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsOneWidget);
      expect(doubleTapped, 0, reason: '单击不应触发回顶');

      await tester.tap(find.byKey(const ValueKey('narrow-nav-cancel')));
      await tester.pumpAndSettle();

      // 双击：回顶触发，且不弹菜单（单击被双击吃掉）。
      await tester.tap(find.text('设置'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(doubleTapped, 1);
      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsNothing);
    });
  });

  group('#128 会话列表页头部（SessionListHeaderDelegate）', () {
    testWidgets('窄屏：点「会话」大标题打开 ▾ 的快捷导航', (tester) async {
      setNarrow(tester);
      final signal = ValueNotifier<int>(0);
      addTearDown(signal.dispose);

      await tester.pumpWidget(
        wrap(
          CupertinoPageScaffold(
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: SessionListHeaderDelegate(
                    title: '会话',
                    titleTrailing: NarrowNavigationDropdownButton(
                      buttonKey: const ValueKey('session-list-narrow-nav'),
                      openSignal: signal,
                    ),
                    onTitleTap: () => signal.value++,
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 1200, width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('会话').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsOneWidget);
    });

    testWidgets('未接线（onTitleTap 为空）时点标题无弹层（默认行为不变）', (tester) async {
      setNarrow(tester);
      await tester.pumpWidget(
        wrap(
          const CupertinoPageScaffold(
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: SessionListHeaderDelegate(title: '会话'),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 1200, width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('会话').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsNothing);
    });
  });

  group('#128 接线护栏（防回归：页面级接线被删）', () {
    test('会话列表页头部必须接线 onTitleTap 与 ▾ 打开通道', () {
      final source = File(
        'lib/features/session_list/session_list_page.dart',
      ).readAsStringSync();
      expect(
        source.contains('onTitleTap: !isWide && !isSearchMode'),
        isTrue,
        reason: '「会话」大标题点击必须与会话页 ▾ 的显示条件同源接线',
      );
      expect(
        source.contains('openSignal: _narrowNavOpenSignal'),
        isTrue,
        reason: '会话页 ▾ 必须接收页面的打开通道',
      );
    });
  });
}
