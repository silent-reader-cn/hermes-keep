// 守卫：工作区分组的**组间顺序确定性**（主人 2026-10-06 反馈）。
//
// 缺陷本体：`buildSessionSections` 曾按组内最近活动时间倒序
// （`b.latestActivity.compareTo(a.latestActivity)`）—— 于是在任意会话里发一条
// 消息，它所属的工作区组立刻跳到最上方，整组会话随之位移。用户视角即
// 「类别顺序乱动 + 类别里的会话跟着一起动」。
//
// 本文件从纯函数层钉住新契约：
//   置顶 恒最前 → 能匹配 workspaceRoots 的组按根目录**声明顺序** →
//   其余组按组标题的稳定比较 → 其他 恒最后；
// 并显式钉住「latestActivity 互换 ⇒ 组顺序一动不动」（RED 判据）。

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(
  String id, {
  String? workspace,
  bool pinned = false,
  required DateTime at,
}) {
  return SessionSummary(
    sessionId: id,
    title: id,
    workspace: workspace,
    pinned: pinned,
    lastMessageAt: _sec(at),
  );
}

List<String> _titles(List<SessionListSection> sections) =>
    sections.map((s) => s.title).toList();

void main() {
  final now = DateTime(2026, 10, 6, 12);

  group('工作区组顺序确定性（不随最近活动变化）', () {
    test('A/B 两工作区的 latestActivity 互换后，组顺序完全不变', () {
      // 第一轮：alpha 活动最新
      final round1 = buildSessionSections([
        _session('a1', workspace: '/ws/alpha', at: now),
        _session(
          'b1',
          workspace: '/ws/beta',
          at: now.subtract(const Duration(hours: 5)),
        ),
      ], now: now);
      // 第二轮：同一批会话，只有「谁最近活动」互换（= 在 beta 里发了一条消息）
      final round2 = buildSessionSections([
        _session(
          'a1',
          workspace: '/ws/alpha',
          at: now.subtract(const Duration(hours: 5)),
        ),
        _session('b1', workspace: '/ws/beta', at: now),
      ], now: now);

      expect(_titles(round1), ['alpha', 'beta'], reason: '未注册工作区按标题稳定排序');
      expect(
        _titles(round2),
        _titles(round1),
        reason: '发消息只改活动时间 —— 工作区组顺序必须一动不动',
      );
    });

    test('置顶恒最前、其他恒最后，且都不随活动时间变化', () {
      final pinnedOld = _session(
        'p1',
        workspace: '/ws/alpha',
        pinned: true,
        at: now.subtract(const Duration(days: 3)),
      );
      final noWs = _session('n1', at: now.subtract(const Duration(hours: 9)));
      final zulu = _session('z1', workspace: '/ws/zulu', at: now);

      final sections = buildSessionSections([noWs, zulu, pinnedOld], now: now);

      expect(_titles(sections), ['置顶', 'zulu', '其他']);
    });

    test('已注册工作区按 workspaceRoots 的声明顺序（而非活动时间倒序）', () {
      const roots = [
        WorkspaceRoot(path: '/ws/zulu', name: 'Zulu'),
        WorkspaceRoot(path: '/ws/alpha', name: 'Alpha'),
        WorkspaceRoot(path: '/ws/mike', name: 'Mike'),
      ];
      // 活动时间刻意与声明顺序相反：alpha 最新、zulu 最旧。
      final sections = buildSessionSections(
        [
          _session('a1', workspace: '/ws/alpha', at: now),
          _session(
            'm1',
            workspace: '/ws/mike',
            at: now.subtract(const Duration(hours: 2)),
          ),
          _session(
            'z1',
            workspace: '/ws/zulu',
            at: now.subtract(const Duration(hours: 4)),
          ),
        ],
        workspaceRoots: roots,
        now: now,
      );

      expect(_titles(sections), ['Zulu', 'Alpha', 'Mike']);
    });

    test('未注册的任意目录组排在已注册工作区之后，且互相按标题稳定排序', () {
      const roots = [WorkspaceRoot(path: '/ws/registered', name: 'Registered')];
      final sections = buildSessionSections(
        [
          _session('x1', workspace: '/tmp/zzz_project', at: now),
          _session(
            'x2',
            workspace: '/tmp/aaa_project',
            at: now.subtract(const Duration(hours: 3)),
          ),
          _session(
            'r1',
            workspace: '/ws/registered',
            at: now.subtract(const Duration(hours: 6)),
          ),
        ],
        workspaceRoots: roots,
        now: now,
      );

      expect(_titles(sections), ['Registered', 'aaa_project', 'zzz_project']);
    });

    test('组内会话仍按时间倒序（本次只改组间顺序）', () {
      final sections = buildSessionSections([
        _session(
          'old',
          workspace: '/ws/alpha',
          at: now.subtract(const Duration(hours: 3)),
        ),
        _session('new', workspace: '/ws/alpha', at: now),
        _session(
          'mid',
          workspace: '/ws/alpha',
          at: now.subtract(const Duration(hours: 1)),
        ),
      ], now: now);

      expect(sections.single.sessions.map((s) => s.sessionId).toList(), [
        'new',
        'mid',
        'old',
      ]);
    });

    test('同名不同路径的组：按路径兜底，保证全序与可重复（同一输入同一输出）', () {
      final input = [
        _session('b1', workspace: '/ws/b/app', at: now),
        _session(
          'a1',
          workspace: '/ws/a/app',
          at: now.subtract(const Duration(hours: 1)),
        ),
      ];
      final first = buildSessionSections(input, now: now);
      final second = buildSessionSections(input.reversed.toList(), now: now);

      expect(_titles(first), ['app', 'app']);
      expect(
        first.map((s) => s.workspacePath).toList(),
        second.map((s) => s.workspacePath).toList(),
        reason: '同一输入（含乱序输入）必须产出同一顺序',
      );
      expect(first.map((s) => s.workspacePath).toList(), [
        '/ws/a/app',
        '/ws/b/app',
      ]);
    });
  });

  group('compareSectionTitles（稳定比较器）', () {
    test('大小写不敏感，且完全同键时用原始串兜底（全序）', () {
      expect(compareSectionTitles('alpha', 'Beta'), lessThan(0));
      expect(compareSectionTitles('Alpha', 'beta'), lessThan(0));
      expect(compareSectionTitles('alpha', 'ALPHA'), greaterThan(0));
      expect(compareSectionTitles('alpha', 'alpha'), 0);
    });

    test('同一组输入反复比较结果一致（可作为 sort 比较器：传递、稳定）', () {
      final titles = ['hermes-ui', 'etl', 'Zulu', 'alpha', '项目 A', 'beta'];
      final sortedOnce = [...titles]..sort(compareSectionTitles);
      final sortedTwice = [...titles.reversed]..sort(compareSectionTitles);
      expect(sortedOnce, sortedTwice);
      expect(sortedOnce.first, 'alpha');
    });
  });
}
