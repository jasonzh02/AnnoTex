import SwiftUI
import PDFKit
import CoreText
import LaTeXSwiftUI
import MathJaxSwift

extension NSColor {
    var annotexHexString: String {
        let converted = usingColorSpace(.sRGB) ?? self
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    convenience init?(annotexHexString: String) {
        let trimmed = annotexHexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}

private class RenderedTextColorPanelTarget: NSObject {
    static let shared = RenderedTextColorPanelTarget()

    private weak var editorPanel: LaTeXEditorPanel?
    private weak var pdfView: MathPDFView?

    func showForEditorPanel(_ panel: LaTeXEditorPanel, color: NSColor) {
        editorPanel = panel
        pdfView = nil
        show(color: color)
    }

    func showForPDFView(_ view: MathPDFView, color: NSColor) {
        editorPanel = nil
        pdfView = view
        show(color: color)
    }

    private func show(color: NSColor) {
        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorChanged(_:)))
        colorPanel.isContinuous = true
        colorPanel.showsAlpha = false
        colorPanel.mode = .wheel
        colorPanel.color = color
        colorPanel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        if let editorPanel {
            editorPanel.setRenderedTextColor(sender.color)
        } else if let pdfView {
            pdfView.applyTextColorToActiveAnnotation(sender.color)
        }
    }
}

extension NSImage {
    func annotexTinted(with color: NSColor) -> NSImage {
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }
}

// MARK: - LaTeX Annotation
class LaTeXAnnotation: PDFAnnotation {
    static let metadataVersion = "1"
    static let rendererVersion = "native-coretext-v1"
    static let markerValue = "AnnoTex.LaTeXAnnotation"

    static let markerKey = PDFAnnotationKey(rawValue: "/AnnoTexKind")
    static let sourceKey = PDFAnnotationKey(rawValue: "/AnnoTexSource")
    static let fontSizeKey = PDFAnnotationKey(rawValue: "/AnnoTexFontSize")
    static let textColorKey = PDFAnnotationKey(rawValue: "/AnnoTexTextColor")
    static let rendererVersionKey = PDFAnnotationKey(rawValue: "/AnnoTexRendererVersion")
    static let metadataVersionKey = PDFAnnotationKey(rawValue: "/AnnoTexMetadataVersion")
    static let layoutBoundsKey = PDFAnnotationKey(rawValue: "/AnnoTexLayoutBounds")

    var latexCode: String = ""
    var renderedContent: RenderedAnnotation?
    var isSelected: Bool = false

    convenience init(bounds: NSRect, latex: String) {
        self.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.latexCode = latex
        self.contents = latex
        self.shouldDisplay = true
        self.shouldPrint = true
        syncPortableMetadata()
    }

    var fontSize: CGFloat {
        get {
            if let val = self.value(forAnnotationKey: Self.fontSizeKey) as? NSNumber {
                return CGFloat(val.doubleValue)
            }
            return 12.0
        }
        set {
            self.setValue(NSNumber(value: Double(newValue)), forAnnotationKey: Self.fontSizeKey)
            syncPortableMetadata()
        }
    }

    var textColor: NSColor {
        get {
            if let hex = value(forAnnotationKey: Self.textColorKey) as? String,
               let color = NSColor(annotexHexString: hex) {
                return color
            }
            return .black
        }
        set {
            setValue(newValue.annotexHexString, forAnnotationKey: Self.textColorKey)
            syncPortableMetadata()
        }
    }

    var isAnnoTexAnnotation: Bool {
        (value(forAnnotationKey: Self.markerKey) as? String) == Self.markerValue
    }

    func syncPortableMetadata() {
        contents = latexCode
        setValue(Self.markerValue, forAnnotationKey: Self.markerKey)
        setValue(Self.metadataVersion, forAnnotationKey: Self.metadataVersionKey)
        setValue(Self.rendererVersion, forAnnotationKey: Self.rendererVersionKey)
        setValue(latexCode, forAnnotationKey: Self.sourceKey)
        setValue(NSNumber(value: Double(fontSize)), forAnnotationKey: Self.fontSizeKey)
        setValue(textColor.annotexHexString, forAnnotationKey: Self.textColorKey)
        setValue(
            [
                NSNumber(value: Double(bounds.origin.x)),
                NSNumber(value: Double(bounds.origin.y)),
                NSNumber(value: Double(bounds.size.width)),
                NSNumber(value: Double(bounds.size.height))
            ],
            forAnnotationKey: Self.layoutBoundsKey
        )
    }

    static func storedSource(from annotation: PDFAnnotation) -> String? {
        if let source = annotation.value(forAnnotationKey: sourceKey) as? String, !source.isEmpty {
            return source
        }
        return annotation.contents
    }

    static func isStoredAnnoTexAnnotation(_ annotation: PDFAnnotation) -> Bool {
        if (annotation.value(forAnnotationKey: markerKey) as? String) == markerValue {
            return true
        }
        if annotation.value(forAnnotationKey: sourceKey) as? String != nil {
            return true
        }
        return annotation.value(forAnnotationKey: fontSizeKey) as? NSNumber != nil
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        if let renderedContent {
            context.saveGState()
            renderedContent.draw(in: context, bounds: self.bounds)
            context.restoreGState()
        }
        if isSelected {
            context.saveGState()
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.0)
            context.setLineDash(phase: 0, lengths: [4, 4])
            let s: CGFloat = 4, h = s / 2
            let r = self.bounds.insetBy(dx: 5, dy: 5)
            let bottomLeft = CGPoint(x: r.minX + h, y: r.minY + h)
            let bottomRight = CGPoint(x: r.maxX - h, y: r.minY + h)
            let topLeft = CGPoint(x: r.minX + h, y: r.maxY - h)
            let topRight = CGPoint(x: r.maxX - h, y: r.maxY - h)
            context.move(to: bottomLeft)
            context.addLine(to: bottomRight)
            context.move(to: topLeft)
            context.addLine(to: topRight)
            context.move(to: bottomLeft)
            context.addLine(to: topLeft)
            context.move(to: bottomRight)
            context.addLine(to: topRight)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            let handles: [CGRect] = [
                CGRect(x: r.minX, y: r.minY, width: s, height: s),
                CGRect(x: r.maxX - s, y: r.minY, width: s, height: s),
                CGRect(x: r.minX, y: r.maxY - s, width: s, height: s),
                CGRect(x: r.maxX - s, y: r.maxY - s, width: s, height: s),
            ]
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.0)
            for handle in handles {
                context.fillEllipse(in: handle)
                context.strokeEllipse(in: handle)
            }
            context.restoreGState()
        }
    }
}

