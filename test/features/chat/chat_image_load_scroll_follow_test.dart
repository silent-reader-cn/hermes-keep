import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_media_cache.dart';

/// 100×300 红色 PNG：在气泡约束下渲染高约 308，远大于 160×120 加载占位 →
/// 图片解码完成后 maxScrollExtent **单向增长**（extent-only 变化）。
///
/// 这是回归守卫的关键前提：extent 增长不移动 pixels，SDK 不触发
/// ScrollPosition 监听与 ScrollNotification 族（旧实现因此存在盲区，
/// 底部跟随被打断）；只有 ScrollMetricsNotification 能感知。
/// 旧版用例用 1×1 透明图（渲染后比占位符更小，且 fakeAsync 下真实下载
/// IO 不推进、图片从未解码）——测试空转通过，盲区长期存活。本文件重写
/// 为「mediaFileProvider 覆盖 + runAsync 放行真实解码」，并显式断言
/// extent 确实增长，杜绝再次空转。
const _kTallPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAGQAAAEsCAIAAAC6/IG2AAACe0lEQVR4nO3SsQ3A'
    'IBAEQXBd9C/Kcgu/AdlMfNHq9j1nMfMNd4jVeFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIJZYb3hWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYg'
    'ViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViBWIFYgViDWmvsB'
    '2DEDmCdzWyEAAAAASUVORK5CYII=';

class _FakeActiveConnectionController extends ActiveConnectionController {
  _FakeActiveConnectionController(this._initial);
  final ServerConnection? _initial;
  @override
  ServerConnection? build() => _initial;
}

