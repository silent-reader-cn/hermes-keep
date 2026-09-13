import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemEntity, Platform, Process;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_action_menu.dart';
import '../../core/api/api_client_sessions.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/utils/accessibility.dart';
import '../../core/utils/safe_clipboard.dart';
import '../../l10n/app_localizations.dart';
import '../notifications/notification_providers.dart';
import '../shared/app_back_button.dart';
import '../shared/app_navigation.dart';
import 'chat_controller.dart';
import 'chat_providers.dart';
import 'chat_state.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/chat_outline_sheet.dart';

/// 聊天页（chat_spec.md §6：消息气泡列表 + 流式渲染 + 工具卡片 + 输入栏）。
///
/// `/chat/:sessionId`，sessionId 为空串表示新会话。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.sessionId,
    this.searchQuery,
    this.matchType,
  });

  /// 会话 id；空串 = 新会话。
  final String sessionId;

  /// 搜索结果关键词（深链定位用；非空且匹配 content 时定位高亮）。
  final String? searchQuery;

  /// 搜索命中类型：'title'（不定位，仅打开）或 'content'（定位到消息）。
  final String? matchType;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  final GlobalKey _actionsKey = GlobalKey();

  /// 标题栏 middle Widget 锚点 GlobalKey（供大纲面板定位用）。
  final GlobalKey _titleAnchorKey = GlobalKey();

  /// ChatMessageList 的 GlobalKey，用于调用 outlineJumpTo。
  final GlobalKey<ChatMessageListState> _listKey =
      GlobalKey<ChatMessageListState>();

  /// 当前展开的大纲 OverlayEntry（null = 关闭）。
  OverlayEntry? _outlineEntry;

  /// 当前视口首条可见用户轮次 renderId（大纲高亮用）。
  String? _outlineSelectedRenderId;

  String? _yoloLoadedFor;
  Timer? _syncDebounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureYoloLoaded();
      _triggerSyncDebounced();
    });
  }

  @override
  void dispose() {
    _syncDebounceTimer?.cancel();
    _dismissOutline();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerSyncDebounced();
    }
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _syncDebounceTimer?.cancel();
      _syncDebounceTimer = null;
      _dismissOutline();
      _outlineSelectedRenderId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureYoloLoaded();
        _triggerSyncDebounced();
      });
    }
  }

  void _triggerSyncDebounced() {
    if (widget.sessionId.isEmpty) return;
    if (_syncDebounceTimer != null && _syncDebounceTimer!.isActive) {
      return;
    }
    _syncDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _syncDebounceTimer = null;
    });
    unawaited(
      ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .syncMissingMessages(),
    );
  }

  void _ensureYoloLoaded() {
    if (_yoloLoadedFor == widget.sessionId) return;
    _yoloLoadedFor = widget.sessionId;
    unawaited(
      ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .loadYoloState(),
    );
  }

  /// 收起大纲面板。
  void _dismissOutline() {
    if (_outlineEntry != null && _outlineEntry!.mounted) {
      _outlineEntry!.remove();
    }
    _outlineEntry = null;
  }

  /// 展开/收起大纲面板（toggle）。
  ///
  /// <2 轮用户消息时静默无动作（规格 §7：不置灰，不弹空态）。
  void _toggleOutline() {
    // 已展开则收起
    if (_outlineEntry != null) {
      _dismissOutline();
      if (mounted) setState(() {});
      return;
    }

    // <2 轮用户消息：静默无动作
    final entries = ref.read(chatOutlineEntriesProvider(widget.sessionId));
    if (entries.length < 2) return;

    // 计算锚点矩形（标题 middle widget 在 overlay 坐标系中的位置）
    final overlay = Overlay.of(context);
    final anchorRect = _resolveAnchorRect(_titleAnchorKey, overlay);
    if (anchorRect == null) return;

    _outlineEntry = ChatOutlineSheet.insert(
      overlay: overlay,
      ref: ref,
      anchorRect: anchorRect,
      sessionId: widget.sessionId,
      selectedRenderId: _outlineSelectedRenderId,
      onJump: (renderId, loadedIndex) {
        _listKey.currentState?.outlineJumpTo(renderId, loadedIndex);
      },
      onDismiss: () {
        _dismissOutline();
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() {});
  }

  /// 换算 widget 在 overlay 坐标系中的全局矩形（复用 context_window_popover 的方式）。
  Rect? _resolveAnchorRect(GlobalKey key, OverlayState overlay) {
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      box.size.width,
      box.size.height,
    );
  }

  /// Windows：在资源管理器中打开会话项目文件夹。
  ///
  /// 内置 sidecar 的 agent 与本机同文件系统，workspace 即本地绝对路径；
  /// 目录不存在（远端路径/已删除）时以 notice 提示，绝不静默失败。
  Future<void> _openProjectFolder(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    await openSessionProjectFolder(context, ref, widget.sessionId, path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 监听生命周期状态（Riverpod provider 驱动）
    ref.listen<AppLifecycleState>(appLifecycleStateProvider, (previous, next) {
      if (next == AppLifecycleState.resumed) {
        _triggerSyncDebounced();
      }
    });
    // P4：新会话首条消息后 URL 从 /chat("") → /chat/<newId> 替换，避免刷新丢会话。
    // 监听与 widget.sessionId 绑定的 controller 的 sessionId 变化；widget 本身
    // 的 sessionId 为空串时代表新会话页，待真实 id 回来后立即 go 替换，左侧
    // SessionList 在 ChatController._onNewSessionCreated 中已触发强制刷新，
    // 桌面双栏下右侧切到新路由后左侧列表保持不丢选中态并高亮新项。
    ref.listen<ChatState>(chatControllerProvider(widget.sessionId), (
      previous,
      next,
    ) {
      final prevId = previous?.sessionId ?? widget.sessionId;
      final nextId = next.sessionId;
      if (widget.sessionId.isEmpty && prevId.isEmpty && nextId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!context.mounted) return;
          context.go('/chat/$nextId');
        });
      }
    });
    final state = ref.watch(chatControllerProvider(widget.sessionId));
    final queued = ref.watch(queuedCountProvider(widget.sessionId));
    // Windows 桌面「打开项目文件夹」按钮可见性：仅 Windows + 会话带 workspace。
    final showProjectFolder =
        !kIsWeb && Platform.isWindows && (state.workspace?.isNotEmpty ?? false);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final content = CupertinoPageScaffold(
      backgroundColor: isLight ? LightSurfaces.page : null,
      navigationBar: CupertinoNavigationBar(
        leading: const AppBackButton(),
        middle: GestureDetector(
          key: const ValueKey('chat-title-outline-trigger'),
          onTap: _toggleOutline,
          behavior: HitTestBehavior.opaque,
          child: Container(
            key: _titleAnchorKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.displayTitle, overflow: TextOverflow.ellipsis),
                if (state.parentSessionId != null)
                  CupertinoButton(
                    key: const ValueKey('chat-branch-badge'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 18),
                    onPressed: () => _showParentSessionDialog(
                      context,
                      state.parentSessionId!,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.arrow_2_squarepath,
                          size: 12,
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: secondaryText,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          l10n.branchBadge,
                          style: TextStyle(
                            fontSize: 12,
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.textSecondary,
                              dark: secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Windows 桌面：三点菜单左侧「在资源管理器中打开项目文件夹」。
            // 会话带 workspace（项目文件夹绝对路径）时才显示。
            if (showProjectFolder) ...[
              AccessibleButton(
                key: const ValueKey('chat-open-project-folder'),
                label: l10n.openProjectFolder,
                padding: EdgeInsets.zero,
                onPressed: () => unawaited(
                  _openProjectFolder(context, ref, state.workspace!),
                ),
                child: const Icon(CupertinoIcons.folder),
              ),
              const SizedBox(width: 14),
            ],
            KeyedSubtree(
              key: _actionsKey,
              child: AccessibleButton(
                key: const ValueKey('chat-session-actions'),
                label: l10n.sessionActions,
                padding: EdgeInsets.zero,
                onPressed: () => _showSessionActions(
                  context,
                  ref,
                  widget.sessionId,
                  state,
                  _actionsKey,
                ),
                child: const Icon(CupertinoIcons.ellipsis),
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (state.pendingAction.hasPendingPrompt)
              _PendingPromptCard(sessionId: widget.sessionId),
            if (state.isShowingOfflineCache)
              _OfflineCacheBanner(
                onReload: () => ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .loadMessages(),
                onDismiss: () => ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .dismissOfflineCache(),
              ),
            Expanded(
              child: ChatMessageList(
                key: _listKey,
                sessionId: widget.sessionId,
                highlightQuery: widget.matchType == 'content'
                    ? widget.searchQuery
                    : null,
              ),
            ),
            if (state.sendErrorMessage != null)
              _ErrorBanner(
                message: state.sendErrorMessage!,
                onDismiss: () => ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .dismissError(),
              ),
            if (queued > 0) _QueuedBanner(count: queued),
            if (state.noticeMessage != null)
              _TransientNoticeToast(
                key: ValueKey('chat-notice-toast-${state.noticeMessage}'),
                message: state.noticeMessage!,
                onDismiss: () => ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .dismissNotice(),
              ),
            for (var i = 0; i < state.steerHints.length; i++)
              _SteerNoticeToast(
                key: ValueKey('chat-steer-notice-$i'),
                index: i,
                message: state.steerHints[i],
                onClose: () => ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .clearSteerHint(index: i),
                onLongPress: () {
                  ref
                      .read(chatControllerProvider(widget.sessionId).notifier)
                      .setNotice(
                        AppLocalizations.of(context).copiedToClipboardNotice,
                      );
                },
              ),
            ChatInputBar(
              sessionId: widget.sessionId,
              enabled: !state.isReadOnly,
            ),
          ],
        ),
      ),
    );
    return isLight
        ? CupertinoTheme(
            data: CupertinoTheme.of(context).copyWith(
              scaffoldBackgroundColor: LightSurfaces.page,
              barBackgroundColor: LightSurfaces.page,
              primaryColor: LightSurfaces.userDetail,
            ),
            child: content,
          )
        : content;
  }
}

/// 分支标识点击：展示父会话信息与跳转入口。
Future<void> _showParentSessionDialog(
  BuildContext context,
  String parentSessionId,
) async {
  final l10n = AppLocalizations.of(context);
  await showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      key: const ValueKey('chat-branch-dialog'),
      title: Text(l10n.branchSession),
      content: Text(l10n.branchSessionDescription(parentSessionId)),
      actions: [
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          key: const ValueKey('chat-branch-dialog-close'),
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.close),
        ),
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          key: const ValueKey('chat-goto-parent'),
          onPressed: () {
            Navigator.pop(dialogContext);
            context.go('/chat/$parentSessionId');
          },
          child: Text(l10n.jumpToParentSession),
        ),
      ],
    ),
  );
}

