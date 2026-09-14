import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';

/// 截图逻辑尺寸（iPhone 12/13/14 尺寸 390x844，2x 物理像素）。
const Size goldenSurfaceSize = Size(780, 1688);

/// 截图物理像素比（2x 保证放大查对比度/溢出时文字清晰）。
const double goldenDevicePixelRatio = 2.0;

/// 横屏桌面档截图物理像素尺寸（逻辑 1280×800 @2x，Windows 桌面常用窗口档；
/// 逻辑宽 1280 ≥ kAdaptiveBreakpoint=900，触发宽屏双栏形态）。
const Size goldenLandscapeSize = Size(2560, 1600);

/// 注册真实字体：flutter_test 默认全部走 Ahem 方块字，截图无法人工核对。
///
/// - [loadAppFonts]：应用 FontManifest（MaterialIcons + CupertinoIcons）；
/// - Roboto：引擎默认字族（fontFamily 缺省文本）英文 + 粗体；
/// - CJK 回退（见 [cjkFallbackFontCandidates]）：Windows 宿主用系统 SimHei，
///   其余宿主（CI Linux/macOS）退回仓库自带 MiSans，避免中文渲染成豆腐块、
///   导致本平台基线无法人工核对；同时覆盖 CupertinoTextThemeData 默认的
///   CupertinoSystemText/Display 字族。
///
/// 字体文件缺失的环境静默跳过（[File.existsSync] 为假）。**金照基线按平台
/// 分目录**（`test/golden/goldens/<平台>/`，见 golden_platform.dart），各平台
/// 用自己的字体渲染、与自己那份基线比对，故不存在跨平台字形漂移问题。
Future<void> loadHermesGoldenFonts() async {
  await loadAppFonts();
  // flutter_tester.exe → <flutter>/bin/cache/artifacts/engine/<platform>/，
  // 向上 6 级即 Flutter SDK 根目录。
  final exe = File(Platform.resolvedExecutable);
  final flutterRoot = exe.parent.parent.parent.parent.parent.parent.path;
  final materialFontsDir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await _registerFontFile('Roboto', '$materialFontsDir/roboto-regular.ttf');
  await _registerFontFile('Roboto', '$materialFontsDir/roboto-bold.ttf');
  // CJK 回退字体：Windows 宿主用系统 simhei，其余宿主退回仓库自带 MiSans。
  // 各平台基线独立成目录，故字体差异不会造成跨平台假红。
  await _registerFontFirstExisting('Roboto', cjkFallbackFontCandidates);
  await _registerFontFirstExisting(
    'CupertinoSystemText',
    cjkFallbackFontCandidates,
  );
  await _registerFontFirstExisting(
    'CupertinoSystemDisplay',
    cjkFallbackFontCandidates,
  );
  // 注册全局字体 MiSans（保证无论环境是否加载 asset bundle，字族都完整注册）
  await _registerFontFile('MiSans', 'assets/fonts/MiSans-Regular.ttf');
  await _registerFontFile('MiSans', 'assets/fonts/MiSans-Medium.ttf');
  // 注册等宽字体 monospace（用于代码块、git diff 等）
  // 已知坑：flutter_tester 同族多注册按「先注册者胜」解析、无按字形族内回退，
  // consola/cour 无 CJK 字形 → monospace 族里的中文文本（如安装向导日志台
  // 「等待安装启动...」）在金照环境渲染为豆腐块。把 simhei 提到族首可修豆腐
  // 块，但会改变 chat 等既有金照的拉丁等宽字形基线，故全局维持 consola 族首；
  // 含中文等宽文本的新金照文件可在自身 setUpAll 里先于本函数注册
  // monospace→CJK 字体做局部修复（见 golden_onboarding_wide_test.dart）。
  await _registerFontFile('monospace', r'C:\Windows\Fonts\consola.ttf');
  await _registerFontFile('monospace', r'C:\Windows\Fonts\cour.ttf');
  await _registerFontFile('monospace', 'assets/fonts/MiSans-Regular.ttf');
}

/// 把某字体文件注册进 [family]（文件不存在时静默跳过）。
Future<void> _registerFontFile(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Windows 系统中文字体（SimHei）路径。
const String simheiFontPath = 'C:\\Windows\\Fonts\\simhei.ttf';

/// CJK 回退字体候选（按序取第一个存在的文件）。
///
/// 顺序只需保证**同一平台内稳定**：Windows 命中 SimHei，其余平台退回仓库自带
/// MiSans。各平台基线独立成目录，故不同平台取到不同字体是预期行为。
final List<String> cjkFallbackFontCandidates = <String>[
  simheiFontPath,
  'assets/fonts/MiSans-Regular.ttf',
];

/// 返回 [candidates] 中第一个存在的字体文件路径；都不存在则返回 null。
String? firstExistingFont(List<String> candidates) {
  for (final path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  return null;
}

/// 把 [candidates] 里第一个存在的字体注册进 [family]（都不存在则静默跳过）。
Future<void> _registerFontFirstExisting(
  String family,
  List<String> candidates,
) async {
  for (final path in candidates) {
    if (File(path).existsSync()) {
      await _registerFontFile(family, path);
      return;
    }
  }
}

/// 以 [brightness] 主题挂载 [page]（注入 [overrides]），等异步加载与入场动画
/// 结算后返回（适合接 matchesGoldenFile 截图）。
///
/// 金照统一钉死中文 locale（L2 起服务层文案随 LocaleResolver 变化，
/// 而金照基线在中文环境生成；CI/开发机系统语言不影响）。
/// 双保险：test/flutter_test_config.dart 已全局钉，这里显式再钉一次防单文件绕过。
void pinGoldenLocale() => LocaleResolver.reset(mode: AppLocaleMode.zh);

/// 泵入被测页面并结算动画。
///
/// [size] 缺省为竖屏 [goldenSurfaceSize]；需要横屏的页面（如 workspace）
/// 可传 [goldenLandscapeSize]。
Future<void> pumpHermesPage(
  WidgetTester tester, {
  required Widget page,
  required Brightness brightness,
  List<Override> overrides = const [],
  Size size = goldenSurfaceSize,
}) async {
  pinGoldenLocale();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = goldenDevicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: page,
      ),
    ),
  );
  // 首帧（AsyncLoading）→ 异步 build 完成（AsyncData）→ 入场动画/图表动画结算
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 卸载页面并释放 ProviderScope（让控制器 dispose 取消定时器，避免 pending timer）。
Future<void> unmountHermesPage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}