// WebUI Sidecar Providers 补测：
// - 默认 provider 实体（默认文件系统 / 配置存储 / 服务）与其 onDispose 停服；
// - 配置控制器 updateConfig 落盘；
// - 控制器 restart 的 Windows 委派与「非 Windows 直接落失败」两分支；
// - 运行中「仅改密码」也触发 restart（password 比较键位）。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSidecarFileSystem implements SidecarFileSystem {
  _FakeSidecarFileSystem();

  @override
  bool isWindows = true;

  bool bundleAvailable = true;

  @override
  bool isBundleAvailable() => isWindows && bundleAvailable;

  @override
  Future<void> appendLogLine(String path, String line) async {}

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  String get defaultSidecarDir => r'C:\app\webui';

  @override
  bool directoryExists(String path) => false;

  @override
  String? get envSidecarRoot => null;

  @override
  bool fileExists(String path) => false;

  String get hermesAgentDir => r'C:\Users\Admin\AppData\Local\hermes\hermes-agent';

  @override
  String get logDirectoryPath => r'C:\logs';

  @override
  String get logFilePath => r'C:\logs\webui.log';

  @override
  String resolveBundleDir() => defaultSidecarDir;

  @override
  Future<void> rotateLogIfNeeded(
    String path, {
    int maxSizeBytes = 5 * 1024 * 1024,
  }) async {}
}

class _FakeSecureStorage implements SidecarSecureStorage {
  final Map<String, String> values = <String, String>{};

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
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> restart() async {
    restartCalls++;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('默认 provider 实体：默认文件系统 / 配置存储 / 服务可实例化，dispose 触发停服', () async {
    // 未覆盖的默认配置存储 provider（无 override）单独实例化：构造本身不触碰平台通道。
    final bareContainer = ProviderContainer();
    expect(
      bareContainer.read(webuiSidecarConfigStorageProvider),
      isA<WebuiSidecarConfigStorage>(),
    );
    bareContainer.dispose();

    final container = ProviderContainer(
      overrides: [
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(secureStorage: _FakeSecureStorage()),
        ),
      ],
    );

    expect(
      container.read(sidecarFileSystemProvider),
      isA<DefaultSidecarFileSystem>(),
    );
    expect(
      container.read(webuiSidecarConfigStorageProvider),
      isA<WebuiSidecarConfigStorage>(),
    );

    final service = container.read(webuiSidecarServiceProvider);
    expect(service, isA<DefaultWebuiSidecarService>());
    expect(service.currentState, SidecarState.initial);

    // onDispose → unawaited(service.stop())：未启动态直接早退，不抛异常。
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('bundledWebuiAvailableProvider 走默认文件系统实例', () {
    final container = ProviderContainer(
      overrides: [
        sidecarFileSystemProvider.overrideWithValue(_FakeSidecarFileSystem()),
      ],
    );

    expect(container.read(bundledWebuiAvailableProvider), isTrue);

    container.dispose();
  });

  test('默认服务 provider 读取配置（getConfig 闭包）后落 missingBundle，不 spawn', () async {
    final container = ProviderContainer(
      overrides: [
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(secureStorage: _FakeSecureStorage()),
        ),
        sidecarFileSystemProvider.overrideWithValue(
          _FakeSidecarFileSystem()..bundleAvailable = false,
        ),
      ],
    );

    final service = container.read(webuiSidecarServiceProvider);
    expect(service, isA<DefaultWebuiSidecarService>());
    expect(service.currentState, SidecarState.initial);

    // 走真实 start()：读配置 → 内置包不可用 → failed(missingBundle)，不探测端口、不 spawn。
    await service.start();

    expect(service.currentState.status, SidecarStatus.failed);
    expect(service.currentState.reason, SidecarFailureReason.missingBundle);

    container.dispose();
  });

  test('WebuiSidecarConfigController.updateConfig 同步 state 并完整落盘', () async {
    final secure = _FakeSecureStorage();
    final container = ProviderContainer(
      overrides: [
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(
            prefs: SharedPreferences.getInstance(),
            secureStorage: secure,
          ),
        ),
      ],
    );

    final controller = container.read(webuiSidecarConfigProvider.notifier);
    // build() 内部 unawaited(load()) 会异步覆盖 state，先等它归位再写入。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    const next = SidecarConfig(
      enabled: true,
      host: '0.0.0.0',
      port: 9001,
      password: 'update_pwd',
    );

    await controller.updateConfig(next);

    expect(container.read(webuiSidecarConfigProvider), equals(next));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(WebuiSidecarConfigStorage.keyEnabled), isTrue);
    expect(prefs.getString(WebuiSidecarConfigStorage.keyHost), '0.0.0.0');
    expect(prefs.getInt(WebuiSidecarConfigStorage.keyPort), 9001);
    expect(
      await secure.read(WebuiSidecarConfigStorage.keyPassword),
      'update_pwd',
    );

