import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/platform/test_environment.dart';
import 'package:hermes_ui/features/desktop/startup_registrar.dart';

/// 无害探针命令（仅用于验证「显式 opt-in 之后确实能跑」这条正向路径）。
final List<String> _probeCommand = Platform.isWindows
    ? const <String>['cmd', '/c', 'echo', 'hermes-guard-probe']
    : const <String>['sh', '-c', 'echo hermes-guard-probe'];

/// 跟 `external_opener_guard_test.dart` 同一条思路：**测试期系统副作用必须会红**。
///
/// 这里守的是「返回真实结果的系统接缝」——它们不能用静默拦截（伪造结果比真跑更危险），
/// 所以闸门口径是**显式抛 `StateError`**：漏注入替身的测试立刻红，而不是悄悄真跑
/// （真跑会写注册表 / 装软件）或悄悄假装成功。
void main() {
  group('测试期系统调用硬闸门', () {
    test('前提：当前确实处于 flutter test 环境（否则本组失去意义）', () {
      expect(isRunningUnderTest, isTrue);
    });

    test('SystemProcessExecutor.run 默认拒绝，并给出可操作的引导', () {
      expect(
        () => const SystemProcessExecutor().run('cmd', const <String>[
          '/c',
          'echo',
          'hi',
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('测试环境禁止真跑系统命令'), contains('run')),
          ),
        ),
      );
    });

    test('SystemProcessExecutor.start 默认拒绝', () {
      expect(
        () => const SystemProcessExecutor().start('cmd', const <String>[
          '/c',
          'echo',
          'hi',
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('WindowsStartupRegistrar.isRegistered 默认拒绝（不真跑 reg query）', () {
      final registrar = WindowsStartupRegistrar(isWindowsPlatform: () => true);
      expect(registrar.isRegistered(), throwsA(isA<StateError>()));
    });

    test('WindowsStartupRegistrar.setRegistered 默认拒绝（不真写注册表）', () {
      final registrar = WindowsStartupRegistrar(isWindowsPlatform: () => true);
      expect(
        registrar.setRegistered(true, command: 'probe'),
        throwsA(isA<StateError>()),
      );
    });

    test('显式 opt-in 后放行 —— 供包装器自身契约测试真跑一次（只有无害命令）', () async {
      final result = await const SystemProcessExecutor(
        allowSystemCallsInTest: true,
      ).run(_probeCommand.first, _probeCommand.sublist(1));
      expect(result.exitCode, 0);
    });

    test('平台判定为否时 registrar 直接 no-op，压根不进闸门（CI Linux 亦安全）', () async {
      final registrar = WindowsStartupRegistrar(isWindowsPlatform: () => false);
      expect(await registrar.isRegistered(), isFalse);
      await registrar.setRegistered(true, command: 'probe');
    });
  });
}
