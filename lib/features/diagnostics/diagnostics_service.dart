import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/app_database.dart';
import '../../core/utils/uuid.dart';
import 'diagnostics_models.dart';

/// 诊断模式持久化键（对齐 todo.md #9 规格）。
const String kDiagnosticsEnabledKey = 'diagnostics_enabled';

/// 旧版 SharedPreferences 诊断日志持久化键（#33 迁移后仅用于一次性清理）。
const String kDiagnosticsLogsStorageKey = 'diagnostics_logs_v1';

/// 诊断日志内存环形缓冲默认最大容量（#33：1500 → 10000）。
const int kDiagnosticsMaxCapacity = 10000;

/// 诊断日志「数据库」行数上限（#33 修订）。
///
/// 内存环形缓冲仍按 [kDiagnosticsMaxCapacity] 裁（UI 热路径轻量），但数据库预算
/// 放宽到 5 万行：此前库也沿用 10000 上限，密集 SSE 日志（≈10000 条/10 分钟）
/// 会把更早的行挤掉 —— 事后追溯现场（例如界面静默冻结）时，触发时刻的日志往往
/// 已不在导出里。30 天保留期不变；开启诊断时最多占用约 10–20MB。
const int kDiagnosticsDatabaseMaxRows = 50000;

/// 诊断服务（内存环形缓冲热路径 + drift 持久化 + 脱敏纪律）。
///
/// 存储架构（#33 方案 A）：
/// - **内存环形缓冲**（[maxCapacity] = 10000）：仅做日志流推送/页面查询热
///   路径，重启即失；
/// - **drift 持久化**（`AppDatabase.diagnostics_logs` 表，schemaVersion 3）：
///   唯一持久数据源，写入时经 500ms 防抖批量落库，按 timestamp 执行
///   30 天保留清理 + 最老优先容量淘汰；
/// - 导出走 drift 全量查询，不受内存缓冲截断影响。
class DiagnosticsService {
  DiagnosticsService({
    SharedPreferences? customPrefs,
    this._database,
    this.maxCapacity = kDiagnosticsMaxCapacity,
    this.maxDatabaseRows = kDiagnosticsDatabaseMaxRows,
  }) : _prefs = customPrefs;

  /// 单例实例。
  static final DiagnosticsService instance = DiagnosticsService();

  final SharedPreferences? _prefs;

  /// drift 数据库（复用 `appDatabaseProvider` 单例，避免双库）。
  ///
  /// 非 final：构造器未传时由 [init] 的 `database:` 入参在运行期接上
  /// （此前是 final，而 init 的入参只用于读回缓冲、不落字段 ⇒ 生产环境里恒为
  /// null，落库与导出都静默退化成「仅内存缓冲」）。
  AppDatabase? _database;

  /// 内存环形缓冲最大容量（#33：10000 条）。
  final int maxCapacity;

  /// 数据库行数预算（见 [kDiagnosticsDatabaseMaxRows]；与内存上限解耦）。
  final int maxDatabaseRows;

  /// 30 天持久化超期保留阈值（#33：7 天 → 30 天）。
  static const Duration retentionDuration = Duration(days: 30);

  bool _initialized = false;
  bool _enabled = false;
  final List<DiagnosticsLogEntry> _buffer = [];

  /// 待落库的增量条目（500ms 防抖批量写入）。
  final List<DiagnosticsLogEntry> _pending = [];

  final StreamController<List<DiagnosticsLogEntry>> _logStreamController =
      StreamController<List<DiagnosticsLogEntry>>.broadcast();

  Timer? _saveDebounceTimer;

  /// 是否启用了诊断日志采集。
  bool get enabled => _enabled;

  /// 诊断更新流。
  Stream<List<DiagnosticsLogEntry>> get logsStream =>
      _logStreamController.stream;

  /// 获取当前日志列表快照（只读副本，最新在后）。
  List<DiagnosticsLogEntry> get logs => List.unmodifiable(_buffer);

