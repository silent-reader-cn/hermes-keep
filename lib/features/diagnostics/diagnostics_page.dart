import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/layout_tokens.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/hermes_dialog.dart';
import '../../app/widgets/hermes_page_route.dart';
import '../../core/utils/safe_clipboard.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_surfaces.dart';
import '../shared/wide_nav_rail.dart';
import 'diagnostics_detail_sheet.dart';
import 'diagnostics_models.dart';
import 'diagnostics_providers.dart';
import 'diagnostics_service.dart';

Color _levelTint(DiagnosticsLogLevel level) {
  switch (level) {
    case DiagnosticsLogLevel.warn:
      return LightSurfaces.tintWarning;
    case DiagnosticsLogLevel.error:
      return LightSurfaces.tintError;
    case DiagnosticsLogLevel.info:
      return LightSurfaces.selection;
    case DiagnosticsLogLevel.debug:
      return LightSurfaces.tintClarification;
    case DiagnosticsLogLevel.verbose:
      return LightSurfaces.page;
  }
}

/// 时间范围筛选的显示文案（窄屏 chips 与宽屏左栏共用同一套）。
String _timeFilterLabel(AppLocalizations l10n, DiagnosticsTimeFilter filter) {
  switch (filter) {
    case DiagnosticsTimeFilter.all:
      return l10n.diagnosticsTimeRangeAll;
    case DiagnosticsTimeFilter.today:
      return l10n.diagnosticsTimeRangeToday;
    case DiagnosticsTimeFilter.last7Days:
      return l10n.diagnosticsTimeRangeLast7Days;
    case DiagnosticsTimeFilter.custom:
      return l10n.diagnosticsTimeRangeCustom;
  }
}

/// 五级日志的显示名称（宽屏左栏「级别」项用）。
///
/// 批 5 起走 l10n（主人指示「l10n 肯定是要补齐的」），不再就地写死中英双表；
/// 语言分流由 [AppLocalizations] 统一承担，与全仓口径一致。
String _levelName(AppLocalizations l10n, DiagnosticsLogLevel level) {
  switch (level) {
    case DiagnosticsLogLevel.verbose:
      return l10n.diagnosticsLevelVerbose;
    case DiagnosticsLogLevel.debug:
      return l10n.diagnosticsLevelDebug;
    case DiagnosticsLogLevel.info:
      return l10n.diagnosticsLevelInfo;
    case DiagnosticsLogLevel.warn:
      return l10n.diagnosticsLevelWarn;
    case DiagnosticsLogLevel.error:
      return l10n.diagnosticsLevelError;
  }
}
/// 宽屏左栏「时间范围」组标题（同上，ARB 未提供）。
String _timeRangeGroupLabel(AppLocalizations l10n) =>
    l10n.diagnosticsGroupTimeRange;

/// 左栏行文案色（浅色设计稿 `#3A3A3C`；与共享骨架
/// `features/shared/wide_nav_rail.dart` 的 `_kNavRowLabel` 同值 —— 那份是私有
/// 常量，本批又不允许改 `features/shared/**`，故就地再定义一次）。
const Color _kRailRowLabel = Color(0xFF3A3A3C);

