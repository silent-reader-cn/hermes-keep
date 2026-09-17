import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/skills.dart';
import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_surfaces.dart';
import '../shared/app_back_button.dart';
import 'skills_providers.dart';

/// 技能浏览页（对齐 Hermex SkillsView）。
///
/// Cupertino 风格：大标题 + 刷新按钮 + 搜索框（本地过滤）+ 下拉刷新 +
/// 分类分组技能列表（名称 / 描述 / 标签 / 已禁用徽标），点击行展开详情
/// （路径 / 相关技能）；含加载 / 错误 / 空态。
class SkillsPage extends ConsumerStatefulWidget {
  const SkillsPage({super.key});

  @override
  ConsumerState<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends ConsumerState<SkillsPage> {
  final TextEditingController _searchController = TextEditingController();

  /// 已展开详情的技能名（点击行切换展开/收起）。
  final Set<String> _expandedNames = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(skillsControllerProvider);
    final state = async.valueOrNull;
    final groups = ref.watch(skillsGroupsProvider);
    final isSearchMode = state?.searchQuery?.isNotEmpty == true;

    ref.listen<AsyncValue<SkillsState>>(skillsControllerProvider, (
      previous,
      next,
    ) {
      final error = next.valueOrNull?.actionError;
      if (error != null && error != previous?.valueOrNull?.actionError) {
        unawaited(_showActionError(context, error));
      }
    });

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('skills-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.skillsTitle,
            leading: const AppBackButton(),
            trailing: AccessibleButton(
              key: const ValueKey('skills-refresh'),
              label: l10n.refreshSkills,
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(
                ref.read(skillsControllerProvider.notifier).refresh(),
              ),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(skillsControllerProvider.notifier).refresh(),
          ),
          SliverToBoxAdapter(child: _buildSearchBar()),
          ..._buildContentSlivers(async, state, groups, isSearchMode),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: CupertinoSearchTextField(
        key: const ValueKey('skills-search'),
        controller: _searchController,
        placeholder: l10n.searchSkills,
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
        onChanged: (value) =>
            ref.read(skillsControllerProvider.notifier).setSearchQuery(value),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 分类分组列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<SkillsState> async,
    SkillsState? state,
    List<SkillGroup> groups,
    bool isSearchMode,
  ) {
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

    if (groups.isEmpty) {
      return [_buildEmptySliver(isSearchMode: isSearchMode)];
    }

    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return [
      for (final group in groups)
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
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
            dividerMargin: 0,
            additionalDividerMargin: 0,
            hasLeading: false,
            header: Text(_skillsGroupTitle(context, group.title)),
            children: [
              for (final skill in group.skills)
                _SkillRow(
                  key: ValueKey('skills-row-${skillDisplayName(skill)}'),
                  skill: skill,
                  expanded: _expandedNames.contains(skillDisplayName(skill)),
                  onTap: () => _toggleExpanded(skill),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _buildErrorSliver(Object? error) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
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
                // 保留原未经解析的 systemGrey 绘制值（#8E8E93），防止高对比暗色下 resolve 变色
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
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
              key: const ValueKey('skills-retry'),
              color: isLight ? LightSurfaces.userDetail : null,
              onPressed: () => unawaited(
                ref.read(skillsControllerProvider.notifier).refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver({required bool isSearchMode}) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearchMode ? CupertinoIcons.search : CupertinoIcons.hammer,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                // 保留原未经解析的 systemGrey 绘制值（#8E8E93），防止高对比暗色下 resolve 变色
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isSearchMode ? l10n.noMatchingSkillsFound : l10n.noSkills,
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              isSearchMode
                  ? l10n.tryAnotherKeyword
                  : l10n.serverSkillsWillShowHere,
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
  // 交互
  // -------------------------------------------------------------------------

  void _toggleExpanded(SkillSummary skill) {
    if (!skillHasDetail(skill)) return;
    final name = skillDisplayName(skill);
    setState(() {
      if (!_expandedNames.remove(name)) {
        _expandedNames.add(name);
      }
    });
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) {
        final isLight =
            CupertinoTheme.brightnessOf(dialogContext) == Brightness.light;
        return CupertinoAlertDialog(
          title: Text(l10n.actionFailed),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              textStyle: isLight
                  ? const TextStyle(color: LightSurfaces.userDetail)
                  : null,
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );
    await ref.read(skillsControllerProvider.notifier).clearActionError();
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

/// 是否存在可展开的本地详情（path 或 relatedSkills 任一非空）。
bool skillHasDetail(SkillSummary skill) {
  final path = skill.path?.trim();
  if (path != null && path.isNotEmpty) return true;
  final related = skill.relatedSkills ?? const <String>[];
  return related.any((e) => e.trim().isNotEmpty);
}

String _skillsGroupTitle(BuildContext context, String rawTitle) {
  final l10n = AppLocalizations.of(context);
  switch (rawTitle) {
    case '内置':
      return l10n.skillsGroupBuiltin;
    case '项目':
      return l10n.skillsGroupProject;
    case '全局':
      return l10n.skillsGroupGlobal;
    case '其他':
      return l10n.skillsGroupOther;
    default:
      return rawTitle;
  }
}

/// 单行技能（自绘行，对齐 Hermex SkillRow：名称 / 描述 / 标签 / 已禁用
/// 徽标 + 展开箭头 + 启用/禁用开关；点击展开详情）。
class _SkillRow extends ConsumerWidget {
  const _SkillRow({
    super.key,
    required this.skill,
    required this.expanded,
    required this.onTap,
  });

  final SkillSummary skill;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final description = _trimmedOrNull(skill.description);
    final tags = (skill.tags ?? const <String>[])
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final disabled = skill.disabled == true;
    final isBusy =
        ref
            .watch(skillsControllerProvider)
            .valueOrNull
            ?.isBusy(skill.name ?? '') ??
        false;
    final hasDetail = skillHasDetail(skill);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasDetail ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              skillDisplayName(skill),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: disabled
                                    ? LightSurfaces.resolve(
                                        context,
                                        LightSurfaces.textSecondary,
                                        dark: secondaryText,
                                      )
                                    : CupertinoColors.label.resolveFrom(
                                        context,
                                      ),
                              ),
                            ),
                          ),
                          if (hasDetail) ...[
                            const SizedBox(width: 6),
                            Icon(
                              expanded
                                  ? CupertinoIcons.chevron_down
                                  : CupertinoIcons.chevron_right,
                              size: 14,
                              color: LightSurfaces.resolve(
                                context,
                                LightSurfaces.textSecondary,
                                dark: CupertinoColors.tertiaryLabel,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 3,
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
                      if (disabled || tags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (disabled)
                              _Badge(
                                text: AppLocalizations.of(context)
                                    .skillDisabledBadge,
                                highlighted: false,
                              ),
                            for (final tag in tags)
                              _Badge(text: tag, highlighted: true),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SettingsSurfaces.toggle(
                  context,
                  CupertinoSwitch(
                    key: ValueKey('skills-toggle-${skillDisplayName(skill)}'),
                    value: !disabled,
                    onChanged: isBusy
                        ? null
                        : (value) => unawaited(
                            ref
                                .read(skillsControllerProvider.notifier)
                                .toggleSkill(skill, enabled: value),
                          ),
                  ),
                ),
              ],
            ),
            if (expanded && hasDetail)
              _SkillDetail(
                key: ValueKey('skills-detail-${skillDisplayName(skill)}'),
                skill: skill,
              ),
          ],
        ),
      ),
    );
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// 展开的技能详情：路径 / 相关技能（本地元数据，无额外网络请求）。
class _SkillDetail extends StatelessWidget {
  const _SkillDetail({super.key, required this.skill});

  final SkillSummary skill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final path = skill.path?.trim();
    final related = (skill.relatedSkills ?? const <String>[])
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path != null && path.isNotEmpty) ...[
            _DetailLine(label: l10n.skillPathLabel, value: path),
            const SizedBox(height: 4),
          ],
          if (related.isNotEmpty)
            _DetailLine(
              label: l10n.relatedSkillsLabel,
              value: related.join('、'),
            ),
        ],
      ),
    );
  }
}

/// 「标签：值」详情行。
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label：',
            style: TextStyle(
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: CupertinoColors.label.resolveFrom(context)),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}

/// 小徽标（已禁用 / 标签）。
class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.highlighted});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        // 装饰性微填充色，非文字层；深浅色文字均为达标 label，保留原语义面。
        color: highlighted
            ? CupertinoColors.secondarySystemFill.resolveFrom(context)
            : CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
    );
  }
}
