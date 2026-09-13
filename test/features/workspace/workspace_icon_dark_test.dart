import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/workspace/workspace_page.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_page.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_providers.dart';

import '../../helpers/fake_workspace_api.dart';
import '../../helpers/fake_workspace_manager_api.dart';

void main() {
  group('Workspace 文件与导航图标深浅色模式解析回归测试', () {
    testWidgets('dark: 目录与文件图标颜色与底色块正确解析为深色变体', (tester) async {
      final fakeApi = FakeWorkspaceApi(
        directories: {
          '.': [
            const WorkspaceEntry(
              name: 'src',
              path: 'src',
              type: 'directory',
              isDirectory: true,
            ),
            const WorkspaceEntry(
              name: 'plain.bin',
              path: 'plain.bin',
              type: 'file',
              size: 512,
            ),
            const WorkspaceEntry(
              name: 'code.dart',
              path: 'code.dart',
              type: 'code',
              size: 1024,
            ),
          ],
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            workspaceApiFactoryProvider.overrideWithValue((_) => fakeApi),
          ],
          child: const CupertinoApp(
            theme: CupertinoThemeData(brightness: Brightness.dark),
            home: WorkspacePage(sessionId: 's1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 1. 目录图标：CupertinoIcons.folder 颜色应为 white (0xFFFFFFFF)
      final folderIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.folder),
      );
      expect(folderIcon.color!.toARGB32(), 0xFFFFFFFF);

      // 2. 普通文件图标：CupertinoIcons.doc 颜色应为 secondaryLabel dark (0x99EBEBF5)
      final docIcon = tester.widget<Icon>(find.byIcon(CupertinoIcons.doc));
      expect(docIcon.color!.toARGB32(), 0x99EBEBF5);

      // 3. 代码图标：systemGreen dark (0xFF30D158)
      final codeIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.chevron_left_slash_chevron_right),
      );
      expect(codeIcon.color!.toARGB32(), 0xFF30D158);

      // 4. 目录项图标容器底色：tertiarySystemFill dark (0x3D767680)
      final folderRow = find.byKey(const ValueKey('workspace-row-src'));
      final folderContainer = tester.widget<Container>(
        find.descendant(of: folderRow, matching: find.byType(Container)).first,
      );
      final folderBox = folderContainer.decoration as BoxDecoration;
      expect(folderBox.color!.toARGB32(), 0x3D767680);

      // 5. 文件项图标容器底色：secondarySystemFill dark (0x51787880)
      final docRow = find.byKey(const ValueKey('workspace-row-plain.bin'));
      final docContainer = tester.widget<Container>(
        find.descendant(of: docRow, matching: find.byType(Container)).first,
      );
      final docBox = docContainer.decoration as BoxDecoration;
      expect(docBox.color!.toARGB32(), 0x51787880);

      // 6. 行尾省略号动作按钮图标：secondaryLabel dark (0x99EBEBF5)
      final actionsButton = find.byKey(
        const ValueKey('workspace-actions-plain.bin'),
      );
      final ellipsisIcon = tester.widget<Icon>(
        find.descendant(of: actionsButton, matching: find.byType(Icon)),
      );
      expect(ellipsisIcon.color!.toARGB32(), 0x99EBEBF5);

      // 7. 列表容器在深色模式下保持系统原生样式（decoration 为 null）
      final section = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(section.decoration, isNull);
    });

    testWidgets('dark: 面包屑与顶部导航在深色模式下正确解析', (tester) async {
      final fakeApi = FakeWorkspaceApi(
        directories: {
          '.': [
            const WorkspaceEntry(
              name: 'src',
              path: 'src',
              type: 'directory',
              isDirectory: true,
            ),
          ],
          'src': [
            const WorkspaceEntry(
              name: 'nested.dart',
              path: 'src/nested.dart',
              type: 'code',
            ),
          ],
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            workspaceApiFactoryProvider.overrideWithValue((_) => fakeApi),
          ],
          child: const CupertinoApp(
            theme: CupertinoThemeData(brightness: Brightness.dark),
            home: WorkspacePage(sessionId: 's1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 点击目录行进入子目录
      await tester.tap(find.byKey(const ValueKey('workspace-row-src')));
      await tester.pumpAndSettle();

      // 面包屑中的分隔符 chevron_right 颜色应为 tertiaryLabel dark (0x4CEBEBF5)
      final chevronIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.chevron_right),
      );
      expect(chevronIcon.color!.toARGB32(), 0x4CEBEBF5);
    });

    testWidgets('light: 目录与文件图标颜色与底色块保持浅色模式一致', (tester) async {
      final fakeApi = FakeWorkspaceApi(
        directories: {
          '.': [
            const WorkspaceEntry(
              name: 'src',
              path: 'src',
              type: 'directory',
              isDirectory: true,
            ),
            const WorkspaceEntry(
              name: 'plain.bin',
              path: 'plain.bin',
              type: 'file',
              size: 512,
            ),
            const WorkspaceEntry(
              name: 'main.dart',
              path: 'main.dart',
              type: 'code',
              size: 1024,
            ),
            const WorkspaceEntry(
              name: 'README.md',
              path: 'README.md',
              type: 'text',
              size: 256,
            ),
          ],
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            workspaceApiFactoryProvider.overrideWithValue((_) => fakeApi),
          ],
          child: const CupertinoApp(
            theme: CupertinoThemeData(brightness: Brightness.light),
            home: WorkspacePage(sessionId: 's1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 1. 目录图标：CupertinoIcons.folder 浅色为 0xFF000000
      final folderIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.folder),
      );
      expect(folderIcon.color!.toARGB32(), 0xFF000000);

      // 2. 普通文件图标：CupertinoIcons.doc 浅色为 LightSurfaces.textSecondary (0xFF6A6A6F)
      final docIcon = tester.widget<Icon>(find.byIcon(CupertinoIcons.doc));
      expect(docIcon.color!.toARGB32(), LightSurfaces.textSecondary.toARGB32());

      // 3. 代码文件图标：statusGreenText 浅色为 0xFF1E7A34
      final codeIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.chevron_left_slash_chevron_right),
      );
      expect(codeIcon.color!.toARGB32(), statusGreenText.color.toARGB32());

      // 4. 文本/Markdown 文件图标：statusTealText 浅色为 0xFF0E7C86
      final textIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.doc_text),
      );
      expect(textIcon.color!.toARGB32(), statusTealText.color.toARGB32());

      // 5. 目录项图标容器底色：tertiarySystemFill light (0x1E767680)
      final folderRow = find.byKey(const ValueKey('workspace-row-src'));
      final folderContainer = tester.widget<Container>(
        find.descendant(of: folderRow, matching: find.byType(Container)).first,
      );
      final folderBox = folderContainer.decoration as BoxDecoration;
      expect(folderBox.color!.toARGB32(), 0x1E767680);

      // 6. 文件项图标容器底色：secondarySystemFill light (0x28787880)
      final docRow = find.byKey(const ValueKey('workspace-row-plain.bin'));
      final docContainer = tester.widget<Container>(
        find.descendant(of: docRow, matching: find.byType(Container)).first,
      );
      final docBox = docContainer.decoration as BoxDecoration;
      expect(docBox.color!.toARGB32(), 0x28787880);

      // 7. 列表容器浅色模式卡片底色与 0.5px 发丝线边框
      final section = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      final sectionBox = section.decoration as BoxDecoration;
      expect(sectionBox.color, LightSurfaces.card);
      expect(sectionBox.border?.top.color, LightSurfaces.cardBorder);
      expect(sectionBox.border?.top.width, 0.5);
    });

    testWidgets('dark: WorkspaceManagerPage 文件夹图标与徽标在深色模式下正确解析', (
      tester,
    ) async {
      final fakeApi = FakeWorkspaceManagerApi(
        workspaces: const [
          WorkspaceRoot(name: 'Main', path: '/workspaces/main'),
        ],
        last: '/workspaces/main',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            workspaceManagerApiFactoryProvider.overrideWithValue(
              (_) => fakeApi,
            ),
          ],
          child: const CupertinoApp(
            theme: CupertinoThemeData(brightness: Brightness.dark),
            home: WorkspaceManagerPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 1. 文件夹图标颜色为 white (0xFFFFFFFF)
      final folderIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.folder),
      );
      expect(folderIcon.color!.toARGB32(), 0xFFFFFFFF);

      // 2. 文件夹容器底色为 tertiarySystemFill dark (0x3D767680)
      final folderRow = find.byKey(
        const ValueKey('workspace-manager-row-/workspaces/main'),
      );
      final folderContainer = tester.widget<Container>(
        find.descendant(of: folderRow, matching: find.byType(Container)).first,
      );
      final folderBox = folderContainer.decoration as BoxDecoration;
      expect(folderBox.color!.toARGB32(), 0x3D767680);
    });
  });
}
