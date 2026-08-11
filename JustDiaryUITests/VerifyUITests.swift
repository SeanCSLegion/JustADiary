import XCTest

final class VerifyUITests: XCTestCase {
    func testRowsClickable() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        let settingsTab = app.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()
        sleep(2)

        var report = ""
        let langRow = app.buttons.matching(NSPredicate(format: "label CONTAINS '语言'")).firstMatch
        report += "LANG: hittable=\(langRow.isHittable)\n"
        if langRow.isHittable {
            langRow.tap()
            sleep(1)
            report += "  after: busy=\(app.staticTexts["语言行被点击"].exists)\n"
        }

        let weekRow = app.buttons.matching(NSPredicate(format: "label CONTAINS '一周从哪一天开始'")).firstMatch
        report += "WEEK: exists=\(weekRow.exists) hittable=\(weekRow.isHittable)\n"
        if weekRow.isHittable {
            weekRow.tap()
            sleep(1)
            report += "  after: busy=\(app.staticTexts["周起始行被点击"].exists)\n"
        }
        let a1 = XCTAttachment(string: report)
        a1.name = "rows"
        a1.lifetime = .keepAlways
        add(a1)
    }
}
