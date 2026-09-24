import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/settings/cron_visibility_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _buildSession(
  String id,
  String title, {
  bool pinned = false,
  DateTime? at,
  String? sessionSource,
  String? sourceTag,
  String? rawSource,
  String? sourceLabel,
  double? createdAt,
  double? updatedAt,
  String? workspace,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    workspace: workspace,
    lastMessageAt: at != null ? _sec(at) : null,
    createdAt: createdAt,
    updatedAt: updatedAt,
    sessionSource: sessionSource,
    sourceTag: sourceTag,
    rawSource: rawSource,
    sourceLabel: sourceLabel,
  );
}

/// #159：把分组方式固定为「工作区」，避免屏宽兜底影响本文件的时间语义假设。
class _WorkspaceGroupingNotifier extends SessionGroupingModeController {
  @override
  SessionGroupingMode? build() => SessionGroupingMode.workspace;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('buildSessionSections 定时融流与过滤逻辑', () {
    test('showCron = false（默认）：cron 会话被过滤，不进入任何分区', () {
      final now = DateTime(2026, 8, 20, 12);
      final cronSession = _buildSession(
        'cron_job_1',
        '定时巡检任务',
        at: now.subtract(const Duration(hours: 1)),
      );
      final todaySession = _buildSession(
        's_today',
        '普通今天会话',
        at: now.subtract(const Duration(hours: 2)),
      );

      final sections = buildSessionSections([
        cronSession,
        todaySession,
      ], now: now);

      expect(sections.map((s) => s.title).toList(), ['其他']);
      expect(sections.single.sessions.map((s) => s.sessionId).toList(), [
        's_today',
      ]);
    });

    test('showCron = false：通过 sessionSource/sourceTag/rawSource/sourceLabel 标记的 cron 会话均被过滤', () {
      final now = DateTime(2026, 8, 20, 12);
      final s1 = _buildSession(
        'c1',
        'Source=cron',
        at: now,
        sessionSource: 'cron',
      );
      final s2 = _buildSession(
        'c2',
        'SourceTag=cron',
        at: now,
        sourceTag: 'cron',
      );
      final s3 = _buildSession(
        'c3',
        'RawSource=cron',
        at: now,
        rawSource: 'cron',
      );
      final s4 = _buildSession(
        'c4',
        'SourceLabel=cron',
        at: now,
        sourceLabel: 'cron',
      );
      final normal = _buildSession('normal_1', '普通会话', at: now);

      final sections = buildSessionSections([s1, s2, s3, s4, normal], now: now);

      expect(sections.map((s) => s.title).toList(), ['其他']);
      expect(sections.single.sessions.map((s) => s.sessionId).toList(), [
        'normal_1',
      ]);
    });

    test('showCron = true：cron 会话融流进工作区分区，不再产生「定时」独立分区', () {
      final now = DateTime(2026, 8, 20, 12);
      final cron = _buildSession(
        'cron_1',
        '定时会话',
        at: now,
        workspace: '/ws/ws1',
      );
      final pinned = _buildSession(
        'p1',
        '置顶会话',
        pinned: true,
        at: now,
        workspace: '/ws/ws2',
      );
      final ws1Session = _buildSession(
        't1',
        'ws1 普通会话',
        at: now.subtract(const Duration(hours: 1)),
        workspace: '/ws/ws1',
      );
      final ws2Session = _buildSession(
        'y1',
        'ws2 会话',
        at: now.subtract(const Duration(days: 1)),
        workspace: '/ws/ws2',
      );
      final ws3Session = _buildSession(
        'e1',
        'ws3 会话',
        at: now.subtract(const Duration(days: 5)),
        workspace: '/ws/ws3',
      );

      final sections = buildSessionSections(
        [ws3Session, ws2Session, ws1Session, pinned, cron],
        showCron: true,
        now: now,
      );

      expect(sections.map((s) => s.title).toList(), [
        '置顶',
        'ws1',
        'ws2',
        'ws3',
      ]);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['p1']);
      // ws1 包含 cron 与 t1，按时间倒序
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), [
        'cron_1',
        't1',
      ]);
      expect(sections[2].sessions.map((s) => s.sessionId).toList(), ['y1']);
      expect(sections[3].sessions.map((s) => s.sessionId).toList(), ['e1']);
    });

    test('showCron = true：cron + pinned 会话仍按时间归入对应工作区，不进「置顶」分区', () {
      final now = DateTime(2026, 8, 20, 12);
      final cronPinned = _buildSession(
        'cron_pinned_1',
        '定时且置顶会话',
        pinned: true,
        at: now,
        workspace: '/ws/main',
      );
      final normalPinned = _buildSession(
        'normal_pinned_1',
        '普通置顶会话',
        pinned: true,
        at: now,
        workspace: '/ws/main',
      );

      final sections = buildSessionSections(
        [cronPinned, normalPinned],
        showCron: true,
        now: now,
      );

      expect(sections.map((s) => s.title).toList(), ['置顶', 'main']);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), [
        'normal_pinned_1',
      ]);
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), [
        'cron_pinned_1',
      ]);
    });

    test('非 cron 会话按工作区分组：置顶独立在最上方，无工作区归入「其他」', () {
      final now = DateTime(2026, 8, 16, 12);
      final pinned = _buildSession(
        'p1',
        '置顶会话',
        pinned: true,
        at: now,
        workspace: '/ws/alpha',
      );
      final alpha = _buildSession(
        'a1',
        'Alpha 会话',
        at: now.subtract(const Duration(hours: 1)),
        workspace: '/ws/alpha',
      );
      final beta = _buildSession(
        'b1',
        'Beta 会话',
        at: now.subtract(const Duration(days: 1)),
        workspace: '/ws/beta',
      );
      final other = _buildSession(
        'o1',
        '无工作区会话',
        at: now.subtract(const Duration(days: 10)),
        workspace: null,
      );

      final sections = buildSessionSections([
        other,
        beta,
        alpha,
        pinned,
      ], now: now);

      expect(sections.map((s) => s.title).toList(), [
        '置顶',
        'alpha',
        'beta',
        '其他',
      ]);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['p1']);
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['a1']);
      expect(sections[2].sessions.map((s) => s.sessionId).toList(), ['b1']);
      expect(sections[3].sessions.map((s) => s.sessionId).toList(), ['o1']);
    });

    test('全空输入 → 无分区', () {
      expect(
        buildSessionSections(const [], now: DateTime(2026, 1, 1)),
        isEmpty,
      );
    });
  });

  group('sessionListSectionsProvider 派生状态', () {
    test('普通模式默认不包含 cron 会话，开启 showCron 后融流包含', () async {
      final now = DateTime.now();
      final cron = _buildSession('cron_1', '定时会话', at: now);
      final normal = _buildSession('s1', '普通会话', at: now);
      final api = FakeSessionListApi(sessions: [cron, normal]);

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          // #159：分组方式默认按屏宽兜底（本文件的测试视口是窄屏 ⇒ 会走时间
          // 分组）。本组用例测的是工作区分组下的 cron 融流语义 ⇒ 显式指定。
          sessionGroupingModeProvider.overrideWith(
            _WorkspaceGroupingNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);

      // 默认 showCron 为 false
      var sections = container.read(sessionListSectionsProvider);
      expect(sections.map((s) => s.title).toList(), ['其他']);
      expect(sections.single.sessions.map((s) => s.sessionId).toList(), ['s1']);

      // 打开 showCron
      await container.read(cronVisibilityProvider.notifier).setShowCron(true);

      sections = container.read(sessionListSectionsProvider);
      expect(sections.map((s) => s.title).toList(), ['其他']);
      expect(sections.single.sessions.map((s) => s.sessionId).toSet(), {
        'cron_1',
        's1',
      });
    });

    test('搜索模式派生单一「搜索结果」分区（包含命中结果，不拆分为工作区分区）', () async {
      final cronHit = _buildSession(
        'cron_hit',
        '定时备份任务',
        workspace: '/ws/backup',
      );
      final normalHit = _buildSession(
        's_hit',
        '普通备份任务',
        workspace: '/ws/other',
      );
      final api = FakeSessionListApi(sessions: [cronHit, normalHit]);
      api.searchResults['备份'] = [cronHit, normalHit];

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          // #159：分组方式默认按屏宽兜底（本文件的测试视口是窄屏 ⇒ 会走时间
          // 分组）。本组用例测的是工作区分组下的 cron 融流语义 ⇒ 显式指定。
          sessionGroupingModeProvider.overrideWith(
            _WorkspaceGroupingNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      await container.read(sessionListControllerProvider.notifier).search('备份');

      final sections = container.read(sessionListSectionsProvider);

      expect(sections, hasLength(1));
      expect(sections.first.title, '搜索结果');
      expect(sections.first.sessions.map((s) => s.sessionId).toList(), [
        'cron_hit',
        's_hit',
      ]);
    });
  });

  group('工作区分组契约专项（#146 · A 案）', () {
    final now = DateTime(2026, 9, 20, 12, 0);

    test('1. 两个工作区的会话分到两组且优先使用 workspaceRoots 中的 name 作为组名', () {
      final s1 = _buildSession(
        's1',
        '会话 1',
        at: now,
        workspace: '/repo/client',
      );
      final s2 = _buildSession(
        's2',
        '会话 2',
        at: now.subtract(const Duration(minutes: 5)),
        workspace: '/repo/server',
      );

      final roots = [
        const WorkspaceRoot(path: '/repo/client', name: '客户端项目'),
        const WorkspaceRoot(path: '/repo/server', name: '服务端项目'),
      ];

      final sections = buildSessionSections(
        [s1, s2],
        workspaceRoots: roots,
        now: now,
      );

      expect(sections.map((s) => s.title).toList(), ['客户端项目', '服务端项目']);
      expect(sections[0].sessions.map((s) => s.sessionId), ['s1']);
      expect(sections[1].sessions.map((s) => s.sessionId), ['s2']);
    });

    test('2. 组按组内最近活动时间倒序排序', () {
      // wsOld 最近活动 2 小时前
      final old1 = _buildSession(
        'old1',
        '较早会话',
        at: now.subtract(const Duration(hours: 2)),
        workspace: '/ws/old',
      );
      // wsNew 最近活动 10 分钟前，但包含一条 5 小时前的会话
      final new1 = _buildSession(
        'new1',
        '最新会话',
        at: now.subtract(const Duration(minutes: 10)),
        workspace: '/ws/new',
      );
      final new2 = _buildSession(
        'new2',
        '很早会话',
        at: now.subtract(const Duration(hours: 5)),
        workspace: '/ws/new',
      );

      final sections = buildSessionSections([old1, new2, new1], now: now);

      // ws/new 的最新时间（-10m）新于 ws/old（-2h），因此 new 在前
      expect(sections.map((s) => s.title).toList(), ['new', 'old']);
      expect(sections[0].sessions.map((s) => s.sessionId), ['new1', 'new2']);
      expect(sections[1].sessions.map((s) => s.sessionId), ['old1']);
    });

    test('3. workspace 为空的会话进「其他」组，固定排在最后，且标记 isOther', () {
      final sNull = _buildSession(
        's_null',
        'null 工作区',
        at: now,
        workspace: null,
      );
      final sEmpty = _buildSession(
        's_empty',
        '空串工作区',
        at: now.subtract(const Duration(minutes: 1)),
        workspace: '',
      );
      final sSpace = _buildSession(
        's_space',
        '空白工作区',
        at: now.subtract(const Duration(minutes: 2)),
        workspace: '   ',
      );
      final sWs = _buildSession(
        's_ws',
        '有工作区',
        at: now.subtract(const Duration(hours: 1)),
        workspace: '/ws/my_project',
      );

      final sections = buildSessionSections([
        sEmpty,
        sWs,
        sNull,
        sSpace,
      ], now: now);

      expect(sections.map((s) => s.title).toList(), ['my_project', '其他']);
      final otherSection = sections.last;
      expect(otherSection.isOther, isTrue);
      expect(otherSection.title, '其他');
      expect(otherSection.sessions.map((s) => s.sessionId), [
        's_null',
        's_empty',
        's_space',
      ]);

      // 契约：默认**不**折叠任何组——宁可在列表里多显示，也不能默认把内容藏起来
      // （无 workspace 的会话曾因「其他」默认折叠，在侧栏里看起来"消失"）。
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final collapsed = container.read(sessionListCollapsedSectionsProvider);
      expect(collapsed, isEmpty);
    });

    test('4. workspace 有值但不在 roots 里 → 按路径最后一段独立成组', () {
      final s1 = _buildSession(
        's1',
        '自定工作区 1',
        at: now,
        workspace: 'D:/random/custom_repo',
      );
      final s2 = _buildSession(
        's2',
        '自定工作区 2',
        at: now.subtract(const Duration(minutes: 10)),
        workspace: '/var/lib/my_service/',
      );

      // roots 为空，模拟不在 roots 里的任意目录
      final sections = buildSessionSections(
        [s1, s2],
        workspaceRoots: const [],
        now: now,
      );

      expect(sections.map((s) => s.title).toList(), [
        'custom_repo',
        'my_service',
      ]);
      expect(sections.any((s) => s.title == '其他'), isFalse);
    });

    test('5. 置顶区跨工作区独立置于最上方，不参与工作区分组', () {
      final p1 = _buildSession(
        'p1',
        '置顶 1',
        pinned: true,
        at: now,
        workspace: '/ws/alpha',
      );
      final p2 = _buildSession(
        'p2',
        '置顶 2',
        pinned: true,
        at: now.subtract(const Duration(minutes: 1)),
        workspace: '/ws/beta',
      );
      final p3 = _buildSession(
        'p3',
        '置顶 3（无工作区）',
        pinned: true,
        at: now.subtract(const Duration(minutes: 2)),
        workspace: null,
      );
      final a1 = _buildSession(
        'a1',
        'Alpha 正常',
        at: now,
        workspace: '/ws/alpha',
      );
      final b1 = _buildSession('b1', 'Beta 正常', at: now, workspace: '/ws/beta');

      final sections = buildSessionSections([a1, p3, b1, p1, p2], now: now);

      expect(sections.first.title, '置顶');
      expect(sections.first.isPinned, isTrue);
      // 三个置顶会话聚合在最顶部分区
      expect(sections.first.sessions.map((s) => s.sessionId).toList(), [
        'p1',
        'p2',
        'p3',
      ]);
      // 其余会话正常进入工作区
      expect(sections.sublist(1).map((s) => s.title).toList(), [
        'alpha',
        'beta',
      ]);
    });

    test('6. 搜索模式保持单一「搜索结果」分区不变', () async {
      final visible = [
        _buildSession('s1', '搜索命中 1', workspace: '/ws/alpha'),
        _buildSession('s2', '搜索命中 2', workspace: '/ws/beta'),
        _buildSession('s3', '搜索命中 3', workspace: null),
      ];
      final api = FakeSessionListApi(sessions: visible);
      api.searchResults['命中'] = visible;

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          // #159：分组方式默认按屏宽兜底（本文件的测试视口是窄屏 ⇒ 会走时间
          // 分组）。本组用例测的是工作区分组下的 cron 融流语义 ⇒ 显式指定。
          sessionGroupingModeProvider.overrideWith(
            _WorkspaceGroupingNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      // 先等初始加载完成，否则 search 后读到的仍是空列表（其余用例均如此初始化）。
      await container.read(sessionListControllerProvider.future);
      await container.read(sessionListControllerProvider.notifier).search('命中');
      final sections = container.read(sessionListSectionsProvider);

      expect(sections.length, 1);
      expect(sections.single.title, '搜索结果');
      expect(sections.single.sessions.length, 3);
    });

    test('容错比对：反斜杠、正斜杠与首尾空格通过 matchesWorkspace 合流同一组', () {
      final s1 = _buildSession(
        's1',
        'Windows 风格路径',
        at: now,
        workspace: r'C:\Projects\HermesApp',
      );
      final s2 = _buildSession(
        's2',
        'Unix 风格路径带空格',
        at: now.subtract(const Duration(minutes: 5)),
        workspace: '  C:/Projects/HermesApp  ',
      );

      final sections = buildSessionSections([s1, s2], now: now);

      expect(sections.length, 1);
      expect(sections.single.title, 'HermesApp');
      expect(sections.single.sessions.map((s) => s.sessionId).toList(), [
        's1',
        's2',
      ]);
    });

    test('折叠控制器操作：切换、展开、折叠及状态判断', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        sessionListCollapsedSectionsProvider.notifier,
      );

      expect(notifier.isCollapsed('其他'), isFalse); // 默认全展开
      expect(notifier.isCollapsed('alpha'), isFalse);

      notifier.toggle('alpha');
      expect(notifier.isCollapsed('alpha'), isTrue);

      notifier.toggle('alpha');
      expect(notifier.isCollapsed('alpha'), isFalse);

      notifier.toggle('其他');
      expect(notifier.isCollapsed('其他'), isTrue); // 用户主动折叠后才是折叠态

      notifier.collapse('beta');
      expect(notifier.isCollapsed('beta'), isTrue);

      notifier.expand('beta');
      expect(notifier.isCollapsed('beta'), isFalse);
    });
  });
}
