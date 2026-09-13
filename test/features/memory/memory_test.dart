import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/memory.dart';
import 'package:hermes_ui/features/memory/memory_api.dart';
import 'package:hermes_ui/features/memory/memory_page.dart';
import 'package:hermes_ui/features/memory/memory_providers.dart';

import '../../helpers/fake_memory_api.dart';

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeMemoryApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      memoryApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('记忆辅助函数', () {
    test('showsProjectContext：仅非空（trim 后）文档展示', () {
      expect(showsProjectContext(const MemoryResponse()), isFalse);
      expect(
        showsProjectContext(const MemoryResponse(projectContext: '   ')),
        isFalse,
      );
      expect(
        showsProjectContext(const MemoryResponse(projectContext: 'x')),
        isTrue,
      );
    });

    test('memoryProjectContextDetail：「名称 — 工作区」，空 → null', () {
      expect(memoryProjectContextDetail(const MemoryResponse()), isNull);
      expect(
        memoryProjectContextDetail(
          const MemoryResponse(
            projectContextName: '  ',
            projectContextWorkspace: '',
          ),
        ),
        isNull,
      );
      expect(
        memoryProjectContextDetail(
          const MemoryResponse(
            projectContextName: 'p',
            projectContextWorkspace: 'w',
          ),
        ),
        'p — w',
      );
      expect(
        memoryProjectContextDetail(
          const MemoryResponse(projectContextName: 'p'),
        ),
        'p',
      );
    });

    test('memoryHasContent：全空 false，任一分区/项目上下文非空 true', () {
      expect(memoryHasContent(const MemoryResponse()), isFalse);
      expect(memoryHasContent(const MemoryResponse(memory: 'm')), isTrue);
      expect(memoryHasContent(const MemoryResponse(user: '  ')), isFalse);
      expect(memoryHasContent(const MemoryResponse(soul: 's')), isTrue);
      expect(
        memoryHasContent(const MemoryResponse(projectContext: 'pc')),
        isTrue,
      );
    });

    test('formatMemoryMtime：相对时间中文描述；null/非法 → null', () {
      final now = DateTime(2026, 8, 16, 12, 0, 0);
      double secs(Duration d) => now.subtract(d).millisecondsSinceEpoch / 1000;

      expect(formatMemoryMtime(null), isNull);
      expect(formatMemoryMtime(double.nan), isNull);
      expect(
        formatMemoryMtime(secs(const Duration(seconds: 30)), now: now),
        '刚刚更新',
      );
      expect(
        formatMemoryMtime(secs(const Duration(minutes: 5)), now: now),
        '5 分钟前更新',
      );
      expect(
        formatMemoryMtime(secs(const Duration(hours: 3)), now: now),
        '3 小时前更新',
      );
      expect(
        formatMemoryMtime(secs(const Duration(days: 10)), now: now),
        '10 天前更新',
      );
      expect(
        formatMemoryMtime(secs(const Duration(days: 40)), now: now),
        '更新于 2026-07-07',
      );
    });
  });

  group('MemoryController 状态机', () {
    test('初始加载成功：AsyncData 携带 MemoryResponse', () async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '笔记', user: '画像'),
      );
      final container = makeContainer(api);

      await container.read(memoryControllerProvider.future);
      final response = container.read(memoryControllerProvider).valueOrNull!;

      expect(api.fetchCount, 1);
      expect(response.memory, '笔记');
      expect(response.user, '画像');
      expect(response.soul, isNull);
    });

    test('初始加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '恢复的记忆'),
      );
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(memoryControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(memoryControllerProvider).hasError, isTrue);
      expect(container.read(memoryControllerProvider).valueOrNull, isNull);

      api.fetchError = null;
      await container.read(memoryControllerProvider.notifier).refresh();

      expect(
        container.read(memoryControllerProvider).valueOrNull!.memory,
        '恢复的记忆',
      );
    });

    test('refresh 重新拉取', () async {
      final api = FakeMemoryApi(response: const MemoryResponse(memory: 'm'));
      final container = makeContainer(api);
      await container.read(memoryControllerProvider.future);
      expect(api.fetchCount, 1);

      await container.read(memoryControllerProvider.notifier).refresh();
      expect(api.fetchCount, 2);
    });
  });

  group('MemoryPage widget', () {
    Future<void> pumpMemoryPage(
      WidgetTester tester,
      FakeMemoryApi api, {
      Brightness brightness = Brightness.light,
    }) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const MemoryPage())],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            memoryApiFactoryProvider.overrideWithValue((_) => api),
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

    testWidgets('渲染：分区 Tab + 内容 + 相对修改时间', (tester) async {
      final mtime =
          DateTime.now()
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch /
          1000;
      final api = FakeMemoryApi(
        response: MemoryResponse(
          memory: '记住用户偏好',
          user: '资深开发者',
          soul: '乐于助人',
          memoryMtime: mtime,
          userMtime: mtime,
          soulMtime: mtime,
        ),
      );
      await pumpMemoryPage(tester, api);

      // 验证 Tab 切换器渲染
      expect(find.byKey(const ValueKey('memory-tab-memory')), findsOneWidget);
      expect(find.byKey(const ValueKey('memory-tab-user')), findsOneWidget);
      expect(find.byKey(const ValueKey('memory-tab-soul')), findsOneWidget);

      // 默认「我的笔记」tab
      expect(find.text('记住用户偏好'), findsOneWidget);
      expect(find.text('2 小时前更新'), findsOneWidget);

      // 切换到「用户画像」tab
      await tester.tap(find.byKey(const ValueKey('memory-tab-user')));
      await tester.pump();
      expect(find.text('资深开发者'), findsOneWidget);
      expect(find.text('2 小时前更新'), findsOneWidget);

      // 切换到「智能体灵魂」tab
      await tester.tap(find.byKey(const ValueKey('memory-tab-soul')));
      await tester.pump();
      expect(find.text('乐于助人'), findsOneWidget);
      expect(find.text('2 小时前更新'), findsOneWidget);
    });

    testWidgets('分区空内容 → 斜体占位文案', (tester) async {
      final api = FakeMemoryApi(response: const MemoryResponse(user: '有内容'));
      await pumpMemoryPage(tester, api);

      // 默认「我的笔记」为空
      expect(find.text('暂无笔记'), findsOneWidget);

      // 切换到「用户画像」
      await tester.tap(find.byKey(const ValueKey('memory-tab-user')));
      await tester.pump();
      expect(find.text('有内容'), findsOneWidget);

      // 切换到「智能体灵魂」为空
      await tester.tap(find.byKey(const ValueKey('memory-tab-soul')));
      await tester.pump();
      expect(find.text('暂无灵魂设定'), findsOneWidget);
    });

    testWidgets('项目上下文分区：内容 + 明细 + 只读锁 + 覆盖警告', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(
          projectContext: '这是项目上下文',
          projectContextName: 'demo',
          projectContextWorkspace: '/workspace/demo',
          projectContextShadowed: true,
        ),
      );
      await pumpMemoryPage(tester, api);

      // 切换到项目上下文 tab
      expect(find.byKey(const ValueKey('memory-tab-project')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('memory-tab-project')));
      await tester.pump();

      expect(find.text('这是项目上下文'), findsOneWidget);
      expect(find.text('demo — /workspace/demo'), findsOneWidget);
      expect(find.textContaining('覆盖'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.lock_fill), findsOneWidget);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染分区', (tester) async {
      final api = FakeMemoryApi(response: const MemoryResponse(memory: '到了'));
      api.fetchGate = Completer<void>();
      await pumpMemoryPage(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('到了'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('全空 → 暂无记忆空态', (tester) async {
      await pumpMemoryPage(tester, FakeMemoryApi());

      expect(find.text('暂无记忆'), findsOneWidget);
      expect(find.text('还没有任何记忆内容'), findsOneWidget);
      // 全空时不再渲染分区标题与 tab 切换器
      expect(find.byKey(const ValueKey('memory-tab-memory')), findsNothing);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '恢复的记忆'),
      );
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpMemoryPage(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('memory-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('恢复的记忆'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('刷新按钮：重新拉取记忆', (tester) async {
      final api = FakeMemoryApi(response: const MemoryResponse(memory: 'm'));
      await pumpMemoryPage(tester, api);
      expect(api.fetchCount, 1);

      await tester.tap(find.byKey(const ValueKey('memory-refresh')));
      await tester.pump();
      await tester.pump();
      expect(api.fetchCount, 2);
    });

    testWidgets('短内容 → 紧凑展示不高胀，无折叠展开按钮', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '记住用户偏好'),
      );
      await pumpMemoryPage(tester, api);

      expect(find.text('记住用户偏好'), findsOneWidget);
      expect(find.textContaining('展开'), findsNothing);
      expect(find.textContaining('收起'), findsNothing);
      expect(find.text('6 字'), findsOneWidget);

      // 验证短内容卡片内滚动容器高度不高胀（紧凑贴合内容高）
      final scrollableSize = tester.getSize(
        find.byType(SingleChildScrollView).first,
      );
      expect(scrollableSize.height, lessThan(100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('长内容 → 视口高度自适应限制且卡片内部滚动不折叠', (tester) async {
      final longText = List.filled(50, '这是一段很长的记忆内容。\n').join();
      final api = FakeMemoryApi(
        response: MemoryResponse(memory: longText, soul: '短'),
      );
      await pumpMemoryPage(tester, api);

      // 无折叠与展开/收起按钮
      expect(find.textContaining('展开'), findsNothing);
      expect(find.textContaining('收起'), findsNothing);

      // 验证存在卡片内部滚动视图，且高度受限于视口（默认测试视口 600 高度下 maxHeight 约为 380）
      final scrollables = find.byType(SingleChildScrollView);
      expect(scrollables, findsOneWidget);
      final scrollableSize = tester.getSize(scrollables.first);
      expect(scrollableSize.height, lessThanOrEqualTo(380));

      // 验证可正常内部滑动且无溢出异常
      await tester.drag(scrollables.first, const Offset(0, -200));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('项目上下文与 Markdown 长内容同样支持卡片内滚动自适应', (tester) async {
      final longMarkdown = List.filled(40, '- 项目上下文长列表条目\n').join();
      final api = FakeMemoryApi(
        response: MemoryResponse(projectContext: longMarkdown),
      );
      await pumpMemoryPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('memory-tab-project')));
      await tester.pump();

      expect(find.textContaining('展开'), findsNothing);
      expect(find.textContaining('收起'), findsNothing);
      expect(find.byType(MarkdownBody), findsOneWidget);

      final scrollables = find.byType(SingleChildScrollView);
      expect(scrollables, findsOneWidget);
      final scrollableSize = tester.getSize(scrollables.first);
      expect(scrollableSize.height, lessThanOrEqualTo(380));

      await tester.drag(scrollables.first, const Offset(0, -200));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('宽屏（≥700）→ 单一 Tab 卡片且 maxWidth 720 居中不双列', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeMemoryApi(
        response: const MemoryResponse(
          memory: 'm',
          user: 'u',
          soul: 's',
          projectContext: 'pc',
        ),
      );
      await pumpMemoryPage(tester, api);

      // 宽屏下只展示当前 tab（默认项目上下文）的单一卡片，不双列并排
      expect(find.text('pc'), findsOneWidget);
      expect(find.text('m'), findsNothing);
      expect(find.text('u'), findsNothing);
      expect(find.text('s'), findsNothing);

      // 验证 ConstrainedBox 限制 maxWidth 为 720
      final constrainedBox = tester.widget<ConstrainedBox>(
        find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 720,
        ),
      );
      expect(constrainedBox.constraints.maxWidth, 720);
    });

    testWidgets('Tab 切换：点击各 Tab 正确切换卡片展示', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(
          memory: '笔记内容',
          user: '用户画像内容',
          soul: '智能体灵魂内容',
          projectContext: '项目上下文内容',
        ),
      );
      await pumpMemoryPage(tester, api);

      // 默认选中项目上下文 Tab（主人指示，2026-08）
      expect(find.text('项目上下文内容'), findsOneWidget);
      expect(find.text('笔记内容'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();
      expect(find.text('笔记内容'), findsOneWidget);
      expect(find.text('项目上下文内容'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('memory-tab-user')));
      await tester.pump();
      expect(find.text('用户画像内容'), findsOneWidget);
      expect(find.text('笔记内容'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('memory-tab-soul')));
      await tester.pump();
      expect(find.text('智能体灵魂内容'), findsOneWidget);
      expect(find.text('用户画像内容'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('memory-tab-project')));
      await tester.pump();
      expect(find.text('项目上下文内容'), findsOneWidget);
      expect(find.text('智能体灵魂内容'), findsNothing);
    });

    testWidgets('智能体灵魂与项目上下文支持 Markdown 渲染', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(
          soul: '# 灵魂标题\n- 规则一\n- 规则二',
          projectContext: '**粗体项目说明**',
        ),
      );
      await pumpMemoryPage(tester, api);

      // 切到智能体灵魂 tab
      await tester.tap(find.byKey(const ValueKey('memory-tab-soul')));
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('灵魂标题'), findsOneWidget);
      expect(find.text('规则一'), findsOneWidget);

      // 切到项目上下文 tab
      await tester.tap(find.byKey(const ValueKey('memory-tab-project')));
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('粗体项目说明'), findsOneWidget);
    });

    testWidgets('分区头副文案样式瘦身：字数与更新时间显式 12pt、w400、secondaryText、Flexible 省略', (
      tester,
    ) async {
      final mtime =
          DateTime.now()
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch /
          1000;
      final api = FakeMemoryApi(
        response: MemoryResponse(
          memory: '测试笔记内容',
          memoryMtime: mtime,
          projectContext: '测试项目上下文内容',
          projectContextMtime: mtime,
        ),
      );
      await pumpMemoryPage(tester, api);

      // 默认处于项目上下文 tab
      final pcCharCountFinder = find.text('9 字');
      final pcModifiedFinder = find.text('1 小时前更新');
      expect(pcCharCountFinder, findsOneWidget);
      expect(pcModifiedFinder, findsOneWidget);

      final pcCharCountText = tester.widget<Text>(pcCharCountFinder);
      expect(pcCharCountText.style?.fontSize, 12);
      expect(pcCharCountText.style?.fontWeight, FontWeight.w400);
      expect(pcCharCountText.overflow, TextOverflow.ellipsis);

      final pcModifiedText = tester.widget<Text>(pcModifiedFinder);
      expect(pcModifiedText.style?.fontSize, 12);
      expect(pcModifiedText.style?.fontWeight, FontWeight.w400);
      expect(pcModifiedText.overflow, TextOverflow.ellipsis);

      // 切换到 memory tab 验证 _MemorySectionHeader
      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();

      final memCharCountFinder = find.text('6 字');
      final memModifiedFinder = find.text('1 小时前更新');
      expect(memCharCountFinder, findsOneWidget);
      expect(memModifiedFinder, findsOneWidget);

      final memCharCountText = tester.widget<Text>(memCharCountFinder);
      expect(memCharCountText.style?.fontSize, 12);
      expect(memCharCountText.style?.fontWeight, FontWeight.w400);
      expect(memCharCountText.overflow, TextOverflow.ellipsis);

      final memModifiedText = tester.widget<Text>(memModifiedFinder);
      expect(memModifiedText.style?.fontSize, 12);
      expect(memModifiedText.style?.fontWeight, FontWeight.w400);
      expect(memModifiedText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('项目上下文覆盖提示：13pt secondary 说明层级，与分区头右簇贴右缘', (tester) async {
      final api = FakeMemoryApi(
        response: MemoryResponse(
          projectContext: '项目上下文内容',
          projectContextShadowed: true,
          projectContextName: 'HERMES.md',
          projectContextWorkspace: 'D:/projects/hermes-ui',
          projectContextMtime:
              DateTime.now()
                  .subtract(const Duration(hours: 1))
                  .millisecondsSinceEpoch /
              1000,
        ),
      );
      await pumpMemoryPage(tester, api);

      // 覆盖提示与明细行：显式 13pt、secondary 说明层级（非继承 17pt 大标题级）
      final warnFinder = find.text('工作区本地文件正在覆盖全局项目上下文。');
      final detailFinder = find.textContaining('HERMES.md');
      expect(warnFinder, findsOneWidget);
      expect(detailFinder, findsWidgets);

      final warnText = tester.widget<Text>(warnFinder);
      expect(warnText.style?.fontSize, 13);
      expect(warnText.style?.fontWeight, FontWeight.w400);

      // 分区头右簇（字数统计 + 修改时间 + 只读锁）沿行右缘 float right：
      // 行末元素（锁图标）右缘贴齐分区卡片右缘，而非摊在行中间标题后。
      final sectionRect = tester.getRect(
        find.byType(CupertinoListSection).first,
      );
      final titleRect = tester.getRect(find.text('项目上下文').last);
      final lockRect = tester.getRect(find.byIcon(CupertinoIcons.lock_fill));
      final charRect = tester.getRect(find.text('7 字'));
      // 右簇整体在标题右侧，且贴齐分区卡内容右缘（16pt 内容内边距 + 容差）。
      expect(lockRect.right, greaterThan(titleRect.right));
      expect(sectionRect.right - lockRect.right, lessThan(60));
      expect(charRect.right, greaterThan(titleRect.right));
      expect(charRect.right, lessThan(lockRect.right));
    });

    testWidgets('进入编辑态：点击编辑按钮 → 隐藏 Markdown / Text，显示 CupertinoTextField', (
      tester,
    ) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(
          memory: '现有笔记内容',
          user: '资深开发者',
          soul: '乐于助人',
        ),
      );
      await pumpMemoryPage(tester, api);

      // 默认项目上下文 tab，切换到我的笔记 tab
      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();

      expect(find.text('现有笔记内容'), findsOneWidget);
      expect(find.byKey(const ValueKey('memory-edit-memory')), findsOneWidget);

      // 点击编辑按钮
      await tester.tap(find.byKey(const ValueKey('memory-edit-memory')));
      await tester.pump();

      // 进入编辑态：显示输入框、保存、取消按钮，原有只读 Text 不再展示
      expect(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('memory-edit-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('memory-edit-cancel')), findsOneWidget);

      final textField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('memory-edit-input-memory')),
      );
      expect(textField.controller?.text, '现有笔记内容');
    });

    testWidgets('保存成功：提交 writeMemory → refresh → 退出编辑态并渲染新内容', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '原笔记', user: '原用户', soul: '原灵魂'),
      );
      await pumpMemoryPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('memory-edit-memory')));
      await tester.pump();

      // 输入新内容
      await tester.enterText(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        '更新后的笔记',
      );

      // 保存成功后准备新 response
      api.response = const MemoryResponse(
        memory: '更新后的笔记',
        user: '原用户',
        soul: '原灵魂',
      );

      await tester.tap(find.byKey(const ValueKey('memory-edit-save')));
      await tester.pump();
      await tester.pump();

      // 验证 API 调用
      expect(api.writeCalls, hasLength(1));
      expect(api.writeCalls.first.section, 'memory');
      expect(api.writeCalls.first.content, '更新后的笔记');

      // 退出编辑态，展示新内容
      expect(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        findsNothing,
      );
      expect(find.text('更新后的笔记'), findsOneWidget);
    });

    testWidgets('保存失败：保留编辑态 + 不丢用户输入 + 输入框下方显示错误', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '原笔记', user: '原用户', soul: '原灵魂'),
      );
      api.writeError = HttpException(403, null, message: '写入权限不足');
      await pumpMemoryPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('memory-edit-memory')));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        '尝试修改的内容',
      );

      await tester.tap(find.byKey(const ValueKey('memory-edit-save')));
      await tester.pump();
      await tester.pump();

      // 保持编辑态，输入框内容不丢
      expect(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        findsOneWidget,
      );
      final textField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('memory-edit-input-memory')),
      );
      expect(textField.controller?.text, '尝试修改的内容');

      // 显示错误信息
      expect(find.text('写入权限不足'), findsOneWidget);

      // 修复错误后重试
      api.writeError = null;
      api.response = const MemoryResponse(
        memory: '尝试修改的内容',
        user: '原用户',
        soul: '原灵魂',
      );
      await tester.tap(find.byKey(const ValueKey('memory-edit-save')));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        findsNothing,
      );
      expect(find.text('尝试修改的内容'), findsOneWidget);
    });

    testWidgets('取消编辑：丢弃修改并回到只读态', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(
          memory: '保持原样',
          user: '原用户',
          soul: '原灵魂',
        ),
      );
      await pumpMemoryPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('memory-edit-memory')));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        '乱写的内容',
      );

      await tester.tap(find.byKey(const ValueKey('memory-edit-cancel')));
      await tester.pump();

      // 退出编辑态且未调用 writeMemory
      expect(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        findsNothing,
      );
      expect(api.writeCalls, isEmpty);
      expect(find.text('保持原样'), findsOneWidget);
    });

    testWidgets('空态分区也可编辑：从占位状态直接进入空白编辑并保存', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(
          memory: null,
          user: '用户画像',
          soul: '智能体灵魂',
        ),
      );
      await pumpMemoryPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();

      // 空态显示占位文案
      expect(find.text('暂无笔记'), findsOneWidget);
      expect(find.byKey(const ValueKey('memory-edit-memory')), findsOneWidget);

      // 点编辑进入空白输入
      await tester.tap(find.byKey(const ValueKey('memory-edit-memory')));
      await tester.pump();

      final textField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('memory-edit-input-memory')),
      );
      expect(textField.controller?.text, '');

      await tester.enterText(
        find.byKey(const ValueKey('memory-edit-input-memory')),
        '第一条笔记',
      );

      api.response = const MemoryResponse(
        memory: '第一条笔记',
        user: '用户画像',
        soul: '智能体灵魂',
      );
      await tester.tap(find.byKey(const ValueKey('memory-edit-save')));
      await tester.pump();
      await tester.pump();

      expect(find.text('第一条笔记'), findsOneWidget);
      expect(find.text('暂无笔记'), findsNothing);
    });

    testWidgets('用户画像与智能体灵魂分区同样支持编辑与保存', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(
          memory: '笔记',
          user: '开发者',
          soul: '# 原始灵魂',
        ),
      );
      await pumpMemoryPage(tester, api);

      // 用户画像编辑
      await tester.tap(find.byKey(const ValueKey('memory-tab-user')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('memory-edit-user')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('memory-edit-input-user')),
        '资深架构师',
      );
      api.response = const MemoryResponse(
        memory: '笔记',
        user: '资深架构师',
        soul: '# 原始灵魂',
      );
      await tester.tap(find.byKey(const ValueKey('memory-edit-save')));
      await tester.pump();
      await tester.pump();
      expect(api.writeCalls.last.section, 'user');
      expect(api.writeCalls.last.content, '资深架构师');
      expect(find.text('资深架构师'), findsOneWidget);

      // 智能体灵魂编辑
      await tester.tap(find.byKey(const ValueKey('memory-tab-soul')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('memory-edit-soul')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('memory-edit-input-soul')),
        '# 新灵魂\n- 细心严谨',
      );
      api.response = const MemoryResponse(
        memory: '笔记',
        user: '资深架构师',
        soul: '# 新灵魂\n- 细心严谨',
      );
      await tester.tap(find.byKey(const ValueKey('memory-edit-save')));
      await tester.pump();
      await tester.pump();
      expect(api.writeCalls.last.section, 'soul');
      expect(api.writeCalls.last.content, '# 新灵魂\n- 细心严谨');
      expect(find.text('新灵魂'), findsOneWidget);
      expect(find.text('细心严谨'), findsOneWidget);
    });

    testWidgets('双主题断言：浅色卡片描边/次级字/编辑态 vs 暗色默认与原语义色', (tester) async {
      final nowSec =
          DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch /
          1000;
      final fullResponse = MemoryResponse(
        memory: '笔记内容',
        user: '画像内容',
        soul: '灵魂内容',
        projectContext: '项目上下文内容',
        projectContextName: 'demo-proj',
        projectContextWorkspace: '/ws/demo',
        projectContextShadowed: true,
        memoryMtime: nowSec,
      );

      // 1. 浅色模式
      await pumpMemoryPage(
        tester,
        FakeMemoryApi(response: fullResponse),
        brightness: Brightness.light,
      );

      // CupertinoListSection 浅色：白卡 + 0.5 hairline 描边 + 分隔线
      final sectionLight = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(sectionLight.decoration, isNotNull);
      final sectionDecLight = sectionLight.decoration as BoxDecoration;
      expect(sectionDecLight.color, LightSurfaces.card);
      expect(sectionDecLight.borderRadius, BorderRadius.circular(10));
      expect(sectionDecLight.border?.top.color, LightSurfaces.cardBorder);
      expect(sectionDecLight.border?.top.width, 0.5);
      expect(sectionLight.separatorColor, LightSurfaces.divider);

      // 项目上下文只读锁与 footer 详情为浅色次级文字
      final lockIconLight = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.lock_fill),
      );
      expect(lockIconLight.color, LightSurfaces.textSecondary);
      final footerTextLight = tester.widget<Text>(
        find.text('demo-proj — /ws/demo'),
      );
      expect(footerTextLight.style?.color, LightSurfaces.textSecondary);

      // 切换到「我的笔记」，检查字数统计次级文字
      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();
      final charCountLight = tester.widget<Text>(find.text('4 字'));
      expect(charCountLight.style?.color, LightSurfaces.textSecondary);

      // 点击进入编辑态
      await tester.tap(find.byKey(const ValueKey('memory-edit-memory')));
      await tester.pump();

      // 输入框浅色：白卡 + 0.5 hairline 描边 + placeholder 颜色
      final editFieldLight = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('memory-edit-input-memory')),
      );
      final fieldDecLight = editFieldLight.decoration as BoxDecoration;
      expect(fieldDecLight.color, LightSurfaces.card);
      expect(fieldDecLight.borderRadius, BorderRadius.circular(5));
      expect(fieldDecLight.border?.top.color, LightSurfaces.cardBorder);
      expect(fieldDecLight.border?.top.width, 0.5);
      expect(editFieldLight.placeholderStyle?.color, LightSurfaces.placeholder);

      // 取消与保存按钮浅色 userDetail
      final cancelTextLight = tester.widget<Text>(find.text('取消'));
      expect(cancelTextLight.style?.color, LightSurfaces.userDetail);
      final saveButtonLight = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('memory-edit-save')),
      );
      expect(saveButtonLight.color, LightSurfaces.userDetail);

      // 2. 暗色模式
      await pumpMemoryPage(
        tester,
        FakeMemoryApi(response: fullResponse),
        brightness: Brightness.dark,
      );
      final darkContext = tester.element(find.byType(CupertinoListSection));

      // CupertinoListSection 暗色回退 null
      final sectionDark = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(sectionDark.decoration, isNull);
      expect(sectionDark.separatorColor, isNull);

      // 项目上下文只读锁暗色 secondaryLabel，footer 暗色 secondaryText
      final lockIconDark = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.lock_fill),
      );
      expect(
        lockIconDark.color,
        CupertinoColors.secondaryLabel.resolveFrom(darkContext),
      );
      final footerTextDark = tester.widget<Text>(
        find.text('demo-proj — /ws/demo'),
      );
      expect(
        footerTextDark.style?.color,
        secondaryText.resolveFrom(darkContext),
      );

      // 切换到「我的笔记」，检查字数统计暗色 secondaryText
      await tester.tap(find.byKey(const ValueKey('memory-tab-memory')));
      await tester.pump();
      final charCountDark = tester.widget<Text>(find.text('4 字'));
      expect(
        charCountDark.style?.color,
        secondaryText.resolveFrom(darkContext),
      );

      // 进入编辑态
      await tester.tap(find.byKey(const ValueKey('memory-edit-memory')));
      await tester.pump();

      // 输入框暗色回退系统默认
      final editFieldDark = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('memory-edit-input-memory')),
      );
      expect(editFieldDark.decoration, const CupertinoTextField().decoration);
      expect(
        editFieldDark.placeholderStyle,
        const CupertinoTextField().placeholderStyle,
      );

      // 取消与保存按钮暗色保持系统默认（null）
      final cancelTextDark = tester.widget<Text>(find.text('取消'));
      expect(cancelTextDark.style?.color, isNull);
      final saveButtonDark = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('memory-edit-save')),
      );
      expect(saveButtonDark.color, isNull);

      // 3. 空态双主题断言
      await pumpMemoryPage(
        tester,
        FakeMemoryApi(),
        brightness: Brightness.light,
      );
      final emptyTextLight = tester.widget<Text>(find.text('还没有任何记忆内容'));
      expect(emptyTextLight.style?.color, LightSurfaces.textSecondary);
      final emptyIconLight = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.doc_text),
      );
      expect(emptyIconLight.color, LightSurfaces.textSecondary);

      await pumpMemoryPage(
        tester,
        FakeMemoryApi(),
        brightness: Brightness.dark,
      );
      final emptyContextDark = tester.element(find.text('还没有任何记忆内容'));
      final emptyTextDark = tester.widget<Text>(find.text('还没有任何记忆内容'));
      expect(
        emptyTextDark.style?.color,
        secondaryText.resolveFrom(emptyContextDark),
      );
      final emptyIconDark = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.doc_text),
      );
      expect(emptyIconDark.color, const Color(0xFF8E8E93));
    });
  });
}
