# Branch PRD - `palette-color-wheel`

Read `PRD.md` first. This file contains only branch-specific state for
`palette-color-wheel`.

## Branch Scope

`palette-color-wheel` is the rendered text color branch. It should preserve
color UI, color metadata, and colored rendering while pulling non-color core
fixes from `master`.

Do not let merges from `master` remove color behavior unless the branch is
intentionally being retired.

## Color Responsibilities

This branch owns:

- rendered text color UI
- color-wheel/color-panel behavior
- rendered text color metadata
- renderer color parameters
- rendering annotations with stored/current color
- color preservation across edit, resize, save, reopen, copy, cut, paste, and
  undo/redo flows

Expected behavior with the synced `master` selection model:

- Font-size changes apply to all selected annotations, matching `master`.
- Color changes apply to all selected annotations.
- If selected annotations have mismatched font sizes or colors, the next
  explicit adjustment is a unified assignment to all selected annotations.
- Resizing must never change rendered text color.
- Raw editor text is always fixed Menlo with white foreground on the dark editor
  background; rendered color choices must not restyle the editor source text.
- Rendered text color is canonical clamped sRGB throughout UI state, annotation
  metadata, CoreText fallback rendering, and MathJax image tinting.
- `/AnnoTexTextColor` remains the exact persisted `#RRGGBB` source of truth for
  rendered color and must be preserved across resize, save, reopen, clipboard
  payloads, and undo state snapshots.
- The editor color picker remembers the last explicitly chosen rendered color
  for new annotations, and typing in the editor must not push the color panel
  selection back to white.
- The editor keeps visible source text white while keeping the text view's
  typing/color-panel foreground synchronized to the rendered color.

## Master Sync Notes

Core non-color fixes should be pulled or cherry-picked from `master`. When
porting, preserve color metadata and renderer color parameters. Resolve
conflicts in favor of keeping this branch's extra color behavior.

The current `master` selection overhaul is part of this branch after the
master sync:

- selected-annotation set plus primary annotation
- centralized selection mutation
- Shift-click multi-selection
- multi-drag
- Delete all selected annotations
- font-size assignment to all selected annotations
- live AppKit overlay selection chrome hosted inside PDFKit's `documentView`
- private annotation clipboard payloads
- context-menu and keyboard copy/cut/paste
- collision-aware paste placement
- undo/redo for add, paste, cut, delete, move, resize, edit, and font-size
  changes

Known issues `MATH-001`, `MATH-002`, and `MATH-003` in `PRD.md` are synced into
this branch after the latest master merge. Future renderer syncs should keep
color rendering parameters threaded through the master renderer changes.

## Color Regression Checklist

Manually verify after color changes or after syncing core selection/rendering
work:

- New annotation uses current selected color.
- Existing annotation opens editor with stored color.
- Render from editor preserves selected color.
- Resize preserves color.
- Copy/cut/paste preserves color for single annotations and multi-selection
  groups.
- Undo/redo of add, paste, cut, delete, move, resize, edit, and font-size
  operations preserves color.
- Save and reopen preserves color.
- Non-AnnoTex PDF readers display colored annotation appearances.
- Multi-selected color adjustment applies to every selected annotation.
- Math rendering fixes from `master` still honor the selected/stored rendered
  text color.

## Verification

Use the palette derived data path for full checks:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

For small UI iterations, prefer `git diff --check` plus source inspection unless
the user asks for full `xcodebuild`.

## Handoff Prompt

```text
Read PRD.md and PRD.palette-color-wheel.md. Continue work on palette-color-wheel. Preserve rendered color functionality while pulling in non-color core fixes from master as needed.
```
