import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_utility_item.dart';

/// 侧栏导航入口的「位置 + 顺序」配置（#154）。
///
/// 宽屏侧栏有两处承载页面入口：
/// - **最上方**：[SidebarToolsList] 的纵向列表（默认 `new_session / tasks / kanban / skills`）；
/// - **右下角**：[SidebarSecondaryTools] 的一排小图标
///   （默认 `workspaces / insights / memory / downloads / settings`）。
///
/// 本模型只管这两处的**成员归属与顺序**；入口的**显隐**仍由
/// `SessionEntryVisibility`（设置页「会话列表入口」）负责，两者正交、互不覆盖。
///
/// 设计要点：
/// - `new_session`（新建会话）是**动作项**而非页面入口，但同样纳入可排序
///   （对齐 Codex 侧栏做法：常用动作与页面入口同一个列表里排）。
/// - 所有读入路径都**绝不抛异常**：JSON 坏了、id 不认识、重复项、缺项，
///   一律经 [normalized] 收敛；新版本新增的入口若不在用户旧配置里，
///   会自动补到 [bottom] 末尾（升级不丢入口）。
class SidebarNavOrder {
  const SidebarNavOrder({
    this.top = defaultTop,
    this.bottom = defaultBottom,
  });

  /// 动作项 id（不在 [sidebarUtilityItems] 里，但可参与排序）。
  static const String newSessionId = 'new_session';

  /// 默认「侧栏最上方」顺序（与 #153 前的硬编码 `_topIds` 一致）。
  static const List<String> defaultTop = <String>[
    newSessionId,
    'tasks',
    'kanban',
    'skills',
  ];

  /// 默认「侧栏右下角」顺序。
  static const List<String> defaultBottom = <String>[
    'workspaces',
    'insights',
    'memory',
    'downloads',
    'settings',
  ];

  /// 默认配置。
  static const SidebarNavOrder defaults = SidebarNavOrder();

  /// 全部**可配置**入口 id（动作项 + 页面入口）。
  ///
  /// 刻意排除 `sessions`（会话列表）：它是侧栏的**隐含主页** —— 侧栏本身就长在
  /// 会话列表里，从无对应的独立入口按钮。若不排除，[normalized] 会把它当作
  /// 「缺失项」补进右下角，凭空多出一个图标（实测踩到）。
  static List<String> get knownIds => <String>[
    newSessionId,
    for (final item in sidebarUtilityItems)
      if (item.id != sessionsId) item.id,
  ];

  /// 隐含主页 id（不参与位置配置）。
  static const String sessionsId = 'sessions';

  /// 侧栏最上方展示的入口 id（顺序即展示顺序）。
  final List<String> top;

  /// 侧栏右下角展示的入口 id（顺序即展示顺序）。
  final List<String> bottom;

  /// 收敛成合法配置：剔除未知 id、去重、补齐缺失 id（补到 bottom 末尾）。
  ///
  /// 任何来源的数据都先过这里，保证渲染侧永远拿到「恰好覆盖全部已知 id、
  /// 无重复、无未知」的两个列表。
  SidebarNavOrder normalized() {
    final known = knownIds.toSet();
    final seen = <String>{};
    final nextTop = <String>[];
    final nextBottom = <String>[];

    void take(Iterable<String> source, List<String> target) {
      for (final id in source) {
        if (!known.contains(id) || !seen.add(id)) continue;
        target.add(id);
      }
    }

    take(top, nextTop);
    take(bottom, nextBottom);
    // 缺失的（含新版本新增入口）补到右下角末尾，保证不丢入口。
    for (final id in knownIds) {
      if (seen.add(id)) nextBottom.add(id);
    }

    return SidebarNavOrder(
      top: List<String>.unmodifiable(nextTop),
      bottom: List<String>.unmodifiable(nextBottom),
    );
  }

  /// 该入口是否位于「最上方」区。
  bool isInTop(String id) => top.contains(id);