  /// 初始化服务：加载开关状态，并从 drift 载入 30 天保留期内日志。
  Future<void> init({SharedPreferences? prefs, AppDatabase? database}) async {
    if (_initialized) return;
    try {
      final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
      _enabled = p.getBool(kDiagnosticsEnabledKey) ?? false;

      // 存量 SharedPreferences 旧日志一次性丢弃：清除遗留键，避免 XML 膨胀
      // 与旧数据混入新库（#33 规格 6）。
      await p.remove(kDiagnosticsLogsStorageKey);

      final db = database ?? _database;
      // #apply-fix：补上字段赋值。此前 `_database` 是 final、只有构造器能赋值，
      // `init(database:)` 的入参仅用于「读回缓冲」，没落到字段上 —— 而生产入口
      // （main.dart）走的正是 `DiagnosticsService.instance.init(database: ...)`，
      // 于是 _database 恒 null：落库与导出静默退化为内存缓冲（导出只能看到最近
      // 约 10 分钟的密集日志，事后追溯现场时关键行往往已被挤掉）。
      _database = db;
      if (db != null) {
        final cutoff = DateTime.now()
            .subtract(retentionDuration)
            .millisecondsSinceEpoch;
        final rows =
            await (db.select(db.diagnosticsLogs)
                  ..where((t) => t.timestamp.isBiggerOrEqualValue(cutoff))
                  ..orderBy([
                    (t) => drift.OrderingTerm(
                      expression: t.timestamp,
                      mode: drift.OrderingMode.asc,
                    ),
                  ]))
                .get();
        _buffer.clear();
        for (final row in rows) {
          _buffer.add(_rowToEntry(row));
        }
        _pruneBuffer();
      }
    } catch (error) {
      debugPrint('DiagnosticsService.init failed: $error');
    } finally {
      _initialized = true;
      _logStreamController.add(List.unmodifiable(_buffer));
    }
  }

  /// 设置并持久化开关。
  Future<void> setEnabled(bool value, {SharedPreferences? prefs}) async {
    _enabled = value;
    try {
      final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
      await p.setBool(kDiagnosticsEnabledKey, value);
    } catch (_) {}
  }

  /// 记录一条诊断日志（仅在 [enabled] == true 时采集）。
  void log({
    required DiagnosticsLogLevel level,
    required String tag,
    required String message,
    Map<String, Object?>? details,
    int? durationMs,
    String? errorKind,
    DateTime? timestamp,
  }) {
    if (!_enabled) return;

    // 脱敏详情数据
    final sanitizedDetails = details != null
        ? sanitizeDataPayload(details) as Map<String, Object?>?
        : null;

    final entry = DiagnosticsLogEntry(
      id: uuidV4(),
      timestamp: timestamp ?? DateTime.now(),
      level: level,
      tag: tag,
      message: truncateText(message, 1000),
      details: sanitizedDetails,
      durationMs: durationMs,
      errorKind: errorKind,
    );

    _buffer.add(entry);
    _pending.add(entry);
    _pruneBuffer();
    _logStreamController.add(List.unmodifiable(_buffer));
    _scheduleDebouncedSave();
  }

  /// 清空内存缓冲与 drift 库中的所有日志（含遗留 SharedPreferences 键）。
  Future<void> clear({SharedPreferences? prefs}) async {
    _buffer.clear();
    _pending.clear();
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _logStreamController.add(const []);
    final db = _database;
    if (db != null) {
      try {
        await (db.delete(db.diagnosticsLogs)).go();
      } catch (error) {
        debugPrint('DiagnosticsService.clear failed: $error');
      }
    }
    try {
      final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
      await p.remove(kDiagnosticsLogsStorageKey);
    } catch (_) {}
  }

  /// 导出当前 drift 库内全部日志（**按时间正序**：旧 → 新）。
  ///
  /// 与 [logs]（内存缓冲快照）不同，导出以 drift 全量查询为源，不受
  /// 内存缓冲淘汰/未落库条目影响（#33 规格 4）。
  ///
  /// 顺序取**正序**：无库时 [logs] 回退本身就是正序，导出文件保持一致，人眼可
  /// 按时间线阅读、并可与服务端 run journal / 服务端日志逐条对齐。
  Future<List<DiagnosticsLogEntry>> exportAllLogs() async {
    final db = _database;
    if (db == null) return logs;
    try {
      final rows =
          await (db.select(db.diagnosticsLogs)..orderBy([
                (t) => drift.OrderingTerm(
                  expression: t.timestamp,
                  mode: drift.OrderingMode.asc,
                ),
              ]))
              .get();
      return rows.map(_rowToEntry).toList();
    } catch (error) {
      debugPrint('DiagnosticsService.exportAllLogs failed: $error');
      return logs;
    }
  }

  /// 内存环形缓冲容量淘汰（最老优先）。
  void _pruneBuffer() {
    if (_buffer.length > maxCapacity) {
      final overflow = _buffer.length - maxCapacity;
      _buffer.removeRange(0, overflow);
    }
  }

