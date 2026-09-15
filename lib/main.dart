import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/theme/cupertino_theme.dart';
import 'core/api/cookie_store.dart';
import 'core/cache/app_database.dart';
import 'core/cache/cache_providers.dart';
import 'core/connections/connection_store.dart';
import 'features/chat/chat_providers.dart';
import 'features/desktop/desktop_settings.dart';
import 'features/desktop/startup_registrar.dart';
import 'features/diagnostics/diagnostics_models.dart';
import 'features/diagnostics/diagnostics_service.dart';
import 'features/notifications/background_keepalive_service.dart';
import 'features/notifications/notification_providers.dart';
import 'features/session_list/session_auto_refresh.dart';

/// 全局渲染/网络错误可恢复卡片（替代默认大灰屏/红屏，todo.md #8 / active.md §1）。
class RecoverableErrorCard extends StatefulWidget {
  const RecoverableErrorCard({
    super.key,
    this.details,
    this.onRetry,
    this.message,
  });

  final FlutterErrorDetails? details;
  final VoidCallback? onRetry;
  final String? message;

  @override
  State<RecoverableErrorCard> createState() => _RecoverableErrorCardState();
}

class _RecoverableErrorCardState extends State<RecoverableErrorCard> {
  bool _retried = false;
  bool _expanded = false;
  bool _copied = false;
  Timer? _copiedResetTimer;

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  String get _displayText {
    if (widget.message != null && widget.message!.trim().isNotEmpty) {
      return widget.message!;
    }
    final exceptionStr = widget.details?.exceptionAsString();
    if (exceptionStr != null && exceptionStr.trim().isNotEmpty) {
      return exceptionStr;
    }
    return '已断开 / 网络错误，重试';
  }

  bool get _hasDetails => widget.details != null;

  String _buildDetailsText() {
    if (widget.details == null) {
      return widget.message ?? '';
    }
    final d = widget.details!;
    final buffer = StringBuffer();
    final ex = d.exceptionAsString();
    if (ex.isNotEmpty) {
      buffer.writeln(ex);
    }
    if (d.library != null && d.library!.isNotEmpty) {
      buffer.writeln('Library: ${d.library}');
    }
    if (d.context != null) {
      buffer.writeln('Context: ${d.context}');
    }
    if (d.stack != null) {
      buffer.writeln('\nStackTrace:');
      buffer.writeln(d.stack.toString());
    }
    final result = buffer.toString().trim();
    if (result.isEmpty) {
      return d.toString();
    }
    return result;
  }

