# Branch PRD - `master`

Read `PRD.md` first. This file is the concise handoff state for `master`.

## Scope

`master` is the stable core branch. It should contain PDF viewing/saving, editable annotations, MathJax rendering, mixed text/math layout, selection behavior, and basic editor workflow.

Do not add rendered text color UI, metadata, renderer parameters, or persistence on `master`. Color work belongs on `palette-color-wheel`.

## Current Core Behavior

- Open PDFs, add annotations, edit source in a floating dark editor panel, render with button or `Command+Enter`.
- Save writes portable visible appearances while preserving AnnoTex metadata for re-editability.
- Single-click selects one annotation.
- Clicking blank PDF space deselects.
- Shift-click toggles multi-selection.
- Multiple selected annotations drag together.
- Delete/Forward Delete deletes all selected annotations.
- Toolbar font-size slider applies one rendered font size to all selected annotations.
- The primary selected annotation is used as the toolbar/editor anchor.

## Selection Implementation

Selection is intentionally PDF Expert-like editor chrome:

- Selection state lives in `MathPDFView` as a selected-annotation set plus primary annotation.
- Selection mutation is centralized in `MathPDFView.setSelectedAnnotations`.
- `LaTeXAnnotation.draw` draws only rendered annotation content. It must not draw selection borders or handles.
- Selection border/handles are drawn by a transparent `SelectionOverlayView`.
- The overlay is hosted inside PDFKit's `documentView`, not directly on `PDFView`, so it moves with PDF content during scroll and zoom.
- The overlay invalidates on selection changes, drag/resize, PDF visible-page changes, scroll clip-view bounds changes, and rerender completion.
- PDFKit is still notified with `annotationsChanged(on:)` when annotation content/state changes, but selected-border drawing is not dependent on PDFKit annotation/page rendering.

Important reason: drawing selection inside `PDFAnnotation.draw` or `PDFView.drawPagePost` caused stale or lagging borders because PDFKit caches and schedules page/annotation rendering independently from mouse tracking.

## Recent Selection Work

Implemented before this handoff:

- Selection set and primary annotation.
- Multi-select with Shift-click.
- Multi-drag.
- Delete all selected annotations.
- Font-size assignment to all selected annotations.
- Live overlay selection chrome.
- Overlay hosted in `documentView` to follow scroll/zoom.
- Overlay refresh after rerender so resize handles match final rendered bounds after line wrapping/natural-size snapping.

The user manually confirmed the current version is acceptable before commit preparation.

## Next Likely Work

1. Commit and push the current `master` selection overhaul after user approval.
2. Carry the core selection changes to `palette-color-wheel`.
3. On the color branch, adapt color adjustment so it applies to all selected annotations.
4. Later feature branch: annotation controls such as context menu, copy/cut/paste, and keyboard clipboard shortcuts.
5. Later export work: separate flattened export mode, not default Save.

## Verification Status

Recent full checks passed during selection work:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

The user prefers manual Xcode builds for UI behavior checks. For small follow-up UI iterations, use `git diff --check` and source inspection unless the user asks for full `xcodebuild`.

Known warning: `removeAllAppearanceStreams()` deprecation remains.

## Handoff Prompt

For a `master` agent:

```text
Read PRD.md and PRD.master.md. Continue work on master. Do not implement rendered color functionality on this branch.
```
