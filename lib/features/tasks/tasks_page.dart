import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_action_menu.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../app/widgets/hermes_page_route.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/cron.dart';
import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_surfaces.dart';
import '../shared/app_back_button.dart';
import 'tasks_providers.dart';

/// 任务状态文案（运行中 / 已暂停 / 已停用 / 出错 / 需关注 / 正常）。
///
/// `state == 'running'` 优先于 [CronJob.status]（运行是瞬时态，status 枚举
/// 不区分）。
String taskStatusLabel(CronJob job, [BuildContext? context]) {
  if (context != null) {
    final l10n = AppLocalizations.of(context);
    if (job.state == 'running') return l10n.taskStatusRunning;
    switch (job.status) {
      case CronJobStatus.active:
        return l10n.taskStatusActive;
      case CronJobStatus.paused:
        return l10n.taskStatusPaused;
      case CronJobStatus.off:
        return l10n.taskStatusOff;
      case CronJobStatus.error:
        return l10n.taskStatusError;
      case CronJobStatus.needsAttention:
        return l10n.taskStatusNeedsAttention;
    }
  }
  if (job.state == 'running') return '运行中';
  switch (job.status) {
    case CronJobStatus.active:
      return '正常';
    case CronJobStatus.paused:
      return '已暂停';
    case CronJobStatus.off:
      return '已停用';
    case CronJobStatus.error:
      return '出错';
    case CronJobStatus.needsAttention:
      return '需关注';
  }
}

/// 任务状态标识颜色（与 [taskStatusLabel] 一一对应）。
///
/// 返回 [CupertinoDynamicColor]：圆点与文字共用，浅色/深色均满足 WCAG AA
/// （浅色用深变体、深色用亮变体，见 theme/status_colors.dart）。
CupertinoDynamicColor taskStatusColor(CronJob job) {
  if (job.state == 'running') return statusGreenText;
  switch (job.status) {
    case CronJobStatus.active:
      return statusBlueText;
    case CronJobStatus.paused:
      return statusOrangeText;
    case CronJobStatus.off:
      return statusGreyText;
    case CronJobStatus.error:
      return statusRedText;
    case CronJobStatus.needsAttention:
      return statusOrangeText;
  }
}

