import XCTest
import UIKit
import SwiftUI
@testable import JustDiary

/// The vertical rhythm, measured on the real layout.
///
/// These numbers cannot be read off a constant: the gap between two paragraphs
/// is TextKit adding one paragraph's `paragraphSpacing` to the next one's
/// `paragraphSpacingBefore`, and TextKit folds both into the *line box* of the
/// paragraph that owns them. So the tests measure two things per paragraph —
/// its line box and the tight ink box inside it — and reason about the gaps the
/// eye actually sees.
///
/// The rules being pinned:
///
/// * body → body adds nothing beyond a normal line advance;
/// * a title/heading is **further from what it follows than from what it
///   introduces** — the editor used to have space *after* only, so a heading
///   hugged the paragraph above it and read as part of it;
/// * an image gets the same room above and below (`imageSpacing`);
/// * a read chunk carries no reserved caret line at the end (that phantom line
///   was ~20pt of blank space before every image and before the card edge).
final class EditorSpacingTests: XCTestCase {

    private let width: CGFloat = 320

    private struct Paragraph {
        var boxTop: CGFloat
        var boxBottom: CGFloat
        var inkTop: CGFloat
        var inkBottom: CGFloat
    }

    /// One entry per paragraph of the rendered document (the codec terminates
    /// every paragraph with a newline).
    ///
    /// TextKit 1 keeps the text storage alive through the manager, so the storage
    /// has to stay in scope for the manager to report anything at all.
    private func paragraphs(_ attributed: NSAttributedString) -> [Paragraph] {
        guard attributed.length > 0 else { return [] }
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)

