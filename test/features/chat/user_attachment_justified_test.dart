import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/message_attachment.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/chat/widgets/user_attachment_block.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **justified 宫格（多图单行等高）真渲染几何守卫**（主人 2026-10-08 拍板档 4）。
///
/// 断言全部是**几何读数**（`tester.getRect`），不看像素观感：
/// ① 行内各瓦片实测高度差 ≤ 0.5px；
/// ② 每张瓦片**渲染盒的宽高比 vs 源图宽高比**偏差 ≤ 2%（证明没裁切、没变形）；
/// ③ 每行总宽（含间距）= 气泡可用宽（未收高时），且**永不超过**（不溢出）；
/// ④ 首帧（图未解码）瓦片尺寸非 0、整行照样铺满 —— 证明「不塌陷」。
///
/// **RED 自查**：若把实现退回「96×96 方形 cover 裁切」，判据 ② 立刻红 ——
/// 竖 3:4 图会被渲染成 1.0 的盒比，源图比 0.75，偏差 33% ≫ 2%
/// （实测见交付说明的 RED 证据段）。
///
/// ⚠️ 工装纪律（踩过的坑，别改回去）：
/// - 预热必须**先挂一棵最小树**再 `runAsync + precacheImage`。在**含
///   `CupertinoActivityIndicator`（无限动画）的真界面上**调 `runAsync` 会
///   **无限挂起**：无报错、无失败行，测试日志停在用例名上（实测探针：
///   最小树先预热 → 0 秒过；真界面挂上再预热 → 25s 超时）。
/// - 文件 IO 一律同步写（FakeAsync 体内裸 `await` 真实文件 IO 同样会挂死）。
/// - 每个用例都挂 `timeout`：挂死必须快速变红，而不是把整轮测试拖死。
const Timeout _timeout = Timeout(Duration(seconds: 60));
const String _baseUrl = 'http://test.local:30002';
const String _sessionId = 's1';
const String _imgPrefix = r'C:\Users\Admin\attachments\s1';

/// 四张真实 PNG（字节内联，测试自带、不依赖外部夹具）。
/// 尺寸刻意错开，让「盒比 == 源图比」这条判据在裁切/变形时必然报警。
const Map<String, String> _base64 = <String, String>{
  'pt.png':
      'iVBORw0KGgoAAAANSUhEUgAAAB4AAAAoCAIAAABmcd1FAAAAPklEQVR42u3XsQ0AIAzEwA9i'
      'J6pMnypThSX4Aske4HrHzMjTltSZz91TtWQLGhoaGhoaGhoaGhr6Rzp8c3cB3rAJS82fy+MA'
      'AAAASUVORK5CYII=',
  'ls.png':
      'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAAQElEQVR42u3XMRUAIAzE0CsP'
      'T0yIQGlFMKGqaGDhlsTAnxNVJUdd0lzns7pzNJkCBgYGBgYGBgYGBgZ+L1zTdgHnUwk3J/SO'
      'iwAAAABJRU5ErkJggg==',
  'uw.png':
      'iVBORw0KGgoAAAANSUhEUgAAADAAAAAbCAIAAAC1C5slAAAAQUlEQVR42u3XQQ0AIBTD0H2C'
      'LWRwQh8nZCBs2FhCq+BdW7aVVJc0zgrR3LmbwgIECBAgQIAAAQIECBCgz0CVdq4PVhEJMWjp'
      'ugwAAAAASUVORK5CYII=',
  'sq.png':
      'iVBORw0KGgoAAAANSUhEUgAAACEAAAAhCAIAAADYhlU4AAAAPklEQVR42u3XMREAIAwEwQ+D'
      'MSq0oChaqJAWRDBPdWdg64uqkrkuKefxAWuPJn8YGBgYGBgYGBgYGG/Fh/+4Z7MJPZGfrL0A'
      'AAAASUVORK5CYII=',
  // 6 张用例需要**文件名互不相同**（同名的两张会撞 `user-attachment-image-*`
  // 测试锚点，finder 直接判歧义）；字节与 pt/ls 相同，比例照旧。
  'pt2.png':
      'iVBORw0KGgoAAAANSUhEUgAAAB4AAAAoCAIAAABmcd1FAAAAPklEQVR42u3XsQ0AIAzEwA9i'
      'J6pMnypThSX4Aske4HrHzMjTltSZz91TtWQLGhoaGhoaGhoaGhr6Rzp8c3cB3rAJS82fy+MA'
      'AAAASUVORK5CYII=',
  'ls2.png':
      'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAAQElEQVR42u3XMRUAIAzE0CsP'
      'T0yIQGlFMKGqaGDhlsTAnxNVJUdd0lzns7pzNJkCBgYGBgYGBgYGBgZ+L1zTdgHnUwk3J/SO'
      'iwAAAABJRU5ErkJggg==',
};

