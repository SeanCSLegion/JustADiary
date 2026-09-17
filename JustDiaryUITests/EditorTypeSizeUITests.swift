import XCTest

/// Guards the editor's load → edit → save round trip at an accessibility text
/// size.
///
/// The editor stores a *design* block style and size — title 28 / heading 22 /
/// body 17 / quote 15, Apple's own iOS type ladder — and draws it at a size
/// resolved for the user's text-size setting. Saving re-derives each line's
/// block type, so parsing must recover the design values and not the drawn ones:
/// at the largest accessibility category a 17pt paragraph is drawn at roughly
/// 26pt, and promoting that to a heading would silently rewrite the entry.
///
/// The tests drive the real UI twice — create + save, then re-open the *rendered*
/// block and save again — because only the second save re-parses text this app
/// wrote. They assert through the `-ui-test-editor-state` probe, which reports
/// the block types (and text) the editor would persist, rather than reading the
/// app container's database.
///
/// The app must be running with the simulator in Chinese (zh-Hans) for the
/// element lookups below.
final class EditorTypeSizeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func todayKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    /// Launches on today's entry at the largest accessibility text size.
    ///
    /// `resetData` wipes the day first, so assertions do not depend on what an
    /// earlier run left behind. The location lookup is switched off: an entry
    /// saved without one now asks for confirmation, which these tests are not
    /// about.
    private func launchApp(resetData: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "-ui-test-open-day", todayKey(),
            "-ui-test-editor-state",
            "-ui-test-reset-settings",
            "-ui-test-no-autoloc",
            // Drives SwiftUI's `dynamicTypeSize` for the launched app.
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        if resetData { args.append("-ui-test-reset-data") }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func editorState(_ app: XCUIApplication) -> String {
        let probe = app.staticTexts["editor.state"]
        guard probe.waitForExistence(timeout: 6) else { return "missing" }
        return probe.label
    }

    /// Waits for the probe to report `expected` and returns the last value seen.
    private func waitForState(_ app: XCUIApplication, _ expected: String,
                              timeout: TimeInterval = 12) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = "missing"
        repeat {
            last = editorState(app)
            if last == expected { return last }
            usleep(250_000)
        } while Date() < deadline
        return last
    }

    /// Applies a paragraph style through the format bar's style menu.
    private func applyStyle(_ app: XCUIApplication, _ label: String) {
        let menu = app.buttons["段落样式"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "paragraph-style menu button")
        menu.tap()
        let button = app.buttons[label]
        if button.waitForExistence(timeout: 4) {
            button.tap()
            return
        }
        let item = app.menuItems[label]
        XCTAssertTrue(item.waitForExistence(timeout: 4), "style item \(label)")
        item.tap()
    }

    private func openWriteMode(_ app: XCUIApplication) {
        let write = app.buttons["写日记"]
        XCTAssertTrue(write.waitForExistence(timeout: 15),
                      "read view of today should offer the write action")
        write.tap()
    }

    func testBlockStylesSurviveReSaveAtLargestTextSize() throws {
        var app = launchApp(resetData: true)

        // Pass 1 — author one paragraph of every style and save it.
        openWriteMode(app)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "editor text view")
        editor.tap()
        editor.typeText("正文段落")
        editor.typeText("\n")
        editor.typeText("大标题行")
        applyStyle(app, "大标题")
        editor.typeText("\n")
        editor.typeText("小标题行")
        applyStyle(app, "小标题")
        editor.typeText("\n")
        editor.typeText("引用行")
        XCTAssertTrue(app.buttons["引用"].waitForExistence(timeout: 6), "quote action")
        app.buttons["引用"].tap()

        let authored = "body,title,heading,quote|正文段落大标题行小标题行引用行"
        XCTAssertEqual(waitForState(app, authored), authored, "authored block types")

        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 6), "save button")
        app.buttons["保存"].tap()
        XCTAssertEqual(waitForState(app, "read:body,title,heading,quote"), "read:body,title,heading,quote",
                       "saved block types")

        // Passes 2 and 3 — re-open the *saved* block (not a new one) and save it
        // again. These are what re-parse text the app itself rendered at the
        // accessibility size, and repeating them catches a design size that
        // drifts a little on each round trip instead of flipping the type on the
        // first one.
        for pass in 2...3 {
            app.terminate()
            app = launchApp()
            XCTAssertEqual(waitForState(app, "read:body,title,heading,quote"), "read:body,title,heading,quote",
                           "saved block types (pass \(pass))")

            let block = app.textViews.firstMatch
            XCTAssertTrue(block.waitForExistence(timeout: 10), "rendered block (pass \(pass))")
            block.tap()
            XCTAssertEqual(waitForState(app, authored), authored,
                           "re-opened block kept its styles and text (pass \(pass))")

            XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 6), "save button (pass \(pass))")
            app.buttons["保存"].tap()
            XCTAssertEqual(waitForState(app, "read:body,title,heading,quote"), "read:body,title,heading,quote",
                           "same styles after the re-save (pass \(pass))")
        }
    }

    /// E4: the input area is a minimum of 160pt at the default text size and
    /// grows on the body style's Dynamic Type curve, so the placeholder no
    /// longer takes up most of the field at accessibility sizes.
    func testInputAreaGrowsWithTextSize() throws {
        let normal = try emptyEditorFrame(contentSizeCategory: nil)
        let largest = try emptyEditorFrame(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertEqual(normal.height, 160, accuracy: 1,
                       "the default input height is the design's 160pt")
        XCTAssertGreaterThan(largest.height, normal.height * 1.4,
                             "input area must grow with the text size (was \(normal.height) → \(largest.height))")
    }

    /// A block saved without a location stays without one: only a *new* block
    /// looks a location up, so re-opening it later offers no way to add one.
    func testEntrySavedWithoutLocationCannotGainOne() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", todayKey(), "-ui-test-reset-data",
                               "-ui-test-reset-settings", "-ui-test-no-location",
                               "-ui-test-editor-state"]
        app.launch()

        openWriteMode(app)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "editor text view")
        editor.tap()
        editor.typeText("没有位置")

        let save = app.buttons["保存"]
        XCTAssertTrue(save.waitForExistence(timeout: 6), "save button")
        save.tap()
        // Saving an entry that never got a location asks first, because the
        // decision cannot be taken back afterwards.
        let confirm = app.buttons["仍然保存"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "save-without-location confirmation")
        confirm.tap()
        XCTAssertEqual(waitForState(app, "read:body"), "read:body", "entry was saved")

        let block = app.textViews.firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 10), "rendered block")
        block.tap()
        XCTAssertTrue(app.staticTexts["未记录地点"].waitForExistence(timeout: 10),
                      "the location row reports that nothing was recorded")
        XCTAssertFalse(app.buttons["选择地点"].exists, "no precision menu without a location")
        XCTAssertFalse(app.staticTexts["重新获取位置"].exists,
                       "editing an existing block must not look a location up")
    }

    private func emptyEditorFrame(contentSizeCategory: String?) throws -> CGRect {
        let app = XCUIApplication()
        var args = ["-ui-test-open-day", todayKey(), "-ui-test-reset-data",
                    "-ui-test-reset-settings", "-ui-test-no-autoloc"]
        if let contentSizeCategory {
            args += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        app.launchArguments = args
        app.launch()
        openWriteMode(app)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "editor text view")
        return editor.frame
    }

    func testDiscardChangesRestoresSavedContent() throws {
        let app = launchApp(resetData: true)

        openWriteMode(app)
        var editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "editor text view")
        editor.tap()
        editor.typeText("第一稿")
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 6), "save button")
        app.buttons["保存"].tap()
        XCTAssertEqual(waitForState(app, "read:body"), "read:body", "saved paragraph")

        // Re-open the block, add to it, then discard: the editor must come back
        // to exactly what was saved. The action used to discard the whole edit
        // silently, under an undo arrow labelled "Redo". (Re-opening places the
        // caret at the start of the entry, so the new text is prepended.)
        let block = app.textViews.firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 10), "rendered block")
        block.tap()
        editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "re-opened editor")
        editor.typeText("改变")
        XCTAssertEqual(waitForState(app, "body|改变第一稿"), "body|改变第一稿", "edited content")

        let discard = app.buttons["放弃修改"]
        XCTAssertTrue(discard.waitForExistence(timeout: 6), "discard action")
        discard.tap()
        let confirm = app.buttons["放弃"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "discard confirmation")
        confirm.tap()
        XCTAssertEqual(waitForState(app, "body|第一稿"), "body|第一稿",
                       "discard must restore the saved content")
    }
}
