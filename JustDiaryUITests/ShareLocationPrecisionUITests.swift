import XCTest

/// 分享位置精度：默认值、可选级别（**只能**是隐藏 / 区县 / 城市 / 省份）、跨重启的持久化。
///
/// 这条用例守住的是用户看得见的那一半：设置里给不出「精确地点」与「街道」，
/// 因为分享长图根本不会输出这两级（逻辑在 `LocationPrecisionTests`）。
/// 需要中文模拟器（元素按中文标签查找），与其它 UI 测试一致。
final class ShareLocationPrecisionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-reset-settings", "-ui-test-tab", "settings"]
        app.launch()
        XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 12),
                      "设置页应以中文打开")
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    /// 「分享位置精度」那一行（标题 + 当前值 + 打开菜单）。
    private var shareRow: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "分享位置精度")).firstMatch
    }

    /// 设置页的规则卡片在首屏之下，元素存在但不可点 —— 往下滑到它能点为止。
    @discardableResult
    private func scrollToShareRow() -> XCUIElement {
        for _ in 0..<6 {
            if shareRow.exists, shareRow.isHittable { return shareRow }
            app.swipeUp()
        }
        return shareRow
    }

    func testSharePrecisionOffersOnlyHideDistrictCityProvinceAndPersists() throws {
        let row = scrollToShareRow()
        XCTAssertTrue(row.waitForExistence(timeout: 8), "设置里应有「分享位置精度」一项")
        XCTAssertEqual(row.value as? String, "区县", "默认分享到区县")
        // 留一张设置行的样子：说明在标准字号下必须**一行**放得下
        // （`SettingsTests.testSettingsRowDescriptionsFitOneLine` 盯着字数与宽度）。
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "share-loc-row"
        shot.lifetime = .keepAlways
        add(shot)

        row.tap()
        // 四个可选项都在。
        for title in ["隐藏", "区县", "城市", "省份"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5),
                          "菜单里应有「\(title)」")
        }
        // 精确地点与街道在分享里不可选（这是这次改动的硬要求）。
        for forbidden in ["精确地点", "街道"] {
            XCTAssertFalse(app.buttons[forbidden].exists,
                           "分享菜单里不该出现「\(forbidden)」")
        }

        app.buttons["隐藏"].tap()
        XCTAssertEqual(row.value as? String, "隐藏", "选完立刻显示新值")

        // 重启后仍然是「隐藏」（设置写在 App Group 的 UserDefaults 里）。
        app.terminate()
        app.launchArguments = ["-ui-test-tab", "settings"]
        app.launch()
        let rowAfterRestart = scrollToShareRow()
        XCTAssertTrue(rowAfterRestart.waitForExistence(timeout: 12))
        XCTAssertEqual(rowAfterRestart.value as? String, "隐藏", "重启后仍保持隐藏")
    }
}
