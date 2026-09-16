import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import '../utils/uuid.dart';
import 'json_value.dart';
import 'model_favorite.dart';

// ============================================================================
// 15.1 Chat 流控制 / 后台任务 / 命令
// ============================================================================

/// 开始聊天响应（Swift: ChatStartResponse）。
class ChatStartResponse {
  const ChatStartResponse({this.streamId, this.sessionId, this.error});

  factory ChatStartResponse.fromJson(Map<String, Object?> json) {
    // 兼容 data 包裹与 camelCase 变体
    Map<String, Object?>? dataMap;
    final raw = json['data'];
    if (raw is Map) {
      try {
        dataMap = Map<String, Object?>.from(raw);
      } catch (_) {}
    }
    String? pick(String snake, String camel) =>
        lossyString(json, snake) ??
        (dataMap != null ? lossyString(dataMap, snake) : null) ??
        lossyString(json, camel) ??
        (dataMap != null ? lossyString(dataMap, camel) : null);
    return ChatStartResponse(
      streamId:
          pick('stream_id', 'streamId') ??
          lossyString(json, 'id') ??
          (dataMap != null ? lossyString(dataMap, 'id') : null),
      sessionId: pick('session_id', 'sessionId'),
      error: pick('error', 'message'),
    );
  }

  final String? streamId;
  final String? sessionId;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is ChatStartResponse &&
        other.streamId == streamId &&
        other.sessionId == sessionId &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(streamId, sessionId, error);

  @override
  String toString() => 'ChatStartResponse(streamId: $streamId)';
}

/// 取消聊天响应（Swift: ChatCancelResponse）。
class ChatCancelResponse {
  const ChatCancelResponse({
    this.ok,
    this.cancelled,
    this.streamId,
    this.error,
  });

