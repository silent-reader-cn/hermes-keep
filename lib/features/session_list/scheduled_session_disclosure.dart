import 'dart:async';
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../app/theme/light_surfaces.dart';

/// **已废弃：由融流替代**
///
/// 定时会话分区可折叠 disclosure 组件（历史遗留，保留以追溯）。
@Deprecated('已废弃：由融流替代')
class ScheduledSessionDisclosure extends StatefulWidget {
  const ScheduledSessionDisclosure({
    super.key,
    required this.title,
    required this.children,
    this.count,
    this.initialExpanded = false,
    this.onExpansionChanged,
  });

  /// 分区标题（如「定时」/「Scheduled」）。
  final String title;

  /// 定时会话数量（可选，展示于标题旁作为 badge）。
  final int? count;

  /// 该分区包含的会话列表项（通常为 [_SessionRow] 列表）。
  final List<Widget> children;

  /// 初始展开状态（对齐蓝本默认为 false：收起）。
  final bool initialExpanded;

  /// 展开/收起状态切换回调（测试/外部监听用）。
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<ScheduledSessionDisclosure> createState() =>
      _ScheduledSessionDisclosureState();
}

class _ScheduledSessionDisclosureState
    extends State<ScheduledSessionDisclosure> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
  }

  void _toggleExpanded() {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _isExpanded = !_isExpanded;
    });
    widget.onExpansionChanged?.call(_isExpanded);
  }

  Widget _buildHeader(BuildContext context) {
    final secondaryLabelColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final count = widget.count;

    return Semantics(
      button: true,
      label: widget.title,
      child: GestureDetector(
        key: const ValueKey('scheduled-disclosure-header'),
        behavior: HitTestBehavior.opaque,
        onTap: _toggleExpanded,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: kFontLabel,
                  fontWeight: FontWeight.normal,
                  color: secondaryLabelColor,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.card,
                      dark: CupertinoColors.systemGrey5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        CupertinoTheme.brightnessOf(context) == Brightness.light
                        ? Border.all(
                            color: LightSurfaces.cardBorder,
                            width: 0.5,
                          )
                        : null,
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: kFontMicro,
                      fontWeight: FontWeight.w600,
                      color: secondaryLabelColor,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                _isExpanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 12,
                color: secondaryLabelColor,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpanded) {
      final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
      return CupertinoListSection.insetGrouped(
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
        dividerMargin: 0,
        additionalDividerMargin: 0,

        key: const ValueKey('scheduled-disclosure-section'),
        hasLeading: false,
        header: _buildHeader(context),
        children: widget.children,
      );
    }

    return Padding(
      key: const ValueKey('scheduled-disclosure-collapsed'),
      padding: const EdgeInsetsDirectional.fromSTEB(20.0, 16.0, 20.0, 10.0),
      child: _buildHeader(context),
    );
  }
}
