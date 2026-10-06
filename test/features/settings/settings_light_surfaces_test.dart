import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/extensions.dart';
import 'package:hermes_ui/core/models/mcp.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/settings/extensions_section.dart';
import 'package:hermes_ui/features/settings/mcp_section.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/settings/settings_subpages.dart';
import 'package:hermes_ui/features/settings/settings_surfaces.dart';
import 'package:hermes_ui/features/settings/webui_sidecar_section.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _NoUpdateController extends AutoCheckUpdateController {
  @override
  bool build() => false;
}

class _SlowInstallApi extends FakeSettingsApi {
  final gate = Completer<ExtensionInstallResponse>();

  @override
  Future<ExtensionInstallResponse> installExtension({
    required String id,
    required String downloadUrl,
    required String sha256,
  }) => gate.future;
}

class _SidecarFileSystem extends Mock implements SidecarFileSystem {}

class _SidecarConfigController extends WebuiSidecarConfigController {
  @override
  SidecarConfig build() => const SidecarConfig();

  @override
  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
  }
}

class _AgentPresentController extends AgentEnvPresentNotifier {
  @override
  FutureOr<bool> build() => true;
}

class _SidecarController extends WebuiSidecarController {
  _SidecarController(this.initial);

  final SidecarState initial;
  final startGate = Completer<void>();

  @override
  SidecarState build() => initial;

  @override
  Future<void> start() => startGate.future;
}

Color _textColor(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  return paragraph.text.style!.color!;
}

double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
}

