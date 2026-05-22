# AnnoTex PRD

This is the shared product, architecture, and handoff document for AnnoTex.
Every agent should read this file first, then read the branch-specific PRD:

- `PRD.master.md` for the stable core branch.
- `PRD.palette-color-wheel.md` for the rendered color branch.

## Product Goal

AnnoTex is a macOS PDF reader and annotation app for writing editable plain
text and LaTeX-style math directly onto PDF documents.

Core workflow:

1. Open a PDF.
2. Click `Add Annotation`.
3. Click a page to create an editable annotation.
4. Type plain text, math-only LaTeX, or mixed text/math source in the editor.
5. Render the annotation.
6. Move, resize, select, multi-select, copy, cut, paste, delete, undo, and
   adjust rendered font size.
7. Save a PDF with visible portable annotation appearances.
8. Reopen the PDF in AnnoTex and continue editing the original source.

Math rendering should be MathJax-backed, visually LaTeX-like, sharp enough for
PDF zooming, and editable after save/reopen through preserved source metadata.

## PRD Maintenance Instructions

Agents must read this section before editing any PRD file.

PRDs are durable handoff documents, not implementation logs. Update them only
when architecture, dependencies, branch responsibilities, rendering/persistence
behavior, verification status, or known issue status changes meaningfully. A
single PRD update before a user-requested commit is usually sufficient.

Keep `PRD.md` as the shared source of truth. Keep branch PRDs short and
branch-specific. Replace stale information instead of appending historical
notes. If code and PRD disagree, inspect and verify the code first, then update
the PRD to describe the current reality.

Known issues must include status, affected branch, reproduction, impact, root
cause if known, intended fix, and verification/fixed commit when resolved.

## Branches

`master`
: Stable core branch. Owns PDF viewing/saving, editable annotations, MathJax
rendering, mixed text/math layout, selection behavior, keyboard shortcuts, and
basic editor workflow. Do not add rendered text color UI, color metadata,
renderer color parameters, or color persistence here.

`palette-color-wheel`
: Experimental rendered text color branch. Owns color UI, color metadata, and
colored rendering while pulling non-color core fixes from `master`. Do not let
merges from `master` remove color behavior unless retiring the branch.

Use separate worktrees for simultaneous branch work:

```sh
git worktree add ../AnnoTex-master master
git worktree add ../AnnoTex-palette palette-color-wheel
```

Use separate derived data paths when building both branches:

```sh
-derivedDataPath /private/tmp/AnnoTexDerivedData-master
-derivedDataPath /private/tmp/AnnoTexDerivedData-palette
```

## Dependencies

Primary platform dependencies:

- SwiftUI and AppKit for application UI, editor panels, and overlay chrome.
- PDFKit for PDF display, PDF pages, annotation storage, coordinate conversion,
  and save/reopen behavior.
- CoreText for the small plain-text/fallback renderer path.
- JavaScriptCore through `MathJaxSwift` for MathJax execution.

Swift package dependencies are pinned by `Package.resolved`:

- Direct package: `LaTeXSwiftUI` from `https://github.com/colinc86/LaTeXSwiftUI.git`
  on branch `main`.
- Transitive packages currently include `MathJaxSwift` version `3.5.0`,
  `SwiftDraw` version `0.27.0`, and `swift-html-entities` version `4.0.1`.

Important dependency notes:

- The Xcode project declares `LaTeXSwiftUI` as the package product dependency.
  `MathJaxSwift` and `SwiftDraw` arrive transitively through that package.
- The current app imports `LaTeXSwiftUI`, `MathJaxSwift`, and `SwiftDraw`
  directly in `AnnoTex.swift`.
- `SwiftDraw` is used by the direct MathJax SVG rasterization path. If package
  visibility changes, verify the Xcode target can still see that module and
  builds from a clean DerivedData path.
