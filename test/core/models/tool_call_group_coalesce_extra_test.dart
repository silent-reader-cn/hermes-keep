import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/tool_call.dart';

/// `tool_call.dart` 覆盖率补强 · 批次 TC3：`coalescingByAssistantTurn`（行 644）
/// 与 `coalescingAdjacent`（行 758）。
///
/// 这两支方法决定展示层「同一 assistant 回合是否合成一张卡」「相邻卡能否合并」，
/// 是本项目「幽灵工具卡」「相邻合并不了」类历史 bug 的判定核心。
///
/// 预期值全部按实现读出来写死（不写空断言）。**不触碰** 12–186 / 188–352 / 354–643
/// 区间，也不触碰 968+ 的内部件（仅通过公开入参把它们带出来）。

ToolCall _call(String name, String id, {String? preview}) =>
    ToolCall(id: id, name: name, preview: preview, isCompleted: true, startedAt: 1);

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

List<String> _groupIDs(List<ToolCallGroup> groups) =>
    groups.map((g) => g.id).toList();

List<String?> _anchors(List<ToolCallGroup> groups) =>
    groups.map((g) => g.anchorMessageID).toList();

List<List<String>> _callIDs(List<ToolCallGroup> groups) =>
    groups.map((g) => g.toolCalls.map((c) => c.id).toList()).toList();

