import 'dart:async';
import 'package:hermes_ui/app/theme/typography_tokens.dart';


import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell/adaptive_shell.dart' show kAdaptiveBreakpoint;
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/hermes_dialog.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/insights.dart';
import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import 'insights_providers.dart';
import '../../app/widgets/app_refresh_control.dart';

// 宽屏 Bento / 两列布局常量（批 2 局部常量）。
//
// 待批次 1 的 `lib/app/theme/layout_tokens.dart` 合入后改用同名 token
// （本 worktree 基线里没有该文件，故先局部定义，取值对齐设计稿
// `sketches/wide-pages-batch2-decision.html` 的 .bento/.cell/.cols2 规格）。
const double _kWideGridGap = 12;
const double _kWideCardRadius = 10;

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
          AppRefreshControl(
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
      dark: LightSurfaces.darkPage,
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
    // 宽屏（≥900）：指标 4 列 Bento + 图表两列（左柱状图 / 右活动·模型），
    // 一屏看完不再一路向下滚；窄屏保持下方既有单列结构（逐像素不变）。
    if (MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint) {
      return [
        _timeframeSelectorSliver(context, ref, timeframe),
        ..._buildWideBodySlivers(context, response, timeframe),
        _pageFooterSliver(context, response, timeframe),
      ];
    }

    return [
      _timeframeSelectorSliver(context, ref, timeframe),
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
                      fontSize: kFontLabel,
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
                      fontSize: kFontLabel,
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
      _pageFooterSliver(context, response, timeframe),
    ];
  }

  // -------------------------------------------------------------------------
  // 宽屏（≥900）：指标 4 列 Bento + 图表两列
  // -------------------------------------------------------------------------

  /// 宽屏正文：指标 4 列 × 2 行 Bento + 图表两列（左柱状图 / 右活动·模型）。
  ///
  /// 出处：`sketches/wide-pages-batch2-decision.html` P7 推荐稿
  /// （.bento 4 列 gap 12 / .cell 白卡 0.5px 描边圆角 10 / .cols2 两列 gap 12）。
  List<Widget> _buildWideBodySlivers(
    BuildContext context,
    InsightsResponse response,
    InsightsTimeframe timeframe,
  ) {
    final l10n = AppLocalizations.of(context);
    // 与窄屏同序、同条件（缓存两项缺失时自然少两格）。
    final metrics = <({String title, String value, IconData icon})>[
      (
        title: l10n.metricSessions,
        value: _formatNumber(response.totalSessions),
        icon: CupertinoIcons.bubble_left_bubble_right,
      ),
      (
        title: l10n.metricMessages,
        value: _formatNumber(response.totalMessages),
        icon: CupertinoIcons.text_bubble,
      ),
      (
        title: l10n.metricInputTokens,
        value: formatTokensCompact(response.totalInputTokens),
        icon: CupertinoIcons.arrow_down_circle,
      ),
      (
        title: l10n.metricOutputTokens,
        value: formatTokensCompact(response.totalOutputTokens),
        icon: CupertinoIcons.arrow_up_circle,
      ),
      (
        title: l10n.metricTotalTokens,
        value: formatTokensCompact(response.totalTokens),
        icon: CupertinoIcons.sum,
      ),
      (
        title: l10n.metricEstimatedCost,
        value: _formatCost(response.totalCost),
        icon: CupertinoIcons.money_dollar_circle,
      ),
      if (response.totalCacheHitPercent != null)
        (
          title: l10n.metricCacheHitRate,
          value: _formatPercent(response.totalCacheHitPercent),
          icon: CupertinoIcons.bolt_circle,
        ),
      if (response.totalCacheReadTokens != null)
        (
          title: l10n.metricCacheReadTokens,
          value: formatTokensCompact(response.totalCacheReadTokens),
          icon: CupertinoIcons.arrow_counterclockwise_circle,
        ),
    ];

    final daily = _recentDailyTokens(response);
    final models = _modelBreakdowns(response);
    final hasActivity = _hasActivity(response);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _wideSectionHeader(
                context,
                _periodHeaderText(context, response, timeframe),
              ),
              const SizedBox(height: 8),
              ..._wideBentoRows(metrics),
            ],
          ),
        ),
      ),
      if (daily.isNotEmpty || hasActivity || models.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, _kWideGridGap, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: daily.isEmpty
                      ? const SizedBox.shrink()
                      : _wideCard(
                          context,
                          title: _dailyChartTitle(context, timeframe, response),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
                            child: _DailyTokensBarChart(days: daily),
                          ),
                        ),
                ),
                const SizedBox(width: _kWideGridGap),
                Expanded(
                  child: Column(
                    children: [
                      if (hasActivity)
                        _wideCard(
                          context,
                          title: l10n.activity,
                          child: _wideActivityRows(context, response),
                        ),
                      if (hasActivity && models.isNotEmpty)
                        const SizedBox(height: _kWideGridGap),
                      if (models.isNotEmpty)
                        _wideCard(
                          context,
                          title: l10n.models,
                          child: Column(
                            children: [
                              for (final model in models)
                                _ModelBreakdownTile(model: model),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// Bento 行：每行 4 格，末行不足时右侧留白（网格列数恒定，不因 7 格变形）。
  List<Widget> _wideBentoRows(
    List<({String title, String value, IconData icon})> metrics,
  ) {
    const perRow = 4;
    final rows = <Widget>[];
    for (var start = 0; start < metrics.length; start += perRow) {
      if (start > 0) rows.add(const SizedBox(height: _kWideGridGap));
      final count = metrics.length - start < perRow
          ? metrics.length - start
          : perRow;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < perRow; i++) ...[
                if (i > 0) const SizedBox(width: _kWideGridGap),
                Expanded(
                  child: i < count
                      ? _WideMetricCell(
                          title: metrics[start + i].title,
                          value: metrics[start + i].value,
                          icon: metrics[start + i].icon,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return rows;
  }

  /// 宽屏区块小标题（对齐既有 ListSection header 的字号与次级色）。
  Widget _wideSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: kFontSectionTitle,
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.textSecondary,
          dark: secondaryText,
        ),
      ),
    );
  }

  /// 宽屏白卡：0.5px 描边 + 圆角 10（浅色实参；暗色沿用既有分组卡面）。
  Widget _wideCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemGroupedBackground,
        ),
        borderRadius: BorderRadius.circular(_kWideCardRadius),
        border: CupertinoTheme.brightnessOf(context) == Brightness.light
            ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: kFontItemTitle,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  /// 宽屏「活动」卡：最活跃的一天 / 时段（文案与窄屏列表行同源）。
  Widget _wideActivityRows(BuildContext context, InsightsResponse response) {
    final l10n = AppLocalizations.of(context);
    final peakDay = _peakDay(response);
    final peakHour = _peakHour(response);
    return Column(
      children: [
        if (peakDay != null)
          _wideActivityRow(
            context,
            icon: CupertinoIcons.time_solid,
            label: l10n.mostActiveDay,
            value: l10n.peakDaySessions(
              peakDay.day ?? l10n.unknown,
              peakDay.sessions ?? 0,
            ),
            showDivider: peakHour != null,
          ),
        if (peakHour != null)
          _wideActivityRow(
            context,
            icon: CupertinoIcons.time,
            label: l10n.mostActiveHour,
            value: l10n.peakHourSessions(
              _formatHour(context, peakHour.hour),
              peakHour.sessions ?? 0,
            ),
          ),
      ],
    );
  }

  Widget _wideActivityRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool showDivider = false,
  }) {
    final secondary = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                // 发丝分隔线：浅色与卡片描边同族，暗色沿用既有 separator。
                bottom: BorderSide(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.cardBorder,
                    dark: CupertinoColors.separator,
                  ),
                  width: 0.5,
                ),
              ),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 15, color: secondary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: kFontCaption,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 2),
                // TODO(type): 未进梯子（10.5 是侧栏徽标专档值，内容区活动行数值）。
                Text(value, style: TextStyle(fontSize: kFontCaption, color: secondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 时间范围分段控件（宽窄屏共用；窄屏尺寸与历史基线逐像素一致）。
  Widget _timeframeSelectorSliver(
    BuildContext context,
    WidgetRef ref,
    InsightsTimeframe timeframe,
  ) {
    return SliverToBoxAdapter(
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
                // 窄屏下每段宽度被均分（390pt ≈ 85pt/段），英文标签
                // （Last 30 Days）比中文长，裸 Text 会折成两行并溢出选中
                // 胶囊；scaleDown 保证单行自适应缩小，宽屏不加尺寸，中英文
                // 与既有基线像素一致。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_insightsTimeframeTitle(context, t)),
                ),
              ),
          },
        ),
      ),
    );
  }

  /// 数据来源页脚（宽窄屏共用）。
  Widget _pageFooterSliver(
    BuildContext context,
    InsightsResponse response,
    InsightsTimeframe timeframe,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Text(
          AppLocalizations.of(
            context,
          ).insightsSourceFooter(response.periodDays ?? timeframe.serverDays),
          style: TextStyle(
            fontSize: kFontCaption,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
        ),
      ),
    );
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
                dark: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              style: const TextStyle(fontSize: kFontItemTitle, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(context, error),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kFontLabel,
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
                dark: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noInsights,
              style: const TextStyle(fontSize: kFontPageTitle, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.insightsWillShowHere,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kFontLabel,
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
    return Text(_periodHeaderText(context, response, timeframe));
  }

  /// 时间段标题文案（宽窄屏共用：窄屏作 ListSection header，宽屏作区块小标题）。
  String _periodHeaderText(
    BuildContext context,
    InsightsResponse response,
    InsightsTimeframe timeframe,
  ) {
    final l10n = AppLocalizations.of(context);
    if (response.periodDays != null) {
      return l10n.recentDaysHeader(response.periodDays!);
    }
    return _insightsTimeframeTitle(context, timeframe);
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
        style: const TextStyle(fontSize: kFontItemTitle, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 宽屏指标格：图标 + 指标名（小字）+ 数值（大字），值就在格子内。
///
/// 不复用 [CupertinoListTile]：它是「列表行」语义（leading/trailing 顶到行两端），
/// 与 Bento 格子「值贴指标名下方」不同构。浅色白卡 + 0.5px 描边 + 圆角 10，
/// 暗色沿用既有分组卡面（与下载卡片同款取舍）。
class _WideMetricCell extends StatelessWidget {
  const _WideMetricCell({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final secondary = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemGroupedBackground,
        ),
        borderRadius: BorderRadius.circular(_kWideCardRadius),
        border: CupertinoTheme.brightnessOf(context) == Brightness.light
            ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: secondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // TODO(type): 未进梯子（11.5 是侧栏状态专档值，内容区指标名借用）。
                  style: TextStyle(fontSize: kFontLabel, color: secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: kFontMetric,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ],
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
                fontSize: kFontBody,
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
          fontSize: kFontMicro,
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
    // 批 5 · C3：明细弹窗 → D1 `confirm`（380）。
    //
    // 分档理由（拿不准 → 按任务书兜底取 `confirm`）：内容是**只读**的 5 行
    // label/value 明细（非表单、非长文预览、无可选项），既不符合 `picker`
    // 「从一组选项里选一个」，也不符合 `wideForm`「长文本预览」；
    // 若要更宽松，把 `confirm` 换成 `picker`（460）即可，一行改。
    unawaited(
      showHermesDialog<void>(
        context,
        kind: HermesDialogKind.confirm,
        title: (_) => Text(date),
        content: (_) => Padding(
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
          HermesDialogAction(
            builder: (dialogContext) => Text(
              l10n.ok,
              style: CupertinoTheme.brightnessOf(dialogContext) ==
                      Brightness.light
                  ? const TextStyle(color: LightSurfaces.menuAction)
                  : null,
            ),
            onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: kFontLabel)),
          Text(
            value,
            style: const TextStyle(fontSize: kFontLabel, fontWeight: FontWeight.w600),
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
