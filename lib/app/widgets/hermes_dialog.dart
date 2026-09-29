/// 弹窗基础设施 —— 批 5A（设计稿 `sketches/wide-dialogs-menus-decision.html` §D1/§D2）。
///
/// 本文件交付三件东西，其余批次只吃它们、不再各写各的 magic number：
///
/// 1. [HermesDialogKind] —— **四档宽度**：380（确认框）/ 460（单选·列表型）/
///    560（表单）/ 760（宽表单·预览）。宽屏一律居中卡片。
/// 2. [showHermesDialog] —— **一份内容、两种形态**。窄屏（`<900`）原样走系统弹窗
///    路径（`showCupertinoDialog` + `CupertinoAlertDialog`，**逐像素不变**）；
///    宽屏走本文件的自定义 dialog route（[HermesDialogRoute]）+ 居中卡片
///    （[HermesDialogCard]）+ 背景压暗。
/// 3. [HermesFormRow] —— 表单行：宽屏「**左 label 88 / 右控件**」横排，窄屏维持
///    「label 上 / 控件下」竖排（§D2）。
///
/// ## 为什么必须自定义 dialog route，而不能给现有弹窗传参
///
/// `CupertinoAlertDialog` 的宽度**写死在它自己内部**：`build` 里是
/// `Center(child: Padding(vertical: 20, child: SizedBox(width: _kCupertinoDialogWidth
/// /* =270 */, …)))` —— 一个**定宽 SizedBox** 而非约束。外面套 `SizedBox(width: 380)`
/// 只会让那个 270 的盒子在新空间里重新居中，仍是 270（实测见
/// `test/app/widgets/hermes_dialog_test.dart` 的「窄屏仍是 270」守卫）。所以宽屏
/// 想要的 380/460/560/760 **只能自绘卡片**：本文件按 Cupertino 原生弹窗的度量
/// （标题 17/w600、正文 13、动作行 45、边距 20、`CupertinoPopupSurface` 圆角 13）
/// 重建一个「形似 `CupertinoAlertDialog`、宽度可控」的卡片。
///
/// ## 窄屏逐像素不变是怎么保证的
///
/// 不是「各调用点自己记得别改窄屏」，而是**由本文件的 API 形状保证**：
/// 调用点只描述内容（[HermesDialogAction] + title/content），窄屏形态由
/// [showHermesDialog] 统一渲染成与改造前**同一个** `CupertinoAlertDialog`
/// 构造路径 —— 想改窄屏像素反而要特意绕开本文件。
///
/// ## 与设计稿的正常偏差（数值取 Cupertino 原生，取「原生一致性」弃「稿面数值」）
///
/// | 稿面 | 本实现 | 理由 |
/// |---|---|---|
/// | 圆角 14 | 13 | `CupertinoPopupSurface` 原生圆角；与全仓既有弹窗同一颗角 |
/// | 内边距 19/16/4 · 18/18 | 20/20/1/20 | Cupertino `_kDialogEdgePadding`；与窄屏弹窗对齐，改宽度不改气质 |
/// | 动作行高 44 | 45（`_kDialogMinButtonHeight`） | 同上：与窄屏动作行等高 |
/// | 卡片投影 `box-shadow` | 无 | 全仓弹窗（`CupertinoPopupSurface`）均无投影，避免出现「两种浮层质感」 |
/// | 分隔线 `#CCD0DA` | `LightSurfaces.divider`（浅）/ `CupertinoColors.separator`（深） | 全仓分栏线口径 |
///
/// 宽度、动作行等高排列、「左 label 88」这三条**稿面契约**逐条兑现，未打折扣。
library;

import 'dart:math' as math;
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';

import '../theme/layout_tokens.dart';
import '../theme/light_surfaces.dart';

/// 表单行左侧 label 的固定宽度（88）—— §D2 规格，宽屏横排时生效。
///
/// 放在本文件（而不是 `app/theme/layout_tokens.dart`）是因为批 5A 的文件级
/// 分区只允许动这三个文件；后续并入令牌表只需一次 `export`，语义与
/// `kWideNavRailWidth` 完全同族。
const double kFormLabelWidth = 88.0;

