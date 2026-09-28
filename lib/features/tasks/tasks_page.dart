import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/layout_tokens.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/theme/typography_tokens.dart';
import '../../app/widgets/adaptive_action_menu.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../app/widgets/hermes_dialog.dart';
import '../../app/widgets/hermes_page_route.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/cron.dart';
import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_surfaces.dart';
import '../shared/app_back_button.dart';
import 'tasks_providers.dart';
import '../../app/widgets/app_refresh_control.dart';

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
///
/// 宽屏（≥900）双栏（批 4 · P4）：左 360 任务列表 + 右「任务输出」**常驻面板**，
/// 不再走底部 sheet（[showCupertinoModalPopup]）；窄屏（<900）原样保留 sheet，
/// 逐像素不变。
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  /// 宽屏（≥900）左栏当前选中的任务 id（`jobId ?? id`，与既有 key 同口径）；
  /// null = 未点过（右栏回落到第一个任务）。窄屏不使用。
  String? _selectedJobId;

  /// 宽屏右栏当前已加载/正在加载输出的任务 id 与其 future（配对保存，防止
  /// 快速切换任务时「任务 A 的 future 渲染成任务 B 的面板」）。
  String? _outputJobId;
  Future<CronOutputResponse?>? _outputFuture;

  /// 首帧占位（永不完成）：post-frame 取数前右栏显示加载态，避免先闪一帧
  /// 「暂无输出」再切到内容。
  static final Future<CronOutputResponse?> _pendingOutput =
      Completer<CronOutputResponse?>().future;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(tasksControllerProvider);
    final state = async.valueOrNull;
    // 宽屏双栏只在「有任务可拆」时启用：加载 / 错误 / 空态仍复用同一套单列状态页
    //（不为宽屏另造空态，状态页与窄屏完全同源）。
    final isWideSplit =
        isWideLayout(context) && state != null && state.jobs.isNotEmpty;

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
          AppRefreshControl(onRefresh: _onRefresh),
          // 窄屏（<900）：单列列表，点行 → 底部「任务输出」sheet —— 逐像素不变。
          if (!isWideSplit) ..._buildContentSlivers(async, state),
          // 宽屏（≥900）：左 360 列表 + 右「任务输出」常驻。
          if (isWideSplit)
            SliverToBoxAdapter(child: _buildWideSplitBody(state)),
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

  // -------------------------------------------------------------------------
  // 宽屏（≥900）双栏（批 4 · P4）
  //
  // 为什么撤 sheet：宽屏明明有地方把「任务输出」常驻在右栏，却仍用手机式的底部
  // 弹层 —— 看输出要弹、看完要关，弹层还盖住列表（没法一边看输出一边换任务）。
  // 拆右栏后：切任务即换右栏内容，输出跟着页面滚，不再有「关掉弹层」这一步。
  // 窄屏（<900）保持原 sheet（[_TaskOutputSheet] 原样保留、未删），逐像素不变。
  // -------------------------------------------------------------------------

  /// 左栏当前选中任务：优先 [_selectedJobId]；首帧或列表刷新后 id 消失时回落到
  /// 第一个任务 —— 宽屏右栏是**常驻面板**，不留空态。
  CronJob _resolveSelectedJob(List<CronJob> jobs) {
    final id = _selectedJobId;
    if (id != null) {
      for (final job in jobs) {
        if ((job.jobId ?? job.id) == id) return job;
      }
    }
    return jobs.first;
  }

  /// 切换右栏任务：取一次输出并换面板（`_outputJobId` 与 future 成对更新，
  /// 避免快速切换时把 A 的输出画到 B 的面板上）。
  Future<void> _selectJob(CronJob job) async {
    final id = job.jobId ?? job.id;
    final future = ref.read(tasksControllerProvider.notifier).fetchOutput(job);
    if (!mounted) return;
    setState(() {
      _selectedJobId = id;
      _outputJobId = id;
      _outputFuture = future;
    });
  }

  /// 保证右栏当前任务的输出已取过（每个任务取一次）。
  ///
  /// **不在 build 里发请求**：首帧由 post-frame 回调补一次 setState（那一帧右栏
  /// 显示加载态，见 [_pendingOutput]）。
  void _ensureWideOutput(CronJob job) {
    final id = job.jobId ?? job.id;
    if (_outputJobId == id && _outputFuture != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_selectJob(job));
    });
  }

  /// 宽屏主体：左栏（固定 360）+ 右栏「任务输出」常驻面板。
  Widget _buildWideSplitBody(TasksState state) {
    final selected = _resolveSelectedJob(state.jobs);
    _ensureWideOutput(selected);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildJobRail(state, selected),
        Expanded(child: _buildOutputPane(selected)),
      ],
    );
  }

  /// 左栏：固定宽 360、右侧 0.5px 发丝分栏线；沿用窄屏的「正常 / 已暂停」两组
  /// 分组口径，组内为任务行（状态圆点 / 名称 / 状态 / 调度 / 行菜单）。
  Widget _buildJobRail(TasksState state, CronJob selected) {
    final l10n = AppLocalizations.of(context);
    final runningJobs = state.jobs
        .where((j) => j.status != CronJobStatus.paused)
        .toList();
    final pausedJobs = state.jobs
        .where((j) => j.status == CronJobStatus.paused)
        .toList();
    final selectedId = selected.jobId ?? selected.id;

    Widget row(CronJob job) {
      final id = job.jobId ?? job.id;
      return _WideTaskRailRow(
        key: ValueKey('tasks-rail-row-$id'),
        job: job,
        selected: id == selectedId,
        busy: state.isBusy(job.jobId ?? ''),
        onTap: () => unawaited(_selectJob(job)),
        onActions: (anchorKey) => _showRowActions(context, job, anchorKey),
      );
    }

    return Container(
      key: const ValueKey('tasks-rail'),
      width: _kTaskRailWidth,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: _railSeparator(context), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (runningJobs.isNotEmpty) ...[
            _WideTaskRailGroupLabel(
              '${l10n.statusNormal}（${runningJobs.length}）',
            ),
            for (final job in runningJobs) row(job),
          ],
          if (pausedJobs.isNotEmpty) ...[
            _WideTaskRailGroupLabel(
              '${l10n.statusPaused}（${pausedJobs.length}）',
            ),
            for (final job in pausedJobs) row(job),
          ],
        ],
      ),
    );
  }

  /// 右栏：「任务输出」常驻面板 —— 标题 + 0.5px 分隔线 + 输出正文。
  ///
  /// 正文与窄屏 sheet 共用 [_TaskOutputBody]（文案 / 字号 / 分隔线完全一致，只有
  /// 外壳不同）；标题右侧放该任务的调度 / 上次运行，让面板自己说得清「这是谁」。
  Widget _buildOutputPane(CronJob job) {
    final l10n = AppLocalizations.of(context);
    final subtitle = _TaskRow._subtitle(context, job);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryLabelColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );
    final separatorColor = LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: CupertinoColors.separator,
    );

    return Column(
      key: const ValueKey('tasks-output-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Text(
                l10n.taskOutput,
                style: TextStyle(
                  fontSize: kFontPageTitle,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // TODO(type): 面板副标题属注解档 kFontCaption(12)，现值 13（按「值不动」保留）。
                    style: TextStyle(fontSize: kFontLabel, color: secondaryLabelColor),
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(height: 0.5, color: separatorColor),
        _TaskOutputBody(outputFuture: _outputFuture ?? _pendingOutput),
      ],
    );
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
              // TODO(type): 错误态标题属内容区标题档 kFontItemTitle(15)，现值 17（值不动）。
              style: const TextStyle(fontSize: kFontItemTitle, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(
                // TODO(type): 说明文字属注解档 kFontCaption(12)，现值 13（值不动）。
                fontSize: kFontLabel,
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
            // TODO(type): 空态标题属内容区标题档 kFontItemTitle(15)，现值 17（值不动）。
            Text(l10n.noTasks, style: const TextStyle(fontSize: kFontItemTitle)),
            const SizedBox(height: 6),
            Text(
              l10n.createTaskPrompt,
              style: TextStyle(
                // TODO(type): 空态提示属注解档 kFontCaption(12)，现值 13（值不动）。
                fontSize: kFontLabel,
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

  /// 新建 / 编辑定时任务 —— **一律 push 整页 [TasksEditPage]**（宽窄屏一致）。
  ///
  /// 注：批 5A 曾把宽屏改成 560 卡片弹窗（D1 样板），主人 2026-09-27 复验后判定
  /// 「定时任务还是整页」，故此处回退。**D2 的横排保留** —— [TasksEditPage] 内部
  /// 用的就是 [_TaskFormFields]（宽屏自动横排，窄屏竖排）。
  void _openEditor(BuildContext context, {CronJob? job}) {
    Navigator.of(context).push(
      HermesPageRoute<void>(builder: (_) => TasksEditPage(job: job)),
    );
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
        // 宽屏：右栏常驻面板直接把该任务切到选中态（不弹 sheet）；窄屏原样弹 sheet。
        onPressed: () => isWideLayout(context)
            ? unawaited(_selectJob(job))
            : unawaited(_showOutput(context, job)),
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

  /// 窄屏（<900）专用：底部「任务输出」sheet。宽屏不走这里 —— 右栏常驻面板
  /// 由 [_selectJob] 直接切内容，不弹层（同页 [showCupertinoModalPopup] 只在窄屏触发）。
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
    // 批 5 · C3：确认框迁到 D1 四档宽的 `confirm`（380）—— 窄屏仍是系统 alert。
    final confirmed = await showHermesDialog<bool>(
      context,
      kind: HermesDialogKind.confirm,
      title: (_) => Text(l10n.deleteTask),
      content: (_) => Text(l10n.confirmDeleteTask(job.displayName)),
      actions: [
        HermesDialogAction(
          key: const ValueKey('tasks-delete-cancel'),
          // 与改造前同落位：颜色走 `textStyle`（不是塞进 builder 的 Text），
          // 窄屏 `CupertinoDialogAction.textStyle` 因此保持非空（既有守卫在钉它）。
          textStyle: isLight
              ? const TextStyle(color: LightSurfaces.menuAction)
              : null,
          builder: (_) => Text(l10n.cancel),
          onPressed: (dialogContext) => Navigator.pop(dialogContext, false),
        ),
        HermesDialogAction(
          key: const ValueKey('tasks-delete-confirm'),
          isDestructiveAction: true,
          // 破坏性色同落位：`textStyle` + `statusRedText`（宽屏由基础设施同款合并）。
          textStyle: isLight
              ? TextStyle(color: statusRedText.resolveFrom(context))
              : null,
          builder: (_) => Text(l10n.delete),
          onPressed: (dialogContext) => Navigator.pop(dialogContext, true),
        ),
      ],
    );
    if (confirmed == true && mounted) {
      await ref.read(tasksControllerProvider.notifier).delete(job);
    }
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    // 批 5 · C3：单动作告警框 → `confirm`（380），窄屏仍是系统 alert。
    await showHermesDialog<void>(
      context,
      kind: HermesDialogKind.confirm,
      title: (_) => Text(l10n.actionFailed),
      content: (_) => Text(message),
      actions: [
        HermesDialogAction(
          key: const ValueKey('tasks-error-ok'),
          textStyle: isLight
              ? const TextStyle(color: LightSurfaces.menuAction)
              : null,
          builder: (_) => Text(l10n.ok),
          onPressed: (dialogContext) => Navigator.pop(dialogContext),
        ),
      ],
    );
    await ref.read(tasksControllerProvider.notifier).clearActionError();
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

// ---------------------------------------------------------------------------
// 宽屏（≥900）左栏令牌与行（批 4 · P4）
// ---------------------------------------------------------------------------

/// 左栏宽度 360（批 4 设计稿 P4「左 360 列表 + 右任务输出常驻」）。
///
/// 比技能页左栏（320）宽一档：这行要塞下「状态圆点 + 名称 + 状态标签 + 调度」，
/// 且右侧还要留行菜单按钮。
const double _kTaskRailWidth = 360.0;

/// 左栏行文字 / 次级元素取色 —— 与批 3 左栏骨架 `features/shared/wide_nav_rail.dart`
/// 及批 4 P2 技能左栏**同款取值**（浅色 #3A3A3C / #8A8A90，深色回退语义色）。
/// （骨架文件属批 3 分区、本批不改，故这里按同款取值重画，不改共享件。）
const Color _kRailRowLabel = Color(0xFF3A3A3C);
const Color _kRailRowIcon = Color(0xFF8A8A90);

/// 分栏线 / 发丝线：浅色与卡片描边同族，暗色沿用 separator。
Color _railSeparator(BuildContext context) => LightSurfaces.resolve(
  context,
  LightSurfaces.divider,
  dark: CupertinoColors.separator,
);

/// 宽屏左栏分组标题（10pt w600 次级灰；文案带「（n）」计数，沿用窄屏 section header
/// 的 `正常（3）` 口径）。
class _WideTaskRailGroupLabel extends StatelessWidget {
  const _WideTaskRailGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
      child: Text(
        label,
        style: TextStyle(
          // TODO(type): 栏内分组标题属分组档 kFontSectionTitle(13)，现值 10 仅侧栏专档同值；
          // 与骨架 wide_nav_rail 同款取值，是否随之统一到 13 待主人拍板（值不动）。
          fontSize: kFontSidebarSub,
          fontWeight: FontWeight.w600,
          color: LightSurfaces.resolve(
            context,
            _kRailRowIcon,
            dark: CupertinoColors.secondaryLabel,
          ),
        ),
      ),
    );
  }
}

/// 宽屏左栏任务行：状态圆点 + 名称 + 状态标签 + 调度/上次运行 + 行菜单按钮。
///
/// 选中态走 L2 —— 浅色「中性灰底 [LightSurfaces.selectedSurface] + 蓝字
/// [LightSurfaces.selectionForeground]」，暗色沿用 primary 12%（与批 3 的
/// `WideNavRailRow`、批 4 技能左栏同一套口径）。
/// 行菜单（运行 / 暂停 / 恢复 / 编辑 / 查看输出 / 删除）原样保留 —— 宽屏撤的只是
/// **输出 sheet**，不是行操作。
class _WideTaskRailRow extends StatefulWidget {
  const _WideTaskRailRow({
    super.key,
    required this.job,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onActions,
  });

  final CronJob job;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final void Function(GlobalKey anchorKey) onActions;

  @override
  State<_WideTaskRailRow> createState() => _WideTaskRailRowState();
}

class _WideTaskRailRowState extends State<_WideTaskRailRow> {
  final GlobalKey _actionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final activeFg = isLight
        ? LightSurfaces.selectionForeground
        : CupertinoTheme.of(context).primaryColor;
    final activeBg = isLight
        ? LightSurfaces.selectedSurface
        : activeFg.withValues(alpha: 0.12);
    final statusColor = taskStatusColor(widget.job).resolveFrom(context);
    final subtitle = _TaskRow._subtitle(context, widget.job);
    final labelFg = widget.selected
        ? activeFg
        : LightSurfaces.resolve(
            context,
            _kRailRowLabel,
            dark: CupertinoColors.label,
          );
    final secondaryFg = widget.selected
        ? activeFg
        : LightSurfaces.resolve(
            context,
            _kRailRowIcon,
            dark: CupertinoColors.secondaryLabel,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: '${widget.job.displayName}, ${l10n.viewOutput}',
        child: CupertinoButton(
          key: ValueKey('tasks-rail-tap-${widget.job.jobId ?? widget.job.id}'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(double.infinity, 40),
          borderRadius: BorderRadius.circular(kRadiusInline),
          color: widget.selected ? activeBg : CupertinoColors.transparent,
          onPressed: () {
            unawaited(selectionHaptic());
            widget.onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.job.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // 宽屏左栏行 = 栏内导航行档 kFontNavItem；内容区项名档 kFontItemTitle(15) 不适用本容器。
                                fontSize: kFontNavItem,
                                fontWeight: FontWeight.w600,
                                color: labelFg,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            taskStatusLabel(widget.job, context),
                            // TODO(type): 状态标签属注解档 kFontCaption(12)，现值 11（与窄屏行 12 同语义两值，值不动）。
                            style: TextStyle(fontSize: kFontMicro, color: statusColor),
                          ),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: kFontCaption, color: secondaryFg),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (widget.busy)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: CupertinoActivityIndicator(radius: 8),
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
                      minimumSize: const Size(32, 32),
                      onPressed: () => widget.onActions(_actionKey),
                      child: Icon(
                        CupertinoIcons.ellipsis,
                        size: 18,
                        color: secondaryFg,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
                          // TODO(type): 行名属内容区项名档 kFontItemTitle(15)，现值 17（与宽屏左栏行 13 同语义两值，值不动）。
                          fontSize: kFontPageTitle,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      taskStatusLabel(widget.job, context),
                      // 状态标签档 kFontCaption（宽屏左栏行为 11，同语义两值待收口）。
                      style: TextStyle(fontSize: kFontCaption, color: statusColor),
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
                      // TODO(type): 副标题属注解档 kFontCaption(12)，现值 13（与宽屏左栏行 12 同语义两值，值不动）。
                      fontSize: kFontLabel,
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

/// 任务输出正文（加载中 → 输出列表（文件名 + 内容预览）→ 空态）。
///
/// 宽屏右栏常驻面板（`_TasksPageState._buildOutputPane`）与窄屏底部 sheet
/// （[_TaskOutputSheet]）**共用同一份正文**：文案 / 字号 / 缩进 / 分隔线完全一致，
/// 两者只有外壳不同（sheet 多一个标题栏与关闭按钮，且限高 0.65 屏）。
/// 拆出这个部件的意义就是「撤 sheet，但内容不抄第二遍」。
class _TaskOutputBody extends StatelessWidget {
  const _TaskOutputBody({required this.outputFuture});

  final Future<CronOutputResponse?> outputFuture;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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

    return FutureBuilder<CronOutputResponse?>(
      future: outputFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CupertinoActivityIndicator(radius: 12)),
          );
        }
        final outputs = snapshot.data?.outputs ?? const <CronOutputItem>[];
        if (outputs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
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
                    // TODO(type): 空态说明文字误用项名档 kFontItemTitle(15)；说明档为 kFontCaption(12)（值不动）。
                    style: TextStyle(fontSize: kFontItemTitle, color: secondaryLabelColor),
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
                          item.filename ?? l10n.outputItemTitle(index + 1),
                          style: TextStyle(
                            // TODO(type): 输出条目名（名字）误用正文档 kFontBody(14)；项名档为 kFontItemTitle(15)（值不动）。
                            fontSize: kFontBody,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.content != null && item.content!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: separatorColor, width: 0.5),
                      ),
                      child: Text(
                        item.content!,
                        maxLines: 10,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // TODO(type): 等宽过程日志应为 kFontCode(12)（现值 13，且未设等宽字族；值不动）。
                          fontSize: kFontLabel,
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
    final labelColor = CupertinoColors.label.resolveFrom(context);
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
                    fontSize: kFontPageTitle,
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
        Flexible(child: _TaskOutputBody(outputFuture: outputFuture)),
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
          // 字段组与宽屏弹窗（`_showEditorDialog`）**共用同一份定义** ——
          // 批 5A · D2 的复用件，避免两处字段漂移。窄屏下每一行仍是
          // 「label 上 / 控件下」竖排（`HermesFormRow` 的窄屏分支），
          // 与改造前逐像素相同。
          _TaskFormFields(
            nameController: _nameController,
            scheduleController: _scheduleController,
            promptController: _promptController,
            toastNotifications: _toastNotifications,
            onChanged: () => setState(() {}),
            onToastChanged: (value) =>
                setState(() => _toastNotifications = value),
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

/// 新建 / 编辑定时任务的字段组 —— **窄屏整页与宽屏弹窗共用同一份定义**（批 5A · D2）。
///
/// 每行都走 [HermesFormRow]：窄屏「label 上 / 控件下」竖排（与改造前逐像素
/// 相同），宽屏「左 label 88 / 右控件」横排。
///
/// [onChanged] / [onToastChanged] 只上报「有变化」，怎么消费由宿主决定
/// （窄屏整页 `setState`；宽屏弹窗弹卡片重建）。
class _TaskFormFields extends StatelessWidget {
  const _TaskFormFields({
    required this.nameController,
    required this.scheduleController,
    required this.promptController,
    required this.toastNotifications,
    required this.onChanged,
    required this.onToastChanged,
  });

  final TextEditingController nameController;
  final TextEditingController scheduleController;
  final TextEditingController promptController;
  final bool toastNotifications;
  final VoidCallback onChanged;
  final ValueChanged<bool> onToastChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 表单正文一律**左对齐**：宽屏卡片把 content 包在
    // `DefaultTextStyle(textAlign: center)`（与 `CupertinoAlertDialog` 的正文
    // 同款）里，直接沿用会让「名称 / 调度表达式 / 提示词」在 88 槽内各自居中、
    // 排成一列锯齿。窄屏整页的环境值本来就是 start，故这层 merge 在窄屏是
    // **恒等变换**，不改任何像素。
    return DefaultTextStyle.merge(
      textAlign: TextAlign.start,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TaskFormField(
            label: l10n.taskName,
            fieldKey: const ValueKey('tasks-form-name'),
            controller: nameController,
            placeholder: l10n.taskNamePlaceholder,
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
          _TaskFormField(
            label: l10n.scheduleExpression,
            fieldKey: const ValueKey('tasks-form-schedule'),
            controller: scheduleController,
            placeholder: l10n.schedulePlaceholder,
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
          _TaskFormField(
            label: l10n.promptLabel,
            fieldKey: const ValueKey('tasks-form-prompt'),
            controller: promptController,
            placeholder: l10n.promptPlaceholder,
            // 6 行文本域的宽屏 label 取顶对齐：居中会飘到文本域的正中间。
            labelAlignment: CrossAxisAlignment.start,
            maxLines: 6,
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
          CupertinoListTile(
            title: Text(l10n.pushNotifications),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('tasks-form-toast'),
                value: toastNotifications,
                onChanged: onToastChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个字段行：label 件 + 带边框输入框，排布全部交给 [HermesFormRow]。
class _TaskFormField extends StatelessWidget {
  const _TaskFormField({
    required this.label,
    required this.fieldKey,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    this.labelAlignment = CrossAxisAlignment.center,
    this.maxLines = 1,
  });

  final String label;
  final Key fieldKey;
  final TextEditingController controller;
  final String placeholder;
  final VoidCallback onChanged;

  /// 宽屏横排时 label 的竖直对齐（见 [HermesFormRow.alignment]）。
  final CrossAxisAlignment labelAlignment;

  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return HermesFormRow(
      alignment: labelAlignment,
      // label 件的字号 / 颜色**逐字保留改造前原值**：窄屏逐像素不变由
      // 「`HermesFormRow` 不重新解释 label 样式」这条结构性约定保证。
      label: Text(
        label,
        style: TextStyle(
          fontSize: kFontLabel,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: secondaryText,
          ),
        ),
      ),
      child: CupertinoTextField(
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
        onChanged: (_) => onChanged(),
      ),
    );
  }
}