// MARK: - Native Annotation Renderer
struct RenderedAnnotation {
    let lines: [CTLine]
    let metrics: [(ascent: CGFloat, descent: CGFloat, leading: CGFloat, width: CGFloat)]
    let image: NSImage?
    let size: CGSize
    let padding: CGFloat
    let textColor: NSColor

    func draw(in context: CGContext, bounds: CGRect) {
        if let image {
            context.saveGState()
            context.interpolationQuality = .high
            let previousContext = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(
                in: bounds.insetBy(dx: padding, dy: padding),
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1
            )
            NSGraphicsContext.current = previousContext
            context.restoreGState()
            return
        }

        context.setFillColor(textColor.cgColor)
        context.textMatrix = .identity

        var baselineY = bounds.maxY - padding
        for (index, line) in lines.enumerated() {
            let metric = metrics[index]
            baselineY -= metric.ascent
            context.textPosition = CGPoint(x: bounds.minX + padding, y: baselineY)
            CTLineDraw(line, context)
            baselineY -= metric.descent + metric.leading
        }
    }
}

// MARK: - MathJax Annotation Renderer
class MathJaxAnnotationRenderer {
    static let shared = MathJaxAnnotationRenderer()

    private enum Segment {
        case text(String)
        case math(String)
    }

    private struct RenderedSegment {
        let image: NSImage?
        let text: String?
        let textAttributes: [NSAttributedString.Key: Any]
        let size: CGSize
        let baseline: CGFloat
    }

    private struct RenderedLine {
        let segments: [RenderedSegment]
        let size: CGSize
        let baseline: CGFloat
        let descent: CGFloat
    }

    private struct SVGGeometry {
        let verticalAlignment: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private struct MathRenderResult {
        let image: NSImage
        let size: CGSize
        let baseline: CGFloat
    }

    private let padding: CGFloat = 8
    private let displayScale: CGFloat = 4
    private let segmentSpacing: CGFloat = 1.5
    private let lineSpacing: CGFloat = 2
    private let mathMetricsQueue = DispatchQueue(label: "annotex.mathjax.metrics")
    private var svgGeometryCache: [String: SVGGeometry] = [:]
    private lazy var mathJaxForMetrics: MathJax? = {
        do {
            return try MathJax(preferredOutputFormats: [.svg])
        } catch {
            NSLog("Error creating MathJax metrics renderer: \(error)")
            return nil
        }
    }()

    private init() {}

    func render(source: String, width: CGFloat, fontSize: CGFloat, textColor: NSColor = .black) -> RenderedAnnotation? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let latex = mathOnlySource(from: trimmed), let image = renderMathImage(latex, fontSize: fontSize, textColor: textColor) {
            return renderedAnnotation(for: image, width: width, fontSize: fontSize, textColor: textColor)
        }
        return renderMixed(source: source, width: width, fontSize: fontSize, textColor: textColor)
    }

    private func mathOnlySource(from source: String) -> String? {
        if source.hasPrefix("\\("), source.hasSuffix("\\)") {
            return String(source.dropFirst(2).dropLast(2))
        }
        if source.hasPrefix("\\["), source.hasSuffix("\\]") {
            return String(source.dropFirst(2).dropLast(2))
        }
        if source.hasPrefix("$$"), source.hasSuffix("$$"), source.count > 4 {
            return String(source.dropFirst(2).dropLast(2))
        }
        if source.hasPrefix("$"), source.hasSuffix("$"), source.count > 2 {
            return String(source.dropFirst().dropLast())
        }
        if source.contains("$") || source.contains("\\(") || source.contains("\\[") {
            return nil
        }
        return source
    }

    private func renderMixed(source: String, width: CGFloat, fontSize: CGFloat, textColor: NSColor) -> RenderedAnnotation? {
        let lines = source.components(separatedBy: .newlines)
        guard lines.contains(where: containsMathDelimiter) else { return nil }

        let font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        let maxContentWidth = max(width - padding * 2, 10)
        let renderedLines = lines.compactMap { line -> [RenderedLine]? in
            guard let segments = parseInlineSegments(line) else { return nil }
            return renderLines(
                segments: segments,
                font: font,
                textAttributes: textAttributes,
                fontSize: fontSize,
                textColor: textColor,
                maxContentWidth: maxContentWidth
            )
        }.flatMap { $0 }
        guard !renderedLines.isEmpty else { return nil }
        guard let image = composeImage(lines: renderedLines, contentWidth: maxContentWidth) else { return nil }
        return renderedAnnotation(for: image, width: width, fontSize: fontSize, textColor: textColor)
    }

    private func containsMathDelimiter(_ line: String) -> Bool {
        line.contains("$") || line.contains("\\(")
    }

    private func parseInlineSegments(_ line: String) -> [Segment]? {
        var segments: [Segment] = []
        var index = line.startIndex
        var textBuffer = ""

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            segments.append(.text(textBuffer))
            textBuffer.removeAll()
        }

