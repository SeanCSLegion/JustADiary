import SwiftUI
import UIKit

// MARK: - 列表 / 待办 / 引用的统一几何
//
// 这三种块在**编辑态和阅读态必须是同一张脸**。两条链路（`PartsCodec` 装配、
// `RichEditorController` 实时输入）本来就共用属性字符串，但「标记长什么样」「引用
// 的底色画到哪」这些几何原先散在各自的代码里：
//
// * 列表 / 待办的标记是一个 15×15 的附件，紧贴正文，没有悬挂缩进 —— 换行后第二行
//   顶到标记底下；
// * 引用只有一段 `.backgroundColor`：底色**只跟着字走**，行尾参差、没有内边距、
//   没有左侧竖条，看起来像荧光笔而不是引用块。
//
// 现在几何集中在这里：附件画布、悬挂缩进的数值、引用块的圆角与竖条，两边都从这里取。
// 数值按正文（17pt）设计，再乘动态字号系数，所以跟着系统文字大小一起长。
enum BlockMetrics {
    /// 正文在当前字号档位下的缩放系数（默认档位为 1）。
    static func scale(_ typeSize: DynamicTypeSize) -> CGFloat {
        DynamicTypeMetrics.multiplier(for: EditorDesignSize.body, typeSize: typeSize)
    }

    /// 正文实际画出来的磅值。
    static func drawnBodySize(_ typeSize: DynamicTypeSize) -> CGFloat {
        DynamicTypeMetrics.scaled(EditorDesignSize.body, for: typeSize)
    }

    // MARK: 引用

    /// 引用正文距**列左边界**的缩进（左竖条在里面）。
    static func quoteTextInset(_ typeSize: DynamicTypeSize) -> CGFloat { 16 * scale(typeSize) }
    /// 左侧竖条距列左边界的距离。
    static func quoteBarLeading(_ typeSize: DynamicTypeSize) -> CGFloat { 6 * scale(typeSize) }
    static func quoteBarWidth(_ typeSize: DynamicTypeSize) -> CGFloat { 3 * scale(typeSize) }
    /// 竖条上下各让出多少（免得它顶到圆角外面）。
    static func quoteBarInset(_ typeSize: DynamicTypeSize) -> CGFloat { 5 * scale(typeSize) }
    /// 底色块在文字行盒之外上下各多出来多少（引用的「内边距」）。
    static func quotePadding(_ typeSize: DynamicTypeSize) -> CGFloat { 6 * scale(typeSize) }
    static func quoteCornerRadius(_ typeSize: DynamicTypeSize) -> CGFloat { 9 * scale(typeSize) }
    static func quoteBarRadius(_ typeSize: DynamicTypeSize) -> CGFloat { 1.5 * scale(typeSize) }

    // MARK: 列表 / 待办标记

    /// 标记占的宽度，也就是正文（含换行后的每一行）的左缩进。
    static func markerIndent(kind: String, _ typeSize: DynamicTypeSize) -> CGFloat {
        (kind == "todo" ? 26 : 18) * scale(typeSize)
    }

    /// 标记图形自身的尺寸：圆点直径 / 复选框边长。
    static func markerSize(kind: String, _ typeSize: DynamicTypeSize) -> CGFloat {
        (kind == "todo" ? 16 : 6.5) * scale(typeSize)
    }

    /// 标记图形的横向中心（距列左边界）。
    static func markerCenterX(kind: String, _ typeSize: DynamicTypeSize) -> CGFloat {
        (kind == "todo" ? 9 : 5.5) * scale(typeSize)
    }

    /// 标记中心距**基线**的高度。
    ///
    /// 0.32 是 CJK 与西文都能接受的那个位置：汉字字面中心约在 0.36em，西文 x-height
    /// 中心约在 0.26em（实测这一版与改造前复选框的落点一致，只是换成了精确的基线换算）。
    static func markerCenterAboveBaseline(_ typeSize: DynamicTypeSize) -> CGFloat {
        drawnBodySize(typeSize) * 0.32
    }

