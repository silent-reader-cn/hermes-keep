import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/platform/external_opener.dart';
import 'package:hermes_ui/features/settings/settings_subpages.dart';
import 'package:hermes_ui/features/settings/webui_sidecar_section.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSidecarFileSystem implements SidecarFileSystem {
  @override
  bool isWindows = true;
  bool bundleAvailable = true;

  @override
  bool isBundleAvailable() => isWindows && bundleAvailable;

  @override
  String get defaultSidecarDir => r'C:\app\webui';

  @override
  bool directoryExists(String path) => true;

  @override
  String? get envSidecarRoot => null;

  bool Function(String path)? fileExistsOverride;
  String customAgentDir = r'C:\Users\Admin\AppData\Local\hermes\hermes-agent';

  String get hermesAgentDir => customAgentDir;

  @override
  bool fileExists(String path) {
    if (fileExistsOverride != null) {
      return fileExistsOverride!(path);
    }
    return true;
  }

  @override
  String logDirectoryPath = r'C:\logs';

  @override
  String get logFilePath => r'C:\logs\webui.log';

  @override
  Future<void> appendLogLine(String path, String line) async {}

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  String resolveBundleDir() => r'C:\app\webui';

  @override
  Future<void> rotateLogIfNeeded(
    String path, {
    int maxSizeBytes = 5 * 1024 * 1024,
  }) async {}
}

class _FakeSecureStorage implements SidecarSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _MockWebuiSidecarService implements WebuiSidecarService {
  _MockWebuiSidecarService({SidecarState? initialState})
    : _state = initialState ?? SidecarState.initial;

  SidecarState _state;
  final StreamController<SidecarState> _controller =
      StreamController<SidecarState>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int restartCalls = 0;