  factory ChatCancelResponse.fromJson(Map<String, Object?> json) {
    return ChatCancelResponse(
      ok: lossyBool(json, 'ok'),
      cancelled: lossyBool(json, 'cancelled'),
      streamId: lossyString(json, 'stream_id'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final bool? cancelled;
  final String? streamId;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is ChatCancelResponse &&
        other.ok == ok &&
        other.cancelled == cancelled &&
        other.streamId == streamId &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, cancelled, streamId, error);

  @override
  String toString() => 'ChatCancelResponse(ok: $ok)';
}

/// 聊天流状态响应（Swift: ChatStreamStatusResponse）。
class ChatStreamStatusResponse {
  const ChatStreamStatusResponse({
    this.active,
    this.streamId,
    this.replayAvailable,
    this.journal,
  });

  factory ChatStreamStatusResponse.fromJson(Map<String, Object?> json) {
    return ChatStreamStatusResponse(
      active: lossyBool(json, 'active'),
      streamId: lossyString(json, 'stream_id'),
      replayAvailable: lossyBool(json, 'replay_available'),
      journal: optModel(json, 'journal', RunJournalStatus.fromJson),
    );
  }

  final bool? active;
  final String? streamId;
  final bool? replayAvailable;
  final RunJournalStatus? journal;

  @override
  bool operator ==(Object other) {
    return other is ChatStreamStatusResponse &&
        other.active == active &&
        other.streamId == streamId &&
        other.replayAvailable == replayAvailable &&
        other.journal == journal;
  }

  @override
  int get hashCode => Object.hash(active, streamId, replayAvailable, journal);

  @override
  String toString() => 'ChatStreamStatusResponse(active: $active)';
}

/// 运行日志状态（Swift: RunJournalStatus）。
class RunJournalStatus {
  const RunJournalStatus({this.terminal, this.terminalState});

  factory RunJournalStatus.fromJson(Map<String, Object?> json) {
    return RunJournalStatus(
      terminal: lossyBool(json, 'terminal'),
      terminalState: lossyString(json, 'terminal_state'),
    );
  }

  final bool? terminal;
  final String? terminalState;

  @override
  bool operator ==(Object other) {
    return other is RunJournalStatus &&
        other.terminal == terminal &&
        other.terminalState == terminalState;
  }

  @override
  int get hashCode => Object.hash(terminal, terminalState);

  @override
  String toString() => 'RunJournalStatus(terminal: $terminal)';
}

/// 引导聊天响应（Swift: ChatSteerResponse）。
class ChatSteerResponse {
  const ChatSteerResponse({
    this.accepted,
    this.fallback,
    this.streamId,
    this.error,
  });

  factory ChatSteerResponse.fromJson(Map<String, Object?> json) {
    return ChatSteerResponse(
      accepted: lossyBool(json, 'accepted'),
      fallback: lossyString(json, 'fallback'),
      streamId: lossyString(json, 'stream_id'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? accepted;
  final String? fallback;
  final String? streamId;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is ChatSteerResponse &&
        other.accepted == accepted &&
        other.fallback == fallback &&
        other.streamId == streamId &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(accepted, fallback, streamId, error);

  @override
  String toString() => 'ChatSteerResponse(accepted: $accepted)';
}

/// Btw 开始响应（Swift: BtwStartResponse）。
class BtwStartResponse {
  const BtwStartResponse({
    this.streamId,
    this.sessionId,
    this.parentSessionId,
    this.error,
  });

  factory BtwStartResponse.fromJson(Map<String, Object?> json) {
    return BtwStartResponse(
      streamId: lossyString(json, 'stream_id'),
      sessionId: lossyString(json, 'session_id'),
      parentSessionId: lossyString(json, 'parent_session_id'),
      error: lossyString(json, 'error'),
    );
  }

  final String? streamId;
  final String? sessionId;
  final String? parentSessionId;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is BtwStartResponse &&
        other.streamId == streamId &&
        other.sessionId == sessionId &&
        other.parentSessionId == parentSessionId &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(streamId, sessionId, parentSessionId, error);

  @override
  String toString() => 'BtwStartResponse(streamId: $streamId)';
}

/// 后台任务开始响应（Swift: BackgroundStartResponse）。
class BackgroundStartResponse {
  const BackgroundStartResponse({
    this.taskId,
    this.streamId,
    this.sessionId,
    this.error,
  });

  factory BackgroundStartResponse.fromJson(Map<String, Object?> json) {
    return BackgroundStartResponse(
      taskId: lossyString(json, 'task_id'),
      streamId: lossyString(json, 'stream_id'),
      sessionId: lossyString(json, 'session_id'),
      error: lossyString(json, 'error'),
    );
  }

  final String? taskId;
  final String? streamId;
  final String? sessionId;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is BackgroundStartResponse &&
        other.taskId == taskId &&
        other.streamId == streamId &&
        other.sessionId == sessionId &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(taskId, streamId, sessionId, error);

  @override
  String toString() => 'BackgroundStartResponse(taskId: $taskId)';
}

/// 后台任务状态响应（Swift: BackgroundStatusResponse）。
class BackgroundStatusResponse {
  const BackgroundStatusResponse({this.results});

  factory BackgroundStatusResponse.fromJson(Map<String, Object?> json) {
    return BackgroundStatusResponse(
      results: optModelList(json, 'results', BackgroundResult.fromJson),
    );
  }

  final List<BackgroundResult>? results;

  @override
  bool operator ==(Object other) =>
      other is BackgroundStatusResponse && deepEquals(other.results, results);

  @override
  int get hashCode => Object.hashAll([deepHash(results)]);

  @override
  String toString() => 'BackgroundStatusResponse(results: ${results?.length})';
}

/// 后台任务结果（Swift: BackgroundResult）。
class BackgroundResult {
  const BackgroundResult({
    this.taskId,
    this.prompt,
    this.answer,
    this.completedAt,
  });

  factory BackgroundResult.fromJson(Map<String, Object?> json) {
    return BackgroundResult(
      taskId: lossyString(json, 'task_id'),
      prompt: lossyString(json, 'prompt'),
      answer: lossyString(json, 'answer'),
      completedAt: lossyDouble(json, 'completed_at'),
    );
  }

  final String? taskId;
  final String? prompt;
  final String? answer;
  final double? completedAt;

  @override
  bool operator ==(Object other) {
    return other is BackgroundResult &&
        other.taskId == taskId &&
        other.prompt == prompt &&
        other.answer == answer &&
        other.completedAt == completedAt;
  }

  @override
  int get hashCode => Object.hash(taskId, prompt, answer, completedAt);

  @override
  String toString() => 'BackgroundResult(taskId: $taskId)';
}

/// 命令列表响应（Swift: CommandsResponse）。
class CommandsResponse {
  const CommandsResponse({this.commands});

  factory CommandsResponse.fromJson(Map<String, Object?> json) {
    return CommandsResponse(
      commands: optModelList(json, 'commands', AgentCommand.fromJson),
    );
  }

  final List<AgentCommand>? commands;

  @override
  bool operator ==(Object other) =>
      other is CommandsResponse && deepEquals(other.commands, commands);

  @override
  int get hashCode => Object.hashAll([deepHash(commands)]);

  @override
  String toString() => 'CommandsResponse(commands: ${commands?.length})';
}

/// 智能体命令（Swift: AgentCommand）。`id` = name ?? uuid。
class AgentCommand {
  const AgentCommand({
    this.name,
    this.description,
    this.category,
    this.aliases,
    this.argsHint,
    this.subcommands,
    this.cliOnly,
    this.gatewayOnly,
  });

  factory AgentCommand.fromJson(Map<String, Object?> json) {
    return AgentCommand(
      name: lossyString(json, 'name'),
      description: lossyString(json, 'description'),
      category: lossyString(json, 'category'),
      aliases: optStringList(json, 'aliases'),
      argsHint: lossyString(json, 'args_hint'),
      subcommands: optStringList(json, 'subcommands'),
      cliOnly: lossyBool(json, 'cli_only'),
      gatewayOnly: lossyBool(json, 'gateway_only'),
    );
  }

  final String? name;
  final String? description;
  final String? category;
  final List<String>? aliases;
  final String? argsHint;
  final List<String>? subcommands;
  final bool? cliOnly;
  final bool? gatewayOnly;

  String get id => name ?? uuidV4();

  @override
  bool operator ==(Object other) {
    return other is AgentCommand &&
        other.name == name &&
        other.description == description &&
        other.category == category &&
        _listEquals(other.aliases, aliases) &&
        other.argsHint == argsHint &&
        _listEquals(other.subcommands, subcommands) &&
        other.cliOnly == cliOnly &&
        other.gatewayOnly == gatewayOnly;
  }

  @override
  int get hashCode => Object.hash(
    name,
    description,
    category,
    Object.hashAll(aliases ?? const []),
    argsHint,
    Object.hashAll(subcommands ?? const []),
    cliOnly,
    gatewayOnly,
  );

  @override
  String toString() => 'AgentCommand(name: $name)';
}

// ============================================================================
// 15.2 Models / Providers（模型目录）
// ============================================================================

/// 模型列表响应（Swift: ModelsResponse）。
class ModelsResponse {
  const ModelsResponse({
    this.groups,
    this.models,
    this.defaultModel,
    this.activeProvider,
  });

  factory ModelsResponse.fromJson(Map<String, Object?> json) {
    return ModelsResponse(
      groups: optJsonValueList(json, 'groups'),
      models: optJsonValueList(json, 'models'),
      defaultModel: lossyString(json, 'default_model'),
      activeProvider: lossyString(json, 'active_provider'),
    );
  }

  final List<JsonValue>? groups;
  final List<JsonValue>? models;
  final String? defaultModel;
  final String? activeProvider;

  /// 解析后的目录分组（对应 Swift `catalogGroups`）。
  List<ModelCatalogGroup> get catalogGroups => ModelCatalogParser.parseGroups(
    groups ?? const [],
    fallbackProvider: null,
  );

  @override
  bool operator ==(Object other) {
    return other is ModelsResponse &&
        deepEquals(other.groups, groups) &&
        deepEquals(other.models, models) &&
        other.defaultModel == defaultModel &&
        other.activeProvider == activeProvider;
  }

  @override
  int get hashCode => Object.hash(
    deepHash(groups),
    deepHash(models),
    defaultModel,
    activeProvider,
  );

  @override
  String toString() => 'ModelsResponse(defaultModel: $defaultModel)';
}

/// 模型刷新响应（POST /api/models/refresh）。
class ModelsRefreshResponse {
  const ModelsRefreshResponse({this.ok = false, this.provider});

  factory ModelsRefreshResponse.fromJson(Map<String, Object?> json) {
    return ModelsRefreshResponse(
      ok: lossyBool(json, 'ok') ?? false,
      provider: lossyString(json, 'provider'),
    );
  }

  final bool ok;
  final String? provider;

  @override
  bool operator ==(Object other) {
    return other is ModelsRefreshResponse &&
        other.ok == ok &&
        other.provider == provider;
  }

  @override
  int get hashCode => Object.hash(ok, provider);

  @override
  String toString() => 'ModelsRefreshResponse(ok: $ok, provider: $provider)';
}

/// 提供商列表响应（Swift: ProvidersResponse）。
class ProvidersResponse {
  const ProvidersResponse({this.providers, this.activeProvider});

  factory ProvidersResponse.fromJson(Map<String, Object?> json) {
    return ProvidersResponse(
      providers: optModelList(json, 'providers', ProviderSummary.fromJson),
      activeProvider: lossyString(json, 'active_provider'),
    );
  }

  final List<ProviderSummary>? providers;
  final String? activeProvider;

  @override
  bool operator ==(Object other) {
    return other is ProvidersResponse &&
        deepEquals(other.providers, providers) &&
        other.activeProvider == activeProvider;
  }

  @override
  int get hashCode => Object.hash(deepHash(providers), activeProvider);

  @override
  String toString() => 'ProvidersResponse(activeProvider: $activeProvider)';
}

/// 提供商摘要（Swift: ProviderSummary）。
class ProviderSummary {
  const ProviderSummary({
    this.id,
    this.displayName,
    this.hasKey,
    this.configurable,
    this.isSelfHosted,
    this.baseUrl,
    this.isPluginProvider,
    this.isOauth,
    this.isCustom,
    this.keySource,
    this.authError,
    this.models,
    this.modelsTotal,
  });

  factory ProviderSummary.fromJson(Map<String, Object?> json) {
    return ProviderSummary(
      id: lossyString(json, 'id'),
      displayName: lossyString(json, 'display_name'),
      hasKey: lossyBool(json, 'has_key'),
      configurable: lossyBool(json, 'configurable'),
      isSelfHosted: lossyBool(json, 'is_self_hosted'),
      baseUrl: lossyString(json, 'base_url'),
      isPluginProvider: lossyBool(json, 'is_plugin_provider'),
      isOauth: lossyBool(json, 'is_oauth'),
      isCustom: lossyBool(json, 'is_custom'),
      keySource: lossyString(json, 'key_source'),
      authError: lossyString(json, 'auth_error'),
      models: optModelList(json, 'models', ProviderModel.fromJson),
      modelsTotal: lossyInt(json, 'models_total'),
    );
  }

  final String? id;
  final String? displayName;
  final bool? hasKey;
  final bool? configurable;
  final bool? isSelfHosted;
  final String? baseUrl;
  final bool? isPluginProvider;
  final bool? isOauth;
  final bool? isCustom;
  final String? keySource;
  final String? authError;
  final List<ProviderModel>? models;
  final int? modelsTotal;

  @override
  bool operator ==(Object other) {
    return other is ProviderSummary &&
        other.id == id &&
        other.displayName == displayName &&
        other.hasKey == hasKey &&
        other.configurable == configurable &&
        other.isSelfHosted == isSelfHosted &&
        other.baseUrl == baseUrl &&
        other.isPluginProvider == isPluginProvider &&
        other.isOauth == isOauth &&
        other.isCustom == isCustom &&
        other.keySource == keySource &&
        other.authError == authError &&
        deepEquals(other.models, models) &&
        other.modelsTotal == modelsTotal;
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    hasKey,
    configurable,
    isSelfHosted,
    baseUrl,
    isPluginProvider,
    isOauth,
    isCustom,
    keySource,
    authError,
    deepHash(models),
    modelsTotal,
  );

  @override
  String toString() => 'ProviderSummary(id: $id, displayName: $displayName)';
}

/// 提供商模型（Swift: ProviderModel）。**支持裸字符串**：
/// 元素为字符串 → id=label=该字符串。
class ProviderModel {
  const ProviderModel({this.id, this.label});

  factory ProviderModel.fromJson(Object? json) {
    if (json is String) return ProviderModel(id: json, label: json);
    if (json is! Map) return const ProviderModel();
    // 非 String 键的 Map 会让 Map.from 抛 TypeError 直穿本工厂；本类处在容错解析链上
    //（可能被 optModelList 的 catch 兜住，也可能被直接调用），按 lossy 口径降级为空模型。
    final Map<String, Object?> map;
    try {
      map = Map<String, Object?>.from(json);
    } catch (_) {
      return const ProviderModel();
    }
    return ProviderModel(
      id: lossyString(map, 'id'),
      label: lossyString(map, 'label'),
    );
  }

  final String? id;
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is ProviderModel && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'ProviderModel(id: $id, label: $label)';
}

/// 默认模型响应（Swift: DefaultModelResponse）。
class DefaultModelResponse {
  const DefaultModelResponse({this.ok, this.model});

  factory DefaultModelResponse.fromJson(Map<String, Object?> json) {
    return DefaultModelResponse(
      ok: lossyBool(json, 'ok'),
      model: lossyString(json, 'model'),
    );
  }

  final bool? ok;
  final String? model;

  @override
  bool operator ==(Object other) =>
      other is DefaultModelResponse && other.ok == ok && other.model == model;

  @override
  int get hashCode => Object.hash(ok, model);

  @override
  String toString() => 'DefaultModelResponse(ok: $ok, model: $model)';
}

/// 在线模型响应（Swift: ModelsLiveResponse）。
class ModelsLiveResponse {
  const ModelsLiveResponse({this.provider, this.models, this.count});

  factory ModelsLiveResponse.fromJson(Map<String, Object?> json) {
    return ModelsLiveResponse(
      provider: lossyString(json, 'provider'),
      models: optJsonValueList(json, 'models'),
      count: lossyInt(json, 'count'),
    );
  }

  final String? provider;
  final List<JsonValue>? models;
  final int? count;

  /// Provider id 去除首尾空白后归一，空白视为缺失（对齐 Swift `normalizedProvider`）。
  String? get normalizedProvider {
    final trimmed = provider?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// 解析后的在线选项（providerID 用 normalizedProvider，对齐 Swift `liveOptions`）。
  List<ModelCatalogOption> get liveOptions {
    return ModelCatalogParser.parseOptions(
      models ?? const [],
      fallbackProvider: normalizedProvider,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ModelsLiveResponse &&
        other.provider == provider &&
        deepEquals(other.models, models) &&
        other.count == count;
  }

  @override
  int get hashCode => Object.hash(provider, deepHash(models), count);

  @override
  String toString() => 'ModelsLiveResponse(provider: $provider, count: $count)';
}

// ============================================================================
// 15.3 设置 / 更新 / 推理 / 人格 / 档案
// ============================================================================

/// 设置响应（Swift: SettingsResponse）。
class SettingsResponse {
  const SettingsResponse({
    this.botName,
    this.webuiVersion,
    this.agentVersion,
    this.theme,
    this.checkForUpdates,
    this.showCliSessions,
    this.showClaudeCodeSessions,
    this.maxTokens,
    this.maxTokensEffective,
    this.authEnabled,
    this.passwordAuthEnabled,
    this.passkeysEnabled,
    this.passwordlessEnabled,
  });

  factory SettingsResponse.fromJson(Map<String, Object?> json) {
    return SettingsResponse(
      botName: lossyString(json, 'bot_name'),
      webuiVersion: lossyString(json, 'webui_version'),
      agentVersion: lossyString(json, 'agent_version'),
      theme: lossyString(json, 'theme'),
      checkForUpdates: lossyBool(json, 'check_for_updates'),
      showCliSessions: lossyBool(json, 'show_cli_sessions'),
      showClaudeCodeSessions: lossyBool(json, 'show_claude_code_sessions'),
      maxTokens: lossyInt(json, 'max_tokens'),
      maxTokensEffective: lossyInt(json, 'max_tokens_effective'),
      authEnabled: lossyBool(json, 'auth_enabled'),
      passwordAuthEnabled: lossyBool(json, 'password_auth_enabled'),
      passkeysEnabled: lossyBool(json, 'passkeys_enabled'),
      passwordlessEnabled: lossyBool(json, 'passwordless_enabled'),
    );
  }

  final String? botName;
  final String? webuiVersion;
  final String? agentVersion;
  final String? theme;
  final bool? checkForUpdates;
  final bool? showCliSessions;
  final bool? showClaudeCodeSessions;
  final int? maxTokens;
  final int? maxTokensEffective;
  final bool? authEnabled;
  final bool? passwordAuthEnabled;
  final bool? passkeysEnabled;
  final bool? passwordlessEnabled;

  @override
  bool operator ==(Object other) {
    return other is SettingsResponse &&
        other.botName == botName &&
        other.webuiVersion == webuiVersion &&
        other.agentVersion == agentVersion &&
        other.theme == theme &&
        other.checkForUpdates == checkForUpdates &&
        other.showCliSessions == showCliSessions &&
        other.showClaudeCodeSessions == showClaudeCodeSessions &&
        other.maxTokens == maxTokens &&
        other.maxTokensEffective == maxTokensEffective &&
        other.authEnabled == authEnabled &&
        other.passwordAuthEnabled == passwordAuthEnabled &&
        other.passkeysEnabled == passkeysEnabled &&
        other.passwordlessEnabled == passwordlessEnabled;
  }

  @override
  int get hashCode => Object.hash(
    botName,
    webuiVersion,
    agentVersion,
    theme,
    checkForUpdates,
    showCliSessions,
    showClaudeCodeSessions,
    maxTokens,
    maxTokensEffective,
    authEnabled,
    passwordAuthEnabled,
    passkeysEnabled,
    passwordlessEnabled,
  );

  @override
  String toString() => 'SettingsResponse(botName: $botName)';
}

/// 更新检查响应（Swift: UpdatesCheckResponse）。
class UpdatesCheckResponse {
  const UpdatesCheckResponse({
    this.webui,
    this.agent,
    this.checkedAt,
    this.disabled,
  });

  factory UpdatesCheckResponse.fromJson(Map<String, Object?> json) {
    return UpdatesCheckResponse(
      webui: optModel(json, 'webui', UpdateTargetInfo.fromJson),
      agent: optModel(json, 'agent', UpdateTargetInfo.fromJson),
      checkedAt: lossyDouble(json, 'checked_at'),
      disabled: lossyBool(json, 'disabled'),
    );
  }

  final UpdateTargetInfo? webui;
  final UpdateTargetInfo? agent;
  final double? checkedAt;
  final bool? disabled;

  @override
  bool operator ==(Object other) {
    return other is UpdatesCheckResponse &&
        other.webui == webui &&
        other.agent == agent &&
        other.checkedAt == checkedAt &&
        other.disabled == disabled;
  }

  @override
  int get hashCode => Object.hash(webui, agent, checkedAt, disabled);

  @override
  String toString() => 'UpdatesCheckResponse(disabled: $disabled)';
}

/// 更新目标信息（Swift: UpdateTargetInfo）。
class UpdateTargetInfo {
  const UpdateTargetInfo({
    this.name,
    this.behind,
    this.currentSha,
    this.latestSha,
    this.branch,
    this.repoUrl,
    this.compareUrl,
    this.error,
    this.staleCheck,
  });

  factory UpdateTargetInfo.fromJson(Map<String, Object?> json) {
    return UpdateTargetInfo(
      name: lossyString(json, 'name'),
      behind: lossyInt(json, 'behind'),
      currentSha: lossyString(json, 'current_sha'),
      latestSha: lossyString(json, 'latest_sha'),
      branch: lossyString(json, 'branch'),
      repoUrl: lossyString(json, 'repo_url'),
      compareUrl: lossyString(json, 'compare_url'),
      error: lossyString(json, 'error'),
      staleCheck: lossyBool(json, 'stale_check'),
    );
  }

  final String? name;
  final int? behind;
  final String? currentSha;
  final String? latestSha;
  final String? branch;
  final String? repoUrl;
  final String? compareUrl;
  final String? error;
  final bool? staleCheck;

  @override
  bool operator ==(Object other) {
    return other is UpdateTargetInfo &&
        other.name == name &&
        other.behind == behind &&
        other.currentSha == currentSha &&
        other.latestSha == latestSha &&
        other.branch == branch &&
        other.repoUrl == repoUrl &&
        other.compareUrl == compareUrl &&
        other.error == error &&
        other.staleCheck == staleCheck;
  }

  @override
  int get hashCode => Object.hash(
    name,
    behind,
    currentSha,
    latestSha,
    branch,
    repoUrl,
    compareUrl,
    error,
    staleCheck,
  );

  @override
  String toString() => 'UpdateTargetInfo(name: $name, behind: $behind)';
}

/// 更新应用响应（Swift: UpdatesApplyResponse）。
class UpdatesApplyResponse {
  const UpdatesApplyResponse({
    this.ok,
    this.message,
    this.target,
    this.conflict,
    this.diverged,
    this.restartBlocked,
    this.restartScheduled,
    this.stashConflict,
    this.activeStreams,
    this.activeRuns,
  });

  factory UpdatesApplyResponse.fromJson(Map<String, Object?> json) {
    return UpdatesApplyResponse(
      ok: lossyBool(json, 'ok'),
      message: lossyString(json, 'message'),
      target: lossyString(json, 'target'),
      conflict: lossyBool(json, 'conflict'),
      diverged: lossyBool(json, 'diverged'),
      restartBlocked: lossyBool(json, 'restart_blocked'),
      restartScheduled: lossyBool(json, 'restart_scheduled'),
      stashConflict: lossyBool(json, 'stash_conflict'),
      activeStreams: lossyInt(json, 'active_streams'),
      activeRuns: lossyInt(json, 'active_runs'),
    );
  }

  final bool? ok;
  final String? message;
  final String? target;
  final bool? conflict;
  final bool? diverged;
  final bool? restartBlocked;
  final bool? restartScheduled;
  final bool? stashConflict;
  final int? activeStreams;
  final int? activeRuns;

  /// outcome 枚举（applying/restartBlocked/failed：先判 restartBlocked 再 ok）。
  UpdatesApplyOutcome get outcome {
    if (restartBlocked == true) return UpdatesApplyOutcome.restartBlocked;
    return ok == true
        ? UpdatesApplyOutcome.applying
        : UpdatesApplyOutcome.failed;
  }

  @override
  bool operator ==(Object other) {
    return other is UpdatesApplyResponse &&
        other.ok == ok &&
        other.message == message &&
        other.target == target &&
        other.conflict == conflict &&
        other.diverged == diverged &&
        other.restartBlocked == restartBlocked &&
        other.restartScheduled == restartScheduled &&
        other.stashConflict == stashConflict &&
        other.activeStreams == activeStreams &&
        other.activeRuns == activeRuns;
  }

  @override
  int get hashCode => Object.hash(
    ok,
    message,
    target,
    conflict,
    diverged,
    restartBlocked,
    restartScheduled,
    stashConflict,
    activeStreams,
    activeRuns,
  );

  @override
  String toString() => 'UpdatesApplyResponse(ok: $ok)';
}

/// 更新应用结果枚举。
enum UpdatesApplyOutcome { applying, restartBlocked, failed }

/// 推理状态响应（Swift: ReasoningStatusResponse）。
class ReasoningStatusResponse {
  const ReasoningStatusResponse({
    this.ok,
    this.showReasoning,
    this.reasoningEffort,
    this.effort,
    this.supportedEfforts,
    this.supportsReasoningEffort,
    this.error,
  });

  factory ReasoningStatusResponse.fromJson(Map<String, Object?> json) {
    return ReasoningStatusResponse(
      ok: lossyBool(json, 'ok'),
      showReasoning: lossyBool(json, 'show_reasoning'),
      reasoningEffort: lossyString(json, 'reasoning_effort'),
      effort: lossyString(json, 'effort'),
      supportedEfforts: optStringList(json, 'supported_efforts'),
      supportsReasoningEffort: lossyBool(json, 'supports_reasoning_effort'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final bool? showReasoning;
  final String? reasoningEffort;
  final String? effort;
  final List<String>? supportedEfforts;
  final bool? supportsReasoningEffort;
  final String? error;

  /// reasoningEffort ?? effort。
  String? get effectiveEffort => reasoningEffort ?? effort;

  /// trim+lowercase+去重保序。
  List<String> get normalizedSupportedEfforts {
    final result = <String>[];
    final seen = <String>{};
    for (final effort in supportedEfforts ?? const <String>[]) {
      final normalized = effort.trim().toLowerCase();
      if (normalized.isNotEmpty && seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    return other is ReasoningStatusResponse &&
        other.ok == ok &&
        other.showReasoning == showReasoning &&
        other.reasoningEffort == reasoningEffort &&
        other.effort == effort &&
        _listEquals(other.supportedEfforts, supportedEfforts) &&
        other.supportsReasoningEffort == supportsReasoningEffort &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(
    ok,
    showReasoning,
    reasoningEffort,
    effort,
    Object.hashAll(supportedEfforts ?? const []),
    supportsReasoningEffort,
    error,
  );

  @override
  String toString() => 'ReasoningStatusResponse(ok: $ok)';
}

/// 人格列表响应（Swift: PersonalitiesResponse）。
class PersonalitiesResponse {
  const PersonalitiesResponse({this.personalities});

  factory PersonalitiesResponse.fromJson(Map<String, Object?> json) {
    return PersonalitiesResponse(
      personalities: optModelList(
        json,
        'personalities',
        PersonalitySummary.fromJson,
      ),
    );
  }

  final List<PersonalitySummary>? personalities;

  @override
  bool operator ==(Object other) =>
      other is PersonalitiesResponse &&
      deepEquals(other.personalities, personalities);

  @override
  int get hashCode => Object.hashAll([deepHash(personalities)]);

  @override
  String toString() =>
      'PersonalitiesResponse(personalities: ${personalities?.length})';
}

/// 人格摘要（Swift: PersonalitySummary）。`id` = name ?? uuid。
class PersonalitySummary {
  const PersonalitySummary({this.name, this.description});

  factory PersonalitySummary.fromJson(Map<String, Object?> json) {
    return PersonalitySummary(
      name: lossyString(json, 'name'),
      description: lossyString(json, 'description'),
    );
  }

  final String? name;
  final String? description;

  String get id => name ?? uuidV4();

  @override
  bool operator ==(Object other) =>
      other is PersonalitySummary &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(name, description);

  @override
  String toString() => 'PersonalitySummary(name: $name)';
}

/// 人格设置响应（Swift: PersonalitySetResponse）。
class PersonalitySetResponse {
  const PersonalitySetResponse({
    this.ok,
    this.personality,
    this.prompt,
    this.error,
  });

  factory PersonalitySetResponse.fromJson(Map<String, Object?> json) {
    return PersonalitySetResponse(
      ok: lossyBool(json, 'ok'),
      personality: lossyString(json, 'personality'),
      prompt: lossyString(json, 'prompt'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final String? personality;
  final String? prompt;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is PersonalitySetResponse &&
        other.ok == ok &&
        other.personality == personality &&
        other.prompt == prompt &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, personality, prompt, error);

  @override
  String toString() => 'PersonalitySetResponse(ok: $ok)';
}

/// 档案列表响应（Swift: ProfilesResponse）。
class ProfilesResponse {
  const ProfilesResponse({this.profiles, this.active, this.singleProfileMode});

  factory ProfilesResponse.fromJson(Map<String, Object?> json) {
    return ProfilesResponse(
      profiles: optModelList(json, 'profiles', ProfileSummary.fromJson),
      active: lossyString(json, 'active'),
      singleProfileMode: lossyBool(json, 'single_profile_mode'),
    );
  }

  final List<ProfileSummary>? profiles;
  final String? active;
  final bool? singleProfileMode;

  @override
  bool operator ==(Object other) {
    return other is ProfilesResponse &&
        deepEquals(other.profiles, profiles) &&
        other.active == active &&
        other.singleProfileMode == singleProfileMode;
  }

  @override
  int get hashCode =>
      Object.hash(deepHash(profiles), active, singleProfileMode);

  @override
  String toString() => 'ProfilesResponse(active: $active)';
}

/// 档案创建响应（Swift: ProfileCreateResponse）。
class ProfileCreateResponse {
  const ProfileCreateResponse({this.ok, this.profile, this.error});

  factory ProfileCreateResponse.fromJson(Map<String, Object?> json) {
    return ProfileCreateResponse(
      ok: lossyBool(json, 'ok'),
      profile: optModel(json, 'profile', ProfileSummary.fromJson),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final ProfileSummary? profile;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is ProfileCreateResponse &&
        other.ok == ok &&
        other.profile == profile &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, profile, error);

  @override
  String toString() => 'ProfileCreateResponse(ok: $ok)';
}

/// 档案切换响应（Swift: ProfileSwitchResponse）。
class ProfileSwitchResponse {
  const ProfileSwitchResponse({
    this.profiles,
    this.active,
    this.defaultModel,
    this.defaultWorkspace,
    this.error,
  });

  factory ProfileSwitchResponse.fromJson(Map<String, Object?> json) {
    return ProfileSwitchResponse(
      profiles: optModelList(json, 'profiles', ProfileSummary.fromJson),
      active: lossyString(json, 'active'),
      defaultModel: lossyString(json, 'default_model'),
      defaultWorkspace: lossyString(json, 'default_workspace'),
      error: lossyString(json, 'error'),
    );
  }

  final List<ProfileSummary>? profiles;
  final String? active;
  final String? defaultModel;
  final String? defaultWorkspace;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is ProfileSwitchResponse &&
        deepEquals(other.profiles, profiles) &&
        other.active == active &&
        other.defaultModel == defaultModel &&
        other.defaultWorkspace == defaultWorkspace &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(
    deepHash(profiles),
    active,
    defaultModel,
    defaultWorkspace,
    error,
  );

  @override
  String toString() => 'ProfileSwitchResponse(active: $active)';
}

/// 档案摘要（Swift: ProfileSummary）。`id` = name ?? path ?? uuid。
class ProfileSummary {
  const ProfileSummary({
    this.name,
    this.path,
    this.isDefault,
    this.isActive,
    this.gatewayRunning,
    this.model,
    this.provider,
    this.hasEnv,
    this.skillCount,
  });

  factory ProfileSummary.fromJson(Map<String, Object?> json) {
    return ProfileSummary(
      name: lossyString(json, 'name'),
      path: lossyString(json, 'path'),
      isDefault: lossyBool(json, 'is_default'),
      isActive: lossyBool(json, 'is_active'),
      gatewayRunning: lossyBool(json, 'gateway_running'),
      model: lossyString(json, 'model'),
      provider: lossyString(json, 'provider'),
      hasEnv: lossyBool(json, 'has_env'),
      skillCount: lossyInt(json, 'skill_count'),
    );
  }

  final String? name;
  final String? path;
  final bool? isDefault;
  final bool? isActive;
  final bool? gatewayRunning;
  final String? model;
  final String? provider;
  final bool? hasEnv;
  final int? skillCount;

  String get id => name ?? path ?? uuidV4();

  /// 空 → 'Profile'，'default' → 'Default'。
  String get displayName {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'Profile';
    if (trimmed == 'default') return 'Default';
    return trimmed;
  }

  String get normalizedName => name?.trim().toLowerCase() ?? '';

  @override
  bool operator ==(Object other) {
    return other is ProfileSummary &&
        other.name == name &&
        other.path == path &&
        other.isDefault == isDefault &&
        other.isActive == isActive &&
        other.gatewayRunning == gatewayRunning &&
        other.model == model &&
        other.provider == provider &&
        other.hasEnv == hasEnv &&
        other.skillCount == skillCount;
  }

  @override
  int get hashCode => Object.hash(
    name,
    path,
    isDefault,
    isActive,
    gatewayRunning,
    model,
    provider,
    hasEnv,
    skillCount,
  );

  @override
  String toString() => 'ProfileSummary(name: $name)';
}

// ============================================================================
// 15.4 ModelCatalog（纯客户端解析，无独立 JSON）
// ============================================================================

/// 模型目录分组（对应 Swift `ModelCatalogGroup`）。
class ModelCatalogGroup {
  const ModelCatalogGroup({
    required this.id,
    required this.name,
    this.providerID,
    required this.models,
    this.extraModels = const [],
  });

  final String id;
  final String name;
  final String? providerID;
  final List<ModelCatalogOption> models;
  final List<ModelCatalogOption> extraModels;

  @override
  bool operator ==(Object other) {
    return other is ModelCatalogGroup &&
        other.id == id &&
        other.name == name &&
        other.providerID == providerID &&
        deepEquals(other.models, models) &&
        deepEquals(other.extraModels, extraModels);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    providerID,
    deepHash(models),
    deepHash(extraModels),
  );

  @override
  String toString() => 'ModelCatalogGroup(id: $id, name: $name)';
}

/// 模型目录选项（对应 Swift `ModelCatalogOption`）。
class ModelCatalogOption {
  const ModelCatalogOption({
    required this.id,
    required this.displayName,
    this.providerID,
  });

  final String id;
  final String displayName;
  final String? providerID;

  /// favoriteKey = (id, providerID)。
  ModelFavoriteKey get favoriteKey =>
      ModelFavoriteKey(modelID: id, providerID: providerID);

  @override
  bool operator ==(Object other) {
    return other is ModelCatalogOption &&
        other.id == id &&
        other.displayName == displayName &&
        other.providerID == providerID;
  }

  @override
  int get hashCode => Object.hash(id, displayName, providerID);

  @override
  String toString() => 'ModelCatalogOption(id: $id)';
}

/// 模型目录解析器（对应 Swift `ModelCatalogParser`）。
class ModelCatalogParser {
  const ModelCatalogParser._();

  /// 解析 `groups` 数组（对应 Swift `parseGroups`）。
  static List<ModelCatalogGroup> parseGroups(
    List<JsonValue> groups, {
    String? fallbackProvider,
  }) {
    final result = <ModelCatalogGroup>[];
    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      if (group is! JsonObject) continue;

      final providerID =
          _trimmed(group.value['provider_id']?.stringValue) ?? fallbackProvider;
      final rawName = _trimmed(group.value['name']?.stringValue);
      final name = rawName ?? providerID ?? 'Models';

      final models = _parseOptions(
        group.value['models'],
        fallbackProvider: providerID,
      );
      if (models.isEmpty) continue;

      final extraModels = _parseOptions(
        group.value['extra_models'],
        fallbackProvider: providerID,
      );
      result.add(
        ModelCatalogGroup(
          id: providerID ?? '$name-$index',
          name: name,
          providerID: providerID,
          models: models,
          extraModels: extraModels,
        ),
      );
    }
    return result;
  }

  /// 解析单个模型数组（models / extra_models / live models）。
  static List<ModelCatalogOption> parseOptions(
    List<JsonValue> values, {
    String? fallbackProvider,
  }) {
    return _parseOptions(JsonArray(values), fallbackProvider: fallbackProvider);
  }

  static List<ModelCatalogOption> _parseOptions(
    JsonValue? raw, {
    String? fallbackProvider,
  }) {
    if (raw is! JsonArray) return const [];
    final result = <ModelCatalogOption>[];
    final seen = <String>{};
    for (final item in raw.value) {
      if (item is! JsonObject) continue;
      final id = _trimmed(item.value['id']?.stringValue);
      if (id == null) continue;
      final normKey = id
          .toLowerCase()
          .replaceAll(' ', '-')
          .replaceAll('_', '-');
      if (!seen.add(normKey)) continue;
      final displayName =
          _trimmed(item.value['name']?.stringValue) ??
          _trimmed(item.value['label']?.stringValue) ??
          id;
      final providerID =
          _trimmed(item.value['provider_id']?.stringValue) ?? fallbackProvider;
      result.add(
        ModelCatalogOption(
          id: id,
          displayName: displayName,
          providerID: providerID,
        ),
      );
    }
    return result;
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// 将活跃 provider 的 live 列表覆盖到缓存分组（对齐 iOS `mergingLiveModels`）。
///
/// - `live.normalizedProvider` 为空 或 `live.liveOptions` 为空 → 原样返回。
/// - 仅替换匹配 `providerID == normalizedProvider` 的分组的 `models`，保留 `extraModels`。
extension ModelCatalogGroupListExtension on List<ModelCatalogGroup> {
  List<ModelCatalogGroup> mergingLiveModels(ModelsLiveResponse live) {
    final provider = live.normalizedProvider;
    if (provider == null) return this;
    final liveModels = live.liveOptions;
    if (liveModels.isEmpty) return this;
    return map((group) {
      if (group.providerID != provider) return group;
      return ModelCatalogGroup(
        id: group.id,
        name: group.name,
        providerID: group.providerID,
        models: liveModels,
        extraModels: group.extraModels,
      );
    }).toList();
  }
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
