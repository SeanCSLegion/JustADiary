import XCTest
import UIKit
import SwiftUI
@testable import JustDiary

/// 列表 / 待办 / 引用这三种块的**画法**，以及编辑态与阅读态的一致性。
///
/// 这三种块原先各画各的：列表圆点紧贴正文、换行后第二行顶到圆点底下；待办复选框
/// 与文字之间没有间距；引用只是一段 `.backgroundColor`（底色跟着字走，行尾参差、
/// 没有内边距、也没有左侧竖条）。修完之后：
///
/// * 标记是一张**宽度等于缩进**的透明画布，图形画在左侧 —— 间距来自画布本身，
///   标记仍然只占一个字符（编辑器的光标 / 选区算术不受影响）；
/// * 列表 / 待办的行有悬挂缩进（`headIndent`），换行后的文字对齐到首行文字；
/// * 引用是「整列宽的圆角底色 + 左侧竖条」，文字让开竖条，由 `BlockDecorationLayer`
///   画在文字后面；
/// * 两条链路（`PartsCodec` 装配 vs `RichEditorController` 实时输入）从同一处取几何，
///   所以同一个块在编辑态与阅读态**逐像素相同**（`testEditorAndReaderRenderIdentically`）。
final class BlockStyleRenderingTests: XCTestCase {

    private let width: CGFloat = 340

    private func list(_ items: [String]) -> ContentPart {
        ContentPart(style: ContentPartStyle.list, items: items)
    }

    private func todo(_ items: [String], _ done: [Bool]) -> ContentPart {
        ContentPart(style: ContentPartStyle.todo, items: items, done: done)
    }

    private func quote(_ text: String) -> ContentPart {
        ContentPart(style: ContentPartStyle.quote, runs: [TextRun(text: text)])
    }

    private func body(_ text: String) -> ContentPart {
        ContentPart(style: ContentPartStyle.body, runs: [TextRun(text: text)])
    }

    private func sampleParts() -> [ContentPart] {
        [
            ContentPart(style: ContentPartStyle.heading, runs: [TextRun(text: "小标题")]),
            body("这一段是正文，用来和下面的引用对比字号。"),
            quote("引用块比正文小一级，底色应该横跨整列、左边一条竖条。这一句故意写长一点，好看到第二行。"),
            list(["找到住处", "办好门禁卡，顺便认识隔壁那只每天在阳台晒太阳、看起来很凶其实很怂的猫"]),
            todo(["验证标题层级", "验证引用底色", "验证行距"], [true, true, false]),
        ]
    }

    // MARK: - 两个模式共用的两个文本视图

    private func makeReader(_ parts: [ContentPart], typeSize: DynamicTypeSize = .large) -> FittedTextView {
        let tv = FittedTextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = BlockMetrics.textContainerInset
        tv.textContainer.lineFragmentPadding = 0
        tv.contentTypeSize = typeSize
        tv.attributedText = PartsCodec.readerChunk(from: parts, imageMaxWidth: width - 12,
                                                   typeSize: typeSize, traits: tv.traitCollection)
        return tv
    }

    private func makeEditor(_ parts: [ContentPart], typeSize: DynamicTypeSize = .large)
        -> (RichEditorController, PlaceholderTextView) {
        let controller = RichEditorController()
        let tv = PlaceholderTextView(frame: .zero, textContainer: nil)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = BlockMetrics.textContainerInset
        tv.textContainer.lineFragmentPadding = 0
        tv.applyTypeSize(typeSize)
        controller.textView = tv
        controller.dynamicTypeSize = typeSize
        controller.load(parts: parts)
        return (controller, tv)
    }

    private func layout(_ tv: UITextView, height: CGFloat = 1200) {
        tv.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tv.setNeedsLayout()
        tv.layoutIfNeeded()
    }

    private func image(of tv: UITextView) -> UIImage {
        tv.layer.displayIfNeeded()
        return UIGraphicsImageRenderer(bounds: tv.bounds).image { ctx in
            UIColor.white.setFill()
            ctx.fill(tv.bounds)
            tv.layer.render(in: ctx.cgContext)
        }
    }

