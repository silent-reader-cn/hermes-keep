package com.silentreader.hermes_ui

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 文件分享通道：content:// URI 生成 / APK 安装权限引导 / 系统分享面板。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getShareUri" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_ARGUMENT", "path is empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "file does not exist", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.provider",
                            file
                        )
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("URI_ERROR", e.message, null)
                    }
                }
                // Android 8+：当前 app 是否已被授予「安装未知应用」资格。
                "canRequestInstall" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                // 跳转系统「安装未知应用」授权页（一次性引导，用户勾选后回来）。
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                // 系统分享面板（ACTION_SEND + EXTRA_STREAM）。
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_ARGUMENT", "path is empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "file does not exist", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.provider",
                            file
                        )
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType ?: "application/octet-stream"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        val chooser = Intent.createChooser(sendIntent, null).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // #105 安卓 16 Live Updates（实况通知）通道：把「Agent 回合进行中」
        // 常驻通知升级为 Promoted Ongoing（状态栏 chip / 岛摘要态 / 通知栏置顶卡）。
        // flutter_local_notifications 暂不支持（上游 issue #2773），故走原生。
        // 全程 try-catch，失败返回 false/error——通知是增强功能，绝不 crash。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LIVE_UPDATE_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isSupported" -> result.success(canPostPromoted())
                    "show" -> {
                        val id = call.argument<Int>("id")
                        val channelId = call.argument<String>("channelId")
                        val title = call.argument<String>("title")
                        val text = call.argument<String>("text")
                        val shortCriticalText = call.argument<String>("shortCriticalText")
                        val indeterminate = call.argument<Boolean>("indeterminate") ?: true
                        if (id == null || channelId.isNullOrEmpty() ||
                            title.isNullOrEmpty() || text.isNullOrEmpty()
                        ) {
                            result.error("BAD_ARGUMENT", "id/channelId/title/text required", null)
                            return@setMethodCallHandler
                        }
                        val ok = showLiveUpdate(
                            id = id,
                            channelId = channelId,
                            title = title,
                            text = text,
                            shortCriticalText = shortCriticalText,
                            indeterminate = indeterminate,
                        )
                        result.success(ok)
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id")
                        if (id == null) {
                            result.error("BAD_ARGUMENT", "id required", null)
                            return@setMethodCallHandler
                        }
                        NotificationManagerCompat.from(this).cancel(id)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("LIVE_UPDATE_ERROR", e.message, null)
            }
        }
    }

    /** 设备是否可发 Promoted Ongoing（安卓 16+/HyperOS 3.1 且用户允许）。 */
    private fun canPostPromoted(): Boolean {
        return try {
            NotificationManagerCompat.from(this).canPostPromotedNotifications()
        } catch (e: Exception) {
            false
        }
    }

    /** 组装并发送实况通知；任何异常返回 false（增强功能，绝不 crash）。 */
    private fun showLiveUpdate(
        id: Int,
        channelId: String,
        title: String,
        text: String,
        shortCriticalText: String?,
        indeterminate: Boolean,
    ): Boolean {
        return try {
            ensureLiveChannel(channelId)
            val contentIntent = PendingIntent.getActivity(
                this,
                id,
                packageManager.getLaunchIntentForPackage(packageName)
                    ?: Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.drawable.ic_live_update)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setRequestPromotedOngoing(true)
                .setShowWhen(true)
                .setWhen(System.currentTimeMillis())
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
                .setContentIntent(contentIntent)
                .setColor(0xFF007AFF.toInt())
            // 状态栏 chip 短文案（系统硬约束 ≤6 字符）。按**字符数**截断：
            // TextUtils.ellipsize 的宽度参数单位是像素、非字符数（且新建
            // TextPaint 无字体度量），任何文案都会被压成单个「…」而使 chip 失效，
            // 故此处直接 substring 截断（Dart 侧文案本就已控制在 6 字符内）。
            if (!shortCriticalText.isNullOrEmpty()) {
                builder.setShortCriticalText(
                    if (shortCriticalText.length <= 6) {
                        shortCriticalText
                    } else {
                        shortCriticalText.take(6)
                    }
                )
            }
            // 进度样式（实况通知资格条件之一）：兼容层 NotificationCompat
            // 自带低版本降级（坑③：SDK<36 时 ProgressStyle 自动回退默认样式，
            // 绝不可引用 framework Notification.ProgressStyle）。
            // 回合无确定进度 → 不定量动画（勿伪造百分比）。
            val style = NotificationCompat.ProgressStyle()
                .setStyledByProgress(false)
            if (indeterminate) {
                style.setProgressIndeterminate(true)
            } else {
                style.setProgressIndeterminate(false)
                style.setProgress(1)
            }
            builder.setStyle(style)
            NotificationManagerCompat.from(this).notify(id, builder.build())
            true
        } catch (e: Exception) {
            false
        }
    }

    /** 创建实况通知渠道（importance=LOW + 无角标：LIVE 高频刷新不得加角标）。 */
    private fun ensureLiveChannel(channelId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(channelId) != null) return
        // channel 删除后重建时保持原名（系统约束，重复创建异常静默忽略）。
        try {
            val channel = NotificationChannel(
                channelId,
                "回合实况",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Agent 回合进行中实况通知（Live Update）"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        } catch (e: Exception) {
            // 渠道名冲突（删除后重建）等异常不阻断通知发送。
        }
    }

    companion object {
        private const val CHANNEL = "com.silentreader.hermes_ui/file_share"
        private const val LIVE_UPDATE_CHANNEL =
            "com.silentreader.hermes_ui/live_update"
    }
}
