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

}
