import XCTest

/// Covers the 足迹 tab that replaced the former self-drawn GeoJSON map.
///
/// The assertions are deliberately data-independent: they check the page chrome
/// and the expand/collapse interaction against whatever diaries exist in the
/// simulator, so the test does not depend on seeded content.
final class FootprintUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-tab", "footprint"]
        app.launch()
    }

    func testFootprintPageShowsStatsAndPlaceList() throws {
        XCTAssertTrue(app.staticTexts["足迹"].waitForExistence(timeout: 12),
                      "the third tab should be the 足迹 tab")

        for label in ["省市", "城市", "国家", "片段", "天数"] {
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5),
                          "stats card should show \(label)")
        }

        XCTAssertTrue(app.staticTexts["地点清单"].waitForExistence(timeout: 5),
                      "the place list section should exist")
    }

    /// The list is a recursive disclosure tree: expanding a country must reveal
    /// at least one child row. Skipped when the simulator has no located diaries.
    func testExpandingFirstPlaceRevealsChildren() throws {
        let listTitle = app.staticTexts["地点清单"]
        XCTAssertTrue(listTitle.waitForExistence(timeout: 12), "place list should exist")

        let rows = app.buttons.matching(identifier: "footprint.node")
        let hittable = rows.allElementsBoundByIndex.filter { $0.isHittable }
        guard let first = hittable.first else {
            throw XCTSkip("no located diaries in this simulator; nothing to expand")
        }

        let before = rows.count
        first.tap()
        // Give the expansion animation a moment, then assert the tree grew.
        let grew = NSPredicate { _, _ in rows.count > before }
        expectation(for: grew, evaluatedWith: NSNull(), handler: nil)
        waitForExpectations(timeout: 5)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "footprint-expanded"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
