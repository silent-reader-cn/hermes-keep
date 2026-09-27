import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_action_menu.dart';
import '../../app/widgets/hermes_dialog.dart';
import '../../core/models/session.dart';
import '../../l10n/app_localizations.dart';
import '../projects/project_providers.dart';

/// 弹出项目选择器（底部 ActionSheet 列表 + 新建项目入口）。
///
/// 返回选中的 `projectId`（选择「无项目」返回空串）；取消返回 null。
/// 新建项目成功后立即返回新项目 id。
Future<String?> showProjectPicker(BuildContext context) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => const _ProjectPickerSheet(),
  );
}

class _ProjectPickerSheet extends ConsumerWidget {
  const _ProjectPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(projectsProvider);
    final projects = async.valueOrNull ?? const <ProjectSummary>[];
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;

    return CupertinoActionSheet(
      title: Text(
        l10n.moveToProject,
        style: isLight
            ? const TextStyle(color: LightSurfaces.textSecondary)
            : null,
      ),
      message: async.isLoading
          ? const CupertinoActivityIndicator(radius: 12)
          : null,
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('project-picker-none'),
          onPressed: () => Navigator.pop(context, ''),
          child: Text(
            l10n.noProject,
            style: isLight
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
        ),
        for (final project in projects)
          _ProjectPickerRow(
            key: ValueKey('project-picker-${project.id}'),
            project: project,
            onSelect: () => Navigator.pop(context, project.id),
            onManage: (anchorKey) => unawaited(
              _showProjectActions(context, ref, project, anchorKey),
            ),
          ),
        CupertinoActionSheetAction(
          key: const ValueKey('project-picker-create'),
          onPressed: () async {
            final name = await _promptProjectName(
              context,
              title: l10n.newProject,
              confirmText: l10n.create,
            );
            if (name == null || !context.mounted) return;
            final created = await ref
                .read(projectsProvider.notifier)
                .createProject(name: name);
            if (!context.mounted) return;
            if (created != null) {
              Navigator.pop(context, created.id);
            }
          },
          child: Text(
            l10n.newProjectEllipsis,
            style: isLight
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('project-picker-cancel'),
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context),
        child: Text(
          l10n.cancel,
          style: isLight
              ? const TextStyle(color: LightSurfaces.menuAction)
              : null,
        ),
      ),
    );
  }
}

Future<String?> _promptProjectName(
  BuildContext context, {
  required String title,
  required String confirmText,
}) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  // 浅色判据取**页面** context（与弹窗 context 同一主题亮度；动作色在
  // `HermesDialogAction.textStyle` 上求值，那里拿不到 dialog 作用域）。
  final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
  // 批 5 · C3：带输入框 → D1 `form`（560）；窄屏仍是系统 alert（竖排、逐像素不变）。
  final name = await showHermesDialog<String>(
    context,
    kind: HermesDialogKind.form,
    title: (_) => KeyedSubtree(
      // 原 alert 根件上的 key 原样保留（供定位；`KeyedSubtree` 不吃布局，像素不变）。
      key: const ValueKey('project-create-dialog'),
      child: Text(title),
    ),
    content: (_) {
      return CupertinoTextField(
        key: const ValueKey('project-create-name'),
        controller: controller,
        autofocus: true,
        placeholder: l10n.projectNamePlaceholder,
        decoration: isLight
            ? BoxDecoration(
                color: LightSurfaces.card,
                border: Border.all(
                  color: LightSurfaces.cardBorder,
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(5),
              )
            : const CupertinoTextField().decoration,
        placeholderStyle: isLight
            ? const TextStyle(
                fontWeight: FontWeight.w400,
                color: LightSurfaces.placeholder,
              )
            : const CupertinoTextField().placeholderStyle,
      );
    },
    actions: [
      HermesDialogAction(
        key: const ValueKey('project-create-cancel'),
        // 与改造前同落位：颜色走 `textStyle`（既有守卫钉的正是这个字段）。
        textStyle: isLight
            ? const TextStyle(color: LightSurfaces.userDetail)
            : null,
        builder: (_) => Text(l10n.cancel),
        onPressed: (dialogContext) => Navigator.pop(dialogContext),
      ),
      HermesDialogAction(
        key: const ValueKey('project-create-confirm'),
        textStyle: isLight
            ? const TextStyle(color: LightSurfaces.userDetail)
            : null,
        builder: (_) => Text(confirmText),
        onPressed: (dialogContext) =>
            Navigator.pop(dialogContext, controller.text),
      ),
    ],
  );
  controller.dispose();
  return name;
}

