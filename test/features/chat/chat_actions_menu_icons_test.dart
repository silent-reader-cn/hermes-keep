import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/widgets/adaptive_action_menu.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/app/widgets/menu_metrics.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';

import '../../helpers/fake_chat_api.dart';

// ---------------------------------------------------------------------------
// 聊天页「⋯」菜单（`lib/features/chat/chat_page.dart` `_showSessionActions`）
// 图标 + 五族分组的渲染护栏（设计稿 `sketches/dialog-family-proposal.html` §5）。
//
// 钉死三件事：
//
// 1. **13 项各有图标、且图标就是设计稿那张表的那个**（逐项按 key 校验
//    `ActionMenuRow.icon` 与真正渲染出的 `Icon`，不是「看起来有图标」）；
// 2. **五族分组**：把渲染树里 `ActionMenuRow` / `ActionMenuDivider` 按 y 排序，
//    得到的「分组线-行」序列必须逐项等于按族算出来的期望序列 —— 这样既钉了
//    项的**顺序**，也钉了分组线**恰好出现在族边界**（多一条、少一条、错位置都红）；
// 3. **窄屏视觉不变**：窄屏走 `CupertinoActionSheet`，同一份 items（图标字段
//    有值 vs 全空）渲染结果**逐项几何相同**，且 sheet 子树里 `Icon` 数量为 0
//    —— 这是「图标字段只在宽屏被消费」的运行时证据；同一条再由源级守卫
//    （窄屏分支不含 `item.icon` / `ActionMenuDivider` / `ActionMenuRow`）兜底。
//
// 「打开项目文件夹」只在 Windows 桌面 + 会话有 workspace 时出现（判据是
// `Platform.isWindows`，即**目标环境**），故数量与顺序期望按平台动态算，
// Linux CI 上不会假红。
// ---------------------------------------------------------------------------

/// 菜单项所属族（顺序即设计稿的族顺序）。
enum _Group { session, context, open, derive, danger }

/// 设计稿 §5 的图标表：顺序 = 渲染顺序，`windowsOnly` 项按平台出现。
class _MenuSpec {
  const _MenuSpec(this.key, this.icon, this.group, {this.windowsOnly = false});

  final String key;
  final IconData icon;
  final _Group group;
  final bool windowsOnly;
}

const List<_MenuSpec> _specs = <_MenuSpec>[
  // 族①会话
  _MenuSpec(
    'chat-action-rename',
    CupertinoIcons.pencil_outline,
    _Group.session,
  ),
  _MenuSpec('chat-action-pin', CupertinoIcons.pin, _Group.session),
  _MenuSpec('chat-action-archive', CupertinoIcons.archivebox, _Group.session),
  // 族②上下文
  _MenuSpec(
    'chat-action-compress',
    CupertinoIcons.arrow_down_doc,
    _Group.context,
  ),
  _MenuSpec(
    'chat-action-undo',
    CupertinoIcons.arrow_uturn_left,
    _Group.context,
  ),
  _MenuSpec(
    'chat-action-retry',
    CupertinoIcons.arrow_clockwise,
    _Group.context,
  ),
  _MenuSpec('chat-action-yolo', CupertinoIcons.bolt, _Group.context),
  // 族③打开
  _MenuSpec('chat-action-workspace', CupertinoIcons.folder, _Group.open),
  _MenuSpec(
    'chat-action-open-project-folder',
    CupertinoIcons.folder_open,
    _Group.open,
    windowsOnly: true,
  ),
  _MenuSpec('chat-action-git', CupertinoIcons.arrow_branch, _Group.open),
  // 族④派生
  _MenuSpec('chat-action-branch', CupertinoIcons.square_stack, _Group.derive),
  _MenuSpec(
    'chat-action-export',
    CupertinoIcons.square_arrow_up,
    _Group.derive,
  ),
  // 族⑤危险
  _MenuSpec('chat-action-delete', CupertinoIcons.trash, _Group.danger),
];

/// 本平台是否会出现「打开项目文件夹」（与 `_showSessionActions` 同一个判据）。
final bool _windowsDesktop = !kIsWeb && Platform.isWindows;

/// 本平台应有的菜单项（顺序不变）。
List<_MenuSpec> _expectedSpecs() =>
    _specs.where((s) => !s.windowsOnly || _windowsDesktop).toList();

