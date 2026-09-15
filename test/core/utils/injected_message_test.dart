import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/utils/injected_message.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

ChatMessage _msg(String content, {String role = 'user'}) =>
    ChatMessage(role: role, content: content);

void main() {
  group('isInjectedNotice', () {
    test('background process 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg('[IMPORTANT: Background process proc_abc completed normally'),
        ),
        isTrue,
      );
    });
    test('cron 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[IMPORTANT: You are running as a scheduled cron job.',
            role: 'system',
          ),
        ),
        isTrue,
      );
    });
    test('skill 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg('[IMPORTANT: The user has invoked the "foo" skill'),
        ),
        isTrue,
      );
    });
    test('[System: network cut] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]',
          ),
        ),
        isTrue,
      );
    });
    test('[System note: gateway recovery] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System note: The previous turn was interrupted by a shutdown; the gateway is now back online. Do NOT re-execute.]',
          ),
        ),
        isTrue,
      );
    });
    test('[System note: new message pending] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System note: A new message has arrived. The conversation history contains pending tool outputs from an interrupted turn. IGNORE those pending results.]',
          ),
        ),
        isTrue,
      );
    });
    test('[System note: suspended] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            "[System note: The user's previous session was stopped and suspended. This is a fresh conversation with no prior context.]",
          ),
        ),
        isTrue,
      );
    });
    test('[System note: first contact] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            "[System note: This is the user's very first message ever. Briefly introduce yourself.]",
          ),
        ),
        isTrue,
      );
    });
    test('[System note: memory recall] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            "[System note: The following is recalled memory context, NOT new user input. Treat as authoritative reference data — this is the agent's persistent memory and should inform all responses.]",
          ),
        ),
        isTrue,
      );
    });
    test('<memory-context> memory recall 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '<memory-context>\n[System note: The following is recalled memory context, NOT new user input.]\nhello\n</memory-context>',
          ),
        ),
        isTrue,
      );
    });
    test('[System: codex reasoning-only] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System: Your previous response contained only internal reasoning and never produced a visible answer or tool call.]',
          ),
        ),
        isTrue,
      );
    });
    test('[System: Continue now] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System: Continue now. Execute the required tool calls and only send your final answer after completing the task.]',
          ),
        ),
        isTrue,
      );
    });
    test('assistant 角色不命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System: The previous response was cut off by a network error',
            role: 'assistant',
          ),
        ),
        isFalse,
      );
    });
    test('用户手打 [System: hello] 不命中', () {
      expect(
        InjectedMessage.isInjectedNotice(_msg('[System: hello world]')),
        isFalse,
      );
    });
    test('用户手打 [IMPORTANT: hello] 不命中', () {
      expect(
        InjectedMessage.isInjectedNotice(_msg('[IMPORTANT: hello world]')),
        isFalse,
      );
    });
    test('role null 不命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          const ChatMessage(
            content: '[System: The previous response was cut off',
          ),
        ),
        isFalse,
      );
    });
    test('大小写/前空白容错', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '  [system: the previous response was cut off by a network error',
          ),
        ),
        isTrue,
      );
    });
  });

  group('classify', () {
    test('network cut', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]',
          ),
        ),
        InjectedNoticeKind.continuationNetworkCut,
      );
    });
    test('output limit', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[System: Your previous response was truncated by the output length limit. Continue exactly where you left off.]',
          ),
        ),
        InjectedNoticeKind.continuationOutputLimit,
      );
    });
    test('tool too large', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[System: Your previous tool call (patch) was too large and the stream timed out.]',
          ),
        ),
        InjectedNoticeKind.continuationToolTooLarge,
      );
    });
    test('codex reasoning-only', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[System: Your previous response contained only internal reasoning and never produced a visible answer.]',
          ),
        ),
        InjectedNoticeKind.codexNudge,
      );
    });
    test('codex Continue now', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[System: Continue now. Execute the required tool calls and only send your final answer.]',
          ),
        ),
        InjectedNoticeKind.codexNudge,
      );
    });
    test('gateway recovery — interrupted', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[System note: The previous turn was interrupted by a shutdown; the gateway is now back online.]',
          ),
        ),
        InjectedNoticeKind.gatewayRecovery,
      );
    });
    test('gateway recovery — pending IGNORE', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[System note: A new message has arrived. The conversation history contains pending tool outputs from an interrupted turn. IGNORE those pending results.]',
          ),
        ),
        InjectedNoticeKind.gatewayRecovery,
      );
    });
    test('session reset — suspended', () {
      expect(
        InjectedMessage.classify(
          _msg(
            "[System note: The user's previous session was stopped and suspended. This is a fresh conversation.]",
          ),
        ),
        InjectedNoticeKind.sessionReset,
      );
    });
    test('session reset — daily', () {
      expect(
        InjectedMessage.classify(
          _msg(
            "[System note: The user's session was automatically reset by the daily schedule.]",
          ),
        ),
        InjectedNoticeKind.sessionReset,
      );
    });
    test('session reset — expired', () {
      expect(
        InjectedMessage.classify(
          _msg(
            "[System note: The user's previous session expired due to inactivity.]",
          ),
        ),
        InjectedNoticeKind.sessionReset,
      );
    });
    test('session reset — first contact', () {
      expect(
        InjectedMessage.classify(
          _msg(
            "[System note: This is the user's very first message ever. Briefly introduce yourself.]",
          ),
        ),
        InjectedNoticeKind.sessionReset,
      );
    });
    test('memory recall', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[System note: The following is recalled memory context, NOT new user input.]',
          ),
        ),
        InjectedNoticeKind.memoryRecall,
      );
    });
    test('background process 仍正确', () {
      expect(
        InjectedMessage.classify(
          _msg(
            '[IMPORTANT: Background process proc_xxx completed normally (exit code 0).',
          ),
        ),
        InjectedNoticeKind.backgroundProcess,
      );
    });
    test('非注入 → none', () {
      expect(
        InjectedMessage.classify(_msg('hello world')),
        InjectedNoticeKind.none,
      );
    });
    test('裸 dropped-tool nudge → codex', () {
      expect(
        InjectedMessage.classify(
          _msg(
            'Your previous turn indicated a tool call but none was included. Do not narrate a plan',
          ),
        ),
        InjectedNoticeKind.codexNudge,
      );
    });
  });

  group('extractSummary', () {
    test('network cut zh', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          '[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]',
        ),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '网络中断续写');
    });
    test('network cut en', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          '[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]',
        ),
        const AppLocalizations(Locale('en')),
      );
      expect(s, 'Continue — network error');
    });
    test('output limit zh', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          '[System: Your previous response was truncated by the output length limit. Continue exactly where you left off.]',
        ),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '输出截断续写');
    });
    test('gateway zh', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          '[System note: The previous turn was interrupted by a shutdown; the gateway is now back online.]',
        ),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '网关已恢复');
    });
    test('session reset zh', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          "[System note: The user's previous session was stopped and suspended. This is a fresh conversation.]",
        ),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '会话已重置');
    });
    test('memory zh', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          '[System note: The following is recalled memory context, NOT new user input.]',
        ),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '记忆上下文');
    });
    test('tool too large zh', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          '[System: Your previous tool call (patch) was too large and the stream timed out.]',
        ),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '工具调用过大续写');
    });
    test('codex zh', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          '[System: Your previous response contained only internal reasoning and never produced a visible answer.]',
        ),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '继续执行');
    });
    test('null l10n → en fallback', () {
      final s = InjectedMessage.extractSummary(
        _msg(
          '[System: The previous response was cut off by a network error mid-stream.]',
        ),
      );
      expect(s, 'Continue — network error');
    });
  });

  // 2026-09-16 新增：异步委派家族（spec §10）。样例逐字取自运行期实产消息与
  // `hermes-agent/tools/process_registry_notifications.py` 的三个格式化函数。
  group('异步委派家族（ASYNC DELEGATION）', () {
    const zh = AppLocalizations(Locale('zh'));
    const en = AppLocalizations(Locale('en'));

    const taskFailed =
        r'''[ASYNC DELEGATION TASK FAILED — deleg_841a0035, task 1/3]
One subagent in a background fan-out you dispatched has failed while its siblings are still running. The batch's consolidated results will still arrive when the last sibling finishes; this is an early warning so you can re-dispatch or investigate now instead of then.
Task: 完整执行 D:\worktrees\hermes-cov-models-a\TASK.md 中的全部工作
Status: failed   Duration: 533.88s
Error: HTTP 500: Post "https://api.commandcode.ai/provider/v1/chat/completions": EOF
Live transcript: C:\Users\Admin\AppData\Local\hermes\cache\delegation\live\deleg_841a0035\task-0.log''';

    const batchComplete =
        r'''[ASYNC DELEGATION BATCH COMPLETE — deleg_b1c2d3e4f5]
A background fan-out unit you dispatched earlier — 2 subagent(s) — has finished; its consolidated results are below.
Role: leaf   Model: gemini-3.8-flash-high
--- ✓ TASK 1/2: goal a  (status=completed, 12.5s) ---
did a''';

    const singleComplete = r'''[ASYNC DELEGATION COMPLETE — deleg_y]
A background subagent you dispatched earlier has finished. You may have moved on since dispatching it.
Status: completed   API calls: 3   Duration: 9s''';

    test('三形态均判为注入（此前 TASK FAILED / BATCH COMPLETE 漏判）', () {
      for (final content in [taskFailed, batchComplete, singleComplete]) {
        expect(
          InjectedMessage.isInjectedNotice(_msg(content)),
          isTrue,
          reason: '首行：${content.split('\n').first}',
        );
      }
    });

    test('分类：失败/批量完成/单条完成 各归其位', () {
      expect(
        InjectedMessage.classify(_msg(taskFailed)),
        InjectedNoticeKind.subagentTaskFailed,
      );
      expect(
        InjectedMessage.classify(_msg(batchComplete)),
        InjectedNoticeKind.subagentBatchComplete,
      );
      expect(
        InjectedMessage.classify(_msg(singleComplete)),
        InjectedNoticeKind.subagentComplete,
      );
    });

    test('单条完成不再被 background subagent 兜底吞成 subagentAggregated', () {
      expect(
        InjectedMessage.classify(_msg(singleComplete)),
        isNot(InjectedNoticeKind.subagentAggregated),
      );
    });

    test('摘要 zh：委派任务 <id> · 状态', () {
      expect(
        InjectedMessage.extractSummary(_msg(taskFailed), zh),
        '委派任务 deleg_841a0035 · 任务 1/3 失败',
      );
      expect(
        InjectedMessage.extractSummary(_msg(batchComplete), zh),
        '委派任务 deleg_b1c2d3e4f5 · 批次完成',
      );
      expect(
        InjectedMessage.extractSummary(_msg(singleComplete), zh),
        '委派任务 deleg_y · 已完成',
      );
    });

    test('摘要 en：Subagent <id> · 状态', () {
      expect(
        InjectedMessage.extractSummary(_msg(taskFailed), en),
        'Subagent deleg_841a0035 · task 1/3 failed',
      );
      expect(
        InjectedMessage.extractSummary(_msg(batchComplete), en),
        'Subagent deleg_b1c2d3e4f5 · batch complete',
      );
      expect(
        InjectedMessage.extractSummary(_msg(singleComplete), en),
        'Subagent deleg_y · completed',
      );
    });

    test('摘要无 l10n 时回落英文（与其它 kind 同约定）', () {
      expect(
        InjectedMessage.extractSummary(_msg(singleComplete)),
        'Subagent deleg_y · completed',
      );
    });

    test('委派 id 超 22 字符按「前 10…后 8」省略', () {
      const long = '[ASYNC DELEGATION COMPLETE — deleg_1234567890abcdefghij]';
      expect(
        InjectedMessage.extractSummary(_msg(long), zh),
        '委派任务 deleg_1234…cdefghij · 已完成',
      );
    });

    test('首行不符合实产模板时不崩、回退截断（容错）', () {
      const broken = '[ASYNC DELEGATION TASK FAILED]\n无 id 与分隔符的畸形首行';
      expect(InjectedMessage.isInjectedNotice(_msg(broken)), isTrue);
      expect(
        InjectedMessage.classify(_msg(broken)),
        InjectedNoticeKind.subagentTaskFailed,
      );
      expect(
        InjectedMessage.extractSummary(_msg(broken), zh),
        'ASYNC DELEGATION TASK FAILED',
      );
    });

    test('容错：连字符 / en dash 分隔符同样识别', () {
      expect(
        InjectedMessage.extractSummary(
          _msg('[ASYNC DELEGATION COMPLETE - deleg_hyphen]'),
          zh,
        ),
        '委派任务 deleg_hyphen · 已完成',
      );
      expect(
        InjectedMessage.extractSummary(
          _msg('[ASYNC DELEGATION COMPLETE \u2013 deleg_en]'),
          zh,
        ),
        '委派任务 deleg_en · 已完成',
      );
    });

    test('防回归：[IMPORTANT: N background subagent delegations completed] 仍归 subagentAggregated', () {
      expect(
        InjectedMessage.classify(
          _msg('[IMPORTANT: 2 background subagent delegations completed — foo'),
        ),
        InjectedNoticeKind.subagentAggregated,
      );
    });

    test('displayTitle：委派任务 / Subagent', () {
      expect(
        InjectedNoticeKind.subagentTaskFailed.displayTitleWithL10n(zh),
        '委派任务',
      );
      expect(
        InjectedNoticeKind.subagentBatchComplete.displayTitleWithL10n(en),
        'Subagent',
      );
      expect(
        InjectedNoticeKind.subagentComplete.displayTitleWithL10n(null),
        'Subagent',
      );
    });
  });
}
