package com.silentreader.hermes_ui

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import androidx.work.Configuration
import androidx.work.WorkManager
import dev.fluttercommunity.plus.wakelock.WakelockPlusPlugin
import dev.fluttercommunity.workmanager.WorkmanagerPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.urllauncher.UrlLauncherPlugin
import java.io.File

class MainActivity : FlutterActivity() {
    /** WorkManager 冷启动兜底结果（探针用；onCreate 时记录）。 */
    private var workManagerCreation: Map<String, Any?> = emptyMap()

    /**
     * #110 兜底：WorkManager 必须在引擎注册插件之前就绪。
     *
     * `WorkmanagerPlugin.onAttachedToEngine()` 的顺序是「先构造再绑通道」——
     * `WorkManagerWrapper(applicationContext)`（内部 `WorkManager.getInstance()`）
     * 先执行，随后才 `WorkmanagerHostApi.setUp(...)`。前者抛异常则整个插件注册
     * 被 GeneratedPluginRegistrant 的 try/catch 吞掉（只打 logcat），pigeon 通道
     * 永不绑定，Dart 侧只能看到 channel-error，且同进程内重试无意义。
     *
     * 因此这里在 super.onCreate()（→ configureFlutterEngine → 插件注册）之前
     * 确保 WorkManager 已初始化，就地消灭「未初始化」这条成因。任何异常都不
     * 阻断启动，仅记录供探针归因。
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        workManagerCreation = ensureWorkManagerInitialized()
        super.onCreate(savedInstanceState)
    }

    /** 确保 WorkManager 已初始化（androidx.startup 已初始化时原样通过）。 */
    private fun ensureWorkManagerInitialized(): Map<String, Any?> {
        var firstFailure: Throwable? = null
        try {
            WorkManager.getInstance(applicationContext)
            return mapOf("creation" to "already-initialized", "error" to null)
        } catch (e: Throwable) {
            firstFailure = e
        }
        return try {
            // 只在 getInstance 已失败的前提下手动初始化；与 androidx.startup
            // 重复初始化会抛 IllegalStateException，同样被下方捕获。
            WorkManager.initialize(applicationContext, Configuration.Builder().build())
            mapOf(
                "creation" to "manual-initialize",
                "error" to describeThrowable(firstFailure),
            )
        } catch (e: Throwable) {
            mapOf(
                "creation" to "manual-initialize-failed",
                "error" to describeThrowable(firstFailure ?: e),
            )
        }
    }

    /**
     * #118 插件链探针：Rust/cargokit 库能否加载 + 尾部插件是否真有实例。
     *
     * GeneratedPluginRegistrant 逐插件只 catch Exception，任一插件在注册期抛
     * Error（缺 .so → UnsatisfiedLinkError）会截断整条注册链，其后插件全部静默
     * 失联。这两项直接指认「当前这次运行是不是被连坐」：rustLib 报错 + 后三个
     * 插件 false，就是典型的「链被上游插件截断」。
     */
    private fun probePluginChain(engine: FlutterEngine?): Map<String, Any?> {
        val rustLib: String = try {
            System.loadLibrary("super_native_extensions")
            "loaded"
        } catch (t: Throwable) {
            describeThrowable(t) ?: "load-failed"
        }
        val attached: (Class<out FlutterPlugin>) -> Any = { cls ->
            try {
                engine?.plugins?.get(cls) != null
            } catch (t: Throwable) {
                describeThrowable(t) ?: "probe-failed"
            }
        }
        return mapOf(
            "rustLib" to rustLib,
            "urlLauncher" to attached(UrlLauncherPlugin::class.java),
            "wakelock" to attached(WakelockPlusPlugin::class.java),
            "workmanager" to attached(WorkmanagerPlugin::class.java),
        )
    }

    /** 探针：报告当下 WorkManager 是否可用 + 冷启动兜底动作 + 异常描述。 */
    private fun probeWorkManagerNow(): Map<String, Any?> {
        val failure: String? = try {
            WorkManager.getInstance(applicationContext)
            null
        } catch (e: Throwable) {
            describeThrowable(e)
        }
        return mapOf(
            "initialized" to (failure == null),
            "creation" to (workManagerCreation["creation"] ?: "unknown"),
            "error" to (failure ?: workManagerCreation["error"]),
        )
    }

    private fun describeThrowable(t: Throwable?): String? =
        t?.let { "${it.javaClass.name}: ${it.message}" }

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

        // #110 诊断探针通道：把 WorkManager 初始化状态暴露给 Dart 侧诊断日志，
        // release 包无需连 adb 也能判定 channel-error 的成因。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KEEPALIVE_PROBE_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "probeWorkManager" -> result.success(probeWorkManagerNow())
                    "probePluginChain" -> result.success(probePluginChain(flutterEngine))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("PROBE_ERROR", e.message, null)
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
                // #114 small icon：应用标识的单色剪影（alpha-only，系统按语境着色）。
                // 展开态大图标位另由 largeIcon 承担，二者职责不同。
                .setSmallIcon(R.drawable.ic_hermes_agent)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setRequestPromotedOngoing(true)
                .setShowWhen(true)
                .setWhen(System.currentTimeMillis())
                .setUsesChronometer(true)
                // #114 修正计时方向：原先 countDown=true 使岛/通知显示「-02:09」
                // 一路往下跳，语义错误。回合进行中应正计时，表达"已经跑了多久"。
                .setChronometerCountDown(false)
                .setContentIntent(contentIntent)
                .setColor(0xFF007AFF.toInt())
            // #114 largeIcon：展开态/岛展开态的大图标位——**支持彩色位图**，直接摆真应用
            // 图标。此前从未设置该项，系统只能回落到 small icon，于是主人在岛上看到的永远
            // 是那枚单色 H（本次修复的根因）。用自适应图标而非位图：它自带 66% 安全区，被
            // HyperOS 裁成圆形时不会切到主体。本版 androidx 的 setLargeIcon 无 IconCompat
            // 重载（编译期实测），故用 framework Icon 并加 API 23 守卫（Android 16 恒满足）。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                builder.setLargeIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            }
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
        private const val KEEPALIVE_PROBE_CHANNEL =
            "com.silentreader.hermes_ui/keepalive_probe"
        private const val LIVE_UPDATE_CHANNEL =
            "com.silentreader.hermes_ui/live_update"
    }
}
