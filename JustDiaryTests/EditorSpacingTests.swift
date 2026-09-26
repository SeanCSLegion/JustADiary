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

    func testHeadingSpacingIsFartherAboveThanBelow() {
        for style in [EditorBlockStyle.title, .heading] {
            XCTAssertGreaterThan(style.paragraphSpacingBefore, style.paragraphSpacing,
                                 "\(style) 应离上文远、离下文近")
            XCTAssertGreaterThan(style.paragraphSpacing, 0, "\(style) 下面也要留一点")
        }
        XCTAssertEqual(EditorBlockStyle.body.paragraphSpacingBefore, 0, accuracy: 0.01)
        XCTAssertEqual(EditorBlockStyle.body.paragraphSpacing, 0, accuracy: 0.01)
        XCTAssertEqual(EditorBlockStyle.quote.paragraphSpacingBefore,
                       EditorBlockStyle.quote.paragraphSpacing, accuracy: 0.01,
                       "引用块上下留白对称")
    }

    func testLineSpacingGrowsWithTheStyle() {
        // lineSpacing separates wrapped lines *inside* one paragraph, and it is
        // deliberately proportional to the style's size.
        XCTAssertEqual(EditorBlockStyle.quote.lineSpacing, EditorDesignSize.quote * 0.5, accuracy: 0.01)
        for style in [EditorBlockStyle.title, .heading, .body] {
            XCTAssertEqual(style.lineSpacing, style.designSize * 0.13, accuracy: 0.01)
        }
        XCTAssertGreaterThan(EditorBlockStyle.quote.lineSpacing, EditorBlockStyle.body.lineSpacing)
    }

    func testBodyParagraphsAddNothingBeyondALineAdvance() {
        let rows = paragraphs(doc([body("正文一"), body("正文二")]))
        XCTAssertEqual(rows.count, 2)
        let advance = rows[1].inkTop - rows[0].inkTop
        // Same font above and below: the ink-to-ink advance is the line box,
        // which already carries the style's own lineSpacing.
        XCTAssertEqual(advance, rows[0].boxBottom - rows[0].boxTop, accuracy: 0.5,
                       "两段正文之间只有正常行距，没有额外段距")
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

    func testImageGetsTheSameRoomAboveAndBelow() throws {
        let image = try imagePart()
        let rows = paragraphs(doc([body("正文一"), image, body("正文二")]))
        XCTAssertEqual(rows.count, 3)

        let imageRow = rows[1]
        XCTAssertEqual(imageRow.inkBottom - imageRow.inkTop, 138 * width / 300, accuracy: 1,
                       "图片行就是图片本身的高度（按列宽等比缩放）")
        XCTAssertEqual(imageRow.inkTop - imageRow.boxTop, EditorDesignSize.imageSpacing, accuracy: 0.5,
                       "图片上方：原来是 0，图片直接贴着上一行")
        XCTAssertEqual(imageRow.boxBottom - imageRow.inkBottom, EditorDesignSize.imageSpacing, accuracy: 0.5,
                       "图片下方：原来是 0")
    }

    func testImageSpacingScalesWithTheTextSize() {
        // Design points, resolved through the text-size ladder like everything
        // else in the editor.
        XCTAssertEqual(EditorDesignSize.imageSpacing, EditorDesignSize.body * 0.6, accuracy: 0.01)
    }

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

        // insertImage lays the picture out at the text view's own width.
        let expectedHeight = CGFloat(320 - 24) * 80 / 120
        let rows = paragraphs(tv.textStorage)
        XCTAssertEqual(rows.count, 2, "正文 / 图片（结尾空行不算一段）")
        XCTAssertEqual(rows[1].inkBottom - rows[1].inkTop, expectedHeight, accuracy: 1,
                       "刚插入的图片行就是图片高度（旧实现给它套了正文段落的属性）")
        XCTAssertEqual(rows[1].inkTop - rows[1].boxTop, EditorDesignSize.imageSpacing, accuracy: 0.5)
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
        let withTitle = paragraphs(PartsCodec.readerChunk(from: [body("上文"),
                                                                line(ContentPartStyle.title, "大标题")]))
        let plain = paragraphs(doc([body("上文"), body("大标题")]))
        XCTAssertEqual(withTitle.count, 2)

        // TextKit folds the paragraph spacing into the paragraph's own line box,
        // so the title's box is taller than a body box by exactly the two gaps.
        let titleBox = withTitle[1].boxBottom - withTitle[1].boxTop
        let plainBox = plain[1].boxBottom - plain[1].boxTop
        // (The trimmed final paragraph rounds a hair differently from the
        // editor's, which keeps its terminating newline.)
        XCTAssertEqual(titleBox - plainBox,
                       EditorBlockStyle.title.paragraphSpacingBefore + EditorBlockStyle.title.paragraphSpacing,
                       accuracy: 2,
                       "块内的段距与编辑区一致")
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
