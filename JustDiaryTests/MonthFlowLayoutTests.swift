import XCTest
import SwiftUI
@testable import JustDiary

/// 连续月历流（`MonthFlowLayout`）的几何回归。
///
/// 月视图改成连续滚动之后，「哪一行在哪儿」不再由 SwiftUI 的布局给出，而是这份
/// 布局算出来的 —— morph 的起点、顶部月份、跳月位置全都读它。所以它的三条约定
/// 必须有测试守住：
/// 1. 行高全局一致（`rowH`），月内相邻两行正好差一个 `rowH`；
/// 2. **月份之间隔一条 `flowMonthGap`（16pt）**（下一块的 `top` == 上一块的 `bottom`
///    + 空隙），从上到下是「上个月的日期 → 小标题 → 分割线 → 本月日期」：小标题整条
///    住在这条空隙里，底边在本月第一行顶上方 3pt（= 分割线上方 3pt）。这条尺子
///    被用户来回改过几版（一整周 94pt 空带 → 35pt → 21pt → 「紧贴数字上方」→
///    「要在分割线上方才对」→ 「两个月之间的间隔窄了一点」），现在这一版是最终版，
///    别再调换次序；
/// 3. 静止位置 = 该月第一行的顶，此时视口里正好是「标题槽 + 星期栏 + 六行日期」
///    —— 与改造前的静止画面一致。
final class MonthFlowLayoutTests: XCTestCase {

    /// 竖屏 402×874 实测：日历区 665 = 672 − 84（头部）− 83（浮条）− …，行高 = (665 − 102) / 6，
    /// 视口 = 665 − 72（标题槽）− 30（星期栏）。
    private let rowH: CGFloat = (665 - CalendarLayout.bigTitleH - CalendarLayout.weekdayHeaderH) / 6
    private let viewportH: CGFloat = 665 - CalendarLayout.bigTitleH - CalendarLayout.weekdayHeaderH

    /// 竖屏小标题这一行字的高度（15pt 字 → 21pt）。
    private var labelH: CGFloat { CalendarLayout.flowLabelBandHeight(compact: false) }
    /// 月份之间那条空隙（16pt）。
    private var gap: CGFloat { CalendarLayout.flowMonthGap }
    /// 小标题底边到分割线的间隙（3pt）。
    private var tightGap: CGFloat { CalendarLayout.flowLabelTightGap }
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

    /// 1) 行高一致：月内相邻两行的顶正好差一个 `rowH`；月份之间只多出一条固定的空隙。
    func testRowsInsideAMonthAreExactlyOneRowApart() {
        let l = layout()
        for block in l.blocks where [202601, 202602, 202606, 202608, 202609].contains(block.key) {
            XCTAssertGreaterThan(block.rowCount, 0)
            for row in 1..<block.rowCount {
                XCTAssertEqual(l.rowTop(of: block, row: row) - l.rowTop(of: block, row: row - 1),
                               rowH, accuracy: 0.001, "\(block.key) 第 \(row) 行")
            }
            // 最后一行到底 = 下个月第一行的顶 − 那条空隙（两块之间只隔这一个数）。
            XCTAssertEqual(l.blocks[block.index + 1].top - l.rowTop(of: block, row: block.rowCount - 1),
                           rowH + gap, accuracy: 0.001, "\(block.key) 最后一行到底就是下个月的开始")
            XCTAssertEqual(l.blocks[block.index + 1].top, block.bottom + gap, accuracy: 0.001,
                           "上一块的底 + 空隙 = 下一块的顶")
        }
    }

