import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/downloads/download_page.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_chat_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 批次 5 · C5「最后 12 处弹窗调用点迁移」真渲染目检工装
// （**非金照基线，不参与 CI**）
//
// 用法（改动前后各跑一次，同一份工装 → 图可直接对照）：
//   C5_SHOTS=1 C5_SHOTS_TAG=before C:/tmp/f.bat test \
//       test/screenshots/c5_dialogs_shots_test.dart --update-goldens
//   …落码后再把 TAG 换成 after 跑一次。不带 C5_SHOTS=1 时全部 skip。
//
// 产物：`.shots/c5/<tag>/<name>-<light|dark>.png`
//
// 覆盖两个**必检**弹窗 + 一个同族确认框（各浅/暗 × 宽/窄）：
//   1. `chat-rename` —— 重命名会话（form 560 表单：含输入框）；
//   2. `chat-delete` —— 删除会话确认（confirm 380）；
//   3. `download-notice` —— 下载文件缺失提示（confirm 380）。
//
// 三个都走**真实调用点**：前两个经真实聊天页「⋯」菜单触发（真 `ChatPage`
// + fake API），第三个经公开函数 `openDownloadedFile`。工装不修改任何
// `lib/` 代码、不注入测试专用 UI。
//
// **窄屏对照的意义**：同一份工装在落码前（`before`）与落码后（`after`）各跑一次，
// 两张 `*-narrow.png` 必须**逐字节相同** —— 这是「窄屏逐像素不变」的硬证据
// （宽屏那几张则应当变化：270 窄条 → 档位卡片）。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip。
final bool _capture = Platform.environment['C5_SHOTS'] == '1';

/// 产物子目录标签（before / after），默认 after。
final String _tag = Platform.environment['C5_SHOTS_TAG'] ?? 'after';

const String _shotRoot = '../../.shots/c5';

/// 宽屏物理像素（逻辑 1280×800 @2x；≥ kAdaptiveBreakpoint=900）。
const Size _wideSize = Size(2560, 1600);

/// 窄屏物理像素（逻辑 800×1200 @2x；< 900 → 系统弹窗形态）。
///
/// 高度刻意不用 600：窄屏「⋯」菜单是底部行动表，600 高时末项「删除」被裁在
/// 视口外 —— `tester.tap` 会静默 miss（实测踩过：窄屏删除那组截出来是菜单而
/// 不是弹窗）。宽度才是断点判据（800 < 900 仍是窄屏），故抬高到 1200 让全部
/// 菜单项可见可点。
const Size _narrowSize = Size(1600, 2400);

/// 不存在的文件路径（下载提示弹窗的触发面）。
final String _kMissingPath =
    '${Directory.systemTemp.path}${Platform.pathSeparator}__hermes_c5_missing__.bin';

/// 下载提示弹窗宿主：真实主题 + 最小页面，只有一个「打开已下载文件」按钮
/// （产品里该弹窗由下载页/文件预览页触发；此处只取最小触发面）。
class _DownloadLauncherPage extends StatelessWidget {
  const _DownloadLauncherPage();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('下载提示 · 宽屏目检宿主'),
      ),
      child: Center(
        child: CupertinoButton.filled(
          key: const ValueKey('c5-shots-open-file'),
          onPressed: () {
            unawaited(openDownloadedFile(context, _kMissingPath));
          },
          child: const Text('打开已下载文件'),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    // 点不中就说明这张图拍错了对象 —— 直接判失败，别产出「菜单照」冒充弹窗照。
    WidgetController.hitTestWarningShouldBeFatal = true;
    await loadHermesGoldenFonts();
  });

  tearDownAll(() {
    WidgetController.hitTestWarningShouldBeFatal = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 挂载真实聊天页（演示会话：一个提问 + 一个回答）。
  Widget chatHome() {
    final api = FakeChatApi()
      ..sessionResult = <String, Object?>{
        'session': <String, Object?>{
          'session_id': 's1',
          'title': 'Hermes 仓 CI 巡检',
          'messages': <Object?>[
            <String, Object?>{
              'role': 'user',
              'content': '帮我看下今天的构建结果',
              'message_id': 'u1',
            },
            <String, Object?>{
              'role': 'assistant',
              'content': 'analyze 零告警，全量测试全绿。',
              'message_id': 'a1',
            },
          ],
        },
      };
    return ProviderScope(
      overrides: <Override>[
        chatApiProvider.overrideWithValue(api),
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: InMemorySecureStorage()),
        ),
      ],
      child: const ChatPage(sessionId: 's1'),
    );
  }

  /// 挂载 [home] → [interact] 触发弹窗 → 截图。
  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Widget home,
    required Brightness brightness,
    required Size size,
    required Future<void> Function(WidgetTester tester) interact,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'https://hermes.example.com:8787'),
          ),
        ],
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: buildCupertinoTheme(brightness),
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await interact(tester);
    // 菜单关闭 + 弹窗入场（Cupertino 弹簧 ≈250ms）全部结算后再截。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    Directory('$_shotRoot/$_tag').createSync(recursive: true);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile(
        '$_shotRoot/$_tag/$name-${brightness == Brightness.dark ? 'dark' : 'light'}.png',
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> openSessionMenuItem(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(ValueKey(key)));
  }

  /// 同一触发路径出「宽屏 / 窄屏」两组（每组浅暗两张）。
  void shotGroups(
    String title,
    Widget Function() home,
    Future<void> Function(WidgetTester tester) Function() interact,
  ) {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.dark ? '暗色' : '浅色';
      final flavor = brightness == Brightness.dark ? 'dark' : 'light';

      testWidgets('宽屏$suffix · $title', (tester) async {
        await capture(
          tester,
          name: '$title-wide-$flavor'.replaceAll('/', '-'),
          home: home(),
          brightness: brightness,
          size: _wideSize,
          interact: interact(),
        );
      }, skip: !_capture);

      testWidgets('窄屏$suffix · $title', (tester) async {
        await capture(
          tester,
          name: '$title-narrow-$flavor'.replaceAll('/', '-'),
          home: home(),
          brightness: brightness,
          size: _narrowSize,
          interact: interact(),
        );
      }, skip: !_capture);
    }
  }

  // -------------------------------------------------------------------------
  // 1. 重命名会话（form 560）—— 必检组 1
  // -------------------------------------------------------------------------
  shotGroups(
    'chat-rename-560',
    chatHome,
    () => (tester) => openSessionMenuItem(tester, 'chat-action-rename'),
  );

  // -------------------------------------------------------------------------
  // 2. 删除会话确认（confirm 380）—— 必检组 2
  // -------------------------------------------------------------------------
  shotGroups(
    'chat-delete-380',
    chatHome,
    () => (tester) => openSessionMenuItem(tester, 'chat-action-delete'),
  );

  // -------------------------------------------------------------------------
  // 3. 下载文件缺失提示（confirm 380）—— 同族确认框抽样
  // -------------------------------------------------------------------------
  shotGroups(
    'download-notice-380',
    () => const _DownloadLauncherPage(),
    () => (tester) async {
      await tester.tap(find.byKey(const ValueKey('c5-shots-open-file')));
    },
  );
}
