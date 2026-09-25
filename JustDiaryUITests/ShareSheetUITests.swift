import XCTest

/// 分享面板：顶栏分享按钮一步拉起「预览 + 系统分享动作」。
///
/// 回归点：以前是「点分享 → 只有一个蓝色「分享」按钮的小菜单 → 再点一次才出系统面板」，
/// 多一步、而且看不到要分享的是什么。现在的形状是「照片」App 那样：上方是长图预览，
/// 下方直接是系统动作（拷贝 / 保存图像 / 打印…）。
///
/// 需要中文模拟器（元素按中文标签查找），与其它 UI 测试一致。
final class ShareSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private var app: XCUIApplication!

    /// 给「今天」写一段日记，好让分享面板里有真实内容。
    private func seedTodayEntry() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", df.string(from: Date()),
                               "-ui-test-reset-data", "-ui-test-reset-settings",
                               "-ui-test-no-autoloc"]
        app.launch()

        let writes = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
        let write = writes.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? writes.firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 15), "空日记页应提供「写日记」")
        write.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器的正文输入区")
        editor.tap()
        editor.typeText("今天随手记一段，用来检查分享面板里的预览与系统动作。")
        let save = app.buttons["保存"]
        XCTAssertTrue(save.waitForExistence(timeout: 6), "保存按钮")
        save.tap()

        let back = app.buttons["返回"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "从日记页返回首页")
        back.tap()
        sleep(2)
        app.terminate()
    }

    func testShareButtonOpensPreviewAndSystemActions() throws {
        seedTodayEntry()

        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", todayKey(), "-ui-test-reset-settings"]
        app.launch()

        let share = app.buttons["分享"]
        XCTAssertTrue(share.waitForExistence(timeout: 15), "日记页顶栏的分享按钮")
        share.tap()

        // 一步到位：面板里直接有长图预览，而不是先弹一个只有一个按钮的菜单。
        let preview = app.images["share.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20), "分享面板里应该有长图预览")
        XCTAssertGreaterThan(preview.frame.width, 120, "预览不能是一条窄缝")
        XCTAssertGreaterThan(preview.frame.height, 120, "预览不能是一条窄缝")

        // 系统动作直接在同一块面板里（拷贝 / 保存图像 / 打印…都属于 systemAction 分组）。
        XCTAssertTrue(app.cells.matching(identifier: "actionGroupCell").firstMatch
                        .waitForExistence(timeout: 10),
                      "系统分享动作应该就在预览下方，不需要再点一次")

        // 关掉面板，回到日记页。
        let close = app.buttons["share.close"]
        XCTAssertTrue(close.exists, "面板要有自己的关闭按钮")
        close.tap()
        XCTAssertFalse(preview.waitForExistence(timeout: 3), "点关闭后面板应收起")
        XCTAssertTrue(share.isHittable, "关闭后回到日记页")
    }

    private func todayKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
