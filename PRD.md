# Product Requirements Document (PRD) - AnnoTex

This file is the shared product baseline for all AnnoTex branches. Branch-specific status, active work, and handoff notes live in:

- `PRD.master.md`
- `PRD.palette-color-wheel.md`

When starting a new agent, read this file first, then read the PRD for the branch being worked on.

## 1. Product Goal

AnnoTex is a macOS PDF reader and annotation app for writing editable text and LaTeX-style math directly on PDF documents.

The core workflow is:

1. Open a PDF.
2. Click `Add Annotation`.
3. Click on a page to create an editable annotation.
4. Type plain text, math-only LaTeX, or mixed text/math source in the editor panel.
5. Render the annotation.
6. Move, resize, and adjust rendered font size without changing the raw editor font.
7. Save the PDF with visible portable annotation appearances.
8. Reopen the same PDF in AnnoTex and continue editing the original annotation source.

The rendering goal is high-fidelity LaTeX-like output. Math should support broad TeX/LaTeX syntax through MathJax, visually resemble standard LaTeX inline/display math, remain sharp enough while zooming, and preserve editable source metadata inside saved PDFs.

## 2. Branch Workflow

### 2.1 `master`

`master` is the stable branch for core app functionality:

- PDF viewing and saving.
- Annotation creation, editing, moving, resizing, and deletion.
- MathJax rendering.
- Mixed text/math wrapping and baseline work.
- Selection behavior.
- Keyboard shortcuts and basic editor workflow.

Rendered text color functionality is intentionally not present on `master`.

Use `PRD.master.md` for current status and next work on this branch.

### 2.2 `palette-color-wheel`

`palette-color-wheel` is the experimental branch for rendered text color:

- It contains the color-wheel/color-panel implementation.
- It may periodically cherry-pick or merge non-color core fixes from `master`.
- Avoid merging `master` commits that intentionally remove color functionality unless the branch is being retired.

Use `PRD.palette-color-wheel.md` for current status and next work on this branch.

### 2.3 Parallel Agent Workflow

Use separate working directories for simultaneous branch work. Prefer `git worktree` over cloning:

```sh
git worktree add ../AnnoTex-master master
git worktree add ../AnnoTex-palette palette-color-wheel
```

Run each agent in its own worktree. Do not point two agents at the same checkout.

Use separate Xcode derived data paths to avoid build cache collisions:

```sh
-derivedDataPath /private/tmp/AnnoTexDerivedData-master
-derivedDataPath /private/tmp/AnnoTexDerivedData-palette
```

Move core fixes from `master` to `palette-color-wheel` with a deliberate merge or cherry-pick. Do not move rendered-color implementation back to `master`.

### 2.4 Future Feature Branches

Create separate branches for substantial feature experiments. Planned examples:

- `annotation-controls` or similar: context menu, copy/cut/paste, keyboard shortcuts for annotation clipboard operations.
- A mixed-baseline branch if the baseline work becomes large enough to isolate.

## 3. Shared Implementation Invariants

### 3.1 PDF Viewing, Editing, and Persistence

- The app uses `PDFKit` for PDF display and annotation management.
- The main PDF surface is `MathPDFView`, a custom `PDFView` subclass.
- Custom annotations are represented by `LaTeXAnnotation`, a `PDFAnnotation` subclass using the standard `/Stamp` subtype.
- Normal PDF annotations from other readers are not blindly converted into AnnoTex annotations.
- Only annotations with AnnoTex metadata are rehydrated as editable AnnoTex annotations.
- The raw editor uses fixed-size monospaced Menlo. Rendered font size must not change the editor font.
- Pressing Enter in the editor inserts a manual line break.
- `Command+Enter` in the editor should render.
- `Esc` exits Add Annotation mode.
- Add Annotation mode should show a crosshair cursor over the PDF view, including after a PDF is loaded.

### 3.2 Portable Metadata

AnnoTex stores private PDF annotation metadata for re-editability:

- `/AnnoTexKind`
- `/AnnoTexSource`
- `/AnnoTexFontSize`
- `/AnnoTexRendererVersion`
- `/AnnoTexMetadataVersion`
- `/AnnoTexLayoutBounds`

Branch-specific metadata must remain branch-specific. In particular, rendered text color metadata belongs only on `palette-color-wheel` unless the feature is intentionally promoted later.

### 3.3 Save Behavior

