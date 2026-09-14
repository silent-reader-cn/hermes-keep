import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/api/api_client.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/session.dart';
import '../desktop/desktop_settings.dart';
import '../notifications/notification_providers.dart';
import 'session_events_client.dart';
import 'session_list_providers.dart';

/// 会话列表活跃流同步回调（检测到活跃流集合变化时调用）。
typedef SessionStreamingSyncCallback = void Function(
  int activeCount,
  List<String> titles,
);

/// 会话列表活跃流同步回调 Provider（notifications feature 注入点）。
final sessionStreamingSyncCallbackProvider =
    Provider<SessionStreamingSyncCallback>((ref) {
  return (activeCount, titles) {
    unawaited(
      ref
          .read(backgroundKeepaliveServiceProvider)
          .syncOngoingNotification(activeCount, titles),
    );
  };
});

/// 窗口焦点状态（桌面端 WindowListener 驱动，非桌面恒 true）。
final windowFocusedProvider = StateProvider<bool>((ref) => true);

/// 测试环境标记：为避免 30s 周期 Timer 在非单测场景中残留导致
/// `verifyInvariants(!timersPending)` 失败，Observer 的周期轮询仅在
/// [enableSessionAutoRefresh] 为 true 时生效（测试可显式置 false）。
bool enableSessionAutoRefresh = true;

/// 监听窗口焦点并同步 [windowFocusedProvider]。
class WindowFocusObserver extends ConsumerStatefulWidget {
  const WindowFocusObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowFocusObserver> createState() =>
      _WindowFocusObserverState();
}

