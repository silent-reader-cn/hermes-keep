// 聊天消息列表「列表项锚点 key」安全性 —— 同类隐患护栏（与 nav bar 槽位一脉同源）。
//
// ## 危害形状（本轮治理对象）
// 危害不取决于「有没有 GlobalKey」，而取决于 **key 归谁持有**：
// - 有害：GlobalKey 由**祖先/页面 State** 持有，并挂到「可能被框架同帧重复
//   build 的子树」上（前一轮的真凶是导航栏槽位里的 `_actionsKey`）；
// - 免疫：GlobalKey 由**该子树自己的 State** 创建（副本自带新 State ⇒ 新 key）。
//
// `ChatMessageListState` 旧实现持有 `Map<String, GlobalKey> _itemKeys` 并挂到
// 每个列表项包装层 —— 有害形状。触发面与 nav bar Hero 不同：**转场期页面子树
// 被重复 build**、以及「别名与规范 id 共用同一把键对象」时同帧双挂。
//
// ## 本文件覆盖
// A. 真 GoRouter 转场（/chat/:id → /chat/:otherId，Cupertino 转场动画）逐帧
//    pump：不得抛异常、消息行不得丢元素；
// B. renderId 整体位移（模拟流式归档 / 重载插入更早行，整批 renderId 失效）
//    的那一帧：不得抛异常、行数不缩水、不得出现重复行；
// C. 结构不变量（本轮机制的直接钉桩）：
//    C1 列表子树内**不得有项级 GlobalKey**（旧实现每个已挂载条目一把）；
//    C2 条目包装层必须可由 `ValueKey('msg-item:<renderId>')` 命中；
//    C3 高亮目标以**独立键**挂载、且不在 `mountedItemElements` 里 —— 这是旧
//       实现（目标挂另一把 `_highlightKey`）带来的既有效应，本轮**刻意保留**
//       （见 chat_message_list.dart 内 `_highlightKeyPrefix` 注释）。
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

/// 可控 ChatState 的控制器：`push` 直接替换状态（模拟服务端重载/归档）。
class _PuppetChatController extends ChatController {
  _PuppetChatController(this._initial);

  final ChatState _initial;

  @override
  ChatState build(String sessionId) => _initial;

  @override
  Future<void> loadYoloState() async {}

  @override
  Future<void> syncMissingMessages({int limit = 50}) async {}

  void push(ChatState next) => state = next;
}

List<ChatMessage> _rows(int from, int to) => [
  for (var i = from; i < to; i++)
    ChatMessage(
      role: i.isEven ? 'user' : 'assistant',
      content: '行 $i',
      messageId: 'm$i',
    ),
];

const String _itemKeyPrefix = 'msg-item:';

