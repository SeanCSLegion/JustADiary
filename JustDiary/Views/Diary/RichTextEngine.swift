import SwiftUI
import UIKit

final class RichEditorController {
    weak var textView: UITextView?
    var onFormatChange: (() -> Void)?
    var imageMaxWidth: CGFloat?

    func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: Theme.onSurfaceUIColor(),
            .paragraphStyle: NSMutableParagraphStyle()
        ]
    }

    func refreshTypingAttributes() {
        textView?.typingAttributes = baseTypingAttributes()
    }

    // MARK: - Character styles

    func toggleBold() {
        toggleFontStyle(.traitBold)
    }

    func toggleItalic() {
        toggleFontStyle(.traitItalic)
    }

    private func toggleFontStyle(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        apply { attributed in
            if range.length > 0 {
                attributed.enumerateAttribute(.font, in: range) { value, subRange, _ in
                    guard let font = value as? UIFont else { return }
                    var sym = font.fontDescriptor.symbolicTraits
                    if sym.contains(trait) {
                        sym.remove(trait)
                    } else {
                        sym.insert(trait)
                    }
                    guard let desc = font.fontDescriptor.withSymbolicTraits(sym) else { return }
                    attributed.removeAttribute(.font, range: subRange)
                    attributed.addAttribute(.font, value: UIFont(descriptor: desc, size: font.pointSize), range: subRange)
                }
            } else {
                let font = (tv.typingAttributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
                var sym = font.fontDescriptor.symbolicTraits
                if sym.contains(trait) {
                    sym.remove(trait)
                } else {
                    sym.insert(trait)
                }
                if let desc = font.fontDescriptor.withSymbolicTraits(sym) {
                    tv.typingAttributes[.font] = UIFont(descriptor: desc, size: font.pointSize)
                }
            }
        }
    }

    func toggleStrike() {
        toggleLineStyle(key: .strikethroughStyle)
    }

    func toggleUnderline() {
        toggleLineStyle(key: .underlineStyle)
    }

    private func toggleLineStyle(key: NSAttributedString.Key) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        apply { attributed in
            if range.length > 0 {
                attributed.enumerateAttribute(key, in: range) { value, subRange, _ in
                    let active = (value as? Int ?? 0) != 0
                    attributed.removeAttribute(key, range: subRange)
                    attributed.addAttribute(key, value: active ? 0 : 1, range: subRange)
                }
            } else {
                let active = (tv.typingAttributes[key] as? Int ?? 0) != 0
                tv.typingAttributes[key] = active ? 0 : 1
            }
        }
    }

    // MARK: - Paragraph styles

    func applyHeading(_ level: Int) {
        guard let tv = textView else { return }
        let size: CGFloat = level == 1 ? 22 : (level == 2 ? 18 : 15)
        let paragraphRange = paragraphRange(around: tv.selectedRange)
        apply { attributed in
            attributed.enumerateAttribute(.font, in: paragraphRange) { value, range, _ in
                guard let font = value as? UIFont else { return }
                let weight: UIFont.Weight = font.fontDescriptor.symbolicTraits.contains(.traitBold) ? .bold : .regular
                attributed.removeAttribute(.font, range: range)
                attributed.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: weight), range: range)
            }
        }
        tv.typingAttributes[.font] = UIFont.systemFont(ofSize: size)
    }

    func currentHeadingLevel() -> Int {
        guard let tv = textView, tv.textStorage.length > 0 else { return 0 }
        let range = paragraphRange(around: tv.selectedRange)
        guard range.location < tv.textStorage.length else { return 0 }
        let font = tv.textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
        let size = font?.pointSize ?? 15
        if size >= 22 { return 1 }
        if size >= 18 { return 2 }
        return 0
    }

    func toggleCenter() {
        guard let tv = textView else { return }
        let range = paragraphRange(around: tv.selectedRange)
        let center = isCenterActive()
        apply { attributed in
            attributed.enumerateAttribute(.paragraphStyle, in: range) { value, r, _ in
                let style = ((value as? NSParagraphStyle) ?? NSParagraphStyle()).mutableCopy() as! NSMutableParagraphStyle
                style.alignment = center ? .left : .center
                attributed.addAttribute(.paragraphStyle, value: style, range: r)
            }
        }
        let style = (tv.typingAttributes[.paragraphStyle] as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = center ? .left : .center
        tv.typingAttributes[.paragraphStyle] = style
    }

    func isCenterActive() -> Bool {
        guard let tv = textView, tv.textStorage.length > 0 else { return false }
        let range = paragraphRange(around: tv.selectedRange)
        guard range.location < tv.textStorage.length else { return false }
        let style = tv.textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        return style?.alignment == .center
    }

    func toggleList() {
        toggleMarkerMarker(kind: "bullet") { payload in
            payload?.kind == "bullet"
        }
    }

    func toggleTodo() {
        toggleMarkerMarker(kind: "todo") { payload in
            payload?.kind == "todo"
        }
    }

    private func toggleMarkerMarker(kind: String, isMarked: (AttachmentPayload?) -> Bool) {
        guard let tv = textView else { return }
        let selected = tv.selectedRange
        guard let startPos = tv.position(from: tv.beginningOfDocument, offset: selected.location),
              let para = tv.tokenizer.rangeEnclosingPosition(startPos, with: .paragraph, inDirection: .storage(.backward)) else { return }
        let lineRange = NSRange(location: tv.offset(from: tv.beginningOfDocument, to: para.start),
                                length: tv.offset(from: para.start, to: para.end))
        let payload: AttachmentPayload? = lineRange.location < tv.textStorage.length
            ? (tv.textStorage.attribute(.attachment, at: lineRange.location, effectiveRange: nil) as? PayloadAttachment)?.payload
            : nil
        apply { attributed in
            if isMarked(payload) {
                attributed.replaceCharacters(in: NSRange(location: lineRange.location, length: 1), with: "")
            } else {
                let attachment = MarkerAttachment.attachment(kind: kind)
                attributed.insert(NSAttributedString(attachment: attachment), at: lineRange.location)
            }
        }
    }

    func toggleQuote() {
        guard let tv = textView else { return }
        let range = paragraphRange(around: tv.selectedRange)
        let isQuote = isQuoteActive()
        let bg: UIColor = isQuote ? .clear : Theme.quoteBgUIColor()
        let size: CGFloat = isQuote ? 15 : 13
        apply { attributed in
            attributed.enumerateAttribute(.paragraphStyle, in: range) { value, r, _ in
                let style = ((value as? NSParagraphStyle) ?? NSParagraphStyle()).mutableCopy() as! NSMutableParagraphStyle
                style.lineSpacing = isQuote ? 0 : 7
                attributed.addAttribute(.paragraphStyle, value: style, range: r)
            }
            attributed.enumerateAttribute(.font, in: range) { value, r, _ in
                guard let font = value as? UIFont else { return }
                let weight: UIFont.Weight = font.fontDescriptor.symbolicTraits.contains(.traitBold) ? .bold : .regular
                attributed.removeAttribute(.font, range: r)
                attributed.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: weight), range: r)
            }
            attributed.addAttribute(.backgroundColor, value: bg, range: range)
        }
        tv.typingAttributes[.backgroundColor] = bg
        tv.typingAttributes[.font] = UIFont.systemFont(ofSize: size)
    }

    func isQuoteActive() -> Bool {
        guard let tv = textView, tv.textStorage.length > 0, tv.selectedRange.length == 0 else { return false }
        let range = paragraphRange(around: tv.selectedRange)
        guard range.location < tv.textStorage.length else { return false }
        let bg = tv.textStorage.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? UIColor
        return bg != nil && !bg!.isEqual(UIColor.clear)
    }

    private func paragraphRange(around range: NSRange) -> NSRange {
        guard let tv = textView, let text = tv.text else { return range }
        let ns = text as NSString
        let start = min(max(0, range.location), max(0, ns.length - 1))
        var paraStart = start
        var paraEnd = start
        var contentStart = 0
        ns.getParagraphStart(&paraStart, end: &paraEnd, contentsEnd: &contentStart,
                             for: NSRange(location: start, length: 0))
        let end = min(ns.length, paraEnd + (paraEnd < ns.length && ns.character(at: paraEnd) == 0x0A ? 1 : 0))
        return NSRange(location: paraStart, length: end - paraStart)
    }

    func activeStyles() -> (bold: Bool, italic: Bool, strike: Bool, underline: Bool) {
        guard let tv = textView else { return (false, false, false, false) }
        let range = paragraphRange(around: tv.selectedRange)
        let location = range.location
        guard location < tv.textStorage.length else { return (false, false, false, false) }
        let font = tv.textStorage.attribute(.font, at: location, effectiveRange: nil) as? UIFont
        let strike = (tv.textStorage.attribute(.strikethroughStyle, at: location, effectiveRange: nil) as? Int ?? 0) != 0
        let underline = (tv.textStorage.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int ?? 0) != 0
        return (font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false,
                strike,
                underline)
    }

    func insertImage(_ image: UIImage, src: String) {
        guard let tv = textView else { return }
        let viewWidth = tv.bounds.width > 0 ? tv.bounds.width - 24 : 343
        let maxW = min(viewWidth, 343)
        let ratio = image.size.height / max(1, image.size.width)
        let displayH = max(40, maxW * ratio)
        let attachment = PayloadAttachment(payload: AttachmentPayload(src: src, w: maxW, h: displayH))
        attachment.image = DiaryImageStore.rounded(image, size: CGSize(width: maxW, height: displayH), radius: 20)
        attachment.bounds = CGRect(x: 0, y: 0, width: maxW, height: displayH)
        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.append(NSAttributedString(string: "\n", attributes: baseTypingAttributes()))
        let insertRange = NSRange(location: tv.selectedRange.location, length: 0)
        tv.textStorage.insert(attributed, at: insertRange.location)
        tv.selectedRange = NSRange(location: insertRange.location + attributed.length, length: 0)
        onFormatChange?()
    }

    func currentParts() -> [ContentPart] {
        guard let tv = textView else { return [] }
        return PartsCodec.parts(from: tv.textStorage)
    }

    func load(parts: [ContentPart]) {
        guard let tv = textView else { return }
        tv.textStorage.setAttributedString(PartsCodec.attributedString(from: parts, imageMaxWidth: imageMaxWidth))
        tv.typingAttributes = baseTypingAttributes()
        tv.selectedRange = NSRange(location: 0, length: 0)
        onFormatChange?()
    }

    func clear() {
        guard let tv = textView else { return }
        tv.textStorage.setAttributedString(NSAttributedString())
        tv.typingAttributes = baseTypingAttributes()
        onFormatChange?()
    }

    func isEmpty() -> Bool {
        guard let tv = textView else { return true }
        return tv.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func apply(_ block: (NSMutableAttributedString) -> Void) {
        guard let tv = textView else { return }
        let text = tv.textStorage
        let attributed = NSMutableAttributedString(attributedString: text)
        block(attributed)
        text.replaceCharacters(in: NSRange(location: 0, length: text.length), with: attributed)
        onFormatChange?()
    }
}

