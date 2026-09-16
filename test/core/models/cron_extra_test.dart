import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/cron.dart';

/// cron.dart 补测：值语义（== / hashCode / toString）逐字段阶梯、
/// running 双形态内部转换分支、editableScheduleText 回退链、
/// _listEquals 全分支。与 cron_test.dart 无重叠断言目标。
void main() {
  // ── CronJobsResponse ────────────────────────────────────────────────
  group('CronJobsResponse 值语义', () {
    test('== 逐形态：等值 / 元素不等 / 长度不等 / 双空 / 单空 / 非同类', () {
      final a = CronJobsResponse.fromJson({
        'jobs': [
          {'id': 'cron_1', 'name': 'A'},
        ],
      });
      final b = CronJobsResponse.fromJson({
        'jobs': [
          {'id': 'cron_1', 'name': 'A'},
        ],
      });
      final differentElement = CronJobsResponse.fromJson({
        'jobs': [
          {'id': 'cron_2', 'name': 'A'},
        ],
      });
      final emptyList = CronJobsResponse.fromJson({'jobs': const <Object?>[]});
      final nullJobs = CronJobsResponse.fromJson(const {});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == differentElement, isFalse);
      expect(a == emptyList, isFalse);
      expect(nullJobs, CronJobsResponse.fromJson(const {}));
      expect(a == nullJobs, isFalse);
      expect(nullJobs == a, isFalse);
      expect(a == Object(), isFalse);
    });

    test('toString 带空与非空两种计数', () {
      final one = CronJobsResponse.fromJson({
        'jobs': [
          {'id': 'cron_1'},
        ],
      });
      expect(one.toString(), 'CronJobsResponse(jobs: 1)');
      expect(
        CronJobsResponse.fromJson(const {}).toString(),
        'CronJobsResponse(jobs: null)',
      );
      expect(
        CronJobsResponse.fromJson({'jobs': const <Object?>[]}).toString(),
        'CronJobsResponse(jobs: 0)',
      );
    });
  });

  // ── CronMutationResponse ────────────────────────────────────────────
  group('CronMutationResponse 值语义', () {
    test('== 逐字段阶梯（ok / job / error）', () {
      final base = CronMutationResponse.fromJson({
        'ok': true,
        'job': {'id': 'cron_1'},
        'error': 'boom',
      });
      final same = CronMutationResponse.fromJson({
        'ok': true,
        'job': {'id': 'cron_1'},
        'error': 'boom',
      });
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      expect(
        base ==
            CronMutationResponse.fromJson({
              'ok': false,
              'job': {'id': 'cron_1'},
              'error': 'boom',
            }),
        isFalse,
      );
      expect(
        base ==
            CronMutationResponse.fromJson({
              'ok': true,
              'job': {'id': 'cron_2'},
              'error': 'boom',
            }),
        isFalse,
      );
      expect(
        base ==
            CronMutationResponse.fromJson({
              'ok': true,
              'job': {'id': 'cron_1'},
              'error': 'other',
            }),
        isFalse,
      );
      expect(base == Object(), isFalse);
    });

    test('空信封 + 宽松类型 + toString', () {
      final typed = CronMutationResponse.fromJson(const {'ok': 1});
      expect(typed.ok, isTrue);
      expect(typed.job, isNull);
      expect(typed.error, isNull);
      expect(typed.toString(), 'CronMutationResponse(ok: true)');
      expect(
        CronMutationResponse.fromJson(const {}).toString(),
        'CronMutationResponse(ok: null)',
      );
      expect(
        CronMutationResponse.fromJson(const {}),
        CronMutationResponse.fromJson(const {}),
      );
      expect(CronMutationResponse.fromJson(const {}) == typed, isFalse);
      expect(
        CronMutationResponse.fromJson(const {}).hashCode,
        CronMutationResponse.fromJson(const {}).hashCode,
      );
      // error 非字符串（int）→ lossy 转字符串
      expect(CronMutationResponse.fromJson(const {'error': 7}).error, '7');
      // error 为 null 显式键
      expect(CronMutationResponse.fromJson(const {'error': null}).error, isNull);
    });
  });

  // ── CronStatusResponse ──────────────────────────────────────────────
  group('CronStatusResponse 值语义与 _toDouble 分支', () {
    test('running Map 值 int → double', () {
      final response = CronStatusResponse.fromJson({
        'running': {'cron_1': 3, 'cron_2': 0},
      });
      expect(response.running, isNull);
      expect(response.runningJobs, {'cron_1': 3.0, 'cron_2': 0.0});
    });

    test('running Map 值 String（含空白）→ double', () {
      final response = CronStatusResponse.fromJson({
        'running': {'cron_1': ' 12.5 ', 'cron_2': '3'},
      });
      expect(response.runningJobs, {'cron_1': 12.5, 'cron_2': 3.0});
    });

    test('running Map 值不可转 → 整体判废（runningJobs = null）', () {
      expect(
        CronStatusResponse.fromJson({
          'running': {'cron_1': 'not-a-number'},
        }).runningJobs,
        isNull,
      );
      expect(
        CronStatusResponse.fromJson({
          'running': {'cron_1': 1.5, 'cron_2': <String>[]},
        }).runningJobs,
        isNull,
      );
      expect(
        CronStatusResponse.fromJson({
          'running': {'cron_1': null},
        }).runningJobs,
        isNull,
      );
    });

    test('running 非 bool 非 Map → 两个字段都 null', () {
      final response = CronStatusResponse.fromJson({'running': 'yes'});
      expect(response.running, isNull);
      expect(response.runningJobs, isNull);
      expect(CronStatusResponse.fromJson(const {'running': 1}).running, isNull);
    });

    test('== 逐字段阶梯（jobId / running / elapsed / runningJobs / error）', () {
      final base = CronStatusResponse.fromJson({
        'job_id': 'cron_1',
        'running': true,
        'elapsed': 1.5,
        'error': 'boom',
      });
      final same = CronStatusResponse.fromJson({
        'job_id': 'cron_1',
        'running': true,
        'elapsed': 1.5,
        'error': 'boom',
      });
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      expect(
        CronStatusResponse.fromJson(const {'job_id': 'other'}) == base,
        isFalse,
      );
      expect(
        CronStatusResponse.fromJson(
              const {'job_id': 'cron_1', 'running': false},
            ) ==
            base,
        isFalse,
      );
      expect(
        CronStatusResponse.fromJson(
              const {'job_id': 'cron_1', 'elapsed': 2.0},
            ) ==
            base,
        isFalse,
      );
      expect(
        CronStatusResponse.fromJson(const {'job_id': 'cron_1', 'error': 'x'}) ==
            base,
        isFalse,
      );

      final jobsA = CronStatusResponse.fromJson({
        'running': {'cron_1': 1.0},
      });
      final jobsB = CronStatusResponse.fromJson({
        'running': {'cron_1': 1.0},
      });
      final jobsOtherKey = CronStatusResponse.fromJson({
        'running': {'cron_2': 1.0},
      });
      final jobsMoreKeys = CronStatusResponse.fromJson({
        'running': {'cron_1': 1.0, 'cron_2': 2.0},
      });
      expect(jobsA, jobsB);
      expect(jobsA.hashCode, jobsB.hashCode);
      expect(jobsA == jobsOtherKey, isFalse);
      expect(jobsA == jobsMoreKeys, isFalse);
      expect(jobsA == base, isFalse);
      expect(base == jobsA, isFalse);
      expect(base == Object(), isFalse);
    });

    test('toString 两种形态', () {
      expect(
        CronStatusResponse.fromJson({
          'job_id': 'cron_1',
          'running': true,
        }).toString(),
        'CronStatusResponse(jobId: cron_1, running: true)',
      );
      expect(
        CronStatusResponse.fromJson({
          'job_id': 'cron_1',
          'running': {'cron_1': 1.0},
        }).toString(),
        'CronStatusResponse(jobId: cron_1, running: null)',
      );
      expect(
        CronStatusResponse.fromJson(const {}).toString(),
        'CronStatusResponse(jobId: null, running: null)',
      );
    });
  });

  // ── CronOutputResponse / CronOutputItem ─────────────────────────────
  group('CronOutputResponse 值语义', () {
    test('== 逐字段阶梯 / hashCode / toString', () {
      final a = CronOutputResponse.fromJson({
        'job_id': 'cron_1',
        'outputs': [
          {'filename': 'a.txt'},
        ],
      });
      final b = CronOutputResponse.fromJson({
        'job_id': 'cron_1',
        'outputs': [
          {'filename': 'a.txt'},
        ],
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'CronOutputResponse(jobId: cron_1)');
      expect(
        a ==
            CronOutputResponse.fromJson({
              'job_id': 'cron_2',
              'outputs': [
                {'filename': 'a.txt'},
              ],
            }),
        isFalse,
      );
      expect(
        a ==
            CronOutputResponse.fromJson({
              'job_id': 'cron_1',
              'outputs': [
                {'filename': 'b.txt'},
              ],
            }),
        isFalse,
      );
      expect(
        a == CronOutputResponse.fromJson(const {'job_id': 'cron_1'}),
        isFalse,
      );
      expect(
        a ==
            CronOutputResponse.fromJson({
              'job_id': 'cron_1',
              'outputs': const <Object?>[],
            }),
        isFalse,
      );
      expect(
        CronOutputResponse.fromJson(const {}),
        CronOutputResponse.fromJson(const {}),
      );
      expect(
        CronOutputResponse.fromJson(const {}).toString(),
        'CronOutputResponse(jobId: null)',
      );
      expect(a == Object(), isFalse);
    });
  });

  group('CronOutputItem 值语义', () {
    test('== 逐字段阶梯 / hashCode / toString', () {
      const a = CronOutputItem(filename: 'a.txt', content: 'c');
      const b = CronOutputItem(filename: 'a.txt', content: 'c');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'CronOutputItem(filename: a.txt)');
      expect(a == const CronOutputItem(filename: 'b.txt', content: 'c'), isFalse);
      expect(a == const CronOutputItem(filename: 'a.txt', content: 'd'), isFalse);
      expect(
        a == const CronOutputItem(filename: 'a.txt', content: null),
        isFalse,
      );
      expect(const CronOutputItem(), const CronOutputItem());
      expect(a == Object(), isFalse);
    });

    test('id = filename ?? uuidV4', () {
      expect(const CronOutputItem(filename: 'a.txt').id, 'a.txt');
      expect(const CronOutputItem(filename: '').id, '');
      final first = const CronOutputItem().id;
      final second = const CronOutputItem().id;
      expect(first, isNotEmpty);
      expect(first.length, 36);
      expect(first == second, isFalse);
      expect(
        CronOutputItem.fromJson(const {'content': '只有内容'}).id.length,
        36,
      );
      // 近似类型：optString 只认 String → filename 判 null → 回落 uuid
      expect(CronOutputItem.fromJson(const {'filename': 7}).filename, isNull);
      expect(CronOutputItem.fromJson(const {'filename': 7}).id.length, 36);
    });
  });

  // ── CronDeliveryOptionsResponse / CronDeliveryOption ────────────────
  group('CronDeliveryOptionsResponse 值语义', () {
    test('== 逐形态 / hashCode / toString', () {
      final a = CronDeliveryOptionsResponse.fromJson({
        'platforms': [
          {'value': 'local', 'label': '本地'},
        ],
      });
      final b = CronDeliveryOptionsResponse.fromJson({
        'platforms': [
          {'value': 'local', 'label': '本地'},
        ],
      });
      final differentElement = CronDeliveryOptionsResponse.fromJson({
        'platforms': [
          {'value': 'other', 'label': '本地'},
        ],
      });
      final nullPlatforms = CronDeliveryOptionsResponse.fromJson(const {});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'CronDeliveryOptionsResponse(platforms: 1)');
      expect(a == differentElement, isFalse);
      expect(a == nullPlatforms, isFalse);
      expect(nullPlatforms == a, isFalse);
      expect(nullPlatforms, CronDeliveryOptionsResponse.fromJson(const {}));
      expect(nullPlatforms.toString(), 'CronDeliveryOptionsResponse(platforms: null)');
      expect(a == Object(), isFalse);
    });
  });

  group('CronDeliveryOption 值语义', () {
    test('== 逐字段阶梯 / hashCode / toString', () {
      const a = CronDeliveryOption(value: 'local', label: '本地');
      const b = CronDeliveryOption(value: 'local', label: '本地');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'CronDeliveryOption(value: local, label: 本地)');
      expect(a == const CronDeliveryOption(value: 'other', label: '本地'), isFalse);
      expect(a == const CronDeliveryOption(value: 'local', label: '其他'), isFalse);
      expect(a == const CronDeliveryOption(value: 'local'), isFalse);
      expect(const CronDeliveryOption(), const CronDeliveryOption());
      expect(const CronDeliveryOption().toString(), 'CronDeliveryOption(value: null, label: null)');
      expect(a == Object(), isFalse);
    });

    test('id 三级回退 value → label → uuid', () {
      expect(const CronDeliveryOption(value: 'local', label: '本地').id, 'local');
      expect(const CronDeliveryOption(label: '只有标签').id, '只有标签');
      expect(const CronDeliveryOption(value: '').id, '');
      final generated = const CronDeliveryOption().id;
      expect(generated, isNotEmpty);
      expect(generated.length, 36);
      expect(const CronDeliveryOption().id == generated, isFalse);
    });
  });

  // ── CronRepeat ──────────────────────────────────────────────────────
  group('CronRepeat 值语义', () {
    test('== 逐字段阶梯 / hashCode / toString', () {
      const a = CronRepeat(times: 30, completed: 12);
      const b = CronRepeat(times: 30, completed: 12);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'CronRepeat(times: 30, completed: 12)');
      expect(a == const CronRepeat(times: 31, completed: 12), isFalse);
      expect(a == const CronRepeat(times: 30, completed: 13), isFalse);
      expect(a == const CronRepeat(times: 30), isFalse);
      expect(const CronRepeat(), const CronRepeat());
      expect(const CronRepeat().toString(), 'CronRepeat(times: null, completed: null)');
      expect(a == Object(), isFalse);
    });

    test('fromJson 宽松转换', () {
      final repeat = CronRepeat.fromJson(const {'times': 3.9, 'completed': '12'});
      expect(repeat.times, 3);
      expect(repeat.completed, 12);
      expect(CronRepeat.fromJson(const {'times': 'abc'}).times, isNull);
      expect(CronRepeat.fromJson(const {'times': '3.9'}).times, 3);
      expect(CronRepeat.fromJson(const {'times': <Object?>[]}).times, isNull);
      expect(CronRepeat.fromJson(const {'times': <String, Object?>{}}).times, isNull);
      expect(CronRepeat.fromJson(const {}).completed, isNull);
    });
  });

  // ── CronJob.editableScheduleText / 逐字段 == ────────────────────────
  group('CronJob.editableScheduleText 回退链', () {
    test('expression → expr → run_at → every → schedule_display', () {
      expect(
        CronJob.fromJson({
          'schedule': {
            'kind': 'cron',
            'expression': 'E',
            'expr': 'X',
            'run_at': 'R',
            'every': 'V',
          },
          'schedule_display': 'D',
        }).editableScheduleText,
        'E',
      );
      expect(
        CronJob.fromJson({
          'schedule': {'expr': 'X', 'run_at': 'R', 'every': 'V'},
          'schedule_display': 'D',
        }).editableScheduleText,
        'X',
      );
      expect(
        CronJob.fromJson({
          'schedule': {'run_at': 'R', 'every': 'V'},
          'schedule_display': 'D',
        }).editableScheduleText,
        'R',
      );
      expect(
        CronJob.fromJson({
          'schedule': {'every': 'V'},
          'schedule_display': 'D',
        }).editableScheduleText,
        'V',
      );
      expect(
        CronJob.fromJson({
          'schedule': {'kind': 'cron'},
          'schedule_display': 'D',
        }).editableScheduleText,
        'D',
      );
      // 只有裸字符串 schedule
      expect(
        CronJob.fromJson(const {'schedule': 'raw'}).editableScheduleText,
        'raw',
      );
      // 全空
      expect(CronJob.fromJson(const {}).editableScheduleText, isNull);
      expect(
        CronJob.fromJson(const {'schedule': <String, Object?>{}})
            .editableScheduleText,
        isNull,
      );
      // scheduleText 同链（display ?? schedule.displayText）
      expect(
        CronJob.fromJson({
          'schedule': {'every': 'V'},
        }).scheduleText,
        'V',
      );
      expect(CronJob.fromJson(const {'schedule_display': 'D'}).scheduleText, 'D');
    });
  });

  group('CronJob.== 逐字段阶梯与 _listEquals 全分支', () {
    test('基准载荷等值 + 每次只改一个键都判不等', () {
      final base = <String, Object?>{
        'id': 'cron_1',
        'name': 'n',
        'prompt': 'p',
        'schedule': '0 3 * * *',
        'schedule_display': 'D',
        'enabled': true,
        'state': 'active',
        'next_run_at': 1,
        'last_run_at': 2,
        'last_status': 'ok',
        'last_error': 'e1',
        'last_delivery_error': 'e2',
        'repeat': {'times': 1},
        'deliver': 'local',
        'skills': <String>['a'],
        'model': 'm',
        'provider': 'pr',
        'profile': 'pf',
        'toast_notifications': true,
      };
      final reference = CronJob.fromJson(base);
      expect(CronJob.fromJson(base), reference);
      expect(CronJob.fromJson(base).hashCode, reference.hashCode);
      expect(reference.toString(), 'CronJob(jobId: cron_1, name: n)');

      final mutations = <String, Object?>{
        'id': 'cron_2',
        'name': 'n2',
        'prompt': 'p2',
        'schedule': '0 4 * * *',
        'schedule_display': 'D2',
        'enabled': false,
        'state': 'paused',
        'next_run_at': 3,
        'last_run_at': 4,
        'last_status': 'error',
        'last_error': 'x1',
        'last_delivery_error': 'x2',
        'repeat': {'times': 2},
        'deliver': 'other',
        'skills': <String>['b'],
        'model': 'm2',
        'provider': 'pr2',
        'profile': 'pf2',
        'toast_notifications': false,
      };
      mutations.forEach((key, value) {
        final mutated = Map<String, Object?>.from(base)..[key] = value;
        expect(
          CronJob.fromJson(mutated) == reference,
          isFalse,
          reason: '字段 $key 变更应使 == 为 false',
        );
      });
      expect(reference == Object(), isFalse);
    });

    test('_listEquals：identical 列表 → true', () {
      final skills = <String>['a', 'b'];
      final a = CronJob(jobId: 'c1', skills: skills);
      final b = CronJob(jobId: 'c1', skills: skills);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('_listEquals：单侧 null → false', () {
      expect(
        const CronJob(jobId: 'c1'),
        isNot(const CronJob(jobId: 'c1', skills: ['a'])),
      );
      expect(
        const CronJob(jobId: 'c1', skills: ['a']),
        isNot(const CronJob(jobId: 'c1')),
      );
    });

    test('_listEquals：长度不等 → false', () {
      expect(
        const CronJob(jobId: 'c1', skills: ['a']),
        isNot(const CronJob(jobId: 'c1', skills: ['a', 'b'])),
      );
    });

    test('_listEquals：同长元素不等 → false', () {
      expect(
        const CronJob(jobId: 'c1', skills: ['a']),
        isNot(const CronJob(jobId: 'c1', skills: ['b'])),
      );
    });

    test('_listEquals：同长全等（不同列表实例）→ true', () {
      // 用函数构造，保证两个列表是不同实例（走逐元素比较而非 identical 短路）。
      List<String> buildSkills() => <String>['a', 'b'];
      final a = CronJob(jobId: 'c1', skills: buildSkills());
      final b = CronJob(jobId: 'c1', skills: buildSkills());
      expect(identical(a.skills, b.skills), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == Object(), isFalse);
    });
  });

  // ── CronSchedule ────────────────────────────────────────────────────
  group('CronSchedule 值语义与 displayText 回退', () {
    test('== 逐字段阶梯 / hashCode / toString', () {
      const a = CronSchedule(
        kind: 'cron',
        expression: 'E',
        expr: 'X',
        runAt: 'R',
        every: 'V',
      );
      const b = CronSchedule(
        kind: 'cron',
        expression: 'E',
        expr: 'X',
        runAt: 'R',
        every: 'V',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'CronSchedule(kind: cron, expression: E)');
      expect(
        a ==
            const CronSchedule(
              kind: 'once',
              expression: 'E',
              expr: 'X',
              runAt: 'R',
              every: 'V',
            ),
        isFalse,
      );
      expect(
        a ==
            const CronSchedule(
              kind: 'cron',
              expression: 'Z',
              expr: 'X',
              runAt: 'R',
              every: 'V',
            ),
        isFalse,
      );
      expect(
        a ==
            const CronSchedule(
              kind: 'cron',
              expression: 'E',
              expr: 'Y',
              runAt: 'R',
              every: 'V',
            ),
        isFalse,
      );
      expect(
        a ==
            const CronSchedule(
              kind: 'cron',
              expression: 'E',
              expr: 'X',
              runAt: 'S',
              every: 'V',
            ),
        isFalse,
      );
      expect(
        a ==
            const CronSchedule(
              kind: 'cron',
              expression: 'E',
              expr: 'X',
              runAt: 'R',
              every: 'W',
            ),
        isFalse,
      );
      expect(const CronSchedule(kind: 'cron'), isNot(a));
      expect(const CronSchedule(), const CronSchedule());
      expect(const CronSchedule().hashCode, const CronSchedule().hashCode);
      expect(const CronSchedule().toString(), 'CronSchedule(kind: null, expression: null)');
      expect(a == Object(), isFalse);
    });

    test('displayText 全链回退', () {
      expect(
        const CronSchedule(
          kind: 'K',
          expression: 'E',
          expr: 'X',
          runAt: 'R',
          every: 'V',
        ).displayText,
        'E',
      );
      expect(const CronSchedule(kind: 'K', expr: 'X', runAt: 'R', every: 'V').displayText, 'X');
      expect(const CronSchedule(kind: 'K', runAt: 'R', every: 'V').displayText, 'R');
      expect(const CronSchedule(kind: 'K', every: 'V').displayText, 'V');
      expect(const CronSchedule(kind: 'K').displayText, 'K');
      expect(const CronSchedule().displayText, isNull);
    });

    test('fromJson / tryParse 各形态', () {
      expect(CronSchedule.fromJson('raw').expression, 'raw');
      expect(CronSchedule.fromJson('raw').kind, isNull);
      expect(CronSchedule.fromJson(const {}).displayText, isNull);
      expect(CronSchedule.fromJson(null).displayText, isNull);
      expect(CronSchedule.fromJson(42).displayText, isNull);
      expect(CronSchedule.fromJson(true).displayText, isNull);
      expect(CronSchedule.fromJson(const <Object?>[]).displayText, isNull);
      expect(CronSchedule.tryParse('raw')!.expression, 'raw');
      expect(CronSchedule.tryParse(42), isNull);
      expect(CronSchedule.tryParse(null), isNull);
      expect(CronSchedule.tryParse(true), isNull);
      expect(CronSchedule.tryParse(const <Object?>[]), isNull);
      // 对象里的宽松转换（int → 字符串）
      final lossy = CronSchedule.tryParse(const {'expression': 1, 'every': 2.5});
      expect(lossy!.expression, '1');
      expect(lossy.every, '2.5');
      // 近似键名不被识别
      final nearMiss = CronSchedule.tryParse(const {
        'Expression': 'E',
        'EXPR': 'X',
        'run-at': 'R',
        'everY': 'V',
      });
      expect(nearMiss!.expression, isNull);
      expect(nearMiss.expr, isNull);
      expect(nearMiss.runAt, isNull);
      expect(nearMiss.every, isNull);
      expect(nearMiss.displayText, isNull);
    });
  });

  // ── CronDateValue ───────────────────────────────────────────────────
  group('CronDateValue 值语义', () {
    test('== / hashCode / toString', () {
      final a = CronDateValue.tryParse(1723798800)!;
      final b = CronDateValue.tryParse('1723798800')!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), startsWith('CronDateValue('));
      expect(a == CronDateValue.tryParse(1723798801)!, isFalse);
      expect(
        a == CronDateValue(DateTime.fromMillisecondsSinceEpoch(1723798800000)),
        isTrue,
      );
      expect(a == Object(), isFalse);
      // 同秒但 UTC/本地差异 → 不等
      final utc = CronDateValue(DateTime.utc(2026, 8, 15, 3));
      final local = CronDateValue(DateTime(2026, 8, 15, 3));
      expect(utc == local, isFalse);
    });

    test('tryParse 各形态（空白 / 负数 / ISO / 非法）', () {
      expect(
        CronDateValue.tryParse(' 1723798800 ')!.date.millisecondsSinceEpoch,
        1723798800000,
      );
      expect(
        CronDateValue.tryParse(-1)!.date.millisecondsSinceEpoch,
        -1000,
      );
      expect(CronDateValue.tryParse(0)!.date, DateTime.fromMillisecondsSinceEpoch(0));
      expect(
        CronDateValue.tryParse('2026-08-15')!.date,
        DateTime.parse('2026-08-15'),
      );
      expect(
        CronDateValue.tryParse('2026-08-15T03:00:00')!.date,
        DateTime.parse('2026-08-15T03:00:00'),
      );
      expect(CronDateValue.tryParse(''), isNull);
      expect(CronDateValue.tryParse('   '), isNull);
      expect(CronDateValue.tryParse('garbage'), isNull);
      expect(CronDateValue.tryParse(const <String, Object?>{}), isNull);
      expect(CronDateValue.tryParse(const <Object?>[]), isNull);
      expect(CronDateValue.tryParse(true), isNull);
      expect(CronDateValue.tryParse(null), isNull);
    });

    test('CronJob 日期字段：合法 / 非法 / 时间戳 / null 各一例', () {
      final job = CronJob.fromJson(const {
        'next_run_at': 1723798800,
        'last_run_at': '2026-08-15T03:00:00Z',
      });
      expect(job.nextRunAt!.date.millisecondsSinceEpoch, 1723798800000);
      expect(job.lastRunAt!.date.toUtc(), DateTime.utc(2026, 8, 15, 3));

      final bad = CronJob.fromJson(const {
        'next_run_at': 'not-a-date',
        'last_run_at': 0,
      });
      expect(bad.nextRunAt, isNull);
      expect(bad.lastRunAt!.date, DateTime.fromMillisecondsSinceEpoch(0));

      final absent = CronJob.fromJson(const {'next_run_at': null, 'last_run_at': null});
      expect(absent.nextRunAt, isNull);
      expect(absent.lastRunAt, isNull);
    });
  });

  // ── 空集合边沿（§4 要求「空集合」各成一例）────────────────────────
  group('空集合边沿', () {
    test('running 空 Map → runningJobs 为空 Map（非 null）', () {
      final response = CronStatusResponse.fromJson(
        const {'running': <String, Object?>{}},
      );
      expect(response.running, isNull);
      expect(response.runningJobs, isNotNull);
      expect(response.runningJobs, isEmpty);
    });

    test('skills 空列表 → 空列表且两个空列表相等（循环零次）', () {
      final job = CronJob.fromJson(const {'skills': <Object?>[]});
      expect(job.skills, isEmpty);
      final a = CronJob.fromJson(const {'skills': <Object?>[]});
      final b = CronJob.fromJson(const {'skills': <Object?>[]});
      expect(identical(a.skills, b.skills), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('jobs / outputs / platforms 空列表', () {
      expect(
        CronJobsResponse.fromJson(const {'jobs': <Object?>[]}).jobs,
        isEmpty,
      );
      expect(
        CronOutputResponse.fromJson(const {'outputs': <Object?>[]}).outputs,
        isEmpty,
      );
      expect(
        CronDeliveryOptionsResponse.fromJson(const {'platforms': <Object?>[]})
            .platforms,
        isEmpty,
      );
    });

    test('schedule 空对象 → 全字段 null，displayText / editableScheduleText 均 null', () {
      final job = CronJob.fromJson(const {'schedule': <String, Object?>{}});
      expect(job.schedule, isNotNull);
      expect(job.schedule!.displayText, isNull);
      expect(job.scheduleText, isNull);
      expect(job.editableScheduleText, isNull);
      expect(job.isRecurring, isFalse);
    });
  });
}
