import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';

/// live 时间线「段列表 ↔ 断点列表」必须一一对应（空段占位）。
///
/// 回归背景：断点记的是「缓冲全量」长度，而切片用的是已 reveal 的 content。
/// 打字机未落地 / diff-merge 吸收后 content 变短时会出现 `start >= end` 的
/// 空段；旧实现把空段从列表里丢掉，后续段就与前一个断点错配 —— 有内容的段
/// 被提前 flush，表现为「相邻工具卡不该切却切了（变成多张 tools）」+ 正文
/// 提前错位渲染（主人：#116 live 多张相邻 tool 卡不合成一张 tools）。
void main() {
  ToolCall tool(String id) =>
      ToolCall(id: id, name: 'terminal', isCompleted: true);

  test('空 text 段占位：相邻工具块仍合成一张卡，正文不错位', () {
    const content = 'B';
    final points = [
      const LiveTimelinePoint(
        kind: LiveSegmentKind.tools,
        start: 0,
        sequence: 1,
      ),
      // 断点 start=5 超过 content 长度（缓冲含未 reveal 内容 / 内容回退）
      // → 该段被 clamp 成零长空段。
      const LiveTimelinePoint(
        kind: LiveSegmentKind.text,
        start: 5,
        sequence: 2,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.tools,
        start: 1,
        sequence: 3,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.text,
        start: 0,
        sequence: 4,
      ),
    ];

    final entries = buildLiveTimelineEntries(
      streamingId: 'stream-1',
      content: content,
      reasoningText: '',
      points: points,
      liveToolCalls: [tool('t1'), tool('t2')],
      hideReasoning: false,
      toolCoalesce: false,
    );

    final cards = entries
        .where((e) => e.kind == LiveSegmentKind.tools)
        .toList();
    final texts = entries
        .where((e) => e.kind == LiveSegmentKind.text)
        .map((e) => e.textSlice)
        .toList();

    expect(
      cards.length,
      1,
      reason: '空 text 段不得把相邻工具块切成两张卡',
    );
    expect(cards.single.toolGroup!.toolCalls.map((c) => c.id).toList(), [
      't1',
      't2',
    ], reason: '工具行顺序 = 事件时间线');
    expect(texts, ['B'], reason: '正文只渲染一次且不得提前错位');
  });

  test('可见正文仍是分隔符：前后工具块各自成卡', () {
    final points = [
      const LiveTimelinePoint(
        kind: LiveSegmentKind.tools,
        start: 0,
        sequence: 1,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.text,
        start: 0,
        sequence: 2,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.tools,
        start: 1,
        sequence: 3,
      ),
    ];

    final entries = buildLiveTimelineEntries(
      streamingId: 'stream-1',
      content: '正文',
      reasoningText: '',
      points: points,
      liveToolCalls: [tool('t1'), tool('t2')],
      hideReasoning: false,
      toolCoalesce: false,
    );

    expect(
      entries.where((e) => e.kind == LiveSegmentKind.tools).length,
      2,
      reason: '正文两侧的工具块应各成一张卡（穿插呈现）',
    );
  });

  test('纯空白段不算分隔符：相邻工具块仍合成一张', () {
    final points = [
      const LiveTimelinePoint(
        kind: LiveSegmentKind.tools,
        start: 0,
        sequence: 1,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.text,
        start: 0,
        sequence: 2,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.tools,
        start: 1,
        sequence: 3,
      ),
    ];

    final entries = buildLiveTimelineEntries(
      streamingId: 'stream-1',
      content: '   ',
      reasoningText: '',
      points: points,
      liveToolCalls: [tool('t1'), tool('t2')],
      hideReasoning: false,
      toolCoalesce: false,
    );

    expect(entries.where((e) => e.kind == LiveSegmentKind.tools).length, 1);
    expect(entries.where((e) => e.kind == LiveSegmentKind.text).length, 0);
  });

  test('聚合开启：整回合一张卡，且空思考段不产生空子行', () {
    final points = [
      const LiveTimelinePoint(
        kind: LiveSegmentKind.thinking,
        start: 0,
        sequence: 1,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.tools,
        start: 0,
        sequence: 2,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.thinking,
        start: 9, // 超出 reasoning 长度 → 空思考段
        sequence: 3,
      ),
      const LiveTimelinePoint(
        kind: LiveSegmentKind.tools,
        start: 1,
        sequence: 4,
      ),
    ];

    final entries = buildLiveTimelineEntries(
      streamingId: 'stream-1',
      content: '',
      reasoningText: '想一下',
      points: points,
      liveToolCalls: [tool('t1'), tool('t2')],
      hideReasoning: false,
      toolCoalesce: true,
    );

    final cards = entries
        .where((e) => e.kind == LiveSegmentKind.tools)
        .toList();
    expect(cards.length, 1);
    final calls = cards.single.toolGroup!.toolCalls;
    expect(calls.where((c) => c.isThinking).length, 1, reason: '空思考段不产子行');
    expect(calls.where((c) => !c.isThinking).map((c) => c.id).toList(), [
      't1',
      't2',
    ]);
  });
}