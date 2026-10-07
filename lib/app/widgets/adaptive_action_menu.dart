import 'package:flutter/cupertino.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../shell/adaptive_shell.dart';
import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';
import 'adaptive_popover.dart';
import 'menu_row.dart';

/// 宽屏（鼠标端）菜单行高（30）。
///
/// 触屏档 44 是「手指档位」；鼠标端 24–32 就够（iOS 菜单 28 / macOS 菜单 22）。
/// 断点之上是鼠标场景，44 等于把手指档位带到了鼠标上（决策稿 `wide-dialogs-menus-decision.html`
/// §D3）。**窄屏一律仍是 44**（走 `CupertinoActionSheet`，逐像素不变）。
const double kActionMenuRowHeightWide = 30.0;

/// 宽屏菜单宽度上限（260）。
///
/// §D3「宽 ≤260」：再宽眼睛要横扫，再窄放不下「标签 + 快捷键列」两栏。
const double kActionMenuMaxWidthWide = 260.0;

/// 分组线高度（0.5）：与菜单标题下那条线同规格。
///
/// 单独成常量是为了让「按行边界收敛高度」的调用方能算出行高序列 —— 硬编码
/// 在 [ActionMenuDivider] 里就没人能引用了。
const double kActionMenuDividerHeight = 0.5;

/// 标题行高（16）：标题文本**行盒**的高度，`kActionMenuTitleBlockHeight` 里的
/// 「16」就是它。
///
/// 必须显式钉死（`TextStyle.height`）：行盒高度随字体浮动（生产 MiSans ≈16，
/// flutter_test 的测试字体是 13）—— 让「32.5」只在某个字体下成立的话，按行边界
/// 收敛就会差 3pt 切进下一行，正是本次要消灭的「半行」。
const double kActionMenuTitleLineHeight = 16.0;

/// 标题块高度（32.5）：`Padding(12, 10, 12, 6)` + 13pt 标题行高 16 + 标题下那条
/// 0.5 分组线。
///
/// 与 [kActionMenuDividerHeight]、[kActionMenuRowHeightWide] 一起构成弹层内容
/// 的真实高度序列（`AdaptiveActionMenu.show` 把它交给 `showAdaptivePopover` 的
/// `rowHeights`），切口因此永远落在行与行之间，不会出现半行。
const double kActionMenuTitleBlockHeight = 32.5;

/// 主修饰键口径：Apple 平台用 `⌘/⇧/⌥`，其余平台映射 `Ctrl/Shift/Alt`。
///
/// 读 [defaultTargetPlatform]（**目标**平台）而不是 `Platform.isX`（宿主平台）：
/// ① 仓库硬规范禁止直接读 `Platform.*` 做语义决策；② 目标平台可被测试覆写，
/// 「显示什么组合」与「注册什么组合」因此能被同一份判据钉死。
bool get _appleModifierLayout =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// 菜单快捷键：**同一组合既显示在右侧列，也真正注册给键盘**。
///
/// 刻意拆成两半（[label] 给人看、[activator] 给键盘用）并要求两者同源生成 ——
/// 只画一个 `⌘C` 而不注册快捷键，就是伪造功能；本类型不允许这种写法。
class ActionMenuShortcut {
  /// 直接给定显示串与激活器（需要非常规组合时用；常规组合请走下面两个工厂）。
  const ActionMenuShortcut({required this.label, required this.activator});

  /// 右侧列显示的组合串（`⌘C` / `Ctrl+C`）。
  final String label;

  /// 真正注册给键盘的激活器。
  final ShortcutActivator activator;

