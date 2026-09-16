import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';

/// git_workspace.dart 第 389–935 行（13 个类）补测 · 第 2 批。
///
/// 风格对照 `test/core/models/git_workspace_extra_test.dart`（第 1 批）：
/// 每类做「正常键 / 键缺失 / 显式 null / 错型 / lossy 跨类型」fromJson 多路，
/// 外加阶梯式 `==`（n 个字段 → n 个变体，逐字段各差一项，保证 `&&` 每一行
/// 比较都被执行）+ hashCode + toString。
///
/// 本批范围：GitRemoteActionResponse / GitMutationResponse / GitCommitResponse /
/// GitCommitMessageResponse / GitBranchesResponse / GitBranches / GitBranchRef /
/// GitCheckoutResponse / GitRestoredStash / GitDiffResponse / GitDiff /
/// enum GitBranchMode / GitCheckoutTarget。
/// （第 1 批已覆盖 GitInfoResponse / GitInfo / GitStatusResponse / GitStatus /
/// GitTotals / GitFile / enum GitFileChangeKind，此处不重复。）
/// 本批 13 类实现均为 snake 单键，无 `firstKey` 多键回退链
/// （`grep -n firstKey lib/core/models/git_workspace.dart` 无命中）。
void main() {
  group('GitRemoteActionResponse', () {
    test('fromJson：正常三字段', () {
      final response = GitRemoteActionResponse.fromJson({
        'ok': true,
        'message': '已推送',
        'status': {'is_git': true, 'branch': 'main'},
      });
      expect(response.ok, true);
      expect(response.message, '已推送');
      expect(response.status!.isGit, true);
      expect(response.status!.branch, 'main');
    });

    test('fromJson：键缺失 → 全 null；显式 null → 全 null', () {
      final empty = GitRemoteActionResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.message, isNull);
      expect(empty.status, isNull);

      final nulls = GitRemoteActionResponse.fromJson({
        'ok': null,
        'message': null,
        'status': null,
      });
      expect(nulls.ok, isNull);
      expect(nulls.message, isNull);
      expect(nulls.status, isNull);
    });

    test('fromJson：lossy 跨类型（ok / message）', () {
      expect(GitRemoteActionResponse.fromJson({'ok': 'yes'}).ok, true);
      expect(GitRemoteActionResponse.fromJson({'ok': 'NO'}).ok, false);
      expect(GitRemoteActionResponse.fromJson({'ok': 1}).ok, true);
      expect(GitRemoteActionResponse.fromJson({'ok': 0}).ok, false);
      expect(GitRemoteActionResponse.fromJson({'ok': 2}).ok, isNull);
      expect(GitRemoteActionResponse.fromJson({'ok': 'maybe'}).ok, isNull);
      expect(GitRemoteActionResponse.fromJson({'ok': <Object?>[]}).ok, isNull);

      expect(GitRemoteActionResponse.fromJson({'message': 1}).message, '1');
      expect(GitRemoteActionResponse.fromJson({'message': 1.5}).message, '1.5');
      expect(GitRemoteActionResponse.fromJson({'message': true}).message, 'true');
      expect(
        GitRemoteActionResponse.fromJson({'message': <Object?>[]}).message,
        isNull,
      );
      expect(
        GitRemoteActionResponse.fromJson({'message': const <String, Object?>{}})
            .message,
        isNull,
      );
    });

    test('fromJson：status 错型 → null；空 Map → 全 null 的 GitStatus', () {
      // optModel 的 `value is! Map` 分支
      expect(GitRemoteActionResponse.fromJson({'status': 'bad'}).status, isNull);
      expect(GitRemoteActionResponse.fromJson({'status': 1}).status, isNull);
      expect(GitRemoteActionResponse.fromJson({'status': true}).status, isNull);
      expect(
        GitRemoteActionResponse.fromJson({'status': <Object?>[]}).status,
        isNull,
      );
      final emptyStatus =
          GitRemoteActionResponse.fromJson({'status': <String, Object?>{}}).status;
      expect(emptyStatus, isNotNull);
      expect(emptyStatus!.branch, isNull);
      expect(emptyStatus.isGit, isNull);
    });

    test('== 阶梯式（3 字段逐项差一）+ hashCode / toString', () {
      const base = GitRemoteActionResponse(
        ok: true,
        message: '已推送',
        status: GitStatus(branch: 'main'),
      );
      const same = GitRemoteActionResponse(
        ok: true,
        message: '已推送',
        status: GitStatus(branch: 'main'),
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(base == const GitRemoteActionResponse(ok: false), isFalse); // ok 差
      expect(
        base == const GitRemoteActionResponse(ok: true, message: '已拉取'),
        isFalse,
      ); // message 差
      expect(
        base ==
            const GitRemoteActionResponse(ok: true, status: GitStatus(branch: 'main')),
        isFalse,
      ); // message 差（null）
      expect(
        base ==
            const GitRemoteActionResponse(
              ok: true,
              message: '已推送',
              status: GitStatus(branch: 'dev'),
            ),
        isFalse,
      ); // status 差
      expect(
        base == const GitRemoteActionResponse(ok: true, message: '已推送'),
        isFalse,
      ); // status 差（null）

      expect(const GitRemoteActionResponse() == const GitRemoteActionResponse(), isTrue);
      expect(const GitRemoteActionResponse() == base, isFalse);
      expect(base == Object(), isFalse);

      expect(base.toString(), 'GitRemoteActionResponse(ok: true)');
      expect(
        GitRemoteActionResponse.fromJson(const {}).toString(),
        'GitRemoteActionResponse(ok: null)',
      );
    });
  });

  group('GitMutationResponse', () {
    test('fromJson：正常双字段 + resolvedStatus 直取 git', () {
      final response = GitMutationResponse.fromJson({
        'ok': true,
        'git': {'is_git': true, 'branch': 'main', 'ahead': 2},
      });
      expect(response.ok, true);
      expect(response.git!.branch, 'main');
      expect(response.git!.ahead, 2);
      expect(response.resolvedStatus!.branch, 'main');
      expect(identical(response.resolvedStatus, response.git), isTrue);
    });

    test('fromJson：键缺失 / 显式 null / 错型', () {
      final empty = GitMutationResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.git, isNull);
      expect(empty.resolvedStatus, isNull);

      final nulls = GitMutationResponse.fromJson({'ok': null, 'git': null});
      expect(nulls.ok, isNull);
      expect(nulls.git, isNull);

      expect(GitMutationResponse.fromJson({'ok': 'no'}).ok, false);
      expect(GitMutationResponse.fromJson({'ok': ''}).ok, isNull);
      expect(GitMutationResponse.fromJson({'ok': 3}).ok, isNull);
      // optModel 的 `value is! Map` 分支
      expect(GitMutationResponse.fromJson({'git': 'bad'}).git, isNull);
      expect(GitMutationResponse.fromJson({'git': 1}).git, isNull);
      expect(GitMutationResponse.fromJson({'git': <Object?>[]}).git, isNull);
      expect(
        GitMutationResponse.fromJson({'git': <String, Object?>{}}).git!.branch,
        isNull,
      );
      // 空 status 映射仍然算「有值」→ resolvedStatus 非 null
      expect(GitMutationResponse.fromJson({'git': <String, Object?>{}}).resolvedStatus, isNotNull);
    });

    test('== 阶梯式（2 字段逐项差一）+ hashCode / toString', () {
      const base = GitMutationResponse(ok: true, git: GitStatus(branch: 'main'));
      const same = GitMutationResponse(ok: true, git: GitStatus(branch: 'main'));
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(base == const GitMutationResponse(ok: false, git: GitStatus(branch: 'main')), isFalse); // ok 差
      expect(base == const GitMutationResponse(ok: true), isFalse); // git 差（null）
      expect(
        base == const GitMutationResponse(ok: true, git: GitStatus(branch: 'dev')),
        isFalse,
      ); // git 差（值）

      expect(const GitMutationResponse() == const GitMutationResponse(), isTrue);
      expect(const GitMutationResponse() == base, isFalse);
      expect(base == Object(), isFalse);
      expect(base.hashCode == const GitMutationResponse().hashCode, isFalse);

      expect(base.toString(), 'GitMutationResponse(ok: true)');
      expect(
        GitMutationResponse.fromJson(const {}).toString(),
        'GitMutationResponse(ok: null)',
      );
    });
  });

  group('GitCommitResponse', () {
    test('fromJson：正常五字段', () {
      final response = GitCommitResponse.fromJson({
        'ok': true,
        'commit': 'abc1234',
        'paths': ['lib/main.dart', 'lib/a.dart'],
        'status': {'is_git': true, 'branch': 'main'},
        'git': {'branch': 'dev'},
      });
      expect(response.ok, true);
      expect(response.commit, 'abc1234');
      expect(response.paths, ['lib/main.dart', 'lib/a.dart']);
      expect(response.status!.branch, 'main');
      expect(response.git!.branch, 'dev');
    });

    test('fromJson：键缺失 / 显式 null → 全 null', () {
      final empty = GitCommitResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.commit, isNull);
      expect(empty.paths, isNull);
      expect(empty.status, isNull);
      expect(empty.git, isNull);

      final nulls = GitCommitResponse.fromJson({
        'ok': null,
        'commit': null,
        'paths': null,
        'status': null,
        'git': null,
      });
      expect(nulls.ok, isNull);
      expect(nulls.commit, isNull);
      expect(nulls.paths, isNull);
      expect(nulls.status, isNull);
      expect(nulls.git, isNull);
    });

    test('fromJson：lossy 跨类型（ok / commit）', () {
      expect(GitCommitResponse.fromJson({'ok': 'yes'}).ok, true);
      expect(GitCommitResponse.fromJson({'ok': 0}).ok, false);
      expect(GitCommitResponse.fromJson({'ok': 2}).ok, isNull);
      expect(GitCommitResponse.fromJson({'ok': []}).ok, isNull);

      expect(GitCommitResponse.fromJson({'commit': 1}).commit, '1');
      expect(GitCommitResponse.fromJson({'commit': 1.5}).commit, '1.5');
      expect(GitCommitResponse.fromJson({'commit': true}).commit, 'true');
      expect(GitCommitResponse.fromJson({'commit': []}).commit, isNull);
    });

    test('fromJson：status / git 错型 → null', () {
      for (final bad in <Object?>['bad', 1, true, <Object?>[]]) {
        expect(GitCommitResponse.fromJson({'status': bad}).status, isNull);
        expect(GitCommitResponse.fromJson({'git': bad}).git, isNull);
      }
      expect(
        GitCommitResponse.fromJson({'status': <String, Object?>{}}).status!.branch,
        isNull,
      );
      expect(
        GitCommitResponse.fromJson({'git': <String, Object?>{}}).git!.branch,
        isNull,
      );
    });

    test('fromJson：paths 走 optStringList —— 非 List / 元素非 String → null；空 → 空', () {
      expect(GitCommitResponse.fromJson({'paths': 'bad'}).paths, isNull);
      expect(GitCommitResponse.fromJson({'paths': 1}).paths, isNull);
      expect(
        GitCommitResponse.fromJson({'paths': <String, Object?>{}}).paths,
        isNull,
      );
      expect(GitCommitResponse.fromJson({'paths': <Object?>[]}).paths, isEmpty);
      expect(GitCommitResponse.fromJson({'paths': [1]}).paths, isNull);
      expect(GitCommitResponse.fromJson({'paths': [null]}).paths, isNull);
      expect(GitCommitResponse.fromJson({'paths': ['a', 1]}).paths, isNull);
      expect(GitCommitResponse.fromJson({'paths': ['a']}).paths, ['a']);
    });

    test('resolvedStatus：status 优先，缺失回退 git，两者皆无 → null', () {
      expect(
        GitCommitResponse.fromJson({'status': {'branch': 's'}}).resolvedStatus!.branch,
        's',
      );
      expect(
        GitCommitResponse.fromJson({'git': {'branch': 'g'}}).resolvedStatus!.branch,
        'g',
      );
      expect(
        GitCommitResponse.fromJson({
          'status': {'branch': 's'},
          'git': {'branch': 'g'},
        }).resolvedStatus!.branch,
        's',
      );
      expect(GitCommitResponse.fromJson(const {}).resolvedStatus, isNull);
      // 空 status 映射是有效值（?? 而非 ||，不回退到 git）
      final emptyMapStatus = GitCommitResponse.fromJson({
        'status': <String, Object?>{},
        'git': {'branch': 'g'},
      });
      expect(emptyMapStatus.resolvedStatus, isNotNull);
      expect(emptyMapStatus.resolvedStatus!.branch, isNull);
    });

    test('shortSHA：trim 后为空 → null，否则 trim 值', () {
      expect(GitCommitResponse.fromJson({'commit': ' abc1234 '}).shortSHA, 'abc1234');
      expect(GitCommitResponse.fromJson({'commit': 'abc1234'}).shortSHA, 'abc1234');
      expect(GitCommitResponse.fromJson({'commit': '\n abc \t'}).shortSHA, 'abc');
      expect(GitCommitResponse.fromJson({'commit': ''}).shortSHA, isNull);
      expect(GitCommitResponse.fromJson({'commit': '   '}).shortSHA, isNull);
      expect(GitCommitResponse.fromJson({'commit': '\t\n'}).shortSHA, isNull);
      expect(GitCommitResponse.fromJson(const {}).shortSHA, isNull);
      expect(GitCommitResponse.fromJson({'commit': null}).shortSHA, isNull);
    });

    test('== 阶梯式（5 字段逐项差一，paths 含 _listEquals 三条路径）+ hashCode / toString', () {
      final basePaths = <String>['a.dart', 'b.dart'];
      final base = GitCommitResponse(
        ok: true,
        commit: 'abc1234',
        paths: basePaths,
        status: const GitStatus(branch: 'main'),
        git: const GitStatus(branch: 'dev'),
      );
      final same = GitCommitResponse(
        ok: true,
        commit: 'abc1234',
        // 不同 List 实例、同内容 → 走 _listEquals 的逐元素比较分支
        paths: List<String>.of(basePaths),
        status: const GitStatus(branch: 'main'),
        git: const GitStatus(branch: 'dev'),
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      // 同一 List 实例 → _listEquals 的 identical 快路径
      expect(base == GitCommitResponse(ok: true, commit: 'abc1234', paths: basePaths, status: const GitStatus(branch: 'main'), git: const GitStatus(branch: 'dev')), isTrue);

      GitCommitResponse variant({
        bool? ok,
        String? commit,
        List<String>? paths,
        GitStatus? status,
        GitStatus? git,
      }) {
        return GitCommitResponse(
          ok: ok ?? true,
          commit: commit ?? 'abc1234',
          paths: paths ?? basePaths,
          status: status ?? const GitStatus(branch: 'main'),
          git: git ?? const GitStatus(branch: 'dev'),
        );
      }

      expect(base == variant(ok: false), isFalse); // ok 差
      expect(base == variant(commit: 'deadbeef'), isFalse); // commit 差
      expect(base == variant(paths: <String>['a.dart']), isFalse); // paths 长度差
      expect(base == variant(paths: <String>[]), isFalse); // paths 长度差（空）
      expect(base == variant(paths: <String>['a.dart', 'c.dart']), isFalse); // paths 同长度逐元素差
      expect(base == variant(status: const GitStatus(branch: 'other')), isFalse); // status 差
      expect(base == variant(git: const GitStatus(branch: 'other')), isFalse); // git 差

      // paths null ↔ 非 null（_listEquals 的 null 分支）
      expect(base == const GitCommitResponse(), isFalse);
      expect(
        const GitCommitResponse(paths: <String>['a']) == const GitCommitResponse(),
        isFalse,
      );
      expect(
        const GitCommitResponse() == const GitCommitResponse(paths: <String>[]),
        isFalse,
      );
      expect(const GitCommitResponse() == const GitCommitResponse(), isTrue);
      expect(const GitCommitResponse().hashCode, const GitCommitResponse().hashCode);
      expect(base == Object(), isFalse);

      expect(base.toString(), 'GitCommitResponse(ok: true, commit: abc1234)');
      expect(
        GitCommitResponse.fromJson(const {}).toString(),
        'GitCommitResponse(ok: null, commit: null)',
      );
    });
  });

  group('GitCommitMessageResponse', () {
    test('fromJson：正常三字段', () {
      final response = GitCommitMessageResponse.fromJson({
        'ok': true,
        'message': 'feat: 提交信息',
        'truncated': false,
      });
      expect(response.ok, true);
      expect(response.message, 'feat: 提交信息');
      expect(response.truncated, false);
    });

    test('fromJson：键缺失 / 显式 null / 错型 / lossy', () {
      final empty = GitCommitMessageResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.message, isNull);
      expect(empty.truncated, isNull);

      final nulls = GitCommitMessageResponse.fromJson({
        'ok': null,
        'message': null,
        'truncated': null,
      });
      expect(nulls.ok, isNull);
      expect(nulls.message, isNull);
      expect(nulls.truncated, isNull);

      expect(GitCommitMessageResponse.fromJson({'ok': 'yes'}).ok, true);
      expect(GitCommitMessageResponse.fromJson({'ok': 0}).ok, false);
      expect(GitCommitMessageResponse.fromJson({'ok': 2}).ok, isNull);
      expect(GitCommitMessageResponse.fromJson({'ok': []}).ok, isNull);
      expect(GitCommitMessageResponse.fromJson({'message': 1}).message, '1');
      expect(GitCommitMessageResponse.fromJson({'message': []}).message, isNull);
      expect(GitCommitMessageResponse.fromJson({'truncated': 1}).truncated, true);
      expect(GitCommitMessageResponse.fromJson({'truncated': 'no'}).truncated, false);
      expect(GitCommitMessageResponse.fromJson({'truncated': 'maybe'}).truncated, isNull);
      expect(GitCommitMessageResponse.fromJson({'truncated': {}}).truncated, isNull);
    });

    test('== 阶梯式（3 字段逐项差一）+ hashCode / toString', () {
      const base = GitCommitMessageResponse(ok: true, message: 'm', truncated: true);
      const same = GitCommitMessageResponse(ok: true, message: 'm', truncated: true);
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(base == const GitCommitMessageResponse(ok: false, message: 'm', truncated: true), isFalse); // ok 差
      expect(base == const GitCommitMessageResponse(ok: true, truncated: true), isFalse); // message 差（null）
      expect(base == const GitCommitMessageResponse(ok: true, message: 'n', truncated: true), isFalse); // message 差（值）
      expect(base == const GitCommitMessageResponse(ok: true, message: 'm'), isFalse); // truncated 差（null）
      expect(base == const GitCommitMessageResponse(ok: true, message: 'm', truncated: false), isFalse); // truncated 差（值）

      expect(
        const GitCommitMessageResponse() == const GitCommitMessageResponse(),
        isTrue,
      );
      expect(const GitCommitMessageResponse() == base, isFalse);
      expect(base == Object(), isFalse);

      expect(base.toString(), 'GitCommitMessageResponse(ok: true)');
      expect(
        GitCommitMessageResponse.fromJson(const {}).toString(),
        'GitCommitMessageResponse(ok: null)',
      );
    });
  });

  group('GitBranchesResponse', () {
    test('fromJson：正常 / 键缺失 / 显式 null / 错型', () {
      final hit = GitBranchesResponse.fromJson({
        'branches': {'is_git': true, 'current': 'main'},
      });
      expect(hit.branches!.isGit, true);
      expect(hit.branches!.current, 'main');

      final empty = GitBranchesResponse.fromJson(const {});
      expect(empty.branches, isNull);

      expect(GitBranchesResponse.fromJson({'branches': null}).branches, isNull);
      // optModel 的 `value is! Map` 分支
      expect(GitBranchesResponse.fromJson({'branches': 'bad'}).branches, isNull);
      expect(GitBranchesResponse.fromJson({'branches': 1}).branches, isNull);
      expect(GitBranchesResponse.fromJson({'branches': true}).branches, isNull);
      expect(
        GitBranchesResponse.fromJson({'branches': <Object?>[]}).branches,
        isNull,
      );
      // 空 Map 仍是有效对象 → 内层字段全 null
      final emptyInner =
          GitBranchesResponse.fromJson({'branches': <String, Object?>{}}).branches;
      expect(emptyInner, isNotNull);
      expect(emptyInner!.current, isNull);
      expect(emptyInner.isGit, isNull);
    });

    test('== / hashCode / toString', () {
      final a = GitBranchesResponse.fromJson({
        'branches': {'current': 'main', 'is_git': true},
      });
      final b = GitBranchesResponse.fromJson({
        'branches': {'current': 'main', 'is_git': true},
      });
      final c = GitBranchesResponse.fromJson({
        'branches': {'current': 'dev'},
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == GitBranchesResponse.fromJson(const {}), isFalse);
      expect(a == const GitBranchesResponse(), isFalse);
      expect(
        GitBranchesResponse.fromJson(const {}),
        const GitBranchesResponse(),
      );
      expect(
        GitBranchesResponse.fromJson(const {}).hashCode,
        const GitBranchesResponse().hashCode,
      );
      expect(a.hashCode == const GitBranchesResponse().hashCode, isFalse);
      expect(a == Object(), isFalse);
      expect(
        a.toString(),
        'GitBranchesResponse(branches: GitBranches(current: main, isGit: true))',
      );
      expect(
        GitBranchesResponse.fromJson(const {}).toString(),
        'GitBranchesResponse(branches: null)',
      );
    });
  });

  group('GitBranches', () {
    test('fromJson：正常全 9 字段', () {
      final branches = GitBranches.fromJson({
        'is_git': true,
        'current': 'main',
        'detached': false,
        'head': 'abc1234',
        'local': [
          {'name': 'main'},
          {'name': 'dev'},
        ],
        'remote': [
          {'name': 'origin/main'},
        ],
        'upstream': 'origin/main',
        'ahead': 1,
        'behind': 2,
      });
      expect(branches.isGit, true);
      expect(branches.current, 'main');
      expect(branches.detached, false);
      expect(branches.head, 'abc1234');
      expect(branches.local, hasLength(2));
      expect(branches.local!.first.name, 'main');
      expect(branches.local!.last.name, 'dev');
      expect(branches.remote!.single.name, 'origin/main');
      expect(branches.upstream, 'origin/main');
      expect(branches.ahead, 1);
      expect(branches.behind, 2);
    });

    test('fromJson：键缺失 / 显式 null → 全 null', () {
      final empty = GitBranches.fromJson(const {});
      expect(empty.isGit, isNull);
      expect(empty.current, isNull);
      expect(empty.detached, isNull);
      expect(empty.head, isNull);
      expect(empty.local, isNull);
      expect(empty.remote, isNull);
      expect(empty.upstream, isNull);
      expect(empty.ahead, isNull);
      expect(empty.behind, isNull);

      final nulls = GitBranches.fromJson({
        'is_git': null,
        'current': null,
        'detached': null,
        'head': null,
        'local': null,
        'remote': null,
        'upstream': null,
        'ahead': null,
        'behind': null,
      });
      expect(nulls.isGit, isNull);
      expect(nulls.current, isNull);
      expect(nulls.detached, isNull);
      expect(nulls.local, isNull);
      expect(nulls.remote, isNull);
      expect(nulls.upstream, isNull);
      expect(nulls.ahead, isNull);
      expect(nulls.behind, isNull);
    });

    test('fromJson：lossy 跨类型（标量 7 键）', () {
      final lossy = GitBranches.fromJson({
        'is_git': 'yes',
        'current': 1,
        'detached': 0,
        'head': 2.5,
        'upstream': true,
        'ahead': '3',
        'behind': 4.9,
      });
      expect(lossy.isGit, true);
      expect(lossy.current, '1');
      expect(lossy.detached, false);
      expect(lossy.head, '2.5');
      expect(lossy.upstream, 'true');
      expect(lossy.ahead, 3);
      expect(lossy.behind, 4);
      // 转换失败一律 null
      expect(GitBranches.fromJson({'is_git': 2}).isGit, isNull);
      expect(GitBranches.fromJson({'is_git': <Object?>[]}).isGit, isNull);
      expect(GitBranches.fromJson({'current': <Object?>[]}).current, isNull);
      expect(GitBranches.fromJson({'detached': 'maybe'}).detached, isNull);
      expect(GitBranches.fromJson({'ahead': 'many'}).ahead, isNull);
      expect(GitBranches.fromJson({'ahead': true}).ahead, isNull);
      expect(GitBranches.fromJson({'behind': '4.7'}).behind, 4);
      expect(GitBranches.fromJson({'behind': 1e20}).behind, isNull);
    });

    test('fromJson：local / remote 走 optModelList —— 非 List / 元素非 Map → 整数组 null', () {
      expect(GitBranches.fromJson({'local': 'bad'}).local, isNull);
      expect(GitBranches.fromJson({'local': 1}).local, isNull);
      expect(GitBranches.fromJson({'local': <String, Object?>{}}).local, isNull);
      expect(GitBranches.fromJson({'local': <Object?>[]}).local, isEmpty);
      expect(GitBranches.fromJson({'local': [1]}).local, isNull);
      expect(GitBranches.fromJson({'local': [null]}).local, isNull);
      expect(GitBranches.fromJson({'local': ['a']}).local, isNull);
      expect(GitBranches.fromJson({'remote': [1]}).remote, isNull);
      expect(GitBranches.fromJson({'remote': <Object?>[]}).remote, isEmpty);
      expect(
        GitBranches.fromJson({
          'local': [
            <String, Object?>{},
            {'name': 'dev'},
          ],
        }).local!.first.name,
        isNull,
      );
      expect(
        GitBranches.fromJson({
          'local': [
            {'name': 'main'},
            'x',
          ],
        }).local,
        isNull,
      );
    });

    test('== 阶梯式（9 字段逐项差一，local/remote 走 deepEquals）+ hashCode / toString', () {
      final baseLocal = <GitBranchRef>[const GitBranchRef(name: 'main', sha: 'a')];
      final baseRemote = <GitBranchRef>[const GitBranchRef(name: 'origin/main')];
      final base = GitBranches(
        isGit: true,
        current: 'main',
        detached: false,
        head: 'abc1234',
        local: baseLocal,
        remote: baseRemote,
        upstream: 'origin/main',
        ahead: 1,
        behind: 2,
      );
      final same = GitBranches(
        isGit: true,
        current: 'main',
        detached: false,
        head: 'abc1234',
        local: List<GitBranchRef>.of(baseLocal),
        remote: List<GitBranchRef>.of(baseRemote),
        upstream: 'origin/main',
        ahead: 1,
        behind: 2,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      GitBranches variant({
        bool? isGit,
        String? current,
        bool? detached,
        String? head,
        List<GitBranchRef>? local,
        List<GitBranchRef>? remote,
        String? upstream,
        int? ahead,
        int? behind,
      }) {
        return GitBranches(
          isGit: isGit ?? true,
          current: current ?? 'main',
          detached: detached ?? false,
          head: head ?? 'abc1234',
          local: local ?? baseLocal,
          remote: remote ?? baseRemote,
          upstream: upstream ?? 'origin/main',
          ahead: ahead ?? 1,
          behind: behind ?? 2,
        );
      }

      expect(base == variant(isGit: false), isFalse); // isGit 差
      expect(base == variant(current: 'dev'), isFalse); // current 差
      expect(base == variant(detached: true), isFalse); // detached 差
      expect(base == variant(head: 'deadbeef'), isFalse); // head 差
      expect(base == variant(upstream: 'origin/dev'), isFalse); // upstream 差
      expect(base == variant(ahead: 9), isFalse); // ahead 差
      expect(base == variant(behind: 9), isFalse); // behind 差
      // local：逐元素差 / 长度差 / 空
      expect(
        base == variant(local: <GitBranchRef>[const GitBranchRef(name: 'main', sha: 'b')]),
        isFalse,
      );
      expect(base == variant(local: <GitBranchRef>[const GitBranchRef(name: 'main')]), isFalse);
      expect(base == variant(local: <GitBranchRef>[]), isFalse);
      // remote：逐元素差
      expect(
        base == variant(remote: <GitBranchRef>[const GitBranchRef(name: 'upstream/main')]),
        isFalse,
      );
      // 集合 null ↔ 非 null / 空（deepEquals 的 identical 与 null 分支）
      expect(base == const GitBranches(), isFalse);
      expect(GitBranches(local: baseLocal) == const GitBranches(), isFalse);
      expect(
        const GitBranches() == const GitBranches(local: <GitBranchRef>[]),
        isFalse,
      );
      expect(const GitBranches() == const GitBranches(), isTrue);
      expect(const GitBranches().hashCode == const GitBranches(local: null).hashCode, isTrue);
      expect(base.hashCode == const GitBranches().hashCode, isFalse);
      expect(base == Object(), isFalse);

      expect(base.toString(), 'GitBranches(current: main, isGit: true)');
      expect(
        GitBranches.fromJson(const {}).toString(),
        'GitBranches(current: null, isGit: null)',
      );
    });
  });

  group('GitBranchRef', () {
    test('fromJson：正常全 9 字段', () {
      final ref = GitBranchRef.fromJson({
        'name': 'main',
        'sha': 'abc1234',
        'updated': 1723700000,
        'updated_relative': '2 小时前',
        'author': 'me',
        'subject': 'fix: x',
        'upstream': 'origin/main',
        'ahead': 1,
        'behind': 2,
      });
      expect(ref.name, 'main');
      expect(ref.sha, 'abc1234');
      expect(ref.updated, 1723700000);
      expect(ref.updatedRelative, '2 小时前');
      expect(ref.author, 'me');
      expect(ref.subject, 'fix: x');
      expect(ref.upstream, 'origin/main');
      expect(ref.ahead, 1);
      expect(ref.behind, 2);
    });

    test('fromJson：键缺失 / 显式 null → 全 null', () {
      final empty = GitBranchRef.fromJson(const {});
      expect(empty.name, isNull);
      expect(empty.sha, isNull);
      expect(empty.updated, isNull);
      expect(empty.updatedRelative, isNull);
      expect(empty.author, isNull);
      expect(empty.subject, isNull);
      expect(empty.upstream, isNull);
      expect(empty.ahead, isNull);
      expect(empty.behind, isNull);

      final nulls = GitBranchRef.fromJson({
        'name': null,
        'sha': null,
        'updated': null,
        'updated_relative': null,
        'author': null,
        'subject': null,
        'upstream': null,
        'ahead': null,
        'behind': null,
      });
      expect(nulls.name, isNull);
      expect(nulls.updated, isNull);
      expect(nulls.updatedRelative, isNull);
      expect(nulls.behind, isNull);
    });

    test('fromJson：lossy 跨类型 + snake 单键（camelCase 不认）', () {
      final lossy = GitBranchRef.fromJson({
        'name': 1,
        'sha': true,
        'updated': '123',
        'updated_relative': 2.5,
        'author': <Object?>[],
        'subject': <String, Object?>{},
        'upstream': false,
        'ahead': 3.9,
        'behind': 'x',
      });
      expect(lossy.name, '1');
      expect(lossy.sha, 'true');
      expect(lossy.updated, 123);
      expect(lossy.updatedRelative, '2.5');
      expect(lossy.author, isNull);
      expect(lossy.subject, isNull);
      expect(lossy.upstream, 'false');
      expect(lossy.ahead, 3);
      expect(lossy.behind, isNull);
      expect(GitBranchRef.fromJson({'updated': 1e20}).updated, isNull);
      expect(GitBranchRef.fromJson({'updated': '99.9'}).updated, 99);

      // 本批无 firstKey 回退链：camelCase 键一律不被识别
      expect(GitBranchRef.fromJson({'updatedRelative': 'x'}).updatedRelative, isNull);
      expect(GitBranchRef.fromJson({'name': 'a', 'updatedRelative': 'x'}).name, 'a');
    });

    test('== 阶梯式（9 字段逐项差一）+ hashCode / toString', () {
      const base = GitBranchRef(
        name: 'main',
        sha: 'abc1234',
        updated: 1723700000,
        updatedRelative: '2 小时前',
        author: 'me',
        subject: 'fix: x',
        upstream: 'origin/main',
        ahead: 1,
        behind: 2,
      );
      const same = GitBranchRef(
        name: 'main',
        sha: 'abc1234',
        updated: 1723700000,
        updatedRelative: '2 小时前',
        author: 'me',
        subject: 'fix: x',
        upstream: 'origin/main',
        ahead: 1,
        behind: 2,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(base == const GitBranchRef(name: 'dev', sha: 'abc1234', updated: 1723700000, updatedRelative: '2 小时前', author: 'me', subject: 'fix: x', upstream: 'origin/main', ahead: 1, behind: 2), isFalse); // name 差
      expect(base == const GitBranchRef(name: 'main', updated: 1723700000, updatedRelative: '2 小时前', author: 'me', subject: 'fix: x', upstream: 'origin/main', ahead: 1, behind: 2), isFalse); // sha 差
      expect(base == const GitBranchRef(name: 'main', sha: 'abc1234', updatedRelative: '2 小时前', author: 'me', subject: 'fix: x', upstream: 'origin/main', ahead: 1, behind: 2), isFalse); // updated 差
      expect(base == const GitBranchRef(name: 'main', sha: 'abc1234', updated: 1723700000, author: 'me', subject: 'fix: x', upstream: 'origin/main', ahead: 1, behind: 2), isFalse); // updatedRelative 差
      expect(base == const GitBranchRef(name: 'main', sha: 'abc1234', updated: 1723700000, updatedRelative: '2 小时前', subject: 'fix: x', upstream: 'origin/main', ahead: 1, behind: 2), isFalse); // author 差
      expect(base == const GitBranchRef(name: 'main', sha: 'abc1234', updated: 1723700000, updatedRelative: '2 小时前', author: 'me', upstream: 'origin/main', ahead: 1, behind: 2), isFalse); // subject 差
      expect(base == const GitBranchRef(name: 'main', sha: 'abc1234', updated: 1723700000, updatedRelative: '2 小时前', author: 'me', subject: 'fix: x', ahead: 1, behind: 2), isFalse); // upstream 差
      expect(base == const GitBranchRef(name: 'main', sha: 'abc1234', updated: 1723700000, updatedRelative: '2 小时前', author: 'me', subject: 'fix: x', upstream: 'origin/main', behind: 2), isFalse); // ahead 差
      expect(base == const GitBranchRef(name: 'main', sha: 'abc1234', updated: 1723700000, updatedRelative: '2 小时前', author: 'me', subject: 'fix: x', upstream: 'origin/main', ahead: 1), isFalse); // behind 差

      expect(const GitBranchRef() == const GitBranchRef(), isTrue);
      expect(const GitBranchRef() == base, isFalse);
      expect(base == Object(), isFalse);
      expect(base.hashCode == const GitBranchRef().hashCode, isFalse);

      expect(base.toString(), 'GitBranchRef(name: main, sha: abc1234)');
      expect(
        GitBranchRef.fromJson(const {}).toString(),
        'GitBranchRef(name: null, sha: null)',
      );
    });
  });

  group('GitCheckoutResponse', () {
    test('fromJson：正常全 12 字段', () {
      final response = GitCheckoutResponse.fromJson({
        'ok': true,
        'message': '已切换',
        'status': {'is_git': true, 'branch': 'dev'},
        'git': {'branch': 'gitBranch'},
        'branches': {'current': 'dev'},
        'current_branch': 'dev',
        'stash_name': 'stash-1',
        'stashed': true,
        'restored_stash': {'ref': 'stash@{0}', 'branch': 'dev', 'message': 'm'},
        'restore_failed': true,
        'restore_error': '冲突',
        'restore_stash': {'ref': 'stash@{1}'},
      });
      expect(response.ok, true);
      expect(response.message, '已切换');
      expect(response.status!.branch, 'dev');
      expect(response.git!.branch, 'gitBranch');
      expect(response.branches!.current, 'dev');
      expect(response.currentBranch, 'dev');
      expect(response.stashName, 'stash-1');
      expect(response.stashed, true);
      expect(response.restoredStash!.ref, 'stash@{0}');
      expect(response.restoredStash!.branch, 'dev');
      expect(response.restoreFailed, true);
      expect(response.restoreError, '冲突');
      expect(response.restoreStash!.ref, 'stash@{1}');
    });

    test('fromJson：键缺失 / 显式 null → 全 null', () {
      final empty = GitCheckoutResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.message, isNull);
      expect(empty.status, isNull);
      expect(empty.git, isNull);
      expect(empty.branches, isNull);
      expect(empty.currentBranch, isNull);
      expect(empty.stashName, isNull);
      expect(empty.stashed, isNull);
      expect(empty.restoredStash, isNull);
      expect(empty.restoreFailed, isNull);
      expect(empty.restoreError, isNull);
      expect(empty.restoreStash, isNull);

      final nulls = GitCheckoutResponse.fromJson({
        'ok': null,
        'message': null,
        'status': null,
        'git': null,
        'branches': null,
        'current_branch': null,
        'stash_name': null,
        'stashed': null,
        'restored_stash': null,
        'restore_failed': null,
        'restore_error': null,
        'restore_stash': null,
      });
      expect(nulls.ok, isNull);
      expect(nulls.status, isNull);
      expect(nulls.branches, isNull);
      expect(nulls.currentBranch, isNull);
      expect(nulls.stashName, isNull);
      expect(nulls.stashed, isNull);
      expect(nulls.restoredStash, isNull);
      expect(nulls.restoreFailed, isNull);
      expect(nulls.restoreError, isNull);
      expect(nulls.restoreStash, isNull);
    });

    test('fromJson：lossy 跨类型 + 嵌套错型', () {
      final lossy = GitCheckoutResponse.fromJson({
        'ok': 'yes',
        'message': 1,
        'current_branch': 2.5,
        'stash_name': true,
        'stashed': 0,
        'restore_failed': 'no',
        'restore_error': 7,
      });
      expect(lossy.ok, true);
      expect(lossy.message, '1');
      expect(lossy.currentBranch, '2.5');
      expect(lossy.stashName, 'true');
      expect(lossy.stashed, false);
      expect(lossy.restoreFailed, false);
      expect(lossy.restoreError, '7');
      expect(GitCheckoutResponse.fromJson({'ok': 2}).ok, isNull);
      expect(GitCheckoutResponse.fromJson({'stashed': 'maybe'}).stashed, isNull);

      // 嵌套模型：'bad' / 数字 / bool / List 一律 null（optModel 的 is! Map 分支）
      for (final bad in <Object?>['bad', 1, true, <Object?>[]]) {
        expect(GitCheckoutResponse.fromJson({'status': bad}).status, isNull);
        expect(GitCheckoutResponse.fromJson({'git': bad}).git, isNull);
        expect(GitCheckoutResponse.fromJson({'branches': bad}).branches, isNull);
        expect(
          GitCheckoutResponse.fromJson({'restored_stash': bad}).restoredStash,
          isNull,
        );
        expect(
          GitCheckoutResponse.fromJson({'restore_stash': bad}).restoreStash,
          isNull,
        );
      }
      expect(
        GitCheckoutResponse.fromJson({'branches': <String, Object?>{}}).branches!.current,
        isNull,
      );
      expect(
        GitCheckoutResponse.fromJson({'restored_stash': <String, Object?>{}})
            .restoredStash!
            .ref,
        isNull,
      );
      // camelCase 键不认（本批无 firstKey）
      expect(
        GitCheckoutResponse.fromJson({'currentBranch': 'dev'}).currentBranch,
        isNull,
      );
    });

    test('resolvedStatus：status 优先 → git 兜底 → null', () {
      expect(
        GitCheckoutResponse.fromJson({'status': {'branch': 's'}}).resolvedStatus!.branch,
        's',
      );
      expect(
        GitCheckoutResponse.fromJson({'git': {'branch': 'g'}}).resolvedStatus!.branch,
        'g',
      );
      expect(
        GitCheckoutResponse.fromJson({
          'status': {'branch': 's'},
          'git': {'branch': 'g'},
        }).resolvedStatus!.branch,
        's',
      );
      expect(GitCheckoutResponse.fromJson(const {}).resolvedStatus, isNull);
      // 空 status 映射是有效值 → 不回退 git
      expect(
        GitCheckoutResponse.fromJson({
          'status': <String, Object?>{},
          'git': {'branch': 'g'},
        }).resolvedStatus!.branch,
        isNull,
      );
    });

    test('== 阶梯式（12 字段逐项差一）+ hashCode / toString', () {
      final baseBranches = GitBranches.fromJson({'current': 'main'});
      final baseRestored = GitRestoredStash.fromJson({
        'ref': 'stash@{0}',
        'branch': 'main',
      });
      final baseRestoreStash = GitRestoredStash.fromJson({'ref': 'stash@{1}'});
      final base = GitCheckoutResponse(
        ok: true,
        message: '已切换',
        status: const GitStatus(branch: 'dev'),
        git: const GitStatus(branch: 'gitBranch'),
        branches: baseBranches,
        currentBranch: 'dev',
        stashName: 'stash-1',
        stashed: true,
        restoredStash: baseRestored,
        restoreFailed: false,
        restoreError: 'err',
        restoreStash: baseRestoreStash,
      );
      final same = GitCheckoutResponse(
        ok: true,
        message: '已切换',
        status: const GitStatus(branch: 'dev'),
        git: const GitStatus(branch: 'gitBranch'),
        branches: GitBranches.fromJson({'current': 'main'}),
        currentBranch: 'dev',
        stashName: 'stash-1',
        stashed: true,
        restoredStash: GitRestoredStash.fromJson({
          'ref': 'stash@{0}',
          'branch': 'main',
        }),
        restoreFailed: false,
        restoreError: 'err',
        restoreStash: GitRestoredStash.fromJson({'ref': 'stash@{1}'}),
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      GitCheckoutResponse variant({
        bool? ok,
        String? message,
        GitStatus? status,
        GitStatus? git,
        GitBranches? branches,
        String? currentBranch,
        String? stashName,
        bool? stashed,
        GitRestoredStash? restoredStash,
        bool? restoreFailed,
        String? restoreError,
        GitRestoredStash? restoreStash,
      }) {
        return GitCheckoutResponse(
          ok: ok ?? true,
          message: message ?? '已切换',
          status: status ?? const GitStatus(branch: 'dev'),
          git: git ?? const GitStatus(branch: 'gitBranch'),
          branches: branches ?? baseBranches,
          currentBranch: currentBranch ?? 'dev',
          stashName: stashName ?? 'stash-1',
          stashed: stashed ?? true,
          restoredStash: restoredStash ?? baseRestored,
          restoreFailed: restoreFailed ?? false,
          restoreError: restoreError ?? 'err',
          restoreStash: restoreStash ?? baseRestoreStash,
        );
      }

      expect(base == variant(ok: false), isFalse); // ok 差
      expect(base == variant(message: 'other'), isFalse); // message 差
      expect(base == variant(status: const GitStatus(branch: 'other')), isFalse); // status 差
      expect(base == variant(git: const GitStatus(branch: 'other')), isFalse); // git 差
      expect(base == variant(branches: GitBranches.fromJson({'current': 'other'})), isFalse); // branches 差
      expect(base == variant(currentBranch: 'main'), isFalse); // currentBranch 差
      expect(base == variant(stashName: 'stash-2'), isFalse); // stashName 差
      expect(base == variant(stashed: false), isFalse); // stashed 差
      expect(base == variant(restoredStash: GitRestoredStash.fromJson({'ref': 'other'})), isFalse); // restoredStash 差
      expect(base == variant(restoreFailed: true), isFalse); // restoreFailed 差
      expect(base == variant(restoreError: 'other'), isFalse); // restoreError 差
      expect(base == variant(restoreStash: GitRestoredStash.fromJson({'ref': 'other'})), isFalse); // restoreStash 差

      // 各字段 null ↔ 非 null（全部走 fromJson 构造，逐字段单独对空对象比较）
      expect(base == const GitCheckoutResponse(), isFalse);
      expect(
        GitCheckoutResponse.fromJson({'ok': true}) == const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({'message': '已切换'}) ==
            const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({
          'status': {'branch': 'dev'},
        }) == const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({'git': {'branch': 'gitBranch'}}) ==
            const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({
          'branches': {'current': 'main'},
        }) == const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({'current_branch': 'dev'}) ==
            const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({'stash_name': 'stash-1'}) ==
            const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({'stashed': true}) ==
            const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({
          'restored_stash': {'ref': 'stash@{0}'},
        }) == const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({'restore_failed': false}) ==
            const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({'restore_error': 'err'}) ==
            const GitCheckoutResponse(),
        isFalse,
      );
      expect(
        GitCheckoutResponse.fromJson({
          'restore_stash': {'ref': 'stash@{1}'},
        }) == const GitCheckoutResponse(),
        isFalse,
      );
      expect(const GitCheckoutResponse() == const GitCheckoutResponse(), isTrue);
      expect(
        const GitCheckoutResponse().hashCode,
        const GitCheckoutResponse().hashCode,
      );
      expect(base == Object(), isFalse);

      expect(base.toString(), 'GitCheckoutResponse(ok: true, currentBranch: dev)');
      expect(
        GitCheckoutResponse.fromJson(const {}).toString(),
        'GitCheckoutResponse(ok: null, currentBranch: null)',
      );
    });
  });

  group('GitRestoredStash', () {
    test('fromJson：正常三字段 / 缺失 / 显式 null / lossy', () {
      final stash = GitRestoredStash.fromJson({
        'ref': 'stash@{0}',
        'branch': 'main',
        'message': 'WIP',
      });
      expect(stash.ref, 'stash@{0}');
      expect(stash.branch, 'main');
      expect(stash.message, 'WIP');

      final empty = GitRestoredStash.fromJson(const {});
      expect(empty.ref, isNull);
      expect(empty.branch, isNull);
      expect(empty.message, isNull);

      final nulls = GitRestoredStash.fromJson({
        'ref': null,
        'branch': null,
        'message': null,
      });
      expect(nulls.ref, isNull);
      expect(nulls.branch, isNull);
      expect(nulls.message, isNull);

      final lossy = GitRestoredStash.fromJson({
        'ref': 1,
        'branch': 2.5,
        'message': true,
      });
      expect(lossy.ref, '1');
      expect(lossy.branch, '2.5');
      expect(lossy.message, 'true');
      expect(GitRestoredStash.fromJson({'ref': <Object?>[]}).ref, isNull);
      expect(GitRestoredStash.fromJson({'branch': <String, Object?>{}}).branch, isNull);
    });

    test('== 阶梯式（3 字段逐项差一）+ hashCode / toString', () {
      const base = GitRestoredStash(ref: 'stash@{0}', branch: 'main', message: 'WIP');
      const same = GitRestoredStash(ref: 'stash@{0}', branch: 'main', message: 'WIP');
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(base == const GitRestoredStash(branch: 'main', message: 'WIP'), isFalse); // ref 差
      expect(base == const GitRestoredStash(ref: 'stash@{0}', message: 'WIP'), isFalse); // branch 差
      expect(base == const GitRestoredStash(ref: 'stash@{0}', branch: 'main'), isFalse); // message 差
      expect(
        base == const GitRestoredStash(ref: 'other', branch: 'main', message: 'WIP'),
        isFalse,
      );

      expect(const GitRestoredStash() == const GitRestoredStash(), isTrue);
      expect(const GitRestoredStash() == base, isFalse);
      expect(base == Object(), isFalse);

      expect(base.toString(), 'GitRestoredStash(ref: stash@{0}, branch: main)');
      expect(
        GitRestoredStash.fromJson(const {}).toString(),
        'GitRestoredStash(ref: null, branch: null)',
      );
    });
  });

  group('GitDiffResponse', () {
    test('fromJson：正常 / 缺失 / null / 错型', () {
      final hit = GitDiffResponse.fromJson({
        'diff': {'path': 'lib/a.dart', 'kind': 'modified'},
      });
      expect(hit.diff!.path, 'lib/a.dart');
      expect(hit.diff!.kind, 'modified');

      expect(GitDiffResponse.fromJson(const {}).diff, isNull);
      expect(GitDiffResponse.fromJson({'diff': null}).diff, isNull);
      expect(GitDiffResponse.fromJson({'diff': 'bad'}).diff, isNull);
      expect(GitDiffResponse.fromJson({'diff': 1}).diff, isNull);
      expect(GitDiffResponse.fromJson({'diff': true}).diff, isNull);
      expect(GitDiffResponse.fromJson({'diff': <Object?>[]}).diff, isNull);
      expect(
        GitDiffResponse.fromJson({'diff': <String, Object?>{}}).diff!.path,
        isNull,
      );
    });

    test('== / hashCode / toString', () {
      final a = GitDiffResponse.fromJson({
        'diff': {'path': 'lib/a.dart'},
      });
      final b = GitDiffResponse.fromJson({
        'diff': {'path': 'lib/a.dart'},
      });
      final c = GitDiffResponse.fromJson({
        'diff': {'path': 'lib/b.dart'},
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == GitDiffResponse.fromJson(const {}), isFalse);
      expect(GitDiffResponse.fromJson(const {}), const GitDiffResponse());
      expect(
        GitDiffResponse.fromJson(const {}).hashCode,
        const GitDiffResponse().hashCode,
      );
      expect(a.hashCode == const GitDiffResponse().hashCode, isFalse);
      expect(a == Object(), isFalse);
      expect(a.toString(), 'GitDiffResponse(diff: GitDiff(path: lib/a.dart, kind: null))');
      expect(
        GitDiffResponse.fromJson(const {}).toString(),
        'GitDiffResponse(diff: null)',
      );
    });
  });

  group('GitDiff', () {
    test('fromJson：正常全 7 字段', () {
      final diff = GitDiff.fromJson({
        'path': 'lib/a.dart',
        'kind': 'modified',
        'binary': false,
        'too_large': true,
        'additions': 12,
        'deletions': 3,
        'diff': '@@ -1 +1 @@',
      });
      expect(diff.path, 'lib/a.dart');
      expect(diff.kind, 'modified');
      expect(diff.binary, false);
      expect(diff.tooLarge, true);
      expect(diff.additions, 12);
      expect(diff.deletions, 3);
      expect(diff.diff, '@@ -1 +1 @@');
    });

    test('fromJson：键缺失 / 显式 null → 全 null', () {
      final empty = GitDiff.fromJson(const {});
      expect(empty.path, isNull);
      expect(empty.kind, isNull);
      expect(empty.binary, isNull);
      expect(empty.tooLarge, isNull);
      expect(empty.additions, isNull);
      expect(empty.deletions, isNull);
      expect(empty.diff, isNull);

      final nulls = GitDiff.fromJson({
        'path': null,
        'kind': null,
        'binary': null,
        'too_large': null,
        'additions': null,
        'deletions': null,
        'diff': null,
      });
      expect(nulls.path, isNull);
      expect(nulls.binary, isNull);
      expect(nulls.tooLarge, isNull);
      expect(nulls.diff, isNull);
    });

    test('fromJson：lossy 跨类型 + snake 单键', () {
      final lossy = GitDiff.fromJson({
        'path': 1,
        'kind': false,
        'binary': 'yes',
        'too_large': 0,
        'additions': '12',
        'deletions': 3.9,
        'diff': 2.5,
      });
      expect(lossy.path, '1');
      expect(lossy.kind, 'false');
      expect(lossy.binary, true);
      expect(lossy.tooLarge, false);
      expect(lossy.additions, 12);
      expect(lossy.deletions, 3);
      expect(lossy.diff, '2.5');
      expect(GitDiff.fromJson({'binary': 'maybe'}).binary, isNull);
      expect(GitDiff.fromJson({'too_large': <Object?>[]}).tooLarge, isNull);
      expect(GitDiff.fromJson({'additions': true}).additions, isNull);
      expect(GitDiff.fromJson({'deletions': 1e20}).deletions, isNull);
      expect(GitDiff.fromJson({'diff': <Object?>[]}).diff, isNull);
      // camelCase 不认
      expect(GitDiff.fromJson({'tooLarge': true}).tooLarge, isNull);
    });

    test('== 阶梯式（7 字段逐项差一）+ hashCode / toString', () {
      const base = GitDiff(
        path: 'lib/a.dart',
        kind: 'modified',
        binary: false,
        tooLarge: true,
        additions: 12,
        deletions: 3,
        diff: '@@',
      );
      const same = GitDiff(
        path: 'lib/a.dart',
        kind: 'modified',
        binary: false,
        tooLarge: true,
        additions: 12,
        deletions: 3,
        diff: '@@',
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(base == const GitDiff(kind: 'modified', binary: false, tooLarge: true, additions: 12, deletions: 3, diff: '@@'), isFalse); // path 差
      expect(base == const GitDiff(path: 'lib/a.dart', binary: false, tooLarge: true, additions: 12, deletions: 3, diff: '@@'), isFalse); // kind 差
      expect(base == const GitDiff(path: 'lib/a.dart', kind: 'modified', tooLarge: true, additions: 12, deletions: 3, diff: '@@'), isFalse); // binary 差
      expect(base == const GitDiff(path: 'lib/a.dart', kind: 'modified', binary: false, additions: 12, deletions: 3, diff: '@@'), isFalse); // tooLarge 差
      expect(base == const GitDiff(path: 'lib/a.dart', kind: 'modified', binary: false, tooLarge: true, deletions: 3, diff: '@@'), isFalse); // additions 差
      expect(base == const GitDiff(path: 'lib/a.dart', kind: 'modified', binary: false, tooLarge: true, additions: 12, diff: '@@'), isFalse); // deletions 差
      expect(base == const GitDiff(path: 'lib/a.dart', kind: 'modified', binary: false, tooLarge: true, additions: 12, deletions: 3), isFalse); // diff 差
      expect(
        base == const GitDiff(path: 'other', kind: 'modified', binary: false, tooLarge: true, additions: 12, deletions: 3, diff: '@@'),
        isFalse,
      );

      expect(const GitDiff() == const GitDiff(), isTrue);
      expect(const GitDiff() == base, isFalse);
      expect(base == Object(), isFalse);
      expect(base.hashCode == const GitDiff().hashCode, isFalse);

      expect(base.toString(), 'GitDiff(path: lib/a.dart, kind: modified)');
      expect(
        GitDiff.fromJson(const {}).toString(),
        'GitDiff(path: null, kind: null)',
      );
    });
  });

  group('enum GitBranchMode', () {
    test('取值、声明顺序、index、name、toString（纯客户端枚举，无 JSON 解析入口）', () {
      // 实现只有 `enum GitBranchMode { local, remote }`——没有任何 fromJson /
      // parse / firstWhere 回退方法，因此「解析回退路径」在源码层面不存在，
      // 唯一可判定的契约是取值集合与顺序。
      expect(GitBranchMode.values, hasLength(2));
      expect(GitBranchMode.values, <GitBranchMode>[
        GitBranchMode.local,
        GitBranchMode.remote,
      ]);
      expect(GitBranchMode.local.index, 0);
      expect(GitBranchMode.remote.index, 1);
      expect(GitBranchMode.local.name, 'local');
      expect(GitBranchMode.remote.name, 'remote');
      expect(GitBranchMode.local.toString(), 'GitBranchMode.local');
      expect(GitBranchMode.remote.toString(), 'GitBranchMode.remote');
      // name ↔ 取值往返（作为「按名解析」的等价能力）
      expect(GitBranchMode.values.byName('remote'), GitBranchMode.remote);
      expect(GitBranchMode.values.first.name, 'local');
      expect(GitBranchMode.values.contains(GitBranchMode.remote), isTrue);
    });
  });

  group('GitCheckoutTarget', () {
    test('构造 + id 拼装（mode:ref:newBranch，含 null 拼装）', () {
      const local = GitCheckoutTarget(
        ref: 'feature/x',
        mode: GitBranchMode.local,
        newBranch: 'nb',
      );
      expect(local.ref, 'feature/x');
      expect(local.mode, GitBranchMode.local);
      expect(local.newBranch, 'nb');
      expect(local.track, isNull);
      expect(local.id, 'GitBranchMode.local:feature/x:nb');

      const remote = GitCheckoutTarget(
        ref: 'origin/main',
        mode: GitBranchMode.remote,
      );
      expect(remote.mode, GitBranchMode.remote);
      expect(remote.newBranch, isNull);
      expect(remote.id, 'GitBranchMode.remote:origin/main:null');

      const tracking = GitCheckoutTarget(
        ref: 'origin/dev',
        mode: GitBranchMode.remote,
        newBranch: 'dev',
        track: true,
      );
      expect(tracking.track, true);
      expect(tracking.id, 'GitBranchMode.remote:origin/dev:dev');

      // newBranch 缺省与显式 null 等价；track 不参与 id
      expect(
        const GitCheckoutTarget(ref: 'x', mode: GitBranchMode.local).id,
        const GitCheckoutTarget(ref: 'x', mode: GitBranchMode.local, newBranch: null).id,
      );
      expect(
        const GitCheckoutTarget(ref: 'x', mode: GitBranchMode.local, track: true).id ==
            const GitCheckoutTarget(ref: 'x', mode: GitBranchMode.local, track: false).id,
        isTrue,
      );
    });

    test('运行期构造（非常量实参）：const 构造器在运行期路径下行为一致', () {
      // 常量上下文里的 const 构造器在编译期就被规范化，运行期不在场；
      // 这里强制走运行期构造，覆盖构造器实体行。
      final refs = <String>['feature/x'];
      final runtime = GitCheckoutTarget(
        ref: refs.first,
        mode: GitBranchMode.values.last,
        newBranch: 'nb'.toUpperCase(),
        track: 1 > 0,
      );
      expect(runtime.ref, 'feature/x');
      expect(runtime.mode, GitBranchMode.remote);
      expect(runtime.newBranch, 'NB');
      expect(runtime.track, true);
      expect(runtime.id, 'GitBranchMode.remote:feature/x:NB');

      final twin = GitCheckoutTarget(
        ref: refs.first,
        mode: GitBranchMode.values.last,
        newBranch: 'nb'.toUpperCase(),
        track: 1 > 0,
      );
      expect(runtime, twin);
      expect(runtime.hashCode, twin.hashCode);
      expect(identical(runtime, twin), isFalse); // 非常量构造 → 两个不同实例
    });

    test('== 阶梯式（4 字段逐项差一）+ hashCode / toString', () {
      const base = GitCheckoutTarget(
        ref: 'feature/x',
        mode: GitBranchMode.local,
        newBranch: 'nb',
        track: true,
      );
      const same = GitCheckoutTarget(
        ref: 'feature/x',
        mode: GitBranchMode.local,
        newBranch: 'nb',
        track: true,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(
        base == const GitCheckoutTarget(ref: 'other', mode: GitBranchMode.local, newBranch: 'nb', track: true),
        isFalse,
      ); // ref 差
      expect(
        base == const GitCheckoutTarget(ref: 'feature/x', mode: GitBranchMode.remote, newBranch: 'nb', track: true),
        isFalse,
      ); // mode 差
      expect(
        base == const GitCheckoutTarget(ref: 'feature/x', mode: GitBranchMode.local, track: true),
        isFalse,
      ); // newBranch 差（null）
      expect(
        base == const GitCheckoutTarget(ref: 'feature/x', mode: GitBranchMode.local, newBranch: 'other', track: true),
        isFalse,
      ); // newBranch 差（值）
      expect(
        base == const GitCheckoutTarget(ref: 'feature/x', mode: GitBranchMode.local, newBranch: 'nb'),
        isFalse,
      ); // track 差（null）
      expect(
        base == const GitCheckoutTarget(ref: 'feature/x', mode: GitBranchMode.local, newBranch: 'nb', track: false),
        isFalse,
      ); // track 差（值）

      expect(
        const GitCheckoutTarget(ref: 'x', mode: GitBranchMode.local) ==
            const GitCheckoutTarget(ref: 'x', mode: GitBranchMode.local),
        isTrue,
      );
      expect(
        const GitCheckoutTarget(ref: 'x', mode: GitBranchMode.local) == base,
        isFalse,
      );
      expect(base == Object(), isFalse);
      expect(
        base.hashCode ==
            const GitCheckoutTarget(ref: 'x', mode: GitBranchMode.remote).hashCode,
        isFalse,
      );

      expect(base.toString(), 'GitCheckoutTarget(ref: feature/x, mode: GitBranchMode.local)');
      expect(
        const GitCheckoutTarget(ref: 'r', mode: GitBranchMode.remote).toString(),
        'GitCheckoutTarget(ref: r, mode: GitBranchMode.remote)',
      );
    });
  });

  group('双键口径：本批 13 类均为 snake 单键，实现无 firstKey 回退链', () {
    test('camelCase 键一律不被识别', () {
      // `grep -n firstKey lib/core/models/git_workspace.dart` 无命中；
      // 本批 fromJson 全部是单键 lossyXxx/optModel 调用，camelCase 是「不认」而非回退。
      expect(GitBranches.fromJson({'isGit': true}).isGit, isNull);
      expect(GitBranches.fromJson({'isGit': true, 'is_git': true}).isGit, true);
      expect(GitBranches.fromJson({'updatedRelative': 'x'}).current, isNull);
      expect(GitBranchRef.fromJson({'updatedRelative': 'x'}).updatedRelative, isNull);
      expect(GitDiff.fromJson({'tooLarge': true}).tooLarge, isNull);
      expect(GitCheckoutResponse.fromJson({'currentBranch': 'x'}).currentBranch, isNull);
      expect(
        GitCheckoutResponse.fromJson({'restoreError': 'x'}).restoreError,
        isNull,
      );
      expect(GitCheckoutResponse.fromJson({'restoredStash': {'ref': 'r'}}).restoredStash, isNull);
      expect(GitCommitResponse.fromJson({'paths': ['a'], 'path': ['b']}).paths, ['a']);
      // snake 命中才生效
      expect(GitCheckoutResponse.fromJson({'current_branch': 'x'}).currentBranch, 'x');
      expect(GitDiff.fromJson({'too_large': true}).tooLarge, true);
    });
  });
}
