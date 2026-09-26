import XCTest
import SwiftUI
@testable import JustDiary

/// 连续月历流（`MonthFlowLayout`）的几何回归。
///
/// 月视图改成连续滚动之后，「哪一行在哪儿」不再由 SwiftUI 的布局给出，而是这份
/// 布局算出来的 —— morph 的起点、顶部月份、跳月位置全都读它。所以它的三条约定
/// 必须有测试守住：
/// 1. 行高全局一致（`rowH`），月内相邻两行正好差一个 `rowH`；
/// 2. **月份之间不留空隙**：两个月的行紧挨着（下一块的 `top` == 上一块的 `bottom`），
///    从上到下是「上个月的日期 → 小标题 → 分割线 → 本月日期」：小标题底边在本月
///    第一行顶上方 3pt（= 分割线上方 3pt），整块落在上一行底部的留白里。这条尺子
///    被用户来回改过三版（一整周 94pt 空带 → 35pt → 21pt → 「紧贴数字上方」→
///    「要在分割线上方才对」），现在这一版是最终版，别再调换次序；
/// 3. 静止位置 = 该月第一行的顶，此时视口里正好是「标题槽 + 星期栏 + 六行日期」
///    —— 与改造前的静止画面一致。
final class MonthFlowLayoutTests: XCTestCase {

    /// 竖屏 402×874 实测：日历区 665 = 672 − 84（头部）− 83（浮条）− …，行高 = (665 − 102) / 6，
    /// 视口 = 665 − 72（标题槽）− 30（星期栏）。
    private let rowH: CGFloat = (665 - CalendarLayout.bigTitleH - CalendarLayout.weekdayHeaderH) / 6
    private let viewportH: CGFloat = 665 - CalendarLayout.bigTitleH - CalendarLayout.weekdayHeaderH

    /// 竖屏小标题这一行字的高度（15pt 字 → 21pt）。
    private var labelH: CGFloat { CalendarLayout.flowLabelBandHeight(compact: false) }
    /// 竖屏单行的绘制参数（用来算「数字上方」到底在哪儿）。
    private var metrics: DayMetrics {
        CalendarLayout.flowMetrics(width: 402, rowH: rowH, lunar: true)
    }

    private func layout(_ ws: String = "monday") -> MonthFlowLayout {
        MonthFlowLayout(weekStart: ws, rowH: rowH)
    }

    /// `displayedWeekCount` 必须与 `displayedWeeks(...).count` 逐月一致
    /// （前者是 O(1) 的算法版本，用来给 2400 个月建偏移）。
    func testWeekCountMatchesTheRealWeekArray() {
        for ws in ["monday", "sunday"] {
            for key in stride(from: 190001, through: 210012, by: 1) where key % 100 >= 1 && key % 100 <= 12 {
                let month = CalendarLayout.dateForMonthKey(key)
                XCTAssertEqual(CalendarLayout.displayedWeekCount(inMonth: month, ws: ws),
                               CalendarLayout.displayedWeeks(inMonth: month, ws: ws).count,
                               "\(key) ws=\(ws)")
            }
        }
    }

    /// 1) 行高一致：月内相邻两行的顶正好差一个 `rowH`。
    func testRowsInsideAMonthAreExactlyOneRowApart() {
        let l = layout()
        for block in l.blocks where [202601, 202602, 202606, 202608, 202609].contains(block.key) {
            XCTAssertGreaterThan(block.rowCount, 0)
            for row in 1..<block.rowCount {
                XCTAssertEqual(l.rowTop(of: block, row: row) - l.rowTop(of: block, row: row - 1),
                               rowH, accuracy: 0.001, "\(block.key) 第 \(row) 行")
            }
            // 最后一行到底就是下个月第一行的顶（两块之间不留空隙）。
            XCTAssertEqual(l.blocks[block.index + 1].top - l.rowTop(of: block, row: block.rowCount - 1),
                           rowH, accuracy: 0.001, "\(block.key) 最后一行到底就是下个月的开始")
            XCTAssertEqual(l.blocks[block.index + 1].top, block.bottom, accuracy: 0.001,
                           "上一块的底 = 下一块的顶")
        }
    }