  /// 主修饰键组合（Apple `⌘` / 其余 `Ctrl`），可叠加 ⇧/⌥（其余 `Shift`/`Alt`）。
  ///
  /// [char] 仅用于显示，默认取 [key] 的 `keyLabel`。
  factory ActionMenuShortcut.primary(
    LogicalKeyboardKey key, {
    String? char,
    bool shift = false,
    bool alt = false,
  }) {
    final String glyph = char ?? key.keyLabel;
    if (_appleModifierLayout) {
      return ActionMenuShortcut(
        label: '${alt ? '⌥' : ''}${shift ? '⇧' : ''}⌘$glyph',
        activator: SingleActivator(key, meta: true, shift: shift, alt: alt),
      );
    }
    return ActionMenuShortcut(
      label: 'Ctrl+${shift ? 'Shift+' : ''}${alt ? 'Alt+' : ''}$glyph',
      activator: SingleActivator(key, control: true, shift: shift, alt: alt),
    );
  }

  /// 回车键：Apple 记作 `↵`，其余平台记作 `Enter`（同一个键、两种写法）。
  factory ActionMenuShortcut.enter() => ActionMenuShortcut(
    label: _appleModifierLayout ? '↵' : 'Enter',
    activator: const SingleActivator(LogicalKeyboardKey.enter),
  );
}

/// 宽屏菜单行（鼠标档 [kActionMenuRowHeightWide]）：图标 + 标签 + 弹性空白 + 快捷键列。
///
/// 布局**委托共享原语 [MenuRow]**：一套布局、两态只差配色。此前按主题分成两支
/// （浅色 [CupertinoListTile] / 深色 [CupertinoButton]），而 [CupertinoListTile]
/// 把 title 装在 `Column(mainAxisAlignment: spaceBetween)` 里 —— 行高被压到 30 后
/// 内容**顶到上沿**，同一个菜单项在明暗两态下布局不同（实测浅色内容中心比行中心
/// 高 8.00pt，暗色 0.00pt）。行的布局不该由主题分支决定，故收敛到 [MenuRow]。
///
/// 几何与本类保持逐像素一致：图标 14pt + 8pt 间距（**不是**选择器那份 16/10，
/// 消息右键菜单的标签左缘不许位移）、内容左右 12pt、行高 30。
///
/// 窄屏不使用本组件：窄屏菜单仍是 `CupertinoActionSheet` 的 44 行。
class ActionMenuRow extends StatelessWidget {
  /// 构造一行宽屏菜单项。
  const ActionMenuRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.shortcut,
    this.isDestructive = false,
    this.isDefault = false,
    this.enabled = true,
  });

  /// 显示文案（一律取仓库真实 l10n 文案，不生造）。
  final String label;

  /// 点击回调（调用方自行负责关闭弹层）。
  final VoidCallback onPressed;

  /// 可选前置图标（14pt，与标签同色）。
  final IconData? icon;

  /// 可选快捷键（右侧列显示 [ActionMenuShortcut.label]）。
  final ActionMenuShortcut? shortcut;

  /// 是否危险操作（红色）。
  final bool isDestructive;

  /// 是否默认强调项（蓝色 + w600）。
  final bool isDefault;

  /// 是否可点；false 时置灰且不响应点击。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color color = !enabled
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
        : isDefault
        ? LightSurfaces.resolve(
            context,
            statusBlueText.resolveFrom(context),
            dark: CupertinoColors.activeBlue,
          )
        : CupertinoColors.label.resolveFrom(context);
    final Color shortcutColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    return MenuRow(
      height: kActionMenuRowHeightWide,
      icon: icon,
      iconSize: 14,
      iconBoxWidth: 14,
      iconGap: 8,
      // 图标与标签同色（既有视觉契约）：不占用 MenuRow 的「次级色」默认值。
      iconColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      trailing: shortcut == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                shortcut!.label,
                style: TextStyle(fontSize: kFontMicro, color: shortcutColor),
              ),
            ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: kFontBody,
          color: color,
          fontWeight: isDefault ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// 宽屏菜单分组线（0.5）：把菜单项按语义分段（复制 / 跳转 / 破坏性）。
///
/// 与菜单标题下那条线同规格（0.5 高 + `LightSurfaces.divider` / 暗色
/// `CupertinoColors.separator`），保证「菜单里所有横线一样细」。
class ActionMenuDivider extends StatelessWidget {
  /// 构造一条分组线。
  const ActionMenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: kActionMenuDividerHeight,
    color: LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: CupertinoColors.separator,
    ),
  );
}

