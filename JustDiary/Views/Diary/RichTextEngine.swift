import SwiftUI
import UIKit
import Observation

// MARK: - Editor design sizes
//
// The editor's text storage is the thing `parts(from:)` reads back to decide
// whether a line is an h1, an h2 or a paragraph, and `TextRun.size` is
// persisted in the diary JSON. The storage must therefore keep the *design*
// size, never the size that was actually drawn: once Dynamic Type is honoured,
// a 15pt paragraph can be drawn at 26pt, and reading that back would classify
// every paragraph as a heading and rewrite the saved entry.
//
// So a run carries two things: a `.font` at the resolved display size, and
// `.diaryDesignSize`, the unscaled size that font was derived from.
enum EditorDesignSize {
    static let h1: CGFloat = 22
    static let h2: CGFloat = 18
    static let body: CGFloat = 15
    static let quote: CGFloat = 13

    /// Every size the editor authors, for exact recovery of a design size from
    /// a drawn one. See `EditorFont.designSize(of:typeSize:)`.
    static let authored: [CGFloat] = [h1, h2, body, quote]
}

extension NSAttributedString.Key {
    /// The unscaled design size a run's `.font` was derived from. Internal to
    /// the editor; never persisted (the design size is persisted separately as
    /// `TextRun.size`).
    static let diaryDesignSize = NSAttributedString.Key("com.cov.justdiary.designSize")
}

enum EditorFont {
    /// Font actually drawn for a design size, in the user's text-size category.
    static func font(_ designSize: CGFloat, weight: UIFont.Weight = .regular,
                     italic: Bool = false, typeSize: DynamicTypeSize) -> UIFont {
        var f = DynamicTypeMetrics.font(designSize, weight: weight, typeSize: typeSize)
        if italic, let d = f.fontDescriptor.withSymbolicTraits(.traitItalic) {
            // CJK glyphs (PingFang etc.) have no true italic outline, so merely
            // toggling `.traitItalic` leaves Chinese text looking barely
            // slanted. A mild oblique matrix makes it obvious while keeping
            // other traits (bold) intact.
            let skewed = d.addingAttributes([.matrix: NSValue(cgAffineTransform:
                CGAffineTransform(a: 1, b: 0, c: 0.24, d: 1, tx: 0, ty: 0))])
            f = UIFont(descriptor: skewed, size: f.pointSize)
        }
        return f
    }

    /// Attributes for a run at `designSize`.
    static func attributes(_ designSize: CGFloat, weight: UIFont.Weight = .regular,
                           italic: Bool = false,
                           typeSize: DynamicTypeSize) -> [NSAttributedString.Key: Any] {
        [
            .font: font(designSize, weight: weight, italic: italic, typeSize: typeSize),
            .diaryDesignSize: NSNumber(value: Double(designSize))
        ]
    }

    /// Design size of a run.
    ///
    /// `.diaryDesignSize` is the authoritative source. It is missing for text
    /// UIKit re-attributed behind our back — `typingAttributes` is re-synced
    /// from the text at the caret for a fixed set of keys, so every character
    /// typed after the first one loses the custom key — and that fallback has to
    /// be *exact*: an approximation drifts the persisted `TextRun.size` upward
    /// on every save until a paragraph crosses the h2 threshold and the entry is
    /// rewritten as a heading.
    ///
    /// Sizes this editor itself draws are therefore matched exactly against the
    /// forward mapping before falling back to division, which is only needed for
    /// per-run sizes in imported documents.
    static func designSize(of attributes: [NSAttributedString.Key: Any],
                           typeSize: DynamicTypeSize = .large) -> CGFloat? {
        if let n = attributes[.diaryDesignSize] as? NSNumber { return CGFloat(truncating: n) }
        guard let point = (attributes[.font] as? UIFont)?.pointSize else { return nil }
        guard typeSize != .large else { return point }
        for design in EditorDesignSize.authored
        where abs(DynamicTypeMetrics.scaled(design, for: typeSize) - point) < 0.01 {
            return design
        }
        return point / DynamicTypeMetrics.multiplier(for: point, typeSize: typeSize)
    }
}

@Observable
final class RichEditorController {
    weak var textView: UITextView?
    var onFormatChange: (() -> Void)?
    var imageMaxWidth: CGFloat?
    private(set) var formatTick = 0

    /// The user's text-size category, pushed in by `RichTextView`. The editor
    /// cannot read the SwiftUI environment itself, but it must build fonts with
    /// the same metrics the rest of the UI uses.
    var dynamicTypeSize: DynamicTypeSize = .large

