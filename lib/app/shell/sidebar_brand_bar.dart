import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/session.dart';
import '../../features/session_list/session_list_providers.dart';
import '../../features/session_list/session_list_shell_requests.dart';
import '../../features/desktop/window_title_service.dart';
import '../../features/desktop/desktop_settings.dart';
import '../../l10n/app_localizations.dart';
import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';

/// 宽屏侧栏顶部品牌行（#149 案 A，对齐设计稿）。
///
/// 结构（一行）：
/// `[logo] Hermes …………………… [搜索] [刷新] [筛选]`
/// 点搜索图标 → 品牌行下方展开一行搜索框（再次点击收起并清空查询）。
///
/// 与列表页的分工（关键，避免双入口）：
/// - **搜索 / 刷新**：品牌行自己完成（搜索用本组件的 controller 调
///   `sessionListControllerProvider.search`；刷新调同一 controller 的 `refresh`）；
/// - **筛选**：弹层依赖列表页私有状态与私有方法，搬迁成本高 ⇒ 走
///   [sessionListFilterRequestProvider] 信号，由列表页监听后用自己已有的实现打开；
/// - 侧栏场景（`showUtilityRows == false`）列表页**不再渲染**搜索框/筛选/刷新/新建，
///   全部由品牌行 + 工具列表承担。
class SidebarBrandBar extends ConsumerStatefulWidget {
  const SidebarBrandBar({super.key});

  @override
  ConsumerState<SidebarBrandBar> createState() => _SidebarBrandBarState();
}

class _SidebarBrandBarState extends ConsumerState<SidebarBrandBar> {
  final TextEditingController _searchController = TextEditingController();

