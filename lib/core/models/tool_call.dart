import 'dart:convert';

import '../../l10n/app_localizations.dart';
import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import '../utils/uuid.dart';
import 'chat_message.dart';
import 'json_value.dart';

/// 实时工具调用（Swift: ToolCall.swift）。**非 JSON 模型**（纯客户端/流式状态），
/// 无 fromJson；提供命名构造。
class ToolCall {
  ToolCall({
    String? id,
    this.name,
    this.preview,
    this.args,
    this.duration,
    this.isError,
    this.isCompleted = false,
    this.thinking,
    double? startedAt,
  }) : id = id ?? 'live-tool-${uuidV4()}',
       startedAt = startedAt ?? DateTime.now().millisecondsSinceEpoch / 1000;

  final String id;
  String? name;
  String? preview;
  Map<String, JsonValue>? args;
  double? duration;
  bool? isError;
  bool isCompleted;

  /// 思考子卡内容（非空 = 本条是「思考」伪工具行，非真实工具调用）。
  ///
  /// 思考降级为工具卡的子卡：think/tool 穿插的调用序列合并进同一张
  /// 工具卡，行序即事件时间线；[isThinking] 行在展开区以思考样式渲染。
  String? thinking;
  final double startedAt;

  /// 是否为思考子卡行（非真实工具调用）。
  bool get isThinking => thinking != null && thinking!.trim().isNotEmpty;

  /// 构建思考子卡行（时间线与工具行混排，name 固定为思考语义）。
  factory ToolCall.thinking(String text) {
    return ToolCall(name: 'thinking', thinking: text, isCompleted: true);
  }

  /// trim 后非空 name 否则 'Tool'。
  String get displayName {
    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) return 'Tool';
    return trimmedName;
  }

  /// 第三方 MCP 工具（命名约定 `mcp__<server>__<action>`）。
  /// 聚合标题统一显示「外部工具」，单卡详情保留原名。
  bool get isExternalMcp =>
      displayName.trim().toLowerCase().startsWith('mcp__');

  /// 提取关键参数摘要文本（纯文本，若无有效摘要返回 null）。
  String? get summary => toolCallSummary(this);

  @override
  bool operator ==(Object other) {
    return other is ToolCall &&
        other.id == id &&
        other.name == name &&
        other.preview == preview &&
        deepEquals(other.args, args) &&
        other.duration == duration &&
        other.isError == isError &&
        other.isCompleted == isCompleted &&
        other.thinking == thinking &&
        other.startedAt == startedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      preview,
      deepHash(args),
      duration,
      isError,
      isCompleted,
      thinking,
      startedAt,
    );
  }

  @override
  String toString() {
    return 'ToolCall(id: $id, name: $name, preview: $preview, '
        'isCompleted: $isCompleted, isError: $isError)';
  }
}

/// 服务端存档工具调用（Swift: ToolCall.swift `PersistedToolCall`）。有 fromJson。
class PersistedToolCall {
  const PersistedToolCall({
    this.name,
    this.snippet,
    this.tid,
    this.assistantMsgIdx,
    this.args,
    this.isError,
  });

  factory PersistedToolCall.fromJson(Map<String, Object?> json) {
    final argsValue = optModel<JsonValue>(
      json,
      'args',
      (m) => JsonValue.fromJson(m),
    );
    return PersistedToolCall(
      name: lossyString(json, 'name'),
      snippet: lossyString(json, 'snippet'),
      tid: lossyString(json, 'tid'),
      assistantMsgIdx: firstKey(json, [
        'assistant_msg_idx',
        'assistantMsgIdx',
      ], lossyInt),
      args: argsValue is JsonObject ? argsValue.value : null,
      isError: firstKey(json, ['is_error', 'isError'], lossyBool),
    );
  }

  final String? name;
  final String? snippet;
  final String? tid;
  final int? assistantMsgIdx;
  final Map<String, JsonValue>? args;
  final bool? isError;

  Map<String, Object?> toJson() {
    return {
      if (name != null) 'name': name,
      if (snippet != null) 'snippet': snippet,
      if (tid != null) 'tid': tid,
      if (assistantMsgIdx != null) 'assistant_msg_idx': assistantMsgIdx,
      if (args != null) 'args': JsonObject(args!).toJson(),
      if (isError != null) 'is_error': isError,
    };
  }

  /// → ToolCall(id: tid 非空 ? tid : `persisted-tool-$fallbackIndex`, …)。
  ToolCall toolCall(int fallbackIndex) {
    final trimmedID = tid?.trim();
    final id = (trimmedID != null && trimmedID.isNotEmpty)
        ? trimmedID
        : 'persisted-tool-$fallbackIndex';
    return ToolCall(
      id: id,
      name: name,
      preview: snippet,
      args: args,
      isError: isError,
      isCompleted: true,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PersistedToolCall &&
        other.name == name &&
        other.snippet == snippet &&
        other.tid == tid &&
        other.assistantMsgIdx == assistantMsgIdx &&
        other.isError == isError &&
        deepEquals(other.args, args);
  }

  @override
  int get hashCode =>
      Object.hash(name, snippet, tid, assistantMsgIdx, isError, deepHash(args));

  @override
  String toString() {
    return 'PersistedToolCall(name: $name, snippet: $snippet, '
        'tid: $tid, assistantMsgIdx: $assistantMsgIdx)';
  }
}

/// 工具调用组（Swift: ToolCall.swift `ToolCallGroup`）。纯客户端模型，无 JSON。
class ToolCallGroup {
  ToolCallGroup({
    String? id,
    this.anchorMessageID,
    this.precedingMessageID,
    this.isAboveContent = false,
    required this.toolCalls,
  }) : id = id ?? uuidV4();

  final String id;
  final String? anchorMessageID;

  /// 前驱正文消息 ID（若本组位于首段正文之前，为 null；若位于某正文之后，为该正文消息 ID）。
  final String? precedingMessageID;

  /// 是否渲染在该消息正文「上方」（首段文本之前的思考/工具组，或聚合开关开启时的整回合大卡）。
  final bool isAboveContent;

  final List<ToolCall> toolCalls;

  ToolCallGroup copyWith({
    String? id,
    String? anchorMessageID,
    String? precedingMessageID,
    bool? isAboveContent,
    List<ToolCall>? toolCalls,
  }) {
    return ToolCallGroup(
      id: id ?? this.id,
      anchorMessageID: anchorMessageID ?? this.anchorMessageID,
      precedingMessageID: precedingMessageID ?? this.precedingMessageID,
      isAboveContent: isAboveContent ?? this.isAboveContent,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }

  /// Hermex 风格的活动摘要：显示少量工具名，其余折叠为 +N。
  String get activityTitle {
    if (toolCalls.isEmpty) return 'No tools';
    final uniqueNames = <String>[];
    for (final call in toolCalls) {
      final name = call.displayName;
      if (!uniqueNames.contains(name)) uniqueNames.add(name);
    }
    if (uniqueNames.length == 1) return 'Activity: 1 tool';
    final visible = uniqueNames.take(3).join(', ');
    final remaining = uniqueNames.length - uniqueNames.length.clamp(0, 3);
    if (remaining > 0) return '$visible, +$remaining';
    return visible;
  }

  /// 本地化的活动摘要：显示频次前 3 的工具及调用次数（如 `读取文件 ×3, 终端 ×1`），剩余种类用 `+N` 兜底。
  String localizedActivityTitle(AppLocalizations l10n) {
    if (toolCalls.isEmpty) return l10n.noTools;
    final counts = <String, int>{};
    final initialIndex = <String, int>{};
    for (var i = 0; i < toolCalls.length; i++) {
      // 思考子卡行也计入标题统计（「思考 ×N, 终端 ×M」）；纯思考卡标题即「思考 ×N」。
      // 第三方 MCP 工具（mcp__*）聚合层统一归为「外部工具 ×N」。
      final call = toolCalls[i];
      final name = call.isThinking
          ? l10n.thinkingLabel
          : call.isExternalMcp
              ? l10n.externalToolsLabel
              : l10n.localizeToolName(call.displayName);
      initialIndex.putIfAbsent(name, () => initialIndex.length);
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        if (cmp != 0) return cmp;
        return (initialIndex[a.key] ?? 0).compareTo(initialIndex[b.key] ?? 0);
      });
    final visible = entries
        .take(3)
        .map((e) => '${e.key} \u00D7${e.value}')
        .join(', ');
    final remaining = entries.length - 3;
    if (remaining > 0) return '$visible, +$remaining';
    return visible;
  }

  /// 全部工具已完成.
  bool get isComplete => toolCalls.every((t) => t.isCompleted);