    container.dispose();
  });

  test('控制器 restart：Windows 委派给 service，非 Windows 直接落 failed 不委派', () async {
    final fakeFs = _FakeSidecarFileSystem();
    final mockService = _MockWebuiSidecarService();
    final container = ProviderContainer(
      overrides: [
        sidecarFileSystemProvider.overrideWithValue(fakeFs),
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(secureStorage: _FakeSecureStorage()),
        ),
        webuiSidecarServiceProvider.overrideWithValue(mockService),
      ],
    );

    final controller = container.read(webuiSidecarControllerProvider.notifier);

    await controller.restart();
    expect(mockService.restartCalls, 1);

    fakeFs.isWindows = false;
    await controller.restart();
    expect(mockService.restartCalls, 1);
    final state = container.read(webuiSidecarControllerProvider);
    expect(state.status, SidecarStatus.failed);
    expect(state.reason, SidecarFailureReason.startFailed);
    expect(state.detail, contains('only supported on Windows'));

    container.dispose();
  });

  test('运行中仅改密码 → 仍触发 restart（password 比较键位）', () async {
    final mockService = _MockWebuiSidecarService();
    final container = ProviderContainer(
      overrides: [
        sidecarFileSystemProvider.overrideWithValue(_FakeSidecarFileSystem()),
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(secureStorage: _FakeSecureStorage()),
        ),
        webuiSidecarServiceProvider.overrideWithValue(mockService),
      ],
    );

    container.read(webuiSidecarControllerProvider);
    final configController = container.read(webuiSidecarConfigProvider.notifier);
    await configController.load();

    // stopped 态下 load 带来的密码变化不触发重启。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(mockService.restartCalls, 0);

    mockService.emitState(
      const SidecarState(status: SidecarStatus.running, pid: 3),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(webuiSidecarControllerProvider).status,
      SidecarStatus.running,
    );

    // host / port 未变，只有密码变化。
    await configController.setPassword('brand_new_password');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(mockService.restartCalls, 1);

    container.dispose();
  });

  test('运行中改 host 触发 restart；写入同值不重复触发', () async {
    final mockService = _MockWebuiSidecarService();
    final container = ProviderContainer(
      overrides: [
        sidecarFileSystemProvider.overrideWithValue(_FakeSidecarFileSystem()),
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(secureStorage: _FakeSecureStorage()),
        ),
        webuiSidecarServiceProvider.overrideWithValue(mockService),
      ],
    );

    container.read(webuiSidecarControllerProvider);
    final configController = container.read(webuiSidecarConfigProvider.notifier);
    await configController.load();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(mockService.restartCalls, 0);

    mockService.emitState(
      const SidecarState(status: SidecarStatus.running, pid: 3),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await configController.setHost('0.0.0.0');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(mockService.restartCalls, 1);

    // 未变化的写入不再重复触发。
    await configController.setHost('0.0.0.0');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(mockService.restartCalls, 1);

    container.dispose();
  });
}
