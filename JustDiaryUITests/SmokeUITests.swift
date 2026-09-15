import XCTest

final class SmokeUITests: XCTestCase {
    func testFootprintAndEditorSmoke() throws {
        let app = XCUIApplication()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        app.launchArguments = ["-ui-test-open-day", today]
        app.launch()
        sleep(4)

        let back = app.buttons["返回"]
        XCTAssertTrue(back.waitForExistence(timeout: 6), "editor opened with back button")
        back.tap()
        sleep(2)

        let footprintTab = app.buttons["足迹"]
        XCTAssertTrue(footprintTab.waitForExistence(timeout: 5), "footprint tab")
        footprintTab.tap()
        sleep(4)
        let stats = app.staticTexts["省市"]
        XCTAssertTrue(stats.waitForExistence(timeout: 8), "footprint stats")
    }
}
