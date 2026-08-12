import XCTest

final class TempVerifyUITests: XCTestCase {

    private func save(_ shot: XCUIScreenshot, _ name: String) {
        let url = URL(fileURLWithPath: "/tmp/jd_\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }

    func testStrip() throws {
        let app = XCUIApplication()
        app.launch()
        _ = app.buttons.firstMatch.waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        // open day mode (tap Aug 11)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.21, dy: 0.41)).tap()
        Thread.sleep(forTimeInterval: 1.0)
        save(XCUIScreen.main.screenshot(), "s1_day")
        // strip swipe left
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.25))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)),
                   withVelocity: .fast, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 1.2)
        save(XCUIScreen.main.screenshot(), "s2_swiped")
        // strip swipe right (back)
        let from2 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25))
        from2.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.25)),
                    withVelocity: .fast, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 1.2)
        save(XCUIScreen.main.screenshot(), "s3_swiped_back")
    }
}
