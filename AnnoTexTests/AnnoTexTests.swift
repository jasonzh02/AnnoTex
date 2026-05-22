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

    @Test func annotationClipboardPayloadRoundTripsPrivately() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnnoTexTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let payload = AnnotationClipboardPayload(items: [
            AnnotationClipboardItem(
                source: #"A \xrightarrow{f} B"#,
                fontSize: 18,
                bounds: CGRect(x: 20, y: 30, width: 140, height: 40)
            )
        ])

        #expect(AnnotationClipboard.write(payload, to: pasteboard))
        let decoded = try #require(AnnotationClipboard.read(from: pasteboard))

        #expect(decoded == payload)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func annotationClipboardPlacementCentersGroupAndPreservesOffsets() throws {
        let payload = AnnotationClipboardPayload(items: [
            AnnotationClipboardItem(
                source: "First",
                fontSize: 12,
                bounds: CGRect(x: 10, y: 20, width: 100, height: 30)
            ),
            AnnotationClipboardItem(
                source: "Second",
                fontSize: 14,
                bounds: CGRect(x: 160, y: 80, width: 80, height: 50)
            )
        ])

        let placed = payload.placedItemBounds(
            centeredAt: CGPoint(x: 300, y: 250),
            within: CGRect(x: 0, y: 0, width: 600, height: 500)
        )
        let group = try #require(union(of: placed))

        #expect(abs(group.midX - 300) < 0.001)
        #expect(abs(group.midY - 250) < 0.001)
        #expect(abs((placed[1].minX - placed[0].minX) - 150) < 0.001)
        #expect(abs((placed[1].minY - placed[0].minY) - 60) < 0.001)
    }

    @Test func annotationClipboardPlacementStaysInsidePageWhenPossible() throws {
        let payload = AnnotationClipboardPayload(items: [
            AnnotationClipboardItem(
                source: "Box",
                fontSize: 12,
                bounds: CGRect(x: 25, y: 30, width: 120, height: 60)
            )
        ])
        let pageBounds = CGRect(x: 0, y: 0, width: 200, height: 160)

        let placed = payload.placedItemBounds(
            centeredAt: CGPoint(x: 5, y: 5),
            within: pageBounds
        )
        let group = try #require(union(of: placed))

        #expect(group.minX >= pageBounds.minX)
        #expect(group.minY >= pageBounds.minY)
        #expect(group.maxX <= pageBounds.maxX)
        #expect(group.maxY <= pageBounds.maxY)
    }

    @Test func annotationClipboardPlacementCascadesAwayFromCenteredOverlap() throws {
        let original = CGRect(x: 250, y: 230, width: 100, height: 40)
        let payload = AnnotationClipboardPayload(items: [
            AnnotationClipboardItem(source: "Centered", fontSize: 12, bounds: original)
        ])

        let placed = payload.placedItemBounds(
            centeredAt: CGPoint(x: 300, y: 250),
            within: CGRect(x: 0, y: 0, width: 600, height: 500),
            avoiding: [original],
            operation: .keyboardCenter
        )
        let group = try #require(union(of: placed))

        #expect(group != original)
        #expect(!group.intersects(expanded(original)))
        #expect(group.midX > original.midX)
        #expect(group.midY < original.midY)
    }

    @Test func annotationClipboardPlacementSkipsOccupiedCascadeSlots() throws {
        let original = CGRect(x: 250, y: 230, width: 100, height: 40)
        let payload = AnnotationClipboardPayload(items: [
            AnnotationClipboardItem(source: "Centered", fontSize: 12, bounds: original)
        ])
        let firstPlaced = payload.placedItemBounds(
            centeredAt: CGPoint(x: 300, y: 250),
            within: CGRect(x: 0, y: 0, width: 600, height: 500),
            avoiding: [original],
            operation: .keyboardCenter
        )
        let firstGroup = try #require(union(of: firstPlaced))

        let secondPlaced = payload.placedItemBounds(
            centeredAt: CGPoint(x: 300, y: 250),
            within: CGRect(x: 0, y: 0, width: 600, height: 500),
            avoiding: [original, firstGroup],
            operation: .keyboardCenter
        )
        let secondGroup = try #require(union(of: secondPlaced))

        #expect(!secondGroup.intersects(expanded(original)))
        #expect(!secondGroup.intersects(expanded(firstGroup)))
        #expect(secondGroup.midX > firstGroup.midX || secondGroup.midY < firstGroup.midY)
    }

    @Test func annotationClipboardPlacementPreservesMultiBoxOffsetsWhileAvoidingCollisions() throws {
        let first = CGRect(x: 250, y: 230, width: 80, height: 35)
        let second = CGRect(x: 360, y: 185, width: 90, height: 45)
        let payload = AnnotationClipboardPayload(items: [
            AnnotationClipboardItem(source: "First", fontSize: 12, bounds: first),
            AnnotationClipboardItem(source: "Second", fontSize: 14, bounds: second)
        ])
        let occupied = try #require(union(of: [first, second]))

        let placed = payload.placedItemBounds(
            centeredAt: CGPoint(x: occupied.midX, y: occupied.midY),
            within: CGRect(x: 0, y: 0, width: 700, height: 520),
            avoiding: [occupied],
            operation: .keyboardCenter
        )
        let group = try #require(union(of: placed))

        #expect(!group.intersects(expanded(occupied)))
        #expect(abs((placed[1].minX - placed[0].minX) - (second.minX - first.minX)) < 0.001)
        #expect(abs((placed[1].minY - placed[0].minY) - (second.minY - first.minY)) < 0.001)
    }

    @Test func annotationClipboardPlacementFallsBackToOverlapWhenNoRoomExists() throws {
        let original = CGRect(x: 20, y: 20, width: 80, height: 60)
        let pageBounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let payload = AnnotationClipboardPayload(items: [
            AnnotationClipboardItem(source: "Box", fontSize: 12, bounds: original)
        ])

        let placed = payload.placedItemBounds(
            centeredAt: CGPoint(x: 50, y: 50),
            within: pageBounds,
            avoiding: [pageBounds],
            operation: .keyboardCenter
        )
        let group = try #require(union(of: placed))

        #expect(group.intersects(pageBounds))
        #expect(group.midX == 50)
        #expect(group.midY == 50)
    }

    private func union(of rects: [CGRect]) -> CGRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result
    }

    private func expanded(_ rect: CGRect) -> CGRect {
        rect.insetBy(
            dx: -AnnotationPastePlacement.collisionMargin,
            dy: -AnnotationPastePlacement.collisionMargin
        )
    }

}
