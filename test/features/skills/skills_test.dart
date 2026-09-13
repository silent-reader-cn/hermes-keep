import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/skills.dart';
import 'package:hermes_ui/features/skills/skills_api.dart';
import 'package:hermes_ui/features/skills/skills_page.dart';
import 'package:hermes_ui/features/skills/skills_providers.dart';

import '../../helpers/fake_skills_api.dart';

SkillSummary buildSkill(
  String name, {
  String? category,
  String? description,
  List<String>? tags,
  bool? disabled,
  String? path,
  List<String>? relatedSkills,
}) {
  return SkillSummary(
    name: name,
    category: category,
    description: description,
    tags: tags,
    disabled: disabled,
    path: path,
    relatedSkills: relatedSkills,
  );
}

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeSkillsApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      skillsApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('buildSkillGroups 分组与过滤', () {
    test('按分类分组：分类名升序，组内按展示名升序（大小写不敏感）', () {
      final skills = [
        buildSkill('beta', category: '工具'),
        buildSkill('alpha', category: '工具'),
        buildSkill('zeta', category: 'Agent'),
        buildSkill('omega', category: 'Agent'),
      ];
      final groups = buildSkillGroups(skills);

      expect(groups.map((g) => g.title).toList(), ['Agent', '工具']);
      expect(groups[0].skills.map((s) => s.name).toList(), ['omega', 'zeta']);
      expect(groups[1].skills.map((s) => s.name).toList(), ['alpha', 'beta']);
    });

    test('无分类技能 → 「未分类」分组', () {
      final groups = buildSkillGroups([
        buildSkill('x'),
        buildSkill('y', category: '  '),
      ]);
      expect(groups.map((g) => g.title).toList(), ['未分类']);
      expect(groups.single.skills, hasLength(2));
    });

    test('空输入 / 空查询 → 空分组 / 全部分组', () {
      expect(buildSkillGroups(const []), isEmpty);
      expect(buildSkillGroups([buildSkill('a')], query: '  '), hasLength(1));
    });

    test('skillHasDetail：仅 path 或 relatedSkills 非空才为 true', () {
      expect(skillHasDetail(buildSkill('plain')), isFalse);
      expect(skillHasDetail(buildSkill('ws-path', path: '  ')), isFalse);
      expect(
        skillHasDetail(buildSkill('ws-related', relatedSkills: ['  ', ''])),
        isFalse,
      );
      expect(skillHasDetail(buildSkill('p', path: '/a/b')), isTrue);
      expect(skillHasDetail(buildSkill('r', relatedSkills: ['alpha'])), isTrue);
      expect(
        skillHasDetail(buildSkill('both', path: '/p', relatedSkills: ['x'])),
        isTrue,
      );
    });

    test('搜索：名称 / 描述 / 分类 / 标签任一命中，大小写不敏感', () {
      final skills = [
        buildSkill('bug-finder', description: '查找并修复 bug', tags: ['debug']),
        buildSkill('writer', description: '写文档', tags: ['docs']),
        buildSkill('tool-a', category: 'media'),
        buildSkill('plain', description: 'x'),
      ];
      expect(
        buildSkillGroups(skills, query: 'bug').single.skills.single.name,
        'bug-finder',
      );
      expect(
        buildSkillGroups(skills, query: '写文档').single.skills.single.name,
        'writer',
      );
      expect(
        buildSkillGroups(skills, query: 'MEDIA').single.skills.single.name,
        'tool-a',
      );
      expect(
        buildSkillGroups(skills, query: 'debug').single.skills.single.name,
        'bug-finder',
      );
      expect(buildSkillGroups(skills, query: 'no-such'), isEmpty);
    });
  });

  group('SkillsController 状态机', () {
    test('初始加载成功：AsyncData + 技能列表 + 派生分组', () async {
      final api = FakeSkillsApi(skills: [buildSkill('a'), buildSkill('b')]);
      final container = makeContainer(api);

      await container.read(skillsControllerProvider.future);
      final state = container.read(skillsControllerProvider).valueOrNull!;

      expect(api.fetchCount, 1);
      expect(state.skills, hasLength(2));
      expect(state.searchQuery, isNull);
      expect(container.read(skillsGroupsProvider).single.title, '未分类');
    });

    test('初始加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeSkillsApi(skills: [buildSkill('a')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(skillsControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(skillsControllerProvider).hasError, isTrue);
      expect(container.read(skillsControllerProvider).valueOrNull, isNull);

      api.fetchError = null;
      await container.read(skillsControllerProvider.notifier).refresh();

      expect(
        container.read(skillsControllerProvider).valueOrNull!.skills,
        hasLength(1),
      );
    });

    test('refresh 重新拉取并保留搜索词', () async {
      final api = FakeSkillsApi(skills: [buildSkill('a')]);
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      controller.setSearchQuery('a');
      expect(
        container.read(skillsControllerProvider).valueOrNull!.searchQuery,
        'a',
      );

      await controller.refresh();
      expect(api.fetchCount, 2);
      expect(
        container.read(skillsControllerProvider).valueOrNull!.searchQuery,
        'a',
      );
    });

    test('setSearchQuery：本地过滤；空串退出过滤', () async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill('bug'),
          buildSkill('writer', description: '写文档'),
        ],
      );
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      controller.setSearchQuery('bug');
      expect(
        container.read(skillsGroupsProvider).single.skills.single.name,
        'bug',
      );

      controller.setSearchQuery('');
      expect(
        container.read(skillsControllerProvider).valueOrNull!.searchQuery,
        isNull,
      );
      expect(container.read(skillsGroupsProvider).single.skills, hasLength(2));
    });

    test('toggleSkill：开启原本已禁用的技能（disabled: true -> false）', () async {
      final api = FakeSkillsApi(
        skills: [buildSkill('my-skill', disabled: true)],
      );
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      final skill = container
          .read(skillsControllerProvider)
          .valueOrNull!
          .skills
          .single;
      final result = await controller.toggleSkill(skill);

      expect(result, isTrue);
      expect(api.toggleCalls, hasLength(1));
      expect(api.toggleCalls.single.name, 'my-skill');
      expect(api.toggleCalls.single.enabled, isTrue);

      final updated = container
          .read(skillsControllerProvider)
          .valueOrNull!
          .skills
          .single;
      expect(updated.disabled, isFalse);
    });

    test('toggleSkill：关闭原本已启用的技能（disabled: false -> true）', () async {
      final api = FakeSkillsApi(
        skills: [buildSkill('my-skill', disabled: false)],
      );
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      final skill = container
          .read(skillsControllerProvider)
          .valueOrNull!
          .skills
          .single;
      final result = await controller.toggleSkill(skill);

      expect(result, isTrue);
      expect(api.toggleCalls, hasLength(1));
      expect(api.toggleCalls.single.name, 'my-skill');
      expect(api.toggleCalls.single.enabled, isFalse);

      final updated = container
          .read(skillsControllerProvider)
          .valueOrNull!
          .skills
          .single;
      expect(updated.disabled, isTrue);
    });

    test('toggleSkill：服务端返回 ok: false → 回滚并设置 actionError', () async {
      final customApi = _FailingToggleSkillsApi(
        skills: [buildSkill('failing-skill', disabled: false)],
      );
      final customContainer = makeContainer(customApi);
      await customContainer.read(skillsControllerProvider.future);
      final customController = customContainer.read(
        skillsControllerProvider.notifier,
      );

      final skill = customContainer
          .read(skillsControllerProvider)
          .valueOrNull!
          .skills
          .single;
      final result = await customController.toggleSkill(skill);

      expect(result, isFalse);
      final state = customContainer.read(skillsControllerProvider).valueOrNull!;
      expect(state.skills.single.disabled, isFalse); // 回滚为启用
      expect(state.actionError, '切换失败，服务器未确认');
    });

    test('toggleSkill：接口抛异常（ApiException） → 回滚并暴露 error.message', () async {
      final api = FakeSkillsApi(
        skills: [buildSkill('err-skill', disabled: false)],
      );
      api.toggleError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      final skill = container
          .read(skillsControllerProvider)
          .valueOrNull!
          .skills
          .single;
      final result = await controller.toggleSkill(skill);

      expect(result, isFalse);
      final state = container.read(skillsControllerProvider).valueOrNull!;
      expect(state.skills.single.disabled, isFalse); // 回滚
      expect(state.actionError, contains('无法连接'));
    });

    test('toggleSkill：空技能名 → 设置 actionError 并返回 false', () async {
      final api = FakeSkillsApi(skills: [buildSkill('')]);
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      final skill = container
          .read(skillsControllerProvider)
          .valueOrNull!
          .skills
          .single;
      final result = await controller.toggleSkill(skill);

      expect(result, isFalse);
      expect(
        container.read(skillsControllerProvider).valueOrNull!.actionError,
        contains('技能名称为空'),
      );
    });

    test('clearActionError：清除操作错误标记', () async {
      final api = FakeSkillsApi(skills: [buildSkill('')]);
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      final skill = container
          .read(skillsControllerProvider)
          .valueOrNull!
          .skills
          .single;
      await controller.toggleSkill(skill);
      expect(
        container.read(skillsControllerProvider).valueOrNull!.actionError,
        isNotNull,
      );

      await controller.clearActionError();
      expect(
        container.read(skillsControllerProvider).valueOrNull!.actionError,
        isNull,
      );
    });
  });

  group('SkillsPage widget', () {
    Future<void> pumpSkillsPage(
      WidgetTester tester,
      FakeSkillsApi api, {
      Brightness brightness = Brightness.light,
    }) async {
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
            skillsApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp.router(
            theme: CupertinoThemeData(brightness: brightness),
            routerConfig: router,
          ),
        ),
      );
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
    }

    testWidgets('渲染：分类标题 + 技能行（名称/描述/标签/已禁用徽标 + 开关）', (tester) async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill(
            'bug-finder',
            category: '调试',
            description: '查找并修复 bug',
            tags: ['debug'],
            disabled: true,
          ),
          buildSkill('writer', category: '调试', description: '写文档'),
        ],
      );
      await pumpSkillsPage(tester, api);

      expect(find.text('调试'), findsOneWidget);
      expect(find.text('bug-finder'), findsOneWidget);
      expect(find.text('查找并修复 bug'), findsOneWidget);
      expect(find.text('debug'), findsOneWidget);
      expect(find.text('已禁用'), findsOneWidget);
      expect(find.text('writer'), findsOneWidget);
      expect(find.text('写文档'), findsOneWidget);

      final bugSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('skills-toggle-bug-finder')),
      );
      expect(bugSwitch.value, isFalse);

      final writerSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('skills-toggle-writer')),
      );
      expect(writerSwitch.value, isTrue);
    });

    testWidgets('点击开关：切换启停状态且不展开描述详情', (tester) async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill(
            'writer',
            category: '工具',
            description: '写文档',
            path: '/skills/writer',
            disabled: false,
          ),
        ],
      );
      await pumpSkillsPage(tester, api);

      // 初始：开关为开，详情未展开
      final switchFinder = find.byKey(const ValueKey('skills-toggle-writer'));
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);
      expect(find.textContaining('路径'), findsNothing);

      // 点击开关
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump();

      // 开关变为关，调用 toggleSkill 成功，且详情依然未展开
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);
      expect(api.toggleCalls, hasLength(1));
      expect(api.toggleCalls.single.enabled, isFalse);
      expect(find.textContaining('路径'), findsNothing);
    });

    testWidgets('点击行（非开关）：展开/收起描述详情', (tester) async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill(
            'writer',
            category: '工具',
            description: '写文档',
            path: '/skills/writer',
            relatedSkills: ['reader'],
          ),
        ],
      );
      await pumpSkillsPage(tester, api);
      expect(find.textContaining('路径'), findsNothing);

      // 点击行展开
      await tester.tap(find.byKey(const ValueKey('skills-row-writer')));
      await tester.pump();
      expect(find.text('路径：/skills/writer'), findsOneWidget);
      expect(find.text('相关技能：reader'), findsOneWidget);

      // 再次点击行收起
      await tester.tap(find.byKey(const ValueKey('skills-row-writer')));
      await tester.pump();
      expect(find.textContaining('路径'), findsNothing);
    });

    testWidgets('开关操作失败：弹窗展示错误信息，点击好关闭弹窗并清除错误', (tester) async {
      final api = FakeSkillsApi(
        skills: [buildSkill('writer', disabled: false)],
      );
      api.toggleError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpSkillsPage(tester, api);

      // 点击开关触发失败
      await tester.tap(find.byKey(const ValueKey('skills-toggle-writer')));
      await tester.pump();
      await tester.pump();

      // 弹窗提示
      expect(find.text('操作失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      // 点击好关闭弹窗
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump();

      expect(find.text('操作失败'), findsNothing);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染列表', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('到了')]);
      api.fetchGate = Completer<void>();
      await pumpSkillsPage(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('到了'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('空态：暂无技能', (tester) async {
      await pumpSkillsPage(tester, FakeSkillsApi());

      expect(find.text('暂无技能'), findsOneWidget);
      expect(find.text('服务器的技能将显示在这里'), findsOneWidget);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('恢复的技能')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpSkillsPage(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('skills-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('恢复的技能'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('搜索：输入即本地过滤；清空恢复全部', (tester) async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill('bug-finder', description: '修复 bug'),
          buildSkill('writer', description: '写文档'),
        ],
      );
      await pumpSkillsPage(tester, api);
      expect(find.text('writer'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('skills-search')),
        'bug',
      );
      await tester.pump();
      expect(find.text('bug-finder'), findsOneWidget);
      expect(find.text('writer'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('skills-search')), '');
      await tester.pump();
      expect(find.text('writer'), findsOneWidget);
    });

    testWidgets('搜索无结果：未找到相关技能', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('bug-finder')]);
      await pumpSkillsPage(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('skills-search')),
        'zzz',
      );
      await tester.pump();
      expect(find.text('未找到相关技能'), findsOneWidget);
    });

    testWidgets('无详情技能：不显示 chevron 且点击不展开', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('plain')]);
      await pumpSkillsPage(tester, api);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('skills-row-plain')),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('skills-row-plain')),
          matching: find.byIcon(CupertinoIcons.chevron_down),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('skills-row-plain')));
      await tester.pump();
      expect(find.text('该技能没有更多详情'), findsNothing);
      expect(find.textContaining('路径'), findsNothing);
      expect(find.textContaining('相关技能'), findsNothing);
    });

    testWidgets('有 path 详情技能：显示 chevron 且可展开收起', (tester) async {
      final api = FakeSkillsApi(
        skills: [buildSkill('with-path', path: '/skills/with-path')],
      );
      await pumpSkillsPage(tester, api);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('skills-row-with-path')),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('skills-row-with-path')));
      await tester.pump();
      expect(find.text('路径：/skills/with-path'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('skills-row-with-path')),
          matching: find.byIcon(CupertinoIcons.chevron_down),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('skills-row-with-path')));
      await tester.pump();
      expect(find.textContaining('路径'), findsNothing);
    });

    testWidgets('有 relatedSkills 详情技能：显示 chevron 且可展开', (tester) async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill('with-related', relatedSkills: ['alpha', 'beta']),
        ],
      );
      await pumpSkillsPage(tester, api);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('skills-row-with-related')),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('skills-row-with-related')));
      await tester.pump();
      expect(find.text('相关技能：alpha、beta'), findsOneWidget);
    });

    testWidgets('刷新按钮：重新拉取列表', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('a')]);
      await pumpSkillsPage(tester, api);
      expect(api.fetchCount, 1);

      await tester.tap(find.byKey(const ValueKey('skills-refresh')));
      await tester.pump();
      await tester.pump();
      expect(api.fetchCount, 2);
    });

    testWidgets('双主题断言：浅色卡片描边/次级字/展开态 vs 暗色默认与原语义色', (tester) async {
      final skill = buildSkill(
        'git-tool',
        category: '工具',
        description: 'Git 工具集',
        path: '/skills/git-tool',
        disabled: true,
      );

      // 1. 浅色模式
      final lightApi = FakeSkillsApi(skills: [skill]);
      await pumpSkillsPage(tester, lightApi, brightness: Brightness.light);

      // 搜索框浅色装饰与 placeholder
      final searchFieldLight = tester.widget<CupertinoSearchTextField>(
        find.byKey(const ValueKey('skills-search')),
      );
      expect(searchFieldLight.decoration, isNotNull);
      final searchBoxDecLight = searchFieldLight.decoration as BoxDecoration;
      expect(searchBoxDecLight.color, LightSurfaces.card);
      expect(searchBoxDecLight.border?.top.color, LightSurfaces.cardBorder);
      expect(
        searchFieldLight.placeholderStyle?.color,
        LightSurfaces.placeholder,
      );
      expect(searchFieldLight.itemColor, LightSurfaces.textSecondary);

      // 列表分组浅色白卡 + hairline + divider
      final sectionLight = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(sectionLight.separatorColor, LightSurfaces.divider);
      final sectionBoxDecLight = sectionLight.decoration as BoxDecoration;
      expect(sectionBoxDecLight.color, LightSurfaces.card);
      expect(sectionBoxDecLight.border?.top.color, LightSurfaces.cardBorder);

      // 描述次级文字浅色达标 textSecondary
      final descTextLight = tester.widget<Text>(find.text('Git 工具集'));
      expect(descTextLight.style?.color, LightSurfaces.textSecondary);

      // 展开 chevron 图标浅色 textSecondary
      final chevronLight = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('skills-row-git-tool')),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
      );
      expect(chevronLight.color, LightSurfaces.textSecondary);

      // 点击展开详情行，检查 label 浅色 textSecondary
      await tester.tap(find.byKey(const ValueKey('skills-row-git-tool')));
      await tester.pump();
      final detailTextLight = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText().contains('路径：') == true,
        ),
      );
      final spanLight = detailTextLight.textSpan as TextSpan;
      final labelSpanLight = spanLight.children!.first as TextSpan;
      expect(labelSpanLight.text, '路径：');
      expect(labelSpanLight.style?.color, LightSurfaces.textSecondary);

      // 2. 暗色模式
      final darkApi = FakeSkillsApi(skills: [skill]);
      await pumpSkillsPage(tester, darkApi, brightness: Brightness.dark);

      // 搜索框暗色回退 null
      final searchFieldDark = tester.widget<CupertinoSearchTextField>(
        find.byKey(const ValueKey('skills-search')),
      );
      expect(searchFieldDark.decoration, isNull);
      expect(searchFieldDark.placeholderStyle, isNull);
      final darkContext = tester.element(
        find.byKey(const ValueKey('skills-search')),
      );
      expect(
        searchFieldDark.itemColor,
        CupertinoColors.secondaryLabel.resolveFrom(darkContext),
      );

      // 列表分组暗色回退 null
      final sectionDark = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(sectionDark.decoration, isNull);
      expect(sectionDark.separatorColor, isNull);

      // 描述次级文字暗色为 secondaryText 动态解析色（非 LightSurfaces.textSecondary）
      final descTextDark = tester.widget<Text>(find.text('Git 工具集'));
      expect(descTextDark.style?.color, secondaryText.resolveFrom(darkContext));
      expect(descTextDark.style?.color, isNot(LightSurfaces.textSecondary));

      // 展开 chevron 暗色为 tertiaryLabel 动态解析色
      final chevronDark = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('skills-row-git-tool')),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
      );
      expect(
        chevronDark.color,
        CupertinoColors.tertiaryLabel.resolveFrom(darkContext),
      );

      // 展开后详情 label 暗色为 secondaryText 动态解析色
      await tester.tap(find.byKey(const ValueKey('skills-row-git-tool')));
      await tester.pump();
      final detailTextDark = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText().contains('路径：') == true,
        ),
      );
      final spanDark = detailTextDark.textSpan as TextSpan;
      final labelSpanDark = spanDark.children!.first as TextSpan;
      expect(labelSpanDark.text, '路径：');
      expect(
        labelSpanDark.style?.color,
        secondaryText.resolveFrom(darkContext),
      );
    });
  });
}

class _FailingToggleSkillsApi extends FakeSkillsApi {
  _FailingToggleSkillsApi({super.skills});

  @override
  Future<ToggleSkillResponse> toggleSkill({
    required String name,
    required bool enabled,
  }) async {
    return const ToggleSkillResponse(ok: false, name: null, enabled: null);
  }
}
