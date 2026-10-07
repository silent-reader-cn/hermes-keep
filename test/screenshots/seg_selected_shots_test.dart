import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 分段控件「选中态」设计稿工装（真渲染，非金照基线）
//
// 用途：主人 2026-10-07 报「设置页分段控件选中项（跟随系统）文字和底色都太浅」，
// 需要「同一界面 × 明暗两态 × 现状/候选档」的 1:1 真图用于拍板。
//
// 用法（改前一份、改后一份，用 TAG 区分文件名）：
//   SEG_SHOTS=1 SEG_SHOTS_TAG=before C:/tmp/f.bat test --no-pub \
//       test/screenshots/seg_selected_shots_test.dart --update-goldens
//   （落码后把 TAG 换成 after 再跑一次）
//
// 产物：`.shots/seg-selected/<tag>-<light|dark>.png`（DPR 2.0）
// 视口：390×1200 逻辑（手机档；< 900 ⇒ 单列长卷，与主人真机截图同形态）。
// 不带 SEG_SHOTS=1 时全部 skip，`flutter test` 全量零影响。
// ---------------------------------------------------------------------------

final bool _capture = Platform.environment['SEG_SHOTS'] == '1';
const String _skipReason = '设置 SEG_SHOTS=1 才生成分段控件选中态设计稿';

final String _tag = Platform.environment['SEG_SHOTS_TAG'] ?? 'current';
const String _shotRoot = '../../.shots/seg-selected';

/// 手机档视口（物理像素，DPR 2.0 ⇒ 逻辑 390×1200）。
const Size _phoneSize = Size(780, 2400);

Future<List<Override>> _overrides() async {
  final store = ConnectionStore(storage: InMemorySecureStorage());
  await store.save(
    ServerConnection(
      id: 'c1',
      name: 'Home 服务器',
      baseUrl: 'http://hermes.local:30002',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');
  final api = FakeSettingsApi();
  api.modelsResponse = ModelsResponse.fromJson({
    'default_model': 'gpt-4o',
    'active_provider': 'openai',
    'groups': [
      {
        'provider_id': 'openai',
        'name': 'OpenAI',
        'models': [
          {'id': 'gpt-4o', 'name': 'GPT-4o'},
          {'id': 'gpt-4o-mini', 'name': 'GPT-4o mini'},
        ],
      },
    ],
  });
  api.reasoningResponse = const ReasoningStatusResponse(
    ok: true,
    reasoningEffort: 'medium',
    supportedEfforts: ['low', 'medium', 'high'],
    supportsReasoningEffort: true,
  );
  return [
    connectionStoreProvider.overrideWithValue(store),
    apiClientProvider.overrideWithValue(
      ApiClient(baseUrl: 'http://hermes.local:30002'),
    ),
    settingsApiFactoryProvider.overrideWithValue((_) => api),
  ];
}

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('分段控件选中态 手机档 $suffix ($_tag)', (tester) async {
      await pumpHermesPage(
        tester,
        page: const SettingsPage(),
        brightness: brightness,
        overrides: await _overrides(),
        size: _phoneSize,
      );
      await tester.pumpAndSettle();

      Directory(_shotRoot).createSync(recursive: true);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('$_shotRoot/$_tag-$suffix.png'),
      );

      await unmountHermesPage(tester);
    }, skip: !_capture);
  }

  test('工装门控', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);
}
