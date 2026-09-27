// 宽屏全局规则（G1–G4）横切件令牌 —— 批 1 落码。
//
// 出处（只读设计稿）：`sketches/wide-global-rules-decision.html` §G1/§G2/§G3/§G4。
// 本文件只交付**常量与判据**；各页吃这些令牌的接入排在批 2–4。
//
// 为什么要单独一件：13 个功能页此前只有聊天 / 会话列表 / 引导有宽屏分支，其余
// 把手机单列横向拉伸到 960pt —— 一行 100+ 字符（眼睛横扫）、卡片变横幅。本文件
// 把「多宽算宽屏、阅读型多宽、内边距几档、圆角几档、焦点环、滚动条、图标钮」
// 定成唯一事实来源，后续每页只吃它，不再各写各的 magic number。
//
// 取值速查（设计稿原值，数值即契约）：
//   G1 阅读型 ≤760 居中 · 表单型 ≤560 居中 · 工具型铺满（内边距 24）
//   G2 内边距 宽屏 24 / 窄屏 16 · 圆角 分组 10 / 独立卡 12 / 行内 7
//   G3 键盘焦点环 2px + 2px offset · 图标钮 hover 圆底 28 · 光标 click/forbidden
//   G4 常显滚动条 6px 圆头（半径 3）
//
// 颜色不在这里：面/线/文字沿用 `light_surfaces.dart`，组件专色（滚动条滑块等）
// 写在使用点，避免把「布局令牌」文件养成第二个调色板。

import 'package:flutter/cupertino.dart';

/// 宽窄分流阈值（900）。
///
/// **与 `app/shell/adaptive_shell.dart` 的 `kAdaptiveBreakpoint` 同值**，但此处
/// 刻意不 import 那个常量：shell 侧大量部件要消费本文件（`theme → shell` 的反向
/// 依赖会绕成 `theme ← shell ← … ← theme` 的循环，`sidebar_tools_list.dart` 里
/// 已有为此避让的先例）。两值由 `test/app/theme/layout_tokens_test.dart` 的恒等
/// 守卫钉死 —— 任何一侧被改动都会立刻变红，所以「单一事实来源」并未丢失。
const double kWideBreakpoint = 900.0;

/// 阅读型内容宽度上限（760，居中）。
///
/// 消费方：设置分组 / 记忆正文 / 技能详情 / 提示词 / 关于 —— 这类内容一行太长
/// 就难看，760 是「桌面阅读舒适区」（约 90 字符 @17pt）。
const double kReadingMaxWidth = 760.0;

/// 表单型内容宽度上限（560，居中，比阅读型窄一档）。
///
/// 消费方：新建任务 / 编辑记忆 / 连接编辑 / 各种输入弹窗 —— 一次性输入场景居中
/// 更聚焦，且避免「标签在最左、输入框在最右」的长距离视线往返。
const double kFormMaxWidth = 560.0;

/// 宽屏面板内边距（24）。
///
/// 与侧栏固定 16 形成「外层 24 / 行内 14」两级节奏（设计稿 §G2），不再是一律 16
/// 的平铺；读数时视线不贴面板边。
const double kPanelPaddingWide = 24.0;

/// 窄屏面板内边距（16）。
///
/// 就是现状值 —— 单独留一个名字是为了让宽屏接入时能写出
/// `isWide ? kPanelPaddingWide : kPanelPaddingNarrow`，而不是把 16 散落成魔数。
const double kPanelPaddingNarrow = 16.0;

/// 分组卡片圆角（10）。
///
/// 消费方：设置页 / 记忆页的分组卡片（同一分组的多行共用一张卡）。
const double kRadiusGroup = 10.0;

/// 独立卡片圆角（12）。
///
/// 消费方：工具卡 / 详情卡这类自成一块的容器；比分组卡大一档，便于同屏辨认层级。
const double kRadiusCard = 12.0;

