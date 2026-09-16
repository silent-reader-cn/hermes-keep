import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/update/github_release.dart';

/// 补测：`ReleaseAsset.toJson` / `GithubRelease.toJson`、
/// `assets` 内非 `Map<String, dynamic>` 的 Map 兜底分支、
/// 逐键位容错与近似键名反例、`findPlatformAsset` 无 platform 与两处回退循环。
void main() {
  group('ReleaseAsset.fromJson / toJson', () {
    test('toJson 输出 GitHub 原始键名，且可往返还原', () {
      const asset = ReleaseAsset(
        name: 'app-release.apk',
        browserDownloadUrl: 'https://example.com/app-release.apk',
        size: 1024,
      );

      final json = asset.toJson();

      expect(json.keys.toSet(), {'name', 'browser_download_url', 'size'});
      expect(json['name'], 'app-release.apk');
      expect(
        json['browser_download_url'],
        'https://example.com/app-release.apk',
      );
      expect(json['size'], 1024);

      final roundTrip = ReleaseAsset.fromJson(json);
      expect(roundTrip.name, asset.name);
      expect(roundTrip.browserDownloadUrl, asset.browserDownloadUrl);
      expect(roundTrip.size, asset.size);
    });

    test('toJson 的 size 默认 0 也要落盘（不被省略）', () {
      const asset = ReleaseAsset(name: 'x', browserDownloadUrl: 'y');

      final json = asset.toJson();

      expect(json.containsKey('size'), isTrue);
      expect(json['size'], 0);
      expect(json.length, 3);
    });

    test('fromJson null / 空集合 → 全空值', () {
      final fromNull = ReleaseAsset.fromJson(null);
      expect(fromNull.name, '');
      expect(fromNull.browserDownloadUrl, '');
      expect(fromNull.size, 0);

      final fromEmpty = ReleaseAsset.fromJson(<String, dynamic>{});
      expect(fromEmpty.name, '');
      expect(fromEmpty.browserDownloadUrl, '');
      expect(fromEmpty.size, 0);
    });

    test('fromJson 逐键位类型不符（数字 / 列表 / 对象）→ 一律降级空值', () {
      final asset = ReleaseAsset.fromJson(<String, dynamic>{
        'name': 123,
        'browser_download_url': <String>['https://x'],
        'size': <String, dynamic>{'n': 1},
      });

      expect(asset.name, '');
      expect(asset.browserDownloadUrl, '');
      expect(asset.size, 0);
    });

    test('fromJson size 四形态：int / num 取整 / 数字串 / 垃圾串归零', () {
      expect(ReleaseAsset.fromJson(<String, dynamic>{'size': 7}).size, 7);
      expect(ReleaseAsset.fromJson(<String, dynamic>{'size': 7.9}).size, 7);
      expect(ReleaseAsset.fromJson(<String, dynamic>{'size': 7.4}).size, 7);
      expect(ReleaseAsset.fromJson(<String, dynamic>{'size': '7'}).size, 7);
      expect(ReleaseAsset.fromJson(<String, dynamic>{'size': '12abc'}).size, 0);
      expect(ReleaseAsset.fromJson(<String, dynamic>{'size': <int>[]}).size, 0);
      expect(ReleaseAsset.fromJson(<String, dynamic>{'size': null}).size, 0);
      expect(ReleaseAsset.fromJson(<String, dynamic>{'size': true}).size, 0);
    });

    test('fromJson 近似键名（Name / download_url / Size）不被识别', () {
      final asset = ReleaseAsset.fromJson(<String, dynamic>{
        'Name': 'a.apk',
        'download_url': 'https://x/a.apk',
        'Size': 99,
      });

      expect(asset.name, '');
      expect(asset.browserDownloadUrl, '');
      expect(asset.size, 0);
    });
  });

  group('GithubRelease.fromJson / toJson', () {
    test('toJson 输出完整键位；publishedAt 走 ISO8601', () {
      final release = GithubRelease(
        tagName: 'v0.1.51',
        htmlUrl: 'https://github.com/silent-reader-cn/hermes-ui/releases/tag/v0.1.51',
        name: '0.1.51',
        body: 'notes',
        publishedAt: DateTime.utc(2026, 9, 15, 12, 30),
        assets: const <ReleaseAsset>[
          ReleaseAsset(
            name: 'a.apk',
            browserDownloadUrl: 'https://x/a.apk',
            size: 3,
          ),
        ],
      );

      final json = release.toJson();

      expect(json.keys.toSet(), {
        'tag_name',
        'html_url',
        'name',
        'body',
        'published_at',
        'assets',
      });
      expect(json['tag_name'], 'v0.1.51');
      expect(json['html_url'], release.htmlUrl);
      expect(json['name'], '0.1.51');
      expect(json['body'], 'notes');
      expect(json['published_at'], '2026-09-15T12:30:00.000Z');
      expect((json['assets'] as List<Object?>).single, {
        'name': 'a.apk',
        'browser_download_url': 'https://x/a.apk',
        'size': 3,
      });

      final roundTrip = GithubRelease.fromJson(json);
      expect(roundTrip.tagName, release.tagName);
      expect(roundTrip.htmlUrl, release.htmlUrl);
      expect(roundTrip.publishedAt, release.publishedAt);
      expect(roundTrip.assets.single.name, 'a.apk');
    });

    test('toJson publishedAt 缺失 → null，assets 缺失 → 空数组', () {
      const release = GithubRelease(tagName: 'v1', htmlUrl: 'h', name: 'n');

      final json = release.toJson();

      expect(json['published_at'], isNull);
      expect(json['assets'], isEmpty);
      expect(json.containsKey('published_at'), isTrue);
    });

    test('fromJson null / 空集合 → 全空值且 publishedAt 为 null', () {
      final fromNull = GithubRelease.fromJson(null);
      expect(fromNull.tagName, '');
      expect(fromNull.htmlUrl, '');
      expect(fromNull.name, '');
      expect(fromNull.body, '');
      expect(fromNull.publishedAt, isNull);
      expect(fromNull.assets, isEmpty);

      final fromEmpty = GithubRelease.fromJson(<String, dynamic>{});
      expect(fromEmpty.tagName, '');
      expect(fromEmpty.publishedAt, isNull);
      expect(fromEmpty.assets, isEmpty);
    });

    test('fromJson 逐键位类型不符 → 一律降级空值', () {
      final release = GithubRelease.fromJson(<String, dynamic>{
        'tag_name': 1,
        'html_url': <String>[],
        'name': <String, dynamic>{},
        'body': 3.5,
        'published_at': 20260915,
        'assets': 'not-a-list',
      });

      expect(release.tagName, '');
      expect(release.htmlUrl, '');
      expect(release.name, '');
      expect(release.body, '');
      expect(release.publishedAt, isNull);
      expect(release.assets, isEmpty);
    });

    test('published_at 空串不解析；非法日期串 → null；合法串正常解析', () {
      expect(
        GithubRelease.fromJson(
          <String, dynamic>{'published_at': ''},
        ).publishedAt,
        isNull,
      );
      expect(
        GithubRelease.fromJson(
          <String, dynamic>{'published_at': 'not-a-date'},
        ).publishedAt,
        isNull,
      );
      expect(
        GithubRelease.fromJson(
          <String, dynamic>{'published_at': '2026-09-15T00:00:00Z'},
        ).publishedAt,
        DateTime.parse('2026-09-15T00:00:00Z'),
      );
    });

    test('fromJson 近似键名（tagName / TAG_NAME / htmlURL）不被识别', () {
      final release = GithubRelease.fromJson(<String, dynamic>{
        'tagName': 'v1.2.3',
        'Tag_Name': 'v1.2.3',
        'TAG_NAME': 'v1.2.3',
        'htmlURL': 'https://x',
        'publishedAt': '2026-09-15T00:00:00Z',
      });

      expect(release.tagName, '');
      expect(release.htmlUrl, '');
      expect(release.publishedAt, isNull);
    });

    test('assets 元素为非 Map<String, dynamic> 的 Map → 走 cast 兜底分支并正常解析', () {
      // jsonDecode 产出 Map<String, dynamic>（走第一分支）；此分支为
      // 「手工组装 / isolate 传回的 Map<Object, Object>」等形态兜底。
      final release = GithubRelease.fromJson(<String, dynamic>{
        'tag_name': 'v9.9.9',
        'assets': <Object>[
          <Object, Object>{
            'name': 'app-release.apk',
            'browser_download_url': 'https://example.com/app-release.apk',
            'size': 42,
          },
        ],
      });

      expect(release.tagName, 'v9.9.9');
      expect(release.assets, hasLength(1));
      expect(release.assets.single.name, 'app-release.apk');
      expect(
        release.assets.single.browserDownloadUrl,
        'https://example.com/app-release.apk',
      );
      expect(release.assets.single.size, 42);
    });

    test('assets 内非 Map 元素（数字 / 字符串 / null / 列表 / bool）被安全跳过', () {
      final release = GithubRelease.fromJson(<String, dynamic>{
        'assets': <Object?>[
          1,
          'str',
          null,
          <Object>[],
          true,
          <String, dynamic>{'name': 'kept.apk'},
        ],
      });

      expect(release.assets, hasLength(1));
      expect(release.assets.single.name, 'kept.apk');
    });

    test('assets 为 null 或空数组 → 空列表（不抛）', () {
      expect(
        GithubRelease.fromJson(<String, dynamic>{'assets': null}).assets,
        isEmpty,
      );
      expect(
        GithubRelease.fromJson(<String, dynamic>{'assets': <Object>[]}).assets,
        isEmpty,
      );
    });
  });

  group('findPlatformAsset', () {
    const mixed = GithubRelease(
      tagName: 'v1',
      htmlUrl: 'h',
      name: 'n',
      assets: <ReleaseAsset>[
        ReleaseAsset(
          name: 'hermes-arm64.apk',
          browserDownloadUrl: 'apk-arm64',
        ),
        ReleaseAsset(
          name: 'hermes-ui-setup.exe',
          browserDownloadUrl: 'exe-setup',
        ),
      ],
    );

    test('不传 platform → 回落 defaultTargetPlatform（android / windows / iOS 三态）', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(findPlatformAsset(mixed)?.name, 'hermes-arm64.apk');

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(findPlatformAsset(mixed)?.name, 'hermes-ui-setup.exe');

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(findPlatformAsset(mixed), isNull);

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(findPlatformAsset(mixed), isNull);
    });

    test('Android：优先 app-release.apk', () {
      const release = GithubRelease(
        tagName: 'v1',
        htmlUrl: 'h',
        name: 'n',
        assets: <ReleaseAsset>[
          ReleaseAsset(name: 'hermes-arm64.apk', browserDownloadUrl: 'other'),
          ReleaseAsset(
            name: 'app-release.apk',
            browserDownloadUrl: 'preferred',
          ),
        ],
      );

      final asset = findPlatformAsset(
        release,
        platform: TargetPlatform.android,
      );
      expect(asset?.name, 'app-release.apk');
      expect(asset?.browserDownloadUrl, 'preferred');
    });

    test('Android：无 app-release.apk 时回退任意 .apk', () {
      const release = GithubRelease(
        tagName: 'v1',
        htmlUrl: 'h',
        name: 'n',
        assets: <ReleaseAsset>[
          ReleaseAsset(
            name: 'hermes-ui-setup.exe',
            browserDownloadUrl: 'exe',
          ),
          ReleaseAsset(
            name: 'hermes-arm64.apk',
            browserDownloadUrl: 'apk-arm64',
          ),
        ],
      );

      final asset = findPlatformAsset(
        release,
        platform: TargetPlatform.android,
      );
      expect(asset?.name, 'hermes-arm64.apk');
      expect(asset?.browserDownloadUrl, 'apk-arm64');
    });

    test('Windows：优先 *-setup.exe', () {
      final asset = findPlatformAsset(mixed, platform: TargetPlatform.windows);
      expect(asset?.name, 'hermes-ui-setup.exe');
      expect(asset?.browserDownloadUrl, 'exe-setup');
    });

    test('Windows：无 *-setup.exe 时回退任意 .exe', () {
      const release = GithubRelease(
        tagName: 'v1',
        htmlUrl: 'h',
        name: 'n',
        assets: <ReleaseAsset>[
          ReleaseAsset(name: 'app-release.apk', browserDownloadUrl: 'apk'),
          ReleaseAsset(
            name: 'hermes-ui-portable.exe',
            browserDownloadUrl: 'exe-plain',
          ),
        ],
      );

      final asset = findPlatformAsset(
        release,
        platform: TargetPlatform.windows,
      );
      expect(asset?.name, 'hermes-ui-portable.exe');
      expect(asset?.browserDownloadUrl, 'exe-plain');
    });

    test('Windows：setup 出现在名字中段（非 -setup.exe 结尾）也算安装包', () {
      const release = GithubRelease(
        tagName: 'v1',
        htmlUrl: 'h',
        name: 'n',
        assets: <ReleaseAsset>[
          ReleaseAsset(
            name: 'HermesUI-setup-x64.exe',
            browserDownloadUrl: 'u',
          ),
        ],
      );

      expect(
        findPlatformAsset(release, platform: TargetPlatform.windows)?.name,
        'HermesUI-setup-x64.exe',
      );
    });

    test('匹配大小写不敏感（.APK / .EXE）', () {
      const release = GithubRelease(
        tagName: 'v1',
        htmlUrl: 'h',
        name: 'n',
        assets: <ReleaseAsset>[
          ReleaseAsset(name: 'APP-RELEASE.APK', browserDownloadUrl: 'apk'),
          ReleaseAsset(name: 'Setup.EXE', browserDownloadUrl: 'exe'),
        ],
      );

      expect(
        findPlatformAsset(release, platform: TargetPlatform.android)?.name,
        'APP-RELEASE.APK',
      );
      expect(
        findPlatformAsset(release, platform: TargetPlatform.windows)?.name,
        'Setup.EXE',
      );
    });

    test('平台错配 / 空资产 → null（不回落到网页）', () {
      const apkOnly = GithubRelease(
        tagName: 'v1',
        htmlUrl: 'h',
        name: 'n',
        assets: <ReleaseAsset>[
          ReleaseAsset(name: 'a.apk', browserDownloadUrl: 'u'),
        ],
      );
      const exeOnly = GithubRelease(
        tagName: 'v1',
        htmlUrl: 'h',
        name: 'n',
        assets: <ReleaseAsset>[
          ReleaseAsset(name: 'a.exe', browserDownloadUrl: 'u'),
        ],
      );
      const none = GithubRelease(tagName: 'v1', htmlUrl: 'h', name: 'n');

      expect(
        findPlatformAsset(apkOnly, platform: TargetPlatform.windows),
        isNull,
      );
      expect(
        findPlatformAsset(exeOnly, platform: TargetPlatform.android),
        isNull,
      );
      expect(findPlatformAsset(none, platform: TargetPlatform.android), isNull);
      expect(findPlatformAsset(none, platform: TargetPlatform.windows), isNull);
      expect(findPlatformAsset(none, platform: TargetPlatform.macOS), isNull);
      expect(findPlatformAsset(none, platform: TargetPlatform.fuchsia), isNull);
    });

    test('Windows：含 setup 但不是 .exe（如 .zip）不算安装包', () {
      const release = GithubRelease(
        tagName: 'v1',
        htmlUrl: 'h',
        name: 'n',
        assets: <ReleaseAsset>[
          ReleaseAsset(name: 'hermes-setup.zip', browserDownloadUrl: 'u'),
        ],
      );

      expect(
        findPlatformAsset(release, platform: TargetPlatform.windows),
        isNull,
      );
    });
  });
}
