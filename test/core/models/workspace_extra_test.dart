import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/workspace.dart';

/// workspace 模型补测（覆盖率补强，批次 A）。
///
/// 专攻模型自身：裸字符串容错、双键回退、四个 Request 的 `toJson` 条件字段、
/// `WorkspaceEntry` 的派生 getter（symlink / 只读逃逸 / 可浏览目录）、
/// 以及内联 `==` / `hashCode` / `toString`。预期值全部按实现读出来写死。
void main() {
  group('WorkspacesResponse', () {
    test('fromJson：全字段 + 空容错', () {
      final r = WorkspacesResponse.fromJson({
        'workspaces': [
          {'path': '/a', 'name': 'A'},
          {'path': '/b'},
        ],
        'last': '/b',
        'terminal_remote_backend': true,
      });

      expect(r.workspaces, hasLength(2));
      expect(r.workspaces!.first.path, '/a');
      expect(r.workspaces!.first.name, 'A');
      expect(r.workspaces!.last.name, isNull);
      expect(r.last, '/b');
      expect(r.terminalRemoteBackend, isTrue);

      final empty = WorkspacesResponse.fromJson({});
      expect(empty.workspaces, isNull);
      expect(empty.last, isNull);
      expect(empty.terminalRemoteBackend, isNull);
    });

    test('== / hashCode / toString', () {
      final a = WorkspacesResponse.fromJson({
        'workspaces': [
          {'path': '/a'},
        ],
        'last': '/a',
        'terminal_remote_backend': false,
      });
      final b = WorkspacesResponse.fromJson({
        'workspaces': [
          {'path': '/a'},
        ],
        'last': '/a',
        'terminal_remote_backend': false,
      });

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == Object(), isFalse);
      expect(a == const WorkspacesResponse(last: '/z'), isFalse);
      expect(const WorkspacesResponse() == const WorkspacesResponse(last: '/a'), isFalse);
      expect(
        const WorkspacesResponse(last: '/a') ==
            const WorkspacesResponse(last: '/a', terminalRemoteBackend: true),
        isFalse,
      );
      expect(
        const WorkspacesResponse(
          workspaces: [WorkspaceRoot(path: '/a')],
        ).toString(),
        'WorkspacesResponse(workspaces: 1)',
      );
      expect(const WorkspacesResponse().toString(), 'WorkspacesResponse(workspaces: null)');
    });
  });

  group('WorkspaceSuggestionsResponse', () {
    test('fromJson：正常 + 元素非 String 整数组 null + 空容错', () {
      final r = WorkspaceSuggestionsResponse.fromJson({
        'suggestions': ['/a', '/b'],
        'prefix': '/a',
      });
      expect(r.suggestions, ['/a', '/b']);
      expect(r.prefix, '/a');

      expect(
        WorkspaceSuggestionsResponse.fromJson({
          'suggestions': ['/a', 1],
        }).suggestions,
        isNull,
      );

      final empty = WorkspaceSuggestionsResponse.fromJson({});
      expect(empty.suggestions, isNull);
      expect(empty.prefix, isNull);
    });

    test('== / hashCode / toString（覆盖私有 _listEquals 全部分支）', () {
      const a = WorkspaceSuggestionsResponse(suggestions: ['/a'], prefix: 'p');
      const b = WorkspaceSuggestionsResponse(suggestions: ['/a'], prefix: 'p');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == Object(), isFalse);

      // 长度不同
      expect(
        const WorkspaceSuggestionsResponse(suggestions: ['/a']) ==
            const WorkspaceSuggestionsResponse(suggestions: ['/a', '/b']),
        isFalse,
      );
      // 元素不同
      expect(
        const WorkspaceSuggestionsResponse(suggestions: ['/a']) ==
            const WorkspaceSuggestionsResponse(suggestions: ['/z']),
        isFalse,
      );
      // 一侧 null
      expect(
        const WorkspaceSuggestionsResponse(suggestions: ['/a']) ==
            const WorkspaceSuggestionsResponse(),
        isFalse,
      );
      expect(
        const WorkspaceSuggestionsResponse() ==
            const WorkspaceSuggestionsResponse(suggestions: ['/a']),
        isFalse,
      );
      // identical 快路径：同一 List 实例
      final shared = ['/a'];
      expect(
        WorkspaceSuggestionsResponse(suggestions: shared) ==
            WorkspaceSuggestionsResponse(suggestions: shared),
        isTrue,
      );
      // 两侧都 null → 相等；仅 prefix 不同 → 不等
      expect(
        const WorkspaceSuggestionsResponse() ==
            const WorkspaceSuggestionsResponse(),
        isTrue,
      );
      expect(
        const WorkspaceSuggestionsResponse(prefix: 'a') ==
            const WorkspaceSuggestionsResponse(prefix: 'b'),
        isFalse,
      );
      expect(
        const WorkspaceSuggestionsResponse(prefix: 'p').toString(),
        'WorkspaceSuggestionsResponse(prefix: p)',
      );
    });
  });

  group('WorkspaceRoot', () {
    test('fromJson：裸字符串 → path，name 为 null', () {
      final r = WorkspaceRoot.fromJson('/home/u/proj');
      expect(r.path, '/home/u/proj');
      expect(r.name, isNull);
    });

    test('fromJson：非 Map 非 String → 全 null', () {
      final r = WorkspaceRoot.fromJson(42);
      expect(r.path, isNull);
      expect(r.name, isNull);
    });

    test('fromJson：Map → path / name', () {
      final r = WorkspaceRoot.fromJson({'path': '/a', 'name': 'A'});
      expect(r.path, '/a');
      expect(r.name, 'A');
    });

    test('== / hashCode / toString', () {
      const a = WorkspaceRoot(path: '/a', name: 'A');
      const b = WorkspaceRoot(path: '/a', name: 'A');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == Object(), isFalse);
      expect(a == const WorkspaceRoot(path: '/a'), isFalse);
      expect(
        const WorkspaceRoot(path: '/a') ==
            const WorkspaceRoot(path: '/a', name: 'A'),
        isFalse,
      );
      expect(
        const WorkspaceRoot(path: '/a', name: 'A').toString(),
        'WorkspaceRoot(path: /a, name: A)',
      );
    });

    test('当前行为：workspaces 数组含裸字符串 → 整数组为 null（optModelList 先要求 Map）', () {
      // 记录现状：WorkspaceRoot.fromJson 本身支持裸字符串，但
      // WorkspacesResponse 经由 optModelList 读取，非 Map 元素会让整数组解码失败。
      // 这里固化「当前行为」，是否放宽留给 Leader 裁决（改行为有风险，本轮不动）。
      final r = WorkspacesResponse.fromJson({
        'workspaces': ['/a', '/b'],
      });
      expect(r.workspaces, isNull);
    });
  });

  group('WorkspaceMutationResponse / WorkspaceMutationRejection', () {
    test('fromJson：ok 宽容布尔 + 空容错', () {
      final r = WorkspaceMutationResponse.fromJson({
        'ok': 'yes',
        'workspaces': [
          {'path': '/a'},
        ],
        'error': 'boom',
      });
      expect(r.ok, isTrue);
      expect(r.workspaces, hasLength(1));
      expect(r.error, 'boom');

      final empty = WorkspaceMutationResponse.fromJson({});
      expect(empty.ok, isNull);
      expect(empty.workspaces, isNull);
      expect(empty.error, isNull);
    });

    test('== / hashCode / toString', () {
      const a = WorkspaceMutationResponse(ok: true, error: 'e');
      const b = WorkspaceMutationResponse(ok: true, error: 'e');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == Object(), isFalse);
      expect(a == const WorkspaceMutationResponse(ok: false, error: 'e'), isFalse);
      expect(const WorkspaceMutationResponse() == const WorkspaceMutationResponse(ok: true), isFalse);
      expect(
        const WorkspaceMutationResponse(ok: true) ==
            const WorkspaceMutationResponse(
              ok: true,
              workspaces: [WorkspaceRoot(path: '/a')],
            ),
        isFalse,
      );
      expect(
        const WorkspaceMutationResponse(ok: true).toString(),
        'WorkspaceMutationResponse(ok: true)',
      );
    });

    test('Rejection：errorDescription 两个分支 + toString', () {
      const withMessage = WorkspaceMutationRejection(serverMessage: 'nope');
      expect(
        withMessage.errorDescription,
        'The server rejected the request: nope',
      );
      expect(
        withMessage.toString(),
        'WorkspaceMutationRejection: The server rejected the request: nope',
      );

      const emptyMessage = WorkspaceMutationRejection(serverMessage: '');
      expect(emptyMessage.errorDescription, 'The server rejected the request.');

      const noMessage = WorkspaceMutationRejection();
      expect(noMessage.errorDescription, 'The server rejected the request.');
      expect(
        noMessage.toString(),
        'WorkspaceMutationRejection: The server rejected the request.',
      );
    });
  });

  group('请求 DTO 的 toJson', () {
    test('AddWorkspaceRequest：可选字段按 null 省略', () {
      expect(
        const AddWorkspaceRequest(path: '/a').toJson(),
        {'path': '/a'},
      );
      expect(
        const AddWorkspaceRequest(path: '/a', name: 'A').toJson(),
        {'path': '/a', 'name': 'A'},
      );
      expect(
        const AddWorkspaceRequest(path: '/a', create: false).toJson(),
        {'path': '/a', 'create': false},
      );
      expect(
        const AddWorkspaceRequest(path: '/a', name: 'A', create: true).toJson(),
        {'path': '/a', 'name': 'A', 'create': true},
      );
    });

    test('RemoveWorkspaceRequest / RenameWorkspaceRequest / ReorderWorkspacesRequest 的 toJson', () {
      expect(
        const RemoveWorkspaceRequest(path: '/a').toJson(),
        {'path': '/a'},
      );
      expect(
        const RenameWorkspaceRequest(path: '/a', name: 'A').toJson(),
        {'path': '/a', 'name': 'A'},
      );
      expect(
        const ReorderWorkspacesRequest(paths: ['/a', '/b']).toJson(),
        {
          'paths': ['/a', '/b'],
        },
      );
    });

    test('四个 DTO 的 == / hashCode / toString', () {
      const add = AddWorkspaceRequest(path: '/a', name: 'A', create: true);
      const addSame = AddWorkspaceRequest(path: '/a', name: 'A', create: true);
      expect(add, equals(addSame));
      expect(add.hashCode, addSame.hashCode);
      expect(add == Object(), isFalse);
      expect(const AddWorkspaceRequest(path: '/a') == const AddWorkspaceRequest(path: '/b'), isFalse);
      expect(
        const AddWorkspaceRequest(path: '/a') ==
            const AddWorkspaceRequest(path: '/a', name: 'A'),
        isFalse,
      );
      expect(
        const AddWorkspaceRequest(path: '/a', name: 'A') ==
            const AddWorkspaceRequest(path: '/a', name: 'A', create: true),
        isFalse,
      );
      expect(add.toString(), 'AddWorkspaceRequest(path: /a)');

      const remove = RemoveWorkspaceRequest(path: '/a');
      expect(remove, equals(const RemoveWorkspaceRequest(path: '/a')));
      expect(
        remove.hashCode,
        const RemoveWorkspaceRequest(path: '/a').hashCode,
      );
      expect(remove == Object(), isFalse);
      expect(
        remove == const RemoveWorkspaceRequest(path: '/b'),
        isFalse,
      );
      expect(remove.toString(), 'RemoveWorkspaceRequest(path: /a)');

      const rename = RenameWorkspaceRequest(path: '/a', name: 'A');
      expect(
        rename,
        equals(const RenameWorkspaceRequest(path: '/a', name: 'A')),
      );
      expect(
        rename.hashCode,
        const RenameWorkspaceRequest(path: '/a', name: 'A').hashCode,
      );
      expect(rename == Object(), isFalse);
      expect(
        rename == const RenameWorkspaceRequest(path: '/a', name: 'B'),
        isFalse,
      );
      expect(
        const RenameWorkspaceRequest(path: '/a', name: 'A') ==
            const RenameWorkspaceRequest(path: '/b', name: 'A'),
        isFalse,
      );
      expect(rename.toString(), 'RenameWorkspaceRequest(path: /a, name: A)');

      const reorder = ReorderWorkspacesRequest(paths: ['/a']);
      expect(
        reorder,
        equals(const ReorderWorkspacesRequest(paths: ['/a'])),
      );
      expect(
        reorder.hashCode,
        const ReorderWorkspacesRequest(paths: ['/a']).hashCode,
      );
      expect(reorder == Object(), isFalse);
      expect(
        reorder == const ReorderWorkspacesRequest(paths: ['/a', '/b']),
        isFalse,
      );
      expect(
        reorder == const ReorderWorkspacesRequest(paths: ['/z']),
        isFalse,
      );
      expect(reorder.toString(), 'ReorderWorkspacesRequest(paths: [/a])');
    });
  });

  group('DirectoryListResponse', () {
    test('fromJson：全字段 + 空容错', () {
      final r = DirectoryListResponse.fromJson({
        'entries': [
          {'name': 'a.txt', 'path': '/a.txt', 'size': 10},
        ],
        'path': '/',
        'workspace': '/ws',
        'error': 'e',
        'signature': 'sig',
      });
      expect(r.entries, hasLength(1));
      expect(r.entries!.first.name, 'a.txt');
      expect(r.path, '/');
      expect(r.workspace, '/ws');
      expect(r.error, 'e');
      expect(r.signature, 'sig');

      final empty = DirectoryListResponse.fromJson({});
      expect(empty.entries, isNull);
      expect(empty.path, isNull);
      expect(empty.workspace, isNull);
      expect(empty.error, isNull);
      expect(empty.signature, isNull);
    });

    test('== / hashCode / toString', () {
      const full = DirectoryListResponse(
        path: '/',
        workspace: '/ws',
        error: 'e',
        signature: 's',
      );
      expect(full, equals(const DirectoryListResponse(
        path: '/',
        workspace: '/ws',
        error: 'e',
        signature: 's',
      )));
      expect(
        full.hashCode,
        const DirectoryListResponse(
          path: '/',
          workspace: '/ws',
          error: 'e',
          signature: 's',
        ).hashCode,
      );
      expect(full == Object(), isFalse);
      expect(
        const DirectoryListResponse() ==
            const DirectoryListResponse(path: '/'),
        isFalse,
      );
      expect(
        const DirectoryListResponse(path: '/') ==
            const DirectoryListResponse(path: '/', workspace: '/ws'),
        isFalse,
      );
      expect(
        const DirectoryListResponse(path: '/', workspace: '/ws') ==
            const DirectoryListResponse(
              path: '/',
              workspace: '/ws',
              error: 'e',
            ),
        isFalse,
      );
      expect(
        const DirectoryListResponse(path: '/', workspace: '/ws', error: 'e') ==
            const DirectoryListResponse(
              path: '/',
              workspace: '/ws',
              error: 'e',
              signature: 's',
            ),
        isFalse,
      );
      expect(
        const DirectoryListResponse(path: '/', workspace: '/ws', error: 'e', signature: 's') ==
            const DirectoryListResponse(
              path: '/',
              workspace: '/ws',
              error: 'e',
              signature: 's',
              entries: [WorkspaceEntry(name: 'a')],
            ),
        isFalse,
      );
      expect(
        const DirectoryListResponse(path: '/').toString(),
        'DirectoryListResponse(path: /)',
      );
    });
  });

  group('WorkspaceEntry', () {
    test('fromJson：全字段 + is_directory/is_dir 回退 + 空容错', () {
      final e = WorkspaceEntry.fromJson({
        'name': 'a.txt',
        'path': '/a.txt',
        'type': 'file',
        'size': 10,
        'modified': 1.5,
        'is_directory': true,
        'mtime_ns': 99,
        'target': '/t',
        'target_outside_workspace': false,
      });
      expect(e.name, 'a.txt');
      expect(e.path, '/a.txt');
      expect(e.type, 'file');
      expect(e.size, 10);
      expect(e.modified, 1.5);
      expect(e.isDirectory, isTrue);
      expect(e.mtimeNs, 99);
      expect(e.target, '/t');
      expect(e.targetOutsideWorkspace, isFalse);

      final viaOldKey = WorkspaceEntry.fromJson({'is_dir': true});
      expect(viaOldKey.isDirectory, isTrue);

      final empty = WorkspaceEntry.fromJson({});
      expect(empty.name, isNull);
      expect(empty.path, isNull);
      expect(empty.type, isNull);
      expect(empty.size, isNull);
      expect(empty.modified, isNull);
      expect(empty.isDirectory, isNull);
      expect(empty.mtimeNs, isNull);
      expect(empty.target, isNull);
      expect(empty.targetOutsideWorkspace, isNull);
    });

    test('id：path → name → uuid 三级回退', () {
      expect(const WorkspaceEntry(path: '/a', name: 'n').id, '/a');
      expect(const WorkspaceEntry(name: 'n').id, 'n');

      const noKeys = WorkspaceEntry();
      expect(noKeys.id, isNotEmpty);
      // 三级回退是 uuidV4()，每次调用都新生成
      expect(noKeys.id == noKeys.id, isFalse);
    });

    test('isSymlink / isReadOnlyEscape', () {
      expect(const WorkspaceEntry(type: 'symlink').isSymlink, isTrue);
      expect(const WorkspaceEntry(type: 'file').isSymlink, isFalse);
      expect(const WorkspaceEntry().isSymlink, isFalse);

      expect(
        const WorkspaceEntry(
          type: 'symlink',
          targetOutsideWorkspace: true,
        ).isReadOnlyEscape,
        isTrue,
      );
      expect(
        const WorkspaceEntry(
          type: 'symlink',
          targetOutsideWorkspace: false,
        ).isReadOnlyEscape,
        isFalse,
      );
      expect(
        const WorkspaceEntry(
          type: 'file',
          targetOutsideWorkspace: true,
        ).isReadOnlyEscape,
        isFalse,
      );
    });

    test('isBrowsableDirectory：普通目录可进入，逃逸 symlink 不可', () {
      expect(const WorkspaceEntry(isDirectory: true).isBrowsableDirectory, isTrue);
      expect(const WorkspaceEntry(type: 'dir').isBrowsableDirectory, isTrue);
      expect(const WorkspaceEntry(type: 'file').isBrowsableDirectory, isFalse);
      expect(const WorkspaceEntry().isBrowsableDirectory, isFalse);
      // 逃逸 symlink 即使带 is_directory 也不可进入
      expect(
        const WorkspaceEntry(
          type: 'symlink',
          isDirectory: true,
          targetOutsideWorkspace: true,
        ).isBrowsableDirectory,
        isFalse,
      );
      // 工作区内的 symlink 目录可进入
      expect(
        const WorkspaceEntry(
          type: 'symlink',
          isDirectory: true,
          targetOutsideWorkspace: false,
        ).isBrowsableDirectory,
        isTrue,
      );
    });

    test('== / hashCode / toString', () {
      const full = WorkspaceEntry(
        name: 'n',
        path: '/p',
        type: 'file',
        size: 1,
        modified: 2.0,
        isDirectory: false,
        mtimeNs: 3,
        target: '/t',
        targetOutsideWorkspace: false,
      );
      expect(
        full,
        equals(const WorkspaceEntry(
          name: 'n',
          path: '/p',
          type: 'file',
          size: 1,
          modified: 2.0,
          isDirectory: false,
          mtimeNs: 3,
          target: '/t',
          targetOutsideWorkspace: false,
        )),
      );
      expect(full.hashCode, full.hashCode);
      expect(full == Object(), isFalse);

      // 阶梯式：保证每一行字段比较都被执行
      expect(const WorkspaceEntry() == const WorkspaceEntry(name: 'n'), isFalse);
      expect(
        const WorkspaceEntry(name: 'n') ==
            const WorkspaceEntry(name: 'n', path: '/p'),
        isFalse,
      );
      expect(
        const WorkspaceEntry(name: 'n', path: '/p') ==
            const WorkspaceEntry(name: 'n', path: '/p', type: 'file'),
        isFalse,
      );
      expect(
        const WorkspaceEntry(name: 'n', path: '/p', type: 'file') ==
            const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
            ),
        isFalse,
      );
      expect(
        const WorkspaceEntry(name: 'n', path: '/p', type: 'file', size: 1) ==
            const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
            ),
        isFalse,
      );
      expect(
        const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
            ) ==
            const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
              isDirectory: false,
            ),
        isFalse,
      );
      expect(
        const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
              isDirectory: false,
            ) ==
            const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
              isDirectory: false,
              mtimeNs: 3,
            ),
        isFalse,
      );
      expect(
        const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
              isDirectory: false,
              mtimeNs: 3,
            ) ==
            const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
              isDirectory: false,
              mtimeNs: 3,
              target: '/t',
            ),
        isFalse,
      );
      expect(
        const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
              isDirectory: false,
              mtimeNs: 3,
              target: '/t',
            ) ==
            const WorkspaceEntry(
              name: 'n',
              path: '/p',
              type: 'file',
              size: 1,
              modified: 2.0,
              isDirectory: false,
              mtimeNs: 3,
              target: '/t',
              targetOutsideWorkspace: false,
            ),
        isFalse,
      );
      expect(
        const WorkspaceEntry(name: 'n', path: '/p').toString(),
        'WorkspaceEntry(name: n, path: /p)',
      );
    });
  });

  group('FileResponse', () {
    test('fromJson：全字段（含 binary → isBinary）', () {
      final r = FileResponse.fromJson({
        'content': 'c',
        'path': '/p',
        'name': 'n',
        'language': 'dart',
        'size': 1,
        'lines': 2,
        'error': 'e',
        'preview_kind': 'office',
        'office_format': 'docx',
        'render_mode': 'html',
        'editable': true,
        'edit_blocked_reason': 'readonly',
        'truncated': true,
        'binary': true,
      });

      expect(r.content, 'c');
      expect(r.path, '/p');
      expect(r.name, 'n');
      expect(r.language, 'dart');
      expect(r.size, 1);
      expect(r.lines, 2);
      expect(r.error, 'e');
      expect(r.previewKind, 'office');
      expect(r.officeFormat, 'docx');
      expect(r.renderMode, 'html');
      expect(r.editable, isTrue);
      expect(r.editBlockedReason, 'readonly');
      expect(r.truncated, isTrue);
      expect(r.isBinary, isTrue);

      final empty = FileResponse.fromJson({});
      expect(empty.content, isNull);
      expect(empty.path, isNull);
      expect(empty.name, isNull);
      expect(empty.language, isNull);
      expect(empty.size, isNull);
      expect(empty.lines, isNull);
      expect(empty.error, isNull);
      expect(empty.previewKind, isNull);
      expect(empty.officeFormat, isNull);
      expect(empty.renderMode, isNull);
      expect(empty.editable, isNull);
      expect(empty.editBlockedReason, isNull);
      expect(empty.truncated, isNull);
      expect(empty.isBinary, isNull);
    });

    test('== / hashCode / toString', () {
      const full = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
        previewKind: 'k',
        officeFormat: 'f',
        renderMode: 'm',
        editable: true,
        editBlockedReason: 'r',
        truncated: true,
        isBinary: false,
      );
      expect(full, equals(const FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
        previewKind: 'k',
        officeFormat: 'f',
        renderMode: 'm',
        editable: true,
        editBlockedReason: 'r',
        truncated: true,
        isBinary: false,
      )));
      expect(full.hashCode, full.hashCode);
      expect(full == Object(), isFalse);

      // 阶梯式覆盖每一行比较
      const f0 = FileResponse();
      const f1 = FileResponse(content: 'c');
      const f2 = FileResponse(content: 'c', path: '/p');
      const f3 = FileResponse(content: 'c', path: '/p', name: 'n');
      const f4 = FileResponse(content: 'c', path: '/p', name: 'n', language: 'dart');
      const f5 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
      );
      const f6 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
      );
      const f7 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
      );
      const f8 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
        previewKind: 'k',
      );
      const f9 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
        previewKind: 'k',
        officeFormat: 'f',
      );
      const f10 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
        previewKind: 'k',
        officeFormat: 'f',
        renderMode: 'm',
      );
      const f11 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
        previewKind: 'k',
        officeFormat: 'f',
        renderMode: 'm',
        editable: true,
      );
      const f12 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
        previewKind: 'k',
        officeFormat: 'f',
        renderMode: 'm',
        editable: true,
        editBlockedReason: 'r',
      );
      const f13 = FileResponse(
        content: 'c',
        path: '/p',
        name: 'n',
        language: 'dart',
        size: 1,
        lines: 2,
        error: 'e',
        previewKind: 'k',
        officeFormat: 'f',
        renderMode: 'm',
        editable: true,
        editBlockedReason: 'r',
        truncated: true,
      );

      expect(f0 == f1, isFalse);
      expect(f1 == f2, isFalse);
      expect(f2 == f3, isFalse);
      expect(f3 == f4, isFalse);
      expect(f4 == f5, isFalse);
      expect(f5 == f6, isFalse);
      expect(f6 == f7, isFalse);
      expect(f7 == f8, isFalse);
      expect(f8 == f9, isFalse);
      expect(f9 == f10, isFalse);
      expect(f10 == f11, isFalse);
      expect(f11 == f12, isFalse);
      expect(f12 == f13, isFalse);
      expect(
        const FileResponse(path: '/p', size: 1).toString(),
        'FileResponse(path: /p, size: 1)',
      );
    });
  });

  group('FileDeleteResponse / FileRenameResponse', () {
    test('FileDeleteResponse：fromJson / == / hashCode / toString', () {
      final r = FileDeleteResponse.fromJson({
        'ok': 1,
        'path': '/p',
        'error': 'e',
      });
      expect(r.ok, isTrue);
      expect(r.path, '/p');
      expect(r.error, 'e');

      final empty = FileDeleteResponse.fromJson({});
      expect(empty.ok, isNull);
      expect(empty.path, isNull);
      expect(empty.error, isNull);

      const full = FileDeleteResponse(ok: true, path: '/p', error: 'e');
      expect(full, equals(const FileDeleteResponse(ok: true, path: '/p', error: 'e')));
      expect(full.hashCode, full.hashCode);
      expect(full == Object(), isFalse);
      expect(const FileDeleteResponse() == const FileDeleteResponse(ok: false), isFalse);
      expect(
        const FileDeleteResponse(ok: true) ==
            const FileDeleteResponse(ok: true, path: '/p'),
        isFalse,
      );
      expect(
        const FileDeleteResponse(ok: true, path: '/p') ==
            const FileDeleteResponse(ok: true, path: '/p', error: 'e'),
        isFalse,
      );
      expect(
        const FileDeleteResponse(ok: true, path: '/p').toString(),
        'FileDeleteResponse(ok: true, path: /p)',
      );
    });

    test('FileRenameResponse：fromJson（old_path/newPath 双向回退）', () {
      final snake = FileRenameResponse.fromJson({
        'ok': true,
        'old_path': '/a',
        'new_path': '/b',
        'error': 'e',
      });
      expect(snake.ok, isTrue);
      expect(snake.oldPath, '/a');
      expect(snake.newPath, '/b');
      expect(snake.error, 'e');

      final camel = FileRenameResponse.fromJson({
        'oldPath': '/a',
        'newPath': '/b',
      });
      expect(camel.oldPath, '/a');
      expect(camel.newPath, '/b');

      final empty = FileRenameResponse.fromJson({});
      expect(empty.ok, isNull);
      expect(empty.oldPath, isNull);
      expect(empty.newPath, isNull);
      expect(empty.error, isNull);
    });

    test('FileRenameResponse：== / hashCode / toString', () {
      const full = FileRenameResponse(
        ok: true,
        oldPath: '/a',
        newPath: '/b',
        error: 'e',
      );
      expect(full, equals(const FileRenameResponse(
        ok: true,
        oldPath: '/a',
        newPath: '/b',
        error: 'e',
      )));
      expect(full.hashCode, full.hashCode);
      expect(full == Object(), isFalse);
      expect(const FileRenameResponse() == const FileRenameResponse(ok: true), isFalse);
      expect(
        const FileRenameResponse(ok: true) ==
            const FileRenameResponse(ok: true, oldPath: '/a'),
        isFalse,
      );
      expect(
        const FileRenameResponse(ok: true, oldPath: '/a') ==
            const FileRenameResponse(ok: true, oldPath: '/a', newPath: '/b'),
        isFalse,
      );
      expect(
        const FileRenameResponse(ok: true, oldPath: '/a', newPath: '/b') ==
            const FileRenameResponse(
              ok: true,
              oldPath: '/a',
              newPath: '/b',
              error: 'e',
            ),
        isFalse,
      );
      expect(
        const FileRenameResponse(
          ok: true,
          oldPath: '/a',
          newPath: '/b',
        ).toString(),
        'FileRenameResponse(ok: true, oldPath: /a, newPath: /b)',
      );
    });
  });
}
