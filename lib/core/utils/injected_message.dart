import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../models/chat_message.dart';

/// Agent 代发注入消息分类器（spec §2）。
///
/// 对齐 `D:\hermes-webui\static\ui.js` 的 `_formatProcessNoticeSummary`
/// 并扩展到全量 17 类注入消息。所有 [RegExp] 均为预编译的 `static const`，
/// 禁止在 `build` 中编译。
enum InjectedNoticeKind {
  backgroundProcess,
  backgroundProcessWatch,
  backgroundProcessAggregated,
  subagentAggregated,

  /// 异步委派：`[ASYNC DELEGATION TASK FAILED — {id}, task i/n]`（兄弟仍在跑时的提前告警）。
  subagentTaskFailed,

  /// 异步委派：`[ASYNC DELEGATION BATCH COMPLETE — {id}]`（扇出批量收口）。
  subagentBatchComplete,

  /// 异步委派：`[ASYNC DELEGATION COMPLETE — {id}]`（单个子代理收口）。
  subagentComplete,
  overflow,
  cron,
  skill,
  skillBundle,
  skillAutoLoaded,
  mcp,
  continuationNetworkCut,
  continuationOutputLimit,
  continuationToolTooLarge,
  codexNudge,
  gatewayRecovery,
  sessionReset,
  memoryRecall,
  none,
}

/// 分类器与摘要工具（纯字符串操作）。
class InjectedMessage {
  const InjectedMessage._();

  // ---------------------------------------------------------------------------
  // 预编译正则（spec §2.3，对齐 ui.js _formatProcessNoticeSummary）
  // ---------------------------------------------------------------------------
  static final RegExp _sidRegExp = RegExp(
    r'Background process\s+(\S+)',
    caseSensitive: false,
  );
  static final RegExp _trailingPunctRegExp = RegExp(r'[.:,;)]+$');
  static final RegExp _exitCodeParenRegExp = RegExp(
    r'\(exit[_\s]*code\s*[:=]?\s*(-?\d+)\)',
    caseSensitive: false,
  );
  static final RegExp _exitCodeBareRegExp = RegExp(
    r'exit[_\s]*code\s*[:=]?\s*(-?\d+)',
    caseSensitive: false,
  );
  static final RegExp _withCodeRegExp = RegExp(
    r'with\s+code\s+(-?\d+)',
    caseSensitive: false,
  );
  static final RegExp _skillNameRegExp = RegExp(r'"([^"]+)"');
  static final RegExp _importantPrefixRegExp = RegExp(
    r'^\[IMPORTANT:\s*',
    caseSensitive: false,
  );
  static final RegExp _systemPrefixRegExp = RegExp(
    r'^\[SYSTEM:\s*',
    caseSensitive: false,
  );
  static final RegExp _systemNotePrefixRegExp = RegExp(
    r'^\[SYSTEM NOTE:\s*',
    caseSensitive: false,
  );
  static final RegExp _trailingBracketRegExp = RegExp(r'\]\s*$');
  static final RegExp _fallbackStatusRegExp = RegExp(
    r'Background process(?:\s+\S+)?\s+(.+?)(?:\s*\(.*)?\.?$',
    caseSensitive: false,
  );

