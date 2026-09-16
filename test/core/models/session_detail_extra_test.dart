import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/session.dart';

/// session.dart 模型补测（覆盖率补强 · 批次 SS3，行 1120–1473 的 `SessionDetail`）。
///
/// 本类是本文件里**多键回退最多**的类，本文件按「一条回退链一组、一个键位一例」
/// 的粒度取证，预期值全部从实现读出来写死（不用 `isNotNull` 之类空断言充数）：
///
/// | 字段 | 键序（实现原文） |
/// |---|---|
/// | `contextLength` | `context_length` → `contextLength`（尾部 `?? lossyInt('context_length')` 是死代码） |
/// | `thresholdTokens` | `threshold_tokens` → `thresholdTokens`（同上） |
/// | `lastPromptTokens` | `last_prompt_tokens` → `lastPromptTokens`（同上） |
/// | `messagesTruncated` | `_messages_truncated` → `_messagesTruncated` → `messages_truncated` |
/// | `messagesOffset` | `_messages_offset` → `_messagesOffset` → `messages_offset` |
/// | `compressionAnchorVisibleIdx` | `compression_anchor_visible_idx` → `compressionAnchorVisibleIdx` |
/// | `compressionAnchorMessageKey` | `compression_anchor_message_key` → `compressionAnchorMessageKey`（走 `firstKeyModel`/`optModel`：非 Map → 视为缺失） |
/// | `compressionAnchorSummary` | `compression_anchor_summary` → `compressionAnchorSummary` |
///
/// 每个主键位都显式断言「主键命中时别名被忽略（含 `false`/`''`/空 Map 这类
/// “有值但看起来空”的值）」与「主键缺失/null/错型时才回退到别名」。
///
/// 另覆盖：两级容错解码（`messages` / `tool_calls` 快慢路径）、`pendingAttachments`、
/// `id` 多级回退、`==` 42 字段阶梯 / `hashCode` / `toString`。
void main() {
  /// 全字段（42 项）JSON：既用于「正常解析」，也用于 `==` 阶梯的逐字段覆盖。
  Map<String, Object?> fullJson() => <String, Object?>{
    'session_id': 's1',
    'title': 't1',
    'workspace': 'w1',
    'model': 'm1',
    'model_provider': 'p1',
    'message_count': 1,
    'created_at': 1.5,
    'updated_at': 2.5,
    'last_message_at': 3.5,
    'pinned': true,
    'archived': true,
    'project_id': 'proj1',
    'profile': 'prof1',
    'input_tokens': 10,
    'output_tokens': 20,
    'estimated_cost': 0.125,
    'active_stream_id': 'as1',
    'is_streaming': true,
    'is_cli_session': true,
    'user_message_count': 2,
    'pending_started_at': 4.5,
    'worktree_path': 'wt1',
    'source_tag': 'st1',
    'raw_source': 'rs1',
    'session_source': 'ss1',
    'source_label': 'sl1',
    'parent_session_id': 'ps1',
    'relationship_type': 'rt1',
    'read_only': true,
    'is_read_only': true,
    'pending_user_message': 'pum1',
    'pending_attachments': ['a1'],
    'context_length': 5,
    'threshold_tokens': 6,
    'last_prompt_tokens': 7,
    'messages': [
      {'role': 'user', 'content': 'hi'},
    ],
    'tool_calls': [
      {'name': 'tc1'},
    ],
    '_messages_truncated': true,
    '_messages_offset': 7,
    'compression_anchor_visible_idx': 3,
    'compression_anchor_message_key': {'role': 'assistant'},
    'compression_anchor_summary': 'sum',
  };

  /// 与 [fullJson] 一一对应的全字段实例（供 `==` / `hashCode` / `toString` 断言）。
  final full = SessionDetail.fromJson(fullJson());

  group('SessionDetail 构造 / 默认值', () {
    test('const 构造：全部字段默认 null', () {
      const s = SessionDetail();

      expect(s.sessionId, isNull);
      expect(s.title, isNull);
      expect(s.workspace, isNull);
      expect(s.model, isNull);
      expect(s.modelProvider, isNull);
      expect(s.messageCount, isNull);
      expect(s.createdAt, isNull);
      expect(s.updatedAt, isNull);
      expect(s.lastMessageAt, isNull);
      expect(s.pinned, isNull);
      expect(s.archived, isNull);
      expect(s.projectId, isNull);
      expect(s.profile, isNull);
      expect(s.inputTokens, isNull);
      expect(s.outputTokens, isNull);
      expect(s.estimatedCost, isNull);
      expect(s.activeStreamId, isNull);
      expect(s.isStreaming, isNull);
      expect(s.isCliSession, isNull);
      expect(s.userMessageCount, isNull);
      expect(s.pendingStartedAt, isNull);
      expect(s.worktreePath, isNull);
      expect(s.sourceTag, isNull);
      expect(s.rawSource, isNull);
      expect(s.sessionSource, isNull);
      expect(s.sourceLabel, isNull);
      expect(s.parentSessionId, isNull);
      expect(s.relationshipType, isNull);
      expect(s.readOnly, isNull);
      expect(s.isReadOnly, isNull);
      expect(s.pendingUserMessage, isNull);
      expect(s.pendingAttachments, isNull);
      expect(s.contextLength, isNull);
      expect(s.thresholdTokens, isNull);
      expect(s.lastPromptTokens, isNull);
      expect(s.messages, isNull);
      expect(s.toolCalls, isNull);
      expect(s.messagesTruncated, isNull);
      expect(s.messagesOffset, isNull);
      expect(s.compressionAnchorVisibleIdx, isNull);
      expect(s.compressionAnchorMessageKey, isNull);
      expect(s.compressionAnchorSummary, isNull);
      // 两个独立默认实例值相等（`==` 全字段链在“全 null”输入下逐行为真）
      expect(s, const SessionDetail());
      expect(s.hashCode, const SessionDetail().hashCode);
    });

    test('const 构造：显式字段原样保留，其余仍为 null', () {
      const s = SessionDetail(
        sessionId: 'x',
        messageCount: 3,
        pinned: false,
        messagesOffset: 0,
      );

      expect(s.sessionId, 'x');
      expect(s.messageCount, 3);
      expect(s.pinned, false);
      // 0 与 null 在 `==` 下不同，此处取证“0 不会被当成缺失”
      expect(s.messagesOffset, 0);
      expect(s == const SessionDetail(sessionId: 'x'), isFalse);
    });
  });

  group('SessionDetail.fromJson：标量字段', () {
    test('全字段正常解析（42 项与 full 实例值等）', () {
      final s = SessionDetail.fromJson(fullJson());

      expect(s, full);
      expect(s.sessionId, 's1');
      expect(s.title, 't1');
      expect(s.workspace, 'w1');
      expect(s.model, 'm1');
      expect(s.modelProvider, 'p1');
      expect(s.messageCount, 1);
      expect(s.createdAt, 1.5);
      expect(s.updatedAt, 2.5);
      expect(s.lastMessageAt, 3.5);
      expect(s.pinned, true);
      expect(s.archived, true);
      expect(s.projectId, 'proj1');
      expect(s.profile, 'prof1');
      expect(s.inputTokens, 10);
      expect(s.outputTokens, 20);
      expect(s.estimatedCost, 0.125);
      expect(s.activeStreamId, 'as1');
      expect(s.isStreaming, true);
      expect(s.isCliSession, true);
      expect(s.userMessageCount, 2);
      expect(s.pendingStartedAt, 4.5);
      expect(s.worktreePath, 'wt1');
      expect(s.sourceTag, 'st1');
      expect(s.rawSource, 'rs1');
      expect(s.sessionSource, 'ss1');
      expect(s.sourceLabel, 'sl1');
      expect(s.parentSessionId, 'ps1');
      expect(s.relationshipType, 'rt1');
      expect(s.readOnly, true);
      expect(s.isReadOnly, true);
      expect(s.pendingUserMessage, 'pum1');
      expect(s.contextLength, 5);
      expect(s.thresholdTokens, 6);
      expect(s.lastPromptTokens, 7);
      expect(s.messagesTruncated, true);
      expect(s.messagesOffset, 7);
      expect(s.compressionAnchorVisibleIdx, 3);
      expect(s.compressionAnchorSummary, 'sum');
      expect(s.compressionAnchorMessageKey, const CompressionAnchorMessageKey(role: 'assistant'));
    });

    test('空 map：标量全 null，集合字段也全 null', () {
      final s = SessionDetail.fromJson(const <String, Object?>{});

      expect(s, const SessionDetail());
      expect(s.messageCount, isNull);
      expect(s.createdAt, isNull);
      expect(s.pendingAttachments, isNull);
      expect(s.messages, isNull);
      expect(s.toolCalls, isNull);
      expect(s.messagesTruncated, isNull);
      expect(s.compressionAnchorMessageKey, isNull);
    });

    test('null 值：与键缺失等价（全部返回 null）', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'session_id': null,
        'title': null,
        'message_count': null,
        'created_at': null,
        'pinned': null,
        'pending_attachments': null,
        'messages': null,
        'tool_calls': null,
        '_messages_truncated': null,
        '_messages_offset': null,
        'compression_anchor_visible_idx': null,
        'compression_anchor_message_key': null,
        'compression_anchor_summary': null,
      });

      expect(s, const SessionDetail());
    });

    test('lossyString：int / double / bool 宽容转字符串，List / Map → null', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 42,
        'title': 1.5,
        'workspace': true,
        'model': false,
        'model_provider': <Object?>[],
        'project_id': <String, Object?>{},
      });

      expect(s.sessionId, '42');
      expect(s.title, '1.5');
      expect(s.workspace, 'true');
      expect(s.model, 'false');
      expect(s.modelProvider, isNull);
      expect(s.projectId, isNull);
    });

    test('lossyInt：double 向零截断 / 字符串解析 / 溢出与错型 → null', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'message_count': 2.9,
        'input_tokens': -2.9,
        'output_tokens': '  12  ',
        'user_message_count': '7.8',
        'context_length': 1e30,
        'threshold_tokens': double.infinity,
        'last_prompt_tokens': true,
        'messages_offset': <String, Object?>{'a': 1},
      });

      expect(s.messageCount, 2);
      expect(s.inputTokens, -2);
      expect(s.outputTokens, 12);
      expect(s.userMessageCount, 7);
      // 1e30 超出 int64 → null，且尾部 `?? lossyInt('context_length')` 同样是 null
      expect(s.contextLength, isNull);
      expect(s.thresholdTokens, isNull);
      expect(s.lastPromptTokens, isNull);
      expect(s.messagesOffset, isNull);
    });

    test('lossyDouble：int → double / 字符串解析 / 错型 → null', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'created_at': 3,
        'updated_at': '4.25',
        'last_message_at': 'x',
        'pending_started_at': <Object?>[],
        'estimated_cost': true,
      });

      expect(s.createdAt, 3.0);
      expect(s.updatedAt, 4.25);
      expect(s.lastMessageAt, isNull);
      expect(s.pendingStartedAt, isNull);
      expect(s.estimatedCost, isNull);
    });

    test('lossyBool：int 0/1 / 字符串族 / 其余错型 → null', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'pinned': 1,
        'archived': 0,
        'is_streaming': 'yes',
        'is_cli_session': 'NO',
        'read_only': 'TRUE',
        'is_read_only': 2,
      });

      expect(s.pinned, true);
      expect(s.archived, false);
      expect(s.isStreaming, true);
      expect(s.isCliSession, false);
      expect(s.readOnly, true);
      expect(s.isReadOnly, isNull);
    });

    test('错型成片：List / Map / 未知类型不抛异常', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'session_id': <Object?>[],
        'title': <String, Object?>{},
        'workspace': Object(),
        'message_count': <Object?>[],
        'created_at': <String, Object?>{},
        'pinned': <Object?>[],
      });

      expect(s.sessionId, isNull);
      expect(s.title, isNull);
      expect(s.workspace, isNull);
      expect(s.messageCount, isNull);
      expect(s.createdAt, isNull);
      expect(s.pinned, isNull);
    });
  });

  group('回退链 · contextLength（context_length → contextLength）', () {
    test('键位 1 命中：别名存在且值不同也被忽略', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'context_length': 100,
        'contextLength': 999,
      });

      expect(s.contextLength, 100);
    });

    test('键位 1 命中：值 0 有效（不被回退覆盖）', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'context_length': 0,
          'contextLength': 999,
        }).contextLength,
        0,
      );
    });

    test('键位 1 缺失 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'contextLength': 42},
        ).contextLength,
        42,
      );
    });

    test('键位 1 为 null → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'context_length': null,
          'contextLength': 42,
        }).contextLength,
        42,
      );
    });

    test('键位 1 错型（lossy 失败）→ 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'context_length': 'bad',
          'contextLength': 42,
        }).contextLength,
        42,
      );
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'context_length': 1e30,
          'contextLength': 42,
        }).contextLength,
        42,
      );
    });

    test('键位 1 错型但可宽容（字符串数字）→ 不回退', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'context_length': '55',
          'contextLength': 42,
        }).contextLength,
        55,
      );
    });

    test('两键皆缺失 / 皆无效 → null', () {
      expect(SessionDetail.fromJson(const <String, Object?>{}).contextLength, isNull);
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'context_length': 'bad',
          'contextLength': 'also-bad',
        }).contextLength,
        isNull,
      );
    });
  });

  group('回退链 · thresholdTokens（threshold_tokens → thresholdTokens）', () {
    test('键位 1 命中：别名被忽略', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'threshold_tokens': 1000,
          'thresholdTokens': 8888,
        }).thresholdTokens,
        1000,
      );
    });

    test('键位 1 缺失 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'thresholdTokens': 512},
        ).thresholdTokens,
        512,
      );
    });

    test('键位 1 为 null → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'threshold_tokens': null,
          'thresholdTokens': 512,
        }).thresholdTokens,
        512,
      );
    });

    test('键位 1 错型 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'threshold_tokens': <Object?>[],
          'thresholdTokens': 512,
        }).thresholdTokens,
        512,
      );
    });

    test('两键皆无效 → null', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'threshold_tokens': <Object?>[],
          'thresholdTokens': <String, Object?>{},
        }).thresholdTokens,
        isNull,
      );
    });
  });

  group('回退链 · lastPromptTokens（last_prompt_tokens → lastPromptTokens）', () {
    test('键位 1 命中：别名被忽略', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'last_prompt_tokens': 11,
          'lastPromptTokens': 22,
        }).lastPromptTokens,
        11,
      );
    });

    test('键位 1 缺失 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'lastPromptTokens': 22},
        ).lastPromptTokens,
        22,
      );
    });

    test('键位 1 为 null → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'last_prompt_tokens': null,
          'lastPromptTokens': 22,
        }).lastPromptTokens,
        22,
      );
    });

    test('键位 1 错型 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'last_prompt_tokens': true,
          'lastPromptTokens': 22,
        }).lastPromptTokens,
        22,
      );
    });

    test('两键皆无效 → null', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'last_prompt_tokens': <Object?>[],
          'lastPromptTokens': <String, Object?>{},
        }).lastPromptTokens,
        isNull,
      );
    });
  });

  group('回退链 · messagesTruncated（_messages_truncated → _messagesTruncated → messages_truncated）', () {
    test('键位 1 命中 true：后两键被忽略', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_truncated': true,
          '_messagesTruncated': false,
          'messages_truncated': false,
        }).messagesTruncated,
        true,
      );
    });

    test('键位 1 命中 false：false 也算命中，不被后两键的 true 抢走', () {
      // 取证点：firstKey 判的是「非 null」而非「非 falsy」，
      // 故 `_messages_truncated: false` 一旦有效，`messages_truncated: true` 必须被忽略。
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_truncated': false,
          '_messagesTruncated': true,
          'messages_truncated': true,
        }).messagesTruncated,
        false,
      );
    });

    test('键位 1 缺失 → 键位 2 生效（键位 3 被忽略）', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messagesTruncated': false,
          'messages_truncated': true,
        }).messagesTruncated,
        false,
      );
    });

    test('键位 1 为 null → 键位 2 生效', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_truncated': null,
          '_messagesTruncated': false,
          'messages_truncated': true,
        }).messagesTruncated,
        false,
      );
    });

    test('键位 1 错型 → 键位 2 生效', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_truncated': 'maybe',
          '_messagesTruncated': false,
          'messages_truncated': true,
        }).messagesTruncated,
        false,
      );
    });

    test('键位 1、2 皆缺失/无效 → 键位 3 兜底', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'messages_truncated': true},
        ).messagesTruncated,
        true,
      );
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_truncated': <Object?>[],
          '_messagesTruncated': null,
          'messages_truncated': false,
        }).messagesTruncated,
        false,
      );
    });

    test('三键全缺 → null', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{}).messagesTruncated,
        isNull,
      );
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_truncated': 'x',
          '_messagesTruncated': 2,
          'messages_truncated': <Object?>[],
        }).messagesTruncated,
        isNull,
      );
    });
  });

  group('回退链 · messagesOffset（_messages_offset → _messagesOffset → messages_offset）', () {
    test('键位 1 命中：后两键被忽略', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_offset': 10,
          '_messagesOffset': 20,
          'messages_offset': 30,
        }).messagesOffset,
        10,
      );
    });

    test('键位 1 命中 0：0 有效，不被回退覆盖', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_offset': 0,
          '_messagesOffset': 20,
          'messages_offset': 30,
        }).messagesOffset,
        0,
      );
    });

    test('键位 1 缺失 → 键位 2 生效', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messagesOffset': 20,
          'messages_offset': 30,
        }).messagesOffset,
        20,
      );
    });

    test('键位 1 为 null → 键位 2 生效', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_offset': null,
          '_messagesOffset': 20,
          'messages_offset': 30,
        }).messagesOffset,
        20,
      );
    });

    test('键位 1 错型 → 键位 2 生效', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_offset': <Object?>[],
          '_messagesOffset': 20,
          'messages_offset': 30,
        }).messagesOffset,
        20,
      );
    });

    test('键位 1、2 皆缺失/无效 → 键位 3 兜底', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'messages_offset': 30},
        ).messagesOffset,
        30,
      );
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_offset': true,
          '_messagesOffset': 'nope',
          'messages_offset': 30,
        }).messagesOffset,
        30,
      );
    });

    test('三键全缺/全无效 → null', () {
      expect(SessionDetail.fromJson(const <String, Object?>{}).messagesOffset, isNull);
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          '_messages_offset': <Object?>[],
          '_messagesOffset': <String, Object?>{},
          'messages_offset': 1e30,
        }).messagesOffset,
        isNull,
      );
    });
  });

  group('回退链 · compressionAnchorVisibleIdx', () {
    test('键位 1 命中：别名被忽略', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_visible_idx': 3,
          'compressionAnchorVisibleIdx': 99,
        }).compressionAnchorVisibleIdx,
        3,
      );
    });

    test('键位 1 命中 0：0 有效，不回退', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_visible_idx': 0,
          'compressionAnchorVisibleIdx': 99,
        }).compressionAnchorVisibleIdx,
        0,
      );
    });

    test('键位 1 缺失 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'compressionAnchorVisibleIdx': 99},
        ).compressionAnchorVisibleIdx,
        99,
      );
    });

    test('键位 1 为 null → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_visible_idx': null,
          'compressionAnchorVisibleIdx': 99,
        }).compressionAnchorVisibleIdx,
        99,
      );
    });

    test('键位 1 错型 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_visible_idx': <Object?>[],
          'compressionAnchorVisibleIdx': 99,
        }).compressionAnchorVisibleIdx,
        99,
      );
    });

    test('两键皆无效 → null', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_visible_idx': 'bad',
          'compressionAnchorVisibleIdx': 'bad',
        }).compressionAnchorVisibleIdx,
        isNull,
      );
    });
  });

  group('回退链 · compressionAnchorMessageKey（firstKeyModel / optModel 语义）', () {
    test('键位 1 命中：别名被忽略（值不同）', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'compression_anchor_message_key': {'role': 'user', 'ts': 1.5},
        'compressionAnchorMessageKey': {'role': 'assistant'},
      });

      expect(
        s.compressionAnchorMessageKey,
        const CompressionAnchorMessageKey(role: 'user', ts: 1.5),
      );
    });

    test('键位 1 命中空 Map：仍算命中（不回退到合法别名）', () {
      // optModel 只判 `value is Map`，空 Map 是合法入参 → 解析出全 null 的实例。
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_message_key': <String, Object?>{},
          'compressionAnchorMessageKey': {'role': 'assistant'},
        }).compressionAnchorMessageKey,
        const CompressionAnchorMessageKey(),
      );
    });

    test('键位 1 缺失 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compressionAnchorMessageKey': {'role': 'assistant', 'attachments': 2},
        }).compressionAnchorMessageKey,
        const CompressionAnchorMessageKey(role: 'assistant', attachments: 2),
      );
    });

    test('键位 1 为 null → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_message_key': null,
          'compressionAnchorMessageKey': {'text': 'hello'},
        }).compressionAnchorMessageKey,
        const CompressionAnchorMessageKey(text: 'hello'),
      );
    });

    test('键位 1 非 Map（字符串 / 数组 / 数字）→ 回退键位 2', () {
      for (final bad in const <Object>[
        'not-a-map',
        <Object?>[1, 2],
        7,
        true,
      ]) {
        expect(
          SessionDetail.fromJson(<String, Object?>{
            'compression_anchor_message_key': bad,
            'compressionAnchorMessageKey': <String, Object?>{'role': 'user'},
          }).compressionAnchorMessageKey,
          const CompressionAnchorMessageKey(role: 'user'),
          reason: '错型 $bad 应回退到别名',
        );
      }
    });

    test('键位 1 非 String 键的 Map → optModel 内部 catch 后回退键位 2', () {
      // `Map<String, Object?>.from` 对非 String 键抛 TypeError，被 optModel 吞掉 → 视为缺失。
      expect(
        SessionDetail.fromJson(<String, Object?>{
          'compression_anchor_message_key': <Object, Object>{1: 'x'},
          'compressionAnchorMessageKey': <String, Object?>{'role': 'user'},
        }).compressionAnchorMessageKey,
        const CompressionAnchorMessageKey(role: 'user'),
      );
    });

    test('两键皆缺失 / 皆错型 → null', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{}).compressionAnchorMessageKey,
        isNull,
      );
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_message_key': null,
          'compressionAnchorMessageKey': 'x',
        }).compressionAnchorMessageKey,
        isNull,
      );
    });

    test('firstKeyModel 直接调用：逐键尝试并在首命中处返回', () {
      const json = <String, Object?>{
        'a': null,
        'b': 'not-a-map',
        'c': <String, Object?>{'text': 'hit'},
        'd': <String, Object?>{'text': 'later'},
      };

      expect(
        SessionDetail.firstKeyModel<CompressionAnchorMessageKey>(
          json,
          const ['a', 'b', 'c', 'd'],
          CompressionAnchorMessageKey.fromJson,
        ),
        const CompressionAnchorMessageKey(text: 'hit'),
      );
      expect(
        SessionDetail.firstKeyModel<CompressionAnchorMessageKey>(
          json,
          const ['a', 'b'],
          CompressionAnchorMessageKey.fromJson,
        ),
        isNull,
      );
      expect(
        SessionDetail.firstKeyModel<CompressionAnchorMessageKey>(
          const <String, Object?>{},
          const ['missing'],
          CompressionAnchorMessageKey.fromJson,
        ),
        isNull,
      );
    });
  });

  group('回退链 · compressionAnchorSummary（compression_anchor_summary → compressionAnchorSummary）', () {
    test('键位 1 命中：别名被忽略', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_summary': 'primary',
          'compressionAnchorSummary': 'alias',
        }).compressionAnchorSummary,
        'primary',
      );
    });

    test('键位 1 命中空串：空串有效，不回退', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_summary': '',
          'compressionAnchorSummary': 'alias',
        }).compressionAnchorSummary,
        '',
      );
    });

    test('键位 1 缺失 → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'compressionAnchorSummary': 'alias'},
        ).compressionAnchorSummary,
        'alias',
      );
    });

    test('键位 1 为 null → 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_summary': null,
          'compressionAnchorSummary': 'alias',
        }).compressionAnchorSummary,
        'alias',
      );
    });

    test('键位 1 错型（List / Map）→ 回退键位 2', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_summary': <String, Object?>{},
          'compressionAnchorSummary': 'alias',
        }).compressionAnchorSummary,
        'alias',
      );
    });

    test('两键皆无效 → null', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'compression_anchor_summary': <Object?>[],
          'compressionAnchorSummary': <Object?>[],
        }).compressionAnchorSummary,
        isNull,
      );
    });
  });

  group('SessionDetail.fromJson：pendingAttachments（optJsonValueList）', () {
    test('缺失 / 非 List → null', () {
      expect(SessionDetail.fromJson(const <String, Object?>{}).pendingAttachments, isNull);
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'pending_attachments': 'x'},
        ).pendingAttachments,
        isNull,
      );
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'pending_attachments': <String, Object?>{}},
        ).pendingAttachments,
        isNull,
      );
    });

    test('空 List → 空列表（非 null）', () {
      final s = SessionDetail.fromJson(
        const <String, Object?>{'pending_attachments': <Object?>[]},
      );

      expect(s.pendingAttachments, isNotNull);
      expect(s.pendingAttachments, isEmpty);
    });

    test('异构元素逐个转 JsonValue（对象 / 数组 / 数字 / 字符串 / bool / null）', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'pending_attachments': <Object?>[
          'a1',
          2,
          true,
          null,
          {'k': 'v'},
          <Object?>[1],
        ],
      });

      expect(s.pendingAttachments, const <JsonValue>[
        JsonString('a1'),
        JsonNumber(2.0),
        JsonBool(true),
        JsonNull(),
        JsonObject(<String, JsonValue>{'k': JsonString('v')}),
        JsonArray(<JsonValue>[JsonNumber(1.0)]),
      ]);
      expect(s.pendingAttachments!.length, 6);
    });
  });

  group('SessionDetail.fromJson：messages 两级容错解码', () {
    test('缺失 / 非 List → null', () {
      expect(SessionDetail.fromJson(const <String, Object?>{}).messages, isNull);
      expect(
        SessionDetail.fromJson(const <String, Object?>{'messages': 'x'}).messages,
        isNull,
      );
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'messages': <String, Object?>{}},
        ).messages,
        isNull,
      );
    });

    test('空 List → 快路径返回空列表（非 null）', () {
      final s = SessionDetail.fromJson(
        const <String, Object?>{'messages': <Object?>[]},
      );

      expect(s.messages, isNotNull);
      expect(s.messages, isEmpty);
    });

    test('快路径：全为 Map → 整数组解析', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'messages': [
          {'role': 'user', 'content': 'hi'},
          {'role': 'assistant', 'content': 'yo'},
        ],
      });

      expect(s.messages, hasLength(2));
      expect(s.messages![0].role, 'user');
      expect(s.messages![0].content, 'hi');
      expect(s.messages![1].role, 'assistant');
    });

    test('慢路径：首元素非 Map → 仅保留 Map 元素，坏元素丢弃', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'messages': <Object?>[
          'bad',
          {'role': 'user', 'content': 'kept'},
          5,
          null,
        ],
      });

      expect(s.messages, hasLength(1));
      expect(s.messages!.single.role, 'user');
      expect(s.messages!.single.content, 'kept');
    });

    test('慢路径：全为坏元素 → null', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'messages': <Object?>['bad', 1, null]},
        ).messages,
        isNull,
      );
    });

    test('慢路径：非 String 键的 Map 经 JsonValue 字符串化键后仍可解析', () {
      final s = SessionDetail.fromJson(<String, Object?>{
        'messages': <Object, Object>{
          0: 'bad',
          1: <Object, Object>{1: 'x', 'role': 'user'},
        }.values.toList(),
      });

      expect(s.messages, hasLength(1));
      // 键 1 被 toString 成 '1'，不是已知字段 → role 取到显式值
      expect(s.messages!.single.role, 'user');
    });

    test('当前行为：快路径首元素为非 String 键 Map → TypeError 直穿（见报告实现观察）', () {
      // 快路径用 `Map<String, Object?>.from(element)`，未包 try/catch；
      // 与 optModelList 的「解码失败返回 null」语义不一致。
      expect(
        () => SessionDetail.fromJson(<String, Object?>{
          'messages': <Object>[
            <Object, Object>{1: 'x'},
          ],
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('SessionDetail.fromJson：toolCalls 两级容错解码', () {
    test('缺失 / 非 List → null', () {
      expect(SessionDetail.fromJson(const <String, Object?>{}).toolCalls, isNull);
      expect(
        SessionDetail.fromJson(const <String, Object?>{'tool_calls': 3}).toolCalls,
        isNull,
      );
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'tool_calls': <Object?>[]},
        ).toolCalls,
        isEmpty,
      );
    });

    test('快路径：全为 Map → 整数组解析', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'tool_calls': [
          {'name': 'a', 'snippet': 'sa', 'tid': 't1'},
          {'name': 'b', 'is_error': true},
        ],
      });

      expect(s.toolCalls, hasLength(2));
      expect(s.toolCalls![0].name, 'a');
      expect(s.toolCalls![0].snippet, 'sa');
      expect(s.toolCalls![0].tid, 't1');
      expect(s.toolCalls![1].name, 'b');
      expect(s.toolCalls![1].isError, true);
    });

    test('慢路径：坏元素丢弃，Map 元素保留', () {
      final s = SessionDetail.fromJson(const <String, Object?>{
        'tool_calls': <Object?>[
          'bad',
          {'name': 'kept'},
        ],
      });

      expect(s.toolCalls, hasLength(1));
      expect(s.toolCalls!.single.name, 'kept');
    });

    test('慢路径：全为坏元素 → null', () {
      expect(
        SessionDetail.fromJson(
          const <String, Object?>{'tool_calls': <Object?>['bad', 2]},
        ).toolCalls,
        isNull,
      );
    });

    test('当前行为：快路径首元素为非 String 键 Map → TypeError 直穿（见报告实现观察）', () {
      expect(
        () => SessionDetail.fromJson(<String, Object?>{
          'tool_calls': <Object>[
            <Object, Object>{1: 'x'},
          ],
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('SessionDetail.id 多级回退', () {
    test('sessionId 非空 → 原样返回（不 trim）', () {
      expect(const SessionDetail(sessionId: 's1').id, 's1');
      // 取证：空白 sessionId 也算“非空”，不会走 title 分支
      expect(const SessionDetail(sessionId: ' ').id, ' ');
      expect(
        SessionDetail.fromJson(const <String, Object?>{'session_id': ''}).id,
        isNot(''),
      );
    });

    test('sessionId 空串 → 落到 title 分支', () {
      // 取证：无时间戳时 `?? 0` 兜底字面量在本实现里渲染成 `0.0`（见下方探针用例）
      expect(const SessionDetail(sessionId: '', title: 'T').id, 'session-T-0.0');
    });

    test('title 缺失 → untitled 兜底', () {
      expect(const SessionDetail().id, 'session-untitled-0.0');
      expect(const SessionDetail(title: null).id, 'session-untitled-0.0');
    });

    test('title 被 trim；空串 title 不换成 untitled（当前行为）', () {
      expect(const SessionDetail(title: '  T  ').id, 'session-T-0.0');
      expect(const SessionDetail(title: '').id, 'session--0.0');
      expect(const SessionDetail(title: '   ').id, 'session--0.0');
    });

    test('时间戳回退：createdAt → updatedAt → lastMessageAt → 0', () {
      expect(
        const SessionDetail(title: 'T', createdAt: 1.5, updatedAt: 2.5).id,
        'session-T-1.5',
      );
      expect(
        const SessionDetail(title: 'T', updatedAt: 2.0, lastMessageAt: 3.5).id,
        'session-T-2.0',
      );
      expect(
        const SessionDetail(title: 'T', lastMessageAt: 3.5).id,
        'session-T-3.5',
      );
      expect(const SessionDetail(title: 'T').id, 'session-T-0.0');
      expect(const SessionDetail(title: 'T', createdAt: 0).id, 'session-T-0.0');
    });

    test('探针：`?? 0` 兜底的运行时类型是 double（故 id 里是 0.0）', () {
      // 与实现同形的表达式：double? ?? double? ?? double? ?? 0
      const double? createdAt = null;
      const double? updatedAt = null;
      const double? lastMessageAt = null;
      final timestamp = createdAt ?? updatedAt ?? lastMessageAt ?? 0;

      expect(timestamp, 0.0);
      expect(timestamp.runtimeType, double);
      expect('$timestamp', '0.0');
      // 有值时同样是 double 语义
      expect('${1.5}'.endsWith('.0'), isFalse);
    });

    test('fromJson 路径的 id（sessionId 缺失 → title + created_at）', () {
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'title': 'hey',
          'created_at': 9,
        }).id,
        'session-hey-9.0',
      );
      expect(
        SessionDetail.fromJson(const <String, Object?>{
          'session_id': '',
          'title': 'hey',
        }).id,
        'session-hey-0.0',
      );
    });
  });

  group('SessionDetail == / hashCode / toString', () {
    test('类型守卫：非 SessionDetail / null / 同形状 Map 均不等', () {
      final Object? nothing = null;
      final Object sameToString = 'SessionDetail(sessionId: s1, title: t1)';
      final Object sameShapeMap = fullJson();

      expect(full == Object(), isFalse);
      expect(full == sameToString, isFalse);
      expect(full == nothing, isFalse);
      expect(full == sameShapeMap, isFalse);
      expect(full == full, isTrue);
      expect(full == SessionDetail.fromJson(fullJson()), isTrue);
    });

    test('42 字段阶梯：逐项差一位全部不等（每个 && 行都执行）', () {
      // 顺序严格照 `operator ==` 的 && 链；每级保留前面所有级，
      // 故比较第 i 对时前 i 行都被执行 → 覆盖整条链。
      final steps = <String, Map<String, Object?>>{
        'sessionId': {'session_id': 's1'},
        'title': {'title': 't1'},
        'workspace': {'workspace': 'w1'},
        'model': {'model': 'm1'},
        'modelProvider': {'model_provider': 'p1'},
        'messageCount': {'message_count': 1},
        'createdAt': {'created_at': 1.5},
        'updatedAt': {'updated_at': 2.5},
        'lastMessageAt': {'last_message_at': 3.5},
        'pinned': {'pinned': true},
        'archived': {'archived': true},
        'projectId': {'project_id': 'proj1'},
        'profile': {'profile': 'prof1'},
        'inputTokens': {'input_tokens': 10},
        'outputTokens': {'output_tokens': 20},
        'estimatedCost': {'estimated_cost': 0.125},
        'activeStreamId': {'active_stream_id': 'as1'},
        'isStreaming': {'is_streaming': true},
        'isCliSession': {'is_cli_session': true},
        'userMessageCount': {'user_message_count': 2},
        'pendingStartedAt': {'pending_started_at': 4.5},
        'worktreePath': {'worktree_path': 'wt1'},
        'sourceTag': {'source_tag': 'st1'},
        'rawSource': {'raw_source': 'rs1'},
        'sessionSource': {'session_source': 'ss1'},
        'sourceLabel': {'source_label': 'sl1'},
        'parentSessionId': {'parent_session_id': 'ps1'},
        'relationshipType': {'relationship_type': 'rt1'},
        'readOnly': {'read_only': true},
        'isReadOnly': {'is_read_only': true},
        'pendingUserMessage': {'pending_user_message': 'pum1'},
        'pendingAttachments': {
          'pending_attachments': ['a1'],
        },
        'contextLength': {'context_length': 5},
        'thresholdTokens': {'threshold_tokens': 6},
        'lastPromptTokens': {'last_prompt_tokens': 7},
        'messages': {
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
        'toolCalls': {
          'tool_calls': [
            {'name': 'tc1'},
          ],
        },
        'messagesTruncated': {'_messages_truncated': true},
        'messagesOffset': {'_messages_offset': 7},
        'compressionAnchorVisibleIdx': {'compression_anchor_visible_idx': 3},
        'compressionAnchorMessageKey': {
          'compression_anchor_message_key': {'role': 'assistant'},
        },
        'compressionAnchorSummary': {'compression_anchor_summary': 'sum'},
      };

      final ladder = <SessionDetail>[const SessionDetail()];
      final acc = <String, Object?>{};
      for (final entry in steps.entries) {
        acc.addAll(entry.value);
        ladder.add(SessionDetail.fromJson(Map<String, Object?>.from(acc)));
      }

      // 1（全 null）+ 42（被比较字段）= 43 级
      expect(steps, hasLength(42));
      expect(ladder, hasLength(43));
      // 末级等于全字段实例：证明阶梯覆盖的正是 `==` 比较的字段全集
      expect(ladder.last, full);
      expect(ladder.last.hashCode, full.hashCode);

      for (var i = 0; i < ladder.length - 1; i++) {
        expect(
          ladder[i] == ladder[i + 1],
          isFalse,
          reason: '阶梯第 ${i + 1} 步应不等',
        );
        expect(
          ladder[i].hashCode == ladder[i + 1].hashCode,
          isFalse,
          reason: '阶梯第 ${i + 1} 步 hashCode 应不同',
        );
      }
    });

    test('集合字段阶梯：null ↔ 空 ↔ 长度不同 ↔ 元素不同 ↔ 同一实例', () {
      // pendingAttachments（走 deepHash / deepEquals）
      final attNull = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
      });
      final attEmpty = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'pending_attachments': <Object?>[],
      });
      final attA = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'pending_attachments': ['a'],
      });
      final attA2 = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'pending_attachments': ['a'],
      });
      final attB = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'pending_attachments': ['b'],
      });
      final attAB = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'pending_attachments': ['a', 'b'],
      });

      expect(attNull == attEmpty, isFalse);
      expect(attEmpty == attA, isFalse);
      expect(attA == attB, isFalse);
      expect(attA == attAB, isFalse);
      expect(attA == attA2, isTrue);
      expect(attA == attA, isTrue);
      expect(attA.hashCode, attA2.hashCode);
      // deepHash：元素值等（对象不同）→ 哈希一致（非 identity 哈希）
      expect(identical(attA.pendingAttachments, attA2.pendingAttachments), isFalse);
      expect(attA.hashCode, attA2.hashCode);

      // messages
      final msgNull = SessionDetail.fromJson(const <String, Object?>{'session_id': 's'});
      final msgEmpty = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'messages': <Object?>[],
      });
      final msgA = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'messages': [
          {'role': 'user', 'content': 'a'},
        ],
      });
      final msgA2 = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'messages': [
          {'role': 'user', 'content': 'a'},
        ],
      });
      final msgB = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'messages': [
          {'role': 'assistant', 'content': 'a'},
        ],
      });
      final msgAB = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'messages': [
          {'role': 'user', 'content': 'a'},
          {'role': 'assistant', 'content': 'b'},
        ],
      });

      expect(msgNull == msgEmpty, isFalse);
      expect(msgEmpty == msgA, isFalse);
      expect(msgA == msgB, isFalse);
      expect(msgA == msgAB, isFalse);
      expect(msgA == msgA2, isTrue);
      expect(msgA.hashCode, msgA2.hashCode);

      // toolCalls
      final tcNull = SessionDetail.fromJson(const <String, Object?>{'session_id': 's'});
      final tcEmpty = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'tool_calls': <Object?>[],
      });
      final tcA = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'tool_calls': [
          {'name': 'a'},
        ],
      });
      final tcA2 = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'tool_calls': [
          {'name': 'a'},
        ],
      });
      final tcB = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'tool_calls': [
          {'name': 'b'},
        ],
      });

      expect(tcNull == tcEmpty, isFalse);
      expect(tcEmpty == tcA, isFalse);
      expect(tcA == tcB, isFalse);
      expect(tcA == tcA2, isTrue);
      expect(tcA.hashCode, tcA2.hashCode);

      // compressionAnchorMessageKey（走 == / hashCode 而非 deep*）
      final keyNull = SessionDetail.fromJson(const <String, Object?>{'session_id': 's'});
      final keyEmpty = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'compression_anchor_message_key': <String, Object?>{},
      });
      final keyA = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'compression_anchor_message_key': {'role': 'a'},
      });
      final keyA2 = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'compression_anchor_message_key': {'role': 'a'},
      });
      final keyB = SessionDetail.fromJson(const <String, Object?>{
        'session_id': 's',
        'compression_anchor_message_key': {'role': 'b'},
      });

      expect(keyNull == keyEmpty, isFalse);
      expect(keyEmpty == keyA, isFalse);
      expect(keyA == keyB, isFalse);
      expect(keyA == keyA2, isTrue);
      expect(keyA.hashCode, keyA2.hashCode);
    });

    test('单字段差异：每个字段单独换值均不等（含布尔 false / 0 / 空串）', () {
      final variants = <String, SessionDetail>{
        'sessionId 空串': SessionDetail.fromJson({
          ...fullJson(),
          'session_id': '',
        }),
        'sessionId null': SessionDetail.fromJson({
          ...fullJson(),
          'session_id': null,
        }),
        'title 空串': SessionDetail.fromJson({...fullJson(), 'title': ''}),
        'pinned false': SessionDetail.fromJson({...fullJson(), 'pinned': false}),
        'archived false': SessionDetail.fromJson({...fullJson(), 'archived': false}),
        'messageCount 0': SessionDetail.fromJson({
          ...fullJson(),
          'message_count': 0,
        }),
        'messagesTruncated false': SessionDetail.fromJson({
          ...fullJson(),
          '_messages_truncated': false,
        }),
        'messagesOffset 0': SessionDetail.fromJson({
          ...fullJson(),
          '_messages_offset': 0,
        }),
        'compressionAnchorVisibleIdx 0': SessionDetail.fromJson({
          ...fullJson(),
          'compression_anchor_visible_idx': 0,
        }),
        'compressionAnchorSummary 空串': SessionDetail.fromJson({
          ...fullJson(),
          'compression_anchor_summary': '',
        }),
        'pendingAttachments null': SessionDetail.fromJson({
          ...fullJson(),
          'pending_attachments': null,
        }),
        'messages 空': SessionDetail.fromJson({
          ...fullJson(),
          'messages': <Object?>[],
        }),
        'toolCalls 空': SessionDetail.fromJson({
          ...fullJson(),
          'tool_calls': <Object?>[],
        }),
        'contextLength null': SessionDetail.fromJson({
          ...fullJson(),
          'context_length': null,
        }),
      };

      for (final entry in variants.entries) {
        expect(entry.value == full, isFalse, reason: entry.key);
      }
    });

    test('hashCode：值等实例哈希一致且稳定', () {
      final a = SessionDetail.fromJson(fullJson());
      final b = SessionDetail.fromJson(fullJson());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.hashCode, a.hashCode);
      expect(const SessionDetail().hashCode, const SessionDetail().hashCode);
    });

    test('toString：只含 sessionId 与 title', () {
      expect(full.toString(), 'SessionDetail(sessionId: s1, title: t1)');
      expect(
        const SessionDetail().toString(),
        'SessionDetail(sessionId: null, title: null)',
      );
      expect(
        SessionDetail.fromJson(const <String, Object?>{'session_id': 'x'}).toString(),
        'SessionDetail(sessionId: x, title: null)',
      );
    });
  });
}