  /// 任一工具报错。
    bool get hasFailedTool => toolCalls.any((t) => t.isError == true);

    /// 合并另一组为一张卡：保留本组的 id / 卡位方向，工具行以本组在前、
    /// [other] 按 stable id / 指纹去重并入（规则同内部相邻聚合，避免双显）。
    ///
    /// 供渲染层做**跨源相邻合并**：live 期间最后一张归档卡（挂 transcript 行）
    /// 与 live 时间线首卡（独立条目）之间没有可见正文分隔时，应呈现为一张卡
    /// （「正文是唯一分隔符」语义在跨渲染源时同样成立）。
    ToolCallGroup mergedWith(ToolCallGroup other) =>
        _mergingToolCallGroup(this, other);

    /// 本组是否被 [others] 完全覆盖（每个非思考调用都能在 others 里配到同一调用）。
    ///
    /// 供「服务端已有真身时丢弃 live 派生归档组」判定（#147 家族）：live 堆是
    /// 「一整轮工具挤进一个 `live-tools-*` 组」的产物，服务端分组已覆盖它时再留作
    /// fallback，会把别段工具搬进同一张卡、并把卡位从「首条正文之上」降级到正文
    /// 之下（主人现象：回合末尾一张位置错误、tools 超多的大卡）。
    bool isCoveredByOthers(List<ToolCallGroup> others) {
      final own = [
        for (final call in toolCalls)
          if (!call.isThinking) call,
      ];
      if (own.isEmpty) return true;
      final pool = [
        for (final group in others)
          for (final call in group.toolCalls)
            if (!call.isThinking) call,
      ];
      if (pool.isEmpty) return false;
      final used = <int>{};
      for (final call in own) {
        var matched = false;
        for (var i = 0; i < pool.length; i++) {
          if (used.contains(i)) continue;
          if (_toolCallsMatch(call, pool[i])) {
            used.add(i);
            matched = true;
            break;
          }
        }
        if (!matched) return false;
      }
      return true;
    }

  /// 实时组：id = `live-tools-<anchor ?? unanchored>`。
  static ToolCallGroup live({
    String? anchorMessageID,
    String? precedingMessageID,
    bool isAboveContent = false,
    required List<ToolCall> toolCalls,
  }) {
    return ToolCallGroup(
      id: 'live-tools-${anchorMessageID ?? 'unanchored'}',
      anchorMessageID: anchorMessageID,
      precedingMessageID: precedingMessageID,
      isAboveContent: isAboveContent,
      toolCalls: toolCalls,
    );
  }

  /// 聚合入口：优先持久化工具调用，缺失时用消息元数据兜底，再按聚合策略合并。
  ///
  /// [coalesce]=true 按 assistant 回合整轮合并（同用户回合内全部工具一张卡）；
  /// [coalesce]=false 仅相邻合并（同回合内无 text/think 打断的连续组合并，
  /// 中间出现可见文本或推理则分离，呈现 text/think/tools 穿插）。
  static List<ToolCallGroup> groups({
    required List<PersistedToolCall> persistedToolCalls,
    required List<ChatMessage> messages,
    int? messageOffset,
    bool coalesce = true,
    bool hideThinking = false,
  }) {
    final derivedGroups = _groupsFromMessageMetadata(messages, messageOffset);
    final rawGroups = persistedToolCalls.isEmpty
        ? derivedGroups
        : merging(
            primaryGroups: _groupsFromPersistedToolCalls(
              persistedToolCalls,
              messages,
              messageOffset,
            ),
            fallbackGroups: derivedGroups,
          );
    // 思考融合（合并前）：reasoning 转 think 行插组首；纯思考消息补组。
    final withThinking = withThinkingRows(
      groups: rawGroups,
      messages: messages,
      messageOffset: messageOffset,
      hideThinking: hideThinking,
    );
    if (!coalesce) {
      return coalescingAdjacent(
        withThinking,
        messages: messages,
        messageOffset: messageOffset,
      );
    }
    return coalescingByAssistantTurn(
      withThinking,
      messages: messages,
      messageOffset: messageOffset,
    );
  }

  /// 思考融合：把消息里的 reasoning 与工具调用按事件时间线区间归入工具组。
  ///
  /// 时间线模型（真实事件序）：
  /// think(m1) → text(m1) → tools(m1) → think(m2) → text(m2) → tools(m2) → …
  /// text 是唯一分隔符：
  /// - 首段 text 之前的 think(m1) → 独立组，isAboveContent = true，挂首条正文上方；
  /// - text(m1) 与 text(m2) 之间的 tools(m1) + think(m2) → 合并一张卡，isAboveContent = false，
  ///   锚到 m1 下方，组内行序为 tools(m1) 在前、think(m2) 在后；
  /// - 末段 text 之后的 tools(mN) → 独立组，isAboveContent = false，挂末条正文下方。
  ///
  /// **入参契约：`groups` 必须是未经本方法处理过的 raw 分组。**
  /// 本方法**不幂等**——它按 `anchorMessageID` 把入参索引回 assistant 消息，而输出组的
  /// 锚是随卡位重算的；把输出回灌会因锚漂移而重复织入，产生重复思考行与幽灵卡
  ///（#112 家族现象）。生产链路每次从 raw 重算，故当前不触发；任何输出缓存复用
  /// 的改动都必须先解除此契约。
  static List<ToolCallGroup> withThinkingRows({
    required List<ToolCallGroup> groups,
    required List<ChatMessage> messages,
    int? messageOffset,
    bool hideThinking = false,
  }) {
    if (messages.isEmpty) return groups;

    final turnKeysByAssistantAnchor =
        TranscriptTurnClassifier.assistantTurnKeysByAnchorID(
          messages,
          messageOffset: messageOffset,
        );

    // 索引各 assistant 消息与其关联的 raw groups
    final rawGroupsByAnchor = <String, List<ToolCallGroup>>{};
    for (final group in groups) {
      final anchor = group.anchorMessageID;
      if (anchor != null) {
        rawGroupsByAnchor.putIfAbsent(anchor, () => []).add(group);
      }
    }

    final turns = <String, List<_AssistantMsgInfo>>{};
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != 'assistant') continue;
      final anchor = TranscriptTurnClassifier.anchorID(
        message,
        at: i,
        messageOffset: messageOffset,
      );
      final turnKey = turnKeysByAssistantAnchor[anchor] ?? 'turn:default';
      final hasText = message.content?.trim().isNotEmpty == true;
      final reasoning = message.reasoning?.trim();
      final msgToolGroups = [
        ...?rawGroupsByAnchor[anchor],
        if (message.messageId != null && message.messageId != anchor)
          ...?rawGroupsByAnchor[message.messageId!],
      ];

      turns
          .putIfAbsent(turnKey, () => [])
          .add(
            _AssistantMsgInfo(
              index: i,
              message: message,
              anchor: anchor,
              turnKey: turnKey,
              hasText: hasText,
              reasoning: (reasoning != null && reasoning.isNotEmpty)
                  ? reasoning
                  : null,
              toolGroups: msgToolGroups,
            ),
          );
    }

    final result = <ToolCallGroup>[];
    final handledRawGroupIds = <String>{};

