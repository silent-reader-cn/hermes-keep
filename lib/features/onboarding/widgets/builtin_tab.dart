import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/connections/server_connection.dart';
import '../../../l10n/app_localizations.dart';
import '../../desktop/desktop_settings.dart';
import '../../settings/settings_surfaces.dart';
import '../../webui_sidecar/webui_sidecar_providers.dart';
import '../onboarding_providers.dart';
import 'onboarding_field_style.dart';

/// 内置服务 Tab（Windows 打包版形态 A 默认选中）。
///
/// 包含：
/// 1. agent 缺失卡（探测 Hermes 引擎是否安装，缺失则插卡引导到安装向导）；
/// 2. 状态胶囊（未启动 / 启动中 / 运行中 host:port / 重启中 / 启动失败）；
/// 3. 大按钮「启动并连接」完整链（start -> 等 running -> 自动 login -> builtin upsert+activate -> 跳转）；
/// 4. 失败态就地红字提示 + 重试按钮；
/// 5. 高级设置折叠（端口 / 监听 IP / 密码脱敏与编辑 / 开机自启开关）。
class BuiltinTab extends ConsumerStatefulWidget {
  const BuiltinTab({super.key});

  @override
  ConsumerState<BuiltinTab> createState() => _BuiltinTabState();
}

class _BuiltinTabState extends ConsumerState<BuiltinTab> {
  bool _isStartingAndConnecting = false;
  String? _errorMessage;

