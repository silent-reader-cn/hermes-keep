import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

/// `tool_call.dart` 覆盖率补强 · 批次 TC2：`withThinkingRows`（354）+
/// `merging`（560），目标区间 354–643。
///
/// 覆盖：思考行插入的区间归属（354 的文本切分模型）/ 卡位与方向字段 /
/// 无正文回合分支 / hideThinking 两态 / 幂等性 / `merging` 的 anchor key
/// 命中与指纹兜底（560）/ 工具行去重配对规则 / 两支方法串联（真实调用链）。
///
/// 预期值全部按实现读出来写死，不用空断言充数。**不触碰** 12–186、
/// 188–352、644+ 区间。
const AppLocalizations _zh = AppLocalizations(Locale('zh'));

/// 便捷工具行：`startedAt` 固定 1.0（`ToolCall.==` 含该字段）。
ToolCall _tool(
  String name, {
  required String id,
  bool completed = true,
  bool? isError,
  String? preview,
  Map<String, JsonValue>? args,
  double startedAt = 1,
}) => ToolCall(
  id: id,
  name: name,
  isCompleted: completed,
  isError: isError,
  preview: preview,
  args: args,
  startedAt: startedAt,
);

/// 同 name 不同 args 的 generated 行（走 name+args 指纹）。
ToolCall _bashArgs(String id, String cmd) => ToolCall(
  id: id,
  name: 'bash',
  args: {'cmd': JsonString(cmd)},
  startedAt: 1,
);

ToolCall _think(String text) => ToolCall.thinking(text);

ToolCallGroup _group(
  String id, {
  String? anchor,
  String? preceding,
  bool above = false,
  required List<ToolCall> calls,
}) => ToolCallGroup(
  id: id,
  anchorMessageID: anchor,
  precedingMessageID: preceding,
  isAboveContent: above,
  toolCalls: calls,
);

/// 工具行 id 序列（用于钉顺序与去重结果）。
List<String> _ids(ToolCallGroup group) =>
    group.toolCalls.map((c) => c.id).toList();

/// 混合行形状：思考行读作 `think:<文本>`（思考行 id 是随机 uuid，不可钉）。
List<String> _shape(ToolCallGroup group) => group.toolCalls
    .map((c) => c.isThinking ? 'think:${c.thinking}' : c.id)
    .toList();

