import XCTest

/// 设置变化只做**最小更新**：不重建整棵界面，也不该丢掉别处的状态。
///
/// 回归点：`uiTick` 曾经被塞进 tab 树的 `.id(...)`，于是改任何一个开关（周起始 /
/// 时间显示 / 分享精度…）都会把四个 tab 连同搜索关键词、结果、滚动位置一起重建。
/// 只有**语言与主题**需要那种整树重建（文案与配色是全局的）。
///
/// 这条用例同时守住两件事：改设置之后
/// 1. 别的页面状态还在（说明没有被重建）；
/// 2. 该生效的地方**立刻**生效（星期栏第一格从「一」变「日」）。
///
/// 需要中文模拟器，与其它 UI 测试一致。
final class SettingsMinimalUpdateUITests: XCTestCase {

    private var app: XCUIApplication!
    /// 关键词与正文都带上句号差异：搜索页顶部那颗「关键词胶囊」只有关键词本身，
    /// 结果行里是正文（带句号）—— 靠这一点区分两者。
    private let keyword = "设置最小更新样本"
    private let entryText = "设置最小更新样本。"

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

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", todayKey(), "-ui-test-reset-data",
                               "-ui-test-reset-settings", "-ui-test-no-autoloc",
                               "-ui-test-no-location", "-ui-test-no-autofocus"]
        app.launch()
    }

    /// 设置页里某一行的按钮（标题在 label 里，值在 `value` 里）。
    private func settingsRow(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// 设置页的规则卡片在首屏之下，往下滑到能点为止。
    @discardableResult
    private func scrollToSettingsRow(_ title: String) -> XCUIElement {
        let row = settingsRow(title)
        for _ in 0..<6 {
            if row.exists, row.isHittable { return row }
            app.swipeUp()
        }
        return row
    }

    /// 星期栏最左边那一格的字（周一起始是「一」，周日起始是「日」）。
    private func firstWeekdayLabel() -> String? {
        let weekdayLabels: Set<String> = ["一", "二", "三", "四", "五", "六", "日"]
        let candidates = app.staticTexts.allElementsBoundByIndex.filter {
            weekdayLabels.contains($0.label) && $0.frame.minY > 120
        }
        return candidates.min { $0.frame.minX < $1.frame.minX }?.label
    }

    private func writeTodayEntry() {
        let write = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
            .allElementsBoundByIndex.first { $0.isHittable } ?? app.buttons["写日记"].firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 12), "空日记页应提供「写日记」")
        write.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器的正文输入区")
        editor.tap()
        editor.typeText(entryText)
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["写日记"].waitForExistence(timeout: 10), "保存后回到阅读态")
    }

    /// 去搜索页搜出那条，返回「结果行」这个元素（顺带把关键词留在条件栏里）。
    private func searchForTheEntry() -> XCUIElement {
        app.buttons["搜索"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "搜索框")
        field.tap()
        field.typeText(keyword)
        field.typeText("\n")   // 提交并收起键盘（键盘会挡住结果行）

        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", entryText)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), "应搜到刚写的那条")
        return row
    }

    func testChangingSettingsKeepsOtherTabsStateAndStillApplies() throws {
        launch()
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 12), "应在日记页上")
        writeTodayEntry()
        app.buttons["返回"].firstMatch.tap()
        XCTAssertTrue(app.buttons["日记"].firstMatch.waitForExistence(timeout: 8), "回到日历")

        // 1) 在搜索页留下状态：关键词条件 + 一条结果。
        let resultRow = searchForTheEntry()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", keyword))
            .firstMatch.waitForExistence(timeout: 6), "条件栏里有关键词胶囊")

        // 2) 设置页改两项：周起始 → 周日；分享位置精度 → 隐藏。
        app.buttons["设置"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 10), "设置页")
        scrollToSettingsRow("一周从哪一天开始").tap()
        XCTAssertTrue(app.buttons["周日"].waitForExistence(timeout: 5), "周起始选项")
        app.buttons["周日"].tap()

        scrollToSettingsRow("分享位置精度").tap()
        XCTAssertTrue(app.buttons["隐藏"].waitForExistence(timeout: 5), "分享精度选项")
        app.buttons["隐藏"].tap()
        XCTAssertEqual(settingsRow("分享位置精度").value as? String, "隐藏", "设置本身要立刻生效")

        // 3) 回搜索页：关键词与结果都还在 —— 界面没有被重建。
        app.buttons["搜索"].firstMatch.tap()
        XCTAssertTrue(resultRow.waitForExistence(timeout: 6),
                      "改设置把搜索页重建了：关键词 / 结果不该被清掉")

        // 4) 回首页：周起始立刻生效（星期栏第一格变成「日」）。
        app.buttons["日记"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["home.monthTitle"].firstMatch.waitForExistence(timeout: 8),
                      "首页日历")
        XCTAssertEqual(firstWeekdayLabel(), "日", "周起始应立刻生效，不该等重启")
    }
}
