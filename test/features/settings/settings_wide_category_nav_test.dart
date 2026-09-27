import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/shared/wide_nav_rail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 关掉「关于」组的自动更新检查（测试纪律：不出网）。
class _NoUpdateController extends AutoCheckUpdateController {
  @override
  bool build() => false;
}

/// 批 3 · P1 守卫：设置页宽屏（≥900）左 220 分类导航 + 右内容限宽 744 居中；
/// 窄屏（<900）8 个 section 顺序长卷逐像素不变（像素级证据另见
/// `test/screenshots/narrow_pages_shots_test.dart` 的窄屏对照工装）。
///
/// 容器实际宽度（最容易搞错的一处，实测 hairline 定锚）：
/// 真机（带 shell）里会话侧栏 **320**（`AdaptiveShell`，AGENTS §5.3）+ 页内导航
/// **220** ⇒ 1280 窗口下右栏只剩 **740**（< 744，限宽不咬合，内容吃满右栏减去
/// 卡片自身 16 内边距；两侧仍相等）。本文件的用例**裸挂页面**，故右栏 = 视口 − 220
/// （1280 ⇒ 1060 ⇒ 744 咬合，左右各 158；1600 ⇒ 1380 ⇒ 左右各 318）。

/// 分类导航项 key → 该分类内可见行 key（断言「只渲染当前分类」）。
///
/// **Map 顺序 = 窄屏长卷的自上而下顺序**（与 `_SettingsPageState.build` 的 sliver
/// 顺序一致：定时在前、通知在后 —— 与左栏三组的组内顺序是两件事）。
const Map<String, String> _categoryProbes = {
  'appearance': 'settings-session-grouping',
  'chat': 'settings-send-message-shortcut',
  'server': 'server-add',
  'model': 'settings-default-model',
  'scheduled': 'settings-show-cron-sessions',
  'notification': 'settings-notify-turns',
  'advanced': 'settings-entry-auxiliary',
  'about': 'settings-repo-tile',
};