  SidebarNavOrder copyWith({List<String>? top, List<String>? bottom}) {
    return SidebarNavOrder(top: top ?? this.top, bottom: bottom ?? this.bottom);
  }

  /// 序列化为 JSON 字符串（持久化用）。
  String toJson() => jsonEncode(<String, Object?>{'top': top, 'bottom': bottom});

  /// 从 JSON 字符串解析；任何异常/畸形输入都回退默认（绝不抛）。
  static SidebarNavOrder fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaults;
      final top = _stringList(decoded['top']);
      final bottom = _stringList(decoded['bottom']);
      return SidebarNavOrder(top: top, bottom: bottom).normalized();
    } catch (_) {
      return defaults;
    }
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return <String>[
      for (final entry in value)
        if (entry is String) entry,
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SidebarNavOrder &&
          runtimeType == other.runtimeType &&
          _listEquals(top, other.top) &&
          _listEquals(bottom, other.bottom);

  @override
  int get hashCode => Object.hash(Object.hashAll(top), Object.hashAll(bottom));

  @override
  String toString() => 'SidebarNavOrder(top: $top, bottom: $bottom)';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 侧栏导航入口「位置 + 顺序」Provider（持久化到 shared_preferences）。
final sidebarNavOrderProvider =
    NotifierProvider<SidebarNavOrderController, SidebarNavOrder>(
      SidebarNavOrderController.new,
    );

/// 控制侧栏导航入口位置与顺序的 Notifier。
class SidebarNavOrderController extends Notifier<SidebarNavOrder> {
  /// 持久化 key。
  static const String storageKey = 'sidebar_nav_order';

  @override
  SidebarNavOrder build() {
    unawaited(_load());
    return const SidebarNavOrder();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = SidebarNavOrder.fromJson(prefs.getString(storageKey));
    } catch (_) {
      // 平台通道缺失（单测/异常环境）→ 保持默认，不影响渲染。
    }
  }

  Future<void> _persist(SidebarNavOrder next) async {
    state = next.normalized();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, state.toJson());
    } catch (_) {
      // 写入失败只影响持久化，不丢当前会话内的状态。
    }
  }

  /// 在「最上方」区内重排（拖拽回调语义：newIndex 为移除前的插入位）。
  Future<void> reorderTop(int oldIndex, int newIndex) =>
      _reorder(state.top, oldIndex, newIndex, (list) {
        return _persist(state.copyWith(top: list));
      });

  /// 在「右下角」区内重排。
  Future<void> reorderBottom(int oldIndex, int newIndex) =>
      _reorder(state.bottom, oldIndex, newIndex, (list) {
        return _persist(state.copyWith(bottom: list));
      });

  Future<void> _reorder(
    List<String> source,
    int oldIndex,
    int newIndex,
    Future<void> Function(List<String> next) apply,
  ) async {
    if (oldIndex < 0 || oldIndex >= source.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, source.length - 1);
    if (target == oldIndex) return;
    final next = List<String>.of(source);
    final moved = next.removeAt(oldIndex);
    next.insert(target, moved);
    await apply(next);
  }

  /// 把入口移到「最上方」区（末尾）。
  Future<void> moveToTop(String id) async {
    if (state.isInTop(id)) return;
    final bottom = List<String>.of(state.bottom)..remove(id);
    final top = List<String>.of(state.top)..add(id);
    await _persist(SidebarNavOrder(top: top, bottom: bottom));
  }

  /// 把入口移到「右下角」区（末尾）。
  Future<void> moveToBottom(String id) async {
    if (!state.isInTop(id)) return;
    final top = List<String>.of(state.top)..remove(id);
    final bottom = List<String>.of(state.bottom)..add(id);
    await _persist(SidebarNavOrder(top: top, bottom: bottom));
  }

  /// 恢复默认顺序与归属。
  Future<void> reset() => _persist(const SidebarNavOrder());
}