        while index < line.endIndex {
            if line[index] == "$" {
                let mathStart = line.index(after: index)
                guard let close = line[mathStart...].firstIndex(of: "$") else { return nil }
                flushText()
                segments.append(.math(String(line[mathStart..<close])))
                index = line.index(after: close)
            } else if line[index...].hasPrefix("\\(") {
                let mathStart = line.index(index, offsetBy: 2)
                guard let close = line.range(of: "\\)", range: mathStart..<line.endIndex) else { return nil }
                flushText()
                segments.append(.math(String(line[mathStart..<close.lowerBound])))
                index = close.upperBound
            } else {
                textBuffer.append(line[index])
                index = line.index(after: index)
            }
        }
        flushText()
        return segments
    }

    private func renderLines(
        segments: [Segment],
        font: NSFont,
        textAttributes: [NSAttributedString.Key: Any],
        fontSize: CGFloat,
        textColor: NSColor,
        maxContentWidth: CGFloat
    ) -> [RenderedLine]? {
        var renderedSegments: [RenderedSegment] = []
        for segment in segments {
            switch segment {
            case .text(let text):
                for token in textWrapTokens(from: text) {
                    let size = (token as NSString).size(withAttributes: textAttributes)
                    renderedSegments.append(RenderedSegment(
                        image: nil,
                        text: token,
                        textAttributes: textAttributes,
                        size: size,
                        baseline: font.ascender
                    ))
                }
            case .math(let latex):
                guard let renderedMath = renderMathSegment(latex, font: font, fontSize: fontSize, textColor: textColor) else { return nil }
                renderedSegments.append(RenderedSegment(
                    image: renderedMath.image,
                    text: nil,
                    textAttributes: textAttributes,
                    size: renderedMath.size,
                    baseline: renderedMath.baseline
                ))
            }
        }
        return wrapRenderedSegments(renderedSegments, maxContentWidth: maxContentWidth, font: font)
    }

    private func textWrapTokens(from text: String) -> [String] {
        var tokens: [String] = []
        var buffer = ""
        var previousWasWhitespace: Bool?

        for character in text {
            let isWhitespace = character.isWhitespace
            if let previousWasWhitespace, previousWasWhitespace != isWhitespace {
                tokens.append(buffer)
                buffer.removeAll()
            }
            buffer.append(character)
            previousWasWhitespace = isWhitespace
        }

        if !buffer.isEmpty { tokens.append(buffer) }
        return tokens
    }

    private func wrapRenderedSegments(_ segments: [RenderedSegment], maxContentWidth: CGFloat, font: NSFont) -> [RenderedLine] {
        var lines: [RenderedLine] = []
        var current: [RenderedSegment] = []
        var currentWidth: CGFloat = 0

        func segmentWidthAfterAppend(_ segment: RenderedSegment, to line: [RenderedSegment], currentWidth: CGFloat) -> CGFloat {
            currentWidth + segment.size.width + (line.isEmpty ? 0 : segmentSpacing)
        }

        func flushLine() {
            guard !current.isEmpty else { return }
            lines.append(line(from: current, font: font))
            current.removeAll()
            currentWidth = 0
        }

        for segment in segments {
            if segment.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true, current.isEmpty {
                continue
            }
            let nextWidth = segmentWidthAfterAppend(segment, to: current, currentWidth: currentWidth)
            if nextWidth > maxContentWidth, !current.isEmpty {
                flushLine()
                if segment.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    continue
                }
            }
            currentWidth = segmentWidthAfterAppend(segment, to: current, currentWidth: currentWidth)
            current.append(segment)
        }

        flushLine()
        return lines
    }

    private func line(from renderedSegments: [RenderedSegment], font: NSFont) -> RenderedLine {
        let baseline = renderedSegments.map(\.baseline).max() ?? font.ascender
        let descent = renderedSegments.map { $0.size.height - $0.baseline }.max() ?? abs(font.descender)
        let width = renderedSegments.enumerated().reduce(CGFloat(0)) { total, item in
            total + item.element.size.width + (item.offset == 0 ? 0 : segmentSpacing)
        }
        return RenderedLine(
            segments: renderedSegments,
            size: CGSize(width: width, height: baseline + descent),
            baseline: baseline,
            descent: descent
        )
    }

    private func composeImage(lines: [RenderedLine], contentWidth: CGFloat? = nil) -> NSImage? {
        let contentWidth = contentWidth ?? lines.map(\.size.width).max() ?? 0
        let contentHeight = lines.enumerated().reduce(CGFloat(0)) { total, item in
            total + item.element.size.height + (item.offset == 0 ? 0 : lineSpacing)
        }
        guard contentWidth > 0, contentHeight > 0 else { return nil }

        let size = CGSize(width: contentWidth, height: contentHeight)
        let image = NSImage(size: size)
        let scale = max(displayScale, 1)
        let pixelWidth = max(Int(ceil(size.width * scale)), 1)
        let pixelHeight = max(Int(ceil(size.height * scale)), 1)
        if let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            bitmap.size = size
            image.addRepresentation(bitmap)
        }
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        var y = size.height
        for line in lines {
            y -= line.size.height
            var x: CGFloat = 0
            for (index, segment) in line.segments.enumerated() {
                if index > 0 { x += segmentSpacing }
                let segmentY = y + line.baseline - segment.baseline
                if let image = segment.image {
                    image.draw(
                        in: NSRect(origin: CGPoint(x: x, y: segmentY), size: segment.size),
                        from: NSRect(origin: .zero, size: segment.size),
                        operation: .sourceOver,
                        fraction: 1
                    )
                } else if let text = segment.text {
                    (text as NSString).draw(
                        at: CGPoint(x: x, y: segmentY),
                        withAttributes: segment.textAttributes
                    )
                }
                x += segment.size.width
            }
            y -= lineSpacing
        }

        image.unlockFocus()
        return image
    }

    private func renderMathSegment(_ latex: String, font: NSFont, fontSize: CGFloat, textColor: NSColor) -> MathRenderResult? {
        guard let image = renderMathImage(latex, fontSize: fontSize, textColor: textColor) else { return nil }
        let xHeight = mathXHeight(for: fontSize)
        let baseline = mathBaseline(for: latex, imageSize: image.size, xHeight: xHeight, font: font)
        return MathRenderResult(image: image, size: image.size, baseline: baseline)
    }

    private func mathBaseline(for latex: String, imageSize: CGSize, xHeight: CGFloat, font: NSFont) -> CGFloat {
        guard let geometry = svgGeometry(for: latex) else {
            return imageSize.height * 0.72
        }
        let expectedHeight = max(geometry.height * xHeight, 1)
        let heightScale = imageSize.height / expectedHeight
        let descent = max(-geometry.verticalAlignment * xHeight * heightScale, 0)
        let baseline = imageSize.height - descent + shallowInlineMathCorrection(
            mathHeight: imageSize.height,
            mathDescent: descent,
            font: font
        )
        return min(max(baseline, 0), imageSize.height)
    }

    private func shallowInlineMathCorrection(mathHeight: CGFloat, mathDescent: CGFloat, font: NSFont) -> CGFloat {
        let textDescent = max(abs(font.descender), 1)
        let textLineHeight = max(font.ascender + textDescent, 1)
        let shallowDepthFactor = min(max((textDescent * 0.75 - mathDescent) / (textDescent * 0.75), 0), 1)
        let compactHeightFactor = min(max((textLineHeight * 1.15 - mathHeight) / (textLineHeight * 0.35), 0), 1)
        let maxCorrection = min(textDescent * 0.45, 1.25)
        return maxCorrection * shallowDepthFactor * compactHeightFactor
    }

    private func svgGeometry(for latex: String) -> SVGGeometry? {
        mathMetricsQueue.sync { () -> SVGGeometry? in
            if let cachedGeometry = svgGeometryCache[latex] {
                return cachedGeometry
            }
            guard let mathJax = mathJaxForMetrics else { return nil }
            var conversionError: Error?
            let svg = mathJax.tex2svg(
                latex,
                styles: false,
                inputOptions: TeXInputProcessorOptions(),
                error: &conversionError
            )
            if let error = conversionError {
                NSLog("MathJax metrics conversion failed: \(error)")
                return nil
            }
            guard let geometry = parseSVGGeometry(svg) else { return nil }
            svgGeometryCache[latex] = geometry
            return geometry
        }
    }

    private func parseSVGGeometry(_ svg: String) -> SVGGeometry? {
        guard let svgElement = firstSVGElement(in: svg) else { return nil }
        let attributes = svgAttributes(in: svgElement)
        guard let width = attributes["width"].flatMap(parseExValue),
              let height = attributes["height"].flatMap(parseExValue),
              let style = attributes["style"],
              let verticalAlignment = parseVerticalAlignment(from: style) else {
            return nil
        }
        return SVGGeometry(verticalAlignment: verticalAlignment, width: width, height: height)
    }

    private func firstSVGElement(in svg: String) -> String? {
        guard let start = svg.range(of: "<svg"),
              let end = svg[start.lowerBound...].firstIndex(of: ">") else {
            return nil
        }
        return String(svg[start.lowerBound...end])
    }

    private func svgAttributes(in svgElement: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let pattern = #"([\w:-]+)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return attributes }
        let range = NSRange(svgElement.startIndex..<svgElement.endIndex, in: svgElement)
        regex.enumerateMatches(in: svgElement, range: range) { match, _, _ in
            guard let match,
                  let keyRange = Range(match.range(at: 1), in: svgElement),
                  let valueRange = Range(match.range(at: 2), in: svgElement) else {
                return
            }
            attributes[String(svgElement[keyRange])] = String(svgElement[valueRange])
        }
        return attributes
    }

    private func parseVerticalAlignment(from style: String) -> CGFloat? {
        let declarations = style.split(separator: ";")
        for declaration in declarations {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "vertical-align" else {
                continue
            }
            return parseExValue(String(parts[1]))
        }
        return nil
    }

    private func parseExValue(_ value: String) -> CGFloat? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("ex") else { return nil }
        guard let doubleValue = Double(String(trimmed.dropLast(2))) else { return nil }
        return CGFloat(doubleValue)
    }

    private func renderMathImage(_ latex: String, fontSize: CGFloat, textColor: NSColor) -> NSImage? {
        let wrapped = "\\(\(latex)\\)"
        let image = LaTeX.renderToImages(
            wrapped,
            xHeight: mathXHeight(for: fontSize),
            displayScale: displayScale,
            parsingMode: .onlyEquations,
            errorMode: .rendered
        ).first
        guard let image else { return nil }
        return textColor.annotexHexString == NSColor.black.annotexHexString ? image : image.annotexTinted(with: textColor)
    }

    private func mathXHeight(for fontSize: CGFloat) -> CGFloat {
        max(fontSize * 0.45, 1)
    }

    private func renderedAnnotation(for image: NSImage, width: CGFloat, fontSize: CGFloat, textColor: NSColor) -> RenderedAnnotation {
        RenderedAnnotation(
            lines: [],
            metrics: [],
            image: image,
            size: CGSize(
                width: max(width, image.size.width + padding * 2, 50),
                height: max(image.size.height + padding * 2, fontSize + padding * 2)
            ),
            padding: padding,
            textColor: textColor
        )
    }
}

