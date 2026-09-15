import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/session.dart';

/// session.dart 模型补测（覆盖率补强 · 批次 SS1，行 9–581 的 13 个类）。
///
/// 专攻模型自身：`lossy*` 容错解码的三类输入（正常 / 缺失 / 错型）、
/// `SessionResponse` / `SessionBranchResponse` 的多形态回退链（嵌套 / 平坦 /
/// `data` 包裹 / 退化兜底）、`ProjectSummary.id` 三级回退、
/// `SessionCompressionSummary.compressedTokenEstimate` 的箭头切分，
/// 以及内联 `==` / `hashCode` / `toString`（阶梯式，保证 `&&` 每行都执行）。
///
/// 预期值全部按实现读出来写死，不用空断言充数。
void main() {
  group('SessionsResponse', () {
    test('fromJson：全字段 + 嵌套列表', () {
      final r = SessionsResponse.fromJson({
        'sessions': [
          {'session_id': 'a', 'title': 'A'},
          {'session_id': 'b'},
        ],
        'cli_count': 2,
        'archived_count': 5,
        'server_time': 1723700000.0,
        'server_tz': 'Asia/Shanghai',
      });

      expect(r.sessions, hasLength(2));
      expect(r.sessions!.first.sessionId, 'a');
      expect(r.sessions!.last.title, isNull);
      expect(r.cliCount, 2);
      expect(r.archivedCount, 5);
      expect(r.serverTime, 1723700000.0);
      expect(r.serverTz, 'Asia/Shanghai');
    });

    test('fromJson：lossy 宽容转换（字符串数字 / int→double / bool→string）', () {
      final r = SessionsResponse.fromJson({
        'cli_count': '7',
        'archived_count': 3.0,
        'server_time': 100,
        'server_tz': true,
      });
      expect(r.cliCount, 7);
      expect(r.archivedCount, 3);
      expect(r.serverTime, 100.0);
      expect(r.serverTz, 'true');

      expect(
        SessionsResponse.fromJson({'server_time': ' 1.5 '}).serverTime,
        1.5,
      );
      expect(
        SessionsResponse.fromJson({'server_time': 'x'}).serverTime,
        isNull,
      );
      expect(SessionsResponse.fromJson({'cli_count': 'x'}).cliCount, isNull);
    });

    test('fromJson：空集合 / 元素非 Map / 类型不符 / 空 map', () {
      expect(SessionsResponse.fromJson({'sessions': []}).sessions, isEmpty);

      // 元素不是对象 → optModelList 整数组失败
      expect(
        SessionsResponse.fromJson({
          'sessions': [1],
        }).sessions,
        isNull,
      );
      expect(SessionsResponse.fromJson({'sessions': 'bad'}).sessions, isNull);

      // 元素是空对象 → 单元素、字段全 null
      final one = SessionsResponse.fromJson({
        'sessions': [<String, Object?>{}],
      });
      expect(one.sessions, hasLength(1));
      expect(one.sessions!.single.sessionId, isNull);

      final empty = SessionsResponse.fromJson(const <String, Object?>{});
      expect(empty.sessions, isNull);
      expect(empty.cliCount, isNull);
      expect(empty.archivedCount, isNull);
      expect(empty.serverTime, isNull);
      expect(empty.serverTz, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const a = SessionsResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        cliCount: 1,
        archivedCount: 2,
        serverTime: 3.0,
        serverTz: 'tz',
      );
      const b = SessionsResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        cliCount: 1,
        archivedCount: 2,
        serverTime: 3.0,
        serverTz: 'tz',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == Object(), isFalse);
      expect(a.toString(), 'SessionsResponse(sessions: 1)');
      expect(
        const SessionsResponse().toString(),
        'SessionsResponse(sessions: null)',
      );

      // 深度列表比较：长度不同 / 元素不同 / 一侧 null
      expect(
        const SessionsResponse() ==
            const SessionsResponse(sessions: [SessionSummary(sessionId: 'a')]),
        isFalse,
      );
      expect(
        const SessionsResponse(sessions: [SessionSummary(sessionId: 'a')]) ==
            const SessionsResponse(
              sessions: [
                SessionSummary(sessionId: 'a'),
                SessionSummary(sessionId: 'b'),
              ],
            ),
        isFalse,
      );
      expect(
        const SessionsResponse(sessions: [SessionSummary(sessionId: 'a')]) ==
            const SessionsResponse(sessions: [SessionSummary(sessionId: 'b')]),
        isFalse,
      );
      // identical 快路径：同一 List 实例
      final shared = [const SessionSummary(sessionId: 'a')];
      expect(
        SessionsResponse(sessions: shared) ==
            SessionsResponse(sessions: shared),
        isTrue,
      );

      // 阶梯：每多一个字段就改一项，逐行执行 && 比较
      const s0 = SessionsResponse();
      const s1 = SessionsResponse(sessions: [SessionSummary(sessionId: 'a')]);
      const s2 = SessionsResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        cliCount: 1,
      );
      const s3 = SessionsResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        cliCount: 1,
        archivedCount: 2,
      );
      const s4 = SessionsResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        cliCount: 1,
        archivedCount: 2,
        serverTime: 3.0,
      );
      const s5 = SessionsResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        cliCount: 1,
        archivedCount: 2,
        serverTime: 3.0,
        serverTz: 'tz',
      );
      expect(s0 == s1, isFalse);
      expect(s1 == s2, isFalse);
      expect(s2 == s3, isFalse);
      expect(s3 == s4, isFalse);
      expect(s4 == s5, isFalse);
      expect(s5 == s5, isTrue);
    });
  });

  group('SessionSearchResponse', () {
    test('fromJson：全字段 / 空集合 / 错型 / 空 map', () {
      final r = SessionSearchResponse.fromJson({
        'sessions': [
          {'session_id': 'a', 'match_type': 'content'},
        ],
        'query': 'bug',
        'count': 1,
      });
      expect(r.sessions, hasLength(1));
      expect(r.sessions!.single.matchType, 'content');
      expect(r.query, 'bug');
      expect(r.count, 1);

      expect(
        SessionSearchResponse.fromJson({'sessions': []}).sessions,
        isEmpty,
      );
      expect(
        SessionSearchResponse.fromJson({'sessions': 'bad'}).sessions,
        isNull,
      );
      expect(
        SessionSearchResponse.fromJson({
          'sessions': [1],
        }).sessions,
        isNull,
      );
      expect(SessionSearchResponse.fromJson({'count': '9'}).count, 9);
      expect(SessionSearchResponse.fromJson({'count': 'x'}).count, isNull);

      final empty = SessionSearchResponse.fromJson(const <String, Object?>{});
      expect(empty.sessions, isNull);
      expect(empty.query, isNull);
      expect(empty.count, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const a = SessionSearchResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        query: 'q',
        count: 1,
      );
      expect(
        a,
        equals(
          const SessionSearchResponse(
            sessions: [SessionSummary(sessionId: 'a')],
            query: 'q',
            count: 1,
          ),
        ),
      );
      expect(
        a.hashCode,
        const SessionSearchResponse(
          sessions: [SessionSummary(sessionId: 'a')],
          query: 'q',
          count: 1,
        ).hashCode,
      );
      expect(a == Object(), isFalse);
      expect(a.toString(), 'SessionSearchResponse(sessions: 1)');
      expect(
        const SessionSearchResponse().toString(),
        'SessionSearchResponse(sessions: null)',
      );

      const t0 = SessionSearchResponse();
      const t1 = SessionSearchResponse(
        sessions: [SessionSummary(sessionId: 'a')],
      );
      const t2 = SessionSearchResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        query: 'q',
      );
      const t3 = SessionSearchResponse(
        sessions: [SessionSummary(sessionId: 'a')],
        query: 'q',
        count: 1,
      );
      expect(t0 == t1, isFalse);
      expect(t1 == t2, isFalse);
      expect(t2 == t3, isFalse);
      expect(t3 == t3, isTrue);

      // 列表比较：长度 / 元素 / null 三向
      expect(
        const SessionSearchResponse(
              sessions: [SessionSummary(sessionId: 'a')],
            ) ==
            const SessionSearchResponse(
              sessions: [
                SessionSummary(sessionId: 'a'),
                SessionSummary(sessionId: 'b'),
              ],
            ),
        isFalse,
      );
      expect(
        const SessionSearchResponse(
              sessions: [SessionSummary(sessionId: 'a')],
            ) ==
            const SessionSearchResponse(
              sessions: [SessionSummary(sessionId: 'b')],
            ),
        isFalse,
      );
    });
  });

  group('SessionResponse', () {
    test('fromJson：标准嵌套 {session:{...}}', () {
      final r = SessionResponse.fromJson({
        'session': {'session_id': 'abc123', 'title': 'T'},
      });
      expect(r.session!.sessionId, 'abc123');
      expect(r.session!.title, 'T');
    });

    test('fromJson：平坦形态 session_id / id / sessionId 三键回退（仅作入口闸门）', () {
      expect(
        SessionResponse.fromJson({'session_id': 'a', 'title': 'T'})
            .session!
            .sessionId,
        'a',
      );
      // 当前行为：id / sessionId 只用于「判定走平坦分支」，
      // 真正进 SessionDetail 的键是 session_id —— 故 session 非空但 sessionId 为 null。
      final byId = SessionResponse.fromJson({'id': 'b'});
      expect(byId.session, isNotNull);
      expect(byId.session!.sessionId, isNull);
      final byCamel = SessionResponse.fromJson({'sessionId': 'c'});
      expect(byCamel.session, isNotNull);
      expect(byCamel.session!.sessionId, isNull);
      // 三键并存时仍读 session_id
      expect(
        SessionResponse.fromJson({
          'session_id': 'a',
          'id': 'b',
          'sessionId': 'c',
        }).session!.sessionId,
        'a',
      );
    });

    test('fromJson：data 包裹形态（嵌套 / 平坦）', () {
      final nested = SessionResponse.fromJson({
        'data': {
          'session': {'session_id': 'd', 'title': 'D'},
        },
      });
      expect(nested.session!.sessionId, 'd');
      expect(nested.session!.title, 'D');

      final flat = SessionResponse.fromJson({
        'data': {'session_id': 'e', 'title': 'E'},
      });
      expect(flat.session!.sessionId, 'e');
      expect(flat.session!.title, 'E');

      final flatById = SessionResponse.fromJson({
        'data': {'id': 'f'},
      });
      expect(flatById.session, isNotNull);
      expect(flatById.session!.sessionId, isNull);
    });

    test('fromJson：空白 flat id 视作缺失 → 落到 data / null', () {
      expect(SessionResponse.fromJson({'session_id': '   '}).session, isNull);
      expect(SessionResponse.fromJson({'id': ''}).session, isNull);
      // 顶层空白 + data 有值 → 用 data 的
      expect(
        SessionResponse.fromJson({
          'session_id': '  ',
          'data': {'session_id': 'z'},
        }).session!.sessionId,
        'z',
      );
    });

    test('fromJson：无法识别形态 → session 为 null', () {
      expect(
        SessionResponse.fromJson(const <String, Object?>{}).session,
        isNull,
      );
      expect(SessionResponse.fromJson({'session': 'bad'}).session, isNull);
      expect(SessionResponse.fromJson({'data': 'bad'}).session, isNull);
      expect(SessionResponse.fromJson({'data': 42}).session, isNull);
      // data 是 Map 但既无 session 嵌套也无 id 键 → 走末端 const 返回
      expect(
        SessionResponse.fromJson({
          'data': {'foo': 'bar'},
        }).session,
        isNull,
      );
      // 空对象也是合法 Map → optModel 返回「全 null 的 SessionDetail」（非 null）
      final emptyNested = SessionResponse.fromJson({
        'session': <String, Object?>{},
      });
      expect(emptyNested.session, isNotNull);
      expect(emptyNested.session!.sessionId, isNull);
      expect(emptyNested.session!.title, isNull);
    });

    test('fromJson：嵌套 session 解码抛错 → optModel 吞掉，整条回退到 null', () {
      // messages 里塞入 int-keyed Map，Map<String, Object?>.from 会抛 TypeError，
      // 该异常在 optModel 内部被 catch → nested 为 null；顶层又无 flat id → null。
      final r = SessionResponse.fromJson({
        'session': {
          'session_id': 'x',
          'messages': [
            <Object, Object>{1: 'a'},
          ],
        },
      });
      expect(r.session, isNull);
    });

    test('fromJson：平坦 id 命中但 detail 解码抛错 → 退化兜底会话 id + title', () {
      final r = SessionResponse.fromJson({
        'session_id': 'flat',
        'title': 'FT',
        'messages': [
          <Object, Object>{1: 'a'},
        ],
      });
      expect(r.session!.sessionId, 'flat');
      expect(r.session!.title, 'FT');

      // data 平坦同路径
      final wrapped = SessionResponse.fromJson({
        'data': {
          'session_id': 'd1',
          'title': 'DT',
          'messages': [
            <Object, Object>{1: 'a'},
          ],
        },
      });
      expect(wrapped.session!.sessionId, 'd1');
      expect(wrapped.session!.title, 'DT');
    });

    test('fromJson：顶层 id 命中时嵌套字段也一并带入 detail', () {
      final r = SessionResponse.fromJson({
        'session_id': 's',
        'model': 'm',
        'message_count': 3,
        'pinned': 1,
      });
      expect(r.session!.sessionId, 's');
      expect(r.session!.model, 'm');
      expect(r.session!.messageCount, 3);
      expect(r.session!.pinned, isTrue);
    });

    test('当前行为：data 为非 String 键的 Map → Map.from 未包裹 try，直接抛 TypeError', () {
      // 记录现状（线路 117 的 Map<String, Object?>.from(data) 不在 try 内），
      // 本轮不改行为，是否加固留给 Leader 裁决。
      expect(
        () => SessionResponse.fromJson({
          'data': <Object, Object>{1: 'a'},
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('== / hashCode / toString', () {
      const a = SessionResponse(session: SessionDetail(sessionId: 's'));
      const b = SessionResponse(session: SessionDetail(sessionId: 's'));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == Object(), isFalse);
      expect(const SessionResponse() == a, isFalse);
      expect(a == const SessionResponse(), isFalse);
      expect(
        a == const SessionResponse(session: SessionDetail(sessionId: 'z')),
        isFalse,
      );
      expect(
        const SessionResponse().toString(),
        'SessionResponse(session: null)',
      );
      expect(
        a.toString(),
        'SessionResponse(session: ${const SessionDetail(sessionId: 's')})',
      );
    });
  });

  group('SessionMutationResponse', () {
    test('fromJson：全字段 / ok 宽容布尔 / 错型 / 空 map', () {
      final r = SessionMutationResponse.fromJson({
        'ok': true,
        'session': {'session_id': 'a'},
        'error': 'boom',
      });
      expect(r.ok, isTrue);
      expect(r.session!.sessionId, 'a');
      expect(r.error, 'boom');

      expect(SessionMutationResponse.fromJson({'ok': 'yes'}).ok, isTrue);
      expect(SessionMutationResponse.fromJson({'ok': 0}).ok, isFalse);
      expect(SessionMutationResponse.fromJson({'ok': 'nope'}).ok, isNull);
      expect(SessionMutationResponse.fromJson({'ok': 3}).ok, isNull);
      // session 类型不符 → null；error 数字 → 字符串化
      expect(
        SessionMutationResponse.fromJson({'session': 'bad'}).session,
        isNull,
      );
      expect(SessionMutationResponse.fromJson({'error': 12}).error, '12');

      final empty = SessionMutationResponse.fromJson(const <String, Object?>{});
      expect(empty.ok, isNull);
      expect(empty.session, isNull);
      expect(empty.error, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = SessionMutationResponse(ok: true, error: 'e');
      expect(full, equals(const SessionMutationResponse(ok: true, error: 'e')));
      expect(
        full.hashCode,
        const SessionMutationResponse(ok: true, error: 'e').hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'SessionMutationResponse(ok: true)');
      expect(
        const SessionMutationResponse().toString(),
        'SessionMutationResponse(ok: null)',
      );

      const m0 = SessionMutationResponse();
      const m1 = SessionMutationResponse(ok: true);
      const m2 = SessionMutationResponse(
        ok: true,
        session: SessionSummary(sessionId: 'a'),
      );
      const m3 = SessionMutationResponse(
        ok: true,
        session: SessionSummary(sessionId: 'a'),
        error: 'e',
      );
      expect(m0 == m1, isFalse);
      expect(m1 == m2, isFalse);
      expect(m2 == m3, isFalse);
      expect(m3 == m3, isTrue);
    });
  });

  group('ProjectsResponse', () {
    test('fromJson：全字段 / 空集合 / 错型 / 空 map', () {
      final r = ProjectsResponse.fromJson({
        'projects': [
          {'project_id': 'p1', 'name': 'P1'},
          {'name': 'P2'},
        ],
      });
      expect(r.projects, hasLength(2));
      expect(r.projects!.first.projectId, 'p1');
      expect(r.projects!.last.projectId, isNull);

      expect(ProjectsResponse.fromJson({'projects': []}).projects, isEmpty);
      expect(ProjectsResponse.fromJson({'projects': 'bad'}).projects, isNull);
      expect(
        ProjectsResponse.fromJson({
          'projects': [1],
        }).projects,
        isNull,
      );
      expect(
        ProjectsResponse.fromJson(const <String, Object?>{}).projects,
        isNull,
      );
    });

    test('== / hashCode / toString', () {
      const a = ProjectsResponse(projects: [ProjectSummary(projectId: 'p1')]);
      expect(
        a,
        equals(
          const ProjectsResponse(projects: [ProjectSummary(projectId: 'p1')]),
        ),
      );
      expect(
        a.hashCode,
        const ProjectsResponse(projects: [ProjectSummary(projectId: 'p1')])
            .hashCode,
      );
      expect(a == Object(), isFalse);
      expect(a.toString(), 'ProjectsResponse(projects: 1)');
      expect(
        const ProjectsResponse().toString(),
        'ProjectsResponse(projects: null)',
      );
      expect(a == const ProjectsResponse(), isFalse);
      expect(
        const ProjectsResponse(projects: [ProjectSummary(projectId: 'p1')]) ==
            const ProjectsResponse(
              projects: [
                ProjectSummary(projectId: 'p1'),
                ProjectSummary(projectId: 'p2'),
              ],
            ),
        isFalse,
      );
      expect(
        const ProjectsResponse(projects: [ProjectSummary(projectId: 'p1')]) ==
            const ProjectsResponse(projects: [ProjectSummary(projectId: 'p2')]),
        isFalse,
      );
      final shared = [const ProjectSummary(projectId: 'p1')];
      expect(
        ProjectsResponse(projects: shared) ==
            ProjectsResponse(projects: shared),
        isTrue,
      );
    });
  });

  group('ProjectMutationResponse', () {
    test('fromJson：全字段 / ok 宽容布尔 / 嵌套错型 / 空 map', () {
      final r = ProjectMutationResponse.fromJson({
        'ok': 'yes',
        'project': {'project_id': 'p1', 'name': 'P1'},
        'error': 'boom',
      });
      expect(r.ok, isTrue);
      expect(r.project!.projectId, 'p1');
      expect(r.error, 'boom');

      expect(ProjectMutationResponse.fromJson({'ok': 0}).ok, isFalse);
      expect(ProjectMutationResponse.fromJson({'ok': 'nope'}).ok, isNull);
      expect(
        ProjectMutationResponse.fromJson({'project': 'bad'}).project,
        isNull,
      );
      expect(ProjectMutationResponse.fromJson({'project': []}).project, isNull);
      expect(ProjectMutationResponse.fromJson({'error': 7}).error, '7');

      final empty = ProjectMutationResponse.fromJson(const <String, Object?>{});
      expect(empty.ok, isNull);
      expect(empty.project, isNull);
      expect(empty.error, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = ProjectMutationResponse(ok: true, error: 'e');
      expect(full, equals(const ProjectMutationResponse(ok: true, error: 'e')));
      expect(
        full.hashCode,
        const ProjectMutationResponse(ok: true, error: 'e').hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'ProjectMutationResponse(ok: true)');
      expect(
        const ProjectMutationResponse().toString(),
        'ProjectMutationResponse(ok: null)',
      );

      const m0 = ProjectMutationResponse();
      const m1 = ProjectMutationResponse(ok: true);
      const m2 = ProjectMutationResponse(
        ok: true,
        project: ProjectSummary(projectId: 'p1'),
      );
      const m3 = ProjectMutationResponse(
        ok: true,
        project: ProjectSummary(projectId: 'p1'),
        error: 'e',
      );
      expect(m0 == m1, isFalse);
      expect(m1 == m2, isFalse);
      expect(m2 == m3, isFalse);
      expect(m3 == m3, isTrue);
    });
  });

  group('ProjectSummary', () {
    test('fromJson：全字段 / 错型 / 空 map', () {
      final r = ProjectSummary.fromJson({
        'project_id': 'p1',
        'name': 'P1',
        'color': '#fff',
        'created_at': 1.5,
      });
      expect(r.projectId, 'p1');
      expect(r.name, 'P1');
      expect(r.color, '#fff');
      expect(r.createdAt, 1.5);

      // created_at 为整数 → double；字符串数字 → double；字符串非数字 → null
      expect(ProjectSummary.fromJson({'created_at': 2}).createdAt, 2.0);
      expect(ProjectSummary.fromJson({'created_at': '3.5'}).createdAt, 3.5);
      expect(ProjectSummary.fromJson({'created_at': 'x'}).createdAt, isNull);
      // project_id 数字 → 字符串化
      expect(ProjectSummary.fromJson({'project_id': 9}).projectId, '9');

      final empty = ProjectSummary.fromJson(const <String, Object?>{});
      expect(empty.projectId, isNull);
      expect(empty.name, isNull);
      expect(empty.color, isNull);
      expect(empty.createdAt, isNull);
    });

    test('id：projectId → name → uuidV4 三级回退', () {
      expect(const ProjectSummary(projectId: 'p1', name: 'P1').id, 'p1');
      expect(const ProjectSummary(name: 'P1').id, 'P1');

      const noKeys = ProjectSummary();
      expect(noKeys.id, isNotEmpty);
      // 第三级是 uuidV4()，每次调用都新生成
      expect(noKeys.id == noKeys.id, isFalse);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = ProjectSummary(
        projectId: 'p1',
        name: 'P1',
        color: '#fff',
        createdAt: 1.5,
      );
      expect(
        full,
        equals(
          const ProjectSummary(
            projectId: 'p1',
            name: 'P1',
            color: '#fff',
            createdAt: 1.5,
          ),
        ),
      );
      expect(
        full.hashCode,
        const ProjectSummary(
          projectId: 'p1',
          name: 'P1',
          color: '#fff',
          createdAt: 1.5,
        ).hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'ProjectSummary(projectId: p1, name: P1)');

      const p0 = ProjectSummary();
      const p1 = ProjectSummary(projectId: 'p1');
      const p2 = ProjectSummary(projectId: 'p1', name: 'P1');
      const p3 = ProjectSummary(projectId: 'p1', name: 'P1', color: '#fff');
      const p4 = ProjectSummary(
        projectId: 'p1',
        name: 'P1',
        color: '#fff',
        createdAt: 1.5,
      );
      expect(p0 == p1, isFalse);
      expect(p1 == p2, isFalse);
      expect(p2 == p3, isFalse);
      expect(p3 == p4, isFalse);
      expect(p4 == p4, isTrue);
    });
  });

  group('SessionBranchResponse', () {
    test('fromJson：平坦全字段', () {
      final r = SessionBranchResponse.fromJson({
        'session_id': 's',
        'title': 'T',
        'parent_session_id': 'p',
        'error': 'e',
      });
      expect(r.sessionId, 's');
      expect(r.title, 'T');
      expect(r.parentSessionId, 'p');
      expect(r.error, 'e');
    });

    test('fromJson：data 包裹全字段 + 顶层优先', () {
      final wrapped = SessionBranchResponse.fromJson({
        'data': {
          'session_id': 's2',
          'title': 'T2',
          'parent_session_id': 'p2',
          'error': 'e2',
        },
      });
      expect(wrapped.sessionId, 's2');
      expect(wrapped.title, 'T2');
      expect(wrapped.parentSessionId, 'p2');
      expect(wrapped.error, 'e2');

      // 顶层键优先于 data 内同名键
      final both = SessionBranchResponse.fromJson({
        'session_id': 'top',
        'title': 'TopT',
        'parent_session_id': 'topP',
        'error': 'topE',
        'data': {
          'session_id': 'inner',
          'title': 'InnerT',
          'parent_session_id': 'innerP',
          'error': 'innerE',
        },
      });
      expect(both.sessionId, 'top');
      expect(both.title, 'TopT');
      expect(both.parentSessionId, 'topP');
      expect(both.error, 'topE');
    });

    test('fromJson：id 键回退（顶层 / data 内）', () {
      final top = SessionBranchResponse.fromJson({'id': 'i'});
      expect(top.sessionId, 'i');
      final inner = SessionBranchResponse.fromJson({
        'data': {'id': 'i2'},
      });
      expect(inner.sessionId, 'i2');
    });

    test('fromJson：session 嵌套形态（顶层 / data 内 / 互补填充）', () {
      final nested = SessionBranchResponse.fromJson({
        'session': {
          'session_id': 'ns',
          'title': 'NT',
          'parent_session_id': 'np',
        },
      });
      expect(nested.sessionId, 'ns');
      expect(nested.title, 'NT');
      expect(nested.parentSessionId, 'np');

      final dataNested = SessionBranchResponse.fromJson({
        'data': {
          'session': {'id': 'ds', 'title': 'DT', 'parent_session_id': 'dp'},
        },
      });
      expect(dataNested.sessionId, 'ds');
      expect(dataNested.title, 'DT');
      expect(dataNested.parentSessionId, 'dp');

      // 顶层 session 只给 session_id，data.session 补 title/parent
      final merged = SessionBranchResponse.fromJson({
        'session': {'session_id': 'ns'},
        'data': {
          'session': {
            'session_id': 'ds',
            'title': 'DT',
            'parent_session_id': 'dp',
          },
        },
      });
      expect(merged.sessionId, 'ns');
      expect(merged.title, 'DT');
      expect(merged.parentSessionId, 'dp');

      // 平坦 session_id 命中时嵌套一律不参与
      final flatWins = SessionBranchResponse.fromJson({
        'session_id': 'flat',
        'session': {'session_id': 'ns', 'title': 'NT'},
      });
      expect(flatWins.sessionId, 'flat');
      expect(flatWins.title, 'NT');
    });

    test('fromJson：data 非 String 键 → dataMap 兜底为 null，只看顶层', () {
      final r = SessionBranchResponse.fromJson({
        'session_id': 's',
        'data': <Object, Object>{1: 'a'},
      });
      expect(r.sessionId, 's');
      expect(r.title, isNull);
      expect(r.error, isNull);
    });

    test('fromJson：session 非 String 键 → 嵌套解码吞异常，全 null', () {
      final r = SessionBranchResponse.fromJson({
        'session': <Object, Object>{1: 'a'},
      });
      expect(r.sessionId, isNull);
      expect(r.title, isNull);
      expect(r.parentSessionId, isNull);
      expect(r.error, isNull);
    });

    test('fromJson：data.session 非 String 键 → 嵌套解码吞异常', () {
      final r = SessionBranchResponse.fromJson({
        'data': {
          'session': <Object, Object>{1: 'a'},
        },
      });
      expect(r.sessionId, isNull);
      expect(r.title, isNull);
      expect(r.parentSessionId, isNull);
    });

    test('fromJson：data 非 Map / 空 map → 全 null', () {
      expect(SessionBranchResponse.fromJson({'data': 'x'}).sessionId, isNull);
      expect(SessionBranchResponse.fromJson({'data': 42}).sessionId, isNull);

      final empty = SessionBranchResponse.fromJson(const <String, Object?>{});
      expect(empty.sessionId, isNull);
      expect(empty.title, isNull);
      expect(empty.parentSessionId, isNull);
      expect(empty.error, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = SessionBranchResponse(
        sessionId: 's',
        title: 'T',
        parentSessionId: 'p',
        error: 'e',
      );
      expect(
        full,
        equals(
          const SessionBranchResponse(
            sessionId: 's',
            title: 'T',
            parentSessionId: 'p',
            error: 'e',
          ),
        ),
      );
      expect(
        full.hashCode,
        const SessionBranchResponse(
          sessionId: 's',
          title: 'T',
          parentSessionId: 'p',
          error: 'e',
        ).hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'SessionBranchResponse(sessionId: s)');
      expect(
        const SessionBranchResponse().toString(),
        'SessionBranchResponse(sessionId: null)',
      );

      const b0 = SessionBranchResponse();
      const b1 = SessionBranchResponse(sessionId: 's');
      const b2 = SessionBranchResponse(sessionId: 's', title: 'T');
      const b3 = SessionBranchResponse(
        sessionId: 's',
        title: 'T',
        parentSessionId: 'p',
      );
      const b4 = SessionBranchResponse(
        sessionId: 's',
        title: 'T',
        parentSessionId: 'p',
        error: 'e',
      );
      expect(b0 == b1, isFalse);
      expect(b1 == b2, isFalse);
      expect(b2 == b3, isFalse);
      expect(b3 == b4, isFalse);
      expect(b4 == b4, isTrue);
    });
  });

  group('SessionCompressionSummary', () {
    test('fromJson：全字段 / 错型 / 空 map', () {
      final r = SessionCompressionSummary.fromJson({
        'headline': 'H',
        'token_line': '128k -> 42k',
        'note': 'N',
        'reference_message': 'R',
      });
      expect(r.headline, 'H');
      expect(r.tokenLine, '128k -> 42k');
      expect(r.note, 'N');
      expect(r.referenceMessage, 'R');

      // token_line 数字 → 字符串化；reference_message 错型对象 → null
      expect(
        SessionCompressionSummary.fromJson({'token_line': 5}).tokenLine,
        '5',
      );
      expect(
        SessionCompressionSummary.fromJson({
          'reference_message': <String, Object?>{'a': 1},
        }).referenceMessage,
        isNull,
      );

      final empty = SessionCompressionSummary.fromJson(
        const <String, Object?>{},
      );
      expect(empty.headline, isNull);
      expect(empty.tokenLine, isNull);
      expect(empty.note, isNull);
      expect(empty.referenceMessage, isNull);
    });

    test('compressedTokenEstimate：箭头切分 + 数字提取', () {
      // tokenLine 缺失 / 空串 → null
      expect(const SessionCompressionSummary().compressedTokenEstimate, isNull);
      expect(
        const SessionCompressionSummary(tokenLine: '').compressedTokenEstimate,
        isNull,
      );
      // 纯箭头（Unicode）→ 末段空 → null
      expect(
        const SessionCompressionSummary(tokenLine: '\u{2192}')
            .compressedTokenEstimate,
        isNull,
      );
      // `->` ASCII 箭头
      expect(
        const SessionCompressionSummary(tokenLine: '128k -> 42k')
            .compressedTokenEstimate,
        42,
      );
      // `→` Unicode 箭头
      expect(
        const SessionCompressionSummary(tokenLine: '128k \u{2192} 42k')
            .compressedTokenEstimate,
        42,
      );
      // 无箭头 → 整串取数字
      expect(
        const SessionCompressionSummary(tokenLine: '128k')
            .compressedTokenEstimate,
        128,
      );
      // 多箭头 → 取最后一段
      expect(
        const SessionCompressionSummary(tokenLine: '100 \u{2192} 25k -> 30')
            .compressedTokenEstimate,
        30,
      );
      // 无数字 → null
      expect(
        const SessionCompressionSummary(tokenLine: 'k -> k')
            .compressedTokenEstimate,
        isNull,
      );
      // 非数字字符被剥离（当前行为：'1e5k' → '15'）
      expect(
        const SessionCompressionSummary(tokenLine: '1e5k')
            .compressedTokenEstimate,
        15,
      );
      // 超出 int 范围 → int.tryParse 失败 → null
      expect(
        const SessionCompressionSummary(
          tokenLine: '999999999999999999999999999999',
        ).compressedTokenEstimate,
        isNull,
      );
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = SessionCompressionSummary(
        headline: 'H',
        tokenLine: 'T',
        note: 'N',
        referenceMessage: 'R',
      );
      expect(
        full,
        equals(
          const SessionCompressionSummary(
            headline: 'H',
            tokenLine: 'T',
            note: 'N',
            referenceMessage: 'R',
          ),
        ),
      );
      expect(
        full.hashCode,
        const SessionCompressionSummary(
          headline: 'H',
          tokenLine: 'T',
          note: 'N',
          referenceMessage: 'R',
        ).hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'SessionCompressionSummary(headline: H)');

      const c0 = SessionCompressionSummary();
      const c1 = SessionCompressionSummary(headline: 'H');
      const c2 = SessionCompressionSummary(headline: 'H', tokenLine: 'T');
      const c3 = SessionCompressionSummary(
        headline: 'H',
        tokenLine: 'T',
        note: 'N',
      );
      const c4 = SessionCompressionSummary(
        headline: 'H',
        tokenLine: 'T',
        note: 'N',
        referenceMessage: 'R',
      );
      expect(c0 == c1, isFalse);
      expect(c1 == c2, isFalse);
      expect(c2 == c3, isFalse);
      expect(c3 == c4, isFalse);
      expect(c4 == c4, isTrue);
    });
  });

  group('SessionCompressResponse', () {
    test('fromJson：全字段（含嵌套 session / summary）', () {
      final r = SessionCompressResponse.fromJson({
        'ok': 'true',
        'session': {'session_id': 's', 'title': 'T'},
        'summary': {'headline': 'H', 'token_line': '128k -> 42k'},
        'focus_topic': 'F',
        'error': 'E',
      });
      expect(r.ok, isTrue);
      expect(r.session!.sessionId, 's');
      expect(r.summary!.headline, 'H');
      expect(r.summary!.compressedTokenEstimate, 42);
      expect(r.focusTopic, 'F');
      expect(r.error, 'E');
    });

    test('fromJson：嵌套错型 → null；空 map 全 null', () {
      final bad = SessionCompressResponse.fromJson({
        'ok': 'nope',
        'session': 'bad',
        'summary': 1,
        'focus_topic': 3,
      });
      expect(bad.ok, isNull);
      expect(bad.session, isNull);
      expect(bad.summary, isNull);
      expect(bad.focusTopic, '3');

      final empty = SessionCompressResponse.fromJson(const <String, Object?>{});
      expect(empty.ok, isNull);
      expect(empty.session, isNull);
      expect(empty.summary, isNull);
      expect(empty.focusTopic, isNull);
      expect(empty.error, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = SessionCompressResponse(
        ok: true,
        session: SessionDetail(sessionId: 's'),
        summary: SessionCompressionSummary(headline: 'H'),
        focusTopic: 'F',
        error: 'E',
      );
      expect(
        full,
        equals(
          const SessionCompressResponse(
            ok: true,
            session: SessionDetail(sessionId: 's'),
            summary: SessionCompressionSummary(headline: 'H'),
            focusTopic: 'F',
            error: 'E',
          ),
        ),
      );
      expect(
        full.hashCode,
        const SessionCompressResponse(
          ok: true,
          session: SessionDetail(sessionId: 's'),
          summary: SessionCompressionSummary(headline: 'H'),
          focusTopic: 'F',
          error: 'E',
        ).hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'SessionCompressResponse(ok: true)');
      expect(
        const SessionCompressResponse().toString(),
        'SessionCompressResponse(ok: null)',
      );

      const r0 = SessionCompressResponse();
      const r1 = SessionCompressResponse(ok: true);
      const r2 = SessionCompressResponse(
        ok: true,
        session: SessionDetail(sessionId: 's'),
      );
      const r3 = SessionCompressResponse(
        ok: true,
        session: SessionDetail(sessionId: 's'),
        summary: SessionCompressionSummary(headline: 'H'),
      );
      const r4 = SessionCompressResponse(
        ok: true,
        session: SessionDetail(sessionId: 's'),
        summary: SessionCompressionSummary(headline: 'H'),
        focusTopic: 'F',
      );
      const r5 = SessionCompressResponse(
        ok: true,
        session: SessionDetail(sessionId: 's'),
        summary: SessionCompressionSummary(headline: 'H'),
        focusTopic: 'F',
        error: 'E',
      );
      expect(r0 == r1, isFalse);
      expect(r1 == r2, isFalse);
      expect(r2 == r3, isFalse);
      expect(r3 == r4, isFalse);
      expect(r4 == r5, isFalse);
      expect(r5 == r5, isTrue);
    });
  });

  group('SessionUndoResponse', () {
    test('fromJson：全字段 / 宽容转换 / 空 map', () {
      final r = SessionUndoResponse.fromJson({
        'ok': true,
        'removed_count': 3,
        'removed_preview': 'p',
        'error': 'e',
      });
      expect(r.ok, isTrue);
      expect(r.removedCount, 3);
      expect(r.removedPreview, 'p');
      expect(r.error, 'e');

      expect(SessionUndoResponse.fromJson({'ok': 'no'}).ok, isFalse);
      expect(SessionUndoResponse.fromJson({'ok': 2}).ok, isNull);
      expect(
        SessionUndoResponse.fromJson({'removed_count': '4'}).removedCount,
        4,
      );
      expect(
        SessionUndoResponse.fromJson({'removed_count': 4.9}).removedCount,
        4,
      );
      expect(
        SessionUndoResponse.fromJson({'removed_count': 'x'}).removedCount,
        isNull,
      );
      expect(
        SessionUndoResponse.fromJson({'removed_preview': 8}).removedPreview,
        '8',
      );

      final empty = SessionUndoResponse.fromJson(const <String, Object?>{});
      expect(empty.ok, isNull);
      expect(empty.removedCount, isNull);
      expect(empty.removedPreview, isNull);
      expect(empty.error, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = SessionUndoResponse(
        ok: true,
        removedCount: 1,
        removedPreview: 'p',
        error: 'e',
      );
      expect(
        full,
        equals(
          const SessionUndoResponse(
            ok: true,
            removedCount: 1,
            removedPreview: 'p',
            error: 'e',
          ),
        ),
      );
      expect(
        full.hashCode,
        const SessionUndoResponse(
          ok: true,
          removedCount: 1,
          removedPreview: 'p',
          error: 'e',
        ).hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'SessionUndoResponse(ok: true)');

      const u0 = SessionUndoResponse();
      const u1 = SessionUndoResponse(ok: true);
      const u2 = SessionUndoResponse(ok: true, removedCount: 1);
      const u3 = SessionUndoResponse(
        ok: true,
        removedCount: 1,
        removedPreview: 'p',
      );
      const u4 = SessionUndoResponse(
        ok: true,
        removedCount: 1,
        removedPreview: 'p',
        error: 'e',
      );
      expect(u0 == u1, isFalse);
      expect(u1 == u2, isFalse);
      expect(u2 == u3, isFalse);
      expect(u3 == u4, isFalse);
      expect(u4 == u4, isTrue);
    });
  });

  group('SessionRetryResponse', () {
    test('fromJson：全字段 / 宽容转换 / 空 map', () {
      final r = SessionRetryResponse.fromJson({
        'ok': 1,
        'last_user_text': 'hello',
        'removed_count': 2,
        'error': 'e',
      });
      expect(r.ok, isTrue);
      expect(r.lastUserText, 'hello');
      expect(r.removedCount, 2);
      expect(r.error, 'e');

      expect(SessionRetryResponse.fromJson({'ok': 'false'}).ok, isFalse);
      expect(SessionRetryResponse.fromJson({'ok': 'nope'}).ok, isNull);
      expect(
        SessionRetryResponse.fromJson({'last_user_text': 5}).lastUserText,
        '5',
      );
      expect(
        SessionRetryResponse.fromJson({'last_user_text': <String, Object?>{}})
            .lastUserText,
        isNull,
      );
      expect(
        SessionRetryResponse.fromJson({'removed_count': '3'}).removedCount,
        3,
      );

      final empty = SessionRetryResponse.fromJson(const <String, Object?>{});
      expect(empty.ok, isNull);
      expect(empty.lastUserText, isNull);
      expect(empty.removedCount, isNull);
      expect(empty.error, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = SessionRetryResponse(
        ok: true,
        lastUserText: 't',
        removedCount: 1,
        error: 'e',
      );
      expect(
        full,
        equals(
          const SessionRetryResponse(
            ok: true,
            lastUserText: 't',
            removedCount: 1,
            error: 'e',
          ),
        ),
      );
      expect(
        full.hashCode,
        const SessionRetryResponse(
          ok: true,
          lastUserText: 't',
          removedCount: 1,
          error: 'e',
        ).hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'SessionRetryResponse(ok: true)');

      const t0 = SessionRetryResponse();
      const t1 = SessionRetryResponse(ok: true);
      const t2 = SessionRetryResponse(ok: true, lastUserText: 't');
      const t3 = SessionRetryResponse(
        ok: true,
        lastUserText: 't',
        removedCount: 1,
      );
      const t4 = SessionRetryResponse(
        ok: true,
        lastUserText: 't',
        removedCount: 1,
        error: 'e',
      );
      expect(t0 == t1, isFalse);
      expect(t1 == t2, isFalse);
      expect(t2 == t3, isFalse);
      expect(t3 == t4, isFalse);
      expect(t4 == t4, isTrue);
    });
  });

  group('SessionStatusResponse', () {
    test('fromJson：全字段 / 宽容转换 / 空 map', () {
      final r = SessionStatusResponse.fromJson({
        'session_id': 's',
        'active_stream_id': 'st',
        'is_streaming': true,
        'pending_user_message': 'm',
        'error': 'e',
      });
      expect(r.sessionId, 's');
      expect(r.activeStreamId, 'st');
      expect(r.isStreaming, isTrue);
      expect(r.pendingUserMessage, 'm');
      expect(r.error, 'e');

      expect(
        SessionStatusResponse.fromJson({'is_streaming': 'true'}).isStreaming,
        isTrue,
      );
      expect(
        SessionStatusResponse.fromJson({'is_streaming': 0}).isStreaming,
        isFalse,
      );
      expect(
        SessionStatusResponse.fromJson({'is_streaming': 'nope'}).isStreaming,
        isNull,
      );
      expect(SessionStatusResponse.fromJson({'session_id': 7}).sessionId, '7');
      expect(
        SessionStatusResponse.fromJson({
          'active_stream_id': <String, Object?>{},
        }).activeStreamId,
        isNull,
      );

      final empty = SessionStatusResponse.fromJson(const <String, Object?>{});
      expect(empty.sessionId, isNull);
      expect(empty.activeStreamId, isNull);
      expect(empty.isStreaming, isNull);
      expect(empty.pendingUserMessage, isNull);
      expect(empty.error, isNull);
    });

    test('== / hashCode / toString（阶梯式逐字段）', () {
      const full = SessionStatusResponse(
        sessionId: 's',
        activeStreamId: 'st',
        isStreaming: true,
        pendingUserMessage: 'm',
        error: 'e',
      );
      expect(
        full,
        equals(
          const SessionStatusResponse(
            sessionId: 's',
            activeStreamId: 'st',
            isStreaming: true,
            pendingUserMessage: 'm',
            error: 'e',
          ),
        ),
      );
      expect(
        full.hashCode,
        const SessionStatusResponse(
          sessionId: 's',
          activeStreamId: 'st',
          isStreaming: true,
          pendingUserMessage: 'm',
          error: 'e',
        ).hashCode,
      );
      expect(full == Object(), isFalse);
      expect(full.toString(), 'SessionStatusResponse(sessionId: s)');
      expect(
        const SessionStatusResponse().toString(),
        'SessionStatusResponse(sessionId: null)',
      );

      const z0 = SessionStatusResponse();
      const z1 = SessionStatusResponse(sessionId: 's');
      const z2 = SessionStatusResponse(sessionId: 's', activeStreamId: 'st');
      const z3 = SessionStatusResponse(
        sessionId: 's',
        activeStreamId: 'st',
        isStreaming: true,
      );
      const z4 = SessionStatusResponse(
        sessionId: 's',
        activeStreamId: 'st',
        isStreaming: true,
        pendingUserMessage: 'm',
      );
      const z5 = SessionStatusResponse(
        sessionId: 's',
        activeStreamId: 'st',
        isStreaming: true,
        pendingUserMessage: 'm',
        error: 'e',
      );
      expect(z0 == z1, isFalse);
      expect(z1 == z2, isFalse);
      expect(z2 == z3, isFalse);
      expect(z3 == z4, isFalse);
      expect(z4 == z5, isFalse);
      expect(z5 == z5, isTrue);
    });
  });
}
