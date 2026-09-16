import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/kanban.dart';

/// kanban.dart 第 1–1408 行补测（覆盖率补强，批次 KBA1）。
///
/// 第 1409–2058 行（Request DTO 段）已由 `kanban_dto_extra_test.dart` 补测完毕，
/// 本文件**不覆盖**该区间，也不改动任何既有测试文件。
///
/// 覆盖清单：
///  - 14.1 配置 / 看板列表：`kanbanAssigneeName` / `KanbanConfiguration` /
///    `KanbanBoardsResponse` / `KanbanBoard` / `KanbanBoardMutationEnvelope`
///  - 14.2 快照 / 列 / 卡：`KanbanBoardSnapshot` / `KanbanColumn` /
///    `KanbanAppliedFilters` / `KanbanStatus` / `KanbanCard`
///  - 14.4 详情家族：`KanbanCardDetailEnvelope` / `KanbanCardMutationEnvelope` /
///    `KanbanComment` / `KanbanDetailEvent` / `KanbanDetailEventPayload` /
///    `KanbanDependencyLinks` / `KanbanDispatchRun` / `KanbanWorkerLog` /
///    `KanbanAddCommentResponse` / `KanbanLinkCounts` / `KanbanStats` /
///    `KanbanAssigneeHistory`
///  - 14.5 事件流 / 批量 / dispatch：`KanbanEventsEnvelope` / `KanbanEvent` /
///    `KanbanBulkActionEnvelope` / `KanbanBulkActionResult` /
///    `KanbanDependencyMutationEnvelope` / `KanbanDispatchResult`
///
/// 写法约定：
///  - 每个 `fromJson` 走「正常键 / 字段缺失 / 类型不符 / 显式 null / 空集合」五态；
///  - `==` 用**阶梯式逐字段差异**（每个字段单独造一个只差该字段的实例，
///    保证 `&&` 链的每一行都被执行到），`hashCode` 只断言相等实例相等；
///  - 多形态回退链（firstKey 双键 / 三键 / 四键）**逐键位单独成例**，并补
///    「近似键名不被识别」的反例；
///  - 所有期望值按实现读出写死，无空断言、无 `isNotNull` 凑数。
/// 键 `toString()` 抛异常的辅助类：用于触达容错解码内部的 `catch` 兜底分支
/// （`KanbanBoard._decodeIntMap` 的 try/catch）。JSON 输入下键恒为字符串，
/// 该分支只能靠这种人造键对象命中。
class _ThrowingKey {
  @override
  String toString() => throw StateError('throwing key');
}

