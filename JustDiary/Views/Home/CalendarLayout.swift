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
/// 放不下六周格时自动降级为「周条」，这样内容永远不会被压扁。
enum CalendarDensity: Equatable {
    /// 六周格 + 农历行。
    case month(lunar: Bool)
    /// 只剩一行的周条（横向翻周）。
    case weekStrip

    /// 带农历行时每行至少这么高，才放得下 20pt 日号 + 11pt 农历 + 选中圆。
    static let lunarRowHeight: CGFloat = 44

    /// **不带**农历行时每行至少这么高：只剩日号与选中圆。
    ///
    /// 比 44 低是有意的：iPhone SE 横屏只有 375pt 高，扣掉顶部留白、标题/星期栏
    /// 与底部系统浮条（64pt）后，六行只剩 ~40pt。若这里坚持 44，SE 横屏会被降级成
    /// 周条 —— 左右分栏的左栏就只剩一行日期，横屏首页等于没有月历。
    /// 40pt 的格子放 ~14pt 日号 + ~32pt 选中圆仍然宽裕（日号字号本来也由格高推导）。
    static let dayRowHeight: CGFloat = 38

    /// 本密度下每行的最小高度（低于它就必须降级）。
    var minimumRowHeight: CGFloat {
        switch self {
        case .month(lunar: true): return Self.lunarRowHeight
        case .month(lunar: false): return Self.dayRowHeight
        case .weekStrip: return Self.dayRowHeight
        }
    }

    /// 每行实际分到的高度。
    ///
    /// 可用高度平均分给 `rows` 行，**向下取整** —— 向上取整会让网格比日历区还高，
    /// 最后一行被裁掉；但不低于本密度的下限。
    func rowHeight(availableHeight: CGFloat, rows: Int) -> CGFloat {
        guard rows > 0 else { return minimumRowHeight }
        return max(minimumRowHeight, (availableHeight / CGFloat(rows)).rounded(.down))
    }

    /// 由可用高度与**实际需要画的行数**决定密度。
    ///
    /// - Parameters:
    ///   - availableHeight: 日历区可用高度（不含标题/星期栏/底部预留）。
    ///   - rows: 实际行数（见 `CalendarLayout.displayedWeeks`，不要传固定的 6）。
    ///   - wantsLunar: 是否希望显示农历行。
    static func resolve(availableHeight: CGFloat, rows: Int, wantsLunar: Bool,
                        typeSize: CGFloat = 1) -> CalendarDensity {
        let needed = max(1, rows)
        // 行高随可用高度分配，并夹在 [最小行高, 舒适上限]：
        // 扣掉农历行需要的空间后，剩下的每行还不到最小行高，才放弃农历。
        //
        // 这里**向下取整**，与 `rowHeight(availableHeight:rows:)` 保持一致：
        // 若这里向上取整，会出现「判定说放得下、实际每行却高出 1pt」的组合，
        // 网格于是比日历区高，最后一行被裁掉半行。
        let perRow = (availableHeight / CGFloat(needed)).rounded(.down)
        if perRow >= lunarRowHeight + 16 {
            return .month(lunar: wantsLunar)
        }
        if perRow >= dayRowHeight {
            return .month(lunar: false)
        }
        return .weekStrip
    }

    var isWeekStrip: Bool {
        if case .weekStrip = self { return true }
        return false
    }

    var showsLunar: Bool {
        if case .month(let lunar) = self { return lunar }
        return false
    }

    /// 需要绘制的行数。
    func rows(monthWeeks: Int) -> Int {
        isWeekStrip ? 1 : monthWeeks
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
}

struct DayMetrics {
    var cellW: CGFloat
    var cellH: CGFloat
    var dayFont: CGFloat
    var lunarFont: CGFloat
    var lunarAlpha: Double
    var dividerAlpha: Double

    static func lerp(_ a: DayMetrics, _ b: DayMetrics, _ t: Double) -> DayMetrics {
        DayMetrics(cellW: CL.lerp(a.cellW, b.cellW, t),
                   cellH: CL.lerp(a.cellH, b.cellH, t),
                   dayFont: CL.lerp(a.dayFont, b.dayFont, t),
                   lunarFont: CL.lerp(a.lunarFont, b.lunarFont, t),
                   lunarAlpha: CL.lerp(a.lunarAlpha, b.lunarAlpha, t),
                   dividerAlpha: CL.lerp(a.dividerAlpha, b.dividerAlpha, t))
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

    static func yearCardSize(in size: CGSize) -> CGSize {
        CGSize(width: (size.width - yearPad * 2 - yearSpacing * 2) / 3,
               height: (size.height - yearTitleH - 8 - yearSpacing * 3) / 4)
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
                      y: yearTitleH + 8 + row * (card.height + yearSpacing),
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
                          dividerAlpha: 0)
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

    static func weekRowIndex(of date: Date, in month: Date, ws: String) -> Int {
        let day = DateUtil.calendar.component(.day, from: date)
        let lead = DateUtil.weekdayIndex(DateUtil.monthFirst(month), weekStart: ws)
        return (lead + day - 1) / 7
    }
}
