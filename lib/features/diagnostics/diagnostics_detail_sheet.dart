import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../l10n/app_localizations.dart';
import 'diagnostics_models.dart';

Color _levelTint(DiagnosticsLogLevel level) {
  switch (level) {
    case DiagnosticsLogLevel.warn:
      return LightSurfaces.tintWarning;
    case DiagnosticsLogLevel.error:
      return LightSurfaces.tintError;
    case DiagnosticsLogLevel.info:
      return LightSurfaces.selection;
    case DiagnosticsLogLevel.debug:
      return LightSurfaces.tintClarification;
    case DiagnosticsLogLevel.verbose:
      return LightSurfaces.page;
  }
}

/// 单条诊断日志详情查看弹层（纯 Cupertino）。
class DiagnosticsDetailSheet extends StatelessWidget {
  const DiagnosticsDetailSheet({super.key, required this.entry});

  final DiagnosticsLogEntry entry;

  Future<void> _copyEntry(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: entry.toExportString()));
    if (!context.mounted) return;
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(l10n.copy),
          content: Text(l10n.copiedToClipboard),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                l10n.ok,
                style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                    ? const TextStyle(color: LightSurfaces.menuAction)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final color = entry.level.textColor.resolveFrom(context);

    return CupertinoPageScaffold(
      backgroundColor: isLight ? LightSurfaces.page : null,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: isLight ? LightSurfaces.page : null,
        border: isLight
            ? const Border(
                bottom: BorderSide(color: LightSurfaces.divider, width: 0.5),
              )
            : const Border(
                bottom: BorderSide(color: Color(0x4D000000), width: 0.0),
              ),
        middle: Text(l10n.diagnosticsDetailsTitle),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => unawaited(_copyEntry(context)),
          child: Text(
            l10n.copy,
            style: isLight
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 元数据行
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.card,
                  dark: CupertinoColors.secondarySystemGroupedBackground,
                ),
                borderRadius: BorderRadius.circular(10),
                border: isLight
                    ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isLight
                              ? _levelTint(entry.level)
                              : color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: color.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          entry.level.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.page,
                            dark: CupertinoColors.systemGrey5,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.tag,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.textSecondary,
                              dark: secondaryText,
                            ),
                          ),
                        ),
                      ),
                      if (entry.durationMs != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${entry.durationMs}ms',
                          style: TextStyle(
                            fontSize: 12,
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.textSecondary,
                              dark: secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatLogTimestamp(entry.timestamp),
                    style: TextStyle(
                      fontSize: 13,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: secondaryText,
                      ),
                    ),
                  ),
                  if (entry.errorKind != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Error: ${entry.errorKind}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: statusRedText.resolveFrom(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 主消息
            Text(
              l10n.info,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.card,
                  dark: CupertinoColors.secondarySystemGroupedBackground,
                ),
                borderRadius: BorderRadius.circular(10),
                border: isLight
                    ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
                    : null,
              ),
              child: Text(
                entry.message,
                style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 16),

            // 详情 JSON
            if (entry.details != null && entry.details!.isNotEmpty) ...[
              Text(
                l10n.description,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: secondaryText,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.card,
                    dark: CupertinoColors.secondarySystemGroupedBackground,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: isLight
                      ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
                      : null,
                ),
                child: Text(
                  entry.detailsJson,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
