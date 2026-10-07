import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart'
    show kAdaptiveBreakpoint;
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';

import '../../helpers/contrast_utils.dart';
import '../../helpers/fake_chat_api.dart';

/// 注入任意 [ChatState] 的控制器（body 状态矩阵用；transcript 渲染不需要网络）。
class _StaticChatController extends ChatController {
  _StaticChatController(this.initialState);

  final ChatState initialState;

  @override
  ChatState build(String sessionId) => initialState;

  @override
  Future<void> loadYoloState() async {}

  @override
  Future<void> syncMissingMessages({int limit = 50}) async {}
}

// ---------------------------------------------------------------------------
// 顶栏 trailing 不变量（会话操作「⋯」+ 打开项目文件夹）。
//
// **真凶（本轮确诊）**：Cupertino 的 nav bar 在路由转场时走 Hero 飞行，
// `_NavigationBarComponentsTransition` 会**直接重建用户传入的 trailing / middle**
// （`topTrailing`/`bottomTrailing` 取的是 `trailingKey.currentWidget.child`，
// 同文件注释明写「... still present in the widget tree during the hero
// transitions, it would cause global key duplications」）。于是顶栏里**任何
// GlobalKey**都会在同一帧被「静态顶栏 + 飞行穿梭层」两处 build：
// - debug：撞 `BuildOwner._debugVerifyGlobalKeyReservation` →
//   「Multiple widgets used the same GlobalKey」；
// - release：`Element._retakeInactiveElement` 把元素从静态顶栏
//   `forgetChild + deactivateChild` 抽给穿梭层，飞行结束穿梭层销毁 ⇒
//   **「⋯」按钮连元素一起消失**，而左边没挂 GlobalKey 的文件夹按钮还在
//   —— 即主人报的「右上角三点有时候会消失、只剩左侧的打开项目文件夹按钮」。
//
// 两组守卫：
//  A. 转场期（真实 router + 真实转场动画）：中间帧与结束帧都不得丢元素、不得
//     出现同帧重持键；结束后「⋯」必须仍能弹出菜单（锚点不飘）。
//  B. 尺寸 × 标题矩阵 + 无 workspace：两点永远完整落在顶栏内且可点（宽度维度
//     的正交回归护栏 —— 宽度假设已被 Flutter 源码级证伪，留作护栏）。
// ---------------------------------------------------------------------------

const String _title = '会话标题';
const String _longTitle =
    '这是一个非常长的中文会话标题用来把顶栏中间槽撑到极限看看右上角的三点按钮会不会被挤出可视区域之外导致用户看不见';

Map<String, Object?> _session(String title, {String? workspace = 'D:/proj'}) {
  final session = <String, Object?>{
    'session_id': 's1',
    'title': title,
    'messages': const <Object?>[],
  };
  if (workspace != null) session['workspace'] = workspace;
  return {'session': session};
}

/// 一个带 CupertinoNavigationBar 的中转页。
///
/// Hero 飞行需要两端都有 transitionable 的 nav bar（两端 heroTag 都是
/// `_HeroTag(Navigator.of(context))`），这样穿梭层才会重建 chat 的 trailing。
Widget _stubPage() => const CupertinoPageScaffold(
  navigationBar: CupertinoNavigationBar(middle: Text('中转页')),
  child: Center(child: Text('中转页')),
);

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeChatApi api, {
  required Size size,
  String initialLocation = '/chat/s1',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/stub', builder: (context, state) => _stubPage()),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) =>
            ChatPage(sessionId: state.pathParameters['id']!),
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
  return router;
}

final Finder _ellipsis = find.byKey(const ValueKey('chat-session-actions'));
final Finder _folder = find.byKey(const ValueKey('chat-open-project-folder'));

/// 元素自己的 CupertinoNavigationBar 矩形。
///
/// Hero 穿梭层里的拷贝不是 nav bar 子树 ⇒ 返回 null（那些拷贝是转场期的正常
/// 产物，只要求「静态顶栏那一份完好」）。
Rect? _ownBarRect(Element element) {
  Rect? out;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is CupertinoNavigationBar) {
      final box = ancestor.renderObject as RenderBox?;
      if (box != null && box.attached) {
        out = box.localToGlobal(Offset.zero) & box.size;
      }
      return false;
    }
    return true;
  });
  return out;
}

