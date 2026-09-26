import 'dart:convert';

import '../../core/models/chat_message.dart';
import '../../core/models/json_value.dart';
import '../../core/models/tool_call.dart';

/// live 时间线段落种类。
///
/// 按 SSE 事件到达顺序穿插：thinking（reasoning 段）/ text（token 段）/
/// tools（工具调用段）。controller 在事件到达时记录断点，渲染层按断点切片。
enum LiveSegmentKind { thinking, text, tools }

/// live 时间线断点：一次「段切换」发生时对应缓冲区的起始游标。
///
/// - [kind] == text     → [start] 为流式 assistant 消息 content 的字符偏移；
/// - [kind] == thinking → [start] 为 liveReasoningText 的字符偏移；
/// - [kind] == tools    → [start] 为 liveToolCalls 的下标。
/// [sequence] 单调递增，用于渲染 key（List 复用稳定）。
///
/// [contentful]：该断点建立时「到达的是内容性正文」（#147）。token 到达的那一刻
/// 文本就在手上，纯空白 token 不建点 ⇒ controller 建的 text 断点恒为 true。
/// 渲染层据此切卡，**与 reveal 进度无关**：内容性正文还没被打字机吐出来也照切。
/// 缺省 false = 兼容旧语义（按「已 reveal 的可见切片」判定，#62 的 hand-fed 断点）。
class LiveTimelinePoint {
  const LiveTimelinePoint({
    required this.kind,
    required this.start,
    required this.sequence,
    this.contentful = false,
  });

  final LiveSegmentKind kind;
  final int start;
  final int sequence;

  /// 见类文档：true = 该 text 断点由「内容性正文到达」建立。
  final bool contentful;

  @override
  bool operator ==(Object other) {
    return other is LiveTimelinePoint &&
        other.kind == kind &&
        other.start == start &&
        other.sequence == sequence &&
        other.contentful == contentful;
  }

  @override
  int get hashCode => Object.hash(kind, start, sequence, contentful);

  @override
  String toString() =>
      'LiveTimelinePoint(kind: $kind, start: $start, seq: $sequence, '
      'contentful: $contentful)';
}

/// live 时间线条目（[liveTimelineProvider] 输出，渲染层按 [kind] 分发 widget）。
class LiveTimelineEntry {
  const LiveTimelineEntry({
    required this.kind,
    required this.renderKey,
    this.textSlice = '',
    this.reasoningText = '',
    this.toolGroup,
  });

  final LiveSegmentKind kind;

  /// ListView 稳定 key（如 `live:text:3` / `live:think:merged`）。
  final String renderKey;

  /// kind==text：流式 assistant 消息 content 的切片（随流式增长）。
  final String textSlice;

  /// kind==thinking：展示用推理文本。
  final String reasoningText;

  /// kind==tools：本段的工具组（coalesce=true 时为整回合合并组）。
  final ToolCallGroup? toolGroup;
}

/// 展示层转录消息（chat_spec.md §6.2；只读派生，不存状态）。
class TranscriptMessage {
  const TranscriptMessage({
    required this.loadedIndex,
    required this.renderId,
    required this.anchorId,
    required this.message,
  });

  /// 在 messages 中的下标。
  final int loadedIndex;

  /// `transcript:<offset+loadedIndex>`（ListView key，必须稳定）。
  final String renderId;

  /// TranscriptTurnClassifier.anchorID。
  final String anchorId;

  final ChatMessage message;

  @override
  bool operator ==(Object other) {
    return other is TranscriptMessage &&
        other.loadedIndex == loadedIndex &&
        other.renderId == renderId &&
        other.anchorId == anchorId &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(loadedIndex, renderId, anchorId, message);
}

/// 已归档推理段（按 assistant turn 分组渲染折叠块）。
class ReasoningGroup {
  const ReasoningGroup({this.anchorMessageId, required this.text});

  final String? anchorMessageId;
  final String text;

