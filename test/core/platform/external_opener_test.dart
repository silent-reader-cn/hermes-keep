import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/platform/external_opener.dart';

/// 记录型 opener：注入 runner 与平台判定，**不碰任何真实系统调用**。
ExternalOpener _recording(
  List<String> calls, {
  bool windows = false,
  bool macOS = false,
  bool linux = false,
}) {
  return ExternalOpener(
    isWindows: windows,
    isMacOS: macOS,
    isLinux: linux,
    processRunner: (executable, arguments) async {
      calls.add('$executable ${arguments.join(' ')}');
    },
  );
}

void main() {
  group('revealInFileManager 平台分流与命令行拼装', () {
    test('Windows → `explorer /select, <path>`', () async {
      final calls = <String>[];
      await _recording(
        calls,
        windows: true,
      ).revealInFileManager(r'D:\proj\a.txt');
      expect(calls, <String>[r'explorer /select, D:\proj\a.txt']);
    });

    test('macOS → `open -R <path>`', () async {
      final calls = <String>[];
      await _recording(
        calls,
        macOS: true,
      ).revealInFileManager('/Users/u/a.txt');
      expect(calls, <String>['open -R /Users/u/a.txt']);
    });

    test('Linux → `xdg-open <所在目录>`（无「定位高亮」语义，退化为父目录）', () async {
      final calls = <String>[];
      await _recording(
        calls,
        linux: true,
      ).revealInFileManager('/home/u/p/a.txt');
      expect(calls, <String>['xdg-open /home/u/p']);
    });

    test('三者皆 false（如 Web / 未知宿主）→ 不发起任何系统调用', () async {
      final calls = <String>[];
      await _recording(calls).revealInFileManager('/any/where.txt');
      expect(calls, isEmpty);
    });
  });

  group('openDirectory 平台分流与命令行拼装', () {
    test('Windows → `explorer <dir>`', () async {
      final calls = <String>[];
      await _recording(calls, windows: true).openDirectory(r'D:\proj');
      expect(calls, <String>[r'explorer D:\proj']);
    });

    test('macOS → `open <dir>`', () async {
      final calls = <String>[];
      await _recording(calls, macOS: true).openDirectory('/Users/u/proj');
      expect(calls, <String>['open /Users/u/proj']);
    });

    test('Linux → `xdg-open <dir>`', () async {
      final calls = <String>[];
      await _recording(calls, linux: true).openDirectory('/home/u/proj');
      expect(calls, <String>['xdg-open /home/u/proj']);
    });

    test('三者皆 false → 不发起任何系统调用', () async {
      final calls = <String>[];
      await _recording(calls).openDirectory('/any/where');
      expect(calls, isEmpty);
    });
  });

  group('测试环境硬闸门（回归护栏：单测绝不拉起真实系统窗口）', () {
    test('当前确实处于 flutter test 环境（闸门前提成立）', () {
      // flutter_test 会注入 FLUTTER_TEST=true；若此断言失败，下面的闸门用例
      // 就失去意义，属于环境异常，应当显式红掉而不是静默放过。
      expect(ExternalOpener.isTestEnvironment, isTrue);
    });

    test('未注入 runner：测试环境下拦截系统调用、不抛异常、并上报原因', () async {
      final blocked = <String>[];
      final opener = ExternalOpener(
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        onBlocked: blocked.add,
      );

      await opener.openDirectory(r'D:\some\dir');
      await opener.revealInFileManager(r'D:\some\dir\a.txt');

      expect(blocked, hasLength(2));
      expect(blocked.first, contains('测试环境已拦截系统调用'));
      expect(blocked.first, contains('explorer'));
      expect(blocked.last, contains(r'D:\some\dir\a.txt'));
    });

    test('注入 runner：闸门让路，记录型 runner 正常收到调用', () async {
      final calls = <String>[];
      await _recording(calls, windows: true).openDirectory(r'D:\proj');
      expect(calls, hasLength(1));
    });
  });

  group('provider 契约', () {
    test('externalOpenerProvider 默认给出生产实例（未注入 runner）', () {
      final opener = externalOpenerProvider;
      // Provider 本身是全局单例定义；此处只断言可被读取且类型正确，
      // 真实覆写路径由各页面测试通过 overrideWithValue 覆盖。
      expect(opener, isA<Provider<ExternalOpener>>());
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(externalOpenerProvider), isA<ExternalOpener>());
    });
  });
}
