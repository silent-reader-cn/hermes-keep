import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/status_colors.dart';
import '../../core/api/api_client_server_panels.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/server_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../session_list/session_list_providers.dart';
import 'settings_surfaces.dart';

/// Profile 管理区块：服务端 profile 与本地服务器是两个独立概念。
class ProfileSection extends ConsumerStatefulWidget {
  const ProfileSection({super.key});

  @override
  ConsumerState<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<ProfileSection> {
  ProfilesResponse? _profiles;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref.read(apiClientProvider).profiles();
      if (mounted) setState(() => _profiles = response);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switch(ProfileSummary profile) async {
    final name = profile.name ?? '';
    if (name.isEmpty || name == _profiles?.active) return;
    setState(() => _loading = true);
    try {
      final response = await ref.read(apiClientProvider).switchProfile(name);
      if (mounted) {
        setState(() => _profiles = response.toProfilesResponse(name));
        ref.invalidate(sessionListControllerProvider);
      }
    } catch (error) {
      if (mounted) await _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showError(Object error) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profiles = _profiles?.profiles ?? const <ProfileSummary>[];
    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        header: Text(l10n.profile),
        children: [
          CupertinoListTile(
            title: Text(
              _profiles?.active ??
                  (_loading ? l10n.loadingEllipsis : l10n.notRead),
            ),
            leading: const Icon(CupertinoIcons.person_2),
            trailing: const CupertinoListTileChevron(),
            onTap: profiles.isEmpty ? _load : () => _showPicker(profiles),
          ),
          if (_error != null)
            CupertinoListTile(
              title: Text(l10n.readFailed),
              subtitle: Text(l10n.clickToRetry),
              onTap: _load,
            ),
        ],
      ),
    );
  }

  Future<void> _showPicker(List<ProfileSummary> profiles) async {
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
    if (selected != null) await _switch(selected);
  }
}

extension on ProfileSwitchResponse {
  ProfilesResponse toProfilesResponse(String fallback) =>
      ProfilesResponse(profiles: profiles, active: active ?? fallback);
}