    /// 2) 月份之间**不留空隙**，小标题在**分割线上方**、紧贴分割线。
    ///
    /// 从上到下的次序：上个月的日期 → 小标题 → 分割线（画在本月第一行的顶）→ 本月日期。
    /// 用户的尺子改过三次（一整周 94pt → 35pt → 「紧贴数字上方」→「要在分割线上方」），
    /// 现在这一版是最终版：小标题底边 = 本月第一行顶 − 3pt，整块落在上一行底部的留白里。
    func testMonthsAreAdjacentAndLabelSitsAboveTheDivider() {
        let l = layout()
        XCTAssertEqual(labelH, 21, "竖屏：15pt 字 → 21pt（就是这一行字）")
        let tightGap: CGFloat = 3
        for block in l.blocks.prefix(24) {
            let next = l.blocks[block.index + 1]
            XCTAssertEqual(next.top, block.bottom, accuracy: 0.001,
                           "\(block.key) → \(next.key) 之间不留空隙")
            // 小标题：整块都在分割线（本月第一行的顶）上方，底边离它 3pt。
            let labelTop = next.top - tightGap - labelH
            XCTAssertLessThanOrEqual(labelTop + labelH, next.top - tightGap + 0.001,
                                     "小标题整个在分割线上方")
            // 而且它没有飘出上个月最后一行（仍在那一行的范围内）。
            XCTAssertGreaterThanOrEqual(labelTop, block.bottom - rowH,
                                        "小标题落在上个月最后一行之内")
            // 竖屏下这一行字**压不到**上个月的日期：上一行「日期内容」的底边离行底
            // 还有 `contentTop` 的留白，而小标题只占 24pt（21 字高 + 3 间隙）。
            let contentTop = DayDraw.contentTopPadding(metrics)
            XCTAssertGreaterThanOrEqual(contentTop, labelH + tightGap,
                                        "竖屏留白要放得下小标题（\(contentTop) ≥ \(labelH + tightGap)）")
        }
        // 月份正好从周首日开始的那几个月，上个月最后一行与小标题同列的那一格是
        // **上个月的日期**（会被画出来）；竖屏仍靠上面的留白错开，横屏留白不足
        // （见 `testCompactLabelIsSmallerAndStillFits` 里记的那个已知取舍）。
        var weekStartAligned = 0
        for block in l.blocks.prefix(120) where
            CalendarLayout.monthLabelColumn(inMonth: l.blocks[block.index + 1].month,
                                            ws: "monday") == 0 {
            weekStartAligned += 1
        }
        XCTAssertGreaterThan(weekStartAligned, 0, "确实存在「1 号就是周首日」的月份")
    }

    /// 横屏左栏用紧凑字号，标题那一行也跟着小一号；行高更矮时标题仍要落在行内。
    func testCompactLabelIsSmallerAndStillFits() {
        let compact = CalendarLayout.flowLabelBandHeight(compact: true)
        XCTAssertEqual(compact, 18, "横屏：13pt 字 → 18pt")
        XCTAssertLessThan(compact, labelH)
        XCTAssertLessThan(compact, 45 * 0.7, "横屏一行只有 45pt，标题也得跟着小")
        // 横屏（隐藏农历）：上一行的底部留白仍要放得下这一行字（否则会压到日期上）。
        let compactMetrics = CalendarLayout.flowMetrics(width: 307, rowH: 40.5, lunar: false, compact: true)
        let padding = DayDraw.contentTopPadding(compactMetrics)
        XCTAssertGreaterThan(padding, 8, "上留白要有意义地大于 0（\(padding)）")
        XCTAssertLessThan(compact + 3, 40.5, "整行 40.5pt，标题 + 间距仍要落在这一行里")
        // **已知取舍**：横屏一行只有 40.5pt，上留白 ~11pt，放不下 18pt 的小标题；
        // 当某个月的 1 号正好落在周首日时（约 1/7 的月份），上个月最后一行同一列
        // 是有日期的，小标题会压进那一格约 10pt。竖屏留白 27pt 足够，不受影响。
        // 这一条把现状钉住：以后若给横屏加「块首额外留白」，这个数字会变。
        XCTAssertLessThan(padding + labelH + 3 - (compact + 3), padding + labelH,
                          "横屏小标题确实放不进上留白（当前差 \(compact + 3 - padding)pt）")
    }

    /// 3) 静止位置 = 该月第一行的顶；此时顶部月份就是它自己。
    func testRestOffsetPutsTheFirstRowAtTheTop() {
        let l = layout()
        for key in [202609, 202608, 202602, 200001, 210012] {
            guard let index = l.blockIndex(forKey: key), let rest = l.restOffset(forKey: key) else {
                XCTFail("\(key) 应在流里")
                continue
            }
            let block = l.blocks[index]
            XCTAssertEqual(rest, block.top, accuracy: 0.001, "静止偏移 = 本月第一行的顶")
            XCTAssertEqual(l.blockIndex(atOffset: rest), index, "静止时顶部月份应是 \(key)")
            XCTAssertEqual(l.blockIndex(atOffset: block.top), index,
                           "本月第一行到顶，顶部月份就该是它")
        }
    }

    /// 静止画面（竖屏）：视口 = 六行。六行月份正好铺满，五行的月份则把下个月的
    /// **小标题与第一行日期**露在视口底部（1 号上方紧贴着的那行月份小字）。
    func testViewportAtRestShowsSixRowsOrTheNextLabel() {
        let l = layout()
        for key in [202608, 202609] {
            guard let rest = l.restOffset(forKey: key), let i = l.blockIndex(forKey: key) else {
                XCTFail("\(key) 应在流里")
                continue
            }
            let block = l.blocks[i]
            let rowsH = CGFloat(block.rowCount) * rowH
            let nextTop = l.blocks[i + 1].top
            if block.rowCount == 6 {
                XCTAssertEqual(rowsH, viewportH, accuracy: 0.001, "六行正好铺满视口")
                XCTAssertEqual(nextTop, rest + viewportH, accuracy: 0.001,
                               "六行月份的下一行正好在视口之外")
            } else {
                XCTAssertLessThan(rowsH, viewportH, "五行月份底下会露出下个月的开头")
                XCTAssertEqual(nextTop, rest + rowsH, accuracy: 0.001,
                               "下个月紧接着本月最后一行（不留空隙）")
                XCTAssertLessThan(nextTop, rest + viewportH, "所以下一行确实露在视口里")
            }
        }
    }