struct AttachmentPayload {
    var src: String
    var w: CGFloat
    var h: CGFloat
    var kind: String
    var done: Bool

    init(src: String = "", w: CGFloat = 0, h: CGFloat = 0, kind: String = "image", done: Bool = false) {
        self.src = src
        self.w = w
        self.h = h
        self.kind = kind
        self.done = done
    }
}

final class PayloadAttachment: NSTextAttachment {
    var payload: AttachmentPayload

    init(payload: AttachmentPayload) {
        self.payload = payload
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum MarkerAttachment {
    static func attachment(kind: String, done: Bool = false) -> PayloadAttachment {
        let attachment = PayloadAttachment(payload: AttachmentPayload(kind: kind, done: done))
        let symbol: String
        switch kind {
        case "todo":
            symbol = done ? "checkmark.square.fill" : "square"
        default:
            symbol = "circle.fill"
        }
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(done ? Theme.primaryUIColor() : Theme.onSurfaceVariantUIColor(),
                           renderingMode: .alwaysTemplate)
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: 15, height: 15)
        return attachment
    }
}

enum PartsCodec {
    static func attributedString(from parts: [ContentPart], imageMaxWidth: CGFloat? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for part in parts {
            switch part.type {
            case ContentPartType.h1:
                appendLine(part, to: result, size: 22)
            case ContentPartType.h2:
                appendLine(part, to: result, size: 18)
            case ContentPartType.quote:
                appendLine(part, to: result, size: 13, background: Theme.quoteBgUIColor())
            case ContentPartType.list:
                for item in part.items ?? [] {
                    appendMarkerLine(kind: "bullet", done: false, text: item, to: result, size: 15)
                }
            case ContentPartType.todo:
                let items = part.items ?? []
                let done = part.done ?? Array(repeating: false, count: items.count)
                for (i, item) in items.enumerated() {
                    appendMarkerLine(kind: "todo", done: done.indices.contains(i) && done[i],
                                     text: item, to: result, size: 15)
                }
            case ContentPartType.image:
                if let src = part.src {
                    let storedW = max(1, CGFloat(part.w ?? 300))
                    let storedH = max(1, CGFloat(part.h ?? 200))
                    let fallbackW = max(60, Screen.width - 76)
                    let maxW = max(60, imageMaxWidth ?? fallbackW)
                    let w = min(storedW, maxW)
                    let h = storedH * w / storedW
                    if let image = DiaryImageStore.shared.image(for: src, maxPixel: max(storedW, storedH) * 3) {
                        let attachment = PayloadAttachment(payload: AttachmentPayload(src: src, w: storedW, h: storedH))
                        attachment.image = DiaryImageStore.rounded(image, size: CGSize(width: w, height: h), radius: 20)
                        attachment.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                        let att = NSMutableAttributedString(attachment: attachment)
                        result.append(att)
                        result.append(NSAttributedString(string: "\n"))
                    }
                }
            default:
                appendLine(part, to: result, size: 15)
            }
        }
        return result
    }

