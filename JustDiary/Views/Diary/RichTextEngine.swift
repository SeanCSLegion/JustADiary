import SwiftUI
import UIKit
import Observation

// MARK: - Editor paragraph styles
//
// The editor's paragraph styles are named after the equivalent styles in Apple
// Notes (Title / Heading / Body) and are backed by Apple's own type ladder —
// Title 1 = 28, Title 2 = 22, Body = 17, Subheadline = 15 (HIG › Typography,
// iOS default). Two things follow from doing it this way:
//
// * Sizes are never chosen freely. The stored number is a *design* size that is
//   drawn through `DynamicTypeMetrics`, so entry text follows
//   设置 › 显示与亮度 › 文字大小 exactly like Notes does.
// * A paragraph's type is stored explicitly (`.diaryBlockStyle`, persisted as
//   `ContentPart.type`) instead of being inferred from its point size. The
//   ladder can therefore change without silently rewriting saved entries; size
//   inference survives only as a fallback for imported runs.
enum EditorBlockStyle: String, CaseIterable {
    case title
    case heading
    case body
    case quote

    /// Title 1 / Title 2 / Body / Subheadline of the iOS type ladder.
    var designSize: CGFloat {
        switch self {
        case .title: return 28
        case .heading: return 22
        case .body: return 17
        case .quote: return 15
        }
    }

    /// Extra leading between wrapped lines, as a fraction of the design size so
    /// that it grows with the text. It used to be a flat 2pt (7pt for quotes),
    /// which read as cramped once the user raised the system text size, and it
    /// was keyed off "size == quote" — i.e. off the very thing this change
    /// decouples the block type from.
    var lineSpacing: CGFloat {
        self == .quote ? designSize * 0.5 : designSize * 0.13
    }

    /// Space after the paragraph. Rendered only: like alignment it is derived
    /// from the block type on load rather than persisted.
    var paragraphSpacing: CGFloat {
        switch self {
        case .title: return designSize * 0.4
        case .heading: return designSize * 0.3
        case .quote: return designSize * 0.4
        case .body: return 0
        }
    }

    /// Styles offered by the format bar's paragraph-style menu, in Notes' order
    /// (largest first). Quote is not here: it is a marker as much as a style, so
    /// it keeps its own toolbar button.
    static let menuStyles: [EditorBlockStyle] = [.title, .heading, .body]

    /// The value persisted in `ContentPart.type`.
    var persistedType: String {
        switch self {
        case .title: return ContentPartType.h1
        case .heading: return ContentPartType.h2
        case .body: return ContentPartType.paragraph
        case .quote: return ContentPartType.quote
        }
    }

    init(persistedType: String) {
        switch persistedType {
        case ContentPartType.h1: self = .title
        case ContentPartType.h2: self = .heading
        case ContentPartType.quote: self = .quote
        default: self = .body
        }
    }

    var localizationKey: String {
        switch self {
        case .title: return "editor_font_heading"
        case .heading: return "editor_font_sub"
        case .body: return "editor_font_body"
        case .quote: return "editor_tool_quote"
        }
    }
}

enum EditorDesignSize {
    static let h1 = EditorBlockStyle.title.designSize
    static let h2 = EditorBlockStyle.heading.designSize
    static let body = EditorBlockStyle.body.designSize
    static let quote = EditorBlockStyle.quote.designSize

    /// Every size the editor authors, for exact recovery of a design size from
    /// a drawn one. See `EditorFont.designSize(of:typeSize:)`.
    static let authored: [CGFloat] = EditorBlockStyle.allCases.map(\.designSize)

    /// The style a bare point size maps to. Used only for runs that carry no
    /// `.diaryBlockStyle` — chiefly imported documents, whose runs may be any
    /// size at all. The thresholds sit halfway between the ladder's steps.
    static func blockStyle(for size: CGFloat) -> EditorBlockStyle {
        if size >= (h1 + h2) / 2 { return .title }
        if size >= (h2 + body) / 2 { return .heading }
        return .body
    }
}

extension NSAttributedString.Key {
    /// The unscaled design size a run's `.font` was derived from. Internal to
    /// the editor; never persisted (the design size is persisted separately as
    /// `TextRun.size`, and then only when it is a custom size).
    static let diaryDesignSize = NSAttributedString.Key("com.cov.justdiary.designSize")

    /// The paragraph style a run belongs to. Also editor-internal: the persisted
    /// form is `ContentPart.type`. Carrying it in the text storage is what makes
    /// the block type independent of the font size.
    static let diaryBlockStyle = NSAttributedString.Key("com.cov.justdiary.blockStyle")
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

