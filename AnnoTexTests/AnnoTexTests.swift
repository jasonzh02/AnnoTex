//
//  AnnoTexTests.swift
//  AnnoTexTests
//
//  Created by Jason Zhong on 5/13/26.
//

import Testing
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

}
