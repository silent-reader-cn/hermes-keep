import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import 'json_value.dart';
import 'message_attachment.dart';

/// 聊天消息（Swift: ChatMessage.swift）。
class ChatMessage {
  const ChatMessage({
    this.role,
    this.content,
    this.timestamp,
    this.messageId,
    this.name,
    this.toolCallId,
    this.toolUseId,
    this.toolCalls,
    this.contentParts,
    this.reasoning,
    this.attachments,
    this.turnTps,
  });

  /// 容错解码。content 可为字符串 / 内容部件数组 / 任意 JSONValue；
  /// attachments 走两级兜底（快路径整数组 → 慢路径 JSONValue 逐项），
  /// 坏元素丢弃不拖垮整体。
  factory ChatMessage.fromJson(Map<String, Object?> json) {
    final role = lossyString(json, 'role');
    final decodedContent = _decodeContentTolerantly(json);
    var content = decodedContent.text;
    final timestamp = firstKey(json, ['_ts', 'timestamp'], lossyDouble);
    final messageId = lossyString(json, 'message_id');
    final name = lossyString(json, 'name');
    final toolCallId = lossyString(json, 'tool_call_id');
    final toolUseId = lossyString(json, 'tool_use_id');
    final toolCalls = optJsonValueList(json, 'tool_calls');
    var reasoning =
        firstKey(json, [
          'reasoning',
          'reasoning_content',
          'reasoning_text',
          'thought',
          'thinking',
        ], lossyString) ??
        _reasoningFromParts(decodedContent.parts);
    if (reasoning == null && role == 'assistant' && content != null) {
      final extracted = _extractThinkingTag(content);
      if (extracted.reasoning != null) {
        reasoning = extracted.reasoning;
        content = extracted.content;
      }
    }
    final turnTps = lossyDouble(json, '_turnTps');
    final decodedAttachments = _decodeAttachmentsTolerantly(json);
    return ChatMessage(
      role: role,
      content: content,
      timestamp: timestamp,
      messageId: messageId,
      name: name,
      toolCallId: toolCallId,
      toolUseId: toolUseId,
      toolCalls: toolCalls,
      contentParts: decodedContent.parts,
      reasoning: reasoning,
      attachments: _enrichAttachments(decodedAttachments, content),
      turnTps: turnTps,
    );
  }

  final String? role;
  final String? content;
  final double? timestamp;
  final String? messageId;
  final String? name;
  final String? toolCallId;
  final String? toolUseId;
  final List<JsonValue>? toolCalls;

  /// 由 content 解码派生（content 为内容部件数组时保留原数组）。
  final List<JsonValue>? contentParts;
  final String? reasoning;
  final List<MessageAttachment>? attachments;
  final double? turnTps;

  /// Identifiable：`messageId ?? '$role-$timestamp-$content'`。
  String get id => messageId ?? '$role-${timestamp ?? 0}-${content ?? ''}';

  /// 浅拷贝（流式追加 / 回合收尾时「原地替换」消息用，其余字段透传）。
  ChatMessage copyWith({
    String? role,
    String? content,
    double? timestamp,
    String? messageId,
    String? name,
    String? toolCallId,
    String? toolUseId,
    List<JsonValue>? toolCalls,
    List<JsonValue>? contentParts,
    String? reasoning,
    List<MessageAttachment>? attachments,
    double? turnTps,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      messageId: messageId ?? this.messageId,
      name: name ?? this.name,
      toolCallId: toolCallId ?? this.toolCallId,
      toolUseId: toolUseId ?? this.toolUseId,
      toolCalls: toolCalls ?? this.toolCalls,
      contentParts: contentParts ?? this.contentParts,
      reasoning: reasoning ?? this.reasoning,
      attachments: attachments ?? this.attachments,
      turnTps: turnTps ?? this.turnTps,
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (timestamp != null) '_ts': timestamp,
      if (messageId != null) 'message_id': messageId,
      if (name != null) 'name': name,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (toolUseId != null) 'tool_use_id': toolUseId,
      if (toolCalls != null)
        'tool_calls': toolCalls!.map((e) => e.toJson()).toList(),
      if (contentParts != null)
        'content': contentParts!.map((e) => e.toJson()).toList(),
      if (reasoning != null) 'reasoning': reasoning,
      if (attachments != null)
        'attachments': attachments!.map((e) => e.toJson()).toList(),
      if (turnTps != null) '_turnTps': turnTps,
    };
  }

