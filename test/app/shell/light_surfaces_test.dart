import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/empty_detail_pane.dart';
import 'package:hermes_ui/app/shell/sidebar_resize_handle.dart';
import 'package:hermes_ui/app/shell/sidebar_utility_toolbar.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/widgets/adaptive_action_menu.dart';
import 'package:hermes_ui/app/widgets/narrow_navigation_dropdown.dart';
import 'package:hermes_ui/app/widgets/popover_dropdown.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/widgets/message_action_menu.dart';
import 'package:hermes_ui/features/shared/app_back_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/contrast_utils.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required WidgetBuilder builder,
  double width = 1280,
  bool highContrast = false,
  CupertinoUserInterfaceLevelData level = CupertinoUserInterfaceLevelData.base,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: highContrast),
            child: CupertinoUserInterfaceLevel(
              data: level,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      for (final level in CupertinoUserInterfaceLevelData.values) {
        testWidgets(
          'shell $brightness hc=$highContrast $level uses actual surfaces',
          (tester) async {
            await _pump(
              tester,
              brightness: brightness,
              highContrast: highContrast,
              level: level,
              builder: (_) => CupertinoPageScaffold(
                child: Row(
                  children: [
                    const SizedBox(
                      width: 320,
                      child: Column(
                        children: [
                          SidebarUtilityToolbar(currentLocation: '/settings'),
                          Row(
                            children: [
                              AppBackButton(),
                              NarrowNavigationDropdownButton(),
                            ],
                          ),
                          PopoverDropdownCard(child: Text('Dropdown content')),
                        ],
                      ),
                    ),
                    SidebarResizeHandle(onDragUpdate: (_) {}),
                    const Expanded(child: EmptyDetailPane()),
                  ],
                ),
              ),
            );
            final inactiveFinder = find.byIcon(CupertinoIcons.clock);
            final context = tester.element(inactiveFinder);
            final inactive = tester.widget<Icon>(inactiveFinder);
            final selected = tester.widget<Icon>(
              find.byIcon(CupertinoIcons.gear_alt),
            );
            final pane = tester.widget<CupertinoPageScaffold>(
              find.descendant(
                of: find.byType(EmptyDetailPane),
                matching: find.byType(CupertinoPageScaffold),
              ),
            );
            final subtitle = tester
                .widgetList<Text>(
                  find.descendant(
                    of: find.byType(EmptyDetailPane),
                    matching: find.byType(Text),
                  ),
                )
                .singleWhere((text) => text.style?.fontSize == 14);
            final emptyIcon = tester.widget<Icon>(
              find.byIcon(CupertinoIcons.chat_bubble_2),
            );
            final createButton = tester.widget<CupertinoButton>(
              find.byKey(const ValueKey('empty-detail-new-chat-button')),
            );
            final divider = tester.widget<Container>(
              find.descendant(
                of: find.byType(SidebarResizeHandle),
                matching: find.byType(Container),
              ),
            );
            final dropdown =
                tester
                        .widget<Container>(
                          find
                              .descendant(
                                of: find.byType(PopoverDropdownCard),
                                matching: find.byType(Container),
                              )
                              .first,
                        )
                        .decoration!
                    as BoxDecoration;
            if (brightness == Brightness.light) {
              expect(
                contrastRatio(inactive.color!, LightSurfaces.page),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                contrastRatio(selected.color!, LightSurfaces.selection),
                greaterThanOrEqualTo(3),
              );
              expect(pane.backgroundColor, LightSurfaces.card);
              expect(
                contrastRatio(subtitle.style!.color!, pane.backgroundColor!),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                contrastRatio(emptyIcon.color!, pane.backgroundColor!),
                greaterThanOrEqualTo(3),
              );
              expect(
                contrastRatio(CupertinoColors.white, createButton.color!),
                greaterThanOrEqualTo(4.5),
              );
              expect(divider.color, LightSurfaces.divider);
              expect(dropdown.color, LightSurfaces.card);
              expect(
                dropdown.border,
                Border.all(color: LightSurfaces.cardBorder),
              );
            } else {
              expect(
                inactive.color!.toARGB32(),
                CupertinoColors.secondaryLabel.resolveFrom(context).toARGB32(),
              );
              expect(selected.color, CupertinoTheme.of(context).primaryColor);
              expect(
                pane.backgroundColor,
                CupertinoTheme.of(context).scaffoldBackgroundColor,
              );
              expect(
                subtitle.style!.color!.toARGB32(),
                CupertinoColors.secondaryLabel.resolveFrom(context).toARGB32(),
              );
              expect(
                emptyIcon.color!.toARGB32(),
                CupertinoColors.tertiaryLabel.resolveFrom(context).toARGB32(),
              );
              expect(createButton.color, isNull);
              expect(
                divider.color!.toARGB32(),
                CupertinoColors.separator.resolveFrom(context).toARGB32(),
              );
              expect(
                dropdown.color!.toARGB32(),
                CupertinoColors.systemBackground
                    .resolveFrom(context)
                    .toARGB32(),
              );
              expect(
                (dropdown.border! as Border).top.color.toARGB32(),
                CupertinoColors.separator.resolveFrom(context).toARGB32(),
              );
            }
            for (final icon in [
              CupertinoIcons.chevron_left,
              CupertinoIcons.chevron_down,
            ]) {
              final iconContext = tester.element(find.byIcon(icon));
              final inherited = IconTheme.of(iconContext).color!;
              if (brightness == Brightness.light) {
                expect(
                  contrastRatio(
                    inherited,
                    CupertinoTheme.of(iconContext).scaffoldBackgroundColor,
                  ),
                  greaterThanOrEqualTo(3),
                );
              } else {
                expect(inherited, CupertinoTheme.of(iconContext).primaryColor);
              }
            }
            await _unmount(tester);
          },
        );
      }
    }
    for (final width in [390.0, 1280.0]) {
      final isWide = width >= 900;
      testWidgets(
        'menu $brightness width=$width preserves actions and pressed contrast',
        (tester) async {
          final anchor = GlobalKey();
          var ordinaryCalls = 0;
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  key: anchor,
                  onPressed: () => unawaited(
                    AdaptiveActionMenu.show(
                      context,
                      anchorKey: anchor,
                      title: 'Menu title',
                      cancelLabel: 'Cancel',
                      items: [
                        AdaptiveMenuItem(
                          label: 'Ordinary action',
                          onPressed: () => ordinaryCalls++,
                        ),
                        AdaptiveMenuItem(
                          label: 'Default action',
                          isDefault: true,
                          onPressed: () {},
                        ),
                        AdaptiveMenuItem(
                          label: 'Delete action',
                          isDestructive: true,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open menu'),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(anchor));
          await tester.pumpAndSettle();
          for (final label in [
            'Ordinary action',
            'Default action',
            'Delete action',
          ]) {
            final text = tester.widget<Text>(find.text(label));
            final context = tester.element(find.text(label));
            if (brightness == Brightness.light) {
              final color = text.style!.color!;
              final backdrop = isWide
                  ? LightSurfaces.card
                  : compositeOver(
                      const Color(0xC8FCFCFC),
                      compositeOver(
                        const Color(0x33000000),
                        LightSurfaces.page,
                      ),
                    );
              expect(
                contrastRatio(color, backdrop),
                greaterThanOrEqualTo(4.5),
                reason: label,
              );
            } else if (isWide) {
              final expected = label == 'Delete action'
                  ? CupertinoColors.destructiveRed
                  : label == 'Default action'
                  ? CupertinoColors.activeBlue
                  : CupertinoColors.label;
              expect(
                text.style!.color!.toARGB32(),
                expected.resolveFrom(context).toARGB32(),
              );
            } else {
              expect(text.style, isNull);
            }
          }
          if (isWide) {
            final surface = tester
                .widgetList<Container>(
                  find.ancestor(
                    of: find.text('Default action'),
                    matching: find.byType(Container),
                  ),
                )
                .map((container) => container.decoration)
                .whereType<BoxDecoration>()
                .firstWhere(
                  (decoration) =>
                      decoration.borderRadius == BorderRadius.circular(14),
                );
            final context = tester.element(find.text('Default action'));
            expect(
              surface.color!.toARGB32(),
              brightness == Brightness.light
                  ? LightSurfaces.card.toARGB32()
                  : CupertinoColors.systemBackground
                        .resolveFrom(context)
                        .toARGB32(),
            );
            expect(
              (surface.border! as Border).top.color.toARGB32(),
              brightness == Brightness.light
                  ? LightSurfaces.cardBorder.toARGB32()
                  : CupertinoColors.systemGrey4.resolveFrom(context).toARGB32(),
            );
          }
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('Default action')),
          );
          await tester.pump(const Duration(milliseconds: 200));
          if (brightness == Brightness.light) {
            final text = tester.widget<Text>(find.text('Default action'));
            final pressed = isWide
                ? tester
                      .widget<ColoredBox>(
                        find
                            .ancestor(
                              of: find.text('Default action'),
                              matching: find.byType(ColoredBox),
                            )
                            .first,
                      )
                      .color
                : compositeOver(
                    const Color(0xCAE0E0E0),
                    compositeOver(const Color(0x33000000), LightSurfaces.page),
                  );
            expect(
              contrastRatio(text.style!.color!, pressed),
              greaterThanOrEqualTo(4.5),
            );
            if (isWide) expect(pressed, LightSurfaces.pressed);
          }
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(ordinaryCalls, 0);
          await tester.tap(find.text('Ordinary action'));
          await tester.pumpAndSettle();
          expect(ordinaryCalls, 1);
          expect(find.text('Menu title'), findsNothing);
          await _unmount(tester);
        },
      );
      testWidgets(
        'empty-message menu $brightness width=$width keeps disabled text readable',
        (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  onPressed: () => unawaited(
                    showMessageActionMenu(
                      context,
                      message: const ChatMessage(
                        role: 'assistant',
                        content: '',
                      ),
                      position: isWide ? const Offset(200, 200) : null,
                    ),
                  ),
                  child: const Text('Open message'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open message'));
          await tester.pumpAndSettle();
          final copy = find.byKey(const ValueKey('msg-action-copy'));
          final text = tester.widget<Text>(
            find.descendant(of: copy, matching: find.byType(Text)).first,
          );
          final context = tester.element(copy);
          if (brightness == Brightness.light) {
            final background = isWide
                ? LightSurfaces.card
                : compositeOver(
                    const Color(0xC8FCFCFC),
                    compositeOver(const Color(0x33000000), LightSurfaces.page),
                  );
            expect(
              contrastRatio(text.style!.color!, background),
              greaterThanOrEqualTo(4.5),
            );
            if (isWide) {
              final tile = tester.widget<CupertinoListTile>(
                find.descendant(
                  of: copy,
                  matching: find.byType(CupertinoListTile),
                ),
              );
              expect(tile.onTap, isNull);
            }
          } else if (isWide) {
            expect(
              text.style!.color!.toARGB32(),
              CupertinoColors.placeholderText.resolveFrom(context).toARGB32(),
            );
          } else {
            expect(text.style, isNull);
          }
          await _unmount(tester);
        },
      );
    }
  }
}
