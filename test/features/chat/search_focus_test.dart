import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/message_highlight.dart';

import '../../helpers/fake_chat_api.dart';

/// 搜索结果定位（深链 /chat/:id?q=&match=）与分支关系展示。
void main() {
  group('搜索定位（深链）', () {
    testWidgets('match=content 命中 → 目标消息高亮出现且不抛错', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一句话不匹配', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '这里提到了关键词喵', 'message_id': 'm2'},
            {'role': 'user', 'content': '最后一句话', 'message_id': 'm3'},
          ],
        },
      };
      final router = GoRouter(
        initialLocation: '/chat/s1?q=关键词&match=content',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) => ChatPage(
              sessionId: state.pathParameters['id']!,
              searchQuery: state.uri.queryParameters['q'],
              matchType: state.uri.queryParameters['match'],
            ),
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
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      // 目标消息高亮包裹（FadeTransition 动画中）
      expect(find.byType(SearchMessageHighlight), findsWidgets);
      // 页面正常渲染
      expect(find.text('第一句话不匹配'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('match=content 无命中 → 静默，无异常无高亮', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '普通内容', 'message_id': 'm1'},
          ],
        },
      };
      final router = GoRouter(
        initialLocation: '/chat/s1?q=不存在的词&match=content',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) => ChatPage(
              sessionId: state.pathParameters['id']!,
              searchQuery: state.uri.queryParameters['q'],
              matchType: state.uri.queryParameters['match'],
            ),
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
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('普通内容'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('match=title → 打开会话但不触发内容定位', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '标题命中会话',
          'messages': [
            {'role': 'user', 'content': '内容不相关', 'message_id': 'm1'},
          ],
        },
      };
      final router = GoRouter(
        initialLocation: '/chat/s1?q=标题命中&match=title',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) => ChatPage(
              sessionId: state.pathParameters['id']!,
              searchQuery: state.uri.queryParameters['q'],
              matchType: state.uri.queryParameters['match'],
            ),
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
      await tester.pump(const Duration(milliseconds: 100));

      // 无高亮包裹（title 命中不定位）
      final highlighted = tester
          .widgetList<SearchMessageHighlight>(
            find.byType(SearchMessageHighlight),
          )
          .where((w) => w.highlight)
          .length;
      expect(highlighted, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('分支关系展示', () {
    testWidgets('parent_session_id 非空 → 分支 badge 显示；点击弹对话框；跳转父会话', (
      tester,
    ) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '分支会话标题',
          'parent_session_id': 'parent-1',
          'messages': [
            {'role': 'user', 'content': '内容', 'message_id': 'm1'},
          ],
        },
      };
      final router = GoRouter(
        initialLocation: '/chat/s1',
        routes: [
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
      await tester.pump(const Duration(milliseconds: 100));

      // badge 出现，且图标为 size 12、浅色次级文字令牌
      final badgeFinder = find.byKey(const ValueKey('chat-branch-badge'));
      expect(badgeFinder, findsOneWidget);
      final badgeIconFinder = find.descendant(
        of: badgeFinder,
        matching: find.byIcon(CupertinoIcons.arrow_2_squarepath),
      );
      expect(badgeIconFinder, findsOneWidget);
      final badgeIcon = tester.widget<Icon>(badgeIconFinder);
      expect(badgeIcon.size, 12);
      expect(badgeIcon.color, LightSurfaces.textSecondary);

      // 点击 → 对话框
      await tester.tap(badgeFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('chat-branch-dialog')), findsOneWidget);

      // 跳转父会话 → 路由变化
      await tester.tap(find.byKey(const ValueKey('chat-goto-parent')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(router.routeInformationProvider.value.uri.path, '/chat/parent-1');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('无 parent_session_id → 不显示分支 badge', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '普通会话',
          'messages': [
            {'role': 'user', 'content': '内容', 'message_id': 'm1'},
          ],
        },
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('chat-branch-badge')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

typedef _FakeChatApi = FakeChatApi;