Future<ProviderContainer> _container() async {
  final store = ConnectionStore(storage: InMemorySecureStorage());
  await store.save(
    ServerConnection(
      id: 'c1',
      name: 'Home 服务器',
      baseUrl: 'https://hermes.example.com:8787',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');
  final container = ProviderContainer(
    overrides: [
      connectionStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'https://hermes.example.com:8787'),
      ),
      settingsApiFactoryProvider.overrideWithValue((_) => FakeSettingsApi()),
      autoCheckUpdateEnabledProvider.overrideWith(_NoUpdateController.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required Size size,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder get _rail => find.byKey(const ValueKey('settings-nav-rail'));

/// 限宽 744 的内容盒（窄屏**不应**存在）。
Finder get _contentBox => find.byWidgetPredicate(
  (w) => w is ConstrainedBox && w.constraints.maxWidth == 744,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('设置页宽屏分类导航（批 3 · P1）', () {
    testWidgets('宽屏 1280：左导航 220 + 右内容受限宽且左右留白相等', (tester) async {
      await _pump(tester, await _container(), size: const Size(1280, 800));

      expect(_rail, findsOneWidget);
      final railRect = tester.getRect(_rail);
      expect(railRect.width, 220, reason: '左栏固定 220');
      expect(railRect.left, 0, reason: '左栏贴页面左缘');
      expect(railRect.height, greaterThan(0));

      // 三组 / 八项（导航行数 == 顶层 section 数）
      final rows = find.descendant(
        of: _rail,
        matching: find.byType(WideNavRailRow),
      );
      expect(rows, findsNWidgets(8));
      for (final label in ['常用', '服务', '其他']) {
        expect(
          find.descendant(of: _rail, matching: find.text(label)),
          findsOneWidget,
          reason: '$label 分组标题应在左栏',
        );
      }
      for (final name in _categoryProbes.keys) {
        expect(
          find.byKey(ValueKey('settings-nav-$name')),
          findsOneWidget,
          reason: '左栏应有 $name 分类项',
        );
      }

      // 右内容限宽 744 且水平居中于右栏
      // （本用例裸挂页面，无 shell 侧栏：右栏 = 1280 − 220 = 1060 > 744 ⇒ 咬合）
      expect(_contentBox, findsOneWidget);
      final box = tester.getRect(_contentBox);
      expect(box.width, 744, reason: '咬合到 744');
      expect(box.left - 220, 158, reason: '左留白 (1060−744)/2 = 158');
      expect(1280 - box.right, 158, reason: '右留白相等');
      expect(
        box.left - 220,
        closeTo(1280 - box.right, 0.01),
        reason: '左右留白必须相等',
      );
      expect(
        find.byKey(const ValueKey('settings-session-grouping')),
        findsOneWidget,
      );
    });

    testWidgets('宽屏 1600：744 咬合（内容盒正好 744 且左右留白相等）', (tester) async {
      await _pump(tester, await _container(), size: const Size(1600, 900));

      final box = tester.getRect(_contentBox);
      expect(box.width, 744, reason: '右栏 1380 > 744 ⇒ 咬合到 744');
      expect(box.left - 220, 318, reason: '左留白 (1380−744)/2 = 318');
      expect(1600 - box.right, 318, reason: '右留白相等');
      expect(box.left - 220, closeTo(1600 - box.right, 0.01));
    });

    testWidgets('宽屏：只渲染当前分类，点左栏切分类（默认第一项 外观）', (tester) async {
      await _pump(tester, await _container(), size: const Size(1280, 800));

      // 默认「外观」：只应看到外观分组的内容
      expect(
        find.byKey(const ValueKey('settings-session-grouping')),
        findsOneWidget,
      );
      for (final entry in _categoryProbes.entries) {
        if (entry.key == 'appearance') continue;
        expect(
          find.byKey(ValueKey(entry.value)),
          findsNothing,
          reason: '未选中分类 ${entry.key} 的内容不应渲染',
        );
      }

      // 切到「高级设置」（其他组）
      await tester.tap(find.byKey(const ValueKey('settings-nav-advanced')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('settings-entry-auxiliary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-session-grouping')),
        findsNothing,
      );

      // 切到「服务器」（服务组）
      await tester.tap(find.byKey(const ValueKey('settings-nav-server')));
      await tester.pump();
      expect(find.byKey(const ValueKey('server-add')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-entry-auxiliary')),
        findsNothing,
      );

      // 选中态：L2 前景 #005FB8 落在选中行文字上
      final selectedText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-nav-server')),
          matching: find.text('服务器'),
        ),
      );
      expect(
        selectedText.style?.color,
        const Color(0xFF005FB8),
        reason: '选中行用 selectionForeground（L2 蓝字）',
      );
    });

    testWidgets('断点：899 为窄屏（无左导航）／900 为宽屏（有左导航）', (tester) async {
      await _pump(tester, await _container(), size: const Size(899, 900));
      expect(_rail, findsNothing);
      expect(_contentBox, findsNothing);

      await _pump(tester, await _container(), size: const Size(900, 900));
      expect(_rail, findsOneWidget);
      expect(_contentBox, findsOneWidget);
    });

    testWidgets('窄屏 800×2000：8 个 section 顺序长卷、无左导航、无 744 限宽', (tester) async {
      await _pump(tester, await _container(), size: const Size(800, 4000));

      expect(_rail, findsNothing, reason: '窄屏无分类导航');
      expect(_contentBox, findsNothing, reason: '窄屏无 744 限宽盒');
      expect(find.byKey(const ValueKey('settings-scroll')), findsOneWidget);

      // 8 个 section 全部存在，且顺序与长卷一致（自上而下）
      final ys = <double>[];
      for (final entry in _categoryProbes.entries) {
        final finder = find.byKey(ValueKey(entry.value));
        expect(finder, findsOneWidget, reason: '窄屏长卷应含 ${entry.key} 分组');
        ys.add(tester.getRect(finder).top);
      }
      for (var i = 1; i < ys.length; i++) {
        expect(
          ys[i],
          greaterThan(ys[i - 1]),
          reason: '窄屏长卷顺序：$_categoryProbes 第 $i 项应在上一项之下',
        );
      }

      // 首屏仍是「外观」在最上（保持长卷首分组不变）
      expect(
        tester
            .getRect(find.byKey(const ValueKey('settings-session-grouping')))
            .top,
        lessThan(400),
      );
    });

    testWidgets('窄屏卡片仍按 16 内边距贴满视口（未被任何限宽/居中改动）', (tester) async {
      await _pump(tester, await _container(), size: const Size(800, 2000));

      final tile = tester.getRect(
        find.byKey(const ValueKey('settings-session-grouping')),
      );
      expect(tile.left, 16, reason: '窄屏卡片左缘 = 视口 + 16（既有口径）');
      expect(800 - tile.right, 16, reason: '窄屏卡片右缘 = 视口 − 16（左右相等）');
    });
  });
}
