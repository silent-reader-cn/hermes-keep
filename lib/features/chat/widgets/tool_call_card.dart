import 'package:flutter/cupertino.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../core/models/tool_call.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/chat_models.dart';

/// 单条工具调用卡片（chat_spec.md §3.5 ToolCallCardView）。
///
/// 内层二次折叠：标题行始终可见，点击展开 arguments / result。
/// 默认收起（collapsed），不管 live 还是 completed。
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({super.key, required this.call});

  final ToolCall call;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  String get _storageKey {
    final call = widget.call;
    if (call.id.isNotEmpty && !call.id.startsWith('uuid-')) {
      return 'tool-call-expanded-${call.id}';
    }
    // 兜底策略：当 call.id 为空或以 'uuid-' 为前缀时（常见于测试/临时 mock 或旧前缀）：
    // 1. 若仍具备非空 call.id（如 'uuid-xxx'），附加 displayName 与 call.id 作为标识；
    // 2. 若 call.id 完全为空，以 displayName 与 startedAt 时间戳组合兜底，
    // 保证在 _completeToolCall 等流式生命周期内（startedAt 保持一致）仍可准确恢复状态。
    if (call.id.isNotEmpty) {
      return 'tool-call-expanded-uuid-${call.displayName}-${call.id}';
    }
    return 'tool-call-expanded-fallback-${call.displayName}-${call.startedAt}';
  }

  void _syncExpandedFromStorage() {
    final key = _storageKey;
    final stored = PageStorage.maybeOf(context)
        ?.readState(context, identifier: key);
    if (stored is bool) {
      _expanded = stored;
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncExpandedFromStorage();
  }

  @override
  void didUpdateWidget(covariant ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.call.id != widget.call.id ||
        oldWidget.call.startedAt != widget.call.startedAt ||
        oldWidget.call.name != widget.call.name) {
      _syncExpandedFromStorage();
    }
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      final key = _storageKey;
      PageStorage.maybeOf(context)
          ?.writeState(context, _expanded, identifier: key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final call = widget.call;
    final content = ToolCallDisplayContent.of(call);
    final failed = call.isError == true;
    final running = !call.isCompleted;
    final accentColor = failed
        ? LightSurfaces.resolve(
            context,
            statusRedText.resolveFrom(context),
            dark: CupertinoColors.systemRed,
          )
        : running
        ? LightSurfaces.resolve(
            context,
            statusBlueText.resolveFrom(context),
            dark: CupertinoColors.activeBlue,
          )
        : LightSurfaces.resolve(
            context,
            statusGreenText.resolveFrom(context),
            dark: CupertinoColors.systemGreen,
          );
    final bgColor = failed
        ? CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.08)
        : running
        ? CupertinoColors.activeBlue
              .resolveFrom(context)
              .withValues(alpha: 0.08)
        : CupertinoColors.systemTeal
              .resolveFrom(context)
              .withValues(alpha: 0.08);

    final rawSummary = call.summary;
    final String? summary;
    if (rawSummary != null && rawSummary.isNotEmpty) {
      summary = rawSummary.length > 36
          ? '${rawSummary.substring(0, 33)}\u2026'
          : rawSummary;
    } else {
      summary = null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          failed
              ? LightSurfaces.tintError
              : running
              ? LightSurfaces.card
              : LightSurfaces.tintGreen,
          dark: bgColor,
        ),
        border: CupertinoTheme.brightnessOf(context) == Brightness.light
            ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleExpanded,
            child: Row(
              children: [
                if (running)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CupertinoActivityIndicator(
                      radius: 7,
                      color: LightSurfaces.resolve(
                        context,
                        statusBlueText.resolveFrom(context),
                        dark: CupertinoColors.activeBlue,
                      ),
                    ),
                  )
                else
                  Icon(
                    failed
                        ? CupertinoIcons.exclamationmark_triangle
                        : _toolIconFor(call.displayName),
                    size: 14,
                    color: accentColor,
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: l10n.localizeToolName(call.displayName),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                        if (summary != null)
                          TextSpan(
                            text: ' \u2014 $summary',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: LightSurfaces.resolve(
                                context,
                                LightSurfaces.textSecondary,
                                dark: CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (call.isCompleted && call.duration != null)
                  Text(
                    '${call.duration!.toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontSize: 11,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 12,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            if (content.arguments.isNotEmpty) ...[
              const SizedBox(height: 6),
              _MonospaceText(content.arguments),
            ],
            if (content.result.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: 1,
                  width: double.infinity,
                  child: _DividerLine(),
                ),
              ),
              _MonospaceText(content.result, monospaced: content.monospaced),
            ],
            // running 状态在 inner 展开时仍显示底部指示（提供文字语义）
            if (running) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CupertinoActivityIndicator(
                      radius: 6,
                      color: LightSurfaces.resolve(
                        context,
                        statusBlueText.resolveFrom(context),
                        dark: CupertinoColors.activeBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).runningIndicator,
                    style: TextStyle(
                      fontSize: 11,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // 没有可展开内容时不额外渲染（保持紧凑）
          ] else if (running) ...[
            // 收起态仍保留一行 running 提示，保证语义可见
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CupertinoActivityIndicator(
                    radius: 6,
                    color: LightSurfaces.resolve(
                      context,
                      statusBlueText.resolveFrom(context),
                      dark: CupertinoColors.activeBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).runningIndicator,
                  style: TextStyle(
                    fontSize: 11,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 主题自适应的 1px 分隔线（ColoredBox 不 resolve 动态色，自行解析）。
class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.divider,
        dark: CupertinoColors.systemGrey4,
      ),
    );
  }
}

class _MonospaceText extends StatelessWidget {
  const _MonospaceText(this.text, {this.monospaced = true});

  final String text;
  final bool monospaced;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontFamily: monospaced ? 'monospace' : null,
        color: CupertinoColors.label.resolveFrom(context),
        height: 1.35,
      ),
    );
  }
}