- Do not change package pins casually. Rendering and PDF appearance behavior are
  sensitive to MathJaxSwift, LaTeXSwiftUI, and SwiftDraw behavior.

## Code Architecture

The current app is concentrated in `AnnoTex/AnnoTex.swift`.

Core types:

- `LaTeXAnnotation`: a `PDFAnnotation` subclass using PDF `/Stamp`
  annotations. It stores editable source and rendering metadata, and its
  `draw(with:in:)` method draws only rendered annotation content.
- `RenderedAnnotation`: immutable rendered content model. It can hold either
  CoreText lines/metrics or a rendered `NSImage`, plus layout size, padding, and
  sizing mode.
- `MathJaxAnnotationRenderer`: primary renderer for math-only and mixed
  text/math sources. It parses mixed inline math, renders math as images, wraps
  mixed segments, and composes final annotation images.
- `NativeAnnotationRenderer`: public renderer entry point used by annotation
  workflows. It currently tries `MathJaxAnnotationRenderer` first and then uses
  a small CoreText path for plain/fallback rendering.
- `LaTeXEditorPanel`: floating dark AppKit editor panel. Raw editor text is
  fixed-size Menlo and does not change with rendered font size.
- `MathPDFView`: custom `PDFView` subclass that owns annotation creation,
  editing, selection, drag, resize, clipboard operations, undoable box
  mutations, deletion, rerendering, save preparation, and PDFKit invalidation.
- `SelectionOverlayView`: transparent overlay hosted inside PDFKit's
  `documentView`. It draws live selection borders and resize handles outside of
  `PDFAnnotation.draw` to avoid PDFKit annotation-cache lag.
- `ContentView` / `PDFKitView`: SwiftUI wrapper and toolbar-level state around
  `MathPDFView`.

Keep architectural ownership clear:

- Annotation content rendering belongs in renderer types.
- PDF interaction, selection, and editor lifecycle belong in `MathPDFView`.
- Selection chrome belongs in `SelectionOverlayView`, not annotation drawing.
- Persistent editability belongs in `LaTeXAnnotation` metadata.

## Annotation Persistence and Saving

Editable AnnoTex annotations are PDF `/Stamp` annotations with private metadata.
Only annotations with AnnoTex metadata should be rehydrated as editable
AnnoTex annotations.

Current metadata keys:

- `/AnnoTexKind`
- `/AnnoTexSource`
- `/AnnoTexFontSize`
- `/AnnoTexRendererVersion`
- `/AnnoTexMetadataVersion`
- `/AnnoTexLayoutBounds`

The `palette-color-wheel` branch additionally stores `/AnnoTexTextColor`.
Keep that key branch-local unless rendered text color is intentionally promoted
to `master`.

On `palette-color-wheel`, annotation clipboard payloads and undo state
snapshots also carry the canonical `/AnnoTexTextColor` hex value so copy, cut,
paste, and undo/redo preserve rendered color.

Expected persistence behavior:

- Normal Save preserves AnnoTex editability and writes portable visible
  appearances for non-AnnoTex PDF readers.
- Saved PDFs should reopen in AnnoTex with editable source, font size, and
  layout bounds restored.
- Flattened export, if added later, must be a separate export mode because
  flattening sacrifices editability.
- `removeAllAppearanceStreams()` is deprecated but currently helps force
  regenerated portable appearances. Do not remove it without manual saved-PDF
  verification in Preview and Acrobat or another external PDF reader.

## Rendering Pipeline

Public renderer entry point on `master`:

```swift
NativeAnnotationRenderer.render(source:width:fontSize:)
```

On `palette-color-wheel`, the renderer entry points additionally accept
`textColor: NSColor = .black` and must pass that color through MathJax,
mixed text/math, and CoreText fallback rendering.

Current intended behavior:

- Empty/whitespace source does not render an annotation.
- Plain text-only source may use the CoreText renderer path.
- Math-only source may be bare TeX or wrapped in `\( ... \)`, `\[ ... \]`,
  `$ ... $`, or `$$ ... $$`.
