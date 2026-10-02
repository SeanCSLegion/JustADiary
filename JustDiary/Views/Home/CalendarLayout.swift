import Foundation
import SwiftUI

enum CalendarMode {
    case year
    case month
    case week
}

/// 日历密度：由**可用高度**决定，用来替代原来「月↔周整屏 morph」在横屏的职责。
///
/// 竖屏仍走原来的 `mode`（年/月/周三态 morph）；横屏只有 `month` 一种交互，
/// 高度不够时**只隐藏农历行**，六行日期始终保留。
///
/// > 2026-10-01 清理：这里原本还有第三档 `.weekStrip`（「放不下六周格就把左栏换成
/// > 一行周条、横向翻周」），但它**只判不画** —— `HomeView` 只读 `showsLunar` 与
/// > `rowHeight`，从来没有渲染分支，设计稿里那张降级稿也一并删了。现在按实际行为
/// > 收成两档：高度再小也只是隐藏农历、把行高夹在下限（`dayRowHeight`），网格会被
/// > `HomeView` 的 `.clipped()` 裁掉。
struct CalendarDensity: Equatable {
    /// 是否画农历行。
    var showsLunar: Bool

    /// 带农历行时每行至少这么高，才放得下 20pt 日号 + 11pt 农历 + 选中圆。
    static let lunarRowHeight: CGFloat = 44

    /// **不带**农历行时每行至少这么高：只剩日号与选中圆。
    ///
    /// 比 44 低是有意的：iPhone SE 横屏只有 375pt 高，扣掉顶部留白、标题/星期栏
    /// 与底部系统浮条（64pt）后，六行只剩 ~40pt。40pt 的格子放 ~14pt 日号 +
    /// ~32pt 选中圆仍然宽裕（日号字号本来也由格高推导）。
    static let dayRowHeight: CGFloat = 38

    /// 本密度下每行的最小高度。
    var minimumRowHeight: CGFloat { showsLunar ? Self.lunarRowHeight : Self.dayRowHeight }

    /// 每行实际分到的高度。
    ///
    /// 可用高度平均分给 `rows` 行，**向下取整** —— 向上取整会让网格比日历区还高，
    /// 最后一行被裁掉；但不低于本密度的下限。
    func rowHeight(availableHeight: CGFloat, rows: Int) -> CGFloat {
        guard rows > 0 else { return minimumRowHeight }
        return max(minimumRowHeight, (availableHeight / CGFloat(rows)).rounded(.down))
    }

    /// 由可用高度与**实际需要画的行数**决定密度（只剩「带农历 / 不带农历」两种结果）。
    ///
    /// - Parameters:
    ///   - availableHeight: 日历区可用高度（不含标题/星期栏/底部预留）。
    ///   - rows: 实际行数（见 `CalendarLayout.displayedWeeks`，不要传固定的 6）。
    ///   - wantsLunar: 是否希望显示农历行。
    static func resolve(availableHeight: CGFloat, rows: Int, wantsLunar: Bool) -> CalendarDensity {
        let needed = max(1, rows)
        // 行高随可用高度分配，并夹在 [最小行高, 舒适上限]：
        // 扣掉农历行需要的空间后，剩下的每行还不到最小行高，才放弃农历。
        //
        // 这里**向下取整**，与 `rowHeight(availableHeight:rows:)` 保持一致：
        // 若这里向上取整，会出现「判定说放得下、实际每行却高出 1pt」的组合，
        // 网格于是比日历区高，最后一行被裁掉半行。
        let perRow = (availableHeight / CGFloat(needed)).rounded(.down)
        if perRow >= lunarRowHeight + 16 {
            return CalendarDensity(showsLunar: wantsLunar)
        }
        return CalendarDensity(showsLunar: false)
    }
}

struct WeekDays {
    var start: Date
    var days: [Date]
}

enum CL {
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: lerp(a.origin.x, b.origin.x, t),
               y: lerp(a.origin.y, b.origin.y, t),
               width: lerp(a.width, b.width, t),
               height: lerp(a.height, b.height, t))
    }

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// 平滑的 S 形（ease-in-out）插值参数，输入会被夹到 0…1：`6t⁵ − 15t⁴ + 10t³`。
    ///
    /// 月↔周 morph 里「相邻月的日期」用它而不是线性 `progress`：线性参数要到动画最后一帧
    /// 才走完，于是那批日期的位移、淡出、被裁剪边切掉三件事结束时间对不上，收尾显得突然。
    ///
    /// 用五次（smootherstep）而不是三次（smoothstep）：三次在两端仍有肉眼可见的加速度
    /// 突变，中段爬升也偏快；五次曲线的一、二阶导数在两端都为 0，起步和收尾都更「软」，
    /// 中段（0.25→0.75）走完 84%，其余时间留给两头的缓入缓出。
    static func smoothstep(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}