void main() {
  group('图片异步加载撑高列表（extent-only 增长）滚动跟随回归', () {
    late File tallPngFile;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tallPngFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}tall_img_fixture.png',
      );
      tallPngFile.writeAsBytesSync(base64Decode(_kTallPngBase64));
    });

    tearDown(() {
      try {
        tallPngFile.deleteSync();
      } on FileSystemException {
        // ignore
      }
    });

    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    ChatMessageListState stateOf(WidgetTester tester) {
      return tester.state<ChatMessageListState>(
        find.byType(ChatMessageList).first,
      );
    }

    List<Map<String, dynamic>> generateMessages({
      required int count,
      Map<int, String>? imageAt,
    }) {
      return List.generate(count, (i) {
        final imgUrl = imageAt?[i];
        final content = imgUrl != null
            ? '图片消息 $i：MEDIA:$imgUrl'
            : '测试文本消息第 $i 轮：用于撑高滚动视图的内容。' * 4;
        return {
          'role': i.isEven ? 'user' : 'assistant',
          'content': content,
          'message_id': 'm-$i',
        };
      });
    }

    /// 推进固定帧完成初始布局与收敛（避开 CupertinoActivityIndicator
    /// 无限动画导致 pumpAndSettle 超时）。
    Future<void> pumpInitialSettlement(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// 放行真实事件循环完成图片解码（`Image.file` 解码走真实异步，
    /// FakeAsync 不推进；runAsync + pump 轮询直到 RawImage 出帧）。
    Future<void> pumpImageDecodeFrames(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpChatWithImages(
      WidgetTester tester, {
      required String sessionId,
      required List<Map<String, dynamic>> messages,
      required Future<File> Function(String url) fileFor,
    }) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': sessionId,
          'messages': messages,
          'message_count': messages.length,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _FakeActiveConnectionController(null),
            ),
            appDatabaseProvider.overrideWithValue(rig.database),
            chatApiProvider.overrideWithValue(api),
            mediaCacheOverride(rig.service),
            mediaFileProvider.overrideWith((ref, url) => fileFor(url)),
          ],
          child: CupertinoApp(home: ChatPage(sessionId: sessionId)),
        ),
      );
    }

    testWidgets('1. 跟随态末尾大图异步加载撑高：extent-only 增长后自动补跳贴底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<File>();
      await pumpChatWithImages(
        tester,
        sessionId: 's-img-grow',
        messages: generateMessages(
          count: 20,
          imageAt: {19: 'https://example.com/tall_photo.png'},
        ),
        fileFor: (_) => imageCompleter.future,
      );

      await pumpInitialSettlement(tester);

      final state = stateOf(tester);
      final pos = positionOf(tester);
      expect(state.initialPositioned, isTrue);
      expect(state.nearBottom, isTrue);
      expect(state.userHasScrolled, isFalse);
      expect(pos.pixels, closeTo(0.0, 1.0));
      final extentBefore = pos.maxScrollExtent;

      imageCompleter.complete(tallPngFile);
      await pumpImageDecodeFrames(tester);

      // 防呆：图片必须真的解码出帧、extent 必须真的增长，否则本用例退化为
      // 空转（旧版盲区存活多年的原因之一）。
      expect(
        find.byType(RawImage),
        findsWidgets,
        reason: '图片应完成解码渲染，否则用例失去回归意义',
      );
      expect(
        pos.maxScrollExtent,
        greaterThan(extentBefore + 100),
        reason: '大图应显著撑高 extent（$extentBefore → ${pos.maxScrollExtent}）',
      );

      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);
      expect(
        pos.pixels,
        closeTo(0.0, 1.0),
        reason:
            'extent 撑高后必须补跳贴底（pixels=${pos.pixels}, max=${pos.maxScrollExtent}）',
      );
      expect(find.text('回到底部'), findsNothing);
    });

    testWidgets('2. 两张大图先后加载：连续两次撑高均保持贴底跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final completer1 = Completer<File>();
      final completer2 = Completer<File>();
      await pumpChatWithImages(
        tester,
        sessionId: 's-img-multi',
        messages: generateMessages(
          count: 20,
          imageAt: {
            10: 'https://example.com/tall1.png',
            19: 'https://example.com/tall2.png',
          },
        ),
        fileFor: (url) =>
            url.contains('tall1') ? completer1.future : completer2.future,
      );

      await pumpInitialSettlement(tester);
      final state = stateOf(tester);
      final pos = positionOf(tester);
      expect(state.nearBottom, isTrue);

      completer1.complete(tallPngFile);
      await pumpImageDecodeFrames(tester);
      expect(state.nearBottom, isTrue);
      expect(state.userHasScrolled, isFalse);
      expect(pos.pixels, closeTo(0.0, 1.0));

      final extentMid = pos.maxScrollExtent;
      completer2.complete(tallPngFile);
      await pumpImageDecodeFrames(tester);
      expect(pos.maxScrollExtent, greaterThan(extentMid + 100));
      expect(state.nearBottom, isTrue);
      expect(state.userHasScrolled, isFalse);
      expect(pos.pixels, closeTo(0.0, 1.0));
    });

    testWidgets('3. 用户手势离底阅读时大图撑高：阅读位置不被拽动', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<File>();
      await pumpChatWithImages(
        tester,
        sessionId: 's-img-user-away',
        messages: generateMessages(
          count: 25,
          imageAt: {24: 'https://example.com/tall_late.png'},
        ),
        fileFor: (_) => imageCompleter.future,
      );

      await pumpInitialSettlement(tester);
      final scrollable = find.byType(Scrollable).first;
      final state = stateOf(tester);
      final pos = positionOf(tester);

      // drag 200px：保证末尾图片仍在 ListView cacheExtent（默认 250px）内
      // 保持 build；drag 过大图片节点被懒加载回收，用例退化为无图空转。
      await tester.drag(scrollable, const Offset(0, 200));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(state.userHasScrolled, isTrue);
      expect(state.nearBottom, isFalse);
      final readingPixels = pos.pixels;
      final extentBefore = pos.maxScrollExtent;
      // 阅读位置的真判据 = 固定**同一条**消息的屏幕 dy。大图撑高发生在列表
      // index 0 端（视觉底部），会把已有条目整体推上去；只钉 pixels（旧断言）
      // 恰好放过了这个位移。不能用「第一条可见气泡」——内容增长会让可视成员
      // 位移一位，那样取到的是另一条气泡。
      String? anchorText;
      double? anchorDy() {
        if (anchorText == null) {
          for (var i = 18; i < 26; i++) {
            final f = find.textContaining('测试文本消息第 $i 轮');
            if (f.evaluate().isEmpty) continue;
            final dy = tester.getTopLeft(f.first).dy;
            if (dy > 40 && dy < 500) {
              anchorText = '测试文本消息第 $i 轮';
              break;
            }
          }
        }
        final t = anchorText;
        if (t == null) return null;
        final f = find.textContaining(t);
        return f.evaluate().isEmpty ? null : tester.getTopLeft(f.first).dy;
      }

      final readingDy = anchorDy();
      expect(readingDy, isNotNull, reason: '前置：应能定位视口内的固定锚点消息');

      imageCompleter.complete(tallPngFile);
      await pumpImageDecodeFrames(tester);

      expect(find.byType(RawImage), findsWidgets, reason: '图须真解码，防退化空转');
      expect(
        pos.maxScrollExtent,
        greaterThan(extentBefore + 100),
        reason: '大图应撑高 extent（$extentBefore → ${pos.maxScrollExtent}）',
      );
      expect(state.userHasScrolled, isTrue);
      expect(state.nearBottom, isFalse);
      expect(
        anchorDy(),
        closeTo(readingDy!, 1.0),
        reason: '离底阅读位置不受大图撑高影响（屏幕坐标不动）',
      );
      expect(
        pos.pixels,
        greaterThanOrEqualTo(readingPixels - 0.5),
        reason: '补偿只应单向推进 pixels，视口不得被拽回底部',
      );
    });

    testWidgets('4. 点「回到底部」恢复跟随后，大图加载继续正常跟底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<File>();
      await pumpChatWithImages(
        tester,
        sessionId: 's-img-resume',
        messages: generateMessages(
          count: 25,
          imageAt: {24: 'https://example.com/tall_resume.png'},
        ),
        fileFor: (_) => imageCompleter.future,
      );

      await pumpInitialSettlement(tester);
      final scrollable = find.byType(Scrollable).first;
      final state = stateOf(tester);
      final pos = positionOf(tester);

      await tester.drag(scrollable, const Offset(0, 300));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(state.userHasScrolled, isTrue);
      expect(state.nearBottom, isFalse);

      await tester.tap(find.text('回到底部'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);

      imageCompleter.complete(tallPngFile);
      await pumpImageDecodeFrames(tester);

      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);
      expect(pos.pixels, closeTo(0.0, 1.0));
    });

    testWidgets('5. 大纲跳转主动离底后：大图撑高不拉回底部', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<File>();
      await pumpChatWithImages(
        tester,
        sessionId: 's-img-outline',
        messages: generateMessages(
          count: 30,
          imageAt: {29: 'https://example.com/tall_outline.png'},
        ),
        fileFor: (_) => imageCompleter.future,
      );

      await pumpInitialSettlement(tester);
      final state = stateOf(tester);
      final pos = positionOf(tester);

      state.outlineJumpTo('m-2', 2);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(state.userHasScrolled, isTrue, reason: '大纲跳转后进入离底阅读态');
      expect(state.nearBottom, isFalse);
      final jumpPixels = pos.pixels;

      imageCompleter.complete(tallPngFile);
      await pumpImageDecodeFrames(tester);

      expect(state.userHasScrolled, isTrue);
      expect(state.nearBottom, isFalse);
      expect(
        (pos.pixels - jumpPixels).abs(),
        lessThan(50.0),
        reason: '大纲跳转位置不受底部大图撑高影响',
      );
    });

    testWidgets('6. 搜索高亮定位进入会话：大图撑高不破坏离底阅读态', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<File>();
      final messages = generateMessages(
        count: 30,
        imageAt: {29: 'https://example.com/tall_highlight.png'},
      );
      messages[3]['content'] = '这是包含 UNIQUE_SEARCH_KEYWORD 的特殊历史消息';

      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-img-highlight',
          'messages': messages,
          'message_count': messages.length,
        },
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _FakeActiveConnectionController(null),
            ),
            appDatabaseProvider.overrideWithValue(rig.database),
            chatApiProvider.overrideWithValue(api),
            mediaCacheOverride(rig.service),
            mediaFileProvider.overrideWith((ref, url) => imageCompleter.future),
          ],
          child: const CupertinoApp(
            home: ChatPage(
              sessionId: 's-img-highlight',
              searchQuery: 'UNIQUE_SEARCH_KEYWORD',
              matchType: 'content',
            ),
          ),
        ),
      );

      await pumpInitialSettlement(tester);
      final state = stateOf(tester);
      final pos = positionOf(tester);

      expect(state.userHasScrolled, isTrue, reason: '高亮定位进入离底阅读态');
      expect(state.nearBottom, isFalse);
      final highlightPixels = pos.pixels;

      imageCompleter.complete(tallPngFile);
      await pumpImageDecodeFrames(tester);

      expect(state.userHasScrolled, isTrue);
      expect(state.nearBottom, isFalse);
      expect(
        (pos.pixels - highlightPixels).abs(),
        lessThan(50.0),
        reason: '高亮定位位置不被底部大图撑高破坏',
      );
    });
  });
}
