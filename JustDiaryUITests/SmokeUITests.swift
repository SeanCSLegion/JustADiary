import XCTest

final class SmokeUITests: XCTestCase {
    func testMapAndEditorSmoke() throws {
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

        let mapTab = app.buttons["地图"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 5), "map tab")
        mapTab.tap()
        sleep(4)
        let stats = app.staticTexts["省市"]
        XCTAssertTrue(stats.waitForExistence(timeout: 8), "map stats")
    }
}