    for (final turnMessages in turns.values) {
      final textMessages = turnMessages.where((m) => m.hasText).toList();

      if (textMessages.isEmpty) {
        // 回合内无任何可见文本：全部非文本事件进入同一区间（Interval 0）
        final calls = <ToolCall>[];
        String? preferredId;
        final targetAnchor = turnMessages.first.anchor;

        for (final m in turnMessages) {
          if (!hideThinking && m.reasoning != null) {
            calls.add(ToolCall.thinking(m.reasoning!));
          }
          for (final tg in m.toolGroups) {
            handledRawGroupIds.add(tg.id);
            preferredId ??= tg.id;
            calls.addAll(tg.toolCalls);
          }
        }

        if (calls.isNotEmpty) {
          result.add(
            ToolCallGroup(
              id: preferredId ?? 'persisted-think-$targetAnchor',
              anchorMessageID: targetAnchor,
              precedingMessageID: null,
              isAboveContent: true,
              toolCalls: _uniqueToolCalls(calls),
            ),
          );
        }
        continue;
      }

      // 回合内存在可见文本：按文本切分区间
      // Interval 0: 首段文本之前
      // Interval j (1..textMessages.length - 1): textMessages[j-1] 与 textMessages[j] 之间
      // Interval last: textMessages.last 之后
      final intervalCount = textMessages.length + 1;
      final intervalCalls = List.generate(intervalCount, (_) => <ToolCall>[]);
      final intervalPreferredIds = List<String?>.filled(intervalCount, null);

      final firstTextIdx = textMessages.first.index;
      final lastTextIdx = textMessages.last.index;

      for (final m in turnMessages) {
        // 1) reasoning：在 m 自身文本之前
        if (!hideThinking && m.reasoning != null) {
          final int thinkInterval;
          if (m.index <= firstTextIdx) {
            thinkInterval = 0;
          } else {
            var prevTextIdx = 0;
            for (var j = 0; j < textMessages.length; j++) {
              if (textMessages[j].index < m.index) {
                prevTextIdx = j;
              } else {
                break;
              }
            }
            thinkInterval = prevTextIdx + 1;
          }
          intervalCalls[thinkInterval].add(ToolCall.thinking(m.reasoning!));
        }

        // 2) tools：在 m 自身文本之后
        if (m.toolGroups.isNotEmpty) {
          final int toolsInterval;
          if (m.index < firstTextIdx) {
            toolsInterval = 0;
          } else if (m.index >= lastTextIdx) {
            toolsInterval = textMessages.length;
          } else {
            var prevTextIdx = 0;
            for (var j = 0; j < textMessages.length; j++) {
              if (textMessages[j].index <= m.index) {
                prevTextIdx = j;
              } else {
                break;
              }
            }
            toolsInterval = prevTextIdx + 1;
          }

          for (final tg in m.toolGroups) {
            handledRawGroupIds.add(tg.id);
            intervalPreferredIds[toolsInterval] ??= tg.id;
            intervalCalls[toolsInterval].addAll(tg.toolCalls);
          }
        }
      }

      // 组装生成的区间组
      for (var intervalIdx = 0; intervalIdx < intervalCount; intervalIdx++) {
        final calls = intervalCalls[intervalIdx];
        if (calls.isEmpty) continue;

        if (intervalIdx == 0) {
          final targetAnchor = textMessages.first.anchor;
          result.add(
            ToolCallGroup(
              id: intervalPreferredIds[0] ?? 'persisted-think-$targetAnchor',
              anchorMessageID: targetAnchor,
              precedingMessageID: null,
              isAboveContent: true,
              toolCalls: _uniqueToolCalls(calls),
            ),
          );
        } else {
          final prevText = textMessages[intervalIdx - 1];
          // 若本区间有 raw 工具组，保留其原始锚点（渲染位置等价：卡片仍在前段
          // 正文之后，且 metadata 路径的空正文携带消息行得以按既有契约保留）。
          final preferredId = intervalPreferredIds[intervalIdx];
          final rawAnchor = preferredId == null
              ? null
              : groups.firstWhere((g) => g.id == preferredId).anchorMessageID;
          final targetAnchor = rawAnchor ?? prevText.anchor;
          result.add(
            ToolCallGroup(
              id:
                  preferredId ??
                  (intervalIdx < textMessages.length
                      ? 'persisted-tools-${prevText.anchor}'
                      : 'persisted-tools-trailing-${prevText.anchor}'),
              anchorMessageID: targetAnchor,
              precedingMessageID: prevText.anchor,
              isAboveContent: false,
              toolCalls: _uniqueToolCalls(calls),
            ),
          );
        }
      }
    }

    // 保留未被 assistant 消息映射到的 raw groups
    for (final group in groups) {
      if (!handledRawGroupIds.contains(group.id)) {
        result.add(group);
      }
    }