/// 工具调用分组卡（chat_spec.md §3.5："Activity: N tools"）。
///
/// 外层折叠 + 内层每个 ToolCallCard 二次折叠，默认全部收起（包括 live）。
class ToolCallGroupCard extends StatefulWidget {
  const ToolCallGroupCard({
    super.key,
    required this.group,
    this.hideThinking = false,
  });

  final ToolCallGroup group;

  /// 隐藏思考子卡行（设置「隐藏思考」开启时：think 行不渲染，仅工具行）。
  final bool hideThinking;

  @override
  State<ToolCallGroupCard> createState() => _ToolCallGroupCardState();
}

class _ToolCallGroupCardState extends State<ToolCallGroupCard> {
  bool _expanded = false;

  String get _storageKey {
    final group = widget.group;
    if (group.toolCalls.isNotEmpty) {
      final first = group.toolCalls.first;
      if (first.id.isNotEmpty && !first.id.startsWith('uuid-')) {
        return 'tool-${first.id}';
      }
    }
    return 'group-${group.anchorMessageID ?? group.id}';
  }

  void _syncExpandedFromStorage() {
    final key = _storageKey;
    final stored = PageStorage.maybeOf(context)
        ?.readState(context, identifier: 'tool-group-expanded-$key');
    if (stored is bool) {
      _expanded = stored;
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncExpandedFromStorage();
  }

  @override
  void didUpdateWidget(covariant ToolCallGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id ||
        oldWidget.group.anchorMessageID != widget.group.anchorMessageID) {
      _syncExpandedFromStorage();
    }
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      final key = _storageKey;
      PageStorage.maybeOf(
        context,
      )?.writeState(context, _expanded, identifier: 'tool-group-expanded-$key');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final group = widget.group;
    final failed = group.hasFailedTool;
    final running = !group.isComplete;
    final titleStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: CupertinoColors.label.resolveFrom(context),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // 动态色需显式 resolve：暗黑模式下不 resolve 会画成浅色亮块。
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.systemGrey6,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.systemGrey4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleExpanded,
            child: Row(
              children: [
                if (running)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CupertinoActivityIndicator(
                      radius: 7,
                      color: LightSurfaces.resolve(
                        context,
                        statusBlueText.resolveFrom(context),
                        dark: CupertinoColors.activeBlue,
                      ),
                    ),
                  )
                else
                  Icon(
                    failed
                        ? CupertinoIcons.exclamationmark_triangle_fill
                        : CupertinoIcons.checkmark_circle_fill,
                    size: 14,
                    color: failed
                        ? LightSurfaces.resolve(
                            context,
                            statusRedText.resolveFrom(context),
                            dark: CupertinoColors.systemRed,
                          )
                        : LightSurfaces.resolve(
                            context,
                            statusGreenText.resolveFrom(context),
                            dark: CupertinoColors.systemGreen,
                          ),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final title = _adaptiveActivityTitle(
                        group: group,
                        l10n: l10n,
                        maxWidth: constraints.maxWidth,
                        style: titleStyle,
                        textScaler: MediaQuery.textScalerOf(context),
                        textDirection:
                            Directionality.maybeOf(context) ??
                            TextDirection.ltr,
                      );
                      return Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      );
                    },
                  ),
                ),
                if (failed)
                  Text(
                    l10n.toolFailedStatus,
                    style: TextStyle(
                      fontSize: 11,
                      color: LightSurfaces.resolve(
                        context,
                        statusRedText.resolveFrom(context),
                        dark: CupertinoColors.systemRed,
                      ),
                    ),
                  )
                else if (running)
                  Text(
                    l10n.toolRunningStatus,
                    style: TextStyle(
                      fontSize: 11,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 12,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            for (final call in group.toolCalls) ...[
              // 思考子卡行（伪工具）以思考样式渲染，与工具行同属时间线。
              if (call.isThinking)
                (widget.hideThinking
                    ? const SizedBox.shrink()
                    : _ThinkingRow(call: call))
              else
                ToolCallCard(call: call),
              if (call != group.toolCalls.last) const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }
}

/// 根据可用宽度自适应计算分组卡片标题。
String _adaptiveActivityTitle({
  required ToolCallGroup group,
  required AppLocalizations l10n,
  required double maxWidth,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  if (group.toolCalls.isEmpty) return l10n.noTools;

  final counts = <String, int>{};
  final initialIndex = <String, int>{};
  for (var i = 0; i < group.toolCalls.length; i++) {
    // 思考子卡行也计入标题统计（「思考 ×N, 终端 ×M」）；纯思考卡标题即「思考 ×N」。
    // 第三方 MCP 工具（mcp__*）聚合层统一归为「外部工具 ×N」。
    final call = group.toolCalls[i];
    final name = call.isThinking
        ? l10n.thinkingLabel
        : call.isExternalMcp
            ? l10n.externalToolsLabel
            : l10n.localizeToolName(call.displayName);
    initialIndex.putIfAbsent(name, () => initialIndex.length);
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final cmp = b.value.compareTo(a.value);
      if (cmp != 0) return cmp;
      return (initialIndex[a.key] ?? 0).compareTo(initialIndex[b.key] ?? 0);
    });

  if (entries.isEmpty) return l10n.noTools;

  bool fits(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return painter.width <= maxWidth;
  }

  // 循环尝试加入下一个 entry 的 "name ×count" 到 visible 列表
  final visible = <String>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final itemText = '${entry.key} \u00D7${entry.value}';
    final candidateVisible = [...visible, itemText];
    final remaining = entries.length - candidateVisible.length;
    final candidateString = remaining > 0
        ? '${candidateVisible.join(', ')} \u2026'
        : candidateVisible.join(', ');

    if (fits(candidateString)) {
      visible.add(itemText);
    } else {
      break;
    }
  }

  if (visible.isNotEmpty) {
    final remaining = entries.length - visible.length;
    if (remaining > 0) {
      return '${visible.join(', ')} \u2026';
    }
    return visible.join(', ');
  }

  // 兜底：若首个 entry 就超宽，则只显示首个 entry 的 name（不含 ×count）+ " …"
  return '${entries.first.key} \u2026';
}

