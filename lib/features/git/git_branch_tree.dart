import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../core/models/git_workspace.dart';
import '../../l10n/app_localizations.dart';

/// 分支树与拓扑视图组件（纯 Cupertino 实现）。
///
/// 将 [GitBranches] 中的本地与远程分支列表映射为直观的分支树与 Git 拓扑图轨（Rail Graph）：
/// - 支持本地 / 远程分支分段切换（[CupertinoSlidingSegmentedControl]）；
/// - 自绘分支轨线（[BranchRailPainter]）：当前分支高亮指示、主干连接线与曲线分支叉；
/// - 分支元数据展示：当前分支高亮徽标、上游追踪分支、领先/落后提交数、最新提交短 SHA、提交说明与作者/时间；
/// - 分支节点可点击一键切换（[onCheckout]），保留操作防重与禁用态。
class GitBranchTree extends StatefulWidget {
  const GitBranchTree({
    super.key,
    required this.branches,
    this.currentBranch,
    this.isActionRunning = false,
    this.isLoading = false,
    this.errorMessage,
    this.onCheckout,
    this.onReload,
  });

  /// 分支列表数据模型。
  final GitBranches? branches;

  /// 当前工作区所在分支名（优先取 branches.current，可由外部指定回退）。
  final String? currentBranch;

  /// 是否有写操作正在执行（切换分支中）。
  final bool isActionRunning;

  /// 是否正在加载分支列表。
  final bool isLoading;

  /// 分支加载错误信息（非空时展示轻量错误重试条）。
  final String? errorMessage;

  /// 点击切换分支回调。
  final ValueChanged<String>? onCheckout;

  /// 重试或刷新回调。
  final VoidCallback? onReload;

  @override
  State<GitBranchTree> createState() => _GitBranchTreeState();
}

class _GitBranchTreeState extends State<GitBranchTree> {
  GitBranchMode _mode = GitBranchMode.local;

