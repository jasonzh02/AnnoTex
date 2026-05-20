import SwiftUI
import PDFKit
import CoreText
import LaTeXSwiftUI
import MathJaxSwift
import SwiftDraw

// MARK: - LaTeX Annotation
class LaTeXAnnotation: PDFAnnotation {
    static let metadataVersion = "1"
    static let rendererVersion = "native-coretext-v1"
    static let markerValue = "AnnoTex.LaTeXAnnotation"

    static let markerKey = PDFAnnotationKey(rawValue: "/AnnoTexKind")
    static let sourceKey = PDFAnnotationKey(rawValue: "/AnnoTexSource")
    static let fontSizeKey = PDFAnnotationKey(rawValue: "/AnnoTexFontSize")
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
    }
}

// MARK: - Native Annotation Renderer
enum RenderedAnnotationSizingMode {
    case naturalSize
    case wrapsToWidth
}

struct RenderedAnnotation {
    let lines: [CTLine]
    let metrics: [(ascent: CGFloat, descent: CGFloat, leading: CGFloat, width: CGFloat)]
    let image: NSImage?
    let size: CGSize
    let padding: CGFloat
    let sizingMode: RenderedAnnotationSizingMode

    func draw(in context: CGContext, bounds: CGRect) {
        if let image {
            context.saveGState()
            context.interpolationQuality = .high
            let previousContext = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let imageRect: NSRect
            switch sizingMode {
            case .naturalSize:
                imageRect = NSRect(
                    x: bounds.minX + padding,
                    y: bounds.maxY - padding - image.size.height,
                    width: image.size.width,
                    height: image.size.height
                )
            case .wrapsToWidth:
                imageRect = bounds.insetBy(dx: padding, dy: padding)
            }
            image.draw(
                in: imageRect,
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1
            )
            NSGraphicsContext.current = previousContext
            context.restoreGState()
            return
        }

        context.setFillColor(NSColor.black.cgColor)
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

    private struct MathSVG {
        let svg: String
        let geometry: SVGGeometry
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
    private let mathRenderQueue = DispatchQueue(label: "annotex.mathjax.render")
    private let correctedDigitsPattern = #"^(?:[0-9]+(?:\{,\}[0-9]{3})*(?:\.[0-9]*)?|\.[0-9]+)"#
    private var mathSVGCache: [String: MathSVG] = [:]
    private lazy var mathJax: MathJax? = {
        do {
            return try MathJax(preferredOutputFormats: [.svg])
        } catch {
            NSLog("Error creating MathJax renderer: \(error)")
            return nil
        }
    }()

    private init() {}

    func sourceRequiresMathRendering(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return containsMathDelimiter(trimmed) || looksLikeBareMath(trimmed)
    }

    func render(source: String, width: CGFloat, fontSize: CGFloat) -> RenderedAnnotation? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let latex = mathOnlySource(from: trimmed), let image = renderMathImage(latex, fontSize: fontSize) {
            return renderedAnnotation(for: image, width: width, fontSize: fontSize, sizingMode: .naturalSize)
        }
        return renderMixed(source: source, width: width, fontSize: fontSize)
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

    private func renderMixed(source: String, width: CGFloat, fontSize: CGFloat) -> RenderedAnnotation? {
        let lines = source.components(separatedBy: .newlines)
        guard lines.contains(where: containsMathDelimiter) else { return nil }

        let font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let maxContentWidth = max(width - padding * 2, 10)
        let renderedLines = lines.compactMap { line -> [RenderedLine]? in
            guard let segments = parseInlineSegments(line) else { return nil }
            return renderLines(
                segments: segments,
                font: font,
                textAttributes: textAttributes,
                fontSize: fontSize,
                maxContentWidth: maxContentWidth
            )
        }.flatMap { $0 }
        guard !renderedLines.isEmpty else { return nil }
        guard let image = composeImage(lines: renderedLines, contentWidth: maxContentWidth) else { return nil }
        return renderedAnnotation(for: image, width: width, fontSize: fontSize, sizingMode: .wrapsToWidth)
    }

    private func containsMathDelimiter(_ line: String) -> Bool {
        line.contains("$") || line.contains("\\(")
    }

    private func looksLikeBareMath(_ source: String) -> Bool {
        source.contains("\\") || source.contains("_") || source.contains("^")
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
                guard let renderedMath = renderMathSegment(latex, font: font, fontSize: fontSize) else { return nil }
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

    private func renderMathSegment(_ latex: String, font: NSFont, fontSize: CGFloat) -> MathRenderResult? {
        guard let image = renderMathImage(latex, fontSize: fontSize) else { return nil }
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
        mathSVG(for: latex)?.geometry
    }

    private func parseSVGGeometry(_ svg: String) -> SVGGeometry? {
        guard let svgElement = firstSVGElement(in: svg) else { return nil }
        let attributes = svgAttributes(in: svgElement)
        guard let width = attributes["width"].flatMap(parseExValue),
              let height = attributes["height"].flatMap(parseExValue) else {
            return nil
        }
        let verticalAlignment = attributes["style"].flatMap(parseVerticalAlignment) ?? 0
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

    private func renderMathImage(_ latex: String, fontSize: CGFloat) -> NSImage? {
        guard let renderedSVG = mathSVG(for: latex) else { return nil }
        let size = CGSize(
            width: max(renderedSVG.geometry.width * mathXHeight(for: fontSize), 1),
            height: max(renderedSVG.geometry.height * mathXHeight(for: fontSize), 1)
        )
        return rasterizeSVG(renderedSVG.svg, size: size, scale: displayScale)
    }

    private func mathSVG(for latex: String) -> MathSVG? {
        mathRenderQueue.sync { () -> MathSVG? in
            if let cachedSVG = mathSVGCache[latex] {
                return cachedSVG
            }
            guard let mathJax else { return nil }

            var conversionError: Error?
            let rawSVG = mathJax.tex2svg(
                latex,
                styles: false,
                inputOptions: correctedTeXInputOptions(),
                error: &conversionError
            )
            if let error = conversionError {
                NSLog("MathJax conversion produced rendered error SVG: \(error)")
            }

            let patchedSVG = patchStrokeAttributes(in: rawSVG)
            guard let geometry = parseSVGGeometry(patchedSVG) else { return nil }
            let renderedSVG = MathSVG(svg: patchedSVG, geometry: geometry)
            mathSVGCache[latex] = renderedSVG
            return renderedSVG
        }
    }

    private func correctedTeXInputOptions() -> TeXInputProcessorOptions {
        TeXInputProcessorOptions(
            loadPackages: TeXInputProcessorOptions.Packages.all,
            digits: correctedDigitsPattern
        )
    }

    private func rasterizeSVG(_ svgString: String, size: CGSize, scale: CGFloat) -> NSImage? {
        guard let data = svgString.data(using: .utf8),
              let svg = SwiftDraw.SVG(data: data) else {
            return nil
        }
        let pixelWidth = max(Int(ceil(size.width * scale)), 1)
        let pixelHeight = max(Int(ceil(size.height * scale)), 1)
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.draw(svg, in: CGRect(origin: .zero, size: size))
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }

    private func patchStrokeAttributes(in svgString: String) -> String {
        var result = svgString

        if let dataLineRegex = try? NSRegularExpression(
            pattern: #"(<line\b[^>]*\bdata-line\b[^>]*?)(\/?>)"#
        ) {
            let mutable = NSMutableString(string: result)
            dataLineRegex.replaceMatches(
                in: mutable,
                range: NSRange(location: 0, length: mutable.length),
                withTemplate: ##"$1 stroke="#000" stroke-width="70" $2"##
            )
            result = mutable as String
        }

        if let borderLineRegex = try? NSRegularExpression(
            pattern: #"(<line\b(?![^>]*\bdata-line\b)(?![^>]*\bstroke=")[^>]*?\bstroke-width="[^"]*"[^>]*?)(\/?>)"#
        ) {
            let mutable = NSMutableString(string: result)
            borderLineRegex.replaceMatches(
                in: mutable,
                range: NSRange(location: 0, length: mutable.length),
                withTemplate: ##"$1 stroke="#000" $2"##
            )
            result = mutable as String
        }

        if let rectRegex = try? NSRegularExpression(
            pattern: #"(<rect\b[^>]*\bdata-frame\b(?![^>]*\bstroke=")[^>]*?)(\/?>)"#
        ) {
            let mutable = NSMutableString(string: result)
            rectRegex.replaceMatches(
                in: mutable,
                range: NSRange(location: 0, length: mutable.length),
                withTemplate: ##"$1 stroke="#000" stroke-width="70" fill="none" $2"##
            )
            result = mutable as String
        }

        return result
    }

    private func mathXHeight(for fontSize: CGFloat) -> CGFloat {
        max(fontSize * 0.45, 1)
    }

    private func renderedAnnotation(
        for image: NSImage,
        width: CGFloat,
        fontSize: CGFloat,
        sizingMode: RenderedAnnotationSizingMode
    ) -> RenderedAnnotation {
        let renderedWidth: CGFloat
        switch sizingMode {
        case .naturalSize:
            renderedWidth = max(image.size.width + padding * 2, 50)
        case .wrapsToWidth:
            renderedWidth = max(width, image.size.width + padding * 2, 50)
        }
        return RenderedAnnotation(
            lines: [],
            metrics: [],
            image: image,
            size: CGSize(
                width: renderedWidth,
                height: max(image.size.height + padding * 2, fontSize + padding * 2)
            ),
            padding: padding,
            sizingMode: sizingMode
        )
    }

#if DEBUG
    func debugMathSVG(for latex: String) -> String? {
        mathSVG(for: latex)?.svg
    }
#endif
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

    func render(source: String, width: CGFloat, fontSize: CGFloat) -> RenderedAnnotation? {
        let mathRenderer = MathJaxAnnotationRenderer.shared
        if let rendered = mathRenderer.render(source: source, width: width, fontSize: fontSize) {
            return rendered
        }
        if mathRenderer.sourceRequiresMathRendering(source) {
            return nil
        }

        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let attributedParagraphs = source
            .components(separatedBy: .newlines)
            .map { attributedLine(for: $0, fontSize: fontSize) }
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
            sizingMode: .wrapsToWidth
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

    private func attributedLine(for line: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = line.startIndex
        var plainBuffer = ""

        func flushPlain() {
            guard !plainBuffer.isEmpty else { return }
            result.append(NSAttributedString(string: plainBuffer, attributes: textAttributes(fontSize: fontSize)))
            plainBuffer.removeAll()
        }

        while index < line.endIndex {
            if line[index] == "$", let close = line[line.index(after: index)...].firstIndex(of: "$") {
                flushPlain()
                let math = String(line[line.index(after: index)..<close])
                result.append(attributedMath(for: math, fontSize: fontSize))
                index = line.index(after: close)
            } else {
                plainBuffer.append(line[index])
                index = line.index(after: index)
            }
        }
        flushPlain()
        return result
    }

    private func attributedMath(for math: String, fontSize: CGFloat) -> NSAttributedString {
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
                        appendMathToken(numerator, to: result, fontSize: fontSize * 0.78, baseline: fontSize * 0.24)
                        appendMathToken("⁄", to: result, fontSize: fontSize)
                        appendMathToken(denominator, to: result, fontSize: fontSize * 0.78, baseline: -fontSize * 0.20)
                        i = parsed.nextIndex
                        continue
                    }
                }
                appendMathToken(greek[command] ?? symbols[command] ?? command, to: result, fontSize: fontSize)
                i = nextIndex
            } else if char == "^" || char == "_" {
                let parsed = readScript(chars, from: i + 1)
                let scriptSize = fontSize * 0.68
                let offset = char == "^" ? fontSize * 0.38 : -fontSize * 0.22
                appendMathToken(parsed.value, to: result, fontSize: scriptSize, baseline: offset)
                i = parsed.nextIndex
            } else if char == "{" || char == "}" {
                i += 1
            } else {
                appendMathToken(String(char), to: result, fontSize: fontSize)
                i += 1
            }
        }

        return result
    }

    private func appendMathToken(_ token: String, to result: NSMutableAttributedString, fontSize: CGFloat, baseline: CGFloat = 0) {
        var attributes = textAttributes(fontSize: fontSize)
        if baseline != 0 {
            attributes[.baselineOffset] = baseline
        }
        result.append(NSAttributedString(string: token, attributes: attributes))
    }

    private func textAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
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

    var onRender: ((String) -> Void)?
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
        onRender?(innerTextView.string)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 36 {
            renderPressed()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func close() {
        onDiscard?()
        super.close()
    }

    var text: String { innerTextView.string }
    func setText(_ s: String) {
        innerTextView.string = s
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

private final class SelectionOverlayView: NSView {
    weak var pdfView: MathPDFView?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        pdfView?.drawSelectionOverlay(in: context, overlayView: self)
    }
}

class MathPDFView: PDFView {
    private var activeEditorPanel: LaTeXEditorPanel?
    private var activeAnnotation: LaTeXAnnotation?
    private var selectedAnnotations: Set<LaTeXAnnotation> = []
    private weak var selectionOverlayView: SelectionOverlayView?
    private weak var selectionOverlayHostView: NSView?
    private weak var observedScrollClipView: NSClipView?
    private var scrollBoundsObserver: NSObjectProtocol?
    private var visiblePagesObserver: NSObjectProtocol?
    var currentFontSize: CGFloat = 12.0
    private var eventMonitor: Any?
    private var dragState: DragState = .none
    private var dragStartPoint: CGPoint = .zero
    private var dragStartBounds: CGRect = .zero
    private var dragStartBoundsByAnnotation: [LaTeXAnnotation: CGRect] = [:]

    var currentAppMode: AppMode = .view {
        didSet { refreshCursorForCurrentMode() }
    }
    var onSelectionChanged: ((LaTeXAnnotation?) -> Void)?
    var onEditingStateChanged: ((Bool) -> Void)?

    func updateActiveFontSize() {
        guard activeEditorPanel == nil, !selectedAnnotations.isEmpty else { return }
        for annotation in selectedAnnotations {
            annotation.fontSize = currentFontSize
            rerenderAnnotation(annotation)
        }
    }

    @MainActor
    func writePortableDocument(to url: URL) async -> Bool {
        guard let document else { return false }
        let annotations = allAnnoTexAnnotations()
        let selectedAnnotationsBeforeSave = annotations.filter { $0.isSelected }
        await prepareAnnotationsForPortableSave(annotations)
        let succeeded = document.write(to: url)
        selectedAnnotationsBeforeSave.forEach { $0.isSelected = true }
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
                    fontSize: annotation.fontSize
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
        ensureSelectionOverlayView()
        installSelectionOverlayInvalidationObservers()
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

    override func layout() {
        super.layout()
        ensureSelectionOverlayView()
        installSelectionOverlayInvalidationObservers()
        invalidateSelectionOverlay()
    }

    deinit {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
        if let visiblePagesObserver {
            NotificationCenter.default.removeObserver(visiblePagesObserver)
        }
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

    private func ensureSelectionOverlayView() {
        let hostView = documentView ?? self
        if let selectionOverlayView, selectionOverlayHostView === hostView {
            selectionOverlayView.frame = hostView.bounds
            return
        }

        selectionOverlayView?.removeFromSuperview()
        let overlay = SelectionOverlayView(frame: hostView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.pdfView = self
        hostView.addSubview(overlay, positioned: .above, relativeTo: nil)
        selectionOverlayView = overlay
        selectionOverlayHostView = hostView
    }

    private func installSelectionOverlayInvalidationObservers() {
        if visiblePagesObserver == nil {
            visiblePagesObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewVisiblePagesChanged,
                object: self,
                queue: .main
            ) { [weak self] _ in
                self?.invalidateSelectionOverlay(immediate: true)
            }
        }

        guard let clipView = documentView?.enclosingScrollView?.contentView,
              observedScrollClipView !== clipView else { return }

        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }

        clipView.postsBoundsChangedNotifications = true
        observedScrollClipView = clipView
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateSelectionOverlay(immediate: true)
        }
    }

    private func invalidateSelectionOverlay(immediate: Bool = false) {
        ensureSelectionOverlayView()
        selectionOverlayView?.needsDisplay = true
        if immediate {
            selectionOverlayView?.displayIfNeeded()
        }
    }

    fileprivate func drawSelectionOverlay(in context: CGContext, overlayView: NSView) {
        for annotation in selectedAnnotations {
            guard let page = annotation.page else { continue }
            let viewRect = convert(annotation.bounds, from: page)
            let overlayRect = overlayView.convert(viewRect, from: self)
            drawSelectionDecoration(in: context, bounds: overlayRect)
        }
    }

    private func drawSelectionDecoration(in context: CGContext, bounds: CGRect) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        let s: CGFloat = 4, h = s / 2
        let r = bounds.insetBy(dx: 5, dy: 5)
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            if currentAppMode == .addMath {
                currentAppMode = .view
                NotificationCenter.default.post(name: NSNotification.Name("AppModeChangedToView"), object: nil)
                return
            }
        }
        if (event.keyCode == 51 || event.keyCode == 117),
           activeEditorPanel == nil, !selectedAnnotations.isEmpty {
            let annotationsToDelete = Array(selectedAnnotations)
            for annotation in annotationsToDelete {
                invalidateAnnotationDisplay(annotation)
                annotation.page?.removeAnnotation(annotation)
            }
            setSelectedAnnotations([], primary: nil, forceFullRedraw: true)
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
            page.addAnnotation(ann)
            selectAnnotation(ann)
            beginEditing(ann, on: page)
            currentAppMode = .view
            NotificationCenter.default.post(name: NSNotification.Name("AppModeChangedToView"), object: nil)
            return
        }

        for sel in selectedAnnotations where sel.page === page && sel.isSelected {
            if let corner = getCornerHit(pagePoint, annotation: sel) {
                setSelectedAnnotations(selectedAnnotations, primary: sel)
                dragState = .resizing(corner: corner)
                dragStartPoint = pagePoint
                dragStartBounds = sel.bounds
                dragStartBoundsByAnnotation = [sel: sel.bounds]
                return
            }
        }

        if let ann = page.annotation(at: pagePoint) as? LaTeXAnnotation {
            if event.clickCount == 2 {
                beginEditing(ann, on: page)
            } else {
                if event.modifierFlags.contains(.shift) {
                    let wasSelected = ann.isSelected
                    toggleSelection(of: ann)
                    guard !wasSelected else { return }
                } else if ann.isSelected {
                    setSelectedAnnotations(selectedAnnotations, primary: ann)
                } else {
                    selectAnnotation(ann)
                }
                dragState = .moving
                dragStartPoint = pagePoint
                dragStartBounds = ann.bounds
                dragStartBoundsByAnnotation = Dictionary(
                    uniqueKeysWithValues: selectedAnnotations.map { ($0, $0.bounds) }
                )
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
            selectedAnnotations.forEach { invalidateAnnotationDisplay($0) }
            for annotation in selectedAnnotations {
                guard var bounds = dragStartBoundsByAnnotation[annotation] else { continue }
                bounds.origin.x += dx
                bounds.origin.y += dy
                annotation.bounds = bounds
                annotation.syncPortableMetadata()
            }
            selectedAnnotations.forEach { invalidateAnnotationDisplay($0) }
            invalidateSelectionOverlay(immediate: true)
            flushPDFDisplay()
            return
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
        invalidateAnnotationDisplay(ann)
        ann.bounds = nb
        ann.syncPortableMetadata()
        invalidateAnnotationDisplay(ann)
        invalidateSelectionOverlay(immediate: true)
        flushPDFDisplay()
    }

    override func mouseUp(with event: NSEvent) {
        if dragState != .none {
            if case .resizing(_) = dragState, let ann = activeAnnotation { rerenderAnnotation(ann) }
            dragState = .none
            dragStartBoundsByAnnotation = [:]
            return
        }
        super.mouseUp(with: event)
    }

    func selectAnnotation(_ ann: LaTeXAnnotation) {
        setSelectedAnnotations([ann], primary: ann)
    }

    private func toggleSelection(of annotation: LaTeXAnnotation) {
        var nextSelection = selectedAnnotations
        let primary: LaTeXAnnotation?
        if nextSelection.contains(annotation) {
            nextSelection.remove(annotation)
            primary = nextSelection.first
        } else {
            nextSelection.insert(annotation)
            primary = annotation
        }
        setSelectedAnnotations(nextSelection, primary: primary, forceFullRedraw: true)
    }

    func deselectAll(forceFullRedraw: Bool = false) {
        setSelectedAnnotations([], primary: nil, forceFullRedraw: forceFullRedraw)
    }

    private func setSelectedAnnotations(
        _ newSelection: Set<LaTeXAnnotation>,
        primary: LaTeXAnnotation?,
        forceFullRedraw: Bool = false
    ) {
        var changedAnnotations = Array(selectedAnnotations.symmetricDifference(newSelection))
        if let doc = document {
            for i in 0..<doc.pageCount {
                if let pg = doc.page(at: i) {
                    for a in pg.annotations {
                        guard let annotation = a as? LaTeXAnnotation else { continue }
                        let shouldBeSelected = newSelection.contains(annotation)
                        if annotation.isSelected != shouldBeSelected {
                            annotation.isSelected = shouldBeSelected
                            if !changedAnnotations.contains(annotation) {
                                changedAnnotations.append(annotation)
                            }
                        }
                    }
                }
            }
        }
        selectedAnnotations = newSelection
        activeAnnotation = primary ?? newSelection.first
        if let activeAnnotation {
            currentFontSize = activeAnnotation.fontSize
        }
        changedAnnotations.forEach { invalidateAnnotationDisplay($0, notifyPDFKit: true) }
        if forceFullRedraw || !changedAnnotations.isEmpty {
            invalidatePDFDisplayImmediately()
        } else {
            needsDisplay = true
        }
        invalidateSelectionOverlay(immediate: true)
        onSelectionChanged?(activeAnnotation)
    }

    private func invalidateAnnotationDisplay(_ annotation: LaTeXAnnotation, notifyPDFKit: Bool = false) {
        guard let page = annotation.page else {
            needsDisplay = true
            return
        }
        if notifyPDFKit {
            annotationsChanged(on: page)
        }
        let dirtyRect = convert(annotation.bounds.insetBy(dx: -12, dy: -12), from: page)
        setNeedsDisplay(dirtyRect)
        if let documentView {
            documentView.setNeedsDisplay(documentView.convert(dirtyRect, from: self))
        }
        needsDisplay = true
    }

    private func invalidatePDFDisplayImmediately() {
        setNeedsDisplay(bounds)
        needsDisplay = true
        documentView?.setNeedsDisplay(documentView?.bounds ?? bounds)
        invalidateSelectionOverlay()
        flushPDFDisplay()
    }

    private func flushPDFDisplay() {
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

        panel.onRender = { [weak self, weak annotation, weak page] text in
            guard let self, let ann = annotation, let pg = page else { return }
            self.finishEditing(annotation: ann, on: pg, text: text)
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

    private func finishEditing(annotation: LaTeXAnnotation, on page: PDFPage, text: String) {
        // Detach callbacks before closing to avoid double-fire
        activeEditorPanel?.onRender = nil
        activeEditorPanel?.onDiscard = nil
        activeEditorPanel?.close()
        activeEditorPanel = nil
        onEditingStateChanged?(false)

        annotation.latexCode = text
        annotation.syncPortableMetadata()

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            page.removeAnnotation(annotation)
            var nextSelection = selectedAnnotations
            nextSelection.remove(annotation)
            setSelectedAnnotations(nextSelection, primary: nextSelection.first, forceFullRedraw: true)
        } else {
            rerenderAnnotation(annotation)
            setSelectedAnnotations(selectedAnnotations.union([annotation]), primary: annotation)
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
                fontSize: annotation.fontSize
            )
            if let rendered {
                let oldTop = annotation.bounds.maxY
                let shouldPreserveWidth = preserveWidth && rendered.sizingMode == .wrapsToWidth
                annotation.bounds = CGRect(
                    x: annotation.bounds.origin.x,
                    y: oldTop - rendered.size.height,
                    width: shouldPreserveWidth ? annotation.bounds.width : rendered.size.width,
                    height: rendered.size.height
                )
                annotation.syncPortableMetadata()
            }
            annotation.renderedContent = rendered
            self.invalidateAnnotationDisplay(annotation)
            self.invalidateSelectionOverlay(immediate: true)
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
            nsView.deselectAll(forceFullRedraw: true)
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
                page.removeAnnotation(annot)
                page.addAnnotation(newAnnot)
                Task { @MainActor in
                    newAnnot.renderedContent = NativeAnnotationRenderer.shared.render(
                        source: source,
                        width: newAnnot.bounds.width,
                        fontSize: newAnnot.fontSize
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