    /// 显示缩放的兜底值。
    ///
    /// `UIScreen.main` 在 iOS 26 起已废弃（官方给的替代就是「用上下文里的 trait」），
    /// 而 trait 里的 `displayScale` 只有在视图挂进窗口后才有值 —— 那之前用当前环境的
    /// 首选格式缩放顶上。第一次布局后 `DiaryTextView` 会用 trait 里的真值再设一次。
    static let fallbackDisplayScale: CGFloat = UIGraphicsImageRendererFormat.preferred().scale

    /// 一个 trait 环境下的显示缩放（拿不到就用兜底）。
    static func displayScale(of traits: UITraitCollection) -> CGFloat {
        traits.displayScale > 0 ? traits.displayScale : fallbackDisplayScale
    }

    // MARK: 正文输入区

    /// 正文文本视图的内缩：阅读态的每个正文块和编辑态的输入区**共用**这一个值。
    ///
    /// 以前阅读态是 2pt、编辑态是 10pt（上下各差 8pt），进出编辑时正文的上下边界会跳，
    /// 「编辑的时候看到和阅读模式一样的效果」也就无从谈起。
    static let textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
}

// MARK: - 标记图形

/// 列表圆点 / 待办复选框，画成一张透明画布图片。
///
/// 画布的**宽度就是这一行的左缩进**，图形画在画布左侧 —— 于是标记本身自带与正文的
/// 间距，不需要在标记后插一个制表符（标记仍是一个字符，编辑器里所有「标记 = 行首
/// 一个附件」的光标 / 选区算术都不用改）。
///
/// 颜色在**这一刻**按传入的 trait 解析并烤进像素里，所以换成深色外观要重画
/// （`DiaryTextView.refreshMarkerGlyphs()`）。
enum MarkerGlyph {
    static func image(kind: String, done: Bool, typeSize: DynamicTypeSize,
                      traits: UITraitCollection) -> UIImage {
        let font = EditorFont.font(EditorDesignSize.body, typeSize: typeSize)
        let canvas = canvasSize(kind: kind, font: font, typeSize: typeSize)
        let centerY = font.ascender - BlockMetrics.markerCenterAboveBaseline(typeSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = BlockMetrics.displayScale(of: traits)
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            if kind == "todo" {
                drawCheckbox(done: done, centerY: centerY, typeSize: typeSize,
                             traits: traits, into: context)
            } else {
                drawBullet(centerY: centerY, typeSize: typeSize, traits: traits, into: context)
            }
        }
    }

    /// 画布尺寸：宽 = 标记缩进，高 = 字体的 ascent + descent。
    ///
    /// 高度**刻意精确取** ascent + descent（不含行距，也不向上取整）：它正好落在这一行
    /// 的 ascent/descent 之内，行高于是完全由字体决定 —— 带标记的行和正文行的行距一致
    /// （`EditorSpacingTests.testMarkerLinesWrapWithTheBodyLineSpacing` 量到 0.01pt）。
    /// 取整过一次，行高会多出最多 1pt，折行推进就跟正文对不上了。
    static func canvasSize(kind: String, font: UIFont, typeSize: DynamicTypeSize) -> CGSize {
        CGSize(width: BlockMetrics.markerIndent(kind: kind, typeSize),
               height: font.ascender - font.descender)
    }

    /// 附件相对基线的位置：画布下沿落在 descent 上，上沿正好落在 ascent 上。
    static func bounds(kind: String, font: UIFont, typeSize: DynamicTypeSize) -> CGRect {
        let size = canvasSize(kind: kind, font: font, typeSize: typeSize)
        return CGRect(x: 0, y: font.descender, width: size.width, height: size.height)
    }