/// 快捷键作用域：菜单在的一天就受理它的快捷键，菜单关掉即刻摘除。
///
/// **刻意不碰焦点**：`Shortcuts`/`Focus` 只能处理「从当前焦点节点冒泡上来」的按键，
/// 而菜单弹出时焦点通常还在聊天输入框上 —— 于是只有两条路：
/// ① 抢焦点（实测代价：关掉菜单后焦点落在路由 FocusScope 上，输入框失焦，用户得再
/// 点一下才能打字）；② 不抢（快捷键全哑）。两条都不可接受。
/// 本实现改用 [HardwareKeyboard] 的全局 handler —— 与焦点解耦：菜单打开的期间受理
/// [bindings] 里的组合并**吃掉**该事件（返回 true = 已处理，不再下发给输入框），
/// 其余按键原样放行；菜单关闭即摘除，输入框全程不失焦。
///
/// [bindings] 为空时不注册（没有快捷键可用的菜单不掺和键盘）。
class ActionMenuShortcutScope extends StatefulWidget {
  /// 构造快捷键作用域。
  const ActionMenuShortcutScope({
    super.key,
    required this.bindings,
    required this.child,
  });

  /// 激活器 → 回调（回调应与对应菜单项的点击回调同一个函数）。
  final Map<ShortcutActivator, VoidCallback> bindings;

  /// 被作用域包住的内容（本组件不再需要包裹层，保留参数以便将来加视觉/语义）。
  final Widget child;

  @override
  State<ActionMenuShortcutScope> createState() =>
      _ActionMenuShortcutScopeState();
}

