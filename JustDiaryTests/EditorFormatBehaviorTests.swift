import XCTest
import UIKit
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
        XCTAssertNotNil(tv.typingAttributes[.backgroundColor],
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
        // End of the quoted text: Return continues the quote, as UIKit's own
        // newline carries the quote attributes.
        tv.selectedRange = NSRange(location: 2, length: 0)
        XCTAssertFalse(controller.handleReturn(at: 2))

        // The empty line after it is quoted (that is what Return just produced),
        // so Return again ends the quote instead of stacking another one.
        tv.selectedRange = NSRange(location: 3, length: 0)
        tv.typingAttributes = controller.typingAttributes(for: .quote)
        XCTAssertTrue(controller.handleReturn(at: 3))
        XCTAssertEqual((tv.typingAttributes[.backgroundColor] as? UIColor)?.isEqual(UIColor.clear), true,
                       "the next typed paragraph is plain again")
        XCTAssertEqual(styles(controller), [ContentPartStyle.quote],
                       "the quoted line above is untouched")
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
}