  void emitState(SidecarState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  SidecarState get currentState => _state;

  @override
  Stream<SidecarState> get states => _controller.stream;

  @override
  Future<void> start() async {
    startCalls++;
    emitState(const SidecarState(status: SidecarStatus.running, pid: 1234));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    emitState(const SidecarState(status: SidecarStatus.stopped));
  }

  @override
  Future<void> restart() async {
    restartCalls++;
    emitState(const SidecarState(status: SidecarStatus.running, pid: 5678));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSidecarFileSystem fakeFs;
  late _FakeSecureStorage fakeSecureStorage;
  late _MockWebuiSidecarService mockService;
  late SharedPreferences prefs;
  late ProviderContainer container;

  /// 组装容器（可注入外部打开器，用于断言「打开日志目录」真的走了接缝）。
  ProviderContainer buildContainer({ExternalOpener? opener}) {
    return ProviderContainer(
      overrides: [
        sidecarFileSystemProvider.overrideWithValue(fakeFs),
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(
            prefs: prefs,
            secureStorage: fakeSecureStorage,
          ),
        ),
        webuiSidecarServiceProvider.overrideWithValue(mockService),
        if (opener != null) externalOpenerProvider.overrideWithValue(opener),
      ],
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeFs = _FakeSidecarFileSystem();
    fakeSecureStorage = _FakeSecureStorage();
    mockService = _MockWebuiSidecarService();

    fakeSecureStorage.values[WebuiSidecarConfigStorage.keyPassword] =
        'init-secret-123456';

    container = buildContainer();
    await container.read(webuiSidecarConfigProvider.notifier).load();
  });

  tearDown(() {
    container.dispose();
  });

  Widget buildTestWidget({Widget? child}) {
    return UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: ListView(children: [child ?? const WebuiSidecarSection()]),
        ),
      ),
    );
  }

  group('WebuiSidecarSection 开关与生命周期联动', () {
    testWidgets('开关切换联动 setEnabled 与 start/stop', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings-webui-enable-switch'),
      );
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);

      // 切换开启 -> 触发 setEnabled(true) 与 start()
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(mockService.startCalls, 1);
      expect(container.read(webuiSidecarConfigProvider).enabled, isTrue);
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);

      // 切换关闭 -> 触发 setEnabled(false) 与 stop()
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(mockService.stopCalls, 1);
      expect(container.read(webuiSidecarConfigProvider).enabled, isFalse);
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);
    });

    testWidgets('未安装 Agent 时点击开关 -> 弹窗且不解开关，保持 false', (tester) async {
      fakeFs.fileExistsOverride = (path) => false;
      await container.read(agentEnvPresentProvider.notifier).refresh();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings-webui-enable-switch'),
      );
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);

      // 点击开关
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // 验证弹出 CupertinoAlertDialog
      expect(
        find.byKey(const ValueKey('settings-webui-missing-agent-dialog')),
        findsOneWidget,
      );
      expect(find.text('需要先安装 Hermes Agent'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-webui-dialog-cancel-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-webui-dialog-guide-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-webui-dialog-recheck-btn')),
        findsOneWidget,
      );

      // 开关仍保持 false，未调用 start()
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);
      expect(container.read(webuiSidecarConfigProvider).enabled, isFalse);
      expect(mockService.startCalls, 0);

      // 点击「取消」按钮关闭弹窗
      await tester.tap(
        find.byKey(const ValueKey('settings-webui-dialog-cancel-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-webui-missing-agent-dialog')),
        findsNothing,
      );
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);
    });

    testWidgets('弹窗中点击「重新检测」触发 refresh', (tester) async {
      var installed = false;
      final expectedVenv =
          '${fakeFs.customAgentDir}\\venv\\Scripts\\python.exe';
      fakeFs.fileExistsOverride = (path) => installed && path == expectedVenv;
      await container.read(agentEnvPresentProvider.notifier).refresh();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings-webui-enable-switch'),
      );
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-webui-missing-agent-dialog')),
        findsOneWidget,
      );

      // 此时用户安装好 agent，点击「重新检测」
      installed = true;
      await tester.tap(
        find.byKey(const ValueKey('settings-webui-dialog-recheck-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-webui-missing-agent-dialog')),
        findsNothing,
      );
      expect(container.read(agentEnvPresentProvider).value, isTrue);
    });
  });

  group('WebuiSidecarSection 监听 IP 校验与提交', () {
    testWidgets('非法 IPv4 红字就地提示且不提交；合法 IPv4 失焦提交', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final hostFieldFinder = find.byKey(
        const ValueKey('settings-webui-host-input'),
      );
      expect(hostFieldFinder, findsOneWidget);

      // 输入非法 IPv4
      await tester.enterText(hostFieldFinder, '999.999.999.999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 IPv4 地址'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).host,
        SidecarConfig.defaultHost,
      );

      // 输入字母非法 IP
      await tester.enterText(hostFieldFinder, 'invalid-ip');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 IPv4 地址'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).host,
        SidecarConfig.defaultHost,
      );

      // 输入合法 IPv4 (0.0.0.0 允许)
      await tester.enterText(hostFieldFinder, '0.0.0.0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 IPv4 地址'), findsNothing);
      expect(container.read(webuiSidecarConfigProvider).host, '0.0.0.0');

      // 输入 192.168.1.100 合法
      await tester.enterText(hostFieldFinder, '192.168.1.100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 IPv4 地址'), findsNothing);
      expect(container.read(webuiSidecarConfigProvider).host, '192.168.1.100');
    });
  });

  group('WebuiSidecarSection 端口输入与校验', () {
    testWidgets('非法端口（<1 或 >65535 或非数字）红字提示且不提交；合法端口提交', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final portFieldFinder = find.byKey(
        const ValueKey('settings-webui-port-input'),
      );
      expect(portFieldFinder, findsOneWidget);

      // 0 非法
      await tester.enterText(portFieldFinder, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('端口号必须在 1-65535 之间'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).port,
        SidecarConfig.defaultPort,
      );

      // 70000 超限非法
      await tester.enterText(portFieldFinder, '70000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('端口号必须在 1-65535 之间'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).port,
        SidecarConfig.defaultPort,
      );

      // 非数字非法
      await tester.enterText(portFieldFinder, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('端口号必须在 1-65535 之间'), findsOneWidget);

      // 合法端口 8080
      await tester.enterText(portFieldFinder, '8080');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('端口号必须在 1-65535 之间'), findsNothing);
      expect(container.read(webuiSidecarConfigProvider).port, 8080);
    });
  });

  group('WebuiSidecarSection 密码内联框、眼睛显隐与写回', () {
    testWidgets('默认遮罩，眼睛切明文，改字提交写回，空字红字不写回', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final passwordInputFinder = find.byKey(
        const ValueKey('settings-webui-password-input'),
      );
      expect(passwordInputFinder, findsOneWidget);
      expect(
        tester.widget<CupertinoTextField>(passwordInputFinder).obscureText,
        isTrue,
      );
      expect(find.text('init-secret-123456'), findsWidgets);
      // 遮罩态：密码只存在于输入框内部，不以普通 Text 明文展示
      final plainTextDisplays = find.byWidgetPredicate(
        (w) => w is Text && w.data == 'init-secret-123456',
      );
      expect(plainTextDisplays, findsNothing);

      // 眼睛切明文
      await tester.tap(
        find.byKey(const ValueKey('settings-webui-password-visibility-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(passwordInputFinder).obscureText,
        isFalse,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-webui-password-visibility-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(passwordInputFinder).obscureText,
        isTrue,
      );

      // 改字提交写回
      await tester.enterText(passwordInputFinder, 'new-secret-999888');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        container.read(webuiSidecarConfigProvider).password,
        'new-secret-999888',
      );
      expect(
        fakeSecureStorage.values[WebuiSidecarConfigStorage.keyPassword],
        'new-secret-999888',
      );

      // 空密码校验：红字且不写回
      await tester.enterText(passwordInputFinder, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('密码不能为空'), findsOneWidget);
      expect(
        fakeSecureStorage.values[WebuiSidecarConfigStorage.keyPassword],
        'new-secret-999888',
      );
    });
  });

  group('WebuiSidecarSection 状态指示四态渲染断言', () {
    testWidgets('已停止 (stopped) 状态渲染', (tester) async {
      mockService.emitState(const SidecarState(status: SidecarStatus.stopped));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('服务状态'), findsOneWidget);
      expect(find.text('○ 已停止'), findsOneWidget);
    });

    testWidgets('启动中 (starting) 状态渲染', (tester) async {
      mockService.emitState(const SidecarState(status: SidecarStatus.starting));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('服务状态'), findsOneWidget);
      expect(find.text('◐ 启动中…'), findsOneWidget);
    });

    testWidgets('运行中 (running) 状态渲染附 PID', (tester) async {
      mockService.emitState(
        const SidecarState(status: SidecarStatus.running, pid: 4567),
      );
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('服务状态'), findsOneWidget);
      expect(find.text('● 运行中'), findsOneWidget);
      expect(find.text('PID: 4567'), findsOneWidget);
    });

    testWidgets('失败 (failed) 状态渲染附四种 reason 文案', (tester) async {
      // 1. 端口占用
      mockService.emitState(
        const SidecarState(
          status: SidecarStatus.failed,
          reason: SidecarFailureReason.portOccupied,
        ),
      );
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('● 启动失败'), findsOneWidget);
      expect(find.text('端口占用'), findsOneWidget);

      // 2. 缺内置包
      mockService.emitState(
        const SidecarState(
          status: SidecarStatus.failed,
          reason: SidecarFailureReason.missingBundle,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('缺内置包'), findsOneWidget);

      // 3. 健康超时
      mockService.emitState(
        const SidecarState(
          status: SidecarStatus.failed,
          reason: SidecarFailureReason.healthTimeout,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('健康超时'), findsOneWidget);

      // 4. 启动失败
      mockService.emitState(
        const SidecarState(
          status: SidecarStatus.failed,
          reason: SidecarFailureReason.startFailed,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('启动失败'), findsWidgets);
    });
  });

  group('WebuiSidecarSection 平台与内置包缺失提示', () {
    testWidgets('缺少内置包时渲染顶部灰字提示', (tester) async {
      fakeFs.bundleAvailable = false;
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final hintFinder = find.byKey(
        const ValueKey('settings-webui-missing-bundle-hint'),
      );
      expect(hintFinder, findsOneWidget);
      expect(find.text('未检测到内置 WebUI 包'), findsOneWidget);
    });

    testWidgets('内置包存在且 Windows 平台时不渲染缺失提示', (tester) async {
      fakeFs.bundleAvailable = true;
      fakeFs.isWindows = true;
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final hintFinder = find.byKey(
        const ValueKey('settings-webui-missing-bundle-hint'),
      );
      expect(hintFinder, findsNothing);
    });
  });

  group('WebuiSidecarSection 日志入口与二级页集成', () {
    testWidgets('渲染打开日志目录行项', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final openLogsFinder = find.byKey(
        const ValueKey('settings-webui-open-logs'),
      );
      expect(openLogsFinder, findsOneWidget);
      expect(find.text('打开日志目录'), findsOneWidget);
    });

    testWidgets('点击「打开日志目录」→ 经外部打开器打开（不拉起真实资源管理器）', (tester) async {
      // 日志目录指向临时目录：默认假值 `C:\logs` 会被 `Directory(...).create`
      // 真的在盘根建出来，故此处换成系统临时目录。
      final logDirPath = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('hermes_sidecar_logs_'),
      ))!.path;
      addTearDown(() async {
        final dir = Directory(logDirPath);
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      fakeFs.logDirectoryPath = logDirPath;

      final opened = <String>[];
      final opener = ExternalOpener(
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        processRunner: (executable, arguments) async {
          opened.add('$executable ${arguments.join(' ')}');
        },
      );

      // 重建容器以注入记录型打开器（setUp 的容器没有该 override）。
      container.dispose();
      container = buildContainer(opener: opener);
      await container.read(webuiSidecarConfigProvider.notifier).load();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings-webui-open-logs')));
      await tester.pumpAndSettle();

      expect(opened, <String>['explorer $logDirPath']);
    });

    testWidgets('DesktopSettingsPage 在 Windows 下渲染内置 WebUI 分组', (tester) async {
      // DesktopSettingsPage 自带 ListView，不能再套滚动容器（嵌套 viewport 无界高度）
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(home: DesktopSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('内置 WebUI 服务'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-webui-enable-switch')),
        findsOneWidget,
      );
    });
  });
}
