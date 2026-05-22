//
//  AnnoTexTests.swift
//  AnnoTexTests
//
//  Created by Jason Zhong on 5/13/26.
//

import Testing
import AppKit
@testable import AnnoTex

struct AnnoTexTests {

    @MainActor
    @Test func bracedNumericScriptsRenderWithoutErrorBoxes() async throws {
        let renderer = MathJaxAnnotationRenderer.shared
        let sources = ["H_{1}", "H_{n-1}", "H^{1}", "H^{n-1}"]

        for source in sources {
            let rendered = NativeAnnotationRenderer.shared.render(source: source, width: 250, fontSize: 12)
            #expect(rendered?.image != nil, "\(source) should render through MathJax image output")
            #expect(rendered?.lines.isEmpty == true, "\(source) should not fall back to CoreText")

            let svg = try #require(renderer.debugMathSVG(for: source))
            #expect(!svg.contains("merror"), "\(source) should not produce a MathJax error SVG")
        }
    }

    @MainActor
    @Test func mixedBracedScriptsRenderThroughMathJax() async throws {
        let source = "Consider $H_{n-1}$ and $H_{2n}$"
        let rendered = NativeAnnotationRenderer.shared.render(source: source, width: 320, fontSize: 12)

        #expect(rendered?.image != nil)
        #expect(rendered?.lines.isEmpty == true)

        for latex in ["H_{n-1}", "H_{2n}"] {
            let svg = try #require(MathJaxAnnotationRenderer.shared.debugMathSVG(for: latex))
            #expect(!svg.contains("merror"), "\(latex) should not produce a MathJax error SVG")
        }
    }

    @Test func numericLetterScriptsKeepMathItalicLetters() async throws {
        let svg = try #require(MathJaxAnnotationRenderer.shared.debugMathSVG(for: "H_{2n}"))
        #expect(svg.contains("TEX-I-1D45B") || svg.contains(#"data-c="1D45B""#))
    }

    @MainActor
    @Test func extendedArrowMacrosRenderWithoutErrorBoxes() async throws {
        let sources = [
            #"\xrightarrow{}"#,
            #"\xrightarrow{a}"#,
            #"A \xrightarrow{f} B"#,
            #"\xleftarrow{a}"#
        ]

        for source in sources {
            let rendered = NativeAnnotationRenderer.shared.render(source: source, width: 300, fontSize: 12)
            #expect(rendered?.image != nil, "\(source) should render through MathJax image output")
            #expect(rendered?.lines.isEmpty == true, "\(source) should not fall back to CoreText")

            let svg = try #require(MathJaxAnnotationRenderer.shared.debugMathSVG(for: source))
            #expect(!svg.contains("merror"), "\(source) should not produce a MathJax error SVG")
        }
    }

