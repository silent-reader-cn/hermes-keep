// #20 回归守卫：下拉刷新（含任何 refresh() 调用方）不得静默重置用户的视图态。
//
// 缺陷本体：`refresh()` 成功分支以 `_loadFirstPage` 返回的**全新 state** 为
// `copyWith` 基底（只回填 showSubagent），于是 searchQuery / searchResults /
// filterMode / filterValue / archivedSessions 被清空、视图退回「全部」；
// 而**失败分支**用的是 `previous.copyWith`（保留）—— 成功丢、失败不丢的
// 不对称即缺陷本体。
//
// 本文件从控制器层钉住修复后的行为：刷新后视图态保留，
// 同时钉住「一般态刷新仍要正常更新数据」，防止过度修复把刷新变成 no-op。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_session_list_api.dart';

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(String id, String title, {String? sourceLabel}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    sourceLabel: sourceLabel,
    lastMessageAt: _sec(DateTime.now()),
  );
}

/// 空项目 API stub：避免真实 [ApiClient] 发出 dio 请求残留超时 Timer。
class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

ProviderContainer _container(FakeSessionListApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 取出就绪后的 [SessionListState]。
SessionListState _state(ProviderContainer container) {
  final s = container.read(sessionListControllerProvider).valueOrNull;
  expect(s, isNotNull, reason: '控制器应已就绪');
  return s!;
}

void main() {
  group('#20 刷新不重置视图态（回归守卫）', () {
    test('搜索态：refresh() 后 searchQuery / searchResults 保留，底层列表已刷新', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      api.searchResults['alpha'] = [_session('s9', '命中')];
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final c = container.read(sessionListControllerProvider.notifier);

      await c.search('alpha');
      expect(_state(container).searchQuery, 'alpha');
      expect(_state(container).searchResults, hasLength(1));

      // 底层列表在刷新时变了，用来证明 refresh 真的重载了数据
      api.sessions = [_session('s1', 'A'), _session('s2', 'B')];
      await c.refresh();

      final st = _state(container);
      expect(st.searchQuery, 'alpha', reason: '下拉刷新不该清掉搜索态');
      expect(st.searchResults, hasLength(1), reason: '搜索结果应保留');
      expect(st.sessions, hasLength(2), reason: '底层列表应已刷新');
    });

    test('归档态：refresh() 后 filterMode 仍为 archived', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final c = container.read(sessionListControllerProvider.notifier);

      await c.setFilter(SessionListFilterMode.archived);
      expect(_state(container).filterMode, SessionListFilterMode.archived);

      await c.refresh();

      expect(
        _state(container).filterMode,
        SessionListFilterMode.archived,
        reason: '下拉刷新不该退出归档视图回到「全部」',
      );
    });

    test('来源筛选态：refresh() 后 filterMode / filterValue 保留', () async {
      final api = FakeSessionListApi(
        sessions: [
          _session('s1', 'A', sourceLabel: 'qq'),
          _session('s2', 'B', sourceLabel: 'web'),
        ],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final c = container.read(sessionListControllerProvider.notifier);

      await c.setFilter(SessionListFilterMode.source, value: 'qq');

      await c.refresh();

      final st = _state(container);
      expect(st.filterMode, SessionListFilterMode.source, reason: '筛选模式应保留');
      expect(st.filterValue, 'qq', reason: '筛选值应保留');
      expect(st.displaySessions, hasLength(1), reason: '筛选结果应仍只有 qq 来源');
    });

    test('一般态：refresh() 仍正常更新数据（防过度修复）', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final c = container.read(sessionListControllerProvider.notifier);

      api.sessions = [_session('s1', 'A'), _session('s2', 'B')];
      await c.refresh();

      final st = _state(container);
      expect(st.sessions, hasLength(2), reason: '刷新必须真的重载数据');
      expect(st.refreshing, isFalse);
      expect(st.searchQuery, isNull, reason: '无搜索时保持无搜索');
      expect(st.filterMode, SessionListFilterMode.all);
    });
  });
}
