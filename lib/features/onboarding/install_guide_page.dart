import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/install/install_detector.dart';
import '../../core/install/llm_onboarding.dart';
import '../../core/install/powershell_installer.dart';
import '../../core/utils/uuid.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/onboarding_field_style.dart';
import 'widgets/wide_dual_pane.dart';

/// 安装步骤定义。
enum InstallStageKey { prereqs, agent, agentDeps, llmConfig }

/// 步骤执行状态。
enum StageStatus { pending, running, success, failed }

/// 引导页整体运行阶段。
enum GuidePhase { idle, installing, failed, configuringModel, done }

/// Windows 本机一键安装部署引导页。
class InstallGuidePage extends ConsumerStatefulWidget {
  const InstallGuidePage({super.key});

  @override
  ConsumerState<InstallGuidePage> createState() => _InstallGuidePageState();
}

class _InstallGuidePageState extends ConsumerState<InstallGuidePage> {
  GuidePhase _phase = GuidePhase.idle;
  String _failureReason = '';
  InstallStageKey? _failedStage;

  final Map<InstallStageKey, StageStatus> _stageStatuses = {
    for (final k in InstallStageKey.values) k: StageStatus.pending,
  };

  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  bool _showLogs = true;

  // 模型配置表单状态
  LlmProviderOption _selectedProvider =
      LlmProviderOption.builtinProviders.first;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  bool _savingModel = false;
  String? _modelFormError;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _baseUrlController = TextEditingController(
      text: _selectedProvider.defaultBaseUrl,
    );
    _modelController = TextEditingController(
      text: _selectedProvider.defaultModel,
    );
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      _logs.add(line);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _getStageTitle(InstallStageKey stage, AppLocalizations l10n) {
    switch (stage) {
      case InstallStageKey.prereqs:
        return l10n.installGuideStagePrereqs;
      case InstallStageKey.agent:
        return l10n.installGuideStageAgent;
      case InstallStageKey.agentDeps:
        return l10n.installGuideStageDeps;
      case InstallStageKey.llmConfig:
        return l10n.installGuideStageModel;
    }
  }

  String _getStageDescription(InstallStageKey stage, AppLocalizations l10n) {
    switch (stage) {
      case InstallStageKey.prereqs:
        return l10n.installGuideStagePrereqsDesc;
      case InstallStageKey.agent:
        return l10n.installGuideStageAgentDesc;
      case InstallStageKey.agentDeps:
        return l10n.installGuideStageDepsDesc;
      case InstallStageKey.llmConfig:
        return l10n.installGuideStageModelDesc;
    }
  }

  // ---------------------------------------------------------------------------
  // 安装流程调度
  // ---------------------------------------------------------------------------

  Future<void> _startOrResumeInstallation([InstallStageKey? fromStage]) async {
    setState(() {
      _phase = GuidePhase.installing;
      _failureReason = '';
      _failedStage = null;
    });

    final stages = InstallStageKey.values;
    final startIndex = fromStage != null ? stages.indexOf(fromStage) : 0;

    for (var i = startIndex; i < stages.length; i++) {
      final stage = stages[i];
      if (stage == InstallStageKey.llmConfig) {
        // 进入配置模型向导页
        setState(() {
          _phase = GuidePhase.configuringModel;
        });
        return;
      }

      setState(() {
        _stageStatuses[stage] = StageStatus.running;
      });

      final success = await _executeStage(stage);
      if (!success) {
        setState(() {
          _phase = GuidePhase.failed;
          _stageStatuses[stage] = StageStatus.failed;
          _failedStage = stage;
        });
        return;
      }

      setState(() {
        _stageStatuses[stage] = StageStatus.success;
      });
    }

    setState(() {
      _phase = GuidePhase.configuringModel;
    });
  }

  Future<bool> _executeStage(InstallStageKey stage) async {
    final psInstaller = ref.read(powershellInstallerProvider);

    try {
      switch (stage) {
        case InstallStageKey.prereqs:
          _appendLog('===> [1/4] 检查安装环境与下载官方 install.ps1 ...');
          await psInstaller.ensureScriptCached();
          await for (final event in psInstaller.runStage('prereqs')) {
            _handleInstallerEvent(event);
            if (event.type == InstallerEventType.stageFailure) {
              _failureReason = event.reason ?? '环境检查失败';
              return false;
            }
          }
          return true;

        case InstallStageKey.agent:
          _appendLog('===> [2/4] 拉取与安装 Hermes Agent 源码 ...');
          await for (final event in psInstaller.runStage('agent')) {
            _handleInstallerEvent(event);
            if (event.type == InstallerEventType.stageFailure) {
              _failureReason = event.reason ?? '拉取 Agent 失败';
              return false;
            }
          }
          return true;

        case InstallStageKey.agentDeps:
          _appendLog('===> [3/4] 安装 Agent Python 虚拟环境及依赖 ...');
          await for (final event in psInstaller.runStage('deps')) {
            _handleInstallerEvent(event);
            if (event.type == InstallerEventType.stageFailure) {
              _failureReason = event.reason ?? '安装 Agent 依赖失败';
              return false;
            }
          }
          return true;

        case InstallStageKey.llmConfig:
          return true;
      }
    } catch (e) {
      _failureReason = '$e';
      _appendLog('执行步骤异常: $e');
      return false;
    }
  }