/// 断言「⋯」与文件夹按钮都在，且「⋯」完整落在**它自己的**顶栏内。
///
/// [requireHit] 为 true 时还要求该「⋯」可命中（转场中间帧里页面还在屏外滑动，
/// 那时只钉「元素在、且在自己顶栏内」）。
/// 「打开项目文件夹」按钮在**当前宿主**的可见性（与 `chat_page` 的生产判据同源）：
/// `hasWorkspace && (isWide || (!kIsWeb && Platform.isWindows))`。
///
/// 非 Windows 上窄屏（< 900）本就不渲染该按钮 —— 断言必须跟随同一判据，否则在
/// Linux / macOS runner 上必红（本仓 #119 家族的老坑：测试缺平台门控）。
bool folderVisibleOnThisHost(WidgetTester tester) {
  if (kIsWeb) return false;
  if (Platform.isWindows) return true;
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  return width >= kAdaptiveBreakpoint;
}

void expectTrailingIntact(
  WidgetTester tester,
  String label, {
  bool requireHit = true,
  bool requireFolder = true,
}) {
  expect(_ellipsis, findsWidgets, reason: '$label：会话操作「⋯」必须存在');
  if (requireFolder && folderVisibleOnThisHost(tester)) {
    expect(_folder, findsWidgets, reason: '$label：打开项目文件夹按钮必须存在');
  }

  final hittable = _ellipsis.hitTestable().evaluate().toSet();
  var insideOk = false;
  var hitOk = false;
  final details = <String>[];
  for (final element in _ellipsis.evaluate()) {
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.attached) {
      details.add('detached');
      continue;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final bar = _ownBarRect(element);
    if (bar == null) {
      details.add('穿梭层拷贝 $rect');
      continue;
    }
    final inside =
        rect.left >= bar.left - 0.01 &&
        rect.right <= bar.right + 0.01 &&
        rect.top >= bar.top - 0.01 &&
        rect.bottom <= bar.bottom + 0.01;
    final hit = hittable.contains(element);
    details.add('$rect in $bar inside=$inside hit=$hit');
    if (inside) {
      insideOk = true;
      if (hit) hitOk = true;
    }
  }
  expect(insideOk, isTrue, reason: '$label：至少一个「⋯」应完整落在自己的顶栏内；实测 $details');
  if (requireHit) {
    expect(
      hitOk,
      isTrue,
      reason: '$label：屏幕上的「⋯」必须可命中（不能只是「画在栏内」）；实测 $details',
    );
  }
}

