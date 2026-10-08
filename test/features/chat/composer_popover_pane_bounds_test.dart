import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/theme/ui_scale_provider.dart';
import 'package:hermes_ui/app/widgets/popover_dropdown.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_session_list_api.dart';

// ---------------------------------------------------------------------------
// 元信息弹层（工作区 / 模型选择）**宿主坐标空间**守卫。
//
// 主人 2026-10-08 实机反馈：「宽屏模式下模型选择框的弹窗右侧都到屏幕外了」。
//
// 根因：路由挂在 go_router `ShellRoute` 的**嵌套 Navigator** 上，宽屏外壳把该嵌套
// Navigator（连同它的 Overlay）放进**右侧详情栏**——宽度 = 视口 - 侧栏（实机 341.9pt），
// 且在视口内整体右移；而 `PopoverMenuShell` 原先用 `MediaQuery.sizeOf(context).width`
// （整窗宽度）算横向 clamp 上限，于是多放行「一条侧栏」的宽度，靠近详情栏右缘的弹层
// 就溢出详情栏、被窗口右缘裁掉（实机截图：卡片右缘 2120.5 > 窗口 2048）。
//
// 本用例在**真实结构**（ShellRoute + AdaptiveShell + 聊天页 + 界面缩放 125%）下量
// 弹窗矩形的屏幕坐标，锁死「弹层必须落在宿主 Overlay 内、且留出安全边距」。
// ---------------------------------------------------------------------------

const _models = <String>[
  'muse-spark-1.3',
  'grok-4',
  'gpt-6-astra',
  'gemini-3.8-flash-high',
  'claude-opus-4-8',
  'deepseek-v4-flash',
  'deepseek-v4.1-flash',
  'step-1-8k',
  'grok-4.5',
  'grok-4.6',
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // 与实机一致：侧栏宽度 341.9（弹窗越界量正是这一条侧栏宽）。
      'adaptive_sidebar_width': 341.9,
    });
  });

  const delegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// 打开「模型」弹层，返回卡片 finder。
  Future<Finder> openModelMenu(
    WidgetTester tester, {
    required Size physical,
    required double dpr,
    required AppUiScale scale,
  }) async {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    final chatApi = FakeChatApi();
    chatApi.sessionResult = {
      'session': {
        'session_id': 's1',
        'workspace': '/path/to/ws',
        'model': 'deepseek-v4.1-flash',
        'messages': const <dynamic>[],
      },
    };

    final router = GoRouter(
      initialLocation: '/chat/s1',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const SessionListPage(),
            ),
            GoRoute(
              path: '/chat/:id',
              builder: (context, state) =>
                  ChatPage(sessionId: state.pathParameters['id'] ?? ''),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(chatApi),
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => FakeSessionListApi(),
          ),
          workspaceRootsProvider.overrideWith((ref) => [
            const WorkspaceRoot(path: '/path/to/ws', name: 'hermes-ui'),
          ]),
          availableModelIdsProvider.overrideWith((ref) => _models),
        ],
        child: CupertinoApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: delegates,
          builder: (context, child) => applyUiScale(
            context,
            child ?? const SizedBox.shrink(),
            scale,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('composer-model-chip')));
    await tester.pumpAndSettle();

    final card = find.byType(PopoverDropdownCard).last;
    expect(card, findsOneWidget, reason: '模型弹层应已展开');
    return card;
  }

  /// 弹层宿主 Overlay 的屏幕矩形（= 定位壳 `Positioned` 的坐标系）。
  ///
  /// 注意：`RenderBox.size` 是**局部**单位，界面缩放（`Transform.scale`）下必须先
  /// `localToGlobal` 两个角点再取矩形，否则与 `tester.getRect` 的口径不一致。
  Rect hostOverlayRect(WidgetTester tester, Finder card) {
    final overlayState = Overlay.of(tester.element(card));
    final box = overlayState.context.findRenderObject()! as RenderBox;
    return Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    );
  }

  testWidgets('宽屏详情栏内：模型弹层不越出宿主 Overlay（实机 2560×1351 @1.25 + 界面缩放 125%）', (
    tester,
  ) async {
    final card = await openModelMenu(
      tester,
      physical: const Size(2560, 1351),
      dpr: 1.25,
      scale: AppUiScale.x125,
    );

    final logical = tester.view.physicalSize / tester.view.devicePixelRatio;
    final cardRect = tester.getRect(card);
    final host = hostOverlayRect(tester, card);
    final popupViewport = MediaQuery.sizeOf(tester.element(card));

    // ── 结构前提（原缺陷的土壤）──────────────────────────────────────────
    // 宿主 Overlay = 右侧详情栏；它比弹层看到的 MediaQuery 视口**窄一条侧栏**，
    // 且整体右移（故右缘仍贴窗口右缘）。注意宿主尺寸要先换算回画布单位再比：
    // 界面缩放把「画布 pt」放大成 1.25 倍根空间逻辑 px。
    expect(
      popupViewport.width - host.width / 1.25,
      closeTo(341.9, 2.0),
      reason: '详情栏应比弹层看到的视口窄一条侧栏（实机 341.9）；'
          '差 0 = clamp 用错了坐标空间',
    );
    expect(host.right, closeTo(logical.width, 1.0), reason: '详情栏右缘贴窗口右缘');
    expect(host.left, greaterThan(0), reason: '详情栏整体右移（左侧是常驻侧栏）');

    // ── 核心断言：横向 clamp 必须按**宿主 Overlay**收敛 ──────────────────
    expect(
      host.right - cardRect.right,
      greaterThanOrEqualTo(7.5),
      reason: '弹层右缘应离宿主右缘 ≥ 8pt（原缺陷：溢出宿主 72.5pt、被窗口裁掉）',
    );
    expect(cardRect.right, lessThanOrEqualTo(logical.width - 7.5));
    expect(
      cardRect.left,
      greaterThanOrEqualTo(host.left),
      reason: '弹层左缘也不得越出宿主左缘（覆盖侧栏）',
    );
    // 宽度口径不变：宽屏仍是 300（× 界面缩放 1.25 = 375）。
    expect(cardRect.width, closeTo(300 * 1.25, 0.5));
  });

  testWidgets('窄屏单栏：宿主 Overlay == 视口，弹层几何与既有口径逐点一致', (tester) async {
    final card = await openModelMenu(
      tester,
      physical: const Size(800, 800),
      dpr: 1.0,
      scale: AppUiScale.x1,
    );

    final logical = tester.view.physicalSize / tester.view.devicePixelRatio;
    final cardRect = tester.getRect(card);
    final host = hostOverlayRect(tester, card);

    // 窄屏（< 900）外壳直接渲染 child ⇒ 嵌套 Navigator 铺满视口：宿主 == 视口。
    // 这意味着本次修复在窄屏**走的是同一条 clamp 路径、结果逐像素一致**。
    expect(host.width, closeTo(logical.width, 0.5));
    expect(host.height, closeTo(logical.height, 0.5));
    expect(host.left, 0.0);
    expect(host.top, 0.0);
    expect(cardRect.width, closeTo(228, 0.5), reason: '窄屏弹层宽度维持 228');
    // 锚点离右缘尚有余量 ⇒ clamp 不生效，卡片左缘 == 触发 chip 左缘（既有几何）。
    expect(cardRect.left, closeTo(tester.getRect(
      find.byKey(const ValueKey('composer-model-chip')),
    ).left, 0.5));
    expect(cardRect.right, lessThanOrEqualTo(logical.width - 7.5));
  });
}
