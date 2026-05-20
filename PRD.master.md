# Branch PRD - `master`

Read `PRD.md` first. This file contains only branch-specific state for
`master`.

## Branch Scope

`master` is the stable core branch. It should contain PDF viewing/saving,
editable annotations, MathJax rendering, mixed text/math layout, selection
behavior, keyboard shortcuts, and basic editor workflow.

Do not add rendered text color UI, color metadata, renderer color parameters,
or color persistence on `master`. Color work belongs on `palette-color-wheel`.

## Current Core Behavior

- Open PDFs, add annotations, edit source in a floating dark editor panel, and
  render with the button or `Command+Enter`.
- Save writes portable visible appearances while preserving AnnoTex metadata for
  re-editability.
- Single-click selects one annotation.
- Clicking blank PDF space deselects.
- Shift-click toggles multi-selection.
- Multiple selected annotations drag together.
- Delete/Forward Delete deletes all selected annotations.
- Toolbar font-size slider applies one rendered font size to all selected
  annotations.
- The primary selected annotation is used as the toolbar/editor anchor.

## Selection State

Selection is intentionally PDF editor-style chrome:

- Selection state lives in `MathPDFView` as a selected-annotation set plus a
  primary annotation.
- Selection mutation is centralized in `MathPDFView.setSelectedAnnotations`.
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

## Active Branch Notes

- Known issues `MATH-001` and `MATH-002` in `PRD.md` are fixed on `master`;
  sync the core renderer fixes and tests to the color branch before relying on
  that branch for braced numeric scripts or extended arrow macros.
- The user manually confirmed the current selection overhaul and math renderer
  fixes before commit preparation.
- Later export work should add a separate flattened export mode, not change
  default Save.
- Later editing work may add annotation controls such as context menu,
  copy/cut/paste, and keyboard clipboard shortcuts.

## Verification Status

Recent full checks passed after the `MATH-001` and `MATH-002` renderer fixes.
The user also manually confirmed the current app version before commit
preparation:

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
Read PRD.md and PRD.master.md. Continue work on master. Do not implement rendered color functionality on this branch.
```
