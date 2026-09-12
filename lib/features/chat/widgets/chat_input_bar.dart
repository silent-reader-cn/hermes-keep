import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/adaptive_shell.dart';
import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/cupertino_popover.dart';
import '../../../core/api/api_client_upload.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/models/context_window_snapshot.dart';
import '../../../core/models/upload_response.dart';
import '../../../core/providers/clipboard_paste_provider.dart';
import '../../../core/providers/file_picker_provider.dart';
import '../../../core/utils/accessibility.dart';
import '../../../core/utils/clipboard_paste.dart';
import '../../../core/utils/file_picker.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/chat_draft_provider.dart';
import '../../chat/chat_providers.dart';
import '../../chat/chat_state.dart';
import '../../chat/pending_attachments_provider.dart';
import '../../chat/selection_provider.dart';
import '../../chat/widgets/attachment_pending_bar.dart';
import '../../chat/widgets/context_window_indicator.dart';
import '../../chat/widgets/context_window_popover.dart';
import '../../chat/widgets/perf_monitor_panel.dart';
import '../../chat/widgets/selection_chips.dart';
import '../../desktop/desktop_settings.dart';
import '../../prompts/widgets/saved_prompts_sheet.dart';
import '../../settings/chat_send_shortcut_settings.dart';
import '../../settings/composer_settings.dart';
import '../../settings/settings_providers.dart';

/// 触发附件/图片粘贴意图（快捷键或右键菜单触发）。
class PasteAttachmentIntent extends Intent {
  const PasteAttachmentIntent();
}

/// 触发发送消息意图（Ctrl+Enter / Cmd+Enter 快捷键；enter 模式下仅作兜底）。
class SendMessageIntent extends Intent {
  const SendMessageIntent();
}

/// 触发发送意图（回车快捷键：经典单行全平台 / 两段式桌面端）。
class SendIntent extends Intent {
  const SendIntent();
}

/// 触发换行意图（Shift+Enter 或移动端两段式回车）。
class InsertNewlineIntent extends Intent {
  const InsertNewlineIntent();
}

