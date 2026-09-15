import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';

/// git_workspace.dart 第 6–388 行（7 个类）补测。
/// 风格对照 `test/core/models/server_catalog_extra_test.dart`：
/// 每个类做「正常键 / 缺失 / null / 错型」四路 fromJson，外加阶梯式 `==`
/// （n 个字段 → n 个变体，逐字段各差一项，保证 `&&` 每一行比较都被执行）。
void main() {
  group('GitInfoResponse', () {
    test('fromJson：命中 / null / 缺失 / 非 Map', () {
      final hit = GitInfoResponse.fromJson({
        'git': {'branch': 'main', 'is_git': true},
      });
      expect(hit.git!.branch, 'main');
      expect(hit.git!.isGit, true);

      expect(GitInfoResponse.fromJson({'git': null}).git, isNull);
      expect(GitInfoResponse.fromJson(const {}).git, isNull);
      // optModel 的 `value is! Map` 分支：字符串 / 列表 / 数字一律 null
      expect(GitInfoResponse.fromJson({'git': 'bad'}).git, isNull);
      expect(GitInfoResponse.fromJson({'git': [1]}).git, isNull);
      expect(GitInfoResponse.fromJson({'git': 1}).git, isNull);
      expect(GitInfoResponse.fromJson({'git': true}).git, isNull);
    });

    test('== / hashCode / toString', () {
      final a = GitInfoResponse.fromJson({
        'git': {'branch': 'main'},
      });
      final b = GitInfoResponse.fromJson({
        'git': {'branch': 'main'},
      });
      final c = GitInfoResponse.fromJson({
        'git': {'branch': 'dev'},
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == GitInfoResponse.fromJson(const {}), isFalse);
      expect(GitInfoResponse.fromJson(const {}), const GitInfoResponse());
      expect(
        GitInfoResponse.fromJson(const {}).hashCode,
        const GitInfoResponse().hashCode,
      );
      expect(a == Object(), isFalse);
      expect(a.toString(), 'GitInfoResponse(git: GitInfo(branch: main, isGit: null))');
      expect(
        GitInfoResponse.fromJson(const {}).toString(),
        'GitInfoResponse(git: null)',
      );
    });
  });

  group('GitInfo', () {
    test('fromJson：正常键全 7 字段', () {
      final info = GitInfo.fromJson({
        'branch': 'main',
        'dirty': 2,
        'modified': 1,
        'untracked': 3,
        'ahead': 4,
        'behind': 5,
        'is_git': true,
      });
      expect(info.branch, 'main');
      expect(info.dirty, 2);
      expect(info.modified, 1);
      expect(info.untracked, 3);
      expect(info.ahead, 4);
      expect(info.behind, 5);
      expect(info.isGit, true);
    });

    test('fromJson：键缺失 → 全 null', () {
      final info = GitInfo.fromJson(const {});
      expect(info.branch, isNull);
      expect(info.dirty, isNull);
      expect(info.modified, isNull);
      expect(info.untracked, isNull);
      expect(info.ahead, isNull);
      expect(info.behind, isNull);
      expect(info.isGit, isNull);
    });

    test('fromJson：显式 null → 全 null', () {
      final info = GitInfo.fromJson({
        'branch': null,
        'dirty': null,
        'modified': null,
        'untracked': null,
        'ahead': null,
        'behind': null,
        'is_git': null,
      });
      expect(info.branch, isNull);
      expect(info.dirty, isNull);
      expect(info.isGit, isNull);
    });

    test('fromJson：lossy 宽容转换（跨类型）', () {
      final info = GitInfo.fromJson({
        'branch': 1, // int → '1'
        'dirty': '12', // 字符串数字 → 12
        'modified': 3.9, // double → 截断 3
        'untracked': 'x', // 非数字字符串 → null
        'ahead': 1e20, // 超 int64 → null
        'behind': true, // bool → null
        'is_git': 'yes', // 'yes' → true
      });
      expect(info.branch, '1');
      expect(info.dirty, 12);
      expect(info.modified, 3);
      expect(info.untracked, isNull);
      expect(info.ahead, isNull);
      expect(info.behind, isNull);
      expect(info.isGit, true);

      expect(GitInfo.fromJson({'branch': true}).branch, 'true');
      expect(GitInfo.fromJson({'branch': 1.5}).branch, '1.5');
      expect(GitInfo.fromJson({'branch': []}).branch, isNull);
      expect(GitInfo.fromJson({'dirty': 0}).dirty, 0);
      expect(GitInfo.fromJson({'dirty': []}).dirty, isNull);
      expect(GitInfo.fromJson({'dirty': 1e20}).dirty, isNull);
      expect(GitInfo.fromJson({'dirty': '3.7'}).dirty, 3);
      expect(GitInfo.fromJson({'is_git': 1}).isGit, true);
      expect(GitInfo.fromJson({'is_git': 0}).isGit, false);
      expect(GitInfo.fromJson({'is_git': 2}).isGit, isNull);
      expect(GitInfo.fromJson({'is_git': 'no'}).isGit, false);
      expect(GitInfo.fromJson({'is_git': 'maybe'}).isGit, isNull);
      expect(GitInfo.fromJson({'is_git': []}).isGit, isNull);
      // 非仓库：is_git=false + 其余缺省
      expect(GitInfo.fromJson({'is_git': false}).isGit, false);
    });

    test('== 阶梯式（7 字段逐项差一）', () {
      const base = GitInfo(
        branch: 'main',
        dirty: 1,
        modified: 2,
        untracked: 3,
        ahead: 4,
        behind: 5,
        isGit: true,
      );
      const same = GitInfo(
        branch: 'main',
        dirty: 1,
        modified: 2,
        untracked: 3,
        ahead: 4,
        behind: 5,
        isGit: true,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(base == const GitInfo(dirty: 1, modified: 2, untracked: 3, ahead: 4, behind: 5, isGit: true), isFalse); // branch 差
      expect(base == const GitInfo(branch: 'main', modified: 2, untracked: 3, ahead: 4, behind: 5, isGit: true), isFalse); // dirty 差
      expect(base == const GitInfo(branch: 'main', dirty: 1, untracked: 3, ahead: 4, behind: 5, isGit: true), isFalse); // modified 差
      expect(base == const GitInfo(branch: 'main', dirty: 1, modified: 2, ahead: 4, behind: 5, isGit: true), isFalse); // untracked 差
      expect(base == const GitInfo(branch: 'main', dirty: 1, modified: 2, untracked: 3, behind: 5, isGit: true), isFalse); // ahead 差
      expect(base == const GitInfo(branch: 'main', dirty: 1, modified: 2, untracked: 3, ahead: 4, isGit: true), isFalse); // behind 差
      expect(base == const GitInfo(branch: 'main', dirty: 1, modified: 2, untracked: 3, ahead: 4, behind: 5), isFalse); // isGit 差

      // 反向：全 null 对方
      expect(base == const GitInfo(), isFalse);
      expect(const GitInfo() == const GitInfo(), isTrue);
      expect(const GitInfo() == base, isFalse);
      expect(base == Object(), isFalse);
      expect(base.hashCode == const GitInfo().hashCode, isFalse);
    });

    test('toString', () {
      expect(
        const GitInfo(branch: 'main', isGit: true).toString(),
        'GitInfo(branch: main, isGit: true)',
      );
      expect(
        GitInfo.fromJson(const {}).toString(),
        'GitInfo(branch: null, isGit: null)',
      );
    });
  });

  group('GitStatusResponse', () {
    test('fromJson：命中 / null / 缺失 / 非 Map', () {
      final hit = GitStatusResponse.fromJson({
        'git': {'branch': 'main', 'totals': {'changed': 3}},
      });
      expect(hit.git!.branch, 'main');
      expect(hit.git!.totals!.changed, 3);

      expect(GitStatusResponse.fromJson({'git': null}).git, isNull);
      expect(GitStatusResponse.fromJson(const {}).git, isNull);
      expect(GitStatusResponse.fromJson({'git': 'bad'}).git, isNull);
      expect(GitStatusResponse.fromJson({'git': <Object?>[]}).git, isNull);
      expect(GitStatusResponse.fromJson({'git': 1}).git, isNull);
    });

    test('== / hashCode / toString', () {
      final a = GitStatusResponse.fromJson({
        'git': {'branch': 'main'},
      });
      final b = GitStatusResponse.fromJson({
        'git': {'branch': 'main'},
      });
      final c = GitStatusResponse.fromJson({
        'git': {'branch': 'dev'},
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == GitStatusResponse.fromJson(const {}), isFalse);
      expect(GitStatusResponse.fromJson(const {}), const GitStatusResponse());
      expect(a == Object(), isFalse);
      expect(a.toString(), 'GitStatusResponse(git: GitStatus(branch: main, isGit: null))');
      expect(
        GitStatusResponse.fromJson(const {}).toString(),
        'GitStatusResponse(git: null)',
      );
    });
  });

  group('GitTotals', () {
    test('fromJson：正常键全 5 字段', () {
      final totals = GitTotals.fromJson({
        'changed': 3,
        'staged': 1,
        'unstaged': 2,
        'untracked': 1,
        'conflicts': 0,
      });
      expect(totals.changed, 3);
      expect(totals.staged, 1);
      expect(totals.unstaged, 2);
      expect(totals.untracked, 1);
      expect(totals.conflicts, 0);
    });

    test('fromJson：缺失 / null / 错型', () {
      final empty = GitTotals.fromJson(const {});
      expect(empty.changed, isNull);
      expect(empty.staged, isNull);
      expect(empty.unstaged, isNull);
      expect(empty.untracked, isNull);
      expect(empty.conflicts, isNull);

      final nulls = GitTotals.fromJson({
        'changed': null,
        'staged': null,
        'unstaged': null,
        'untracked': null,
        'conflicts': null,
      });
      expect(nulls.changed, isNull);
      expect(nulls.conflicts, isNull);

      final lossy = GitTotals.fromJson({
        'changed': '7',
        'staged': 2.8,
        'unstaged': true,
        'untracked': [],
        'conflicts': 1e20,
      });
      expect(lossy.changed, 7);
      expect(lossy.staged, 2);
      expect(lossy.unstaged, isNull);
      expect(lossy.untracked, isNull);
      expect(lossy.conflicts, isNull);
    });

    test('== 阶梯式（5 字段逐项差一）', () {
      const base = GitTotals(
        changed: 1,
        staged: 2,
        unstaged: 3,
        untracked: 4,
        conflicts: 5,
      );
      const same = GitTotals(
        changed: 1,
        staged: 2,
        unstaged: 3,
        untracked: 4,
        conflicts: 5,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      expect(base == const GitTotals(staged: 2, unstaged: 3, untracked: 4, conflicts: 5), isFalse); // changed 差
      expect(base == const GitTotals(changed: 1, unstaged: 3, untracked: 4, conflicts: 5), isFalse); // staged 差
      expect(base == const GitTotals(changed: 1, staged: 2, untracked: 4, conflicts: 5), isFalse); // unstaged 差
      expect(base == const GitTotals(changed: 1, staged: 2, unstaged: 3, conflicts: 5), isFalse); // untracked 差
      expect(base == const GitTotals(changed: 1, staged: 2, unstaged: 3, untracked: 4), isFalse); // conflicts 差

      expect(base == const GitTotals(), isFalse);
      expect(const GitTotals() == const GitTotals(), isTrue);
      expect(base == Object(), isFalse);
    });

    test('toString', () {
      expect(
        const GitTotals(changed: 3).toString(),
        'GitTotals(changed: 3)',
      );
      expect(GitTotals.fromJson(const {}).toString(), 'GitTotals(changed: null)');
    });
  });

  group('GitStatus', () {
    test('fromJson：正常键全 8 字段', () {
      final status = GitStatus.fromJson({
        'is_git': true,
        'branch': 'main',
        'upstream': 'origin/main',
        'ahead': 0,
        'behind': 1,
        'totals': {'changed': 3, 'staged': 1},
        'files': [
          {'path': 'a.dart'},
          {'path': 'b.dart'},
        ],
        'truncated': false,
      });
      expect(status.isGit, true);
      expect(status.branch, 'main');
      expect(status.upstream, 'origin/main');
      expect(status.ahead, 0);
      expect(status.behind, 1);
      expect(status.totals!.changed, 3);
      expect(status.totals!.staged, 1);
      expect(status.files, hasLength(2));
      expect(status.files!.first.path, 'a.dart');
      expect(status.files!.last.path, 'b.dart');
      expect(status.truncated, false);
    });

    test('fromJson：键缺失 / 显式 null → 全 null', () {
      final empty = GitStatus.fromJson(const {});
      expect(empty.isGit, isNull);
      expect(empty.branch, isNull);
      expect(empty.upstream, isNull);
      expect(empty.ahead, isNull);
      expect(empty.behind, isNull);
      expect(empty.totals, isNull);
      expect(empty.files, isNull);
      expect(empty.truncated, isNull);

      final nulls = GitStatus.fromJson({
        'is_git': null,
        'branch': null,
        'upstream': null,
        'ahead': null,
        'behind': null,
        'totals': null,
        'files': null,
        'truncated': null,
      });
      expect(nulls.isGit, isNull);
      expect(nulls.branch, isNull);
      expect(nulls.upstream, isNull);
      expect(nulls.ahead, isNull);
      expect(nulls.behind, isNull);
      expect(nulls.totals, isNull);
      expect(nulls.files, isNull);
      expect(nulls.truncated, isNull);
    });

    test('fromJson：lossy 宽容转换（跨类型）', () {
      final status = GitStatus.fromJson({
        'is_git': 'yes',
        'branch': 1,
        'upstream': 2.5,
        'ahead': '3',
        'behind': 4.9,
        'truncated': 0,
      });
      expect(status.isGit, true);
      expect(status.branch, '1');
      expect(status.upstream, '2.5');
      expect(status.ahead, 3);
      expect(status.behind, 4);
      expect(status.truncated, false);
      expect(GitStatus.fromJson({'branch': []}).branch, isNull);
      expect(GitStatus.fromJson({'ahead': true}).ahead, isNull);
      expect(GitStatus.fromJson({'truncated': []}).truncated, isNull);
      expect(GitStatus.fromJson({'is_git': 2}).isGit, isNull);
    });

    test('fromJson：totals 错型 → null；files 空集合 / 错型 / 元素非 Map', () {
      // totals：optModel 的 `value is! Map` 分支
      expect(GitStatus.fromJson({'totals': 'bad'}).totals, isNull);
      expect(GitStatus.fromJson({'totals': <Object?>[]}).totals, isNull);
      expect(GitStatus.fromJson({'totals': 1}).totals, isNull);
      expect(GitStatus.fromJson({'totals': null}).totals, isNull);
      expect(GitStatus.fromJson({'totals': <String, Object?>{}}).totals!.changed, isNull);

      // files：非 List → null
      expect(GitStatus.fromJson({'files': 'bad'}).files, isNull);
      expect(GitStatus.fromJson({'files': 1}).files, isNull);
      expect(GitStatus.fromJson({'files': <String, Object?>{}}).files, isNull);
      // files：空列表 → 空（非 null）
      expect(GitStatus.fromJson({'files': <Object?>[]}).files, isEmpty);
      // files：任一元素非 Map → 整数组 null（optModelList 契约）
      expect(GitStatus.fromJson({'files': [1]}).files, isNull);
      expect(GitStatus.fromJson({'files': [null]}).files, isNull);
      expect(GitStatus.fromJson({'files': ['a.dart']}).files, isNull);
      expect(
        GitStatus.fromJson({
          'files': [
            {'path': 'a.dart'},
            'b.dart',
          ],
        }).files,
        isNull,
      );
      // files：多元素 + 元素缺键
      final multi = GitStatus.fromJson({
        'files': [
          <String, Object?>{},
          {'path': 'b.dart'},
        ],
      });
      expect(multi.files, hasLength(2));
      expect(multi.files!.first.path, isNull);
      expect(multi.files!.last.path, 'b.dart');
    });

    test('trackedFiles 排除 ignored 条目；files 为 null → 空列表', () {
      final status = GitStatus.fromJson({
        'files': [
          {'path': 'a.dart'},
          {'path': 'b.dart', 'ignored': true},
          {'path': 'c.dart', 'status': 'Ignored'},
          {'path': 'd.dart', 'ignored': false},
        ],
      });
      expect(status.trackedFiles.map((f) => f.path).toList(), <String>[
        'a.dart',
        'd.dart',
      ]);
      expect(GitStatus.fromJson(const {}).trackedFiles, isEmpty);
      expect(GitStatus.fromJson({'files': <Object?>[]}).trackedFiles, isEmpty);
    });

    test('changedCount：totals.changed 优先，0 不回退', () {
      final withTotals = GitStatus.fromJson({
        'totals': {'changed': 3},
        'files': [
          {'path': 'a.dart'},
        ],
      });
      expect(withTotals.changedCount, 3);

      // totals.changed == 0 是有效值，不回退到文件数（?? 而非 ||）
      final zero = GitStatus.fromJson({
        'totals': {'changed': 0},
        'files': [
          {'path': 'a.dart'},
        ],
      });
      expect(zero.changedCount, 0);

      // totals 存在但 changed 缺失 → 回退到 trackedFiles 数量
      final noChanged = GitStatus.fromJson({
        'totals': {'staged': 1},
        'files': [
          {'path': 'a.dart'},
          {'path': 'b.dart'},
        ],
      });
      expect(noChanged.changedCount, 2);

      // totals 缺失 → trackedFiles 数量（ignored 不计）
      final noTotals = GitStatus.fromJson({
        'files': [
          {'path': 'a.dart'},
          {'path': 'b.dart', 'ignored': true},
        ],
      });
      expect(noTotals.changedCount, 1);
      expect(GitStatus.fromJson(const {}).changedCount, 0);
    });

    test('totalAdditions / totalDeletions：只算 trackedFiles，缺失计 0', () {
      final status = GitStatus.fromJson({
        'files': [
          {'path': 'a.dart', 'additions': 2, 'deletions': 1},
          {'path': 'b.dart', 'ignored': true, 'additions': 9, 'deletions': 9},
          {'path': 'c.dart', 'additions': 5},
          {'path': 'd.dart', 'deletions': 4},
          {'path': 'e.dart'},
        ],
      });
      expect(status.totalAdditions, 7);
      expect(status.totalDeletions, 5);
      expect(GitStatus.fromJson(const {}).totalAdditions, 0);
      expect(GitStatus.fromJson(const {}).totalDeletions, 0);
    });

    test('== 阶梯式（8 字段逐项差一）+ hashCode / toString', () {
      final baseFiles = <GitFile>[
        GitFile(path: 'a.dart', additions: 2),
        GitFile(path: 'b.dart', deletions: 1),
      ];
      final base = GitStatus(
        isGit: true,
        branch: 'main',
        upstream: 'origin/main',
        ahead: 1,
        behind: 2,
        totals: const GitTotals(changed: 1),
        files: baseFiles,
        truncated: false,
      );
      final same = GitStatus(
        isGit: true,
        branch: 'main',
        upstream: 'origin/main',
        ahead: 1,
        behind: 2,
        totals: const GitTotals(changed: 1),
        files: <GitFile>[
          GitFile(path: 'a.dart', additions: 2),
          GitFile(path: 'b.dart', deletions: 1),
        ],
        truncated: false,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      GitStatus variant({
        bool? isGit,
        String? branch,
        String? upstream,
        int? ahead,
        int? behind,
        GitTotals? totals,
        List<GitFile>? files,
        bool? truncated,
      }) {
        return GitStatus(
          isGit: isGit ?? true,
          branch: branch ?? 'main',
          upstream: upstream ?? 'origin/main',
          ahead: ahead ?? 1,
          behind: behind ?? 2,
          totals: totals ?? const GitTotals(changed: 1),
          files: files ?? baseFiles,
          truncated: truncated ?? false,
        );
      }

      expect(base == variant(isGit: false), isFalse); // isGit 差
      expect(base == variant(branch: 'dev'), isFalse); // branch 差
      expect(base == variant(upstream: 'origin/dev'), isFalse); // upstream 差
      expect(base == variant(ahead: 9), isFalse); // ahead 差
      expect(base == variant(behind: 9), isFalse); // behind 差
      expect(
        base == variant(totals: const GitTotals(changed: 2)),
        isFalse,
      ); // totals 差

      // files 差：deepEquals 三条路径
      expect(
        base == variant(files: <GitFile>[GitFile(path: 'a.dart', additions: 2), GitFile(path: 'c.dart')]),
        isFalse,
      ); // 同长度逐元素差
      expect(base == variant(files: <GitFile>[GitFile(path: 'a.dart', additions: 2)]), isFalse); // 长度差
      expect(base == variant(files: <GitFile>[]), isFalse); // 长度差（空）
      expect(base == variant(truncated: true), isFalse); // truncated 差

      // files null ↔ 非 null / 空列表
      expect(base == const GitStatus(), isFalse);
      expect(GitStatus(files: baseFiles) == const GitStatus(), isFalse);
      expect(const GitStatus() == const GitStatus(files: <GitFile>[]), isFalse);
      expect(const GitStatus() == const GitStatus(), isTrue);
      expect(base == Object(), isFalse);

      expect(base.toString(), 'GitStatus(branch: main, isGit: true)');
      expect(
        GitStatus.fromJson(const {}).toString(),
        'GitStatus(branch: null, isGit: null)',
      );
    });
  });

  group('GitFile', () {
    test('fromJson：正常键全 12 字段', () {
      final file = GitFile.fromJson({
        'path': 'lib/main.dart',
        'old_path': 'lib/old.dart',
        'workspace_path': 'ws/lib/main.dart',
        'status': 'M',
        'staged': true,
        'unstaged': false,
        'untracked': false,
        'ignored': false,
        'conflict': false,
        'additions': 12,
        'deletions': 3,
        'binary': false,
      });
      expect(file.path, 'lib/main.dart');
      expect(file.oldPath, 'lib/old.dart');
      expect(file.workspacePath, 'ws/lib/main.dart');
      expect(file.status, 'M');
      expect(file.staged, true);
      expect(file.unstaged, false);
      expect(file.untracked, false);
      expect(file.ignored, false);
      expect(file.conflict, false);
      expect(file.additions, 12);
      expect(file.deletions, 3);
      expect(file.binary, false);
      expect(file.id, 'lib/main.dart');
    });

    test('fromJson：键缺失 → 全 null，id 走 uuid 兜底', () {
      final file = GitFile.fromJson(const {});
      expect(file.path, isNull);
      expect(file.oldPath, isNull);
      expect(file.workspacePath, isNull);
      expect(file.status, isNull);
      expect(file.staged, isNull);
      expect(file.unstaged, isNull);
      expect(file.untracked, isNull);
      expect(file.ignored, isNull);
      expect(file.conflict, isNull);
      expect(file.additions, isNull);
      expect(file.deletions, isNull);
      expect(file.binary, isNull);
      // uuid v4：8-4-4-4-12，版本位 4，变体位 [89ab]
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(file.id),
        isTrue,
      );
      // 每次构造新 uuid → 两次 id 不同
      expect(GitFile.fromJson(const {}).id == GitFile.fromJson(const {}).id, isFalse);
    });

    test('fromJson：lossy 宽容转换 + 错型', () {
      final file = GitFile.fromJson({
        'path': 1,
        'old_path': true,
        'workspace_path': 2.5,
        'status': false,
        'staged': 'yes',
        'unstaged': 0,
        'untracked': 'no',
        'ignored': 1,
        'conflict': 2,
        'additions': '12',
        'deletions': 3.9,
        'binary': <Object?>[],
      });
      expect(file.path, '1');
      expect(file.oldPath, 'true');
      expect(file.workspacePath, '2.5');
      expect(file.status, 'false');
      expect(file.staged, true);
      expect(file.unstaged, false);
      expect(file.untracked, false);
      expect(file.ignored, true);
      expect(file.conflict, isNull); // int 2 → null
      expect(file.additions, 12);
      expect(file.deletions, 3);
      expect(file.binary, isNull);
      expect(file.id, '1');
    });

    test('id：第一个 trim 后非空（path → workspacePath → oldPath），否则 uuid', () {
      expect(GitFile.fromJson({'path': ' a.dart '}).id, 'a.dart');
      expect(GitFile.fromJson({'path': ' a.dart '}).path, ' a.dart '); // 字段原样保留
      expect(
        GitFile.fromJson({'path': '', 'workspace_path': 'ws.dart'}).id,
        'ws.dart',
      );
      expect(
        GitFile.fromJson({'path': '   ', 'workspace_path': ' ws.dart '}).id,
        'ws.dart',
      );
      expect(GitFile.fromJson({'workspace_path': 'w.dart'}).id, 'w.dart');
      expect(
        GitFile.fromJson({'path': null, 'old_path': 'x.dart'}).id,
        'x.dart',
      );
      expect(
        GitFile.fromJson({
          'path': '',
          'workspace_path': '',
          'old_path': 'o.dart',
        }).id,
        'o.dart',
      );
      // 三者都空白 → uuid 兜底
      final blank = GitFile.fromJson({
        'path': ' ',
        'workspace_path': '\t',
        'old_path': '',
      });
      expect(blank.id, isNotEmpty);
      expect(blank.id == GitFile.fromJson(const {}).id, isFalse);
    });

    test('isIgnoredFile：ignored==true 或 status 大小写不敏感 == ignored', () {
      expect(GitFile(ignored: true).isIgnoredFile, isTrue);
      expect(GitFile(ignored: false).isIgnoredFile, isFalse);
      expect(GitFile(status: 'Ignored').isIgnoredFile, isTrue);
      expect(GitFile(status: 'ignored').isIgnoredFile, isTrue);
      expect(GitFile(status: 'IGNORED').isIgnoredFile, isTrue);
      expect(GitFile(status: 'Ignored', ignored: false).isIgnoredFile, isTrue);
      expect(GitFile(status: 'Modified').isIgnoredFile, isFalse);
      expect(GitFile().isIgnoredFile, isFalse);
      // 实现用 toLowerCase 比较、不 trim → ' ignored ' 不认（对现行为取证）
      expect(GitFile(status: ' ignored ').isIgnoredFile, isFalse);
    });

    test('changeKind：全部 8 个取值 + 判决优先级', () {
      // 顺序：conflict → ignored → untracked → status 首字符 → staged||unstaged → unknown
      expect(GitFile(conflict: true).changeKind, GitFileChangeKind.conflict);
      expect(
        GitFile(conflict: true, ignored: true, untracked: true, status: 'A', staged: true).changeKind,
        GitFileChangeKind.conflict,
      );
      expect(GitFile(ignored: true).changeKind, GitFileChangeKind.ignored);
      expect(
        GitFile(ignored: true, untracked: true, status: 'A', staged: true).changeKind,
        GitFileChangeKind.ignored,
      );
      expect(GitFile(status: 'Ignored').changeKind, GitFileChangeKind.ignored);
      expect(GitFile(status: 'IGNORED').changeKind, GitFileChangeKind.ignored);
      expect(GitFile(untracked: true).changeKind, GitFileChangeKind.untracked);
      expect(
        GitFile(untracked: true, status: 'D', staged: true).changeKind,
        GitFileChangeKind.untracked,
      );
      expect(
        GitFile(untracked: false).changeKind,
        GitFileChangeKind.unknown,
      );
      // status 首字符（大写归一）
      expect(GitFile(status: 'A').changeKind, GitFileChangeKind.added);
      expect(GitFile(status: 'a').changeKind, GitFileChangeKind.added);
      expect(GitFile(status: 'Added').changeKind, GitFileChangeKind.added);
      expect(GitFile(status: 'D').changeKind, GitFileChangeKind.deleted);
      expect(GitFile(status: 'd').changeKind, GitFileChangeKind.deleted);
      expect(GitFile(status: 'R').changeKind, GitFileChangeKind.renamed);
      expect(GitFile(status: 'R100').changeKind, GitFileChangeKind.renamed);
      expect(GitFile(status: 'M').changeKind, GitFileChangeKind.modified);
      expect(GitFile(status: 'm').changeKind, GitFileChangeKind.modified);
      expect(GitFile(status: 'T').changeKind, GitFileChangeKind.modified);
      expect(GitFile(status: 't').changeKind, GitFileChangeKind.modified);
      // 首字符不可识别 → staged||unstaged ? modified : unknown
      expect(GitFile(status: '?').changeKind, GitFileChangeKind.unknown);
      expect(GitFile(status: 'ZZ').changeKind, GitFileChangeKind.unknown);
      expect(
        GitFile(status: '?', staged: true).changeKind,
        GitFileChangeKind.modified,
      );
      expect(
        GitFile(status: '?', unstaged: true).changeKind,
        GitFileChangeKind.modified,
      );
      expect(
        GitFile(status: '?', staged: false, unstaged: false).changeKind,
        GitFileChangeKind.unknown,
      );
      // status 缺失 / 空串 → 走 default 分支
      expect(GitFile().changeKind, GitFileChangeKind.unknown);
      expect(GitFile(status: '').changeKind, GitFileChangeKind.unknown);
      expect(GitFile(status: null).changeKind, GitFileChangeKind.unknown);
      expect(GitFile(staged: true).changeKind, GitFileChangeKind.modified);
      expect(GitFile(staged: false).changeKind, GitFileChangeKind.unknown);
      expect(GitFile(unstaged: true).changeKind, GitFileChangeKind.modified);
      expect(GitFile(unstaged: false).changeKind, GitFileChangeKind.unknown);
    });

    test('displayPath / fileName / parentDirectory', () {
      expect(GitFile(path: 'a.dart').displayPath, 'a.dart');
      expect(GitFile(path: ' lib/a.dart ').displayPath, 'lib/a.dart');
      expect(GitFile(workspacePath: 'ws/a.dart').displayPath, 'ws/a.dart');
      expect(GitFile(oldPath: 'old.dart').displayPath, 'old.dart');
      expect(GitFile().displayPath, '');
      // 实现是 (path ?? workspacePath ?? '').trim，不是三键回退链：
      // path 为空白串（非 null）时不再看 workspacePath
      expect(
        GitFile(path: '   ', workspacePath: 'ws/a.dart').displayPath,
        '',
      );
      expect(
        GitFile(path: '   ', workspacePath: 'ws/a.dart', oldPath: 'o.dart').displayPath,
        'o.dart',
      );
      // 同一实例：id 会跳过空白 path，displayPath 不会 → 两者口径不同
      expect(GitFile(path: '   ', workspacePath: 'ws/a.dart').id, 'ws/a.dart');

      expect(GitFile(path: 'a.dart').fileName, 'a.dart');
      expect(GitFile(path: 'lib/a.dart').fileName, 'a.dart');
      expect(GitFile(path: 'a/b/c.dart').fileName, 'c.dart');
      expect(GitFile(path: 'lib/').fileName, '');
      expect(GitFile().fileName, '');

      expect(GitFile(path: 'lib/a.dart').parentDirectory, 'lib');
      expect(GitFile(path: 'a/b/c.dart').parentDirectory, 'a/b');
      expect(GitFile(path: 'top.dart').parentDirectory, isNull);
      expect(GitFile(path: 'lib/').parentDirectory, 'lib');
      expect(GitFile(path: 'a//b').parentDirectory, 'a/');
      expect(GitFile().parentDirectory, isNull);
    });

    test('preferredDiffKind：staged-only → staged，否则 unstaged', () {
      expect(GitFile(staged: true, unstaged: false).preferredDiffKind, 'staged');
      expect(GitFile(staged: true).preferredDiffKind, 'staged');
      expect(
        GitFile(staged: true, unstaged: true).preferredDiffKind,
        'unstaged',
      );
      expect(
        GitFile(staged: false, unstaged: true).preferredDiffKind,
        'unstaged',
      );
      expect(GitFile(staged: false).preferredDiffKind, 'unstaged');
      expect(GitFile(unstaged: true).preferredDiffKind, 'unstaged');
      expect(GitFile().preferredDiffKind, 'unstaged');
    });

    test('== 阶梯式（12 字段逐项差一）+ hashCode / toString', () {
      Map<String, Object?> baseJson() => <String, Object?>{
        'path': 'lib/a.dart',
        'old_path': 'lib/old.dart',
        'workspace_path': 'ws/a.dart',
        'status': 'M',
        'staged': true,
        'unstaged': false,
        'untracked': false,
        'ignored': false,
        'conflict': false,
        'additions': 1,
        'deletions': 2,
        'binary': false,
      };
      final base = GitFile.fromJson(baseJson());
      final same = GitFile.fromJson(baseJson());
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      // 每个字段单独差一项（值差 + null 差），保证 && 每一行比较都被执行
      final overrides = <Map<String, Object?>>[
        <String, Object?>{'path': 'lib/b.dart'},
        <String, Object?>{'path': null},
        <String, Object?>{'old_path': 'lib/other.dart'},
        <String, Object?>{'old_path': null},
        <String, Object?>{'workspace_path': 'ws/b.dart'},
        <String, Object?>{'workspace_path': null},
        <String, Object?>{'status': 'A'},
        <String, Object?>{'status': null},
        <String, Object?>{'staged': false},
        <String, Object?>{'staged': null},
        <String, Object?>{'unstaged': true},
        <String, Object?>{'unstaged': null},
        <String, Object?>{'untracked': true},
        <String, Object?>{'untracked': null},
        <String, Object?>{'ignored': true},
        <String, Object?>{'ignored': null},
        <String, Object?>{'conflict': true},
        <String, Object?>{'conflict': null},
        <String, Object?>{'additions': 2},
        <String, Object?>{'additions': null},
        <String, Object?>{'deletions': 3},
        <String, Object?>{'deletions': null},
        <String, Object?>{'binary': true},
        <String, Object?>{'binary': null},
      ];
      for (final override in overrides) {
        final mutated = baseJson()..addAll(override);
        expect(
          base == GitFile.fromJson(mutated),
          isFalse,
          reason: '字段差一项应当不等：$override',
        );
      }

      // id 不参与 ==：不同 uuid 但字段全 null 的两个实例相等
      expect(GitFile.fromJson(const {}), GitFile.fromJson(const {}));
      expect(
        GitFile.fromJson(const {}).hashCode,
        GitFile.fromJson(const {}).hashCode,
      );
      expect(base == GitFile(), isFalse);
      expect(base == Object(), isFalse);
      expect(base.toString(), 'GitFile(path: lib/a.dart, status: M)');
      expect(GitFile.fromJson(const {}).toString(), 'GitFile(path: null, status: null)');
    });
  });

  group('GitFileChangeKind', () {
    test('全部 8 个取值与声明顺序', () {
      expect(GitFileChangeKind.values, hasLength(8));
      expect(GitFileChangeKind.values, <GitFileChangeKind>[
        GitFileChangeKind.conflict,
        GitFileChangeKind.untracked,
        GitFileChangeKind.added,
        GitFileChangeKind.deleted,
        GitFileChangeKind.renamed,
        GitFileChangeKind.modified,
        GitFileChangeKind.ignored,
        GitFileChangeKind.unknown,
      ]);
      expect(GitFileChangeKind.conflict.index, 0);
      expect(GitFileChangeKind.untracked.index, 1);
      expect(GitFileChangeKind.added.index, 2);
      expect(GitFileChangeKind.deleted.index, 3);
      expect(GitFileChangeKind.renamed.index, 4);
      expect(GitFileChangeKind.modified.index, 5);
      expect(GitFileChangeKind.ignored.index, 6);
      expect(GitFileChangeKind.unknown.index, 7);
      expect(GitFileChangeKind.conflict.name, 'conflict');
      expect(GitFileChangeKind.untracked.name, 'untracked');
      expect(GitFileChangeKind.added.name, 'added');
      expect(GitFileChangeKind.deleted.name, 'deleted');
      expect(GitFileChangeKind.renamed.name, 'renamed');
      expect(GitFileChangeKind.modified.name, 'modified');
      expect(GitFileChangeKind.ignored.name, 'ignored');
      expect(GitFileChangeKind.unknown.name, 'unknown');
      expect(
        GitFileChangeKind.modified.toString(),
        'GitFileChangeKind.modified',
      );
    });

    test('未知回退：无法判定 → unknown，绝不抛错', () {
      expect(
        GitFile.fromJson({'status': 'Z'}).changeKind,
        GitFileChangeKind.unknown,
      );
      expect(GitFile(status: '??').changeKind, GitFileChangeKind.unknown);
      expect(
        GitFileChangeKind.values.contains(GitFile.fromJson(const {}).changeKind),
        isTrue,
      );
    });
  });

  group('双键回退口径（本批 7 类均为 snake 单键，实现无 firstKey 回退）', () {
    test('camelCase 键一律不被识别', () {
      // is_git 只认 snake；'isGit' 被忽略（不是「回退」，是不认）
      expect(GitInfo.fromJson({'isGit': true}).isGit, isNull);
      expect(GitInfo.fromJson({'isGit': true, 'is_git': true}).isGit, true);
      expect(GitStatus.fromJson({'isGit': true}).isGit, isNull);
      expect(GitStatus.fromJson({'git': null}).isGit, isNull);
      expect(GitStatusResponse.fromJson({'git': {'isGit': true}}).git!.isGit, isNull);
      expect(GitInfoResponse.fromJson({'git': {'isGit': true}}).git!.isGit, isNull);

      final file = GitFile.fromJson({'oldPath': 'x', 'workspacePath': 'y'});
      expect(file.oldPath, isNull);
      expect(file.workspacePath, isNull);
      expect(file.id, isNotEmpty); // 无可用路径键 → uuid 兜底
      // snake 命中才生效
      expect(
        GitFile.fromJson({'old_path': 'x', 'workspace_path': 'y'}).id,
        'y',
      );
    });
  });
}
