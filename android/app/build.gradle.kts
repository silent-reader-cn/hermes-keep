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