class _WindowFocusObserverState extends ConsumerState<WindowFocusObserver>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    if (isDesktopPlatform()) {
      windowManager.addListener(this);
      ref.read(windowFocusedProvider.notifier).state =
          true; // 启动时保守置 true，后续由事件驱动。
    }
  }

  @override
  void dispose() {
    if (isDesktopPlatform()) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowFocus() {
    if (!mounted) return;
    ref.read(windowFocusedProvider.notifier).state = true;
  }

  @override
  void onWindowBlur() {
    if (!mounted) return;
    ref.read(windowFocusedProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 会话列表自动刷新 Observer：挂载到 SessionListPage，驱动 30s 轮询 +
/// 获焦/前台 1s debounce + 失焦即停 + 10s 去重/并发互斥（在 Controller 层）。
///
/// 双条件约束：仅当 `resumed && windowFocused && mounted` 时运行定时器；任一
/// 为 false 立即 cancel。
class SessionAutoRefreshObserver extends ConsumerStatefulWidget {
  const SessionAutoRefreshObserver({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<SessionAutoRefreshObserver> createState() =>
      _SessionAutoRefreshObserverState();
}

class _SessionAutoRefreshObserverState
    extends ConsumerState<SessionAutoRefreshObserver> {
  Timer? _focusDebounce;
  Timer? _periodic;
  bool _didInit = false;
  Set<String>? _lastStreamingSessionIds;
  SessionEventsSseClient? _eventsClient;

  @visibleForTesting
  SessionEventsSseClient? get eventsClientForTesting => _eventsClient;

  bool get _shouldStreamEvents {
    if (!enableSessionAutoRefresh) return false;
    final enabled = ref.read(sessionEventsStreamEnabledProvider);
    return _shouldPoll && enabled;
  }

  void _initEventsClient() {
    _eventsClient?.stop();
    _eventsClient?.dispose();
    _eventsClient = null;

    ApiClient? client;
    try {
      client = ref.read(apiClientProvider);
    } catch (_) {
      client = null;
    }
    if (client == null) return;

    _eventsClient = SessionEventsSseClient(
      dio: client.dio,
      baseUrl: client.baseUrl,
      onSessionsChanged: ({version, reason, profile, sessionId}) {
        if (!mounted) return;
        ref.read(sessionListControllerProvider.notifier).onSessionsChangedEvent(
          version: version,
          reason: reason,
          profile: profile,
          sessionId: sessionId,
        );
      },
    );
  }

  void _syncEventsClient() {
    if (!mounted) return;
    if (_eventsClient == null) {
      _initEventsClient();
    }
    if (_shouldStreamEvents) {
      _eventsClient?.start();
    } else {
      _eventsClient?.stop();
    }
  }

  void _syncStreamingSessions(List<SessionSummary>? sessions) {
    if (sessions == null) return;
    final streaming = sessions
        .where((s) =>
            s.isStreaming == true ||
            (s.activeStreamId != null && s.activeStreamId!.trim().isNotEmpty))
        .toList();
    final ids = streaming
        .map((s) => s.sessionId ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (_lastStreamingSessionIds != null &&
        setEquals(_lastStreamingSessionIds, ids)) {
      return;
    }
    _lastStreamingSessionIds = ids;
    final titles = streaming
        .map((s) => s.title ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList();

    ref.read(sessionStreamingSyncCallbackProvider)(ids.length, titles);
  }

  bool get _shouldPoll {
    if (!mounted) return false;
    final lifecycle = ref.read(appLifecycleStateProvider);
    final focused = ref.read(windowFocusedProvider);
    return lifecycle == AppLifecycleState.resumed && focused;
  }

  Duration get _pollPeriod {
    final failures = ref
            .read(sessionListControllerProvider)
            .valueOrNull
            ?.consecutiveFailures ??
        0;
    return SessionListController.nextAutoRefreshDelay(failures);
  }

  void _startPeriodic() {
    if (!enableSessionAutoRefresh) return;
    _periodic?.cancel();
    final period = _pollPeriod;
    _periodic = Timer.periodic(period, (_) {
      if (!mounted || !_shouldPoll) {
        _periodic?.cancel();
        _periodic = null;
        return;
      }
      unawaited(
        ref.read(sessionListControllerProvider.notifier).refreshIfStale(),
      );
    });
  }

  void _stopPeriodic() {
    _periodic?.cancel();
    _periodic = null;
  }

  void _maybeSchedulePoll() {
    if (!mounted || !enableSessionAutoRefresh) return;
    if (_shouldPoll) {
      _startPeriodic();
    } else {
      _stopPeriodic();
    }
  }

  void _onFocusGained() {
    if (!mounted) return;
    _syncEventsClient();
    _focusDebounce?.cancel();
    _focusDebounce = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      _maybeSchedulePoll();
      unawaited(
        ref.read(sessionListControllerProvider.notifier).refreshIfStale(),
      );
    });
  }

  void _onFocusLost() {
    _focusDebounce?.cancel();
    _stopPeriodic();
    _eventsClient?.stop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _didInit = true;
      _syncStreamingSessions(
        ref.read(sessionListControllerProvider).valueOrNull?.sessions,
      );
      _initEventsClient();
      _syncEventsClient();
      _maybeSchedulePoll();
    });
  }

  @override
  void dispose() {
    _focusDebounce?.cancel();
    _stopPeriodic();
    _eventsClient?.stop();
    _eventsClient?.dispose();
    _eventsClient = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppLifecycleState>(appLifecycleStateProvider, (prev, next) {
      if (!mounted || !_didInit) return;
      if (next == AppLifecycleState.resumed) {
        _onFocusGained();
      } else {
        _onFocusLost();
      }
      _syncEventsClient();
    });
    ref.listen<bool>(windowFocusedProvider, (prev, next) {
      if (!mounted || !_didInit) return;
      if (next) {
        _onFocusGained();
      } else {
        _onFocusLost();
      }
      _syncEventsClient();
    });
    ref.listen<bool>(sessionEventsStreamEnabledProvider, (prev, next) {
      if (!mounted || !_didInit) return;
      _syncEventsClient();
    });
    // 监听会话列表变化：同步活跃流集合到保活常驻通知 + 失败次数退避重建 + 事件客户端重连
    ref.listen(sessionListControllerProvider, (prev, next) {
      if (!mounted) return;
      _syncStreamingSessions(next.valueOrNull?.sessions);

      if (!_didInit) return;
      if (_eventsClient == null) {
        _initEventsClient();
        _syncEventsClient();
      }
      final pf = prev?.valueOrNull?.consecutiveFailures ?? 0;
      final nf = next.valueOrNull?.consecutiveFailures ?? 0;
      if (pf != nf && _shouldPoll && _periodic != null) {
        _startPeriodic();
      }
    });
    return widget.child;
  }
}
