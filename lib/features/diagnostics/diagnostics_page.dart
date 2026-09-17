import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/hermes_page_route.dart';
import '../../core/utils/safe_clipboard.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_surfaces.dart';
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

/// 诊断日志主页面（纯 Cupertino 风格，零 Material 组件）。
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;

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
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.diagnosticsClear),
        content: Text(l10n.diagnosticsConfirmClear),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            key: const ValueKey('diagnostics-clear-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.clear,
              style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                  ? const TextStyle(color: Color(0xFFB3001B))
                  : null,
            ),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.cancel,
              style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                  ? const TextStyle(color: LightSurfaces.menuAction)
                  : null,
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(diagnosticsLogsProvider.notifier).clear();
    }
  }

  void _showAlert(String title, String message) {
    final l10n = AppLocalizations.of(context);
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                l10n.ok,
                style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                    ? const TextStyle(color: LightSurfaces.menuAction)
                    : null,
              ),
            ),
          ],
        ),
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
                      onPressed: () {
                        ref
                            .read(diagnosticsIsSelectionModeProvider.notifier)
                            .setMode(true);
                      },
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
        child: Column(
          children: [
            // 开关区
            CupertinoListSection.insetGrouped(
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
                      border: Border.all(
                        color: LightSurfaces.cardBorder,
                        width: 0.5,
                      ),
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
                          ref
                              .read(diagnosticsEnabledProvider.notifier)
                              .setEnabled(val),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),

            // 搜索与筛选工具栏（仅在开启或有日志时展示）
            if (enabled || allLogs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: CupertinoSearchTextField(
                  key: const ValueKey('diagnostics-search-field'),
                  controller: _searchController,
                  placeholder: l10n.diagnosticsSearchPlaceholder,
                  decoration: isLight
                      ? BoxDecoration(
                          color: LightSurfaces.card,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: LightSurfaces.cardBorder,
                            width: 0.5,
                          ),
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
              ),

              // 级别筛选与时间筛选 Chips
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
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
              ),

              // 操作按钮栏（导出、清空、条数统计）
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      key: const ValueKey('diagnostics-export-btn'),
                      onPressed: allLogs.isEmpty
                          ? null
                          : () => unawaited(_exportLogs()),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
                        final isAllSelected =
                            selectedIds.length == allIds.length;
                        if (isAllSelected) {
                          ref
                              .read(diagnosticsSelectedIdsProvider.notifier)
                              .clear();
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      key: const ValueKey('diagnostics-copy-selected-btn'),
                      color: isLight ? LightSurfaces.userDetail : null,
                      onPressed: selectedIds.isEmpty
                          ? null
                          : () => unawaited(
                              _copySelectedLogs(filteredLogs, selectedIds),
                            ),
                      child: Text(
                        l10n.diagnosticsCopySelected,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
    String label;
    switch (filter) {
      case DiagnosticsTimeFilter.all:
        label = l10n.diagnosticsTimeRangeAll;
      case DiagnosticsTimeFilter.today:
        label = l10n.diagnosticsTimeRangeToday;
      case DiagnosticsTimeFilter.last7Days:
        label = l10n.diagnosticsTimeRangeLast7Days;
      case DiagnosticsTimeFilter.custom:
        label = l10n.diagnosticsTimeRangeCustom;
    }

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
          color: isSelected
              ? (isLight
                    ? LightSurfaces.selection
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
              _showDetailSheet(entry);
            }
          },
        );
      },
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
          color: isSelected
              ? (isLight
                    ? LightSurfaces.selection
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
