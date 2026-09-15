import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/update/update_checker_service.dart';
import 'package:hermes_ui/core/update/version_info.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(Options());
  });

  setUp(() {
    mockDio = MockDio();
    SharedPreferences.setMockInitialValues({});
  });

  UpdateCheckerService createService({
    String currentVersion = '0.1.30',
  }) {
    return UpdateCheckerService(
      dio: mockDio,
      currentVersion: currentVersion,
      prefsResolver: SharedPreferences.getInstance,
    );
  }

  group('UpdateCheckerService', () {
    test('1. 有更新：远端版本高于本地时，返回 hasUpdate=true 并更新上次检查时间', () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          statusCode: 200,
          data: {
            'tag_name': 'v0.1.31',
            'html_url': 'https://github.com/releases/v0.1.31',
            'name': 'v0.1.31',
            'body': 'New update',
          },
        ),
      );

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: true);

      expect(result.hasUpdate, isTrue);
      expect(result.status, UpdateCheckStatus.hasUpdate);
      expect(result.latestVersion, 'v0.1.31');
      expect(result.release?.tagName, 'v0.1.31');

      final lastCheck = await service.getLastCheckTime();
      expect(lastCheck, isNotNull);
    });

    test('2. 无更新：远端版本等于或低于本地时，返回 upToDate', () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          statusCode: 200,
          data: {
            'tag_name': 'v0.1.30',
            'html_url': 'https://github.com/releases/v0.1.30',
            'name': 'v0.1.30',
            'body': 'Current',
          },
        ),
      );

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: true);

      expect(result.hasUpdate, isFalse);
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.latestVersion, 'v0.1.30');
    });

    test('3. 403 静默：限流 403 发生时完全静默不抛异常，记录时间并返回 failedSilent', () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenThrow(
        DioException(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          response: Response(
            statusCode: 403,
            requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: false);

      expect(result.hasUpdate, isFalse);
      expect(result.status, UpdateCheckStatus.failedSilent);
      expect(result.error, isNotNull);

      // 频控时间已记录，避免重试打爆 API
      final lastCheck = await service.getLastCheckTime();
      expect(lastCheck, isNotNull);
    });

    test('4. 断网静默：网络故障时完全静默不抛异常，返回 failedSilent', () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenThrow(
        DioException(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          type: DioExceptionType.connectionError,
          error: 'SocketException: Network is unreachable',
        ),
      );

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: false);

      expect(result.hasUpdate, isFalse);
      expect(result.status, UpdateCheckStatus.failedSilent);
      expect(result.error, isNotNull);
    });

    test('5. 24h 频控跳过：24h 内已检测过则跳过请求', () async {
      final prefs = await SharedPreferences.getInstance();
      final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
      await prefs.setString(kLastUpdateCheckAtKey, twoHoursAgo.toIso8601String());

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: false);

      expect(result.status, UpdateCheckStatus.skippedThrottled);
      verifyNever(() => mockDio.get<dynamic>(any(), options: any(named: 'options')));
    });

    test('6. 频控到点触发：上次检查超过 24h 时正常触发网络检查', () async {
      final prefs = await SharedPreferences.getInstance();
      final dayAndHalfAgo = DateTime.now().subtract(const Duration(hours: 25));
      await prefs.setString(kLastUpdateCheckAtKey, dayAndHalfAgo.toIso8601String());

      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          statusCode: 200,
          data: {
            'tag_name': 'v0.1.31',
            'html_url': 'https://github.com/releases/v0.1.31',
            'name': 'v0.1.31',
            'body': 'New update',
          },
        ),
      );

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: false);

      expect(result.status, UpdateCheckStatus.hasUpdate);
      verify(() => mockDio.get<dynamic>(any(), options: any(named: 'options'))).called(1);
    });

    test('7. 自动检查开关关闭时静默跳过', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kAutoCheckUpdateEnabledKey, false);

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: false);

      expect(result.status, UpdateCheckStatus.skippedDisabled);
      verifyNever(() => mockDio.get<dynamic>(any(), options: any(named: 'options')));
    });

    test('8. 手动检查不受 24h 频控与开关约束', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kAutoCheckUpdateEnabledKey, false);
      final tenMinutesAgo = DateTime.now().subtract(const Duration(minutes: 10));
      await prefs.setString(kLastUpdateCheckAtKey, tenMinutesAgo.toIso8601String());

      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          statusCode: 200,
          data: {
            'tag_name': 'v0.1.30',
            'html_url': 'https://github.com/releases/v0.1.30',
            'name': 'v0.1.30',
          },
        ),
      );

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.upToDate);
      verify(() => mockDio.get<dynamic>(any(), options: any(named: 'options'))).called(1);
    });

    test('9. 手动检查失败时返回 failed（非静默态）', () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenThrow(
        DioException(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          response: Response(
            statusCode: 500,
            requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final service = createService(currentVersion: '0.1.30');
      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.failed);
      expect(result.error, isNotNull);
    });

    test('10. #122 未注入版本时用解析器取真实版本作比对基准（远端同版 → 无更新）',
        () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          statusCode: 200,
          data: {
            'tag_name': 'v0.1.50',
            'html_url': 'https://github.com/releases/v0.1.50',
            'name': 'v0.1.50',
            'body': 'Current',
          },
        ),
      );

      final service = UpdateCheckerService(
        dio: mockDio,
        currentVersionResolver: () async => '0.1.50+56',
        prefsResolver: SharedPreferences.getInstance,
      );

      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.currentVersion, '0.1.50+56');
      expect(result.hasUpdate, isFalse);
    });

    test('11. #122 装了更新一版后不得再报同一版（0.1.50 装 0.1.50 → 无更新）', () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          statusCode: 200,
          data: {
            'tag_name': 'v0.1.50',
            'html_url': 'https://github.com/releases/v0.1.50',
            'name': 'v0.1.50',
            'body': 'Current',
          },
        ),
      );

      // 旧实现在此路径会用硬编码常量（停在 0.1.31）当基准 → 永远误报有更新。
      final service = UpdateCheckerService(
        dio: mockDio,
        currentVersionResolver: () async => '0.1.50',
        prefsResolver: SharedPreferences.getInstance,
      );

      final result = await service.checkForUpdates(isManual: true);

      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.hasUpdate, isFalse);
    });

    test('12. #122 版本解析失败 → 安全回退兜底常量，不崩且不误报有更新', () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          statusCode: 200,
          data: {
            'tag_name': 'v0.1.47',
            'html_url': 'https://github.com/releases/v0.1.47',
            'name': 'v0.1.47',
            'body': 'Older than fallback',
          },
        ),
      );

      final service = UpdateCheckerService(
        dio: mockDio,
        currentVersionResolver: () async => throw StateError('no platform'),
        prefsResolver: SharedPreferences.getInstance,
      );

      final result = await service.checkForUpdates(isManual: true);

      // 兜底常量 appVersion > v0.1.47 → 不应误报「发现新版本 v0.1.47」
      expect(result.currentVersion, appVersion);
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.hasUpdate, isFalse);
    });

    test('13. #122 未注入且未指定解析器 → 默认解析器在无平台通道下安全降级', () async {
      when(() => mockDio.get<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: kGithubReleasesLatestUrl),
          statusCode: 200,
          data: {
            'tag_name': 'v0.1.47',
            'html_url': 'https://github.com/releases/v0.1.47',
            'name': 'v0.1.47',
            'body': 'x',
          },
        ),
      );

      final service = UpdateCheckerService(
        dio: mockDio,
        prefsResolver: SharedPreferences.getInstance,
      );

      final result = await service.checkForUpdates(isManual: true);

      // 单测环境无原生通道 → package_info 解析失败 → 回退兜底常量，不抛异常
      expect(result.currentVersion, isNotEmpty);
      expect(result.status, isA<UpdateCheckStatus>());
    });
  });
}
