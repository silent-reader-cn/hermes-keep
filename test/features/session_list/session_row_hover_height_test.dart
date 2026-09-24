import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' show PointerDeviceKind;

import '../../helpers/fake_session_list_api.dart';

// ---------------------------------------------------------------------------
// #155：组头「悬停出 +」不得改变高度（主人实测回归：+ 的 22px 命中区把组头撑高）。
//
// 修法是「始终占位 + 只切不透明度」，所以断言分两层：
//   ① 未悬停时 + 也**存在于布局**（findsOneWidget，只是 opacity=0）；
//   ② 悬停前后组头**尺寸逐像素相同**。
// ② 是真正的防回归闸门：只要有人改回 `if (hovering)` 条件插入，它就会红。
// ---------------------------------------------------------------------------

SessionSummary _s(String id, String title, {String? workspace}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    workspace: workspace,
    lastMessageAt: DateTime(2026, 9, 24, 10).millisecondsSinceEpoch / 1000,
  );
}

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const delegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  Future<void> pumpSidebar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeSessionListApi(
      sessions: <SessionSummary>[
        _s('a', '工作区里的会话 A', workspace: '/home/u/my-project'),
        _s('b', '工作区里的会话 B', workspace: '/home/u/my-project'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 必须有：侧栏列表要读连接态，缺它会显示「未配置服务器连接」而不是会话。
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        ],
        child: const CupertinoApp(
          locale: Locale('zh'),
          supportedLocales: [Locale('zh'), Locale('en')],
          localizationsDelegates: delegates,
          home: CupertinoPageScaffold(
            child: SizedBox(
              width: 340,
              child: SessionSidebar(currentLocation: '/'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 找到第一个「工作区组」的组头 key（非置顶 / 非其他）。
  String? firstWorkspaceSectionKey(WidgetTester tester) {
    for (final e in find.byType(Text).evaluate()) {
      final key = (e.widget as Text).data;
      if (key == null) continue;
    }
    // 直接按 key 前缀扫：session-section-header-<key>
    for (final e in find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          k.value.startsWith('session-section-header-');
    }).evaluate()) {
      final k = (e.widget.key! as ValueKey<String>).value;
      final sectionKey = k.substring('session-section-header-'.length);
      if (sectionKey == '置顶' || sectionKey == '其他') continue;
      return sectionKey;
    }
    return null;
  }

  testWidgets('未悬停时组头「+」已存在于布局（占位，只是不可见）', (tester) async {
    await pumpSidebar(tester);
    final sectionKey = firstWorkspaceSectionKey(tester);
    expect(sectionKey, isNotNull, reason: '应存在一个工作区组');

    expect(
      find.byKey(ValueKey('session-section-new-$sectionKey')),
      findsOneWidget,
      reason: '「+」应始终参与布局（占位方案），而不是条件插入',
    );
  });

  testWidgets('★ 悬停工作区组头前后，组头尺寸逐像素不变（防回归闸门）', (tester) async {
    await pumpSidebar(tester);
    final sectionKey = firstWorkspaceSectionKey(tester);
    expect(sectionKey, isNotNull);

    final headerFinder = find.byKey(
      ValueKey('session-section-header-$sectionKey'),
    );
    final sizeBefore = tester.getSize(headerFinder);

    // 鼠标移入组头
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(headerFinder));
    await mouse.moveTo(tester.getCenter(headerFinder));
    await tester.pumpAndSettle();

    // 悬停后「+」可见（opacity 1），但仍应占同一尺寸
    final sizeDuring = tester.getSize(headerFinder);

    // 移出
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    final sizeAfter = tester.getSize(headerFinder);

    expect(
      sizeDuring.height,
      moreOrLessEquals(sizeBefore.height, epsilon: 0.01),
      reason: '悬停时组头高度不得变化（原回归：+ 的命中区把组头撑高）',
    );
    expect(
      sizeAfter.height,
      moreOrLessEquals(sizeBefore.height, epsilon: 0.01),
    );
    expect(
      sizeDuring.width,
      moreOrLessEquals(sizeBefore.width, epsilon: 0.01),
    );
  });

  testWidgets('会话项悬停同样不改变行高（#153 已修，一并守住）', (tester) async {
    await pumpSidebar(tester);

    final rowFinder = find.byKey(const ValueKey('session-row-a'));
    expect(rowFinder, findsOneWidget);
    final before = tester.getSize(rowFinder);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(rowFinder));
    await mouse.moveTo(tester.getCenter(rowFinder));
    await tester.pumpAndSettle();

    final during = tester.getSize(rowFinder);
    expect(
      during.height,
      moreOrLessEquals(before.height, epsilon: 0.01),
      reason: '悬停时会话行行高不得变化',
    );
  });
}