    private func paragraphRanges(_ storage: NSAttributedString) -> [NSRange] {
        let ns = storage.string as NSString
        var ranges: [NSRange] = []
        var start = 0
        while start < ns.length {
            var end = start
            while end < ns.length && ns.character(at: end) != 0x0A { end += 1 }
            ranges.append(NSRange(location: start, length: end - start))
            start = end + 1
        }
        return ranges
    }

    // MARK: - 列表 / 待办：悬挂缩进与标记间距

    /// 标记是这一行的第一个字符，它的画布**宽度就是这一行的缩进**：图形只画在画布
    /// 左侧，于是标记与正文之间有间距，而标记仍然只占一个字符。
    func testMarkerReservesItsIndentInsideOneCharacter() {
        for (kind, indent) in [("bullet", BlockMetrics.markerIndent(kind: "bullet", .large)),
                               ("todo", BlockMetrics.markerIndent(kind: "todo", .large))] {
            let style = PartsCodec.markerParagraphStyle(typeSize: .large, kind: kind)
            XCTAssertEqual(style.firstLineHeadIndent, 0, accuracy: 0.01, kind)
            XCTAssertEqual(style.headIndent, indent, accuracy: 0.01,
                           "换行后的文字要对齐到首行文字，而不是回到列首")

            let attachment = MarkerAttachment.attachment(kind: kind, typeSize: .large)
            XCTAssertEqual(attachment.bounds.width, indent, accuracy: 0.01,
                           "画布宽度必须等于缩进：正文正好从缩进处开始")
            let glyph = BlockMetrics.markerSize(kind: kind, .large)
            XCTAssertLessThan(glyph, indent, "图形要比画布窄，留出与正文的间距（\(kind)）")
        }
    }

    /// 标记的图形**垂直居中于正文**：画布下沿落在 descent 上、上沿落在 ascent 上，
    /// 图形中心在基线之上 `markerCenterAboveBaseline`。
    func testMarkerGlyphIsCentredOnTheBaseline() {
        let font = EditorFont.font(EditorDesignSize.body, typeSize: .large)
        let bounds = MarkerGlyph.bounds(kind: "todo", font: font, typeSize: .large)
        XCTAssertEqual(bounds.minY, -(-font.descender), accuracy: 0.01, "画布下沿落在 descent 上")
        XCTAssertEqual(bounds.maxY, font.ascender, accuracy: 0.51, "画布上沿落在 ascent 上")
        // 图形中心 = 画布上沿往下 (ascent - center)。
        let centerY = bounds.maxY - (font.ascender - BlockMetrics.markerCenterAboveBaseline(.large))
        XCTAssertEqual(centerY, BlockMetrics.markerCenterAboveBaseline(.large), accuracy: 0.51)
        XCTAssertLessThanOrEqual(bounds.height, font.lineHeight,
                                 "画布不能比行盒高，否则会把带标记的行撑开")
    }

    /// 列表 / 待办的每一行都拿到同一个悬挂缩进 —— 编辑态和阅读态都是。
    func testListAndTodoParagraphsCarryTheHangingIndentInBothModes() {
        let parts = [list(["甲"]), todo(["乙"], [false])]
        for storage in [makeReader(parts).textStorage,
                        makeEditor(parts).1.textStorage] {
            let indents = paragraphRanges(storage).map { range -> CGFloat in
                let style = storage.attribute(.paragraphStyle, at: range.location,
                                              effectiveRange: nil) as? NSParagraphStyle
                return style?.headIndent ?? -1
            }
            XCTAssertEqual(indents, [BlockMetrics.markerIndent(kind: "bullet", .large),
                                     BlockMetrics.markerIndent(kind: "todo", .large)],
                           "两条链路都要缩进")
        }
    }

    // MARK: - 引用：底色块 + 竖条

