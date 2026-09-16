import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_settings.dart';

/// 桌面端窗口标题服务。
///
/// 职责：
/// 1. 维护当前窗口标题并在桌面端同步至原生窗口；
/// 2. 提供标题格式化纯函数（会话标题截断、默认标题兜底）；
/// 3. 非桌面平台安全 no-op。
class WindowTitleService {
  /// 默认应用标题。
  static const String defaultTitle = 'Hermes';

  /// 会话标题最大字符长度（超出截断并追加省略号）。
  static const int maxSessionTitleLength = 40;

  /// 是否为桌面平台。
  final bool isDesktop;

  /// 原生设置标题回调（注入用于测试）。
  final FutureOr<void> Function(String title)? onSetTitle;

  String _currentTitle = defaultTitle;

  /// 构造窗口标题服务。
  WindowTitleService({bool? isDesktop, this.onSetTitle})
    : isDesktop = isDesktop ?? isDesktopPlatform();

  /// 当前窗口标题。
  String get currentTitle => _currentTitle;

  /// 格式化窗口标题纯函数。
  ///
  /// - [sessionTitle] 为 null、空白、或占位名（'untitled' / 'untitled session'）时，返回默认标题 `'Hermes'`；
  /// - 字符长度超出 [maxTitleLength] 时截断并追加 `'...'`；
  /// - 最终格式为 `'<处理后标题> - Hermes'`。
  static String formatWindowTitle(
    String? sessionTitle, {
    int maxTitleLength = maxSessionTitleLength,
  }) {
    final trimmed = sessionTitle?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return defaultTitle;
    }
    final lower = trimmed.toLowerCase();
    if (lower == 'untitled' || lower == 'untitled session') {
      return defaultTitle;
    }

    String title = trimmed;
    if (title.characters.length > maxTitleLength) {
      title = '${title.characters.take(maxTitleLength).toString()}...';
    }
    return '$title - $defaultTitle';
  }

  /// 设置原生窗口标题。
  Future<void> setTitle(String title) async {
    _currentTitle = title;
    if (!isDesktop) return;

    try {
      if (onSetTitle != null) {
        await onSetTitle!(title);
      } else {
        await windowManager.setTitle(title);
      }
    } catch (e, st) {
      developer.log(
        'Failed to set window title: $title',
        name: 'WindowTitleService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 根据会话标题更新窗口标题。
  Future<void> updateSessionTitle(String? sessionTitle) async {
    final formatted = formatWindowTitle(sessionTitle);
    await setTitle(formatted);
  }

  /// 重置为默认窗口标题 'Hermes'。
  Future<void> resetTitle() async {
    await setTitle(defaultTitle);
  }
}

/// 窗口标题服务 Provider。
final windowTitleServiceProvider = Provider<WindowTitleService>((ref) {
  return WindowTitleService();
});

/// 当前活跃会话 ID（由桌面路由监听器维护）。
///
/// 记录所有带会话 id 的路由：`/chat/:id`、`/workspace/:id`、`/git/:id`。
final activeSessionIdProvider = StateProvider<String?>((ref) => null);

/// 当前活跃的 **chat 路由**会话 ID —— 仅 `/chat/:id` 时非 null。
///
/// 与 [activeSessionIdProvider] 的区别：工作区/Git 详情页也会写后者，但它们
/// **不需要聊天控制器**。标题链路只认本 provider，避免「仅为读一个窗口标题，
/// 就把 chatController 建起来」——真实控制器会拉起 clarify/approval/content
/// 三条通道并调用 loadMessages()（chat_controller.dart:259-267），属纯开销。
final activeChatSessionIdProvider = StateProvider<String?>((ref) => null);