/// 源图像素尺寸（宽 × 高）—— 与上面的 base64 一一对应。
const Map<String, (int, int)> _sources = <String, (int, int)>{
  'pt.png': (30, 40), // 竖 3:4
  'ls.png': (40, 30), // 横 4:3
  'uw.png': (48, 27), // 超宽 16:9
  'sq.png': (33, 33), // 方 1:1
  'pt2.png': (30, 40), // 竖 3:4（6 张用例补齐张数）
  'ls2.png': (40, 30), // 横 4:3（6 张用例补齐张数）
};

/// 混比例池：竖 3:4 / 横 4:3 / 超宽 16:9 / 方 1:1（再补两张不同名的竖、横）。
const List<String> _pool = [
  'pt.png',
  'ls.png',
  'uw.png',
  'sq.png',
  'pt2.png',
  'ls2.png',
];

/// 气泡可用宽（= 气泡宽 − 左右内边距 24）。
/// - 296   ⇔ 宽屏（1280 逻辑宽）三图气泡 320；
/// - 269.28 ⇔ 手机 400 逻辑宽，`0.78` 上限反算出的气泡宽 293.28。
const double _wideAvailable = 296.0;
const double _phoneAvailable =
    376 * UserAttachmentBlock.bubbleMaxWidthRatio -
    UserAttachmentBlock.bubbleHorizontalPadding;

late Map<String, File> _files;

/// 造 N 张混比例附件名（循环 竖 / 横 / 超宽 / 方 / 竖 / 横）。
List<String> _mixed(int count) => [
  for (var i = 0; i < count; i++) _pool[i % _pool.length],
];

List<MessageAttachment> _attachments(List<String> names) => [
  for (final name in names)
    MessageAttachment(name: name, path: '$_imgPrefix\\$name', isImage: true),
];

File _fileForUrl(String url) {
  var probe = url;
  try {
    probe = Uri.parse(url).queryParameters['path'] ?? url;
  } catch (_) {
    // 非法 URL：退回原串比对
  }
  for (final entry in _files.entries) {
    if (probe.endsWith(entry.key) || url.endsWith(entry.key)) {
      return entry.value;
    }
  }
  throw StateError('没有匹配的测试图：$url');
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      mediaFileProvider.overrideWith((ref, url) async => _fileForUrl(url)),
    ],
  );
  return container;
}

Widget _app(ProviderContainer container, List<String> names, {double? width}) =>
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: CupertinoPageScaffold(
          backgroundColor: CupertinoColors.white,
          child: Center(
            child: SizedBox(
              width: width ?? _wideAvailable,
              child: UserAttachmentBlock(
                attachments: _attachments(names),
                baseUrl: _baseUrl,
                sessionId: _sessionId,
              ),
            ),
          ),
        ),
      ),
    );

Map<String, Rect> _rects(WidgetTester tester, List<String> names) => {
  for (final name in names)
    name: tester.getRect(
      find.byKey(ValueKey<String>('user-attachment-image-$name')),
    ),
};

/// 按实测 `top` 分组：同一行的瓦片顶边必然相等（同一 Row 内等高）。
List<List<String>> _rowsOf(Map<String, Rect> rects, List<String> names) {
  final sorted = [...names]
    ..sort((a, b) {
      final byTop = rects[a]!.top.compareTo(rects[b]!.top);
      return byTop != 0 ? byTop : rects[a]!.left.compareTo(rects[b]!.left);
    });
  final rows = <List<String>>[];
  for (final name in sorted) {
    if (rows.isNotEmpty &&
        (rects[rows.last.first]!.top - rects[name]!.top).abs() < 0.5) {
      rows.last.add(name);
    } else {
      rows.add([name]);
    }
  }
  return rows;
}

