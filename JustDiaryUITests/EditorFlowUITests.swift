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

    /// 触控键盘当前是否真的露在屏幕里（接了硬件键盘时它“存在”但在屏幕下方）。
    private func keyboardIsVisible() -> Bool {
        let kb = app.keyboards.firstMatch
        guard kb.exists else { return false }
        return kb.frame.minY < app.windows.firstMatch.frame.maxY - 1
    }

    private func card(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 点一处空白并等键盘收起。竖屏用「卡片与格式栏之间那条空白」，横屏用「顶栏
    /// 中间的空白」（横屏可用高度只有 402pt，键盘弹起后卡片与格式栏之间已经没有缝）。
    @discardableResult
    private func tapBlankToDismissKeyboard() -> Bool {
        let win = app.windows.firstMatch.frame
        if win.width > win.height {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 175, dy: 30))
                .tap()
        } else {
            let editorFrame = app.textViews.firstMatch.frame
            let bar = card("editor.formatBar").frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 200, dy: (editorFrame.maxY + bar.minY) / 2))
                .tap()
        }
        let deadline = Date().addingTimeInterval(5)
        while keyboardIsVisible(), Date() < deadline { usleep(200_000) }
        return !keyboardIsVisible()
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

    /// 点空白处要能收起键盘 —— 这是编辑器唯一的“退出键盘”路径（顶栏按钮会被触控
    /// 键盘压住，用户也得先收起键盘才好选文字）。
    func testTappingBlankSpaceDismissesTheKeyboard() throws {
        launch(resetData: true)
        openWriteMode()

        let editor = app.textViews.firstMatch
        editor.tap()
        try XCTSkipUnless(keyboardIsVisible(), "模拟器接了硬件键盘，触控键盘没弹出来")

        XCTAssertTrue(tapBlankToDismissKeyboard(), "竖屏：点空白后键盘应该收起")

        // 键盘收起后顶栏按钮应当完整可见（这正是用户报的“顶栏没有按钮”）。
        let win = app.windows.firstMatch.frame
        for label in ["返回", "插入图片", "保存"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "顶栏按钮 \(label)")
            XCTAssertGreaterThanOrEqual(button.frame.minY, win.minY - 1,
                                        "\(label) 应在屏内：\(button.frame)")
            XCTAssertTrue(button.isHittable, "\(label) 应可点：\(button.frame)")
        }

        // 横屏同样要能收：可用高度只有 402pt，键盘一弹起来几乎盖掉半屏，
        // 这时候“点顶栏中间的空白”是唯一自然的出口（下拉内容也可以）。
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        app.textViews.firstMatch.tap()
        try XCTSkipUnless(keyboardIsVisible(), "横屏没有触控键盘")
        XCTAssertTrue(tapBlankToDismissKeyboard(), "横屏：点空白后键盘应该收起")

        // 收起之后顶栏按钮就该回到屏内 —— 用户在横屏要的正是这条路径。
        let landscapeWin = app.windows.firstMatch.frame
        for label in ["返回", "插入图片", "保存"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "横屏顶栏按钮 \(label)")
            XCTAssertGreaterThanOrEqual(button.frame.minY, landscapeWin.minY - 1,
                                        "横屏收键盘后 \(label) 应回到屏内：\(button.frame)")
            XCTAssertTrue(button.isHittable, "横屏收键盘后 \(label) 应可点：\(button.frame)")
        }

        // 顶栏还必须**不随滚动移动**：它原来挂在 ScrollView 的 `safeAreaInset` 上，
        // 键盘把编辑卡片带进视野时 `scrollTo` 会连它一起滚出去。
        let before = app.buttons["返回"].frame.minY
        app.scrollViews.firstMatch.swipeUp()
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertEqual(app.buttons["返回"].frame.minY, before, accuracy: 1,
                       "顶栏应钉在页面顶部，不随内容滚动")

        XCUIDevice.shared.orientation = .portrait
    }

    /// 进出编辑时正文列的宽度不能变（竖屏、横屏都要）。
    ///
    /// 卡片宽度 = 正文列宽，两个模式共用同一个上限（见 `DiaryPageView`）。卡片内边距
    /// 阅读态是 `Spacing.card`(12)、编辑态是 10，编辑输入区自己再内缩 12 —— 所以两个
    /// **输入区**的宽度差恒为 4pt：差得对，就说明列宽一致、进出编辑时卡片不会跳。
    func testReadAndEditContentColumnsHaveTheSameWidth() throws {
        launch(resetData: true)
        openWriteMode()
        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText("卡片宽度")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["写日记"].waitForExistence(timeout: 12), "保存后回到阅读态")

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            sleep(3)

            let readText = app.textViews.firstMatch
            XCTAssertTrue(readText.waitForExistence(timeout: 10),
                          "阅读态的正文输入区（\(orientation.rawValue)）")
            let readWidth = readText.frame.width

            let body = app.staticTexts["卡片宽度"].firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 6), "阅读态的正文")
            body.tap()

            let editText = app.textViews.firstMatch
            XCTAssertTrue(editText.waitForExistence(timeout: 10),
                          "编辑态的正文输入区（\(orientation.rawValue)）")
            let editWidth = editText.frame.width

            XCTAssertEqual(editWidth - readWidth, 4, accuracy: 1.5,
                           "方向 \(orientation.rawValue)：阅读 / 编辑的正文列应等宽"
                           + "（阅读 \(readWidth)，编辑 \(editWidth)）")

            // 先收键盘（触控键盘弹起时顶栏按钮会被推到屏幕外，点不到返回）。
            tapBlankToDismissKeyboard()
            app.buttons["返回"].tap()
            let discard = app.buttons["放弃"]
            if discard.waitForExistence(timeout: 3) { discard.tap() }
            XCTAssertTrue(app.buttons["写日记"].waitForExistence(timeout: 8), "回到阅读态")
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