  // 新增 6+ 类型预编译（保持 build 零编译）
  static final RegExp _continuationNetworkRegExp = RegExp(
    r'previous response was cut off by a network error',
    caseSensitive: false,
  );
  static final RegExp _continuationOutputRegExp = RegExp(
    r'previous response was truncated by.*output',
    caseSensitive: false,
  );
  static final RegExp _continuationToolRegExp = RegExp(
    r'your previous tool call.*was too large',
    caseSensitive: false,
  );
  static final RegExp _codexReasoningRegExp = RegExp(
    r'contained only internal reasoning',
    caseSensitive: false,
  );
  static final RegExp _codexContinueRegExp = RegExp(
    r'continue now.*execute the required tool calls',
    caseSensitive: false,
  );
  static final RegExp _gatewayRecoveryRegExp = RegExp(
    r'previous turn was interrupted by.*gateway is now back online',
    caseSensitive: false,
  );
  static final RegExp _gatewayPendingRegExp = RegExp(
    r'a new message has arrived.*pending tool outputs',
    caseSensitive: false,
  );
  static final RegExp _sessionSuspendedRegExp = RegExp(
    r'previous session was stopped and suspended',
    caseSensitive: false,
  );
  static final RegExp _sessionDailyRegExp = RegExp(
    r'session was automatically reset by the daily schedule',
    caseSensitive: false,
  );
  static final RegExp _sessionResumeExpiredRegExp = RegExp(
    r'previous gateway session could not be recovered',
    caseSensitive: false,
  );
  static final RegExp _sessionExpiredRegExp = RegExp(
    r'previous session expired due to inactivity',
    caseSensitive: false,
  );
  static final RegExp _firstContactRegExp = RegExp(
    r"this is the user's very first message ever",
    caseSensitive: false,
  );
  static final RegExp _memoryRecallRegExp = RegExp(
    r'the following is recalled memory context',
    caseSensitive: false,
  );

  // 异步委派家族（producer-owned；`tools/process_registry_notifications.py`
  // `_format_task_failure_notice` / `_format_batch_delegation` / `_format_async_delegation`）。
  // 分隔符实产为 em dash `—`，历史/容错同时认 `-` 与 en dash。
  static final RegExp _asyncDelegationPrefixRegExp = RegExp(
    r'^\[\s*async delegation',
    caseSensitive: false,
  );
  static final RegExp _leadingBracketRegExp = RegExp(r'^\[\s*');
  static final RegExp _asyncTaskFailedRegExp = RegExp(
    r'^\[\s*ASYNC DELEGATION TASK FAILED\s*[-\u2014\u2013]+\s*(\S+?)\s*,?\s*task\s*(\d+)\s*/\s*(\d+)\s*\]',
    caseSensitive: false,
  );
  static final RegExp _asyncCompleteRegExp = RegExp(
    r'^\[\s*ASYNC DELEGATION\s+(?:BATCH\s+)?COMPLETE\s*[-\u2014\u2013]+\s*(\S+?)\s*\]',
    caseSensitive: false,
  );

  static const Set<String> _sidBlacklist = <String>{
    'completed',
    'failed',
    'terminated',
    'exited',
    'lost',
    'matched',
    'marked',
  };

  // ---------------------------------------------------------------------------
  // 检测入口（spec §2.2）
  // ---------------------------------------------------------------------------

  /// 是否为 agent 代发注入消息。
  ///
  /// 仅当 [ChatMessage.role] 为 `user` 或 `system` 且内容满足白名单前缀时
  /// 返回 `true`，避免误伤用户手打的 `[IMPORTANT: hello]`。
  static bool isInjectedNotice(ChatMessage message) {
    final String? role = message.role;
    if (role == null) return false;
    final String normalizedRole = role.trim().toLowerCase();
    if (normalizedRole != 'user' && normalizedRole != 'system') return false;
    final String? content = message.content;
    if (content == null) return false;
    if (content.trim().isEmpty) return false;
    return _isInjectedNoticeText(content);
  }

