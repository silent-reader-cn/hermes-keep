import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../app/locale/locale_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../diagnostics/diagnostics_models.dart';
import '../diagnostics/diagnostics_service.dart';
import '../downloads/download_models.dart';

/// 回合/澄清/错误/下载通知服务（抽象接口，平台无关契约）。
///
/// 生产实现 [LocalNotificationsTurnNotificationService] 基于
/// flutter_local_notifications；测试注入 fake 实现即可验证通知触发逻辑。
abstract interface class TurnNotificationService {
  /// 回合完成 → 弹系统通知（Android channel: "turns", ID: 1001; Windows）。
  ///
  /// 应用内横幅已移除：前台与后台统一走系统通知（免打扰双条件命中时不发，
  /// 见 notification_providers.dart 的 [shouldSilenceNotification] 语义）。
  ///
  /// [sessionId] 编码进点击 payload（点击回到对应会话）；[title] 为通知标题，
  /// [preview] 为内容预览（由实现负责单行化/截断）。
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  );

  /// 需要澄清 → 弹系统通知（Android channel: "clarify", ID: 1101; Windows）。
  ///
  /// [sessionId] 编码进点击 payload；[question] 为澄清问题正文。
  Future<void> notifyClarificationNeeded(String sessionId, String question);

  /// 异常中断/错误 → 弹系统通知（Android channel: "errors", ID: 1201; Windows）。
  ///
  /// [sessionId] 编码进点击 payload；[title] 为异常标题，[preview] 为错误预览。
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  );

  /// 下载完成 → 弹系统通知（Android channel: "downloads", ID: 1301; Windows）。
  ///
  /// [downloadId] 编码进点击 payload（payload 格式为 `download:<downloadId>`）；
  /// [fileName] 为文件名，[byteSize] 为文件字节大小。
  Future<void> notifyDownloadCompleted(
    String downloadId,
    String fileName,
    int byteSize,
  );

  /// 下载进度 → 状态栏常驻进度通知（#93；Android only，其他平台空转）。
  ///
  /// [fileName] 当前下载文件名；[receivedBytes]/[expectedBytes] 已接收/总字节
  /// （expectedBytes <= 0 表示总大小未知 → 进度条转 indeterminate）；
  /// [queuedCount] 为队列中排队中任务数（>0 时正文附「还有 N 个排队」）。
  Future<void> updateDownloadProgress({
    required String fileName,
    required int receivedBytes,
    required int expectedBytes,
    int queuedCount = 0,
  });

  /// 隐藏下载进度常驻通知（下载完成/失败/取消/队列空时调用；Android only）。
  Future<void> clearDownloadProgress();

  /// 清除全部通知（回到前台 / 点击通知后调用）。
  Future<void> clearAll();

  /// 请求通知权限（Android 13+ 必需；其他平台视为已授权）。
  Future<bool> requestPermission();

  /// 检查通知权限当前是否已授予（Android 13+ 需 POST_NOTIFICATIONS；
  /// 升级安装场景系统保留旧状态且不再弹窗——用于设置页状态提示引导）。
  Future<bool> areNotificationsEnabled();

  /// 冷启动来源 payload / sessionId：由通知点击拉起 app 时返回 payload 中的
  /// 内容（非通知启动返回 null）。
  Future<String?> getLaunchSessionId();
}