  void _handleInstallerEvent(InstallerEvent event) {
    if (event.message != null && event.message!.isNotEmpty) {
      _appendLog('[${event.stage ?? 'info'}] ${event.message}');
    } else if (event.raw.isNotEmpty) {
      _appendLog(event.raw);
    }
  }

  // ---------------------------------------------------------------------------
  // 模型配置与连接保存
  // ---------------------------------------------------------------------------

  Future<void> _submitModelConfigAndComplete({bool skip = false}) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _savingModel = true;
      _modelFormError = null;
    });

    if (!skip && _selectedProvider.requiresApiKey) {
      final key = _apiKeyController.text.trim();
      if (key.isEmpty) {
        setState(() {
          _savingModel = false;
          _modelFormError = l10n.installGuideApiKeyRequired;
        });
        return;
      }
    }

    try {
      if (!skip) {
        final api = ref.read(llmOnboardingApiProvider);
        final config = LlmOnboardingConfig(
          provider: _selectedProvider.id,
          apiKey: _apiKeyController.text.trim(),
          baseUrl: _baseUrlController.text.trim(),
          model: _modelController.text.trim(),
        );
        _appendLog('正在保存大模型配置到 WebUI...');
        await api.saveConfig(
          serverBaseUrl: 'http://127.0.0.1:8787',
          config: config,
        );
        _appendLog('模型配置已保存');
      }

      setState(() {
        _stageStatuses[InstallStageKey.llmConfig] = StageStatus.success;
        _phase = GuidePhase.done;
      });

      // 写入并激活 ServerConnection (http://127.0.0.1:8787)
      const localUrl = 'http://127.0.0.1:8787';
      final connection = ServerConnection(
        id: uuidV4(),
        name: 'Localhost (8787)',
        baseUrl: localUrl,
        username: null,
        password: null,
        customHeaders: const {},
        createdAt: DateTime.now().toUtc(),
      );

      final saved = await ref
          .read(connectionsProvider.notifier)
          .upsert(connection);
      await ref.read(activeConnectionProvider.notifier).setActive(saved.id);

      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingModel = false;
        _modelFormError = '保存配置失败: $e';
      });
      _appendLog('保存配置失败: $e');
    }
  }

  void _showProviderPicker() {
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(
            AppLocalizations.of(ctx).installGuideSelectProvider,
            style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                ? const TextStyle(color: LightSurfaces.textSecondary)
                : null,
          ),
          actions: LlmProviderOption.builtinProviders.map((p) {
            return CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedProvider = p;
                  _baseUrlController.text = p.defaultBaseUrl;
                  _modelController.text = p.defaultModel;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color:
                              CupertinoTheme.brightnessOf(ctx) ==
                                  Brightness.light
                              ? LightSurfaces.menuAction
                              : null,
                        ),
                      ),
                      Text(
                        p.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: LightSurfaces.resolve(
                            context,
                            statusGreyText.resolveFrom(ctx),
                            dark: secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedProvider.id == p.id)
                    Icon(
                      CupertinoIcons.checkmark_alt,
                      color: statusGreenText.resolveFrom(context),
                    ),
                ],
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(ctx).cancel,
              style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                  ? const TextStyle(color: LightSurfaces.menuAction)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isWindows = ref.read(installDetectorProvider).isWindows;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoTheme.brightnessOf(context) == Brightness.light
          ? LightSurfaces.page
          : null,
      navigationBar: CupertinoNavigationBar(
        border: CupertinoTheme.brightnessOf(context) == Brightness.light
            ? const Border(
                bottom: BorderSide(color: LightSurfaces.divider, width: 0.5),
              )
            : const CupertinoNavigationBar().border,
        backgroundColor:
            CupertinoTheme.brightnessOf(context) == Brightness.light
            ? LightSurfaces.page
            : null,
        middle: Text(l10n.installGuideTitle),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => context.go('/onboarding'),
          child: const Icon(CupertinoIcons.back),
        ),
      ),
      child: SafeArea(
        child: isWindows
            ? _buildMainContent(l10n)
            : _buildNonWindowsPlaceholder(l10n),
      ),
    );
  }

  Widget _buildNonWindowsPlaceholder(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              size: 56,
              color: LightSurfaces.resolve(
                context,
                statusOrangeText.resolveFrom(context),
                dark: Color(CupertinoColors.systemYellow.toARGB32()),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.installGuideWindowsOnly,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              color: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? LightSurfaces.userDetail
                  : null,
              onPressed: () => context.go('/onboarding'),
              child: Text(l10n.installGuideBackToConnect),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(AppLocalizations l10n) {
    return WideDualPane(
      wideChild: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          _buildHeader(l10n),
          const SizedBox(height: 16),
          _buildProgressBar(),
          const SizedBox(height: 20),
          if (_phase == GuidePhase.configuringModel)
            _buildModelConfigForm(l10n)
          else
            _buildStageList(l10n),
          if (_phase == GuidePhase.failed) ...[
            const SizedBox(height: 16),
            _buildErrorCard(l10n),
          ],
          const SizedBox(height: 20),
          _buildLogConsole(l10n),
          const SizedBox(height: 20),
          _buildBottomBar(l10n),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildHeader(l10n),
                const SizedBox(height: 16),
                _buildProgressBar(),
                const SizedBox(height: 20),
                if (_phase == GuidePhase.configuringModel)
                  _buildModelConfigForm(l10n)
                else
                  _buildStageList(l10n),
                if (_phase == GuidePhase.failed) ...[
                  const SizedBox(height: 16),
                  _buildErrorCard(l10n),
                ],
                const SizedBox(height: 20),
                _buildLogConsole(l10n),
              ],
            ),
          ),
          _buildBottomBar(l10n),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.installGuideTitle,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.installGuideSubtitle,
          style: TextStyle(
            fontSize: 14,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: secondaryText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final completedCount = _stageStatuses.values
        .where((s) => s == StageStatus.success)
        .length;
    final total = InstallStageKey.values.length;
    final progress = (completedCount / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '进度: $completedCount / $total 步骤',
              style: TextStyle(
                fontSize: 12,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.divider,
              dark: CupertinoColors.systemGrey5,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: statusGreenText.resolveFrom(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStageList(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemGroupedBackground,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < InstallStageKey.values.length; i++) ...[
            if (i > 0)
              Container(
                height: 0.5,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.divider,
                  dark: CupertinoColors.separator,
                ),
              ),
            _buildStageTile(InstallStageKey.values[i], l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildStageTile(InstallStageKey stage, AppLocalizations l10n) {
    final status = _stageStatuses[stage] ?? StageStatus.pending;
    final title = _getStageTitle(stage, l10n);
    final desc = _getStageDescription(stage, l10n);

    Widget trailingIcon;
    switch (status) {
      case StageStatus.pending:
        trailingIcon = Icon(
          CupertinoIcons.circle,
          size: 18,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: CupertinoColors.tertiaryLabel,
          ),
        );
        break;
      case StageStatus.running:
        trailingIcon = const CupertinoActivityIndicator(radius: 8);
        break;
      case StageStatus.success:
        trailingIcon = Icon(
          CupertinoIcons.checkmark_circle_fill,
          size: 18,
          color: statusGreenText.resolveFrom(context),
        );
        break;
      case StageStatus.failed:
        trailingIcon = Icon(
          CupertinoIcons.xmark_circle_fill,
          size: 18,
          color: statusRedText.resolveFrom(context),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          trailingIcon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: status == StageStatus.running
                        ? FontWeight.bold
                        : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintError,
          dark: statusRedText.resolveFrom(context).withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: statusRedText.resolveFrom(context).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.xmark_octagon_fill,
                size: 20,
                color: statusRedText.resolveFrom(context),
              ),
              const SizedBox(width: 8),
              Text(
                '步骤失败: ${_failedStage != null ? _getStageTitle(_failedStage!, l10n) : ""}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: statusRedText.resolveFrom(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _failureReason,
            style: TextStyle(
              fontSize: 13,
              color: statusRedText.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              key: const ValueKey('install-guide-retry-btn'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: statusRedText.resolveFrom(context),
              onPressed: () => _startOrResumeInstallation(_failedStage),
              child: Text(
                l10n.installGuideRetryStage,
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelConfigForm(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemGroupedBackground,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.installGuideStageModel,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.installGuideStageModelDesc,
            style: TextStyle(
              fontSize: 13,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: secondaryText,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.installGuideSelectProvider,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildProviderSelector(),
          const SizedBox(height: 16),
          if (_selectedProvider.requiresApiKey) ...[
            Text(
              l10n.installGuideApiKey,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            CupertinoTextField(
              decoration: OnboardingFieldStyle.decoration(context),
              placeholderStyle: OnboardingFieldStyle.placeholder(context),
              key: const ValueKey('install-guide-apikey-input'),
              controller: _apiKeyController,
              placeholder: _selectedProvider.keyPlaceholder,
              obscureText: true,
              padding: const EdgeInsets.all(10),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            l10n.installGuideBaseUrl,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          CupertinoTextField(
            decoration: OnboardingFieldStyle.decoration(context),
            placeholderStyle: OnboardingFieldStyle.placeholder(context),
            key: const ValueKey('install-guide-baseurl-input'),
            controller: _baseUrlController,
            placeholder: l10n.installGuideBaseUrlHint,
            padding: const EdgeInsets.all(10),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.installGuideModelName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          CupertinoTextField(
            decoration: OnboardingFieldStyle.decoration(context),
            placeholderStyle: OnboardingFieldStyle.placeholder(context),
            key: const ValueKey('install-guide-model-input'),
            controller: _modelController,
            placeholder: l10n.installGuideModelNameHint,
            padding: const EdgeInsets.all(10),
          ),
          if (_modelFormError != null) ...[
            const SizedBox(height: 10),
            Text(
              '❌ $_modelFormError',
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProviderSelector() {
    return GestureDetector(
      key: const ValueKey('install-guide-provider-dropdown'),
      onTap: _showProviderPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.card,
            dark: CupertinoColors.tertiarySystemFill,
          ),
          borderRadius: BorderRadius.circular(8),
          border: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedProvider.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selectedProvider.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_up_chevron_down,
              size: 16,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The terminal remains an inverse surface in both themes. Its grey/green
  // content is readable on the fixed dark background; do not apply light grey.
  Widget _buildLogConsole(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.darkBackgroundGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.chevron_left_slash_chevron_right,
                      size: 14,
                      color: CupertinoColors.systemGrey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.installGuideLogs,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        unawaited(
                          Clipboard.setData(
                            ClipboardData(text: _logs.join('\n')),
                          ),
                        );
                      },
                      child: Text(
                        l10n.installGuideCopyLogs,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              CupertinoTheme.brightnessOf(context) ==
                                  Brightness.light
                              ? CupertinoColors.white
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setState(() => _showLogs = !_showLogs);
                      },
                      child: Text(
                        _showLogs
                            ? l10n.installGuideHideLogs
                            : l10n.installGuideShowLogs,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              CupertinoTheme.brightnessOf(context) ==
                                  Brightness.light
                              ? CupertinoColors.white
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_showLogs)
            Container(
              height: 140,
              padding: const EdgeInsets.all(10),
              color: CupertinoColors.black,
              child: _logs.isEmpty
                  ? const Text(
                      '等待安装启动...',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey,
                        fontFamily: 'monospace',
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, idx) {
                        return Text(
                          _logs[idx],
                          style: const TextStyle(
                            fontSize: 11,
                            color: CupertinoColors.systemGreen,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    if (_phase == GuidePhase.configuringModel) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                color: CupertinoTheme.brightnessOf(context) == Brightness.light
                    ? LightSurfaces.userDetail
                    : null,
                key: const ValueKey('install-guide-save-model-btn'),
                onPressed: _savingModel
                    ? null
                    : () => _submitModelConfigAndComplete(skip: false),
                child: _savingModel
                    ? CupertinoActivityIndicator(
                        color:
                            CupertinoTheme.brightnessOf(context) ==
                                Brightness.light
                            ? LightSurfaces.textSecondary
                            : null,
                      )
                    : Text(l10n.installGuideSaveAndContinue),
              ),
            ),
            const SizedBox(height: 6),
            CupertinoButton(
              key: const ValueKey('install-guide-skip-model-btn'),
              padding: EdgeInsets.zero,
              onPressed: _savingModel
                  ? null
                  : () => _submitModelConfigAndComplete(skip: true),
              child: Text(
                l10n.installGuideSkipModelConfig,
                style: TextStyle(
                  fontSize: 13,
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
      );
    }

    if (_phase == GuidePhase.idle) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoButton.filled(
            color: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? LightSurfaces.userDetail
                : null,
            key: const ValueKey('install-guide-start-btn'),
            onPressed: () => _startOrResumeInstallation(),
            child: Text(l10n.installGuideStartInstall),
          ),
        ),
      );
    }

    if (_phase == GuidePhase.installing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: CupertinoColors.systemGrey4,
            onPressed: null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 8),
                Text(
                  l10n.installGuideInstalling,
                  style: const TextStyle(color: CupertinoColors.black),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_phase == GuidePhase.done) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoButton.filled(
            color: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? LightSurfaces.userDetail
                : null,
            onPressed: () => context.go('/'),
            child: Text(l10n.installGuideEnterChat),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
