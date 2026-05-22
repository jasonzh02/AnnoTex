# Branch PRD - `master`

Read `PRD.md` first. This file contains only compact active-branch state for
`master`.

## Branch Scope

`master` is the active core branch. It contains PDF viewing/saving, editable
annotations, MathJax rendering, mixed text/math layout, rendered text color,
selection behavior, annotation clipboard operations, keyboard shortcuts, and
the basic editor workflow.

Use short-lived feature branches for substantial future work. See
`PRD.md` -> `Future Features And Implementation Plan` for branch names and
implementation guidance.

## Current Core Behavior

- Open PDFs, add annotations, edit source in a floating dark editor panel, and
  render with the button or `Command+Enter`.
- Rendered annotation font size and rendered color are adjustable from the
  toolbar when annotations are selected.
- Save writes portable visible appearances while preserving AnnoTex metadata for
  re-editability.
- Single-click selects one annotation; Shift-click toggles multi-selection.
- Multiple selected annotations drag together.
- Delete/Forward Delete deletes all selected annotations.
- Right-clicking an annotation opens Copy/Cut/Delete actions. Right-clicking
  blank PDF space opens Paste, disabled when no AnnoTex annotation payload is on
  the clipboard.
- `Command+C`, `Command+X`, `Command+V`, `Command+Z`, and `Shift+Command+Z`
  support annotation copy, cut, paste, undo, and redo.
- Paste placement is collision-aware: it tries the requested center first,
  cascades nearby when existing annotations occupy that spot, and preserves
  multi-annotation relative offsets.
- Clipboard payloads and undo state snapshots preserve source, bounds, font
  size, and rendered color.

## Selection State

Selection is intentionally PDF editor-style chrome:

- Selection state lives in `MathPDFView` as a selected-annotation set plus a
  primary annotation.
- Selection mutation is centralized in `MathPDFView.setSelectedAnnotations`.
- Right-click selection follows editor conventions: an unselected clicked
  annotation becomes the only selection, while right-clicking inside an existing
  multi-selection keeps that selected set.
- `LaTeXAnnotation.draw` draws only rendered annotation content.
- Selection border/handles are drawn by `SelectionOverlayView`.
- The overlay is hosted inside PDFKit's `documentView`, not directly on
  `PDFView`, so it moves with PDF content during scroll and zoom.
- The overlay invalidates on selection changes, drag/resize, visible-page
  changes, scroll clip-view bounds changes, and rerender completion.
- PDFKit is still notified with `annotationsChanged(on:)` when annotation
  content/state changes, but selected-border drawing must not depend on PDFKit
  annotation/page rendering.

Reason: drawing selection inside `PDFAnnotation.draw` or `PDFView.drawPagePost`
caused stale or lagging borders because PDFKit caches and schedules page and
annotation rendering independently from mouse tracking.

## Verification Status

Recent full checks passed after merging rendered color into `master` and after
deleting the retired `palette-color-wheel` branch:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

The user prefers manual Xcode builds for UI behavior checks. For small follow-up
UI iterations, use `git diff --check` and source inspection unless the user asks
for full `xcodebuild`.

Known warning: `removeAllAppearanceStreams()` deprecation remains.

## Handoff Prompt

```text
Read PRD.md and PRD.master.md. Continue work on master. Use feature branches for the roadmap items in PRD.md.
```