void main() {
  group('ToolCallGroup.withThinkingRows（行 354）· 元与边界', () {
    test('messages 为空 → 原样返回同一列表实例（不做任何变换）', () {
      final groups = <ToolCallGroup>[
        _group('g1', anchor: 'm1', calls: [_tool('bash', id: 'call_1')]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: const [],
      );

      expect(identical(result, groups), isTrue);
      expect(identical(result.single, groups.single), isTrue);
    });

    test('无 assistant 消息（只有 user）→ 全部 raw 组视为未映射，原样保留', () {
      final groups = [
        _group('g1', anchor: 'm1', calls: [_tool('bash', id: 'call_1')]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: const [ChatMessage(role: 'user', content: 'q', messageId: 'u1')],
      );

      expect(result, hasLength(1));
      expect(identical(result.single, groups.single), isTrue);
    });

    test('未映射的 raw 组（anchor 为 null / 无对应消息）追加在生成卡之后', () {
      const messages = [ChatMessage(role: 'assistant', content: '正文', messageId: 'm1')];
      final groups = [
        _group('g-null', calls: [_tool('bash', id: 'call_9')]),
        _group('g-matched', anchor: 'm1', calls: [_tool('grep', id: 'call_1')]),
        _group('g-foreign', anchor: 'mX', calls: [_tool('cat', id: 'call_8')]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );

      // 生成卡（沿用命中组的 id）在前，未映射组按入参顺序追加。
      expect(result.map((g) => g.id).toList(), [
        'g-matched',
        'g-null',
        'g-foreign',
      ]);
      expect(identical(result[1], groups[0]), isTrue);
      expect(identical(result[2], groups[2]), isTrue);
      expect(_ids(result[0]), ['call_1']);
    });
  });

  group('ToolCallGroup.withThinkingRows · 区间划分与卡位（行 449 起）', () {
    test('单 assistant 带正文 + 工具组锚定它 → 一张卡，正文之后、id 沿用原组', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', content: '正文', messageId: 'm1'),
      ];
      final groups = [
        _group('persisted-tools-m1', anchor: 'm1', calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );

      expect(result, hasLength(1));
      final group = result.single;
      expect(group.id, 'persisted-tools-m1');
      expect(group.anchorMessageID, 'm1');
      // 卡在 m1 正文之后：前驱正文 = m1，不在正文上方。
      expect(group.precedingMessageID, 'm1');
      expect(group.isAboveContent, isFalse);
      expect(_ids(group), ['call_1']);
    });

    test('首段正文之前的 reason + tools → 合成一张「正文上方」卡，行序 think 在前', () {
      const messages = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '先想一下'),
        ChatMessage(role: 'assistant', content: '正文', messageId: 'm2'),
      ];
      final groups = [
        _group('persisted-tools-m1', anchor: 'm1', calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );

      expect(result, hasLength(1));
      final group = result.single;
      expect(group.id, 'persisted-tools-m1');
      // 卡位锚到首段正文本体（m2），而非思考行所属消息（m1）。
      expect(group.anchorMessageID, 'm2');
      expect(group.precedingMessageID, isNull);
      expect(group.isAboveContent, isTrue);
      expect(_shape(group), ['think:先想一下', 'call_1']);
      expect(group.localizedActivityTitle(_zh), '思考 ×1, 终端 ×1');
    });

    test('同一 assistant 消息内 reason 在前、正文在后 → 纯思考卡 persisted-think-<锚>', () {
      const messages = [
        ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          content: '正文',
          reasoning: '先想一下',
        ),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: const [],
        messages: messages,
      );

      expect(result, hasLength(1));
      final group = result.single;
      expect(group.id, 'persisted-think-m1');
      expect(group.anchorMessageID, 'm1');
      expect(group.precedingMessageID, isNull);
      expect(group.isAboveContent, isTrue);
      expect(_shape(group), ['think:先想一下']);
      // ToolCall.thinking 出厂即完成 → 纯思考卡 isComplete。
      expect(group.isComplete, isTrue);
    });

    test('正文把思考与工具切成两段 → 上方思考卡 + 下方工具卡（行序工具在前）', () {
      const messages = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '第一段思考'),
        ChatMessage(role: 'assistant', content: '正文一', messageId: 'm2'),
        ChatMessage(role: 'assistant', messageId: 'm3', reasoning: '第二段思考'),
      ];
      final groups = [
        _group('g-tools', anchor: 'm2', calls: [_tool('bash', id: 'call_1')]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );

      expect(result, hasLength(2));
      expect(result[0].id, 'persisted-think-m2');
      expect(result[0].anchorMessageID, 'm2');
      expect(result[0].precedingMessageID, isNull);
      expect(result[0].isAboveContent, isTrue);
      expect(_shape(result[0]), ['think:第一段思考']);

      expect(result[1].id, 'g-tools');
      expect(result[1].anchorMessageID, 'm2');
      expect(result[1].precedingMessageID, 'm2');
      expect(result[1].isAboveContent, isFalse);
      // 同区间内工具行在前、其后接该消息的思考行（时间线序）。
      expect(_shape(result[1]), ['call_1', 'think:第二段思考']);
    });

    test('区间内只有思考没有工具 → id 回落 persisted-tools[-trailing]-<前段正文锚>', () {
      const midMessages = [
        ChatMessage(role: 'assistant', content: '正文一', messageId: 'm1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: '夹在中间'),
        ChatMessage(role: 'assistant', content: '正文二', messageId: 'm3'),
      ];
      final mid = ToolCallGroup.withThinkingRows(
        groups: const [],
        messages: midMessages,
      );

      expect(mid, hasLength(1));
      expect(mid.single.id, 'persisted-tools-m1');
      expect(mid.single.anchorMessageID, 'm1');
      expect(mid.single.precedingMessageID, 'm1');
      expect(mid.single.isAboveContent, isFalse);
      expect(_shape(mid.single), ['think:夹在中间']);

      const trailingMessages = [
        ChatMessage(role: 'assistant', content: '正文一', messageId: 'm1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: '收尾思考'),
      ];
      final trailing = ToolCallGroup.withThinkingRows(
        groups: const [],
        messages: trailingMessages,
      );

      expect(trailing, hasLength(1));
      expect(trailing.single.id, 'persisted-tools-trailing-m1');
      expect(trailing.single.anchorMessageID, 'm1');
      expect(trailing.single.precedingMessageID, 'm1');
      expect(trailing.single.isAboveContent, isFalse);
      expect(_shape(trailing.single), ['think:收尾思考']);
    });

    test('回合内无可见文本 → 全部事件进同一区间：id 取首个工具组、卡位锚回合首条', () {
      const messages = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '思考'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
      ];
      final groups = [
        _group('g2', anchor: 'm2', calls: [_tool('grep', id: 'call_2')]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );

      expect(result, hasLength(1));
      final group = result.single;
      expect(group.id, 'g2');
      // 卡位取回合内首条 assistant 的锚（m2 的锚被换掉），方向恒为「正文上方」。
      expect(group.anchorMessageID, 'm1');
      expect(group.precedingMessageID, isNull);
      expect(group.isAboveContent, isTrue);
      expect(_shape(group), ['think:思考', 'call_2']);

      // 无 raw 工具组时 id 回落 persisted-think-<回合首锚>。
      final noGroups = ToolCallGroup.withThinkingRows(
        groups: const [],
        messages: const [
          ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '思考'),
        ],
      );
      expect(noGroups.single.id, 'persisted-think-m1');
      expect(_shape(noGroups.single), ['think:思考']);
    });

    test('两个用户回合 → 每回合独立成卡，顺序按回合先后', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', content: 'a1', messageId: 'm1'),
        ChatMessage(role: 'user', content: 'q2', messageId: 'u2'),
        ChatMessage(role: 'assistant', content: 'a2', messageId: 'm2'),
      ];
      final groups = [
        _group('g1', anchor: 'm1', calls: [_tool('bash', id: 'call_1')]),
        _group('g2', anchor: 'm2', calls: [_tool('grep', id: 'call_2')]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );

      expect(result.map((g) => g.id).toList(), ['g1', 'g2']);
      expect(result.map((g) => g.anchorMessageID).toList(), ['m1', 'm2']);
      expect(result.map((g) => g.precedingMessageID).toList(), ['m1', 'm2']);
      expect(result.map((g) => g.isAboveContent).toList(), [false, false]);
    });

    test('raw 组带 stream- 临时锚 → 卡位沿用原锚，preceding 用规范化的 raw:N', () {
      const messages = [
        ChatMessage(role: 'assistant', content: '正文', messageId: 'stream-abc'),
      ];
      final groups = [
        _group('g-live', anchor: 'stream-abc', calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];

      final result = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );

      expect(result, hasLength(1));
      final group = result.single;
      expect(group.id, 'g-live');
      // 卡位保留 raw 组原始锚点（stream- 走 messageId 兜底索引），
      // 而消息自身的 anchorID 已规范化为 raw:0。
      expect(group.anchorMessageID, 'stream-abc');
      expect(group.precedingMessageID, 'raw:0');
      expect(group.isAboveContent, isFalse);
    });
  });

  group('ToolCallGroup.withThinkingRows · hideThinking / 去重 / 幂等', () {
    test('hideThinking 两态对照：思考行剔除后卡位与工具行不变', () {
      const messages = [
        ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          content: '正文',
          reasoning: '思考',
        ),
      ];

      final shown = ToolCallGroup.withThinkingRows(
        groups: const [],
        messages: messages,
      );
      expect(shown, hasLength(1));
      expect(shown.single.id, 'persisted-think-m1');

      // 纯思考形态：隐藏思考 → 整卡消失。
      final hidden = ToolCallGroup.withThinkingRows(
        groups: const [],
        messages: messages,
        hideThinking: true,
      );
      expect(hidden, isEmpty);

      // 带工具时：卡还在，只是少了思考行。
      final groups = [
        _group('g1', anchor: 'm1', calls: [_tool('bash', id: 'call_1')]),
      ];
      final hiddenWithTools = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
        hideThinking: true,
      );
      expect(hiddenWithTools, hasLength(1));
      expect(hiddenWithTools.single.id, 'g1');
      expect(hiddenWithTools.single.anchorMessageID, 'm1');
      expect(hiddenWithTools.single.precedingMessageID, 'm1');
      expect(_shape(hiddenWithTools.single), ['call_1']);

      // 不隐藏时同入参被切成两张卡（思考在上、工具在下）。
      final shownWithTools = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );
      expect(shownWithTools.map((g) => g.isAboveContent).toList(), [
        true,
        false,
      ]);
      expect(_shape(shownWithTools[1]), ['call_1']);
    });

    test('同区间内相同思考文本去重为一行；不同文本保留两行', () {
      const same = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '同一段'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: '同一段'),
      ];
      final deduped = ToolCallGroup.withThinkingRows(
        groups: const [],
        messages: same,
      );

      expect(deduped, hasLength(1));
      expect(_shape(deduped.single), ['think:同一段']);
      expect(deduped.single.id, 'persisted-think-m1');

      const different = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '第一段'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: '第二段'),
      ];
      final kept = ToolCallGroup.withThinkingRows(
        groups: const [],
        messages: different,
      );
      expect(_shape(kept.single), ['think:第一段', 'think:第二段']);
    });

    test('幂等（正文 + 工具形态）：自身输出喂回一遍，字段与形状不变', () {
      const messages = [
        ChatMessage(role: 'assistant', content: '正文', messageId: 'm1'),
      ];
      final groups = [
        _group('persisted-tools-m1', anchor: 'm1', calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];

      final once = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );
      final twice = ToolCallGroup.withThinkingRows(
        groups: once,
        messages: messages,
      );

      expect(twice, hasLength(1));
      expect(twice.single == once.single, isTrue);
      expect(twice.single.id, 'persisted-tools-m1');
      expect(twice.single.precedingMessageID, 'm1');
      expect(twice.single.isAboveContent, isFalse);
    });

    test('幂等（思考 + 工具形态）：喂回后思考行被搬进工具卡，形态由 1 卡变 2 卡', () {
      const messages = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '先想一下'),
        ChatMessage(role: 'assistant', content: '正文', messageId: 'm2'),
      ];
      final groups = [
        _group('persisted-tools-m1', anchor: 'm1', calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];

      final once = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );
      expect(once, hasLength(1));
      expect(_shape(once.single), ['think:先想一下', 'call_1']);
      expect(once.single.isAboveContent, isTrue);

      final twice = ToolCallGroup.withThinkingRows(
        groups: once,
        messages: messages,
      );

      // 二次喂回：上方卡的锚点已变成 m2（= 正文消息），其工具行落进
      // 「末段之后」区间，于是思考与工具被重新切分：纯思考卡 + 工具卡。
      expect(twice, hasLength(2));
      expect(twice[0].id, 'persisted-think-m2');
      expect(twice[0].isAboveContent, isTrue);
      expect(_shape(twice[0]), ['think:先想一下']);

      expect(twice[1].id, 'persisted-tools-m1');
      expect(twice[1].anchorMessageID, 'm2');
      expect(twice[1].precedingMessageID, 'm2');
      expect(twice[1].isAboveContent, isFalse);
      // 工具卡里仍带着思考行（raw 组自带，未被剔除）。
      expect(_shape(twice[1]), ['think:先想一下', 'call_1']);
    });
  });

  group('ToolCallGroup.merging（行 560）· anchor key 命中与透传', () {
    test('空 × 空 → 空；单边为空 → 原样透传（同实例、同顺序）', () {
      expect(
        ToolCallGroup.merging(primaryGroups: const [], fallbackGroups: const []),
        isEmpty,
      );

      final primary = [
        _group('p1', anchor: 'a1', calls: [_tool('bash', id: 'call_1')]),
      ];
      final fallback = [
        _group('f1', anchor: 'a2', calls: [_tool('grep', id: 'call_2')]),
      ];

      final onlyPrimary = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: const [],
      );
      expect(onlyPrimary, hasLength(1));
      expect(identical(onlyPrimary.single, primary.single), isTrue);

      final onlyFallback = ToolCallGroup.merging(
        primaryGroups: const [],
        fallbackGroups: fallback,
      );
      expect(onlyFallback, hasLength(1));
      expect(identical(onlyFallback.single, fallback.single), isTrue);
    });

    test('anchor 与卡位方向都相同 → 并卡：id/anchor/preceding 取主组，工具行主组在前', () {
      final primary = [
        _group('p1', anchor: 'a1', preceding: 'p0', calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];
      final fallback = [
        _group('f1', anchor: 'a1', calls: [_tool('read_file', id: 'call_9')]),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged, hasLength(1));
      final group = merged.single;
      expect(group.id, 'p1');
      expect(group.anchorMessageID, 'a1');
      expect(group.precedingMessageID, 'p0');
      expect(group.isAboveContent, isFalse);
      expect(_ids(group), ['call_1', 'call_9']);
      // 并卡会产出新实例（主组实例不被就地改写）。
      expect(identical(group, primary.single), isFalse);
      expect(primary.single.toolCalls, hasLength(1));
    });

    test('同 anchor 但 isAboveContent 不同 → key 不同，不合并（指纹兜底也要求方向一致）', () {
      final primary = [
        _group('p1', anchor: 'a1', calls: [_tool('bash', id: 'call_1')]),
      ];
      final fallback = [
        _group('f1', anchor: 'a1', above: true, calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged.map((g) => g.id).toList(), ['p1', 'f1']);
      expect(merged.map((g) => g.isAboveContent).toList(), [false, true]);
      expect(identical(merged[1], fallback.single), isTrue);
      // 两条工具行内容相同但分属两张卡，未去重。
      expect(_ids(merged[0]), ['call_1']);
      expect(_ids(merged[1]), ['call_1']);
    });

    test('指纹兜底：anchor 不同但内容相同 → 并卡，卡位仍取主组（不产幽灵卡）', () {
      final primary = [
        _group('p1', anchor: 'a1', calls: [_tool('bash', id: 'call_1')]),
      ];
      final fallback = [
        _group('f1', anchor: 'stream-x', calls: [_tool('bash', id: 'call_1')]),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged, hasLength(1));
      expect(merged.single.id, 'p1');
      expect(merged.single.anchorMessageID, 'a1');
      expect(_ids(merged.single), ['call_1']);
    });

    test('指纹兜底命中后登记 anchor key：后续同锚同方向组直接并卡', () {
      final primary = [
        _group('p1', anchor: 'a1', calls: [_tool('bash', id: 'call_1')]),
      ];
      final fallback = [
        // 第一条靠指纹命中 p1（锚点空间漂移）。
        _group('f1', anchor: 'aX', calls: [_tool('bash', id: 'call_1')]),
        // 第二条沿第一条登记下的 aX:false 命中。
        _group('f2', anchor: 'aX', calls: [_tool('grep', id: 'call_2')]),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged, hasLength(1));
      expect(merged.single.id, 'p1');
      expect(_ids(merged.single), ['call_1', 'call_2']);
    });

    test('指纹子集/超集双向命中：不丢行；主组是子集时行序改由兜底组主导', () {
      // （1）兜底是主组子集 → 并卡且不丢行。
      final subset = ToolCallGroup.merging(
        primaryGroups: [
          _group('p1', anchor: 'a1', calls: [
            _tool('bash', id: 'call_1'),
            _tool('grep', id: 'call_2'),
          ]),
        ],
        fallbackGroups: [
          _group('f1', anchor: 'a9', calls: [_tool('bash', id: 'call_1')]),
        ],
      );
      expect(subset, hasLength(1));
      expect(subset.single.id, 'p1');
      expect(subset.single.anchorMessageID, 'a1');
      expect(_ids(subset.single), ['call_1', 'call_2']);

      // （2）主组是子集（兜底为超集）→ 卡位仍取主组，但工具行顺序按超集方。
      final superset = ToolCallGroup.merging(
        primaryGroups: [
          _group('p1', anchor: 'a1', calls: [_tool('bash', id: 'call_1')]),
        ],
        fallbackGroups: [
          _group('f1', anchor: 'a9', calls: [
            _tool('grep', id: 'call_2'),
            _tool('bash', id: 'call_1'),
          ]),
        ],
      );
      expect(superset, hasLength(1));
      expect(superset.single.id, 'p1');
      expect(superset.single.anchorMessageID, 'a1');
      expect(_ids(superset.single), ['call_2', 'call_1']);
    });

    test('三条以上：命中的并入、未命中的追加末尾，主组相对顺序不变', () {
      final primary = [
        _group('p1', anchor: 'a1', calls: [_tool('bash', id: 'call_1')]),
        _group('p2', anchor: 'a2', calls: [_tool('grep', id: 'call_2')]),
        _group('p3', anchor: 'a3', calls: [_tool('cat', id: 'call_3')]),
      ];
      final fallback = [
        _group('f2', anchor: 'a2', calls: [_tool('read_file', id: 'call_9')]),
        _group('f4', anchor: 'a4', calls: [_tool('web_search', id: 'call_4')]),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged.map((g) => g.id).toList(), ['p1', 'p2', 'p3', 'f4']);
      expect(merged.map((g) => g.anchorMessageID).toList(), [
        'a1',
        'a2',
        'a3',
        'a4',
      ]);
      expect(identical(merged[0], primary[0]), isTrue);
      expect(identical(merged[2], primary[2]), isTrue);
      expect(_ids(merged[1]), ['call_2', 'call_9']);
      // 未命中的兜底组原样追加（字段全部保留）。
      expect(identical(merged[3], fallback[1]), isTrue);
      expect(merged[3].isAboveContent, isFalse);
    });

    test('主组内同 anchor 同方向重复 → key 表后写覆盖，前一条永不接收兜底行', () {
      final primary = [
        _group('p1', anchor: 'a1', calls: [_tool('bash', id: 'call_1')]),
        _group('p2', anchor: 'a1', calls: [_tool('grep', id: 'call_2')]),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: [
          _group('f1', anchor: 'a1', calls: [_tool('cat', id: 'call_3')]),
        ],
      );

      expect(merged, hasLength(2));
      expect(merged.map((g) => g.toolCalls.map((c) => c.id).toList()).toList(), [
        ['call_1'],
        ['call_2', 'call_3'],
      ]);
    });

    test('anchor 为 null 的兜底组只能走指纹：内容相同则并卡，不同则追加', () {
      final primary = [
        _group('p1', anchor: 'a1', calls: [_tool('bash', id: 'call_1')]),
      ];

      final same = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: [
          _group('f1', calls: [_tool('bash', id: 'call_1')]),
        ],
      );
      expect(same, hasLength(1));
      expect(same.single.id, 'p1');

      final different = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: [
          _group('f2', calls: [_tool('grep', id: 'call_2')]),
        ],
      );
      expect(different.map((g) => g.anchorMessageID).toList(), ['a1', null]);
      expect(different.map((g) => g.id).toList(), ['p1', 'f2']);
    });

    test('空工具行的组：同锚同方向仍并卡（结果仍空）；不同锚不会被指纹误并', () {
      final primary = [_group('p1', anchor: 'a1', calls: const [])];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: [_group('f1', anchor: 'a1', calls: const [])],
      );
      expect(merged, hasLength(1));
      expect(merged.single.id, 'p1');
      expect(merged.single.toolCalls, isEmpty);

      final appended = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: [_group('f2', anchor: 'a2', calls: const [])],
      );
      expect(appended.map((g) => g.id).toList(), ['p1', 'f2']);
    });

    test('对同一入参自合并 → 字段不变、工具行不翻倍（幂等形状）', () {
      final primary = [
        _group('p1', anchor: 'a1', preceding: 'p0', calls: [
          _tool('bash', id: 'call_1'),
          _tool('grep', id: 'call_2'),
        ]),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: primary,
      );

      expect(merged, hasLength(1));
      expect(merged.single.id, 'p1');
      expect(merged.single.precedingMessageID, 'p0');
      expect(_ids(merged.single), ['call_1', 'call_2']);
      expect(merged.single == primary.single, isTrue);
    });
  });

  group('ToolCallGroup.merging · 工具行去重与配对规则（私有件带出）', () {
    test('稳定 id 认领同名 generated 行（args 不同也认领）：字段各自补齐', () {
      final merged = ToolCallGroup.merging(
        primaryGroups: [
          _group('p1', anchor: 'a1', calls: [
            ToolCall(
              id: 'message-tool-1-0',
              name: 'bash',
              args: const {'cmd': JsonString('ls')},
              isCompleted: false,
              startedAt: 1,
            ),
          ]),
        ],
        fallbackGroups: [
          _group('f1', anchor: 'a1', calls: [
            ToolCall(
              id: 'call_1',
              name: 'bash',
              args: const {'cmd': JsonString('pwd')},
              preview: '结果',
              isCompleted: true,
              startedAt: 1,
            ),
          ]),
        ],
      );

      expect(merged.single.toolCalls, hasLength(1));
      final call = merged.single.toolCalls.single;
      // 稳定 id 顶替 generated id；主组的 args 保留，空缺字段由兜底补齐。
      expect(call.id, 'call_1');
      expect(call.args!['cmd']!.stringValue, 'ls');
      expect(call.preview, '结果');
      // 完成态按「任一方完成即完成」（主组 false + 兜底 true）。
      expect(call.isCompleted, isTrue);
    });

    test('generated 同名行按出现次序 1:1 配对，不同 args 的两条都保留', () {
      final merged = ToolCallGroup.merging(
        primaryGroups: [
          _group('p1', anchor: 'a1', calls: [
            _bashArgs('live-tool-a', 'ls'),
            _bashArgs('live-tool-b', 'pwd'),
          ]),
        ],
        fallbackGroups: [
          _group('f1', anchor: 'a1', calls: [
            _bashArgs('live-tool-c', 'ls'),
            _bashArgs('live-tool-d', 'pwd'),
          ]),
        ],
      );

      final calls = merged.single.toolCalls;
      expect(calls, hasLength(2));
      expect(calls.map((c) => c.args!['cmd']!.stringValue).toList(), [
        'ls',
        'pwd',
      ]);
      // generated × generated 合并时保留主组 id。
      expect(_ids(merged.single), ['live-tool-a', 'live-tool-b']);
    });

    test('同名序号配对：主组只有 1 条 bash 时，第 2 条 bash 追加为新行', () {
      final merged = ToolCallGroup.merging(
        primaryGroups: [
          _group('p1', anchor: 'a1', calls: [_bashArgs('live-tool-a', 'ls')]),
        ],
        fallbackGroups: [
          _group('f1', anchor: 'a1', calls: [
            _bashArgs('live-tool-c', 'ls'),
            _bashArgs('live-tool-d', 'pwd'),
          ]),
        ],
      );

      expect(_ids(merged.single), ['live-tool-a', 'live-tool-d']);
      expect(
        merged.single.toolCalls
            .map((c) => c.args!['cmd']!.stringValue)
            .toList(),
        ['ls', 'pwd'],
      );
    });

    test('思考行并入：主组优先，不同文本拼接，相同文本只留一份', () {
      String mergedThinking(List<ToolCall> a, List<ToolCall> b) =>
          ToolCallGroup.merging(
            primaryGroups: [_group('p1', anchor: 'a1', calls: a)],
            fallbackGroups: [_group('f1', anchor: 'a1', calls: b)],
          ).single.toolCalls.single.thinking!;

      expect(mergedThinking([_think('第一段')], [_think('第二段')]), '第一段\n\n第二段');
      expect(mergedThinking([_think('同一段')], [_think('同一段')]), '同一段');
      expect(mergedThinking(const [], [_think('只有兜底')]), '只有兜底');
      expect(mergedThinking([_think('只有主组')], const []), '只有主组');
    });

    test('同名 thinking 行按序号配对合并：文本拼接为一行，工具行各自续后', () {
      final merged = ToolCallGroup.merging(
        primaryGroups: [
          _group('p1', anchor: 'a1', calls: [
            _think('主组思考'),
            _tool('bash', id: 'call_1'),
          ]),
        ],
        fallbackGroups: [
          _group('f1', anchor: 'a1', calls: [
            _think('兜底思考'),
            _tool('grep', id: 'call_2'),
          ]),
        ],
      );

      // 两条同名（thinking）行被「同名序号」配对成一条：文本拼接、不丢内容，
      // 但行数不增加（与 withThinkingRows 保留两行的口径不同）。
      expect(_shape(merged.single), [
        'think:主组思考\n\n兜底思考',
        'call_1',
        'call_2',
      ]);
      expect(merged.single.toolCalls.where((c) => c.isThinking), hasLength(1));
    });

    test('主组 1 条 thinking + 兜底 2 条 → 首条被配对合并，多出的成为新行', () {
      final merged = ToolCallGroup.merging(
        primaryGroups: [
          _group('p1', anchor: 'a1', calls: [
            _think('甲'),
            _tool('bash', id: 'call_1'),
          ]),
        ],
        fallbackGroups: [
          _group('f1', anchor: 'a1', calls: [
            _think('乙'),
            _think('丙'),
            _tool('grep', id: 'call_2'),
          ]),
        ],
      );

      expect(_shape(merged.single), [
        'think:甲\n\n乙',
        'call_1',
        'think:丙',
        'call_2',
      ]);
    });
  });

  group('withThinkingRows × merging 串联（真实调用链顺序）', () {
    test('先 merging 再 withThinkingRows：persisted 主组 + 元数据兜底 → 思考卡 + 工具卡', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          reasoning: '先想一下',
          content: '正文一',
        ),
      ];
      final primary = [
        _group('persisted-tools-m1', anchor: 'm1', calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];
      final fallback = [
        _group('message-groups-m1', anchor: 'm1', calls: [
          _tool('read_file', id: 'message-tool-1-0'),
        ]),
      ];

      final raw = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );
      expect(raw, hasLength(1));
      expect(raw.single.id, 'persisted-tools-m1');
      expect(_ids(raw.single), ['call_1', 'message-tool-1-0']);

      final result = ToolCallGroup.withThinkingRows(
        groups: raw,
        messages: messages,
      );

      expect(result.map((g) => g.id).toList(), [
        'persisted-think-m1',
        'persisted-tools-m1',
      ]);
      expect(result[0].isAboveContent, isTrue);
      expect(result[0].anchorMessageID, 'm1');
      expect(_shape(result[0]), ['think:先想一下']);

      expect(result[1].isAboveContent, isFalse);
      expect(result[1].precedingMessageID, 'm1');
      expect(_shape(result[1]), ['call_1', 'message-tool-1-0']);
      expect(result[1].localizedActivityTitle(_zh), '终端 ×1, 读取文件 ×1');
    });

    test('反序：先 withThinkingRows 再 merging（兜底为空 → 透传；同锚兜底 → 幂等）', () {
      const messages = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '先想一下'),
        ChatMessage(role: 'assistant', content: '正文', messageId: 'm2'),
      ];
      final groups = [
        _group('persisted-tools-m1', anchor: 'm1', calls: [
          _tool('bash', id: 'call_1'),
        ]),
      ];

      final withThinking = ToolCallGroup.withThinkingRows(
        groups: groups,
        messages: messages,
      );
      expect(withThinking, hasLength(1));

      final passthrough = ToolCallGroup.merging(
        primaryGroups: withThinking,
        fallbackGroups: const [],
      );
      // 返回新列表实例，但元素原样透传。
      expect(identical(passthrough, withThinking), isFalse);
      expect(identical(passthrough.single, withThinking.single), isTrue);

      // 兜底组复刻同一张卡（同锚 + 同方向 + 同内容）→ 并回一张，行数不翻倍。
      final sameShape = ToolCallGroup.merging(
        primaryGroups: withThinking,
        fallbackGroups: [
          _group('dup', anchor: 'm2', above: true, calls: [
            _tool('bash', id: 'call_1'),
          ]),
        ],
      );
      expect(sameShape, hasLength(1));
      expect(sameShape.single.id, 'persisted-tools-m1');
      expect(_shape(sameShape.single), ['think:先想一下', 'call_1']);
    });
  });
}
