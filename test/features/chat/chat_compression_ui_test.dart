import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/context_window_snapshot.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/utils/accessibility.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/context_window_indicator.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// #156 UI 侧守卫：
/// - 指示器在压缩期间渲染 iOS 原生 loading 记号（同槽位、无百分比）；
/// - 输入栏在压缩期间禁用发送并给出明确提示，压缩结束后恢复可发。
void main() {
  group('#156 指示器加载态', () {
    testWidgets('RED-156-UI-0a 压缩中：渲染 loading 记号且不再显示百分比', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: Center(
            child: ContextWindowIndicator(
              snapshot: ContextWindowSnapshot(
                lastPromptTokens: 1200,
                contextLength: 200000,
              ),
              onTap: null,
              isCompressing: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      // 百分比是压缩前的旧用量，压缩中显示会误导（以为它是压缩进度）。
      expect(find.text('1'), findsNothing);
      // 槽位尺寸不变（切换到 loading 不产生跳位）。
      expect(
        tester.getSize(find.byType(ContextWindowIndicator)),
        const Size(
          ContextWindowIndicator.tapTargetSize,
          ContextWindowIndicator.tapTargetSize,
        ),
      );
    });

    testWidgets('RED-156-UI-0b 非压缩态：仍是百分比环，无 loading', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: Center(
            child: ContextWindowIndicator(
              snapshot: ContextWindowSnapshot(
                lastPromptTokens: 1200,
                contextLength: 200000,
              ),
              onTap: null,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('#156 输入栏压缩守卫', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: false,
      });
    });

    testWidgets('RED-156-UI-1 压缩中禁用发送 + 提示文案；结束后恢复可发', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      // 轮询首拍即收敛（idle）→ 测完不留 pending timer。
      api.compressStatusResponse = const SessionCompressStatusResponse(
        ok: true,
        status: 'idle',
        sessionId: 's1',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatPage)),
      );
      final controller = container.read(chatControllerProvider('s1').notifier);
      final l10n = AppLocalizations.of(tester.element(find.byType(ChatPage)));

      Future<void> typeText(String text) async {
        await tester.enterText(
          find.byKey(const ValueKey('chat-input-field')),
          text,
        );
        await tester.pump();
      }

      AccessibleButton sendButton() => tester.widget<AccessibleButton>(
        find.byKey(const ValueKey('chat-send-button')),
      );
      CupertinoTextField inputField() => tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-input-field')),
      );

      await typeText('待发消息');

      // 基线：非压缩态可发、placeholder 为常规文案。
      expect(sendButton().onPressed, isNotNull);
      expect(inputField().placeholder, l10n.sendMessagePlaceholder);

      // 启动压缩（异步 start 立刻返回，进度由会话状态承载）。
      unawaited(controller.startCompression());
      await tester.pump();
      await tester.pump();
      expect(controller.state.isCompressingContext, isTrue);

      // 压缩中：发送按钮禁用（输入仍可编辑）+ 明确提示 + 指示器 loading。
      expect(sendButton().onPressed, isNull, reason: '压缩期间不允许发新回合');
      expect(inputField().placeholder, l10n.compressingContextHint);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chat-context-indicator-button')),
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
      );

      // 服务端收敛（idle）后本地复位，发送能力恢复。
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(controller.state.isCompressingContext, isFalse);
      expect(sendButton().onPressed, isNotNull);
      expect(inputField().placeholder, l10n.sendMessagePlaceholder);
    });

    testWidgets('RED-156-UI-2 压缩中直接调 send 被拒（守卫兜底，非仅 UI 禁用）', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      api.compressStatusResponse = const SessionCompressStatusResponse(
        ok: true,
        status: 'idle',
        sessionId: 's1',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatPage)),
      );
      final controller = container.read(chatControllerProvider('s1').notifier);

      unawaited(controller.startCompression());
      await tester.pump();
      await tester.pump();
      api.startChatCalls = 0;

      bool? sent;
      unawaited(controller.send('绕过 UI 直接发').then((v) => sent = v));
      await tester.pump();

      expect(sent, isFalse);
      expect(api.startChatCalls, 0);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    });
  });
}
