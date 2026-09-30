import XCTest
import UIKit
import SwiftUI
@testable import JustDiary

/// 光标停在**空行**上时，格式按钮落在这条空行上吗？
///
/// 空段落没有字形，但它的行盒是排出来的：段落样式取段落第一个字符（实测见
/// `docs/editor-typography.md` §5.2），空段落的第一个字符就是它自己的换行符 ——
/// 所以「只改 typingAttributes」的空行会停在旧样式里：取消居中了光标还在中间、开启居中
/// 了光标还在左边；引用把行首标记摘掉时，光标还会被夹到下一行去。
///
/// 这些断言量的是**真实排版**（`caretRect(for:)`），不是只看属性：用户看到的就是
/// 光标的位置。
final class EditorEmptyLineTests: XCTestCase {

    private let marker = "\u{FFFC}"
    private var window: UIWindow!
    private var tv: UITextView!
    private var controller: RichEditorController!

    override func setUpWithError() throws {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let vc = UIViewController()
        window.rootViewController = vc
        window.makeKeyAndVisible()
        tv = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        vc.view.addSubview(tv)
        controller = RichEditorController()
        controller.textView = tv
        tv.becomeFirstResponder()
        layout()
    }

    private func layout() {
        window.layoutIfNeeded()
        tv.layoutIfNeeded()
    }

    private func caretRect() -> CGRect {
        tv.caretRect(for: tv.selectedTextRange?.end ?? tv.endOfDocument)
    }

    private func body(_ text: String) -> ContentPart {
        ContentPart(style: ContentPartStyle.body, runs: [TextRun(text: text)])
    }

    private func list(_ items: [String]) -> ContentPart {
        ContentPart(style: ContentPartStyle.list, items: items)
    }

