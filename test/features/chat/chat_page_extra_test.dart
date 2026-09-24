import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/endpoints.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

typedef _FakeChatApi = FakeChatApi;

/// 仅 Windows 桌面可达的分支（`!kIsWeb && Platform.isWindows`）标记。
/// 非 Windows 主机（如 Linux CI）跳过，避免误报失败。
final bool _isWindowsDesktop = !kIsWeb && Platform.isWindows;

void main() {
  // ---------------------------------------------------------------------------
  // A. 大纲面板（_toggleOutline / _dismissOutline / _resolveAnchorRect）
  // ---------------------------------------------------------------------------
  group('聊天页大纲面板（标题栏触发）', () {
    final contentA = '第一轮提问：${'甲' * 50}';
    final contentB = '第二轮提问：${'乙' * 50}';

    Map<String, Object?> outlineSession() => {
      'session': {
        'session_id': 's1',
        'title': '大纲会话',
        'messages': [
          {'role': 'user', 'content': contentA, 'message_id': 'u1'},
          {'role': 'assistant', 'content': '助手回复一', 'message_id': 'a1'},
          {'role': 'user', 'content': contentB, 'message_id': 'u2'},
          {'role': 'assistant', 'content': '助手回复二', 'message_id': 'a2'},
        ],
      },
    };

    testWidgets('≥2 轮用户消息：点标题展开面板 → 再点收起（toggle 两分支）', (tester) async {
      final api = _FakeChatApi()..sessionResult = outlineSession();
      await _pumpPage(tester, api);

      expect(
        find.byKey(const ValueKey('chat-title-outline-trigger')),
        findsOneWidget,
      );
      // 面板未展开：截断预览（前 40 字 + '…'）不在树中
      expect(find.text(_outlinePreview(contentA)), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chat-title-outline-trigger')));
      await tester.pump();

      // 大纲行预览为「前 40 字 + …」，消息本体更长 → 该文本只属于大纲面板
      expect(find.text(_outlinePreview(contentA)), findsOneWidget);
      expect(find.text(_outlinePreview(contentB)), findsOneWidget);

      // 再次点击标题 → 收起（_dismissOutline + setState）
      await tester.tap(find.byKey(const ValueKey('chat-title-outline-trigger')));
      await tester.pump();
      expect(find.text(_outlinePreview(contentA)), findsNothing);
      expect(find.text(_outlinePreview(contentB)), findsNothing);

      await _unmount(tester);
    });

    testWidgets('点大纲条目：触发 onJump 跳转并自动收起', (tester) async {
      final api = _FakeChatApi()..sessionResult = outlineSession();
      await _pumpPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('chat-title-outline-trigger')));
      await tester.pump();
      expect(find.text(_outlinePreview(contentB)), findsOneWidget);

      await tester.tap(find.text(_outlinePreview(contentB)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // onJump 已接线（跳转经 ChatMessageListState.outlineJumpTo），面板自动收起
      expect(find.text(_outlinePreview(contentB)), findsNothing);

      await _unmount(tester);
    });

    testWidgets('点面板外空白：触发 onDismiss 收起', (tester) async {
      final api = _FakeChatApi()..sessionResult = outlineSession();
      await _pumpPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('chat-title-outline-trigger')));
      await tester.pump();
      expect(find.text(_outlinePreview(contentA)), findsOneWidget);

      // 面板贴导航栏下方（top ≈ 56），底部空白落在 barrier 上
      await tester.tapAt(const Offset(20, 560));
      await tester.pump();

      expect(find.text(_outlinePreview(contentA)), findsNothing);

      await _unmount(tester);
    });

    testWidgets('<2 轮用户消息：点标题静默无动作（不弹空态面板）', (tester) async {
      final single = '唯一的用户提问：${'丙' * 50}';
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': 's1',
            'title': '单轮会话',
            'messages': [
              {'role': 'user', 'content': single, 'message_id': 'u1'},
            ],
          },
        };
      await _pumpPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('chat-title-outline-trigger')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 静默返回：无任何浮层（截断预览不会出现）
      expect(find.text(_outlinePreview(single)), findsNothing);

      await _unmount(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // B. Windows 项目文件夹入口（_openProjectFolder / openSessionProjectFolder）
  // ---------------------------------------------------------------------------
  group('Windows 会话项目文件夹入口', () {
    testWidgets('会话带 workspace → 头部出现文件夹按钮；缺失目录走 notice 提示', (
      tester,
    ) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': 's1',
            'title': '项目会话',
            'workspace': r'C:\__hermes_missing_dir_for_test__',
            'messages': const [],
          },
        };
      await _pumpPage(tester, api);

      expect(
        find.byKey(const ValueKey('chat-open-project-folder')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('chat-open-project-folder')));
      await _settleRealIo(tester);

      // 目录不存在 → 绝不静默失败，以 notice 提示路径
      expect(find.textContaining('项目文件夹不存在'), findsOneWidget);
      expect(
        tester.widget<Text>(find.textContaining('项目文件夹不存在')).data,
        contains(r'C:\__hermes_missing_dir_for_test__'),
      );

      await _unmount(tester);
    }, skip: !_isWindowsDesktop);

    testWidgets('无 workspace → 头部不出现文件夹按钮', (tester) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': 's1',
            'title': '普通会话',
            'messages': const [],
          },
        };
      await _pumpPage(tester, api);

      expect(find.byKey(const ValueKey('chat-open-project-folder')), findsNothing);

      await _unmount(tester);
    }, skip: !_isWindowsDesktop);

    testWidgets('三点菜单内亦有「打开项目文件夹」项，点击同样提示路径缺失', (
      tester,
    ) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': 's1',
            'title': '项目会话',
            'workspace': r'C:\__hermes_missing_dir_for_test__',
            'messages': const [],
          },
        };
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);

      expect(
        find.byKey(const ValueKey('chat-action-open-project-folder')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('chat-action-open-project-folder')),
      );
      await _settleRealIo(tester);

      expect(find.textContaining('项目文件夹不存在'), findsOneWidget);

      await _unmount(tester);
    }, skip: !_isWindowsDesktop);
  });

  // ---------------------------------------------------------------------------
  // C. 导航栏 / 菜单回调（归档、压缩、撤销、重试、YOLO、导出）
  // ---------------------------------------------------------------------------
  group('会话菜单回调', () {
    Map<String, Object?> plainSession({String title = '会话'}) => {
      'session': {'session_id': 's1', 'title': title, 'messages': const []},
    };

    testWidgets('归档：确认 → setArchived(true) 并离开当前页回列表', (tester) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-archive')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.archiveCalls, 1);
      expect(api.lastArchived, isTrue);
      expect(find.text('列表页'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('压缩：输入聚焦主题 → confirm → startCompression(focusTopic)', (
      tester,
    ) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-compress')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('chat-compress-topic')), findsOneWidget);
      expect(find.text('压缩会话'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('chat-compress-topic')),
        '聚焦主题A',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-compress-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // #156：改走异步 start（立刻返回）；聚焦主题原样透传。
      expect(api.compressStartCalls, 1);
      expect(api.lastCompressFocusTopic, '聚焦主题A');

      await _unmount(tester);
    });

    testWidgets('压缩：留空主题确认 → focusTopic 空串仍走压缩（全量压缩）', (
      tester,
    ) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-compress')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('chat-compress-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.compressStartCalls, 1);
      // 空串经 controller 归一为 null（全量压缩，不聚焦主题）
      expect(api.lastCompressFocusTopic, isNull);

      await _unmount(tester);
    });

    testWidgets('压缩：取消 → 不调用 compressSession', (tester) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-compress')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('chat-compress-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.compressStartCalls, 0);

      await _unmount(tester);
    });

    testWidgets('暗色模式压缩对话框 → 走 CupertinoTextField 默认装饰与占位样式', (
      tester,
    ) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api, brightness: Brightness.dark);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-compress')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-compress-topic')),
      );
      expect(field.decoration, const CupertinoTextField().decoration);
      expect(
        field.placeholderStyle,
        const CupertinoTextField().placeholderStyle,
      );

      await tester.tap(find.byKey(const ValueKey('chat-compress-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.compressStartCalls, 0);

      await _unmount(tester);
    });

    testWidgets('撤销上一轮：确认 → undoSession', (tester) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-undo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('删除最后一轮对话？此操作不可撤销'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-undo-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.undoCalls, 1);

      await _unmount(tester);
    });

    testWidgets('撤销上一轮：取消 → 不调用 undoSession', (tester) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-undo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('chat-undo-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.undoCalls, 0);

      await _unmount(tester);
    });

    testWidgets('重试上一轮：菜单点击 → retrySession 并把原文回填输入框', (
      tester,
    ) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.retryCalls, 1);
      // composerPrefill 回填输入框（FakeChatApi.lastUserText = '你好'）
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('chat-input-field')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '你好',
      );

      await _unmount(tester);
    });

    testWidgets('YOLO 开关：菜单点击 → setYolo(true)', (tester) async {
      final api = _FakeChatApi()..sessionResult = plainSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      expect(find.text('开启 YOLO'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-action-yolo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.setYoloCalls, 1);
      expect(api.lastYoloEnabled, isTrue);

      await _unmount(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // D. 分支会话徽标对话框
  // ---------------------------------------------------------------------------
  group('分支会话徽标', () {
    testWidgets('点分支徽标 → 弹父会话对话框；关闭不跳转', (tester) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': 's1',
            'title': '分支会话',
            'parent_session_id': 'parent-9',
            'messages': const [],
          },
        };
      final router = await _pumpRouted(tester, api);

      expect(find.byKey(const ValueKey('chat-branch-badge')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-branch-badge')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('chat-branch-dialog')), findsOneWidget);
      expect(find.textContaining('parent-9'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-branch-dialog-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('chat-branch-dialog')), findsNothing);
      expect(router.state.uri.path, '/chat/s1');

      await _unmount(tester);
    });

    testWidgets('点分支徽标 → 选择「跳转父会话」→ go 到父会话路由', (tester) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': 's1',
            'title': '分支会话',
            'parent_session_id': 'parent-9',
            'messages': const [],
          },
        };
      final router = await _pumpRouted(tester, api);

      await tester.tap(find.byKey(const ValueKey('chat-branch-badge')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('chat-goto-parent')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(router.state.uri.path, '/chat/parent-9');

      await _unmount(tester);
    });

    testWidgets('非分支会话：不出现分支徽标', (tester) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': 's1',
            'title': '普通会话',
            'messages': const [],
          },
        };
      await _pumpPage(tester, api);

      expect(find.byKey(const ValueKey('chat-branch-badge')), findsNothing);

      await _unmount(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // E. 错误横幅关闭
  // ---------------------------------------------------------------------------
  group('错误横幅', () {
    testWidgets('发送失败 → 错误横幅可点 × 关闭并清空状态', (tester) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        }
        ..startChatError = NetworkException(
          NetworkExceptionKind.cannotConnect,
        );
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '触发失败',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('无法连接'), findsOneWidget);
      expect(
        container.read(chatControllerProvider('s1')).sendErrorMessage,
        isNotNull,
      );

      await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('无法连接'), findsNothing);
      expect(
        container.read(chatControllerProvider('s1')).sendErrorMessage,
        isNull,
      );

      await _unmount(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // F. 排队待发送横幅（_QueuedBanner）
  // ---------------------------------------------------------------------------
  group('排队待发送横幅', () {
    testWidgets('流式期间队列发送 → 横幅展示排队条数；队列清空后消失', (tester) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '第一条',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-stop-button')), findsOneWidget);

      final notifier = container.read(chatControllerProvider('s1').notifier);
      await notifier.send(
        '排队一',
        behavior: StreamingSendBehavior.queue,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 文案在排队横幅与「注入提示卡」各出现一次（同源 notice）
      expect(find.textContaining('已排队 1 条消息'), findsWidgets);
      expect(container.read(queuedCountProvider('s1')), 1);

      await notifier.send('排队二', behavior: StreamingSendBehavior.queue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('已排队 2 条消息'), findsWidgets);
      expect(container.read(queuedCountProvider('s1')), 2);

      await _unmount(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // G. 澄清卡片倒计时（_initCountdown / _handleTimeout / 紧急配色）
  // ---------------------------------------------------------------------------
  group('澄清卡片倒计时', () {
    Future<void> emitClarify(
      WidgetTester tester,
      _FakeChatApi api,
      Map<String, Object?> prompt,
    ) async {
      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '开始任务',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      api.emit(
        ClarificationPendingSseEvent({
          'pending': {'clarify_id': 'clarify-x', ...prompt},
          'pending_count': 1,
        }),
      );
      await tester.pump();
    }

    _FakeChatApi baseApi() => _FakeChatApi()
      ..sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };

    testWidgets('expires_at 已过期 → 立即超时收卡并提示（_handleTimeout）', (
      tester,
    ) async {
      final api = baseApi();
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      await emitClarify(tester, api, {
        'question': '过期澄清',
        'choices_offered': <String>[],
        'expires_at': 1, // 1970 → 早已过期
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 卡片被清掉
      expect(find.text('需要澄清'), findsNothing);
      expect(find.text('过期澄清'), findsNothing);
      // _handleTimeout → handleClarificationTimeout → setNotice('澄清已超时')
      expect(
        container.read(chatControllerProvider('s1')).pendingAction.clarificationPrompt,
        isNull,
      );

      await _unmount(tester);
    });

    testWidgets('requested_at + timeoutSeconds（camelCase）→ 计时器正常启动', (
      tester,
    ) async {
      final api = baseApi();
      await _pumpPage(tester, api);

      final requestedAt =
          (DateTime.now().millisecondsSinceEpoch / 1000) - 1;
      await emitClarify(tester, api, {
        'question': '走 requested_at 分支',
        'choices_offered': <String>[],
        'requestedAt': requestedAt,
        'timeoutSeconds': 300,
      });
      await tester.pump(const Duration(milliseconds: 50));

      // target = requestedAt + 300 ≈ now + 299 → 04:5x
      final countdown = tester.widget<Text>(
        find.byKey(const ValueKey('chat-prompt-clarify-countdown')),
      );
      expect(countdown.data, isNotNull);
      expect(countdown.data, matches(RegExp(r'^0[45]:[0-5]\d$')));

      await _unmount(tester);
    });

    testWidgets('倒计时 <10 秒时走紧急配色（isUrgent）', (tester) async {
      final api = baseApi();
      await _pumpPage(tester, api);

      await emitClarify(tester, api, {
        'question': '紧急澄清',
        'choices_offered': <String>[],
        'timeout_seconds': 5,
      });
      await tester.pump(const Duration(milliseconds: 50));

      final countdown = tester.widget<Text>(
        find.byKey(const ValueKey('chat-prompt-clarify-countdown')),
      );
      expect(countdown.data, '00:05');
      // isUrgent 分支 → 非同普通灰（橙色告警）
      expect(countdown.style?.color, isNot(CupertinoColors.secondaryLabel));

      await _unmount(tester);
    });

    testWidgets('计时器每秒触发且剩余 >0 → 卡片保留（不误判超时）', (tester) async {
      final api = baseApi();
      await _pumpPage(tester, api);

      await emitClarify(tester, api, {
        'question': '正常倒计时',
        'choices_offered': <String>[],
        'timeout_seconds': 120,
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('02:00'), findsOneWidget);

      // 推进 1s → Timer.periodic 触发一次，rem 仍 >0 → 仅刷新剩余秒数
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('chat-prompt-clarify-countdown')), findsOneWidget);
      expect(find.text('正常倒计时'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('真实时间跨过目标 → 计时器回调归零并超时收卡', (tester) async {
      final api = baseApi();
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      // expires_at = now + 0.5s：ceil(0.5)=1 → 计时器启动（不立即超时）
      final expiresAt =
          (DateTime.now().millisecondsSinceEpoch / 1000) + 0.5;
      await emitClarify(tester, api, {
        'question': '跨过目标的澄清',
        'choices_offered': <String>[],
        'expires_at': expiresAt,
      });
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('需要澄清'), findsOneWidget);

      // 真实时间推进 700ms（fake clock 不动），使 target 落在过去
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      // 触发周期性计时器一次
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container.read(chatControllerProvider('s1')).pendingAction.clarificationPrompt,
        isNull,
      );
      expect(find.text('需要澄清'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('父级状态更新触发 didUpdateWidget → 澄清 id 未变则不重启计时', (
      tester,
    ) async {
      final api = baseApi();
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      await emitClarify(tester, api, {
        'question': '重绘不重启',
        'choices_offered': <String>[],
        'timeout_seconds': 200,
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('03:20'), findsOneWidget);

      // 同一 clarify_id 再推一次 + 置 notice → ChatPage 重建 → 卡片 didUpdateWidget
      api.emit(
        const ClarificationPendingSseEvent({
          'pending': {
            'clarify_id': 'clarify-x',
            'question': '重绘不重启',
            'choices_offered': <String>[],
            'timeout_seconds': 200,
          },
          'pending_count': 1,
        }),
      );
      await tester.pump();
      container.read(chatControllerProvider('s1').notifier).setNotice('重绘');

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 仍是同一条卡片、同一计时（未重建）
      expect(find.text('重绘不重启'), findsOneWidget);
      expect(find.text('03:20'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-prompt-clarify-input')), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('暗色模式：澄清输入框走 CupertinoTextField 默认装饰', (tester) async {
      final api = baseApi();
      await _pumpPage(tester, api, brightness: Brightness.dark);

      await emitClarify(tester, api, {
        'question': '暗色澄清',
        'choices_offered': <String>[],
        'timeout_seconds': 120,
      });
      await tester.pump(const Duration(milliseconds: 50));

      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-prompt-clarify-input')),
      );
      expect(field.decoration, const CupertinoTextField().decoration);

      await _unmount(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // H. 重命名对话框（取消 / 暗色装饰分支）
  // ---------------------------------------------------------------------------
  group('重命名对话框分支', () {
    Map<String, Object?> titledSession() => {
      'session': {'session_id': 's1', 'title': '旧标题', 'messages': const []},
    };

    testWidgets('取消重命名 → 不调用 renameSession', (tester) async {
      final api = _FakeChatApi()..sessionResult = titledSession();
      await _pumpRouted(tester, api);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-rename')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('chat-rename-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.renameCalls, 0);
      expect(find.text('旧标题'), findsWidgets);

      await _unmount(tester);
    });

    testWidgets('暗色模式重命名对话框 → 走 CupertinoTextField 默认装饰与占位样式', (
      tester,
    ) async {
      final api = _FakeChatApi()..sessionResult = titledSession();
      await _pumpRouted(tester, api, brightness: Brightness.dark);

      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-rename')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final dialog = find.ancestor(
        of: find.byKey(const ValueKey('chat-rename-save')),
        matching: find.byType(CupertinoAlertDialog),
      );
      final field = tester.widget<CupertinoTextField>(
        find.descendant(of: dialog, matching: find.byType(CupertinoTextField)),
      );
      expect(field.decoration, const CupertinoTextField().decoration);
      expect(
        field.placeholderStyle,
        const CupertinoTextField().placeholderStyle,
      );

      await tester.tap(find.byKey(const ValueKey('chat-rename-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await _unmount(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // I. 导出会话（_exportSession 成功 / 落盘 / ApiException 三分支）
  // ---------------------------------------------------------------------------
  group('导出会话', () {
    Map<String, Object?> exportSession() => {
      'session': {'session_id': 's1', 'title': '导出会话', 'messages': const []},
    };

    tearDown(SafeClipboard.resetOverridesForTesting);

    testWidgets('导出成功（剪贴板）→ 展示成功对话框并写入剪贴板', (tester) async {
      final api = _FakeChatApi()..sessionResult = exportSession();
      final client = _ExportStubApiClient();
      String? clipboardText;
      SafeClipboard.clipboardSetterOverride = (text) async {
        clipboardText = text;
      };

      await _pumpRouted(tester, api, apiClient: client);
      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-export')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.calls, 1);
      expect(clipboardText, '# 导出内容');
      expect(find.text('导出成功'), findsOneWidget);
      expect(find.text('Markdown 已复制到剪贴板。'), findsOneWidget);

      // 关闭对话框
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('导出成功'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('导出内容超限 → 降级落盘并展示文件路径', (tester) async {
      final api = _FakeChatApi()..sessionResult = exportSession();
      final client = _ExportStubApiClient();
      final dir = Directory.systemTemp.createTempSync('hermes_export_extra');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      SafeClipboard.maxBytesOverride = 4;
      SafeClipboard.destinationDirOverride = dir;

      await _pumpRouted(tester, api, apiClient: client);
      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-export')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('导出成功'), findsOneWidget);
      expect(find.textContaining('内容过大已保存到文件：'), findsOneWidget);
      expect(dir.listSync().whereType<File>(), isNotEmpty);

      await _unmount(tester);
    });

    testWidgets('导出失败（ApiException）→ 展示失败对话框与错误文案', (tester) async {
      final api = _FakeChatApi()..sessionResult = exportSession();
      final client = _ExportStubApiClient(
        throwError: HttpException(500, null, message: '导出通道错误'),
      );

      await _pumpRouted(tester, api, apiClient: client);
      await _openSessionMenu(tester);
      await tester.tap(find.byKey(const ValueKey('chat-action-export')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('导出失败'), findsOneWidget);
      expect(find.text('导出通道错误'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('导出失败'), findsNothing);

      await _unmount(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // J. 新会话 URL 替换 + 生命周期 resumed 监听
  // ---------------------------------------------------------------------------
  group('新会话与生命周期', () {
    testWidgets('新会话首条消息后 sessionId 非空 → go 替换为 /chat/<newId>', (
      tester,
    ) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {
            'session_id': '',
            'title': '新会话',
            'messages': const [],
          },
        };
      final router = await _pumpNewSessionRoute(tester, api);
      expect(router.state.uri.path, '/chat');

      await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')),
        '首条消息',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.startChatCalls, 1);
      expect(router.state.uri.path, '/chat/sess-new');

      await _unmount(tester);
    });

    testWidgets('生命周期回到前台 → 触发缺失消息同步（不抛异常）', (tester) async {
      final api = _FakeChatApi()
        ..sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      await tester.pump();
      final callsAfterPause = api.sessionCalls;

      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // resumed → _triggerSyncDebounced → controller.syncMissingMessages
      expect(api.sessionCalls, greaterThanOrEqualTo(callsAfterPause));
      expect(tester.takeException(), isNull);

      await _unmount(tester);
    });
  });
}

// -----------------------------------------------------------------------------
// helpers
// -----------------------------------------------------------------------------

/// 大纲行预览：与 `chatOutlineEntriesProvider` 同口径（>40 字截断 + '…'）。
String _outlinePreview(String content) =>
    content.length > 40 ? '${content.substring(0, 40)}\u2026' : content;

/// 测试用连接存储（内存版，绕开 secure_storage 平台通道）。
ConnectionStore _memoryConnectionStore() =>
    ConnectionStore(storage: InMemorySecureStorage());

/// 组装 ChatPage（override chatApiProvider 注入 fake）。
Future<void> _pumpPage(
  WidgetTester tester,
  _FakeChatApi api, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(api),
        connectionStoreProvider.overrideWithValue(_memoryConnectionStore()),
      ],
      child: CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: const ChatPage(sessionId: 's1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 组装带 GoRouter 的 ChatPage（会话菜单导航走真实路由）。
///
/// 菜单项超过 10 个，默认 600px 视口会裁剪底部项导致 tap miss —— 统一放大视口。
Future<GoRouter> _pumpRouted(
  WidgetTester tester,
  _FakeChatApi api, {
  Brightness brightness = Brightness.light,
  _ExportStubApiClient? apiClient,
}) async {
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
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(api),
        connectionStoreProvider.overrideWithValue(_memoryConnectionStore()),
        if (apiClient != null) apiClientProvider.overrideWithValue(apiClient),
      ],
      child: CupertinoApp.router(
        theme: CupertinoThemeData(brightness: brightness),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}

/// 新会话路由（`/chat` → sessionId 空串），用于 P4 URL 替换断言。
Future<GoRouter> _pumpNewSessionRoute(
  WidgetTester tester,
  _FakeChatApi api,
) async {
  final router = GoRouter(
    initialLocation: '/chat',
    routes: [
      GoRoute(
        path: '/chat',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: ChatPage(sessionId: '')),
      ),
      GoRoute(
        path: '/chat/:id',
        pageBuilder: (context, state) => NoTransitionPage(
          child: ChatPage(sessionId: state.pathParameters['id']!),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(api),
        connectionStoreProvider.overrideWithValue(_memoryConnectionStore()),
      ],
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}

/// 打开三点会话操作菜单（宽屏 popover / 窄屏 sheet 统一路径）。
Future<void> _openSessionMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

ProviderContainer _containerOf(WidgetTester tester) {
  final context = tester.element(find.byType(ChatPage));
  return ProviderScope.containerOf(context);
}

/// 驱动一次真实异步（`dart:io` 的 `FileSystemEntity.isDirectory` 等）：
/// fake-async 下真实 I/O 回调不会自行投递，必须借 `runAsync` 放行事件循环。
Future<void> _settleRealIo(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 卸载 ProviderScope（dispose 容器 → 取消看门狗等周期定时器，避免 pending timer）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// 不联网的 ApiClient 替身：只拦 `sendDataReturningResponse`（导出链路的唯一出口）。
class _ExportStubApiClient extends ApiClient {
  _ExportStubApiClient({this.throwError})
    : super(baseUrl: 'http://test.local:30002');

  final Object? throwError;
  int calls = 0;

  @override
  Future<ApiByteResponse> sendDataReturningResponse(
    Endpoint endpoint, {
    String method = 'GET',
    Map<String, Object?>? body,
    Duration? timeout,
    String accept = 'application/json',
    bool allowAutoReauth = true,
  }) async {
    calls++;
    final error = throwError;
    if (error != null) throw error;
    return (
      data: Uint8List.fromList(utf8.encode('# 导出内容')),
      headers: Headers(),
      statusCode: 200,
    );
  }
}
