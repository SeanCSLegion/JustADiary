import UIKit

struct ShareBlock {
    var time: Int64
    var loc: String
    var parts: [ContentPart]
}

enum ShareRenderer {
    static let width = 720.0
    static let blockLeft = 108.0
    static let side = 48.0
    static let tlLineX = 61.0
    static let tlLineW = 3.0
    static let dateY = 64.0
    static let footerH = 34.0
    static let contentWidth = width - blockLeft - side

    struct Palette {
        var text: UIColor
        var sub: UIColor
        var faint: UIColor
        var bgTop: UIColor
        var bgMid: UIColor
        var bgBottom: UIColor
        var accentA: UIColor
        var accentB: UIColor
        var accentC: UIColor
        var quoteBg: UIColor

        static func light() -> Palette {
            Palette(text: UIColor(hex: 0x191C20), sub: UIColor(hex: 0x44474F),
                    faint: UIColor(red: 25/255, green: 28/255, blue: 32/255, alpha: 0.38),
                    bgTop: UIColor(hex: 0xFBFBFE), bgMid: UIColor(hex: 0xF3F6FD), bgBottom: UIColor(hex: 0xF7F2FF),
                    accentA: UIColor(hex: 0x6E8BFF), accentB: UIColor(hex: 0x9B6BFF), accentC: UIColor(hex: 0x3FB6FF),
                    quoteBg: UIColor(hex: 0xE4EAF9))
        }

        static func dark() -> Palette {
            Palette(text: UIColor(hex: 0xE1E2E8), sub: UIColor(hex: 0xC5C6D0),
                    faint: UIColor(red: 225/255, green: 226/255, blue: 232/255, alpha: 0.38),
                    bgTop: UIColor(hex: 0x101318), bgMid: UIColor(hex: 0x131826), bgBottom: UIColor(hex: 0x131826),
                    accentA: UIColor(hex: 0x4A7DFF), accentB: UIColor(hex: 0xA56BFF), accentC: UIColor(hex: 0x38BDF8),
                    quoteBg: UIColor(hex: 0x2B3344))
        }
    }

    struct Layout {
        var height: Double
        var blockRects: [CGRect]
        var partRects: [[CGRect]]
    }

    static func layout(dateText: String, startLine: String, blocks: [ShareBlock]) -> Layout {
        var y = dateY
        y += 70
        y += startLineHeight(startLine)
        y += 2 + 24
        var blockRects: [CGRect] = []
        var partRects: [[CGRect]] = []
        for block in blocks {
            let blockTop = y
            y += 36
            y += 20
            y += 34
            var parts: [CGRect] = []
            for part in block.parts {
                let rect = partRect(part, y: y)
                parts.append(rect)
                y += rect.height
            }
            y += 36
            partRects.append(parts)
            blockRects.append(CGRect(x: 0, y: blockTop, width: 0, height: y - blockTop))
        }
        y += footerH
        return Layout(height: y, blockRects: blockRects, partRects: partRects)
    }

    private static func startLineHeight(_ line: String) -> Double {
        let width = contentWidth
        let font = UIFont.systemFont(ofSize: 28, weight: .regular)
        var lines = 1
        var current: Double = 0
        for ch in line {
            let w = measure(ch, font)
            if current + w > width { lines += 1; current = 0 }
            current += w
        }
        return Double(lines) * 40
    }

    private static func partRect(_ part: ContentPart, y: Double) -> CGRect {
        let font = fontForPart(part)
        let text = plainText(part)
        let width = contentWidth
        let lineHeight = lineHeightForPart(part)
        switch part.type {
        case ContentPartType.h1:
            return CGRect(x: 0, y: y, width: width, height: 52 + 12)
        case ContentPartType.h2:
            return CGRect(x: 0, y: y, width: width, height: 46 + 10)
        case ContentPartType.quote:
            let box = wrappedHeight(text, font: font, width: width - 22, lineHeight: 40, inkRatio: 0.87)
            return CGRect(x: 0, y: y, width: width, height: box)
        case ContentPartType.list, ContentPartType.todo:
            let items = part.items ?? []
            return CGRect(x: 0, y: y, width: width, height: Double(items.count) * 55)
        case ContentPartType.image:
            let h = imageHeight(part)
            return CGRect(x: 0, y: y, width: width, height: h)
        default:
            let lines = wrappedLines(text, font: font, width: width, maxLines: Int.max)
            return CGRect(x: 0, y: y, width: width, height: Double(lines.count) * lineHeight + 10)
        }
    }