/// Windows：在资源管理器中打开会话项目文件夹（头部按钮与三点菜单共用）。
///
/// 内置 sidecar 的 agent 与本机同文件系统，workspace 即本地绝对路径；
/// 目录不存在（远端路径/已删除）时以 notice 提示，绝不静默失败。
Future<void> openSessionProjectFolder(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  String path,
) async {
  final l10n = AppLocalizations.of(context);
  final notifier = ref.read(chatControllerProvider(sessionId).notifier);
  try {
    if (!await FileSystemEntity.isDirectory(path)) {
      notifier.setNotice(l10n.projectFolderMissing(path));
      return;
    }
    await Process.run('explorer', [path]);
  } catch (e) {
    notifier.setNotice(l10n.openProjectFolderFailed(e.toString()));
  }
}

Future<void> _showSessionActions(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  ChatState state,
  GlobalKey actionsKey,
) async {
  if (sessionId.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final isReadOnly = state.isReadOnly;
  final controller = ref.read(chatControllerProvider(sessionId).notifier);
  final items = [
    if (!isReadOnly) ...[
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-rename'),
        label: l10n.rename,
        onPressed: () =>
            unawaited(_renameSession(context, controller, state.displayTitle)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-pin'),
        label: l10n.pin,
        onPressed: () => unawaited(controller.setPinned(true)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-archive'),
        label: l10n.archive,
        onPressed: () async {
          if (await controller.setArchived(true)) {
            if (context.mounted) leaveToRoot(context);
          }
        },
      ),
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-compress'),
        label: l10n.compressSession,
        onPressed: () => unawaited(_compressSession(context, controller)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-undo'),
        label: l10n.undoLastTurn,
        onPressed: () async {
          final confirmed = await _confirmSessionUndo(context);
          if (confirmed) await controller.undoLastTurn();
        },
      ),
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-retry'),
        label: l10n.retryLastTurn,
        onPressed: () => unawaited(controller.retryLastTurn()),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-yolo'),
        label: state.yoloEnabled ? l10n.disableYolo : l10n.enableYolo,
        onPressed: () => unawaited(controller.toggleYolo(!state.yoloEnabled)),
      ),
    ],
    AdaptiveMenuItem(
      key: const ValueKey('chat-action-workspace'),
      label: l10n.workspaceFilesTitle,
      onPressed: () => unawaited(context.push('/workspace/$sessionId')),
    ),
    // Windows 桌面：三点菜单同样提供「打开项目文件夹」。
    if (!kIsWeb && Platform.isWindows && (state.workspace?.isNotEmpty ?? false))
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-open-project-folder'),
        label: l10n.openProjectFolder,
        onPressed: () => unawaited(
          openSessionProjectFolder(context, ref, sessionId, state.workspace!),
        ),
      ),
    AdaptiveMenuItem(
      key: const ValueKey('chat-action-git'),
      label: l10n.gitWorkspaceTitle,
      onPressed: () => unawaited(context.push('/git/$sessionId')),
    ),
    AdaptiveMenuItem(
      key: const ValueKey('chat-action-branch'),
      label: l10n.createBranch,
      onPressed: () async {
        final newId = await controller.branchSession();
        if (newId != null && context.mounted) {
          context.go('/chat/$newId');
        }
      },
    ),
    AdaptiveMenuItem(
      key: const ValueKey('chat-action-export'),
      label: l10n.export,
      onPressed: () => unawaited(_exportSession(context, ref, sessionId)),
    ),
    if (!isReadOnly)
      AdaptiveMenuItem(
        key: const ValueKey('chat-action-delete'),
        isDestructive: true,
        label: l10n.delete,
        onPressed: () async {
          final confirmed = await _confirmSessionDelete(
            context,
            state.displayTitle,
          );
          if (confirmed) {
            if (await controller.deleteSession()) {
              if (context.mounted) leaveToRoot(context);
            }
          }
        },
      ),
  ];

  await AdaptiveActionMenu.show(
    context,
    anchorKey: actionsKey,
    items: items,
    cancelLabel: l10n.cancel,
    cancelKey: const ValueKey('chat-action-cancel'),
  );
}