struct DayMetrics {
    var cellW: CGFloat
    var cellH: CGFloat
    var dayFont: CGFloat
    var lunarFont: CGFloat
    var lunarAlpha: Double
    var dividerAlpha: Double
    /// 「这天有日记」那条标记条与日号之间的间距：**日号盒底 → 条顶**（pt）。
    ///
    /// 它是一个**绝对**值，而年历的日号只有 ~13pt（月视图是 20pt），同样的 2pt 摆在
    /// 小字号下面就明显偏远 —— 实测年历里「日号视觉底边 → 条顶」有 4pt（2pt 间距加上
    /// 字体自身的下伸部）。所以年历的迷你月用 `0`（见 `miniMetrics`），月/周/连续流
    /// 保持 `2` 不变。
    var flagGap: CGFloat = 2

    static func lerp(_ a: DayMetrics, _ b: DayMetrics, _ t: Double) -> DayMetrics {
        DayMetrics(cellW: CL.lerp(a.cellW, b.cellW, t),
                   cellH: CL.lerp(a.cellH, b.cellH, t),
                   dayFont: CL.lerp(a.dayFont, b.dayFont, t),
                   lunarFont: CL.lerp(a.lunarFont, b.lunarFont, t),
                   lunarAlpha: CL.lerp(a.lunarAlpha, b.lunarAlpha, t),
                   dividerAlpha: CL.lerp(a.dividerAlpha, b.dividerAlpha, t),
                   // 年↔月 morph 的两端本来就不同（迷你月 0 / 月视图 2），这里跟着插值，
                   // 收尾换回真实图层时标记条才不会「啪」地跳一下。
                   flagGap: CL.lerp(a.flagGap, b.flagGap, t))
    }
}