    private static func wrappedHeight(_ text: String, font: UIFont, width: Double, lineHeight: Double, inkRatio: Double) -> Double {
        let lines = wrappedLines(text, font: font, width: width, maxLines: Int.max)
        var ink: Double = 0
        for line in lines {
            var maxRatio: Double = 0
            for ch in line {
                let r: Double
                if ch.isCJK { r = 0.87 }
                else if ch.isASCII { r = 0.75 }
                else { r = 0.98 }
                maxRatio = max(maxRatio, r)
            }
            ink = max(ink, maxRatio * font.pointSize)
        }
        return Double(max(1, lines.count - 1)) * lineHeight + ink + 40
    }

    private static func imageHeight(_ part: ContentPart) -> Double {
        let w = part.w ?? 0
        let h = part.h ?? 0
        let ratio: Double
        if w > 0, h > 0 {
            ratio = h / w
        } else if let img = loadImage(part.src), img.size.width > 0 {
            ratio = Double(img.size.height / img.size.width)
        } else {
            ratio = 0.75
        }
        return max(120, contentWidth * ratio)
    }

    private static func wrappedLines(_ text: String, font: UIFont, width: Double, maxLines: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        var currentW: Double = 0
        var cursor = 0
        while cursor < text.count {
            let idx = text.index(text.startIndex, offsetBy: cursor)
            let ch = text[idx]
            let w = measure(ch, font)
            if currentW + w > width, !current.isEmpty {
                lines.append(current)
                if lines.count >= maxLines { return lines }
                current = String(ch)
                currentW = w
            } else {
                current.append(ch)
                currentW += w
            }
            cursor += 1
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private static func measure(_ ch: Character, _ font: UIFont) -> Double {
        Double((String(ch) as NSString).boundingRect(with: CGSize(width: .greatestFiniteMagnitude, height: font.pointSize),
                                                     options: .usesLineFragmentOrigin,
                                                     attributes: [.font: font],
                                                     context: nil).width)
    }

    private static func fontForPart(_ part: ContentPart) -> UIFont {
        switch part.type {
        case ContentPartType.h1: return UIFont.systemFont(ofSize: 36, weight: .bold)
        case ContentPartType.h2: return UIFont.systemFont(ofSize: 32, weight: .semibold)
        case ContentPartType.quote: return UIFont.systemFont(ofSize: 30, weight: .regular)
        case ContentPartType.list, ContentPartType.todo: return UIFont.systemFont(ofSize: 30, weight: .regular)
        default: return UIFont.systemFont(ofSize: 31, weight: .regular)
        }
    }

    private static func lineHeightForPart(_ part: ContentPart) -> Double {
        switch part.type {
        case ContentPartType.h1: return 52
        case ContentPartType.h2: return 46
        case ContentPartType.quote: return 40
        case ContentPartType.list, ContentPartType.todo: return 55
        default: return 50
        }
    }

    private static func plainText(_ part: ContentPart) -> String {
        ContentFlatten.flattenPart(part)
    }

    private static func loadImage(_ src: String?) -> UIImage? {
        guard let src else { return nil }
        let path = ImagePathUtil.resolveImagePath(src)
        return UIImage(contentsOfFile: path)
    }

    static func render(dayKey: String, blocks: [ShareBlock], isDark: Bool) -> UIImage? {
        let palette = isDark ? Palette.dark() : Palette.light()
        let dateText = L10n.dateOnly(DateUtil.parseDayKey(dayKey) ?? Date())
        let firstBlock = blocks.first
        let startLine = L10n.startLine(firstBlock?.time ?? 0, locText: firstBlock?.loc ?? "")
        let layout = layout(dateText: dateText, startLine: startLine, blocks: blocks)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: layout.height), format: format)
        return renderer.image { ctx in
            let c = ctx.cgContext
            drawBackground(c, palette: palette, height: layout.height)
            var y = dateY
            drawText(dateText, x: blockLeft, y: y, font: .systemFont(ofSize: 62, weight: .bold),
                     color: palette.text)
            y += 70
            drawWrapped(startLine, x: blockLeft, y: y, width: contentWidth, font: .systemFont(ofSize: 28),
                        lineHeight: 40, color: palette.sub)
            y += startLineHeight(startLine)
            drawHairline(c, y: y, palette: palette)
            y += 24 + 2
            drawTimeline(c, from: y, to: layout.height - footerH - 20, palette: palette)
            for (bi, block) in blocks.enumerated() {
                drawNode(c, x: tlLineX, y: y + 36 + 20 - 20, palette: palette)
                drawText(L10n.timeOf(block.time), x: blockLeft, y: y + 36, font: .systemFont(ofSize: 26, weight: .bold),
                         color: palette.accentA)
                y += 36 + 20
                drawWrapped(block.loc, x: blockLeft, y: y, width: contentWidth, font: .systemFont(ofSize: 24),
                            lineHeight: 34, color: palette.sub)
                y += 34
                for (pi, part) in block.parts.enumerated() {
                    drawPart(c, part, x: blockLeft, y: y, palette: palette)
                    y += layout.partRects[bi][pi].height
                }
                y += 36
            }
            drawFooter(c, y: layout.height - footerH, palette: palette)
        }
    }