Future<void> _renameSession(
  BuildContext context,
  ChatController controller,
  String current,
) async {
  final l10n = AppLocalizations.of(context);
  final input = TextEditingController(text: current);
  final title = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(l10n.renameSession),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          decoration: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? BoxDecoration(
                  color: LightSurfaces.card,
                  border: Border.all(
                    color: LightSurfaces.cardBorder,
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(5),
                )
              : const CupertinoTextField().decoration,
          placeholderStyle:
              CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(
                  fontWeight: FontWeight.w400,
                  color: LightSurfaces.placeholder,
                )
              : const CupertinoTextField().placeholderStyle,
          controller: input,
          autofocus: true,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          key: const ValueKey('chat-rename-cancel'),
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          key: const ValueKey('chat-rename-save'),
          onPressed: () => Navigator.pop(dialogContext, input.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  input.dispose();
  if (title != null) await controller.renameSession(title);
}

Future<bool> _confirmSessionDelete(BuildContext context, String title) async {
  final l10n = AppLocalizations.of(context);
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(l10n.deleteSession),
      content: Text(l10n.confirmDeleteSession(title)),
      actions: [
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          key: const ValueKey('chat-delete-cancel'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancel),
        ),
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? TextStyle(color: statusRedText.resolveFrom(context))
              : null,
          key: const ValueKey('chat-delete-confirm'),
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return result == true;
}

/// 压缩会话：可选输入聚焦主题（留空 = 全量压缩）；成功后由控制器轻提示。
Future<void> _compressSession(
  BuildContext context,
  ChatController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final input = TextEditingController();
  final focusTopic = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(l10n.compressSession),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          key: const ValueKey('chat-compress-topic'),
          decoration: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? BoxDecoration(
                  color: LightSurfaces.card,
                  border: Border.all(
                    color: LightSurfaces.cardBorder,
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(5),
                )
              : const CupertinoTextField().decoration,
          placeholderStyle:
              CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(
                  fontWeight: FontWeight.w400,
                  color: LightSurfaces.placeholder,
                )
              : const CupertinoTextField().placeholderStyle,
          controller: input,
          placeholder: l10n.focusTopicPlaceholder,
          autofocus: true,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          key: const ValueKey('chat-compress-cancel'),
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          key: const ValueKey('chat-compress-confirm'),
          onPressed: () => Navigator.pop(dialogContext, input.text),
          child: Text(l10n.compress),
        ),
      ],
    ),
  );
  input.dispose();
  if (focusTopic != null) {
    await controller.compressSession(focusTopic: focusTopic);
  }
}

