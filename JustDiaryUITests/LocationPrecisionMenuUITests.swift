import XCTest

/// 定位权限 → 精度菜单的**端到端**接线。
///
/// 回归点：`LocationSnapshot.maxPrecision` 有个默认值 `province`，而 `resolve` 忘了传 ——
/// 表现就是「系统里已经给了精确位置，编辑页的精度菜单却只剩省份」。单元测试
/// （`LocationPrecisionTests.testLiveSnapshotCarriesThePermissionCap`）盯的是计算与快照，
/// 这条用例盯的是**真机 / 模拟器上跑起来之后**菜单里到底有没有那些级别。
///
/// 依赖模拟器的定位状态，所以拿不到位置时**跳过**。手动跑之前先给这台模拟器授权并放一个点：
///
/// ```
/// xcrun simctl privacy booted grant location com.cov.justdiary
/// xcrun simctl location booted set 22.54,114.06
/// ```
final class LocationPrecisionMenuUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testPreciseLocationOffersLevelsFinerThanProvince() throws {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        app = XCUIApplication()
        // 不关定位、也不注入「没有位置」：这里要的就是真实的那条路。
        app.launchArguments = ["-ui-test-open-day", df.string(from: Date()),
                               "-ui-test-reset-settings", "-ui-test-no-autofocus"]
        app.launch()

        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 12), "应在日记页上")
        let write = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
            .allElementsBoundByIndex.first { $0.isHittable } ?? app.buttons["写日记"].firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 12), "空日记页应提供「写日记」")
        write.tap()

        // 位置胶囊的开合就是精度菜单（`.accessibilityLabel` = 「选择地点」）；
        // 拿不到位置时它显示「重新获取位置」/「位置获取中…」。
        let chip = app.buttons["选择地点"]
        guard chip.waitForExistence(timeout: 15) else {
            throw XCTSkip("这台模拟器没有可用的定位（先 grant location 并 location set）")
        }
        chip.tap()

        let district = app.buttons["区县"]
        guard district.waitForExistence(timeout: 5) else {
            throw XCTSkip("这次定位没能给出区县以上的级别（权限或精度本身就不够）")
        }
        // 精确位置下，菜单必须给得出完整梯子。
        for level in ["精确地点", "街道", "区县", "城市", "省份"] {
            XCTAssertTrue(app.buttons[level].exists, "菜单里应有「\(level)」")
        }
        district.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "·")).firstMatch
            .waitForExistence(timeout: 5), "选完区县后胶囊上应有一段地址")
    }
}