    private static func drawBackground(_ c: CGContext, palette: Palette, height: Double) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [palette.bgTop.cgColor, palette.bgMid.cgColor, palette.bgBottom.cgColor] as CFArray,
                                  locations: [0, 0.5, 1])!
        c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: height), options: [])
        drawOrb(c, x: 620, y: -80, r: 460, color: palette.accentA)
        drawOrb(c, x: -60, y: 300, r: 380, color: palette.accentB)
        drawOrb(c, x: 450, y: height + 60, r: 500, color: palette.accentC)
    }

    private static func drawOrb(_ c: CGContext, x: Double, y: Double, r: Double, color: UIColor) {
        let colors = [color.withAlphaComponent(0.45).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        c.saveGState()
        c.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        c.clip()
        c.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                             endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
        c.restoreGState()
    }

    private static func drawHairline(_ c: CGContext, y: Double, palette: Palette) {
        let colors = [UIColor.clear.cgColor, palette.accentA.withAlphaComponent(0.6).cgColor, UIColor.clear.cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
        c.drawLinearGradient(gradient, start: CGPoint(x: blockLeft, y: y), end: CGPoint(x: width - side, y: y), options: [])
    }

    private static func drawTimeline(_ c: CGContext, from: Double, to: Double, palette: Palette) {
        let colors = [palette.accentA.withAlphaComponent(0.9).cgColor,
                      palette.accentA.withAlphaComponent(0.35).cgColor,
                      palette.accentA.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
        c.saveGState()
        c.addRect(CGRect(x: tlLineX - tlLineW / 2, y: from, width: tlLineW, height: max(1, to - from)))
        c.clip()
        c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to), options: [])
        c.restoreGState()
    }

    private static func drawNode(_ c: CGContext, x: Double, y: Double, palette: Palette) {
        c.saveGState()
        c.setShadow(offset: .zero, blur: 18, color: palette.accentA.cgColor)
        c.setFillColor(palette.accentA.cgColor)
        c.fillEllipse(in: CGRect(x: x - 15, y: y - 15, width: 30, height: 30))
        c.restoreGState()
        c.setStrokeColor(palette.accentA.cgColor)
        c.setLineWidth(6)
        c.strokeEllipse(in: CGRect(x: x - 18, y: y - 18, width: 36, height: 36))
        c.setFillColor(UIColor.white.cgColor)
        c.fillEllipse(in: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
    }

    private static func drawFooter(_ c: CGContext, y: Double, palette: Palette) {
        let text = "· \(L10n.str("module_desc")) ·"
        let font = UIFont.systemFont(ofSize: 24, weight: .regular)
        let totalWidth = Double(text.count) * 6 + (text as NSString).size(withAttributes: [.font: font]).width
        var cx = (width - totalWidth) / 2
        for ch in text {
            drawText(String(ch), x: cx, y: y, font: font, color: palette.faint)
            cx += 6 + measure(ch, font)
        }
    }

    private static func drawPart(_ c: CGContext, _ part: ContentPart, x: Double, y: Double, palette: Palette) {
        let text = plainText(part)
        switch part.type {
        case ContentPartType.h1:
            drawText(text, x: x, y: y, font: .systemFont(ofSize: 36, weight: .bold), color: palette.text)
        case ContentPartType.h2:
            drawText(text, x: x, y: y, font: .systemFont(ofSize: 32, weight: .semibold), color: palette.text)
        case ContentPartType.quote:
            let bg = palette.quoteBg
            c.saveGState()
            c.setFillColor(bg.cgColor)
            let box = wrappedHeight(text, font: .systemFont(ofSize: 30), width: contentWidth - 22, lineHeight: 40, inkRatio: 0.87)
            let rect = CGRect(x: x + 22, y: y, width: contentWidth - 22, height: box)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            path.fill()
            c.restoreGState()
            drawWrapped(text, x: x + 22 + 22, y: y + 20, width: contentWidth - 22 - 22, font: .systemFont(ofSize: 30),
                        lineHeight: 40, color: palette.text)
        case ContentPartType.list:
            let items = part.items ?? []
            for (i, item) in items.enumerated() {
                let iy = y + Double(i) * 55
                drawBullet(c, x: x + 12, y: iy + 15, palette: palette)
                drawWrapped(item, x: x + 24, y: iy, width: contentWidth - 24, font: .systemFont(ofSize: 30),
                            lineHeight: 55, color: palette.text)
            }
        case ContentPartType.todo:
            let items = part.items ?? []
            let done = part.done ?? Array(repeating: false, count: items.count)
            for (i, item) in items.enumerated() {
                let iy = y + Double(i) * 55
                drawCheckbox(c, x: x, y: iy + 11, checked: done.indices.contains(i) ? done[i] : false, palette: palette)
                let color = palette.text.withAlphaComponent(done.indices.contains(i) && done[i] ? 0.45 : 1)
                drawWrapped(item, x: x + 42, y: iy, width: contentWidth - 42, font: .systemFont(ofSize: 30),
                            lineHeight: 55, color: color)
            }
        case ContentPartType.image:
            let img = loadImage(part.src)
            let h = imageHeight(part)
            let rect = CGRect(x: x, y: y, width: contentWidth, height: h)
            if let img {
                c.saveGState()
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 20)
                path.addClip()
                img.draw(in: rect)
                c.restoreGState()
            } else {
                drawPlaceholder(c, rect: rect, palette: palette)
            }
        default:
            c.saveGState()
            c.setAlpha(0.9)
            drawWrapped(text, x: x, y: y, width: contentWidth, font: .systemFont(ofSize: 31),
                        lineHeight: 50, color: palette.text)
            c.restoreGState()
        }
    }

    private static func drawBullet(_ c: CGContext, x: Double, y: Double, palette: Palette) {
        c.saveGState()
        c.setShadow(offset: .zero, blur: 8, color: palette.accentA.cgColor)
        c.setFillColor(palette.accentA.cgColor)
        c.fillEllipse(in: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11))
        c.restoreGState()
    }

    private static func drawCheckbox(_ c: CGContext, x: Double, y: Double, checked: Bool, palette: Palette) {
        let rect = CGRect(x: x, y: y, width: 28, height: 28)
        if checked {
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [palette.accentA.cgColor, palette.accentB.cgColor] as CFArray,
                                      locations: [0, 1])!
            c.saveGState()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            path.addClip()
            c.drawLinearGradient(gradient, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            c.restoreGState()
            let check = UIBezierPath()
            check.move(to: CGPoint(x: rect.minX + 7, y: rect.midY + 1))
            check.addLine(to: CGPoint(x: rect.minX + 12.5, y: rect.maxY - 7))
            check.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.minY + 7))
            check.lineWidth = 3.2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            UIColor.white.setStroke()
            check.stroke()
        } else {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            path.lineWidth = 2
            path.stroke()
        }
    }

    private static func drawPlaceholder(_ c: CGContext, rect: CGRect, palette: Palette) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [palette.surface2(palette).cgColor, palette.quoteBg(palette).cgColor] as CFArray,
                                  locations: [0, 1])!
        c.saveGState()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 20)
        path.addClip()
        c.drawLinearGradient(gradient, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        c.restoreGState()
        let label = L10n.str("share_image_placeholder") as NSString
        let size = label.size(withAttributes: [.font: UIFont.systemFont(ofSize: 26)])
        label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                   withAttributes: [.font: UIFont.systemFont(ofSize: 26), .foregroundColor: palette.faint])
    }

    private static func drawText(_ text: String, x: Double, y: Double, font: UIFont, color: UIColor) {
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func drawWrapped(_ text: String, x: Double, y: Double, width: Double, font: UIFont,
                                    lineHeight: Double, color: UIColor) {
        let lines = wrappedLines(text, font: font, width: width, maxLines: Int.max)
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: CGPoint(x: x, y: y + Double(i) * lineHeight),
                                    withAttributes: [.font: font, .foregroundColor: color])
        }
    }
}

extension ShareRenderer.Palette {
    func surface2(_ palette: ShareRenderer.Palette) -> UIColor {
        palette.bgMid
    }

    func quoteBg(_ palette: ShareRenderer.Palette) -> UIColor {
        palette.accentA.withAlphaComponent(0.08)
    }
}

private extension Character {
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    var isASCII: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.value < 128
    }
}
