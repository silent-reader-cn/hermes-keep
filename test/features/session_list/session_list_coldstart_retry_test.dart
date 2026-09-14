import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_session_list_api.dart';

SessionSummary buildSession(String id, String title) {
  return SessionSummary(
    sessionId: id,
    title: title,
    lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
  );
}

ServerConnection remoteConn() {
  return ServerConnection(
    id: 'remote-1',
    name: 'Remote Server',
    baseUrl: 'http://test.local:30002',
    kind: ConnectionKind.remote,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

ServerConnection builtinConn() {
  return ServerConnection(
    id: ServerConnection.builtinId,
    name: 'Built-in WebUI',
    baseUrl: 'http://127.0.0.1:8787',
    kind: ConnectionKind.builtin,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

ProviderContainer makeContainer(
  FakeSessionListApi api, {
  ServerConnection? active,
}) {
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
      activeConnectionProvider.overrideWith(
        () => _StubActiveConnection(active ?? remoteConn()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _StubActiveConnection extends ActiveConnectionController {
  _StubActiveConnection(this._connection);

  final ServerConnection? _connection;

  @override
  ServerConnection? build() => _connection;
}

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);
  @override
  Future<ProjectMutationResponse> createProject(
          {required String name, String? color}) async =>
      const ProjectMutationResponse(ok: true);
  @override
  Future<ProjectMutationResponse> renameProject(
          {required String projectId, required String name, String? color}) async =>
      const ProjectMutationResponse(ok: true);
  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

void main() {
  group('SessionListController.shouldRetryColdStartFetch 判据 (#111)', () {
    test('连接层快速失败（连接被拒 / DNS / 离线）→ 补偿', () {
      expect(
        SessionListController.shouldRetryColdStartFetch(
          NetworkException(NetworkExceptionKind.cannotConnect),
        ),
        isTrue,
      );
      expect(
        SessionListController.shouldRetryColdStartFetch(
          NetworkException(NetworkExceptionKind.cannotFindHost),
        ),
        isTrue,
      );
      expect(
        SessionListController.shouldRetryColdStartFetch(
          NetworkException(NetworkExceptionKind.offline),
        ),
        isTrue,
      );
    });

    test('超时 / TLS / 取消 / 401 / 500 → 不补偿', () {
      expect(
        SessionListController.shouldRetryColdStartFetch(
          NetworkException(NetworkExceptionKind.timedOut),
        ),
        isFalse,
      );
      expect(
        SessionListController.shouldRetryColdStartFetch(
          NetworkException(NetworkExceptionKind.tls),
        ),
        isFalse,
      );
      expect(
        SessionListController.shouldRetryColdStartFetch(
          NetworkException(NetworkExceptionKind.cancelled),
        ),
        isFalse,
      );
      expect(
        SessionListController.shouldRetryColdStartFetch(
          const UnauthorizedException(),
        ),
        isFalse,
      );
      expect(
        SessionListController.shouldRetryColdStartFetch(
          HttpException(500, 'Internal Server Error'),
        ),
        isFalse,
      );
    });

    test('网关侧瞬断 502/503/504 → 补偿', () {
      for (final status in const [502, 503, 504]) {
        expect(
          SessionListController.shouldRetryColdStartFetch(
            HttpException(status, 'Gateway'),
          ),
          isTrue,
          reason: 'HTTP $status',
        );
      }
    });
  });

  group('冷启动首屏静默重试 (#111)', () {
    test('远程连接 + 冷启动 + 连接被拒（首次失败）→ 退避后重试一次即成功', () {
      fakeAsync((async) {
        final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
        api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
        api.fetchErrorCap = 1; // 首次抛错，第二次起成功
        final c = makeContainer(api);

        SessionListState? loaded;
        Object? failure;
        unawaited(
          c.read(sessionListControllerProvider.future).then(
            (value) => loaded = value,
            onError: (Object error) => failure = error,
          ),
        );
        async.flushMicrotasks();

        // 第一次失败：尚未重试（退避窗口内）。
        expect(api.fetchCount, 1);
        expect(loaded, isNull);
        expect(failure, isNull);

        // 退避后静默重试一次 → 成功，首屏不再红屏。
        async.elapse(SessionListController.coldStartRetryBackoff);
        async.flushMicrotasks();
        expect(api.fetchCount, 2);
        expect(failure, isNull);
        expect(loaded?.sessions.single.sessionId, 's1');
      });
    });

    test('远程连接 + 冷启动 + 连接被拒（持续失败）→ 只补偿一次，仍失败则原样抛出', () {
      fakeAsync((async) {
        final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
        api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
        final c = makeContainer(api);

        Object? failure;
        unawaited(
          c.read(sessionListControllerProvider.future).then(
            (value) {},
            onError: (Object error) => failure = error,
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        // 首屏 1 + 补偿 1 = 2，不产生雪崩式重试。
        expect(api.fetchCount, 2);
        expect(failure, isA<NetworkException>());
        expect(c.read(sessionListControllerProvider).hasError, isTrue);
      });
    });

    test('内置连接 + 冷启动失败 → 不补偿（保留 #72 静默宽限契约）', () {
      fakeAsync((async) {
        final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
        api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
        api.fetchErrorCap = 1;
        final c = makeContainer(api, active: builtinConn());

        Object? failure;
        unawaited(
          c.read(sessionListControllerProvider.future).then(
            (value) {},
            onError: (Object error) => failure = error,
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        // 失败次数保持 1：宽限状态机接管（无缓存 → 抛出，由 UI 重试按钮兜底）。
        expect(api.fetchCount, 1);
        expect(failure, isA<NetworkException>());
      });
    });

    test('远程连接 + 冷启动 + receiveTimeout → 不补偿（避免首屏空窗翻倍）', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.fetchError = NetworkException(NetworkExceptionKind.timedOut);
      final c = makeContainer(api);

      await expectLater(
        c.read(sessionListControllerProvider.future),
        throwsA(isA<NetworkException>()),
      );
      expect(api.fetchCount, 1);
      expect(c.read(sessionListControllerProvider).hasError, isTrue);
    });

    test('首屏成功后的手动 refresh 失败 → 不补偿（仅冷启动首屏）', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      final c = makeContainer(api);

      await c.read(sessionListControllerProvider.future);
      expect(api.fetchCount, 1);

      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await c.read(sessionListControllerProvider.notifier).refresh();

      // 首屏 1 + refresh 1，无额外补偿请求。
      expect(api.fetchCount, 2);
      final state = c.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions.single.sessionId, 's1');
      expect(state.consecutiveFailures, 1);
    });
  });
}
