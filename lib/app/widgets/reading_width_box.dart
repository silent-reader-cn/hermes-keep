import 'package:flutter/cupertino.dart';

import '../theme/layout_tokens.dart';

/// G1 限宽容器：宽屏把 child 限宽并**水平居中**，窄屏原样透传。
///
/// 背景（设计稿 §G1）：13 个功能页里只有聊天 / 会话列表 / 引导有宽屏分支，其余
/// 把手机单列横向拉伸到 960pt —— ① 行太长（一行 100+ 字符，眼睛横扫）② 卡片变
/// 横幅（本该 3 列的拉成 1 列 960 宽）。
///
/// 本组件只做两件事：**限宽**（[maxWidth]）+ **水平居中**。
/// - 不加内边距（内边距归 `kPanelPaddingWide/Narrow` 与页面自己）
/// - 不加动画、不引 Material
/// - 不包 ScrollView / 不改 child 的字号、换行、内部对齐
///
/// 为什么居中而不是左对齐：左对齐会在右侧留下一整片空洞（像内容没做完）；
/// 居中两侧对称留白 ≈108，观感是「呼吸」（设计稿 §G1 三方案对比，主人取②）。
///
/// 为什么用 `Align(topCenter)` 而不是 `Center`：限宽只针对**水平**方向。`Center`
/// 同时做垂直居中 —— 在高而空的父级里，一个矮 child 会被推到屏幕中间（垂直布局
/// 被悄悄改掉）；`Align(topCenter)` 水平居中、垂直交给 child 自己（要铺满的
/// ListView 依然铺满，矮内容依然贴顶）。
///
/// 窄屏（`width < kWideBreakpoint`）**逐像素原样透传**：返回的就是传进来的那棵
/// 子树，不包 Center、不包 ConstrainedBox、不加任何 padding —— 手机端与接入前
/// 完全一致（守卫见 `test/app/widgets/reading_width_box_test.dart`）。
class ReadingWidthBox extends StatelessWidget {
  /// 阅读型档位（默认 [kReadingMaxWidth] = 760）：设置分组 / 记忆正文 / 技能详情
  /// / 提示词 / 关于。
  const ReadingWidthBox({
    super.key,
    required this.child,
    this.maxWidth = kReadingMaxWidth,
  });

  /// 表单型档位（[kFormMaxWidth] = 560）：新建任务 / 编辑记忆 / 连接编辑 / 各种
  /// 输入弹窗 —— 两侧更宽的留白把视线压到中间，一次只看一件事。
  const ReadingWidthBox.form({super.key, required this.child})
    : maxWidth = kFormMaxWidth;

  /// 被限宽的内容（浏览型页面通常是一棵 ListView / Column）。
  final Widget child;

  /// 宽屏下的宽度上限；两档：阅读型 760（[kReadingMaxWidth]）、表单型 560
  /// （[kFormMaxWidth]）。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) {
      return child;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
