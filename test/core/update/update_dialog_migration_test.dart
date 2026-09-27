// 批 5 · C4（下载 / 更新 / 引导系弹窗迁移）守卫。
//
// 钉死两件事（照批 5A 的写法，绝对数值 + 双档形态）：
//
// 1. **宽屏（>=900）**：五个迁移点全部出 [HermesDialogCard]，宽度 == 该点声明的
//    档位（写死绝对像素，不拿 `HermesDialogKind.width` 自证 —— 枚举被改坏时
//    自证型断言仍会全绿）；
// 2. **窄屏（<900）**：仍出系统 `CupertinoAlertDialog`（`CupertinoPopupSurface`
//    270 定宽），卡片一个都不能有，路由是 `CupertinoDialogRoute` 而非
//    `HermesDialogRoute` —— 即「窄屏逐像素不变」这条硬约束的被检点。
//
// 覆盖的五个迁移点（原 `showCupertinoDialog` + `CupertinoAlertDialog`）：
//
// | 迁移点 | 文件 | 档位 |
// |---|---|---|
// | 更新已加入下载队列 | `update_providers.handleDownloadOrOpenRelease` | confirm 380 |
// | 确认安装新版本 APK | `update_providers.promptInstallApk` | confirm 380 |
// | 安装未知应用权限引导 | `apk_installer.installApkWithPermissionGate` | confirm 380 |
// | 引导页连接/登录失败提示 | `onboarding_page._showErrorDialog` | confirm 380 |
// | 收藏提示词保存/删除提示 | `saved_prompts_sheet._showAlert` | confirm 380 |
//
// 五处全是「短文案 + 至多两个动作」的确认/警告框，故一律 confirm 380：本片
// 无表单（form 560）与长文本预览（wideForm 760）语义的弹窗。发布说明全文那枚
// （`settings_page.dart` 的 `releaseNotes`）才是 wideForm 760 的真实候选，它属
// settings 分区、不在本片文件清单内。
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/widgets/hermes_dialog.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/core/update/apk_installer.dart';
import 'package:hermes_ui/core/update/github_release.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/downloads/download_controller.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/features/onboarding/onboarding_page.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/prompts/widgets/saved_prompts_sheet.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_prompts_api.dart';

/// 宽屏（>=900）视口。
const Size _kWide = Size(1280, 800);

/// 窄屏（<900）视口 —— flutter_test 默认档。
const Size _kNarrow = Size(800, 600);

/// 本片五个迁移点的**绝对**期望宽度（一档都不许漂）。
const double _kConfirmWidth = 380.0;

const MethodChannel _channel = MethodChannel('test/c4_guard/apk_installer');

/// 更新资源（Android 路径命中 .apk 资产 → 入队 → 弹「已加入下载队列」）。
const GithubRelease _kRelease = GithubRelease(
  tagName: 'v0.1.60',
  htmlUrl: 'https://github.com/releases/v0.1.60',
  name: 'v0.1.60',
  assets: [
    ReleaseAsset(
      name: 'app-release.apk',
      browserDownloadUrl: 'https://example.com/app-release.apk',
      size: 1024,
    ),
  ],
);

/// 下载控制器 fake：入队返回固定 id，不落盘、不联网。
class _FakeDownloadController extends DownloadController {
  @override
  DownloadState build() => const DownloadState();

  @override
  Future<String> enqueue({
    String? sourceUrl,
    Uint8List? bytes,
    required String fileName,
    String? mimeType,
    int? expectedBytes,
    String? sessionId,
  }) async => 'fake-task-id';
}

/// 收藏提示词 API fake：create 成功但无回显 → 弹「保存失败」提示（红字正文）。
class _NullPromptApi extends FakePromptsApi {
  _NullPromptApi() : super(initialPrompts: const <SavedPrompt>[]);

  @override
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  }) async => const SavePromptResponse(ok: true, prompt: null);
}

/// 触发宿主（收 `WidgetRef`，供 `handleDownloadOrOpenRelease` 用）。
class _Trigger extends ConsumerWidget {
  const _Trigger({required this.onTap});

  final void Function(BuildContext context, WidgetRef ref) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoButton(
      key: const ValueKey('c4-trigger'),
      onPressed: () => onTap(context, ref),
      child: const Text('触发'),
    );
  }
}

/// 一个迁移点的开窗动作 + 期望仍存在的关键文案。
class _MigrationCase {
  const _MigrationCase({
    required this.label,
    required this.texts,
    required this.open,
  });

  final String label;

  /// 宽窄两档都必须仍在的文案（防「迁移顺手改文案」）：文案 → 期望命中数。
  final Map<String, int> texts;

  /// 在 [size] 视口下把弹窗开出来并结算入场转场。
  final Future<void> Function(WidgetTester tester, Size size) open;
}

/// 挂宿主：真主题 + 真中文本地化。
Future<void> _pumpHost(
  WidgetTester tester, {
  required Size size,
  required Widget home,
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      // 每次换新 key：同类型根件会被框架「更新」而非重建，上一档的弹窗路由
      // 会赖在 Navigator 上（宿主复用陷阱，批 5A 踩过）。
      key: UniqueKey(),
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        ...overrides,
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: home,
      ),
    ),
  );
  await tester.pump();
}

