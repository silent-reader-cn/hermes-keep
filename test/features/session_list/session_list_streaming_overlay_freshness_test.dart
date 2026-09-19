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

ServerConnection _conn() {
  return ServerConnection(
    id: 'c1',
    name: 'Test',
    baseUrl: 'http://test.local:30002',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

class _StubActiveConnection extends ActiveConnectionController {
  _StubActiveConnection(this._connection);
  final ServerConnection _connection;
  @override
  ServerConnection? build() => _connection;
}

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

ProviderContainer _makeContainer(FakeSessionListApi sessionApi) {
  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      activeConnectionProvider.overrideWith(
        () => _StubActiveConnection(_conn()),
      ),
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => FakeOnboardingLoginApi(),
      ),
    ],
  );
}

/// #142：本地乐观 streaming 标记的「新鲜度」契约。
///
/// 真机症状：长回合 + 反复锁屏解锁后，会话永久显示「活动中」，刷新/点开/返回
/// 全部无效，唯有杀进程重开才恢复。
///
/// 根因：`_overlayStreaming` 把本地乐观标记**无条件**盖到服务端数据上
/// （`isStreaming: true` 硬编码），于是服务端已返回 `is_streaming: false` 也被
/// 覆盖回 true；而 `_streamingSessions` 是内存 Map，只有杀进程才释放。
///
/// 修复契约：覆盖**仅在标记新鲜时**生效（`localStreamingOverlayGrace`）；
/// 陈旧标记一律以服务端为准，并触发一次后台求证把状态清干净。
void main() {
  const session = SessionSummary(
    sessionId: 's1',
    title: '会话 1',
    createdAt: 1000,
    messageCount: 2,
  );

  /// 把宽限期压到 20ms，便于在用例内制造「陈旧」；用例结束自动还原。
  void useShortGrace() {
    localStreamingOverlayGrace = const Duration(milliseconds: 20);
    addTearDown(
      () => localStreamingOverlayGrace = const Duration(seconds: 60),
    );
  }

  SessionSummary s1Of(ProviderContainer c) => c
      .read(sessionListControllerProvider)
      .valueOrNull!
      .sessions
      .firstWhere((s) => s.sessionId == 's1');

  Future<SessionListController> setup(ProviderContainer container) async {
    await container.read(sessionListControllerProvider.future);
    return container.read(sessionListControllerProvider.notifier);
  }

  group('#142 本地乐观 streaming 标记新鲜度', () {
    test('RED-1 核心：陈旧标记 + 服务端已结束 ⇒ 刷新后必须以服务端为准（不再被覆盖）', () async {
      useShortGrace();
      final api = FakeSessionListApi(sessions: [session]);
      // 令「后台求证」不可用 —— 这样清除路径失效，唯一变量就只剩
      // `_overlayStreaming` 到底还覆不覆盖（精确隔离本修复的效果）。
      api.statusError = HttpException(500, null, message: 'probe blocked');
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container);
      controller.markStreaming('s1', true, activeStreamId: 'stream-stale');
      expect(s1Of(container).isStreaming, isTrue, reason: '乐观置位应即时生效');

      // 越过宽限期 → 标记变陈旧
      await Future<void>.delayed(const Duration(milliseconds: 60));

      await controller.refresh();

      expect(
        s1Of(container).isStreaming,
        isNot(true),
        reason: '陈旧标记不得再压过服务端（修复前此处为 true → 永久卡住）；服务端未标流式时回落为 null 亦属正确',
      );
      expect(s1Of(container).activeStreamId, isNull);
    });

    test('RED-2 防回归：新鲜标记 + 服务端滞后 ⇒ 仍覆盖，保住防抖动原意', () async {
      // 默认宽限 60s，置位后立即刷新 → 标记新鲜
      final api = FakeSessionListApi(sessions: [session]);
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container);
      controller.markStreaming('s1', true, activeStreamId: 'stream-fresh');

      await controller.refresh();

      expect(
        s1Of(container).isStreaming,
        isTrue,
        reason: '刚置位时的服务端滞后抖动必须被本地覆盖兜住（既有契约，不得改坏）',
      );
      expect(s1Of(container).activeStreamId, 'stream-fresh');
    });

    test('RED-3 不误清：陈旧标记 + 服务端仍在流式 ⇒ 仍显示流式（陈旧只关覆盖，不改真相）', () async {
      useShortGrace();
      final api = FakeSessionListApi(
        sessions: [session.copyWith(isStreaming: true, activeStreamId: 'srv-1')],
      );
      api.statusResponses['s1'] = const SessionStatusResponse(
        sessionId: 's1',
        isStreaming: true,
        activeStreamId: 'srv-1',
      );
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container);
      controller.markStreaming('s1', true, activeStreamId: 'stream-1');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      await controller.refresh();

      expect(
        s1Of(container).isStreaming,
        isTrue,
        reason: '真在跑的长任务不得因本地标记陈旧而被误清（服务端才是权威）',
      );
    });

    test('RED-4 陈旧标记会触发一次后台求证（把状态清干净的通道）', () async {
      useShortGrace();
      final api = FakeSessionListApi(sessions: [session]);
      api.statusResponses['s1'] = const SessionStatusResponse(
        sessionId: 's1',
        isStreaming: false,
        activeStreamId: null,
      );
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container);
      controller.markStreaming('s1', true, activeStreamId: 'stream-old');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      await controller.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        api.statusCalls,
        contains('s1'),
        reason: '陈旧标记必须触发后台求证，否则内存标记永远清不掉',
      );
      expect(s1Of(container).isStreaming, isNot(true));
    });

    test('RED-5 时间戳不泄漏：显式清除后本地标记表不再持有该会话', () async {
      final api = FakeSessionListApi(sessions: [session]);
      final container = _makeContainer(api);
      addTearDown(container.dispose);

      final controller = await setup(container);
      controller.markStreaming('s1', true, activeStreamId: 'stream-1');
      expect(controller.hasLocalStreamingMarkForTesting('s1'), isTrue);

      controller.markStreaming('s1', false);
      expect(
        controller.hasLocalStreamingMarkForTesting('s1'),
        isFalse,
        reason: '清除标记必须同步清掉时间戳，否则残留会让它「永远新鲜」',
      );
    });
  });
}