/// 列表子树里挂在 [KeyedSubtree] 上的 GlobalKey —— 这正是旧实现在**每个列表项
/// 包装层**上挂的「祖先 State 持有」的有害锚点形状。
///
/// 注意：Flutter 自身控件（SelectableText / EditableText / RawGestureDetector
/// 等）内部也持有 GlobalKey，但那是**该子树自己的 State** 创建的免疫形状，不属
/// 本判据（危害取决于 key 归谁持有，不取决于有没有 GlobalKey）。
List<GlobalKey> _itemWrapperGlobalKeys(WidgetTester tester) {
  final out = <GlobalKey>[];
  final root = tester.element(find.byType(ChatMessageList));
  void visit(Element element) {
    final key = element.widget.key;
    if (key is GlobalKey && element.widget is KeyedSubtree) out.add(key);
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return out;
}

/// 列表子树里 `msg-item:<规范 id>` 形式的 ValueKey 取值清单。
List<String> _itemValueKeysInList(WidgetTester tester) {
  final out = <String>[];
  final root = tester.element(find.byType(ChatMessageList));
  void visit(Element element) {
    final key = element.widget.key;
    if (key is ValueKey<String> && key.value.startsWith(_itemKeyPrefix)) {
      out.add(key.value.substring(_itemKeyPrefix.length));
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return out;
}

Future<_PuppetChatController> _pumpList(
  WidgetTester tester, {
  required String sessionId,
  required List<ChatMessage> messages,
  int messagesOffset = 0,
  String? highlightQuery,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = _PuppetChatController(
    ChatState(
      sessionId: sessionId,
      messages: messages,
      messagesOffset: messagesOffset,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatControllerProvider.overrideWith(() => controller)],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: ChatMessageList(
            sessionId: sessionId,
            highlightQuery: highlightQuery,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return controller;
}

void main() {
  group('A. 转场期页面子树重复 build：列表项锚点不丢元素、不重持键', () {
    testWidgets('/chat/:id → /chat/:other 真转场逐帧不抛异常、行不消失', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controllers = <String, _PuppetChatController>{};
      Widget page(String id) {
        final controller = controllers.putIfAbsent(
          id,
          () => _PuppetChatController(
            ChatState(sessionId: id, messages: _rows(0, 40)),
          ),
        );
        return ProviderScope(
          overrides: [chatControllerProvider.overrideWith(() => controller)],
          child: CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(middle: Text('会话')),
            child: ChatMessageList(sessionId: id),
          ),
        );
      }

      final router = GoRouter(
        initialLocation: '/chat/s-a',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (_, state) {
              return page(state.pathParameters['id']!);
            },
          ),
        ],
      );
      await tester.pumpWidget(CupertinoApp.router(routerConfig: router));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(_itemValueKeysInList(tester), isNotEmpty, reason: '首屏应有已挂载条目');

      router.go('/chat/s-b');
      // 逐帧推进转场中间帧（Hero/页面转场都在这些帧里发生）。
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.takeException(),
          isNull,
          reason: '转场第 ${i + 1} 帧不得出现同帧重持键/元素被抽走',
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('行 39'), findsOneWidget, reason: '转场结束后目标会话的行应完好');
      expect(
        _itemWrapperGlobalKeys(tester),
        isEmpty,
        reason: '列表项包装层不得挂祖先 State 持有的 GlobalKey（有害形状）',
      );
      expect(
        _itemValueKeysInList(tester),
        isNotEmpty,
        reason: '转场后条目锚点仍应由 ValueKey 承担',
      );
    });
  });

  group('B. renderId 整体位移（流式归档 / 重载插入更早行）', () {
    for (final headInsert in [true, false]) {
      testWidgets(
        headInsert
            ? '头部插入 5 行（offset 不变）不抛异常且行数不缩水'
            : 'offset 位移 +5 不抛异常且行数不缩水',
        (tester) async {
          final controller = await _pumpList(
            tester,
            sessionId: 's-shift-${headInsert ? "head" : "off"}',
            messages: _rows(0, 60),
          );
          expect(tester.takeException(), isNull);
          final before = find.textContaining('行 ').evaluate().length;
          expect(before, greaterThan(0));

          controller.push(
            ChatState(
              sessionId: 's-shift-${headInsert ? "head" : "off"}',
              messages: headInsert
                  ? [..._rows(-5, 0), ..._rows(0, 60)]
                  : _rows(0, 60),
              messagesOffset: headInsert ? 0 : 5,
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '整批 renderId 失效那一帧不得出现 GlobalKey 抢占/重持',
          );
          final after = find.textContaining('行 ').evaluate().length;
          expect(
            after,
            greaterThanOrEqualTo(before - 1),
            reason: '位移后可见行数不应缩水（元素被抽走的表征）',
          );
          // 行文本不得重复（同一条目被挂两份的表征）
          expect(find.text('行 40').evaluate().length, lessThanOrEqualTo(1));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('C. 结构不变量（不带 GlobalKey 的等价机制）', () {
    testWidgets('C1/C2 列表子树内无项级 GlobalKey，条目可被 ValueKey 命中', (tester) async {
      await _pumpList(tester, sessionId: 's-struct', messages: _rows(0, 40));
      expect(tester.takeException(), isNull);

      expect(
        _itemWrapperGlobalKeys(tester),
        isEmpty,
        reason:
            '项级锚点必须由 ValueKey 承担：GlobalKey 由祖先 State 持有 + 挂到'
            '可能被同帧重复 build 的子树 = 有害形状',
      );

      final valueKeys = _itemValueKeysInList(tester);
      expect(valueKeys, isNotEmpty, reason: '条目包装层应挂 msg-item:<规范 id>');
      for (final id in valueKeys) {
        expect(
          id,
          startsWith('transcript:'),
          reason: '规范 id 应为 renderId（transcript 条目）',
        );
      }
      final state = tester.state<ChatMessageListState>(
        find.byType(ChatMessageList),
      );
      final resolved = state.mountedItemElements;
      expect(
        resolved.keys.toSet(),
        valueKeys.toSet(),
        reason: '解算入口收集到的规范 id 应与实际挂载一致',
      );
      // 每个解算出的条目元素必须是「ValueKey 包装层」，绝不是 GlobalKey。
      for (final entry in resolved.entries) {
        expect(
          entry.value.widget,
          isA<KeyedSubtree>(),
          reason: '条目 ${entry.key} 的锚点元素应为 KeyedSubtree 包装层',
        );
        expect(
          entry.value.widget.key,
          isA<ValueKey<String>>(),
          reason: '条目 ${entry.key} 的锚点 key 必须是 ValueKey（非 GlobalKey）',
        );
      }
    });

    testWidgets('C3 高亮目标以独立键挂载且不在解算集合内（既有效应保留）', (tester) async {
      await _pumpList(
        tester,
        sessionId: 's-hl',
        messages: _rows(0, 40),
        highlightQuery: '行 20',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      final state = tester.state<ChatMessageListState>(
        find.byType(ChatMessageList),
      );
      final resolved = state.mountedItemElements;
      // 高亮目标（第一条命中关键词的行 = 行 20）对锚点/探针/大纲解算不可见
      // —— 与旧实现（目标改挂另一把 _highlightKey）逐位同形。
      expect(
        resolved.containsKey('transcript:20'),
        isFalse,
        reason: '高亮目标沿用旧语义：不在项级解算集合里',
      );
      // 但它确实以独立前缀的键挂载着（否则高亮定位就没有锚点了）。
      final hlKeys = <String>[];
      final root = tester.element(find.byType(ChatMessageList));
      void visit(Element element) {
        final key = element.widget.key;
        if (key is ValueKey<String> && key.value.startsWith('msg-item-hl:')) {
          hlKeys.add(key.value);
        }
        element.visitChildren(visit);
      }

      root.visitChildren(visit);
      expect(hlKeys, contains('msg-item-hl:transcript:20'));
    });
  });
}
