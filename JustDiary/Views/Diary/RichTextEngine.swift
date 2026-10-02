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

    /// 目标「总行高 ÷ 设计字号」。
    ///
    /// TextKit 真正画出来的行盒是 `font.lineHeight + lineSpacing`，而系统字体（SF）
    /// 的 lineHeight 恒为 ≈1.193 × 字号。这个倍率由三个**可查的来源**一起定
    /// （推导与实测见 `docs/editor-typography.md` 第八节）：
    ///
    /// * **HIG「iOS built-in text styles」的行高是下限**：Title 1 28→34（1.21）、
    ///   Title 2 22→28（1.27）、Body 17→22（1.29）、Subheadline 15→20（1.33）。
    /// * **中日韩正文要容得下真正画字的字体**。系统字体给的行盒只有 20.29pt（17pt），
    ///   而 PingFang SC 自己的行高是 23.80pt（1.40em，模拟器实测）—— 差 3.5pt，汉字
    ///   上下几乎贴在一起，这就是「中文看着挤」的原因。1.40 是 CJK 的硬下限。
    /// * **HIG 明确要求长段落用松行距**：*"when you display text in wide columns or long
    ///   passages, more space between lines (loose leading) can make it easier for people
    ///   to keep their place while moving from one line to the next."* 日记正是长段落。
    ///
    /// 于是正文取 1.50（17pt → 25.5pt），比三个下限都宽；标题 / 小标题是短行，
    /// 贴着 HIG 的梯级走，保持「字号越大行距越紧」的层次。
    var lineHeightRatio: CGFloat {
        switch self {
        case .title: return 1.25
        case .heading: return 1.32
        case .body: return 1.50
        case .quote: return 1.60
        }
    }

    /// Extra leading between wrapped lines: whatever the target line height needs
    /// on top of the font's own. Proportional to the design size, so it follows
    /// the system text size like everything else.
    var lineSpacing: CGFloat {
        designSize * (lineHeightRatio - EditorDesignSize.systemLineHeightRatio)
    }

    /// **段间距全部由「段前距」承担，段后距一律为 0。**
    ///
    /// 这不是随手选的：TextKit 把段前距折进**这一段自己的行盒**，把段后距折进
    /// **上一段的盒底**，而一行文字下面本来就还压着 `lineSpacing`（行盒每行都加，
    /// 最后一行也加）。所以两段之间的实际空隙是：
    ///
    ///     上一段的 lineSpacing + 上一段的段后距 + 这一段的段前距
    ///
    /// 两件事因此变简单：
    /// * **图片上下的可见留白能配平**：图片的段前距 / 段后距只要各扣掉「行盒与墨迹之间
    ///   那两段看不见的空白」（`imageTopSlack` / `imageBottomSlack`，见
    ///   `imageParagraphStyle()`），肉眼上下的空白就一样多；
    /// * **贴边的段距会被丢掉**。读模式每个块是独立的文本视图，文档第一段的段前距与
    ///   最后一段的段后距都不生效 —— 段前距承担间距时，块首块尾不会多出空白，正好。
    ///
    /// 标题仍然是「离上文比离下文远」：它自己的段后距是 0，下面由正文的段前距撑开，
    /// 而上面的空隙还要再加上正文的 `lineSpacing`（见 `EditorSpacingTests` 的实测）。
    var paragraphSpacing: CGFloat { 0 }

    /// 这一段的段前距 —— 段间距的实际来源。
    ///
    /// 正文 0.5×17 = 8.5pt（半行上下），标题 / 小标题更大，引用与正文对称。
    var paragraphSpacingBefore: CGFloat {
        switch self {
        case .title: return designSize * 0.55
        case .heading: return designSize * 0.55
        case .body: return designSize * 0.50
        case .quote: return designSize * 0.60
        }
    }

    /// Styles offered by the format bar's paragraph-style menu, in Notes' order
    /// (largest first). Quote is not here: it is a marker as much as a style, so
    /// it keeps its own toolbar button.
    static let menuStyles: [EditorBlockStyle] = [.title, .heading, .body]

    /// The value persisted in `ContentPart.style`.
    var partStyle: String {
        switch self {
        case .title: return ContentPartStyle.title
        case .heading: return ContentPartStyle.heading
        case .body: return ContentPartStyle.body
        case .quote: return ContentPartStyle.quote
        }
    }

    /// The editor style for a persisted part style. `list`, `todo` and `image`
    /// have their own persisted names but are drawn with the body attributes.
    init(partStyle: String) {
        switch partStyle {
        case ContentPartStyle.title: self = .title
        case ContentPartStyle.heading: self = .heading
        case ContentPartStyle.quote: self = .quote
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

    /// 中日韩字体自己的 `lineHeight ÷ 字号`：PingFang SC 在 17pt 实测 23.80（1.40），
    /// 而系统字体给的行盒只有 1.193em —— 汉字会在这个盒子里上下贴住，所以**成段的
    /// CJK 正文行高不能低于它**（见 `EditorBlockStyle.lineHeightRatio`）。
    static let cjkLineHeightRatio: CGFloat = 1.40

    /// 系统字体（SF）的 `lineHeight ÷ 字号`。实测 11–28pt 恒定 1.193（17pt → 20.29、
    /// 22pt → 26.25、28pt → 33.41），所以「目标行高」可以直接按比例换算成
    /// `lineSpacing`，不需要为每个字号查表。
    static let systemLineHeightRatio: CGFloat = 1.193

    /// 列表 / 待办项之间的间距，比正文段距小得多（同一个列表的几项是一组，
    /// 挨紧一点才像一组，但仍然分得开、点得准）。
    static let markerSpacing = body * 0.15

    /// Breathing room above and below an image, in design points.
    ///
    /// Expressed through the image paragraph's spacing so the editor gets it
    /// from TextKit; the reader adds the same number as padding around its
    /// image chunk. Before this existed the editor gave an image 0pt (it was
    /// glued to the text above and below) while the reader added a stack gap
    /// plus a phantom line — the same entry looked different in the two.
    ///
    /// 0.8 个正文：一段正文之间的实际空隙是 `lineSpacing + 段前距` = 13.7pt，
    /// 图片是单独一块，留白不该比段落之间还小。
    static let imageSpacing = body * 0.8

    /// 图片上下各有一次「看不见的空白」，按正文字号等比（17pt 实测值写在注释里）。
    ///
    /// TextKit 2 把附件放在**基线**上，于是行盒与墨迹不重合：
    /// * 图片**上方**：上一段的行盒底比它的墨迹低 `0.153em`（约 2.6pt）—— 这段空白
    ///   眼睛看不到，图片的段前距要把它补上；
    /// * 图片**下方**：下面那一行的墨迹从自己的行盒顶往下 `0.735em`（约 12.5pt）才开始
    ///   （CJK 字面远低于 ascent）—— 这段同样看不到，图片的段后距要把它扣掉。
    ///
    /// 修正之后，**肉眼**上下的空白才真的一样多（`EditorSpacingTests` 的像素用例逐行量
    /// 过）。这两个数是字体几何，不是设计偏好：换字体 / 换书写系统要重新实测。
    static let imageTopSlack = body * 0.153
    static let imageBottomSlack = body * 0.735

    /// 读模式里图片**外面**那一圈 padding：`DiaryPartsView` 用它。
    ///
    /// 读模式的正文块自己带 `BlockMetrics.textContainerInset`（上下各 6pt），块里的墨迹
    /// 又离块顶 `imageTopSlack`（≈2.6pt）—— 这两段都算「已经给了的空白」，所以 padding
    /// 要比 `imageSpacing` 小这么多，图片上下才是同样的 `imageSpacing`。
    static var readerImagePadding: CGFloat {
        max(0, imageSpacing - BlockMetrics.textContainerInset.top - imageTopSlack)
    }

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
    /// the editor and never persisted: the persisted form is the block's
    /// `ContentPart.style`, which is what the size is derived from again on load.
    static let diaryDesignSize = NSAttributedString.Key("com.cov.justdiary.designSize")

    /// The paragraph style a run belongs to. Also editor-internal: the persisted
    /// form is `ContentPart.style`. Carrying it in the text storage is what makes
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
    /// typed after the first one loses the custom key — and the fallback has to
    /// be *exact*: it is what decides a paragraph's block type, and an
    /// approximation drifts upward on every save until a paragraph crosses the
    /// heading threshold and the entry is rewritten as a heading.
    ///
    /// Sizes this editor itself draws are therefore matched exactly against the
    /// forward mapping before falling back to division, which is only needed for
    /// sizes the editor did not author (imported material).
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
    var dynamicTypeSize: DynamicTypeSize = .large {
        didSet {
            guard dynamicTypeSize != oldValue else { return }
            // 引用装饰（圆角、内边距）与标记图形都按这个档位换算。
            (textView as? DiaryTextView)?.contentTypeSize = dynamicTypeSize
        }
    }

    /// Typing attributes for a paragraph of `block`: what the next typed
    /// character will look like. Also the reset applied after a block toggle.
    ///
    /// The paragraph style comes from `PartsCodec`, the same factory the codec
    /// uses to assemble a stored entry — that is what keeps "what you type" and
    /// "what you see after reopening" identical (quote indent included).
    func typingAttributes(for block: EditorBlockStyle) -> [NSAttributedString.Key: Any] {
        var attrs = EditorFont.attributes(block.designSize, block: block, typeSize: dynamicTypeSize)
        attrs[.foregroundColor] = Theme.onSurfaceUIColor()
        attrs[.paragraphStyle] = PartsCodec.paragraphStyle(block, typeSize: dynamicTypeSize)
        return attrs
    }

    /// Typing state on a list / to-do line: body attributes plus the marker's
    /// hanging indent, so the caret and the text after the marker line up under
    /// the item's own text rather than at the column's edge.
    func markerTypingAttributes(kind: String) -> [NSAttributedString.Key: Any] {
        var attrs = EditorFont.attributes(EditorDesignSize.body, block: .body, typeSize: dynamicTypeSize)
        attrs[.foregroundColor] = Theme.onSurfaceUIColor()
        attrs[.paragraphStyle] = PartsCodec.markerParagraphStyle(typeSize: dynamicTypeSize, kind: kind)
        return attrs
    }

    func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        typingAttributes(for: .body)
    }

    func refreshTypingAttributes() {
        if let tv = textView { setTypingAttributes(baseTypingAttributes(), in: tv) }
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
        guard range.length > 0 else {
            // No selection: the toggle describes what is typed next. Characters
            // that are already there are never rewritten.
            let font = (tv.typingAttributes[.font] as? UIFont)
                ?? EditorFont.font(EditorDesignSize.body, typeSize: dynamicTypeSize)
            var sym = font.fontDescriptor.symbolicTraits
            let adding = !sym.contains(trait)
            if adding { sym.insert(trait) } else { sym.remove(trait) }
            if let base = font.fontDescriptor.withSymbolicTraits(sym) {
                let desc = Self.applyItalicSlant(base, trait: trait, adding: adding)
                tv.typingAttributes[.font] = UIFont(descriptor: desc, size: font.pointSize)
            }
            notifyFormatChange()
            return
        }
        // One state for the whole selection. Toggling each run on its own (what
        // this used to do) turned a mixed selection into a patchwork: half of
        // it gained the trait while the other half lost it.
        let removing = selectionHasTrait(trait, in: range)
        apply { attributed in
            attributed.enumerateAttribute(.font, in: range) { value, subRange, _ in
                guard let font = value as? UIFont else { return }
                var sym = font.fontDescriptor.symbolicTraits
                if removing { sym.remove(trait) } else { sym.insert(trait) }
                guard let base = font.fontDescriptor.withSymbolicTraits(sym) else { return }
                let desc = Self.applyItalicSlant(base, trait: trait, adding: !removing)
                attributed.removeAttribute(.font, range: subRange)
                attributed.addAttribute(.font, value: UIFont(descriptor: desc, size: font.pointSize), range: subRange)
            }
        }
    }

    /// Whether every font in `range` already carries `trait`, which is what
    /// decides the direction a toggle goes in. Runs without a font (attachment
    /// characters) are ignored: there is nothing to toggle there.
    private func selectionHasTrait(_ trait: UIFontDescriptor.SymbolicTraits, in range: NSRange) -> Bool {
        guard let tv = textView, range.length > 0 else { return false }
        var found = false
        var all = true
        tv.textStorage.enumerateAttribute(.font, in: range) { value, _, _ in
            guard let font = value as? UIFont else { return }
            found = true
            if !font.fontDescriptor.symbolicTraits.contains(trait) { all = false }
        }
        return found && all
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
        guard range.length > 0 else {
            // No selection: only the next typed characters change.
            let active = (tv.typingAttributes[key] as? Int ?? 0) != 0
            tv.typingAttributes[key] = active ? 0 : 1
            notifyFormatChange()
            return
        }
        // Uniform across the selection, exactly like the font traits above.
        let removing = selectionHasStyle(key, in: range)
        apply { attributed in
            attributed.removeAttribute(key, range: range)
            attributed.addAttribute(key, value: removing ? 0 : 1, range: range)
        }
    }

    /// Whether every run in `range` already carries the 0/1 valued line style
    /// `key`. Decides the direction a strike/underline toggle goes in.
    private func selectionHasStyle(_ key: NSAttributedString.Key, in range: NSRange) -> Bool {
        guard let tv = textView, range.length > 0 else { return false }
        var found = false
        var all = true
        tv.textStorage.enumerateAttribute(key, in: range) { value, _, _ in
            found = true
            if (value as? Int ?? 0) == 0 { all = false }
        }
        return found && all
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
        let caret = tv.selectedRange
        let lineStart = paragraphRange(in: tv.textStorage, around: caret.location).location
        let lengthBefore = tv.textStorage.length
        let ranges = paragraphRanges(covering: caret)
        let dropped = markerDrops(in: tv.textStorage, ranges: ranges, caret: caret)
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
        keepCaretOnItsLine(caret, lineStart: lineStart, lengthBefore: lengthBefore, dropped: dropped)
        setTypingAttributes(typingAttributes(for: block), in: tv)
        carryEmptyLineAlignment(of: block, into: tv)
        syncEmptyParagraphWithTypingAttributes()
        ensureCaretGeometry()
    }

    /// 空行上换行样式时的对齐：标题 / 正文保留这一行原来的对齐（居中可以与它们共存），
    /// 引用强制左对齐 —— 与 `restyle` 对整行的规则一致。
    ///
    /// 少了这一步，一条居中的空行选完「大标题」会跳回左边；引用那条也不能只靠
    /// `NSMutableParagraphStyle` 默认的 `.natural`（RTL 文本里那是右对齐）。
    private func carryEmptyLineAlignment(of block: EditorBlockStyle, into tv: UITextView) {
        if block == .quote {
            Self.setTypingAlignment(.left, in: tv)
            return
        }
        if let alignment = emptyLineAlignment() {
            Self.setTypingAlignment(alignment, in: tv)
        }
    }

    /// 把光标所在那一段（以及文档末尾）排出来，并让 UIKit 重算一次光标几何。
    ///
    /// TextKit 2 是**懒排版**，而且「文档以换行结尾时最后那个空段落」不会被自动排到：
    /// `textLayoutFragment(for: 文档末尾)` 是 nil（实测 usageBounds 正好停在上一行底部）。
    /// 这时 UIKit 的光标几何会退回「最后一个已排版片段的**末尾**」—— 也就是**上一行文字的
    /// 结尾**：光标画在上一行末尾，而逻辑位置（`selectedRange`）一直是最后那一行，所以打字
    /// 又落在下一行。摘掉末尾列表项的标记（引用 / 换字号 / 回车结束列表）之后正好是这个状态，
    /// 而且不会自己恢复（实测 10 秒不变）。
    ///
    /// 两步：① 把「光标那一段 → 文档末尾」这一段排出来（增量，不整篇重排）；
    /// ② 在**下一轮 runloop**再让 UIKit 重取一次几何 —— 切换那一瞬间布局还没算完，
    /// 早做无效（上一轮试过「切换时立刻抖选区」，确认没用）。
    ///
    /// 每一步排完之后都补一次 `notifyFormatChange()`（B35）：调用方在改文本 / 打字态时已经
    /// 刷新过一次装饰层，但那一次发生在**这一段排版之前** —— 空行上新建引用时它算出来的还是
    /// 「这一行不是引用」，底色块根本不画；而后面没有第二次刷新，用户看到的就是引用背景
    /// 晚一拍才出现（那一下闪）。排完再刷一次，块在点下去的这一帧就到位。
    func ensureCaretGeometry() {
        guard let tv = textView else { return }
        layOutThroughDocumentEnd(in: tv)
        notifyFormatChange()
        DispatchQueue.main.async { [weak self, weak tv] in
            guard let self, let tv, tv.isFirstResponder else { return }
            self.layOutThroughDocumentEnd(in: tv)
            // 下一轮那一遍排版也补一次：文末那一段是这一遍才真正排出来的。
            self.notifyFormatChange()
        }
    }



    /// 从光标那一段（往前一格，含它的换行符）一路排到文档末尾。
    ///
    /// **必须先 `invalidateLayout`**：末尾那个空段落没有字符、也没有片段，而 TextKit 认为
    /// 它「已经排完了」—— 只调 `ensureLayout` 什么都不会发生（实测：片段仍然是 nil）。
    /// 作废之后重排，末尾那一行才会被真正排出来（实测线框高度正好多出一行、光标几何随之
    /// 落到行首）。作废范围只取光标往后这一小段，不是整篇。
    private func layOutThroughDocumentEnd(in tv: UITextView) {
        guard let layoutManager = tv.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }
        let length = tv.textStorage.length
        guard length > 0 else { return }
        let caret = min(max(0, tv.selectedRange.location), length)
        let paragraph = paragraphRange(in: tv.textStorage, around: caret)
        let from = max(0, min(paragraph.location, length - 1) - 1)
        guard let start = contentManager.location(contentManager.documentRange.location, offsetBy: from),
              let end = contentManager.location(start, offsetBy: length - from),
              let range = NSTextRange(location: start, end: end) else { return }
        layoutManager.invalidateLayout(for: range)
        layoutManager.ensureLayout(for: range)
        layoutManager.textViewportLayoutController.layoutViewport()
    }

    /// 光标所在**空行**当前的对齐；光标不在空行上时为 nil。
    ///
    /// 空行的对齐在它自己的换行符上；文本末尾那条空行没有自己的字符，对齐在打字态里。
    private func emptyLineAlignment() -> NSTextAlignment? {
        guard let tv = textView else { return nil }
        if let range = emptyParagraphTerminator(in: tv.textStorage, at: tv.selectedRange.location) {
            let style = tv.textStorage.attribute(.paragraphStyle, at: range.location,
                                                 effectiveRange: nil) as? NSParagraphStyle
            return style?.alignment
        }
        guard Self.paragraphIsEmpty(in: tv.textStorage, location: tv.selectedRange.location) else {
            return nil
        }
        return (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment
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

    /// 光标落定之后，把 UIKit 抹掉的**块类型**补回打字态。
    ///
    /// UIKit 每次光标移动 / 文字变更都会按「光标处的文字」重算 `typingAttributes`，
    /// 而它只认自己认识的那些键：`.diaryBlockStyle`（这一段是引用 / 正文 / 标题）与
    /// `.diaryDesignSize`（设计字号）会被丢掉。丢掉之后「引用」就只剩 15pt 字号 +
    /// 16pt 缩进 —— 引用按钮灭了、底色没了，回车续出来的新行顶着引用的缩进却不是引用
    /// （用户报的 bug），光标挪开再回来也一样，得点一次别的格式再取消才能回到列首。
    ///
    /// 段落自己才是块类型的权威（`restyle` / `parts(from:)` 用的是同一套判据），所以
    /// 这里只补这两个自定义键；字号、段落几何、行内样式都还是 UIKit 算出来的那套 ——
    /// 只有**文末那条空行**例外，见下。
    func resyncBlockAttributesWithCaret() {
        guard let tv = textView, let caret = caretBlockStyle() else { return }
        let block: EditorBlockStyle
        if caret.trailingEmptyLine, let line = trailingEmptyLineBreak(in: tv) {
            // 文末那条空行：它的样式只活在打字态里，而 UIKit 每次光标 / 文字变化都会把
            // 自定义键抹掉、按上一段的换行符重算 —— 于是「在它上面取消引用 → 输入文字 →
            // 再把文字删掉」之后，取消掉的引用自己又回来了（用户报的）。
            // 所以这一行以「用户最后一次为它挑的样式」为准（`trailingEmptyLineStyle`），
            // 没记过才退回「延续上一段」。
            let remembered = trailingEmptyLineStyle?.breakIndex == line ? trailingEmptyLineStyle?.block : nil
            block = EditorFont.blockStyle(of: tv.typingAttributes) ?? remembered ?? caret.block
            trailingEmptyLineStyle = (line, block)
        } else {
            block = caret.block
        }
        if EditorFont.blockStyle(of: tv.typingAttributes) != block {
            tv.typingAttributes[.diaryBlockStyle] = block.rawValue
        }
        if EditorFont.designSize(of: tv.typingAttributes, typeSize: dynamicTypeSize) != block.designSize {
            tv.typingAttributes[.diaryDesignSize] = NSNumber(value: Double(block.designSize))
        }
        guard caret.trailingEmptyLine else { return }
        // 文末那条空行的段落几何**完全**由打字态决定，而 UIKit 是照上一段的换行符推导
        // 出来的：上一段是列表 / 待办时，那份悬挂缩进（18 / 26pt）与更小的段距会留到
        // 这一行上 —— 打字得到的明明是正文，折行却缩进 18pt、段距也不是正文的。
        // 所以按块类型重排一遍；居中延续（R4）保留，引用照旧强制左对齐。
        let alignment = (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment
        tv.typingAttributes[.paragraphStyle] = PartsCodec.paragraphStyle(
            block, center: alignment == .center && block != .quote, typeSize: dynamicTypeSize)
    }

    /// 文末那条**没有自己字符**的空行当前的块类型记录（见 `trailingEmptyLineStyle`）。
    ///
    /// `breakIndex` 是文档最后一个换行的位置：那一个换行换了，这一行就是「另一条空行」了。
    private var trailingEmptyLineStyle: (breakIndex: Int, block: EditorBlockStyle)?

    /// 光标是不是停在**文末那条没有自己字符的空行**上；是的话给出文档最后一个换行的位置。
    ///
    /// 「文末那条空行」= 文档以换行结尾（或整篇为空）时的最后一段。它没有字符，样式只能
    /// 放在打字态里，UIKit 又会按上一段的换行符重算 —— 所以这一段要单独认。
    private func trailingEmptyLineBreak(in tv: UITextView) -> Int? {
        let storage = tv.textStorage
        guard tv.selectedRange.length == 0, tv.selectedRange.location >= storage.length else { return nil }
        let ns = storage.string as NSString
        guard ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A else { return nil }
        return ns.length - 1
    }

    /// 记下「用户为文末那条空行挑的样式」。设置打字态的地方都经过 `setTypingAttributes`，
    /// 所以光标停在这一行上时挑的样式都会被记住。
    private func rememberTrailingEmptyLineStyle() {
        guard let tv = textView, let line = trailingEmptyLineBreak(in: tv),
              let block = EditorFont.blockStyle(of: tv.typingAttributes) else { return }
        trailingEmptyLineStyle = (line, block)
    }

    /// 设置打字态，并顺手记下文末空行的样式（见 `trailingEmptyLineStyle`）。
    private func setTypingAttributes(_ attrs: [NSAttributedString.Key: Any], in tv: UITextView) {
        tv.typingAttributes = attrs
        rememberTrailingEmptyLineStyle()
    }

    /// 光标所在那一段的块类型，以及它是不是**文末那条没有自己字符的空行**。
    ///
    /// * 有文字的段落：看**段落第一个字符**（UIKit 会把后续字符上的自定义键抹掉）；
    /// * 中间那条空行：看它**自己的换行符**（B22：空行的行盒就是它排出来的）；
    /// * 文末那条空行没有自己的字符，它的行样式按「延续上一段」推导（UIKit 自己也是
    ///   这么算打字态的），所以看文末那个字符。
    ///
    /// 段落没有块类型（导入内容、列表 / 待办的行首标记、图片后面那个空换行）时返回
    /// nil，调用方什么都不做。
    private func caretBlockStyle() -> (block: EditorBlockStyle, trailingEmptyLine: Bool)? {
        guard let tv = textView else { return nil }
        let storage = tv.textStorage
        guard storage.length > 0 else { return nil }
        let location = tv.selectedRange.location
        var probe = -1
        var trailingEmptyLine = false
        if Self.paragraphIsEmpty(in: storage, location: location) {
            if let terminator = emptyParagraphTerminator(in: storage, at: location) {
                probe = terminator.location
            } else if min(max(0, location), storage.length) >= storage.length {
                probe = storage.length - 1
                trailingEmptyLine = true
            } else {
                return nil
            }
        } else {
            let para = paragraphRange(in: storage, around: location)
            guard para.location < storage.length else { return nil }
            probe = para.location
        }
        guard let block = EditorFont.blockStyle(of: storage.attributes(at: probe, effectiveRange: nil)) else {
            return nil
        }
        return (block, trailingEmptyLine)
    }

    /// Restyles one paragraph (newline included), preserving bold/italic traits.
    private func restyle(_ attributed: NSMutableAttributedString, range: NSRange,
                         to block: EditorBlockStyle, cancelCenter: Bool = false) {
        // An image line is not text: a text style would only rewrite its
        // spacing (a title's paragraph gap does not belong around a picture).
        if range.location < attributed.length,
           let payload = (attributed.attribute(.attachment, at: range.location, effectiveRange: nil) as? PayloadAttachment)?.payload,
           payload.kind == "image" {
            return
        }
        // Drop a list/todo marker: it is a paragraph style of its own, and it
        // would otherwise stay attached to what is now a heading/quote/body.
        if range.location < attributed.length,
           let payload = (attributed.attribute(.attachment, at: range.location, effectiveRange: nil) as? PayloadAttachment)?.payload,
           payload.kind == "bullet" || payload.kind == "todo" {
            attributed.replaceCharacters(in: NSRange(location: range.location, length: 1), with: "")
        }
        let para = paragraphRange(in: attributed, around: range.location)
        guard para.length > 0 else {
            // An empty paragraph has no text to rewrite, but it still has a line
            // box — and TextKit builds that box from the paragraph's *own*
            // terminator (the paragraph style comes from the paragraph's first
            // character, `docs/editor-typography.md` §5.2). Writing the style
            // there is what makes "open a new line, then pick a style" show up on
            // the line the caret is on, instead of only on the first typed
            // character. The paragraph that ends the text has no character of its
            // own; `typingAttributes` already lay that one out.
            styleEmptyParagraph(in: attributed, at: range.location, to: block, cancelCenter: cancelCenter)
            return
        }
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
        // A quote's background is no longer an attribute: `DiaryTextView` draws
        // the block (rounded background + bar) behind the paragraph. Any
        // background left by an older version is dropped here so the old
        // highlighter look cannot survive an edit.
        attributed.removeAttribute(.backgroundColor, range: para)
        attributed.enumerateAttribute(.paragraphStyle, in: para) { value, r, _ in
            let style = ((value as? NSParagraphStyle) ?? NSParagraphStyle()).mutableCopy() as! NSMutableParagraphStyle
            Self.applyBlockGeometry(to: style, block: block, cancelCenter: cancelCenter,
                                    typeSize: dynamicTypeSize)
            attributed.addAttribute(.paragraphStyle, value: style, range: r)
        }
    }

    /// Writes a block's paragraph-level geometry (gaps and, for a quote, the
    /// indent its bar needs) onto an existing style.
    ///
    /// Both the paragraph restyle and the empty-line helpers go through here:
    /// the numbers themselves live in `PartsCodec` / `BlockMetrics`, so the
    /// editor cannot drift from the reader.
    private static func applyBlockGeometry(to style: NSMutableParagraphStyle, block: EditorBlockStyle,
                                           cancelCenter: Bool, typeSize: DynamicTypeSize) {
        if cancelCenter || block == .quote {
            style.alignment = .left
        }
        style.lineSpacing = block.lineSpacing
        style.paragraphSpacing = block.paragraphSpacing
        // 段前距也要跟着换：少了这一句，编辑区里「选大标题」得到的行没有标题的
        // 段前留白，而重新打开这篇日记（走 `PartsCodec.paragraphStyle`）却带着它
        // （改造前是 9.8pt，现行模型是 0.55 × 28 = 15.4，见 `lineHeightRatio` 那一节）
        // —— 同一条标题在两条链路上长得不一样。
        style.paragraphSpacingBefore = block.paragraphSpacingBefore
        // 引用正文要让开左侧竖条；其它块（列表 / 待办的行会被 `restyle` 先摘掉标记）
        // 必须显式归零，否则从引用改成正文后整段会留在缩进里。
        let indent = block == .quote ? BlockMetrics.quoteTextInset(typeSize) : 0
        style.firstLineHeadIndent = indent
        style.headIndent = indent
    }

    /// Paragraph ranges (terminating newline included) touched by `range`.
    ///
    /// * A selection contributes every paragraph it actually overlaps.
    /// * A caret contributes the caret's own paragraph and nothing else. The
    ///   old test — `location >= start && location <= lineEnd` — also matched
    ///   the paragraph *above*, because a line's exclusive end is the next
    ///   line's start: restyling a freshly opened line silently rewrote the
    ///   line above it, which is exactly the state right after Return.
    /// * A caret paragraph that holds no text resolves to a zero-width range at
    ///   its line start, so callers can tell "nothing to restyle here" from
    ///   "restyle this paragraph". `includeEmpty` keeps that range (the
    ///   list/to-do markers need an anchor there); text styles drop it and only
    ///   affect what is typed next.
    private func paragraphRanges(covering range: NSRange, includeEmpty: Bool = false) -> [NSRange] {
        guard let tv = textView else { return [] }
        let storage = tv.textStorage
        if range.length == 0 {
            let para = paragraphRange(in: storage, around: range.location)
            if para.length > 0 { return [para] }
            return includeEmpty ? [para] : []
        }
        let ns = storage.string as NSString
        var result: [NSRange] = []
        var start = 0
        while start < ns.length {
            var end = start
            while end < ns.length && ns.character(at: end) != 0x0A {
                end += 1
            }
            let lineEnd = end < ns.length ? end + 1 : end
            let line = NSRange(location: start, length: lineEnd - start)
            if NSIntersectionRange(range, line).length > 0 { result.append(line) }
            start = end + 1
        }
        return result
    }

    func toggleCenter() {
        guard let tv = textView else { return }
        // Center cannot coexist with list/quote/todo; the toolbar disables the
        // button while one of them is active, guard here too.
        if isListActive() || isQuoteActive() || isTodoActive() { return }
        let center = isCenterActive()

        // Every paragraph the selection touches, like the style menu and quote.
        // It used to look at `selectedRange.location` alone, so a multi-line
        // selection only centered its first line.
        let ranges = paragraphRanges(covering: tv.selectedRange)
        if !ranges.isEmpty {
            apply { attributed in
                for range in ranges.reversed() {
                    // A selection may well cover a quote / list / to-do line, where
                    // this button is disabled on purpose: skip those lines instead
                    // of centring them behind the user's back.
                    guard Self.centerIsAllowed(in: attributed, at: range.location) else { continue }
                    let para = self.paragraphRange(in: attributed, around: range.location)
                    guard para.length > 0 else {
                        // An empty line covered by the selection is a line too: its
                        // alignment lives on its own terminator (see the empty-line
                        // helpers below). Leaving it out made two identical empty
                        // lines end up in different alignments after one tap.
                        self.setEmptyParagraphAlignment(center ? .left : .center,
                                                        in: attributed, at: range.location)
                        continue
                    }
                    let existing = (attributed.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle()
                    let style = existing.mutableCopy() as! NSMutableParagraphStyle
                    style.alignment = center ? .left : .center
                    attributed.addAttribute(.paragraphStyle, value: style, range: para)
                }
            }
        } else {
            // An empty line holds no typed text of its own: only what is typed
            // next changes, and the paragraph above is left alone.
            notifyFormatChange()
        }
        Self.setTypingAlignment(center ? .left : .center, in: tv)
        // …and the empty line itself has to follow, or the caret stays in the old
        // alignment until the first character is typed.
        syncEmptyParagraphWithTypingAttributes()
        ensureCaretGeometry()
    }

    /// Center cannot coexist with a list/to-do marker or a quote (the toolbar
    /// disables the button on those lines). An image is skipped for the same
    /// reason `restyle` skips it: its paragraph is centred by the codec, so a
    /// left-aligned image line would only exist until the entry is re-opened.
    private static func centerIsAllowed(in storage: NSAttributedString, at location: Int) -> Bool {
        guard location >= 0, location < storage.length else { return false }
        let attrs = storage.attributes(at: location, effectiveRange: nil)
        if let payload = (attrs[.attachment] as? PayloadAttachment)?.payload,
           payload.kind == "bullet" || payload.kind == "todo" || payload.kind == "image" {
            return false
        }
        if EditorFont.blockStyle(of: attrs) == .quote { return false }
        if let bg = attrs[.backgroundColor] as? UIColor, !bg.isEqual(UIColor.clear) { return false }
        return true
    }

    /// Points the *next typed* paragraph at `alignment`, keeping the rest of the
    /// typing attributes (font, block style, spacing) as they are. Copies the
    /// style instead of mutating it in place: `typingAttributes` can hold an
    /// object that is also referenced by stored text.
    private static func setTypingAlignment(_ alignment: NSTextAlignment, in tv: UITextView) {
        let existing = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = alignment
        tv.typingAttributes[.paragraphStyle] = style
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
        let selection = tv.selectedRange
        // Empty lines are kept: on a line with no text the marker *is* the
        // line's content, so there is always somewhere to put it.
        let ranges = paragraphRanges(covering: selection, includeEmpty: true)
        guard !ranges.isEmpty else { return }
        let caretLine = paragraphRange(in: tv.textStorage, around: selection.location).location
        let isMarked = Self.markerKind(in: tv.textStorage, at: caretLine) == kind
        let lengthBefore = tv.textStorage.length

        apply { attributed in
            // Back to front: every insertion/removal shifts the lines after it.
            for range in ranges.reversed() {
                let lineStart = range.location
                if isMarked {
                    // Only strip a marker we can actually confirm exists.
                    if Self.markerKind(in: attributed, at: lineStart) == kind {
                        attributed.replaceCharacters(in: NSRange(location: lineStart, length: 1), with: "")
                        // 标记占的缩进挂在**这一行的段落样式**上（`headIndent`，换行后的
                        // 文字才能对齐首行）。摘掉标记就得把它归零，否则这一行会顶着一份
                        // 「列表的缩进」继续当正文排（标记没了、文字却还缩着）。
                        self.restyle(attributed, range: NSRange(location: lineStart, length: 0),
                                     to: .body)
                    }
                } else {
                    // Turning on: cancel heading / quote / other marker / center first.
                    self.restyle(attributed, range: NSRange(location: lineStart, length: 0),
                                 to: .body, cancelCenter: true)
                    attributed.insert(MarkerAttachment.attributed(
                        kind: kind,
                        typeSize: self.dynamicTypeSize,
                        traits: tv.traitCollection,
                        paragraphStyle: self.markerTypingAttributes(kind: kind)[.paragraphStyle] as? NSParagraphStyle
                    ), at: lineStart)
                }
            }
        }

        // Keep the caret inside the item it was in: that line just gained or
        // lost one character before the caret.
        if selection.length == 0 {
            let delta = tv.textStorage.length - lengthBefore
            let target = min(max(0, max(caretLine, selection.location + delta)), tv.textStorage.length)
            tv.selectedRange = NSRange(location: target, length: 0)
        }
        // Reset typing attributes. Continuing the list onto the next line is
        // `handleReturn(at:)`'s job — the marker is a real character and typing
        // attributes cannot carry it. Turning the marker *off* goes back to plain
        // body attributes: a marker's hanging indent left on a plain paragraph
        // would indent its wrapped lines for no reason.
        setTypingAttributes(isMarked ? baseTypingAttributes() : markerTypingAttributes(kind: kind), in: tv)
        // Toggling the marker *off* can leave an empty line behind; toggling it on
        // puts a marker on the line, so there is nothing left to sync there.
        syncEmptyParagraphWithTypingAttributes()
        ensureCaretGeometry()
    }

    /// The list/to-do marker at `location`, if there is one.
    private static func markerKind(in storage: NSAttributedString, at location: Int) -> String? {
        guard location >= 0, location < storage.length,
              let payload = (storage.attribute(.attachment, at: location, effectiveRange: nil) as? PayloadAttachment)?.payload,
              payload.kind == "bullet" || payload.kind == "todo" else { return nil }
        return payload.kind
    }

    /// Handles Return inside a line-styled paragraph.
    ///
    /// List and to-do markers are real characters at the line start, so UIKit's
    /// own newline cannot carry them onto the next line: pressing Return inside
    /// an item has to start the next item here. Quote needs the same treatment
    /// for a different reason — see the branch below. The same rule *ends* the
    /// style on an empty line — that is what keeps "the style continues on the
    /// next line" from trapping the user, because Return twice yields a plain
    /// paragraph.
    ///
    /// `range` is what this keystroke replaces — the range UIKit hands to
    /// `shouldChangeTextIn`, i.e. the selection when there is one. The branches
    /// that insert the newline themselves delete it first: they never hand the
    /// edit back to UIKit, so leaving the selected text in place would push the
    /// newline into the middle of it.
    ///
    /// Returns true when the keystroke has been consumed here.
    @discardableResult
    func handleReturn(in range: NSRange) -> Bool {
        guard let tv = textView else { return false }
        let location = range.location
        let storage = tv.textStorage
        let ns = storage.string as NSString
        let para = paragraphRange(in: storage, around: location)
        let lineStart = para.location
        // End of the paragraph's text, excluding its terminating newline.
        var contentEnd = lineStart + para.length
        if contentEnd > lineStart, contentEnd <= ns.length, ns.character(at: contentEnd - 1) == 0x0A {
            contentEnd -= 1
        }
        // 选区：这个回车是**替换**它。只有「自己插换行」的两条路径会调用它 ——
        // 返回 false 的那些不能删（UIKit 还要拿原来那个 range 去应用它自己的编辑）。
        func replaceSelection() -> Int {
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return location }
            storage.deleteCharacters(in: range)
            return min(max(0, location), storage.length)
        }

        if let kind = Self.markerKind(in: storage, at: lineStart) {
            let contentStart = lineStart + 1
            guard contentEnd > contentStart else {
                // Empty item: end the list here, leaving the line where it is
                // (now a plain empty paragraph). Return again for a blank line.
                // 空项上不该有选区（这一行只有一个标记），真选了就交回 UIKit。
                guard range.length == 0 else { return false }
                removeMarker(kind: kind, at: lineStart)
                return true
            }
            // Start a new item: a newline plus the marker for the next line, so
            // what is typed next belongs to a fresh item of the same kind.
            let insertAt = range.length > 0 ? replaceSelection()
                                            : min(max(location, contentStart), contentEnd)
            let bodyAttributes = markerTypingAttributes(kind: kind)
            let insertion = NSMutableAttributedString()
            insertion.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
            insertion.append(MarkerAttachment.attributed(
                kind: kind,
                typeSize: dynamicTypeSize,
                traits: tv.traitCollection,
                paragraphStyle: bodyAttributes[.paragraphStyle] as? NSParagraphStyle
            ))
            storage.insert(insertion, at: insertAt)
            tv.selectedRange = NSRange(location: insertAt + insertion.length, length: 0)
            setTypingAttributes(bodyAttributes, in: tv)
            notifyFormatChange()
            return true
        }

        // 这一行是不是引用：有字的段落看**段落第一个字符**（和 `restyle` /
        // `parts(from:)` 同一套判据），文末那条空行没有自己的字符，只能看打字态。
        let lineAttrs = lineStart < ns.length ? storage.attributes(at: lineStart, effectiveRange: nil) : [:]
        let quoted = Self.attributesAreQuote(lineAttrs)
            || (contentEnd <= lineStart && isQuoteActive())

        // An empty quoted line ends the quote the same way: the line becomes a
        // plain empty paragraph and this Return is consumed.
        if contentEnd <= lineStart, quoted {
            // 空行上只有它自己的换行符可选；真选了就交回 UIKit（替换换行符 = 并段）。
            guard range.length == 0 else { return false }
            setTypingAttributes(baseTypingAttributes(), in: tv)
            // The line itself has to stop looking like a quote too, not just the
            // next typed character.
            syncEmptyParagraphWithTypingAttributes()
            // 这一行的行盒跟着打字态变（文末那条空行只能这么排），所以要把它的排版
            // 作废重来一次，光标才会从引用的缩进退回列首。
            ensureCaretGeometry()
            notifyFormatChange()
            return true
        }

        // 有文字的引用行：下一行**接着引用**（R2「新行延续该行样式」）。
        // 这一句不能交给 UIKit 的换行去做：它的换行只继承 `typingAttributes`，而
        // UIKit 每次都按光标处的文字重算这个字典，且**只认自己认识的那些键** ——
        // `.diaryBlockStyle` 会被丢掉。丢掉的后果正是用户报的那一条：新行拿到的是
        // 「15pt + 引用的缩进」，却没有「这一段是引用」这个块类型 —— 底色没了、引用
        // 按钮灭了，接着回车（以及之后在别处点一下再回来）还是这份缩进，要点一次别的
        // 格式再取消才能回到列首。所以换行符由我们自己插，带上引用的整套属性。
        if quoted {
            let attrs = typingAttributes(for: .quote)
            let insertAt = range.length > 0 ? replaceSelection()
                                            : min(max(location, lineStart), contentEnd)
            storage.insert(NSAttributedString(string: "\n", attributes: attrs), at: insertAt)
            tv.selectedRange = NSRange(location: insertAt + 1, length: 0)
            setTypingAttributes(attrs, in: tv)
            // 文档中间那条新空行有自己的换行符，行样式要一并写成引用（B22）；文末那条
            // 空行没有字符，它的行盒本来就由打字态排出。
            syncEmptyParagraphWithTypingAttributes()
            // 文末那条空行 TextKit 不会自动排（B27），光标几何得手动催一次。
            ensureCaretGeometry()
            notifyFormatChange()
            return true
        }
        return false
    }

    /// `handleReturn(in:)` 的光标版本（没有选区时用）。测试与旧的调用点用它。
    @discardableResult
    func handleReturn(at location: Int) -> Bool {
        handleReturn(in: NSRange(location: location, length: 0))
    }

    /// Drops `kind`'s marker from the line starting at `location`, if it is
    /// really there. The caret keeps its place in the line.
    private func removeMarker(kind: String, at location: Int) {
        guard let tv = textView else { return }
        let selection = tv.selectedRange
        let lengthBefore = tv.textStorage.length
        apply { attributed in
            guard Self.markerKind(in: attributed, at: location) == kind else { return }
            attributed.replaceCharacters(in: NSRange(location: location, length: 1), with: "")
        }
        let delta = tv.textStorage.length - lengthBefore
        if selection.length == 0, delta != 0 {
            let target = min(max(0, max(location, selection.location + delta)), tv.textStorage.length)
            tv.selectedRange = NSRange(location: target, length: 0)
        }
        setTypingAttributes(baseTypingAttributes(), in: tv)
        // Ending a list/to-do leaves an empty line the caret is on: it has to be
        // laid out as a plain paragraph, not as the item that just ended.
        syncEmptyParagraphWithTypingAttributes()
        ensureCaretGeometry()
        notifyFormatChange()
    }

    func isListActive() -> Bool { currentMarkerKind() == "bullet" }

    func isTodoActive() -> Bool { currentMarkerKind() == "todo" }

    private func currentMarkerKind() -> String? {
        guard let tv = textView, tv.textStorage.length > 0 else { return nil }
        let range = paragraphRange(around: tv.selectedRange)
        return Self.markerKind(in: tv.textStorage, at: range.location)
    }

    func toggleQuote() {
        guard let tv = textView else { return }
        let block: EditorBlockStyle = isQuoteActive() ? .body : .quote
        let caret = tv.selectedRange
        let lineStart = paragraphRange(in: tv.textStorage, around: caret.location).location
        let lengthBefore = tv.textStorage.length
        let ranges = paragraphRanges(covering: caret)
        let dropped = markerDrops(in: tv.textStorage, ranges: ranges, caret: caret)
        if !ranges.isEmpty {
            apply { attributed in
                for range in ranges.reversed() {
                    self.restyle(attributed, range: range, to: block, cancelCenter: true)
                }
            }
        } else {
            notifyFormatChange()
        }
        // Turning a list/to-do line into a quote drops its marker — a real
        // character — so the caret (or the selection) has to be put back on this
        // line by hand.
        keepCaretOnItsLine(caret, lineStart: lineStart, lengthBefore: lengthBefore, dropped: dropped)
        setTypingAttributes(typingAttributes(for: block), in: tv)
        carryEmptyLineAlignment(of: block, into: tv)
        syncEmptyParagraphWithTypingAttributes()
        ensureCaretGeometry()
    }

    /// Whether these attributes describe a quote paragraph.
    ///
    /// The block type is the source of truth. A non-clear `.backgroundColor` is
    /// how a quote was marked before the decoration layer existed, and imported
    /// material can still carry only that, so it keeps counting as one.
    private static func attributesAreQuote(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
        if EditorFont.blockStyle(of: attrs) == .quote { return true }
        if let bg = attrs[.backgroundColor] as? UIColor, !bg.isEqual(UIColor.clear) { return true }
        return false
    }

    func isQuoteActive() -> Bool {
        guard let tv = textView else { return false }
        if tv.textStorage.length == 0
            || Self.paragraphIsEmpty(in: tv.textStorage, location: tv.selectedRange.location) {
            return Self.attributesAreQuote(tv.typingAttributes)
        }
        let range = paragraphRange(around: tv.selectedRange)
        guard range.location < tv.textStorage.length else { return false }
        return Self.attributesAreQuote(tv.textStorage.attributes(at: range.location, effectiveRange: nil))
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

    // MARK: - The empty line the caret sits in
    //
    // An empty paragraph has no glyphs, but it does have a line box, and TextKit
    // builds that box from the paragraph's *own* terminator — the paragraph style
    // comes from the paragraph's first character, which for an empty paragraph is
    // the newline itself (`docs/editor-typography.md` §5.2). So a toggle that only
    // rewrote `typingAttributes` left the empty line — and the caret drawn inside
    // it — in the *old* style: cancelling center kept the caret in the middle,
    // turning it on kept it at the left edge, and cancelling a list item left the
    // caret one line off. Writing the new style onto the terminator fixes the line
    // without touching a single visible character, and an empty line is never
    // persisted (`PartsCodec.parts(from:)` skips it), so nothing stored changes.

    /// The empty paragraph's own terminator at `location`, when the caret sits on
    /// an empty line that has one. `nil` for a non-empty paragraph, and for the
    /// paragraph that ends the text (it has no character of its own — that one is
    /// laid out from `typingAttributes`, which is what makes it work already).
    private func emptyParagraphTerminator(in storage: NSAttributedString, at location: Int) -> NSRange? {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return nil }
        let clamped = min(max(0, location), ns.length)
        if clamped >= ns.length, ns.character(at: ns.length - 1) == 0x0A { return nil }
        let searchPos = min(clamped, ns.length - 1)
        var paraStart = searchPos, paraEnd = searchPos, contentStart = 0
        ns.getParagraphStart(&paraStart, end: &paraEnd, contentsEnd: &contentStart,
                             for: NSRange(location: searchPos, length: 0))
        guard contentStart == paraStart, paraEnd > paraStart else { return nil }
        return NSRange(location: paraStart, length: paraEnd - paraStart)
    }

    /// Writes `block`'s line style onto an empty paragraph's own terminator: the
    /// line box (size, spacing, alignment, quote background) then matches the
    /// paragraph that is about to be typed there. Only that one character is
    /// touched, so no neighbouring line moves.
    private func styleEmptyParagraph(in attributed: NSMutableAttributedString, at location: Int,
                                     to block: EditorBlockStyle, cancelCenter: Bool) {
        guard let range = emptyParagraphTerminator(in: attributed, at: location) else { return }
        let existing = (attributed.attribute(.paragraphStyle, at: range.location,
                                            effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle()
        let style = existing.mutableCopy() as! NSMutableParagraphStyle
        Self.applyBlockGeometry(to: style, block: block, cancelCenter: cancelCenter,
                                typeSize: dynamicTypeSize)
        // 行内样式（加粗 / 斜体）在这一行的重设里保留，与 `restyle` 对整行的规则一致。
        let existingFont = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
        let traits = existingFont?.fontDescriptor.symbolicTraits ?? []
        var attrs = EditorFont.attributes(block.designSize, block: block,
                                          weight: traits.contains(.traitBold) ? .bold : .regular,
                                          italic: traits.contains(.traitItalic),
                                          typeSize: dynamicTypeSize)
        attrs[.paragraphStyle] = style
        // 旧的引用底色在这里清掉（引用现在由块类型 + 装饰层画）。
        attrs[.backgroundColor] = UIColor.clear
        attributed.addAttributes(attrs, range: range)
    }

    /// Sets the alignment of an empty paragraph's own terminator — the character
    /// its line box is laid out from — keeping the rest of that line's style.
    private func setEmptyParagraphAlignment(_ alignment: NSTextAlignment,
                                           in attributed: NSMutableAttributedString, at location: Int) {
        guard let range = emptyParagraphTerminator(in: attributed, at: location) else { return }
        let existing = (attributed.attribute(.paragraphStyle, at: range.location,
                                            effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle()
        let style = existing.mutableCopy() as! NSMutableParagraphStyle
        style.alignment = alignment
        attributed.addAttribute(.paragraphStyle, value: style, range: range)
    }

    /// Copies the paragraph-level part of "the next typed character" onto the
    /// empty line the caret is on, so that line is drawn (and the caret placed)
    /// exactly where the text will be typed. Called after every toggle that can
    /// change what the caret's empty line should look like.
    ///
    /// Writing the attributes directly is deliberately cheaper than routing this
    /// through `apply`: a full-storage replacement would collapse and restore the
    /// selection on every tap, which is the very thing that used to move the
    /// caret off its line.
    @discardableResult
    private func syncEmptyParagraphWithTypingAttributes() -> Bool {
        guard let tv = textView,
              let range = emptyParagraphTerminator(in: tv.textStorage, at: tv.selectedRange.location)
        else { return false }
        let typing = tv.typingAttributes
        var attrs: [NSAttributedString.Key: Any] = [
            // Set explicitly: leaving the key out would keep an old quote
            // background on the line after the quote was cancelled.
            .backgroundColor: (typing[.backgroundColor] as? UIColor) ?? UIColor.clear
        ]
        for key in [NSAttributedString.Key.font, .diaryDesignSize, .diaryBlockStyle] {
            if let value = typing[key] { attrs[key] = value }
        }
        // 行内样式也跟上打字态（写成 0 = 关）：勾选过的待办会给这一行留下删除线，
        // 取消待办 / 换样式之后它不该继续挂在空行的换行符上。
        attrs[.strikethroughStyle] = typing[.strikethroughStyle] as? Int ?? 0
        attrs[.underlineStyle] = typing[.underlineStyle] as? Int ?? 0
        // Copy the style: `typingAttributes` can hold an object that stored text
        // also references (same note as `setTypingAlignment`).
        if let style = typing[.paragraphStyle] as? NSParagraphStyle {
            attrs[.paragraphStyle] = style.mutableCopy()
        }
        tv.textStorage.addAttributes(attrs, range: range)
        notifyFormatChange()
        return true
    }

    /// How many line-start markers this toggle is about to drop, split into the
    /// ones before the caret/selection and the ones inside it.
    ///
    /// Needed before the mutation: afterwards the markers are gone and the only
    /// thing left is a shorter string.
    private func markerDrops(in storage: NSAttributedString, ranges: [NSRange],
                             caret: NSRange) -> (before: Int, inside: Int) {
        var before = 0
        var inside = 0
        for range in ranges where Self.markerKind(in: storage, at: range.location) != nil {
            if range.location < caret.location {
                before += 1
            } else if range.location < caret.location + caret.length {
                inside += 1
            }
        }
        return (before, inside)
    }

    /// Puts the caret back on the line it was on after a style toggle dropped
    /// that line's list/to-do marker.
    ///
    /// The marker is a real character, so removing it shortens the paragraph. The
    /// generic restore in `apply` can only clamp the caret into the new text
    /// length, which on the entry's last paragraphs pushed it onto the *next*
    /// line — reported as "after tapping quote the caret is not on the line any
    /// more". Shifting by the dropped markers (and clamping to the paragraph)
    /// keeps the caret where the user left it; a selection shrinks by the markers
    /// dropped inside it instead of growing over text the user never selected.
    private func keepCaretOnItsLine(_ caret: NSRange, lineStart: Int, lengthBefore: Int,
                                    dropped: (before: Int, inside: Int) = (0, 0)) {
        guard let tv = textView else { return }
        let storage = tv.textStorage
        guard storage.length != lengthBefore || dropped.before + dropped.inside > 0 else { return }

        if caret.length > 0 {
            let location = min(max(0, caret.location - dropped.before), storage.length)
            let length = min(max(0, caret.length - dropped.inside), storage.length - location)
            tv.selectedRange = NSRange(location: location, length: length)
            return
        }
        let start = min(max(0, lineStart), storage.length)
        // An empty paragraph has no content range of its own: its terminator is as
        // far as the caret may go without leaving the line.
        let para = paragraphRange(in: storage, around: start)
        let end = para.length > 0 ? para.location + para.length : min(storage.length, start + 1)
        let target = min(max(start, caret.location - dropped.before), max(start, end))
        tv.selectedRange = NSRange(location: target, length: 0)
    }

    func activeStyles() -> (bold: Bool, italic: Bool, strike: Bool, underline: Bool) {
        guard let tv = textView else { return (false, false, false, false) }
        if tv.selectedRange.length > 0 {
            // "All of the selection", matching what a tap does to it: a mixed
            // selection reads as off and a tap turns the trait on everywhere.
            // Probing the first character instead made the button disagree with
            // its own action.
            let range = tv.selectedRange
            return (selectionHasTrait(.traitBold, in: range),
                    selectionHasTrait(.traitItalic, in: range),
                    selectionHasStyle(.strikethroughStyle, in: range),
                    selectionHasStyle(.underlineStyle, in: range))
        }
        // Empty caret: report what the next typed characters will look like.
        let typing = tv.typingAttributes
        let font = typing[.font] as? UIFont
        return (font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false,
                (typing[.strikethroughStyle] as? Int ?? 0) != 0,
                (typing[.underlineStyle] as? Int ?? 0) != 0)
    }

    /// 输入区宽度变了：记下新的正文列宽，并让图片按新宽度重排。
    ///
    /// 宽度变化以前会重跑 `loadParts`（进入编辑时的那份快照），把用户中途输入的内容
    /// 悄悄丢掉；现在只重排图片，正文与光标原地不动。首次测量不需要重排（正文还没
    /// 载入，载入时自然会用上这个宽度）。
    func handleTextWidthChange(_ width: CGFloat) {
        guard let tv = textView, width > 40 else { return }
        let inset = tv.textContainerInset
        let available = max(60, width - inset.left - inset.right)
        guard imageMaxWidth == nil || abs((imageMaxWidth ?? 0) - available) > 1 else { return }
        let measured = imageMaxWidth
        imageMaxWidth = available
        guard measured != nil else { return }
        refitImages(maxWidth: available)
    }

    func insertImage(_ image: UIImage, src: String) {
        guard let tv = textView else { return }
        // The column's full width. It was capped at a portrait phone's 343pt, so
        // a picture inserted in landscape was laid out small and left-aligned
        // (the cap belongs to the *stored* size, which is only an aspect ratio
        // and a pixel-fetch hint now).
        // 正文列的宽度 = 输入区宽度减去它自己的左右内缩（不是写死的 24：编辑区曾经
        // 自带 12pt 内缩，后来去掉了，两边必须用同一把尺子，否则插入的图片与旋转后
        // `refitImages` 重排的宽度会差一截）。
        let inset = tv.textContainerInset
        let textWidth = tv.bounds.width > 0 ? tv.bounds.width - inset.left - inset.right : 343
        let maxW = max(60, textWidth)
        let ratio = image.size.height / max(1, image.size.width)
        let displayH = max(40, maxW * ratio)
        let attachment = PayloadAttachment(payload: AttachmentPayload(src: src, w: maxW, h: displayH))
        attachment.image = DiaryImageStore.rounded(image, size: CGSize(width: maxW, height: displayH), radius: Radius.image)
        attachment.bounds = CGRect(x: 0, y: 0, width: maxW, height: displayH)
        let attributed = NSMutableAttributedString(attachment: attachment)
        // Same paragraph style the image gets when the entry is re-opened, so a
        // freshly inserted image is spaced exactly like a loaded one.
        attributed.addAttribute(.paragraphStyle, value: PartsCodec.imageParagraphStyle(),
                                range: NSRange(location: 0, length: attributed.length))
        attributed.append(NSAttributedString(string: "\n", attributes: baseTypingAttributes()))
        let insertRange = NSRange(location: tv.selectedRange.location, length: 0)
        tv.textStorage.insert(attributed, at: insertRange.location)
        tv.selectedRange = NSRange(location: insertRange.location + attributed.length, length: 0)
        // 图片下面那一段的**段前距为 0**：图片自己已经把上下留白给足，装配链路里也是
        // 这样（`appendLine(followsImage:)`）。少了这一句，刚插完图片接着打字得到的
        // 那一段会比重新打开时多出 8.5pt。
        var typing = baseTypingAttributes()
        if let style = (typing[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.paragraphSpacingBefore = 0
            typing[.paragraphStyle] = style
        }
        setTypingAttributes(typing, in: tv)
        notifyFormatChange()
    }

    func currentParts() -> [ContentPart] {
        guard let tv = textView else { return [] }
        return PartsCodec.parts(from: tv.textStorage, typeSize: dynamicTypeSize)
    }

    func load(parts: [ContentPart]) {
        guard let tv = textView else { return }
        (tv as? DiaryTextView)?.contentTypeSize = dynamicTypeSize
        tv.textStorage.setAttributedString(
            PartsCodec.attributedString(from: parts, imageMaxWidth: imageMaxWidth,
                                        typeSize: dynamicTypeSize, traits: tv.traitCollection)
        )
        tv.typingAttributes = baseTypingAttributes()
        tv.selectedRange = NSRange(location: 0, length: 0)
        // 整篇换掉了：文末空行的记忆跟着作废（键是「文档最后那个换行的位置」）。
        trailingEmptyLineStyle = nil
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
        (tv as? DiaryTextView)?.contentTypeSize = newSize
        tv.textStorage.setAttributedString(
            PartsCodec.attributedString(from: parts, imageMaxWidth: imageMaxWidth,
                                        typeSize: newSize, traits: tv.traitCollection)
        )
        tv.typingAttributes = baseTypingAttributes()
        tv.selectedRange = NSRange(location: min(caret.location, tv.textStorage.length), length: 0)
        notifyFormatChange()
    }

    func clear() {
        guard let tv = textView else { return }
        tv.textStorage.setAttributedString(NSAttributedString())
        tv.typingAttributes = baseTypingAttributes()
        trailingEmptyLineStyle = nil
        notifyFormatChange()
    }

    /// Re-fits the images already in the text to a new content width, leaving
    /// the text and the caret untouched.
    ///
    /// The width changes when the device rotates. Reloading the editor's
    /// original parts here — which is what the view used to do — threw away
    /// every edit made since the editor opened, because those parts are the
    /// snapshot from when it opened.
    func refitImages(maxWidth: CGFloat) {
        guard let tv = textView else { return }
        let storage = tv.textStorage
        guard storage.length > 0, maxWidth > 0 else { return }
        let selection = tv.selectedRange
        var refits: [(PayloadAttachment, NSRange)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? PayloadAttachment,
                  attachment.payload.kind == "image" else { return }
            refits.append((attachment, range))
        }
        guard !refits.isEmpty else { return }
        for (attachment, range) in refits {
            let storedW = max(1, CGFloat(attachment.payload.w))
            let storedH = max(1, CGFloat(attachment.payload.h))
            // Same rule as the codec: the column decides the width, the stored
            // pair only the aspect ratio. Leaving `min(storedW, maxWidth)` here
            // meant a rotation re-fitted every image back to its stored width.
            let w = max(60, maxWidth)
            let h = storedH * w / storedW
            if let image = DiaryImageStore.shared.image(for: attachment.payload.src,
                                                        maxPixel: max(storedW, storedH) * 3) {
                attachment.image = DiaryImageStore.shared.rounded(for: attachment.payload.src, image: image,
                                                                   size: CGSize(width: w, height: h),
                                                                   radius: Radius.image)
            }
            attachment.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            // Re-adding the attribute is what makes the layout manager pick the
            // new bounds up.
            storage.addAttribute(.attachment, value: attachment, range: range)
        }
        tv.selectedRange = selection
        notifyFormatChange()
    }

    /// 光标（选区末端）在窗口坐标里的矩形；不在编辑状态时为 nil。
    func caretRectInWindow() -> CGRect? {
        guard let tv = textView, tv.isFirstResponder else { return nil }
        let caret = tv.caretRect(for: tv.selectedTextRange?.end ?? tv.endOfDocument)
        // `isNull` / `isInfinite` 都**不覆盖 NaN**：TextKit 在布局还没就绪时算出来的
        // 光标矩形可能是 NaN，`Int(NaN)` 会直接崩（`Double value cannot be converted
        // to Int`，2026-09-26 12:27 那次崩溃就是这里漏出来的），而 `convert(_:to:)`
        // 也会把 NaN 传下去污染键盘避让的算术。四个分量都要查。
        guard !caret.isNull, !caret.isInfinite,
              caret.origin.x.isFinite, caret.origin.y.isFinite,
              caret.size.width.isFinite, caret.size.height.isFinite else { return nil }
        let inWindow = tv.convert(caret, to: nil)
        guard inWindow.origin.x.isFinite, inWindow.origin.y.isFinite,
              inWindow.size.width.isFinite, inWindow.size.height.isFinite else { return nil }
        return inWindow
    }

    /// 把光标滚进「可见区」：底部让开 `obscuredBottom`（键盘 + 浮在键盘上方的格式栏），
    /// 顶部让开 `topInset`（悬浮顶栏）。
    ///
    /// 键盘弹起时页面不再把整张卡片 `scrollTo(anchor: .center)` —— 那个视口是整屏，
    /// 横屏（SE 横屏可用高度只有 198pt）卡片下半张连光标一起被键盘盖住，用户得先上滑
    /// 才看得到自己在输入什么。这里直接滚承载编辑器的 `UIScrollView`（就是 SwiftUI 的
    /// ScrollView），按光标的实际位置算偏移，不动 SwiftUI 的滚动绑定。
    /// 第一个图片附件在正文里的尺寸；没有图片时返回 nil（UI 测试用它断言图片宽度）。
    func firstImageSize() -> CGSize? {
        guard let tv = textView, tv.textStorage.length > 0 else { return nil }
        var size: CGSize?
        tv.textStorage.enumerateAttribute(.attachment,
                                          in: NSRange(location: 0, length: tv.textStorage.length)) { value, _, stop in
            guard let attachment = value as? PayloadAttachment,
                  attachment.payload.kind == "image" else { return }
            size = attachment.bounds.size
            stop.pointee = true
        }
        return size
    }

    func isEmpty() -> Bool {
        guard let tv = textView else { return true }
        return tv.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func apply(_ block: (NSMutableAttributedString) -> Void) {
        guard let tv = textView else { return }
        let text = tv.textStorage
        let selection = tv.selectedRange
        let attributed = NSMutableAttributedString(attributedString: text)
        block(attributed)
        text.replaceCharacters(in: NSRange(location: 0, length: text.length), with: attributed)
        // Rewriting the whole storage makes UIKit collapse the selection to the
        // end of the edit, which silently dropped a selection the user had just
        // made. Put it back, clamped to the new length; toggles that changed the
        // length (a marker added or dropped) adjust the caret themselves after
        // calling this.
        let length = text.length
        let location = min(selection.location, length)
        tv.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
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
    /// the user had enlarged.
    ///
    /// The attachment is a transparent canvas whose **width is the item's
    /// hanging indent** and whose glyph sits at its left edge (see
    /// `MarkerGlyph`). That single trick gives the marker its gap to the text
    /// without inserting a tab character — the marker stays one character, so
    /// every caret/selection offset in the editor keeps its meaning.
    static func attachment(kind: String, done: Bool = false,
                           typeSize: DynamicTypeSize = .large,
                           traits: UITraitCollection = .current) -> PayloadAttachment {
        let attachment = PayloadAttachment(payload: AttachmentPayload(kind: kind, done: done))
        let font = EditorFont.font(EditorDesignSize.body, typeSize: typeSize)
        attachment.image = MarkerGlyph.image(kind: kind, done: done, typeSize: typeSize, traits: traits)
        attachment.bounds = MarkerGlyph.bounds(kind: kind, font: font, typeSize: typeSize)
        return attachment
    }

    /// A marker as the string that goes into the text storage.
    ///
    /// The marker is the line's **first** character, and TextKit takes a
    /// paragraph's style from that character — a bare marker made the whole item
    /// fall back to the default paragraph style, silently dropping the body line
    /// spacing (measured under the old model: a wrapped list line advanced
    /// 20.29pt instead of the body's 22.5pt — today the body adds 5.219pt of
    /// `lineSpacing`). So the marker carries the line's paragraph style;
    /// its size still comes from the attachment's own bounds, not from a font.
    static func attributed(kind: String, done: Bool = false,
                           typeSize: DynamicTypeSize = .large,
                           traits: UITraitCollection = .current,
                           paragraphStyle: NSParagraphStyle?) -> NSAttributedString {
        let string = NSMutableAttributedString(attachment: attachment(kind: kind, done: done,
                                                                     typeSize: typeSize,
                                                                     traits: traits))
        if let paragraphStyle {
            string.addAttribute(.paragraphStyle, value: paragraphStyle,
                                range: NSRange(location: 0, length: string.length))
        }
        return string
    }
}

enum PartsCodec {
    static func attributedString(from parts: [ContentPart], imageMaxWidth: CGFloat? = nil,
                                 typeSize: DynamicTypeSize = .large,
                                 traits: UITraitCollection = .current) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var previousWasImage = false
        for part in parts {
            defer { previousWasImage = part.style == ContentPartStyle.image }
            switch part.style {
            case ContentPartStyle.list:
                for item in part.items ?? [] {
                    appendMarkerLine(kind: "bullet", done: false, text: item, to: result,
                                     typeSize: typeSize, traits: traits)
                }
            case ContentPartStyle.todo:
                let items = part.items ?? []
                let done = part.done ?? Array(repeating: false, count: items.count)
                for (i, item) in items.enumerated() {
                    appendMarkerLine(kind: "todo", done: done.indices.contains(i) && done[i],
                                     text: item, to: result, typeSize: typeSize, traits: traits)
                }
            case ContentPartStyle.image:
                if let src = part.src {
                    let storedW = max(1, CGFloat(part.w ?? 300))
                    let storedH = max(1, CGFloat(part.h ?? 200))
                    let fallbackW = max(60, Screen.width - 76)
                    let maxW = max(60, imageMaxWidth ?? fallbackW)
                    // Fill the column. The stored pair only carries the aspect
                    // ratio from here on: a picture authored on a phone used to
                    // keep its portrait width in landscape (a small picture in a
                    // wide column, left-aligned), and the reader sized its
                    // aspect box from the column while drawing the picture at
                    // the stored width, which is where the phantom bands above
                    // and below it came from.
                    let w = maxW
                    let h = storedH * w / storedW
                    let attachment = PayloadAttachment(payload: AttachmentPayload(src: src, w: storedW, h: storedH))
                    if let image = DiaryImageStore.shared.image(for: src, maxPixel: max(storedW, storedH) * 3) {
                        attachment.image = DiaryImageStore.shared.rounded(for: src, image: image,
                                                                       size: CGSize(width: w, height: h),
                                                                       radius: Radius.image)
                    }
                    attachment.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                    let att = NSMutableAttributedString(attachment: attachment)
                    // The paragraph style rides on the attachment itself: the
                    // terminating newline stays plain, so the paragraph *after*
                    // an image is not born with the image's spacing, while the
                    // image line still gets the space above and below it.
                    att.addAttribute(.paragraphStyle, value: imageParagraphStyle(),
                                     range: NSRange(location: 0, length: att.length))
                    result.append(att)
                    result.append(NSAttributedString(string: "\n"))
                }
            default:
                appendLine(part, to: result, block: EditorBlockStyle(partStyle: part.style),
                           typeSize: typeSize, followsImage: previousWasImage)
            }
        }
        return result
    }

    /// The paragraph an image sits in: centred, with the same breathing room
    /// above and below, so an image is never glued to the text around it and
    /// never hangs off the left edge of a wide column.
    static func imageParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        // 目标是**肉眼**上下一样多（`imageTopSlack` / `imageBottomSlack` 见上）。
        // 图片后面那一段的段前距会被 `appendLine` 归零（`followsImage`：图片自己已经
        // 把间距给足了，读模式里那一段本来就是新的一块、段前距同样不生效），所以下面
        // 只需要扣掉字体几何那一份。
        style.paragraphSpacingBefore = max(0, EditorDesignSize.imageSpacing - EditorDesignSize.imageTopSlack)
        style.paragraphSpacing = max(0, EditorDesignSize.imageSpacing - EditorDesignSize.imageBottomSlack)
        return style
    }

    /// One read-mode chunk: what `attributedString(from:)` produces, minus the
    /// two things the reader's chunked layout must not carry.
    ///
    /// * **The trailing paragraph break.** A read chunk is its own `UITextView`,
    ///   and `sizeThatFits` reserves a whole empty caret line for the break after
    ///   the last paragraph — about 20pt of blank space at the end of every
    ///   chunk, which showed up as an unexplained gap before images and before
    ///   the card's bottom edge.
    /// * **The image paragraph's spacing.** An image is a chunk of its own and
    ///   `DiaryPartsView` pads it by the same amount, so keeping the paragraph
    ///   spacing would count that gap twice.
    ///
    /// Text paragraphs keep their own spacing: inside a chunk the reader and the
    /// editor lay text out with exactly the same paragraph styles.
    static func readerChunk(from parts: [ContentPart], imageMaxWidth: CGFloat? = nil,
                            typeSize: DynamicTypeSize = .large,
                            traits: UITraitCollection = .current) -> NSAttributedString {
        let attributed = NSMutableAttributedString(attributedString: attributedString(from: parts,
                                                                                     imageMaxWidth: imageMaxWidth,
                                                                                     typeSize: typeSize,
                                                                                     traits: traits))
        if attributed.string.hasSuffix("\n") {
            attributed.deleteCharacters(in: NSRange(location: attributed.length - 1, length: 1))
        }
        let isImageChunk = parts.count == 1 && parts.first?.style == ContentPartStyle.image
        if isImageChunk, attributed.length > 0 {
            attributed.removeAttribute(.paragraphStyle,
                                       range: NSRange(location: 0, length: attributed.length))
        }
        return attributed
    }

    /// The paragraph style of a block: line spacing, the gaps around it, and —
    /// for a quote — the indent its left bar needs.
    ///
    /// Shared by both chains on purpose. The editor's live mutations
    /// (`RichEditorController.restyle`, `typingAttributes`, the empty-line
    /// helpers) and this codec must agree, or the same paragraph is drawn one
    /// way while it is being typed and another way once the entry is reopened.
    static func paragraphStyle(_ block: EditorBlockStyle, center: Bool = false,
                               typeSize: DynamicTypeSize = .large) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = center ? .center : .left
        style.lineSpacing = block.lineSpacing
        style.paragraphSpacing = block.paragraphSpacing
        style.paragraphSpacingBefore = block.paragraphSpacingBefore
        if block == .quote {
            let inset = BlockMetrics.quoteTextInset(typeSize)
            style.firstLineHeadIndent = inset
            style.headIndent = inset
        }
        return style
    }

    /// The paragraph style of a list / to-do item: body attributes plus the
    /// hanging indent the marker's canvas reserves, so a wrapped line starts
    /// under the first one's text instead of under the bullet.
    static func markerParagraphStyle(typeSize: DynamicTypeSize = .large,
                                     kind: String = "bullet") -> NSMutableParagraphStyle {
        let style = paragraphStyle(.body, typeSize: typeSize)
        style.firstLineHeadIndent = 0
        style.headIndent = BlockMetrics.markerIndent(kind: kind, typeSize)
        // 列表 / 待办项之间用更小的间距：同一个列表的几项是一组，挨紧一点才像一组，
        // 但也不能贴死（每一项都是可以点的）。
        let scale = BlockMetrics.scale(typeSize)
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = EditorDesignSize.markerSpacing * scale
        return style
    }

    private static func appendMarkerLine(kind: String, done: Bool, text: String,
                                         to result: NSMutableAttributedString,
                                         typeSize: DynamicTypeSize,
                                         traits: UITraitCollection) {
        let block = EditorBlockStyle.body
        let style = markerParagraphStyle(typeSize: typeSize, kind: kind)
        var attrs = EditorFont.attributes(block.designSize, block: block, typeSize: typeSize)
        attrs[.foregroundColor] = Theme.onSurfaceUIColor()
        attrs[.paragraphStyle] = style
        if kind == "todo", done {
            attrs[.strikethroughStyle] = 1
            attrs[.foregroundColor] = Theme.onSurfaceUIColor().withAlphaComponent(0.45)
        }
        result.append(MarkerAttachment.attributed(kind: kind, done: done, typeSize: typeSize,
                                                  traits: traits, paragraphStyle: style))
        result.append(NSAttributedString(string: text, attributes: attrs))
        result.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    private static func appendLine(_ part: ContentPart, to result: NSMutableAttributedString,
                                   block: EditorBlockStyle, typeSize: DynamicTypeSize,
                                   followsImage: Bool = false) {
        let runs = part.runs ?? []
        let center = part.align == "center"
        if runs.isEmpty, let text = part.text {
            appendLine([TextRun(text: text)], to: result, block: block, center: center,
                       typeSize: typeSize, followsImage: followsImage)
        } else {
            appendLine(runs, to: result, block: block, center: center,
                       typeSize: typeSize, followsImage: followsImage)
        }
    }

    private static func appendLine(_ runs: [TextRun], to result: NSMutableAttributedString,
                                   block: EditorBlockStyle, center: Bool = false,
                                   typeSize: DynamicTypeSize,
                                   followsImage: Bool = false) {
        let line = NSMutableAttributedString()
        let style = paragraphStyle(block, center: center, typeSize: typeSize)
        // 紧跟在图片后面的那一段不再加自己的段前距：图片自己已经把上下留白给足了，
        // 而且读模式里这一段本来就是新的一块 —— TextKit 会丢掉块首段的段前距。
        // 不归零的话，编辑区里图片下面会多出 8.5pt，两个模式对不上。
        if followsImage { style.paragraphSpacingBefore = 0 }
        for run in runs {
            // The size comes from the block, never from the run: a paragraph has
            // one style and that style owns its point size.
            var attrs = EditorFont.attributes(block.designSize, block: block,
                                              weight: run.bold == true ? .bold : .regular,
                                              italic: run.italic == true,
                                              typeSize: typeSize)
            attrs[.foregroundColor] = Theme.onSurfaceUIColor()
            attrs[.paragraphStyle] = style
            if run.strike == true { attrs[.strikethroughStyle] = 1 }
            if run.underline == true { attrs[.underlineStyle] = 1 }
            // A quote's background is *not* a `.backgroundColor` attribute any
            // more: that only ever covered the glyphs (ragged right edge, no
            // padding, no bar). `DiaryTextView` draws the block behind the text
            // instead, in both the editor and the reader.
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
                // A marker with nothing after it is a line the user is still on
                // — a just-added marker, or the empty item left by Return — not
                // an item yet, so it is not written to storage.
                if rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
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
                    parts.append(ContentPart(style: ContentPartStyle.image,
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
                // Only the traits that are actually on are written: a stored
                // `"bold": false` is noise, and `nil` is what "not styled" means
                // everywhere else in the format.
                let bold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
                let italic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true
                let strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
                let underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
                // No font size is persisted: it belongs to the block's style, and
                // a stored size could only describe a size the editor cannot
                // author or edit. The drawn size is deliberately *not* read here
                // — it grows with the user's text-size setting.
                runs.append(TextRun(text: sub,
                                    bold: bold ? true : nil,
                                    italic: italic ? true : nil,
                                    strike: strike ? true : nil,
                                    underline: underline ? true : nil))
                cursor = effectiveEnd
            }
            if runs.isEmpty { continue }
            parts.append(ContentPart(style: block.partStyle, runs: runs, align: align))
        }
        return parts
    }

    private static func appendList(parts: inout [ContentPart], item: String, done: Bool?) {
        if let last = parts.last, last.style == ContentPartStyle.todo, done != nil {
            var items = last.items ?? []
            items.append(item)
            var newDone = last.done ?? []
            newDone.append(done!)
            parts[parts.count - 1] = ContentPart(style: last.style, items: items, done: newDone)
        } else if let last = parts.last, last.style == ContentPartStyle.list, done == nil {
            var items = last.items ?? []
            items.append(item)
            parts[parts.count - 1] = ContentPart(style: last.style, items: items)
        } else {
            let type = done == nil ? ContentPartStyle.list : ContentPartStyle.todo
            parts.append(ContentPart(style: type, items: [item], done: done.map { [$0] }))
        }
    }
}
