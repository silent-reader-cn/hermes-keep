import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/widgets/hermes_dialog.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/endpoints.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/media_cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/platform/external_opener.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/downloads/download_page.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_download_service.dart';
import '../../helpers/fake_media_cache.dart';
import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 批次 5 · C5「最后 12 处弹窗调用点迁移」守卫。
//
// 钉死三件事（都不是「看起来差不多」）：
//
// 1. **源级**：C5 文件级分区内的四个文件里 `showCupertinoDialog` 零残留，
//    `showHermesDialog` 调用点数与**档位序列**逐项等于 C5 分档表；
// 2. **宽屏渲染**：每个真实调用点（走产品 UI 触发路径）在 1280 下出
//    `HermesDialogCard`，卡片实际宽度 == 该档绝对像素（380/460/560/760），
//    且**没有**系统 alert；
// 3. **窄屏回退**：同一条触发路径在 800 下仍是 `CupertinoAlertDialog` +
//    内部 270 定宽（逐像素不变的结构保证），卡片一个都不出。
//
// 档位表刻意写死「绝对像素 + 绝对 kind 名」，不拿 `HermesDialogKind.width`
// 自证 —— 枚举被改坏时那种写法照样全绿（批 5A 的 RED 教训）。
//
// 未纳入渲染守卫的两处（**仍由源级守卫覆盖**，理由见文件末尾 §未纳入说明）：
// `download_page` 的 Android 安装权限闸门（Windows 宿主不可达）、
// `webui_sidecar_section` 的缺 agent 提示（需要整套 sidecar 存储假件）。
// ---------------------------------------------------------------------------

/// 本片四文件 → 迁移后应有的**档位序列**（按源码出现次序）。
///
/// 注释里逐处写明语义依据（分档规则的四个判据：确认/警告 · 单选 · 表单 ·
/// 长文本）。改档位要先改这张表 —— 这是刻意的手工摩擦。
const Map<String, List<String>> _kMigratedFiles = <String, List<String>>{
  'lib/features/chat/chat_page.dart': <String>[
    'confirm', // _showParentSessionDialog —— 分支会话信息框 + 2 动作
    'form', // _renameSession —— 含输入框
    'confirm', // _confirmSessionDelete —— 破坏性确认
    'form', // _compressSession —— 含「聚焦主题」输入框
    'confirm', // _confirmSessionUndo —— 破坏性确认
    'wideForm', // _exportSession 成功 —— 正文可能是很长的落盘路径
    'confirm', // _exportSession 失败 —— 失败提示
  ],
  'lib/features/chat/widgets/chat_media_view.dart': <String>[
    'confirm', // _MediaRefreshButton 刷新失败提示
  ],
  'lib/features/downloads/download_page.dart': <String>[
    'confirm', // _installApkWithPermissionGate 授权引导
    'confirm', // openDownloadedFile 文件不存在提示
    'confirm', // openDownloadedFile 打开异常提示
  ],
  'lib/features/settings/webui_sidecar_section.dart': <String>[
    'confirm', // _showMissingAgentDialog 阻断型提示（3 动作）
  ],
};

/// 档位 → 宽屏卡片**绝对**宽度（px）。四档逐值写死。
const Map<HermesDialogKind, double> _kWaist = <HermesDialogKind, double>{
  HermesDialogKind.confirm: 380.0,
  HermesDialogKind.picker: 460.0,
  HermesDialogKind.form: 560.0,
  HermesDialogKind.wideForm: 760.0,
};

/// 宽屏视口（逻辑 1280×2000：宽 ≥ 900 触发宽屏；高 2000 免会话菜单被裁剪）。
const Size _kWide = Size(1280, 2000);

/// 窄屏视口（逻辑 800×2000，宽 < 900；高度同宽屏口径，排除菜单裁剪干扰）。
const Size _kNarrow = Size(800, 2000);

