import XCTest

/// 手机横屏的版面回归。
///
/// 竖屏的交互（年 ↔ 月 ↔ 周三态 morph）由 `MorphPerfUITests` 守住，这里只管横屏：
/// - 横屏首页是左右分栏，且**不再**重复「今天 / 年份」入口；
/// - 月历可以横向滑动翻月；
/// - 点某一天只换右栏，不改月历宽度（两栏宽度固定）。
///
/// 需要中文模拟器（元素按中文标签查找），与其它 UI 测试一致。
final class LandscapeLayoutUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    /// 当前显示的月份标题（`MonthPane` 里挂了 `home.monthTitle` 标识）。
    private func monthTitle(_ app: XCUIApplication) -> String {
        let el = app.staticTexts["home.monthTitle"].firstMatch
        return el.exists ? el.label : ""
    }

    func testLandscapeHomeSplitsAndKeepsOneTodayEntry() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-tab", "home"]
        app.launch()

        // 横屏首页左栏应显示月历标题（说明左右分栏真的生效了）
        XCTAssertTrue(app.staticTexts["home.monthTitle"].firstMatch.waitForExistence(timeout: 6),
                      "横屏首页应显示月历标题")

        // 「今天」的入口只在左栏标题行；头部那个 `InfoCapsule` 在横屏必须消失。
        // 注意 `DragPagePager` 会同时构建相邻月，所以按标签计数会是 3（当前 + 前后各一），
        // 这里断言的是「头部那个相对日期胶囊不在」（它的标签含「天前/昨天/明天」）。
        let headerCapsule = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '天前' OR label CONTAINS '昨天' OR label CONTAINS '明天'"))
        XCTAssertEqual(headerCapsule.count, 0,
                       "横屏头部不应再出现相对日期胶囊（与左栏「今天」重复）")

        // 年份入口：至少有一个（左栏标题行），且数量不应随翻月增加
        // （`DragPagePager` 会同时构建左右相邻月，所以按标签计数会大于 1，
        //  这里只保证入口存在；重复入口的问题由「今天」那一条守住。）
        let yearChips = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '2026年'"))
        XCTAssertGreaterThanOrEqual(yearChips.count, 1, "横屏左栏应有年份入口")
    }

    func testLandscapeMonthSwipesVertically() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-tab", "home"]
        app.launch()
        sleep(3)

        let before = monthTitle(app)
        XCTAssertFalse(before.isEmpty, "找不到月历标题，无法验证横向翻月")

        // 在左栏月历区域内**向上**滑 → 下一个月（与竖屏同方向）
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.72))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(2)

        XCTAssertNotEqual(monthTitle(app), before, "横屏向上滑应切换到下一个月")
    }

    func testTappingDayKeepsPaneWidthsStable() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-tab", "home"]
        app.launch()
        sleep(3)

        let calendar = app.staticTexts["home.monthTitle"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 6))
        let widthBefore = calendar.frame.width
        let originBefore = calendar.frame.minX

        // 点一个不是今天的日期（16 是今天，点 9）
        let day = app.staticTexts["9"].firstMatch
        if day.waitForExistence(timeout: 3) {
            day.tap()
            sleep(1)
        }

        let widthAfter = calendar.frame.width
        let originAfter = calendar.frame.minX
        XCTAssertEqual(widthBefore, widthAfter, accuracy: 1,
                       "点日期后月历宽度不应变化（两栏宽度固定）")
        XCTAssertEqual(originBefore, originAfter, accuracy: 1,
                       "点日期后月历不应位移")
    }
}
