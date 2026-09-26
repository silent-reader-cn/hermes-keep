import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';

/// Hermes agent 的内部结构化内容前缀（`hermes_state.py` `_CONTENT_JSON_PREFIX`）。
///
/// 带附件的多模态消息会被存成 `\x00json:[{type:text},{type:image,...}]`，
/// webui 的 transcript 原样透传，客户端若不识别就会把 1MB base64 当正文渲染。
const String _prefix = '\u0000json:';

String _structured(List<Object> blocks) => _prefix + jsonEncode(blocks);

void main() {
  group('结构化内容前缀（\\x00json:）解码', () {
    test('文本 + 图片块 → content 只留纯文本，base64 不泄漏', () {
      final bigBase64 = 'QUJD' * 16; // 模拟内嵌图片数据（保持断言信息可读）
      final message = ChatMessage.fromJson({
        'role': 'user',
        'content': _structured([
          {
            'type': 'text',
            'text': '[Workspace::v1: D:\\projects\\hermes-ui]\n帮我看看这个报错',
          },
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': 'image/jpeg',
              'data': bigBase64,
            },
          },
        ]),
      });

      // 关键：正文里绝不能出现 base64 原文
      expect(message.content, isNotNull);
      expect(message.content, isNot(contains(bigBase64)));
      expect(message.content!.length, lessThan(500));
      // 文本块被保留
      expect(message.content, contains('帮我看看这个报错'));
      // 原始 blocks 数组保留，供附件/媒体渲染使用
      expect(message.contentParts, isNotNull);
      expect(message.contentParts!.length, 2);
    });

    test('纯文本块 → 正常解出文本', () {
      final message = ChatMessage.fromJson({
        'role': 'user',
        'content': _structured([
          {'type': 'text', 'text': '只有文字'},
        ]),
      });

      expect(message.content, '只有文字');
      expect(message.contentParts, isNotNull);
    });

    test('多个文本块 → 拼接', () {
      final message = ChatMessage.fromJson({
        'role': 'user',
        'content': _structured([
          {'type': 'text', 'text': '第一段'},
          {'type': 'text', 'text': '第二段'},
        ]),
      });

      expect(message.content, '第一段第二段');
    });

    test('畸形 JSON → 不抛异常，退化为原文（不崩）', () {
      final message = ChatMessage.fromJson({
        'role': 'user',
        'content': '$_prefix{not valid json',
      });

      // 不应抛；内容退化但保留字符串
      expect(message.content, isNotNull);
    });

    test('前缀后非数组（对象）→ 退化为原文', () {
      final message = ChatMessage.fromJson({
        'role': 'user',
        'content': '$_prefix{"type":"text","text":"x"}',
      });

      expect(message.content, isNotNull);
    });

    test('无前缀的普通字符串 → 行为完全不变', () {
      const plain = '普通消息，没有任何前缀';
      final message = ChatMessage.fromJson({'role': 'user', 'content': plain});

      expect(message.content, plain);
      expect(message.contentParts, isNull);
    });
  });
}