    /// 引用段落：文字让开竖条，段落样式里带着缩进；底色不再是 `.backgroundColor`
    /// （旧写法只盖住字，行尾参差）。
    func testQuoteIndentsItsTextAndDropsTheOldBackgroundAttribute() {
        let parts = [quote("引用一句话。")]
        for storage in [makeReader(parts).textStorage, makeEditor(parts).1.textStorage] {
            let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(style?.firstLineHeadIndent ?? -1,
                           BlockMetrics.quoteTextInset(.large), accuracy: 0.01)
            XCTAssertEqual(style?.headIndent ?? -1,
                           BlockMetrics.quoteTextInset(.large), accuracy: 0.01)
            XCTAssertEqual(EditorFont.blockStyle(of: storage.attributes(at: 0, effectiveRange: nil)),
                           .quote, "块类型仍然是引用的判据")
            let bg = storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? UIColor
            XCTAssertTrue(bg == nil || bg!.isEqual(UIColor.clear),
                          "引用不再用文字底色画（那是荧光笔，不是引用块）")
        }
    }

    /// 装饰层为每个引用段落画一个块：横跨整列、含上下内边距，竖条在块内左侧。
    func testQuoteDecorationSpansTheColumnAndKeepsTheBarInside() {
        let parts = [body("正文"), quote("引用一句话。"), body("正文")]
        let tv = makeReader(parts)
        layout(tv)
        let blocks = tv.blockDecorations.quotes
        XCTAssertEqual(blocks.count, 1, "只有引用段落有装饰")
        guard let block = blocks.first else { return }

        let inset = tv.textContainerInset
        let columnWidth = tv.bounds.width - inset.left - inset.right
        XCTAssertEqual(block.frame.minX, inset.left, accuracy: 0.01, "底色从正文列左边界开始")
        XCTAssertEqual(block.frame.width, columnWidth, accuracy: 0.01, "底色横跨整列")

        let barLeading = BlockMetrics.quoteBarLeading(.large)
        XCTAssertEqual(block.bar.minX, inset.left + barLeading, accuracy: 0.01)
        XCTAssertGreaterThan(block.bar.minX, block.frame.minX, "竖条在底色块内部")
        XCTAssertGreaterThanOrEqual(block.bar.minY, block.frame.minY)
        XCTAssertLessThanOrEqual(block.bar.maxY, block.frame.maxY)
        XCTAssertGreaterThanOrEqual(block.bar.minX, BlockMetrics.quoteTextInset(.large) - 100)
        XCTAssertLessThan(block.bar.maxX, BlockMetrics.quoteTextInset(.large),
                          "文字让开竖条，竖条不能压到字上")
    }

    /// 引用块的高度跟着段落走：两行的块明显比一行高（每行都算进同一个块）。
    func testQuoteBlockGrowsWithAWrappedParagraph() {
        let short = makeReader([quote("短。")])
        layout(short)
        let long = makeReader([quote("这一句故意写得长一些，好让它在这个宽度下折成两行，从而检验引用块的高度是否把两行都算进去。")])
        layout(long)
        guard let shortBlock = short.blockDecorations.quotes.first,
              let longBlock = long.blockDecorations.quotes.first else {
            return XCTFail("两个引用段落都该有装饰")
        }
        XCTAssertGreaterThan(longBlock.frame.height, shortBlock.frame.height + 10,
                             "两行的引用块要把第二行也算进去")
    }

    /// 引用块只跟**这一段文字**有关：后面再输入内容（或删光）都不能改变它。
    ///
    /// 回归点：`layoutFragmentFrame` 会把段落结尾那个空行（`characterRange` 为空的
    /// extra line fragment）与段前距一起算进来 —— 文档末尾的引用因此比别处高出一整行，
    /// 而**一旦后面输入了内容，那个空行就消失**，用户看到的就是「引用的蓝色背景高度
    /// 会随着后续输入变化」。
    func testQuoteBlockDoesNotChangeWhenContentFollows() {
        func block(_ parts: [ContentPart]) -> CGRect? {
            let tv = makeReader(parts)
            layout(tv)
            return tv.blockDecorations.quotes.first?.frame
        }
        func height(_ rect: CGRect?) -> CGFloat { rect?.height ?? -1 }
        let quote = quote("引用一句话。")
        guard let last = block([body("上文"), quote]),
              let followed = block([body("上文"), quote, body("短")]),
              let followedLong = block([body("上文"), quote,
                                        body("后面这一段很长，长到会折行，用来看引用块会不会跟着变。")]) else {
            return XCTFail("三种排版都该有引用块")
        }
        XCTAssertEqual(last, followed, "引用块不该因为后面多了一段而变")
        XCTAssertEqual(last, followedLong, "引用块不该因为后面那段折行而变")

        // 高度 = 真实行高 + 上下 6pt 内边距（不含段前距、不含结尾空行）。
        let padding = BlockMetrics.quotePadding(.large) * 2
        XCTAssertEqual(height(last), 17.90 + padding, accuracy: 1,
                       "单行引用块 = 一行 17.9pt + 上下内边距")
        XCTAssertLessThan(height(last), 17.90 + padding + 8, "不能把段前距也算进块里")
    }

