import 'package:flutter/cupertino.dart';

/// 聊天正文 selectable 文本的右键菜单抑制器（#81）。
///
/// 背景：Windows/Linux 上对正文（flutter_markdown 内部为 SelectableText）
/// 右键时，Flutter 原生文本选择工具条（无选区时仅「全选」一项）会与
/// 气泡外层的自定义消息右键菜单叠加，弹出双层菜单。
///
/// 策略：仅在「当前没有选区」时抑制原生工具条——复制/分支/截断等能力
/// 已由自定义消息菜单统一承载，空选区下的工具条纯属叠影；一旦用户
/// 双击/拖动选中了文字，原生工具条照常弹出（桌面右键选区复制、移动端
/// 长按选字复制、Ctrl+C 等能力全部保留）。
///
/// 为什么返回空 SizedBox 而不是把 contextMenuBuilder 置 null：
/// EditableText 层面 null 会让 SelectionOverlay 退回 legacy
/// TextSelectionControls.buildToolbar 路径（平台控件默认工具条，行为
/// 不可控）；空 builder 保持新式 ContextMenuController 路径，菜单体为
/// 零尺寸、不可见、不可点。
///
/// 工具条样式统一用 CupertinoAdaptiveTextSelectionToolbar（与输入栏
/// 右键菜单同源），避免 Material 默认条混入全 Cupertino 的聊天界面。
Widget chatMessageTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final selection = editableTextState.textEditingValue.selection;
  if (selection.isCollapsed || !selection.isValid || selection.end <= selection.start) {
    return const SizedBox.shrink();
  }
  return CupertinoAdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );
}