  void _scheduleDebouncedSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveDebounceTimer = null;
      unawaited(_flushToDatabase());
    });
  }

  /// 批量落库 + 清理：先插入增量条目，再执行 30 天保留清理与容量淘汰。
  Future<void> _flushToDatabase() async {
    final db = _database;
    if (db == null || _pending.isEmpty) return;
    final batch = List<DiagnosticsLogEntry>.from(_pending);
    _pending.clear();
    try {
      await db.batch((b) {
        b.insertAll(db.diagnosticsLogs, [
          for (final entry in batch) _entryToCompanion(entry),
        ]);
      });
      await _pruneDatabase(db);
    } catch (error) {
      // 落库失败：条目回滚到待写队列，避免静默丢失。
      _pending.insertAll(0, batch);
      debugPrint('DiagnosticsService._flushToDatabase failed: $error');
    }
  }

  /// drift 侧清理：删除超期（>30 天）行，并淘汰超出 [maxCapacity] 的最老行。
  Future<void> _pruneDatabase(AppDatabase db) async {
    final cutoff = DateTime.now()
        .subtract(retentionDuration)
        .millisecondsSinceEpoch;
    await (db.delete(
      db.diagnosticsLogs,
    )..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();

    final count = await db.diagnosticsLogs.count().getSingle();
    if (count > maxDatabaseRows) {
      final overflow = count - maxDatabaseRows;
      final ids =
          (await (db.selectOnly(db.diagnosticsLogs)
                    ..addColumns([db.diagnosticsLogs.id])
                    ..orderBy([
                      drift.OrderingTerm(
                        expression: db.diagnosticsLogs.timestamp,
                        mode: drift.OrderingMode.asc,
                      ),
                    ])
                    ..limit(overflow))
                  .get())
              .map((row) => row.read(db.diagnosticsLogs.id))
              .whereType<String>()
              .toList();
      if (ids.isNotEmpty) {
        await (db.delete(
          db.diagnosticsLogs,
        )..where((t) => t.id.isIn(ids))).go();
      }
    }
  }

  /// 生成导出的文件名 `Diagnostics_YYYYMMDD_HHmmss.txt`。
  static String generateExportFileName([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return 'Diagnostics_$y$m${d}_$h$min$s.txt';
  }

  /// 生成完整大文本导出内容（UTF-8 纯文本）。
  static String formatExportText(
    List<DiagnosticsLogEntry> entries, [
    DateTime? now,
  ]) {
    final dt = now ?? DateTime.now();
    final sb = StringBuffer();
    sb.writeln('=' * 60);
    sb.writeln('Hermes Diagnostics Log Export');
    sb.writeln('Exported At: ${formatLogTimestamp(dt)}');
    sb.writeln('Total Entries: ${entries.length}');
    if (entries.isNotEmpty) {
      // 覆盖窗口对事后追溯至关重要：与服务端日志按时间对齐时，先要知道这份
      // 导出的起止（内存回退只有最近约 10 分钟；以库为源则可达 30 天）。
      sb.writeln('Earliest Entry: ${formatLogTimestamp(entries.first.timestamp)}');
      sb.writeln('Latest Entry: ${formatLogTimestamp(entries.last.timestamp)}');
    }
    sb.writeln('=' * 60);
    sb.writeln();

    for (var i = 0; i < entries.length; i++) {
      sb.writeln(entries[i].toExportString());
      if (i < entries.length - 1) {
        sb.writeln('-' * 60);
      }
    }
    return sb.toString();
  }

  /// drift 行 → 领域模型。
  DiagnosticsLogEntry _rowToEntry(DiagnosticsLog row) {
    return DiagnosticsLogEntry(
      id: row.id,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row.timestamp),
      level: DiagnosticsLogLevel.fromString(row.level),
      tag: row.tag,
      message: row.message,
      details: row.details == null ? null : _decodeDetails(row.details!),
      durationMs: row.durationMs,
      errorKind: row.errorKind,
    );
  }

  /// 领域模型 → drift 插入 Companion（details 序列化为 JSON 文本）。
  DiagnosticsLogsCompanion _entryToCompanion(DiagnosticsLogEntry entry) {
    return DiagnosticsLogsCompanion.insert(
      id: entry.id,
      timestamp: entry.timestamp.millisecondsSinceEpoch,
      level: entry.level.name,
      tag: entry.tag,
      message: entry.message,
      details: drift.Value(
        entry.details == null ? null : jsonEncode(entry.details),
      ),
      durationMs: drift.Value(entry.durationMs),
      errorKind: drift.Value(entry.errorKind),
    );
  }

  /// 容错反序列化 details JSON 文本。
  Map<String, Object?>? _decodeDetails(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  void clearMemoryOnly() {
    _buffer.clear();
    _pending.clear();
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _logStreamController.add(const []);
  }

  /// 立即冲刷待落库条目（测试用，等价于等待 500ms 防抖触发）。
  @visibleForTesting
  Future<void> flushNow() => _flushToDatabase();
}