/// 诊断日志主页面（纯 Cupertino 风格，零 Material 组件）。
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;

  /// 宽屏右栏内联展开的详情条目（`null` = 右栏显示日志表）。
  ///
  /// 窄屏从不写它：窄屏点行仍是整页 push [DiagnosticsDetailSheet]（逐像素不变）。
  DiagnosticsLogEntry? _wideDetailEntry;

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      ref.read(diagnosticsFilterProvider.notifier).setSearchQuery(query);
    });
  }

  /// 导出当前 drift 库内全部日志（以库为源，不受内存缓冲截断影响，#33）。
  Future<void> _exportLogs() async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(diagnosticsServiceProvider);
    final logs = await service.exportAllLogs();
    if (logs.isEmpty || !mounted) return;
    final exportText = DiagnosticsService.formatExportText(logs);
    final result = await SafeClipboard.copyOrSave(exportText);
    if (!mounted) return;
    switch (result) {
      case SafeClipboardSuccess():
        _showAlert(l10n.diagnosticsExport, l10n.diagnosticsExportSuccess);
      case SafeClipboardFileSaved(:final filePath):
        _showAlert(
          l10n.diagnosticsExport,
          l10n.diagnosticsExportTooLargeSaved(filePath),
        );
    }
  }

  Future<void> _copySelectedLogs(
    List<DiagnosticsLogEntry> logs,
    Set<String> selectedIds,
  ) async {
    final l10n = AppLocalizations.of(context);
    final selectedEntries = logs
        .where((e) => selectedIds.contains(e.id))
        .toList();
    if (selectedEntries.isEmpty) return;

    final exportText = DiagnosticsService.formatExportText(selectedEntries);
    final result = await SafeClipboard.copyOrSave(exportText);
    if (!mounted) return;
    ref.read(diagnosticsIsSelectionModeProvider.notifier).setMode(false);
    ref.read(diagnosticsSelectedIdsProvider.notifier).clear();
    switch (result) {
      case SafeClipboardSuccess():
        _showAlert(l10n.copy, l10n.copiedToClipboard);
      case SafeClipboardFileSaved(:final filePath):
        _showAlert(l10n.copy, l10n.diagnosticsExportTooLargeSaved(filePath));
    }
  }

  Future<void> _confirmClearLogs() async {
    final l10n = AppLocalizations.of(context);
    // 批 5 · C3：清空日志确认 → D1 `confirm`（380）；窄屏仍是系统 alert。
    final confirmed = await showHermesDialog<bool>(
      context,
      kind: HermesDialogKind.confirm,
      title: (_) => Text(l10n.diagnosticsClear),
      content: (_) => Text(l10n.diagnosticsConfirmClear),
      actions: [
        HermesDialogAction(
          isDestructiveAction: true,
          key: const ValueKey('diagnostics-clear-confirm'),
          builder: (ctx) => Text(
            l10n.clear,
            style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                ? const TextStyle(color: Color(0xFFB3001B))
                : null,
          ),
          onPressed: (ctx) => Navigator.of(ctx).pop(true),
        ),
        HermesDialogAction(
          isDefaultAction: true,
          builder: (ctx) => Text(
            l10n.cancel,
            style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
          onPressed: (ctx) => Navigator.of(ctx).pop(false),
        ),
      ],
    );
    if (confirmed == true && mounted) {
      await ref.read(diagnosticsLogsProvider.notifier).clear();
    }
  }

  void _showAlert(String title, String message) {
    final l10n = AppLocalizations.of(context);
    // 批 5 · C3：单动作提示框 → D1 `confirm`（380）；窄屏仍是系统 alert。
    unawaited(
      showHermesDialog<void>(
        context,
        kind: HermesDialogKind.confirm,
        title: (_) => Text(title),
        content: (_) => Text(message),
        actions: [
          HermesDialogAction(
            builder: (ctx) => Text(
              l10n.ok,
              style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                  ? const TextStyle(color: LightSurfaces.menuAction)
                  : null,
            ),
            onPressed: (ctx) => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  void _showDetailSheet(DiagnosticsLogEntry entry) {
    Navigator.of(context).push(
      HermesPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DiagnosticsDetailSheet(entry: entry),
      ),
    );
  }

  /// 点一条日志：宽屏在右栏内联展开，窄屏整页 push（工装/真机行为都不变）。
  void _openDetail(DiagnosticsLogEntry entry) {
    if (isWideLayout(context)) {
      setState(() => _wideDetailEntry = entry);
    } else {
      _showDetailSheet(entry);
    }
  }

  /// 进入多选模式（顺带收起宽屏内联详情：多选态下点行是勾选，不是看详情）。
  void _enterSelectionMode() {
    if (_wideDetailEntry != null) {
      setState(() => _wideDetailEntry = null);
    }
    ref.read(diagnosticsIsSelectionModeProvider.notifier).setMode(true);
  }

  /// 左栏「全部」= 把缺的级别补齐。
  ///
  /// 既有筛选状态是**集合多选且末项不可撤**（`toggleLevel` 语义），故「全部」
  /// 不新增状态字段，逐个补齐缺口即可（只用公开 API，不动 providers）。
  void _selectAllLevels() {
    final notifier = ref.read(diagnosticsFilterProvider.notifier);
    final selected = ref.read(diagnosticsFilterProvider).selectedLevels;
    for (final level in DiagnosticsLogLevel.values) {
      if (!selected.contains(level)) notifier.toggleLevel(level);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final enabled = ref.watch(diagnosticsEnabledProvider);
    final allLogs = ref.watch(diagnosticsLogsProvider);
    final filteredLogs = ref.watch(filteredDiagnosticsLogsProvider);
    final filter = ref.watch(diagnosticsFilterProvider);
    final isSelectionMode = ref.watch(diagnosticsIsSelectionModeProvider);
    final selectedIds = ref.watch(diagnosticsSelectedIdsProvider);

    return CupertinoPageScaffold(
      backgroundColor: isLight ? LightSurfaces.page : null,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: isLight ? LightSurfaces.page : null,
        border: isLight
            ? const Border(
                bottom: BorderSide(color: LightSurfaces.divider, width: 0.5),
              )
            : const Border(
                bottom: BorderSide(color: Color(0x4D000000), width: 0.0),
              ),
        middle: Text(
          isSelectionMode
              ? l10n.diagnosticsSelectedCount(selectedIds.length)
              : l10n.diagnosticsTitle,
        ),
        trailing: isSelectionMode
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                key: const ValueKey('diagnostics-exit-selection-btn'),
                onPressed: () {
                  ref
                      .read(diagnosticsIsSelectionModeProvider.notifier)
                      .setMode(false);
                  ref.read(diagnosticsSelectedIdsProvider.notifier).clear();
                },
                child: Text(
                  l10n.diagnosticsExitSelectMode,
                  style: isLight
                      ? const TextStyle(color: LightSurfaces.menuAction)
                      : null,
                ),
              )
            : (allLogs.isNotEmpty
                  ? CupertinoButton(
                      padding: EdgeInsets.zero,
                      key: const ValueKey('diagnostics-enter-selection-btn'),
                      onPressed: _enterSelectionMode,
                      child: Text(
                        l10n.diagnosticsSelectMode,
                        style: isLight
                            ? const TextStyle(color: LightSurfaces.menuAction)
                            : null,
                      ),
                    )
                  : null),
      ),
      child: SafeArea(
        // 宽屏（≥900）：顶部 chips 行搬进左 220 筛选导航，右栏（调试模式开关 /
        // 搜索框 / 计数 / 导出 / 清空日志 / 日志表）一律留原位、日志表铺满，
        // 详情在右栏内展开；窄屏（<900）：既有单列 —— 逐像素不变。
        child: isWideLayout(context)
            ? _buildWideBody(
                context,
                enabled: enabled,
                allLogs: allLogs,
                filteredLogs: filteredLogs,
                filter: filter,
                isSelectionMode: isSelectionMode,
                selectedIds: selectedIds,
              )
            : _buildNarrowBody(
                context,
                isLight: isLight,
                enabled: enabled,
                allLogs: allLogs,
                filteredLogs: filteredLogs,
                filter: filter,
                isSelectionMode: isSelectionMode,
                selectedIds: selectedIds,
              ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 窄屏（<900）：既有单列长卷 —— 与批 4C 之前逐像素相同
  // -------------------------------------------------------------------------

  Widget _buildNarrowBody(
    BuildContext context, {
    required bool isLight,
    required bool enabled,
    required List<DiagnosticsLogEntry> allLogs,
    required List<DiagnosticsLogEntry> filteredLogs,
    required DiagnosticsFilterState filter,
    required bool isSelectionMode,
    required Set<String> selectedIds,
  }) {
    return Column(
      children: [
        _buildSwitchCard(context, enabled: enabled, isLight: isLight),

        // 搜索与筛选工具栏（仅在开启或有日志时展示）
        if (enabled || allLogs.isNotEmpty) ...[
          _buildSearchField(context, isLight: isLight),

          // 级别筛选与时间筛选 Chips
          _buildFilterChipsRow(context, filter),

          // 操作按钮栏（导出、清空、条数统计）
          _buildActionRow(
            context,
            isLight: isLight,
            allLogs: allLogs,
            filteredLogs: filteredLogs,
          ),
        ],

        const SizedBox(height: 4),

        // 日志列表内容区（虚拟化）
        Expanded(
          child: _buildLogContent(
            context,
            enabled: enabled,
            allLogs: allLogs,
            filteredLogs: filteredLogs,
            isSelectionMode: isSelectionMode,
            selectedIds: selectedIds,
          ),
        ),

        // 多选模式底部操作栏
        if (isSelectionMode)
          _buildSelectionBar(
            context,
            isLight: isLight,
            filteredLogs: filteredLogs,
            selectedIds: selectedIds,
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 宽屏（≥900）：左 220 只接管「筛选」（级别 chips + 时间范围）；右栏原样
  // -------------------------------------------------------------------------

  Widget _buildWideBody(
    BuildContext context, {
    required bool enabled,
    required List<DiagnosticsLogEntry> allLogs,
    required List<DiagnosticsLogEntry> filteredLogs,
    required DiagnosticsFilterState filter,
    required bool isSelectionMode,
    required Set<String> selectedIds,
  }) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    // 窄屏里 chips 行只在「开启 / 有日志」时出现；左栏承接的正是那排 chips，
    // 故沿用同一条件（不新增「窄屏看不到、宽屏凭空多出来」的入口）。
    final showsFilters = enabled || allLogs.isNotEmpty;
    final detailEntry = _wideDetailEntry;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左 220：只接管筛选（级别 → 全部 + V/D/I/W/E，级别色与计数全保留；
        // 时间范围同列在下面）。
        if (showsFilters)
          _buildFilterRail(context, filter: filter, allLogs: allLogs),
        Expanded(
          child: Column(
            children: [
              // 调试模式开关：原地不动
              _buildSwitchCard(context, enabled: enabled, isLight: isLight),

              if (showsFilters) ...[
                // 搜索框：原地不动
                _buildSearchField(context, isLight: isLight),
                // 计数 / 导出 / 清空日志：原地不动
                _buildActionRow(
                  context,
                  isLight: isLight,
                  allLogs: allLogs,
                  filteredLogs: filteredLogs,
                ),
              ],

              const SizedBox(height: 4),

              // 日志表铺满（表格型内容不限宽）；详情在右栏内展开
              Expanded(
                child: detailEntry != null && !isSelectionMode
                    ? _buildWideDetailPane(context, detailEntry)
                    : _buildLogContent(
                        context,
                        enabled: enabled,
                        allLogs: allLogs,
                        filteredLogs: filteredLogs,
                        isSelectionMode: isSelectionMode,
                        selectedIds: selectedIds,
                      ),
              ),

              if (isSelectionMode)
                _buildSelectionBar(
                  context,
                  isLight: isLight,
                  filteredLogs: filteredLogs,
                  selectedIds: selectedIds,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 左栏筛选导航：级别（全部 + V/D/I/W/E）+ 时间范围。
  ///
  /// 计数口径 = **库内各级日志条数**（不做级别/时间/搜索过滤），「全部」= 总数：
  /// 它是一个稳定的「级别分布」读数，与右栏 `选中/总数` 的筛选计数分工不同
  /// （后者回答「当前筛选剩下几条」，前者回答「各级共几条」）。为避免与 providers
  /// 里的过滤逻辑分叉，这里刻意不重复实现过滤管线。
  Widget _buildFilterRail(
    BuildContext context, {
    required DiagnosticsFilterState filter,
    required List<DiagnosticsLogEntry> allLogs,
  }) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final counts = <DiagnosticsLogLevel, int>{
      for (final level in DiagnosticsLogLevel.values) level: 0,
    };
    for (final log in allLogs) {
      counts[log.level] = (counts[log.level] ?? 0) + 1;
    }
    final blue = statusBlueText.resolveFrom(context);
    final levelAllSelected =
        filter.selectedLevels.length >= DiagnosticsLogLevel.values.length;

    return WideNavRail(
      key: const ValueKey('diagnostics-nav-rail'),
      children: [
        // 级别：全部（「全」色块，样式同各级：选中才显色）
        _DiagnosticsRailRow(
          key: const ValueKey('diagnostics-nav-all'),
          letter: '全',
          label: l10n.all,
          count: allLogs.length,
          selected: levelAllSelected,
          tint: isLight ? LightSurfaces.selection : blue.withValues(alpha: 0.2),
          levelColor: blue,
          onTap: _selectAllLevels,
        ),
        for (final level in DiagnosticsLogLevel.values)
          _DiagnosticsRailRow(
            key: ValueKey('diagnostics-nav-level-${level.code}'),
            letter: level.code,
            label: _levelName(l10n, level),
            count: counts[level] ?? 0,
            // chips 的既有显色规则原样保留：**选中才显级别色**，未选中一律灰底灰字。
            selected: filter.selectedLevels.contains(level),
            tint: isLight
                ? _levelTint(level)
                : level.textColor.resolveFrom(context).withValues(alpha: 0.2),
            levelColor: level.textColor.resolveFrom(context),
            onTap: () {
              ref.read(diagnosticsFilterProvider.notifier).toggleLevel(level);
            },
          ),

        const WideNavRailSeparator(),
        WideNavRailGroupLabel(_timeRangeGroupLabel(l10n)),

        // 时间范围：与级别同列、放在其下（含「全部」，与窄屏 chips 一一对应）
        for (final timeFilter in DiagnosticsTimeFilter.values)
          _DiagnosticsRailRow(
            key: ValueKey('diagnostics-nav-time-${timeFilter.name}'),
            label: _timeFilterLabel(l10n, timeFilter),
            selected: filter.timeFilter == timeFilter,
            onTap: () {
              ref
                  .read(diagnosticsFilterProvider.notifier)
                  .setTimeFilter(timeFilter);
            },
          ),
      ],
    );
  }

  /// 宽屏右栏内联详情（不再 push 整页；正文与窄屏 sheet 同源）。
  Widget _buildWideDetailPane(BuildContext context, DiagnosticsLogEntry entry) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final actionColor = isLight
        ? LightSurfaces.menuAction
        : CupertinoTheme.of(context).primaryColor;
    final backLabel = CupertinoLocalizations.of(context).backButtonLabel;

    return Column(
      key: const ValueKey('diagnostics-wide-detail'),
      children: [
        SizedBox(
          height: 44,
          child: Stack(
            children: [
              Center(
                child: Text(
                  l10n.diagnosticsDetailsTitle,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    CupertinoButton(
                      key: const ValueKey('diagnostics-wide-detail-back'),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(44, 44),
                      onPressed: () => setState(() => _wideDetailEntry = null),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.chevron_left,
                            size: 18,
                            color: actionColor,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            backLabel,
                            style: TextStyle(fontSize: 16, color: actionColor),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      key: const ValueKey('diagnostics-wide-detail-copy'),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(44, 44),
                      onPressed: () =>
                          unawaited(copyDiagnosticsEntry(context, entry)),
                      child: Text(
                        l10n.copy,
                        style: TextStyle(fontSize: 16, color: actionColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 0.5,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
        ),
        Expanded(child: DiagnosticsDetailBody(entry: entry)),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 宽窄共用的四段（搬迁时**原样搬运**，位置与样式都不改）
  // -------------------------------------------------------------------------

  /// 调试模式开关卡。
  Widget _buildSwitchCard(
    BuildContext context, {
    required bool enabled,
    required bool isLight,
  }) {
    final l10n = AppLocalizations.of(context);
    return CupertinoListSection.insetGrouped(
      dividerMargin: 0,
      additionalDividerMargin: 0,
      backgroundColor: LightSurfaces.resolve(
        context,
        LightSurfaces.page,
        dark: CupertinoColors.systemGroupedBackground,
      ),
      separatorColor: isLight ? LightSurfaces.divider : null,
      decoration: isLight
          ? BoxDecoration(
              color: LightSurfaces.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
            )
          : null,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      children: [
        CupertinoListTile(
          key: const ValueKey('diagnostics-switch-tile'),
          title: Text(l10n.diagnosticsEnabled),
          subtitle: Text(
            l10n.diagnosticsEnabledDesc,
            style: TextStyle(
              fontSize: 12,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
          trailing: SettingsSurfaces.toggle(
            context,
            CupertinoSwitch(
              key: const ValueKey('diagnostics-switch-enable'),
              value: enabled,
              onChanged: (val) {
                unawaited(
                  ref.read(diagnosticsEnabledProvider.notifier).setEnabled(val),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 搜索框。
  Widget _buildSearchField(BuildContext context, {required bool isLight}) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: CupertinoSearchTextField(
        key: const ValueKey('diagnostics-search-field'),
        controller: _searchController,
        placeholder: l10n.diagnosticsSearchPlaceholder,
        decoration: isLight
            ? BoxDecoration(
                color: LightSurfaces.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
              )
            : null,
        placeholderStyle: isLight
            ? const TextStyle(color: LightSurfaces.placeholder)
            : null,
        itemColor: LightSurfaces.resolve(
          context,
          LightSurfaces.textSecondary,
          dark: CupertinoColors.secondaryLabel,
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  /// 级别 + 时间 chips 行（**只给窄屏**：宽屏已搬进左栏筛选导航）。
  Widget _buildFilterChipsRow(
    BuildContext context,
    DiagnosticsFilterState filter,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Level Chips
            for (final level in DiagnosticsLogLevel.values) ...[
              _buildLevelChip(
                context,
                level: level,
                isSelected: filter.selectedLevels.contains(level),
                onTap: () {
                  ref
                      .read(diagnosticsFilterProvider.notifier)
                      .toggleLevel(level);
                },
              ),
              const SizedBox(width: 6),
            ],
            const SizedBox(width: 8),
            // Time Chips
            for (final tf in DiagnosticsTimeFilter.values) ...[
              _buildTimeChip(
                context,
                filter: tf,
                isSelected: filter.timeFilter == tf,
                onTap: () {
                  ref
                      .read(diagnosticsFilterProvider.notifier)
                      .setTimeFilter(tf);
                },
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// 计数（`筛选后 / 总数`）+ 导出 + 清空日志。
  Widget _buildActionRow(
    BuildContext context, {
    required bool isLight,
    required List<DiagnosticsLogEntry> allLogs,
    required List<DiagnosticsLogEntry> filteredLogs,
  }) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '${filteredLogs.length} / ${allLogs.length}',
            style: TextStyle(
              fontSize: 12,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            key: const ValueKey('diagnostics-export-btn'),
            onPressed: allLogs.isEmpty ? null : () => unawaited(_exportLogs()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.share,
                  size: 16,
                  color: isLight && allLogs.isNotEmpty
                      ? LightSurfaces.userDetail
                      : null,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.diagnosticsExport,
                  style: TextStyle(
                    fontSize: 13,
                    color: isLight && allLogs.isNotEmpty
                        ? LightSurfaces.userDetail
                        : null,
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            key: const ValueKey('diagnostics-clear-btn'),
            onPressed: allLogs.isEmpty
                ? null
                : () => unawaited(_confirmClearLogs()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.trash,
                  size: 16,
                  color: isLight && allLogs.isNotEmpty
                      ? LightSurfaces.userDetail
                      : null,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.diagnosticsClear,
                  style: TextStyle(
                    fontSize: 13,
                    color: isLight && allLogs.isNotEmpty
                        ? LightSurfaces.userDetail
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 多选模式底部操作栏。
  Widget _buildSelectionBar(
    BuildContext context, {
    required bool isLight,
    required List<DiagnosticsLogEntry> filteredLogs,
    required Set<String> selectedIds,
  }) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemGroupedBackground,
        ),
        border: Border(
          top: BorderSide(
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.divider,
              dark: CupertinoColors.separator,
            ),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              final allIds = filteredLogs.map((e) => e.id).toSet();
              final isAllSelected = selectedIds.length == allIds.length;
              if (isAllSelected) {
                ref.read(diagnosticsSelectedIdsProvider.notifier).clear();
              } else {
                ref
                    .read(diagnosticsSelectedIdsProvider.notifier)
                    .setSelected(allIds);
              }
            },
            child: Text(
              selectedIds.length == filteredLogs.length &&
                      filteredLogs.isNotEmpty
                  ? l10n.cancel
                  : l10n.selectAll,
              style: TextStyle(
                fontSize: 14,
                color: isLight ? LightSurfaces.menuAction : null,
              ),
            ),
          ),
          const Spacer(),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            key: const ValueKey('diagnostics-copy-selected-btn'),
            color: isLight ? LightSurfaces.userDetail : null,
            onPressed: selectedIds.isEmpty
                ? null
                : () => unawaited(_copySelectedLogs(filteredLogs, selectedIds)),
            child: Text(
              l10n.diagnosticsCopySelected,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelChip(
    BuildContext context, {
    required DiagnosticsLogLevel level,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final color = level.textColor.resolveFrom(context);
    final unselectedBg = isLight
        ? LightSurfaces.page
        : CupertinoColors.systemGrey6.resolveFrom(context);
    final unselectedBorder = isLight
        ? LightSurfaces.cardBorder
        : CupertinoColors.systemGrey4.resolveFrom(context);
    final unselectedText = isLight
        ? LightSurfaces.textSecondary
        : secondaryText.resolveFrom(context);

    return GestureDetector(
      key: ValueKey('diagnostics-filter-level-${level.code}'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? _levelTint(level) : color.withValues(alpha: 0.2))
              : unselectedBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : unselectedBorder,
            width: 1,
          ),
        ),
        child: Text(
          level.code,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? color : unselectedText,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeChip(
    BuildContext context, {
    required DiagnosticsTimeFilter filter,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final l10n = AppLocalizations.of(context);
    final label = _timeFilterLabel(l10n, filter);

    final activeColor = statusBlueText.resolveFrom(context);
    final unselectedBg = isLight
        ? LightSurfaces.page
        : CupertinoColors.systemGrey6.resolveFrom(context);
    final unselectedBorder = isLight
        ? LightSurfaces.cardBorder
        : CupertinoColors.systemGrey4.resolveFrom(context);
    final unselectedText = isLight
        ? LightSurfaces.textSecondary
        : secondaryText.resolveFrom(context);

    return GestureDetector(
      key: ValueKey('diagnostics-filter-time-${filter.name}'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          // L2：分段控件选中底改中性灰 .16；前景仍是 statusBlueText(#005FB8)。
          color: isSelected
              ? (isLight
                    ? LightSurfaces.selectedSurface
                    : activeColor.withValues(alpha: 0.15))
              : unselectedBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? activeColor : unselectedBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? activeColor : unselectedText,
          ),
        ),
      ),
    );
  }

  Widget _buildLogContent(
    BuildContext context, {
    required bool enabled,
    required List<DiagnosticsLogEntry> allLogs,
    required List<DiagnosticsLogEntry> filteredLogs,
    required bool isSelectionMode,
    required Set<String> selectedIds,
  }) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;

    if (!enabled && allLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.waveform_path_badge_plus,
              size: 48,
              color: isLight
                  ? LightSurfaces.textSecondary
                  : CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.diagnosticsEmptyDisabled,
              style: TextStyle(
                fontSize: 14,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (allLogs.isEmpty) {
      return Center(
        child: Text(
          l10n.diagnosticsEmptyNoLogs,
          style: TextStyle(
            fontSize: 14,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
        ),
      );
    }

    if (filteredLogs.isEmpty) {
      return Center(
        child: Text(
          l10n.diagnosticsEmptyNoMatch,
          style: TextStyle(
            fontSize: 14,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('diagnostics-log-list'),
      itemCount: filteredLogs.length,
      itemBuilder: (context, index) {
        final entry = filteredLogs[index];
        final isSelected = selectedIds.contains(entry.id);
        return _DiagnosticsLogRow(
          key: ValueKey(entry.id),
          entry: entry,
          isSelectionMode: isSelectionMode,
          isSelected: isSelected,
          onTap: () {
            if (isSelectionMode) {
              ref
                  .read(diagnosticsSelectedIdsProvider.notifier)
                  .toggle(entry.id);
            } else {
              _openDetail(entry);
            }
          },
        );
      },
    );
  }
}

/// 宽屏左栏筛选行：可选「级别字母色块」+ 名称 + 计数（时间范围行无前两者）。
///
/// 行高 32 / 圆角 7 / 文案 12.5pt / 左右内边距 10、选中态走 L2（中性灰底 +
/// 蓝字）—— 与共享骨架 `features/shared/wide_nav_rail.dart::WideNavRailRow`
/// 同一套尺寸；差别只有两处：首列是可着级别色的字母色块（不是 16pt 图标）、
/// 尾部带计数。共享骨架只提供 icon/label 两个槽位，而本批文件级分区禁止改
/// `features/shared/**`，故按同款尺寸就地实现。
///
/// 显色规则沿用 chips：**选中才显级别色**（[tint] + [levelColor]），未选中一律
/// 灰底灰字（与真机 chips 的语义一致）。
class _DiagnosticsRailRow extends StatelessWidget {
  const _DiagnosticsRailRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.letter,
    this.count,
    this.tint,
    this.levelColor,
  });

  /// 级别字母（`全` / `V` / `D` / `I` / `W` / `E`）；时间范围行为 null。
  final String? letter;

  /// 行名称（级别名 / 时间范围名）。
  final String label;

  /// 行尾计数（级别行有，时间范围行没有）。
  final int? count;

  final bool selected;
  final VoidCallback onTap;

  /// 选中时字母色块底（各级 tint；「全部」用蓝色 tint）。
  final Color? tint;

  /// 选中时字母色块描边与字母色（各级 `level.textColor`）。
  final Color? levelColor;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    // L2 选中态：浅色中性灰 .16 + #005FB8 前景；暗色沿用 primary 12%（取值不变）。
    final activeFg = isLight
        ? LightSurfaces.selectionForeground
        : CupertinoTheme.of(context).primaryColor;
    final activeBg = isLight
        ? LightSurfaces.selectedSurface
        : activeFg.withValues(alpha: 0.12);
    final labelFg = selected
        ? activeFg
        : LightSurfaces.resolve(
            context,
            _kRailRowLabel,
            dark: CupertinoColors.label,
          );
    final unselectedBg = isLight
        ? LightSurfaces.page
        : CupertinoColors.systemGrey6.resolveFrom(context);
    final unselectedBorder = isLight
        ? LightSurfaces.cardBorder
        : CupertinoColors.systemGrey4.resolveFrom(context);
    final unselectedText = isLight
        ? LightSurfaces.textSecondary
        : secondaryText.resolveFrom(context);
    final countFg = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(double.infinity, 32),
          borderRadius: BorderRadius.circular(kRadiusInline),
          color: selected ? activeBg : CupertinoColors.transparent,
          onPressed: onTap,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (letter != null)
                    Container(
                      width: 20,
                      height: 16,
                      decoration: BoxDecoration(
                        color: selected ? (tint ?? unselectedBg) : unselectedBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: selected
                              ? (levelColor ?? unselectedBorder)
                              : unselectedBorder,
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        letter!,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: selected
                              ? (levelColor ?? unselectedText)
                              : unselectedText,
                        ),
                      ),
                    )
                  else
                    // 时间范围行：名称列与级别行对齐（色块 20 + 间隙 9）。
                    const SizedBox(width: 29),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: labelFg),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(fontSize: 11.5, color: countFg),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单条诊断日志行组件。
class _DiagnosticsLogRow extends StatelessWidget {
  const _DiagnosticsLogRow({
    super.key,
    required this.entry,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
  });

  final DiagnosticsLogEntry entry;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final color = entry.level.textColor.resolveFrom(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          // L2：选中的日志行底同步换中性灰 .16（同级单位：选中行）。
          color: isSelected
              ? (isLight
                    ? LightSurfaces.selectedSurface
                    : statusBlueText
                          .resolveFrom(context)
                          .withValues(alpha: 0.1))
              : null,
          border: Border(
            bottom: BorderSide(
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.divider,
                dark: CupertinoColors.separator,
              ),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSelectionMode) ...[
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 2),
                child: Icon(
                  isSelected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  color: isSelected
                      ? statusBlueText.resolveFrom(context)
                      : (isLight
                            ? LightSurfaces.textSecondary
                            : CupertinoColors.systemGrey),
                  size: 20,
                ),
              ),
            ],
            // 级别徽标
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isLight
                    ? _levelTint(entry.level)
                    : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: color.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: Text(
                entry.level.code,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 主体信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0.5,
                        ),
                        decoration: BoxDecoration(
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.page,
                            dark: CupertinoColors.systemGrey5,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entry.tag,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.textSecondary,
                              dark: secondaryText,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatLogTimeOnly(entry.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: secondaryText,
                          ),
                        ),
                      ),
                      if (entry.durationMs != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${entry.durationMs}ms',
                          style: TextStyle(
                            fontSize: 11,
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.textSecondary,
                              dark: secondaryText,
                            ),
                          ),
                        ),
                      ],
                      if (entry.errorKind != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          entry.errorKind!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusRedText.resolveFrom(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            if (!isSelectionMode)
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: isLight
                    ? LightSurfaces.textSecondary
                    : const Color(0xFFC7C7CC),
              ),
          ],
        ),
      ),
    );
  }
}
