import XCTest

/// 手机竖屏首页的版面回归：年历 / 月历都必须在**底部系统浮条之上**结束。
///
/// 竖屏几何因为 `HomeView` 的 `.ignoresSafeArea(edges: .bottom)` 一直延伸到屏幕底边，
/// 而浮条**悬在内容之上**（竖屏 `safeArea.bottom` 只有 home indicator 的 34pt，
/// `app.tabBars` frame 实测 `(0, 791, 402, 83)`）。所以底部要让出的 83pt 必须在日历区
/// 的高度里自己减掉 —— 修之前 `h = 几何高 − 64`：18 Pro 竖屏上的六行月格底边正好落在
/// 屏底 y 874、年历最后一行卡片 709→874，而浮条从 y 791 起，两者的最后一整行日期
/// 都被浮条压住（came in as「首页年视图 / 月视图日期被底部导航栏遮挡」）。
///
/// 年历页的四行卡片**正好铺满**日历区（`CalendarLayout.yearCardSize` 就是按容器高
/// 反推的：4 行 + 3 个间隙 + 标题 = 容器高），所以「最后一行迷你月落在浮条之上」
/// 等价于「整个日历区落在浮条之上」；月视图与它共用同一个日历区高度。
///
/// 需要中文模拟器（元素按中文标签查找），与其它 UI 测试一致。
final class PortraitLayoutUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    /// 竖屏首页 + 底部浮条的 frame（用来判定「有没有被遮挡」）。
    @discardableResult
    private func launchPortraitHome() -> CGRect {
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-tab", "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.monthTitle"].firstMatch.waitForExistence(timeout: 10),
                      "竖屏首页应显示月历标题")
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "找不到底部浮条，无法判定遮挡")
        return bar.frame
    }

    /// 屏内（整块可见）的元素 —— 年历分页器会同时构建前后两页，同一个标识会有 3 个元素，
    /// 直接 `firstMatch` 可能拿到被推到屏幕外的邻页（与
    /// `LandscapeLayoutUITests.monthTitleElement` 同一个坑）。
    private func onScreenElements(_ identifier: String) -> [XCUIElement] {
        let screen = app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(identifier: identifier)
            .allElementsBoundByIndex
            .filter { $0.frame.minY >= -1 && $0.frame.maxY <= screen.maxY }
    }

    /// 年历里的某个迷你月（`YearPageView.miniMonth` 挂了 `year.month.N` 标识）。
    private func miniMonth(_ month: Int) -> XCUIElement {
        let id = "year.month.\(month)"
        let onScreen = onScreenElements(id)
        if let first = onScreen.first { return first }
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 日历标题。`home.monthTitle` 唯一属于连续月历流的钉住标题（morph 层不再挂它），
    /// 所以直接点名即可 —— 不必去多个同名元素里筛帧（那种筛法会在 morph 收尾时撞上
    /// 「元素已不在快照里」）。
    private func monthTitle() -> XCUIElement { app.staticTexts["home.monthTitle"] }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testYearViewLastRowEndsAboveTheTabBar() throws {
        let bar = launchPortraitHome()
        attachScreenshot("portrait-month")

        // 左上角「‹ 2026年」胶囊 → 年历（缩放 morph）
        app.buttons["home.header.back"].tap()

        let december = miniMonth(12)
        XCTAssertTrue(december.waitForExistence(timeout: 6), "点年份胶囊后应进入年历")
        sleep(1)  // 等 morph 收尾，量到的才是真实年历的 frame
        attachScreenshot("portrait-year")

        // 末行三个月（10 / 11 / 12）必须整块在浮条顶边之上。
        for month in [10, 11, 12] {
            let card = miniMonth(month)
            XCTAssertTrue(card.exists, "年历应有 \(month) 月")
            XCTAssertLessThanOrEqual(card.frame.maxY, bar.minY + 0.5,
                                     "\(month) 月卡片底边 \(card.frame.maxY) 越过了浮条顶边 \(bar.minY)")
        }

        // 年历第一行也必须还在屏内（别为了避让底部把整块推到屏幕外）。
        let january = miniMonth(1)
        XCTAssertTrue(january.exists, "年历应有 1 月")
        XCTAssertGreaterThan(january.frame.minY, 0, "年历第一行不该被顶到屏幕外")
    }

    /// 月视图：六行月份（2026 年 8 月）也落在浮条之上。
    ///
    /// 日期画在 `Canvas` 里、没有可量的元素，所以这里量的是**同一个日历区**的年历末行
    /// （见类型注释），并通过「点 8 月回到月视图」确认这条切换路径没有被这次改动影响。
    func testSixRowMonthSitsAboveTheTabBar() throws {
        let bar = launchPortraitHome()
        let before = monthTitle().label
        XCTAssertFalse(before.isEmpty, "找不到月历标题")

        app.buttons["home.header.back"].tap()
        XCTAssertTrue(miniMonth(8).waitForExistence(timeout: 6), "点年份胶囊后应进入年历")
        sleep(1)
        XCTAssertLessThanOrEqual(miniMonth(12).frame.maxY, bar.minY + 0.5,
                                 "年历末行越过了浮条顶边 \(bar.minY)")

        // 年历 → 点 8 月 → 回到月视图（morph）。
        miniMonth(8).tap()
        XCTAssertTrue(monthTitle().waitForExistence(timeout: 6), "点迷你月后应回到月视图")
        sleep(1)
        attachScreenshot("portrait-month-6rows")
        let after = monthTitle().label
        XCTAssertNotEqual(after, before, "点 8 月后标题应变成 8 月")
        XCTAssertTrue(after.contains("八") || after.contains("8") || after.contains("Aug"),
                      "应停在 8 月，实际标题是「\(after)」")
    }
}