/// 三条几何判据的公共检查（行内等高 / 盒比==源图比 / 整行填满不溢出）。
void _expectJustified(
  Map<String, Rect> rects,
  List<String> names,
  double available, {
  required String label,
}) {
  final rows = _rowsOf(rects, names);
  var seen = 0;
  for (final row in rows) {
    final heights = [for (final name in row) rects[name]!.height];
    final maxHeight = heights.reduce(mathMax);
    final minHeight = heights.reduce(mathMin);
    final widthSum = row.fold<double>(
      0,
      (total, name) => total + rects[name]!.width,
    );
    final rowWidth = widthSum + UserAttachmentBlock.tileGap * (row.length - 1);
    var maxDeviation = 0.0;
    for (final name in row) {
      final source = _sources[name]!;
      final sourceAspect = source.$1 / source.$2;
      final boxAspect = rects[name]!.width / rects[name]!.height;
      maxDeviation = mathMax(
        maxDeviation,
        (boxAspect - sourceAspect).abs() / sourceAspect,
      );
    }
    debugPrint(
      'EVIDENCE $label row=[${row.join(",")}] h=${maxHeight.toStringAsFixed(3)} '
      'Δh=${(maxHeight - minHeight).toStringAsFixed(4)} '
      'w=${row.map((n) => rects[n]!.width.toStringAsFixed(2)).toList()} '
      'rowW=${rowWidth.toStringAsFixed(3)} avail=${available.toStringAsFixed(3)} '
      'maxAspectDev=${(maxDeviation * 100).toStringAsFixed(3)}%',
    );
    expect(
      maxHeight - minHeight,
      lessThanOrEqualTo(0.5),
      reason: '$label 行内瓦片高度差 ${(maxHeight - minHeight)}px > 0.5px',
    );
    for (final name in row) {
      final source = _sources[name]!;
      final sourceAspect = source.$1 / source.$2;
      final boxAspect = rects[name]!.width / rects[name]!.height;
      final deviation = (boxAspect - sourceAspect).abs() / sourceAspect;
      expect(
        deviation,
        lessThanOrEqualTo(0.02),
        reason:
            '$label $name 渲染盒比 $boxAspect vs 源图比 $sourceAspect '
            '偏差 ${(deviation * 100).toStringAsFixed(2)}% > 2%（= 被裁切/变形）',
      );
    }
    expect(
      rowWidth,
      lessThanOrEqualTo(available + 0.5),
      reason: '$label 行宽 $rowWidth 溢出可用宽 $available',
    );
    if (maxHeight < UserAttachmentBlock.kJustifiedMaxRowHeight - 0.001) {
      expect(
        rowWidth,
        closeTo(available, 0.5),
        reason: '$label 未收高的行必须正好填满可用宽（不留白）',
      );
    }
    seen += row.length;
  }
  expect(seen, names.length, reason: '$label 有瓦片没被量到');
}

double _rowWidthOf(Map<String, Rect> rects, List<String> names) =>
    names.fold<double>(0, (total, name) => total + rects[name]!.width) +
    UserAttachmentBlock.tileGap * (names.length - 1);

double mathMax(double a, double b) => a > b ? a : b;
double mathMin(double a, double b) => a < b ? a : b;