/// 工具名 → 语义图标映射（告别统一扳手，按工具语义匹配 Icon）。
///
/// 覆盖 Hermes 内置工具与常见别名；第三方 MCP 工具（mcp__*）用 [CupertinoIcons.cube]；
/// 其余未命中的工具回退 [CupertinoIcons.wrench]。
IconData _toolIconFor(String name) {
  final key = name.trim().toLowerCase();
  if (key.startsWith('mcp__')) return CupertinoIcons.cube;
  switch (key) {
    case 'thinking':
    case 'think':
    case 'reasoning':
      return CupertinoIcons.sparkles;
    case 'terminal':
    case 'exec':
    case 'shell':
    case 'bash':
    case 'cmd':
    case 'powershell':
    case 'zsh':
      return CupertinoIcons.chevron_left_slash_chevron_right;
    case 'execute_code':
    case 'exec_code':
    case 'code_execution':
    case 'run_code':
    case 'code':
      return CupertinoIcons.chevron_left_slash_chevron_right;
    case 'read':
    case 'read_file':
    case 'readfile':
    case 'view_file':
    case 'viewfile':
    case 'cat':
      return CupertinoIcons.doc_text;
    case 'write':
    case 'write_file':
    case 'writefile':
    case 'write_to_file':
    case 'create_file':
      return CupertinoIcons.pencil;
    case 'patch':
    case 'apply_patch':
    case 'applypatch':
    case 'edit_file':
    case 'editfile':
    case 'str_replace':
      return CupertinoIcons.wrench;
    case 'search_files':
    case 'file_search':
    case 'search':
    case 'grep':
    case 'grep_search':
    case 'grep_code':
    case 'ripgrep':
    case 'find':
    case 'find_by_name':
      return CupertinoIcons.search;
    case 'glob':
    case 'list_dir':
    case 'listdir':
    case 'list_files':
    case 'listdir_files':
      return CupertinoIcons.folder;
    case 'web_search':
    case 'websearch':
      return CupertinoIcons.globe;
    case 'web_extract':
    case 'webextract':
    case 'web_fetch':
    case 'webfetch':
    case 'read_url_content':
    case 'fetch_web':
      return CupertinoIcons.arrow_down_circle;
    case 'memory':
    case 'memory_write':
    case 'memory_read':
    case 'mem0':
    case 'mem0_search':
    case 'mem0_add':
    case 'mem0_update':
    case 'mem0_delete':
      return CupertinoIcons.bookmark;
    case 'skill_view':
    case 'view_skill':
    case 'skill':
    case 'skill_manage':
    case 'skillmanage':
    case 'skills_list':
    case 'list_skills':
      return CupertinoIcons.book;
    case 'cronjob':
    case 'cron_job':
    case 'cron':
      return CupertinoIcons.clock;
    case 'delegate_task':
    case 'delegate-task':
    case 'delegatetask':
    case 'invoke_subagent':
    case 'subagent_progress':
    case 'subagentprogress':
    case 'subagent':
    case 'sub_agent':
    case 'agent':
      return CupertinoIcons.person_2;
    case 'send_message':
    case 'sendmessage':
    case 'send_msg':
      return CupertinoIcons.paperplane;
    case 'browser':
    case 'browse':
    case 'browser_navigate':
    case 'browsernavigate':
    case 'browser_exec':
    case 'browserexec':
    case 'browser_action':
      return CupertinoIcons.compass;
    case 'vision_analyze':
    case 'visionanalyze':
    case 'vision':
    case 'image_analyze':
      return CupertinoIcons.eye;
    case 'image_generate':
    case 'image_gen':
      return CupertinoIcons.photo;
    case 'video_generate':
    case 'video_gen':
      return CupertinoIcons.film;
    case 'video_analyze':
      return CupertinoIcons.videocam;
    case 'text_to_speech':
    case 'tts':
    case 'tts_speak':
      return CupertinoIcons.speaker_2;
    case 'process':
    case 'proc':
    case 'background_process':
    case 'process_manage':
    case 'process-manage':
      return CupertinoIcons.gear_alt;
    case 'kanban':
    case 'kanban_list':
    case 'kanban_create':
    case 'kanban_show':
    case 'kanban_complete':
    case 'kanban_comment':
    case 'kanban_heartbeat':
      return CupertinoIcons.square_grid_2x2;
    case 'clarify':
    case 'clarification':
      return CupertinoIcons.question_circle;
    case 'session_search':
    case 'search_sessions':
      return CupertinoIcons.time;
    case 'todo':
    case 'task':
    case 'todo_write':
    case 'todo_list':
    case 'todo-list':
    case 'list_todos':
    case 'write_todo':
    case 'todo_update':
      return CupertinoIcons.list_bullet;
    case 'tool_search':
    case 'tool_describe':
    case 'tool_call':
    case 'invoke_tool':
      return CupertinoIcons.square_stack_3d_up;
    case 'x_search':
      return CupertinoIcons.search;
    default:
      return CupertinoIcons.wrench;
  }
}

/// 思考子卡行（工具卡展开区内的思考条目）。
class _ThinkingRow extends StatefulWidget {
  const _ThinkingRow({required this.call});

  final ToolCall call;

  @override
  State<_ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<_ThinkingRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = widget.call.thinking?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final summary = text.replaceAll(RegExp(r'\s+'), ' ');
    final preview = summary.length > 80
        ? '${summary.substring(0, 80)}…'
        : summary;
    final secondary = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    // 与工具行同构的「卡式子行」：淡紫底块 + 圆角 8（思考专属色调），
    // 内部保持 ReasoningBlock 时代的标题/预览/展开交互。
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintClarification,
          dark: CupertinoColors.systemPurple
              .resolveFrom(context)
              .withValues(alpha: 0.08),
        ),
        border: CupertinoTheme.brightnessOf(context) == Brightness.light
            ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.sparkles,
                  size: 14,
                  color: CupertinoColors.systemPurple.resolveFrom(context),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.thinkingLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 12,
                  color: secondary,
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}
