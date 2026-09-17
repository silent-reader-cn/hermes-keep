import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/hermes_page_route.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/extensions.dart';
import '../../l10n/app_localizations.dart';
import 'settings_providers.dart';
import 'settings_surfaces.dart';

/// 扩展生态分组（`_ExtensionsSection`，key: `settings-extensions-section`）。
///
/// 展示已安装扩展列表、启停开关、详情 sheet（Sidecar 授权、卸载）及安装表单。
class ExtensionsSection extends ConsumerWidget {
  const ExtensionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final extensionsAsync = ref.watch(extensionsControllerProvider);

    return extensionsAsync.when(
      loading: () => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-extensions-section'),
          header: Text(l10n.extensionsSection),
          children: [
            CupertinoListTile(
              title: Text(l10n.loadingExtensions),
              trailing: const CupertinoActivityIndicator(),
            ),
          ],
        ),
      ),
      error: (error, _) => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-extensions-section'),
          header: Text(l10n.extensionsSection),
          children: [
            CupertinoListTile(
              title: Text(l10n.extensionsLoadFailed),
              subtitle: Text(_describeError(context, error)),
            ),
            CupertinoListTile(
              key: const ValueKey('settings-extensions-retry'),
              title: Text(l10n.retry),
              trailing: const Icon(CupertinoIcons.refresh),
              onTap: () => unawaited(
                ref.read(extensionsControllerProvider.notifier).refresh(),
              ),
            ),
          ],
        ),
      ),
      data: (state) => SettingsSurfaces.section(
        context,
        CupertinoListSection(
          key: const ValueKey('settings-extensions-section'),
          header: Text(l10n.extensionsSection),
          children: [
            if (state.extensions.isEmpty)
              CupertinoListTile(
                title: Text(l10n.noExtensions),
                subtitle: Text(
                  state.registry.isNotEmpty
                      ? l10n.selectFromRegistry
                      : l10n.extensionsTitle,
                  style: TextStyle(
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: secondaryText,
                    ),
                  ),
                ),
              ),
            for (final ext in state.extensions)
              _buildExtensionRow(context, ref, ext),
            CupertinoListTile(
              key: const ValueKey('settings-extension-install'),
              leading: const Icon(CupertinoIcons.add_circled),
              title: Text(l10n.installExtension),
              onTap: () =>
                  unawaited(_openInstallPage(context, ref, state.registry)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtensionRow(
    BuildContext context,
    WidgetRef ref,
    ExtensionInfo ext,
  ) {
    final l10n = AppLocalizations.of(context);
    final displayName = ext.name.isNotEmpty ? ext.name : ext.id;
    final sidecarInfo = ext.sidecarActive
        ? ' · ${l10n.extensionSidecarActive}'
        : '';

    return CupertinoListTile(
      key: ValueKey('extension-row-${ext.id}'),
      title: Text(displayName),
      subtitle: Text(
        '${ext.id}$sidecarInfo',
        style: TextStyle(
          color: ext.sidecarActive
              ? statusGreenText.resolveFrom(context)
              : LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
        ),
      ),
      trailing: SettingsSurfaces.toggle(
        context,
        CupertinoSwitch(
          key: ValueKey('extension-toggle-${ext.id}'),
          value: ext.enabled,
          onChanged: (value) {
            unawaited(
              ref
                  .read(extensionsControllerProvider.notifier)
                  .toggleExtension(ext.id, value),
            );
          },
        ),
      ),
      onTap: () => unawaited(_showExtensionActions(context, ref, ext)),
    );
  }

  Future<void> _showExtensionActions(
    BuildContext context,
    WidgetRef ref,
    ExtensionInfo ext,
  ) {
    final l10n = AppLocalizations.of(context);
    final displayName = ext.name.isNotEmpty ? ext.name : ext.id;

    return showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => SettingsSurfaces.sheet(
        context,
        CupertinoActionSheet(
          title: Text(displayName),
          message: Text(ext.id),
          actions: [
            CupertinoActionSheetAction(
              key: ValueKey('extension-sidecar-${ext.id}'),
              onPressed: () {
                Navigator.of(modalContext).pop();
                unawaited(
                  ref
                      .read(extensionsControllerProvider.notifier)
                      .setSidecarConsent(ext.id, !ext.sidecarProxyConsent),
                );
              },
              child: Text(
                '${l10n.extensionSidecarConsent}: '
                '${ext.sidecarProxyConsent ? l10n.statusNormal : l10n.statusDisabled}',
              ),
            ),
            CupertinoActionSheetAction(
              key: ValueKey('extension-uninstall-${ext.id}'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(modalContext).pop();
                unawaited(_confirmUninstall(context, ref, ext));
              },
              child: Text(l10n.uninstall),
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

  Future<void> _confirmUninstall(
    BuildContext context,
    WidgetRef ref,
    ExtensionInfo ext,
  ) {
    final l10n = AppLocalizations.of(context);
    final displayName = ext.name.isNotEmpty ? ext.name : ext.id;

    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => SettingsSurfaces.dialog(
        context,
        CupertinoAlertDialog(
          title: Text(l10n.uninstallExtension),
          content: Text(l10n.confirmUninstallExtension(displayName)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            CupertinoDialogAction(
              key: const ValueKey('extension-uninstall-confirm'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  ref
                      .read(extensionsControllerProvider.notifier)
                      .uninstallExtension(ext.id),
                );
              },
              child: Text(l10n.uninstall),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInstallPage(
    BuildContext context,
    WidgetRef ref,
    List<ExtensionRegistryItem> registry,
  ) {
    return Navigator.of(context).push(
      HermesPageRoute<void>(
        builder: (context) => ExtensionInstallPage(registry: registry),
      ),
    );
  }
}

/// 扩展安装表单页（id / download_url / sha256）。
class ExtensionInstallPage extends ConsumerStatefulWidget {
  const ExtensionInstallPage({super.key, this.registry = const []});

  final List<ExtensionRegistryItem> registry;

  @override
  ConsumerState<ExtensionInstallPage> createState() =>
      _ExtensionInstallPageState();
}

class _ExtensionInstallPageState extends ConsumerState<ExtensionInstallPage> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _sha256Controller = TextEditingController();

  String _error = '';
  bool _saving = false;

  @override
  void dispose() {
    _idController.dispose();
    _urlController.dispose();
    _sha256Controller.dispose();
    super.dispose();
  }

  void _selectRegistryItem(ExtensionRegistryItem item) {
    setState(() {
      _idController.text = item.id;
      _urlController.text = item.downloadUrl;
      _sha256Controller.text = item.sha256;
      _error = '';
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final id = _idController.text.trim();
    final url = _urlController.text.trim();
    final sha256 = _sha256Controller.text.trim();

    if (id.isEmpty) {
      setState(() => _error = 'Extension ID is required');
      return;
    }

    setState(() => _saving = true);
    final ok = await ref
        .read(extensionsControllerProvider.notifier)
        .installExtension(id: id, downloadUrl: url, sha256: sha256);

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      final actionError = ref
          .read(extensionsControllerProvider)
          .valueOrNull
          ?.actionError;
      setState(() {
        _saving = false;
        _error = actionError ?? 'Install failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsSurfaces.page(
      context,
      CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          border: SettingsSurfaces.navigationBorder(context),
          leading: const _PopBackButton(),
          middle: Text(l10n.installExtension),
          trailing: CupertinoButton(
            foregroundColor: SettingsSurfaces.actionColor(
              context,
              disabled: _saving,
            ),
            pressedOpacity: SettingsSurfaces.pressedOpacity(context),
            key: const ValueKey('extension-install-submit'),
            padding: EdgeInsets.zero,
            onPressed: _saving ? null : () => unawaited(_submit()),
            child: Text(l10n.save),
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.registry.isNotEmpty) ...[
                SettingsSurfaces.section(
                  context,
                  CupertinoListSection(
                    header: Text(l10n.extensionRegistry),
                    children: [
                      for (final item in widget.registry)
                        CupertinoListTile(
                          key: ValueKey('registry-item-${item.id}'),
                          title: Text(
                            item.name.isNotEmpty ? item.name : item.id,
                          ),
                          subtitle: Text(
                            '${item.id} · ${item.version}',
                            style: TextStyle(
                              color: LightSurfaces.resolve(
                                context,
                                LightSurfaces.textSecondary,
                                dark: secondaryText,
                              ),
                            ),
                          ),
                          trailing: Icon(
                            CupertinoIcons.chevron_right,
                            size: 16,
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.textSecondary,
                              dark: CupertinoColors.systemGrey,
                            ),
                          ),
                          onTap: () => _selectRegistryItem(item),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('extension-install-id'),
                controller: _idController,
                placeholder: l10n.extensionId,
                autocorrect: false,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('extension-install-url'),
                controller: _urlController,
                placeholder: l10n.extensionDownloadUrl,
                autocorrect: false,
                keyboardType: TextInputType.url,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('extension-install-sha256'),
                controller: _sha256Controller,
                placeholder: l10n.extensionSha256,
                autocorrect: false,
                padding: const EdgeInsets.all(12),
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
