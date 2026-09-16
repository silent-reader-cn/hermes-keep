import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_prompts.dart';
import '../../core/api/api_exception.dart';
import '../../core/cache/app_database.dart';
import '../../core/cache/cache_providers.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/saved_prompt.dart';

/// 收藏提示词 API 工厂（测试可 override 注入 fake）。
abstract interface class PromptsApi {
  Future<SavedPromptsResponse> fetchPrompts();
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  });
  Future<DeletePromptResponse> deletePrompt(String id);
}

/// [PromptsApi] 的生产实现，包 [ApiClient]。
class PromptsApiClient implements PromptsApi {
  PromptsApiClient(this._client);

  final ApiClient _client;

  @override
  Future<SavedPromptsResponse> fetchPrompts() => _client.fetchPrompts();

  @override
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  }) => _client.createPrompt(text: text, label: label);

  @override
  Future<DeletePromptResponse> deletePrompt(String id) =>
      _client.deletePrompt(id);
}

typedef PromptsApiFactory = PromptsApi Function(ApiClient client);

final promptsApiFactoryProvider = Provider<PromptsApiFactory>(
  (ref) => PromptsApiClient.new,
);

/// 收藏提示词控制器（列表 CRUD）。
///
/// 缓存策略：先读 SharedPreferences/drift 缓存即显列表后静默刷新，无缓存才 loading。
/// 覆盖式小 indicator 而非替换整板。
final savedPromptsControllerProvider =
    AsyncNotifierProvider<SavedPromptsController, List<SavedPrompt>>(
      SavedPromptsController.new,
    );

class SavedPromptsController extends AsyncNotifier<List<SavedPrompt>> {
  PromptsApi get _api =>
      ref.read(promptsApiFactoryProvider)(ref.read(apiClientProvider));

  static const String _spKey = 'saved_prompts_cache_v1';
  static const Duration _spTtl = Duration(days: 7);

