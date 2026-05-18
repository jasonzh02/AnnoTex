# Product Requirements Document (PRD) - AnnoTex

## 1. Overview
AnnoTex is a macOS PDF reader and annotation app for writing mixed plain text and LaTeX-style math directly on PDF documents. The product goal is a lightweight academic reading workflow: users can open a PDF, add editable math annotations, adjust rendered size, save the PDF, and later reopen the same file in AnnoTex to continue editing annotations.

The rendering goal is high-fidelity inline math: plain text and math should share a stable baseline, remain sharp while zooming, and visually resemble standard LaTeX output.

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

### 2.4 Native Rendering Pipeline
- The previous MathJax / SVG / bitmap path has been removed from active annotation rendering.
- Annotations now render through a native Core Text based renderer:
  - `NativeAnnotationRenderer` parses mixed plain text and inline `$...$` math.
  - `RenderedAnnotation` stores Core Text lines and metrics.
  - `LaTeXAnnotation.draw` draws Core Text glyphs directly into the PDF graphics context.
- This native drawing path improves zoom sharpness and baseline stability because annotations no longer draw scaled `NSImage` bitmaps.

### 2.5 Supported Math Subset
The current native renderer supports a practical first subset:
- Plain text mixed with inline dollar math, e.g. `Let $x^2 + y^2 = r^2$`.
- Superscripts and subscripts using `^` and `_`, including braced scripts.
- Common Greek commands such as `\alpha`, `\beta`, `\Gamma`, and `\Omega`.
- Common operators and symbols such as `\sum`, `\int`, `\infty`, `\leq`, `\neq`, and arrows.
- Simple inline fractions using `\frac{a}{b}`.
- Manual line breaks.

This is not yet a full TeX engine. Complex environments, matrices, roots, delimiter sizing, display math, and advanced macros remain future work.

## 3. Current Limitations and Required Improvements

### 3.1 LaTeX Font Fidelity
The current renderer uses system serif glyphs, currently Times New Roman fallback behavior, which makes math resemble macOS / Microsoft Word-style equation text more than default LaTeX. The desired output should use default LaTeX-like Computer Modern style.

Required improvement:
- Bundle or depend on real TeX math fonts, preferably Latin Modern Math or New Computer Modern Math.
- Use a Computer Modern-compatible text font for plain annotation text.
- Use a matching OpenType MATH font for math symbols and layout where possible.
- Update the renderer font selection so ordinary text, Greek symbols, operators, superscripts, subscripts, and fractions share a coherent LaTeX-style font system.

### 3.2 Math Alphabet Support
The renderer does not yet properly support math alphabet commands such as:
- `\mathbb`
- `\mathfrak`
- `\mathcal`
- Potentially `\mathrm`, `\mathbf`, `\mathit`, and `\mathsf`

Required improvement:
- Extend the parser to recognize math alphabet commands with braced arguments, e.g. `\mathbb{R}` and `\mathfrak{g}`.
- Map supported Latin letters and digits to appropriate Unicode Mathematical Alphanumeric Symbols when reliable.
- Use dedicated fallback fonts for alphabets where Unicode coverage is missing or poor.
- Preserve baseline alignment and sizing when alphabet styles appear inline with normal math.
- Define a graceful fallback for unsupported characters by rendering the original character in the closest available math font rather than dropping content.

### 3.3 Full Math Layout
The current renderer approximates some math layout with attributed text and baseline offsets. This is a good first native step, but a complete LaTeX-like renderer needs more robust math layout.

Future requirements:
- Better fraction layout with true stacked numerator/denominator for display-like cases.
- Square roots and n-th roots.
- Scalable delimiters.
- Matrices and aligned equations.
- Macro expansion for common user-defined shortcuts.
- Optional integration with a proven native math layout engine if maintaining a custom renderer becomes too costly.

### 3.4 Project Cleanup
- The Xcode project still references the local `LaTeXSwiftUI` package, though active annotation rendering no longer imports it.
- Once the native renderer is stable, remove unused package dependencies and any obsolete scratch rendering experiments.

## 4. User Constraints and Preferences
- The raw annotation editor must remain fixed-size monospaced text.
- The rendered font size slider must affect only rendered output, not the editor.
- Enter in the editor must insert a manual line break.
- Normal Save should preserve AnnoTex re-editability.
- Other PDF readers only need to display annotations correctly; they do not need to edit AnnoTex source.
- Flattened export may be added later as a separate command, not as the default save behavior.

## 5. Next Milestones

### Milestone 1: Computer Modern Font Integration
- Choose and bundle a LaTeX-like font family.
- Prefer Latin Modern Roman for text and Latin Modern Math or New Computer Modern Math for math.
- Register bundled fonts at app startup.
- Update `NativeAnnotationRenderer` to select these fonts explicitly.
- Verify visual comparison against standard LaTeX inline math examples.

### Milestone 2: Math Alphabet Commands
- Add parser support for braced math alphabet commands.
- Implement Unicode/fallback-font mapping for `\mathbb`, `\mathfrak`, and `\mathcal`.
- Add acceptance examples:
  - `$\mathbb{R}$`
  - `$\mathbb{N} \subset \mathbb{R}$`
  - `$\mathfrak{g}$`
  - `$\mathcal{F}$`
- Confirm alphabet runs stay baseline-aligned with surrounding text.

### Milestone 3: Broader Native Math Layout
- Improve fractions, roots, delimiters, and multi-line math structures.
- Decide whether to continue evolving the custom Core Text renderer or integrate a dedicated native math layout engine.
- Keep PDF appearance stream compatibility and AnnoTex re-editability intact.
