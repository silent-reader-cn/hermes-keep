import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../selection_provider.dart';

/// 待发选区条面板（规格 §4.3）.
///
/// 消费 [pendingSelectionsProvider(sessionId)]，纵向 `Column gap 8`、
/// `maxHeight 280` + `SingleChildScrollView`，空时隐藏.
class SelectionChipPanel extends ConsumerWidget {
  const SelectionChipPanel({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(pendingSelectionsProvider(sessionId));
    if (pending.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pending.length > 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    key: const ValueKey('selection-clear-all'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    onPressed: () => ref
                        .read(pendingSelectionsProvider(sessionId).notifier)
                        .clear(),
                    child: Text(
                      l10n.clear,
                      style: TextStyle(
                        fontSize: 12,
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          dark: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < pending.length; i++) ...[
                if (i > 0 || pending.length > 1) const SizedBox(height: 8),
                _SelectionChipCard(sessionId: sessionId, selection: pending[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionChipCard extends ConsumerWidget {
  const _SelectionChipCard({required this.sessionId, required this.selection});

  final String sessionId;
  final PendingSelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final secondary = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final preview = selectedContextPreview(selection.text);

    return Semantics(
      label: selection.name,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: separator),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Rename context block: ${selection.name}',
                      child: Tooltip(
                        message: 'Click or press Enter to rename',
                        child: CupertinoButton(
                          key: ValueKey('selection-rename-${selection.id}'),
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () =>
                              _showRenameDialog(context, ref, selection),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              selection.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.04 * 11,
                                color: LightSurfaces.resolve(
                                  context,
                                  statusBlueText.resolveFrom(context),
                                  dark: CupertinoColors.activeBlue,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Remove context block: ${selection.name}',
                    child: CupertinoButton(
                      key: ValueKey('selection-remove-${selection.id}'),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(28, 28),
                      onPressed: () => ref
                          .read(pendingSelectionsProvider(sessionId).notifier)
                          .remove(selection.id),
                      child: Icon(
                        CupertinoIcons.xmark,
                        size: 12,
                        color: secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Tooltip(
                message: selection.text,
                child: Text(
                  preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    PendingSelection sel,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: sel.name);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.rename),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            key: const ValueKey('selection-rename-field'),
            decoration: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? BoxDecoration(
                    color: LightSurfaces.card,
                    border: Border.all(
                      color: LightSurfaces.cardBorder,
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  )
                : const CupertinoTextField().decoration,
            placeholderStyle:
                CupertinoTheme.brightnessOf(context) == Brightness.light
                ? const TextStyle(
                    fontWeight: FontWeight.w400,
                    color: LightSurfaces.placeholder,
                  )
                : const CupertinoTextField().placeholderStyle,
            controller: controller,
            autofocus: true,
            maxLength: 120,
            placeholder: sel.name,
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? const TextStyle(color: LightSurfaces.userDetail)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? const TextStyle(color: LightSurfaces.userDetail)
                : null,
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      ref
          .read(pendingSelectionsProvider(sessionId).notifier)
          .rename(sel.id, result);
    }
  }
}
