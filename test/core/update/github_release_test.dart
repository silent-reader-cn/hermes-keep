import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/update/github_release.dart';

void main() {
  group('GithubRelease & ReleaseAsset', () {
    test('fromJson parses complete release correctly', () {
      final json = {
        'tag_name': 'v0.1.31',
        'html_url': 'https://github.com/silent-reader-cn/hermes-keep/releases/tag/v0.1.31',
        'name': '0.1.31 Release',
        'body': 'Bug fixes and performance improvements.',
        'published_at': '2026-09-08T20:00:00Z',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://github.com/releases/download/v0.1.31/app-release.apk',
            'size': 25000000,
          },
          {
            'name': 'hermes-ui-setup.exe',
            'browser_download_url': 'https://github.com/releases/download/v0.1.31/hermes-ui-setup.exe',
            'size': 45000000,
          },
        ],
      };

      final release = GithubRelease.fromJson(json);
      expect(release.tagName, 'v0.1.31');
      expect(release.htmlUrl, 'https://github.com/silent-reader-cn/hermes-keep/releases/tag/v0.1.31');
      expect(release.name, '0.1.31 Release');
      expect(release.body, 'Bug fixes and performance improvements.');
      expect(release.publishedAt, DateTime.parse('2026-09-08T20:00:00Z'));
      expect(release.assets.length, 2);

      expect(release.assets[0].name, 'app-release.apk');
      expect(release.assets[0].browserDownloadUrl, 'https://github.com/releases/download/v0.1.31/app-release.apk');
      expect(release.assets[0].size, 25000000);

      expect(release.assets[1].name, 'hermes-ui-setup.exe');
      expect(release.assets[1].size, 45000000);
    });

    test('fromJson tolerates missing or null fields', () {
      final release = GithubRelease.fromJson(null);
      expect(release.tagName, '');
      expect(release.htmlUrl, '');
      expect(release.name, '');
      expect(release.body, '');
      expect(release.publishedAt, isNull);
      expect(release.assets, isEmpty);

      final malformed = GithubRelease.fromJson({
        'tag_name': 123,
        'published_at': 'not-a-date',
        'assets': 'not-a-list',
      });
      expect(malformed.tagName, '');
      expect(malformed.publishedAt, isNull);
      expect(malformed.assets, isEmpty);
    });

    test('ReleaseAsset.fromJson tolerates size as string or num', () {
      final asset1 = ReleaseAsset.fromJson({
        'name': 'test.apk',
        'browser_download_url': 'http://example.com/test.apk',
        'size': '1024',
      });
      expect(asset1.size, 1024);

      final asset2 = ReleaseAsset.fromJson({
        'name': 'test.apk',
        'browser_download_url': 'http://example.com/test.apk',
        'size': 2048.5,
      });
      expect(asset2.size, 2048);

      final assetNull = ReleaseAsset.fromJson(null);
      expect(assetNull.name, '');
      expect(assetNull.browserDownloadUrl, '');
      expect(assetNull.size, 0);
    });

    group('findPlatformAsset', () {
      const release = GithubRelease(
        tagName: 'v0.1.31',
        htmlUrl: 'https://github.com/...',
        name: 'Release',
        assets: [
          ReleaseAsset(
            name: 'hermes-arm64.apk',
            browserDownloadUrl: 'https://apk-arm64',
            size: 100,
          ),
          ReleaseAsset(
            name: 'app-release.apk',
            browserDownloadUrl: 'https://apk-release',
            size: 200,
          ),
          ReleaseAsset(
            name: 'hermes-ui-setup.exe',
            browserDownloadUrl: 'https://exe-setup',
            size: 300,
          ),
        ],
      );

      test('finds Android asset and prefers app-release.apk', () {
        final asset = findPlatformAsset(release, platform: TargetPlatform.android);
        expect(asset, isNotNull);
        expect(asset!.name, 'app-release.apk');
        expect(asset.browserDownloadUrl, 'https://apk-release');
      });

      test('finds Windows asset (*-setup.exe)', () {
        final asset = findPlatformAsset(release, platform: TargetPlatform.windows);
        expect(asset, isNotNull);
        expect(asset!.name, 'hermes-ui-setup.exe');
        expect(asset.browserDownloadUrl, 'https://exe-setup');
      });

      test('returns null for platforms without asset or when not matched', () {
        expect(findPlatformAsset(release, platform: TargetPlatform.iOS), isNull);
        expect(findPlatformAsset(release, platform: TargetPlatform.macOS), isNull);

        const noAssetsRelease = GithubRelease(
          tagName: 'v0.1.31',
          htmlUrl: 'https://...',
          name: 'Empty',
        );
        expect(findPlatformAsset(noAssetsRelease, platform: TargetPlatform.android), isNull);
        expect(findPlatformAsset(noAssetsRelease, platform: TargetPlatform.windows), isNull);
      });
    });
  });
}