- Mixed text/math supports inline `$...$` and `\(...\)`.
- Rendered font size changes affect rendered annotation output only, not the
  raw editor font.
- Plain text and MathJax-rendered math should resize synchronously.

Current implementation shape:

- `MathJaxAnnotationRenderer` detects math-only input, otherwise requires math
  delimiters for mixed rendering.
- Mixed parsing splits lines into text and math segments, wraps segments to the
  annotation width, and composes a final `NSImage`.
- Visible math rendering calls `MathJaxSwift.tex2svg` directly with AnnoTex's
  corrected TeX input options, including the corrected digit parser and the full
  MathJax TeX package set. It parses the resulting SVG metrics and rasterizes
  the same SVG through `SwiftDraw`.
- Mixed rendering currently relies on `NSImage.lockFocus()` behavior for final
  text/math composition. Do not replace that composition path without carefully
  reproducing coordinate behavior and manually verifying mixed text rendering.
- Mixed layout treats every segment baseline as distance from the bottom of that
  segment's drawing box. Text segments use CoreText descent for that baseline
  depth; MathJax image segments use SVG `vertical-align` depth.
- Mixed layout uses MathJax SVG metrics for baseline alignment and rendered math
  images for visible output.
- The CoreText fallback is intentionally small. Do not grow it into a TeX
  implementation. Math content should be rendered by MathJax.

Renderer baseline stress case:

```text
Consider $\bigoplus_p E^\infty_{p, n-p}$ the graded complex
```

MATH-003 guards this case. Future baseline fixes should stay systemic and
metric-based. Do not patch individual commands, glyphs, or symbols.

## Interaction Model

Current core interactions:

- `Add Annotation` mode changes the PDF cursor to a crosshair.
- Clicking a page in add mode creates a new editable annotation.
- Single-click selects one annotation.
- Clicking blank PDF space deselects annotations.
- Shift-click toggles multi-selection.
- Multiple selected annotations drag together.
- Delete/Forward Delete deletes all selected annotations.
- Right-clicking an unselected annotation selects only that annotation, then
  shows annotation actions.
- Right-clicking any annotation in a multi-selection keeps the selection and
  applies annotation actions to the whole selected set.
- Right-clicking blank PDF space keeps the current selection and shows Paste.
  Paste is disabled when the macOS clipboard has no private AnnoTex annotation
  payload.
- Context-menu Paste tries the right-click point first. `Command+V` tries the
  visible PDF area center first. If that placement overlaps existing AnnoTex
  annotations on the target page, paste cascades to a nearby non-overlapping
  position when one is available.
- Copied multi-annotation groups preserve relative offsets when pasted.
- Toolbar font-size slider applies one rendered font size to all selected
  annotations.
- The primary selected annotation is used as the toolbar/editor anchor.
- Enter inserts a manual line break in the editor.
- `Command+Enter` renders from the editor.
- `Command+C`, `Command+X`, and `Command+V` copy, cut, and paste annotations
  using an AnnoTex-private pasteboard payload.
- `Command+Z` undoes box edits including add, paste, cut, delete, move, resize,
  rendered text edits, and font-size changes. `Shift+Command+Z` redoes through
  the same undo stack.
- `Esc` exits Add Annotation mode.

Selection implementation rule:

- `LaTeXAnnotation.draw` must not draw selection borders or handles.
- Selection state lives in `MathPDFView`.
- Selection mutation should stay centralized through the existing selection
  update path.
- Selection chrome is drawn by `SelectionOverlayView` so it remains responsive
  during mouse tracking and avoids stale PDFKit annotation rendering.
- Clipboard data should remain a private AnnoTex pasteboard type unless the
  product intentionally adds cross-app plain-text copy behavior later.

## User Constraints