class _ProjectPickerRow extends StatefulWidget {
  const _ProjectPickerRow({
    super.key,
    required this.project,
    required this.onSelect,
    required this.onManage,
  });

  final ProjectSummary project;
  final VoidCallback onSelect;
  final void Function(GlobalKey anchorKey) onManage;

  @override
  State<_ProjectPickerRow> createState() => _ProjectPickerRowState();
}

class _ProjectPickerRowState extends State<_ProjectPickerRow> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => widget.onManage(_anchorKey),
      child: CupertinoActionSheetAction(
        onPressed: widget.onSelect,
        child: KeyedSubtree(
          key: _anchorKey,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  widget.project.name ?? l10n.unnamedProject,
                  overflow: TextOverflow.ellipsis,
                  style: isLight
                      ? const TextStyle(color: LightSurfaces.menuAction)
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.ellipsis,
                size: 14,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.secondaryLabel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 长按项目行：弹管理菜单（重命名 / 删除，删除需确认）。
Future<void> _showProjectActions(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary project,
  GlobalKey anchorKey,
) async {
  final l10n = AppLocalizations.of(context);
  await AdaptiveActionMenu.show(
    context,
    anchorKey: anchorKey,
    title: project.name ?? l10n.unnamedProject,
    cancelLabel: l10n.cancel,
    cancelKey: const ValueKey('project-action-cancel'),
    items: [
      AdaptiveMenuItem(
        key: const ValueKey('project-action-rename'),
        label: l10n.rename,
        onPressed: () async {
          final name = await _promptProjectName(
            context,
            title: l10n.renameProject,
            confirmText: l10n.save,
          );
          if (name == null || name.trim().isEmpty || !context.mounted) return;
          await ref
              .read(projectsProvider.notifier)
              .renameProject(projectId: project.id, name: name.trim());
        },
      ),
      AdaptiveMenuItem(
        key: const ValueKey('project-action-delete'),
        isDestructive: true,
        label: l10n.delete,
        onPressed: () async {
          // 批 5 · C3：删除项目确认 → D1 `confirm`（380）；窄屏仍是系统 alert。
          // 颜色与改造前**同落位**（`textStyle`），宽屏由基础设施按同一规则合并。
          final isLight =
              CupertinoTheme.brightnessOf(context) == Brightness.light;
          final confirmed = await showHermesDialog<bool>(
            context,
            kind: HermesDialogKind.confirm,
            title: (_) => Text(l10n.deleteProject),
            content: (_) => Text(l10n.deleteProjectWarning),
            actions: [
              HermesDialogAction(
                key: const ValueKey('project-delete-cancel'),
                textStyle: isLight
                    ? const TextStyle(color: LightSurfaces.userDetail)
                    : null,
                builder: (_) => Text(l10n.cancel),
                onPressed: (dialogContext) =>
                    Navigator.pop(dialogContext, false),
              ),
              HermesDialogAction(
                key: const ValueKey('project-delete-confirm'),
                isDestructiveAction: true,
                textStyle: isLight
                    ? TextStyle(color: statusRedText.resolveFrom(context))
                    : null,
                builder: (_) => Text(l10n.delete),
                onPressed: (dialogContext) =>
                    Navigator.pop(dialogContext, true),
              ),
            ],
          );
          if (confirmed == true && context.mounted) {
            await ref.read(projectsProvider.notifier).deleteProject(project.id);
          }
        },
      ),
    ],
  );
}
