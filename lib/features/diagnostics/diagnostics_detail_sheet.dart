import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/hermes_dialog.dart';
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

/// 复制单条日志到剪贴板（窄屏整页 sheet 与宽屏右栏内联详情共用）。
Future<void> copyDiagnosticsEntry(
  BuildContext context,
  DiagnosticsLogEntry entry,
) async {
  final l10n = AppLocalizations.of(context);
  await Clipboard.setData(ClipboardData(text: entry.toExportString()));
  if (!context.mounted) return;
  // 批 5 · C3：单动作提示框 → D1 `confirm`（380）；窄屏仍是系统 alert。
  unawaited(
    showHermesDialog<void>(
      context,
      kind: HermesDialogKind.confirm,
      title: (_) => Text(l10n.copy),
      content: (_) => Text(l10n.copiedToClipboard),
      actions: [
        HermesDialogAction(
          builder: (ctx) => Text(
            l10n.ok,
            style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}

/// 单条日志详情正文（元数据 + 主消息 + 详情 JSON）。
///
/// 抽出来是为了让**同一份正文**同时供两处使用：
/// - 窄屏（<900）：[DiagnosticsDetailSheet] —— 整页 push，逐像素与既有实现相同；
/// - 宽屏（≥900）：诊断页右栏内联展开（不再整页覆盖，见 `diagnostics_page.dart`
///   的 `_buildWideDetailPane`）。
///
/// 两处显示的信息因此天然一致 —— 「搬迁不丢信息」这条在本页既适用于筛选 chips，
/// 也适用于详情。
class DiagnosticsDetailBody extends StatelessWidget {
  const DiagnosticsDetailBody({super.key, required this.entry});

  final DiagnosticsLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final color = entry.level.textColor.resolveFrom(context);

    return ListView(
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
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      entry.level.label,
                      style: TextStyle(
                        fontSize: kFontCaption,
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
                        fontSize: kFontCaption,
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
                        fontSize: kFontCaption,
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
                  fontSize: kFontLabel,
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
                    fontSize: kFontLabel,
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
            fontSize: kFontBody,
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
            style: const TextStyle(fontSize: kFontCode, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 16),

        // 详情 JSON
        if (entry.details != null && entry.details!.isNotEmpty) ...[
          Text(
            l10n.description,
            style: TextStyle(
              fontSize: kFontBody,
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
              style: const TextStyle(fontSize: kFontCode, fontFamily: 'monospace'),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单条诊断日志详情查看弹层（纯 Cupertino）。
///
/// 窄屏（<900）走这里：整页 push（`HermesPageRoute(fullscreenDialog: true)`）。
/// 宽屏（≥900）改为诊断页右栏内联展开，复用同一份正文 [DiagnosticsDetailBody]。
class DiagnosticsDetailSheet extends StatelessWidget {
  const DiagnosticsDetailSheet({super.key, required this.entry});

  final DiagnosticsLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;

    return CupertinoPageScaffold(
      backgroundColor: isLight ? LightSurfaces.page : null,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: isLight ? LightSurfaces.page : null,
        border: isLight
            ? Border(
                bottom: BorderSide(color: LightSurfaces.divider, width: 0.5),
              )
            : const Border(
                bottom: BorderSide(color: Color(0x4D000000), width: 0.0),
              ),
        middle: Text(l10n.diagnosticsDetailsTitle),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => unawaited(copyDiagnosticsEntry(context, entry)),
          child: Text(
            l10n.copy,
            style: isLight
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
        ),
      ),
      child: SafeArea(child: DiagnosticsDetailBody(entry: entry)),
    );
  }
}
