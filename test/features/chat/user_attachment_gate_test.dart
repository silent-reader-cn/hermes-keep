import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户消息里「图片附件气泡」两条确凿缺陷的守卫（2026-10-07 主人报告）：
///
/// - **② 返回再点开同消息后图片消失**：关闭自动加载时，用户点过「点击加载」的瓦片
///   只在 `_ChatInlineMediaWidgetState._forceLoaded` 里记状态 —— 状态跟着 widget
///   State 走，`返回`（瓦片卸载）即丢 ⇒ 再点开同消息又回到「点击加载」占位，
///   用户看到的就是「图片消失了」。
/// - **③ 关闭自动加载时，加载按钮与提醒不在 placeholder 的正中间**：闸门占位是
///   一个 `CrossAxisAlignment.start` + `mainAxisSize.min` 的 Column，落在 96×96
///   瓦片里被撑满后内容贴左上角（`Align` 缺省 topLeft）。
///
/// 两条都用**几何读数**断言（中心偏移 px / 锚点存在性），不靠像素观感。
const String kBaseUrl = 'http://test.local:30002';
const String kRawUri = 'C:\\Users\\Admin\\attachments\\s1\\pasted_image.png';
const ValueKey<String> kTileKey = ValueKey<String>('tile-under-test');
const ValueKey<String> kGateKey = ValueKey<String>(
  'chat-inline-media-tap-to-load',
);

/// 1×1 透明 PNG（喂给 mediaFileProvider 的替身，避免真实网络/磁盘缓存链路）。
final Uint8List kTinyPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0xDA, 0x63, 0x64, 0xF8, 0xCF, 0x50,
  0x0F, 0x00, 0x03, 0x86, 0x01, 0x80, 0x5A, 0x34,
  0x7D, 0x6B, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// 关闭自动加载图片（主人报告两条缺陷时的设置态）。
class _GateOff extends AutoLoadImagesController {
  @override
  bool build() => false;
}

void main() {
  late File tinyFile;

  setUpAll(() {
    // ⚠️ 不能裸 await 真实文件 IO（FakeAsync 体内会挂死）；同步写。
    tinyFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}attach_gate_1x1.png',
    )..writeAsBytesSync(kTinyPng);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(ProviderContainer container, Widget child) =>
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: CupertinoPageScaffold(child: Center(child: child)),
        ),
      );

  /// 真实排布下的一幕：`UserAttachmentBlock` 给每张图一个 96×96 的紧约束盒子
  /// （见 `user_attachment_block.dart` 的 `_imageTile`），闸门占位落在里面。
  Widget box({
    required double width,
    required double height,
    String name = 'pasted_image.png',
  }) => SizedBox(
    key: kTileKey,
    width: width,
    height: height,
    child: ChatInlineMediaWidget(
      rawUri: 'C:\\Users\\Admin\\attachments\\s1\\$name',
      title: name,
      alt: name,
      baseUrl: kBaseUrl,
      sessionId: 's1',
      maxWidth: width,
      maxHeight: height,
      fit: BoxFit.cover,
      padding: EdgeInsets.zero,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
    ),
  );

  Widget tile() => box(width: 96, height: 96);

  ProviderContainer container() => ProviderContainer(
    overrides: [
      autoLoadImagesProvider.overrideWith(_GateOff.new),
      mediaFileProvider.overrideWith((ref, url) async => tinyFile),
    ],
  );

  /// 闸门内容（图标行 ∪ 按钮）的中心必须落在盒子的中心上（≤1px）。
  Future<void> expectCentered(
    WidgetTester tester,
    ProviderContainer c,
    Widget child, {
    required String label,
  }) async {
    await tester.pumpWidget(wrap(c, child));
    await tester.pumpAndSettle();

    expect(find.byKey(kGateKey), findsOneWidget, reason: '$label：闸门占位应在');

    final boxRect = tester.getRect(find.byKey(kTileKey));
    final buttonRect = tester.getRect(find.byKey(kGateKey));
    final iconRect = tester.getRect(find.byIcon(CupertinoIcons.photo));
    final contentRect = iconRect.expandToInclude(buttonRect);
    final dx = (contentRect.center.dx - boxRect.center.dx).abs();
    final dy = (contentRect.center.dy - boxRect.center.dy).abs();
    // 读数写进失败信息里，方便把「偏了多少 px」贴进证据。
    expect(
      dx,
      lessThanOrEqualTo(1.0),
      reason:
          '$label 水平中心未居中（dx=$dx）：box=${boxRect.center} content=${contentRect.center}',
    );
    expect(
      dy,
      lessThanOrEqualTo(1.0),
      reason:
          '$label 垂直中心未居中（dy=$dy）：box=${boxRect.center} content=${contentRect.center}',
    );
    // 按钮自身也必须整块落在盒子里（贴边/溢出会越界）。
    expect(boxRect.contains(buttonRect.topLeft), isTrue, reason: label);
    expect(boxRect.contains(buttonRect.bottomRight), isTrue, reason: label);
  }

  testWidgets('③ 关闭自动加载：闸门内容落在 placeholder 正中间（96 瓦片 / 200×150 单图）', (
    tester,
  ) async {
    final c = container();
    addTearDown(c.dispose);
    // 宫格瓦片（多图）。
    await expectCentered(tester, c, tile(), label: '96×96 瓦片');
    // 单图 placeholder（`singleImageMaxWidth/Height` = 200×150）—— 主人报的就是这处。
    await expectCentered(
      tester,
      c,
      box(width: 200, height: 150),
      label: '200×150 单图占位',
    );
    // 长文件名也要居中（宽度按内容收缩，不再被 Flexible 拉满整行）。
    await expectCentered(
      tester,
      c,
      box(
        width: 200,
        height: 150,
        name: '20261007-123456-a-very-long-screenshot-name.png',
      ),
      label: '200×150 长名',
    );
  });

  testWidgets('② 返回再点开同消息：点过「点击加载」的图片不得退回占位', (tester) async {
    final c = container();
    addTearDown(c.dispose);

    await tester.pumpWidget(wrap(c, tile()));
    await tester.pumpAndSettle();
    expect(find.byKey(kGateKey), findsOneWidget, reason: '首次进入：闸门占位在');

    await tester.tap(find.byKey(kGateKey));
    await tester.pump();
    expect(find.byKey(kGateKey), findsNothing, reason: '点过加载：闸门应解除');

    // 「返回」：瓦片整棵子树卸载（导航回会话列表时真实发生的事）。
    await tester.pumpWidget(wrap(c, const SizedBox.shrink()));
    await tester.pump();

    // 「再点开同消息」：同一块瓦片重新挂上（ProviderContainer 不变 = 根 scope 不变）。
    await tester.pumpWidget(wrap(c, tile()));
    // ⚠️ 不能 pumpAndSettle：解闸后走的是真实图片链路，loading 态里的
    // CupertinoActivityIndicator 是无限动画，永远 settle 不了。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(kGateKey),
      findsNothing,
      reason: '返回再进后不得重新回到「点击加载」占位（主人所报「图片消失了」）',
    );
    expect(find.byType(Image), findsWidgets, reason: '返回再进后应直接进图片渲染链路（而不是占位）');
  });
}