/// 表单行 label 与控件之间的水平间距（12，§D2 稿面 `gap:12px`）。
const double kFormLabelGap = 12.0;

/// 表单行**窄屏**竖排时 label 与控件之间的垂直间距（6）。
///
/// 稿面写 5，这里取**现状实盘值 6**（`tasks_page.dart` 表单的
/// `SizedBox(height: 6)`）—— 窄屏逐像素不变优先于稿面微差。
const double kFormStackedGap = 6.0;

/// 宽屏弹窗卡片的宽度盒 Key（守卫测试量实际宽度、目检工装定位用）。
const Key kHermesDialogCardKey = Key('hermes-dialog-card');

/// 弹窗四档宽度（§D1）。
///
/// - [confirm] 380 —— 确认类（删除/下载/覆盖…），一两句话 + 两个动作
/// - [picker] 460 —— 单选 / 列表型（选择项目、迁移目标…）
/// - [form] 560 —— 表单（新建定时任务、编辑连接、输入弹窗）
/// - [wideForm] 760 —— 宽表单 / 预览（正文编辑器、长文本预览）
///
/// 窄屏（`<900`）不消费本枚举：形态跟随系统弹窗，宽度由系统决定。
enum HermesDialogKind {
  /// 确认框（380）。
  confirm(380.0),

  /// 单选 / 列表型（460）。
  picker(460.0),

  /// 表单（560）。
  form(560.0),

  /// 宽表单 / 预览（760）。
  wideForm(760.0);

  const HermesDialogKind(this.width);

  /// 宽屏卡片宽度（逻辑像素）。
  final double width;
}

/// 弹窗动作件（§D1 底部动作行 / §D2 表单卡片底栏共用）。
///
/// 为什么不是直接收 `CupertinoDialogAction`：动作回调需要 **dialog 自己的
/// BuildContext** 才能正确 `Navigator.pop(dialogContext, result)` —— 用调用点的
/// context 去 pop，在嵌套 Navigator / `useRootNavigator` 场景会 pop 错路由。
/// 而调用点在 `showHermesDialog` 之前拿不到 dialog 的 context，故把回调写成
/// `Function(BuildContext dialogContext)`，由基础设施在**路由内部**用正确的
/// context 调用（窄屏与宽屏都是同一个 context，行为一致）。
///
/// ## 两种形态各怎么落地这个动作
///
/// - **窄屏**：转成 `CupertinoDialogAction`（`CupertinoAlertDialog` 的动作），
///   与改造前逐像素一致；
/// - **宽屏**：**自绘**按钮（见 `_DialogActionButton`）—— 这里有个 Flutter 陷阱
///   必须写明：`CupertinoDialogAction` 是**纯表现件**，它的 `onPressed` 只由外层
///   `CupertinoAlertDialog` 自己的手势层（`_ActionSheetGestureDetector` →
///   `_SlideTarget.didConfirm()`）回调，**自身不含任何手势识别器**。直接把它摆进
///   自绘卡片 = 一排点不动的死按钮（批 5A 实测：命中路径里根本没有 gesture 节点）。
///   故宽屏自绘按钮用 `CupertinoButton` 承接手势，并按 `CupertinoDialogAction`
///   的规则复刻文字样式（16.8 / w400、默认动作 w600、破坏性 `systemRed`、
///   禁用 50% 透明），让两档**看起来**一致、**点起来**都对。
class HermesDialogAction {
  /// 构造一个弹窗动作。
  const HermesDialogAction({
    required this.builder,
    this.onPressed,
    this.enabled,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
    this.textStyle,
    this.key,
  });

  /// 动作文案（用 dialog 的 context 构建）。
  final Widget Function(BuildContext dialogContext) builder;

  /// 点击回调（用 dialog 的 context 调用）；null = 恒禁用。
  final void Function(BuildContext dialogContext)? onPressed;

  /// 可用态判据：**每次卡片重建时求值**，null = 恒可用。
  ///
  /// 为什么单列一个回调、而不是让调用点自己判 `onPressed` 传不传：
  /// 构造 [HermesDialogAction] 时可用态往往还不知道（例：表单必填项随输入变化），
  /// 而 `onPressed == null` 一旦构造就定死了。把判据做成回调，
  /// 配合 [HermesDialogCard.rebuildOn]（状态一变就重建卡片），
  /// 「保存钮灰 → 亮」才能真的跟着输入走。
  final bool Function()? enabled;

