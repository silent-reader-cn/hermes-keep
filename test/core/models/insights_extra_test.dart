import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/insights.dart';

/// insights 模型补测（覆盖率补强，批次 A）。
///
/// 既有 `test/features/insights/insights_test.dart` 走的是页面级路径，
/// 这里专攻模型自身的容错分支、双键回退、内联 `==` / `hashCode` / `toString`
/// 与派生 getter。预期值全部按实现读出来写死，不用「非空即通过」的空断言。
void main() {
  group('InsightsResponse.fromJson', () {
    test('snake_case 全字段 + 四组嵌套数组', () {
      final r = InsightsResponse.fromJson({
        'period_days': 7,
        'total_sessions': 12,
        'total_messages': 345,
        'total_input_tokens': 1000,
        'total_output_tokens': 2000,
        'total_tokens': 3000,
        'total_cost': 1.25,
        'total_cache_read_tokens': 500,
        'total_cache_hit_percent': 42.5,
        'models': [
          {'model': 'gpt-x', 'sessions': 3},
        ],
        'daily_tokens': [
          {'date': '2026-09-15', 'input_tokens': 10, 'output_tokens': 20},
        ],
        'activity_by_day': [
          {'day': 'Mon', 'sessions': 4},
        ],
        'activity_by_hour': [
          {'hour': 9, 'sessions': 2},
        ],
      });

      expect(r.periodDays, 7);
      expect(r.totalSessions, 12);
      expect(r.totalMessages, 345);
      expect(r.totalInputTokens, 1000);
      expect(r.totalOutputTokens, 2000);
      expect(r.totalTokens, 3000);
      expect(r.totalCost, 1.25);
      expect(r.totalCacheReadTokens, 500);
      expect(r.totalCacheHitPercent, 42.5);
      expect(r.models, hasLength(1));
      expect(r.models!.first.model, 'gpt-x');
      expect(r.dailyTokens, hasLength(1));
      expect(r.dailyTokens!.first.date, '2026-09-15');
      expect(r.activityByDay, hasLength(1));
      expect(r.activityByDay!.first.day, 'Mon');
      expect(r.activityByHour, hasLength(1));
      expect(r.activityByHour!.first.hour, 9);
    });

    test('camelCase 别名回退：标量走 firstKey、三个数组走 snake ?? camel', () {
      final r = InsightsResponse.fromJson({
        'periodDays': 30,
        'totalSessions': 1,
        'totalMessages': 2,
        'totalInputTokens': 3,
        'totalOutputTokens': 4,
        'totalTokens': 5,
        'totalCost': 6.5,
        'totalCacheReadTokens': 7,
        'totalCacheHitPercent': 8.5,
        'dailyTokens': [
          {'date': 'd', 'inputTokens': 1, 'outputTokens': 2},
        ],
        'activityByDay': [
          {'day': 'Tue', 'sessions': 5},
        ],
        'activityByHour': [
          {'hour': 3, 'sessions': 6},
        ],
      });

      expect(r.periodDays, 30);
      expect(r.totalSessions, 1);
      expect(r.totalMessages, 2);
      expect(r.totalInputTokens, 3);
      expect(r.totalOutputTokens, 4);
      expect(r.totalTokens, 5);
      expect(r.totalCost, 6.5);
      expect(r.totalCacheReadTokens, 7);
      expect(r.totalCacheHitPercent, 8.5);
      expect(r.dailyTokens!.first.date, 'd');
      expect(r.activityByDay!.first.day, 'Tue');
      expect(r.activityByHour!.first.hour, 3);
    });

    test('snake_case 与 camelCase 同时存在时 snake 优先', () {
      final r = InsightsResponse.fromJson({
        'period_days': 7,
        'periodDays': 30,
        'daily_tokens': [
          {'date': 'snake'},
        ],
        'dailyTokens': [
          {'date': 'camel'},
        ],
      });

      expect(r.periodDays, 7);
      expect(r.dailyTokens!.first.date, 'snake');
    });

    test('空 json → 全 null', () {
      final r = InsightsResponse.fromJson({});

      expect(r.periodDays, isNull);
      expect(r.totalSessions, isNull);
      expect(r.totalMessages, isNull);
      expect(r.totalInputTokens, isNull);
      expect(r.totalOutputTokens, isNull);
      expect(r.totalTokens, isNull);
      expect(r.totalCost, isNull);
      expect(r.totalCacheReadTokens, isNull);
      expect(r.totalCacheHitPercent, isNull);
      expect(r.models, isNull);
      expect(r.dailyTokens, isNull);
      expect(r.activityByDay, isNull);
      expect(r.activityByHour, isNull);
    });

    test('错型 → 宽容转换或整数组置 null（绝不 throw）', () {
      final r = InsightsResponse.fromJson({
        'period_days': '7',
        'total_sessions': 1.9,
        'total_cost': '1.25',
        'models': 'not-a-list',
        'daily_tokens': [
          {'date': 'ok'},
          'not-a-map',
        ],
        'activity_by_day': [1, 2],
      });

      expect(r.periodDays, 7);
      expect(r.totalSessions, 1);
      expect(r.totalCost, 1.25);
      expect(r.models, isNull);
      expect(r.dailyTokens, isNull);
      expect(r.activityByDay, isNull);
    });

    test('字段为 null 时 firstKey 继续尝试下一个键', () {
      final r = InsightsResponse.fromJson({
        'period_days': null,
        'periodDays': 14,
      });

      expect(r.periodDays, 14);
    });
  });

  group('InsightsResponse.hasData', () {
    test('全空 → false', () {
      expect(InsightsResponse.fromJson({}).hasData, isFalse);
      expect(const InsightsResponse().hasData, isFalse);
    });

    test('不在判据内的字段非空 → 仍为 false', () {
      expect(const InsightsResponse(periodDays: 7).hasData, isFalse);
      expect(const InsightsResponse(totalCacheReadTokens: 1).hasData, isFalse);
      expect(const InsightsResponse(totalCacheHitPercent: 1).hasData, isFalse);
      expect(
        const InsightsResponse(
          activityByDay: [InsightsActivityByDay(day: 'a')],
        ).hasData,
        isFalse,
      );
      expect(
        const InsightsResponse(
          activityByHour: [InsightsActivityByHour(hour: 1)],
        ).hasData,
        isFalse,
      );
    });

    test('六个标量指标任一非空 → true（0 也算非空）', () {
      expect(const InsightsResponse(totalSessions: 0).hasData, isTrue);
      expect(const InsightsResponse(totalMessages: 0).hasData, isTrue);
      expect(const InsightsResponse(totalTokens: 0).hasData, isTrue);
      expect(const InsightsResponse(totalInputTokens: 0).hasData, isTrue);
      expect(const InsightsResponse(totalOutputTokens: 0).hasData, isTrue);
      expect(const InsightsResponse(totalCost: 0).hasData, isTrue);
    });

    test('models / dailyTokens：非空列表 true、空列表 false', () {
      expect(
        const InsightsResponse(
          models: [InsightsModelBreakdown(model: 'm')],
        ).hasData,
        isTrue,
      );
      expect(
        const InsightsResponse(
          dailyTokens: [InsightsDailyToken(date: 'd')],
        ).hasData,
        isTrue,
      );
      expect(const InsightsResponse(models: []).hasData, isFalse);
      expect(const InsightsResponse(dailyTokens: []).hasData, isFalse);
    });
  });

  group('InsightsResponse == / hashCode / toString', () {
    test('同内容不同实例（含四个 List 字段）→ 相等且 hashCode 一致', () {
      final a = InsightsResponse.fromJson({
        'period_days': 7,
        'models': [
          {'model': 'm'},
        ],
        'daily_tokens': [
          {'date': 'd'},
        ],
        'activity_by_day': [
          {'day': 'x'},
        ],
        'activity_by_hour': [
          {'hour': 1},
        ],
      });
      final b = InsightsResponse.fromJson({
        'period_days': 7,
        'models': [
          {'model': 'm'},
        ],
        'daily_tokens': [
          {'date': 'd'},
        ],
        'activity_by_day': [
          {'day': 'x'},
        ],
        'activity_by_hour': [
          {'hour': 1},
        ],
      });

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('List 字段为同一实例（identical 快路径）→ 相等', () {
      final shared = [
        const InsightsModelBreakdown(model: 'm'),
      ];
      final a = InsightsResponse(models: shared);
      final b = InsightsResponse(models: shared);

      expect(a, equals(b));
    });

    test('List 长度不同 / 元素不同 / 一侧为 null → 不等', () {
      const one = InsightsResponse(models: [InsightsModelBreakdown(model: 'm')]);
      const two = InsightsResponse(
        models: [
          InsightsModelBreakdown(model: 'm'),
          InsightsModelBreakdown(model: 'n'),
        ],
      );
      const other = InsightsResponse(models: [InsightsModelBreakdown(model: 'z')]);
      const empty = InsightsResponse();

      expect(one == two, isFalse);
      expect(one == other, isFalse);
      expect(one == empty, isFalse);
      expect(empty == one, isFalse);
    });

    test('阶梯式逐字段差异 → 不等（保证每行比较都被执行）', () {
      const r0 = InsightsResponse();
      const r1 = InsightsResponse(periodDays: 1);
      const r2 = InsightsResponse(periodDays: 1, totalSessions: 2);
      const r3 = InsightsResponse(
        periodDays: 1,
        totalSessions: 2,
        totalMessages: 3,
      );
      const r4 = InsightsResponse(
        periodDays: 1,
        totalSessions: 2,
        totalMessages: 3,
        totalInputTokens: 4,
      );
      const r5 = InsightsResponse(
        periodDays: 1,
        totalSessions: 2,
        totalMessages: 3,
        totalInputTokens: 4,
        totalOutputTokens: 5,
      );
      const r6 = InsightsResponse(
        periodDays: 1,
        totalSessions: 2,
        totalMessages: 3,
        totalInputTokens: 4,
        totalOutputTokens: 5,
        totalTokens: 6,
      );
      const r7 = InsightsResponse(
        periodDays: 1,
        totalSessions: 2,
        totalMessages: 3,
        totalInputTokens: 4,
        totalOutputTokens: 5,
        totalTokens: 6,
        totalCost: 7.0,
      );
      const r8 = InsightsResponse(
        periodDays: 1,
        totalSessions: 2,
        totalMessages: 3,
        totalInputTokens: 4,
        totalOutputTokens: 5,
        totalTokens: 6,
        totalCost: 7.0,
        totalCacheReadTokens: 8,
      );
      const r9 = InsightsResponse(
        periodDays: 1,
        totalSessions: 2,
        totalMessages: 3,
        totalInputTokens: 4,
        totalOutputTokens: 5,
        totalTokens: 6,
        totalCost: 7.0,
        totalCacheReadTokens: 8,
        totalCacheHitPercent: 9.0,
      );
      const r10 = InsightsResponse(
        periodDays: 1,
        totalSessions: 2,
        totalMessages: 3,
        totalInputTokens: 4,
        totalOutputTokens: 5,
        totalTokens: 6,
        totalCost: 7.0,
        totalCacheReadTokens: 8,
        totalCacheHitPercent: 9.0,
        models: [InsightsModelBreakdown(model: 'm')],
      );

      expect(r0 == r1, isFalse);
      expect(r1 == r2, isFalse);
      expect(r2 == r3, isFalse);
      expect(r3 == r4, isFalse);
      expect(r4 == r5, isFalse);
      expect(r5 == r6, isFalse);
      expect(r6 == r7, isFalse);
      expect(r7 == r8, isFalse);
      expect(r8 == r9, isFalse);
      expect(r9 == r10, isFalse);
    });

    test('dailyTokens / activity 字段差异 → 不等', () {
      const base = InsightsResponse(
        models: [InsightsModelBreakdown(model: 'm')],
      );
      const withDaily = InsightsResponse(
        models: [InsightsModelBreakdown(model: 'm')],
        dailyTokens: [InsightsDailyToken(date: 'd')],
      );
      const withDay = InsightsResponse(
        models: [InsightsModelBreakdown(model: 'm')],
        dailyTokens: [InsightsDailyToken(date: 'd')],
        activityByDay: [InsightsActivityByDay(day: 'a')],
      );
      const withHour = InsightsResponse(
        models: [InsightsModelBreakdown(model: 'm')],
        dailyTokens: [InsightsDailyToken(date: 'd')],
        activityByDay: [InsightsActivityByDay(day: 'a')],
        activityByHour: [InsightsActivityByHour(hour: 1)],
      );

      expect(base == withDaily, isFalse);
      expect(withDaily == withDay, isFalse);
      expect(withDay == withHour, isFalse);
    });

    test('与其它类型比较 → false', () {
      expect(const InsightsResponse() == Object(), isFalse);
    });

    test('toString 只含两个字段', () {
      expect(
        const InsightsResponse(periodDays: 7, totalSessions: 3).toString(),
        'InsightsResponse(periodDays: 7, totalSessions: 3)',
      );
    });
  });

  group('InsightsModelBreakdown', () {
    test('fromJson 全字段（snake_case）', () {
      final m = InsightsModelBreakdown.fromJson({
        'model': 'gpt-x',
        'sessions': 3,
        'input_tokens': 10,
        'output_tokens': 20,
        'total_tokens': 30,
        'cost': 1.5,
        'cache_hit_percent': 12.5,
        'session_share': 40,
        'token_share': 50,
        'cost_share': 60,
      });

      expect(m.model, 'gpt-x');
      expect(m.sessions, 3);
      expect(m.inputTokens, 10);
      expect(m.outputTokens, 20);
      expect(m.totalTokens, 30);
      expect(m.cost, 1.5);
      expect(m.cacheHitPercent, 12.5);
      expect(m.sessionShare, 40);
      expect(m.tokenShare, 50);
      expect(m.costShare, 60);
    });

    test('fromJson camelCase 回退 + 空 json 容错', () {
      final m = InsightsModelBreakdown.fromJson({
        'model': 'm',
        'inputTokens': 1,
        'outputTokens': 2,
        'totalTokens': 3,
        'cacheHitPercent': 4.5,
        'sessionShare': 5,
        'tokenShare': 6,
        'costShare': 7,
      });

      expect(m.inputTokens, 1);
      expect(m.outputTokens, 2);
      expect(m.totalTokens, 3);
      expect(m.cacheHitPercent, 4.5);
      expect(m.sessionShare, 5);
      expect(m.tokenShare, 6);
      expect(m.costShare, 7);

      final empty = InsightsModelBreakdown.fromJson({});
      expect(empty.model, isNull);
      expect(empty.sessions, isNull);
      expect(empty.inputTokens, isNull);
      expect(empty.outputTokens, isNull);
      expect(empty.totalTokens, isNull);
      expect(empty.cost, isNull);
      expect(empty.cacheHitPercent, isNull);
      expect(empty.sessionShare, isNull);
      expect(empty.tokenShare, isNull);
      expect(empty.costShare, isNull);
    });

    test('displayShare：cost → token → session 取首个 > 0，否则首个非空', () {
      expect(
        const InsightsModelBreakdown(
          costShare: 5,
          tokenShare: 3,
          sessionShare: 1,
        ).displayShare,
        5,
      );
      expect(
        const InsightsModelBreakdown(
          costShare: 0,
          tokenShare: 3,
          sessionShare: 1,
        ).displayShare,
        3,
      );
      expect(
        const InsightsModelBreakdown(
          costShare: 0,
          tokenShare: 0,
          sessionShare: 7,
        ).displayShare,
        7,
      );
      expect(
        const InsightsModelBreakdown(
          costShare: 0,
          tokenShare: 0,
          sessionShare: 0,
        ).displayShare,
        0,
      );
      expect(const InsightsModelBreakdown().displayShare, isNull);
      expect(const InsightsModelBreakdown(sessionShare: 9).displayShare, 9);
    });

    test('== / hashCode', () {
      const full = InsightsModelBreakdown(
        model: 'm',
        sessions: 1,
        inputTokens: 2,
        outputTokens: 3,
        totalTokens: 4,
        cost: 5.0,
        cacheHitPercent: 6.0,
        sessionShare: 7,
        tokenShare: 8,
        costShare: 9,
      );
      const same = InsightsModelBreakdown(
        model: 'm',
        sessions: 1,
        inputTokens: 2,
        outputTokens: 3,
        totalTokens: 4,
        cost: 5.0,
        cacheHitPercent: 6.0,
        sessionShare: 7,
        tokenShare: 8,
        costShare: 9,
      );

      expect(full, equals(same));
      expect(full.hashCode, same.hashCode);
      expect(full == Object(), isFalse);

      // 阶梯式：每多一个字段相等比较就多执行一行
      expect(
        const InsightsModelBreakdown() ==
            const InsightsModelBreakdown(model: 'm'),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(model: 'm') ==
            const InsightsModelBreakdown(model: 'm', sessions: 1),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(model: 'm', sessions: 1) ==
            const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
            ),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
            ) ==
            const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
            ),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
            ) ==
            const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
            ),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
            ) ==
            const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
            ),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
            ) ==
            const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
              cacheHitPercent: 6.0,
            ),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
              cacheHitPercent: 6.0,
            ) ==
            const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
              cacheHitPercent: 6.0,
              sessionShare: 7,
            ),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
              cacheHitPercent: 6.0,
              sessionShare: 7,
            ) ==
            const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
              cacheHitPercent: 6.0,
              sessionShare: 7,
              tokenShare: 8,
            ),
        isFalse,
      );
      expect(
        const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
              cacheHitPercent: 6.0,
              sessionShare: 7,
              tokenShare: 8,
            ) ==
            const InsightsModelBreakdown(
              model: 'm',
              sessions: 1,
              inputTokens: 2,
              outputTokens: 3,
              totalTokens: 4,
              cost: 5.0,
              cacheHitPercent: 6.0,
              sessionShare: 7,
              tokenShare: 8,
              costShare: 9,
            ),
        isFalse,
      );
    });

    test('toString', () {
      expect(
        const InsightsModelBreakdown(model: 'm').toString(),
        'InsightsModelBreakdown(model: m)',
      );
    });
  });

  group('InsightsDailyToken', () {
    test('fromJson 全字段 + snake/camel 回退 + 空容错', () {
      final d = InsightsDailyToken.fromJson({
        'date': '2026-09-15',
        'input_tokens': 10,
        'output_tokens': 20,
        'sessions': 3,
        'cost': 1.5,
      });
      expect(d.date, '2026-09-15');
      expect(d.inputTokens, 10);
      expect(d.outputTokens, 20);
      expect(d.sessions, 3);
      expect(d.cost, 1.5);

      final camel = InsightsDailyToken.fromJson({
        'inputTokens': 1,
        'outputTokens': 2,
      });
      expect(camel.inputTokens, 1);
      expect(camel.outputTokens, 2);

      final empty = InsightsDailyToken.fromJson({});
      expect(empty.date, isNull);
      expect(empty.inputTokens, isNull);
      expect(empty.outputTokens, isNull);
      expect(empty.sessions, isNull);
      expect(empty.cost, isNull);
    });

    test('totalTokens：null 视为 0', () {
      expect(
        const InsightsDailyToken(inputTokens: 10, outputTokens: 20).totalTokens,
        30,
      );
      expect(const InsightsDailyToken(inputTokens: 10).totalTokens, 10);
      expect(const InsightsDailyToken(outputTokens: 20).totalTokens, 20);
      expect(const InsightsDailyToken().totalTokens, 0);
    });

    test('== / hashCode / toString', () {
      const a = InsightsDailyToken(
        date: 'd',
        inputTokens: 1,
        outputTokens: 2,
        sessions: 3,
        cost: 4.0,
      );
      const b = InsightsDailyToken(
        date: 'd',
        inputTokens: 1,
        outputTokens: 2,
        sessions: 3,
        cost: 4.0,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == Object(), isFalse);
      expect(a == const InsightsDailyToken(date: 'x'), isFalse);
      expect(
        const InsightsDailyToken() ==
            const InsightsDailyToken(date: 'd'),
        isFalse,
      );
      expect(
        const InsightsDailyToken(date: 'd') ==
            const InsightsDailyToken(date: 'd', inputTokens: 1),
        isFalse,
      );
      expect(
        const InsightsDailyToken(date: 'd', inputTokens: 1) ==
            const InsightsDailyToken(
              date: 'd',
              inputTokens: 1,
              outputTokens: 2,
            ),
        isFalse,
      );
      expect(
        const InsightsDailyToken(
              date: 'd',
              inputTokens: 1,
              outputTokens: 2,
            ) ==
            const InsightsDailyToken(
              date: 'd',
              inputTokens: 1,
              outputTokens: 2,
              sessions: 3,
            ),
        isFalse,
      );
      expect(
        const InsightsDailyToken(
              date: 'd',
              inputTokens: 1,
              outputTokens: 2,
              sessions: 3,
            ) ==
            const InsightsDailyToken(
              date: 'd',
              inputTokens: 1,
              outputTokens: 2,
              sessions: 3,
              cost: 4.0,
            ),
        isFalse,
      );
      expect(
        const InsightsDailyToken(date: 'd').toString(),
        'InsightsDailyToken(date: d)',
      );
    });
  });

  group('InsightsActivityByDay / ByHour', () {
    test('ByDay：fromJson / == / hashCode / toString', () {
      final a = InsightsActivityByDay.fromJson({
        'day': 'Mon',
        'sessions': 4,
      });
      expect(a.day, 'Mon');
      expect(a.sessions, 4);

      final empty = InsightsActivityByDay.fromJson({});
      expect(empty.day, isNull);
      expect(empty.sessions, isNull);

      const x = InsightsActivityByDay(day: 'Mon', sessions: 4);
      const y = InsightsActivityByDay(day: 'Mon', sessions: 4);
      expect(x, equals(y));
      expect(x.hashCode, y.hashCode);
      expect(x == Object(), isFalse);
      expect(x == const InsightsActivityByDay(day: 'Tue', sessions: 4), isFalse);
      expect(const InsightsActivityByDay() == const InsightsActivityByDay(day: 'a'), isFalse);
      expect(
        const InsightsActivityByDay(day: 'a') ==
            const InsightsActivityByDay(day: 'a', sessions: 1),
        isFalse,
      );
      expect(
        const InsightsActivityByDay(day: 'Mon', sessions: 4).toString(),
        'InsightsActivityByDay(day: Mon)',
      );
    });

    test('ByHour：fromJson / == / hashCode / toString', () {
      final a = InsightsActivityByHour.fromJson({'hour': 9, 'sessions': 2});
      expect(a.hour, 9);
      expect(a.sessions, 2);

      final empty = InsightsActivityByHour.fromJson({});
      expect(empty.hour, isNull);
      expect(empty.sessions, isNull);

      const x = InsightsActivityByHour(hour: 9, sessions: 2);
      const y = InsightsActivityByHour(hour: 9, sessions: 2);
      expect(x, equals(y));
      expect(x.hashCode, y.hashCode);
      expect(x == Object(), isFalse);
      expect(x == const InsightsActivityByHour(hour: 3, sessions: 2), isFalse);
      expect(const InsightsActivityByHour() == const InsightsActivityByHour(hour: 1), isFalse);
      expect(
        const InsightsActivityByHour(hour: 1) ==
            const InsightsActivityByHour(hour: 1, sessions: 2),
        isFalse,
      );
      expect(
        const InsightsActivityByHour(hour: 9, sessions: 2).toString(),
        'InsightsActivityByHour(hour: 9)',
      );
    });
  });
}
