# Branch PRD - `master`

Read `PRD.md` before this file. This file tracks current status and next work specific to `master`.

## 1. Branch Purpose

`master` is the stable branch for core app functionality:

- PDF viewing and saving.
- Annotation creation, editing, moving, resizing, and deletion.
- MathJax rendering.
- Mixed text/math wrapping and baseline work.
- Selection behavior.
- Keyboard shortcuts and basic editor workflow.

Rendered text color functionality is intentionally not present on `master`. Do not add rendered color UI, metadata, renderer parameters, or color persistence here.

## 2. Current Implementation Snapshot

### 2.1 PDF Viewing, Editing, and Persistence

- Users can open PDFs through `NSOpenPanel`.
- Users can click `Add Annotation` and then click a page to create an annotation.
- Users can edit annotations in a floating dark `NSPanel`.
- Rendering works with the `Render` button or `Command+Enter`.
- Single-click selects an annotation.
- A selected annotation can be moved by dragging it.
- A selected annotation can be resized from corner handles.
- Delete/Forward Delete deletes the selected annotation.
- The toolbar font-size slider adjusts rendered font size.
- PDFs save through the normal portable save path.
- The raw editor uses fixed-size monospaced Menlo. Rendered font size must not change the editor font.

### 2.2 Annotation Data Model

- Custom annotations are represented by `LaTeXAnnotation`, a `PDFAnnotation` subclass using the standard `/Stamp` subtype.
- `master` stores the shared AnnoTex metadata listed in `PRD.md`.
- `master` does not store rendered text color metadata.
- Normal PDF annotations from other readers are not blindly converted into AnnoTex annotations.
- Only annotations with AnnoTex metadata are rehydrated as editable AnnoTex annotations.

### 2.3 Selection UI

- A selected annotation draws a dashed black selection border.
- The selection border is inset inside the annotation bounds so the corner handles are not clipped.
- Corner handles are small full circles.
- The dashed border edges meet at the centers of the corner circles, similar to PowerPoint image selection.
- Known issue: selection invalidation is still imperfect. Borders can linger until hover/repaint in some cases, and multiple boxes can appear selected even when the intended model is single selection. This is a priority future fix.

## 3. Planned Work

### 3.1 Selection Model Overhaul

Required behavior:

- Single-click selects exactly one annotation.
- Single-clicking another annotation deselects the previous annotation immediately and selects the new one.
- Clicking outside all annotations deselects all annotations immediately, with no lingering borders.
- Shift-click supports multiple selected annotations.
- Multiple selected annotations can be dragged together.
- Toolbar font-size adjustment applies synchronously to all selected annotations.
- If selected annotations have mismatched font sizes, the next explicit adjustment should be treated as a unified assignment to all selected annotations.

Implementation direction:

- Replace the single `activeAnnotation` model with a selected-annotation set.
- Keep a primary selected annotation only for operations that need an anchor.
- Centralize selection mutation in one method.
- Always invalidate old and new annotation display rects, plus fall back to a full PDF view redraw if PDFKit caching still leaves stale borders.

Do not implement rendered color selection behavior on `master`. That belongs in `PRD.palette-color-wheel.md`.

### 3.2 Annotation Controls Branch

Create a new branch for annotation editing controls when this work starts:

- Right-click selected annotation:
  - Delete
  - Copy
  - Cut
- Right-click blank PDF area:
  - Paste, when an annotation exists on the app clipboard
- Keyboard shortcuts:
  - `Command+C` copy selected annotation(s)
  - `Command+V` paste copied annotation(s)
  - `Command+X` cut selected annotation(s)
  - Delete/Forward Delete delete selected annotation(s)
- Clipboard should preserve:
  - source
  - rendered font size
  - bounds/layout

### 3.3 Save/Export Modes

- Keep normal Save as editable AnnoTex PDF with portable annotation appearances.
- Add a separate flattened export mode for maximum compatibility.
- Verify both modes on another machine and in non-AnnoTex PDF readers.

## 4. Verification Status

Most recent known-good commands for `master`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

Both commands succeeded after the current sizing-mode update.

## 5. Handoff Instructions

For a `master` agent, start with:

```text
Read PRD.md and PRD.master.md. Continue work on master. Do not implement rendered color functionality on this branch.
```

When finishing a meaningful change on `master`, update this file with:

- Current implementation status.
- New known issues or regressions.
- Verification commands run and their results.
- Any core commits that should be merged or cherry-picked into `palette-color-wheel`.
