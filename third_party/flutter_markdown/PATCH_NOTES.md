# Patch notes for third_party/flutter_markdown_patched
#
# Vendored from flutter_markdown 0.7.7+1 (discontinued upstream;
# pub.dev points to flutter_markdown_plus which we deliberately do
# not adopt this cycle to keep the diff minimal).
#
# Root cause of "Bad state: Too many elements" (crash dialog when
# previewing README files with badge images [![x](y)](z)):
# MarkdownBuilder._addAnonymousBlockIfNeeded() used `_inlines.single`,
# which throws when a link-wrapped block-level image leaves more than
# one inline element on the stack at flush time (p > a > img).

## 1. lib/src/builder.dart
- `_addAnonymousBlockIfNeeded`: merge ALL accumulated inline elements
  into one block (children of every `_InlineElement` in order) instead
  of asserting exactly one.
- `visitElementAfter` inline unwind: skip the pop when the inline stack
  is already empty (link `a` unwinds after the img builder already
  dropped its own inline).

## 2. lib/src/widget.dart
- `_parseMarkdown` wraps `builder.build(astNodes)` in try/catch:
  any builder crash now degrades to a plain-text build of the source
  (second parse attempt) instead of surfacing a widgets-library
  exception to the global error dialog. Recognizers created during the
  failed attempt are disposed before fallback.

## 3. lib/src/builder.dart (block-tag scoping)
- The package-global `_kBlockTags` list was mutated by
  `build()` (builder registrations appended, never removed). The first
  MarkdownBody that registered `img` as a block element permanently
  changed block semantics for every later MarkdownBody in the process
  (e.g. file-preview/memory pages silently lost default inline img
  rendering). Block tags are now a per-builder list initialised from
  `_kDefaultBlockTags` and rebuilt on each `build()`.

## 4. contextMenuBuilder passthrough (#81 double right-click menu)
On Windows/Linux a right-click on `SelectableText` always toggles the
native text-selection toolbar (a lone "Select all" entry when there is
no selection). In the chat window this stacked on top of the custom
message context menu, producing two menus from one right-click.

- `lib/src/widget.dart`: `MarkdownWidget` gains an optional
  `contextMenuBuilder` (`EditableTextContextMenuBuilder?`, forwarded to
  `MarkdownBuilder`; `MarkdownBody` / `Markdown` expose it via
  `super.contextMenuBuilder`).
- `lib/src/builder.dart`: `MarkdownBuilder` stores it and, in
  `_buildRichText`, passes it to `SelectableText.rich` **only when
  non-null** (upstream default preserved otherwise; a null explicit
  pass-through would fall back to the legacy controls path).
- `lib/src/builder.dart`: `onSelectionChanged` callback passes
  `text.toPlainText()` instead of `text.text` (`text.text` is null when
  paragraphs contain child spans like bold, code, or links, which left
  the callback receiving null).

Hosts that want to suppress/replace the native selection toolbar pass
their own builder (see `lib/features/chat/widgets/chat_text_selection.dart`).

## Regression tests
- test/features/chat/widgets/markdown_image_link_crash_test.dart
- test/features/chat/message_context_menu_native_toolbar_test.dart (#81;
  baseline without the fix renders the native toolbar with "Select all")

Patch author: hermes-ui maintainers, 2026-09-07; section 4 added 2026-09-13.
