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

  for (final contrast in [false, true]) {
    for (final elevated in [false, true]) {
      testWidgets(
        'dark controls match native pixels, high contrast $contrast elevated $elevated',
        (tester) async {
          tester.view.physicalSize = const Size(390, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          Future<Uint8List> render(bool migrate) async {
            await tester.pumpWidget(
              CupertinoApp(
                theme: buildCupertinoTheme(Brightness.dark),
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
                        final toggle = CupertinoSwitch(
                          value: true,
                          onChanged: (_) {},
                        );
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
                                        decoration:
                                            SettingsSurfaces.fieldDecoration(
                                              context,
                                            ),
                                        placeholderStyle:
                                            SettingsSurfaces.placeholderStyle(
                                              context,
                                            ),
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
                          key: const ValueKey('dark-pixels'),
                          child: migrate
                              ? SettingsSurfaces.page(context, page)
                              : page,
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('dark-pixels')),
            );
            return (await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              image.dispose();
              return data!.buffer.asUint8List();
            }))!;
          }

          final native = await render(false);
          final migrated = await render(true);
          expect(migrated, orderedEquals(native));
        },
      );
    }
  }
}
