import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../core/models/context_window_snapshot.dart';
import '../../../l10n/app_localizations.dart';

/// 22px 环形进度指示器（对齐 WebUI 手机端圆环原型 static/ui.js _syncCtxIndicator）。
///
/// WebUI 原型：width 34 / ring 24 / r 9.75 / stroke 3 / center 15 / font 8 w600，
/// 阈值 ctx-mid>50 ctx-high>75 变色（muted → warning 橙 → error 红）。
/// Flutter 对齐：
/// - ringSize 22（与输入栏 send 图标 22 视觉统一），stroke 2.5、start -90° 不变。
/// - <=50 中性（白92%/黑82%）、50-75 warning 橙、>75 error 红（systemOrange/Red 装饰可直用）。
/// - 中心 7pt w600，'·' 与百分比一致色（互动时 label、不可用时 secondaryLabel）。
/// - track 白 0.12 / 黑 0.12（WebUI dark 0.12），对齐静止轨迹透明度。
/// - 可点击性 snapshot!=null 即可弹出（百分比为 null 时显示 · 且展示 Unavailable）。
/// - a11y label/value、命中 44、深浅色适配；Semantics enabled 与 onPressed 同步。
///
/// #156 压缩上下文进行中（[isCompressing]）：整个记号换成 iOS 原生
/// [CupertinoActivityIndicator]（**同槽位 22px、同命中区**，不产生跳位），环与
/// 百分比让位 —— 此刻的百分比表达的是压缩前的旧用量，留着反而误导用户以为
/// 「压缩有进度」。选原生指示器的另一个理由：它天然受 `TickerMode` 管控
/// （失焦自动停帧，见 #141 焦点门控），无需自建 AnimationController。
class ContextWindowIndicator extends StatelessWidget {
  const ContextWindowIndicator({
    super.key,
    required this.snapshot,
    required this.onTap,
    this.isCompressing = false,
  });

  final ContextWindowSnapshot? snapshot;
  final VoidCallback? onTap;

  /// 压缩上下文进行中（#156）：渲染为 loading 记号。
  final bool isCompressing;

  static const double ringSize = 22;
  static const double tapTargetSize = 44;

  @override
  Widget build(BuildContext context) {
    final percentage = snapshot?.percentage;
    // 任务：isInteractive 改为 snapshot!=null，无数据仍可点击展示 Unavailable。
    final isInteractive = snapshot != null;
    final pct = percentage == null
        ? null
        : (percentage * 100).round().clamp(0, 100);
    // 无百分比时显示 '·'（WebUI hasPromptTok?String(pct):'·'），与百分比同样式。
    final label = pct != null ? '$pct' : '·';
    final brightness =
        CupertinoTheme.of(context).brightness ??
        MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    // track 对齐 WebUI：light rgba(0,0,0,0.12) / dark rgba(255,255,255,0.12)
    // Decorative empty track; the progress arc and percentage carry the value.
    final trackColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.12)
        : CupertinoColors.black.withValues(alpha: 0.12);
    final neutralProgress = isDark
        ? CupertinoColors.white.withValues(alpha: 0.92)
        : CupertinoColors.black.withValues(alpha: 0.82);
    Color progressColor;
    if (pct == null) {
      progressColor = neutralProgress;
    } else if (pct > 75) {
      progressColor = LightSurfaces.resolve(
        context,
        statusRedText.resolveFrom(context),
        dark: CupertinoColors.systemRed,
      );
    } else if (pct > 50) {
      progressColor = LightSurfaces.resolve(
        context,
        statusOrangeText.resolveFrom(context),
        dark: CupertinoColors.systemOrange,
      );
    } else {
      progressColor = neutralProgress;
    }
    // 中心文字：7pt w600，'·' 与百分比一致色；无百分比时 secondaryLabel
    final hasPct = pct != null;
    final textColor = hasPct
        ? CupertinoColors.label.resolveFrom(context)
        : LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: CupertinoColors.secondaryLabel,
          );
    final l10n = AppLocalizations.of(context);

    // #156 压缩中：换成 loading 记号（同尺寸、同命中区，切换不跳位）。
    final Widget glyph;
    if (isCompressing) {
      glyph = const SizedBox(
        width: ringSize,
        height: ringSize,
        child: Center(child: CupertinoActivityIndicator(radius: 10)),
      );
    } else {
      glyph = SizedBox(
        width: ringSize,
        height: ringSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(ringSize, ringSize),
              painter: _RingPainter(
                percentage: percentage?.clamp(0.0, 1.0),
                trackColor: trackColor,
                progressColor: progressColor,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w600,
                color: textColor,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final hit = SizedBox(
      width: tapTargetSize,
      height: tapTargetSize,
      child: Center(child: RepaintBoundary(child: glyph)),
    );

    return Semantics(
      button: true,
      enabled: isInteractive,
      label: isCompressing
          ? l10n.compressing
          : (isInteractive
                ? l10n.contextWindowUsage
                : l10n.contextWindowUsageLoading),
      value: isCompressing ? '' : (hasPct ? '$pct percent' : ''),
      child: CupertinoButton(
        key: const ValueKey('chat-context-indicator-button'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(tapTargetSize, tapTargetSize),
        onPressed: isInteractive ? onTap : null,
        child: hit,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.percentage,
    required this.trackColor,
    required this.progressColor,
  });

  final double? percentage;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 2.5;
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);
    final pct = percentage;
    if (pct != null && pct > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;
      final sweep = 2 * math.pi * pct.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}