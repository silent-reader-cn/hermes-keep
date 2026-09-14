import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/llm_onboarding.dart';
import 'package:hermes_ui/core/install/powershell_installer.dart';
import 'package:hermes_ui/core/install/webui_bootstrap.dart';
import 'package:hermes_ui/features/onboarding/install_guide_page.dart';
import 'package:hermes_ui/features/onboarding/onboarding_page.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden_helpers.dart';
import 'golden_platform.dart';

// ---------------------------------------------------------------------------
// 引导体系宽屏双栏金照（规格 .todo/active.md 宽屏双栏铁律·验收4）
//
// Windows 桌面尺寸档（逻辑 1280×800 ≥ kAdaptiveBreakpoint=900），验证
// WideDualPane 新形态：左品牌氛围区（OnboardingBrandPane）+ 右单列功能区
// （maxWidth 460 居中）。深浅两态各一枚，共 4 张 PNG。
//
// 形态说明：本文件只覆盖「形态 B 远程连接表单」——测试机即便跑在 Windows
// 宿主上（Platform.isWindows==true），也显式 override
// bundledWebuiAvailableProvider=false 钉死非打包态，形态 A（内置服务 Tab）
// 不在此金照范围（其依赖打包资源，CI 不可复现）。
// ---------------------------------------------------------------------------

/// 横屏宽屏对：注册 [pageName] 浅色 + 深色两枚金照（[goldenLandscapeSize]
/// 桌面档，PNG 输出到 test/golden/goldens/<平台>/）。
void goldenWidePair(
  String pageName, {
  required Widget Function() page,
  required List<Override> Function() overrides,
}) {
  for (final brightness in Brightness.values) {
    final themeName = brightness == Brightness.light ? 'light' : 'dark';
    testWidgets('$pageName wide $themeName', (tester) async {
      // 金照基线按平台分目录：本平台无基线时跳过（不是回归）。
      final name = '${pageName}_$themeName';
      if (skipIfNoGoldenBaseline(name)) return;
      await pumpHermesPage(
        tester,
        page: page(),
        brightness: brightness,
        overrides: overrides(),
        size: goldenLandscapeSize,
      );
      // 品牌区入场序列总长 1200ms（hero motion），pumpHermesPage 只结算到
      // 400ms——直接截图会定格在「slogan 未淡入」的半途帧。这里补泵到
      // 入场完成后的稳定态（fake-async 下时序确定；12s 呼吸循环在 ~100ms
      // 处缩放 ≈1.00002，像素级不可见且逐次一致）。
      await tester.pump(const Duration(milliseconds: 900));
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile(goldenKey(name)),
      );
      await unmountHermesPage(tester);
    });
  }
}

/// 假安装探测：isWindows=true 让安装向导走 WideDualPane 主内容
/// （否则渲染「仅支持 Windows」占位）。与
/// test/features/onboarding/install_guide_page_test.dart 同款。
class _FakeInstallDetector implements InstallDetector {
  _FakeInstallDetector();

  @override
  bool isWindows = true;

  @override
  String get localAppDataPath => r'C:\Users\Admin\AppData\Local';
  @override
  String get hermesHomePath => r'C:\Users\Admin\AppData\Local\hermes';
  @override
  String get hermesAgentPath =>
      r'C:\Users\Admin\AppData\Local\hermes\hermes-agent';
  @override
  String get webuiPath => r'C:\Users\Admin\AppData\Local\hermes\webui';

  @override
  Future<bool> agentInstalled() async => false;

  @override
  bool bundledWebuiAvailable() => false;

  @override
  Future<bool> isInstalled() => agentInstalled();
}

/// 假安装器（金照停在 idle 态不触发，仅为隔离真实文件系统/进程副作用）。
class _FakePowershellInstaller implements PowershellInstaller {
  _FakePowershellInstaller();

  @override
  Future<String> ensureScriptCached({
    String url = PowershellInstaller.defaultScriptUrl,
    String? destinationPath,
  }) async =>
      destinationPath ?? r'C:\Users\Admin\AppData\Local\hermes\install.ps1';

  @override
  Future<List<String>> getManifest({String? scriptPath}) async =>
      ['prereqs', 'agent', 'deps'];

  @override
  Stream<InstallerEvent> runStage(
    String stageName, {
    String? scriptPath,
    String? hermesHome,
  }) async* {
    yield InstallerEvent.stageStart(stageName, title: 'Starting $stageName');
    yield InstallerEvent.stageSuccess(stageName, message: '$stageName ok');
  }
}

/// 假 WebUI 自举（同上，隔离副作用）。
class _FakeWebuiBootstrap implements WebuiBootstrap {
  _FakeWebuiBootstrap();

  @override
  Future<bool> waitForHealth({
    String baseUrl = 'http://127.0.0.1:8787',
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 500),
  }) async =>
      true;

  @override
  String resolvePythonPath() => 'python.exe';
}

/// 假模型配置 API（同上，隔离副作用）。
class _FakeLlmOnboardingApi implements LlmOnboardingApi {
  _FakeLlmOnboardingApi();

  @override
  Future<bool> saveConfig({
    required String serverBaseUrl,
    required LlmOnboardingConfig config,
  }) async =>
      true;
}

/// 在本 isolate 内把 CJK 字体抢先注册为 monospace 族（见 main 的 setUpAll 注释）。
///
/// 候选顺序见 [cjkFallbackFontCandidates]：Windows 命中 SimHei，其余平台退回
/// 仓库自带 MiSans。各平台基线独立成目录，故字体差异不会造成跨平台假红。
Future<void> _registerMonospaceCjk() async {
  final path = firstExistingFont(cjkFallbackFontCandidates);
  if (path == null) return;
  final bytes = File(path).readAsBytesSync();
  await (FontLoader('monospace')
        ..addFont(Future.value(ByteData.sublistView(bytes))))
      .load();
}

void main() {
  setUpAll(() async {
    // monospace→SimHei 抢先注册：flutter_tester 同族多注册「先注册者胜」
    // （golden_helpers.dart 已知坑注释）。本文件金照含中文等宽文本
    // （日志台「等待安装启动...」），故在本 isolate 内先把 CJK 字体注册为
    // monospace 族首，避免豆腐块；仅影响本测试文件，不改 chat 等既有金照
    // 的拉丁等宽字形基线。
    await _registerMonospaceCjk();
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // U2 引导页（形态 B 远程表单）宽屏双栏：左品牌氛围区 + 右 URL 表单列。
  goldenWidePair(
    'onboarding_wide',
    page: () => const OnboardingPage(),
    overrides: () => [
      // 钉死形态 B：不依赖测试机是否存在打包 WebUI（Windows 宿主上
      // Platform.isWindows 为 true，仅靠 bundle 探测会漂移）。
      bundledWebuiAvailableProvider.overrideWithValue(false),
    ],
  );

  // U3 本机部署向导宽屏双栏：idle 态（4 步骤列表 + 日志台 + 开始按钮）。
  goldenWidePair(
    'install_guide_wide',
    page: () => const InstallGuidePage(),
    overrides: () => [
      installDetectorProvider.overrideWithValue(_FakeInstallDetector()),
      powershellInstallerProvider.overrideWithValue(_FakePowershellInstaller()),
      webuiBootstrapProvider.overrideWithValue(_FakeWebuiBootstrap()),
      llmOnboardingApiProvider.overrideWithValue(_FakeLlmOnboardingApi()),
    ],
  );
}