    private static func appendMarkerLine(kind: String, done: Bool, text: String,
                                         to result: NSMutableAttributedString, size: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        var attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size),
            .foregroundColor: Theme.onSurfaceUIColor(),
            .paragraphStyle: style
        ]
        if kind == "todo", done {
            attrs[.strikethroughStyle] = 1
            attrs[.foregroundColor] = Theme.onSurfaceUIColor().withAlphaComponent(0.45)
        }
        result.append(NSAttributedString(attachment: MarkerAttachment.attachment(kind: kind, done: done)))
        result.append(NSAttributedString(string: text, attributes: attrs))
        result.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: size)]))
    }

    private static func appendLine(_ part: ContentPart, to result: NSMutableAttributedString, size: CGFloat,
                                   background: UIColor? = nil) {
        let runs = part.runs ?? []
        if runs.isEmpty, let text = part.text {
            appendLine([TextRun(text: text)], to: result, size: size, background: background,
                       center: part.align == "center")
        } else {
            appendLine(runs, to: result, size: size, background: background, center: part.align == "center")
        }
    }

    private static func appendLine(_ runs: [TextRun], to result: NSMutableAttributedString, size: CGFloat,
                                   background: UIColor? = nil, center: Bool = false) {
        let line = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.alignment = center ? .center : .left
        style.lineSpacing = size == 13 ? 7 : 2
        for run in runs {
            let bold = run.bold == true
            var font = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: Theme.onSurfaceUIColor(),
                .paragraphStyle: style
            ]
            if run.italic == true {
                if let desc = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                    font = UIFont(descriptor: desc, size: size)
                    attrs[.font] = font
                }
            }
            if run.strike == true { attrs[.strikethroughStyle] = 1 }
            if run.underline == true { attrs[.underlineStyle] = 1 }
            if let runSize = run.size, runSize > 0, runSize != size {
                attrs[.font] = UIFont.systemFont(ofSize: runSize, weight: bold ? .bold : .regular)
            }
            if let bg = background { attrs[.backgroundColor] = bg }
            line.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        result.append(line)
        result.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: size)]))
    }

    static func parts(from storage: NSAttributedString) -> [ContentPart] {
        var parts: [ContentPart] = []
        let text = storage.string as NSString
        var lineStart = 0
        while lineStart < text.length {
            var lineEnd = lineStart
            while lineEnd < text.length && text.character(at: lineEnd) != 0x0A {
                lineEnd += 1
            }
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            let lineText = text.substring(with: lineRange)
            lineStart = lineEnd + 1
            if lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            if lineText.hasPrefix("• ") {
                appendList(parts: &parts, item: String(lineText.dropFirst(2)), done: nil)
                continue
            }
            if lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ") {
                appendList(parts: &parts, item: String(lineText.dropFirst(2)), done: lineText.hasPrefix("☑ "))
                continue
            }

            let lineLength = lineRange.length
            guard lineLength > 0 else { continue }
            let lineStartPayload = storage.attribute(.attachment, at: lineRange.location, effectiveRange: nil) as? PayloadAttachment
            if let markerPayload = lineStartPayload?.payload, markerPayload.kind == "todo" || markerPayload.kind == "bullet" {
                let rest = text.substring(with: NSRange(location: lineRange.location + 1, length: lineLength - 1))
                if markerPayload.kind == "todo" {
                    appendList(parts: &parts, item: rest, done: markerPayload.done)
                } else {
                    appendList(parts: &parts, item: rest, done: nil)
                }
                continue
            }
            var isQuote = false
            if let bg = storage.attribute(.backgroundColor, at: lineRange.location, effectiveRange: nil) as? UIColor,
               !bg.isEqual(UIColor.clear) {
                isQuote = true
            }
            var align: String?
            if let style = storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle {
                if style.alignment == .center { align = "center" }
            }
            var runs: [TextRun] = []
            var cursor = lineRange.location
            while cursor < lineRange.location + lineLength {
                var effective = NSRange()
                let attrs = storage.attributes(at: cursor, effectiveRange: &effective)
                let effectiveEnd = min(lineRange.location + lineLength, effective.location + effective.length)
                let sub = text.substring(with: NSRange(location: cursor, length: effectiveEnd - cursor))
                if let payload = (attrs[.attachment] as? PayloadAttachment)?.payload, payload.kind == "image" {
                    parts.append(ContentPart(type: ContentPartType.image,
                                             src: ImagePathUtil.normalizeSrcKey(payload.src),
                                             w: Double(payload.w), h: Double(payload.h)))
                    cursor = effectiveEnd
                    continue
                }
                guard !sub.isEmpty else {
                    cursor = effectiveEnd
                    continue
                }
                let font = attrs[.font] as? UIFont
                let strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
                let underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
                runs.append(TextRun(text: sub,
                                    bold: font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true,
                                    italic: font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true,
                                    strike: strike,
                                    underline: underline,
                                    size: font.map { Double($0.pointSize) }))
                cursor = effectiveEnd
            }
            if runs.isEmpty { continue }
            if let first = runs.first {
                let size = first.size ?? 15
                let type: String
                if isQuote {
                    type = ContentPartType.quote
                } else if size >= 22 {
                    type = ContentPartType.h1
                } else if size >= 18 {
                    type = ContentPartType.h2
                } else {
                    type = ContentPartType.paragraph
                }
                parts.append(ContentPart(type: type, runs: runs, align: align))
            }
        }
        return parts
    }

    private static func appendList(parts: inout [ContentPart], item: String, done: Bool?) {
        if let last = parts.last, last.type == ContentPartType.todo, done != nil {
            var items = last.items ?? []
            items.append(item)
            var newDone = last.done ?? []
            newDone.append(done!)
            parts[parts.count - 1] = ContentPart(type: last.type, items: items, done: newDone)
        } else if let last = parts.last, last.type == ContentPartType.list, done == nil {
            var items = last.items ?? []
            items.append(item)
            parts[parts.count - 1] = ContentPart(type: last.type, items: items)
        } else {
            let type = done == nil ? ContentPartType.list : ContentPartType.todo
            parts.append(ContentPart(type: type, items: [item], done: done.map { [$0] }))
        }
    }
}
