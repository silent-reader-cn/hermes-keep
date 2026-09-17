# Patch notes for third_party/mermaid_flutter

Vendored from **mermaid_flutter 0.3.0** (published 2026-09-08 — still the
latest release on pub.dev at vendoring time, so there is no upstream fix to
upgrade to). Consumed via `dependency_overrides` in the root `pubspec.yaml`.

## Why this fork exists

`MermaidView`'s on-canvas pan/zoom controls (top-right lock toggle, bottom-right
arrow pad + zoom ± + reset) painted a **hardcoded light-mode palette**: white
fill, `#D9D5E4` border, `#4A4458` glyph. Every one of those values is a `const`
literal and the widget never reads `Theme.of(context)` for them, so the buttons
stayed white in HermesUI regardless of the app theme — visible in dark mode
(white chips floating on the dark fullscreen viewer) and in light mode.

Root cause: the package assumes a **MaterialApp** host — it builds
`Material` / `InkWell` widgets and uses Material `Icons.*` + `Tooltip`.
HermesUI is a Cupertino app, so even a `Theme.of(context)` lookup would resolve
to `ThemeData.fallback()` and always report light. Worse, the app-level
brightness lives in `CupertinoThemeData` (built in `lib/app/app.dart` from
`themeModeProvider`), so `MediaQuery.platformBrightnessOf` would be wrong
whenever the user overrides light/dark in-app.

## 1. `lib/src/mermaid_view.dart` — `_CtlButton`

- Palette now resolves from the ambient brightness:
  `CupertinoTheme.maybeBrightnessOf(context) ?? Theme.of(context).brightness`.
  Cupertino is checked first for the reason above; Material stays as the
  fallback for MaterialApp hosts.
- Dark values are iOS system grays, matching the diagram's own dark theme in
  `lib/features/chat/widgets/mermaid_block.dart` (`kMermaidDarkTheme`):

  | role          | light (byte-identical to upstream) | dark      |
  | ------------- | ---------------------------------- | --------- |
  | fill          | `#FFFFFF`                          | `#2C2C2E` |
  | fill (active) | `#E8E4F6`                          | `#3A3A3C` |
  | border        | `#D9D5E4`                          | `#48484A` |
  | glyph         | `#4A4458`                          | `#F2F2F7` |

- Added `import 'package:flutter/cupertino.dart' show CupertinoTheme;` (scoped,
  so no symbol clash with the existing `material.dart` import).
- Light mode is unchanged: the light branch keeps upstream's exact values.

## 2. `pubspec.yaml`

- Dropped `resolution: workspace` — that line only applies to the upstream pub
  workspace monorepo and breaks path-based consumption from this repo.
- Dropped the `screenshots:` block — those nine entries point at
  `doc/screenshots/*.png`, which are pub.dev store-page assets and are not
  vendored here. Left in place they produce ten `path_does_not_exist` warnings
  in this repo's `flutter analyze` run (which must stay at zero warnings).

## 3. `lib/src/mermaid_view.dart` — `_openFullscreen`

- The dialog future is now discarded explicitly with `unawaited(...)`. The
  call was already fire-and-forget; the change only silences this repo's
  `discarded_futures` lint, which also runs over vendored path dependencies
  (`flutter analyze` must report zero issues, info included).
- `dart:async` was already imported, so no new dependency.

## Not patched (known, deliberately out of scope)

- The controls are still Material widgets (`Material` + `InkWell` + Material
  icons + `Tooltip`). Replacing them with Cupertino equivalents would let the
  fullscreen viewer drop its last Material dependency, but it is a larger
  interaction/visual change — left for a separate pass.
- `MermaidView._openFullscreen()` builds a Material `Dialog`. HermesUI never
  reaches it: the viewer passes `allowFullscreen: false`.

## Removal criteria

Drop this override — and delete this directory — when upstream exposes a theme
hook for the controls or ships adaptive colors. Check
<https://pub.dev/packages/mermaid_flutter> first; revisit on every dependency
upgrade.

## Guards

`test/features/chat/mermaid_theme_test.dart` asserts the resolved colors and
WCAG contrast floors in both brightnesses (RED-verified: reverting either this
patch or the viewer's background turns the suite red).
