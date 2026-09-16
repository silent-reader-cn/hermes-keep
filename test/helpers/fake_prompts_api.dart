import 'dart:async';

import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';

/// 可配置的 [PromptsApi] fake（测试注入，彻底绕开网络）.
class FakePromptsApi implements PromptsApi {
  FakePromptsApi({List<SavedPrompt>? initialPrompts})
    : _prompts = [...?initialPrompts];

  final List<SavedPrompt> _prompts;
  List<SavedPrompt> get prompts => List.unmodifiable(_prompts);

  Object? fetchError;
  Object? createError;
  Object? deleteError;

  /// create 成功后返回的自定义 prompt（null 则按 text/label 自动构造）.
  SavedPrompt? createResult;

  /// delete 返回 ok==false 时的回显（否则 ok==true）.
  bool deleteOk = true;

  /// 非 null 时 create 返回 `ok: false` 且带该 error 文案（模拟服务端
  /// 业务层拒绝，如「已达上限 (max 200)」——HTTP 200 但 body 表示失败）。
  String? createRejectReason;

  /// 延迟 gate（测试加载态用）.
  Completer<void>? fetchGate;

  int fetchCount = 0;
  int createCount = 0;
  int deleteCount = 0;
  String? lastCreateText;
  String? lastCreateLabel;
  String? lastDeleteId;

  @override
  Future<SavedPromptsResponse> fetchPrompts() async {
    fetchCount++;
    if (fetchError != null) throw fetchError!;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    return SavedPromptsResponse(prompts: [..._prompts]);
  }

  @override
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  }) async {
    createCount++;
    lastCreateText = text;
    lastCreateLabel = label;
    if (createError != null) throw createError!;
    final reason = createRejectReason;
    if (reason != null) {
      return SavePromptResponse(ok: false, error: reason);
    }
    final prompt =
        createResult ??
        SavedPrompt(
          id: 'id_$createCount',
          label:
              label ?? text.substring(0, text.length > 60 ? 60 : text.length),
          text: text,
          createdAt: DateTime.now().millisecondsSinceEpoch / 1000,
        );
    _prompts.add(prompt);
    return SavePromptResponse(ok: true, prompt: prompt);
  }

  @override
  Future<DeletePromptResponse> deletePrompt(String id) async {
    deleteCount++;
    lastDeleteId = id;
    if (deleteError != null) throw deleteError!;
    _prompts.removeWhere((p) => p.id == id);
    return DeletePromptResponse(ok: deleteOk);
  }
}
