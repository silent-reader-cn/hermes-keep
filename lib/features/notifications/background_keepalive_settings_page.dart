import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_subpages.dart';
import 'background_keepalive_service.dart';
import 'notification_providers.dart';

/// 后台保活二级设置页（设置 → 高级设置 → 后台保活）。
///
/// 前台服务保活开关 + WorkManager 周期探活 + 系统保活与权限引导（展开为独立行，
/// 不再把多个引导按钮挤在单个 tile 的 subtitle 里）。
class BackgroundKeepalivePage extends StatelessWidget {
  const BackgroundKeepalivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return CupertinoPageScaffold(
      backgroundColor: isLight ? LightSurfaces.page : null,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: isLight ? LightSurfaces.page : null,
        border: isLight
            ? const Border(
                bottom: BorderSide(color: LightSurfaces.divider, width: 0.5),
              )
            : const Border(
                bottom: BorderSide(color: Color(0x4D000000), width: 0.0),
              ),
        leading: const PopBackButton(),
        middle: Text(l10n.bgKeepAliveSection),
      ),
      child: ListView(children: const [BackgroundKeepAliveSection()]),
    );
  }
}

/// 后台保活分组内容：前台服务开关 + WorkManager 状态 + 权限引导多项。
class BackgroundKeepAliveSection extends ConsumerWidget {
  const BackgroundKeepAliveSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    final keepalive = ref.watch(backgroundKeepaliveServiceProvider);
    final chevronColor = isLight
        ? LightSurfaces.textSecondary
        : const Color(0xFF8E8E93);

