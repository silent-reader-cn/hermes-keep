import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/chat_diff_merge.dart';

/// 内部恢复载体去重守卫（#173）。
///
/// 缺陷现象（主人真机报告）：
/// 「会话轮次完成以后，有时候会重播该轮次已经显示完毕的整个会话。」
///
/// 根因（实证，非推断）：Hermes 在请求失败 / 中断后会写回三个内部标记
/// （webui 自己也把它们当内部状态：`api/streaming.py` 注释「Skip _partial
/// markers…」、`api/models.py` 注释「appending those rows makes … show
/// duplicated process prose after cancel」）：
///
/// | 标记 | role | 含义 |
/// |---|---|---|
/// | `_partial` | assistant | 中断时的**部分回复快照**，带 `_partial_tool_calls`；
/// webui 组装客户端内容行时与 `tool_calls` 一并展开 ⇒ 该轮正文 + 整轮工具卡再放一遍 |
/// | `_recovered` | user | 中断恢复时写回的**用户消息副本**（同内容） |
/// | `_error` | assistant | 错误载体（`**Error:** …`）—— **保留**，不是重播源 |
///
/// 实证样本（会话 `5052efdc1f11`）：
/// ```
/// [296] assistant ts=…708  正常正文 + tool_calls
/// [297][298] tool …
/// [299] user      ts=…626  _recovered=true  ← 副本
/// [300] assistant ts=…815  _partial=true + _partial_tool_calls=[整轮工具调用]
/// [301] assistant ts=…815  _error=true  **Error:** HTTP 500 … EOF
/// ```
///
/// **红线**：判据只能是「内容已被同会话其他消息覆盖」，绝不无条件丢弃 ——
/// 重试也失败时 partial 可能是该轮唯一回复。
void main() {
  ChatMessage msg(
    String role,
    String content, {
    bool partial = false,
    bool recovered = false,
    double? ts,
  }) => ChatMessage(
    role: role,
    content: content,
    timestamp: ts,
    isPartialArtifact: partial,
    isRecoveredArtifact: recovered,
  );

  const longText = '主人报的这个「轮次完成后重播已显示内容」听起来和收尾时 live 到归档的切换有关。';
  const longerFull = '$longText 本喵先查历史修复痕迹与 reveal 队列的写入点，再定位路径。';
  // 覆盖池只收 ≥16 字的归一化内容（短文本判据误伤概率过高）。
  const userText = '会话轮次完成以后有时候会重播该轮次已经显示完毕的整个会话，需要定位路径。';

  group('#173 内部恢复载体去重', () {
    test('partial（内容被同会话完整回复覆盖）→ 丢弃，不再重播整轮', () {
      final out = dropRecoveryArtifacts([
        msg('user', userText, ts: 1),
        msg('assistant', longerFull, ts: 2),
        msg('assistant', longText, partial: true, ts: 3),
      ]);
      expect(out, hasLength(2));
      expect(
        out.any((m) => m.isPartialArtifact),
        isFalse,
        reason: 'partial 的内容已在完整回复里显示过 ⇒ 必须退场（否则「重播」）',
      );
    });

    test('recovered（用户消息副本）→ 丢弃，用户气泡不再显示两次', () {
      final out = dropRecoveryArtifacts([
        msg('user', userText, ts: 1),
        msg('assistant', userText, ts: 2),
        msg('user', userText, recovered: true, ts: 0.5),
      ]);
      expect(out, hasLength(2));
      expect(out.any((m) => m.isRecoveredArtifact), isFalse);
      expect(out.where((m) => m.role == 'user'), hasLength(1));
    });

    test('partial 是唯一内容（无覆盖）→ 必须保留（重试失败时不能丢回复）', () {
      final out = dropRecoveryArtifacts([
        msg('user', userText, ts: 1),
        msg('assistant', longText, partial: true, ts: 2),
      ]);
      expect(out, hasLength(2), reason: '没有可覆盖它的完整消息 ⇒ 它是该轮唯一回复，丢了就是内容损失');
    });

    test('短内容（<16 字）不参与覆盖判定 → 保留，防误伤', () {
      final out = dropRecoveryArtifacts([
        msg('user', '好的', ts: 1),
        msg('assistant', '好的', partial: true, ts: 2),
      ]);
      expect(
        out.any((m) => m.isPartialArtifact),
        isTrue,
        reason: '短文本被判据误伤概率过高，宁可留着重复也不丢内容',
      );
    });

    test('两个载体之间不互相「覆盖」（覆盖池只收非载体消息）', () {
      final out = dropRecoveryArtifacts([
        msg('assistant', longText, partial: true, ts: 1),
        msg('user', longText, recovered: true, ts: 2),
      ]);
      expect(out, hasLength(2), reason: '双方都是载体 ⇒ 无人证明内容已被正常消息覆盖，都保留');
    });

    test('_error 载体不受影响（不是重播源，且常是错误唯一可见面）', () {
      final out = dropRecoveryArtifacts([
        msg('user', userText, ts: 1),
        msg('assistant', '**Error:** HTTP 500 请求失败载体应当保留不被去重', ts: 2),
      ]);
      expect(out, hasLength(2));
    });

    test('回归：正常对话（无任何载体）逐条不动', () {
      final input = [
        msg('user', 'a', ts: 1),
        msg('assistant', 'b', ts: 2),
        msg('user', 'c', ts: 3),
      ];
      expect(dropRecoveryArtifacts(input), hasLength(3));
    });
  });

  group('#173 渲染入口接线（防止只修一条路径）', () {
    test('diffMergeMessages 入口即过滤载体', () {
      final out = diffMergeMessages(
        localMessages: const [],
        serverMessages: [
          msg('user', userText, ts: 1),
          msg('assistant', longerFull, ts: 2),
          msg('assistant', longText, partial: true, ts: 3),
          msg('user', userText, recovered: true, ts: 0.5),
        ],
      );
      expect(out, hasLength(2));
      expect(
        out.any((m) => m.isPartialArtifact || m.isRecoveredArtifact),
        isFalse,
      );
    });
  });
}