- The raw editor font stays fixed-size monospaced Menlo.
- The rendered font size slider affects rendered output only.
- Math rendering must not depend on the CoreText fallback for valid math.
- Save/reopen must preserve editability.
- Default Save must not flatten annotations.
- Color UI and color persistence are out of scope for `master`.

## Known Issues and Bugs

Maintain this section regularly. Use stable issue IDs so future agents can
refer to issues without re-explaining them.

### COLOR-001: Editor Color Panel Changes Raw Editor Text Color

Status: Fixed on `palette-color-wheel` as of 2026-05-22.

Affected branches: `palette-color-wheel` only. Rendered text color remains out
of scope for `master`.

Reproduction:

- Open an annotation editor on `palette-color-wheel`.
- Use the rendered text color button in the editor and choose a non-white color.
- The raw editor text can change color even though only rendered output should
  be affected.
- After choosing a non-white rendered color, typing in the editor can push the
  color panel selection back to the editor's white source-text color.

Impact:

- Editor readability regresses in the dark editor.
- Rendered annotation color and raw source-editing style become conflated.

Findings:

- The rendered color UI uses the shared `NSColorPanel`.
- The raw editor was a plain `NSTextView` without protection against AppKit text
  color actions or typing-attribute changes.
- AppKit also reads `NSTextView.typingAttributes` for color panel state, so
  forcing typing attributes to white can overwrite the rendered color selection
  even when existing editor source text remains white.

Fix:

- The editor now uses a fixed-style text view that ignores `changeColor(_:)`
  and reasserts fixed Menlo, white foreground, dark background, insertion color,
  and source-text storage after rendered-color changes.
- Existing editor source text stays white, while typing/color-panel foreground
  attributes stay synchronized to the rendered color so typing does not reset
  the color panel to white.
- The fixed-style text view must still be initialized through the normal
  `NSTextView(frame:)` path so editor text storage, layout manager, and text
  container remain intact.

Verification:

- Passed on 2026-05-22 on `palette-color-wheel`:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests`.
- Manual verification should confirm red, green, and blue rendered-color
  selections leave raw editor text white and remain selected while typing.

### COLOR-002: Selected Color Differs From Rendered Or Persisted Color

Status: Fixed on `palette-color-wheel` as of 2026-05-22.

Affected branches: `palette-color-wheel` only.

Reproduction:

- Select a rendered text color from the color panel.
- Compare the toolbar/editor swatch, rendered annotation appearance, and
  `/AnnoTexTextColor` after save/reopen.

Impact:

- Users can see a mismatch between the color they selected and the color drawn
  in annotations.
- Save/reopen can preserve a different-looking color than the visible swatch.

Findings:

- The color branch mixed raw `NSColorPanel` colors, sRGB hex metadata, and
  calibrated-RGB decoding.
- Different paths could therefore consume subtly different color-space values.

Fix:

- Rendered colors are now canonicalized as clamped sRGB values everywhere.
- `/AnnoTexTextColor` remains exactly `#RRGGBB`, decoded with
  `NSColor(srgbRed:green:blue:alpha:)`.
- Toolbar/editor UI state, annotation metadata, CoreText rendering, and MathJax
  image tinting all consume the same canonical color.

Verification:

- Passed on 2026-05-22 on `palette-color-wheel`:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests`.
- Tests cover sRGB hex round-trip, wide-gamut clamping, valid decode, editor
  fixed-style protection with intact text storage/layout/container and stable
  rendered typing/color-panel foreground, metadata preservation, and
  MathJax/mixed image tinting.

### COLOR-003: Resize Can Change Rendered Text Color

Status: Fixed on `palette-color-wheel` as of 2026-05-22.

Affected branches: `palette-color-wheel` only.

Reproduction:

- Create a colored annotation.
- Resize the selected annotation.
- The annotation can rerender with an unexpected color.

Impact:

- Resize becomes destructive to color state.
- Users cannot trust color persistence across ordinary layout edits.

Findings:

- Resize triggers rerendering.
- Before canonicalization, rerendering could read a color back through metadata
  using a different color-space representation than the one originally selected.

Fix:

- Resize remains color-neutral.
- Rerendering captures the annotation's canonical stored color and passes that
  exact color to the renderer; bounds/layout updates do not assign a new color.

Verification:

- Passed on 2026-05-22 on `palette-color-wheel`:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests`.
- Manual verification should resize colored math-only and mixed text/math
  annotations, then save/reopen and confirm color and source persist.

