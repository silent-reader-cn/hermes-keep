import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/settings/accessibility_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AccessibilitySettings 值对象', () {
    test('默认不强制高对比度（零干预 = 既有像素不变）', () {
      expect(const AccessibilitySettings().forceHighContrast, isFalse);
    });

    test('copyWith 只改指定字段', () {
      const base = AccessibilitySettings();
      expect(base.copyWith(forceHighContrast: true).forceHighContrast, isTrue);
      expect(
        base.copyWith(forceHighContrast: true).copyWith().forceHighContrast,
        isTrue,
      );
    });

    test('== / hashCode 按 forceHighContrast 区分', () {
      const a = AccessibilitySettings();
      const b = AccessibilitySettings(forceHighContrast: true);
      expect(a, const AccessibilitySettings());
      expect(a, isNot(b));
      expect(a.hashCode, const AccessibilitySettings().hashCode);
      expect(a.toString(), contains('false'));
    });
  });

  group('AccessibilitySettingsController 持久化', () {
    test('loadForcePref：缺省 false，写入 true 后可读回', () async {
      expect(await AccessibilitySettingsController.loadForcePref(), isFalse);

      await AccessibilitySettingsController.saveForcePref(true);
      expect(await AccessibilitySettingsController.loadForcePref(), isTrue);

      await AccessibilitySettingsController.saveForcePref(false);
      expect(await AccessibilitySettingsController.loadForcePref(), isFalse);
    });

    test('落盘键为 force_high_contrast', () async {
      await AccessibilitySettingsController.saveForcePref(true);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(AccessibilitySettingsController.keyForceHighContrast),
        isTrue,
      );
    });

    test('provider 初始为 false（不干预）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(accessibilitySettingsProvider); // 触发 build() → 启动异步回读
      await _settle();
      expect(
        container.read(accessibilitySettingsProvider).forceHighContrast,
        isFalse,
      );
    });

    test('setForceHighContrast 更新 state 并立即落盘', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(accessibilitySettingsProvider);
      await _settle();

      await container
          .read(accessibilitySettingsProvider.notifier)
          .setForceHighContrast(true);

      expect(
        container.read(accessibilitySettingsProvider).forceHighContrast,
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(AccessibilitySettingsController.keyForceHighContrast),
        isTrue,
      );
    });

    test('冷启动（新容器）回读到已持久化的 true', () async {
      await AccessibilitySettingsController.saveForcePref(true);
      // SharedPreferences 单例已缓存，故用「新建容器」表达冷启动语义。
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(accessibilitySettingsProvider); // 惰性：必须先读才会 build
      await _settle();
      expect(
        container.read(accessibilitySettingsProvider).forceHighContrast,
        isTrue,
      );
    });
  });
}

/// 排空若干轮微任务，等 Notifier 的异步回读落到 state 上。
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
