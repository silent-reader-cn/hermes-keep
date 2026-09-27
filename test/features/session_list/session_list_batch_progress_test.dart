import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_session_list_api.dart';

/// #174 批量操作进度：controller 侧守卫。
///
/// 现象（主人报告）：多选后点归档/删除**全程无反馈**，几十条时只能干等；
/// 且操作期按钮不禁用，连点会并发发起第二批请求。
///
/// 本文件钉死三件事：
/// 1. 循环内**逐条推进** [SessionListState.batchProgress]（含失败条）；
/// 2. 收尾**必清**进度（否则批量栏永久禁用）；
/// 3. 在途期间**拒绝重入**（连点不得产生第二批请求）。
double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(String id, String title) => SessionSummary(
  sessionId: id,
  title: title,
  lastMessageAt: _sec(DateTime.now()),
);

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
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => FakeOnboardingLoginApi(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('#174 批量操作进度', () {
    test('归档：逐条推进进度，收尾清空并退出多选', () async {
      final api = FakeSessionListApi(
        sessions: [
          _session('s1', 'A'),
          _session('s2', 'B'),
          _session('s3', 'C'),
        ],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      SessionListState snap() =>
          container.read(sessionListControllerProvider).valueOrNull!;

      for (final id in ['s1', 's2', 's3']) {
        controller.toggleSelection(id);
      }

      // 预注册闸门：三条都会挂起，边界确定。
      for (final id in ['s1', 's2', 's3']) {
        api.gate(id);
      }

      final future = controller.batchArchive();
      await pumpEventQueue();

      final started = snap().batchProgress;
      expect(started, isNotNull, reason: '在途必须有进度可观测');
      expect(started!.kind, BatchOperationKind.archive);
      expect(started.done, 0);
      expect(started.total, 3);
      expect(started.fraction, 0);
      expect(api.archiveCalls, ['s1:true'], reason: '串行：只有第一条在途');

      api.gate('s1').complete();
      await pumpEventQueue();
      expect(snap().batchProgress!.done, 1);
      expect(snap().batchProgress!.fraction, closeTo(1 / 3, 1e-9));
      expect(api.archiveCalls, ['s1:true', 's2:true']);

      api.gate('s2').complete();
      await pumpEventQueue();
      expect(snap().batchProgress!.done, 2);

      api.gate('s3').complete();
      await future;

      final done = snap();
      expect(done.batchProgress, isNull, reason: '收尾必须清掉进度，否则批量栏永久禁用');
      expect(done.selectedSessionIds, isEmpty);
      expect(done.isSelectionMode, isFalse);
      expect(done.sessions, isEmpty, reason: '三条全部成功 ⇒ 全部移出列表');
    });

    test('在途期间重入被拒：不产生第二批请求', () async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', 'A'), _session('s2', 'B')],
      );
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.toggleSelection('s1');
      controller.toggleSelection('s2');
      api.gate('s1');
      api.gate('s2');

      final first = controller.batchArchive();
      await pumpEventQueue();
      expect(api.archiveCalls, ['s1:true']);

      // 连点第二下（模拟批量栏按钮被重复触发）。
      final second = controller.batchArchive();
      await pumpEventQueue();
      // 先断请求列表：无门闩时这里会多出第二条 s1 —— 失败形态是精确断言，
      // 而不是「await 挂住直到超时」。
      expect(
        api.archiveCalls,
        ['s1:true'],
        reason: '重入必须被门闩挡下，不得再发一轮',
      );
      final secondResult = await second;
      expect(secondResult.succeeded, 0);
      expect(secondResult.failed, 0);

      api.gate('s1').complete();
      await pumpEventQueue();
      api.gate('s2').complete();
      await first;

      expect(api.archiveCalls, ['s1:true', 's2:true'], reason: '全程只跑一批');
      expect(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .batchProgress,
        isNull,
      );
    });

    test('部分失败：失败条同样推进进度（不卡住），收尾清空 + 写 actionError', () async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', 'A'), _session('s2', 'B')],
      )..failingIds.add('s2');
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      SessionListState snap() =>
          container.read(sessionListControllerProvider).valueOrNull!;

      controller.toggleSelection('s1');
      controller.toggleSelection('s2');
      api.gate('s1');
      api.gate('s2');

      final future = controller.batchDelete();
      await pumpEventQueue();
      expect(snap().batchProgress!.done, 0);

      api.gate('s1').complete();
      await pumpEventQueue();
      expect(snap().batchProgress!.done, 1);

      api.gate('s2').complete();
      final result = await future;

      expect(result.succeeded, 1);
      expect(result.failed, 1);
      expect(snap().batchProgress, isNull, reason: '失败项也必须推进到底并清空进度');
      expect(snap().actionError, '批量删除：1 个会话失败');
    });

    test('删除 / 移动上报各自的进度类型', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      SessionListState snap() =>
          container.read(sessionListControllerProvider).valueOrNull!;

      controller.toggleSelection('s1');
      api.gate('s1');
      final del = controller.batchDelete();
      await pumpEventQueue();
      expect(snap().batchProgress!.kind, BatchOperationKind.delete);
      expect(snap().batchProgress!.total, 1);
      api.gate('s1').complete();
      await del;
      expect(snap().batchProgress, isNull);

      api.resetGates();
      controller.toggleSelection('s1');
      api.gate('s1');
      final move = controller.batchMove('p-1');
      await pumpEventQueue();
      expect(snap().batchProgress!.kind, BatchOperationKind.move);
      expect(snap().batchProgress!.total, 1);
      api.gate('s1').complete();
      await move;
      expect(snap().batchProgress, isNull);
      expect(api.moveCalls, ['s1:p-1']);
    });

    test('空勾选：直接返回且不残留进度', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final result = await controller.batchArchive();
      expect(result.succeeded, 0);
      expect(result.failed, 0);
      expect(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .batchProgress,
        isNull,
      );
      expect(api.archiveCalls, isEmpty);
    });

    test('恢复归档（archived: false）上报 unarchive 类型', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', 'A')]);
      final container = _container(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      controller.toggleSelection('s1');
      api.gate('s1');
      final future = controller.batchArchive(archived: false);
      await pumpEventQueue();
      expect(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .batchProgress!
            .kind,
        BatchOperationKind.unarchive,
      );
      api.gate('s1').complete();
      await future;
      expect(api.archiveCalls, ['s1:false']);
    });
  });
}
