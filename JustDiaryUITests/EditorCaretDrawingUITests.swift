import XCTest

/// 光标**画在哪里**（不是属性、不是探针读到的值）。
///
/// 用户报的「引用 / 换字号之后光标停在上一行末尾，输入却落在下一行」：App 拿到的
/// `caretRect(for:)` 与 UIKit 画出来的光标**同时**退回到「上一个已排版片段的末尾」——
/// 因为文档以换行结尾时，末尾那个空段落没有字符也没有排版片段（TextKit 2 不会自己补），
/// 而摘掉末尾列表项的标记正好造成这个状态。
///
/// 这条用例**故意不开** `-ui-test-editor-caret`：那条探针会替 App 把末尾排出来，
/// 把问题遮住（实测：开探针时光标画得是对的，只有读到的值是错的）。所以这里只看截图的像素。
final class EditorCaretDrawingUITests: XCTestCase {

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

    private var editor: XCUIElement { app.textViews["editor.text"] }

    /// 用户的复现路径：大标题 → 小标题 → 正文 → 两行引用 → 正文 → 两行列表 →
    /// 回车出第三行列表（空）→ 点引用。只开 `editor.state` / `editor.scroll` 两个
    /// **不碰排版**的探针。
    func testQuoteOnAnEmptyListItemDrawsTheCaretOnThatLine() throws {
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-open-day", todayKey(),
                               "-ui-test-editor-state",
                               "-ui-test-editor-scroll",
                               "-ui-test-reset-data",
                               "-ui-test-reset-settings",
                               "-ui-test-no-autoloc"]
        app.launch()

        let writes = app.buttons.matching(NSPredicate(format: "label == %@", "写日记"))
        let write = writes.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? writes.firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 15), "写日记")
        write.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "编辑器")
        editor.tap()

        editor.typeText("A")
        applyStyle("大标题")
        editor.typeText("\n")
        editor.typeText("B")
        applyStyle("小标题")
        editor.typeText("\n")
        editor.typeText("C")
        applyStyle("正文")
        editor.typeText("\n")
        editor.typeText("D")
        app.buttons["引用"].tap()
        editor.typeText("\n")
        editor.typeText("E")
        editor.typeText("\n")
        app.buttons["引用"].tap()
        editor.typeText("F")
        editor.typeText("\n")
        app.buttons["列表"].tap()
        editor.typeText("G")
        editor.typeText("\n")
        editor.typeText("H")
        usleep(600_000)

        // 回车 → 空的第三行列表，什么都不输入，直接点引用
        editor.typeText("\n")
        usleep(600_000)
        app.buttons["引用"].tap()
        usleep(800_000)

        let barTop = try XCTUnwrap(scrollProbe()?.barTop, "格式栏上沿探针")
        let caret = try XCTUnwrap(waitForDrawnCaret(below: editor.frame.minY - 20, above: barTop - 4),
                                  "截图里应该能找到画出来的光标")
        XCTAssertLessThanOrEqual(abs(caret.minX - editor.frame.minX), 8,
                                 "光标要画在这一行（行首）：实际 \(caret)，正文列左边 \(editor.frame.minX)")
        XCTAssertLessThanOrEqual(caret.maxY, barTop - 4,
                                 "光标要露在格式栏之上：实际 \(caret)，格式栏上沿 \(barTop)")

        // 接着输入的字必须落在这一行（引用行），而不是插进上一行
        editor.typeText("Z")
        usleep(800_000)
        let state = editorState()
        XCTAssertTrue(state.contains("quote|"), "输入的字应落在引用行上：\(state)")
        XCTAssertTrue(state.hasSuffix("Z"), "刚输入的字在文末：\(state)")
    }

    // MARK: - 像素工具

    private func applyStyle(_ label: String) {
        let menu = app.buttons["段落样式"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "段落样式")
        menu.tap()
        let item = app.buttons[label]
        if item.waitForExistence(timeout: 5) { item.tap(); return }
        app.menuItems[label].tap()
    }

    private func editorState() -> String {
        let probe = app.staticTexts["editor.state"]
        guard probe.waitForExistence(timeout: 8) else { return "missing" }
        return probe.label
    }

    /// 滚动探针（`editor.scroll`）：`"contentOffset.y,格式栏上沿,键盘高度"`。
    private func scrollProbe() -> (offset: CGFloat, barTop: CGFloat, keyboard: CGFloat)? {
        let probe = app.staticTexts["editor.scroll"]
        guard probe.waitForExistence(timeout: 6) else { return nil }
        let parts = probe.label.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return (CGFloat(parts[0]), CGFloat(parts[1]), CGFloat(parts[2]))
    }

    /// 连拍几张（光标会闪），返回找到的那根画出来的光标。
    private func waitForDrawnCaret(below: CGFloat, above: CGFloat, frames: Int = 10) -> CGRect? {
        for _ in 0..<frames {
            if let rect = drawnCaret(in: XCUIScreen.main.screenshot(), below: below, above: above) {
                return rect
            }
            usleep(150_000)
        }
        return nil
    }

    /// 截图里找**画出来的**光标：指定窗口区域里一根**孤立**的细蓝竖条。
    ///
    /// 孤立是关键：日期胶囊、引用底色、格式栏按钮都是蓝的，但它们要么宽、要么成片；
    /// 光标是 2–3pt 宽、10–30pt 高、左右 6pt 内没有同类像素的一根。
    private func drawnCaret(in screenshot: XCUIScreenshot, below: CGFloat, above: CGFloat) -> CGRect? {
        guard let cg = screenshot.image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / max(1, app.windows.firstMatch.frame.width)
        let windowTop = Int(max(0, below) * scale)
        let windowBottom = Int(min(CGFloat(height) / scale, above) * scale)
        guard windowBottom > windowTop else { return nil }

        var runs: [(x: Int, top: Int, bottom: Int)] = []
        for x in 0..<width {
            var start: Int?
            for y in windowTop..<windowBottom {
                let offset = (y * width + x) * 4
                let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
                let isBlue = b > 160 && b - r > 50 && b - g > 30 && r < 160
                if isBlue {
                    if start == nil { start = y }
                } else if let from = start {
                    let length = y - from
                    if length >= Int(10 * scale), length <= Int(40 * scale) { runs.append((x, from, y)) }
                    start = nil
                }
            }
        }
        // 先把相邻列并成「笔画」，再按形状挑：细（≤8pt）、高 10–40pt。
        // 引用底色、日期胶囊这类成片的蓝色会并成很宽的一条，直接被排除。
        var strokes: [(x0: Int, x1: Int, top: Int, bottom: Int)] = []
        for run in runs {
            if var last = strokes.last,
               run.x - last.x1 <= Int(2 * scale), abs(run.top - last.top) <= Int(6 * scale) {
                last.x1 = run.x
                last.top = min(last.top, run.top)
                last.bottom = max(last.bottom, run.bottom)
                strokes[strokes.count - 1] = last
            } else {
                strokes.append((run.x, run.x, run.top, run.bottom))
            }
        }
        let shaped = strokes.filter { stroke in
            let w = CGFloat(stroke.x1 - stroke.x0 + 1) / scale
            let h = CGFloat(stroke.bottom - stroke.top) / scale
            return w <= 8 && h >= 8 && h <= 40
        }
        guard let best = shaped.max(by: { ($0.bottom - $0.top) < ($1.bottom - $1.top) }) else { return nil }
        return CGRect(x: CGFloat(best.x0) / scale, y: CGFloat(best.top) / scale,
                      width: CGFloat(best.x1 - best.x0 + 1) / scale,
                      height: CGFloat(best.bottom - best.top) / scale)
    }
}