  static bool _isInjectedNoticeText(String text) {
    final String t = text.trimLeft();
    if (t.isEmpty) return false;
    final String lower = t.toLowerCase();
    // 记忆上下文可被 <memory-context> 包裹，不一定以 [ 开头
    if (_memoryRecallRegExp.hasMatch(lower)) return true;
    if (lower.contains('recalled memory context')) return true;
    // 裸提示（无 [System: 包裹的 dropped/empty nudge，极低误伤）
    if (lower.contains(
      'your previous turn indicated a tool call but none was included',
    )) {
      return true;
    }
    if (lower.contains(
      'you just executed tool calls but returned an empty response',
    )) {
      return true;
    }
    if (!t.startsWith('[')) {
      // 除记忆/裸 nudge 外，其余注入均以 [ 开头
      return false;
    }
    // 异步委派的三种形态均以 `[ASYNC DELEGATION` 整串前缀开口，且该前缀在
    // `context_compressor._synthetic_prefixes` 里同列（producer-owned 合成行），
    // 现实输入不可能手打 → 窄白名单直接收口，不参与关键词二次确认。
    if (_asyncDelegationPrefixRegExp.hasMatch(lower)) return true;
    if (lower.startsWith('[important: background process')) return true;
    if (lower.startsWith('[important: you are running as a scheduled cron')) {
      return true;
    }
    if (lower.startsWith('[important: the user has invoked the')) return true;
    if (lower.startsWith('[important: the "')) return true;
    if (lower.contains('background subagent')) return true;
    if (lower.startsWith('[important: mcp servers have been reloaded')) {
      return true;
    }
    if (lower.startsWith('[system: background process')) return true;
    // 全量 [System: / [System note: 白名单命中
    if (lower.startsWith('[system:') || lower.startsWith('[system note:')) {
      if (_continuationNetworkRegExp.hasMatch(lower) ||
          _continuationOutputRegExp.hasMatch(lower) ||
          _continuationToolRegExp.hasMatch(lower) ||
          _codexReasoningRegExp.hasMatch(lower) ||
          _codexContinueRegExp.hasMatch(lower) ||
          _gatewayRecoveryRegExp.hasMatch(lower) ||
          _gatewayPendingRegExp.hasMatch(lower) ||
          _sessionSuspendedRegExp.hasMatch(lower) ||
          _sessionDailyRegExp.hasMatch(lower) ||
          _sessionResumeExpiredRegExp.hasMatch(lower) ||
          _sessionExpiredRegExp.hasMatch(lower) ||
          _firstContactRegExp.hasMatch(lower) ||
          _memoryRecallRegExp.hasMatch(lower)) {
        return true;
      }
      if (lower.contains('was cut off by a network error') ||
          lower.contains('was truncated by the output') ||
          lower.contains('was truncated by output') ||
          (lower.contains('your previous tool call') &&
              lower.contains('was too large')) ||
          lower.contains('contained only internal reasoning') ||
          (lower.contains('continue now') &&
              lower.contains('execute the required tool calls')) ||
          lower.contains('previous turn was interrupted by') ||
          lower.contains('gateway is now back online') ||
          (lower.contains('a new message has arrived') &&
              lower.contains('pending tool outputs')) ||
          lower.contains('ignore those pending results') ||
          lower.contains('previous session was stopped') ||
          lower.contains('automatically reset by the daily schedule') ||
          lower.contains('could not be recovered after a restart') ||
          lower.contains('session expired due to inactivity') ||
          lower.contains('very first message ever') ||
          lower.contains('recalled memory context') ||
          lower.contains('was truncated by') ||
          lower.contains('was cut off by')) {
        return true;
      }
      // 未命中白名单的 [System: 视为用户手打，不折叠
      return false;
    }
    if (lower.startsWith('[important:')) {
      if (_containsAny(lower, const <String>[
        'background process',
        'background subagent',
        'subagent',
        'mcp servers',
        'cron job',
        'skill',
      ])) {
        return true;
      }
      return false;
    }
    return false;
  }

