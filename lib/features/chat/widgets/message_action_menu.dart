import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../app/shell/adaptive_shell.dart';
import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/adaptive_action_menu.dart';
import '../../../app/widgets/adaptive_popover.dart';
import '../../../app/widgets/cupertino_popover.dart';
import '../../../app/widgets/hermes_dialog.dart';
import '../../../core/models/chat_message.dart';
import '../../../l10n/app_localizations.dart';

/// 消息级操作菜单返回的动作 tag。
///
/// - `copy_selection`：复制选中文本；
/// - `copy`：复制纯文本；
/// - `copy_md`：复制 Markdown 原文；
/// - `edit`：用户消息回填输入框；
/// - `branch`：从此处创建分支；
/// - `truncate`：从此处截断（确认对话框已通过）。
abstract final class MessageAction {
  static const String copySelection = 'copy_selection';
  static const String copy = 'copy';
  static const String copyMd = 'copy_md';
  static const String edit = 'edit';
  static const String branch = 'branch';
  static const String truncate = 'truncate';
}

/// 弹出的消息操作菜单；返回 [MessageAction] tag，取消返回 null。
///
/// - 宽屏（`width >= kAdaptiveBreakpoint`）且传入 [position] 时，使用
///   [showCupertinoPopover] 弹出**鼠标档密排**悬浮面板（行高 30 / 宽 260 /
///   分组线 / 快捷键列，见 §D3）；
/// - 窄屏或未提供 [position] 时，使用 [showCupertinoModalPopup] 弹出
///   CupertinoActionSheet 底部操作表（行高 44，逐像素不变）；
///
/// 宽屏面板的快捷键**与点击同一个回调**，所以右侧列画出来的组合是真的能触发的
/// 组合（`⌘C` / `Ctrl+C` 由目标平台裁决，见 [ActionMenuShortcut.primary]）。
///
/// `truncate` 动作内部先弹确认对话框，确认后才返回 tag（取消层级：菜单取消 → null）。
/// 内容为空时复制/复制MD 项禁用。
Future<String?> showMessageActionMenu(
  BuildContext context, {
  required ChatMessage message,
  Offset? position,
  String? selectionText,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
  if (isWide && position != null) {
    return _showMessageActionPopover(
      context,
      message: message,
      position: position,
      selectionText: selectionText,
    );
  }
  return _showMessageActionSheet(
    context,
    message: message,
    selectionText: selectionText,
  );
}

/// 窄屏 / 兜底模式：底部弹出 ActionSheet（触屏档行高 44，本批**不动**）。
Future<String?> _showMessageActionSheet(
  BuildContext context, {
  required ChatMessage message,
  String? selectionText,
}) {
  final l10n = AppLocalizations.of(context);
  final hasContent = (message.content ?? '').trim().isNotEmpty;
  final hasSelection = selectionText != null && selectionText.isNotEmpty;
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
        if (hasSelection)
          CupertinoActionSheetAction(
            key: const ValueKey('msg-action-copy-selection'),
            onPressed: () =>
                Navigator.pop(sheetContext, MessageAction.copySelection),
            child: Text(l10n.copySelection, style: actionStyle),
          ),
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
            // D1 确认档（380）：破坏性二次确认（窄屏仍是原系统弹窗）。
            final confirmed = await showHermesDialog<bool>(
              sheetContext,
              kind: HermesDialogKind.confirm,
              title: (_) => Text(l10n.truncateFromHere),
              content: (_) => Text(l10n.confirmTruncatePrompt),
              actions: [
                HermesDialogAction(
                  key: const ValueKey('msg-truncate-cancel'),
                  builder: (_) => Text(l10n.cancel, style: actionStyle),
                  onPressed: (dialogContext) =>
                      Navigator.pop(dialogContext, false),
                ),
                HermesDialogAction(
                  key: const ValueKey('msg-truncate-confirm'),
                  isDestructiveAction: true,
                  builder: (_) => Text(l10n.truncate, style: destructiveStyle),
                  onPressed: (dialogContext) =>
                      Navigator.pop(dialogContext, true),
                ),
              ],
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

/// 宽屏模式：右键位置悬浮面板（鼠标档密排）。
///
/// §D3：固定宽 [kActionMenuMaxWidthWide]（≤260）、行高 [kActionMenuRowHeightWide]（30）、
/// 三族分组线（复制 / 跳转 / 破坏性）、右侧快捷键列；文案一律取仓库真实 l10n。
/// §D3 的快捷键列是**新增功能**：右侧列画出的组合在 [ActionMenuShortcutScope] 里
/// 真正注册，走的是与点击完全相同的回调（不是装饰）。
Future<String?> _showMessageActionPopover(
  BuildContext context, {
  required ChatMessage message,
  required Offset position,
  String? selectionText,
}) async {
  final l10n = AppLocalizations.of(context);
  final hasContent = (message.content ?? '').trim().isNotEmpty;
  final hasSelection = selectionText != null && selectionText.isNotEmpty;
  // 菜单高度按行数实算（供 placement 判上下翻转用）：行高 30 + 上下 4 的留白。
  final rowCount =
      (hasSelection ? 3 : 2) + (message.role == 'user' ? 2 : 1) + 1;
  final completer = Completer<String?>();
  var isProcessingAction = false;

  await showCupertinoPopover(
    context: context,
    position: position,
    placement: PopoverPlacement.bottom,
    align: PopoverAlign.start,
    preferredWidth: kActionMenuMaxWidthWide,
    maxWidth: kActionMenuMaxWidthWide,
    preferredHeight: rowCount * kActionMenuRowHeightWide + 12,
    onClosed: () {
      if (!isProcessingAction && !completer.isCompleted) {
        completer.complete(null);
      }
    },
    builder: (popoverContext, close) {
      void run(String action) {
        isProcessingAction = true;
        close();
        if (!completer.isCompleted) {
          completer.complete(action);
        }
      }

      // 三族分组（§D3）：复制 / 跳转 / 破坏性。空组（如非 user 消息没有「编辑
      // 并重新发送」）自然消失，分组线按「非首组的第一项」插入。
      final groups = <List<_MessageMenuEntry>>[
        [
          _MessageMenuEntry(
            key: const ValueKey('msg-action-copy'),
            label: l10n.copyText,
            icon: CupertinoIcons.doc_text,
            shortcut: ActionMenuShortcut.primary(LogicalKeyboardKey.keyC),
            enabled: hasContent,
            onRun: () => run(MessageAction.copy),
          ),
          _MessageMenuEntry(
            key: const ValueKey('msg-action-copy-md'),
            label: l10n.copyMarkdown,
            icon: CupertinoIcons.doc_richtext,
            shortcut: ActionMenuShortcut.primary(
              LogicalKeyboardKey.keyC,
              shift: true,
            ),
            enabled: hasContent,
            onRun: () => run(MessageAction.copyMd),
          ),
          if (hasSelection)
            _MessageMenuEntry(
              key: const ValueKey('msg-action-copy-selection'),
              label: l10n.copySelection,
              icon: CupertinoIcons.doc_on_clipboard,
              shortcut: ActionMenuShortcut.primary(
                LogicalKeyboardKey.keyC,
                alt: true,
              ),
              onRun: () => run(MessageAction.copySelection),
            ),
        ],
        [
          if (message.role == 'user')
            _MessageMenuEntry(
              key: const ValueKey('msg-action-edit'),
              label: l10n.editAndResend,
              icon: CupertinoIcons.paintbrush,
              shortcut: ActionMenuShortcut.enter(),
              onRun: () => run(MessageAction.edit),
            ),
          _MessageMenuEntry(
            key: const ValueKey('msg-action-branch'),
            label: l10n.branchFromHere,
            icon: CupertinoIcons.square_stack,
            onRun: () => run(MessageAction.branch),
          ),
        ],
        [
          _MessageMenuEntry(
            key: const ValueKey('msg-action-truncate'),
            label: l10n.truncateFromHere,
            icon: CupertinoIcons.xmark,
            isDestructive: true,
            onRun: () {
              // 破坏性动作二阶确认：先按「已处理」关面板，再问；取消即整体取消。
              isProcessingAction = true;
              close();
              unawaited(
                _confirmTruncate(
                  context: context,
                  l10n: l10n,
                  complete: (action) {
                    if (!completer.isCompleted) completer.complete(action);
                  },
                ),
              );
            },
          ),
        ],
      ];
      final entries = <_MessageMenuEntry>[
        for (var gi = 0; gi < groups.length; gi++)
          for (var i = 0; i < groups[gi].length; i++)
            groups[gi][i].withGroupStart(gi > 0 && i == 0),
      ];
      // 快捷键注册表：与点击同一个回调；禁用项（空消息的复制）与不存在的项
      // （无选区时的复制选中）一律不注册 —— 否则「按了没反应」比没有更糟。
      final bindings = <ShortcutActivator, VoidCallback>{
        for (final entry in entries)
          if (entry.enabled && entry.shortcut != null)
            entry.shortcut!.activator: entry.onRun,
      };
      return ActionMenuShortcutScope(
        bindings: bindings,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0 && entries[i].startsGroup) const ActionMenuDivider(),
                ActionMenuRow(
                  key: entries[i].key,
                  label: entries[i].label,
                  icon: entries[i].icon,
                  shortcut: entries[i].shortcut,
                  enabled: entries[i].enabled,
                  isDestructive: entries[i].isDestructive,
                  onPressed: entries[i].onRun,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  return completer.future;
}

/// 破坏性动作的二次确认（宽屏面板与窄屏 sheet 同一套文案与 key）。
///
/// 取消时补 `null` —— 与「菜单整体取消」同语义（调用方据此提前返回，不做任何事）。
Future<void> _confirmTruncate({
  required BuildContext context,
  required AppLocalizations l10n,
  required void Function(String? action) complete,
}) async {
  final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
  // D1 确认档（380）—— 与窄屏 sheet 路径的同一个弹窗共用分档。
  final confirmed = await showHermesDialog<bool>(
    context,
    kind: HermesDialogKind.confirm,
    title: (_) => Text(l10n.truncateFromHere),
    content: (_) => Text(l10n.confirmTruncatePrompt),
    actions: [
      HermesDialogAction(
        textStyle: isLight
            ? const TextStyle(color: LightSurfaces.userDetail)
            : null,
        key: const ValueKey('msg-truncate-cancel'),
        builder: (_) => Text(l10n.cancel),
        onPressed: (dialogContext) => Navigator.pop(dialogContext, false),
      ),
      HermesDialogAction(
        textStyle: isLight
            ? TextStyle(color: statusRedText.resolveFrom(context))
            : null,
        key: const ValueKey('msg-truncate-confirm'),
        isDestructiveAction: true,
        builder: (_) => Text(l10n.truncate),
        onPressed: (dialogContext) => Navigator.pop(dialogContext, true),
      ),
    ],
  );
  complete(confirmed == true ? MessageAction.truncate : null);
}

/// 宽屏面板的一行：文案 + 图标 + 快捷键 + 分组位（渲染交给 `ActionMenuRow`）。
class _MessageMenuEntry {
  const _MessageMenuEntry({
    required this.key,
    required this.label,
    required this.icon,
    required this.onRun,
    this.shortcut,
    this.enabled = true,
    this.isDestructive = false,
    this.startsGroup = false,
  });

  final Key key;
  final String label;
  final IconData icon;
  final VoidCallback onRun;
  final ActionMenuShortcut? shortcut;
  final bool enabled;
  final bool isDestructive;
  final bool startsGroup;

  /// 返回本项的副本并把 [startsGroup] 设为给定值（分组线由调用方按组边界裁决）。
  _MessageMenuEntry withGroupStart(bool value) => _MessageMenuEntry(
    key: key,
    label: label,
    icon: icon,
    onRun: onRun,
    shortcut: shortcut,
    enabled: enabled,
    isDestructive: isDestructive,
    startsGroup: value,
  );
}

/// 把 [message] 的纯文本写入剪贴板（返回结果供提示用）。
Future<void> copyMessageText(ChatMessage message) {
  return Clipboard.setData(ClipboardData(text: message.content ?? ''));
}
