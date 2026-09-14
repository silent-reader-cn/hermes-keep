import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/platform_paths.dart';

void main() {
  group('platformPathSeparator', () {
    test('分隔符由入参决定，与宿主平台无关', () {
      expect(platformPathSeparator(true), '\\');
      expect(platformPathSeparator(false), '/');
    });
  });

  group('platformParentDir', () {
    test('Windows 风格路径取父目录（宿主是 Linux 也不受影响）', () {
      expect(
        platformParentDir(r'C:\Program Files\Hermes\hermes.exe'),
        r'C:\Program Files\Hermes',
      );
    });

    test('POSIX 风格路径取父目录（宿主是 Windows 也不受影响）', () {
      expect(platformParentDir('/opt/hermes/bin/hermes'), '/opt/hermes/bin');
    });

    test('无分隔符时原样返回，不套用宿主 dirname 语义（File.parent 会得到 .）', () {
      expect(platformParentDir('hermes.exe'), 'hermes.exe');
    });

    test('混合分隔符取最后一个', () {
      expect(platformParentDir(r'C:\a/b\hermes.exe'), r'C:\a/b');
    });
  });
}
