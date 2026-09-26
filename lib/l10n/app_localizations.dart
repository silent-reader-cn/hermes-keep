import 'package:flutter/widgets.dart';

/// Lightweight localization facade for business text across Hermes.
///
/// The catalog keeps Chinese as the product default and provides English
/// fallbacks without requiring generated code.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;
  bool get isEnglish => locale.languageCode == 'en';

  // ---------------------------------------------------------------------------
  // Common / General
  // ---------------------------------------------------------------------------
  String get ok => isEnglish ? 'OK' : '好';
  String get cancel => isEnglish ? 'Cancel' : '取消';
  String get confirm => isEnglish ? 'Confirm' : '确定';
  String get clear => isEnglish ? 'Clear' : '清空';
  String get clearAll => isEnglish ? 'Clear All' : '全部清空';
  String get copy => isEnglish ? 'Copy' : '复制';
  String get save => isEnglish ? 'Save' : '保存';
  String get create => isEnglish ? 'Create' : '创建';
  String get delete => isEnglish ? 'Delete' : '删除';
  String get edit => isEnglish ? 'Edit' : '编辑';
  String get close => isEnglish ? 'Close' : '关闭';
  String get filterSessions => isEnglish ? 'Filter sessions' : '筛选会话';
  String get channels => isEnglish ? 'Channels' : '渠道';
  String get projects => isEnglish ? 'Projects' : '项目';
  String get displaySectionHeader => isEnglish ? 'Display' : '显示';
  String get showSubagentSessions =>
      isEnglish ? 'Show subagent sessions' : '显示 subagent 会话';
  String get retry => isEnglish ? 'Retry' : '重试';
  String get loading => isEnglish ? 'Loading…' : '加载中…';
  String get loadingEllipsis => isEnglish ? 'Loading…' : '加载中…';
  String get export => isEnglish ? 'Export' : '导出';
  String get rename => isEnglish ? 'Rename' : '重命名';
  String get notice => isEnglish ? 'Notice' : '提示';
  String get unknown => isEnglish ? 'Unknown' : '未知';
  String get unnamed => isEnglish ? 'Unnamed' : '未命名';
  String get unknownError => isEnglish ? 'Unknown error' : '未知错误';
  String get loadFailed => isEnglish ? 'Failed to load' : '加载失败';
  String get loadFailedRetry =>
      isEnglish ? 'Loading failed, please retry' : '加载失败，请重试';
  String get loadFailedPleaseRetry =>
      isEnglish ? 'Loading failed, please retry' : '加载失败，请重试';
  String get actionFailed => isEnglish ? 'Action Failed' : '操作失败';
  String get dismissNotice => isEnglish ? 'Dismiss notice' : '关闭提示';
  String get closeNotice => isEnglish ? 'Dismiss notice' : '关闭提示';
  String get dismissError => isEnglish ? 'Dismiss error' : '关闭错误提示';
  String get offlineCache => isEnglish ? 'Offline cache' : '离线缓存';
  String get all => isEnglish ? 'All' : '全部';
  String get name => isEnglish ? 'Name' : '名称';
  String get value => isEnglish ? 'Value' : '值';
  String get info => isEnglish ? 'Info' : '信息';
  String get description => isEnglish ? 'Description' : '描述';
  String get noDescription => isEnglish ? 'No description' : '暂无描述';
  String get copiedToClipboard => isEnglish ? 'Copied to clipboard' : '已复制到剪贴板';

  // ---------------------------------------------------------------------------
  // 1. Onboarding
  // ---------------------------------------------------------------------------
  String get connectServer => isEnglish ? 'Connect Server' : '连接服务器';
  String get connectYourHermesServer =>
      isEnglish ? 'Connect your Hermes server' : '连接你的 Hermes 服务器';

  String get inputServerAddressHint => isEnglish
      ? 'Enter the hermes-webui address (with port), e.g. https://hermes.example.com:8787'
      : '输入 hermes-webui 的地址（含端口），例如 https://hermes.example.com:8787';
  String get testConnection => isEnglish ? 'Test Connection' : '连接测试';
  String get haveApiKeySkipWizard =>
      isEnglish ? 'Have an API Key? Skip wizard' : '已有 API Key？跳过向导';
  String get checking => isEnglish ? 'Checking…' : '正在检查…';
  String get connectionFailed => isEnglish ? 'Connection failed' : '连接失败';
  String get connectionSuccessful =>
      isEnglish ? 'Connection successful' : '连接成功';
  String get connectionSuccessfulWithCheck =>
      isEnglish ? '✅ Connection successful' : '✅ 连接成功';
  String get serverReturnedAbnormalStatus =>
      isEnglish ? 'Server returned abnormal status' : '服务器返回异常状态';
  String get cannotConnectToServer =>
      isEnglish ? 'Cannot connect to server' : '无法连接到服务器';
  String get authentication => isEnglish ? 'Authentication' : '认证';
  String get detectingServerAuth =>
      isEnglish ? 'Detecting server authentication…' : '正在检测服务器认证…';
  String get serverNoPasswordRequired => isEnglish
      ? 'Password authentication is not enabled on this server, you can proceed directly'
      : '该服务器未启用密码认证，可直接继续';
  String get serverPasswordRequired => isEnglish
      ? 'Password authentication is required on this server, please log in'
      : '该服务器需要密码认证，请登录';
  String get usernameOptional => isEnglish ? 'Username (optional)' : '用户名（可选）';
  String get password => isEnglish ? 'Password' : '密码';
  String get skipAuthNoPasswordMode =>
      isEnglish ? 'Skip authentication (no-password mode)' : '跳过认证（无密码模式）';
  String get loginFailed => isEnglish ? 'Login Failed' : '登录失败';
  String loginFailedWithReason(String reason) =>
      isEnglish ? 'Login failed: $reason' : '登录失败：$reason';
  String loginFailedWithMessage(String msg) =>
      isEnglish ? 'Login failed: $msg' : '登录失败：$msg';
  String get cannotConnectRetryLater => isEnglish
      ? 'Cannot connect to server, please try again later'
      : '无法连接到服务器，请稍后重试';
  String get customHeadersOptional =>
      isEnglish ? 'Custom Headers (optional)' : '自定义 Headers（可选）';
  String get customHeadersDescription => isEnglish
      ? 'Add custom request headers for reverse proxy setups, e.g. Authorization: Bearer xxx'
      : '反向代理场景可添加自定义请求头，如 Authorization: Bearer xxx';
  String get addHeader => isEnglish ? 'Add Header' : '添加 Header';
  String get headerName => isEnglish ? 'Header Name' : 'Header 名';
  String get deleteHeader => isEnglish ? 'Delete Header' : '删除 Header';
  String get nextStep => isEnglish ? 'Next' : '下一步';
  String get continueAction => isEnglish ? 'Continue' : '继续';
  String get loginAndContinue => isEnglish ? 'Log in & Continue' : '登录并继续';
  String get finish => isEnglish ? 'Finish' : '完成';
  String get pleaseEnterServerUrl =>
      isEnglish ? 'Please enter the server address' : '请输入服务器地址';
  String get serverUrlRequired =>
      isEnglish ? 'Please enter the server address' : '请输入服务器地址';
  String get pleaseEnterValidServerUrl => isEnglish
      ? 'Please enter a valid server address, e.g. https://hermes.example.com:8787'
      : '请输入有效的服务器地址，例如 https://hermes.example.com:8787';
  String get serverUrlInvalid => isEnglish
      ? 'Please enter a valid server address, e.g. https://hermes.example.com:8787'
      : '请输入有效的服务器地址，例如 https://hermes.example.com:8787';
  String get headerValidationFailed => isEnglish
      ? 'Header name must be a valid token, and value cannot contain newlines'
      : 'Header 名必须是合法 token，值不能包含换行';
  String get connectAndSave => isEnglish ? 'Connect & Save' : '连接并保存';
  String get passwordVerified => isEnglish ? '✅ Password correct' : '✅ 密码正确';
  String get verifyingPassword => isEnglish ? 'Verifying password…' : '正在验证密码…';
  String get passwordRequiredOnServer => isEnglish
      ? 'This server requires a password. Enter it to connect.'
      : '该服务器需要密码认证，请填写密码后再连接';

  // ---------------------------------------------------------------------------
  // 2. Session List
  // ---------------------------------------------------------------------------
  String get sessions => isEnglish ? 'Sessions' : '会话';
  String get utilityNavigation => isEnglish ? 'Navigation' : '快捷导航';
  String get switchDestination => isEnglish ? 'Switch destination' : '切换目的地';
  String get doneSelecting => isEnglish ? 'Done' : '完成选择';
  String get newSession => isEnglish ? 'New Session' : '新建会话';
  String get searchSessions => isEnglish ? 'Search sessions' : '搜索会话';
  String get archived => isEnglish ? 'Archived' : '已归档';
  String get clearFilter => isEnglish ? 'Clear filter' : '清除筛选';
  String get untitledProject => isEnglish ? 'Untitled project' : '未命名项目';
  String selectedCount(int count) =>
      isEnglish ? 'Selected $count' : '已选 $count 个';
  String get selectAll => isEnglish ? 'Select All' : '全选';
  String get archive => isEnglish ? 'Archive' : '归档';
  String get batchMoveProject => isEnglish ? 'Move Project' : '移动项目';
  String get moveToProject => isEnglish ? 'Move to Project' : '移动到项目';
  String get pin => isEnglish ? 'Pin' : '置顶';
  String get unpin => isEnglish ? 'Unpin' : '取消置顶';
  String get unarchive => isEnglish ? 'Unarchive' : '恢复归档';
  String get branch => isEnglish ? 'Branch' : '分支';
  String get exportSession => isEnglish ? 'Export Session' : '导出会话';
  String get markdownFormat => isEnglish ? 'Markdown' : 'Markdown';
  String get jsonFormat => isEnglish ? 'JSON' : 'JSON';
  String exportSuccess(String format) =>
      isEnglish ? '$format exported successfully' : '$format 导出成功';
  String get exportContentEmpty =>
      isEnglish ? 'Exported content is empty' : '导出内容为空';
  String get copyContent => isEnglish ? 'Copy Content' : '复制内容';
  String get exportFailed => isEnglish ? 'Export Failed' : '导出失败';
  String get deleteSession => isEnglish ? 'Delete Session' : '删除会话';
  String confirmDeleteSession(String title) => isEnglish
      ? 'Are you sure you want to delete "$title"? This action cannot be undone.'
      : '确定删除「$title」？此操作不可撤销。';
  String get batchArchiveTitle => isEnglish ? 'Batch Archive' : '批量归档';
  String get confirmBatchArchivePrompt =>
      isEnglish ? 'Archive selected sessions?' : '归档选中的会话？';
  String get batchDeleteTitle => isEnglish ? 'Batch Delete' : '批量删除';
  String confirmBatchDeletePrompt(int count) => isEnglish
      ? 'Delete selected $count sessions? This action cannot be undone.'
      : '删除选中的 $count 个会话？此操作不可撤销。';
  String get noMore => isEnglish ? 'No more' : '没有更多了';
  String get noMatchingSessionsFound =>
      isEnglish ? 'No matching sessions found' : '未找到相关会话';
  String get noSessions => isEnglish ? 'No sessions' : '暂无会话';
  String get tryAnotherKeyword => isEnglish ? 'Try another keyword' : '换个关键词试试';
  String get tapButtonToStartNewChat =>
      isEnglish ? 'Tap the button below to start a new chat' : '点击下方按钮开始新对话';
  String get pendingInput => isEnglish ? 'Pending input' : '待输入';
  String get sessionActions => isEnglish ? 'Session Actions' : '会话操作';
  String get untitledSession => isEnglish ? 'Untitled session' : '未命名会话';
  String messageCountLabel(int count) =>
      isEnglish ? '$count messages' : '$count 条消息';
  String get scheduledSection => isEnglish ? 'Scheduled' : '定时';
  String get showCronSessionsTitle =>
      isEnglish ? 'Show Scheduled Sessions' : '显示定时会话';
  String get showCronSessionsSubtitle => isEnglish
      ? 'Display scheduled (cron) tasks in the session list'
      : '在会话列表中显示定时任务会话';
  String get pinnedSection => isEnglish ? 'Pinned' : '置顶';
  String get todaySection => isEnglish ? 'Today' : '今天';
  String get yesterdaySection => isEnglish ? 'Yesterday' : '昨天';
  String get earlierSection => isEnglish ? 'Earlier' : '更早';
  String get searchResultsSection => isEnglish ? 'Search Results' : '搜索结果';

  // ---------------------------------------------------------------------------
  // 3. Chat & Sub-components
  // ---------------------------------------------------------------------------
  String get branchBadge => isEnglish ? 'Branch' : '分支';
  String get branchSession => isEnglish ? 'Branch Session' : '分支会话';
  String branchSessionDescription(String parentId) => isEnglish
      ? 'This session is a branch of another session.\nParent session $parentId'
      : '该会话是另一个会话的分支。\n父会话 $parentId';
  String get jumpToParentSession =>
      isEnglish ? 'Jump to Parent Session' : '跳转父会话';
  String get renameSession => isEnglish ? 'Rename Session' : '重命名会话';
  String get compressSession => isEnglish ? 'Compress Session' : '压缩会话';
  String get focusTopicPlaceholder =>
      isEnglish ? 'Focus topic (optional)' : '聚焦主题（可留空）';
  String get compress => isEnglish ? 'Compress' : '压缩';
  String get undoLastTurn => isEnglish ? 'Undo Last Turn' : '撤销上一轮';
  String get confirmUndoLastTurnPrompt => isEnglish
      ? 'Delete the last turn of the conversation? This action cannot be undone'
      : '删除最后一轮对话？此操作不可撤销';
  String get retryLastTurn => isEnglish ? 'Retry Last Turn' : '重试上一轮';
  String get sessionSettings => isEnglish ? 'Session Settings' : '会话设置';
  String get workspaceOptionalPlaceholder =>
      isEnglish ? 'Workspace (optional)' : 'Workspace（可留空）';
  String get modelNameOptionalPlaceholder =>
      isEnglish ? 'Model name (optional)' : '模型名（可留空）';
  String get enableYolo => isEnglish ? 'Enable YOLO' : '开启 YOLO';
  String get disableYolo => isEnglish ? 'Disable YOLO' : '关闭 YOLO';
  String get createBranch => isEnglish ? 'Create Branch' : '创建分支';
  String get exportSuccessDialogTitle =>
      isEnglish ? 'Export Succeeded' : '导出成功';
  String get markdownCopiedToClipboard =>
      isEnglish ? 'Markdown copied to clipboard.' : 'Markdown 已复制到剪贴板。';
  String get approvalNeeded => isEnglish ? 'Approval Needed' : '需要审批';
  String get clarificationNeeded => isEnglish ? 'Clarification Needed' : '需要澄清';
  String get clarifyInputPlaceholder =>
      isEnglish ? 'Type your response…' : '输入你的回答…';
  String get clarifySend => isEnglish ? 'Send' : '发送';
  String get clarificationTimedOut =>
      isEnglish ? 'Clarification timed out' : '澄清已超时';
  String get clarifyHint => isEnglish
      ? 'Please choose one option, or type your own response below.'
      : '请选择一个选项，或在下方输入你的回答。';
  String get collapseClarification =>
      isEnglish ? 'Collapse clarification' : '折叠澄清';
  String get expandClarification => isEnglish ? 'Expand clarification' : '展开澄清';
  String get notificationsSection => isEnglish ? 'Notifications' : '通知';
  String get notificationsTitle => isEnglish ? 'Notifications' : '通知';
  String get notifyTurnsTitle =>
      isEnglish ? 'Turn Completed Notifications' : '回合完成通知';
  String get notifyTurnsSubtitle =>
      isEnglish ? 'Notify when an agent turn completes' : 'Agent 回合完成时推送通知';
  String get notifyClarifyTitle =>
      isEnglish ? 'Clarification Notifications' : '澄清请求通知';
  String get notifyClarifySubtitle =>
      isEnglish ? 'Notify when clarification is needed' : 'Agent 需要你澄清时推送通知';
  String get notifyErrorsTitle => isEnglish ? 'Error Notifications' : '异常中断通知';
  String get notifyErrorsSubtitle =>
      isEnglish ? 'Notify on session errors or interruption' : '会话异常中断或出错时推送通知';
  String get pushTestTitle => isEnglish ? 'Push Notification Test' : '推送测试';
  String get pushTestButton => isEnglish ? 'Push' : '推送';
  String get pushTestTurns => isEnglish ? 'Turn Completed' : '回合完成';
  String get pushTestClarify => isEnglish ? 'Clarification' : '需要澄清';
  String get pushTestErrors => isEnglish ? 'Error Interrupted' : '异常中断';
  String get pushTestTurnsNotificationTitle =>
      isEnglish ? 'Test: Turn Completed' : '测试：回合完成';
  String get pushTestClarifyNotificationTitle =>
      isEnglish ? 'Test: Clarification Needed' : '测试：需要澄清';
  String get pushTestErrorsNotificationTitle =>
      isEnglish ? 'Test: Error Interrupted' : '测试：异常中断';
  String pushTestBody(String timestamp) => isEnglish
      ? 'Tap to return to test session ($timestamp)'
      : '点击可回到测试会话（$timestamp）';
  String pushTestSuccess(String type) =>
      isEnglish ? 'Pushed: $type' : '已推送：$type';
  String pushTestDisabledNotice(String type) => isEnglish
      ? '$type notification is disabled, but test notification was sent (system channel is independent)'
      : '该类型通知已关闭，仍已推送测试通知（系统通道独立）';
  String get pushTestPermissionDenied =>
      isEnglish ? 'Notification permission denied' : '通知权限已被拒绝';
  String get bgKeepAliveSection => isEnglish ? 'Background Keepalive' : '后台保活';
  String get bgForegroundServiceTitle =>
      isEnglish ? 'Foreground Service Keepalive' : '前台服务保活';
  String get bgForegroundServiceSubtitle => isEnglish
      ? 'Show ongoing notification and hold wakelock during background generation to prevent network freeze'
      : '后台生成时显示常驻通知并持有唤醒锁，防止网络被系统冻结（实时性高）';
  String get bgWorkManagerStatusTitle =>
      isEnglish ? 'WorkManager Periodic Polling' : 'WorkManager 周期探活';
  String get bgWorkManagerStatusSubtitle => isEnglish
      ? 'Ready (15 min periodic + instant background poll fallback)'
      : '已就绪（15 分钟周期 + 切后台即时探活兜底）';
  String get bgHyperOsGuidanceTitle =>
      isEnglish ? 'System Keepalive & Permissions' : '系统保活与权限引导';
  String get bgHyperOsGuidanceSubtitle => isEnglish
      ? 'Jump to system settings for auto-start, unrestricted battery, etc.'
      : '跳转系统设置以开启自启动、无限制省电等';
  String get bgGuideAutoStart => isEnglish ? 'Auto-start' : '自启动';
  String get bgGuideBattery => isEnglish ? 'No Restrictions' : '省电无限制';
  String get bgGuideNetwork => isEnglish ? 'Network' : '联网控制';
  String get bgGuideNotifications => isEnglish ? 'Notifications' : '通知权限';
  String get bgPermissionWarningTitle =>
      isEnglish ? 'Notification permission not granted' : '通知权限未开启';
  String get bgPermissionWarningSubtitle => isEnglish
      ? 'Keepalive and turn notifications cannot show until you enable it'
      : '开启后保活与回合完成通知才能正常显示';
  String get bgGeneratingOngoingNotification =>
      isEnglish ? 'Hermes is generating…' : 'Hermes 正在生成…';
  String get bgGeneratingChannelName =>
      isEnglish ? 'Background Keepalive' : '后台生成保活';
  String get bgGeneratingChannelDescription => isEnglish
      ? 'Ongoing notification during background generation'
      : '后台流式生成进行中常驻通知';
  String get sessionErrorTitle => isEnglish ? 'Session Error' : '会话异常';
  String get sessionCancelledTitle =>
      isEnglish ? 'Response Cancelled' : '响应已取消';
  String get sessionDisconnectedTitle =>
      isEnglish ? 'Connection Disconnected' : '连接已断开';
  String queuedBannerMessage(int count) => isEnglish
      ? '$count messages queued, will be sent automatically when current reply ends'
      : '已排队 $count 条消息，将在当前回复结束后自动发送';
  String get offlineCacheBanner => isEnglish
      ? 'Offline cache mode. Content may not be up to date.'
      : '离线缓存模式，部分内容可能不是最新';
  String get dismissOfflineBanner =>
      isEnglish ? 'Dismiss offline cache notice' : '关闭离线提示';
  String get pickFileFailed => isEnglish ? 'Failed to Select File' : '选择文件失败';
  String get selectFileFailed => isEnglish ? 'Failed to Select File' : '选择文件失败';
  String get uploadSucceeded => isEnglish ? 'Upload Succeeded' : '上传成功';
  String get uploadSuccess => isEnglish ? 'Upload Succeeded' : '上传成功';
  String attachmentUploadedNotice(String name) =>
      isEnglish ? 'Attachment "$name" uploaded.' : '附件「$name」已上传。';
  String attachmentUploaded(String name) =>
      isEnglish ? 'Attachment "$name" uploaded.' : '附件「$name」已上传。';
  String get uploadFailed => isEnglish ? 'Upload Failed' : '上传失败';
  String get selectModel => isEnglish ? 'Select Model' : '选择模型';
  String get followServerDefault =>
      isEnglish ? 'Follow Server Default' : '跟随服务器默认';
  String get contextWindowTitle => isEnglish ? 'Context window' : '上下文窗口';
  String get contextWindowInput => isEnglish ? 'Input' : '输入';
  String get contextWindowOutput => isEnglish ? 'Output' : '输出';
  String get contextWindowThreshold => isEnglish ? 'Threshold' : '阈值';
  String get contextWindowCost => isEnglish ? 'Cost' : '费用';
  String get compressHint =>
      isEnglish ? 'Compress when usage is high' : '上下文较高时建议压缩';
  String get compressing => isEnglish ? 'Compressing…' : '压缩中…';
  String get unavailable => isEnglish ? 'Unavailable' : '暂无数据';
  // Context window indicator + popover (contextWindow* prefix)
  String get contextWindowUsage => isEnglish ? 'Context usage' : '上下文使用量';
  String get contextWindowUsageLoading =>
      isEnglish ? 'Context usage loading' : '上下文使用量加载中';
  String get contextWindowCurrentModel => isEnglish ? 'Current model' : '当前模型';
  String get contextWindowFollowServerDefault =>
      isEnglish ? 'Follow server default' : '跟随服务器默认';
  String get selectWorkspace => isEnglish ? 'Select Workspace' : '选择工作区';
  String get noWorkspacesAvailableHint => isEnglish
      ? 'No workspaces available (can be added in Settings → Manage Workspaces)'
      : '暂无可用工作区（可在设置→工作区管理中添加）';
  String get followSessionDefaultWorkspace =>
      isEnglish ? 'No workspace / Follow session default' : '未选择工作区 / 跟随会话默认';
  String get manualInputWorkspace => isEnglish ? 'Manual input' : '手动输入';
  String get contextWindowCompressNow =>
      isEnglish ? 'Compress now to free context' : '立即压缩以释放上下文';
  String get contextWindowCompressHint =>
      isEnglish ? 'Compress to free up space →' : '压缩以释放空间 →';
  String get contextWindowClose => isEnglish ? 'Close' : '关闭';
  String get modelLabel => isEnglish ? 'Model' : '模型';
  String get addAttachment => isEnglish ? 'Add Attachment' : '添加附件';
  String get sessionIsReadOnly =>
      isEnglish ? 'This session is read-only' : '此会话为只读';
  String get readOnlySessionPlaceholder =>
      isEnglish ? 'This session is read-only' : '此会话为只读';
  String get steerCurrentReplyPlaceholder =>
      isEnglish ? 'Steer current reply…' : '提示当前回复…';
  String get steerPromptPlaceholder =>
      isEnglish ? 'Steer current reply…' : '提示当前回复…';
  String get sendMessagePlaceholder => isEnglish ? 'Send a message…' : '发送消息…';
  String get steerCurrentReply => isEnglish ? 'Steer current reply' : '提示当前回复';
  String get steerPrompt => isEnglish ? 'Steer current reply' : '提示当前回复';
  String get stopGenerating => isEnglish ? 'Stop generating' : '停止生成';
  // todo #19 停止生成二次确认框（拍板稿：标题「停止生成？」+ 正文
  // 「确定要停止当前回复吗？已生成的内容会保留。」+ 取消/停止）
  String get stopGeneratingTitle => isEnglish ? 'Stop generating?' : '停止生成？';
  String get stopGeneratingConfirmPrompt => isEnglish
      ? 'Stop this reply? Already generated content will be kept.'
      : '确定要停止当前回复吗？已生成的内容会保留。';
  String get sendMessage => isEnglish ? 'Send message' : '发送消息';
  String get copiedToClipboardNotice =>
      isEnglish ? 'Copied to clipboard' : '已复制到剪贴板';
  String get thinking => isEnglish ? 'Thinking…' : '思考中…';
  String get thinkingIndicator => isEnglish ? 'Thinking…' : '思考中…';
  String get sending => isEnglish ? 'Sending…' : '发送中…';
  String get sendingIndicator => isEnglish ? 'Sending…' : '发送中…';
  String get reconnecting => isEnglish ? 'Reconnecting…' : '正在恢复连接…';
  String get reconnectingIndicator => isEnglish ? 'Reconnecting…' : '正在恢复连接…';
  String get messageActions => isEnglish ? 'Message Actions' : '消息操作';
  String get copyText => isEnglish ? 'Copy Text' : '复制文本';
  String get copyMarkdown => isEnglish ? 'Copy Markdown' : '复制 Markdown';
  String get copySelection => isEnglish ? 'Copy Selection' : '复制选中文本';
  String get editAndResend => isEnglish ? 'Edit and Resend' : '编辑并重新发送';
  String get branchFromHere => isEnglish ? 'Branch from Here' : '从此处创建分支';
  String get truncateFromHere => isEnglish ? 'Truncate from Here' : '从此处截断';
  String get confirmTruncatePrompt => isEnglish
      ? 'Delete all messages after this message? This action cannot be undone.'
      : '删除此消息之后的所有消息？此操作不可撤销。';
  String get truncate => isEnglish ? 'Truncate' : '截断';
  String get attachmentFallback => isEnglish ? 'Attachment' : '附件';
  String get thinkingBlock => isEnglish ? 'Thinking' : '思考';
  String get thinkingLabel => isEnglish ? 'Thinking' : '思考';
  String get runningDots => isEnglish ? 'Running…' : '运行中…';
  String get runningIndicator => isEnglish ? 'Running…' : '运行中…';
  String get failedStatus => isEnglish ? 'Failed' : '失败';
  String get runningStatus => isEnglish ? 'Running' : '运行中';
  String get toolFailedStatus => isEnglish ? 'Failed' : '失败';
  String get toolRunningStatus => isEnglish ? 'Running' : '运行中';
  String get noTools => isEnglish ? 'No tools' : '无工具';
  String get externalToolsLabel => isEnglish ? 'External Tools' : '外部工具';

  /// 本地化工具名称（chat / tool_call 聚合）。
  String localizeToolName(String name) {
    final key = name.trim().toLowerCase();
    switch (key) {
      case 'thinking':
      case 'think':
      case 'reasoning':
        return isEnglish ? 'Thinking' : '思考';
      case 'terminal':
      case 'exec':
      case 'shell':
      case 'bash':
      case 'cmd':
      case 'powershell':
      case 'zsh':
        return isEnglish ? 'Terminal' : '终端';
      case 'skill_view':
      case 'view_skill':
        return isEnglish ? 'Skill View' : '查看技能';
      case 'skill':
        return isEnglish ? 'Skill' : '技能';
      case 'execute_code':
      case 'exec_code':
      case 'code_execution':
      case 'run_code':
        return isEnglish ? 'Execute Code' : '执行代码';
      case 'todo_write':
      case 'write_todo':
      case 'todo_update':
        return isEnglish ? 'Todo Write' : '写入待办';
      case 'todo':
      case 'task':
        return isEnglish ? 'Todo' : '待办';
      case 'todo_list':
      case 'todo-list':
      case 'list_todos':
        return isEnglish ? 'Todo List' : '待办列表';
      case 'search_files':
      case 'file_search':
        return isEnglish ? 'Search Files' : '搜索文件';
      case 'read':
      case 'read_file':
      case 'readfile':
      case 'view_file':
      case 'viewfile':
      case 'cat':
        return isEnglish ? 'Read File' : '读取文件';
      case 'write':
      case 'write_file':
      case 'writefile':
      case 'write_to_file':
      case 'create_file':
        return isEnglish ? 'Write File' : '写入文件';
      case 'patch':
      case 'apply_patch':
      case 'applypatch':
      case 'replace_file_content':
      case 'edit_file':
      case 'editfile':
      case 'str_replace':
        return isEnglish ? 'Apply Patch' : '应用补丁';
      case 'memory':
      case 'memory_write':
      case 'memory_read':
        return isEnglish ? 'Memory' : '记忆';
      case 'web_search':
      case 'websearch':
        return isEnglish ? 'Web Search' : '联网搜索';
      case 'web_extract':
      case 'webextract':
      case 'web_fetch':
      case 'webfetch':
      case 'read_url_content':
      case 'fetch_web':
        return isEnglish ? 'Web Fetch' : '网页提取';
      case 'skill_manage':
      case 'skillmanage':
        return isEnglish ? 'Skill Manage' : '技能管理';
      case 'cronjob':
      case 'cron_job':
      case 'cron':
        return isEnglish ? 'Cron Job' : '定时任务';
      case 'send_message':
      case 'sendmessage':
      case 'send_msg':
        return isEnglish ? 'Send Message' : '发送消息';
      case 'browser_navigate':
      case 'browsernavigate':
      case 'browser_action':
      case 'browser':
      case 'browse':
        return isEnglish ? 'Browser' : '浏览器导航';
      case 'vision_analyze':
      case 'visionanalyze':
      case 'vision':
        return isEnglish ? 'Vision Analyze' : '视觉分析';
      case 'subagent_progress':
      case 'subagentprogress':
        return isEnglish ? 'Subagent Progress' : '子代理进度';
      case 'delegate_task':
      case 'delegate-task':
      case 'delegatetask':
      case 'invoke_subagent':
        return isEnglish ? 'Delegate Task' : '委派任务';
      case 'agent':
      case 'subagent':
      case 'sub_agent':
        return isEnglish ? 'Agent' : '智能体';
      case 'search':
      case 'grep':
      case 'grep_search':
      case 'ripgrep':
        return isEnglish ? 'Search' : '搜索';
      case 'grep_code':
        return isEnglish ? 'Code Search' : '代码搜索';
      case 'glob':
        return isEnglish ? 'Glob' : '文件检索';
      case 'list_dir':
      case 'listdir':
      case 'list_files':
      case 'find_by_name':
      case 'find':
        return isEnglish ? 'List Files' : '文件列表';
      case 'process':
      case 'proc':
      case 'background_process':
        return isEnglish ? 'Process' : '后台进程';
      case 'process_manage':
      case 'process-manage':
        return isEnglish ? 'Process Manage' : '进程管理';
      case 'mem0':
      case 'mem0_search':
        return isEnglish ? 'Memory Search' : '记忆检索';
      case 'mem0_add':
        return isEnglish ? 'Memory Add' : '记忆写入';
      case 'mem0_update':
        return isEnglish ? 'Memory Update' : '记忆更新';
      case 'mem0_delete':
        return isEnglish ? 'Memory Delete' : '记忆删除';
      case 'clarify':
      case 'clarification':
        return isEnglish ? 'Clarify' : '澄清确认';
      case 'session_search':
      case 'search_sessions':
        return isEnglish ? 'Session Search' : '会话搜索';
      case 'skills_list':
      case 'list_skills':
        return isEnglish ? 'Skills List' : '技能列表';
      case 'text_to_speech':
      case 'tts':
      case 'tts_speak':
        return isEnglish ? 'Text to Speech' : '语音合成';
      case 'image_generate':
      case 'image_gen':
        return isEnglish ? 'Image Generate' : '图片生成';
      case 'tool_search':
        return isEnglish ? 'Tool Search' : '工具搜索';
      case 'tool_describe':
        return isEnglish ? 'Tool Describe' : '工具详情';
      case 'tool_call':
      case 'invoke_tool':
        return isEnglish ? 'Tool Call' : '调用工具';
      case 'browser_exec':
      case 'browserexec':
        return isEnglish ? 'Browser Execute' : '浏览器执行';
      case 'kanban':
      case 'kanban_list':
      case 'kanban_create':
      case 'kanban_show':
      case 'kanban_complete':
      case 'kanban_comment':
      case 'kanban_heartbeat':
        return isEnglish ? 'Kanban' : '看板';
      case 'video_generate':
      case 'video_gen':
        return isEnglish ? 'Video Generate' : '视频生成';
      case 'video_analyze':
        return isEnglish ? 'Video Analyze' : '视频分析';
      case 'x_search':
        return isEnglish ? 'X Search' : 'X 搜索';
      default:
        final trimmed = name.trim();
        return trimmed.isEmpty ? (isEnglish ? 'Tool' : '工具') : trimmed;
    }
  }

  String get imageLoadFailed => isEnglish ? 'Failed to load image' : '图片加载失败';
  String get imageReload => isEnglish ? 'Reload' : '重新加载';
  String get imageDownloadOriginal => isEnglish ? 'Download Original' : '下载原图';
  String get mediaDownload => isEnglish ? 'Download' : '下载';
  String get previewUnsupported =>
      isEnglish ? 'Preview not supported' : '不支持预览';
  String get downloadFailed => isEnglish ? 'Download failed' : '下载失败';
  String get downloaded => isEnglish ? 'Downloaded' : '已下载';
  String get downloading => isEnglish ? 'Downloading…' : '下载中…';
  String get mediaAudio => isEnglish ? 'Audio' : '音频';
  String get mediaVideo => isEnglish ? 'Video' : '视频';
  String get mediaDocument => isEnglish ? 'Document' : '文档';
  String get mediaImage => isEnglish ? 'Image' : '图片';
  String get refreshImage => isEnglish ? 'Refresh image' : '刷新图片';
  String get refreshPreview => isEnglish ? 'Refresh preview' : '刷新预览';
  String get downloadsTitle => isEnglish ? 'Downloads' : '下载';
  String get downloadStatusQueued => isEnglish ? 'Queued' : '等待中';
  String get downloadStatusDownloading => isEnglish ? 'Downloading…' : '下载中…';
  String get downloadStatusCompleted => isEnglish ? 'Completed' : '已完成';
  String get downloadStatusFailed => isEnglish ? 'Failed' : '失败';
  String get downloadStatusCancelled => isEnglish ? 'Cancelled' : '已取消';
  String get downloadsEmpty => isEnglish ? 'No downloads yet' : '暂无下载记录';
  String get downloadConfirmTitle => isEnglish ? 'Download File' : '下载文件';
  String downloadConfirmBody({
    required String fileName,
    required String fileType,
    required String fileSize,
    String? session,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(isEnglish ? 'File name: $fileName' : '文件名：$fileName');
    buffer.writeln(isEnglish ? 'Type: $fileType' : '类型：$fileType');
    buffer.writeln(isEnglish ? 'Size: $fileSize' : '大小：$fileSize');
    if (session != null && session.isNotEmpty) {
      buffer.write(isEnglish ? 'Source session: $session' : '来源会话：$session');
    }
    return buffer.toString().trimRight();
  }

  String get downloadConfirmCancel => isEnglish ? 'Cancel' : '取消';
  String get downloadConfirmStart => isEnglish ? 'Start Download' : '开始下载';
  String get downloadOpen => isEnglish ? 'Open' : '打开';
  String get downloadRetry => isEnglish ? 'Retry' : '重试';
  String get downloadDelete => isEnglish ? 'Delete' : '删除';
  String get downloadClear => isEnglish ? 'Clear Completed' : '清除已完成';
  String get downloadClearConfirm => isEnglish
      ? 'Clear all completed and failed downloads?'
      : '清除所有已完成与失败的下载记录？';
  String get downloadFileMissing =>
      isEnglish ? 'File has been moved or deleted' : '文件已被移动或删除';
  String get downloadRedownload => isEnglish ? 'Redownload' : '重新下载';
  String get downloadUnknownSize => isEnglish ? 'Unknown size' : '未知大小';
  String get downloadModifiedTime => isEnglish ? 'Modified' : '修改时间';
  String downloadFromSessionLabel(String sessionId) =>
      isEnglish ? 'From session: $sessionId' : '来自会话：$sessionId';
  String get downloadFileTypeArchive => isEnglish ? 'Archive' : '压缩包';
  String get downloadFileTypeCode => isEnglish ? 'Code' : '代码';
  String get downloadFileTypeOther => isEnglish ? 'File' : '文件';
  String get downloadOpenFileFailed =>
      isEnglish ? 'Unable to open file' : '无法打开文件';

  // ---------------------------------------------------------------------------
  // 4. Tasks (Cron)
  // ---------------------------------------------------------------------------
  String get tasks => isEnglish ? 'Tasks' : '任务';
  String get cronTasks => isEnglish ? 'Scheduled Tasks' : '定时任务';
  String get tasksTitle => isEnglish ? 'Scheduled Tasks' : '定时任务';
  String get newScheduledTask => isEnglish ? 'New Scheduled Task' : '新建定时任务';
  String totalTasksHeader(int count) =>
      isEnglish ? '$count tasks in total' : '共 $count 个任务';
  String get noTasks => isEnglish ? 'No tasks' : '暂无任务';
  String get noTasksDescription => isEnglish
      ? 'Create scheduled tasks to let the assistant run automatically'
      : '创建定时任务，让助手按调度自动执行';
  String get createTaskPrompt => isEnglish
      ? 'Create scheduled tasks to let the assistant run automatically'
      : '创建定时任务，让助手按调度自动执行';
  String get newTask => isEnglish ? 'New Task' : '新建任务';
  String get editTask => isEnglish ? 'Edit Task' : '编辑任务';
  String get run => isEnglish ? 'Run' : '运行';
  String get runTask => isEnglish ? 'Run' : '运行';
  String get resume => isEnglish ? 'Resume' : '恢复';
  String get resumeTask => isEnglish ? 'Resume' : '恢复';
  String get pause => isEnglish ? 'Pause' : '暂停';
  String get pauseTask => isEnglish ? 'Pause' : '暂停';
  String get viewOutput => isEnglish ? 'View Output' : '查看输出';
  String get deleteTask => isEnglish ? 'Delete Task' : '删除任务';
  String confirmDeleteTaskPrompt(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"? This action cannot be undone.'
      : '确定删除「$name」？此操作不可撤销。';
  String confirmDeleteTask(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"? This action cannot be undone.'
      : '确定删除「$name」？此操作不可撤销。';
  String get taskActions => isEnglish ? 'Task Actions' : '任务操作';
  String lastRunTime(String time) =>
      isEnglish ? 'Last run $time' : '上次运行 $time';
  String get taskOutput => isEnglish ? 'Task Output' : '任务输出';
  String get closeOutputPanel => isEnglish ? 'Close Output Panel' : '关闭输出面板';
  String get noOutput => isEnglish ? 'No output' : '暂无输出';
  String outputNumber(int index) => isEnglish ? 'Output $index' : '输出 $index';
  String outputItemTitle(int index) =>
      isEnglish ? 'Output $index' : '输出 $index';
  String get taskName => isEnglish ? 'Name' : '名称';
  String get taskNamePlaceholder =>
      isEnglish ? 'Task name (optional)' : '任务名称（可选）';
  String get taskNameOptionalPlaceholder =>
      isEnglish ? 'Task name (optional)' : '任务名称（可选）';
  String get scheduleExpression => isEnglish ? 'Schedule Expression' : '调度表达式';
  String get schedulePlaceholder => isEnglish
      ? 'e.g. 0 9 * * * or every 2 hours'
      : '例如 0 9 * * * 或 every 2 hours';
  String get scheduleExpressionPlaceholder => isEnglish
      ? 'e.g. 0 9 * * * or every 2 hours'
      : '例如 0 9 * * * 或 every 2 hours';
  String get promptLabel => isEnglish ? 'Prompt' : '提示词';
  String get promptField => isEnglish ? 'Prompt' : '提示词';
  String get promptPlaceholder => isEnglish
      ? 'Prompt sent to the assistant when executed'
      : '定时执行时发送给助手的提示词';
  String get promptFieldPlaceholder => isEnglish
      ? 'Prompt sent to the assistant when executed'
      : '定时执行时发送给助手的提示词';
  String get pushNotifications => isEnglish ? 'Push Notifications' : '推送通知';
  String get statusRunning => isEnglish ? 'Running' : '运行中';
  String get statusNormal => isEnglish ? 'Active' : '正常';
  String get statusPaused => isEnglish ? 'Paused' : '已暂停';
  String get statusDisabled => isEnglish ? 'Disabled' : '已停用';
  String get statusError => isEnglish ? 'Error' : '出错';
  String get statusNeedsAttention => isEnglish ? 'Needs Attention' : '需关注';
  String get taskStatusRunning => isEnglish ? 'Running' : '运行中';
  String get taskStatusActive => isEnglish ? 'Active' : '正常';
  String get taskStatusNormal => isEnglish ? 'Active' : '正常';
  String get taskStatusPaused => isEnglish ? 'Paused' : '已暂停';
  String get taskStatusOff => isEnglish ? 'Disabled' : '已停用';
  String get taskStatusError => isEnglish ? 'Error' : '出错';
  String get taskStatusNeedsAttention => isEnglish ? 'Needs Attention' : '需关注';

  // ---------------------------------------------------------------------------
  // 5. Skills
  // ---------------------------------------------------------------------------
  String get skills => isEnglish ? 'Skills' : '技能';
  String get skillsTitle => isEnglish ? 'Skills' : '技能';
  String get refreshSkills => isEnglish ? 'Refresh Skills' : '刷新技能';
  String get searchSkills => isEnglish ? 'Search skills' : '搜索技能';
  String get noMatchingSkillsFound =>
      isEnglish ? 'No matching skills found' : '未找到相关技能';
  String get noSkills => isEnglish ? 'No skills' : '暂无技能';
  String get serverSkillsWillShowHere =>
      isEnglish ? 'Skills from the server will appear here' : '服务器的技能将显示在这里';
  String get disabledBadge => isEnglish ? 'Disabled' : '已禁用';
  String get skillDisabledBadge => isEnglish ? 'Disabled' : '已禁用';
  String get noMoreSkillDetails =>
      isEnglish ? 'No further details for this skill' : '该技能没有更多详情';
  String get noMoreDetailsForSkill =>
      isEnglish ? 'No further details for this skill' : '该技能没有更多详情';
  String get pathLabel => isEnglish ? 'Path' : '路径';
  String get skillPathLabel => isEnglish ? 'Path' : '路径';
  String get relatedSkillsLabel => isEnglish ? 'Related skills' : '相关技能';
  String get skillsGroupBuiltin => isEnglish ? 'Builtin' : '内置技能';
  String get skillsGroupProject => isEnglish ? 'Project' : '项目技能';
  String get skillsGroupGlobal => isEnglish ? 'Global' : '全局技能';
  String get skillsGroupOther => isEnglish ? 'Other' : '其他技能';

  // ---------------------------------------------------------------------------
  // 6. Memory
  // ---------------------------------------------------------------------------
  String get memory => isEnglish ? 'Memory' : '记忆';
  String get memoryTitle => isEnglish ? 'Memory' : '记忆';
  String get memoryEntrySubtitle =>
      isEnglish ? 'View notes, profile and project context' : '查看笔记、画像与项目上下文';
  String get refreshMemory => isEnglish ? 'Refresh Memory' : '刷新记忆';
  String get noMemory => isEnglish ? 'No memory' : '暂无记忆';
  String get noMemoryContentYet =>
      isEnglish ? 'No memory content yet' : '还没有任何记忆内容';
  String get projectContext => isEnglish ? 'Project Context' : '项目上下文';
  String get projectContextTitle => isEnglish ? 'Project Context' : '项目上下文';
  String get memoryNotesTitle => isEnglish ? 'My Notes' : '我的笔记';
  String get memoryUserTitle => isEnglish ? 'User Profile' : '用户画像';
  String get memorySoulTitle => isEnglish ? 'Agent Soul' : '智能体灵魂';
  String get memoryNotesEmpty => isEnglish ? 'No notes yet' : '暂无笔记';
  String get memoryUserEmpty => isEnglish ? 'No profile yet' : '暂无画像';
  String get memorySoulEmpty => isEnglish ? 'No soul settings yet' : '暂无灵魂设定';
  String get projectContextShadowedWarning => isEnglish
      ? 'Workspace local file is overriding the global project context.'
      : '工作区本地文件正在覆盖全局项目上下文。';
  String get memoryCharUnit => isEnglish ? 'chars' : '字';
  String get expandText => isEnglish ? 'Show More' : '展开全文';
  String get collapseText => isEnglish ? 'Show Less' : '收起';

  // Injected notice collapse (agent-injected-message-cards-spec §4)
  String get collapseInjectedNoticesLabel =>
      isEnglish ? 'Collapse system notices' : '折叠系统通知';
  String get collapseInjectedNoticesDescription => isEnglish
      ? 'Fold agent-injected notices (background processes, skills, cron, MCP) into compact cards'
      : '将后台进程/技能/定时任务/MCP 等系统通知折叠为紧凑卡片';
  String get injectedNoticeTitleBackgroundProcess =>
      isEnglish ? 'Background process' : '后台进程';
  String get injectedNoticeTitleSkill => isEnglish ? 'Skill' : '技能';
  String get injectedNoticeTitleCron => isEnglish ? 'Scheduled task' : '定时任务';
  String get injectedNoticeTitleMcp => isEnglish ? 'MCP' : 'MCP';
  String get injectedNoticeShowOutput => isEnglish ? 'Show output' : '展开';
  String get injectedNoticeHideOutput => isEnglish ? 'Hide output' : '收起';
  String get injectedNoticeExpand => injectedNoticeShowOutput;
  String get injectedNoticeCollapse => injectedNoticeHideOutput;

  // ---------------------------------------------------------------------------
  // 7. Workspace (Files)
  // ---------------------------------------------------------------------------
  String get workspace => isEnglish ? 'Workspace' : '工作区';
  String get files => isEnglish ? 'Files' : '文件';
  String get workspaceFilesTitle => isEnglish ? 'Workspace Files' : '工作区文件';
  String get refreshFileList => isEnglish ? 'Refresh file list' : '刷新文件列表';
  String get uploadFile => isEnglish ? 'Upload file' : '上传文件';
  String get location => isEnglish ? 'Location' : '位置';
  String get locationLabel => isEnglish ? 'Location' : '位置';
  String get rootDir => isEnglish ? 'Root' : '根目录';
  String get rootDirectory => isEnglish ? 'Root' : '根目录';
  String get parentDir => isEnglish ? 'Up' : '上一级';
  String get parentDirectory => isEnglish ? 'Up' : '上一级';
  String get noFiles => isEnglish ? 'No files' : '暂无文件';
  String get unnamedFile => isEnglish ? 'Unnamed' : '未命名';
  String get loadingIndicator => isEnglish ? 'Loading…' : '加载中…';
  String get download => isEnglish ? 'Download' : '下载';
  String get deleteFile => isEnglish ? 'Delete File' : '删除文件';
  String confirmDeleteFilePrompt(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"? This action cannot be undone.'
      : '确定要删除「$name」吗？此操作不可撤销。';
  String confirmDeleteFile(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"? This action cannot be undone.'
      : '确定要删除「$name」吗？此操作不可撤销。';
  String get filePickerNotAvailable =>
      isEnglish ? 'File picker not yet available' : '文件选择功能待接入';
  String get filePickerPendingPlatformSupport => isEnglish
      ? 'Selecting local files requires platform channel support (file picker), which will be available in a future version.'
      : '选择本地文件需要平台通道支持（file picker），将在后续版本提供。';
  String get filePickerNotAvailableDescription => isEnglish
      ? 'Selecting local files requires platform channel support (file picker), which will be available in a future version.'
      : '选择本地文件需要平台通道支持（file picker），将在后续版本提供。';
  String get fileActions => isEnglish ? 'File Actions' : '文件操作';
  String get manageWorkspaces => isEnglish ? 'Manage Workspaces' : '工作区管理';
  String get manageWorkspacesSubtitle => isEnglish
      ? 'Add, rename or remove workspaces, and browse their files'
      : '添加/重命名/移除工作区，并浏览其文件';
  String get workspacesTitle => isEnglish ? 'Workspaces' : '工作区';
  String get addWorkspace => isEnglish ? 'Add Workspace' : '添加工作区';
  String get addWorkspaceButton => isEnglish ? 'Add' : '添加';
  String get workspacePathLabel => isEnglish ? 'Path' : '路径';
  String get workspacePathHint => isEnglish
      ? 'Absolute path on disk, e.g. D:/projects/my-app'
      : '磁盘上的绝对路径，例如 D:/projects/my-app';
  String get workspaceNameOptionalLabel =>
      isEnglish ? 'Name (optional)' : '名称（可选）';
  String get workspaceNamePlaceholder => isEnglish ? 'Display name' : '显示名称';
  String get createDirectoryIfMissing =>
      isEnglish ? 'Create if missing' : '目录不存在时自动创建';
  String get renameWorkspaceTitle => isEnglish ? 'Rename Workspace' : '重命名工作区';
  String get removeWorkspaceTitle => isEnglish ? 'Remove Workspace' : '移除工作区';
  String confirmRemoveWorkspace(String name) => isEnglish
      ? 'Remove "$name" from the workspace list? Only the path is unregistered — no files on disk are deleted.'
      : '确定从列表移除「$name」吗？只注销路径，不会删除磁盘上的任何文件。';
  String get removeWorkspaceFooter => isEnglish
      ? 'Removing a workspace only unregisters its path from the server list. No files are deleted.'
      : '移除工作区只是从列表注销路径，不会删除磁盘上的文件。';
  String get noWorkspacesYet => isEnglish ? 'No workspaces yet' : '还没有工作区';
  String get addWorkspaceHint => isEnglish
      ? 'Tap + at the top right to add a workspace.'
      : '点右上角 + 添加工作区。';
  String get currentWorkspaceBadge => isEnglish ? 'Current' : '当前';
  String get browseWorkspaceFiles => isEnglish ? 'Browse files' : '浏览文件';
  String get noSessionForWorkspaceTitle =>
      isEnglish ? 'Cannot browse this workspace' : '无法浏览该工作区';
  String noSessionForWorkspaceBody(String path) => isEnglish
      ? 'No session is using this workspace ($path) yet. Open it from a session first, or create a new session.'
      : '当前没有会话使用该工作区（$path）。请先从会话进入该工作区的文件页，或新建会话后重试。';
  String get preview => isEnglish ? 'Preview' : '预览';
  String get previewUnavailable =>
      isEnglish ? 'Preview not available' : '无法预览该文件';
  String get previewUnavailableHint => isEnglish
      ? 'This file type is not supported for preview yet. Download it instead.'
      : '暂不支持预览该文件类型，请改用下载。';
  String get downloadFolderZip =>
      isEnglish ? 'Download folder as ZIP' : '打包下载当前目录';
  String get emptyFile => isEnglish ? '(empty file)' : '（空文件）';
  String get linesShort => isEnglish ? 'lines' : '行';
  String get previewTruncated =>
      isEnglish ? 'Truncated: file too large' : '已截断：文件过大';

  // ---------------------------------------------------------------------------
  // 8. Kanban
  // ---------------------------------------------------------------------------
  String get kanban => isEnglish ? 'Kanban' : '看板';
  String get kanbanTitle => isEnglish ? 'Kanban' : '看板';
  String get newCard => isEnglish ? 'New Card' : '新建卡片';
  String get unnamedBoard => isEnglish ? 'Untitled board' : '未命名看板';
  String get untitledBoard => isEnglish ? 'Untitled board' : '未命名看板';
  String get kanbanEmptyContent =>
      isEnglish ? 'Board has no content' : '看板暂无内容';
  String get boardEmpty => isEnglish ? 'Board has no content' : '看板暂无内容';
  String get clickPlusToCreateFirstCard => isEnglish
      ? 'Tap the + button at the top right to create the first card'
      : '点击右上角 + 创建第一张卡片';
  String get tapPlusToCreateFirstCard => isEnglish
      ? 'Tap the + button at the top right to create the first card'
      : '点击右上角 + 创建第一张卡片';
  String get noKanbanBoards => isEnglish ? 'No boards' : '暂无看板';
  String get noBoards => isEnglish ? 'No boards' : '暂无看板';
  String get createBoardOnServerPrompt => isEnglish
      ? 'Pull down to refresh after creating a board on the server'
      : '在服务器端创建看板后下拉刷新';
  String get noCards => isEnglish ? 'No cards' : '暂无卡片';
  String get unnamedCard => isEnglish ? 'Untitled card' : '未命名卡片';
  String get untitledCard => isEnglish ? 'Untitled card' : '未命名卡片';
  String get unassigned => isEnglish ? 'Unassigned' : '未指派';
  String parentsDependency(int count) =>
      isEnglish ? 'Parents $count' : '前驱 $count';
  String childrenDependency(int count) =>
      isEnglish ? 'Children $count' : '后继 $count';
  String parentsCount(int count) => isEnglish ? 'Parents $count' : '前驱 $count';
  String childrenCount(int count) =>
      isEnglish ? 'Children $count' : '后继 $count';
  String get cardDetail => isEnglish ? 'Card Detail' : '卡片详情';
  String get cardDoesNotExist => isEnglish ? 'Card does not exist' : '卡片不存在';
  String get cardNotFound => isEnglish ? 'Card not found' : '卡片不存在';
  String get statusLabel => isEnglish ? 'Status' : '状态';
  String get assigneeLabel => isEnglish ? 'Assignee' : '负责人';
  String get priorityLabel => isEnglish ? 'Priority' : '优先级';
  String get createdAtLabel => isEnglish ? 'Created at' : '创建时间';
  String get updatedAtLabel => isEnglish ? 'Updated at' : '更新时间';
  String get status => isEnglish ? 'Status' : '状态';
  String get assignee => isEnglish ? 'Assignee' : '负责人';
  String get priority => isEnglish ? 'Priority' : '优先级';
  String get createdAt => isEnglish ? 'Created at' : '创建时间';
  String get updatedAt => isEnglish ? 'Updated at' : '更新时间';
  String get changeStatus => isEnglish ? 'Change Status' : '变更状态';
  String commentsHeader(int count) =>
      isEnglish ? 'Comments ($count)' : '评论（$count）';
  String get noComments => isEnglish ? 'No comments' : '暂无评论';
  String get addCommentPlaceholder => isEnglish ? 'Add a comment…' : '添加评论…';
  String get sendComment => isEnglish ? 'Send comment' : '发送评论';
  String boardPrefix(String name) => isEnglish ? 'Board: $name' : '看板：$name';
  String get titleLabel => isEnglish ? 'Title' : '标题';
  String get title => isEnglish ? 'Title' : '标题';
  String get cardTitlePlaceholder => isEnglish ? 'Card title' : '卡片标题';
  String get cardDescriptionPlaceholder =>
      isEnglish ? 'Card description (optional)' : '卡片描述（可选）';
  String get assignProfilePlaceholder =>
      isEnglish ? 'Assign profile (optional)' : '指派 profile（可选）';
  String get initialStatus => isEnglish ? 'Initial Status' : '初始状态';
  String get kanbanStatusTriage => isEnglish ? 'Triage' : '待分类';
  String get kanbanStatusTodo => isEnglish ? 'To Do' : '待办';
  String get kanbanStatusReady => isEnglish ? 'Ready' : '就绪';
  String get kanbanStatusRunning => isEnglish ? 'Running' : '运行中';
  String get kanbanStatusBlocked => isEnglish ? 'Blocked' : '受阻';
  String get kanbanStatusDone => isEnglish ? 'Done' : '完成';
  String get kanbanStatusArchived => isEnglish ? 'Archived' : '已归档';
  String get kanbanStatusUnknown => isEnglish ? 'Unknown Status' : '未知状态';
  String kanbanStatusUnsupported(String? raw) =>
      isEnglish ? 'Unsupported: $raw' : '不支持: $raw';

  // ---------------------------------------------------------------------------
  // 9. Insights
  // ---------------------------------------------------------------------------
  String get insights => isEnglish ? 'Insights' : '统计';
  String get insightsTitle => isEnglish ? 'Usage Insights' : '用量统计';
  String get refreshInsights => isEnglish ? 'Refresh Usage Insights' : '刷新用量统计';
  String get timeframeToday => isEnglish ? 'Today' : '今天';
  String get timeframeLast7Days => isEnglish ? 'Last 7 Days' : '近 7 天';
  String get timeframeLast30Days => isEnglish ? 'Last 30 Days' : '近 30 天';
  String get timeframeAll => isEnglish ? 'All Time' : '全部';
  String recentDaysHeader(int days) =>
      isEnglish ? 'Last $days Days' : '最近 $days 天';
  String periodRecentDays(int days) =>
      isEnglish ? 'Last $days Days' : '最近 $days 天';
  String get metricSessions => isEnglish ? 'Sessions' : '会话';
  String get metricMessages => isEnglish ? 'Messages' : '消息';
  String get metricInputTokens => isEnglish ? 'Input Tokens' : '输入令牌';
  String get metricOutputTokens => isEnglish ? 'Output Tokens' : '输出令牌';
  String get metricTotalTokens => isEnglish ? 'Total Tokens' : '总令牌';
  String get metricEstimatedCost => isEnglish ? 'Estimated Cost' : '估算费用';
  String get metricCacheHitRate => isEnglish ? 'Cache Hit Rate' : '缓存命中率';
  String get metricCacheReadTokens =>
      isEnglish ? 'Cache Read Tokens' : '缓存读取令牌';
  String get models => isEnglish ? 'Models' : '模型';
  String get modelsSection => isEnglish ? 'Models' : '模型';
  String get tokensLast14Days =>
      isEnglish ? 'Tokens in Last 14 Days' : '近 14 天令牌';
  String get recent14DaysTokens =>
      isEnglish ? 'Tokens in Last 14 Days' : '近 14 天令牌';
  String get tokensTodayChartTitle => isEnglish ? 'Today\'s Tokens' : '今日令牌';
  String tokensDailyChartTitle(int days) =>
      isEnglish ? 'Tokens in Last $days Days' : '近 $days 天令牌';
  String get tokensAllTimeChartTitle => isEnglish ? 'All Tokens' : '全部令牌';
  String get activity => isEnglish ? 'Activity' : '活动';
  String get activitySection => isEnglish ? 'Activity' : '活动';
  String get mostActiveDay => isEnglish ? 'Most Active Day' : '最活跃的一天';
  String peakDaySessions(String day, int count) =>
      isEnglish ? '$day · $count sessions' : '$day · $count 个会话';
  String get mostActiveHour => isEnglish ? 'Peak Activity Hour' : '最活跃时段';
  String peakHourSessions(String hour, int count) =>
      isEnglish ? '$hour · $count sessions' : '$hour · $count 个会话';
  String insightsSourceFooter(int days) => isEnglish
      ? 'Source: Server statistics over the last $days days.'
      : '来源：服务器按最近 $days 天统计。';
  String insightsSourceDisclaimer(int days) => isEnglish
      ? 'Source: Server statistics over the last $days days.'
      : '来源：服务器按最近 $days 天统计。';
  String get noInsights => isEnglish ? 'No Statistics' : '暂无统计';
  String get insightsWillShowHere => isEnglish
      ? 'Usage data will appear here once you have conversations.'
      : '有对话后这里会显示用量数据。';
  String get unknownModel => isEnglish ? 'Unknown model' : '未知模型';
  String modelTokensSubtitle(String tokens) =>
      isEnglish ? '$tokens tokens' : '$tokens 令牌';

  // ---------------------------------------------------------------------------
  // 10. Git
  // ---------------------------------------------------------------------------
  String get git => isEnglish ? 'Git' : 'Git';
  String get gitPanel => isEnglish ? 'Git Panel' : 'Git 面板';
  String get gitPanelTitle => isEnglish ? 'Git Panel' : 'Git 面板';
  String get gitWorkspaceTitle => isEnglish ? 'Git Workspace' : 'Git 工作区';
  String get refreshGitStatus => isEnglish ? 'Refresh Git Status' : '刷新 Git 状态';
  String get notAGitRepo => isEnglish ? 'Not a Git Repository' : '不是 Git 仓库';
  String get notAGitRepoDetail => isEnglish
      ? 'This workspace is not a git repository and Git features cannot be used.'
      : '该工作区不是 git 仓库，无法使用 Git 功能。';
  String get notAGitRepository =>
      isEnglish ? 'Not a Git Repository' : '不是 Git 仓库';
  String get stagedSection => isEnglish ? 'Staged' : '已暂存';
  String get unstagedSection => isEnglish ? 'Unstaged' : '未暂存';
  String get tooManyChangedFilesWarning => isEnglish
      ? 'Too many changed files, displaying the first 500 only.'
      : '变更文件过多，仅显示前 500 个。';
  String get unknownBranch => isEnglish ? 'Unknown branch' : '未知分支';
  String aheadBehind(int ahead, int behind) =>
      isEnglish ? 'ahead $ahead · behind $behind' : '领先 $ahead · 落后 $behind';
  String aheadBehindStatus(int ahead, int behind) =>
      isEnglish ? 'ahead $ahead · behind $behind' : '领先 $ahead · 落后 $behind';
  String get syncedWithRemote => isEnglish ? 'In sync with remote' : '与远程同步';
  String get inSyncWithRemote => isEnglish ? 'In sync with remote' : '与远程同步';
  String get switchBranch => isEnglish ? 'Switch Branch' : '切换分支';
  String get branchTreeSection => isEnglish ? 'Branch Tree' : '分支树';
  String get localBranches => isEnglish ? 'Local' : '本地';
  String get remoteBranches => isEnglish ? 'Remote' : '远程';
  String get currentBranchBadge => isEnglish ? 'CURRENT' : '当前';
  String get checkoutBranchAction => isEnglish ? 'Switch' : '切换';
  String get noBranches => isEnglish ? 'No branches found' : '未找到分支';
  String get changesLabel => isEnglish ? 'Changes' : '变更';
  String get changes => isEnglish ? 'Changes' : '变更';
  String changesSummary(int additions, int deletions, int changed) => isEnglish
      ? '+$additions −$deletions · $changed files in total'
      : '+$additions −$deletions · 共 $changed 个文件';
  String get commitSection => isEnglish ? 'Commit' : '提交';
  String get commitButton => isEnglish ? 'Commit' : '提交';
  String get commitMessagePlaceholder => isEnglish ? 'Commit message' : '提交信息';
  String get remoteOperations => isEnglish ? 'Remote Operations' : '远程操作';
  String get stageAction => isEnglish ? 'Stage' : '暂存';
  String get unstageAction => isEnglish ? 'Unstage' : '取消暂存';
  String get discardChanges => isEnglish ? 'Discard Changes' : '放弃更改';
  String get gitChangeAdded => isEnglish ? 'Added' : '新增';
  String get gitChangeDeleted => isEnglish ? 'Deleted' : '删除';
  String get gitChangeRenamed => isEnglish ? 'Renamed' : '重命名';
  String get gitChangeConflict => isEnglish ? 'Conflict' : '冲突';
  String get gitChangeUntracked => isEnglish ? 'Untracked' : '未跟踪';
  String get gitChangeIgnored => isEnglish ? 'Ignored' : '忽略';
  String get gitChangeModified => isEnglish ? 'Modified' : '修改';
  String get cannotLoadDiff =>
      isEnglish ? 'Unable to load diff.' : '无法加载 diff。';
  String get binaryFileCannotShowDiff =>
      isEnglish ? 'Binary file, diff cannot be displayed.' : '二进制文件，无法显示 diff。';
  String get noDiffContent => isEnglish ? 'No diff content.' : '无 diff 内容。';
  String fileTooLargePartialContent(String partial) => isEnglish
      ? 'File is too large, showing partial content:\n$partial'
      : '文件过大，以下为部分内容：\n$partial';
  String get workspaceClean => isEnglish ? 'Workspace Clean' : '工作区干净';
  String get noPendingChanges =>
      isEnglish ? 'No changes to commit.' : '没有待提交的变更。';

  // ---------------------------------------------------------------------------
  // 11. Settings & Profile
  // ---------------------------------------------------------------------------
  String get settingsTitle => isEnglish ? 'Settings' : '设置';
  String get settings => isEnglish ? 'Settings' : '设置';
  String get appearanceSection => isEnglish ? 'Appearance' : '外观';
  String get appearance => isEnglish ? 'Appearance' : '外观';
  String get sessionListEntriesSection =>
      isEnglish ? 'Session List Entries' : '会话列表入口';
  // #154：侧栏导航入口的「位置 + 顺序」设置组。
  String get sidebarNavOrderSection =>
      isEnglish ? 'Sidebar Navigation' : '侧栏导航入口';
  // #159：会话列表分组方式（自动 / 按时间 / 按工作区）。
  String get sessionGroupingSection =>
      isEnglish ? 'Session Grouping' : '会话分组方式';
  String get sessionGroupingDescription => isEnglish
      ? 'Narrow screens default to time (Today / Yesterday / Earlier); wide screens to workspace.'
      : '窄屏默认按时间（今天/昨天/更早），桌面默认按工作区。';
  String get sessionGroupingAuto => isEnglish ? 'By screen' : '跟随屏幕';

  /// #161：品牌行副标题里的会话数量（如「hermes-ui · 6 个会话」）。
  String sessionsCountLabel(int count) =>
      isEnglish ? '$count sessions' : '$count 个会话';

  /// #161：无工作区会话的收纳分组（原名「其他」语义模糊）。
  String get ungroupedSection => isEnglish ? 'Ungrouped' : '未分组';
  String get sessionGroupingTime => isEnglish ? 'By time' : '按时间';
  String get sessionGroupingWorkspace => isEnglish ? 'By workspace' : '按工作区';
  String get sidebarNavOrderSectionFooter => isEnglish
      ? 'Choose where each entry appears in the wide-screen sidebar and reorder it.'
      : '宽屏侧栏中，各入口显示的位置与顺序。';
  String get sidebarNavOrderTopLabel => isEnglish ? 'At the top' : '侧栏最上方';
  String get sidebarNavOrderBottomLabel => isEnglish ? 'Bottom right' : '侧栏右下角';
  String get sidebarNavOrderReset => isEnglish ? 'Restore defaults' : '恢复默认';
  String get sidebarNavOrderMoveToTop =>
      isEnglish ? 'Move to top area' : '移到上方';
  String get sidebarNavOrderMoveToBottom =>
      isEnglish ? 'Move to bottom area' : '移到右下';
  String get sidebarNavOrderMoveUp => isEnglish ? 'Move up' : '上移';
  String get sidebarNavOrderMoveDown => isEnglish ? 'Move down' : '下移';
  String get sidebarNavOrderEmptyHint => isEnglish
      ? 'No entries here — move some down from the top area.'
      : '此区暂无入口，可从上方移一些过来。';
  String get sessionListEntries =>
      isEnglish ? 'Session List Entries' : '会话列表入口';
  String get sessionRowSubtitleSection =>
      isEnglish ? 'Session Row Details' : '会话行信息';
  String get sessionRowShowMessageCount => isEnglish ? 'Message count' : '消息数';
  String get sessionRowShowProjectName => isEnglish ? 'Project name' : '项目名';
  String get sessionRowShowWorkspace => isEnglish ? 'Workspace' : '工作区';
  String get sessionRowShowChannel => isEnglish ? 'Channel' : '渠道';
  String get sessionRowShowEstimatedCost =>
      isEnglish ? 'Estimated cost' : '预估价钱';
  String get themeLabel => isEnglish ? 'Theme' : '主题';
  String get theme => isEnglish ? 'Theme' : '主题';
  String get themeSystem => isEnglish ? 'System' : '跟随系统';
  String get themeLight => isEnglish ? 'Light' : '浅色';
  String get themeDark => isEnglish ? 'Dark' : '深色';
  // 高对比度模式（#140 P2-b：把 P2-b 做成开关，默认关 = 零行为变更）
  String get forceHighContrastLabel => isEnglish ? 'High contrast' : '高对比度模式';
  String get forceHighContrastDescription => isEnglish
      ? 'Use stronger colour variants even when the system setting is off'
      : '即使系统未开启辅助功能高对比度，也使用对比度更强的颜色变体';
  String get chatSection => isEnglish ? 'Chat' : '对话';
  String get groupToolsByTurn => isEnglish ? 'Group tools by turn' : '工具按回合聚合';
  String get smoothStreaming => isEnglish ? 'Smooth Streaming' : '平滑输出';
  String get smoothStreamingDesc => isEnglish
      ? 'Smooth typewriter output with adaptive speed during backlog'
      : '逐字平滑输出，积压时自适应加速';
  String get smoothStreamingSpeed => isEnglish ? 'Typing Speed' : '打字机速度';
  String get smoothStreamingSpeedDesc =>
      isEnglish ? 'Speed preset for typewriter streaming' : '调节流式消息的吐字速度与平滑节奏';
  String get smoothStreamingSpeedCharByChar =>
      isEnglish ? 'Per Character' : '逐字';
  String get smoothStreamingSpeedSlow => isEnglish ? 'Slow' : '慢';
  String get smoothStreamingSpeedStandard => isEnglish ? 'Standard' : '标准';
  String get smoothStreamingSpeedFast => isEnglish ? 'Fast' : '快';
  String get smoothStreamingSpeedVeryFast => isEnglish ? 'Very Fast' : '极快';
  String get composerTwoPane => isEnglish ? 'Two-pane input bar' : '两段式输入栏';
  String get composerTwoPaneDesc => isEnglish
      ? 'Multi-line text area with a separate tool row below'
      : '多行文本区与独立工具行的输入栏布局（关闭为经典单行）';
  String get perfMonitor => isEnglish ? 'Performance Monitor' : '性能监控';
  String get perfMonitorDesc => isEnglish
      ? 'Show CPU & memory in the tool row (two-pane only)'
      : '在工具行显示 CPU/内存占用（仅两段式可见）';
  String get perfMonitorCpu => isEnglish ? 'CPU' : 'CPU';
  String get perfMonitorMem => isEnglish ? 'MEM' : 'MEM';
  String get perfMonitorDisk => isEnglish ? 'DISK' : 'DISK';
  String get groupToolsByTurnDesc => isEnglish
      ? 'On: all tools of a turn collapse into one card. Off: only adjacent tools merge; text/thinking breaks them apart'
      : '开启：整轮工具合成一张折叠卡；关闭：仅相邻工具合并，被文本/思考打断则分离';
  String get groupThinkByTurn =>
      isEnglish ? 'Group thinking by turn' : '思考按回合聚合';
  String get groupThinkByTurnDesc => isEnglish
      ? 'On: all thinking of a turn collapses into one card. Off: only adjacent thinking merges; text/tools break it apart'
      : '开启：整轮思考合成一张折叠卡；关闭：仅相邻思考合并，被文本/工具打断则分离';
  String get hideThinking => isEnglish ? 'Hide thinking' : '隐藏思考';
  String get hideThinkingDesc => isEnglish
      ? 'Hide thinking cards entirely, leaving text and tool cards only'
      : '完全隐藏思考卡片，仅保留文本与工具卡片';
  String get sendMessageShortcutLabel => isEnglish ? 'Send Message' : '发送消息';
  String get sendShortcutEnter => isEnglish ? 'Enter to send' : 'Enter 发送';
  String get sendShortcutCtrlEnter =>
      isEnglish ? 'Ctrl+Enter to send' : 'Ctrl+Enter 发送';
  String get desktopSection => isEnglish ? 'Desktop' : '桌面';
  String get desktop => isEnglish ? 'Desktop' : '桌面';
  String get minimizeToTray => isEnglish ? 'Minimize to Tray' : '最小化到托盘';
  String get minimizeToTraySubtitle => isEnglish
      ? 'Hide to tray instead of quitting when closing window'
      : '关闭窗口时隐藏到托盘而非退出';
  String get globalShortcuts => isEnglish ? 'Global Shortcuts' : '全局快捷键';
  String get globalShortcutsSubtitle => isEnglish
      ? 'Ctrl+Shift+H show window, Ctrl+Shift+N new session'
      : 'Ctrl+Shift+H 唤起主窗口，Ctrl+Shift+N 新建会话';
  String get rememberWindowPosition =>
      isEnglish ? 'Remember Window Position' : '记住窗口位置';
  String get rememberWindowPositionSubtitle => isEnglish
      ? 'Restore window size and position on startup'
      : '启动时恢复上次窗口位置与尺寸';
  String get startOnLogin => isEnglish ? 'Start on Login' : '开机启动';
  String get startOnLoginSubtitle => isEnglish
      ? 'Launch Hermes automatically when you sign in to Windows'
      : '登录 Windows 时自动启动 Hermes';
  String get silentStart => isEnglish ? 'Silent Start' : '静默启动';
  String get silentStartSubtitle => isEnglish
      ? 'Start in the system tray without showing the main window'
      : '启动时不显示主窗口，直接驻留系统托盘';
  String get serverSection => isEnglish ? 'Servers' : '服务器';
  String get serverSectionDisconnected =>
      isEnglish ? 'Servers (Not Connected)' : '服务器（未连接）';
  String get noServerConfigured =>
      isEnglish ? 'No servers configured' : '尚未配置服务器';
  String get noServerConfiguredSubtitle => isEnglish
      ? 'Click "Add Server" below or configure from onboarding'
      : '点击下方「添加服务器」或从引导页配置';
  String get addServer => isEnglish ? 'Add Server' : '添加服务器';
  String get editServer => isEnglish ? 'Edit Server' : '编辑服务器';
  String get deleteServer => isEnglish ? 'Delete Server' : '删除服务器';
  String confirmDeleteServer(String name) =>
      isEnglish ? 'Are you sure you want to delete "$name"?' : '确定删除「$name」吗？';
  String get builtinWebuiName => isEnglish ? 'Built-in WebUI' : '内置 WebUI';
  String get disableConnection => isEnglish ? 'Disable' : '停用';
  String get enableConnection => isEnglish ? 'Enable' : '启用';
  String get serverNamePlaceholder =>
      isEnglish ? 'Name (optional, defaults to host)' : '名称（可选，默认使用主机名）';
  String get serverNameOptionalPlaceholder =>
      isEnglish ? 'Name (optional, defaults to host)' : '名称（可选，默认使用主机名）';
  String get advancedSettings => isEnglish ? 'Advanced Settings' : '高级设置';
  String get advancedSettingsSection =>
      isEnglish ? 'Advanced Settings' : '高级设置';
  String get serverBasicInfoSection => isEnglish ? 'Basic Information' : '基本信息';
  String get serverNameLabel => isEnglish ? 'Name' : '名称';
  String get serverUrlLabel => isEnglish ? 'Address' : '地址';
  String get serverPasswordLabel => isEnglish ? 'Password' : '密码';
  String get serverUrlExampleHint => isEnglish
      ? 'e.g. https://hermes.example.com:8787'
      : '例如 https://hermes.example.com:8787';
  String get serverPasswordPlaceholder => isEnglish
      ? 'Password (optional; leave blank to keep existing)'
      : '密码（可选；编辑时留空保持原密码）';
  String get serverPasswordOptionalPlaceholder => isEnglish
      ? 'Password (optional; leave blank to keep existing)'
      : '密码（可选；编辑时留空保持原密码）';
  String get loadingModels => isEnglish ? 'Loading models…' : '正在加载模型…';
  String get modelsLoadFailed => isEnglish ? 'Failed to load models' : '模型加载失败';
  String get defaultModel => isEnglish ? 'Default Model' : '默认模型';
  String get refreshModels => isEnglish ? 'Refresh Models' : '刷新模型列表';
  String get refreshFailed => isEnglish ? 'Refresh Failed' : '刷新失败';
  String get notSet => isEnglish ? 'Not set' : '未设置';
  String get reasoningEffort => isEnglish ? 'Reasoning Effort' : '推理强度';
  String get noAvailableModels => isEnglish ? 'No models available' : '暂无可用模型';
  String get noModelsAvailable => isEnglish ? 'No models available' : '暂无可用模型';
  String get aboutSection => isEnglish ? 'About' : '关于';
  String get about => isEnglish ? 'About' : '关于';
  String get hermesWebUIClient =>
      isEnglish ? 'Hermes WebUI Client' : 'Hermes WebUI 客户端';
  String get hermesWebUiClient =>
      isEnglish ? 'Hermes WebUI Client' : 'Hermes WebUI 客户端';
  String get version => isEnglish ? 'Version' : '版本';
  String get profile => isEnglish ? 'Profile' : 'Profile';
  String get notRead => isEnglish ? 'Not loaded' : '未读取';
  String get notLoaded => isEnglish ? 'Not loaded' : '未读取';
  String get readFailed => isEnglish ? 'Read Failed' : '读取失败';
  String get clickToRetry => isEnglish ? 'Click to retry' : '点击重试';
  String get selectProfile => isEnglish ? 'Select Profile' : '选择 Profile';
  String get profileSwitchFailed =>
      isEnglish ? 'Profile Switch Failed' : 'Profile 切换失败';

  // ---------------------------------------------------------------------------
  // 12. Projects
  // ---------------------------------------------------------------------------
  String get noProject => isEnglish ? 'No Project' : '无项目';
  String get unnamedProject => isEnglish ? 'Untitled project' : '未命名项目';
  String get newProject => isEnglish ? 'New Project' : '新建项目';
  String get newProjectEllipsis => isEnglish ? 'New Project…' : '新建项目…';
  String get projectNamePlaceholder => isEnglish ? 'Project name' : '项目名称';
  String get projectManagement => isEnglish ? 'Project Management' : '项目管理';
  String get renameProject => isEnglish ? 'Rename Project' : '重命名项目';
  String get deleteProject => isEnglish ? 'Delete Project' : '删除项目';
  String get deleteProjectDescription => isEnglish
      ? 'Sessions in the project will not be deleted, only unassigned.'
      : '删除后项目内会话不会被删除，仅解除归类。';
  String get deleteProjectWarning => isEnglish
      ? 'Sessions in the project will not be deleted, only unassigned.'
      : '删除后项目内会话不会被删除，仅解除归类。';

  // ---------------------------------------------------------------------------
  // 13. Saved Prompts
  // ---------------------------------------------------------------------------
  String get savedPrompts => isEnglish ? 'Saved Prompts' : '收藏提示词';
  String get savedPromptsTitle => isEnglish ? 'Saved Prompts' : '收藏提示词';
  String get savedPromptsEmpty =>
      isEnglish ? 'No saved prompts yet.' : '暂无收藏提示词';
  String get savedPromptsDelete => isEnglish ? 'Delete' : '删除';
  String get savedPromptsSaveCurrent =>
      isEnglish ? 'Save current input' : '收藏当前输入';
  String get saveCurrentInput => isEnglish ? 'Save current input' : '收藏当前输入';
  String get savedPromptsEmptyInput =>
      isEnglish ? 'Type a prompt first' : '请先输入提示词';
  String get bookmarkPrompt => isEnglish ? 'Saved prompts' : '收藏提示词';
  String get promptSaved => isEnglish ? 'Prompt saved' : '已收藏';
  String get promptDeleted => isEnglish ? 'Prompt deleted' : '已删除';
  String get savePromptFailed => isEnglish ? 'Failed to save prompt' : '收藏失败';
  String get deletePromptFailed =>
      isEnglish ? 'Failed to delete prompt' : '删除失败';

  // ---------------------------------------------------------------------------
  // 14. Settings · Extensions/MCP/Auxiliary
  // ---------------------------------------------------------------------------
  String get extensionsSection => isEnglish ? 'Extensions' : '扩展';
  String get extensionsTitle => isEnglish ? 'Extensions' : '扩展';
  String get installedExtensions =>
      isEnglish ? 'Installed Extensions' : '已安装扩展';
  String get noExtensions => isEnglish ? 'No extensions installed' : '暂无已安装扩展';
  String get installExtension => isEnglish ? 'Install Extension' : '安装扩展';
  String get extensionId => isEnglish ? 'Extension ID' : '扩展 ID';
  String get extensionDownloadUrl => isEnglish ? 'Download URL' : '下载地址';
  String get extensionSha256 => isEnglish ? 'SHA256 Checksum' : 'SHA256 校验和';
  String get extensionSidecarConsent =>
      isEnglish ? 'Sidecar Proxy Consent' : 'Sidecar 代理授权';
  String get extensionSidecarActive =>
      isEnglish ? 'Sidecar Active' : 'Sidecar 运行中';
  String get extensionSidecarInactive =>
      isEnglish ? 'Sidecar Inactive' : 'Sidecar 未运行';
  String get uninstall => isEnglish ? 'Uninstall' : '卸载';
  String get uninstallExtension => isEnglish ? 'Uninstall Extension' : '卸载扩展';
  String confirmUninstallExtension(String name) => isEnglish
      ? 'Are you sure you want to uninstall "$name"?'
      : '确定卸载「$name」扩展吗？';
  String get extensionDetails => isEnglish ? 'Extension Details' : '扩展详情';
  String get extensionRegistry => isEnglish ? 'Extension Registry' : '扩展源';
  String get selectFromRegistry =>
      isEnglish ? 'Select from Registry' : '从扩展源选择';
  String get loadingExtensions => isEnglish ? 'Loading extensions…' : '正在加载扩展…';
  String get extensionsLoadFailed =>
      isEnglish ? 'Failed to load extensions' : '扩展加载失败';

  String get mcpSection => isEnglish ? 'MCP Servers' : 'MCP 服务器';
  String get mcpServersTitle => isEnglish ? 'MCP Servers' : 'MCP 服务器';
  String get noMcpServers =>
      isEnglish ? 'No MCP servers configured' : '暂无已配置的 MCP 服务器';
  String get addMcpServer => isEnglish ? 'Add MCP Server' : '添加 MCP 服务器';
  String get editMcpServer => isEnglish ? 'Edit MCP Server' : '编辑 MCP 服务器';
  String get deleteMcpServer => isEnglish ? 'Delete MCP Server' : '删除 MCP 服务器';
  String confirmDeleteMcpServer(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"?'
      : '确定删除 MCP 服务器「$name」吗？';
  String get mcpServerName => isEnglish ? 'Server Name' : '服务器名称';
  String get mcpCommand => isEnglish ? 'Command' : '执行命令';
  String get mcpArgs => isEnglish ? 'Arguments' : '参数';
  String get mcpArgsPlaceholder =>
      isEnglish ? 'Arguments (one per line or space separated)' : '命令参数（每行一个）';
  String get mcpEnv =>
      isEnglish ? 'Environment Variables (JSON)' : '环境变量（JSON）';
  String get mcpServerEnabled => isEnglish ? 'Enabled' : '启用';
  String get mcpTools => isEnglish ? 'MCP Tools' : 'MCP 工具';
  String mcpToolsCount(int count) => isEnglish ? '$count tools' : '$count 个工具';
  String get viewMcpTools => isEnglish ? 'View Tools' : '查看工具';
  String get noMcpTools => isEnglish ? 'No tools available' : '暂无可用的 MCP 工具';
  String get mcpStatusConnected => isEnglish ? 'Connected' : '已连接';
  String get mcpStatusDisconnected => isEnglish ? 'Disconnected' : '未连接';
  String get mcpServerDetails => isEnglish ? 'MCP Server Details' : 'MCP 服务器详情';
  String get loadingMcpServers =>
      isEnglish ? 'Loading MCP servers…' : '正在加载 MCP 服务器…';
  String get mcpServersLoadFailed =>
      isEnglish ? 'Failed to load MCP servers' : 'MCP 服务器加载失败';
  String get mcpServerNameRequired =>
      isEnglish ? 'Server name is required' : '请输入服务器名称';
  String get mcpCommandRequired =>
      isEnglish ? 'Command is required' : '请输入执行命令';
  String get mcpEnvInvalidJson =>
      isEnglish ? 'Environment must be valid JSON' : '环境变量必须是合法的 JSON 对象';

  String get auxiliaryModelsSection => isEnglish ? 'Auxiliary Models' : '辅助模型';
  String get auxiliaryModelsTitle => isEnglish ? 'Auxiliary Models' : '辅助模型';
  String get resetAuxiliary => isEnglish ? 'Reset All to Auto' : '全部重置为自动';
  String get confirmResetAuxiliary => isEnglish
      ? 'Reset all auxiliary model tasks to automatic?'
      : '确定将所有辅助模型任务重置为自动吗？';
  String get auto => isEnglish ? 'Auto' : '自动';
  String get apiKeyConfigured =>
      isEnglish ? 'API Key Configured' : '已配置 API Key';
  String get apiKeyNotConfigured => isEnglish ? 'No API Key' : '未配置 API Key';
  String get auxTaskPickerTitle =>
      isEnglish ? 'Select Auxiliary Model' : '选择辅助模型';
  String get auxMainModel => isEnglish ? 'Main Model' : '主模型';
  String get auxTasks => isEnglish ? 'Task Bindings' : '任务绑定';
  String get loadingAuxiliaryModels =>
      isEnglish ? 'Loading auxiliary models…' : '正在加载辅助模型…';
  String get auxiliaryModelsLoadFailed =>
      isEnglish ? 'Failed to load auxiliary models' : '辅助模型加载失败';

  // Malformed event friendly prefix (sse_client 525)
  String get connectionErrorPrefix => isEnglish ? 'Connection error:' : '连接异常：';
  String connectionErrorWithDetail(String detail) =>
      '$connectionErrorPrefix $detail';
  // ---------------------------------------------------------------------------
  // 15. Diagnostics & Debugging
  // ---------------------------------------------------------------------------
  String get diagnostics => isEnglish ? 'Diagnostics' : '调试/诊断';
  String get diagnosticsTitle => isEnglish ? 'Diagnostics' : '调试/诊断';
  String get diagnosticsSection => isEnglish ? 'Diagnostics' : '调试/诊断';
  String get diagnosticsEnabled => isEnglish ? 'Debug Mode' : '调试模式';
  String get diagnosticsEnabledDesc => isEnglish
      ? 'Collect network requests, SSE events, and system errors when enabled'
      : '开启后采集网络请求、SSE 事件及系统错误日志';
  String get diagnosticsEmptyDisabled =>
      isEnglish ? 'Enable debug mode to start recording logs' : '打开调试模式后开始记录';
  String get diagnosticsEmptyNoLogs =>
      isEnglish ? 'No logs recorded' : '暂无日志记录';
  String get diagnosticsEmptyNoMatch =>
      isEnglish ? 'No matching logs' : '无匹配的日志';
  String get diagnosticsTimeRangeAll => isEnglish ? 'All' : '全部';
  String get diagnosticsTimeRangeToday => isEnglish ? 'Today' : '今天';
  String get diagnosticsTimeRangeLast7Days =>
      isEnglish ? 'Last 7 Days' : '近 7 天';
  String get diagnosticsTimeRangeCustom => isEnglish ? 'Custom' : '自定义';
  String get diagnosticsSearchPlaceholder => isEnglish
      ? 'Search timestamp, level, tag, message, details…'
      : '搜索时间、级别、Tag、内容或详情…';
  String get diagnosticsCopySingle => isEnglish ? 'Copy Log' : '复制日志';
  String get diagnosticsCopySelected => isEnglish ? 'Copy Selected' : '复制选中';
  String get diagnosticsClear => isEnglish ? 'Clear Logs' : '清空日志';
  String get diagnosticsConfirmClear => isEnglish
      ? 'Are you sure you want to clear all diagnostic logs?'
      : '确定要清空所有诊断日志吗？';
  String get diagnosticsExport => isEnglish ? 'Export' : '导出';
  String get diagnosticsExportSuccess => isEnglish
      ? 'Diagnostic logs exported and copied to clipboard'
      : '诊断日志已导出并复制到剪贴板';
  String diagnosticsExportTooLargeSaved(String path) => isEnglish
      ? 'Content too large, saved to file: $path'
      : '内容过大已保存到文件：$path';
  String get diagnosticsSelectMode => isEnglish ? 'Select' : '多选';
  String get diagnosticsExitSelectMode => isEnglish ? 'Done' : '完成';
  String diagnosticsSelectedCount(int count) =>
      isEnglish ? '$count selected' : '已选择 $count 条';
  String get diagnosticsDetailsTitle => isEnglish ? 'Log Details' : '日志详情';

  String get bgKeepalivePersistentHint => isEnglish
      ? 'When enabled, an ongoing notification displays the number of active sessions'
      : '开启后常驻通知显示进行中会话数';
  String get bgKeepaliveNoActiveSessions =>
      isEnglish ? 'No active sessions' : '暂无进行中会话';
  String bgKeepaliveActiveCount(int count) => count > 0
      ? (isEnglish
            ? '$count session${count == 1 ? '' : 's'} generating'
            : '$count 个会话正在生成')
      : (isEnglish ? 'No active sessions' : '暂无进行中会话');

  String get chatStatusConnecting => isEnglish ? 'Connecting' : '连接中';
  String get chatStatusWaitingResponse =>
      isEnglish ? 'Waiting for model response' : '等待模型响应';
  String get chatStatusGenerating => isEnglish ? 'Generating' : '生成中';
  String get chatStatusInvestigating =>
      isEnglish ? 'Connection anomaly, investigating' : '连接异常，排查中';
  String get chatStatusReconnecting => isEnglish ? 'Reconnecting' : '正在重新连接';
  String get chatStatusReconnected => isEnglish ? 'Reconnected' : '已重连';
  String get chatStatusContextUnavailable =>
      isEnglish ? 'Context unavailable' : '上下文不可用';
  String get chatStatusLine => isEnglish ? 'Chat Status Line' : '聊天状态指示';
  String get chatStatusLineDesc => isEnglish
      ? 'Show real-time status at the bottom of chat message list'
      : '在聊天消息列表底部显示实时连接与生成状态';

  /// 状态行耗时后缀（意见3）：如「已工作 01:05」。
  String chatStatusWorkingFor(String elapsed) =>
      isEnglish ? 'Working for $elapsed' : '已工作 $elapsed';

  // ---------------------------------------------------------------------------
  // 13. Install Guide (Windows Local Deployment)
  // ---------------------------------------------------------------------------
  String get installGuideTitle =>
      isEnglish ? 'Windows Local Deployment Guide' : 'Windows 本机部署向导';
  String get installGuideSubtitle => isEnglish
      ? 'One-click pull, configure, and deploy Hermes Agent & WebUI'
      : '一键拉取、配置与部署 Hermes Agent 和 WebUI';
  String get installGuideLocalDeploy => isEnglish ? 'Local Deployment' : '本机部署';
  String get installGuideLocalDeployDesc => isEnglish
      ? 'Install Hermes Agent & WebUI locally on Windows'
      : '在 Windows 本机一键安装并部署 Hermes';
  String get installGuideStagePrereqs =>
      isEnglish ? 'Environment Check' : '环境检查';
  String get installGuideStagePrereqsDesc => isEnglish
      ? 'Check Python, Git, and PowerShell requirements'
      : '检查 Python、Git 及 PowerShell 环境';
  String get installGuideStageAgent => isEnglish ? 'Pull Agent' : '拉取 Agent';
  String get installGuideStageAgentDesc => isEnglish
      ? 'Download and install Hermes Agent via install.ps1'
      : '下载并通过 install.ps1 安装 Hermes Agent';
  String get installGuideStageDeps =>
      isEnglish ? 'Install Dependencies' : '安装依赖';
  String get installGuideStageDepsDesc => isEnglish
      ? 'Set up Python virtual environment and dependencies'
      : '配置 Python 虚拟环境并安装核心依赖';
  String get installGuideStageModel => isEnglish ? 'Configure Model' : '配置模型';
  String get installGuideStageModelDesc =>
      isEnglish ? 'Set up LLM provider and API key' : '选择大模型服务商并配置 API Key';
  String get installGuideStatusPending => isEnglish ? 'Pending' : '等待中';
  String get installGuideStatusRunning => isEnglish ? 'Running' : '执行中';
  String get installGuideStatusSuccess => isEnglish ? 'Completed' : '已完成';
  String get installGuideStatusFailed => isEnglish ? 'Failed' : '执行失败';
  String get installGuideStartInstall =>
      isEnglish ? 'Start One-Click Install' : '开始一键安装';
  String get installGuideInstalling => isEnglish ? 'Installing...' : '正在安装...';
  String get installGuideRetry => isEnglish ? 'Retry' : '重试';
  String get installGuideRetryStage =>
      isEnglish ? 'Retry Failed Step' : '重试当前步骤';
  String get installGuideCompleted =>
      isEnglish ? 'Installation Completed!' : '安装配置完成！';
  String get installGuideEnterChat => isEnglish ? 'Enter Chat' : '进入聊天';
  String get installGuideLogs => isEnglish ? 'Installation Logs' : '安装日志';
  String get installGuideShowLogs => isEnglish ? 'Show Logs' : '展开日志';
  String get installGuideHideLogs => isEnglish ? 'Hide Logs' : '收起日志';
  String get installGuideCopyLogs => isEnglish ? 'Copy Logs' : '复制日志';
  String get installGuideLogsCopied =>
      isEnglish ? 'Logs copied to clipboard' : '日志已复制到剪贴板';
  String get installGuideSelectProvider =>
      isEnglish ? 'Select Provider' : '选择模型服务商';
  String get installGuideApiKey => isEnglish ? 'API Key' : 'API Key';
  String get installGuideApiKeyHint =>
      isEnglish ? 'Enter your API key' : '请输入 API Key';
  String get installGuideBaseUrl =>
      isEnglish ? 'Base URL (Optional)' : 'API 地址（选填）';
  String get installGuideBaseUrlHint => isEnglish
      ? 'e.g. https://api.example.com/v1'
      : '例如 https://api.example.com/v1';
  String get installGuideModelName =>
      isEnglish ? 'Model Name (Optional)' : '模型名称（选填）';
  String get installGuideModelNameHint => isEnglish
      ? 'e.g. claude-3-5-sonnet-20241022'
      : '例如 claude-3-5-sonnet-20241022';
  String get installGuideSaveAndContinue =>
      isEnglish ? 'Save & Start Using' : '保存并开始使用';
  String get installGuideSaving => isEnglish ? 'Saving...' : '正在保存配置...';
  String get installGuideSkipModelConfig =>
      isEnglish ? 'Skip for now' : '暂不配置，稍后设置';
  String get installGuideWindowsOnly => isEnglish
      ? 'Local deployment guide is only supported on Windows'
      : '本机部署向导仅支持 Windows 系统';
  String get installGuideBackToConnect =>
      isEnglish ? 'Back to Remote Connection' : '返回远程连接';
  String get installGuideDownloadScriptFailed => isEnglish
      ? 'Failed to download install.ps1. Please check network connection.'
      : '下载 install.ps1 失败，请检查网络连接';
  String get installGuideProviderRequired =>
      isEnglish ? 'Please select a provider' : '请选择模型服务商';
  String get installGuideApiKeyRequired =>
      isEnglish ? 'API Key is required for this provider' : '该服务商需要填写 API Key';
  String get autoOpenContextTitle =>
      isEnglish ? 'Auto-open context on new session' : '新建会话自动打开上下文';
  String get autoOpenContextDesc => isEnglish
      ? 'Open the context panel automatically when creating a new session to set workspace and model'
      : '新建会话时自动打开上下文面板，便于设置工作区和模型';
  String get onboardingBrandSlogan =>
      isEnglish ? 'Your self-hosted AI companion' : '随时随地的自建 AI 智能体助手';

  // ---------------------------------------------------------------------------
  // Built-in WebUI Sidecar
  // ---------------------------------------------------------------------------
  String get webuiSectionTitle => isEnglish ? 'Built-in WebUI' : '内置 WebUI 服务';
  String get webuiBundleMissingHint =>
      isEnglish ? 'Built-in WebUI bundle not found' : '未检测到内置 WebUI 包';
  String get webuiEnableTitle =>
      isEnglish ? 'Enable Built-in Service' : '启用内置服务';
  String get webuiEnableSubtitle => isEnglish
      ? 'Run Hermes WebUI in background with the app'
      : '随应用启动并在后台运行 Hermes WebUI';
  String get webuiListeningHost => isEnglish ? 'Listening IP' : '监听 IP';
  String get webuiListeningPort => isEnglish ? 'Listening Port' : '监听端口';
  String get webuiInvalidHost =>
      isEnglish ? 'Please enter a valid IPv4 address' : '请输入合法的 IPv4 地址';
  String get webuiInvalidPort =>
      isEnglish ? 'Port must be between 1 and 65535' : '端口号必须在 1-65535 之间';
  String get webuiPassword => isEnglish ? 'WebUI Password' : 'WebUI 密码';
  String get webuiPasswordEmpty =>
      isEnglish ? 'Password cannot be empty' : '密码不能为空';
  String get webuiPasswordPlaceholder => isEnglish ? 'Enter password' : '输入密码';
  String get webuiStatusTitle => isEnglish ? 'Service Status' : '服务状态';
  String get webuiStatusRunning => isEnglish ? 'Running' : '运行中';
  String get webuiStatusStarting => isEnglish ? 'Starting…' : '启动中…';
  String get webuiStatusStopped => isEnglish ? 'Stopped' : '已停止';
  String get webuiStatusFailed => isEnglish ? 'Failed' : '启动失败';
  String get webuiFailurePortOccupied => isEnglish ? 'Port occupied' : '端口占用';
  String get webuiFailureMissingBundle =>
      isEnglish ? 'Missing built-in bundle' : '缺内置包';
  String get webuiFailureHealthTimeout =>
      isEnglish ? 'Health check timed out' : '健康超时';
  String get webuiFailureStartFailed => isEnglish ? 'Failed to start' : '启动失败';
  String get webuiOpenLogs => isEnglish ? 'Open Log Directory' : '打开日志目录';

  // Keepalive error messages (keepalive* prefix)
  String get keepaliveStartFailed =>
      isEnglish ? 'Failed to start keepalive service' : '前台保活服务启动失败';
  String keepaliveStartFailedWithReason(String reason) => isEnglish
      ? 'Failed to start keepalive service: $reason'
      : '前台保活服务启动失败：$reason';
  String get keepaliveNotInitialized =>
      isEnglish ? 'Keepalive service not initialized' : '保活服务未完成初始化';
  String get keepalivePermissionRequired => isEnglish
      ? 'Notification permission is required for keepalive service'
      : '前台保活服务需要通知权限';

  // ---------------------------------------------------------------------------
  // Onboarding U2 Built-in Tab and Segmentation (onboarding* prefix)
  // ---------------------------------------------------------------------------
  String get onboardingTabBuiltin => isEnglish ? 'Built-in Service' : '内置服务';
  String get onboardingTabRemote => isEnglish ? 'Connect Server' : '连接服务器';
  String get onboardingBuiltinTitle =>
      isEnglish ? 'Hermes Built-in Service' : 'Hermes 内置服务';
  String get onboardingBuiltinSubtitle => isEnglish
      ? 'Built-in Hermes WebUI service, ready with one click'
      : '应用随附的本地 Hermes WebUI 服务，一键启动即可使用';
  String get onboardingStartAndConnect =>
      isEnglish ? 'Start & Connect' : '启动并连接';
  String get onboardingEnterSessionList =>
      isEnglish ? 'Enter Sessions' : '进入会话列表';
  String get onboardingStarting => isEnglish ? 'Starting…' : '启动中…';
  String get onboardingRestarting => isEnglish ? 'Restarting…' : '重启中';
  String get onboardingRetry => isEnglish ? 'Retry' : '重试';
  String get onboardingNeedInstallAgent =>
      isEnglish ? 'Hermes engine required' : '需先安装 Hermes 引擎';
  String get onboardingNeedInstallAgentDesc => isEnglish
      ? 'The built-in service requires the Hermes engine. Please install it first.'
      : '内置服务需要 Hermes 引擎支持，请先完成安装。';
  String get onboardingGoToInstallGuide =>
      isEnglish ? 'Install Engine' : '安装引擎';
  String get onboardingAdvancedSettings =>
      isEnglish ? 'Advanced Settings' : '高级设置';
  String get onboardingStartOnLoginTitle =>
      isEnglish ? 'Launch at Login' : '开机自启';
  String get onboardingStartOnLoginSubtitle => isEnglish
      ? 'Start Hermes automatically when logging in'
      : '登录 Windows 时自动启动应用';
  String get onboardingBuiltinNotStarted => isEnglish ? 'Not Started' : '未启动';
  String get onboardingBuiltinRunning => isEnglish ? 'Running' : '运行中';

  // ---------------------------------------------------------------------------
  // Language Settings (多语言设置)
  // ---------------------------------------------------------------------------
  String get languageSectionTitle => isEnglish ? 'Language' : '语言';
  String get languageAuto => isEnglish ? 'Auto' : '自动';
  String get languageZh => '中文';
  String get languageEn => 'English';
  // ---------------------------------------------------------------------------
  // Tray menu / keepalive (service-layer, resolved via LocaleResolver)
  // ---------------------------------------------------------------------------
  String get trayShowWindow => isEnglish ? 'Show Main Window' : '显示主窗口';
  String get trayNewSession => isEnglish ? 'New Session' : '新建会话';
  String get trayOpenWebui => isEnglish ? 'Open WebUI' : '打开 WebUI';
  String get trayNoRecentSessions =>
      isEnglish ? 'No Recent Sessions' : '暂无最近会话';
  String get trayQuitApp => isEnglish ? 'Quit App' : '退出应用';
  String get trayWebuiRunning => isEnglish ? 'WebUI: Running' : 'WebUI 服务：运行中';
  String get trayWebuiStarting =>
      isEnglish ? 'WebUI: Starting' : 'WebUI 服务：启动中';
  String get trayWebuiFailed => isEnglish ? 'WebUI: Failed' : 'WebUI 服务：失败';
  String get trayWebuiStopped => isEnglish ? 'WebUI: Stopped' : 'WebUI 服务：已停止';
  String get trayStatusRunning => isEnglish ? 'Running' : '运行中';
  String get trayStatusQueued => isEnglish ? 'Queued' : '排队中';
  String get trayStatusArchived => isEnglish ? 'Archived' : '已归档';
  String get trayStatusReadOnly => isEnglish ? 'Read-only' : '只读';
  String get notifTurnCompleted => isEnglish ? 'Turn Completed' : '回合完成';
  String get notifDownloadComplete => isEnglish ? 'Download Completed' : '下载完成';
  String get notifClarifyBody => isEnglish
      ? 'The agent needs clarification — tap to view'
      : 'Agent 需要你澄清，点击查看';
  String get notifErrorBody =>
      isEnglish ? 'Generation was interrupted — tap to view' : '会话生成异常中断，点击查看';
  String get notifTurnFallbackBody =>
      isEnglish ? 'Agent turn completed — tap to view' : 'Agent 回合已生成完毕，点击查看';
  String get webuiDetailTakeover => isEnglish
      ? 'Takeover: reusing an already-running instance'
      : '接管模式：复用已运行实例';
  String webuiDetailRestarting(int attempt) =>
      isEnglish ? 'Restarting (attempt $attempt)…' : '重启中（第 $attempt 次尝试）…';

  String get previewPdfFailed => isEnglish ? 'Failed to open PDF' : 'PDF 无法打开';
  String get previewOfficeUnsupported =>
      isEnglish ? 'Cannot parse this document' : '无法解析该办公文档';
  String get previewOfficeTooLarge =>
      isEnglish ? 'File too large to preview' : '文件过大，无法预览，请改用下载';
  String get previewOfficeLegacyHint => isEnglish
      ? 'Legacy Office format: text extraction only'
      : '旧版 Office 格式仅提取文本预览';
  String get mermaidRenderToggleTitle =>
      isEnglish ? 'Render Mermaid diagrams' : '渲染 Mermaid 图表';
  String get mermaidRenderToggleSubtitle => isEnglish
      ? 'Render mermaid code blocks in chat as diagrams'
      : '将聊天中的 mermaid 代码块渲染为图形';
  String get mermaidFullscreen => isEnglish ? 'Fullscreen' : '全屏';
  String get mermaidDiagramTitle =>
      isEnglish ? 'Mermaid Diagram' : 'Mermaid 图表';
  String get previewOfficeSheet => isEnglish ? 'Sheet' : '工作表';
  String previewOfficeSlide(int n) => isEnglish ? 'Slide $n' : '第 $n 页';

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('zh'));
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

// ---------------------------------------------------------------------------
// #53 Download center unification extensions
// ---------------------------------------------------------------------------
extension AppLocalizationsDl53 on AppLocalizations {
  String get dl53CannotDownload =>
      isEnglish ? 'Cannot download from this source' : '无法从此来源下载';
}

// ---------------------------------------------------------------------------
// #55 Turn process collapse extensions
// ---------------------------------------------------------------------------
extension AppLocalizationsTurn55 on AppLocalizations {
  String get turn55IntermediateText => isEnglish ? 'Intermediate text' : '中间文本';
  String get turn55TurnCollapseTitle =>
      isEnglish ? 'Collapse Turn Process' : '折叠回合过程';
  String get turn55TurnCollapseDesc => isEnglish
      ? 'Default to showing only question and final response'
      : '默认只显示提问和最终答复';
  String get turn55ExpandProcess => isEnglish ? 'Expand process' : '展开过程';
  String get turn55CollapseProcess => isEnglish ? 'Collapse process' : '收起过程';
  String get turn55ProcessLabel => isEnglish ? 'Process' : '过程';
}

// ---------------------------------------------------------------------------
// #76 Agent gate extensions
// ---------------------------------------------------------------------------
extension AppLocalizationsAgentGate on AppLocalizations {
  String get agentGateNotDetectedTitle =>
      isEnglish ? 'Hermes Agent Not Detected' : '未检测到 Hermes Agent';
  String get agentGateNotDetectedDesc => isEnglish
      ? 'Built-in WebUI service requires a local Hermes Agent environment to run.'
      : '启用内置 WebUI 服务需依赖本机已安装的 Hermes Agent 运行环境。';
  String get agentGateViewInstallGuide =>
      isEnglish ? 'View Install Guide' : '查看安装指南';
  String get agentGateRecheckDone =>
      isEnglish ? 'I have installed it, recheck' : '我装好了，重新检测';
  String get agentGateNeedInstallTitle =>
      isEnglish ? 'Hermes Agent Required' : '需要先安装 Hermes Agent';
  String get agentGateNeedInstallDesc => isEnglish
      ? 'Hermes Agent runtime is not installed on this machine. Cannot start built-in WebUI service. Please install it first.'
      : '检测到本机尚未安装 Hermes Agent 运行环境，无法启动内置 WebUI 服务。请先安装后再启用。';
  String get agentGateGoToInstallGuide =>
      isEnglish ? 'Go to Install Guide' : '前往安装指南';
  String get agentGateRecheck => isEnglish ? 'Recheck' : '重新检测';
  String get agentGateCancel => isEnglish ? 'Cancel' : '取消';
}

// ---------------------------------------------------------------------------
// #78/#79/#80 Message action extensions
// ---------------------------------------------------------------------------
extension AppLocalizationsMsgAction on AppLocalizations {
  String get msgActionLocateFailed =>
      isEnglish ? 'Failed to locate message' : '定位消息失败';
  String get msgActionTruncateFailed =>
      isEnglish ? 'Failed to truncate message' : '截断消息失败';
  String get msgActionEditFailed =>
      isEnglish ? 'Failed to truncate before edit' : '编辑前截断失败';
}

// ---------------------------------------------------------------------------
// #84 Built-in WebUI password hint & regenerate extensions
// ---------------------------------------------------------------------------
extension AppLocalizationsBuiltinPassword84 on AppLocalizations {
  String get agentGatePasswordHint => isEnglish
      ? 'A random password was generated by default. You can set your own.'
      : '默认已生成随机密码，可修改为你自己的密码';
  String get agentGateRegeneratePassword => isEnglish ? 'Regenerate' : '重新生成';
}

// ---------------------------------------------------------------------------
// #85 Auto-load images extensions
// ---------------------------------------------------------------------------
extension AppLocalizationsAutoLoadImages85 on AppLocalizations {
  String get chatAutoLoadSetting => isEnglish ? 'Auto-load Images' : '自动加载图片';
  String get chatAutoLoadTapToLoad => isEnglish ? 'Tap to load' : '点击加载';
}

// #93 下载进度常驻通知（notification-rewriter 不涉及；仅 Android 使用）
// ---------------------------------------------------------------------------
extension AppLocalizationsDownloadProgress93 on AppLocalizations {
  String get notifDownloading => isEnglish ? 'Downloading' : '正在下载';
}

// #96 APK 安装权限引导（仅 Android 使用）
// ---------------------------------------------------------------------------
extension AppLocalizationsInstallPermission96 on AppLocalizations {
  String get installPermissionTitle =>
      isEnglish ? 'Install Permission Required' : '需要安装权限';
  String get installPermissionBody => isEnglish
      ? 'To install APK files, allow "Install unknown apps" for Hermes in system settings, then come back and tap Open again.'
      : '安装 APK 需要在系统设置中允许 Hermes「安装未知应用」，授权后回来重新点「打开」即可。';
  String get installPermissionGoSettings =>
      isEnglish ? 'Go to Settings' : '去设置';
}

// ---------------------------------------------------------------------------
// #98 下载自动重试与断点续传（下载页进行中提示）
// ---------------------------------------------------------------------------
extension AppLocalizationsDownloadResume98 on AppLocalizations {
  String downloadRetrying(int attempt, int maxAttempts) => isEnglish
      ? 'Retrying ($attempt/$maxAttempts)…'
      : '第 $attempt/$maxAttempts 次重试中';

  String get downloadResumed => isEnglish ? 'Resumed' : '已续传';

  String downloadResumedWithSize(String size) =>
      isEnglish ? 'Resumed $size' : '已续传 $size';
}

// ---------------------------------------------------------------------------
// #101 GitHub Releases 更新检测与自动更新开关
// ---------------------------------------------------------------------------
extension AppLocalizationsUpdate101 on AppLocalizations {
  String get updateSectionTitle => isEnglish ? 'Software Update' : '软件更新';
  String get currentVersionLabel => isEnglish ? 'Current Version' : '当前版本';
  String get autoCheckUpdateLabel =>
      isEnglish ? 'Auto-check for Updates' : '自动检查更新';
  String get checkUpdateNowLabel => isEnglish ? 'Check for Updates' : '检查更新';
  String get checkingForUpdate =>
      isEnglish ? 'Checking for updates…' : '正在检查更新…';
  String get updateAlreadyLatest => isEnglish ? 'Already up to date' : '已是最新版本';
  String get updateCheckFailed => isEnglish
      ? 'Failed to check for updates, please try again later'
      : '检查更新失败，请稍后重试';
  String updateDialogTitle(String version) =>
      isEnglish ? 'New Version Available $version' : '发现新版本 $version';
  String get updateGoToDownload => isEnglish ? 'Download' : '前往下载';
  String get updateDownloadingStarted =>
      isEnglish ? 'Download added to queue' : '已加入下载队列，可在下载管理中查看进度';
  String get updateInstallNow => isEnglish ? 'Install Now' : '立即安装';
  String get updateReadyToInstall => isEnglish
      ? 'Update download completed. Install now?'
      : '新版本已下载完成，是否立即安装？';
}

// ---------------------------------------------------------------------------
// chat header: open session project folder in Explorer (Windows)
// ---------------------------------------------------------------------------
extension AppLocalizationsProjectFolder on AppLocalizations {
  String get openProjectFolder => isEnglish ? 'Open Project Folder' : '打开项目文件夹';
  String projectFolderMissing(String path) =>
      isEnglish ? 'Project folder not found: $path' : '项目文件夹不存在：$path';
  String openProjectFolderFailed(String error) =>
      isEnglish ? 'Failed to open project folder: $error' : '打开项目文件夹失败：$error';
}

// ---------------------------------------------------------------------------
// #105 安卓 16 Live Updates（实况通知/灵动岛）
// ---------------------------------------------------------------------------
extension AppLocalizationsLiveUpdate105 on AppLocalizations {
  /// 实况通知标题（单会话）。
  String get liveUpdateTitle =>
      isEnglish ? 'Hermes · Working' : 'Hermes · 回合进行中';

  /// 实况通知标题（多会话聚合）。
  String liveUpdateTitleMulti(int count) => isEnglish
      ? 'Hermes · Working · $count sessions'
      : 'Hermes · 回合进行中 · $count 个会话';

  /// 无会话名时的兜底正文。
  String get liveUpdateDefaultText =>
      isEnglish ? 'Generating reply…' : '正在生成回复…';

  /// 状态栏 chip 短文案（硬约束 ≤6 字符）。
  String get liveUpdateChip => isEnglish ? 'Live' : '生成中';

  /// 设置页开关行标题。
  String get liveUpdateSwitchTitle =>
      isEnglish ? 'Live Updates (Dynamic Island)' : '实况通知（灵动岛）';

  /// 设置页开关行副标题。
  String get liveUpdateSwitchSubtitle => isEnglish
      ? 'Promoted ongoing notifications on Android 16+ / HyperOS 3.1; silently ignored on older systems'
      : '安卓 16+/HyperOS 3.1 实况通知生效，其他系统自动降级、不受影响';

  // ---------------------------------------------------------------------------
  // #120 实况通知回合实时活动（正文与 chip 随活动变化）
  // ---------------------------------------------------------------------------

  /// 活动正文：推理中。
  String get liveUpdateActivityThinking => isEnglish ? 'Thinking…' : '正在思考…';

  /// 活动正文：工具调用（[name] 为空时用通用文案）。
  String liveUpdateActivityTool(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return isEnglish ? 'Using tools…' : '正在调用工具…';
    }
    return isEnglish ? 'Running $trimmed…' : '正在调用 $trimmed…';
  }

  /// 活动正文：正文输出中。
  String get liveUpdateActivityOutput => isEnglish ? 'Writing reply…' : '正在输出…';

  /// 活动正文：等待主人回复（澄清卡片已弹出）。
  String get liveUpdateActivityWaitingReply =>
      isEnglish ? 'Waiting for your reply' : '等待你的回复';

  /// 活动正文：等待主人批准（审批卡片已弹出）。
  String get liveUpdateActivityWaitingApproval =>
      isEnglish ? 'Waiting for approval' : '等待你的批准';

  /// 状态栏 chip 短文案（#48 定稿五态之一：请回复；系统硬限 ≤6 字符）。
  String get liveUpdateChipReply => isEnglish ? 'Reply' : '请回复';

  /// 状态栏 chip 短文案（#48 定稿五态之一：请批准）。
  String get liveUpdateChipApproval => isEnglish ? 'Allow' : '请批准';

  /// 活动正文：回合已完成（#129 已完成态，岛上停留 15s 后撤）。
  String get liveUpdateActivityCompleted =>
      isEnglish ? 'Turn completed' : '回合已完成';

  /// 活动正文：回合已中断（#129，cancel / error 收尾）。
  String get liveUpdateActivityInterrupted =>
      isEnglish ? 'Turn interrupted' : '回合已中断';

  /// 状态栏 chip 短文案（#48 定稿五态之一：已完成）。
  String get liveUpdateChipDone => isEnglish ? 'Done' : '已完成';

  /// 状态栏 chip 短文案（#48 定稿五态之一：已中断）。
  String get liveUpdateChipStopped => isEnglish ? 'Stop' : '已中断';

  /// 状态栏 chip 短文案（下载中，硬约束 ≤6 字符）。
  String get liveUpdateDownloadChip => isEnglish ? 'Save' : '下载中';

  /// 活动正文：下载进行中（已知总大小）。
  String liveUpdateActivityDownload(String fileName, int percent) => isEnglish
      ? 'Downloading $fileName · $percent%'
      : '正在下载 $fileName · $percent%';

  /// 活动正文：下载进行中（总大小未知）。
  String liveUpdateActivityDownloadUnknownSize(String fileName) =>
      isEnglish ? 'Downloading $fileName' : '正在下载 $fileName';

  /// 活动正文：下载队列排队后缀（仅 queuedCount > 0 时拼接）。
  String liveUpdateDownloadQueuedSuffix(int count) =>
      isEnglish ? ' · +$count queued' : ' · 还有 $count 个';

  /// 活动正文：下载完成（#158，岛上的完成态）。
  ///
  /// 与回合完成态的「回合已完成」区分开：下载是全局动作、不属于回合，故文案
  /// 以文件名为焦点，让用户一眼知道**下完了哪个文件**。
  String liveUpdateActivityDownloadCompleted(String fileName) =>
      isEnglish ? '$fileName downloaded' : '$fileName 下载完成';

  /// 实况通知次级信息（subText）：另有 N 个会话（B 案，2026-09-19）。
  ///
  /// 只放**系统不会替我们显示**的信息：真机取证显示小米超级岛会自行在头部显示
  /// App 名与计时器，subText 再放 App 名会让一屏出现两遍「Hermes」。中文不带
  /// 量词后缀以省宽度；英文按单复数分流。
  String liveUpdateSubTextExtraSessions(int count) {
    if (isEnglish) {
      return count == 1 ? '1 more session' : '$count more sessions';
    }
    return '另有 $count 个会话';
  }
}

// ---------------------------------------------------------------------------
// #106 会话列表实时推送
// ---------------------------------------------------------------------------
extension AppLocalizationsSessionEvents106 on AppLocalizations {
  /// 设置页开关行标题。
  String get sessionEventsStreamTitle =>
      isEnglish ? 'Realtime session list updates' : '会话列表实时推送';

  /// 设置页开关行副标题。
  String get sessionEventsStreamSubtitle => isEnglish
      ? 'Subscribe to server events for immediate session list updates'
      : '通过服务端事件推送即时感知会话变更';
}

// ---------------------------------------------------------------------------
// #107 审批实时推送
// ---------------------------------------------------------------------------
extension AppLocalizationsApprovalStream107 on AppLocalizations {
  /// 设置页开关行标题。
  String get approvalStreamTitle =>
      isEnglish ? 'Realtime approval updates' : '审批实时推送';

  /// 设置页开关行副标题。
  String get approvalStreamSubtitle => isEnglish
      ? 'Subscribe to server events for immediate approval prompts'
      : '通过服务端事件推送即时感知待审批操作';
}

// #108 会话内容实时同步
// ---------------------------------------------------------------------------
extension AppLocalizationsSessionContent108 on AppLocalizations {
  /// 设置页开关行标题。
  String get sessionContentStreamTitle =>
      isEnglish ? 'Realtime session content sync' : '会话内容实时同步';

  /// 设置页开关行副标题。
  String get sessionContentStreamSubtitle => isEnglish
      ? 'Subscribe to per-session events for realtime transcript updates'
      : '通过当前会话事件流实时同步正文内容与自唤醒回合';
}

// ---------------------------------------------------------------------------
// #113 保活设置页 WorkManager 状态三态
// ---------------------------------------------------------------------------
extension AppLocalizationsWorkManagerStatus113 on AppLocalizations {
  /// WorkManager 状态：不适用（非 Android）。
  String get bgWorkManagerStatusNotApplicable =>
      isEnglish ? 'Not applicable (Android only)' : '不适用（仅限 Android）';

  /// WorkManager 状态：未就绪（无归因简写）。
  String get bgWorkManagerStatusFailedShort => isEnglish ? 'Not ready' : '未就绪';

  /// WorkManager 状态：未就绪（带归因描述）。
  String bgWorkManagerStatusFailed(String reason) => isEnglish
      ? (reason.isEmpty ? 'Not ready' : 'Not ready: $reason')
      : (reason.isEmpty ? '未就绪' : '未就绪：$reason');
}

// ---------------------------------------------------------------------------
// #145 桌面端外壳：侧栏导航轨 / 工作区选择器 / 输入区元信息 chip
// ---------------------------------------------------------------------------
extension AppLocalizationsDesktopShell145 on AppLocalizations {
  /// 输入区元信息 chip：工作区键名。
  String get composerWorkspaceLabel => isEnglish ? 'Workspace' : '工作区';

  /// 输入区元信息 chip：模型键名。
  String get composerModelLabel => isEnglish ? 'Model' : '模型';

  /// 会话未绑定工作区时的虚线 chip 文案（可点即填）。
  String get composerNoWorkspace => isEnglish ? 'Select workspace' : '选择工作区';

  /// 会话未显式选模型时的虚线 chip 文案（跟随服务端默认）。
  String get composerDefaultModel => isEnglish ? 'Server default' : '跟随默认模型';

  /// 会话绑定的工作区目录已不存在 / 无权限（chip 红色异常态）。
  String get composerWorkspaceUnavailable =>
      isEnglish ? 'Workspace unavailable' : '工作区已失效';

  /// 侧栏工作区选择器：不过滤，显示全部会话。
  String get allWorkspaces => isEnglish ? 'All workspaces' : '全部工作区';

  /// 侧栏工作区选择器：某工作区下的会话计数（用于副标题）。
  String workspaceSessionCount(int count) =>
      isEnglish ? '$count sessions' : '$count 个会话';

  /// 侧栏底部状态条：内置服务（sidecar）。
  String get builtinService => isEnglish ? 'Built-in service' : '内置服务';

  /// 侧栏底部状态条：外部服务器连接。
  String get externalServer => isEnglish ? 'External server' : '外部服务器';

  /// 侧栏底部状态条：正在建立连接。
  String get connecting => isEnglish ? 'Connecting…' : '连接中…';

  /// 侧栏底部状态条：未连接。
  String get offline => isEnglish ? 'Offline' : '离线';

  /// 侧栏导航轨：会话入口标题。
  String get sessionsTitle => sessions;
}

// ---------------------------------------------------------------------------
// #146 会话列表按工作区分组
// ---------------------------------------------------------------------------
extension AppLocalizationsWorkspaceGroup146 on AppLocalizations {
  /// 会话列表未绑定工作区的「其他」分组标题。
  String get otherSection => isEnglish ? 'Other' : '其他';
}