/// HyperOS 3 / Android 后台联网与保活策略说明：
///
/// 1. **HyperOS 3 / MIUI 后台冻结机制**：
///    - 小米 HyperOS 3 对后台应用的电池和网络管控极其严格。App 切入后台或锁屏后，
///      系统可能在数秒到数分钟内冻结网络套接字（WebSocket / SSE）并暂停 Isolate 定时器。
///    - 导致现象：后台期间无法实时接收服务端 SSE 结束事件；切回前台时才触发重连与同步。
///
/// 2. **用户端可复现引导与配置**：
///    - 自启动管理：系统设置 → 应用设置 → 应用管理 → Hermes → 开启「自启动」与「关联启动」；
///    - 省电策略：系统设置 → 应用设置 → Hermes → 省电策略 → 设为「无限制」；
///    - 后台联网：系统设置 → 应用设置 → Hermes → 联网控制 → 确保 WLAN 和移动数据全开；
///    - 通知权限与锁屏：允许「通知」以及「悬浮通知」、「锁屏通知」；
///    - 任务卡片锁定：在多任务界面下拉 Hermes 卡片加锁，防止被一键清理。
///
/// 3. **长期保活与降级架构方案**：
///    - 方案 A（Foreground Service 前台服务）：在后台流式生成进行期间启动前台服务，
///      展示进行中通知（"Hermes 正在生成..."）并持有 CPU WakeLock，防止网络冻结；生成完成后
///      自动关闭前台服务并弹出回合完成高优先级通知（ID: 1001）；
///    - 方案 B（WorkManager / 周期探活）：当流式断开或未收到完成通知时，通过 WorkManager
///      后台拉取 `GET /api/sessions/:id/status` 纠偏，触发补发通知；
///    - 方案 C（FCM / 统一推送通道）：服务端生成完成时直接下发推送通知唤醒 App。
///
/// flutter_local_notifications 生产实现（Android 4 通道 + Windows Toast）。
///
/// 行为对齐契约：
/// 1. Android 分区 1001(turns)/1101(clarify)/1201(errors)/1301(downloads)，冷启动即批量预创建通道；
/// 2. Windows Toast 初始化 (Hermes UI + AUMID com.hermes.ui)；
/// 3. 点击回到对应会话或处理下载，回到 app 自动清除。所有平台调用均吞异常并记日志与诊断。
class LocalNotificationsTurnNotificationService
    implements TurnNotificationService {
  LocalNotificationsTurnNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    this.onTap,
    bool? androidPlatformOverride,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _androidPlatformOverride = androidPlatformOverride; // ignore: prefer_initializing_formals

  /// Android 通知通道：回合完成。
  static const channelTurnsId = 'turns';
  static const channelTurnsName = '回合完成';
  static const channelTurnsDescription = 'Agent 回合完成时推送系统通知';
  static const notificationTurnsId = 1001;

  /// Android 通知通道：需要澄清。
  static const channelClarifyId = 'clarify';
  static const channelClarifyName = '需要澄清';
  static const channelClarifyDescription = 'Agent 需要用户澄清时推送系统通知';
  static const notificationClarifyId = 1101;

  /// Android 通知通道：异常中断。
  static const channelErrorsId = 'errors';
  static const channelErrorsName = '异常中断';
  static const channelErrorsDescription = '会话异常中断或出错时推送系统通知';
  static const notificationErrorsId = 1201;

  /// Android 通知通道：下载完成。
  static const channelDownloadsId = 'downloads';
  static const channelDownloadsName = '下载完成';
  static const channelDownloadsDescription = '文件下载完成时推送系统通知';
  static const notificationDownloadsId = 1301;

  /// 下载进行中常驻进度通知 ID（#93；与 1301 同渠道，完成时 cancel 本条）。
  static const notificationDownloadProgressId = 1401;

  /// Android 通知渠道配置列表（启动时批量预创建）。
  static const androidChannels = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      channelTurnsId,
      channelTurnsName,
      description: channelTurnsDescription,
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      channelClarifyId,
      channelClarifyName,
      description: channelClarifyDescription,
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      channelErrorsId,
      channelErrorsName,
      description: channelErrorsDescription,
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      channelDownloadsId,
      channelDownloadsName,
      description: channelDownloadsDescription,
      importance: Importance.high,
    ),
  ];

  /// 兼容历史 channel 常量。
  static const channelId = channelTurnsId;
  static const channelName = channelTurnsName;
  static const channelDescription = channelTurnsDescription;
  static const notificationId = notificationTurnsId;

  /// 预览正文最大长度（超出截断）。
  static const maxPreviewLength = 120;

  final FlutterLocalNotificationsPlugin _plugin;

  /// 点击通知回调（入参为 payload：sessionId 或 `download:<id>` 等扩展前缀）。
  final void Function(String payload)? onTap;

  /// Android 平台判定覆盖（测试注入用；null = 真实 Platform.isAndroid）。
  final bool? _androidPlatformOverride;

  bool get _isAndroid => _androidPlatformOverride ?? Platform.isAndroid;

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: 'Hermes UI',
            appUserModelId: 'com.hermes.ui',
            guid: 'd9b0a6fb-9a4f-4d33-97be-4ef018260827',
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final sessionId = response.payload;
          if (sessionId != null && sessionId.isNotEmpty) {
            onTap?.call(sessionId);
          }
        },
      );
      _initialized = true;

      // 显式批量预创建 Android 通知三渠道（覆盖安装冷启动后立即补齐三通道）：
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        for (final channel in androidChannels) {
          await android.createNotificationChannel(channel);
        }
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.info,
          tag: 'notifications',
          message: '预创建 Android 通知渠道成功',
          details: {'channels': androidChannels.map((c) => c.id).toList()},
        );
      }
    } on Object catch (error) {
      // 平台插件未注册（如测试环境 / 桌面端）或初始化失败：
      // 通知是增强功能，绝不影响聊天主流程。
      developer.log('通知服务初始化失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '通知服务初始化失败',
        errorKind: error.toString(),
      );
    }
  }

  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {
    if (sessionId.isEmpty) return;
    await _ensureInitialized();
    try {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'notifications',
        message: '发送回合完成通知',
        details: {
          'sessionId': sessionId,
          'title': title,
          'previewLength': preview.length,
          'channel': channelTurnsId,
          'notificationId': notificationTurnsId,
        },
      );
      await _plugin.show(
        id: notificationTurnsId,
        title: title,
        body: formatPreview(preview),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelTurnsId,
            channelTurnsName,
            channelDescription: channelTurnsDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: sessionId,
      );
    } on Object catch (error) {
      developer.log('回合完成通知发送失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '回合完成通知发送失败',
        details: {'sessionId': sessionId, 'title': title},
        errorKind: error.toString(),
      );
    }
  }

  @override
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {
    if (sessionId.isEmpty) return;
    await _ensureInitialized();
    try {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'notifications',
        message: '发送需要澄清通知',
        details: {
          'sessionId': sessionId,
          'questionLength': question.length,
          'channel': channelClarifyId,
          'notificationId': notificationClarifyId,
        },
      );
      await _plugin.show(
        id: notificationClarifyId,
        title: AppLocalizations(LocaleResolver.resolve())
            .clarificationNeeded,
        body: formatPreview(question),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelClarifyId,
            channelClarifyName,
            channelDescription: channelClarifyDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: sessionId,
      );
    } on Object catch (error) {
      developer.log('澄清请求通知发送失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '澄清请求通知发送失败',
        details: {'sessionId': sessionId},
        errorKind: error.toString(),
      );
    }
  }

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {
    if (sessionId.isEmpty) return;
    await _ensureInitialized();
    final heading = title.trim().isNotEmpty ? title.trim() : '会话异常';
    try {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'notifications',
        message: '发送异常中断通知',
        details: {
          'sessionId': sessionId,
          'title': heading,
          'previewLength': preview.length,
          'channel': channelErrorsId,
          'notificationId': notificationErrorsId,
        },
      );
      await _plugin.show(
        id: notificationErrorsId,
        title: heading,
        body: formatPreview(preview),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelErrorsId,
            channelErrorsName,
            channelDescription: channelErrorsDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: sessionId,
      );
    } on Object catch (error) {
      developer.log('异常中断通知发送失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '异常中断通知发送失败',
        details: {'sessionId': sessionId, 'title': heading},
        errorKind: error.toString(),
      );
    }
  }

  @override
  Future<void> notifyDownloadCompleted(
    String downloadId,
    String fileName,
    int byteSize,
  ) async {
    if (downloadId.isEmpty) return;
    await _ensureInitialized();
    final sizeText = formatDownloadByteSize(byteSize);
    final body = sizeText.isNotEmpty ? '$fileName ($sizeText)' : fileName;
    try {
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'notifications',
        message: '发送下载完成通知',
        details: {
          'downloadId': downloadId,
          'fileName': fileName,
          'byteSize': byteSize,
          'channel': channelDownloadsId,
          'notificationId': notificationDownloadsId,
        },
      );
      await _plugin.show(
        id: notificationDownloadsId,
        title: AppLocalizations(LocaleResolver.resolve())
            .notifDownloadComplete,
        body: formatPreview(body),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelDownloadsId,
            channelDownloadsName,
            channelDescription: channelDownloadsDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: 'download:$downloadId',
      );
    } on Object catch (error) {
      developer.log('下载完成通知发送失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '下载完成通知发送失败',
        details: {'downloadId': downloadId, 'fileName': fileName},
        errorKind: error.toString(),
      );
    }
  }

  @override
  Future<void> updateDownloadProgress({
    required String fileName,
    required int receivedBytes,
    required int expectedBytes,
    int queuedCount = 0,
  }) async {
    // #93 手机端专属：Windows 等桌面平台不弹进度通知（桌面下载页内可见）。
    if (!_isAndroid) return;
    await _ensureInitialized();
    try {
      final hasTotal = expectedBytes > 0;
      final percent = hasTotal ? (receivedBytes * 100 ~/ expectedBytes) : 0;
      final sizeText = hasTotal
          ? '${formatDownloadByteSize(receivedBytes)} / ${formatDownloadByteSize(expectedBytes)}'
          : formatDownloadByteSize(receivedBytes);
      final queueSuffix = queuedCount > 0 ? ' · 还有 $queuedCount 个排队' : '';
      final body = '$fileName ${sizeText.isNotEmpty ? '($sizeText)' : ''}'
          '$queueSuffix';
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.debug,
        tag: 'notifications',
        message: '更新下载进度通知',
        details: {
          'fileName': fileName,
          'receivedBytes': receivedBytes,
          'expectedBytes': expectedBytes,
          'percent': percent,
          'queuedCount': queuedCount,
        },
      );
      await _plugin.show(
        id: notificationDownloadProgressId,
        title: AppLocalizations(LocaleResolver.resolve()).notifDownloading,
        body: formatPreview(body),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelDownloadsId,
            channelDownloadsName,
            channelDescription: channelDownloadsDescription,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            showProgress: true,
            indeterminate: !hasTotal,
            maxProgress: 100,
            progress: percent.clamp(0, 100),
          ),
        ),
        payload: 'download:progress',
      );
    } on Object catch (error) {
      developer.log('下载进度通知更新失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '下载进度通知更新失败',
        details: {'fileName': fileName},
        errorKind: error.toString(),
      );
    }
  }

  @override
  Future<void> clearDownloadProgress() async {
    if (!_isAndroid) return;
    await _ensureInitialized();
    try {
      await _plugin.cancel(id: notificationDownloadProgressId);
    } on Object catch (error) {
      developer.log('清除下载进度通知失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '清除下载进度通知失败',
        errorKind: error.toString(),
      );
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      await _plugin.cancelAll();
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.debug,
        tag: 'notifications',
        message: '清除全部通知',
      );
    } on Object catch (error) {
      developer.log('清除通知失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '清除通知失败',
        errorKind: error.toString(),
      );
    }
  }

  @override
  Future<bool> requestPermission() async {
    // 必须先初始化插件（根因②：此前未 initialize 直接 invoke 权限通道，
    // 异常被 catch 吞 → false → 后台 show 全被系统丢弃）。
    await _ensureInitialized();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      final result = granted ?? true;
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'notifications',
        message: '请求通知权限结果: $result',
        details: {'granted': result},
      );
      return result;
    } on Object catch (error) {
      developer.log('请求通知权限失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '请求通知权限失败',
        errorKind: error.toString(),
      );
      return false;
    }
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    await _ensureInitialized();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // 非 Android 平台无 POST_NOTIFICATIONS 概念，视为已启用。
      if (android == null) return true;
      final enabled = await android.areNotificationsEnabled();
      final result = enabled ?? false;
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'notifications',
        message: '通知权限状态: $result',
        details: {'enabled': result},
      );
      return result;
    } on Object catch (error) {
      developer.log('检查通知权限失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '检查通知权限失败',
        errorKind: error.toString(),
      );
      return false;
    }
  }

  @override
  Future<String?> getLaunchSessionId() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      final payload = details?.notificationResponse?.payload;
      if (payload == null || payload.isEmpty) return null;
      return payload;
    } on Object catch (error) {
      developer.log('读取启动通知失败: $error', name: 'notifications');
      return null;
    }
  }

  /// preview 单行化 + 截断（通知栏正文展示用）。
  static String formatPreview(String preview) {
    final oneLine = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= maxPreviewLength) return oneLine;
    return '${oneLine.substring(0, maxPreviewLength)}…';
  }
}
