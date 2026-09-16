import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/endpoints.dart';
import 'package:hermes_ui/features/git/git_api.dart';

/// 测试用固定 base URL（不触发任何网络）。
const String kBaseUrl = 'http://test.local:30002';

/// 记录调用入参、返回可配置 JSON 的假 [ApiClient]。
///
/// [GitApiClient] 的每个方法最终都落到 `ApiClient.sendJson`，因此重写
/// 该方法即可在**完全无网络**的前提下验证 URL / method / body / timeout。
class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(baseUrl: kBaseUrl);

  final List<_RecordedCall> calls = [];

  /// [sendJson] 返回的 JSON（默认空 Map；可换成 List / null / 错误结构）。
  Object? json = const <String, Object?>{};

  /// 非 null 时 [sendJson] 直接抛出（模拟非 2xx / 网络失败）。
  Object? error;

  _RecordedCall get last => calls.last;

  @override
  Future<Object?> sendJson(
    Endpoint endpoint, {
    String method = 'GET',
    Map<String, Object?>? body,
    Duration? timeout,
    String accept = 'application/json',
    bool allowAutoReauth = true,
  }) async {
    calls.add(
      _RecordedCall(
        path: endpoint.path,
        method: method,
        body: body,
        timeout: timeout,
        url: endpoint.url(baseUrl).toString(),
      ),
    );
    final failure = error;
    if (failure != null) throw failure;
    return json;
  }
}

class _RecordedCall {
  _RecordedCall({
    required this.path,
    required this.method,
    required this.body,
    required this.timeout,
    required this.url,
  });

  final String path;
  final String method;
  final Map<String, Object?>? body;
  final Duration? timeout;
  final String url;

  Map<String, Object?> get bodyOrEmpty => body ?? const <String, Object?>{};
}