class _ActionMenuShortcutScopeState extends State<ActionMenuShortcutScope> {
  @override
  void initState() {
    super.initState();
    if (widget.bindings.isNotEmpty) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  /// 命中即执行并从事件流里吃掉（返回 true）；未命中放行。
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    for (final entry in widget.bindings.entries) {
      if (entry.key.accepts(event, keyboard)) {
        entry.value();
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 单条菜单项（与两侧 ellipsis 的 ActionSheet 保持同语义）。
class AdaptiveMenuItem {
  const AdaptiveMenuItem({
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
    this.isDefault = false,
    this.key,
    this.icon,
    this.shortcut,
    this.startsGroup = false,
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

  /// 可选前置图标（仅宽屏密排行渲染）。
  final IconData? icon;

  /// 可选快捷键（仅宽屏：右侧列显示 + 真正注册）。
  final ActionMenuShortcut? shortcut;

  /// 本项之前是否插一条分组线（仅宽屏；列表首项传 true 无效）。
  final bool startsGroup;
}

/// 桌面悬浮 vs 窄屏底部弹层的统一入口。
///
/// - 宽屏（`width >= kAdaptiveBreakpoint`）走 [showCupertinoPopover] 锚点悬浮卡片，
///   行高 [kActionMenuRowHeightWide]（30）、宽 ≤ [kActionMenuMaxWidthWide]（260）、
///   带分组线与快捷键列（§D3 鼠标档密排）；
/// - 窄屏走 [showCupertinoModalPopup] + [CupertinoActionSheet] 系统底部弹层（行高 44，不变）；
///
/// 6 处 `CupertinoIcons.ellipsis` 入口复用同一封装，行为一致可测。
class AdaptiveActionMenu {
  const AdaptiveActionMenu._();

  /// 弹出菜单。
  ///
  /// [title] 仅在有值时作为 popover 标题 / sheet title 展示；
  /// [cancelLabel] 仅 sheet 生效（popover 点击外部即关闭，无需取消按钮）。
  ///
  /// 锚点二选一：[anchorKey]（GlobalKey，传统路径）或 [anchorRect]
  /// （overlay 坐标系矩形 —— 供**不能挂 GlobalKey 的锚点**使用，例如顶栏
  /// trailing：它在路由转场时会被 Cupertino nav bar 的 Hero 穿梭层重复 build，
  /// GlobalKey 会被框架从静态顶栏抽走导致按钮丢元素）。窄屏 ActionSheet 不需要
  /// 锚点，两者都可空。
  static Future<void> show(
    BuildContext context, {
    GlobalKey? anchorKey,
    Rect? anchorRect,
    required List<AdaptiveMenuItem> items,
    String? title,
    String cancelLabel = '取消',
    Key? cancelKey,
    double preferredWidth = 220,
    double minWidth = 180,
    double? maxWidth,
  }) async {
    assert(
      anchorKey != null || anchorRect != null,
      'AdaptiveActionMenu.show 需要 anchorKey 或 anchorRect 之一',
    );
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    if (isWide) {
      // §D3：宽 ≤260。调用方就算传了更大的 preferredWidth 也被压回来。
      final double menuWidth = maxWidth ?? kActionMenuMaxWidthWide;
      // 内容的真实高度序列（标题块 + 每行 30 + 每条分组线 0.5），交给弹层做
      // **行边界**收敛：可用高度不够时切口落在两行之间，绝不切出半行。
      // 分组线（含标题下那条）算在标题块里，故此处只补项之间的分组线。
      final rowHeights = <double>[
        if (title != null && title.isNotEmpty) kActionMenuTitleBlockHeight,
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0 && items[i].startsGroup) kActionMenuDividerHeight,
          kActionMenuRowHeightWide,
        ],
      ];
      await showAdaptivePopover(
        context: context,
        anchorKey: anchorKey,
        anchorRect: anchorRect,
        preferredWidth: preferredWidth,
        minWidth: minWidth,
        maxWidth: menuWidth,
        rowHeights: rowHeights,
        builder: (popoverContext, close) {
          final bindings = <ShortcutActivator, VoidCallback>{};
          final rows = <Widget>[];
          for (var i = 0; i < items.length; i++) {
            final item = items[i];
            void run() {
              close();
              item.onPressed();
            }

            if (i > 0 && item.startsGroup) {
              rows.add(const ActionMenuDivider());
            }
            rows.add(
              ActionMenuRow(
                key: item.key,
                label: item.label,
                icon: item.icon,
                shortcut: item.shortcut,
                isDestructive: item.isDestructive,
                isDefault: item.isDefault,
                onPressed: run,
              ),
            );
            if (item.shortcut != null) {
              bindings[item.shortcut!.activator] = run;
            }
          }
          return ActionMenuShortcutScope(
            bindings: bindings,
            // **显式定宽**（而不是 `IntrinsicWidth`）：行内容现在装在 `MenuRow`
            // 的 `Stack` / `Positioned.fill` 里（为选中竖条留位），而 `Stack`
            // 的宽度内在值只统计**非定位**子节点 ⇒ 内在宽度量到 0，卡片会塌到
            // `minWidth`（180），带快捷键列的行随即横向溢出。
            // 宽度本来就该由 §D3 的「宽 ≤260」（`maxWidth`）决定，直接写死；
            // 宿主侧还会再按屏幕宽与 `minWidth` 收紧。
            child: SizedBox(
              width: menuWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null && title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Text(
                        title,
                        // 主题适配：必须 resolve 动态色（const TextStyle 直接用
                        // CupertinoColors.secondaryLabel 会冻结在浅色主题值，
                        // 深色弹层底上黑字 50% 透明几乎不可见）。
                        style: TextStyle(
                          fontSize: kFontLabel,
                          // 行盒钉死 16：`kActionMenuTitleBlockHeight` 里的「16」
                          // 必须与渲染一致，否则按行边界收敛会差几 pt 切进下一行。
                          height: kActionMenuTitleLineHeight / kFontLabel,
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
                    // Decorative separator between the menu title and actions.
                    const ActionMenuDivider(),
                  ...rows,
                ],
              ),
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
