# Product Requirements Document (PRD) - AnnoTex

## 1. Product Goal
AnnoTex is a macOS PDF reader and annotation app for writing editable text and LaTeX-style math directly on PDF documents. The core academic workflow is:

1. Open a PDF.
2. Add editable text/math annotations.
3. Resize rendered annotation output without changing the raw editor font.
4. Save the PDF with portable visible annotation appearances.
5. Reopen the same PDF in AnnoTex and continue editing the original annotation source.

The rendering goal is high-fidelity LaTeX-like output. Math should support broad TeX/LaTeX syntax through MathJax, visually resemble standard LaTeX inline and display math, remain sharp enough while zooming, and preserve editable source metadata inside saved PDFs.

## 2. Current Implementation Snapshot

### 2.1 PDF Viewing, Editing, and Persistence
- The app uses `PDFKit` for PDF display and annotation management.
- The main PDF surface is `MathPDFView`, a custom `PDFView` subclass.
- Users can:
  - Open PDFs through `NSOpenPanel`.
  - Enter Add Math Mode and click a page to create an annotation.
  - Edit annotations in a floating dark `NSPanel`.
  - Select, move, resize, delete, and double-click edit annotations.
  - Adjust rendered annotation size with a toolbar slider.
  - Save PDFs through the normal portable save path.
- The raw editor uses fixed-size monospaced Menlo. The rendered size slider must not change the editor font.
- Pressing Enter in the editor inserts a manual line break.

### 2.2 Annotation Data Model
- Custom annotations are represented by `LaTeXAnnotation`, a `PDFAnnotation` subclass using the standard `/Stamp` subtype.
- AnnoTex stores private PDF annotation metadata for re-editability:
  - `/AnnoTexKind`
  - `/AnnoTexSource`
  - `/AnnoTexFontSize`
  - `/AnnoTexRendererVersion`
  - `/AnnoTexMetadataVersion`
  - `/AnnoTexLayoutBounds`
- Normal PDF annotations from other readers are not blindly converted into AnnoTex annotations.
- Only annotations with AnnoTex metadata are rehydrated as editable AnnoTex annotations.

### 2.3 Save Behavior
- Normal Save syncs AnnoTex metadata, clears stale appearance streams, and lets PDFKit write annotation appearance streams.
- Saved PDFs should display annotations in other PDF readers.
- Only AnnoTex needs to preserve/edit original annotation source.
- Maximum-compatibility flattening is not implemented and must remain a separate export mode because flattening sacrifices AnnoTex editability.

## 3. Rendering Architecture

### 3.1 Renderer Entry Points
- `NativeAnnotationRenderer.render(...)` is still the public fallback entry point used by `MathPDFView`.
- `NativeAnnotationRenderer` first tries `MathJaxAnnotationRenderer.shared.render(source:fontSize:)`.
- If MathJax rendering fails, the native Core Text fallback path is used.
- The native fallback contains a small handwritten math subset. Do not grow it into a TeX implementation.

### 3.2 MathJax Rendering
- The project depends on `LaTeXSwiftUI`, which brings in:
  - `MathJaxSwift`
  - `SwiftDraw`
  - `swift-html-entities`
- `MathJaxAnnotationRenderer` renders:
  - math-only annotations through `LaTeXSwiftUI.LaTeX.renderToImages`
  - mixed text/math annotations by parsing inline math, rendering math segments through MathJax, and compositing text plus math into one `NSImage`
- Math rendering uses `displayScale = 4`.
- Math x-height currently uses `max(fontSize * 0.45, 1)`.

### 3.3 Mixed Text/Math Layout
Mixed annotations currently support inline math delimiters:

- `$...$`
- `\(...\)`

Display delimiters and block-like structures still work best as math-only annotations.

The mixed renderer now uses MathJax SVG geometry for inline baseline alignment:

- `MathJaxSwift` is imported directly in `AnnoTex.swift`.
- A private `MathJax` instance with `.svg` output is used only for metrics.
- SVG metrics are parsed from the MathJax `<svg>` element:
  - `width`
  - `height`
  - CSS `vertical-align`
- Geometry is cached per LaTeX snippet in `svgGeometryCache`.
- The rendered bitmap still comes from `LaTeXSwiftUI.LaTeX.renderToImages`.
- Baseline calculation:
  - MathJax SVG `vertical-align` gives the TeX depth in `ex` units.
  - `depth = -verticalAlignment * xHeight`, scaled to the actual image height.
  - `baseline = imageHeight - depth`.
- A bounded optical correction is applied only for shallow, compact inline math. This fixes expressions such as `Let $f: M \to N$ be a map`, where technically correct SVG depth can still look slightly high against Times New Roman text.
- The correction is font-aware and geometry-aware, not command-specific. Do not add one-off offsets for `\to`, `:`, letters, or symbols.
- Examples checked manually by the user:
  - `Let $f(x) = x^2$ be a function` aligns as desired.
  - `Let $f: M \to N$ be a map` needed the shallow inline optical correction and is acceptable for now.

### 3.4 Mixed Raster Quality
- Mixed text/math annotations still composite through `NSImage.lockFocus()` to preserve existing AppKit drawing behavior.
- Before focusing the image, the renderer adds a high-resolution `NSBitmapImageRep` whose pixel dimensions are based on `displayScale`.
- This preserves the original drawing coordinate behavior while improving mixed-output backing resolution.
- A prior attempt to replace `lockFocus()` with a direct bitmap graphics context broke mixed text rendering. Avoid repeating that exact approach unless the coordinate-system behavior is carefully reproduced and manually verified.

