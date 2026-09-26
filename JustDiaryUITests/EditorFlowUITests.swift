import XCTest

/// 编辑页的进出与格式栏版面（与字号无关的那些）。
///
/// - 从编辑器返回应该回到**这一天的阅读页**，而不是整个日记页被关掉、掉回首页
///   日历；
/// - 默认字号下格式栏应当一条放得下，不需要横滑。
final class EditorFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func todayKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    /// 打开今天的日记页（阅读态），带 `editor.state` 探针。
    @discardableResult
    private func launch(resetData: Bool = false) -> XCUIApplication {
        app = XCUIApplication()
        var args = ["-ui-test-open-day", todayKey(),
                    "-ui-test-editor-state",
                    "-ui-test-reset-settings",
                    "-ui-test-no-autoloc"]
        if resetData { args.append("-ui-test-reset-data") }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func editorState() -> String {
        let probe = app.staticTexts["editor.state"]
        guard probe.waitForExistence(timeout: 8) else { return "missing" }
        return probe.label
    }

    private func openWriteMode() {
        let writes = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
        let write = writes.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? writes.firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 15), "阅读页应提供「写日记」")
        write.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10), "编辑器的正文输入区")
    }

    func testBackFromTheEditorReturnsToTheDaysReadingView() throws {
        launch(resetData: true)
        openWriteMode()

        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText("写了一半就想返回")
        XCTAssertTrue(editorState().hasPrefix("body|"), "编辑器里的探针：\(editorState())")

        app.buttons["返回"].tap()
        let confirm = app.buttons["放弃"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "有未保存内容时应先确认")
        confirm.tap()

        // 回到的是**今天这一天的阅读页**，不是整个日记页被关掉。
        let deadline = Date().addingTimeInterval(10)
        var state = ""
        repeat {
            state = editorState()
            if state.hasPrefix("read:") { break }
            usleep(250_000)
        } while Date() < deadline
        XCTAssertTrue(state.hasPrefix("read:"), "应停在阅读态，实际是 \(state)")
        // 阅读页自己的入口还在（首页被 fullScreenCover 盖住，但元素仍留在无障碍树里，
        // 所以只能断言「日记页还在」这一侧；首页被关掉时探针整体消失，上面的断言会先失败）。
        XCTAssertTrue(app.buttons["写日记"].waitForExistence(timeout: 5),
                      "阅读页的「写日记」入口还在，说明没有退回首页")
    }

    func testBackFromAnEmptyEditorAlsoReturnsToTheReadingView() throws {
        launch(resetData: true)
        openWriteMode()

        app.buttons["返回"].tap()
        XCTAssertFalse(app.buttons["放弃"].waitForExistence(timeout: 2),
                       "空编辑器没有内容要放弃，不该弹确认")

        let deadline = Date().addingTimeInterval(10)
        var state = ""
        repeat {
            state = editorState()
            if state.hasPrefix("read:") { break }
            usleep(250_000)
        } while Date() < deadline
        XCTAssertTrue(state.hasPrefix("read:"), "应停在阅读态，实际是 \(state)")
    }

    /// 默认字号下九个按钮一条放得下（不横滑）：`ViewThatFits` 的第一种布局。
    func testFormatBarFitsInOnePieceAtTheDefaultTextSize() throws {
        launch(resetData: true)
        openWriteMode()

        let bar = app.descendants(matching: .any)
            .matching(identifier: "editor.formatBar").firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "格式栏")

        let win = app.windows.firstMatch.frame
        XCTAssertLessThan(bar.frame.width, win.width - 8,
                          "格式栏应完整落在屏内并留出边距：\(bar.frame)")

        for label in ["段落样式", "居中", "列表", "引用", "待办", "粗体", "斜体", "删除线", "下划线"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 4), "格式栏按钮 \(label)")
            XCTAssertTrue(button.isHittable, "\(label) 在默认字号下应可见可点：\(button.frame)")
        }
    }
}
