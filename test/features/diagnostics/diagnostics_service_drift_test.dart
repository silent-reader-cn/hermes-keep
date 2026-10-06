import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #33 验收 1：drift 迁移专项单测。
///
/// 覆盖：写入 >1500 条可见不丢、上限 10000 最老优先淘汰、
/// 30 天保留过滤、重启不丢（内存态 → 库 → 新实例恢复）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiagnosticsService drift 持久化', () {
    test('默认内存上限为 10000 条（#33 规格 2）', () {
      final service = DiagnosticsService();
      expect(service.maxCapacity, 10000);
      expect(DiagnosticsService.retentionDuration, const Duration(days: 30));
    });

    test('写入 2000 条（>1500）：内存可见且落库不丢', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final service = DiagnosticsService(customPrefs: prefs, database: db);
      await service.init(prefs: prefs, database: db);
      await service.setEnabled(true, prefs: prefs);

      for (var i = 0; i < 2000; i++) {
        service.log(
          level: DiagnosticsLogLevel.info,
          tag: 'bulk',
          message: 'M-${i.toString().padLeft(5, '0')}',
        );
      }

      // 内存缓冲：2000 条全部可见（>1500 不被截断）。
      expect(service.logs.length, 2000);
      expect(service.logs.first.message, 'M-00000');
      expect(service.logs.last.message, 'M-01999');

      await service.flushNow();

      // drift 库：同步 2000 条不丢。
      final count = await db.diagnosticsLogs.count().getSingle();
      expect(count, 2000);
      final firstRow = await (db.select(
        db.diagnosticsLogs,
      )..where((t) => t.message.equals('M-00000'))).getSingle();
      expect(firstRow.tag, 'bulk');
      final lastRow = await (db.select(
        db.diagnosticsLogs,
      )..where((t) => t.message.equals('M-01999'))).getSingle();
      expect(lastRow.message, 'M-01999');
    });

    test('超过 10000 条：缓冲与库均按最老优先淘汰', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final service = DiagnosticsService(
        customPrefs: prefs,
        database: db,
        // 本用例只验淘汰机制：把库预算钉成与内存一致（默认已解耦为
        // kDiagnosticsDatabaseMaxRows）。
        maxDatabaseRows: 10000,
      );
      await service.init(prefs: prefs, database: db);
      await service.setEnabled(true, prefs: prefs);

      // 10005 条，时间戳递增（最老在前，均在 30 天保留期内）。
      final base = DateTime.now().subtract(const Duration(seconds: 10004));
      for (var i = 0; i < 10005; i++) {
        service.log(
          level: DiagnosticsLogLevel.debug,
          tag: 'cap',
          message: 'M-${i.toString().padLeft(5, '0')}',
          timestamp: base.add(Duration(seconds: i)),
        );
      }

      // 内存缓冲：10000 条，最老 5 条被淘汰。
      expect(service.logs.length, 10000);
      expect(service.logs.first.message, 'M-00005');
      expect(service.logs.last.message, 'M-10004');

      await service.flushNow();

      // drift 库：10000 条，最老 5 条同样被淘汰。
      final count = await db.diagnosticsLogs.count().getSingle();
      expect(count, 10000);
      final oldest =
          await (db.select(db.diagnosticsLogs)
                ..orderBy([
                  (t) => OrderingTerm(
                    expression: t.timestamp,
                    mode: OrderingMode.asc,
                  ),
                ])
                ..limit(1))
              .getSingle();
      expect(oldest.message, 'M-00005');
      final newest =
          await (db.select(db.diagnosticsLogs)
                ..orderBy([
                  (t) => OrderingTerm(
                    expression: t.timestamp,
                    mode: OrderingMode.desc,
                  ),
                ])
                ..limit(1))
              .getSingle();
      expect(newest.message, 'M-10004');
    });

    test('30 天保留：超期行落库时被清理，内存热路径不受影响', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final service = DiagnosticsService(customPrefs: prefs, database: db);
      await service.init(prefs: prefs, database: db);
      await service.setEnabled(true, prefs: prefs);

      final oldTimestamp = DateTime.now().subtract(const Duration(days: 40));
      service.log(
        level: DiagnosticsLogLevel.error,
        tag: 'old',
        message: 'Forty days ago',
        timestamp: oldTimestamp,
      );
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'fresh',
        message: 'Fresh entry',
      );

      await service.flushNow();

      // drift 库：仅保留 30 天内的行。
      final rows = await db.select(db.diagnosticsLogs).get();
      expect(rows.length, 1);
      expect(rows.single.message, 'Fresh entry');

      // 内存缓冲：与旧行为一致，运行期不按保留期过滤。
      expect(service.logs.length, 2);
    });

    test('重启不丢：内存态落库后，新实例从 drift 恢复', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dir = Directory.systemTemp.createTempSync('hermes_diag_');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });
      final file = File('${dir.path}${Platform.pathSeparator}diag_logs.sqlite');

      // 第一轮：写入并落库后关闭。
      final db1 = AppDatabase(NativeDatabase(file));
      final service1 = DiagnosticsService(customPrefs: prefs, database: db1);
      await service1.init(prefs: prefs, database: db1);
      await service1.setEnabled(true, prefs: prefs);
      service1.log(
        level: DiagnosticsLogLevel.info,
        tag: 'alpha',
        message: 'Alpha',
      );
      service1.log(
        level: DiagnosticsLogLevel.warn,
        tag: 'beta',
        message: 'Beta',
        errorKind: 'Timeout',
      );
      service1.log(
        level: DiagnosticsLogLevel.error,
        tag: 'gamma',
        message: 'Gamma',
        details: {'url': 'https://example.com'},
        durationMs: 42,
      );
      await service1.flushNow();
      expect(await db1.diagnosticsLogs.count().getSingle(), 3);
      await db1.close();

      // 第二轮：同一文件新开库，模拟进程重启。
      final db2 = AppDatabase(NativeDatabase(file));
      addTearDown(db2.close);
      final service2 = DiagnosticsService(customPrefs: prefs, database: db2);
      await service2.init(prefs: prefs, database: db2);

      expect(service2.enabled, true);
      expect(service2.logs.length, 3);
      expect(service2.logs.map((e) => e.message).toList(), [
        'Alpha',
        'Beta',
        'Gamma',
      ]);
      final beta = service2.logs[1];
      expect(beta.errorKind, 'Timeout');
      expect(beta.level, DiagnosticsLogLevel.warn);
      final gamma = service2.logs.last;
      expect(gamma.durationMs, 42);
      expect(gamma.details?['url'], 'https://example.com');
      expect(gamma.level, DiagnosticsLogLevel.error);
    });
  });
}
