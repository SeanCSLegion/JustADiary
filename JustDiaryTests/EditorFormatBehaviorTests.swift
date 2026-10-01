import XCTest
import UIKit
import SwiftUI
@testable import JustDiary

/// Pins the *scope* of every format-bar button: what a tap changes, how far it
/// reaches, and what "cancel" does.
///
/// The rules are written down in `docs/editor-format-behaviors.md` (R1–R4).
/// These run the real `RichEditorController` against a real `UITextView`, which
/// is where the scope bugs lived:
///
/// * a caret at a line start used to restyle the line *above* it (B1/B2),
/// * center / list / to-do ignored a multi-line selection (B3/B4),
/// * a mixed selection was toggled run by run, half on and half off (B5),
/// * list and to-do did not continue on Return, while quote did (B6).
final class EditorFormatBehaviorTests: XCTestCase {

    private let marker = "\u{FFFC}"

    @discardableResult
    private func makeEditor(_ parts: [ContentPart]) -> (RichEditorController, UITextView) {
        let controller = RichEditorController()
        let tv = UITextView()
        controller.textView = tv
        controller.load(parts: parts)
        return (controller, tv)
    }

    private func styles(_ controller: RichEditorController) -> [String] {
        controller.currentParts().map(\.style)
    }

    private func typingDesignSize(_ tv: UITextView) -> CGFloat? {
        EditorFont.designSize(of: tv.typingAttributes)
    }

    private func body(_ text: String) -> ContentPart {
        ContentPart(style: ContentPartStyle.body, runs: [TextRun(text: text)])
    }

    private func line(_ style: String, _ text: String) -> ContentPart {
        ContentPart(style: style, runs: [TextRun(text: text)])
    }

    /// One flag per character, so an assertion does not depend on how the codec
    /// grouped the runs: two runs that end up with identical attributes come
    /// back as a single run.
    private func perCharacter(_ part: ContentPart?, _ flag: (TextRun) -> Bool) -> [Bool] {
        (part?.runs ?? []).flatMap { run in Array(repeating: flag(run), count: run.text.count) }
    }

    // MARK: - B1 / B2: a new line never rewrites the line above it

    func testStyleMenuOnEmptyLineLeavesPreviousLineAlone() {
        let (controller, tv) = makeEditor([line(ContentPartStyle.title, "标题")])
        XCTAssertEqual(tv.textStorage.string, "标题\n", "a loaded paragraph ends with a newline")

        // The caret sits on the empty line Return has just opened.
        tv.selectedRange = NSRange(location: 3, length: 0)
        controller.applyBlockStyle(.heading)

        XCTAssertEqual(styles(controller), [ContentPartStyle.title],
                       "picking a style on an empty line must not restyle the paragraph above")
        XCTAssertEqual(typingDesignSize(tv), EditorBlockStyle.heading.designSize,
                       "…it must still describe what is typed next")
    }

    func testCaretAtLineStartStylesOnlyThatLine() {
        let (controller, tv) = makeEditor([body("第一行"), body("第二行")])
        XCTAssertEqual(tv.textStorage.string, "第一行\n第二行\n")

        tv.selectedRange = NSRange(location: 4, length: 0) // start of 第二行
        controller.applyBlockStyle(.title)

        XCTAssertEqual(styles(controller), [ContentPartStyle.body, ContentPartStyle.title])
    }

    func testQuoteCancelOnNewLineKeepsPreviousQuote() {
        let (controller, tv) = makeEditor([line(ContentPartStyle.quote, "甲"),
                                           line(ContentPartStyle.quote, "乙")])
        XCTAssertEqual(tv.textStorage.string, "甲\n乙\n")

        // Second quoted line: tapping quote again cancels that line only.
        tv.selectedRange = NSRange(location: 2, length: 0)
        controller.toggleQuote()

        XCTAssertEqual(styles(controller), [ContentPartStyle.quote, ContentPartStyle.body],
                       "cancelling on the new line must leave the quote above it alone")
    }

