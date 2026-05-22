# Retired Palette Color Experiment

Read `PRD.md` first. This file is an archive of the retired
`palette-color-wheel` experiment, not an active branch handoff.

## Retirement Status

The `palette-color-wheel` branch was merged into `master` at commit `9cfb8bc`
on 2026-05-22. The local branch, remote branch, and extra worktree were then
deleted. Do not continue work on or recreate `palette-color-wheel`; rendered
text color is now core `master` behavior.

## Durable Color Behavior

The experiment promoted these behaviors into `master`:

- Rendered text color UI in the toolbar and editor panel.
- Rendered color metadata stored as `/AnnoTexTextColor`.
- Canonical clamped sRGB `#RRGGBB` color handling.
- Renderer color parameters threaded through MathJax, mixed text/math, and
  CoreText fallback rendering.
- Color preservation across edit, resize, save, reopen, copy, cut, paste, and
  undo/redo flows.
- Raw editor text remains fixed Menlo white on a dark background; rendered
  color choices do not restyle source text.
- The shared macOS color panel opens as a frontmost/key floating panel, starts
  on the common-colors picker, accepts user color actions while key, and closes
  with `Command+W`.

## Regression Checklist

Use this checklist when changing rendered color behavior on `master`:

- New annotation uses the current selected color.
- Existing annotation opens the editor with stored color.
- Render from editor preserves selected color.
- Resize preserves color.
- Copy/cut/paste preserves color for single annotations and multi-selection
  groups.
- Undo/redo of add, paste, cut, delete, move, resize, edit, and font-size
  operations preserves color.
- Save and reopen preserves color.
- Non-AnnoTex PDF readers display colored annotation appearances.
- Multi-selected color adjustment applies to every selected annotation.
- Math rendering fixes still honor the selected/stored rendered text color.
- The color panel opens frontmost/key from both toolbar and editor controls,
  accepts user color changes, and closes with `Command+W`.
- `Command+A` and typing in the editor leave the rendered color selection
  unchanged.
- The color panel opens on common colors by default.

Manual verification passed on 2026-05-22 before merging this experiment into
`master`.