  static const List<CupertinoDynamicColor> _laneColors = [
    CupertinoColors.systemBlue,
    CupertinoColors.systemTeal,
    CupertinoColors.systemPurple,
    CupertinoColors.systemOrange,
    CupertinoColors.systemIndigo,
    CupertinoColors.systemPink,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final branches = widget.branches;
    final current = widget.currentBranch ?? branches?.current;

    final localList = (branches?.local ?? const <GitBranchRef>[])
        .where((b) => b.name != null && b.name!.trim().isNotEmpty)
        .toList(growable: false);
    final remoteList = (branches?.remote ?? const <GitBranchRef>[])
        .where((b) => b.name != null && b.name!.trim().isNotEmpty)
        .toList(growable: false);

    final currentList = _mode == GitBranchMode.local ? localList : remoteList;

    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoListSection.insetGrouped(
      dividerMargin: 0,
      additionalDividerMargin: 0,
      decoration: isDark
          ? null
          : BoxDecoration(
              color: LightSurfaces.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
            ),
      separatorColor: isDark ? null : LightSurfaces.divider,
      key: const ValueKey('git-branch-tree-section'),
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l10n.branchTreeSection),
          if (localList.isNotEmpty || remoteList.isNotEmpty)
            CupertinoSlidingSegmentedControl<GitBranchMode>(
              key: const ValueKey('git-branch-mode-segmented'),
              groupValue: _mode,
              onValueChanged: (mode) {
                if (mode != null && mounted) {
                  setState(() => _mode = mode);
                }
              },
              children: {
                GitBranchMode.local: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    '${l10n.localBranches} (${localList.length})',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                GitBranchMode.remote: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    '${l10n.remoteBranches} (${remoteList.length})',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              },
            ),
        ],
      ),
      children: [
        if (widget.isLoading && currentList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CupertinoActivityIndicator(radius: 11)),
          )
        else if (widget.errorMessage != null && currentList.isEmpty)
          _buildErrorTile(context, l10n)
        else if (currentList.isEmpty)
          _buildEmptyTile(l10n)
        else
          for (var i = 0; i < currentList.length; i++)
            _buildBranchTile(
              context: context,
              branch: currentList[i],
              index: i,
              totalCount: currentList.length,
              currentBranch: current,
              isRemote: _mode == GitBranchMode.remote,
            ),
      ],
    );
  }

  Widget _buildBranchTile({
    required BuildContext context,
    required GitBranchRef branch,
    required int index,
    required int totalCount,
    required String? currentBranch,
    required bool isRemote,
  }) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final isCurrent = !isRemote && (branch.name == currentBranch);
    final isFirst = index == 0;
    final isLast = index == totalCount - 1;
    final laneColor = _laneColors[index % _laneColors.length].resolveFrom(
      context,
    );

    final ahead = branch.ahead ?? 0;
    final behind = branch.behind ?? 0;
    final upstream = branch.upstream;
    final sha = branch.sha;
    final shortSha = (sha != null && sha.isNotEmpty)
        ? (sha.length > 7 ? sha.substring(0, 7) : sha)
        : null;
    final subject = branch.subject;
    final updatedRelative = branch.updatedRelative;

    return Container(
      key: ValueKey('git-branch-node-${branch.name}'),
      color: isCurrent
          ? (isDark
                ? CupertinoColors.systemBlue
                      .resolveFrom(context)
                      .withValues(alpha: 0.07)
                : LightSurfaces.selection)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧：自绘 Git 分支拓扑轨线（Rail Graph）
          SizedBox(
            width: 28,
            height: 48,
            child: CustomPaint(
              painter: BranchRailPainter(
                isCurrent: isCurrent,
                isFirst: isFirst,
                isLast: isLast,
                laneColor: isCurrent
                    ? (isDark
                          ? CupertinoColors.systemBlue.resolveFrom(context)
                          : statusBlueText.resolveFrom(context))
                    : laneColor,
                isBranchOff: index > 0,
                trackColor: isDark
                    ? CupertinoColors.separator.resolveFrom(context)
                    : LightSurfaces.divider,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 中间：分支名称、徽标与提交元数据
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：分支名 + 当前徽标 + 上游分支 + 领先落后
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      branch.name ?? l10n.unknownBranch,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isCurrent
                            ? (isDark
                                  ? CupertinoColors.systemBlue.resolveFrom(
                                      context,
                                    )
                                  : statusBlueText.resolveFrom(context))
                            : CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? CupertinoColors.systemBlue
                                    .resolveFrom(context)
                                    .withValues(alpha: 0.16)
                              : LightSurfaces.selection,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.currentBranchBadge,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: statusBlueText.resolveFrom(context),
                          ),
                        ),
                      ),
                    if (upstream != null && upstream.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? CupertinoColors.systemGrey5.resolveFrom(context)
                              : LightSurfaces.page,
                          borderRadius: BorderRadius.circular(4),
                          border: isDark
                              ? null
                              : Border.all(
                                  color: LightSurfaces.cardBorder,
                                  width: 0.5,
                                ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.cloud,
                              size: 10,
                              color: isDark
                                  ? secondaryText.resolveFrom(context)
                                  : LightSurfaces.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              upstream,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: isDark
                                    ? secondaryText.resolveFrom(context)
                                    : LightSurfaces.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (ahead > 0)
                      Text(
                        '↑$ahead',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusGreenText.resolveFrom(context),
                        ),
                      ),
                    if (behind > 0)
                      Text(
                        '↓$behind',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusOrangeText.resolveFrom(context),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                // 第二行：短 SHA + 提交说明 + 相对时间
                Row(
                  children: [
                    if (shortSha != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? CupertinoColors.secondarySystemBackground
                                    .resolveFrom(context)
                              : LightSurfaces.page,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: isDark
                                ? CupertinoColors.separator.resolveFrom(context)
                                : LightSurfaces.cardBorder,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          shortSha,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            color: isDark
                                ? secondaryText.resolveFrom(context)
                                : LightSurfaces.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (subject != null && subject.isNotEmpty)
                      Expanded(
                        child: Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark
                                ? secondaryText.resolveFrom(context)
                                : LightSurfaces.textSecondary,
                          ),
                        ),
                      ),
                    if (updatedRelative != null &&
                        updatedRelative.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        updatedRelative,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? secondaryText.resolveFrom(context)
                              : LightSurfaces.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧：当前指示 或 切换按钮
          if (isCurrent)
            Icon(
              CupertinoIcons.checkmark_alt,
              size: 20,
              color: isDark
                  ? CupertinoColors.systemGreen.resolveFrom(context)
                  : statusGreenText.resolveFrom(context),
            )
          else if (!isRemote && branch.name != null)
            CupertinoButton(
              key: ValueKey('git-branch-switch-${branch.name}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              minimumSize: const Size(0, 26),
              color: isDark
                  ? CupertinoColors.systemBlue
                        .resolveFrom(context)
                        .withValues(alpha: 0.12)
                  : LightSurfaces.selection,
              borderRadius: BorderRadius.circular(6),
              onPressed: widget.isActionRunning
                  ? null
                  : () => widget.onCheckout?.call(branch.name!),
              child: Text(
                l10n.checkoutBranchAction,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? CupertinoColors.activeBlue.resolveFrom(context)
                      : (widget.isActionRunning
                            ? LightSurfaces.textSecondary
                            : LightSurfaces.userDetail),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyTile(AppLocalizations l10n) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Center(
        child: Text(
          l10n.noBranches,
          style: TextStyle(
            fontSize: 13,
            color: isDark
                ? secondaryText.resolveFrom(context)
                : LightSurfaces.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorTile(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 16,
            color: statusRedText.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.errorMessage ?? l10n.loadFailed,
              style: TextStyle(
                fontSize: 12,
                color: statusRedText.resolveFrom(context),
              ),
            ),
          ),
          if (widget.onReload != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: const Size(0, 24),
              onPressed: widget.isActionRunning ? null : widget.onReload,
              child: Text(
                l10n.retry,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                      ? null
                      : (widget.isActionRunning
                            ? LightSurfaces.textSecondary
                            : LightSurfaces.userDetail),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分支拓扑轨线绘制器（CustomPainter）。
///
/// 绘制垂直主干通道、节点圆点（当前分支带光晕外环）以及曲线分支叉。
/// 注：本组件绘制内容属于拓扑数据图形，评价门槛为 3:1。
/// 透明轨线、多彩 lane 轨道及外光晕 halo 本轮维持原绘制算法，列入待裁决项，
/// 不宣称全图达标 3:1；当前分支功能性标识通过右侧 checkmark（>=3:1）单独达标确保辨识。
class BranchRailPainter extends CustomPainter {
  const BranchRailPainter({
    required this.isCurrent,
    required this.isFirst,
    required this.isLast,
    required this.laneColor,
    required this.isBranchOff,
    required this.trackColor,
  });

  final bool isCurrent;
  final bool isFirst;
  final bool isLast;
  final Color laneColor;
  final bool isBranchOff;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = 14.0;
    final centerY = size.height / 2;

    // 1. 主干轨道线（从顶部贯穿或从当前节点引出）
    final trackPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (!isFirst) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, centerY), trackPaint);
    }
    if (!isLast) {
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX, size.height),
        trackPaint,
      );
    }

    // 2. 分支曲线叉（若为衍生分支，自左上主干平滑分叉）
    if (isBranchOff) {
      final forkPaint = Paint()
        ..color = laneColor.withValues(alpha: 0.75)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(centerX, math.max(0, centerY - 14))
        ..cubicTo(centerX, centerY, centerX + 4, centerY, centerX, centerY);
      canvas.drawPath(path, forkPaint);
    }

    // 3. 节点标记（Node Marker）
    final nodeRadius = isCurrent ? 5.5 : 4.0;
    if (isCurrent) {
      // 当前分支：带外光晕环 + 内部强调实心 + 中心白点
      final haloPaint = Paint()
        ..color = laneColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), nodeRadius + 3.5, haloPaint);

      final outerPaint = Paint()
        ..color = laneColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(centerX, centerY), nodeRadius, outerPaint);

      final fillPaint = Paint()
        ..color = laneColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), nodeRadius - 1.5, fillPaint);

      final centerDotPaint = Paint()
        ..color = CupertinoColors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), 1.8, centerDotPaint);
    } else {
      // 普通分支节点：实心圆点 + 边框
      final fillPaint = Paint()
        ..color = laneColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), nodeRadius, fillPaint);

      final borderPaint = Paint()
        ..color = CupertinoColors.white.withValues(alpha: 0.8)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(centerX, centerY), nodeRadius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BranchRailPainter oldDelegate) {
    return oldDelegate.isCurrent != isCurrent ||
        oldDelegate.isFirst != isFirst ||
        oldDelegate.isLast != isLast ||
        oldDelegate.laneColor != laneColor ||
        oldDelegate.isBranchOff != isBranchOff ||
        oldDelegate.trackColor != trackColor;
  }
}
