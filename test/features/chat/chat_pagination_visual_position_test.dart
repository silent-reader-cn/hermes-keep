// 分页加载的**视觉位置**定案测试。
//
// 背景：主人报告「拉到最顶端之后，新加载的聊天记录显示在最下面而不是最上面」。
//
// 此前几轮推演都在「数组拼接顺序」与「pixels 语义」上打转、且互相矛盾
// （探针实测 pixels 与 maxScrollExtent 同步 +5200 增长，说明视口被自动补偿，
// 仅看这两个量无法判定视觉位置）。因此本测试**只断言主人能看见的事实**：
// 新加载的更早消息，其屏幕 dy 必须小于（即位于上方）原有消息。
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

const String _sessionId = 's-visual-order';
const int _total = 200;
const int _pageSize = 25;

/// 一页消息。`from..to` 为消息序号（越小越早）。
Map<String, Object?> _page({
  required int from,
  required int to,
  required int offset,
}) {
  return <String, Object?>{
    'session': <String, Object?>{
      'session_id': _sessionId,
      'messages': [
        for (var i = from; i < to; i++)
          {
            'role': i.isEven ? 'user' : 'assistant',
            // 每条都做成足够高，保证一屏放不下几页
            'content': '历史消息 $i：' * 40,
            'message_id': 'm$i',
          },
      ],
      'message_count': _total,
      '_messages_offset': offset,
    },
  };
}

Map<String, Object?> _pagedResponse(int? messageBefore) {
  final before = messageBefore ?? _total;
  final from = (before - _pageSize).clamp(0, _total);
  return _page(from: from, to: before, offset: from);
}

Future<void> _pumpChatPage(WidgetTester tester, FakeChatApi api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const CupertinoApp(home: ChatPage(sessionId: _sessionId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('拉顶加载历史后：更早的消息必须出现在屏幕上方', (tester) async {
    final api = FakeChatApi()..sessionResultBuilder = _pagedResponse;
    await _pumpChatPage(tester, api);

    expect(
      api.sessionMessageBefore.where((b) => b != null),
      isEmpty,
      reason: '初始加载不应产生分页请求',
    );

    // 记录加载前屏幕上的相对关系（较新的一页：175..199）

    // 持续上拖进入顶部带（reverse：朝最旧端 = 增大 pixels）
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChatMessageList)),
    );
    await tester.pump();
    var guard = 0;
    while (guard < 200) {
      await gesture.moveBy(const Offset(0, 400));
      await tester.pump(const Duration(milliseconds: 16));
      guard++;
      final hit = api.sessionMessageBefore.where((b) => b != null).isNotEmpty;
      if (hit) break;
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      api.sessionMessageBefore.where((b) => b != null),
      isNotEmpty,
      reason: '拉到最顶必须触发分页',
    );

    // 诊断：屏幕上实际有哪些消息文本（断言失败时便于定位）
    final visible = <String, double>{};
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      final m = RegExp(r'历史消息 (\d+)').firstMatch(s);
      if (m == null) continue;
      final dy = (e.renderObject as RenderBox?)?.localToGlobal(Offset.zero).dy;
      if (dy != null) visible[m.group(1)!] = dy;
    }

    // ===== 核心断言：视觉位置（用实际可见的消息对比较） =====
    // 断言口径：所有可见消息里，序号更小者（更早）的 dy 必须更小（更靠上）。
    // 这直接对应主人看到的画面顺序，不依赖具体哪一条恰好可见。
    final entries = visible.entries
        .map((e) => MapEntry(int.parse(e.key), e.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    expect(
      entries.length,
      greaterThanOrEqualTo(2),
      reason: '至少应有两条消息可见才能判定上下顺序（实际: $visible）',
    );
    for (var i = 1; i < entries.length; i++) {
      final earlier = entries[i - 1];
      final later = entries[i];
      expect(
        earlier.value,
        lessThan(later.value),
        reason:
            '更早的消息 ${earlier.key} 必须在更新的 ${later.key} 上方；'
            '实际 ${earlier.key}@${earlier.value} vs ${later.key}@${later.value}'
            ' —— 若更早的 dy 更大，说明历史被渲染到了视觉下方（主人报告的 bug）',
      );
    }
  });
}
