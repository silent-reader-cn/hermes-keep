import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../app/shell/adaptive_shell.dart';
import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/adaptive_popover.dart';
import '../../../app/widgets/cupertino_popover.dart';
import '../../../core/models/chat_message.dart';
import '../../../l10n/app_localizations.dart';

/// 消息级操作菜单返回的动作 tag。
///
/// - `copy`：复制纯文本；
/// - `copy_md`：复制 Markdown 原文；
/// - `edit`：用户消息回填输入框；
/// - `branch`：从此处创建分支；
/// - `truncate`：从此处截断（确认对话框已通过）。
abstract final class MessageAction {
  static const String copy = 'copy';
  static const String copyMd = 'copy_md';
  static const String edit = 'edit';
  static const String branch = 'branch';
  static const String truncate = 'truncate';
}

/// 弹出的消息操作菜单；返回 [MessageAction] tag，取消返回 null。
///
/// - 宽屏（`width >= kAdaptiveBreakpoint`）且传入 [position] 时，使用
///   [showCupertinoPopover] 弹出悬浮面板；
/// - 窄屏或未提供 [position] 时，使用 [showCupertinoModalPopup] 弹出
///   CupertinoActionSheet 底部操作表；
///
/// `truncate` 动作内部先弹确认对话框，确认后才返回 tag（取消层级：菜单取消 → null）。
/// 内容为空时复制/复制MD 项禁用。
Future<String?> showMessageActionMenu(
  BuildContext context, {
  required ChatMessage message,
  Offset? position,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
  if (isWide && position != null) {
    return _showMessageActionPopover(
      context,
      message: message,
      position: position,
    );
  }
  return _showMessageActionSheet(context, message: message);
}

/// 窄屏 / 兜底模式：底部弹出 ActionSheet。
Future<String?> _showMessageActionSheet(
  BuildContext context, {
  required ChatMessage message,
}) {
  final l10n = AppLocalizations.of(context);
  final hasContent = (message.content ?? '').trim().isNotEmpty;
  final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
  final actionStyle = isLight
      ? const TextStyle(color: LightSurfaces.userDetail)
      : null;
  final destructiveStyle = isLight
      ? TextStyle(color: statusRedText.resolveFrom(context))
      : null;
  final copyStyle = isLight && !hasContent
      ? const TextStyle(color: LightSurfaces.textSecondary)
      : actionStyle;
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(
        l10n.messageActions,
        style: TextStyle(
          fontSize: 15,
          color: isLight ? LightSurfaces.textSecondary : null,
        ),
      ),
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-copy'),
          onPressed: hasContent
              ? () => Navigator.pop(sheetContext, MessageAction.copy)
              : () {},
          child: Text(l10n.copyText, style: copyStyle),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-copy-md'),
          onPressed: hasContent
              ? () => Navigator.pop(sheetContext, MessageAction.copyMd)
              : () {},
          child: Text(l10n.copyMarkdown, style: copyStyle),
        ),
        if (message.role == 'user')
          CupertinoActionSheetAction(
            key: const ValueKey('msg-action-edit'),
            onPressed: () => Navigator.pop(sheetContext, MessageAction.edit),
            child: Text(l10n.editAndResend, style: actionStyle),
          ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-branch'),
          onPressed: () => Navigator.pop(sheetContext, MessageAction.branch),
          child: Text(l10n.branchFromHere, style: actionStyle),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-truncate'),
          isDestructiveAction: true,
          onPressed: () async {
            final confirmed = await showCupertinoDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => CupertinoAlertDialog(
                title: Text(l10n.truncateFromHere),
                content: Text(l10n.confirmTruncatePrompt),
                actions: [
                  CupertinoDialogAction(
                    key: const ValueKey('msg-truncate-cancel'),
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(l10n.cancel, style: actionStyle),
                  ),
                  CupertinoDialogAction(
                    key: const ValueKey('msg-truncate-confirm'),
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(l10n.truncate, style: destructiveStyle),
                  ),
                ],
              ),
            );
            if (confirmed == true && sheetContext.mounted) {
              Navigator.pop(sheetContext, MessageAction.truncate);
            }
          },
          child: Text(l10n.truncateFromHere, style: destructiveStyle),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('msg-action-cancel'),
        onPressed: () => Navigator.pop(sheetContext),
        child: Text(l10n.cancel, style: actionStyle),
      ),
    ),
  );
}