  /// content 容错解码（对应 Swift `decodeContentTolerantly`）。
  static ({String? text, List<JsonValue>? parts}) _decodeContentTolerantly(
    Map<String, Object?> json,
  ) {
    final asString = lossyString(json, 'content');
    if (asString != null) return (text: asString, parts: null);

    final value = JsonValue.fromJson(json['content']);
    if (value is JsonArray) {
      return (text: _textContentFromParts(value.value), parts: value.value);
    }
    if (value is JsonNull) {
      return (text: null, parts: null);
    }
    return (text: value.compactJsonString, parts: null);
  }

  static String? _textContentFromParts(List<JsonValue> parts) {
    final text = parts
        .map((part) {
          if (part is JsonString) return part.value;
          if (part is JsonObject) {
            final type = part.value['type']?.stringValue;
            if (type == 'text') {
              return part.value['text']?.stringValue;
            }
          }
          return null;
        })
        .whereType<String>()
        .join()
        .trim();
    return text.isEmpty ? null : text;
  }

  static String? _reasoningFromParts(List<JsonValue>? parts) {
    if (parts == null || parts.isEmpty) return null;
    final text = parts
        .map((part) {
          if (part is JsonObject) {
            final type = part.value['type']?.stringValue?.toLowerCase();
            if (type == 'thinking' ||
                type == 'thought' ||
                type == 'reasoning') {
              return part.value['thinking']?.stringValue ??
                  part.value['thought']?.stringValue ??
                  part.value['text']?.stringValue ??
                  part.value['content']?.stringValue;
            }
          }
          return null;
        })
        .whereType<String>()
        .join('\n')
        .trim();
    return text.isEmpty ? null : text;
  }

  static ({String? content, String? reasoning}) _extractThinkingTag(
    String text,
  ) {
    final match = RegExp(
      r'<(?:thinking|thought)>([\s\S]*?)</(?:thinking|thought)>',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final thinking = match.group(1)?.trim();
      final clean = text.replaceRange(match.start, match.end, '').trim();
      return (
        content: clean.isEmpty ? null : clean,
        reasoning: (thinking != null && thinking.isNotEmpty) ? thinking : null,
      );
    }
    return (content: text, reasoning: null);
  }

  /// attachments 容错解码（对应 Swift `decodeAttachmentsTolerantly`）。
  static List<MessageAttachment>? _decodeAttachmentsTolerantly(
    Map<String, Object?> json,
  ) {
    final raw = json['attachments'];
    if (raw is! List) return null;

    // 快路径：整数组直接逐项解码（元素为字符串或对象时 MessageAttachment
    // 自身即容错），坏形状元素触发慢路径。
    var fastOk = true;
    final fast = <MessageAttachment>[];
    for (final element in raw) {
      if (element is String || element is Map) {
        fast.add(MessageAttachment.fromJson(element));
      } else {
        fastOk = false;
        break;
      }
    }
    if (fastOk) return fast;

    // 慢路径：整个数组先解为 List<JsonValue>，逐项 JsonValue.fromJson →
    // 该项是 object/string 则再递归 MessageAttachment.fromJson，坏项丢弃。
    final slow = <MessageAttachment>[];
    for (final element in raw) {
      final value = JsonValue.fromJson(element);
      if (value is JsonObject || value is JsonString) {
        final attachment = MessageAttachment.fromJson(value.toJson());
        slow.add(attachment);
      }
    }
    return slow.isEmpty ? null : slow;
  }

