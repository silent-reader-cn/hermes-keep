import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';

/// `chat_models.dart` 覆盖率补强 · 批次 CM2：`ReasoningGroup`（行 105–359）。
///
/// 覆盖：构造器（106）/ 字段（108–109）/ `groups`（112–130）/
/// `merging`（133–162）/ `coalescingByTurn`（165–232）/
/// `coalescingAdjacent`（236–306）/ `_messageIndexForAnchor`（308–324）/
/// `_turnKeyAt`（326–338）/ `==`·`hashCode`·`toString`（340–352）。
///
/// 注（任务书 §3 的「不适用」条目）：`ReasoningGroup` 只有 `anchorMessageId` /
/// `text` 两个字段，**没有** `fromJson` / `toJson`、**没有**派生 getter、
/// **没有** `LiveSegmentKind` 字段。对应条目改由「构造 + 四个静态工厂逐分支」
/// 覆盖，判断依据见 TASK_REPORT.md。
///
/// 预期值全部按实现读出来写死，不用空断言充数。
/// **不触碰** 11–104 与 360+ 区间（别的作业面）。
ChatMessage _assistant(String? id, {String? content, String? reasoning}) =>
    ChatMessage(
      role: 'assistant',
      messageId: id,
      content: content,
      reasoning: reasoning,
    );

ChatMessage _user(String? id, {String? content}) =>
    ChatMessage(role: 'user', messageId: id, content: content);

/// 只带工具调用、没有可见正文的 assistant 消息
/// （`coalescingAdjacent.breaksBetween` 的「不打断」形状）。
ChatMessage _assistantToolsOnly(String id) => ChatMessage(
  role: 'assistant',
  messageId: id,
  toolCalls: const [
    JsonObject({'id': JsonString('call_1')}),
  ],
);

