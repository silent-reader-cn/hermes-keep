import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DiagnosticsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.memory();
    addTearDown(database.close);
    final prefs = await SharedPreferences.getInstance();
    service = DiagnosticsService(
      customPrefs: prefs,
      database: database,
      maxCapacity: 5,
      // 本用例只验「最老优先淘汰」机制本身：把库预算钉成与内存一致。
      // （库与内存的预算已解耦，默认 kDiagnosticsDatabaseMaxRows，见
      //  diagnostics_service_db_wiring_test.dart 的策略用例。）
      maxDatabaseRows: 5,
    );
    await service.init(prefs: prefs, database: database);
  });

  group('DiagnosticsService', () {
    test('default state is disabled', () {
      expect(service.enabled, false);
      expect(service.logs, isEmpty);
    });

    test('setting enabled persists in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await service.setEnabled(true, prefs: prefs);
      expect(service.enabled, true);
      expect(prefs.getBool(kDiagnosticsEnabledKey), true);

      await service.setEnabled(false, prefs: prefs);
      expect(service.enabled, false);
      expect(prefs.getBool(kDiagnosticsEnabledKey), false);
    });

    test('log does nothing when disabled', () {
      expect(service.enabled, false);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'test',
        message: 'Should not be recorded',
      );
      expect(service.logs, isEmpty);
    });

    test('log records entries and enforces ring buffer max capacity', () async {
      await service.setEnabled(true);

      for (var i = 1; i <= 7; i++) {
        service.log(
          level: DiagnosticsLogLevel.info,
          tag: 'tag-$i',
          message: 'Message $i',
        );
      }

      // Max capacity is 5, so entries 3, 4, 5, 6, 7 remain
      expect(service.logs.length, 5);
      expect(service.logs.first.message, 'Message 3');
      expect(service.logs.last.message, 'Message 7');

      // drift 库同步淘汰：落库后同样只剩 5 条（最老优先）。
      await service.flushNow();
      final dbCount = await database.diagnosticsLogs.count().getSingle();
      expect(dbCount, 5);
    });

    test('clear wipes memory buffer, drift storage and legacy key', () async {
      final prefs = await SharedPreferences.getInstance();
      await service.setEnabled(true, prefs: prefs);
      service.log(
        level: DiagnosticsLogLevel.error,
        tag: 'err',
        message: 'An error occurred',
      );
      expect(service.logs.length, 1);
      await service.flushNow();
      expect(await database.diagnosticsLogs.count().getSingle(), 1);

      await service.clear(prefs: prefs);
      expect(service.logs, isEmpty);
      expect(await database.diagnosticsLogs.count().getSingle(), 0);
      expect(prefs.getString(kDiagnosticsLogsStorageKey), isNull);
    });

    test('init loads logs from drift and prunes older than 30 days', () async {
      final now = DateTime.now();
      final freshDate = now.subtract(const Duration(days: 2));
      final oldDate = now.subtract(const Duration(days: 40));

      // 直接向 drift 库播种：一条 2 天前 + 一条 40 天前。
      await database
          .into(database.diagnosticsLogs)
          .insert(
            DiagnosticsLogsCompanion.insert(
              id: 'old-1',
              timestamp: oldDate.millisecondsSinceEpoch,
              level: DiagnosticsLogLevel.info.name,
              tag: 'old',
              message: 'Old log message',
            ),
          );
      await database
          .into(database.diagnosticsLogs)
          .insert(
            DiagnosticsLogsCompanion.insert(
              id: 'fresh-1',
              timestamp: freshDate.millisecondsSinceEpoch,
              level: DiagnosticsLogLevel.info.name,
              tag: 'fresh',
              message: 'Fresh log message',
            ),
          );

      SharedPreferences.setMockInitialValues({
        kDiagnosticsEnabledKey: true,
        kDiagnosticsLogsStorageKey: '{"legacy":"should be discarded"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final newService = DiagnosticsService(
        customPrefs: prefs,
        database: database,
      );
      await newService.init(prefs: prefs, database: database);

      expect(newService.enabled, true);
      expect(newService.logs.length, 1);
      expect(newService.logs.first.id, 'fresh-1');
      // 存量 SharedPreferences 旧日志一次性丢弃（#33 规格 6）。
      expect(prefs.getString(kDiagnosticsLogsStorageKey), isNull);
    });

    test('formatExportText generates valid formatted output', () {
      final entries = [
        DiagnosticsLogEntry(
          id: '1',
          timestamp: DateTime(2026, 8, 28, 12, 0, 0),
          level: DiagnosticsLogLevel.info,
          tag: 'dio',
          message: 'GET /api/test -> 200',
        ),
      ];

      final text = DiagnosticsService.formatExportText(
        entries,
        DateTime(2026, 8, 28, 12, 0, 0),
      );
      expect(text, contains('Hermes Diagnostics Log Export'));
      expect(text, contains('Total Entries: 1'));
      expect(text, contains('[dio] GET /api/test -> 200'));
    });

    test('generateExportFileName creates proper filename format', () {
      final name = DiagnosticsService.generateExportFileName(
        DateTime(2026, 8, 28, 14, 30, 45),
      );
      expect(name, 'Diagnostics_20260828_143045.txt');
    });
  });
}
