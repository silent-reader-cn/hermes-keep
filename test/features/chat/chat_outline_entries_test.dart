import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';

import '../../helpers/fake_chat_api.dart';

/// 大纲条目列表 = 主人的提问导航。
///
/// 覆盖：
/// 1. 后台任务完成 / 异步委派 / 定时任务回执等**服务端合成消息**（role 仍是
///    `user`）不得出现在大纲里，也不得占用轮次编号 —— 它们不是一轮提问；
/// 2. 主人手打的形似文本（`[IMPORTANT: hello]`）不得被误伤；
/// 3. 预览先剥离 `[Workspace::v1: …]` / `[Attached files: …]` 注入标记，
///    否则前 40 字会被工作区路径占满、看不出提问内容。
void main() {
  /// 服务端注入消息的真实形态（取自本机 `webui_30002/sessions/*.json` 实测：
  /// 带 `_source: process_wakeup` 或直接以 `[IMPORTANT:` / `[ASYNC DELEGATION`
  /// / `[System:` 开口）。
  const injectedSamples = <Map<String, dynamic>>[
    {
      'role': 'user',
      'content':
          '[IMPORTANT: Background process proc_2edf80c91c0a completed '
          '(exit_code=0).\nCommand: sleep 5\nOutput:\ndone',
      'message_id': 'sys-1',
      '_source': 'process_wakeup',
    },
    {
      'role': 'user',
      'content':
          '[ASYNC DELEGATION BATCH COMPLETE — deleg_aabf6cd3]\n'
          'A background subagent you launched has completed.',
      'message_id': 'sys-2',
      '_source': 'process_wakeup',
    },
    {
      'role': 'user',
      'content':
          '[IMPORTANT: You are running as a scheduled cron job. '
          'Execute the following task and finish.]',
      'message_id': 'sys-3',
    },
    {
      'role': 'user',
      'content':
          '[System: The previous response was cut off by a network error. '
          'Continue.',
      'message_id': 'sys-4',
    },
  ];

  Future<List<OutlineEntry>> outlineOf(
    WidgetTester tester, {
    required String sid,
    required List<Map<String, dynamic>> messages,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: false)
      ..sessionResult = {
        'session': {
          'session_id': sid,
          'title': '大纲条目会话',
          'messages': messages,
          'message_count': messages.length,
        },
      };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: CupertinoApp(home: ChatPage(sessionId: sid)),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ChatPage)),
    ).read(chatOutlineEntriesProvider(sid));
  }

  testWidgets('系统消息（后台任务完成/异步委派/定时任务/切断续跑）不进大纲且不占编号', (
    tester,
  ) async {
    final messages = <Map<String, dynamic>>[
      // 1) 真实提问（带服务端注入的 workspace 前缀）
      {
        'role': 'user',
        'content': '[Workspace::v1: D:\\projects\\hermes-ui]\n第一轮真实提问',
        'message_id': 'u-1',
      },
      {
        'role': 'assistant',
        'content': '第一轮回答',
        'message_id': 'a-1',
      },
      // 2) 后台任务完成通知（真实数据里的典型形态）
      injectedSamples[0],
      injectedSamples[1],
      {
        'role': 'assistant',
        'content': '收到后台结果后的回答',
        'message_id': 'a-2',
      },
      // 3) 定时任务 / 切断续跑
      injectedSamples[2],
      injectedSamples[3],
      // 4) 第二轮真实提问（带附件标记）
      {
        'role': 'user',
        'content': '第二轮真实提问\n\n[Attached files: uploads/a.png]',
        'message_id': 'u-2',
      },
      {'role': 'assistant', 'content': '第二轮回答', 'message_id': 'a-3'},
    ];

    final entries = await outlineOf(
      tester,
      sid: 's-outline-entries',
      messages: messages,
    );

    expect(
      entries.length,
      2,
      reason: '只有两轮真实提问；4 条服务端合成消息不得占行',
    );
    expect(entries.map((e) => e.index).toList(), <int>[1, 2]);
    expect(entries[0].preview, '第一轮真实提问',
        reason: '预览须剥离 [Workspace::v1: …] 注入前缀');
    expect(entries[1].preview, '第二轮真实提问',
        reason: '预览须剥离 [Attached files: …] 注入后缀');
    for (final e in entries) {
      expect(
        e.preview.contains('IMPORTANT'),
        isFalse,
        reason: '系统通知不得出现在大纲行里',
      );
    }
  });

  testWidgets('主人手打的形似文本不被误伤（窄白名单）', (tester) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'user',
        'content': '[IMPORTANT: hello] 这是主人手打的内容',
        'message_id': 'u-1',
      },
      {'role': 'assistant', 'content': '回答一', 'message_id': 'a-1'},
      {
        'role': 'user',
        'content': '第二条普通提问',
        'message_id': 'u-2',
      },
      {'role': 'assistant', 'content': '回答二', 'message_id': 'a-2'},
    ];

    final entries = await outlineOf(
      tester,
      sid: 's-outline-manual',
      messages: messages,
    );

    expect(
      entries.length,
      2,
      reason: '手打 [IMPORTANT: hello] 不是系统注入，仍算一轮提问',
    );
    expect(entries[0].preview, startsWith('[IMPORTANT: hello]'));
  });

  testWidgets('轮次编号按真实提问连续递增（系统消息不打断编号）', (tester) async {
    final messages = <Map<String, dynamic>>[];
    for (var i = 1; i <= 3; i++) {
      messages.add({
        'role': 'user',
        'content': '真实提问 $i',
        'message_id': 'u-$i',
      });
      messages.add(injectedSamples[0]);
      messages.add({
        'role': 'assistant',
        'content': '回答 $i',
        'message_id': 'a-$i',
      });
    }

    final entries = await outlineOf(
      tester,
      sid: 's-outline-indexing',
      messages: messages,
    );

    expect(entries.length, 3);
    expect(
      entries.map((e) => e.index).toList(),
      <int>[1, 2, 3],
      reason: '3 条系统通知不得把编号顶成 1/3/5',
    );
    expect(entries.map((e) => e.preview).toList(), <String>[
      '真实提问 1',
      '真实提问 2',
      '真实提问 3',
    ]);
  });
}