    @MainActor
    @Test func mixedSimpleMathUsesBaselineDepthInsteadOfImageHeight() async throws {
        let lines = try #require(MathJaxAnnotationRenderer.shared.debugMixedLayoutMetrics(
            for: "Text $x$ text",
            width: 300,
            fontSize: 24
        ))
        let line = try #require(lines.first)
        let mathSegment = try #require(line.segments.first { $0.kind == .math })

        #expect(mathSegment.baselineFromBottom >= 0)
        #expect(mathSegment.baselineFromBottom < max(1, mathSegment.size.height * 0.2))
        #expect(mathSegment.heightAboveBaseline > mathSegment.baselineFromBottom)
    }

    @MainActor
    @Test func mixedTextSegmentsUseFontDescentForBaselineDepth() async throws {
        let fontSize: CGFloat = 24
        let lines = try #require(MathJaxAnnotationRenderer.shared.debugMixedLayoutMetrics(
            for: "Text $x$ text",
            width: 300,
            fontSize: fontSize
        ))
        let line = try #require(lines.first)
        let textSegment = try #require(line.segments.first {
            $0.kind == .text && $0.content == "Text"
        })
        let font = try #require(NSFont(name: "Times New Roman", size: fontSize))

        #expect(abs(textSegment.baselineFromBottom - abs(font.descender)) < 1.5)
        #expect(textSegment.baselineFromBottom < font.ascender * 0.5)
    }

    @MainActor
    @Test func deepInlineMathReservesDepthBelowAndHeightAboveBaseline() async throws {
        let source = #"Consider $\bigoplus_p E^\infty_{p, n-p}$ the graded complex"#
        let rendered = NativeAnnotationRenderer.shared.render(source: source, width: 480, fontSize: 18)
        let lines = try #require(MathJaxAnnotationRenderer.shared.debugMixedLayoutMetrics(
            for: source,
            width: 480,
            fontSize: 18
        ))
        let line = try #require(lines.first)
        let mathSegment = try #require(line.segments.first { $0.kind == .math })

        #expect(rendered?.image != nil)
        #expect(rendered?.lines.isEmpty == true)
        #expect(mathSegment.baselineFromBottom > 0.5)
        #expect(mathSegment.heightAboveBaseline > 0.5)
        #expect(line.baselineFromBottom >= mathSegment.baselineFromBottom)
        #expect(line.heightAboveBaseline >= mathSegment.heightAboveBaseline)
        #expect(abs(line.size.height - (line.baselineFromBottom + line.heightAboveBaseline)) < 0.01)
    }

    @MainActor
    @Test func mixedMathRegressionCasesStillRenderThroughMathJax() async throws {
        let sources = [
            #"Consider $H_{n-1}$ and $H_{2n}$"#,
            #"Map $A \xrightarrow{f} B$ now"#
        ]

        for source in sources {
            let rendered = NativeAnnotationRenderer.shared.render(source: source, width: 360, fontSize: 14)
            let lines = try #require(MathJaxAnnotationRenderer.shared.debugMixedLayoutMetrics(
                for: source,
                width: 360,
                fontSize: 14
            ))

            #expect(rendered?.image != nil, "\(source) should render through MathJax image output")
            #expect(rendered?.lines.isEmpty == true, "\(source) should not fall back to CoreText")
            #expect(lines.flatMap(\.segments).contains { $0.kind == .math })
        }

        for latex in ["H_{n-1}", #"A \xrightarrow{f} B"#] {
            let svg = try #require(MathJaxAnnotationRenderer.shared.debugMathSVG(for: latex))
            #expect(!svg.contains("merror"), "\(latex) should not produce a MathJax error SVG")
        }
    }

    @Test func renderedTextColorHexRoundTripsThroughCanonicalSRGB() async throws {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.35)
        let hex = color.annotexHexString
        let decoded = try #require(NSColor(annotexHexString: hex))

        #expect(hex == "#336699")
        #expect(decoded.annotexHexString == hex)
        #expect(decoded.alphaComponent == 1)
    }

    @Test func renderedTextColorClampsWideGamutComponents() async throws {
        let wideRed = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 0.25)
        let canonical = wideRed.annotexCanonicalRenderedTextColor

        #expect(wideRed.annotexHexString == "#FF0000")
        #expect(canonical.annotexHexString == "#FF0000")
        #expect(canonical.alphaComponent == 1)
    }

    @Test func validRenderedTextColorDecodeDoesNotFallBackToBlack() async throws {
        let decoded = try #require(NSColor(annotexHexString: "#12ABEF"))

        #expect(decoded.annotexHexString == "#12ABEF")
        #expect(decoded.annotexHexString != NSColor.annotexDefaultRenderedTextColor.annotexHexString)
    }

    @MainActor
    @Test func editorRenderedColorDoesNotRestyleRawEditorText() async throws {
        let panel = LaTeXEditorPanel()
        defer {
            panel.onDiscard = nil
            panel.close()
        }

        panel.setText("Text $x$ text")
        panel.setRenderedTextColor(NSColor(srgbRed: 0.9, green: 0.1, blue: 0.2, alpha: 1))
        let textView = try #require(firstSubview(ofType: LaTeXEditorTextView.self, in: panel.contentView))

        #expect(textView.string == "Text $x$ text")
        #expect(textView.textStorage != nil)
        #expect(textView.layoutManager != nil)
        #expect(textView.textContainer != nil)

        let renderedHex = "#E61A33"
        let storedForeground = try #require(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(storedForeground.annotexHexString == LaTeXEditorTextView.fixedTextColor.annotexHexString)
        var foreground = try #require(textView.typingAttributes[.foregroundColor] as? NSColor)
        #expect(foreground.annotexHexString == renderedHex)

        textView.textColor = .red
        var typingAttributes = textView.typingAttributes
        typingAttributes[.foregroundColor] = NSColor.red
        textView.typingAttributes = typingAttributes
        textView.changeColor(nil)

        #expect(textView.textColor?.annotexHexString == LaTeXEditorTextView.fixedTextColor.annotexHexString)
        foreground = try #require(textView.typingAttributes[.foregroundColor] as? NSColor)
        #expect(foreground.annotexHexString == renderedHex)

        textView.insertText("!", replacementRange: NSRange(location: textView.string.count, length: 0))
        #expect(textView.string == "Text $x$ text!")
        let insertedForeground = try #require(textView.textStorage?.attribute(.foregroundColor, at: textView.string.count - 1, effectiveRange: nil) as? NSColor)
        #expect(insertedForeground.annotexHexString == LaTeXEditorTextView.fixedTextColor.annotexHexString)
        foreground = try #require(textView.typingAttributes[.foregroundColor] as? NSColor)
        #expect(foreground.annotexHexString == renderedHex)
    }

    @MainActor
    @Test func editorRenderedColorChangesNotifyRememberedColor() async throws {
        let panel = LaTeXEditorPanel()
        defer {
            panel.onDiscard = nil
            panel.close()
        }

        var notifiedColors: [String] = []
        panel.onRenderedTextColorChanged = { color in
            notifiedColors.append(color.annotexHexString)
        }

        panel.setRenderedTextColor(NSColor(srgbRed: 0.15, green: 0.25, blue: 0.35, alpha: 1))

        #expect(notifiedColors == ["#264059"])
    }

    @MainActor
    @Test func typingInEditorRestoresRenderedColorPanelSelection() async throws {
        let panel = LaTeXEditorPanel()
        defer {
            panel.onDiscard = nil
            panel.close()
            NSColorPanel.shared.setTarget(nil)
            NSColorPanel.shared.setAction(nil)
            NSColorPanel.shared.orderOut(nil)
        }

        let renderedColor = NSColor(srgbRed: 0.9, green: 0.1, blue: 0.2, alpha: 1)
        panel.setText("")
        panel.setRenderedTextColor(renderedColor)
        panel.showColorPanel()
        let textView = try #require(firstSubview(ofType: LaTeXEditorTextView.self, in: panel.contentView))

        #expect(NSColorPanel.shared.color.annotexHexString == renderedColor.annotexHexString)
        textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(textView.string == "a")
        #expect(NSColorPanel.shared.color.annotexHexString == renderedColor.annotexHexString)
        let storedForeground = try #require(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(storedForeground.annotexHexString == LaTeXEditorTextView.fixedTextColor.annotexHexString)
    }

    @MainActor
    @Test func annotationTextColorSurvivesMetadataSyncAndBoundsChanges() async throws {
        let annotation = LaTeXAnnotation(bounds: CGRect(x: 10, y: 20, width: 250, height: 60), latex: "Text $x$ text")
        let color = NSColor(srgbRed: 0.1, green: 0.5, blue: 0.9, alpha: 0.4)
        annotation.textColor = color
        let storedHex = try #require(annotation.value(forAnnotationKey: LaTeXAnnotation.textColorKey) as? String)

        annotation.bounds = CGRect(x: 10, y: 20, width: 320, height: 80)
        annotation.syncPortableMetadata()

        #expect(annotation.value(forAnnotationKey: LaTeXAnnotation.textColorKey) as? String == storedHex)
        #expect(annotation.textColor.annotexHexString == storedHex)
    }

    @MainActor
    @Test func mathJaxAndMixedImageRenderingUseSelectedTextColor() async throws {
        let color = NSColor(srgbRed: 0.9, green: 0.08, blue: 0.28, alpha: 1)
        let sources = [
            "H_{1}",
            "Text $x$ text"
        ]

        for source in sources {
            let rendered = try #require(NativeAnnotationRenderer.shared.render(
                source: source,
                width: 320,
                fontSize: 18,
                textColor: color
            ))
            let image = try #require(rendered.image)
            #expect(imageContainsTint(image, matching: color), "\(source) should contain the selected rendered text color")
        }
    }

    private func firstSubview<T: NSView>(ofType type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let typed = view as? T { return typed }
        for subview in view.subviews {
            if let match = firstSubview(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func imageContainsTint(_ image: NSImage, matching targetColor: NSColor) -> Bool {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let bitmap: NSBitmapImageRep?
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            bitmap = NSBitmapImageRep(cgImage: cgImage)
        } else if let data = image.tiffRepresentation {
            bitmap = NSBitmapImageRep(data: data)
        } else {
            bitmap = nil
        }
        guard let bitmap,
              let target = targetColor.annotexCanonicalRenderedTextColor.usingColorSpace(.sRGB) else {
            return false
        }
        let targetMaxComponent = max(target.redComponent, target.greenComponent, target.blueComponent)
        let targetVector = (
            red: target.redComponent / targetMaxComponent,
            green: target.greenComponent / targetMaxComponent,
            blue: target.blueComponent / targetMaxComponent
        )
        let tolerance: CGFloat = 0.2

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      pixel.alphaComponent > 0.05 else {
                    continue
                }
                let pixelMaxComponent = max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
                guard pixelMaxComponent > 0.05 else { continue }
                let pixelVector = (
                    red: pixel.redComponent / pixelMaxComponent,
                    green: pixel.greenComponent / pixelMaxComponent,
                    blue: pixel.blueComponent / pixelMaxComponent
                )
                if abs(pixelVector.red - targetVector.red) <= tolerance,
                   abs(pixelVector.green - targetVector.green) <= tolerance,
                   abs(pixelVector.blue - targetVector.blue) <= tolerance {
                    return true
                }
            }
        }
        return false
    }
}
