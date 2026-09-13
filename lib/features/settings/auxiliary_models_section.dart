import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/hermes_page_route.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/auxiliary_model.dart';
import '../../l10n/app_localizations.dart';
import 'settings_providers.dart';
import 'settings_surfaces.dart';

/// 辅助模型分组（`_AuxiliaryModelsSection`，key: `settings-auxiliary-section`）。
///
/// 展示 11 个 canonical task 槽位绑定、主模型信息展示、模型选择页及「全部重置为自动」。
class AuxiliaryModelsSection extends ConsumerWidget {
  const AuxiliaryModelsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auxAsync = ref.watch(auxiliaryModelsControllerProvider);

    return auxAsync.when(
      loading: () => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-auxiliary-section'),
          header: Text(l10n.auxiliaryModelsSection),
          children: [
            CupertinoListTile(
              title: Text(l10n.loadingAuxiliaryModels),
              trailing: const CupertinoActivityIndicator(),
            ),
          ],
        ),
      ),
      error: (error, _) => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-auxiliary-section'),
          header: Text(l10n.auxiliaryModelsSection),
          children: [
            CupertinoListTile(
              title: Text(l10n.auxiliaryModelsLoadFailed),
              subtitle: Text(_describeError(context, error)),
            ),
            CupertinoListTile(
              key: const ValueKey('settings-aux-retry'),
              title: Text(l10n.retry),
              trailing: const Icon(CupertinoIcons.refresh),
              onTap: () => unawaited(
                ref.read(auxiliaryModelsControllerProvider.notifier).refresh(),
              ),
            ),
          ],
        ),
      ),
      data: (state) => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-auxiliary-section'),
          header: Text(l10n.auxiliaryModelsSection),
          children: [
            CupertinoListTile(
              key: const ValueKey('settings-aux-reset'),
              leading: const Icon(CupertinoIcons.arrow_counterclockwise),
              title: Text(l10n.resetAuxiliary),
              onTap: () => unawaited(_confirmResetAll(context, ref)),
            ),
            if (state.main.model.isNotEmpty)
              CupertinoListTile(
                key: const ValueKey('aux-main-model-info'),
                title: Text(l10n.auxMainModel),
                subtitle: Text(
                  '${state.main.provider.isNotEmpty ? state.main.provider : l10n.auto} / ${state.main.model}',
                  style: TextStyle(
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: secondaryText,
                    ),
                  ),
                ),
              ),
            for (final taskRow in state.tasks)
              _buildTaskRow(context, ref, taskRow),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskRow(
    BuildContext context,
    WidgetRef ref,
    AuxiliaryTaskRow taskRow,
  ) {
    final l10n = AppLocalizations.of(context);
    final displayLabel = taskRow.label.isNotEmpty
        ? taskRow.label
        : taskRow.task;
    final isAuto = taskRow.provider == 'auto' || taskRow.provider.isEmpty;
    final modelSubtitle = isAuto
        ? l10n.auto
        : '${taskRow.provider} / ${taskRow.model}';

    return CupertinoListTile(
      key: ValueKey('aux-task-${taskRow.task}'),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(displayLabel, overflow: TextOverflow.ellipsis)),
          if (taskRow.apiKeySet) ...[
            const SizedBox(width: 6),
            const Text('🔑', style: TextStyle(fontSize: 12)),
          ],
        ],
      ),
      subtitle: Text(
        modelSubtitle,
        style: TextStyle(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: secondaryText,
          ),
        ),
      ),
      trailing: Icon(
        CupertinoIcons.chevron_right,
        size: 16,
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.textSecondary,
          dark: const Color(0xFF8E8E93),
        ),
      ),
      onTap: () => unawaited(_openAuxTaskPicker(context, ref, taskRow)),
    );
  }

  Future<void> _confirmResetAll(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => SettingsSurfaces.dialog(
        context,
        CupertinoAlertDialog(
          title: Text(l10n.resetAuxiliary),
          content: Text(l10n.confirmResetAuxiliary),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            CupertinoDialogAction(
              key: const ValueKey('settings-aux-reset-confirm'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  ref
                      .read(auxiliaryModelsControllerProvider.notifier)
                      .resetAllToAuto(),
                );
              },
              child: Text(l10n.resetAuxiliary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAuxTaskPicker(
    BuildContext context,
    WidgetRef ref,
    AuxiliaryTaskRow taskRow,
  ) {
    return Navigator.of(context).push(
      HermesPageRoute<void>(
        builder: (context) => AuxTaskPickerPage(taskRow: taskRow),
      ),
    );
  }
}

/// 辅助模型任务选择器页面（支持选 auto 或目录中的 provider/model）。
class AuxTaskPickerPage extends ConsumerWidget {
  const AuxTaskPickerPage({super.key, required this.taskRow});

  final AuxiliaryTaskRow taskRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsState = ref.watch(settingsControllerProvider).valueOrNull;
    final groups = settingsState?.modelGroups ?? const [];
    final displayTitle = taskRow.label.isNotEmpty
        ? '${taskRow.label} · ${l10n.auxTaskPickerTitle}'
        : l10n.auxTaskPickerTitle;
    final isAutoSelected =
        taskRow.provider == 'auto' || taskRow.provider.isEmpty;

    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const _PopBackButton(),
          middle: Text(displayTitle),
        ),
        child: SafeArea(
          child: ListView(
            children: [
              SettingsSurfaces.section(
                context,
                CupertinoListSection(
                  header: Text(l10n.auto),
                  children: [
                    CupertinoListTile(
                      key: const ValueKey('aux-model-option-auto'),
                      backgroundColor: SettingsSurfaces.selection(
                        context,
                        isAutoSelected,
                      ),
                      title: Text(l10n.auto),
                      subtitle: Text(
                        'auto',
                        style: TextStyle(
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: secondaryText,
                          ),
                        ),
                      ),
                      trailing: isAutoSelected
                          ? const Icon(CupertinoIcons.checkmark)
                          : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(
                          ref
                              .read(auxiliaryModelsControllerProvider.notifier)
                              .setAuxiliaryModel(
                                task: taskRow.task,
                                provider: 'auto',
                                model: '',
                              ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (groups.isNotEmpty)
                for (final group in groups)
                  SettingsSurfaces.section(
                    context,
                    CupertinoListSection(
                      header: Text(group.name),
                      children: [
                        for (final model in [
                          ...group.models,
                          ...group.extraModels,
                        ])
                          _buildModelOptionTile(
                            context,
                            ref,
                            group.providerID ?? '',
                            model,
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelOptionTile(
    BuildContext context,
    WidgetRef ref,
    String providerId,
    dynamic model,
  ) {
    final modelId = model.id as String;
    final displayName = model.displayName as String;
    final isSelected =
        taskRow.provider == providerId && taskRow.model == modelId;

    return CupertinoListTile(
      key: ValueKey('aux-model-option-$modelId'),
      backgroundColor: SettingsSurfaces.selection(context, isSelected),
      title: Text(displayName),
      subtitle: Text(
        providerId,
        style: TextStyle(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: secondaryText,
          ),
        ),
      ),
      trailing: isSelected ? const Icon(CupertinoIcons.checkmark) : null,
      onTap: () {
        Navigator.of(context).pop();
        unawaited(
          ref
              .read(auxiliaryModelsControllerProvider.notifier)
              .setAuxiliaryModel(
                task: taskRow.task,
                provider: providerId.isNotEmpty ? providerId : 'auto',
                model: modelId,
              ),
        );
      },
    );
  }
}

class _PopBackButton extends StatelessWidget {
  const _PopBackButton();

  @override
  Widget build(BuildContext context) {
    return CupertinoNavigationBarBackButton(
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}

String _describeError(BuildContext context, Object error) {
  if (error is ApiException) return error.message;
  return AppLocalizations.of(context).loadFailedRetry;
}