  /// 从消息列表提取全部已归档推理段（按 assistant anchor 关联）。
  ///
  /// 口径：**只认 `role == 'assistant'` 消息上的 `reasoning`** —— role 门禁
  /// 排在 reasoning 读取之前，故挂在 user/tool 消息上的 reasoning 一律丢弃。
  /// 理由：reasoning 是 assistant 的输出属性；放宽到别的 role 反而可能把
  /// 注入内容当推理渲染出来。
  /// 对照：WebUI 的 `compression_anchor.py` 用「any non-tool role」的宽判据，
  /// 那是**压缩锚点**（判断消息有无内容）的需求，不是渲染口径。
  static List<ReasoningGroup> groups({
    required List<ChatMessage> messages,
    int? messageOffset,
  }) {
    final groups = <ReasoningGroup>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != 'assistant') continue;
      final text = message.reasoning?.trim();
      if (text == null || text.isEmpty) continue;
      final anchor = TranscriptTurnClassifier.anchorID(
        message,
        at: i,
        messageOffset: messageOffset,
      );
      groups.add(ReasoningGroup(anchorMessageId: anchor, text: text));
    }
    return groups;
  }

  /// 主推理组 + 兜底推理组按 anchorMessageId 合并。
  static List<ReasoningGroup> merging({
    required List<ReasoningGroup> primaryGroups,
    required List<ReasoningGroup> fallbackGroups,
  }) {
    final merged = List<ReasoningGroup>.from(primaryGroups);
    final groupIndexesByAnchor = <String, int>{};
    for (var i = 0; i < primaryGroups.length; i++) {
      final anchor = primaryGroups[i].anchorMessageId;
      if (anchor != null) groupIndexesByAnchor[anchor] = i;
    }

    for (final fallbackGroup in fallbackGroups) {
      final anchor = fallbackGroup.anchorMessageId;
      final groupIndex = anchor == null ? null : groupIndexesByAnchor[anchor];
      if (groupIndex == null) {
        if (anchor != null) {
          groupIndexesByAnchor[anchor] = merged.length;
        }
        merged.add(fallbackGroup);
        continue;
      }

      final existingGroup = merged[groupIndex];
      if (existingGroup.text.trim().isEmpty &&
          fallbackGroup.text.trim().isNotEmpty) {
        merged[groupIndex] = fallbackGroup;
      }
    }
    return merged;
  }

  @override
  bool operator ==(Object other) {
    return other is ReasoningGroup &&
        other.anchorMessageId == anchorMessageId &&
        other.text == text;
  }

  @override
  int get hashCode => Object.hash(anchorMessageId, text);

  @override
  String toString() =>
      'ReasoningGroup(anchorMessageId: $anchorMessageId, text: $text)';
}

// ---------------------------------------------------------------------------
// 工具调用展示格式化（chat_spec.md §3.5 ToolCallDisplayFormatter → Dart）
// ---------------------------------------------------------------------------

/// 工具调用卡片渲染内容的纯函数格式化器。
class ToolCallDisplayFormatter {
  const ToolCallDisplayFormatter._();

  /// 参数行：args（Map）按键名排序，值转显示文本。
  static String argumentsLine(ToolCall call) {
    final args = call.args;
    if (args == null || args.isEmpty) return '';
    final keys = args.keys.toList()..sort();
    return keys.map((key) => '$key: ${toolDisplayText(args[key])}').join('\n');
  }

  /// 单值显示文本：对象 → 缩进树；数组 → "- " 列表；字符串 → 换行归一化。
  static String toolDisplayText(JsonValue? value) {
    if (value == null) return '';
    return switch (value) {
      JsonNull() => 'null',
      JsonBool(:final value) => '$value',
      JsonNumber(:final value) => _formatNumber(value),
      JsonString(:final value) => _normalizeNewlines(value),
      JsonArray(:final value) =>
        value.map((e) => '- ${toolDisplayText(e)}').join('\n'),
      JsonObject(:final value) => _objectTree(value),
    };
  }

