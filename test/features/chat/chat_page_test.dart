import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';
import '../../helpers/fake_chat_api.dart';

void main() {
  testWidgets('渲染已加载的会话消息列表', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'title': '测试会话',
        'messages': [
          {'role': 'user', 'content': '你好', 'message_id': 'u1'},
          {
            'role': 'assistant',
            'content': '**你好！** 有什么可以帮你？',
            'message_id': 'a1',
          },
        ],
      },
    };
    await _pumpPage(tester, api);

    expect(find.text('你好'), findsOneWidget);
    // Markdown 渲染（粗体文本出现两次：源码 + 渲染后的富文本片段）
    expect(find.textContaining('有什么可以帮你', findRichText: true), findsWidgets);
    expect(find.text('测试会话'), findsOneWidget); // 导航栏标题

    await _unmount(tester);
  });

  testWidgets('输入并发送 → 乐观 user 气泡 + 调用 startChat → streaming 停止按钮出现', (
    tester,
  ) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await _pumpPage(tester, api);

    // idle：有发送按钮，无停止按钮
    expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-stop-button')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '帮我写首诗',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();

    // startChat 已调用；乐观 user 气泡出现
    expect(api.startChatCalls, 1);
    expect(api.lastSentText, '帮我写首诗');
    expect(find.text('帮我写首诗'), findsOneWidget);

    // streaming：停止按钮出现，发送按钮消失
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-stop-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send-button')), findsNothing);

    await _unmount(tester);
  });

  testWidgets('流式 token 渲染 + done 后停止按钮消失', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await _pumpPage(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      'hi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();

    // 状态行指示（生成中，空流式气泡不再显示独立思考中指示器）
    expect(find.textContaining('生成中'), findsOneWidget);
    expect(find.text('思考中…'), findsNothing);

    // token 流式渲染（16ms 合并 + 48ms reveal）
    api.emit(const TokenSseEvent('流式'));
    api.emit(const TokenSseEvent('内容'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.textContaining('流式内容', findRichText: true), findsOneWidget);
    expect(find.text('思考中…'), findsNothing);

    // done 收尾 → 停止按钮消失、发送按钮回归
    api.emit(
      const DoneSseEvent(
        DoneStreamEvent(
          session: {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
              {'role': 'assistant', 'content': '流式内容', 'message_id': 'a1'},
            ],
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('chat-stop-button')), findsNothing);
    expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);
    expect(find.textContaining('流式内容', findRichText: true), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('工具调用卡片渲染（tool 事件 → 卡片出现，完成后显示结果）', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await _pumpPage(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      'hi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();

    api.emit(
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'bash', args: {'cmd': 'ls -la'}),
      ),
    );
    await tester.pump();
    // group header 已本地化为"终端 ×1"（双层默认收起，outer 收起时 inner 不在树）
    expect(find.textContaining('终端'), findsOneWidget);
    expect(find.text('bash'), findsNothing);
    // 展开外层组 -> inner header 出现（header 含摘要：终端 — ls -la）
    await tester.tap(find.textContaining('终端'));
    await tester.pump();
    expect(find.textContaining('终端'), findsWidgets);
    expect(find.textContaining('ls -la'), findsOneWidget);
    // 展开 inner 卡片详情
    await tester.tap(find.textContaining('ls -la').first);
    await tester.pump();
    expect(find.textContaining('cmd: ls -la'), findsOneWidget);
    expect(find.text('运行中…'), findsOneWidget);

    api.emit(
      const ToolCompletedSseEvent(
        ToolStreamEvent(
          stableId: 't1',
          name: 'bash',
          preview: 'total 8',
          isError: false,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('运行中…'), findsNothing);
    expect(find.text('total 8'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('模型选择器：经上下文圆环弹层选择后发送带 explicit_model_pick', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'messages': const [],
        'context_length': 128000,
        'last_prompt_tokens': 1000,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          chatAvailableModelsProvider.overrideWithValue(const [
            'gpt-5',
            'claude',
          ]),
        ],
        child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 新入口：点击上下文圆环 → 弹出含模型列表的详情弹层
    await tester.tap(find.byKey(const ValueKey('chat-context-indicator-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 点击模型选择器触发按钮展开选项列表
    await tester.tap(find.byKey(const ValueKey('context-popover-model-trigger')));
    await tester.pumpAndSettle();
    expect(find.text('gpt-5'), findsOneWidget);

    await tester.tap(find.text('gpt-5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '用模型回答',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();

    expect(api.startChatCalls, 1);
    expect(api.lastModel, 'gpt-5');
    expect(api.lastExplicitModelPick, isTrue);

    await _unmount(tester);
  });

  testWidgets('发送失败 → 错误横幅展示，可关闭', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    api.startChatError = NetworkException(NetworkExceptionKind.cannotConnect);
    await _pumpPage(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      'hi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();
    expect(api.startChatCalls, 1);
    // 错误横幅展示（NetworkException 被捕获 → sendErrorMessage）
    expect(find.textContaining('无法连接'), findsOneWidget);

    await _unmount(tester);
  });

  group('第一阶段：聊天页会话菜单', () {
    testWidgets('导航栏菜单按钮打开操作菜单，展示全部操作项', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '测试会话', 'messages': const []},
      };
      await _pumpRouted(tester, api);

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('chat-action-rename')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-pin')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-archive')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-workspace')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-git')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-branch')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-export')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-settings')), findsNothing);

      // 关闭菜单
      await tester.tap(find.byKey(const ValueKey('chat-action-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await _unmount(tester);
    });

    testWidgets('重命名：输入新标题保存 → 标题更新且请求发出', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '旧标题', 'messages': const []},
      };
      await _pumpRouted(tester, api);
      expect(find.text('旧标题'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-rename')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 对话框内有输入框（预填当前标题）
      final input = find.byType(CupertinoTextField).last;
      await tester.enterText(input, '新标题');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-rename-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.renameCalls, 1);
      expect(api.lastRenameTitle, '新标题');
      expect(find.text('新标题'), findsWidgets); // 导航栏标题已更新

      await _unmount(tester);
    });

    testWidgets('置顶：选择置顶 → setPinned(true)', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '会话', 'messages': const []},
      };
      await _pumpRouted(tester, api);

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-pin')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.pinCalls, 1);
      expect(api.lastPinned, isTrue);
      await _unmount(tester);
    });

    testWidgets('删除：确认后删除并返回列表；取消则不删除', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '会话', 'messages': const []},
      };
      await _pumpRouted(tester, api);

      // 取消路径：不删除
      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('此操作不可撤销'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-delete-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.deleteCalls, 0);

      // 确认路径：删除并返回列表页
      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-delete-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.deleteCalls, 1);
      expect(find.text('列表页'), findsOneWidget); // 已回到会话列表路由

      await _unmount(tester);
    });

    testWidgets('分支：创建分支后跳转到分支会话', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '会话', 'messages': const []},
      };
      final router = await _pumpRouted(tester, api);
      expect(router.routeInformationProvider.value.uri.path, '/chat/s1');

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-branch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.branchCalls, 1);
      // 已跳转到新分支会话路由
      expect(router.routeInformationProvider.value.uri.path, '/chat/branch-s1');

      await _unmount(tester);
    });

    testWidgets('工作区文件：点击后 push 到工作区路由', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '会话', 'messages': const []},
      };
      final router = await _pumpRouted(tester, api);
      expect(router.routeInformationProvider.value.uri.path, '/chat/s1');

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('chat-action-workspace')), findsOneWidget);
      expect(find.text('工作区文件'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-action-workspace')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 注：go_router 在测试环境（非 pumpAndSettle 驱动）下，push 会真实压入
      // Navigator 显示目标页，但 RouteInformation 回写要等转场 settle，路径断言
      // 不可靠——以页面渲染为准（与 session_action_menu_test 口径一致）。
      expect(find.text('工作区页:s1'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('Git 工作区：点击后 push 到 Git 工作区路由', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '会话', 'messages': const []},
      };
      final router = await _pumpRouted(tester, api);
      expect(router.routeInformationProvider.value.uri.path, '/chat/s1');

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('chat-action-git')), findsOneWidget);
      expect(find.text('Git 工作区'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-action-git')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 同上：push 语义以页面渲染为准，路径不 settle 不断言。
      expect(find.text('Git页:s1'), findsOneWidget);

      await _unmount(tester);
    });
  });

  group('消息级操作（长按菜单）', () {
    testWidgets('长按用户消息 → 弹出操作菜单（复制/编辑/截断）', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复内容', 'message_id': 'm2'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '第一条用户消息');
      expect(find.byKey(const ValueKey('msg-action-copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-copy-md')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-truncate')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('msg-action-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await _unmount(tester);
    });

    testWidgets('截断：菜单 → 确认对话框 → 确认后调用 truncate(keepCount)', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复内容', 'message_id': 'm2'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '第一条用户消息');
      await tester.tap(find.byKey(const ValueKey('msg-action-truncate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 确认对话框
      expect(
        find.byKey(const ValueKey('msg-truncate-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('msg-truncate-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.truncateCalls, 1);
      // 第一条消息 index=0 → keepCount=1
      expect(api.truncateKeepCounts, [1]);

      await _unmount(tester);
    });

    testWidgets('截断：取消确认 → 不调用 truncate', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复内容', 'message_id': 'm2'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '第一条用户消息');
      await tester.tap(find.byKey(const ValueKey('msg-action-truncate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('msg-truncate-cancel')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.truncateCalls, 0);

      await _unmount(tester);
    });

    testWidgets('从此处分支：长按 → 分支 → keepCount=index+1 并跳转新会话', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复内容', 'message_id': 'm2'},
          ],
        },
      };
      final router = await _pumpRouted(tester, api);

      await _longPressBubble(tester, '回复内容');
      expect(find.byKey(const ValueKey('msg-action-branch')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('msg-action-branch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 第二条消息（index=1）→ keep_count=2 → 跳转 /chat/branch-s1
      expect(api.branchCalls, 1);
      expect(api.lastBranchKeepCount, 2);
      expect(router.state.uri.path, '/chat/branch-s1');

      await _unmount(tester);
    });

    testWidgets('复制：长按 → 复制 → 提示已复制', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '第一条用户消息');
      await tester.tap(find.byKey(const ValueKey('msg-action-copy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Clipboard 平台通道异步完成
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 复制完成 → controller 轻提示就位（横幅渲染机制已有独立用例）
      final ctx = tester.element(find.byType(ChatPage));
      final container = ProviderScope.containerOf(ctx);
      final notice = container.read(chatControllerProvider('s1')).noticeMessage;
      expect(notice, contains('已复制'));

      await _unmount(tester);
    });

    testWidgets('assistant 消息菜单无「编辑」项', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'assistant', 'content': '只有助手消息', 'message_id': 'm1'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '只有助手消息');
      expect(find.byKey(const ValueKey('msg-action-edit')), findsNothing);
      expect(find.byKey(const ValueKey('msg-action-truncate')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('msg-action-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await _unmount(tester);
    });
  });

  group('澄清卡片 UI 测试', () {
    testWidgets('渲染澄清卡片：倒计时、问题、选项按钮、文本输入框与提交按钮', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);

      // 发送消息并收到 clarifyPending 事件
      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '开始任务',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      api.emit(const ClarificationPendingSseEvent({
        'pending': {
          'clarify_id': 'clarify-1',
          'question': '请选择目标环境：',
          'choices_offered': ['开发环境', '生产环境'],
          'timeout_seconds': 120,
        },
        'pending_count': 1,
      }));
      await tester.pump();

      expect(find.text('需要澄清'), findsOneWidget);
      expect(find.text('请选择目标环境：'), findsOneWidget);
      expect(find.text('开发环境'), findsOneWidget);
      expect(find.text('生产环境'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-prompt-clarify-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-prompt-clarify-submit')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-prompt-clarify-countdown')), findsOneWidget);

      // 点击选项按钮作答
      await tester.tap(find.byKey(const ValueKey('chat-prompt-choice-开发环境')));
      await tester.pump();
      await tester.pump();

      expect(api.lastClarificationSessionId, 's1');
      expect(api.lastClarificationResponse, '开发环境');
      expect(find.text('需要澄清'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('自由文本输入并提交作答', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '执行操作',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      api.emit(const ClarificationPendingSseEvent({
        'pending': {
          'clarify_id': 'clarify-2',
          'question': '请输入配置项：',
          'choices_offered': <String>[],
          'timeout_seconds': 60,
        },
        'pending_count': 1,
      }));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('chat-prompt-clarify-input')),
        'MY_CONFIG=123',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-prompt-clarify-submit')));
      await tester.pump();
      await tester.pump();

      expect(api.lastClarificationSessionId, 's1');
      expect(api.lastClarificationResponse, 'MY_CONFIG=123');
      expect(find.text('需要澄清'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('折叠与展开澄清卡片', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '执行',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      api.emit(const ClarificationPendingSseEvent({
        'pending': {
          'clarify_id': 'clarify-3',
          'question': '是否继续执行？',
          'choices_offered': ['是', '否'],
          'timeout_seconds': 120,
        },
        'pending_count': 1,
      }));
      await tester.pump();

      expect(find.text('是否继续执行？'), findsOneWidget);

      // 点击折叠按钮
      await tester.tap(find.byKey(const ValueKey('chat-clarify-collapse-toggle')));
      await tester.pump();

      // 折叠后问题与输入框隐藏
      expect(find.text('是否继续执行？'), findsNothing);
      expect(find.byKey(const ValueKey('chat-prompt-clarify-input')), findsNothing);

      // 再次点击展开
      await tester.tap(find.byKey(const ValueKey('chat-clarify-collapse-toggle')));
      await tester.pump();

      expect(find.text('是否继续执行？'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-prompt-clarify-input')), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('澄清卡片控件高度与字号规格：按钮与输入框高 36，字号紧凑阶梯', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '规格测试',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      api.emit(const ClarificationPendingSseEvent({
        'pending': {
          'clarify_id': 'clarify-spec',
          'question': '测试问题',
          'choices_offered': ['选项A'],
          'timeout_seconds': 120,
        },
        'pending_count': 1,
      }));
      await tester.pump();

      // 校验控件高度统一为 36
      final inputSize = tester.getSize(
        find.byKey(const ValueKey('chat-prompt-clarify-input')),
      );
      final submitSize = tester.getSize(
        find.byKey(const ValueKey('chat-prompt-clarify-submit')),
      );
      final choiceSize = tester.getSize(
        find.byKey(const ValueKey('chat-prompt-choice-选项A')),
      );
      expect(inputSize.height, 36.0);
      expect(submitSize.height, 36.0);
      expect(choiceSize.height, 36.0);

      // 校验字号：按钮文字 13，输入框文字 13，问题 14，标题 13，提示 12
      final choiceText = tester.widget<Text>(find.text('选项A'));
      expect(choiceText.style?.fontSize, 13.0);

      final submitText = tester.widget<Text>(find.text('发送'));
      expect(submitText.style?.fontSize, 13.0);

      final questionText = tester.widget<Text>(find.text('测试问题'));
      expect(questionText.style?.fontSize, 14.0);

      final titleText = tester.widget<Text>(find.text('需要澄清'));
      expect(titleText.style?.fontSize, 13.0);

      final hintText = tester.widget<Text>(find.text('请选择一个选项，或在下方输入你的回答。'));
      expect(hintText.style?.fontSize, 12.0);

      await _unmount(tester);
    });
  });

  group('审批卡片 UI 测试', () {
    testWidgets('渲染审批卡片：标题、问题、选项按钮高度与字号对齐 + 点击作答', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '申请权限',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      api.emit(const ApprovalPendingSseEvent({
        'pending': {
          'approval_id': 'app-1',
          'question': '是否允许执行危险命令？',
          'choices_offered': ['允许', '拒绝'],
        },
        'pending_count': 1,
      }));
      await tester.pump();

      expect(find.text('需要审批'), findsOneWidget);
      expect(find.text('是否允许执行危险命令？'), findsOneWidget);
      expect(find.text('允许'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);

      // 选项按钮高度 36
      final approveSize = tester.getSize(
        find.byKey(const ValueKey('chat-prompt-choice-允许')),
      );
      final denySize = tester.getSize(
        find.byKey(const ValueKey('chat-prompt-choice-拒绝')),
      );
      expect(approveSize.height, 36.0);
      expect(denySize.height, 36.0);

      // 按钮文字字号 13
      final approveText = tester.widget<Text>(find.text('允许'));
      expect(approveText.style?.fontSize, 13.0);

      // 点击作答
      await tester.tap(find.byKey(const ValueKey('chat-prompt-choice-允许')));
      await tester.pump();
      await tester.pump();

      expect(find.text('需要审批'), findsNothing);

      await _unmount(tester);
    });
  });
}

/// 组装 ChatPage（override chatApiProvider 注入 fake）。
Future<void> _pumpPage(WidgetTester tester, _FakeChatApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    ),
  );
  // 初始 loadMessages + 页面动画
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 组装带 GoRouter 的 ChatPage（会话菜单的导航跳转走真实路由）。
///
/// 菜单项已超过 10 个（压缩/撤销/重试/设置/YOLO 等），默认 600px 高视口
/// 会裁剪底部项导致 tap miss——统一放大视口高度。
Future<GoRouter> _pumpRouted(WidgetTester tester, _FakeChatApi api) async {
  tester.view.physicalSize = const Size(800, 2000);
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
        builder: (context, state) => CupertinoPageScaffold(
          child: Center(
            child: Text('工作区页:${state.pathParameters['sessionId']}'),
          ),
        ),
      ),
      GoRoute(
        path: '/git/:sessionId',
        builder: (context, state) => CupertinoPageScaffold(
          child: Center(
            child: Text('Git页:${state.pathParameters['sessionId']}'),
          ),
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
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}

/// 卸载 ProviderScope（dispose 容器 → 取消看门狗等周期定时器，避免 pending timer）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

typedef _FakeChatApi = FakeChatApi;

/// 消息级操作：长按气泡空白区（文本区被 selectable 抢占，模拟真实交互）。
Future<void> _longPressBubble(WidgetTester tester, String text) async {
  final bubble = find
      .ancestor(of: find.text(text), matching: find.byType(ChatMessageBubble))
      .first;
  final rect = tester.getRect(bubble);
  // 气泡左上角内侧 padding 区域（避开文本）
  await tester.longPressAt(rect.topLeft + const Offset(8, 8));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
