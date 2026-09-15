import XCTest

/// Guards the editor's load → edit → save round trip at an accessibility text
/// size.
///
/// The editor stores a *design* font size (22 / 18 / 15 / 13) and draws it at a
/// size resolved for the user's text-size setting. Saving re-derives each line's
/// block type from that stored size, so parsing must recover the design size and
/// not the drawn one: at the largest accessibility category a 15pt paragraph is
/// drawn at roughly 26pt, and reading that back would classify it as a heading
/// (h1) and silently rewrite the entry.
///
/// The test drives the real UI twice — create + save, then edit + save again —
/// because only the second save re-parses text this app wrote. It deliberately
/// does not assert on the database; `JustDiary/Resources` has no test hook for
/// that, so the accompanying verification step reads `edit_block.content_json`
/// from the simulator container and checks the paragraph is still a paragraph.
final class EditorTypeSizeUITests: XCTestCase {

    private func launchApp(day: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-test-open-day", day,
            // Drives SwiftUI's `dynamicTypeSize` for the launched app.
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        return app
    }

    func testParagraphSurvivesReSaveAtLargestTextSize() throws {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        // Pass 1 — write a paragraph and save it.
        var app = launchApp(day: today)
        XCTAssertTrue(app.buttons["写日记"].waitForExistence(timeout: 12),
                      "read view of today should offer the write action")
        app.buttons["写日记"].tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8), "editor text view")
        editor.tap()
        editor.typeText("字号往返校验")

        let save = app.buttons["保存"]
        XCTAssertTrue(save.waitForExistence(timeout: 6), "save button")
        save.tap()
        sleep(3)

        // Passes 2 and 3 — reopen, edit and save again. These are what re-parse
        // text the app itself rendered at the accessibility size. Repeating it
        // also catches a size that drifts a little on each round trip instead of
        // flipping the block type on the first one.
        for pass in 2...3 {
            app.terminate()
            app = launchApp(day: today)
            XCTAssertTrue(app.buttons["写日记"].waitForExistence(timeout: 12),
                          "saved entry should be editable again (pass \(pass))")
            app.buttons["写日记"].tap()

            let reopened = app.textViews.firstMatch
            XCTAssertTrue(reopened.waitForExistence(timeout: 8), "editor text view (pass \(pass))")
            reopened.tap()
            reopened.typeText("二")
            let saveAgain = app.buttons["保存"]
            XCTAssertTrue(saveAgain.waitForExistence(timeout: 6), "save button (pass \(pass))")
            saveAgain.tap()
            sleep(3)
        }

        XCTAssertTrue(app.buttons["返回"].exists, "editor still usable after the re-saves")
    }
}
