import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';

/// 孤儿兜底守卫：**没有 tools 断点 = 本轮没有任何工具事件**，"孤儿" 语义不成立。
///
/// 缺陷现象（主人真机报告）：
/// 「锁屏一段时间后，对话最下方就会出现一张 tools 调用特别多的卡；但这一轮
///  末尾其实根本没有工具调用，而且本轮实际只有几次工具调用。」
///
/// 根因（数据侧 + 渲染侧，本文件钉住渲染侧这一半）：
/// ① 数据侧：`_finishStream`（收尾统一入口）只清 `liveTimelinePoints` 与流身份，
///    不清 `liveToolCalls` / `liveReasoningText`；`_beginStream` 同样只清断点。
///    于是锁屏/后台静默断线等**异常收尾**路径留下的 live 工具跨轮累积；
/// ② 渲染侧：`orphanToolCount` 缺 `toolStarts.isNotEmpty` 守卫 —— 无工具断点时
///    `minToolStart` 停在初值 `toolCallsLength`，整堆 live 工具被误判成
///    「首个断点之前的孤儿」，在时间线**末尾** flush 成一张巨卡（seq:-1）。
///
/// 对称性依据：`orphanThink` 本来就有 `thinkStarts.isNotEmpty` 守卫（同文件），
/// 工具侧漏了这一条 —— 属实现不对称，不是设计取舍。
///
/// **RED 校验**：把守卫改回 `minToolStart > 0 ? minToolStart : 0`
/// → 用例 1 / 2 精确变红；用例 3 / 4（真孤儿与正常路径）仍绿。
void main() {
  ToolCall tool(String id) =>
      ToolCall(id: id, name: 'terminal', isCompleted: true);

  List<ToolCall> tools(int n, String prefix) =>
      List.generate(n, (i) => tool('$prefix$i'));

  LiveTimelinePoint text(int seq, int start) => LiveTimelinePoint(
    kind: LiveSegmentKind.text,
    start: start,
    sequence: seq,
    contentful: true,
  );

  LiveTimelinePoint toolsPoint(int seq, int start) =>
      LiveTimelinePoint(kind: LiveSegmentKind.tools, start: start, sequence: seq);

  LiveTimelinePoint think(int seq, int start) => LiveTimelinePoint(
    kind: LiveSegmentKind.thinking,
    start: start,
    sequence: seq,
  );

  List<LiveTimelineEntry> build({
    required List<LiveTimelinePoint> points,
    required List<ToolCall> liveToolCalls,
    String content = '本轮正文。',
    String reasoningText = '',
    bool toolCoalesce = true,
  }) => buildLiveTimelineEntries(
    streamingId: 'stream-1',
    content: content,
    reasoningText: reasoningText,
    points: points,
    liveToolCalls: liveToolCalls,
    hideReasoning: false,
    toolCoalesce: toolCoalesce,
    hasUnrevealedText: false,
  );

  int toolEntryCount(List<LiveTimelineEntry> entries) => entries
      .where((e) => e.kind == LiveSegmentKind.tools && e.toolGroup != null)
      .length;

  /// 真实工具行数（排除思考伪工具行 —— 思考按 #20 降级为工具卡子卡）。
  int realToolCount(List<LiveTimelineEntry> entries) => entries
      .where((e) => e.kind == LiveSegmentKind.tools && e.toolGroup != null)
      .expand((e) => e.toolGroup!.toolCalls)
      .where((c) => !c.isThinking)
      .length;

  List<ToolCall> thinkingRows(List<LiveTimelineEntry> entries) => [
    for (final e in entries)
      if (e.toolGroup != null)
        ...e.toolGroup!.toolCalls.where((c) => c.isThinking),
  ];

  int totalToolsInEntries(List<LiveTimelineEntry> entries) => entries
      .where((e) => e.kind == LiveSegmentKind.tools && e.toolGroup != null)
      .fold<int>(0, (sum, e) => sum + e.toolGroup!.toolCalls.length);

  group('孤儿堆守卫（无 tools 断点 ⇒ 不得整堆渲染）', () {
    test('本轮 0 工具事件 + 残留 liveToolCalls（62 个）→ 不得产出任何工具卡', () {
      // 本轮真实事件：思考 → 正文（服务端 run journal 实测 tool 事件数 = 0）。
      final entries = build(
        points: [think(1, 0), text(2, 0)],
        liveToolCalls: tools(62, 'residue'),
        reasoningText: '收尾核对。',
      );

      // 残留的 62 个真实工具一个都不许上屏。
      expect(
        realToolCount(entries),
        0,
        reason: '本轮没有任何 tools 断点 ⇒ 残留工具不得以孤儿名义整堆上屏',
      );
      expect(
        entries.any((e) => e.renderKey == 'live:tools:orphan'),
        isFalse,
        reason: '孤儿键不得出现（无工具断点 = 无孤儿）',
      );
      // 本轮的思考行（真实事件）照常渲染，走 thinking 断点。
      expect(thinkingRows(entries).length, 1);
    });

    test('无 thinking 断点 + 残留 liveReasoningText → 不得产出思考行（对称性）', () {
      final entries = build(
        points: [text(1, 0)],
        liveToolCalls: const [],
        reasoningText: '上一轮残留的思考，本轮没有 reasoning 事件。',
      );
      expect(toolEntryCount(entries), 0);
    });
  });

  group('孤儿兜底既有能力不得误伤', () {
    test('真孤儿（有 tools 断点且 start > 0）→ 断点前那一段仍作为孤儿整堆前置', () {
      // 重连/重锚场景：live 已有 3 个工具，但断点只从第 3 个开始
      // （前 2 个是「首个断点之前」的旧内容，必须保住，否则丢内容）。
      final entries = build(
        points: [toolsPoint(1, 2), text(2, 0)],
        liveToolCalls: tools(3, 't'),
        content: '恢复后的正文。',
      );
      expect(toolEntryCount(entries), 1);
      expect(totalToolsInEntries(entries), 3);
      expect(entries.last.kind, LiveSegmentKind.tools);
    });

    test('正常路径（tools 断点从 0 起）→ 无孤儿，工具按断点切片', () {
      final entries = build(
        points: [toolsPoint(1, 0), text(2, 0)],
        liveToolCalls: tools(4, 't'),
        content: '正文。',
      );
      expect(toolEntryCount(entries), 1);
      expect(totalToolsInEntries(entries), 4);
      // 孤儿键不得出现。
      expect(
        entries.any((e) => e.renderKey == 'live:tools:orphan'),
        isFalse,
      );
    });
  });
}
