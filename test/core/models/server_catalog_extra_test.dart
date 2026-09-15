import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';

/// 探针 Map：任何读取（含 `Map<String, Object?>.from` 内部的遍历/拷贝）
/// 都会抛错，用来命中 `ChatStartResponse.fromJson` 里 `catch (_) {}` 分支。
class _ExplodingMap extends MapBase<String, Object?> {
  @override
  Iterable<String> get keys => throw StateError('explode');

  @override
  Object? operator [](Object? key) => throw StateError('explode');

  @override
  void operator []=(String key, Object? value) => throw StateError('explode');

  @override
  void clear() => throw StateError('explode');

  @override
  Object? remove(Object? key) => throw StateError('explode');
}

void main() {
  // ==========================================================================
  // ChatStartResponse
  // ==========================================================================
  group('ChatStartResponse', () {
    test('fromJson：顶层 snake_case 三键', () {
      final response = ChatStartResponse.fromJson({
        'stream_id': 's_snake',
        'session_id': 'sess_snake',
        'error': 'boom',
      });
      expect(response.streamId, 's_snake');
      expect(response.sessionId, 'sess_snake');
      expect(response.error, 'boom');
    });

    test('fromJson：顶层 camelCase 回退（streamId/sessionId/message）', () {
      final response = ChatStartResponse.fromJson({
        'streamId': 's_camel',
        'sessionId': 'sess_camel',
        'message': 'camel-error',
      });
      expect(response.streamId, 's_camel');
      expect(response.sessionId, 'sess_camel');
      expect(response.error, 'camel-error');
    });

    test('fromJson：data 包裹走 snake_case', () {
      final response = ChatStartResponse.fromJson({
        'data': {
          'stream_id': 'd_snake',
          'session_id': 'd_sess_snake',
          'error': 'd_err_snake',
        },
      });
      expect(response.streamId, 'd_snake');
      expect(response.sessionId, 'd_sess_snake');
      expect(response.error, 'd_err_snake');
    });

    test('fromJson：data 包裹走 camelCase', () {
      final response = ChatStartResponse.fromJson({
        'data': {
          'streamId': 'd_camel',
          'sessionId': 'd_sess_camel',
          'message': 'd_msg_camel',
        },
      });
      expect(response.streamId, 'd_camel');
      expect(response.sessionId, 'd_sess_camel');
      expect(response.error, 'd_msg_camel');
    });

    test('fromJson：streamId 兜底链 id（顶层优先于 data）', () {
      expect(ChatStartResponse.fromJson({'id': 'top_id'}).streamId, 'top_id');
      expect(
        ChatStartResponse.fromJson({'data': {'id': 'data_id'}}).streamId,
        'data_id',
      );
      expect(
        ChatStartResponse.fromJson({
          'id': 'top_id',
          'data': {'id': 'data_id'},
        }).streamId,
        'top_id',
      );
    });

    test('fromJson：顶层优先于 data（同键同名）', () {
      final response = ChatStartResponse.fromJson({
        'stream_id': 'top',
        'session_id': 'top_sess',
        'error': 'top_err',
        'data': {
          'stream_id': 'nested',
          'session_id': 'nested_sess',
          'error': 'nested_err',
        },
      });
      expect(response.streamId, 'top');
      expect(response.sessionId, 'top_sess');
      expect(response.error, 'top_err');
    });

    test('fromJson：lossy 宽容转换（int / bool / double）', () {
      final response = ChatStartResponse.fromJson({
        'stream_id': 42,
        'session_id': true,
        'error': 1.5,
      });
      expect(response.streamId, '42');
      expect(response.sessionId, 'true');
      expect(response.error, '1.5');
    });

    test('fromJson：全缺失 / null / 不可转换类型一律 null', () {
      final empty = ChatStartResponse.fromJson(const {});
      expect(empty.streamId, isNull);
      expect(empty.sessionId, isNull);
      expect(empty.error, isNull);

      final nulls = ChatStartResponse.fromJson({
        'stream_id': null,
        'session_id': null,
        'error': null,
        'id': null,
      });
      expect(nulls.streamId, isNull);
      expect(nulls.sessionId, isNull);
      expect(nulls.error, isNull);

      final wrongTypes = ChatStartResponse.fromJson({
        'stream_id': [1],
        'session_id': {'a': 1},
        'error': [1],
      });
      expect(wrongTypes.streamId, isNull);
      expect(wrongTypes.sessionId, isNull);
      expect(wrongTypes.error, isNull);
    });

    test('fromJson：data 非 Map 时整块忽略', () {
      expect(ChatStartResponse.fromJson({'data': 'nope'}).streamId, isNull);
      expect(ChatStartResponse.fromJson({'data': 7}).streamId, isNull);
      expect(ChatStartResponse.fromJson({'data': [1, 2]}).streamId, isNull);
    });

    test('fromJson：data 键类型不符 → Map.from 抛错被吞（dataMap 保持 null）', () {
      // `Map<String, Object?>.from({1: 'x'})` 拷贝时键类型检查失败。
      final mismatchedKeys = ChatStartResponse.fromJson({
        'data': {1: 'x'},
      });
      expect(mismatchedKeys.streamId, isNull);

      // 探针 Map：遍历即抛错，必定命中 `catch (_) {}`。
      final exploding = ChatStartResponse.fromJson({
        'data': _ExplodingMap(),
        'id': 'fallback_from_top',
      });
      expect(exploding.streamId, 'fallback_from_top');
    });

    test('== / hashCode / toString（阶梯式）', () {
      ChatStartResponse build({
        String? streamId,
        String? sessionId,
        String? error,
      }) =>
          ChatStartResponse.fromJson({
            'stream_id': streamId,
            'session_id': sessionId,
            'error': error,
          });

      final base = build(streamId: 's1', sessionId: 'sess1', error: 'e1');
      expect(base, build(streamId: 's1', sessionId: 'sess1', error: 'e1'));
      expect(
        base.hashCode,
        build(streamId: 's1', sessionId: 'sess1', error: 'e1').hashCode,
      );
      expect(base.toString(), 'ChatStartResponse(streamId: s1)');
      expect(
        const ChatStartResponse().toString(),
        'ChatStartResponse(streamId: null)',
      );

      // 阶梯：每行只差一个字段，保证 `&&` 每个比较都被执行。
      expect(base == build(streamId: 's2', sessionId: 'sess1', error: 'e1'),
          isFalse);
      expect(base == build(streamId: 's1', sessionId: 'sess2', error: 'e1'),
          isFalse);
      expect(base == build(streamId: 's1', sessionId: 'sess1', error: 'e2'),
          isFalse);
      expect(base == const ChatStartResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // ChatCancelResponse
  // ==========================================================================
  group('ChatCancelResponse', () {
    test('fromJson：snake_case 四键', () {
      final response = ChatCancelResponse.fromJson({
        'ok': true,
        'cancelled': false,
        'stream_id': 's_9',
        'error': 'nope',
      });
      expect(response.ok, true);
      expect(response.cancelled, false);
      expect(response.streamId, 's_9');
      expect(response.error, 'nope');
    });

    test('fromJson：lossyBool 宽容（int / 字符串）', () {
      expect(ChatCancelResponse.fromJson({'ok': 1}).ok, true);
      expect(ChatCancelResponse.fromJson({'ok': 0}).ok, false);
      expect(ChatCancelResponse.fromJson({'ok': 'yes'}).ok, true);
      expect(ChatCancelResponse.fromJson({'ok': ' no '}).ok, false);
      expect(ChatCancelResponse.fromJson({'ok': 'TRUE'}).ok, true);
      expect(ChatCancelResponse.fromJson({'ok': 2}).ok, isNull);
      expect(ChatCancelResponse.fromJson({'ok': 'maybe'}).ok, isNull);
      expect(ChatCancelResponse.fromJson({'ok': [true]}).ok, isNull);
    });

    test('fromJson：全缺失 / null / 非字符串 → null', () {
      final empty = ChatCancelResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.cancelled, isNull);
      expect(empty.streamId, isNull);
      expect(empty.error, isNull);

      final nulls = ChatCancelResponse.fromJson({
        'ok': null,
        'cancelled': null,
        'stream_id': null,
        'error': null,
      });
      expect(nulls.ok, isNull);
      expect(nulls.cancelled, isNull);
      expect(nulls.streamId, isNull);
      expect(nulls.error, isNull);
    });

    test('fromJson：无 camelCase 回退（streamId / message 不认）', () {
      final response = ChatCancelResponse.fromJson({
        'streamId': 's_camel',
        'message': 'm',
      });
      expect(response.streamId, isNull);
      expect(response.error, isNull);
    });

    test('fromJson：lossyString 宽容转换', () {
      final response = ChatCancelResponse.fromJson({
        'stream_id': 42,
        'error': false,
      });
      expect(response.streamId, '42');
      expect(response.error, 'false');
    });

    test('== / hashCode / toString（阶梯式）', () {
      ChatCancelResponse build({
        bool? ok,
        bool? cancelled,
        String? streamId,
        String? error,
      }) =>
          ChatCancelResponse.fromJson({
            'ok': ok,
            'cancelled': cancelled,
            'stream_id': streamId,
            'error': error,
          });

      final base = build(
        ok: true,
        cancelled: false,
        streamId: 's1',
        error: 'e1',
      );
      expect(base, build(ok: true, cancelled: false, streamId: 's1', error: 'e1'));
      expect(
        base.hashCode,
        build(ok: true, cancelled: false, streamId: 's1', error: 'e1')
            .hashCode,
      );
      expect(base.toString(), 'ChatCancelResponse(ok: true)');
      expect(
        const ChatCancelResponse().toString(),
        'ChatCancelResponse(ok: null)',
      );

      expect(base == build(ok: false, cancelled: false, streamId: 's1', error: 'e1'),
          isFalse);
      expect(base == build(ok: true, cancelled: true, streamId: 's1', error: 'e1'),
          isFalse);
      expect(base == build(ok: true, cancelled: false, streamId: 's2', error: 'e1'),
          isFalse);
      expect(base == build(ok: true, cancelled: false, streamId: 's1', error: 'e2'),
          isFalse);
      expect(base == const ChatCancelResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // ChatStreamStatusResponse + RunJournalStatus
  // ==========================================================================
  group('ChatStreamStatusResponse', () {
    test('fromJson：snake_case 三键 + 嵌套 journal', () {
      final response = ChatStreamStatusResponse.fromJson({
        'active': true,
        'stream_id': 's_9',
        'replay_available': false,
        'journal': {'terminal': true, 'terminal_state': 'completed'},
      });
      expect(response.active, true);
      expect(response.streamId, 's_9');
      expect(response.replayAvailable, false);
      expect(response.journal, const RunJournalStatus(
        terminal: true,
        terminalState: 'completed',
      ));
    });

    test('fromJson：journal 非 Map / 缺失 → null', () {
      expect(ChatStreamStatusResponse.fromJson(const {}).journal, isNull);
      expect(
        ChatStreamStatusResponse.fromJson({'journal': null}).journal,
        isNull,
      );
      expect(
        ChatStreamStatusResponse.fromJson({'journal': 'bad'}).journal,
        isNull,
      );
      expect(ChatStreamStatusResponse.fromJson({'journal': 5}).journal, isNull);
      expect(
        ChatStreamStatusResponse.fromJson({
          'journal': [1],
        }).journal,
        isNull,
      );
      // 空 Map 仍是合法对象 → 解出全 null 的 journal。
      final emptyJournal = ChatStreamStatusResponse.fromJson(const {
        'journal': <String, Object?>{},
      }).journal;
      expect(emptyJournal, isNotNull);
      expect(emptyJournal!.terminal, isNull);
      expect(emptyJournal.terminalState, isNull);
    });

    test('fromJson：bool 宽容 + 全缺失', () {
      final coerced = ChatStreamStatusResponse.fromJson({
        'active': 1,
        'replay_available': 'no',
      });
      expect(coerced.active, true);
      expect(coerced.replayAvailable, false);

      final empty = ChatStreamStatusResponse.fromJson(const {});
      expect(empty.active, isNull);
      expect(empty.streamId, isNull);
      expect(empty.replayAvailable, isNull);
    });

    test('fromJson：无 camelCase 回退（streamId / replayAvailable 不认）', () {
      final response = ChatStreamStatusResponse.fromJson({
        'streamId': 's_camel',
        'replayAvailable': true,
      });
      expect(response.streamId, isNull);
      expect(response.replayAvailable, isNull);
    });

    test('fromJson：stream_id 宽容转换 + 不可转换 → null', () {
      expect(ChatStreamStatusResponse.fromJson({'stream_id': 7}).streamId, '7');
      expect(
        ChatStreamStatusResponse.fromJson({'stream_id': [1]}).streamId,
        isNull,
      );
    });

    test('== / hashCode / toString（阶梯式）', () {
      ChatStreamStatusResponse build({
        bool? active,
        String? streamId,
        bool? replayAvailable,
        Map<String, Object?>? journal,
      }) =>
          ChatStreamStatusResponse.fromJson({
            'active': active,
            'stream_id': streamId,
            'replay_available': replayAvailable,
            'journal': journal,
          });

      final journal = {'terminal': true, 'terminal_state': 'done'};
      final base = build(
        active: true,
        streamId: 's1',
        replayAvailable: false,
        journal: journal,
      );
      expect(
        base,
        build(
          active: true,
          streamId: 's1',
          replayAvailable: false,
          journal: {'terminal': true, 'terminal_state': 'done'},
        ),
      );
      expect(
        base.hashCode,
        build(
          active: true,
          streamId: 's1',
          replayAvailable: false,
          journal: {'terminal': true, 'terminal_state': 'done'},
        ).hashCode,
      );
      expect(base.toString(), 'ChatStreamStatusResponse(active: true)');
      expect(
        const ChatStreamStatusResponse().toString(),
        'ChatStreamStatusResponse(active: null)',
      );

      expect(
        base ==
            build(
              active: false,
              streamId: 's1',
              replayAvailable: false,
              journal: journal,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              active: true,
              streamId: 's2',
              replayAvailable: false,
              journal: journal,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              active: true,
              streamId: 's1',
              replayAvailable: true,
              journal: journal,
            ),
        isFalse,
      );
      // journal 只差内层一个字段 → 走 RunJournalStatus ==。
      expect(
        base ==
            build(
              active: true,
              streamId: 's1',
              replayAvailable: false,
              journal: {'terminal': true, 'terminal_state': 'other'},
            ),
        isFalse,
      );
      expect(base == const ChatStreamStatusResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('RunJournalStatus', () {
    test('fromJson：正常 / 宽容 / 缺失', () {
      final response = RunJournalStatus.fromJson({
        'terminal': true,
        'terminal_state': 'completed',
      });
      expect(response.terminal, true);
      expect(response.terminalState, 'completed');

      final coerced = RunJournalStatus.fromJson({
        'terminal': 'yes',
        'terminal_state': 42,
      });
      expect(coerced.terminal, true);
      expect(coerced.terminalState, '42');

      final empty = RunJournalStatus.fromJson(const {});
      expect(empty.terminal, isNull);
      expect(empty.terminalState, isNull);

      final wrong = RunJournalStatus.fromJson({
        'terminal': 2,
        'terminal_state': [1],
      });
      expect(wrong.terminal, isNull);
      expect(wrong.terminalState, isNull);
    });

    test('fromJson：无 camelCase 回退（terminalState 不认）', () {
      final response = RunJournalStatus.fromJson({'terminalState': 'done'});
      expect(response.terminalState, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      RunJournalStatus build({bool? terminal, String? terminalState}) =>
          RunJournalStatus.fromJson({
            'terminal': terminal,
            'terminal_state': terminalState,
          });

      final base = build(terminal: true, terminalState: 'done');
      expect(base, build(terminal: true, terminalState: 'done'));
      expect(
        base.hashCode,
        build(terminal: true, terminalState: 'done').hashCode,
      );
      expect(base.toString(), 'RunJournalStatus(terminal: true)');
      expect(
        const RunJournalStatus().toString(),
        'RunJournalStatus(terminal: null)',
      );

      expect(base == build(terminal: false, terminalState: 'done'), isFalse);
      expect(base == build(terminal: true, terminalState: 'other'), isFalse);
      expect(base == const RunJournalStatus(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // ChatSteerResponse
  // ==========================================================================
  group('ChatSteerResponse', () {
    test('fromJson：snake_case 四键', () {
      final response = ChatSteerResponse.fromJson({
        'accepted': true,
        'fallback': 'queue',
        'stream_id': 's_9',
        'error': 'nope',
      });
      expect(response.accepted, true);
      expect(response.fallback, 'queue');
      expect(response.streamId, 's_9');
      expect(response.error, 'nope');
    });

    test('fromJson：accepted 宽容（int / 字符串）', () {
      expect(ChatSteerResponse.fromJson({'accepted': 1}).accepted, true);
      expect(ChatSteerResponse.fromJson({'accepted': 0}).accepted, false);
      expect(ChatSteerResponse.fromJson({'accepted': 'yes'}).accepted, true);
      expect(ChatSteerResponse.fromJson({'accepted': 'no'}).accepted, false);
      expect(ChatSteerResponse.fromJson({'accepted': 3}).accepted, isNull);
      expect(ChatSteerResponse.fromJson({'accepted': 'x'}).accepted, isNull);
      expect(ChatSteerResponse.fromJson({'accepted': [true]}).accepted, isNull);
    });

    test('fromJson：fallback / stream_id / error 宽容转换', () {
      final coerced = ChatSteerResponse.fromJson({
        'fallback': 5,
        'stream_id': 6,
        'error': false,
      });
      expect(coerced.fallback, '5');
      expect(coerced.streamId, '6');
      expect(coerced.error, 'false');

      final wrong = ChatSteerResponse.fromJson({
        'fallback': {'a': 1},
        'stream_id': [1],
        'error': <String>[],
      });
      expect(wrong.fallback, isNull);
      expect(wrong.streamId, isNull);
      expect(wrong.error, isNull);
    });

    test('fromJson：全缺失 / null → null', () {
      final empty = ChatSteerResponse.fromJson(const {});
      expect(empty.accepted, isNull);
      expect(empty.fallback, isNull);
      expect(empty.streamId, isNull);
      expect(empty.error, isNull);

      final nulls = ChatSteerResponse.fromJson({
        'accepted': null,
        'fallback': null,
        'stream_id': null,
        'error': null,
      });
      expect(nulls.accepted, isNull);
      expect(nulls.fallback, isNull);
      expect(nulls.streamId, isNull);
      expect(nulls.error, isNull);
    });

    test('fromJson：无 camelCase 回退（streamId 不认）', () {
      final response = ChatSteerResponse.fromJson({'streamId': 's_camel'});
      expect(response.streamId, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      ChatSteerResponse build({
        bool? accepted,
        String? fallback,
        String? streamId,
        String? error,
      }) =>
          ChatSteerResponse.fromJson({
            'accepted': accepted,
            'fallback': fallback,
            'stream_id': streamId,
            'error': error,
          });

      final base = build(
        accepted: true,
        fallback: 'queue',
        streamId: 's1',
        error: 'e1',
      );
      expect(
        base,
        build(accepted: true, fallback: 'queue', streamId: 's1', error: 'e1'),
      );
      expect(
        base.hashCode,
        build(accepted: true, fallback: 'queue', streamId: 's1', error: 'e1')
            .hashCode,
      );
      expect(base.toString(), 'ChatSteerResponse(accepted: true)');
      expect(
        const ChatSteerResponse().toString(),
        'ChatSteerResponse(accepted: null)',
      );

      expect(
        base ==
            build(
              accepted: false,
              fallback: 'queue',
              streamId: 's1',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              accepted: true,
              fallback: 'drop',
              streamId: 's1',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              accepted: true,
              fallback: 'queue',
              streamId: 's2',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              accepted: true,
              fallback: 'queue',
              streamId: 's1',
              error: 'e2',
            ),
        isFalse,
      );
      expect(base == const ChatSteerResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // BtwStartResponse
  // ==========================================================================
  group('BtwStartResponse', () {
    test('fromJson：snake_case 四键（含 parent_session_id）', () {
      final response = BtwStartResponse.fromJson({
        'stream_id': 's_10',
        'session_id': 'abc124',
        'parent_session_id': 'abc123',
        'error': 'nope',
      });
      expect(response.streamId, 's_10');
      expect(response.sessionId, 'abc124');
      expect(response.parentSessionId, 'abc123');
      expect(response.error, 'nope');
    });

    test('fromJson：宽容转换 + 不可转换 → null', () {
      final coerced = BtwStartResponse.fromJson({
        'stream_id': 1,
        'session_id': true,
        'parent_session_id': 2.5,
        'error': 0,
      });
      expect(coerced.streamId, '1');
      expect(coerced.sessionId, 'true');
      expect(coerced.parentSessionId, '2.5');
      expect(coerced.error, '0');

      final wrong = BtwStartResponse.fromJson({
        'stream_id': [1],
        'session_id': {'a': 1},
        'parent_session_id': <Object?>[],
        'error': <String>[],
      });
      expect(wrong.streamId, isNull);
      expect(wrong.sessionId, isNull);
      expect(wrong.parentSessionId, isNull);
      expect(wrong.error, isNull);
    });

    test('fromJson：全缺失 / null → null', () {
      final empty = BtwStartResponse.fromJson(const {});
      expect(empty.streamId, isNull);
      expect(empty.sessionId, isNull);
      expect(empty.parentSessionId, isNull);
      expect(empty.error, isNull);

      final nulls = BtwStartResponse.fromJson({
        'stream_id': null,
        'session_id': null,
        'parent_session_id': null,
        'error': null,
      });
      expect(nulls.streamId, isNull);
      expect(nulls.sessionId, isNull);
      expect(nulls.parentSessionId, isNull);
      expect(nulls.error, isNull);
    });

    test('fromJson：无 camelCase 回退（parentSessionId 不认）', () {
      final response = BtwStartResponse.fromJson({
        'streamId': 'a',
        'sessionId': 'b',
        'parentSessionId': 'c',
      });
      expect(response.streamId, isNull);
      expect(response.sessionId, isNull);
      expect(response.parentSessionId, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      BtwStartResponse build({
        String? streamId,
        String? sessionId,
        String? parentSessionId,
        String? error,
      }) =>
          BtwStartResponse.fromJson({
            'stream_id': streamId,
            'session_id': sessionId,
            'parent_session_id': parentSessionId,
            'error': error,
          });

      final base = build(
        streamId: 's1',
        sessionId: 'sess1',
        parentSessionId: 'parent1',
        error: 'e1',
      );
      expect(
        base,
        build(
          streamId: 's1',
          sessionId: 'sess1',
          parentSessionId: 'parent1',
          error: 'e1',
        ),
      );
      expect(
        base.hashCode,
        build(
          streamId: 's1',
          sessionId: 'sess1',
          parentSessionId: 'parent1',
          error: 'e1',
        ).hashCode,
      );
      expect(base.toString(), 'BtwStartResponse(streamId: s1)');
      expect(
        const BtwStartResponse().toString(),
        'BtwStartResponse(streamId: null)',
      );

      expect(
        base ==
            build(
              streamId: 's2',
              sessionId: 'sess1',
              parentSessionId: 'parent1',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              streamId: 's1',
              sessionId: 'sess2',
              parentSessionId: 'parent1',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              streamId: 's1',
              sessionId: 'sess1',
              parentSessionId: 'parent2',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              streamId: 's1',
              sessionId: 'sess1',
              parentSessionId: 'parent1',
              error: 'e2',
            ),
        isFalse,
      );
      expect(base == const BtwStartResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // BackgroundStartResponse
  // ==========================================================================
  group('BackgroundStartResponse', () {
    test('fromJson：snake_case 四键（含 task_id）', () {
      final response = BackgroundStartResponse.fromJson({
        'task_id': 't_1',
        'stream_id': 's_11',
        'session_id': 'abc125',
        'error': 'nope',
      });
      expect(response.taskId, 't_1');
      expect(response.streamId, 's_11');
      expect(response.sessionId, 'abc125');
      expect(response.error, 'nope');
    });

    test('fromJson：宽容转换 + 不可转换 → null', () {
      final coerced = BackgroundStartResponse.fromJson({
        'task_id': 1,
        'stream_id': false,
        'session_id': 'abc',
        'error': 9,
      });
      expect(coerced.taskId, '1');
      expect(coerced.streamId, 'false');
      expect(coerced.sessionId, 'abc');
      expect(coerced.error, '9');

      final wrong = BackgroundStartResponse.fromJson({
        'task_id': [1],
        'stream_id': {'a': 1},
        'session_id': <Object?>[],
        'error': <String>[],
      });
      expect(wrong.taskId, isNull);
      expect(wrong.streamId, isNull);
      expect(wrong.sessionId, isNull);
      expect(wrong.error, isNull);
    });

    test('fromJson：全缺失 / null → null', () {
      final empty = BackgroundStartResponse.fromJson(const {});
      expect(empty.taskId, isNull);
      expect(empty.streamId, isNull);
      expect(empty.sessionId, isNull);
      expect(empty.error, isNull);

      final nulls = BackgroundStartResponse.fromJson({
        'task_id': null,
        'stream_id': null,
        'session_id': null,
        'error': null,
      });
      expect(nulls.taskId, isNull);
      expect(nulls.streamId, isNull);
      expect(nulls.sessionId, isNull);
      expect(nulls.error, isNull);
    });

    test('fromJson：无 camelCase 回退（taskId 不认）', () {
      final response = BackgroundStartResponse.fromJson({
        'taskId': 't_camel',
        'streamId': 's_camel',
        'sessionId': 'sess_camel',
      });
      expect(response.taskId, isNull);
      expect(response.streamId, isNull);
      expect(response.sessionId, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      BackgroundStartResponse build({
        String? taskId,
        String? streamId,
        String? sessionId,
        String? error,
      }) =>
          BackgroundStartResponse.fromJson({
            'task_id': taskId,
            'stream_id': streamId,
            'session_id': sessionId,
            'error': error,
          });

      final base = build(
        taskId: 't1',
        streamId: 's1',
        sessionId: 'sess1',
        error: 'e1',
      );
      expect(
        base,
        build(taskId: 't1', streamId: 's1', sessionId: 'sess1', error: 'e1'),
      );
      expect(
        base.hashCode,
        build(taskId: 't1', streamId: 's1', sessionId: 'sess1', error: 'e1')
            .hashCode,
      );
      expect(base.toString(), 'BackgroundStartResponse(taskId: t1)');
      expect(
        const BackgroundStartResponse().toString(),
        'BackgroundStartResponse(taskId: null)',
      );

      expect(
        base ==
            build(
              taskId: 't2',
              streamId: 's1',
              sessionId: 'sess1',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              taskId: 't1',
              streamId: 's2',
              sessionId: 'sess1',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              taskId: 't1',
              streamId: 's1',
              sessionId: 'sess2',
              error: 'e1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              taskId: 't1',
              streamId: 's1',
              sessionId: 'sess1',
              error: 'e2',
            ),
        isFalse,
      );
      expect(base == const BackgroundStartResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // BackgroundStatusResponse + BackgroundResult
  // ==========================================================================
  group('BackgroundStatusResponse', () {
    test('fromJson：空列表 / 多元素', () {
      final empty = BackgroundStatusResponse.fromJson(const {
        'results': <Object?>[],
      });
      expect(empty.results, isEmpty);

      final multi = BackgroundStatusResponse.fromJson({
        'results': [
          {'task_id': 't_1', 'prompt': 'p1', 'answer': 'a1', 'completed_at': 1},
          {
            'task_id': 't_2',
            'prompt': 'p2',
            'answer': 'a2',
            'completed_at': 2.5,
          },
        ],
      });
      expect(multi.results, hasLength(2));
      expect(multi.results!.first.taskId, 't_1');
      expect(multi.results!.first.completedAt, 1.0);
      expect(multi.results!.last.taskId, 't_2');
      expect(multi.results!.last.completedAt, 2.5);
    });

    test('fromJson：results 非 List / 元素非对象 → null', () {
      expect(BackgroundStatusResponse.fromJson(const {}).results, isNull);
      expect(
        BackgroundStatusResponse.fromJson({'results': null}).results,
        isNull,
      );
      expect(
        BackgroundStatusResponse.fromJson({'results': 'bad'}).results,
        isNull,
      );
      expect(
        BackgroundStatusResponse.fromJson({'results': 7}).results,
        isNull,
      );
      expect(
        BackgroundStatusResponse.fromJson({
          'results': {'task_id': 't'},
        }).results,
        isNull,
      );
      // 数组里出现非对象元素 → 整个数组解码失败（不是逐项兜底）。
      expect(
        BackgroundStatusResponse.fromJson({
          'results': [1],
        }).results,
        isNull,
      );
      expect(
        BackgroundStatusResponse.fromJson({
          'results': [
            {'task_id': 't'},
            'bad',
          ],
        }).results,
        isNull,
      );
    });

    test('fromJson：元素全字段缺失仍是合法对象', () {
      final response = BackgroundStatusResponse.fromJson(const {
        'results': <Object?>[<String, Object?>{}],
      });
      expect(response.results, hasLength(1));
      expect(response.results!.single.taskId, isNull);
      expect(response.results!.single.completedAt, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      BackgroundStatusResponse build(List<Object?>? results) =>
          BackgroundStatusResponse.fromJson({'results': results});

      final base = build([
        {'task_id': 't1', 'prompt': 'p', 'answer': 'a', 'completed_at': 1.0},
      ]);
      expect(
        base,
        build([
          {'task_id': 't1', 'prompt': 'p', 'answer': 'a', 'completed_at': 1.0},
        ]),
      );
      expect(
        base.hashCode,
        build([
          {'task_id': 't1', 'prompt': 'p', 'answer': 'a', 'completed_at': 1.0},
        ]).hashCode,
      );
      expect(base.toString(), 'BackgroundStatusResponse(results: 1)');
      expect(
        const BackgroundStatusResponse().toString(),
        'BackgroundStatusResponse(results: null)',
      );

      // null vs 空列表（deepEquals 的 null 分支）。
      expect(base == const BackgroundStatusResponse(), isFalse);
      expect(const BackgroundStatusResponse() == build(<Object?>[]), isFalse);
      // 长度不同。
      expect(
        base ==
            build([
              {'task_id': 't1', 'prompt': 'p', 'answer': 'a', 'completed_at': 1.0},
              {'task_id': 't2', 'prompt': 'p', 'answer': 'a', 'completed_at': 1.0},
            ]),
        isFalse,
      );
      // 同长度、逐元素只差一个字段（走 BackgroundResult ==）。
      expect(
        base ==
            build([
              {
                'task_id': 't2',
                'prompt': 'p',
                'answer': 'a',
                'completed_at': 1.0,
              },
            ]),
        isFalse,
      );
      expect(
        base ==
            build([
              {
                'task_id': 't1',
                'prompt': 'p',
                'answer': 'a',
                'completed_at': 2.0,
              },
            ]),
        isFalse,
      );
      expect(base == Object(), isFalse);
    });
  });

  group('BackgroundResult', () {
    test('fromJson：四键正常解析', () {
      final response = BackgroundResult.fromJson({
        'task_id': 't_1',
        'prompt': '写周报',
        'answer': '已完成',
        'completed_at': 1723700000.0,
      });
      expect(response.taskId, 't_1');
      expect(response.prompt, '写周报');
      expect(response.answer, '已完成');
      expect(response.completedAt, 1723700000.0);
    });

    test('fromJson：completed_at 宽容（int / 数字字符串 / trim）', () {
      expect(
        BackgroundResult.fromJson({'completed_at': 1723700000}).completedAt,
        1723700000.0,
      );
      expect(
        BackgroundResult.fromJson({'completed_at': ' 2.5 '}).completedAt,
        2.5,
      );
      expect(
        BackgroundResult.fromJson({'completed_at': '3'}).completedAt,
        3.0,
      );
    });

    test('fromJson：completed_at 不可转换 → null', () {
      expect(
        BackgroundResult.fromJson({'completed_at': 'abc'}).completedAt,
        isNull,
      );
      expect(
        BackgroundResult.fromJson({'completed_at': true}).completedAt,
        isNull,
      );
      expect(
        BackgroundResult.fromJson({
          'completed_at': [1],
        }).completedAt,
        isNull,
      );
      expect(
        BackgroundResult.fromJson({'completed_at': null}).completedAt,
        isNull,
      );
    });

    test('fromJson：全缺失 / null / 字符串字段类型不符', () {
      final empty = BackgroundResult.fromJson(const {});
      expect(empty.taskId, isNull);
      expect(empty.prompt, isNull);
      expect(empty.answer, isNull);
      expect(empty.completedAt, isNull);

      final coerced = BackgroundResult.fromJson({
        'task_id': 1,
        'prompt': 2,
        'answer': false,
      });
      expect(coerced.taskId, '1');
      expect(coerced.prompt, '2');
      expect(coerced.answer, 'false');

      final wrong = BackgroundResult.fromJson({
        'task_id': [1],
        'prompt': <Object?>[],
        'answer': {'a': 1},
      });
      expect(wrong.taskId, isNull);
      expect(wrong.prompt, isNull);
      expect(wrong.answer, isNull);
    });

    test('fromJson：无 camelCase 回退（taskId / completedAt 不认）', () {
      final response = BackgroundResult.fromJson({
        'taskId': 't_camel',
        'completedAt': 1.0,
      });
      expect(response.taskId, isNull);
      expect(response.completedAt, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      BackgroundResult build({
        String? taskId,
        String? prompt,
        String? answer,
        double? completedAt,
      }) =>
          BackgroundResult.fromJson({
            'task_id': taskId,
            'prompt': prompt,
            'answer': answer,
            'completed_at': completedAt,
          });

      final base = build(
        taskId: 't1',
        prompt: 'p1',
        answer: 'a1',
        completedAt: 1.5,
      );
      expect(
        base,
        build(taskId: 't1', prompt: 'p1', answer: 'a1', completedAt: 1.5),
      );
      expect(
        base.hashCode,
        build(taskId: 't1', prompt: 'p1', answer: 'a1', completedAt: 1.5)
            .hashCode,
      );
      expect(base.toString(), 'BackgroundResult(taskId: t1)');
      expect(
        const BackgroundResult().toString(),
        'BackgroundResult(taskId: null)',
      );

      expect(
        base ==
            build(
              taskId: 't2',
              prompt: 'p1',
              answer: 'a1',
              completedAt: 1.5,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              taskId: 't1',
              prompt: 'p2',
              answer: 'a1',
              completedAt: 1.5,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              taskId: 't1',
              prompt: 'p1',
              answer: 'a2',
              completedAt: 1.5,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              taskId: 't1',
              prompt: 'p1',
              answer: 'a1',
              completedAt: 2.5,
            ),
        isFalse,
      );
      expect(base == const BackgroundResult(), isFalse);
      expect(base == Object(), isFalse);
    });
  });
}
