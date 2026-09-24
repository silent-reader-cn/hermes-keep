import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// #159：会话列表分组方式（时间 / 工作区）—— 时间分组从 #146 之前恢复，
// 并新增「用户显式选择 + 按屏宽兜底」。
// ---------------------------------------------------------------------------

SessionSummary _s(
  String id,
  String title, {
  bool pinned = false,
  String? workspace,
  DateTime? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    workspace: workspace,
    lastMessageAt: at == null ? null : at.millisecondsSinceEpoch / 1000,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  final now = DateTime(2026, 9, 24, 12);

  group('buildTimeSessionSections（时间分组）', () {
    test('置顶 / 今天 / 昨天 / 更早 四组齐备且各自归位', () {
      final sections = buildTimeSessionSections([
        _s('p', '置顶的', pinned: true, at: now),
        _s('t', '今天的', at: now.subtract(const Duration(hours: 2))),
        _s('y', '昨天的', at: now.subtract(const Duration(days: 1))),
        _s('e', '早先的', at: now.subtract(const Duration(days: 30))),
      ], now: now);
      expect(sections.map((s) => s.title).toList(), ['置顶', '今天', '昨天', '更早']);
      expect(sections[0].sessions.single.title, '置顶的');
      expect(sections[1].sessions.single.title, '今天的');
      expect(sections[2].sessions.single.title, '昨天的');
      expect(sections[3].sessions.single.title, '早先的');
    });

    test('空组剔除（只有今天时只出一组）', () {
      final sections = buildTimeSessionSections([
        _s('t', '今天的', at: now),
      ], now: now);
      expect(sections.length, 1);
      expect(sections.single.title, '今天');
    });

    test('时间戳缺失归「更早」', () {
      final sections = buildTimeSessionSections([_s('x', '无时间')], now: now);
      expect(sections.single.title, '更早');
    });

    test('跨天边界：昨天 23:59 与今天 00:01 分属两组', () {
      final sections = buildTimeSessionSections([
        _s('a', '今天凌晨', at: DateTime(2026, 9, 24, 0, 1)),
        _s('b', '昨晚', at: DateTime(2026, 9, 23, 23, 59)),
      ], now: now);
      final byTitle = {for (final s in sections) s.title: s};
      expect(byTitle['今天']!.sessions.single.title, '今天凌晨');
      expect(byTitle['昨天']!.sessions.single.title, '昨晚');
    });

    test('组内按时间倒序', () {
      final sections = buildTimeSessionSections([
        _s('old', '更早的今天', at: now.subtract(const Duration(hours: 5))),
        _s('new', '较新的今天', at: now.subtract(const Duration(minutes: 5))),
      ], now: now);
      expect(sections.single.sessions.map((s) => s.title).toList(), [
        '较新的今天',
        '更早的今天',
      ]);
    });
  });

  group('buildSessionSections 按模式分流', () {
    test('mode=time 走时间分组、mode=workspace 走工作区分组', () {
      final sessions = [
        _s('a', 'A', workspace: '/home/u/proj-a', at: now),
        _s('b', 'B', at: now),
      ];
      final byTime = buildSessionSections(
        sessions,
        now: now,
        mode: SessionGroupingMode.time,
      );
      final byWorkspace = buildSessionSections(sessions, now: now);

      expect(byTime.map((s) => s.title), contains('今天'));
      expect(byTime.map((s) => s.title), isNot(contains('proj-a')));
      // 默认（不传 mode）= 工作区分组，保持 #146 起的既有行为
      expect(byWorkspace.map((s) => s.title), contains('proj-a'));
      expect(byWorkspace.map((s) => s.title), contains('其他'));
    });
  });

  group('sessionGroupingModeProvider（显式选择 + 持久化）', () {
    test('初始为 null（未显式设置 → 由 UI 按屏宽兜底）', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // 等 _load 完成
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionGroupingModeProvider), isNull);
    });

    test('setMode 后生效并落盘；clearMode 回到自动', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(sessionGroupingModeProvider.notifier);

      await notifier.setMode(SessionGroupingMode.time);
      expect(c.read(sessionGroupingModeProvider), SessionGroupingMode.time);

      await notifier.clearMode();
      expect(c.read(sessionGroupingModeProvider), isNull);
    });

    test('ensureDefault 只在未显式设置时写默认', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(sessionGroupingModeProvider.notifier);

      await notifier.ensureDefault(SessionGroupingMode.workspace);
      expect(
        c.read(sessionGroupingModeProvider),
        SessionGroupingMode.workspace,
      );

      // 已有显式值时不被覆盖
      await notifier.ensureDefault(SessionGroupingMode.time);
      expect(
        c.read(sessionGroupingModeProvider),
        SessionGroupingMode.workspace,
      );
    });
  });

  group('屏宽兜底 provider', () {
    test('默认是时间（窄屏形态），UI 可改成工作区', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(sessionGroupingModeFallbackProvider),
        SessionGroupingMode.time,
      );
      c
          .read(sessionGroupingModeFallbackProvider.notifier)
          .setMode(SessionGroupingMode.workspace);
      expect(
        c.read(sessionGroupingModeFallbackProvider),
        SessionGroupingMode.workspace,
      );
    });

    test('显式设置优先于兜底值', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c
          .read(sessionGroupingModeProvider.notifier)
          .setMode(SessionGroupingMode.time);
      c
          .read(sessionGroupingModeFallbackProvider.notifier)
          .setMode(SessionGroupingMode.workspace);

      final explicit = c.read(sessionGroupingModeProvider);
      final fallback = c.read(sessionGroupingModeFallbackProvider);
      expect(explicit ?? fallback, SessionGroupingMode.time);
    });
  });
}
