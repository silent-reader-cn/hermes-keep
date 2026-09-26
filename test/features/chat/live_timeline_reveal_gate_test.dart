import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';

/// #162 正文前沿闸门（打字机水位）：未揭示的正文**之后**的工具/思考条目
/// 必须挂起展示，直到打字机把该段吐完。
///
/// 修复的现象（主人报告）：网络突发一次性到达 `tools1 text1 tools2 text2 tools3`
/// 时，三张工具卡当场抢跑就位，而正文还在逐字揭示 —— 于是 text1 事后插进
/// 「卡1 / 卡2」之间的缝隙、text2 插进「卡2 / 卡3」之间，每次插入都把后面的卡
/// 往下推，观感突兀（凭空出现 + 布局跳动）。
///
/// 本文件在**纯函数层**钉住闸门语义（不依赖时序），端到端行为由
/// `live_timeline_reveal_lag_split_test.dart` 覆盖。
///
/// 铁律：闸门只改**展示时机**，绝不改卡片数量与分组 —— #147 的「边界按事件
/// 真相切、不得并成一张大卡」不受影响。
void main() {
  ToolCall tool(String id) => ToolCall(id: id, name: 'terminal', isCompleted: true);

  LiveTimelinePoint text(int seq, int start) => LiveTimelinePoint(
    kind: LiveSegmentKind.text,
    start: start,
    sequence: seq,
    contentful: true,
  );

  LiveTimelinePoint tools(int seq, int start) =>
      LiveTimelinePoint(kind: LiveSegmentKind.tools, start: start, sequence: seq);

  LiveTimelinePoint think(int seq, int start) => LiveTimelinePoint(
    kind: LiveSegmentKind.thinking,
    start: start,
    sequence: seq,
  );

  group('#162 正文前沿闸门', () {
    test('主人场景：正文未吐完 → 其后工具卡全挂起；前沿推进则逐段放行', () {
      // 时间线：tools1 · text1 · tools2 · text2 · tools3
      //          卡1在正文之前（应立即放行），卡2/卡3在未揭示正文之后（应挂起）
      final points = [
        tools(1, 0),
        text(2, 0), // text1 段 = content[0,3)
        tools(3, 1),
        text(4, 3), // text2 段 = content[3,6)
        tools(5, 2),
      ];
      final calls = [tool('t1'), tool('t2'), tool('t3')];

      List<LiveTimelineEntry> run(String content, bool pending) =>
          buildLiveTimelineEntries(
            streamingId: 'stream-1',
            content: content,
            reasoningText: '',
            points: points,
            liveToolCalls: calls,
            hideReasoning: false,
            toolCoalesce: false,
            hasUnrevealedText: pending,
          );

      // ① 突发刚到达：正文一个字都没吐，但卡1在它之前 ⇒ 卡1可见，卡2/卡3挂起。
      expect(
        _shape(run('', true)),
        'T[t1]',
        reason: '卡2/卡3 不得抢跑占位（这正是「突兀」的根源）',
      );

      // ② 打字机吐完 text1（3 字）⇒ 卡2 放行，卡3 仍挂起（text2 未吐）。
      expect(
        _shape(run('AAA', true)),
        'T[t1] | X[AAA] | T[t2]',
        reason: '前沿推进一段，就放行一段（逐段揭示，无推挤）',
      );

      // ③ 打字机吐完 text2 ⇒ 卡3 放行。边界与 #147 完全一致：仍是三张卡。
      expect(
        _shape(run('AAAAAA', false)),
        'T[t1] | X[AAA] | T[t2] | X[AAA] | T[t3]',
        reason: '全部放行后不并卡、不丢卡，顺序 = 事件时间线',
      );
    });

    test('挂起不得让段游标错配（工具归属与张数仍按断点切）', () {
      // 挂起期跳过的 tools 点，其 toolIndex 必须照常推进 —— 否则放行后
      // 后续段会整段错配（#62 踩过的坑：相邻工具块归属错乱）。
      final points = [
        tools(1, 0),
        text(2, 0),
        tools(3, 1),
        tools(4, 2),
      ];
      final calls = [tool('t1'), tool('t2'), tool('t3')];

      List<LiveTimelineEntry> run(String content, bool pending) =>
          buildLiveTimelineEntries(
            streamingId: 'stream-1',
            content: content,
            reasoningText: '',
            points: points,
            liveToolCalls: calls,
            hideReasoning: false,
            toolCoalesce: false,
            hasUnrevealedText: pending,
          );

      expect(_shape(run('', true)), 'T[t1]', reason: '正文未吐 ⇒ 其后工具挂起');

      expect(
        _shape(run('XY', false)),
        'T[t1] | X[XY] | T[t2,t3]',
        reason: '放行后：第 2/3 个工具点连续且无正文打断 ⇒ 合成一张卡，且不含 t1',
      );
    });

    test('正文之前的卡立即放行，不被误伤', () {
      final points = [tools(1, 0), text(2, 0), tools(3, 1)];

      final entries = buildLiveTimelineEntries(
        streamingId: 'stream-1',
        content: '',
        reasoningText: '',
        points: points,
        liveToolCalls: [tool('t1'), tool('t2')],
        hideReasoning: false,
        toolCoalesce: false,
        hasUnrevealedText: true,
      );

      expect(
        _shape(entries),
        'T[t1]',
        reason: '首个工具块位于未揭示正文之前 ⇒ 照常显示；仅其后条目挂起',
      );
    });

    test('末段判据 = hasUnrevealedText（末段终点不可知）', () {
      final points = [text(1, 0), tools(2, 0)];

      List<LiveTimelineEntry> run(bool pending) => buildLiveTimelineEntries(
        streamingId: 'stream-1',
        content: 'abc',
        reasoningText: '',
        points: points,
        liveToolCalls: [tool('t1')],
        hideReasoning: false,
        toolCoalesce: false,
        hasUnrevealedText: pending,
      );

      expect(
        _shape(run(true)),
        'X[abc]',
        reason: '末段仍有待揭示正文 ⇒ 其后工具挂起（即便此刻已吐出 3 字）',
      );
      expect(
        _shape(run(false)),
        'X[abc] | T[t1]',
        reason: '打字机追平 ⇒ 立即放行',
      );
    });

    test('思考子卡同样受前沿门控（与工具行同一时间线）', () {
      final points = [text(1, 0), think(2, 0), tools(3, 0)];

      List<LiveTimelineEntry> run(String content, bool pending) =>
          buildLiveTimelineEntries(
            streamingId: 'stream-1',
            content: content,
            reasoningText: '想了',
            points: points,
            liveToolCalls: [tool('t1')],
            hideReasoning: false,
            toolCoalesce: false,
            hasUnrevealedText: pending,
          );

      expect(_shape(run('', true)), '', reason: '正文未吐 ⇒ 思考行与工具行一并挂起');
      expect(
        _shape(run('AB', false)),
        'X[AB] | T[t1|think1]',
        reason: '追平后思考作为工具卡子行呈现（think 行序 = 时间线）',
      );
    });

    test('聚合开启：整回合一张卡，同样受前沿门控', () {
      final points = [tools(1, 0), text(2, 0), tools(3, 1)];

      List<LiveTimelineEntry> run(String content, bool pending) =>
          buildLiveTimelineEntries(
            streamingId: 'stream-1',
            content: content,
            reasoningText: '',
            points: points,
            liveToolCalls: [tool('t1'), tool('t2')],
            hideReasoning: false,
            toolCoalesce: true,
            hasUnrevealedText: pending,
          );

      expect(_shape(run('', true)), '', reason: '正文未吐 ⇒ 整回合那张卡也挂起');
      expect(
        _shape(run('AB', false)),
        'X[AB] | T[t1,t2]',
        reason: '追平后整回合一张卡（聚合语义不变）',
      );
    });
  });
}

/// 形状描述：`T[...]` = 工具卡（`|thinkN` 标注思考子行数，逗号分隔工具 id）；
/// `X[...]` = 正文段。
String _shape(List<LiveTimelineEntry> entries) {
  return entries.map((e) {
    if (e.kind != LiveSegmentKind.tools) return 'X[${e.textSlice}]';
    final calls = e.toolGroup?.toolCalls ?? const <ToolCall>[];
    final thinkCount = calls.where((c) => c.isThinking).length;
    final ids = calls.where((c) => !c.isThinking).map((c) => c.id).join(',');
    return 'T[$ids${thinkCount > 0 ? '|think$thinkCount' : ''}]';
  }).join(' | ');
}
