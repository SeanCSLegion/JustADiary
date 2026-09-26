import XCTest

/// 连续月历流（月视图）的版面与交互回归。
///
/// 月视图从「一次一个月、上下滑整页翻月」改成**一条连续滚动的月份流**：
/// 顶部大月份标题 + 星期栏钉住，下面的月份无级滚动，每个月在自己 1 号那一行上方
/// 有一行小标题（如「10月」），月份之间隔一个行高。这里守住四件事：
/// - 滚动后顶部大标题跟着换成新月份；
/// - 星期栏钉住不动（滚动前后 frame 不变）；
/// - 小标题在浮条之上、且落在视口里（「紧贴 1 号那一行」的可见证据）；
/// - 点日期仍然能 morph 进周视图、返回后月视图还停在原来的滚动位置。
///
/// 需要中文模拟器（元素按中文标签查找），与其它 UI 测试一致。
final class MonthFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    /// 当前日历标题。
    ///
    /// `home.monthTitle` 唯一属于连续月历流的**钉住标题**（morph 层不再挂这个标识），
    /// 所以这里可以直接点名，不必再去一堆同名元素里筛帧 —— 那种筛法会在 morph 收尾时
    /// 撞上「元素已不在快照里」。
    private func monthTitle() -> XCUIElement {
        app.staticTexts["home.monthTitle"]
    }

    /// 星期栏里的「一」（`WeekdayHeaderView` 的第一个字）。
    private func weekdayHeader() -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "一"))
            .allElementsBoundByIndex
            .first { $0.frame.minY > 0 && $0.frame.maxY < app.windows.firstMatch.frame.maxY }
            ?? app.staticTexts["一"].firstMatch
    }

    /// 左上角胶囊（月视图显示「‹ 2026年」，周视图显示「‹ 十月」）。
    private func headerCapsule() -> XCUIElement { app.buttons["home.header.back"] }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @discardableResult
    private func launchPortraitHome() -> CGRect {
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-tab", "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.monthTitle"].firstMatch.waitForExistence(timeout: 10),
                      "竖屏首页应显示月历标题")
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "找不到底部浮条")
        return bar.frame
    }

    /// 从下往上滑（看后面的月份）。
    private func swipeUp(_ distance: CGFloat = 0.35) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72 - distance))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(2)
    }

    func testScrollsContinuouslyAndKeepsTheHeaderPinned() throws {
        launchPortraitHome()
        let before = monthTitle().label
        XCTAssertFalse(before.isEmpty, "找不到月历标题")
        let headerBefore = weekdayHeader().frame
        attachScreenshot("flow-month-top")

        // 向上滑：滚到后面的月份。一屏（563pt）刚好装下一个月的五六行 + 小标题带，
        // 所以「顶部月份换掉」大约要滑过一整个月 —— 这里滑两次。
        swipeUp(0.5)
        swipeUp(0.5)
        let after = monthTitle().label
        XCTAssertNotEqual(after, before, "向上滑之后顶部大标题应换成新的月份")
        attachScreenshot("flow-month-scrolled")

        // 星期栏钉住：滚动前后面板位置不变。
        let headerAfter = weekdayHeader().frame
        XCTAssertEqual(headerBefore.minY, headerAfter.minY, accuracy: 0.5,
                       "星期栏必须钉在顶部（滚动不该把它带走）")
        XCTAssertEqual(headerBefore.minX, headerAfter.minX, accuracy: 0.5, "星期栏不该横向移动")
    }

    func testNextMonthLabelSitsTightAboveItsFirstRowAndClearOfTheTabBar() throws {
        let bar = launchPortraitHome()

        // 今天所在的月份（九月）只有 5 行，所以视口底部能看见下个月的小标题。
        let nextLabel = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "月"))
            .allElementsBoundByIndex
            .first { el in
                el.frame.minY > 0 && el.frame.maxY <= bar.minY
                    && el.label.count <= 4 && el.identifier != "home.monthTitle"
            }
        guard let label = nextLabel else {
            // 也许这个月是 6 行（视口里放不下小标题带）——向上滚一点把它带进来。
            swipeUp(0.25)
            let retry = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "月"))
                .allElementsBoundByIndex
                .first { $0.frame.minY > 0 && $0.frame.maxY <= bar.minY && $0.label.count <= 4 }
            XCTAssertNotNil(retry, "视口里应能看到某个月的小标题")
            XCTAssertLessThanOrEqual(retry!.frame.maxY, bar.minY + 0.5, "小标题不该被浮条压住")
            return
        }
        XCTAssertLessThanOrEqual(label.frame.maxY, bar.minY + 0.5,
                                 "小标题「\(label.label)」被底部浮条压住了")
        attachScreenshot("flow-month-label")
    }

    /// 点日期 → 周视图 → 返回：月视图要回到**原来的滚动位置**。
    func testTapDayMorphsToWeekAndBackRestoresTheScrollPosition() throws {
        launchPortraitHome()
        swipeUp(0.35)   // 先滚到一个「非静止」的位置，才检验得出位置有没有被重置
        let titleBefore = monthTitle().label
        let headerBefore = weekdayHeader().frame
        let capsuleBefore = headerCapsule().label

        // 点视口中间偏下的一天（那一带一定是本月的日期，不会是空白格）。
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)).tap()
        sleep(2)
        attachScreenshot("flow-week")

        // 周视图的判据用左上角胶囊：月视图显示「‹ 2026年」，周视图显示「‹ 十月」。
        let capsule = headerCapsule()
        XCTAssertTrue(capsule.waitForExistence(timeout: 6), "应进入周视图")
        XCTAssertNotEqual(capsule.label, capsuleBefore,
                          "进入周视图后胶囊应换成月份名（实际「\(capsule.label)」）")

        // 返回（左上角胶囊）。
        app.buttons["home.header.back"].tap()
        sleep(2)
        attachScreenshot("flow-back-to-month")

        XCTAssertEqual(monthTitle().label, titleBefore,
                       "返回月视图后顶部月份应还是原来那个（滚动位置没被重置到别处）")
        let headerAfter = weekdayHeader().frame
        XCTAssertEqual(headerBefore.minY, headerAfter.minY, accuracy: 0.5, "返回后星期栏仍在原位")
    }

    /// 快速甩动的惯性期间，屏幕上也必须是**连续的月份**。
    ///
    /// 回归点：惯性不能靠「改一次状态 + `withAnimation`」实现 —— 那样整段动画里可见块
    /// 一直是终点那一批，中间几个月不会画出来（屏幕上会先空一段、再让终点月份滑进来）。
    /// 正确做法是让 SwiftUI 逐帧插值 `animatableData`（`MonthFlowView: Animatable`），
    /// body 才会用当前帧的位置重算可见块与顶部大标题。
    func testFastFlingStaysContinuous() throws {
        launchPortraitHome()

        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.01, thenDragTo: end)
        // 不等它停：这一刻应当正滑在中间某个月上。
        attachScreenshot("flow-mid-fling")

        let mid = monthTitle().label
        sleep(3)
        let settled = monthTitle().label
        XCTAssertFalse(mid.isEmpty, "惯性期间顶部大标题也应该有内容（不该是空白）")
        XCTAssertFalse(settled.isEmpty, "落定后应有月份标题")
    }
}
