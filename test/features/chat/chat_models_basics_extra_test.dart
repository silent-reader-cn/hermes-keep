import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';

/// `lib/features/chat/chat_models.dart` 第 11–104 行四个声明补测。
///
/// 覆盖：
/// - `LiveSegmentKind`（11）：全部取值 / 声明顺序 / `index` / `name` /
///   `toString`，以及**字符串→枚举的未知名回退语义**（本声明不含解析器，
///   `byName` 遇未知名抛 `ArgumentError`，`asNameMap` 落空为 null）；
/// - `LiveTimelinePoint`（19）：三个必填参数落位、const 规范化、
///   内联 `==` 的逐字段阶梯差异、`hashCode`、`toString`（注意形参名
///   `sequence` 在输出里写作 `seq`）；
/// - `LiveTimelineEntry`（47）：必填 / 可选参数与默认值，以及**未重写**
///   `==` / `hashCode` / `toString` 带来的默认身份语义（读实现得出，非猜测）；
/// - `TranscriptMessage`（72）：四个必填参数落位、`==` 逐字段阶梯差异、
///   `hashCode`、内层 `ChatMessage` 值比较，以及**未重写** `toString`。
///
/// 口径说明：本区间的四个声明都是纯数据持有者 —— **没有** `fromJson` /
/// `toJson`（它们不参与 JSON 解码），也**没有**派生 getter 与排序 / 去重逻辑
/// （排序由 `chat_controller` 侧的 `sequence` 单调计数器产生）。因此任务书
/// §3 里「fromJson 各分支 / 派生 getter / 时间线顺序合并」在本批无可测对象，
/// 已按实况改为对字段语义、枚举回退与值相等等价语义的精确断言。
///
/// 预期值全部按实现读出来写死。`ReasoningGroup`（105 行起）、
/// `ToolCallDisplayFormatter`（360 行起）、`ToolCallDisplayContent`（618 行起）
/// 不在本批范围。
void main() {
  // ---------------------------------------------------------------------------
  // 构造辅助：用「非编译期常量」的参数构造，避免 const 规范化把两次调用折成
  // 同一实例（那会让「同值不同实例」的断言失去意义），同时不触发
  // prefer_const_constructors。
  // ---------------------------------------------------------------------------

  LiveTimelinePoint point({
    LiveSegmentKind kind = LiveSegmentKind.text,
    int start = 4,
    int sequence = 9,
    bool contentful = false,
  }) => LiveTimelinePoint(
    kind: kind,
    start: start,
    sequence: sequence,
    contentful: contentful,
  );

  LiveTimelineEntry entry({
    LiveSegmentKind kind = LiveSegmentKind.text,
    String renderKey = 'live:text:1',
    String textSlice = '',
    String reasoningText = '',
    ToolCallGroup? toolGroup,
  }) => LiveTimelineEntry(
    kind: kind,
    renderKey: renderKey,
    textSlice: textSlice,
    reasoningText: reasoningText,
    toolGroup: toolGroup,
  );

  ChatMessage chatMessage({
    String role = 'assistant',
    String content = '正文',
    String? messageId = 'm1',
    double? timestamp = 10.0,
  }) => ChatMessage(
    role: role,
    content: content,
    messageId: messageId,
    timestamp: timestamp,
  );

  TranscriptMessage transcript({
    int loadedIndex = 2,
    String renderId = 'transcript:2',
    String anchorId = 'raw:msg-1',
    ChatMessage? message,
  }) => TranscriptMessage(
    loadedIndex: loadedIndex,
    renderId: renderId,
    anchorId: anchorId,
    message: message ?? chatMessage(),
  );

  group('LiveSegmentKind 枚举', () {
    test('全部取值与声明顺序：thinking → text → tools', () {
      expect(LiveSegmentKind.values, hasLength(3));
      expect(LiveSegmentKind.values, <LiveSegmentKind>[
        LiveSegmentKind.thinking,
        LiveSegmentKind.text,
        LiveSegmentKind.tools,
      ]);
    });

    test('index 与声明顺序严格一致', () {
      expect(LiveSegmentKind.thinking.index, 0);
      expect(LiveSegmentKind.text.index, 1);
      expect(LiveSegmentKind.tools.index, 2);
      expect(LiveSegmentKind.values.indexOf(LiveSegmentKind.thinking), 0);
      expect(LiveSegmentKind.values.indexOf(LiveSegmentKind.text), 1);
      expect(LiveSegmentKind.values.indexOf(LiveSegmentKind.tools), 2);
      // index 与下标一一对应（index 是稳定序列化序）
      for (var i = 0; i < LiveSegmentKind.values.length; i++) {
        expect(LiveSegmentKind.values[i].index, i);
      }
    });

    test('name 即源码字面量', () {
      expect(LiveSegmentKind.thinking.name, 'thinking');
      expect(LiveSegmentKind.text.name, 'text');
      expect(LiveSegmentKind.tools.name, 'tools');
      expect(LiveSegmentKind.values.map((kind) => kind.name), <String>[
        'thinking',
        'text',
        'tools',
      ]);
    });

    test('toString 为「枚举名.取值名」；渲染 key 依赖 name 拼接', () {
      expect(LiveSegmentKind.thinking.toString(), 'LiveSegmentKind.thinking');
      expect(LiveSegmentKind.text.toString(), 'LiveSegmentKind.text');
      expect(LiveSegmentKind.tools.toString(), 'LiveSegmentKind.tools');
      // 渲染层 key 形态 `live:text:<seq>`，name 参与拼接
      expect('live:${LiveSegmentKind.text.name}:3', 'live:text:3');
      expect('live:${LiveSegmentKind.tools.name}:0', 'live:tools:0');
    });

    test('未知值回退：本声明不含解析器，byName 遇未知名抛 ArgumentError', () {
      // 取值名大小写敏感：近似写法一律不命中。
      expect(
        () => LiveSegmentKind.values.byName('reasoning'),
        throwsArgumentError,
      );
      expect(() => LiveSegmentKind.values.byName('Text'), throwsArgumentError);
      expect(() => LiveSegmentKind.values.byName('TOOLS'), throwsArgumentError);
      expect(() => LiveSegmentKind.values.byName(''), throwsArgumentError);
      expect(
        () => LiveSegmentKind.values.byName('thinking '),
        throwsArgumentError,
      );
      // 已知名不抛，且往返一致。
      expect(
        LiveSegmentKind.values.byName('thinking'),
        LiveSegmentKind.thinking,
      );
      expect(LiveSegmentKind.values.byName('text'), LiveSegmentKind.text);
      expect(LiveSegmentKind.values.byName('tools'), LiveSegmentKind.tools);
    });

    test('asNameMap：已知名命中、未知名与近似写法落空为 null', () {
      final byName = LiveSegmentKind.values.asNameMap();
      expect(byName, hasLength(3));
      expect(byName['thinking'], LiveSegmentKind.thinking);
      expect(byName['text'], LiveSegmentKind.text);
      expect(byName['tools'], LiveSegmentKind.tools);
      expect(byName['Text'], isNull);
      expect(byName['reasoning'], isNull);
      expect(byName[''], isNull);
    });

    test('（名 → 枚举 → 名）往返稳定', () {
      for (final kind in LiveSegmentKind.values) {
        expect(LiveSegmentKind.values.byName(kind.name), kind);
        expect(LiveSegmentKind.values.asNameMap()[kind.name], kind);
      }
    });

    test('三个取值互不相等，switch 穷举三分支', () {
      String describe(LiveSegmentKind kind) => switch (kind) {
        LiveSegmentKind.thinking => 'think',
        LiveSegmentKind.text => 'text',
        LiveSegmentKind.tools => 'tools',
      };

      expect(describe(LiveSegmentKind.thinking), 'think');
      expect(describe(LiveSegmentKind.text), 'text');
      expect(describe(LiveSegmentKind.tools), 'tools');

      expect(LiveSegmentKind.thinking == LiveSegmentKind.text, isFalse);
      expect(LiveSegmentKind.text == LiveSegmentKind.tools, isFalse);
      expect(LiveSegmentKind.tools == LiveSegmentKind.thinking, isFalse);
      expect(LiveSegmentKind.text == LiveSegmentKind.text, isTrue);
      expect(identical(LiveSegmentKind.text, LiveSegmentKind.text), isTrue);
      expect(LiveSegmentKind.tools.hashCode, LiveSegmentKind.tools.hashCode);
    });
  });

  group('LiveTimelinePoint 构造', () {
    test('三个必填参数逐项落位', () {
      final p = point(kind: LiveSegmentKind.tools, start: 12, sequence: 7);

      expect(p.kind, LiveSegmentKind.tools);
      expect(p.start, 12);
      expect(p.sequence, 7);
    });

    test('每个 kind 取值都能承载（text / thinking / tools）', () {
      expect(point(kind: LiveSegmentKind.text).kind, LiveSegmentKind.text);
      expect(
        point(kind: LiveSegmentKind.thinking).kind,
        LiveSegmentKind.thinking,
      );
      expect(point(kind: LiveSegmentKind.tools).kind, LiveSegmentKind.tools);
    });

    test('数值参数不设边界：0 与负数原样保留', () {
      expect(point(start: 0, sequence: 0).start, 0);
      expect(point(start: 0, sequence: 0).sequence, 0);
      expect(point(start: -1).start, -1);
      expect(point(sequence: -5).sequence, -5);
      expect(point(start: 1 << 40).start, 1 << 40);
    });

    test('const 构造可用；同一常量字面量被规范化成同一实例', () {
      const a = LiveTimelinePoint(
        kind: LiveSegmentKind.thinking,
        start: 0,
        sequence: 1,
      );
      const b = LiveTimelinePoint(
        kind: LiveSegmentKind.thinking,
        start: 0,
        sequence: 1,
      );

      expect(identical(a, b), isTrue);
      expect(a, equals(b));
      expect(a == b, isTrue);
    });
  });

  group('LiveTimelinePoint == / hashCode / toString', () {
    test('同值不同实例：== 为 true 且 hashCode 相同', () {
      final a = point();
      final b = point();

      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == a, isTrue);
    });

    test('const 实例与运行时重建实例：== 与 hashCode 一致', () {
      const constPoint = LiveTimelinePoint(
        kind: LiveSegmentKind.text,
        start: 4,
        sequence: 9,
      );

      expect(constPoint == point(), isTrue);
      expect(point() == constPoint, isTrue);
      expect(constPoint.hashCode, point().hashCode);
    });

    test('逐字段阶梯式差异：任一字段不同即 !=（覆盖 && 每一行比较）', () {
      final base = point();

      // kind 差异
      expect(base == point(kind: LiveSegmentKind.thinking), isFalse);
      expect(base == point(kind: LiveSegmentKind.tools), isFalse);
      // start 差异
      expect(base == point(start: 5), isFalse);
      expect(base == point(start: 0), isFalse);
      // sequence 差异
      expect(base == point(sequence: 10), isFalse);
      expect(base == point(sequence: 0), isFalse);
      // contentful 差异（#147：内容性正文标记参与等值判定）
      expect(base == point(contentful: true), isFalse);
      expect(point(contentful: true) == base, isFalse);
      // 反向（让每个字段都作为「入参侧」参与比较）
      expect(point(start: 5) == base, isFalse);
      expect(point(sequence: 10) == base, isFalse);
    });

    test('与非本类实例比较为 false', () {
      final base = point();
      final Object otherType = point().kind;
      final Object plain = <int>[1, 2];

      expect(base == otherType, isFalse);
      expect(base == plain, isFalse);
      expect(base == Object(), isFalse);
    });

    test('toString：固定格式（形参 sequence 在输出里写作 seq）', () {
      expect(
        point().toString(),
        'LiveTimelinePoint(kind: LiveSegmentKind.text, start: 4, seq: 9, '
        'contentful: false)',
      );
      expect(
        point(kind: LiveSegmentKind.thinking, start: 0, sequence: 0).toString(),
        'LiveTimelinePoint(kind: LiveSegmentKind.thinking, start: 0, seq: 0, '
        'contentful: false)',
      );
      expect(
        point(
          kind: LiveSegmentKind.tools,
          start: -1,
          sequence: 42,
          contentful: true,
        ).toString(),
        'LiveTimelinePoint(kind: LiveSegmentKind.tools, start: -1, seq: 42, '
        'contentful: true)',
      );
      // kind 段渲染的是枚举 toString 而非 name
      expect(point().toString(), contains('LiveSegmentKind.text'));
      expect(point().toString(), isNot(contains('kind: text')));
    });
  });

  group('LiveTimelineEntry 构造', () {
    test('必填 kind / renderKey 落位；可选字段默认空串与 null', () {
      final e = entry();

      expect(e.kind, LiveSegmentKind.text);
      expect(e.renderKey, 'live:text:1');
      expect(e.textSlice, '');
      expect(e.reasoningText, '');
      expect(e.toolGroup, isNull);
    });

    test('全部可选字段显式赋值', () {
      final group = ToolCallGroup(
        id: 'g1',
        anchorMessageID: 'raw:a',
        precedingMessageID: 'raw:a',
        isAboveContent: true,
        toolCalls: [ToolCall(id: 't1', name: 'read_file', isCompleted: true)],
      );
      final e = entry(
        kind: LiveSegmentKind.tools,
        renderKey: 'live:tools:2',
        textSlice: 'slice',
        reasoningText: 'think',
        toolGroup: group,
      );

      expect(e.kind, LiveSegmentKind.tools);
      expect(e.renderKey, 'live:tools:2');
      expect(e.textSlice, 'slice');
      expect(e.reasoningText, 'think');
      expect(e.toolGroup, same(group));
    });

    test('三种 kind 的典型载荷：text 用 textSlice、thinking 用 reasoningText', () {
      final textEntry = entry(
        kind: LiveSegmentKind.text,
        renderKey: 'live:text:3',
        textSlice: '流式正文',
      );
      expect(textEntry.kind, LiveSegmentKind.text);
      expect(textEntry.textSlice, '流式正文');
      expect(textEntry.reasoningText, '');
      expect(textEntry.toolGroup, isNull);

      final thinkEntry = entry(
        kind: LiveSegmentKind.thinking,
        renderKey: 'live:think:merged',
        reasoningText: '推理文本',
      );
      expect(thinkEntry.kind, LiveSegmentKind.thinking);
      expect(thinkEntry.reasoningText, '推理文本');
      expect(thinkEntry.textSlice, '');
      expect(thinkEntry.toolGroup, isNull);
    });

    test('空 renderKey 与空载荷不被拦截（渲染层自行判空）', () {
      final e = entry(renderKey: '', textSlice: '', reasoningText: '');

      expect(e.renderKey, '');
      expect(e.textSlice, '');
      expect(e.reasoningText, '');
    });

    test('toolGroup 为可变引用：同一底层实例被多条目共享', () {
      final group = ToolCallGroup(
        id: 'g',
        toolCalls: [ToolCall(id: 'a')],
      );
      final first = entry(kind: LiveSegmentKind.tools, toolGroup: group);
      final second = entry(
        kind: LiveSegmentKind.tools,
        renderKey: 'live:tools:4',
        toolGroup: group,
      );

      expect(first.toolGroup, same(group));
      expect(second.toolGroup, same(group));
      expect(identical(first.toolGroup, second.toolGroup), isTrue);
      expect(first.toolGroup!.toolCalls, hasLength(1));
    });
  });

  group('LiveTimelineEntry 未重写 == / hashCode / toString（默认身份语义）', () {
    test('同值不同实例仍不相等（无值相等语义）', () {
      final a = entry();
      final b = entry();

      expect(identical(a, b), isFalse);
      expect(a == b, isFalse);
      expect(b == a, isFalse);
      expect(a == a, isTrue);
      expect(a == Object(), isFalse);
    });

    test('逐项相同的完整载荷也不相等（含 toolGroup 同引用）', () {
      final group = ToolCallGroup(
        id: 'g',
        toolCalls: [ToolCall(id: 'a')],
      );
      final a = entry(
        kind: LiveSegmentKind.tools,
        renderKey: 'live:tools:1',
        textSlice: 's',
        reasoningText: 'r',
        toolGroup: group,
      );
      final b = entry(
        kind: LiveSegmentKind.tools,
        renderKey: 'live:tools:1',
        textSlice: 's',
        reasoningText: 'r',
        toolGroup: group,
      );

      expect(a == b, isFalse);
      expect(a == a, isTrue);
    });

    test('const 规范化：同一常量字面量是同一实例，故 == 为 true', () {
      const a = LiveTimelineEntry(
        kind: LiveSegmentKind.tools,
        renderKey: 'live:tools:1',
      );
      const b = LiveTimelineEntry(
        kind: LiveSegmentKind.tools,
        renderKey: 'live:tools:1',
      );

      expect(identical(a, b), isTrue);
      expect(a == b, isTrue);
    });

    test('toString 未重写：输出为默认的 Instance of 形态', () {
      expect(entry().toString(), 'Instance of \'LiveTimelineEntry\'');
      expect(
        entry(kind: LiveSegmentKind.tools, renderKey: 'k').toString(),
        'Instance of \'LiveTimelineEntry\'',
      );
      // 不复述任何字段，故与值无关
      expect(
        entry(textSlice: 'x').toString(),
        entry(textSlice: 'y').toString(),
      );
    });
  });

  group('TranscriptMessage 构造', () {
    test('四个必填参数逐项落位', () {
      final message = chatMessage(messageId: 'm9', content: 'hi');
      final t = TranscriptMessage(
        loadedIndex: 5,
        renderId: 'transcript:5',
        anchorId: 'raw:m9',
        message: message,
      );

      expect(t.loadedIndex, 5);
      expect(t.renderId, 'transcript:5');
      expect(t.anchorId, 'raw:m9');
      expect(t.message, same(message));
      expect(t.message.messageId, 'm9');
    });

    test('loadedIndex 不设边界：0 与负数（分页偏移前的下标）原样保留', () {
      expect(transcript(loadedIndex: 0).loadedIndex, 0);
      expect(transcript(loadedIndex: -1).loadedIndex, -1);
      expect(transcript(renderId: '').renderId, '');
      expect(transcript(anchorId: '').anchorId, '');
    });

    test('message 为必填的 ChatMessage（非空、可为任意 role）', () {
      final user = transcript(
        message: chatMessage(role: 'user', content: 'q'),
      );
      final assistant = transcript(
        message: chatMessage(role: 'assistant', content: 'a'),
      );

      expect(user.message.role, 'user');
      expect(user.message.content, 'q');
      expect(assistant.message.role, 'assistant');
      expect(assistant.message.content, 'a');
    });
  });

  group('TranscriptMessage == / hashCode / toString', () {
    test('同值不同实例：== 为 true 且 hashCode 相同', () {
      final a = transcript();
      final b = transcript();

      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == a, isTrue);
    });

    test('内层 message 按 ChatMessage.== 做值比较（同引用与等值实例均成立）', () {
      final shared = chatMessage(content: 'same');
      final a = transcript(message: shared);
      final b = transcript(message: shared);
      final c = transcript(message: chatMessage(content: 'same'));

      expect(identical(a.message, b.message), isTrue);
      expect(a, equals(b));
      expect(identical(a.message, c.message), isFalse);
      expect(a == c, isTrue);
      expect(a.hashCode, c.hashCode);
    });

    test('逐字段阶梯式差异：任一字段不同即 !=（覆盖 && 每一行比较）', () {
      final base = transcript();

      // loadedIndex 差异
      expect(base == transcript(loadedIndex: 3), isFalse);
      expect(base == transcript(loadedIndex: 1), isFalse);
      // renderId 差异
      expect(base == transcript(renderId: 'transcript:3'), isFalse);
      // anchorId 差异
      expect(base == transcript(anchorId: 'raw:msg-2'), isFalse);
      // message 差异（内容）
      expect(base == transcript(message: chatMessage(content: '别的')), isFalse);
      // message 差异（role）
      expect(base == transcript(message: chatMessage(role: 'user')), isFalse);
      // message 差异（messageId）
      expect(
        base == transcript(message: chatMessage(messageId: 'm2')),
        isFalse,
      );
      // message 差异（null ↔ 非 null）
      expect(
        base == transcript(message: chatMessage(messageId: null)),
        isFalse,
      );
      // 反向：入参侧参与比较
      expect(transcript(loadedIndex: 3) == base, isFalse);
    });

    test('与非本类实例比较为 false', () {
      final base = transcript();
      final Object otherType = base.message;
      final Object plain = <int>[1];

      expect(base == otherType, isFalse);
      expect(base == plain, isFalse);
      expect(base == Object(), isFalse);
    });

    test('toString 未重写：输出为默认的 Instance of 形态', () {
      expect(transcript().toString(), 'Instance of \'TranscriptMessage\'');
      expect(
        transcript(loadedIndex: 99, renderId: 'r').toString(),
        'Instance of \'TranscriptMessage\'',
      );
    });
  });
}