### MATH-001: Braced Numeric Scripts Fail Or Use Upright Glyphs

Status: Fixed on `master` as of 2026-05-20 in commit `483f855`.

Affected branches: fixed on `master`; likely relevant to `palette-color-wheel`
until the core renderer fix is synced there.

Reproduction examples:

- Math-only: `H_{1}`, `H_{n-1}`, `H^{1}`, `H^{n-1}`.
- Mixed text: `Consider $H_{n-1}$ and $H_{2n}$`.
- `H_{2n}` may render, but the `n` can be upright instead of italic math
  font.
- Nearby non-failing examples include `H_n`, `H_{n}`, `H_1`, and `H_{n^2}`.

Impact:

- Valid MathJax/LaTeX scripts can display as a black/error box.
- Some scripts render with incorrect math typography.
- The CoreText fallback can mask MathJax failures and produce non-MathJax
  output, which violates the product goal for math rendering.

Findings:

- Before the fix, the visible math image path called `LaTeX.renderToImages`
  from `MathJaxAnnotationRenderer.renderMathImage`.
- `LaTeX.renderToImages` is MathJax-backed but hides the intermediate SVG and
  uses MathJaxSwift options that include a problematic default `digits` regex.
- The default regex does not escape literal braces/dot correctly for this
  JavaScript MathJax context. With inputs like `H_{1}` and `H_{n-1}`, MathJax
  can emit an `merror` SVG such as "Extra open brace or missing close brace".
- With `H_{2n}`, the same digit parsing can treat `2n` like numeric text,
  causing the `n` to use an upright glyph instead of italic math glyph.

Fix:

- Math now renders through direct `MathJaxSwift.tex2svg` calls with corrected
  `TeXInputProcessorOptions.digits`:
  `^(?:[0-9]+(?:\{,\}[0-9]{3})*(?:\.[0-9]*)?|\.[0-9]+)`.
- The same corrected MathJax SVG result is used for rasterized images and
  metrics in math-only and mixed text environments.
- SVG geometry parsing treats a missing `vertical-align` style as zero, which
  supports superscript-only outputs such as `H^{1}`.
- Failed explicit math or bare math-looking sources are not routed through the
  CoreText fallback.

Verification:

- Added renderer tests for braced numeric subscripts/superscripts and mixed
  text/math cases.
- Tests assert no MathJax `merror` output for valid test expressions.
- Tests assert `H_{2n}` uses the italic math `n` glyph in MathJax SVG output.
- Passed on 2026-05-20:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build`.
- Passed on 2026-05-20:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests`.
- User manually confirmed in the running app on 2026-05-20 that the
  number-in-brackets rendering issue is solved.

### MATH-002: Extended Arrow Macros Render As Error Boxes

Status: Fixed on `master` as of 2026-05-20 in commit `483f855`.

Affected branches: fixed on `master`; likely relevant to `palette-color-wheel`
until the core renderer fix is synced there.

Reproduction examples:

- `\xrightarrow{}`
- `\xrightarrow{a}`
- `A \xrightarrow{f} B`
- `\xleftarrow{a}`

Impact:

- Valid extended arrow macros can display as black/error boxes.
- Users may see the same symptom as MATH-001, but this is a different root
  cause.

Findings:

- The direct MathJax renderer introduced for MATH-001 originally created
  `TeXInputProcessorOptions` with only the corrected `digits` regex.
