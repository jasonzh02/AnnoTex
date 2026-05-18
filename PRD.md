# Product Requirements Document (PRD) - AnnoTex

## 1. Overview
AnnoTex is a macOS PDF reader and annotation app for writing editable text and LaTeX-style math directly on PDF documents. The product goal is a lightweight academic reading workflow: users can open a PDF, add math annotations, adjust rendered size, save the PDF, and later reopen the same file in AnnoTex to continue editing annotation source.

The rendering goal is high-fidelity LaTeX math: annotation math should support broad TeX/LaTeX syntax, visually resemble standard LaTeX output, remain sharp enough while zooming, and preserve editable source metadata inside the saved PDF.

## 2. Current Implementation

### 2.1 PDF Viewing, Editing, and Persistence
- Uses `PDFKit` for PDF display and annotation management.
- The main PDF surface is a custom `PDFView` subclass, `MathPDFView`.
- Users can:
  - Open PDFs through `NSOpenPanel`.
  - Enter Add Math Mode and click a page to create an annotation.
  - Edit annotations in a floating dark `NSPanel`.
  - Select, move, resize, delete, and double-click edit annotations.
  - Adjust rendered annotation size with a toolbar slider.
  - Save PDFs through a portable save path.
- The editor uses a fixed-size monospaced `NSTextView` font, currently Menlo, so the editor font does not change when the rendered font size changes.
- Pressing Enter in the editor creates a manual line break.

### 2.2 Annotation Data Model
- Custom annotations are represented by `LaTeXAnnotation`, a `PDFAnnotation` subclass using the standard `/Stamp` subtype.
- AnnoTex stores private PDF annotation metadata for re-editability:
  - `/AnnoTexKind`
  - `/AnnoTexSource`
  - `/AnnoTexFontSize`
  - `/AnnoTexRendererVersion`
  - `/AnnoTexMetadataVersion`
  - `/AnnoTexLayoutBounds`
- Normal PDF annotations from other readers are no longer blindly converted into AnnoTex annotations. Only annotations with AnnoTex metadata are rehydrated as editable AnnoTex annotations.

### 2.3 Portable PDF Rendering
- The normal Save path syncs AnnoTex metadata, clears stale appearance streams, and lets PDFKit write annotation appearance streams.
- Saved PDFs are intended to display annotations in other PDF readers, while the source remains re-editable only in AnnoTex.
- Maximum-compatibility flattening is not implemented yet and should remain a separate export mode because it would sacrifice AnnoTex editability.

### 2.4 Rendering Pipeline
- Active rendering now tries a MathJax-backed path first.
- The Xcode project depends on `LaTeXSwiftUI`, which brings in:
  - `MathJaxSwift`
  - `SwiftDraw`
  - `swift-html-entities`
- `MathJaxAnnotationRenderer` renders math-only annotations and mixed text/math annotations through `LaTeXSwiftUI.LaTeX.renderToImages`.
- `RenderedAnnotation` can draw either:
  - a MathJax-rendered `NSImage`, or
  - Core Text lines from the native fallback path.
- `NativeAnnotationRenderer` remains as a fallback when MathJax rendering or mixed parsing fails.
- MathJax output is currently image-based at high display scale, not yet a direct vector/SVG/PDF appearance stream.

### 2.5 Supported Math Behavior
The current MathJax path supports broad LaTeX math for math-only annotations and inline math inside mixed annotations.

Supported examples include:
- `A \Rightarrow B`
- `$A \Rightarrow B$`
- `Let $A \Rightarrow B$ and $x \in \mathbb{R}$`
- `\frac{x}{y}`
- `\sqrt{x}`
- `\mathbb{R}`, `\mathcal{F}`, and other MathJax-supported math alphabet commands.
- Many AMS-style symbols and environments supported by MathJax.

Mixed annotations currently support inline math delimiters:
- `$...$`
- `\(...\)`

Display delimiters and block-like structures work best as math-only annotations for now.

### 2.6 Project Cleanup
- Removed obsolete root-level scratch scripts, one-off Swift experiments, compiled scratch binaries, and build logs.
- Added ignore rules for regenerated scratch files, logs, build products, SwiftPM caches, local package checkouts, and Xcode user state.
- Added an Xcode SwiftPM `Package.resolved` lockfile so the package versions that built successfully are pinned.
- The app currently uses the remote `LaTeXSwiftUI` package reference. The old checked-out local copy under `AnnoTex/LocalPackages` was removed.

## 3. Current Limitations

### 3.1 Image-Based Rendering
The MathJax path currently renders to `NSImage`. This is acceptable for interactive testing and visually good for math-only annotations, but it is not the final fidelity target.