void _expectReadable(WidgetTester tester, Finder text, Color surface) {
  expect(
    _contrast(_textColor(tester, text), surface),
    greaterThanOrEqualTo(4.5),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  double width = 390,
  TextScaler textScaler = TextScaler.noScaling,
  FakeSettingsApi? api,
  List<Override> overrides = const [],
}) async {
  final store = ConnectionStore(storage: InMemorySecureStorage());
  for (final id in ['active', 'other']) {
    await store.save(
      ServerConnection(
        id: id,
        name: 'Server $id',
        baseUrl: 'https://$id.example.com',
        createdAt: DateTime.utc(2026),
      ),
    );
  }
  await store.setActive('active');
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://example.com'),
        ),
        settingsApiFactoryProvider.overrideWithValue(
          (_) => api ?? FakeSettingsApi(),
        ),
        autoCheckUpdateEnabledProvider.overrideWith(_NoUpdateController.new),
        ...overrides,
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 批 3 起宽屏（≥900）只渲染当前分类：服务器相关断言先点左栏「服务器」分类。
///
/// 窄屏（<900）仍是 8 个 section 长卷，不需要这一步。
Future<void> _selectServerCategory(WidgetTester tester, double width) async {
  if (width < 900) return;
  await tester.tap(find.byKey(const ValueKey('settings-nav-server')));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(
      find.byKey(const ValueKey('settings-scroll')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
}

void _expectFieldsReadable(WidgetTester tester, int count) {
  final fields = tester.widgetList<CupertinoTextField>(
    find.byType(CupertinoTextField),
  );
  expect(fields, hasLength(count));
  for (final field in fields) {
    final surface = field.decoration!.color!;
    expect(surface, LightSurfaces.card);
    _expectReadable(tester, find.text(field.placeholder!), surface);
    expect(field.decoration!.border!.top.width, 0.5);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [390.0, 960.0]) {
    testWidgets(
      'server addresses remain readable selected and pressed at $width',
      (tester) async {
        await _pump(tester, const SettingsPage(), width: width);
        await _selectServerCategory(tester, width);
        final active = find.byKey(const ValueKey('server-row-active'));
        await _reveal(tester, active);
        _expectReadable(
          tester,
          find.text('https://active.example.com'),
          LightSurfaces.selection,
        );
        final semantics = tester.ensureSemantics();
        try {
          for (final action in ['edit', 'delete']) {
            final button = find.byKey(ValueKey('server-$action-active'));
            final node = tester.getSemantics(button);
            expect(node.flagsCollection.isButton, isTrue);
            expect(node.label, isNotEmpty);
            final gesture = await tester.startGesture(tester.getCenter(button));
            await tester.pump(const Duration(milliseconds: 200));
            final iconFinder = find.descendant(
              of: button,
              matching: find.byType(Icon),
            );
            final icon = tester.widget<Icon>(iconFinder);
            final ink =
                icon.color ?? IconTheme.of(tester.element(iconFinder)).color!;
            final fade = tester
                .widget<FadeTransition>(
                  find.descendant(
                    of: button,
                    matching: find.byType(FadeTransition),
                  ),
                )
                .opacity
                .value;
            expect(
              _contrast(
                ink.withValues(alpha: ink.a * fade),
                LightSurfaces.selection,
              ),
              greaterThanOrEqualTo(3),
            );
            await gesture.cancel();
            await tester.pumpAndSettle();
          }
        } finally {
          semantics.dispose();
        }
        final other = find.byKey(const ValueKey('server-row-other'));
        await _reveal(tester, other);
        final gesture = await tester.startGesture(tester.getCenter(other));
        await tester.pump(const Duration(milliseconds: 100));
        final box = tester.widget<ColoredBox>(
          find.descendant(of: other, matching: find.byType(ColoredBox)).first,
        );
        _expectReadable(
          tester,
          find.text('https://other.example.com'),
          box.color,
        );
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'all server placeholders and profile chevron are readable at $width',
      (tester) async {
        await _pump(tester, const SettingsPage(), width: width);
        await _selectServerCategory(tester, width);
        final add = find.byKey(const ValueKey('server-add'));
        await _reveal(tester, add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        _expectFieldsReadable(tester, 3);
        final chevron = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const ValueKey('server-editor-profile-tile')),
            matching: find.byIcon(CupertinoIcons.right_chevron),
          ),
        );
        expect(
          _contrast(chevron.color!, LightSurfaces.card),
          greaterThanOrEqualTo(3),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('MCP form placeholders are readable at $width', (tester) async {
      await _pump(tester, const McpServerEditorPage(), width: width);
      _expectFieldsReadable(tester, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('extension form placeholders are readable at $width', (
      tester,
    ) async {
      await _pump(tester, const ExtensionInstallPage(), width: width);
      _expectFieldsReadable(tester, 3);
      expect(tester.takeException(), isNull);
    });
  }

  for (final page in const [
    SettingsPage(),
    McpServerEditorPage(),
    ExtensionInstallPage(),
  ]) {
    testWidgets('${page.runtimeType} fits 320px at 1.5x text scale', (
      tester,
    ) async {
      await _pump(
        tester,
        page,
        width: 320,
        textScaler: const TextScaler.linear(1.5),
      );
      expect(tester.takeException(), isNull);
      if (page is SettingsPage) {
        await tester.drag(
          find.byKey(const ValueKey('settings-scroll')),
          const Offset(0, -800),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'disabled submission stays readable while installation is pending',
    (tester) async {
      final api = _SlowInstallApi();
      await _pump(tester, const ExtensionInstallPage(), api: api);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ExtensionInstallPage)),
      );
      final ready = container.read(extensionsControllerProvider.future);
      await tester.pump();
      await ready;
      await tester.enterText(
        find.byKey(const ValueKey('extension-install-id')),
        'demo',
      );
      final submit = find.byKey(const ValueKey('extension-install-submit'));
      await tester.tap(submit);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<CupertinoButton>(submit).onPressed, isNull);
      _expectReadable(
        tester,
        find.descendant(of: submit, matching: find.byType(Text)),
        LightSurfaces.page,
      );
      api.gate.complete(const ExtensionInstallResponse(ok: false));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'MCP destructive menu and confirmation text meet AA on pressed surfaces',
    (tester) async {
      final api = FakeSettingsApi()
        ..mcpServersResponse = const McpServersResponse(
          servers: [McpServer(name: 'demo', command: 'npx')],
        );
      await _pump(tester, const McpPage(), api: api);
      await tester.tap(find.byKey(const ValueKey('mcp-server-row-demo')));
      await tester.pumpAndSettle();
      final remove = find.byKey(const ValueKey('mcp-delete-demo'));
      final label = find.descendant(of: remove, matching: find.byType(Text));
      // The native translucent sheet can reach this gray when held down.
      _expectReadable(tester, label, const Color(0xFFDADADB));
      await tester.tap(remove);
      await tester.pumpAndSettle();
      final confirmation = find.byKey(const ValueKey('mcp-delete-confirm'));
      _expectReadable(
        tester,
        find.descendant(of: confirmation, matching: find.byType(Text)),
        const Color(0xFFE1E1E1),
      );
      await tester.tap(confirmation);
      await tester.pumpAndSettle();
      expect(api.deleteMcpServerCalls, ['demo']);
    },
  );

  testWidgets(
    'disabled dialog label remains readable after native alpha handling',
    (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => SettingsSurfaces.dialog(
            context,
            const CupertinoAlertDialog(
              title: Text('Pending request'),
              actions: [CupertinoDialogAction(child: Text('Unavailable'))],
            ),
          ),
        ),
      );
      _expectReadable(
        tester,
        find.text('Unavailable'),
        const Color(0xFFF2F2F2),
      );
    },
  );

  for (final status in SidecarStatus.values) {
    testWidgets(
      'sidecar ${status.name} status, metadata and placeholders are readable',
      (tester) async {
        final fs = _SidecarFileSystem();
        when(() => fs.isWindows).thenReturn(true);
        when(() => fs.isBundleAvailable()).thenReturn(true);
        final controller = _SidecarController(
          SidecarState(status: status, pid: 1234),
        );
        await _pump(
          tester,
          const CupertinoPageScaffold(
            child: SingleChildScrollView(child: WebuiSidecarSection()),
          ),
          overrides: [
            sidecarFileSystemProvider.overrideWithValue(fs),
            webuiSidecarConfigProvider.overrideWith(
              _SidecarConfigController.new,
            ),
            webuiSidecarControllerProvider.overrideWith(() => controller),
            agentEnvPresentProvider.overrideWith(_AgentPresentController.new),
          ],
        );
        final statusRow = find.byKey(
          const ValueKey('settings-webui-status-tile'),
        );
        for (final text
            in find
                .descendant(of: statusRow, matching: find.byType(Text))
                .evaluate()) {
          _expectReadable(
            tester,
            find.byWidget(text.widget),
            LightSurfaces.card,
          );
        }
        final password = tester.widget<CupertinoTextField>(
          find.byKey(const ValueKey('settings-webui-password-input')),
        );
        _expectReadable(
          tester,
          find.text(password.placeholder!),
          LightSurfaces.card,
        );
        final toggle = find.byKey(
          const ValueKey('settings-webui-enable-switch'),
        );
        await tester.tap(toggle);
        await tester.pump(const Duration(milliseconds: 300));
        final disabled = tester.widget<CupertinoSwitch>(toggle);
        expect(disabled.onChanged, isNull);
        final fadedTrack = Color.alphaBlend(
          disabled.activeTrackColor!.withValues(alpha: 0.5),
          LightSurfaces.card,
        );
        expect(
          _contrast(fadedTrack, LightSurfaces.card),
          greaterThanOrEqualTo(3),
        );
        controller.startGate.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // 分区卡片结构契约（2026-10-06 本轮）
  //
  // **有意推翻**旧契约「深色下 migrate=true 与 native 逐像素相同」：旧实现里
  // `section()` 对非浅色直接 `return original`，深色因此沿用 base 构造 ——
  // margin 只有 `EdgeInsets.only(bottom: 8)`（零水平边距）、圆角为零、无前景
  // 描边，也就是「深色通栏方角」而浅色是内缩卡片。
  //
  // 新契约：两个主题共用同一套 inset 结构（16/8/16/8 + 圆角 14 + 0.5pt 描边 +
  // 0.5pt 全宽分割线 + 同一套排版令牌），**只有取色**按主题解析；深色走
  // Cupertino 动态语义色，高对比度 / elevated 变体必须保留。
  // ───────────────────────────────────────────────────────────────────────
  for (final contrast in [false, true]) {
    for (final elevated in [false, true]) {
      testWidgets('dark section adopts the inset card structure, high contrast '
          '$contrast elevated $elevated', (tester) async {
        await _pumpSectionHarness(
          tester,
          brightness: Brightness.dark,
          migrate: true,
          contrast: contrast,
          elevated: elevated,
        );

        final section = tester.widget<CupertinoListSection>(
          find.byType(CupertinoListSection),
        );
        // 旧门在此返回 base 构造 → 这三条是「精确变红」的判据。
        expect(section.type, CupertinoListSectionType.insetGrouped);
        expect(section.margin, const EdgeInsets.fromLTRB(16, 8, 16, 8));
        expect(section.dividerMargin, 0.0);
        expect(section.additionalDividerMargin, 0.0);

        final decoration = section.decoration!;
        expect(
          decoration.borderRadius,
          const BorderRadius.all(Radius.circular(14)),
        );
        expect(
          decoration.color!.toARGB32(),
          _expectedDarkCard(contrast, elevated),
        );

        // 0.5pt 前景描边（深色此前完全没有）。
        final stroke = _foregroundStroke(tester);
        expect(stroke.top.width, 0.5);
        expect(
          stroke.top.color.toARGB32(),
          _expectedDarkSeparator(contrast, elevated),
        );

        // 像素取证：卡片左缘之外仍是页底色，卡片内是卡片底 —— 深色不再通栏。
        final card = tester.getRect(_foregroundFinder());
        expect(card.left, 16);
        expect(card.right, 390 - 16);
        final pixels = await _capturePixels(tester);
        expect(
          _pixelAt(pixels, 390, 2, card.center.dy.round()),
          _expectedDarkPage(contrast, elevated),
        );
        expect(
          _pixelAt(pixels, 390, card.left.round() + 20, card.top.round() + 5),
          _expectedDarkCard(contrast, elevated),
        );

        // 推翻的契约本身：迁移后的深色像素**不再**等于 native base 分区。
        await _pumpSectionHarness(
          tester,
          brightness: Brightness.dark,
          migrate: false,
          contrast: contrast,
          elevated: elevated,
        );
        expect(
          await _capturePixels(tester),
          isNot(orderedEquals(pixels)),
          reason: '深色迁移后应与 base 通栏分区不同（旧契约已被有意推翻）',
        );
      });
    }
  }

  testWidgets('light section card stays inset, rounded and bordered', (
    tester,
  ) async {
    await _pumpSectionHarness(
      tester,
      brightness: Brightness.light,
      migrate: true,
    );

    final section = tester.widget<CupertinoListSection>(
      find.byType(CupertinoListSection),
    );
    expect(section.type, CupertinoListSectionType.insetGrouped);
    expect(section.margin, const EdgeInsets.fromLTRB(16, 8, 16, 8));
    final decoration = section.decoration!;
    expect(
      decoration.borderRadius,
      const BorderRadius.all(Radius.circular(14)),
    );
    expect(decoration.color!.toARGB32(), LightSurfaces.card.toARGB32());
    final stroke = _foregroundStroke(tester);
    expect(stroke.top.width, 0.5);
    expect(stroke.top.color.toARGB32(), LightSurfaces.cardBorder.toARGB32());

    // 浅色像素守卫：中缩 16、圆角 14、卡片底/页底色各就各位。
    final card = tester.getRect(_foregroundFinder());
    expect(card.left, 16);
    expect(card.right, 390 - 16);
    final pixels = await _capturePixels(tester);
    int at(int x, int y) => _pixelAt(pixels, 390, x, y);
    final midY = card.center.dy.round();
    expect(at(2, midY), LightSurfaces.page.toARGB32());
    expect(
      at(card.left.round() + 20, card.top.round() + 5),
      LightSurfaces.card.toARGB32(),
    );
    // 圆角过渡：卡角内缩一格仍是页底色，再深一格才落到卡片底。
    expect(
      at(card.left.round() + 1, card.top.round() + 1),
      LightSurfaces.page.toARGB32(),
    );
    expect(
      at(card.left.round() + 7, card.top.round() + 7),
      LightSurfaces.card.toARGB32(),
    );
  });
}

/// 分区卡片工装：`migrate` 决定是否过 [SettingsSurfaces.section]。
///
/// 保留「同一棵树、只切换迁移开关」的对照法（旧契约的取证方式），这样
/// 「深色迁移后 ≠ native」这一推翻结论才有同一基线的可比性。
Future<void> _pumpSectionHarness(
  WidgetTester tester, {
  required Brightness brightness,
  required bool migrate,
  bool contrast = false,
  bool elevated = false,
}) async {
  tester.view.physicalSize = const Size(390, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CupertinoApp(
      theme: buildCupertinoTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 700),
          highContrast: contrast,
        ),
        child: CupertinoUserInterfaceLevel(
          data: elevated
              ? CupertinoUserInterfaceLevelData.elevated
              : CupertinoUserInterfaceLevelData.base,
          child: Builder(
            builder: (context) {
              final toggle = CupertinoSwitch(value: true, onChanged: (_) {});
              final section = CupertinoListSection(
                header: const Text('Settings'),
                children: [
                  CupertinoListTile(
                    title: const Text('Option'),
                    subtitle: const Text('Description'),
                    trailing: migrate
                        ? SettingsSurfaces.toggle(context, toggle)
                        : toggle,
                  ),
                  CupertinoListTile(
                    title: const Text('Input'),
                    trailing: SizedBox(
                      width: 150,
                      child: migrate
                          ? CupertinoTextField(
                              placeholder: 'Placeholder',
                              decoration: SettingsSurfaces.fieldDecoration(
                                context,
                              ),
                              placeholderStyle:
                                  SettingsSurfaces.placeholderStyle(context),
                            )
                          : const CupertinoTextField(
                              placeholder: 'Placeholder',
                            ),
                    ),
                  ),
                ],
              );
              final page = CupertinoPageScaffold(
                child: migrate
                    ? SettingsSurfaces.section(context, section)
                    : section,
              );
              return RepaintBoundary(
                key: const ValueKey('surface-pixels'),
                child: migrate ? SettingsSurfaces.page(context, page) : page,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 抓取工装整页的 raw RGBA 像素。
Future<Uint8List> _capturePixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('surface-pixels')),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

/// 卡片外框的 0.5pt 前景描边（唯一一处 `DecorationPosition.foreground`）。
Finder _foregroundFinder() => find
    .byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.position == DecorationPosition.foreground,
    )
    .first;

Border _foregroundStroke(WidgetTester tester) =>
    (tester.widget<DecoratedBox>(_foregroundFinder()).decoration
                as BoxDecoration)
            .border!
        as Border;

/// raw RGBA 缓冲里 `(x, y)` 处的 ARGB 值。
int _pixelAt(Uint8List bytes, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (bytes[i + 3] << 24) |
      (bytes[i] << 16) |
      (bytes[i + 1] << 8) |
      bytes[i + 2];
}

/// 期望卡片底：SDK `secondarySystemGroupedBackground` 的深色四档
/// （base × base/elevated，各含高对比度变体；取值见 Flutter `cupertino/colors.dart`）。
int _expectedDarkCard(bool contrast, bool elevated) =>
    switch ((contrast, elevated)) {
      (false, false) => 0xFF1C1C1E,
      (true, false) => 0xFF242426,
      (false, true) => 0xFF2C2C2E,
      (true, true) => 0xFF363638,
    };

/// 期望页底色：SDK `systemGroupedBackground` 的深色四档。
int _expectedDarkPage(bool contrast, bool elevated) =>
    switch ((contrast, elevated)) {
      (false, false) => 0xFF000000,
      (true, false) => 0xFF000000,
      (false, true) => 0xFF1C1C1E,
      (true, true) => 0xFF242426,
    };

/// 期望线族色：SDK `separator` 的深色四档（半透明，逐像素断言用 ARGB）。
int _expectedDarkSeparator(bool contrast, bool elevated) =>
    switch ((contrast, elevated)) {
      (false, false) => 0x99545458,
      (true, false) => 0xAD545458,
      (false, true) => 0x99D2D2D2,
      (true, true) => 0xAD545458,
    };