  Future<List<SavedPrompt>?> _readCacheInternal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_spKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final list = decoded['prompts'];
          final ts = decoded['cachedAt'];
          if (list is List) {
            // 时间戳缺失 / 类型不符一律视为「已过期」：畸形缓存比没有缓存更危险
            //（写坏一次就永久有效，TTL 形同虚设），代价只是多一次网络请求。
            final ageOk = ts is int
                ? (DateTime.now().millisecondsSinceEpoch - ts) <
                    _spTtl.inMilliseconds
                : false;
            if (ageOk) {
              final prompts = <SavedPrompt>[];
              for (final e in list) {
                if (e is Map) {
                  try {
                    prompts.add(
                      SavedPrompt.fromJson(Map<String, Object?>.from(e)),
                    );
                  } catch (_) {}
                }
              }
              if (prompts.isNotEmpty) return prompts;
            }
          }
        }
      }
    } catch (_) {}
    try {
      final db = ref.read(appDatabaseProvider);
      final row = await (db.select(db.cachedSessions)
            ..where((t) => t.sessionId.equals('saved_prompts')))
          .getSingleOrNull();
      if (row != null) {
        final payload = jsonDecode(row.payload);
        if (payload is Map && payload['prompts'] is List) {
          final list = payload['prompts'] as List;
          final prompts = <SavedPrompt>[];
          for (final e in list) {
            if (e is Map) {
              try {
                prompts.add(SavedPrompt.fromJson(Map<String, Object?>.from(e)));
              } catch (_) {}
            }
          }
          if (prompts.isNotEmpty) return prompts;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<SavedPrompt>?> _readCache() async {
    try {
      return await _readCacheInternal();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<SavedPrompt> prompts) async {
    final payload = jsonEncode({
      'prompts': prompts.map((e) => e.toJson()).toList(),
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_spKey, payload);
    } catch (_) {}
    try {
      final db = ref.read(appDatabaseProvider);
      await db.into(db.cachedSessions).insertOnConflictUpdate(
            CachedSessionsCompanion.insert(
              sessionId: 'saved_prompts',
              title: const Value('saved_prompts'),
              payload: payload,
              cachedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    } catch (_) {}
  }

  @override
  Future<List<SavedPrompt>> build() async {
    // 缓存预热在后台静默进行，不阻塞首帧 data；首帧仍走 fetch 以保证测试时序与实时性
    unawaited(_readCache().then((cached) {
      if (cached != null && cached.isNotEmpty) {
        // 若首帧已是 AsyncData 则不覆盖，否则用缓存快速展示
        if (state is AsyncLoading) state = AsyncData(cached);
      }
    }));
    final api = ref.watch(promptsApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    final response = await api.fetchPrompts();
    final fresh = response.prompts ?? const <SavedPrompt>[];
    unawaited(_writeCache(fresh));
    return fresh;
  }

  /// 下拉/错误态重试：重新拉取。
  Future<void> refresh() async {
    try {
      final response = await _api.fetchPrompts();
      final fresh = response.prompts ?? const <SavedPrompt>[];
      unawaited(_writeCache(fresh));
      state = AsyncData(fresh);
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 收藏当前输入。
  Future<SavedPrompt?> create({required String text, String? label}) async {
    final response = await _api.createPrompt(text: text, label: label);
    final prompt = response.prompt;
    if (response.ok == true && prompt != null) {
      final current = state.valueOrNull;
      if (current != null) {
        final next = [...current, prompt];
        state = AsyncData(next);
        unawaited(_writeCache(next));
      }
      try {
        final refreshed = await _api.fetchPrompts();
        final list = refreshed.prompts ?? const <SavedPrompt>[];
        unawaited(_writeCache(list));
        state = AsyncData(list);
      } catch (_) {}
      return prompt;
    }
    // 服务端明确拒绝（HTTP 200 但 ok=false）时把原因抛出去：否则
    // response.error（如「已达上限 (max 200)」）会被调用侧丢弃，
    // 用户只能看到通用「收藏失败」，永远不知道该删几条。
    final reason = response.error?.trim();
    if (reason != null && reason.isNotEmpty) {
      throw RequestRejectedException(reason);
    }
    return prompt;
  }

  /// 删除指定 id（后端幂等），乐观删除 + 失败回滚并透传异常。
  Future<void> remove(String id) async {
    final previous = state.valueOrNull;
    if (previous != null) {
      final next = previous.where((p) => p.id != id).toList();
      state = AsyncData(next);
      unawaited(_writeCache(next));
    }
    try {
      final response = await _api.deletePrompt(id);
      if (response.ok == false) {
        if (previous != null) {
          state = AsyncData(previous);
          // state 回滚了，缓存也必须回滚：:210 已乐观写过 next。
          // 只还原 state 会让 7 天 TTL 内的冷启动先渲染缺失列表、
          // 再被后续拉取静默补回（视觉闪变）。
          unawaited(_writeCache(previous));
        }
        return;
      }
      try {
        final refreshed = await _api.fetchPrompts();
        final list = refreshed.prompts ?? const <SavedPrompt>[];
        unawaited(_writeCache(list));
        state = AsyncData(list);
      } catch (_) {}
    } on Exception {
      if (previous != null) {
        state = AsyncData(previous);
        unawaited(_writeCache(previous)); // 同上：缓存与 state 一并回滚
      }
      rethrow;
    }
  }
}

/// 收藏数量派生（测试可注入性验证 + UI 角标用）。
final savedPromptsCountProvider = Provider<int>((ref) {
  return ref.watch(savedPromptsControllerProvider).valueOrNull?.length ?? 0;
});

/// 是否为空派生。
final savedPromptsIsEmptyProvider = Provider<bool>((ref) {
  final value = ref.watch(savedPromptsControllerProvider).valueOrNull;
  if (value == null) return true;
  return value.isEmpty;
});

/// 展示名：label 优先，空/缺失回落 text 的前 60 字符（同后端截断）。
String savedPromptDisplayLabel(SavedPrompt prompt) {
  final label = prompt.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  final text = prompt.text ?? '';
  if (text.length <= 60) return text;
  return text.substring(0, 60);
}
