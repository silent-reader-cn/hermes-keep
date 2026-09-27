import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/skills.dart';
import 'package:hermes_ui/features/skills/skills_api.dart';
import 'package:hermes_ui/features/skills/skills_page.dart';

import '../../helpers/fake_skills_api.dart';

/// 批 4 · P2 守卫：技能页宽屏（≥900）**左 320 列表 + 右详情（正文限宽 744 居中）**；
/// 窄屏（<900）保留原**手风琴就地展开**，逐像素不变（像素级证据见交付报告里的
/// `.shots/b4a` 前后对照工装：400 / 880 × 浅暗 × 默认/展开共 16 张逐像素一致）。
///
/// 规范出处：`sketches/wide-pages-batch4-decision.html` §P2 ＋
/// `sketches/wide-redesign-v2-corrected.html` §P2（修正版：现状是**手风琴**，
/// 不是「整页跳走」；拆右栏的理由是「右半屏空着 + 展开推长列表 + 可连续对比」）。
///
/// 容器宽度口径：本文件**裸挂页面**（无 AdaptiveShell 侧栏），故 1280 窗口下
/// 右栏 = 1280 − 320 = 960 > 744 ⇒ 744 限宽真正咬合，左右留白各 108；
/// 1600 ⇒ 右栏 1280 ⇒ 左右各 268。真机带 shell 时（侧栏 320）1280 窗口的右栏
/// 只有 640 < 744，限宽不咬合、内容吃满右栏（与批 3 设置页同一现象，见
/// `settings_wide_category_nav_test.dart` 顶部注释）。

const String _alphaPath = r'C:\Users\Admin\AppData\Local\hermes\skills\alpha-skill\SKILL.md';
const String _betaPath = r'C:\Users\Admin\AppData\Local\hermes\skills\beta-skill\SKILL.md';