/// 期望的分组边界：相邻两项族不同 ⇒ 该项前有一条分组线（首项永不带线）。
List<bool> _expectedStartsGroup(List<_MenuSpec> specs) => [
  for (var i = 0; i < specs.length; i++)
    i > 0 && specs[i].group != specs[i - 1].group,
];

/// 期望的「分组线?-项」渲染序列（`null` = 分组线）。
List<String?> _expectedSequence(List<_MenuSpec> specs) {
  final startsGroup = _expectedStartsGroup(specs);
  return [
    for (var i = 0; i < specs.length; i++) ...[
      if (startsGroup[i]) null,
      specs[i].key,
    ],
  ];
}

/// 会话 JSON：带 workspace（「打开项目文件夹」的显示前提）。
Map<String, Object?> _session({bool readOnly = false}) => {
  'session': {
    'session_id': 's1',
    'title': '会话',
    'workspace': 'D:/proj',
    if (readOnly) 'read_only': true,
    'messages': const <Object?>[],
  },
};

Future<void> _pumpChat(
  WidgetTester tester,
  FakeChatApi api, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/chat/s1',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const CupertinoPageScaffold(child: Center(child: Text('列表页'))),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) =>
            ChatPage(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/workspace/:sessionId',
        builder: (context, state) =>
            const CupertinoPageScaffold(child: Center(child: Text('工作区'))),
      ),
      GoRoute(
        path: '/git/:sessionId',
        builder: (context, state) =>
            const CupertinoPageScaffold(child: Center(child: Text('Git'))),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 打开右上角「⋯」菜单并等动画落定。
Future<void> _openActionsMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 卸载 ProviderScope（dispose 容器，避免 pending timer）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// 按屏幕 y 升序取出（行 / 分组线）序列，`null` 代表分组线。
List<String?> _visualSequence(WidgetTester tester) {
  final entries = <(double, String?)>[];
  for (final element in find.byType(ActionMenuRow).evaluate()) {
    final row = element.widget as ActionMenuRow;
    final box = element.renderObject! as RenderBox;
    entries.add((
      box.localToGlobal(Offset.zero).dy,
      (row.key! as ValueKey<String>).value,
    ));
  }
  for (final element in find.byType(ActionMenuDivider).evaluate()) {
    final box = element.renderObject! as RenderBox;
    entries.add((box.localToGlobal(Offset.zero).dy, null));
  }
  entries.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final e in entries) e.$2];
}