    /// 两行的引用块要把两行都盖住（含行间），不是只有第一行。
    func testQuoteBlockCoversEveryLineOfAWrappedParagraph() {
        let tv = makeReader([quote("这一句很长，长到在这个宽度里会折成两行，从而检验引用块的高度是否把第二行也算进去。")])
        layout(tv)
        guard let block = tv.blockDecorations.quotes.first else { return XCTFail("应有引用块") }
        let padding = BlockMetrics.quotePadding(.large) * 2
        let twoLines = 17.90 * 2 + EditorBlockStyle.quote.lineSpacing
        XCTAssertEqual(block.frame.height, twoLines + padding, accuracy: 1.5,
                       "两行引用块 = 两行 + 行距 + 上下内边距")
    }

    /// 空引用行（刚点完引用按钮、还没输入）也要有块 —— 它的样式挂在自己的换行符上。
    ///
    /// 编辑区里这条空行**在**（它以换行符结尾），读模式的块尾换行会被
    /// `readerChunk` 摘掉，所以只有「中间那条空引用行」会在读模式里出现。
    func testEmptyQuoteLineStillGetsABlock() {
        let (_, editor) = makeEditor([body("上文"), ContentPart(style: ContentPartStyle.quote, text: "")])
        layout(editor)
        XCTAssertEqual(editor.blockDecorations.quotes.count, 1, "编辑区：空引用行也要有底色块")
        XCTAssertGreaterThan(editor.blockDecorations.quotes.first?.frame.height ?? 0, 10,
                             "空引用行的块要有一行高（不是 0）")

        let reader = makeReader([body("上文"), ContentPart(style: ContentPartStyle.quote, text: ""), body("下文")])
        layout(reader)
        XCTAssertEqual(reader.blockDecorations.quotes.count, 1, "读模式：中间的空引用行也要有块")
    }

    /// 装饰层在**文字后面**：文本视图的子层顺序不能把底色盖在字上面。
    func testDecorationLayerStaysBehindTheText() {
        let tv = makeReader([quote("引用")])
        layout(tv)
        XCTAssertTrue(tv.layer.sublayers?.first === tv.blockDecorations,
                      "装饰层必须在最底下（文本层画在它上面）")
    }