- Normal Save syncs AnnoTex metadata, clears stale appearance streams, and lets PDFKit write annotation appearance streams.
- Saved PDFs should display annotations in other PDF readers.
- Only AnnoTex needs to preserve/edit original annotation source.
- Maximum-compatibility flattening is not implemented and must remain a separate export mode because flattening sacrifices AnnoTex editability.
- `removeAllAppearanceStreams()` is deprecated but still used because it currently helps force regenerated portable appearances. Do not remove it without manual saved-PDF verification in Preview/Acrobat.

## 4. Rendering Architecture

### 4.1 Renderer Entry Points

- `NativeAnnotationRenderer.render(source:width:fontSize:)` is the public entry point used by `MathPDFView`.
- `NativeAnnotationRenderer` first tries `MathJaxAnnotationRenderer.shared.render(source:width:fontSize:)`.
- If MathJax rendering fails, the native Core Text fallback path is used.
- The native fallback contains a small handwritten math subset. Do not grow it into a TeX implementation.

### 4.2 MathJax Rendering

- The project depends on `LaTeXSwiftUI`, which brings in:
  - `MathJaxSwift`
  - `SwiftDraw`
  - `swift-html-entities`
- `MathJaxAnnotationRenderer` renders:
  - math-only annotations through `LaTeXSwiftUI.LaTeX.renderToImages`
  - mixed text/math annotations by parsing inline math, rendering math segments through MathJax, and compositing text plus math into one `NSImage`
- Math rendering uses `displayScale = 4`.
- Math x-height currently uses `max(fontSize * 0.45, 1)`.

### 4.3 Rendered Sizing Modes

`RenderedAnnotation` distinguishes between sizing behaviors:

- `naturalSize`: math-only rendered images should keep their natural rendered symbol size.
- `wrapsToWidth`: mixed text/math and Core Text fallback annotations should use the current annotation width for line wrapping.

Resize behavior:

- Math-only annotations snap back to the natural rendered symbol bounds after resize release. This prevents distortion.
- Mixed text/math annotations preserve the dragged width and recompute automatic line breaks.
- Plain fallback annotations preserve the dragged width and wrap through Core Text line breaking.

### 4.4 Mixed Text/Math Layout

Mixed annotations currently support inline math delimiters:

- `$...$`
- `\(...\)`

Display delimiters and block-like structures still work best as math-only annotations.

The mixed renderer uses MathJax SVG geometry for inline baseline alignment:

- `MathJaxSwift` is imported directly in `AnnoTex.swift`.
- A private `MathJax` instance with `.svg` output is used only for metrics.
- SVG metrics are parsed from the MathJax `<svg>` element:
  - `width`
  - `height`
  - CSS `vertical-align`
- Geometry is cached per LaTeX snippet in `svgGeometryCache`.
- The rendered bitmap still comes from `LaTeXSwiftUI.LaTeX.renderToImages`.
- Baseline calculation:
  - MathJax SVG `vertical-align` gives TeX depth in `ex` units.
  - `depth = -verticalAlignment * xHeight`, scaled to actual image height.
  - `baseline = imageHeight - depth`.
- A bounded optical correction is applied for shallow, compact inline math.

Known issue:

- Some larger operators still align too high in mixed text. Example:
  - `Consider $\bigoplus_p E^\infty_{p, n-p}$ the graded complex`
- Future fixes should be systemic and metric based. Do not add command-specific patches for `\bigoplus`.

### 4.5 Mixed Raster Quality

- Mixed text/math annotations still composite through `NSImage.lockFocus()` to preserve existing AppKit drawing behavior.
- Before focusing the image, the renderer adds a high-resolution `NSBitmapImageRep` whose pixel dimensions are based on `displayScale`.
- This preserves the original drawing coordinate behavior while improving mixed-output backing resolution.
- A prior attempt to replace `lockFocus()` with a direct bitmap graphics context broke mixed text rendering. Avoid repeating that exact approach unless the coordinate-system behavior is carefully reproduced and manually verified.

## 5. Supported Math Behavior

The MathJax path supports broad LaTeX math for math-only annotations and inline math inside mixed annotations.

Supported examples include:

- `A \Rightarrow B`
- `$A \Rightarrow B$`
- `Let $A \Rightarrow B$ and $x \in \mathbb{R}$`
- `Let $f(x) = x^2$ be a function`
- `Let $f: M \to N$ be a map`
- `\frac{x}{y}`
- `\sqrt{x}`
- `\mathbb{R}`, `\mathcal{F}`, and other MathJax-supported math alphabet commands
- Many AMS-style symbols and environments supported by MathJax

