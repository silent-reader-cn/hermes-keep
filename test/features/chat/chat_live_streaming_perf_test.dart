import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _NoopCacheService extends CacheService {
  _NoopCacheService(super.db);
  @override
  Future<void> writeMessages({
    required String sessionId,
    required List<Map<String, Object?>> messages,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> readMessages(String sessionId) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase B: 流式增量渲染与整表去重建测试', () {
    testWidgets(
      '生成时即构建 MarkdownBody（过程文本走 markdown），done 后转 transcript 仍是 MarkdownBody',
      (tester) async {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);

        api.sessionResult = {
          'session': {
            'session_id': 's-perf-stream',
            'active_stream_id': 'stream-perf-1',
            'messages': [
              {
                'role': 'user',
                'content': 'Hello, tell me a formatted story.',
                'message_id': 'u1',
              },
            ],
            'message_count': 1,
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatApiProvider.overrideWithValue(api)],
            child: const CupertinoApp(
              home: ChatPage(sessionId: 's-perf-stream'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 历史 user 消息渲染完成
        expect(find.text('Hello, tell me a formatted story.'), findsOneWidget);

        // 推送带有 Markdown 格式的 token
        api.emit(const TokenSseEvent('**Bold Story** with `code snippet`\n'));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        // 契约（2026-09-26 改钉）：**生成时就**走 markdown —— 主人要的正是
        // 「过程文本要 markdown 渲染」。旧契约（b6a1bb7）钉的是「流式 tick 不建
        // MarkdownBody」，代价就是生成时看不见 markdown，故此处反转。
        expect(find.byType(MarkdownBody), findsOneWidget);
        // 且确实解析过：字面量标记不该出现在渲染结果里（纯文本路径会原样显示 **）。
        expect(
          find.textContaining('**Bold Story**', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining('Bold Story', findRichText: true),
          findsWidgets,
        );

        // 继续推送更多 token
        api.emit(const TokenSseEvent('Second line of the story.\n'));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(
          find.textContaining('Second line of the story.', findRichText: true),
          findsWidgets,
        );

        // 发送 done 事件，结束流
        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's-perf-stream',
                'messages': [
                  {
                    'role': 'user',
                    'content': 'Hello, tell me a formatted story.',
                    'message_id': 'u1',
                  },
                  {
                    'role': 'assistant',
                    'content': '**Bold Story** with `code snippet`\nSecond line of the story.\n',
                    'message_id': 'a1',
                  },
                ],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证：done 收尾后转入 transcript，仍是 MarkdownBody 呈现富文本
        expect(find.byType(MarkdownBody), findsOneWidget);
      },
    );

    testWidgets('超长流式文本退回轻量 Text（性能保底阀）', (tester) async {
      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      api.sessionResult = {
        'session': {
          'session_id': 's-perf-huge',
          'active_stream_id': 'stream-perf-2',
          'messages': [
            {'role': 'user', 'content': 'long one', 'message_id': 'u1'},
          ],
          'message_count': 1,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-perf-huge')),
        ),
      );
      await tester.pumpAndSettle();

      // 单条超阈值 token（不含 MEDIA 标记 ⇒ 走流式分支）
      api.emit(TokenSseEvent('铺' * (kLiveMarkdownMaxChars + 512)));
      await tester.pump(const Duration(milliseconds: 16));
      // 大步推进时钟让 reveal 排空（1s 排空窗口），避免逐帧重解析超大文本拖慢测试
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(
        find.byType(MarkdownBody),
        findsNothing,
        reason: '超过 kLiveMarkdownMaxChars 的流式文本应退回轻量 Text（保底不卡）',
      );
      expect(
        find.textContaining('铺', findRichText: true),
        findsWidgets,
        reason: '退回轻量 Text 后内容仍须可见',
      );
    });

    test('流式 token reveal 期间 transcriptMessagesProvider 保持列表实例引用不变', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final db = AppDatabase.memory();
        final container = ProviderContainer(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            appDatabaseProvider.overrideWithValue(db),
            cacheServiceProvider.overrideWithValue(_NoopCacheService(db)),
            connectionStoreProvider.overrideWithValue(
              ConnectionStore(storage: InMemorySecureStorage()),
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          unawaited(db.close());
        });

        final controller = container.read(
          chatControllerProvider('s-cache').notifier,
        );
        unawaited(controller.send('Hello'));
        async.flushMicrotasks();

        // 第一次读取 transcript
        final initialTranscript = container.read(
          transcriptMessagesProvider('s-cache'),
        );
        expect(initialTranscript.length, 1); // user 消息

        // 连续收到 10 个 token
        for (var i = 0; i < 10; i++) {
          api.emit(TokenSseEvent('token$i '));
          async.elapse(const Duration(milliseconds: 16));
          async.elapse(const Duration(milliseconds: 48));

          final currentTranscript = container.read(
            transcriptMessagesProvider('s-cache'),
          );
          expect(
            identical(initialTranscript, currentTranscript),
            isTrue,
            reason: 'token $i: transcript 列表实例必须保持恒等，避免整表重建',
          );
        }
      });
    });
  });
}
