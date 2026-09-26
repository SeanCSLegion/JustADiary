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
///    小标题**坐在本月第一行的上留白里**，底边离日期数字只差 4pt —— 也就是
///    「紧贴数字上方」。前几版（一整周 94pt → 35pt → 21pt 的空带）都被用户否掉：
///    「间隔太多」「还是太高」「要紧贴数字上方」；
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

    /// 2) 月份之间**不留空隙**，小标题坐在本月第一行的上留白里、紧贴数字上方。
    ///
    /// 用户的尺子换了三次：一整周（94pt）→ 35pt → 现在「紧贴数字上方」：行与行挨着，
    /// 标题底边离数字只差 4pt。
    func testMonthsAreAdjacentAndLabelHugsTheNumbers() throws {
        let l = layout()
        XCTAssertEqual(labelH, 21, "竖屏：15pt 字 → 21pt（就是这一行字）")
        let contentTop = DayDraw.contentTopPadding(metrics)
        let tightGap: CGFloat = 4
        // 数字上方要留得下这一行字（留白够 + 标题落在行内，不压到上个月的日期上）。
        XCTAssertGreaterThan(contentTop - tightGap, labelH - 8,
                             "第一行的上留白要放得下小标题（留白 \(contentTop)）")
        for block in l.blocks.prefix(24) {
            let next = l.blocks[block.index + 1]
            XCTAssertEqual(next.top, block.bottom, accuracy: 0.001,
                           "\(block.key) → \(next.key) 之间不留空隙")
            XCTAssertEqual(next.rowCount, CalendarLayout.displayedWeekCount(inMonth: next.month,
                                                                           ws: l.weekStart))
            // 小标题底边 = 本月第一行顶 + 上留白 − 4pt；顶边仍在行内（≥ 行顶）。
            let labelBottom = next.top + contentTop - tightGap
            XCTAssertGreaterThanOrEqual(labelBottom - labelH, next.top - 0.001,
                                        "小标题整体落在本月第一行之内")
            let contentTopY = next.top + contentTop
            XCTAssertEqual(contentTopY - labelBottom, tightGap, accuracy: 0.001,
                           "标题底边离数字 4pt（紧贴）")
        }
    }

    /// 横屏左栏用紧凑字号，标题那一行也跟着小一号；行高更矮时标题仍要落在行内。
    func testCompactLabelIsSmallerAndStillFits() {
        let compact = CalendarLayout.flowLabelBandHeight(compact: true)
        XCTAssertEqual(compact, 18, "横屏：13pt 字 → 18pt")
        XCTAssertLessThan(compact, labelH)
        XCTAssertLessThan(compact, 45 * 0.7, "横屏一行只有 45pt，标题也得跟着小")
        // 横屏（隐藏农历，日号 ~15pt）：上留白还放得下这行字。
        let compactMetrics = CalendarLayout.flowMetrics(width: 307, rowH: 40.5, lunar: false, compact: true)
        let padding = DayDraw.contentTopPadding(compactMetrics)
        XCTAssertGreaterThan(padding, 8, "上留白要有意义地大于 0（\(padding)）")
        XCTAssertLessThanOrEqual(compact, padding + 8, "标题最多略微压进上一行的空白里")
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
    /// 小标题带露在视口底部（「1 号上方紧贴显示月份」的那一行字）。
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