/// 定时任务管理页（`/tasks`）。
///
/// Cupertino 风格：大标题 + 新建按钮 + 下拉刷新 + 任务列表（状态圆点 + 名称 +
/// 调度/上次运行 + ellipsis 行菜单：运行 / 暂停 / 恢复 / 编辑 / 查看输出 / 删除）
/// + 加载 / 错误 / 空态。新建与编辑共用 [TasksEditPage] 表单页。
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(tasksControllerProvider);
    final state = async.valueOrNull;

    ref.listen<AsyncValue<TasksState>>(tasksControllerProvider, (
      previous,
      next,
    ) {
      final error = next.valueOrNull?.actionError;
      if (error != null && error != previous?.valueOrNull?.actionError) {
        unawaited(_showActionError(context, error));
      }
    });

    final content = CupertinoPageScaffold(
      backgroundColor: isLight ? LightSurfaces.page : null,
      child: CustomScrollView(
        key: const ValueKey('tasks-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.tasksTitle,
            leading: const AppBackButton(),
            trailing: AccessibleButton(
              key: const ValueKey('tasks-create'),
              label: l10n.newTask,
              padding: EdgeInsets.zero,
              onPressed: () => _openEditor(context),
              child: const Icon(CupertinoIcons.add),
            ),
          ),
          // 刷新指示器必须排在所有 SliverToBoxAdapter 之前（对齐会话列表页）。
          CupertinoSliverRefreshControl(onRefresh: _onRefresh),
          ..._buildContentSlivers(async, state),
        ],
      ),
    );

    return isLight
        ? CupertinoTheme(
            data: CupertinoTheme.of(context).copyWith(
              primaryColor: statusBlueText.resolveFrom(context),
              scaffoldBackgroundColor: LightSurfaces.page,
              barBackgroundColor: LightSurfaces.page,
            ),
            child: content,
          )
        : content;
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 任务列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<TasksState> async,
    TasksState? state,
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
      return [_buildErrorSliver(async.error)];
    }

    if (state.jobs.isEmpty) {
      return [_buildEmptySliver()];
    }

    // 分组：正常状态一组 / 暂停状态一组（用户要求分开显示）。
    final runningJobs = state.jobs
        .where((j) => j.status != CronJobStatus.paused)
        .toList();
    final pausedJobs = state.jobs
        .where((j) => j.status == CronJobStatus.paused)
        .toList();

    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;

    Widget rowsSection({required String header, required List<CronJob> jobs}) {
      return SliverToBoxAdapter(
        child: CupertinoListSection.insetGrouped(
          backgroundColor: isLight
              ? LightSurfaces.page
              : CupertinoColors.systemGroupedBackground,
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
          dividerMargin: 0,
          additionalDividerMargin: 0,
          hasLeading: false,
          header: Text(
            '$header（${jobs.length}）',
            style: isLight
                ? const TextStyle(color: LightSurfaces.textSecondary)
                : null,
          ),
          children: [
            for (final job in jobs)
              _TaskRow(
                key: ValueKey('tasks-row-${job.jobId ?? job.id}'),
                job: job,
                busy: state.isBusy(job.jobId ?? ''),
                onTap: () => unawaited(_showOutput(context, job)),
                onActions: (anchorKey) =>
                    _showRowActions(context, job, anchorKey),
              ),
          ],
        ),
      );
    }

    return [
      if (runningJobs.isNotEmpty)
        rowsSection(header: l10n.statusNormal, jobs: runningJobs),
      if (pausedJobs.isNotEmpty)
        rowsSection(header: l10n.statusPaused, jobs: pausedJobs),
    ];
  }

  Widget _buildErrorSliver(Object? error) {
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
                dark: CupertinoColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('tasks-retry'),
              onPressed: () => unawaited(_onRefresh()),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver() {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.clock,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.noTasks, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              l10n.createTaskPrompt,
              style: TextStyle(
                fontSize: 13,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('tasks-empty-create'),
              onPressed: () => _openEditor(context),
              child: Text(l10n.newTask),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 交互：刷新 / 行菜单 / 输出 / 删除 / 表单
  // -------------------------------------------------------------------------

  Future<void> _onRefresh() =>
      ref.read(tasksControllerProvider.notifier).refresh();

  void _openEditor(BuildContext context, {CronJob? job}) {
    Navigator.of(context)
        .push(HermesPageRoute<void>(builder: (_) => TasksEditPage(job: job)));
  }

  void _showRowActions(BuildContext context, CronJob job, GlobalKey anchorKey) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(tasksControllerProvider.notifier);
    final paused = job.state == 'paused' || job.enabled == false;
    final items = [
      AdaptiveMenuItem(
        key: const ValueKey('tasks-action-run'),
        label: l10n.runTask,
        onPressed: () => unawaited(controller.run(job)),
      ),
      if (paused)
        AdaptiveMenuItem(
          key: const ValueKey('tasks-action-resume'),
          label: l10n.resumeTask,
          onPressed: () => unawaited(controller.resume(job)),
        )
      else
        AdaptiveMenuItem(
          key: const ValueKey('tasks-action-pause'),
          label: l10n.pauseTask,
          onPressed: () => unawaited(controller.pause(job)),
        ),
      AdaptiveMenuItem(
        key: const ValueKey('tasks-action-edit'),
        label: l10n.edit,
        onPressed: () => _openEditor(context, job: job),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('tasks-action-output'),
        label: l10n.viewOutput,
        onPressed: () => unawaited(_showOutput(context, job)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('tasks-action-delete'),
        isDestructive: true,
        label: l10n.delete,
        onPressed: () => unawaited(_confirmDelete(context, job)),
      ),
    ];

    unawaited(
      AdaptiveActionMenu.show(
        context,
        anchorKey: anchorKey,
        items: items,
        title: job.displayName,
        cancelLabel: l10n.cancel,
        cancelKey: const ValueKey('tasks-action-cancel'),
      ),
    );
  }

  Future<void> _showOutput(BuildContext context, CronJob job) async {
    final future = ref.read(tasksControllerProvider.notifier).fetchOutput(job);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => _TaskOutputSheet(outputFuture: future),
    );
  }

  Future<void> _confirmDelete(BuildContext context, CronJob job) async {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.deleteTask),
        content: Text(l10n.confirmDeleteTask(job.displayName)),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('tasks-delete-cancel'),
            textStyle: isLight
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('tasks-delete-confirm'),
            isDestructiveAction: true,
            textStyle: isLight
                ? TextStyle(color: statusRedText.resolveFrom(dialogContext))
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(tasksControllerProvider.notifier).delete(job);
    }
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.actionFailed),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('tasks-error-ok'),
            textStyle: isLight
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    await ref.read(tasksControllerProvider.notifier).clearActionError();
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