/// 中文文案（守卫断言标题用真 l10n，不硬编码字符串）。
const AppLocalizations _l10n = AppLocalizations(Locale('zh'));

/// 一个「可驱动的迁移点」：真实触发路径 → 期望档位 + 期望标题。
class _Site {
  _Site({
    required this.name,
    required this.kind,
    required this.title,
    required this.drive,
  });

  /// 用例名（含文件与档位）。
  final String name;

  /// 期望档位（宽屏卡片宽度由此查表）。
  final HermesDialogKind kind;

  /// 期望标题文案（确认「开的是这一个弹窗」，不只看「有弹窗」）。
  final String title;

  /// 触发路径（真实产品 UI；不直接调 dialog 函数）。
  final Future<void> Function(WidgetTester tester, Size size) drive;
}

/// C5 十个**可驱动**迁移点（12 处里除 §未纳入说明 的两处）。
final List<_Site> _sites = <_Site>[
  _Site(
    name: 'chat_page · 分支会话信息框（confirm 380）',
    kind: HermesDialogKind.confirm,
    title: _l10n.branchSession,
    drive: (tester, size) async {
      await _pumpChat(
        tester,
        size,
        api: FakeChatApi()..sessionResult = _session(parent: 'parent-9'),
      );
      await tester.tap(find.byKey(const ValueKey('chat-branch-badge')));
      await _settleDialog(tester);
    },
  ),
  _Site(
    name: 'chat_page · 重命名会话（form 560）',
    kind: HermesDialogKind.form,
    title: _l10n.renameSession,
    drive: (tester, size) async {
      await _pumpChat(
        tester,
        size,
        api: FakeChatApi()..sessionResult = _session(),
      );
      await _tapSessionMenuItem(tester, 'chat-action-rename');
    },
  ),
  _Site(
    name: 'chat_page · 删除会话确认（confirm 380）',
    kind: HermesDialogKind.confirm,
    title: _l10n.deleteSession,
    drive: (tester, size) async {
      await _pumpChat(
        tester,
        size,
        api: FakeChatApi()..sessionResult = _session(),
      );
      await _tapSessionMenuItem(tester, 'chat-action-delete');
    },
  ),
  _Site(
    name: 'chat_page · 压缩会话（form 560）',
    kind: HermesDialogKind.form,
    title: _l10n.compressSession,
    drive: (tester, size) async {
      await _pumpChat(
        tester,
        size,
        api: FakeChatApi()..sessionResult = _session(),
      );
      await _tapSessionMenuItem(tester, 'chat-action-compress');
    },
  ),
  _Site(
    name: 'chat_page · 撤销上一轮确认（confirm 380）',
    kind: HermesDialogKind.confirm,
    title: _l10n.undoLastTurn,
    drive: (tester, size) async {
      await _pumpChat(
        tester,
        size,
        api: FakeChatApi()..sessionResult = _session(),
      );
      await _tapSessionMenuItem(tester, 'chat-action-undo');
    },
  ),
  _Site(
    name: 'chat_page · 导出成功（wideForm 760）',
    kind: HermesDialogKind.wideForm,
    title: _l10n.exportSuccessDialogTitle,
    drive: (tester, size) async {
      await _pumpChat(
        tester,
        size,
        api: FakeChatApi()..sessionResult = _session(),
        apiClient: _ExportStubApiClient(),
      );
      await _tapSessionMenuItem(tester, 'chat-action-export');
    },
  ),
  _Site(
    name: 'chat_page · 导出失败（confirm 380）',
    kind: HermesDialogKind.confirm,
    title: _l10n.exportFailed,
    drive: (tester, size) async {
      await _pumpChat(
        tester,
        size,
        api: FakeChatApi()..sessionResult = _session(),
        apiClient: _ExportStubApiClient(
          throwError: HttpException(500, null, message: '导出通道错误'),
        ),
      );
      await _tapSessionMenuItem(tester, 'chat-action-export');
    },
  ),
  _Site(
    name: 'chat_media_view · 媒体刷新失败（confirm 380）',
    kind: HermesDialogKind.confirm,
    title: _l10n.refreshFailed,
    drive: (tester, size) async {
      final cache = _ThrowingRefreshCache(
        Directory.systemTemp.createTempSync('hermes_c5_media_'),
        AppDatabase.memory(),
      );
      addTearDown(cache.dispose);
      await _pumpHost(
        tester,
        size,
        home: const AttachmentLightbox(
          bytes: null,
          resolvedUrl: _kMediaUrl,
          name: 'pic.png',
          isImage: true,
        ),
        overrides: <Override>[
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          mediaCacheOverride(cache),
          ...createDownloadTestOverrides(db: cache.database),
        ],
      );
      await tester.tap(find.byKey(_kRefreshKey));
      await _settleDialog(tester);
    },
  ),
  _Site(
    name: 'download_page · 文件已被移动或删除（confirm 380）',
    kind: HermesDialogKind.confirm,
    title: _l10n.notice,
    drive: (tester, size) async {
      await _pumpHost(
        tester,
        size,
        home: _OpenFileLauncherPage(
          key: const ValueKey('c5-download-missing'),
          path: _kMissingPath,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('c5-open-file')));
      await _settleDialog(tester);
    },
  ),
  _Site(
    name: 'download_page · 打开文件失败（confirm 380）',
    kind: HermesDialogKind.confirm,
    title: _l10n.downloadOpenFileFailed,
    drive: (tester, size) async {
      final file = File(_kExistingPath)..writeAsBytesSync(<int>[0]);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      await _pumpHost(
        tester,
        size,
        home: _OpenFileLauncherPage(
          key: const ValueKey('c5-download-openfail'),
          path: _kExistingPath,
          // 接缝注入一个必抛的执行器：走 `openDownloadedFile` 的 catch 分支。
          opener: ExternalOpener(
            isWindows: true,
            processRunner: (executable, arguments) async =>
                throw StateError('explorer 起不来'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('c5-open-file')));
      await _settleDialog(tester);
    },
  ),
];

/// 临时目录下不存在的路径（文件不存在分支）。
final String _kMissingPath =
    '${Directory.systemTemp.path}${Platform.pathSeparator}__hermes_c5_missing__.bin';

/// 临时目录下会真实创建的路径（打开异常分支）。
final String _kExistingPath =
    '${Directory.systemTemp.path}${Platform.pathSeparator}__hermes_c5_openme__.bin';

const String _kMediaUrl = 'http://test.local:30002/api/media?path=pic.png';

const ValueKey<String> _kRefreshKey = ValueKey<String>('media-refresh-button');

Map<String, Object?> _session({String? parent}) => <String, Object?>{
  'session': <String, Object?>{
    'session_id': 's1',
    'title': 'C5 会话',
    'parent_session_id': ?parent,
    'messages': const <Object?>[],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // -------------------------------------------------------------------------
  // 1. 源级：零残留 + 调用点数 + 档位序列
  // -------------------------------------------------------------------------
  group('源级 · C5 四文件迁移齐活且档位逐项对齐', () {
    for (final entry in _kMigratedFiles.entries) {
      final path = entry.key;
      final expected = entry.value;

      test(
        '$path：0 处 showCupertinoDialog · ${expected.length} 处 showHermesDialog · 档位序列一致',
        () {
          final source = File(path).readAsStringSync();

          final residual = RegExp(r'showCupertinoDialog')
              .allMatches(source)
              .length;
          expect(
            residual,
            0,
            reason:
                '$path 仍有 $residual 处 showCupertinoDialog —— C5 要求全部迁到 '
                'showHermesDialog（未迁移的每一处都必须在报告里登记理由）',
          );

          final calls = RegExp(r'showHermesDialog<').allMatches(source).length;
          expect(
            calls,
            expected.length,
            reason: '$path 的 showHermesDialog 调用点数与 C5 分档表不符',
          );

          final kinds = RegExp(r'kind:\s*HermesDialogKind\.(\w+)')
              .allMatches(source)
              .map((match) => match.group(1)!)
              .toList();
          expect(kinds, expected, reason: '$path 档位序列与 C5 分档表不一致（顺序即源码出现次序）');
          expect(
            kinds.every(
              (kind) => const <String>[
                'confirm',
                'picker',
                'form',
                'wideForm',
              ].contains(kind),
            ),
            isTrue,
            reason: '出现了四档之外的 kind 名',
          );
        },
      );
    }

    test('C5 只动这四个文件（别的 feature 里的弹窗调用点不在本片范围）', () {
      // 本片文件级分区：任一其它文件出现 showHermesDialog 即说明越界改动
      // （5A 样板 download_confirm_dialog.dart 与基础设施除外）。
      final allowed = <String>{
        'lib/app/widgets/hermes_dialog.dart',
        'lib/features/downloads/download_confirm_dialog.dart',
        ..._kMigratedFiles.keys,
      };
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (allowed.contains(path)) continue;
        if (entity.readAsStringSync().contains('showHermesDialog<')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty, reason: 'C5 之外的 lib 文件被改动了: $offenders');
    });
  });

  // -------------------------------------------------------------------------
  // 2. 宽屏：真实触发路径 → HermesDialogCard + 绝对档位宽
  // -------------------------------------------------------------------------
  group('宽屏 1280 · 每个调用点出卡片且宽度 == 档位绝对像素', () {
    for (final site in _sites) {
      testWidgets('${site.name} → ${site.kind.width.toInt()} 卡片', (
        tester,
      ) async {
        await site.drive(tester, _kWide);

        expect(find.byType(HermesDialogCard), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(HermesDialogCard),
            matching: find.text(site.title),
          ),
          findsOneWidget,
          reason: '触发路径没打开「${site.title}」这个弹窗',
        );
        expect(
          find.byType(CupertinoAlertDialog),
          findsNothing,
          reason: '宽屏不得再走系统 alert 路径（270 定宽那条）',
        );

        final card = find.byKey(kHermesDialogCardKey);
        expect(card, findsOneWidget);
        expect(tester.getSize(card).width, _kWaist[site.kind]);
        expect(
          ModalRoute.of(tester.element(card)),
          isA<HermesDialogRoute<void>>(),
        );

        await _unmount(tester);
      });
    }
  });

  // -------------------------------------------------------------------------
  // 3. 窄屏：同一条触发路径仍是系统弹窗（逐像素不变的结构保证）
  // -------------------------------------------------------------------------
  group('窄屏 800 · 同一条触发路径仍是 CupertinoAlertDialog(270)', () {
    for (final site in _sites) {
      testWidgets('${site.name} → 系统 alert', (tester) async {
        await site.drive(tester, _kNarrow);

        expect(find.byType(HermesDialogCard), findsNothing);
        expect(find.byKey(kHermesDialogCardKey), findsNothing);

        final alert = find.byType(CupertinoAlertDialog);
        expect(alert, findsOneWidget);
        expect(
          find.descendant(of: alert, matching: find.text(site.title)),
          findsOneWidget,
          reason: '窄屏开的不是「${site.title}」这个弹窗',
        );
        // 270 是 `CupertinoAlertDialog` 自己的定宽（外部设不动）—— 「窄屏
        // 逐像素不变」在结构层就是这一条：仍走同一个构造路径、同一颗 270 盒。
        final surface = find.descendant(
          of: alert,
          matching: find.byType(CupertinoPopupSurface),
        );
        expect(surface, findsOneWidget);
        expect(tester.getSize(surface).width, 270.0);

        final route = ModalRoute.of(tester.element(alert));
        expect(route, isA<CupertinoDialogRoute<void>>());
        expect(route, isNot(isA<HermesDialogRoute<void>>()));

        await _unmount(tester);
      });
    }
  });
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// 挂载宿主（真中文 locale + 真 Cupertino 本地化；可注入 overrides）。
Future<void> _pumpHost(
  WidgetTester tester,
  Size size, {
  required Widget home,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: CupertinoApp(
        debugShowCheckedModeBanner: false,
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
  await tester.pump(const Duration(milliseconds: 50));
}

/// 挂载真实聊天页（fake API + 内存连接存储；ApiClient 注入导出替身）。
Future<void> _pumpChat(
  WidgetTester tester,
  Size size, {
  required FakeChatApi api,
  ApiClient? apiClient,
}) async {
  // 导出链路会写剪贴板：override 掉，别碰平台通道。
  SafeClipboard.clipboardSetterOverride = (text) async {};
  addTearDown(SafeClipboard.resetOverridesForTesting);

  await _pumpHost(
    tester,
    size,
    home: const ChatPage(sessionId: 's1'),
    overrides: <Override>[
      chatApiProvider.overrideWithValue(api),
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      apiClientProvider.overrideWithValue(
        apiClient ?? ApiClient(baseUrl: 'http://test.local:30002'),
      ),
    ],
  );
}

/// 打开会话「⋯」菜单 → 点某一项。
Future<void> _tapSessionMenuItem(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(ValueKey(key)));
  await _settleDialog(tester);
}

/// 弹窗入场（Cupertino 弹簧 ≈250ms）结算后再断言。
Future<void> _settleDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 卸载 ProviderScope（dispose 容器 → 取消聊天页看门狗等周期定时器）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// 下载页「打开文件」触发宿主。
class _OpenFileLauncherPage extends StatelessWidget {
  const _OpenFileLauncherPage({super.key, required this.path, this.opener});

  final String path;
  final ExternalOpener? opener;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: CupertinoButton(
          key: const ValueKey('c5-open-file'),
          onPressed: () {
            unawaited(openDownloadedFile(context, path, opener: opener));
          },
          child: const Text('打开文件'),
        ),
      ),
    );
  }
}

/// 导出链路的 ApiClient 替身：只拦 `sendDataReturningResponse`。
class _ExportStubApiClient extends ApiClient {
  _ExportStubApiClient({this.throwError})
    : super(baseUrl: 'http://test.local:30002');

  final Object? throwError;
  int calls = 0;

  @override
  Future<ApiByteResponse> sendDataReturningResponse(
    Endpoint endpoint, {
    String method = 'GET',
    Map<String, Object?>? body,
    Duration? timeout,
    String accept = 'application/json',
    bool allowAutoReauth = true,
  }) async {
    calls++;
    final error = throwError;
    if (error != null) throw error;
    return (
      data: Uint8List.fromList(utf8.encode('# 导出内容')),
      headers: Headers(),
      statusCode: 200,
    );
  }
}

/// 同步落盘、但 `refresh` 必抛的假媒体缓存（媒体刷新失败弹窗的触发面）。
class _ThrowingRefreshCache extends MediaCacheService {
  _ThrowingRefreshCache(this.root, this.database)
    : super.withDownloader(
        database: database,
        downloader: (_) async => Uint8List(0),
        rootDir: root,
      );

  final Directory root;

  /// 与下载侧 overrides 共用的内存库（避免二次开库告警）。
  final AppDatabase database;

  int refreshCalls = 0;
  File? _current;

  @override
  Future<File> get(String fullUrl, {String? sessionId}) async {
    return _current ??= File('${root.path}${Platform.pathSeparator}pic.png')
      ..writeAsBytesSync(_kPngBytes);
  }

  @override
  Future<File> refresh(String fullUrl, {String? sessionId}) async {
    refreshCalls++;
    throw StateError('500 from test');
  }

  Future<void> dispose() async {
    await database.close();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // 忽略：临时目录清理失败不污染结果。
    }
  }
}

final Uint8List _kPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
