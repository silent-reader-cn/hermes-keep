import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/utils/injection_markers.dart';

void main() {
  group('stripInjectionMarkers', () {
    test('剥离 [Workspace::v1] 首行', () {
      const raw = '[Workspace::v1: D:\\projects\\hermes-ui]\n正文内容';
      expect(stripInjectionMarkers(raw), '正文内容');
    });

    test('剥离 [Attached files] 段', () {
      const raw =
          '正文内容\n\n[Attached files: C:\\a\\b.jpg, C:\\a\\c.png]';
      expect(stripInjectionMarkers(raw), '正文内容');
    });

    test('剥离行级 [screenshot] 占位符', () {
      const raw = '正文内容\n[screenshot]';
      expect(stripInjectionMarkers(raw), '正文内容');
    });

    test('剥离结构化前缀标记（\\x00json:）', () {
      final raw = '${ChatMessageStructuredPrefix.value}[{"type":"text"}]';
      final stripped = stripInjectionMarkers(raw);
      expect(stripped.startsWith('\u0000json:'), isFalse);
    });

    test('纯正文不受影响', () {
      const raw = '这条消息里没有任何标记，应当原样保留';
      expect(stripInjectionMarkers(raw), raw);
    });

    test('正文中出现的普通方括号不被误伤', () {
      const raw = '数组写法是 arr[0] 和 obj["key"]';
      expect(stripInjectionMarkers(raw), raw);
    });
  });

  group('sanitizeSessionTitle', () {
    test('「bug 1000 Attached files」→ 剥掉标记只剩正文标题', () {
      const raw =
          'bug 1000 Attached files\n[Attached files: C:\\Users\\a\\shot.jpg]';
      expect(sanitizeSessionTitle(raw), 'bug 1000 Attached files');
    });

    test('标题里的注入标记被剥掉', () {
      const raw = '[Workspace::v1: D:\\x]\n真实标题 [Attached files: C:\\a.png]';
      expect(sanitizeSessionTitle(raw), '真实标题');
    });

    test('多行标题压平为单行', () {
      const raw = '第一行\n第二行   第三行';
      expect(sanitizeSessionTitle(raw), '第一行 第二行 第三行');
    });

    test('超长标题截断并加省略号', () {
      final raw = '字' * 200;
      final result = sanitizeSessionTitle(raw, maxLength: 10);
      expect(result.length, lessThanOrEqualTo(11));
      expect(result.endsWith('…'), isTrue);
    });

    test('全标记标题 → 空串（交给调用方兜底）', () {
      const raw = '[Workspace::v1: D:\\x]\n[Attached files: C:\\a.png]';
      expect(sanitizeSessionTitle(raw), '');
    });
  });
}

/// 结构化前缀常量（与 `ChatMessage.structuredContentPrefix` 同值）。
///
/// 本文件只依赖 utils 层，避免为一个前缀把模型层拖进 utils 测试。
class ChatMessageStructuredPrefix {
  static const String value = '\u0000json:';
}
