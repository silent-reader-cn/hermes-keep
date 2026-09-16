// 覆盖补强：prompts_providers.dart 的未覆盖区间。
//
// 目标（lcov 口径）：
//   - PromptsApiClient 三方法透传 + promptsApiFactoryProvider 默认实现
//   - SharedPreferences 缓存读取全分支（新鲜/过期/非 int 时间戳/非 Map/元素非法）
//   - drift 缓存行回退链
//   - _writeCache 双写（SP + drift）
//   - build() 首帧缓存预热（loading 期用缓存快速展示）
//   - refresh() 失败落 AsyncError（保留 previous value）
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_prompts_api.dart';

/// 与 SavedPromptsController._spKey 对齐（白盒断言缓存产物）。
const String spCacheKey = 'saved_prompts_cache_v1';

ProviderContainer makeContainer(FakePromptsApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      promptsApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

SavedPrompt prompt(String id, String text, {String? label}) =>
    SavedPrompt(id: id, label: label ?? text, text: text, createdAt: 1710000000);

Map<String, Object?> cachedPromptJson(String id, String text) => {
  'id': id,
  'label': 'cached $text',
  'text': text,
  'created_at': 1.0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PromptsApiClient / promptsApiFactoryProvider 默认实现', () {
    test('默认工厂 = PromptsApiClient.new，三方法透传 ApiClient（GET/POST/DELETE）', () async {
      final adapter = _RecordingJsonAdapter(
        jsonEncode({
          'ok': true,
          'prompts': [
            {
              'id': 'p1',
              'label': 'L',
              'text': 'T',
              'created_at': 1.0,
            },
          ],
          'prompt': {
            'id': 'p2',
            'label': 'L2',
            'text': 'T2',
            'created_at': 2.0,
          },
        }),
      );
      final dio = Dio(
        BaseOptions(validateStatus: (_) => true, followRedirects: false),
      );
      dio.httpClientAdapter = adapter;
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8787',
        dio: dio,
        publicMediaDio: dio,
      );

      // 未 override：走 Provider 体内的默认构造（行 47-48）。
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final factory = container.read(promptsApiFactoryProvider);
      expect(factory, isA<PromptsApiFactory>());

      final api = factory(client);
      expect(api, isA<PromptsApiClient>());

      final list = await api.fetchPrompts();
      expect(list.prompts, hasLength(1));
      expect(list.prompts!.single.id, 'p1');

      final created = await api.createPrompt(text: 'T', label: 'L');
      expect(created.ok, isTrue);
      expect(created.prompt!.id, 'p2');

      final deleted = await api.deletePrompt('abc123');
      expect(deleted.ok, isTrue);

      expect(adapter.requests.map((r) => r.method).toList(), [
        'GET',
        'POST',
        'DELETE',
      ]);
      expect(
        adapter.requests.every((r) => r.uri.path == '/api/prompts'),
        isTrue,
      );
      final postBody =
          jsonDecode(adapter.requests[1].data as String) as Map<String, dynamic>;
      expect(postBody['text'], 'T');
      expect(postBody['label'], 'L');
      final deleteBody =
          jsonDecode(adapter.requests[2].data as String) as Map<String, dynamic>;
      expect(deleteBody['id'], 'abc123');
    });

    test('label 缺省时 POST body 不含 label 键', () async {
      final adapter = _RecordingJsonAdapter(
        jsonEncode({'ok': true, 'prompt': null}),
      );
      final dio = Dio(
        BaseOptions(validateStatus: (_) => true, followRedirects: false),
      );
      dio.httpClientAdapter = adapter;
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8787',
        dio: dio,
        publicMediaDio: dio,
      );
      final api = PromptsApiClient(client);

      final created = await api.createPrompt(text: 'only text');
      expect(created.prompt, isNull);
      expect(created.ok, isTrue);
      final body =
          jsonDecode(adapter.requests.single.data as String) as Map<String, dynamic>;
      expect(body.containsKey('label'), isFalse);
      expect(body['text'], 'only text');
    });
  });

  group('SharedPreferences 缓存读取（_readCacheInternal 第一段）', () {
    test('新鲜缓存 + 阻塞 fetch → 首帧用缓存，fetch 完成后被服务端覆盖', () async {
      SharedPreferences.setMockInitialValues({
        spCacheKey: jsonEncode({
          'prompts': [
            cachedPromptJson('cached-1', 'cached text'),
            cachedPromptJson('cached-2', 'cached text 2'),
          ],
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      });
      final api = FakePromptsApi(initialPrompts: [prompt('srv-1', 'server')]);
      api.fetchGate = Completer<void>();
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);

      expect(
        c.read(savedPromptsControllerProvider),
        isA<AsyncLoading<List<SavedPrompt>>>(),
      );
      await pumpEventQueue();

      final prefill = c.read(savedPromptsControllerProvider).valueOrNull;
      expect(prefill, isNotNull);
      expect(prefill!.map((e) => e.id).toList(), ['cached-1', 'cached-2']);
      expect(prefill.first.text, 'cached text');
      expect(prefill.first.createdAt, 1.0);
      expect(prefill.first.label, 'cached cached text');

      api.fetchGate!.complete();
      await pumpEventQueue();
      final after = c.read(savedPromptsControllerProvider).valueOrNull;
      expect(after, isNotNull);
      expect(after!.single.id, 'srv-1');
    });

    test('过期缓存（超 7 天 TTL）→ 不采用，首帧保持 loading', () async {
      SharedPreferences.setMockInitialValues({
        spCacheKey: jsonEncode({
          'prompts': [cachedPromptJson('stale', 'stale text')],
          'cachedAt':
              DateTime.now().millisecondsSinceEpoch -
              const Duration(days: 8).inMilliseconds,
        }),
      });
      final api = FakePromptsApi(initialPrompts: const []);
      api.fetchGate = Completer<void>();
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);

      await pumpEventQueue();
      expect(c.read(savedPromptsControllerProvider).valueOrNull, isNull);
      expect(c.read(savedPromptsControllerProvider).isLoading, isTrue);

      api.fetchGate!.complete();
      await pumpEventQueue();
      expect(c.read(savedPromptsControllerProvider).valueOrNull, isEmpty);
    });

    test('cachedAt 非 int → 视为未过期（容错：ageOk 默认 true）', () async {
      SharedPreferences.setMockInitialValues({
        spCacheKey: jsonEncode({
          'prompts': [cachedPromptJson('noTS', 'no ts text')],
          'cachedAt': 'not-a-number',
        }),
      });
      final api = FakePromptsApi(initialPrompts: const []);
      api.fetchGate = Completer<void>();
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);

      await pumpEventQueue();
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(1));
      expect(
        c.read(savedPromptsControllerProvider).valueOrNull!.single.id,
        'noTS',
      );

      api.fetchGate!.complete();
      await pumpEventQueue();
    });

    test('cachedAt 缺失 → 视为未过期', () async {
      SharedPreferences.setMockInitialValues({
        spCacheKey: jsonEncode({
          'prompts': [cachedPromptJson('noKey', 'no key text')],
        }),
      });
      final api = FakePromptsApi(initialPrompts: const []);
      api.fetchGate = Completer<void>();
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);

      await pumpEventQueue();
      expect(
        c.read(savedPromptsControllerProvider).valueOrNull!.single.id,
        'noKey',
      );
      api.fetchGate!.complete();
      await pumpEventQueue();
    });

    test('元素混合：非 Map 跳过、Map 解析成功 → 只保留合法项', () async {
      SharedPreferences.setMockInitialValues({
        spCacheKey: jsonEncode({
          'prompts': [
            cachedPromptJson('ok-1', 'ok text'),
            'not-a-map',
            42,
            <String, Object?>{},
          ],
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      });
      final api = FakePromptsApi(initialPrompts: const []);
      api.fetchGate = Completer<void>();
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);

      await pumpEventQueue();
      final value = c.read(savedPromptsControllerProvider).valueOrNull!;
      // 空 Map 走 fromJson 的容错路径，全字段 null 不 throw → 仍入列。
      expect(value.length, 2);
      expect(value.first.id, 'ok-1');
      expect(value.last.id, isNull);
      api.fetchGate!.complete();
      await pumpEventQueue();
    });

    test('prompts 非 List / 顶层非 Map / 空串 → 缓存不可用，回落 drift', () async {
      for (final raw in <Object>[
        jsonEncode({'prompts': 'nope', 'cachedAt': 1}),
        jsonEncode([1, 2, 3]),
        '',
      ]) {
        SharedPreferences.setMockInitialValues({spCacheKey: raw});
        final api = FakePromptsApi(initialPrompts: [prompt('srv', 'server')]);
        api.fetchGate = Completer<void>();
        final c = makeContainer(api);
        // 同测试内多轮复用同一内存库：清掉上一轮 _writeCache 落下的行。
        final db = c.read(appDatabaseProvider);
        await db.delete(db.cachedSessions).go();
        final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
        addTearDown(sub.close);
        await pumpEventQueue();
        expect(c.read(savedPromptsControllerProvider).valueOrNull, isNull);
        api.fetchGate!.complete();
        await pumpEventQueue();
        expect(
          c.read(savedPromptsControllerProvider).valueOrNull!.single.id,
          'srv',
        );
      }
    });

    test('缓存列表全为非法元素（prompts 为空）→ 不采用缓存', () async {
      SharedPreferences.setMockInitialValues({
        spCacheKey: jsonEncode({
          'prompts': ['a', 'b'],
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      });
      final api = FakePromptsApi(initialPrompts: [prompt('srv', 'server')]);
      api.fetchGate = Completer<void>();
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);

      await pumpEventQueue();
      expect(c.read(savedPromptsControllerProvider).valueOrNull, isNull);
      api.fetchGate!.complete();
      await pumpEventQueue();
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(1));
    });
  });

  group('drift 缓存回退（_readCacheInternal 第二段）', () {
    test('SP 无数据 + drift 行存在 → 首帧用库内缓存', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = FakePromptsApi(initialPrompts: [prompt('srv', 'server')]);
      api.fetchGate = Completer<void>();
      final c = makeContainer(api);

      final db = c.read(appDatabaseProvider);
      await db
          .into(db.cachedSessions)
          .insertOnConflictUpdate(
            CachedSessionsCompanion.insert(
              sessionId: 'saved_prompts',
              payload: jsonEncode({
                'prompts': [
                  cachedPromptJson('db-1', 'db text'),
                  cachedPromptJson('db-2', 'db text 2'),
                ],
              }),
              cachedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final value = c.read(savedPromptsControllerProvider).valueOrNull;
      expect(value, isNotNull);
      expect(value!.map((e) => e.id).toList(), ['db-1', 'db-2']);
      expect(value.first.text, 'db text');

      api.fetchGate!.complete();
      await pumpEventQueue();
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(1));
    });

    test('drift 行 payload 非法（非 JSON / 非 Map / prompts 非 List）→ 返回 null', () async {
      for (final payload in <String>[
        'not json at all',
        jsonEncode([1, 2]),
        jsonEncode({'prompts': 'nope'}),
        jsonEncode({'prompts': ['x', 'y']}),
      ]) {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final api = FakePromptsApi(initialPrompts: [prompt('srv', 'server')]);
        api.fetchGate = Completer<void>();
        final c = makeContainer(api);
        final db = c.read(appDatabaseProvider);
        await db
            .into(db.cachedSessions)
            .insertOnConflictUpdate(
              CachedSessionsCompanion.insert(
                sessionId: 'saved_prompts',
                payload: payload,
                cachedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
        final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
        addTearDown(sub.close);
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          c.read(savedPromptsControllerProvider).valueOrNull,
          isNull,
          reason: 'payload=$payload 不应产生缓存命中',
        );
        api.fetchGate!.complete();
        await pumpEventQueue();
        expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(1));
      }
    });
  });

  group('_writeCache 双写（SP + drift）', () {
    test('build 成功后 SP 与 drift 都落缓存，且可被下次读取复用', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = FakePromptsApi(
        initialPrompts: [prompt('w1', 'write me', label: 'W1')],
      );
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(savedPromptsControllerProvider.future);
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(spCacheKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect((decoded['prompts'] as List).single['id'], 'w1');
      expect(decoded['cachedAt'], isA<int>());

      final db = c.read(appDatabaseProvider);
      final row = await (db.select(db.cachedSessions)
            ..where((t) => t.sessionId.equals('saved_prompts')))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(jsonDecode(row!.payload), isA<Map<String, Object?>>());

      // 复用：同一缓存可被新的 controller 实例读出（走 SP 快路径）。
      final api2 = FakePromptsApi(initialPrompts: const []);
      api2.fetchGate = Completer<void>();
      final c2 = makeContainer(api2);
      final sub2 = c2.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub2.close);
      await pumpEventQueue();
      expect(
        c2.read(savedPromptsControllerProvider).valueOrNull!.single.id,
        'w1',
      );
      api2.fetchGate!.complete();
      await pumpEventQueue();
    });

    test('remove 成功后缓存同步收敛（SP 内不再含被删项）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = FakePromptsApi(
        initialPrompts: [prompt('r1', 'keep'), prompt('r2', 'drop')],
      );
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(savedPromptsControllerProvider.future);
      await pumpEventQueue();

      await c.read(savedPromptsControllerProvider.notifier).remove('r2');
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      final decoded =
          jsonDecode(prefs.getString(spCacheKey)!) as Map<String, dynamic>;
      final ids = (decoded['prompts'] as List)
          .map((e) => (e as Map)['id'])
          .toList();
      expect(ids, ['r1']);
    });
  });

  group('build() 缓存预热与首帧时序', () {
    test('缓存非空但 build 已返回 AsyncData → 不覆盖服务端数据（行 158 守卫）', () async {
      SharedPreferences.setMockInitialValues({
        spCacheKey: jsonEncode({
          'prompts': [cachedPromptJson('cached', 'cached text')],
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      });
      final api = FakePromptsApi(initialPrompts: [prompt('srv', 'server')]);
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(savedPromptsControllerProvider.future);
      await pumpEventQueue();

      final value = c.read(savedPromptsControllerProvider).valueOrNull!;
      expect(value.single.id, 'srv');
      expect(api.fetchCount, 1);
    });
  });

  group('refresh() 失败路径', () {
    test('已经有数据时 refresh 抛 Exception → AsyncError 且保留 previous value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = FakePromptsApi(initialPrompts: [prompt('a1', 'hello')]);
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(savedPromptsControllerProvider.future);

      api.fetchError = NetworkException(NetworkExceptionKind.timedOut);
      await c.read(savedPromptsControllerProvider.notifier).refresh();

      final state = c.read(savedPromptsControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<NetworkException>());
      expect(state.stackTrace, isNotNull);
      // AsyncTransition 语义：错误态保留上一次的值，供 UI「不替换整板」。
      expect(state.valueOrNull, isNotNull);
      expect(state.valueOrNull!.single.id, 'a1');
      expect(c.read(savedPromptsCountProvider), 1);
    });

    test('无数据时 refresh 失败 → AsyncError 且无 previous value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = FakePromptsApi(initialPrompts: const []);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final c = makeContainer(api);
      final sub = c.listen(savedPromptsControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await expectLater(
        c.read(savedPromptsControllerProvider.future),
        throwsA(isA<ApiException>()),
      );

      api.fetchError = NetworkException(NetworkExceptionKind.other);
      await c.read(savedPromptsControllerProvider.notifier).refresh();
      final state = c.read(savedPromptsControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.valueOrNull, isNull);
      expect(c.read(savedPromptsCountProvider), 0);
      expect(c.read(savedPromptsIsEmptyProvider), isTrue);
    });
  });
}

/// 记录请求并回放固定 JSON 的假 HttpClientAdapter。
class _RecordingJsonAdapter implements HttpClientAdapter {
  _RecordingJsonAdapter(this.body);

  final String body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
