import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// 聊天正文 selectable 文本的右键/长按菜单抑制器。
///
/// 背景：对正文（flutter_markdown 内部为 SelectableText）右键/长按选字时，
/// Flutter 原生文本选择工具条会与气泡外层的自定义消息菜单叠加，弹出双层菜单。
///
/// 契约（主人 2026-09-15 拍板）：
/// **桌面（Windows / Linux / macOS）**：一次右键永远只出「一层」自定义消息菜单
/// ——原生文本选择工具条在任何选区状态下都无条件抑制（含「复制」「全选」
/// 「Select all」任何形态）。有选区时的复制改由自定义消息菜单顶部的
/// 「复制选中文本」承载（见 `message_action_menu.dart`）；拖选、双击选词、
/// 键盘 Ctrl+C 能力照常保留。
/// 原先在 #81 中采用的「有选区放行原生工具条」取舍，在本轮按主人指示撤销。
///
/// **移动端（Android / iOS）**：保留原生工具条。实测（widget 工装对照，修复前
/// 基线）安卓长按正文时自定义菜单**不会**弹出（气泡外层 `onLongPress` 的长按
/// 手势被 SelectableText 的选字手势抢先，pad 区域长按才走自定义菜单），即两层
/// 菜单在移动端本就不会同现；而原生工具条是移动端「选中即复制」的唯一入口，
/// 抑制它等于让移动端失去复制能力。故移动端行为维持原状。
///
/// 为什么返回空 SizedBox 而不是把 contextMenuBuilder 置 null：
/// EditableText 层面 null 会让 SelectionOverlay 退回 legacy
/// TextSelectionControls.buildToolbar 路径（平台控件默认工具条，行为
/// 不可控）；空 builder 保持新式 ContextMenuController 路径，菜单体为
/// 零尺寸、不可见、不可点。
Widget chatMessageTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  if (!_usesNativeToolbarOnLongPress) {
    return const SizedBox.shrink();
  }
  final selection = editableTextState.textEditingValue.selection;
  if (selection.isCollapsed ||
      !selection.isValid ||
      selection.end <= selection.start) {
    return const SizedBox.shrink();
  }
  return CupertinoAdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );
}

/// 是否保留「长按选字 → 原生工具条」的移动端语义。
/// 抽成独立判据以便测试用 `debugDefaultTargetPlatformOverride` 覆盖两个分支。
bool get _usesNativeToolbarOnLongPress {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return false;
  }
}