/// 单行任务：状态圆点 + 名称 + 状态标签 + 调度/上次运行 + ellipsis 操作按钮。
class _TaskRow extends StatefulWidget {
  const _TaskRow({
    super.key,
    required this.job,
    required this.busy,
    required this.onTap,
    required this.onActions,
  });

  final CronJob job;
  final bool busy;
  final VoidCallback onTap;
  final void Function(GlobalKey anchorKey) onActions;

  @override
  State<_TaskRow> createState() => _TaskRowState();

  static String? _subtitle(BuildContext context, CronJob job) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[
      if (job.scheduleText != null && job.scheduleText!.isNotEmpty)
        job.scheduleText!,
      if (job.lastRunAt != null)
        l10n.lastRunTime(_formatTime(job.lastRunAt!.date)),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _TaskRowState extends State<_TaskRow> {
  final GlobalKey _actionKey = GlobalKey();
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final subtitle = _TaskRow._subtitle(context, widget.job);
    final statusColor = taskStatusColor(widget.job).resolveFrom(context);

    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.job.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      taskStatusLabel(widget.job, context),
                      style: TextStyle(fontSize: 12, color: statusColor),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
              ],
            ),
          ),
          if (widget.busy)
            const Padding(
              padding: EdgeInsets.all(10),
              child: CupertinoActivityIndicator(radius: 9),
            )
          else
            KeyedSubtree(
              key: _actionKey,
              child: AccessibleButton(
                key: ValueKey(
                  'tasks-actions-${widget.job.jobId ?? widget.job.id}',
                ),
                label: l10n.taskActions,
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed: () => widget.onActions(_actionKey),
                child: Icon(
                  CupertinoIcons.ellipsis,
                  size: 20,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: '${widget.job.displayName}, ${l10n.viewOutput}',
      hint: l10n.viewOutput,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(selectionHaptic());
          widget.onTap();
        },
        onTapDown: isLight ? (_) => _setPressed(true) : null,
        onTapUp: isLight ? (_) => _setPressed(false) : null,
        onTapCancel: isLight ? () => _setPressed(false) : null,
        child: isLight
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: _pressed ? LightSurfaces.pressed : null,
                ),
                child: rowContent,
              )
            : rowContent,
      ),
    );
  }
}

/// 任务输出底部面板：加载中 → 输出列表（文件名 + 内容预览）→ 空态。
class _TaskOutputSheet extends StatelessWidget {
  const _TaskOutputSheet({required this.outputFuture});

  final Future<CronOutputResponse?> outputFuture;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final sheetBg = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: CupertinoColors.secondarySystemBackground,
    );
    final cardBg = LightSurfaces.resolve(
      context,
      LightSurfaces.card,
      dark: CupertinoColors.tertiarySystemBackground,
    );
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryLabelColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );
    final tertiaryLabelColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final separatorColor = LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: CupertinoColors.separator,
    );

    final sheetContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.taskOutput,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                ),
              ),
              AccessibleButton(
                key: const ValueKey('tasks-output-close'),
                label: l10n.closeOutputPanel,
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed: () => Navigator.pop(context),
                child: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 22,
                  color: tertiaryLabelColor,
                ),
              ),
            ],
          ),
        ),
        Container(height: 0.5, color: separatorColor),
        Flexible(
          child: FutureBuilder<CronOutputResponse?>(
            future: outputFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CupertinoActivityIndicator(radius: 12)),
                );
              }
              final outputs =
                  snapshot.data?.outputs ?? const <CronOutputItem>[];
              if (outputs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 36,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.doc_text,
                          size: 40,
                          color: tertiaryLabelColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.noOutput,
                          style: TextStyle(
                            fontSize: 15,
                            color: secondaryLabelColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                itemCount: outputs.length,
                separatorBuilder: (_, _) => Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: separatorColor,
                ),
                itemBuilder: (context, index) {
                  final item = outputs[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.doc,
                              size: 16,
                              color: secondaryLabelColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.filename ??
                                    l10n.outputItemTitle(index + 1),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: labelColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (item.content != null &&
                            item.content!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: separatorColor,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              item.content!,
                              maxLines: 10,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: labelColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );

    if (isLight) {
      return SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: const ValueKey('tasks-output-sheet'),
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.sizeOf(context).height * 0.65,
            ),
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: sheetContent,
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        key: const ValueKey('tasks-output-sheet'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
        ),
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: sheetContent,
      ),
    );
  }
}

