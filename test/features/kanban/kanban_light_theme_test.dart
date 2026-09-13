import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/kanban.dart';
import 'package:hermes_ui/features/kanban/kanban_page.dart';
import 'package:hermes_ui/features/kanban/kanban_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_kanban_api.dart';

const _card = KanbanCard(
  cardID: 'first',
  title: 'First card',
  status: KanbanStatus('todo'),
  assignee: 'owner',
  linkCounts: KanbanLinkCounts(parents: 2),
);

FakeKanbanApi _api() => FakeKanbanApi(
  boards: const [
    KanbanBoard(slug: 'main', name: 'Main board'),
    KanbanBoard(slug: 'other', name: 'Other board'),
  ],
  currentSlug: 'main',
  snapshots: const {
    'main': KanbanBoardSnapshot(
      columns: [
        KanbanColumn(name: 'todo', cards: [_card]),
        KanbanColumn(name: 'ready', cards: []),
      ],
    ),
    'other': KanbanBoardSnapshot(
      columns: [
        KanbanColumn(name: 'todo', cards: [_card]),
      ],
    ),
  },
  details: {'first': const KanbanCardDetailEnvelope(card: _card, comments: [])},
);

Future<FakeKanbanApi> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  Widget page = const KanbanPage(),
}) async {
  final api = _api();
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    api.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://test.local'),
        ),
        kanbanApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: page is KanbanCardDetailPage ? const KanbanPage() : page,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  if (page is KanbanCardDetailPage) {
    await tester.tap(find.byKey(ValueKey('kanban-card-${page.cardId}')));
    await tester.pumpAndSettle();
  }
  return api;
}

BoxDecoration _cardDecoration(WidgetTester tester) {
  final card = find.byKey(const ValueKey('kanban-card-first'));
  final surface = find.descendant(
    of: card,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.padding == const EdgeInsets.all(12) &&
          widget.decoration is BoxDecoration,
    ),
  );
  return tester.widget<Container>(surface).decoration! as BoxDecoration;
}