  /// attachments 与 `[Attached files: …]` 标记合并（对应 Swift
  /// `attachments(_:enrichedByMarkerIn:)`）。
  static List<MessageAttachment>? _enrichAttachments(
    List<MessageAttachment>? decoded,
    String? content,
  ) {
    final inferred = MessageAttachment.inferredFromAttachedFilesMarker(content);
    if (decoded == null || decoded.isEmpty) return inferred;
    if (inferred == null || inferred.isEmpty) return decoded;

    final available = List<MessageAttachment>.from(inferred);
    final availableOffsets = List<int>.generate(inferred.length, (i) => i);
    final result = <MessageAttachment>[];

    for (var index = 0; index < decoded.length; index++) {
      final attachment = decoded[index];
      if (_nonEmptyString(attachment.path) != null) {
        result.add(attachment);
        continue;
      }

      var matchedIndex = -1;
      final key = attachment.identityKey;
      if (key != null) {
        for (var j = 0; j < available.length; j++) {
          if (available[j].identityKey == key) {
            matchedIndex = j;
            break;
          }
        }
      }
      if (matchedIndex == -1) {
        for (var j = 0; j < availableOffsets.length; j++) {
          if (availableOffsets[j] == index) {
            matchedIndex = j;
            break;
          }
        }
      }
      if (matchedIndex == -1) {
        result.add(attachment);
        continue;
      }

      final inferredMatch = available.removeAt(matchedIndex);
      availableOffsets.removeAt(matchedIndex);
      result.add(
        MessageAttachment(
          name: _nonEmptyString(attachment.name) ?? inferredMatch.name,
          path: _nonEmptyString(inferredMatch.path),
          mime: attachment.mime ?? inferredMatch.mime,
          size: attachment.size ?? inferredMatch.size,
          isImage: attachment.isImage ?? inferredMatch.isImage,
        ),
      );
    }
    return result;
  }

  static String? _nonEmptyString(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  bool operator ==(Object other) {
    return other is ChatMessage &&
        other.role == role &&
        other.content == content &&
        other.timestamp == timestamp &&
        other.messageId == messageId &&
        other.name == name &&
        other.toolCallId == toolCallId &&
        other.toolUseId == toolUseId &&
        deepEquals(other.toolCalls, toolCalls) &&
        deepEquals(other.contentParts, contentParts) &&
        other.reasoning == reasoning &&
        deepEquals(other.attachments, attachments) &&
        other.turnTps == turnTps;
  }

  @override
  int get hashCode {
    return Object.hash(
      role,
      content,
      timestamp,
      messageId,
      name,
      toolCallId,
      toolUseId,
      deepHash(toolCalls),
      deepHash(contentParts),
      reasoning,
      deepHash(attachments),
      turnTps,
    );
  }

  @override
  String toString() {
    return 'ChatMessage(role: $role, content: $content, '
        'timestamp: $timestamp, messageId: $messageId, '
        'attachments: ${attachments?.length})';
  }
}

/// 转录回合分类器（Swift `TranscriptTurnClassifier`）。纯客户端逻辑，无 JSON。
class TranscriptTurnClassifier {
  const TranscriptTurnClassifier._();

  static String anchorID(
    ChatMessage message, {
    required int at,
    int? messageOffset,
  }) {
    final messageId = _nonEmpty(message.messageId);
    if (messageId != null &&
        !messageId.startsWith('stream-') &&
        !messageId.startsWith('local-') &&
        messageId != 'unanchored') {
      return messageId;
    }
    final offset = messageOffset ?? 0;
    return 'raw:${(offset < 0 ? 0 : offset) + at}';
  }

  /// user 且有可见内容或附件 → 用户回合边界。
  /// 工具结果消息（携带 `tool_call_id` / `tool_use_id`）不是回合边界：
  /// 否则同回合的连续工具调用会被切成多个 turnKey，聚合时无法合并。
  static bool isUserTurnBoundary(ChatMessage message) {
    if (message.role != 'user') return false;
    if (_nonEmpty(message.toolCallId) != null ||
        _nonEmpty(message.toolUseId) != null) {
      return false;
    }
    return _hasVisibleUserContent(message);
  }

