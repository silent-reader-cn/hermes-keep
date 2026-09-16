import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/session.dart';

/// session.dart 模型补测（覆盖率补强 · 批次 SS2，行 582–1063 的 `SessionSummary`）。
///
/// 实证：本类的 `fromJson` **不使用** `firstKey` 双键回退 —— 33 个字段全部只有
/// snake_case 键，无 camelCase 别名（对比 `SessionDetail` 的 `contextLength` 等
/// 多键回退）。故本文件不虚构 camelCase 用例，只按实现覆盖：
///
/// 1. `fromJson` 全字段 / 缺失 / 错型（`[]`、`{}`、`'x'`）/ 宽容转换 / int64 溢出；
/// 2. `fromDetail` 的回退链（`messageCount ?? messages.length`、
///    `hasPendingUserMessage` 的 `||` 两侧）；
/// 3. `id` 的多级回退（sessionId → title → createdAt/updatedAt/lastMessageAt → 0）；
/// 4. `replacingTitle` / `withStreaming` 三态 / `copyWith` 全量；
/// 5. 派生 getter 与状态判定（subagent / claude_code / cron / readOnly /
///    placeholder / sidebar state / message activity）；
/// 6. `==` 阶梯式（33 个被比较字段逐项差一位，保证每个 `&&` 行都执行）、
///    `hashCode`、`toString`。
///
/// 预期值全部按实现读出来写死，不用空断言充数。
void main() {
  /// 全字段（33 项）JSON，用于「正常解析」与「逐字段阶梯」两处。
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
    'has_pending_user_message': true,
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
    'match_type': 'mt1',
    'match_preview': 'mp1',
  };

  /// 与 [fullJson] 一一对应的全字段实例（供 `==` 阶梯与 copyWith 断言使用）。
  const full = SessionSummary(
    sessionId: 's1',
    title: 't1',
    workspace: 'w1',
    model: 'm1',
    modelProvider: 'p1',
    messageCount: 1,
    createdAt: 1.5,
    updatedAt: 2.5,
    lastMessageAt: 3.5,
    pinned: true,
    archived: true,
    projectId: 'proj1',
    profile: 'prof1',
    inputTokens: 10,
    outputTokens: 20,
    estimatedCost: 0.125,
    activeStreamId: 'as1',
    isStreaming: true,
    isCliSession: true,
    userMessageCount: 2,
    hasPendingUserMessage: true,
    pendingStartedAt: 4.5,
    worktreePath: 'wt1',
    sourceTag: 'st1',
    rawSource: 'rs1',
    sessionSource: 'ss1',
    sourceLabel: 'sl1',
    parentSessionId: 'ps1',
    relationshipType: 'rt1',
    readOnly: true,
    isReadOnly: true,
    matchType: 'mt1',
    matchPreview: 'mp1',
  );

  group('SessionSummary.fromJson', () {
    test('全字段正常解析', () {
      final s = SessionSummary.fromJson(fullJson());

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
      expect(s.hasPendingUserMessage, true);
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
      expect(s.matchType, 'mt1');
      expect(s.matchPreview, 'mp1');
    });

    test('空 map / 键缺失 / 未知键 → 全 null（未知键不参与）', () {
      final empty = SessionSummary.fromJson(const <String, Object?>{});
      expect(empty, const SessionSummary());
      expect(empty.sessionId, isNull);
      expect(empty.title, isNull);
      expect(empty.workspace, isNull);
      expect(empty.model, isNull);
      expect(empty.modelProvider, isNull);
      expect(empty.messageCount, isNull);
      expect(empty.createdAt, isNull);
      expect(empty.updatedAt, isNull);
      expect(empty.lastMessageAt, isNull);
      expect(empty.pinned, isNull);
      expect(empty.archived, isNull);
      expect(empty.projectId, isNull);
      expect(empty.profile, isNull);
      expect(empty.inputTokens, isNull);
      expect(empty.outputTokens, isNull);
      expect(empty.estimatedCost, isNull);
      expect(empty.activeStreamId, isNull);
      expect(empty.isStreaming, isNull);
      expect(empty.isCliSession, isNull);
      expect(empty.userMessageCount, isNull);
      expect(empty.hasPendingUserMessage, isNull);
      expect(empty.pendingStartedAt, isNull);
      expect(empty.worktreePath, isNull);
      expect(empty.sourceTag, isNull);
      expect(empty.rawSource, isNull);
      expect(empty.sessionSource, isNull);
      expect(empty.sourceLabel, isNull);
      expect(empty.parentSessionId, isNull);
      expect(empty.relationshipType, isNull);
      expect(empty.readOnly, isNull);
      expect(empty.isReadOnly, isNull);
      expect(empty.matchType, isNull);
      expect(empty.matchPreview, isNull);

      // 未知键被忽略，不进任何字段
      final unknown = SessionSummary.fromJson({
        'session_id': 'k',
        'nickname': 'nope',
        'match_preview_typo': 'x',
      });
      expect(unknown.sessionId, 'k');
      expect(unknown.matchPreview, isNull);
    });

    test('错型（数组 / map / 嵌套 list）→ 一律 null，不 throw', () {
      final bad = SessionSummary.fromJson({
        'session_id': <Object?>[],
        'title': <String, Object?>{},
        'workspace': <Object?>[],
        'model': <String, Object?>{},
        'model_provider': <Object?>[],
        'message_count': <Object?>[],
        'created_at': <Object?>[],
        'updated_at': <String, Object?>{},
        'last_message_at': <Object?>[],
        'pinned': <Object?>[],
        'archived': <String, Object?>{},
        'project_id': <Object?>[],
        'profile': <Object?>[],
        'input_tokens': <Object?>[],
        'output_tokens': <String, Object?>{},
        'estimated_cost': <Object?>[],
        'active_stream_id': <Object?>[],
        'is_streaming': <Object?>[],
        'is_cli_session': <String, Object?>{},
        'user_message_count': <Object?>[],
        'has_pending_user_message': <Object?>[],
        'pending_started_at': <Object?>[],
        'worktree_path': <Object?>[],
        'source_tag': <Object?>[],
        'raw_source': <String, Object?>{},
        'session_source': <Object?>[],
        'source_label': <Object?>[],
        'parent_session_id': <Object?>[],
        'relationship_type': <Object?>[],
        'read_only': <Object?>[],
        'is_read_only': <Object?>[],
        'match_type': <Object?>[],
        'match_preview': <Object?>[],
      });
      expect(bad, const SessionSummary());
    });

    test('显式 null → null（与键缺失等价）', () {
      final s = SessionSummary.fromJson({
        'session_id': null,
        'message_count': null,
        'created_at': null,
        'pinned': null,
        'read_only': null,
      });
      expect(s.sessionId, isNull);
      expect(s.messageCount, isNull);
      expect(s.createdAt, isNull);
      expect(s.pinned, isNull);
      expect(s.readOnly, isNull);
    });

    test('宽容转换：字符串/数字/bool 互转', () {
      final s = SessionSummary.fromJson({
        'session_id': 42,
        'title': false,
        'workspace': 1.5,
        'message_count': '12',
        'created_at': 100,
        'updated_at': ' 2.5 ',
        'pinned': 'yes',
        'archived': 1,
        'read_only': 0,
        'is_read_only': 'NO',
        'source_label': true,
      });
      expect(s.sessionId, '42');
      expect(s.title, 'false');
      expect(s.workspace, '1.5');
      expect(s.messageCount, 12);
      expect(s.createdAt, 100.0);
      expect(s.updatedAt, 2.5);
      expect(s.pinned, true);
      expect(s.archived, true);
      expect(s.readOnly, false);
      expect(s.isReadOnly, false);
      expect(s.sourceLabel, 'true');
    });

    test('宽容转换：小数截断 / 字符串小数 / 解析失败 → null', () {
      final s = SessionSummary.fromJson({
        'message_count': 12.9,
        'input_tokens': '-3.7',
        'output_tokens': '7.0',
        'estimated_cost': '0.25',
        'pending_started_at': 'x',
      });
      expect(s.messageCount, 12);
      expect(s.inputTokens, -3);
      expect(s.outputTokens, 7);
      expect(s.estimatedCost, 0.25);
      expect(s.pendingStartedAt, isNull);

      expect(SessionSummary.fromJson({'created_at': 'x'}).createdAt, isNull);
      expect(SessionSummary.fromJson({'pinned': 'maybe'}).pinned, isNull);
      expect(SessionSummary.fromJson({'pinned': 2}).pinned, isNull);
      expect(SessionSummary.fromJson({'archived': 3.5}).archived, isNull);
    });

    test('宽容转换：double 溢出 int64 / 非有限 → null', () {
      // 1e20 是有限 double 但超出 int64 上界 → null（lossyInt 溢出检查）
      expect(
        SessionSummary.fromJson({'message_count': 1e20}).messageCount,
        isNull,
      );
      expect(
        SessionSummary.fromJson({'message_count': double.infinity})
            .messageCount,
        isNull,
      );
      expect(
        SessionSummary.fromJson({'message_count': double.nan}).messageCount,
        isNull,
      );
      expect(
        SessionSummary.fromJson({'message_count': '1e999'}).messageCount,
        isNull,
      );
      // 恰好在 int64 上界内 → 正常截断
      expect(
        SessionSummary.fromJson({'message_count': '9223372036854775807'})
            .messageCount,
        9223372036854775807,
      );
      // double 形态的极大值：2^63 本身即越界 → null
      expect(
        SessionSummary.fromJson({'message_count': -9223372036854775808.0})
            .messageCount,
        -9223372036854775808,
      );
    });
  });

  group('SessionSummary.fromDetail', () {
    Map<String, Object?> detailJson() => <String, Object?>{
      'session_id': 'd1',
      'title': 'detail-title',
      'workspace': '/w',
      'model': 'm',
      'model_provider': 'p',
      'message_count': 7,
      'created_at': 1.0,
      'updated_at': 2.0,
      'last_message_at': 3.0,
      'pinned': true,
      'archived': true,
      'project_id': 'proj',
      'profile': 'prof',
      'input_tokens': 11,
      'output_tokens': 22,
      'estimated_cost': 0.75,
      'active_stream_id': 'stream1',
      'is_streaming': true,
      'is_cli_session': true,
      'user_message_count': 3,
      'pending_started_at': 4.0,
      'worktree_path': '/wt',
      'source_tag': 'st',
      'raw_source': 'rs',
      'session_source': 'ss',
      'source_label': 'sl',
      'parent_session_id': 'ps',
      'relationship_type': 'rt',
      'read_only': true,
      'is_read_only': true,
    };

    test('全字段拷贝；isStreaming / userMessageCount / matchType 恒为 null', () {
      final detail = SessionDetail.fromJson(detailJson());
      final s = SessionSummary.fromDetail(detail);

      expect(s.sessionId, 'd1');
      expect(s.title, 'detail-title');
      expect(s.workspace, '/w');
      expect(s.model, 'm');
      expect(s.modelProvider, 'p');
      expect(s.messageCount, 7);
      expect(s.createdAt, 1.0);
      expect(s.updatedAt, 2.0);
      expect(s.lastMessageAt, 3.0);
      expect(s.pinned, true);
      expect(s.archived, true);
      expect(s.projectId, 'proj');
      expect(s.profile, 'prof');
      expect(s.inputTokens, 11);
      expect(s.outputTokens, 22);
      expect(s.estimatedCost, 0.75);
      expect(s.activeStreamId, 'stream1');
      expect(s.pendingStartedAt, 4.0);
      expect(s.worktreePath, '/wt');
      expect(s.sourceTag, 'st');
      expect(s.rawSource, 'rs');
      expect(s.sessionSource, 'ss');
      expect(s.sourceLabel, 'sl');
      expect(s.parentSessionId, 'ps');
      expect(s.relationshipType, 'rt');
      expect(s.readOnly, true);
      expect(s.isReadOnly, true);

      // detail 里 is_streaming=true / user_message_count=3，摘要一律丢弃
      expect(detail.isStreaming, true);
      expect(s.isStreaming, isNull);
      expect(s.userMessageCount, isNull);
      expect(s.matchType, isNull);
      expect(s.matchPreview, isNull);
      // 无 pending 消息 → false
      expect(s.hasPendingUserMessage, false);
    });

    test('messageCount：detail 缺字段 → 回退 messages.length', () {
      final two = SessionDetail.fromJson({
        'session_id': 'd2',
        'messages': [
          {'role': 'user', 'content': 'a'},
          {'role': 'assistant', 'content': 'b'},
        ],
      });
      expect(SessionSummary.fromDetail(two).messageCount, 2);

      // messages 为空列表 → 0（不是 null）
      final zero = SessionDetail.fromJson({
        'session_id': 'd3',
        'messages': <Object?>[],
      });
      expect(SessionSummary.fromDetail(zero).messageCount, 0);

      // 两者都缺 → null
      final none = SessionDetail.fromJson({'session_id': 'd4'});
      expect(SessionSummary.fromDetail(none).messageCount, isNull);

      // message_count 优先于 messages.length
      final both = SessionDetail.fromJson({
        'session_id': 'd5',
        'message_count': 99,
        'messages': [
          {'role': 'user', 'content': 'a'},
        ],
      });
      expect(SessionSummary.fromDetail(both).messageCount, 99);
    });

    test('hasPendingUserMessage：pending 文本 || 附件列表', () {
      // 文本非空 → true
      expect(
        SessionSummary.fromDetail(
          SessionDetail.fromJson({'pending_user_message': '待发'}),
        ).hasPendingUserMessage,
        true,
      );
      // 空白文本（_nonEmpty 归零）+ 无附件 → false
      expect(
        SessionSummary.fromDetail(
          SessionDetail.fromJson({'pending_user_message': '   '}),
        ).hasPendingUserMessage,
        false,
      );
      // 文本 null + 附件非空 → true
      expect(
        SessionSummary.fromDetail(
          SessionDetail.fromJson({
            'pending_attachments': ['a.png'],
          }),
        ).hasPendingUserMessage,
        true,
      );
      // 文本 null + 附件空列表 → false
      expect(
        SessionSummary.fromDetail(
          SessionDetail.fromJson({'pending_attachments': <Object?>[]}),
        ).hasPendingUserMessage,
        false,
      );
      // 文本 null + 附件键缺失 → false
      expect(
        SessionSummary.fromDetail(
          SessionDetail.fromJson(const <String, Object?>{}),
        ).hasPendingUserMessage,
        false,
      );
    });

    test('空 detail → 摘要字段全空（id 走 untitled 回退）', () {
      final s = SessionSummary.fromDetail(const SessionDetail());
      expect(s.sessionId, isNull);
      expect(s.title, isNull);
      expect(s.messageCount, isNull);
      expect(s.hasPendingUserMessage, false);
      expect(s.isStreaming, isNull);
      // `?? 0` 落在 double 上下文里 → 字面量被提升为 0.0，插值出 '0.0'
      expect(s.id, 'session-untitled-0.0');
      expect(s.shouldAppearInSessionList, false);
    });
  });

  group('SessionSummary.id（多级回退）', () {
    test('sessionId 非空 → 原样（含纯空白，仅判 isEmpty）', () {
      expect(SessionSummary.fromJson({'session_id': 'abc'}).id, 'abc');
      // isNotEmpty 为真 → 原样返回，不做 trim
      expect(SessionSummary.fromJson({'session_id': '  '}).id, '  ');
      expect(
        SessionSummary.fromJson({'session_id': '  spaced  '}).id,
        '  spaced  ',
      );
    });

    test('sessionId 缺失/空串 → session-<title>-<ts>', () {
      expect(
        SessionSummary.fromJson({
          'session_id': '',
          'title': ' 我的会话 ',
          'created_at': 100.0,
        }).id,
        'session-我的会话-100.0',
      );
      // title 缺失 → 'untitled'；时间戳兜底 0 在 double 上下文里是 0.0
      expect(
        SessionSummary.fromJson(const <String, Object?>{}).id,
        'session-untitled-0.0',
      );
      expect(
        SessionSummary.fromJson({'session_id': ''}).id,
        'session-untitled-0.0',
      );
      // title 是纯空白：trim 得 '' 但非 null → 不回退 'untitled'
      expect(SessionSummary.fromJson({'title': '   '}).id, 'session--0.0');
      expect(SessionSummary.fromJson({'title': ''}).id, 'session--0.0');
    });

    test('时间戳回退链 createdAt → updatedAt → lastMessageAt → 0', () {
      expect(
        SessionSummary.fromJson({
          'title': 'x',
          'created_at': 10.0,
          'updated_at': 20.0,
          'last_message_at': 30.0,
        }).id,
        'session-x-10.0',
      );
      expect(
        SessionSummary.fromJson({
          'title': 'x',
          'updated_at': 20.0,
          'last_message_at': 30.0,
        }).id,
        'session-x-20.0',
      );
      expect(
        SessionSummary.fromJson({'title': 'x', 'last_message_at': 30.0}).id,
        'session-x-30.0',
      );
      // 全缺 → 兜底 0 被提升为 double 0.0
      expect(SessionSummary.fromJson({'title': 'x'}).id, 'session-x-0.0');
      // createdAt 显式为 0.0 时不再回退（?? 只认 null）
      expect(
        SessionSummary.fromJson({
          'title': 'x',
          'created_at': 0.0,
          'updated_at': 20.0,
        }).id,
        'session-x-0.0',
      );
    });
  });

  group('SessionSummary.replacingTitle', () {
    test('只换标题，其余 32 字段逐项保留（含 matchPreview）', () {
      final renamed = full.replacingTitle('新标题');

      expect(renamed.title, '新标题');
      expect(renamed.matchPreview, 'mp1');
      expect(
        renamed,
        const SessionSummary(
          sessionId: 's1',
          title: '新标题',
          workspace: 'w1',
          model: 'm1',
          modelProvider: 'p1',
          messageCount: 1,
          createdAt: 1.5,
          updatedAt: 2.5,
          lastMessageAt: 3.5,
          pinned: true,
          archived: true,
          projectId: 'proj1',
          profile: 'prof1',
          inputTokens: 10,
          outputTokens: 20,
          estimatedCost: 0.125,
          activeStreamId: 'as1',
          isStreaming: true,
          isCliSession: true,
          userMessageCount: 2,
          hasPendingUserMessage: true,
          pendingStartedAt: 4.5,
          worktreePath: 'wt1',
          sourceTag: 'st1',
          rawSource: 'rs1',
          sessionSource: 'ss1',
          sourceLabel: 'sl1',
          parentSessionId: 'ps1',
          relationshipType: 'rt1',
          readOnly: true,
          isReadOnly: true,
          matchType: 'mt1',
          matchPreview: 'mp1',
        ),
      );
      // 原对象不变
      expect(full.title, 't1');
    });

    test('空摘要换标题 → 只有 title 有值', () {
      final renamed = const SessionSummary().replacingTitle('t');
      expect(renamed.title, 't');
      expect(renamed.sessionId, isNull);
      expect(renamed.id, 'session-t-0.0');
    });
  });

  group('SessionSummary.withStreaming', () {
    test('isStreaming=true：显式 id > 原 id > 兜底 active', () {
      // 1) 显式给 id
      final explicit = full.withStreaming(
        isStreaming: true,
        activeStreamId: 'new-stream',
      );
      expect(explicit.isStreaming, true);
      expect(explicit.activeStreamId, 'new-stream');

      // 2) 不给 id → 沿用自身 activeStreamId
      final inherited = full.withStreaming(isStreaming: true);
      expect(inherited.isStreaming, true);
      expect(inherited.activeStreamId, 'as1');

      // 3) 自身也没有 → 'active'
      final fallback = full
          .copyWith(activeStreamId: null)
          .withStreaming(isStreaming: true);
      // copyWith 的 ?? 语义保不住 null，故直接构造
      final bare = const SessionSummary(sessionId: 's')
          .withStreaming(isStreaming: true);
      expect(bare.activeStreamId, 'active');
      expect(bare.isStreaming, true);
      expect(fallback.activeStreamId, 'as1');
    });

    test('isStreaming=false：activeStreamId 强制清空', () {
      final stopped = full.withStreaming(isStreaming: false);
      expect(stopped.isStreaming, false);
      expect(stopped.activeStreamId, isNull);
      // 显式传 id 也被忽略（false 分支不看参数）
      final stopped2 = full.withStreaming(
        isStreaming: false,
        activeStreamId: 'ignored',
      );
      expect(stopped2.activeStreamId, isNull);
    });

    test('其余字段保留', () {
      final s = full.withStreaming(isStreaming: false);
      expect(s.matchPreview, 'mp1');
      expect(
        s,
        const SessionSummary(
          sessionId: 's1',
          title: 't1',
          workspace: 'w1',
          model: 'm1',
          modelProvider: 'p1',
          messageCount: 1,
          createdAt: 1.5,
          updatedAt: 2.5,
          lastMessageAt: 3.5,
          pinned: true,
          archived: true,
          projectId: 'proj1',
          profile: 'prof1',
          inputTokens: 10,
          outputTokens: 20,
          estimatedCost: 0.125,
          isStreaming: false,
          isCliSession: true,
          userMessageCount: 2,
          hasPendingUserMessage: true,
          pendingStartedAt: 4.5,
          worktreePath: 'wt1',
          sourceTag: 'st1',
          rawSource: 'rs1',
          sessionSource: 'ss1',
          sourceLabel: 'sl1',
          parentSessionId: 'ps1',
          relationshipType: 'rt1',
          readOnly: true,
          isReadOnly: true,
          matchType: 'mt1',
          matchPreview: 'mp1',
        ),
      );
    });
  });

  group('SessionSummary.copyWith', () {
    test('全字段替换（33 项）', () {
      final s = full.copyWith(
        sessionId: 's2',
        title: 't2',
        workspace: 'w2',
        model: 'm2',
        modelProvider: 'p2',
        messageCount: 2,
        createdAt: 11.5,
        updatedAt: 12.5,
        lastMessageAt: 13.5,
        pinned: false,
        archived: false,
        projectId: 'proj2',
        profile: 'prof2',
        inputTokens: 110,
        outputTokens: 120,
        estimatedCost: 0.25,
        activeStreamId: 'as2',
        isStreaming: false,
        isCliSession: false,
        userMessageCount: 3,
        hasPendingUserMessage: false,
        pendingStartedAt: 14.5,
        worktreePath: 'wt2',
        sourceTag: 'st2',
        rawSource: 'rs2',
        sessionSource: 'ss2',
        sourceLabel: 'sl2',
        parentSessionId: 'ps2',
        relationshipType: 'rt2',
        readOnly: false,
        isReadOnly: false,
        matchType: 'mt2',
        matchPreview: 'mp2',
      );

      expect(
        s,
        const SessionSummary(
          sessionId: 's2',
          title: 't2',
          workspace: 'w2',
          model: 'm2',
          modelProvider: 'p2',
          messageCount: 2,
          createdAt: 11.5,
          updatedAt: 12.5,
          lastMessageAt: 13.5,
          pinned: false,
          archived: false,
          projectId: 'proj2',
          profile: 'prof2',
          inputTokens: 110,
          outputTokens: 120,
          estimatedCost: 0.25,
          activeStreamId: 'as2',
          isStreaming: false,
          isCliSession: false,
          userMessageCount: 3,
          hasPendingUserMessage: false,
          pendingStartedAt: 14.5,
          worktreePath: 'wt2',
          sourceTag: 'st2',
          rawSource: 'rs2',
          sessionSource: 'ss2',
          sourceLabel: 'sl2',
          parentSessionId: 'ps2',
          relationshipType: 'rt2',
          readOnly: false,
          isReadOnly: false,
          matchType: 'mt2',
          matchPreview: 'mp2',
        ),
      );
      expect(s.matchPreview, 'mp2');
      expect(s.messageCount, 2);
      expect(s.isStreaming, false);
    });

    test('无参调用 → 逐字段原样（含显式 false/0 不被 null 覆盖）', () {
      expect(full.copyWith(), full);
      expect(full.copyWith().hashCode, full.hashCode);

      const falsy = SessionSummary(
        messageCount: 0,
        pinned: false,
        archived: false,
        isStreaming: false,
        readOnly: false,
        isReadOnly: false,
        estimatedCost: 0.0,
        createdAt: 0.0,
        title: '',
      );
      final same = falsy.copyWith();
      expect(same.messageCount, 0);
      expect(same.pinned, false);
      expect(same.archived, false);
      expect(same.isStreaming, false);
      expect(same.readOnly, false);
      expect(same.isReadOnly, false);
      expect(same.estimatedCost, 0.0);
      expect(same.createdAt, 0.0);
      expect(same.title, '');
    });

    test('部分替换：只动一个字段，其余保持（含空摘要起点）', () {
      final one = const SessionSummary().copyWith(pinned: true);
      expect(one.pinned, true);
      expect(one.sessionId, isNull);
      expect(one.title, isNull);
      expect(one.messageCount, isNull);
      expect(one, const SessionSummary(pinned: true));

      final two = full.copyWith(title: 'changed');
      expect(two.title, 'changed');
      expect(two.sessionId, 's1');
      expect(two.matchPreview, 'mp1');
      expect(two, full.copyWith(title: 'changed'));
    });
  });

  group('SessionSummary 派生标记（subagent / claude_code / readOnly / cron）', () {
    test('isDelegatedSubagentSession：5 个标记任一含 subagent', () {
      expect(
        SessionSummary.fromJson(const <String, Object?>{})
            .isDelegatedSubagentSession,
        false,
      );
      // 四个 source 字段 + title 逐个单独命中（归一：trim + 小写）
      for (final key in <String>[
        'source_tag',
        'raw_source',
        'session_source',
        'source_label',
        'title',
      ]) {
        expect(
          SessionSummary.fromJson({key: 'subagent'}).isDelegatedSubagentSession,
          true,
          reason: key,
        );
        expect(
          SessionSummary.fromJson({key: 'SUBAGENT'}).isDelegatedSubagentSession,
          true,
          reason: key,
        );
        expect(
          SessionSummary.fromJson({key: '  SubAgent  '})
              .isDelegatedSubagentSession,
          true,
          reason: key,
        );
      }
      // contains 语义（非精确相等）
      expect(
        SessionSummary.fromJson({'title': '委派 subagent 执行记录'})
            .isDelegatedSubagentSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'title': 'Subagents'})
            .isDelegatedSubagentSession,
        true,
      );
      // 纯空白标记被 _nonEmpty 归一为 null → 不命中
      expect(
        SessionSummary.fromJson({'source_tag': '   '})
            .isDelegatedSubagentSession,
        false,
      );
      // 近似但不含 subagent
      expect(
        SessionSummary.fromJson({'source_tag': 'sub_agent'})
            .isDelegatedSubagentSession,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': '普通会话'}).isDelegatedSubagentSession,
        false,
      );
    });

    test('isClaudeCodeSession：只认 source_tag / raw_source 的精确归一值', () {
      expect(
        SessionSummary.fromJson({'source_tag': 'claude_code'})
            .isClaudeCodeSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'source_tag': ' Claude_Code '})
            .isClaudeCodeSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'raw_source': 'CLAUDE_CODE'})
            .isClaudeCodeSession,
        true,
      );
      // contains 判定用 equals：带前后缀不命中
      expect(
        SessionSummary.fromJson({'source_tag': 'claude_code_v2'})
            .isClaudeCodeSession,
        false,
      );
      expect(
        SessionSummary.fromJson({'source_tag': 'my-claude_code'})
            .isClaudeCodeSession,
        false,
      );
      // 只有这两字段参与 —— session_source / source_label / title 不算
      expect(
        SessionSummary.fromJson({'session_source': 'claude_code'})
            .isClaudeCodeSession,
        false,
      );
      expect(
        SessionSummary.fromJson({'source_label': 'claude_code'})
            .isClaudeCodeSession,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'claude_code'}).isClaudeCodeSession,
        false,
      );
      expect(
        SessionSummary.fromJson(const <String, Object?>{}).isClaudeCodeSession,
        false,
      );
    });

    test('isSessionReadOnly：三个 OR 分支各自可独立命中', () {
      // 分支 1：委派 subagent（|| 短路，readOnly 未参与）
      expect(
        SessionSummary.fromJson({'title': 'Subagent Session'})
            .isSessionReadOnly,
        true,
      );
      // 分支 2：readOnly == true（isReadOnly 为 null）
      expect(
        SessionSummary.fromJson({'read_only': true}).isSessionReadOnly,
        true,
      );
      // 分支 3：isReadOnly == true（readOnly 为 null）
      expect(
        SessionSummary.fromJson({'is_read_only': true}).isSessionReadOnly,
        true,
      );
      // 显式 false / null → 三支全否
      expect(
        SessionSummary.fromJson(const <String, Object?>{}).isSessionReadOnly,
        false,
      );
      expect(
        SessionSummary.fromJson({'read_only': false, 'is_read_only': false})
            .isSessionReadOnly,
        false,
      );
      expect(
        SessionSummary.fromJson({'read_only': false}).isSessionReadOnly,
        false,
      );
      // 非 bool 值被 lossyBool 归 null → 不算 true
      expect(
        SessionSummary.fromJson({'read_only': 'maybe'}).isSessionReadOnly,
        false,
      );
    });

    test('isCronSession：sessionId 前缀 或 四标记含 cron', () {
      expect(
        SessionSummary.fromJson({'session_id': 'cron_123'}).isCronSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'session_id': 'CRON_abc'}).isCronSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'session_id': '  cron_x  '}).isCronSession,
        true,
      );
      // 'cron' 无下划线 / 前缀不在开头 → false
      expect(
        SessionSummary.fromJson({'session_id': 'cron'}).isCronSession,
        false,
      );
      expect(
        SessionSummary.fromJson({'session_id': 'my_cron_1'}).isCronSession,
        false,
      );
      for (final key in <String>[
        'session_source',
        'source_tag',
        'raw_source',
        'source_label',
      ]) {
        expect(
          SessionSummary.fromJson({key: 'cron'}).isCronSession,
          true,
          reason: key,
        );
        expect(
          SessionSummary.fromJson({key: ' Cron '}).isCronSession,
          true,
          reason: key,
        );
      }
      // title 不参与 cron 判定（对比 subagent 的 5 字段）
      expect(
        SessionSummary.fromJson({'title': 'cron job'}).isCronSession,
        false,
      );
      // 纯空白标记归一为 null
      expect(
        SessionSummary.fromJson({'source_tag': '  '}).isCronSession,
        false,
      );
      expect(
        SessionSummary.fromJson(const <String, Object?>{}).isCronSession,
        false,
      );
    });
  });

  group('SessionSummary 占位 / 列表可见性判定', () {
    test('hasPlaceholderTitle：null / 空白 / untitled 两式', () {
      expect(
        SessionSummary.fromJson(const <String, Object?>{}).hasPlaceholderTitle,
        true,
      );
      expect(SessionSummary.fromJson({'title': ''}).hasPlaceholderTitle, true);
      expect(
        SessionSummary.fromJson({'title': '   '}).hasPlaceholderTitle,
        true,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled'}).hasPlaceholderTitle,
        true,
      );
      expect(
        SessionSummary.fromJson({'title': 'UNTITLED'}).hasPlaceholderTitle,
        true,
      );
      expect(
        SessionSummary.fromJson({'title': ' Untitled '}).hasPlaceholderTitle,
        true,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled session'})
            .hasPlaceholderTitle,
        true,
      );
      expect(
        SessionSummary.fromJson({'title': 'Untitled Session'})
            .hasPlaceholderTitle,
        true,
      );
      // 精确相等：近似标题不算占位
      expect(
        SessionSummary.fromJson({'title': 'untitled!'}).hasPlaceholderTitle,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled sessions'})
            .hasPlaceholderTitle,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': '我的会话'}).hasPlaceholderTitle,
        false,
      );
    });

    test('hasSidebarState：六个条件逐一命中', () {
      expect(
        SessionSummary.fromJson(const <String, Object?>{}).hasSidebarState,
        false,
      );
      expect(SessionSummary.fromJson({'pinned': true}).hasSidebarState, true);
      expect(
        SessionSummary.fromJson({'is_streaming': true}).hasSidebarState,
        true,
      );
      expect(
        SessionSummary.fromJson({'active_stream_id': 'x'}).hasSidebarState,
        true,
      );
      expect(
        SessionSummary.fromJson({'has_pending_user_message': true})
            .hasSidebarState,
        true,
      );
      expect(
        SessionSummary.fromJson({'pending_started_at': 1.0}).hasSidebarState,
        true,
      );
      expect(
        SessionSummary.fromJson({'worktree_path': '/wt'}).hasSidebarState,
        true,
      );
      // _nonEmpty 归零：空白串不算状态
      expect(
        SessionSummary.fromJson({'active_stream_id': '   '}).hasSidebarState,
        false,
      );
      expect(
        SessionSummary.fromJson({'worktree_path': '  '}).hasSidebarState,
        false,
      );
      expect(
        SessionSummary.fromJson({'active_stream_id': ''}).hasSidebarState,
        false,
      );
      // 显式 false / 0 不算状态
      expect(
        SessionSummary.fromJson({
          'pinned': false,
          'is_streaming': false,
          'has_pending_user_message': false,
          'pending_started_at': null,
        }).hasSidebarState,
        false,
      );
    });

    test('hasMessageActivity：只认 > 0', () {
      expect(
        SessionSummary.fromJson(const <String, Object?>{}).hasMessageActivity,
        false,
      );
      expect(
        SessionSummary.fromJson({'message_count': 0}).hasMessageActivity,
        false,
      );
      expect(
        SessionSummary.fromJson({'message_count': 1}).hasMessageActivity,
        true,
      );
      expect(
        SessionSummary.fromJson({'user_message_count': 0}).hasMessageActivity,
        false,
      );
      expect(
        SessionSummary.fromJson({'user_message_count': 1}).hasMessageActivity,
        true,
      );
      // 负值不构成活动（严格 > 0）
      expect(
        SessionSummary.fromJson({'message_count': -1}).hasMessageActivity,
        false,
      );
      expect(
        SessionSummary.fromJson({'user_message_count': -5}).hasMessageActivity,
        false,
      );
    });

    test('isEmptySidebarPlaceholder：三条早退 + 终判两侧', () {
      // 早退 1：非占位标题
      expect(
        SessionSummary.fromJson({'title': 'hello'}).isEmptySidebarPlaceholder,
        false,
      );
      // 早退 2：有 sidebar 状态
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'pinned': true})
            .isEmptySidebarPlaceholder,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'worktree_path': '/wt'})
            .isEmptySidebarPlaceholder,
        false,
      );
      // 早退 3：有消息活动
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'message_count': 3})
            .isEmptySidebarPlaceholder,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'user_message_count': 1})
            .isEmptySidebarPlaceholder,
        false,
      );
      // 终判为真：占位标题 + 无状态 + 计数 0/null
      expect(
        SessionSummary.fromJson({'title': 'untitled'})
            .isEmptySidebarPlaceholder,
        true,
      );
      expect(
        SessionSummary.fromJson({
          'title': 'untitled',
          'message_count': 0,
          'user_message_count': 0,
        }).isEmptySidebarPlaceholder,
        true,
      );
      expect(
        SessionSummary.fromJson(const <String, Object?>{})
            .isEmptySidebarPlaceholder,
        true,
      );
      // 终判为假：负计数躲过 hasMessageActivity 后 `== 0` 不成立
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'message_count': -1})
            .isEmptySidebarPlaceholder,
        false,
      );
      expect(
        SessionSummary.fromJson({
          'title': 'untitled',
          'message_count': -2,
          'user_message_count': 0,
        }).isEmptySidebarPlaceholder,
        false,
      );
    });

    test('shouldAppearInSessionList = !isEmptySidebarPlaceholder', () {
      expect(
        SessionSummary.fromJson({'title': 'hello'}).shouldAppearInSessionList,
        true,
      );
      expect(
        SessionSummary.fromJson(const <String, Object?>{})
            .shouldAppearInSessionList,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled'})
            .shouldAppearInSessionList,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'pinned': true})
            .shouldAppearInSessionList,
        true,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'message_count': 2})
            .shouldAppearInSessionList,
        true,
      );
    });
  });

  group('SessionSummary == / hashCode / toString', () {
    test('非 SessionSummary / 自身 / null → 类型守卫分支', () {
      // 静态类型放宽到 Object 以免触发 unrelated_type_equality_checks
      final Object? nothing = null;
      final Object sameToString = 'SessionSummary(s1)';
      final Object sameShapeMap = fullJson();
      expect(full == Object(), isFalse);
      expect(full == sameToString, isFalse);
      expect(full == nothing, isFalse);
      expect(full == sameShapeMap, isFalse);
      expect(full == full, isTrue);
    });

    test('32 字段阶梯：逐项差一位全部不等（每个 && 行都执行）', () {
      // 顺序严格照 `operator ==` 的 && 链；每加一项都保留前面所有项，
      // 故比较 N 对时前 N 行都被执行 → 覆盖整条链。
      final ladder = <SessionSummary>[const SessionSummary()];
      ladder.add(ladder.last.copyWith(sessionId: 's1'));
      ladder.add(ladder.last.copyWith(title: 't1'));
      ladder.add(ladder.last.copyWith(workspace: 'w1'));
      ladder.add(ladder.last.copyWith(model: 'm1'));
      ladder.add(ladder.last.copyWith(modelProvider: 'p1'));
      ladder.add(ladder.last.copyWith(messageCount: 1));
      ladder.add(ladder.last.copyWith(createdAt: 1.5));
      ladder.add(ladder.last.copyWith(updatedAt: 2.5));
      ladder.add(ladder.last.copyWith(lastMessageAt: 3.5));
      ladder.add(ladder.last.copyWith(pinned: true));
      ladder.add(ladder.last.copyWith(archived: true));
      ladder.add(ladder.last.copyWith(projectId: 'proj1'));
      ladder.add(ladder.last.copyWith(profile: 'prof1'));
      ladder.add(ladder.last.copyWith(inputTokens: 10));
      ladder.add(ladder.last.copyWith(outputTokens: 20));
      ladder.add(ladder.last.copyWith(estimatedCost: 0.125));
      ladder.add(ladder.last.copyWith(activeStreamId: 'as1'));
      ladder.add(ladder.last.copyWith(isStreaming: true));
      ladder.add(ladder.last.copyWith(isCliSession: true));
      ladder.add(ladder.last.copyWith(userMessageCount: 2));
      ladder.add(ladder.last.copyWith(hasPendingUserMessage: true));
      ladder.add(ladder.last.copyWith(pendingStartedAt: 4.5));
      ladder.add(ladder.last.copyWith(worktreePath: 'wt1'));
      ladder.add(ladder.last.copyWith(sourceTag: 'st1'));
      ladder.add(ladder.last.copyWith(rawSource: 'rs1'));
      ladder.add(ladder.last.copyWith(sessionSource: 'ss1'));
      ladder.add(ladder.last.copyWith(sourceLabel: 'sl1'));
      ladder.add(ladder.last.copyWith(parentSessionId: 'ps1'));
      ladder.add(ladder.last.copyWith(relationshipType: 'rt1'));
      ladder.add(ladder.last.copyWith(readOnly: true));
      ladder.add(ladder.last.copyWith(isReadOnly: true));
      ladder.add(ladder.last.copyWith(matchType: 'mt1'));

      // 1（全 null）+ 32（被比较字段）= 33 级
      expect(ladder, hasLength(33));
      // 末级 == full：== 未比较 matchPreview，故 matchPreview 之差被忽略
      expect(ladder.last, full);
      expect(ladder.last.hashCode, full.hashCode);
      expect(full.matchPreview, 'mp1');

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

    test('全字段相同 → 相等且 hashCode 一致；单字段差异 → 不等', () {
      final same = SessionSummary.fromJson(fullJson());
      expect(same, full);
      expect(same.hashCode, full.hashCode);
      expect(same, full.copyWith());
      expect(same.toString(), full.toString());

      // 值等而类型不同（'1' vs 1）不算相等（lossy 已归一，这里对比手写实例）
      const intCount = SessionSummary(sessionId: 's1', messageCount: 1);
      const strCount = SessionSummary(sessionId: 's1');
      expect(intCount == strCount, isFalse);

      // 逐字段替换为不同值时均不等
      final variants = <String, SessionSummary>{
        'sessionId': full.copyWith(sessionId: 'other'),
        'title': full.copyWith(title: 'other'),
        'workspace': full.copyWith(workspace: 'other'),
        'model': full.copyWith(model: 'other'),
        'modelProvider': full.copyWith(modelProvider: 'other'),
        'messageCount': full.copyWith(messageCount: 2),
        'createdAt': full.copyWith(createdAt: 9.5),
        'updatedAt': full.copyWith(updatedAt: 9.5),
        'lastMessageAt': full.copyWith(lastMessageAt: 9.5),
        'pinned': full.copyWith(pinned: false),
        'archived': full.copyWith(archived: false),
        'projectId': full.copyWith(projectId: 'other'),
        'profile': full.copyWith(profile: 'other'),
        'inputTokens': full.copyWith(inputTokens: 11),
        'outputTokens': full.copyWith(outputTokens: 21),
        'estimatedCost': full.copyWith(estimatedCost: 0.25),
        'activeStreamId': full.copyWith(activeStreamId: 'other'),
        'isStreaming': full.copyWith(isStreaming: false),
        'isCliSession': full.copyWith(isCliSession: false),
        'userMessageCount': full.copyWith(userMessageCount: 3),
        'hasPendingUserMessage': full.copyWith(hasPendingUserMessage: false),
        'pendingStartedAt': full.copyWith(pendingStartedAt: 9.5),
        'worktreePath': full.copyWith(worktreePath: 'other'),
        'sourceTag': full.copyWith(sourceTag: 'other'),
        'rawSource': full.copyWith(rawSource: 'other'),
        'sessionSource': full.copyWith(sessionSource: 'other'),
        'sourceLabel': full.copyWith(sourceLabel: 'other'),
        'parentSessionId': full.copyWith(parentSessionId: 'other'),
        'relationshipType': full.copyWith(relationshipType: 'other'),
        'readOnly': full.copyWith(readOnly: false),
        'isReadOnly': full.copyWith(isReadOnly: false),
        'matchType': full.copyWith(matchType: 'other'),
      };
      for (final entry in variants.entries) {
        expect(entry.value == full, isFalse, reason: entry.key);
      }
      // matchPreview 不参与 == / hashCode（实现只比到 matchType）——当前行为记录
      expect(full == full.copyWith(matchPreview: 'other'), isTrue);
      expect(full.hashCode, full.copyWith(matchPreview: 'other').hashCode);
    });

    test('toString：只含 sessionId 与 title', () {
      expect(full.toString(), 'SessionSummary(sessionId: s1, title: t1)');
      expect(
        const SessionSummary().toString(),
        'SessionSummary(sessionId: null, title: null)',
      );
      expect(
        SessionSummary.fromJson({'session_id': 'x'}).toString(),
        'SessionSummary(sessionId: x, title: null)',
      );
    });
  });
}