double _contrast(Color foreground, Color background) {
  final ink = Color.alphaBlend(foreground, background).computeLuminance();
  final surface = background.computeLuminance();
  return ink > surface
      ? (ink + 0.05) / (surface + 0.05)
      : (surface + 0.05) / (ink + 0.05);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('status ink meets AA and every original dark variant is preserved', () {
    const original = <String?, CupertinoDynamicColor>{
      'triage': statusGreyText,
      'todo': statusBlueText,
      'ready': statusTealText,
      'running': statusOrangeText,
      'blocked': CupertinoColors.systemRed,
      'done': statusGreenText,
      'archived': secondaryText,
      'unexpected': CupertinoColors.systemPurple,
      null: CupertinoColors.systemPurple,
    };
    for (final entry in original.entries) {
      final color = kanbanStatusColor(entry.key);
      for (final ink in [
        color.color,
        color.highContrastColor,
        color.elevatedColor,
        color.highContrastElevatedColor,
      ]) {
        for (final surface in [LightSurfaces.page, LightSurfaces.card]) {
          expect(
            _contrast(ink, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} on $surface',
          );
        }
      }
      expect(color.darkColor, entry.value.darkColor, reason: entry.key);
      expect(
        color.darkHighContrastColor,
        entry.value.darkHighContrastColor,
        reason: entry.key,
      );
      expect(
        color.darkElevatedColor,
        entry.value.darkElevatedColor,
        reason: entry.key,
      );
      expect(
        color.darkHighContrastElevatedColor,
        entry.value.darkHighContrastElevatedColor,
        reason: entry.key,
      );
    }
  });

  testWidgets('dark board exposes three surfaces and readable dependencies', (
    tester,
  ) async {
    await _pump(tester, brightness: Brightness.dark);
    final card = find.byKey(const ValueKey('kanban-card-first'));
    final context = tester.element(card);
    expect(
      CupertinoTheme.of(context).scaffoldBackgroundColor,
      CupertinoColors.black,
    );
    final surfaces = <Color>[];
    for (final target in find.byType(DragTarget<KanbanCard>).evaluate()) {
      final panel = find
          .ancestor(
            of: find.byWidget(target.widget),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          )
          .first;
      final decoration =
          tester.widget<Container>(panel).decoration! as BoxDecoration;
      surfaces.add(decoration.color!);
      expect(decoration.color!.computeLuminance(), greaterThan(0));
      expect(
        decoration.color!.computeLuminance(),
        lessThan(_cardDecoration(tester).color!.computeLuminance()),
      );
      if (target == find.byType(DragTarget<KanbanCard>).evaluate().first) {
        expect(
          tester.getRect(card).left,
          greaterThan(tester.getRect(panel).left),
        );
        expect(
          tester.getRect(card).right,
          lessThan(tester.getRect(panel).right),
        );
      }
    }
    expect(surfaces, hasLength(2));
    expect(surfaces[0], surfaces[1]);
    final link = find.byIcon(CupertinoIcons.link);
    final badge = find
        .ancestor(of: link, matching: find.byType(Container))
        .first;
    final fill =
        (tester.widget<Container>(badge).decoration! as BoxDecoration).color!;
    final icon = tester.widget<Icon>(link).color!;
    expect(
      icon,
      CupertinoColors.systemYellow.resolveFrom(tester.element(link)),
    );
    expect(_contrast(icon, fill), greaterThanOrEqualTo(3));
    expect(_contrast(icon, fill), closeTo(7.39, 0.01));
    final label = tester.widget<Text>(
      find.descendant(of: badge, matching: find.byType(Text)),
    );
    expect(_contrast(label.style!.color!, fill), greaterThanOrEqualTo(4.5));
  });

  for (final brightness in Brightness.values) {
    final light = brightness == Brightness.light;

    testWidgets('card surface and press feedback ${brightness.name}', (
      tester,
    ) async {
      await _pump(tester, brightness: brightness);
      final card = find.byKey(const ValueKey('kanban-card-first'));
      final context = tester.element(card);
      final originalSurface = CupertinoColors.secondarySystemBackground
          .resolveFrom(context);
      final resting = _cardDecoration(tester);
      expect(resting.color, light ? LightSurfaces.card : originalSurface);
      expect(
        (resting.border! as Border).top.color,
        light
            ? LightSurfaces.cardBorder
            : const Color(0xFF3A3A3C),
      );
      expect(
        tester.widget<Text>(find.text('owner')).style!.color,
        light
            ? LightSurfaces.textSecondary
            : secondaryText.resolveFrom(context),
      );
      final button = tester.widget<CupertinoButton>(card);
      expect(button.pressedOpacity, light ? 1 : 0.4);
      final size = tester.getSize(card);
      final pointer = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _cardDecoration(tester).color,
        light ? LightSurfaces.pressed : originalSurface,
      );
      expect(tester.getSize(card), size);
      if (light) {
        expect(
          _contrast(
            LightSurfaces.textSecondary,
            _cardDecoration(tester).color!,
          ),
          greaterThanOrEqualTo(4.5),
        );
      }
      await pointer.cancel();
      await tester.pumpAndSettle();
      expect(_cardDecoration(tester).color, resting.color);
    });

    testWidgets('board selection and native dark fill ${brightness.name}', (
      tester,
    ) async {
      final api = await _pump(tester, brightness: brightness);
      final selected = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('kanban-board-main')),
      );
      final otherFinder = find.byKey(const ValueKey('kanban-board-other'));
      final other = tester.widget<CupertinoButton>(otherFinder);
      expect(selected.onPressed, isNull);
      expect(
        selected.disabledColor,
        light ? LightSurfaces.selection : CupertinoColors.transparent,
      );
      if (!light) {
        final context = tester.element(otherFinder);
        final selectedSurface = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('kanban-board-main')),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final selectedFill =
            (selectedSurface.decoration as BoxDecoration).color!;
        expect(selectedFill, CupertinoColors.activeBlue.resolveFrom(context));
        expect(
          _contrast((selected.child as Text).style!.color!, selectedFill),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          (other.child as Text).style!.color,
          CupertinoColors.label.resolveFrom(context),
        );
        expect(
          _contrast((other.child as Text).style!.color!, other.color!),
          greaterThanOrEqualTo(4.5),
        );
        final outline = tester.widget<DecoratedBox>(
          find
              .ancestor(of: otherFinder, matching: find.byType(DecoratedBox))
              .first,
        );
        expect(
          ((outline.decoration as BoxDecoration).border! as Border).top.color,
          const Color(0xFF3A3A3C),
        );
      }
      // Dark chips use an opaque fill and keep selected activeBlue visible.
      expect(
        other.color,
        light ? LightSurfaces.card : const Color(0xFF2C2C2E),
      );
      final pointer = await tester.startGesture(tester.getCenter(otherFinder));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<CupertinoButton>(otherFinder).color,
        light ? LightSurfaces.pressed : const Color(0xFF2C2C2E),
      );
      await pointer.up();
      await tester.pumpAndSettle();
      expect(api.makeBoardActiveCalls, ['other']);
      expect(tester.widget<CupertinoButton>(otherFinder).onPressed, isNull);
    });

    testWidgets('detail panels and status action contrast ${brightness.name}', (
      tester,
    ) async {
      await _pump(
        tester,
        brightness: brightness,
        page: const KanbanCardDetailPage(cardId: 'first'),
      );
      final sections = tester.widgetList<CupertinoListSection>(
        find.byType(CupertinoListSection),
      );
      expect(sections.length, 4);
      for (final section in sections) {
        if (light) {
          expect(section.decoration!.color, LightSurfaces.card);
          expect(
            (section.decoration!.border! as Border).top.color,
            LightSurfaces.cardBorder,
          );
          expect(section.separatorColor, LightSurfaces.divider);
        } else {
          expect(section.decoration, isNull);
          expect(section.separatorColor, isNull);
        }
      }
      final actionFinder = find.byKey(const ValueKey('kanban-status-ready'));
      final action = tester.widget<CupertinoButton>(actionFinder);
      if (light) {
        expect(
          _contrast(action.foregroundColor!, action.color!),
          greaterThanOrEqualTo(4.5),
        );
        final pointer = await tester.startGesture(
          tester.getCenter(actionFinder),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final pressed = tester.widget<CupertinoButton>(actionFinder);
        expect(pressed.color, LightSurfaces.pressed);
        expect(
          _contrast(pressed.foregroundColor!, pressed.color!),
          greaterThanOrEqualTo(4.5),
        );
        await pointer.cancel();
        await tester.pumpAndSettle();
      } else {
        expect(action.color, const Color(0xFF111113));
        expect(action.foregroundColor, isNull);
        final actionText = find.descendant(
          of: actionFinder,
          matching: find.byType(Text),
        );
        expect(
          _contrast(
            DefaultTextStyle.of(tester.element(actionText)).style.color!,
            action.color!,
          ),
          greaterThanOrEqualTo(4.5),
        );
      }
      final input = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('kanban-comment-input')),
      );
      expect(
        input.placeholderStyle,
        light
            ? const TextStyle(
                fontWeight: FontWeight.w400,
                color: LightSurfaces.placeholder,
              )
            : const CupertinoTextField().placeholderStyle,
      );
      if (!light) {
        expect(input.decoration, const CupertinoTextField().decoration);
      }
    });

    testWidgets('card dragging still changes status ${brightness.name}', (
      tester,
    ) async {
      final api = await _pump(tester, brightness: brightness);
      final card = find.byKey(const ValueKey('kanban-card-first'));
      final pointer = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 600));
      final target = find.byType(DragTarget<KanbanCard>).at(1);
      await pointer.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 100));
      await pointer.up();
      await tester.pumpAndSettle();
      expect(api.lastSetStatusCall, 'first:ready');
      expect(tester.takeException(), isNull);
    });

    testWidgets('create fields preserve dark defaults ${brightness.name}', (
      tester,
    ) async {
      await _pump(
        tester,
        brightness: brightness,
        page: const KanbanCreateCardPage(),
      );
      for (final field in tester.widgetList<CupertinoTextField>(
        find.byType(CupertinoTextField),
      )) {
        if (light) {
          expect(field.decoration!.color, LightSurfaces.card);
          expect(field.placeholderStyle!.color, LightSurfaces.placeholder);
          expect(
            (field.decoration!.border! as Border).top.color,
            LightSurfaces.cardBorder,
          );
          expect(
            _contrast(field.placeholderStyle!.color!, field.decoration!.color!),
            greaterThanOrEqualTo(4.5),
          );
        } else {
          expect(field.decoration, const CupertinoTextField().decoration);
          expect(
            field.placeholderStyle,
            const CupertinoTextField().placeholderStyle,
          );
        }
      }
      final nav = tester.widget<CupertinoNavigationBar>(
        find.byType(CupertinoNavigationBar),
      );
      expect(
        nav.border,
        light
            ? const Border(
                bottom: BorderSide(color: LightSurfaces.divider, width: 0),
              )
            : const CupertinoNavigationBar().border,
      );
      final control = tester.widget<CupertinoSlidingSegmentedControl<String>>(
        find.byType(CupertinoSlidingSegmentedControl<String>),
      );
      if (light) {
        expect(control.backgroundColor, LightSurfaces.card);
        expect(control.thumbColor, LightSurfaces.selection);
      } else {
        expect(control.backgroundColor, const Color(0xFF2C2C2E));
        final outline = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.byType(CupertinoSlidingSegmentedControl<String>),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
          ((outline.decoration as BoxDecoration).border! as Border).top.color,
          const Color(0xFF3A3A3C),
        );
      }
      await tester.enterText(
        find.byKey(const ValueKey('kanban-form-title')),
        'New card',
      );
      await tester.pump();
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('kanban-form-save')),
            )
            .onPressed,
        isNotNull,
      );
    });
  }
}