    /// 2) 月份之间隔一条 `flowMonthGap`，小标题画在这条空隙里、贴在分割线上方。
    ///
    /// 从上到下的次序：上个月的日期 → 小标题 → 分割线（画在本月第一行的顶）→ 本月日期。
    /// 用户的尺子改过几版（一整周 94pt → 35pt → 「紧贴数字上方」→「要在分割线上方」→
    /// 「两个月之间的间隔窄了一点」），现在这一版是最终版：
    /// - 下一块的 `top` = 上一块的 `bottom` + 16pt，小标题底边 = `top` − 3pt；
    /// - 上一行底部的留白（竖屏 26.9pt）也还在，两段加起来离上个月最后一行数字
    ///   约 13pt，小标题因此不会碰到任何数字。
    func testMonthsAreSeparatedByTheGapAndLabelSitsAboveTheDivider() {
        let l = layout()
        XCTAssertEqual(labelH, 21, "竖屏：15pt 字 → 21pt（就是这一行字）")
        XCTAssertEqual(gap, 16, "月份之间的空隙：16pt")
        XCTAssertEqual(tightGap, 3, "小标题底边离分割线 3pt")
        let contentTop = DayDraw.contentTopPadding(metrics)
        for block in l.blocks.prefix(24) {
            let next = l.blocks[block.index + 1]
            XCTAssertEqual(next.top - block.bottom, gap, accuracy: 0.001,
                           "\(block.key) → \(next.key) 之间正好隔一条空隙")
            // 小标题：底边贴分割线上方 3pt，整条落在块首那条空隙里（上沿可以伸进
            // 上一行底部的留白，那里没有日期）。
            let labelBottom = next.top - tightGap
            let labelTop = labelBottom - labelH
            XCTAssertEqual(labelBottom, next.top - tightGap, accuracy: 0.001, "小标题底边贴分割线")
            XCTAssertGreaterThanOrEqual(labelTop, next.top - gap - labelH,
                                        "小标题整条住在块首那条空隙里")
            XCTAssertLessThan(labelTop, block.bottom, "小标题上沿仍在上一块之内（不是凭空多一条带）")
            // 呼吸：上个月最后一行「日期内容」的底边（行底再往上收 `contentTop` 的留白）
            // 到小标题上沿的距离；小标题底边到本月第一行「日期内容」的顶同理。
            // 首块前面没有空隙（`top == 0`），它的上一「行」就是流顶端。
            XCTAssertGreaterThan(gap + contentTop - labelH - tightGap, 10,
                                 "\(block.key) 的日期底边到小标题上沿要留出呼吸（实测 \(gap + contentTop - labelH - tightGap)）")
            XCTAssertGreaterThan(contentTop + tightGap, 10,
                                 "小标题底边到本月日期顶的呼吸（实测 \(contentTop + tightGap)）")
            // 空隙 + 留白一起放得下小标题（不然它会压到上个月的日期上）。
            XCTAssertGreaterThanOrEqual(contentTop + gap, labelH + tightGap,
                                        "竖屏留白 + 空隙要放得下小标题（\(contentTop) + \(gap) ≥ \(labelH + tightGap)）")
        }
        // 月份正好从周首日开始的那几个月，上个月最后一行与小标题同列的那一格是
        // **上个月的日期**（会被画出来）；竖屏靠「空隙 + 留白」错开，横屏留白小得多
        // （见 `testCompactLabelIsSmallerAndStillFits`）。
        var weekStartAligned = 0
        for block in l.blocks.prefix(120) where
            CalendarLayout.monthLabelColumn(inMonth: l.blocks[block.index + 1].month,
                                            ws: "monday") == 0 {
            weekStartAligned += 1
        }
        XCTAssertGreaterThan(weekStartAligned, 0, "确实存在「1 号就是周首日」的月份")
    }

    /// 月份之间的空隙真的**拉开了**（这次的用户反馈：「两个月之间的间隔窄了一点，
    /// 小月份会和上一行的日期太近了」）。
    ///
    /// 空隙是 16pt，且恒为 16pt：不随行高（竖屏 93.8 / 横屏 40.5）变 —— 它属于块首，
    /// 与 `rowH` 无关。
    func testEveryMonthPairIsSeparatedByTheSameGap() {
        for rowH in [93.83333333333333, 45.0, 40.5] {
            let l = MonthFlowLayout(weekStart: "monday", rowH: rowH)
            for i in 0..<240 {
                XCTAssertEqual(l.blocks[i + 1].top - l.blocks[i].bottom, gap, accuracy: 0.001,
                               "rowH=\(rowH) \(l.blocks[i].key) → \(l.blocks[i + 1].key)")
            }
            // 第一块前面**没有**空隙：整条流从 0 开始（否则首月静止时上面多一条空带）。
            XCTAssertEqual(l.blocks[0].top, 0, accuracy: 0.001, "rowH=\(rowH)：首块从 0 开始")
        }
    }