void main() {
  setUpAll(() {
    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}attach_justified',
    )..createSync(recursive: true);
    // ⚠️ 同步写：FakeAsync 体内裸 await 真实文件 IO 会挂死。
    _files = {
      for (final entry in _base64.entries)
        entry.key: File('${dir.path}${Platform.pathSeparator}${entry.key}')
          ..writeAsBytesSync(base64Decode(entry.value)),
    };
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 预热：**先挂一棵最小树**再 `runAsync + precacheImage`。
  ///
  /// flutter_test 的 fake async 不推进 `Image.file` 的文件 IO + 解码，不预热
  /// 瓦片就永远停在 loading 白块；而在**真界面**（含无限动画的 loading 指示器）
  /// 上调 `runAsync` 会无限挂起 —— 所以预热只能在最小树上做。
  Future<void> warmCache(WidgetTester tester) async {
    await tester.pumpWidget(const CupertinoApp(home: SizedBox.shrink()));
    final warm = tester.element(find.byType(SizedBox));
    await tester.runAsync(() async {
      for (final file in _files.values) {
        await precacheImage(FileImage(file), warm);
      }
    });
  }

  /// 挂真界面并推进到稳定帧（图已在 ImageCache 时，固有尺寸回调当帧就到）。
  Future<void> pumpBlock(
    WidgetTester tester,
    ProviderContainer container,
    List<String> names, {
    required double width,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(container, names, width: width));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  testWidgets('宽 296（1280 宽屏气泡）· 3 张混比例：行内等高、盒比==源图比、整行填满', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    final names = ['pt.png', 'ls.png', 'uw.png'];
    await warmCache(tester);
    await pumpBlock(tester, container, names, width: _wideAvailable);

    expect(tester.takeException(), isNull);
    final rects = _rects(tester, names);
    _expectJustified(rects, names, _wideAvailable, label: 'wide3');
    // 档 4 参考形态：三张**一行**（不是两行），行高 ≈74.6。
    expect(_rowsOf(rects, names), hasLength(1));
  }, timeout: _timeout);

  testWidgets('宽 269.28（手机 400 气泡）· 3 张混比例：同样一行等高填满', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    final names = ['pt.png', 'ls.png', 'uw.png'];
    await warmCache(tester);
    await pumpBlock(tester, container, names, width: _phoneAvailable);

    expect(tester.takeException(), isNull);
    final rects = _rects(tester, names);
    _expectJustified(rects, names, _phoneAvailable, label: 'phone3');
    expect(_rowsOf(rects, names), hasLength(1));
  }, timeout: _timeout);

  testWidgets('同一消息两张同名附件：不得抛 Duplicate keys，两张都出瓦片', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    // 同名 ⇒ `_identityOf` 退化成同一个文件名；旧实现会在同一 Row 里放两个相同
    // ValueKey，debug 下 Flutter 直接抛「Duplicate keys found」。
    final names = ['ls.png', 'ls.png'];
    await warmCache(tester);
    await pumpBlock(tester, container, names, width: _wideAvailable);

    expect(
      tester.takeException(),
      isNull,
      reason: '同名附件撞 ValueKey 会被 Flutter 直接抛出来',
    );
    // 首张保持原锚点，第二张带 `#1` 去重后缀 —— 既有工装/测试的锚点约定不受影响。
    expect(
      find.byKey(const ValueKey('user-attachment-image-ls.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('user-attachment-image-ls.png#1')),
      findsOneWidget,
    );
  }, timeout: _timeout);

  testWidgets('2 / 3 / 4 / 6 张混比例 · 两档可用宽：逐行等高、逐行填满、无溢出', (tester) async {
    await warmCache(tester);
    for (final available in [_wideAvailable, _phoneAvailable]) {
      for (final count in [2, 3, 4, 6]) {
        final container = _container();
        addTearDown(container.dispose);
        final names = _mixed(count);
        await pumpBlock(tester, container, names, width: available);
        expect(tester.takeException(), isNull, reason: 'n=$count 有渲染异常');
        _expectJustified(
          _rects(tester, names),
          names,
          available,
          label: 'n$count@${available.toStringAsFixed(1)}',
        );
      }
    }
  }, timeout: _timeout);

  testWidgets('首帧不塌陷：未预热时瓦片尺寸非 0、整行照样铺满；就绪后收敛到真比例', (tester) async {
    // 冷启：整幅图缓存清空（本用例必须从「图未解码」开始）。
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    final container = _container();
    addTearDown(container.dispose);
    final names = ['pt.png', 'ls.png', 'uw.png'];
    await pumpBlock(tester, container, names, width: _wideAvailable);

    // ---- 首帧（图没解码，比例未知 → 稳定 1:1 占位）----
    final cold = _rects(tester, names);
    for (final name in names) {
      expect(
        cold[name]!.width,
        greaterThan(0),
        reason: '$name 首帧宽度塌成 0（主人所担心的「抽一下」）',
      );
      expect(cold[name]!.height, greaterThan(0), reason: '$name 首帧高度塌成 0');
      // 三张 1:1 占位：宽 = 高 = (296 − 4×2) / 3 = 96。
      expect(cold[name]!.width, closeTo(96, 0.5));
      expect(cold[name]!.height, closeTo(96, 0.5));
    }
    final coldRowWidth = _rowWidthOf(cold, names);
    expect(coldRowWidth, closeTo(_wideAvailable, 0.5), reason: '首帧整行没铺满');

    // ---- 就绪后：最小树预热 → 重挂真界面（新 State，但图已在缓存）----
    // ⚠️ 预热前必须再清一次图缓存：冷启那帧的 `FileImage` 加载是在 FakeAsync
    // zone 里发起的、**永远不会完成**；`precacheImage` 会加入同一个 pending
    // completer 从而无限挂起。清掉 pending 条目，让预热在真实 zone 里重新解码。
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await warmCache(tester);
    await pumpBlock(tester, container, names, width: _wideAvailable);
    final warm = _rects(tester, names);
    _expectJustified(warm, names, _wideAvailable, label: 'warm3');

    final warmRowWidth = _rowWidthOf(warm, names);
    debugPrint(
      'EVIDENCE first-frame-vs-ready '
      'rowWidth cold=${coldRowWidth.toStringAsFixed(3)} '
      'warm=${warmRowWidth.toStringAsFixed(3)} '
      'delta=${(warmRowWidth - coldRowWidth).abs().toStringAsFixed(3)} | '
      'tileH cold=${cold[names.first]!.height.toStringAsFixed(3)} '
      'warm=${warm[names.first]!.height.toStringAsFixed(3)}'
      '（比例未知时按 1:1 占位，就绪后按真比例重排）',
    );
    // 整行宽（决定气泡会不会「缩一下再弹开」的量）首帧与就绪后完全一致。
    expect(warmRowWidth, closeTo(coldRowWidth, 0.5));
    expect(tester.takeException(), isNull);
  }, timeout: _timeout);
}
