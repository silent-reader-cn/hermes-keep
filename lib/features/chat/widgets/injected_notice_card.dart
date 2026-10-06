import 'package:hermes_ui/app/theme/typography_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/utils/injected_message.dart';
import '../../../l10n/app_localizations.dart';
import 'chat_text_selection.dart';

/// Agent injected notice fold card (spec §3.1).
///
/// Visual baseline mirrors `D:\hermes-webui\static\style.css:2330`
/// `.process-notice-*` (outer border + radius 8 + secondarySystemBackground,
/// header row with icon + single-line ellipsis title + toggle button,
/// body bordered code block max 400 scrollable).
class InjectedNoticeCard extends StatelessWidget {
  const InjectedNoticeCard({
    super.key,
    required this.message,
    required this.expanded,
    required this.onToggle,
  });

  final ChatMessage message;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = InjectedMessage.extractSummary(message, l10n);
    final kind = InjectedMessage.classify(message);

    final separator = LightSurfaces.resolve(
      context,
      LightSurfaces.cardBorder,
      dark: CupertinoColors.separator,
    );
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryLabel = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    // 失败态委派告警复用工具卡同一套红（`tool_call_card.dart`：statusRedText +
    // tintError），让「兄弟还在跑、这个已经死了」在滚动里一眼可辨；
    // 其余类型维持淡色中性（spec §3.2「不为每类另起一套」）。
    final failed = kind == InjectedNoticeKind.subagentTaskFailed;
    final accent = failed
        ? LightSurfaces.resolve(
            context,
            statusRedText.resolveFrom(context),
            dark: CupertinoColors.systemRed,
          )
        : secondaryLabel;
    final bg = LightSurfaces.resolve(
      context,
      failed ? LightSurfaces.tintError : LightSurfaces.card,
      dark: failed
          ? CupertinoColors.systemRed
                .resolveFrom(context)
                .withValues(alpha: 0.08)
          : CupertinoColors.secondarySystemBackground,
    );
    final codeBg = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: CupertinoColors.systemGrey6,
    );

    return Semantics(
      button: true,
      label: summary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Container(
          // 内距 / 圆角对齐工具聚合卡（`tool_call_card.dart:441-449`）
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: separator),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: GestureDetector(
                  // 命中区对齐工具聚合卡（`tool_call_card.dart:461-463`）：整行可点，
                  // 而非只有尾随那枚 12px chevron 可点。
                  // 语义层由外层 `Semantics(button:/label:)` 统一提供，这里排除自身
                  // 节点，避免读屏把同一张卡读成两个可点节点。
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: onToggle,
                  child: Row(
                    children: [
                      // 图标 / 字号 / 字重 / 尾随 chevron 逐项对齐工具聚合卡
                      // （`tool_call_card.dart:480-496 / 511-516 / 545-549`）。
                      Icon(_iconForKind(kind), size: 14, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        // 标题是外层 `Semantics.label` 的大写副本；排除自身语义节点，
                        // 否则读屏会把同一句话读两遍（实测合并成 `原大小写\n大写`）。
                        child: ExcludeSemantics(
                          child: Text(
                            // 大写是这一族（系统注入通知）的刻意残留差异：
                            // 与工具卡的句式标题区分开，但字级/字重已同档。
                            summary.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kFontCaption,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        expanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 12,
                        color: secondaryLabel,
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Padding(
                  // 展开体与头部的间距对齐聚合卡展开体（`tool_call_card.dart:560`）。
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: codeBg,
                      border: Border.all(color: separator),
                      // 内层子块圆角对齐工具卡内层子卡（`tool_call_card.dart:141`）。
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          message.content ?? '',
                          // #81：右键不叠原生「全选」工具条。
                          contextMenuBuilder: chatMessageTextContextMenu,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['MiSans'],
                            fontSize: kFontCode,
                            height: 1.5,
                            color: labelColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForKind(InjectedNoticeKind kind) {
    switch (kind) {
      case InjectedNoticeKind.backgroundProcess:
      case InjectedNoticeKind.backgroundProcessWatch:
      case InjectedNoticeKind.backgroundProcessAggregated:
      case InjectedNoticeKind.subagentAggregated:
      case InjectedNoticeKind.overflow:
        return CupertinoIcons.command;
      case InjectedNoticeKind.subagentTaskFailed:
        return CupertinoIcons.exclamationmark_triangle;
      case InjectedNoticeKind.subagentBatchComplete:
      case InjectedNoticeKind.subagentComplete:
        return CupertinoIcons.command;
      case InjectedNoticeKind.skill:
      case InjectedNoticeKind.skillBundle:
      case InjectedNoticeKind.skillAutoLoaded:
        return CupertinoIcons.hammer;
      case InjectedNoticeKind.cron:
        return CupertinoIcons.clock;
      case InjectedNoticeKind.mcp:
        return CupertinoIcons.cube_box;
      case InjectedNoticeKind.continuationNetworkCut:
      case InjectedNoticeKind.continuationOutputLimit:
      case InjectedNoticeKind.continuationToolTooLarge:
        return CupertinoIcons.arrow_2_circlepath;
      case InjectedNoticeKind.codexNudge:
        return CupertinoIcons.lightbulb;
      case InjectedNoticeKind.gatewayRecovery:
      case InjectedNoticeKind.sessionReset:
      case InjectedNoticeKind.memoryRecall:
        return CupertinoIcons.info_circle;
      case InjectedNoticeKind.contextCompaction:
        return CupertinoIcons.rectangle_compress_vertical;
      case InjectedNoticeKind.priorContext:
        return CupertinoIcons.doc_text;
      case InjectedNoticeKind.activeTaskList:
        return CupertinoIcons.list_bullet;
      case InjectedNoticeKind.planningState:
        return CupertinoIcons.flag;
      case InjectedNoticeKind.outOfBandMessage:
        return CupertinoIcons.bubble_left;
      case InjectedNoticeKind.cronjobResponse:
        return CupertinoIcons.tray_full;
      case InjectedNoticeKind.none:
        return CupertinoIcons.command;
    }
  }
}
