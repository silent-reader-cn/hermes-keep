import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 生产接线回归（真实缺陷，#apply-fix）：
///
/// 生产入口是 `DiagnosticsService.instance.init(database: _productionDatabase)`
/// （lib/main.dart）—— 单例在**构造期没有数据库**，库只能由 `init` 在运行期接上。
/// 修复前 `_database` 是 `final`，`init` 的入参只用于「读回缓冲」而不落字段，
/// 于是 `_database` 恒为 null：落库（[DiagnosticsService.flushNow]）与导出
/// （[DiagnosticsService.exportAllLogs]）全部静默退化成内存缓冲 ——
/// 导出只能看到最近约 10 分钟的密集日志，事后追溯现场时触发时刻的日志往往已被
/// 环形缓冲挤掉（这正是定位「界面静默冻结」时踩到的坑）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsEnabled() async {
    SharedPreferences.setMockInitialValues({'diagnostics_enabled': true});
    return SharedPreferences.getInstance();
  }

  group('DiagnosticsService 数据库接线（生产路径）', () {
    test('构造期无库 + init(database:) ⇒ 落库真的生效', () async {
      final prefs = await prefsEnabled();
      final db = AppDatabase.memory();
      addTearDown(db.close);

      // 关键：复刻 DiagnosticsService.instance —— 构造期不传库。
      final service = DiagnosticsService(customPrefs: prefs);
      await service.init(prefs: prefs, database: db);
      expect(service.enabled, isTrue, reason: '前置：诊断开关须为开，否则 log 直接丢弃');

      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'wiring',
        message: 'W1',
      );
      await service.flushNow();

      expect(await db.diagnosticsLogs.count().getSingle(), 1);
    });

    test('导出以库为源：内存缓冲清空后仍可导出，且按时间正序', () async {
      final prefs = await prefsEnabled();
      final db = AppDatabase.memory();
      addTearDown(db.close);

      final service = DiagnosticsService(customPrefs: prefs);
      await service.init(prefs: prefs, database: db);

      final base = DateTime.now().subtract(const Duration(minutes: 1));
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 't',
        message: 'A',
        timestamp: base,
      );
      service.log(
        level: DiagnosticsLogLevel.warn,
        tag: 't',
        message: 'B',
        timestamp: base.add(const Duration(seconds: 1)),
      );
      await service.flushNow();

      // 模拟「重启后打开导出」：内存缓冲里没有这些行。
      service.clearMemoryOnly();
      expect(service.logs, isEmpty);

      final exported = await service.exportAllLogs();
      expect(exported.map((e) => e.message).toList(), ['A', 'B']);
      expect(exported.first.level, DiagnosticsLogLevel.info);
      expect(exported.last.level, DiagnosticsLogLevel.warn);
    });

    test('数据库行数预算与内存上限解耦（maxDatabaseRows > maxCapacity）', () async {
      final prefs = await prefsEnabled();
      final db = AppDatabase.memory();
      addTearDown(db.close);

      final service = DiagnosticsService(
        customPrefs: prefs,
        maxCapacity: 2,
        maxDatabaseRows: 3,
      );
      await service.init(prefs: prefs, database: db);

      final base = DateTime.now().subtract(const Duration(seconds: 10));
      for (var i = 0; i < 5; i++) {
        service.log(
          level: DiagnosticsLogLevel.debug,
          tag: 'cap',
          message: 'M-$i',
          timestamp: base.add(Duration(seconds: i)),
        );
      }
      await service.flushNow();

      // 内存：按 maxCapacity 裁（最老优先）。
      expect(service.logs.map((e) => e.message).toList(), ['M-3', 'M-4']);
      // 库：按 maxDatabaseRows 裁 —— 与内存上限解耦。
      final rows =
          await (db.select(db.diagnosticsLogs)
                ..orderBy([
                  (t) => OrderingTerm(
                    expression: t.timestamp,
                    mode: OrderingMode.asc,
                  ),
                ]))
              .get();
      expect(rows.map((r) => r.message).toList(), ['M-2', 'M-3', 'M-4']);
    });

    test('导出头给出覆盖窗口（Earliest / Latest Entry）', () {
      final base = DateTime(2026, 10, 6, 14, 6, 3);
      final text = DiagnosticsService.formatExportText([
        DiagnosticsLogEntry(
          id: 'a',
          timestamp: base,
          level: DiagnosticsLogLevel.info,
          tag: 't',
          message: 'A',
        ),
        DiagnosticsLogEntry(
          id: 'b',
          timestamp: base.add(const Duration(minutes: 9, seconds: 31)),
          level: DiagnosticsLogLevel.info,
          tag: 't',
          message: 'B',
        ),
      ]);

      expect(text, contains('Total Entries: 2'));
      // 断言用同一格式化器，避免把 Dart 默认 toString 的形态钉死。
      expect(text, contains('Earliest Entry: ${formatLogTimestamp(base)}'));
      expect(
        text,
        contains(
          'Latest Entry: '
          '${formatLogTimestamp(base.add(const Duration(minutes: 9, seconds: 31)))}',
        ),
      );
    });
  });
}