    return Column(
      children: [
        CupertinoListSection(
          dividerMargin: 0,
          additionalDividerMargin: 0,
          backgroundColor: LightSurfaces.resolve(
            context,
            LightSurfaces.page,
            dark: CupertinoColors.systemGroupedBackground,
          ),
          decoration: isLight
              ? BoxDecoration(
                  color: LightSurfaces.card,
                  border: Border.all(
                    color: LightSurfaces.cardBorder,
                    width: 0.5,
                  ),
                )
              : null,
          separatorColor: isLight ? LightSurfaces.divider : null,
          header: Text(
            l10n.bgKeepAliveSection,
            style: isLight
                ? const TextStyle(
                    fontSize: 13,
                    color: LightSurfaces.textSecondary,
                  )
                : null,
          ),
          children: [
            CupertinoListTile(
              key: const ValueKey('settings-bg-foreground-service'),
              title: Text(l10n.bgForegroundServiceTitle),
              subtitle: Text(
                l10n.bgKeepalivePersistentHint,
                style: isLight
                    ? const TextStyle(color: LightSurfaces.textSecondary)
                    : null,
              ),
              trailing: CupertinoSwitch(
                key: const ValueKey('settings-switch-bg-foreground-service'),
                value: settings.bgForegroundServiceEnabled,
                onChanged: (value) {
                  unawaited(notifier.setBgForegroundServiceEnabled(value));
                },
              ),
            ),
            // #105 安卓 16 实况通知（灵动岛/状态栏 chip）开关：默认开，
            // 关闭即回退到仅保活常驻通知的现状（低版本系统本就自动无感）。
            CupertinoListTile(
              key: const ValueKey('settings-bg-live-update'),
              title: Text(l10n.liveUpdateSwitchTitle),
              subtitle: Text(
                l10n.liveUpdateSwitchSubtitle,
                style: isLight
                    ? const TextStyle(color: LightSurfaces.textSecondary)
                    : null,
              ),
              trailing: CupertinoSwitch(
                key: const ValueKey('settings-switch-bg-live-update'),
                value: settings.bgLiveUpdateEnabled,
                onChanged: (value) {
                  unawaited(notifier.setBgLiveUpdateEnabled(value));
                },
              ),
            ),
            if (settings.error != null)
              CupertinoListTile(
                key: const ValueKey('settings-bg-foreground-service-error'),
                leading: Icon(
                  CupertinoIcons.exclamationmark_circle_fill,
                  color: statusRedText.resolveFrom(context),
                  size: 20,
                ),
                title: Text(
                  l10n.keepaliveStartFailed,
                  style: TextStyle(color: statusRedText.resolveFrom(context)),
                ),
                subtitle: Text(
                  settings.error!,
                  style: TextStyle(color: statusRedText.resolveFrom(context)),
                ),
              ),
            CupertinoListTile(
              key: const ValueKey('settings-bg-workmanager-status'),
              title: Text(l10n.bgWorkManagerStatusTitle),
              subtitle: Text(
                l10n.bgWorkManagerStatusSubtitle,
                style: isLight
                    ? const TextStyle(color: LightSurfaces.textSecondary)
                    : null,
              ),
              trailing: Icon(
                CupertinoIcons.checkmark_seal_fill,
                color: isLight
                    ? statusGreenText.resolveFrom(context)
                    : const Color(0xFF34C759),
                size: 20,
              ),
            ),
          ],
        ),
        // 系统保活与权限引导：每项独立一行，跳转对应系统设置页。
        CupertinoListSection(
          dividerMargin: 0,
          additionalDividerMargin: 0,
          backgroundColor: LightSurfaces.resolve(
            context,
            LightSurfaces.page,
            dark: CupertinoColors.systemGroupedBackground,
          ),
          decoration: isLight
              ? BoxDecoration(
                  color: LightSurfaces.card,
                  border: Border.all(
                    color: LightSurfaces.cardBorder,
                    width: 0.5,
                  ),
                )
              : null,
          separatorColor: isLight ? LightSurfaces.divider : null,
          header: Text(
            l10n.bgHyperOsGuidanceTitle,
            style: isLight
                ? const TextStyle(
                    fontSize: 13,
                    color: LightSurfaces.textSecondary,
                  )
                : null,
          ),
          children: [
            // 通知权限状态警示：升级安装后系统保留旧状态且不再弹窗，
            // 权限未授予时保活/回合通知会被系统抑制——显式提示并引导跳转。
            ref
                .watch(notificationPermissionProvider)
                .maybeWhen(
                  data: (enabled) {
                    if (enabled) return const SizedBox.shrink();
                    return CupertinoListTile(
                      key: const ValueKey(
                        'settings-bg-guide-permission-warning',
                      ),
                      leading: Icon(
                        CupertinoIcons.exclamationmark_triangle_fill,
                        color: statusOrangeText.resolveFrom(context),
                        size: 20,
                      ),
                      title: Text(
                        l10n.bgPermissionWarningTitle,
                        style: TextStyle(
                          color: statusOrangeText.resolveFrom(context),
                        ),
                      ),
                      subtitle: Text(
                        l10n.bgPermissionWarningSubtitle,
                        style: isLight
                            ? const TextStyle(
                                color: LightSurfaces.textSecondary,
                              )
                            : null,
                      ),
                      trailing: Icon(
                        CupertinoIcons.chevron_right,
                        size: 18,
                        color: chevronColor,
                      ),
                      onTap: () => unawaited(
                        keepalive.openHyperOsSetting(
                          HyperOsSettingType.notificationSettings,
                        ),
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
            CupertinoListTile(
              key: const ValueKey('settings-bg-guide-autostart'),
              title: Text(l10n.bgGuideAutoStart),
              trailing: Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: chevronColor,
              ),
              onTap: () => unawaited(
                keepalive.openHyperOsSetting(HyperOsSettingType.autoStart),
              ),
            ),
            CupertinoListTile(
              key: const ValueKey('settings-bg-guide-battery'),
              title: Text(l10n.bgGuideBattery),
              trailing: Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: chevronColor,
              ),
              onTap: () => unawaited(
                keepalive.openHyperOsSetting(
                  HyperOsSettingType.batteryOptimization,
                ),
              ),
            ),
            CupertinoListTile(
              key: const ValueKey('settings-bg-guide-network'),
              title: Text(l10n.bgGuideNetwork),
              trailing: Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: chevronColor,
              ),
              onTap: () => unawaited(
                keepalive.openHyperOsSetting(HyperOsSettingType.networkControl),
              ),
            ),
            CupertinoListTile(
              key: const ValueKey('settings-bg-guide-notifications'),
              title: Text(l10n.bgGuideNotifications),
              trailing: Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: chevronColor,
              ),
              onTap: () => unawaited(
                keepalive.openHyperOsSetting(
                  HyperOsSettingType.notificationSettings,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