    private static func drawBullet(centerY: CGFloat, typeSize: DynamicTypeSize,
                                   traits: UITraitCollection, into context: UIGraphicsImageRendererContext) {
        let diameter = BlockMetrics.markerSize(kind: "bullet", typeSize)
        let radius = diameter / 2
        let centerX = BlockMetrics.markerCenterX(kind: "bullet", typeSize)
        let color = Theme.onSurfaceVariantUIColor().resolvedColor(with: traits)
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: centerX - radius, y: centerY - radius,
                                    width: diameter, height: diameter)).fill()
    }

    private static func drawCheckbox(done: Bool, centerY: CGFloat, typeSize: DynamicTypeSize,
                                     traits: UITraitCollection,
                                     into context: UIGraphicsImageRendererContext) {
        let side = BlockMetrics.markerSize(kind: "todo", typeSize)
        let centerX = BlockMetrics.markerCenterX(kind: "todo", typeSize)
        let box = CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
        // 描边画在框内侧，于是勾选框的外沿与圆点一样落在同一个「标记框」里。
        let lineWidth = max(1.2, (side * 0.075).rounded())
        let radius = (side * 0.28).rounded()
        let path = UIBezierPath(roundedRect: box.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                                cornerRadius: radius)
        if done {
            Theme.primaryUIColor().resolvedColor(with: traits).setFill()
            path.fill()
            drawCheckmark(in: box, lineWidth: max(1.6, side * 0.13), traits: traits)
        } else {
            let border = Theme.onSurfaceVariantUIColor().resolvedColor(with: traits)
            border.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        }
    }

    /// 已完成的勾：一条折线，圆头圆角。
    private static func drawCheckmark(in box: CGRect, lineWidth: CGFloat, traits: UITraitCollection) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: box.minX + box.width * 0.24, y: box.minY + box.height * 0.52))
        path.addLine(to: CGPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * 0.70))
        path.addLine(to: CGPoint(x: box.minX + box.width * 0.77, y: box.minY + box.height * 0.31))
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        UIColor.white.setStroke()
        path.stroke()
    }
}

// MARK: - 引用块的底色与竖条

/// 引用段落的底色与左侧竖条。
///
/// 画在文本视图**自己的 layer 里、所有子层的最下面**，所以它在文字后面，跟着内容一起
/// 滚动。之所以不用 `.backgroundColor` 属性：那个底色只覆盖有字的地方 —— 行尾参差、
/// 没有内边距、也没有竖条。
final class BlockDecorationLayer: CALayer {
    struct QuoteBlock: Equatable {
        /// 底色块（已经含上下内边距、横跨整个正文列）。
        var frame: CGRect
        /// 左侧竖条。
        var bar: CGRect
    }

    var quotes: [QuoteBlock] = [] {
        didSet { if quotes != oldValue { setNeedsDisplay() } }
    }
    // 每个 setter 都先比一次：这些值每次布局都会被重新算一遍并赋回来，无脑
    // `setNeedsDisplay()` 会让图层在**每一帧**都重画（滚动时最明显）。
    var blockColor: UIColor = .clear {
        didSet { if !blockColor.isEqual(oldValue) { setNeedsDisplay() } }
    }
    var barColor: UIColor = .clear {
        didSet { if !barColor.isEqual(oldValue) { setNeedsDisplay() } }
    }
    var blockRadius: CGFloat = 9 {
        didSet { if blockRadius != oldValue { setNeedsDisplay() } }
    }
    var barRadius: CGFloat = 1.5 {
        didSet { if barRadius != oldValue { setNeedsDisplay() } }
    }

    override func draw(in ctx: CGContext) {
        guard !quotes.isEmpty else { return }
        ctx.setFillColor(blockColor.cgColor)
        for quote in quotes {
            ctx.addPath(CGPath(roundedRect: quote.frame, cornerWidth: blockRadius,
                               cornerHeight: blockRadius, transform: nil))
            ctx.fillPath()
        }
        ctx.setFillColor(barColor.cgColor)
        for quote in quotes {
            ctx.addPath(CGPath(roundedRect: quote.bar, cornerWidth: barRadius,
                               cornerHeight: barRadius, transform: nil))
            ctx.fillPath()
        }
    }
}

// MARK: - 带块级装饰的文本视图

/// `UITextView` + 引用块装饰，编辑区和阅读区的文本视图都从这里派生。
///
/// 阅读态的每个正文块、编辑态的整篇文档都各是一个 `UITextView`，装饰挂在文本视图自己
/// 身上（而不是 SwiftUI 那一层），两条链路才可能画出**逐像素相同**的引用块。
class DiaryTextView: UITextView {
    /// 引用装饰层（internal：单元测试要读它算出来的块几何）。
    let blockDecorations = BlockDecorationLayer()

    /// 当前正文是按哪个字号档位排的 —— 引用的圆角、内边距和标记图形都要按它换算。
    var contentTypeSize: DynamicTypeSize = .large {
        didSet { if contentTypeSize != oldValue { refreshBlockDecorations() } }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        installDecorations()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installDecorations()
    }