  static bool _containsAny(String lower, List<String> keywords) {
    for (final String k in keywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // 分类（spec §2.2）
  // ---------------------------------------------------------------------------

  /// 分类（未命中注入则返回 [InjectedNoticeKind.none]）。
  static InjectedNoticeKind classify(ChatMessage message) {
    if (!isInjectedNotice(message)) return InjectedNoticeKind.none;
    final String content = message.content ?? '';
    final String lower = content.trimLeft().toLowerCase();

    // 新增 6+ 类型优先（避免被 overflow 兜底吞掉）
    if (_continuationNetworkRegExp.hasMatch(lower) ||
        lower.contains('was cut off by a network error')) {
      return InjectedNoticeKind.continuationNetworkCut;
    }
    if (_continuationOutputRegExp.hasMatch(lower) ||
        (lower.contains('was truncated by') && lower.contains('output'))) {
      return InjectedNoticeKind.continuationOutputLimit;
    }
    if (_continuationToolRegExp.hasMatch(lower) ||
        (lower.contains('your previous tool call') &&
            lower.contains('was too large'))) {
      return InjectedNoticeKind.continuationToolTooLarge;
    }
    if (_codexReasoningRegExp.hasMatch(lower) ||
        _codexContinueRegExp.hasMatch(lower) ||
        lower.contains('contained only internal reasoning') ||
        (lower.contains('continue now') &&
            lower.contains('execute the required tool calls'))) {
      return InjectedNoticeKind.codexNudge;
    }
    if (_gatewayRecoveryRegExp.hasMatch(lower) ||
        _gatewayPendingRegExp.hasMatch(lower) ||
        lower.contains('gateway is now back online') ||
        lower.contains('previous turn was interrupted by') ||
        (lower.contains('a new message has arrived') &&
            lower.contains('pending tool outputs')) ||
        lower.contains('ignore those pending results')) {
      return InjectedNoticeKind.gatewayRecovery;
    }
    if (_sessionSuspendedRegExp.hasMatch(lower) ||
        _sessionDailyRegExp.hasMatch(lower) ||
        _sessionResumeExpiredRegExp.hasMatch(lower) ||
        _sessionExpiredRegExp.hasMatch(lower) ||
        _firstContactRegExp.hasMatch(lower) ||
        lower.contains('previous session was stopped and suspended') ||
        lower.contains('automatically reset by the daily schedule') ||
        lower.contains('could not be recovered after a restart') ||
        lower.contains('session expired due to inactivity') ||
        lower.contains('very first message ever')) {
      return InjectedNoticeKind.sessionReset;
    }
    if (_memoryRecallRegExp.hasMatch(lower) ||
        lower.contains('recalled memory context')) {
      return InjectedNoticeKind.memoryRecall;
    }
    // 裸 nudge（无 [ 前缀）也归 codex
    if (lower.contains(
          'your previous turn indicated a tool call but none was included',
        ) ||
        lower.contains(
          'you just executed tool calls but returned an empty response',
        )) {
      return InjectedNoticeKind.codexNudge;
    }

    // 异步委派家族：必须在 `background subagent` 兜底之前判，否则
    // `[ASYNC DELEGATION COMPLETE …]` 的引导句（"A background subagent you
    // dispatched earlier…"）会把它吞进 subagentAggregated。
    if (_asyncDelegationPrefixRegExp.hasMatch(lower)) {
      if (lower.startsWith('[async delegation task failed')) {
        return InjectedNoticeKind.subagentTaskFailed;
      }
      if (lower.startsWith('[async delegation batch complete')) {
        return InjectedNoticeKind.subagentBatchComplete;
      }
      return InjectedNoticeKind.subagentComplete;
    }

    if (lower.contains('background subagent delegations completed') ||
        lower.contains('background subagent')) {
      return InjectedNoticeKind.subagentAggregated;
    }
    if (lower.contains('background processes completed')) {
      return InjectedNoticeKind.backgroundProcessAggregated;
    }
    if (lower.contains('matched watch pattern')) {
      return InjectedNoticeKind.backgroundProcessWatch;
    }
    if (lower.contains('background process')) {
      if (lower.contains('overflow') ||
          lower.contains('watch_disabled') ||
          lower.contains('watch disabled')) {
        return InjectedNoticeKind.overflow;
      }
      return InjectedNoticeKind.backgroundProcess;
    }
    if (lower.contains('you are running as a scheduled cron')) {
      return InjectedNoticeKind.cron;
    }
    if (lower.contains('skill bundle')) {
      return InjectedNoticeKind.skillBundle;
    }
    if (lower.contains('skill is auto-loaded') ||
        lower.contains('skill is auto loaded')) {
      return InjectedNoticeKind.skillAutoLoaded;
    }
    if (lower.contains('the user has invoked the') && lower.contains('skill')) {
      return InjectedNoticeKind.skill;
    }
    if (lower.contains('mcp servers have been reloaded')) {
      return InjectedNoticeKind.mcp;
    }
    if (lower.contains('mcp servers') || lower.contains('mcp')) {
      if (lower.contains('mcp')) return InjectedNoticeKind.mcp;
    }
    if (lower.contains('cron job')) return InjectedNoticeKind.cron;
    if (lower.contains('skill')) return InjectedNoticeKind.skill;
    if (lower.contains('overflow') ||
        lower.contains('truncated') ||
        lower.contains('watch_disabled')) {
      return InjectedNoticeKind.overflow;
    }
    return InjectedNoticeKind.overflow;
  }

  // ---------------------------------------------------------------------------
  // 摘要（spec §2.3，对齐 ui.js _formatProcessNoticeSummary）
  // ---------------------------------------------------------------------------

  /// 摘要标题提取。
  ///
  /// - Background process 单条/watch：`Background process {sid} · {status} (exit {code})`
  /// - 聚合：首行去前缀后截断 ≤64
  /// - Skill：`Skill · {skillName}`（引号内提取，bundle 追加 `bundle`）
  /// - Cron/MCP：固定标题
  /// - 新增 6+ 类型：本地化固定标题（网络中断续写/输出截断续写/网关已恢复/会话已重置等）
  /// - 兜底：首行去 `[IMPORTANT:` 前缀后 ≤48
  static String extractSummary(ChatMessage message, [AppLocalizations? l10n]) {
    final InjectedNoticeKind kind = classify(message);
    if (kind == InjectedNoticeKind.none) return '';
    final String raw = message.content ?? '';
    final String firstLine = raw.split('\n').first;
    if (firstLine.trim().isEmpty) return '';

    switch (kind) {
      case InjectedNoticeKind.backgroundProcess:
      case InjectedNoticeKind.backgroundProcessWatch:
        return _backgroundSummary(firstLine, l10n);
      case InjectedNoticeKind.backgroundProcessAggregated:
      case InjectedNoticeKind.subagentAggregated:
        return _firstLineStripped(firstLine, 64);
      case InjectedNoticeKind.subagentTaskFailed:
      case InjectedNoticeKind.subagentBatchComplete:
      case InjectedNoticeKind.subagentComplete:
        return _asyncDelegationSummary(firstLine, kind, l10n);
      case InjectedNoticeKind.cron:
        return _cronTitle(l10n);
      case InjectedNoticeKind.mcp:
        return _mcpTitle(l10n);
      case InjectedNoticeKind.skill:
      case InjectedNoticeKind.skillBundle:
      case InjectedNoticeKind.skillAutoLoaded:
        return _skillSummary(firstLine, kind, l10n);
      case InjectedNoticeKind.continuationNetworkCut:
        return _continuationNetworkTitle(l10n);
      case InjectedNoticeKind.continuationOutputLimit:
        return _continuationOutputTitle(l10n);
      case InjectedNoticeKind.continuationToolTooLarge:
        return _continuationToolTitle(l10n);
      case InjectedNoticeKind.codexNudge:
        return _codexTitle(l10n);
      case InjectedNoticeKind.gatewayRecovery:
        return _gatewayTitle(l10n);
      case InjectedNoticeKind.sessionReset:
        return _sessionResetTitle(l10n);
      case InjectedNoticeKind.memoryRecall:
        return _memoryTitle(l10n);
      case InjectedNoticeKind.overflow:
        return _firstLineStripped(firstLine, 48);
      case InjectedNoticeKind.none:
        return '';
    }
  }

  static String _backgroundSummary(String firstLine, AppLocalizations? l10n) {
    final String firstLineNoBracket = firstLine
        .replaceFirst(_importantPrefixRegExp, '')
        .replaceFirst(_trailingBracketRegExp, '');
    String sid = '';
    final RegExpMatch? sidMatch = _sidRegExp.firstMatch(firstLineNoBracket);
    if (sidMatch != null) {
      String rawSid = sidMatch.group(1) ?? '';
      rawSid = rawSid.replaceFirst(_trailingPunctRegExp, '');
      final String lowerToken = rawSid.toLowerCase();
      if (!_sidBlacklist.contains(lowerToken)) {
        sid = rawSid;
      }
    }

    String? exitCode;
    RegExpMatch? m = _exitCodeParenRegExp.firstMatch(firstLine);
    m ??= _exitCodeBareRegExp.firstMatch(firstLine);
    m ??= _withCodeRegExp.firstMatch(firstLine);
    if (m != null) exitCode = m.group(1);

    final String lower = firstLine.toLowerCase();
    late final String statusText;
    if (lower.contains('completed normally') || lower.contains('completed')) {
      statusText = _statusCompleted(l10n);
    } else if (lower.contains('failed to start')) {
      statusText = _statusFailedToStart(l10n);
    } else if (lower.contains('terminated by') ||
        lower.contains('terminated') ||
        lower.contains('killed')) {
      statusText = _statusTerminated(l10n);
    } else if (lower.contains('marked lost') || lower.contains('lost')) {
      statusText = _statusLost(l10n);
    } else if (lower.contains('matched watch pattern')) {
      statusText = _statusMatched(l10n);
    } else if (lower.contains('exited')) {
      statusText = _statusExited(l10n);
    } else {
      final RegExpMatch? sm = _fallbackStatusRegExp.firstMatch(
        firstLineNoBracket,
      );
      if (sm != null) {
        final String raw = (sm.group(1) ?? 'completed').trim();
        statusText = raw.isEmpty ? _statusCompleted(l10n) : raw;
      } else {
        statusText = _statusCompleted(l10n);
      }
    }

    final String baseTitle = _backgroundTitle(l10n);
    final String sidPart = sid.isEmpty ? '' : ' ${_elideMiddle(sid)}';
    final String exitPart = exitCode == null ? '' : ' (exit $exitCode)';
    return '$baseTitle$sidPart · $statusText$exitPart';
  }

  /// 异步委派卡摘要：`<别名> <委派 id> · <状态>`（对齐后台进程卡的
  /// `<类型> <sid> · <状态 (exit n)>` 骨架）。
  static String _asyncDelegationSummary(
    String firstLine,
    InjectedNoticeKind kind,
    AppLocalizations? l10n,
  ) {
    final String? id = _asyncDelegationId(firstLine, kind);
    if (id == null) {
      // 畸形首行（无 id/分隔符）兜底：`_firstLineStripped` 只认 [IMPORTANT:/[SYSTEM:
      // 前缀，对本族会留下一个孤立 `[`，这里补一次去括号。
      return _firstLineStripped(
        firstLine,
        64,
      ).replaceFirst(_leadingBracketRegExp, '');
    }

    final String label = _subagentLabel(l10n);
    final String head = '$label ${_elideMiddle(id)}';

    if (kind == InjectedNoticeKind.subagentTaskFailed) {
      final RegExpMatch? m = _asyncTaskFailedRegExp.firstMatch(firstLine);
      final String index = m?.group(2) ?? '';
      final String total = m?.group(3) ?? '';
      if (index.isNotEmpty && total.isNotEmpty) {
        return '$head · ${_taskFailedText(l10n, index, total)}';
      }
      return '$head · ${_statusTaskFailed(l10n)}';
    }
    if (kind == InjectedNoticeKind.subagentBatchComplete) {
      return '$head · ${_statusBatchComplete(l10n)}';
    }
    return '$head · ${_statusCompleted(l10n)}';
  }

  /// 提取委派 id；首行不符合该 kind 的实产模板时返回 `null`（调用方回退截断）。
  static String? _asyncDelegationId(String firstLine, InjectedNoticeKind kind) {
    final RegExpMatch? m = kind == InjectedNoticeKind.subagentTaskFailed
        ? _asyncTaskFailedRegExp.firstMatch(firstLine)
        : _asyncCompleteRegExp.firstMatch(firstLine);
    final String id = (m?.group(1) ?? '').trim();
    return id.isEmpty ? null : id;
  }

  /// 长 id 中段省略（与后台进程 sid 同一规则，便于两族卡片视觉对齐）。
  static String _elideMiddle(String id) => id.length > 22
      ? '${id.substring(0, 10)}…${id.substring(id.length - 8)}'
      : id;

  static String _skillSummary(
    String firstLine,
    InjectedNoticeKind kind,
    AppLocalizations? l10n,
  ) {
    final RegExpMatch? m = _skillNameRegExp.firstMatch(firstLine);
    final String? name = m?.group(1)?.trim();
    final String skillLabel = _skillLabel(l10n);
    if (name != null && name.isNotEmpty) {
      final String suffix = kind == InjectedNoticeKind.skillBundle
          ? ' bundle'
          : '';
      return '$skillLabel · $name$suffix';
    }
    return _firstLineStripped(firstLine, 64);
  }

  static String _firstLineStripped(String firstLine, int limit) {
    String t = firstLine.trimLeft();
    t = t.replaceFirst(_importantPrefixRegExp, '');
    t = t.replaceFirst(_systemPrefixRegExp, '');
    t = t.replaceFirst(_systemNotePrefixRegExp, '');
    t = t.replaceFirst(_trailingBracketRegExp, '');
    t = t.trim();
    if (t.length > limit) {
      t = '${t.substring(0, limit).trimRight()}…';
    }
    return t;
  }

  static String _backgroundTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Background process';
    return l10n.isEnglish ? 'Background process' : '后台进程';
  }

  static String _skillLabel(AppLocalizations? l10n) {
    if (l10n == null) return 'Skill';
    return l10n.isEnglish ? 'Skill' : '技能';
  }

  static String _cronTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Scheduled task';
    return l10n.isEnglish ? 'Scheduled task' : '定时任务';
  }

