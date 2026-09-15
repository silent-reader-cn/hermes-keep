import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

void main() {
  group('ToolCall（非 JSON 模型）', () {
    test('默认构造：live-tool- 前缀 id、startedAt 当前秒', () {
      final call = ToolCall(name: 'write_file');
      expect(call.id, startsWith('live-tool-'));
      expect(call.isCompleted, false);
      expect(
        call.startedAt,
        closeTo(DateTime.now().millisecondsSinceEpoch / 1000, 5),
      );
      expect(call.displayName, 'write_file');
      expect(ToolCall(name: '  ').displayName, 'Tool');
      expect(ToolCall().displayName, 'Tool');
    });
  });

  group('PersistedToolCall.fromJson', () {
    test('规格示例正常解析', () {
      final call = PersistedToolCall.fromJson({
        'name': 'write_file',
        'snippet': 'Wrote /tmp/a.txt',
        'tid': 'call_9',
        'assistant_msg_idx': 3,
        'args': {'path': '/tmp/a.txt'},
      });
      expect(call.name, 'write_file');
      expect(call.snippet, 'Wrote /tmp/a.txt');
      expect(call.tid, 'call_9');
      expect(call.assistantMsgIdx, 3);
      expect(call.args!['path'], const JsonString('/tmp/a.txt'));
    });

    test('assistant_msg_idx 与 camel 双键', () {
      expect(
        PersistedToolCall.fromJson({'assistantMsgIdx': 5}).assistantMsgIdx,
        5,
      );
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final call = PersistedToolCall.fromJson({
        'name': 1,
        'snippet': false,
        'tid': null,
        'assistant_msg_idx': 'oops',
        'args': 'not-an-object',
      });
      expect(call.name, '1');
      expect(call.snippet, 'false');
      expect(call.tid, isNull);
      expect(call.assistantMsgIdx, isNull);
      expect(call.args, isNull);
    });

    test('toolCall(fallbackIndex)：tid 优先，否则 persisted-tool-N', () {
      final withTid = PersistedToolCall.fromJson({'tid': ' call_1 '});
      final toolCall = withTid.toolCall(2);
      expect(toolCall.id, 'call_1');
      expect(toolCall.isCompleted, true);
      expect(toolCall.preview, withTid.snippet);

      final fallback = PersistedToolCall.fromJson({'name': 'x'}).toolCall(2);
      expect(fallback.id, 'persisted-tool-2');
    });
  });

  group('ToolCallGroup 基础', () {
    test('activityTitle / isComplete / hasFailedTool', () {
      final group = ToolCallGroup(
        anchorMessageID: 'a1',
        toolCalls: [
          ToolCall(name: 't1', isCompleted: true),
          ToolCall(name: 't2'),
        ],
      );
      expect(group.activityTitle, 't1, t2');
      expect(group.isComplete, false);
      expect(group.hasFailedTool, false);

      final failed = ToolCallGroup(
        toolCalls: [ToolCall(isError: true, isCompleted: true)],
      );
      expect(failed.isComplete, true);
      expect(failed.hasFailedTool, true);
    });

    test('localizedActivityTitle 本地化活动摘要', () {
      final l10nZh = const AppLocalizations(Locale('zh'));
      final l10nEn = const AppLocalizations(Locale('en'));

      final emptyGroup = ToolCallGroup(toolCalls: const []);
      expect(emptyGroup.localizedActivityTitle(l10nZh), '无工具');
      expect(emptyGroup.localizedActivityTitle(l10nEn), 'No tools');

      final group = ToolCallGroup(
        toolCalls: [
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'bash', isCompleted: true),
          ToolCall(name: 'write_file', isCompleted: true),
          ToolCall(name: 'execute_code', isCompleted: true),
        ],
      );
      // Top 3 distinct by frequency: 读取文件 ×3, 终端 ×1, 写入文件 ×1 (or 执行代码), then +1
      expect(group.localizedActivityTitle(l10nZh), contains('读取文件 \u00D73'));
      expect(group.localizedActivityTitle(l10nZh), contains('+1'));
      expect(
        group.localizedActivityTitle(l10nEn),
        contains('Read File \u00D73'),
      );
      expect(group.localizedActivityTitle(l10nEn), contains('+1'));
    });

    test('localizedActivityTitle：第三方 MCP 工具聚合为「外部工具 ×N」', () {
      final l10nZh = const AppLocalizations(Locale('zh'));
      final l10nEn = const AppLocalizations(Locale('en'));

      final group = ToolCallGroup(
        toolCalls: [
          ToolCall(name: 'mcp__github__create_issue', isCompleted: true),
          ToolCall(name: 'mcp__playwright__browser_click', isCompleted: true),
          ToolCall(name: 'mcp__blender__execute_blender_code', isCompleted: true),
          ToolCall(name: 'terminal', isCompleted: true),
        ],
      );
      // 三种不同 MCP 服务器归为同一「外部工具」条目 ×3，内置工具照常显示。
      expect(
        group.localizedActivityTitle(l10nZh),
        contains('外部工具 \u00D73'),
      );
      expect(group.localizedActivityTitle(l10nZh), contains('终端 \u00D71'));
      expect(
        group.localizedActivityTitle(l10nEn),
        contains('External Tools \u00D73'),
      );

      // isExternalMcp 判定：大小写不敏感、trim 容错、非前缀不误伤。
      expect(ToolCall(name: 'MCP__x__y').isExternalMcp, true);
      expect(ToolCall(name: ' mcp__x__y ').isExternalMcp, true);
      expect(ToolCall(name: 'mcp_x').isExternalMcp, false);
      expect(ToolCall(name: 'not_mcp__x').isExternalMcp, false);
    });
  });

  group('ToolCallGroup.groups 聚合', () {
    test('groupsFromPersistedToolCalls：coalesce=true 时按回合合并，coalesce=false 时保持一 anchor 一组', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm2'),
      ];
      final persisted = [
        const PersistedToolCall(
          name: 'write_file',
          tid: 'call_1',
          assistantMsgIdx: 1,
        ),
        const PersistedToolCall(
          name: 'read_file',
          tid: 'call_2',
          assistantMsgIdx: 2,
        ),
      ];

      final coalesced = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        coalesce: true,
      );
      expect(coalesced, hasLength(1));
      expect(coalesced.single.anchorMessageID, 'm1');
      expect(coalesced.single.toolCalls, hasLength(2));
      expect(coalesced.single.toolCalls[0].id, 'call_1');
      expect(coalesced.single.toolCalls[1].id, 'call_2');

      // coalesce=false 时间线新语义：m2 自身带可见正文，事件序 =
      // text(m1) → call_1 → text(m2) → call_2，正文是分隔符 → 拆两组穿插。
      final separated = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        coalesce: false,
      );
      expect(separated, hasLength(2));
      expect(separated[0].anchorMessageID, 'm1');
      expect(separated[0].toolCalls.single.id, 'call_1');
      expect(separated[1].anchorMessageID, 'm2');
      expect(separated[1].toolCalls.single.id, 'call_2');
    });

    test('coalesce=false 时被 text 打断的相邻工具拆分为两组（穿插呈现）', () {
      const persisted = [
        PersistedToolCall(
          name: 'write_file',
          tid: 'call_1',
          assistantMsgIdx: 1,
        ),
        PersistedToolCall(name: 'read_file', tid: 'call_2', assistantMsgIdx: 3),
      ];
      final brokenMessages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        const ChatMessage(
          role: 'assistant',
          content: '中间有可见文本，打断相邻聚合',
          messageId: 'm_break',
        ),
        const ChatMessage(role: 'assistant', content: 'b', messageId: 'm2'),
      ];
      final broken = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: brokenMessages,
        coalesce: false,
      );
      expect(broken, hasLength(2));
      expect(broken[0].anchorMessageID, 'm1');
      expect(broken[0].toolCalls.single.id, 'call_1');
      expect(broken[1].anchorMessageID, 'm2');
      expect(broken[1].toolCalls.single.id, 'call_2');
    });

    test('coalesce=false 时中间仅思考（无文本）不打断工具 → 仍合并为一组', () {
      const persisted = [
        PersistedToolCall(
          name: 'write_file',
          tid: 'call_1',
          assistantMsgIdx: 1,
        ),
        PersistedToolCall(name: 'read_file', tid: 'call_2', assistantMsgIdx: 3),
      ];
      final brokenMessages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm_think',
          reasoning: '我先思考一下再继续',
        ),
        const ChatMessage(role: 'assistant', messageId: 'm2'),
      ];
      // 关闭聚合语义：仅「可见文本」打断（text 才是分隔符），思考段不
      // 打断工具调用——think/tool 互相穿插时工具调用照常相邻合并。
      final broken = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: brokenMessages,
        coalesce: false,
      );
      // 结果：1 组（思考行 + 工具行混排，行序=时间线）。
      expect(broken, hasLength(1));
      expect(broken.single.anchorMessageID, 'm1');
      expect(broken.single.toolCalls, hasLength(3));
      expect(broken.single.toolCalls[0].id, 'call_1');
      expect(broken.single.toolCalls[1].isThinking, isTrue);
      expect(broken.single.toolCalls[1].thinking, '我先思考一下再继续');
      expect(broken.single.toolCalls[2].id, 'call_2');
    });

    test('coalesce=false 时正文打断工具与后续调用 → 正文前后分为两组（时间线穿插）', () {
      const persisted = [
        PersistedToolCall(
          name: 'write_file',
          tid: 'call_1',
          assistantMsgIdx: 1,
        ),
        PersistedToolCall(name: 'read_file', tid: 'call_2', assistantMsgIdx: 3),
      ];
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm_think',
          reasoning: '我先思考一下再继续',
        ),
        const ChatMessage(role: 'assistant', content: 'b', messageId: 'm2'),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        coalesce: false,
      );
      // text 是分隔符：call_1 与 think 夹在 a 与 b 之间（挂 m1 下方），call_2 位于 b 之后（挂 m2 下方）
      expect(groups, hasLength(2));
      expect(groups[0].anchorMessageID, 'm1');
      expect(groups[0].isAboveContent, false);
      expect(groups[0].toolCalls, hasLength(2));
      expect(groups[0].toolCalls[0].id, 'call_1');
      expect(groups[0].toolCalls[1].isThinking, true);
      expect(groups[1].anchorMessageID, 'm2');
      expect(groups[1].isAboveContent, false);
      expect(groups[1].toolCalls.single.id, 'call_2');
    });

    test('新语义时间线：首段思考在上、中间工具+思考在两正文之间（tools在前think在后）、末段工具在下', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          content: 'text 1',
          messageId: 'm1',
          reasoning: 'think 1',
        ),
        const ChatMessage(
          role: 'assistant',
          content: 'text 2',
          messageId: 'm2',
          reasoning: 'think 2',
        ),
      ];
      final persisted = [
        const PersistedToolCall(name: 'tool_1', tid: 't1', assistantMsgIdx: 1),
        const PersistedToolCall(name: 'tool_2', tid: 't2', assistantMsgIdx: 2),
      ];

      // 聚合关：按正文切分区间
      final groups = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        coalesce: false,
      );

      // 结果为 3 组：
      // 1. 首段文本之前的 think(m1) → isAboveContent=true，anchor=m1
      // 2. tools(m1)+think(m2) → isAboveContent=false，anchor=m1，行序 tools 在前、think 在后
      // 3. tools(m2) → isAboveContent=false，anchor=m2
      expect(groups, hasLength(3));

      expect(groups[0].anchorMessageID, 'm1');
      expect(groups[0].isAboveContent, true);
      expect(groups[0].toolCalls.single.isThinking, true);
      expect(groups[0].toolCalls.single.thinking, 'think 1');

      expect(groups[1].anchorMessageID, 'm1');
      expect(groups[1].isAboveContent, false);
      expect(groups[1].toolCalls, hasLength(2));
      expect(groups[1].toolCalls[0].id, 't1');
      expect(groups[1].toolCalls[1].isThinking, true);
      expect(groups[1].toolCalls[1].thinking, 'think 2');

      expect(groups[2].anchorMessageID, 'm2');
      expect(groups[2].isAboveContent, false);
      expect(groups[2].toolCalls.single.id, 't2');

      // 聚合开：整回合合并为一张大卡，钉在首条正文上方
      final coalesced = ToolCallGroup.groups(
        persistedToolCalls: persisted,
        messages: messages,
        coalesce: true,
      );
      expect(coalesced, hasLength(1));
      expect(coalesced.single.anchorMessageID, 'm1');
      expect(coalesced.single.isAboveContent, true);
      expect(coalesced.single.toolCalls, hasLength(4));
      expect(coalesced.single.toolCalls[0].thinking, 'think 1');
      expect(coalesced.single.toolCalls[1].id, 't1');
      expect(coalesced.single.toolCalls[2].thinking, 'think 2');
      expect(coalesced.single.toolCalls[3].id, 't2');
    });

    test('无持久化调用时从消息元数据派生（OpenAI tool_calls）', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_x'),
              'function': JsonObject({
                'name': JsonString('bash'),
                'arguments': JsonString('{"cmd": "ls"}'),
              }),
            }),
          ],
        ),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: const [],
        messages: messages,
      );
      expect(groups, hasLength(1));
      final call = groups.single.toolCalls.single;
      expect(call.id, 'call_x');
      expect(call.name, 'bash');
      expect(call.args!['cmd'], const JsonString('ls'));
      expect(call.isCompleted, true);
    });

    test('合并 + 按 assistant 回合去重（uniqueToolCalls）', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_x'),
              'function': JsonObject({
                'name': JsonString('bash'),
                'arguments': JsonString('{"cmd": "ls"}'),
              }),
            }),
          ],
        ),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: [
          const PersistedToolCall(
            name: 'bash',
            tid: 'call_x',
            assistantMsgIdx: 1,
            args: {'cmd': JsonString('ls')},
          ),
        ],
        messages: messages,
      );
      expect(groups, hasLength(1));
      expect(groups.single.toolCalls, hasLength(1));
    });

    test('messageOffset 参与 raw index 换算', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: [
          const PersistedToolCall(name: 'x', assistantMsgIdx: 5),
        ],
        messages: messages,
        messageOffset: 4,
      );
      expect(groups, hasLength(1));
      expect(groups.single.anchorMessageID, 'm1');
    });

    test('assistantMsgIdx 越界 / 缺失 → 跳过', () {
      final messages = [
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: [
          const PersistedToolCall(name: 'x', assistantMsgIdx: 99),
          const PersistedToolCall(name: 'y'),
        ],
        messages: messages,
      );
      expect(groups, isEmpty);
    });
  });

  test('ToolCallGroupAnchorLookup', () {
    final lookup = ToolCallGroupAnchorLookup(
      groups: [
        ToolCallGroup(anchorMessageID: 'a', toolCalls: [ToolCall()]),
        ToolCallGroup(toolCalls: [ToolCall()]),
      ],
    );
    expect(lookup.groups(anchorMessageID: 'a'), hasLength(1));
    expect(lookup.groups(anchorMessageID: null), hasLength(1));
    expect(lookup.groups(anchorMessageID: 'zz'), isEmpty);
  });

  group('toolCallSummary', () {
    test('读文件类：提取文件名与行/偏移后缀', () {
      final call1 = ToolCall(
        name: 'read_file',
        args: {
          'file_path': const JsonString('/Users/dev/project/src/main.dart'),
          'line_start': const JsonNumber(10),
          'line_end': const JsonNumber(50),
        },
      );
      expect(call1.summary, 'main.dart:10-50');

      final call2 = ToolCall(
        name: 'read',
        args: {
          'path': const JsonString(r'C:\workspace\app\config.json'),
          'offset': const JsonNumber(100),
        },
      );
      expect(call2.summary, 'config.json:100');

      final call3 = ToolCall(
        name: 'view',
        args: {
          'filename': const JsonString('app.dart'),
          'start_line': const JsonNumber(5),
        },
      );
      expect(call3.summary, 'app.dart:5');

      final call4 = ToolCall(
        name: 'cat',
        args: {'file': const JsonString('pubspec.yaml')},
      );
      expect(call4.summary, 'pubspec.yaml');
    });

    test('写/编辑类：提取文件名与行范围', () {
      final call1 = ToolCall(
        name: 'write_file',
        args: {
          'target_file': const JsonString('lib/features/chat/chat_page.dart'),
        },
      );
      expect(call1.summary, 'chat_page.dart');

      final call2 = ToolCall(
        name: 'edit',
        args: {
          'filepath': const JsonString('/tmp/test.dart'),
          'line_start': const JsonNumber(1),
          'line_end': const JsonNumber(20),
        },
      );
      expect(call2.summary, 'test.dart:1-20');

      final call3 = ToolCall(
        name: 'str_replace',
        args: {'path': const JsonString('README.md')},
      );
      expect(call3.summary, 'README.md');
    });

    test('终端类：提取命令去换行并截断 40 字符', () {
      final call1 = ToolCall(
        name: 'bash',
        args: {'command': const JsonString('flutter test\n--coverage')},
      );
      expect(call1.summary, 'flutter test --coverage');

      final longCmd =
          'git commit -m "feat: very long commit message that exceeds 40 characters easily"';
      final call2 = ToolCall(name: 'exec', args: {'cmd': JsonString(longCmd)});
      expect(call2.summary, longCmd.substring(0, 40));
    });

    test('搜索类：pattern + path 组合', () {
      final call1 = ToolCall(
        name: 'grep',
        args: {
          'pattern': const JsonString('toolCallSummary'),
          'path': const JsonString('lib/core/models/tool_call.dart'),
        },
      );
      expect(call1.summary, 'toolCallSummary tool_call.dart');

      final call2 = ToolCall(
        name: 'search',
        args: {'query': const JsonString('Flutter')},
      );
      expect(call2.summary, 'Flutter');
    });

    test('列表类：pattern + path', () {
      final call1 = ToolCall(
        name: 'glob',
        args: {
          'pattern': const JsonString('*.dart'),
          'path': const JsonString('/src/lib'),
        },
      );
      expect(call1.summary, '*.dart lib');

      final call2 = ToolCall(
        name: 'ls',
        args: {'path': const JsonString('/Users/admin/docs')},
      );
      expect(call2.summary, 'docs');
    });

    test('todo/task 类：匹配键含 todo/task/title/content', () {
      final call1 = ToolCall(
        name: 'task_manager',
        args: {'todo_title': const JsonString('Fix layout bug')},
      );
      expect(call1.summary, 'Fix layout bug');

      final call2 = ToolCall(
        name: 'note',
        args: {'content': const JsonString('Meeting at 3pm')},
      );
      expect(call2.summary, 'Meeting at 3pm');
    });

    test('Generic fallback：未命中特定分类时取第一个非空字符串值', () {
      final call = ToolCall(
        name: 'unknown_tool',
        args: {
          'extra': const JsonNull(),
          'message': const JsonString('Custom payload string'),
        },
      );
      expect(call.summary, 'Custom payload string');
    });

    test('Preview fallback：args 为空时回退到 preview', () {
      final call1 = ToolCall(
        name: 'custom',
        preview: '  Wrote 12 lines to file.txt \n  ',
      );
      expect(call1.summary, 'Wrote 12 lines to file.txt');

      final call2 = ToolCall(name: 'custom');
      expect(call2.summary, isNull);
    });
  });

  group('TASK #112 归档组死锚与指纹去重', () {
    test('归档组锚 = 流式 id + 派生组锚 = raw: → re-anchor/指纹去重后单卡', () {
      final derivedGroup = ToolCallGroup(
        id: 'persisted-tools-raw:1',
        anchorMessageID: 'raw:1',
        toolCalls: [
          ToolCall(
            id: 'call_1',
            name: 'terminal',
            args: {'cmd': const JsonString('ls')},
            isCompleted: true,
          ),
        ],
      );
      final archivedGroup = ToolCallGroup(
        id: 'live-archive-group',
        anchorMessageID: 'stream-temp-uuid',
        toolCalls: [
          ToolCall(
            id: 'live-tool-0',
            name: 'terminal',
            args: {'cmd': const JsonString('ls')},
            isCompleted: true,
          ),
        ],
      );

      final merged = ToolCallGroup.merging(
        primaryGroups: [derivedGroup],
        fallbackGroups: [archivedGroup],
      );

      expect(merged, hasLength(1));
      expect(merged.first.anchorMessageID, 'raw:1');
      expect(merged.first.toolCalls, hasLength(1));
    });

    test('指纹相等 → 去重', () {
      final groupA = ToolCallGroup(
        id: 'group-a',
        anchorMessageID: 'raw:1',
        toolCalls: [
          ToolCall.thinking('思考中...'),
          ToolCall(
            id: 'call_1',
            name: 'todo_list',
            args: {'action': const JsonString('show')},
          ),
        ],
      );
      final groupB = ToolCallGroup(
        id: 'group-b',
        anchorMessageID: 'dead-anchor-id',
        toolCalls: [
          ToolCall.thinking('思考中...'),
          ToolCall(
            id: 'live-todo',
            name: 'todo_list',
            args: {'action': const JsonString('show')},
          ),
        ],
      );

      final merged = ToolCallGroup.merging(
        primaryGroups: [groupA],
        fallbackGroups: [groupB],
      );

      expect(merged, hasLength(1));
      expect(merged.first.id, 'group-a');
      expect(merged.first.anchorMessageID, 'raw:1');
      expect(merged.first.toolCalls, hasLength(2));
    });

    test('指纹为子集 → 合并且不吞内容', () {
      final supersetGroup = ToolCallGroup(
        id: 'group-super',
        anchorMessageID: 'raw:1',
        toolCalls: [
          ToolCall.thinking('think1'),
          ToolCall(
            id: 'call_1',
            name: 'terminal',
            args: {'cmd': const JsonString('ls')},
          ),
          ToolCall.thinking('think2'),
          ToolCall(
            id: 'call_2',
            name: 'terminal',
            args: {'cmd': const JsonString('pwd')},
          ),
        ],
      );
      final subsetGroup = ToolCallGroup(
        id: 'group-sub',
        anchorMessageID: 'stream-ghost-id',
        toolCalls: [
          ToolCall.thinking('think1'),
          ToolCall(
            id: 'live-1',
            name: 'terminal',
            args: {'cmd': const JsonString('ls')},
            duration: 42,
          ),
        ],
      );

      final merged = ToolCallGroup.merging(
        primaryGroups: [supersetGroup],
        fallbackGroups: [subsetGroup],
      );

      expect(merged, hasLength(1));
      expect(merged.first.id, 'group-super');
      expect(merged.first.toolCalls, hasLength(4));
      expect(
        merged.first.toolCalls
            .map((c) => c.isThinking ? c.thinking : c.name)
            .toList(),
        ['think1', 'terminal', 'think2', 'terminal'],
      );
      expect(merged.first.toolCalls[1].duration, 42);
    });
  });
}
