import XCTest

final class ImportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testImportBackup() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(3)

        // 1. Settings tab
        let settingsTab = app.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "settings tab should exist")
        settingsTab.tap()
        sleep(2)

        // 2. Scroll until import row visible, then tap
        let importPredicate = NSPredicate(format: "label CONTAINS '导入备份'")
        let importRow = app.buttons.matching(importPredicate).firstMatch
        var attempts = 0
        while !importRow.exists && attempts < 4 {
            app.swipeUp()
            sleep(1)
            attempts += 1
        }
        attach("import-row", importRow.exists ? "FOUND: \(importRow.label)" : "NOT FOUND after \(attempts) swipes")
        if importRow.exists {
            importRow.tap()
            sleep(3)
        }

        // 3. Document picker appeared?
        let sheet = app.sheets.firstMatch
        let navBar = app.navigationBars.firstMatch
        attach("after-import-tap", "sheet.exists=\(sheet.exists) navBar.exists=\(navBar.exists)\n\n" + app.debugDescription)

        // Navigate: Browse -> On My iPhone -> file
        let browse = app.buttons["浏览"]
        if browse.waitForExistence(timeout: 3) {
            browse.tap()
            sleep(1)
        }
        let onMyIPhone = app.staticTexts["我的 iPhone"]
        if onMyIPhone.exists {
            onMyIPhone.tap()
            sleep(2)
        }
        let fileCell = app.cells.containing(NSPredicate(format: "label CONTAINS 'JustDiary'")).firstMatch
        if fileCell.exists {
            fileCell.tap()
            sleep(2)
        }
        attach("after-pick", app.debugDescription)

        // 4. Import mode dialog
        let skip = app.buttons["跳过已有日记"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
            sleep(4)
        } else {
            let overwrite = app.buttons["覆盖已有日记"]
            if overwrite.exists { overwrite.tap(); sleep(4) }
        }

        // 5. Success alert
        let ok = app.buttons["知道了"]
        if ok.waitForExistence(timeout: 8) {
            ok.tap()
        }
        attach("final", app.debugDescription)
    }
}
