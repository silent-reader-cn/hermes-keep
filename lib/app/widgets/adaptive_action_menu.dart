import 'package:flutter/cupertino.dart';

import '../shell/adaptive_shell.dart';
import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';
import 'cupertino_popover.dart';

/// 单条菜单项（与两侧 ellipsis 的 ActionSheet 保持同语义）。
class AdaptiveMenuItem {
  const AdaptiveMenuItem({
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
    this.isDefault = false,
    this.key,
  });

  /// 显示文案。
  final String label;

  /// 点击回调（调用方需自行 pop/close）。
  final VoidCallback onPressed;

  /// 是否为危险操作（红色）。
  final bool isDestructive;

  /// 是否为默认强调项。
  final bool isDefault;

  /// 可选 key（便于测试 find.byKey）。
  final Key? key;
}

/// 桌面悬浮 vs 窄屏底部弹层的统一入口。
///
/// - 宽屏（`width >= kAdaptiveBreakpoint`）走 [showCupertinoPopover] 锚点悬浮卡片（360×420，贴近按钮，不占屏）；
/// - 窄屏走 [showCupertinoModalPopup] + [CupertinoActionSheet] 系统底部弹层；
///
/// 6 处 `CupertinoIcons.ellipsis` 入口复用同一封装，行为一致可测。
class AdaptiveActionMenu {
  const AdaptiveActionMenu._();

  /// 弹出菜单。
  ///
  /// [title] 仅在有值时作为 popover 标题 / sheet title 展示；
  /// [cancelLabel] 仅 sheet 生效（popover 点击外部即关闭，无需取消按钮）。
  static Future<void> show(
    BuildContext context, {
    required GlobalKey anchorKey,
    required List<AdaptiveMenuItem> items,
    String? title,
    String cancelLabel = '取消',
    Key? cancelKey,
    double preferredWidth = 220,
    double minWidth = 180,
    double? maxWidth,
  }) async {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    if (isWide) {
      await showCupertinoPopover(
        context: context,
        anchorKey: anchorKey,
        preferredWidth: preferredWidth,
        minWidth: minWidth,
        maxWidth: maxWidth,
        builder: (popoverContext, close) {
          return IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null && title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      title,
                      // 主题适配：必须 resolve 动态色（const TextStyle 直接用
                      // CupertinoColors.secondaryLabel 会冻结在浅色主题值，
                      // 深色弹层底上黑字 50% 透明几乎不可见）。
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          dark: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                  ),
                if (title != null && title.isNotEmpty)
                  Container(
                    height: 0.5,
                    // Decorative separator between the menu title and actions.
                    color: LightSurfaces.resolve(
                      popoverContext,
                      LightSurfaces.divider,
                      dark: CupertinoColors.separator,
                    ),
                  ),
                for (final item in items)
                  _PopoverRow(
                    key: item.key,
                    label: item.label,
                    isDestructive: item.isDestructive,
                    isDefault: item.isDefault,
                    onTap: () {
                      close();
                      item.onPressed();
                    },
                  ),
              ],
            ),
          );
        },
      );
      return;
    }
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: title == null || title.isEmpty
            ? null
            : Text(
                title,
                style: isLight
                    ? const TextStyle(color: LightSurfaces.textSecondary)
                    : null,
              ),
        actions: [
          for (final item in items)
            CupertinoActionSheetAction(
              key: item.key,
              isDestructiveAction: item.isDestructive,
              isDefaultAction: item.isDefault,
              onPressed: () {
                Navigator.pop(sheetContext);
                item.onPressed();
              },
              child: Text(
                item.label,
                style: isLight
                    ? TextStyle(
                        color: item.isDestructive
                            ? statusRedText.resolveFrom(sheetContext)
                            : LightSurfaces.menuAction,
                      )
                    : null,
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          key: cancelKey,
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(
            cancelLabel,
            style: isLight
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
        ),
      ),
    );
  }
}

class _PopoverRow extends StatelessWidget {
  const _PopoverRow({
    super.key,
    required this.label,
    required this.isDestructive,
    required this.isDefault,
    required this.onTap,
  });

  final String label;
  final bool isDestructive;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? LightSurfaces.resolve(
            context,
            statusRedText.resolveFrom(context),
            dark: CupertinoColors.destructiveRed,
          )
        : isDefault
        ? LightSurfaces.resolve(
            context,
            statusBlueText.resolveFrom(context),
            dark: CupertinoColors.activeBlue,
          )
        : CupertinoColors.label.resolveFrom(context);
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 15,
        color: color,
        fontWeight: isDefault ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    if (CupertinoTheme.brightnessOf(context) == Brightness.light) {
      return CupertinoListTile(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        backgroundColor: LightSurfaces.card,
        backgroundColorActivated: LightSurfaces.pressed,
        onTap: onTap,
        title: text,
      );
    }
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      alignment: Alignment.centerLeft,
      onPressed: onTap,
      child: text,
    );
  }
}