    /// Attributes for a run at `designSize`, belonging to `block`.
    static func attributes(_ designSize: CGFloat,
                           block: EditorBlockStyle? = nil,
                           weight: UIFont.Weight = .regular,
                           italic: Bool = false,
                           typeSize: DynamicTypeSize) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(designSize, weight: weight, italic: italic, typeSize: typeSize),
            .diaryDesignSize: NSNumber(value: Double(designSize))
        ]
        if let block { attrs[.diaryBlockStyle] = block.rawValue }
        return attrs
    }

    /// The paragraph style a run belongs to, if the editor authored it.
    static func blockStyle(of attributes: [NSAttributedString.Key: Any]) -> EditorBlockStyle? {
        guard let raw = attributes[.diaryBlockStyle] as? String else { return nil }
        return EditorBlockStyle(rawValue: raw)
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

    /// Typing attributes for a paragraph of `block`: what the next typed
    /// character will look like. Also the reset applied after a block toggle.
    func typingAttributes(for block: EditorBlockStyle) -> [NSAttributedString.Key: Any] {
        var attrs = EditorFont.attributes(block.designSize, block: block, typeSize: dynamicTypeSize)
        attrs[.foregroundColor] = Theme.onSurfaceUIColor()
        let style = NSMutableParagraphStyle()
        style.lineSpacing = block.lineSpacing
        style.paragraphSpacing = block.paragraphSpacing
        attrs[.paragraphStyle] = style
        attrs[.backgroundColor] = block == .quote ? Theme.quoteBgUIColor() : UIColor.clear
        return attrs
    }

    func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        typingAttributes(for: .body)
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

    // MARK: - Paragraph styles
    //
    // Title / heading / quote / body are mutually exclusive with list & todo: a
    // list item is a paragraph style of its own, so turning one on removes the
    // other. Center alignment may coexist with a heading/body but not with
    // list/quote/todo.

    /// Applies a paragraph style to every paragraph the caret or selection
    /// touches. Like Notes, a paragraph style belongs to the paragraph rather
    /// than to the selected glyphs, so a partial selection still restyles the
    /// whole line.
    func applyBlockStyle(_ block: EditorBlockStyle) {
        guard let tv = textView else { return }
        let ranges = paragraphRanges(covering: tv.selectedRange)
        if !ranges.isEmpty {
            apply { attributed in
                // Back to front: restyling a paragraph can drop its list/todo
                // marker, which shifts every later range by one.
                for range in ranges.reversed() {
                    self.restyle(attributed, range: range, to: block, cancelCenter: block == .quote)
                }
            }
        } else {
            notifyFormatChange()
        }
        tv.typingAttributes = typingAttributes(for: block)
    }

    /// The paragraph style at the caret, for the format bar's menu state.
    func currentBlockStyle() -> EditorBlockStyle {
        guard let tv = textView else { return .body }
        let location = tv.selectedRange.location
        let attrs: [NSAttributedString.Key: Any]
        if tv.textStorage.length > 0, location < tv.textStorage.length,
           !(tv.selectedRange.length == 0 && Self.paragraphIsEmpty(in: tv.textStorage, location: location)) {
            // Probe the *start* of the paragraph: UIKit drops the custom keys
            // from characters typed after the first one, so the character at the
            // caret may be one that no longer carries them.
            let para = paragraphRange(in: tv.textStorage, around: location)
            let probe = para.location < tv.textStorage.length ? para.location : location
            attrs = tv.textStorage.attributes(at: probe, effectiveRange: nil)
        } else {
            attrs = tv.typingAttributes
        }
        if let explicit = EditorFont.blockStyle(of: attrs) { return explicit }
        if let bg = attrs[.backgroundColor] as? UIColor, !bg.isEqual(UIColor.clear) { return .quote }
        let size = EditorFont.designSize(of: attrs, typeSize: dynamicTypeSize) ?? EditorDesignSize.body
        return EditorDesignSize.blockStyle(for: size)
    }

    /// Restyles one paragraph (newline included), preserving bold/italic traits.
    private func restyle(_ attributed: NSMutableAttributedString, range: NSRange,
                         to block: EditorBlockStyle, cancelCenter: Bool = false) {
        // Drop a list/todo marker: it is a paragraph style of its own, and it
        // would otherwise stay attached to what is now a heading/quote/body.
        if range.location < attributed.length,
           let payload = (attributed.attribute(.attachment, at: range.location, effectiveRange: nil) as? PayloadAttachment)?.payload,
           payload.kind == "bullet" || payload.kind == "todo" {
            attributed.replaceCharacters(in: NSRange(location: range.location, length: 1), with: "")
        }
        let para = paragraphRange(in: attributed, around: range.location)
        guard para.length > 0 else { return }
        attributed.enumerateAttribute(.font, in: para) { value, r, _ in
            guard let font = value as? UIFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            let attrs = EditorFont.attributes(block.designSize, block: block,
                                              weight: traits.contains(.traitBold) ? .bold : .regular,
                                              italic: traits.contains(.traitItalic),
                                              typeSize: dynamicTypeSize)
            attributed.removeAttribute(.font, range: r)
            attributed.removeAttribute(.diaryDesignSize, range: r)
            attributed.removeAttribute(.diaryBlockStyle, range: r)
            for (key, value) in attrs {
                attributed.addAttribute(key, value: value, range: r)
            }
        }
        attributed.removeAttribute(.backgroundColor, range: para)
        if block == .quote {
            attributed.addAttribute(.backgroundColor, value: Theme.quoteBgUIColor(), range: para)
        }
        attributed.enumerateAttribute(.paragraphStyle, in: para) { value, r, _ in
            let style = ((value as? NSParagraphStyle) ?? NSParagraphStyle()).mutableCopy() as! NSMutableParagraphStyle
            if cancelCenter || block == .quote {
                style.alignment = .left
            }
            style.lineSpacing = block.lineSpacing
            style.paragraphSpacing = block.paragraphSpacing
            attributed.addAttribute(.paragraphStyle, value: style, range: r)
        }
    }

    /// Paragraph ranges (terminating newline included) touched by `range`, or
    /// the caret's paragraph when `range` is empty. An empty trailing line has
    /// no paragraph and yields nothing, which is how "only affect what is typed
    /// next" is expressed.
    private func paragraphRanges(covering range: NSRange) -> [NSRange] {
        guard let tv = textView else { return [] }
        let ns = tv.textStorage.string as NSString
        guard ns.length > 0 else { return [] }
        var result: [NSRange] = []
        var start = 0
        while start < ns.length {
            var end = start
            while end < ns.length && ns.character(at: end) != 0x0A {
                end += 1
            }
            let lineEnd = end < ns.length ? end + 1 : end
            let line = NSRange(location: start, length: lineEnd - start)
            let hit: Bool
            if range.length == 0 {
                hit = range.location >= start && range.location <= lineEnd
            } else {
                hit = NSIntersectionRange(range, line).length > 0
            }
            if hit { result.append(line) }
            start = end + 1
        }
        return result
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
                self.restyle(attributed, range: NSRange(location: insertLocation, length: 0),
                             to: .body, cancelCenter: true)
            }
            if isMarked {
                // Only strip a marker we can actually confirm exists at the line start.
                if insertLocation < attributed.length,
                   let p = (attributed.attribute(.attachment, at: insertLocation, effectiveRange: nil) as? PayloadAttachment)?.payload,
                   p.kind == kind {
                    attributed.replaceCharacters(in: NSRange(location: insertLocation, length: 1), with: "")
                }
            } else {
                let attachment = MarkerAttachment.attachment(kind: kind, typeSize: self.dynamicTypeSize)
                attributed.insert(NSAttributedString(attachment: attachment), at: insertLocation)
            }
        }

        // Reset typing attributes to a plain block line.
        tv.typingAttributes = typingAttributes(for: .body)
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
        let block: EditorBlockStyle = isQuoteActive() ? .body : .quote
        let ranges = paragraphRanges(covering: tv.selectedRange)
        if !ranges.isEmpty {
            apply { attributed in
                for range in ranges.reversed() {
                    self.restyle(attributed, range: range, to: block, cancelCenter: true)
                }
            }
        } else {
            notifyFormatChange()
        }
        tv.typingAttributes = typingAttributes(for: block)
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
            case ContentPartType.list:
                for item in part.items ?? [] {
                    appendMarkerLine(kind: "bullet", done: false, text: item, to: result, typeSize: typeSize)
                }
            case ContentPartType.todo:
                let items = part.items ?? []
                let done = part.done ?? Array(repeating: false, count: items.count)
                for (i, item) in items.enumerated() {
                    appendMarkerLine(kind: "todo", done: done.indices.contains(i) && done[i],
                                     text: item, to: result, typeSize: typeSize)
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
                appendLine(part, to: result, block: EditorBlockStyle(persistedType: part.type),
                           typeSize: typeSize)
            }
        }
        return result
    }

    private static func paragraphStyle(_ block: EditorBlockStyle, center: Bool = false) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = center ? .center : .left
        style.lineSpacing = block.lineSpacing
        style.paragraphSpacing = block.paragraphSpacing
        return style
    }

    private static func appendMarkerLine(kind: String, done: Bool, text: String,
                                         to result: NSMutableAttributedString,
                                         typeSize: DynamicTypeSize) {
        let block = EditorBlockStyle.body
        let style = paragraphStyle(block)
        var attrs = EditorFont.attributes(block.designSize, block: block, typeSize: typeSize)
        attrs[.foregroundColor] = Theme.onSurfaceUIColor()
        attrs[.paragraphStyle] = style
        if kind == "todo", done {
            attrs[.strikethroughStyle] = 1
            attrs[.foregroundColor] = Theme.onSurfaceUIColor().withAlphaComponent(0.45)
        }
        result.append(NSAttributedString(attachment: MarkerAttachment.attachment(kind: kind, done: done,
                                                                               typeSize: typeSize)))
        result.append(NSAttributedString(string: text, attributes: attrs))
        result.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    private static func appendLine(_ part: ContentPart, to result: NSMutableAttributedString,
                                   block: EditorBlockStyle, typeSize: DynamicTypeSize) {
        let runs = part.runs ?? []
        let center = part.align == "center"
        if runs.isEmpty, let text = part.text {
            appendLine([TextRun(text: text)], to: result, block: block, center: center, typeSize: typeSize)
        } else {
            appendLine(runs, to: result, block: block, center: center, typeSize: typeSize)
        }
    }

    private static func appendLine(_ runs: [TextRun], to result: NSMutableAttributedString,
                                   block: EditorBlockStyle, center: Bool = false,
                                   typeSize: DynamicTypeSize) {
        let line = NSMutableAttributedString()
        let style = paragraphStyle(block, center: center)
        for run in runs {
            // An imported run may carry its own design size; it is resolved the
            // same way as the block default so the two cannot drift apart.
            let design = run.size.flatMap { $0 > 0 ? CGFloat($0) : nil } ?? block.designSize
            var attrs = EditorFont.attributes(design, block: block,
                                              weight: run.bold == true ? .bold : .regular,
                                              italic: run.italic == true,
                                              typeSize: typeSize)
            attrs[.foregroundColor] = Theme.onSurfaceUIColor()
            attrs[.paragraphStyle] = style
            if run.strike == true { attrs[.strikethroughStyle] = 1 }
            if run.underline == true { attrs[.underlineStyle] = 1 }
            if block == .quote { attrs[.backgroundColor] = Theme.quoteBgUIColor() }
            line.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        result.append(line)
        // The terminating newline carries the block's attributes too, so pressing
        // return at the end of a paragraph keeps writing in the same style (the
        // trailing empty line itself is skipped when the entry is parsed back).
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: EditorFont.font(block.designSize, typeSize: typeSize),
            .diaryDesignSize: NSNumber(value: Double(block.designSize)),
            .diaryBlockStyle: block.rawValue,
            .paragraphStyle: style
        ]))
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

            let lineAttrs = storage.attributes(at: lineRange.location, effectiveRange: nil)
            // The block type is stored explicitly. Size inference is only the
            // fallback for runs that predate the attribute (imported content) or
            // for characters UIKit re-attributed behind our back.
            let block: EditorBlockStyle
            if let explicit = EditorFont.blockStyle(of: lineAttrs) {
                block = explicit
            } else if let bg = lineAttrs[.backgroundColor] as? UIColor, !bg.isEqual(UIColor.clear) {
                block = .quote
            } else {
                let size = EditorFont.designSize(of: lineAttrs, typeSize: typeSize) ?? EditorDesignSize.body
                block = EditorDesignSize.blockStyle(for: size)
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
                // A size is stored only when the run genuinely differs from its
                // block's default. `TextRun.size` is therefore unambiguously a
                // *custom* size (an imported document), and a later change to
                // the ladder cannot be mistaken for one.
                let custom = design.flatMap { d -> Double? in
                    abs(d - block.designSize) > 0.01 ? Double((d * 1000).rounded() / 1000) : nil
                }
                runs.append(TextRun(text: sub,
                                    bold: font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true,
                                    italic: font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true,
                                    strike: strike,
                                    underline: underline,
                                    size: custom))
                cursor = effectiveEnd
            }
            if runs.isEmpty { continue }
            parts.append(ContentPart(type: block.persistedType, runs: runs, align: align))
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
