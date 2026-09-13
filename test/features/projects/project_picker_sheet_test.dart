import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_picker_sheet.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';

class _FakeProjectApi implements ProjectApi {
  _FakeProjectApi({this.projects = const []});

  List<ProjectSummary> projects;

  @override
  Future<ProjectsResponse> fetchProjects() async {
    return ProjectsResponse(projects: projects);
  }

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async {
    final newProj = ProjectSummary(projectId: 'new-id', name: name);
    projects = [...projects, newProj];
    return ProjectMutationResponse(ok: true, project: newProj);
  }

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async {
    return const ProjectMutationResponse(ok: true);
  }

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async {
    return const ProjectMutationResponse(ok: true);
  }
}

Future<void> _pumpPickerSheet(
  WidgetTester tester, {
  required _FakeProjectApi api,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectApiFactoryProvider.overrideWithValue((_) => api),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
      ],
      child: CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: CupertinoPageScaffold(
          child: Center(
            child: Builder(
              builder: (context) => CupertinoButton(
                key: const ValueKey('open-picker-btn'),
                onPressed: () => unawaited(showProjectPicker(context)),
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-picker-btn')));
  await tester.pumpAndSettle();
}

void main() {
  group('ProjectPickerSheet 双主题断言', () {
    testWidgets(
      '浅色主题：ActionSheet 标题次级字/操作项 menuAction/新建对话框白卡描边与 userDetail 按钮',
      (tester) async {
        final api = _FakeProjectApi(
          projects: [const ProjectSummary(projectId: 'p1', name: '项目一')],
        );
        await _pumpPickerSheet(tester, api: api, brightness: Brightness.light);

        // 1. ActionSheet 浅色标题使用 textSecondary
        final titleWidget = tester.widget<Text>(find.text('移动到项目'));
        expect(titleWidget.style?.color, LightSurfaces.textSecondary);

        // 2. 「无项目」使用 menuAction
        final noneText = tester.widget<Text>(find.text('无项目'));
        expect(noneText.style?.color, LightSurfaces.menuAction);

        // 3. 项目行文字使用 menuAction，ellipsis 图标使用 textSecondary
        final p1Text = tester.widget<Text>(find.text('项目一'));
        expect(p1Text.style?.color, LightSurfaces.menuAction);
        final ellipsisIcon = tester.widget<Icon>(
          find.byIcon(CupertinoIcons.ellipsis),
        );
        expect(ellipsisIcon.color, LightSurfaces.textSecondary);

        // 4. 「新建项目…」使用 menuAction
        final createText = tester.widget<Text>(find.text('新建项目…'));
        expect(createText.style?.color, LightSurfaces.menuAction);

        // 5. 「取消」使用 menuAction
        final cancelText = tester.widget<Text>(find.text('取消'));
        expect(cancelText.style?.color, LightSurfaces.menuAction);

        // 6. 点击「新建项目…」弹出新建对话框，验证浅色输入框与操作按钮
        await tester.tap(find.byKey(const ValueKey('project-picker-create')));
        await tester.pumpAndSettle();

        final nameField = tester.widget<CupertinoTextField>(
          find.byKey(const ValueKey('project-create-name')),
        );
        final fieldDec = nameField.decoration as BoxDecoration;
        expect(fieldDec.color, LightSurfaces.card);
        expect(fieldDec.borderRadius, BorderRadius.circular(5));
        expect(fieldDec.border?.top.color, LightSurfaces.cardBorder);
        expect(fieldDec.border?.top.width, 0.5);
        expect(nameField.placeholderStyle?.color, LightSurfaces.placeholder);

        final dialogCancel = tester.widget<CupertinoDialogAction>(
          find.byKey(const ValueKey('project-create-cancel')),
        );
        expect(dialogCancel.textStyle?.color, LightSurfaces.userDetail);

        final dialogConfirm = tester.widget<CupertinoDialogAction>(
          find.byKey(const ValueKey('project-create-confirm')),
        );
        expect(dialogConfirm.textStyle?.color, LightSurfaces.userDetail);

        // 7. 取消关闭新建对话框与 ActionSheet，避免测试悬挂
        await tester.tap(find.byKey(const ValueKey('project-create-cancel')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('project-picker-cancel')));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '暗色主题：ActionSheet 标题与操作项回退 null 原生样式/图标 secondaryLabel/对话框系统默认',
      (tester) async {
        final api = _FakeProjectApi(
          projects: [const ProjectSummary(projectId: 'p1', name: '项目一')],
        );
        await _pumpPickerSheet(tester, api: api, brightness: Brightness.dark);

        // 1. ActionSheet 暗色标题为 null（使用系统默认样式）
        final titleWidget = tester.widget<Text>(find.text('移动到项目'));
        expect(titleWidget.style, isNull);

        // 2. 「无项目」暗色为 null
        final noneText = tester.widget<Text>(find.text('无项目'));
        expect(noneText.style, isNull);

        // 3. 项目行文字暗色为 null，ellipsis 图标解析为 secondaryLabel
        final p1Text = tester.widget<Text>(find.text('项目一'));
        expect(p1Text.style, isNull);
        final darkContext = tester.element(
          find.byKey(const ValueKey('project-picker-p1')),
        );
        final ellipsisIcon = tester.widget<Icon>(
          find.byIcon(CupertinoIcons.ellipsis),
        );
        expect(
          ellipsisIcon.color,
          CupertinoColors.secondaryLabel.resolveFrom(darkContext),
        );

        // 4. 「新建项目…」暗色为 null
        final createText = tester.widget<Text>(find.text('新建项目…'));
        expect(createText.style, isNull);

        // 5. 「取消」暗色为 null
        final cancelText = tester.widget<Text>(find.text('取消'));
        expect(cancelText.style, isNull);

        // 6. 点击「新建项目…」弹出新建对话框，验证暗色输入框与操作按钮保持系统默认
        await tester.tap(find.byKey(const ValueKey('project-picker-create')));
        await tester.pumpAndSettle();

        final nameField = tester.widget<CupertinoTextField>(
          find.byKey(const ValueKey('project-create-name')),
        );
        expect(nameField.decoration, const CupertinoTextField().decoration);
        expect(
          nameField.placeholderStyle,
          const CupertinoTextField().placeholderStyle,
        );

        final dialogCancel = tester.widget<CupertinoDialogAction>(
          find.byKey(const ValueKey('project-create-cancel')),
        );
        expect(dialogCancel.textStyle, isNull);

        final dialogConfirm = tester.widget<CupertinoDialogAction>(
          find.byKey(const ValueKey('project-create-confirm')),
        );
        expect(dialogConfirm.textStyle, isNull);

        // 7. 取消关闭新建对话框与 ActionSheet，避免测试悬挂
        await tester.tap(find.byKey(const ValueKey('project-create-cancel')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('project-picker-cancel')));
        await tester.pumpAndSettle();
      },
    );
  });
}
