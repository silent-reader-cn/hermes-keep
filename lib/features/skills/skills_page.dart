import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/layout_tokens.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/hermes_dialog.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../app/widgets/reading_width_box.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/skills.dart';
import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_surfaces.dart';
import '../shared/app_back_button.dart';
import 'skills_providers.dart';
import '../../app/widgets/app_refresh_control.dart';

/// 技能浏览页（对齐 Hermex SkillsView）。
///
/// Cupertino 风格：大标题 + 刷新按钮 + 搜索框（本地过滤）+ 下拉刷新 +
/// 分类分组技能列表（名称 / 描述 / 标签 / 已禁用徽标），点击行展开详情
/// （路径 / 相关技能）；含加载 / 错误 / 空态。
///
/// 宽屏（≥900）双栏（批 4 · P2）：左 320 技能列表常驻 + 右详情（正文限宽 744
/// 居中）；窄屏（<900）保留原**手风琴**就地展开，逐像素不变。
class SkillsPage extends ConsumerStatefulWidget {
  const SkillsPage({super.key});

  @override
  ConsumerState<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends ConsumerState<SkillsPage> {
  final TextEditingController _searchController = TextEditingController();

  /// 已展开详情的技能名（点击行切换展开/收起）。**窄屏（<900）专用**：宽屏走
  /// 右栏详情，不再就地展开。
  final Set<String> _expandedNames = {};

  /// 宽屏（≥900）右栏详情当前选中的技能名；null = 未点过（右栏回落到第一个
  /// 技能）。窄屏不使用。
  String? _selectedSkillName;

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
    // 宽屏双栏只在「有列表可拆」时启用：加载 / 错误 / 搜索无结果仍复用同一套
    // 单列状态页（不为宽屏另造空态，状态页与窄屏完全同源）。
    final isWideSplit =
        isWideLayout(context) && state != null && groups.isNotEmpty;

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
          AppRefreshControl(
            onRefresh: () =>
                ref.read(skillsControllerProvider.notifier).refresh(),
          ),
          // 窄屏（<900）：搜索框 + 单列分组卡片，点击行手风琴就地展开 —— 逐像素不变。
          if (!isWideSplit) ...[
            SliverToBoxAdapter(child: _buildSearchBar()),
            ..._buildContentSlivers(async, state, groups, isSearchMode),
          ],
          // 宽屏（≥900）：左 320 技能列表常驻 + 右详情（正文限宽 744 居中）。
          if (isWideSplit)
            SliverToBoxAdapter(child: _buildWideSplitBody(groups)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 宽屏（≥900）双栏（批 4 · P2）
  //
  // 为什么拆右栏（**理由取自批 4 修正版，别再写成「详情整页跳走」——那不是事实**）：
  // ① 现状是「一列卡片铺满 960」，宽屏右半屏整片空着；
  // ② 详情本来就是**手风琴就地展开**（`_toggleExpanded` + `_SkillDetail`），
  //    展开会把整列推长（其余技能被挤出屏幕），且一次只能看一个技能；
  // ③ 拆右栏后列表常驻，可连续点选**对比**多个技能 —— 这才是本页真正的收益。
  //
  // 窄屏保持手风琴原地展开（上面那条分支），宽窄两套互不影响。
  // -------------------------------------------------------------------------

  /// 宽屏主体：左栏（固定 320，含搜索框）+ 右栏详情（阅读型限宽 744 居中）。
  Widget _buildWideSplitBody(List<SkillGroup> groups) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSkillRail(groups),
        Expanded(child: _buildSkillDetailPane(_resolveSelectedSkill(groups))),
      ],
    );
  }

  /// 当前选中技能：优先 [_selectedSkillName]；首帧或列表刷新后名字消失时回落到
  /// 第一个技能 —— 宽屏右栏是**常驻面板**，不留空态。
  SkillSummary _resolveSelectedSkill(List<SkillGroup> groups) {
    final flat = [for (final group in groups) ...group.skills];
    final name = _selectedSkillName;
    if (name != null) {
      for (final skill in flat) {
        if (skillDisplayName(skill) == name) return skill;
      }
    }
    return flat.first;
  }

  /// 左栏：固定宽 320、右侧 0.5px 发丝分栏线；搜索框 + 分组标题 + 技能行
  /// （技能名 / 描述单行省略 / 启用开关）。
  Widget _buildSkillRail(List<SkillGroup> groups) {
    final selectedName = skillDisplayName(_resolveSelectedSkill(groups));
    return Container(
      key: const ValueKey('skills-rail'),
      width: _kSkillRailWidth,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: _railSeparator(context), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchBar(padding: const EdgeInsets.only(bottom: 8)),
          for (final group in groups) ...[
            _WideSkillRailGroupLabel(_skillsGroupTitle(context, group.title)),
            for (final skill in group.skills)
              _WideSkillRailRow(
                key: ValueKey('skills-rail-row-${skillDisplayName(skill)}'),
                skill: skill,
                selected: skillDisplayName(skill) == selectedName,
                onTap: () => setState(
                  () => _selectedSkillName = skillDisplayName(skill),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 右栏：详情正文限宽 744 并水平居中（G1 阅读型档位；与设置 / 记忆同口径）。
  ///
  /// **为什么不重复技能名**：技能名已经由左栏那一行承担（选中行 L2 高亮 + 常驻
  /// 可见），右栏再写一遍是同一屏内说两遍同一件事；右栏只回答「这个技能是什么、
  /// 在哪儿、和谁相关」。窄屏行内详情同理（名称在行首，详情挂在下方）。
  Widget _buildSkillDetailPane(SkillSummary skill) {
    final l10n = AppLocalizations.of(context);
    final description = _SkillRow._trimmedOrNull(skill.description);
    final tags = (skill.tags ?? const <String>[])
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final disabled = skill.disabled == true;
    final hasDetail = skillHasDetail(skill);
    // 什么都没有的技能（无描述 / 无标签 / 无路径 / 无相关）：给一句明确的
    // 「没有更多详情」，而不是留一片看不出所以然的空白。
    final isEmpty =
        description == null && tags.isEmpty && !disabled && !hasDetail;

    return ReadingWidthBox(
      key: const ValueKey('skills-detail-pane'),
      maxWidth: _kSkillDetailMaxWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          kPanelPaddingWide,
          12,
          kPanelPaddingWide,
          kPanelPaddingWide,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isEmpty)
              Text(
                l10n.noMoreSkillDetails,
                style: TextStyle(
                  fontSize: 13,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: secondaryText,
                  ),
                ),
              ),
            if (description != null) ...[
              Text(
                description,
                style: TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ],
            // 标签 / 已禁用徽标：窄屏挂在列表行上，宽屏移到这里（列表行只留
            // 名称 + 描述 + 开关，保持左栏可扫读）。
            if (disabled || tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (disabled)
                    _Badge(text: l10n.skillDisabledBadge, highlighted: false),
                  for (final tag in tags) _Badge(text: tag, highlighted: true),
                ],
              ),
            ],
            // 路径 / 相关技能（本地元数据，无额外网络请求）。
            _SkillDetail(
              key: ValueKey('skills-detail-pane-${skillDisplayName(skill)}'),
              skill: skill,
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索框。
  ///
  /// [padding] 默认逐像素沿用窄屏的 `16,4,16,8`；宽屏左栏（320）由 [_buildSkillRail]
  /// 传入更紧的内边距（左栏自身已有 10 边距）。
  Widget _buildSearchBar({
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  }) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return Padding(
      padding: padding,
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
    // 批 5 · C3：单动作告警框 → D1 `confirm`（380）；窄屏仍是系统 alert。
    await showHermesDialog<void>(
      context,
      kind: HermesDialogKind.confirm,
      title: (_) => Text(l10n.actionFailed),
      content: (_) => Text(message),
      actions: [
        HermesDialogAction(
          builder: (dialogContext) {
            final isLight =
                CupertinoTheme.brightnessOf(dialogContext) == Brightness.light;
            return Text(
              l10n.ok,
              style: isLight
                  ? const TextStyle(color: LightSurfaces.userDetail)
                  : null,
            );
          },
          onPressed: (dialogContext) => Navigator.pop(dialogContext),
        ),
      ],
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

// ---------------------------------------------------------------------------
// 宽屏（≥900）左栏 / 右栏令牌（批 4 · P2）
// ---------------------------------------------------------------------------

/// 左栏宽度 320（批 4 设计稿 P2「左 320 列表 + 右详情」）。
///
/// 与批 3 的设置/记忆左栏（220，导航型）刻意分档：那里是**分类导航**（短标签，
/// 点到即换内容），这里是**技能列表**（要放下技能名 + 描述单行 + 开关）。
const double _kSkillRailWidth = 320.0;

/// 右栏详情正文限宽 744（G1 阅读型档位；设置 / 记忆同值）。
///
/// 不直接用 `kReadingMaxWidth`（760）是因为批 3 设置/记忆已经落码 744，同一套
/// 「右栏限宽」在三页必须同值，否则并排对比时右栏内容左右游移。
const double _kSkillDetailMaxWidth = 744.0;

/// 左栏行文字（浅色设计稿 `#3A3A3C`）与行图标/分组标题（`#8A8A90`）—— 与批 3
/// 左栏骨架 `features/shared/wide_nav_rail.dart` 同款取值；深色回退语义色。
/// （该骨架文件属批 3 分区、本批不改，故这里按同款取值重画，不改共享件。）
const Color _kRailRowLabel = Color(0xFF3A3A3C);
const Color _kRailRowIcon = Color(0xFF8A8A90);

/// 分栏线 / 发丝线：浅色与卡片描边同族，暗色沿用 separator。
Color _railSeparator(BuildContext context) => LightSurfaces.resolve(
  context,
  LightSurfaces.divider,
  dark: CupertinoColors.separator,
);

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

/// 宽屏左栏分组标题（10pt w600 次级灰）。
///
/// 与 `features/shared/wide_nav_rail.dart` 的 `WideNavRailGroupLabel` 同款
/// （同字号 / 同内缩 / 同取色）—— 两页左栏被并排对比时视觉应一致。
class _WideSkillRailGroupLabel extends StatelessWidget {
  const _WideSkillRailGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
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

/// 宽屏左栏技能行：技能名（单行省略）+ 描述（单行省略）+ 启用开关。
///
/// 选中态走 L2 —— 浅色「中性灰底 [LightSurfaces.selectedSurface] + 蓝字
/// [LightSurfaces.selectionForeground]」，暗色沿用 primary 12%（与批 3 的
/// `WideNavRailRow` 同一套口径；L2 是主人 2026-09-27 拍板的全局选中态）。
/// 行高不固定（两行文案 + 开关），圆角 / 内边距与左栏骨架同档。
class _WideSkillRailRow extends ConsumerWidget {
  const _WideSkillRailRow({
    super.key,
    required this.skill,
    required this.selected,
    required this.onTap,
  });

  final SkillSummary skill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final activeFg = isLight
        ? LightSurfaces.selectionForeground
        : CupertinoTheme.of(context).primaryColor;
    final activeBg = isLight
        ? LightSurfaces.selectedSurface
        : activeFg.withValues(alpha: 0.12);
    final disabled = skill.disabled == true;
    final description = _SkillRow._trimmedOrNull(skill.description);
    final label = skillDisplayName(skill);
    final isBusy =
        ref
            .watch(skillsControllerProvider)
            .valueOrNull
            ?.isBusy(skill.name ?? '') ??
        false;

    // 名称：选中 → L2 蓝字；未选中 → 与左栏骨架同族（已禁用则退到次级灰，
    // 与窄屏行同口径）。
    final nameFg = selected
        ? activeFg
        : disabled
        ? LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: secondaryText,
          )
        : LightSurfaces.resolve(
            context,
            _kRailRowLabel,
            dark: CupertinoColors.label,
          );
    final descFg = selected
        ? activeFg
        : LightSurfaces.resolve(
            context,
            _kRailRowIcon,
            dark: CupertinoColors.secondaryLabel,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: CupertinoButton(
          key: ValueKey('skills-rail-tap-$label'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(double.infinity, 40),
          borderRadius: BorderRadius.circular(kRadiusInline),
          color: selected ? activeBg : CupertinoColors.transparent,
          onPressed: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: nameFg,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: descFg),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SettingsSurfaces.toggle(
                  context,
                  CupertinoSwitch(
                    key: ValueKey('skills-rail-toggle-$label'),
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
          ),
        ),
      ),
    );
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
