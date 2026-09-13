import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/workspace_manager/add_workspace_sheet.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_page.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_providers.dart';

import '../../helpers/fake_workspace_manager_api.dart';

/// WCAG 2.1 相对亮度计算
double _linearize(double component) {
  return component <= 0.04045
      ? component / 12.92
      : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color color) {
  final r = _linearize(color.r);
  final g = _linearize(color.g);
  final b = _linearize(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG 2.1 对比度实算：(L1 + 0.05) / (L2 + 0.05)
double _contrastRatio(Color c1, Color c2) {
  final l1 = _relativeLuminance(c1);
  final l2 = _relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('WorkspaceManager & AddWorkspaceSheet 浅深双主题与无障碍对比度测试', () {
    test('WCAG 对比度实算：浅色控件在其承载面上达标断言', () {
      // 1. userDetail (#005FB8) 在 card (#FFFFFF) 上对比度 >= 4.5:1 (正文 AA)
      final userDetailOnCard = _contrastRatio(
        LightSurfaces.userDetail,
        LightSurfaces.card,
      );
      expect(userDetailOnCard, greaterThanOrEqualTo(4.5));

      // 2. 当前选中徽标字 statusBlueText (#005FB8) 在 selection 面 (#E0ECFF) 上 >= 4.5:1
      final badgeOnSelection = _contrastRatio(
        statusBlueText.color,
        LightSurfaces.selection,
      );
      expect(badgeOnSelection, greaterThanOrEqualTo(4.5));

      // 3. 勾选图标 statusGreenText (#1E7A34) 在 selection 面 (#E0ECFF) 上 >= 3:1 (图形标识)
      final checkOnSelection = _contrastRatio(
        statusGreenText.color,
        LightSurfaces.selection,
      );
      expect(checkOnSelection, greaterThanOrEqualTo(3.0));

      // 4. 次级文字 textSecondary (#6A6A6F) 在 page 面 (#F2F2F7) 上 >= 4.5:1
      final secondaryOnPage = _contrastRatio(
        LightSurfaces.textSecondary,
        LightSurfaces.page,
      );
      expect(secondaryOnPage, greaterThanOrEqualTo(4.5));
    });

    testWidgets('light/dark: WorkspaceManagerPage 卡片边框与当前徽标双主题表现', (
      tester,
    ) async {
      final fakeApi = FakeWorkspaceManagerApi(
        workspaces: const [
          WorkspaceRoot(name: 'Main', path: '/workspaces/main'),
        ],
        last: '/workspaces/main',
      );

      // --- 浅色模式 ---
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
            theme: CupertinoThemeData(brightness: Brightness.light),
            home: WorkspaceManagerPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final lightSection = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      final lightSectionBox = lightSection.decoration as BoxDecoration;
      expect(lightSectionBox.color, LightSurfaces.card);
      expect(lightSectionBox.border?.top.color, LightSurfaces.cardBorder);
      expect(lightSectionBox.border?.top.width, 0.5);

      final lightBadge = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey('workspace-manager-row-/workspaces/main'),
              ),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius != null,
              ),
            )
            .last,
      );
      final lightBadgeBox = lightBadge.decoration as BoxDecoration;
      expect(lightBadgeBox.color, LightSurfaces.selection);

      // 卸载以防 ProviderScope 残留
      await tester.pumpWidget(const SizedBox());

      // --- 深色模式 ---
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

      final darkSection = tester.widget<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(darkSection.decoration, isNull);

      final darkBadge = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey('workspace-manager-row-/workspaces/main'),
              ),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius != null,
              ),
            )
            .last,
      );
      final darkBadgeBox = darkBadge.decoration as BoxDecoration;
      final expectedDarkBadgeColor = CupertinoColors.systemBlue
          .resolveFrom(tester.element(find.byType(WorkspaceManagerPage)))
          .withValues(alpha: 0.15);
      expect(darkBadgeBox.color, expectedDarkBadgeColor);
    });

    testWidgets('light/dark: AddWorkspaceSheet 输入框 placeholderStyle 与卡片面', (
      tester,
    ) async {
      // --- 浅色模式 ---
      await tester.pumpWidget(
        const ProviderScope(
          child: CupertinoApp(
            theme: CupertinoThemeData(brightness: Brightness.light),
            home: CupertinoPageScaffold(child: AddWorkspaceSheet()),
          ),
        ),
      );
      await tester.pump();

      final lightPathField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('workspace-add-path')),
      );
      expect(lightPathField.placeholderStyle?.color, LightSurfaces.placeholder);
      expect(lightPathField.placeholderStyle?.fontWeight, isNull);

      final lightNameField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('workspace-add-name')),
      );
      expect(lightNameField.placeholderStyle?.color, LightSurfaces.placeholder);
      expect(lightNameField.placeholderStyle?.fontWeight, isNull);

      final lightCancelText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('workspace-add-cancel')),
          matching: find.byType(Text),
        ),
      );
      expect(
        lightCancelText.style!.color!.toARGB32(),
        statusBlueText
            .resolveFrom(tester.element(find.byType(AddWorkspaceSheet)))
            .toARGB32(),
      );

      // 卸载
      await tester.pumpWidget(const SizedBox());

      // --- 深色模式 ---
      await tester.pumpWidget(
        const ProviderScope(
          child: CupertinoApp(
            theme: CupertinoThemeData(brightness: Brightness.dark),
            home: CupertinoPageScaffold(child: AddWorkspaceSheet()),
          ),
        ),
      );
      await tester.pump();

      final darkPathField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('workspace-add-path')),
      );
      expect(
        darkPathField.placeholderStyle?.color,
        CupertinoColors.placeholderText.resolveFrom(
          tester.element(find.byType(AddWorkspaceSheet)),
        ),
      );
      expect(darkPathField.placeholderStyle?.fontWeight, isNull);

      final darkCancelText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('workspace-add-cancel')),
          matching: find.byType(Text),
        ),
      );
      expect(
        darkCancelText.style?.color,
        CupertinoColors.systemBlue.resolveFrom(
          tester.element(find.byType(AddWorkspaceSheet)),
        ),
      );
    });
  });
}
