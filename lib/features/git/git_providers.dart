import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/git_workspace.dart';
import 'git_api.dart';

/// Git 面板状态（AsyncNotifier 的 AsyncData 载荷）。
///
/// 面板按会话工作区定位：每个 `session_id` 一个独立的
/// [gitControllerProvider] 实例（autoDispose family）。
class GitState {
  const GitState({
    this.status,
    this.branches,
    this.isBranchesLoading = false,
    this.branchesError,
    this.selectedFile,
    this.diff,
    this.isDiffLoading = false,
    this.isActionRunning = false,
    this.actionError,
    this.actionMessage,
  });

  /// git status 响应（null = 尚未加载成功）。
  final GitStatus? status;

  /// 分支列表（非 git 仓库 / 加载失败 → null）。
  final GitBranches? branches;

  /// 分支列表加载中（build 后由 refresh 触发）。
  final bool isBranchesLoading;

  /// 分支列表加载失败信息（不影响 status 展示）。
  final String? branchesError;

  /// 当前选中查看 diff 的文件（null = 未展开）。
  final GitFile? selectedFile;

  /// 选中文件的 diff（加载中 / 失败 → null）。
  final GitDiff? diff;

  /// 选中文件的 diff 加载中。
  final bool isDiffLoading;

  /// 任一写操作进行中（stage/unstage/discard/commit/fetch/pull/push/checkout）。
  final bool isActionRunning;

  /// 最近一次写操作错误（UI 弹窗展示后调用 [GitController.clearActionError] 清除）。
  final String? actionError;

  /// 最近一次写操作成功提示（commit SHA / 远程操作结果）。
  final String? actionMessage;

  /// 已确认是 git 仓库。
  bool get isGitRepository => status?.isGit == true;

  /// 已确认不是 git 仓库。
  bool get isNonRepository => status?.isGit == false;

  /// 工作区已跟踪变更文件（排除 ignored）。
  List<GitFile> get trackedFiles => status?.trackedFiles ?? const <GitFile>[];

  /// 已暂存文件（staged == true）。
  List<GitFile> get stagedFiles =>
      trackedFiles.where((f) => f.staged == true).toList(growable: false);

  /// 未暂存 / 未跟踪文件（staged != true）。
  List<GitFile> get unstagedFiles =>
      trackedFiles.where((f) => f.staged != true).toList(growable: false);

  /// 是否有可提交的变更。
  bool get hasCommittableChanges => trackedFiles.isNotEmpty;

  GitState copyWith({
    GitStatus? Function()? status,
    GitBranches? Function()? branches,
    bool? isBranchesLoading,
    String? Function()? branchesError,
    GitFile? Function()? selectedFile,
    GitDiff? Function()? diff,
    bool? isDiffLoading,
    bool? isActionRunning,
    String? Function()? actionError,
    String? Function()? actionMessage,
  }) {
    return GitState(
      status: status != null ? status() : this.status,
      branches: branches != null ? branches() : this.branches,
      isBranchesLoading: isBranchesLoading ?? this.isBranchesLoading,
      branchesError: branchesError != null
          ? branchesError()
          : this.branchesError,
      selectedFile: selectedFile != null ? selectedFile() : this.selectedFile,
      diff: diff != null ? diff() : this.diff,
      isDiffLoading: isDiffLoading ?? this.isDiffLoading,
      isActionRunning: isActionRunning ?? this.isActionRunning,
      actionError: actionError != null ? actionError() : this.actionError,
      actionMessage: actionMessage != null
          ? actionMessage()
          : this.actionMessage,
    );
  }

  @override
  String toString() =>
      'GitState(branch: ${status?.branch}, isGit: ${status?.isGit}, '
      'actionRunning: $isActionRunning)';
}

/// Git 面板控制器：加载 status / 分支 / diff，执行 stage / unstage /
/// discard / commit / fetch / pull / push / checkout。
///
/// AsyncValue 语义：初始加载与刷新失败 → `AsyncError`（UI 展示错误态 +
/// 重试）；行操作失败不改变主状态，只设置 [GitState.actionError] 供弹窗
/// 提示；分支列表加载失败只记录 [GitState.branchesError]。
final gitControllerProvider = AsyncNotifierProvider.autoDispose
    .family<GitController, GitState, String>(GitController.new);

class GitController extends AutoDisposeFamilyAsyncNotifier<GitState, String> {
  String get _sessionId => arg;

  GitApi get _api =>
      ref.read(gitApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<GitState> build(String sessionId) async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(gitApiFactoryProvider)(ref.watch(apiClientProvider));
    return _load(api);
  }