/// 行内元素圆角（7）。
///
/// 消费方：侧栏工具行（既有 `_ToolRow` 已用 7）、图标钮、行内小胶囊；行内元素
/// 比卡片收一档，避免「小元素配大圆角」的笨重感。
const double kRadiusInline = 7.0;

/// 键盘焦点环线宽（2）。
///
/// 批 1 **只交付常量**：焦点环的实际接入放后续批次（决策稿明确「仅键盘导航触发，
/// 鼠标点击不显示」，接线需要各页补 FocusableActionDetector，不属于横切件）。
const double kFocusRingWidth = 2.0;

/// 键盘焦点环外扩距离（2，即环与元素边界之间的间隙）。
///
/// 与 [kFocusRingWidth] 同批交付、同批接入。
const double kFocusRingOffset = 2.0;

/// 图标钮鼠标悬停圆底直径（28）。
///
/// 为什么是圆的：与 iOS 工具条语言一致（设计稿 §G3 明确「不是方形」）；28 是
/// 「够托住 14–20pt 图标、又不至于溢出 32pt 紧凑工具行」的档位。
/// 消费方：侧栏三个工具行部件的图标钮（`icon_hover_disk.dart`）。
const double kIconButtonHoverSize = 28.0;

/// 常显滚动条厚度（6）。
///
/// 消费方：`app_scrollbar.dart`（宽屏常显细条）。
const double kScrollbarThickness = 6.0;

/// 常显滚动条圆头半径（3，恰为厚度一半 —— 保证端头是半圆）。
const double kScrollbarRadius = 3.0;

/// 宽屏左栏（分类 / 分区导航）固定宽度（220）。
///
/// 批 3 的 `features/shared/wide_nav_rail.dart` 骨架默认吃这个值；批 4 的五页左列表
/// 在 220–380 区间按内容取（技能 320 / 任务 360 / 工作区 340 / Git 380 / 诊断 220），
/// 其中诊断页与骨架同为 220。放这里是为了让「左栏宽度」只有一个来源，各页不再各写
/// magic number（这批之前 `wide_nav_rail.dart` 里有一份局部 `kWideNavRailWidth`
/// 与本文件并存，已并入）。
const double kWideNavRailWidth = 220.0;

/// G3 光标语义令牌：可点元素 → 手型 [SystemMouseCursors.click]；
/// 禁用态 → 禁止符 [SystemMouseCursors.forbidden]。
///
/// 用法：直接交给 `CupertinoButton.mouseCursor`（覆盖整颗按钮，禁用态自动分流、
/// 不必自己判 `onPressed == null`），或交给 `MouseRegion.cursor`（行/区域级）。
/// 定成 [WidgetStateMouseCursor] 而非裸 `MouseCursor` 就是为了让禁用态自动生效。
///
/// 背景：桌面端此前整屏默认箭头，鼠标落在可点行/图标上没有任何提示 —— 这是
/// 「不像桌面应用」的主要来源之一（设计稿 §G3「光标语义（同批，一次性定）」）。
const WidgetStateMouseCursor kPointerCursor = WidgetStateMouseCursor.resolveWith(
  _resolvePointerCursor,
  debugDescription: 'kPointerCursor(click/forbidden)',
);

/// [kPointerCursor] 的分流实现：禁用优先。
MouseCursor _resolvePointerCursor(Set<WidgetState> states) =>
    states.contains(WidgetState.disabled)
    ? SystemMouseCursors.forbidden
    : SystemMouseCursors.click;

/// 是否宽屏（`width >= kWideBreakpoint`）。
///
/// 全仓唯一判据入口：批 1 之后的宽屏分支一律走它，别再在各页重写
/// `MediaQuery.sizeOf(context).width >= 900`（重复的阈值迟早漂）。
/// 注意用 `sizeOf` 而不是 `of` —— 只订阅尺寸变化，避免无谓重建。
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;