enum CalendarLayout {
    static let morphDuration: Double = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SLOW_MORPH"] == "1" { return 3.0 }
        if ProcessInfo.processInfo.arguments.contains("-slow-morph") { return 3.0 }
        #endif
        return 0.6
    }()
    // 年↔月缩放切换。此前用 easeInOut：它从零速度起步，前 1/4 时间只走完约
    // 13% 进度，所以「开头一段几乎不动」，观感上就比月↔周切换慢半拍。
    // 现在与月↔周共用同一条起步带速度、尾部减速的曲线，两者节奏一致。
    static var morphAnimation: Animation { morphSlideAnimation }

    /// Used when 设置 › 辅助功能 › 减弱动态效果 is on: the same state change, but
    /// the travel is collapsed into a quick cross-fade rather than a sweep.
    static var reducedMorphAnimation: Animation { .linear(duration: 0.18) }

    // 月↔周滑动切换：无回弹的速度连续曲线——起步带速度、减速集中在尾部、
    // 精确停在终点（无弹簧过冲/回弹），日期行与内容区共用同一曲线
    static var morphSlideAnimation: Animation {
        .timingCurve(0.2, 0.75, 0.3, 1.0, duration: morphDuration)
    }

    static let weekdayHeaderH: CGFloat = 30
    static let bigTitleH: CGFloat = 72
    /// 横屏分栏专用的紧凑标题行 / 星期栏。
    ///
    /// 横屏只有 402pt 高，标题每多占 1pt 就是从日期行里扣 1pt；这一对数字是
    /// 「六行月格 + 底部系统浮条都放得下」的边界值，调大就会整块降级成周条。
    static let compactMonthTitleH: CGFloat = 34
    static let compactWeekdayHeaderH: CGFloat = 26
    static let weekStripH: CGFloat = 68
    static let dayTitleH: CGFloat = 40

    static let yearTitleH: CGFloat = 62
    static let yearPad: CGFloat = 16
    /// 月与月之间的空隙：从 10 收到 6，给迷你月里的字号留出空间。
    static let yearSpacing: CGFloat = 6
    /// 年历页**最上面一行卡片**与标题分隔线之间的留白（`YearPageView` 的 `.padding(.top, 8)`）。
    /// 抽出来是为了让 `yearCardRect` 与年历页用同一个数 —— 两边各写一个字面量的话，
    /// 「月→年」morph 的终点会与真实年历差几 pt。
    static let yearTopPad: CGFloat = 8

    static func monthCellW(width: CGFloat) -> CGFloat { width / 7 }

    static func weekdayFontSize(cellW: CGFloat) -> CGFloat { min(max(cellW * 0.26, 11), 14) }

    static func monthCellH(areaH: CGFloat) -> CGFloat {
        (areaH - bigTitleH - weekdayHeaderH) / 6
    }

    static func monthMetrics(width: CGFloat, areaH: CGFloat, lunar: Bool) -> DayMetrics {
        DayMetrics(cellW: monthCellW(width: width),
                   cellH: monthCellH(areaH: areaH),
                   dayFont: 20,
                   lunarFont: 11,
                   lunarAlpha: lunar ? 1 : 0,
                   dividerAlpha: 1)
    }

    static func weekMetrics(width: CGFloat, lunar: Bool) -> DayMetrics {
        DayMetrics(cellW: monthCellW(width: width),
                   cellH: weekStripH,
                   dayFont: 20,
                   lunarFont: 11,
                   lunarAlpha: lunar ? 1 : 0,
                   dividerAlpha: 0)
    }

    /// 连续月历流（`MonthFlowView`）单行的绘制参数。
    ///
    /// 字号跟着行高走：竖屏行高 ~94pt，仍是设计里的 20/11；横屏左栏只有 ~40pt 一格，
    /// 20pt 日号 + 11pt 农历会上下叠在一起（横屏左栏一直是按格高推导字号）。
    static func flowMetrics(width: CGFloat, rowH: CGFloat, lunar: Bool,
                            compact: Bool = false) -> DayMetrics {
        DayMetrics(cellW: monthCellW(width: width),
                   cellH: rowH,
                   dayFont: dayFont(forCellH: rowH),
                   lunarFont: lunarFont(forCellH: rowH),
                   lunarAlpha: lunar ? 1 : 0,
                   dividerAlpha: 1)
    }

    static func dayFont(forCellH cellH: CGFloat) -> CGFloat {
        min(20, max(13, cellH * 0.34))
    }

    static func lunarFont(forCellH cellH: CGFloat) -> CGFloat {
        min(11, max(9, cellH * 0.18))
    }

    static func yearCardSize(in size: CGSize) -> CGSize {
        CGSize(width: (size.width - yearPad * 2 - yearSpacing * 2) / 3,
               height: (size.height - yearTitleH - yearTopPad - yearSpacing * 3) / 4)
    }

    /// 年历里迷你日期字号：格子变小的时候按格宽收缩，避免相邻日期叠在一起。
    ///
    /// 3 列布局下单元格约 15pt 宽，所以 15×0.95 ≈ 14pt —— 比原来的 11pt 明显大；
    /// 上限再由「格高 × 0.5」兜住，保证选中圆不会碰到上下两行。
    static func miniDayFont(cellW: CGFloat, cellH: CGFloat) -> CGFloat {
        min(14, max(9, min(cellW * 0.95, cellH * 0.5)))
    }

    static let miniLunarHidden: CGFloat = 0

    static func yearCardRect(month: Int, in size: CGSize) -> CGRect {
        let card = yearCardSize(in: size)
        let col = CGFloat((month - 1) % 3)
        let row = CGFloat((month - 1) / 3)
        return CGRect(x: yearPad + col * (card.width + yearSpacing),
                      y: yearTitleH + yearTopPad + row * (card.height + yearSpacing),
                      width: card.width,
                      height: card.height)
    }

    static let miniPad: CGFloat = 6
    static let miniTitleH: CGFloat = 17

    static func miniGridRect(month: Int, in size: CGSize) -> CGRect {
        let card = yearCardRect(month: month, in: size)
        return CGRect(x: card.minX + miniPad,
                      y: card.minY + miniPad + miniTitleH,
                      width: card.width - miniPad * 2,
                      height: card.height - miniPad * 2 - miniTitleH)
    }

    /// 迷你月标题在容器里的矩形（**绝对坐标**，含卡片原点）。
    ///
    /// 年历页与「月→年」morph 都**必须**用这一个矩形来摆标题：两侧各写一套时，
    /// `.position`（按中心对位）与 VStack 的取整会差 1/3pt，morph 收尾换回真实
    /// 年历那一帧，月份数字会「啪」地挪一下。现在两边都用
    /// `frame(width:height:alignment: .leading)` + `offset`。
    ///
    /// 「月→年」morph 的 ZStack 就是整块容器，直接用这个绝对矩形；年历页的 ZStack
    /// 是**卡片本身**，要用下面的卡片内偏移（`miniTitleInCard` / `miniGridInCard`），
    /// 再套绝对坐标就会把迷你月推出去、和隔壁月叠在一起。
    static func miniTitleRect(month: Int, in size: CGSize) -> CGRect {
        let card = yearCardRect(month: month, in: size)
        return CGRect(x: card.minX + miniPad,
                      y: card.minY + miniPad,
                      width: card.width - miniPad * 2,
                      height: miniTitleH)
    }

    /// 卡片内偏移：标题在左上角内缩 `miniPad`，网格紧接标题下方。
    static let miniTitleInCard = CGPoint(x: miniPad, y: miniPad)
    static var miniGridInCard: CGPoint { CGPoint(x: miniPad, y: miniPad + miniTitleH) }

    /// 年历迷你月的绘制参数 —— 年历页与「月→年」morph 的起点必须完全一致，
    /// 否则过渡到一半会出现字号/间距的跳变（之前月份数字会「跳一下」）。
    static func miniMetrics(in size: CGSize) -> DayMetrics {
        let grid = miniGridRect(month: 1, in: size)
        let cellW = grid.width / 7
        let cellH = grid.height / 6
        return DayMetrics(cellW: cellW,
                          cellH: cellH,
                          dayFont: miniDayFont(cellW: cellW, cellH: cellH),
                          lunarFont: 6,
                          lunarAlpha: miniLunarHidden,
                          dividerAlpha: 0,
                          // 年历的日号只有 ~13pt，标记条贴紧日号才不显得「掉在下面」
                          // （月视图保持默认的 2pt，那里字号大一档，观感本来就合适）。
                          flagGap: 0)
    }

    /// 「年→月」morph 里那条**下个月预告**（小标题 + 第一行日期）的几何。
    ///
    /// `MonthFlowView` 的连续流里，下个月的块 = 本月 `rows` 行 + 块首那条 `flowMonthGap`；
    /// morph 的网格也是按 6 行画（`fullRect.height / 6`），所以两边的尺子完全一样：
    ///
    ///     nextRowTop   = fullRect.minY + rows × rowH + flowMonthGap   ← 下个月第一行的顶
    ///     labelBottom  = nextRowTop − flowLabelTightGap               ← 小标题底边（贴分割线）
    ///
    /// **再减一次 `flowMonthGap` 就错了**（实测小标题会高 16pt，收尾换回真图层时往上跳）：
    /// 它是 morph 层与真实流最容易对不上的一个数，所以抽出来给 `MorphViews` 和测试共用。
    static func peekGeometry(fullRect: CGRect, rows: Int) -> (nextRowTop: CGFloat, labelBottom: CGFloat) {
        let rowH = fullRect.height / 6
        let nextRowTop = fullRect.minY + CGFloat(max(1, rows)) * rowH + flowMonthGap
        return (nextRowTop, nextRowTop - flowLabelTightGap)
    }

    static func fullMonthGridRect(in size: CGSize) -> CGRect {
        CGRect(x: 0,
               y: bigTitleH + weekdayHeaderH,
               width: size.width,
               height: size.height - bigTitleH - weekdayHeaderH)
    }

    static func monthKey(_ date: Date) -> Int {
        let c = DateUtil.calendar.dateComponents([.year, .month], from: date)
        return (c.year ?? 0) * 100 + (c.month ?? 0)
    }

    static func dateForMonthKey(_ key: Int) -> Date {
        var comps = DateComponents()
        comps.year = key / 100
        comps.month = key % 100
        comps.day = 1
        return DateUtil.calendar.date(from: comps) ?? Date()
    }

    /// 连续月历流里小标题的字号（竖屏 15 / 横屏紧凑 13）。
    static func flowLabelFontSize(compact: Bool) -> CGFloat { compact ? 13 : 15 }

    /// 连续月历流里「月份之间那一带」的高度 = **小标题这一行字本身的高度**。
    ///
    /// 用户看过第一版（一个整行高 ≈ 94pt）说「间隔太多」，看过第二版（35pt）又说
    /// 「还是太高，应该紧贴月份高度」，所以这里不再加任何上下留白：
    /// 竖屏 15pt 字 → **21pt**；横屏紧凑 13pt 字 → **18pt**。
    /// 上下看起来的空白来自 `flowMonthGap` 与日期行自身的垂直居中留白，不需要带子再让一份。
    static func flowLabelBandHeight(compact: Bool) -> CGFloat {
        (flowLabelFontSize(compact: compact) * 1.4).rounded()
    }

    /// 小标题底边与它下面那条分割线（= 本月第一行的顶）之间的间隙 ——「紧贴」的那个「紧」。
    ///
    /// 三处必须用同一个数：`MonthFlowView` 画小标题、`MonthFlowView.morphSource` 冻结
    /// 小标题位置、`YearMonthMorphView` 的「下个月那一条」。各写一份的话，morph 收尾
    /// 换回真实图层时小标题会挪一下。
    static let flowLabelTightGap: CGFloat = 3

    /// 连续月历流里**月份之间那条真正的空隙**（插在上一块与下一块之间，小标题就画在这里）。
    ///
    /// 16pt 是量出来的：竖屏一行 93.8pt、日期内容上下各留 26.9pt 白边，小标题高 21pt +
    /// 贴线 3pt；16 − (26.9 − 21 − 3) ≈ 13pt 的净间隙落在「上个月最后一行数字」与
    /// 「小标题」之间（横屏一行 40.5pt 时约 10pt），两个月因此不再挤在一起。
    ///
    /// 这一版之前，两个月的周行是**紧挨着**的（`下一块的 top == 上一块的 bottom`），小标题
    /// 借用上一行底部的留白画在分割线上方 —— 于是「占满一行」的月份里，小标题离上一行的
    /// 日期只有那点留白，看着太挤（用户：「两个月之间的间隔窄了一点，小月份会和上一行的
    /// 日期太近了」）。现在每个月的块首自带这条空隙：
    ///
    ///     上一块的日期（最后一行，垂直居中，下面还有 contentTop ≈ 27pt 的留白）
    ///     ─┬─ 空隙 16pt：小标题画在这里，底边贴分割线 3pt
    ///      │  上个月最后一行数字底 → 小标题上沿 ≈ 13pt（竖屏；横屏 ≈ 10pt）
    ///     ─┴─ 分割线（= 本块第一行的顶，也就是 `Block.top`）
    ///        小标题底 → 本月数字顶 ≈ 30pt（竖屏；横屏 ≈ 14pt）
    ///
    /// 三条不变量都没变，变的是「下一块的 `top` = 上一块的 `bottom` + 这个空隙」：
    /// `restOffset` 仍取 `Block.top`（静止时第一行顶到视口顶，画面与改造前逐像素一致），
    /// 年↔月 morph 的终点也就不用重新推导。横屏左栏一行只有 40pt、上留白 ~11pt，
    /// 原来放不下 18pt 的小标题（会压进上一行那一格约 10pt），这条空隙也顺手把它收住了。
    static let flowMonthGap: CGFloat = 16

    /// 小标题该站在哪一列：**当月 1 号所在的那一列**（用户要求「小月份在 1 号的上方」，
    /// 不是整行居中）。列号 = 1 号是星期几（按周起始设置换算）。
    static func monthLabelColumn(inMonth month: Date, ws: String) -> Int {
        DateUtil.weekdayIndex(DateUtil.monthFirst(month), weekStart: ws)
    }

    /// 下一个月（月初），连续月历流里画「下个月的小标题」要用。
    static func nextMonth(_ month: Date) -> Date {
        DateUtil.calendar.date(byAdding: .month, value: 1, to: DateUtil.monthFirst(month)) ?? month
    }

    static let allMonthKeys: [Int] = {
        var keys: [Int] = []
        for y in 1900...2100 {
            for m in 1...12 { keys.append(y * 100 + m) }
        }
        return keys
    }()

    static let allYears: [Int] = Array(1900...2100)

    static func weekStart(of date: Date, ws: String) -> Date {
        let lead = DateUtil.weekdayIndex(date, weekStart: ws)
        return DateUtil.calendar.date(byAdding: .day, value: -lead, to: date) ?? date
    }

    static func weekKey(_ date: Date, ws: String) -> Int {
        let start = weekStart(of: date, ws: ws)
        return keyOfDate(start)
    }

    static func dateForWeekKey(_ key: Int) -> Date {
        var comps = DateComponents()
        comps.year = key / 10000
        comps.month = (key / 100) % 100
        comps.day = key % 100
        return DateUtil.calendar.date(from: comps) ?? Date()
    }

    private static var weekKeysCache: [String: [Int]] = [:]

    static func allWeekKeys(weekStart: String) -> [Int] {
        if let cached = weekKeysCache[weekStart] { return cached }
        let cal = DateUtil.calendar
        var comps = DateComponents()
        comps.year = 1900
        comps.month = 1
        comps.day = 1
        let start = cal.date(from: comps) ?? Date()
        let lead = DateUtil.weekdayIndex(start, weekStart: weekStart)
        var cursor = cal.date(byAdding: .day, value: -lead, to: start) ?? start
        let end = cal.date(from: DateComponents(year: 2101, month: 1, day: 1)) ?? start
        var keys: [Int] = []
        while cursor < end {
            keys.append(keyOfDate(cursor))
            cursor = cal.date(byAdding: .day, value: 7, to: cursor) ?? cursor
        }
        weekKeysCache[weekStart] = keys
        return keys
    }

    private static func keyOfDate(_ date: Date) -> Int {
        let c = DateUtil.calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    private static let lock = NSLock()
    private static var weeksCache: [Int: [WeekDays]] = [:]

    /// 实际需要绘制的周，去掉末尾「整周都不属于本月」的填充行。
    ///
    /// `weeks(inMonth:)` 固定返回 6 行（月份可能只占 5 行），末尾那行若一天都不在
    /// 本月内，就不该参与密度判定 —— 否则会把「5 行放得下」误判成「6 行放不下」，
    /// 横屏于是错误地降级成周条（这正是第一版横屏只剩一行日期的原因）。
    static func displayedWeeks(inMonth month: Date, ws: String) -> [WeekDays] {
        var rows = weeks(inMonth: month, ws: ws)
        // 明确写成从尾部逐个判断的循环：`dropLast(where:)` 与 `dropLast(_:)` 的
        // 重载在这里容易让编译器选错，反而报「Int 不接受闭包」。
        while rows.count > 1 {
            guard let last = rows.last else { break }
            let hasThisMonth = last.days.contains {
                DateUtil.calendar.isDate($0, equalTo: month, toGranularity: .month)
            }
            if hasThisMonth { break }
            rows.removeLast()
        }
        return rows
    }

    /// `displayedWeeks(inMonth:ws:)` 的行数，**O(1)** 算出来。
    ///
    /// 连续月历流（`MonthFlowLayout`）要为 1900–2100 共 2400 个月建前缀偏移，
    /// 每个月都去展开一次周数组（6×7 次 `isDate`）会拖慢首次布局；行数只取决于
    /// 「1 号是星期几 + 这个月几天」：`ceil((前导天数 + 当月天数) / 7)`，而最后一格
    /// 一定含当月的一天，所以不会有需要裁掉的空尾行 —— 与 `displayedWeeks` 等价
    /// （由 `MonthFlowLayoutTests` 在 1900–2100 的每个月上守住）。
    static func displayedWeekCount(inMonth month: Date, ws: String) -> Int {
        let lead = DateUtil.weekdayIndex(DateUtil.monthFirst(month), weekStart: ws)
        let days = DateUtil.calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return max(1, Int((Double(lead + days) / 7.0).rounded(.up)))
    }

    static func weeks(inMonth month: Date, ws: String) -> [WeekDays] {
        let key = (DateUtil.calendar.component(.year, from: month) * 100 + DateUtil.calendar.component(.month, from: month)) * 2 + (ws == "sunday" ? 1 : 0)
        lock.lock()
        if let cached = weeksCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let cal = DateUtil.calendar
        let first = DateUtil.monthFirst(month)
        let start = weekStart(of: first, ws: ws)
        let result = (0..<6).map { i in
            let s = cal.date(byAdding: .day, value: i * 7, to: start) ?? start
            return WeekDays(start: s, days: (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: s) })
        }
        lock.lock()
        weeksCache[key] = result
        lock.unlock()
        return result
    }

    static func weekOf(_ date: Date, ws: String) -> WeekDays {
        let start = weekStart(of: date, ws: ws)
        let cal = DateUtil.calendar
        return WeekDays(start: start, days: (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) })
    }
}
