import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/session_list/session_list_providers.dart';
import '../../features/session_list/session_list_shell_requests.dart';
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
      unawaited(
        ref.read(sessionListControllerProvider.notifier).search(''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              // 品牌记号：沿用侧栏既有视觉语言（深色圆角方块）而非新插图，
              // 避免在 19px 尺寸上引入难辨认的细节。
              Container(
                key: const ValueKey('sidebar-brand-logo'),
                width: 19.0,
                height: 19.0,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5.0),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3A3A3C), Color(0xFF1C1C1E)],
                  ),
                ),
              ),
              const SizedBox(width: 7.0),
              Expanded(
                child: Text(
                  'Hermes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
              ),
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
            ],
          ),
        ),
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(10.0, 0.0, 10.0, 8.0),
            child: CupertinoSearchTextField(
              key: const ValueKey('sidebar-brand-search-field'),
              controller: _searchController,
              placeholder: l10n.searchSessions,
              autofocus: true,
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
              itemColor: inactiveFg,
              onChanged: (value) => unawaited(
                ref.read(sessionListControllerProvider.notifier).search(value),
              ),
            ),
          ),
        Container(height: 0.5, color: divider),
      ],
    );

    return isLight ? ColoredBox(color: LightSurfaces.page, child: content) : content;
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
        child: Icon(
          icon,
          size: 17.0,
          color: selected ? activeFg : inactiveFg,
        ),
      ),
    );
  }
}