  /// 是否默认动作（iOS 会加粗）。
  final bool isDefaultAction;

  /// 是否破坏性动作（iOS 取 `systemRed`）。
  final bool isDestructiveAction;

  /// 覆盖动作文字样式（与 `CupertinoDialogAction.textStyle` 同义）。
  final TextStyle? textStyle;

  /// 动作件自身的 Key（守卫测试/目检定位用）。
  final Key? key;

  /// 转成 `CupertinoDialogAction` —— **只给窄屏（`CupertinoAlertDialog`）路径用**。
  ///
  /// 宽屏卡片**不要**用它：它在 `CupertinoAlertDialog` 之外没有任何手势识别器，
  /// 摆进自绘卡片就是死按钮（见类文档）。宽屏走 `_DialogActionButton`。
  Widget toCupertinoDialogAction(BuildContext dialogContext) {
    final onPressed = (enabled?.call() ?? true) ? this.onPressed : null;
    return CupertinoDialogAction(
      key: key,
      isDefaultAction: isDefaultAction,
      isDestructiveAction: isDestructiveAction,
      textStyle: textStyle,
      onPressed: onPressed == null ? null : () => onPressed(dialogContext),
      child: builder(dialogContext),
    );
  }
}

/// 宽屏弹窗路由 —— [CupertinoDialogRoute] 的具名子类。
///
/// 存在的意义有两个：
/// 1. **可判**：「窄屏仍走原路径」由守卫用类型断言钉死
///    （窄屏必须是 `CupertinoDialogRoute` 且 `isNot(isA<HermesDialogRoute>())`）。
/// 2. **可读**：宽屏的居中卡片形态在路由层就与系统弹窗分了类，后续批次
///    找宽屏特化入口不必翻 `pageBuilder`。
///
/// 转场、压暗色（`kCupertinoModalBarrierColor`）、压暗强度（0.2）全部继承
/// `CupertinoDialogRoute`，即**与窄屏弹窗同一套转场与同一块遮罩**。
class HermesDialogRoute<T> extends CupertinoDialogRoute<T> {
  /// 构造宽屏弹窗路由（[builder] 返回卡片内容，宽度由 `HermesDialogKind` 决定）。
  HermesDialogRoute({
    required super.context,
    required super.builder,
    super.barrierDismissible,
    super.barrierLabel,
    super.settings,
  });
}

/// 宽屏居中卡片（380/460/560/760，§D1）。
///
/// 形制对齐 `CupertinoAlertDialog`（标题 17/w600 居中、正文 13 居中、动作行
/// 等宽横排 + 发丝分隔、`CupertinoPopupSurface` 圆角 13 + 背景压暗），只有
/// **宽度可控**这一条是新增能力。
///
/// [rebuildOn]：需要「卡片本身随状态重建」时传（例：底部动作的可用态跟着输入框
/// 变）。传了它，卡片每次收到通知都会重新调用 [actions] 的 `builder` 与
/// 重算 `onPressed == null`；不传则卡片只在路由重建时构建一次。**内容子树
/// （title/content）是用 dialog context 构建的 Widget，重建时会被重新插入**，
/// 输入框自身状态由 controller 持有，不受影响。
class HermesDialogCard extends StatelessWidget {
  /// 构造卡片。
  const HermesDialogCard({
    super.key,
    required this.width,
    this.title,
    this.content,
    this.actions = const <HermesDialogAction>[],
    this.rebuildOn,
  });

  /// 卡片宽度（取 [HermesDialogKind.width] 之一）。
  final double width;

  /// 标题（尽量短，与 `CupertinoAlertDialog.title` 同义）。
  final Widget? title;

  /// 正文（与 `CupertinoAlertDialog.content` 同义）。
  final Widget? content;

  /// 底部动作行（等宽横排，末位之间的发丝分隔线与窄屏弹窗同族）。
  final List<HermesDialogAction> actions;

  /// 触发卡片重建的通知源（见类文档）。
  final Listenable? rebuildOn;