void main() {
  // ==========================================================================
  // 14.1 配置 / 看板列表
  // ==========================================================================

  group('kanbanAssigneeName', () {
    test('字符串 → 自身；{name} 对象 → name；其余类型 → null', () {
      expect(kanbanAssigneeName('alice'), 'alice');
      expect(kanbanAssigneeName(''), '');

      expect(kanbanAssigneeName({'name': 'bob'}), 'bob');
      // 对象 name 走 lossyString：数字 / 布尔被宽容转换。
      expect(kanbanAssigneeName({'name': 1}), '1');
      expect(kanbanAssigneeName({'name': 1.5}), '1.5');
      expect(kanbanAssigneeName({'name': false}), 'false');
      expect(kanbanAssigneeName({'name': null}), isNull);
      expect(kanbanAssigneeName({'other': 'x'}), isNull);
      expect(kanbanAssigneeName(const <String, Object?>{}), isNull);

      // 非字符串非对象（null / 数字 / 布尔 / 数组）→ null。
      expect(kanbanAssigneeName(null), isNull);
      expect(kanbanAssigneeName(42), isNull);
      expect(kanbanAssigneeName(1.5), isNull);
      expect(kanbanAssigneeName(true), isNull);
      expect(kanbanAssigneeName(<Object?>[]), isNull);
    });
  });

  group('KanbanConfiguration', () {
    test('fromJson：全键正常（含 assignees 字符串 + {name} 对象混排）', () {
      final config = KanbanConfiguration.fromJson({
        'columns': ['todo', 'done'],
        'assignees': [
          'alice',
          {'name': 'bob'},
          {'name': 3},
        ],
        'default_tenant': 't1',
        'lane_by_profile': true,
        'include_archived_by_default': true,
        'render_markdown': true,
        'read_only': true,
      });
      expect(config.columns, ['todo', 'done']);
      expect(config.assignees, ['alice', 'bob', '3']);
      expect(config.defaultTenant, 't1');
      expect(config.laneByProfile, true);
      expect(config.includeArchivedByDefault, true);
      expect(config.renderMarkdown, true);
      expect(config.readOnly, true);
    });

    test('fromJson：键全缺 / 显式 null → 全 null', () {
      final missing = KanbanConfiguration.fromJson(const {});
      expect(missing.columns, isNull);
      expect(missing.assignees, isNull);
      expect(missing.defaultTenant, isNull);
      expect(missing.laneByProfile, isNull);
      expect(missing.includeArchivedByDefault, isNull);
      expect(missing.renderMarkdown, isNull);
      expect(missing.readOnly, isNull);

      final explicitNull = KanbanConfiguration.fromJson(const {
        'columns': null,
        'assignees': null,
        'default_tenant': null,
        'lane_by_profile': null,
        'include_archived_by_default': null,
        'render_markdown': null,
        'read_only': null,
      });
      expect(explicitNull.columns, isNull);
      expect(explicitNull.assignees, isNull);
      expect(explicitNull.defaultTenant, isNull);
      expect(explicitNull.laneByProfile, isNull);
      expect(explicitNull.includeArchivedByDefault, isNull);
      expect(explicitNull.renderMarkdown, isNull);
      expect(explicitNull.readOnly, isNull);
    });

    test('fromJson：空集合 ≠ null', () {
      final config = KanbanConfiguration.fromJson(const {
        'columns': <String>[],
        'assignees': <Object?>[],
      });
      expect(config.columns, isEmpty);
      expect(config.assignees, isEmpty);
    });

    test('fromJson：类型不符 → 宽容转换或 null', () {
      final config = KanbanConfiguration.fromJson({
        'columns': 'bad',
        'assignees': 42,
        'default_tenant': 1,
        'lane_by_profile': 1,
        'include_archived_by_default': 0,
        'render_markdown': true,
        'read_only': 'yes',
      });
      expect(config.columns, isNull);
      expect(config.assignees, isNull); // 非 List → null
      expect(config.defaultTenant, '1');
      expect(config.laneByProfile, true);
      expect(config.includeArchivedByDefault, false);
      expect(config.renderMarkdown, true);
      expect(config.readOnly, true);
    });

    test('fromJson：columns 含非字符串元素 → 整数组 null', () {
      expect(
        KanbanConfiguration.fromJson(const {
          'columns': ['a', 1],
        }).columns,
        isNull,
      );
      expect(
        KanbanConfiguration.fromJson(const {
          'columns': [null],
        }).columns,
        isNull,
      );
      expect(
        KanbanConfiguration.fromJson(const {
          'columns': <String>['only'],
        }).columns,
        ['only'],
      );
    });

    test('fromJson：assignees 任一元素不可解 → 整数组 null', () {
      expect(
        KanbanConfiguration.fromJson(const {
          'assignees': ['alice', 42],
        }).assignees,
        isNull,
      );
      expect(
        KanbanConfiguration.fromJson(const {
          'assignees': ['alice', null],
        }).assignees,
        isNull,
      );
      expect(
        KanbanConfiguration.fromJson(const {
          'assignees': ['alice', {'age': 1}],
        }).assignees,
        isNull,
      );
      expect(
        KanbanConfiguration.fromJson(const {
          'assignees': ['alice', {'name': null}],
        }).assignees,
        isNull,
      );
      expect(
        KanbanConfiguration.fromJson(const {
          'assignees': ['alice', {'name': 'bob'}],
        }).assignees,
        ['alice', 'bob'],
      );
    });

    test('fromJson：布尔六态字符串 + int 0/1 + double 不支持', () {
      bool? readOnly(Object? raw) =>
          KanbanConfiguration.fromJson({'read_only': raw}).readOnly;

      expect(readOnly('true'), true);
      expect(readOnly('TRUE'), true);
      expect(readOnly('  yes  '), true);
      expect(readOnly('1'), true);
      expect(readOnly('false'), false);
      expect(readOnly('No'), false);
      expect(readOnly('0'), false);
      expect(readOnly('2'), isNull);
      expect(readOnly('nope'), isNull);
      expect(readOnly(1), true);
      expect(readOnly(0), false);
      expect(readOnly(2), isNull);
      expect(readOnly(true), true);
      // lossyBool 无 double 分支 → 1.0 不识别。
      expect(readOnly(1.0), isNull);
      expect(readOnly(<Object?>[]), isNull);
    });

    test('== 阶梯：columns → assignees → defaultTenant → … → readOnly', () {
      const base = KanbanConfiguration(
        columns: ['a'],
        assignees: ['x'],
        defaultTenant: 't',
        laneByProfile: true,
        includeArchivedByDefault: true,
        renderMarkdown: true,
        readOnly: true,
      );
      const same = KanbanConfiguration(
        columns: ['a'],
        assignees: ['x'],
        defaultTenant: 't',
        laneByProfile: true,
        includeArchivedByDefault: true,
        renderMarkdown: true,
        readOnly: true,
      );
      expect(base, equals(same));
      expect(base.hashCode, same.hashCode);
      expect(base == Object(), isFalse);

      // 第 1 行：columns 长度不同。
      expect(
        base ==
            const KanbanConfiguration(
              columns: ['a', 'z'],
              assignees: ['x'],
              defaultTenant: 't',
              laneByProfile: true,
              includeArchivedByDefault: true,
              renderMarkdown: true,
              readOnly: true,
            ),
        isFalse,
      );
      // 第 1 行：columns 元素不同（同长度）。
      expect(
        base ==
            const KanbanConfiguration(
              columns: ['b'],
              assignees: ['x'],
              defaultTenant: 't',
              laneByProfile: true,
              includeArchivedByDefault: true,
              renderMarkdown: true,
              readOnly: true,
            ),
        isFalse,
      );
      // 第 1 行：一侧 columns 为 null。
      expect(
        base ==
            const KanbanConfiguration(
              assignees: ['x'],
              defaultTenant: 't',
              laneByProfile: true,
              includeArchivedByDefault: true,
              renderMarkdown: true,
              readOnly: true,
            ),
        isFalse,
      );
      // 第 2 行：assignees 不同。
      expect(
        base ==
            const KanbanConfiguration(
              columns: ['a'],
              assignees: ['y'],
              defaultTenant: 't',
              laneByProfile: true,
              includeArchivedByDefault: true,
              renderMarkdown: true,
              readOnly: true,
            ),
        isFalse,
      );
      // 第 3 行：defaultTenant 不同。
      expect(
        base ==
            const KanbanConfiguration(
              columns: ['a'],
              assignees: ['x'],
              defaultTenant: 'u',
              laneByProfile: true,
              includeArchivedByDefault: true,
              renderMarkdown: true,
              readOnly: true,
            ),
        isFalse,
      );
      // 第 4 行：laneByProfile 不同。
      expect(
        base ==
            const KanbanConfiguration(
              columns: ['a'],
              assignees: ['x'],
              defaultTenant: 't',
              laneByProfile: false,
              includeArchivedByDefault: true,
              renderMarkdown: true,
              readOnly: true,
            ),
        isFalse,
      );
      // 第 5 行：includeArchivedByDefault 不同。
      expect(
        base ==
            const KanbanConfiguration(
              columns: ['a'],
              assignees: ['x'],
              defaultTenant: 't',
              laneByProfile: true,
              includeArchivedByDefault: false,
              renderMarkdown: true,
              readOnly: true,
            ),
        isFalse,
      );
      // 第 6 行：renderMarkdown 不同。
      expect(
        base ==
            const KanbanConfiguration(
              columns: ['a'],
              assignees: ['x'],
              defaultTenant: 't',
              laneByProfile: true,
              includeArchivedByDefault: true,
              renderMarkdown: false,
              readOnly: true,
            ),
        isFalse,
      );
      // 第 7 行：readOnly 不同（走完整条链）。
      expect(
        base ==
            const KanbanConfiguration(
              columns: ['a'],
              assignees: ['x'],
              defaultTenant: 't',
              laneByProfile: true,
              includeArchivedByDefault: true,
              renderMarkdown: true,
              readOnly: false,
            ),
        isFalse,
      );
    });

    test('_listEquals 四条路径（identical / 一侧 null / 长度 / 元素）', () {
      final cols = ['a'];
      // identical：同一个 list 实例 → 直接 true。
      expect(
        KanbanConfiguration(columns: cols) == KanbanConfiguration(columns: cols),
        isTrue,
      );
      // 双侧 null 也走 identical 短路。
      expect(const KanbanConfiguration() == const KanbanConfiguration(), isTrue);
      // 不同实例但同内容 → 逐元素比较后 true。
      expect(
        KanbanConfiguration(columns: cols) ==
            const KanbanConfiguration(columns: ['a']),
        isTrue,
      );
      // 一侧 null → false。
      expect(
        KanbanConfiguration(columns: cols) == const KanbanConfiguration(),
        isFalse,
      );
      expect(
        const KanbanConfiguration() == KanbanConfiguration(columns: cols),
        isFalse,
      );
      // 长度不同 → false。
      expect(
        KanbanConfiguration(columns: cols) ==
            const KanbanConfiguration(columns: ['a', 'b']),
        isFalse,
      );
      // 元素不同 → false。
      expect(
        KanbanConfiguration(columns: cols) ==
            const KanbanConfiguration(columns: ['b']),
        isFalse,
      );
    });

    test('toString', () {
      expect(
        KanbanConfiguration.fromJson(const {
          'columns': ['todo', 'done'],
        }).toString(),
        'KanbanConfiguration(columns: [todo, done])',
      );
      expect(
        const KanbanConfiguration().toString(),
        'KanbanConfiguration(columns: null)',
      );
    });
  });

  group('KanbanBoardsResponse', () {
    test('fromJson：boards / current / read_only 正常', () {
      final response = KanbanBoardsResponse.fromJson({
        'boards': [
          {'slug': 'dev', 'name': '开发'},
          {'slug': 'ops'},
        ],
        'current': 'dev',
        'read_only': true,
      });
      expect(response.boards, hasLength(2));
      expect(response.boards![0].slug, 'dev');
      expect(response.boards![0].name, '开发');
      expect(response.boards![1].name, isNull);
      expect(response.current, 'dev');
      expect(response.readOnly, true);
    });

    test('fromJson：缺失 / 显式 null / 空集合 / 错型', () {
      final missing = KanbanBoardsResponse.fromJson(const {});
      expect(missing.boards, isNull);
      expect(missing.current, isNull);
      expect(missing.readOnly, isNull);

      expect(
        KanbanBoardsResponse.fromJson(const {
          'boards': <Object?>[],
        }).boards,
        isEmpty,
      );
      expect(
        KanbanBoardsResponse.fromJson(const {
          'boards': 'bad',
        }).boards,
        isNull,
      );
      // 任一元素非对象 → 整数组 null（optModelList 语义）。
      expect(
        KanbanBoardsResponse.fromJson(const {
          'boards': [
            {'slug': 'a'},
            7,
          ],
        }).boards,
        isNull,
      );
      expect(
        KanbanBoardsResponse.fromJson(const {
          'boards': ['a'],
        }).boards,
        isNull,
      );
      expect(
        KanbanBoardsResponse.fromJson(const {
          'boards': {'slug': 'a'},
        }).boards,
        isNull,
      );
      // current 走 lossyString：数字宽容转换。
      expect(KanbanBoardsResponse.fromJson(const {'current': 5}).current, '5');
      expect(
        KanbanBoardsResponse.fromJson(const {'current': true}).current,
        'true',
      );
      expect(
        KanbanBoardsResponse.fromJson(const {'current': 5.5}).current,
        '5.5',
      );
      expect(
        KanbanBoardsResponse.fromJson(const {
          'read_only': 1,
        }).readOnly,
        true,
      );
      expect(
        KanbanBoardsResponse.fromJson(const {
          'read_only': 'nope',
        }).readOnly,
        isNull,
      );
    });

    test('== 阶梯（boards 深比较 → current → readOnly）+ hashCode', () {
      final base = KanbanBoardsResponse.fromJson(const {
        'boards': [
          {'slug': 'dev', 'name': 'n'},
        ],
        'current': 'dev',
        'read_only': true,
      });
      final same = KanbanBoardsResponse.fromJson(const {
        'boards': [
          {'slug': 'dev', 'name': 'n'},
        ],
        'current': 'dev',
        'read_only': true,
      });
      expect(base, equals(same));
      expect(base.hashCode, same.hashCode);
      expect(base == Object(), isFalse);

      // 第 1 行：boards 元素内容不同。
      expect(
        base ==
            KanbanBoardsResponse.fromJson(const {
              'boards': [
                {'slug': 'other', 'name': 'n'},
              ],
              'current': 'dev',
              'read_only': true,
            }),
        isFalse,
      );
      // 第 1 行：boards 长度不同。
      expect(
        base ==
            KanbanBoardsResponse.fromJson(const {
              'boards': [
                {'slug': 'dev', 'name': 'n'},
                {'slug': 'x'},
              ],
              'current': 'dev',
              'read_only': true,
            }),
        isFalse,
      );
      // 第 1 行：一侧 boards 为 null。
      expect(
        base ==
            KanbanBoardsResponse.fromJson(const {
              'current': 'dev',
              'read_only': true,
            }),
        isFalse,
      );
      // 第 2 行：仅 current 不同。
      expect(
        base ==
            KanbanBoardsResponse.fromJson(const {
              'boards': [
                {'slug': 'dev', 'name': 'n'},
              ],
              'current': 'ops',
              'read_only': true,
            }),
        isFalse,
      );
      // 第 3 行：仅 readOnly 不同。
      expect(
        base ==
            KanbanBoardsResponse.fromJson(const {
              'boards': [
                {'slug': 'dev', 'name': 'n'},
              ],
              'current': 'dev',
              'read_only': false,
            }),
        isFalse,
      );
    });

    test('toString', () {
      expect(
        KanbanBoardsResponse.fromJson(const {'current': 'dev'}).toString(),
        'KanbanBoardsResponse(current: dev)',
      );
      expect(
        const KanbanBoardsResponse().toString(),
        'KanbanBoardsResponse(current: null)',
      );
    });
  });

  group('KanbanBoard', () {
    test('fromJson：全键正常（counts 为 int）', () {
      final board = KanbanBoard.fromJson({
        'slug': 'dev',
        'name': '开发',
        'description': '描述',
        'icon': '🛠️',
        'color': '#4f46e5',
        'is_current': true,
        'total': 42,
        'counts': {'todo': 10, 'running': 3},
        'read_only': true,
      });
      expect(board.slug, 'dev');
      expect(board.name, '开发');
      expect(board.description, '描述');
      expect(board.icon, '🛠️');
      expect(board.color, '#4f46e5');
      expect(board.isCurrent, true);
      expect(board.total, 42);
      expect(board.counts, {'todo': 10, 'running': 3});
      expect(board.readOnly, true);
    });

    test('fromJson：缺失 / 显式 null / 空 counts → 全 null（counts 为 {}）', () {
      final missing = KanbanBoard.fromJson(const {});
      expect(missing.slug, isNull);
      expect(missing.name, isNull);
      expect(missing.description, isNull);
      expect(missing.icon, isNull);
      expect(missing.color, isNull);
      expect(missing.isCurrent, isNull);
      expect(missing.total, isNull);
      expect(missing.counts, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanBoard.fromJson(const {
        'slug': null,
        'total': null,
        'counts': null,
        'is_current': null,
      });
      expect(nulls.slug, isNull);
      expect(nulls.total, isNull);
      expect(nulls.counts, isNull);
      expect(nulls.isCurrent, isNull);

      expect(
        KanbanBoard.fromJson(const {
          'counts': <String, Object?>{},
        }).counts,
        isEmpty,
      );
    });

    test('fromJson：counts 数字宽容（double 截断 / 非有限 / 越界 / 非数字）', () {
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': 2.9, 'b': -2.9},
        }).counts,
        {'a': 2, 'b': -2},
      );
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': 9.0e18},
        }).counts,
        {'a': 9000000000000000000},
      );
      // 非有限 → 整 Map null。
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': double.infinity},
        }).counts,
        isNull,
      );
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': double.negativeInfinity},
        }).counts,
        isNull,
      );
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': double.nan},
        }).counts,
        isNull,
      );
      // double 越 int64 边界 → null。
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': 1.0e19},
        }).counts,
        isNull,
      );
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': -1.0e19},
        }).counts,
        isNull,
      );
      // 非 int / 非 double（字符串 / bool / null）→ null。
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': '3'},
        }).counts,
        isNull,
      );
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': true},
        }).counts,
        isNull,
      );
      expect(
        KanbanBoard.fromJson(const {
          'counts': {'a': null},
        }).counts,
        isNull,
      );
      // 非 Map → null。
      expect(KanbanBoard.fromJson(const {'counts': 7}).counts, isNull);
      expect(
        KanbanBoard.fromJson(const {
          'counts': <Object?>[],
        }).counts,
        isNull,
      );
      // 非字符串键 → key.toString()。
      expect(
        KanbanBoard.fromJson(const {
          'counts': {1: 5},
        }).counts,
        {'1': 5},
      );
    });

    test('fromJson：类型不符 → 宽容转换或 null', () {
      final board = KanbanBoard.fromJson(const {
        'slug': 1,
        'name': 1.5,
        'description': true,
        'icon': <Object?>[],
        'color': <String, Object?>{},
        'is_current': 'yes',
        'total': 'bad',
        'read_only': 0,
      });
      expect(board.slug, '1');
      expect(board.name, '1.5');
      expect(board.description, 'true');
      expect(board.icon, isNull);
      expect(board.color, isNull);
      expect(board.isCurrent, true);
      expect(board.total, isNull);
      expect(board.readOnly, false);

      expect(KanbanBoard.fromJson(const {'total': 42.9}).total, 42);
      expect(KanbanBoard.fromJson(const {'total': ' 7 '}).total, 7);
      expect(KanbanBoard.fromJson(const {'total': '1e3'}).total, 1000);
      expect(KanbanBoard.fromJson(const {'total': '1e400'}).total, isNull);
    });

    test('fromJson：counts 键的 toString 抛异常 → catch 兜底 null（绝不抛）', () {
      expect(
        KanbanBoard.fromJson({
          'counts': {_ThrowingKey(): 1},
        }).counts,
        isNull,
      );
      // 同一私有解析器也被 KanbanStats 复用。
      expect(
        KanbanStats.fromJson({
          'by_status': {_ThrowingKey(): 1},
        }).byStatus,
        isNull,
      );
      expect(
        KanbanStats.fromJson({
          'by_assignee': {_ThrowingKey(): 1},
        }).byAssignee,
        isNull,
      );
    });

    test('== 阶梯：slug → … → readOnly（9 字段）+ hashCode', () {
      const baseJson = <String, Object?>{
        'slug': 'dev',
        'name': 'n',
        'description': 'd',
        'icon': 'i',
        'color': 'c',
        'is_current': true,
        'total': 42,
        'counts': {'todo': 1},
        'read_only': true,
      };
      final base = KanbanBoard.fromJson(baseJson);
      expect(base, equals(KanbanBoard.fromJson(baseJson)));
      expect(base.hashCode, KanbanBoard.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'slug': 'other',
        'name': 'n2',
        'description': 'd2',
        'icon': 'i2',
        'color': 'c2',
        'is_current': false,
        'total': 7,
        'counts': {'todo': 2},
        'read_only': false,
      };
      for (final entry in replacements.entries) {
        final variant = KanbanBoard.fromJson({
          ...baseJson,
          entry.key: entry.value,
        });
        expect(
          base == variant,
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }
    });

    test('toString', () {
      expect(
        KanbanBoard.fromJson(const {'slug': 'dev', 'name': 'n'}).toString(),
        'KanbanBoard(slug: dev, name: n)',
      );
      expect(const KanbanBoard().toString(), 'KanbanBoard(slug: null, name: null)');
    });
  });

  group('KanbanBoardMutationEnvelope', () {
    test('fromJson：board / current / read_only 正常', () {
      final envelope = KanbanBoardMutationEnvelope.fromJson(const {
        'board': {'slug': 'dev', 'name': 'n'},
        'current': 'dev',
        'read_only': true,
      });
      expect(envelope.board!.slug, 'dev');
      expect(envelope.board!.name, 'n');
      expect(envelope.current, 'dev');
      expect(envelope.readOnly, true);
    });

    test('fromJson：缺失 / 显式 null / board 错型', () {
      final missing = KanbanBoardMutationEnvelope.fromJson(const {});
      expect(missing.board, isNull);
      expect(missing.current, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanBoardMutationEnvelope.fromJson(const {
        'board': null,
        'current': null,
        'read_only': null,
      });
      expect(nulls.board, isNull);
      expect(nulls.current, isNull);
      expect(nulls.readOnly, isNull);

      // board 非 Map → null（optModel 语义）。
      expect(
        KanbanBoardMutationEnvelope.fromJson(const {
          'board': 'bad',
        }).board,
        isNull,
      );
      expect(
        KanbanBoardMutationEnvelope.fromJson(const {
          'board': <Object?>[],
        }).board,
        isNull,
      );
      // 空对象仍解出「全 null 的 board」而非 null。
      final emptyBoard = KanbanBoardMutationEnvelope.fromJson(const {
        'board': <String, Object?>{},
      }).board;
      expect(emptyBoard, isNotNull);
      expect(emptyBoard!.slug, isNull);
      expect(
        KanbanBoardMutationEnvelope.fromJson(const {
          'current': 3,
        }).current,
        '3',
      );
      expect(
        KanbanBoardMutationEnvelope.fromJson(const {
          'read_only': 'yes',
        }).readOnly,
        true,
      );
    });

    test('== 阶梯（board → current → readOnly）+ hashCode + toString', () {
      final base = KanbanBoardMutationEnvelope.fromJson(const {
        'board': {'slug': 'dev'},
        'current': 'dev',
        'read_only': true,
      });
      expect(
        base,
        equals(
          KanbanBoardMutationEnvelope.fromJson(const {
            'board': {'slug': 'dev'},
            'current': 'dev',
            'read_only': true,
          }),
        ),
      );
      expect(
        base.hashCode,
        KanbanBoardMutationEnvelope.fromJson(const {
          'board': {'slug': 'dev'},
          'current': 'dev',
          'read_only': true,
        }).hashCode,
      );
      expect(base == Object(), isFalse);

      // 第 1 行：仅 board 不同。
      expect(
        base ==
            KanbanBoardMutationEnvelope.fromJson(const {
              'board': {'slug': 'other'},
              'current': 'dev',
              'read_only': true,
            }),
        isFalse,
      );
      // 第 1 行：一侧 board 为 null。
      expect(
        base ==
            KanbanBoardMutationEnvelope.fromJson(const {
              'current': 'dev',
              'read_only': true,
            }),
        isFalse,
      );
      // 第 2 行：仅 current 不同。
      expect(
        base ==
            KanbanBoardMutationEnvelope.fromJson(const {
              'board': {'slug': 'dev'},
              'current': 'ops',
              'read_only': true,
            }),
        isFalse,
      );
      // 第 3 行：仅 readOnly 不同。
      expect(
        base ==
            KanbanBoardMutationEnvelope.fromJson(const {
              'board': {'slug': 'dev'},
              'current': 'dev',
              'read_only': false,
            }),
        isFalse,
      );

      expect(
        KanbanBoardMutationEnvelope.fromJson(const {
          'board': {'slug': 'dev', 'name': 'n'},
        }).toString(),
        'KanbanBoardMutationEnvelope(board: KanbanBoard(slug: dev, name: n))',
      );
      expect(
        const KanbanBoardMutationEnvelope().toString(),
        'KanbanBoardMutationEnvelope(board: null)',
      );
    });
  });

  // ==========================================================================
  // 14.2 看板快照 / 列 / 卡
  // ==========================================================================

  group('KanbanBoardSnapshot', () {
    test('fromJson：全键正常（latestEventId 为显式 camel 键）', () {
      final snapshot = KanbanBoardSnapshot.fromJson({
        'columns': [
          {
            'name': 'todo',
            'tasks': [
              {'id': 'card_1', 'title': 't'},
            ],
          },
        ],
        'tenants': ['t1', 't2'],
        'assignees': ['alice'],
        'filters': {'assignee': 'alice', 'only_mine': true},
        'changed': true,
        'latestEventId': 99,
        'read_only': true,
      });
      expect(snapshot.columns, hasLength(1));
      expect(snapshot.columns!.single.name, 'todo');
      expect(snapshot.columns!.single.cards!.single.cardID, 'card_1');
      expect(snapshot.tenants, ['t1', 't2']);
      expect(snapshot.assignees, ['alice']);
      expect(snapshot.filters!.assignee, 'alice');
      expect(snapshot.filters!.onlyMine, true);
      expect(snapshot.changed, true);
      expect(snapshot.latestEventID, 99);
      expect(snapshot.readOnly, true);
    });

    test('fromJson：缺失 / 显式 null / 空集合 / 错型', () {
      final missing = KanbanBoardSnapshot.fromJson(const {});
      expect(missing.columns, isNull);
      expect(missing.tenants, isNull);
      expect(missing.assignees, isNull);
      expect(missing.filters, isNull);
      expect(missing.changed, isNull);
      expect(missing.latestEventID, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanBoardSnapshot.fromJson(const {
        'columns': null,
        'tenants': null,
        'assignees': null,
        'filters': null,
        'changed': null,
        'latestEventId': null,
        'read_only': null,
      });
      expect(nulls.columns, isNull);
      expect(nulls.tenants, isNull);
      expect(nulls.assignees, isNull);
      expect(nulls.filters, isNull);
      expect(nulls.changed, isNull);
      expect(nulls.latestEventID, isNull);
      expect(nulls.readOnly, isNull);

      final empties = KanbanBoardSnapshot.fromJson(const {
        'columns': <Object?>[],
        'tenants': <String>[],
        'assignees': <String>[],
      });
      expect(empties.columns, isEmpty);
      expect(empties.tenants, isEmpty);
      expect(empties.assignees, isEmpty);

      final bad = KanbanBoardSnapshot.fromJson(const {
        'columns': 'bad',
        'tenants': 'bad',
        'assignees': [1],
        'filters': 'bad',
        'changed': 'maybe',
        'latestEventId': 'bad',
        'read_only': 1,
      });
      expect(bad.columns, isNull);
      expect(bad.tenants, isNull);
      expect(bad.assignees, isNull);
      expect(bad.filters, isNull);
      expect(bad.changed, isNull);
      expect(bad.latestEventID, isNull);
      expect(bad.readOnly, true);

      // columns 含非对象元素 → 整数组 null。
      expect(
        KanbanBoardSnapshot.fromJson(const {
          'columns': [
            {'name': 'todo'},
            7,
          ],
        }).columns,
        isNull,
      );
      // latestEventId 宽容数字。
      expect(
        KanbanBoardSnapshot.fromJson(const {
          'latestEventId': 12.9,
        }).latestEventID,
        12,
      );
      expect(
        KanbanBoardSnapshot.fromJson(const {
          'latestEventId': '12',
        }).latestEventID,
        12,
      );
    });

    test('== 阶梯：columns → tenants → … → readOnly（7 字段）+ hashCode', () {
      const baseJson = <String, Object?>{
        'columns': [
          {
            'name': 'todo',
            'tasks': [
              {'id': 'c1'},
            ],
          },
        ],
        'tenants': ['t1'],
        'assignees': ['alice'],
        'filters': {'assignee': 'alice'},
        'changed': true,
        'latestEventId': 99,
        'read_only': true,
      };
      final base = KanbanBoardSnapshot.fromJson(baseJson);
      expect(base, equals(KanbanBoardSnapshot.fromJson(baseJson)));
      expect(base.hashCode, KanbanBoardSnapshot.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'columns': [
          {'name': 'done'},
        ],
        'tenants': ['t2'],
        'assignees': ['bob'],
        'filters': {'assignee': 'bob'},
        'changed': false,
        'latestEventId': 1,
        'read_only': false,
      };
      for (final entry in replacements.entries) {
        final variant = KanbanBoardSnapshot.fromJson({
          ...baseJson,
          entry.key: entry.value,
        });
        expect(
          base == variant,
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      // columns / tenants / assignees 的一侧为 null 分支。
      expect(
        base ==
            KanbanBoardSnapshot.fromJson({
              ...baseJson,
              'columns': null,
              'tenants': null,
              'assignees': null,
            }),
        isFalse,
      );
      // 长度不同分支（tenants）。
      expect(
        base ==
            KanbanBoardSnapshot.fromJson({
              ...baseJson,
              'tenants': ['t1', 't2'],
            }),
        isFalse,
      );
    });

    test('toString', () {
      expect(
        KanbanBoardSnapshot.fromJson(const {'changed': true}).toString(),
        'KanbanBoardSnapshot(changed: true)',
      );
      expect(
        const KanbanBoardSnapshot().toString(),
        'KanbanBoardSnapshot(changed: null)',
      );
    });
  });

  group('KanbanColumn', () {
    test('fromJson：name + tasks（键名是 tasks 而非 cards）', () {
      final column = KanbanColumn.fromJson({
        'name': 'todo',
        'tasks': [
          {'id': 'c1', 'title': 't1'},
          {'id': 'c2'},
        ],
      });
      expect(column.name, 'todo');
      expect(column.cards, hasLength(2));
      expect(column.cards![0].cardID, 'c1');
      expect(column.cards![1].title, isNull);
    });

    test('fromJson：缺失 / 显式 null / 空集合 / 错型', () {
      final missing = KanbanColumn.fromJson(const {});
      expect(missing.name, isNull);
      expect(missing.cards, isNull);

      final nulls = KanbanColumn.fromJson(const {
        'name': null,
        'tasks': null,
      });
      expect(nulls.name, isNull);
      expect(nulls.cards, isNull);

      expect(KanbanColumn.fromJson(const {'tasks': <Object?>[]}).cards, isEmpty);
      expect(
        KanbanColumn.fromJson(const {
          'name': 1,
        }).name,
        '1',
      );
      expect(KanbanColumn.fromJson(const {'tasks': 'bad'}).cards, isNull);
      expect(
        KanbanColumn.fromJson(const {
          'tasks': [1],
        }).cards,
        isNull,
      );
    });

    test('== 阶梯（name → cards）+ hashCode + toString', () {
      final base = KanbanColumn.fromJson(const {
        'name': 'todo',
        'tasks': [
          {'id': 'c1'},
        ],
      });
      expect(
        base,
        equals(
          KanbanColumn.fromJson(const {
            'name': 'todo',
            'tasks': [
              {'id': 'c1'},
            ],
          }),
        ),
      );
      expect(
        base.hashCode,
        KanbanColumn.fromJson(const {
          'name': 'todo',
          'tasks': [
            {'id': 'c1'},
          ],
        }).hashCode,
      );
      expect(base == Object(), isFalse);

      // 第 1 行：仅 name 不同。
      expect(
        base == KanbanColumn.fromJson(const {'name': 'done', 'tasks': [
          {'id': 'c1'},
        ]}),
        isFalse,
      );
      // 第 2 行：仅 cards 内容不同。
      expect(
        base == KanbanColumn.fromJson(const {'name': 'todo', 'tasks': [
          {'id': 'c2'},
        ]}),
        isFalse,
      );
      // 第 2 行：cards 长度不同。
      expect(
        base == KanbanColumn.fromJson(const {'name': 'todo', 'tasks': []}),
        isFalse,
      );
      // 第 2 行：一侧 cards 为 null。
      expect(
        base == KanbanColumn.fromJson(const {'name': 'todo'}),
        isFalse,
      );
      // 空列互等（cards 为空数组）。
      expect(
        KanbanColumn.fromJson(const {'name': 'todo', 'tasks': []}),
        equals(KanbanColumn.fromJson(const {'name': 'todo', 'tasks': []})),
      );

      expect(
        KanbanColumn.fromJson(const {
          'name': 'todo',
          'tasks': [
            {'id': 'c1'},
          ],
        }).toString(),
        'KanbanColumn(name: todo, cards: 1)',
      );
      expect(
        const KanbanColumn().toString(),
        'KanbanColumn(name: null, cards: null)',
      );
    });
  });

  group('KanbanAppliedFilters', () {
    test('fromJson：全键正常', () {
      final filters = KanbanAppliedFilters.fromJson(const {
        'tenant': 't1',
        'assignee': 'alice',
        'include_archived': true,
        'only_mine': true,
        'profile': 'work',
      });
      expect(filters.tenant, 't1');
      expect(filters.assignee, 'alice');
      expect(filters.includeArchived, true);
      expect(filters.onlyMine, true);
      expect(filters.profile, 'work');
    });

    test('fromJson：缺失 / 显式 null / 错型', () {
      final missing = KanbanAppliedFilters.fromJson(const {});
      expect(missing.tenant, isNull);
      expect(missing.assignee, isNull);
      expect(missing.includeArchived, isNull);
      expect(missing.onlyMine, isNull);
      expect(missing.profile, isNull);

      final nulls = KanbanAppliedFilters.fromJson(const {
        'tenant': null,
        'assignee': null,
        'include_archived': null,
        'only_mine': null,
        'profile': null,
      });
      expect(nulls.tenant, isNull);
      expect(nulls.assignee, isNull);
      expect(nulls.includeArchived, isNull);
      expect(nulls.onlyMine, isNull);
      expect(nulls.profile, isNull);

      final bad = KanbanAppliedFilters.fromJson(const {
        'tenant': 1,
        'assignee': <Object?>[],
        'include_archived': 'yes',
        'only_mine': 'no',
        'profile': 2.5,
      });
      expect(bad.tenant, '1');
      expect(bad.assignee, isNull);
      expect(bad.includeArchived, true);
      expect(bad.onlyMine, false);
      expect(bad.profile, '2.5');
    });

    test('== 阶梯（tenant → assignee → includeArchived → onlyMine → profile）', () {
      const baseJson = <String, Object?>{
        'tenant': 't1',
        'assignee': 'alice',
        'include_archived': true,
        'only_mine': true,
        'profile': 'work',
      };
      final base = KanbanAppliedFilters.fromJson(baseJson);
      expect(base, equals(KanbanAppliedFilters.fromJson(baseJson)));
      expect(base.hashCode, KanbanAppliedFilters.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'tenant': 't2',
        'assignee': 'bob',
        'include_archived': false,
        'only_mine': false,
        'profile': 'home',
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanAppliedFilters.fromJson({
                ...baseJson,
                entry.key: entry.value,
              }),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }
    });

    test('toString', () {
      expect(
        KanbanAppliedFilters.fromJson(const {'assignee': 'alice'}).toString(),
        'KanbanAppliedFilters(assignee: alice)',
      );
      expect(
        const KanbanAppliedFilters().toString(),
        'KanbanAppliedFilters(assignee: null)',
      );
    });
  });

  group('KanbanStatus', () {
    test('isSupported：7 个受支持值（大小写不敏感）+ 未知值', () {
      const supported = [
        'triage',
        'todo',
        'blocked',
        'ready',
        'running',
        'done',
        'archived',
      ];
      for (final raw in supported) {
        expect(KanbanStatus(raw).isSupported, isTrue, reason: raw);
        expect(KanbanStatus(raw.toUpperCase()).isSupported, isTrue, reason: raw);
      }
      expect(const KanbanStatus('RuNnInG').isSupported, isTrue);
      expect(const KanbanStatus('mystery').isSupported, isFalse);
      expect(const KanbanStatus('').isSupported, isFalse);
      expect(const KanbanStatus('archiv').isSupported, isFalse);
      expect(const KanbanStatus('todo ').isSupported, isFalse);
      // 原始值原样保留（类而非枚举）。
      expect(const KanbanStatus('MYSTERY').rawValue, 'MYSTERY');
    });

    test('== / hashCode / toString', () {
      expect(const KanbanStatus('todo') == const KanbanStatus('todo'), isTrue);
      expect(const KanbanStatus('todo') == const KanbanStatus('done'), isFalse);
      expect(const KanbanStatus('todo') == Object(), isFalse);
      expect(
        const KanbanStatus('todo').hashCode,
        const KanbanStatus('todo').hashCode,
      );
      expect(const KanbanStatus('todo').toString(), 'KanbanStatus(todo)');
      expect(const KanbanStatus('').toString(), 'KanbanStatus()');
    });
  });

  group('KanbanCard', () {
    test('fromJson：全键正常（20 字段）', () {
      final card = KanbanCard.fromJson(const {
        'id': 'card_1',
        'title': 't',
        'status': 'ready',
        'assignee': 'alice',
        'body': 'b',
        'tenant': 't1',
        'priority': 1,
        'comment_count': 2,
        'link_counts': {'parents': 1, 'children': 2},
        'age_seconds': 1200.5,
        'created_at': 'c',
        'updated_at': 'u',
        'workspace_kind': 'hermes',
        'workspace_path': '/p',
        'skills': ['dart'],
        'max_runtime_seconds': 600,
        'currentRunId': 'r1',
        'claim_lock': 'l',
        'claim_expires': 'e',
        'workerPid': 'w',
      });
      expect(card.cardID, 'card_1');
      expect(card.title, 't');
      expect(card.status!.rawValue, 'ready');
      expect(card.assignee, 'alice');
      expect(card.body, 'b');
      expect(card.tenant, 't1');
      expect(card.priority, 1);
      expect(card.commentCount, 2);
      expect(card.linkCounts!.parents, 1);
      expect(card.linkCounts!.children, 2);
      expect(card.ageSeconds, 1200.5);
      expect(card.createdAt, 'c');
      expect(card.updatedAt, 'u');
      expect(card.workspaceKind, 'hermes');
      expect(card.workspacePath, '/p');
      expect(card.skills, ['dart']);
      expect(card.maxRuntimeSeconds, 600);
      expect(card.currentRunID, 'r1');
      expect(card.claimLock, 'l');
      expect(card.claimExpires, 'e');
      expect(card.workerID, 'w');
    });

    test('fromJson：缺失 / 显式 null → 全 null（status 为 null 而非空对象）', () {
      final missing = KanbanCard.fromJson(const {});
      expect(missing.cardID, isNull);
      expect(missing.title, isNull);
      expect(missing.status, isNull);
      expect(missing.assignee, isNull);
      expect(missing.body, isNull);
      expect(missing.tenant, isNull);
      expect(missing.priority, isNull);
      expect(missing.commentCount, isNull);
      expect(missing.linkCounts, isNull);
      expect(missing.ageSeconds, isNull);
      expect(missing.createdAt, isNull);
      expect(missing.updatedAt, isNull);
      expect(missing.workspaceKind, isNull);
      expect(missing.workspacePath, isNull);
      expect(missing.skills, isNull);
      expect(missing.maxRuntimeSeconds, isNull);
      expect(missing.currentRunID, isNull);
      expect(missing.claimLock, isNull);
      expect(missing.claimExpires, isNull);
      expect(missing.workerID, isNull);

      final nulls = KanbanCard.fromJson(const {
        'id': null,
        'status': null,
        'link_counts': null,
        'skills': null,
        'age_seconds': null,
      });
      expect(nulls.cardID, isNull);
      expect(nulls.status, isNull);
      expect(nulls.linkCounts, isNull);
      expect(nulls.skills, isNull);
      expect(nulls.ageSeconds, isNull);
    });

    test('fromJson：空集合 / 错型 / 宽容转换', () {
      final card = KanbanCard.fromJson(const {
        'id': 1,
        'title': 1.5,
        'status': 'mystery',
        'priority': 1.9,
        'comment_count': ' 3 ',
        'link_counts': 'bad',
        'age_seconds': '1200.5',
        'skills': <Object?>[],
      });
      expect(card.cardID, '1');
      expect(card.title, '1.5');
      expect(card.status!.rawValue, 'mystery');
      expect(card.status!.isSupported, isFalse);
      expect(card.priority, 1);
      expect(card.commentCount, 3);
      expect(card.linkCounts, isNull);
      expect(card.ageSeconds, 1200.5);
      expect(card.skills, isEmpty);

      expect(KanbanCard.fromJson(const {'age_seconds': 7}).ageSeconds, 7.0);
      expect(KanbanCard.fromJson(const {'age_seconds': 'x'}).ageSeconds, isNull);
      expect(KanbanCard.fromJson(const {'skills': 'bad'}).skills, isNull);
      expect(KanbanCard.fromJson(const {'skills': [1]}).skills, isNull);
      expect(KanbanCard.fromJson(const {'status': 7}).status!.rawValue, '7');
      expect(
        KanbanCard.fromJson(const {
          'link_counts': {'parents': 1},
        }).linkCounts!.children,
        isNull,
      );
    });

    test('staleness：阈值边界逐分支', () {
      KanbanStaleness st(Object? status, Object? age) {
        final json = <String, Object?>{};
        if (status != null) json['status'] = status;
        if (age != null) json['age_seconds'] = age;
        return KanbanCard.fromJson(json).staleness;
      }

      // 无 status 或无 age → none（两个方向都测）。
      expect(st('running', null), KanbanStaleness.none);
      expect(st(null, 999999), KanbanStaleness.none);
      expect(st(null, null), KanbanStaleness.none);

      // running：>=3600 critical / >=600 warning / 其余 none。
      expect(st('running', 3600), KanbanStaleness.critical);
      expect(st('running', 3599), KanbanStaleness.warning);
      expect(st('running', 600), KanbanStaleness.warning);
      expect(st('running', 599), KanbanStaleness.none);
      expect(st('running', 0), KanbanStaleness.none);

      // ready：>=3600 warning / 其余 none。
      expect(st('ready', 3600), KanbanStaleness.warning);
      expect(st('ready', 3599), KanbanStaleness.none);
      expect(st('ready', 999999), KanbanStaleness.warning);

      // blocked：>=86400 critical / >=3600 warning / 其余 none。
      expect(st('blocked', 86400), KanbanStaleness.critical);
      expect(st('blocked', 86399), KanbanStaleness.warning);
      expect(st('blocked', 3600), KanbanStaleness.warning);
      expect(st('blocked', 3599), KanbanStaleness.none);

      // 其余 status（含受支持但与陈旧度无关的、未知的、大写未知的）→ none。
      expect(st('todo', 999999), KanbanStaleness.none);
      expect(st('done', 999999), KanbanStaleness.none);
      expect(st('mystery', 999999), KanbanStaleness.none);
      expect(st('RUNNING', 999999), KanbanStaleness.none);
      expect(st('Blocked', 999999), KanbanStaleness.none);
    });

    test('replacingStatus：running 保留运行字段，其余清空', () {
      final running = KanbanCard.fromJson(const {
        'id': 'c1',
        'title': 't',
        'status': 'running',
        'age_seconds': 7200.0,
        'skills': ['dart'],
        'currentRunId': 'r1',
        'claim_lock': 'l',
        'claim_expires': 'e',
        'workerPid': 'w',
      });

      final stillRunning = running.replacingStatus('running');
      expect(stillRunning.status!.rawValue, 'running');
      expect(stillRunning.currentRunID, 'r1');
      expect(stillRunning.claimLock, 'l');
      expect(stillRunning.claimExpires, 'e');
      expect(stillRunning.workerID, 'w');
      // 其余字段原样复制。
      expect(stillRunning.cardID, 'c1');
      expect(stillRunning.title, 't');
      expect(stillRunning.ageSeconds, 7200.0);
      expect(stillRunning.skills, ['dart']);
      expect(stillRunning, equals(running));

      final done = running.replacingStatus('done');
      expect(done.status!.rawValue, 'done');
      expect(done.currentRunID, isNull);
      expect(done.claimLock, isNull);
      expect(done.claimExpires, isNull);
      expect(done.workerID, isNull);
      expect(done.cardID, 'c1');
      expect(done.skills, ['dart']);

      // 大小写不匹配 → 按非 running 处理（比较是精确字面量）。
      final upper = running.replacingStatus('RUNNING');
      expect(upper.status!.rawValue, 'RUNNING');
      expect(upper.currentRunID, isNull);
      expect(upper.claimLock, isNull);
      expect(upper.claimExpires, isNull);
      expect(upper.workerID, isNull);
    });

    test('== 阶梯：20 字段逐字段差异 + hashCode', () {
      const baseJson = <String, Object?>{
        'id': 'card_1',
        'title': 't',
        'status': 'ready',
        'assignee': 'alice',
        'body': 'b',
        'tenant': 't1',
        'priority': 1,
        'comment_count': 2,
        'link_counts': {'parents': 1, 'children': 2},
        'age_seconds': 1200.0,
        'created_at': 'c',
        'updated_at': 'u',
        'workspace_kind': 'hermes',
        'workspace_path': '/p',
        'skills': ['dart'],
        'max_runtime_seconds': 600,
        'currentRunId': 'r1',
        'claim_lock': 'l',
        'claim_expires': 'e',
        'workerPid': 'w',
      };
      final base = KanbanCard.fromJson(baseJson);
      expect(base, equals(KanbanCard.fromJson(baseJson)));
      expect(base.hashCode, KanbanCard.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'id': 'card_2',
        'title': 't2',
        'status': 'todo',
        'assignee': 'bob',
        'body': 'b2',
        'tenant': 't2',
        'priority': 9,
        'comment_count': 9,
        'link_counts': {'parents': 9, 'children': 2},
        'age_seconds': 1.0,
        'created_at': 'c2',
        'updated_at': 'u2',
        'workspace_kind': 'other',
        'workspace_path': '/q',
        'skills': ['dart', 'x'],
        'max_runtime_seconds': 1,
        'currentRunId': 'r2',
        'claim_lock': 'l2',
        'claim_expires': 'e2',
        'workerPid': 'w2',
      };
      for (final entry in replacements.entries) {
        expect(
          base == KanbanCard.fromJson({...baseJson, entry.key: entry.value}),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      // skills 同长度不同元素 / 一侧 null / identical 三条路径。
      expect(
        base == KanbanCard.fromJson({...baseJson, 'skills': ['other']}),
        isFalse,
      );
      expect(
        base == KanbanCard.fromJson({...baseJson, 'skills': null}),
        isFalse,
      );
      final skills = ['dart'];
      expect(
        KanbanCard(skills: skills) == KanbanCard(skills: skills),
        isTrue,
      );
      expect(const KanbanCard() == const KanbanCard(), isTrue);
    });

    test('toString', () {
      expect(
        KanbanCard.fromJson(const {
          'id': 'card_1',
          'title': 't',
        }).toString(),
        'KanbanCard(cardID: card_1, title: t)',
      );
      expect(
        const KanbanCard().toString(),
        'KanbanCard(cardID: null, title: null)',
      );
    });
  });

  // ==========================================================================
  // 14.4 卡片详情 / 评论 / 事件 / 运行 / 日志
  // ==========================================================================

  group('KanbanCardDetailEnvelope', () {
    test('fromJson：全键正常（card 的键是 task）', () {
      final envelope = KanbanCardDetailEnvelope.fromJson({
        'task': {'id': 'card_1', 'title': 't'},
        'comments': [
          {'id': 'cm1', 'taskId': 'card_1'},
        ],
        'events': [
          {'id': 'e1', 'kind': 'created'},
        ],
        'links': {
          'parents': ['card_0'],
          'children': ['card_2'],
        },
        'runs': [
          {'id': 'run_1'},
        ],
        'read_only': true,
      });
      expect(envelope.card!.cardID, 'card_1');
      expect(envelope.comments!.single.commentID, 'cm1');
      expect(envelope.events!.single.kind, 'created');
      expect(envelope.links!.prerequisites, ['card_0']);
      expect(envelope.links!.dependents, ['card_2']);
      expect(envelope.runs!.single.runID, 'run_1');
      expect(envelope.readOnly, true);
    });

    test('fromJson：缺失 / 显式 null / 空集合 / 错型', () {
      final missing = KanbanCardDetailEnvelope.fromJson(const {});
      expect(missing.card, isNull);
      expect(missing.comments, isNull);
      expect(missing.events, isNull);
      expect(missing.links, isNull);
      expect(missing.runs, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanCardDetailEnvelope.fromJson(const {
        'task': null,
        'comments': null,
        'events': null,
        'links': null,
        'runs': null,
        'read_only': null,
      });
      expect(nulls.card, isNull);
      expect(nulls.comments, isNull);
      expect(nulls.events, isNull);
      expect(nulls.links, isNull);
      expect(nulls.runs, isNull);
      expect(nulls.readOnly, isNull);

      final empties = KanbanCardDetailEnvelope.fromJson(const {
        'comments': <Object?>[],
        'events': <Object?>[],
        'runs': <Object?>[],
      });
      expect(empties.comments, isEmpty);
      expect(empties.events, isEmpty);
      expect(empties.runs, isEmpty);

      final bad = KanbanCardDetailEnvelope.fromJson(const {
        'task': 'bad',
        'comments': 'bad',
        'events': 'bad',
        'links': 'bad',
        'runs': 'bad',
        'read_only': 'yes',
      });
      expect(bad.card, isNull);
      expect(bad.comments, isNull);
      expect(bad.events, isNull);
      expect(bad.links, isNull);
      expect(bad.runs, isNull);
      expect(bad.readOnly, true);

      // 数组含非对象元素 → 整数组 null。
      expect(
        KanbanCardDetailEnvelope.fromJson(const {
          'comments': [
            {'id': 'c'},
            1,
          ],
        }).comments,
        isNull,
      );
      expect(
        KanbanCardDetailEnvelope.fromJson(const {
          'runs': ['x'],
        }).runs,
        isNull,
      );
    });

    test('== 阶梯（card → comments → events → links → runs → readOnly）', () {
      const baseJson = <String, Object?>{
        'task': {'id': 'card_1'},
        'comments': [
          {'id': 'cm1'},
        ],
        'events': [
          {'id': 'e1'},
        ],
        'links': {'parents': ['p']},
        'runs': [
          {'id': 'run_1'},
        ],
        'read_only': true,
      };
      final base = KanbanCardDetailEnvelope.fromJson(baseJson);
      expect(base, equals(KanbanCardDetailEnvelope.fromJson(baseJson)));
      expect(base.hashCode, KanbanCardDetailEnvelope.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'task': {'id': 'card_2'},
        'comments': [
          {'id': 'cm2'},
        ],
        'events': [
          {'id': 'e2'},
        ],
        'links': {'parents': ['q']},
        'runs': [
          {'id': 'run_2'},
        ],
        'read_only': false,
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanCardDetailEnvelope.fromJson({
                ...baseJson,
                entry.key: entry.value,
              }),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      // comments / events / runs 的一侧 null 与长度差异分支。
      expect(
        base ==
            KanbanCardDetailEnvelope.fromJson({
              ...baseJson,
              'comments': null,
              'events': null,
              'runs': null,
            }),
        isFalse,
      );
      expect(
        base ==
            KanbanCardDetailEnvelope.fromJson({
              ...baseJson,
              'events': <Object?>[],
            }),
        isFalse,
      );
      expect(
        base ==
            KanbanCardDetailEnvelope.fromJson({
              ...baseJson,
              'runs': [
                {'id': 'run_1'},
                {'id': 'run_3'},
              ],
            }),
        isFalse,
      );
    });

    test('toString', () {
      expect(
        KanbanCardDetailEnvelope.fromJson(const {
          'task': {'id': 'card_1', 'title': 't'},
        }).toString(),
        'KanbanCardDetailEnvelope(card: KanbanCard(cardID: card_1, title: t))',
      );
      expect(
        const KanbanCardDetailEnvelope().toString(),
        'KanbanCardDetailEnvelope(card: null)',
      );
    });
  });

  group('KanbanCardMutationEnvelope', () {
    test('fromJson：task / read_only 正常', () {
      final envelope = KanbanCardMutationEnvelope.fromJson(const {
        'task': {'id': 'card_1'},
        'read_only': false,
      });
      expect(envelope.card!.cardID, 'card_1');
      expect(envelope.readOnly, false);
    });

    test('fromJson：缺失 / 显式 null / 错型', () {
      final missing = KanbanCardMutationEnvelope.fromJson(const {});
      expect(missing.card, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanCardMutationEnvelope.fromJson(const {
        'task': null,
        'read_only': null,
      });
      expect(nulls.card, isNull);
      expect(nulls.readOnly, isNull);

      expect(
        KanbanCardMutationEnvelope.fromJson(const {
          'task': 'bad',
        }).card,
        isNull,
      );
      expect(
        KanbanCardMutationEnvelope.fromJson(const {
          'task': <Object?>[],
        }).card,
        isNull,
      );
      expect(
        KanbanCardMutationEnvelope.fromJson(const {
          'read_only': 1,
        }).readOnly,
        true,
      );
      expect(
        KanbanCardMutationEnvelope.fromJson(const {
          'read_only': 'nope',
        }).readOnly,
        isNull,
      );
    });

    test('== 阶梯（card → readOnly）+ hashCode + toString', () {
      const baseJson = <String, Object?>{'task': {'id': 'c1'}, 'read_only': true};
      final base = KanbanCardMutationEnvelope.fromJson(baseJson);
      expect(base, equals(KanbanCardMutationEnvelope.fromJson(baseJson)));
      expect(
        base.hashCode,
        KanbanCardMutationEnvelope.fromJson(baseJson).hashCode,
      );
      expect(base == Object(), isFalse);

      // 第 1 行：仅 card 不同。
      expect(
        base ==
            KanbanCardMutationEnvelope.fromJson(const {
              'task': {'id': 'c2'},
              'read_only': true,
            }),
        isFalse,
      );
      // 第 1 行：一侧 card 为 null。
      expect(
        base ==
            KanbanCardMutationEnvelope.fromJson(const {'read_only': true}),
        isFalse,
      );
      // 第 2 行：仅 readOnly 不同。
      expect(
        base ==
            KanbanCardMutationEnvelope.fromJson(const {
              'task': {'id': 'c1'},
              'read_only': false,
            }),
        isFalse,
      );

      expect(
        KanbanCardMutationEnvelope.fromJson(const {
          'task': {'id': 'c1', 'title': 't'},
        }).toString(),
        'KanbanCardMutationEnvelope(card: KanbanCard(cardID: c1, title: t))',
      );
      expect(
        const KanbanCardMutationEnvelope().toString(),
        'KanbanCardMutationEnvelope(card: null)',
      );
    });
  });

  group('KanbanComment', () {
    test('fromJson：全键正常 / 部分缺失 / 错型', () {
      final comment = KanbanComment.fromJson(const {
        'id': 'cm1',
        'taskId': 'card_1',
        'author': 'alice',
        'body': 'b',
        'created_at': 'c',
      });
      expect(comment.commentID, 'cm1');
      expect(comment.cardID, 'card_1');
      expect(comment.author, 'alice');
      expect(comment.body, 'b');
      expect(comment.createdAt, 'c');

      final missing = KanbanComment.fromJson(const {});
      expect(missing.commentID, isNull);
      expect(missing.cardID, isNull);
      expect(missing.author, isNull);
      expect(missing.body, isNull);
      expect(missing.createdAt, isNull);

      final nulls = KanbanComment.fromJson(const {
        'id': null,
        'taskId': null,
        'author': null,
        'body': null,
        'created_at': null,
      });
      expect(nulls.commentID, isNull);
      expect(nulls.cardID, isNull);
      expect(nulls.author, isNull);
      expect(nulls.body, isNull);
      expect(nulls.createdAt, isNull);

      final bad = KanbanComment.fromJson(const {
        'id': 1,
        'taskId': <Object?>[],
        'author': true,
        'body': 2.5,
        'created_at': <String, Object?>{},
      });
      expect(bad.commentID, '1');
      expect(bad.cardID, isNull);
      expect(bad.author, 'true');
      expect(bad.body, '2.5');
      expect(bad.createdAt, isNull);
    });

    test('presentationID：有 id 用 id，无 id 用 [cardID, author, createdAt, body] 拼', () {
      expect(KanbanComment.fromJson(const {'id': 'cm1'}).presentationID, 'cm1');
      expect(KanbanComment.fromJson(const {'id': 7}).presentationID, '7');
      expect(
        KanbanComment.fromJson(const {
          'taskId': 'c',
          'author': 'a',
          'created_at': 't',
          'body': 'b',
        }).presentationID,
        'c|a|t|b',
      );
      // 缺字段的键位被跳过，不留空段。
      expect(KanbanComment.fromJson(const {'author': 'a'}).presentationID, 'a');
      expect(
        KanbanComment.fromJson(const {'cardID': 'c', 'body': 'b'}).presentationID,
        'b',
      );
      expect(KanbanComment.fromJson(const {}).presentationID, '');
    });

    test('== 阶梯（commentID → cardID → author → body → createdAt）+ toString', () {
      const baseJson = <String, Object?>{
        'id': 'cm1',
        'taskId': 'c1',
        'author': 'alice',
        'body': 'b',
        'created_at': 't',
      };
      final base = KanbanComment.fromJson(baseJson);
      expect(base, equals(KanbanComment.fromJson(baseJson)));
      expect(base.hashCode, KanbanComment.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'id': 'cm2',
        'taskId': 'c2',
        'author': 'bob',
        'body': 'b2',
        'created_at': 't2',
      };
      for (final entry in replacements.entries) {
        expect(
          base == KanbanComment.fromJson({...baseJson, entry.key: entry.value}),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      expect(
        KanbanComment.fromJson(const {'id': 'cm1'}).toString(),
        'KanbanComment(commentID: cm1)',
      );
      expect(
        const KanbanComment().toString(),
        'KanbanComment(commentID: null)',
      );
    });
  });

  group('KanbanDetailEvent', () {
    test('fromJson：全键正常 / 缺失 / null / 错型', () {
      final event = KanbanDetailEvent.fromJson(const {
        'id': 'e1',
        'taskId': 'c1',
        'run_id': 'r1',
        'kind': 'status_change',
        'created_at': 't',
        'payload': {'status': 'ready'},
      });
      expect(event.eventID, 'e1');
      expect(event.cardID, 'c1');
      expect(event.runID, 'r1');
      expect(event.kind, 'status_change');
      expect(event.createdAt, 't');
      expect(event.payload!.status, 'ready');

      final missing = KanbanDetailEvent.fromJson(const {});
      expect(missing.eventID, isNull);
      expect(missing.cardID, isNull);
      expect(missing.runID, isNull);
      expect(missing.kind, isNull);
      expect(missing.createdAt, isNull);
      expect(missing.payload, isNull);

      final nulls = KanbanDetailEvent.fromJson(const {
        'id': null,
        'taskId': null,
        'run_id': null,
        'kind': null,
        'created_at': null,
        'payload': null,
      });
      expect(nulls.eventID, isNull);
      expect(nulls.cardID, isNull);
      expect(nulls.runID, isNull);
      expect(nulls.kind, isNull);
      expect(nulls.createdAt, isNull);
      expect(nulls.payload, isNull);

      final bad = KanbanDetailEvent.fromJson(const {
        'id': 3,
        'run_id': <Object?>[],
        'payload': 'bad',
      });
      expect(bad.eventID, '3');
      expect(bad.runID, isNull);
      expect(bad.payload, isNull);
      // payload 是空对象 → 解出「全 null 的 payload」而非 null。
      final emptyPayload = KanbanDetailEvent.fromJson(const {
        'payload': <String, Object?>{},
      }).payload;
      expect(emptyPayload, isNotNull);
      expect(emptyPayload!.status, isNull);
      expect(emptyPayload.fields, isNull);
    });

    test('presentationID：有 id 用 id，无 id 用 [cardID, runID, kind, createdAt] 拼', () {
      expect(KanbanDetailEvent.fromJson(const {'id': 'e1'}).presentationID, 'e1');
      expect(
        KanbanDetailEvent.fromJson(const {
          'taskId': 'c',
          'run_id': 'r',
          'kind': 'k',
          'created_at': 't',
        }).presentationID,
        'c|r|k|t',
      );
      expect(
        KanbanDetailEvent.fromJson(const {'kind': 'k'}).presentationID,
        'k',
      );
      expect(KanbanDetailEvent.fromJson(const {}).presentationID, '');
    });

    test('== 阶梯（eventID → cardID → runID → kind → createdAt → payload）+ toString', () {
      const baseJson = <String, Object?>{
        'id': 'e1',
        'taskId': 'c1',
        'run_id': 'r1',
        'kind': 'k',
        'created_at': 't',
        'payload': {'status': 'ready'},
      };
      final base = KanbanDetailEvent.fromJson(baseJson);
      expect(base, equals(KanbanDetailEvent.fromJson(baseJson)));
      expect(base.hashCode, KanbanDetailEvent.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'id': 'e2',
        'taskId': 'c2',
        'run_id': 'r2',
        'kind': 'k2',
        'created_at': 't2',
        'payload': {'status': 'done'},
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanDetailEvent.fromJson({...baseJson, entry.key: entry.value}),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      expect(
        KanbanDetailEvent.fromJson(const {
          'id': 'e1',
          'kind': 'k',
        }).toString(),
        'KanbanDetailEvent(eventID: e1, kind: k)',
      );
      expect(
        const KanbanDetailEvent().toString(),
        'KanbanDetailEvent(eventID: null, kind: null)',
      );
    });
  });

  group('KanbanDetailEventPayload', () {
    test('fromJson：全键正常 / 缺失 / null / 错型 / 空集合', () {
      final payload = KanbanDetailEventPayload.fromJson(const {
        'status': 'ready',
        'reason': 'r',
        'summary': 's',
        'fields': ['a', 'b'],
      });
      expect(payload.status, 'ready');
      expect(payload.reason, 'r');
      expect(payload.summary, 's');
      expect(payload.fields, ['a', 'b']);

      final missing = KanbanDetailEventPayload.fromJson(const {});
      expect(missing.status, isNull);
      expect(missing.reason, isNull);
      expect(missing.summary, isNull);
      expect(missing.fields, isNull);

      final nulls = KanbanDetailEventPayload.fromJson(const {
        'status': null,
        'reason': null,
        'summary': null,
        'fields': null,
      });
      expect(nulls.status, isNull);
      expect(nulls.reason, isNull);
      expect(nulls.summary, isNull);
      expect(nulls.fields, isNull);

      expect(
        KanbanDetailEventPayload.fromJson(const {
          'fields': <String>[],
        }).fields,
        isEmpty,
      );
      expect(
        KanbanDetailEventPayload.fromJson(const {
          'fields': [1],
        }).fields,
        isNull,
      );
      expect(
        KanbanDetailEventPayload.fromJson(const {
          'fields': 'bad',
        }).fields,
        isNull,
      );
      expect(
        KanbanDetailEventPayload.fromJson(const {
          'status': 1,
        }).status,
        '1',
      );
    });

    test('== 阶梯（status → reason → summary → fields）+ hashCode + toString', () {
      const baseJson = <String, Object?>{
        'status': 'ready',
        'reason': 'r',
        'summary': 's',
        'fields': ['a'],
      };
      final base = KanbanDetailEventPayload.fromJson(baseJson);
      expect(base, equals(KanbanDetailEventPayload.fromJson(baseJson)));
      expect(base.hashCode, KanbanDetailEventPayload.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'status': 'done',
        'reason': 'r2',
        'summary': 's2',
        'fields': ['b'],
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanDetailEventPayload.fromJson({
                ...baseJson,
                entry.key: entry.value,
              }),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      // fields 的一侧 null / 长度差异 / identical 三条路径。
      expect(
        base == KanbanDetailEventPayload.fromJson({...baseJson, 'fields': null}),
        isFalse,
      );
      expect(
        base ==
            KanbanDetailEventPayload.fromJson({
              ...baseJson,
              'fields': <String>[],
            }),
        isFalse,
      );
      final fields = ['a'];
      expect(
        KanbanDetailEventPayload(fields: fields) ==
            KanbanDetailEventPayload(fields: fields),
        isTrue,
      );
      expect(
        const KanbanDetailEventPayload() ==
            const KanbanDetailEventPayload(),
        isTrue,
      );

      expect(
        KanbanDetailEventPayload.fromJson(const {
          'status': 'ready',
        }).toString(),
        'KanbanDetailEventPayload(status: ready)',
      );
      expect(
        const KanbanDetailEventPayload().toString(),
        'KanbanDetailEventPayload(status: null)',
      );
    });
  });

  group('KanbanDependencyLinks', () {
    test('fromJson：parents → prerequisites / children → dependents', () {
      final links = KanbanDependencyLinks.fromJson(const {
        'parents': ['p1', 'p2'],
        'children': ['c1'],
      });
      expect(links.prerequisites, ['p1', 'p2']);
      expect(links.dependents, ['c1']);
    });

    test('fromJson：缺失 / null / 空集合 / 错型', () {
      final missing = KanbanDependencyLinks.fromJson(const {});
      expect(missing.prerequisites, isNull);
      expect(missing.dependents, isNull);

      final nulls = KanbanDependencyLinks.fromJson(const {
        'parents': null,
        'children': null,
      });
      expect(nulls.prerequisites, isNull);
      expect(nulls.dependents, isNull);

      final empties = KanbanDependencyLinks.fromJson(const {
        'parents': <String>[],
        'children': <String>[],
      });
      expect(empties.prerequisites, isEmpty);
      expect(empties.dependents, isEmpty);

      expect(
        KanbanDependencyLinks.fromJson(const {
          'parents': 'bad',
        }).prerequisites,
        isNull,
      );
      expect(
        KanbanDependencyLinks.fromJson(const {
          'parents': [1],
        }).prerequisites,
        isNull,
      );
    });

    test('== 阶梯（prerequisites → dependents）+ hashCode + toString', () {
      const baseJson = <String, Object?>{
        'parents': ['p'],
        'children': ['c'],
      };
      final base = KanbanDependencyLinks.fromJson(baseJson);
      expect(base, equals(KanbanDependencyLinks.fromJson(baseJson)));
      expect(base.hashCode, KanbanDependencyLinks.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      // 第 1 行：仅 prerequisites 不同。
      expect(
        base ==
            KanbanDependencyLinks.fromJson(const {
              'parents': ['p2'],
              'children': ['c'],
            }),
        isFalse,
      );
      // 第 2 行：仅 dependents 不同（走完整条链）。
      expect(
        base ==
            KanbanDependencyLinks.fromJson(const {
              'parents': ['p'],
              'children': ['c2'],
            }),
        isFalse,
      );
      // 一侧 null 与长度差异。
      expect(
        base ==
            KanbanDependencyLinks.fromJson(const {'children': ['c']}),
        isFalse,
      );
      expect(
        base ==
            KanbanDependencyLinks.fromJson(const {
              'parents': ['p', 'q'],
              'children': ['c'],
            }),
        isFalse,
      );

      expect(
        KanbanDependencyLinks.fromJson(const {
          'parents': ['p'],
        }).toString(),
        'KanbanDependencyLinks(prerequisites: [p])',
      );
      expect(
        const KanbanDependencyLinks().toString(),
        'KanbanDependencyLinks(prerequisites: null)',
      );
    });
  });

  group('KanbanDispatchRun', () {
    test('fromJson：全键正常', () {
      final run = KanbanDispatchRun.fromJson(const {
        'id': 'run_1',
        'status': 'completed',
        'outcome': 'success',
        'summary': 's',
        'error': null,
        'started_at': 's1',
        'endedAt': 'e1',
        'workerPid': 'w1',
        'log_tail': 'tail',
      });
      expect(run.runID, 'run_1');
      expect(run.status, 'completed');
      expect(run.outcome, 'success');
      expect(run.summary, 's');
      expect(run.error, isNull);
      expect(run.startedAt, 's1');
      expect(run.finishedAt, 'e1');
      expect(run.workerID, 'w1');
      expect(run.logTail, 'tail');
    });

    test('runID 回退链：id → runId（逐键位）', () {
      expect(KanbanDispatchRun.fromJson(const {'id': 'a'}).runID, 'a');
      expect(KanbanDispatchRun.fromJson(const {'runId': 'b'}).runID, 'b');
      // 首键优先。
      expect(
        KanbanDispatchRun.fromJson(const {
          'id': 'a',
          'runId': 'b',
        }).runID,
        'a',
      );
      // 首键为 null / 解不出 → 继续尝试后键。
      expect(
        KanbanDispatchRun.fromJson(const {
          'id': null,
          'runId': 'b',
        }).runID,
        'b',
      );
      expect(KanbanDispatchRun.fromJson(const {}).runID, isNull);
      // 近似键名不识别。
      expect(KanbanDispatchRun.fromJson(const {'run_id': 'x'}).runID, isNull);
      expect(KanbanDispatchRun.fromJson(const {'runID': 'x'}).runID, isNull);
    });

    test('finishedAt 回退链：endedAt → finished_at（逐键位）', () {
      expect(KanbanDispatchRun.fromJson(const {'endedAt': 'e'}).finishedAt, 'e');
      expect(
        KanbanDispatchRun.fromJson(const {'finished_at': 'f'}).finishedAt,
        'f',
      );
      expect(
        KanbanDispatchRun.fromJson(const {
          'endedAt': 'e',
          'finished_at': 'f',
        }).finishedAt,
        'e',
      );
      expect(
        KanbanDispatchRun.fromJson(const {
          'endedAt': null,
          'finished_at': 'f',
        }).finishedAt,
        'f',
      );
      expect(KanbanDispatchRun.fromJson(const {}).finishedAt, isNull);
      // 近似键名不识别（camel 的 finishedAt）。
      expect(
        KanbanDispatchRun.fromJson(const {'finishedAt': 'x'}).finishedAt,
        isNull,
      );
    });

    test('workerID 回退链：workerPid → worker（逐键位）', () {
      expect(KanbanDispatchRun.fromJson(const {'workerPid': 'w'}).workerID, 'w');
      expect(KanbanDispatchRun.fromJson(const {'worker': 'v'}).workerID, 'v');
      expect(
        KanbanDispatchRun.fromJson(const {
          'workerPid': 'w',
          'worker': 'v',
        }).workerID,
        'w',
      );
      expect(
        KanbanDispatchRun.fromJson(const {
          'workerPid': null,
          'worker': 'v',
        }).workerID,
        'v',
      );
      expect(KanbanDispatchRun.fromJson(const {}).workerID, isNull);
      // 近似键名不识别。
      expect(KanbanDispatchRun.fromJson(const {'worker_id': 'x'}).workerID, isNull);
      expect(KanbanDispatchRun.fromJson(const {'workerID': 'x'}).workerID, isNull);
    });

    test('fromJson：缺失 / 显式 null / 错型', () {
      final missing = KanbanDispatchRun.fromJson(const {});
      expect(missing.status, isNull);
      expect(missing.outcome, isNull);
      expect(missing.summary, isNull);
      expect(missing.error, isNull);
      expect(missing.startedAt, isNull);
      expect(missing.logTail, isNull);

      final nulls = KanbanDispatchRun.fromJson(const {
        'status': null,
        'outcome': null,
        'summary': null,
        'error': null,
        'started_at': null,
        'log_tail': null,
      });
      expect(nulls.status, isNull);
      expect(nulls.outcome, isNull);
      expect(nulls.summary, isNull);
      expect(nulls.error, isNull);
      expect(nulls.startedAt, isNull);
      expect(nulls.logTail, isNull);

      final bad = KanbanDispatchRun.fromJson(const {
        'status': 1,
        'outcome': <Object?>[],
        'summary': true,
        'error': 2.5,
        'started_at': <String, Object?>{},
        'log_tail': 9,
      });
      expect(bad.status, '1');
      expect(bad.outcome, isNull);
      expect(bad.summary, 'true');
      expect(bad.error, '2.5');
      expect(bad.startedAt, isNull);
      expect(bad.logTail, '9');
    });

    test('presentationID：有 runID 用 runID，否则 4 段拼接', () {
      expect(KanbanDispatchRun.fromJson(const {'id': 'r1'}).presentationID, 'r1');
      expect(
        KanbanDispatchRun.fromJson(const {
          'status': 'completed',
          'outcome': 'success',
          'started_at': 's',
          'endedAt': 'e',
        }).presentationID,
        'completed|success|s|e',
      );
      expect(
        KanbanDispatchRun.fromJson(const {'status': 'running'}).presentationID,
        'running',
      );
      expect(KanbanDispatchRun.fromJson(const {}).presentationID, '');
    });

    test('== 阶梯：9 字段逐字段差异 + hashCode + toString', () {
      const baseJson = <String, Object?>{
        'id': 'run_1',
        'status': 'completed',
        'outcome': 'success',
        'summary': 's',
        'error': 'e',
        'started_at': 's1',
        'endedAt': 'e1',
        'workerPid': 'w1',
        'log_tail': 'tail',
      };
      final base = KanbanDispatchRun.fromJson(baseJson);
      expect(base, equals(KanbanDispatchRun.fromJson(baseJson)));
      expect(base.hashCode, KanbanDispatchRun.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'id': 'run_2',
        'status': 'failed',
        'outcome': 'error',
        'summary': 's2',
        'error': 'e2',
        'started_at': 's2',
        'endedAt': 'e2',
        'workerPid': 'w2',
        'log_tail': 'tail2',
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanDispatchRun.fromJson({...baseJson, entry.key: entry.value}),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      expect(
        KanbanDispatchRun.fromJson(const {
          'id': 'run_1',
          'status': 'completed',
        }).toString(),
        'KanbanDispatchRun(runID: run_1, status: completed)',
      );
      expect(
        const KanbanDispatchRun().toString(),
        'KanbanDispatchRun(runID: null, status: null)',
      );
    });
  });

  group('KanbanWorkerLog', () {
    test('fromJson：全键正常（path 刻意不保留）', () {
      final log = KanbanWorkerLog.fromJson(const {
        'taskId': 'card_1',
        'exists': true,
        'size_bytes': 1024,
        'content': 'text',
        'truncated': false,
        'path': '/var/log/work.log',
      });
      expect(log.cardID, 'card_1');
      expect(log.exists, true);
      expect(log.sizeBytes, 1024);
      expect(log.content, 'text');
      expect(log.truncated, false);
    });

    test('fromJson：缺失 / 显式 null / 错型', () {
      final missing = KanbanWorkerLog.fromJson(const {});
      expect(missing.cardID, isNull);
      expect(missing.exists, isNull);
      expect(missing.sizeBytes, isNull);
      expect(missing.content, isNull);
      expect(missing.truncated, isNull);

      final nulls = KanbanWorkerLog.fromJson(const {
        'taskId': null,
        'exists': null,
        'size_bytes': null,
        'content': null,
        'truncated': null,
      });
      expect(nulls.cardID, isNull);
      expect(nulls.exists, isNull);
      expect(nulls.sizeBytes, isNull);
      expect(nulls.content, isNull);
      expect(nulls.truncated, isNull);

      final bad = KanbanWorkerLog.fromJson(const {
        'taskId': 1,
        'exists': 'yes',
        'size_bytes': '2bad',
        'content': <Object?>[],
        'truncated': 0,
      });
      expect(bad.cardID, '1');
      expect(bad.exists, true);
      expect(bad.sizeBytes, isNull);
      expect(bad.content, isNull);
      expect(bad.truncated, false);

      expect(
        KanbanWorkerLog.fromJson(const {
          'size_bytes': 12.9,
        }).sizeBytes,
        12,
      );
    });

    test('== 阶梯（cardID → exists → sizeBytes → content → truncated）+ toString', () {
      const baseJson = <String, Object?>{
        'taskId': 'c1',
        'exists': true,
        'size_bytes': 10,
        'content': 'x',
        'truncated': true,
      };
      final base = KanbanWorkerLog.fromJson(baseJson);
      expect(base, equals(KanbanWorkerLog.fromJson(baseJson)));
      expect(base.hashCode, KanbanWorkerLog.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'taskId': 'c2',
        'exists': false,
        'size_bytes': 11,
        'content': 'y',
        'truncated': false,
      };
      for (final entry in replacements.entries) {
        expect(
          base == KanbanWorkerLog.fromJson({...baseJson, entry.key: entry.value}),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      expect(
        KanbanWorkerLog.fromJson(const {'taskId': 'c1'}).toString(),
        'KanbanWorkerLog(cardID: c1)',
      );
      expect(
        const KanbanWorkerLog().toString(),
        'KanbanWorkerLog(cardID: null)',
      );
    });
  });

  group('KanbanAddCommentResponse', () {
    test('fromJson：全键正常（commentId 显式 camel 键）', () {
      final response = KanbanAddCommentResponse.fromJson(const {
        'ok': true,
        'commentId': 'cm1',
        'read_only': false,
      });
      expect(response.ok, true);
      expect(response.commentID, 'cm1');
      expect(response.readOnly, false);
    });

    test('fromJson：缺失 / 显式 null / 错型 / 近似键不识别', () {
      final missing = KanbanAddCommentResponse.fromJson(const {});
      expect(missing.ok, isNull);
      expect(missing.commentID, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanAddCommentResponse.fromJson(const {
        'ok': null,
        'commentId': null,
        'read_only': null,
      });
      expect(nulls.ok, isNull);
      expect(nulls.commentID, isNull);
      expect(nulls.readOnly, isNull);

      final bad = KanbanAddCommentResponse.fromJson(const {
        'ok': 'yes',
        'commentId': 9,
        'read_only': 'no',
      });
      expect(bad.ok, true);
      expect(bad.commentID, '9');
      expect(bad.readOnly, false);

      expect(
        KanbanAddCommentResponse.fromJson(const {
          'comment_id': 'x',
        }).commentID,
        isNull,
      );
      expect(KanbanAddCommentResponse.fromJson(const {'ok': 2}).ok, isNull);
    });

    test('== 阶梯（ok → commentID → readOnly）+ hashCode + toString', () {
      const baseJson = <String, Object?>{
        'ok': true,
        'commentId': 'cm1',
        'read_only': true,
      };
      final base = KanbanAddCommentResponse.fromJson(baseJson);
      expect(base, equals(KanbanAddCommentResponse.fromJson(baseJson)));
      expect(base.hashCode, KanbanAddCommentResponse.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'ok': false,
        'commentId': 'cm2',
        'read_only': false,
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanAddCommentResponse.fromJson({
                ...baseJson,
                entry.key: entry.value,
              }),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      expect(
        KanbanAddCommentResponse.fromJson(const {'ok': true}).toString(),
        'KanbanAddCommentResponse(ok: true)',
      );
      expect(
        const KanbanAddCommentResponse().toString(),
        'KanbanAddCommentResponse(ok: null)',
      );
    });
  });

  group('KanbanLinkCounts', () {
    test('fromJson：全键正常 / 缺失 / null / 错型', () {
      final counts = KanbanLinkCounts.fromJson(const {
        'parents': 2,
        'children': 3,
      });
      expect(counts.parents, 2);
      expect(counts.children, 3);

      final missing = KanbanLinkCounts.fromJson(const {});
      expect(missing.parents, isNull);
      expect(missing.children, isNull);

      final nulls = KanbanLinkCounts.fromJson(const {
        'parents': null,
        'children': null,
      });
      expect(nulls.parents, isNull);
      expect(nulls.children, isNull);

      final bad = KanbanLinkCounts.fromJson(const {
        'parents': 'bad',
        'children': <Object?>[],
      });
      expect(bad.parents, isNull);
      expect(bad.children, isNull);

      expect(KanbanLinkCounts.fromJson(const {'parents': 4.9}).parents, 4);
      expect(KanbanLinkCounts.fromJson(const {'children': '5'}).children, 5);
    });

    test('== 阶梯（parents → children）+ hashCode + toString', () {
      const baseJson = <String, Object?>{'parents': 1, 'children': 2};
      final base = KanbanLinkCounts.fromJson(baseJson);
      expect(base, equals(KanbanLinkCounts.fromJson(baseJson)));
      expect(base.hashCode, KanbanLinkCounts.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      // 第 1 行：仅 parents 不同。
      expect(
        base == KanbanLinkCounts.fromJson(const {'parents': 9, 'children': 2}),
        isFalse,
      );
      // 第 2 行：仅 children 不同（走完整条链）。
      expect(
        base == KanbanLinkCounts.fromJson(const {'parents': 1, 'children': 9}),
        isFalse,
      );
      expect(
        base == KanbanLinkCounts.fromJson(const {'children': 2}),
        isFalse,
      );

      expect(
        KanbanLinkCounts.fromJson(const {
          'parents': 1,
          'children': 2,
        }).toString(),
        'KanbanLinkCounts(parents: 1, children: 2)',
      );
      expect(
        const KanbanLinkCounts().toString(),
        'KanbanLinkCounts(parents: null, children: null)',
      );
    });
  });

  group('KanbanStats', () {
    test('fromJson：全键正常（by_status / by_assignee 走 counts 解析）', () {
      final stats = KanbanStats.fromJson(const {
        'total': 42,
        'by_status': {'todo': 10, 'running': 3},
        'by_assignee': {'alice': 7},
      });
      expect(stats.total, 42);
      expect(stats.byStatus, {'todo': 10, 'running': 3});
      expect(stats.byAssignee, {'alice': 7});
    });

    test('fromJson：缺失 / 显式 null / 空集合 / 错型', () {
      final missing = KanbanStats.fromJson(const {});
      expect(missing.total, isNull);
      expect(missing.byStatus, isNull);
      expect(missing.byAssignee, isNull);

      final nulls = KanbanStats.fromJson(const {
        'total': null,
        'by_status': null,
        'by_assignee': null,
      });
      expect(nulls.total, isNull);
      expect(nulls.byStatus, isNull);
      expect(nulls.byAssignee, isNull);

      final empties = KanbanStats.fromJson(const {
        'by_status': <String, Object?>{},
        'by_assignee': <String, Object?>{},
      });
      expect(empties.byStatus, isEmpty);
      expect(empties.byAssignee, isEmpty);

      // 数字宽容：double 截断；非 int / 非 double → 整 Map null。
      expect(
        KanbanStats.fromJson(const {
          'by_status': {'todo': 2.9},
        }).byStatus,
        {'todo': 2},
      );
      expect(
        KanbanStats.fromJson(const {
          'by_status': {'todo': 1.0e19},
        }).byStatus,
        isNull,
      );
      expect(
        KanbanStats.fromJson(const {
          'by_assignee': {'alice': 'bad'},
        }).byAssignee,
        isNull,
      );
      expect(KanbanStats.fromJson(const {'by_status': 7}).byStatus, isNull);
      expect(KanbanStats.fromJson(const {'total': 'bad'}).total, isNull);
    });

    test('== 阶梯（total → byStatus → byAssignee）+ hashCode + toString', () {
      const baseJson = <String, Object?>{
        'total': 3,
        'by_status': {'todo': 1},
        'by_assignee': {'alice': 2},
      };
      final base = KanbanStats.fromJson(baseJson);
      expect(base, equals(KanbanStats.fromJson(baseJson)));
      expect(base.hashCode, KanbanStats.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'total': 4,
        'by_status': {'todo': 9},
        'by_assignee': {'bob': 2},
      };
      for (final entry in replacements.entries) {
        expect(
          base == KanbanStats.fromJson({...baseJson, entry.key: entry.value}),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      // 一侧 null 分支。
      expect(
        base ==
            KanbanStats.fromJson(const {
              'total': 3,
              'by_status': null,
              'by_assignee': null,
            }),
        isFalse,
      );
      // Map 长度差异分支。
      expect(
        base ==
            KanbanStats.fromJson(const {
              'total': 3,
              'by_status': {'todo': 1, 'done': 1},
              'by_assignee': {'alice': 2},
            }),
        isFalse,
      );

      expect(
        KanbanStats.fromJson(const {'total': 42}).toString(),
        'KanbanStats(total: 42)',
      );
      expect(const KanbanStats().toString(), 'KanbanStats(total: null)');
    });
  });

  group('KanbanAssigneeHistory', () {
    test('fromJson：assignees 多形态（字符串 / {name} 对象 / 混排）', () {
      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': ['alice', 'bob'],
        }).assignees,
        ['alice', 'bob'],
      );
      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': [
            {'name': 'bob'},
          ],
        }).assignees,
        ['bob'],
      );
      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': [
            'alice',
            {'name': 'bob'},
            {'name': 3},
          ],
        }).assignees,
        ['alice', 'bob', '3'],
      );
    });

    test('fromJson：缺失 / null / 空集合 / 非 List / 元素不可解', () {
      final missing = KanbanAssigneeHistory.fromJson(const {});
      expect(missing.assignees, isNull);
      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': null,
        }).assignees,
        isNull,
      );
      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': <Object?>[],
        }).assignees,
        isEmpty,
      );
      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': 'bad',
        }).assignees,
        isNull,
      );
      // 任一元素既非字符串也非 {name} → 整数组 null。
      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': ['alice', 42],
        }).assignees,
        isNull,
      );
      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': ['alice', {'other': 1}],
        }).assignees,
        isNull,
      );
    });

    test('== _listEquals 四条路径 + hashCode + toString', () {
      final assignees = ['alice'];
      // identical 短路。
      expect(
        KanbanAssigneeHistory(assignees: assignees) ==
            KanbanAssigneeHistory(assignees: assignees),
        isTrue,
      );
      // 双侧 null 也走 identical。
      expect(
        const KanbanAssigneeHistory() == const KanbanAssigneeHistory(),
        isTrue,
      );
      // 不同实例同内容 → 逐元素比较后 true。
      expect(
        KanbanAssigneeHistory(assignees: assignees) ==
            const KanbanAssigneeHistory(assignees: ['alice']),
        isTrue,
      );
      expect(
        KanbanAssigneeHistory(assignees: assignees).hashCode,
        const KanbanAssigneeHistory(assignees: ['alice']).hashCode,
      );
      // 一侧 null。
      expect(
        KanbanAssigneeHistory(assignees: assignees) ==
            const KanbanAssigneeHistory(),
        isFalse,
      );
      // 长度不同。
      expect(
        KanbanAssigneeHistory(assignees: assignees) ==
            const KanbanAssigneeHistory(assignees: ['alice', 'bob']),
        isFalse,
      );
      // 元素不同。
      expect(
        KanbanAssigneeHistory(assignees: assignees) ==
            const KanbanAssigneeHistory(assignees: ['bob']),
        isFalse,
      );
      expect(
        KanbanAssigneeHistory(assignees: assignees) == Object(),
        isFalse,
      );

      expect(
        KanbanAssigneeHistory.fromJson(const {
          'assignees': ['alice'],
        }).toString(),
        'KanbanAssigneeHistory(assignees: [alice])',
      );
      expect(
        const KanbanAssigneeHistory().toString(),
        'KanbanAssigneeHistory(assignees: null)',
      );
    });
  });

  // ==========================================================================
  // 14.5 事件流 / 批量操作 / dispatch
  // ==========================================================================

  group('KanbanEventsEnvelope', () {
    test('fromJson：全键正常（latestEventId 显式 camel 键）', () {
      final envelope = KanbanEventsEnvelope.fromJson(const {
        'events': [
          {'id': 1, 'kind': 'created'},
          {'id': 2, 'kind': 'moved'},
        ],
        'cursor': 5,
        'latestEventId': 6,
        'read_only': true,
      });
      expect(envelope.events, hasLength(2));
      expect(envelope.events![0].eventID, 1);
      expect(envelope.events![1].kind, 'moved');
      expect(envelope.cursor, 5);
      expect(envelope.latestEventID, 6);
      expect(envelope.readOnly, true);
    });

    test('fromJson：缺失 / 显式 null / 空集合 / 错型', () {
      final missing = KanbanEventsEnvelope.fromJson(const {});
      expect(missing.events, isNull);
      expect(missing.cursor, isNull);
      expect(missing.latestEventID, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanEventsEnvelope.fromJson(const {
        'events': null,
        'cursor': null,
        'latestEventId': null,
        'read_only': null,
      });
      expect(nulls.events, isNull);
      expect(nulls.cursor, isNull);
      expect(nulls.latestEventID, isNull);
      expect(nulls.readOnly, isNull);

      expect(
        KanbanEventsEnvelope.fromJson(const {
          'events': <Object?>[],
        }).events,
        isEmpty,
      );
      expect(
        KanbanEventsEnvelope.fromJson(const {
          'events': 'bad',
        }).events,
        isNull,
      );
      expect(
        KanbanEventsEnvelope.fromJson(const {
          'events': [1],
        }).events,
        isNull,
      );
      expect(
        KanbanEventsEnvelope.fromJson(const {
          'cursor': '12',
        }).cursor,
        12,
      );
      expect(
        KanbanEventsEnvelope.fromJson(const {
          'cursor': 'bad',
        }).cursor,
        isNull,
      );
      expect(
        KanbanEventsEnvelope.fromJson(const {
          'latestEventId': 12.9,
        }).latestEventID,
        12,
      );
      expect(
        KanbanEventsEnvelope.fromJson(const {
          'read_only': 'yes',
        }).readOnly,
        true,
      );
      // 近似键名不识别。
      expect(
        KanbanEventsEnvelope.fromJson(const {
          'latest_event_id': 9,
        }).latestEventID,
        isNull,
      );
    });

    test('== 阶梯（events → cursor → latestEventID → readOnly）+ hashCode + toString', () {
      const baseJson = <String, Object?>{
        'events': [
          {'id': 1, 'kind': 'k'},
        ],
        'cursor': 5,
        'latestEventId': 6,
        'read_only': true,
      };
      final base = KanbanEventsEnvelope.fromJson(baseJson);
      expect(base, equals(KanbanEventsEnvelope.fromJson(baseJson)));
      expect(base.hashCode, KanbanEventsEnvelope.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'events': [
          {'id': 2, 'kind': 'k2'},
        ],
        'cursor': 7,
        'latestEventId': 8,
        'read_only': false,
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanEventsEnvelope.fromJson({
                ...baseJson,
                entry.key: entry.value,
              }),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      // events 一侧 null / 长度差异。
      expect(
        base == KanbanEventsEnvelope.fromJson({...baseJson, 'events': null}),
        isFalse,
      );
      expect(
        base ==
            KanbanEventsEnvelope.fromJson({
              ...baseJson,
              'events': <Object?>[],
            }),
        isFalse,
      );

      expect(
        KanbanEventsEnvelope.fromJson(const {'cursor': 5}).toString(),
        'KanbanEventsEnvelope(cursor: 5)',
      );
      expect(
        const KanbanEventsEnvelope().toString(),
        'KanbanEventsEnvelope(cursor: null)',
      );
    });
  });

  group('KanbanEvent', () {
    test('eventID 回退链：id → eventId → event_id（逐键位）', () {
      expect(KanbanEvent.fromJson(const {'id': 1}).eventID, 1);
      expect(KanbanEvent.fromJson(const {'eventId': 2}).eventID, 2);
      expect(KanbanEvent.fromJson(const {'event_id': 3}).eventID, 3);
      // lossyInt 宽容：字符串 / double。
      expect(KanbanEvent.fromJson(const {'id': '4'}).eventID, 4);
      expect(KanbanEvent.fromJson(const {'id': ' 5 '}).eventID, 5);
      expect(KanbanEvent.fromJson(const {'id': 6.9}).eventID, 6);
      expect(KanbanEvent.fromJson(const {'event_id': '7'}).eventID, 7);
      // 优先级：id > eventId > event_id。
      expect(
        KanbanEvent.fromJson(const {
          'id': 1,
          'eventId': 2,
          'event_id': 3,
        }).eventID,
        1,
      );
      expect(
        KanbanEvent.fromJson(const {
          'eventId': 2,
          'event_id': 3,
        }).eventID,
        2,
      );
      // 前键解不出 → 继续尝试后键。
      expect(
        KanbanEvent.fromJson(const {
          'id': 'bad',
          'eventId': 2,
        }).eventID,
        2,
      );
      expect(
        KanbanEvent.fromJson(const {
          'id': null,
          'event_id': 3,
        }).eventID,
        3,
      );
      expect(KanbanEvent.fromJson(const {}).eventID, isNull);
      // 近似键名不识别。
      expect(KanbanEvent.fromJson(const {'eventID': 9}).eventID, isNull);
      expect(KanbanEvent.fromJson(const {'eventID2': 9}).eventID, isNull);
    });

    test('cardID 回退链：taskId → task_id → cardId → card_id（逐键位）', () {
      expect(KanbanEvent.fromJson(const {'taskId': 'a'}).cardID, 'a');
      expect(KanbanEvent.fromJson(const {'task_id': 'b'}).cardID, 'b');
      expect(KanbanEvent.fromJson(const {'cardId': 'c'}).cardID, 'c');
      expect(KanbanEvent.fromJson(const {'card_id': 'd'}).cardID, 'd');
      // 优先级顺序。
      expect(
        KanbanEvent.fromJson(const {
          'taskId': 'a',
          'task_id': 'b',
          'cardId': 'c',
          'card_id': 'd',
        }).cardID,
        'a',
      );
      expect(
        KanbanEvent.fromJson(const {
          'task_id': 'b',
          'cardId': 'c',
          'card_id': 'd',
        }).cardID,
        'b',
      );
      expect(
        KanbanEvent.fromJson(const {
          'cardId': 'c',
          'card_id': 'd',
        }).cardID,
        'c',
      );
      // 前键为 null → 继续。
      expect(
        KanbanEvent.fromJson(const {
          'taskId': null,
          'card_id': 'd',
        }).cardID,
        'd',
      );
      expect(KanbanEvent.fromJson(const {}).cardID, isNull);
      // 近似键名不识别。
      expect(KanbanEvent.fromJson(const {'cardID': 'x'}).cardID, isNull);
      expect(KanbanEvent.fromJson(const {'cardID_': 'x'}).cardID, isNull);
      // 非字符串（数组 / 对象）→ null 并继续尝试。
      expect(
        KanbanEvent.fromJson(const {
          'taskId': <Object?>[1],
          'card_id': 'd',
        }).cardID,
        'd',
      );
    });

    test('runID 回退链：runId → run_id（逐键位）+ 近似键不识别', () {
      expect(KanbanEvent.fromJson(const {'runId': 'a'}).runID, 'a');
      expect(KanbanEvent.fromJson(const {'run_id': 'b'}).runID, 'b');
      expect(
        KanbanEvent.fromJson(const {
          'runId': 'a',
          'run_id': 'b',
        }).runID,
        'a',
      );
      expect(
        KanbanEvent.fromJson(const {
          'runId': null,
          'run_id': 'b',
        }).runID,
        'b',
      );
      expect(KanbanEvent.fromJson(const {}).runID, isNull);
      expect(KanbanEvent.fromJson(const {'runID': 'x'}).runID, isNull);
      expect(KanbanEvent.fromJson(const {'run': 'x'}).runID, isNull);
    });

    test('createdAt 回退链：created_at → createdAt → timestamp（逐键位）', () {
      expect(KanbanEvent.fromJson(const {'created_at': 1}).createdAt, 1);
      expect(KanbanEvent.fromJson(const {'createdAt': 2}).createdAt, 2);
      expect(KanbanEvent.fromJson(const {'timestamp': 3}).createdAt, 3);
      // 字符串 / double 宽容。
      expect(KanbanEvent.fromJson(const {'created_at': '4'}).createdAt, 4);
      expect(KanbanEvent.fromJson(const {'timestamp': 5.9}).createdAt, 5);
      // 优先级。
      expect(
        KanbanEvent.fromJson(const {
          'created_at': 1,
          'createdAt': 2,
          'timestamp': 3,
        }).createdAt,
        1,
      );
      expect(
        KanbanEvent.fromJson(const {
          'createdAt': 2,
          'timestamp': 3,
        }).createdAt,
        2,
      );
      // 前键解不出 → 继续。
      expect(
        KanbanEvent.fromJson(const {
          'created_at': 'bad',
          'timestamp': 3,
        }).createdAt,
        3,
      );
      expect(KanbanEvent.fromJson(const {}).createdAt, isNull);
      // 近似键名不识别。
      expect(KanbanEvent.fromJson(const {'created': 9}).createdAt, isNull);
      expect(KanbanEvent.fromJson(const {'createdAtMs': 9}).createdAt, isNull);
    });

    test('fromJson：kind / 缺失 / 显式 null / 错型', () {
      expect(KanbanEvent.fromJson(const {'kind': 'created'}).kind, 'created');
      expect(KanbanEvent.fromJson(const {'kind': 1}).kind, '1');
      expect(KanbanEvent.fromJson(const {'kind': <Object?>[]}).kind, isNull);
      expect(KanbanEvent.fromJson(const {'kind': null}).kind, isNull);

      final missing = KanbanEvent.fromJson(const {});
      expect(missing.eventID, isNull);
      expect(missing.cardID, isNull);
      expect(missing.runID, isNull);
      expect(missing.kind, isNull);
      expect(missing.createdAt, isNull);
    });

    test('toJson：条件字段「有值出现 / 为 null 整键缺席」+ 往返', () {
      final full = KanbanEvent.fromJson(const {
        'id': 1,
        'taskId': 'c1',
        'runId': 'r1',
        'kind': 'created',
        'created_at': 1723700000,
      });
      expect(full.toJson(), const {
        'id': 1,
        'taskId': 'c1',
        'runId': 'r1',
        'kind': 'created',
        'created_at': 1723700000,
      });
      expect(KanbanEvent.fromJson(full.toJson()), equals(full));

      expect(const KanbanEvent().toJson(), isEmpty);
      expect(KanbanEvent.fromJson(const {'id': 1}).toJson(), const {'id': 1});
      expect(
        KanbanEvent.fromJson(const {'task_id': 'c1'}).toJson(),
        const {'taskId': 'c1'},
      );
      expect(
        KanbanEvent.fromJson(const {'event_id': 3}).toJson(),
        const {'id': 3},
      );
      expect(
        KanbanEvent.fromJson(const {'timestamp': 9}).toJson(),
        const {'created_at': 9},
      );
      // 缺 cardID 时整键缺席（不是 'taskId': null）。
      final partial = KanbanEvent.fromJson(const {'id': 2, 'kind': 'k'}).toJson();
      expect(partial.containsKey('taskId'), isFalse);
      expect(partial.containsKey('runId'), isFalse);
      expect(partial.containsKey('created_at'), isFalse);
    });

    test('== 阶梯（eventID → cardID → runID → kind → createdAt）+ hashCode + toString', () {
      const baseJson = <String, Object?>{
        'id': 1,
        'taskId': 'c1',
        'runId': 'r1',
        'kind': 'k',
        'created_at': 10,
      };
      final base = KanbanEvent.fromJson(baseJson);
      expect(base, equals(KanbanEvent.fromJson(baseJson)));
      expect(base.hashCode, KanbanEvent.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'id': 2,
        'taskId': 'c2',
        'runId': 'r2',
        'kind': 'k2',
        'created_at': 20,
      };
      for (final entry in replacements.entries) {
        expect(
          base == KanbanEvent.fromJson({...baseJson, entry.key: entry.value}),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      expect(
        KanbanEvent.fromJson(const {
          'id': 1,
          'kind': 'k',
        }).toString(),
        'KanbanEvent(eventID: 1, kind: k)',
      );
      expect(
        const KanbanEvent().toString(),
        'KanbanEvent(eventID: null, kind: null)',
      );
    });
  });

  group('KanbanBulkActionEnvelope', () {
    test('fromJson：results / read_only 正常', () {
      final envelope = KanbanBulkActionEnvelope.fromJson(const {
        'results': [
          {'id': 'c1', 'ok': true},
          {'id': 'c2', 'ok': false, 'error': 'boom'},
        ],
        'read_only': false,
      });
      expect(envelope.results, hasLength(2));
      expect(envelope.results![0].cardID, 'c1');
      expect(envelope.results![0].ok, true);
      expect(envelope.results![1].error, 'boom');
      expect(envelope.readOnly, false);
    });

    test('fromJson：缺失 / 显式 null / 空集合 / 元素非对象', () {
      final missing = KanbanBulkActionEnvelope.fromJson(const {});
      expect(missing.results, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanBulkActionEnvelope.fromJson(const {
        'results': null,
        'read_only': null,
      });
      expect(nulls.results, isNull);
      expect(nulls.readOnly, isNull);

      expect(
        KanbanBulkActionEnvelope.fromJson(const {
          'results': <Object?>[],
        }).results,
        isEmpty,
      );
      expect(
        KanbanBulkActionEnvelope.fromJson(const {
          'results': 'bad',
        }).results,
        isNull,
      );
      // 整元素非对象 → 整数组 null（optModelList 语义，不是逐项兜底）。
      expect(
        KanbanBulkActionEnvelope.fromJson(const {
          'results': [
            {'id': 'c1'},
            42,
          ],
        }).results,
        isNull,
      );
      expect(
        KanbanBulkActionEnvelope.fromJson(const {
          'read_only': 'yes',
        }).readOnly,
        true,
      );
    });

    test('== 阶梯（results → readOnly）+ hashCode + toString', () {
      const baseJson = <String, Object?>{
        'results': [
          {'id': 'c1', 'ok': true},
        ],
        'read_only': true,
      };
      final base = KanbanBulkActionEnvelope.fromJson(baseJson);
      expect(base, equals(KanbanBulkActionEnvelope.fromJson(baseJson)));
      expect(base.hashCode, KanbanBulkActionEnvelope.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      // 第 1 行：仅 results 内容不同。
      expect(
        base ==
            KanbanBulkActionEnvelope.fromJson(const {
              'results': [
                {'id': 'c2', 'ok': true},
              ],
              'read_only': true,
            }),
        isFalse,
      );
      // 第 1 行：一侧 results 为 null。
      expect(
        base ==
            KanbanBulkActionEnvelope.fromJson(const {'read_only': true}),
        isFalse,
      );
      // 第 2 行：仅 readOnly 不同。
      expect(
        base ==
            KanbanBulkActionEnvelope.fromJson(const {
              'results': [
                {'id': 'c1', 'ok': true},
              ],
              'read_only': false,
            }),
        isFalse,
      );

      expect(
        KanbanBulkActionEnvelope.fromJson(const {
          'results': [
            {'id': 'c1'},
            {'id': 'c2'},
          ],
        }).toString(),
        'KanbanBulkActionEnvelope(results: 2)',
      );
      expect(
        const KanbanBulkActionEnvelope().toString(),
        'KanbanBulkActionEnvelope(results: null)',
      );
    });
  });

  group('KanbanBulkActionResult', () {
    test('fromJson：Map 正常解析 + 字段缺失 / null / 错型', () {
      final result = KanbanBulkActionResult.fromJson(const {
        'id': 'c1',
        'ok': true,
        'error': 'boom',
      });
      expect(result.cardID, 'c1');
      expect(result.ok, true);
      expect(result.error, 'boom');

      final missing = KanbanBulkActionResult.fromJson(const <String, Object?>{});
      expect(missing.cardID, isNull);
      expect(missing.ok, isNull);
      expect(missing.error, isNull);

      final nulls = KanbanBulkActionResult.fromJson(const {
        'id': null,
        'ok': null,
        'error': null,
      });
      expect(nulls.cardID, isNull);
      expect(nulls.ok, isNull);
      expect(nulls.error, isNull);

      final bad = KanbanBulkActionResult.fromJson(const {
        'id': 1,
        'ok': 'yes',
        'error': 2.5,
      });
      expect(bad.cardID, '1');
      expect(bad.ok, true);
      expect(bad.error, '2.5');

      // 近似键名不识别。
      expect(
        KanbanBulkActionResult.fromJson(const {
          'cardID': 'x',
        }).cardID,
        isNull,
      );
    });

    test('fromJson：整元素非对象 → 三字段全 null（常量实例）', () {
      expect(
        KanbanBulkActionResult.fromJson(null),
        equals(const KanbanBulkActionResult()),
      );
      expect(
        KanbanBulkActionResult.fromJson('bare'),
        equals(const KanbanBulkActionResult()),
      );
      expect(
        KanbanBulkActionResult.fromJson(42),
        equals(const KanbanBulkActionResult()),
      );
      expect(
        KanbanBulkActionResult.fromJson(1.5),
        equals(const KanbanBulkActionResult()),
      );
      expect(
        KanbanBulkActionResult.fromJson(<Object?>[]),
        equals(const KanbanBulkActionResult()),
      );
      expect(
        KanbanBulkActionResult.fromJson(true),
        equals(const KanbanBulkActionResult()),
      );
      final bare = KanbanBulkActionResult.fromJson('bare');
      expect(bare.cardID, isNull);
      expect(bare.ok, isNull);
      expect(bare.error, isNull);
    });

    test('== 阶梯（cardID → ok → error）+ hashCode + toString', () {
      const baseJson = <String, Object?>{
        'id': 'c1',
        'ok': true,
        'error': 'e',
      };
      final base = KanbanBulkActionResult.fromJson(baseJson);
      expect(base, equals(KanbanBulkActionResult.fromJson(baseJson)));
      expect(base.hashCode, KanbanBulkActionResult.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'id': 'c2',
        'ok': false,
        'error': 'e2',
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanBulkActionResult.fromJson({
                ...baseJson,
                entry.key: entry.value,
              }),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      expect(
        KanbanBulkActionResult.fromJson(const {
          'id': 'c1',
          'ok': true,
        }).toString(),
        'KanbanBulkActionResult(cardID: c1, ok: true)',
      );
      expect(
        const KanbanBulkActionResult().toString(),
        'KanbanBulkActionResult(cardID: null, ok: null)',
      );
    });
  });

  group('KanbanDependencyMutationEnvelope', () {
    test('fromJson：全键正常（parentId / childId 显式 camel 键）', () {
      final envelope = KanbanDependencyMutationEnvelope.fromJson(const {
        'ok': true,
        'changed': true,
        'parentId': 'p',
        'childId': 'c',
        'read_only': false,
      });
      expect(envelope.ok, true);
      expect(envelope.changed, true);
      expect(envelope.prerequisiteID, 'p');
      expect(envelope.dependentID, 'c');
      expect(envelope.readOnly, false);
    });

    test('fromJson：缺失 / 显式 null / 错型 / 近似键不识别', () {
      final missing = KanbanDependencyMutationEnvelope.fromJson(const {});
      expect(missing.ok, isNull);
      expect(missing.changed, isNull);
      expect(missing.prerequisiteID, isNull);
      expect(missing.dependentID, isNull);
      expect(missing.readOnly, isNull);

      final nulls = KanbanDependencyMutationEnvelope.fromJson(const {
        'ok': null,
        'changed': null,
        'parentId': null,
        'childId': null,
        'read_only': null,
      });
      expect(nulls.ok, isNull);
      expect(nulls.changed, isNull);
      expect(nulls.prerequisiteID, isNull);
      expect(nulls.dependentID, isNull);
      expect(nulls.readOnly, isNull);

      final bad = KanbanDependencyMutationEnvelope.fromJson(const {
        'ok': 'yes',
        'changed': 0,
        'parentId': 1,
        'childId': <Object?>[],
        'read_only': 'no',
      });
      expect(bad.ok, true);
      expect(bad.changed, false);
      expect(bad.prerequisiteID, '1');
      expect(bad.dependentID, isNull);
      expect(bad.readOnly, false);

      expect(
        KanbanDependencyMutationEnvelope.fromJson(const {
          'parent_id': 'p',
        }).prerequisiteID,
        isNull,
      );
      expect(
        KanbanDependencyMutationEnvelope.fromJson(const {
          'child_id': 'c',
        }).dependentID,
        isNull,
      );
    });

    test('== 阶梯（ok → changed → prerequisiteID → dependentID → readOnly）', () {
      const baseJson = <String, Object?>{
        'ok': true,
        'changed': true,
        'parentId': 'p',
        'childId': 'c',
        'read_only': true,
      };
      final base = KanbanDependencyMutationEnvelope.fromJson(baseJson);
      expect(base, equals(KanbanDependencyMutationEnvelope.fromJson(baseJson)));
      expect(
        base.hashCode,
        KanbanDependencyMutationEnvelope.fromJson(baseJson).hashCode,
      );
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'ok': false,
        'changed': false,
        'parentId': 'p2',
        'childId': 'c2',
        'read_only': false,
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanDependencyMutationEnvelope.fromJson({
                ...baseJson,
                entry.key: entry.value,
              }),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      expect(
        KanbanDependencyMutationEnvelope.fromJson(const {
          'ok': true,
        }).toString(),
        'KanbanDependencyMutationEnvelope(ok: true)',
      );
      expect(
        const KanbanDependencyMutationEnvelope().toString(),
        'KanbanDependencyMutationEnvelope(ok: null)',
      );
    });
  });

  group('KanbanDispatchResult', () {
    test('_count：List → 长度（含空数组）', () {
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': ['a', 'b', 'c'],
        }).spawned,
        3,
      );
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': <Object?>[],
        }).spawned,
        0,
      );
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': <String>['x'],
        }).spawned,
        1,
      );
    });

    test('_count：int / double（截断 / 非有限 / 越 int64）', () {
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': 5}).spawned,
        5,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': -5}).spawned,
        -5,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': 5.9}).spawned,
        5,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': -5.9}).spawned,
        -5,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': 9.0e18}).spawned,
        9000000000000000000,
      );
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': double.infinity,
        }).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': double.negativeInfinity,
        }).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': double.nan}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': 1.0e19}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': -1.0e19}).spawned,
        isNull,
      );
    });

    test('_count：String（int.tryParse(trim)，无 double 兜底 → 否则 null）', () {
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '7'}).spawned,
        7,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': ' 7 '}).spawned,
        7,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '-7'}).spawned,
        -7,
      );
      // 注意：与 lossyInt 不同，_count 的字符串分支只走 int.tryParse，
      // **没有** double 兜底（类头注释即「字符串 → int.parse(trim)」）。
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '3.9'}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': ' 3.9 '}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '1e3'}).spawned,
        isNull,
      );
      // Dart 的 int.tryParse 接受 0x 十六进制字面量（trim 后即可）。
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '0x10'}).spawned,
        16,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': ' 0x10 '}).spawned,
        16,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '+5'}).spawned,
        5,
      );
      // '5.0' 不是合法整数（无 double 兜底）→ null。
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '5.0'}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': ''}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': 'x'}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '  '}).spawned,
        isNull,
      );
      // 越 int64 的整数字符串 → int.tryParse 溢出 → null。
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': '1e400'}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': '99999999999999999999',
        }).spawned,
        isNull,
      );
    });

    test('_count：bool / Map / null / 键缺失 → null', () {
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': true}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': false}).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': {'a': 1},
        }).spawned,
        isNull,
      );
      expect(
        KanbanDispatchResult.fromJson(const {'spawned': null}).spawned,
        isNull,
      );
      expect(KanbanDispatchResult.fromJson(const {}).spawned, isNull);
    });

    test('8 个字段名各自落键（skipped_unassigned 等下划线键）', () {
      final result = KanbanDispatchResult.fromJson(const {
        'spawned': 1,
        'promoted': 2,
        'reclaimed': 3,
        'skipped_unassigned': 4,
        'skipped_nonspawnable': 5,
        'auto_blocked': 6,
        'timed_out': 7,
        'crashed': 8,
      });
      expect(result.spawned, 1);
      expect(result.promoted, 2);
      expect(result.reclaimed, 3);
      expect(result.skippedUnassigned, 4);
      expect(result.skippedNonspawnable, 5);
      expect(result.autoBlocked, 6);
      expect(result.timedOut, 7);
      expect(result.crashed, 8);
    });

    test('hasKnownCategory：任一字段有值即 true', () {
      const keys = [
        'spawned',
        'promoted',
        'reclaimed',
        'skipped_unassigned',
        'skipped_nonspawnable',
        'auto_blocked',
        'timed_out',
        'crashed',
      ];
      for (final key in keys) {
        expect(
          KanbanDispatchResult.fromJson({key: 1}).hasKnownCategory,
          isTrue,
          reason: key,
        );
      }
      // List 输入恒得到长度（哪怕是 0）→ 也判为已知。
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': <Object?>[],
        }).hasKnownCategory,
        isTrue,
      );
      expect(KanbanDispatchResult.fromJson(const {}).hasKnownCategory, isFalse);

      // 全部字段都给「不可识别值」→ 全 null → false。
      final allUnknown = <String, Object?>{};
      for (final key in keys) {
        allUnknown[key] = true;
      }
      expect(
        KanbanDispatchResult.fromJson(allUnknown).hasKnownCategory,
        isFalse,
      );
    });

    test('== 阶梯：8 字段逐字段差异 + hashCode', () {
      const baseJson = <String, Object?>{
        'spawned': 1,
        'promoted': 2,
        'reclaimed': 3,
        'skipped_unassigned': 4,
        'skipped_nonspawnable': 5,
        'auto_blocked': 6,
        'timed_out': 7,
        'crashed': 8,
      };
      final base = KanbanDispatchResult.fromJson(baseJson);
      expect(base, equals(KanbanDispatchResult.fromJson(baseJson)));
      expect(base.hashCode, KanbanDispatchResult.fromJson(baseJson).hashCode);
      expect(base == Object(), isFalse);

      const replacements = <String, Object?>{
        'spawned': 9,
        'promoted': 9,
        'reclaimed': 9,
        'skipped_unassigned': 9,
        'skipped_nonspawnable': 9,
        'auto_blocked': 9,
        'timed_out': 9,
        'crashed': 9,
      };
      for (final entry in replacements.entries) {
        expect(
          base ==
              KanbanDispatchResult.fromJson({
                ...baseJson,
                entry.key: entry.value,
              }),
          isFalse,
          reason: '字段 ${entry.key} 的差异未被 == 捕获',
        );
      }

      // 一侧字段为 null（键缺失）也要判不等。
      expect(
        base ==
            KanbanDispatchResult.fromJson({
              ...baseJson,
              'crashed': null,
            }),
        isFalse,
      );
    });

    test('toString', () {
      expect(
        KanbanDispatchResult.fromJson(const {
          'spawned': 1,
          'promoted': 2,
        }).toString(),
        'KanbanDispatchResult(spawned: 1, promoted: 2, reclaimed: null)',
      );
      expect(
        const KanbanDispatchResult().toString(),
        'KanbanDispatchResult(spawned: null, promoted: null, reclaimed: null)',
      );
    });
  });

  // ==========================================================================
  // 近似键名不被识别（反向例，集中一轮）
  // ==========================================================================

  group('近似键名不被识别（反向例）', () {
    test('snake / camel 错位一律不落键', () {
      expect(
        KanbanConfiguration.fromJson(const {
          'defaultTenant': 't',
        }).defaultTenant,
        isNull,
      );
      expect(
        KanbanConfiguration.fromJson(const {
          'laneByProfile': true,
        }).laneByProfile,
        isNull,
      );
      expect(
        KanbanConfiguration.fromJson(const {
          'renderMarkdown': true,
        }).renderMarkdown,
        isNull,
      );
      expect(
        KanbanBoardSnapshot.fromJson(const {
          'latest_event_id': 5,
        }).latestEventID,
        isNull,
      );
      expect(
        KanbanCard.fromJson(const {
          'current_run_id': 'r',
        }).currentRunID,
        isNull,
      );
      expect(
        KanbanCard.fromJson(const {
          'worker_id': 'w',
        }).workerID,
        isNull,
      );
      expect(
        KanbanCard.fromJson(const {
          'maxRuntimeSeconds': 60,
        }).maxRuntimeSeconds,
        isNull,
      );
      expect(
        KanbanColumn.fromJson(const {
          'cards': [
            {'id': 'c'},
          ],
        }).cards,
        isNull,
      );
      expect(
        KanbanCardDetailEnvelope.fromJson(const {
          'card': {'id': 'c'},
        }).card,
        isNull,
      );
      expect(
        KanbanCardMutationEnvelope.fromJson(const {
          'card': {'id': 'c'},
        }).card,
        isNull,
      );
      expect(
        KanbanComment.fromJson(const {'commentId': 'c'}).commentID,
        isNull,
      );
      expect(
        KanbanAddCommentResponse.fromJson(const {
          'comment_id': 'c',
        }).commentID,
        isNull,
      );
      expect(
        KanbanDependencyLinks.fromJson(const {
          'prerequisite': ['a'],
        }).prerequisites,
        isNull,
      );
      expect(
        KanbanDependencyLinks.fromJson(const {
          'dependent': ['a'],
        }).dependents,
        isNull,
      );
      expect(
        KanbanDependencyMutationEnvelope.fromJson(const {
          'parent_id': 'p',
        }).prerequisiteID,
        isNull,
      );
      expect(KanbanDispatchRun.fromJson(const {'run_id': 'r'}).runID, isNull);
      expect(
        KanbanDispatchRun.fromJson(const {'finishedAt': 'f'}).finishedAt,
        isNull,
      );
      expect(
        KanbanDispatchRun.fromJson(const {'worker_id': 'w'}).workerID,
        isNull,
      );
      expect(
        KanbanWorkerLog.fromJson(const {'path': '/p'}).content,
        isNull,
      );
      expect(KanbanEvent.fromJson(const {'eventID': 1}).eventID, isNull);
      expect(KanbanEvent.fromJson(const {'cardID': 'c'}).cardID, isNull);
      expect(KanbanEvent.fromJson(const {'runID': 'r'}).runID, isNull);
      expect(KanbanEvent.fromJson(const {'created': 1}).createdAt, isNull);
      expect(KanbanEvent.fromJson(const {'kindName': 'k'}).kind, isNull);
      expect(
        KanbanDetailEvent.fromJson(const {'eventId': 'e'}).eventID,
        isNull,
      );
      expect(
        KanbanDetailEvent.fromJson(const {'cardId': 'c'}).cardID,
        isNull,
      );
      expect(
        KanbanDetailEventPayload.fromJson(const {
          'field': ['a'],
        }).fields,
        isNull,
      );
      expect(
        KanbanStats.fromJson(const {
          'byStatus': {'todo': 1},
        }).byStatus,
        isNull,
      );
      expect(
        KanbanBulkActionResult.fromJson(const {'cardID': 'c'}).cardID,
        isNull,
      );
      expect(
        KanbanBulkActionEnvelope.fromJson(const {
          'result': [
            {'id': 'c'},
          ],
        }).results,
        isNull,
      );
      expect(
        KanbanWorkerLog.fromJson(const {'sizeBytes': 1}).sizeBytes,
        isNull,
      );
      expect(
        KanbanBoardsResponse.fromJson(const {
          'board': [
            {'slug': 'a'},
          ],
        }).boards,
        isNull,
      );
    });
  });
}
