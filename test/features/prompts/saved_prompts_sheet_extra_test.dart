// 覆盖补强：saved_prompts_sheet.dart 的未覆盖区间。
//
// 目标（lcov 口径）：
//   - _handleSaveCurrent：create 返回 null（savePromptFailed）与 create 抛异常两个分支
//   - _handleDelete：remove 抛异常 → deletePromptFailed 提示
//   - _showAlert：isError=true 时正文红字样式
//   - error 分支：有缓存数据时的「不替换整板」紧凑重试行 + 重试回调
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/prompts/widgets/saved_prompts_sheet.dart';

import '../../helpers/fake_prompts_api.dart';

ProviderScope wrap(Widget child, PromptsApi api) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      promptsApiFactoryProvider.overrideWithValue((_) => api),
    ],
    child: CupertinoApp(
      theme: const CupertinoThemeData(brightness: Brightness.light),
      home: child,
    ),
  );
}

Widget sheetFor(PromptsApi api, {String? currentInput}) {
  return wrap(
    SavedPromptsSheet(
      onInsert: _noop,
      currentInput: currentInput,
      getCurrentInput: currentInput == null ? null : () => currentInput,
    ),
    api,
  );
}

SavedPrompt p(String id, String text, {String? label}) =>
    SavedPrompt(id: id, label: label, text: text, createdAt: 1700000000);

/// create 成功但服务端未回显 prompt（ok=true / prompt=null）。
class _NullPromptApi extends FakePromptsApi {
  _NullPromptApi({super.initialPrompts});

  @override
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  }) async {
    createCount++;
    lastCreateText = text;
    lastCreateLabel = label;
    return const SavePromptResponse(ok: true, prompt: null);
  }
}

void main() {
  group('SavedPromptsSheet 收藏当前输入 · 失败分支', () {
    testWidgets('create 返回 null → 弹 savePromptFailed（红字正文）', (tester) async {
      final api = _NullPromptApi(initialPrompts: const []);
      await tester.pumpWidget(
        sheetFor(api, currentInput: '  something  '),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(
        find.byKey(const ValueKey('saved-prompts-save-current')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 请求确实发出去了（不是被空输入短路）
      expect(api.createCount, 1);
      expect(api.lastCreateText, 'something');
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('收藏失败'), findsNWidgets(2));

      // isError=true 分支：正文带 statusRedText 颜色（行 115）
      final dialog = tester.widget<CupertinoAlertDialog>(
        find.byType(CupertinoAlertDialog),
      );
      final dialogContext = tester.element(find.byType(CupertinoAlertDialog));
      final content = dialog.content! as Text;
      expect(content.data, '收藏失败');
      expect(content.style?.color, statusRedText.resolveFrom(dialogContext));

      // 列表未被污染
      expect(find.byKey(const ValueKey('saved-prompts-retry')), findsNothing);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('create 抛异常 → catch 分支透传 error.toString()', (tester) async {
      final api = FakePromptsApi(initialPrompts: const []);
      api.createError = Exception('create boom');
      await tester.pumpWidget(
        sheetFor(api, currentInput: 'to save'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(
        find.byKey(const ValueKey('saved-prompts-save-current')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.createCount, 1);
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('收藏失败'), findsOneWidget);
      expect(find.textContaining('create boom'), findsOneWidget);

      final dialog = tester.widget<CupertinoAlertDialog>(
        find.byType(CupertinoAlertDialog),
      );
      final dialogContext = tester.element(find.byType(CupertinoAlertDialog));
      expect(
        (dialog.content! as Text).style?.color,
        statusRedText.resolveFrom(dialogContext),
      );

      // 失败后按钮恢复可用（_saving 落回 false）
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final button = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('saved-prompts-save-current')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('getCurrentInput 优先于 currentInput（动态读取）', (tester) async {
      final api = FakePromptsApi(initialPrompts: const []);
      var live = 'first';
      await tester.pumpWidget(
        wrap(
          SavedPromptsSheet(
            onInsert: _noop,
            currentInput: 'stale snapshot',
            getCurrentInput: () => live,
          ),
          api,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      live = 'live value';
      await tester.tap(
        find.byKey(const ValueKey('saved-prompts-save-current')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.createCount, 1);
      expect(api.lastCreateText, 'live value');
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('SavedPromptsSheet 删除 · 失败分支', () {
    testWidgets('remove 抛异常 → 弹 deletePromptFailed 且列表回滚', (tester) async {
      final api = FakePromptsApi(
        initialPrompts: [p('a1', 'hello'), p('a2', 'world')],
      );
      api.deleteError = Exception('delete boom');
      await tester.pumpWidget(sheetFor(api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('saved-prompt-delete-a1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.deleteCount, 1);
      expect(api.lastDeleteId, 'a1');
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('删除失败'), findsOneWidget);
      expect(find.textContaining('delete boom'), findsOneWidget);

      final dialog = tester.widget<CupertinoAlertDialog>(
        find.byType(CupertinoAlertDialog),
      );
      final dialogContext = tester.element(find.byType(CupertinoAlertDialog));
      expect(
        (dialog.content! as Text).style?.color,
        statusRedText.resolveFrom(dialogContext),
      );

      // 失败回滚：两行都还在
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-prompt-a2-1')), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.delete), findsNWidgets(2));
    });
  });

  group('SavedPromptsSheet 错误态 · 有缓存数据时保留整板', () {
    testWidgets('AsyncError 携带 previous value → 紧凑重试行，不替换整板', (tester) async {
      final api = FakePromptsApi(initialPrompts: [p('a1', 'cached row')]);
      await tester.pumpWidget(sheetFor(api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SavedPromptsSheet)),
      );
      api.fetchError = Exception('refresh boom');
      await container.read(savedPromptsControllerProvider.notifier).refresh();
      await tester.pump();

      final state = container.read(savedPromptsControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.valueOrNull, isNotNull);

      // 命中「有数据」分支：只有重试行，没有整板错误正文
      expect(find.byKey(const ValueKey('saved-prompts-retry')), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.textContaining('refresh boom'), findsNothing);
      expect(find.text('收藏提示词'), findsOneWidget);
    });

    testWidgets('紧凑重试行 onPressed 重新发起 fetch → 列表恢复', (tester) async {
      final api = FakePromptsApi(initialPrompts: [p('a1', 'cached row')]);
      await tester.pumpWidget(sheetFor(api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SavedPromptsSheet)),
      );
      api.fetchError = Exception('refresh boom');
      await container.read(savedPromptsControllerProvider.notifier).refresh();
      await tester.pump();
      expect(find.byKey(const ValueKey('saved-prompts-retry')), findsOneWidget);
      final failedFetches = api.fetchCount;

      // 恢复服务端后点重试（覆盖行 293-294 的 onPressed 箭头体）
      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('saved-prompts-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.fetchCount, greaterThan(failedFetches));
      final value = container
          .read(savedPromptsControllerProvider)
          .valueOrNull;
      expect(value, isNotNull);
      expect(value!.single.id, 'a1');
      expect(find.byKey(const ValueKey('saved-prompts-retry')), findsNothing);
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsOneWidget);
    });
  });
}

void _noop(String _) {}