    func testQuoteOnEmptyLineLeavesPreviousLineAlone() {
        let (controller, tv) = makeEditor([line(ContentPartStyle.quote, "引用")])
        tv.selectedRange = NSRange(location: 3, length: 0)
        controller.toggleQuote()

        XCTAssertEqual(styles(controller), [ContentPartStyle.quote])
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote,
                       "the next typed paragraph is what changes")
    }

    // MARK: - R2: a selection styles every line it touches

    func testSelectionStylesEverySelectedLine() {
        let (controller, tv) = makeEditor([body("甲"), body("乙")])
        tv.selectedRange = NSRange(location: 0, length: 4)
        controller.applyBlockStyle(.title)
        XCTAssertEqual(styles(controller), [ContentPartStyle.title, ContentPartStyle.title])
    }

    // MARK: - B3: center

    func testCenterAppliesToEverySelectedLine() {
        let (controller, tv) = makeEditor([body("甲"), body("乙")])
        tv.selectedRange = NSRange(location: 0, length: 4)
        controller.toggleCenter()

        XCTAssertEqual(controller.currentParts().map(\.align), ["center", "center"])
    }

    func testCenterOnEmptyLineOnlyChangesTypingAttributes() {
        let (controller, tv) = makeEditor([body("甲")])
        tv.selectedRange = NSRange(location: 2, length: 0)
        controller.toggleCenter()

        XCTAssertNil(controller.currentParts().first?.align,
                     "an empty line has no text to center")
        XCTAssertEqual((tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment, .center)
    }

    // MARK: - B4 / R3: list and to-do markers

    func testListToggleAppliesToEverySelectedLine() {
        let (controller, tv) = makeEditor([body("甲"), body("乙")])
        tv.selectedRange = NSRange(location: 0, length: 4)
        controller.toggleList()

        let parts = controller.currentParts()
        XCTAssertEqual(parts.count, 1, "consecutive items stay one list part: \(parts)")
        XCTAssertEqual(parts.first?.style, ContentPartStyle.list)
        XCTAssertEqual(parts.first?.items, ["甲", "乙"])
    }

    func testListToggleOffOnNewLineKeepsPreviousItem() {
        let (controller, tv) = makeEditor([ContentPart(style: ContentPartStyle.list, items: ["甲", "乙"])])
        XCTAssertEqual(tv.textStorage.string, "\(marker)甲\n\(marker)乙\n")

        // Caret on the second item's line start: cancelling drops one marker.
        tv.selectedRange = NSRange(location: 3, length: 0)
        controller.toggleList()

        let parts = controller.currentParts()
        XCTAssertEqual(parts.map(\.style), [ContentPartStyle.list, ContentPartStyle.body])
        XCTAssertEqual(parts.first?.items, ["甲"], "the item above keeps its marker")
    }

    func testListAndTodoSwapInPlace() {
        let (controller, tv) = makeEditor([ContentPart(style: ContentPartStyle.list, items: ["甲"])])
        tv.selectedRange = NSRange(location: 1, length: 0)
        controller.toggleTodo()

        XCTAssertEqual(styles(controller), [ContentPartStyle.todo])
        XCTAssertEqual(controller.currentParts().first?.items, ["甲"])
    }

    // MARK: - B6: Return continues the line style, an empty item ends it

    func testReturnOnListItemStartsANewItem() {
        let (controller, tv) = makeEditor([ContentPart(style: ContentPartStyle.list, items: ["甲"])])
        XCTAssertEqual(tv.textStorage.string, "\(marker)甲\n")

        tv.selectedRange = NSRange(location: 2, length: 0) // end of the item's text
        XCTAssertTrue(controller.handleReturn(at: 2))

        // A newline plus the marker slot in before the item's own terminating
        // newline: the next line is an item of the same kind.
        XCTAssertEqual(tv.textStorage.string, "\(marker)甲\n\(marker)\n",
                       "a new item carries the same marker")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 4, length: 0),
                       "the caret lands after the new marker")
        XCTAssertEqual(styles(controller), [ContentPartStyle.list])

        // Return again on the empty item ends the list: the marker goes, and the
        // line stays behind as a plain blank one.
        XCTAssertTrue(controller.handleReturn(at: 4))
        XCTAssertEqual(tv.textStorage.string, "\(marker)甲\n\n")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 3, length: 0))
    }

    func testReturnOnTodoItemStartsAnUndoneItem() {
        let (controller, tv) = makeEditor([ContentPart(style: ContentPartStyle.todo,
                                                       items: ["做"], done: [true])])
        XCTAssertEqual(tv.textStorage.string, "\(marker)做\n")

        tv.selectedRange = NSRange(location: 2, length: 0)
        XCTAssertTrue(controller.handleReturn(at: 2))

        let payload = (tv.textStorage.attribute(.attachment, at: 3, effectiveRange: nil) as? PayloadAttachment)?.payload
        XCTAssertEqual(payload?.kind, "todo")
        XCTAssertEqual(payload?.done, false, "a new to-do item starts undone")
    }

    func testReturnOutsideALineStyleIsLeftToUIKit() {
        let (controller, tv) = makeEditor([body("甲")])
        tv.selectedRange = NSRange(location: 1, length: 0)
        XCTAssertFalse(controller.handleReturn(at: 1),
                       "a plain paragraph's Return is not intercepted")
        XCTAssertEqual(tv.textStorage.string, "甲\n")
    }

    func testReturnOnAnEmptyQuotedLineEndsTheQuote() {
        let (controller, tv) = makeEditor([line(ContentPartStyle.quote, "引用")])
        // End of the quoted text: Return opens the next line as a quote too — the
        // editor inserts that newline itself (`handleReturn`), because UIKit's
        // own one only inherits `typingAttributes`, where the block type is gone.
        tv.selectedRange = NSRange(location: 2, length: 0)
        XCTAssertTrue(controller.handleReturn(at: 2), "引用行的回车由编辑器处理")

        // The line after it is quoted, so Return again ends the quote instead of
        // stacking another one.
        tv.selectedRange = NSRange(location: 3, length: 0)
        XCTAssertTrue(controller.handleReturn(at: 3))
        XCTAssertNotEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote,
                          "the next typed paragraph is plain again")
        XCTAssertEqual(styles(controller), [ContentPartStyle.quote],
                       "the quoted line above is untouched")
    }

    // MARK: - B29: 引用换行 = 新行**接着引用**（不是「顶着引用缩进的正文」）

    /// 引用行上回车：新行要是**真的引用** —— 块类型、字号、段落几何三样都得跟上。
    ///
    /// 改动前这里交给 UIKit 的换行：它只继承 `typingAttributes`，而 UIKit 会把
    /// `.diaryBlockStyle` 抹掉 —— 新行只剩「15pt + 引用的缩进」，底色没了、引用按钮
    /// 灭了，再回车还是这份缩进（用户报的 bug）。
    func testReturnOnAQuotedLineContinuesTheQuote() {
        let (controller, tv) = makeEditor([line(ContentPartStyle.quote, "甲")])
        XCTAssertEqual(tv.textStorage.string, "甲\n")

        tv.selectedRange = NSRange(location: 1, length: 0) // 引用文字末尾
        XCTAssertTrue(controller.handleReturn(at: 1), "引用行的回车由编辑器处理")

        XCTAssertEqual(tv.textStorage.string, "甲\n\n", "在光标处插入一个换行")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 2, length: 0), "光标落在新行行首")
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote,
                       "之后输入的文字还是引用")
        XCTAssertEqual(typingDesignSize(tv), EditorDesignSize.quote, "字号也是引用那一档")
        XCTAssertEqual((tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? -1,
                       BlockMetrics.quoteTextInset(.large), accuracy: 0.01,
                       "新行让开左侧竖条（它确实是引用）")
        // 新行自己的那个换行符也要是引用：空行的行盒与底色块都看它（B22）。
        XCTAssertEqual(EditorFont.blockStyle(of: tv.textStorage.attributes(at: 2, effectiveRange: nil)),
                       .quote)

        tv.insertText("乙")
        XCTAssertEqual(styles(controller), [ContentPartStyle.quote, ContentPartStyle.quote],
                       "接着输入的字落在新的引用行上")
    }

    /// 光标在引用行**中间**回车：拆出来的两段都还是引用。
    func testReturnInTheMiddleOfAQuoteKeepsBothHalvesQuoted() {
        let (controller, tv) = makeEditor([line(ContentPartStyle.quote, "甲乙")])
        tv.selectedRange = NSRange(location: 1, length: 0)
        XCTAssertTrue(controller.handleReturn(at: 1))
        XCTAssertEqual(tv.textStorage.string, "甲\n乙\n")

        tv.insertText("丙")
        XCTAssertEqual(tv.textStorage.string, "甲\n丙乙\n")
        XCTAssertEqual(styles(controller), [ContentPartStyle.quote, ContentPartStyle.quote])
    }

    /// **有选区**时回车：这个回车是替换选区。自己插换行的那两条路径（引用 / 列表）
    /// 不把编辑交回 UIKit，所以选中的文字得由它们删掉 —— 否则新行会插在选中文字中间。
    func testReturnWithASelectionReplacesIt() {
        let (controller, tv) = makeEditor([line(ContentPartStyle.quote, "甲乙丙")])
        XCTAssertTrue(controller.handleReturn(in: NSRange(location: 1, length: 1)))
        XCTAssertEqual(tv.textStorage.string, "甲\n丙\n", "选中的「乙」被一个换行替换")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 2, length: 0), "光标落在新行行首")
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote)
        XCTAssertEqual(styles(controller), [ContentPartStyle.quote, ContentPartStyle.quote])

        let (listController, listTV) = makeEditor([ContentPart(style: ContentPartStyle.list, items: ["甲乙"])])
        XCTAssertTrue(listController.handleReturn(in: NSRange(location: 1, length: 1)))
        XCTAssertEqual(listTV.textStorage.string, "\(marker)\n\(marker)乙\n",
                       "列表项：选中的「甲」被「换行 + 标记」替换，剩下的「乙」还在自己的项里")
        XCTAssertEqual(listController.currentParts().first?.items, ["乙"])
    }

    /// 空行上只有一个换行符可选：真选了就交回 UIKit（替换换行符 = 并段），
    /// 编辑器不认领这一次回车。
    func testReturnWithASelectionOnAnEmptyQuotedLineIsLeftToUIKit() {
        let (controller, tv) = makeEditor([line(ContentPartStyle.quote, "甲"), body("乙")])
        tv.textStorage.insert(NSAttributedString(string: "\n",
                                                 attributes: controller.typingAttributes(for: .quote)),
                              at: 2)
        XCTAssertEqual(tv.textStorage.string, "甲\n\n乙\n")

        XCTAssertFalse(controller.handleReturn(in: NSRange(location: 2, length: 1)))
        XCTAssertEqual(tv.textStorage.string, "甲\n\n乙\n", "文本没被改动")
    }

    /// 用户的复现路径：新日记 → 点引用 → 输入 → 回车（新行还是引用）→ 再回车
    /// （空引用行上结束引用，缩进跟着回到列首）。
    func testTypingInAQuoteAndPressingReturnTwiceEndsItOnAPlainLine() {
        let (controller, tv) = makeEditor([])
        controller.toggleQuote()
        tv.insertText("甲")
        XCTAssertEqual(styles(controller), [ContentPartStyle.quote])

        XCTAssertTrue(controller.handleReturn(at: 1))
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote,
                       "回车之后新行仍是引用（不是只剩缩进的正文）")

        XCTAssertTrue(controller.handleReturn(at: tv.selectedRange.location))
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .body,
                       "空引用行上再回车 = 结束引用")
        XCTAssertEqual((tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? -1, 0,
                       "结束引用之后不该还留着引用的缩进")

        tv.insertText("乙")
        XCTAssertEqual(styles(controller), [ContentPartStyle.quote, ContentPartStyle.body])
    }

    /// UIKit 每次移动光标都会按光标处的文字重算 `typingAttributes`，而它只认自己认识
    /// 的键：`.diaryBlockStyle` / `.diaryDesignSize` 会被抹掉。抹掉之后引用就只剩
    /// 「15pt + 缩进」，所以光标一落定就要按**光标所在那一段**把块类型补回来。
    func testResyncRestoresTheBlockTypeUIKitDrops() {
        let (controller, tv) = makeEditor([body("甲"), line(ContentPartStyle.quote, "乙")])
        XCTAssertEqual(tv.textStorage.string, "甲\n乙\n")

        // UIKit 重算之后的打字态：只剩字号与段落几何，没有自定义键。
        func dropCustomKeys() {
            var typing = tv.typingAttributes
            typing.removeValue(forKey: .diaryBlockStyle)
            typing.removeValue(forKey: .diaryDesignSize)
            tv.typingAttributes = typing
        }

        tv.selectedRange = NSRange(location: 2, length: 0) // 引用行（有文字）
        dropCustomKeys()
        controller.resyncBlockAttributesWithCaret()
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote)
        XCTAssertEqual(typingDesignSize(tv), EditorDesignSize.quote)

        // 文末那条空行没有自己的字符：它的样式由上一段延续（UIKit 自己也是这么推导的），
        // 所以「引用行下面那一条空行」也还是引用。
        tv.selectedRange = NSRange(location: 4, length: 0)
        dropCustomKeys()
        controller.resyncBlockAttributesWithCaret()
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote)
        XCTAssertTrue(controller.isQuoteActive(), "引用按钮在这条空行上也要保持选中")

        // 正文行上不会被误判成引用。
        tv.selectedRange = NSRange(location: 0, length: 0)
        dropCustomKeys()
        controller.resyncBlockAttributesWithCaret()
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .body)
    }

    /// 文档中间那条空引用行（样式写在它自己的换行符上，B22）在光标落上去之后也要
    /// 认得出自己是引用 —— 否则在它上面回车既结束不了引用，还会再续一份缩进。
    func testResyncReadsAnEmptyQuotedLineFromItsOwnNewline() {
        let (controller, tv) = makeEditor([body("甲"), body("乙")])
        tv.textStorage.insert(NSAttributedString(string: "\n",
                                                 attributes: controller.typingAttributes(for: .quote)),
                              at: 2)
        XCTAssertEqual(tv.textStorage.string, "甲\n\n乙\n")

        tv.selectedRange = NSRange(location: 2, length: 0)
        tv.typingAttributes = controller.typingAttributes(for: .body) // UIKit 抹掉键之后的样子
        controller.resyncBlockAttributesWithCaret()
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote)
        XCTAssertTrue(controller.isQuoteActive())
        XCTAssertTrue(controller.handleReturn(at: 2), "空引用行上的回车被吃掉（结束引用）")
    }

    /// 在续出来的空引用行上**取消引用 → 输入文字 → 再把文字删掉**：这一行还是正文。
    ///
    /// 文末那条空行没有自己的字符，样式只活在 `typingAttributes` 里；UIKit 每次光标 /
    /// 文字变化都会按**上一段的换行符**重算那份字典、把块类型抹掉 —— 于是取消掉的引用
    /// 自己又回来了（用户报的）。所以编辑器为这一行记一份「用户最后挑的样式」。
    func testCancelledQuoteOnTheTrailingEmptyLineDoesNotComeBack() {
        let (controller, tv) = makeEditor([])
        controller.toggleQuote()
        tv.insertText("甲")
        XCTAssertTrue(controller.handleReturn(at: 1), "回车：新行接着引用")
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .quote)

        controller.toggleQuote() // 在这条空引用行上取消引用
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .body)

        tv.insertText("乙")
        controller.resyncBlockAttributesWithCaret() // 真实链路里由光标变化回调调
        XCTAssertEqual(styles(controller), [ContentPartStyle.quote, ContentPartStyle.body])

        tv.deleteBackward()
        controller.resyncBlockAttributesWithCaret()
        XCTAssertEqual(tv.textStorage.string, "甲\n")
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .body,
                       "取消掉的引用不该因为把字删掉又回来")
        XCTAssertFalse(controller.isQuoteActive(), "引用按钮也不该自己亮起来")
        XCTAssertEqual((tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? -1, 0,
                       "也不该留下引用的缩进")
    }

    /// 文末那条空行接着**列表 / 待办**时：块类型是正文，但 UIKit 从上一段的换行符推出
    /// 的段落几何还带着标记的悬挂缩进（18 / 26pt）与更小的段距 —— 在那里打字得到的是
    /// 正文，折行却缩进 18pt、段间距也不对。按块类型重排一遍。
    func testResyncDropsTheMarkerIndentFromTheTrailingEmptyLine() {
        let (controller, tv) = makeEditor([ContentPart(style: ContentPartStyle.list, items: ["甲"])])
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
        // UIKit 在光标移动时按上一段的换行符重算：段落样式就是标记那一份。
        tv.typingAttributes = controller.markerTypingAttributes(kind: "bullet")
        XCTAssertEqual((tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0,
                       BlockMetrics.markerIndent(kind: "bullet", .large), accuracy: 0.01,
                       "前提：这份打字态带着标记的悬挂缩进")

        controller.resyncBlockAttributesWithCaret()
        let fixed = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(EditorFont.blockStyle(of: tv.typingAttributes), .body, "这一行是正文")
        XCTAssertEqual(fixed?.headIndent ?? -1, 0, accuracy: 0.01, "正文没有悬挂缩进")
        XCTAssertEqual(fixed?.firstLineHeadIndent ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(fixed?.paragraphSpacingBefore ?? -1,
                       EditorBlockStyle.body.paragraphSpacingBefore, accuracy: 0.01,
                       "段前距也回到正文的（不是标记那种更小的）")
    }

    // MARK: - B5 / R1: character styles

    func testBoldTurnsOnForWholeMixedSelection() {
        let (controller, tv) = makeEditor([
            ContentPart(style: ContentPartStyle.body,
                        runs: [TextRun(text: "普通"), TextRun(text: "粗", bold: true)])
        ])
        tv.selectedRange = NSRange(location: 0, length: 3)
        controller.toggleBold()

        XCTAssertEqual(perCharacter(controller.currentParts().first) { $0.bold == true },
                       [true, true, true],
                       "a mixed selection turns the trait on everywhere, not half and half")
    }

    func testBoldTurnsOffForWholeSelection() {
        let (controller, tv) = makeEditor([
            ContentPart(style: ContentPartStyle.body,
                        runs: [TextRun(text: "粗", bold: true), TextRun(text: "也粗", bold: true)])
        ])
        tv.selectedRange = NSRange(location: 0, length: 3)
        controller.toggleBold()

        XCTAssertEqual(perCharacter(controller.currentParts().first) { $0.bold == true },
                       [false, false, false])
    }

    func testStrikeTurnsOnForWholeSelection() {
        let (controller, tv) = makeEditor([
            ContentPart(style: ContentPartStyle.body,
                        runs: [TextRun(text: "甲"), TextRun(text: "乙", strike: true)])
        ])
        tv.selectedRange = NSRange(location: 0, length: 2)
        controller.toggleStrike()

        XCTAssertEqual(perCharacter(controller.currentParts().first) { $0.strike == true },
                       [true, true])
    }

    func testCaretOnlyChangesTypingAttributes() {
        let (controller, tv) = makeEditor([body("abc")])
        tv.selectedRange = NSRange(location: 3, length: 0)
        controller.toggleBold()

        XCTAssertNil(controller.currentParts().first?.runs?.first?.bold,
                     "text that is already there is never rewritten")
        let typingFont = tv.typingAttributes[.font] as? UIFont
        XCTAssertEqual(typingFont?.fontDescriptor.symbolicTraits.contains(.traitBold), true,
                       "the next typed characters are bold instead")
    }

    func testSelectionSurvivesAFormatToggle() {
        let (controller, tv) = makeEditor([body("abcd")])
        tv.selectedRange = NSRange(location: 1, length: 2)
        controller.toggleItalic()

        XCTAssertEqual(tv.selectedRange, NSRange(location: 1, length: 2),
                       "formatting must not collapse the selection the user made")
    }

    func testMixedSelectionReportsNoActiveTrait() {
        let (controller, tv) = makeEditor([
            ContentPart(style: ContentPartStyle.body,
                        runs: [TextRun(text: "普通"), TextRun(text: "粗", bold: true)])
        ])
        tv.selectedRange = NSRange(location: 0, length: 3)
        XCTAssertFalse(controller.activeStyles().bold,
                       "the button must agree with what a tap would do")

        tv.selectedRange = NSRange(location: 2, length: 1)
        XCTAssertTrue(controller.activeStyles().bold)
    }

    // MARK: - B9: an empty item is not storage

    func testMarkerWithoutTextIsNotPersisted() {
        let (controller, tv) = makeEditor([ContentPart(style: ContentPartStyle.list, items: ["甲"])])
        tv.selectedRange = NSRange(location: 2, length: 0)
        controller.handleReturn(at: 2) // "• 甲\n• " — an item the user has not typed in yet

        let parts = controller.currentParts()
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?.items, ["甲"], "the empty item is not written to storage")
    }

    func testTrailingMarkerIsNotPersisted() {
        let (controller, tv) = makeEditor([body("甲")])
        tv.selectedRange = NSRange(location: 2, length: 0)
        controller.toggleList()
        XCTAssertEqual(tv.textStorage.string, "甲\n\(marker)")

        XCTAssertEqual(styles(controller), [ContentPartStyle.body],
                       "a marker on a line with nothing else is not an item")
    }

    // MARK: - B10: a width change keeps uncommitted edits

    func testRefitImagesLeavesTextAndCaretAlone() {
        let (controller, tv) = makeEditor([body("甲"), body("乙")])
        tv.selectedRange = NSRange(location: 3, length: 0)
        controller.refitImages(maxWidth: 200)

        XCTAssertEqual(tv.textStorage.string, "甲\n乙\n")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 3, length: 0))
    }

    // MARK: - 编辑区里换上的行样式 = 重新打开时排出来的那一个

    /// 样式按钮换掉的是**行样式**，它的行距 / 段前距 / 段后距必须和
    /// `PartsCodec`（重新打开这篇日记时的排版）算出的一模一样。
    ///
    /// 段前距以前漏了：编辑区里点「大标题」得到的行没有标题的段前留白（当时是
    /// 9.8pt，现行模型是 0.55 × 28 = 15.4），而保存后重新打开却带着 ——
    /// 同一条标题在两条链路上长得不一样。
    func testStyleAppliedInTheEditorMatchesALoadedOne() {
        for block in EditorBlockStyle.allCases {
            let (controller, tv) = makeEditor([body("甲")])
            tv.selectedRange = NSRange(location: 0, length: 0)
            controller.applyBlockStyle(block)

            let applied = tv.textStorage.attribute(.paragraphStyle, at: 0,
                                                   effectiveRange: nil) as? NSParagraphStyle
            let loaded = PartsCodec
                .attributedString(from: [line(block.partStyle, "甲")], typeSize: .large)
                .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

            XCTAssertEqual(applied?.lineSpacing ?? -1, loaded?.lineSpacing ?? -2, accuracy: 0.01,
                           "\(block.rawValue) 行距")
            XCTAssertEqual(applied?.paragraphSpacing ?? -1, loaded?.paragraphSpacing ?? -2, accuracy: 0.01,
                           "\(block.rawValue) 段后距")
            XCTAssertEqual(applied?.paragraphSpacingBefore ?? -1,
                           loaded?.paragraphSpacingBefore ?? -2, accuracy: 0.01,
                           "\(block.rawValue) 段前距")
        }
    }
}