class NativeAnnotationRenderer {
    static let shared = NativeAnnotationRenderer()

    private let padding: CGFloat = 8
    private let lineSpacing: CGFloat = 2

    private let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
        "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ",
        "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ",
        "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω"
    ]

    private let symbols: [String: String] = [
        "sum": "∑", "prod": "∏", "int": "∫", "infty": "∞", "partial": "∂",
        "nabla": "∇", "cdot": "·", "times": "×", "div": "÷", "pm": "±",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠",
        "approx": "≈", "to": "→", "rightarrow": "→", "leftarrow": "←",
        "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆",
        "forall": "∀", "exists": "∃"
    ]

    func render(source: String, width: CGFloat, fontSize: CGFloat, textColor: NSColor = .black) -> RenderedAnnotation? {
        if let rendered = MathJaxAnnotationRenderer.shared.render(source: source, width: width, fontSize: fontSize, textColor: textColor) {
            return rendered
        }

        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let attributedParagraphs = source
            .components(separatedBy: .newlines)
            .map { attributedLine(for: $0, fontSize: fontSize, textColor: textColor) }
        let maxContentWidth = max(width - padding * 2, 10)

        let ctLines = attributedParagraphs.flatMap { wrappedLines(for: $0, maxWidth: maxContentWidth) }
        let lineMetrics = ctLines.map { line in
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            return (ascent: ascent, descent: descent, leading: max(leading, lineSpacing), width: width)
        }

        let contentWidth = lineMetrics.map(\.width).max() ?? 0
        let contentHeight = lineMetrics.reduce(CGFloat(0)) { total, metric in
            total + metric.ascent + metric.descent + metric.leading
        }

        return RenderedAnnotation(
            lines: ctLines,
            metrics: lineMetrics,
            image: nil,
            size: CGSize(
                width: max(width, contentWidth + padding * 2, 50),
                height: max(contentHeight + padding * 2, fontSize + padding * 2)
            ),
            padding: padding,
            textColor: textColor
        )
    }

    private func wrappedLines(for attributedString: NSAttributedString, maxWidth: CGFloat) -> [CTLine] {
        guard attributedString.length > 0 else {
            return [CTLineCreateWithAttributedString(NSAttributedString(string: " "))]
        }

        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        var lines: [CTLine] = []
        var start = 0

        while start < attributedString.length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(maxWidth))
            if count <= 0 { count = 1 }
            let range = CFRange(location: start, length: count)
            lines.append(CTTypesetterCreateLine(typesetter, range))
            start += count
        }

        return lines
    }

    private func attributedLine(for line: String, fontSize: CGFloat, textColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = line.startIndex
        var plainBuffer = ""

        func flushPlain() {
            guard !plainBuffer.isEmpty else { return }
            result.append(NSAttributedString(string: plainBuffer, attributes: textAttributes(fontSize: fontSize, textColor: textColor)))
            plainBuffer.removeAll()
        }

        while index < line.endIndex {
            if line[index] == "$", let close = line[line.index(after: index)...].firstIndex(of: "$") {
                flushPlain()
                let math = String(line[line.index(after: index)..<close])
                result.append(attributedMath(for: math, fontSize: fontSize, textColor: textColor))
                index = line.index(after: close)
            } else {
                plainBuffer.append(line[index])
                index = line.index(after: index)
            }
        }
        flushPlain()
        return result
    }

    private func attributedMath(for math: String, fontSize: CGFloat, textColor: NSColor = .black) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(math)
        var i = 0

        while i < chars.count {
            let char = chars[i]
            if char == "\\" {
                let (command, nextIndex) = readCommand(chars, from: i + 1)
                if command == "frac" {
                    let parsed = readFraction(chars, from: nextIndex)
                    if let numerator = parsed.numerator, let denominator = parsed.denominator {
                        appendMathToken(numerator, to: result, fontSize: fontSize * 0.78, textColor: textColor, baseline: fontSize * 0.24)
                        appendMathToken("⁄", to: result, fontSize: fontSize, textColor: textColor)
                        appendMathToken(denominator, to: result, fontSize: fontSize * 0.78, textColor: textColor, baseline: -fontSize * 0.20)
                        i = parsed.nextIndex
                        continue
                    }
                }
                appendMathToken(greek[command] ?? symbols[command] ?? command, to: result, fontSize: fontSize, textColor: textColor)
                i = nextIndex
            } else if char == "^" || char == "_" {
                let parsed = readScript(chars, from: i + 1)
                let scriptSize = fontSize * 0.68
                let offset = char == "^" ? fontSize * 0.38 : -fontSize * 0.22
                appendMathToken(parsed.value, to: result, fontSize: scriptSize, textColor: textColor, baseline: offset)
                i = parsed.nextIndex
            } else if char == "{" || char == "}" {
                i += 1
            } else {
                appendMathToken(String(char), to: result, fontSize: fontSize, textColor: textColor)
                i += 1
            }
        }

        return result
    }

    private func appendMathToken(_ token: String, to result: NSMutableAttributedString, fontSize: CGFloat, textColor: NSColor, baseline: CGFloat = 0) {
        var attributes = textAttributes(fontSize: fontSize, textColor: textColor)
        if baseline != 0 {
            attributes[.baselineOffset] = baseline
        }
        result.append(NSAttributedString(string: token, attributes: attributes))
    }

    private func textAttributes(fontSize: CGFloat, textColor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor
        ]
    }

    private func readCommand(_ chars: [Character], from start: Int) -> (String, Int) {
        var index = start
        var command = ""
        while index < chars.count, chars[index].isLetter {
            command.append(chars[index])
            index += 1
        }
        if command.isEmpty, index < chars.count {
            command.append(chars[index])
            index += 1
        }
        return (command, index)
    }

    private func readScript(_ chars: [Character], from start: Int) -> (value: String, nextIndex: Int) {
        guard start < chars.count else { return ("", start) }
        if chars[start] == "{" {
            return readBracedValue(chars, from: start)
        }
        return (String(chars[start]), start + 1)
    }

    private func readFraction(_ chars: [Character], from start: Int) -> (numerator: String?, denominator: String?, nextIndex: Int) {
        let numerator = readBracedValue(chars, from: start)
        guard numerator.nextIndex < chars.count else {
            return (nil, nil, start)
        }
        let denominator = readBracedValue(chars, from: numerator.nextIndex)
        guard !numerator.value.isEmpty, !denominator.value.isEmpty else {
            return (nil, nil, start)
        }
        return (cleanMath(numerator.value), cleanMath(denominator.value), denominator.nextIndex)
    }

    private func readBracedValue(_ chars: [Character], from start: Int) -> (value: String, nextIndex: Int) {
        guard start < chars.count, chars[start] == "{" else { return ("", start) }
        var depth = 1
        var index = start + 1
        var value = ""
        while index < chars.count, depth > 0 {
            if chars[index] == "{" {
                depth += 1
                value.append(chars[index])
            } else if chars[index] == "}" {
                depth -= 1
                if depth > 0 { value.append(chars[index]) }
            } else {
                value.append(chars[index])
            }
            index += 1
        }
        return (value, index)
    }

    private func cleanMath(_ value: String) -> String {
        let rendered = attributedMath(for: value, fontSize: 12).string
        return rendered.isEmpty ? value : rendered
    }
}

