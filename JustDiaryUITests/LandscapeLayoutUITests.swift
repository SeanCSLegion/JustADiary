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
/// 判定按**可用宽度**而不是机型，所以这套断言在宽窄两种横屏上都成立，
/// **两档都要跑**（2026-09 实测）：
/// - iPhone 18 Pro（874×402，左右各 62 安全区 → 可用 750）：左栏 345 / 右栏 356.5；
/// - iPhone SE（667×375，无安全区 → 可用 667）：左栏 307 / 右栏 311.5，六行月格
///   刚好在系统浮条（y 311）之上结束。
/// 之前的 `contentWidth >= 700` 阈值只让 18 Pro 分栏，SE 会退回「竖屏版面横向拉长」，
/// 于是「横屏首页必须是左右双列」这条需求在真机 SE 上不成立。
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

        // 左栏日历紧贴左侧内容边：内容边 = 安全区 + 16pt 页面边距 + 20pt 标题内边距。
        // 18 Pro 横屏安全区 leading = 62 → 标题在 x ≈ 98；SE 没有安全区 → x ≈ 36。
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

    /// 其余三屏横屏时，页头也必须紧贴左侧内容边。
    ///
    /// 回归点：`leadingPagePadding` 曾把安全区又加了一遍，横屏页头在 x = 78、
    /// 卡片却在 x = 140，左半屏白掉一条 62pt（和首页分栏是同一个错误）。
    func testOtherTabsContentSitsAtTheSafeAreaEdge() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        for (tab, title) in [("footprint", "足迹"), ("search", "搜索"), ("settings", "设置")] {
            app?.terminate()
            app = XCUIApplication()
            app.launchArguments = ["-ui-test-tab", tab]
            app.launch()

            // 页头在屏幕顶部；同名的 tab 条目在底部，按纵坐标过滤掉。
            let candidates = app.staticTexts.matching(NSPredicate(format: "label == %@", title))
            let header = candidates.allElementsBoundByIndex.first { $0.frame.minY < 160 }
            guard let header else {
                XCTFail("\(tab)：找不到页头「\(title)」")
                continue
            }
            XCTAssertLessThan(header.frame.minX, 130,
                              "\(tab) 页头应贴近左侧内容边（安全区只避让一次）")
            app.terminate()
        }
    }

    /// 右栏有日记时，正文也必须按**右栏宽度**排版。
    ///
    /// 回归点：`ReadTextView` 里的 UITextView 首次测量时 `bounds.width` 还是 0，
    /// intrinsic size 于是退回兜底值 320pt，SwiftUI 就按 320 排了整张卡片 ——
    /// SE 横屏右栏只有 311.5pt，扣掉页边距与卡片内边距正文列只剩 ~247pt。
    /// 卡片因此比栏还宽，外层 `frame(maxWidth:.infinity)` 再把它居中：
    /// 左边压住月历、右边被裁掉（2026-09 实测正文右边界到过 807pt，而整屏只有 667）。
    ///
    /// 用例先竖屏写一段足够长的日记，再转横屏量右栏正文的实际排版宽度 ——
    /// 只靠「空状态」或竖屏是发现不了的。
    func testDayPaneWithDiaryFitsThePaneWidth() throws {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        // 明确从竖屏开始（上一个用例可能刚转过屏，旋转要等它落定再启动）。
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", df.string(from: Date()),
                               "-ui-test-reset-data", "-ui-test-no-autoloc"]
        app.launch()

        // 1) 给「今天」写一段足够长的日记（编辑器 → 保存 → 返回首页）。
        // 同一文案在「日记页」和它后面被盖住的首页上各有一个，所以取真正可点的那一个。
        let writes = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
        let write = writes.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? writes.firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 15), "空日记页应提供「写日记」")
        write.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器的正文输入区")
        editor.tap()
        editor.typeText("横屏右栏的正文列宽必须跟着右栏走，不能按输入区自己的兜底宽度排版，"
                        + "否则整张卡片会比栏还宽，左边压住月历、右边被裁掉。")
        let save = app.buttons["保存"]
        XCTAssertTrue(save.waitForExistence(timeout: 6), "保存按钮")
        save.tap()
        let back = app.buttons["返回"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "从日记页返回首页")
        back.tap()
        sleep(2)

        // 2) 转横屏：首页分栏，右栏显示刚写的这段日记。
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)

        let win = app.windows.firstMatch.frame
        let heading = app.staticTexts["home.dayHeading"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 8), "横屏右栏的标题行")
        // 右栏边界：标题行有 20pt 内边距；页面左右各留 16pt。
        let paneLeft = heading.frame.minX - 20
        let paneRight = win.maxX - 16

        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 6), "右栏的正文")
        XCTAssertGreaterThanOrEqual(text.frame.minX, paneLeft - 0.5,
                                    "右栏正文不能越过栏边界压到月历上")
        XCTAssertLessThanOrEqual(text.frame.maxX, paneRight + 0.5,
                                 "右栏正文不能超出右栏")
        // 页边距 20×2 + 卡片内边距 12×2 = 64，留 2pt 余量。
        XCTAssertLessThanOrEqual(text.frame.width, paneRight - paneLeft - 62,
                                 "正文列宽必须跟着右栏宽度走，不能按 UITextView 的兜底宽度排版")
    }

    /// 横屏进编辑时，格式栏必须是键盘上方的**横排**一条。
    ///
    /// 它曾经只在横屏（`layout.splitsMasterDetail` 为真时）改成竖排面板：9 个
    /// 按钮竖排约 454pt，比 iPhone 18 Pro 横屏的 402pt 可用高度还高，整条被屏幕
    /// 裁掉、又贴在全屏底部中间，与正文列对不上 —— 一进编辑就看不出那是格式栏。
    /// 参照备忘录：键盘上方的工具栏横竖屏都是横向的。
    func testLandscapeEditorFormatBarStaysHorizontal() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", todayKey(),
                               "-ui-test-reset-settings", "-ui-test-no-autoloc"]
        app.launch()

        let writes = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
        let write = writes.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? writes.firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 15), "日记页应提供「写日记」")
        write.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器的正文输入区")

        let bar = app.descendants(matching: .any)
            .matching(identifier: "editor.formatBar").firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "格式栏")

        let frame = bar.frame
        let win = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.width, frame.height * 2,
                             "格式栏应是横排一条，而不是竖排（frame=\(frame)）")
        XCTAssertGreaterThan(frame.width, 300,
                             "九个按钮横排应占满可用宽度（frame=\(frame)）")
        XCTAssertGreaterThanOrEqual(frame.minY, win.minY - 1,
                                    "整条不该被屏幕顶部裁掉（frame=\(frame)）")
        XCTAssertLessThanOrEqual(frame.maxY, win.maxY + 1,
                                 "整条不该超出屏幕底部（frame=\(frame)）")
        // 每个按钮都要在屏幕内：竖排时最上面几个按钮会被推到屏幕外。
        for label in ["引用", "待办"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.exists, "格式栏按钮 \(label)")
            XCTAssertGreaterThanOrEqual(button.frame.minY, win.minY - 1,
                                        "\(label) 被推到屏幕上方之外：\(button.frame)")
        }
        // 剩下的按钮在右边缘外，横滑一下就该出来（与备忘录那条可滑动的工具栏一致）。
        bar.swipeLeft()
        let underline = app.buttons["下划线"]
        XCTAssertTrue(underline.waitForExistence(timeout: 4), "横滑后应能看到最后一个按钮")
        XCTAssertGreaterThanOrEqual(underline.frame.minY, win.minY - 1,
                                    "下划线被推到屏幕上方之外：\(underline.frame)")
    }

    /// 横屏进编辑时，顶栏那些按钮必须留在屏内。
    ///
    /// 页面自己做键盘避让（格式栏用 `keyboardHeight` 抬到键盘上方、内容末尾补一块
    /// 等高占位），如果 system 那套避让还在，横屏（可用高度只有 402pt）会把整页
    /// 连同 `safeAreaInset` 里**钉住**的顶栏一起往上顶：实测键盘弹起后「返回 /
    /// 插入图片 / 保存」跑到屏幕上方之外，用户看到的就是「顶栏没有按钮」。
    func testLandscapeEditorTopBarStaysOnScreen() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", todayKey(),
                               "-ui-test-reset-settings", "-ui-test-no-autoloc"]
        app.launch()

        let writes = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
        let write = writes.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? writes.firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 15), "日记页应提供「写日记」")
        write.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器的正文输入区")
        editor.tap()
        sleep(2)

        let win = app.windows.firstMatch.frame
        for label in ["返回", "插入图片", "放弃修改", "保存"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 6), "顶栏按钮 \(label)")
            XCTAssertGreaterThanOrEqual(button.frame.minY, win.minY - 1,
                                        "\(label) 被顶出屏幕上方：\(button.frame)")
            XCTAssertLessThanOrEqual(button.frame.maxY, win.maxY + 1,
                                     "\(label) 超出屏幕底部：\(button.frame)")
            XCTAssertTrue(button.isHittable, "\(label) 应可见可点：\(button.frame)")
        }

        // 顶栏还必须**不随滚动移动**：它原来挂在 ScrollView 的 `safeAreaInset` 上，
        // 键盘把编辑卡片带进视野时 `scrollTo` 会连它一起滚出去（模拟器接硬件键盘时
        // 键盘不弹，所以这一条是不依赖键盘的确定性断言）。
        let before = app.buttons["返回"].frame.minY
        app.scrollViews.firstMatch.swipeUp()
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertEqual(app.buttons["返回"].frame.minY, before, accuracy: 1,
                       "顶栏应钉在页面顶部，不随内容滚动")
    }

    private func todayKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
