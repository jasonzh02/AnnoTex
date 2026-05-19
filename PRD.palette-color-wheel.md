# Branch PRD - `palette-color-wheel`

Read `PRD.md` before this file. This file tracks current status and next work specific to `palette-color-wheel`.

## 1. Branch Purpose

`palette-color-wheel` is the experimental branch for rendered text color. It should keep the full rendered-color implementation isolated from `master` until the feature is intentionally promoted.

This branch may periodically merge or cherry-pick non-color core fixes from `master`.

## 2. Branch-Specific Functionality

The color branch owns:

- Rendered text color UI.
- Color-wheel/color-panel behavior.
- Rendered text color metadata.
- Rendered text color application during annotation rendering.
- Color preservation across edit, resize, save, and reopen flows.

Expected color behavior:

- Color adjustment should apply synchronously to all selected annotations once multi-selection exists.
- If selected annotations have mismatched colors, the next explicit color adjustment should be treated as a unified assignment to all selected annotations.
- Resizing must never change rendered text color as a side effect.
- Branch-specific clipboard behavior should preserve color metadata once annotation copy/cut/paste exists.

## 3. Metadata

`palette-color-wheel` may store branch-specific rendered color metadata in addition to the shared metadata listed in `PRD.md`.

Keep color metadata isolated from `master`. If a core fix from `master` removes color metadata or renderer parameters, do not merge it blindly. Adapt the core fix while preserving branch-specific color behavior.

## 4. Core Work To Track From `master`

Regularly review `master` for non-color fixes in these areas:

- Selection model and invalidation.
- Annotation movement, resize, and deletion.
- MathJax rendering.
- Mixed text/math wrapping and baseline work.
- Save/reopen metadata handling.
- Test and build infrastructure.

When applying a `master` fix:

- Prefer cherry-picking small, focused commits.
- Use a normal merge only when the branch is ready to absorb all non-color changes.
- Resolve conflicts by preserving the color branch's extra metadata, UI, and rendering inputs.
- Re-run branch-specific verification with `/private/tmp/AnnoTexDerivedData-palette`.

## 5. Planned Work

### 5.1 Selection Model Follow-Through

After `master` lands the selection model overhaul, adapt it on this branch so:

- Single-click selection behavior matches `master`.
- Shift-click multi-select works.
- Multiple selected annotations drag together.
- Toolbar font-size adjustment applies to all selected annotations.
- Color adjustment applies to all selected annotations.
- Mismatched selected font sizes or colors are unified on the next explicit adjustment.

### 5.2 Color Regression Checks

When making color changes or merging core work, manually verify:

- New annotation uses the current selected color.
- Existing annotation opens editor with its stored color.
- Render from editor preserves selected color.
- Resize preserves color.
- Save and reopen preserves color.
- Non-AnnoTex PDF readers display colored annotation appearances.

## 6. Verification Commands

Use a palette-specific derived data path when another agent is working on `master`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

## 7. Handoff Instructions

For a `palette-color-wheel` agent, start with:

```text
Read PRD.md and PRD.palette-color-wheel.md. Continue work on palette-color-wheel. Preserve rendered color functionality while pulling in non-color core fixes from master as needed.
```

When finishing a meaningful change on `palette-color-wheel`, update this file with:

- Current color implementation status.
- New known color regressions or fixes.
- Which `master` commits were merged or cherry-picked.
- Verification commands run and their results.