  static bool isToolResultOnlyMessage(ChatMessage message) {
    return message.role == 'user' && !_hasVisibleUserContent(message);
  }

  /// assistant 消息 anchorID → 所属回合 key。
  static Map<String, String> assistantTurnKeysByAnchorID(
    List<ChatMessage> messages, {
    int? messageOffset,
  }) {
    final keysByMessageID = <String, String>{};
    var currentTurnKey = 'turn:start';
    for (var messageIndex = 0; messageIndex < messages.length; messageIndex++) {
      final message = messages[messageIndex];
      if (isUserTurnBoundary(message)) {
        currentTurnKey = 'turn:user:${(messageOffset ?? 0) + messageIndex}';
      }
      if (message.role == 'assistant') {
        keysByMessageID[anchorID(
              message,
              at: messageIndex,
              messageOffset: messageOffset,
            )] =
            currentTurnKey;
      }
    }
    return keysByMessageID;
  }

  static Map<String, String> assistantTurnKeysByMessageID(
    List<ChatMessage> messages,
  ) {
    return assistantTurnKeysByAnchorID(messages);
  }

  /// 为原始索引定位其所属 assistant 回合的 anchorID。
  static String? assistantAnchorID(
    int rawIndex,
    List<ChatMessage> messages, {
    int? messageOffset,
  }) {
    if (rawIndex < 0 || rawIndex >= messages.length) return null;

    if (messages[rawIndex].role == 'assistant') {
      return anchorID(
        messages[rawIndex],
        at: rawIndex,
        messageOffset: messageOffset,
      );
    }

    final previous = _previousUserBoundaryIndex(rawIndex, messages);
    final lowerBound = previous == null ? 0 : previous + 1;
    if (rawIndex > lowerBound) {
      for (var index = rawIndex - 1; index >= lowerBound; index--) {
        if (messages[index].role == 'assistant') {
          return anchorID(
            messages[index],
            at: index,
            messageOffset: messageOffset,
          );
        }
      }
    }

    final next = _nextUserBoundaryIndex(rawIndex, messages);
    final upperBound = next ?? messages.length;
    if (rawIndex + 1 < upperBound) {
      for (var index = rawIndex + 1; index < upperBound; index++) {
        if (messages[index].role == 'assistant') {
          return anchorID(
            messages[index],
            at: index,
            messageOffset: messageOffset,
          );
        }
      }
    }

    return null;
  }

  /// 当前回合（最后一个用户边界之后）的全部 assistant anchorID。
  static List<String> currentTurnAssistantAnchorIDs(
    List<ChatMessage> messages, {
    int? messageOffset,
  }) {
    var latestUserIndex = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (isUserTurnBoundary(messages[i])) {
        latestUserIndex = i;
        break;
      }
    }
    final startIndex = latestUserIndex == -1 ? 0 : latestUserIndex + 1;
    if (startIndex >= messages.length) return const [];

    final result = <String>[];
    for (var i = startIndex; i < messages.length; i++) {
      if (messages[i].role == 'assistant') {
        result.add(anchorID(messages[i], at: i, messageOffset: messageOffset));
      }
    }
    return result;
  }

  static List<String> currentTurnAssistantMessageIDs(
    List<ChatMessage> messages,
  ) {
    return currentTurnAssistantAnchorIDs(messages);
  }

  static int? _previousUserBoundaryIndex(
    int rawIndex,
    List<ChatMessage> messages,
  ) {
    if (rawIndex <= 0) return null;
    for (var index = rawIndex - 1; index >= 0; index--) {
      if (isUserTurnBoundary(messages[index])) return index;
    }
    return null;
  }

  static int? _nextUserBoundaryIndex(int rawIndex, List<ChatMessage> messages) {
    for (var index = rawIndex + 1; index < messages.length; index++) {
      if (isUserTurnBoundary(messages[index])) return index;
    }
    return null;
  }

  static bool _hasVisibleUserContent(ChatMessage message) {
    if (message.role != 'user') return false;
    if (message.content?.trim().isNotEmpty == true) return true;
    return message.attachments?.isNotEmpty == true;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