void main() {
  late _RecordingApiClient client;
  late GitApiClient api;

  setUp(() {
    client = _RecordingApiClient();
    api = GitApiClient(client);
  });

  group('GitApiClient 端点委托：GET 类', () {
    test('fetchStatus → GET /api/git/status?session_id=… 并解码 git 载荷', () async {
      client.json = {
        'git': {'is_git': true, 'branch': 'main', 'ahead': 2},
      };

      final response = await api.fetchStatus('s1');

      expect(client.calls, hasLength(1));
      expect(client.last.path, '/api/git/status');
      expect(client.last.method, 'GET');
      expect(client.last.url, '$kBaseUrl/api/git/status?session_id=s1');
      expect(client.last.body, isNull);
      expect(response.git!.isGit, isTrue);
      expect(response.git!.branch, 'main');
      expect(response.git!.ahead, 2);
    });

    test('fetchBranches → GET /api/git/branches 并解码 local/remote', () async {
      client.json = {
        'branches': {
          'is_git': true,
          'current': 'main',
          'local': [
            {'name': 'main', 'sha': 'abc1234'},
            {'name': 'dev'},
          ],
          'remote': [
            {'name': 'origin/main'},
          ],
        },
      };

      final response = await api.fetchBranches('s1');

      expect(client.last.path, '/api/git/branches');
      expect(client.last.method, 'GET');
      expect(client.last.url, '$kBaseUrl/api/git/branches?session_id=s1');
      expect(response.branches!.current, 'main');
      expect(response.branches!.local, hasLength(2));
      expect(response.branches!.local!.first.sha, 'abc1234');
      expect(response.branches!.remote!.single.name, 'origin/main');
    });

    test('fetchDiff → GET /api/git/diff（默认 kind=unstaged）', () async {
      client.json = {
        'diff': {'path': 'a.txt', 'kind': 'unstaged', 'diff': '@@ -1 +1 @@'},
      };

      final response = await api.fetchDiff(sessionId: 's1', path: 'a.txt');

      expect(client.last.path, '/api/git/diff');
      expect(
        client.last.url,
        '$kBaseUrl/api/git/diff?session_id=s1&path=a.txt&kind=unstaged',
      );
      expect(response.diff!.path, 'a.txt');
      expect(response.diff!.diff, '@@ -1 +1 @@');
    });

    test('fetchDiff → kind=staged 透传，且 path 按 URL 规则编码', () async {
      client.json = {
        'diff': {'path': 'a/b c.txt', 'kind': 'staged'},
      };

      final response = await api.fetchDiff(
        sessionId: 's1',
        path: 'a/b c.txt',
        kind: 'staged',
      );

      expect(
        client.last.url,
        '$kBaseUrl/api/git/diff?session_id=s1&path=a%2Fb%20c.txt&kind=staged',
      );
      expect(response.diff!.kind, 'staged');
    });
  });

  group('GitApiClient 端点委托：POST 类', () {
    test('stage → POST /api/git/stage {session_id, paths}', () async {
      client.json = {
        'ok': true,
        'git': {'is_git': true, 'branch': 'main'},
      };

      final response = await api.stage(sessionId: 's1', paths: ['a.txt', 'b']);

      expect(client.last.path, '/api/git/stage');
      expect(client.last.method, 'POST');
      expect(client.last.body, {
        'session_id': 's1',
        'paths': ['a.txt', 'b'],
      });
      expect(response.ok, isTrue);
      expect(response.resolvedStatus!.branch, 'main');
    });

    test('unstage → POST /api/git/unstage {session_id, paths}', () async {
      client.json = {'ok': true};

      final response = await api.unstage(sessionId: 's1', paths: ['a.txt']);

      expect(client.last.path, '/api/git/unstage');
      expect(client.last.method, 'POST');
      expect(client.last.body, {
        'session_id': 's1',
        'paths': ['a.txt'],
      });
      expect(response.ok, isTrue);
      expect(response.resolvedStatus, isNull);
    });

    test('discard → POST /api/git/discard（delete_untracked 默认 false）', () async {
      client.json = {'ok': true};

      await api.discard(sessionId: 's1', paths: ['c.txt']);

      expect(client.last.path, '/api/git/discard');
      expect(client.last.method, 'POST');
      expect(client.last.body, {
        'session_id': 's1',
        'paths': ['c.txt'],
        'delete_untracked': false,
      });
    });

    test('discard → delete_untracked=true 显式透传', () async {
      client.json = {'ok': true};

      await api.discard(
        sessionId: 's1',
        paths: ['c.txt'],
        deleteUntracked: true,
      );

      expect(client.last.bodyOrEmpty['delete_untracked'], isTrue);
    });

    test('commit → POST /api/git/commit {session_id, message}', () async {
      client.json = {
        'ok': true,
        'commit': 'abc1234',
        'status': {'is_git': true, 'branch': 'main'},
      };

      final response = await api.commit(sessionId: 's1', message: 'feat: x');

      expect(client.last.path, '/api/git/commit');
      expect(client.last.method, 'POST');
      expect(client.last.body, {'session_id': 's1', 'message': 'feat: x'});
      expect(client.last.timeout, isNull);
      expect(response.shortSHA, 'abc1234');
      expect(response.resolvedStatus!.branch, 'main');
    });

    test('fetch / pull / push → POST 同名端点，body 仅 session_id', () async {
      client.json = {
        'ok': true,
        'message': '完成',
        'status': {'is_git': true, 'branch': 'main'},
      };

      final fetched = await api.fetch('s1');
      expect(client.last.path, '/api/git/fetch');
      expect(client.last.method, 'POST');
      expect(client.last.body, {'session_id': 's1'});
      expect(client.last.timeout, isNull);
      expect(fetched.message, '完成');

      final pulled = await api.pull('s1');
      expect(client.last.path, '/api/git/pull');
      expect(client.last.body, {'session_id': 's1'});
      expect(pulled.status!.branch, 'main');

      final pushed = await api.push('s2');
      expect(client.last.path, '/api/git/push');
      expect(client.last.body, {'session_id': 's2'});
      expect(pushed.ok, isTrue);
      expect(pushed.status!.branch, 'main');

      expect(
        client.calls.map((c) => c.path),
        ['/api/git/fetch', '/api/git/pull', '/api/git/push'],
      );
    });
  });

  group('GitApiClient checkout body 组装', () {
    test('默认：mode=local、无 new_branch / track，dirty_mode 固定 block', () async {
      client.json = {'ok': true};

      await api.checkout(sessionId: 's1', ref: 'dev');

      expect(client.last.path, '/api/git/checkout');
      expect(client.last.method, 'POST');
      expect(client.last.body, {
        'session_id': 's1',
        'ref': 'dev',
        'mode': 'local',
        'dirty_mode': 'block',
      });
      expect(client.last.bodyOrEmpty.containsKey('new_branch'), isFalse);
      expect(client.last.bodyOrEmpty.containsKey('track'), isFalse);
    });

    test('mode=local + newBranch → mode 自动升级为 new 并带 new_branch', () async {
      client.json = {
        'ok': true,
        'message': '已切换',
        'branches': {
          'is_git': true,
          'current': 'feature',
          'local': [
            {'name': 'feature'},
          ],
        },
      };

      final response = await api.checkout(
        sessionId: 's1',
        ref: 'main',
        newBranch: 'feature',
      );

      expect(client.last.bodyOrEmpty['mode'], 'new');
      expect(client.last.bodyOrEmpty['new_branch'], 'feature');
      expect(client.last.bodyOrEmpty['dirty_mode'], 'block');
      expect(response.message, '已切换');
      expect(response.branches!.current, 'feature');
    });

    test('track=true → body 带 track:true', () async {
      client.json = {'ok': true};

      await api.checkout(sessionId: 's1', ref: 'origin/dev', track: true);

      expect(client.last.bodyOrEmpty['track'], isTrue);
    });

    test('mode=remote + newBranch → mode 保持 remote（不升级）', () async {
      client.json = {'ok': true};

      await api.checkout(
        sessionId: 's1',
        ref: 'origin/dev',
        mode: 'remote',
        newBranch: 'dev',
      );

      expect(client.last.bodyOrEmpty['mode'], 'remote');
      expect(client.last.bodyOrEmpty['new_branch'], 'dev');
    });
  });

  group('GitApiClient 错误与畸形响应', () {
    test('非 2xx（HttpException）原样抛出，不做吞没', () async {
      client.error = HttpException(
        409,
        '{"code":"active_stream"}',
        serverCode: 'active_stream',
      );

      await expectLater(
        api.fetchStatus('s1'),
        throwsA(isA<HttpException>()),
      );
      await expectLater(
        api.stage(sessionId: 's1', paths: []),
        throwsA(isA<HttpException>()),
      );
      expect(client.calls, hasLength(2));
    });

    test('网络异常（NetworkException）原样抛出', () async {
      client.error = NetworkException(NetworkExceptionKind.timedOut);

      await expectLater(
        api.push('s1'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('空响应体（null）→ 各响应信封字段全为 null，不抛错', () async {
      client.json = null;

      expect((await api.fetchStatus('s1')).git, isNull);
      expect((await api.fetchBranches('s1')).branches, isNull);
      expect((await api.fetchDiff(sessionId: 's1', path: 'a')).diff, isNull);
      expect((await api.stage(sessionId: 's1', paths: [])).ok, isNull);
      expect((await api.commit(sessionId: 's1', message: 'm')).commit, isNull);
      expect((await api.checkout(sessionId: 's1', ref: 'dev')).ok, isNull);
      expect((await api.fetch('s1')).message, isNull);
      expect((await api.pull('s1')).status, isNull);
      expect((await api.push('s1')).ok, isNull);
    });

    test('响应体是 List（非 Map）→ 回退空 Map，字段全 null', () async {
      client.json = [1, 2, 3];

      expect((await api.fetchStatus('s1')).git, isNull);
      expect((await api.fetchBranches('s1')).branches, isNull);
    });

    test('类型不符的键位走 lossy 语义：能宽转的转、不能转的丢弃（不抛错）', () async {
      client.json = {
        'git': {
          'is_git': 'bad',
          'branch': 1,
          'ahead': 'x',
          'totals': 'nope',
          'files': 'not-a-list',
        },
      };

      final status = (await api.fetchStatus('s1')).git!;

      // lossyBool：'bad' 无法识别 → null。
      expect(status.isGit, isNull);
      // lossyString：int 1 → '1'（宽容转换，而非丢弃）。
      expect(status.branch, '1');
      // lossyInt：'x' 既非 int 也非数值字符串 → null。
      expect(status.ahead, isNull);
      // 期望 Map / List 的键位给错类型 → null。
      expect(status.totals, isNull);
      expect(status.files, isNull);
      expect(status.trackedFiles, isEmpty);
      expect(status.changedCount, 0);
    });

    test('lossyBool 数字/字符串形态：1→true、0→false、其他→null', () async {
      client.json = {
        'git': {'is_git': 1},
      };
      expect((await api.fetchStatus('s1')).git!.isGit, isTrue);

      client.json = {
        'git': {'is_git': 0},
      };
      expect((await api.fetchStatus('s1')).git!.isGit, isFalse);

      client.json = {
        'git': {'is_git': 'yes'},
      };
      expect((await api.fetchStatus('s1')).git!.isGit, isTrue);

      client.json = {
        'git': {'is_git': 'maybe'},
      };
      expect((await api.fetchStatus('s1')).git!.isGit, isNull);

      client.json = {
        'git': {'is_git': true, 'branch': true},
      };
      final status = (await api.fetchStatus('s1')).git!;
      expect(status.isGit, isTrue);
      // lossyString：bool → 'true' / 'false'。
      expect(status.branch, 'true');
    });

    test('近似键名不被识别（isGit / branchName / updatedRelative 无下划线）', () async {
      client.json = {
        'git': {'isGit': true, 'branchName': 'main'},
        'branches': {
          'local': [
            {'name': 'main', 'updatedRelative': '2h'},
          ],
          'remote': [
            {'name': 'origin/main', 'upstream': 'main'},
          ],
        },
      };

      final status = (await api.fetchStatus('s1')).git!;
      expect(status.isGit, isNull);
      expect(status.branch, isNull);

      final branches = (await api.fetchBranches('s1')).branches!;
      expect(branches.local!.single.updatedRelative, isNull);
      // 下划线形态才是被识别的键位。
      expect(branches.remote!.single.upstream, 'main');

      client.json = {
        'branches': {
          'local': [
            {'name': 'main', 'updated_relative': '2h'},
          ],
        },
      };
      final snake = (await api.fetchBranches('s1')).branches!;
      expect(snake.local!.single.updatedRelative, '2h');
    });

    test('缺失键位 → 字段 null；空 Map → 全 null；空集合保持空列表', () async {
      client.json = const <String, Object?>{};
      expect((await api.fetchStatus('s1')).git, isNull);

      client.json = {
        'branches': {
          'local': <Object?>[],
          'remote': <Object?>[],
        },
      };
      final branches = (await api.fetchBranches('s1')).branches!;
      expect(branches.local, isEmpty);
      expect(branches.remote, isEmpty);
      expect(branches.current, isNull);
      expect(branches.isGit, isNull);
    });
  });

  group('gitApiFactoryProvider', () {
    test('默认工厂产出 GitApiClient：可完成一次真实解码往返', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final factory = container.read(gitApiFactoryProvider);
      final client = _RecordingApiClient()
        ..json = {
          'git': {'is_git': true, 'branch': 'release'},
        };
      final built = factory(client);

      expect(built, isA<GitApiClient>());
      expect(built, isA<GitApi>());

      final status = (await built.fetchStatus('s9')).git!;
      expect(status.branch, 'release');
      expect(client.last.path, '/api/git/status');
      expect(client.last.url, '$kBaseUrl/api/git/status?session_id=s9');
    });

    test('override 后工厂返回注入实现（对齐 git 测试的 fake 注入姿势）', () {
      final fake = GitApiClient(_RecordingApiClient());
      final container = ProviderContainer(
        overrides: [gitApiFactoryProvider.overrideWithValue((_) => fake)],
      );
      addTearDown(container.dispose);

      final built = container.read(gitApiFactoryProvider)(_RecordingApiClient());

      expect(identical(built, fake), isTrue);
    });
  });
}
