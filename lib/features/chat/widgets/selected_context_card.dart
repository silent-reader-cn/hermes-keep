import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../core/utils/selected_context.dart';
import '../../../l10n/app_localizations.dart';

/// 已发送选中上下文卡片 — 对齐 WebUI `style.css:1399-1401` + 参照 `InjectedNoticeCard`.
///
/// 视觉：secondarySystemBackground resolve、1px separator、圆角10、左侧 3px
/// activeBlue accent、header Row[label 11/700 activeBlue + 复制按钮]、
/// quote SelectableText 12.5/1.45 secondaryLabel，max 400 可滚.
/// 支持单块与多块 Column gap8；点击复制 quote.
class SelectedContextCard extends StatelessWidget {
  const SelectedContextCard({super.key, required this.block, this.onCopied});

  final SelectedContextBlock block;
  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
    final secondaryLabel = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final accent = LightSurfaces.resolve(
      context,
      statusBlueText.resolveFrom(context),
      dark: CupertinoColors.activeBlue,
    );
    final label = block.label.trim().isEmpty
        ? (l10n.isEnglish ? 'Context' : '上下文')
        : block.label.trim();
    final quote = block.quote.replaceAll(RegExp(r'\s+$'), '');

    return Semantics(
      label: label,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: separator),
          borderRadius: BorderRadius.circular(10),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(10),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.04 * 11,
                                  color: accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CopyButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: quote),
                              );
                              onCopied?.call();
                            },
                            color: secondaryLabel,
                            separator: separator,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        quote,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 多块容器 — 垂直 Column gap8.
class SelectedContextCardGroup extends StatelessWidget {
  const SelectedContextCardGroup({super.key, required this.blocks});

  final List<SelectedContextBlock> blocks;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    if (blocks.length == 1) {
      return SelectedContextCard(block: blocks.first);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          SelectedContextCard(block: blocks[i]),
          if (i != blocks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({
    required this.onPressed,
    required this.color,
    required this.separator,
  });

  final VoidCallback onPressed;
  final Color color;
  final Color separator;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: separator),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.doc_on_doc, size: 11, color: color),
            const SizedBox(width: 3),
            Text(l10n.copy, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
