import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/insights.dart';
import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import 'insights_providers.dart';

/// 用量统计页（对齐 Hermex InsightsView 的展示形态）。
///
/// Cupertino 风格：大标题 + 刷新按钮 + 下拉刷新；时间范围用分段控件切换
/// （今天 / 近 7 天 / 近 30 天 / 全部），指标卡片展示会话 / 消息 / 令牌 /
/// 费用等汇总，模型拆分列表 + 近 14 天令牌柱状图（fl_chart）+ 峰值活动；
/// 含加载 / 错误 / 空态。
class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(insightsControllerProvider);
    final state = async.valueOrNull;

    final page = CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('insights-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.insightsTitle,
            leading: const AppBackButton(),
            trailing: AccessibleButton(
              key: const ValueKey('insights-refresh'),
              label: l10n.refreshInsights,
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(
                ref.read(insightsControllerProvider.notifier).refresh(),
              ),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(insightsControllerProvider.notifier).refresh(),
          ),
          ..._buildContentSlivers(context, ref, async, state),
        ],
      ),
    );
    if (CupertinoTheme.brightnessOf(context) == Brightness.dark) return page;
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(
        scaffoldBackgroundColor: LightSurfaces.page,
        barBackgroundColor: LightSurfaces.page,
      ),
      child: page,
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 统计正文
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<InsightsState> async,
    InsightsState? state,
  ) {
    final l10n = AppLocalizations.of(context);
    if (state == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(context, ref, async.error)];
    }

    if (!state.response.hasData) {
      return [_buildEmptySliver(context)];
    }

    final response = state.response;
    final timeframe = state.timeframe;
    final sectionBackground = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: CupertinoColors.systemGroupedBackground,
    );
    final sectionSeparator = LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: CupertinoColors.separator,
    );
    final sectionDecoration =
        CupertinoTheme.brightnessOf(context) == Brightness.light
        ? BoxDecoration(
            color: LightSurfaces.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
          )
        : null;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: CupertinoSlidingSegmentedControl<InsightsTimeframe>(
            groupValue: timeframe,
            onValueChanged: (value) {
              if (value != null) {
                unawaited(
                  ref
                      .read(insightsControllerProvider.notifier)
                      .setTimeframe(value),
                );
              }
            },
            children: {
              for (final t in InsightsTimeframe.values)
                t: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(_insightsTimeframeTitle(context, t)),
                ),
            },
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: CupertinoListSection.insetGrouped(
          backgroundColor: sectionBackground,
          separatorColor: sectionSeparator,
          decoration: sectionDecoration,
          dividerMargin: 0,
          additionalDividerMargin: 0,

          header: _periodHeader(context, response, timeframe),
          children: [
            _MetricTile(
              title: l10n.metricSessions,
              value: _formatNumber(response.totalSessions),
              icon: CupertinoIcons.bubble_left_bubble_right,
            ),
            _MetricTile(
              title: l10n.metricMessages,
              value: _formatNumber(response.totalMessages),
              icon: CupertinoIcons.text_bubble,
            ),
            _MetricTile(
              title: l10n.metricInputTokens,
              value: formatTokensCompact(response.totalInputTokens),
              icon: CupertinoIcons.arrow_down_circle,
            ),
            _MetricTile(
              title: l10n.metricOutputTokens,
              value: formatTokensCompact(response.totalOutputTokens),
              icon: CupertinoIcons.arrow_up_circle,
            ),
            _MetricTile(
              title: l10n.metricTotalTokens,
              value: formatTokensCompact(response.totalTokens),
              icon: CupertinoIcons.sum,
            ),
            _MetricTile(
              title: l10n.metricEstimatedCost,
              value: _formatCost(response.totalCost),
              icon: CupertinoIcons.money_dollar_circle,
            ),
            if (response.totalCacheHitPercent != null)
              _MetricTile(
                title: l10n.metricCacheHitRate,
                value: _formatPercent(response.totalCacheHitPercent),
                icon: CupertinoIcons.bolt_circle,
              ),
            if (response.totalCacheReadTokens != null)
              _MetricTile(
                title: l10n.metricCacheReadTokens,
                value: formatTokensCompact(response.totalCacheReadTokens),
                icon: CupertinoIcons.arrow_counterclockwise_circle,
              ),
          ],
        ),
      ),
      if (_recentDailyTokens(response).isNotEmpty)
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            backgroundColor: sectionBackground,
            separatorColor: sectionSeparator,
            decoration: sectionDecoration,
            dividerMargin: 0,
            additionalDividerMargin: 0,

            header: Text(_dailyChartTitle(context, timeframe, response)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: _DailyTokensBarChart(days: _recentDailyTokens(response)),
              ),
            ],
          ),
        ),
      if (_hasActivity(response))
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            backgroundColor: sectionBackground,
            separatorColor: sectionSeparator,
            decoration: sectionDecoration,
            dividerMargin: 0,
            additionalDividerMargin: 0,

            hasLeading: false,
            header: Text(l10n.activity),
            children: [
              if (_peakDay(response) != null)
                CupertinoListTile(
                  title: Text(l10n.mostActiveDay),
                  trailing: Text(
                    l10n.peakDaySessions(
                      _peakDay(response)!.day ?? l10n.unknown,
                      _peakDay(response)!.sessions ?? 0,
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: secondaryText,
                      ),
                    ),
                  ),
                ),
              if (_peakHour(response) != null)
                CupertinoListTile(
                  title: Text(l10n.mostActiveHour),
                  trailing: Text(
                    l10n.peakHourSessions(
                      _formatHour(context, _peakHour(response)!.hour),
                      _peakHour(response)!.sessions ?? 0,
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: secondaryText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (_modelBreakdowns(response).isNotEmpty)
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            backgroundColor: sectionBackground,
            separatorColor: sectionSeparator,
            decoration: sectionDecoration,
            dividerMargin: 0,
            additionalDividerMargin: 0,

            hasLeading: false,
            header: Text(l10n.models),
            children: [
              for (final model in _modelBreakdowns(response))
                _ModelBreakdownTile(model: model),
            ],
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Text(
            l10n.insightsSourceFooter(
              response.periodDays ?? timeframe.serverDays,
            ),
            style: TextStyle(
              fontSize: 12,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildErrorSliver(BuildContext context, WidgetRef ref, Object? error) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                // Preserve the original unresolved icon color in dark mode.
                dark: const Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(context, error),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('insights-retry'),
              color: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? statusBlueText.resolveFrom(context)
                  : null,
              onPressed: () => unawaited(
                ref.read(insightsControllerProvider.notifier).refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.chart_bar,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                // Preserve the original unresolved icon color in dark mode.
                dark: const Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noInsights,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.insightsWillShowHere,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 派生展示数据
  // -------------------------------------------------------------------------

  List<InsightsModelBreakdown> _modelBreakdowns(InsightsResponse response) {
    final models = response.models ?? const [];
    return models.length <= 10 ? models : models.sublist(0, 10);
  }

  List<InsightsDailyToken> _recentDailyTokens(InsightsResponse response) {
    final tokens = response.dailyTokens ?? const [];
    final recent = tokens.length <= 14
        ? tokens
        : tokens.sublist(tokens.length - 14);
    // 服务器按最新在前返回，图表按时间正序绘制。
    return recent.reversed.toList(growable: false);
  }

  bool _hasActivity(InsightsResponse response) =>
      _peakDay(response) != null || _peakHour(response) != null;

  InsightsActivityByDay? _peakDay(InsightsResponse response) {
    final days = response.activityByDay ?? const [];
    if (days.isEmpty) return null;
    return days.reduce(
      (a, b) => (a.sessions ?? 0) >= (b.sessions ?? 0) ? a : b,
    );
  }

  InsightsActivityByHour? _peakHour(InsightsResponse response) {
    final hours = response.activityByHour ?? const [];
    if (hours.isEmpty) return null;
    return hours.reduce(
      (a, b) => (a.sessions ?? 0) >= (b.sessions ?? 0) ? a : b,
    );
  }

  Widget _periodHeader(
    BuildContext context,
    InsightsResponse response,
    InsightsTimeframe timeframe,
  ) {
    final l10n = AppLocalizations.of(context);
    if (response.periodDays != null) {
      return Text(l10n.recentDaysHeader(response.periodDays!));
    }
    return Text(_insightsTimeframeTitle(context, timeframe));
  }

  String _errorMessage(BuildContext context, Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

String _insightsTimeframeTitle(
  BuildContext context,
  InsightsTimeframe timeframe,
) {
  final l10n = AppLocalizations.of(context);
  switch (timeframe) {
    case InsightsTimeframe.today:
      return l10n.timeframeToday;
    case InsightsTimeframe.last7Days:
      return l10n.timeframeLast7Days;
    case InsightsTimeframe.last30Days:
      return l10n.timeframeLast30Days;
    case InsightsTimeframe.allTime:
      return l10n.timeframeAll;
  }
}

String _dailyChartTitle(
  BuildContext context,
  InsightsTimeframe timeframe,
  InsightsResponse response,
) {
  final l10n = AppLocalizations.of(context);
  final days = response.periodDays ?? timeframe.serverDays;
  if (timeframe == InsightsTimeframe.today) {
    return l10n.tokensTodayChartTitle;
  }
  if (timeframe == InsightsTimeframe.allTime) {
    return l10n.tokensAllTimeChartTitle;
  }
  return l10n.tokensDailyChartTitle(days);
}

// ---------------------------------------------------------------------------
// 指标行
// ---------------------------------------------------------------------------

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: Icon(icon, color: CupertinoColors.systemBlue),
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ModelBreakdownTile extends StatelessWidget {
  const _ModelBreakdownTile({required this.model});

  final InsightsModelBreakdown model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final share = model.displayShare;
    final title = model.model?.isNotEmpty == true
        ? model.model!
        : l10n.unknownModel;
    return CupertinoListTile(
      title: Text(title),
      subtitle: Text(
        l10n.modelTokensSubtitle(formatTokensCompact(model.totalTokens)),
        style: CupertinoTheme.brightnessOf(context) == Brightness.light
            ? const TextStyle(color: LightSurfaces.textSecondary)
            : null,
      ),
      trailing: share == null
          ? null
          : Text(
              '$share%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: LightSurfaces.resolve(
                  context,
                  statusBlueText.resolveFrom(context),
                  // TextStyle previously painted the unresolved blue value.
                  dark: const Color(0xFF007AFF),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// 近期令牌柱状图（可点击弹窗详情 + hover/触摸高亮，已去掉悬浮 tooltip）
// ---------------------------------------------------------------------------

class _DailyTokensBarChart extends StatefulWidget {
  const _DailyTokensBarChart({required this.days});

  final List<InsightsDailyToken> days;

  @override
  State<_DailyTokensBarChart> createState() => _DailyTokensBarChartState();
}

class _DailyTokensBarChartState extends State<_DailyTokensBarChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final maxTokens = days.fold<int>(
      0,
      (max, day) => day.totalTokens > max ? day.totalTokens : max,
    );
    final safeMax = maxTokens <= 0 ? 1.0 : maxTokens * 1.15;

    return SizedBox(
      height: 180,
      width: double.infinity,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: safeMax.toDouble(),
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (event, response) {
              final spot = response?.spot;
              final newIndex = spot?.touchedBarGroupIndex ?? -1;
              if (newIndex != _touchedIndex) {
                setState(() => _touchedIndex = newIndex);
              }
              if (event is FlTapUpEvent && spot != null) {
                final idx = spot.touchedBarGroupIndex;
                if (idx >= 0 && idx < days.length) {
                  _showDayDetail(days[idx]);
                }
              }
            },
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) =>
                    _bottomTitle(value, meta, context),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: days[i].totalTokens.toDouble(),
                    color: i == _touchedIndex
                        ? const Color(0xFF004999)
                        : CupertinoColors.systemBlue,
                    width: 10,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomTitle(double value, TitleMeta meta, BuildContext context) {
    final index = value.toInt();
    final days = widget.days;
    if (index < 0 || index >= days.length) {
      return const SizedBox.shrink();
    }
    // 标签过密时抽稀：以最后一根柱为锚点、按轴像素宽度自适应步长。
    // 旧实现「index % 3 == 0 或强制显示最后一根」会让末位与相邻显示位
    // 只隔 1 个槽位而互相重叠（如 14 根柱的 index 12 与 13）。
    final step = _labelStep(days.length, meta.parentAxisSize);
    if ((days.length - 1 - index) % step != 0) {
      return const SizedBox.shrink();
    }
    final date = days[index].date;
    if (date == null || date.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        _shortDate(date),
        style: TextStyle(
          fontSize: 10,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: secondaryText,
          ),
        ),
      ),
    );
  }

  /// '2026-08-16' / '2026/08/16' → '08-16'；其余原样截断。
  static String _shortDate(String date) {
    final parts = date.split(RegExp(r'[-/]'));
    if (parts.length >= 3) {
      return '${parts[1]}-${parts[2]}';
    }
    return date.length <= 5 ? date : date.substring(date.length - 5);
  }

  /// 标签最小安全占位。取保守值（覆盖测试环境 Ahem 字体下 '08-27' 约
  /// 50px 的布局宽；真机 MiSans 10px 字号实际仅 ~30px，只会更宽松），
  /// 保证任意字体缩放下相邻标签中心距恒大于标签宽度。
  static const double _minLabelSlotPx = 52;

  /// 按轴像素宽度自适应抽稀步长：柱少而宽时全显（step=1），
  /// 窄屏柱密时自动拉大步长，保证任意屏宽标签互不重叠。
  static int _labelStep(int count, double axisSizePx) {
    if (count <= 1 || axisSizePx <= 0) return 1;
    final slot = axisSizePx / count;
    final step = (_minLabelSlotPx / slot).ceil();
    return step < 1 ? 1 : step;
  }

  void _showDayDetail(InsightsDailyToken day) {
    final l10n = AppLocalizations.of(context);
    final date = day.date ?? l10n.unknown;
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(date),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(
                  l10n.metricInputTokens,
                  formatTokensCompact(day.inputTokens),
                ),
                _detailRow(
                  l10n.metricOutputTokens,
                  formatTokensCompact(day.outputTokens),
                ),
                _detailRow(
                  l10n.metricTotalTokens,
                  formatTokensCompact(day.totalTokens),
                ),
                _detailRow(
                  l10n.metricSessions,
                  formatInsightsNumber(day.sessions),
                ),
                _detailRow(
                  l10n.metricEstimatedCost,
                  formatInsightsCost(day.cost),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              textStyle:
                  CupertinoTheme.brightnessOf(dialogContext) == Brightness.light
                  ? const TextStyle(color: LightSurfaces.menuAction)
                  : null,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.ok),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 数字格式化
// ---------------------------------------------------------------------------

/// 千分位格式化（null → '—'）。
String formatInsightsNumber(int? value) {
  if (value == null) return '—';
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// 紧凑令牌格式化：≥1M 用 M 单位（保留 2 位去尾零），否则千分位（null → '—'）。
String formatTokensCompact(int? value) {
  if (value == null) return '—';
  if (value.abs() >= 1000000) {
    final sign = value < 0 ? '-' : '';
    final absValue = value.abs();
    final text = (absValue / 1e6)
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return '$sign${text}M';
  }
  return formatInsightsNumber(value);
}

/// 费用格式化：保留最多 4 位小数，去掉末尾 0（null → '—'）。
String formatInsightsCost(double? value) {
  if (value == null) return '—';
  final text = value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  return '\$${text.replaceFirst(RegExp(r'\.$'), '')}';
}

/// 百分比格式化（null → '—'）。
String formatInsightsPercent(double? value) {
  if (value == null) return '—';
  return '${value.toStringAsFixed(1)}%';
}

String _formatNumber(int? value) => formatInsightsNumber(value);

String _formatCost(double? value) => formatInsightsCost(value);

String _formatPercent(double? value) => formatInsightsPercent(value);

String _formatHour(BuildContext context, int? hour) {
  if (hour == null) return AppLocalizations.of(context).unknown;
  return '${hour.toString().padLeft(2, '0')}:00';
}
