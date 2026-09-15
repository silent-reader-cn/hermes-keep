import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.silentreader.hermes_ui"
    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // flutter_secure_storage 等插件要求 compileSdk 37（Platform 37 已安装）
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 必需：Java 8+ API 脱糖（v10+ 要求）
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.silentreader.hermes_ui"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // flutter_local_notifications 必需（v10+ 要求 Java 8+ API 脱糖）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // MainActivity FileProvider（content:// URI 共享，Android 7+ 禁裸 file://）
    // #105 升至 1.18.0：NotificationCompat.ProgressStyle / setRequestPromotedOngoing /
    // NotificationManagerCompat.canPostPromotedNotifications（安卓 16 Live Updates 兼容层）。
    implementation("androidx.core:core-ktx:1.18.0")
    // #110：MainActivity 的 WorkManager 就绪兜底 + 诊断探针需要编译期依赖。
    // workmanager_android 用 implementation 引入 work-runtime（只进 runtime 类路径），
    // 不在 app 模块编译类路径上，故此处显式声明同版本（2.11.2，与插件一致）。
    implementation("androidx.work:work-runtime:2.11.2")
}

// ---------------------------------------------------------------------------
// #119 故障隔离：放宽 Flutter 生成的插件注册器的异常捕获。
//
// io.flutter.plugins.GeneratedPluginRegistrant 逐插件只 `catch (Exception)`，
// 任一插件在注册期抛 Error（典型：Rust/cargokit 插件缺 .so → UnsatisfiedLinkError）
// 会让整条注册循环就此中断，**其后所有插件静默失联**——引擎是用反射调用注册器并
// catch Exception 的，只留一行 logcat，应用不闪退，用户侧只表现为「某些功能莫名
// 不可用」（#119 的 url_launcher 打不开链接 + workmanager channel-error 即此）。
//
// 该文件在 android/.gitignore 内（插件集变化时由 flutter 工具重新生成），因此这里
// 在构建期就地放宽为 `catch (Throwable)`：单个插件失败只影响它自己，失败照常打日志。
// ---------------------------------------------------------------------------
val generatedPluginRegistrant =
    file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")

fun relaxPluginRegistrantCatch() {
    if (!generatedPluginRegistrant.isFile) return
    val original = generatedPluginRegistrant.readText()
    if (!original.contains("catch (Exception e)")) return
    generatedPluginRegistrant.writeText(
        original.replace("catch (Exception e)", "catch (Throwable e)"),
    )
    logger.lifecycle(
        "[hermes] GeneratedPluginRegistrant: catch(Exception) -> catch(Throwable)（#119 故障隔离）",
    )
}

// preBuild 覆盖所有变体；Java 编译任务是兜底（preBuild 缺席的非常规调用链）。
tasks.matching {
    it.name == "preBuild" ||
        (it.name.startsWith("compile") && it.name.endsWith("JavaWithJavac"))
}.configureEach {
    doFirst { relaxPluginRegistrantCatch() }
}

// ---------------------------------------------------------------------------
// #119 Rust/cargokit 产物（libsuper_native_extensions.so）拼包。
//
// cargokit 自己是把 build/jniLibs/<buildType> 挂到 `android.sourceSets` 上，但在
// AGP 8 + 本工程实测**不生效**：那个 srcDir 从未进入变体源集，.so 一次都没进过 APK
// （合并产物 merged_jni_libs / merged_native_libs 里始终没有它）。
//
// 后果不是「少个功能」而是连坐：SuperNativeExtensionsPlugin 静态块里
// System.loadLibrary("super_native_extensions") 抛 UnsatisfiedLinkError（Error，
// 而 GeneratedPluginRegistrant 只 catch Exception），整条插件注册链自该插件起被截断，
// 其后 url_launcher / wakelock_plus / workmanager 全部静默失联——引擎用反射调用
// 注册器并 catch Exception，只留一行 logcat，应用不闪退，用户侧只看到「某些功能
// 莫名不可用」（#119 的「打不开仓库链接」+「WorkManager channel-error」即此）。
//
// 这里改走 Flutter 自己也在用的变体 API：variant.sources.jniLibs 静态源目录
// （FlutterPlugin.kt 用同族 API 的 addGeneratedSourceDirectory 塞 libapp.so），
// 并显式依赖插件模块内的 cargo 构建任务，保证产物先落盘。
// ---------------------------------------------------------------------------
androidComponents {
    onVariants(selector().all()) { variant ->
        val buildType = variant.buildType ?: return@onVariants
        val cap = buildType.replaceFirstChar { it.uppercase() }
        val cargoJniLibs = rootProject.file("../build/super_native_extensions/jniLibs/$buildType")
        variant.sources.jniLibs?.addStaticSourceDirectory(cargoJniLibs.absolutePath)
        // cargo 任务在插件模块内；用字符串路径声明，任务不存在时构建直接报错（宁可响，不可静默）。
        val cargoTask = ":super_native_extensions:cargokitCargoBuildSuper_native_extensions${cap}"
        tasks.matching {
            it.name == "merge${cap}JniLibFolders" ||
                it.name == "merge${cap}NativeLibs" ||
                it.name == "strip${cap}DebugSymbols"
        }.configureEach { dependsOn(cargoTask) }
    }
}
