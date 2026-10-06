import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ToolGroupCoalesceController 状态与持久化', () {
    test('默认值为 false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(toolGroupCoalesceProvider);
      expect(state, isFalse);
    });

    test('初始状态从 SharedPreferences 读取', () async {
      SharedPreferences.setMockInitialValues({kToolGroupCoalesceKey: true});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(toolGroupCoalesceProvider.notifier);
      await controller.load();

      final state = container.read(toolGroupCoalesceProvider);
      expect(state, isTrue);
    });

    test('setCoalesce 修改配置并写入 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(toolGroupCoalesceProvider.notifier);
      await controller.setCoalesce(true);

      expect(container.read(toolGroupCoalesceProvider), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kToolGroupCoalesceKey), isTrue);

      await controller.setCoalesce(false);
      expect(container.read(toolGroupCoalesceProvider), isFalse);
      expect(prefs.getBool(kToolGroupCoalesceKey), isFalse);
    });
  });

  group('TurnCollapseController 状态与持久化', () {
    test('默认值为 true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(turnCollapseProvider);
      expect(state, isTrue);
    });

    test('初始状态从 SharedPreferences 读取', () async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: false});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(turnCollapseProvider.notifier);
      await controller.load();

      final state = container.read(turnCollapseProvider);
      expect(state, isFalse);
    });

    test('setTurnCollapse 修改配置并写入 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(turnCollapseProvider.notifier);
      await controller.setTurnCollapse(false);

      expect(container.read(turnCollapseProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kTurnCollapseKey), isFalse);

      await controller.setTurnCollapse(true);
      expect(container.read(turnCollapseProvider), isTrue);
      expect(prefs.getBool(kTurnCollapseKey), isTrue);
    });
  });

  group('ToolCallGroup.groups 聚合与穿插', () {
    test('coalesce: true 聚合模式：合并同一回合内不同 assistant 消息的工具调用', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'hello', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          content: 'let me check',
          messageId: 'm1',
        ),
        const ChatMessage(
          role: 'assistant',
          content: '中间说明文字打断相邻',
          messageId: 'm_break',
        ),
        const ChatMessage(
          role: 'assistant',
          content: 'now editing',
          messageId: 'm2',
        ),
      ];
      final persistedCalls = [
        const PersistedToolCall(
          name: 'read_file',
          tid: 'call_1',
          assistantMsgIdx: 1,
        ),
        const PersistedToolCall(
          name: 'write_file',
          tid: 'call_2',
          assistantMsgIdx: 3,
        ),
      ];

      final aggregated = ToolCallGroup.groups(
        persistedToolCalls: persistedCalls,
        messages: messages,
        coalesce: true,
      );
      expect(aggregated, hasLength(1));
      expect(aggregated.single.anchorMessageID, 'm1');
      expect(aggregated.single.toolCalls, hasLength(2));
      expect(aggregated.single.toolCalls[0].id, 'call_1');
      expect(aggregated.single.toolCalls[1].id, 'call_2');
    });

    test('coalesce: false 穿插模式：保留独立 anchorMessageID 分别挂载在对应 assistant 消息旁', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'hello', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          content: 'let me check',
          messageId: 'm1',
        ),
        const ChatMessage(
          role: 'assistant',
          content: '中间说明文字打断相邻',
          messageId: 'm_break',
        ),
        const ChatMessage(
          role: 'assistant',
          content: 'now editing',
          messageId: 'm2',
        ),
      ];
      final persistedCalls = [
        const PersistedToolCall(
          name: 'read_file',
          tid: 'call_1',
          assistantMsgIdx: 1,
        ),
        const PersistedToolCall(
          name: 'write_file',
          tid: 'call_2',
          assistantMsgIdx: 3,
        ),
      ];

      final interleaved = ToolCallGroup.groups(
        persistedToolCalls: persistedCalls,
        messages: messages,
        coalesce: false,
      );
      expect(interleaved, hasLength(2));
      expect(interleaved[0].anchorMessageID, 'm1');
      expect(interleaved[0].toolCalls, hasLength(1));
      expect(interleaved[0].toolCalls.single.id, 'call_1');

      expect(interleaved[1].anchorMessageID, 'm2');
      expect(interleaved[1].toolCalls, hasLength(1));
      expect(interleaved[1].toolCalls.single.id, 'call_2');
    });

    test('从消息元数据派生时 coalesce 开关同样生效', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'query', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_1'),
              'function': JsonObject({
                'name': JsonString('grep'),
                'arguments': JsonString('{"pattern": "abc"}'),
              }),
            }),
          ],
        ),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm2',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_2'),
              'function': JsonObject({
                'name': JsonString('cat'),
                'arguments': JsonString('{"file": "a.txt"}'),
              }),
            }),
          ],
        ),
      ];

      final coalesced = ToolCallGroup.groups(
        persistedToolCalls: const [],
        messages: messages,
        coalesce: true,
      );
      expect(coalesced, hasLength(1));
      expect(coalesced.single.anchorMessageID, 'm1');
      expect(coalesced.single.toolCalls, hasLength(2));

      final nonCoalesced = ToolCallGroup.groups(
        persistedToolCalls: const [],
        messages: messages,
        coalesce: false,
      );
      // 连续无文本的工具调用即使在 coalesce=false 时也聚合（不被 text 打断的连续段）
      expect(nonCoalesced, hasLength(1));
      expect(nonCoalesced.single.anchorMessageID, 'm1');
      expect(nonCoalesced.single.toolCalls, hasLength(2));
    });
  });

  test('coalesce=false 时被文本打断的连续工具应拆分为 2 组（metadata 路径）', () {
    final messages = [
      const ChatMessage(role: 'user', content: 'query', messageId: 'u1'),
      const ChatMessage(
        role: 'assistant',
        messageId: 'm1',
        content: 'has text',
        toolCalls: [
          JsonObject({
            'id': JsonString('call_1'),
            'function': JsonObject({
              'name': JsonString('terminal'),
              'arguments': JsonString('{}'),
            }),
          }),
        ],
      ),
      const ChatMessage(
        role: 'assistant',
        messageId: 'm_break',
        content: '可见文本打断聚合',
      ),
      const ChatMessage(
        role: 'assistant',
        messageId: 'm2',
        toolCalls: [
          JsonObject({
            'id': JsonString('call_2'),
            'function': JsonObject({
              'name': JsonString('terminal'),
              'arguments': JsonString('{}'),
            }),
          }),
        ],
      ),
    ];

    final nonCoalesced = ToolCallGroup.groups(
      persistedToolCalls: const [],
      messages: messages,
      coalesce: false,
    );
    // m1 has text, so m2 should be separate group
    expect(nonCoalesced, hasLength(2));
    expect(nonCoalesced[0].anchorMessageID, 'm1');
    expect(nonCoalesced[1].anchorMessageID, 'm2');
  });

  group('SettingsPage 对话分区 Widget 测试', () {
    testWidgets('渲染工具按回合聚合开关并响应点击切换', (tester) async {
      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: InMemorySecureStorage()),
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          settingsApiFactoryProvider.overrideWithValue(
            (_) => FakeSettingsApi(),
          ),
          onboardingApiFactoryProvider.overrideWithValue(
            (_, _) => FakeOnboardingLoginApi(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // HiDPI（#164）：设置页新增「界面缩放」项后整体变长，默认 800x600 视口下
      // 「对话」分区的开关会被推到视口外 => tap 打空（hitTest 只有 render view）、
      // 断言以「开关状态没变」这种迷惑方式失败。这里给一个**高视口**让内容整体可见，
      // 比依赖 ensureVisible 更稳、也与布局细节解耦（宽度仍 800 => 仍是窄屏，语义不变）。
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(
        const ValueKey('settings-group-tools-by-turn'),
      );
      final switchFinder = find.byKey(
        const ValueKey('settings-switch-group-tools-by-turn'),
      );

      expect(find.text('对话'), findsOneWidget);
      expect(find.text('工具按回合聚合'), findsOneWidget);
      expect(
        find.text('开启：整轮工具合成一张折叠卡；关闭：仅相邻工具合并，被文本/思考打断则分离'),
        findsOneWidget,
      );

      expect(tileFinder, findsOneWidget);
      expect(switchFinder, findsOneWidget);

      // 默认关闭
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);

      // 点击切换为开启
      // HiDPI（#164）：新增「界面缩放」项让设置页变长，目标控件可能滚出视口 =>
      // tap 前先滚到它（否则 hitTest 打空，开关状态不变导致断言失败）。
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(toolGroupCoalesceProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kToolGroupCoalesceKey), isTrue);

      // 再次点击恢复关闭
      // HiDPI（#164）：新增「界面缩放」项让设置页变长，目标控件可能滚出视口 =>
      // tap 前先滚到它（否则 hitTest 打空，开关状态不变导致断言失败）。
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(toolGroupCoalesceProvider), isFalse);
      expect(prefs.getBool(kToolGroupCoalesceKey), isFalse);
    });

    testWidgets('渲染回合过程折叠开关并响应点击切换', (tester) async {
      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: InMemorySecureStorage()),
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          settingsApiFactoryProvider.overrideWithValue(
            (_) => FakeSettingsApi(),
          ),
          onboardingApiFactoryProvider.overrideWithValue(
            (_, _) => FakeOnboardingLoginApi(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(const ValueKey('settings-turn-collapse'));
      final switchFinder = find.byKey(
        const ValueKey('settings-switch-turn-collapse'),
      );

      expect(tileFinder, findsOneWidget);
      expect(switchFinder, findsOneWidget);
      expect(find.text('折叠回合过程'), findsOneWidget);
      expect(find.text('默认只显示提问和最终答复'), findsOneWidget);

      // 默认开启
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);

      // 点击切换为关闭
      // 设置页会随新增项变长（#164 界面缩放、页面底色）：目标控件可能落到视口
      // 之外 ⇒ tap 前必须把它滚进视口，否则 hitTest 打空、开关状态不变。
      // 用 scrollUntilVisible 显式指定滚动体并滚到「命中为止」——
      // ensureVisible 只走「最近的可滚动祖先」，滚动量不足以让中心点进入视口
      // 时仍会打空（实测 800×600 下目标落在 y=630 > 600）。
      await tester.scrollUntilVisible(
        switchFinder,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(turnCollapseProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kTurnCollapseKey), isFalse);

      // 再次点击恢复开启
      // HiDPI（#164）：新增「界面缩放」项让设置页变长，目标控件可能滚出视口 =>
      // tap 前先滚到它（否则 hitTest 打空，开关状态不变导致断言失败）。
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(turnCollapseProvider), isTrue);
      expect(prefs.getBool(kTurnCollapseKey), isTrue);
    });
  });

  group('ChatMessageList 工具按回合聚合与穿插渲染测试', () {
    testWidgets('coalesce 开关控制多工具卡片的合并与穿插渲染，无 double 副本', (tester) async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: false});
      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 'sess-tools-test',
          'title': '测试工具分组',
          'messages': [
            {'role': 'user', 'content': '请执行操作', 'message_id': 'u1'},
            {'role': 'assistant', 'content': '读取完毕', 'message_id': 'm1'},
            {
              'role': 'assistant',
              'content': '我先确认一下格式',
              'message_id': 'm_break',
            },
            {'role': 'assistant', 'content': '写入完毕', 'message_id': 'm2'},
          ],
          'tool_calls': [
            {
              'name': 'read_file',
              'snippet': 'Read content',
              'tid': 'call_1',
              'assistant_msg_idx': 1,
            },
            {
              'name': 'write_file',
              'snippet': 'Wrote content',
              'tid': 'call_2',
              'assistant_msg_idx': 3,
            },
          ],
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(fakeApi)],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: ChatMessageList(sessionId: 'sess-tools-test'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ChatMessageList));
      final container = ProviderScope.containerOf(element);

      // 1. 默认 coalesce: false 模式下：中间文本打断相邻聚合 → 2 张独立卡片穿插呈现，绝无 double 副本
      expect(find.byType(ToolCallGroupCard), findsNWidgets(2));
      expect(find.text('读取文件 \u00D71'), findsOneWidget);
      expect(find.text('写入文件 \u00D71'), findsOneWidget);
      // 确认无聚合卡片残余副本
      expect(find.text('读取文件 \u00D71, 写入文件 \u00D71'), findsNothing);

      // 2. 切换为 coalesce: true 模式：同回合多个 assistant 消息的工具聚合为 1 张 ToolCallGroupCard 卡片
      await container
          .read(toolGroupCoalesceProvider.notifier)
          .setCoalesce(true);
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallGroupCard), findsNWidgets(1));
      expect(find.text('读取文件 \u00D71, 写入文件 \u00D71'), findsOneWidget);

      // 3. 再次切换回 coalesce: false 模式：即时恢复为 2 张穿插卡片
      await container
          .read(toolGroupCoalesceProvider.notifier)
          .setCoalesce(false);
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallGroupCard), findsNWidgets(2));
      expect(find.text('读取文件 \u00D71'), findsOneWidget);
      expect(find.text('写入文件 \u00D71'), findsOneWidget);
      expect(find.text('读取文件 \u00D71, 写入文件 \u00D71'), findsNothing);

      // 清理树与 Timer
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('coalesce: false 时空 transcript 不渲染 fallback 聚合卡片', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({kToolGroupCoalesceKey: false});

      final fakeApi = FakeChatApi();
      fakeApi.sessionResult = {
        'session': {
          'session_id': 'sess-empty-transcript',
          'title': '空消息会话',
          'messages': <Map<String, dynamic>>[],
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(fakeApi)],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: ChatMessageList(sessionId: 'sess-empty-transcript'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ChatMessageList));
      final container = ProviderScope.containerOf(element);
      await container
          .read(toolGroupCoalesceProvider.notifier)
          .setCoalesce(false);
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallGroupCard), findsNothing);

      // 清理树与 Timer
      await tester.pumpWidget(const SizedBox());
    });
  });
}