  @override
  Widget build(BuildContext context) {
    final rebuildOn = this.rebuildOn;
    if (rebuildOn == null) {
      return _buildCard(context);
    }
    return ListenableBuilder(
      listenable: rebuildOn,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    // 夹一层安全上限：窗口比档位还窄时（例如 900 宽 + 760 档仍富余，但极端情况下
    // 系统字体放大 / 分屏会缩窗）卡片不越界，仍留 24 的左右呼吸位。
    final cardWidth = math.min(width, math.max(200.0, media.width - 48.0));
    final maxHeight = math.max(200.0, media.height - 96.0);

    return Padding(
      // 键盘弹起时整体上移（与 CupertinoAlertDialog 一致）。
      padding: MediaQuery.viewInsetsOf(context),
      child: Center(
        child: SizedBox(
          key: kHermesDialogCardKey,
          width: cardWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: CupertinoPopupSurface(
              // 与原生弹窗同款：在模糊背板之上铺 `_kDialogColor` 语义面。
              isSurfacePainted: true,
              child: Semantics(
                namesRoute: true,
                scopesRoute: true,
                explicitChildNodes: true,
                label: CupertinoLocalizations.of(context).alertDialogLabel,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          20,
                          20,
                          content == null ? 20 : 1,
                        ),
                        child: DefaultTextStyle(
                          style: _kDialogTitleStyle.copyWith(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label,
                              context,
                            ),
                          ),
                          textAlign: TextAlign.center,
                          child: title!,
                        ),
                      ),
                    if (content != null)
                      Flexible(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              title == null ? 20 : 1,
                              20,
                              20,
                            ),
                            child: DefaultTextStyle(
                              style: _kDialogContentStyle.copyWith(
                                color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.label,
                                  context,
                                ),
                              ),
                              textAlign: TextAlign.center,
                              child: content!,
                            ),
                          ),
                        ),
                      ),
                    if (actions.isNotEmpty)
                      _buildActionRow(context, cardWidth),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 底部动作行：发丝顶线 + 等宽横排 + 动作间发丝竖线。
  ///
  /// 竖线用动作的 `Border(left:)` 而不是并列的 `Container`：这样竖线高度
  /// **自动等于动作件高度**，不必引 `IntrinsicHeight` 多跑一趟布局。
  ///
  /// [cardWidth] 用于算每颗动作的可用内容宽（`FittedBox` 缩字上限），
  /// 让长文案缩字而不是溢出。
  Widget _buildActionRow(BuildContext context, double cardWidth) {
    final dividerColor = LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: CupertinoColors.separator,
    );
    const dividerWidth = 0.5;
    const horizontalPadding = 8.0 * 2;
    final actionWidth =
        (cardWidth - dividerWidth * (actions.length - 1)) / actions.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: dividerWidth, color: dividerColor),
        Row(
          children: [
            for (var i = 0; i < actions.length; i++)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(
                            left: BorderSide(
                              color: dividerColor,
                              width: dividerWidth,
                            ),
                          ),
                  ),
                  child: _DialogActionButton(
                    action: actions[i],
                    maxContentWidth: math.max(
                      0,
                      actionWidth - horizontalPadding,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 宽屏卡片底部动作件 —— **自绘**（不复用 `CupertinoDialogAction`，原因见
/// [HermesDialogAction] 类文档：它是纯表现件，`onPressed` 由 alert 自己的手势层
/// 回调，摆进自绘卡片点不动）。
///
/// 手势用 `CupertinoButton` 承接；文字样式按 `CupertinoDialogAction` 的规则复刻
/// （16.8 / w400 / 居中；默认动作 w600；破坏性 `systemRed`；禁用 50% 透明），
/// 因此宽屏卡片与窄屏系统弹窗的动作**看起来一致**。
///
/// [action] 的 `key` 落在 `CupertinoButton` 上 —— 守卫测试与 E2E 据此判可用态
/// （`tester.widget<CupertinoButton>(find.byKey(k)).onPressed == null` 即禁用）。
class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.action,
    required this.maxContentWidth,
  });

  final HermesDialogAction action;

  /// 文案可用的最大宽度（超出由 `FittedBox` 缩字，而非溢出）。
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final enabled =
        (action.enabled?.call() ?? true) && action.onPressed != null;
    final onPressed = action.onPressed;

    TextStyle style = _kDialogActionStyle
        .copyWith(
          color: CupertinoDynamicColor.resolve(
            action.isDestructiveAction
                ? CupertinoColors.systemRed
                : CupertinoTheme.of(context).primaryColor,
            context,
          ),
        )
        .merge(action.textStyle);
    if (action.isDefaultAction) {
      style = style.copyWith(fontWeight: FontWeight.w600);
    }
    if (!enabled) {
      style = style.copyWith(color: style.color?.withValues(alpha: 0.5));
    }

    return CupertinoButton(
      key: action.key,
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, _kDialogActionMinHeight),
      borderRadius: BorderRadius.zero,
      // 透明底：卡片自己的面就是背景（原生 alert 的动作底也是弹窗自己的面）。
      color: CupertinoColors.transparent,
      // 禁用态**不得**出现填充底（`CupertinoButton` 默认会用 quaternarySystemFill
      // 铺一层灰），这里显式抹平。
      disabledColor: CupertinoColors.transparent,
      pressedOpacity: 0.55,
      mouseCursor: kPointerCursor,
      onPressed: enabled && onPressed != null
          ? () => onPressed(context)
          : null,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: DefaultTextStyle(
                style: style,
                textAlign: TextAlign.center,
                child: action.builder(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹出 Hermes 弹窗 —— **一份内容、两种形态**（窄屏系统弹窗 / 宽屏居中卡片）。
///
/// 窄屏（`width < 900`）：`showCupertinoDialog` + `CupertinoAlertDialog`，
/// 与改造前**同一个构造路径**，逐像素不变（[HermesDialogKind] 不参与窄屏）。
/// 宽屏（`>= 900`）：[HermesDialogRoute] + [HermesDialogCard]，宽度取
/// [kind]（380/460/560/760），水平垂直居中，背景由路由遮罩压暗。
///
/// 参数：
/// - [kind] 四档宽，只影响宽屏；窄屏忽略。
/// - [title] / [content] 与 `CupertinoAlertDialog` 同名参数同义，但收
///   `Widget Function(BuildContext dialogContext)` —— 因此可以用 dialog 自己的
///   context 构建（本仓既有弹窗的正文/标题其实都不依赖 context，传 `(_) => …` 即可）。
/// - [actions] 动作（见 [HermesDialogAction]）。
/// - [rebuildOn] 需要卡片随状态重建时传（透传给 [HermesDialogCard]）。
/// - [barrierDismissible] 默认 `false` —— 与 `showCupertinoDialog` 默认一致。
///
/// 返回值与 `showCupertinoDialog` 一致：`Navigator.pop` 的结果。
Future<T?> showHermesDialog<T>(
  BuildContext context, {
  required HermesDialogKind kind,
  Widget Function(BuildContext dialogContext)? title,
  Widget Function(BuildContext dialogContext)? content,
  List<HermesDialogAction> actions = const <HermesDialogAction>[],
  Listenable? rebuildOn,
  bool barrierDismissible = false,
  String? barrierLabel,
  RouteSettings? routeSettings,
}) {
  if (!isWideLayout(context)) {
    // 窄屏：原路径。**不要**在这里换成卡片 —— 手机端卡片会挤掉安全区与
    // 键盘适配，也是「窄屏逐像素不变」这条硬约束的被检点。
    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      routeSettings: routeSettings,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: title?.call(dialogContext),
        content: content?.call(dialogContext),
        actions: [
          for (final action in actions)
            action.toCupertinoDialogAction(dialogContext),
        ],
      ),
    );
  }

  return Navigator.of(context, rootNavigator: true).push<T>(
    HermesDialogRoute<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      settings: routeSettings,
      builder: (dialogContext) => HermesDialogCard(
        width: kind.width,
        title: title?.call(dialogContext),
        content: content?.call(dialogContext),
        actions: actions,
        rebuildOn: rebuildOn,
      ),
    ),
  );
}