void main() {
  group('ReasoningGroup 构造器 / 字段', () {
    test('anchorMessageId 缺省为 null；text 原样落位（不 trim）', () {
      const group = ReasoningGroup(text: '思考正文');

      expect(group.anchorMessageId, isNull);
      expect(group.text, '思考正文');
    });

    test('显式 anchorMessageId 落位；空串 / 纯空白原样保留（构造期不归一）', () {
      const emptyBoth = ReasoningGroup(anchorMessageId: '', text: '');

      expect(emptyBoth.anchorMessageId, '');
      expect(emptyBoth.text, '');

      const blank = ReasoningGroup(anchorMessageId: '  ', text: '  x  ');

      expect(blank.anchorMessageId, '  ');
      expect(blank.text, '  x  ');
    });

    test('const 构造走 canonical 化：同参 const 实例 identical 且相等', () {
      const lhs = ReasoningGroup(anchorMessageId: 'm1', text: 'x');
      const rhs = ReasoningGroup(anchorMessageId: 'm1', text: 'x');

      expect(identical(lhs, rhs), isTrue);
      expect(lhs == rhs, isTrue);
      expect(lhs.hashCode == rhs.hashCode, isTrue);
    });

    test('非 const 同参构造：不同实例但相等', () {
      // 由运行期取值（列表下标）构造：编译器无法 canonical 化，两个实例必然不同。
      final fields = ['m1', 'x'];
      final lhs = ReasoningGroup(anchorMessageId: fields[0], text: fields[1]);
      final rhs = ReasoningGroup(anchorMessageId: fields[0], text: fields[1]);

      expect(identical(lhs, rhs), isFalse);
      expect(lhs == rhs, isTrue);
      expect(lhs.hashCode == rhs.hashCode, isTrue);
    });
  });

  group('ReasoningGroup.groups（从消息列表提取已归档推理段）', () {
    test('空消息列表 → 无组（带 messageOffset 同样为空）', () {
      expect(ReasoningGroup.groups(messages: const []), isEmpty);
      expect(
        ReasoningGroup.groups(messages: const [], messageOffset: 9),
        isEmpty,
      );
    });

    test('非 assistant 角色即使带 reasoning 也不参与（role 先于 reasoning 判定）', () {
      expect(
        ReasoningGroup.groups(
          messages: const [
            ChatMessage(role: 'user', messageId: 'u1', reasoning: '用户侧推理'),
            ChatMessage(role: 'tool', messageId: 't1', reasoning: '工具侧推理'),
          ],
        ),
        isEmpty,
      );
    });

    test('reasoning 为 null / 空串 / 纯空白（含换行制表）→ 全部跳过', () {
      expect(
        ReasoningGroup.groups(
          messages: const [
            ChatMessage(role: 'assistant', messageId: 'm1'),
            ChatMessage(role: 'assistant', messageId: 'm2', reasoning: ''),
            ChatMessage(role: 'assistant', messageId: 'm3', reasoning: '   '),
            ChatMessage(
              role: 'assistant',
              messageId: 'm4',
              reasoning: '\n\t ',
            ),
            ChatMessage(
              role: 'assistant',
              messageId: 'm5',
              content: '有正文无推理',
            ),
          ],
        ),
        isEmpty,
      );
    });

    test('有 reasoning 才成组：text 取 trim 后结果，anchor 取 messageId', () {
      final groups = ReasoningGroup.groups(
        messages: const [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(
            role: 'assistant',
            messageId: 'm1',
            content: 'a',
            reasoning: '  第一段思考  ',
          ),
        ],
      );

      expect(groups, hasLength(1));
      expect(groups.single.anchorMessageId, 'm1');
      expect(groups.single.text, '第一段思考');
    });

    test('多段按消息顺序成组，空段被跳过且不影响后续锚', () {
      final groups = ReasoningGroup.groups(
        messages: const [
          ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
          ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
          ChatMessage(role: 'assistant', messageId: 'm2', content: '无推理'),
          ChatMessage(role: 'user', content: 'q2', messageId: 'u2'),
          ChatMessage(role: 'assistant', messageId: 'm3', reasoning: 'r2'),
          ChatMessage(role: 'assistant', messageId: 'm4', reasoning: '  '),
          ChatMessage(role: 'assistant', messageId: 'm5', reasoning: 'r3'),
        ],
      );

      expect(groups.map((g) => g.anchorMessageId).toList(), [
        'm1',
        'm3',
        'm5',
      ]);
      expect(groups.map((g) => g.text).toList(), ['r1', 'r2', 'r3']);
    });

    test('messageId 缺失 / 空串 / 纯空白 / stream- / local- / unanchored '
        '→ raw:offset+index 兜底', () {
      final groups = ReasoningGroup.groups(
        messages: const [
          ChatMessage(role: 'assistant', reasoning: 'r0'),
          ChatMessage(role: 'assistant', messageId: '', reasoning: 'r1'),
          ChatMessage(role: 'assistant', messageId: '   ', reasoning: 'r2'),
          ChatMessage(
            role: 'assistant',
            messageId: 'stream-1',
            reasoning: 'r3',
          ),
          ChatMessage(role: 'assistant', messageId: 'local-2', reasoning: 'r4'),
          ChatMessage(
            role: 'assistant',
            messageId: 'unanchored',
            reasoning: 'r5',
          ),
        ],
      );

      expect(groups.map((g) => g.anchorMessageId).toList(), [
        'raw:0',
        'raw:1',
        'raw:2',
        'raw:3',
        'raw:4',
        'raw:5',
      ]);
      // text 与兜底锚一一对应，未错位。
      expect(groups.map((g) => g.text).toList(), [
        'r0',
        'r1',
        'r2',
        'r3',
        'r4',
        'r5',
      ]);
    });

    test('messageOffset 平移到 raw 兜底锚；负 offset 夹到 0；缺省按 0', () {
      const messages = [
        ChatMessage(role: 'assistant', messageId: 'stream-x', reasoning: 'r'),
      ];

      expect(
        ReasoningGroup.groups(messages: messages).single.anchorMessageId,
        'raw:0',
      );
      expect(
        ReasoningGroup.groups(
          messages: messages,
          messageOffset: 7,
        ).single.anchorMessageId,
        'raw:7',
      );
      expect(
        ReasoningGroup.groups(
          messages: messages,
          messageOffset: -5,
        ).single.anchorMessageId,
        'raw:0',
      );
    });

    test('messageId 首尾空白 trim 后是真锚（不落 raw 兜底）', () {
      final groups = ReasoningGroup.groups(
        messages: const [
          ChatMessage(
            role: 'assistant',
            messageId: '  m1  ',
            reasoning: 'r',
          ),
        ],
      );

      expect(groups.single.anchorMessageId, 'm1');
    });

    test('只有 stream- / local- 前缀与整串 unanchored 触发兜底：'
        'streaming- / localized / unanchored-x 是真锚', () {
      final groups = ReasoningGroup.groups(
        messages: const [
          ChatMessage(
            role: 'assistant',
            messageId: 'streaming-1',
            reasoning: 'r0',
          ),
          ChatMessage(
            role: 'assistant',
            messageId: 'localized',
            reasoning: 'r1',
          ),
          ChatMessage(
            role: 'assistant',
            messageId: 'unanchored-x',
            reasoning: 'r2',
          ),
        ],
      );

      expect(groups.map((g) => g.anchorMessageId).toList(), [
        'streaming-1',
        'localized',
        'unanchored-x',
      ]);
    });

    test('返回值是可增删列表（非固定长度）', () {
      final groups = ReasoningGroup.groups(messages: const []);

      groups.add(const ReasoningGroup(text: 'x'));

      expect(groups, hasLength(1));
    });
  });

  group('ReasoningGroup.merging（主推理组 + 兜底推理组按锚合并）', () {
    test('两组都空 → 空列表，且是新列表（不动入参）', () {
      final primary = <ReasoningGroup>[];
      final fallback = <ReasoningGroup>[];
      final merged = ReasoningGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged, isEmpty);
      expect(identical(merged, primary), isFalse);
    });

    test('只有 primary → 内容与顺序原样，且是新列表', () {
      const primary = [
        ReasoningGroup(anchorMessageId: 'a1', text: 't1'),
        ReasoningGroup(anchorMessageId: 'a2', text: 't2'),
      ];
      final merged = ReasoningGroup.merging(
        primaryGroups: primary,
        fallbackGroups: const [],
      );

      expect(merged.map((g) => g.anchorMessageId).toList(), ['a1', 'a2']);
      expect(merged.map((g) => g.text).toList(), ['t1', 't2']);
      expect(identical(merged, primary), isFalse);
    });

    test('fallback 锚未命中 primary → 追加到尾部并保持入参顺序', () {
      const primary = [ReasoningGroup(anchorMessageId: 'a1', text: 't1')];
      const fallback = [
        ReasoningGroup(anchorMessageId: 'a2', text: 't2'),
        ReasoningGroup(anchorMessageId: 'a3', text: 't3'),
      ];
      final merged = ReasoningGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged.map((g) => g.anchorMessageId).toList(), [
        'a1',
        'a2',
        'a3',
      ]);
    });

    test('同锚命中且 primary 有非空正文 → 保留 primary，fallback 被丢弃', () {
      const primary = [
        ReasoningGroup(anchorMessageId: 'a1', text: '服务端推理'),
      ];
      const fallback = [
        ReasoningGroup(anchorMessageId: 'a1', text: '本地 live 推理'),
      ];
      final merged = ReasoningGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged, hasLength(1));
      expect(merged.single.text, '服务端推理');
    });

    test('同锚命中且 primary 为空串 / 纯空白，fallback 非空 → 整体替换成 fallback', () {
      const fallback = [ReasoningGroup(anchorMessageId: 'a1', text: ' 兜底 ')];

      final fromEmpty = ReasoningGroup.merging(
        primaryGroups: const [ReasoningGroup(anchorMessageId: 'a1', text: '')],
        fallbackGroups: fallback,
      );
      expect(fromEmpty, hasLength(1));
      expect(fromEmpty.single.anchorMessageId, 'a1');
      expect(fromEmpty.single.text, ' 兜底 ');

      final fromBlank = ReasoningGroup.merging(
        primaryGroups: const [
          ReasoningGroup(anchorMessageId: 'a1', text: '   '),
        ],
        fallbackGroups: fallback,
      );
      expect(fromBlank.single.text, ' 兜底 ');
    });

    test('同锚命中：仅当「primary 空白 且 fallback 非空白」才替换——'
        'fallback 也空白时保持 primary 原文', () {
      final merged = ReasoningGroup.merging(
        primaryGroups: const [
          ReasoningGroup(anchorMessageId: 'a1', text: '   '),
        ],
        fallbackGroups: const [
          ReasoningGroup(anchorMessageId: 'a1', text: '\n'),
        ],
      );

      expect(merged, hasLength(1));
      expect(merged.single.text, '   ');
    });

    test('锚为 null 的组不上索引：fallback 逐条追加（与 primary 的 null 锚不去重）', () {
      const primary = [ReasoningGroup(text: '无锚 primary')];
      const fallback = [
        ReasoningGroup(text: '无锚 fallback 1'),
        ReasoningGroup(text: '无锚 fallback 2'),
      ];
      final merged = ReasoningGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged, hasLength(3));
      expect(merged.map((g) => g.text).toList(), [
        '无锚 primary',
        '无锚 fallback 1',
        '无锚 fallback 2',
      ]);
      expect(merged.every((g) => g.anchorMessageId == null), isTrue);
    });

    test('primary 内同锚重复 → 索引取最后一条；替换也只落最后一条', () {
      const primary = [
        ReasoningGroup(anchorMessageId: 'a1', text: ''),
        ReasoningGroup(anchorMessageId: 'a1', text: ''),
      ];
      final merged = ReasoningGroup.merging(
        primaryGroups: primary,
        fallbackGroups: const [
          ReasoningGroup(anchorMessageId: 'a1', text: '兜底'),
        ],
      );

      expect(merged, hasLength(2));
      expect(merged[0].text, '');
      expect(merged[1].text, '兜底');
    });

    test('追加后的 fallback 已入索引：后续同锚 fallback 再走命中分支', () {
      final merged = ReasoningGroup.merging(
        primaryGroups: const [],
        fallbackGroups: const [
          ReasoningGroup(anchorMessageId: 'a1', text: '第一条'),
          ReasoningGroup(anchorMessageId: 'a1', text: '第二条'),
        ],
      );

      // 第一条入索引时 text 非空 → 第二条命中但不替换（保持第一条）。
      expect(merged, hasLength(1));
      expect(merged.single.text, '第一条');
    });

    test('返回列表可写：向结果追加不影响 primary 入参', () {
      final primary = [const ReasoningGroup(anchorMessageId: 'a1', text: 't')];
      final merged = ReasoningGroup.merging(
        primaryGroups: primary,
        fallbackGroups: const [],
      );

      merged.add(const ReasoningGroup(text: '追加'));

      expect(merged, hasLength(2));
      expect(primary, hasLength(1));
    });
  });

  group('ReasoningGroup.coalescingByTurn（按用户回合整轮聚合）', () {
    test('≤1 组短路：原样返回同一实例', () {
      final none = <ReasoningGroup>[];
      final one = [const ReasoningGroup(anchorMessageId: 'm1', text: 't')];

      expect(
        identical(
          ReasoningGroup.coalescingByTurn(none, messages: const []),
          none,
        ),
        isTrue,
      );
      expect(
        identical(
          ReasoningGroup.coalescingByTurn(one, messages: const []),
          one,
        ),
        isTrue,
      );
    });

    test('同一用户回合内两组 → 合成一组，锚统一到回合内最早的 assistant，'
        '正文按入参顺序 \\n\\n 连接', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: 'r1'),
          ReasoningGroup(anchorMessageId: 'm2', text: 'r2'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, 'r1\n\nr2');
    });

    test('入参倒序时正文按入参顺序连接，但锚仍是回合内最早的 assistant', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'm2', text: '后'),
          ReasoningGroup(anchorMessageId: 'm1', text: '先'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, '后\n\n先');
    });

    test('不同用户回合 → 各成一组，锚保持各自回合最早的 assistant', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: 'r2'),
        ChatMessage(role: 'user', content: 'q2', messageId: 'u2'),
        ChatMessage(role: 'assistant', messageId: 'm3', reasoning: 'r3'),
        ChatMessage(role: 'assistant', messageId: 'm4', reasoning: 'r4'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: 'r1'),
          ReasoningGroup(anchorMessageId: 'm2', text: 'r2'),
          ReasoningGroup(anchorMessageId: 'm3', text: 'r3'),
          ReasoningGroup(anchorMessageId: 'm4', text: 'r4'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(2));
      expect(merged[0].anchorMessageId, 'm1');
      expect(merged[0].text, 'r1\n\nr2');
      expect(merged[1].anchorMessageId, 'm3');
      expect(merged[1].text, 'r3\n\nr4');
    });

    test('无用户边界 → 全部归 turn:start，锚取最早的 assistant', () {
      const messages = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: 'r1'),
          ReasoningGroup(anchorMessageId: 'm2', text: 'r2'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, 'r1\n\nr2');
    });

    test('null 锚的组自成一桶（turnAnchor 缺失 → 锚保持 null）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(text: '孤儿'),
          ReasoningGroup(anchorMessageId: 'm1', text: 'r1'),
          ReasoningGroup(anchorMessageId: 'm2', text: 'r2'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(2));
      expect(merged[0].anchorMessageId, isNull);
      expect(merged[0].text, '孤儿');
      expect(merged[1].anchorMessageId, 'm1');
      expect(merged[1].text, 'r1\n\nr2');
    });

    test('锚在 messages 中查不到 → 自成一桶且原锚保留', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'ghost', text: '死锚正文'),
          ReasoningGroup(anchorMessageId: 'm1', text: 'r1'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(2));
      expect(merged[0].anchorMessageId, 'ghost');
      expect(merged[0].text, '死锚正文');
      expect(merged[1].anchorMessageId, 'm1');
      expect(merged[1].text, 'r1');
    });

    test('锚指向 user 消息 id → 也能解出回合，锚归一到该回合最早的 assistant', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'u1', text: '挂到 user 上的推理'),
          ReasoningGroup(anchorMessageId: 'm1', text: 'r1'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, '挂到 user 上的推理\n\nr1');
    });

    test('拼接时逐段 trim 并丢弃空白段（不留多余分隔符）', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: 'r2'),
        ChatMessage(role: 'assistant', messageId: 'm3', reasoning: 'r3'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: '  A  '),
          ReasoningGroup(anchorMessageId: 'm2', text: '   '),
          ReasoningGroup(anchorMessageId: 'm3', text: '\nB\n'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.text, 'A\n\nB');
    });

    test('同回合全部为空白正文 → 组被丢弃，结果为空', () {
      const messages = [
        ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: ' '),
          ReasoningGroup(anchorMessageId: 'm2', text: ''),
        ],
        messages: messages,
      );

      expect(merged, isEmpty);
    });

    test('messageOffset 参与 raw 锚与 turnKey 的解析（同 offset 下可解出回合并聚合）', () {
      const messages = [
        ChatMessage(role: 'assistant', reasoning: 'r1'),
        ChatMessage(role: 'assistant', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'raw:2', text: 'r1'),
          ReasoningGroup(anchorMessageId: 'raw:3', text: 'r2'),
        ],
        messages: messages,
        messageOffset: 2,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'raw:2');
      expect(merged.single.text, 'r1\n\nr2');
    });
  });

  group('ReasoningGroup.coalescingAdjacent（聚合关闭语义：相邻段合并）', () {
    test('≤1 组短路：原样返回同一实例', () {
      final none = <ReasoningGroup>[];
      final one = [const ReasoningGroup(anchorMessageId: 'm1', text: 't')];

      expect(
        identical(
          ReasoningGroup.coalescingAdjacent(none, messages: const []),
          none,
        ),
        isTrue,
      );
      expect(
        identical(
          ReasoningGroup.coalescingAdjacent(one, messages: const []),
          one,
        ),
        isTrue,
      );
    });

    test('相邻锚、中间无任何消息 → 合并为一组，锚取先出现者，正文 trim 后 \\n\\n 连接', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistant('m2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: '  第一段  '),
          ReasoningGroup(anchorMessageId: 'm2', text: '\n第二段\n'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, '第一段\n\n第二段');
    });

    test('间隔内有 assistant 可见正文 → 不合并（被 text 打断）', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistant('mid', content: '可见正文'),
        _assistant('m2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: '第一段'),
          ReasoningGroup(anchorMessageId: 'm2', text: '第二段'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(2));
      expect(merged[0].anchorMessageId, 'm1');
      expect(merged[0].text, '第一段');
      expect(merged[1].anchorMessageId, 'm2');
      expect(merged[1].text, '第二段');
    });

    test('间隔内是工具调用消息（无可见正文）→ 不打断，照常合并', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistantToolsOnly('mid'),
        _assistant('m2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: '第一段'),
          ReasoningGroup(anchorMessageId: 'm2', text: '第二段'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, '第一段\n\n第二段');
    });

    test('间隔内 assistant 正文为纯空白 → 不算可见文本，照常合并', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistant('mid', content: '   '),
        _assistant('m2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: '第一段'),
          ReasoningGroup(anchorMessageId: 'm2', text: '第二段'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.text, '第一段\n\n第二段');
    });

    test('间隔内是 user 消息（换回合）→ 不打断，跨回合也合并（实现观察，见报告）', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _user('u2', content: 'q2'),
        _assistant('m2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: '回合一'),
          ReasoningGroup(anchorMessageId: 'm2', text: '回合二'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, '回合一\n\n回合二');
    });

    test('打断只看两锚之间：后一组自身的可见正文不打断', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistant('m2', content: '第二段自己的正文', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: '第一段'),
          ReasoningGroup(anchorMessageId: 'm2', text: '第二段'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, '第一段\n\n第二段');
    });

    test('三段链式全可合并 → 一组，锚取最早者，正文三段连接', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistant('m2', reasoning: 'r2'),
        _assistant('m3', reasoning: 'r3'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: 'A'),
          ReasoningGroup(anchorMessageId: 'm2', text: 'B'),
          ReasoningGroup(anchorMessageId: 'm3', text: 'C'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, 'A\n\nB\n\nC');
    });

    test('链式合并中途被正文打断 → 断点前一组、断点后一组', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistant('m2', reasoning: 'r2'),
        _assistant('mid', content: '打断'),
        _assistant('m3', reasoning: 'r3'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: 'A'),
          ReasoningGroup(anchorMessageId: 'm2', text: 'B'),
          ReasoningGroup(anchorMessageId: 'm3', text: 'C'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(2));
      expect(merged[0].anchorMessageId, 'm1');
      expect(merged[0].text, 'A\n\nB');
      expect(merged[1].anchorMessageId, 'm3');
      expect(merged[1].text, 'C');
    });

    test('入参倒序 → 先按消息下标升序重排再合并', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistant('m2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm2', text: 'B'),
          ReasoningGroup(anchorMessageId: 'm1', text: 'A'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.anchorMessageId, 'm1');
      expect(merged.single.text, 'A\n\nB');
    });

    test('锚为 null 的组排到最后且永不参与合并（index 为 null → canMerge 恒假）', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
      ];
      const input = [
        ReasoningGroup(text: '无锚'),
        ReasoningGroup(anchorMessageId: 'm1', text: '有锚'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        input,
        messages: messages,
      );

      expect(merged, hasLength(2));
      expect(merged[0].anchorMessageId, 'm1');
      expect(merged[0].text, '有锚');
      expect(merged[1].anchorMessageId, isNull);
      expect(merged[1].text, '无锚');
      // 未发生合并也返回新列表。
      expect(identical(merged, input), isFalse);
    });

    test('两个 null 锚的组各自成组（互不合并）', () {
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(text: 'a'),
          ReasoningGroup(text: 'b'),
        ],
        messages: const [],
      );

      expect(merged, hasLength(2));
      expect(merged.map((g) => g.text), unorderedEquals(['a', 'b']));
      expect(merged.every((g) => g.anchorMessageId == null), isTrue);
    });

    test('锚在 messages 中查不到 → 视作不可合并，排到有锚组之后', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'ghost', text: '死锚'),
          ReasoningGroup(anchorMessageId: 'm1', text: '有锚'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(2));
      expect(merged[0].anchorMessageId, 'm1');
      expect(merged[1].anchorMessageId, 'ghost');
    });

    test('同锚重复的两组 → 下标相同、区间为空 → 合并', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
      ];
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: 'A'),
          ReasoningGroup(anchorMessageId: 'm1', text: 'B'),
        ],
        messages: messages,
      );

      expect(merged, hasLength(1));
      expect(merged.single.text, 'A\n\nB');
    });

    test('空 messages + 两个有锚组 → 都解不出下标 → 保持两组', () {
      final merged = ReasoningGroup.coalescingAdjacent(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: 'A'),
          ReasoningGroup(anchorMessageId: 'm2', text: 'B'),
        ],
        messages: const [],
      );

      expect(merged, hasLength(2));
      expect(
        merged.map((g) => g.anchorMessageId),
        unorderedEquals(['m1', 'm2']),
      );
    });

    test('合并后再合并是幂等的（结果组只有一段，二次调用不再变化）', () {
      final messages = [
        _user('u1', content: 'q1'),
        _assistant('m1', reasoning: 'r1'),
        _assistant('m2', reasoning: 'r2'),
      ];
      const input = [
        ReasoningGroup(anchorMessageId: 'm1', text: 'A'),
        ReasoningGroup(anchorMessageId: 'm2', text: 'B'),
      ];
      final once = ReasoningGroup.coalescingAdjacent(input, messages: messages);
      final twice = ReasoningGroup.coalescingAdjacent(once, messages: messages);

      expect(once, hasLength(1));
      expect(twice, hasLength(1));
      expect(twice.single, once.single);
    });
  });

  group('ReasoningGroup 值相等阶梯（== / hashCode / toString）', () {
    test('两字段全同 → 相等（不同实例）；自反；反向；跨类型不等', () {
      const lhs = ReasoningGroup(anchorMessageId: 'a1', text: 't');
      const rhs = ReasoningGroup(anchorMessageId: 'a1', text: 't');

      expect(lhs == rhs, isTrue);
      expect(rhs == lhs, isTrue);
      expect(lhs == lhs, isTrue);
      expect(lhs == Object(), isFalse);
      final Object unrelated = 't';
      expect(lhs == unrelated, isFalse);
      expect(lhs.hashCode == rhs.hashCode, isTrue);
    });

    test('等值对象入 Set 去重为一条（不同实例，非 canonical 化）', () {
      final fields = ['a1', 't'];
      final first = ReasoningGroup(anchorMessageId: fields[0], text: fields[1]);
      final second = ReasoningGroup(anchorMessageId: fields[0], text: fields[1]);

      expect(identical(first, second), isFalse);
      expect(<Object>{first, second}, hasLength(1));
      expect(first.hashCode == second.hashCode, isTrue);
    });

    test('逐字段改一项即不等：anchorMessageId（含 null ↔ 值）/ text', () {
      const base = ReasoningGroup(anchorMessageId: 'a1', text: 't');

      expect(base == const ReasoningGroup(text: 't'), isFalse);
      expect(
        base == const ReasoningGroup(anchorMessageId: 'a2', text: 't'),
        isFalse,
      );
      expect(
        base == const ReasoningGroup(anchorMessageId: 'a1', text: 'T'),
        isFalse,
      );
      // text 不 trim：'a1'/'t' 与空白变体必须区分。
      expect(
        base == const ReasoningGroup(anchorMessageId: 'a1', text: ' t'),
        isFalse,
      );
      expect(
        base == const ReasoningGroup(anchorMessageId: ' a1', text: 't'),
        isFalse,
      );
      expect(base == const ReasoningGroup(anchorMessageId: 'a1', text: 't'), isTrue);
    });

    test('null 锚的等值：null ↔ null 相等，null ↔ 空串不等', () {
      const nullAnchor = ReasoningGroup(text: 't');

      expect(nullAnchor == const ReasoningGroup(text: 't'), isTrue);
      expect(
        nullAnchor == const ReasoningGroup(anchorMessageId: '', text: 't'),
        isFalse,
      );
      expect(
        nullAnchor.hashCode,
        const ReasoningGroup(text: 't').hashCode,
      );
    });

    test('等值对象的 hashCode 相等且稳定（同一实例重复取值一致）', () {
      const group = ReasoningGroup(anchorMessageId: 'a1', text: 't');

      expect(group.hashCode, group.hashCode);
      expect(group.hashCode, isA<int>());
      expect(
        const ReasoningGroup(anchorMessageId: 'a1', text: 't').hashCode,
        group.hashCode,
      );
    });

    test('toString 逐字段复读（含 null 锚）', () {
      expect(
        const ReasoningGroup(text: '思考').toString(),
        'ReasoningGroup(anchorMessageId: null, text: 思考)',
      );
      expect(
        const ReasoningGroup(anchorMessageId: 'm1', text: 't').toString(),
        'ReasoningGroup(anchorMessageId: m1, text: t)',
      );
    });

    test('工厂产物参与等值：coalescingByTurn 合成的组与手写同字段组相等', () {
      const messages = [
        ChatMessage(role: 'assistant', messageId: 'm1', reasoning: 'r1'),
        ChatMessage(role: 'assistant', messageId: 'm2', reasoning: 'r2'),
      ];
      final merged = ReasoningGroup.coalescingByTurn(
        const [
          ReasoningGroup(anchorMessageId: 'm1', text: 'r1'),
          ReasoningGroup(anchorMessageId: 'm2', text: 'r2'),
        ],
        messages: messages,
      );

      expect(merged.single, const ReasoningGroup(anchorMessageId: 'm1', text: 'r1\n\nr2'));
    });
  });
}
