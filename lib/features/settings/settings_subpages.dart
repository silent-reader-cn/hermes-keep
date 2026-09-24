import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../desktop/desktop_settings.dart';
import '../session_list/session_entry_visibility.dart';
import '../session_list/session_row_subtitle_settings.dart';
import '../webui_sidecar/webui_sidecar_providers.dart';
import 'auxiliary_models_section.dart';
import 'extensions_section.dart';
import 'mcp_section.dart';
import 'settings_surfaces.dart';
import 'sidebar_nav_order_settings.dart';
import 'webui_sidecar_section.dart';

/// 返回按钮：显式 [CupertinoNavigationBarBackButton.onPressed]，
/// 避免框架「仅可用于可 pop 路由」断言在首帧/测试环境误触发。
class PopBackButton extends StatelessWidget {
  const PopBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoNavigationBarBackButton(
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. 辅助模型二级页
// ---------------------------------------------------------------------------

class AuxiliaryModelsPage extends StatelessWidget {
  const AuxiliaryModelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const PopBackButton(),
          middle: Text(l10n.auxiliaryModelsSection),
        ),
        child: ListView(children: const [AuxiliaryModelsSection()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. MCP 服务器二级页
// ---------------------------------------------------------------------------

class McpPage extends StatelessWidget {
  const McpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const PopBackButton(),
          middle: Text(l10n.mcpSection),
        ),
        child: ListView(children: const [McpSection()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. 扩展生态二级页
// ---------------------------------------------------------------------------

class ExtensionsPage extends StatelessWidget {
  const ExtensionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const PopBackButton(),
          middle: Text(l10n.extensionsSection),
        ),
        child: ListView(children: const [ExtensionsSection()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. 会话列表入口二级页
// ---------------------------------------------------------------------------

class SessionListEntriesPage extends StatelessWidget {
  const SessionListEntriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const PopBackButton(),
          middle: Text(l10n.sessionListEntriesSection),
        ),
        child: ListView(children: const [SessionListEntriesSection()]),
      ),
    );
  }
}

/// 会话列表入口显隐分组（TASK W5 / 蓝本 SidebarSectionVisibility）。
class SessionListEntriesSection extends ConsumerWidget {
  const SessionListEntriesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final visibility = ref.watch(sessionEntryVisibilityProvider);
    final controller = ref.read(sessionEntryVisibilityProvider.notifier);

    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        header: Text(l10n.sessionListEntriesSection),
        children: [
          CupertinoListTile(
            title: Text(l10n.tasksTitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-visibility-tasks'),
                value: visibility.tasks,
                onChanged: (value) {
                  unawaited(controller.setVisible('tasks', value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.kanbanTitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-visibility-kanban'),
                value: visibility.kanban,
                onChanged: (value) {
                  unawaited(controller.setVisible('kanban', value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.workspacesTitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-visibility-workspaces'),
                value: visibility.workspaces,
                onChanged: (value) {
                  unawaited(controller.setVisible('workspaces', value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.skillsTitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-visibility-skills'),
                value: visibility.skills,
                onChanged: (value) {
                  unawaited(controller.setVisible('skills', value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.insightsTitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-visibility-insights'),
                value: visibility.insights,
                onChanged: (value) {
                  unawaited(controller.setVisible('insights', value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.memoryTitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-visibility-memory'),
                value: visibility.memory,
                onChanged: (value) {
                  unawaited(controller.setVisible('memory', value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.downloadsTitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-visibility-downloads'),
                value: visibility.downloads,
                onChanged: (value) {
                  unawaited(controller.setVisible('downloads', value));
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
// 5. 会话行信息二级页
// ---------------------------------------------------------------------------

class SessionRowSubtitlePage extends StatelessWidget {
  const SessionRowSubtitlePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const PopBackButton(),
          middle: Text(l10n.sessionRowSubtitleSection),
        ),
        child: ListView(children: const [SessionRowSubtitleSection()]),
      ),
    );
  }
}

/// 会话行信息分组：会话行副标题显示项开关（消息数 / 项目名 / 工作区 /
/// 渠道 / 预估价钱；渠道与预估价钱默认关闭）。
class SessionRowSubtitleSection extends ConsumerWidget {
  const SessionRowSubtitleSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(sessionRowSubtitleSettingsProvider);
    final controller = ref.read(sessionRowSubtitleSettingsProvider.notifier);

    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        header: Text(l10n.sessionRowSubtitleSection),
        children: [
          CupertinoListTile(
            title: Text(l10n.sessionRowShowMessageCount),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-subtitle-message-count'),
                value: settings.messageCount,
                onChanged: (value) {
                  unawaited(controller.setMessageCount(value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.sessionRowShowProjectName),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-subtitle-project-name'),
                value: settings.projectName,
                onChanged: (value) {
                  unawaited(controller.setProjectName(value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.sessionRowShowWorkspace),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-subtitle-workspace'),
                value: settings.workspace,
                onChanged: (value) {
                  unawaited(controller.setWorkspace(value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.sessionRowShowChannel),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-subtitle-channel'),
                value: settings.channel,
                onChanged: (value) {
                  unawaited(controller.setChannel(value));
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.sessionRowShowEstimatedCost),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-subtitle-estimated-cost'),
                value: settings.estimatedCost,
                onChanged: (value) {
                  unawaited(controller.setEstimatedCost(value));
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
// 6. 桌面设置二级页
// ---------------------------------------------------------------------------

/// 桌面设置二级页。
///
/// 「内置 WebUI 服务」分组按**注入的平台判定**（`SidecarFileSystem.isWindows`）
/// 决定是否渲染，而不是宿主 `Platform.isWindows`：平台语义是决策输入，
/// 必须能被测试覆写，否则 CI（Linux）上该分组永远缺席、用例只能假红。
class DesktopSettingsPage extends ConsumerWidget {
  const DesktopSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const PopBackButton(),
          middle: Text(l10n.desktopSection),
        ),
        child: ListView(
          children: [
            const DesktopSection(),
            if (ref.watch(sidecarFileSystemProvider).isWindows)
              const WebuiSidecarSection(),
          ],
        ),
      ),
    );
  }
}

/// 桌面分组：最小化到托盘 / 全局快捷键 / 记住窗口位置。
class DesktopSection extends ConsumerWidget {
  const DesktopSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(desktopSettingsProvider);
    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,

        header: Text(l10n.desktopSection),
        children: [
          CupertinoListTile(
            title: Text(l10n.minimizeToTray),
            subtitle: Text(l10n.minimizeToTraySubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-desktop-minimize-to-tray'),
                value: settings.minimizeToTray,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(desktopSettingsProvider.notifier)
                        .setMinimizeToTray(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.globalShortcuts),
            subtitle: Text(l10n.globalShortcutsSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-desktop-global-shortcuts'),
                value: settings.globalShortcutsEnabled,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(desktopSettingsProvider.notifier)
                        .setGlobalShortcutsEnabled(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.rememberWindowPosition),
            subtitle: Text(l10n.rememberWindowPositionSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-desktop-remember-window'),
                value: settings.rememberWindowPosition,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(desktopSettingsProvider.notifier)
                        .setRememberWindowPosition(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.startOnLogin),
            subtitle: Text(l10n.startOnLoginSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-desktop-start-on-login'),
                value: settings.startOnLogin,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(desktopSettingsProvider.notifier)
                        .setStartOnLogin(value),
                  );
                },
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.silentStart),
            subtitle: Text(l10n.silentStartSubtitle),
            trailing: SettingsSurfaces.toggle(
              context,
              CupertinoSwitch(
                key: const ValueKey('settings-desktop-silent-start'),
                value: settings.silentStart,
                onChanged: (value) {
                  unawaited(
                    ref
                        .read(desktopSettingsProvider.notifier)
                        .setSilentStart(value),
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
// #154. 侧栏导航入口（位置 + 顺序）二级页
// ---------------------------------------------------------------------------

class SidebarNavOrderPage extends StatelessWidget {
  const SidebarNavOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const PopBackButton(),
          middle: Text(l10n.sidebarNavOrderSection),
        ),
        child: ListView(children: const [SidebarNavOrderSection()]),
      ),
    );
  }
}
