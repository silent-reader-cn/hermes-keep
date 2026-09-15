import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/kanban.dart';

/// kanban.dart 请求 DTO 段补测（覆盖率补强，批次 KB1）。
///
/// 覆盖第 1409–2058 行：16 个 Request DTO + sealed `KanbanBulkAction` 的 4 个子类。
/// 重点：
///  - `queryParameters` 的每条条件分支（tenant / assignee 空串、includeArchived、
///    onlyMine、since 空与非空、`since < 0` 归零、`clamp` 上下界与区间内）
///  - `toJson` 条件字段「有值 → 出现」与「为 null → 整键缺席」
///  - `==` 阶梯式逐字段比较、`hashCode`、`toString`
///  - 文件内 `_listEquals` 的四条路径（identical / 一侧 null / 长度不等 / 元素不等）
/// 预期值全部按实现读出写死，不做空断言。
void main() {
  group('KanbanBoardRequest', () {
    test('queryParameters：条件字段逐项开关', () {
      expect(const KanbanBoardRequest(board: 'b').queryParameters, {
        'board': 'b',
      });

      // tenant / assignee 非空 → 落键。
      expect(
        const KanbanBoardRequest(
          board: 'b',
          tenant: 't',
          assignee: 'alice',
        ).queryParameters,
        {'board': 'b', 'tenant': 't', 'assignee': 'alice'},
      );

      // tenant / assignee 空串 → 视为缺席（与 null 同路径）。
      expect(
        const KanbanBoardRequest(
          board: 'b',
          tenant: '',
          assignee: '',
        ).queryParameters,
        {'board': 'b'},
      );

      // 布尔开关只落 true。
      expect(
        const KanbanBoardRequest(board: 'b', includeArchived: true).queryParameters,
        {'board': 'b', 'include_archived': 'true'},
      );
      expect(
        const KanbanBoardRequest(board: 'b', onlyMine: true).queryParameters,
        {'board': 'b', 'only_mine': 'true'},
      );
      expect(
        const KanbanBoardRequest(
          board: 'b',
          includeArchived: false,
          onlyMine: false,
        ).queryParameters,
        {'board': 'b'},
      );

      // since：null 缺席，0 也要落键（判据是 `!= null` 而非真值）。
      expect(
        const KanbanBoardRequest(board: 'b', since: 0).queryParameters,
        {'board': 'b', 'since': '0'},
      );
      expect(
        const KanbanBoardRequest(board: 'b', since: 42).queryParameters,
        {'board': 'b', 'since': '42'},
      );

      // 全字段齐开。
      expect(
        const KanbanBoardRequest(
          board: 'b',
          tenant: 't',
          assignee: 'a',
          includeArchived: true,
          onlyMine: true,
          since: 7,
        ).queryParameters,
        {
          'board': 'b',
          'tenant': 't',
          'assignee': 'a',
          'include_archived': 'true',
          'only_mine': 'true',
          'since': '7',
        },
      );
    });

    test('== / hashCode / toString', () {
      const a = KanbanBoardRequest(
        board: 'b',
        tenant: 't',
        assignee: 'a',
        includeArchived: true,
        onlyMine: true,
        since: 7,
      );
      const same = KanbanBoardRequest(
        board: 'b',
        tenant: 't',
        assignee: 'a',
        includeArchived: true,
        onlyMine: true,
        since: 7,
      );
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);

      // 阶梯：每多一个字段相等比较就多走一行 `&&`。
      expect(a == const KanbanBoardRequest(
            board: 'x',
            tenant: 't',
            assignee: 'a',
            includeArchived: true,
            onlyMine: true,
            since: 7,
          ), isFalse);
      expect(a == const KanbanBoardRequest(
            board: 'b',
            tenant: 'x',
            assignee: 'a',
            includeArchived: true,
            onlyMine: true,
            since: 7,
          ), isFalse);
      expect(a == const KanbanBoardRequest(
            board: 'b',
            tenant: 't',
            assignee: 'x',
            includeArchived: true,
            onlyMine: true,
            since: 7,
          ), isFalse);
      expect(a == const KanbanBoardRequest(
            board: 'b',
            tenant: 't',
            assignee: 'a',
            includeArchived: false,
            onlyMine: true,
            since: 7,
          ), isFalse);
      expect(a == const KanbanBoardRequest(
            board: 'b',
            tenant: 't',
            assignee: 'a',
            includeArchived: true,
            onlyMine: false,
            since: 7,
          ), isFalse);
      expect(a == const KanbanBoardRequest(
            board: 'b',
            tenant: 't',
            assignee: 'a',
            includeArchived: true,
            onlyMine: true,
            since: 8,
          ), isFalse);

      expect(a.toString(), 'KanbanBoardRequest(board: b)');
    });
  });

  group('KanbanEventsRequest', () {
    test('queryParameters：since 归零 + limit clamp', () {
      // 默认 limit 200（区间内原样）。
      expect(
        const KanbanEventsRequest(board: 'b', since: 12).queryParameters,
        {'board': 'b', 'since': '12', 'limit': '200'},
      );

      // since < 0 → 归零；since == 0 原样保 0。
      expect(
        const KanbanEventsRequest(board: 'b', since: -5).queryParameters,
        {'board': 'b', 'since': '0', 'limit': '200'},
      );
      expect(
        const KanbanEventsRequest(board: 'b', since: 0).queryParameters,
        {'board': 'b', 'since': '0', 'limit': '200'},
      );

      // limit 低于下界 → 1；高于上界 → 200；区间内原样。
      expect(
        const KanbanEventsRequest(board: 'b', since: 1, limit: 0).queryParameters,
        {'board': 'b', 'since': '1', 'limit': '1'},
      );
      expect(
        const KanbanEventsRequest(board: 'b', since: 1, limit: -9).queryParameters,
        {'board': 'b', 'since': '1', 'limit': '1'},
      );
      expect(
        const KanbanEventsRequest(board: 'b', since: 1, limit: 500).queryParameters,
        {'board': 'b', 'since': '1', 'limit': '200'},
      );
      expect(
        const KanbanEventsRequest(board: 'b', since: 1, limit: 1).queryParameters,
        {'board': 'b', 'since': '1', 'limit': '1'},
      );
      expect(
        const KanbanEventsRequest(board: 'b', since: 1, limit: 50).queryParameters,
        {'board': 'b', 'since': '1', 'limit': '50'},
      );
    });

    test('== / hashCode / toString', () {
      const a = KanbanEventsRequest(board: 'b', since: 3, limit: 9);
      const same = KanbanEventsRequest(board: 'b', since: 3, limit: 9);
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a == const KanbanEventsRequest(board: 'x', since: 3, limit: 9),
        isFalse,
      );
      expect(
        a == const KanbanEventsRequest(board: 'b', since: 4, limit: 9),
        isFalse,
      );
      expect(
        a == const KanbanEventsRequest(board: 'b', since: 3, limit: 10),
        isFalse,
      );
      expect(a.toString(), 'KanbanEventsRequest(board: b, since: 3)');
    });
  });

  group('KanbanEventsStreamRequest', () {
    test('queryParameters：since 归零', () {
      expect(
        const KanbanEventsStreamRequest(board: 'b', since: 8).queryParameters,
        {'board': 'b', 'since': '8'},
      );
      expect(
        const KanbanEventsStreamRequest(board: 'b', since: -1).queryParameters,
        {'board': 'b', 'since': '0'},
      );
    });

    test('== / hashCode / toString', () {
      const a = KanbanEventsStreamRequest(board: 'b', since: 8);
      const same = KanbanEventsStreamRequest(board: 'b', since: 8);
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a == const KanbanEventsStreamRequest(board: 'x', since: 8),
        isFalse,
      );
      expect(
        a == const KanbanEventsStreamRequest(board: 'b', since: 9),
        isFalse,
      );
      expect(a.toString(), 'KanbanEventsStreamRequest(board: b)');
    });
  });

  group('KanbanWorkerLogRequest', () {
    test('queryParameters：仅 board + clamp 后的 tail（cardID 走路径）', () {
      // 默认 tailBytes 65536，区间内原样。
      expect(
        const KanbanWorkerLogRequest(cardID: 'c1', board: 'b').queryParameters,
        {'board': 'b', 'tail': '65536'},
      );
      expect(
        const KanbanWorkerLogRequest(
          cardID: 'c1',
          board: 'b',
          tailBytes: 1024,
        ).queryParameters,
        {'board': 'b', 'tail': '1024'},
      );
      // 下界 clamp 到 1，上界 clamp 到 2_000_000。
      expect(
        const KanbanWorkerLogRequest(
          cardID: 'c1',
          board: 'b',
          tailBytes: 0,
        ).queryParameters,
        {'board': 'b', 'tail': '1'},
      );
      expect(
        const KanbanWorkerLogRequest(
          cardID: 'c1',
          board: 'b',
          tailBytes: -3,
        ).queryParameters,
        {'board': 'b', 'tail': '1'},
      );
      expect(
        const KanbanWorkerLogRequest(
          cardID: 'c1',
          board: 'b',
          tailBytes: 5000000,
        ).queryParameters,
        {'board': 'b', 'tail': '2000000'},
      );
      expect(
        const KanbanWorkerLogRequest(
          cardID: 'c1',
          board: 'b',
          tailBytes: 2000000,
        ).queryParameters,
        {'board': 'b', 'tail': '2000000'},
      );
    });

    test('== / hashCode / toString', () {
      const a = KanbanWorkerLogRequest(cardID: 'c1', board: 'b', tailBytes: 10);
      const same = KanbanWorkerLogRequest(cardID: 'c1', board: 'b', tailBytes: 10);
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a == const KanbanWorkerLogRequest(cardID: 'c2', board: 'b', tailBytes: 10),
        isFalse,
      );
      expect(
        a == const KanbanWorkerLogRequest(cardID: 'c1', board: 'x', tailBytes: 10),
        isFalse,
      );
      expect(
        a == const KanbanWorkerLogRequest(cardID: 'c1', board: 'b', tailBytes: 11),
        isFalse,
      );
      expect(a.toString(), 'KanbanWorkerLogRequest(cardID: c1)');
    });
  });

  group('KanbanDispatchRequest', () {
    test('queryParameters：dry_run 字面量 + 固定 max=8', () {
      expect(const KanbanDispatchRequest(board: 'b', dryRun: true).queryParameters, {
        'board': 'b',
        'dry_run': 'true',
        'max': '8',
      });
      expect(const KanbanDispatchRequest(board: 'b', dryRun: false).queryParameters, {
        'board': 'b',
        'dry_run': 'false',
        'max': '8',
      });
      expect(KanbanDispatchRequest.maximum, 8);
    });

    test('== / hashCode / toString', () {
      const a = KanbanDispatchRequest(board: 'b', dryRun: true);
      const same = KanbanDispatchRequest(board: 'b', dryRun: true);
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(a == const KanbanDispatchRequest(board: 'x', dryRun: true), isFalse);
      expect(a == const KanbanDispatchRequest(board: 'b', dryRun: false), isFalse);
      expect(a.toString(), 'KanbanDispatchRequest(board: b, dryRun: true)');
    });
  });

  group('KanbanCreateCardRequest', () {
    test('queryParameters 只带 board', () {
      expect(
        const KanbanCreateCardRequest(
          board: 'b',
          title: 't',
          status: 'todo',
          workspaceKind: 'none',
          idempotencyKey: 'k',
        ).queryParameters,
        {'board': 'b'},
      );
    });

    test('toJson：可选字段为 null 时整键缺席', () {
      expect(
        const KanbanCreateCardRequest(
          board: 'b',
          title: 't',
          status: 'todo',
          workspaceKind: 'none',
          idempotencyKey: 'k',
        ).toJson(),
        {
          'title': 't',
          'status': 'todo',
          'workspace_kind': 'none',
          'idempotency_key': 'k',
        },
      );
    });

    test('toJson：全字段齐开', () {
      expect(
        const KanbanCreateCardRequest(
          board: 'b',
          title: 't',
          body: 'body',
          status: 'todo',
          priority: 2,
          assignee: 'alice',
          tenant: 'tn',
          workspaceKind: 'git',
          workspacePath: '/w',
          skills: ['s1', 's2'],
          maxRuntimeSeconds: 60,
          prerequisiteID: 'p1',
          idempotencyKey: 'k',
        ).toJson(),
        {
          'title': 't',
          'body': 'body',
          'status': 'todo',
          'priority': 2,
          'assignee': 'alice',
          'tenant': 'tn',
          'workspace_kind': 'git',
          'workspace_path': '/w',
          'skills': ['s1', 's2'],
          'max_runtime_seconds': 60,
          'prerequisite_id': 'p1',
          'idempotency_key': 'k',
        },
      );
    });

    test('toJson：空 skills 列表仍落键（判据是 != null）', () {
      expect(
        const KanbanCreateCardRequest(
          board: 'b',
          title: 't',
          status: 'todo',
          workspaceKind: 'none',
          skills: [],
          idempotencyKey: 'k',
        ).toJson(),
        {
          'title': 't',
          'status': 'todo',
          'workspace_kind': 'none',
          'skills': <String>[],
          'idempotency_key': 'k',
        },
      );
    });

    test('== / hashCode / toString（含 _listEquals 四条路径）', () {
      const full = KanbanCreateCardRequest(
        board: 'b',
        title: 't',
        body: 'body',
        status: 'todo',
        priority: 2,
        assignee: 'alice',
        tenant: 'tn',
        workspaceKind: 'git',
        workspacePath: '/w',
        skills: ['s1'],
        maxRuntimeSeconds: 60,
        prerequisiteID: 'p1',
        idempotencyKey: 'k',
      );
      const fullSame = KanbanCreateCardRequest(
        board: 'b',
        title: 't',
        body: 'body',
        status: 'todo',
        priority: 2,
        assignee: 'alice',
        tenant: 'tn',
        workspaceKind: 'git',
        workspacePath: '/w',
        skills: ['s1'],
        maxRuntimeSeconds: 60,
        prerequisiteID: 'p1',
        idempotencyKey: 'k',
      );
      expect(full, equals(fullSame));
      expect(full.hashCode, fullSame.hashCode);
      expect(full == Object(), isFalse);

      // 逐字段不等（阶梯）。
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'x',
              title: 't',
              status: 'todo',
              workspaceKind: 'git',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 'x',
              status: 'todo',
              workspaceKind: 'git',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              body: 'x',
              status: 'todo',
              workspaceKind: 'git',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'doing',
              workspaceKind: 'git',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              priority: 3,
              workspaceKind: 'git',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              assignee: 'bob',
              workspaceKind: 'git',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              tenant: 'other',
              workspaceKind: 'git',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              workspaceKind: 'wt',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              workspaceKind: 'git',
              workspacePath: '/x',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      // _listEquals：元素不等。
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              workspaceKind: 'git',
              skills: ['s2'],
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      // _listEquals：长度不等。
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              workspaceKind: 'git',
              skills: ['s1', 's2'],
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      // _listEquals：一侧 null（另一侧非 null）。
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              workspaceKind: 'git',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              workspaceKind: 'git',
              skills: ['s1'],
              maxRuntimeSeconds: 61,
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              workspaceKind: 'git',
              skills: ['s1'],
              prerequisiteID: 'p2',
              idempotencyKey: 'k',
            ),
        isFalse,
      );
      expect(
        full ==
            const KanbanCreateCardRequest(
              board: 'b',
              title: 't',
              status: 'todo',
              workspaceKind: 'git',
              skills: ['s1'],
              idempotencyKey: 'k2',
            ),
        isFalse,
      );

      // _listEquals：identical（两侧同为 null，也同为同一实例）。
      const noSkillsA = KanbanCreateCardRequest(
        board: 'b',
        title: 't',
        status: 'todo',
        workspaceKind: 'none',
        idempotencyKey: 'k',
      );
      const noSkillsB = KanbanCreateCardRequest(
        board: 'b',
        title: 't',
        status: 'todo',
        workspaceKind: 'none',
        idempotencyKey: 'k',
      );
      expect(noSkillsA, equals(noSkillsB));
      expect(noSkillsA.hashCode, noSkillsB.hashCode);

      expect(full.toString(), 'KanbanCreateCardRequest(title: t)');
    });
  });

  group('KanbanEditCardRequest', () {
    test('queryParameters 只带 board；toJson 条件字段两种形态', () {
      expect(
        const KanbanEditCardRequest(
          cardID: 'c1',
          board: 'b',
          title: 't',
          body: 'body',
          priority: 1,
        ).queryParameters,
        {'board': 'b'},
      );
      expect(
        const KanbanEditCardRequest(
          cardID: 'c1',
          board: 'b',
          title: 't',
          body: 'body',
          priority: 1,
        ).toJson(),
        {'title': 't', 'body': 'body', 'priority': 1},
      );
      expect(
        const KanbanEditCardRequest(
          cardID: 'c1',
          board: 'b',
          title: 't',
          body: 'body',
          tenant: 'tn',
          priority: 1,
          assignee: 'alice',
          status: 'doing',
        ).toJson(),
        {
          'title': 't',
          'body': 'body',
          'tenant': 'tn',
          'priority': 1,
          'assignee': 'alice',
          'status': 'doing',
        },
      );
    });

    test('== / hashCode / toString', () {
      const a = KanbanEditCardRequest(
        cardID: 'c1',
        board: 'b',
        title: 't',
        body: 'body',
        tenant: 'tn',
        priority: 1,
        assignee: 'alice',
        status: 'doing',
      );
      const same = KanbanEditCardRequest(
        cardID: 'c1',
        board: 'b',
        title: 't',
        body: 'body',
        tenant: 'tn',
        priority: 1,
        assignee: 'alice',
        status: 'doing',
      );
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a ==
            const KanbanEditCardRequest(
              cardID: 'c2',
              board: 'b',
              title: 't',
              body: 'body',
              priority: 1,
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditCardRequest(
              cardID: 'c1',
              board: 'x',
              title: 't',
              body: 'body',
              priority: 1,
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditCardRequest(
              cardID: 'c1',
              board: 'b',
              title: 'x',
              body: 'body',
              priority: 1,
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditCardRequest(
              cardID: 'c1',
              board: 'b',
              title: 't',
              body: 'x',
              priority: 1,
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditCardRequest(
              cardID: 'c1',
              board: 'b',
              title: 't',
              body: 'body',
              tenant: 'other',
              priority: 1,
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditCardRequest(
              cardID: 'c1',
              board: 'b',
              title: 't',
              body: 'body',
              priority: 2,
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditCardRequest(
              cardID: 'c1',
              board: 'b',
              title: 't',
              body: 'body',
              priority: 1,
              assignee: 'bob',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditCardRequest(
              cardID: 'c1',
              board: 'b',
              title: 't',
              body: 'body',
              priority: 1,
              status: 'done',
            ),
        isFalse,
      );
      expect(a.toString(), 'KanbanEditCardRequest(cardID: c1)');
    });
  });

  group('KanbanCardStatusRequest', () {
    test('queryParameters / toJson', () {
      const a = KanbanCardStatusRequest(
        cardID: 'c1',
        board: 'b',
        status: 'doing',
      );
      expect(a.queryParameters, {'board': 'b'});
      expect(a.toJson(), {'status': 'doing'});
    });

    test('== / hashCode / toString', () {
      const a = KanbanCardStatusRequest(
        cardID: 'c1',
        board: 'b',
        status: 'doing',
      );
      const same = KanbanCardStatusRequest(
        cardID: 'c1',
        board: 'b',
        status: 'doing',
      );
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a ==
            const KanbanCardStatusRequest(
              cardID: 'c2',
              board: 'b',
              status: 'doing',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanCardStatusRequest(
              cardID: 'c1',
              board: 'x',
              status: 'doing',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanCardStatusRequest(
              cardID: 'c1',
              board: 'b',
              status: 'done',
            ),
        isFalse,
      );
      expect(a.toString(), 'KanbanCardStatusRequest(cardID: c1)');
    });
  });

  group('KanbanCardActionRequest', () {
    test('queryParameters / toJson：reason 为 null → 空 map', () {
      const a = KanbanCardActionRequest(cardID: 'c1', board: 'b');
      expect(a.queryParameters, {'board': 'b'});
      expect(a.toJson(), isEmpty);
      expect(
        const KanbanCardActionRequest(
          cardID: 'c1',
          board: 'b',
          reason: 'because',
        ).toJson(),
        {'reason': 'because'},
      );
    });

    test('== / hashCode / toString', () {
      const a = KanbanCardActionRequest(cardID: 'c1', board: 'b', reason: 'r');
      const same = KanbanCardActionRequest(cardID: 'c1', board: 'b', reason: 'r');
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a == const KanbanCardActionRequest(cardID: 'c2', board: 'b', reason: 'r'),
        isFalse,
      );
      expect(
        a == const KanbanCardActionRequest(cardID: 'c1', board: 'x', reason: 'r'),
        isFalse,
      );
      expect(
        a == const KanbanCardActionRequest(cardID: 'c1', board: 'b', reason: 'z'),
        isFalse,
      );
      expect(
        const KanbanCardActionRequest(cardID: 'c1', board: 'b') ==
            const KanbanCardActionRequest(
              cardID: 'c1',
              board: 'b',
              reason: 'r',
            ),
        isFalse,
      );
      expect(a.toString(), 'KanbanCardActionRequest(cardID: c1)');
    });
  });

  group('KanbanDependencyMutationRequest', () {
    test('queryParameters / toJson', () {
      const a = KanbanDependencyMutationRequest(
        board: 'b',
        prerequisiteID: 'p1',
        dependentID: 'd1',
      );
      expect(a.queryParameters, {'board': 'b'});
      expect(a.toJson(), {'prerequisite_id': 'p1', 'dependent_id': 'd1'});
    });

    test('== / hashCode / toString', () {
      const a = KanbanDependencyMutationRequest(
        board: 'b',
        prerequisiteID: 'p1',
        dependentID: 'd1',
      );
      const same = KanbanDependencyMutationRequest(
        board: 'b',
        prerequisiteID: 'p1',
        dependentID: 'd1',
      );
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a ==
            const KanbanDependencyMutationRequest(
              board: 'x',
              prerequisiteID: 'p1',
              dependentID: 'd1',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanDependencyMutationRequest(
              board: 'b',
              prerequisiteID: 'p2',
              dependentID: 'd1',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanDependencyMutationRequest(
              board: 'b',
              prerequisiteID: 'p1',
              dependentID: 'd2',
            ),
        isFalse,
      );
      expect(a.toString(), 'KanbanDependencyMutationRequest(board: b)');
    });
  });

  group('KanbanAddCommentRequest', () {
    test('queryParameters / toJson', () {
      const a = KanbanAddCommentRequest(
        cardID: 'c1',
        board: 'b',
        body: 'hello',
      );
      expect(a.queryParameters, {'board': 'b'});
      expect(a.toJson(), {'body': 'hello'});
    });

    test('== / hashCode / toString', () {
      const a = KanbanAddCommentRequest(cardID: 'c1', board: 'b', body: 'hello');
      const same = KanbanAddCommentRequest(
        cardID: 'c1',
        board: 'b',
        body: 'hello',
      );
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a == const KanbanAddCommentRequest(cardID: 'c2', board: 'b', body: 'hello'),
        isFalse,
      );
      expect(
        a == const KanbanAddCommentRequest(cardID: 'c1', board: 'x', body: 'hello'),
        isFalse,
      );
      expect(
        a == const KanbanAddCommentRequest(cardID: 'c1', board: 'b', body: 'bye'),
        isFalse,
      );
      expect(a.toString(), 'KanbanAddCommentRequest(cardID: c1)');
    });
  });

  group('KanbanCreateBoardRequest', () {
    test('toJson 全字段', () {
      expect(
        const KanbanCreateBoardRequest(
          slug: 's',
          name: 'N',
          description: 'D',
          icon: 'i',
          color: '#fff',
        ).toJson(),
        {
          'slug': 's',
          'name': 'N',
          'description': 'D',
          'icon': 'i',
          'color': '#fff',
        },
      );
    });

    test('== / hashCode / toString', () {
      const a = KanbanCreateBoardRequest(
        slug: 's',
        name: 'N',
        description: 'D',
        icon: 'i',
        color: '#fff',
      );
      const same = KanbanCreateBoardRequest(
        slug: 's',
        name: 'N',
        description: 'D',
        icon: 'i',
        color: '#fff',
      );
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a ==
            const KanbanCreateBoardRequest(
              slug: 'x',
              name: 'N',
              description: 'D',
              icon: 'i',
              color: '#fff',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanCreateBoardRequest(
              slug: 's',
              name: 'X',
              description: 'D',
              icon: 'i',
              color: '#fff',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanCreateBoardRequest(
              slug: 's',
              name: 'N',
              description: 'X',
              icon: 'i',
              color: '#fff',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanCreateBoardRequest(
              slug: 's',
              name: 'N',
              description: 'D',
              icon: 'x',
              color: '#fff',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanCreateBoardRequest(
              slug: 's',
              name: 'N',
              description: 'D',
              icon: 'i',
              color: '#000',
            ),
        isFalse,
      );
      expect(a.toString(), 'KanbanCreateBoardRequest(slug: s)');
    });
  });

  group('KanbanEditBoardRequest', () {
    test('toJson 全字段', () {
      expect(
        const KanbanEditBoardRequest(
          slug: 's',
          name: 'N',
          description: 'D',
          icon: 'i',
          color: '#fff',
        ).toJson(),
        {
          'slug': 's',
          'name': 'N',
          'description': 'D',
          'icon': 'i',
          'color': '#fff',
        },
      );
    });

    test('== / hashCode / toString', () {
      const a = KanbanEditBoardRequest(
        slug: 's',
        name: 'N',
        description: 'D',
        icon: 'i',
        color: '#fff',
      );
      const same = KanbanEditBoardRequest(
        slug: 's',
        name: 'N',
        description: 'D',
        icon: 'i',
        color: '#fff',
      );
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);
      expect(
        a ==
            const KanbanEditBoardRequest(
              slug: 'x',
              name: 'N',
              description: 'D',
              icon: 'i',
              color: '#fff',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditBoardRequest(
              slug: 's',
              name: 'X',
              description: 'D',
              icon: 'i',
              color: '#fff',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditBoardRequest(
              slug: 's',
              name: 'N',
              description: 'X',
              icon: 'i',
              color: '#fff',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditBoardRequest(
              slug: 's',
              name: 'N',
              description: 'D',
              icon: 'x',
              color: '#fff',
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanEditBoardRequest(
              slug: 's',
              name: 'N',
              description: 'D',
              icon: 'i',
              color: '#000',
            ),
        isFalse,
      );
      expect(a.toString(), 'KanbanEditBoardRequest(slug: s)');
    });
  });

  group('KanbanBoardMutationRequest', () {
    test('toJson / == / hashCode / toString', () {
      const a = KanbanBoardMutationRequest(slug: 's');
      expect(a.toJson(), {'slug': 's'});
      expect(a, equals(const KanbanBoardMutationRequest(slug: 's')));
      expect(a.hashCode, const KanbanBoardMutationRequest(slug: 's').hashCode);
      expect(a == Object(), isFalse);
      expect(a == const KanbanBoardMutationRequest(slug: 'x'), isFalse);
      expect(a.toString(), 'KanbanBoardMutationRequest(slug: s)');
    });
  });

  group('KanbanBulkAction 子类', () {
    test('ChangeStatus：构造 / == / hashCode', () {
      const a = KanbanBulkActionChangeStatus('doing');
      expect(a.status, 'doing');
      expect(a, equals(const KanbanBulkActionChangeStatus('doing')));
      expect(a.hashCode, const KanbanBulkActionChangeStatus('doing').hashCode);
      expect(a == Object(), isFalse);
      expect(a == const KanbanBulkActionChangeStatus('done'), isFalse);
      expect(a, isA<KanbanBulkAction>());
      // 子类未覆写 toString → 走 Object.toString。
      expect(a.toString(), contains('KanbanBulkActionChangeStatus'));
    });

    test('AssignProfile：profile 可空 + == / hashCode', () {
      const a = KanbanBulkActionAssignProfile('p1');
      expect(a.profile, 'p1');
      expect(a, equals(const KanbanBulkActionAssignProfile('p1')));
      expect(a.hashCode, const KanbanBulkActionAssignProfile('p1').hashCode);
      expect(a == Object(), isFalse);
      expect(a == const KanbanBulkActionAssignProfile('p2'), isFalse);

      const none = KanbanBulkActionAssignProfile(null);
      expect(none.profile, isNull);
      expect(none, equals(const KanbanBulkActionAssignProfile(null)));
      expect(none.hashCode, const KanbanBulkActionAssignProfile(null).hashCode);
      expect(none == a, isFalse);
      expect(none, isA<KanbanBulkAction>());
      expect(none.toString(), contains('KanbanBulkActionAssignProfile'));
    });

    test('SetPriority：构造 / == / hashCode', () {
      const a = KanbanBulkActionSetPriority(3);
      expect(a.priority, 3);
      expect(a, equals(const KanbanBulkActionSetPriority(3)));
      expect(a.hashCode, const KanbanBulkActionSetPriority(3).hashCode);
      expect(a == Object(), isFalse);
      expect(a == const KanbanBulkActionSetPriority(4), isFalse);
      expect(a, isA<KanbanBulkAction>());
      expect(a.toString(), contains('KanbanBulkActionSetPriority'));
    });

    test('ArchiveCards：无字段 / == / hashCode（跨子类不等）', () {
      const a = KanbanBulkActionArchiveCards();
      expect(a, equals(const KanbanBulkActionArchiveCards()));
      expect(a.hashCode, const KanbanBulkActionArchiveCards().hashCode);
      expect(a == Object(), isFalse);
      expect(a, isA<KanbanBulkAction>());
      expect(a.toString(), contains('KanbanBulkActionArchiveCards'));
      // 不同子类之间互不相等。
      expect(a == const KanbanBulkActionChangeStatus('done'), isFalse);
      expect(
        const KanbanBulkActionChangeStatus('done') ==
            const KanbanBulkActionArchiveCards(),
        isFalse,
      );
      expect(
        const KanbanBulkActionAssignProfile('p') ==
            const KanbanBulkActionSetPriority(1),
        isFalse,
      );
    });
  });

  group('KanbanBulkActionRequest', () {
    test('queryParameters / toJson 形状（无 toJson，只有 query）', () {
      const a = KanbanBulkActionRequest(
        board: 'b',
        cardIDs: ['c1', 'c2'],
        action: KanbanBulkActionChangeStatus('done'),
      );
      expect(a.queryParameters, {'board': 'b'});
      expect(a.cardIDs, ['c1', 'c2']);
      expect(a.action, const KanbanBulkActionChangeStatus('done'));
    });

    test('== / hashCode / toString（含 _listEquals 路径）', () {
      const a = KanbanBulkActionRequest(
        board: 'b',
        cardIDs: ['c1', 'c2'],
        action: KanbanBulkActionChangeStatus('done'),
      );
      const same = KanbanBulkActionRequest(
        board: 'b',
        cardIDs: ['c1', 'c2'],
        action: KanbanBulkActionChangeStatus('done'),
      );
      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a == Object(), isFalse);

      // board 不等。
      expect(
        a ==
            const KanbanBulkActionRequest(
              board: 'x',
              cardIDs: ['c1', 'c2'],
              action: KanbanBulkActionChangeStatus('done'),
            ),
        isFalse,
      );
      // cardIDs 元素不等 / 长度不等 / 顺序不同。
      expect(
        a ==
            const KanbanBulkActionRequest(
              board: 'b',
              cardIDs: ['c1', 'c3'],
              action: KanbanBulkActionChangeStatus('done'),
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanBulkActionRequest(
              board: 'b',
              cardIDs: ['c1'],
              action: KanbanBulkActionChangeStatus('done'),
            ),
        isFalse,
      );
      expect(
        a ==
            const KanbanBulkActionRequest(
              board: 'b',
              cardIDs: ['c2', 'c1'],
              action: KanbanBulkActionChangeStatus('done'),
            ),
        isFalse,
      );
      // action 不等。
      expect(
        a ==
            const KanbanBulkActionRequest(
              board: 'b',
              cardIDs: ['c1', 'c2'],
              action: KanbanBulkActionArchiveCards(),
            ),
        isFalse,
      );
      expect(a.toString(), 'KanbanBulkActionRequest(board: b)');

      // 空 cardIDs（identical 路径的另一侧：两侧同一 const 空表）。
      const emptyA = KanbanBulkActionRequest(
        board: 'b',
        cardIDs: [],
        action: KanbanBulkActionArchiveCards(),
      );
      const emptyB = KanbanBulkActionRequest(
        board: 'b',
        cardIDs: [],
        action: KanbanBulkActionArchiveCards(),
      );
      expect(emptyA, equals(emptyB));
      expect(emptyA.hashCode, emptyB.hashCode);
    });
  });

  // 运行时（非 const）构造：确认构造器在非常量语境下同样可用。
  // 顺带点亮 lcov 里的构造器签名行——全程 `const` 时那些行不会被记为执行
  // （编译期求值），这是行覆盖率口径问题，不是实现缺陷。
  group('运行时构造（非 const）', () {
    test('18 个 DTO / 子类可由运行时值构造', () {
      final s = 'kanban-'.substring(0, 6);
      final i = int.parse('42');
      final flag = s.startsWith('kan');
      final list = <String>[s];

      expect(KanbanBoardRequest(board: s, tenant: s, since: i).queryParameters['board'], s);
      expect(KanbanEventsRequest(board: s, since: i).queryParameters['since'], '42');
      expect(KanbanEventsStreamRequest(board: s, since: i).queryParameters['since'], '42');
      expect(KanbanWorkerLogRequest(cardID: s, board: s).queryParameters['tail'], '65536');
      expect(KanbanDispatchRequest(board: s, dryRun: flag).queryParameters['dry_run'], 'true');
      expect(
        KanbanCreateCardRequest(
          board: s,
          title: s,
          status: s,
          workspaceKind: s,
          idempotencyKey: s,
        ).toJson()['title'],
        s,
      );
      expect(
        KanbanEditCardRequest(
          cardID: s,
          board: s,
          title: s,
          body: s,
          priority: i,
        ).toJson()['priority'],
        42,
      );
      expect(KanbanCardStatusRequest(cardID: s, board: s, status: s).toJson()['status'], s);
      expect(KanbanCardActionRequest(cardID: s, board: s).toJson(), isEmpty);
      expect(
        KanbanDependencyMutationRequest(
          board: s,
          prerequisiteID: s,
          dependentID: s,
        ).toJson()['dependent_id'],
        s,
      );
      expect(KanbanAddCommentRequest(cardID: s, board: s, body: s).toJson()['body'], s);
      expect(
        KanbanCreateBoardRequest(
          slug: s,
          name: s,
          description: s,
          icon: s,
          color: s,
        ).toJson()['slug'],
        s,
      );
      expect(
        KanbanEditBoardRequest(
          slug: s,
          name: s,
          description: s,
          icon: s,
          color: s,
        ).toJson()['slug'],
        s,
      );
      expect(KanbanBoardMutationRequest(slug: s).toJson()['slug'], s);

      expect(KanbanBulkActionChangeStatus(s).status, s);
      expect(KanbanBulkActionAssignProfile(s).profile, s);
      expect(KanbanBulkActionSetPriority(i).priority, 42);
      expect(
        KanbanBulkActionRequest(
          board: s,
          cardIDs: list,
          action: KanbanBulkActionChangeStatus(s),
        ).queryParameters['board'],
        s,
      );
    });
  });
}