    return result;
  }

  /// 主组 + 兜底组按 anchor 及区间方向合并（Swift `merging`）。
  static List<ToolCallGroup> merging({
    required List<ToolCallGroup> primaryGroups,
    required List<ToolCallGroup> fallbackGroups,
  }) {
    final merged = List<ToolCallGroup>.from(primaryGroups);
    final groupIndexesByKey = <String, int>{};
    for (var i = 0; i < primaryGroups.length; i++) {
      final g = primaryGroups[i];
      if (g.anchorMessageID != null) {
        groupIndexesByKey['${g.anchorMessageID}:${g.isAboveContent}'] = i;
      }
    }

    for (final fallbackGroup in fallbackGroups) {
      final anchorMessageID = fallbackGroup.anchorMessageID;
      final key = anchorMessageID == null
          ? null
          : '$anchorMessageID:${fallbackGroup.isAboveContent}';
      final groupIndex = key == null ? null : groupIndexesByKey[key];
      if (groupIndex != null) {
        final existingGroup = merged[groupIndex];
        merged[groupIndex] = ToolCallGroup(
          id: existingGroup.id,
          anchorMessageID: existingGroup.anchorMessageID,
          precedingMessageID: existingGroup.precedingMessageID,
          isAboveContent: existingGroup.isAboveContent,
          toolCalls: _mergingToolCalls(
            primaryToolCalls: existingGroup.toolCalls,
            fallbackToolCalls: fallbackGroup.toolCalls,
          ),
        );
        continue;
      }

      // 指纹兜底比对：在 fallbackGroup 未通过 anchor key 匹配到既有组时，
      // 检查 merged 中是否已有内容指纹相等或互为子集的组，防锚点空间漂移（如 stream- 临时 id vs raw:）。
      var matchedFingerprintIndex = -1;
      for (var i = 0; i < merged.length; i++) {
        final existing = merged[i];
        if (existing.isAboveContent != fallbackGroup.isAboveContent) continue;
        if (_isToolCallsEqual(existing.toolCalls, fallbackGroup.toolCalls) ||
            _isToolCallsSubset(fallbackGroup.toolCalls, existing.toolCalls) ||
            _isToolCallsSubset(existing.toolCalls, fallbackGroup.toolCalls)) {
          matchedFingerprintIndex = i;
          break;
        }
      }

      if (matchedFingerprintIndex != -1) {
        final existingGroup = merged[matchedFingerprintIndex];
        final bool fallbackIsSuperset = _isToolCallsSubset(
          existingGroup.toolCalls,
          fallbackGroup.toolCalls,
        );
        merged[matchedFingerprintIndex] = ToolCallGroup(
          id: existingGroup.id,
          anchorMessageID: existingGroup.anchorMessageID,
          precedingMessageID: existingGroup.precedingMessageID,
          isAboveContent: existingGroup.isAboveContent,
          toolCalls: fallbackIsSuperset
              ? _mergingToolCalls(
                  primaryToolCalls: fallbackGroup.toolCalls,
                  fallbackToolCalls: existingGroup.toolCalls,
                )
              : _mergingToolCalls(
                  primaryToolCalls: existingGroup.toolCalls,
                  fallbackToolCalls: fallbackGroup.toolCalls,
                ),
        );
        if (key != null) {
          groupIndexesByKey[key] = matchedFingerprintIndex;
        }
        continue;
      }

      if (key != null) {
        groupIndexesByKey[key] = merged.length;
      }
      merged.add(fallbackGroup);
    }
    return merged;
  }

  /// 按 assistant 回合合并相邻组（Swift `coalescingByAssistantTurn`）。
  static List<ToolCallGroup> coalescingByAssistantTurn(
    List<ToolCallGroup> groups, {
    required List<ChatMessage> messages,
    int? messageOffset,
  }) {
    if (groups.length <= 1) {
      return groups.map((group) {
        return ToolCallGroup(
          id: group.id,
          anchorMessageID: group.anchorMessageID,
          precedingMessageID: group.precedingMessageID,
          isAboveContent: group.isAboveContent,
          toolCalls: _uniqueToolCalls(group.toolCalls),
        );
      }).toList();
    }

    final messageIndexesByID = <String, int>{};
    for (var i = 0; i < messages.length; i++) {
      messageIndexesByID[TranscriptTurnClassifier.anchorID(
            messages[i],
            at: i,
            messageOffset: messageOffset,
          )] =
          i;
    }
    final turnKeysByAssistantMessageID =
        TranscriptTurnClassifier.assistantTurnKeysByAnchorID(
          messages,
          messageOffset: messageOffset,
        );

    final earliestAssistantAnchorByTurnKey = <String, String>{};
    final firstTextAssistantAnchorByTurnKey = <String, String>{};
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != 'assistant') continue;
      final anchor = TranscriptTurnClassifier.anchorID(
        message,
        at: i,
        messageOffset: messageOffset,
      );
      final turnKey = turnKeysByAssistantMessageID[anchor];
      if (turnKey != null) {
        earliestAssistantAnchorByTurnKey.putIfAbsent(turnKey, () => anchor);
        if (message.content?.trim().isNotEmpty == true) {
          firstTextAssistantAnchorByTurnKey.putIfAbsent(turnKey, () => anchor);
        }
      }
    }

    final mergedGroups = <_TurnGroupBuilder>[];
    final builderIndexesByTurnKey = <String, int>{};

    for (var groupOrder = 0; groupOrder < groups.length; groupOrder++) {
      final group = groups[groupOrder];
      final anchorIndex = group.anchorMessageID == null
          ? (1 << 62) - groupOrder
          : (messageIndexesByID[group.anchorMessageID] ??
                (1 << 62) - groupOrder);
      final turnKey = group.anchorMessageID == null
          ? 'group:${group.id}'
          : (turnKeysByAssistantMessageID[group.anchorMessageID] ??
                'group:${group.id}');

      final builderIndex = builderIndexesByTurnKey[turnKey];
      if (builderIndex != null) {
        mergedGroups[builderIndex].append(group, anchorIndex: anchorIndex);
      } else {
        builderIndexesByTurnKey[turnKey] = mergedGroups.length;
        mergedGroups.add(
          _TurnGroupBuilder(
            turnKey: turnKey,
            group: group,
            anchorIndex: anchorIndex,
          ),
        );
      }
    }

    mergedGroups.sort((lhs, rhs) {
      if (lhs.anchorIndex == rhs.anchorIndex) {
        return lhs.turnKey.compareTo(rhs.turnKey);
      }
      return lhs.anchorIndex.compareTo(rhs.anchorIndex);
    });

    return mergedGroups.map((builder) {
      final firstTextAnchor =
          firstTextAssistantAnchorByTurnKey[builder.turnKey];
      final earliestAnchor = earliestAssistantAnchorByTurnKey[builder.turnKey];
      final turnAnchor =
          firstTextAnchor ?? earliestAnchor ?? builder.anchorMessageID;

      // 卡位 = 组内第一个事件在时间线上的实际位置
      // 聚合开关开启时，若回合首个事件为思考或首组位于正文上方，大卡钉在首条正文上方。
      final isAbove =
          builder.isAboveContent ||
          (builder.toolCalls.isNotEmpty && builder.toolCalls.first.isThinking);

      return ToolCallGroup(
        id: builder.id,
        anchorMessageID: turnAnchor,
        precedingMessageID: isAbove ? null : turnAnchor,
        isAboveContent: isAbove,
        toolCalls: _uniqueToolCalls(builder.toolCalls),
      );
    }).toList();
  }

  /// 相邻聚合（聚合开关关闭时的语义：不等于完全不聚合）。
  ///
  /// 同一回合内，仅当相邻两组之间**没有**带可见文本的 assistant 消息打断
  /// 且卡位方向一致时才合并为一张卡；被打断则保持分离，呈现穿插布局。
  static List<ToolCallGroup> coalescingAdjacent(
    List<ToolCallGroup> groups, {
    required List<ChatMessage> messages,
    int? messageOffset,
  }) {
    if (groups.length <= 1) {
      return groups.map((group) {
        return ToolCallGroup(
          id: group.id,
          anchorMessageID: group.anchorMessageID,
          precedingMessageID: group.precedingMessageID,
          isAboveContent: group.isAboveContent,
          toolCalls: _uniqueToolCalls(group.toolCalls),
        );
      }).toList();
    }

    final messageIndexesByID = <String, int>{};
    for (var i = 0; i < messages.length; i++) {
      messageIndexesByID[TranscriptTurnClassifier.anchorID(
            messages[i],
            at: i,
            messageOffset: messageOffset,
          )] =
          i;
    }

    /// 两组之间是否存在「可见正文」——**只认 assistant 正文**，即把 assistant 的非空
    /// content 当作回合分界。user 消息与工具消息都不算分界，因此「跨用户回合、但中间
    /// 没有 assistant 正文」的两组仍会被判为可合并（与 coalescingAdjacent 上
    /// 「同一回合内」的表述不同源，属既有行为，已由
    /// test/core/models/tool_call_group_coalesce_extra_test.dart 固化）。
    bool hasTextBetween(int prevIndex, int curIndex) {
      for (var k = prevIndex + 1; k < curIndex; k++) {
        if (k < 0 || k >= messages.length) continue;
        final message = messages[k];
        if (message.role != 'assistant') continue;
        if (message.content?.trim().isNotEmpty == true) return true;
      }
      return false;
    }

    // 时间线新语义：后组锚点消息**自身**带可见正文时，该正文位于两组之间
    // （组钉在「该段正文之后」），同样是分隔符，不得合并。
    final textAnchorIDs = <String>{};
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != 'assistant') continue;
      if (message.content?.trim().isNotEmpty == true) {
        textAnchorIDs.add(
          TranscriptTurnClassifier.anchorID(
            message,
            at: i,
            messageOffset: messageOffset,
          ),
        );
      }
    }

    // 指纹比对预处理：扫描互为相等或子集的组（防死锚/空间漂移产生的重复卡）
    final deduped = <ToolCallGroup>[];
    for (final group in groups) {
      final groupAnchorIdx = group.anchorMessageID == null
          ? -1
          : (messageIndexesByID[group.anchorMessageID] ?? -1);

      var matchedIndex = -1;
      for (var j = 0; j < deduped.length; j++) {
        final existing = deduped[j];
        if (existing.isAboveContent != group.isAboveContent) continue;

        final existingAnchorIdx = existing.anchorMessageID == null
            ? -1
            : (messageIndexesByID[existing.anchorMessageID] ?? -1);

        // 两组都在当前 messages 且属于不同回合（有文本打断）→ 保守：绝不跨回合去重
        if (existingAnchorIdx >= 0 &&
            groupAnchorIdx >= 0 &&
            (hasTextBetween(existingAnchorIdx, groupAnchorIdx) ||
                (existingAnchorIdx != groupAnchorIdx &&
                    (textAnchorIDs.contains(group.anchorMessageID) ||
                        textAnchorIDs.contains(existing.anchorMessageID))))) {
          continue;
        }

        final isEqual = _isToolCallsEqual(existing.toolCalls, group.toolCalls);
        final isSub = _isToolCallsSubset(group.toolCalls, existing.toolCalls);
        final isSuper = _isToolCallsSubset(existing.toolCalls, group.toolCalls);

        if (isEqual || isSub || isSuper) {
          matchedIndex = j;
          final targetAnchor = (existingAnchorIdx < 0 && groupAnchorIdx >= 0)
              ? group.anchorMessageID
              : existing.anchorMessageID;
          final targetId = (existingAnchorIdx < 0 && groupAnchorIdx >= 0)
              ? group.id
              : existing.id;
          final targetPreceding = (existingAnchorIdx < 0 && groupAnchorIdx >= 0)
              ? group.precedingMessageID
              : existing.precedingMessageID;

          deduped[j] = ToolCallGroup(
            id: targetId,
            anchorMessageID: targetAnchor,
            precedingMessageID: targetPreceding,
            isAboveContent: existing.isAboveContent,
            toolCalls: isSuper
                ? _mergingToolCalls(
                    primaryToolCalls: group.toolCalls,
                    fallbackToolCalls: existing.toolCalls,
                  )
                : _mergingToolCalls(
                    primaryToolCalls: existing.toolCalls,
                    fallbackToolCalls: group.toolCalls,
                  ),
          );
          break;
        }
      }

      if (matchedIndex == -1) {
        deduped.add(group);
      }
    }

    final merged = <ToolCallGroup>[];
    final anchorIndexes = <String, int>{};
    final groupOrderIndexes = <String, int>{};
    for (var i = 0; i < deduped.length; i++) {
      final group = deduped[i];
      groupOrderIndexes[group.id] = i;
      if (group.anchorMessageID != null) {
        anchorIndexes[group.id] =
            messageIndexesByID[group.anchorMessageID] ?? -1;
      }
    }

    final orderedIds = deduped.map((g) => g.id).toList()
      ..sort((a, b) {
        final ia = anchorIndexes[a] ?? (1 << 62) - groupOrderIndexes[a]!;
        final ib = anchorIndexes[b] ?? (1 << 62) - groupOrderIndexes[b]!;
        final cmp = ia.compareTo(ib);
        if (cmp != 0) return cmp;
        final ga = deduped.firstWhere((g) => g.id == a);
        final gb = deduped.firstWhere((g) => g.id == b);
        if (ga.isAboveContent != gb.isAboveContent) {
          return ga.isAboveContent ? -1 : 1;
        }
        return (groupOrderIndexes[a] ?? 0).compareTo(groupOrderIndexes[b] ?? 0);
      });

    ToolCallGroup? current;
    int? currentAnchorIndex;
    for (final id in orderedIds) {
      final group = deduped.firstWhere((g) => g.id == id);
      final anchorIndex = anchorIndexes[id] ?? -1;
      final currIdx = currentAnchorIndex;
      if (current == null || currIdx == null) {
        current = group;
        currentAnchorIndex = anchorIndex;
        continue;
      }
      final isAnchoredMerge =
          currIdx >= 0 &&
          anchorIndex >= 0 &&
          current.isAboveContent == group.isAboveContent &&
          !hasTextBetween(currIdx, anchorIndex) &&
          !(anchorIndex != currIdx &&
              textAnchorIDs.contains(group.anchorMessageID));

      // C（可选加固）：coalescingAdjacent 对 anchorIndex < 0 的组按 isAboveContent + 最近有锚组归并，
      // 触发条件：相邻两组卡位方向一致，且其中一方为未命中 messages 的死锚组（anchorIndex < 0）。
      final isUnanchoredLeakMerge =
          current.isAboveContent == group.isAboveContent &&
          ((currIdx >= 0 && anchorIndex < 0) ||
              (currIdx < 0 && anchorIndex >= 0));

      final canMerge = isAnchoredMerge || isUnanchoredLeakMerge;
      if (canMerge) {
        if (currIdx < 0 && anchorIndex >= 0) {
          current = ToolCallGroup(
            id: group.id,
            anchorMessageID: group.anchorMessageID,
            precedingMessageID: group.precedingMessageID,
            isAboveContent: group.isAboveContent,
            toolCalls: _mergingToolCalls(
              primaryToolCalls: group.toolCalls,
              fallbackToolCalls: current.toolCalls,
            ),
          );
          currentAnchorIndex = anchorIndex;
        } else {
          current = _mergingToolCallGroup(current, group);
        }
        continue;
      }
      merged.add(current);
      current = group;
      currentAnchorIndex = anchorIndex;
    }
    if (current != null) merged.add(current);

    return merged.map((group) {
      return ToolCallGroup(
        id: group.id,
        anchorMessageID: group.anchorMessageID,
        precedingMessageID: group.precedingMessageID,
        isAboveContent: group.isAboveContent,
        toolCalls: _uniqueToolCalls(group.toolCalls),
      );
    }).toList();
  }

  // MARK: - 内部聚合

  static List<ToolCallGroup> _groupsFromPersistedToolCalls(
    List<PersistedToolCall> persistedToolCalls,
    List<ChatMessage> messages,
    int? messageOffset,
  ) {
    final offset = messageOffset ?? 0;
    final groups = <ToolCallGroup>[];
    final groupIndexesByAnchor = <String, int>{};

    for (
      var toolIndex = 0;
      toolIndex < persistedToolCalls.length;
      toolIndex++
    ) {
      final persistedToolCall = persistedToolCalls[toolIndex];
      final assistantMsgIdx = persistedToolCall.assistantMsgIdx;
      if (assistantMsgIdx == null) continue;

      final loadedMessageIndex = assistantMsgIdx - offset;
      if (loadedMessageIndex < 0 || loadedMessageIndex >= messages.length) {
        continue;
      }

      final anchorMessageID = TranscriptTurnClassifier.assistantAnchorID(
        loadedMessageIndex,
        messages,
        messageOffset: messageOffset,
      );
      if (anchorMessageID == null) continue;

      final toolCall = persistedToolCall.toolCall(toolIndex);
      final existingIndex = groupIndexesByAnchor[anchorMessageID];
      if (existingIndex != null) {
        final existingGroup = groups[existingIndex];
        groups[existingIndex] = ToolCallGroup(
          id: existingGroup.id,
          anchorMessageID: existingGroup.anchorMessageID,
          toolCalls: [...existingGroup.toolCalls, toolCall],
        );
      } else {
        groupIndexesByAnchor[anchorMessageID] = groups.length;
        groups.add(
          ToolCallGroup(
            id: 'persisted-tools-$anchorMessageID',
            anchorMessageID: anchorMessageID,
            toolCalls: [toolCall],
          ),
        );
      }
    }
    return groups;
  }

  static List<ToolCallGroup> _groupsFromMessageMetadata(
    List<ChatMessage> messages,
    int? messageOffset,
  ) {
    final resultsByToolID = _toolResultSnippetsByID(messages);
    final groups = <ToolCallGroup>[];
    String? currentAnchorMessageID;
    var currentToolCalls = <ToolCall>[];

    void flushCurrentGroup() {
      if (currentToolCalls.isEmpty) {
        currentAnchorMessageID = null;
        return;
      }
      groups.add(
        ToolCallGroup(
          id: 'persisted-tools-${currentAnchorMessageID ?? 'unanchored-${groups.length}'}',
          anchorMessageID: currentAnchorMessageID,
          toolCalls: _uniqueToolCalls(currentToolCalls),
        ),
      );
      currentAnchorMessageID = null;
      currentToolCalls = [];
    }

    for (var messageIndex = 0; messageIndex < messages.length; messageIndex++) {
      final message = messages[messageIndex];
      if (TranscriptTurnClassifier.isUserTurnBoundary(message)) {
        flushCurrentGroup();
        continue;
      }
      if (message.role != 'assistant') continue;

      final toolCalls =
          _openAIToolCalls(
            message,
            messageIndex: messageIndex,
            resultsByToolID: resultsByToolID,
          ) +
          _anthropicToolCalls(
            message,
            messageIndex: messageIndex,
            resultsByToolID: resultsByToolID,
          );
      if (toolCalls.isEmpty) continue;

      final anchor = TranscriptTurnClassifier.anchorID(
        message,
        at: messageIndex,
        messageOffset: messageOffset,
      );
      if (currentAnchorMessageID == null) {
        currentAnchorMessageID = anchor;
      } else if (anchor != currentAnchorMessageID) {
        // 连续工具聚合：若新消息与当前累计的最后一条都无可见文本，则视为同一连续段，不切分
        final hasVisibleText = message.content?.trim().isNotEmpty == true;
        // 查找当前段最后一条消息是否有可见文本（近似：若 currentAnchor 对应的消息有文本，则已是一段带文本的段落）
        var currentHasText = false;
        for (var k = messageIndex - 1; k >= 0; k--) {
          if (TranscriptTurnClassifier.anchorID(
                messages[k],
                at: k,
                messageOffset: messageOffset,
              ) ==
              currentAnchorMessageID) {
            if (messages[k].content?.trim().isNotEmpty == true) {
              currentHasText = true;
            }
            break;
          }
        }
        if (hasVisibleText || currentHasText) {
          flushCurrentGroup();
          currentAnchorMessageID = anchor;
        }
        // 否则：连续无文本的工具调用，继续累加到同一分组
      }
      currentToolCalls += toolCalls;
    }

    flushCurrentGroup();
    return groups;
  }

  static Map<String, String> _toolResultSnippetsByID(
    List<ChatMessage> messages,
  ) {
    final result = <String, String>{};
    for (final message in messages) {
      if (message.role == 'tool') {
        final toolCallID =
            _nonEmpty(message.toolCallId) ?? _nonEmpty(message.toolUseId);
        final content = _nonEmpty(message.content);
        if (toolCallID != null && content != null) {
          result[toolCallID] = content;
        }
      }
      for (final part in message.contentParts ?? const <JsonValue>[]) {
        final toolResult = _toolResult(from: part);
        if (toolResult != null) {
          result[toolResult.id] = toolResult.content;
        }
      }
    }
    return result;
  }

  static List<ToolCall> _openAIToolCalls(
    ChatMessage message, {
    required int messageIndex,
    required Map<String, String> resultsByToolID,
  }) {
    final result = <ToolCall>[];
    final toolCalls = message.toolCalls ?? const <JsonValue>[];
    for (var toolIndex = 0; toolIndex < toolCalls.length; toolIndex++) {
      final call = _toolCall(
        fromOpenAIToolCall: toolCalls[toolIndex],
        messageIndex: messageIndex,
        toolIndex: toolIndex,
        resultsByToolID: resultsByToolID,
      );
      if (call != null) result.add(call);
    }
    return result;
  }

  static ToolCall? _toolCall({
    required JsonValue fromOpenAIToolCall,
    required int messageIndex,
    required int toolIndex,
    required Map<String, String> resultsByToolID,
  }) {
    if (fromOpenAIToolCall is! JsonObject) return null;
    final object = fromOpenAIToolCall.value;

    final function = object['function']?.objectValue;
    final name =
        _nonEmpty(function?['name']?.stringValue) ??
        _nonEmpty(object['name']?.stringValue) ??
        'tool';
    final toolID =
        _nonEmpty(object['id']?.stringValue) ??
        _nonEmpty(object['call_id']?.stringValue) ??
        _nonEmpty(object['tool_call_id']?.stringValue) ??
        'message-tool-$messageIndex-$toolIndex';
    final argumentValue =
        function?['arguments'] ??
        object['arguments'] ??
        object['args'] ??
        object['input'];
    final preview =
        _nonEmpty(resultsByToolID[toolID]) ??
        _nonEmpty(object['snippet']?.stringValue) ??
        _nonEmpty(object['preview']?.stringValue);

    final isError =
        object['is_error']?.boolValue ?? object['isError']?.boolValue;
    return ToolCall(
      id: toolID,
      name: name,
      preview: preview,
      args: _arguments(argumentValue),
      isError: isError,
      isCompleted: true,
    );
  }

  static List<ToolCall> _anthropicToolCalls(
    ChatMessage message, {
    required int messageIndex,
    required Map<String, String> resultsByToolID,
  }) {
    final result = <ToolCall>[];
    final parts = message.contentParts ?? const <JsonValue>[];
    for (var toolIndex = 0; toolIndex < parts.length; toolIndex++) {
      final value = parts[toolIndex];
      if (value is! JsonObject) continue;
      final object = value.value;
      if (object['type']?.stringValue != 'tool_use') continue;

      final name = _nonEmpty(object['name']?.stringValue) ?? 'tool';
      final toolID =
          _nonEmpty(object['id']?.stringValue) ??
          'message-tool-$messageIndex-$toolIndex';
      final argumentValue =
          object['input'] ?? object['arguments'] ?? object['args'];

      result.add(
        ToolCall(
          id: toolID,
          name: name,
          preview:
              _nonEmpty(resultsByToolID[toolID]) ??
              _nonEmpty(object['snippet']?.stringValue) ??
              _nonEmpty(object['preview']?.stringValue),
          args: _arguments(argumentValue),
          isCompleted: true,
        ),
      );
    }
    return result;
  }

  static ({String id, String content})? _toolResult({required JsonValue from}) {
    if (from is! JsonObject) return null;
    final object = from.value;
    if (object['type']?.stringValue != 'tool_result') return null;
    final id =
        _nonEmpty(object['tool_use_id']?.stringValue) ??
        _nonEmpty(object['tool_call_id']?.stringValue) ??
        _nonEmpty(object['id']?.stringValue);
    final content = _resultContent(object['content']);
    if (id == null || content == null) return null;
    return (id: id, content: content);
  }

  static String? _resultContent(JsonValue? value) {
    if (value == null) return null;
    switch (value) {
      case JsonString(:final value):
        return _nonEmpty(value);
      case JsonArray(:final value):
        final text = value
            .map((item) {
              if (item is JsonString) return item.value;
              if (item is JsonObject) {
                return item.value['text']?.stringValue ??
                    item.value['content']?.stringValue;
              }
              return null;
            })
            .whereType<String>()
            .join();
        return _nonEmpty(text);
      case JsonObject() || JsonNumber() || JsonBool() || JsonNull():
        return _nonEmpty(value.compactJsonString);
    }
  }

  static List<ToolCall> _uniqueToolCalls(List<ToolCall> toolCalls) {
    final stableIDIndexes = <String, int>{};
    final fingerprintIndexes = <String, int>{};
    final uniqueToolCalls = <ToolCall>[];
    final isGeneratedByIndex = <bool>[];

    for (final toolCall in toolCalls) {
      final isGenerated = _isGeneratedToolID(toolCall.id);
      final fingerprint = _toolCallFingerprint(toolCall);
      final stableIDIndex = isGenerated ? null : stableIDIndexes[toolCall.id];
      final fingerprintIndex = fingerprintIndexes[fingerprint];
      final resolvedFingerprintIndex = fingerprintIndex == null
          ? null
          : (isGenerated || isGeneratedByIndex[fingerprintIndex]
                ? fingerprintIndex
                : null);

      final existingIndex = stableIDIndex ?? resolvedFingerprintIndex;
      if (existingIndex != null) {
        uniqueToolCalls[existingIndex] = _mergingToolCall(
          uniqueToolCalls[existingIndex],
          fallbackCall: toolCall,
        );
        isGeneratedByIndex[existingIndex] = _isGeneratedToolID(
          uniqueToolCalls[existingIndex].id,
        );
        if (!isGenerated) {
          stableIDIndexes[toolCall.id] = existingIndex;
        }
        fingerprintIndexes[fingerprint] = existingIndex;
      } else {
        if (!isGenerated) {
          stableIDIndexes[toolCall.id] = uniqueToolCalls.length;
        }
        if (fingerprintIndexes[fingerprint] == null || isGenerated) {
          fingerprintIndexes[fingerprint] = uniqueToolCalls.length;
        }
        isGeneratedByIndex.add(isGenerated);
        uniqueToolCalls.add(toolCall);
      }
    }
    return uniqueToolCalls;
  }

  /// 相邻合并辅助：把 [other] 的工具调用并入 [base]，保留 base 的 id/anchor。
  static ToolCallGroup _mergingToolCallGroup(
    ToolCallGroup base,
    ToolCallGroup other,
  ) {
    return ToolCallGroup(
      id: base.id,
      anchorMessageID: base.anchorMessageID,
      precedingMessageID: base.precedingMessageID,
      isAboveContent: base.isAboveContent,
      toolCalls: _mergingToolCalls(
        primaryToolCalls: base.toolCalls,
        fallbackToolCalls: other.toolCalls,
      ),
    );
  }

  static List<ToolCall> _mergingToolCalls({
    required List<ToolCall> primaryToolCalls,
    required List<ToolCall> fallbackToolCalls,
  }) {
    final mergedToolCalls = _uniqueToolCalls(primaryToolCalls);
    final fallbackNameOrdinals = <String, int>{};

    for (final fallbackToolCall in fallbackToolCalls) {
      final nameKey = _toolCallNameKey(fallbackToolCall);
      final nameOrdinal = (fallbackNameOrdinals[nameKey] ?? 0) + 1;
      fallbackNameOrdinals[nameKey] = nameOrdinal;

      final existingIndex = _matchingToolCallIndex(
        fallbackToolCall,
        nameOrdinal: nameOrdinal,
        toolCalls: mergedToolCalls,
      );
      if (existingIndex != null) {
        mergedToolCalls[existingIndex] = _mergingToolCall(
          mergedToolCalls[existingIndex],
          fallbackCall: fallbackToolCall,
        );
      } else {
        mergedToolCalls.add(fallbackToolCall);
      }
    }
    return _uniqueToolCalls(mergedToolCalls);
  }

  static int? _matchingToolCallIndex(
    ToolCall fallbackToolCall, {
    required int nameOrdinal,
    required List<ToolCall> toolCalls,
  }) {
    final fallbackIsGenerated = _isGeneratedToolID(fallbackToolCall.id);

    if (!fallbackIsGenerated) {
      for (var i = 0; i < toolCalls.length; i++) {
        final toolCall = toolCalls[i];
        if (!_isGeneratedToolID(toolCall.id) &&
            toolCall.id == fallbackToolCall.id) {
          return i;
        }
      }
    }

    final fallbackFingerprint = _toolCallFingerprint(fallbackToolCall);
    for (var i = 0; i < toolCalls.length; i++) {
      final toolCall = toolCalls[i];
      if ((fallbackIsGenerated || _isGeneratedToolID(toolCall.id)) &&
          _toolCallFingerprint(toolCall) == fallbackFingerprint) {
        return i;
      }
    }

    return _matchingToolCallNameOrdinalIndex(
      fallbackToolCall,
      fallbackIsGenerated: fallbackIsGenerated,
      nameOrdinal: nameOrdinal,
      toolCalls: toolCalls,
    );
  }

  static int? _matchingToolCallNameOrdinalIndex(
    ToolCall fallbackToolCall, {
    required bool fallbackIsGenerated,
    required int nameOrdinal,
    required List<ToolCall> toolCalls,
  }) {
    final fallbackNameKey = _toolCallNameKey(fallbackToolCall);
    var currentOrdinal = 0;

    for (var index = 0; index < toolCalls.length; index++) {
      final toolCall = toolCalls[index];
      if (_toolCallNameKey(toolCall) != fallbackNameKey) continue;
      if (!fallbackIsGenerated && !_isGeneratedToolID(toolCall.id)) continue;

      currentOrdinal += 1;
      if (currentOrdinal == nameOrdinal) {
        return index;
      }
    }
    return null;
  }

  static String _toolCallNameKey(ToolCall toolCall) =>
      toolCall.displayName.trim();

  static String _argumentsKey(Map<String, JsonValue>? args) {
    if (args == null || args.isEmpty) return '';
    final keys = args.keys.toList()..sort();
    final sortedObject = <String, JsonValue>{
      for (final key in keys) key: args[key]!,
    };
    return JsonObject(sortedObject).compactJsonString ?? '';
  }

  static String _toolCallFingerprint(ToolCall toolCall) {
    // 思考子卡行按内容参与指纹：不同思考段不得互相去重（同 name 无 args）。
    if (toolCall.isThinking) {
      return 'fallback:thinking:${toolCall.thinking ?? ''}';
    }
    return [
      'fallback',
      toolCall.displayName,
      _argumentsKey(toolCall.args),
    ].join(':');
  }

  static bool _toolCallsMatch(ToolCall a, ToolCall b) {
    if (a.isThinking != b.isThinking) return false;
    if (a.isThinking) {
      return (a.thinking ?? '').trim() == (b.thinking ?? '').trim();
    }
    final aStable = !_isGeneratedToolID(a.id) && a.id.trim().isNotEmpty;
    final bStable = !_isGeneratedToolID(b.id) && b.id.trim().isNotEmpty;
    if (aStable && bStable) {
      return a.id == b.id;
    }
    return _toolCallFingerprint(a) == _toolCallFingerprint(b);
  }

  static bool _isToolCallsEqual(List<ToolCall> a, List<ToolCall> b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a.length != b.length) return false;
    var allMatch = true;
    for (var i = 0; i < a.length; i++) {
      if (!_toolCallsMatch(a[i], b[i])) {
        allMatch = false;
        break;
      }
    }
    if (allMatch) return true;

    final matchedIndices = <int>{};
    for (final callA in a) {
      var found = false;
      for (var j = 0; j < b.length; j++) {
        if (!matchedIndices.contains(j) && _toolCallsMatch(callA, b[j])) {
          matchedIndices.add(j);
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return matchedIndices.length == b.length;
  }

  static bool _isToolCallsSubset(List<ToolCall> sub, List<ToolCall> sup) {
    if (sub.isEmpty || sup.isEmpty) return false;
    if (sub.length >= sup.length) return false;

    final matchedIndices = <int>{};
    for (final callSub in sub) {
      var found = false;
      for (var j = 0; j < sup.length; j++) {
        if (!matchedIndices.contains(j) && _toolCallsMatch(callSub, sup[j])) {
          matchedIndices.add(j);
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  static bool _isGeneratedToolID(String id) {
    return id.startsWith('live-') ||
        id.startsWith('message-tool-') ||
        id.startsWith('persisted-tool-');
  }

  static ToolCall _mergingToolCall(
    ToolCall existing, {
    required ToolCall fallbackCall,
  }) {
    final id =
        _isGeneratedToolID(existing.id) && !_isGeneratedToolID(fallbackCall.id)
        ? fallbackCall.id
        : existing.id;
    return ToolCall(
      id: id,
      name: existing.name ?? fallbackCall.name,
      preview: existing.preview ?? fallbackCall.preview,
      args: existing.args ?? fallbackCall.args,
      duration: existing.duration ?? fallbackCall.duration,
      isError: _mergedErrorState(existing.isError, fallbackCall.isError),
      isCompleted: existing.isCompleted || fallbackCall.isCompleted,
      thinking: _mergedThinking(existing, fallbackCall),
      startedAt: existing.startedAt < fallbackCall.startedAt
          ? existing.startedAt
          : fallbackCall.startedAt,
    );
  }

  /// 合并思考子卡内容：existing 优先；两者都有时拼接（思考段合并不丢文本）。
  /// 同内容（重放/重连出现两次）→ 去重只保留一份。
  static String? _mergedThinking(ToolCall existing, ToolCall fallback) {
    final a = existing.thinking?.trim();
    final b = fallback.thinking?.trim();
    if (a == null || a.isEmpty) return b;
    if (b == null || b.isEmpty) return a;
    if (a == b) return a;
    return '$a\n\n$b';
  }

  static bool? _mergedErrorState(bool? existing, bool? fallback) {
    if (existing == true || fallback == true) return true;
    return existing ?? fallback;
  }

  static Map<String, JsonValue>? _arguments(JsonValue? value) {
    if (value == null) return null;
    if (value is JsonObject) {
      return value.value.isEmpty ? null : value.value;
    }
    if (value is JsonString) {
      final decoded = _tryDecodeJson(value.value);
      if (decoded is JsonObject) {
        return decoded.value.isEmpty ? null : decoded.value;
      }
    }
    return null;
  }

  static JsonValue? _tryDecodeJson(String source) {
    try {
      return JsonValue.fromJson(jsonDecode(source));
    } catch (_) {
      return null;
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  bool operator ==(Object other) {
    return other is ToolCallGroup &&
        other.id == id &&
        other.anchorMessageID == anchorMessageID &&
        other.precedingMessageID == precedingMessageID &&
        other.isAboveContent == isAboveContent &&
        deepEquals(other.toolCalls, toolCalls);
  }

  @override
  int get hashCode => Object.hash(
    id,
    anchorMessageID,
    precedingMessageID,
    isAboveContent,
    deepHash(toolCalls),
  );

  @override
  String toString() {
    return 'ToolCallGroup(id: $id, anchorMessageID: $anchorMessageID, '
        'preceding: $precedingMessageID, isAbove: $isAboveContent, '
        'toolCalls: ${toolCalls.length})';
  }
}

/// 按 anchor 分组查找表（Swift `ToolCallGroupAnchorLookup`）。
class ToolCallGroupAnchorLookup {
  ToolCallGroupAnchorLookup({List<ToolCallGroup> groups = const []}) {
    for (final group in groups) {
      _groupsByAnchor.putIfAbsent(group.anchorMessageID, () => []).add(group);
    }
  }

  final Map<String?, List<ToolCallGroup>> _groupsByAnchor = {};

  List<ToolCallGroup> groups({String? anchorMessageID}) {
    return _groupsByAnchor[anchorMessageID] ?? const [];
  }
}

class _AssistantMsgInfo {
  const _AssistantMsgInfo({
    required this.index,
    required this.message,
    required this.anchor,
    required this.turnKey,
    required this.hasText,
    required this.reasoning,
    required this.toolGroups,
  });

  final int index;
  final ChatMessage message;
  final String anchor;
  final String turnKey;
  final bool hasText;
  final String? reasoning;
  final List<ToolCallGroup> toolGroups;
}

/// 回合组构建器（Swift 私有 `TurnGroupBuilder`）。
class _TurnGroupBuilder {
  _TurnGroupBuilder({
    required this.turnKey,
    required ToolCallGroup group,
    required this.anchorIndex,
  }) : id = group.id,
       anchorMessageID = group.anchorMessageID,
       precedingMessageID = group.precedingMessageID,
       isAboveContent = group.isAboveContent,
       toolCalls = List<ToolCall>.from(group.toolCalls);

  final String turnKey;
  String id;
  String? anchorMessageID;
  String? precedingMessageID;
  bool isAboveContent;
  int anchorIndex;
  List<ToolCall> toolCalls;

  void append(ToolCallGroup group, {required int anchorIndex}) {
    if (anchorIndex < this.anchorIndex ||
        (anchorIndex == this.anchorIndex &&
            group.isAboveContent &&
            !isAboveContent)) {
      id = group.id;
      anchorMessageID = group.anchorMessageID;
      precedingMessageID = group.precedingMessageID;
      isAboveContent = group.isAboveContent;
      this.anchorIndex = anchorIndex;
    }
    toolCalls += group.toolCalls;
  }
}

/// 从工具调用中提取关键参数摘要文本（纯文本，截断前最多 40 字符，无有效摘要返回 null）。
String? toolCallSummary(ToolCall call) {
  final args = call.args;
  if (args != null && args.isNotEmpty) {
    final rawName = call.name?.trim();
    final toolName =
        ((rawName != null && rawName.isNotEmpty)
                ? rawName
                : (call.displayName != 'Tool' ? call.displayName : ''))
            .toLowerCase();

    // 1. 读文件类：read / read_file / cat / view
    if (_isReadFileTool(toolName)) {
      final summary = _extractFileSummary(args);
      if (summary != null) return summary;
    }

    // 2. 写/编辑类：write / edit / str_replace / create
    if (_isWriteFileTool(toolName)) {
      final summary = _extractFileSummary(args);
      if (summary != null) return summary;
    }

    // 3. 终端类：bash / shell / exec / terminal / run / run_command / command
    if (_isTerminalTool(toolName)) {
      final summary = _extractTerminalSummary(args);
      if (summary != null) return summary;
    }

    // 4. 搜索类：grep / search / ripgrep / find
    if (_isSearchTool(toolName)) {
      final summary = _extractSearchSummary(args);
      if (summary != null) return summary;
    }

    // 5. 列表类：glob / list / ls
    if (_isListTool(toolName)) {
      final summary = _extractListSummary(args);
      if (summary != null) return summary;
    }

    // 6. todo/task 类：键含 todo/task/title/content
    final todoSummary = _extractTodoSummary(args);
    if (todoSummary != null) return todoSummary;

    // 若 toolName 未匹配特定分类，也尝试常见参数名匹配
    final fileSummary = _extractFileSummary(args);
    if (fileSummary != null) return fileSummary;

    final terminalSummary = _extractTerminalSummary(args);
    if (terminalSummary != null) return terminalSummary;

    final searchSummary = _extractSearchSummary(args);
    if (searchSummary != null) return searchSummary;

    final listSummary = _extractListSummary(args);
    if (listSummary != null) return listSummary;

    // 7. Generic fallback: 取 args 中第一个非空字符串值（JsonValue 转字符串），截断 40 字符
    for (final entry in args.entries) {
      final str = _jsonValueToDisplayString(entry.value);
      if (str != null) {
        final clean = _cleanSingleLine(str);
        if (clean.isNotEmpty) {
          return _truncate40(clean);
        }
      }
    }
  }

  // 8. 若 args 为空或无有效值，fallback 到 call.preview?.trim()（去换行，截断 40）
  final preview = call.preview;
  if (preview != null && preview.trim().isNotEmpty) {
    final clean = _cleanSingleLine(preview);
    if (clean.isNotEmpty) {
      return _truncate40(clean);
    }
  }

  // 9. 返回 null 表示无摘要
  return null;
}

/// ToolCall 摘要扩展。
extension ToolCallSummaryExtension on ToolCall {
  String? get callSummary => toolCallSummary(this);
}

bool _isReadFileTool(String toolName) {
  return const {
        'read',
        'read_file',
        'readfile',
        'cat',
        'view',
        'view_file',
        'viewfile',
      }.contains(toolName) ||
      toolName.startsWith('read_') ||
      toolName.startsWith('view_');
}

bool _isWriteFileTool(String toolName) {
  return const {
        'write',
        'write_file',
        'writefile',
        'edit',
        'edit_file',
        'editfile',
        'str_replace',
        'strreplace',
        'create',
        'create_file',
        'createfile',
        'patch',
        'apply_patch',
        'applypatch',
        'write_to_file',
        'replace_file_content',
      }.contains(toolName) ||
      toolName.startsWith('write_') ||
      toolName.startsWith('edit_');
}

bool _isTerminalTool(String toolName) {
  return const {
    'bash',
    'shell',
    'exec',
    'terminal',
    'run',
    'run_command',
    'runcommand',
    'command',
    'cmd',
    'zsh',
    'powershell',
  }.contains(toolName);
}

bool _isSearchTool(String toolName) {
  return const {
    'grep',
    'search',
    'ripgrep',
    'find',
    'find_by_name',
    'grep_search',
    'search_web',
    'web_search',
    'websearch',
  }.contains(toolName);
}

bool _isListTool(String toolName) {
  return const {'glob', 'list', 'ls', 'list_dir', 'listdir'}.contains(toolName);
}

String? _extractFileSummary(Map<String, JsonValue> args) {
  final path = _findArgString(args, const [
    'file_path',
    'filepath',
    'path',
    'file',
    'filename',
    'target_file',
    'targetfile',
  ]);
  if (path == null) return null;
  final fileName = _extractFileName(path);
  if (fileName.isEmpty) return null;
  final suffix = _extractLineOrOffsetSuffix(args);
  final combined = '$fileName$suffix';
  return _truncate40(combined);
}

String? _extractTerminalSummary(Map<String, JsonValue> args) {
  final cmd = _findArgString(args, const [
    'command',
    'cmd',
    'commands',
    'script',
    'code',
    'command_line',
    'commandline',
  ]);
  if (cmd == null) return null;
  final clean = _cleanSingleLine(cmd);
  if (clean.isEmpty) return null;
  return _truncate40(clean);
}

String? _extractSearchSummary(Map<String, JsonValue> args) {
  final pattern = _findArgString(args, const [
    'pattern',
    'query',
    'text',
    'keyword',
    'q',
  ]);
  final path = _findArgString(args, const [
    'file_path',
    'filepath',
    'path',
    'file',
    'filename',
    'directory',
    'dir',
    'search_directory',
    'search_path',
    'searchpath',
    'searchdirectory',
  ]);
  final cleanPattern = pattern != null ? _cleanSingleLine(pattern) : null;
  final cleanPath = path != null ? _extractFileName(path) : null;
  if (cleanPattern != null &&
      cleanPattern.isNotEmpty &&
      cleanPath != null &&
      cleanPath.isNotEmpty) {
    return _truncate40('$cleanPattern $cleanPath');
  } else if (cleanPattern != null && cleanPattern.isNotEmpty) {
    return _truncate40(cleanPattern);
  } else if (cleanPath != null && cleanPath.isNotEmpty) {
    return _truncate40(cleanPath);
  }
  return null;
}

String? _extractListSummary(Map<String, JsonValue> args) {
  final pattern = _findArgString(args, const [
    'pattern',
    'glob',
    'filter',
    'query',
  ]);
  final path = _findArgString(args, const [
    'file_path',
    'filepath',
    'path',
    'file',
    'filename',
    'directory',
    'dir',
    'directory_path',
    'directorypath',
    'search_directory',
  ]);
  final cleanPattern = pattern != null ? _cleanSingleLine(pattern) : null;
  final cleanPath = path != null ? _extractFileName(path) : null;
  if (cleanPattern != null &&
      cleanPattern.isNotEmpty &&
      cleanPath != null &&
      cleanPath.isNotEmpty) {
    return _truncate40('$cleanPattern $cleanPath');
  } else if (cleanPattern != null && cleanPattern.isNotEmpty) {
    return _truncate40(cleanPattern);
  } else if (cleanPath != null && cleanPath.isNotEmpty) {
    return _truncate40(cleanPath);
  }
  return null;
}

String? _extractTodoSummary(Map<String, JsonValue> args) {
  for (final entry in args.entries) {
    final lowerKey = entry.key.toLowerCase();
    if (lowerKey.contains('todo') ||
        lowerKey.contains('task') ||
        lowerKey.contains('title') ||
        lowerKey.contains('content')) {
      final val = _jsonValueToDisplayString(entry.value);
      if (val != null) {
        final clean = _cleanSingleLine(val);
        if (clean.isNotEmpty) {
          return _truncate40(clean);
        }
      }
    }
  }
  return null;
}

String _extractFileName(String path) {
  final normalized = path
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  if (normalized.isEmpty) return path.trim();
  final lastSlash = normalized.lastIndexOf('/');
  if (lastSlash >= 0 && lastSlash < normalized.length - 1) {
    return normalized.substring(lastSlash + 1);
  }
  return normalized;
}

String _extractLineOrOffsetSuffix(Map<String, JsonValue> args) {
  final startVal = _findArgString(args, const [
    'line_start',
    'linestart',
    'start_line',
    'startline',
    'start',
  ]);
  final endVal = _findArgString(args, const [
    'line_end',
    'lineend',
    'end_line',
    'endline',
    'end',
  ]);
  if (startVal != null && endVal != null) {
    return ':$startVal-$endVal';
  } else if (startVal != null) {
    return ':$startVal';
  } else if (endVal != null) {
    return ':$endVal';
  }

  final lineVal = _findArgString(args, const ['line', 'lines']);
  if (lineVal != null) {
    return ':$lineVal';
  }

  final offsetVal = _findArgString(args, const [
    'offset',
    'offset_start',
    'offsetstart',
  ]);
  if (offsetVal != null) {
    return ':$offsetVal';
  }

  final limitVal = _findArgString(args, const ['limit']);
  if (limitVal != null) {
    return ':$limitVal';
  }

  return '';
}

String? _findArgString(
  Map<String, JsonValue> args,
  List<String> candidateKeys,
) {
  for (final targetKey in candidateKeys) {
    final lowerTarget = targetKey.toLowerCase();
    for (final entry in args.entries) {
      if (entry.key.toLowerCase() == lowerTarget) {
        final str = _jsonValueToDisplayString(entry.value);
        if (str != null && str.trim().isNotEmpty) {
          return str.trim();
        }
      }
    }
  }
  return null;
}

String? _jsonValueToDisplayString(JsonValue? val) {
  if (val == null) return null;
  return switch (val) {
    JsonString(:final value) => value,
    JsonNumber(:final value) =>
      value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString(),
    JsonBool(:final value) => value ? 'true' : 'false',
    JsonNull() => null,
    JsonObject() => val.compactJsonString,
    JsonArray() => val.compactJsonString,
  };
}

String _cleanSingleLine(String text) {
  return text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
}

String _truncate40(String text) {
  return text.length > 40 ? text.substring(0, 40) : text;
}
