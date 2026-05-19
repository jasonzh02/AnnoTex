# AnnoTex PRD

Shared product and workflow notes for all branches. Branch-specific handoff state lives in:

- `PRD.master.md`
- `PRD.palette-color-wheel.md`

New agents should read this file plus the file for their branch.

## Product Goal

AnnoTex is a macOS PDF reader and annotation app for writing editable text and LaTeX-style math directly on PDF documents.

Core workflow:

1. Open a PDF.
2. Click `Add Annotation`.
3. Click a page to create an editable annotation.
4. Type plain text, math-only LaTeX, or mixed text/math source in the editor panel.
5. Render the annotation.
6. Move, resize, and adjust rendered font size without changing the raw editor font.
7. Save a PDF with visible portable annotation appearances.
8. Reopen the PDF in AnnoTex and continue editing original annotation source.

Math should use MathJax-backed rendering where possible, visually resemble LaTeX, stay sharp enough while zooming, and preserve editable source metadata in saved PDFs.

## Branches

`master`
: Stable core branch. Owns PDF viewing/saving, annotation creation/editing/moving/resizing/deletion, MathJax rendering, mixed text/math layout, selection behavior, keyboard shortcuts, and basic editor workflow. Do not add rendered text color functionality here.

`palette-color-wheel`
: Experimental rendered text color branch. Owns color UI, color metadata, and colored rendering. Pull or cherry-pick non-color core fixes from `master` as needed. Do not blindly merge changes that remove color functionality unless retiring the branch.

Use separate worktrees for simultaneous agents:

```sh
git worktree add ../AnnoTex-master master
git worktree add ../AnnoTex-palette palette-color-wheel
```

Use separate derived data paths if building both branches:

```sh
-derivedDataPath /private/tmp/AnnoTexDerivedData-master
-derivedDataPath /private/tmp/AnnoTexDerivedData-palette
```

## PRD Maintenance

PRD files are handoff checkpoints, not implementation logs. Do not update them during every small code change. Update them only when the user asks, typically before a commit, and keep updates concise:

- current behavior that a next agent must know
- active branch-specific next steps
- non-obvious architecture decisions or warnings
- latest meaningful verification status

Compress or remove outdated detail when updating.

## Core Architecture Notes

- UI is SwiftUI hosting a custom `PDFView` subclass, `MathPDFView`.
- Custom editable annotations are `LaTeXAnnotation`, a `PDFAnnotation` subclass using `/Stamp`.
- Re-editability is stored in private PDF annotation metadata:
  - `/AnnoTexKind`
  - `/AnnoTexSource`
  - `/AnnoTexFontSize`
  - `/AnnoTexRendererVersion`
  - `/AnnoTexMetadataVersion`
  - `/AnnoTexLayoutBounds`
- Only annotations with AnnoTex metadata should be rehydrated as editable AnnoTex annotations.
- Normal Save should preserve AnnoTex editability and produce portable visible annotation appearances.
- Flattened export, if added, must be a separate mode because flattening sacrifices editability.
- `removeAllAppearanceStreams()` is deprecated but currently helps force regenerated portable appearances. Do not remove it without manual saved-PDF verification in Preview/Acrobat.

## Rendering Notes

- Public renderer entry point on `master`: `NativeAnnotationRenderer.render(source:width:fontSize:)`.
- Renderer tries MathJax first via `MathJaxAnnotationRenderer`, then falls back to a small Core Text path.
- Do not grow the fallback into a TeX implementation.
- Mixed text/math supports inline `$...$` and `\(...\)`.
- Mixed layout uses MathJax SVG metrics for baseline alignment and MathJax/LaTeXSwiftUI images for rendered math.
- Known baseline stress case: `Consider $\bigoplus_p E^\infty_{p, n-p}$ the graded complex`.
- Baseline fixes should be systemic and metric-based. Do not patch individual commands, glyphs, or symbols.
- Mixed rendering currently relies on `NSImage.lockFocus()` behavior. Do not replace it with a direct CGContext path without carefully reproducing coordinate behavior and manually verifying mixed text rendering.

## User Constraints

- Raw editor font stays fixed-size monospaced Menlo.
- Rendered font size slider affects rendered output only, not the editor.
- Plain text and MathJax-rendered math should resize synchronously.
- Enter inserts a manual line break.
- `Command+Enter` renders.
- `Esc` exits Add Annotation mode.
- Add Annotation mode should show a crosshair cursor over the PDF view.

## Verification

The reliable full verification commands are:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project AnnoTex.xcodeproj -scheme AnnoTex -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/AnnoTexDerivedData-master CODE_SIGNING_ALLOWED=NO test -only-testing:AnnoTexTests
```

For fast UI iteration, the user may manually build/test in Xcode. In that case, use lightweight checks such as `git diff --check` plus source inspection unless the user asks for full `xcodebuild`.
