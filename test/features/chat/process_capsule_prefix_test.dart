import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/widgets/collapsible_process_capsule.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

/// #64 方案 E：「过程 ·」前缀的摘要纯函数行为。
void main() {
  final l10nZh = const AppLocalizations(Locale('zh'));
  final l10nEn = const AppLocalizations(Locale('en'));

  ToolCallGroup group(List<ToolCall> calls) =>
      ToolCallGroup(id: 'g1', anchorMessageID: 'a1', toolCalls: calls);

  final calls = [
    ToolCall(id: 't1', name: 'execute_code', args: null, isCompleted: true),
    ToolCall(id: 't2', name: 'terminal', args: null, isCompleted: true),
    ToolCall.thinking('think'),
  ];

  test('processPrefix=true：中文摘要以「过程 ·」开头', () {
    final title = formatProcessCapsuleSummary(
      toolGroups: [group(calls)],
      intermediateTextCount: 0,
      hideThinking: false,
      l10n: l10nZh,
      processPrefix: true,
    );
    expect(title, startsWith('过程 · '));
    expect(title, contains('思考'));
  });

  test('processPrefix=true：英文摘要以 "Process · " 开头', () {
    final title = formatProcessCapsuleSummary(
      toolGroups: [group(calls)],
      intermediateTextCount: 0,
      hideThinking: false,
      l10n: l10nEn,
      processPrefix: true,
    );
    expect(title, startsWith('Process \u00B7 '));
  });

  test('processPrefix=false（默认）：无前缀，向后兼容', () {
    final title = formatProcessCapsuleSummary(
      toolGroups: [group(calls)],
      intermediateTextCount: 0,
      hideThinking: false,
      l10n: l10nZh,
    );
    expect(title.startsWith('过程'), isFalse);
  });

  test('空计数：仅「过程」（无前缀参数时同义，counts 空即回退标签）', () {
    final title = formatProcessCapsuleSummary(
      toolGroups: [group(const [])],
      intermediateTextCount: 0,
      hideThinking: true,
      l10n: l10nZh,
      processPrefix: true,
    );
    expect(title, '过程');
  });

  test('第三方 MCP 工具在过程摘要中聚合为「外部工具 ×N」', () {
    final mcpCalls = [
      ToolCall(id: 'm1', name: 'mcp__github__create_issue', isCompleted: true),
      ToolCall(id: 'm2', name: 'mcp__playwright__browser_navigate', isCompleted: true),
      ToolCall(id: 'm3', name: 'mcp__anki__addNote', isCompleted: true),
    ];
    final title = formatProcessCapsuleSummary(
      toolGroups: [group(mcpCalls)],
      intermediateTextCount: 0,
      hideThinking: false,
      l10n: l10nZh,
      processPrefix: true,
    );
    expect(title, '过程 · 外部工具 \u00D73');
    final titleEn = formatProcessCapsuleSummary(
      toolGroups: [group(mcpCalls)],
      intermediateTextCount: 0,
      hideThinking: false,
      l10n: l10nEn,
      processPrefix: true,
    );
    expect(titleEn, 'Process · External Tools \u00D73');
  });
}