/// 撤销上一轮确认（删除最后一轮对话，不可撤销）。
Future<bool> _confirmSessionUndo(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(l10n.undoLastTurn),
      content: Text(l10n.confirmUndoLastTurnPrompt),
      actions: [
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          key: const ValueKey('chat-undo-cancel'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancel),
        ),
        CupertinoDialogAction(
          textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? TextStyle(color: statusRedText.resolveFrom(context))
              : null,
          key: const ValueKey('chat-undo-confirm'),
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return result == true;
}

Future<void> _exportSession(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final response = await ref
        .read(apiClientProvider)
        .exportSession(sessionId: sessionId, format: 'md');
    final content = utf8.decode(response.data, allowMalformed: true);
    // 同源修复：长会话 markdown 无界，剪贴板事务超限会崩（TransactionTooLarge
    // Exception）——走 SafeClipboard，超限/异常自动落盘文件并提示路径。
    final result = await SafeClipboard.copyOrSave(
      content,
      fileNamePrefix: 'hermes_session_export',
    );
    if (context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(l10n.exportSuccessDialogTitle),
          content: Text(
            result.isFileSaved
                ? l10n.diagnosticsExportTooLargeSaved(result.filePath!)
                : l10n.markdownCopiedToClipboard,
          ),
          actions: [
            CupertinoDialogAction(
              textStyle:
                  CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? const TextStyle(color: LightSurfaces.userDetail)
                  : null,
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  } on ApiException catch (error) {
    if (context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(l10n.exportFailed),
          content: Text(error.message),
          actions: [
            CupertinoDialogAction(
              textStyle:
                  CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? const TextStyle(color: LightSurfaces.userDetail)
                  : null,
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  }
}

/// 审批/澄清卡片（chat_spec.md §2.3：approval/clarify 是主流报警事件，流不中断）。
class _PendingPromptCard extends ConsumerStatefulWidget {
  const _PendingPromptCard({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_PendingPromptCard> createState() => _PendingPromptCardState();

  static String? _stringOf(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static List<String> _stringListOf(
    Map<String, Object?> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) {
        final items = value.whereType<String>().toList();
        if (items.isNotEmpty) return items;
      }
    }
    return const [];
  }
}

class _PendingPromptCardState extends ConsumerState<_PendingPromptCard> {
  final TextEditingController _textController = TextEditingController();
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _isCollapsed = false;
  bool _submitting = false;
  Map<String, Object?>? _lastClarifyPrompt;

  @override
  void initState() {
    super.initState();
    _checkAndStartCountdown();
  }

  @override
  void didUpdateWidget(covariant _PendingPromptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAndStartCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _checkAndStartCountdown() {
    final state = ref.read(chatControllerProvider(widget.sessionId));
    final pending = state.pendingAction;
    if (pending.approvalPrompt != null) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }
    final clarifyPrompt = pending.clarificationPrompt;
    if (clarifyPrompt == null) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }
    if (_lastClarifyPrompt == clarifyPrompt && _countdownTimer != null) {
      return;
    }
    _lastClarifyPrompt = clarifyPrompt;
    _initCountdown(clarifyPrompt);
  }

  void _initCountdown(Map<String, Object?> prompt) {
    _countdownTimer?.cancel();
    final expiresAt =
        (prompt['expires_at'] as num?)?.toDouble() ??
        (prompt['expiresAt'] as num?)?.toDouble();
    final requestedAt =
        (prompt['requested_at'] as num?)?.toDouble() ??
        (prompt['requestedAt'] as num?)?.toDouble();
    final timeoutSec =
        (prompt['timeout_seconds'] as num?)?.toInt() ??
        (prompt['timeoutSeconds'] as num?)?.toInt() ??
        120;

    final double targetEpochSec;
    if (expiresAt != null && expiresAt > 0) {
      targetEpochSec = expiresAt;
    } else if (requestedAt != null && requestedAt > 0) {
      targetEpochSec = requestedAt + timeoutSec;
    } else {
      targetEpochSec =
          (DateTime.now().millisecondsSinceEpoch / 1000) + timeoutSec;
    }

    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000;
    _remainingSeconds = (targetEpochSec - nowSec).ceil();
    if (_remainingSeconds <= 0) {
      _remainingSeconds = 0;
      scheduleMicrotask(_handleTimeout);
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      final rem = (targetEpochSec - now).ceil();
      if (rem <= 0) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        _handleTimeout();
      } else {
        setState(() => _remainingSeconds = rem);
      }
    });
  }

  void _handleTimeout() {
    _countdownTimer?.cancel();
    final controller = ref.read(
      chatControllerProvider(widget.sessionId).notifier,
    );
    controller.handleClarificationTimeout();
  }

  Future<void> _submitText([String? val]) async {
    final text = (val ?? _textController.text).trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final controller = ref.read(
      chatControllerProvider(widget.sessionId).notifier,
    );
    final ok = await controller.respondToClarification(text);
    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        _textController.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(chatControllerProvider(widget.sessionId));
    final pending = state.pendingAction;
    final isApproval = pending.approvalPrompt != null;
    final prompt = isApproval
        ? pending.approvalPrompt!
        : pending.clarificationPrompt!;
    final question = _PendingPromptCard._stringOf(prompt, const [
      'question',
      'prompt',
      'text',
    ]);
    final choices = _PendingPromptCard._stringListOf(prompt, const [
      'choices_offered',
      'choicesOffered',
      'choices',
    ]);
    final controller = ref.read(
      chatControllerProvider(widget.sessionId).notifier,
    );

    if (isApproval) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.tintWarning,
            dark: CupertinoColors.systemOrange.withValues(alpha: 0.12),
          ),
          borderRadius: BorderRadius.circular(10),
          border: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.approvalNeeded,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: LightSurfaces.resolve(
                  context,
                  statusOrangeText.resolveFrom(context),
                  dark: CupertinoColors.systemOrange,
                ),
              ),
            ),
            if (question != null && question.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                question,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final choice in choices)
                    _buildChoiceButton(
                      choice: choice,
                      onPressed: () => controller.respondToApproval(choice),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    // Clarification 分支
    final mm = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_remainingSeconds % 60).toString().padLeft(2, '0');
    final countdownStr = '$mm:$ss';
    final isUrgent = _remainingSeconds < 10;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintClarification,
          dark: CupertinoColors.systemIndigo.withValues(alpha: 0.12),
        ),
        borderRadius: BorderRadius.circular(10),
        border: CupertinoTheme.brightnessOf(context) == Brightness.light
            ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.question_circle_fill,
                size: 16,
                color: CupertinoColors.systemIndigo,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.clarificationNeeded,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemIndigo,
                ),
              ),
              const Spacer(),
              if (_remainingSeconds > 0)
                Text(
                  key: const ValueKey('chat-prompt-clarify-countdown'),
                  countdownStr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isUrgent
                        ? statusOrangeText.resolveFrom(context)
                        : LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: CupertinoColors.secondaryLabel,
                          ),
                  ),
                ),
              const SizedBox(width: 6),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(24, 24),
                onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
                child: Icon(
                  _isCollapsed
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_up,
                  size: 16,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                ),
              ),
            ],
          ),
          if (!_isCollapsed) ...[
            if (question != null && question.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                question,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final choice in choices)
                    _buildChoiceButton(
                      choice: choice,
                      onPressed: () =>
                          controller.respondToClarification(choice),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: CupertinoTextField(
                      key: const ValueKey('chat-prompt-clarify-input'),
                      decoration:
                          CupertinoTheme.brightnessOf(context) ==
                              Brightness.light
                          ? BoxDecoration(
                              color: LightSurfaces.card,
                              border: Border.all(
                                color: LightSurfaces.cardBorder,
                                width: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            )
                          : const CupertinoTextField().decoration,

                      controller: _textController,
                      placeholder: l10n.clarifyInputPlaceholder,
                      style: const TextStyle(fontSize: 13),
                      placeholderStyle: TextStyle(
                        fontSize: 13,
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.placeholder,
                          dark: CupertinoColors.placeholderText,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      onSubmitted: _submitText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: CupertinoButton.filled(
                    key: const ValueKey('chat-prompt-clarify-submit'),
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    borderRadius: BorderRadius.circular(8),
                    onPressed: _submitting ? null : _submitText,
                    child: Text(
                      l10n.clarifySend,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.clarifyHint,
              style: TextStyle(
                fontSize: 12,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChoiceButton({
    required String choice,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 36,
      child: CupertinoButton.filled(
        key: ValueKey('chat-prompt-choice-$choice'),
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        borderRadius: BorderRadius.circular(8),
        onPressed: onPressed,
        child: Text(
          choice,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// 离线缓存提示横幅（isShowingOfflineCache 模式，中性/蓝色系，可点重试与关闭）。
class _OfflineCacheBanner extends StatelessWidget {
  const _OfflineCacheBanner({required this.onReload, required this.onDismiss});

  final VoidCallback onReload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('chat-offline-cache-banner'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.selection,
          dark: CupertinoColors.systemBlue.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.systemBlue.withValues(alpha: 0.2),
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.archivebox,
            size: 14,
            color: LightSurfaces.resolve(
              context,
              statusBlueText.resolveFrom(context),
              dark: CupertinoColors.systemBlue.color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.offlineCacheBanner,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: LightSurfaces.resolve(
                  context,
                  statusBlueText.resolveFrom(context),
                  dark: CupertinoColors.systemBlue.color,
                ),
              ),
            ),
          ),
          CupertinoButton(
            key: const ValueKey('chat-offline-cache-reload'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: const Size(0, 0),
            onPressed: onReload,
            child: Text(
              l10n.retry,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: LightSurfaces.resolve(
                  context,
                  statusBlueText.resolveFrom(context),
                  dark: CupertinoColors.systemBlue.color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          AccessibleButton(
            key: const ValueKey('chat-offline-cache-dismiss'),
            label: l10n.dismissOfflineBanner,
            minimumSize: const Size(0, 0),
            onPressed: onDismiss,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 14,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: const Color(0xFF8E8E93),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 发送错误横幅（error/apperror 事件、send/stop 失败）。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintError,
          dark: CupertinoColors.systemRed.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.systemRed.withValues(alpha: 0.2),
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 14,
            color: CupertinoColors.systemRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: statusRedText.resolveFrom(context),
              ),
            ),
          ),
          AccessibleButton(
            label: l10n.dismissError,
            minimumSize: const Size(0, 0),
            onPressed: onDismiss,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 14,
              color: CupertinoColors.systemRed,
            ),
          ),
        ],
      ),
    );
  }
}

/// 排队待发送横幅（queue 行为 / steer 失败入队）。
class _QueuedBanner extends StatelessWidget {
  const _QueuedBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintWarning,
          dark: CupertinoColors.systemYellow.withValues(alpha: 0.15),
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.systemYellow.withValues(alpha: 0.25),
          ),
          width: 0.5,
        ),
      ),
      child: Text(
        l10n.queuedBannerMessage(count),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: LightSurfaces.resolve(
            context,
            statusOrangeText.resolveFrom(context),
            dark: CupertinoColors.systemBrown,
          ),
        ),
      ),
    );
  }
}

/// 成功类会话操作轻提示横幅（可点 × 关闭）。
///
/// 已保留作兼容，当前挂载点已改为 [_TransientNoticeToast]。
// ignore: unused_element
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintGreen,
          dark: CupertinoColors.systemGreen.withValues(alpha: 0.12),
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.systemGreen.withValues(alpha: 0.2),
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.checkmark_circle,
            size: 14,
            color: LightSurfaces.resolve(
              context,
              statusGreenText.resolveFrom(context),
              dark: CupertinoColors.systemGreen.color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: statusGreenText.resolveFrom(context),
              ),
            ),
          ),
          AccessibleButton(
            label: l10n.dismissNotice,
            minimumSize: const Size(0, 0),
            onPressed: onDismiss,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 14,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: const Color(0xFF8E8E93),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 轻量自动消失通知 toast（selected-context-spec §5.2，复制提示分型）。
///
/// - 2800ms 后自动 [onDismiss]（`Timer` 在 `State` 内持有，`dispose` 取消）。
/// - 200ms `AnimatedOpacity` 淡入淡出；新 `message` 到达时旧定时被取消（`Key` 以 message 区分，同一时刻仅一条）。
/// - 距输入栏 8px（`margin bottom 8`），不遮输入框；轻量视觉：白/绿8%轻底 + label 500 + 14px 绿勾、圆角 10 + 细阴影。
/// - 暗色 #2C2C2E/白92%字；与 [_ErrorBanner] 分型：错误横幅（`statusRedText`）仍常驻，仅 toast 自动消失。
class _TransientNoticeToast extends StatefulWidget {
  const _TransientNoticeToast({
    required super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  State<_TransientNoticeToast> createState() => _TransientNoticeToastState();
}

class _TransientNoticeToastState extends State<_TransientNoticeToast> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _visible = true;
    _arm();
  }

  @override
  void didUpdateWidget(covariant _TransientNoticeToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _timer?.cancel();
      _visible = true;
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      setState(() => _visible = false);
      // 等淡出完成再真正清除状态，避免被下一条 toast 的 Key 复用误清。
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        widget.onDismiss();
      });
    });
  }

  void _dismissNow() {
    _timer?.cancel();
    setState(() => _visible = false);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    // 要求：白/绿8%轻底（浅色 white + systemGreen 8%）、深色 #2C2C2E
    // 文字用 label 主色 500、14px 绿勾、圆角10+细阴影
    // Light tint and hairline are tokens; dark #2C2C2E stays unchanged.
    final bgColor = isDark ? const Color(0xFF2C2C2E) : LightSurfaces.tintGreen;
    final textColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.92)
        : CupertinoColors.label.resolveFrom(context);
    return AnimatedOpacity(
      key: const ValueKey('chat-notice-toast-opacity'),
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: const ValueKey('chat-notice-toast'),
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? CupertinoColors.systemGrey
                      .resolveFrom(context)
                      .withValues(alpha: 0.18)
                : LightSurfaces.cardBorder,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(
                alpha: isDark ? 0.18 : 0.06,
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.checkmark_circle_fill,
              size: 14,
              color: LightSurfaces.resolve(
                context,
                statusGreenText.resolveFrom(context),
                dark: CupertinoColors.systemGreen.color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            AccessibleButton(
              key: const ValueKey('chat-notice-toast-dismiss'),
              label: l10n.dismissNotice,
              minimumSize: const Size(0, 0),
              onPressed: _dismissNow,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 14,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: const Color(0xFF8E8E93),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 常驻 steer 提示（左侧图标用 steer 转向语义，区别于「已复制到剪贴板」的成功勾）。
///
/// 差异：不自动消失；多条 steer 垂直堆叠；支持长按复制；
/// 直到 live 会话结束（finishStream 清 steerHints）或用户手动点 × 关闭。
class _SteerNoticeToast extends StatelessWidget {
  const _SteerNoticeToast({
    super.key,
    required this.message,
    required this.onClose,
    this.onLongPress,
    this.index,
  });

  final String message;
  final VoidCallback onClose;
  final VoidCallback? onLongPress;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : LightSurfaces.tintGreen;
    final textColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.92)
        : CupertinoColors.label.resolveFrom(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? CupertinoColors.systemGrey
                    .resolveFrom(context)
                    .withValues(alpha: 0.18)
              : LightSurfaces.cardBorder,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(
              alpha: isDark ? 0.18 : 0.06,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.arrow_turn_up_right,
            size: 14,
            color: LightSurfaces.resolve(
              context,
              statusGreenText.resolveFrom(context),
              dark: CupertinoColors.systemGreen.color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () {
                unawaited(Clipboard.setData(ClipboardData(text: message)));
                onLongPress?.call();
              },
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ),
          AccessibleButton(
            key: index != null
                ? ValueKey('chat-steer-notice-close-$index')
                : const ValueKey('chat-steer-notice-close'),
            label: l10n.dismissNotice,
            minimumSize: const Size(0, 0),
            onPressed: onClose,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 14,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: const Color(0xFF8E8E93),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