/// 表单行（§D2）：宽屏「左 label 88 / 右控件」横排，窄屏「label 上 / 控件下」竖排。
///
/// ## 为什么 label 收 `Widget` 而不是 `String` + style
///
/// 为了把「窄屏逐像素不变」变成**结构性保证**：窄屏分支就是把调用点原本的
/// label 件与控件件按原来的顺序、原来的间距（[kFormStackedGap]）放进一个
/// `Column(crossAxisAlignment: start)`。调用点交进来的 label 是什么样，
/// 窄屏就还是什么样 —— 本组件不重新解释字号/颜色，就没有机会改掉窄屏像素。
/// 宽屏则把这个同一颗 label 件塞进固定 88 的槽位（[kFormLabelWidth]）。
///
/// ## alignment
///
/// 宽屏横排时 label 相对控件的竖直对齐，默认 [CrossAxisAlignment.center]
/// （稿面 `.frow { align-items:center }`）。**高控件（多行文本域）应传
/// `CrossAxisAlignment.start`** —— 否则 label 会飘到文本域的正中间，
/// 看起来像两条不相干的元素。
class HermesFormRow extends StatelessWidget {
  /// 构造表单行。
  const HermesFormRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = kFormLabelWidth,
    this.gap = kFormLabelGap,
    this.stackedGap = kFormStackedGap,
    this.alignment = CrossAxisAlignment.center,
  });

  /// 左侧（窄屏为上方）标签件 —— 由调用点决定字号与颜色。
  final Widget label;

  /// 右侧（窄屏为下方）控件件。
  final Widget child;

  /// 宽屏 label 槽宽（[kFormLabelWidth] = 88）。
  final double labelWidth;

  /// 宽屏 label 与控件之间的水平间距（[kFormLabelGap] = 12）。
  final double gap;

  /// 窄屏 label 与控件之间的垂直间距（[kFormStackedGap] = 6）。
  final double stackedGap;

  /// 宽屏横排时 label 的竖直对齐（见类文档）。
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label, SizedBox(height: stackedGap), child],
      );
    }
    return Row(
      crossAxisAlignment: alignment,
      children: [
        SizedBox(width: labelWidth, child: label),
        SizedBox(width: gap),
        Expanded(child: child),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 以下两个样式常量是 Flutter 私有常量
// （`cupertino/dialog.dart` 的 `_kCupertinoDialogTitleStyle` /
// `_kCupertinoDialogContentStyle`）的**逐字段复刻**。
//
// 为什么要复刻而不是"用主题字号"：同一个弹窗在窄屏是 `CupertinoAlertDialog`
// （用它自己这套字）、在宽屏是本卡片 —— 两边的标题/正文如果取自不同来源，
// 同一个弹窗就会在两档宽度下显示成两种字。复刻是为了让宽屏卡片与窄屏原生
// 弹窗**字面一致**。上游若改这两个常量，这里是唯一需要跟改的地方。
// ---------------------------------------------------------------------------

/// 弹窗标题样式（17 / w600 / 行高 1.3 / 字距 -0.5）。
const TextStyle _kDialogTitleStyle = TextStyle(
  fontFamily: 'CupertinoSystemText',
  inherit: false,
  fontSize: kFontPageTitle,
  fontWeight: FontWeight.w600,
  height: 1.3,
  letterSpacing: -0.5,
  textBaseline: TextBaseline.alphabetic,
);

/// 弹窗正文样式（13 / w400 / 行高 1.35 / 字距 -0.2）。
const TextStyle _kDialogContentStyle = TextStyle(
  fontFamily: 'CupertinoSystemText',
  inherit: false,
  fontSize: kFontLabel,
  fontWeight: FontWeight.w400,
  height: 1.35,
  letterSpacing: -0.2,
  textBaseline: TextBaseline.alphabetic,
);

/// 弹窗动作行最小行高（45 = Cupertino `_kDialogMinButtonHeight`）。
const double _kDialogActionMinHeight = 45.0;

/// 弹窗动作文字样式（16.8 / w400 = Cupertino `_kCupertinoDialogActionStyle`）。
const TextStyle _kDialogActionStyle = TextStyle(
  fontFamily: 'CupertinoSystemText',
  inherit: false,
  fontSize: kFontDialogAction,  // TODO(type): 未进梯子
  fontWeight: FontWeight.w400,
  textBaseline: TextBaseline.alphabetic,
);