  /// 下拉刷新 / 错误态重试：重新加载 status + 分支。
  Future<void> refresh() async {
    try {
      state = AsyncData(await _load(_api));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 重新加载分支列表（fetch/pull/push 后调用，保持选择器同步）。
  Future<void> reloadBranches() async {
    final current = state.valueOrNull;
    if (current == null || !current.isGitRepository) return;
    state = AsyncData(current.copyWith(isBranchesLoading: true));
    try {
      final branches = (await _api.fetchBranches(_sessionId)).branches;
      state = AsyncData(
        current.copyWith(
          branches: () => branches,
          isBranchesLoading: false,
          branchesError: () => null,
        ),
      );
    } on Exception catch (error) {
      state = AsyncData(
        current.copyWith(
          isBranchesLoading: false,
          branchesError: () => gitFriendlyError(error),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // 文件操作
  // -------------------------------------------------------------------------

  /// 选中 / 折叠文件：首次点击加载 diff，再次点击折叠。
  Future<void> selectFile(GitFile file) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.selectedFile?.id == file.id && current.diff != null) {
      state = AsyncData(
        current.copyWith(
          selectedFile: () => null,
          diff: () => null,
          isDiffLoading: false,
        ),
      );
      return;
    }
    final path = file.displayPath;
    if (path.isEmpty) {
      state = AsyncData(
        current.copyWith(
          selectedFile: () => file,
          diff: () => null,
          actionError: () => '服务器未提供文件路径。',
        ),
      );
      return;
    }
    state = AsyncData(
      current.copyWith(
        selectedFile: () => file,
        diff: () => null,
        isDiffLoading: true,
      ),
    );
    try {
      final response = await _api.fetchDiff(
        sessionId: _sessionId,
        path: path,
        kind: file.preferredDiffKind,
      );
      state = AsyncData(
        current.copyWith(
          selectedFile: () => file,
          diff: () => response.diff,
          isDiffLoading: false,
        ),
      );
    } on Exception catch (error) {
      state = AsyncData(
        current.copyWith(
          selectedFile: () => file,
          diff: () => null,
          isDiffLoading: false,
          actionError: () => gitFriendlyError(error),
        ),
      );
    }
  }

  /// 暂存指定文件。
  Future<bool> stage(List<String> paths) => _runMutation<GitMutationResponse>(
    (api) => api.stage(sessionId: _sessionId, paths: paths),
    (current, response) => current.copyWith(
      status: () => response.resolvedStatus ?? current.status,
    ),
  );

  /// 取消暂存指定文件。
  Future<bool> unstage(List<String> paths) => _runMutation<GitMutationResponse>(
    (api) => api.unstage(sessionId: _sessionId, paths: paths),
    (current, response) => current.copyWith(
      status: () => response.resolvedStatus ?? current.status,
    ),
  );

  /// 丢弃指定文件的更改（untracked 文件默认删除）。
  Future<bool> discard(List<String> paths, {bool deleteUntracked = true}) =>
      _runMutation<GitMutationResponse>(
        (api) => api.discard(
          sessionId: _sessionId,
          paths: paths,
          deleteUntracked: deleteUntracked,
        ),
        (current, response) => current.copyWith(
          status: () => response.resolvedStatus ?? current.status,
          selectedFile: () => null,
          diff: () => null,
        ),
      );

  /// 提交暂存更改；成功返回 true 并提示短 SHA。
  Future<bool> commit(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      await _setActionError('提交信息不能为空。');
      return false;
    }
    return _runMutation<GitCommitResponse>(
      (api) => api.commit(sessionId: _sessionId, message: trimmed),
      (current, response) {
        final sha = response.shortSHA;
        return current.copyWith(
          status: () => response.resolvedStatus ?? current.status,
          selectedFile: () => null,
          diff: () => null,
          actionMessage: () => sha != null ? '已提交 $sha' : '提交成功',
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // 分支与远程操作
  // -------------------------------------------------------------------------

  /// 切换到本地分支；成功后刷新 status + 分支列表。
  Future<bool> checkout(String ref) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    if (current.branches?.current == ref) return false;
    state = AsyncData(
      current.copyWith(isActionRunning: true, actionError: () => null),
    );
    try {
      final response = await _api.checkout(sessionId: _sessionId, ref: ref);
      var next = current.copyWith(
        status: () => response.resolvedStatus ?? current.status,
        branches: () => response.branches ?? current.branches,
        selectedFile: () => null,
        diff: () => null,
        actionMessage: () => response.message ?? '已切换到 $ref',
      );
      next = await _reloadAfterMutation(next);
      state = AsyncData(next.copyWith(isActionRunning: false));
      return true;
    } on Exception catch (error) {
      state = AsyncData(
        current.copyWith(
          isActionRunning: false,
          actionError: () => gitFriendlyError(error),
        ),
      );
      return false;
    }
  }

  /// fetch 远程更新。
  Future<bool> fetchRemote() => _runMutation<GitRemoteActionResponse>(
    (api) => api.fetch(_sessionId),
    (current, response) => current.copyWith(
      status: () => response.status ?? current.status,
      actionMessage: () => response.message ?? 'fetch 完成',
    ),
  );

  /// pull 远程更新。
  Future<bool> pullRemote() => _runMutation<GitRemoteActionResponse>(
    (api) => api.pull(_sessionId),
    (current, response) => current.copyWith(
      status: () => response.status ?? current.status,
      actionMessage: () => response.message ?? 'pull 完成',
    ),
  );

  /// push 到远程。
  Future<bool> pushRemote() => _runMutation<GitRemoteActionResponse>(
    (api) => api.push(_sessionId),
    (current, response) => current.copyWith(
      status: () => response.status ?? current.status,
      actionMessage: () => response.message ?? 'push 完成',
    ),
  );

  /// 清除写操作错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  /// 清除成功提示标记。
  Future<void> clearActionMessage() async {
    final current = state.valueOrNull;
    if (current == null || current.actionMessage == null) return;
    state = AsyncData(current.copyWith(actionMessage: () => null));
  }

  // -------------------------------------------------------------------------
  // 内部原语
  // -------------------------------------------------------------------------

  Future<GitState> _load(GitApi api) async {
    final statusResponse = await api.fetchStatus(_sessionId);
    final status = statusResponse.git;
    if (status?.isGit != true) {
      return GitState(status: status);
    }
    GitBranches? branches;
    String? branchesError;
    try {
      branches = (await api.fetchBranches(_sessionId)).branches;
    } on Exception catch (error) {
      branchesError = gitFriendlyError(error);
    }
    return GitState(
      status: status,
      branches: branches,
      branchesError: branchesError,
    );
  }

  /// 写操作通用执行：置 running → 调 API → 应用响应 / 记录错误。
  Future<bool> _runMutation<T>(
    Future<T> Function(GitApi api) call,
    GitState Function(GitState current, T response) apply,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    state = AsyncData(
      current.copyWith(isActionRunning: true, actionError: () => null),
    );
    try {
      final response = await call(_api);
      var next = apply(current, response);
      // 远程操作（fetch/pull/push）后刷新分支，保持选择器同步。
      if (response is GitRemoteActionResponse && current.isGitRepository) {
        next = await _reloadAfterMutation(next);
      }
      state = AsyncData(next.copyWith(isActionRunning: false));
      return true;
    } on Exception catch (error) {
      state = AsyncData(
        current.copyWith(
          isActionRunning: false,
          actionError: () => gitFriendlyError(error),
        ),
      );
      return false;
    }
  }

  /// 变更类操作后重新拉取 status + 分支（checkout / fetch / pull / push）。
  Future<GitState> _reloadAfterMutation(GitState current) async {
    try {
      final statusResponse = await _api.fetchStatus(_sessionId);
      final status = statusResponse.git;
      GitBranches? branches;
      String? branchesError;
      if (status?.isGit == true) {
        try {
          branches = (await _api.fetchBranches(_sessionId)).branches;
        } on Exception catch (error) {
          branchesError = gitFriendlyError(error);
          // 保留已知分支：对齐同文件 reloadBranches 的失败语义。
          // 否则一次瞬时拉取失败就把 branches 置 null，分支树整块变空白
          //（真机表现：网络抖动一次 → 分支列表消失）。
          branches = current.branches;
        }
      }
      return current.copyWith(
        status: () => status,
        branches: () => branches,
        branchesError: () => branchesError,
      );
    } on Exception catch (error) {
      return current.copyWith(branchesError: () => gitFriendlyError(error));
    }
  }

  Future<void> _setActionError(String message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(actionError: () => message));
  }
}

/// 把 git 写操作错误映射为友好的中文提示（对齐 Swift
/// `gitWriteFriendlyMessage`）；未知错误码回退到服务器消息 / 通用描述。
String gitFriendlyError(Object error) {
  if (error is HttpException) {
    switch (error.serverCode) {
      case 'destructive_git_disabled':
        return '服务器已禁用写入操作。请在服务器设置 '
            'HERMES_WEBUI_WORKSPACE_GIT_DESTRUCTIVE=1 后使用。';
      case 'active_stream':
        return '请等待当前响应完成后再操作仓库。';
      case 'dirty_worktree':
        return '工作区有未提交的更改，无法切换分支。';
      default:
        final serverMessage = error.serverMessage;
        if (serverMessage != null && serverMessage.isNotEmpty) {
          return serverMessage;
        }
    }
  }
  if (error is ApiException) return error.message;
  return error.toString();
}