  Future<void> _copyDetails(String text) async {
    setState(() => _copied = true);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _copiedResetTimer?.cancel();
    _copiedResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final detailBgColor =
        CupertinoColors.tertiarySystemGroupedBackground.resolveFrom(context);
    final primaryTextColor = CupertinoColors.label.resolveFrom(context);
    final secondaryTextColor =
        CupertinoColors.secondaryLabel.resolveFrom(context);
    final redColor = CupertinoColors.systemRed.resolveFrom(context);
    final blueColor = CupertinoColors.activeBlue.resolveFrom(context);
    final greenColor = CupertinoColors.systemGreen.resolveFrom(context);
    final separatorColor = CupertinoColors.separator.resolveFrom(context);

    final displayText = _displayText;
    final detailsText = _hasDetails ? _buildDetailsText() : '';

    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: redColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: redColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayText,
                  style: TextStyle(
                    fontFamily: kAppFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: primaryTextColor,
                    decoration: TextDecoration.none,
                  ),
                  maxLines: _expanded ? 10 : 2,
                  overflow:
                      _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_hasDetails) ...[
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? '收起' : '详情',
                        style: TextStyle(
                          fontFamily: kAppFontFamily,
                          fontSize: 12,
                          color: blueColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _expanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 12,
                        color: blueColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                color: blueColor,
                borderRadius: BorderRadius.circular(8),
                onPressed: () {
                  setState(() => _retried = true);
                  widget.onRetry?.call();
                },
                child: Text(
                  _retried ? '已重试' : '重试',
                  style: const TextStyle(
                    fontFamily: kAppFontFamily,
                    fontSize: 12,
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_expanded && _hasDetails) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: detailBgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: separatorColor.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '异常详情',
                        style: TextStyle(
                          fontFamily: kAppFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: secondaryTextColor,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        onPressed: () => _copyDetails(detailsText),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _copied
                                  ? CupertinoIcons.check_mark
                                  : CupertinoIcons.doc_on_doc,
                              size: 12,
                              color: _copied ? greenColor : blueColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _copied ? '已复制' : '复制详情',
                              style: TextStyle(
                                fontFamily: kAppFontFamily,
                                fontSize: 11,
                                color: _copied ? greenColor : blueColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        detailsText,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                          color: primaryTextColor,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    if (Directionality.maybeOf(context) == null) {
      card = Directionality(textDirection: TextDirection.ltr, child: card);
    }
    return Center(child: card);
  }
}

/// 进程级唯一持久库单例
///
/// 用 `overrideWithValue` 注入 [appDatabaseProvider]，避免
/// `overrideWith((ref) => AppDatabase.production())` 每次 rebuild 都 `new`
/// 一个 `driftDatabase(name: 'hermes_cache')` 导致同名 QueryExecutor 争用
/// （见渲染层崩溃族：GeneratedDatabase 被实例化两次）。
final AppDatabase _productionDatabase = AppDatabase.production();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 注册全局错误处理与可恢复卡片 builder（todo.md #8 渲染层兜底）
  FlutterError.onError = (FlutterErrorDetails details) {
    developer.log(
      'FlutterError caught: ${details.exceptionAsString()}',
      name: 'hermes.error',
      error: details.exception,
      stackTrace: details.stack,
    );
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.error,
      tag: 'flutter_error',
      message: details.exceptionAsString(),
      details: {
        'library': details.library,
        'context': details.context?.toString(),
        if (details.stack != null) 'stackTrace': details.stack.toString(),
      },
      errorKind: details.exception.runtimeType.toString(),
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    developer.log(
      'PlatformDispatcher error caught: $error',
      name: 'hermes.error',
      error: error,
      stackTrace: stack,
    );
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.error,
      tag: 'platform_error',
      message: error.toString(),
      details: {'stackTrace': stack.toString()},
      errorKind: error.runtimeType.toString(),
    );
    return true;
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    developer.log(
      'ErrorWidget.builder caught: ${details.exceptionAsString()}',
      name: 'hermes.error',
      error: details.exception,
      stackTrace: details.stack,
    );
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.error,
      tag: 'error_widget',
      message: details.exceptionAsString(),
      details: {
        'library': details.library,
        'context': details.context?.toString(),
        if (details.stack != null) 'stackTrace': details.stack.toString(),
      },
      errorKind: details.exception.runtimeType.toString(),
    );
    return RecoverableErrorCard(details: details);
  };

  // 注入唯一持久库后初始化诊断服务（drift 落库，避免双库；#33 存储迁移）。
  unawaited(DiagnosticsService.instance.init(database: _productionDatabase));

  final silentStart = isSilentStart(
    args: args,
    executableArguments: Platform.executableArguments,
  );
  if (isDesktopPlatform()) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle('Hermes');
      // 兜底最小窗口：避免拖到 0 宽/过窄时 Windows EGL 上下文丢失
      // （gpu_surface_gl_impeller.cc Context Lost 循环刷屏）。
      await windowManager.setMinimumSize(const Size(720, 480));
      if (silentStart) {
        // 静默启动：不显示主窗口，仅驻留系统托盘；
        // 托盘「显示主窗口」可随时唤出。无参启动路径行为不变。
        unawaited(
          windowManager.waitUntilReadyToShow(null, () async {
            try {
              await windowManager.hide();
            } catch (e, st) {
              developer.log(
                'Failed to hide window on silent start',
                name: 'main',
                error: e,
                stackTrace: st,
              );
            }
          }),
        );
      }
    } catch (e, st) {
      developer.log(
        'windowManager.ensureInitialized failed',
        name: 'main',
        error: e,
        stackTrace: st,
      );
    }
  }

  if (!kIsWeb && Platform.isAndroid) {
    unawaited(BackgroundKeepaliveService.instance.initialize());
  }

  // 启动时恢复持久化的登录 cookie，避免 App 重启后登录态丢失（401）。
  // 未登录/无 cookie 时静默跳过；失败静默（会话列表会走自动重登兜底）。
  CookieStore.shared = CookieStore(
    storage: const FlutterSecureStorageAdapter(),
  );
  await CookieStore.shared.restore();
  runApp(
    ProviderScope(
      overrides: [
        // 回合完成 → 后台通知 hook（chat_controller 的 done/stream_end
        // 收尾处调用；前台不发、后台发，见 notifications feature）。
        chatTurnCompletedCallbackProvider.overrideWith(
          (ref) => ref.watch(turnNotificationHookProvider),
        ),
        // 澄清请求 → 后台通知 hook（chat_controller 的 clarify 事件处调用；
        // 默认 no-op，不 override 则澄清永不通知，见 #26 根因①）。
        chatClarificationNeededCallbackProvider.overrideWith(
          (ref) => ref.watch(clarificationNotificationHookProvider),
        ),
        // 会话异常 → 后台通知 hook（cancel / error / 重连失败处调用）。
        chatSessionErrorCallbackProvider.overrideWith(
          (ref) => ref.watch(sessionErrorNotificationHookProvider),
        ),
        // 会话列表活跃流同步 → 保活常驻通知 hook（#89 保活通知同步）。
        sessionStreamingSyncCallbackProvider.overrideWith(
          (ref) => (activeCount, titles) {
            unawaited(
              ref
                  .read(backgroundKeepaliveServiceProvider)
                  .syncOngoingNotification(activeCount, titles),
            );
          },
        ),
        // 回合实时活动 → 实况通知（灵动岛）hook（#120：事件驱动、退后台即时上岛）。
        chatLiveActivityCallbackProvider.overrideWith(
          (ref) => ref.watch(chatLiveActivityHookProvider),
        ),
        // 启用生产持久缓存数据库：会话列表 / 消息 /（未来）媒体的离线缓存
        // 真正落盘（默认 appDatabaseProvider 为内存库，重启即清空）。
        // 单例注入：全进程唯一实例，避免 drift 同名库双开。
        appDatabaseProvider.overrideWithValue(_productionDatabase),
      ],
      child: const HermesApp(),
    ),
  );
}
