import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/core/utils/selected_context.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';
import 'package:hermes_ui/features/chat/widgets/selected_context_card.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/contrast_utils.dart';
import '../../helpers/fake_chat_api.dart';

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

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  required Brightness brightness,
  ChatState state = const ChatState(sessionId: 's1'),
  bool highContrast = false,
  CupertinoUserInterfaceLevelData level = CupertinoUserInterfaceLevelData.base,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(FakeChatApi()),
        chatControllerProvider.overrideWith(() => _StaticChatController(state)),
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: highContrast),
            child: CupertinoUserInterfaceLevel(data: level, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final brightness in Brightness.values) {
    for (final twoPane in [false, true]) {
      testWidgets(
        'composer $brightness twoPane=$twoPane preserves dark defaults',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            kComposerTwoPaneKey: twoPane,
          });
          await _pump(
            tester,
            brightness: brightness,
            child: const ChatPage(sessionId: 's1'),
          );
          final field = tester.widget<CupertinoTextField>(
            find.byKey(const ValueKey('chat-input-field')),
          );
          if (brightness == Brightness.light) {
            final decoration = field.decoration!;
            expect(decoration.color, LightSurfaces.card);
            expect(
              decoration.border,
              Border.all(color: LightSurfaces.cardBorder, width: 0.5),
            );
            expect(
              contrastRatio(field.placeholderStyle!.color!, decoration.color!),
              greaterThanOrEqualTo(4.5),
            );
          } else {
            expect(field.decoration, const CupertinoTextField().decoration);
            expect(
              field.placeholderStyle,
              const CupertinoTextField().placeholderStyle,
            );
          }
          for (final key in [
            'chat-attach-button',
            'chat-saved-prompts-button',
          ]) {
            final icon = tester.widget<Icon>(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(Icon),
              ),
            );
            // #140 P2-b：深色档改由 CupertinoColors.systemGrey 解析而来，结果是
            // 带解析值的 CupertinoDynamicColor（值同 #8E8E93、类型不同），
            // 故断言比解析值而非对象相等，语义仍是「深色像素不变」。
            expect(
              icon.color!.toARGB32(),
              (brightness == Brightness.light
                      ? LightSurfaces.textSecondary
                      : const Color(0xFF8E8E93))
                  .toARGB32(),
            );
          }
          await _unmount(tester);
        },
      );
    }
    testWidgets('confirmation actions $brightness preserve dark defaults', (
      tester,
    ) async {
      await _pump(
        tester,
        brightness: brightness,
        state: const ChatState(sessionId: 's1', phase: ChatPhase.streaming),
        child: const ChatPage(sessionId: 's1'),
      );
      await tester.tap(find.byKey(const ValueKey('chat-stop-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final actions = tester.widgetList<CupertinoDialogAction>(
        find.byType(CupertinoDialogAction),
      );
      expect(actions, hasLength(2));
      for (final action in actions) {
        if (brightness == Brightness.light) {
          final text = find.byWidget(action.child);
          final color = DefaultTextStyle.of(tester.element(text)).style.color!;
          expect(
            contrastRatio(
              color,
              localBackgroundFor(tester.element(text), brightness),
            ),
            greaterThanOrEqualTo(4.5),
          );
        } else {
          expect(action.textStyle, isNull);
        }
      }
      final cancel = actions.first;
      await tester.tap(find.byWidget(cancel));
      await tester.pump(const Duration(milliseconds: 400));
      await _unmount(tester);
    });
    for (final highContrast in [false, true]) {
      for (final level in CupertinoUserInterfaceLevelData.values) {
        testWidgets(
          'approval $brightness hc=$highContrast $level uses its actual tint',
          (tester) async {
            await _pump(
              tester,
              brightness: brightness,
              highContrast: highContrast,
              level: level,
              state: const ChatState(
                sessionId: 's1',
                pendingAction: ChatPendingActionState(
                  approvalPrompt: {
                    'question': 'Approval check',
                    'choices': ['Allow'],
                  },
                ),
              ),
              child: const ChatPage(sessionId: 's1'),
            );
            final question = find.text('Approval check');
            final context = tester.element(question);
            final title = tester.widget<Text>(
              find.text(AppLocalizations.of(context).approvalNeeded),
            );
            final surface = tester
                .widgetList<Container>(
                  find.ancestor(of: question, matching: find.byType(Container)),
                )
                .map((widget) => widget.decoration)
                .whereType<BoxDecoration>()
                .firstWhere(
                  (decoration) =>
                      decoration.borderRadius == BorderRadius.circular(10),
                );
            if (brightness == Brightness.light) {
              expect(surface.color!.a, 1);
              expect(
                contrastRatio(title.style!.color!, surface.color!),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                surface.border,
                Border.all(color: LightSurfaces.cardBorder, width: 0.5),
              );
            } else {
              expect(
                surface.color,
                CupertinoColors.systemOrange.withValues(alpha: 0.12),
              );
              expect(surface.border, isNull);
              expect(
                title.style!.color!.toARGB32(),
                CupertinoColors.systemOrange.resolveFrom(context).toARGB32(),
              );
            }
            await _unmount(tester);
          },
        );
      }
    }
    testWidgets(
      'user code and links $brightness keep brand bubble and readable detail surfaces',
      (tester) async {
        late BuildContext styleContext;
        await _pump(
          tester,
          brightness: brightness,
          child: Builder(
            builder: (context) {
              styleContext = context;
              return Center(
                child: Container(
                  key: const ValueKey('brand-bubble'),
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                  child: MarkdownBody(
                    data: 'Check `inline-command` and [link](https://example.com).\n\n```text\ncode block\n```',
                    styleSheet: buildUserMarkdownStyleSheet(context),
                    builders: createUserMarkdownBuilders(context),
                  ),
                ),
              );
            },
          ),
        );
        final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
        final sheet = markdown.styleSheet!;
        final text = tester.widget<Text>(find.text('inline-command'));
        final pill = tester
            .widgetList<Container>(
              find.ancestor(
                of: find.text('inline-command'),
                matching: find.byType(Container),
              ),
            )
            .firstWhere((container) => container.padding == kInlineCodePadding);
        final background = (pill.decoration! as BoxDecoration).color!;
        expect(
          tester
              .widget<Container>(find.byKey(const ValueKey('brand-bubble')))
              .color,
          CupertinoColors.activeBlue.resolveFrom(styleContext),
        );
        expect(sheet.p!.color, CupertinoColors.white);
        if (brightness == Brightness.light) {
          expect(
            contrastRatio(text.style!.color!, background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(sheet.a!.color!, sheet.a!.backgroundColor!),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(
              sheet.code!.color!,
              (sheet.codeblockDecoration! as BoxDecoration).color!,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(sheet.a!.decoration, TextDecoration.underline);
        } else {
          expect(background, CupertinoColors.white.withValues(alpha: 0.22));
          expect(sheet.a!.backgroundColor, isNull);
          expect(
            (sheet.codeblockDecoration! as BoxDecoration).color,
            CupertinoColors.white.withValues(alpha: 0.15),
          );
        }
        await _unmount(tester);
      },
    );
    testWidgets(
      'shared Markdown defaults $brightness stay unchanged outside chat',
      (tester) async {
        late BuildContext styleContext;
        await _pump(
          tester,
          brightness: brightness,
          child: Builder(
            builder: (context) {
              styleContext = context;
              return const SizedBox.shrink();
            },
          ),
        );
        final original = buildAssistantMarkdownStyleSheet(styleContext);
        final chat = buildAssistantMarkdownStyleSheet(
          styleContext,
          useLightSurfaces: true,
        );
        expect(
          original.code!.backgroundColor,
          CupertinoColors.systemGrey5.resolveFrom(styleContext),
        );
        expect(
          original.a!.color,
          CupertinoColors.link.resolveFrom(styleContext),
        );
        expect((original.codeblockDecoration! as BoxDecoration).border, isNull);
        if (brightness == Brightness.dark) {
          expect(chat.p, original.p);
          expect(chat.a, original.a);
          expect(chat.code, original.code);
          expect(chat.codeblockDecoration, original.codeblockDecoration);
          expect(chat.blockquoteDecoration, original.blockquoteDecoration);
          expect(chat.tableBorder, original.tableBorder);
        } else {
          expect(
            contrastRatio(chat.a!.color!, LightSurfaces.page),
            greaterThanOrEqualTo(4.5),
          );
        }
        await _unmount(tester);
      },
    );
  }

  testWidgets(
    'tool metadata and selected-context quote pass AA on their rendered surfaces',
    (tester) async {
      await _pump(
        tester,
        brightness: Brightness.light,
        child: CupertinoPageScaffold(
          child: Column(
            children: [
              ToolCallCard(
                call: ToolCall(
                  id: 'success',
                  name: 'terminal',
                  preview: 'Done',
                  duration: 0.42,
                  startedAt: 100,
                  isCompleted: true,
                ),
              ),
              ToolCallCard(
                call: ToolCall(
                  id: 'failure',
                  name: 'terminal',
                  preview: 'Failed',
                  isCompleted: true,
                  isError: true,
                  startedAt: 100,
                ),
              ),
              const SelectedContextCard(
                block: SelectedContextBlock(
                  label: 'Quote',
                  quote: 'Readable context',
                ),
              ),
            ],
          ),
        ),
      );
      for (final element in find.byType(Text).evaluate()) {
        final text = element.widget as Text;
        final color = text.style?.color;
        if (color != null) {
          expect(
            contrastRatio(color, localBackgroundFor(element, Brightness.light)),
            greaterThanOrEqualTo(4.5),
            reason: text.data,
          );
        }
      }
      for (final element in find.byType(Icon).evaluate()) {
        final icon = element.widget as Icon;
        if (icon.color != null) {
          expect(
            contrastRatio(
              icon.color!,
              localBackgroundFor(element, Brightness.light),
            ),
            greaterThanOrEqualTo(3),
          );
        }
      }
      await _unmount(tester);
    },
  );
}