Important mixed-baseline regression examples:

- `Let $f(x) = x^2$ be a function`
- `Let $f: M \to N$ be a map`
- `For $x \in \mathbb{R}$, $x^2 \ge 0$`
- `Text before $\frac{a}{b}$ text after`
- `Consider $\bigoplus_p E^\infty_{p, n-p}$ the graded complex`

## 6. Current Limitations

### 6.1 Image-Based Rendering

The MathJax path currently renders to `NSImage`. This is acceptable for interactive testing and current app state, but it is not the final fidelity target.

Known effects:

- Math-only and mixed-text annotations may differ slightly in perceived resolution.
- Mixed annotations composite text and math into a second image.
- Saved PDF appearance depends on PDFKit writing the image-backed annotation appearance.

Required future direction:

- Preserve MathJax SVG output or convert it to PDF/vector drawing.
- Embed vector-like appearance streams in saved PDFs where possible.
- Keep high-resolution raster output only as a compatibility fallback.

### 6.2 Baseline Alignment

The current SVG metric path is better than the old `image.height * 0.72` heuristic, but it is still a mixed raster/text approximation rather than a full TeX paragraph layout engine.

Future direction:

- Keep MathJax/SVG metrics as the source of truth.
- Improve handling for large operators and deep sub/superscript combinations.
- Use global geometry/font rules, such as operator height, depth, ascender/descender, and text x-height.
- Do not patch individual commands, glyphs, letters, or symbols.

### 6.3 Plain Text Font Fidelity

- Plain text in mixed annotations currently uses Times New Roman fallback behavior.
- This is not identical to real LaTeX text.

Future direction:

- Evaluate using a bundled LaTeX-like text font such as Latin Modern Roman or New Computer Modern.
- Keep the raw editor fixed-width Menlo regardless of rendered font selection.
- Recheck all baseline examples after any text-font change because font ascender/descender/x-height metrics affect optical alignment.

### 6.4 Renderer Architecture

- Renderer responsibilities are still concentrated in `AnnoTex.swift`.
- `MathPDFView` and `LaTeXAnnotation` still depend indirectly on the current renderer structure.

Future direction:

- Split renderer responsibilities behind protocols/types:
  - source parsing
  - MathJax image rendering
  - MathJax SVG metric extraction
  - mixed text layout
  - PDF/vector appearance generation
- Keep `MathPDFView` and `LaTeXAnnotation` independent of backend details.
- Make it possible to swap image, SVG, and PDF/vector backends without changing annotation editing logic.

## 7. User Constraints and Preferences

- The raw annotation editor must remain fixed-size monospaced text.
- The rendered font size slider must affect only rendered output, not the editor.
- Plain text and MathJax-rendered math should resize synchronously.
- Enter in the editor must insert a manual line break.
- `Command+Enter` in the editor should render.
- Normal Save should preserve AnnoTex re-editability.
- Other PDF readers only need to display annotations correctly; they do not need to edit AnnoTex source.
- Flattened export may be added later as a separate command, not as the default save behavior.
- Prefer real TeX/MathJax-backed implementation over manually patching commands, letters, symbols, or fonts.
- Baseline fixes should be systemic and metric based.

## 8. Verification Commands

Use branch-specific derived data paths when multiple agents are building simultaneously.

For `master`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

For `palette-color-wheel`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-palette CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

Notes for future agents:

- The local machine may have `xcode-select` pointed at Command Line Tools. Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for project builds.
- Xcode/SwiftPM may need access to user cache directories outside the workspace.
- Full scheme `test` has previously failed in the Codex desktop sandbox because the UI test runner could not bootstrap. The failure was environmental, not a compile failure. Use `-only-testing:AnnoTexTests` for reliable local regression checks unless UI testing is explicitly needed.
- A pre-existing warning remains: `removeAllAppearanceStreams()` is deprecated in macOS 10.12.

## 9. Implementation Warnings For Future Agents

- Do not replace the current mixed `lockFocus()` composition with a direct CGContext unless you verify coordinate orientation and text drawing behavior manually.
- Do not grow `NativeAnnotationRenderer` into a TeX parser.
- Do not add symbol-specific baseline patches.
- Do not make flattened export the default save path.
- Do not change the raw editor font when changing rendered annotation fonts.
- Do not reintroduce rendered text color to `master`; use `palette-color-wheel`.
