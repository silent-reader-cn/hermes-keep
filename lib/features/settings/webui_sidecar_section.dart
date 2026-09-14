import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../l10n/app_localizations.dart';
import '../webui_sidecar/webui_sidecar_providers.dart';
import 'settings_surfaces.dart';

/// 设置页「内置 WebUI 服务」配置与状态分组。
class WebuiSidecarSection extends ConsumerStatefulWidget {
  const WebuiSidecarSection({super.key});

  @override
  ConsumerState<WebuiSidecarSection> createState() =>
      _WebuiSidecarSectionState();
}

class _WebuiSidecarSectionState extends ConsumerState<WebuiSidecarSection> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _hostFocusNode = FocusNode();
  final FocusNode _portFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  String? _hostError;
  String? _portError;
  String? _passwordError;

  bool _isToggling = false;
  bool _passwordObscured = true;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _hostFocusNode.addListener(_onHostFocusChange);
    _portFocusNode.addListener(_onPortFocusChange);
    _passwordFocusNode.addListener(_onPasswordFocusChange);
  }

  @override
  void dispose() {
    _hostFocusNode.removeListener(_onHostFocusChange);
    _portFocusNode.removeListener(_onPortFocusChange);
    _passwordFocusNode.removeListener(_onPasswordFocusChange);

    _hostFocusNode.dispose();
    _portFocusNode.dispose();
    _passwordFocusNode.dispose();

    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onHostFocusChange() {
    if (!_hostFocusNode.hasFocus) {
      _submitHost();
    }
  }

  void _onPortFocusChange() {
    if (!_portFocusNode.hasFocus) {
      _submitPort();
    }
  }

  void _onPasswordFocusChange() {
    if (!_passwordFocusNode.hasFocus) {
      _submitPassword();
    }
  }

  void _submitHost() {
    final l10n = AppLocalizations.of(context);
    final text = _hostController.text.trim();
    final addr = InternetAddress.tryParse(text);
    if (addr == null || addr.type != InternetAddressType.IPv4) {
      setState(() {
        _hostError = l10n.webuiInvalidHost;
      });
      return;
    }
    setState(() {
      _hostError = null;
    });
    final currentHost = ref.read(webuiSidecarConfigProvider).host;
    if (text != currentHost) {
      unawaited(ref.read(webuiSidecarConfigProvider.notifier).setHost(text));
    }
  }

  void _submitPort() {
    final l10n = AppLocalizations.of(context);
    final text = _portController.text.trim();
    final port = int.tryParse(text);
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _portError = l10n.webuiInvalidPort;
      });
      return;
    }
    setState(() {
      _portError = null;
    });
    final currentPort = ref.read(webuiSidecarConfigProvider).port;
    if (port != currentPort) {
      unawaited(ref.read(webuiSidecarConfigProvider.notifier).setPort(port));
    }
  }

  void _submitPassword() {
    final l10n = AppLocalizations.of(context);
    final text = _passwordController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _passwordError = l10n.webuiPasswordEmpty;
      });
      return;
    }
    setState(() {
      _passwordError = null;
    });
    final currentPassword = ref.read(webuiSidecarConfigProvider).password;
    if (text != currentPassword) {
      unawaited(
        ref.read(webuiSidecarConfigProvider.notifier).setPassword(text),
      );
    }
  }

  Future<void> _showMissingAgentDialog() async {
    final l10n = AppLocalizations.of(context);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) {
        return SettingsSurfaces.dialog(
          context,
          CupertinoAlertDialog(
            key: const ValueKey('settings-webui-missing-agent-dialog'),
            title: Text(l10n.agentGateNeedInstallTitle),
            content: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(l10n.agentGateNeedInstallDesc),
            ),
            actions: [
              CupertinoDialogAction(
                key: const ValueKey('settings-webui-dialog-cancel-btn'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: Text(l10n.agentGateCancel),
              ),
              CupertinoDialogAction(
                key: const ValueKey('settings-webui-dialog-guide-btn'),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  try {
                    await launchUrl(
                      Uri.parse(hermesAgentDocsUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {}
                },
                child: Text(l10n.agentGateGoToInstallGuide),
              ),
              CupertinoDialogAction(
                key: const ValueKey('settings-webui-dialog-recheck-btn'),
                isDefaultAction: true,
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await ref.read(agentEnvPresentProvider.notifier).refresh();
                },
                child: Text(l10n.agentGateRecheck),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleToggle(bool value) async {
    if (value) {
      final isAgentPresent = ref.read(agentEnvPresentProvider).value ?? false;
      if (!isAgentPresent) {
        await _showMissingAgentDialog();
        return;
      }
    }

    setState(() => _isToggling = true);
    try {
      await ref.read(webuiSidecarConfigProvider.notifier).setEnabled(value);
      if (value) {
        await ref.read(webuiSidecarControllerProvider.notifier).start();
      } else {
        await ref.read(webuiSidecarControllerProvider.notifier).stop();
      }
    } finally {
      if (mounted) {
        setState(() => _isToggling = false);
      }
    }
  }

  Future<void> _openLogDirectory() async {
    final fs = ref.read(sidecarFileSystemProvider);
    final logDir = fs.logDirectoryPath;
    final dir = Directory(logDir);
    if (!dir.existsSync()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }
    // 平台判定走注入接缝（宿主在 CI 上是 Linux）。
    if (fs.isWindows) {
      await Process.run('explorer', [logDir]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(webuiSidecarConfigProvider);
    final sidecarState = ref.watch(webuiSidecarControllerProvider);
    final fs = ref.watch(sidecarFileSystemProvider);
    final isBundleAvailable = ref.watch(bundledWebuiAvailableProvider);

    // 联动更新文本框（未聚焦编辑时跟随配置变化）
    ref.listen<SidecarConfig>(webuiSidecarConfigProvider, (prev, next) {
      if (!_hostFocusNode.hasFocus) {
        _hostController.text = next.host;
      }
      if (!_portFocusNode.hasFocus) {
        _portController.text = next.port.toString();
      }
      if (!_passwordFocusNode.hasFocus) {
        _passwordController.text = next.password;
      }
    });

    if (!_isInitialized) {
      _hostController.text = config.host;
      _portController.text = config.port.toString();
      _passwordController.text = config.password;
      _isInitialized = true;
    }

    final isMissingBundle = !fs.isWindows || !isBundleAvailable;

    return SettingsSurfaces.section(
      context,
      CupertinoListSection(
        dividerMargin: 0,
        additionalDividerMargin: 0,
        header: Text(l10n.webuiSectionTitle),
        children: [
          if (isMissingBundle)
            CupertinoListTile(
              key: const ValueKey('settings-webui-missing-bundle-hint'),
              leading: Icon(
                CupertinoIcons.info_circle,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.secondaryLabel,
                ),
                size: 20,
              ),
              title: Text(
                l10n.webuiBundleMissingHint,
                style: TextStyle(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                  fontSize: 13,
                ),
              ),
            ),
          CupertinoListTile(
            title: Text(l10n.webuiEnableTitle),
            subtitle: Text(l10n.webuiEnableSubtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isToggling)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: CupertinoActivityIndicator(),
                  ),
                SettingsSurfaces.toggle(
                  context,
                  CupertinoSwitch(
                    key: const ValueKey('settings-webui-enable-switch'),
                    value: config.enabled,
                    onChanged: _isToggling ? null : _handleToggle,
                  ),
                ),
              ],
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.webuiListeningHost),
            subtitle: _hostError != null
                ? Text(
                    _hostError!,
                    style: TextStyle(
                      color: statusRedText.resolveFrom(context),
                      fontSize: 12,
                    ),
                  )
                : null,
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('settings-webui-host-input'),
                controller: _hostController,
                focusNode: _hostFocusNode,
                textAlign: TextAlign.end,
                placeholder: SidecarConfig.defaultHost,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                onSubmitted: (_) => _submitHost(),
              ),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.webuiListeningPort),
            subtitle: _portError != null
                ? Text(
                    _portError!,
                    style: TextStyle(
                      color: statusRedText.resolveFrom(context),
                      fontSize: 12,
                    ),
                  )
                : null,
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('settings-webui-port-input'),
                controller: _portController,
                focusNode: _portFocusNode,
                textAlign: TextAlign.end,
                keyboardType: TextInputType.number,
                placeholder: SidecarConfig.defaultPort.toString(),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                onSubmitted: (_) => _submitPort(),
              ),
            ),
          ),
          _buildPasswordTile(context, l10n, config),
          _buildStatusTile(context, l10n, sidecarState),
          CupertinoListTile(
            key: const ValueKey('settings-webui-open-logs'),
            title: Text(l10n.webuiOpenLogs),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: const Color(0xFF8E8E93),
              ),
            ),
            onTap: () {
              unawaited(_openLogDirectory());
            },
          ),
        ],
      ),
    );
  }

  /// 密码行：与端口/IP 统一的右对齐内联密码框（无 subtitle、无按钮）。
  /// 默认遮罩，眼睛图标切显隐；编辑失焦/回车即写回。
  Widget _buildPasswordTile(
    BuildContext context,
    AppLocalizations l10n,
    SidecarConfig config,
  ) {
    return CupertinoListTile(
      key: const ValueKey('settings-webui-password-tile'),
      title: Text(l10n.webuiPassword),
      subtitle: _passwordError != null
          ? Text(
              _passwordError!,
              style: TextStyle(
                color: statusRedText.resolveFrom(context),
                fontSize: 12,
              ),
            )
          : null,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: CupertinoTextField(
                decoration: SettingsSurfaces.fieldDecoration(context),
                placeholderStyle: SettingsSurfaces.placeholderStyle(context),
                key: const ValueKey('settings-webui-password-input'),
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                textAlign: TextAlign.end,
                obscureText: _passwordObscured,
                placeholder: l10n.webuiPasswordPlaceholder,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                onChanged: (_) {
                  if (_passwordError != null) {
                    setState(() => _passwordError = null);
                  }
                },
                onSubmitted: (_) => _submitPassword(),
              ),
            ),
            CupertinoButton(
              foregroundColor: SettingsSurfaces.actionColor(context),
              pressedOpacity: SettingsSurfaces.pressedOpacity(context),
              key: const ValueKey('settings-webui-password-visibility-btn'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: const Size(0, 28),
              onPressed: () {
                setState(() => _passwordObscured = !_passwordObscured);
              },
              child: Icon(
                _passwordObscured
                    ? CupertinoIcons.eye
                    : CupertinoIcons.eye_slash,
                size: 18,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTile(
    BuildContext context,
    AppLocalizations l10n,
    SidecarState state,
  ) {
    final String statusText;
    final Color statusColor;
    String? subtitle;
    Color? subtitleColor;

    switch (state.status) {
      case SidecarStatus.running:
        statusText = '● ${l10n.webuiStatusRunning}';
        statusColor = statusGreenText.resolveFrom(context);
        if (state.detail != null && state.detail!.isNotEmpty) {
          // P2-11：service 内部 detail 为英文诊断串，UI 消费处映射 l10n。
          final detail = state.detail!;
          final lower = detail.toLowerCase();
          if (lower.contains('takeover')) {
            subtitle = l10n.webuiDetailTakeover;
          } else if (lower.contains('restarting')) {
            final attempt = RegExp(r'(\d+)').firstMatch(detail)?.group(1);
            subtitle = l10n.webuiDetailRestarting(
              int.tryParse(attempt ?? '') ?? 0,
            );
          } else {
            subtitle = detail;
          }
        } else if (state.pid != null) {
          subtitle = 'PID: ${state.pid}';
        }
      case SidecarStatus.starting:
        statusText = '◐ ${l10n.webuiStatusStarting}';
        statusColor = statusBlueText.resolveFrom(context);
      case SidecarStatus.failed:
        statusText = '● ${l10n.webuiStatusFailed}';
        statusColor = statusRedText.resolveFrom(context);
        final reasonText = switch (state.reason) {
          SidecarFailureReason.portOccupied => l10n.webuiFailurePortOccupied,
          SidecarFailureReason.missingBundle => l10n.webuiFailureMissingBundle,
          SidecarFailureReason.healthTimeout => l10n.webuiFailureHealthTimeout,
          SidecarFailureReason.startFailed =>
            state.detail ?? l10n.webuiFailureStartFailed,
          SidecarFailureReason.none => l10n.webuiStatusFailed,
        };
        subtitle = reasonText;
        subtitleColor = statusRedText.resolveFrom(context);
      case SidecarStatus.stopped:
        statusText = '○ ${l10n.webuiStatusStopped}';
        statusColor = statusGreyText.resolveFrom(context);
    }

    return CupertinoListTile(
      key: const ValueKey('settings-webui-status-tile'),
      title: Text(l10n.webuiStatusTitle),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color:
                    subtitleColor ??
                    LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: CupertinoColors.secondaryLabel,
                    ),
                fontSize: 12,
              ),
            )
          : null,
      trailing: Text(
        statusText,
        style: TextStyle(color: statusColor, fontWeight: FontWeight.w500),
      ),
    );
  }
}