  /// 搜索框是否展开（局部 UI 态，不落盘、不跨会话）。
  bool _searchOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    final willOpen = !_searchOpen;
    setState(() => _searchOpen = willOpen);
    if (!willOpen && _searchController.text.isNotEmpty) {
      _searchController.clear();
      // 收起时清空查询 → 列表回到非搜索态（与列表页搜索框行为一致）。
      unawaited(ref.read(sessionListControllerProvider.notifier).search(''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // #161：品牌行副标题（当前工作区 · 会话数）。取自已加载的列表，零新增请求。
    final brandSubtitle = _resolveBrandSubtitle(ref, l10n);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    // 刷新中判据沿用列表页同一 provider（避免自己拼状态字段）。
    final refreshing = ref.watch(sessionListRefreshingProvider);

    final activeFg = isLight
        ? statusBlueText.resolveFrom(context)
        : CupertinoTheme.of(context).primaryColor;
    final inactiveFg = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final divider = LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: CupertinoColors.separator,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10.0, 8.0, 6.0, 6.0),
          child: Row(
            children: [
              // #156：进入搜索态时 logo 让位（见下方 Row 末尾的「取消」）——
              // 内联搜索框只有「侧栏宽 − logo − 三图标」的宽度，CupertinoSearchTextField
              // 自带放大镜与清除按钮，窄侧栏下会把文字挤到只剩一半。
              if (!_searchOpen)
                // #153：改用真实品牌图标。原先是个纯渐变的深色方块 —— 在暗色主题
                // 下与背景几乎同色，看起来就是「一个空框」（主人实机反馈）。
                ClipRRect(
                  key: const ValueKey('sidebar-brand-logo'),
                  borderRadius: BorderRadius.circular(5.0),
                  child: Image.asset(
                    'assets/branding/hermes-agent-icon-1024.png',
                    width: 21.0,
                    height: 21.0,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              if (!_searchOpen) const SizedBox(width: 7.0),
              Expanded(
                // #153：搜索改为**在本行内横向展开**（原实现是在下方另起一行
                // 搜索框，会临时占掉一整行高度、把会话列表往下推）。
                child: _searchOpen
                    ? SizedBox(
                        // #157：原来硬限 26px —— 15px 字号 + CupertinoSearchTextField
                        // 内置内边距装不下，placeholder 底部被裁掉几像素（主人实测）。
                        // 放宽到 32px，并让文字行高走默认（不再压缩）。
                        height: 32.0,
                        child: CupertinoSearchTextField(
                          key: const ValueKey('sidebar-brand-search-field'),
                          controller: _searchController,
                          placeholder: l10n.searchSessions,
                          autofocus: true,
                          style: const TextStyle(fontSize: 15.0),
                          decoration: isLight
                              ? BoxDecoration(
                                  color: LightSurfaces.card,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: LightSurfaces.cardBorder,
                                    width: 0.5,
                                  ),
                                )
                              : BoxDecoration(
                                  color: CupertinoColors.tertiarySystemFill
                                      .resolveFrom(context),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                          // #153：placeholder 配色沿用列表页搜索框的口径
                          // （浅色用 LightSurfaces.placeholder、暗色用系统次要色）。
                          // 漏了它会让可读性审计拿不到颜色（曾导致一条测试报空）。
                          placeholderStyle: isLight
                              ? const TextStyle(
                                  color: LightSurfaces.placeholder,
                                )
                              : TextStyle(
                                  fontSize: 15.0,
                                  color: CupertinoColors.placeholderText
                                      .resolveFrom(context),
                                  decoration: TextDecoration.none,
                                ),
                          onChanged: (value) => unawaited(
                            ref
                                .read(sessionListControllerProvider.notifier)
                                .search(value),
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hermes',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // #153：字号对齐 markdown 正文基准（15），原 12.5 偏小。
                            // #161：回到设计稿口径（12.5）—— #153 曾把侧栏字号统一
                            // 抬到 15，主人实测「比设计稿大一圈」，此处回调。
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: LightSurfaces.resolve(
                                context,
                                const Color(0xFF1C1C1E),
                                dark: CupertinoColors.label,
                              ),
                            ),
                          ),
                          // #161：副标题 —— 当前工作区 + 会话数（利用常驻信息位）。
                          // 数据全部取自已加载的会话列表（无新增网络请求）。
                          if (brandSubtitle != null)
                            Text(
                              brandSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // 设计稿 .brand .sub2 = 10。
                                fontSize: 10.0,
                                height: 1.25,
                                color: LightSurfaces.resolve(
                                  context,
                                  const Color(0xFF8E8E93),
                                  dark: CupertinoColors.placeholderText,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              if (!_searchOpen) ...[
                _BrandIconButton(
                  buttonKey: 'sidebar-brand-search',
                  icon: CupertinoIcons.search,
                  label: l10n.searchSessions,
                  selected: _searchOpen,
                  activeFg: activeFg,
                  inactiveFg: inactiveFg,
                  onPressed: _toggleSearch,
                ),
                // 刷新保持「桌面平台专属」语义（与列表页 showDesktopRefresh
                // = isDesktop && isWide 一致）——安卓平板宽屏不凭空多出刷新按钮。
                if (isDesktopPlatform())
                  _BrandIconButton(
                    buttonKey: 'sidebar-brand-refresh',
                    icon: CupertinoIcons.arrow_clockwise,
                    label: l10n.refreshInsights,
                    selected: false,
                    activeFg: activeFg,
                    inactiveFg: inactiveFg,
                    onPressed: refreshing
                        ? null
                        : () => unawaited(
                            ref
                                .read(sessionListControllerProvider.notifier)
                                .refresh(),
                          ),
                  ),
                _BrandIconButton(
                  buttonKey: 'sidebar-brand-filter',
                  icon: CupertinoIcons.line_horizontal_3_decrease,
                  label: l10n.filterSessions,
                  selected: false,
                  activeFg: activeFg,
                  inactiveFg: inactiveFg,
                  onPressed: () => ref
                      .read(sessionListFilterRequestProvider.notifier)
                      .bump(),
                ),
              ] else ...[
                // #156：搜索态末尾只留「取消」（iOS 惯例：搜索时导航栏整条让位），
                // 保证搜索框有充足宽度，文字与图标不再挤在一起。
                CupertinoButton(
                  key: const ValueKey('sidebar-brand-search-cancel'),
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  minimumSize: const Size(0, 26.0),
                  onPressed: _toggleSearch,
                  child: Text(
                    l10n.cancel,
                    style: TextStyle(fontSize: 15.0, color: activeFg),
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(height: 0.5, color: divider),
      ],
    );

    return isLight
        ? ColoredBox(color: LightSurfaces.page, child: content)
        : content;
  }
}

/// 品牌行内的图标按钮：命中区 26×26、图标 17、圆角 6。
class _BrandIconButton extends StatelessWidget {
  const _BrandIconButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.selected,
    required this.activeFg,
    required this.inactiveFg,
    required this.onPressed,
  });

  final String buttonKey;
  final IconData icon;
  final String label;
  final bool selected;
  final Color activeFg;
  final Color inactiveFg;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('$buttonKey-semantics'),
      label: label,
      tooltip: label,
      selected: selected,
      button: true,
      child: CupertinoButton(
        key: ValueKey(buttonKey),
        padding: EdgeInsets.zero,
        minimumSize: const Size(26.0, 26.0),
        borderRadius: BorderRadius.circular(6.0),
        onPressed: onPressed,
        child: Icon(icon, size: 17.0, color: selected ? activeFg : inactiveFg),
      ),
    );
  }
}

/// #161：品牌行副标题 =「当前工作区末段 · N 个会话」。
///
/// - 工作区优先取**当前正在查看的会话**的 `workspace`；没有则退回列表首个；
///   全部无 `workspace` 时只显示会话数。
/// - 数据源是已加载的会话列表（`sessionListVisibleSessionsProvider`），
///   **不引入任何新的网络请求** —— 避免 #146 那类「provider watch 出 timer」
///   的坑（挂载即发 Dio 请求，测试里表现为 !timersPending）。
String? _resolveBrandSubtitle(WidgetRef ref, AppLocalizations l10n) {
  final sessions = ref.watch(sessionListVisibleSessionsProvider);
  if (sessions.isEmpty) return null;

  final currentId = ref.watch(activeChatSessionIdProvider);
  SessionSummary? anchor;
  for (final session in sessions) {
    if ((session.sessionId ?? session.id) == currentId) {
      anchor = session;
      break;
    }
  }
  anchor ??= sessions.first;

  final parts = <String>[];
  final workspace = anchor.workspace?.trim();
  if (workspace != null && workspace.isNotEmpty) {
    parts.add(extractWorkspaceLastPathComponent(workspace));
  }
  parts.add(l10n.sessionsCountLabel(sessions.length));
  return parts.join(' · ');
}