    func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        var attrs = EditorFont.attributes(EditorDesignSize.body, typeSize: dynamicTypeSize)
        attrs[.foregroundColor] = Theme.onSurfaceUIColor()
        attrs[.paragraphStyle] = NSMutableParagraphStyle()
        return attrs
    }

    func refreshTypingAttributes() {
        textView?.typingAttributes = baseTypingAttributes()
        notifyFormatChange()
    }

    /// Bumps the observable tick so SwiftUI toolbar buttons re-evaluate their
    /// active state after any format mutation or cursor move.
    func notifyFormatChange() {
        formatTick += 1
        onFormatChange?()
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
        if range.length > 0 {
            apply { attributed in
                attributed.enumerateAttribute(.font, in: range) { value, subRange, _ in
                    guard let font = value as? UIFont else { return }
                    var sym = font.fontDescriptor.symbolicTraits
                    if sym.contains(trait) {
                        sym.remove(trait)
                    } else {
                        sym.insert(trait)
                    }
                    guard let base = font.fontDescriptor.withSymbolicTraits(sym) else { return }
                    let desc = Self.applyItalicSlant(base, trait: trait, adding: !font.fontDescriptor.symbolicTraits.contains(trait))
                    attributed.removeAttribute(.font, range: subRange)
                    attributed.addAttribute(.font, value: UIFont(descriptor: desc, size: font.pointSize), range: subRange)
                }
            }
        } else {
            let font = (tv.typingAttributes[.font] as? UIFont)
                ?? EditorFont.font(EditorDesignSize.body, typeSize: dynamicTypeSize)
            var sym = font.fontDescriptor.symbolicTraits
            if sym.contains(trait) {
                sym.remove(trait)
            } else {
                sym.insert(trait)
            }
            if let base = font.fontDescriptor.withSymbolicTraits(sym) {
                let desc = Self.applyItalicSlant(base, trait: trait, adding: !font.fontDescriptor.symbolicTraits.contains(trait))
                tv.typingAttributes[.font] = UIFont(descriptor: desc, size: font.pointSize)
            }
            notifyFormatChange()
        }
    }

    /// CJK glyphs (PingFang etc.) have no true italic outline, so merely toggling
    /// `.traitItalic` leaves Chinese text looking barely slanted. Applying a mild
    /// oblique transform to the descriptor matrix makes the italic obvious while
    /// keeping other traits (bold) intact.
    private static func applyItalicSlant(_ descriptor: UIFontDescriptor, trait: UIFontDescriptor.SymbolicTraits,
                                         adding: Bool) -> UIFontDescriptor {
        guard trait == .traitItalic else { return descriptor }
        if adding {
            let skew = CGAffineTransform(a: 1, b: 0, c: 0.24, d: 1, tx: 0, ty: 0)
            return descriptor.addingAttributes([.matrix: NSValue(cgAffineTransform: skew)])
        } else {
            return descriptor.addingAttributes([.matrix: NSValue(cgAffineTransform: .identity)])
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
        if range.length > 0 {
            apply { attributed in
                attributed.enumerateAttribute(key, in: range) { value, subRange, _ in
                    let active = (value as? Int ?? 0) != 0
                    attributed.removeAttribute(key, range: subRange)
                    attributed.addAttribute(key, value: active ? 0 : 1, range: subRange)
                }
            }
        } else {
            let active = (tv.typingAttributes[key] as? Int ?? 0) != 0
            tv.typingAttributes[key] = active ? 0 : 1
            notifyFormatChange()
        }
    }

    // MARK: - Block styles (heading / list / quote / todo are mutually exclusive)

    /// Block styles are mutually exclusive. Turning one on first cancels the
    /// others on the paragraph: list/todo markers are removed, quote background
    /// is cleared and font sizes are reset. Center alignment is only cancelled
    /// when the new block style is list/quote/todo (heading may coexist with it).
    private func normalizeBlockStyle(_ attributed: NSMutableAttributedString,
                                     lineStart: Int,
                                     cancelCenter: Bool) {
        let loc = lineStart
        if loc < attributed.length,
           let payload = (attributed.attribute(.attachment, at: loc, effectiveRange: nil) as? PayloadAttachment)?.payload,
           payload.kind == "bullet" || payload.kind == "todo" {
            attributed.replaceCharacters(in: NSRange(location: loc, length: 1), with: "")
        }
        let para = paragraphRange(in: attributed, around: loc)
        attributed.enumerateAttribute(.font, in: para) { value, r, _ in
            guard let font = value as? UIFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            let weight: UIFont.Weight = traits.contains(.traitBold) ? .bold : .regular
            let italic = traits.contains(.traitItalic)
            let attrs = EditorFont.attributes(EditorDesignSize.body, weight: weight, italic: italic,
                                              typeSize: dynamicTypeSize)
            attributed.removeAttribute(.font, range: r)
            attributed.removeAttribute(.diaryDesignSize, range: r)
            for (key, value) in attrs {
                attributed.addAttribute(key, value: value, range: r)
            }
        }
        attributed.enumerateAttribute(.backgroundColor, in: para) { value, r, _ in
            attributed.removeAttribute(.backgroundColor, range: r)
        }
        attributed.enumerateAttribute(.paragraphStyle, in: para) { value, r, _ in
            let style = ((value as? NSParagraphStyle) ?? NSParagraphStyle()).mutableCopy() as! NSMutableParagraphStyle
            if cancelCenter {
                style.alignment = .left
            }
            style.lineSpacing = 2
            attributed.addAttribute(.paragraphStyle, value: style, range: r)
        }
    }

    func applyHeading(_ level: Int) {
        guard let tv = textView else { return }
        let size: CGFloat = level == 1 ? EditorDesignSize.h1 : (level == 2 ? EditorDesignSize.h2 : EditorDesignSize.body)
        let range = tv.selectedRange

        if range.length > 0 {
            // A real selection: apply the heading to the selected runs and drop
            // quote/list/todo styling from them (mutual exclusion). Center is
            // preserved: heading and center may coexist.
            apply { attributed in
                if level > 0 {
                    let para = paragraphRange(in: attributed, around: range.location)
                    if para.length > 0,
                       let payload = (attributed.attribute(.attachment, at: para.location, effectiveRange: nil) as? PayloadAttachment)?.payload,
                       payload.kind == "bullet" || payload.kind == "todo" {
                        attributed.replaceCharacters(in: NSRange(location: para.location, length: 1), with: "")
                    }
                    attributed.enumerateAttribute(.backgroundColor, in: range) { value, r, _ in
                        if let bg = value as? UIColor, !bg.isEqual(UIColor.clear) {
                            attributed.removeAttribute(.backgroundColor, range: r)
                        }
                    }
                }
                attributed.enumerateAttribute(.font, in: range) { value, subRange, _ in
                    guard let font = value as? UIFont else { return }
                    let traits = font.fontDescriptor.symbolicTraits
                    let weight: UIFont.Weight = traits.contains(.traitBold) ? .bold : .regular
                    let attrs = EditorFont.attributes(size, weight: weight,
                                                      italic: traits.contains(.traitItalic),
                                                      typeSize: dynamicTypeSize)
                    attributed.removeAttribute(.font, range: subRange)
                    attributed.removeAttribute(.diaryDesignSize, range: subRange)
                    for (key, value) in attrs {
                        attributed.addAttribute(key, value: value, range: subRange)
                    }
                }
                if level > 0 {
                    attributed.enumerateAttribute(.paragraphStyle, in: range) { value, r, _ in
                        let style = ((value as? NSParagraphStyle) ?? NSParagraphStyle()).mutableCopy() as! NSMutableParagraphStyle
                        style.lineSpacing = 2
                        attributed.addAttribute(.paragraphStyle, value: style, range: r)
                    }
                }
            }
        } else {
            // Empty caret: heading (like bold/strike/underline/italic) only
            // affects content typed afterwards; other block styles on the line
            // are cancelled first (mutual exclusion).
            if level > 0 {
                let start = paragraphRange(around: tv.selectedRange).location
                apply { attributed in
                    normalizeBlockStyle(attributed, lineStart: start, cancelCenter: false)
                }
            } else {
                notifyFormatChange()
            }
            tv.typingAttributes[.font] = EditorFont.font(size, typeSize: dynamicTypeSize)
            tv.typingAttributes[.diaryDesignSize] = NSNumber(value: Double(size))
        }
    }

    /// Heading state is decided on the *design* size, not the drawn size: once
    /// Dynamic Type is honoured a paragraph and an h2 can be drawn at the same
    /// point size, so comparing what is on screen would mis-report headings.
    private func designSize(at location: Int) -> CGFloat {
        guard let tv = textView else { return EditorDesignSize.body }
        if tv.textStorage.length > 0, location < tv.textStorage.length,
           let value = EditorFont.designSize(of: tv.textStorage.attributes(at: location, effectiveRange: nil)) {
            return value
        }
        return EditorFont.designSize(of: tv.typingAttributes) ?? EditorDesignSize.body
    }

    func currentHeadingLevel() -> Int {
        guard let tv = textView else { return 0 }
        // Empty caret: what gets typed next governs the toggle state (UIKit keeps
        // typingAttributes in sync with the attributes at the insertion point).
        let size: CGFloat
        if tv.selectedRange.length == 0 {
            size = EditorFont.designSize(of: tv.typingAttributes, typeSize: dynamicTypeSize) ?? EditorDesignSize.body
        } else {
            let location = min(tv.selectedRange.location, max(0, tv.textStorage.length - 1))
            guard tv.textStorage.length > 0, location < tv.textStorage.length else { return 0 }
            size = designSize(at: location)
        }
        if size >= EditorDesignSize.h1 { return 1 }
        if size >= EditorDesignSize.h2 { return 2 }
        return 0
    }

    func toggleCenter() {
        guard let tv = textView else { return }
        // Center cannot coexist with list/quote/todo; the toolbar disables the
        // button while one of them is active, guard here too.
        if isListActive() || isQuoteActive() || isTodoActive() { return }
        let location = tv.selectedRange.location
        let center = isCenterActive()

        // On an empty line there is no typed text on THIS line to restyle; only
        // affect subsequent typing. Otherwise paragraphRange would (via the old
        // getParagraphStart) pull in the preceding line's range and reset it too.
        if Self.paragraphIsEmpty(in: tv.textStorage, location: location) {
            if let style = tv.typingAttributes[.paragraphStyle] as? NSMutableParagraphStyle {
                style.alignment = center ? .left : .center
            } else if let style = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle {
                let mutable = style.mutableCopy() as! NSMutableParagraphStyle
                mutable.alignment = center ? .left : .center
                tv.typingAttributes[.paragraphStyle] = mutable
            } else {
                let style = NSMutableParagraphStyle()
                style.alignment = center ? .left : .center
                tv.typingAttributes[.paragraphStyle] = style
            }
            notifyFormatChange()
            return
        }

        apply { attributed in
            let para = paragraphRange(in: attributed, around: location)
            if para.length > 0 {
                let existing = (attributed.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle()
                let style = existing.mutableCopy() as! NSMutableParagraphStyle
                style.alignment = center ? .left : .center
                attributed.addAttribute(.paragraphStyle, value: style, range: para)
            }
        }
        if let style = tv.typingAttributes[.paragraphStyle] as? NSMutableParagraphStyle {
            style.alignment = center ? .left : .center
        } else if let style = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle {
            let mutable = style.mutableCopy() as! NSMutableParagraphStyle
            mutable.alignment = center ? .left : .center
            tv.typingAttributes[.paragraphStyle] = mutable
        } else {
            let style = NSMutableParagraphStyle()
            style.alignment = center ? .left : .center
            tv.typingAttributes[.paragraphStyle] = style
        }
    }

    func isCenterActive() -> Bool {
        guard let tv = textView, tv.textStorage.length > 0 else {
            return (textView?.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .center
        }
        let location = tv.selectedRange.location
        // On an empty current line, report the *typing* state for this line, not
        // the paragraphStyle that leaks from the preceding line's newline run.
        if Self.paragraphIsEmpty(in: tv.textStorage, location: location) {
            return (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .center
        }
        let range = paragraphRange(around: tv.selectedRange)
        guard range.location < tv.textStorage.length else { return false }
        if let style = tv.textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
           style.alignment == .center {
            return true
        }
        return false
    }

    /// Called before inserting a newline. While a paragraph is centered we do not
    /// allow consecutive blank lines: pressing return on an empty, centered line
    /// is ignored until the user actually types something on it.
    func shouldBlockNewline(at location: Int) -> Bool {
        guard let tv = textView else { return true }
        guard Self.paragraphIsEmpty(in: tv.textStorage, location: location) else { return false }
        return isCenterActive()
    }

    func toggleList() {
        toggleMarker(kind: "bullet")
    }

    func toggleTodo() {
        toggleMarker(kind: "todo")
    }

    private func toggleMarker(kind: String) {
        guard let tv = textView else { return }
        let location = tv.selectedRange.location
        // Determine the current line start. For an empty line there is no typed
        // text to scan, so we anchor on the caret; use it directly instead of
        // relying on the (unreliable) tokenizer for a fresh empty paragraph.
        let lineRange = paragraphRange(in: tv.textStorage, around: location)

        let payload: AttachmentPayload? = lineRange.length > 0 && lineRange.location < tv.textStorage.length
            ? (tv.textStorage.attribute(.attachment, at: lineRange.location, effectiveRange: nil) as? PayloadAttachment)?.payload
            : nil
        let isMarked = payload?.kind == kind

        // Insertion target: at the start of the (possibly empty) current line.
        let insertLocation = lineRange.location

        apply { attributed in
            if !isMarked {
                // Turning on: cancel heading / quote / other marker / center first.
                normalizeBlockStyle(attributed, lineStart: insertLocation, cancelCenter: true)
            }
            if isMarked {
                // Only strip a marker we can actually confirm exists at the line start.
                if insertLocation < attributed.length,
                   let p = (attributed.attribute(.attachment, at: insertLocation, effectiveRange: nil) as? PayloadAttachment)?.payload,
                   p.kind == kind {
                    attributed.replaceCharacters(in: NSRange(location: insertLocation, length: 1), with: "")
                }
            } else {
                let attachment = MarkerAttachment.attachment(kind: kind, typeSize: dynamicTypeSize)
                attributed.insert(NSAttributedString(attachment: attachment), at: insertLocation)
            }
        }

        // Reset typing attributes to a plain block line.
        tv.typingAttributes[.font] = EditorFont.font(EditorDesignSize.body, typeSize: dynamicTypeSize)
        tv.typingAttributes[.diaryDesignSize] = NSNumber(value: Double(EditorDesignSize.body))
        tv.typingAttributes[.backgroundColor] = UIColor.clear
        if let style = tv.typingAttributes[.paragraphStyle] as? NSMutableParagraphStyle {
            style.alignment = .left
            style.lineSpacing = 2
        } else if let style = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle {
            let mutable = style.mutableCopy() as! NSMutableParagraphStyle
            mutable.alignment = .left
            mutable.lineSpacing = 2
            tv.typingAttributes[.paragraphStyle] = mutable
        } else {
            let style = NSMutableParagraphStyle()
            style.alignment = .left
            style.lineSpacing = 2
            tv.typingAttributes[.paragraphStyle] = style
        }
    }

    func isListActive() -> Bool { currentMarkerKind() == "bullet" }

    func isTodoActive() -> Bool { currentMarkerKind() == "todo" }

    private func currentMarkerKind() -> String? {
        guard let tv = textView, tv.textStorage.length > 0 else { return nil }
        let range = paragraphRange(around: tv.selectedRange)
        guard range.location < tv.textStorage.length else { return nil }
        return (tv.textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) as? PayloadAttachment)?.payload.kind
    }

    func toggleQuote() {
        guard let tv = textView else { return }
        let range = paragraphRange(around: tv.selectedRange)
        let isQuote = isQuoteActive()

        apply { attributed in
            let para = paragraphRange(in: attributed, around: range.location)
            if !isQuote {
                // Turning on: cancel heading / list / todo / center first.
                normalizeBlockStyle(attributed, lineStart: para.location, cancelCenter: true)
            }
            let para2 = paragraphRange(in: attributed, around: para.location)
            let bg: UIColor = isQuote ? .clear : Theme.quoteBgUIColor()
            attributed.enumerateAttribute(.paragraphStyle, in: para2) { value, r, _ in
                let style = ((value as? NSParagraphStyle) ?? NSParagraphStyle()).mutableCopy() as! NSMutableParagraphStyle
                style.lineSpacing = isQuote ? 0 : 7
                attributed.addAttribute(.paragraphStyle, value: style, range: r)
            }
            attributed.enumerateAttribute(.font, in: para2) { value, r, _ in
                guard let font = value as? UIFont else { return }
                let traits = font.fontDescriptor.symbolicTraits
                let weight: UIFont.Weight = traits.contains(.traitBold) ? .bold : .regular
                let design = isQuote ? EditorDesignSize.body : EditorDesignSize.quote
                let attrs = EditorFont.attributes(design, weight: weight,
                                                  italic: traits.contains(.traitItalic),
                                                  typeSize: dynamicTypeSize)
                attributed.removeAttribute(.font, range: r)
                attributed.removeAttribute(.diaryDesignSize, range: r)
                for (key, value) in attrs {
                    attributed.addAttribute(key, value: value, range: r)
                }
            }
            attributed.addAttribute(.backgroundColor, value: bg, range: para2)
        }

        if let style = tv.typingAttributes[.paragraphStyle] as? NSMutableParagraphStyle {
            style.lineSpacing = isQuote ? 0 : 7
            style.alignment = .left
        } else if let style = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle {
            let mutable = style.mutableCopy() as! NSMutableParagraphStyle
            mutable.lineSpacing = isQuote ? 0 : 7
            mutable.alignment = .left
            tv.typingAttributes[.paragraphStyle] = mutable
        } else {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = isQuote ? 0 : 7
            style.alignment = .left
            tv.typingAttributes[.paragraphStyle] = style
        }
        tv.typingAttributes[.backgroundColor] = isQuote ? UIColor.clear : Theme.quoteBgUIColor()
        let quoted = isQuote ? EditorDesignSize.body : EditorDesignSize.quote
        tv.typingAttributes[.font] = EditorFont.font(quoted, typeSize: dynamicTypeSize)
        tv.typingAttributes[.diaryDesignSize] = NSNumber(value: Double(quoted))
    }

    func isQuoteActive() -> Bool {
        guard let tv = textView, tv.textStorage.length > 0 else {
            let bg = textView?.typingAttributes[.backgroundColor] as? UIColor
            return bg != nil && !bg!.isEqual(UIColor.clear)
        }
        let location = tv.selectedRange.location
        if Self.paragraphIsEmpty(in: tv.textStorage, location: location) {
            let tbg = tv.typingAttributes[.backgroundColor] as? UIColor
            return tbg != nil && !tbg!.isEqual(UIColor.clear)
        }
        let range = paragraphRange(around: tv.selectedRange)
        guard range.location < tv.textStorage.length else { return false }
        let bg = tv.textStorage.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? UIColor
        return bg != nil && !bg!.isEqual(UIColor.clear)
    }

    private func paragraphRange(around range: NSRange) -> NSRange {
        guard let tv = textView else { return range }
        return paragraphRange(in: tv.textStorage, around: range.location)
    }

    /// Whether the paragraph containing (or immediately before) `location` holds
    /// no visible text. Used to decide if a block/toggle applies to the *current*
    /// empty line rather than to the preceding, already-typed line.
    private static func paragraphIsEmpty(in storage: NSAttributedString, location: Int) -> Bool {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return true }
        let clamped = min(max(0, location), ns.length)
        // Caret at the very end, right after a trailing newline → empty last line.
        if clamped >= ns.length, ns.character(at: ns.length - 1) == 0x0A { return true }
        let searchPos = min(clamped, ns.length - 1)
        var paraStart = searchPos, paraEnd = searchPos, contentStart = 0
        ns.getParagraphStart(&paraStart, end: &paraEnd, contentsEnd: &contentStart,
                             for: NSRange(location: searchPos, length: 0))
        return (contentStart - paraStart) == 0
    }

    private func paragraphRange(in storage: NSAttributedString, around location: Int) -> NSRange {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let clamped = min(max(0, location), ns.length)
        // Caret at the very end, right after a trailing newline → the current
        // line is the empty trailing paragraph; return a zero-width range there
        // so toggles do not pull in (and reset) the preceding line.
        if clamped >= ns.length, ns.character(at: ns.length - 1) == 0x0A {
            return NSRange(location: ns.length, length: 0)
        }
        let searchPos = min(clamped, ns.length - 1)
        var paraStart = searchPos
        var paraEnd = searchPos
        var contentStart = 0
        ns.getParagraphStart(&paraStart, end: &paraEnd, contentsEnd: &contentStart,
                             for: NSRange(location: searchPos, length: 0))
        let contentLen = contentStart - paraStart
        // Empty current line → zero-width range so we only affect subsequent
        // typing, never the adjacent (previous or next) line's content.
        if contentLen == 0 {
            return NSRange(location: paraStart, length: 0)
        }
        // paraEnd already sits just past the paragraph's terminating newline
        // (or at the end of text when there is none), so it is the correct
        // exclusive end. In particular we must NOT add another index when a
        // subsequent newline exists — that would bleed into an adjacent empty
        // line's newline and restyle it.
        let end = min(ns.length, paraEnd)
        return NSRange(location: paraStart, length: end - paraStart)
    }

    func activeStyles() -> (bold: Bool, italic: Bool, strike: Bool, underline: Bool) {
        guard let tv = textView else { return (false, false, false, false) }
        if tv.selectedRange.length > 0 {
            let location = min(tv.selectedRange.location, max(0, tv.textStorage.length - 1))
            guard tv.textStorage.length > 0, location < tv.textStorage.length else { return (false, false, false, false) }
            let font = tv.textStorage.attribute(.font, at: location, effectiveRange: nil) as? UIFont
            let strike = (tv.textStorage.attribute(.strikethroughStyle, at: location, effectiveRange: nil) as? Int ?? 0) != 0
            let underline = (tv.textStorage.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int ?? 0) != 0
            return (font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                    font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false,
                    strike,
                    underline)
        }
        // Empty caret: report what the next typed characters will look like.
        let typing = tv.typingAttributes
        let font = typing[.font] as? UIFont
        return (font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false,
                (typing[.strikethroughStyle] as? Int ?? 0) != 0,
                (typing[.underlineStyle] as? Int ?? 0) != 0)
    }

    func insertImage(_ image: UIImage, src: String) {
        guard let tv = textView else { return }
        let viewWidth = tv.bounds.width > 0 ? tv.bounds.width - 24 : 343
        let maxW = min(viewWidth, 343)
        let ratio = image.size.height / max(1, image.size.width)
        let displayH = max(40, maxW * ratio)
        let attachment = PayloadAttachment(payload: AttachmentPayload(src: src, w: maxW, h: displayH))
        attachment.image = DiaryImageStore.rounded(image, size: CGSize(width: maxW, height: displayH), radius: Radius.image)
        attachment.bounds = CGRect(x: 0, y: 0, width: maxW, height: displayH)
        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.append(NSAttributedString(string: "\n", attributes: baseTypingAttributes()))
        let insertRange = NSRange(location: tv.selectedRange.location, length: 0)
        tv.textStorage.insert(attributed, at: insertRange.location)
        tv.selectedRange = NSRange(location: insertRange.location + attributed.length, length: 0)
        notifyFormatChange()
    }

    func currentParts() -> [ContentPart] {
        guard let tv = textView else { return [] }
        return PartsCodec.parts(from: tv.textStorage, typeSize: dynamicTypeSize)
    }

    func load(parts: [ContentPart]) {
        guard let tv = textView else { return }
        tv.textStorage.setAttributedString(
            PartsCodec.attributedString(from: parts, imageMaxWidth: imageMaxWidth, typeSize: dynamicTypeSize)
        )
        tv.typingAttributes = baseTypingAttributes()
        tv.selectedRange = NSRange(location: 0, length: 0)
        notifyFormatChange()
    }

    /// Re-renders the current content for a new text-size category, keeping the
    /// caret where it was. Called when 设置 › 文字大小 changes while an entry is
    /// open; the stored design sizes are unaffected, only the drawn fonts.
    func reapplyTypeSize(_ newSize: DynamicTypeSize) {
        guard let tv = textView, newSize != dynamicTypeSize else { return }
        // Parse with the *old* category so the design sizes come back exactly,
        // then rebuild at the new one.
        let parts = PartsCodec.parts(from: tv.textStorage, typeSize: dynamicTypeSize)
        let caret = tv.selectedRange
        dynamicTypeSize = newSize
        tv.textStorage.setAttributedString(
            PartsCodec.attributedString(from: parts, imageMaxWidth: imageMaxWidth, typeSize: newSize)
        )
        tv.typingAttributes = baseTypingAttributes()
        tv.selectedRange = NSRange(location: min(caret.location, tv.textStorage.length), length: 0)
        notifyFormatChange()
    }

    func clear() {
        guard let tv = textView else { return }
        tv.textStorage.setAttributedString(NSAttributedString())
        tv.typingAttributes = baseTypingAttributes()
        notifyFormatChange()
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
        notifyFormatChange()
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
    /// List bullets and todo checkboxes are drawn as text attachments, so they
    /// have to be scaled by hand: a fixed 13pt glyph stayed small next to text
    /// the user had enlarged. The bounds scale with it so the marker keeps its
    /// proportion to the line.
    static func attachment(kind: String, done: Bool = false,
                           typeSize: DynamicTypeSize = .large) -> PayloadAttachment {
        let attachment = PayloadAttachment(payload: AttachmentPayload(kind: kind, done: done))
        let symbol: String
        switch kind {
        case "todo":
            symbol = done ? "checkmark.square.fill" : "square"
        default:
            symbol = "circle.fill"
        }
        let scale = DynamicTypeMetrics.multiplier(for: EditorDesignSize.body, typeSize: typeSize)
        let config = UIImage.SymbolConfiguration(pointSize: 13 * scale, weight: .regular)
        let image = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(done ? Theme.primaryUIColor() : Theme.onSurfaceVariantUIColor(),
                           renderingMode: .alwaysTemplate)
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: 15 * scale, height: 15 * scale)
        return attachment
    }
}

enum PartsCodec {
    static func attributedString(from parts: [ContentPart], imageMaxWidth: CGFloat? = nil,
                                 typeSize: DynamicTypeSize = .large) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for part in parts {
            switch part.type {
            case ContentPartType.h1:
                appendLine(part, to: result, size: EditorDesignSize.h1, typeSize: typeSize)
            case ContentPartType.h2:
                appendLine(part, to: result, size: EditorDesignSize.h2, typeSize: typeSize)
            case ContentPartType.quote:
                appendLine(part, to: result, size: EditorDesignSize.quote,
                           background: Theme.quoteBgUIColor(), typeSize: typeSize)
            case ContentPartType.list:
                for item in part.items ?? [] {
                    appendMarkerLine(kind: "bullet", done: false, text: item, to: result,
                                     size: EditorDesignSize.body, typeSize: typeSize)
                }
            case ContentPartType.todo:
                let items = part.items ?? []
                let done = part.done ?? Array(repeating: false, count: items.count)
                for (i, item) in items.enumerated() {
                    appendMarkerLine(kind: "todo", done: done.indices.contains(i) && done[i],
                                     text: item, to: result, size: EditorDesignSize.body, typeSize: typeSize)
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
                        attachment.image = DiaryImageStore.rounded(image, size: CGSize(width: w, height: h), radius: Radius.image)
                        attachment.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                        let att = NSMutableAttributedString(attachment: attachment)
                        result.append(att)
                        result.append(NSAttributedString(string: "\n"))
                    }
                }
            default:
                appendLine(part, to: result, size: EditorDesignSize.body, typeSize: typeSize)
            }
        }
        return result
    }

    private static func appendMarkerLine(kind: String, done: Bool, text: String,
                                         to result: NSMutableAttributedString, size: CGFloat,
                                         typeSize: DynamicTypeSize) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        var attrs = EditorFont.attributes(size, typeSize: typeSize)
        attrs[.foregroundColor] = Theme.onSurfaceUIColor()
        attrs[.paragraphStyle] = style
        if kind == "todo", done {
            attrs[.strikethroughStyle] = 1
            attrs[.foregroundColor] = Theme.onSurfaceUIColor().withAlphaComponent(0.45)
        }
        result.append(NSAttributedString(attachment: MarkerAttachment.attachment(kind: kind, done: done,
                                                                              typeSize: typeSize)))
        result.append(NSAttributedString(string: text, attributes: attrs))
        result.append(NSAttributedString(string: "\n", attributes: EditorFont.attributes(size, typeSize: typeSize)))
    }

    private static func appendLine(_ part: ContentPart, to result: NSMutableAttributedString, size: CGFloat,
                                   background: UIColor? = nil, typeSize: DynamicTypeSize) {
        let runs = part.runs ?? []
        if runs.isEmpty, let text = part.text {
            appendLine([TextRun(text: text)], to: result, size: size, background: background,
                       center: part.align == "center", typeSize: typeSize)
        } else {
            appendLine(runs, to: result, size: size, background: background,
                       center: part.align == "center", typeSize: typeSize)
        }
    }

    private static func appendLine(_ runs: [TextRun], to result: NSMutableAttributedString, size: CGFloat,
                                   background: UIColor? = nil, center: Bool = false,
                                   typeSize: DynamicTypeSize) {
        let line = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.alignment = center ? .center : .left
        style.lineSpacing = size == EditorDesignSize.quote ? 7 : 2
        for run in runs {
            // An imported run may carry its own design size; it is resolved the
            // same way as the block default so the two cannot drift apart.
            let design = run.size.flatMap { $0 > 0 ? CGFloat($0) : nil } ?? size
            var attrs = EditorFont.attributes(design,
                                              weight: run.bold == true ? .bold : .regular,
                                              italic: run.italic == true,
                                              typeSize: typeSize)
            attrs[.foregroundColor] = Theme.onSurfaceUIColor()
            attrs[.paragraphStyle] = style
            if run.strike == true { attrs[.strikethroughStyle] = 1 }
            if run.underline == true { attrs[.underlineStyle] = 1 }
            if let bg = background { attrs[.backgroundColor] = bg }
            line.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        result.append(line)
        result.append(NSAttributedString(string: "\n", attributes: EditorFont.attributes(size, typeSize: typeSize)))
    }

    static func parts(from storage: NSAttributedString, typeSize: DynamicTypeSize = .large) -> [ContentPart] {
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
                // Persist the *design* size, never the drawn one: the drawn size
                // grows with the user's text-size setting, and writing it back
                // would turn a paragraph into a heading on the next load.
                let design = EditorFont.designSize(of: attrs, typeSize: typeSize)
                runs.append(TextRun(text: sub,
                                    bold: font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true,
                                    italic: font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true,
                                    strike: strike,
                                    underline: underline,
                                    size: design.map { Double(($0 * 1000).rounded() / 1000) }))
                cursor = effectiveEnd
            }
            if runs.isEmpty { continue }
            if let first = runs.first {
                let size = first.size ?? Double(EditorDesignSize.body)
                let type: String
                if isQuote {
                    type = ContentPartType.quote
                } else if size >= Double(EditorDesignSize.h1) {
                    type = ContentPartType.h1
                } else if size >= Double(EditorDesignSize.h2) {
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
