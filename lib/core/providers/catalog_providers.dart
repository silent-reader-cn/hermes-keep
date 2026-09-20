import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_client_server_panels.dart';
import '../api/api_client_workspace.dart';
import '../connections/connection_providers.dart';
import '../models/workspace.dart';

/// 桌面端外壳共享目录 provider（#145）。
///
/// 侧栏工作区选择器与输入区「工作区 / 模型」元信息 chip 需要同一份
/// 目录数据，故集中在此，避免两处各自拉取（两处口径不一致会造出
/// 「侧栏显示 A 工作区、chip 显示 B」这类自相矛盾的界面）。
///
/// 容错口径与上下文弹层（`context_window_popover._maybeFetchModels` /
/// `_fetchWorkspaces`）保持一致：**无激活连接或网络失败一律返回空列表，
/// 不抛错、不弹窗**——调用方按「空列表 = 未知」静默退化，绝不因目录拉取
/// 失败阻断聊天或侧栏。

/// 可用模型 id 列表（`GET /api/models/live`）。
///
/// 按「小写 + 空格/下划线归一为连字符」去重（与弹层同一归一规则，
/// 避免 `Foo Bar` / `foo_bar` 这类同模型重复出现），保留首个出现的原始
/// 大小写形式供显示与回传。
final availableModelIdsProvider = FutureProvider<List<String>>((ref) async {
  final ApiClient client;
  try {
    client = ref.watch(apiClientProvider);
  } catch (_) {
    // 未配置 / 未激活任何服务器连接。
    return const <String>[];
  }
  try {
    final response = await client.modelsLive();
    final ids = <String>[];
    final seen = <String>{};
    for (final option in response.liveOptions) {
      final id = option.id.trim();
      if (id.isEmpty) continue;
      final normKey = id
          .toLowerCase()
          .replaceAll(' ', '-')
          .replaceAll('_', '-');
      if (seen.add(normKey)) {
        ids.add(id);
      }
    }
    return ids;
  } catch (_) {
    // 网络 / 解析失败：静默退化为空列表。
    return const <String>[];
  }
});

/// 工作区根列表（`GET /api/workspaces`）。
///
/// 端点为「已登记的工作区根」，供侧栏聚合视图与 chip 选择器使用；
/// 与按会话浏览文件树的 `workspaceControllerProvider`（family by sessionId）
/// 不是同一件事，勿混用。
final workspaceRootsProvider = FutureProvider<List<WorkspaceRoot>>((
  ref,
) async {
  final ApiClient client;
  try {
    client = ref.watch(apiClientProvider);
  } catch (_) {
    return const <WorkspaceRoot>[];
  }
  try {
    final response = await client.workspaces();
    return response.workspaces ?? const <WorkspaceRoot>[];
  } catch (_) {
    return const <WorkspaceRoot>[];
  }
});