/// 起一个最小宽屏页面（可指定主题），点按钮弹出 `AdaptiveActionMenu`。
///
/// 只为「行两态布局一致 / 卡片不越屏 / 切口落在行边界」三条布局性质取证用；
/// 与聊天页真实入口解耦，尺寸与 items 由用例决定。
Future<void> _pumpActionMenu(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  required List<AdaptiveMenuItem> items,
  String? title,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final anchor = GlobalKey();
  await tester.pumpWidget(
    CupertinoApp(
      theme: buildCupertinoTheme(brightness),
      home: CupertinoPageScaffold(
        child: Center(
          child: CupertinoButton(
            key: anchor,
            onPressed: () => unawaited(
              AdaptiveActionMenu.show(
                tester.element(find.byKey(anchor)),
                anchorKey: anchor,
                title: title,
                preferredWidth: kActionMenuMaxWidthWide,
                items: items,
              ),
            ),
            child: const Text('打开菜单'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(anchor));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 13 项菜单（与聊天三点菜单同构：3/4/3/2/1 五族 ⇒ 4 条分组线）。
List<AdaptiveMenuItem> _thirteenItems() => [
  for (var i = 0; i < 13; i++)
    AdaptiveMenuItem(
      key: ValueKey<String>('probe-item-$i'),
      label: '动作 ${i + 1}',
      icon: CupertinoIcons.pencil_outline,
      startsGroup: const {3, 7, 10, 12}.contains(i),
      onPressed: () {},
    ),
];

/// 弹层卡片的矩形（`_PopoverCard` 是唯一带 14 圆角 `BoxDecoration` 的容器）。
Rect _cardRect(WidgetTester tester) {
  final card = find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).borderRadius ==
            BorderRadius.circular(14),
  );
  expect(card, findsOneWidget, reason: '弹层卡片应恰好一个');
  return tester.getRect(card);
}

void main() {
  tearDown(AdaptivePopover.debugReset);

  group('宽屏（≥900）：13 项图标 + 五族分组', () {
    testWidgets('逐项图标等于设计稿 §5 图标表，且真的渲染出来', (tester) async {
      final api = FakeChatApi()..sessionResult = _session();
      await _pumpChat(tester, api, size: const Size(1280, 1200));
      await _openActionsMenu(tester);

      final specs = _expectedSpecs();
      expect(
        find.byType(ActionMenuRow),
        findsNWidgets(specs.length),
        reason: '本平台应有 ${specs.length} 项（Windows + workspace ⇒ 13）',
      );

      for (final spec in specs) {
        final rowFinder = find.byKey(ValueKey<String>(spec.key));
        expect(rowFinder, findsOneWidget, reason: '${spec.key} 应在菜单里');
        final row = tester.widget<ActionMenuRow>(rowFinder);
        expect(
          (row.key! as ValueKey<String>).value,
          spec.key,
          reason: '行 key 应与菜单项 key 同源',
        );
        expect(row.icon, spec.icon, reason: '${spec.key} 的图标必须等于设计稿图标表里的那一个');
        expect(
          find.descendant(of: rowFinder, matching: find.byIcon(spec.icon)),
          findsOneWidget,
          reason: '${spec.key} 的图标必须真的绘制在行内（不只是字段有值）',
        );
      }

      await _unmount(tester);
    });

    testWidgets('分组线恰好落在族边界（顺序即设计稿顺序）', (tester) async {
      final api = FakeChatApi()..sessionResult = _session();
      await _pumpChat(tester, api, size: const Size(1280, 1200));
      await _openActionsMenu(tester);

      final specs = _expectedSpecs();
      expect(
        _visualSequence(tester),
        _expectedSequence(specs),
        reason: '渲染顺序 + 分组线位置必须逐项等于按族算出的期望',
      );

      // 行高仍是鼠标档 30（加图标不得撑高行）。
      for (final spec in specs) {
        expect(
          tester.getSize(find.byKey(ValueKey<String>(spec.key))).height,
          30.0,
          reason: '${spec.key} 行高必须仍是 kActionMenuRowHeightWide=30',
        );
      }

      // 分组线数量 = 出现的族数 - 1（菜单无 title，标题下那条不存在）。
      final families = _Group.values
          .where((g) => specs.any((s) => s.group == g))
          .length;
      expect(find.byType(ActionMenuDivider), findsNWidgets(families - 1));

      await _unmount(tester);
    });

    testWidgets('只读会话：前七项与删除隐藏后分组线自然收敛（首项前无分组线）', (tester) async {
      final api = FakeChatApi()..sessionResult = _session(readOnly: true);
      await _pumpChat(tester, api, size: const Size(1280, 1200));
      await _openActionsMenu(tester);

      const hidden = {
        'chat-action-rename',
        'chat-action-pin',
        'chat-action-archive',
        'chat-action-compress',
        'chat-action-undo',
        'chat-action-retry',
        'chat-action-yolo',
        'chat-action-delete',
      };
      final specs = _expectedSpecs()
          .where((s) => !hidden.contains(s.key))
          .toList();
      expect(find.byType(ActionMenuRow), findsNWidgets(specs.length));

      final expected = _expectedSequence(specs);
      expect(expected.first, isNotNull, reason: '首项之前不得有分组线');
      expect(_visualSequence(tester), expected);

      await _unmount(tester);
    });
  });

  group('窄屏（<900）：视觉不变', () {
    testWidgets('仍走 CupertinoActionSheet：无密排行 / 无分组线 / sheet 内零 Icon', (
      tester,
    ) async {
      final api = FakeChatApi()..sessionResult = _session();
      await _pumpChat(tester, api, size: const Size(800, 1200));
      await _openActionsMenu(tester);

      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byType(ActionMenuRow), findsNothing, reason: '窄屏不得出现密排行');
      expect(find.byType(ActionMenuDivider), findsNothing, reason: '窄屏不得出现分组线');
      expect(
        find.descendant(
          of: find.byType(CupertinoActionSheet),
          matching: find.byType(Icon),
        ),
        findsNothing,
        reason: 'CupertinoActionSheet 不支持图标，sheet 子树里必须一个 Icon 都没有',
      );

      // 同一份 items 的动作仍在，顺序不变（语义不变）。
      // 取消按钮也带 key（`chat-action-cancel`），单独断言，不混进动作序列。
      final specs = _expectedSpecs();
      final actionKeys = tester
          .widgetList<CupertinoActionSheetAction>(
            find.byType(CupertinoActionSheetAction),
          )
          .map((a) => (a.key as ValueKey<String>?)?.value)
          .whereType<String>()
          .where((k) => k != 'chat-action-cancel')
          .toList();
      expect(actionKeys, [for (final s in specs) s.key]);
      expect(
        find.byKey(const ValueKey('chat-action-cancel')),
        findsOneWidget,
        reason: '窄屏取消按钮仍在',
      );

      // 触屏档行高（44）没被密排压扁。
      for (final spec in specs) {
        expect(
          tester.getSize(find.byKey(ValueKey<String>(spec.key))).height,
          greaterThanOrEqualTo(44.0),
        );
      }

      await _unmount(tester);
    });

    testWidgets('同一批 items「带图标 vs 不带图标」窄屏渲染逐项几何相同', (tester) async {
      // 图标字段只在宽屏被消费 —— 这个 A/B 就是它的运行时证明：
      // 只有 icon/startsGroup 有差别，窄屏几何必须完全一致（含行序）。
      Future<List<(String, Rect)>> render({required bool withIcons}) async {
        final anchor = GlobalKey();
        final items = <AdaptiveMenuItem>[];
        for (var i = 0; i < _specs.length; i++) {
          final spec = _specs[i];
          final startsGroup = i > 0 && _specs[i].group != _specs[i - 1].group;
          items.add(
            AdaptiveMenuItem(
              key: ValueKey<String>(spec.key),
              label: '动作 ${i + 1}',
              icon: withIcons ? spec.icon : null,
              startsGroup: withIcons && startsGroup,
              onPressed: () {},
            ),
          );
        }
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(800, 1200)),
            child: CupertinoApp(
              home: CupertinoPageScaffold(
                child: Center(
                  child: CupertinoButton(
                    key: anchor,
                    onPressed: () => unawaited(
                      AdaptiveActionMenu.show(
                        tester.element(find.byKey(anchor)),
                        anchorKey: anchor,
                        items: items,
                      ),
                    ),
                    child: const Text('打开菜单'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(anchor));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final out = <(String, Rect)>[];
        for (final element
            in find.byType(CupertinoActionSheetAction).evaluate()) {
          final action = element.widget as CupertinoActionSheetAction;
          // 取消按钮在此 A/B 里没有 key（本组只对照 13 个动作项的几何）。
          final key = (action.key as ValueKey<String>?)?.value;
          if (key == null) continue;
          out.add((key, tester.getRect(find.byKey(ValueKey<String>(key)))));
        }
        return out;
      }

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final withIcons = await render(withIcons: true);
      expect(withIcons.length, _specs.length);
      expect(find.text('动作 1'), findsOneWidget, reason: '窄屏仍按 label 渲染');

      // 换树重排，避免两个 modal 叠在同一 Navigator 上。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final withoutIcons = await render(withIcons: false);
      expect(
        withIcons,
        withoutIcons,
        reason: '窄屏渲染必须与「完全不带图标/分组」的同一批 items 逐项几何相同',
      );

      await _unmount(tester);
    });
  });

  group('源级守卫：窄屏分支不消费 icon / startsGroup', () {
    test('adaptive_action_menu.dart 的 ActionSheet 分支里没有 item.icon / 分组线', () {
      final source = File('lib/app/widgets/adaptive_action_menu.dart')
          .readAsStringSync();
      // 宽屏分支直接调 `showAdaptivePopover`（为传 `rowHeights` 做行边界收敛；
      // 旧路径经 `showCupertinoPopover` 薄转发，没有该参数）。
      final wideIndex = source.indexOf('await showAdaptivePopover(');
      final narrowIndex = source.indexOf(
        'await showCupertinoModalPopup<void>(',
      );
      expect(wideIndex, greaterThan(0), reason: '宽屏分支应存在');
      expect(narrowIndex, greaterThan(wideIndex), reason: '窄屏分支应存在且在后');

      final wide = source.substring(wideIndex, narrowIndex);
      final narrow = source.substring(narrowIndex);

      expect(wide, contains('icon: item.icon'));
      expect(wide, contains('ActionMenuDivider()'));
      for (final token in const [
        'item.icon',
        'ActionMenuDivider',
        'ActionMenuRow',
        'startsGroup',
      ]) {
        expect(
          narrow,
          isNot(contains(token)),
          reason: '窄屏分支不得引用 $token（否则窄屏视觉会变）',
        );
      }
    });
  });

  // 宽屏弹层菜单的三条布局性质（与具体入口无关的几何护栏）。
  group('宽屏弹层菜单布局护栏', () {
    // ① 行两态布局一致：内容垂直居中。
    // 旧实现按主题分两支（浅色 CupertinoListTile / 暗色 CupertinoButton），
    // CupertinoListTile 把 title 装在 spaceBetween 里 → 被 30 定高压到上沿
    // （实测内容中心比行中心高 8.00pt）。两态必须是同一套布局。
    for (final brightness in Brightness.values) {
      testWidgets('$brightness 菜单行内容与行垂直居中（差 ≤0.5pt）', (tester) async {
        await _pumpActionMenu(
          tester,
          size: const Size(1280, 800),
          brightness: brightness,
          items: [
            AdaptiveMenuItem(
              key: const ValueKey('probe-row'),
              label: '探测行',
              icon: CupertinoIcons.pencil_outline,
              shortcut: ActionMenuShortcut.primary(LogicalKeyboardKey.keyC),
              onPressed: () {},
            ),
          ],
        );
        final row = find.byKey(const ValueKey('probe-row'));
        expect(row, findsOneWidget);
        final rowCenter = tester.getRect(row).center.dy;
        final textCenter = tester
            .getRect(find.descendant(of: row, matching: find.text('探测行')))
            .center
            .dy;
        expect(
          (textCenter - rowCenter).abs(),
          lessThanOrEqualTo(0.5),
          reason: '$brightness：行内文字必须与行垂直居中（两态同一布局）',
        );
        final iconCenter = tester
            .getRect(
              find.descendant(
                of: row,
                matching: find.byIcon(CupertinoIcons.pencil_outline),
              ),
            )
            .center
            .dy;
        expect(
          (iconCenter - rowCenter).abs(),
          lessThanOrEqualTo(0.5),
          reason: '$brightness：行内图标必须与行垂直居中',
        );
        await _unmount(tester);
      });
    }

    // ② 卡片高度收敛到该侧真实可用高度，不越出屏幕。
    // 旧实现只给一个纵向偏移（Positioned(bottom:)），Stack 给宽松约束 →
    // 13 项菜单在锚点居中时卡片 top ≈ -24.5（首行不可达）。
    testWidgets('13 项菜单锚点居中：卡片完全落在屏内（1280×800）', (tester) async {
      await _pumpActionMenu(
        tester,
        size: const Size(1280, 800),
        brightness: Brightness.light,
        items: _thirteenItems(),
      );
      final card = _cardRect(tester);
      expect(card.top, greaterThanOrEqualTo(0.0), reason: '卡片顶边越出屏顶');
      expect(card.bottom, lessThanOrEqualTo(800.0), reason: '卡片底边越出屏底');
      await _unmount(tester);
    });

    // ③ 防御性收敛：可用高度成为约束时（短窗口），切口必须落在两行之间。
    // 逐行判「整行在卡片内 or 完全在卡片外」，不存在跨卡片底边的行。
    testWidgets('短窗口 1280×560：13 项菜单每行不跨卡片底边', (tester) async {
      await _pumpActionMenu(
        tester,
        size: const Size(1280, 560),
        brightness: Brightness.light,
        title: '会话操作',
        items: _thirteenItems(),
      );
      expect(find.byType(ActionMenuRow), findsNWidgets(13));
      final card = _cardRect(tester);
      // 卡片内容视口底边 = 卡片矩形底边 - 1pt 边框：`_PopoverCard` 的 1px 边框
      // 由 `Container` 的 decoration padding 消费，内容视口因此比卡片矩形内缩
      // 1pt。「整行在卡片内」指的是在**内容视口**里（边框那 1pt 画在边上，不是
      // 内容区）。用卡片外缘判会让一个「零像素可见」的下一行看起来像跨了边。
      const cardBorder = kPopoverMenuCardChrome / 2;
      final viewportBottom = card.bottom - cardBorder;
      for (var i = 0; i < 13; i++) {
        final rect = tester.getRect(
          find.byKey(ValueKey<String>('probe-item-$i')),
        );
        expect(
          rect.bottom <= viewportBottom + 0.5 ||
              rect.top >= viewportBottom - 0.5,
          isTrue,
          reason:
              '第 ${i + 1} 行（${rect.top}..${rect.bottom}）跨了内容视口底边 '
              '$viewportBottom（卡片 ${card.top}..${card.bottom}）'
              ' —— 切口必须落在两行之间',
        );
      }
      await _unmount(tester);
    });
  });
}
