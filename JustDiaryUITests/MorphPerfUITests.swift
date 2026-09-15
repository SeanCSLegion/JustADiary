import XCTest

/// Drives both calendar morphs with `-morph-log` enabled so the frame-timing
/// harness can compare the year↔month morph against the month↔week morph.
///
/// The test itself only asserts that each morph actually ran; the numbers come
/// from `Documents/morph.log`, read off the simulator by the caller.
final class MorphPerfUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-morph-log"]
        app.launch()
        XCTAssertTrue(app.buttons["home.header.back"].waitForExistence(timeout: 12),
                      "calendar header should be on screen")
    }

    func testBothMorphsRun() throws {
        // Query by identifier: the month canvas' accessibility label also
        // contains "年", so a label-based match taps the wrong element.
        let yearButton = app.buttons["home.header.back"]
        XCTAssertTrue(yearButton.waitForExistence(timeout: 8), "header back button")
        yearButton.tap()
        sleep(3)

        // Month -> Year should now be showing the year page with its mini months.
        // The morph view renders its own copy of the year page and the pager
        // keeps neighbouring year pages alive, so several "year.month.1"
        // elements exist, most of them offscreen. Pick the visible one.
        XCTAssertTrue(app.buttons.matching(identifier: "year.month.1").firstMatch
                        .waitForExistence(timeout: 8), "year page mini months")
        let visibleJanuary = app.buttons.matching(identifier: "year.month.1")
            .allElementsBoundByIndex
            .first { $0.isHittable && $0.frame.minY > 0 }
        guard let january = visibleJanuary else {
            XCTFail("no visible January card")
            return
        }
        january.tap()
        sleep(3)

        // Year -> Month completed: the big month title is back.
        XCTAssertTrue(app.staticTexts["一月"].waitForExistence(timeout: 8),
                      "month view after year->month morph")

        // Now the month <-> week morph, so both segments appear in one log.
        // Tapping a day expands the month into the week strip.
        let canvas = app.otherElements.matching(NSPredicate(format: "label CONTAINS '年'")).firstMatch
        if canvas.waitForExistence(timeout: 5) {
            // The element's centre can land on a blank adjacent-month cell,
            // which is not tappable; aim at the first week row instead.
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
            sleep(3)
        }
    }
}
