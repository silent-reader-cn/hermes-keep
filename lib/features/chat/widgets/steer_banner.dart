import 'package:flutter/cupertino.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../l10n/app_localizations.dart';

/// Cupertino 风格 steer 横幅（列表底部、流式气泡上方）。
///
/// - 图标 `CupertinoIcons.arrow_turn_up_right`（steer 语义）
/// - 背景 `systemGrey6` 圆角 10，边框 `separator` 0.5，适配深浅色
/// - 文字 `secondaryText`，单行截断 `···`
/// - 文案 `✦ 已提示："$text"`（英文 `✦ Steered: "$text"`）
class SteerBanner extends StatelessWidget {
  const SteerBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final display = text.trim();
    final label = l10n.isEnglish
        ? (display.isEmpty ? '✦ Steered' : '✦ Steered: "$display"')
        : (display.isEmpty ? '✦ 已提示' : '✦ 已提示："$display"');
    return Container(
      key: const ValueKey('chat-steer-banner'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2C2C2E)
            : LightSurfaces.resolve(
                context,
                LightSurfaces.card,
                dark: CupertinoColors.systemGrey6,
              ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.separator,
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.arrow_turn_up_right,
            size: 14,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 排队横幅 polish 版（Cupertino systemGrey6 圆角，保持与 steer 横幅同风格）。
class QueuedBanner extends StatelessWidget {
  const QueuedBanner({super.key, required this.count, this.preview});

  final int count;
  final String? preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final text = l10n.queuedBannerMessage(count);
    final hasPreview = preview != null && preview!.trim().isNotEmpty;
    return Container(
      key: const ValueKey('chat-queued-banner'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2C2C2E)
            : LightSurfaces.resolve(
                context,
                LightSurfaces.card,
                dark: CupertinoColors.systemGrey6,
              ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.separator,
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.tray,
            size: 14,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: secondaryText,
                    ),
                  ),
                ),
                if (hasPreview)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      preview!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          dark: secondaryText,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.selection,
                dark: CupertinoColors.activeBlue.withValues(alpha: 0.12),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: LightSurfaces.resolve(
                  context,
                  statusBlueText.resolveFrom(context),
                  dark: CupertinoColors.activeBlue.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