    /// 字号档位变了，引用块与标记跟着放大。
    func testBlockGeometryFollowsTheTextSizeSetting() {
        XCTAssertGreaterThan(BlockMetrics.quoteTextInset(.accessibility3), BlockMetrics.quoteTextInset(.large))
        XCTAssertGreaterThan(BlockMetrics.markerIndent(kind: "todo", .accessibility3),
                             BlockMetrics.markerIndent(kind: "todo", .large))

        let tv = makeReader([quote("引用")], typeSize: .accessibility3)
        layout(tv)
        let style = tv.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.headIndent ?? -1, BlockMetrics.quoteTextInset(.accessibility3), accuracy: 0.01)
        XCTAssertEqual(tv.blockDecorations.quotes.first?.bar.width ?? -1,
                       BlockMetrics.quoteBarWidth(.accessibility3), accuracy: 0.01)
    }

    // MARK: - 编辑态 == 阅读态

    /// 同一个块，编辑态画出来的和阅读态**逐像素相同**。
    ///
    /// 编辑器的文档以换行结尾（末尾那条空段落是给用户打字的），阅读态的块会摘掉它 ——
    /// 所以比较的是两者公共的那段高度。
    func testEditorAndReaderRenderIdentically() {
        let parts = sampleParts()
        let reader = makeReader(parts)
        layout(reader)
        let (_, editor) = makeEditor(parts)
        layout(editor)

        let readerImage = image(of: reader)
        let editorImage = image(of: editor)
        let height = min(readerImage.size.height, editorImage.size.height)
        let shared = CGRect(x: 0, y: 0, width: min(readerImage.size.width, editorImage.size.width),
                            height: height - 24)
        guard let a = readerImage.cgImage?.cropping(to: shared),
              let b = editorImage.cgImage?.cropping(to: shared) else {
            return XCTFail("两张渲染图都该裁得出来")
        }
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)

        let differing = pixelDifference(a, b)
        XCTAssertEqual(differing, 0, "编辑态与阅读态必须画出同一个效果（\(differing) 个像素不同）")
    }

    private func pixelDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let width = a.width
        let height = a.height
        let bytes = width * height * 4
        var bufferA = [UInt8](repeating: 0, count: bytes)
        var bufferB = [UInt8](repeating: 0, count: bytes)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctxA = CGContext(data: &bufferA, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let ctxB = CGContext(data: &bufferB, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return -1
        }
        ctxA.draw(a, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctxB.draw(b, in: CGRect(x: 0, y: 0, width: width, height: height))
        var differing = 0
        for i in stride(from: 0, to: bytes, by: 4) {
            if abs(Int(bufferA[i]) - Int(bufferB[i])) > 8
                || abs(Int(bufferA[i + 1]) - Int(bufferB[i + 1])) > 8
                || abs(Int(bufferA[i + 2]) - Int(bufferB[i + 2])) > 8 {
                differing += 1
            }
        }
        return differing
    }

    /// 实时输入的那条链路（点按钮开启列表 / 引用）也要拿到同一份几何 —— 只改
    /// `PartsCodec` 而漏掉 `RichEditorController` 的话，这一条会挂。
    func testLiveTogglesProduceTheSameGeometryAsTheCodec() {
        let (controller, tv) = makeEditor([body("甲")])
        tv.selectedRange = NSRange(location: 0, length: 1)
        controller.toggleList()
        layout(tv)
        var style = tv.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.headIndent ?? -1, BlockMetrics.markerIndent(kind: "bullet", .large),
                       accuracy: 0.01, "点按钮加的列表项要有同样的悬挂缩进")

        // 再点一次取消列表：标记摘掉，**缩进也要跟着归零** —— 缩进挂在段落样式上，
        // 不归零的话这一行会顶着一份「列表的缩进」继续当正文排。
        controller.toggleList()
        layout(tv)
        style = tv.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.headIndent ?? -1, 0, accuracy: 0.01, "取消列表后不该还留着悬挂缩进")
        XCTAssertEqual(style?.firstLineHeadIndent ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(controller.currentParts().map(\.style), [ContentPartStyle.body])

        // 空行上同理：光标停的那条空行不能留下列表的缩进（它的行盒由自己的换行符排出）。
        let (emptyController, emptyTV) = makeEditor([body("")])
        emptyTV.selectedRange = NSRange(location: 0, length: 0)
        emptyController.toggleList()
        layout(emptyTV)
        emptyController.toggleList()
        layout(emptyTV)
        let emptyStyle = emptyTV.textStorage.attribute(.paragraphStyle, at: 0,
                                                       effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(emptyStyle?.headIndent ?? -1, 0, accuracy: 0.01,
                       "取消列表后空行也不该留着悬挂缩进")

        // 同一行再改成引用：缩进换成引用的，标记被摘掉。
        controller.toggleQuote()
        layout(tv)
        style = tv.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.headIndent ?? -1, BlockMetrics.quoteTextInset(.large), accuracy: 0.01)
        XCTAssertEqual(style?.firstLineHeadIndent ?? -1, BlockMetrics.quoteTextInset(.large), accuracy: 0.01)
        XCTAssertEqual(controller.currentParts().map(\.style), [ContentPartStyle.quote])
        XCTAssertEqual(tv.blockDecorations.quotes.count, 1, "点出来的引用也要有装饰块")
    }
}