### 3.5 RenderedAnnotation Drawing
- `RenderedAnnotation` can draw either:
  - a MathJax-rendered/composited `NSImage`, or
  - Core Text lines from the native fallback path.
- The current MathJax path is image-based. It is not yet a direct vector/SVG/PDF appearance stream.

## 4. Supported Math Behavior
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

## 5. Current Limitations

### 5.1 Image-Based Rendering
The MathJax path currently renders to `NSImage`. This is acceptable for interactive testing and good enough for the current app state, but it is not the final fidelity target.

Known effects:

- Math-only and mixed-text annotations may differ slightly in perceived resolution.
- Mixed annotations composite text and math into a second image.
- Saved PDF appearance depends on PDFKit writing the image-backed annotation appearance.

Required future direction:

- Preserve MathJax SVG output or convert it to PDF/vector drawing.
- Embed vector-like appearance streams in saved PDFs where possible.
- Keep high-resolution raster output only as a compatibility fallback.

### 5.2 Baseline Alignment
The current SVG metric path is substantially better than the old `image.height * 0.72` heuristic, but it is still a mixed raster/text approximation rather than a full TeX paragraph layout engine.

Important constraints:

- Keep MathJax/SVG metrics as the source of truth.
- Keep optical correction global, bounded, and geometry/font based.
- Do not patch individual commands, glyphs, letters, or symbols.
- Re-test both shallow and tall formulas after every change:
  - `Let $f(x) = x^2$ be a function`
  - `Let $f: M \to N$ be a map`
  - `For $x \in \mathbb{R}$, $x^2 \ge 0$`
  - `Text before $\frac{a}{b}$ text after`

### 5.3 Plain Text Font Fidelity
- Plain text in mixed annotations currently uses Times New Roman fallback behavior.
- This is not identical to real LaTeX text.

Future direction:

- Decide whether rendered plain text should use a bundled LaTeX-like text font such as Latin Modern Roman or New Computer Modern.
- Keep the raw editor fixed-width Menlo regardless of rendered font selection.
- Ensure the rendered size slider affects plain text and math together.

### 5.4 Renderer Architecture
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

## 6. User Constraints and Preferences
- The raw annotation editor must remain fixed-size monospaced text.
- The rendered font size slider must affect only rendered output, not the editor.
- Plain text and MathJax-rendered math should resize synchronously.
- Enter in the editor must insert a manual line break.
- Normal Save should preserve AnnoTex re-editability.
- Other PDF readers only need to display annotations correctly; they do not need to edit AnnoTex source.
- Flattened export may be added later as a separate command, not as the default save behavior.
- Prefer real TeX/MathJax-backed implementation over manually patching commands, letters, symbols, or fonts.
- Baseline fixes should be systemic and metric based.

## 7. Verification Status
Current verified commands:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

Both commands succeeded after the current mixed baseline/raster updates.

Notes for future agents:

- The local machine may have `xcode-select` pointed at Command Line Tools. Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for project builds.
- Xcode/SwiftPM may need access to user cache directories outside the workspace.
- Full scheme `test` has previously failed in the Codex desktop sandbox because the UI test runner could not bootstrap. The failure was environmental, not a compile failure. Use `-only-testing:AnnoTexTests` for reliable local regression checks unless UI testing is explicitly needed.
- A pre-existing warning remains: `removeAllAppearanceStreams()` is deprecated in macOS 10.12.

## 8. Recommended Next Milestones

### Milestone 1: Manual Visual QA For Mixed Baselines
Manually run the app and test mixed annotations on a PDF:

- `Let $f(x) = x^2$ be a function`
- `Let $f: M \to N$ be a map`
- `For $x \in \mathbb{R}$, $x^2 \ge 0$`
- `Text before $\frac{a}{b}$ text after`

Acceptance:

- Shallow math should not float above surrounding text.
- Tall math should increase line height naturally rather than being forced downward.
- The rendered size slider should keep text and math in sync.

### Milestone 2: Plain Text Font Fidelity
- Evaluate using a bundled LaTeX-like text font for mixed annotation plain text.
- Prefer Latin Modern Roman or New Computer Modern if licensing and bundling are acceptable.
- Keep editor font Menlo.
- Recheck all baseline examples after any text-font change because font ascender/descender/x-height metrics affect optical alignment.

### Milestone 3: Renderer Decomposition
Create explicit renderer components:

- `InlineMathParser`
- `MathJaxImageRenderer`
- `MathJaxSVGMetricProvider`
- `MixedAnnotationLayout`
- `AnnotationAppearanceRenderer`

Acceptance:

- `MathPDFView` should not need to know whether rendering uses image, SVG, or PDF/vector backends.
- MathJax/SVG metrics should stay cached and reusable.

### Milestone 4: Vector PDF Appearance Streams
- Render MathJax SVG as vector content for annotation drawing and saving.
- Investigate SVG-to-PDF conversion or direct Core Graphics drawing through `SwiftDraw`.
- Ensure saved PDFs display correctly in Preview and other PDF readers without requiring MathJax or AnnoTex.
- Keep AnnoTex metadata for re-editability.

### Milestone 5: Save/Export Modes
- Keep normal Save as editable AnnoTex PDF with portable annotation appearances.
- Add a separate flattened export mode for maximum compatibility.
- Verify both modes on another machine and in non-AnnoTex PDF readers.

## 9. Implementation Warnings For Future Agents
- Do not replace the current mixed `lockFocus()` composition with a direct CGContext unless you verify coordinate orientation and text drawing behavior manually.
- Do not grow `NativeAnnotationRenderer` into a TeX parser.
- Do not add symbol-specific baseline patches.
- Do not make flattened export the default save path.
- Do not change the raw editor font when changing rendered annotation fonts.
