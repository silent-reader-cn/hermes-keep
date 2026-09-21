import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';
import 'package:hermes_ui/features/workspace_manager/file_preview_page.dart';

import '../../helpers/fake_download_service.dart';
import '../../helpers/fake_workspace_api.dart';

/// 工作区文件预览的「刷新」入口（#148 同类体检）。
///
/// 注意：这条链路**本来就不吃媒体缓存**（`_WorkspaceFilePreviewSource.loadBytes`
/// 直连 `downloadFile`），所以不存在「看旧图」问题；这里钉的是**刷新入口的
/// 接线** —— `reloadToken` 是显式契约，不能靠「重建时 source 实例不同」这种副作用。
const String kBaseUrl = 'http://test.local:30002';

/// 1x1 透明 PNG（合法位图，base64；避免手抄字节数组抄错）。
final Uint8List kPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

WorkspaceEntry _entry(String name) => WorkspaceEntry(name: name, path: name);

void main() {
  group('FilePreviewBody reloadToken（刷新接线）', () {
    testWidgets('token 自增 → 同一 source 实例也重新加载；token 不变则不重复加载', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;
      // 全程复用同一个 source 实例：这样「只有 token 变」这一条判据是干净的，
      // 不会和 source 变化带来的重载混淆（source 的值语义另有用例覆盖）。
      final source = FilePreviewSource.workspaceFile('s1', 'pic.png');
      // 复用同一批 override 实例（避免每次 pump 重放新 override）。
      final overrides = <Override>[
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: kBaseUrl)),
        workspaceApiFactoryProvider.overrideWithValue((_) => api),
      ];

      Widget wrap(int token) => ProviderScope(
        overrides: overrides,
        child: CupertinoApp(
          home: FilePreviewBody(
            fileName: 'pic.png',
            source: source,
            reloadToken: token,
          ),
        ),
      );

      await tester.pumpWidget(wrap(0));
      await tester.pump();
      await tester.pump();
      expect(api.downloadCalls, hasLength(1));

      // 宿主点「刷新」：token 0 → 1。
      await tester.pumpWidget(wrap(1));
      await tester.pump();
      await tester.pump();
      expect(api.downloadCalls, hasLength(2));

      // 纯重建（token 不变）不得重新拉取 —— RED 红线：把 token 判据写成恒真
      // （或干脆删掉该分支）即可复现。
      await tester.pumpWidget(wrap(1));
      await tester.pump();
      await tester.pump();
      expect(api.downloadCalls, hasLength(2));
    });
  });

  group('FilePreviewBody source 值语义', () {
    testWidgets('宿主同型重建（每次新建等值 source 实例）不重复拉取；换文件才重载', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;
      final overrides = <Override>[
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: kBaseUrl)),
        workspaceApiFactoryProvider.overrideWithValue((_) => api),
      ];

      // 宿主真实写法：每次 build 都 `FilePreviewSource.workspaceFile(...)` 新建实例。
      Widget wrap({String path = 'pic.png'}) => ProviderScope(
        overrides: overrides,
        child: CupertinoApp(
          home: FilePreviewBody(
            fileName: path,
            source: FilePreviewSource.workspaceFile('s1', path),
          ),
        ),
      );

      await tester.pumpWidget(wrap());
      await tester.pump();
      await tester.pump();
      expect(api.downloadCalls, hasLength(1));

      // RED 红线：source 退回默认的同一性比较 ⇒ 等值重建也会重载，
      // 于是「主题/语言切换、下载态 setState」等任何宿主 rebuild 都白拉一整份。
      await tester.pumpWidget(wrap());
      await tester.pump();
      await tester.pump();
      expect(api.downloadCalls, hasLength(1), reason: '等值 source 不该触发重载');

      // 真换文件仍必须重载。
      await tester.pumpWidget(wrap(path: 'other.png'));
      await tester.pump();
      await tester.pump();
      expect(api.downloadCalls, hasLength(2));
    });
  });

  group('FilePreviewPage 导航栏刷新按钮', () {
    testWidgets('按钮存在，点击后重新拉取文件内容', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient(baseUrl: kBaseUrl)),
            workspaceApiFactoryProvider.overrideWithValue((_) => api),
            ...createDownloadTestOverrides(),
          ],
          child: CupertinoApp(
            home: FilePreviewPage(sessionId: 's1', entry: _entry('pic.png')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final refresh = find.byKey(const ValueKey('preview-refresh'));
      expect(refresh, findsOneWidget);
      // 下载按钮仍在（刷新是并排新增，不是替换）。
      expect(find.byKey(const ValueKey('preview-download')), findsOneWidget);

      final before = api.downloadCalls.length;
      await tester.tap(refresh);
      await tester.pump();
      await tester.pump();

      expect(api.downloadCalls.length, greaterThan(before));
      expect(api.downloadCalls.last, 's1|pic.png');
    });
  });
}