  static String _mcpTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'MCP servers reloaded';
    return l10n.isEnglish ? 'MCP servers reloaded' : 'MCP 服务已重载';
  }

  static String _continuationNetworkTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Continue — network error';
    return l10n.isEnglish ? 'Continue — network error' : '网络中断续写';
  }

  static String _continuationOutputTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Continue — output limit';
    return l10n.isEnglish ? 'Continue — output limit' : '输出截断续写';
  }

  static String _continuationToolTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Continue — tool too large';
    return l10n.isEnglish ? 'Continue — tool too large' : '工具调用过大续写';
  }

  static String _codexTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Continue execution';
    return l10n.isEnglish ? 'Continue execution' : '继续执行';
  }

  static String _gatewayTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Gateway recovered';
    return l10n.isEnglish ? 'Gateway recovered' : '网关已恢复';
  }

  static String _sessionResetTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Session reset';
    return l10n.isEnglish ? 'Session reset' : '会话已重置';
  }

  static String _memoryTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Memory recall';
    return l10n.isEnglish ? 'Memory recall' : '记忆上下文';
  }

  static String _statusCompleted(AppLocalizations? l10n) {
    if (l10n == null) return 'completed';
    return l10n.isEnglish ? 'completed' : '已完成';
  }

  static String _statusFailedToStart(AppLocalizations? l10n) {
    if (l10n == null) return 'failed to start';
    return l10n.isEnglish ? 'failed to start' : '启动失败';
  }

  static String _statusTerminated(AppLocalizations? l10n) {
    if (l10n == null) return 'terminated';
    return l10n.isEnglish ? 'terminated' : '已终止';
  }

  static String _statusLost(AppLocalizations? l10n) {
    if (l10n == null) return 'lost';
    return l10n.isEnglish ? 'lost' : '已丢失';
  }

  static String _statusMatched(AppLocalizations? l10n) {
    if (l10n == null) return 'matched';
    return l10n.isEnglish ? 'matched' : '已匹配';
  }

  static String _statusExited(AppLocalizations? l10n) {
    if (l10n == null) return 'exited';
    return l10n.isEnglish ? 'exited' : '已退出';
  }

  static String _subagentLabel(AppLocalizations? l10n) {
    if (l10n == null) return 'Subagent';
    return l10n.isEnglish ? 'Subagent' : '委派任务';
  }

  static String _statusTaskFailed(AppLocalizations? l10n) {
    if (l10n == null) return 'task failed';
    return l10n.isEnglish ? 'task failed' : '任务失败';
  }

  static String _statusBatchComplete(AppLocalizations? l10n) {
    if (l10n == null) return 'batch complete';
    return l10n.isEnglish ? 'batch complete' : '批次完成';
  }

  static String _taskFailedText(
    AppLocalizations? l10n,
    String index,
    String total,
  ) {
    if (l10n == null) return 'task $index/$total failed';
    return l10n.isEnglish ? 'task $index/$total failed' : '任务 $index/$total 失败';
  }
}

