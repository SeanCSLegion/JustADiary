import XCTest

/// 日记页的进入 / 退出方式。
///
/// 回归点：它以前是 `fullScreenCover`（从下往上弹出、只能点「返回」关掉）。
/// 现在它是导航栈里**推进**出来的一页：从右往左进入、边缘右滑返回 ——
/// 与 Apple 自己的「日历 → 某一天」「备忘录 → 某一条」一致。
///
/// 需要中文模拟器（元素按中文标签查找），与其它 UI 测试一致。
final class DiaryPageTransitionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    private func todayKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    /// 清掉今天的日记并把日记页推进来（`-ui-test-open-day` 走的就是
    /// `AppState.openDiary`，与点日历上的日期是同一条路）。
    private func launchOnToday() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", todayKey(), "-ui-test-reset-data",
                               "-ui-test-no-autoloc", "-ui-test-no-location",
                               "-ui-test-no-autofocus"]
        app.launch()
    }

    /// 从屏幕左边缘往右拖：系统的「右滑返回」手势。
    private func swipeBackFromLeftEdge() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.002, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private var tabBarDiary: XCUIElement { app.buttons["日记"].firstMatch }
    private var back: XCUIElement { app.buttons["返回"].firstMatch }

    /// 写一条今天的日记（从空日记页进入编辑 → 保存）。
    private func writeEntry(_ text: String) {
        let write = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
            .allElementsBoundByIndex.first { $0.isHittable } ?? app.buttons["写日记"].firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 12), "空日记页应提供「写日记」")
        write.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器的正文输入区")
        editor.tap()
        editor.typeText(text)
        app.buttons["保存"].tap()
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isHittable { return true }
            usleep(150_000)
        }
        return element.isHittable
    }

    /// 推进出来的日记页盖住整个屏幕（底部浮条不在），右滑能回到日历。
    func testDiaryPageCoversTabBarAndSwipesBackToCalendar() throws {
        launchOnToday()
        XCTAssertTrue(back.waitForExistence(timeout: 12), "启动即打开今天，应在日记页上")
        XCTAssertFalse(tabBarDiary.isHittable, "推进出来的日记页应盖住底部浮条")

        swipeBackFromLeftEdge()
        XCTAssertTrue(waitUntilHittable(tabBarDiary, timeout: 6), "右滑返回后应回到首页日历")
        XCTAssertFalse(back.exists, "已经离开日记页")
    }

    /// 写一段、保存、回到阅读态，再右滑返回。
    func testSavingThenSwipingBackReturnsToCalendar() throws {
        launchOnToday()
        XCTAssertTrue(back.waitForExistence(timeout: 12), "日记页")
        writeEntry("右滑返回前先写一句。")
        XCTAssertTrue(app.buttons["写日记"].waitForExistence(timeout: 10), "保存后回到阅读态")

        swipeBackFromLeftEdge()
        XCTAssertTrue(waitUntilHittable(tabBarDiary, timeout: 6), "阅读态右滑应回到日历")
    }

    /// 编辑态**不给**右滑：正文还没落库，弹回就等于无声丢掉（点「返回」会先问一句）。
    func testSwipeBackIsBlockedWhileEditing() throws {
        launchOnToday()
        XCTAssertTrue(back.waitForExistence(timeout: 12), "日记页")

        let write = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
            .allElementsBoundByIndex.first { $0.isHittable } ?? app.buttons["写日记"].firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 12))
        write.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器的正文输入区")
        editor.tap()
        editor.typeText("这半篇还没保存，右滑不该把它丢掉。")

        swipeBackFromLeftEdge()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 4), "右滑之后仍应停在编辑态")
        XCTAssertFalse(tabBarDiary.isHittable, "不该退回日历")
    }

    /// 从搜索结果进入日记页（这条路径能拍到推进动画的帧），右滑返回后回到**搜索页**。
    func testPushFromSearchResultThenSwipeBackReturnsToSearchTab() throws {
        launchOnToday()
        XCTAssertTrue(back.waitForExistence(timeout: 12), "日记页")
        writeEntry("右滑返回的搜索样本。")
        XCTAssertTrue(app.buttons["写日记"].waitForExistence(timeout: 10), "保存后回到阅读态")
        swipeBackFromLeftEdge()
        XCTAssertTrue(waitUntilHittable(tabBarDiary, timeout: 6), "先回到日历")

        app.buttons["搜索"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "搜索框")
        field.tap()
        field.typeText("右滑返回的搜索样本")
        // 回车提交并收起键盘：结果行在键盘底下时，点击会落到键盘上。
        field.typeText("\n")

        // 结果行用的是 `.onTapGesture`（不是 Button）；顶部条件栏里那颗**关键词胶囊**
        // 才是 Button，它的文本（含 ✕）也包含关键词 —— 所以按正文里带句号的那句找，
        // 胶囊上只有关键词本身。
        let row = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "右滑返回的搜索样本。")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), "应有一条搜索结果")
        XCTAssertTrue(waitUntilHittable(row, timeout: 6), "结果行应可点（键盘不要压着它）")

        // 进入瞬间连拍几张：给「从右往左」留证据（方向由系统推进动画决定，
        // 自动化只能留下帧，人看帧最直接）。
        row.tap()
        for i in 0..<4 {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "push-frame-\(i)"
            shot.lifetime = .keepAlways
            add(shot)
        }

        XCTAssertTrue(back.waitForExistence(timeout: 10), "结果点开应进入日记页")
        XCTAssertFalse(tabBarDiary.isHittable, "日记页盖住底部浮条")

        swipeBackFromLeftEdge()
        XCTAssertTrue(waitUntilHittable(app.buttons["搜索"].firstMatch, timeout: 6),
                      "右滑返回应回到进来时的搜索页")
        XCTAssertTrue(field.exists, "搜索页还在（结果与关键词都还在）")
    }
}
