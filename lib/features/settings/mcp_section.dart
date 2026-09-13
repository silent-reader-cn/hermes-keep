import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/hermes_page_route.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/mcp.dart';
import '../../l10n/app_localizations.dart';
import 'settings_providers.dart';
import 'settings_surfaces.dart';

/// MCP 服务器管理分组（`_McpSection`，key: `settings-mcp-section`）。
///
/// 展示 MCP 服务器列表、启用开关、服务器详情/菜单（编辑、查看工具、删除）及添加服务器表单。
class McpSection extends ConsumerWidget {
  const McpSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mcpAsync = ref.watch(mcpControllerProvider);

    return mcpAsync.when(
      loading: () => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-mcp-section'),
          header: Text(l10n.mcpSection),
          children: [
            CupertinoListTile(
              title: Text(l10n.loadingMcpServers),
              trailing: const CupertinoActivityIndicator(),
            ),
          ],
        ),
      ),
      error: (error, _) => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-mcp-section'),
          header: Text(l10n.mcpSection),
          children: [
            CupertinoListTile(
              title: Text(l10n.mcpServersLoadFailed),
              subtitle: Text(_describeError(context, error)),
            ),
            CupertinoListTile(
              key: const ValueKey('settings-mcp-retry'),
              title: Text(l10n.retry),
              trailing: const Icon(CupertinoIcons.refresh),
              onTap: () =>
                  unawaited(ref.read(mcpControllerProvider.notifier).refresh()),
            ),
          ],
        ),
      ),
      data: (state) => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-mcp-section'),
          header: Text(l10n.mcpSection),
          children: [
            if (state.servers.isEmpty)
              CupertinoListTile(title: Text(l10n.noMcpServers)),
            for (final server in state.servers)
              _buildServerRow(context, ref, server, state.tools),
            CupertinoListTile(
              key: const ValueKey('settings-mcp-add'),
              leading: const Icon(CupertinoIcons.add_circled),
              title: Text(l10n.addMcpServer),
              onTap: () => unawaited(_openServerEditor(context, ref)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerRow(
    BuildContext context,
    WidgetRef ref,
    McpServer server,
    List<McpTool> tools,
  ) {
    final l10n = AppLocalizations.of(context);
    final isConnected = server.status == 'connected';
    final statusText = isConnected
        ? l10n.mcpStatusConnected
        : (server.status.isNotEmpty
              ? server.status
              : l10n.mcpStatusDisconnected);
    final cmdSummary = server.args.isNotEmpty
        ? '${server.command} ${server.args.join(' ')}'
        : server.command;

    return CupertinoListTile(
      key: ValueKey('mcp-server-row-${server.name}'),
      title: Text(server.name),
      subtitle: Text(
        '$cmdSummary · $statusText',
        style: TextStyle(
          color: (isConnected ? statusGreenText : statusGreyText).resolveFrom(
            context,
          ),
        ),
      ),
      trailing: SettingsSurfaces.toggle(
        context,
        CupertinoSwitch(
          key: ValueKey('mcp-toggle-${server.name}'),
          value: server.enabled,
          onChanged: (value) {
            unawaited(
              ref
                  .read(mcpControllerProvider.notifier)
                  .toggleServer(server.name, value),
            );
          },
        ),
      ),
      onTap: () => unawaited(_showServerMenu(context, ref, server, tools)),
    );
  }

  Future<void> _showServerMenu(
    BuildContext context,
    WidgetRef ref,
    McpServer server,
    List<McpTool> tools,
  ) {
    final l10n = AppLocalizations.of(context);
    final serverTools = tools.where((t) => t.server == server.name).toList();

    return showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => SettingsSurfaces.sheet(
        context,
        CupertinoActionSheet(
          title: Text(server.name),
          message: Text(server.command),
          actions: [
            CupertinoActionSheetAction(
              key: ValueKey('mcp-tools-${server.name}'),
              onPressed: () {
                Navigator.of(modalContext).pop();
                unawaited(_openToolsPage(context, server, serverTools));
              },
              child: Text('${l10n.mcpTools} (${serverTools.length})'),
            ),
            CupertinoActionSheetAction(
              key: ValueKey('mcp-edit-${server.name}'),
              onPressed: () {
                Navigator.of(modalContext).pop();
                unawaited(_openServerEditor(context, ref, server: server));
              },
              child: Text(l10n.editMcpServer),
            ),
            CupertinoActionSheetAction(
              key: ValueKey('mcp-delete-${server.name}'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(modalContext).pop();
                unawaited(_confirmDelete(context, ref, server));
              },
              child: Text(l10n.deleteMcpServer),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(modalContext).pop(),
            child: Text(l10n.cancel),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    McpServer server,
  ) {
    final l10n = AppLocalizations.of(context);

    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => SettingsSurfaces.dialog(
        context,
        CupertinoAlertDialog(
          title: Text(l10n.deleteMcpServer),
          content: Text(l10n.confirmDeleteMcpServer(server.name)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            CupertinoDialogAction(
              key: const ValueKey('mcp-delete-confirm'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  ref
                      .read(mcpControllerProvider.notifier)
                      .deleteServer(server.name),
                );
              },
              child: Text(l10n.delete),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openServerEditor(
    BuildContext context,
    WidgetRef ref, {
    McpServer? server,
  }) {
    return Navigator.of(context).push(
      HermesPageRoute<void>(
        builder: (context) => McpServerEditorPage(server: server),
      ),
    );
  }

  Future<void> _openToolsPage(
    BuildContext context,
    McpServer server,
    List<McpTool> tools,
  ) {
    return Navigator.of(context).push(
      HermesPageRoute<void>(
        builder: (context) => McpToolsPage(server: server, tools: tools),
      ),
    );
  }
}

/// MCP 服务器添加/编辑页面。
class McpServerEditorPage extends ConsumerStatefulWidget {
  const McpServerEditorPage({super.key, this.server});

  final McpServer? server;

  @override
  ConsumerState<McpServerEditorPage> createState() =>
      _McpServerEditorPageState();
}

class _McpServerEditorPageState extends ConsumerState<McpServerEditorPage> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.server?.name ?? '',
  );
  late final TextEditingController _commandController = TextEditingController(
    text: widget.server?.command ?? '',
  );
  late final TextEditingController _argsController = TextEditingController(
    text: widget.server?.args.join('\n') ?? '',
  );
  late final TextEditingController _envController = TextEditingController(
    text: widget.server?.env != null && widget.server!.env!.isNotEmpty
        ? const JsonEncoder.withIndent('  ').convert(widget.server!.env)
        : '',
  );

  late bool _enabled = widget.server?.enabled ?? true;
  String _error = '';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _envController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    final command = _commandController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = l10n.mcpServerNameRequired);
      return;
    }
    if (command.isEmpty) {
      setState(() => _error = l10n.mcpCommandRequired);
      return;
    }

    final rawArgs = _argsController.text.trim();
    final List<String> args;
    if (rawArgs.isEmpty) {
      args = const [];
    } else if (rawArgs.contains('\n')) {
      args = rawArgs
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      args = rawArgs
          .split(RegExp(r'\s+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    Map<String, String>? env;
    final rawEnv = _envController.text.trim();
    if (rawEnv.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEnv);
        if (decoded is Map) {
          env = {};
          for (final entry in decoded.entries) {
            env[entry.key.toString()] = entry.value?.toString() ?? '';
          }
        } else {
          setState(() => _error = l10n.mcpEnvInvalidJson);
          return;
        }
      } catch (_) {
        setState(() => _error = l10n.mcpEnvInvalidJson);
        return;
      }
    }

    setState(() => _saving = true);
    final ok = await ref
        .read(mcpControllerProvider.notifier)
        .saveServer(
          name,
          command: command,
          args: args,
          env: env,
          enabled: _enabled,
        );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      final actionError = ref
          .read(mcpControllerProvider)
          .valueOrNull
          ?.actionError;
      setState(() {
        _saving = false;
        _error = actionError ?? 'Failed to save MCP server';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = widget.server != null;

    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const _PopBackButton(),
          middle: Text(isEditing ? l10n.editMcpServer : l10n.addMcpServer),
          trailing: CupertinoButton(
            foregroundColor: SettingsSurfaces.actionColor(
              context,
              disabled: _saving,
            ),
            pressedOpacity: SettingsSurfaces.pressedOpacity(context),
            key: const ValueKey('mcp-editor-save'),
            padding: EdgeInsets.zero,
            onPressed: _saving ? null : () => unawaited(_save()),
            child: Text(l10n.save),
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('mcp-editor-name'),
                controller: _nameController,
                placeholder: l10n.mcpServerName,
                readOnly: isEditing,
                autocorrect: false,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('mcp-editor-command'),
                controller: _commandController,
                placeholder: l10n.mcpCommand,
                autocorrect: false,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('mcp-editor-args'),
                controller: _argsController,
                placeholder: l10n.mcpArgsPlaceholder,
                autocorrect: false,
                maxLines: 3,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('mcp-editor-env'),
                controller: _envController,
                placeholder: l10n.mcpEnv,
                autocorrect: false,
                maxLines: 3,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 12),
              SettingsSurfaces.section(
                context,
                CupertinoListSection(
                  children: [
                    CupertinoListTile(
                      title: Text(l10n.mcpServerEnabled),
                      trailing: SettingsSurfaces.toggle(
                        context,
                        CupertinoSwitch(
                          key: const ValueKey('mcp-editor-enabled'),
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error,
                    style: TextStyle(color: statusRedText.resolveFrom(context)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// MCP 工具列表页面。
class McpToolsPage extends StatelessWidget {
  const McpToolsPage({super.key, required this.server, required this.tools});

  final McpServer server;
  final List<McpTool> tools;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const _PopBackButton(),
          middle: Text('${server.name} · ${l10n.mcpTools}'),
        ),
        child: SafeArea(
          child: tools.isEmpty
              ? Center(
                  child: Text(
                    l10n.noMcpTools,
                    style: TextStyle(
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: secondaryText,
                      ),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    SettingsSurfaces.section(
                      context,
                      CupertinoListSection(
                        header: Text(l10n.mcpToolsCount(tools.length)),
                        children: [
                          for (final tool in tools)
                            CupertinoListTile(
                              key: ValueKey('mcp-tool-row-${tool.name}'),
                              title: Text(tool.name),
                              subtitle: Text(
                                tool.description.isNotEmpty
                                    ? tool.description
                                    : l10n.noDescription,
                                style: TextStyle(
                                  color: LightSurfaces.resolve(
                                    context,
                                    LightSurfaces.textSecondary,
                                    dark: secondaryText,
                                  ),
                                ),
                              ),
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
