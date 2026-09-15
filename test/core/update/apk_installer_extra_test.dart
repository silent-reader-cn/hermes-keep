import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/update/apk_installer.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

/// 覆盖率补强：`apk_installer.dart`（此前 0%）。
///
/// 三条通道（canRequestInstall / openInstallPermissionSettings /
/// getShareUri）全部用 mock method channel 覆盖成功与异常路径；
/// `installApkWithPermissionGate` 用注入的 `launchIntent` 捕获真实
/// `AndroidIntent` 载荷（action/type/flags/data），不触碰真机安装器。
const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

class _InstallTrigger extends StatelessWidget {
  const _InstallTrigger({required this.onPressed});

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: () => onPressed(context),
      child: const Text('install'),
    );
  }
}

Future<void> _pumpApp(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    CupertinoApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: _delegates,
      home: CupertinoPageScaffold(child: Center(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 独立测试通道，避免污染真实通道 `updateFileShareChannel`
  const channel = MethodChannel('test/hermes_ui/apk_installer');
  final calls = <MethodCall>[];

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('原生通道契约', () {
    test('默认通道名与 MainActivity 约定一致', () {
      expect(updateFileShareChannel.name, 'com.silentreader.hermes_ui/file_share');
    });
  });

  group('canRequestInstall', () {
    test('原生返回 true → true', () async {
      mockChannel((call) async {
        expect(call.method, 'canRequestInstall');
        return true;
      });
      expect(await canRequestInstall(channel: channel), isTrue);
    });

    test('原生返回 false → false', () async {
      mockChannel((_) async => false);
      expect(await canRequestInstall(channel: channel), isFalse);
    });

    test('原生返回 null → false（?? 兜底）', () async {
      mockChannel((_) async => null);
      expect(await canRequestInstall(channel: channel), isFalse);
    });

    test('通道异常 → 吞掉并返回 false', () async {
      mockChannel((_) async => throw PlatformException(code: 'no_impl'));
      expect(await canRequestInstall(channel: channel), isFalse);
    });
  });

  group('openInstallPermissionSettings', () {
    test('跳转系统设置页：走 openInstallPermissionSettings 且无参数', () async {
      mockChannel((call) async {
        calls.add(call);
        return null;
      });
      await openInstallPermissionSettings(channel: channel);
      expect(calls.map((c) => c.method).toList(), ['openInstallPermissionSettings']);
      expect(calls.single.arguments, isNull);
    });

    test('通道异常被吞掉（不向调用方抛）', () async {
      mockChannel((_) async => throw PlatformException(code: 'no_impl'));
      await expectLater(
        openInstallPermissionSettings(channel: channel),
        completes,
      );
    });
  });

  group('androidContentUriFor', () {
    test('成功后返回 content:// URI，并把 path 作为参数传给原生', () async {
      mockChannel((call) async {
        calls.add(call);
        expect(call.method, 'getShareUri');
        return 'content://com.silentreader.hermes_ui.fileprovider/install/a.apk';
      });
      expect(
        await androidContentUriFor('/data/app/a.apk', channel: channel),
        'content://com.silentreader.hermes_ui.fileprovider/install/a.apk',
      );
      expect(calls.single.arguments, {'path': '/data/app/a.apk'});
    });

    test('通道异常 → 返回 null 让调用方回退 file:// 路径', () async {
      mockChannel((_) async => throw PlatformException(code: 'no_impl'));
      expect(await androidContentUriFor('/data/app/a.apk', channel: channel),
          isNull);
    });
  });

  group('installApkWithPermissionGate', () {
    testWidgets('已授权：直接发起 VIEW/package-archive intent（content:// + 双 flag）', (
      tester,
    ) async {
      const path = '/data/app/hermes.apk';
      const uri =
          'content://com.silentreader.hermes_ui.fileprovider/install/hermes.apk';
      mockChannel((call) async {
        calls.add(call);
        switch (call.method) {
          case 'canRequestInstall':
            return true;
          case 'getShareUri':
            return uri;
        }
        return null;
      });

      AndroidIntent? launched;
      bool? result;
      await _pumpApp(
        tester,
        _InstallTrigger(
          onPressed: (context) async {
            result = await installApkWithPermissionGate(
              context,
              path,
              channel: channel,
              launchIntent: (intent) async => launched = intent,
            );
          },
        ),
      );

      await tester.tap(find.text('install'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(launched, isNotNull);
      expect(launched!.action, 'android.intent.action.VIEW');
      expect(launched!.type, 'application/vnd.android.package-archive');
      expect(launched!.data, uri);
      expect(launched!.flags, [0x10000000, 0x00000001]);
      // 授权已通过：不弹权限引导
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(calls.map((c) => c.method).toList(), ['canRequestInstall', 'getShareUri']);
    });

    testWidgets('getShareUri 返回 null → 回退 file:// 路径（空格转义）', (tester) async {
      const path = '/tmp/a b.apk';
      mockChannel((call) async {
        switch (call.method) {
          case 'canRequestInstall':
            return true;
          case 'getShareUri':
            return null;
        }
        return null;
      });

      AndroidIntent? launched;
      bool? result;
      await _pumpApp(
        tester,
        _InstallTrigger(
          onPressed: (context) async {
            result = await installApkWithPermissionGate(
              context,
              path,
              channel: channel,
              launchIntent: (intent) async => launched = intent,
            );
          },
        ),
      );

      await tester.tap(find.text('install'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(launched!.data, 'file:///tmp/a%20b.apk');
    });

    testWidgets('launchIntent 为空 → 走 AndroidIntent.launch() 内置路径仍返回 true', (
      tester,
    ) async {
      mockChannel((call) async {
        switch (call.method) {
          case 'canRequestInstall':
            return true;
          case 'getShareUri':
            return 'content://com.silentreader.hermes_ui.fileprovider/install/x.apk';
        }
        return null;
      });

      bool? result;
      await _pumpApp(
        tester,
        _InstallTrigger(
          onPressed: (context) async {
            result = await installApkWithPermissionGate(
              context,
              '/data/app/x.apk',
              channel: channel,
            );
          },
        ),
      );

      await tester.tap(find.text('install'));
      await tester.pumpAndSettle();

      // 宿主为 Windows：android_intent_plus 的 LocalPlatform 非安卓，launch() 直接返回
      expect(result, isTrue);
    });

    testWidgets('未授权 + 点「取消」→ 复查仍拒 → 返回 false 且不发起安装', (tester) async {
      mockChannel((call) async {
        calls.add(call);
        if (call.method == 'canRequestInstall') return false;
        return null;
      });

      AndroidIntent? launched;
      bool? result;
      await _pumpApp(
        tester,
        _InstallTrigger(
          onPressed: (context) async {
            result = await installApkWithPermissionGate(
              context,
              '/data/app/hermes.apk',
              channel: channel,
              launchIntent: (intent) async => launched = intent,
            );
          },
        ),
      );

      await tester.tap(find.text('install'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 引导弹窗文案与两个动作按钮（实现取自 l10n）
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('需要安装权限'), findsOneWidget);
      expect(
        find.text('安装 APK 需要在系统设置中允许 Hermes「安装未知应用」，授权后回来重新点「打开」即可。'),
        findsOneWidget,
      );
      expect(find.text('去设置'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(launched, isNull);
      // 两次复查，且未触碰 getShareUri / 设置页跳转
      expect(calls.map((c) => c.method).toList(), ['canRequestInstall', 'canRequestInstall']);
    });

    testWidgets('未授权 + 点「去设置」→ 跳设置页；复查通过 → 继续安装并返回 true', (
      tester,
    ) async {
      var permissionChecks = 0;
      mockChannel((call) async {
        calls.add(call);
        switch (call.method) {
          case 'canRequestInstall':
            permissionChecks++;
            // 第一次拒绝，从设置页回来后放行
            return permissionChecks > 1;
          case 'getShareUri':
            return 'content://com.silentreader.hermes_ui.fileprovider/install/y.apk';
        }
        return null;
      });

      AndroidIntent? launched;
      bool? result;
      await _pumpApp(
        tester,
        _InstallTrigger(
          onPressed: (context) async {
            result = await installApkWithPermissionGate(
              context,
              '/data/app/y.apk',
              channel: channel,
              launchIntent: (intent) async => launched = intent,
            );
          },
        ),
      );

      await tester.tap(find.text('install'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);

      await tester.tap(find.text('去设置'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(launched?.data,
          'content://com.silentreader.hermes_ui.fileprovider/install/y.apk');
      expect(calls.map((c) => c.method).toList(), [
        'canRequestInstall',
        'openInstallPermissionSettings',
        'canRequestInstall',
        'getShareUri',
      ]);
    });

    testWidgets('权限受理期间 context 已卸载（页面被销毁）→ 不弹窗直接返回 false', (
      tester,
    ) async {
      final gate = Completer<bool?>();
      mockChannel((call) async {
        if (call.method == 'canRequestInstall') return gate.future;
        return null;
      });

      bool? result;
      await _pumpApp(
        tester,
        _InstallTrigger(
          onPressed: (ctx) async {
            result = await installApkWithPermissionGate(
              ctx,
              '/data/app/gone.apk',
              channel: channel,
              launchIntent: (_) async {},
            );
          },
        ),
      );

      await tester.tap(find.text('install'));
      await tester.pump();

      // 整棵树换掉：承载 context 的组件被卸载 → context.mounted == false
      await tester.pumpWidget(
        const CupertinoApp(
          locale: Locale('zh'),
          supportedLocales: [Locale('zh'), Locale('en')],
          localizationsDelegates: _delegates,
          home: CupertinoPageScaffold(child: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      gate.complete(false);
      await tester.pump();
      await tester.pump();

      expect(result, isFalse);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });
  });
}