  static String _objectTree(Map<String, JsonValue> object) {
    final buffer = StringBuffer();
    final keys = object.keys.toList()..sort();
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final child = toolDisplayText(object[key]);
      final childLines = child.split('\n');
      buffer.write('$key: ${childLines.first}');
      for (final line in childLines.skip(1)) {
        buffer.write('\n  $line');
      }
      if (i != keys.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String _normalizeNewlines(String value) =>
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // -------------------------------------------------------------------------
  // 结果（preview）格式化：JSON 解析 → 终端信封 → 可读值 → JSON 树
  // -------------------------------------------------------------------------

  /// 终端工具名集合。
  static const terminalToolNames = {
    'terminal',
    'shell',
    'bash',
    'zsh',
    'command',
    'exec',
    'cmd',
    'powershell',
  };

  /// 结果展示（preview 非空才渲染；空 → ''）。
  static String resultText(ToolCall call, {bool monospaced = false}) {
    final preview = call.preview;
    if (preview == null || preview.trim().isEmpty) return '';

    // 1) 尝试把 preview 当 JSON 解析（含去转义、嵌套解包最多 3 层）。
    final parsed = _tryParseJsonTree(preview);
    if (parsed != null) {
      if (_isTerminalEnvelope(call, parsed)) {
        return _terminalEnvelopeText(parsed);
      }
      final readable = _firstReadableValue(parsed);
      if (readable != null) return readable;
      if (parsed is Map<String, Object?>) {
        return _jsonTreeText(parsed);
      }
      return _scalarText(parsed);
    }

    // 2) 非 JSON：原样展示（等宽由调用方按换行判定）。
    return _normalizeNewlines(preview);
  }

  /// 等宽字体条件：terminal 工具 或 文本含换行 或 由 JSON 解析得出。
  static bool usesMonospace(ToolCall call, {required String resultText}) {
    if (terminalToolNames.contains((call.name ?? '').trim().toLowerCase())) {
      return true;
    }
    if (resultText.contains('\n')) return true;
    return _tryParseJsonTree(call.preview ?? '') != null;
  }

  /// 终端信封格式（output/stdout 优先、接 stderr、Error、非 0 exit_code）。
  /// [parsed] 非 Map（如 terminal 工具名的裸字符串 preview）时按原样返回。
  static String _terminalEnvelopeText(Object? parsed) {
    if (parsed is! Map<String, Object?>) {
      return _scalarText(parsed);
    }
    final object = parsed;
    final buffer = StringBuffer();
    final stdout = _firstNonEmptyString(object, const ['output', 'stdout']);
    final stderr = _firstNonEmptyString(object, const ['stderr']);
    final error = _firstNonEmptyString(object, const ['error']);
    final exitCode = _intField(object, const ['exit_code', 'exitCode']);
    if (stdout != null) buffer.write(stdout);
    if (stderr != null && stderr.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(stderr);
    }
    if (error != null && error.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('Error: $error');
    }
    if (exitCode != null && exitCode != 0) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('Exit code: $exitCode');
    }
    return buffer.toString();
  }

  /// 终端信封判定：terminal 工具名 或 对象含 output/stdout/stderr/exit_code/
  /// exitCode/error 键。
  static bool _isTerminalEnvelope(ToolCall call, Object? parsed) {
    final name = (call.name ?? '').trim().toLowerCase();
    if (terminalToolNames.contains(name)) return true;
    if (parsed is Map<String, Object?>) {
      const keys = {
        'output',
        'stdout',
        'stderr',
        'exit_code',
        'exitCode',
        'error',
      };
      return parsed.keys.any(keys.contains);
    }
    return false;
  }

  /// 可读值：result/results/preview/content/text/message/summary/data/items
  /// 顺序取第一个可读值；再试 error；都没有 → null。
  static String? _firstReadableValue(Object? parsed) {
    if (parsed is Map<String, Object?>) {
      const keys = [
        'result',
        'results',
        'preview',
        'content',
        'text',
        'message',
        'summary',
        'data',
        'items',
      ];
      for (final key in keys) {
        final value = parsed[key];
        if (value == null) continue;
        if (value is String && value.trim().isNotEmpty) {
          return _normalizeNewlines(value);
        }
        if (value is num || value is bool) return _scalarText(value);
      }
      final error = parsed['error'];
      if (error is String && error.trim().isNotEmpty) {
        return 'Error: ${_normalizeNewlines(error)}';
      }
    }
    return null;
  }

  /// 对象 JSON 树文本。
  static String _jsonTreeText(Map<String, Object?> object) {
    final buffer = StringBuffer();
    final keys = object.keys.toList()..sort();
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final value = object[key];
      final line = _scalarText(value);
      final lines = line.split('\n');
      buffer.write('$key: ${lines.first}');
      for (final rest in lines.skip(1)) {
        buffer.write('\n  $rest');
      }
      if (i != keys.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  static String _scalarText(Object? value) {
    if (value == null) return 'null';
    if (value is String) return _normalizeNewlines(value);
    if (value is num) return _formatNumber(value.toDouble());
    if (value is bool) return '$value';
    if (value is Map) return jsonEncode(value);
    if (value is List) {
      return value.map(_scalarText).map((e) => '- $e').join('\n');
    }
    return value.toString();
  }

  static String? _firstNonEmptyString(
    Map<String, Object?> object,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = object[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static int? _intField(Map<String, Object?> object, List<String> keys) {
    for (final key in keys) {
      final value = object[key];
      if (value is int) return value;
      if (value is double) return value.truncate();
      if (value is String) return int.tryParse(value.trim());
    }
    return null;
  }

  /// 尝试把 preview 当 JSON 解析（含去转义、嵌套解包最多 3 层）。
  /// 解析成功返回解包后的值；失败返回 null。
  static Object? _tryParseJsonTree(String preview) {
    var candidate = preview.trim();
    for (var depth = 0; depth < 3; depth++) {
      final decoded = _decodeJson(candidate);
      if (decoded == null) return null;
      // 嵌套解包：JSON 字符串里再包 JSON → 继续解。
      if (decoded is String) {
        final inner = decoded.trim();
        final again = _decodeJson(inner);
        if (again == null) return decoded;
        candidate = inner;
        continue;
      }
      return decoded;
    }
    return _decodeJson(candidate);
  }

  static Object? _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}

/// 工具调用展示内容（名称行 + 参数行 + 结果文本 + 等宽判定）。
class ToolCallDisplayContent {
  const ToolCallDisplayContent({
    required this.arguments,
    required this.result,
    required this.monospaced,
  });

  final String arguments;
  final String result;
  final bool monospaced;

  factory ToolCallDisplayContent.of(ToolCall call) {
    final arguments = ToolCallDisplayFormatter.argumentsLine(call);
    final result = ToolCallDisplayFormatter.resultText(call);
    final monospaced = ToolCallDisplayFormatter.usesMonospace(
      call,
      resultText: result,
    );
    return ToolCallDisplayContent(
      arguments: arguments,
      result: result,
      monospaced: monospaced,
    );
  }
}

// ---------------------------------------------------------------------------
// live 时间线构建（纯函数：断点 → 展示条目；供 liveTimelineProvider 调用）
// ---------------------------------------------------------------------------

/// 断点缺失/异常时的单段兜底：思考 → 正文 → 工具，各成一段（内容不丢）。
List<LiveTimelineEntry> fallbackLiveTimelineEntries({
  required String streamingId,
  required String content,
  required String reasoningText,
  required List<ToolCall> liveToolCalls,
  required bool hideReasoning,
  required bool toolCoalesce,
}) {
  final entries = <LiveTimelineEntry>[];
  // 思考子卡行并入工具条目（think 行前置，时间线一致）。
  final calls = <ToolCall>[
    if (!hideReasoning && reasoningText.trim().isNotEmpty)
      ToolCall.thinking(reasoningText.trim()),
    ...liveToolCalls,
  ];
  if (calls.isNotEmpty) {
    entries.add(
      LiveTimelineEntry(
        kind: LiveSegmentKind.tools,
        renderKey: 'live:tools:fallback',
        toolGroup: ToolCallGroup(
          id: 'live-timeline-tools-fallback',
          anchorMessageID: streamingId,
          toolCalls: toolCoalesce ? calls : [for (final call in calls) call],
        ),
      ),
    );
  }
  if (content.trim().isNotEmpty) {
    entries.add(
      LiveTimelineEntry(
        kind: LiveSegmentKind.text,
        renderKey: 'live:text:fallback',
        textSlice: content,
      ),
    );
  }
  return entries;
}

/// 按事件断点把流式缓冲切成 think/text/tools 穿插的展示条目。
///
/// 断点顺序即事件时间线；正文（text）是唯一分隔符：聚合关闭（
/// [toolCoalesce] == false）时按 text 区段切卡，聚合开启时整回合一张。
///
/// **段列表与断点列表必须一一对应（空段占位）**：断点记的是「缓冲全量」
/// 长度，而 [content] 是已 reveal 的部分，中间态会出现 `start >= end` 的空段
/// （或 diff-merge 吸收后 content 变短被 clamp 成零长）。若把空段从列表里
/// 丢掉，后续段就会与前一个断点错配 —— 有内容的段被提前 flush，表现为
/// 「相邻工具卡不该切却切了（变成多张 tools）」+ 正文提前错位渲染。
///
/// **正文前沿闸门（打字机水位）**：[hasUnrevealedText] 表示「已到达但尚未被
/// 打字机揭示」的正文仍存在。只要某段正文还没吐完，它在时间线上**之后**的
/// 条目（工具/思考）一律挂起不产出 —— 否则卡会抢跑占位，未揭示的正文随后
/// 才补进卡与卡之间的缝隙，表现为「凭空插入 + 向下推挤」（主人现象：打字机
/// 还在打 text1，tools2/tools3 已经就位，text2 事后插进两张卡之间）。
///
/// 闸门只推迟**展示时机**，绝不改动卡片数量与分组 —— #147 的核心不变量
/// （边界按事件真相切，不得因 reveal 滞后并成一张大卡）保持原样。
/// 非末段终点 = 下一个 text 断点起点（精确）；末段终点不可知，由
/// [hasUnrevealedText] 表达。挂起是单调的：一旦某段未吐完，其后条目必然也在
/// 未揭示正文之后，故无需回退判断。
List<LiveTimelineEntry> buildLiveTimelineEntries({
  required String streamingId,
  required String content,
  required String reasoningText,
  required List<LiveTimelinePoint> points,
  required List<ToolCall> liveToolCalls,
  required bool hideReasoning,
  required bool toolCoalesce,
  required bool hasUnrevealedText,
}) {
  try {
    // 按 kind 分组切片边界。
    final textStarts = <int>[];
    final thinkStarts = <int>[];
    final toolStarts = <int>[];
    for (final point in points) {
      switch (point.kind) {
        case LiveSegmentKind.text:
          textStarts.add(point.start);
        case LiveSegmentKind.thinking:
          thinkStarts.add(point.start);
        case LiveSegmentKind.tools:
          toolStarts.add(point.start);
      }
    }

    final textSegments = <({int start, int end})>[];
    for (var i = 0; i < textStarts.length; i++) {
      // 断点含 pending 缓冲长度，中间态可能超过已 flush 的 content 长度，
      // 两侧 clamp 保证切片安全（内容随后续 reveal 增长补齐）。
      final rawEnd = i + 1 < textStarts.length
          ? textStarts[i + 1]
          : content.length;
      final start = textStarts[i].clamp(0, content.length);
      final end = rawEnd.clamp(start, content.length);
      // 空段也入列（占位对齐），渲染端跳过。
      textSegments.add((start: start, end: end));
    }
    final thinkSegments = <String>[];
    for (var i = 0; i < thinkStarts.length; i++) {
      final rawEnd = i + 1 < thinkStarts.length
          ? thinkStarts[i + 1]
          : reasoningText.length;
      final start = thinkStarts[i].clamp(0, reasoningText.length);
      final end = rawEnd.clamp(start, reasoningText.length);
      // 空思考段入列（占位对齐），渲染端不产生子行。
      thinkSegments.add(
        end > start ? reasoningText.substring(start, end).trim() : '',
      );
    }
    final toolSegments = <List<ToolCall>>[];
    final toolCallsLength = liveToolCalls.length;
    for (var i = 0; i < toolStarts.length; i++) {
      final start = toolStarts[i].clamp(0, toolCallsLength);
      final rawEnd = i + 1 < toolStarts.length
          ? toolStarts[i + 1]
          : toolCallsLength;
      final end = rawEnd.clamp(start, toolCallsLength);
      // 空工具段入列空列表（占位对齐）。
      toolSegments.add(
        end > start ? liveToolCalls.sublist(start, end) : const <ToolCall>[],
      );
    }

    final entries = <LiveTimelineEntry>[];
    // 混合行缓冲：思考子卡行与工具行按断点序统一累积，flush 时合并为一
    // 张工具卡（思考为卡内子行，行序即事件时间线）。toolCoalesce=true
    // 整回合一张（仅末尾 flush）；false 按 text 区段拆分（text 断点 flush）。
    final pendingCallBlock = <({int seq, ToolCall call})>[];
    // 重连/重锚定场景：首个断点前的内容无断点覆盖（如恢复时锚定到一条
    // 已有内容的 assistant 消息），作为「孤儿段」前置，保证旧内容不丢失。
    // 孤儿前缀以「全部段起点的最小值」为准，不能用首个断点的 start：
    // 断点回退/虚高（缓冲含未 reveal 内容）时首个 start 会被 clamp 到
    // content 末尾，用它取前缀会把整段正文当成孤儿重复渲染一次。
    var minTextStart = content.length;
    for (final start in textStarts) {
      final clamped = start.clamp(0, content.length);
      if (clamped < minTextStart) minTextStart = clamped;
    }
    var minThinkStart = reasoningText.length;
    for (final start in thinkStarts) {
      final clamped = start.clamp(0, reasoningText.length);
      if (clamped < minThinkStart) minThinkStart = clamped;
    }
    var minToolStart = toolCallsLength;
    for (final start in toolStarts) {
      final clamped = start.clamp(0, toolCallsLength);
      if (clamped < minToolStart) minToolStart = clamped;
    }
    final orphanText =
        textStarts.isNotEmpty && minTextStart > 0 && content.isNotEmpty
        ? content.substring(0, minTextStart)
        : null;
    final orphanThink =
        thinkStarts.isNotEmpty && minThinkStart > 0 && reasoningText.isNotEmpty
        ? reasoningText.substring(0, minThinkStart).trim()
        : null;
    final orphanToolCount = minToolStart > 0 ? minToolStart : 0;
    if (orphanText != null && orphanText.trim().isNotEmpty) {
      entries.add(
        LiveTimelineEntry(
          kind: LiveSegmentKind.text,
          renderKey: 'live:text:orphan',
          textSlice: orphanText,
        ),
      );
    }
    if (orphanThink != null && orphanThink.isNotEmpty && !hideReasoning) {
      pendingCallBlock.add((seq: -1, call: ToolCall.thinking(orphanThink)));
    }
    if (orphanToolCount > 0 && orphanToolCount <= toolCallsLength) {
      for (final call in liveToolCalls.sublist(0, orphanToolCount)) {
        pendingCallBlock.add((seq: -1, call: call));
      }
    }

    var textIndex = 0;
    var thinkIndex = 0;
    var toolIndex = 0;
    // 正文前沿闸门：true = 打字机还没吐完当前正文段，其后的条目一律挂起。
    var blocked = false;

    void flushBlock() {
      if (pendingCallBlock.isEmpty) return;
      final firstSeq = pendingCallBlock.first.seq;
      final renderKey = firstSeq < 0
          ? 'live:tools:orphan'
          : (toolCoalesce ? 'live:tools:merged' : 'live:tools:$firstSeq');
      entries.add(
        LiveTimelineEntry(
          kind: LiveSegmentKind.tools,
          renderKey: renderKey,
          toolGroup: ToolCallGroup(
            id: 'live-timeline-tools-${firstSeq < 0 ? 'orphan' : '$firstSeq'}',
            anchorMessageID: streamingId,
            toolCalls: [for (final e in pendingCallBlock) e.call],
          ),
        ),
      );
      pendingCallBlock.clear();
    }

    for (final point in points) {
      switch (point.kind) {
        case LiveSegmentKind.text:
          // 关闭聚合：text 断点分区块（思考行/工具行随区段合并）。
          //
          // 切卡判据（#62 + #147）：
          // ① 断点由「内容性正文到达」建立（`contentful`，事件时刻记录）→ 一定是
          //    分隔符，**即便这段字此刻还没被打字机吐出来**（后台冻结 / 回前台重放
          //    补课 / 打字机滞后都不改变卡片边界）；
          // ② 或该段已有可见正文（旧语义，#62 的纯函数契约与 hand-fed 断点兼容）。
          // 唯独「到达空段占位」（断点被 clamp 成零长、无正文到达）不切卡 —— 它
          // 只是段列表的占位，不是事件真相。
          final segment = textIndex < textSegments.length
              ? textSegments[textIndex]
              : null;
          final segStart = segment == null
              ? 0
              : segment.start.clamp(0, content.length);
          final segEnd = segment == null
              ? 0
              : segment.end.clamp(segStart, content.length);
          final segText = segEnd > segStart
              ? content.substring(segStart, segEnd)
              : '';
          final hasVisibleText = segText.trim().isNotEmpty;
          // 前沿推进：本段是否已被打字机吐完。非末段用下一个 text 断点起点
          // 精确判定；末段终点不可知，只能由 hasUnrevealedText 表达。
          final nextRawStart = textIndex + 1 < textStarts.length
              ? textStarts[textIndex + 1]
              : null;
          final rawEnd =
              nextRawStart ??
              (hasUnrevealedText ? content.length + 1 : content.length);
          blocked = content.length < rawEnd;
          if (!toolCoalesce && (point.contentful || hasVisibleText)) {
            flushBlock();
          }
          // 未 reveal（空/半截）时不建条目：文字随打字机随后填入该槽位。
          if (hasVisibleText) {
            entries.add(
              LiveTimelineEntry(
                kind: LiveSegmentKind.text,
                renderKey: 'live:text:${point.sequence}',
                textSlice: segText,
              ),
            );
          }
          textIndex++;
        case LiveSegmentKind.thinking:
          // 思考降级为工具卡子卡行：并入混合块（时间线与工具行混排）。
          // 占位用的空思考段不产生子行（避免空卡片）。
          final thinkText = thinkIndex < thinkSegments.length
              ? thinkSegments[thinkIndex]
              : '';
          if (!blocked && !hideReasoning && thinkText.isNotEmpty) {
            pendingCallBlock.add((
              seq: point.sequence,
              call: ToolCall.thinking(thinkText),
            ));
          }
          thinkIndex++;
        case LiveSegmentKind.tools:
          // 挂起时不累积，但 toolIndex 必须照常推进 —— 段与断点一一对应，
          // 漏递增会让后续段整段错配（#62 踩过的坑）。
          if (!blocked && toolIndex < toolSegments.length) {
            for (final call in toolSegments[toolIndex]) {
              pendingCallBlock.add((seq: point.sequence, call: call));
            }
          }
          toolIndex++;
      }
    }
    // 挂起中不 flush：末尾累积的条目同样位于未揭示正文之后，交下一次重建放行。
    if (!blocked) flushBlock();
    return entries;
  } catch (_) {
    // 顶层异常兜底：降级为单段呈现，确保不抛出到 Widget build 造成黑屏。
    return fallbackLiveTimelineEntries(
      streamingId: streamingId,
      content: content,
      reasoningText: reasoningText,
      liveToolCalls: liveToolCalls,
      hideReasoning: hideReasoning,
      toolCoalesce: toolCoalesce,
    );
  }
}