Known effects:
- Math-only annotations and mixed-text annotations may differ slightly in perceived resolution.
- Mixed annotations composite text and math into a second image, which can soften math compared with the math-only path.
- Saved PDF appearance depends on PDFKit writing the image-backed annotation appearance.

Required direction:
- Preserve MathJax SVG output or convert it to PDF/vector drawing instead of relying on bitmap images.
- Embed vector-like appearance streams in saved PDFs where possible.
- Keep high-resolution raster output only as a compatibility fallback.

### 3.2 Baseline Alignment in Mixed Text
Mixed annotations currently align MathJax math segments with plain text using a heuristic baseline estimate.

Known effects:
- Inline math in mixed annotations can appear slightly above the surrounding plain text.
- The baseline can vary depending on the math expression height.

Required direction:
- Expose or recover MathJax SVG geometry, including vertical alignment/depth metrics.
- Use those metrics to align each math segment to the text baseline.
- Avoid manual per-symbol or per-command alignment fixes.

### 3.3 Plain Text Font Fidelity
Plain text in mixed annotations still uses the existing serif fallback behavior. The main visual improvement currently comes from MathJax-rendered math.

Required direction:
- Decide whether plain annotation text should use a bundled LaTeX-like text font such as Latin Modern Roman.
- Keep editor font fixed-width Menlo regardless of rendered font selection.
- Ensure the rendered font-size slider affects plain text and math together.

### 3.4 Renderer Architecture
The old native Core Text parser still exists as fallback and contains a small hand-written math subset. It should not grow into a full TeX implementation.

Required direction:
- Treat MathJax or another proven TeX engine as the source of truth for math rendering.
- Keep native rendering only as fallback for simple text or for failure recovery.
- Avoid adding one-off command dictionaries or manual glyph mappings for individual LaTeX commands.

## 4. User Constraints and Preferences
- The raw annotation editor must remain fixed-size monospaced text.
- The rendered font size slider must affect only rendered output, not the editor.
- Plain text and MathJax-rendered math should resize synchronously.
- Enter in the editor must insert a manual line break.
- Normal Save should preserve AnnoTex re-editability.
- Other PDF readers only need to display annotations correctly; they do not need to edit AnnoTex source.
- Flattened export may be added later as a separate command, not as the default save behavior.
- Prefer a real TeX/MathJax-backed implementation over manually patching individual commands, letters, or fonts.

## 5. Verification Status
- `xcodebuild -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData CODE_SIGNING_ALLOWED=NO build` succeeded.
- `xcodebuild -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData CODE_SIGNING_ALLOWED=NO test` succeeded.
- Manual Xcode testing confirmed:
  - Math-only annotations render with acceptable quality.
  - Mixed text/math annotations render through MathJax for the math parts.
  - The rendered size slider changes plain text and math synchronously.
  - Remaining concerns are mixed-text math resolution and baseline alignment.

## 6. Next Milestones

### Milestone 1: Improve Mixed-Text Raster Quality
- Replace `NSImage.lockFocus()` mixed composition with an explicit high-resolution bitmap context.
- Match mixed composition scale to the MathJax segment render scale.
- Avoid an extra low-resolution composition pass.
- Retest math-only versus mixed-text perceived sharpness.

### Milestone 2: SVG/Metric-Based Baseline Alignment
- Expose MathJax SVG geometry from the rendering layer or add a local SVG-render result type.
- Capture width, height, baseline/depth, and vertical alignment for each math segment.
- Align inline math against surrounding plain text using real metrics instead of the current heuristic.
- Add acceptance examples:
  - `Let $f(x) \Rightarrow y$`
  - `For $x \in \mathbb{R}$, $x^2 \ge 0$`
  - `Text before $\frac{a}{b}$ text after`

### Milestone 3: Vector PDF Appearance Streams
- Render MathJax SVG as vector content for annotation drawing and saving.
- Investigate SVG-to-PDF conversion or direct Core Graphics drawing through `SwiftDraw`.
- Ensure saved PDFs display correctly in Preview and other PDF readers without requiring MathJax or AnnoTex.
- Keep AnnoTex metadata for re-editability.

### Milestone 4: Renderer Abstraction
- Split renderer responsibilities behind a protocol, for example:
  - source parsing
  - MathJax rendering
  - mixed text layout
  - PDF appearance generation
- Keep `MathPDFView` and `LaTeXAnnotation` independent of renderer implementation details.
- Make it possible to swap image, SVG, and PDF/vector backends without changing annotation editing logic.

### Milestone 5: Save/Export Modes
- Keep normal Save as editable AnnoTex PDF with portable annotation appearances.
- Add a separate flattened export mode for maximum compatibility.
- Verify both modes on another machine and in non-AnnoTex PDF readers.
