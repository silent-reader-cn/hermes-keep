import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/locale/locale_provider.dart';
import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/theme/theme_provider.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../app/widgets/hermes_page_route.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_client_server_panels.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/custom_header.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/models/server_catalog.dart';
import '../../core/update/update_checker_service.dart';
import '../../core/update/update_providers.dart';
import '../../core/utils/accessibility.dart';
import '../../core/utils/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../chat/chat_providers.dart';
import '../chat/chat_session_channel.dart';
import '../diagnostics/diagnostics_models.dart';
import '../diagnostics/diagnostics_page.dart';
import '../diagnostics/diagnostics_service.dart';
import '../notifications/background_keepalive_settings_page.dart';
import '../notifications/notification_providers.dart';
import '../onboarding/onboarding_providers.dart';
import '../session_list/session_events_client.dart';
import '../session_list/session_list_providers.dart';
import '../shared/app_back_button.dart';
import 'accessibility_settings.dart';
import 'chat_send_shortcut_settings.dart';
import 'composer_settings.dart';
import 'cron_visibility_settings.dart';
import 'injected_notice_settings.dart';
import 'perf_monitor_settings.dart';
import 'settings_providers.dart';
import 'settings_subpages.dart';
import 'settings_surfaces.dart';
import 'smooth_streaming_settings.dart';
import 'tool_group_settings.dart';