/// 是否为注入通知（转发至 [InjectedMessage.isInjectedNotice]）。
bool isInjectedNotice(ChatMessage message) =>
    InjectedMessage.isInjectedNotice(message);

/// 分类（转发至 [InjectedMessage.classify]）。
InjectedNoticeKind classify(ChatMessage message) =>
    InjectedMessage.classify(message);

/// 摘要（转发至 [InjectedMessage.extractSummary]）。
String extractSummary(ChatMessage message, [AppLocalizations? l10n]) =>
    InjectedMessage.extractSummary(message, l10n);

/// [InjectedNoticeKind] 展示标题扩展。
extension InjectedNoticeKindDisplay on InjectedNoticeKind {
  /// 基于 [BuildContext] 的本地化标题（优先走 [AppLocalizations]）。
  String displayTitle(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return displayTitleWithL10n(l10n);
  }

  /// 基于可选 [AppLocalizations] 的标题（便于测试与非 Widget 调用）。
  String displayTitleWithL10n([AppLocalizations? l10n]) {
    switch (this) {
      case InjectedNoticeKind.backgroundProcess:
      case InjectedNoticeKind.backgroundProcessWatch:
      case InjectedNoticeKind.backgroundProcessAggregated:
      case InjectedNoticeKind.subagentAggregated:
        if (l10n == null) return 'Background process';
        return l10n.isEnglish ? 'Background process' : '后台进程';
      case InjectedNoticeKind.subagentTaskFailed:
      case InjectedNoticeKind.subagentBatchComplete:
      case InjectedNoticeKind.subagentComplete:
        if (l10n == null) return 'Subagent';
        return l10n.isEnglish ? 'Subagent' : '委派任务';
      case InjectedNoticeKind.cron:
        if (l10n == null) return 'Scheduled task';
        return l10n.isEnglish ? 'Scheduled task' : '定时任务';
      case InjectedNoticeKind.skill:
      case InjectedNoticeKind.skillBundle:
      case InjectedNoticeKind.skillAutoLoaded:
        if (l10n == null) return 'Skill';
        return l10n.isEnglish ? 'Skill' : '技能';
      case InjectedNoticeKind.mcp:
        if (l10n == null) return 'MCP';
        return l10n.isEnglish ? 'MCP' : 'MCP';
      case InjectedNoticeKind.continuationNetworkCut:
        if (l10n == null) return 'Continue — network error';
        return l10n.isEnglish ? 'Continue — network error' : '网络中断续写';
      case InjectedNoticeKind.continuationOutputLimit:
        if (l10n == null) return 'Continue — output limit';
        return l10n.isEnglish ? 'Continue — output limit' : '输出截断续写';
      case InjectedNoticeKind.continuationToolTooLarge:
        if (l10n == null) return 'Continue — tool too large';
        return l10n.isEnglish ? 'Continue — tool too large' : '工具调用过大续写';
      case InjectedNoticeKind.codexNudge:
        if (l10n == null) return 'Continue execution';
        return l10n.isEnglish ? 'Continue execution' : '继续执行';
      case InjectedNoticeKind.gatewayRecovery:
        if (l10n == null) return 'Gateway recovered';
        return l10n.isEnglish ? 'Gateway recovered' : '网关已恢复';
      case InjectedNoticeKind.sessionReset:
        if (l10n == null) return 'Session reset';
        return l10n.isEnglish ? 'Session reset' : '会话已重置';
      case InjectedNoticeKind.memoryRecall:
        if (l10n == null) return 'Memory recall';
        return l10n.isEnglish ? 'Memory recall' : '记忆上下文';
      case InjectedNoticeKind.overflow:
        if (l10n == null) return 'Notice';
        return l10n.isEnglish ? 'Notice' : '提示';
      case InjectedNoticeKind.none:
        return '';
    }
  }
}
