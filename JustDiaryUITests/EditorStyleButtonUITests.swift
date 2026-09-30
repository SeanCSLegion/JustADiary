import XCTest

/// 编辑模式里格式按钮的**状态**与**光标**（用户在模拟器里报的三条）。
///
/// 1. 点「引用」不该把「字号 / 段落样式」按钮也点亮 —— 引用有自己的按钮，字号也是引用
///    自己管的（15pt）；
/// 2. 列表 / 待办的空项上点「引用」：标记被摘掉之后，光标要停在**这一行**，接着输入的
///    字就该落在引用行上；
/// 3. 空行上开 / 关「居中」：光标要跟着走到列中间 / 回到行首（这条量的是光标窗口坐标，
///    不是内部属性 —— 用户看到的就是它）。
final class EditorStyleButtonUITests: XCTestCase {

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

    @discardableResult
    private func launch() -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", todayKey(),
                               "-ui-test-editor-state",
                               "-ui-test-editor-caret",
                               "-ui-test-reset-data",
                               "-ui-test-reset-settings",
                               "-ui-test-no-autoloc"]
        app.launch()
        return app
    }

    private func openWriteMode() {
        let writes = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
        let write = writes.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? writes.firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 15), "阅读页应提供「写日记」")
        write.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器的正文输入区")
    }

    /// 编辑态的输入区：编辑时阅读态的块可能还在无障碍树里，所以用固定标识取。
    private var editor: XCUIElement { app.textViews["editor.text"] }

    private func state() -> String {
        let probe = app.staticTexts["editor.state"]
        guard probe.waitForExistence(timeout: 8) else { return "missing" }
        return probe.label
    }

    /// `editor.caret` 探针：`"minY,maxY|minX,maxX"`（窗口坐标）。
    private func caret() -> CGRect? {
        let probe = app.staticTexts["editor.caret"]
        guard probe.waitForExistence(timeout: 5) else { return nil }
        let groups = probe.label.split(separator: "|").map(String.init)
        guard groups.count == 2 else { return nil }
        let vertical = groups[0].split(separator: ",").compactMap { Double($0) }
        let horizontal = groups[1].split(separator: ",").compactMap { Double($0) }
        guard vertical.count == 2, horizontal.count == 2 else { return nil }
        return CGRect(x: horizontal[0], y: vertical[0],
                      width: horizontal[1] - horizontal[0], height: vertical[1] - vertical[0])
    }

    /// 等光标探针报出一个可用的矩形（点完按钮后要等一帧布局）。
    @discardableResult
    private func waitForCaret(timeout: TimeInterval = 5) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let rect = caret() { return rect }
            usleep(150_000)
        } while Date() < deadline
        return nil
    }

    /// 把当前屏幕拍成附件：光标位置 / 按钮高亮这类东西截图最直观，
    /// `python3 tools/xcresult_frames.py <x.xcresult> <目录>` 可以导出来肉眼核对。
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func applyStyle(_ label: String) {
        let menu = app.buttons["段落样式"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "段落样式按钮")
        menu.tap()
        let item = app.buttons[label]
        if item.waitForExistence(timeout: 6) {
            item.tap()
            return
        }
        let menuItem = app.menuItems[label]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 6), "样式项 \(label)")
        menuItem.tap()
    }

    // MARK: - 1. 引用不该点亮字号按钮

    func testQuoteDoesNotSelectTheParagraphStyleMenu() throws {
        launch()
        openWriteMode()
        editor.tap()
        editor.typeText("引用行")

        let menu = app.buttons["段落样式"]
        XCTAssertFalse(menu.isSelected, "正文行上段落样式按钮不该是选中态")

        app.buttons["引用"].tap()
        usleep(700_000)
        XCTAssertTrue(app.buttons["引用"].isSelected, "引用按钮自己应该是选中态")
        XCTAssertFalse(menu.isSelected,
                       "引用行上「字号 / 段落样式」按钮不该被点亮（引用有自己的字号与按钮）")
        attach("style-menu-after-quote")

        applyStyle("大标题")
        usleep(700_000)
        XCTAssertTrue(menu.isSelected, "大标题行上段落样式按钮应该是选中态")
        XCTAssertFalse(app.buttons["引用"].isSelected, "换成大标题后引用不再是选中态")

        applyStyle("正文")
        usleep(700_000)
        XCTAssertFalse(menu.isSelected, "回到正文后按钮不再点亮")
    }

    // MARK: - 2. 空项上点引用：光标留在这一行

    func testQuoteOnAMarkerOnlyLineKeepsTheCaretOnThatLine() throws {
        launch()
        openWriteMode()
        editor.tap()
        editor.typeText("abc")
        app.buttons["列表"].tap()
        usleep(500_000)
        editor.typeText("\n")
        usleep(700_000)
        XCTAssertEqual(state(), "list|abc", "回车后应该是一个新的空列表项")

        let onItemLine = try XCTUnwrap(waitForCaret(), "空项上的光标")

        app.buttons["引用"].tap()
        usleep(900_000)
        let afterQuote = try XCTUnwrap(waitForCaret(), "点引用后的光标")
        let frame = editor.frame
        // 引用正文让开左侧的竖条（`BlockMetrics.quoteTextInset`，默认字号下 16pt），
        // 所以光标不再贴着正文列的左边界，而是落在引用的文字缩进处。
        XCTAssertLessThanOrEqual(afterQuote.minX, frame.minX + 22,
                                 "光标应停在引用行的文字缩进处（默认 16pt），实际 \(afterQuote)")
        XCTAssertGreaterThanOrEqual(afterQuote.minX, frame.minX + 8,
                                    "光标不该还贴在正文列边界上（那是引用块竖条的位置），实际 \(afterQuote)")
        attach("quote-on-empty-item")
        XCTAssertEqual(state(), "list|abc", "空行不入库：探针里仍只有上面那个列表项")

        // 接着输入的字必须落在引用行上 —— 而不是插进上面那行列表项里。
        editor.typeText("引")
        usleep(900_000)
        XCTAssertEqual(state(), "list,quote|abc引",
                       "输入的字应该成为新的引用行（光标在列表项文字里的话会变成 list|a引bc）")
        let afterTyping = try XCTUnwrap(waitForCaret(), "输入后的光标")
        XCTAssertGreaterThan(afterTyping.minY, onItemLine.minY - 1,
                             "输入后光标还在列表项下面那一行")
    }

    // MARK: - 3. 居中：空行上的光标要跟着走

    func testCenterMovesTheCaretOnAnEmptyLineInTheMiddle() throws {
        launch()
        openWriteMode()
        editor.tap()
        // "abc" / 空行 / "def"，光标停在空行上（空行自己带换行符）。
        editor.typeText("abc")
        editor.typeText("\n")
        editor.typeText("\n")
        editor.typeText("def")
        usleep(700_000)
        let onDefLine = try XCTUnwrap(waitForCaret(), "def 行上的光标")

        // 点上面那一行的空白处，把光标放到空行上。
        let frame = editor.frame
        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width / 2, dy: onDefLine.minY - 14 - frame.minY))
            .tap()
        usleep(700_000)
        let onEmptyLine = try XCTUnwrap(waitForCaret(), "空行上的光标")
        XCTAssertLessThan(onEmptyLine.minY, onDefLine.minY, "光标应该上移到空行")
        XCTAssertLessThanOrEqual(onEmptyLine.minX, frame.minX + 4, "空行未居中时光标在行首")

        app.buttons["居中"].tap()
        usleep(900_000)
        let centered = try XCTUnwrap(waitForCaret(), "居中后的光标")
        XCTAssertGreaterThan(centered.minX, frame.midX - 40,
                             "空行居中后光标要移到列中间，实际 \(centered)（列 \(frame)）")
        attach("center-on-empty-line")
        XCTAssertEqual(centered.minY, onEmptyLine.minY, accuracy: 3, "还是同一行")

        app.buttons["居中"].tap()
        usleep(900_000)
        let cancelled = try XCTUnwrap(waitForCaret(), "取消居中后的光标")
        XCTAssertLessThanOrEqual(cancelled.minX, frame.minX + 4,
                                 "取消居中后光标要回到行首，实际 \(cancelled)")
        attach("center-cancelled")
    }
}
