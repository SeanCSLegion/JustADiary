import Foundation
import SwiftUI

enum CalendarMode {
    case year
    case month
    case week
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
    static var morphAnimation: Animation { .easeInOut(duration: morphDuration) }

    // 月↔周滑动切换：无回弹的速度连续曲线——起步带速度、减速集中在尾部、
    // 精确停在终点（无弹簧过冲/回弹），日期行与内容区共用同一曲线
    static var morphSlideAnimation: Animation {
        .timingCurve(0.2, 0.75, 0.3, 1.0, duration: morphDuration)
    }

    static let weekdayHeaderH: CGFloat = 30
    static let bigTitleH: CGFloat = 72
    static let weekStripH: CGFloat = 68
    static let dayTitleH: CGFloat = 76

    static let yearTitleH: CGFloat = 62
    static let yearPad: CGFloat = 16
    static let yearSpacing: CGFloat = 10

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
    static let miniTitleH: CGFloat = 16

    static func miniGridRect(month: Int, in size: CGSize) -> CGRect {
        let card = yearCardRect(month: month, in: size)
        return CGRect(x: card.minX + miniPad,
                      y: card.minY + miniPad + miniTitleH,
                      width: card.width - miniPad * 2,
                      height: card.height - miniPad * 2 - miniTitleH)
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
