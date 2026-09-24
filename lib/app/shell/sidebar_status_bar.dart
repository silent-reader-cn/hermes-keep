import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../l10n/app_localizations.dart';
import '../theme/light_surfaces.dart';
import 'sidebar_hover_tip.dart';

/// 底部状态条连接状态枚举。
enum SidebarConnectionStatus {
  /// 已连接（绿点）。
  connected,

  /// 连接中（转圈）。
  connecting,

  /// 离线（红点 + 重试动作）。
  offline,
}

/// 桌面端会话列表底部状态条（#145 规格 B 案）。
///
/// 展示在侧栏会话列表列底部：
/// - 左侧：连接状态 pill（已连接 / 连接中 / 离线三态）
/// - 离线态附带重连动作按钮
/// - 右侧：端口号 + 服务类型（内置服务 / 外部服务器）
class SidebarStatusBar extends ConsumerWidget {
  const SidebarStatusBar({
    this.trailing,
    super.key,
    this.statusOverride,
    this.onRetry,
  });

  /// 状态覆写（主要用于测试或外部状态驱动）。
  ///
  /// 若未显式传入：
  /// - 当 [activeConnectionProvider] 有激活连接时渲染 [SidebarConnectionStatus.connected]
  /// - 当无激活连接时渲染 [SidebarConnectionStatus.offline]
  /// 底部行最右侧的附加控件槽（#149：次级功能图标并入住状态条同一行，
  /// 不再单独占一行高度）。
  final Widget? trailing;

  final SidebarConnectionStatus? statusOverride;

  /// 重连动作回调。若未提供且存在激活连接，触发既有连接的重新激活。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(activeConnectionProvider);

    final effectiveStatus = statusOverride ??
        (active != null
            ? SidebarConnectionStatus.connected
            : SidebarConnectionStatus.offline);

    final bgColor = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: const Color(0xFF1C1C1E),
    );
    final borderColor = LightSurfaces.resolve(
      context,
      LightSurfaces.divider,
      dark: const Color(0xFF3A3A3C),
    );

    String? portText;
    String? serviceTypeText;

    if (active != null) {
      final uri = Uri.tryParse(active.baseUrl);
      if (uri != null && uri.hasPort && uri.port != 0) {
        portText = uri.port.toString();
      } else if (uri?.scheme == 'https') {
        portText = '443';
      } else if (uri?.scheme == 'http') {
        portText = '80';
      }

      serviceTypeText = active.kind == ConnectionKind.builtin
          ? l10n.builtinService
          : l10n.externalServer;
    }

    return Container(
      key: const ValueKey('sidebar-status-bar'),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            width: 0.5,
            color: borderColor,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12.0, 7.0, 12.0, 9.0),
      child: Row(
        children: [
          // #153：端口与服务类型不再各占一个 chip（最窄侧栏时会挤到截断），
          // 改为「已连接」的 hover 提示承载（主人要求）。
          // 注意：不能用 Material 的 Tooltip（本项目禁 Material 混入业务 UI），
          // 故用本仓自绘的 Cupertino 风格 hover 提示。
          SidebarHoverTip(
            tipKey: const ValueKey('sidebar-status-tip'),
            message: [?portText, ?serviceTypeText].join(' · '),
            child: _buildStatusPill(context, l10n, effectiveStatus),
          ),
          if (effectiveStatus == SidebarConnectionStatus.offline) ...[
            const SizedBox(width: 6.0),
            _buildRetryButton(context, ref, l10n, active),
          ],
          const Spacer(),
          if (trailing != null) ...[
            const SizedBox(width: 6.0),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _buildStatusPill(
    BuildContext context,
    AppLocalizations l10n,
    SidebarConnectionStatus status,
  ) {
    switch (status) {
      case SidebarConnectionStatus.connected:
        final okBg = LightSurfaces.resolve(
          context,
          const Color(0xFFE8F6EC),
          dark: const Color(0xFF2C2C2E),
        );
        final okText = LightSurfaces.resolve(
          context,
          const Color(0xFF1E7B3C),
          dark: const Color(0xFF34C759),
        );
        return _buildPill(
          context,
          key: const ValueKey('sidebar-status-pill'),
          backgroundColor: okBg,
          textColor: okText,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6.0,
                height: 6.0,
                decoration: const BoxDecoration(
                  color: Color(0xFF34C759),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4.0),
              Text(l10n.mcpStatusConnected),
            ],
          ),
        );

      case SidebarConnectionStatus.connecting:
        return _buildPill(
          context,
          key: const ValueKey('sidebar-status-pill'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(radius: 5.0),
              const SizedBox(width: 4.0),
              Text(l10n.connecting),
            ],
          ),
        );

      case SidebarConnectionStatus.offline:
        final offlineBg = LightSurfaces.resolve(
          context,
          const Color(0xFFFFEFEE),
          dark: const Color(0xFF2C2C2E),
        );
        final offlineText = LightSurfaces.resolve(
          context,
          const Color(0xFFB3261E),
          dark: const Color(0xFFFF453A),
        );
        return _buildPill(
          context,
          key: const ValueKey('sidebar-status-pill'),
          backgroundColor: offlineBg,
          textColor: offlineText,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6.0,
                height: 6.0,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4.0),
              Text(l10n.offline),
            ],
          ),
        );
    }
  }

  Widget _buildRetryButton(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ServerConnection? active,
  ) {
    final retryColor = LightSurfaces.resolve(
      context,
      const Color(0xFFB3261E),
      dark: const Color(0xFFFF453A),
    );

    return Semantics(
      button: true,
      label: l10n.retry,
      child: CupertinoButton(
        key: const ValueKey('sidebar-status-retry'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 20.0),
        onPressed: () {
          if (onRetry != null) {
            onRetry!();
          } else if (active != null) {
            unawaited(
              ref.read(activeConnectionProvider.notifier).setActive(active.id),
            );
          }
        },
        child: _buildPill(
          context,
          textColor: retryColor,
          child: Text(l10n.retry),
        ),
      ),
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required Widget child,
    Key? key,
    Color? backgroundColor,
    Color? textColor,
  }) {
    final defaultBg = LightSurfaces.resolve(
      context,
      const Color(0xFFEBEBF0),
      dark: const Color(0xFF2C2C2E),
    );
    final defaultText = LightSurfaces.resolve(
      context,
      const Color(0xFF4A4A4F),
      dark: const Color(0xFFC4C4C9),
    );

    return Container(
      key: key,
      height: 20.0,
      padding: const EdgeInsets.symmetric(horizontal: 7.0),
      decoration: BoxDecoration(
        color: backgroundColor ?? defaultBg,
        borderRadius: BorderRadius.circular(10.0),
      ),
      alignment: Alignment.center,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: 'MiSans',
          fontSize: 11.5,
          color: textColor ?? defaultText,
        ),
        child: child,
      ),
    );
  }
}
