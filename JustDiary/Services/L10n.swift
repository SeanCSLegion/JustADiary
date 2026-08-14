import Foundation
import SwiftUI

enum AppLanguage {
    static var current: String {
        let mode = SettingsStore.load().appLanguage
        if mode == "zh" { return "zh-Hans" }
        if mode == "en" { return "en" }
        return Locale.preferredLanguages.first ?? "zh-Hans"
    }

    static var locale: Locale {
        Locale(identifier: current)
    }

    static var isZh: Bool {
        current.lowercased().hasPrefix("zh")
    }
}

enum L10n {
    static func str(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: AppLanguage.locale)
    }

    static func fmt(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        let format = String(localized: key, locale: AppLanguage.locale)
        return String(format: format, arguments: args)
    }

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = AppLanguage.locale
        cal.timeZone = .current
        return cal
    }()

    static func weekdayShort(_ weekdayIndex: Int) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.indices.contains(weekdayIndex) else { return "" }
        return symbols[weekdayIndex]
    }

    static func weekdayName(_ weekdayIndex: Int) -> String {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.indices.contains(weekdayIndex) else { return "" }
        return symbols[weekdayIndex]
    }

    static func weekdayNames(weekStart: String) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let base = weekStart == "sunday" ? 0 : 1
        return (0..<7).map { symbols[(base + $0) % 7] }
    }

    static func monthName(_ month: Int) -> String {
        let symbols = calendar.shortMonthSymbols
        guard symbols.indices.contains(month - 1) else { return "" }
        return symbols[month - 1]
    }

    static func dayTitle(_ date: Date) -> String {
        let cal = DateUtil.calendar
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let wd = cal.component(.weekday, from: date)
        return fmt("date_day_title", monthName(month), day, weekdayName(wd - 1))
    }

    static func dateOnly(_ date: Date) -> String {
        let cal = DateUtil.calendar
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        return fmt("date_day_only", monthName(month), day)
    }

    static func dateRange(_ from: Date, _ to: Date) -> String {
        "\(dateOnly(from)) ~ \(dateOnly(to))"
    }

    private static let monthFullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = "MMMM"
        return f
    }()

    static func monthFull(_ date: Date) -> String {
        monthFullFormatter.string(from: date)
    }

    static func weekHeaderTitle(_ date: Date) -> String {
        let cal = DateUtil.calendar
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let wd = cal.component(.weekday, from: date)
        return fmt("index_week_head", y, monthName(m), d, weekdayName(wd - 1))
    }

    static func formatDayKey(_ dayKey: String) -> String {
        guard let date = DateUtil.parseDayKey(dayKey) else { return dayKey }
        return dayTitle(date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = "HH:mm"
        return f
    }()

    static func timeOf(_ utcMs: Int64) -> String {
        timeFormatter.string(from: Date(timeIntervalSince1970: Double(utcMs) / 1000))
    }

    static func startLine(_ timeMs: Int64, locText: String) -> String {
        let time = timeOf(timeMs)
        if locText.isEmpty {
            return fmt("read_start_time", time)
        }
        return fmt("read_start_time_loc", time, locText)
    }

    static func dayStartLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return fmt("time_label_midnight")
        case 1..<6: return fmt("time_label_dawn", hour)
        case 6..<12: return fmt("time_label_morning", hour)
        case 12: return fmt("time_label_noon")
        case 13..<18: return fmt("time_label_afternoon", hour)
        default: return fmt("time_label_evening", hour)
        }
    }

    static func precisionLabel(_ precision: String) -> String {
        switch precision {
        case LocPrecision.exact: return str("loc_precision_exact")
        case LocPrecision.street: return str("loc_precision_street")
        case LocPrecision.district: return str("loc_precision_district")
        case LocPrecision.city: return str("loc_precision_city")
        case LocPrecision.province: return str("loc_precision_province")
        default: return ""
        }
    }
}