/// 宽屏模式：右键位置悬浮面板。
Future<String?> _showMessageActionPopover(
  BuildContext context, {
  required ChatMessage message,
  required Offset position,
}) async {
  final l10n = AppLocalizations.of(context);
  final hasContent = (message.content ?? '').trim().isNotEmpty;
  final completer = Completer<String?>();
  var isProcessingAction = false;

  await showCupertinoPopover(
    context: context,
    position: position,
    placement: PopoverPlacement.bottom,
    align: PopoverAlign.start,
    preferredWidth: 200,
    preferredHeight: message.role == 'user' ? 220 : 180,
    onClosed: () {
      if (!isProcessingAction && !completer.isCompleted) {
        completer.complete(null);
      }
    },
    builder: (popoverContext, close) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MessageActionPopoverRow(
                key: const ValueKey('msg-action-copy'),
                label: l10n.copyText,
                enabled: hasContent,
                onTap: () {
                  isProcessingAction = true;
                  close();
                  if (!completer.isCompleted) {
                    completer.complete(MessageAction.copy);
                  }
                },
              ),
              _MessageActionPopoverRow(
                key: const ValueKey('msg-action-copy-md'),
                label: l10n.copyMarkdown,
                enabled: hasContent,
                onTap: () {
                  isProcessingAction = true;
                  close();
                  if (!completer.isCompleted) {
                    completer.complete(MessageAction.copyMd);
                  }
                },
              ),
              if (message.role == 'user')
                _MessageActionPopoverRow(
                  key: const ValueKey('msg-action-edit'),
                  label: l10n.editAndResend,
                  onTap: () {
                    isProcessingAction = true;
                    close();
                    if (!completer.isCompleted) {
                      completer.complete(MessageAction.edit);
                    }
                  },
                ),
              _MessageActionPopoverRow(
                key: const ValueKey('msg-action-branch'),
                label: l10n.branchFromHere,
                onTap: () {
                  isProcessingAction = true;
                  close();
                  if (!completer.isCompleted) {
                    completer.complete(MessageAction.branch);
                  }
                },
              ),
              _MessageActionPopoverRow(
                key: const ValueKey('msg-action-truncate'),
                label: l10n.truncateFromHere,
                isDestructive: true,
                onTap: () async {
                  isProcessingAction = true;
                  close();
                  final confirmed = await showCupertinoDialog<bool>(
                    context: context,
                    builder: (dialogContext) => CupertinoAlertDialog(
                      title: Text(l10n.truncateFromHere),
                      content: Text(l10n.confirmTruncatePrompt),
                      actions: [
                        CupertinoDialogAction(
                          textStyle:
                              CupertinoTheme.brightnessOf(context) ==
                                  Brightness.light
                              ? const TextStyle(color: LightSurfaces.userDetail)
                              : null,
                          key: const ValueKey('msg-truncate-cancel'),
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(l10n.cancel),
                        ),
                        CupertinoDialogAction(
                          textStyle:
                              CupertinoTheme.brightnessOf(context) ==
                                  Brightness.light
                              ? TextStyle(
                                  color: statusRedText.resolveFrom(context),
                                )
                              : null,
                          key: const ValueKey('msg-truncate-confirm'),
                          isDestructiveAction: true,
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(l10n.truncate),
                        ),
                      ],
                    ),
                  );
                  if (!completer.isCompleted) {
                    completer.complete(
                      confirmed == true ? MessageAction.truncate : null,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      );
    },
  );

  return completer.future;
}

class _MessageActionPopoverRow extends StatelessWidget {
  const _MessageActionPopoverRow({
    super.key,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? LightSurfaces.resolve(
            context,
            LightSurfaces.placeholder,
            dark: CupertinoColors.placeholderText,
          )
        : isDestructive
        ? LightSurfaces.resolve(
            context,
            statusRedText.resolveFrom(context),
            dark: CupertinoColors.destructiveRed,
          )
        : CupertinoColors.label.resolveFrom(context);
    if (CupertinoTheme.brightnessOf(context) == Brightness.light) {
      return CupertinoListTile(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        backgroundColor: LightSurfaces.card,
        backgroundColorActivated: LightSurfaces.pressed,
        onTap: enabled ? onTap : null,
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      alignment: Alignment.centerLeft,
      onPressed: enabled ? onTap : null,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: color,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// 把 [message] 的纯文本写入剪贴板（返回结果供提示用）。
Future<void> copyMessageText(ChatMessage message) {
  return Clipboard.setData(ClipboardData(text: message.content ?? ''));
}