/// 设置页（app_shell_spec.md §3 `/settings`）。
///
/// 首页分组：外观 / 对话 / 服务器 / 模型 / 定时会话 / 二级入口组（辅助模型、MCP、扩展、
/// 会话列表入口、会话行信息、桌面）/ 关于。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        child: CustomScrollView(
          key: const ValueKey('settings-scroll'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            AdaptiveSliverNavigationBar(
              title: l10n.settingsTitle,
              leading: const AppBackButton(),
              onTitleDoubleTap: _scrollToTop,
            ),
            const SliverToBoxAdapter(child: _AppearanceSection()),
            const SliverToBoxAdapter(child: _ChatSection()),
            const SliverToBoxAdapter(child: _ServerSection()),
            const SliverToBoxAdapter(child: _ModelSection()),
            const SliverToBoxAdapter(child: _CronSection()),
            const SliverToBoxAdapter(child: _NotificationSection()),
            const SliverToBoxAdapter(child: _AdvancedSettingsSection()),
            const SliverToBoxAdapter(child: _AboutSection()),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 外观
// ---------------------------------------------------------------------------

/// 外观分组：主题三态（跟随系统 / 浅色 / 深色，接 [themeModeProvider]）。
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(themeModeProvider);
    final localeMode = ref.watch(localeModeProvider);
    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        header: Text(l10n.appearanceSection),
        children: [
          CupertinoListTile(
            title: Text(l10n.themeLabel),
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SettingsSurfaces.segmented(
                  context,
                  CupertinoSlidingSegmentedControl<AppThemeMode>(
                    groupValue: mode,
                    onValueChanged: (value) {
                      if (value != null) {
                        unawaited(
                          ref.read(themeModeProvider.notifier).setMode(value),
                        );
                      }
                    },
                    children: {
                      AppThemeMode.system: Text(l10n.themeSystem),
                      AppThemeMode.light: Text(l10n.themeLight),
                      AppThemeMode.dark: Text(l10n.themeDark),
                    },
                  ),
                ),
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.languageSectionTitle),
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SettingsSurfaces.segmented(
                  context,
                  CupertinoSlidingSegmentedControl<AppLocaleMode>(
                    key: const ValueKey('settings-locale-mode'),
                    groupValue: localeMode,
                    onValueChanged: (value) {
                      if (value != null) {
                        unawaited(
                          ref.read(localeModeProvider.notifier).setMode(value),
                        );
                      }
                    },
                    children: {
                      AppLocaleMode.system: Text(l10n.languageAuto),
                      AppLocaleMode.zh: Text(l10n.languageZh),
                      AppLocaleMode.en: Text(l10n.languageEn),
                    },
                  ),
                ),
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-force-high-contrast'),
            title: Text(l10n.forceHighContrastLabel),
            subtitle: Text(l10n.forceHighContrastDescription),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                value: ref
                    .watch(accessibilitySettingsProvider)
                    .forceHighContrast,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(accessibilitySettingsProvider.notifier)
                        .setForceHighContrast(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-collapse-injected-notices'),
            title: Text(l10n.collapseInjectedNoticesLabel),
            subtitle: Text(l10n.collapseInjectedNoticesDescription),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                value: ref
                    .watch(injectedNoticeSettingsProvider)
                    .collapseInjectedNotices,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(injectedNoticeSettingsProvider.notifier)
                        .setCollapse(value),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 对话
// ---------------------------------------------------------------------------

/// 对话设置分组：工具调用按回合聚合开关。
class _ChatSection extends ConsumerWidget {
  const _ChatSection();

  Future<void> _openSpeedPresetPicker(
    BuildContext context,
    WidgetRef ref,
    SmoothStreamingSpeedPreset currentSpeed,
  ) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => SettingsSurfaces.sheet(
        context,
        CupertinoActionSheet(
          title: Text(l10n.smoothStreamingSpeed),
          actions: [
            for (final preset in SmoothStreamingSpeedPreset.values)
              CupertinoActionSheetAction(
                key: ValueKey('smooth-streaming-speed-${preset.id}'),
                isDefaultAction: preset == currentSpeed,
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(
                    ref
                        .read(smoothStreamingSpeedProvider.notifier)
                        .setSpeed(preset),
                  );
                },
                child: Text(preset.localizedName(l10n)),
              ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final turnCollapse = ref.watch(turnCollapseProvider);
    final coalesce = ref.watch(toolGroupCoalesceProvider);
    final hideReasoning = ref.watch(hideReasoningProvider);
    final sendShortcut = ref.watch(chatSendShortcutSettingsProvider).mode;
    final composerTwoPane = ref.watch(composerTwoPaneProvider);
    final smoothStreaming = ref.watch(smoothStreamingProvider);
    final smoothStreamingSpeed = ref.watch(smoothStreamingSpeedProvider);
    final showPerfMonitor = ref.watch(perfMonitorProvider);
    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        header: Text(l10n.chatSection),
        children: [
          CupertinoListTile(
            key: const ValueKey('settings-send-message-shortcut'),
            title: Text(l10n.sendMessageShortcutLabel),
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SettingsSurfaces.segmented(
                  context,
                  CupertinoSlidingSegmentedControl<ChatSendShortcutMode>(
                    groupValue: sendShortcut,
                    onValueChanged: (value) {
                      if (value != null) {
                        unawaited(
                          ref
                              .read(chatSendShortcutSettingsProvider.notifier)
                              .setMode(value),
                        );
                      }
                    },
                    children: {
                      ChatSendShortcutMode.enter: Text(l10n.sendShortcutEnter),
                      ChatSendShortcutMode.ctrlEnter: Text(
                        l10n.sendShortcutCtrlEnter,
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-smooth-streaming'),
            title: Text(l10n.smoothStreaming),
            subtitle: Text(l10n.smoothStreamingDesc),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-smooth-streaming'),
                value: smoothStreaming,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(smoothStreamingProvider.notifier)
                        .setSmoothStreaming(value),
                  );
                },
              ),
            ),
          ),
          if (smoothStreaming)
            CupertinoListTile(
              key: const ValueKey('settings-smooth-streaming-speed'),
              title: Text(l10n.smoothStreamingSpeed),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    smoothStreamingSpeed.localizedName(l10n),
                    style: TextStyle(
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 18,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
              onTap: () =>
                  _openSpeedPresetPicker(context, ref, smoothStreamingSpeed),
            ),
          CupertinoListTile(
            key: const ValueKey('settings-turn-collapse'),
            title: Text(l10n.turn55TurnCollapseTitle),
            subtitle: Text(l10n.turn55TurnCollapseDesc),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-turn-collapse'),
                value: turnCollapse,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(turnCollapseProvider.notifier)
                        .setTurnCollapse(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-group-tools-by-turn'),
            title: Text(l10n.groupToolsByTurn),
            subtitle: Text(l10n.groupToolsByTurnDesc),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-group-tools-by-turn'),
                value: coalesce,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(toolGroupCoalesceProvider.notifier)
                        .setCoalesce(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-hide-thinking'),
            title: Text(l10n.hideThinking),
            subtitle: Text(l10n.hideThinkingDesc),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-hide-thinking'),
                value: hideReasoning,
                onChanged: (value) {
                  unawaited(
                    ref.read(hideReasoningProvider.notifier).setHide(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-composer-two-pane'),
            title: Text(l10n.composerTwoPane),
            subtitle: Text(l10n.composerTwoPaneDesc),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-composer-two-pane'),
                value: composerTwoPane,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(composerTwoPaneProvider.notifier)
                        .setTwoPane(value),
                  );
                  // 联动：切到经典单行时自动关闭性能监控，保证事务性。
                  if (!value) {
                    unawaited(
                      ref
                          .read(perfMonitorProvider.notifier)
                          .setShowPerfMonitor(false),
                    );
                  }
                },
              ),
            ),
          ),
          // 性能监控开关：仅两段式开启时显示。
          if (composerTwoPane)
            CupertinoListTile(
              key: const ValueKey('settings-perf-monitor'),
              title: Text(l10n.perfMonitor),
              subtitle: Text(l10n.perfMonitorDesc),
              trailing: SettingsSurfaces.toggle(
                context,
                CupertinoSwitch(
                  key: const ValueKey('settings-switch-perf-monitor'),
                  value: showPerfMonitor,
                  onChanged: (value) {
                    unawaited(
                      ref
                          .read(perfMonitorProvider.notifier)
                          .setShowPerfMonitor(value),
                    );
                  },
                ),
              ),
            ),
          CupertinoListTile(
            key: const ValueKey('settings-chat-status-line'),
            title: Text(l10n.chatStatusLine),
            subtitle: Text(l10n.chatStatusLineDesc),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-chat-status-line'),
                value: ref.watch(chatStatusLineProvider),
                onChanged: (value) {
                  unawaited(
                    ref.read(chatStatusLineProvider.notifier).setEnabled(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-auto-open-context'),
            title: Text(l10n.autoOpenContextTitle),
            subtitle: Text(l10n.autoOpenContextDesc),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-auto-open-context'),
                value: ref.watch(autoOpenContextOnNewSessionProvider),
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(autoOpenContextOnNewSessionProvider.notifier)
                        .setEnabled(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.chatAutoLoadSetting),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-auto-load-images'),
                value: ref.watch(autoLoadImagesProvider),
                onChanged: (value) {
                  unawaited(
                    ref.read(autoLoadImagesProvider.notifier).setEnabled(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-mermaid-tile'),
            title: Text(AppLocalizations.of(context).mermaidRenderToggleTitle),
            subtitle: Text(
              AppLocalizations.of(context).mermaidRenderToggleSubtitle,
            ),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-mermaid-toggle'),
                value: ref.watch(chatRenderMermaidProvider),
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(chatRenderMermaidProvider.notifier)
                        .setEnabled(value),
                  );
                },
              ),
            ),
            onTap: () {
              final current = ref.read(chatRenderMermaidProvider);
              unawaited(
                ref
                    .read(chatRenderMermaidProvider.notifier)
                    .setEnabled(!current),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 二级入口组（高级设置）
// ---------------------------------------------------------------------------

/// 二级入口分组：辅助模型 / MCP 服务器 / 扩展 / 会话列表入口 / 会话行信息 / 桌面。
class _AdvancedSettingsSection extends StatelessWidget {
  const _AdvancedSettingsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        header: Text(l10n.advancedSettingsSection),
        children: [
          CupertinoListTile(
            key: const ValueKey('settings-entry-auxiliary'),
            title: Text(l10n.auxiliaryModelsSection),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context).push(
              HermesPageRoute<void>(
                builder: (_) => const AuxiliaryModelsPage(),
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-entry-mcp'),
            title: Text(l10n.mcpSection),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context)
                .push(HermesPageRoute<void>(builder: (_) => const McpPage())),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-entry-extensions'),
            title: Text(l10n.extensionsSection),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context).push(
              HermesPageRoute<void>(builder: (_) => const ExtensionsPage()),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-entry-session-list-entries'),
            title: Text(l10n.sessionListEntriesSection),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context).push(
              HermesPageRoute<void>(
                builder: (_) => const SessionListEntriesPage(),
              ),
            ),
          ),
          // #154：侧栏导航入口（位置 + 顺序）。
          CupertinoListTile(
            key: const ValueKey('settings-entry-sidebar-nav-order'),
            title: Text(l10n.sidebarNavOrderSection),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context).push(
              HermesPageRoute<void>(
                builder: (_) => const SidebarNavOrderPage(),
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-entry-session-row-subtitle'),
            title: Text(l10n.sessionRowSubtitleSection),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context).push(
              HermesPageRoute<void>(
                builder: (_) => const SessionRowSubtitlePage(),
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-entry-desktop'),
            title: Text(l10n.desktopSection),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context).push(
              HermesPageRoute<void>(
                builder: (_) => const DesktopSettingsPage(),
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-entry-bg-keepalive'),
            title: Text(l10n.bgKeepAliveSection),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context).push(
              HermesPageRoute<void>(
                builder: (_) => const BackgroundKeepalivePage(),
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-entry-diagnostics'),
            title: Text(l10n.diagnosticsTitle),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.of(context).push(
              HermesPageRoute<void>(builder: (_) => const DiagnosticsPage()),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 定时会话
// ---------------------------------------------------------------------------

/// 定时会话显隐设置分组（TASK W3）。
class _CronSection extends ConsumerWidget {
  const _CronSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final showCron = ref.watch(cronVisibilityProvider).showCron;
    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        children: [
          CupertinoListTile(
            key: const ValueKey('settings-show-cron-sessions'),
            title: Text(l10n.showCronSessionsTitle),
            subtitle: Text(l10n.showCronSessionsSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-show-cron'),
                value: showCron,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(cronVisibilityProvider.notifier)
                        .setShowCron(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-session-events-stream'),
            title: Text(l10n.sessionEventsStreamTitle),
            subtitle: Text(l10n.sessionEventsStreamSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-session-events-stream'),
                value: ref.watch(sessionEventsStreamEnabledProvider),
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(sessionEventsStreamEnabledProvider.notifier)
                        .setEnabled(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-approval-stream'),
            title: Text(l10n.approvalStreamTitle),
            subtitle: Text(l10n.approvalStreamSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-approval-stream'),
                value: ref.watch(approvalStreamEnabledProvider),
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(approvalStreamEnabledProvider.notifier)
                        .setEnabled(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-session-content-stream'),
            title: Text(l10n.sessionContentStreamTitle),
            subtitle: Text(l10n.sessionContentStreamSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-session-content-stream'),
                value: ref.watch(sessionContentStreamEnabledProvider),
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(sessionContentStreamEnabledProvider.notifier)
                        .setEnabled(value),
                  );
                },
              ),
            ),
          ),
        ],

      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 通知
// ---------------------------------------------------------------------------

/// 通知推送测试类型。
enum PushTestType { turns, clarify, errors }

/// 通知设置分组（回合完成 / 澄清请求 / 异常中断 三类开关 + 推送测试）。
class _NotificationSection extends ConsumerStatefulWidget {
  const _NotificationSection();

  @override
  ConsumerState<_NotificationSection> createState() =>
      _NotificationSectionState();
}

class _NotificationSectionState extends ConsumerState<_NotificationSection> {
  PushTestType _selectedType = PushTestType.turns;
  bool _isLoading = false;

  Future<void> _handlePushTest() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final service = ref.read(turnNotificationServiceProvider);
      final hasPermission = await service.requestPermission();
      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      if (!hasPermission) {
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.warn,
          tag: 'notifications',
          message: '推送测试权限被拒绝',
        );
        _showNotice(l10n.pushTestTitle, l10n.pushTestPermissionDenied);
        return;
      }

      final now = DateTime.now();
      final nowStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final sessionId =
          'test-push-${_selectedType.name}-${now.millisecondsSinceEpoch}';
      final preview = l10n.pushTestBody(nowStr);

      final String typeLabel;
      final bool isEnabled;
      final settings = ref.read(notificationSettingsProvider);

      switch (_selectedType) {
        case PushTestType.turns:
          typeLabel = l10n.pushTestTurns;
          isEnabled = settings.notifyTurnsEnabled;
          await service.notifyTurnCompleted(
            sessionId,
            l10n.pushTestTurnsNotificationTitle,
            preview,
          );
        case PushTestType.clarify:
          typeLabel = l10n.pushTestClarify;
          isEnabled = settings.notifyClarifyEnabled;
          await service.notifyClarificationNeeded(
            sessionId,
            '${l10n.pushTestClarifyNotificationTitle} - $preview',
          );
        case PushTestType.errors:
          typeLabel = l10n.pushTestErrors;
          isEnabled = settings.notifyErrorsEnabled;
          await service.notifySessionError(
            sessionId,
            l10n.pushTestErrorsNotificationTitle,
            preview,
          );
      }

      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'notifications',
        message: '推送测试通知成功: ${_selectedType.name}',
        details: {
          'type': _selectedType.name,
          'sessionId': sessionId,
          'enabledInSettings': isEnabled,
        },
      );

      if (!mounted) return;

      final message = isEnabled
          ? l10n.pushTestSuccess(typeLabel)
          : l10n.pushTestDisabledNotice(typeLabel);

      _showNotice(l10n.pushTestTitle, message);
    } on Object catch (error) {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '推送测试通知失败: $error',
        errorKind: error.toString(),
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        // 统一文案口径：ApiException 展示其 message，其余回落本地化通用提示，
        // 不再把 error.toString() 原样弹给用户（与同文件 _describeError 一致）。
        _showNotice(l10n.pushTestTitle, _describeError(context, error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showNotice(String title, String message) {
    final l10n = AppLocalizations.of(context);
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => SettingsSurfaces.dialog(
          context,
          CupertinoAlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.ok),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        header: Text(l10n.notificationsSection),
        children: [
          CupertinoListTile(
            key: const ValueKey('settings-notify-turns'),
            title: Text(l10n.notifyTurnsTitle),
            subtitle: Text(l10n.notifyTurnsSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-notify-turns'),
                value: settings.notifyTurnsEnabled,
                onChanged: (value) {
                  unawaited(notifier.setNotifyTurnsEnabled(value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-notify-clarify'),
            title: Text(l10n.notifyClarifyTitle),
            subtitle: Text(l10n.notifyClarifySubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-notify-clarify'),
                value: settings.notifyClarifyEnabled,
                onChanged: (value) {
                  unawaited(notifier.setNotifyClarifyEnabled(value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-notify-errors'),
            title: Text(l10n.notifyErrorsTitle),
            subtitle: Text(l10n.notifyErrorsSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-switch-notify-errors'),
                value: settings.notifyErrorsEnabled,
                onChanged: (value) {
                  unawaited(notifier.setNotifyErrorsEnabled(value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-notify-push-test'),
            title: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SettingsSurfaces.segmented(
                  context,
                  CupertinoSlidingSegmentedControl<PushTestType>(
                    key: const ValueKey('settings-notify-push-test-type'),
                    groupValue: _selectedType,
                    onValueChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedType = value;
                        });
                      }
                    },
                    children: {
                      PushTestType.turns: Text(l10n.pushTestTurns),
                      PushTestType.clarify: Text(l10n.pushTestClarify),
                      PushTestType.errors: Text(l10n.pushTestErrors),
                    },
                  ),
                ),
              ),
            ),
            trailing: CupertinoButton.filled(
              color: SettingsSurfaces.isLight(context)
                  ? statusBlueText.resolveFrom(context)
                  : null,
              pressedOpacity: SettingsSurfaces.pressedOpacity(context),
              key: const ValueKey('settings-notify-push-test-button'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 28),
              onPressed: _isLoading ? null : _handlePushTest,
              child: _isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CupertinoActivityIndicator(radius: 7),
                    )
                  : Text(
                      l10n.pushTestButton,
                      style: const TextStyle(fontSize: 14),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 服务器
// ---------------------------------------------------------------------------

/// 服务器分组：当前服务器信息 + 服务器列表（切换 / 编辑 / 删除 / 新增）。
class _ServerSection extends ConsumerWidget {
  const _ServerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final connections = ref.watch(connectionsProvider);
    final active = ref.watch(activeConnectionProvider);
    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        header: Text(
          active == null ? l10n.serverSectionDisconnected : l10n.serverSection,
        ),
        children: [
          if (connections.isEmpty)
            CupertinoListTile(
              title: Text(l10n.noServerConfigured),
              subtitle: Text(l10n.noServerConfiguredSubtitle),
            ),
          for (final connection in connections)
            _buildServerRow(
              context,
              ref,
              connection,
              connection.id == active?.id,
            ),
          CupertinoListTile(
            key: const ValueKey('server-add'),
            leading: const Icon(CupertinoIcons.add_circled),
            title: Text(l10n.addServer),
            onTap: () => unawaited(_openServerEditor(context, ref)),
          ),
        ],
      ),
    );
  }

  Widget _buildServerRow(
    BuildContext context,
    WidgetRef ref,
    ServerConnection connection,
    bool isActive,
  ) {
    final l10n = AppLocalizations.of(context);
    final isBuiltin = connection.kind == ConnectionKind.builtin;
    final defaultName = isBuiltin ? l10n.builtinWebuiName : connection.baseUrl;
    final name = connection.name.isEmpty ? defaultName : connection.name;
    final canActivate = !isActive && !(isBuiltin && !connection.enabled);

    return CupertinoListTile(
      key: ValueKey('server-row-${connection.id}'),
      backgroundColor: SettingsSurfaces.selection(context, isActive),
      title: Text(
        name,
        style: TextStyle(
          color: (isBuiltin && !connection.enabled)
              ? LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.secondaryLabel,
                )
              : null,
        ),
      ),
      subtitle: Text(connection.baseUrl),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            const Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: CupertinoColors.systemBlue,
            ),
          if (isBuiltin)
            CupertinoButton(
              foregroundColor: SettingsSurfaces.actionColor(context),
              pressedOpacity: SettingsSurfaces.pressedOpacity(context),
              key: const ValueKey('server-toggle-builtin'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 28),
              onPressed: () => unawaited(
                ref
                    .read(connectionsProvider.notifier)
                    .setBuiltinEnabled(!connection.enabled),
              ),
              child: Text(
                connection.enabled
                    ? l10n.disableConnection
                    : l10n.enableConnection,
                style: TextStyle(
                  fontSize: 13,
                  color: connection.enabled
                      ? LightSurfaces.resolve(
                          context,
                          statusRedText.resolveFrom(context),
                          dark: CupertinoColors.systemRed,
                        )
                      : LightSurfaces.resolve(
                          context,
                          LightSurfaces.menuAction,
                          dark: CupertinoColors.activeBlue,
                        ),
                ),
              ),
            )
          else ...[
            SettingsSurfaces.serverAction(
              context,
              AccessibleButton(
                key: ValueKey('server-edit-${connection.id}'),
                label: l10n.editServer,
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: () => unawaited(
                  _openServerEditor(context, ref, connection: connection),
                ),
                child: const Icon(CupertinoIcons.pencil, size: 18),
              ),
            ),
            SettingsSurfaces.serverAction(
              context,
              AccessibleButton(
                key: ValueKey('server-delete-${connection.id}'),
                label: l10n.deleteServer,
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: () =>
                    unawaited(_confirmDeleteServer(context, ref, connection)),
                child: Icon(
                  CupertinoIcons.trash,
                  size: 18,
                  color: LightSurfaces.resolve(
                    context,
                    statusRedText.resolveFrom(context),
                    dark: const Color(0xFFFF3B30),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: canActivate
          ? () => unawaited(
              ref
                  .read(activeConnectionProvider.notifier)
                  .setActive(connection.id),
            )
          : null,
    );
  }

  Future<void> _openServerEditor(
    BuildContext context,
    WidgetRef ref, {
    ServerConnection? connection,
  }) {
    return Navigator.of(context).push(
      HermesPageRoute<void>(
        builder: (context) => _ServerEditorPage(connection: connection),
      ),
    );
  }

  Future<void> _confirmDeleteServer(
    BuildContext context,
    WidgetRef ref,
    ServerConnection connection,
  ) {
    final l10n = AppLocalizations.of(context);
    final name = connection.name.isEmpty ? connection.baseUrl : connection.name;
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => SettingsSurfaces.dialog(
        context,
        CupertinoAlertDialog(
          title: Text(l10n.deleteServer),
          content: Text(l10n.confirmDeleteServer(name)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            CupertinoDialogAction(
              key: const ValueKey('server-delete-confirm'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(
                  ref.read(connectionsProvider.notifier).remove(connection.id),
                );
              },
              child: Text(l10n.delete),
            ),
          ],
        ),
      ),
    );
  }
}

/// 服务器新增 / 编辑表单（复用 onboarding 的连接字段：名称 / 地址 / 密码 + Profile 管理）。
class _ServerEditorPage extends ConsumerStatefulWidget {
  const _ServerEditorPage({this.connection});

  /// 非 null = 编辑模式（保留 id / username / customHeaders / createdAt）。
  final ServerConnection? connection;

  @override
  ConsumerState<_ServerEditorPage> createState() => _ServerEditorPageState();
}

class _ServerEditorPageState extends ConsumerState<_ServerEditorPage> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.connection?.name ?? '',
  );
  late final TextEditingController _urlController = TextEditingController(
    text: widget.connection?.baseUrl ?? '',
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.connection?.password ?? '',
  );

  String _error = '';
  bool _saving = false;

  ProfilesResponse? _profiles;
  Object? _profileError;
  bool _loadingProfiles = false;

  @override
  void initState() {
    super.initState();
    if (widget.connection != null && widget.connection!.baseUrl.isNotEmpty) {
      unawaited(_loadProfiles());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ApiClient _getClient() {
    final active = ref.read(activeConnectionProvider);
    if (widget.connection != null && widget.connection!.id == active?.id) {
      return ref.read(apiClientProvider);
    }
    final url = widget.connection?.baseUrl ?? _urlController.text.trim();
    final headers = [
      for (final entry
          in (widget.connection?.customHeaders ?? const <String, String>{})
              .entries)
        CustomHeader(name: entry.key, value: entry.value),
    ];
    final factory = ref.read(serverEditorApiClientFactoryProvider);
    return factory(url, headers);
  }

  Future<void> _loadProfiles() async {
    final url = widget.connection?.baseUrl ?? _urlController.text.trim();
    if (url.isEmpty || !mounted) return;
    setState(() {
      _loadingProfiles = true;
      _profileError = null;
    });
    try {
      final client = _getClient();
      final response = await client.profiles();
      if (mounted) setState(() => _profiles = response);
    } catch (error) {
      if (mounted) setState(() => _profileError = error);
    } finally {
      if (mounted) setState(() => _loadingProfiles = false);
    }
  }

  Future<void> _switchProfile(ProfileSummary profile) async {
    final name = profile.name ?? '';
    if (name.isEmpty || name == _profiles?.active) return;
    setState(() => _loadingProfiles = true);
    try {
      final client = _getClient();
      final response = await client.switchProfile(name);
      if (mounted) {
        setState(() => _profiles = response.toProfilesResponse(name));
        final active = ref.read(activeConnectionProvider);
        if (widget.connection != null && widget.connection!.id == active?.id) {
          ref.invalidate(sessionListControllerProvider);
        }
      }
    } catch (error) {
      if (mounted) await _showProfileError(error);
    } finally {
      if (mounted) setState(() => _loadingProfiles = false);
    }
  }

  Future<void> _showProfileError(Object error) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => SettingsSurfaces.dialog(
        context,
        CupertinoAlertDialog(
          title: Text(l10n.profileSwitchFailed),
          content: Text(
            error is ApiException ? error.message : '$error',
            style: TextStyle(color: statusRedText.resolveFrom(context)),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.ok),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProfilePicker(List<ProfileSummary> profiles) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showCupertinoModalPopup<ProfileSummary>(
      context: context,
      builder: (sheetContext) => SettingsSurfaces.sheet(
        context,
        CupertinoActionSheet(
          title: Text(l10n.selectProfile),
          actions: [
            for (final profile in profiles)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(sheetContext, profile),
                child: Text(profile.name ?? l10n.unnamed),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(l10n.cancel),
          ),
        ),
      ),
    );
    if (selected != null) await _switchProfile(selected);
  }

  String? _validate() {
    final l10n = AppLocalizations.of(context);
    final url = _urlController.text.trim();
    if (url.isEmpty) return l10n.serverUrlRequired;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return l10n.serverUrlInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    final url = _urlController.text.trim();
    final host = Uri.tryParse(url)?.host;
    final existing = widget.connection;
    // 编辑时密码留空 = 保留原密码；新增时留空 = 无密码。
    final password = _passwordController.text.isEmpty
        ? existing?.password
        : _passwordController.text;
    // 有密码 → 先登录种会话 cookie（否则保存后会话列表必 401「密码被拒绝」）；
    // 登录失败 → 报错并停留，不保存无效配置。
    if (password != null && password.isNotEmpty) {
      final loginError = await _tryLogin(url, password, existing);
      if (loginError != null) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = loginError;
        });
        return;
      }
    }
    final resolvedName = _nameController.text.trim().isEmpty
        ? (host == null || host.isEmpty ? url : host)
        : _nameController.text.trim();
    final connection = (existing != null)
        ? existing.copyWith(
            name: resolvedName,
            baseUrl: url,
            password: password,
          )
        : ServerConnection(
            id: uuidV4(),
            name: resolvedName,
            baseUrl: url,
            password: password,
            createdAt: DateTime.now().toUtc(),
            kind: ConnectionKind.remote,
          );
    await ref.read(connectionsProvider.notifier).upsert(connection);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 用 [url] + [password] 调登录接口种 cookie；返回错误文案，null = 成功。
  Future<String?> _tryLogin(
    String url,
    String password,
    ServerConnection? existing,
  ) async {
    final l10n = AppLocalizations.of(context);
    final factory = ref.read(onboardingApiFactoryProvider);
    final api = factory(url, [
      for (final entry
          in (existing?.customHeaders ?? const <String, String>{}).entries)
        CustomHeader(name: entry.key, value: entry.value),
    ]);
    try {
      await api.login(password);
      return null;
    } on ApiException catch (error) {
      return l10n.loginFailedWithMessage(error.message);
    } on Exception {
      return l10n.cannotConnectToServer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = widget.connection != null;
    final profiles = _profiles?.profiles ?? const <ProfileSummary>[];
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const _PopBackButton(),
          middle: Text(isEditing ? l10n.editServer : l10n.addServer),
          trailing: Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              foregroundColor: SettingsSurfaces.actionColor(
                context,
                disabled: _saving,
              ),
              pressedOpacity: SettingsSurfaces.pressedOpacity(context),
              key: const ValueKey('server-editor-save'),
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              onPressed: _saving ? null : () => unawaited(_save()),
              child: Text(
                l10n.save,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        child: SafeArea(
          child: ListView(
            children: [
              SettingsSurfaces.section(
                context,
                CupertinoListSection(
                  dividerMargin: 0,
                  additionalDividerMargin: 0,

                  header: Text(l10n.serverBasicInfoSection),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.serverNameLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: LightSurfaces.resolve(
                                context,
                                LightSurfaces.textSecondary,
                                dark: CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          CupertinoTextField(
                            decoration: SettingsSurfaces.fieldDecoration(
                              context,
                            ),
                            placeholderStyle: SettingsSurfaces.placeholderStyle(
                              context,
                            ),
                            key: const ValueKey('server-editor-name'),
                            controller: _nameController,
                            placeholder: l10n.serverNamePlaceholder,
                            autocorrect: false,
                            padding: const EdgeInsets.all(12),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.serverUrlLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: LightSurfaces.resolve(
                                context,
                                LightSurfaces.textSecondary,
                                dark: CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          CupertinoTextField(
                            decoration: SettingsSurfaces.fieldDecoration(
                              context,
                            ),
                            placeholderStyle: SettingsSurfaces.placeholderStyle(
                              context,
                            ),
                            key: const ValueKey('server-editor-url'),
                            controller: _urlController,
                            placeholder: 'https://hermes.example.com:8787',
                            autocorrect: false,
                            keyboardType: TextInputType.url,
                            padding: const EdgeInsets.all(12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.serverUrlExampleHint,
                            style: TextStyle(
                              fontSize: 12,
                              color: LightSurfaces.resolve(
                                context,
                                LightSurfaces.textSecondary,
                                dark: CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.serverPasswordLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: LightSurfaces.resolve(
                                context,
                                LightSurfaces.textSecondary,
                                dark: CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          CupertinoTextField(
                            decoration: SettingsSurfaces.fieldDecoration(
                              context,
                            ),
                            placeholderStyle: SettingsSurfaces.placeholderStyle(
                              context,
                            ),
                            key: const ValueKey('server-editor-password'),
                            controller: _passwordController,
                            placeholder: l10n.serverPasswordPlaceholder,
                            obscureText: true,
                            padding: const EdgeInsets.all(12),
                          ),
                          if (_error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _error,
                                style: TextStyle(
                                  color: statusRedText.resolveFrom(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SettingsSurfaces.section(
                context,
                CupertinoListSection(
                  dividerMargin: 0,
                  additionalDividerMargin: 0,

                  header: Text(l10n.profile),
                  children: [
                    CupertinoListTile(
                      key: const ValueKey('server-editor-profile-tile'),
                      title: Text(
                        _profiles?.active ??
                            (_loadingProfiles
                                ? l10n.loadingEllipsis
                                : l10n.notRead),
                      ),
                      leading: const Icon(CupertinoIcons.person_2),
                      trailing: const CupertinoListTileChevron(),
                      onTap: profiles.isEmpty
                          ? _loadProfiles
                          : () => _showProfilePicker(profiles),
                    ),
                    if (_profileError != null)
                      CupertinoListTile(
                        key: const ValueKey('server-editor-profile-retry'),
                        title: Text(l10n.readFailed),
                        subtitle: Text(l10n.clickToRetry),
                        onTap: _loadProfiles,
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
}

extension on ProfileSwitchResponse {
  ProfilesResponse toProfilesResponse(String fallback) =>
      ProfilesResponse(profiles: profiles, active: active ?? fallback);
}

// ---------------------------------------------------------------------------
// 模型
// ---------------------------------------------------------------------------

/// 模型分组：默认模型（选择器）+ 推理强度（服务器支持时显示）。
class _ModelSection extends ConsumerWidget {
  const _ModelSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider);
    return settings.when(
      loading: () => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          dividerMargin: 0,
          additionalDividerMargin: 0,

          header: Text(l10n.models),
          children: [
            CupertinoListTile(
              title: Text(l10n.loadingModels),
              trailing: const CupertinoActivityIndicator(),
            ),
          ],
        ),
      ),
      error: (error, _) => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          dividerMargin: 0,
          additionalDividerMargin: 0,

          header: Text(l10n.models),
          children: [
            CupertinoListTile(
              title: Text(l10n.modelsLoadFailed),
              subtitle: Text(_describeError(context, error)),
            ),
            CupertinoListTile(
              key: const ValueKey('settings-models-retry'),
              title: Text(l10n.retry),
              trailing: const Icon(CupertinoIcons.refresh),
              onTap: () => unawaited(
                ref.read(settingsControllerProvider.notifier).refresh(),
              ),
            ),
          ],
        ),
      ),
      data: (state) => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          dividerMargin: 0,
          additionalDividerMargin: 0,

          header: Text(l10n.models),
          children: [
            CupertinoListTile(
              key: const ValueKey('settings-default-model'),
              title: Text(l10n.defaultModel),
              subtitle: Text(state.defaultModelLabel ?? l10n.notSet),
              trailing: const Icon(CupertinoIcons.chevron_right),
              onTap: () => unawaited(_openModelPicker(context, ref, state)),
            ),
            if (state.supportsReasoningEffort &&
                state.supportedEfforts.isNotEmpty)
              CupertinoListTile(
                key: const ValueKey('settings-reasoning'),
                title: Text(l10n.reasoningEffort),
                subtitle: Text(state.reasoningEffort ?? l10n.notSet),
                trailing: const Icon(CupertinoIcons.chevron_right),
                onTap: () =>
                    unawaited(_openReasoningPicker(context, ref, state)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openModelPicker(
    BuildContext context,
    WidgetRef ref,
    SettingsState state,
  ) {
    return Navigator.of(context).push(
      HermesPageRoute<void>(
        builder: (context) => _ModelPickerPage(state: state),
      ),
    );
  }

  Future<void> _openReasoningPicker(
    BuildContext context,
    WidgetRef ref,
    SettingsState state,
  ) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => SettingsSurfaces.sheet(
        context,
        CupertinoActionSheet(
          title: Text(l10n.reasoningEffort),
          actions: [
            for (final effort in state.supportedEfforts)
              CupertinoActionSheetAction(
                key: ValueKey('reasoning-$effort'),
                isDefaultAction: effort == state.reasoningEffort,
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setReasoningEffort(effort),
                  );
                },
                child: Text(effort),
              ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 默认模型选择页：按 provider 分组列出全部模型，选中即保存并返回。
class _ModelPickerPage extends ConsumerWidget {
  const _ModelPickerPage({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currentState =
        ref.watch(settingsControllerProvider).valueOrNull ?? state;
    final groups = currentState.modelGroups;
    final isRefreshing = currentState.isRefreshingModels;

    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const _PopBackButton(),
          middle: Text(l10n.defaultModel),
          trailing: CupertinoButton(
            foregroundColor: SettingsSurfaces.actionColor(
              context,
              disabled: isRefreshing,
            ),
            pressedOpacity: SettingsSurfaces.pressedOpacity(context),
            key: const ValueKey('model-picker-refresh-button'),
            padding: EdgeInsets.zero,
            onPressed: isRefreshing
                ? null
                : () => unawaited(
                    ref
                        .read(settingsControllerProvider.notifier)
                        .refreshModels(),
                  ),
            child: isRefreshing
                ? const CupertinoActivityIndicator(radius: 8)
                : const Icon(CupertinoIcons.arrow_clockwise, size: 20),
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              CupertinoSliverRefreshControl(
                onRefresh: () => ref
                    .read(settingsControllerProvider.notifier)
                    .refreshModels(),
              ),
              if (currentState.refreshError != null)
                SliverToBoxAdapter(
                  child: Container(
                    key: const ValueKey('model-picker-refresh-error'),
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.tintError,
                        dark: CupertinoColors.destructiveRed.withValues(
                          alpha: 0.12,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.divider,
                          dark: CupertinoColors.destructiveRed.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.exclamationmark_circle_fill,
                          size: 16,
                          color: LightSurfaces.resolve(
                            context,
                            statusRedText.resolveFrom(context),
                            dark: const Color(0xFFFF3B30),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentState.refreshError!,
                            style: TextStyle(
                              fontSize: 13,
                              color: LightSurfaces.resolve(
                                context,
                                statusRedText.resolveFrom(context),
                                dark: const Color(0xFFFF3B30),
                              ),
                            ),
                          ),
                        ),
                        CupertinoButton(
                          foregroundColor: SettingsSurfaces.actionColor(
                            context,
                          ),
                          pressedOpacity: SettingsSurfaces.pressedOpacity(
                            context,
                          ),
                          key: const ValueKey(
                            'model-picker-clear-refresh-error',
                          ),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(20, 20),
                          onPressed: () => ref
                              .read(settingsControllerProvider.notifier)
                              .clearRefreshError(),
                          child: Icon(
                            CupertinoIcons.clear_circled_solid,
                            size: 16,
                            color: LightSurfaces.resolve(
                              context,
                              statusRedText.resolveFrom(context),
                              dark: const Color(0xFFFF3B30),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (groups.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      l10n.noAvailableModels,
                      style: TextStyle(
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          dark: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                  ),
                )
              else
                for (final group in groups)
                  SliverToBoxAdapter(
                    child: SettingsSurfaces.section(
                      context,
                      CupertinoListSection(
                        dividerMargin: 0,
                        additionalDividerMargin: 0,

                        header: Text(group.name),
                        children: [
                          for (final model in [
                            ...group.models,
                            ...group.extraModels,
                          ])
                            CupertinoListTile(
                              key: ValueKey('model-option-${model.id}'),
                              backgroundColor: SettingsSurfaces.selection(
                                context,
                                model.id == currentState.defaultModel,
                              ),
                              title: Text(model.displayName),
                              trailing: model.id == currentState.defaultModel
                                  ? const Icon(CupertinoIcons.checkmark)
                                  : null,
                              onTap: () {
                                Navigator.of(context).pop();
                                unawaited(
                                  ref
                                      .read(settingsControllerProvider.notifier)
                                      .setDefaultModel(model.id),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 关于
// ---------------------------------------------------------------------------

/// 返回按钮：显式 [CupertinoNavigationBarBackButton.onPressed]，
/// 避免框架「仅可用于可 pop 路由」断言在首帧/测试环境误触发。
class _PopBackButton extends StatelessWidget {
  const _PopBackButton();

  @override
  Widget build(BuildContext context) {
    return CupertinoNavigationBarBackButton(
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}

/// 关于与更新分组：应用名 + 版本号 + 自动检查更新开关 + 检查更新按钮。
class _AboutSection extends ConsumerStatefulWidget {
  const _AboutSection();

  @override
  ConsumerState<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<_AboutSection> {
  bool _isChecking = false;

  /// 打开本应用公开仓库（外部浏览器）。
  ///
  /// 失败（无浏览器/被策略拦截/返回 false）时弹窗给出完整地址，
  /// 用户可一键复制地址手动访问，不静默吞掉。
  Future<void> _openRepository() async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(kHermesUiRepoUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }

    if (launched || !mounted) return;

    final l10n = AppLocalizations.of(context);
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => SettingsSurfaces.dialog(
        context,
        CupertinoAlertDialog(
          title: Text(l10n.actionFailed),
          content: const Text(kHermesUiRepoUrl),
          actions: [
            CupertinoDialogAction(
              child: Text(l10n.copy),
              onPressed: () {
                unawaited(
                  Clipboard.setData(
                    const ClipboardData(text: kHermesUiRepoUrl),
                  ),
                );
                Navigator.of(ctx).pop();
              },
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: Text(l10n.ok),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdate() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    UpdateCheckResult result;
    try {
      final checker = ref.read(updateCheckerServiceProvider);
      result = await checker.checkForUpdates(isManual: true);
    } on Object catch (error) {
      // 兜底：不把「服务内部自吞异常」当隐性契约。服务真抛错时给出与
      // result.status 异常分支一致的可见反馈，而不是让异常直穿 UI。
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'settings',
        message: '检查更新失败: $error',
        errorKind: error.toString(),
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        await showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => SettingsSurfaces.dialog(
            context,
            CupertinoAlertDialog(
              title: Text(l10n.updateSectionTitle),
              content: Text(l10n.updateCheckFailed),
              actions: [
                CupertinoDialogAction(
                  child: Text(l10n.ok),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }

    if (!mounted) return;

    final l10n = AppLocalizations.of(context);

    if (result.hasUpdate && result.release != null) {
      final release = result.release!;
      final releaseNotes = release.body.trim().isNotEmpty
          ? release.body.trim()
          : (release.name.isNotEmpty ? release.name : release.tagName);

      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => SettingsSurfaces.dialog(
          context,
          CupertinoAlertDialog(
            title: Text(l10n.updateDialogTitle(release.tagName)),
            content: Text(releaseNotes),
            actions: [
              CupertinoDialogAction(
                child: Text(l10n.cancel),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: Text(l10n.updateGoToDownload),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  unawaited(handleDownloadOrOpenRelease(context, ref, release));
                },
              ),
            ],
          ),
        ),
      );
    } else if (result.status == UpdateCheckStatus.upToDate) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => SettingsSurfaces.dialog(
          context,
          CupertinoAlertDialog(
            title: Text(l10n.updateSectionTitle),
            content: Text(l10n.updateAlreadyLatest),
            actions: [
              CupertinoDialogAction(
                child: Text(l10n.ok),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );
    } else {
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => SettingsSurfaces.dialog(
          context,
          CupertinoAlertDialog(
            title: Text(l10n.updateSectionTitle),
            content: Text(l10n.updateCheckFailed),
            actions: [
              CupertinoDialogAction(
                child: Text(l10n.ok),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 动态版本号：平台通道就绪后显示 pubspec version（如 0.1.2+4），
    // 未就绪/异常回退常量（settings_providers.dart appVersionProvider）。
    final version = ref.watch(appVersionProvider).value ?? appVersionFallback;
    final autoCheckEnabled = ref.watch(autoCheckUpdateEnabledProvider);

    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,
        header: Text(l10n.aboutSection),
        children: [
          CupertinoListTile(
            key: const ValueKey('settings-repo-tile'),
            title: const Text('Hermes UI'),
            subtitle: Text(l10n.hermesWebUIClient),
            trailing: const CupertinoListTileChevron(),
            onTap: () => unawaited(_openRepository()),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-version-tile'),
            title: Text(l10n.version),
            trailing: Text(
              version,
              style: TextStyle(
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.autoCheckUpdateLabel),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-auto-check-update-switch'),
                value: autoCheckEnabled,
                onChanged: (val) {
                  unawaited(
                    ref
                        .read(autoCheckUpdateEnabledProvider.notifier)
                        .setEnabled(val),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-check-update-tile'),
            title: Text(l10n.checkUpdateNowLabel),
            trailing: _isChecking
                ? const CupertinoActivityIndicator()
                : const CupertinoListTileChevron(),
            onTap: _isChecking ? null : _checkUpdate,
          ),
        ],
      ),
    );
  }
}

/// 统一错误文案：ApiException 展示其消息，其余给通用提示。
String _describeError(BuildContext context, Object error) {
  if (error is ApiException) return error.message;
  return AppLocalizations.of(context).loadFailedRetry;
}