/// 三条技能同属一组（分组标题 = `项目技能`），组内按展示名升序：
/// alpha-skill → beta-skill → gamma-skill（与页面 buildSkillGroups 同口径）。
List<SkillSummary> _demoSkills() => [
  const SkillSummary(
    name: 'alpha-skill',
    category: '项目',
    description: '第一个技能的描述（左栏单行省略用）',
    tags: ['tag-x'],
    path: _alphaPath,
    relatedSkills: ['beta-skill'],
  ),
  const SkillSummary(
    name: 'beta-skill',
    category: '项目',
    description: '第二个技能的描述',
    path: _betaPath,
  ),
  const SkillSummary(
    name: 'gamma-skill',
    category: '项目',
    description: '第三个技能的描述',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  Brightness brightness = Brightness.light,
  FakeSkillsApi? api,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, _) => const SkillsPage())],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        skillsApiFactoryProvider.overrideWithValue(
          (_) => api ?? FakeSkillsApi(skills: _demoSkills()),
        ),
      ],
      child: CupertinoApp.router(
        theme: buildCupertinoTheme(brightness),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 左栏容器（窄屏**不应**存在）。
Finder get _rail => find.byKey(const ValueKey('skills-rail'));

/// 右栏详情面板（含 744 限宽盒）。
Finder get _detailPane => find.byKey(const ValueKey('skills-detail-pane'));

/// 右栏的 744 限宽盒（窄屏**不应**存在）。
Finder get _detailBox => find.descendant(
  of: _detailPane,
  matching: find.byWidgetPredicate(
    (w) => w is ConstrainedBox && w.constraints.maxWidth == 744,
  ),
);

Finder _railRow(String name) => find.byKey(ValueKey('skills-rail-row-$name'));

/// 窄屏行内手风琴详情的 key（宽屏**不应**存在）。
Finder _inlineDetail(String name) =>
    find.byKey(ValueKey('skills-detail-$name'));

/// 取某技能在左栏的名字文字（断言 L2 选中态用）。
Text _railName(WidgetTester tester, String name) => tester.widget<Text>(
  find.descendant(of: _railRow(name), matching: find.text(name)),
);

/// 取某技能左栏行自身的按钮（断言 L2 选中底）。
CupertinoButton _railTap(WidgetTester tester, String name) =>
    tester.widget<CupertinoButton>(
      find.byKey(ValueKey('skills-rail-tap-$name')),
    );

void main() {
  group('技能页宽屏双栏（批 4 · P2）', () {
    testWidgets('宽屏 1280：左 320 列表 + 右详情限宽 744 居中，行含名称 + 描述', (tester) async {
      await _pump(tester, size: const Size(1280, 800));

      expect(_rail, findsOneWidget, reason: '宽屏应有左栏');
      final rail = tester.getRect(_rail);
      expect(rail.width, 320, reason: '左栏固定 320');
      expect(rail.left, 0, reason: '左栏贴页面左缘');
      expect(rail.height, greaterThan(200));

      // 搜索框移进左栏（窄屏在页顶）；分组标题在左栏
      expect(
        find.descendant(of: _rail, matching: find.text('项目技能')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _rail,
          matching: find.byKey(const ValueKey('skills-search')),
        ),
        findsOneWidget,
        reason: '宽屏搜索框在左栏顶部（过滤列表）',
      );

      // 三条技能都在左栏，且各自带单行描述
      for (final name in ['alpha-skill', 'beta-skill', 'gamma-skill']) {
        expect(_railRow(name), findsOneWidget, reason: '$name 应在左栏');
      }
      expect(
        find.descendant(
          of: _rail,
          matching: find.text('第一个技能的描述（左栏单行省略用）'),
        ),
        findsOneWidget,
        reason: '左栏行含描述（单行省略）',
      );

      // 右详情：744 限宽且水平居中于右栏
      expect(_detailBox, findsOneWidget, reason: '右栏应有 744 限宽盒');
      final box = tester.getRect(_detailBox);
      expect(box.width, 744, reason: '右栏 960 > 744 ⇒ 咬合到 744');
      expect(box.left - 320, 108, reason: '左留白 (960−744)/2 = 108');
      expect(1280 - box.right, 108, reason: '右留白相等');
      expect(
        box.left - 320,
        closeTo(1280 - box.right, 0.01),
        reason: '右栏内容必须水平居中',
      );

      // 详情内容 = 描述 / 标签 / 路径 / 相关技能（首个技能默认选中）
      expect(find.textContaining('SKILL.md'), findsOneWidget);
      expect(find.text('tag-x'), findsOneWidget);
      expect(find.textContaining('相关技能'), findsOneWidget);
    });

    testWidgets('宽屏 1600：744 限宽仍在（右栏 1280 ⇒ 左右留白各 268）', (tester) async {
      await _pump(tester, size: const Size(1600, 900));

      final box = tester.getRect(_detailBox);
      expect(box.width, 744);
      expect(box.left - 320, 268, reason: '左留白 (1280−744)/2 = 268');
      expect(1600 - box.right, 268);
      expect(box.left - 320, closeTo(1600 - box.right, 0.01));
    });

    testWidgets('宽屏：手风琴不再就地展开（列表不被推长，右栏换内容）', (tester) async {
      await _pump(tester, size: const Size(1280, 800));

      // 默认选中第一条 → 右栏是 alpha 的详情；行内详情 key 一个都不该有
      expect(find.textContaining(_alphaPath), findsOneWidget);
      for (final name in ['alpha-skill', 'beta-skill', 'gamma-skill']) {
        expect(
          _inlineDetail(name),
          findsNothing,
          reason: '宽屏不得再用行内手风琴详情（$name）',
        );
      }

      final beforeRows = tester.getRect(_railRow('gamma-skill')).top;

      // 点第二行 → 右栏换内容；左栏列表几何完全不变（不推长）
      await tester.tap(_railRow('beta-skill'));
      await tester.pump();

      expect(find.textContaining(_betaPath), findsOneWidget);
      expect(
        find.textContaining(_alphaPath),
        findsNothing,
        reason: '切技能后右栏只留当前技能',
      );
      expect(
        tester.getRect(_railRow('gamma-skill')).top,
        beforeRows,
        reason: '选中只换右栏，各行位置不动（列表不被推长）',
      );
    });

    testWidgets('宽屏：选中态 L2（灰底 + #005FB8 蓝字），未选中行回落到左栏常规取色', (tester) async {
      await _pump(tester, size: const Size(1280, 800));

      // 首帧默认选中第一条
      expect(_railName(tester, 'alpha-skill').style?.color,
          const Color(0xFF005FB8));
      expect(_railTap(tester, 'alpha-skill').color, LightSurfaces.selectedSurface);
      expect(_railTap(tester, 'beta-skill').color, CupertinoColors.transparent);

      await tester.tap(_railRow('beta-skill'));
      await tester.pump();

      expect(_railName(tester, 'beta-skill').style?.color,
          const Color(0xFF005FB8));
      expect(_railTap(tester, 'beta-skill').color, LightSurfaces.selectedSurface);
      expect(
        _railName(tester, 'alpha-skill').style?.color,
        const Color(0xFF3A3A3C),
        reason: '未选中行回落左栏常规文字色（与 WideNavRail 同款）',
      );
      expect(_railTap(tester, 'alpha-skill').color, CupertinoColors.transparent);
    });

    testWidgets('宽屏：左栏开关仍可直接启停技能（功能不因拆栏而丢）', (tester) async {
      final api = FakeSkillsApi(skills: _demoSkills());
      await _pump(tester, size: const Size(1280, 800), api: api);

      await tester.tap(
        find.byKey(const ValueKey('skills-rail-toggle-beta-skill')),
      );
      await tester.pump();
      await tester.pump();

      expect(api.toggleCalls, [(name: 'beta-skill', enabled: false)]);
    });

    testWidgets('宽屏：左栏搜索照常过滤，右栏回落到第一个匹配技能', (tester) async {
      await _pump(tester, size: const Size(1280, 800));

      await tester.enterText(
        find.byKey(const ValueKey('skills-search')),
        'gamma',
      );
      await tester.pump();
      await tester.pump();

      expect(_railRow('gamma-skill'), findsOneWidget);
      expect(_railRow('alpha-skill'), findsNothing, reason: '不匹配的行被过滤掉');
      expect(_railRow('beta-skill'), findsNothing);
      expect(
        find.textContaining('SKILL.md'),
        findsNothing,
        reason: 'gamma 无 path，右栏应换成 gamma 的详情（回落第一个匹配）',
      );
      expect(find.text('第三个技能的描述'), findsWidgets);
    });

    testWidgets('宽屏：搜索无结果时复用既有空态（不硬撑双栏）', (tester) async {
      await _pump(tester, size: const Size(1280, 800));

      await tester.enterText(
        find.byKey(const ValueKey('skills-search')),
        'zzz-no-match',
      );
      await tester.pump();
      await tester.pump();

      expect(_rail, findsNothing, reason: '无列表可拆 ⇒ 回落到单列状态页');
      expect(_detailBox, findsNothing);
      expect(find.text('未找到相关技能'), findsOneWidget);
    });

    testWidgets('断点：899 为窄屏（无左栏 / 无 744 盒，走手风琴）／900 为宽屏（双栏）', (tester) async {
      await _pump(tester, size: const Size(899, 900));
      expect(_rail, findsNothing, reason: '899 < 900 ⇒ 窄屏');
      expect(_detailBox, findsNothing);

      await tester.tap(find.byKey(const ValueKey('skills-row-alpha-skill')));
      await tester.pump();
      expect(
        _inlineDetail('alpha-skill'),
        findsOneWidget,
        reason: '窄屏仍是就地展开的手风琴',
      );

      await _pump(tester, size: const Size(900, 900));
      expect(_rail, findsOneWidget, reason: '900 ≥ 900 ⇒ 宽屏');
      expect(_detailBox, findsOneWidget);
      expect(_inlineDetail('alpha-skill'), findsNothing);
    });

    testWidgets('窄屏 800：手风琴就地展开（详情挂在行下方）、无左栏、无 744 限宽盒', (tester) async {
      await _pump(tester, size: const Size(800, 2000));

      expect(_rail, findsNothing, reason: '窄屏无左栏');
      expect(_detailPane, findsNothing, reason: '窄屏无右详情面板');
      expect(_detailBox, findsNothing, reason: '窄屏无 744 限宽盒');
      expect(find.byKey(const ValueKey('skills-search')), findsOneWidget);

      // 首帧无展开（窄屏不再默认选中）
      expect(_inlineDetail('alpha-skill'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('skills-row-alpha-skill')));
      await tester.pump();

      final row = tester.getRect(
        find.byKey(const ValueKey('skills-row-alpha-skill')),
      );
      final detail = tester.getRect(_inlineDetail('alpha-skill'));
      expect(detail.top, greaterThan(row.top), reason: '详情挂在行下方（手风琴）');
      expect(detail.bottom, lessThanOrEqualTo(row.bottom + 0.01));
    });

    testWidgets('窄屏 800：卡片外边距 / 行内几何逐像素不变（20 外边距）', (tester) async {
      await _pump(tester, size: const Size(800, 2000));

      final row = tester.getRect(
        find.byKey(const ValueKey('skills-row-alpha-skill')),
      );
      // 20 = `CupertinoListSection.insetGrouped` 的默认水平外边距（实测值）。
      // 这条断言钉的是**窄屏几何未被我改动**：改动前后 400 / 880 × 浅暗 ×
      // 默认/展开共 16 张真渲染逐像素一致（见交付报告 .shots/b4a 前后对照）。
      expect(row.left, 20, reason: '窄屏卡片左缘 = 视口 + 20');
      expect(800 - row.right, 20, reason: '窄屏卡片右缘 = 视口 − 20（左右相等）');
    });
  });
}
