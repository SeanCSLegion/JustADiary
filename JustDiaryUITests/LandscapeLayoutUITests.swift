import XCTest

/// 手机横屏的版面回归。
///
/// 竖屏的交互（年 ↔ 月 ↔ 周三态 morph）由 `MorphPerfUITests` 守住，这里只管横屏：
/// - 横屏首页是左右分栏，日历紧贴左侧内容边（不再重复避让安全区）；
/// - **没有年份入口**（横屏只上下滑切月，不提供点按钮切年）；
/// - 「今天」在右栏标题行；
/// - 上下滑可翻月；
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

    private func launchLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-tab", "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.monthTitle"].firstMatch.waitForExistence(timeout: 8),
                      "横屏首页应显示月历标题")
    }

    /// 当前显示的月份标题（`MonthBigTitle` 挂了 `home.monthTitle` 标识）。
    ///
    /// `DragPagePager` 会同时构建前后两页，所以同一标识会有 3 个元素；
    /// 只取真正落在屏幕顶部的那个（分页器把邻页放在 ±pageSize 处）。
    private func monthTitleElement() -> XCUIElement {
        let all = app.staticTexts.matching(identifier: "home.monthTitle")
        return all.allElementsBoundByIndex
            .first { $0.frame.minY >= 0 && $0.frame.minY < 300 } ?? all.firstMatch
    }

    private func monthTitle(_ app: XCUIApplication) -> String {
        let el = monthTitleElement()
        return el.exists ? el.label : ""
    }

    func testLandscapeHomeSplitsAndCalendarSitsAtContentEdge() throws {
        launchLandscape()

        // 横屏没有年份入口：既不该有旧的年份胶囊，也不该有头部的「‹ 2026年」。
        XCTAssertFalse(app.buttons["home.yearChip"].exists, "横屏不应再有年份入口")
        let headerBack = app.buttons["home.header.back"]
        XCTAssertFalse(headerBack.exists, "横屏分栏时整块头部应隐藏")

        // 左栏日历紧贴左侧内容边：iPhone 18 Pro 横屏安全区 leading = 62，
        // 加上 16pt 页面边距与 20pt 标题内边距，标题应在 x ≈ 98。
        // 之前重复避让了一次 62pt + 78pt，标题被推到 x ≈ 222，屏幕左半白白浪费。
        let title = monthTitleElement()
        XCTAssertLessThan(title.frame.minX, 130,
                          "月历标题应贴近左侧内容边，不应被重复的安全区避让推走")

        // 「今天」在右栏标题行，位于月历右边界之外（说明真的分了栏）。
        let today = app.buttons["home.todayChip"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 4), "横屏右栏标题行应有「今天」")
        XCTAssertGreaterThan(today.frame.minX, title.frame.maxX,
                             "「今天」应在右栏，而不是压在月历旁边")
    }

    func testLandscapeMonthSwipesVertically() throws {
        launchLandscape()
        sleep(3)

        let before = monthTitle(app)
        XCTAssertFalse(before.isEmpty, "找不到月历标题，无法验证翻月")

        // 在左栏月历区域内**向上**滑 → 下一个月（与竖屏同方向）
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.72))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(2)

        XCTAssertNotEqual(monthTitle(app), before, "横屏向上滑应切换到下一个月")
    }

    func testTappingDayKeepsPaneWidthsStable() throws {
        launchLandscape()
        sleep(3)

        let calendar = monthTitleElement()
        let widthBefore = calendar.frame.width
        let originBefore = calendar.frame.minX

        // 日期数字画在 Canvas 里，没有可点的独立元素：按坐标点月历里的一个日期。
        // 网格从 y ≈ 8（顶部留白）+ 34（标题）+ 26（星期栏）起。
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.45)).tap()
        sleep(1)

        let widthAfter = calendar.frame.width
        let originAfter = calendar.frame.minX
        XCTAssertEqual(widthBefore, widthAfter, accuracy: 1,
                       "点日期后月历宽度不应变化（两栏宽度固定）")
        XCTAssertEqual(originBefore, originAfter, accuracy: 1,
                       "点日期后月历不应位移")
    }

    /// 翻月时右栏的选中日应跟着进入新月份，否则日历上没有任何选中项。
    func testSwipingMonthKeepsSelectionVisible() throws {
        launchLandscape()
        sleep(3)

        let headingBefore = app.staticTexts["home.dayHeading"].firstMatch.label
        let before = monthTitle(app)

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.72))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(3)

        XCTAssertNotEqual(monthTitle(app), before, "向上滑应翻到下一个月")
        let headingAfter = app.staticTexts["home.dayHeading"].firstMatch.label
        XCTAssertNotEqual(headingAfter, headingBefore,
                          "翻月后右栏选中日要跟着进入新月份（否则日历上没有选中项）")
    }
}
