import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';
import 'package:hermes_ui/features/git/git_api.dart';
import 'package:hermes_ui/features/git/git_providers.dart';

import '../../helpers/fake_git_api.dart';

/// 带 2 个变更文件的仓库状态。
GitStatus sampleStatus() {
  return GitStatus(
    isGit: true,
    branch: 'main',
    upstream: 'origin/main',
    ahead: 1,
    behind: 0,
    totals: const GitTotals(changed: 2, staged: 1, unstaged: 1),
    files: [
      GitFile(path: 'a.txt', status: 'M', staged: true, additions: 2),
      GitFile(path: 'b.txt', status: 'M', unstaged: true, additions: 1),
    ],
  );
}

GitBranchesResponse branchesResponse(String current) => GitBranchesResponse(
  branches: GitBranches(
    isGit: true,
    current: current,
    local: [
      GitBranchRef(name: current),
      const GitBranchRef(name: 'dev'),
    ],
  ),
);

ProviderContainer makeContainer(FakeGitApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      gitApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('GitState.toString', () {
    test('含分支名 / isGit / 动作标记', () {
      const state = GitState(
        status: GitStatus(isGit: true, branch: 'main'),
        isActionRunning: true,
      );
      expect(
        state.toString(),
        'GitState(branch: main, isGit: true, actionRunning: true)',
      );
    });

    test('全空状态不抛错（null 分支 / null isGit）', () {
      expect(
        const GitState().toString(),
        'GitState(branch: null, isGit: null, actionRunning: false)',
      );
    });
  });

  group('GitController.refresh', () {
    test('刷新失败 → state 转 AsyncError 且带 stackTrace', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      api.statusError = NetworkException(NetworkExceptionKind.timedOut);
      await container.read(gitControllerProvider('s1').notifier).refresh();

      final async = container.read(gitControllerProvider('s1'));
      expect(async.hasError, isTrue);
      expect(async.error, isA<NetworkException>());
      expect(async.error, isA<ApiException>());
      expect(async.stackTrace, isNotNull);
      expect(async.isLoading, isFalse);
      // Riverpod 会把上一次数据挂到 AsyncError 上（copyWithPrevious 语义），
      // 但 UI 判定走 hasError 分支，旧数据只作占位。
      expect(async.valueOrNull!.status!.branch, 'main');
    });

    test('刷新成功 → 覆盖为 AsyncData 并重新拉取 status + 分支', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      api.statusResponse = const GitStatusResponse(
        git: GitStatus(isGit: true, branch: 'release'),
      );
      await container.read(gitControllerProvider('s1').notifier).refresh();

      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.status!.branch, 'release');
      expect(api.statusCount, 2);
      expect(api.branchesCount, 2);
    });
  });

  group('GitController.reloadBranches', () {
    test('build 尚未完成（无数据）→ 直接返回，不发请求', () async {
      final api = FakeGitApi(status: sampleStatus());
      final gate = Completer<void>();
      api.statusGate = gate;
      final container = makeContainer(api);
      final subscription = container.listen(
        gitControllerProvider('s1'),
        (_, _) {},
      );
      addTearDown(subscription.close);

      final notifier = container.read(gitControllerProvider('s1').notifier);
      expect(container.read(gitControllerProvider('s1')).valueOrNull, isNull);

      await notifier.reloadBranches();

      expect(api.branchesCount, 0);
      expect(container.read(gitControllerProvider('s1')).valueOrNull, isNull);

      gate.complete();
      final state = await container.read(gitControllerProvider('s1').future);
      expect(state.status!.branch, 'main');
      // build 完成后分支只拉取一次（reload 那次被挡在前面）。
      expect(api.branchesCount, 1);
    });

    test('非 git 仓库 → 直接返回，不发请求', () async {
      final api = FakeGitApi(status: const GitStatus(isGit: false));
      final container = makeContainer(api);
      final state = await container.read(gitControllerProvider('s1').future);
      expect(state.isNonRepository, isTrue);

      await container.read(gitControllerProvider('s1').notifier).reloadBranches();

      expect(api.branchesCount, 0);
      final after = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(after.branches, isNull);
      expect(after.branchesError, isNull);
    });

    test('成功：置 loading → 换新分支 → loading 复位、错误清空', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);
      expect(api.branchesCount, 1);

      api.branchesResponse = branchesResponse('release');
      await container.read(gitControllerProvider('s1').notifier).reloadBranches();

      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(api.branchesCount, 2);
      expect(state.branches!.current, 'release');
      expect(state.isBranchesLoading, isFalse);
      expect(state.branchesError, isNull);
      // 主状态（status）不被分支刷新覆盖。
      expect(state.status!.branch, 'main');
    });

    test('失败：保留旧分支 + 记录 branchesError + loading 复位', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      api.branchesError = NetworkException(NetworkExceptionKind.cannotConnect);
      await container.read(gitControllerProvider('s1').notifier).reloadBranches();

      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.isBranchesLoading, isFalse);
      expect(state.branchesError, isNotNull);
      // 与 _reloadAfterMutation 不同：这里旧分支被保留。
      expect(state.branches!.current, 'main');
      expect(state.status!.branch, 'main');
    });
  });

  group('GitController 提示清理', () {
    test('clearActionMessage：无提示时为幂等空操作，有提示时清空', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);
      final notifier = container.read(gitControllerProvider('s1').notifier);

      await notifier.clearActionMessage();
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionMessage,
        isNull,
      );

      expect(await notifier.commit('feat: 补测'), isTrue);
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionMessage,
        '已提交 abc1234',
      );
      expect(api.commitCalls, ['feat: 补测']);

      await notifier.clearActionMessage();
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionMessage,
        isNull,
      );

      // 再清一次仍是空操作（分支已被覆盖）。
      await notifier.clearActionMessage();
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionMessage,
        isNull,
      );
    });

    test('clearActionError：无错误时为幂等空操作，有错误时清空', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);
      final notifier = container.read(gitControllerProvider('s1').notifier);

      await notifier.clearActionError();
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        isNull,
      );

      api.stageError = NetworkException(NetworkExceptionKind.timedOut);
      expect(await notifier.stage(['a.txt']), isFalse);
      final failed = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(failed.actionError, isNotNull);
      expect(failed.isActionRunning, isFalse);

      await notifier.clearActionError();
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        isNull,
      );

      await notifier.clearActionError();
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        isNull,
      );
    });
  });

  group('变更后重载（_reloadAfterMutation）失败路径', () {
    test('checkout 后分支重载失败 → 切换仍返回 true + branchesError + 保留旧分支', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);
      final notifier = container.read(gitControllerProvider('s1').notifier);

      api.branchesError = NetworkException(NetworkExceptionKind.timedOut);
      final ok = await notifier.checkout('dev');

      expect(ok, isTrue);
      expect(api.checkoutCalls, ['dev:local']);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.isActionRunning, isFalse);
      expect(state.branchesError, isNotNull);
      // 修复（#14）：重载失败时保留已知分支（对齐同文件 reloadBranches），
      // 不再把 branches 置 null —— 否则一次瞬时抖动就把分支树清空。
      expect(state.branches, isNotNull);
      expect(state.branches!.current, 'main');
      expect(state.status!.branch, 'main');
    });

    test('push 后分支重载失败 → 远程操作仍返回 true + branchesError', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);
      final notifier = container.read(gitControllerProvider('s1').notifier);

      api.branchesError = NetworkException(NetworkExceptionKind.cannotConnect);
      final ok = await notifier.pushRemote();

      expect(ok, isTrue);
      expect(api.pushCalls, ['s1']);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.branchesError, isNotNull);
      expect(state.actionMessage, '完成');
      expect(state.isActionRunning, isFalse);
    });

    test('checkout 后 status 重载失败 → 外层 catch 记录 branchesError', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);
      final notifier = container.read(gitControllerProvider('s1').notifier);

      api.statusError = NetworkException(NetworkExceptionKind.timedOut);
      final ok = await notifier.checkout('dev');

      expect(ok, isTrue);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.branchesError, isNotNull);
      expect(state.isActionRunning, isFalse);
      // status 保持切换前快照（重载未成功）。
      expect(state.status!.branch, 'main');
      expect(state.branches!.current, 'main');
    });

    test('checkout 后 status 与分支均成功 → 错误清空、数据替换', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);
      final notifier = container.read(gitControllerProvider('s1').notifier);

      api.statusResponse = const GitStatusResponse(
        git: GitStatus(isGit: true, branch: 'dev'),
      );
      api.branchesResponse = branchesResponse('dev');
      final ok = await notifier.checkout('dev');

      expect(ok, isTrue);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.status!.branch, 'dev');
      expect(state.branches!.current, 'dev');
      expect(state.branchesError, isNull);
      expect(state.isActionRunning, isFalse);
    });
  });
}
