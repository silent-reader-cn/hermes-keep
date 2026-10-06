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
// 「深色 / 浅色共用同一套 inset 分区结构」真渲染取证工装（**非金照基线**）
//
// 用途：主人要看的四张 1:1 真图 —— 同一张设置页，深/浅 × 宽/窄，用于目检
// 「深色不再通栏方角、与浅色同为一套内缩卡片」。
//
// 用法：
//   SETTINGS_CARD_SHOTS=1 C:/tmp/f.bat test test/screenshots/settings_card_shots_test.dart \
//       --update-goldens
//   不带 SETTINGS_CARD_SHOTS=1 时全部 skip，`flutter test` 全量零影响。
//
// 产物：`.shots/settings-card/settings-<wide|narrow>-<light|dark>.png`
//   （DPR 2.0，与仓库其余工装一致；`.shots/` 已在 .gitignore，故不进金照基线）
//
// 视口：宽 1280×800 逻辑（≥ kAdaptiveBreakpoint=900 ⇒ 左 220 分类导航 + 右内容
//       限宽 744）；窄 390×844 逻辑（< 900 ⇒ 单列长卷）。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip。
final bool _capture = Platform.environment['SETTINGS_CARD_SHOTS'] == '1';
const String _skipReason = '设置 SETTINGS_CARD_SHOTS=1 才生成设置页分区卡片取证图';

/// 产物根目录（相对本文件：test/screenshots/ → 仓库根 .shots）。
const String _shotRoot = '../../.shots/settings-card';

/// 宽屏视口（物理像素，DPR 2.0 ⇒ 逻辑 1280×800）。
const Size _wideSize = Size(2560, 1600);

/// 窄屏视口（物理像素，DPR 2.0 ⇒ 逻辑 390×844）。
const Size _narrowSize = Size(780, 1688);

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
    for (final viewport in const ['wide', 'narrow']) {
      final suffix = brightness == Brightness.dark ? 'dark' : 'light';
      testWidgets('设置页分区卡片 $viewport $suffix', (tester) async {
        await pumpHermesPage(
          tester,
          page: const SettingsPage(),
          brightness: brightness,
          overrides: await _overrides(),
          size: viewport == 'wide' ? _wideSize : _narrowSize,
        );
        await tester.pumpAndSettle();

        Directory(_shotRoot).createSync(recursive: true);
        await expectLater(
          find.byType(CupertinoApp),
          matchesGoldenFile('$_shotRoot/settings-$viewport-$suffix.png'),
        );

        await unmountHermesPage(tester);
      }, skip: !_capture);
    }
  }

  test('工装门控', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);
}