  // 高级设置折叠状态与控制器（默认展开）
  bool _isAdvancedExpanded = true;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _hostFocusNode = FocusNode();
  final FocusNode _portFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _passwordObscured = false;
  String? _hostError;
  String? _portError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final config = ref.read(webuiSidecarConfigProvider);
    _hostController.text = config.host;
    _portController.text = config.port.toString();
    _passwordController.text = config.password;

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
      _submitHost(_hostController.text);
    }
  }

  void _onPortFocusChange() {
    if (!_portFocusNode.hasFocus) {
      _submitPort(_portController.text);
    }
  }

  void _onPasswordFocusChange() {
    if (!_passwordFocusNode.hasFocus) {
      _submitPassword(_passwordController.text);
    }
  }

  Future<void> _recheckAgent() async {
    try {
      await ref.read(agentEnvPresentProvider.notifier).refresh();
    } catch (_) {}
  }

  Future<void> _openInstallGuide() async {
    try {
      await launchUrl(
        Uri.parse(hermesAgentDocsUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  String _mapFailureReason(SidecarState state) {
    final l10n = AppLocalizations.of(context);
    return switch (state.reason) {
      SidecarFailureReason.portOccupied => l10n.webuiFailurePortOccupied,
      SidecarFailureReason.missingBundle => l10n.webuiFailureMissingBundle,
      SidecarFailureReason.healthTimeout => l10n.webuiFailureHealthTimeout,
      SidecarFailureReason.startFailed =>
        state.detail ?? l10n.webuiFailureStartFailed,
      SidecarFailureReason.none => state.detail ?? l10n.webuiStatusFailed,
    };
  }

  Future<void> _waitForRunning(Future<void> startFuture) async {
    final current = ref.read(webuiSidecarControllerProvider);
    if (current.status == SidecarStatus.running) return;
    if (current.status == SidecarStatus.failed) {
      throw StateError(_mapFailureReason(current));
    }

    final completer = Completer<void>();

    unawaited(
      startFuture
          .then((_) {
            final s = ref.read(webuiSidecarControllerProvider);
            if (s.status == SidecarStatus.running) {
              if (!completer.isCompleted) completer.complete();
            } else if (s.status == SidecarStatus.failed) {
              if (!completer.isCompleted) {
                completer.completeError(StateError(_mapFailureReason(s)));
              }
            }
          })
          .catchError((e) {
            if (!completer.isCompleted) completer.completeError(e);
          }),
    );

    final sub = ref.listenManual<SidecarState>(webuiSidecarControllerProvider, (
      prev,
      next,
    ) {
      if (next.status == SidecarStatus.running) {
        if (!completer.isCompleted) completer.complete();
      } else if (next.status == SidecarStatus.failed) {
        if (!completer.isCompleted) {
          completer.completeError(StateError(_mapFailureReason(next)));
        }
      }
    });

    final timer = Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Sidecar start timed out after 30s'),
        );
      }
    });

    try {
      await completer.future;
    } finally {
      timer.cancel();
      sub.close();
    }
  }

  /// 「启动并连接」完整链：
  /// setEnabled(true) -> controller.start() -> 等 running（30s 超时）
  /// -> 自动 login -> builtin upsert + setActive -> context.go('/')
  Future<void> _startAndConnect() async {
    if (_isStartingAndConnecting) return;
    setState(() {
      _isStartingAndConnecting = true;
      _errorMessage = null;
    });

    try {
      // 1. setEnabled(true)
      await ref.read(webuiSidecarConfigProvider.notifier).setEnabled(true);

      // 2. controller.start()
      final startFuture = ref
          .read(webuiSidecarControllerProvider.notifier)
          .start();

      // 等待 running 状态（超时 30s 失败态）
      await _waitForRunning(startFuture);

      // 3. 自动 login
      final config = ref.read(webuiSidecarConfigProvider);
      final effectiveHost = (config.host == '0.0.0.0' || config.host.isEmpty)
          ? '127.0.0.1'
          : config.host;
      final baseUrl = 'http://$effectiveHost:${config.port}';
      final password = config.password;

      final factory = ref.read(onboardingApiFactoryProvider);
      final client = factory(baseUrl, const []);
      await client.login(password);

      // 4. ServerConnection.builtinId upsert & activate
      final connection = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Hermes',
        baseUrl: baseUrl,
        username: null,
        password: password.isEmpty ? null : password,
        customHeaders: const {},
        createdAt: DateTime.now().toUtc(),
        kind: ConnectionKind.builtin,
        enabled: true,
      );

      await ref
          .read(connectionsProvider.notifier)
          .upsertBuiltinAndActivate(connection);

      // 5. 跳转会话列表
      if (mounted) {
        context.go('/');
      }
    } on TimeoutException {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _errorMessage = l10n.webuiFailureHealthTimeout;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _errorMessage = l10n.loginFailedWithMessage(e.message);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStartingAndConnecting = false;
        });
      }
    }
  }

  Future<void> _enterSessionList() async {
    await ref
        .read(activeConnectionProvider.notifier)
        .setActive(ServerConnection.builtinId);
    if (mounted) {
      context.go('/');
    }
  }

  void _submitHost(String text) {
    final trimmed = text.trim();
    final addr = InternetAddress.tryParse(trimmed);
    if (addr == null || addr.type != InternetAddressType.IPv4) {
      setState(
        () => _hostError = AppLocalizations.of(context).webuiInvalidHost,
      );
      return;
    }
    setState(() => _hostError = null);
    final current = ref.read(webuiSidecarConfigProvider).host;
    if (trimmed != current) {
      unawaited(ref.read(webuiSidecarConfigProvider.notifier).setHost(trimmed));
    }
  }

  void _submitPort(String text) {
    final trimmed = text.trim();
    final port = int.tryParse(trimmed);
    if (port == null || port < 1 || port > 65535) {
      setState(
        () => _portError = AppLocalizations.of(context).webuiInvalidPort,
      );
      return;
    }
    setState(() => _portError = null);
    final current = ref.read(webuiSidecarConfigProvider).port;
    if (port != current) {
      unawaited(ref.read(webuiSidecarConfigProvider.notifier).setPort(port));
    }
  }

  void _submitPassword(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(
        () => _passwordError = AppLocalizations.of(context).webuiPasswordEmpty,
      );
      return;
    }
    setState(() {
      _passwordError = null;
    });
    final current = ref.read(webuiSidecarConfigProvider).password;
    if (trimmed != current) {
      unawaited(
        ref.read(webuiSidecarConfigProvider.notifier).setPassword(trimmed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sidecarConfig = ref.watch(webuiSidecarConfigProvider);
    final sidecarState = ref.watch(webuiSidecarControllerProvider);
    final activeConn = ref.watch(activeConnectionProvider);

    // 联动配置变化更新输入框内容（未聚焦时）
    ref.listen<SidecarConfig>(webuiSidecarConfigProvider, (prev, next) {
      if (!_hostFocusNode.hasFocus && _hostController.text != next.host) {
        _hostController.text = next.host;
      }
      if (!_portFocusNode.hasFocus &&
          _portController.text != next.port.toString()) {
        _portController.text = next.port.toString();
      }
      if (!_passwordFocusNode.hasFocus &&
          _passwordController.text != next.password) {
        _passwordController.text = next.password;
      }
    });

    final isBuiltinActiveAndRunning =
        activeConn != null &&
        activeConn.id == ServerConnection.builtinId &&
        activeConn.kind == ConnectionKind.builtin &&
        sidecarState.status == SidecarStatus.running;

    final isAgentInstalled = ref.watch(agentEnvPresentProvider).value ?? false;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        if (!isAgentInstalled) ...[
          _buildMissingAgentCard(l10n),
          const SizedBox(height: 12),
        ],
        Text(
          l10n.onboardingBuiltinTitle,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.onboardingBuiltinSubtitle,
          style: TextStyle(
            fontSize: 14,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [_buildStatusCapsule(l10n, sidecarState, sidecarConfig)]),
        if (sidecarState.status == SidecarStatus.failed ||
            _errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildErrorSection(l10n, sidecarState, isAgentInstalled),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: _buildActionButton(
            l10n,
            sidecarState,
            isBuiltinActiveAndRunning,
            isAgentInstalled,
          ),
        ),
        const SizedBox(height: 20),
        _buildAdvancedDisclosure(context, l10n),
      ],
    );
  }

  /// 顶部 agent 缺失卡
  Widget _buildMissingAgentCard(AppLocalizations l10n) {
    return Container(
      key: const ValueKey('onboarding-missing-agent-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintWarning,
          dark: CupertinoColors.systemOrange
              .resolveFrom(context)
              .withValues(alpha: 0.12),
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.systemOrange
                .resolveFrom(context)
                .withValues(alpha: 0.35),
          ),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: statusOrangeText.resolveFrom(context),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.agentGateNotDetectedTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: statusOrangeText.resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.agentGateNotDetectedDesc,
            style: TextStyle(
              fontSize: 13,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  key: const ValueKey('onboarding-install-agent-btn'),
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  color: LightSurfaces.resolve(
                    context,
                    statusOrangeText.resolveFrom(context),
                    dark: CupertinoColors.activeOrange,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () => unawaited(_openInstallGuide()),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l10n.agentGateViewInstallGuide,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoButton(
                  key: const ValueKey('onboarding-recheck-agent-btn'),
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.pressed,
                    dark: CupertinoColors.systemGrey5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () => unawaited(_recheckAgent()),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l10n.agentGateRecheckDone,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 状态胶囊
  Widget _buildStatusCapsule(
    AppLocalizations l10n,
    SidecarState sidecarState,
    SidecarConfig config,
  ) {
    final isRestarting =
        sidecarState.detail != null &&
        sidecarState.detail!.toLowerCase().contains('restarting');

    final String text;
    final Color textColor;
    final Color bgColor;

    if (isRestarting) {
      text = '◐ ${l10n.onboardingRestarting}';
      textColor = statusOrangeText.resolveFrom(context);
      bgColor = LightSurfaces.resolve(
        context,
        LightSurfaces.tintWarning,
        dark: CupertinoColors.systemOrange
            .resolveFrom(context)
            .withValues(alpha: 0.12),
      );
    } else {
      switch (sidecarState.status) {
        case SidecarStatus.running:
          final effectiveHost =
              (config.host == '0.0.0.0' || config.host.isEmpty)
              ? '127.0.0.1'
              : config.host;
          text =
              '● ${l10n.onboardingBuiltinRunning} $effectiveHost:${config.port}';
          textColor = statusGreenText.resolveFrom(context);
          bgColor = LightSurfaces.resolve(
            context,
            LightSurfaces.tintGreen,
            dark: CupertinoColors.systemGreen
                .resolveFrom(context)
                .withValues(alpha: 0.12),
          );
        case SidecarStatus.starting:
          text = '◐ ${l10n.onboardingStarting}';
          textColor = statusBlueText.resolveFrom(context);
          bgColor = LightSurfaces.resolve(
            context,
            LightSurfaces.selection,
            dark: CupertinoColors.systemBlue
                .resolveFrom(context)
                .withValues(alpha: 0.12),
          );
        case SidecarStatus.failed:
          text = '● ${l10n.webuiStatusFailed}';
          textColor = statusRedText.resolveFrom(context);
          bgColor = LightSurfaces.resolve(
            context,
            LightSurfaces.tintError,
            dark: CupertinoColors.systemRed
                .resolveFrom(context)
                .withValues(alpha: 0.12),
          );
        case SidecarStatus.stopped:
          text = '○ ${l10n.onboardingBuiltinNotStarted}';
          textColor = statusGreyText.resolveFrom(context);
          bgColor = LightSurfaces.resolve(
            context,
            LightSurfaces.page,
            dark: CupertinoColors.systemGrey
                .resolveFrom(context)
                .withValues(alpha: 0.12),
          );
      }
    }

    return Container(
      key: const ValueKey('onboarding-builtin-status-capsule'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: textColor.withValues(alpha: 0.3),
          ),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  /// 失败态就地红字 + 重试
  Widget _buildErrorSection(
    AppLocalizations l10n,
    SidecarState sidecarState,
    bool isAgentInstalled,
  ) {
    final failureMsg = _errorMessage ?? _mapFailureReason(sidecarState);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintError,
          dark: statusRedText.resolveFrom(context).withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: statusRedText.resolveFrom(context).withValues(alpha: 0.25),
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '❌ $failureMsg',
              key: const ValueKey('onboarding-builtin-error-text'),
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          CupertinoButton(
            key: const ValueKey('onboarding-builtin-retry-btn'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 28),
            onPressed: (_isStartingAndConnecting || !isAgentInstalled)
                ? null
                : () => unawaited(_startAndConnect()),
            child: Text(
              l10n.onboardingRetry,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: statusBlueText.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 操作大按钮
  Widget _buildActionButton(
    AppLocalizations l10n,
    SidecarState sidecarState,
    bool isBuiltinActiveAndRunning,
    bool isAgentInstalled,
  ) {
    if (isBuiltinActiveAndRunning) {
      return CupertinoButton.filled(
        color: CupertinoTheme.brightnessOf(context) == Brightness.light
            ? LightSurfaces.userDetail
            : null,
        key: const ValueKey('onboarding-builtin-action-btn'),
        onPressed: () => unawaited(_enterSessionList()),
        child: Text(l10n.onboardingEnterSessionList),
      );
    }

    final isBusy =
        _isStartingAndConnecting ||
        sidecarState.status == SidecarStatus.starting;

    final String buttonText;
    if (sidecarState.status == SidecarStatus.failed) {
      buttonText = l10n.onboardingRetry;
    } else {
      buttonText = l10n.onboardingStartAndConnect;
    }

    final canPress = !isBusy && isAgentInstalled;

    return CupertinoButton.filled(
      color: CupertinoTheme.brightnessOf(context) == Brightness.light
          ? LightSurfaces.userDetail
          : null,
      key: const ValueKey('onboarding-builtin-action-btn'),
      onPressed: canPress ? () => unawaited(_startAndConnect()) : null,
      child: isBusy
          ? CupertinoActivityIndicator(
              color: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? LightSurfaces.textSecondary
                  : null,
            )
          : Text(buttonText),
    );
  }

  /// 高级设置折叠
  Widget _buildAdvancedDisclosure(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: const ValueKey('onboarding-advanced-disclosure'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _isAdvancedExpanded = !_isAdvancedExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  l10n.onboardingAdvancedSettings,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: secondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _isAdvancedExpanded
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_right,
                  size: 14,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isAdvancedExpanded) _buildAdvancedSettingsContent(context, l10n),
      ],
    );
  }

  Widget _buildAdvancedSettingsContent(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final desktopSettings = ref.watch(desktopSettingsProvider);
    final sidecarConfig = ref.watch(webuiSidecarConfigProvider);

    return CupertinoListSection.insetGrouped(
      decoration: CupertinoTheme.brightnessOf(context) == Brightness.light
          ? BoxDecoration(
              color: LightSurfaces.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
            )
          : null,
      separatorColor: LightSurfaces.resolve(
        context,
        LightSurfaces.divider,
        dark: CupertinoColors.separator,
      ),
      margin: const EdgeInsets.only(top: 8),
      dividerMargin: 0,
      additionalDividerMargin: 0,
      children: [
        // 端口（输入框走 trailing 固定宽度贴右缘，与 IP/密码行对齐，对齐 settings 页同款）
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
            constraints: const BoxConstraints(maxWidth: 180),
            child: CupertinoTextField(
              decoration: OnboardingFieldStyle.decoration(context),
              placeholderStyle: OnboardingFieldStyle.placeholder(context),
              key: const ValueKey('onboarding-sidecar-port-input'),
              controller: _portController,
              focusNode: _portFocusNode,
              textAlign: TextAlign.end,
              keyboardType: TextInputType.number,
              placeholder: SidecarConfig.defaultPort.toString(),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              onChanged: (val) {
                final p = int.tryParse(val.trim());
                if (p != null && p >= 1 && p <= 65535) {
                  setState(() => _portError = null);
                  if (p != ref.read(webuiSidecarConfigProvider).port) {
                    unawaited(
                      ref.read(webuiSidecarConfigProvider.notifier).setPort(p),
                    );
                  }
                }
              },
              onSubmitted: _submitPort,
            ),
          ),
        ),

        // 监听 IP（输入框走 trailing 固定宽度贴右缘）
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
            constraints: const BoxConstraints(maxWidth: 180),
            child: CupertinoTextField(
              decoration: OnboardingFieldStyle.decoration(context),
              placeholderStyle: OnboardingFieldStyle.placeholder(context),
              key: const ValueKey('onboarding-sidecar-host-input'),
              controller: _hostController,
              focusNode: _hostFocusNode,
              textAlign: TextAlign.end,
              placeholder: SidecarConfig.defaultHost,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              onChanged: (val) {
                final trimmed = val.trim();
                final addr = InternetAddress.tryParse(trimmed);
                if (addr != null && addr.type == InternetAddressType.IPv4) {
                  setState(() => _hostError = null);
                  if (trimmed != ref.read(webuiSidecarConfigProvider).host) {
                    unawaited(
                      ref
                          .read(webuiSidecarConfigProvider.notifier)
                          .setHost(trimmed),
                    );
                  }
                }
              },
              onSubmitted: _submitHost,
            ),
          ),
        ),

        // 密码（脱敏 + 复制 + 编辑）
        _buildPasswordTile(context, l10n, sidecarConfig),

        // 开机自启开关
        CupertinoListTile(
          title: Text(l10n.onboardingStartOnLoginTitle),
          subtitle: Text(
            l10n.onboardingStartOnLoginSubtitle,
            style: TextStyle(
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
              fontSize: 12,
            ),
          ),
          trailing: SettingsSurfaces.toggle(
            context,
            CupertinoSwitch(
              key: const ValueKey('onboarding-sidecar-start-on-login-switch'),
              value: desktopSettings.startOnLogin,
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
      ],
    );
  }

  /// 密码行：与端口/IP 统一的自适应内联密码框。
  /// 眼睛按钮嵌在输入框内部右侧；默认明文方便复制，失焦/回车即写回。
  Widget _buildPasswordTile(
    BuildContext context,
    AppLocalizations l10n,
    SidecarConfig config,
  ) {
    return CupertinoListTile(
      key: const ValueKey('onboarding-sidecar-password-tile'),
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
        constraints: const BoxConstraints(maxWidth: 180),
        child: CupertinoTextField(
          decoration: OnboardingFieldStyle.decoration(context),
          placeholderStyle: OnboardingFieldStyle.placeholder(context),
          key: const ValueKey('onboarding-sidecar-password-input'),
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          textAlign: TextAlign.end,
          obscureText: _passwordObscured,
          placeholder: l10n.webuiPasswordPlaceholder,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          suffix: CupertinoButton(
            key: const ValueKey('onboarding-sidecar-password-visibility-btn'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: const Size(0, 28),
            onPressed: () {
              setState(() => _passwordObscured = !_passwordObscured);
            },
            child: Icon(
              _passwordObscured ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              size: 18,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.secondaryLabel,
              ),
            ),
          ),
          onChanged: (_) {
            if (_passwordError != null) {
              setState(() => _passwordError = null);
            }
          },
          onSubmitted: _submitPassword,
        ),
      ),
    );
  }
}
