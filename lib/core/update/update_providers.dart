import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/widgets/hermes_dialog.dart';
import '../../features/downloads/download_controller.dart';
import '../../features/downloads/download_models.dart';
import '../../features/downloads/download_providers.dart';
import '../../l10n/app_localizations.dart';
import 'apk_installer.dart';
import 'github_release.dart';
import 'update_checker_service.dart';

/// UpdateCheckerService Provider。
final updateCheckerServiceProvider = Provider<UpdateCheckerService>((ref) {
  return UpdateCheckerService();
});

/// 自动检查更新开关 Notifier 控制器。
class AutoCheckUpdateController extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_init());
    return true;
  }

  Future<void> _init() async {
    final service = ref.read(updateCheckerServiceProvider);
    final enabled = await service.isAutoCheckEnabled();
    state = enabled;
    if (enabled) {
      unawaited(service.checkForUpdates(isManual: false));
    }
  }

  /// 切换开关状态并持久化。
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final service = ref.read(updateCheckerServiceProvider);
    await service.setAutoCheckEnabled(enabled);
  }
}

/// 自动检查更新开关 Provider。
final autoCheckUpdateEnabledProvider =
    NotifierProvider<AutoCheckUpdateController, bool>(
  AutoCheckUpdateController.new,
);

/// 处理点击「前往下载」的核心逻辑（双端差异与资产匹配）。
Future<void> handleDownloadOrOpenRelease(
  BuildContext context,
  WidgetRef ref,
  GithubRelease release, {
  TargetPlatform? platform,
  Future<bool> Function(Uri url)? urlLauncher,
  Future<bool> Function(BuildContext context, String path)? apkInstaller,
}) async {
  final targetPlatform = platform ?? defaultTargetPlatform;
  final l10n = AppLocalizations.of(context);

  if (targetPlatform == TargetPlatform.android) {
    final apkAsset = findPlatformAsset(
      release,
      platform: TargetPlatform.android,
    );

    if (apkAsset != null && apkAsset.browserDownloadUrl.isNotEmpty) {
      final downloadController = ref.read(downloadControllerProvider.notifier);
      final taskId = await downloadController.enqueue(
        sourceUrl: apkAsset.browserDownloadUrl,
        fileName: apkAsset.name.isNotEmpty ? apkAsset.name : 'app-release.apk',
        expectedBytes: apkAsset.size > 0 ? apkAsset.size : null,
      );

      final state = ref.read(downloadControllerProvider);
      final task = state.taskById(taskId);

      // 若已经下载完毕且文件存在，直接提示安装
      if (task != null &&
          task.status == DownloadStatus.completed &&
          task.savedPath != null) {
        try {
          if (File(task.savedPath!).existsSync()) {
            if (context.mounted) {
              await promptInstallApk(
                context,
                task.savedPath!,
                apkInstaller: apkInstaller,
              );
            }
            return;
          }
        } catch (_) {}
      }

      // 监听下载完成事件：下载完毕后在当前上下文弹出安装提示
      ProviderSubscription<DownloadState>? sub;
      sub = ref.listenManual<DownloadState>(
        downloadControllerProvider,
        (previous, next) {
          final updatedTask = next.taskById(taskId);
          if (updatedTask != null &&
              updatedTask.status == DownloadStatus.completed &&
              updatedTask.savedPath != null) {
            sub?.close();
            if (context.mounted) {
              unawaited(
                promptInstallApk(
                  context,
                  updatedTask.savedPath!,
                  apkInstaller: apkInstaller,
                ),
              );
            }
          } else if (updatedTask != null &&
              (updatedTask.status == DownloadStatus.failed ||
                  updatedTask.status == DownloadStatus.cancelled)) {
            sub?.close();
          }
        },
      );

      if (context.mounted) {
        // 批 5 · C4：D1 四档宽「确认框 380」（窄屏仍走系统 alert，逐像素不变）。
        await showHermesDialog<void>(
          context,
          kind: HermesDialogKind.confirm,
          title: (_) => Text(l10n.updateSectionTitle),
          content: (_) => Text(l10n.updateDownloadingStarted),
          actions: [
            HermesDialogAction(
              builder: (_) => Text(l10n.ok),
              onPressed: (dialogContext) =>
                  Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      }
      return;
    }
  }

  // Windows 或未找到对应资产时：使用 url_launcher 打开
  final asset = findPlatformAsset(release, platform: targetPlatform);
  final targetUrl = (asset != null && asset.browserDownloadUrl.isNotEmpty)
      ? asset.browserDownloadUrl
      : release.htmlUrl;

  final uri = Uri.tryParse(targetUrl.isNotEmpty ? targetUrl : release.htmlUrl);
  if (uri != null) {
    if (urlLauncher != null) {
      await urlLauncher(uri);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 弹出 APK 安装确认弹窗。
Future<void> promptInstallApk(
  BuildContext context,
  String path, {
  Future<bool> Function(BuildContext context, String path)? apkInstaller,
}) async {
  final l10n = AppLocalizations.of(context);
  // 批 5 · C4：D1 四档宽「确认框 380」（确认安装属确认类；窄屏逐像素不变）。
  // 动作回调收 dialogContext 只用于 pop —— 安装本身仍用外层 context
  // （业务语义不变：安装流程要活在调用页上，不活在弹窗路由上）。
  await showHermesDialog<void>(
    context,
    kind: HermesDialogKind.confirm,
    title: (_) => Text(l10n.updateSectionTitle),
    content: (_) => Text(l10n.updateReadyToInstall),
    actions: [
      HermesDialogAction(
        builder: (_) => Text(l10n.cancel),
        onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
      ),
      HermesDialogAction(
        isDefaultAction: true,
        builder: (_) => Text(l10n.updateInstallNow),
        onPressed: (dialogContext) {
          Navigator.of(dialogContext).pop();
          if (apkInstaller != null) {
            unawaited(apkInstaller(context, path));
          } else {
            unawaited(installApkWithPermissionGate(context, path));
          }
        },
      ),
    ],
  );
}
