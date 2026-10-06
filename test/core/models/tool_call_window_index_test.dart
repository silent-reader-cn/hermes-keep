import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';

/// 守卫：`ToolCallGroup._groupsFromPersistedToolCalls` 对 `assistant_msg_idx` 的窗口下标解析。
///
/// ## 缺陷（本文件固化修复后的行为）
///
/// 服务端（hermes-webui 分页响应，`api/routes.py::_tool_calls_for_message_window()`）
/// 在返回分页窗口时已把 `assistant_msg_idx` **rebase 成窗口内相对下标**
/// （`rebased["assistant_msg_idx"] = assistant_idx - start_idx`）。
/// 客户端旧实现一律按「全转写坐标」解释：
///
/// ```dart
/// final loadedMessageIndex = assistantMsgIdx - offset; // offset = messageOffset
/// if (loadedMessageIndex < 0 || loadedMessageIndex >= messages.length) continue;
/// ```
///
/// 于是 `offset > 0` 的窗口里 `assistantMsgIdx - offset` 恒为负 → **整批 persisted
/// 工具调用被静默丢弃**，`ToolCallGroup.groups()` 回落到窗口内消息元数据派生：
/// 真机现象是转写区工具卡的工具数错（该轮真值 1 个，界面显示 10~56 个）与卡位错。
///
/// 修法（`_resolveLoadedMessageIndex`）：相对 / 绝对两解都算，越界剔除；唯一解直接用；
/// 两解都在窗口内（重叠）时先用 `tid` 与消息内工具 id 自证，认不出则回落「相对」（新版口径）；
/// 任何 null / 非法值保守回落，解析路径永不抛异常。
///
/// ## RED 判据
///
/// 用例 1（`persisted 全部锚定`）在未修版本上产出 **0 次**工具调用（整批丢弃），
/// 修复后为 12 次——把 `_resolveLoadedMessageIndex` 换回 `assistantMsgIdx - offset`
/// 即精确变红。
void main() {
  group('persisted 工具调用窗口下标解析', () {
    test('窗口相对下标（新版服务端 rebase）+ offset>0：95 条窗口里 12 条 persisted 全部锚定', () {
      final messages = _realShapeWindow(messageCount: 95, toolCallCount: 12);

      final persisted = <PersistedToolCall>[
        for (var k = 0; k < 12; k++)
          PersistedToolCall(
            name: 'terminal',
            tid: 'call_$k',
            assistantMsgIdx: k * 2,
            snippet: '服务端摘要 $k',
          ),
      ];

      final groups = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        messageOffset: 159,
        coalesce: false,
      );

      final calls = groups.expand((group) => group.toolCalls).toList();
      // 未修版本：persisted 整批被丢（0 次）；修复后：12 次。
      expect(calls, hasLength(12));
      expect(groups, hasLength(12));
      expect(groups.map((group) => group.anchorMessageID).toList(), [
        'm0',
        'm2',
        'm4',
        'm6',
        'm8',
        'm10',
        'm12',
        'm14',
        'm16',
        'm18',
        'm20',
        'm22',
      ]);
      expect(calls.map((call) => call.id).toList(), [
        for (var k = 0; k < 12; k++) 'call_$k',
      ]);
      // 锚点必须落在对应 assistant 消息上（而非工具结果行 / 窗口首条）。
      final indexByAnchor = <String, int>{
        for (var i = 0; i < messages.length; i++)
          if (messages[i].messageId != null) messages[i].messageId!: i,
      };
      for (var g = 0; g < groups.length; g++) {
        final anchor = groups[g].anchorMessageID;
        expect(anchor, isNotNull);
        final messageIndex = indexByAnchor[anchor!];
        expect(messageIndex, isNotNull);
        expect(messages[messageIndex!].role, 'assistant');
        expect(messageIndex, g * 2);
      }
      // 摘要来自服务端 persisted 载荷（而非窗口内派生）。
      expect(calls.map((call) => call.preview).toList(), [
        for (var k = 0; k < 12; k++) '服务端摘要 $k',
      ]);
    });

    test('真实完整形态：assistant 消息自带 tool_calls（与 tid 一致）时 persisted 载荷仍为权威', () {
      final messages = _realShapeWindow(
        messageCount: 95,
        toolCallCount: 12,
        assistantCarriesToolCalls: true,
      );

      final persisted = <PersistedToolCall>[
        for (var k = 0; k < 12; k++)
          PersistedToolCall(
            name: 'terminal',
            tid: 'call_$k',
            assistantMsgIdx: k * 2,
            snippet: '服务端摘要 $k',
            args: const {'cmd': JsonString('ls')},
          ),
      ];

      final groups = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        messageOffset: 159,
        coalesce: false,
      );

      final calls = groups.expand((group) => group.toolCalls).toList();
      expect(calls, hasLength(12));
      expect(calls.map((call) => call.id).toList(), [
        for (var k = 0; k < 12; k++) 'call_$k',
      ]);
      // persisted 载荷优先于消息元数据派生：snippet / args 只有 persisted 有。
      expect(calls.map((call) => call.preview).toList(), [
        for (var k = 0; k < 12; k++) '服务端摘要 $k',
      ]);
      expect(
        calls.every((call) => call.args?['cmd'] == const JsonString('ls')),
        isTrue,
      );
    });

    test('旧版绝对坐标（全转写坐标 + offset）：仍按绝对解锚定', () {
      final messages = <ChatMessage>[
        for (var i = 0; i < 10; i++)
          ChatMessage(role: 'assistant', content: '正文 $i', messageId: 'm$i'),
      ];
      final persisted = <PersistedToolCall>[
        const PersistedToolCall(
          name: 'terminal',
          tid: 'call_0',
          assistantMsgIdx: 20,
        ),
        const PersistedToolCall(
          name: 'terminal',
          tid: 'call_1',
          assistantMsgIdx: 22,
        ),
      ];

      final groups = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        messageOffset: 20,
        coalesce: false,
      );

      expect(groups, hasLength(2));
      expect(groups[0].anchorMessageID, 'm0');
      expect(groups[0].toolCalls.single.id, 'call_0');
      expect(groups[1].anchorMessageID, 'm2');
      expect(groups[1].toolCalls.single.id, 'call_1');
    });

    test('越界：两种解释都落在窗口外 → 静默丢弃，不抛异常', () {
      final messages = <ChatMessage>[
        for (var i = 0; i < 5; i++)
          ChatMessage(role: 'assistant', content: '正文 $i', messageId: 'm$i'),
      ];

      final farOut = ToolCallGroup.groups(
        persistedToolCalls: const [
          // 相对 500 / 绝对 500-100=400 都在窗口外。
          PersistedToolCall(
            name: 'terminal',
            tid: 'call_far',
            assistantMsgIdx: 500,
          ),
        ],
        messages: messages,
        messageOffset: 100,
        coalesce: false,
      );
      expect(farOut, isEmpty);

      final badValues = ToolCallGroup.groups(
        persistedToolCalls: const [
          // 相对 -3 / 绝对 -103 都为负。
          PersistedToolCall(
            name: 'terminal',
            tid: 'call_neg',
            assistantMsgIdx: -3,
          ),
          // 缺失 index。
          PersistedToolCall(name: 'terminal', tid: 'call_null'),
        ],
        messages: messages,
        messageOffset: 100,
        coalesce: false,
      );
      expect(badValues, isEmpty);
    });

    test('重叠歧义：相对与绝对都在窗口内时，优先按 tid 自证', () {
      // offset=5、窗口 10 条：idx=7 → 相对 7 / 绝对 2，两解都在窗口内。
      final messages = <ChatMessage>[
        const ChatMessage(role: 'assistant', content: '正文 0', messageId: 'm0'),
        const ChatMessage(role: 'assistant', content: '正文 1', messageId: 'm1'),
        const ChatMessage(
          role: 'assistant',
          content: '正文 2',
          messageId: 'm2',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_abs'),
              'function': JsonObject({
                'name': JsonString('terminal'),
                'arguments': JsonString('{}'),
              }),
            }),
          ],
        ),
        const ChatMessage(role: 'assistant', content: '正文 3', messageId: 'm3'),
        const ChatMessage(role: 'assistant', content: '正文 4', messageId: 'm4'),
        const ChatMessage(role: 'assistant', content: '正文 5', messageId: 'm5'),
        const ChatMessage(role: 'assistant', content: '正文 6', messageId: 'm6'),
        const ChatMessage(
          role: 'assistant',
          content: '正文 7',
          messageId: 'm7',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_rel'),
              'function': JsonObject({
                'name': JsonString('terminal'),
                'arguments': JsonString('{}'),
              }),
            }),
          ],
        ),
        const ChatMessage(role: 'assistant', content: '正文 8', messageId: 'm8'),
        const ChatMessage(role: 'assistant', content: '正文 9', messageId: 'm9'),
      ];

      String? anchorOf(String tid) {
        final groups = ToolCallGroup.groups(
          persistedToolCalls: [
            PersistedToolCall(name: 'terminal', tid: tid, assistantMsgIdx: 7),
          ],
          messages: messages,
          messageOffset: 5,
          coalesce: false,
        );
        final hits = [
          for (final group in groups)
            for (final call in group.toolCalls)
              if (call.id == tid) group.anchorMessageID,
        ];
        expect(hits, hasLength(1), reason: 'tid=$tid 应恰好锚定一次');
        return hits.single;
      }

      // tid 只在「绝对解」（m2）里出现 → 选绝对解。
      expect(anchorOf('call_abs'), 'm2');
      // tid 只在「相对解」（m7）里出现 → 选相对解。
      expect(anchorOf('call_rel'), 'm7');
      // 两解都无法自证 → 回落「相对」（新版服务端口径）＝ m7。
      expect(anchorOf('call_unknown'), 'm7');
    });

    test('全量响应（messageOffset 为 null / 0）行为不变', () {
      final messages = <ChatMessage>[
        const ChatMessage(role: 'assistant', content: '正文 0', messageId: 'm0'),
        const ChatMessage(role: 'assistant', content: '正文 1', messageId: 'm1'),
        const ChatMessage(role: 'assistant', content: '正文 2', messageId: 'm2'),
      ];
      const persisted = [
        PersistedToolCall(name: 'terminal', tid: 'call_0', assistantMsgIdx: 0),
        PersistedToolCall(name: 'terminal', tid: 'call_1', assistantMsgIdx: 2),
      ];

      final withoutOffset = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        coalesce: false,
      );
      expect(withoutOffset.map((g) => g.anchorMessageID).toList(), [
        'm0',
        'm2',
      ]);
      expect(
        withoutOffset.expand((g) => g.toolCalls).map((c) => c.id).toList(),
        ['call_0', 'call_1'],
      );

      final zeroOffset = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        messageOffset: 0,
        coalesce: false,
      );
      expect(zeroOffset.map((g) => g.anchorMessageID).toList(), ['m0', 'm2']);
      expect(zeroOffset.expand((g) => g.toolCalls).map((c) => c.id).toList(), [
        'call_0',
        'call_1',
      ]);

      // 旧版绝对坐标在全量响应下等价于直接用 idx（offset=0）。
      final legacyFull = ToolCallGroup.groups(
        persistedToolCalls: const [
          PersistedToolCall(
            name: 'terminal',
            tid: 'call_2',
            assistantMsgIdx: 1,
          ),
        ],
        messages: messages,
        messageOffset: 0,
        coalesce: false,
      );
      expect(legacyFull.single.anchorMessageID, 'm1');
    });
  });
}