// MARK: - Dark Editor Panel
// A real titled NSPanel (traffic-light dots) with dark appearance, acting as the LaTeX input editor.
class LaTeXEditorPanel: NSPanel {
    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 210  // includes title bar height (~22pt)
    static let barHeight: CGFloat = 44

    private let innerTextView: NSTextView
    private let colorButton = NSButton()
    private var renderedTextColor: NSColor = .black

    var onRender: ((String, NSColor) -> Void)?
    var onDiscard: (() -> Void)?

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: LaTeXEditorPanel.panelWidth, height: LaTeXEditorPanel.panelHeight),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        // Create the NSTextView
        let tv = NSTextView()
        tv.isEditable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont(name: "Menlo", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = NSColor(white: 0.88, alpha: 1)
        tv.backgroundColor = NSColor(white: 0.12, alpha: 1)
        tv.insertionPointColor = .white
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainer?.widthTracksTextView = true
        self.innerTextView = tv

        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        self.title = "LaTeX Editor"
        self.appearance = NSAppearance(named: .darkAqua)
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.level = .floating
        self.hasShadow = true
        self.isReleasedWhenClosed = false

        buildUI()
    }

    private func buildUI() {
        let cv = self.contentView!
        let cvW = cv.bounds.width
        let cvH = cv.bounds.height
        let barH = LaTeXEditorPanel.barHeight
        let editorH = cvH - barH

        // Scroll view + text view
        let sv = NSScrollView(frame: NSRect(x: 0, y: barH, width: cvW, height: editorH))
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.backgroundColor = NSColor(white: 0.12, alpha: 1)
        sv.drawsBackground = true
        sv.autoresizingMask = [.width, .height]
        innerTextView.frame = NSRect(x: 0, y: 0, width: sv.bounds.width, height: max(editorH, 100))
        innerTextView.autoresizingMask = [.width]
        sv.documentView = innerTextView
        cv.addSubview(sv)

        // Divider
        let divider = NSBox(frame: NSRect(x: 0, y: barH - 1, width: cvW, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        cv.addSubview(divider)

        // Bottom bar
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: cvW, height: barH))
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = NSColor(white: 0.17, alpha: 1).cgColor
        bottomBar.autoresizingMask = [.width]
        cv.addSubview(bottomBar)

        colorButton.title = ""
        colorButton.bezelStyle = .rounded
        colorButton.frame = NSRect(x: 10, y: 8, width: 32, height: 28)
        colorButton.target = self
        colorButton.action = #selector(showColorPanel)
        colorButton.wantsLayer = true
        colorButton.layer?.cornerRadius = 6
        colorButton.toolTip = "Rendered text color"
        bottomBar.addSubview(colorButton)
        updateColorButton()

        // Render button
        let btn = NSButton(title: "Render ▶", target: self, action: #selector(renderPressed))
        btn.bezelStyle = .rounded
        btn.controlSize = .regular
        btn.keyEquivalent = "\r"
        btn.keyEquivalentModifierMask = .command
        let bw: CGFloat = 96
        btn.frame = NSRect(x: cvW - bw - 10, y: 8, width: bw, height: 28)
        btn.autoresizingMask = [.minXMargin]
        bottomBar.addSubview(btn)
    }

    @objc private func renderPressed() {
        onRender?(innerTextView.string, renderedTextColor)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 36 {
            renderPressed()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc private func showColorPanel() {
        RenderedTextColorPanelTarget.shared.showForEditorPanel(self, color: renderedTextColor)
    }

    private func updateColorButton() {
        colorButton.layer?.backgroundColor = renderedTextColor.cgColor
        colorButton.layer?.borderWidth = 1
        colorButton.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func close() {
        onDiscard?()
        super.close()
    }

    var text: String { innerTextView.string }
    func setText(_ s: String) {
        innerTextView.string = s
    }

    func setRenderedTextColor(_ color: NSColor) {
        renderedTextColor = color
        updateColorButton()
    }

    func focusTextView() {
        makeFirstResponder(innerTextView)
        let end = innerTextView.string.count
        innerTextView.setSelectedRange(NSRange(location: end, length: 0))
    }

    func flash() {
        guard let cv = contentView else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            cv.animator().alphaValue = 0.55
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                cv.animator().alphaValue = 1.0
            }
        })
    }

    func positionNear(annotScreenRect: NSRect) {
        let gap: CGFloat = 8
        let w = frame.width
        let h = frame.height
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let belowY = annotScreenRect.minY - gap - h
        let aboveY = annotScreenRect.maxY + gap
        let y = belowY >= screen.minY ? belowY : aboveY
        let x = max(screen.minX + 4, min(annotScreenRect.minX, screen.maxX - w - 4))
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Custom PDFView
enum DragState: Equatable {
    case none, moving
    case resizing(corner: ResizeCorner)
}
enum ResizeCorner: Equatable {
    case bottomLeft, bottomRight, topLeft, topRight
}

class MathPDFView: PDFView {
    private var activeEditorPanel: LaTeXEditorPanel?
    private var activeAnnotation: LaTeXAnnotation?
    var currentFontSize: CGFloat = 12.0
    var currentTextColor: NSColor = .black
    private var eventMonitor: Any?
    private var dragState: DragState = .none
    private var dragStartPoint: CGPoint = .zero
    private var dragStartBounds: CGRect = .zero

    var currentAppMode: AppMode = .view {
        didSet { refreshCursorForCurrentMode() }
    }
    var onSelectionChanged: ((LaTeXAnnotation?) -> Void)?
    var onEditingStateChanged: ((Bool) -> Void)?
    var onActiveTextColorChanged: ((NSColor) -> Void)?

    func updateActiveFontSize() {
        guard let ann = activeAnnotation, activeEditorPanel == nil else { return }
        ann.fontSize = currentFontSize
        rerenderAnnotation(ann)
    }

    func updateActiveTextColor() {
        guard let ann = activeAnnotation, activeEditorPanel == nil else { return }
        ann.textColor = currentTextColor
        rerenderAnnotation(ann)
    }

    func showTextColorPanelForActiveAnnotation() {
        guard let ann = activeAnnotation, activeEditorPanel == nil else { return }
        RenderedTextColorPanelTarget.shared.showForPDFView(self, color: ann.textColor)
    }

    func applyTextColorToActiveAnnotation(_ color: NSColor) {
        guard let ann = activeAnnotation, activeEditorPanel == nil else { return }
        currentTextColor = color
        ann.textColor = color
        rerenderAnnotation(ann)
        onActiveTextColorChanged?(color)
    }

    @MainActor
    func writePortableDocument(to url: URL) async -> Bool {
        guard let document else { return false }
        let annotations = allAnnoTexAnnotations()
        let selectedAnnotations = annotations.filter { $0.isSelected }
        await prepareAnnotationsForPortableSave(annotations)
        let succeeded = document.write(to: url)
        selectedAnnotations.forEach { $0.isSelected = true }
        needsDisplay = true
        return succeeded
    }

    @MainActor
    private func prepareAnnotationsForPortableSave(_ annotations: [LaTeXAnnotation]) async {
        for annotation in annotations {
            annotation.isSelected = false
            annotation.syncPortableMetadata()
            if annotation.renderedContent == nil {
                annotation.renderedContent = NativeAnnotationRenderer.shared.render(
                    source: annotation.latexCode,
                    width: annotation.bounds.width,
                    fontSize: annotation.fontSize,
                    textColor: annotation.textColor
                )
            }
            annotation.removeAllAppearanceStreams()
        }
        needsDisplay = true
    }

    private func allAnnoTexAnnotations() -> [LaTeXAnnotation] {
        guard let document else { return [] }
        var annotations: [LaTeXAnnotation] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            annotations.append(contentsOf: page.annotations.compactMap { $0 as? LaTeXAnnotation })
        }
        return annotations
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        if currentAppMode == .addMath {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if currentAppMode == .addMath {
            NSCursor.crosshair.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.window?.acceptsMouseMovedEvents = true
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate]) { [weak self] event in
                guard let self, self.currentAppMode == .addMath, self.containsWindowEvent(event) else {
                    return event
                }
                NSCursor.crosshair.set()
                if event.type == .cursorUpdate {
                    return nil
                }
                return event
            }
        }
        refreshCursorForCurrentMode()
    }

    deinit {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
    }

    func refreshCursorForCurrentMode() {
        window?.invalidateCursorRects(for: self)
        if let documentView {
            window?.invalidateCursorRects(for: documentView)
        }
        if currentAppMode == .addMath {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func containsWindowEvent(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            if currentAppMode == .addMath {
                currentAppMode = .view
                NotificationCenter.default.post(name: NSNotification.Name("AppModeChangedToView"), object: nil)
                return
            }
        }
        if (event.keyCode == 51 || event.keyCode == 117),
           let sel = activeAnnotation, sel.isSelected, activeEditorPanel == nil {
            sel.page?.removeAnnotation(sel)
            deselectAll()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        // If editor is open, flash it and consume the event
        if let panel = activeEditorPanel, panel.isVisible {
            panel.flash()
            panel.orderFront(nil)
            return
        }

        self.window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: true) else {
            deselectAll(forceFullRedraw: true)
            return
        }
        let pagePoint = convert(point, to: page)

        if currentAppMode == .addMath {
            deselectAll()
            let newBounds = CGRect(x: pagePoint.x, y: pagePoint.y - 30, width: 250, height: 60)
            let ann = LaTeXAnnotation(bounds: newBounds, latex: "")
            ann.fontSize = currentFontSize
            ann.textColor = currentTextColor
            page.addAnnotation(ann)
            selectAnnotation(ann)
            beginEditing(ann, on: page)
            currentAppMode = .view
            NotificationCenter.default.post(name: NSNotification.Name("AppModeChangedToView"), object: nil)
            return
        }

        if let sel = activeAnnotation, sel.isSelected {
            if let corner = getCornerHit(pagePoint, annotation: sel) {
                dragState = .resizing(corner: corner)
                dragStartPoint = pagePoint
                dragStartBounds = sel.bounds
                return
            }
        }

        if let ann = page.annotation(at: pagePoint) as? LaTeXAnnotation {
            if event.clickCount == 2 {
                beginEditing(ann, on: page)
            } else {
                selectAnnotation(ann)
                dragState = .moving
                dragStartPoint = pagePoint
                dragStartBounds = ann.bounds
            }
        } else {
            deselectAll(forceFullRedraw: true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragState != .none, let ann = activeAnnotation, let page = ann.page else {
            super.mouseDragged(with: event); return
        }
        let pt = convert(convert(event.locationInWindow, from: nil), to: page)
        let dx = pt.x - dragStartPoint.x
        let dy = pt.y - dragStartPoint.y
        var nb = dragStartBounds
        switch dragState {
        case .moving:
            nb.origin.x += dx; nb.origin.y += dy
        case .resizing(let c):
            switch c {
            case .bottomLeft:  nb.origin.x += dx; nb.size.width -= dx; nb.origin.y += dy; nb.size.height -= dy
            case .bottomRight: nb.size.width += dx; nb.origin.y += dy; nb.size.height -= dy
            case .topLeft:     nb.origin.x += dx; nb.size.width -= dx; nb.size.height += dy
            case .topRight:    nb.size.width += dx; nb.size.height += dy
            }
            nb.size.width = max(nb.size.width, 50)
            nb.size.height = max(nb.size.height, 20)
        case .none: break
        }
        ann.bounds = nb
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if dragState != .none {
            if case .resizing(_) = dragState, let ann = activeAnnotation { rerenderAnnotation(ann) }
            dragState = .none
            return
        }
        super.mouseUp(with: event)
    }

    func selectAnnotation(_ ann: LaTeXAnnotation) {
        deselectAll()
        activeAnnotation = ann
        ann.isSelected = true
        invalidateAnnotationDisplay(ann)
        onSelectionChanged?(ann)
    }

    func deselectAll(forceFullRedraw: Bool = false) {
        var changedAnnotations: [LaTeXAnnotation] = []
        if let doc = document {
            for i in 0..<doc.pageCount {
                if let pg = doc.page(at: i) {
                    for a in pg.annotations {
                        guard let annotation = a as? LaTeXAnnotation, annotation.isSelected else { continue }
                        annotation.isSelected = false
                        changedAnnotations.append(annotation)
                    }
                }
            }
        }
        activeAnnotation = nil
        changedAnnotations.forEach(invalidateAnnotationDisplay)
        if forceFullRedraw || !changedAnnotations.isEmpty {
            invalidatePDFDisplayImmediately()
        } else {
            needsDisplay = true
        }
        onSelectionChanged?(nil)
    }

    private func invalidateAnnotationDisplay(_ annotation: LaTeXAnnotation) {
        guard let page = annotation.page else {
            needsDisplay = true
            return
        }
        let dirtyRect = convert(annotation.bounds.insetBy(dx: -12, dy: -12), from: page)
        setNeedsDisplay(dirtyRect)
        needsDisplay = true
    }

    private func invalidatePDFDisplayImmediately() {
        setNeedsDisplay(bounds)
        needsDisplay = true
        documentView?.setNeedsDisplay(documentView?.bounds ?? bounds)
        displayIfNeeded()
        documentView?.displayIfNeeded()
    }

    private func getCornerHit(_ point: CGPoint, annotation: LaTeXAnnotation) -> ResizeCorner? {
        let s: CGFloat = 16, h = s / 2
        let r = annotation.bounds
        if CGRect(x: r.minX-h, y: r.minY-h, width: s, height: s).contains(point) { return .bottomLeft }
        if CGRect(x: r.maxX-h, y: r.minY-h, width: s, height: s).contains(point) { return .bottomRight }
        if CGRect(x: r.minX-h, y: r.maxY-h, width: s, height: s).contains(point) { return .topLeft }
        if CGRect(x: r.maxX-h, y: r.maxY-h, width: s, height: s).contains(point) { return .topRight }
        return nil
    }

    // MARK: - Editing
    func beginEditing(_ annotation: LaTeXAnnotation, on page: PDFPage) {
        // Silently dismiss any existing panel without triggering its callbacks
        activeEditorPanel?.onRender = nil
        activeEditorPanel?.onDiscard = nil
        activeEditorPanel?.close()
        activeEditorPanel = nil

        selectAnnotation(annotation)

        let panel = LaTeXEditorPanel()
        panel.setText(annotation.latexCode)
        panel.setRenderedTextColor(annotation.textColor)

        panel.onRender = { [weak self, weak annotation, weak page] text, textColor in
            guard let self, let ann = annotation, let pg = page else { return }
            self.finishEditing(annotation: ann, on: pg, text: text, textColor: textColor)
        }
        panel.onDiscard = { [weak self] in
            self?.activeEditorPanel = nil
            self?.onEditingStateChanged?(false)
        }

        if let win = self.window {
            let annotViewRect = self.convert(annotation.bounds, from: page)
            let annotWinRect = self.convert(annotViewRect, to: nil)
            let annotScreenRect = win.convertToScreen(annotWinRect)
            panel.positionNear(annotScreenRect: annotScreenRect)
        }

        panel.makeKeyAndOrderFront(nil)
        panel.focusTextView()
        activeEditorPanel = panel
        onEditingStateChanged?(true)
    }

    private func finishEditing(annotation: LaTeXAnnotation, on page: PDFPage, text: String, textColor: NSColor) {
        // Detach callbacks before closing to avoid double-fire
        activeEditorPanel?.onRender = nil
        activeEditorPanel?.onDiscard = nil
        activeEditorPanel?.close()
        activeEditorPanel = nil
        onEditingStateChanged?(false)

        annotation.latexCode = text
        annotation.textColor = textColor
        annotation.syncPortableMetadata()
        currentTextColor = textColor

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            page.removeAnnotation(annotation)
            activeAnnotation = nil
            onSelectionChanged?(nil)
        } else {
            rerenderAnnotation(annotation)
            onSelectionChanged?(annotation)
        }
        needsDisplay = true
    }

    func rerenderAnnotation(_ annotation: LaTeXAnnotation, preserveWidth: Bool = true) {
        Task { @MainActor in
            annotation.syncPortableMetadata()
            let targetWidth = preserveWidth ? annotation.bounds.width : 250
            let rendered = NativeAnnotationRenderer.shared.render(
                source: annotation.latexCode,
                width: targetWidth,
                fontSize: annotation.fontSize,
                textColor: annotation.textColor
            )
            if let rendered {
                let oldTop = annotation.bounds.maxY
                annotation.bounds = CGRect(
                    x: annotation.bounds.origin.x,
                    y: oldTop - rendered.size.height,
                    width: preserveWidth ? annotation.bounds.width : rendered.size.width,
                    height: rendered.size.height
                )
                annotation.syncPortableMetadata()
            }
            annotation.renderedContent = rendered
            self.invalidateAnnotationDisplay(annotation)
        }
    }
}

// MARK: - SwiftUI Wrapper
struct PDFKitView: NSViewRepresentable {
    let url: URL?
    let pdfView: MathPDFView

    func makeNSView(context: Context) -> MathPDFView {
        pdfView.autoScales = true
        return pdfView
    }

    func updateNSView(_ nsView: MathPDFView, context: Context) {
        if let url = url, nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
            loadCustomAnnotations(in: nsView)
            nsView.refreshCursorForCurrentMode()
        }
    }

    func loadCustomAnnotations(in view: MathPDFView) {
        guard let doc = view.document else { return }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for annot in page.annotations {
                if let existing = annot as? LaTeXAnnotation {
                    existing.syncPortableMetadata()
                    continue
                }
                guard LaTeXAnnotation.isStoredAnnoTexAnnotation(annot),
                      let source = LaTeXAnnotation.storedSource(from: annot),
                      !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let newAnnot = LaTeXAnnotation(bounds: annot.bounds, latex: source)
                if let storedFontSize = annot.value(forAnnotationKey: LaTeXAnnotation.fontSizeKey) as? NSNumber {
                    newAnnot.fontSize = CGFloat(storedFontSize.doubleValue)
                }
                if let storedTextColor = annot.value(forAnnotationKey: LaTeXAnnotation.textColorKey) as? String,
                   let textColor = NSColor(annotexHexString: storedTextColor) {
                    newAnnot.textColor = textColor
                }
                page.removeAnnotation(annot)
                page.addAnnotation(newAnnot)
                Task { @MainActor in
                    newAnnot.renderedContent = NativeAnnotationRenderer.shared.render(
                        source: source,
                        width: newAnnot.bounds.width,
                        fontSize: newAnnot.fontSize,
                        textColor: newAnnot.textColor
                    )
                    view.needsDisplay = true
                }
            }
        }
    }
}

// MARK: - App Entry Point
@main
struct AnnoTexApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