        let ns = attributed.string as NSString
        var result: [Paragraph] = []
        var start = 0
        while start < ns.length {
            var end = start
            while end < ns.length && ns.character(at: end) != 0x0A { end += 1 }
            let length = end - start
            if length > 0 {
                let box = manager.lineFragmentRect(forGlyphAt: start, effectiveRange: nil)
                let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: start, length: length),
                                                actualCharacterRange: nil)
                let ink = manager.boundingRect(forGlyphRange: glyphs, in: container)
                result.append(Paragraph(boxTop: box.minY, boxBottom: box.maxY,
                                        inkTop: ink.minY, inkBottom: ink.maxY))
            }
            start = end + 1
        }
        return result
    }

    /// What a read chunk measures inside its own text view, which is where the
    /// reserved trailing caret line shows up (TextKit's own layout skips it).
    private func textViewHeight(_ attributed: NSAttributedString) -> CGFloat {
        let tv = UITextView()
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.attributedText = attributed
        return tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    private func body(_ text: String) -> ContentPart {
        ContentPart(style: ContentPartStyle.body, runs: [TextRun(text: text)])
    }

    private func line(_ style: String, _ text: String) -> ContentPart {
        ContentPart(style: style, runs: [TextRun(text: text)])
    }

    private func attachmentBounds(_ attributed: NSAttributedString) -> CGRect? {
        var rect: CGRect?
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let attachment = value as? PayloadAttachment { rect = attachment.bounds }
        }
        return rect
    }

    /// Redraws into a plain RGBA bitmap: `ImageRenderer`'s own image is backed
    /// by a pixel buffer with no readable data provider.
    private func readable(_ image: UIImage) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
    }

    /// The colour bytes at a point of a rendered image. Alpha is not reliable
    /// here (the renderer may drop it), so callers compare against the corner.
    private func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) -> [UInt8] {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return [] }
        let bpp = max(1, cg.bitsPerPixel / 8)
        let offset = Int(y) * cg.bytesPerRow + Int(x) * bpp
        guard offset + bpp <= CFDataGetLength(data) else { return [] }
        return (0..<bpp).map { bytes[offset + $0] }
    }

    private func doc(_ parts: [ContentPart], width: CGFloat? = nil) -> NSAttributedString {
        PartsCodec.attributedString(from: parts, imageMaxWidth: width ?? self.width, typeSize: .large)
    }

    /// A real file on disk: without one the codec cannot size the picture, so a
    /// fake path would measure nothing.
    private func imagePart(_ name: String = "spacing-test.png", h: CGFloat = 138) throws -> ContentPart {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        // Same aspect as the declared 300 × 138: the view draws with
        // `scaledToFit`, so a mismatched fixture would letterbox and the
        // edge-to-edge assertion below would measure the fixture, not the code.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 150, height: 69))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 150, height: 69))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        return ContentPart(style: ContentPartStyle.image, src: "images/\(name)", w: 300, h: Double(h))
    }

    // MARK: - The rules, in the model

    /// 段间距**全部由段前距承担**，段后距一律为 0。
    ///
    /// TextKit 把段前距折进这一段自己的行盒、段后距折进上一段的盒底，而每一行下面
    /// 本来就压着 `lineSpacing`。用段前距承担，图片上下才能配平、读模式的块首块尾
    /// 才不会多出空白（贴边的段距会被丢掉）。
    func testParagraphSpacingComesFromTheSpaceBefore() {
        for style in EditorBlockStyle.allCases {
            XCTAssertEqual(style.paragraphSpacing, 0, accuracy: 0.01, "\(style) 的段后距应为 0")
            XCTAssertGreaterThan(style.paragraphSpacingBefore, 0, "\(style) 要有段前距")
        }
        XCTAssertEqual(EditorBlockStyle.body.paragraphSpacingBefore, EditorDesignSize.body * 0.5,
                       accuracy: 0.01, "正文之间留半行")
        XCTAssertGreaterThan(EditorBlockStyle.title.paragraphSpacingBefore,
                             EditorBlockStyle.heading.paragraphSpacingBefore)
        XCTAssertGreaterThan(EditorBlockStyle.heading.paragraphSpacingBefore,
                             EditorBlockStyle.body.paragraphSpacingBefore)
    }

    /// 行高按 HIG 的梯级 + CJK 的下限来，正文再放宽到 1.5。
    func testLineHeightFollowsTheAppleLadderAndTheCJKFloor() {
        // HIG「iOS built-in text styles」的行高下限（Leading ÷ Size）。
        let higFloor: [EditorBlockStyle: CGFloat] = [.title: 34.0 / 28, .heading: 28.0 / 22,
                                                     .body: 22.0 / 17, .quote: 20.0 / 15]
        for style in EditorBlockStyle.allCases {
            XCTAssertGreaterThanOrEqual(style.lineHeightRatio, (higFloor[style] ?? 0) - 0.001,
                                        "\(style) 不能低于 HIG 的行高")
        }
        // 成段的样式还要容得下中日韩字体自己的行高（PingFang 1.40em）。
        for style in [EditorBlockStyle.body, .quote] {
            XCTAssertGreaterThanOrEqual(style.lineHeightRatio, EditorDesignSize.cjkLineHeightRatio,
                                        "\(style) 要容得下 CJK 字体的行高，否则汉字上下贴住")
        }
        XCTAssertEqual(EditorBlockStyle.body.lineHeightRatio, 1.50, accuracy: 0.001,
                       "长段落用松行距（HIG）")
        XCTAssertLessThan(EditorBlockStyle.title.lineHeightRatio, EditorBlockStyle.heading.lineHeightRatio)
        XCTAssertLessThan(EditorBlockStyle.heading.lineHeightRatio, EditorBlockStyle.body.lineHeightRatio)

        // lineSpacing 就是把目标行高补齐的那一份，按字号等比。
        for style in EditorBlockStyle.allCases {
            let drawn = style.designSize * EditorDesignSize.systemLineHeightRatio + style.lineSpacing
            XCTAssertEqual(drawn / style.designSize, style.lineHeightRatio, accuracy: 0.001)
        }
    }

    /// 两段正文之间真的分得开：空隙就是后一段的段前距。
    func testBodyParagraphsAreSeparatedByHalfALine() {
        let rows = paragraphs(doc([body("正文一"), body("正文二")]))
        XCTAssertEqual(rows.count, 2)
        let advance = rows[1].inkTop - rows[0].inkTop
        let lineHeight = rows[0].boxBottom - rows[0].boxTop
        XCTAssertEqual(advance - lineHeight, EditorBlockStyle.body.paragraphSpacingBefore, accuracy: 0.5,
                       "两段正文之间的空隙应等于段前距（实测 \(advance - lineHeight)）")
        XCTAssertGreaterThan(advance - lineHeight, 4, "两段之间必须真的分得开")
    }

    /// 标题仍然「离上文比离下文远」——这一条现在由「上一段的 lineSpacing + 标题的
    /// 段前距」对上「正文的段前距」实现，所以要真排一遍来量。
    func testHeadingKeepsMoreRoomAboveThanBelow() {
        let rows = paragraphs(doc([body("上文"), line(ContentPartStyle.heading, "小标题"), body("下文")]))
        XCTAssertEqual(rows.count, 3)
        let above = rows[1].inkTop - rows[0].inkBottom
        let below = rows[2].inkTop - rows[1].inkBottom
        XCTAssertGreaterThan(above, below + 3,
                             "小标题应离上文更远（实测上 \(above) / 下 \(below)）")
    }

    /// 列表 / 待办行按正文属性排版：行内换行也要有正文的 `lineSpacing`。
    ///
    /// 行首标记是这一行的**第一个字符**，而段落样式取自段落第一个字符 —— 标记上不带
    /// 段落样式时，整条列表项会退回默认段落属性，把正文的行距悄悄丢掉
    /// （改造前实测折行推进 20.29pt，而正文是 22.5pt；现行模型下正文会多出
    /// 5.219pt 的 `lineSpacing`）。所以 `MarkerAttachment.attributed`
    /// 会把行段落样式挂在标记上。
    func testMarkerLinesWrapWithTheBodyLineSpacing() {
        let long = String(repeating: "字", count: 40)
        let bodyHeight = lineFragmentHeights(doc([body(long)]), width: 200).first
        let listHeight = lineFragmentHeights(doc([ContentPart(style: ContentPartStyle.list, items: [long])]),
                                            width: 200).first
        let todoHeight = lineFragmentHeights(doc([ContentPart(style: ContentPartStyle.todo, items: [long],
                                                              done: [false])]),
                                            width: 200).first

        XCTAssertNotNil(bodyHeight)
        XCTAssertEqual(listHeight ?? 0, bodyHeight ?? -1, accuracy: 0.01,
                       "列表项折行推进应与正文一致（标记也要带行段落样式）")
        XCTAssertEqual(todoHeight ?? 0, bodyHeight ?? -1, accuracy: 0.01,
                       "待办项折行推进应与正文一致")
    }

    /// 每一行折行片的高度（`lineFragmentRect`）；用来量行内换行的推进。
    private func lineFragmentHeights(_ attributed: NSAttributedString, width: CGFloat) -> [CGFloat] {
        guard attributed.length > 0 else { return [] }
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        var heights: [CGFloat] = []
        var index = 0
        while index < manager.numberOfGlyphs {
            var range = NSRange()
            heights.append(manager.lineFragmentRect(forGlyphAt: index, effectiveRange: &range).height)
            index = range.location + range.length
        }
        return heights
    }

    // MARK: - The rules, in the layout

    func testHeadingPushesTheTextAboveItFurtherThanTheTextBelow() {
        // Compare against the same document with plain body text in the middle:
        // that isolates the heading's spacing from the fonts' own metrics.
        let withHeading = paragraphs(doc([body("上文"), line(ContentPartStyle.heading, "小标题"), body("下文")]))
        let plain = paragraphs(doc([body("上文"), body("小标题"), body("下文")]))
        XCTAssertEqual(withHeading.count, 3)
        XCTAssertEqual(plain.count, 3)

        let headingAbove = withHeading[1].inkTop - withHeading[0].inkBottom
        let headingBelow = withHeading[2].inkTop - withHeading[1].inkBottom
        let plainAbove = plain[1].inkTop - plain[0].inkBottom
        let plainBelow = plain[2].inkTop - plain[1].inkBottom

        XCTAssertGreaterThan(headingAbove - plainAbove, headingBelow - plainBelow,
                             "小标题多出来的空间应该加在上方（旧实现只加在下方）")
    }

    func testTitlePushesTheTextAboveItFurtherThanTheTextBelow() {
        let withTitle = paragraphs(doc([body("上文"), line(ContentPartStyle.title, "大标题"), body("下文")]))
        let plain = paragraphs(doc([body("上文"), body("大标题"), body("下文")]))

        let titleAbove = withTitle[1].inkTop - withTitle[0].inkBottom
        let titleBelow = withTitle[2].inkTop - withTitle[1].inkBottom
        let plainAbove = plain[1].inkTop - plain[0].inkBottom
        let plainBelow = plain[2].inkTop - plain[1].inkBottom

        XCTAssertGreaterThan(titleAbove - plainAbove, titleBelow - plainBelow)
    }

    // MARK: - Images

    /// 图片上下的**可见**留白一样多：把行盒与墨迹之间那两段看不见的空白
    /// （`imageTopSlack` / `imageBottomSlack`）算进来之后，两边相等且不比
    /// `imageSpacing` 小。
    func testImageIsVisuallyBalancedByTheModel() {
        let style = PartsCodec.imageParagraphStyle()
        let above = style.paragraphSpacingBefore + EditorDesignSize.imageTopSlack
        let below = style.paragraphSpacing + EditorDesignSize.imageBottomSlack
        XCTAssertEqual(above, EditorDesignSize.imageSpacing, accuracy: 0.5, "图片上方")
        XCTAssertEqual(below, EditorDesignSize.imageSpacing, accuracy: 0.5, "图片下方")
        // 读模式那一侧：padding + 正文块的内缩 + 块内的墨迹留白 = 同一个值。
        let readerAbove = EditorDesignSize.readerImagePadding
            + BlockMetrics.textContainerInset.top + EditorDesignSize.imageTopSlack
        let readerBelow = EditorDesignSize.readerImagePadding
            + BlockMetrics.textContainerInset.bottom + EditorDesignSize.imageTopSlack
        XCTAssertEqual(readerAbove, EditorDesignSize.imageSpacing, accuracy: 0.5, "读模式图片上方")
        XCTAssertEqual(readerBelow, EditorDesignSize.imageSpacing, accuracy: 0.5, "读模式图片下方")
        // 图片后面的那一段自己不再加段前距（`appendLine(followsImage:)`）。
        let parts = [ContentPart(style: ContentPartStyle.image, src: "images/x.png", w: 300, h: 138),
                     body("图注")]
        let chunk = PartsCodec.readerChunk(from: parts, imageMaxWidth: width)
        let paragraphStyle = chunk.attribute(.paragraphStyle, at: chunk.length - 1,
                                             effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.paragraphSpacingBefore ?? -1, 0, accuracy: 0.01,
                       "图片后面的那一段不该再加段前距")
    }

    /// 图片不再是「贴着上一行」，而且上下的可见留白一样多：把它真画成位图，量图片（systemTeal）上下最近的一行
    /// 墨迹 —— 两边都要明显大于 0（原来图片是紧贴上下两行的）。
    ///
    /// 只断言「不贴」而不是「两边完全相等」：`boundingRect(forGlyphRange:)` 给的是行
    /// 片段而非紧致墨迹，TextKit 2 又把附件放在基线上，按像素量会把字体自身的
    /// ascent / descent 差算进去（下面那一段的墨迹从行盒顶往下 12pt 才开始）。盒级的
    /// 对称由 `testImageOwnsTheDifferenceSoBothSidesMatch` 保证。
    @MainActor
    func testImageIsNotGluedToTheTextAroundIt() throws {
        let image = try imagePart()
        let tv = UITextView()
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.backgroundColor = .white
        tv.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        tv.attributedText = doc([body("正文一"), image, body("正文二")])
        tv.setNeedsLayout()
        tv.layoutIfNeeded()
        tv.layer.displayIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: tv.bounds.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(tv.bounds)
            tv.layer.render(in: ctx.cgContext)
        }
        guard let source = rendered.cgImage else { return XCTFail("渲染不出位图") }
        // 自己开一个 RGBA 的上下文再画一遍：`UIGraphicsImageRenderer` 出来的位图
        // 字节序不定（常见的是 BGRA），按通道读颜色会读错。
        let w = source.width
        let h = source.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return XCTFail("建不出位图上下文")
        }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let o = (y * w + x) * 4
            return (Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2]))
        }
        // 「墨迹」= 深色像素。不能用「非白」：图片自己的圆角边缘有一圈浅色抗锯齿，
        // 会被当成图片下面第一行墨迹（实测差 1pt 就是这么来的）。
        let hasInk = (0..<h).map { y in
            (0..<w).contains { x in let (r, g, b) = rgb(x, y); return r < 160 && g < 160 && b < 160 }
        }
        // 图片是 teal（绿色通道明显、红色通道明显低），文字是深灰（三通道接近）。
        func isTeal(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = rgb(x, y)
            return g - r > 60 && b - r > 60
        }
        let middleX = w / 2
        guard let imageTop = (0..<h).first(where: { isTeal(middleX, $0) }),
              let imageBottom = (0..<h).last(where: { isTeal(middleX, $0) }) else {
            return XCTFail("位图里找不到图片")
        }
        let inkAbove = (0..<imageTop).last(where: { hasInk[$0] })
        let inkBelow = ((imageBottom + 1)..<h).first(where: { hasInk[$0] })
        let gapAbove = imageTop - (inkAbove ?? imageTop)
        let gapBelow = (inkBelow ?? imageBottom) - imageBottom
        XCTAssertEqual(gapAbove, gapBelow, accuracy: 2,
                       "图片上下的可见留白要基本一样（实测上 \(gapAbove) / 下 \(gapBelow)）")
        XCTAssertGreaterThanOrEqual(gapAbove, Int(EditorDesignSize.imageSpacing),
                                    "图片上方原来贴着上一行（实测 \(gapAbove)）")
        XCTAssertGreaterThanOrEqual(gapBelow, Int(EditorDesignSize.imageSpacing),
                                    "图片下方原来贴着下一行（实测 \(gapBelow)）")
    }

    func testImageSpacingScalesWithTheTextSize() {
        // Design points, resolved through the text-size ladder like everything
        // else in the editor. 0.8 个正文：一段正文之间的实际空隙是
        // `lineSpacing + 段前距` = 13.7pt，图片是单独一块，留白不该比段落之间还小。
        XCTAssertEqual(EditorDesignSize.imageSpacing, EditorDesignSize.body * 0.8, accuracy: 0.01)
    }

    /// 图片上下的「盒级」空隙都等于 `imageSpacing`：上一段行盒里的 `lineSpacing`
    /// 与下一段的段前距已经各加了一份，所以图片自己那份要把它们扣掉。
    func testInsertedImageIsSpacedLikeALoadedOne() throws {
        let src = try XCTUnwrap(try imagePart().src)
        let controller = RichEditorController()
        let tv = UITextView()
        tv.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        controller.textView = tv
        controller.load(parts: [body("正文一")])
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)

        let inserted = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        controller.insertImage(inserted, src: src)
        XCTAssertEqual(tv.textStorage.string, "正文一\n\u{FFFC}\n",
                       "图片插在光标处，后面跟一个换行")

        // insertImage lays the picture out at the **text column** width: the text view's
        // width minus its own text insets (zero here). It used to subtract a hard-coded
        // 24pt, which stopped matching the width `refitImages`/the codec use once the
        // editor dropped its 12pt side inset — images then jumped 24pt on rotation.
        let expectedHeight = CGFloat(320) * 80 / 120
        let rows = paragraphs(tv.textStorage)
        XCTAssertEqual(rows.count, 2, "正文 / 图片（结尾空行不算一段）")
        XCTAssertEqual(rows[1].inkBottom - rows[1].inkTop, expectedHeight, accuracy: 1,
                       "刚插入的图片行就是图片高度（旧实现给它套了正文段落的属性）")
        XCTAssertEqual(rows[1].inkTop - rows[1].boxTop,
                       PartsCodec.imageParagraphStyle().paragraphSpacingBefore, accuracy: 0.5,
                       "刚插入的图片上方的空隙 = 图片段落的段前距（重新打开时同一条路径）")
    }

    func testImageKeepsItsLineWhenTheFileIsMissing() {
        // The reader used to drop the whole image line when the file could not be
        // loaded, so a missing picture silently reflowed the entry.
        let missing = ContentPart(style: ContentPartStyle.image, src: "images/does-not-exist.png",
                                  w: 300, h: 138)
        let attributed = doc([body("正文一"), missing, body("正文二")])
        XCTAssertEqual(attributed.length, doc([body("正文一"), body("正文二")]).length + 2,
                       "占位附件 + 换行都应保留")
        let placeholder = paragraphs(attributed)[1]
        XCTAssertEqual(placeholder.inkBottom - placeholder.inkTop, 138 * width / 300, accuracy: 1,
                       "占位仍占图片应有的高度")
    }

    // MARK: - Reader chunks

    func testReaderChunkDropsTheReservedCaretLine() {
        let parts = [body("正文一"), body("正文二")]
        let editor = doc(parts)
        let reader = PartsCodec.readerChunk(from: parts)

        XCTAssertFalse(reader.string.hasSuffix("\n"), "读模式的块不该带结尾换行")
        let saved = textViewHeight(editor) - textViewHeight(reader)
        XCTAssertGreaterThan(saved, 15,
                             "结尾那个换行会让 UITextView 多留一整行（原来阅读区每块都多这一行）")
    }

    func testReaderImageChunkIsExactlyTheImage() throws {
        let chunk = PartsCodec.readerChunk(from: [try imagePart()], imageMaxWidth: width)

        XCTAssertNil(chunk.attribute(.paragraphStyle, at: 0, effectiveRange: nil),
                     "图片块的段距由 DiaryPartsView 用 padding 给，不该在段样式里再算一遍")
        // The picture (scaled to the chunk) plus the line's descender — what
        // matters is that the ~20pt reserved caret line is gone.
        let scaled = 138 * width / 300
        let height = textViewHeight(chunk)
        XCTAssertGreaterThan(height, scaled)
        XCTAssertLessThan(height, scaled + 8, "块高就是图片高度，上下留白交给 padding")
    }

    func testReaderTextChunkKeepsItsParagraphGaps() {
        let parts = [body("上文"), line(ContentPartStyle.title, "大标题")]
        let chunk = paragraphs(PartsCodec.readerChunk(from: parts))
        let editor = paragraphs(doc(parts))
        XCTAssertEqual(chunk.count, 2)
        XCTAssertEqual(editor.count, 2)

        // 读模式只是砍掉块尾的换行与图片块的段样式，块**内部**的段距必须与编辑区
        // 一模一样（TextKit 把段前距折进这一段自己的行盒）。
        // （末尾那一段的取整会和编辑区差一丝，所以给 1pt 容差。）
        for i in 0..<2 {
            XCTAssertEqual(chunk[i].boxBottom - chunk[i].boxTop,
                           editor[i].boxBottom - editor[i].boxTop, accuracy: 2, "第 \(i) 段")
        }
    }

    // MARK: - An image follows the column

    func testImageFillsTheColumnAndStaysCentred() throws {
        let image = try imagePart()   // stored as 300 × 138
        let narrow = try XCTUnwrap(attachmentBounds(doc([body("上文"), image], width: 300)))
        let wide = try XCTUnwrap(attachmentBounds(doc([body("上文"), image], width: 600)))

        XCTAssertEqual(narrow.width, 300, accuracy: 1)
        XCTAssertEqual(wide.width, 600, accuracy: 1,
                       "列变宽时图片要跟着放大（原来停在竖屏宽度）")
        XCTAssertEqual(wide.height / wide.width, 138.0 / 300.0, accuracy: 0.01,
                       "只按存储的比例缩放")

        let rendered = doc([body("上文"), image], width: 600)
        let attachmentIndex = (rendered.string as NSString).range(of: "\u{FFFC}").location
        let style = rendered.attribute(.paragraphStyle, at: attachmentIndex,
                                       effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.alignment, .center, "图片段落居中")
    }

    func testImageStoredSizeIsAnAspectRatioNotALayoutSize() throws {
        let image = try imagePart()   // 300 × 138
        let rendered = doc([image], width: 600)
        let saved = try XCTUnwrap(PartsCodec.parts(from: rendered, typeSize: .large).first)
        XCTAssertEqual(saved.w, 300, "存储的宽度不随列宽变化")
        XCTAssertEqual(saved.h, 138)
    }

    @MainActor
    func testReaderImageFillsTheWidthItIsGiven() throws {
        let image = try imagePart()
        let view = DiaryImageView(src: try XCTUnwrap(image.src), displayW: 300, displayH: 138)
            .frame(width: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let rendered = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(rendered.size.width, 600, accuracy: 1)
        XCTAssertEqual(rendered.size.height, 600 * 138 / 300, accuracy: 1)

        // …and the picture itself reaches both edges, rather than sitting small
        // in the middle of a full-width box (that was the landscape rendering).
        let bitmap = try XCTUnwrap(readable(rendered))
        let midY = bitmap.size.height / 2
        let background = pixel(bitmap, x: 1, y: 1)
        XCTAssertNotEqual(pixel(bitmap, x: 2, y: midY), background, "左边应该有图")
        XCTAssertNotEqual(pixel(bitmap, x: bitmap.size.width - 3, y: midY), background,
                          "右边应该有图")
    }
}
