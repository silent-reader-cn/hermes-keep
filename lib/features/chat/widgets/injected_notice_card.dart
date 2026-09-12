import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;

import '../../../app/theme/light_surfaces.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/utils/injected_message.dart';
import '../../../l10n/app_localizations.dart';

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
    final bg = LightSurfaces.resolve(
      context,
      LightSurfaces.card,
      dark: CupertinoColors.secondarySystemBackground,
    );
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryLabel = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: separator),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Row(
                  children: [
                    Icon(_iconForKind(kind), size: 13, color: secondaryLabel),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.04 * 11,
                          color: secondaryLabel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ToggleButton(
                      label: expanded
                          ? l10n.injectedNoticeHideOutput
                          : l10n.injectedNoticeShowOutput,
                      onPressed: onToggle,
                      separator: separator,
                      textColor: secondaryLabel,
                    ),
                  ],
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: codeBg,
                      border: Border.all(color: separator),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          message.content ?? '',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['MiSans'],
                            fontSize: 12,
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
      case InjectedNoticeKind.none:
        return CupertinoIcons.command;
    }
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.onPressed,
    required this.separator,
    required this.textColor,
  });

  final String label;
  final VoidCallback onPressed;
  final Color separator;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: separator),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: textColor)),
      ),
    );
  }
}
