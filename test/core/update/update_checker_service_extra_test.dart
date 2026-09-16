import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/version_info.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDio extends Mock implements Dio {}

/// 补测：`platformAppVersion()` 成功路径（真实安装版本拼接）、
/// `setAutoCheckEnabled` 持久化、以及 `checkForUpdates` 对
/// 「响应体不是 Map」的两种形态（cast 兜底 / FormatException）处理。
void main() {
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(Options());
  });

  setUp(() {
    mockDio = MockDio();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  UpdateCheckerService createService({
    String currentVersion = '0.1.30',
    Future<SharedPreferences> Function()? prefsResolver,
  }) =>
      UpdateCheckerService(
        dio: mockDio,
        currentVersion: currentVersion,
        prefsResolver: prefsResolver ?? SharedPreferences.getInstance,
      );

  void stubResponse(Object? data, {int statusCode = 200}) {
    when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
        .thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
        statusCode: statusCode,
        data: data,
      ),
    );
  }

  group('platformAppVersion 真实安装版本解析', () {
    test('version + buildNumber → "<version>+<build>"（与设置页同源格式）', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Hermes UI',
        packageName: 'cn.hermes.ui',
        version: '0.1.50',
        buildNumber: '56',
        buildSignature: '',
      );

      expect(await platformAppVersion(), '0.1.50+56');
    });

    test('buildNumber 为空 → 只返回 version（不留下孤立 "+"）', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Hermes UI',
        packageName: 'cn.hermes.ui',
        version: '0.1.50',
        buildNumber: '',
        buildSignature: '',
      );

      expect(await platformAppVersion(), '0.1.50');
    });

    test('两端带空白 → trim 后再拼接', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Hermes UI',
        packageName: 'cn.hermes.ui',
        version: ' 0.1.50 ',
        buildNumber: ' 56 ',
        buildSignature: '',
      );

      expect(await platformAppVersion(), '0.1.50+56');
    });

    test('version 只有空白 → 兜底常量 appVersion（不返回空白版本）', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Hermes UI',
        packageName: 'cn.hermes.ui',
        version: '   ',
        buildNumber: '56',
        buildSignature: '',
      );

      expect(await platformAppVersion(), appVersion);
    });

    test('解析出的版本可直接作为比对基准（远端同版 → 无更新）', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Hermes UI',
        packageName: 'cn.hermes.ui',
        version: '0.1.50',
        buildNumber: '56',
        buildSignature: '',
      );
      stubResponse(<String, dynamic>{
        'tag_name': 'v0.1.50',
        'html_url': 'https://github.com/releases/v0.1.50',
        'name': 'v0.1.50',
      });

      // 不注入 currentVersion → 走默认解析器（platformAppVersion）。
      final service = UpdateCheckerService(
        dio: mockDio,
        prefsResolver: SharedPreferences.getInstance,
      );
      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.currentVersion, '0.1.50+56');
      expect(result.hasUpdate, isFalse);

      // 真实版本解析结果在实例内缓存，getter 立即反映。
      expect(service.currentVersion, '0.1.50+56');
    });
  });

  group('setAutoCheckEnabled 持久化', () {
    test('写入后 isAutoCheckEnabled / 底层 prefs 键位一致', () async {
      final service = createService();

      expect(await service.isAutoCheckEnabled(), isTrue, reason: '默认开启');

      await service.setAutoCheckEnabled(false);
      expect(await service.isAutoCheckEnabled(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAutoCheckUpdateEnabledKey), isFalse);

      await service.setAutoCheckEnabled(true);
      expect(await service.isAutoCheckEnabled(), isTrue);
      expect(prefs.getBool(kAutoCheckUpdateEnabledKey), isTrue);
    });

    test('关闭开关后自动检查跳过；重新打开后恢复联网检查', () async {
      stubResponse(<String, dynamic>{
        'tag_name': 'v0.1.99',
        'html_url': 'https://github.com/releases/v0.1.99',
        'name': 'v0.1.99',
      });
      final service = createService();

      await service.setAutoCheckEnabled(false);
      expect(
        (await service.checkForUpdates(isManual: false)).status,
        UpdateCheckStatus.skippedDisabled,
      );
      verifyNever(
        () => mockDio.get<dynamic>(any(), options: any(named: 'options')),
      );

      await service.setAutoCheckEnabled(true);
      expect(
        (await service.checkForUpdates(isManual: false)).status,
        UpdateCheckStatus.hasUpdate,
      );
      verify(
        () => mockDio.get<dynamic>(any(), options: any(named: 'options')),
      ).called(1);
    });

    test('prefs 不可用（resolver 抛错）→ 读写全部静默降级，不抛异常', () async {
      final service = createService(
        prefsResolver: () async => throw StateError('prefs unavailable'),
      );

      expect(await service.isAutoCheckEnabled(), isTrue);
      await service.setAutoCheckEnabled(false);
      expect(await service.getLastCheckTime(), isNull);
    });

    test('未注入 dio → 走自建默认 Dio（超时/头约定），短路分支不触网', () async {
      final service = UpdateCheckerService(
        prefsResolver: SharedPreferences.getInstance,
      );

      // 未注入版本、也未解析过 → getter 兜底常量（真实版本在比对时才解析）。
      expect(service.currentVersion, appVersion);

      await service.setAutoCheckEnabled(false);
      final result = await service.checkForUpdates(isManual: false);

      expect(result.status, UpdateCheckStatus.skippedDisabled);
      expect(result.currentVersion, appVersion);
      expect(result.release, isNull);
      expect(result.error, isNull);
    });
  });

  group('checkForUpdates 响应体形态容错', () {
    test('响应体是非 Map<String, dynamic> 的 Map → 走 cast 兜底并正常解析', () async {
      // dio 默认解码产出 Map<String, dynamic>（第一分支）；此分支为
      // 「手工组装 / 拦截器替换过的 Map」兜底。
      stubResponse(<Object, Object>{
        'tag_name': 'v0.1.99',
        'html_url': 'https://github.com/releases/v0.1.99',
        'name': 'v0.1.99',
        'body': 'from cast branch',
        'assets': <Object>[
          <Object, Object>{
            'name': 'app-release.apk',
            'browser_download_url': 'https://x/app-release.apk',
            'size': 11,
          },
        ],
      });

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.hasUpdate);
      expect(result.latestVersion, 'v0.1.99');
      expect(result.release?.name, 'v0.1.99');
      expect(result.release?.body, 'from cast branch');
      expect(result.release?.assets.single.name, 'app-release.apk');
      expect(result.release?.assets.single.size, 11);
    });

    test('响应体不是 Map（数组/字符串/数字）→ FormatException，静默态 failedSilent', () async {
      final now = DateTime.utc(2026, 9, 16, 8);
      stubResponse(<Object>['unexpected']);

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(now: now);

      expect(result.status, UpdateCheckStatus.failedSilent);
      expect(result.error, isA<FormatException>());
      expect(
        result.error.toString(),
        contains('Unexpected response format'),
      );
      expect(result.currentVersion, '0.1.30');
      expect(result.hasUpdate, isFalse);

      // 失败也要记录检查时间，避免静默失败被无限重试打爆 GitHub。
      expect(await service.getLastCheckTime(), now);
    });

    test('响应体是字符串 / 数字 → 同样 FormatException（手动态 failed）', () async {
      stubResponse('plain text');

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.failed);
      expect(result.error, isA<FormatException>());

      stubResponse(42);
      final second = await service.checkForUpdates(isManual: true);
      expect(second.status, UpdateCheckStatus.failed);
      expect(second.error, isA<FormatException>());
    });

    test('响应体为 null → FormatException（不把 null 当成空 Release）', () async {
      stubResponse(null);

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.failed);
      expect(result.error, isA<FormatException>());
    });

    test('响应体是合法 Map 但 tag 畸形 → 不回退成「有更新」误报', () async {
      stubResponse(<String, dynamic>{
        'tag_name': 'not-a-version',
        'html_url': 'https://github.com/releases/x',
        'name': 'x',
      });

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.hasUpdate, isFalse);
      expect(result.release?.tagName, 'not-a-version');
    });
  });
}
