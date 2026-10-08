import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 源码级守卫：**全应用 `CupertinoNavigationBar` 必须「关掉 SDK 默认边框 +
/// 常驻发丝线」**。
///
/// 为什么值得写一条源码扫描：这条口径是「约定」而不是类型能表达的东西 ——
/// 少写一个 `border: null`，SDK 的 `_kDefaultNavBarBorder`（1 物理像素黑 30%）
/// 就会随内容滚动淡入，与常驻发丝线叠成「新会话浅、有内容的会话一滚动就变深」
/// （主人 2026-10-08 报告的现象，SDK 源码里的 `_scrollAnimationValue` 机制）。
/// 单页渲染测试抓不到「别的新页面又忘了传」，故这里直接扫全仓。
void main() {
  test('lib/ 下每个 CupertinoNavigationBar 都 border: null 且有常驻发丝线', () {
    /// 例外（刻意的，附理由）。新增例外必须在这里写明原因。
    const whitelist = <String, String>{
      'lib/features/chat/widgets/chat_media_view.dart':
          '全屏媒体查看器：栏体恒黑，结构线在其上会变成一条亮线 ⇒ 刻意无线',
    };

    final violations = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '测试须在仓库根目录运行');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final source = entity.readAsStringSync();
      var index = source.indexOf('CupertinoNavigationBar(');
      while (index >= 0) {
        // 取出这次构造调用的实参文本（按括号配对收尾）。
        var depth = 0;
        var end = -1;
        for (var i = index; i < source.length; i++) {
          final ch = source[i];
          if (ch == '(') {
            depth++;
          } else if (ch == ')') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        if (end < 0) break;
        final body = source.substring(index, end + 1);
        final line = source.substring(0, index).split('\n').length;
        final where = '$path:$line';
        if (!whitelist.containsKey(path)) {
          if (!body.contains('border: null')) {
            violations.add('$where 缺 `border: null`（SDK 黑 30% 会随滚动淡入）');
          }
          if (!body.contains('NavBarHairline') && !body.contains('NavBarBottom')) {
            violations.add('$where 缺常驻发丝线（NavBarHairline / NavBarBottom）');
          }
        }
        index = source.indexOf('CupertinoNavigationBar(', end);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '导航栏底线口径见 lib/app/widgets/nav_bar_hairline.dart。\n'
          '违规点：\n  ${violations.join('\n  ')}',
    );
  });
}