/// 结算 `CupertinoDialogRoute` 的入场弹簧（≈250ms）。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 宽屏断言：卡片在、系统 alert 不在、宽度 == [width]、路由是 Hermes 路由。
void _expectWideCard(WidgetTester tester, double width) {
  expect(find.byType(HermesDialogCard), findsOneWidget);
  expect(find.byType(CupertinoAlertDialog), findsNothing);
  final card = find.byKey(kHermesDialogCardKey);
  expect(card, findsOneWidget);
  expect(tester.getSize(card).width, width);
  expect(ModalRoute.of(tester.element(card)), isA<HermesDialogRoute<void>>());
}

/// 窄屏断言：仍是系统 alert + 270 定宽 + 原路由；卡片一个都不能有。
void _expectNarrowAlert(WidgetTester tester) {
  expect(find.byType(HermesDialogCard), findsNothing);
  expect(find.byKey(kHermesDialogCardKey), findsNothing);
  expect(find.byType(CupertinoAlertDialog), findsOneWidget);
  expect(tester.getSize(find.byType(CupertinoPopupSurface)).width, 270.0);
  final route = ModalRoute.of(
    tester.element(find.byType(CupertinoAlertDialog)),
  );
  expect(route, isA<CupertinoDialogRoute<void>>());
  expect(route, isNot(isA<HermesDialogRoute<void>>()));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  final cases = <_MigrationCase>[
    _MigrationCase(
      label: '更新已加入下载队列',
      texts: <String, int>{'软件更新': 1, '已加入下载队列，可在下载管理中查看进度': 1, '好': 1},
      open: (tester, size) async {
        await _pumpHost(
          tester,
          size: size,
          overrides: <Override>[
            downloadControllerProvider.overrideWith(
              _FakeDownloadController.new,
            ),
          ],
          home: CupertinoPageScaffold(
            child: Center(
              child: _Trigger(
                onTap: (context, ref) => handleDownloadOrOpenRelease(
                  context,
                  ref,
                  _kRelease,
                  platform: TargetPlatform.android,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('c4-trigger')));
        await _settle(tester);
      },
    ),
    _MigrationCase(
      label: '确认安装新版本 APK',
      texts: <String, int>{
        '软件更新': 1,
        '新版本已下载完成，是否立即安装？': 1,
        '取消': 1,
        '立即安装': 1,
      },
      open: (tester, size) async {
        await _pumpHost(
          tester,
          size: size,
          overrides: const <Override>[],
          home: CupertinoPageScaffold(
            child: Center(
              child: _Trigger(
                onTap: (context, ref) => promptInstallApk(
                  context,
                  '/data/app/hermes.apk',
                  // 注入 fake：不触碰系统包安装器。
                  apkInstaller: (_, _) async => true,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('c4-trigger')));
        await _settle(tester);
      },
    ),
    _MigrationCase(
      label: '安装未知应用权限引导',
      texts: <String, int>{'需要安装权限': 1, '去设置': 1, '取消': 1},
      open: (tester, size) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              _channel,
              (call) async => call.method == 'canRequestInstall' ? false : null,
            );
        await _pumpHost(
          tester,
          size: size,
          overrides: const <Override>[],
          home: CupertinoPageScaffold(
            child: Center(
              child: _Trigger(
                onTap: (context, ref) => installApkWithPermissionGate(
                  context,
                  '/data/app/hermes.apk',
                  channel: _channel,
                  launchIntent: (_) async {},
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('c4-trigger')));
        await _settle(tester);
      },
    ),
    _MigrationCase(
      label: '引导页连接失败提示',
      texts: <String, int>{'连接失败': 1, '好': 1},
      open: (tester, size) async {
        await _pumpHost(
          tester,
          size: size,
          overrides: <Override>[
            bundledWebuiAvailableProvider.overrideWithValue(false),
          ],
          home: const OnboardingPage(),
        );
        await tester.enterText(
          find.byKey(const ValueKey('onboarding-url')),
          'not-a-url',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('onboarding-connect')));
        await _settle(tester);
      },
    ),
    _MigrationCase(
      label: '收藏提示词保存失败提示',
      // 「收藏失败」同时是标题与正文（_showAlert 两处都传 savePromptFailed），
      // 故期望命中 2 个 —— 恰是「迁移没顺手改内容」的证据。
      texts: <String, int>{'收藏失败': 2, '好': 1},
      open: (tester, size) async {
        await _pumpHost(
          tester,
          size: size,
          overrides: <Override>[
            promptsApiFactoryProvider.overrideWithValue(
              (_) => _NullPromptApi(),
            ),
          ],
          home: CupertinoPageScaffold(
            child: SavedPromptsSheet(onInsert: (_) {}, currentInput: '要点'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(
          find.byKey(const ValueKey('saved-prompts-save-current')),
        );
        await _settle(tester);
      },
    ),
  ];

  group('C4 · 宽屏 1280 出卡片且宽度=档位（confirm 380）', () {
    for (final c in cases) {
      testWidgets('${c.label} → 380 卡片', (tester) async {
        await c.open(tester, _kWide);
        _expectWideCard(tester, _kConfirmWidth);
        for (final entry in c.texts.entries) {
          expect(
            find.text(entry.key),
            findsNWidgets(entry.value),
            reason: '文案缺失/重复：${entry.key}',
          );
        }
      });
    }
  });

  group('C4 · 窄屏 800 仍走系统 alert（逐像素不变）', () {
    for (final c in cases) {
      testWidgets('${c.label} → 仍 CupertinoAlertDialog', (tester) async {
        await c.open(tester, _kNarrow);
        _expectNarrowAlert(tester);
        for (final entry in c.texts.entries) {
          expect(
            find.text(entry.key),
            findsNWidgets(entry.value),
            reason: '文案缺失/重复：${entry.key}',
          );
        }
      });
    }
  });
}
