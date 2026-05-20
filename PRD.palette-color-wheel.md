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
- color preservation across edit, resize, save, reopen, and future copy/paste
  flows

Expected behavior after multi-selection is ported:

- Font-size changes apply to all selected annotations, matching `master`.
- Color changes apply to all selected annotations.
- If selected annotations have mismatched font sizes or colors, the next
  explicit adjustment is a unified assignment to all selected annotations.
- Resizing must never change rendered text color.

## Master Sync Notes

Core non-color fixes should be pulled or cherry-picked from `master`. When
porting, preserve color metadata and renderer color parameters. Resolve
conflicts in favor of keeping this branch's extra color behavior.

The current `master` selection overhaul should be carried to this branch if it
has not already been synced:

- selected-annotation set plus primary annotation
- centralized selection mutation
- Shift-click multi-selection
- multi-drag
- Delete all selected annotations
- font-size assignment to all selected annotations
- live AppKit overlay selection chrome hosted inside PDFKit's `documentView`

Known issue `MATH-001` in `PRD.md` likely affects this branch unless the branch
has a separate renderer fix. If `master` fixes it first, port the fix without
dropping color rendering parameters.

## Color Regression Checklist

Manually verify after color changes or after syncing core selection/rendering
work:

- New annotation uses current selected color.
- Existing annotation opens editor with stored color.
- Render from editor preserves selected color.
- Resize preserves color.
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