    /// 横屏左栏用紧凑字号，标题那一行也跟着小一号；行高更矮时标题仍要落在行内。
    func testCompactLabelIsSmallerAndStillFits() {
        let compact = CalendarLayout.flowLabelBandHeight(compact: true)
        XCTAssertEqual(compact, 18, "横屏：13pt 字 → 18pt")
        XCTAssertLessThan(compact, labelH)
        XCTAssertLessThan(compact, 45 * 0.7, "横屏一行只有 45pt，标题也得跟着小")
        // 横屏（隐藏农历）：上一行的底部留白 + 块首那条空隙要放得下这一行字。
        let compactMetrics = CalendarLayout.flowMetrics(width: 307, rowH: 40.5, lunar: false, compact: true)
        let padding = DayDraw.contentTopPadding(compactMetrics)
        XCTAssertGreaterThan(padding, 8, "上留白要有意义地大于 0（\(padding)）")
        XCTAssertLessThan(compact + tightGap, 40.5, "整行 40.5pt，标题 + 间距仍要落在这一行里")
        // **这一版正好收住了横屏**（改动前不行）：一行 40.5pt 的上留白只有 ~11.4pt，
        // 放不下 18pt 的小标题，而 1 号正好落在周首日的月份（约 1/7）里上一行同一列
        // 是有日期的 —— 那时小标题会压进那一格约 7pt。加上块首那条空隙后，
        // 「留白 + 空隙」（23.4pt）已经比「小标题 + 间隙」（21pt）宽裕，一格都不压。
        XCTAssertGreaterThan(padding + gap, compact + tightGap,
                             "横屏：留白 + 空隙（\(padding) + \(gap)）要盖得住小标题（\(compact + tightGap)）")
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

    /// 静止画面（竖屏）：视口 = 六行。六行月份正好铺满（下个月从那 16pt 空隙之后才开始，
    /// 全在视口之外），五行的月份则把下个月**那条空隙里的小标题与第一行日期**露在视口
    /// 底部（1 号上方紧贴着的那行月份小字）。
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
                XCTAssertEqual(nextTop, rest + viewportH + gap, accuracy: 0.001,
                               "六行月份之后：先是那条 16pt 空隙，然后才是下个月第一行")
                XCTAssertGreaterThan(nextTop, rest + viewportH, "所以下一行整个在视口之外")
            } else {
                XCTAssertLessThan(rowsH, viewportH, "五行月份底下会露出下个月的开头")
                XCTAssertEqual(nextTop, rest + rowsH + gap, accuracy: 0.001,
                               "下个月在本月最后一行之后隔一条空隙")
                XCTAssertLessThan(nextTop, rest + viewportH, "所以下一行确实露在视口里")
                // 露出来的那段里包含整条小标题（它住在空隙与上一行留白里）。
                XCTAssertLessThan(nextTop - tightGap - labelH, rest + viewportH,
                                  "下个月的小标题也要落在视口里")
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
    /// 月份」「快速滑动会乱显示」）。这里守住三条：静止时是它自己；只露出下个月一小截
    /// 时仍显示本月；视口顶部正好落在月份之间那条空隙里时也仍显示本月（空隙属于下一块，
    /// 单看 `blockIndex` 会提前翻页）。
    ///
    /// 分界点 = **上个月最后一行与本月第一行之间那条空隙的中点**（= 两个月的视觉分界）
    /// 越过视口中心的那一刻，所以下面拿空隙中点当参照来取「还差一点」/「已经过半」。
    func testDominantMonthIsTheOneFillingMostOfTheViewport() {
        let l = layout()
        for key in [202609, 202602, 202608] {
            guard let rest = l.restOffset(forKey: key), let i = l.blockIndex(forKey: key) else {
                XCTFail("\(key) 应在流里")
                continue
            }
            XCTAssertEqual(l.dominantBlockIndex(offset: rest, viewportH: viewportH), i,
                           "\(key) 静止时顶部月份就是它")

            let boundary = l.blocks[i + 1].top
            // 两个月的视觉分界（空隙中点）：视口中心越过它就该翻页。
            let seam = l.blocks[i].bottom + gap / 2
            XCTAssertEqual(seam, boundary - gap / 2, accuracy: 0.001, "\(key)：分界在空隙中点")

            // 关键差别：视口顶部还落在上个月的最后一行里，但屏幕上**下个月已经过半**
            // —— 这时候要显示下个月（「占据屏幕主要的月份」）。
            let mostlyNext = seam - (viewportH / 2) + 2
            XCTAssertEqual(l.blockIndex(atOffset: mostlyNext), i, "\(key)：顶部那一块仍是上个月")
            XCTAssertEqual(l.dominantBlockIndex(offset: mostlyNext, viewportH: viewportH), i + 1,
                           "\(key)：下个月占了多半屏，顶部月份就该是它")

            // 反过来：上个月仍占多半屏时不换（这个偏移落在上个月的最后一行里）。
            let mostlyCurrent = seam - (viewportH / 2) - 2
            XCTAssertGreaterThanOrEqual(mostlyCurrent, l.blocks[i].top, "\(key)：还在上个月之内")
            XCTAssertEqual(l.dominantBlockIndex(offset: mostlyCurrent, viewportH: viewportH), i,
                           "\(key)：上个月还占多数，不该换")

            // 视口顶部落在空隙里（= 两个月的视觉分界已经在屏幕上方）：上个月最后一行
            // 也整个滚上去了，屏幕上只剩本月的行 —— 顶部月份该换成它。
            let inGap = boundary - gap / 2
            XCTAssertGreaterThanOrEqual(inGap, l.blocks[i].bottom, "\(key)：\(inGap) 在空隙里")
            XCTAssertGreaterThan(inGap, l.blocks[i].bottom - rowH, "上个月最后一行已整个在屏幕上方")
            XCTAssertEqual(l.dominantBlockIndex(offset: inGap, viewportH: viewportH), i + 1,
                           "\(key)：视口顶部进了空隙、上个月一行都不剩，顶部月份该换成下个月")
            // 空隙里那一块必须在「可见块」里：morph 的源要从它取「屏幕上半行」的那些行，
            // 少了它，morph 第一帧会缺一块（`MonthFlowView.morphSource`）。
            let visible = l.visibleBlocks(offset: inGap, viewportH: viewportH, margin: 0)
            XCTAssertEqual(visible.first?.key, key, "\(key)：空隙上方的块也要算进可见块")

        }

        // 连续扫过一整段流：顶部月份只能一格一格往前走，不能跳月、不能倒退，
        // 也不能在空隙附近来回抖（每翻一次都记下来）。
        let start = l.blocks[0].top
        let end = min(l.contentH - viewportH, start + 2000)
        var lastDominant = l.dominantBlockIndex(offset: start, viewportH: viewportH)
        var flips = 0
        var o = start
        while o < end {
            let d = l.dominantBlockIndex(offset: o, viewportH: viewportH)
            if d != lastDominant {
                XCTAssertEqual(d, lastDominant + 1,
                               "offset \(o)：顶部月份只能一格一格往前走，不能跳月或倒退")
                flips += 1
                lastDominant = d
            }
            o += 0.5
        }
        XCTAssertGreaterThanOrEqual(flips, 4, "滚动 2000pt 该翻过好几个月（实际 \(flips) 次）")
    }

    /// 「年→月」morph 的下个月预告，收尾那一帧必须与真实月视图**逐像素对齐**。
    ///
    /// 回归的是两次踩到的坑：① 日期行忘了加 `flowMonthGap`（收尾整块日期向下跳一格）；
    /// ② 小标题把 `flowMonthGap` 减了第二次（收尾标题向上跳 16pt）。
    /// 这里把 `CalendarLayout.peekGeometry`（morph 层）与 `MonthFlowLayout`（真实流）在同一
    /// 坐标系下逐月对照：`rows` 取 4…6 都要成立。
    func testYearToMonthPeekMatchesTheFlowForEveryRowCount() {
        let l = layout()
        // morph 的网格：日历区顶部 = 标题槽 + 星期栏，整体 6 行高。
        let fullRect = CalendarLayout.fullMonthGridRect(in: CGSize(width: 402, height: 665))
        for key in [202601, 202602, 202608, 202609, 202610, 202612] {
            guard let i = l.blockIndex(forKey: key), i + 1 < l.blocks.count else {
                XCTFail("\(key) 应在流里")
                continue
            }
            let block = l.blocks[i]
            let next = l.blocks[i + 1]
            let peek = CalendarLayout.peekGeometry(fullRect: fullRect, rows: block.rowCount)

            // 真实流：静止时本月第一行顶到视口顶（视口顶 = fullRect.minY）。
            let rest = l.restOffset(forKey: key)!
            let flowNextRowTop = next.top - rest + fullRect.minY
            let flowLabelBottom = flowNextRowTop - tightGap

            XCTAssertEqual(peek.nextRowTop, flowNextRowTop, accuracy: 0.001,
                           "\(key)（\(block.rowCount) 行）：morph 里下个月第一行的顶 = 真实流")
            XCTAssertEqual(peek.labelBottom, flowLabelBottom, accuracy: 0.001,
                           "\(key)：morph 里小标题底边 = 真实流（别再减第二次空隙）")
            XCTAssertEqual(peek.nextRowTop - peek.labelBottom, tightGap, accuracy: 0.001,
                           "\(key)：小标题贴在分割线上方 \(tightGap)pt")
        }
        // 4…6 行都要成立（补一个假 rows 覆盖 4 行月份）
        for rows in 4...6 {
            let peek = CalendarLayout.peekGeometry(fullRect: fullRect, rows: rows)
            XCTAssertEqual(peek.nextRowTop - peek.labelBottom, tightGap, accuracy: 0.001,
                           "rows=\(rows)：标题贴分割线")
            XCTAssertEqual(peek.nextRowTop,
                           fullRect.minY + CGFloat(rows) * (fullRect.height / 6) + gap,
                           accuracy: 0.001, "rows=\(rows)：下个月第一行 = 本月 rows 行 + 空隙")
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