/// 输入栏（chat_spec.md §4.2：idle 发送；流式期间 steer/停止；模型选择；附件）。
///
/// - idle：附件按钮 + 输入框 + 发送；
/// - 流式：附件按钮 + 输入框 + steer 发送 + 停止；
/// - sending：输入禁用（发送请求在途）。
class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key, required this.sessionId, this.enabled = true});

  final String sessionId;

  /// 输入栏可用性（只读会话传 false：输入/附件/模型/发送全部禁用）。
  final bool enabled;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final TextEditingController _textController = TextEditingController();
  late GlobalKey _bookmarkKey;
  late GlobalKey _contextIndicatorKey;
  bool _hasText = false;
  bool _draftApplied = false;
  bool _pendingAutoOpen = false;

  @override
  void initState() {
    super.initState();
    _bookmarkKey = GlobalKey(debugLabel: 'chat-bookmark-${widget.sessionId}');
    _contextIndicatorKey = GlobalKey(
      debugLabel: 'chat-context-${widget.sessionId}',
    );
    _checkRecentlyCreatedOnMount();
    // 挂载后恢复本会话草稿（postFrame 避开 build 期 setState）；挂载时若已有
    // 未消费的 prefill（切换会话等罕见遗留）一并消费。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref
          .read(chatControllerProvider(widget.sessionId))
          .composerPrefill;
      if (current != null) _consumePrefill(current);
      _restoreDraft();
      _tryAutoOpenContextPopover();
    });
  }

  void _checkRecentlyCreatedOnMount() {
    _pendingAutoOpen = false;
    final recentlyCreated = ref.read(recentlyCreatedSessionIdProvider);
    if (recentlyCreated == widget.sessionId) {
      scheduleMicrotask(() {
        if (mounted) {
          ref.read(recentlyCreatedSessionIdProvider.notifier).clear();
        }
      });
      final autoOpenEnabled = ref.read(autoOpenContextOnNewSessionProvider);
      if (autoOpenEnabled) {
        _pendingAutoOpen = true;
      }
    }
  }

  void _tryAutoOpenContextPopover() {
    if (!_pendingAutoOpen || !mounted) return;
    final snapshot = ref
        .read(chatControllerProvider(widget.sessionId))
        .contextWindowSnapshot;
    if (snapshot == null) return;
    _pendingAutoOpen = false;
    unawaited(_showContextPopover());
  }

  /// 从本会话草稿存储恢复输入框（仅当输入框为空时，避免覆盖 prefill）。
  void _restoreDraft() {
    if (_draftApplied || !mounted) return;
    if (_textController.text.isNotEmpty) {
      _draftApplied = true;
      return;
    }
    final draft = ref.read(chatDraftProvider(widget.sessionId));
    if (draft.isNotEmpty) {
      _textController.text = draft;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: draft.length),
      );
    }
    _draftApplied = true;
    final pending = ref.read(pendingSelectionsProvider(widget.sessionId));
    final pendingAttachments = ref.read(
      pendingAttachmentsProvider(widget.sessionId),
    );
    final hasText =
        draft.trim().isNotEmpty ||
        pending.isNotEmpty ||
        pendingAttachments.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _bookmarkKey = GlobalKey(debugLabel: 'chat-bookmark-${widget.sessionId}');
      _contextIndicatorKey = GlobalKey(
        debugLabel: 'chat-context-${widget.sessionId}',
      );
      _checkRecentlyCreatedOnMount();
      // 切会话：清空旧文本，postFrame 恢复新会话草稿（各会话草稿独立）。
      _textController.clear();
      _draftApplied = false;
      _appliedPrefill = null;
      setState(() => _hasText = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restoreDraft();
        _tryAutoOpenContextPopover();
      });
    }
  }

  bool _uploading = false;

  /// 已消费的 composerPrefill 值（去重，避免重复写入输入框）。
  String? _appliedPrefill;

  /// 监听 [sessionId] 会话的 composerPrefill 变化并消费。
  ///
  /// 必须在 `build()` 内调用：Riverpod 2.x 的 `ref.listen` 只能在 build 阶段
  /// 注册（`debugDoingBuild` 断言），并在每次 build 时自动清理旧订阅，因此
  /// 会话切换后下一次 build 自然切换到新会话的监听；回调里再以
  /// `sessionId != widget.sessionId` 防御同一帧内的切换窗口残留通知。
  void _bindPrefillListener(String sessionId) {
    ref.listen<ChatState>(chatControllerProvider(sessionId), (previous, next) {
      if (sessionId != widget.sessionId) return;
      _consumePrefill(next.composerPrefill);
    });
  }

  /// 监听新会话的 contextWindowSnapshot 就绪并在首次进入时自动打开上下文弹窗。
  void _bindAutoOpenListener(String sessionId) {
    ref.listen<ChatState>(chatControllerProvider(sessionId), (previous, next) {
      if (sessionId != widget.sessionId) return;
      if (_pendingAutoOpen && next.contextWindowSnapshot != null) {
        _pendingAutoOpen = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_showContextPopover());
          }
        });
      }
    });
  }

  /// 消费 [prefill]：非 null 且未被消费过 → 写入输入框（光标置末尾）+ 同步
  /// 草稿，再清除 provider 值；prefill 为 null（清除后）→ 复位 [_appliedPrefill]，
  /// 保证第二次以相同文本 prefill 仍能生效（#25 验收：连点第二次仍回填）。
  ///
  /// 由 `build()` 内注册的 `ref.listen` 回调驱动：Riverpod
  /// provider 值变化只会触发 listener，不会再次回调 didChangeDependencies。
  void _consumePrefill(String? prefill) {
    if (!mounted) return;
    if (prefill == null) {
      _appliedPrefill = null;
      return;
    }
    if (prefill == _appliedPrefill) return;
    _appliedPrefill = prefill;
    _textController.text = prefill;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: prefill.length),
    );
    final hasText = prefill.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
    // prefill 视为一次性的草稿内容：同步写入本会话草稿存储，后续编辑覆盖。
    ref.read(chatDraftProvider(widget.sessionId).notifier).update(prefill);
    ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .clearComposerPrefill();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _textController.text;
    final repo = ref.read(pendingSelectionsProvider(widget.sessionId).notifier);
    final pendingAttachments = ref.read(
      pendingAttachmentsProvider(widget.sessionId),
    );
    final extra = repo.buildMessageForApi(raw);
    // 附件引用后缀（对齐 Swift PendingAttachment.chatMessageText）
    final message = PendingAttachment.chatMessageText(
      extra.trim(),
      pendingAttachments,
    );
    if (message.trim().isEmpty) return;
    _textController.clear();
    setState(() => _hasText = false);
    // await 前一次性捕获全部 notifier（均无 autoDispose，随容器常驻）：
    // 发送途中切会话/退页导致本 widget dispose 后，`ref` 即不可再用
    // （platform_error: Cannot use "ref" after the widget was disposed）。
    final controller = ref.read(
      chatControllerProvider(widget.sessionId).notifier,
    );
    final selectionsRepo = repo;
    final attachmentsRepo = ref.read(
      pendingAttachmentsProvider(widget.sessionId).notifier,
    );
    final draftRepo = ref.read(chatDraftProvider(widget.sessionId).notifier);
    final sent = await controller.send(
      message,
      attachments: pendingAttachments,
    );
    if (sent) {
      if (extra != raw) {
        selectionsRepo.clear();
      }
      attachmentsRepo.clear();
      // 发送成功：清空本会话草稿（prefill 也已随发送消费）。
      draftRepo.clear();
    } else {
      // 发送失败：仅在本页仍在场时回填输入框（_textController 已随 dispose
      // 销毁，退页后触碰同样抛 StateError）；草稿回填是数据层操作照常执行。
      if (mounted) {
        _textController.text = raw;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        setState(() => _hasText = raw.trim().isNotEmpty);
      }
      // 发送失败：草稿同步回填内容（继续编辑保留）。
      draftRepo.update(raw);
    }
  }

  /// Ctrl+Enter/Cmd+Enter 快捷键发送的前置条件。
  ///
  /// 对齐发送按钮条件 `interactive && (_hasText || canSendWithPending)`，
  /// 且流式/到来中（sending）阶段不发送（任务书 §4.5 边界）；按钮行为不变。
  bool _canSendByShortcut() {
    final phase = ref.read(chatPhaseProvider(widget.sessionId));
    final isStreaming =
        phase == ChatPhase.streaming ||
        phase == ChatPhase.steered ||
        phase == ChatPhase.approvalPending ||
        phase == ChatPhase.clarifyPending ||
        phase == ChatPhase.recovering;
    final isSending = phase == ChatPhase.sending;
    if (!widget.enabled || isSending || isStreaming) return false;
    final pending = ref.read(pendingSelectionsProvider(widget.sessionId));
    final pendingAttachments = ref.read(
      pendingAttachmentsProvider(widget.sessionId),
    );
    return _hasText || pending.isNotEmpty || pendingAttachments.isNotEmpty;
  }

  /// 在光标处插入换行（两段式 Shift+Enter / 移动端 Enter 路径）。
  void _insertNewline() {
    final currentText = _textController.text;
    final selection = _textController.selection;
    final int start = selection.isValid ? selection.start : currentText.length;
    final int end = selection.isValid ? selection.end : currentText.length;
    final int min = start < end ? start : end;
    final int max = start > end ? start : end;

    final newText = currentText.replaceRange(min, max, '\n');
    final newOffset = min + 1;
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );

    final pending = ref.read(pendingSelectionsProvider(widget.sessionId));
    final canSendWithPending =
        pending.isNotEmpty ||
        ref.read(pendingAttachmentsProvider(widget.sessionId)).isNotEmpty;
    final hasText = newText.trim().isNotEmpty || canSendWithPending;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  Future<void> _handleAttachment() async {
    if (_uploading) return;
    final l10n = AppLocalizations.of(context);
    final picker = ref.read(filePickerServiceProvider);
    final FilePickerResult? picked;
    try {
      picked = await picker.pickFile();
    } catch (error) {
      await _showError(l10n.selectFileFailed, _errorMessage(error));
      return;
    }
    if (picked == null) return; // 用户取消

    setState(() => _uploading = true);
    try {
      final client = ref.read(apiClientProvider);
      final resp = await client.uploadFile(
        sessionId: widget.sessionId,
        data: picked.bytes,
        filename: picked.name,
      );
      if (!mounted) return;
      // 只入待发附件列表，不直接发送；点发送时随消息一并提交。
      ref
          .read(pendingAttachmentsProvider(widget.sessionId).notifier)
          .add(
            PendingAttachment(
              name: picked.name,
              path: resp.path ?? picked.name,
              mime: resp.mime ?? '',
              size: resp.size ?? picked.bytes.length,
              isImage: resp.isImage ?? false,
              thumbnailData: picked.bytes,
            ),
          );
    } catch (error) {
      if (!mounted) return;
      await _showError(l10n.uploadFailed, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 粘贴得到的图片/文件：上传完成后进入待发附件列表（发送由用户点按钮触发）。
  Future<void> _handlePasteBytes(Uint8List bytes, String filename) async {
    if (_uploading) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _uploading = true);
    try {
      final client = ref.read(apiClientProvider);
      final resp = await client.uploadFile(
        sessionId: widget.sessionId,
        data: bytes,
        filename: filename,
      );
      if (!mounted) return;
      ref
          .read(pendingAttachmentsProvider(widget.sessionId).notifier)
          .add(
            PendingAttachment(
              name: filename,
              path: resp.path ?? filename,
              mime: resp.mime ?? '',
              size: resp.size ?? bytes.length,
              isImage: resp.isImage ?? false,
              thumbnailData: bytes,
            ),
          );
    } catch (error) {
      if (!mounted) return;
      await _showError(l10n.uploadFailed, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _handlePaste() async {
    final phase = ref.read(chatPhaseProvider(widget.sessionId));
    final isSending = phase == ChatPhase.sending;
    if (!widget.enabled || isSending || _uploading) return;

    // 对话框复制文本后右键粘贴闪退的主因：纯文本也先走 FFI 的
    // ClipboardReader.readClipboard()（super_clipboard），在 Windows 上
    // Dart 3.13 + irondash 0.1.1 会直接 abort。
    // 修复：附件探测与纯文本路径彻底解耦——任意一边异常都不影响另一边。
    PastedAttachment? attachment;
    try {
      attachment = await ref
          .read(clipboardPasteServiceProvider)
          .readPastedAttachment();
    } catch (_) {
      attachment = null;
    }

    if (attachment != null && attachment.bytes.isNotEmpty) {
      await _handlePasteBytes(attachment.bytes, attachment.filename);
      return;
    }

    // 无附件或探测超时/失败：回落到纯文本粘贴（引擎通道，Windows 安全）
    try {
      await _pastePlainText();
    } catch (_) {}
  }

  Future<void> _pastePlainText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final textToInsert = data?.text;
    if (textToInsert == null || textToInsert.isEmpty) return;

    final currentText = _textController.text;
    final selection = _textController.selection;
    final int start = selection.isValid ? selection.start : currentText.length;
    final int end = selection.isValid ? selection.end : currentText.length;
    final int min = start < end ? start : end;
    final int max = start > end ? start : end;

    final int clampedMin = min.clamp(0, currentText.length);
    final int clampedMax = max.clamp(0, currentText.length);

    final newText = currentText.replaceRange(
      clampedMin,
      clampedMax,
      textToInsert,
    );
    final newOffset = clampedMin + textToInsert.length;
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );

    final pending = ref.read(pendingSelectionsProvider(widget.sessionId));
    final pendingAttachments = ref.read(
      pendingAttachmentsProvider(widget.sessionId),
    );
    final canSendWithPending =
        pending.isNotEmpty || pendingAttachments.isNotEmpty;
    final hasText = newText.trim().isNotEmpty || canSendWithPending;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  Future<void> _showError(String title, String message) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(
          message,
          style: TextStyle(color: statusRedText.resolveFrom(context)),
        ),
        actions: [
          CupertinoDialogAction(
            textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? const TextStyle(color: LightSurfaces.userDetail)
                : null,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }

  /// 停止生成（用户显式点击停止按钮的入口）：先弹 Cupertino 二次确认框，
  /// 用户确认后才真正调用 controller.stop()。
  ///
  /// 内部程序性停止（dispose / 看门狗 / 重连 / 发新消息顺带停旧流 /
  /// clarify 流）一律直接走 controller.stop()，不经此确认框。
  Future<void> _stop() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.stopGeneratingTitle),
        content: Text(l10n.stopGeneratingConfirmPrompt),
        actions: [
          CupertinoDialogAction(
            textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? const TextStyle(color: LightSurfaces.userDetail)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            textStyle: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? TextStyle(color: statusRedText.resolveFrom(context))
                : null,
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.stopGenerating),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(chatControllerProvider(widget.sessionId).notifier).stop();
  }

  void _insertPromptText(String text) {
    final current = _textController.text;
    final next = current.trim().isEmpty
        ? text
        : '${current.replaceAll(RegExp(r'\s+$'), '')}\n\n$text';
    _textController.text = next;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _textController.text.length),
    );
    final hasText = next.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  Future<void> _showSavedPromptsSheet() async {
    // 宽屏（桌面/平板双栏）：在按钮上方弹出局部气泡，避免底部弹层遮蔽内容区；
    // 窄屏（手机）：保持系统底部 Sheet 体验。
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (isWide) {
      await showCupertinoPopover(
        context: context,
        anchorKey: _bookmarkKey,
        builder: (popoverContext, close) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppLocalizations.of(popoverContext).savedPromptsTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Container(
              height: 0.5,
              color: LightSurfaces.resolve(
                popoverContext,
                LightSurfaces.divider,
                dark: CupertinoColors.separator,
              ),
            ),
            SavedPromptsPanel(
              onInsert: _insertPromptText,
              getCurrentInput: () => _textController.text,
              onInserted: close,
            ),
          ],
        ),
      );
      return;
    }
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => SavedPromptsSheet(
        onInsert: _insertPromptText,
        getCurrentInput: () => _textController.text,
      ),
    );
  }

  Future<void> _showContextPopover() async {
    if (!mounted) return;
    final snapshot = ref
        .read(chatControllerProvider(widget.sessionId))
        .contextWindowSnapshot;
    if (snapshot == null) return;
    final currentModel = ref
        .read(chatControllerProvider(widget.sessionId))
        .model;
    await showCupertinoPopover(
      context: context,
      anchorKey: _contextIndicatorKey,
      preferredWidth: 260,
      maxHeight: 520,
      preferredHeight: 520,
      builder: (popoverContext, close) => ContextWindowPopover(
        sessionId: widget.sessionId,
        snapshot: snapshot,
        currentModel: currentModel,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 消费 composerPrefill：必须挂 ref.listen 于 build（provider 值变化只触发
    // listener / rebuild，不会再次回调 didChangeDependencies —— #25 实证：prefill
    // 已写入 provider 但输入框永不回填，根因即消费逻辑挂错生命周期）。
    _bindPrefillListener(widget.sessionId);
    _bindAutoOpenListener(widget.sessionId);
    final l10n = AppLocalizations.of(context);
    final phase = ref.watch(chatPhaseProvider(widget.sessionId));
    final isStreaming =
        phase == ChatPhase.streaming ||
        phase == ChatPhase.steered ||
        phase == ChatPhase.approvalPending ||
        phase == ChatPhase.clarifyPending ||
        phase == ChatPhase.recovering;
    final isSending = phase == ChatPhase.sending;
    final interactive = widget.enabled;
    final pending = ref.watch(pendingSelectionsProvider(widget.sessionId));
    final pendingAttachments = ref.watch(
      pendingAttachmentsProvider(widget.sessionId),
    );
    final canSendWithPending =
        pending.isNotEmpty || pendingAttachments.isNotEmpty;
    final snapshot = ref
        .watch(chatControllerProvider(widget.sessionId))
        .contextWindowSnapshot;
    final sendMode = ref.watch(chatSendShortcutSettingsProvider).mode;
    // 两段式输入栏开关（设置 → 对话；默认关闭=经典单行）。
    final twoPane = ref.watch(composerTwoPaneProvider);
    final isDesktop = isDesktopPlatform();
    final multiline =
        sendMode == ChatSendShortcutMode.ctrlEnter || (twoPane && !isDesktop);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionChipPanel(sessionId: widget.sessionId),
        AttachmentPendingBar(sessionId: widget.sessionId),
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.divider,
                  dark: CupertinoColors.systemGrey4,
                ),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SafeArea(
            top: false,
            child: twoPane
                ? _buildTwoPaneComposer(
                    l10n,
                    isStreaming,
                    isSending,
                    interactive,
                    canSendWithPending,
                    snapshot,
                    sendMode,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AccessibleButton(
                        key: const ValueKey('chat-attach-button'),
                        label: l10n.addAttachment,
                        onPressed: (!interactive || isSending || _uploading)
                            ? null
                            : _handleAttachment,
                        padding: EdgeInsets.zero,
                        child: _uploading
                            ? const CupertinoActivityIndicator()
                            : Icon(
                                CupertinoIcons.plus_circle,
                                size: 22,
                                color: LightSurfaces.resolve(
                                  context,
                                  LightSurfaces.textSecondary,
                                  dark: const Color(0xFF8E8E93),
                                ),
                              ),
                      ),
                      Container(
                        key: _bookmarkKey,
                        child: AccessibleButton(
                          key: const ValueKey('chat-saved-prompts-button'),
                          label: l10n.bookmarkPrompt,
                          onPressed: (!interactive || isSending || _uploading)
                              ? null
                              : _showSavedPromptsSheet,
                          padding: EdgeInsets.zero,
                          child: Icon(
                            CupertinoIcons.bookmark,
                            size: 22,
                            color: LightSurfaces.resolve(
                              context,
                              LightSurfaces.textSecondary,
                              dark: const Color(0xFF8E8E93),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        key: _contextIndicatorKey,
                        child: ContextWindowIndicator(
                          snapshot: snapshot,
                          onTap: _showContextPopover,
                        ),
                      ),
                      Expanded(
                        child: Shortcuts(
                          shortcuts: const <ShortcutActivator, Intent>{
                            SingleActivator(
                              LogicalKeyboardKey.keyV,
                              control: true,
                            ): PasteAttachmentIntent(),
                            SingleActivator(
                              LogicalKeyboardKey.keyV,
                              meta: true,
                            ): PasteAttachmentIntent(),
                            // Ctrl+Enter / Cmd+Enter 发送（ctrlEnter 模式主路径；
                            // enter 模式下 Ctrl+Enter 也可发送，无副作用）
                            SingleActivator(
                              LogicalKeyboardKey.enter,
                              control: true,
                            ): SendMessageIntent(),
                            SingleActivator(
                              LogicalKeyboardKey.enter,
                              meta: true,
                            ): SendMessageIntent(),
                          },
                          child: Actions(
                            actions: <Type, Action<Intent>>{
                              PasteAttachmentIntent:
                                  CallbackAction<PasteAttachmentIntent>(
                                    onInvoke: (intent) {
                                      unawaited(_handlePaste());
                                      return null;
                                    },
                                  ),
                              PasteTextIntent: CallbackAction<PasteTextIntent>(
                                onInvoke: (intent) {
                                  unawaited(_handlePaste());
                                  return null;
                                },
                              ),
                              SendMessageIntent:
                                  CallbackAction<SendMessageIntent>(
                                    onInvoke: (intent) {
                                      if (_canSendByShortcut()) {
                                        unawaited(_submit());
                                      }
                                      return null;
                                    },
                                  ),
                            },
                            child: CupertinoTextField(
                              key: const ValueKey('chat-input-field'),
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
                              placeholderStyle:
                                  CupertinoTheme.brightnessOf(context) ==
                                      Brightness.light
                                  ? const TextStyle(
                                      fontWeight: FontWeight.w400,
                                      color: LightSurfaces.placeholder,
                                    )
                                  : const CupertinoTextField().placeholderStyle,

                              controller: _textController,
                              placeholder: !interactive
                                  ? l10n.readOnlySessionPlaceholder
                                  : (isStreaming
                                        ? l10n.steerPromptPlaceholder
                                        : l10n.sendMessagePlaceholder),
                              enabled: !isSending && !_uploading && interactive,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              // 行数策略（主人定版）：经典模式保留自适应 max4 软上限
                              // （不收回单行）；ctrlEnter 模式多行不封顶。
                              minLines: 1,
                              maxLines: multiline ? null : 4,
                              contextMenuBuilder: (context, editableTextState) {
                                final buttonItems = editableTextState
                                    .contextMenuButtonItems
                                    .map((item) {
                                      if (item.type ==
                                          ContextMenuButtonType.paste) {
                                        return ContextMenuButtonItem(
                                          type: item.type,
                                          label: item.label,
                                          onPressed: () {
                                            ContextMenuController.removeAny();
                                            unawaited(_handlePaste());
                                          },
                                        );
                                      }
                                      return item;
                                    })
                                    .toList();
                                return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                                  buttonItems: buttonItems,
                                  anchors: editableTextState.contextMenuAnchors,
                                );
                              },
                              onChanged: (value) {
                                ref
                                    .read(
                                      chatDraftProvider(widget.sessionId)
                                          .notifier,
                                    )
                                    .update(value);
                                final hasText =
                                    value.trim().isNotEmpty ||
                                    canSendWithPending;
                                if (hasText != _hasText) {
                                  setState(() => _hasText = hasText);
                                }
                              },
                              onSubmitted: (_) {
                                // 豁口一修复：
                                // 1. ctrlEnter 模式：发送只走 Shortcuts 通道（Ctrl+Enter/Cmd+Enter），
                                //    onSubmitted 绝不提交（桌面 IME/done 动作不发，裸 Enter 交引擎默认换行）。
                                if (sendMode ==
                                    ChatSendShortcutMode.ctrlEnter) {
                                  return;
                                }
                                // 2. enter 模式防双发：Ctrl+Enter/Cmd+Enter 同样走 Shortcuts 通道（SendMessageIntent），
                                //    若修饰键按下则跳过，交给 Shortcuts 处理；裸 Enter 照常提交。
                                if (HardwareKeyboard
                                        .instance
                                        .isControlPressed ||
                                    HardwareKeyboard.instance.isMetaPressed) {
                                  return;
                                }
                                unawaited(_submit());
                              },
                            ),
                          ),
                        ),
                      ),
                      if (isStreaming) ...[
                        AccessibleButton(
                          key: const ValueKey('chat-stop-button'),
                          label: l10n.stopGenerating,
                          onPressed: _stop,
                          padding: EdgeInsets.zero,
                          child: const Icon(
                            CupertinoIcons.stop_circle,
                            size: 22,
                            color: CupertinoColors.systemRed,
                          ),
                        ),
                        AccessibleButton(
                          key: const ValueKey('chat-steer-button'),
                          label: l10n.steerPrompt,
                          onPressed: (interactive && _hasText) ? _submit : null,
                          padding: EdgeInsets.zero,
                          child: const Icon(
                            CupertinoIcons.arrow_right_circle,
                            size: 22,
                            color: CupertinoColors.activeBlue,
                          ),
                        ),
                      ] else if (!isSending)
                        AccessibleButton(
                          key: const ValueKey('chat-send-button'),
                          label: l10n.sendMessage,
                          onPressed:
                              (interactive && (_hasText || canSendWithPending))
                              ? _submit
                              : null,
                          padding: EdgeInsets.zero,
                          child: const Icon(
                            CupertinoIcons.arrow_up_circle,
                            size: 22,
                            color: CupertinoColors.activeBlue,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// 两段式 composer：上方多行文本区（min2/max8 自适应增高），下方独立工具行。
  Widget _buildTwoPaneComposer(
    AppLocalizations l10n,
    bool isStreaming,
    bool isSending,
    bool interactive,
    bool canSendWithPending,
    ContextWindowSnapshot? snapshot,
    ChatSendShortcutMode sendMode,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                const PasteAttachmentIntent(),
            const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                const PasteAttachmentIntent(),
            if (isDesktopPlatform()) ...{
              if (sendMode == ChatSendShortcutMode.ctrlEnter) ...{
                const SingleActivator(LogicalKeyboardKey.enter):
                    const InsertNewlineIntent(),
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    const InsertNewlineIntent(),
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    const SendIntent(),
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    const SendIntent(),
              } else ...{
                const SingleActivator(LogicalKeyboardKey.enter):
                    const SendIntent(),
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    const InsertNewlineIntent(),
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    const SendIntent(),
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    const SendIntent(),
              },
            },
            if (!isDesktopPlatform())
              const SingleActivator(LogicalKeyboardKey.enter):
                  const InsertNewlineIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              PasteAttachmentIntent: CallbackAction<PasteAttachmentIntent>(
                onInvoke: (intent) {
                  unawaited(_handlePaste());
                  return null;
                },
              ),
              PasteTextIntent: CallbackAction<PasteTextIntent>(
                onInvoke: (intent) {
                  unawaited(_handlePaste());
                  return null;
                },
              ),
              InsertNewlineIntent: CallbackAction<InsertNewlineIntent>(
                onInvoke: (intent) {
                  if (interactive && !isSending && !_uploading) {
                    _insertNewline();
                  }
                  return null;
                },
              ),
              SendIntent: CallbackAction<SendIntent>(
                onInvoke: (intent) {
                  if (interactive && !isSending && !_uploading) {
                    final canSend = isStreaming
                        ? _hasText
                        : (_hasText || canSendWithPending);
                    if (canSend) {
                      unawaited(_submit());
                    }
                  }
                  return null;
                },
              ),
            },
            child: CupertinoTextField(
              key: const ValueKey('chat-input-field'),
              decoration:
                  CupertinoTheme.brightnessOf(context) == Brightness.light
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

              controller: _textController,
              placeholder: !interactive
                  ? l10n.readOnlySessionPlaceholder
                  : (isStreaming
                        ? l10n.steerPromptPlaceholder
                        : l10n.sendMessagePlaceholder),
              enabled: !isSending && !_uploading && interactive,
              minLines: 2,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              contextMenuBuilder: (context, editableTextState) {
                final buttonItems = editableTextState.contextMenuButtonItems
                    .map((item) {
                      if (item.type == ContextMenuButtonType.paste) {
                        return ContextMenuButtonItem(
                          type: item.type,
                          label: item.label,
                          onPressed: () {
                            ContextMenuController.removeAny();
                            unawaited(_handlePaste());
                          },
                        );
                      }
                      return item;
                    })
                    .toList();
                return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                  buttonItems: buttonItems,
                  anchors: editableTextState.contextMenuAnchors,
                );
              },
              onChanged: (value) {
                ref
                    .read(chatDraftProvider(widget.sessionId).notifier)
                    .update(value);
                final hasText = value.trim().isNotEmpty || canSendWithPending;
                if (hasText != _hasText) {
                  setState(() => _hasText = hasText);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AccessibleButton(
              key: const ValueKey('chat-attach-button'),
              label: l10n.addAttachment,
              onPressed: (!interactive || isSending || _uploading)
                  ? null
                  : _handleAttachment,
              padding: EdgeInsets.zero,
              child: _uploading
                  ? const CupertinoActivityIndicator()
                  : Icon(
                      CupertinoIcons.plus_circle,
                      size: 22,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: const Color(0xFF8E8E93),
                      ),
                    ),
            ),
            Container(
              key: _bookmarkKey,
              child: AccessibleButton(
                key: const ValueKey('chat-saved-prompts-button'),
                label: l10n.bookmarkPrompt,
                onPressed: (!interactive || isSending || _uploading)
                    ? null
                    : _showSavedPromptsSheet,
                padding: EdgeInsets.zero,
                child: Icon(
                  CupertinoIcons.bookmark,
                  size: 22,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: const Color(0xFF8E8E93),
                  ),
                ),
              ),
            ),
            Container(
              key: _contextIndicatorKey,
              child: ContextWindowIndicator(
                snapshot: snapshot,
                onTap: _showContextPopover,
              ),
            ),
            const SizedBox(width: 8),
            // 性能监控面板：两段式且开关开启有数据时左靠剩余空间显示，紧跟左簇；无数据或关闭时不占位。
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: PerfMonitorPanel(),
              ),
            ),
            ..._buildTrailingControls(
              l10n,
              isStreaming,
              isSending,
              interactive,
              canSendWithPending,
            ),
          ],
        ),
      ],
    );
  }

  /// 右侧控件组：流式= 停止+steer（steer 在最右）；空闲= 发送。
  List<Widget> _buildTrailingControls(
    AppLocalizations l10n,
    bool isStreaming,
    bool isSending,
    bool interactive,
    bool canSendWithPending,
  ) {
    return [
      if (isStreaming) ...[
        AccessibleButton(
          key: const ValueKey('chat-stop-button'),
          label: l10n.stopGenerating,
          onPressed: _stop,
          padding: EdgeInsets.zero,
          child: const Icon(
            CupertinoIcons.stop_circle,
            size: 22,
            color: CupertinoColors.systemRed,
          ),
        ),
        AccessibleButton(
          key: const ValueKey('chat-steer-button'),
          label: l10n.steerPrompt,
          onPressed: (interactive && _hasText) ? _submit : null,
          padding: EdgeInsets.zero,
          child: const Icon(
            CupertinoIcons.arrow_right_circle,
            size: 22,
            color: CupertinoColors.activeBlue,
          ),
        ),
      ] else if (!isSending)
        AccessibleButton(
          key: const ValueKey('chat-send-button'),
          label: l10n.sendMessage,
          onPressed: (interactive && (_hasText || canSendWithPending))
              ? _submit
              : null,
          padding: EdgeInsets.zero,
          child: const Icon(
            CupertinoIcons.arrow_up_circle,
            size: 22,
            color: CupertinoColors.activeBlue,
          ),
        ),
    ];
  }
}