/// 新建 / 编辑定时任务表单页（HermesPageRoute push 进入）。
///
/// 字段：名称（可选）/ 调度表达式（必填）/ 提示词（必填）/ 推送通知。
/// 调度表达式与提示词为空时保存按钮禁用（对齐 Hermex 编辑草稿校验）。
class TasksEditPage extends ConsumerStatefulWidget {
  const TasksEditPage({super.key, this.job});

  /// 非 null = 编辑模式（字段预填）；null = 新建。
  final CronJob? job;

  @override
  ConsumerState<TasksEditPage> createState() => _TasksEditPageState();
}

class _TasksEditPageState extends ConsumerState<TasksEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _scheduleController;
  late final TextEditingController _promptController;
  late bool _toastNotifications;
  bool _saving = false;

  bool get _isEdit => widget.job != null;

  bool get _canSave =>
      !_saving &&
      _scheduleController.text.trim().isNotEmpty &&
      _promptController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    _nameController = TextEditingController(text: job?.name ?? '');
    _scheduleController = TextEditingController(
      text: job?.editableScheduleText ?? '',
    );
    _promptController = TextEditingController(text: job?.prompt ?? '');
    _toastNotifications = job?.toastNotifications ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final l10n = AppLocalizations.of(context);
    final content = CupertinoPageScaffold(
      backgroundColor: isLight ? LightSurfaces.page : null,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: isLight ? LightSurfaces.page : null,
        border: isLight
            ? const Border(
                bottom: BorderSide(color: LightSurfaces.divider, width: 0.0),
              )
            : const CupertinoNavigationBar().border,
        middle: Text(_isEdit ? l10n.editTask : l10n.newTask),
        trailing: CupertinoButton(
          key: const ValueKey('tasks-form-save'),
          padding: EdgeInsets.zero,
          onPressed: _canSave ? () => unawaited(_save(context)) : null,
          child: Text(_isEdit ? l10n.save : l10n.create),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildField(
            label: l10n.taskName,
            fieldKey: const ValueKey('tasks-form-name'),
            controller: _nameController,
            placeholder: l10n.taskNamePlaceholder,
          ),
          const SizedBox(height: 16),
          _buildField(
            label: l10n.scheduleExpression,
            fieldKey: const ValueKey('tasks-form-schedule'),
            controller: _scheduleController,
            placeholder: l10n.schedulePlaceholder,
          ),
          const SizedBox(height: 16),
          _buildField(
            label: l10n.promptLabel,
            fieldKey: const ValueKey('tasks-form-prompt'),
            controller: _promptController,
            placeholder: l10n.promptPlaceholder,
            maxLines: 6,
          ),
          const SizedBox(height: 16),
          CupertinoListTile(
            title: Text(l10n.pushNotifications),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('tasks-form-toast'),
                value: _toastNotifications,
                onChanged: (value) =>
                    setState(() => _toastNotifications = value),
              ),
            ),
          ),
        ],
      ),
    );

    return isLight
        ? CupertinoTheme(
            data: CupertinoTheme.of(context).copyWith(
              primaryColor: statusBlueText.resolveFrom(context),
              scaffoldBackgroundColor: LightSurfaces.page,
              barBackgroundColor: LightSurfaces.page,
            ),
            child: DefaultSelectionStyle(
              selectionColor: LightSurfaces.selection,
              child: content,
            ),
          )
        : content;
  }

  Widget _buildField({
    required String label,
    required Key fieldKey,
    required TextEditingController controller,
    required String placeholder,
    int maxLines = 1,
  }) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          key: fieldKey,
          controller: controller,
          placeholder: placeholder,
          maxLines: maxLines,
          decoration: isLight
              ? BoxDecoration(
                  color: LightSurfaces.card,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: LightSurfaces.cardBorder,
                    width: 0.5,
                  ),
                )
              : const CupertinoTextField().decoration,
          placeholderStyle: isLight
              ? const TextStyle(
                  fontWeight: FontWeight.w400,
                  color: LightSurfaces.placeholder,
                )
              : const CupertinoTextField().placeholderStyle,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    setState(() => _saving = true);
    final controller = ref.read(tasksControllerProvider.notifier);
    final job = widget.job;
    final ok = job == null
        ? await controller.create(
            name: _nameController.text,
            schedule: _scheduleController.text.trim(),
            prompt: _promptController.text.trim(),
            toastNotifications: _toastNotifications,
          )
        : await controller.save(
            job,
            name: _nameController.text,
            schedule: _scheduleController.text.trim(),
            prompt: _promptController.text.trim(),
            toastNotifications: _toastNotifications,
          );
    if (!context.mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.maybePop(context);
    }
  }
}
