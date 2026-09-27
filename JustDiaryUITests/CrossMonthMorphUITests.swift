import XCTest

/// 跨月 morph 的**逐帧取证**：同一周里属于两个月份的日期（例：9/28–10/4 这一周里，
/// 9 月的那几天与 10 月的那几天），在整段「月 ↔ 周」动画里是不是**各走各的路线**。
///
/// 这是给人看的取证，不是断言型回归，所以**默认跳过**（它没有断言，却要跑四次 3 秒动画
/// ＋几十次截图，不该拖慢整包 UI 测试）。要看片子就给它 `MORPH_FILM=1`：
///
///     MORPH_FILM=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
///       -project JustDiary.xcodeproj -scheme JustDiary \
///       -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
///       -only-testing:JustDiaryUITests/CrossMonthMorphUITests test
///
/// 里面的做法：
/// - 用 `-slow-morph` 把时长拉到 3 秒（`CalendarLayout.morphDuration`），中间帧才拍得够；
/// - 每一帧都存成附件，名字里带帧号与相对点按那一刻的毫秒数，抽出来就能拼成胶片：
///   `python3 tools/xcresult_frames.py <x.xcresult> <目录>` +
///   `python3 tools/film_strip.py <目录> <out.png> --cols 6 --label`。
///
/// 四个用例：跨月（下个月那一组 / 上个月那一组）、不跨月的对照、以及**反向**
/// （周 → 月，用户报的「同一批日期两套动画」在那个方向最明显）。
/// 坐标是按 iPhone 18 Pro 竖屏（402×874、顶部安全区 62、头部 64、浮条 83）算出来的：
/// 日历区从屏幕 y = 126 开始，月视图视口顶 = 126 + 72(标题) + 30(星期栏) = 228，
/// 行高 = (812 − 64 − 83 − 102) / 6 = 93.83。行 i 的顶 = 228 + 93.83·i。
final class CrossMonthMorphUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORPH_FILM"] == "1",
                          "取证用例默认跳过；要看逐帧片子请设 MORPH_FILM=1")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - 工具

    private func launchAtToday() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-tab", "home", "-slow-morph"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.monthTitle"].firstMatch.waitForExistence(timeout: 20),
                      "竖屏首页应显示月历标题")
        // 等首屏数据与滚动静止位置落定（`flowRest`）再拍。
        sleep(4)
    }

    /// 屏幕点（pt）→ 窗口归一化坐标。
    private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        let window = app.windows.firstMatch
        let frame = window.frame
        return window.coordinate(withNormalizedOffset: CGVector(dx: x / frame.width,
                                                                dy: y / frame.height))
    }

    private func attach(_ prefix: String, _ index: Int, since t0: Date) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = String(format: "%@-%02d-%04dms", prefix, index,
                           Int(Date().timeIntervalSince(t0) * 1000))
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 连续拍 `frames` 帧，帧间只留一点点时间 —— 真正决定间隔的是截图本身的耗时，
    /// 所以帧名里带上真实毫秒数。
    private func film(_ prefix: String, frames: Int, gapUS: UInt32 = 40_000) -> Date {
        let t0 = Date()
        for i in 0..<frames {
            attach(prefix, i, since: t0)
            if i < frames - 1 { usleep(gapUS) }
        }
        return t0
    }

    /// 一个完整用例：静止帧 → 点某一天 → 动画逐帧 → 收尾静止帧。
    private func filmMorph(name: String, tapX: CGFloat, tapY: CGFloat) {
        launchAtToday()
        attach("\(name)-before", 0, since: Date())
        let t0 = Date()
        point(tapX, tapY).tap()
        _ = t0
        // 3 秒的动画：每帧截图本身约 0.1–0.2s，22 帧足够铺满整段。
        let start = film("\(name)-morph", frames: 22)
        sleep(2)
        attach("\(name)-after", 0, since: start)
    }

    // MARK: - 用例

    /// 跨月（**下个月**那一组）：九月最后一行 9/28–10/4，点 9/30（第 3 列）。
    /// 10 月 1–4 日此刻正画在十月第一行里（屏幕下方），要往上走回周条。
    func testFilmCrossMonthNextGroup() throws {
        filmMorph(name: "next", tapX: 143.6, tapY: 650)
    }

    /// 跨月（**上个月**那一组）：九月第一行 8/31–9/6，点 9/2（第 3 列）。
    /// 8 月 31 日此刻在屏幕上方之外（八月最后一行），要往下走回周条。
    func testFilmCrossMonthPreviousGroup() throws {
        filmMorph(name: "prev", tapX: 143.6, tapY: 275)
    }

    /// 对照：不跨月的一周（九月第 3 行 9/14–9/20），点 9/16（第 3 列）。
    func testFilmSameMonthWeek() throws {
        filmMorph(name: "same", tapX: 143.6, tapY: 462)
    }

    /// 跨月**反向**（周 → 月）：点边界那一周进周视图，再点左上角胶囊回来。
    ///
    /// 用户报的「同一批日期两套动画」在这个方向最明显：一套（选中行带的那几格）
    /// 从周条往下走回月视图，另一套（它自己那个月的第一行）跟着月份往上滑进来。
    func testFilmCrossMonthBackToMonth() throws {
        launchAtToday()
        point(143.6, 650).tap()          // 进周视图：9/28–10/4 那一周
        sleep(5)                         // 等正向 morph 收尾（-slow-morph 3 秒）
        attach("back-week", 0, since: Date())

        let t0 = Date()
        app.buttons["home.header.back"].tap()
        _ = film("back-morph", frames: 22)
        sleep(2)
        attach("back-month", 0, since: t0)
    }
}
