import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/app.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';
import 'package:hermes_ui/features/settings/accessibility_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/in_memory_secure_storage.dart';

/// 固定开关值，绕开 shared_preferences 的异步回读。
class _FakeAccessibilityController extends AccessibilitySettingsController {
  _FakeAccessibilityController(this.initial);
  final bool initial;

  @override
  AccessibilitySettings build() =>
      AccessibilitySettings(forceHighContrast: initial);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    enableSessionAutoRefresh = false;
  });

  tearDown(() {
    enableSessionAutoRefresh = true;
  });

  Widget buildApp({required bool force}) {
    return ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: InMemorySecureStorage()),
        ),
        accessibilitySettingsProvider.overrideWith(
          () => _FakeAccessibilityController(force),
        ),
      ],
      child: const HermesApp(),
    );
  }

  /// 路由内容的 MediaQuery —— builder 包在 Navigator 之外，故读最内层 Navigator。
  MediaQueryData mediaQueryOfContent(WidgetTester tester) =>
      MediaQuery.of(tester.element(find.byType(Navigator).first));

  testWidgets('app.dart 接线：开关关闭 → 不新建 MediaQuery，highContrast 保持系统值', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(force: false));
    await tester.pump();
    expect(mediaQueryOfContent(tester).highContrast, isFalse);
  });

  testWidgets('app.dart 接线：开关开启 → highContrast 强制为 true', (tester) async {
    await tester.pumpWidget(buildApp(force: true));
    await tester.pump();
    expect(mediaQueryOfContent(tester).highContrast, isTrue);
  });

  testWidgets('开关关闭时不覆盖系统辅助功能设置：系统已开高对比度则仍然生效', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(buildApp(force: false));
    await tester.pump();
    expect(
      mediaQueryOfContent(tester).highContrast,
      isTrue,
      reason: '关闭只表示「不强制」，不得把系统已开启的高对比度压掉',
    );
  });

  // 拆成两个用例：同一测试体内连续 pumpWidget 换 override 时，Riverpod 不会
  // 重建被 override 的 notifier，且 CupertinoDynamicColor 是全局 const，
  // 分开跑才是确定性的。
  testWidgets('开关关闭 → systemGrey 解析为普通档 #8E8E93', (tester) async {
    await tester.pumpWidget(buildApp(force: false));
    await tester.pump();
    expect(
      CupertinoDynamicColor.resolve(
        CupertinoColors.systemGrey,
        tester.element(find.byType(Navigator).first),
      ).toARGB32(),
      const Color(0xFF8E8E93).toARGB32(),
    );
  });

  testWidgets('开关开启 → systemGrey 解析为高对比档 #6C6C70', (tester) async {
    await tester.pumpWidget(buildApp(force: true));
    await tester.pump();
    expect(
      CupertinoDynamicColor.resolve(
        CupertinoColors.systemGrey,
        tester.element(find.byType(Navigator).first),
      ).toARGB32(),
      const Color(0xFF6C6C70).toARGB32(),
    );
  });
}