    private func installDecorations() {
        blockDecorations.contentsScale = displayScale
        // 插在最底下：文本是后面的子层画的，装饰在文字后面。
        layer.insertSublayer(blockDecorations, at: 0)
        // 深浅色一换，引用块的图层颜色与标记图形的位图都要重画 —— 它们都是按当时的
        // 颜色算好 / 烤好的，动态色不会自己跟过来。
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: DiaryTextView, _) in
            view.blockDecorations.contentsScale = view.displayScale
            view.refreshBlockDecorations()
            view.refreshMarkerGlyphs(typeSize: view.contentTypeSize)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshBlockDecorations()
    }

    private var displayScale: CGFloat { BlockMetrics.displayScale(of: traitCollection) }

    /// 就地重画正文里所有列表 / 待办标记的图形；尺寸不变，所以不会挪动任何一行。
    func refreshMarkerGlyphs(typeSize: DynamicTypeSize) {
        let length = textStorage.length
        guard length > 0 else { return }
        var markers: [(PayloadAttachment, NSRange, String, Bool)] = []
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard let attachment = value as? PayloadAttachment,
                  attachment.payload.kind == "bullet" || attachment.payload.kind == "todo" else { return }
            markers.append((attachment, range, attachment.payload.kind, attachment.payload.done))
        }
        guard !markers.isEmpty else { return }
        let traits = traitCollection
        let font = EditorFont.font(EditorDesignSize.body, typeSize: typeSize)
        for (attachment, range, kind, done) in markers {
            attachment.image = MarkerGlyph.image(kind: kind, done: done, typeSize: typeSize, traits: traits)
            attachment.bounds = MarkerGlyph.bounds(kind: kind, font: font, typeSize: typeSize)
            textStorage.addAttribute(.attachment, value: attachment, range: range)
        }
    }

    /// 重画引用块。文本、宽度、字号档位或外观一变就调一次；只读布局，不改文本。
    func refreshBlockDecorations() {
        let typeSize = contentTypeSize
        blockDecorations.contentsScale = displayScale
        // 装饰层是**子层**，不是子视图：`UITextView` 可以随时把自己的文本层插到
        // 前面，所以每次布局都把它按回最底下（不是最底下时那一次插入才会真的动）。
        if let first = layer.sublayers?.first, first !== blockDecorations {
            layer.insertSublayer(blockDecorations, at: 0)
        }
        blockDecorations.blockColor = Theme.quoteBgUIColor().resolvedColor(with: traitCollection)
        blockDecorations.barColor = Theme.primaryUIColor().withAlphaComponent(0.75).resolvedColor(with: traitCollection)
        blockDecorations.blockRadius = BlockMetrics.quoteCornerRadius(typeSize)
        blockDecorations.barRadius = BlockMetrics.quoteBarRadius(typeSize)
        let quotes = quoteBlocks()
        // 图层默认尺寸是 0，尺寸不对就什么都画不出来。
        var covered = bounds
        for quote in quotes { covered = covered.union(quote.frame) }
        let target = CGRect(x: 0, y: 0,
                            width: max(1, max(bounds.width, covered.maxX)),
                            height: max(1, max(bounds.height, covered.maxY)))
        if blockDecorations.frame != target { blockDecorations.frame = target }
        blockDecorations.quotes = quotes
    }

    /// 把当前文本里所有引用段落换算成底色块 + 竖条（文本视图坐标）。
    private func quoteBlocks() -> [BlockDecorationLayer.QuoteBlock] {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return [] }
        let inset = textContainerInset
        let padding = BlockMetrics.quotePadding(contentTypeSize)
        let barLeading = BlockMetrics.quoteBarLeading(contentTypeSize)
        let barWidth = BlockMetrics.quoteBarWidth(contentTypeSize)
        let barInset = BlockMetrics.quoteBarInset(contentTypeSize)
        // 底色块横跨整个正文列（列宽由文本视图的宽度和内缩决定）。
        let columnWidth = bounds.width - inset.left - inset.right
        guard columnWidth > 40 else { return [] }
        // 一段的排版框（文本容器坐标）→ 底色块 + 竖条（文本视图坐标）。
        func block(for textFrame: CGRect) -> BlockDecorationLayer.QuoteBlock {
            let padded = textFrame.insetBy(dx: 0, dy: -padding)
            let frame = CGRect(x: inset.left,
                               y: padded.minY + inset.top,
                               width: columnWidth,
                               height: padded.height)
            let bar = CGRect(x: inset.left + barLeading,
                             y: frame.minY + barInset,
                             width: barWidth,
                             height: max(0, frame.height - barInset * 2))
            return BlockDecorationLayer.QuoteBlock(frame: frame, bar: bar)
        }
        let ns = textStorage.string as NSString
        var blocks: [BlockDecorationLayer.QuoteBlock] = []
        var lineStart = 0
        while lineStart < ns.length {
            var lineEnd = lineStart
            while lineEnd < ns.length && ns.character(at: lineEnd) != 0x0A { lineEnd += 1 }
            let contentLength = lineEnd - lineStart
            // 空引用行也算：它的样式在**自己的换行符**上（编辑区里刚按下引用按钮的
            // 那一行就是这种），换行符就是 `lineStart` 处的那个字符。
            let paragraphLength = lineEnd < ns.length ? contentLength + 1 : contentLength
            if paragraphLength > 0, isQuoteParagraph(at: lineStart),
               let textFrame = textFrame(layoutManager: layoutManager,
                                         contentManager: contentManager,
                                         location: lineStart, length: paragraphLength) {
                blocks.append(block(for: textFrame))
            }
            lineStart = lineEnd + 1
        }
        // 文档末尾那条**空行**没有自己的字符（文档以换行结尾，或者整个文档为空），上面的
        // 循环走不到它 —— 它的行盒由打字态排出来（B22 的同一件事）。只有光标正停在它上面
        // 时才画：那时它算不算引用才有确定含义。「点完引用还没输入」看到的就是这一行，
        // 而回车续出来的空引用行也是它 —— 少了这块底色，用户看到的就只是「一行缩进」。
        let caret = selectedRange
        if caret.length == 0, caret.location >= ns.length,
           ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A,
           EditorFont.blockStyle(of: typingAttributes) == .quote,
           let textFrame = trailingEmptyLineFrame(layoutManager: layoutManager,
                                                  contentManager: contentManager) {
            blocks.append(block(for: textFrame))
        }
        return blocks
    }

    /// 文档末尾那条空行的行框（文本容器坐标）。
    ///
    /// 它没有自己的字符，TextKit 也就不给它独立的排版片段：它的行盒挂在**贴着文末**那个
    /// 片段的 extra line fragment 上（`characterRange` 为空的那一条）。从文末**反向**
    /// 枚举取第一个片段即可，不用把整篇排一遍。
    ///
    /// 空文档连片段都没有 —— 那一行就在文本容器顶端，高度取这一档字号的引用行高。
    private func trailingEmptyLineFrame(layoutManager: NSTextLayoutManager,
                                        contentManager: NSTextContentManager) -> CGRect? {
        let documentEnd = contentManager.documentRange.endLocation
        var frame: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: documentEnd,
                                                   options: [.ensuresLayout, .reverse]) { fragment in
            guard let element = fragment.textElement,
                  let elementRange = element.elementRange,
                  contentManager.offset(from: elementRange.endLocation, to: documentEnd) == 0 else {
                return false
            }
            let origin = fragment.layoutFragmentFrame.origin
            for line in fragment.textLineFragments where line.characterRange.length == 0 {
                let bounds = line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y)
                guard bounds.minY.isFinite else { continue }
                // 高度换成这一档字号自己的行高：extra line fragment 的高度带着行距，
                // 直接用它会让这一块比有字时高一行距（和 `textFrame` 里同一条规则）。
                let lineBox = CGRect(x: bounds.minX, y: bounds.minY, width: 0, height: quoteLineHeight)
                frame = frame.map { $0.union(lineBox) } ?? lineBox
            }
            return false
        }
        if frame == nil, textStorage.length == 0 {
            frame = CGRect(x: 0, y: 0, width: 0, height: quoteLineHeight)
        }
        return frame
    }

    /// 引用字号画出来的行高（空段落的那一块用它当高度）。
    private var quoteLineHeight: CGFloat {
        EditorFont.font(EditorBlockStyle.quote.designSize, typeSize: contentTypeSize).lineHeight
    }

    /// 这一段是不是引用：看块类型（`.diaryBlockStyle`），再看旧的底色属性（导入内容
    /// 或本功能之前写的日记只带那一个）。
    private func isQuoteParagraph(at location: Int) -> Bool {
        guard location >= 0, location < textStorage.length else { return false }
        let attrs = textStorage.attributes(at: location, effectiveRange: nil)
        if EditorFont.blockStyle(of: attrs) == .quote { return true }
        if let bg = attrs[.backgroundColor] as? UIColor, !bg.isEqual(UIColor.clear) { return true }
        return false
    }

    /// 这一段**真实文字**的排版框：它每一行的 `typographicBounds` 的并集。
    ///
    /// 不能用整段的 `layoutFragmentFrame`：那个框把段前距、段后距，以及**段落结尾那个
    /// 空行**（`characterRange` 为空的 extra line fragment）全算进来了。后果有两个，
    /// 都会直接落在引用块的底色上：
    ///
    /// * **块比文字大一圈**：段前距（引用 9pt）被算进块内，上下不再是 6pt 的内边距；
    /// * **高度会变**：文档末尾的引用天然带着那个空行（+24pt），而**只要后面再输入
    ///   内容，空行就没了** —— 用户看到的「引用的蓝色背景高度会随着后续输入变化」
    ///   就是这么来的。
    ///
    /// 只并真实行（`characterRange.length > 0`）之后，块只跟这一段文字有关，与前后文
    /// 无关。TextKit 2 是懒排版，这里只把这一段排出来，不会牵动整篇。
    private func textFrame(layoutManager: NSTextLayoutManager,
                           contentManager: NSTextContentManager,
                           location: Int, length: Int) -> CGRect? {
        let documentStart = contentManager.documentRange.location
        guard let start = contentManager.location(documentStart, offsetBy: location),
              let end = contentManager.location(start, offsetBy: length),
              let range = NSTextRange(location: start, end: end) else { return nil }
        var rect: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: range.location,
                                                   options: [.ensuresLayout]) { fragment in
            guard let element = fragment.textElement,
                  let elementRange = element.elementRange else { return false }
            let fragmentStart = contentManager.offset(from: documentStart,
                                                      to: elementRange.location)
            // 已经走出这一段：停（枚举是从这里一路排到文末的）。
            if fragmentStart >= location + length { return false }
            let fragmentFrame = fragment.layoutFragmentFrame
            let origin = fragmentFrame.origin
            guard origin.x.isFinite, origin.y.isFinite else { return true }
            let lines = fragment.textLineFragments
            let realLines = lines.filter { $0.characterRange.length > 0 }
            if realLines.isEmpty {
                // 空段落（刚点「引用」还没输入）只有一条 extra line fragment：它的高度
                // 带着行距，直接用会让块比有字时高一行距（一打字就变矮）。所以只用它
                // 定位，高度换成这一档字号自己的行高。
                if let extra = lines.first?.typographicBounds {
                    let bounds = CGRect(x: extra.minX + origin.x, y: extra.minY + origin.y,
                                        width: 0, height: quoteLineHeight)
                    rect = rect.map { $0.union(bounds) } ?? bounds
                } else {
                    let bounds = CGRect(x: origin.x, y: origin.y, width: 0, height: quoteLineHeight)
                    rect = rect.map { $0.union(bounds) } ?? bounds
                }
                return true
            }
            for line in realLines {
                // 行框在**片段内**的坐标，加上片段的原点才是容器坐标。
                let bounds = line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y)
                // 只看**纵向**：块的宽度由列宽决定，而空段落的行框宽度是 0
                // （`CGRect.isEmpty` 对宽度为 0 也成立，用它当守卫会把空引用行漏掉）。
                guard !bounds.isNull, bounds.height > 0,
                      bounds.minY.isFinite, bounds.height.isFinite else { continue }
                rect = rect.map { $0.union(bounds) } ?? bounds
            }
            return true
        }
        return rect
    }
}