void main() {
  // ── coalescingAdjacent（行 758–964）───────────────────────────────────────
  group('coalescingAdjacent · 空 / 单组（≤1 短路：字段透传 + 工具行去重）', () {
    test('空列表 → 空列表', () {
      expect(
        ToolCallGroup.coalescingAdjacent(const [], messages: const []),
        isEmpty,
      );
    });

    test('单组：id / anchor / preceding / 方向原样，重复工具行按稳定 id 塌成一条', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];
      final single = _group(
        'g1',
        anchor: 'm1',
        preceding: 'u1',
        above: true,
        calls: [
          _call('bash', 'call_1', preview: '第一条'),
          _call('bash', 'call_1', preview: '重放副本'),
        ],
      );

      final out = ToolCallGroup.coalescingAdjacent(
        [single],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.precedingMessageID, 'u1');
      expect(out.single.isAboveContent, isTrue);
      // 去重：先到者的字段胜出（existing.preview ?? fallback.preview）。
      expect(out.single.toolCalls, hasLength(1));
      expect(out.single.toolCalls.single.id, 'call_1');
      expect(out.single.toolCalls.single.preview, '第一条');
      expect(identical(out.single, single), isFalse);
    });

    test('单组且无锚：null 字段不被改写', () {
      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('live-1', calls: [_call('bash', 'call_1')]),
        ],
        messages: const [],
      );

      expect(out.single.id, 'live-1');
      expect(out.single.anchorMessageID, isNull);
      expect(out.single.precedingMessageID, isNull);
      expect(out.single.isAboveContent, isFalse);
    });
  });

  group('coalescingAdjacent · 相邻合并的可 / 不可判据', () {
    test('同回合相邻、两组之间与后组锚点自身都无正文 → 合成一张（工具名不同也合）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
        ChatMessage(role: 'assistant', content: '收尾正文', messageId: 'm3'),
      ];
      final g1 = _group(
        'g1',
        anchor: 'm1',
        preceding: 'u1',
        calls: [_call('bash', 'call_1')],
      );
      final g2 = _group(
        'g2',
        anchor: 'm2',
        preceding: 'm1',
        calls: [_call('read_file', 'call_2')],
      );

      final out = ToolCallGroup.coalescingAdjacent(
        [g1, g2],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.precedingMessageID, 'u1');
      expect(out.single.isAboveContent, isFalse);
      // 判据不含工具名：bash 与 read_file 照合。
      expect(_callIDs(out), [
        ['call_1', 'call_2'],
      ]);
    });

    test('两组之间有带正文的 assistant 消息（hasTextBetween）→ 不合并', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', content: '中间正文', messageId: 'm_mid'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(2));
      expect(_groupIDs(out), ['g1', 'g2']);
      expect(_anchors(out), ['m1', 'm2']);
      expect(_callIDs(out), [
        ['call_1'],
        ['call_2'],
      ]);
    });

    test('后组锚点消息自身带可见正文 → 仍不合并（textAnchorIDs 语义）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', content: '正文', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      // hasTextBetween(1, 2) 为 false（两者紧邻），阻断来自
      // `anchorIndex != currIdx && textAnchorIDs.contains(group.anchorMessageID)`。
      expect(out, hasLength(2));
      expect(_anchors(out), ['m1', 'm2']);
    });

    test('卡位方向不同（above vs below）→ 不合并', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group(
            'g2',
            anchor: 'm2',
            above: true,
            calls: [_call('grep', 'call_2')],
          ),
        ],
        messages: messages,
      );

      expect(out, hasLength(2));
      expect(_groupIDs(out), ['g1', 'g2']);
      expect(out[0].isAboveContent, isFalse);
      expect(out[1].isAboveContent, isTrue);
    });

    test('同锚点、方向相反：方向不同既不去重也不合并，且 above 排前（排序 tie-break）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g-below', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group(
            'g-above',
            anchor: 'm1',
            above: true,
            calls: [_call('grep', 'call_2')],
          ),
        ],
        messages: messages,
      );

      expect(out, hasLength(2));
      // 同一 anchorIndex 平手 → isAboveContent=true 者在前。
      expect(_groupIDs(out), ['g-above', 'g-below']);
    });

    test('输出按锚点消息在 transcript 中的位置重排（输入倒序 → 输出正序）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', content: '中间正文', messageId: 'm_mid'),
        ChatMessage(role: 'assistant', messageId: 'm3'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g3', anchor: 'm3', calls: [_call('grep', 'call_3')]),
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
        ],
        messages: messages,
      );

      expect(_groupIDs(out), ['g1', 'g3']);
      expect(_anchors(out), ['m1', 'm3']);
      expect(_callIDs(out), [
        ['call_1'],
        ['call_3'],
      ]);
    });

    test('null 锚（未锚组）与有锚组方向不同 → 不归并，且排在有锚组之后', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g-live', calls: [_call('read_file', 'call_2')], above: true),
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
        ],
        messages: messages,
      );

      expect(_groupIDs(out), ['g1', 'g-live']);
      expect(out[0].anchorMessageID, 'm1');
      expect(out[1].anchorMessageID, isNull);
      expect(out[1].isAboveContent, isTrue);
    });
  });

  group('coalescingAdjacent · 未锚 / 死锚归并（#112 幽灵卡路径）', () {
    test('有锚组在前、null 锚组在后且方向一致 → 归并到有锚组，保留其 id / anchor', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', preceding: 'u1', calls: [_call('bash', 'call_1')]),
          _group('g-live', calls: [_call('read_file', 'call_2')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.precedingMessageID, 'u1');
      expect(_callIDs(out), [
        ['call_1', 'call_2'],
      ]);
    });

    test('死锚（anchor 不在 messages）在前 → 归并到后方的有锚组，且取有锚组身份', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group(
            'g-dead',
            anchor: 'stream-ghost',
            preceding: 'stream-ghost',
            calls: [_call('bash', 'call_1')],
          ),
          _group('g1', anchor: 'm1', preceding: 'u1', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      // 死锚 anchorIndex = -1（排最前）；方向一致 → isUnanchoredLeakMerge 命中，
      // 因 currIdx < 0 而整体换成有锚组的 id / anchor / preceding。
      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.precedingMessageID, 'u1');
      expect(_callIDs(out), [
        ['call_2', 'call_1'],
      ]);
    });

    test('两枚死锚相邻：方向一致但双方都未锚 → 不归并（只各留一组）', () {
      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g-dead-1', anchor: 'stream-a', calls: [_call('bash', 'call_1')]),
          _group('g-dead-2', anchor: 'stream-b', calls: [_call('grep', 'call_2')]),
        ],
        messages: const [],
      );

      expect(out, hasLength(2));
      expect(_groupIDs(out), ['g-dead-1', 'g-dead-2']);
    });

    test('两枚死锚 + 工具指纹相等 → 降级为指纹去重，只留一张（防重复卡）', () {
      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g-dead-1', anchor: 'stream-a', calls: [_call('bash', 'call_1')]),
          _group('g-dead-2', anchor: 'stream-b', calls: [_call('bash', 'call_1')]),
        ],
        messages: const [],
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g-dead-1');
      expect(out.single.toolCalls, hasLength(1));
    });
  });

  group('coalescingAdjacent · 指纹去重（相等 / 子集）与其保守边界', () {
    test('同锚点同方向、工具指纹相等 → 塌成一张', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm1', calls: [_call('bash', 'call_1')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(out.single.toolCalls, hasLength(1));
    });

    test('子集关系（existing ⊃ group）→ 去重合并，字段取先到者，工具行保持两条', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group(
            'g1',
            anchor: 'm1',
            calls: [
              _call('bash', 'call_1', preview: '先到者字段'),
              _call('grep', 'call_2'),
            ],
          ),
          _group('g2', anchor: 'm1', calls: [_call('bash', 'call_1')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(_callIDs(out), [
        ['call_1', 'call_2'],
      ]);
      // 合并时 existing 为主：preview 保留先到者，不被 null 覆盖。
      expect(out.single.toolCalls.first.preview, '先到者字段');
    });

    test('两组跨正文锚点（后组锚自身带正文）→ 保守不去重，保持两组', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', content: '正文', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('bash', 'call_1')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(2));
      expect(_anchors(out), ['m1', 'm2']);
      expect(_callIDs(out), [
        ['call_1'],
        ['call_1'],
      ]);
    });

    test('空工具行的同锚相邻组：指纹去重不适用，但相邻归并照常塌成一张（0 工具行）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: const []),
          _group('g2', anchor: 'm1', calls: const []),
        ],
        messages: messages,
      );

      // 指纹去重（相等/子集）以「双方非空」为前提，故不走指纹路径；
      // 相邻归并（isAnchoredMerge）不比对工具内容，仍然命中 → 一张空卡。
      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(out.single.toolCalls, isEmpty);
    });

    test('空工具行 + 方向相反 → 既不指纹去重也不相邻归并，保持两组', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: const []),
          _group('g2', anchor: 'm1', above: true, calls: const []),
        ],
        messages: messages,
      );

      expect(out, hasLength(2));
      expect(_groupIDs(out), ['g2', 'g1']);
    });

    test('未锚组在前、有锚组在后且指纹相等 → 去重后整体换成有锚组身份（补锚）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g-live', calls: [_call('bash', 'call_1')]),
          _group(
            'g-a',
            anchor: 'm1',
            preceding: 'u1',
            calls: [_call('bash', 'call_1')],
          ),
        ],
        messages: messages,
      );

      // existing 未锚（anchorIdx < 0）而 group 已锚 → 指纹去重时整体采用
      // group 的 id / anchor / preceding（targetAnchor/targetId/targetPreceding 真分支）。
      expect(out, hasLength(1));
      expect(out.single.id, 'g-a');
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.precedingMessageID, 'u1');
      expect(_callIDs(out), [
        ['call_1'],
      ]);
    });

    test('已去重组是严格子集（isSuper）→ 以元素更多的一组为主拼接，字段保留先到者', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group(
            'g1',
            anchor: 'm1',
            calls: [_call('bash', 'call_1', preview: '先到者字段')],
          ),
          _group(
            'g2',
            anchor: 'm1',
            calls: [_call('bash', 'call_1'), _call('grep', 'call_2')],
          ),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(out.single.anchorMessageID, 'm1');
      expect(_callIDs(out), [
        ['call_1', 'call_2'],
      ]);
      expect(out.single.toolCalls.first.preview, '先到者字段');
    });
  });

  group('coalescingAdjacent · 跨回合边界与幂等', () {
    test('跨用户回合、但两组之间没有 assistant 可见正文 → 仍合并（当前行为，见报告）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'user', content: 'q2', messageId: 'u2'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      // hasTextBetween 只看 assistant 角色：u2 的正文不构成分隔符 → 合并且锚取前组。
      expect(out, hasLength(1));
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.toolCalls, hasLength(2));
    });

    test('幂等：被正文分开的两组再跑一次，形状不变', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', content: '中间正文', messageId: 'm_mid'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
      ];
      final input = [
        _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
        _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
      ];

      final once = ToolCallGroup.coalescingAdjacent(input, messages: messages);
      final twice = ToolCallGroup.coalescingAdjacent(once, messages: messages);

      expect(_groupIDs(twice), _groupIDs(once));
      expect(_anchors(twice), _anchors(once));
      expect(_callIDs(twice), _callIDs(once));
    });

    test('幂等：已合并成一张后再跑一次，仍是同一张且工具行不重复', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
      ];
      final once = ToolCallGroup.coalescingAdjacent(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      final twice = ToolCallGroup.coalescingAdjacent(once, messages: messages);

      expect(twice, hasLength(1));
      expect(twice.single.id, once.single.id);
      expect(_callIDs(twice), [
        ['call_1', 'call_2'],
      ]);
    });
  });

  // ── coalescingByAssistantTurn（行 644–752）─────────────────────────────────
  group('coalescingByAssistantTurn · 空 / 单组（≤1 短路）', () {
    test('空列表 → 空列表', () {
      expect(
        ToolCallGroup.coalescingByAssistantTurn(const [], messages: const []),
        isEmpty,
      );
    });

    test('单组：方向字段原样，重复工具行按稳定 id 塌成一条', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
      ];
      final single = _group(
        'g1',
        anchor: 'm1',
        preceding: 'u1',
        above: true,
        calls: [_call('bash', 'call_1'), _call('bash', 'call_1')],
      );

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [single],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.precedingMessageID, 'u1');
      expect(out.single.isAboveContent, isTrue);
      expect(out.single.toolCalls, hasLength(1));
      expect(out.single.toolCalls.single.id, 'call_1');
    });

    test('单组且无锚：null 字段不被改写', () {
      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('live-1', calls: [_call('bash', 'call_1')]),
        ],
        messages: const [],
      );

      expect(out.single.id, 'live-1');
      expect(out.single.anchorMessageID, isNull);
      expect(out.single.precedingMessageID, isNull);
    });
  });

  group('coalescingByAssistantTurn · 回合聚合（同回合合、跨回合不合）', () {
    test('同一 assistant 回合内被正文打断的两组 → 合成一张（与 adjacent 相反）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', content: '中间正文', messageId: 'm2'),
        ChatMessage(role: 'assistant', messageId: 'm3'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm3', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g1');
      // 卡位锚 = 该回合首个「带正文」的 assistant 消息。
      expect(out.single.anchorMessageID, 'm2');
      expect(out.single.precedingMessageID, 'm2');
      expect(out.single.isAboveContent, isFalse);
      expect(_callIDs(out), [
        ['call_1', 'call_2'],
      ]);
    });

    test('两个用户回合 → 各成一张，不跨回合合，且按锚点位置排序', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', content: 'a1', messageId: 'm1'),
        ChatMessage(role: 'user', content: 'q2', messageId: 'u2'),
        ChatMessage(role: 'assistant', content: 'a2', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(2));
      expect(_groupIDs(out), ['g1', 'g2']);
      expect(_anchors(out), ['m1', 'm2']);
      expect(out.map((g) => g.precedingMessageID).toList(), ['m1', 'm2']);
      expect(_callIDs(out), [
        ['call_1'],
        ['call_2'],
      ]);
    });

    test('回合内无任何正文 → 锚回落该回合「最早的 assistant 消息」', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.precedingMessageID, 'm1');
      expect(out.single.isAboveContent, isFalse);
    });

    test('回合内首段正文不在任何工具锚上 → 锚取那条正文消息', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', content: '首段正文', messageId: 'm2'),
        ChatMessage(role: 'assistant', messageId: 'm3'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm3', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      expect(out.single.anchorMessageID, 'm2');
      expect(out.single.precedingMessageID, 'm2');
    });

    test('合并后工具行顺序 = 输入（时间线）顺序；同 id 工具行不双显', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
        ChatMessage(role: 'assistant', messageId: 'm3'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('bash', 'call_1')]),
          _group('g3', anchor: 'm3', calls: [_call('grep', 'call_3')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(_callIDs(out), [
        ['call_1', 'call_3'],
      ]);
    });

    test('输入倒序仍按输入序拼接工具行（append 只换身份不重排工具行）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      // 后到的更早锚点会覆盖 id/anchor（_TurnGroupBuilder.append 覆盖规则），
      // 但工具行保持 append 顺序。
      expect(out.single.id, 'g1');
      expect(out.single.anchorMessageID, 'm1');
      expect(_callIDs(out), [
        ['call_2', 'call_1'],
      ]);
    });

    test('同锚点两组：后组 isAboveContent=true 触发 append 覆盖（id 换成后组）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g-below', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group(
            'g-above',
            anchor: 'm1',
            above: true,
            calls: [_call('grep', 'call_2')],
          ),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'g-above');
      expect(out.single.anchorMessageID, 'm1');
      expect(out.single.isAboveContent, isTrue);
      expect(out.single.precedingMessageID, isNull);
      expect(_callIDs(out), [
        ['call_1', 'call_2'],
      ]);
    });

    test('合并后首个工具行是思考行 → 整卡钉到正文上方（preceding 置 null）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
        ChatMessage(role: 'assistant', content: '正文', messageId: 'm2'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'm1', calls: [_think('先想一想')]),
          _group('g2', anchor: 'm2', calls: [_call('bash', 'call_1')]),
        ],
        messages: messages,
      );

      expect(out, hasLength(1));
      expect(out.single.isAboveContent, isTrue);
      expect(out.single.precedingMessageID, isNull);
      expect(out.single.anchorMessageID, 'm2');
      expect(out.single.toolCalls.first.isThinking, isTrue);
      expect(_callIDs(out).single, hasLength(2));
    });
  });

  group('coalescingByAssistantTurn · 锚不可解析 / 非 assistant 锚 / messageOffset', () {
    test('null 锚组各自成组、不参与回合归并，且排在有锚组之后', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g-live', calls: [_call('read_file', 'call_2')]),
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
        ],
        messages: messages,
      );

      expect(_groupIDs(out), ['g1', 'g-live']);
      expect(_anchors(out), ['m1', null]);
      expect(out.last.isAboveContent, isFalse);
    });

    test('messages 为空 → 锚全不可解析：各自成组，且输出顺序按 groupOrder 反向', () {
      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'm2', calls: [_call('grep', 'call_2')]),
        ],
        messages: const [],
      );

      // anchorIndex = (1<<62) - groupOrder，升序排序 → 后输入者在前。
      expect(_groupIDs(out), ['g2', 'g1']);
      expect(_anchors(out), ['m2', 'm1']);
    });

    test('锚点落在 user 消息上（非 assistant）→ 不归并；同锚平手按 turnKey 字典序', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('ga', anchor: 'u1', calls: [_call('bash', 'call_1')]),
          _group('gb', anchor: 'u1', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      expect(_groupIDs(out), ['ga', 'gb']);
      expect(_anchors(out), ['u1', 'u1']);
      expect(_callIDs(out), [
        ['call_1'],
        ['call_2'],
      ]);
    });

    test('messageOffset 让 raw: 锚命中 → 照常按回合归并', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q'),
        ChatMessage(role: 'assistant', content: 'a'),
        ChatMessage(role: 'assistant'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'raw:6', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'raw:7', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
        messageOffset: 5,
      );

      expect(out, hasLength(1));
      expect(out.single.anchorMessageID, 'raw:6');
      expect(out.single.precedingMessageID, 'raw:6');
    });

    test('同一组入参换 messageOffset → raw: 锚失配，退化为两组（顺序反向）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q'),
        ChatMessage(role: 'assistant', content: 'a'),
        ChatMessage(role: 'assistant'),
      ];

      final out = ToolCallGroup.coalescingByAssistantTurn(
        [
          _group('g1', anchor: 'raw:6', calls: [_call('bash', 'call_1')]),
          _group('g2', anchor: 'raw:7', calls: [_call('grep', 'call_2')]),
        ],
        messages: messages,
      );

      expect(_groupIDs(out), ['g2', 'g1']);
    });
  });

  group('coalescingByAssistantTurn · 组合链（merging → withThinkingRows → coalesce）', () {
    // 一条「同回合、中间有正文」的标准入参：
    // u1 → m1(工具) → m2(中间正文) → m3(工具)
    const chainMessages = [
      ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
      ChatMessage(role: 'assistant', messageId: 'm1'),
      ChatMessage(role: 'assistant', content: '中间正文', messageId: 'm2'),
      ChatMessage(role: 'assistant', messageId: 'm3'),
    ];

    final rawGroups = [
      _group('persisted-tools-m1', anchor: 'm1', calls: [_call('bash', 'call_1')]),
      _group('persisted-tools-m3', anchor: 'm3', calls: [_call('grep', 'call_2')]),
    ];

    test('withThinkingRows 把两组按正文切成「正文上方 / 正文下方」两区间', () {
      final interval = ToolCallGroup.withThinkingRows(
        groups: rawGroups,
        messages: chainMessages,
      );

      expect(interval, hasLength(2));
      expect(interval[0].id, 'persisted-tools-m1');
      expect(interval[0].anchorMessageID, 'm2');
      expect(interval[0].precedingMessageID, isNull);
      expect(interval[0].isAboveContent, isTrue);
      expect(interval[1].id, 'persisted-tools-m3');
      expect(interval[1].anchorMessageID, 'm3');
      expect(interval[1].precedingMessageID, 'm2');
      expect(interval[1].isAboveContent, isFalse);
    });

    test('全链（coalesce=true）：merging → withThinkingRows → byAssistantTurn = 整轮一张大卡', () {
      final interval = ToolCallGroup.withThinkingRows(
        groups: rawGroups,
        messages: chainMessages,
      );
      final merged = ToolCallGroup.merging(
        primaryGroups: interval,
        fallbackGroups: [
          _group(
            'metadata-tools-m3',
            anchor: 'm3',
            calls: [_call('read_file', 'call_3')],
          ),
        ],
      );
      // merging 按 `anchor:isAboveContent` 命中主组 → 主组身份保留、工具行合并。
      expect(merged, hasLength(2));
      expect(_callIDs(merged), [
        ['call_1'],
        ['call_2', 'call_3'],
      ]);

      final out = ToolCallGroup.coalescingByAssistantTurn(
        merged,
        messages: chainMessages,
      );

      expect(out, hasLength(1));
      expect(out.single.id, 'persisted-tools-m1');
      expect(out.single.anchorMessageID, 'm2');
      expect(out.single.isAboveContent, isTrue);
      expect(out.single.precedingMessageID, isNull);
      expect(_callIDs(out), [
        ['call_1', 'call_2', 'call_3'],
      ]);
      expect(out.single.isComplete, isTrue);
    });

    test('全链（coalesce=false）：同一预处理结果走 adjacent = 两卡穿插', () {
      final interval = ToolCallGroup.withThinkingRows(
        groups: rawGroups,
        messages: chainMessages,
      );
      final merged = ToolCallGroup.merging(
        primaryGroups: interval,
        fallbackGroups: [
          _group(
            'metadata-tools-m3',
            anchor: 'm3',
            calls: [_call('read_file', 'call_3')],
          ),
        ],
      );

      final out = ToolCallGroup.coalescingAdjacent(
        merged,
        messages: chainMessages,
      );

      expect(out, hasLength(2));
      expect(_groupIDs(out), ['persisted-tools-m1', 'persisted-tools-m3']);
      expect(_anchors(out), ['m2', 'm3']);
      expect(out[0].isAboveContent, isTrue);
      expect(out[1].isAboveContent, isFalse);
      expect(_callIDs(out), [
        ['call_1'],
        ['call_2', 'call_3'],
      ]);
    });

    test('groups(coalesce:) 端到端：同一入参两种模式的分组数对照', () {
      const persisted = [
        PersistedToolCall(name: 'bash', tid: 'call_1', assistantMsgIdx: 1),
        PersistedToolCall(name: 'grep', tid: 'call_2', assistantMsgIdx: 3),
      ];

      final coalesced = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: chainMessages,
        coalesce: true,
      );
      final adjacent = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: chainMessages,
        coalesce: false,
      );

      expect(coalesced, hasLength(1));
      expect(coalesced.single.anchorMessageID, 'm2');
      expect(_callIDs(coalesced), [
        ['call_1', 'call_2'],
      ]);

      expect(adjacent, hasLength(2));
      expect(_callIDs(adjacent), [
        ['call_1'],
        ['call_2'],
      ]);
    });
  });
}