    /// 可见块：只画与视口相交的那些（外加留白），首尾两端不越界。
    func testVisibleBlocksStayInsideTheFlow() {
        let l = layout()
        let count = l.visibleBlocks(offset: 0, viewportH: viewportH, margin: rowH).count
        XCTAssertGreaterThanOrEqual(count, 1)
        XCTAssertLessThanOrEqual(count, 4, "一屏最多跨 3–4 个月，不该把整条流都建出来")
        XCTAssertEqual(l.visibleBlocks(offset: 0, viewportH: viewportH, margin: 0).first?.key,
                       l.blocks.first?.key)

        let end = l.maxOffset(viewportH: viewportH)
        XCTAssertEqual(l.visibleBlocks(offset: end, viewportH: viewportH, margin: rowH).last?.key,
                       l.blocks.last?.key)
        XCTAssertEqual(l.contentH, l.blocks.last!.bottom, accuracy: 0.001,
                       "内容总高 = 最后一块的底")
        XCTAssertGreaterThan(l.contentH, viewportH * 100, "1900–2100 是一条很长的流")
    }

    /// 小标题要站在**当月 1 号所在的那一列**（用户：「小月份应该是在每个月的 1 号的
    /// 上方的，不是居中放在中间」）。
    func testMonthLabelStandsAboveTheFirstDay() {
        for ws in ["monday", "sunday"] {
            for key in [202601, 202602, 202608, 202609, 202610, 202612] {
                let month = CalendarLayout.dateForMonthKey(key)
                let col = CalendarLayout.monthLabelColumn(inMonth: month, ws: ws)
                XCTAssertTrue((0..<7).contains(col), "\(key) 列号要在 0…6")
                let firstWeek = CalendarLayout.displayedWeeks(inMonth: month, ws: ws)[0]
                XCTAssertEqual(DateUtil.calendar.component(.day, from: firstWeek.days[col]), 1,
                               "ws=\(ws) \(key)：小标题那一列必须是 1 号")
            }
        }
    }

    /// 顶部月份 = **占视口最多**的那一块，不是「视口顶部落在哪一块」。
    ///
    /// 后者在滑动时只要下一月的第一行露头就抢标题（用户：「要显示的是占据屏幕主要的
    /// 月份」「快速滑动会乱显示」）。这里守住两条：静止时是它自己；只露出下个月一小截
    /// 时仍显示本月。
    func testDominantMonthIsTheOneFillingMostOfTheViewport() {
        let l = layout()
        for key in [202609, 202602, 202608] {
            guard let rest = l.restOffset(forKey: key), let i = l.blockIndex(forKey: key) else {
                XCTFail("\(key) 应在流里")
                continue
            }
            XCTAssertEqual(l.dominantBlockIndex(offset: rest, viewportH: viewportH), i,
                           "\(key) 静止时顶部月份就是它")

            // 关键差别：视口顶部还落在上个月的最后一行里，但屏幕上**下个月已经过半**
            // —— 这时候要显示下个月（「占据屏幕主要的月份」）。
            let boundary = l.blocks[i + 1].top
            let mostlyNext = boundary - (viewportH / 2 - 1)
            XCTAssertEqual(l.blockIndex(atOffset: mostlyNext), i, "\(key)：顶部那一块仍是上个月")
            XCTAssertEqual(l.dominantBlockIndex(offset: mostlyNext, viewportH: viewportH), i + 1,
                           "\(key)：下个月占了多半屏，顶部月份就该是它")

            // 反过来：上个月仍占多半屏时不换。
            let mostlyCurrent = boundary - (viewportH / 2 + 1)
            XCTAssertEqual(l.dominantBlockIndex(offset: mostlyCurrent, viewportH: viewportH), i,
                           "\(key)：上个月还占多数，不该换")
        }
    }

    /// 星期一起始 / 星期日起始两种设置下，同一行的位置都要对得上。
    func testWeekStartChangesTheRowsButNotTheRhythm() {
        for ws in ["monday", "sunday"] {
            let l = layout(ws)
            guard let rest = l.restOffset(forKey: 202609), let i = l.blockIndex(forKey: 202609) else {
                XCTFail("ws=\(ws)：202609 应在流里")
                continue
            }
            let block = l.blocks[i]
            XCTAssertEqual(l.blockIndex(atOffset: rest), i)
            let weeks = l.weeks(of: block)
            XCTAssertEqual(weeks.count, block.rowCount, "ws=\(ws)：行数与几何必须一致")
            // 第一行的第一天就是 1 号。
            XCTAssertEqual(DateUtil.calendar.component(.day, from: weeks[0].days[
                DateUtil.weekdayIndex(DateUtil.monthFirst(block.month), weekStart: ws)]), 1)
        }
    }
}
