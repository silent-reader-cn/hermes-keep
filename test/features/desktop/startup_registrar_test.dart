import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/desktop/desktop_settings.dart';
import 'package:hermes_ui/features/desktop/startup_registrar.dart';
import 'package:hermes_ui/features/settings/settings_subpages.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 开机启动注册器测试替身：只记录调用与命令值，绝不触碰真实注册表。
class FakeStartupRegistrar implements StartupRegistrar {
  /// 最近一次写入的注册状态。
  bool registered = false;

  /// 最近一次写入的命令值（注册为 true 时非空）。
  String? lastCommand;

  /// 全部 setRegistered 调用记录（true=写入 / false=删除）。
  final List<bool> setCalls = [];

  /// 全部写入命令记录。
  final List<String?> commands = [];

  /// isRegistered 被调用次数。
  int isRegisteredCallCount = 0;

  /// isRegistered 返回结果。
  bool isRegisteredResult = false;

  @override
  Future<bool> isRegistered() async {
    isRegisteredCallCount++;
    return isRegisteredResult;
  }

  @override
  Future<void> setRegistered(bool registered, {String? command}) async {
    this.registered = registered;
    lastCommand = command;
    setCalls.add(registered);
    commands.add(command);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('isSilentStart 启动参数解析', () {
    test('args 含 --silent 判定为静默启动', () {
      expect(isSilentStart(args: ['--silent']), isTrue);
      expect(isSilentStart(args: ['-x', '--silent', 'foo']), isTrue);
    });

    test('executableArguments 含 --silent 判定为静默启动', () {
      expect(isSilentStart(executableArguments: ['--silent']), isTrue);
    });

    test('Windows argv 首元素为可执行路径时仍能识别 --silent', () {
      final argv = [r'C:\Program Files\Hermes\hermes.exe', '--silent'];
      expect(isSilentStart(args: argv), isTrue);
      expect(isSilentStart(executableArguments: argv), isTrue);
    });

    test('无 --silent 或空参数均判定为非静默', () {
      expect(isSilentStart(args: []), isFalse);
      expect(isSilentStart(args: ['-x', 'y']), isFalse);
      expect(isSilentStart(executableArguments: []), isFalse);
      expect(isSilentStart(), isFalse);
    });
  });

  group('buildStartupCommand 命令构建', () {
    test('可执行路径一律双引号包裹（含空格路径）', () {
      expect(
        buildStartupCommand(
          executablePath: r'C:\Program Files\Hermes\hermes.exe',
          silent: false,
        ),
        r'"C:\Program Files\Hermes\hermes.exe"',
      );
    });

    test('silent 为真时追加 --silent', () {
      expect(
        buildStartupCommand(executablePath: r'C:\hermex.exe', silent: true),
        r'"C:\hermex.exe" --silent',
      );
    });
  });

  group('WindowsStartupRegistrar（桩进程，绝不真跑 reg）', () {
    List<List<String>>? recordedArgs;

    WindowsStartupRegistrar buildRegistrar({int queryExitCode = 0}) {
      recordedArgs = [];
      return WindowsStartupRegistrar(
        isWindowsPlatform: () => true,
        runProcess: (executable, arguments) async {
          recordedArgs!.add(arguments);
          // 返回退出码模拟 reg 结果（query 0=存在 1=不存在）。
          return ProcessResult(0, queryExitCode, '', '');
        },
      );
    }

    test('setRegistered(true) 构造 reg add 参数并透传命令值', () async {
      final registrar = buildRegistrar();
      const command = r'"C:\Program Files\Hermes\hermes.exe" --silent';
      await registrar.setRegistered(true, command: command);

      expect(recordedArgs!.single, [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        'Hermes',
        '/t',
        'REG_SZ',
        '/d',
        command,
        '/f',
      ]);
      expect(recordedArgs!.single.first, 'add');
    });

    test('setRegistered(false) 构造 reg delete 参数', () async {
      final registrar = buildRegistrar();
      await registrar.setRegistered(false);

      expect(recordedArgs!.single, [
        'delete',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        'Hermes',
        '/f',
      ]);
    });

    test('isRegistered 依退出码判定存在性（0 存在 / 1 不存在）', () async {
      final exists = buildRegistrar(queryExitCode: 0);
      expect(await exists.isRegistered(), isTrue);

      final missing = buildRegistrar(queryExitCode: 1);
      expect(await missing.isRegistered(), isFalse);
    });

    test('非 Windows 平台安全 no-op（不调用进程）', () async {
      var called = false;
      final registrar = WindowsStartupRegistrar(
        isWindowsPlatform: () => false,
        runProcess: (executable, arguments) async {
          called = true;
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(await registrar.isRegistered(), isFalse);
      await registrar.setRegistered(true, command: 'x');
      await registrar.setRegistered(false);
      expect(called, isFalse);
    });
  });

  group('DesktopSettingsController 开机启动/静默启动持久化与联动', () {
    test('新开关默认 false 且可持久化读写', () async {
      SharedPreferences.setMockInitialValues({
        DesktopSettingsController.keyStartOnLogin: true,
        DesktopSettingsController.keySilentStart: true,
      });

      // 开关切换会同步写注册表（`_syncStartupRegistration`）——注入替身，
      // 别让单测真跑 `reg`（本用例只关心 prefs 持久化与 state 联动）。
      final registrar = FakeStartupRegistrar();
      final container = ProviderContainer(
        overrides: [startupRegistrarProvider.overrideWithValue(registrar)],
      );
      addTearDown(container.dispose);

      // 先触发 build（内部 unawaited(_load())），再等异步加载完成
      final controller = container.read(desktopSettingsProvider.notifier);
      await pumpEventQueue();

      var settings = container.read(desktopSettingsProvider);
      expect(settings.startOnLogin, isTrue);
      expect(settings.silentStart, isTrue);
      await controller.setStartOnLogin(false);
      await controller.setSilentStart(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(DesktopSettingsController.keyStartOnLogin), isFalse);
      expect(prefs.getBool(DesktopSettingsController.keySilentStart), isFalse);

      settings = container.read(desktopSettingsProvider);
      expect(settings.startOnLogin, isFalse);
      expect(settings.silentStart, isFalse);
    });

    test('开启开机启动：写入命令含可执行路径、不含 --silent', () async {
      final registrar = FakeStartupRegistrar();
      final container = ProviderContainer(
        overrides: [startupRegistrarProvider.overrideWithValue(registrar)],
      );
      addTearDown(container.dispose);

      final controller = container.read(desktopSettingsProvider.notifier);
      await controller.setStartOnLogin(true);

      expect(registrar.registered, isTrue);
      expect(registrar.lastCommand, contains(Platform.resolvedExecutable));
      expect(registrar.lastCommand, startsWith('"'));
      expect(registrar.lastCommand, isNot(contains('--silent')));
    });

    test('联动：静默启动开启后重写命令追加 --silent', () async {
      final registrar = FakeStartupRegistrar();
      final container = ProviderContainer(
        overrides: [startupRegistrarProvider.overrideWithValue(registrar)],
      );
      addTearDown(container.dispose);

      final controller = container.read(desktopSettingsProvider.notifier);
      // 先开「开机启动」（静默未开）
      await controller.setStartOnLogin(true);
      expect(registrar.lastCommand, isNot(contains('--silent')));

      // 再开「静默启动」→ 联动重写注册表值
      await controller.setSilentStart(true);
      expect(registrar.setCalls.length, 2);
      expect(registrar.registered, isTrue);
      expect(registrar.lastCommand, contains(Platform.resolvedExecutable));
      expect(registrar.lastCommand, contains('--silent'));
    });

    test('联动：先开静默再开开机启动，首次写入即带 --silent', () async {
      final registrar = FakeStartupRegistrar();
      final container = ProviderContainer(
        overrides: [startupRegistrarProvider.overrideWithValue(registrar)],
      );
      addTearDown(container.dispose);

      final controller = container.read(desktopSettingsProvider.notifier);
      // 静默未开开机启动时不触碰注册表
      await controller.setSilentStart(true);
      expect(registrar.setCalls, isEmpty);

      // 后开开机启动 → 命令直接带 --silent（勾选顺序无关）
      await controller.setStartOnLogin(true);
      expect(registrar.registered, isTrue);
      expect(registrar.lastCommand, contains('--silent'));
    });

    test('取消开机启动：删除注册值；之后再切静默不再触发写注册表', () async {
      final registrar = FakeStartupRegistrar();
      final container = ProviderContainer(
        overrides: [startupRegistrarProvider.overrideWithValue(registrar)],
      );
      addTearDown(container.dispose);

      final controller = container.read(desktopSettingsProvider.notifier);
      await controller.setStartOnLogin(true);
      await controller.setSilentStart(true);
      expect(registrar.setCalls.length, 2);

      await controller.setStartOnLogin(false);
      expect(registrar.registered, isFalse);
      expect(container.read(desktopSettingsProvider).startOnLogin, isFalse);

      // 关机启动后切静默不写注册表（幂等，避免无谓 reg 调用）
      await controller.setSilentStart(false);
      expect(registrar.setCalls.length, 3);

      final silentOff = FakeStartupRegistrar();
      final quietContainer = ProviderContainer(
        overrides: [startupRegistrarProvider.overrideWithValue(silentOff)],
      );
      addTearDown(quietContainer.dispose);
      final quietController = quietContainer.read(
        desktopSettingsProvider.notifier,
      );
      await quietController.setSilentStart(true);
      expect(silentOff.setCalls, isEmpty);
    });
  });

  group('DesktopSettingsPage 设置页开关渲染与交互', () {
    testWidgets('渲染开机启动/静默启动并切换联动 fake 注册器', (tester) async {
      final registrar = FakeStartupRegistrar();
      final container = ProviderContainer(
        overrides: [startupRegistrarProvider.overrideWithValue(registrar)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(home: DesktopSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 文案与开关渲染（沿用现有 3 个开关的 ListTile 视觉）
      expect(find.text('开机启动'), findsOneWidget);
      expect(find.text('静默启动'), findsOneWidget);
      final startOnLoginFinder = find.byKey(
        const ValueKey('settings-desktop-start-on-login'),
      );
      final silentStartFinder = find.byKey(
        const ValueKey('settings-desktop-silent-start'),
      );
      expect(startOnLoginFinder, findsOneWidget);
      expect(silentStartFinder, findsOneWidget);
      expect(tester.widget<CupertinoSwitch>(startOnLoginFinder).value, isFalse);
      expect(tester.widget<CupertinoSwitch>(silentStartFinder).value, isFalse);

      // 开启开机启动 → fake 收到写入
      await tester.tap(startOnLoginFinder);
      await tester.pumpAndSettle();
      expect(container.read(desktopSettingsProvider).startOnLogin, isTrue);
      expect(registrar.registered, isTrue);

      // 开启静默启动 → 联动重写（命令含 --silent）
      await tester.tap(silentStartFinder);
      await tester.pumpAndSettle();
      expect(container.read(desktopSettingsProvider).silentStart, isTrue);
      expect(registrar.lastCommand, contains('--silent'));

      // 关闭开机启动 → fake 收到删除
      await tester.tap(startOnLoginFinder);
      await tester.pumpAndSettle();
      expect(container.read(desktopSettingsProvider).startOnLogin, isFalse);
      expect(registrar.registered, isFalse);
    });
  });
}