/// 实测形状（2026-10-06 会话 763cc412ed0a，`/api/session?messages=1&msg_limit=50`）：
/// 95 条消息的窗口 + `_messages_offset = 159`；返回的 12 条 persisted 调用
/// `assistant_msg_idx` 为窗口相对下标 [0,2,4,…,22]，其 tid 与窗口内工具 id 一一对应。
///
/// 消息构成：`toolCallCount` 组「assistant（正文）→ tool（结果）」交替行，其后用空正文
/// assistant 补足到 [messageCount] 条（模拟窗口内其余消息）。
/// [assistantCarriesToolCalls] 打开时 assistant 行额外携带与服务端一致的 `tool_calls`。
List<ChatMessage> _realShapeWindow({
  required int messageCount,
  required int toolCallCount,
  bool assistantCarriesToolCalls = false,
}) {
  final messages = <ChatMessage>[];
  for (var i = 0; i < messageCount; i++) {
    final k = i ~/ 2;
    final inToolRun = i < toolCallCount * 2;
    if (inToolRun && i.isEven) {
      messages.add(
        ChatMessage(
          role: 'assistant',
          content: '正文 $k',
          messageId: 'm$i',
          toolCalls: assistantCarriesToolCalls
              ? [
                  JsonObject({
                    'id': JsonString('call_$k'),
                    'function': const JsonObject({
                      'name': JsonString('terminal'),
                      'arguments': JsonString('{}'),
                    }),
                  }),
                ]
              : null,
        ),
      );
    } else if (inToolRun) {
      messages.add(
        ChatMessage(role: 'tool', content: '窗口内工具结果 $k', toolCallId: 'call_$k'),
      );
    } else {
      messages.add(
        ChatMessage(role: 'assistant', content: '', messageId: 'm$i'),
      );
    }
  }
  return messages;
}