- MathJaxSwift's default `loadPackages` is only `base`.
- LaTeXSwiftUI's rendered path loads the full MathJax package set; extended
  arrow macros such as `\xrightarrow{...}` require packages outside `base`.

Fix:

- AnnoTex's direct MathJax options now preserve
  `TeXInputProcessorOptions.Packages.all` while keeping the corrected MATH-001
  `digits` regex.

Verification:

- Added renderer tests for `\xrightarrow{}`, `\xrightarrow{a}`,
  `A \xrightarrow{f} B`, and `\xleftarrow{a}`.
- Tests assert the expressions render through MathJax image output, do not fall
  back to CoreText, and do not emit MathJax `merror` SVG output.
- Passed on 2026-05-20:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build`.
- Passed on 2026-05-20:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests`.
- User manually confirmed in the running app on 2026-05-20 that the current
  renderer behavior is acceptable after the extended-arrow fix.

### MATH-003: Mixed Text/Math Baseline Misalignment

Status: Fixed on `master` as of 2026-05-21. Fixed commit pending.

Affected branches: fixed on `master`; likely relevant to `palette-color-wheel`
until the core renderer fix is synced there.

Reproduction examples:

- `Text $x$ text`
- `Text $H_{n-1}$ text`
- `Before $\frac{a}{b}$ after`
- `Consider $\bigoplus_p E^\infty_{p, n-p}$ the graded complex`
- `Map $A \xrightarrow{f} B$ now`

Impact:

- Inline math could sit too high or too low relative to surrounding text.
- Tall/deep math such as fractions or subscripted operators could distort line
  placement or visually drift away from the plain-text baseline.
- Users saw the issue most clearly in mixed text/math annotations, not math-only
  annotations.

Findings:

- The mixed renderer composes text and math segments into a single `NSImage`
  and positions each segment with `lineBaseline - segmentBaseline`.
- That composition formula expects `segmentBaseline` to mean distance from the
  bottom of the segment's drawing box.
- Before the fix, text segments reported `font.ascender`, which is height above
  the baseline, not depth below it.
- Before the fix, math segments converted MathJax SVG `vertical-align` into
  `imageHeight - depth`, which again describes a near-top coordinate rather than
  depth below the baseline.
- A `shallowInlineMathCorrection` heuristic partially hid the mismatch for some
  compact expressions but made the baseline model harder to reason about.

Fix:

- Mixed text segments now use CoreText typographic metrics and report descent as
  their baseline depth.
- Mixed MathJax image segments now interpret SVG `vertical-align` as the math
  depth below the baseline:
  `max(-verticalAlignment * xHeight * heightScale, 0)`.
- Line height is computed from maximum depth below the baseline plus maximum
  height above the baseline across all segments.
- The `NSImage.lockFocus()` composition path is preserved, but its metric inputs
  are now consistent.
- The shallow inline correction heuristic was removed.
- Added debug-only mixed layout metrics so tests can verify baseline geometry
  without relying on fragile image snapshots.

Verification:

- Added tests for simple inline math, text descent metrics, the deep
  `\bigoplus_p E^\infty_{p, n-p}` stress case, and MATH-001/MATH-002 mixed
  regressions.
- Passed on 2026-05-21:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build`.
- Passed on 2026-05-21:
  `xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests`.
- Manual checks should cover font sizes 12, 18, and 24, plus a narrow annotation
  width that forces mixed text/math wrapping.

## Verification

Reliable full checks for `master`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

Use the palette branch derived data path for `palette-color-wheel`:

```sh
-derivedDataPath /private/tmp/AnnoTexDerivedData-palette
```

For small UI iterations, the user may prefer manual Xcode builds. In that case,
use lightweight checks such as `git diff --check` plus source inspection unless
the user asks for full `xcodebuild`.

When recording verification in PRDs, be explicit: passed, failed, not run, or
manual-only. Avoid vague "should work" language.
