import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';
import 'package:hermes_ui/app/widgets/menu_metrics.dart';
import 'package:hermes_ui/app/widgets/popover_dropdown.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/context_window_snapshot.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/context_window_popover.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_settings_api.dart';

/// 工作区列表用假 ApiClient（`_fetchWorkspaces` 直读 apiClient，不走 chatApi）。
ApiClient _workspacesClient(List<Map<String, Object?>> workspaces) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = _JsonAdapter((options) {
    if (options.path.contains('/api/workspaces')) {
      return jsonEncode({'workspaces': workspaces, 'last': null});
    }
    return '{}';
  });
  return ApiClient(baseUrl: 'http://test.local:30002', dio: dio);
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);
  final String Function(RequestOptions) body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body(options),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

/// 上下文弹层宽窄分流验收（设计稿 `dialog-family-proposal.html` §3 推荐①）：
///
/// - 宽屏（>=900，`isWideLayout`）：宽 300、大数字（窗口上限）+「已用 X · 上限 Y」
///   副行、占用进度条、四项数值 13pt 右对齐、**去掉**底部「关闭」行；
/// - 窄屏（<900）：宽 260、`tokensLabel` 行、四项数值 12pt、保留「关闭」行
///   —— 逐像素维持改造前排版（本组用例把两条分流的关键差异钉死）；
/// - 无数据文案两态共用 l10n（`l10n.unavailable`），不再出现 formatter 里
///   硬编码的英文 'Unavailable'（缺陷修复）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fullSnapshot = ContextWindowSnapshot.fromJson({
    'context_length': 128000,
    'last_prompt_tokens': 1200,
    'input_tokens': 800,
    'output_tokens': 400,
    'threshold_tokens': 96000,
    'estimated_cost': 0.0123,
  });
  final emptySnapshot = ContextWindowSnapshot.fromJson(const {});

  Widget host({
    required Widget child,
    Locale locale = const Locale('zh'),
    Brightness? brightness,
    List<String> models = const ['gpt-4o'],
    List<Map<String, Object?>>? workspaces,
    List<String> efforts = const [],
    String? reasoningEffort,
  }) {
    final fakeChat = FakeChatApi();
    fakeChat.sessionResult = {
      'session': {'session_id': 's1', 'workspace': null},
    };
    final overrides = <Override>[
      chatApiProvider.overrideWithValue(fakeChat),
      chatAvailableModelsProvider.overrideWithValue(models),
    ];
    if (workspaces != null) {
      overrides.add(
        apiClientProvider.overrideWithValue(_workspacesClient(workspaces)),
      );
    }
    if (efforts.isNotEmpty) {
      final fakeSettings = FakeSettingsApi();
      fakeSettings.reasoningResponse = ReasoningStatusResponse(
        supportsReasoningEffort: true,
        supportedEfforts: efforts,
        reasoningEffort: reasoningEffort,
      );
      overrides.add(
        settingsApiFactoryProvider.overrideWithValue((_) => fakeSettings),
      );
    }
    return ProviderScope(
      overrides: overrides,
      child: CupertinoApp(
        locale: locale,
        theme: brightness == null
            ? null
            : CupertinoThemeData(brightness: brightness),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: CupertinoPageScaffold(child: Center(child: child)),
      ),
    );
  }

  Widget popover(ContextWindowSnapshot snapshot) => ContextWindowPopover(
    sessionId: 's1',
    snapshot: snapshot,
    currentModel: 'gpt-4o',
    onClose: () {},
  );

  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('宽屏（>=900）重排', () {
    testWidgets('宽 248（紧凑档）：大数字 + 已用/上限副行 + 进度条 + 数值 13pt + 去「关闭」行', (
      tester,
    ) async {
      useViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(host(child: popover(fullSnapshot)));
      await settle(tester);

      // 紧凑档契约（主人 2026-10-07 反馈「太大」后收一档）：宽 300 → 248。
      expect(kContextPopoverWideWidth, 248);
      expect(
        tester.getSize(find.byType(ContextWindowPopover)).width,
        kContextPopoverWideWidth,
      );
      // 大数字 = 窗口上限；副行 = 已用 · 上限
      expect(
        find.byKey(const ValueKey('context-popover-window-label')),
        findsOneWidget,
      );
      expect(find.text('128.0K'), findsOneWidget);
      expect(find.text('已用 1.2K · 上限 128.0K'), findsOneWidget);
      // 大数字回到字号梯子（紧凑档：kFontMetric 21 → kFontPageTitle 17）
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('context-popover-window-label')),
            )
            .style
            ?.fontSize,
        kFontPageTitle,
      );
      // 进度条
      expect(
        find.byKey(const ValueKey('context-popover-usage-bar')),
        findsOneWidget,
      );
      // 去「关闭」行（点外部即关）
      expect(find.byKey(const ValueKey('context-popover-close')), findsNothing);
      // 去模型 / 工作区两个分区（主人 2026-10-07 拍板）：宽屏输入行上就有这两个
      // chip，进弹层再选一次是重复入口 —— 触发器与当前值都不再出现在弹层里。
      expect(
        find.byKey(const ValueKey('context-popover-model-trigger')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('context-popover-workspace-trigger')),
        findsNothing,
      );
      expect(find.text('gpt-4o'), findsNothing);
      expect(find.text('Current model'), findsNothing);
      // 四项数值：13pt（kFontLabel）右对齐
      final thresholdValue = tester.widget<Text>(find.text('96.0K (75%)'));
      expect(thresholdValue.style?.fontSize, kFontLabel);
      expect(thresholdValue.style?.fontWeight, FontWeight.w500);
      expect(thresholdValue.textAlign, TextAlign.right);
      expect(tester.widget<Text>(find.text('800')).style?.fontSize, kFontLabel);
      // 窄屏头部样式不出现
      expect(find.text('1.2K / 128.0K'), findsNothing);
    });

    testWidgets('无数据（宽屏）：数值退次级色 + 文案走 l10n 中文', (tester) async {
      useViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(host(child: popover(emptySnapshot)));
      await settle(tester);

      expect(find.text('Unavailable'), findsNothing);
      // 大数字 + 四项数值 + 副行（无数据时副行不渲染，只剩大数字）
      expect(find.text('暂无数据'), findsNWidgets(5));
      // 大数字保持强调字重；四项数值退为不加粗（设计稿 .kv .v.muted）
      final windowText = tester.widget<Text>(
        find.byKey(const ValueKey('context-popover-window-label')),
      );
      expect(windowText.style?.fontWeight, FontWeight.w500);
      final mutedValues = tester
          .widgetList<Text>(find.text('暂无数据'))
          .where((t) => t.style?.fontWeight == FontWeight.w400)
          .toList();
      expect(mutedValues.length, 4);
      expect(mutedValues.first.style?.fontSize, kFontLabel);
    });

    testWidgets('英文语言下无数据文案为 Unavailable（本地化而非硬编码）', (tester) async {
      useViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(
        host(child: popover(emptySnapshot), locale: const Locale('en')),
      );
      await settle(tester);

      expect(find.text('暂无数据'), findsNothing);
      expect(find.text('Unavailable'), findsNWidgets(5));
    });
  });

  group('窄屏（<900）逐像素维持原排版', () {
    testWidgets('宽 260：tokensLabel 行 + 数值 12pt + 保留「关闭」行 + 无进度条', (
      tester,
    ) async {
      useViewport(tester, const Size(800, 600));
      await tester.pumpWidget(host(child: popover(fullSnapshot)));
      await settle(tester);

      expect(tester.getSize(find.byType(ContextWindowPopover)).width, 260);
      expect(find.text('1.2K / 128.0K'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('context-popover-window-label')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('context-popover-usage-bar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('context-popover-close')),
        findsOneWidget,
      );
      // 窄屏没有输入行那排 chip ⇒ 模型 / 工作区两个分区照旧在（逐像素不变的一部分）。
      expect(
        find.byKey(const ValueKey('context-popover-model-trigger')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('context-popover-workspace-trigger')),
        findsOneWidget,
      );
      final thresholdValue = tester.widget<Text>(find.text('96.0K (75%)'));
      expect(thresholdValue.style?.fontSize, kFontCaption);
      expect(thresholdValue.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('400 手机视口同样走窄屏排版（无宽屏分支渗漏）', (tester) async {
      useViewport(tester, const Size(400, 700));
      await tester.pumpWidget(host(child: popover(fullSnapshot)));
      await settle(tester);

      expect(tester.getSize(find.byType(ContextWindowPopover)).width, 260);
      expect(find.text('1.2K / 128.0K'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('context-popover-usage-bar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('context-popover-close')),
        findsOneWidget,
      );
    });

    testWidgets('无数据（窄屏）：中文「暂无数据」而非英文 Unavailable', (tester) async {
      useViewport(tester, const Size(800, 600));
      await tester.pumpWidget(host(child: popover(emptySnapshot)));
      await settle(tester);

      expect(find.text('Unavailable'), findsNothing);
      // tokensLabel 行 + 四项数值
      expect(find.text('暂无数据'), findsNWidgets(5));
    });
  });

  group('三个下拉：内容放得下就全放（不再硬编码 200 裁切）', () {
    // 6 个模型 + 「跟随服务器默认」= 7 行（旧实现 200 上限下第 5 行起被裁）。
    const sixModels = [
      'gpt-5.2',
      'grok-4.5',
      'grok-4.6',
      'claude-4.7',
      'gemini-3',
      'deepseek-v4',
    ];
    // 6 个工作区 + 「跟随会话默认」= 7 行（同理）。
    final sixWorkspaces = <Map<String, Object?>>[
      for (var i = 0; i < 6; i++)
        {'path': '/home/user/project-$i', 'name': 'Project $i'},
    ];
    const fiveEfforts = ['minimal', 'low', 'medium', 'high', 'ultra'];

    Future<void> openMenu(WidgetTester tester, String trigger) async {
      await tester.tap(find.byKey(ValueKey(trigger)));
      await tester.pumpAndSettle();
    }

    /// 每一行都必须**完整**落在卡片内（`row.bottom <= 卡片底`）——历史实现把列表
    /// 封顶 200，第 5 行起被切断；行高固定 44（浅/深两态一致）。
    void expectAllRowsFullyVisible(WidgetTester tester, List<Key> rowKeys) {
      final card = tester.getRect(find.byType(PopoverDropdownCard));
      for (final key in rowKeys) {
        final row = tester.getRect(find.byKey(key));
        expect(
          row.top,
          greaterThanOrEqualTo(card.top - 0.5),
          reason: '$key 上缘被裁',
        );
        expect(
          row.bottom,
          lessThanOrEqualTo(card.bottom + 0.5),
          reason: '$key 下缘被裁（行底 ${row.bottom} > 卡片底 ${card.bottom}）',
        );
        expect(row.height, 44, reason: '$key 行高应恒为 44');
      }
    }

    testWidgets('模型下拉：7 行（6 模型 + 跟随默认）全部完整可见', (tester) async {
      // 触发器只存在于窄屏（宽屏 2026-10-07 起整段不渲染模型 / 工作区分区），
      // 故本组用例一律在窄屏视口下跑；菜单行为本身与屏宽无关。
      useViewport(tester, const Size(800, 900));
      await tester.pumpWidget(
        host(child: popover(fullSnapshot), models: sixModels),
      );
      await tester.pumpAndSettle();

      await openMenu(tester, 'context-popover-model-trigger');

      final rowKeys = <Key>[
        for (final m in sixModels) ValueKey('context-popover-model-$m'),
        const ValueKey('context-popover-model-default'),
      ];
      for (final key in rowKeys) {
        expect(find.byKey(key), findsOneWidget);
      }
      expectAllRowsFullyVisible(tester, rowKeys);
      // 卡片按内容摊开（7 × 44 + 边框 2），而不是旧实现的 200 + 2
      expect(
        tester.getRect(find.byType(PopoverDropdownCard)).height,
        7 * 44 + 2,
      );
      // 末行（此前整项不可见）文案可读
      expect(find.text('deepseek-v4'), findsOneWidget);
    });

    testWidgets('工作区下拉：7 行（6 工作区 + 跟随默认）全部完整可见', (tester) async {
      useViewport(tester, const Size(800, 900));
      await tester.pumpWidget(
        host(child: popover(fullSnapshot), workspaces: sixWorkspaces),
      );
      await tester.pumpAndSettle();

      await openMenu(tester, 'context-popover-workspace-trigger');

      final rowKeys = <Key>[
        for (var i = 0; i < 6; i++)
          ValueKey('workspace-item-/home/user/project-$i'),
        const ValueKey('workspace-item-default'),
      ];
      for (final key in rowKeys) {
        expect(find.byKey(key), findsOneWidget);
      }
      expectAllRowsFullyVisible(tester, rowKeys);
      expect(
        tester.getRect(find.byType(PopoverDropdownCard)).height,
        7 * 44 + 2,
      );
    });

    testWidgets('推理强度下拉：5 档全部可见 + 宽 140 且右缘对齐触发器', (tester) async {
      useViewport(tester, const Size(800, 900));
      await tester.pumpWidget(
        host(
          child: popover(fullSnapshot),
          workspaces: sixWorkspaces,
          efforts: fiveEfforts,
          reasoningEffort: 'medium',
        ),
      );
      await tester.pumpAndSettle();

      await openMenu(tester, 'context-popover-reasoning-trigger');

      expectAllRowsFullyVisible(tester, [
        for (final e in fiveEfforts) ValueKey('context-popover-reasoning-$e'),
      ]);
      final card = tester.getRect(find.byType(PopoverDropdownCard));
      expect(card.width, 140);
      expect(card.height, 5 * 44 + 2);
      final trigger = tester.getRect(
        find.byKey(const ValueKey('context-popover-reasoning-trigger')),
      );
      expect((card.right - trigger.right).abs(), lessThanOrEqualTo(0.5));
    });

    testWidgets('回落向下：菜单顶边 = 触发器底边 + 8；高度按行边界 + 上限 420 收紧', (tester) async {
      // 800×900 + 弹层贴顶：上方 / 下方都放不下 21 行（926），取较大的一侧 = 下方；
      // 可用高度被上限 420 收住 → fitMenuHeight 取整行最大前缀（不切行、不盖触发器）。
      useViewport(tester, const Size(800, 900));

      await tester.pumpWidget(
        host(
          child: Align(
            alignment: Alignment.topCenter,
            child: popover(fullSnapshot),
          ),
          models: [for (var i = 0; i < 20; i++) 'model-v$i'],
        ),
      );
      await tester.pumpAndSettle();

      final trigger = tester.getRect(
        find.byKey(const ValueKey('context-popover-model-trigger')),
      );
      await openMenu(tester, 'context-popover-model-trigger');

      final card = tester.getRect(find.byType(PopoverDropdownCard));
      // 统一口径：向下 = 触发器**底边** + 8。旧副本是「触发器顶部 + 38」——触发器实测
      // 高 44，故旧口径 = 底边 − 6（会盖住触发器 6pt）；新口径顶边比旧实现低 14pt。
      expect((card.top - (trigger.bottom + 8)).abs(), lessThanOrEqualTo(0.5));
      expect(card.top, greaterThan(trigger.bottom));
      // 可见行区 = 卡片高 − 卡片边框（1px × 2）= 9 整行（上限 420 内取最大整行前缀，
      // 绝不切半行）。
      expect(card.height - kPopoverMenuCardChrome, 9 * 44);
      expect(card.height, lessThanOrEqualTo(420));
      // 更强判据：**没有任何一行跨过卡片内容区底边**。
      // （把「卡片高」当列表上限时，第 10 行会露出 2px —— 半行感正是要消灭的东西，
      // 而只比对总高度是看不出来的。）
      final contentBottom = card.bottom - 1;
      for (var i = 0; i < 20; i++) {
        final row = tester.getRect(
          find.byKey(ValueKey('context-popover-model-model-v$i')),
        );
        expect(
          row.bottom <= contentBottom + 0.5 || row.top >= contentBottom - 0.5,
          isTrue,
          reason:
              '第 $i 行跨了内容区底边（${row.top}..${row.bottom} vs $contentBottom）',
        );
      }
      expect(card.bottom, lessThanOrEqualTo(900));
      // 被裁部分仍可滚动访问
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('context-popover-model-default')),
        -50.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('context-popover-model-default')),
        findsOneWidget,
      );
    });

    testWidgets('浅/深两态：模型下拉的行矩形与卡片矩形逐像素一致', (tester) async {
      useViewport(tester, const Size(800, 900));

      Future<Map<String, Rect>> measure(Brightness brightness) async {
        await tester.pumpWidget(
          host(
            child: popover(fullSnapshot),
            models: sixModels,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        await openMenu(tester, 'context-popover-model-trigger');

        final rects = <String, Rect>{
          'card': tester.getRect(find.byType(PopoverDropdownCard)),
          for (final m in sixModels)
            'model-$m': tester.getRect(
              find.byKey(ValueKey('context-popover-model-$m')),
            ),
          'default': tester.getRect(
            find.byKey(const ValueKey('context-popover-model-default')),
          ),
        };
        // 收起本态的菜单：旧 OverlayEntry 的 barrier 会跨越重 pump 残留并拦截点击
        await tester.tapAt(const Offset(20, 780));
        await tester.pumpAndSettle();
        return rects;
      }

      final light = await measure(Brightness.light);
      final dark = await measure(Brightness.dark);
      expect(dark, light);
    });
  });
}