void main() {
  group('C. 状态排列：body 状态改不动顶栏 trailing', () {
    final states = <String, ChatState>{
      'idle': const ChatState(
        sessionId: 's1',
        displayTitle: _longTitle,
        workspace: 'D:/proj',
      ),
      'sending': const ChatState(
        sessionId: 's1',
        phase: ChatPhase.sending,
        displayTitle: _longTitle,
        workspace: 'D:/proj',
      ),
      'streaming': const ChatState(
        sessionId: 's1',
        phase: ChatPhase.streaming,
        displayTitle: _longTitle,
        workspace: 'D:/proj',
        stream: ChatStreamState(activeStreamId: 'st-1'),
      ),
      'clarify 等待': const ChatState(
        sessionId: 's1',
        phase: ChatPhase.clarifyPending,
        displayTitle: _longTitle,
        workspace: 'D:/proj',
        stream: ChatStreamState(activeStreamId: 'st-1'),
        pendingAction: ChatPendingActionState(
          clarificationPrompt: {'clarify_id': 'c1', 'question': '选哪个？'},
        ),
      ),
      'approval 等待': const ChatState(
        sessionId: 's1',
        phase: ChatPhase.approvalPending,
        displayTitle: _longTitle,
        workspace: 'D:/proj',
        stream: ChatStreamState(activeStreamId: 'st-1'),
        pendingAction: ChatPendingActionState(
          approvalPrompt: {'approval_id': 'a1', 'message': '允许执行？'},
        ),
      ),
      '错误 banner': const ChatState(
        sessionId: 's1',
        displayTitle: _longTitle,
        workspace: 'D:/proj',
        sendErrorMessage: '发送失败：网络不可达',
      ),
      '离线缓存 banner': const ChatState(
        sessionId: 's1',
        displayTitle: _longTitle,
        workspace: 'D:/proj',
        isShowingOfflineCache: true,
      ),
      '只读会话': const ChatState(
        sessionId: 's1',
        displayTitle: _longTitle,
        workspace: 'D:/proj',
        isReadOnly: true,
      ),
      'steer 提示堆叠': const ChatState(
        sessionId: 's1',
        displayTitle: _longTitle,
        workspace: 'D:/proj',
        steerHints: ['已转向：先跑测试', '已转向：再发版'],
      ),
      '分支子会话（badge）': const ChatState(
        sessionId: 's1',
        displayTitle: _longTitle,
        workspace: 'D:/proj',
        parentSessionId: 'p0',
      ),
    };

    for (final entry in states.entries) {
      testWidgets('${entry.key}：两点都在顶栏内且可点', (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatApiProvider.overrideWithValue(FakeChatApi()),
              chatControllerProvider.overrideWith(
                () => _StaticChatController(entry.value),
              ),
            ],
            child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectTrailingIntact(tester, entry.key);
      });
    }
  });

  group('D. 「⋯」图标解析色：两态 × 高对比度都要看得见', () {
    // 图标是图形（非文字）：WCAG 1.4.11 非文本对比度下限 3:1。
    const minRatio = 3.0;
    for (final brightness in const [Brightness.light, Brightness.dark]) {
      for (final highContrast in const [false, true]) {
        testWidgets('$brightness highContrast=$highContrast', (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                chatApiProvider.overrideWithValue(FakeChatApi()),
                chatControllerProvider.overrideWith(
                  () => _StaticChatController(
                    const ChatState(
                      sessionId: 's1',
                      displayTitle: _longTitle,
                      workspace: 'D:/proj',
                    ),
                  ),
                ),
              ],
              child: CupertinoApp(
                theme: buildCupertinoTheme(brightness),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(highContrast: highContrast),
                    child: const ChatPage(sessionId: 's1'),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          final contrastTargets = <String, Finder>{
            '「⋯」': _ellipsis,
            if (folderVisibleOnThisHost(tester)) '文件夹': _folder,
          };
          for (final entry in contrastTargets.entries) {
            final iconCtx = tester.element(
              find.descendant(of: entry.value, matching: find.byType(Icon)),
            );
            final resolved =
                IconTheme.of(iconCtx).color ?? CupertinoColors.label;
            // 顶栏底色（nav bar 的 effective background 取 CupertinoTheme
            // 的 barBackgroundColor；此处它就是非空值）。
            final barBg = CupertinoTheme.of(iconCtx).barBackgroundColor;
            final ratio = contrastRatio(resolved, barBg);
            expect(
              ratio >= minRatio,
              isTrue,
              reason:
                  '$brightness/$highContrast ${entry.key} 解析色 $resolved 与顶栏底色 '
                  '$barBg 对比度 ${ratio.toStringAsFixed(2)}:1 低于 $minRatio:1 ⇒ '
                  '「图标在但看不见」',
            );
          }
        });
      }
    }
  });

  group('A. 转场期（Hero 飞行）：trailing 不得丢元素', () {
    testWidgets('中转页 → 聊天页（GoRoute 默认 builder：带转场动画）', (tester) async {
      final api = FakeChatApi()..sessionResult = _session(_longTitle);
      final router = await _pump(
        tester,
        api,
        size: const Size(1280, 900),
        initialLocation: '/stub',
      );
      expect(_ellipsis, findsNothing, reason: '中转页还没有 chat 顶栏');

      router.go('/chat/s1');
      await tester.pump();
      // 转场中间帧：Hero 穿梭层正在重建 chat 的 trailing。
      await tester.pump(const Duration(milliseconds: 100));
      expectTrailingIntact(tester, '转场中(100ms)', requireHit: false);

      await tester.pump(const Duration(milliseconds: 200));
      expectTrailingIntact(tester, '转场中(300ms)', requireHit: false);

      await tester.pumpAndSettle();
      expect(_ellipsis, findsOneWidget, reason: '转场结束后只应有一个「⋯」');
      expectTrailingIntact(tester, '转场结束');
    });

    testWidgets('聊天页 → 中转页（pop 方向）：穿梭层里的 chat trailing 不撞键', (tester) async {
      final api = FakeChatApi()..sessionResult = _session(_longTitle);
      final router = await _pump(tester, api, size: const Size(1280, 900));
      expectTrailingIntact(tester, '转场前');

      router.go('/stub');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_ellipsis, findsWidgets, reason: '转场中 chat 的「⋯」不应整棵消失');
      await tester.pumpAndSettle();
      expect(_ellipsis, findsNothing, reason: '已离场，chat 顶栏应卸载');
    });

    testWidgets('会话 → 会话（切换 sessionId）：转场中与结束后都在', (tester) async {
      final api = FakeChatApi()..sessionResult = _session(_longTitle);
      final router = await _pump(tester, api, size: const Size(1280, 900));
      expectTrailingIntact(tester, '转场前');

      router.go('/chat/s2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectTrailingIntact(tester, '会话切换转场中(100ms)', requireHit: false);
      await tester.pumpAndSettle();
      expectTrailingIntact(tester, '会话切换转场结束');

      // 同 id 重进（GoRouter：同 location 不应异常、不应丢元素）
      router.go('/chat/s2');
      await tester.pump();
      await tester.pumpAndSettle();
      expectTrailingIntact(tester, '同 id 重进后');
    });

    testWidgets('窄屏转场同样不丢元素', (tester) async {
      final api = FakeChatApi()..sessionResult = _session(_longTitle);
      final router = await _pump(
        tester,
        api,
        size: const Size(375, 812),
        initialLocation: '/stub',
      );
      router.go('/chat/s1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectTrailingIntact(tester, '窄屏转场中', requireHit: false);
      await tester.pumpAndSettle();
      expectTrailingIntact(tester, '窄屏转场结束');
    });

    testWidgets('转场结束后「⋯」仍可点开菜单（锚点不飘）', (tester) async {
      final api = FakeChatApi()..sessionResult = _session(_longTitle);
      final router = await _pump(
        tester,
        api,
        size: const Size(1280, 900),
        initialLocation: '/stub',
      );
      router.go('/chat/s1');
      await tester.pumpAndSettle();

      await tester.tap(_ellipsis);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final rename = find.byKey(const ValueKey('chat-action-rename'));
      expect(rename, findsOneWidget, reason: '转场后「⋯」必须仍能弹出会话操作菜单');
      // 锚点不飘：菜单必须贴在被点的「⋯」附近（横向邻近）。
      final anchor = tester.getRect(_ellipsis);
      final menu = tester.getRect(rename);
      expect(
        (menu.center.dx - anchor.center.dx).abs() < 320,
        isTrue,
        reason: '菜单锚点不得飘离「⋯」：anchor=$anchor menu=$menu',
      );
    });
  });

  group('B. 尺寸矩阵：trailing 永不被挤出顶栏', () {
    for (final width in const [320.0, 375.0, 899.0, 900.0, 1280.0]) {
      for (final entry in {'短标题': _title, '长标题': _longTitle}.entries) {
        testWidgets('w=$width ${entry.key}：两点都完整在顶栏内且可点', (tester) async {
          final api = FakeChatApi()..sessionResult = _session(entry.value);
          await _pump(tester, api, size: Size(width, 900));
          expectTrailingIntact(tester, 'w=$width ${entry.key}');

          final bar = tester.getRect(find.byType(CupertinoNavigationBar).first);
          final folderVisible = folderVisibleOnThisHost(tester);
          // trailing 左缘参照：有文件夹按钮时是它，否则是「⋯」（非 Windows 窄屏）
          final trailingRect = folderVisible
              ? tester.getRect(_folder)
              : tester.getRect(_ellipsis);
          if (folderVisible) {
            expect(
              trailingRect.right <= bar.right + 0.01 &&
                  trailingRect.left >= bar.left - 0.01,
              isTrue,
              reason: '文件夹按钮 rect=$trailingRect 必须完整落在顶栏 $bar 内',
            );
          }
          // middle 不得与 trailing 抢位（右边界必须让开）。
          final mid = tester.getRect(
            find.byKey(const ValueKey('chat-title-outline-trigger')),
          );
          expect(
            mid.right <= trailingRect.left + 0.01,
            isTrue,
            reason:
                'middle 右边界 ${mid.right} 必须让开 trailing（左边界 ${trailingRect.left}）',
          );
        });
      }
    }

    testWidgets('无 workspace：只有「⋯」，完整在顶栏内且能开菜单', (tester) async {
      final api = FakeChatApi()
        ..sessionResult = _session(_longTitle, workspace: null);
      await _pump(tester, api, size: const Size(900, 900));
      expect(_folder, findsNothing);
      expectTrailingIntact(tester, '无 workspace', requireFolder: false);
      await tester.tap(_ellipsis);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('chat-action-rename')),
        findsOneWidget,
        reason: '「⋯」可点且弹出会话操作菜单',
      );
    });
  });
}