    private func paragraphStyle(at location: Int) -> NSParagraphStyle? {
        tv.textStorage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    /// 这一段是不是引用。判据是块类型（`.diaryBlockStyle`）：引用不再靠
    /// `.backgroundColor` 标记，底色改由 `DiaryTextView` 的装饰层画在文字后面。
    private func isQuoted(at location: Int) -> Bool {
        EditorFont.blockStyle(of: tv.textStorage.attributes(at: location, effectiveRange: nil)) == .quote
    }

    // MARK: - 居中：空行本身要跟着动

    /// 文本中间的空行（自己带换行符的那种）：开启居中光标要移到列中间，取消要回到左边。
    func testCenterOnAnEmptyLineInTheMiddleMovesTheCaret() {
        controller.load(parts: [body("甲"), body(""), body("乙")])
        XCTAssertEqual(tv.textStorage.string, "甲\n\n乙\n")

        // 光标在中间那条空行上（它自己的换行符在 offset 2）。
        tv.selectedRange = NSRange(location: 2, length: 0)
        layout()
        XCTAssertEqual(caretRect().minX, 0, accuracy: 0.5, "空行未居中时光标应在行首")

        controller.toggleCenter()
        layout()
        XCTAssertEqual(paragraphStyle(at: 2)?.alignment, .center,
                       "空行自己的换行符也要居中，否则光标不跟着走")
        XCTAssertGreaterThan(caretRect().minX, 100,
                             "空行居中后光标应移到列中间（实际 x=\(caretRect().minX)）")
        XCTAssertEqual(paragraphStyle(at: 0)?.alignment, .left, "上一行不受影响")
        XCTAssertEqual(paragraphStyle(at: 3)?.alignment, .left, "下一行不受影响")

        controller.toggleCenter()
        layout()
        XCTAssertEqual(caretRect().minX, 0, accuracy: 0.5, "取消居中后光标应回到行首")
        XCTAssertEqual(paragraphStyle(at: 2)?.alignment, .left)
    }

    /// 文本末尾那条空行（没有自己的字符）由 `typingAttributes` 排版 —— 这条链路本来就
    /// 对，用例守住它别被改坏。
    func testCenterOnTheLastEmptyLineMovesTheCaret() {
        controller.load(parts: [body("甲")])
        tv.selectedRange = NSRange(location: 2, length: 0)
        layout()
        XCTAssertEqual(caretRect().minX, 0, accuracy: 0.5)

        controller.toggleCenter()
        layout()
        XCTAssertGreaterThan(caretRect().minX, 100, "末行居中后光标应移到列中间")

        controller.toggleCenter()
        layout()
        XCTAssertEqual(caretRect().minX, 0, accuracy: 0.5, "取消后回到行首")
    }

    // MARK: - 引用：摘掉行首标记后，这一行还是光标所在的行

    /// 新写的日记：列表项 → 回车 → 空项上点引用。
    func testQuoteOnAMarkerOnlyItemKeepsTheCaretOnThatLine() {
        controller.load(parts: [])
        tv.becomeFirstResponder()
        controller.toggleList()
        tv.insertText("甲")
        XCTAssertEqual(tv.textStorage.string, marker + "甲")
        XCTAssertTrue(controller.handleReturn(at: tv.selectedRange.location))
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n" + marker)

        controller.toggleQuote()
        layout()
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n", "空项的标记被摘掉")
        XCTAssertEqual(tv.selectedRange.location, 3, "光标应停在这一行（不是被夹到文本末尾之外）")
        // 光标矩形比行盒起点左半个光标宽，所以容差给到 2pt（正文行是 0，两者差得开）。
        XCTAssertEqual(caretRect().minX, BlockMetrics.quoteTextInset(.large), accuracy: 2,
                       "引用正文让开左侧竖条，光标落在缩进处")

        tv.insertText("引")
        layout()
        XCTAssertEqual(controller.currentParts().map(\.style),
                       [ContentPartStyle.list, ContentPartStyle.quote],
                       "接着输入的字落在引用行上")
        XCTAssertEqual(controller.currentParts().last?.runs?.first?.text, "引")
    }

    /// 重新打开一篇日记：存储末尾带换行，空项是「标记 + 换行」，光标更容易被夹到下一行。
    func testQuoteOnAMarkerOnlyItemInAReopenedEntryKeepsTheCaretOnThatLine() {
        controller.load(parts: [list(["甲"])])
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n")

        tv.selectedRange = NSRange(location: 2, length: 0) // 项文字末尾
        XCTAssertTrue(controller.handleReturn(at: 2))
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n" + marker + "\n")
        XCTAssertEqual(tv.selectedRange.location, 4)

        controller.toggleQuote()
        layout()
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n\n")
        XCTAssertEqual(tv.selectedRange.location, 3,
                       "标记被摘掉后光标要留在这一行（改动前是 4，即被推到文本末尾那条空段落）")
        // 光标矩形比行盒起点左半个光标宽，所以容差给到 2pt（正文行是 0，两者差得开）。
        XCTAssertEqual(caretRect().minX, BlockMetrics.quoteTextInset(.large), accuracy: 2,
                       "引用正文让开左侧竖条，光标落在缩进处")
        XCTAssertTrue(isQuoted(at: 3), "这一行自己也要变成引用行")

        tv.insertText("引")
        layout()
        XCTAssertEqual(controller.currentParts().map(\.style),
                       [ContentPartStyle.list, ContentPartStyle.quote])
    }

    /// 列表项夹在正文中间：引用只改这一行，上一行与下一行都不动。
    func testQuoteOnAMarkerOnlyItemInTheMiddleLeavesBothNeighboursAlone() {
        controller.load(parts: [list(["甲"]), body("乙")])
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n乙\n")

        tv.selectedRange = NSRange(location: 2, length: 0)
        XCTAssertTrue(controller.handleReturn(at: 2))
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n" + marker + "\n乙\n")
        XCTAssertEqual(tv.selectedRange.location, 4)

        controller.toggleQuote()
        layout()
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n\n乙\n")
        XCTAssertEqual(tv.selectedRange.location, 3, "光标留在引用这一行，不掉到「乙」行首")
        XCTAssertFalse(isQuoted(at: 4), "下一行不能被带上引用")
        XCTAssertTrue(isQuoted(at: 3))

        tv.insertText("引")
        layout()
        XCTAssertEqual(controller.currentParts().map(\.style),
                       [ContentPartStyle.list, ContentPartStyle.quote, ContentPartStyle.body],
                       "输入的字落在引用行上，上一行还是列表、下一行还是正文")
    }

    /// 空行上直接点引用（没有标记要摘）：空行自己就该变成引用行。
    func testQuoteOnAnEmptyMiddleLineStylesThatLine() {
        controller.load(parts: [body("甲"), body(""), body("乙")])
        tv.selectedRange = NSRange(location: 2, length: 0)
        layout()

        controller.toggleQuote()
        layout()
        XCTAssertTrue(isQuoted(at: 2), "空行自己也要变成引用行")
        XCTAssertEqual(caretRect().minX, BlockMetrics.quoteTextInset(.large), accuracy: 2,
                       "引用是左对齐，光标落在引用的文字缩进处（让开竖条）")
        XCTAssertFalse(isQuoted(at: 0))
        XCTAssertFalse(isQuoted(at: 3))

        controller.toggleQuote()
        layout()
        XCTAssertFalse(isQuoted(at: 2), "取消后这一行要跟着变回正文")
    }

    /// 空引用行上回车 = 结束引用：这一行自己也要恢复成正文，不能只改打字态。
    func testReturnOnAnEmptyQuotedLineAlsoClearsTheLineItself() {
        controller.load(parts: [body("甲"), body("乙")])
        // 造一条空引用行：把引用属性的换行符插在「甲」和「乙」之间。
        tv.textStorage.insert(NSAttributedString(string: "\n",
                                                 attributes: controller.typingAttributes(for: .quote)),
                              at: 2)
        tv.selectedRange = NSRange(location: 2, length: 0)
        tv.typingAttributes = controller.typingAttributes(for: .quote)
        layout()
        XCTAssertEqual(tv.textStorage.string, "甲\n\n乙\n")
        XCTAssertTrue(isQuoted(at: 2), "空行此刻是引用行")
        XCTAssertTrue(controller.isQuoteActive())

        XCTAssertTrue(controller.handleReturn(at: 2), "空引用行上的回车被吃掉（结束引用）")
        layout()
        XCTAssertFalse(isQuoted(at: 2), "结束引用后这一行自己的底色也要去掉")
    }

    // MARK: - 选区：摘掉标记不能让选区「长大」

    /// 选中两行列表项（选区到第二个标记为止，不含它的文字）点引用：两个标记都被摘掉，
    /// 选区应当跟着缩短 —— 而不是留在原来的 offset 上，把没收进来的文字也圈进去。
    func testQuoteOnASelectionOfItemsKeepsTheSelectionOffUntouchedText() {
        controller.load(parts: [list(["甲"]), list(["乙"])])
        XCTAssertEqual(tv.textStorage.string, marker + "甲\n" + marker + "乙\n")

        // 从第一个标记选到第二个标记之前（0..<4，不含「乙」）。
        tv.selectedRange = NSRange(location: 0, length: 4)
        controller.toggleQuote()
        layout()

        XCTAssertEqual(tv.textStorage.string, "甲\n乙\n", "两行的标记都被摘掉")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 2),
                       "选区要缩短到真正选中的两个字（改动前会涨到 0..<4，把「乙\n」也圈进去）")
    }

    // MARK: - 居中：选区覆盖的空行也要一起改

    /// 两条一模一样的空行在同一次「居中」里必须得到同样的结果。
    func testCenterAppliesToEveryEmptyLineCoveredByTheSelection() {
        controller.load(parts: [body("甲"), body(""), body("乙"), body(""), body("丙")])
        XCTAssertEqual(tv.textStorage.string, "甲\n\n乙\n\n丙\n")

        // 选中间那条空行 + 「乙」+ 第二条空行（offset 2..<6）。
        tv.selectedRange = NSRange(location: 2, length: 4)
        controller.toggleCenter()
        layout()

        XCTAssertEqual(paragraphStyle(at: 2)?.alignment, .center, "第一条空行要居中")
        XCTAssertEqual(paragraphStyle(at: 5)?.alignment, .center, "第二条空行也要居中")
        XCTAssertEqual(paragraphStyle(at: 3)?.alignment, .center, "「乙」行居中")
        XCTAssertEqual(paragraphStyle(at: 0)?.alignment, .left, "选区外的行不动")
    }

    // MARK: - 样式菜单：空行上换样式不该把居中丢掉

    /// 居中可以与标题 / 正文共存，只有引用强制左对齐 —— 空行上也要遵守同一条规则。
    func testApplyingAStyleToACenteredEmptyLineKeepsItCentered() {
        controller.load(parts: [body("甲"), body(""), body("乙")])
        tv.selectedRange = NSRange(location: 2, length: 0)
        controller.toggleCenter()
        layout()
        XCTAssertEqual(paragraphStyle(at: 2)?.alignment, .center)
        XCTAssertGreaterThan(caretRect().minX, 100, "空行居中后光标在列中间")

        controller.applyBlockStyle(.heading)
        layout()
        XCTAssertEqual(paragraphStyle(at: 2)?.alignment, .center, "换小标题不该把这一行的居中丢掉")
        XCTAssertGreaterThan(caretRect().minX, 100, "光标仍在该行中间")
        XCTAssertEqual(EditorFont.designSize(of: tv.textStorage.attributes(at: 2, effectiveRange: nil)),
                       EditorDesignSize.h2, "字号已经是小标题")

        controller.toggleQuote()
        layout()
        XCTAssertEqual(paragraphStyle(at: 2)?.alignment, .left, "引用强制左对齐")
    }

    // MARK: - 图片行：居中也要跳过

    /// 图片段落的对齐由编解码决定（`imageParagraphStyle()` 恒为居中）：选区里带上它时
    /// 不该把它改成左对齐 —— 那种状态保存后就没了，阅读区也还是居中。
    func testCenterSkipsAnImageParagraphCoveredByTheSelection() {
        controller.load(parts: [body("甲"), body("乙")])
        // 造一条图片行（图片文件取不到也不影响排版：占位与尺寸照留）。
        let attachment = PayloadAttachment(payload: AttachmentPayload(src: "missing.jpg",
                                                                     w: 100, h: 50, kind: "image"))
        attachment.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        let imageLine = NSMutableAttributedString(attachment: attachment)
        imageLine.addAttribute(.paragraphStyle, value: PartsCodec.imageParagraphStyle(),
                               range: NSRange(location: 0, length: imageLine.length))
        imageLine.append(NSAttributedString(string: "\n"))
        tv.textStorage.insert(imageLine, at: 2)
        XCTAssertEqual(tv.textStorage.string, "甲\n\u{FFFC}\n乙\n")

        // 光标在图片行上（它此刻是居中的），选中它以确定方向：取消居中。
        tv.selectedRange = NSRange(location: 2, length: 3)
        controller.toggleCenter()
        layout()

        XCTAssertEqual(paragraphStyle(at: 2)?.alignment, .center, "图片行必须保持居中")
        XCTAssertEqual(paragraphStyle(at: 4)?.alignment, .left, "选区里的正文行照常取消居中")
    }
}
