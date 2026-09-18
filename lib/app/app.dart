import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// PDF 预览（pdfrx）长按选字的工具条（AdaptiveTextSelectionToolbar）取自
// package:material_ui —— 该包自带一份独立的 MaterialLocalizations 类型，
// 与 flutter/material（flutter_localizations 注册的）并不同源；不单独注册
// 它的 delegate 时 Localizations.of 空断言崩溃（zh/en 均炸）。
import 'package:material_ui/material_ui.dart' as material_ui;

import '../features/desktop/desktop_lifecycle_observer.dart';
import '../features/notifications/notification_lifecycle_observer.dart';
import '../features/session_list/session_auto_refresh.dart';
import '../features/settings/accessibility_settings.dart';
import '../l10n/app_localizations.dart';
import 'locale/locale_provider.dart';
import 'router.dart';
import 'theme/cupertino_theme.dart';
import 'theme/theme_provider.dart';
import 'widgets/focus_gated_ticker_mode.dart';

/// 根 Widget（app_shell_spec.md §2.2）。
///
/// 纯 Cupertino 壳：深浅色主题（跟随系统 + 手动三态）、go_router 路由表、
/// 中英本地化。桌面端窗口标题 'Hermes'，移动端状态栏样式随系统。
///
/// 注：CupertinoApp 不支持 `darkTheme`/`themeMode` 参数（MaterialApp 专属），
/// 深浅色在这里按三态模式 + 系统亮度手工解析出单一 [CupertinoThemeData]。
class HermesApp extends ConsumerWidget {
  const HermesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final localeMode = ref.watch(localeModeProvider);
    final router = ref.watch(routerProvider);
    // 无障碍高对比度开关（默认关）。
    final forceHighContrast = ref
        .watch(accessibilitySettingsProvider)
        .forceHighContrast;
    final brightness = switch (themeMode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final locale = switch (localeMode) {
      AppLocaleMode.system => null,
      AppLocaleMode.zh => const Locale('zh'),
      AppLocaleMode.en => const Locale('en'),
    };
    return DesktopLifecycleObserver(
      child: WindowFocusObserver(
        child: NotificationLifecycleObserver(
          child: CupertinoApp.router(
          title: 'Hermes',
          theme: buildCupertinoTheme(brightness),
          routerConfig: router,
          locale: locale,
          // 关闭时不新建 MediaQuery —— 既不改变既有像素，也不覆盖系统辅助功能设置；
          // 开启时把 highContrast 强制为 true，令全部 Cupertino 动态色切到更强变体。
          builder: (context, child) {
            final content = child ?? const SizedBox.shrink();
            final themed = forceHighContrast
                ? MediaQuery(
                    data: MediaQuery.of(context).copyWith(highContrast: true),
                    child: content,
                  )
                : content;
            // 窗口失焦时静音整棵子树的动画 ticker；见 FocusGatedTickerMode。
            return FocusGatedTickerMode(child: themed);
          },
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            // package:material_ui 独立 MaterialLocalizations 类型的一份
            // （WidgetsLocalizations 键与 flutter/widgets 同源，无需重复）。
            material_ui.GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          ),
        ),
      ),
    );
  }
}
